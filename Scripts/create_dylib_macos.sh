#!/bin/bash

set -e

export MVK_OS_CLANG="macosx"
export MVK_UX_FWK="AppKit"
export MVK_MIN_OS_VERSION=${MACOSX_DEPLOYMENT_TARGET}
export MVK_IOSURFACE_FWK="-framework IOSurface"
export MVK_IOKIT_FWK="-framework IOKit"

. "${SRCROOT}/../Scripts/create_dylib.sh"
