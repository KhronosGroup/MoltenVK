#!/bin/bash

set -e

export MVK_PROD_BASE_NAME="MoltenVKShaderConverter"
export MVK_PKG_BASE_PATH="${PROJECT_DIR}/Package/${CONFIGURATION}/${MVK_PROD_BASE_NAME}"
export MVK_PKG_INCLUDE_PATH="${MVK_PKG_BASE_PATH}/include"

# Remove and replace header include folder
rm -rf "${MVK_PKG_INCLUDE_PATH}"
mkdir -p "${MVK_PKG_INCLUDE_PATH}"
cp -pRL "${PROJECT_DIR}/${MVK_PROD_BASE_NAME}/include/" "${MVK_PKG_INCLUDE_PATH}"

#-----------------------------------
# MoltenVKSPIRVToMSLConverter
export MVK_PROD_NAME="MoltenVKSPIRVToMSLConverter"

. "${SRCROOT}/Scripts/package_shader_converter_lib.sh"

#-----------------------------------
# MoltenVKGLSLToSPIRVConverter
export MVK_PROD_NAME="MoltenVKGLSLToSPIRVConverter"

. "${SRCROOT}/Scripts/package_shader_converter_lib.sh"
