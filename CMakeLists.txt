# Detects whether this is a top-level project
get_directory_property(HAS_PARENT PARENT_DIRECTORY)
if(HAS_PARENT)
	set(MOLTEN_VK_TOPLEVEL_PROJECT OFF)
else()
	set(MOLTEN_VK_TOPLEVEL_PROJECT ON)
endif()

# Check required CMake version
set(REQUIRED_CMAKE_VERSION "3.18.0")
if(MOLTEN_VK_TOPLEVEL_PROJECT)
	cmake_minimum_required(VERSION ${REQUIRED_CMAKE_VERSION})
else()
	# Don't use cmake_minimum_required here to avoid implicitly overriding parent policies
	if(${CMAKE_VERSION} VERSION_LESS ${REQUIRED_CMAKE_VERSION})
		message(FATAL_ERROR "CMake required version to build MoltenVK is ${REQUIRED_CMAKE_VERSION}")
	endif()
endif()

# Include user-provided default options if available. We do that before the main
# `project()` so that we can define the C/C++ compilers from the option file.
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVKOptions.cmake)
	message(STATUS "Using local options file: ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVKOptions.cmake")
	include(${CMAKE_CURRENT_SOURCE_DIR}/MoltenVKOptions.cmake)
endif()

# Enable ccache if available
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
	option(MOLTEN_VK_WITH_CCACHE "Enable ccache when building MoltenVK" ${MOLTEN_VK_TOPLEVEL_PROJECT})
else()
	option(MOLTEN_VK_WITH_CCACHE "Enable ccache when building MoltenVK" OFF)
endif()
if(MOLTEN_VK_WITH_CCACHE AND CCACHE_PROGRAM)
	message(STATUS "Enabling Ccache support (${CCACHE_PROGRAM})")
	set(ccacheEnv
		CCACHE_BASEDIR=${CMAKE_BINARY_DIR}
		CCACHE_SLOPPINESS=clang_index_store,include_file_ctime,include_file_mtime,locale,pch_defines,time_macros
	)
	foreach(lang IN ITEMS C CXX)
		set(CMAKE_${lang}_COMPILER_LAUNCHER
			${CMAKE_COMMAND} -E env ${ccacheEnv} ${CCACHE_PROGRAM}
		)
	endforeach()
endif()

################################################################################
# CMake Policies
################################################################################

cmake_policy(SET CMP0054 NEW) # Only interpret if() arguments as variables or keywords when unquoted.
cmake_policy(SET CMP0076 NEW) # target_sources() command converts relative paths to absolute.
if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.24")
	cmake_policy(SET CMP0135 NEW) # Set the timestamps of all extracted contents to the time of the extraction.
endif()
cmake_policy(SET CMP0114 NEW) # Support the Xcode "new build system"

################################################################################

project(MoltenVK
	DESCRIPTION "MoltenVK is a Vulkan Portability implementation. It layers a subset of the high-performance, industry-standard Vulkan graphics and compute API over Apple's Metal graphics framework, enabling Vulkan applications to run on macOS, iOS and tvOS."
	LANGUAGES C CXX OBJC OBJCXX
	VERSION "1.4.1")

set(MVK_CONFIG_LOG_LEVEL "info" CACHE STRING "Set the default log level for MoltenVK. Options are: debug, info, warn, error, off. Default is 'info'.")
set_property(CACHE MVK_CONFIG_LOG_LEVEL PROPERTY STRINGS "debug" "info" "warn" "error" "off")

option(MVK_USE_METAL_PRIVATE_API "If enabled, MoltenVK will use private interfaces exposed by Metal to implement Vulkan features that are difficult to support otherwise." OFF)

# Set default minimum C++ standard
if(MOLTEN_VK_TOPLEVEL_PROJECT)
	set(CMAKE_CXX_STANDARD 17)
	set(CMAKE_CXX_STANDARD_REQUIRED ON)
	set(CMAKE_CXX_EXTENSIONS OFF)
endif()

### Configuration
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/MoltenVK/")
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/recipes/")

# General CMake utils
include(MoltenVK_CPM_Cache)

# Generate position-independent code by default
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT DEFINED MOLTEN_VK_EXTERNAL_REVISIONS_DIR)
	set(MOLTEN_VK_EXTERNAL_REVISIONS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ExternalRevisions")
endif()

################################################################################
# MoltenVK Libraries
################################################################################

# MoltenVK::Common
add_subdirectory("Common")

# MoltenVK::ShaderConverter
add_subdirectory("MoltenVKShaderConverter/MoltenVKShaderConverter")

## MoltenVK::MoltenVK
add_subdirectory("MoltenVK")

## MoltenVKShaderConverter
add_subdirectory("MoltenVKShaderConverter/MoltenVKShaderConverterTool")

################################################################################
# Install
################################################################################

if(MOLTEN_VK_TOPLEVEL_PROJECT)
	include(GNUInstallDirs)

	install(TARGETS MoltenVK
			LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
			PUBLIC_HEADER DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/MoltenVK")

	configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Templates/cmake/MoltenVK.pc.in" MoltenVK.pc @ONLY)
	install(FILES ${CMAKE_BINARY_DIR}/MoltenVK.pc
			DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)

    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Templates/cmake/MoltenVK_icd.json.in" MoltenVK_icd.json @ONLY)
    install(FILES ${CMAKE_BINARY_DIR}/MoltenVK_icd.json
            DESTINATION ${CMAKE_INSTALL_PREFIX}/etc/vulkan/icd.d)

	install(TARGETS MoltenVKShaderConverter)
endif()
