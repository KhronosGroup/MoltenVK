/*
 * MVKCommandBuffer.h
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include "MVKDevice.h"
#include "MVKCommand.h"
#include "MVKCommandEncoderState.h"
#include "MVKMTLBufferAllocation.h"
#include "MVKCmdPipeline.h"
#include "MVKQueryPool.h"
#include "MVKVector.h"
#include <unordered_map>

class MVKCommandPool;
class MVKQueue;
class MVKQueueCommandBufferSubmission;
class MVKCommandEncoder;
class MVKCommandEncodingPool;
class MVKRenderPass;
class MVKFramebuffer;
class MVKRenderSubpass;
class MVKQueryPool;
class MVKPipeline;
class MVKGraphicsPipeline;
class MVKComputePipeline;
class MVKCmdBeginRenderPass;
class MVKCmdEndRenderPass;
class MVKLoadStoreOverrideMixin;

typedef uint64_t MVKMTLCommandBufferID;


#pragma mark -
#pragma mark MVKCommandBuffer

/** Represents a Vulkan command pool. */
class MVKCommandBuffer : public MVKDispatchableVulkanAPIObject,
						 public MVKDeviceTrackingMixin,
						 public MVKLinkableMixin<MVKCommandBuffer> {
public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_COMMAND_BUFFER; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_COMMAND_BUFFER_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _device->getInstance(); }

	/** Prepares this instance to receive commands. */
	VkResult begin(const VkCommandBufferBeginInfo* pBeginInfo);

	/** Resets this instance to allow it to receive new commands. */
	VkResult reset(VkCommandBufferResetFlags flags);

	/** Closes this buffer from receiving commands and prepares for submission to a queue. */
	VkResult end();

	/** Adds the specified execution command at the end of this command buffer. */
	void addCommand(MVKCommand* command);

	/** Returns the number of commands currently in this command buffer. */
	inline uint32_t getCommandCount() { return _commandCount; }

	/** Submit the commands in this buffer as part of the queue submission. */
	void submit(MVKQueueCommandBufferSubmission* cmdBuffSubmit);

    /** Returns whether this command buffer can be submitted to a queue more than once. */
    inline bool getIsReusable() { return _isReusable; }

	/** The command pool that is the source of commands for this buffer. */
	MVKCommandPool* _commandPool;

    /**
     * Metal requires that a visibility buffer is established when a render pass is created, 
     * but Vulkan permits it to be set during a render pass. When the first occlusion query
     * command is added, it sets this value so that it can be applied when the first renderpass
     * is begun. The execution of subsequent occlusion query commmands may change the visibility
     * buffer during command execution, and begin a new Metal renderpass.
     */
    id<MTLBuffer> _initialVisibilityResultMTLBuffer;


#pragma mark Constituent render pass management
    /** Preps metadata for recording render pass */
	void recordBeginRenderPass(MVKCmdBeginRenderPass* mvkBeginRenderPass);
	
	/** Finishes metadata for recording render pass */
	void recordEndRenderPass(MVKCmdEndRenderPass* mvkEndRenderPass);
	
	/** Update the last recorded pipeline if it will end and start a new Metal render pass (ie, in tessellation) */
	void recordBindPipeline(MVKCmdBindPipeline* mvkBindPipeline);
	
	/** Update the last recorded drawcall to determine load/store actions */
	void recordDraw(MVKLoadStoreOverrideMixin* mvkDraw);
	
	/** The most recent recorded begin renderpass */
	MVKCmdBeginRenderPass* _lastBeginRenderPass;
	
	/** The most recent recorded multi-pass (ie, tessellation) pipeline */
	MVKCmdBindPipeline* _lastTessellationPipeline;
	
	/** The most recent recorded multi-pass (ie, tessellation) draw */
	MVKLoadStoreOverrideMixin* _lastTessellationDraw;


