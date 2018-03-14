/*
 * MVKCommandBuffer.mm
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKQueue.h"
#include "MVKPipeline.h"
#include "MVKRenderPass.h"
#include "MVKFramebuffer.h"
#include "MVKQueryPool.h"
#include "MVKFoundation.h"

using namespace std;


#pragma mark -
#pragma mark MVKCommandBuffer

VkResult MVKCommandBuffer::begin(const VkCommandBufferBeginInfo* pBeginInfo) {
	_recordingResult = VK_SUCCESS;
	_canAcceptCommands = true;
	reset(0);

	VkCommandBufferUsageFlags usage = pBeginInfo->flags;
	_isReusable = !mvkAreFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT);
	_supportsConcurrentExecution = mvkAreFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT);

	// If this is a secondary command buffer, and contains inheritance info, set the inheritance info and determine
	// whether it contains render pass continuation info. Otherwise, clear the inheritance info, and ignore it.
	const VkCommandBufferInheritanceInfo* pInheritInfo = (_isSecondary ? pBeginInfo->pInheritanceInfo : NULL);
	bool hasInheritInfo = mvkSetOrClear(&_secondaryInheritanceInfo, pInheritInfo);
	_doesContinueRenderPass = mvkAreFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT) && hasInheritInfo;

	_wasExecuted = false;
	return _recordingResult;
}

VkResult MVKCommandBuffer::reset(VkCommandBufferResetFlags flags) {
	MVKCommand* cmd = _head;
	while (cmd) {
		MVKCommand* nextCmd = cmd->_next;	// Establish next before returning current to pool.
		cmd->returnToPool();
		cmd = nextCmd;
	}

	_head = nullptr;
	_tail = nullptr;
	_commandCount = 0;
    _initialVisibilityResultMTLBuffer = nil;       // not retained

	if (mvkAreFlagsEnabled(flags, VK_COMMAND_BUFFER_RESET_RELEASE_RESOURCES_BIT)) {
		// TODO: what are we releasing or returning here?
	}

	return VK_SUCCESS;
}

VkResult MVKCommandBuffer::end() {
	_canAcceptCommands = false;
	return _recordingResult;
}

void MVKCommandBuffer::addCommand(MVKCommand* command) {
	if ( !_canAcceptCommands ) {
		recordResult(mvkNotifyErrorWithText(VK_NOT_READY, "Command buffer cannot accept commands before vkBeginCommandBuffer() is called."));
		return;
	}

    if (_tail) { _tail->_next = command; }
    command->_next = VK_NULL_HANDLE;
    _tail = command;
    if ( !_head ) { _head = command; }
    _commandCount++;

    command->added(this);

    recordResult(command->getConfigurationResult());
}

void MVKCommandBuffer::execute(MVKQueueCommandBufferSubmission* cmdBuffSubmit,
                               const MVKCommandBufferBatchPosition& batchPosition) {
	if ( !canExecute() ) { return; }

	MVKCommandEncoder encoder(this, batchPosition);
	encoder.encode(cmdBuffSubmit);

	if ( !_supportsConcurrentExecution ) { _nonConcurrentIsExecuting.clear(); }
}

bool MVKCommandBuffer::canExecute() {
	if (_isSecondary) {
		recordResult(mvkNotifyErrorWithText(VK_NOT_READY, "Secondary command buffers may not be submitted directly to a queue."));
		return false;
	}
	if ( !_isReusable && _wasExecuted ) {
		recordResult(mvkNotifyErrorWithText(VK_NOT_READY, "Command buffer does not support execution more that once."));
		return false;
	}

	// Do this test last so that _isExecution is only set if everthing else passes
	if ( !_supportsConcurrentExecution && _nonConcurrentIsExecuting.test_and_set()) {
		recordResult(mvkNotifyErrorWithText(VK_NOT_READY, "Command buffer does not support concurrent execution."));
		return false;
	}

	_wasExecuted = true;
	return true;
}


#pragma mark Construction

MVKCommandBuffer::MVKCommandBuffer(MVKDevice* device,
								   const VkCommandBufferAllocateInfo* pAllocateInfo) : MVKDispatchableDeviceObject(device) {

	_commandPool = (MVKCommandPool*)pAllocateInfo->commandPool;
	_commandPool->addCommandBuffer(this);
	_level = pAllocateInfo->level;
	_isSecondary = (_level == VK_COMMAND_BUFFER_LEVEL_SECONDARY);
	_doesContinueRenderPass = false;
	_canAcceptCommands = false;
	_isReusable = false;
	_supportsConcurrentExecution = false;
	_wasExecuted = false;
	_nonConcurrentIsExecuting.clear();
	_recordingResult = VK_NOT_READY;
	_head = VK_NULL_HANDLE;
	_tail = VK_NULL_HANDLE;
	_commandCount = 0;
    _initialVisibilityResultMTLBuffer = nil;
}

MVKCommandBuffer::~MVKCommandBuffer() {
	reset(0);
	_commandPool->removeCommandBuffer(this);
}


#pragma mark -
#pragma mark MVKCommandEncoder

void MVKCommandEncoder::encode(MVKQueueCommandBufferSubmission* cmdBuffSubmit) {
	_queueSubmission = cmdBuffSubmit;
	_subpassContents = VK_SUBPASS_CONTENTS_INLINE;
	_renderSubpassIndex = 0;
	_isAwaitingFlush = false;

	beginEncoding();

    MVKCommand* cmd = _cmdBuffer->_head;
	while (cmd) {
        if (cmd->canEncode()) { cmd->encode(this); }
        cmd = cmd->_next;
	}

	endEncoding();
}

void MVKCommandEncoder::encodeSecondary(MVKCommandBuffer* secondaryCmdBuffer) {
	MVKCommand* cmd = secondaryCmdBuffer->_head;
	while (cmd) {
		cmd->encode(this);
		cmd = cmd->_next;
	}
}

// Retrieves and caches the MTLCommandBuffer from the queue submission
void MVKCommandEncoder::beginEncoding() {
	_mtlCmdBuffer = _queueSubmission->getActiveMTLCommandBuffer();
}

// Finishes the encoding process.
void MVKCommandEncoder::endEncoding() {
	endCurrentMetalEncoding();
    finishQueries();
}

void MVKCommandEncoder::beginRenderpass(VkSubpassContents subpassContents,
										MVKRenderPass* renderPass,
										MVKFramebuffer* framebuffer,
										VkRect2D& renderArea,
										vector<VkClearValue>* clearValues) {
	_renderPass = renderPass;
	_framebuffer = framebuffer;
	_renderArea = renderArea;
	_isRenderingEntireAttachment = (mvkVkOffset2DsAreEqual(_renderArea.offset, {0,0}) &&
									mvkVkExtent2DsAreEqual(_renderArea.extent, _framebuffer->getExtent2D()));
	_clearValues.assign(clearValues->begin(), clearValues->end());
	setSubpass(subpassContents, 0);
}

void MVKCommandEncoder::beginNextSubpass(VkSubpassContents contents) {
	setSubpass(contents, _renderSubpassIndex + 1);
}

/** Sets the current render subpass to the subpass with the specified index. */
void MVKCommandEncoder::setSubpass(VkSubpassContents subpassContents, uint32_t subpassIndex) {
	_subpassContents = subpassContents;
	_renderSubpassIndex = subpassIndex;

    beginMetalRenderPass();
}

