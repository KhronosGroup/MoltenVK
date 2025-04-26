#!/bin/bash

if [ "${SKIP_PACKAGING}" = "Y" ]; then exit 0; fi

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
ln -sfn "${abs_ext_dir}/SPIRVTools" "${hdr_dir}/SPIRVTools"

create_xcframework "SPIRVCross" "library"
create_xcframework "SPIRVTools" "library"