#pragma mark Construction

	MVKCommandBuffer(MVKDevice* device) : MVKDeviceTrackingMixin(device) {}

	~MVKCommandBuffer() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKCommandBuffer() method.
     */
    inline VkCommandBuffer getVkCommandBuffer() { return (VkCommandBuffer)getVkHandle(); }

    /**
     * Retrieves the MVKCommandBuffer instance referenced by the VkCommandBuffer handle.
     * This is the compliment of the getVkCommandBuffer() method.
     */
    static inline MVKCommandBuffer* getMVKCommandBuffer(VkCommandBuffer vkCommandBuffer) {
        return (MVKCommandBuffer*)getDispatchableObject(vkCommandBuffer);
    }

protected:
	friend class MVKCommandEncoder;
	friend class MVKCommandPool;

	MVKBaseObject* getBaseObject() override { return this; };
	void propogateDebugName() override {}
	void init(const VkCommandBufferAllocateInfo* pAllocateInfo);
	bool canExecute();
	bool canPrefill();
	void prefill();
	void clearPrefilledMTLCommandBuffer();

	MVKCommand* _head = nullptr;
	MVKCommand* _tail = nullptr;
	uint32_t _commandCount;
	std::atomic_flag _isExecutingNonConcurrently;
	VkCommandBufferInheritanceInfo _secondaryInheritanceInfo;
	id<MTLCommandBuffer> _prefilledMTLCmdBuffer = nil;
	bool _isSecondary;
	bool _doesContinueRenderPass;
	bool _canAcceptCommands;
	bool _isReusable;
	bool _supportsConcurrentExecution;
	bool _wasExecuted;
};


#pragma mark -
#pragma mark MVKCommandEncoder

// The following commands can be issued both inside and outside a renderpass and their state must
// span multiple MTLRenderCommandEncoders, to allow state to be set before a renderpass, and to
// allow more than one MTLRenderCommandEncoder to be used for a single Vulkan renderpass or subpass.
//
// + vkCmdBindPipeline() : _graphicsPipelineState & _computePipelineState
// + vkCmdBindDescriptorSets() : _graphicsResourcesState & _computeResourcesState
// + vkCmdBindVertexBuffers() : _graphicsResourcesState
// + vkCmdBindIndexBuffer() : _graphicsResourcesState
// + vkCmdPushConstants() : _vertexPushConstants & _tessCtlPushConstants & _tessEvalPushConstants & _fragmentPushConstants & _computePushConstants
// + vkCmdSetViewport() : _viewportState
// + vkCmdSetDepthBias() : _depthBiasState
// + vkCmdSetScissor() : _scissorState
// + vkCmdSetStencilCompareMask() : _depthStencilState
// + vkCmdSetStencilWriteMask() : _depthStencilState
// + vkCmdSetStencilReference() : _stencilReferenceValueState
// + vkCmdSetBlendConstants() : _blendColorState
// + vkCmdBeginQuery() : _occlusionQueryState
// + vkCmdEndQuery() : _occlusionQueryState
// + vkCmdPipelineBarrier() : handled via textureBarrier and MTLBlitCommandEncoder
// + vkCmdWriteTimestamp() : doesn't affect MTLCommandEncoders
// + vkCmdExecuteCommands() : state managed by embedded commands
// - vkCmdSetLineWidth() - unsupported by Metal
// - vkCmdSetDepthBounds() - unsupported by Metal
// - vkCmdWaitEvents() - unsupported by Metal

