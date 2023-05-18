cmake_minimum_required(VERSION 3.25)
project(MoltenVK)

set(MVK_GIT_REV "unknown")

find_package(Git)
if(GIT_FOUND)
    execute_process(
            COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
            OUTPUT_VARIABLE MVK_GIT_REV
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    message( STATUS "GIT hash: ${MVK_GIT_REV}")
else()
    message(STATUS "GIT not found")
endif()

configure_file(${CMAKE_CURRENT_LIST_DIR}/mvkGitRevDerived.h.in
        ${CMAKE_CURRENT_BINARY_DIR}/mvkGitRevDerived.h)

add_subdirectory(External)
add_subdirectory(MoltenVKShaderConverter)
add_subdirectory(MoltenVK)

target_include_directories(MoltenVK-iOS PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_include_directories(MoltenVK-tvOS PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_include_directories(MoltenVK-macOS PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
