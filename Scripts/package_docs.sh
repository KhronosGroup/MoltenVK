#!/bin/bash

set -e

# Package folder
export MVK_PKG_CONFIG_PATH="${PROJECT_DIR}/Package/${CONFIGURATION}"

# Copy the docs.
cp -a "${PROJECT_DIR}/Docs" "${MVK_PKG_CONFIG_PATH}"
cp -a "${PROJECT_DIR}/LICENSE" "${MVK_PKG_CONFIG_PATH}"
