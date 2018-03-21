project(MoltenVK-External)
cmake_minimum_required(VERSION 3.10)
set(CMAKE_CXX_STANDARD 14)

add_library(glslang STATIC IMPORTED GLOBAL)
set_target_properties(
  glslang PROPERTIES
  IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/glslang/build/glslang/libglslang.a
)

add_library(spirv STATIC IMPORTED GLOBAL)
set_target_properties(
  spirv PROPERTIES
  IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/glslang/build/SPIRV/libSPIRV.a
)

add_library(spirvremapper STATIC IMPORTED GLOBAL)
set_target_properties(
  spirvremapper PROPERTIES
  IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/glslang/build/SPIRV/libSPVRemapper.a
)

add_library(oglcompiler STATIC IMPORTED GLOBAL)
set_target_properties(
  oglcompiler PROPERTIES
  IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/glslang/build/OGLCompilersDLL/libOGLCompiler.a
)

add_library(hlsl STATIC IMPORTED GLOBAL)
set_target_properties(
  hlsl PROPERTIES
  IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/glslang/build/hlsl/libHLSL.a
)

add_library(osdependent STATIC IMPORTED GLOBAL)
set_target_properties(
  osdependent PROPERTIES
  IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/glslang/build/glslang/OSDependent/Unix/libOSDependent.a
)

add_library(spirvtools STATIC IMPORTED GLOBAL)
set_target_properties(
  spirvtools PROPERTIES
  IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/glslang/build/External/spirv-tools/source/libSPIRV-Tools.a
)

add_library(spirvtoolslink STATIC IMPORTED GLOBAL)
set_target_properties(
  spirvtoolslink PROPERTIES
  IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/glslang/build/External/spirv-tools/source/link/libSPIRV-Tools-link.a
)

add_library(spirvtoolsopt STATIC IMPORTED GLOBAL)
set_target_properties(
  spirvtoolsopt PROPERTIES
  IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/glslang/build/External/spirv-tools/source/opt/libSPIRV-Tools-opt.a
)

find_library(frameworkFoundation foundation)

set(
  MVK_EXTERNAL_INCLUDES
  ${CMAKE_CURRENT_SOURCE_DIR}/glslang/SPIRV
  ${CMAKE_CURRENT_SOURCE_DIR}/SPIRV-Cross
  ${CMAKE_CURRENT_SOURCE_DIR}/glslang/External/spirv-tools/include
  PARENT_SCOPE
)

set(
  MVK_EXTERNAL_SPIRV_CROSS_SOURCES
  ${CMAKE_CURRENT_SOURCE_DIR}/SPIRV-Cross/spirv_cfg.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/SPIRV-Cross/spirv_cross.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/SPIRV-Cross/spirv_glsl.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/SPIRV-Cross/spirv_msl.cpp
  PARENT_SCOPE
)

set(
  MVK_EXTERNAL_LIBS
  ${frameworkFoundation}
  glslang
  spirv
  spirvremapper
  oglcompiler
  hlsl
  osdependent
  spirvtools
  spirvtoolslink
  spirvtoolsopt
  PARENT_SCOPE
)

add_custom_target(MoltenVK-External)

add_custom_command(
  TARGET MoltenVK-External
  COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/fetchDependencies
)