// Called after the _mtlRenderEncoder is established.
// Marks cached render state as dirty so it will be set into the _mtlRenderEncoder.
void MVKCommandEncoder::beginMetalRenderPass() {

    endCurrentMetalEncoding();

    MTLRenderPassDescriptor* mtlRPDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    getSubpass()->populateMTLRenderPassDescriptor(mtlRPDesc, _framebuffer, _clearValues, _isRenderingEntireAttachment);
    mtlRPDesc.visibilityResultBuffer = _occlusionQueryState.getVisibilityResultMTLBuffer();

    _mtlRenderEncoder = [_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];     // not retained
    _mtlRenderEncoder.label = getMTLRenderCommandEncoderName();

    if ( !_isRenderingEntireAttachment ) { clearRenderArea(); }

    _graphicsPipelineState.beginMetalRenderPass();
    _graphicsResourcesState.beginMetalRenderPass();
    _viewportState.beginMetalRenderPass();
    _scissorState.beginMetalRenderPass();
    _depthBiasState.beginMetalRenderPass();
    _blendColorState.beginMetalRenderPass();
    _vertexPushConstants.beginMetalRenderPass();
    _fragmentPushConstants.beginMetalRenderPass();
    _depthStencilState.beginMetalRenderPass();
    _stencilReferenceValueState.beginMetalRenderPass();
    _occlusionQueryState.beginMetalRenderPass();
}

