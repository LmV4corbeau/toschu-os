#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib.sh"
require_yq
YQ=/tmp/yq
REPO_ROOT="${TOSCHU_REPO_ROOT:-$SCRIPT_DIR}"
CONFIG="${TOSCHU_DISTROBOX_CONFIG:-$REPO_ROOT/config/distrobox.yml}"
MANIFEST="${TOSCHU_DISTROBOX_MANIFEST:-/etc/distrobox/toschu.ini}"
PREFIX="ghcr.io/lmv4corbeau/toschu-os-distrobox/"

fail() {
  echo "invalid distrobox.yml: $*" >&2
  exit 1
}

[ -f "$CONFIG" ] || fail "missing $CONFIG"

while IFS= read -r key; do
  case "$key" in
    images | containers) ;;
    *) fail "unknown key '$key'" ;;
  esac
done < <("$YQ" -r 'keys // [] | .[]' "$CONFIG")

[ "$("$YQ" -r '.images // {} | type' "$CONFIG")" = "!!map" ] ||
  fail "images must be a mapping"
[ "$("$YQ" -r '.containers // {} | type' "$CONFIG")" = "!!map" ] ||
  fail "containers must be a mapping"

# Validate image definitions. The GitHub Actions matrix performs the same
# checks before building, but the bootc build must fail on a broken manifest too.
declare -A seen_refs=()
while IFS= read -r name; do
  [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "invalid image name '$name'"
  [ "$("$YQ" -r ".images[\"$name\"] | type" "$CONFIG")" = "!!map" ] ||
    fail "images.$name must be a mapping"

  context=$("$YQ" -r ".images[\"$name\"].context // \"\"" "$CONFIG")
  [[ "$context" =~ ^distrobox/[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] ||
    fail "images.$name.context must be a path under distrobox/"
  [[ "/$context/" != *"/../"* ]] ||
    fail "images.$name.context must not contain '..'"
  [ -f "$REPO_ROOT/$context/Containerfile" ] ||
    fail "images.$name.context must contain a Containerfile"

  ref=$("$YQ" -r ".images[\"$name\"].ref // \"\"" "$CONFIG")
  [[ "$ref" =~ ^ghcr\.io/lmv4corbeau/toschu-os-distrobox/[a-z0-9][a-z0-9._-]*:[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] ||
    fail "images.$name.ref must be a tagged ghcr.io/lmv4corbeau/toschu-os-distrobox/ reference"
  [[ "$ref" == "$PREFIX$name:"* ]] ||
    fail "images.$name.ref must use the image name '$name'"
  [ -z "${seen_refs[$ref]:-}" ] || fail "duplicate image ref '$ref'"
  seen_refs[$ref]=1

  base=$("$YQ" -r ".images[\"$name\"].base // \"\"" "$CONFIG")
  [[ "$base" =~ ^[^[:space:]@]+:[^@[:space:]]+@sha256:[0-9a-f]{64}$ ]] ||
    fail "images.$name.base must be a tagged image pinned by sha256 digest"

  [ "$("$YQ" -r ".images[\"$name\"].platforms // [] | type" "$CONFIG")" = "!!seq" ] ||
    fail "images.$name.platforms must be a list"
  platform_count=$("$YQ" -r ".images[\"$name\"].platforms // [] | length" "$CONFIG")
  [ "$platform_count" -gt 0 ] || fail "images.$name.platforms must not be empty"
  for ((p = 0; p < platform_count; p++)); do
    platform=$("$YQ" -r ".images[\"$name\"].platforms[$p] // \"\"" "$CONFIG")
    case "$platform" in
      linux/amd64 | linux/arm64) ;;
      *) fail "images.$name.platforms[$p] must be linux/amd64 or linux/arm64" ;;
    esac
  done

  [ "$("$YQ" -r ".images[\"$name\"].packages // [] | type" "$CONFIG")" = "!!seq" ] ||
    fail "images.$name.packages must be a list"
  package_count=$("$YQ" -r ".images[\"$name\"].packages // [] | length" "$CONFIG")
  for ((p = 0; p < package_count; p++)); do
    package=$("$YQ" -r ".images[\"$name\"].packages[$p] // \"\"" "$CONFIG")
    [[ "$package" =~ ^[A-Za-z0-9][A-Za-z0-9._+:-]*$ ]] ||
      fail "images.$name.packages[$p] contains an invalid package name"
  done
done < <("$YQ" -r '.images // {} | keys | .[]' "$CONFIG")

# Validate container definitions.
while IFS= read -r name; do
  [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "invalid container name '$name'"
  [ "$("$YQ" -r ".containers[\"$name\"] | type" "$CONFIG")" = "!!map" ] ||
    fail "containers.$name must be a mapping"

  image=$("$YQ" -r ".containers[\"$name\"].image // \"\"" "$CONFIG")
  [ -n "$image" ] || fail "containers.$name.image is required"
  [[ "$image" =~ ^[A-Za-z0-9][A-Za-z0-9._/:@-]*$ ]] ||
    fail "containers.$name.image contains invalid characters"
  if ! "$YQ" -e ".images[\"$image\"]" "$CONFIG" >/dev/null 2>&1; then
    [[ "$image" == */* || "$image" == *:* ]] ||
      fail "containers.$name.image must be an image key or a full image reference"
  fi

  for field in pull nvidia init replace; do
    value=$("$YQ" -r ".containers[\"$name\"].$field // false" "$CONFIG")
    case "$value" in
      true | false) ;;
      *) fail "containers.$name.$field must be true or false" ;;
    esac
  done

  for field in exported_apps exported_bins; do
    [ "$("$YQ" -r ".containers[\"$name\"].${field} // [] | type" "$CONFIG")" = "!!seq" ] ||
      fail "containers.$name.${field} must be a list"
    count=$("$YQ" -r ".containers[\"$name\"].$field // [] | length" "$CONFIG")
    for ((i = 0; i < count; i++)); do
      item=$("$YQ" -r ".containers[\"$name\"].${field}[$i] // \"\"" "$CONFIG")
      [[ "$item" =~ ^[A-Za-z0-9._/~+@:%-]+$ ]] ||
        fail "containers.$name.${field}[$i] contains invalid characters"
    done
  done
done < <("$YQ" -r '.containers // {} | keys | .[]' "$CONFIG")

# Generate the Distrobox assemble manifest. Bazzite's own
# /etc/distrobox/distrobox.ini is left untouched.
mkdir -p "$(dirname "$MANIFEST")"
tmp="${MANIFEST}.tmp"

{
  echo "# Generated by build_files/install-distrobox.sh. Do not edit."
  echo "# Source: config/distrobox.yml"
  echo

  while IFS= read -r name; do
    image=$("$YQ" -r ".containers[\"$name\"].image // \"\"" "$CONFIG")
    if "$YQ" -e ".images[\"$image\"]" "$CONFIG" >/dev/null 2>&1; then
      resolved=$("$YQ" -r ".images[\"$image\"].ref" "$CONFIG")
    else
      resolved=$image
    fi

    printf '[%s]\n' "$name"
    printf 'image=%s\n' "$resolved"
    for field in pull nvidia init replace; do
      value=$("$YQ" -r ".containers[\"$name\"].$field // false" "$CONFIG")
      printf '%s=%s\n' "$field" "$value"
    done
    for field in exported_apps exported_bins; do
      count=$("$YQ" -r ".containers[\"$name\"].$field // [] | length" "$CONFIG")
      if [ "$count" -gt 0 ]; then
        values=()
        for ((i = 0; i < count; i++)); do
          values+=("$("$YQ" -r ".containers[\"$name\"].${field}[$i] // \"\"" "$CONFIG")")
        done
        printf '%s="%s"\n' "$field" "${values[*]}"
      fi
    done
    echo
  done < <("$YQ" -r '.containers // {} | keys | .[]' "$CONFIG")
} > "$tmp"

mv "$tmp" "$MANIFEST"
chmod 0644 "$MANIFEST"

echo "wrote $MANIFEST"
