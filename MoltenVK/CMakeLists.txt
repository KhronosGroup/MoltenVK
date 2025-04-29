################################################################################
# MoltenVK::MoltenVK Library
################################################################################

# Find the source files in this directory. We prefer to use GLOB because it is
# easier to maintain in conjunction with the Xcode project file.
file(GLOB_RECURSE SOURCES "MoltenVK/*.c" "MoltenVK/*.cpp" "MoltenVK/*.m" "MoltenVK/*.mm")

add_library(MoltenVK SHARED ${SOURCES})
add_library(MoltenVK::MoltenVK ALIAS MoltenVK)

target_include_directories(MoltenVK
	PUBLIC
		"${CMAKE_CURRENT_SOURCE_DIR}/include"
	PRIVATE
		"${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/API"
		"${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands"
		"${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects"
		"${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Layers"
		"${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/OS"
		"${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Utility"
		"${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Vulkan"
		"${CMAKE_CURRENT_BINARY_DIR}" # for mvkGitRevDerived.h
)

# Record the MoltenVK GIT revision as a derived header file suitable for including in a build
find_package(Git)
if(GIT_FOUND)
	execute_process(
		COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
		OUTPUT_VARIABLE MVK_GIT_REV
		ERROR_QUIET
		OUTPUT_STRIP_TRAILING_WHITESPACE
	)
	configure_file(
		"${PROJECT_SOURCE_DIR}/Templates/cmake/mvkGitRevDerived.h.in"
		"${CMAKE_CURRENT_BINARY_DIR}/mvkGitRevDerived.h"
	)
else()
	message(FATAL_ERROR "GIT not found")
endif()

target_compile_definitions(MoltenVK PUBLIC
	"MVK_FRAMEWORK_VERSION=${PROJECT_VERSION}"
)

set_target_properties(MoltenVK PROPERTIES VERSION ${PROJECT_VERSION})
set_target_properties(MoltenVK PROPERTIES SOVERSION ${PROJECT_VERSION_MAJOR})

################################################################################
# Dependencies
################################################################################

target_link_libraries(MoltenVK PUBLIC MoltenVK::ShaderConverter)

include(cereal)
target_link_libraries(MoltenVK PRIVATE cereal::cereal)

include(Vulkan-Headers)
target_link_libraries(MoltenVK PUBLIC Vulkan::Headers)