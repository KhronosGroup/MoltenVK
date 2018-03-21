project(MoltenVK)
cmake_minimum_required(VERSION 3.10)
set(CMAKE_CXX_STANDARD 14)

include_directories(MoltenVKShaderConverter)

include_directories(Common)
include_directories(MoltenVK/include)
include_directories(MoltenVK/MoltenVK/API)
include_directories(MoltenVK/MoltenVK/Commands)
include_directories(MoltenVK/MoltenVK/GPUObjects)
include_directories(MoltenVK/MoltenVK/Loader)
include_directories(MoltenVK/MoltenVK/Utility)
include_directories(MoltenVK/MoltenVK/Vulkan)

set(
  SOURCES
  MoltenVK/MoltenVK/GPUObjects/MVKQueryPool.mm
  MoltenVK/MoltenVK/GPUObjects/MVKRenderPass.mm
  MoltenVK/MoltenVK/GPUObjects/MVKDeviceMemory.mm
  MoltenVK/MoltenVK/GPUObjects/MVKSwapchain.mm
  MoltenVK/MoltenVK/GPUObjects/MVKBuffer.mm
  MoltenVK/MoltenVK/GPUObjects/MVKSurface.mm
  MoltenVK/MoltenVK/GPUObjects/MVKPipeline.mm
  MoltenVK/MoltenVK/GPUObjects/MVKSync.mm
  MoltenVK/MoltenVK/GPUObjects/MVKImage.mm
  MoltenVK/MoltenVK/GPUObjects/MVKShaderModule.mm
  MoltenVK/MoltenVK/GPUObjects/MVKFramebuffer.mm
  MoltenVK/MoltenVK/GPUObjects/MVKResource.mm
  MoltenVK/MoltenVK/GPUObjects/MVKQueue.mm
  MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm
  MoltenVK/MoltenVK/GPUObjects/MVKInstance.mm
  MoltenVK/MoltenVK/GPUObjects/MVKDescriptorSet.mm
  MoltenVK/MoltenVK/Loader/MVKLayers.mm
  MoltenVK/MoltenVK/Vulkan/mvk_datatypes.mm
  MoltenVK/MoltenVK/Vulkan/vk_mvk_moltenvk.mm
  MoltenVK/MoltenVK/Vulkan/vulkan.mm
  MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm
  MoltenVK/MoltenVK/Commands/MVKCommandEncodingPool.mm
  MoltenVK/MoltenVK/Commands/MVKCommandPool.mm
  MoltenVK/MoltenVK/Commands/MVKCmdQueries.mm
  MoltenVK/MoltenVK/Commands/MVKMTLBufferAllocation.mm
  MoltenVK/MoltenVK/Commands/MVKCmdDraw.mm
  MoltenVK/MoltenVK/Commands/MVKCmdPipeline.mm
  MoltenVK/MoltenVK/Commands/MVKCmdRenderPass.mm
  MoltenVK/MoltenVK/Commands/MVKCmdTransfer.mm
  MoltenVK/MoltenVK/Commands/MVKCommand.mm
  MoltenVK/MoltenVK/Commands/MVKCmdDispatch.mm
  MoltenVK/MoltenVK/Commands/MVKCommandResourceFactory.mm
  MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm
  MoltenVK/MoltenVK/Utility/MVKWatermark.mm
  MoltenVK/MoltenVK/Utility/MVKOSExtensions.mm
  MoltenVK/MoltenVK/Utility/MVKFoundation.mm
  MoltenVK/MoltenVK/Utility/MVKBaseObject.cpp
)

add_library(MoltenVK ${SOURCES})

add_custom_target(
    fetchDependencies ALL
    COMMENT "Fetching dependencies"
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/External/fetchDependencies
)

add_dependencies(MoltenVK fetchDependencies)

