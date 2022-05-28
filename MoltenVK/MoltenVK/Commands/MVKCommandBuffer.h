/*
 * MVKCommandBuffer.h
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKRenderPass.h"
#include "MVKCmdPipeline.h"
#include "MVKQueryPool.h"
#include "MVKSmallVector.h"
#include <unordered_map>

class MVKCommandPool;
class MVKQueueCommandBufferSubmission;
class MVKCommandEncoder;
class MVKCommandEncodingPool;
class MVKCmdBeginRenderPassBase;
class MVKCmdNextSubpass;
class MVKRenderPass;
class MVKFramebuffer;
class MVKRenderSubpass;
class MVKQueryPool;
class MVKPipeline;
class MVKGraphicsPipeline;
class MVKComputePipeline;

typedef uint64_t MVKMTLCommandBufferID;


#pragma mark -
#pragma mark MVKCommandEncodingContext

/** Context for tracking information across multiple encodings. */
typedef struct MVKCommandEncodingContext {
	NSUInteger mtlVisibilityResultOffset = 0;
	const MVKMTLBufferAllocation* visibilityResultBuffer = nullptr;

	MVKRenderPass* getRenderPass() { return _renderPass; }
	MVKFramebuffer* getFramebuffer() { return _framebuffer; }
	void setRenderingContext(MVKRenderPass* renderPass, MVKFramebuffer* framebuffer);
	VkRenderingFlags getRenderingFlags() { return _renderPass ? _renderPass->getRenderingFlags() : 0; }
	~MVKCommandEncodingContext();

private:
	MVKRenderPass* _renderPass = nullptr;
	MVKFramebuffer* _framebuffer = nullptr;
} MVKCommandEncodingContext;


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

	/** Returns the command pool backing this command buffer. */
	inline MVKCommandPool* getCommandPool() { return _commandPool; }

	/** Submit the commands in this buffer as part of the queue submission. */
	void submit(MVKQueueCommandBufferSubmission* cmdBuffSubmit, MVKCommandEncodingContext* pEncodingContext);

    /** Returns whether this command buffer can be submitted to a queue more than once. */
    inline bool getIsReusable() { return _isReusable; }

    /**
     * Metal requires that a visibility buffer is established when a render pass is created, 
     * but Vulkan permits it to be set during a render pass. When the first occlusion query
     * command is added, it sets this value so that it can be applied when the first renderpass
     * is begun.
     */
    bool _needsVisibilityResultMTLBuffer;

	/** Called when a MVKCmdExecuteCommands is added to this command buffer. */
	void recordExecuteCommands(const MVKArrayRef<MVKCommandBuffer*> secondaryCommandBuffers);

	/** Called when a timestamp command is added. */
	void recordTimestampCommand();


#pragma mark Tessellation constituent command management

	/** Update the last recorded pipeline with tessellation shaders */
	void recordBindPipeline(MVKCmdBindPipeline* mvkBindPipeline);

	/** The most recent recorded tessellation pipeline */
	MVKCmdBindPipeline* _lastTessellationPipeline;


#pragma mark Multiview render pass command management

	/** Update the last recorded multiview render pass */
	void recordBeginRenderPass(MVKCmdBeginRenderPassBase* mvkBeginRenderPass);

	/** Update the last recorded multiview subpass */
	void recordNextSubpass();

	/** Forget the last recorded multiview render pass */
	void recordEndRenderPass();

	/** The most recent recorded multiview render subpass */
	MVKRenderSubpass* _lastMultiviewSubpass;

	/** Returns the currently active multiview render subpass, even for secondary command buffers */
	MVKRenderSubpass* getLastMultiviewSubpass();


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
	void propagateDebugName() override {}
	void init(const VkCommandBufferAllocateInfo* pAllocateInfo);
	bool canExecute();
	bool canPrefill();
	void prefill();
	void clearPrefilledMTLCommandBuffer();
    void releaseCommands(MVKCommand* command);
	void releaseRecordedCommands();
    void flushImmediateCmdEncoder();

	MVKCommand* _head = nullptr;
	MVKCommand* _tail = nullptr;
	MVKSmallVector<VkFormat, kMVKDefaultAttachmentCount> _colorAttachmentFormats;
	MVKCommandPool* _commandPool;
	VkCommandBufferInheritanceInfo _secondaryInheritanceInfo;
	VkCommandBufferInheritanceRenderingInfo _inerhitanceRenderingInfo;
	id<MTLCommandBuffer> _prefilledMTLCmdBuffer = nil;
    MVKCommandEncodingContext* _immediateCmdEncodingContext = nullptr;
    MVKCommandEncoder* _immediateCmdEncoder = nullptr;
	uint32_t _commandCount;
	std::atomic_flag _isExecutingNonConcurrently;
	bool _isSecondary;
	bool _doesContinueRenderPass;
	bool _canAcceptCommands;
	bool _isReusable;
	bool _supportsConcurrentExecution;
	bool _wasExecuted;
	bool _hasStageCounterTimestampCommand;
};


