#!/bin/bash

set -e

export MVK_OS="iOS"
export MVK_FRWK_SUBPATH=""

. "${SRCROOT}/../Scripts/create_framework.sh"
