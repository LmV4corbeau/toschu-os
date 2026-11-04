#!/bin/bash
# Shared helpers for build-time scripts.

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/yq-version.env"

require_yq() {
  if [ -x /tmp/yq ]; then
    return 0
  fi

  local arch asset sha
  arch="$(uname -m)"
  case "$arch" in
    x86_64)
      asset="yq_linux_amd64"
      sha="$YQ_SHA256_AMD64"
      ;;
    aarch64 | arm64)
      asset="yq_linux_arm64"
      sha="$YQ_SHA256_ARM64"
      ;;
    *)
      echo "unsupported architecture for yq: $arch" >&2
      return 1
      ;;
  esac

  curl -fsSL -o /tmp/yq \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${asset}"
  printf '%s  %s\n' "$sha" /tmp/yq | sha256sum -c -
  chmod +x /tmp/yq
}
