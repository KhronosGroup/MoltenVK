#!/bin/bash

# Creates a universal XCFramework for a product from any libraries that can be found for the product.
#
# Takes 2 parameters:
#   1 - product_name
#   2 - lib_type (either "library" or "framework")
#
# Requires the variables MVK_XCFWK_STAGING_DIR and MVK_XCFWK_DEST_DIR.

function create_xcframework() {
	prod_name=${1}
	lib_type=${2}
	has_content=""

	prod_file="lib${prod_name}.a"
	if [[ "${lib_type}" == "framework" ]]; then
		prod_file="${prod_name}.framework"
	fi

	xcfwk_path="${MVK_XCFWK_DEST_DIR}/${prod_name}.xcframework"
	hdr_path="${MVK_XCFWK_STAGING_DIR}/Headers/${prod_name}"

	xcfwk_cmd="xcodebuild -quiet -create-xcframework -output \"${xcfwk_path}\""

	# For each platform directory in the staging directory, add the library to the
	# XCFramework if it exists, and for each library, add headers if they exist.
	for prod_staging_dir in "${MVK_XCFWK_STAGING_DIR}/${CONFIGURATION}"/*; do
		prod_lib_path="${prod_staging_dir}/${prod_file}"
		if [[ -e "${prod_lib_path}" ]]; then
			xcfwk_cmd+=" -${lib_type} \"${prod_lib_path}\""
#			if [[ -e "${hdr_path}" ]]; then
#				xcfwk_cmd+=" -headers \"${hdr_path}\""		# Headers currently break build due to Xcode 12 ProcessXCFramework bug: https://developer.apple.com/forums/thread/651043?answerId=628400022#628400022
#			fi
			has_content="Y"
		fi
	done

	if [ "$has_content" != "" ]; then
		mkdir -p "${MVK_XCFWK_DEST_DIR}"
		rm -rf "${xcfwk_path}"
		eval "${xcfwk_cmd}"
	fi
}
