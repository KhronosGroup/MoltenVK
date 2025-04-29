# Vulkan-Tools (https://github.com/KhronosGroup/Vulkan-Tools)
# License: Apache-2.0
if(TARGET Vulkan::Headers)
    return()
endif()

message(STATUS "External: creating target 'Vulkan::Tools'")

include(CPM)
CPMAddPackage("gh:KhronosGroup/Vulkan-Tools#fb8f5a5d69f4590ff1f5ecacb5e3957b6d11daee")