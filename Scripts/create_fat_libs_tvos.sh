#!/bin/bash

set -e

export MVK_OS="tvOS"
export MVK_OS_PROD_EXTN="appletvos"
export MVK_SIM_PROD_EXTN="appletvsimulator"

. "${SRCROOT}/../Scripts/create_fat_libs.sh"

