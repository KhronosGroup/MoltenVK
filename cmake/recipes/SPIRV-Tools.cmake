# SPIRV-Tools (https://github.com/KhronosGroup/SPIRV-Tools)
# License: Apache-2.0
if(TARGET SPIRV-Tools::SPIRV-Tools)
    return()
endif()

message(STATUS "External: creating target 'SPIRV-Tools::SPIRV-Tools'")

# SPIRV-Tools requires SPIRV-Headers
include(SPIRV-Headers)

set(SPIRV_TOOLS_BUILD_STATIC ON)

# Read Git commit hash from ExternalRevisions file
file(READ "${MOLTEN_VK_EXTERNAL_REVISIONS_DIR}/SPIRV-Tools_repo_revision" SPIRV_TOOLS_COMMIT_HASH)
string(STRIP "${SPIRV_TOOLS_COMMIT_HASH}" SPIRV_TOOLS_COMMIT_HASH)

include(CPM)
CPMAddPackage("gh:KhronosGroup/SPIRV-Tools#${SPIRV_TOOLS_COMMIT_HASH}")

add_library(SPIRV-Tools::SPIRV-Tools ALIAS SPIRV-Tools-static)