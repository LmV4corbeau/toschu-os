#!/bin/bash
# Shared helpers for build-time scripts.

YQ_VERSION="v4.54.1"
YQ_SHA256_AMD64="8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f"
YQ_SHA256_ARM64="189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b"

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
