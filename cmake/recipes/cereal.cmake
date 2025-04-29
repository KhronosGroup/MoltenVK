# cereal (https://github.com/USCiLab/cereal)
# License: BSD-3-Clause
if(TARGET cereal::cereal)
    return()
endif()

message(STATUS "External: creating target 'cereal::cereal'")

include(CPM)
CPMAddPackage("gh:USCiLab/cereal@1.3.2")