#!/bin/bash

set -e

# We don't support dylib for Mac Catalyst yet
if [ "${IS_MACCATALYST}" == "YES" ]; then
	exit 0
fi

export MVK_OS_CLANG="ios"
export MVK_UX_FWK="UIKit"
export MVK_MIN_OS_VERSION=${IPHONEOS_DEPLOYMENT_TARGET}
export MVK_IOSURFACE_FWK="-framework IOSurface"
export MVK_IOKIT_FWK="-framework IOKit"

# Do not link to IOSurface if deploying to iOS versions below 11.0, doing so will
# link IOSurface as a private framework, which will trigger App Store rejection.
if [ $(echo "${MVK_MIN_OS_VERSION} < 11.0" | bc) -eq 1 ]; then
	MVK_IOSURFACE_FWK=""
fi

. "${SRCROOT}/../Scripts/create_dylib.sh"
