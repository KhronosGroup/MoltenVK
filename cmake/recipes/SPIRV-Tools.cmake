# SPIRV-Tools (https://github.com/KhronosGroup/SPIRV-Tools)
# License: Apache-2.0
if(TARGET SPIRV-Tools::SPIRV-Tools)
    return()
endif()

message(STATUS "External: creating target 'SPIRV-Tools::SPIRV-Tools'")

# SPIRV-Tools requires SPIRV-Headers
include(SPIRV-Headers)

set(SPIRV_TOOLS_BUILD_STATIC ON)

# Read Git commit hash from ExternalRevisions file
file(READ "${MOLTEN_VK_EXTERNAL_REVISIONS_DIR}/SPIRV-Tools_repo_revision" SPIRV_TOOLS_COMMIT_HASH)
string(STRIP "${SPIRV_TOOLS_COMMIT_HASH}" SPIRV_TOOLS_COMMIT_HASH)

include(CPM)
CPMAddPackage("gh:KhronosGroup/SPIRV-Tools#${SPIRV_TOOLS_COMMIT_HASH}")

add_library(SPIRV-Tools::SPIRV-Tools ALIAS SPIRV-Tools-static)

# The optimizer is a library of its own. The Xcode build gets it inside the prebuilt archive, but
# this one has to ask for it by name, or a pass that rewrites shaders finds no symbols to link.
#
# Such a pass also includes headers the optimizer does not publish, so where its sources and the
# tables generated beside them ended up is published here. They are wherever CPM fetched them,
# which is not the External directory this build leaves empty.
add_library(SPIRV-Tools::opt ALIAS SPIRV-Tools-opt)
set(SPIRV_TOOLS_OPT_INCLUDE_DIRS "${SPIRV-Tools_SOURCE_DIR}" "${SPIRV-Tools_BINARY_DIR}"
    CACHE INTERNAL "Headers the SPIRV-Tools optimizer does not publish, which its passes include.")
