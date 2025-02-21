#!/bin/bash

set -e

. "${PROJECT_DIR}/Scripts/create_xcframework_func.sh"

prod_name="MoltenVKShaderConverter"
export MVK_XCFWK_STAGING_DIR="${BUILD_DIR}/XCFrameworkStaging"
export MVK_XCFWK_DEST_DIR="${PROJECT_DIR}/Package/${CONFIGURATION}/${prod_name}"

# Assemble the headers for the shader frameworks
hdr_dir="${MVK_XCFWK_STAGING_DIR}/Headers"
mkdir -p "${hdr_dir}"
rm -rf "${hdr_dir}/${prod_name}"
cp -pRL "${PROJECT_DIR}/${prod_name}/include/${prod_name}" "${hdr_dir}"

# Also copy headers to an include directory in the package.
# This will not be needed once the XCFramework can be created with a Headers directory.
mkdir -p "${MVK_XCFWK_DEST_DIR}"
cp -pRL "${PROJECT_DIR}/${prod_name}/include/" "${MVK_XCFWK_DEST_DIR}/include"

create_xcframework "${prod_name}" "library"
