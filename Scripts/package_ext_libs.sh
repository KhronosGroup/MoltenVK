#!/bin/bash

set -e

export MVK_EXT_LIB_DST_PATH="${PROJECT_DIR}/External/build/"
export MVK_EXT_LIB_DST_OS_PATH="${MVK_EXT_LIB_DST_PATH}/${CONFIGURATION}/${MVK_OS}"

rm -rf "${MVK_EXT_LIB_DST_OS_PATH}"
mkdir -p "${MVK_EXT_LIB_DST_OS_PATH}"

cp -a "${MVK_BUILT_PROD_PATH}/"*.a "${MVK_EXT_LIB_DST_OS_PATH}"

# Assign symlink to Latest
ln -sfn "${CONFIGURATION}" "${MVK_EXT_LIB_DST_PATH}/Latest"

# Clean MoltenVK to ensure the next MoltenVK build will use the latest external library versions.
make --quiet clean