// The above list of Vulkan commands covers the following corresponding MTLRenderCommandEncoder state:
// + setBlendColorRed : _blendColorState
// + setCullMode : _graphicsPipelineState
// + setDepthBias : _depthBiasState
// + setDepthClipMode : _graphicsPipelineState
// + setDepthStencilState : _depthStencilState
// + setFrontFacingWinding : _graphicsPipelineState
// + setRenderPipelineState : _graphicsPipelineState
// + setScissorRect : _scissorState
// + setStencilFrontReferenceValue : _stencilReferenceValueState
// + setStencilReferenceValue (unused) : _stencilReferenceValueState
// + setTriangleFillMode : _graphicsPipelineState
// + setViewport : _viewportState
// + setVisibilityResultMode : _occlusionQueryState
// + setVertexBuffer : _graphicsResourcesState & _vertexPushConstants & _tessEvalPushConstants
// + setVertexBuffers (unused) : _graphicsResourcesState
// + setVertexBytes : _vertexPushConstants & _tessEvalPushConstants
// + setVertexBufferOffset (unused) : _graphicsResourcesState
// + setVertexTexture : _graphicsResourcesState
// + setVertexTextures (unused) : _graphicsResourcesState
// + setVertexSamplerState : _graphicsResourcesState
// + setVertexSamplerStates : (unused) : _graphicsResourcesState
// + setFragmentBuffer : _graphicsResourcesState & _fragmentPushConstants
// + setFragmentBuffers (unused) : _graphicsResourcesState
// + setFragmentBytes : _fragmentPushConstants
// + setFragmentBufferOffset (unused) : _graphicsResourcesState
// + setFragmentTexture : _graphicsResourcesState
// + setFragmentTextures (unused) : _graphicsResourcesState
// + setFragmentSamplerState : _graphicsResourcesState
// + setFragmentSamplerStates : (unused) : _graphicsResourcesState

// The above list of Vulkan commands covers the following corresponding MTLComputeCommandEncoder state:
// + setComputePipelineState : _computePipelineState & _graphicsPipelineState
// + setBuffer : _computeResourcesState & _computePushConstants & _graphicsResourcesState & _tessCtlPushConstants
// + setBuffers (unused) : _computeResourcesState & _graphicsResourcesState
// + setBytes : _computePushConstants & _tessCtlPushConstants
// + setBufferOffset (unused) : _computeResourcesState & _graphicsResourcesState
// + setTexture : _computeResourcesState & _graphicsResourcesState
// + setTextures (unused) : _computeResourcesState & _graphicsResourcesState
// + setSamplerState : _computeResourcesState & _graphicsResourcesState
// + setSamplerStates : (unused) : _computeResourcesState & _graphicsResourcesState


/*** Holds a collection of active queries for each query pool. */
typedef std::unordered_map<MVKQueryPool*, MVKVectorInline<uint32_t, kMVKDefaultQueryCount>> MVKActivatedQueries;

/** 
 * MVKCommandEncoder uses a visitor design pattern iterate the commands in a MVKCommandBuffer, 
 * tracking and caching dynamic encoding state, and encoding the commands onto Metal MTLCommandBuffers.
 *
 * Much of the dynamic cached encoding state has public access and is accessed directly
 * from the commands in the command buffer.
 */
