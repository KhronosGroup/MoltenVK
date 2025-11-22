# SPIRV-Cross (https://github.com/KhronosGroup/SPIRV-Cross)
# License: Apache-2.0
if(TARGET SPRIV-Cross::SPRIV-Cross)
    return()
endif()

message(STATUS "External: creating target 'SPRIV-Cross::SPRIV-Cross'")

# Read Git commit hash from ExternalRevisions file
file(READ "${MOLTEN_VK_EXTERNAL_REVISIONS_DIR}/SPIRV-Cross_repo_revision" SPIRV_CROSS_COMMIT_HASH)
string(STRIP "${SPIRV_CROSS_COMMIT_HASH}" SPIRV_CROSS_COMMIT_HASH)

include(CPM)
CPMAddPackage(
  NAME SPIRV-Cross
  GITHUB_REPOSITORY KhronosGroup/SPIRV-Cross
  GIT_TAG ${SPIRV_CROSS_COMMIT_HASH}
  SYSTEM TRUE
  OPTIONS
    "SPIRV_CROSS_CLI OFF"
    "SPIRV_CROSS_ENABLE_TESTS OFF"
    "SPIRV_CROSS_ENABLE_GLSL ON"
    "SPIRV_CROSS_ENABLE_HLSL OFF"
    "SPIRV_CROSS_ENABLE_MSL ON"
    "SPIRV_CROSS_ENABLE_CPP OFF"
    "SPIRV_CROSS_ENABLE_REFLECT ON"
    "SPIRV_CROSS_ENABLE_C_API OFF"
    "SPIRV_CROSS_ENABLE_UTIL OFF"
    "SPIRV_CROSS_NAMESPACE_OVERRIDE MVK_spirv_cross"
    "SPIRV_CROSS_SKIP_INSTALL ON"
)

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
