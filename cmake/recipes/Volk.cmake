# Volk (https://github.com/zeux/Volk)
# License: MIT
if(TARGET volk::volk)
    return()
endif()

message(STATUS "External: creating target 'volk::volk'")

include(CPM)
CPMAddPackage("gh:zeux/Volk#58689c063427f5bad4f133625049b1a3c5dd8287")