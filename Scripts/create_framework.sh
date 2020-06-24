#!/bin/bash

set -e

export MVK_TMPLT_PATH="${PROJECT_DIR}/../Templates/framework/${MVK_OS}"
export MVK_BUILT_FRWK_PATH="${MVK_BUILT_PROD_DIR}/framework/${PRODUCT_NAME}.framework"
export MVK_BUILT_FRWK_CONTENT_PATH="${MVK_BUILT_FRWK_PATH}/${MVK_FRWK_SUBPATH}"

mkdir -p "${MVK_BUILT_PROD_DIR}/framework"

rm -rf "${MVK_BUILT_FRWK_PATH}"
cp -a  "${MVK_TMPLT_PATH}/Template.framework" "${MVK_BUILT_FRWK_PATH}"
cp -a  "${MVK_BUILT_PROD_DIR}/lib${PRODUCT_NAME}.a" "${MVK_BUILT_FRWK_CONTENT_PATH}${PRODUCT_NAME}"
cp -pRL "${PROJECT_DIR}/include/${PRODUCT_NAME}/" "${MVK_BUILT_FRWK_CONTENT_PATH}Headers"
rm -f "${MVK_BUILT_FRWK_CONTENT_PATH}Headers/README"	#Remove git empty directory placeholder file
