#!/bin/bash

set -e

# Copy dylibs only if the source directory exists.
# Takes two args: source build path OS suffix and destination path OS directory name
function copy_dylib() {
	src_dir="${BUILD_DIR}/${CONFIGURATION}${1}/dynamic"
	dst_dir="${MVK_PKG_PROD_PATH}/dylib/${2}"

	# If dylib file exists, copy it, any debug symbol file, and the Vulkan layer JSON file
	src_file="${src_dir}/lib${MVK_PROD_NAME}.dylib"
	if [[ -e "${src_file}" ]]; then
		rm -rf "${dst_dir}"
		mkdir -p "${dst_dir}"

		cp -a "${src_file}" "${dst_dir}"

		src_file+=".dSYM"
		if [[ -e "${src_file}" ]]; then
		   cp -a "${src_file}" "${dst_dir}"
		fi

		cp -a "${MVK_PROD_PROJ_PATH}/icd/${MVK_PROD_NAME}_icd.json" "${dst_dir}"

	fi
}

export MVK_PROD_NAME="MoltenVK"
export MVK_PROD_PROJ_PATH="${PROJECT_DIR}/${MVK_PROD_NAME}"
export MVK_PKG_PROD_PATH="${PROJECT_DIR}/Package/${CONFIGURATION}/${MVK_PROD_NAME}"

# Make sure directory is there in case no dylibs are created for this platform
mkdir -p "${MVK_PKG_PROD_PATH}"

copy_dylib "" "macOS"
copy_dylib "-iphoneos" "iOS"
copy_dylib "-iphonesimulator" "iOS-simulator"
copy_dylib "-appletvos" "tvOS"
copy_dylib "-appletvsimulator" "tvOS-simulator"

# Remove and replace header include folder
rm -rf "${MVK_PKG_PROD_PATH}/include"
cp -pRL "${MVK_PROD_PROJ_PATH}/include" "${MVK_PKG_PROD_PATH}"
