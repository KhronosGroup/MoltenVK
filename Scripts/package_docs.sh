#!/bin/bash

set -e

# Package folder
export MVK_WKSPC_PATH="${PROJECT_DIR}"
export MVK_PKG_LOCN="${MVK_WKSPC_PATH}/Package"
export MVK_PKG_CONFIG_PATH="${MVK_PKG_LOCN}/${CONFIGURATION}"

# Copy the docs. Allow silent fail if a symlinked doc is not built.
cp -a "${MVK_WKSPC_PATH}/LICENSE" "${MVK_PKG_CONFIG_PATH}"
cp -pRLf "${MVK_WKSPC_PATH}/Docs" "${MVK_PKG_CONFIG_PATH}" 2> /dev/null || true