MVKRenderSubpass* MVKCommandEncoder::getSubpass() { return _renderPass->getSubpass(_renderSubpassIndex); }

// Returns a name for use as a MTLRenderCommandEncoder label
NSString* MVKCommandEncoder::getMTLRenderCommandEncoderName() {
    MVKCommandUse cmdUse = (_renderSubpassIndex == 0) ? kMVKCommandUseBeginRenderPass : kMVKCommandUseNextSubpass;
    return mvkMTLRenderCommandEncoderLabel(cmdUse);
}

void MVKCommandEncoder::bindPipeline(VkPipelineBindPoint pipelineBindPoint, MVKPipeline* pipeline) {
    switch (pipelineBindPoint) {
        case VK_PIPELINE_BIND_POINT_GRAPHICS:
            _graphicsPipelineState.setPipeline(pipeline);
            break;

        case VK_PIPELINE_BIND_POINT_COMPUTE:
            _computePipelineState.setPipeline(pipeline);
            break;

        default:
            break;
    }
}

bool MVKCommandEncoder::supportsDynamicState(VkDynamicState state) {
    MVKGraphicsPipeline* gpl = (MVKGraphicsPipeline*)_graphicsPipelineState.getPipeline();
    return !gpl || gpl->supportsDynamicState(state);
}

MTLScissorRect MVKCommandEncoder::clipToRenderArea(MTLScissorRect mtlScissor) {

	NSUInteger raLeft = _renderArea.offset.x;
	NSUInteger raRight = raLeft + _renderArea.extent.width;
	NSUInteger raBottom = _renderArea.offset.y;
	NSUInteger raTop = raBottom + _renderArea.extent.height;

	mtlScissor.x		= mvkClamp(mtlScissor.x, raLeft, max(raRight - 1, raLeft));
	mtlScissor.y		= mvkClamp(mtlScissor.y, raBottom, max(raTop - 1, raBottom));
	mtlScissor.width	= min(mtlScissor.width, raRight - mtlScissor.x);
	mtlScissor.height	= min(mtlScissor.height, raTop - mtlScissor.y);

	return mtlScissor;
}

void MVKCommandEncoder::finalizeDrawState() {
    _graphicsPipelineState.encode();    // Must do first..it sets others
    _graphicsResourcesState.encode();
    _viewportState.encode();
    _scissorState.encode();
    _depthBiasState.encode();
    _blendColorState.encode();
    _vertexPushConstants.encode();
    _fragmentPushConstants.encode();
    _depthStencilState.encode();
    _stencilReferenceValueState.encode();
    _occlusionQueryState.encode();
}

// Clears the render area of the framebuffer attachments.
void MVKCommandEncoder::clearRenderArea() {

	vector<VkClearAttachment> clearAtts;
	getSubpass()->populateClearAttachments(clearAtts, _clearValues);

	uint32_t clearAttCnt = (uint32_t)clearAtts.size();

	if (clearAttCnt == 0) { return; }

	VkClearRect clearRect;
	clearRect.rect = _renderArea;
	clearRect.baseArrayLayer = 0;
	clearRect.layerCount = 1;

    // Create and execute a temporary clear attachments command.
    // To be threadsafe...do NOT acquire and return the command from the pool.
    MVKCmdClearAttachments cmd(&_cmdBuffer->_commandPool->_cmdClearAttachmentsPool);
    cmd.setContent(clearAttCnt, clearAtts.data(), 1, &clearRect);
    cmd.encode(this);
}

void MVKCommandEncoder::finalizeDispatchState() {
    _computePipelineState.encode();
    _computeResourcesState.encode();
    _computePushConstants.encode();
}

void MVKCommandEncoder::endMetalRenderEncoding() {
//    MVKLogDebugIf(_mtlRenderEncoder, "Render subpass end MTLRenderCommandEncoder.");
    [_mtlRenderEncoder endEncoding];
	_mtlRenderEncoder = nil;    // not retained

	if (_isAwaitingFlush) { flush(); }		// if awaiting a flush, do so now
}

