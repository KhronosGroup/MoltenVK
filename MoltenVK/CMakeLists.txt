

##
## MoltenVK-iOS Files
##

set(MOLTEN_VK_PROJECT_HEADERS
        ${CMAKE_CURRENT_LIST_DIR}/../Common/MVKCommonEnvironment.h
        ${CMAKE_CURRENT_LIST_DIR}/../Common/MVKOSExtensions.h
        ${CMAKE_CURRENT_LIST_DIR}/../Common/MVKStrings.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/API/mvk_datatypes.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/API/mvk_vulkan.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/API/vk_mvk_moltenvk.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdDebug.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdDraw.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdPipeline.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdQueries.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdRenderPass.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdTransfer.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommand.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandBuffer.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandEncoderState.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandEncodingPool.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandPipelineStateFactoryShaderSource.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandPool.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandResourceFactory.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKMTLBufferAllocation.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKMTLResourceBindings.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKBuffer.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKDescriptor.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKDescriptorSet.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKDevice.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKDeviceFeatureStructs.def
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKDeviceMemory.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKFramebuffer.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKImage.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKInstance.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKPipeline.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKPixelFormats.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKQueryPool.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKQueue.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKRenderPass.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKResource.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKShaderModule.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKSurface.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKSwapchain.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKSync.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKVulkanAPIObject.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Layers/MVKExtensions.def
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Layers/MVKExtensions.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Layers/MVKLayers.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/CAMetalLayer+MoltenVK.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLRenderPassDepthAttachmentDescriptor+MoltenVK.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLRenderPassDescriptor+MoltenVK.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLRenderPassStencilAttachmentDescriptor+MoltenVK.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLRenderPipelineDescriptor+MoltenVK.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLSamplerDescriptor+MoltenVK.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLTextureDescriptor+MoltenVK.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MVKGPUCapture.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/NSString+MoltenVK.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKBaseObject.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKBitArray.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKBlockObserver.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKCodec.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKEnvironment.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKFoundation.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKLogging.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKObjectPool.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKSmallVector.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKSmallVectorAllocator.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKWatermark.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKWatermarkShaderSource.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKWatermarkTextureContent.h
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Vulkan/mvk_datatypes.hpp
        )

set(MOLTEN_VK_SOURCES
        ${CMAKE_CURRENT_LIST_DIR}/../Common/MVKOSExtensions.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdDebug.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdDispatch.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdDraw.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdPipeline.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdQueries.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdRenderPass.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCmdTransfer.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandBuffer.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandEncoderState.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandEncodingPool.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandPool.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKCommandResourceFactory.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands/MVKMTLBufferAllocation.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKBuffer.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKDescriptor.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKDescriptorSet.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKDevice.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKDeviceMemory.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKFramebuffer.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKImage.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKInstance.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKPipeline.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKPixelFormats.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKQueryPool.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKQueue.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKRenderPass.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKResource.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKShaderModule.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKSurface.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKSwapchain.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKSync.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects/MVKVulkanAPIObject.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Layers/MVKExtensions.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Layers/MVKLayers.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/CAMetalLayer+MoltenVK.m
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLRenderPassDepthAttachmentDescriptor+MoltenVK.m
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLRenderPassDescriptor+MoltenVK.m
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLRenderPassStencilAttachmentDescriptor+MoltenVK.m
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLRenderPipelineDescriptor+MoltenVK.m
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLSamplerDescriptor+MoltenVK.m
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MTLTextureDescriptor+MoltenVK.m
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/MVKGPUCapture.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS/NSString+MoltenVK.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKBaseObject.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKBlockObserver.m
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKCodec.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKEnvironment.cpp
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKFoundation.cpp
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility/MVKWatermark.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Vulkan/mvk_datatypes.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Vulkan/mvk_api.mm
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Vulkan/vulkan.mm
        )

##
## MoltenVK-iOS
##

add_library(MoltenVK-iOS STATIC
        ${MOLTEN_VK_SOURCES}
        )

target_include_directories(MoltenVK-iOS
        PUBLIC
        ${CMAKE_CURRENT_LIST_DIR}/../Common
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/API
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Layers
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility
        ${CMAKE_CURRENT_LIST_DIR}/include
        )

##
## MoltenVK-tvOS
##

add_library(MoltenVK-tvOS STATIC
        ${MOLTEN_VK_SOURCES}
        )

target_include_directories(MoltenVK-tvOS
        PUBLIC
        ${CMAKE_CURRENT_LIST_DIR}/../Common
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/API
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Commands
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/GPUObjects
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Layers
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/OS
        ${CMAKE_CURRENT_LIST_DIR}/MoltenVK/Utility
        ${CMAKE_CURRENT_LIST_DIR}/include
        )

##
## MoltenVK-macOS
##

add_executable(MoltenVK-macOS
        ${MOLTEN_VK_SOURCES}
        )

target_include_directories(MoltenVK-macOS
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

target_compile_features(MoltenVK-macOS PRIVATE cxx_std_17)
target_link_libraries(MoltenVK-macOS PUBLIC moltenvk_shader_converter)
