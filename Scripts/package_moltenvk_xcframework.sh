#!/bin/bash

set -e

. "${PROJECT_DIR}/Scripts/create_xcframework_func.sh"

export MVK_PROD_BASE_NAME="MoltenVK"
export MVK_XCFWK_STAGING_DIR="${BUILD_DIR}/XCFrameworkStaging"
export MVK_XCFWK_DEST_DIR="${PROJECT_DIR}/Package/${CONFIGURATION}/${MVK_PROD_BASE_NAME}"

# Assemble the headers
hdr_dir="${MVK_XCFWK_STAGING_DIR}/Headers"
mkdir -p "${hdr_dir}"
rm -rf "${hdr_dir}/${MVK_PROD_BASE_NAME}"
cp -pRL "${PROJECT_DIR}/${MVK_PROD_BASE_NAME}/include/${MVK_PROD_BASE_NAME}" "${hdr_dir}"

create_xcframework "MoltenVK"
