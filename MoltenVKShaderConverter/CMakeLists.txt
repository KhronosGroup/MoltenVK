##
## MoltenVKShaderConverter Files
##
set(SRC_LIST
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

file(GLOB SRCS RELATIVE CONFIGURE_DEPENDS ${CMAKE_CURRENT_LIST_DIR}/MoltenVKShaderConverter *.mm *.cpp *.m)
list(PREPEND SRCS ../Common/MVKOSExtensions.mm)

check_lists_equal(${SRCS}, ${SRC_LIST})

add_library(moltenvk_shader_converter STATIC ${SRC_LIST})

find_library(FOUNDATION_LIBRARY Foundation REQUIRED)
find_library(METAL_LIBRARY Metal REQUIRED)
find_library(APPKIT_LIBRARY AppKit REQUIRED)
find_library(IOKIT_LIBRARY IOKit REQUIRED)
find_library(IOSURFACE_LIBRARY IOSurface REQUIRED)
find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)


target_link_libraries(moltenvk_shader_converter PUBLIC ${FOUNDATION_LIBRARY} ${METAL_LIBRARY} ${APPKIT_LIBRARY}
    ${IOKIT_LIBRARY} ${IOSURFACE_LIBRARY} ${QUARTZCORE_LIBRARY}
    cereal spirv-cross-msl glslang SPIRV-Tools-opt spirv-cross-reflect SPIRV)

target_include_directories(moltenvk_shader_converter PUBLIC MoltenVKShaderConverter include
    ${CMAKE_CURRENT_LIST_DIR}/../Common
    ${CMAKE_CURRENT_LIST_DIR}/../External
    ${CMAKE_CURRENT_LIST_DIR})
target_compile_features(moltenvk_shader_converter PUBLIC cxx_std_17)
