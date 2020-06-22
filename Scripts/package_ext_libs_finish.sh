#!/bin/bash

set -e

export MVK_EXT_LIB_DST_PATH="${PROJECT_DIR}/External/build/"

# Assign symlink to Latest
ln -sfn "${CONFIGURATION}" "${MVK_EXT_LIB_DST_PATH}/Latest"

# Clean MoltenVK to ensure the next MoltenVK build will use the latest external library versions.
make --quiet clean

