#!/bin/bash

set -e

export MVK_UX_FWK="UIKit"
export MVK_MIN_OS_VERSION=${XROS_DEPLOYMENT_TARGET}
export MVK_CLANG_OS_MIN_VERSION="" #"-mxros-version-min=${MVK_MIN_OS_VERSION}"
export MVK_IOSURFACE_FWK="-framework IOSurface"
export MVK_IOKIT_FWK="-framework IOKit"

. "${SRCROOT}/../Scripts/create_dylib.sh"
