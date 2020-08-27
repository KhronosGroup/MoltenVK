#!/bin/bash

export MVK_BUILT_PROD_DIR="${BUILT_PRODUCTS_DIR}"

export MVK_OS="iOS"
. "${SRCROOT}/Scripts/package_moltenvk.sh"

export MVK_OS="tvOS"
. "${SRCROOT}/Scripts/package_moltenvk.sh"

export MVK_OS="macOS"
. "${SRCROOT}/Scripts/package_moltenvk.sh"

. "${SRCROOT}/Scripts/package_shader_converter.sh"
. "${SRCROOT}/Scripts/package_shader_converter_tool.sh"
. "${SRCROOT}/Scripts/package_docs.sh"
. "${SRCROOT}/Scripts/package_update_latest.sh"

