# SPIRV-Cross (https://github.com/KhronosGroup/SPIRV-Cross)
# License: Apache-2.0
if(TARGET SPRIV-Cross::SPRIV-Cross)
    return()
endif()

message(STATUS "External: creating target 'SPRIV-Cross::SPRIV-Cross'")

set(SPIRV_CROSS_NAMESPACE_OVERRIDE "MVK_spirv_cross")

include(CPM)
CPMAddPackage("gh:KhronosGroup/SPIRV-Cross#ccff428086b625241de9f225dab0a53269b4d12c")

add_library(SPRIV-Cross::Core ALIAS spirv-cross-core)
add_library(SPRIV-Cross::Reflect ALIAS spirv-cross-reflect)
add_library(SPRIV-Cross::GLSL ALIAS spirv-cross-glsl)
add_library(SPRIV-Cross::MSL ALIAS spirv-cross-msl)

add_library(SPRIV-Cross INTERFACE)
add_library(SPRIV-Cross::SPRIV-Cross ALIAS SPRIV-Cross)
target_link_libraries(SPRIV-Cross INTERFACE
    spirv-cross-core
    spirv-cross-reflect
    spirv-cross-glsl
    spirv-cross-msl
)