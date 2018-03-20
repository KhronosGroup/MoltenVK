project(MoltenVK)
cmake_minimum_required(VERSION 3.10)
set(CMAKE_CXX_STANDARD 14)

include_directories(MoltenVKShaderConverter)

include_directories(Common)
include_directories(MoltenVK/include)
include_directories(MoltenVK/MoltenVK/API)
include_directories(MoltenVK/MoltenVK/Commands)
include_directories(MoltenVK/MoltenVK/GPUObjects)
include_directories(MoltenVK/MoltenVK/Loader)
include_directories(MoltenVK/MoltenVK/Utility)
include_directories(MoltenVK/MoltenVK/Vulkan)

set(
  SOURCES
  MoltenVK/MoltenVK/GPUObjects/MVKQueryPool.mm
  MoltenVK/MoltenVK/GPUObjects/MVKRenderPass.mm
  MoltenVK/MoltenVK/GPUObjects/MVKDeviceMemory.mm
  MoltenVK/MoltenVK/GPUObjects/MVKSwapchain.mm
  MoltenVK/MoltenVK/GPUObjects/MVKBuffer.mm
  MoltenVK/MoltenVK/GPUObjects/MVKSurface.mm
  MoltenVK/MoltenVK/GPUObjects/MVKPipeline.mm
  MoltenVK/MoltenVK/GPUObjects/MVKSync.mm
  MoltenVK/MoltenVK/GPUObjects/MVKImage.mm
  MoltenVK/MoltenVK/GPUObjects/MVKShaderModule.mm
  MoltenVK/MoltenVK/GPUObjects/MVKFramebuffer.mm
  MoltenVK/MoltenVK/GPUObjects/MVKResource.mm
  MoltenVK/MoltenVK/GPUObjects/MVKQueue.mm
  MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm
  MoltenVK/MoltenVK/GPUObjects/MVKInstance.mm
  MoltenVK/MoltenVK/GPUObjects/MVKDescriptorSet.mm
  MoltenVK/MoltenVK/Loader/MVKLayers.mm
  MoltenVK/MoltenVK/Vulkan/mvk_datatypes.mm
  MoltenVK/MoltenVK/Vulkan/vk_mvk_moltenvk.mm
  MoltenVK/MoltenVK/Vulkan/vulkan.mm
  MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm
  MoltenVK/MoltenVK/Commands/MVKCommandEncodingPool.mm
  MoltenVK/MoltenVK/Commands/MVKCommandPool.mm
  MoltenVK/MoltenVK/Commands/MVKCmdQueries.mm
  MoltenVK/MoltenVK/Commands/MVKMTLBufferAllocation.mm
  MoltenVK/MoltenVK/Commands/MVKCmdDraw.mm
  MoltenVK/MoltenVK/Commands/MVKCmdPipeline.mm
  MoltenVK/MoltenVK/Commands/MVKCmdRenderPass.mm
  MoltenVK/MoltenVK/Commands/MVKCmdTransfer.mm
  MoltenVK/MoltenVK/Commands/MVKCommand.mm
  MoltenVK/MoltenVK/Commands/MVKCmdDispatch.mm
  MoltenVK/MoltenVK/Commands/MVKCommandResourceFactory.mm
  MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm
  MoltenVK/MoltenVK/Utility/MVKWatermark.mm
  MoltenVK/MoltenVK/Utility/MVKOSExtensions.mm
  MoltenVK/MoltenVK/Utility/MVKFoundation.mm
  MoltenVK/MoltenVK/Utility/MVKBaseObject.cpp
)

add_library(MoltenVK ${SOURCES})

add_custom_target(
    fetchDependencies ALL
    COMMENT "Fetching dependencies"
    COMMAND ${CMAKE_SOURCE_DIR}/External/fetchDependencies
)

add_dependencies(MoltenVK fetchDependencies)