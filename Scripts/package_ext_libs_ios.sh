#!/bin/bash

export MVK_OS="iOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}-iphoneos"

"${SRCROOT}/Scripts/package_ext_libs.sh"

