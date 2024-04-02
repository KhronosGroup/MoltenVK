#!/bin/bash

# Delete the dynamic components, to force them to be rebuilt.
# This, combined with forcing the Scheme to run sequentially, and building 
# the dynamic framework before the dylib, avoids a problem where the dynamic 
# components contain no static content after an incremental build.

rm -rf "${BUILT_PRODUCTS_DIR}/MoltenVK.framework"
rm -rf "${BUILT_PRODUCTS_DIR}/libMoltenVK.dylib"
