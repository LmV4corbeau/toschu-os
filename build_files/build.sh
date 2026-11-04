#!/bin/bash

set -euxo pipefail

# Copy files from system_files/ into the image root.
cp -avf "/ctx/system_files"/. /

# Add packages here. Bazzite is Fedora-based and ships dnf5.
# RPM Fusion is already enabled in the Universal Blue base images.
dnf5 install -y tmux

# Example: enable a systemd unit.
# systemctl enable podman.socket

# Example COPR: enable, install, then disable so it is not left enabled.
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# dnf5 -y copr disable ublue-os/staging
