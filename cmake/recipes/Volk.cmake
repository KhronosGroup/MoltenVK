# Volk (https://github.com/zeux/Volk)
# License: MIT
if(TARGET volk::volk)
    return()
endif()

message(STATUS "External: creating target 'volk::volk'")

# Read Git commit hash from ExternalRevisions file
file(READ "${PROJECT_SOURCE_DIR}/ExternalRevisions/Volk_repo_revision" VOLK_COMMIT_HASH)
string(STRIP "${VOLK_COMMIT_HASH}" VOLK_COMMIT_HASH)

include(CPM)
CPMAddPackage("gh:zeux/Volk#${VOLK_COMMIT_HASH}")