#!/bin/bash

set -e

export MVK_DYLIB_NAME="lib${PRODUCT_NAME}.dylib"
export MVK_SYS_FWK_DIR="${SDK_DIR}/System/Library/Frameworks"
export MVK_USR_LIB_DIR="${SDK_DIR}/usr/lib"

if test x"${ENABLE_THREAD_SANITIZER}" = xYES; then
	MVK_TSAN="-fsanitize=thread"
fi

clang++ \
-dynamiclib ${MVK_TSAN} \
-arch ${MVK_ARCH} \
-m${MVK_OS}-version-min=${MVK_MIN_OS_VERSION} \
-compatibility_version 1.0.0 -current_version 1.0.0  \
-install_name "@rpath/${MVK_DYLIB_NAME}"  \
-Wno-incompatible-sysroot \
-isysroot ${SDK_DIR} \
-iframework ${MVK_SYS_FWK_DIR}  \
-framework Metal ${MVK_IOSURFACE_FWK} -framework ${MVK_UX_FWK} -framework QuartzCore -framework IOKit -framework Foundation \
--library-directory ${MVK_USR_LIB_DIR} \
-lSystem \
-o "${BUILT_PRODUCTS_DIR}/${MVK_DYLIB_NAME}" \
-force_load "${BUILT_PRODUCTS_DIR}/lib${PRODUCT_NAME}.a"
