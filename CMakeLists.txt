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
	LANGUAGES OBJCXX CXX C
	VERSION "1.2.12")

# Set default minimum C++ standard
if(MOLTEN_VK_TOPLEVEL_PROJECT)
	set(CMAKE_CXX_STANDARD 17)
	set(CMAKE_CXX_STANDARD_REQUIRED ON)
	set(CMAKE_CXX_EXTENSIONS OFF)
endif()

### Configuration
list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake/MoltenVK/")
list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake/recipes/")

# General CMake utils
include(MoltenVK_CPM_Cache)

# Generate position-independent code by default
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

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

################################################################################
# MoltenVK Library
################################################################################

## MoltenVK::Common

add_library(MoltenVK_Common STATIC "Common/MVKOSExtensions.mm")
add_library(MoltenVK::Common ALIAS MoltenVK_Common)

target_include_directories(MoltenVK_Common PUBLIC "Common")

## MoltenVK::ShaderConverter

add_library(MoltenVK_ShaderConverter STATIC
	"MoltenVKShaderConverter/MoltenVKShaderConverter/FileSupport.mm"
	"MoltenVKShaderConverter/MoltenVKShaderConverter/SPIRVConversion.mm"
	"MoltenVKShaderConverter/MoltenVKShaderConverter/SPIRVSupport.cpp"
	"MoltenVKShaderConverter/MoltenVKShaderConverter/SPIRVToMSLConverter.cpp"
)
add_library(MoltenVK::ShaderConverter ALIAS MoltenVK_ShaderConverter)

target_include_directories(MoltenVK_ShaderConverter PUBLIC "MoltenVKShaderConverter")

## MoltenVK::MoltenVK

add_library(MoltenVK SHARED
	"MoltenVK/MoltenVK/Commands/MVKCmdDebug.mm"
	"MoltenVK/MoltenVK/Commands/MVKCmdDispatch.mm"
	"MoltenVK/MoltenVK/Commands/MVKCmdDraw.mm"
	"MoltenVK/MoltenVK/Commands/MVKCmdPipeline.mm"
	"MoltenVK/MoltenVK/Commands/MVKCmdQueries.mm"
	"MoltenVK/MoltenVK/Commands/MVKCmdRendering.mm"
	"MoltenVK/MoltenVK/Commands/MVKCmdTransfer.mm"
	"MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm"
	"MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm"
	"MoltenVK/MoltenVK/Commands/MVKCommandEncodingPool.mm"
	"MoltenVK/MoltenVK/Commands/MVKCommandPool.mm"
	"MoltenVK/MoltenVK/Commands/MVKCommandResourceFactory.mm"
	"MoltenVK/MoltenVK/Commands/MVKMTLBufferAllocation.mm"

	"MoltenVK/MoltenVK/GPUObjects/MVKBuffer.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKDescriptor.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKDescriptorSet.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKDeviceMemory.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKFramebuffer.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKImage.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKInstance.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKPipeline.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKPixelFormats.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKQueryPool.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKQueue.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKRenderPass.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKResource.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKShaderModule.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKSurface.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKSwapchain.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKSync.mm"
	"MoltenVK/MoltenVK/GPUObjects/MVKVulkanAPIObject.mm"

	"MoltenVK/MoltenVK/Layers/MVKExtensions.mm"
	"MoltenVK/MoltenVK/Layers/MVKLayers.mm"

	"MoltenVK/MoltenVK/OS/CAMetalLayer+MoltenVK.mm"
	"MoltenVK/MoltenVK/OS/MTLRenderPassDepthAttachmentDescriptor+MoltenVK.m"
	"MoltenVK/MoltenVK/OS/MTLRenderPassDescriptor+MoltenVK.m"
	"MoltenVK/MoltenVK/OS/MTLRenderPassStencilAttachmentDescriptor+MoltenVK.m"
	"MoltenVK/MoltenVK/OS/MTLRenderPipelineColorAttachmentDescriptor+MoltenVK.m"
	"MoltenVK/MoltenVK/OS/MTLRenderPipelineDescriptor+MoltenVK.m"
	"MoltenVK/MoltenVK/OS/MTLSamplerDescriptor+MoltenVK.m"
	"MoltenVK/MoltenVK/OS/MTLTextureDescriptor+MoltenVK.m"
	"MoltenVK/MoltenVK/OS/MVKGPUCapture.mm"
	"MoltenVK/MoltenVK/OS/NSString+MoltenVK.mm"

	"MoltenVK/MoltenVK/Utility/MVKBaseObject.mm"
	"MoltenVK/MoltenVK/Utility/MVKBlockObserver.m"
	"MoltenVK/MoltenVK/Utility/MVKCodec.mm"
	"MoltenVK/MoltenVK/Utility/MVKEnvironment.cpp"
	"MoltenVK/MoltenVK/Utility/MVKFoundation.cpp"
	"MoltenVK/MoltenVK/Utility/MVKWatermark.mm"

	"MoltenVK/MoltenVK/Vulkan/mvk_api.mm"
	"MoltenVK/MoltenVK/Vulkan/mvk_datatypes.mm"
	"MoltenVK/MoltenVK/Vulkan/vulkan.mm"
)
add_library(MoltenVK::MoltenVK ALIAS MoltenVK)