void MVKCommandEncoder::endCurrentMetalEncoding() {
	endMetalRenderEncoding();

	[_mtlComputeEncoder endEncoding];
	_mtlComputeEncoder = nil;       // not retained
	_mtlComputeEncoderUse = kMVKCommandUseNone;

	[_mtlBlitEncoder endEncoding];
	_mtlBlitEncoder = nil;          // not retained
    _mtlBlitEncoderUse = kMVKCommandUseNone;
}

void MVKCommandEncoder::flush() {
	if (_mtlRenderEncoder) {
		// If currently in a render pass, wait until it's done before flushing,
		_isAwaitingFlush = true;
	} else {
		// Otherwise, flush immediately by committing the current MTLCommandBuffer and starting a new one.
		_isAwaitingFlush = false;
        _flushCount++;
		endEncoding();
		_queueSubmission->commitActiveMTLCommandBuffer();
		beginEncoding();
	}
}

id<MTLComputeCommandEncoder> MVKCommandEncoder::getMTLComputeEncoder(MVKCommandUse cmdUse) {
	if ( !_mtlComputeEncoder ) {
		endCurrentMetalEncoding();
		_mtlComputeEncoder = [_mtlCmdBuffer computeCommandEncoder];		// not retained
	}
	if (_mtlComputeEncoderUse != cmdUse) {
		_mtlComputeEncoderUse = cmdUse;
		_mtlComputeEncoder.label = mvkMTLComputeCommandEncoderLabel(cmdUse);
	}
	return _mtlComputeEncoder;
}

id<MTLBlitCommandEncoder> MVKCommandEncoder::getMTLBlitEncoder(MVKCommandUse cmdUse) {
	if ( !_mtlBlitEncoder ) {
		endCurrentMetalEncoding();
		_mtlBlitEncoder = [_mtlCmdBuffer blitCommandEncoder];   // not retained
	}
    if (_mtlBlitEncoderUse != cmdUse) {
        _mtlBlitEncoderUse = cmdUse;
        _mtlBlitEncoder.label = mvkMTLBlitCommandEncoderLabel(cmdUse);
    }
	return _mtlBlitEncoder;
}
MVKPushConstantsCommandEncoderState* MVKCommandEncoder::getPushConstants(VkShaderStageFlagBits shaderStage) {
	switch (shaderStage) {
		case VK_SHADER_STAGE_VERTEX_BIT:	return &_vertexPushConstants;
		case VK_SHADER_STAGE_FRAGMENT_BIT:	return &_fragmentPushConstants;
		case VK_SHADER_STAGE_COMPUTE_BIT:	return &_computePushConstants;
		default:
			MVKAssert(false, "Invalid shader stage: %u", shaderStage);
			return VK_NULL_HANDLE;
	}
}

void MVKCommandEncoder::setVertexBytes(id<MTLRenderCommandEncoder> mtlEncoder,
                                       const void* bytes,
                                       NSUInteger length,
                                       uint32_t mtlBuffIndex) {
    if (_pDeviceMetalFeatures->dynamicMTLBuffers) {
        [mtlEncoder setVertexBytes: bytes length: length atIndex: mtlBuffIndex];
    } else {
        const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
        [mtlEncoder setVertexBuffer: mtlBuffAlloc->_mtlBuffer offset: mtlBuffAlloc->_offset atIndex: mtlBuffIndex];
    }
}

void MVKCommandEncoder::setFragmentBytes(id<MTLRenderCommandEncoder> mtlEncoder,
                                         const void* bytes,
                                         NSUInteger length,
                                         uint32_t mtlBuffIndex) {
    if (_pDeviceMetalFeatures->dynamicMTLBuffers) {
        [mtlEncoder setFragmentBytes: bytes length: length atIndex: mtlBuffIndex];
    } else {
        const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
        [mtlEncoder setFragmentBuffer: mtlBuffAlloc->_mtlBuffer offset: mtlBuffAlloc->_offset atIndex: mtlBuffIndex];
    }
}

void MVKCommandEncoder::setComputeBytes(id<MTLComputeCommandEncoder> mtlEncoder,
                                        const void* bytes,
                                        NSUInteger length,
                                        uint32_t mtlBuffIndex) {
    if (_pDeviceMetalFeatures->dynamicMTLBuffers) {
        [mtlEncoder setBytes: bytes length: length atIndex: mtlBuffIndex];
    } else {
        const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
        [mtlEncoder setBuffer: mtlBuffAlloc->_mtlBuffer offset: mtlBuffAlloc->_offset atIndex: mtlBuffIndex];
    }
}

