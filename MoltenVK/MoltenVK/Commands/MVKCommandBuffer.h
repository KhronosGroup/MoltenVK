/*
 * MVKCommandBuffer.h
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

struct BarrierFenceSlots {
	uint32_t updateDirtyBits = ~0;
	int update[kMVKBarrierStageCount] = {};
	int wait[kMVKBarrierStageCount][kMVKBarrierStageCount] = {};
};

/** Context for tracking information across multiple encodings. */
typedef struct MVKCommandEncodingContext {
	NSUInteger mtlVisibilityResultOffset = 0;
	const MVKMTLBufferAllocation* visibilityResultBuffer = nullptr;
	BarrierFenceSlots fenceSlots;

	void syncFences(MVKDevice *device, id<MTLCommandBuffer> mtlCommandBuffer);
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
#pragma mark MVKCurrentSubpassInfo

/** Tracks current render subpass information. */
typedef struct MVKCurrentSubpassInfo {
	MVKRenderPass* renderpass;
	uint32_t subpassIndex;
	uint32_t subpassViewMask;

	void beginRenderpass(MVKRenderPass* rp);
	void nextSubpass();
	void beginRendering(uint32_t viewMask);

private:
	void updateViewMask();
} MVKCurrentSubpassInfo;


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
	uint32_t getCommandCount() { return _commandCount; }

	/** Returns the command pool backing this command buffer. */
	MVKCommandPool* getCommandPool() { return _commandPool; }

	/** Submit the commands in this buffer as part of the queue submission. */
	void submit(MVKQueueCommandBufferSubmission* cmdBuffSubmit, MVKCommandEncodingContext* pEncodingContext);

    /** Returns whether this command buffer can be submitted to a queue more than once. */
    bool getIsReusable() { return _isReusable; }

	/**
	 * If this is a secondary command buffer, returns the number of views inherited
	 * from the primary command buffer. If this is a primary command buffer, returns 1.
	 */
	uint32_t getViewCount() const;

	/** Updated as renderpass commands are added. */
	MVKCurrentSubpassInfo _currentSubpassInfo;

    /**
     * Metal requires that a visibility buffer is established when a render pass is created, 
     * but Vulkan permits it to be set during a render pass. When the first occlusion query
     * command is added, it sets this value so that it can be applied when the first renderpass
     * is begun.
     */
    bool _needsVisibilityResultMTLBuffer;

	/** Called when a MVKCmdExecuteCommands is added to this command buffer. */
	void recordExecuteCommands(MVKArrayRef<MVKCommandBuffer*const> secondaryCommandBuffers);

	/** Called when a timestamp command is added. */
	void recordTimestampCommand();


#pragma mark Tessellation constituent command management

	/** Update the last recorded pipeline with tessellation shaders */
	void recordBindPipeline(MVKCmdBindPipeline* mvkBindPipeline);

	/** The most recent recorded tessellation pipeline */
	MVKCmdBindPipeline* _lastTessellationPipeline;


#pragma mark Construction

	MVKCommandBuffer(MVKDevice* device) : MVKDeviceTrackingMixin(device) {}

	~MVKCommandBuffer() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKCommandBuffer() method.
     */
	VkCommandBuffer getVkCommandBuffer() { return (VkCommandBuffer)getVkHandle(); }

    /**
     * Retrieves the MVKCommandBuffer instance referenced by the VkCommandBuffer handle.
     * This is the compliment of the getVkCommandBuffer() method.
     */
    static MVKCommandBuffer* getMVKCommandBuffer(VkCommandBuffer vkCommandBuffer) {
        return (MVKCommandBuffer*)getDispatchableObject(vkCommandBuffer);
    }

protected:
	friend class MVKCommandEncoder;
	friend class MVKCommandPool;

	void propagateDebugName() override {}
	void init(const VkCommandBufferAllocateInfo* pAllocateInfo);
	bool canExecute();
	void clearPrefilledMTLCommandBuffer();
    void releaseCommands(MVKCommand* command);
	void releaseRecordedCommands();
	void flushImmediateCmdEncoder();
	void checkDeferredEncoding();

	MVKCommand* _head = nullptr;
	MVKCommand* _tail = nullptr;
	MVKSmallVector<VkFormat, kMVKDefaultAttachmentCount> _colorAttachmentFormats;
	MVKCommandPool* _commandPool;
	VkCommandBufferInheritanceInfo _secondaryInheritanceInfo;
	VkCommandBufferInheritanceRenderingInfo _secondaryInheritanceRenderingInfo;
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
						 MVKCommandUse cmdUse);

	/** Begins the next render subpass. */
	void beginNextSubpass(MVKCommand* subpassCmd, VkSubpassContents renderpassContents);

	/** Begins dynamic rendering. */
	void beginRendering(MVKCommand* rendCmd, const VkRenderingInfo* pRenderingInfo);

	/** Begins a Metal render pass for the current render subpass. */
	void beginMetalRenderPass(MVKCommandUse cmdUse);

	/** 
	 * If a Metal render pass has started, and it needs to be restarted,
	 * then end the existing Metal render pass, and start a new one.
	 */
	void restartMetalRenderPassIfNeeded();

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
	uint32_t getMultiviewPassIndex() { return _multiviewPassIndex; }

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

	/** Clips the rect to ensure it fits inside the render area.  */
	VkRect2D clipToRenderArea(VkRect2D rect);

	/** Clips the scissor to ensure it fits inside the render area.  */
	MTLScissorRect clipToRenderArea(MTLScissorRect scissor);

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
	 * If the current encoder is a compute encoder, the compute state being tracked can
	 * optionally be marked dirty. Otherwise, if the current encoder is not a compute
	 * encoder, this function ends the current encoder before beginning compute encoding.
	 */
	id<MTLComputeCommandEncoder> getMTLComputeEncoder(MVKCommandUse cmdUse,
													  bool markCurrentComputeStateDirty = false);

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

	/** Returns the graphics pipeline. */
	MVKGraphicsPipeline* getGraphicsPipeline() { return (MVKGraphicsPipeline*)_graphicsPipelineState.getPipeline(); }

	/** Returns the compute pipeline. */
	MVKComputePipeline* getComputePipeline() { return (MVKComputePipeline*)_computePipelineState.getPipeline(); }

	/** Returns the push constants associated with the specified shader stage. */
	MVKPushConstantsCommandEncoderState* getPushConstants(VkShaderStageFlagBits shaderStage);

	/** Encode the buffer binding as a vertex attribute buffer. */
	void encodeVertexAttributeBuffer(MVKMTLBufferBinding& b, bool isDynamicStride);

    /**
	 * Copy bytes into the Metal encoder at a Metal vertex buffer index, and optionally indicate
	 * that this binding might override a desriptor binding. If so, the descriptor binding will
	 * be marked dirty so that it will rebind before the next usage.
	 */
    void setVertexBytes(id<MTLRenderCommandEncoder> mtlEncoder, const void* bytes,
						NSUInteger length, uint32_t mtlBuffIndex, bool descOverride = false);

	/**
	 * Copy bytes into the Metal encoder at a Metal fragment buffer index, and optionally indicate
	 * that this binding might override a desriptor binding. If so, the descriptor binding will
	 * be marked dirty so that it will rebind before the next usage.
	 */
    void setFragmentBytes(id<MTLRenderCommandEncoder> mtlEncoder, const void* bytes,
						  NSUInteger length, uint32_t mtlBuffIndex, bool descOverride = false);

	/**
	 * Copy bytes into the Metal encoder at a Metal compute buffer index, and optionally indicate
	 * that this binding might override a desriptor binding. If so, the descriptor binding will
	 * be marked dirty so that it will rebind before the next usage.
	 */
    void setComputeBytes(id<MTLComputeCommandEncoder> mtlEncoder, const void* bytes,
						 NSUInteger length, uint32_t mtlBuffIndex, bool descOverride = false);

	/**
	 * Copy bytes into the Metal encoder at a Metal compute buffer index with dynamic stride,
	 * and optionally indicate that this binding might override a desriptor binding. If so,
	 * the descriptor binding will be marked dirty so that it will rebind before the next usage.
	 */
    void setComputeBytesWithStride(id<MTLComputeCommandEncoder> mtlEncoder, const void* bytes,
						 NSUInteger length, uint32_t mtlBuffIndex, uint32_t stride, bool descOverride = false);

    /** Get a temporary MTLBuffer that will be returned to a pool after the command buffer is finished. */
    const MVKMTLBufferAllocation* getTempMTLBuffer(NSUInteger length, bool isPrivate = false, bool isDedicated = false);

	/** Copy the bytes to a temporary MTLBuffer that will be returned to a pool after the command buffer is finished. */
	const MVKMTLBufferAllocation* copyToTempMTLBufferAllocation(const void* bytes, NSUInteger length, bool isDedicated = false);

    /** Returns the command encoding pool. */
    MVKCommandEncodingPool* getCommandEncodingPool();

	#pragma mark Barriers

	/** Encode waits in the current command encoder for the stage that corresponds to given use. */
	void encodeBarrierWaits(MVKCommandUse use);

	/** Update fences for the currently executing pipeline stage. */
	void encodeBarrierUpdates();

	/** Insert a new execution barrier */
	void setBarrier(uint64_t sourceStageMask, uint64_t destStageMask);

	/** Encode waits for a specific stage in given encoder. */
	void barrierWait(MVKBarrierStage stage, id<MTLRenderCommandEncoder> mtlEncoder, MTLRenderStages beforeStages);
	void barrierWait(MVKBarrierStage stage, id<MTLBlitCommandEncoder> mtlEncoder);
	void barrierWait(MVKBarrierStage stage, id<MTLComputeCommandEncoder> mtlEncoder);

	/** Encode update for a specific stage in given encoder. */
	void barrierUpdate(MVKBarrierStage stage, id<MTLRenderCommandEncoder> mtlEncoder, MTLRenderStages afterStages);
	void barrierUpdate(MVKBarrierStage stage, id<MTLBlitCommandEncoder> mtlEncoder);
	void barrierUpdate(MVKBarrierStage stage, id<MTLComputeCommandEncoder> mtlEncoder);

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

	/** The command buffer whose commands are being encoded. */
	MVKCommandBuffer* _cmdBuffer;

	/** The current Metal command buffer. */
	id<MTLCommandBuffer> _mtlCmdBuffer;

	/** The current Metal render encoder. */
	id<MTLRenderCommandEncoder> _mtlRenderEncoder;

    /** Tracks the current graphics pipeline bound to the encoder. */
	MVKPipelineCommandEncoderState _graphicsPipelineState;

	/** Tracks the current graphics resources state of the encoder. */
	MVKGraphicsResourcesCommandEncoderState _graphicsResourcesState;

    /** Tracks the current compute pipeline bound to the encoder. */
	MVKPipelineCommandEncoderState _computePipelineState;

	/** Tracks the current compute resources state of the encoder. */
	MVKComputeResourcesCommandEncoderState _computeResourcesState;

	/** Tracks whether the GPU-addressable buffers need to be used. */
	MVKGPUAddressableBuffersCommandEncoderState _gpuAddressableBuffersState;

    /** Tracks the current depth stencil state of the encoder. */
    MVKDepthStencilCommandEncoderState _depthStencilState;

	/** Tracks the current rendering states of the encoder. */
	MVKRenderingCommandEncoderState _renderingState;

	/** Tracks the occlusion query state of the encoder. */
	MVKOcclusionQueryCommandEncoderState _occlusionQueryState;

    /** The size of the threadgroup for the compute shader. */
    MTLSize _mtlThreadgroupSize;

	/** Indicates whether the current render subpass is able to render to an array (layered) framebuffer. */
	bool _canUseLayeredRendering;

	/** Indicates whether the current draw is an indexed draw. */
	bool _isIndexedDraw;