find_library(FOUNDATION_LIB foundation)
include_directories(External/glslang/SPIRV)
include_directories(MoltenVKShaderConverter/MoltenVKGLSLToSPIRVConverter)
include_directories(MoltenVKShaderConverter/Tool)
include_directories(MoltenVKShaderConverter/MoltenVKSPIRVToMSLConverter)
include_directories(External/SPIRV-Cross)
include_directories(External/glslang/External/spirv-tools/include)

set(
  SPIRV_TO_MSL_SOURCES
  MoltenVKShaderConverter/MoltenVKSPIRVToMSLConverter/FileSupport.mm
  MoltenVKShaderConverter/MoltenVKSPIRVToMSLConverter/SPIRVConversion.mm
  MoltenVKShaderConverter/MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.cpp
  External/SPIRV-Cross/spirv_cfg.cpp
  External/SPIRV-Cross/spirv_cross.cpp
  External/SPIRV-Cross/spirv_glsl.cpp
  External/SPIRV-Cross/spirv_msl.cpp
)

set(
  GLSL_TO_SPIRV_SOURCES
  MoltenVKShaderConverter/MoltenVKGLSLToSPIRVConverter/GLSLConversion.mm
  MoltenVKShaderConverter/MoltenVKGLSLToSPIRVConverter/GLSLToSPIRVConverter.cpp
)

set(
  SHADER_CONVERTER_TOOL_SOURCES
  MoltenVKShaderConverter/MoltenVKShaderConverterTool/main.cpp
  MoltenVKShaderConverter/MoltenVKShaderConverterTool/MoltenVKShaderConverterTool.cpp
  MoltenVKShaderConverter/MoltenVKShaderConverterTool/DirectorySupport.mm
)

add_library(MoltenVKGLSLToSPIRVConverter ${GLSL_TO_SPIRV_SOURCES})

add_library(MoltenVKSPIRVToMSLConverter ${SPIRV_TO_MSL_SOURCES})

add_library(glslang STATIC IMPORTED GLOBAL)
set_target_properties(glslang PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/External/glslang/build/glslang/libglslang.a)

add_library(spirv STATIC IMPORTED GLOBAL)
set_target_properties(spirv PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/External/glslang/build/SPIRV/libSPIRV.a)

add_library(spirvremapper STATIC IMPORTED GLOBAL)
set_target_properties(spirvremapper PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/External/glslang/build/SPIRV/libSPVRemapper.a)

add_library(oglcompiler STATIC IMPORTED GLOBAL)
set_target_properties(oglcompiler PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/External/glslang/build/OGLCompilersDLL/libOGLCompiler.a)

add_library(hlsl STATIC IMPORTED GLOBAL)
set_target_properties(hlsl PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/External/glslang/build/hlsl/libHLSL.a)

add_library(osdependent STATIC IMPORTED GLOBAL)
set_target_properties(osdependent PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/External/glslang/build/glslang/OSDependent/Unix/libOSDependent.a)

add_library(spirvtools STATIC IMPORTED GLOBAL)
set_target_properties(spirvtools PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/External/glslang/build/External/spirv-tools/source/libSPIRV-Tools.a)

add_library(spirvtoolslink STATIC IMPORTED GLOBAL)
set_target_properties(spirvtoolslink PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/External/glslang/build/External/spirv-tools/source/link/libSPIRV-Tools-link.a)

add_library(spirvtoolsopt STATIC IMPORTED GLOBAL)
set_target_properties(spirvtoolsopt PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/External/glslang/build/External/spirv-tools/source/opt/libSPIRV-Tools-opt.a)

add_executable(MoltenVKShaderConverterTool ${SHADER_CONVERTER_TOOL_SOURCES})
  target_link_libraries(
  MoltenVKShaderConverterTool
  ${FOUNDATION_LIB}
  MoltenVKSPIRVToMSLConverter
  MoltenVKGLSLToSPIRVConverter
  glslang
  spirv
  spirvremapper
  oglcompiler
  hlsl
  osdependent
  spirvtools
  spirvtoolslink
  spirvtoolsopt
)
