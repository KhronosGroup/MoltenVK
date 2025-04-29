# SPIRV-Tools (https://github.com/KhronosGroup/SPIRV-Tools)
# License: Apache-2.0
if(TARGET SPIRV-Tools::SPIRV-Tools)
    return()
endif()

message(STATUS "External: creating target 'SPIRV-Tools::SPIRV-Tools'")


# SPIRV-Tools requires SPIRV-Headers
include(SPIRV-Headers)

set(SPIRV_TOOLS_BUILD_STATIC ON)

include(CPM)
CPMAddPackage("gh:KhronosGroup/SPIRV-Tools#f289d047f49fb60488301ec62bafab85573668cc")

add_library(SPIRV-Tools::SPIRV-Tools ALIAS SPIRV-Tools-static)