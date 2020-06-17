#!/bin/bash

set -e

# If both platform and simulator lib files exist, create a fat file
# from them both, otherwise if only one exists, copy it to the fat file.
function create_fat_lib() {
	export MVK_BUILT_OS_PROD_FILE="${MVK_BUILT_OS_PROD_DIR}/lib${MVK_PROD_NAME}.a"
	export MVK_BUILT_SIM_PROD_FILE="${MVK_BUILT_SIM_PROD_DIR}/lib${MVK_PROD_NAME}.a"
	export MVK_BUILT_FAT_PROD_FILE="${MVK_BUILT_FAT_PROD_DIR}/lib${MVK_PROD_NAME}.a"

	if test -f "${MVK_BUILT_OS_PROD_FILE}"; then
		if test -f "${MVK_BUILT_SIM_PROD_FILE}"; then
			lipo \
			-create \
			-output "${MVK_BUILT_FAT_PROD_FILE}" \
			"${MVK_BUILT_OS_PROD_FILE}" \
			"${MVK_BUILT_SIM_PROD_FILE}"
		else
			cp -a "${MVK_BUILT_OS_PROD_FILE}" "${MVK_BUILT_FAT_PROD_FILE}"
		fi
	elif test -f "${MVK_BUILT_SIM_PROD_FILE}"; then
		cp -a "${MVK_BUILT_SIM_PROD_FILE}" "${MVK_BUILT_FAT_PROD_FILE}"
	fi
}

export MVK_BUILT_OS_PROD_DIR="${BUILT_PRODUCTS_DIR}-${MVK_OS_PROD_EXTN}"
export MVK_BUILT_SIM_PROD_DIR="${BUILT_PRODUCTS_DIR}-${MVK_SIM_PROD_EXTN}"
export MVK_BUILT_FAT_PROD_DIR="${BUILT_PRODUCTS_DIR}-${MVK_OS}"

rm -rf "${MVK_BUILT_FAT_PROD_DIR}"
mkdir -p "${MVK_BUILT_FAT_PROD_DIR}"

export MVK_PROD_NAME="SPIRVCross"
create_fat_lib

export MVK_PROD_NAME="SPIRVTools"
create_fat_lib

export MVK_PROD_NAME="glslang"
create_fat_lib

