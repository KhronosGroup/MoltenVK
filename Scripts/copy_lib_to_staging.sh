#!/bin/bash

# Copy the static library file to its own directory within the XCFrameworkStaging directory.
# and mark the XCFrameworkStaging directory as changed, to trigger packaging dependencies.
#
# Takes 2 parameters:
#   1 - prod_file_name
#   2 - xcfwk_dst_dir, destiation directory in which to create XCFramework

prod_file_name=${1}
xcfwk_dst_dir=${2}
built_prod_file="${BUILT_PRODUCTS_DIR}/${prod_file_name}"
staging_dir="${xcfwk_dst_dir}/XCFrameworkStaging/${CONFIGURATION}/Platform${EFFECTIVE_PLATFORM_NAME}"

mkdir -p "${staging_dir}"
cp -a "${built_prod_file}" "${staging_dir}/"
touch "${staging_dir}/.."
