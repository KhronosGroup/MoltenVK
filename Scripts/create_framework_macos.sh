#!/bin/bash

set -e

export MVK_OS="macOS"
export MVK_FRWK_SUBPATH="Versions/Current/"

. "${SRCROOT}/../Scripts/create_framework.sh"

ln -sfn "${MVK_FRWK_SUBPATH}${PRODUCT_NAME}" "${MVK_BUILT_FRWK_PATH}/${PRODUCT_NAME}"
