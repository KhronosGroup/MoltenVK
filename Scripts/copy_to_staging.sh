#!/bin/bash

# Query the architectures in the built static library. If it contains only a single architecture,
# copy the file into a separate file in its own directory within the XCFrameworkStaging directory.
# If it contains mulitple architectures, extract each architecture into a separate file in its own
# directory within the XCFrameworkStaging directory.
#
# Requires the variable MVK_XCFWK_STAGING_DIR.
#
export MVK_PROD_FILENAME="lib${PRODUCT_NAME}.a"
export MVK_BUILT_PROD_FILE="${BUILT_PRODUCTS_DIR}/${MVK_PROD_FILENAME}"

IFS=' ' read -ra archs <<< $(lipo -archs "${MVK_BUILT_PROD_FILE}")
if [ ${#archs[@]} -eq '1' ]; then
	arch="${archs[0]}"
	staging_dir="${MVK_XCFWK_STAGING_DIR}/${arch}${EFFECTIVE_PLATFORM_NAME}"
	mkdir -p "${staging_dir}"
	cp -a "${MVK_BUILT_PROD_FILE}" "${staging_dir}/${MVK_PROD_FILENAME}"
else
	for arch in ${archs[@]}; do
		staging_dir="${MVK_XCFWK_STAGING_DIR}/${arch}${EFFECTIVE_PLATFORM_NAME}"
		mkdir -p "${staging_dir}"
		lipo "${MVK_BUILT_PROD_FILE}" -thin ${arch} -output "${staging_dir}/${MVK_PROD_FILENAME}"
	done
fi








