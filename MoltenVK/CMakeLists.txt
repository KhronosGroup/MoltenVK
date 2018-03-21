project(MoltenVK)
cmake_minimum_required(VERSION 3.10)
set(CMAKE_CXX_STANDARD 14)

include_directories(
  ${MVK_COMMON_INCLUDES}
  ${MVK_SHADER_CONVERTER_INCLUDES}
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/API
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Loader
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Utility
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Vulkan
)

set(
  MVK_SOURCES
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKQueryPool.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKRenderPass.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKDeviceMemory.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKSwapchain.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKBuffer.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKSurface.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKPipeline.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKSync.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKImage.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKShaderModule.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKFramebuffer.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKResource.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKQueue.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKDevice.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKInstance.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/GPUObjects/MVKDescriptorSet.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Loader/MVKLayers.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Vulkan/mvk_datatypes.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Vulkan/vk_mvk_moltenvk.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Vulkan/vulkan.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCommandBuffer.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCommandEncodingPool.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCommandPool.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCmdQueries.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKMTLBufferAllocation.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCmdDraw.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCmdPipeline.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCmdRenderPass.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCmdTransfer.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCommand.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCmdDispatch.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCommandResourceFactory.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Commands/MVKCommandEncoderState.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Utility/MVKWatermark.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Utility/MVKOSExtensions.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Utility/MVKFoundation.mm
  ${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/Utility/MVKBaseObject.cpp
)

add_library(MoltenVK ${MVK_SOURCES})
add_dependencies(MoltenVK MoltenVK-External)
