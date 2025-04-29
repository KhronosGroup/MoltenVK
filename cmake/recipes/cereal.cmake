# cereal (https://github.com/USCiLab/cereal)
# License: BSD-3-Clause
if(TARGET cereal::cereal)
    return()
endif()

message(STATUS "External: creating target 'cereal::cereal'")

# Read Git commit hash from ExternalRevisions file
file(READ "${PROJECT_SOURCE_DIR}/ExternalRevisions/cereal_repo_revision" CEREAL_COMMIT_HASH)
string(STRIP "${CEREAL_COMMIT_HASH}" CEREAL_COMMIT_HASH)

include(CPM)
CPMAddPackage("gh:USCiLab/cereal#${CEREAL_COMMIT_HASH}")