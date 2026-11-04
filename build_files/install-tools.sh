#!/bin/bash
set -euo pipefail

# shellcheck source=/dev/null
source /ctx/lib.sh
require_yq
YQ=/tmp/yq
CONFIG=/ctx/config/tools.yml

if [ ! -f "$CONFIG" ]; then
  echo "missing $CONFIG" >&2
  exit 1
fi

while IFS= read -r key; do
  case "$key" in
    dnf | copr | systemd) ;;
    *)
      echo "unknown key in tools.yml: $key" >&2
      exit 1
      ;;
  esac
done < <("$YQ" -r 'keys // [] | .[]' "$CONFIG")

dnf_count=$("$YQ" -r '.dnf.packages // [] | length' "$CONFIG")
for ((i = 0; i < dnf_count; i++)); do
  name=$("$YQ" -r ".dnf.packages[$i].name // \"\"" "$CONFIG")
  version=$("$YQ" -r ".dnf.packages[$i].version // \"\"" "$CONFIG")
  repo=$("$YQ" -r ".dnf.packages[$i].repo // \"\"" "$CONFIG")

  if [ -z "$name" ] || [ -z "$version" ] || [ -z "$repo" ]; then
    echo "invalid dnf.packages[$i]: name, version, and repo are required" >&2
    exit 1
  fi

  dnf5 install -y --allow-downgrade "${name}-${version}"
done

copr_enabled=()
cleanup_copr() {
  if [ "${#copr_enabled[@]}" -gt 0 ]; then
    for repo in "${copr_enabled[@]}"; do
      dnf5 -y copr disable "$repo" || true
    done
  fi
}
trap cleanup_copr EXIT

copr_count=$("$YQ" -r '.copr // [] | length' "$CONFIG")
for ((i = 0; i < copr_count; i++)); do
  repo_name=$("$YQ" -r ".copr[$i].name // \"\"" "$CONFIG")
  if [ -z "$repo_name" ]; then
    echo "invalid copr[$i]: name is required" >&2
    exit 1
  fi

  dnf5 -y copr enable "$repo_name"
  copr_enabled+=("$repo_name")

  pkg_count=$("$YQ" -r ".copr[$i].packages // [] | length" "$CONFIG")
  for ((j = 0; j < pkg_count; j++)); do
    name=$("$YQ" -r ".copr[$i].packages[$j].name // \"\"" "$CONFIG")
    version=$("$YQ" -r ".copr[$i].packages[$j].version // \"\"" "$CONFIG")
    repo=$("$YQ" -r ".copr[$i].packages[$j].repo // \"\"" "$CONFIG")

    if [ -z "$name" ] || [ -z "$version" ] || [ -z "$repo" ]; then
      echo "invalid copr[$i].packages[$j]: name, version, and repo are required" >&2
      exit 1
    fi

    dnf5 install -y --allow-downgrade "${name}-${version}"
  done
done

while IFS= read -r unit; do
  [ -z "$unit" ] && continue
  systemctl enable "$unit"
done < <("$YQ" -r '.systemd.enable // [] | .[]' "$CONFIG")
