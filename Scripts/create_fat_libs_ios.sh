#!/bin/bash

set -e

export MVK_OS="iOS"
export MVK_OS_PROD_EXTN="iphoneos"
export MVK_SIM_PROD_EXTN="iphonesimulator"

. "${SRCROOT}/../Scripts/create_fat_libs.sh"