target_include_directories(MoltenVK
	PUBLIC
		"MoltenVk/include"
	PRIVATE
		"MoltenVK/MoltenVK/API"
		"MoltenVK/MoltenVK/Commands"
		"MoltenVK/MoltenVK/GPUObjects"
		"MoltenVK/MoltenVK/Layers"
		"MoltenVK/MoltenVK/OS"
		"MoltenVK/MoltenVK/Utility"
		"MoltenVK/MoltenVK/Vulkan"
		${CMAKE_CURRENT_BINARY_DIR} # for mvkGitRevDerived.h
)

target_compile_definitions(MoltenVK PUBLIC
	"MVK_FRAMEWORK_VERSION=${PROJECT_VERSION}"
)

set_target_properties(MoltenVK PROPERTIES VERSION ${PROJECT_VERSION})
set_target_properties(MoltenVK PROPERTIES SOVERSION ${PROJECT_VERSION_MAJOR})

## MoltenVKShaderConverter

add_executable(MoltenVKShaderConverter
	"MoltenVKShaderConverter/MoltenVKShaderConverterTool/main.cpp"
	"MoltenVKShaderConverter/MoltenVKShaderConverterTool/MoltenVKShaderConverterTool.cpp"
	"MoltenVKShaderConverter/MoltenVKShaderConverterTool/OSSupport.mm"
)

target_include_directories(MoltenVKShaderConverter PRIVATE
	"MoltenVKShaderConverter/MoltenVKShaderConverter"
)

################################################################################
# Dependencies
################################################################################

## MoltenVK::Common

find_library(FOUNDATION_LIBRARY Foundation REQUIRED)
find_library(METAL_LIBRARY Metal REQUIRED)
find_library(APPKIT_LIBRARY AppKit REQUIRED)
find_library(IOKIT_LIBRARY IOKit REQUIRED)
find_library(IOSURFACE_LIBRARY IOSurface REQUIRED)
find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
target_link_libraries(MoltenVK PUBLIC
	${FOUNDATION_LIBRARY} ${METAL_LIBRARY} ${APPKIT_LIBRARY} ${IOKIT_LIBRARY} ${IOSURFACE_LIBRARY} ${QUARTZCORE_LIBRARY}
)

## MoltenVK::ShaderConverter

target_link_libraries(MoltenVK_ShaderConverter PUBLIC MoltenVK::Common)

include(SPIRV-Cross)
target_link_libraries(MoltenVK_ShaderConverter PUBLIC SPRIV-Cross::SPRIV-Cross)

include(SPIRV-Tools)
target_link_libraries(MoltenVK_ShaderConverter PUBLIC SPIRV-Tools::SPIRV-Tools)

## MoltenVK::MoltenVK

target_link_libraries(MoltenVK PUBLIC MoltenVK::ShaderConverter)

include(cereal)
target_link_libraries(MoltenVK PRIVATE cereal::cereal)

include(Vulkan-Headers)
target_link_libraries(MoltenVK PUBLIC Vulkan::Headers)

## MoltenVKShaderConverter

target_link_libraries(MoltenVKShaderConverter PRIVATE MoltenVK::MoltenVK)

################################################################################
# Compiler options
################################################################################

# Use C++17
target_compile_features(MoltenVK_Common PUBLIC cxx_std_17)

################################################################################
# Install
################################################################################

# install(TARGETS MoltenVK MoltenVKShaderConverter EXPORT MotlenVK)
# export (TARGETS MoltenVK MoltenVKShaderConverter cereal glslang SPIRV OGLCompiler OSDependent MachineIndependent GenericCodeGen
#         FILE ${CMAKE_BINARY_DIR}/MoltenVKConfig.cmake)