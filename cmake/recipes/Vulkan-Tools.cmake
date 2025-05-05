# Vulkan-Tools (https://github.com/KhronosGroup/Vulkan-Tools)
# License: Apache-2.0
if(TARGET Vulkan::Headers)
    return()
endif()

message(STATUS "External: creating target 'Vulkan::Tools'")

# Read Git commit hash from ExternalRevisions file
file(READ "${MOLTEN_VK_EXTERNAL_REVISIONS_DIR}/Vulkan-Tools_repo_revision" VULKAN_TOOLS_COMMIT_HASH)
string(STRIP "${VULKAN_TOOLS_COMMIT_HASH}" VULKAN_TOOLS_COMMIT_HASH)

include(CPM)
CPMAddPackage("gh:KhronosGroup/Vulkan-Tools#${VULKAN_TOOLS_COMMIT_HASH}")