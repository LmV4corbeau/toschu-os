#!/bin/bash

set -euxo pipefail

# Copy files from system_files/ into the image root.
cp -avf "/ctx/system_files"/. /

# Install pinned DNF packages and AppImages from config/.
bash /ctx/install-tools.sh
bash /ctx/install-apps.sh

# Validate config/distrobox.yml and write /etc/distrobox/toschu.ini.
bash /ctx/install-distrobox.sh

# Do not leave the build-time YAML parser in the final image.
rm -f /tmp/yq
