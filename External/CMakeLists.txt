set(SKIP_PORTABILITY_TEST ON)
set(JUST_INSTALL_CEREAL ON)

add_subdirectory(cereal)
add_subdirectory(glslang)
set(SPIRV_TOOLS_BUILD_STATIC ON)
add_subdirectory(SPIRV-Cross)
add_subdirectory(Vulkan-Headers)
