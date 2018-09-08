#!/bin/bash

set -e

# Package folder
export MVK_PROD_NAME="MoltenVK"
export MVK_DYLIB_NAME="lib${MVK_PROD_NAME}.dylib"
export MVK_ICD_NAME="${MVK_PROD_NAME}_icd.json"
export MVK_WKSPC_PATH="${PROJECT_DIR}"
export MVK_PROD_PROJ_PATH="${MVK_WKSPC_PATH}/${MVK_PROD_NAME}"
export MVK_PKG_LOCN="${MVK_WKSPC_PATH}/Package"
export MVK_PKG_CONFIG_PATH="${MVK_PKG_LOCN}/${CONFIGURATION}"
export MVK_PKG_PROD_PATH="${MVK_PKG_CONFIG_PATH}/${MVK_PROD_NAME}"

# Remove the product folder
rm -rf "${MVK_PKG_PROD_PATH}"

# Remove and replace the existing macOS framework folder and copy framework into it
export MVK_OS_PROD_PATH="${MVK_PKG_PROD_PATH}/macOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}"
rm -rf "${MVK_OS_PROD_PATH}"
if [ -e "${MVK_BUILT_PROD_PATH}" ]; then
	mkdir -p "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework" "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_BUILT_PROD_PATH}/${MVK_DYLIB_NAME}" "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_PROD_PROJ_PATH}/icd/${MVK_ICD_NAME}" "${MVK_OS_PROD_PATH}"
fi

# Remove and replace the existing iOS framework folder and copy framework into it
export MVK_OS_PROD_PATH="${MVK_PKG_PROD_PATH}/iOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}-iphoneos"
rm -rf "${MVK_OS_PROD_PATH}"
echo MVK_BUILT_PROD_PATH = "${MVK_BUILT_PROD_PATH}"
if [ -e "${MVK_BUILT_PROD_PATH}" ]; then
	rm -rf "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework/_CodeSignature"
	mkdir -p "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework" "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_BUILT_PROD_PATH}/${MVK_DYLIB_NAME}" "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_PROD_PROJ_PATH}/icd/${MVK_ICD_NAME}" "${MVK_OS_PROD_PATH}"
fi
# Remove and replace header include folder
rm -rf "${MVK_PKG_PROD_PATH}/include"
cp -pRL "${MVK_PROD_PROJ_PATH}/include" "${MVK_PKG_PROD_PATH}"
