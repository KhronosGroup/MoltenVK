#!/bin/bash

set -e

export MVK_PROD_NAME="MoltenVKShaderConverter"
export MVK_PKG_PROD_PATH_OS="${PROJECT_DIR}/Package/${CONFIGURATION}/${MVK_PROD_NAME}/Tools"
export MVK_BUILT_PROD_DIR="${BUILT_PRODUCTS_DIR}"

rm -rf "${MVK_PKG_PROD_PATH_OS}"
mkdir -p "${MVK_PKG_PROD_PATH_OS}"
cp -a "${MVK_BUILT_PROD_DIR}/${MVK_PROD_NAME}" "${MVK_PKG_PROD_PATH_OS}"
