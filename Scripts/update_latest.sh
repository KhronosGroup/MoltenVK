#!/bin/bash

set -e

# Package folder
export MVK_WKSPC_LOCN="${PROJECT_DIR}"
export MVK_PKG_LOCN="${MVK_WKSPC_LOCN}/Package"

# Configuration package folder location
export MVK_PKG_CONFIG_LOCN="${CONFIGURATION}"
export MVK_PKG_LATEST_LOCN="Latest"

# Assign symlink from Latest
ln -sfn "${MVK_PKG_LOCN}/${MVK_PKG_CONFIG_LOCN}" "${MVK_PKG_LOCN}/${MVK_PKG_LATEST_LOCN}"
