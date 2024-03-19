cmake_minimum_required(VERSION 3.20)
project(MoltenVK)

set(MVK_GIT_REV "unknown")

function(check_lists_equal list1 list2)
    set(DIFF_ITEMS )
    # Check if each element in the first list is in the second list
    foreach(element IN LISTS ${list1})
        if(NOT ${element} IN LISTS ${list2})
            LIST(APPEND DIFF_ITEMS ${element})
        endif()
    endforeach()

    if(DIFF_ITEMS)
        message(STATUS "glob found the following files ${DIFF_ITEMS} which aren't part of the SRC_LIST in ${CMAKE_CURRENT_LIST_FILE}")
    endif ()
endfunction()

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

target_include_directories(MoltenVK PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

install ( TARGETS MoltenVK moltenvk_shader_converter EXPORT MotlenVK )
export ( TARGETS MoltenVK moltenvk_shader_converter cereal glslang SPIRV OGLCompiler OSDependent MachineIndependent
        GenericCodeGen
        FILE ${CMAKE_BINARY_DIR}/MoltenVKConfig.cmake )