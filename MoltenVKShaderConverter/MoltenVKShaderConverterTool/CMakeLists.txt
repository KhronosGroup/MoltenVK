################################################################################
# MoltenVKShaderConverter Executable
################################################################################

# Find the source files in this directory. We prefer to use GLOB because it is
# easier to maintain in conjunction with the Xcode project file.
file(GLOB_RECURSE SOURCES "*.c" "*.cpp" "*.m" "*.mm")

add_executable(MoltenVKShaderConverter_bin ${SOURCES})

target_include_directories(MoltenVK_ShaderConverter PUBLIC
	"${CMAKE_CURRENT_SOURCE_DIR}/../MoltenVKShaderConverter"
)

################################################################################
# Dependencies
################################################################################

target_link_libraries(MoltenVKShaderConverter_bin PRIVATE MoltenVK::MoltenVK)