#!/bin/bash

export MVK_OS="tvOS"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}-appletvos"

. "${SRCROOT}/Scripts/package_moltenvk.sh"
. "${SRCROOT}/Scripts/package_shader_converter.sh"
. "${SRCROOT}/Scripts/package_docs.sh"
. "${SRCROOT}/Scripts/package_update_latest.sh"

