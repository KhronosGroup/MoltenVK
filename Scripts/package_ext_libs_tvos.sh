#!/bin/bash

export MVK_OS="tvOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}-appletvos"

"${SRCROOT}/Scripts/package_ext_libs.sh"

