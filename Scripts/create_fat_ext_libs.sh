#!/bin/bash

# Load functions
. "${SRCROOT}/Scripts/create_fat_lib_func.sh"

set -e

export MVK_BUILT_OS_PROD_DIR="${BUILT_PRODUCTS_DIR}-${MVK_OS_PROD_EXTN}"
export MVK_BUILT_SIM_PROD_DIR="${BUILT_PRODUCTS_DIR}-${MVK_SIM_PROD_EXTN}"
export MVK_BUILT_FAT_PROD_DIR="${BUILT_PRODUCTS_DIR}-${MVK_OS}"

create_fat_lib "libSPIRVCross.a"
create_fat_lib "libSPIRVTools.a"
create_fat_lib "libglslang.a"

