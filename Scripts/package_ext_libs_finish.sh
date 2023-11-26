#!/bin/bash

if [ "${SKIP_PACKAGING}" = "Y" ]; then exit 0; fi

set -e

export MVK_EXT_LIB_DST_PATH="${PROJECT_DIR}/External/build/"

# Assign symlink to Latest
ln -sfn "${CONFIGURATION}" "${MVK_EXT_LIB_DST_PATH}/Latest"

# Remove the large Intermediates directory if no longer needed
if [ "${KEEP_CACHE}" != "Y" ]; then
	echo Removing Intermediates library at "${MVK_EXT_LIB_DST_PATH}/Intermediates"
	rm -rf "${MVK_EXT_LIB_DST_PATH}/Intermediates"
fi

# Clean MoltenVK to ensure the next MoltenVK build will use the latest external library versions.
make --quiet clean