#pragma mark Construction

	MVKCommandEncoder(MVKCommandBuffer* cmdBuffer,
					  MVKPrefillMetalCommandBuffersStyle prefillStyle = MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_NO_PREFILL);

	~MVKCommandEncoder() override;

protected:
    void addActivatedQueries(MVKQueryPool* pQueryPool, uint32_t query, uint32_t queryCount);
    void finishQueries();
	void setSubpass(MVKCommand* passCmd, VkSubpassContents subpassContents, uint32_t subpassIndex, MVKCommandUse cmdUse);
	void clearRenderArea(MVKCommandUse cmdUse);
	bool hasMoreMultiviewPasses();
	void beginNextMultiviewPass();
	void encodeCommandsImpl(MVKCommand* command);
	void encodeGPUCounterSample(MVKGPUCounterQueryPool* mvkQryPool, uint32_t sampleIndex, MVKCounterSamplingFlags samplingPoints);
	void encodeTimestampStageCounterSamples();
	id<MTLFence> getStageCountersMTLFence();
	NSString* getMTLRenderCommandEncoderName(MVKCommandUse cmdUse);
	template<typename T> void retainIfImmediatelyEncoding(T& mtlEnc);
	template<typename T> void endMetalEncoding(T& mtlEnc);
	id<MTLFence> getBarrierStageFence(MVKBarrierStage stage);

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
	id<MTLComputeCommandEncoder> _mtlComputeEncoder;
	id<MTLBlitCommandEncoder> _mtlBlitEncoder;
	id<MTLFence> _stageCountersMTLFence;
	MVKPushConstantsCommandEncoderState _vertexPushConstants;
	MVKPushConstantsCommandEncoderState _tessCtlPushConstants;
	MVKPushConstantsCommandEncoderState _tessEvalPushConstants;
	MVKPushConstantsCommandEncoderState _fragmentPushConstants;
	MVKPushConstantsCommandEncoderState _computePushConstants;
	MVKPrefillMetalCommandBuffersStyle _prefillStyle;
	VkSubpassContents _subpassContents;
	uint32_t _renderSubpassIndex;
	uint32_t _multiviewPassIndex;
    uint32_t _flushCount;
	MVKCommandUse _mtlComputeEncoderUse;
	MVKCommandUse _mtlBlitEncoderUse;
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
