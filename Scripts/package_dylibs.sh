#!/bin/bash

set -e

# Copy dylibs only if the source file exists.
#
# Takes 2 parameters:
#   1 - source build path OS suffix (aka EFFECTIVE_PLATFORM_NAME during build)
#   2 - destination path OS directory name

function copy_dylib() {
	file_name="lib${mvk_prod_name}.dylib"
	src_dir="${BUILT_PRODUCTS_DIR}"
	src_file="${src_dir}/${file_name}"
	dst_dir="${mvk_pkg_prod_path}/dynamic/dylib/${2}"

	# If dylib file exists, copy it, any debug symbol file, and the Vulkan layer JSON file
	if [[ -e "${src_file}" ]]; then
		rm -rf "${dst_dir}"
		mkdir -p "${dst_dir}"

		cp -p "${src_file}" "${dst_dir}/"

		src_file+=".dSYM"
		if [[ -e "${src_file}" ]]; then
		   cp -a "${src_file}" "${dst_dir}/"
		fi

		cp -a "${mvk_prod_proj_path}/icd/${mvk_prod_name}_icd.json" "${dst_dir}"
	fi
}

mvk_prod_name="MoltenVK"
mvk_prod_proj_path="${PROJECT_DIR}/${mvk_prod_name}"
mvk_pkg_prod_path="${PROJECT_DIR}/Package/${CONFIGURATION}/${mvk_prod_name}"

# Make sure directory is there
mkdir -p "${mvk_pkg_prod_path}"

# App store distribution does not support naked dylibs, so only include a naked dylib for macOS.
copy_dylib "" "macOS"
#copy_dylib "-iphoneos" "iOS"
#copy_dylib "-iphonesimulator" "iOS-simulator"
#copy_dylib "-appletvos" "tvOS"
#copy_dylib "-appletvsimulator" "tvOS-simulator"
#copy_dylib "-xrvos" "xrOS"
#copy_dylib "-xrsimulator" "xrOS-simulator"

# For legacy support, symlink old dylib location to new location
ln -sfn "dynamic/dylib" "${mvk_pkg_prod_path}/dylib"

