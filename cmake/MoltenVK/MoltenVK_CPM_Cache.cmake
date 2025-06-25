#
# Copyright 2021 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.
#

if(DEFINED ENV{CPM_SOURCE_CACHE})
    set(CPM_SOURCE_CACHE_DEFAULT $ENV{CPM_SOURCE_CACHE})
else()
    # Set CPM cache folder if unset
    file(REAL_PATH "~/.cache/CPM" CPM_SOURCE_CACHE_DEFAULT EXPAND_TILDE)
endif()

set(CPM_SOURCE_CACHE
    ${CPM_SOURCE_CACHE_DEFAULT}
    CACHE PATH "Directory to download CPM dependencies"
)
message(STATUS "Using CPM cache folder: ${CPM_SOURCE_CACHE}")