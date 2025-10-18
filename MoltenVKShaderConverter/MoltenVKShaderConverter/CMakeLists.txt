################################################################################
# MoltenVK::ShaderConverter Library
################################################################################

# Find the source files in this directory. We prefer to use GLOB because it is
# easier to maintain in conjunction with the Xcode project file.
file(GLOB_RECURSE SOURCES "*.c" "*.cpp" "*.m" "*.mm")

add_library(MoltenVK_ShaderConverter STATIC ${SOURCES})
add_library(MoltenVK::ShaderConverter ALIAS MoltenVK_ShaderConverter)

target_include_directories(MoltenVK_ShaderConverter PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/..")

################################################################################
# Dependencies
################################################################################

target_link_libraries(MoltenVK_ShaderConverter PUBLIC MoltenVK::Common)

include(SPIRV-Cross)
target_link_libraries(MoltenVK_ShaderConverter PUBLIC SPRIV-Cross::SPRIV-Cross)

include(SPIRV-Tools)
target_link_libraries(MoltenVK_ShaderConverter PUBLIC SPIRV-Tools::SPIRV-Tools)