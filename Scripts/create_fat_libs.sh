#!/bin/bash

# Load functions
. "${SRCROOT}/../Scripts/create_fat_lib_func.sh"

set -e

#Static library
export MVK_BUILT_OS_PROD_DIR="${BUILT_PRODUCTS_DIR}/../${CONFIGURATION}-${MVK_OS_PROD_EXTN}"
export MVK_BUILT_SIM_PROD_DIR="${BUILT_PRODUCTS_DIR}/../${CONFIGURATION}-${MVK_SIM_PROD_EXTN}"
export MVK_BUILT_FAT_PROD_DIR="${BUILT_PRODUCTS_DIR}/../${CONFIGURATION}-${MVK_OS}"
create_fat_lib "lib${PRODUCT_NAME}.a"

# Dynamic library
export MVK_BUILT_OS_PROD_DIR="${MVK_BUILT_OS_PROD_DIR}/dynamic"
export MVK_BUILT_SIM_PROD_DIR="${MVK_BUILT_SIM_PROD_DIR}/dynamic"
export MVK_BUILT_FAT_PROD_DIR="${MVK_BUILT_FAT_PROD_DIR}/dynamic"
create_fat_lib "lib${PRODUCT_NAME}.dylib"

# Dynamic library dSYM
if [ "${CONFIGURATION}" == "Debug" ]; then
	cp -a  "${MVK_BUILT_OS_PROD_DIR}/lib${PRODUCT_NAME}.dylib.dSYM" "${MVK_BUILT_FAT_PROD_DIR}"
	export MVK_BUILT_OS_PROD_DIR="${MVK_BUILT_OS_PROD_DIR}/lib${PRODUCT_NAME}.dylib.dSYM/Contents/Resources/DWARF"
	export MVK_BUILT_SIM_PROD_DIR="${MVK_BUILT_SIM_PROD_DIR}/lib${PRODUCT_NAME}.dylib.dSYM/Contents/Resources/DWARF"
	export MVK_BUILT_FAT_PROD_DIR="${MVK_BUILT_FAT_PROD_DIR}/lib${PRODUCT_NAME}.dylib.dSYM/Contents/Resources/DWARF"
	create_fat_lib "lib${PRODUCT_NAME}.dylib"
fi
