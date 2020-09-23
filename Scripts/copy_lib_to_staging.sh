#!/bin/bash

# Copy the static library file to its own directory within the XCFrameworkStaging directory.
#
# Requires the variable MVK_XCFWK_STAGING_DIR.
#
export MVK_PROD_FILENAME="lib${PRODUCT_NAME}.a"
export MVK_BUILT_PROD_FILE="${BUILT_PRODUCTS_DIR}/${MVK_PROD_FILENAME}"

staging_dir="${MVK_XCFWK_STAGING_DIR}/Platform${EFFECTIVE_PLATFORM_NAME}"
mkdir -p "${staging_dir}"
cp -a "${MVK_BUILT_PROD_FILE}" "${staging_dir}/${MVK_PROD_FILENAME}"