#pragma mark -
#pragma mark MVKCommandEncoder

/*** Holds a collection of active queries for each query pool. */
typedef std::unordered_map<MVKQueryPool*, MVKSmallVector<uint32_t, kMVKDefaultQueryCount>> MVKActivatedQueries;

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
	void encode(id<MTLCommandBuffer> mtlCmdBuff, MVKCommandEncodingContext* pEncodingContext);
    
    void beginEncoding(id<MTLCommandBuffer> mtlCmdBuff, MVKCommandEncodingContext* pEncodingContext);
    void encodeCommands(MVKCommand* command);
    void endEncoding();

	/** Encode commands from the specified secondary command buffer onto the Metal command buffer. */
	void encodeSecondary(MVKCommandBuffer* secondaryCmdBuffer);

	/** Begins a render pass and establishes initial draw state. */
	void beginRenderpass(MVKCommand* passCmd,
						 VkSubpassContents subpassContents,
						 MVKRenderPass* renderPass,
						 MVKFramebuffer* framebuffer,
						 const VkRect2D& renderArea,
						 MVKArrayRef<VkClearValue> clearValues,
						 MVKArrayRef<MVKImageView*> attachments,
						 MVKArrayRef<MVKArrayRef<MTLSamplePosition>> subpassSamplePositions);

	/** Begins the next render subpass. */
	void beginNextSubpass(MVKCommand* subpassCmd, VkSubpassContents renderpassContents);

	/** Begins the next multiview Metal render pass. */
	void beginNextMultiviewPass();

	/** Sets the dynamic custom sample positions to use when rendering. */
	void setDynamicSamplePositions(MVKArrayRef<MTLSamplePosition> dynamicSamplePositions);

	/** Begins dynamic rendering. */
	void beginRendering(MVKCommand* rendCmd, const VkRenderingInfo* pRenderingInfo);

	/** Begins a Metal render pass for the current render subpass. */
	void beginMetalRenderPass(MVKCommandUse cmdUse);

	/** If a render encoder is active, encodes store actions for all attachments to it. */
	void encodeStoreActions(bool storeOverride = false);

	/** Returns whether or not we are presently in a render pass. */
	bool isInRenderPass() { return _pEncodingContext->getRenderPass() != nullptr; }

	/** Returns the render subpass that is currently active. */
	MVKRenderSubpass* getSubpass();

	/** The extent of current framebuffer.*/
	VkExtent2D getFramebufferExtent();

	/** The layer count of current framebuffer.*/
	uint32_t getFramebufferLayerCount();

	/** Returns the index of the currently active multiview subpass, or zero if the current render pass is not multiview. */
	uint32_t getMultiviewPassIndex();

	/** Begins a Metal compute encoding. */
	void beginMetalComputeEncoding(MVKCommandUse cmdUse);

    /** Binds a pipeline to a bind point. */
    void bindPipeline(VkPipelineBindPoint pipelineBindPoint, MVKPipeline* pipeline);

	/** Binds the descriptor set to the index at the bind point. */
	void bindDescriptorSet(VkPipelineBindPoint pipelineBindPoint,
						   uint32_t descSetIndex,
						   MVKDescriptorSet* descSet,
						   MVKShaderResourceBinding& dslMTLRezIdxOffsets,
						   MVKArrayRef<uint32_t> dynamicOffsets,
						   uint32_t& dynamicOffsetIndex);

	/** Encodes an operation to signal an event to a status. */
	void signalEvent(MVKEvent* mvkEvent, bool status);

    /**
     * If a pipeline is currently bound, returns whether the current pipeline permits dynamic
     * setting of the specified state. If no pipeline is currently bound, returns true.
     */
    bool supportsDynamicState(VkDynamicState state);

	/** Clips the scissor to ensure it fits inside the render area.  */
	VkRect2D clipToRenderArea(VkRect2D scissor);

	/** Called by each graphics draw command to establish any outstanding state just prior to performing the draw. */
	void finalizeDrawState(MVKGraphicsStage stage);

    /** Called by each compute dispatch command to establish any outstanding state just prior to performing the dispatch. */
    void finalizeDispatchState();

	/** Ends the current renderpass. */
	void endRenderpass();

	/** Ends the current dymamic rendering. */
	void endRendering();

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
	 * Returns the current Metal compute encoder for the specified use,
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
	 * compute, or Blit encoders, or nil if no encoding is currently occurring.
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
    const MVKMTLBufferAllocation* getTempMTLBuffer(NSUInteger length, bool isPrivate = false, bool isDedicated = false);

	/** Copy the bytes to a temporary MTLBuffer that will be returned to a pool after the command buffer is finished. */
	const MVKMTLBufferAllocation* copyToTempMTLBufferAllocation(const void* bytes, NSUInteger length, bool isDedicated = false);

    /** Returns the command encoding pool. */
    MVKCommandEncodingPool* getCommandEncodingPool();