class MVKCommandEncoder : public MVKBaseDeviceObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _cmdBuffer->getVulkanAPIObject(); };

	/** Encode commands from the command buffer onto the Metal command buffer. */
	void encode(id<MTLCommandBuffer> mtlCmdBuff);

	/** Encode commands from the specified secondary command buffer onto the Metal command buffer. */
	void encodeSecondary(MVKCommandBuffer* secondaryCmdBuffer);

	/** Begins a render pass and establishes initial draw state. */
	void beginRenderpass(VkSubpassContents subpassContents,
						 MVKRenderPass* renderPass,
						 MVKFramebuffer* framebuffer,
						 VkRect2D& renderArea,
						 MVKVector<VkClearValue>* clearValues,
						 bool loadOverride = false,
						 bool storeOverride = false);

	/** Begins the next render subpass. */
	void beginNextSubpass(VkSubpassContents renderpassContents);

	/** Begins a Metal render pass for the current render subpass. */
	void beginMetalRenderPass(bool loadOverride = false, bool storeOverride = false);

	/** Returns the render subpass that is currently active. */
	MVKRenderSubpass* getSubpass();

    /** Binds a pipeline to a bind point. */
    void bindPipeline(VkPipelineBindPoint pipelineBindPoint, MVKPipeline* pipeline);

	/** Encodes an operation to signal an event to a status. */
	void signalEvent(MVKEvent* mvkEvent, bool status);

    /**
     * If a pipeline is currently bound, returns whether the current pipeline permits dynamic
     * setting of the specified state. If no pipeline is currently bound, returns true.
     */
    bool supportsDynamicState(VkDynamicState state);

	/** Clips the scissor to ensure it fits inside the render area.  */
	MTLScissorRect clipToRenderArea(MTLScissorRect mtlScissor);

	/** Called by each graphics draw command to establish any outstanding state just prior to performing the draw. */
	void finalizeDrawState(MVKGraphicsStage stage);

    /** Called by each compute dispatch command to establish any outstanding state just prior to performing the dispatch. */
    void finalizeDispatchState();

	/** Ends the current renderpass. */
	void endRenderpass();

	/** 
	 * Ends all encoding operations on the current Metal command encoder.
	 *
	 * This must be called once all encoding is complete, and prior 
	 * to each switch between render, compute, and BLIT encoding.
	 */
	void endCurrentMetalEncoding();

	/** Ends encoding operations on the current Metal command encoder if it is a rendering encoder. */
	void endMetalRenderEncoding();

	/** 
	 * Returns trhe current Metal compute encoder for the specified use,
	 * which determines the label assigned to the returned encoder.
	 *
	 * If the current encoder is not a compute encoder, this function ends current before 
	 * beginning compute encoding.
	 */
	id<MTLComputeCommandEncoder> getMTLComputeEncoder(MVKCommandUse cmdUse);

	/**
	 * Returns the current Metal BLIT encoder for the specified use,
     * which determines the label assigned to the returned encoder.
	 *
	 * If the current encoder is not a BLIT encoder, this function ends 
     * the current encoder before beginning BLIT encoding.
	 */
	id<MTLBlitCommandEncoder> getMTLBlitEncoder(MVKCommandUse cmdUse);

	/**
	 * Returns the current Metal encoder, which may be any of the Metal render,
	 * comupte, or Blit encoders, or nil if no encoding is currently occurring.
	 */
	id<MTLCommandEncoder> getMTLEncoder();

	/** Returns the push constants associated with the specified shader stage. */
	MVKPushConstantsCommandEncoderState* getPushConstants(VkShaderStageFlagBits shaderStage);

    /** Copy bytes into the Metal encoder at a Metal vertex buffer index. */
    void setVertexBytes(id<MTLRenderCommandEncoder> mtlEncoder, const void* bytes, NSUInteger length, uint32_t mtlBuffIndex);

    /** Copy bytes into the Metal encoder at a Metal fragment buffer index. */
    void setFragmentBytes(id<MTLRenderCommandEncoder> mtlEncoder, const void* bytes, NSUInteger length, uint32_t mtlBuffIndex);

    /** Copy bytes into the Metal encoder at a Metal compute buffer index. */
    void setComputeBytes(id<MTLComputeCommandEncoder> mtlEncoder, const void* bytes, NSUInteger length, uint32_t mtlBuffIndex);

    /** Get a temporary MTLBuffer that will be returned to a pool after the command buffer is finished. */
    const MVKMTLBufferAllocation* getTempMTLBuffer(NSUInteger length);

    /** Returns the command encoding pool. */
    MVKCommandEncodingPool* getCommandEncodingPool();

#pragma mark Queries

    /** Begins an occulusion query. */
    void beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags);

    /** Ends the current occulusion query. */
    void endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query);

    /** Marks a timestamp for the specified query. */
    void markTimestamp(MVKQueryPool* pQueryPool, uint32_t query);

