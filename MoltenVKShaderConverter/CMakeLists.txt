##
## MoltenVKShaderConverter Files
##

add_library(moltenvk_shader_converter STATIC
        ../Common/MVKOSExtensions.mm
        MoltenVKShaderConverter/SPIRVSupport.cpp
        MoltenVKShaderConverterTool/MoltenVKShaderConverterTool.cpp
        MoltenVKShaderConverterTool/OSSupport.mm
        MoltenVKShaderConverterTool/main.cpp
        MoltenVKShaderConverter/FileSupport.mm
        MoltenVKShaderConverter/GLSLConversion.mm
        MoltenVKShaderConverter/GLSLToSPIRVConverter.cpp
        MoltenVKShaderConverter/SPIRVConversion.mm
        MoltenVKShaderConverter/SPIRVToMSLConverter.cpp
        )

find_library(FOUNDATION_LIBRARY Foundation)
message(STATUS "FOUNDATION_LIBRARY is ${FOUNDATION_LIBRARY}")
find_library(METAL_LIBRARY Metal)
message(STATUS "METAL_LIBRARY is ${METAL_LIBRARY}")
find_library(APPKIT_LIBRARY AppKit)
message(STATUS "APPKIT_LIBRARY is ${APPKIT_LIBRARY}")
find_library(IOKIT_LIBRARY IOKit)
message(STATUS "IOKIT_LIBRARY is ${IOKIT_LIBRARY}")
find_library(IOSURFACE_LIBRARY IOSurface)
message(STATUS "IOSURFACE_LIBRARY is ${IOSURFACE_LIBRARY}")
find_library(QUARTZCORE_LIBRARY QuartzCore)
message(STATUS "QUARTZCORE_LIBRARY is ${QUARTZCORE_LIBRARY}")


target_link_libraries(moltenvk_shader_converter PUBLIC ${FOUNDATION_LIBRARY} ${METAL_LIBRARY} ${APPKIT_LIBRARY}
        ${IOKIT_LIBRARY} ${IOSURFACE_LIBRARY} ${QUARTZCORE_LIBRARY}
        cereal spirv-cross-msl glslang SPIRV-Tools-opt spirv-cross-reflect SPIRV)

target_include_directories(moltenvk_shader_converter PUBLIC MoltenVKShaderConverter include
        ${CMAKE_CURRENT_LIST_DIR}/../Common
        ${CMAKE_CURRENT_LIST_DIR}/../External
        ${CMAKE_CURRENT_LIST_DIR})
target_compile_features(moltenvk_shader_converter PUBLIC cxx_std_17)
