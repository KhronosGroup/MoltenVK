################################################################################
# MoltenVK::Common Library
################################################################################

# Find the source files in this directory. We prefer to use GLOB because it is
# easier to maintain in conjunction with the Xcode project file.
file(GLOB_RECURSE SOURCES "*.c" "*.cpp" "*.m" "*.mm")

add_library(MoltenVK_Common STATIC ${SOURCES})
add_library(MoltenVK::Common ALIAS MoltenVK_Common)

target_include_directories(MoltenVK_Common PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")

################################################################################
# Dependencies
################################################################################

find_library(FOUNDATION_LIBRARY Foundation REQUIRED)
find_library(METAL_LIBRARY Metal REQUIRED)
find_library(APPKIT_LIBRARY AppKit REQUIRED)
find_library(IOKIT_LIBRARY IOKit REQUIRED)
find_library(IOSURFACE_LIBRARY IOSurface REQUIRED)
find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
target_link_libraries(MoltenVK_Common PUBLIC
	${FOUNDATION_LIBRARY}
	${METAL_LIBRARY}
	${APPKIT_LIBRARY}
	${IOKIT_LIBRARY}
	${IOSURFACE_LIBRARY}
	${QUARTZCORE_LIBRARY}
)

################################################################################
# Compiler options
################################################################################

# Use C++17
target_compile_features(MoltenVK_Common PUBLIC cxx_std_17)

# Disable annoying warnings
set(MOLTEN_VK_WARNING_FLAGS
	-Wno-deprecated-declarations # deprecated metal API
	-Wno-vla-cxx-extension # variable length arrays in C++ are a Clang extension
)

include(MoltenVK_Filter_Flags)
MoltenVK_Filter_Flags(MOLTEN_VK_WARNING_FLAGS)
target_compile_options(MoltenVK_Common PUBLIC ${MOLTEN_VK_WARNING_FLAGS})