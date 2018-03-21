project(MoltenVK)
cmake_minimum_required(VERSION 3.10)
set(CMAKE_CXX_STANDARD 14)

execute_process(COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/External/fetchDependencies)

add_subdirectory(Common)
add_subdirectory(External)
add_subdirectory(MoltenVKShaderConverter)
add_subdirectory(MoltenVK)

set(
  MVK_INCLUDES
  ${MVK_INCLUDES}
  PARENT_SCOPE
)
