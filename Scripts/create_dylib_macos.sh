#!/bin/bash

set -e

export MVK_OS="macosx"
export MVK_UX_FWK="AppKit"
export MVK_MIN_OS_VERSION=${MACOSX_DEPLOYMENT_TARGET}
export MVK_IOSURFACE_FWK="-framework IOSurface"

#Suppress visibility warning spam when linking Debug to SPIRV-Cross Release
if test "$CONFIGURATION" = Debug; then
	export MVK_LINK_WARN="-Xlinker -w"
fi

. "${SRCROOT}/../Scripts/create_dylib.sh"
