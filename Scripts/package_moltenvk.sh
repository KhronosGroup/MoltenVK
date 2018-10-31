#!/bin/bash

set -e

export MVK_PROD_NAME="MoltenVK"
export MVK_PROD_PROJ_PATH="${PROJECT_DIR}/${MVK_PROD_NAME}"
export MVK_PKG_PROD_PATH="${PROJECT_DIR}/Package/${CONFIGURATION}/${MVK_PROD_NAME}"
export MVK_PKG_PROD_PATH_OS="${MVK_PKG_PROD_PATH}/${MVK_OS}"

rm -rf "${MVK_PKG_PROD_PATH_OS}"
mkdir -p "${MVK_PKG_PROD_PATH_OS}/static"
cp -a "${MVK_BUILT_PROD_PATH}/lib${MVK_PROD_NAME}.a" "${MVK_PKG_PROD_PATH_OS}/static"
mkdir -p "${MVK_PKG_PROD_PATH_OS}/dynamic"
cp -a "${MVK_BUILT_PROD_PATH}/lib${MVK_PROD_NAME}.dylib" "${MVK_PKG_PROD_PATH_OS}/dynamic"
cp -a "${MVK_PROD_PROJ_PATH}/icd/${MVK_PROD_NAME}_icd.json" "${MVK_PKG_PROD_PATH_OS}/dynamic"
mkdir -p "${MVK_PKG_PROD_PATH_OS}/framework"
cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework" "${MVK_PKG_PROD_PATH_OS}/framework"

# Remove the code signature
rm -rf "${MVK_PKG_PROD_PATH_OS}/framework/${MVK_PROD_NAME}.framework/_CodeSignature"

# Remove and replace header include folder
rm -rf "${MVK_PKG_PROD_PATH}/include"
cp -pRL "${MVK_PROD_PROJ_PATH}/include" "${MVK_PKG_PROD_PATH}"
