#!/bin/bash

# If both platform and simulator lib files exist, create a fat file
# from them both, otherwise if only one exists, copy it to the fat file.
#
# Takes one parameter:
#   1 - filename
#
# Requires 3 build settings:
#   MVK_BUILT_OS_PROD_DIR  - location to find OS input file
#   MVK_BUILT_SIM_PROD_DIR - location to find simulator input file
#   MVK_BUILT_FAT_PROD_DIR - location to put fat output file
function create_fat_lib() {
	FILE_NAME=${1}
	BUILT_OS_PROD_FILE="${MVK_BUILT_OS_PROD_DIR}/${FILE_NAME}"
	BUILT_SIM_PROD_FILE="${MVK_BUILT_SIM_PROD_DIR}/${FILE_NAME}"
	BUILT_FAT_PROD_FILE="${MVK_BUILT_FAT_PROD_DIR}/${FILE_NAME}"

	if [ ! -e "${MVK_BUILT_FAT_PROD_DIR}" ]; then
		mkdir -p "${MVK_BUILT_FAT_PROD_DIR}"
	fi
	rm -rf "${BUILT_FAT_PROD_FILE}"

	if test -e "${BUILT_OS_PROD_FILE}"; then
		if test -e "${BUILT_SIM_PROD_FILE}"; then
			lipo \
			-create \
			-output "${BUILT_FAT_PROD_FILE}" \
			"${BUILT_OS_PROD_FILE}" \
			"${BUILT_SIM_PROD_FILE}"
		else
			cp -a "${BUILT_OS_PROD_FILE}" "${BUILT_FAT_PROD_FILE}"
		fi
	elif test -e "${BUILT_SIM_PROD_FILE}"; then
		cp -a "${BUILT_SIM_PROD_FILE}" "${BUILT_FAT_PROD_FILE}"
	fi
}
