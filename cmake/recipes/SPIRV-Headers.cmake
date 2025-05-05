# SPIRV-Headers (https://github.com/KhronosGroup/SPIRV-Headers)
# License: Apache-2.0
if(TARGET SPIRV-Headers::SPIRV-Headers)
    return()
endif()

message(STATUS "External: creating target 'SPIRV-Headers::SPIRV-Headers'")

# Read Git commit hash from ExternalRevisions file
file(READ "${MOLTEN_VK_EXTERNAL_REVISIONS_DIR}/SPIRV-Headers_repo_revision" SPIRV_HEADERS_COMMIT_HASH)
string(STRIP "${SPIRV_HEADERS_COMMIT_HASH}" SPIRV_HEADERS_COMMIT_HASH)

include(CPM)
CPMAddPackage("gh:KhronosGroup/SPIRV-Headers#${SPIRV_HEADERS_COMMIT_HASH}")