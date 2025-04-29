# SPIRV-Cross (https://github.com/KhronosGroup/SPIRV-Cross)
# License: Apache-2.0
if(TARGET SPRIV-Cross::SPRIV-Cross)
    return()
endif()

message(STATUS "External: creating target 'SPRIV-Cross::SPRIV-Cross'")

set(SPIRV_CROSS_NAMESPACE_OVERRIDE "MVK_spirv_cross")

# Read Git commit hash from ExternalRevisions file
file(READ "${PROJECT_SOURCE_DIR}/ExternalRevisions/SPIRV-Cross_repo_revision" SPIRV_CROSS_COMMIT_HASH)
string(STRIP "${SPIRV_CROSS_COMMIT_HASH}" SPIRV_CROSS_COMMIT_HASH)

include(CPM)
CPMAddPackage("gh:KhronosGroup/SPIRV-Cross#${SPIRV_CROSS_COMMIT_HASH}")

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