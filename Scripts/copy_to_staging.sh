#!/bin/bash

# Copy the static library file to its own directory within the XCFrameworkStaging directory.
# and mark the XCFrameworkStaging directory as changed, to trigger packaging dependencies.
#
# Takes 1 parameter:
#   1 - prod_file_name

prod_file_name=${1}
. "${SRCROOT}/../Scripts/copy_lib_to_staging.sh" ${prod_file_name} "${BUILD_DIR}"
