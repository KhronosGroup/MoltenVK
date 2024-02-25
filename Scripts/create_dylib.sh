#!/bin/bash

# Allow dylib building to be skipped based on build setting.
# For example, skipping the build of a dylib for tvOS Simulator builds
# because Xcode cannot currently handle creating a tvOS Simulator dylib
# containing both x86_64 and arm64 (Apple Silicon) architectures.
if [ "${MVK_SKIP_DYLIB}" == "YES" ]; then
	exit 0
fi

MVK_BUILT_PROD_DIR="${BUILT_PRODUCTS_DIR}"
MVK_DYLIB_NAME="lib${PRODUCT_NAME}.dylib"
MVK_SYS_FWK_DIR="${SDK_DIR}/System/Library/Frameworks"
MVK_USR_LIB_DIR="${SDK_DIR}/usr/lib"
MVK_DYN_FWK="${MVK_BUILT_PROD_DIR}/dynamic/${PRODUCT_NAME}.framework"

# Copy the dynamic framework template
if [[ "${EFFECTIVE_PLATFORM_NAME}" == "" ]]; then
	tmplt_sfx="-macOS"
	dyn_fwk_sub_path="Versions/A/"
else
	tmplt_sfx=""
	dyn_fwk_sub_path=""
fi
cp -a "${PROJECT_DIR}/../Templates/Framework/Template${tmplt_sfx}.framework" "${MVK_DYN_FWK}"
#mkdir -p "${MVK_DYN_FWK}"

export MVK_EMBED_BITCODE=""
if test x"${ENABLE_BITCODE}" == xYES; then
	if test x"${BITCODE_GENERATION_MODE}" == xbitcode; then
		MVK_EMBED_BITCODE="-fembed-bitcode"
	else
		MVK_EMBED_BITCODE="-fembed-bitcode-marker"
	fi
fi

if test x"${ENABLE_THREAD_SANITIZER}" = xYES; then
	MVK_SAN="-fsanitize=thread"
elif test x"${ENABLE_ADDRESS_SANITIZER}" = xYES; then
	MVK_SAN="-fsanitize=address"
fi
if test x"${ENABLE_UNDEFINED_BEHAVIOR_SANITIZER}" = xYES; then
	if test x"$MVK_SAN" = x; then
		MVK_SAN="-fsanitize=undefined"
	else
		MVK_SAN="$MVK_SAN,undefined"
	fi
fi

# Suppress visibility warning spam when linking in Release or Debug mode
# and external libraries built in the other mode.
MVK_LINK_WARN="-Xlinker -w"

# Create the dylib and install in the dynamic framework
clang++ \
-stdlib=${CLANG_CXX_LIBRARY} \
-dynamiclib \
$(printf -- "-arch %s " ${ARCHS}) \
${MVK_CLANG_OS_MIN_VERSION} \
-compatibility_version 1.0.0 -current_version 1.0.0  \
-install_name "@rpath/${PRODUCT_NAME}.framework/${PRODUCT_NAME}" \
-Wno-incompatible-sysroot \
${MVK_EMBED_BITCODE} \
${MVK_SAN} \
${MVK_LINK_WARN} \
-isysroot ${SDK_DIR} \
-iframework ${MVK_SYS_FWK_DIR}  \
-framework Metal ${MVK_IOSURFACE_FWK} -framework ${MVK_UX_FWK} -framework QuartzCore -framework CoreGraphics ${MVK_IOKIT_FWK} -framework Foundation \
--library-directory ${MVK_USR_LIB_DIR} \
-o "${MVK_DYN_FWK}/${dyn_fwk_sub_path}${PRODUCT_NAME}" \
-force_load "${MVK_BUILT_PROD_DIR}/lib${PRODUCT_NAME}.a"

# Add a dylib linked to the framework binary
ln -sfn "${PRODUCT_NAME}" "${MVK_DYN_FWK}/${MVK_DYLIB_NAME}"

if test "$CONFIGURATION" = Debug; then
	dsymutil "${MVK_DYN_FWK}/${MVK_DYLIB_NAME}" -o "${MVK_DYN_FWK}/${MVK_DYLIB_NAME}.dSYM"
fi
