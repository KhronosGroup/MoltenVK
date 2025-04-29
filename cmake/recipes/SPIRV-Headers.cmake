# SPIRV-Headers (https://github.com/KhronosGroup/SPIRV-Headers)
# License: Apache-2.0
if(TARGET SPIRV-Headers::SPIRV-Headers)
    return()
endif()

message(STATUS "External: creating target 'SPIRV-Headers::SPIRV-Headers'")

include(CPM)
CPMAddPackage("gh:KhronosGroup/SPIRV-Headers#09913f088a1197aba4aefd300a876b2ebbaa3391")