MVKCommandEncodingPool* MVKCommandEncoder::getCommandEncodingPool() { return _queueSubmission->_queue->getCommandEncodingPool(); }

// Copies the specified bytes into a temporary allocation within a pooled MTLBuffer, and returns the MTLBuffer allocation.
const MVKMTLBufferAllocation* MVKCommandEncoder::copyToTempMTLBufferAllocation(const void* bytes, NSUInteger length) {
    const MVKMTLBufferAllocation* mtlBuffAlloc = getCommandEncodingPool()->acquireMTLBufferAllocation(length);
    void* pBuffData = mtlBuffAlloc->getContents();
    memcpy(pBuffData, bytes, length);

    // Return the MTLBuffer allocation to the pool once the command buffer is done with it
    [_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mcb) {
        ((MVKMTLBufferAllocation*)mtlBuffAlloc)->returnToPool();
    }];

    return mtlBuffAlloc;
}


#pragma mark Queries

void MVKCommandEncoder::beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
    _occlusionQueryState.beginOcclusionQuery(pQueryPool, query, flags);
    addActivatedQuery(pQueryPool, query);
}

void MVKCommandEncoder::endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
    _occlusionQueryState.endOcclusionQuery(pQueryPool, query);
    flush();
}

void MVKCommandEncoder::markTimestamp(MVKQueryPool* pQueryPool, uint32_t query) {
    addActivatedQuery(pQueryPool, query);
    flush();
}

// Marks the specified query as activated
void MVKCommandEncoder::addActivatedQuery(MVKQueryPool* pQueryPool, uint32_t query) {
    if ( !_pActivatedQueries ) { _pActivatedQueries = new MVKActivatedQueries(); }
    (*_pActivatedQueries)[pQueryPool].push_back(query);
}

// Register a command buffer completion handler that finishes each activated query.
// Ownership of the collection of activated queries is passed to the handler.
void MVKCommandEncoder::finishQueries() {
    if ( !_pActivatedQueries ) { return; }

    MVKActivatedQueries* pAQs = _pActivatedQueries;
    [_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mtlCmdBuff) {
        for (auto& qryPair : *pAQs) {
            qryPair.first->finishQueries(qryPair.second);
        }
        delete pAQs;
    }];
    _pActivatedQueries = nullptr;
}


#pragma mark Construction

MVKCommandEncoder::MVKCommandEncoder(MVKCommandBuffer* cmdBuffer,
                                     const MVKCommandBufferBatchPosition& batchPosition) : MVKBaseDeviceObject(cmdBuffer->getDevice()),
        _cmdBuffer(cmdBuffer),
        _batchPosition(batchPosition),
        _graphicsPipelineState(this),
        _computePipelineState(this),
        _viewportState(this),
        _scissorState(this),
        _depthBiasState(this),
        _blendColorState(this),
        _vertexPushConstants(this, VK_SHADER_STAGE_VERTEX_BIT),
        _fragmentPushConstants(this, VK_SHADER_STAGE_FRAGMENT_BIT),
        _computePushConstants(this, VK_SHADER_STAGE_COMPUTE_BIT),
        _depthStencilState(this),
        _stencilReferenceValueState(this),
        _graphicsResourcesState(this),
        _computeResourcesState(this),
        _occlusionQueryState(this) {

            _pDeviceFeatures = _device->_pFeatures;
            _pDeviceMetalFeatures = _device->_pMetalFeatures;
            _pDeviceProperties = _device->_pProperties;
            _pDeviceMemoryProperties = _device->_pMemoryProperties;
            _pActivatedQueries = nullptr;
            _mtlCmdBuffer = nil;
            _mtlRenderEncoder = nil;
            _mtlComputeEncoder = nil;
			_mtlComputeEncoderUse = kMVKCommandUseNone;
            _mtlBlitEncoder = nil;
            _mtlBlitEncoderUse = kMVKCommandUseNone;
}


#pragma mark -
#pragma mark MVKMTLCommandBufferCountdown

bool MVKMTLCommandBufferCountdown::setActiveMTLCommandBufferCount(uint32_t count,
                                                                  MVKMTLCommandBufferID mtlCmdBuffID) {
    _activeMTLCommandBufferCount = count;
    _maxMTLCmdBuffID = mtlCmdBuffID;

    return checkFinished();
}

