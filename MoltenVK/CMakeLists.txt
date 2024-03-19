##
## MoltenVK-iOS Files
##

file(GLOB_RECURSE MOLTEN_VK_PROJECT_HEADERS CONFIGURE_DEPENDS RELATIVE ${CMAKE_CURRENT_LIST_DIR}/MoltenVK *.h *.hpp)
file(GLOB MOLTEN_VK_PROJECT_HEADERS_COMMON RELATIVE CONFIGURE_DEPENDS ${CMAKE_CURRENT_LIST_DIR}/.. *.h *.hpp)
list(APPEND MOLTEN_VK_PROJECT_HEADERS ${MOLTEN_VK_PROJECT_HEADERS_COMMON})

file(GLOB_RECURSE MOLTEN_VK_SOURCES CONFIGURE_DEPENDS ${CMAKE_CURRENT_LIST_DIR}/MoltenVK *.mm *.m *.cpp)
list(PREPEND MOLTEN_VK_SOURCES ../Common/MVKOSExtensions.mm)

##
## MoltenVK-iOS
##

add_library(MoltenVK STATIC
        ${MOLTEN_VK_SOURCES}
        )

target_include_directories(MoltenVK
        PUBLIC
        ${CMAKE_CURRENT_LIST_DIR}/../Common
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/API
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Layers
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Vulkan
        ${CMAKE_CURRENT_LIST_DIR}/include
        )

target_compile_features(MoltenVK PRIVATE cxx_std_17)
target_link_libraries(MoltenVK PUBLIC moltenvk_shader_converter)
