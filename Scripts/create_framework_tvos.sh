#!/bin/bash

set -e

export MVK_OS="tvOS"
export MVK_FRWK_SUBPATH=""

. "${SRCROOT}/../Scripts/create_framework.sh"
