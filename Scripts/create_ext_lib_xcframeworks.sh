#!/bin/bash

. "${PROJECT_DIR}/Scripts/create_xcframework_func.sh"

export MVK_EXT_DIR="${PROJECT_DIR}/External"
export MVK_XCFWK_STAGING_DIR="${MVK_EXT_DIR}/build/Intermediates/XCFrameworkStaging"
export MVK_XCFWK_DEST_DIR="${MVK_EXT_DIR}/build/${CONFIGURATION}"

# Assemble the headers for the external libraries
abs_ext_dir=`cd "${MVK_EXT_DIR}"; pwd; cd - > /dev/null`
hdr_dir="${MVK_XCFWK_STAGING_DIR}/Headers"
rm -rf "${hdr_dir}"
mkdir -p "${hdr_dir}"
ln -sfn "${abs_ext_dir}/SPIRV-Cross" "${hdr_dir}/SPIRVCross"
ln -sfn "${abs_ext_dir}/glslang/External/spirv-tools/include/spirv-tools" "${hdr_dir}/SPIRVTools"
ln -sfn "${abs_ext_dir}/glslang" "${hdr_dir}/glslang"

create_xcframework "SPIRVCross"
create_xcframework "SPIRVTools"
create_xcframework "glslang"
