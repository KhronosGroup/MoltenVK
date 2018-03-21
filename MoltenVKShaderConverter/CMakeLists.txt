project(MoltenVK-ShaderConverter)
cmake_minimum_required(VERSION 3.10)
set(CMAKE_CXX_STANDARD 14)

include_directories(
  ${MVK_COMMON_INCLUDES}
  ${MVK_EXTERNAL_INCLUDES}
  MoltenVKGLSLToSPIRVConverter
  MoltenVKSPIRVToMSLConverter
  Tool
)

set(
  MVK_SHADER_CONVERTER_INCLUDES
  ${CMAKE_CURRENT_SOURCE_DIR}
  PARENT_SCOPE
)

set(
  SPIRV_TO_MSL_SOURCES
  MoltenVKSPIRVToMSLConverter/FileSupport.mm
  MoltenVKSPIRVToMSLConverter/SPIRVConversion.mm
  MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.cpp
  ${MVK_EXTERNAL_SPIRV_CROSS_SOURCES}
)

set(
  GLSL_TO_SPIRV_SOURCES
  MoltenVKGLSLToSPIRVConverter/GLSLConversion.mm
  MoltenVKGLSLToSPIRVConverter/GLSLToSPIRVConverter.cpp
)

set(
  SHADER_CONVERTER_TOOL_SOURCES
  MoltenVKShaderConverterTool/main.cpp
  MoltenVKShaderConverterTool/MoltenVKShaderConverterTool.cpp
  MoltenVKShaderConverterTool/DirectorySupport.mm
)

add_library(MoltenVKGLSLToSPIRVConverter ${GLSL_TO_SPIRV_SOURCES})
add_library(MoltenVKSPIRVToMSLConverter ${SPIRV_TO_MSL_SOURCES})
add_executable(MoltenVKShaderConverterTool ${SHADER_CONVERTER_TOOL_SOURCES})

target_link_libraries(
  MoltenVKShaderConverterTool
  MoltenVKSPIRVToMSLConverter
  MoltenVKGLSLToSPIRVConverter
  ${MVK_EXTERNAL_LIBS}
)
