#!/bin/bash

set -e

export MVK_PROD_NAME="MoltenVK"
export MVK_DYLIB_NAME="lib${MVK_PROD_NAME}.dylib"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}"
export MVK_SYS_FWK_DIR="${SDK_DIR}/System/Library/Frameworks"
export MVK_USR_LIB_DIR="${SDK_DIR}/usr/lib"

# Do not link to IOSurface if deploying to iOS versions below 11.0, doing so will
# link IOSurface as a private framework, which will trigger App Store rejection.
if [ $(echo "${IPHONEOS_DEPLOYMENT_TARGET} >= 11.0" | bc) -eq 1 ]
then
    export MVK_IOSURFACE_FWK="-framework IOSurface"
else
    export MVK_IOSURFACE_FWK=""
fi

clang \
-dynamiclib \
-arch arm64 \
-mios-version-min=${IPHONEOS_DEPLOYMENT_TARGET}  \
-compatibility_version 1.0.0 -current_version 1.0.0  \
-install_name "@rpath/${MVK_DYLIB_NAME}"  \
-Wno-incompatible-sysroot \
-isysroot ${SDK_DIR} \
-iframework ${MVK_SYS_FWK_DIR}  \
-framework Metal ${MVK_IOSURFACE_FWK} -framework UIKit -framework QuartzCore -framework Foundation \
--library-directory ${MVK_USR_LIB_DIR} \
-lSystem  -lc++ \
-o "${MVK_BUILT_PROD_PATH}/${MVK_DYLIB_NAME}" \
-force_load "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework/${MVK_PROD_NAME}"
