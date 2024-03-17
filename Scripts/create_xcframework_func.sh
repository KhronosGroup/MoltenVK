#!/bin/bash

# Creates a universal XCFramework for a product from any libraries that can be found for the product.
#
# Takes one parameter:
#   1 - product_name
#
# Requires the variables MVK_XCFWK_STAGING_DIR and MVK_XCFWK_DEST_DIR.
#
function create_xcframework() {
	prod_name=${1}
	xcfwk_path="${MVK_XCFWK_DEST_DIR}/${prod_name}.xcframework"
	hdr_path="${MVK_XCFWK_STAGING_DIR}/Headers/${prod_name}"

	xcfwk_cmd="xcodebuild -quiet -create-xcframework -output \"${xcfwk_path}\""

	# For each platform directory in the staging directory, add the library to the
	# XCFramework if it exists, and for each library, add headers if they exist.
	for prod_staging_dir in "${MVK_XCFWK_STAGING_DIR}/${CONFIGURATION}"/*; do
		prod_lib_path="${prod_staging_dir}/lib${prod_name}.a"
		if [[ -e "${prod_lib_path}" ]]; then
			xcfwk_cmd+=" -library \"${prod_lib_path}\""
#			if [[ -e "${hdr_path}" ]]; then
#				xcfwk_cmd+=" -headers \"${hdr_path}\""		# Headers currently break build due to Xcode 12 ProcessXCFramework bug: https://developer.apple.com/forums/thread/651043?answerId=628400022#628400022
#			fi
		fi
	done

	rm -rf "${xcfwk_path}"
	eval "${xcfwk_cmd}"
}
