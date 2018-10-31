#!/bin/bash

set -e

# Package folder
export MVK_PKG_PATH="${PROJECT_DIR}/Package"

# Assign symlink to Latest
ln -sfn "${MVK_PKG_PATH}/${CONFIGURATION}" "${MVK_PKG_PATH}/Latest"
