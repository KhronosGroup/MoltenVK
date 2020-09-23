#!/bin/bash

set -e

. "${PROJECT_DIR}/Scripts/create_xcframework_func.sh"

export MVK_PROD_BASE_NAME="MoltenVKShaderConverter"
export MVK_XCFWK_STAGING_DIR="${BUILD_DIR}/XCFrameworkStaging"
export MVK_XCFWK_DEST_DIR="${PROJECT_DIR}/Package/${CONFIGURATION}/${MVK_PROD_BASE_NAME}"

# Assemble the headers for the shader frameworks
hdr_dir="${MVK_XCFWK_STAGING_DIR}/Headers"
mkdir -p "${hdr_dir}"
rm -rf "${hdr_dir}/MoltenVKShaderConverter"
cp -pRL "${PROJECT_DIR}/${MVK_PROD_BASE_NAME}/include/MoltenVKShaderConverter" "${hdr_dir}"

# Also copy headers to an include directory in the package.
# This will not be needed once the XCFramework can be created with a Headers directory.
mkdir -p "${MVK_XCFWK_DEST_DIR}"
cp -pRL "${PROJECT_DIR}/${MVK_PROD_BASE_NAME}/include/" "${MVK_XCFWK_DEST_DIR}/include"

create_xcframework "MoltenVKShaderConverter"