bool MVKMTLCommandBufferCountdown::mtlCommandBufferHasCompleted(MVKMTLCommandBufferID mtlCmdBuffID) {
    if ( (_activeMTLCommandBufferCount > 0) && (mtlCmdBuffID < _maxMTLCmdBuffID) ) {
        _activeMTLCommandBufferCount--;
    }
    return checkFinished();
}

// If the count of active MTLCommandBuffers is zero, calls the finish() member function.
// Returns whether the count is now at zero.
bool MVKMTLCommandBufferCountdown::checkFinished() {
    bool isDone = (_activeMTLCommandBufferCount == 0);
    if (isDone) { finish();	}
    return isDone;
}

uint32_t MVKMTLCommandBufferCountdown::getCount() { return _activeMTLCommandBufferCount; }


#pragma mark -
#pragma mark Support functions

NSString* mvkMTLCommandBufferLabel(MVKCommandUse cmdUse) {
    switch (cmdUse) {
        case kMVKCommandUseQueueSubmit:     return @"vkQueueSubmit CommandBuffer";
        case kMVKCommandUseQueuePresent:    return @"vkQueuePresentKHR CommandBuffer";
        case kMVKCommandUseQueueWaitIdle:   return @"vkQueueWaitIdle CommandBuffer";
        case kMVKCommandUseDeviceWaitIdle:  return @"vkDeviceWaitIdle CommandBuffer";
        default:                            return @"Unknown Use CommandBuffer";
    }
}

NSString* mvkMTLRenderCommandEncoderLabel(MVKCommandUse cmdUse) {
    switch (cmdUse) {
        case kMVKCommandUseBeginRenderPass:         return @"vkCmdBeginRenderPass RenderEncoder";
        case kMVKCommandUseNextSubpass:             return @"vkCmdNextSubpass RenderEncoder";
        case kMVKCommandUseBlitImage:               return @"vkCmdBlitImage RenderEncoder";
        case kMVKCommandUseResolveImage:            return @"vkCmdResolveImage (resolve stage) RenderEncoder";
        case kMVKCommandUseResolveExpandImage:      return @"vkCmdResolveImage (expand stage) RenderEncoder";
        case kMVKCommandUseClearColorImage:         return @"vkCmdClearColorImage RenderEncoder";
        case kMVKCommandUseClearDepthStencilImage:  return @"vkCmdClearDepthStencilImage RenderEncoder";
        default:                                    return @"Unknown Use RenderEncoder";
    }
}

NSString* mvkMTLBlitCommandEncoderLabel(MVKCommandUse cmdUse) {
    switch (cmdUse) {
        case kMVKCommandUsePipelineBarrier:     return @"vkCmdPipelineBarrier BlitEncoder";
        case kMVKCommandUseCopyImage:           return @"vkCmdCopyImage BlitEncoder";
        case kMVKCommandUseResolveCopyImage:    return @"vkCmdResolveImage (copy stage) RenderEncoder";
        case kMVKCommandUseCopyBuffer:          return @"vkCmdCopyBuffer BlitEncoder";
        case kMVKCommandUseCopyBufferToImage:   return @"vkCmdCopyBufferToImage BlitEncoder";
        case kMVKCommandUseCopyImageToBuffer:   return @"vkCmdCopyImageToBuffer BlitEncoder";
        case kMVKCommandUseFillBuffer:          return @"vkCmdFillBuffer BlitEncoder";
        case kMVKCommandUseUpdateBuffer:        return @"vkCmdUpdateBuffer BlitEncoder";
        case kMVKCommandUseResetQueryPool:      return @"vkCmdResetQueryPool BlitEncoder";
        default:                                return @"Unknown Use BlitEncoder";
    }
}

NSString* mvkMTLComputeCommandEncoderLabel(MVKCommandUse cmdUse) {
	switch (cmdUse) {
		case kMVKCommandUseDispatch:          	return @"vkCmdDispatch ComputeEncoder";
		case kMVKCommandUseCopyBuffer:          return @"vkCmdCopyBuffer ComputeEncoder";
		case kMVKCommandUseFillBuffer:          return @"vkCmdFillBuffer ComputeEncoder";
		default:                                return @"Unknown Use ComputeEncoder";
	}
}

