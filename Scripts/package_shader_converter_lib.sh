#!/bin/bash

set -e

export MVK_PROD_PROJ_PATH="${PROJECT_DIR}/${MVK_PROD_BASE_NAME}/${MVK_PROD_NAME}"
export MVK_PKG_PROD_PATH="${MVK_PKG_BASE_PATH}/${MVK_PROD_NAME}"
export MVK_PKG_PROD_PATH_OS="${MVK_PKG_PROD_PATH}/${MVK_OS}"

rm -rf "${MVK_PKG_PROD_PATH_OS}"

mkdir -p "${MVK_PKG_PROD_PATH_OS}/static"
cp -a "${MVK_BUILT_PROD_PATH}/lib${MVK_PROD_NAME}.a" "${MVK_PKG_PROD_PATH_OS}/static"

mkdir -p "${MVK_PKG_PROD_PATH_OS}/dynamic"
cp -a "${MVK_BUILT_PROD_PATH}/dynamic/lib${MVK_PROD_NAME}.dylib" "${MVK_PKG_PROD_PATH_OS}/dynamic"
if test "$CONFIGURATION" = Debug; then
    cp -a "${MVK_BUILT_PROD_PATH}/dynamic/lib${MVK_PROD_NAME}.dylib.dSYM" "${MVK_PKG_PROD_PATH_OS}/dynamic"
fi

mkdir -p "${MVK_PKG_PROD_PATH_OS}/framework"
cp -a "${MVK_BUILT_PROD_PATH}/framework/${MVK_PROD_NAME}.framework" "${MVK_PKG_PROD_PATH_OS}/framework"
