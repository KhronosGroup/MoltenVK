#!/bin/bash

set -e

# Package folder
export MVK_PROD_BASE_NAME="MoltenVKShaderConverter"
export MVK_WKSPC_PATH="${PROJECT_DIR}"
export MVK_PKG_LOCN="${MVK_WKSPC_PATH}/Package"

# Remove the base product folder
rm -rf "${MVK_PKG_LOCN}/${CONFIGURATION}/${MVK_PROD_BASE_NAME}"

#-----------------------------------
# MoltenVKGLSLToSPIRVConverter
export MVK_PROD_NAME="MoltenVKGLSLToSPIRVConverter"
export MVK_PKG_CONFIG_PATH="${MVK_PKG_LOCN}/${CONFIGURATION}/${MVK_PROD_BASE_NAME}/${MVK_PROD_NAME}"

# Remove and replace the existing macOS framework folder and copy framework into it
export MVK_OS_PROD_PATH="${MVK_PKG_CONFIG_PATH}/macOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}"
rm -rf "${MVK_OS_PROD_PATH}"
if [ -e "${MVK_BUILT_PROD_PATH}" ]; then
	mkdir -p "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework" "${MVK_OS_PROD_PATH}"
fi

# Remove and replace the existing iOS framework folder and copy framework into it
export MVK_OS_PROD_PATH="${MVK_PKG_CONFIG_PATH}/iOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}-iphoneos"
rm -rf "${MVK_OS_PROD_PATH}"
if [ -e "${MVK_BUILT_PROD_PATH}" ]; then
	rm -rf "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework/_CodeSignature"
	mkdir -p "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework" "${MVK_OS_PROD_PATH}"
fi

#-----------------------------------
# MoltenVKSPIRVToMSLConverter
export MVK_PROD_NAME="MoltenVKSPIRVToMSLConverter"
export MVK_PKG_CONFIG_PATH="${MVK_PKG_LOCN}/${CONFIGURATION}/${MVK_PROD_BASE_NAME}/${MVK_PROD_NAME}"

# Remove and replace the existing macOS framework folder and copy framework into it
export MVK_OS_PROD_PATH="${MVK_PKG_CONFIG_PATH}/macOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}"
rm -rf "${MVK_OS_PROD_PATH}"
if [ -e "${MVK_BUILT_PROD_PATH}" ]; then
	mkdir -p "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework" "${MVK_OS_PROD_PATH}"
fi

# Remove and replace the existing iOS framework folder and copy framework into it
export MVK_OS_PROD_PATH="${MVK_PKG_CONFIG_PATH}/iOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}-iphoneos"
rm -rf "${MVK_OS_PROD_PATH}"
if [ -e "${MVK_BUILT_PROD_PATH}" ]; then
	rm -rf "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework/_CodeSignature"
	mkdir -p "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework" "${MVK_OS_PROD_PATH}"
fi

#-----------------------------------
# MoltenVKShaderConverter Tool
export MVK_PROD_NAME="MoltenVKShaderConverter"
export MVK_PKG_CONFIG_PATH="${MVK_PKG_LOCN}/${CONFIGURATION}/${MVK_PROD_BASE_NAME}"

# Remove and replace the existing macOS framework folder and copy framework into it
export MVK_OS_PROD_PATH="${MVK_PKG_CONFIG_PATH}/Tools"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}"
rm -rf "${MVK_OS_PROD_PATH}"
if [ -e "${MVK_BUILT_PROD_PATH}" ]; then
	mkdir -p "${MVK_OS_PROD_PATH}"
	cp -a "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}" "${MVK_OS_PROD_PATH}"
fi
