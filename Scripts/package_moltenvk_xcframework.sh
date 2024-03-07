#!/bin/bash

set -e

. "${PROJECT_DIR}/Scripts/create_xcframework_func.sh"

prod_name="MoltenVK"
export MVK_XCFWK_STAGING_DIR="${BUILD_DIR}/XCFrameworkStaging"

# Assemble the headers
hdr_dir="${MVK_XCFWK_STAGING_DIR}/Headers"
mkdir -p "${hdr_dir}"
rm -rf "${hdr_dir}/${prod_name}"
cp -pRL "${PROJECT_DIR}/${prod_name}/include/${prod_name}" "${hdr_dir}"

export MVK_XCFWK_DEST_DIR="${PROJECT_DIR}/Package/${CONFIGURATION}/${prod_name}/static"
create_xcframework "${prod_name}" "library"

export MVK_XCFWK_DEST_DIR="${PROJECT_DIR}/Package/${CONFIGURATION}/${prod_name}/dynamic"
create_xcframework "${prod_name}" "framework"
