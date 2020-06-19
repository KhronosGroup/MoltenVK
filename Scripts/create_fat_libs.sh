#!/bin/bash

# Load functions
. "${SRCROOT}/../Scripts/create_fat_lib_func.sh"

set -e

#Static library
export MVK_BUILT_OS_PROD_DIR="${BUILT_PRODUCTS_DIR}/../${CONFIGURATION}-${MVK_OS_PROD_EXTN}"
export MVK_BUILT_SIM_PROD_DIR="${BUILT_PRODUCTS_DIR}/../${CONFIGURATION}-${MVK_SIM_PROD_EXTN}"
export MVK_BUILT_FAT_PROD_DIR="${BUILT_PRODUCTS_DIR}/../${CONFIGURATION}-${MVK_OS}"

create_fat_lib "lib${PRODUCT_NAME}.a"

# Dynamic library and associated dSYM
export MVK_BUILT_OS_PROD_DIR="${MVK_BUILT_OS_PROD_DIR}/dynamic"
export MVK_BUILT_SIM_PROD_DIR="${MVK_BUILT_SIM_PROD_DIR}/dynamic"
export MVK_BUILT_FAT_PROD_DIR="${MVK_BUILT_FAT_PROD_DIR}/dynamic"

create_fat_lib "lib${PRODUCT_NAME}.dylib"
create_fat_lib "lib${PRODUCT_NAME}.dylib.dSYM"

