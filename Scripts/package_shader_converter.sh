#!/bin/bash

set -e

export MVK_PROD_BASE_NAME="MoltenVKShaderConverter"
export MVK_PKG_CONFIG_BASE_PATH="${PROJECT_DIR}/Package/${CONFIGURATION}/${MVK_PROD_BASE_NAME}"

#-----------------------------------
# MoltenVKGLSLToSPIRVConverter
export MVK_PROD_NAME="MoltenVKGLSLToSPIRVConverter"
export MVK_PKG_PROD_PATH_OS="${MVK_PKG_CONFIG_BASE_PATH}/${MVK_PROD_NAME}/${MVK_OS}"

rm -rf "${MVK_PKG_PROD_PATH_OS}"
mkdir -p "${MVK_PKG_PROD_PATH_OS}"
cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework" "${MVK_PKG_PROD_PATH_OS}"
rm -rf "${MVK_PKG_PROD_PATH_OS}/${MVK_PROD_NAME}.framework/_CodeSignature"

#-----------------------------------
# MoltenVKSPIRVToMSLConverter
export MVK_PROD_NAME="MoltenVKSPIRVToMSLConverter"
export MVK_PKG_PROD_PATH_OS="${MVK_PKG_CONFIG_BASE_PATH}/${MVK_PROD_NAME}/${MVK_OS}"

rm -rf "${MVK_PKG_PROD_PATH_OS}"
mkdir -p "${MVK_PKG_PROD_PATH_OS}"
cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework" "${MVK_PKG_PROD_PATH_OS}"
rm -rf "${MVK_PKG_PROD_PATH_OS}/${MVK_PROD_NAME}.framework/_CodeSignature"
