#!/bin/bash

set -e

# Copy dylibs only if the source file exists.
#
# Takes 2 parameters:
#   1 - source build path OS suffix (aka EFFECTIVE_PLATFORM_NAME during build)
#   2 - destination path OS directory name

function copy_dylib() {
	src_dir="${BUILD_DIR}/XCFrameworkStaging/${CONFIGURATION}/Platform${1}/${MVK_PROD_NAME}.framework"
	src_file_name="${MVK_PROD_NAME}"
	dst_dir="${MVK_PKG_PROD_PATH}/dynamic/dylib/${2}"
	dst_file_name="lib${MVK_PROD_NAME}.dylib"

	# If dylib file exists, copy it, any debug symbol file, and the Vulkan layer JSON file
	src_file="${src_dir}/${src_file_name}"

	if [[ -e "${src_file}" ]]; then
		rm -rf "${dst_dir}"
		mkdir -p "${dst_dir}"

		cp -p "${src_file}" "${dst_dir}/${dst_file_name}"
		install_name_tool -id "@rpath/${dst_file_name}" "${dst_dir}/${dst_file_name}"

		src_file+=".dSYM"
		if [[ -e "${src_file}" ]]; then
		   cp -a "${src_file}" "${dst_dir}/${dst_file_name}.dSYM"
		fi

		cp -a "${MVK_PROD_PROJ_PATH}/icd/${MVK_PROD_NAME}_icd.json" "${dst_dir}"
	fi
}

export MVK_PROD_NAME="MoltenVK"
export MVK_PROD_PROJ_PATH="${PROJECT_DIR}/${MVK_PROD_NAME}"
export MVK_PKG_PROD_PATH="${PROJECT_DIR}/Package/${CONFIGURATION}/${MVK_PROD_NAME}"

# Make sure directory is there in case no dylibs are created for this platform
mkdir -p "${MVK_PKG_PROD_PATH}"

# App store distribution does not support naked dylibs, so only include a naked dylib for macOS.
copy_dylib "" "macOS"
#copy_dylib "-iphoneos" "iOS"
#copy_dylib "-iphonesimulator" "iOS-simulator"
#copy_dylib "-appletvos" "tvOS"
#copy_dylib "-appletvsimulator" "tvOS-simulator"
#copy_dylib "-xrvos" "xrOS"
#copy_dylib "-xrsimulator" "xrOS-simulator"

# Remove and replace header include folder
rm -rf "${MVK_PKG_PROD_PATH}/include"
cp -pRL "${MVK_PROD_PROJ_PATH}/include" "${MVK_PKG_PROD_PATH}"
