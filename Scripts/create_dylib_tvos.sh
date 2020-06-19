#!/bin/bash

set -e

export MVK_OS="tvos"
export MVK_UX_FWK="UIKit"
export MVK_MIN_OS_VERSION=${TVOS_DEPLOYMENT_TARGET}
export MVK_IOSURFACE_FWK="-framework IOSurface"
export MVK_IOKIT_FWK=""

. "${SRCROOT}/../Scripts/create_dylib.sh"
