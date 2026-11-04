#!/bin/bash
set -euo pipefail

# shellcheck source=/dev/null
source /ctx/lib.sh
require_yq
YQ=/tmp/yq
CONFIG=/ctx/config/apps.yml

if [ ! -f "$CONFIG" ]; then
  echo "missing $CONFIG" >&2
  exit 1
fi

while IFS= read -r key; do
  case "$key" in
    flatpak | appimage) ;;
    *)
      echo "unknown key in apps.yml: $key" >&2
      exit 1
      ;;
  esac
done < <("$YQ" -r 'keys // [] | .[]' "$CONFIG")

flatpak_remote=$("$YQ" -r '.flatpak.remote // "flathub"' "$CONFIG")
flatpak_url=$("$YQ" -r '.flatpak.url // "https://flathub.org/repo/flathub.flatpakrepo"' "$CONFIG")
flatpak_count=$("$YQ" -r '.flatpak.apps // [] | length' "$CONFIG")

if [ "$flatpak_count" -gt 0 ]; then
  flatpak remote-add --if-not-exists --system "$flatpak_remote" "$flatpak_url"
  for ((i = 0; i < flatpak_count; i++)); do
    app=$("$YQ" -r ".flatpak.apps[$i] // \"\"" "$CONFIG")
    if [ -z "$app" ]; then
      echo "invalid flatpak.apps[$i]" >&2
      exit 1
    fi
    flatpak install --system -y "$flatpak_remote" "$app"
  done
fi

appimage_count=$("$YQ" -r '.appimage // [] | length' "$CONFIG")
for ((i = 0; i < appimage_count; i++)); do
  name=$("$YQ" -r ".appimage[$i].name // \"\"" "$CONFIG")
  version=$("$YQ" -r ".appimage[$i].version // \"\"" "$CONFIG")
  url=$("$YQ" -r ".appimage[$i].url // \"\"" "$CONFIG")
  sha256=$("$YQ" -r ".appimage[$i].sha256 // \"\"" "$CONFIG")

  if [ -z "$name" ] || [ -z "$version" ] || [ -z "$url" ] || [ -z "$sha256" ]; then
    echo "invalid appimage[$i]: name, version, url, and sha256 are required" >&2
    exit 1
  fi

  if ! [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "invalid AppImage name: $name" >&2
    exit 1
  fi

  url=${url//\{\{version\}\}/$version}
  dest="/usr/bin/$name"
  tmp="${dest}.tmp"
  curl -fsSL -o "$tmp" "$url"
  printf '%s  %s\n' "$sha256" "$tmp" | sha256sum -c -
  chmod +x "$tmp"
  mv "$tmp" "$dest"
done
