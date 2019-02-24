#!/bin/bash

set -e

export MVK_EXT_LIB_DST_DIR="External"
export MVK_EXT_LIB_DST_OS_PATH="${PROJECT_DIR}/${MVK_EXT_LIB_DST_DIR}/build/${MVK_OS}"

rm -rf "${MVK_EXT_LIB_DST_OS_PATH}"
mkdir -p "${MVK_EXT_LIB_DST_OS_PATH}"

cp -a "${MVK_BUILT_PROD_PATH}/"*.a "${MVK_EXT_LIB_DST_OS_PATH}"

# Clean MoltenVK to ensure the next MoltenVK build will use the latest external library versions.
make --quiet clean

