# Vulkan-Headers (https://github.com/KhronosGroup/Vulkan-Headers)
# License: Apache-2.0
if(TARGET Vulkan::Headers)
    return()
endif()

message(STATUS "External: creating target 'Vulkan::Headers'")

include(CPM)
CPMAddPackage("gh:KhronosGroup/Vulkan-Headers#952f776f6573aafbb62ea717d871cd1d6816c387")