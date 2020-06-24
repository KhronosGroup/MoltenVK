#!/bin/bash

set -e

export MVK_OS="iOS"
export MVK_BUILT_PROD_DIR="${BUILT_PRODUCTS_DIR}/../${CONFIGURATION}-${MVK_OS}"
export MVK_FRWK_SUBPATH=""

. "${SRCROOT}/../Scripts/create_framework.sh"
