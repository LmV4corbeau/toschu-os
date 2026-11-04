#!/bin/bash

set -euxo pipefail

# Copy files from system_files/ into the image root.
cp -avf "/ctx/system_files"/. /

# Install pinned DNF packages and AppImages from config/.
bash /ctx/install-tools.sh
bash /ctx/install-apps.sh

# Do not leave the build-time YAML parser in the final image.
rm -f /tmp/yq
