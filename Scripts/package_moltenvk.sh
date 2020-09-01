#!/bin/bash

set -e

# Copy dylibs only if the source directory exists.
# Takes two args: source build path OS suffix and destination path OS directory name
function copy_dylib() {
	src_dir="${BUILD_DIR}/${CONFIGURATION}${1}/dynamic"
	dst_dir="${MVK_PKG_PROD_PATH}/dylib/${2}"

echo Copying dylib from "${src_dir}" to "${dst_dir}"

	if [[ -e "${src_dir}" ]]; then
		rm -rf "${dst_dir}"
		mkdir -p "${dst_dir}"

		cp -a "${src_dir}/lib${MVK_PROD_NAME}.dylib" "${dst_dir}"

		if [[ -e "${src_dir}/lib${MVK_PROD_NAME}.dylib.dSYM" ]]; then
		   cp -a "${src_dir}/lib${MVK_PROD_NAME}.dylib.dSYM" "${dst_dir}"
		fi

		cp -a "${MVK_PROD_PROJ_PATH}/icd/${MVK_PROD_NAME}_icd.json" "${dst_dir}"
	fi
}

export MVK_PROD_NAME="MoltenVK"
export MVK_PROD_PROJ_PATH="${PROJECT_DIR}/${MVK_PROD_NAME}"
export MVK_PKG_PROD_PATH="${PROJECT_DIR}/Package/${CONFIGURATION}/${MVK_PROD_NAME}"

copy_dylib "" "macOS"
copy_dylib "-iphoneos" "iOS"
copy_dylib "-iphonesimulator" "iOS-simulator"
copy_dylib "-appletvos" "tvOS"
copy_dylib "-appletvsimulator" "tvOS-simulator"

# Remove and replace header include folder
rm -rf "${MVK_PKG_PROD_PATH}/include"
cp -pRL "${MVK_PROD_PROJ_PATH}/include" "${MVK_PKG_PROD_PATH}"
