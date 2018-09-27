#!/bin/bash

set -e

export MVK_PROD_NAME="MoltenVK"
export MVK_DYLIB_NAME="lib${MVK_PROD_NAME}.dylib"
export MVK_BUILT_PROD_PATH="${BUILT_PRODUCTS_DIR}"
export MVK_SYS_FWK_DIR="${SDK_DIR}/System/Library/Frameworks"
export MVK_USR_LIB_DIR="${SDK_DIR}/usr/lib"

if test x"${ENABLE_THREAD_SANITIZER}" = xYES; then
	MVK_TSAN="-fsanitize=thread"
fi

clang \
-dynamiclib ${MVK_TSAN} \
-arch x86_64 \
-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} \
-compatibility_version 1.0.0 -current_version 1.0.0  \
-install_name "@rpath/${MVK_DYLIB_NAME}"  \
-Wno-incompatible-sysroot \
-isysroot ${SDK_DIR} \
-iframework ${MVK_SYS_FWK_DIR}  \
-framework Metal -framework IOSurface -framework IOKit -framework QuartzCore -framework AppKit -framework Foundation \
--library-directory ${MVK_USR_LIB_DIR} \
-lSystem  -lc++ \
-o "${MVK_BUILT_PROD_PATH}/${MVK_DYLIB_NAME}" \
-force_load "${MVK_BUILT_PROD_PATH}/${MVK_PROD_NAME}.framework/${MVK_PROD_NAME}"
