#!/bin/bash

export MVK_OS="macOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}"

"${SRCROOT}/Scripts/package_moltenvk.sh"
"${SRCROOT}/Scripts/package_shader_converter.sh"
"${SRCROOT}/Scripts/package_shader_converter_tool.sh"
"${SRCROOT}/Scripts/package_docs.sh"
"${SRCROOT}/Scripts/package_update_latest.sh"

