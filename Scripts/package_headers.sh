#!/bin/bash

set -e

mvk_prod_name="MoltenVK"
mvk_prod_proj_path="${PROJECT_DIR}/${mvk_prod_name}"
mvk_pkg_prod_path="${PROJECT_DIR}/Package/${CONFIGURATION}/${mvk_prod_name}"

# Make sure directory is there in case no dylibs are created for this platform
mkdir -p "${mvk_pkg_prod_path}"

# Remove and replace header include folder
rm -rf "${mvk_pkg_prod_path}/include"
cp -pRL "${mvk_prod_proj_path}/include" "${mvk_pkg_prod_path}/"