#pragma mark Dynamic encoding state accessed directly

    /** A reference to the Metal features supported by the device. */
    const MVKPhysicalDeviceMetalFeatures* _pDeviceMetalFeatures;

    /** A reference to the Vulkan features supported by the device. */
    const VkPhysicalDeviceFeatures* _pDeviceFeatures;

    /** Pointer to the properties of the device. */
    const VkPhysicalDeviceProperties* _pDeviceProperties;

    /** Pointer to the memory properties of the device. */
    const VkPhysicalDeviceMemoryProperties* _pDeviceMemoryProperties;

	/** The command buffer whose commands are being encoded. */
	MVKCommandBuffer* _cmdBuffer;

	/** The framebuffer to which rendering is currently directed. */
	MVKFramebuffer* _framebuffer;

	/** The current Metal command buffer. */
	id<MTLCommandBuffer> _mtlCmdBuffer;

	/** The current Metal render encoder. */
	id<MTLRenderCommandEncoder> _mtlRenderEncoder;

    /** Tracks the current graphics pipeline bound to the encoder. */
    MVKPipelineCommandEncoderState _graphicsPipelineState;

    /** Tracks the current compute pipeline bound to the encoder. */
    MVKPipelineCommandEncoderState _computePipelineState;

    /** Tracks the current viewport state of the encoder. */
    MVKViewportCommandEncoderState _viewportState;

    /** Tracks the current scissor state of the encoder. */
    MVKScissorCommandEncoderState _scissorState;

    /** Tracks the current depth bias state of the encoder. */
    MVKDepthBiasCommandEncoderState _depthBiasState;

    /** Tracks the current blend color state of the encoder. */
    MVKBlendColorCommandEncoderState _blendColorState;

    /** Tracks the current depth stencil state of the encoder. */
    MVKDepthStencilCommandEncoderState _depthStencilState;

    /** Tracks the current stencil reference value state of the encoder. */
    MVKStencilReferenceValueCommandEncoderState _stencilReferenceValueState;

    /** Tracks the current graphics resources state of the encoder. */
    MVKGraphicsResourcesCommandEncoderState _graphicsResourcesState;

    /** Tracks the current compute resources state of the encoder. */
    MVKComputeResourcesCommandEncoderState _computeResourcesState;

	/** The type of primitive that will be rendered. */
	MTLPrimitiveType _mtlPrimitiveType;

    /** The size of the threadgroup for the compute shader. */
    MTLSize _mtlThreadgroupSize;

	/** Indicates whether the current render subpass is rendering to an array (layered) framebuffer. */
	bool _isUsingLayeredRendering;


#pragma mark Construction

	MVKCommandEncoder(MVKCommandBuffer* cmdBuffer);

protected:
    void addActivatedQuery(MVKQueryPool* pQueryPool, uint32_t query);
    void finishQueries();
	void setSubpass(VkSubpassContents subpassContents, uint32_t subpassIndex, bool loadOverride = false, bool storeOverride = false);
	void clearRenderArea();
    const MVKMTLBufferAllocation* copyToTempMTLBufferAllocation(const void* bytes, NSUInteger length);
    NSString* getMTLRenderCommandEncoderName();

	VkSubpassContents _subpassContents;
	MVKRenderPass* _renderPass;
	uint32_t _renderSubpassIndex;
	VkRect2D _renderArea;
    MVKActivatedQueries* _pActivatedQueries;
	MVKVectorInline<VkClearValue, 8> _clearValues;
	id<MTLComputeCommandEncoder> _mtlComputeEncoder;
	MVKCommandUse _mtlComputeEncoderUse;
	id<MTLBlitCommandEncoder> _mtlBlitEncoder;
    MVKCommandUse _mtlBlitEncoderUse;
	MVKPushConstantsCommandEncoderState _vertexPushConstants;
	MVKPushConstantsCommandEncoderState _tessCtlPushConstants;
	MVKPushConstantsCommandEncoderState _tessEvalPushConstants;
	MVKPushConstantsCommandEncoderState _fragmentPushConstants;
	MVKPushConstantsCommandEncoderState _computePushConstants;
    MVKOcclusionQueryCommandEncoderState _occlusionQueryState;
    uint32_t _flushCount = 0;
	bool _isRenderingEntireAttachment;
};


#pragma mark -
#pragma mark Support functions

/** Returns a name, suitable for use as a MTLRenderCommandEncoder label, based on the MVKCommandUse. */
NSString* mvkMTLRenderCommandEncoderLabel(MVKCommandUse cmdUse);

/** Returns a name, suitable for use as a MTLBlitCommandEncoder label, based on the MVKCommandUse. */
NSString* mvkMTLBlitCommandEncoderLabel(MVKCommandUse cmdUse);

/** Returns a name, suitable for use as a MTLComputeCommandEncoder label, based on the MVKCommandUse. */
NSString* mvkMTLComputeCommandEncoderLabel(MVKCommandUse cmdUse);