#pragma mark Queries

    /** Begins an occlusion query. */
    void beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags);

    /** Ends the current occlusion query. */
    void endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query);

    /** Marks a timestamp for the specified query. */
    void markTimestamp(MVKTimestampQueryPool* pQueryPool, uint32_t query);

    /** Reset a range of queries. */
    void resetQueries(MVKQueryPool* pQueryPool, uint32_t firstQuery, uint32_t queryCount);

#pragma mark Dynamic encoding state accessed directly

	/** Context for tracking information across multiple encodings. */
	MVKCommandEncodingContext* _pEncodingContext;

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

	/** Indicates whether the current render subpass is able to render to an array (layered) framebuffer. */
	bool _canUseLayeredRendering;

	/** Indicates whether the current draw is an indexed draw. */
	bool _isIndexedDraw;

#pragma mark Construction

	MVKCommandEncoder(MVKCommandBuffer* cmdBuffer);

protected:
    void addActivatedQueries(MVKQueryPool* pQueryPool, uint32_t query, uint32_t queryCount);
    void finishQueries();
	void setSubpass(MVKCommand* passCmd, VkSubpassContents subpassContents, uint32_t subpassIndex);
	void clearRenderArea();
    NSString* getMTLRenderCommandEncoderName(MVKCommandUse cmdUse);
	void encodeGPUCounterSample(MVKGPUCounterQueryPool* mvkQryPool, uint32_t sampleIndex, MVKCounterSamplingFlags samplingPoints);
	void encodeTimestampStageCounterSamples();
	id<MTLFence> getStageCountersMTLFence();
	MVKArrayRef<MTLSamplePosition> getCustomSamplePositions();

	typedef struct GPUCounterQuery {
		MVKGPUCounterQueryPool* queryPool = nullptr;
		uint32_t query = 0;
	} GPUCounterQuery;

	VkRect2D _renderArea;
	MVKCommand* _lastMultiviewPassCmd;
    MVKActivatedQueries* _pActivatedQueries;
	MVKSmallVector<GPUCounterQuery, 16> _timestampStageCounterQueries;
	MVKSmallVector<VkClearValue, kMVKDefaultAttachmentCount> _clearValues;
	MVKSmallVector<MVKImageView*, kMVKDefaultAttachmentCount> _attachments;
	MVKSmallVector<MTLSamplePosition> _dynamicSamplePositions;
	MVKSmallVector<MVKSmallVector<MTLSamplePosition>> _subpassSamplePositions;
	id<MTLComputeCommandEncoder> _mtlComputeEncoder;
	id<MTLBlitCommandEncoder> _mtlBlitEncoder;
	id<MTLFence> _stageCountersMTLFence;
	MVKPushConstantsCommandEncoderState _vertexPushConstants;
	MVKPushConstantsCommandEncoderState _tessCtlPushConstants;
	MVKPushConstantsCommandEncoderState _tessEvalPushConstants;
	MVKPushConstantsCommandEncoderState _fragmentPushConstants;
	MVKPushConstantsCommandEncoderState _computePushConstants;
    MVKOcclusionQueryCommandEncoderState _occlusionQueryState;
	VkSubpassContents _subpassContents;
	MVKCommandUse _mtlComputeEncoderUse;
	MVKCommandUse _mtlBlitEncoderUse;
	uint32_t _renderSubpassIndex;
	uint32_t _multiviewPassIndex;
    uint32_t _flushCount = 0;
	bool _isRenderingEntireAttachment;
};


#pragma mark -
#pragma mark Support functions

/** Returns a name, suitable for use as a MTLCommandBuffer label, based on the MVKCommandUse. */
NSString* mvkMTLCommandBufferLabel(MVKCommandUse cmdUse);

/** Returns a name, suitable for use as a MTLRenderCommandEncoder label, based on the MVKCommandUse. */
NSString* mvkMTLRenderCommandEncoderLabel(MVKCommandUse cmdUse);

/** Returns a name, suitable for use as a MTLBlitCommandEncoder label, based on the MVKCommandUse. */
NSString* mvkMTLBlitCommandEncoderLabel(MVKCommandUse cmdUse);

/** Returns a name, suitable for use as a MTLComputeCommandEncoder label, based on the MVKCommandUse. */
NSString* mvkMTLComputeCommandEncoderLabel(MVKCommandUse cmdUse);
