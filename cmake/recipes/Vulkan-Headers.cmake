# Vulkan-Headers (https://github.com/KhronosGroup/Vulkan-Headers)
# License: Apache-2.0
if(TARGET Vulkan::Headers)
    return()
endif()

message(STATUS "External: creating target 'Vulkan::Headers'")

# Read Git commit hash from ExternalRevisions file
file(READ "${MOLTEN_VK_EXTERNAL_REVISIONS_DIR}/Vulkan-Headers_repo_revision" VULKAN_HEADERS_COMMIT_HASH)
string(STRIP "${VULKAN_HEADERS_COMMIT_HASH}" VULKAN_HEADERS_COMMIT_HASH)

include(CPM)
CPMAddPackage("gh:KhronosGroup/Vulkan-Headers#${VULKAN_HEADERS_COMMIT_HASH}")