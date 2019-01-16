#!/bin/bash

export MVK_OS="macOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}"

"${SRCROOT}/Scripts/package_ext_libs.sh"

