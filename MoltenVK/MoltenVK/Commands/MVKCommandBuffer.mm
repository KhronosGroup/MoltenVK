/*
 * MVKCommandBuffer.mm
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

#include "MVKCommandBuffer.h"
#include "MVKFramebuffer.h"
#include "MVKCommandPool.h"
#include "MVKQueue.h"
#include "MVKPipeline.h"
#include "MVKQueryPool.h"
#include "MVKFoundation.h"
#include "MTLRenderPassDescriptor+MoltenVK.h"
#include "MVKCmdDraw.h"
#include "MVKCmdRendering.h"
#include <sys/mman.h>

using namespace std;


#pragma mark -
#pragma mark MVKCommandEncodingContext

// Sets the rendering objects, releasing the old objects, and retaining the new objects.
// Retaining the new is performed first, in case the old and new are the same object.
// With dynamic rendering, the objects are transient and only live as long as the
// duration of the active renderpass. To make it transient, it is released by the calling
// code after it has been retained here, so that when it is released again here at the
// end of the renderpass, it will automatically be destroyed. App-created objects are
// not released by the calling code, and will not be destroyed by the release here.
void MVKCommandEncodingContext::setRenderingContext(MVKRenderPass* renderPass, MVKFramebuffer* framebuffer) {

	if (renderPass) { renderPass->retain(); }
	if (_renderPass) { _renderPass->release(); }
	_renderPass = renderPass;

	if (framebuffer) { framebuffer->retain(); }
	if (_framebuffer) { _framebuffer->release(); }
	_framebuffer = framebuffer;
}

void MVKCommandEncodingContext::syncFences(MVKDevice *device, id<MTLCommandBuffer> mtlCommandBuffer) {
	if (!device->hasResidencySet()) return;

	// Synchronize all stages to their fences at index 0, which will be waited on in the next command buffer.
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
		auto fenceIndex = fenceSlots.update[i];
		if (!fenceIndex) continue;

		auto encoder = [mtlCommandBuffer blitCommandEncoder];
		[encoder waitForFence:device->getFence((MVKBarrierStage)i, fenceIndex)];
		[encoder updateFence:device->getFence((MVKBarrierStage)i, 0)];
		[encoder endEncoding];
	}
}

// Release rendering objects in case this instance is destroyed before ending the current renderpass.
MVKCommandEncodingContext::~MVKCommandEncodingContext() {
	setRenderingContext(nullptr, nullptr);
}


#pragma mark -
#pragma mark MVKCurrentSubpassInfo

void MVKCurrentSubpassInfo::beginRenderpass(MVKRenderPass* rp) {
	renderpass = rp;
	subpassIndex = 0;
	updateViewMask();
}
void MVKCurrentSubpassInfo::nextSubpass() {
	subpassIndex++;
	updateViewMask();
}
void MVKCurrentSubpassInfo::beginRendering(uint32_t viewMask) {
	renderpass = nullptr;
	subpassIndex = 0;
	subpassViewMask = viewMask;
}
void MVKCurrentSubpassInfo::updateViewMask() {
	subpassViewMask = renderpass ? renderpass->getSubpass(subpassIndex)->getViewMask() : 0;
}


#pragma mark -
#pragma mark MVKCommandBuffer

VkResult MVKCommandBuffer::begin(const VkCommandBufferBeginInfo* pBeginInfo) {

	reset(0);

	clearConfigurationResult();
	_canAcceptCommands = true;

	VkCommandBufferUsageFlags usage = pBeginInfo->flags;
	_isReusable = !mvkAreAllFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT);
	_supportsConcurrentExecution = mvkAreAllFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT);

	// If this is a secondary command buffer, and contains inheritance info, set the inheritance info and determine
	// whether it contains render pass continuation info. Otherwise, clear the inheritance info, and ignore it.
	// Also check for and set any dynamic rendering inheritance info. The color format array must be copied locally.
	const VkCommandBufferInheritanceInfo* pInheritInfo = (_isSecondary ? pBeginInfo->pInheritanceInfo : nullptr);
	bool hasInheritInfo = mvkSetOrClear(&_secondaryInheritanceInfo, pInheritInfo);
	if (hasInheritInfo) {
		for (const auto* next = (VkBaseInStructure*)_secondaryInheritanceInfo.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO: {
					if (mvkSetOrClear(&_secondaryInheritanceRenderingInfo, (VkCommandBufferInheritanceRenderingInfo*)next)) {
						for (uint32_t caIdx = 0; caIdx < _secondaryInheritanceRenderingInfo.colorAttachmentCount; caIdx++) {
							_colorAttachmentFormats.push_back(_secondaryInheritanceRenderingInfo.pColorAttachmentFormats[caIdx]);
						}
						_secondaryInheritanceRenderingInfo.pColorAttachmentFormats = _colorAttachmentFormats.data();
					}
					break;
				}
				default:
					break;
			}
		}
	}
	_doesContinueRenderPass = mvkAreAllFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT) && hasInheritInfo;

    if(_device->shouldPrefillMTLCommandBuffers() && !(_isSecondary || _supportsConcurrentExecution)) {
		@autoreleasepool {
			_prefilledMTLCmdBuffer = [_commandPool->getMTLCommandBuffer(kMVKCommandUseBeginCommandBuffer, 0) retain];    // retained
			auto prefillStyle = getMVKConfig().prefillMetalCommandBuffers;
			if (prefillStyle == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_IMMEDIATE_ENCODING ||
				prefillStyle == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_IMMEDIATE_ENCODING_NO_AUTORELEASE ) {
				_immediateCmdEncodingContext = new MVKCommandEncodingContext;
				_immediateCmdEncoder = new MVKCommandEncoder(this, prefillStyle);
				_immediateCmdEncoder->beginEncoding(_prefilledMTLCmdBuffer, _immediateCmdEncodingContext);
			}
		}
    }

    return getConfigurationResult();
}

void MVKCommandBuffer::releaseCommands(MVKCommand* command) {
    while(command) {
        MVKCommand* nextCommand = command->_next; // Establish next before returning current to pool.
        (command->getTypePool(getCommandPool()))->returnObject(command);
        command = nextCommand;
    }
}

void MVKCommandBuffer::releaseRecordedCommands() {
    releaseCommands(_head);
	_head = nullptr;
	_tail = nullptr;
}

void MVKCommandBuffer::flushImmediateCmdEncoder() {
    if(_immediateCmdEncoder) {
        _immediateCmdEncoder->endEncoding();
        delete _immediateCmdEncoder;
        _immediateCmdEncoder = nullptr;
        
        delete _immediateCmdEncodingContext;
        _immediateCmdEncodingContext = nullptr;
    }
}

VkResult MVKCommandBuffer::reset(VkCommandBufferResetFlags flags) {
    flushImmediateCmdEncoder();
	clearPrefilledMTLCommandBuffer();
	releaseRecordedCommands();
	_doesContinueRenderPass = false;
	_canAcceptCommands = false;
	_isReusable = false;
	_supportsConcurrentExecution = false;
	_wasExecuted = false;
	_isExecutingNonConcurrently.clear();
	_commandCount = 0;
	_currentSubpassInfo = {};
	_needsVisibilityResultMTLBuffer = false;
	_hasStageCounterTimestampCommand = false;
	_lastTessellationPipeline = nullptr;
	setConfigurationResult(VK_NOT_READY);

	if (mvkAreAllFlagsEnabled(flags, VK_COMMAND_BUFFER_RESET_RELEASE_RESOURCES_BIT)) {
		// TODO: what are we releasing or returning here?
	}

	return VK_SUCCESS;
}

VkResult MVKCommandBuffer::end() {
	_canAcceptCommands = false;
    
    flushImmediateCmdEncoder();
	checkDeferredEncoding();

	return getConfigurationResult();
}

void MVKCommandBuffer::checkDeferredEncoding() {
	if (getMVKConfig().prefillMetalCommandBuffers == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_DEFERRED_ENCODING) {
		@autoreleasepool {
			MVKCommandEncodingContext encodingContext;
			MVKCommandEncoder encoder(this);
			encoder.encode(_prefilledMTLCmdBuffer, &encodingContext);
			if (isUsingMetalArgumentBuffers()) {
				encodingContext.syncFences(getDevice(), _prefilledMTLCmdBuffer);
			}

			// Once encoded onto Metal, if this command buffer is not reusable, we don't need the
			// MVKCommand instances anymore, so release them in order to reduce memory pressure.
			if ( !_isReusable ) { releaseRecordedCommands(); }
		}
	}
}

void MVKCommandBuffer::addCommand(MVKCommand* command) {
    if ( !_canAcceptCommands ) {
        setConfigurationResult(reportError(VK_NOT_READY, "Command buffer cannot accept commands before vkBeginCommandBuffer() is called."));
        return;
    }

	_commandCount++;

    if(_immediateCmdEncoder) {
        _immediateCmdEncoder->encodeCommands(command);
        if( !_isReusable ) {
            releaseCommands(command);
            return;
        }
    }

    if (_tail) { _tail->_next = command; }
    command->_next = nullptr;
    _tail = command;
    if ( !_head ) { _head = command; }
}

void MVKCommandBuffer::submit(MVKQueueCommandBufferSubmission* cmdBuffSubmit,
							  MVKCommandEncodingContext* pEncodingContext) {
	if ( !canExecute() ) { return; }

	if (_prefilledMTLCmdBuffer) {
		cmdBuffSubmit->setActiveMTLCommandBuffer(_prefilledMTLCmdBuffer);
		clearPrefilledMTLCommandBuffer();
	} else {
		MVKCommandEncoder encoder(this);
		encoder.encode(cmdBuffSubmit->getActiveMTLCommandBuffer(), pEncodingContext);
	}

	if ( !_supportsConcurrentExecution ) { _isExecutingNonConcurrently.clear(); }
}

bool MVKCommandBuffer::canExecute() {
	if (_isSecondary) {
		setConfigurationResult(reportError(VK_NOT_READY, "Secondary command buffers may not be submitted directly to a queue."));
		return false;
	}
	if ( !_isReusable && _wasExecuted ) {
		setConfigurationResult(reportError(VK_NOT_READY, "Command buffer does not support execution more that once."));
		return false;
	}

	// Do this test last so that _isExecutingNonConcurrently is only set if everything else passes
	if ( !_supportsConcurrentExecution && _isExecutingNonConcurrently.test_and_set()) {
		setConfigurationResult(reportError(VK_NOT_READY, "Command buffer does not support concurrent execution."));
		return false;
	}

	_wasExecuted = true;
	return wasConfigurationSuccessful();
}

// Return the number of bits set in the view mask, with a minimum value of 1.
uint32_t MVKCommandBuffer::getViewCount() const {
	uint32_t viewMask = 0;
	if (_doesContinueRenderPass) {
		MVKRenderPass* inheritedRenderPass = (MVKRenderPass*)_secondaryInheritanceInfo.renderPass;
		if (inheritedRenderPass) {
			viewMask = inheritedRenderPass->getSubpass(_secondaryInheritanceInfo.subpass)->getViewMask();
		} else {
			viewMask = _secondaryInheritanceRenderingInfo.viewMask;
		}
	} else {
		viewMask = _currentSubpassInfo.subpassViewMask;
	}
	return max(__builtin_popcount(viewMask), 1);
}

void MVKCommandBuffer::clearPrefilledMTLCommandBuffer() {

	// Metal command buffers do not return to their pool on release, nor do they support the
	// concept of a reset. In order to become available again in their pool, they must pass
	// through the commit step. This is unfortunate because if the app adds commands to this
	// command buffer and then chooses to reset it instead of submit it, we risk committing
	// a prefilled Metal command buffer that the app did not intend to submit, potentially
	// causing unexpected side effects. But unfortunately there is nothing else we can do.
	if (_prefilledMTLCmdBuffer && _prefilledMTLCmdBuffer.status == MTLCommandBufferStatusNotEnqueued) {
		[_prefilledMTLCmdBuffer commit];
	}

	[_prefilledMTLCmdBuffer release];
	_prefilledMTLCmdBuffer = nil;
}

#pragma mark Construction

// Initializes this instance after it has been created or retrieved from a pool.
void MVKCommandBuffer::init(const VkCommandBufferAllocateInfo* pAllocateInfo) {
	_commandPool = (MVKCommandPool*)pAllocateInfo->commandPool;
	_isSecondary = (pAllocateInfo->level == VK_COMMAND_BUFFER_LEVEL_SECONDARY);

	reset(0);
}

MVKCommandBuffer::~MVKCommandBuffer() {
	reset(0);
}

// Promote the initial visibility buffer and indication of timestamp use from the secondary buffers.
void MVKCommandBuffer::recordExecuteCommands(MVKArrayRef<MVKCommandBuffer*const> secondaryCommandBuffers) {
	for (MVKCommandBuffer* cmdBuff : secondaryCommandBuffers) {
		if (cmdBuff->_needsVisibilityResultMTLBuffer) { _needsVisibilityResultMTLBuffer = true; }
		if (cmdBuff->_hasStageCounterTimestampCommand) { _hasStageCounterTimestampCommand = true; }
	}
}

// Track whether a stage-based timestamp command has been added, so we know
// to update the timestamp command fence when ending a Metal command encoder.
void MVKCommandBuffer::recordTimestampCommand() {
	_hasStageCounterTimestampCommand = mvkIsAnyFlagEnabled(getMetalFeatures().counterSamplingPoints, MVK_COUNTER_SAMPLING_AT_PIPELINE_STAGE);
}


#pragma mark -
#pragma mark Tessellation constituent command management

void MVKCommandBuffer::recordBindPipeline(MVKCmdBindPipeline* mvkBindPipeline) {
	_lastTessellationPipeline = mvkBindPipeline->isTessellationPipeline() ? mvkBindPipeline : nullptr;
}


#pragma mark -
#pragma mark MVKCommandEncoder

// Activity performance tracking is put here to deliberately exclude when
// MVKConfiguration::prefillMetalCommandBuffers is set to immediate prefilling,
// because that would include app time between command submissions.
void MVKCommandEncoder::encode(id<MTLCommandBuffer> mtlCmdBuff,
							   MVKCommandEncodingContext* pEncodingContext) {
	uint64_t startTime = getPerformanceTimestamp();

    beginEncoding(mtlCmdBuff, pEncodingContext);
    encodeCommands(_cmdBuffer->_head);
    endEncoding();

	addPerformanceInterval(getPerformanceStats().queue.commandBufferEncoding, startTime);
}

void MVKCommandEncoder::beginEncoding(id<MTLCommandBuffer> mtlCmdBuff, MVKCommandEncodingContext* pEncodingContext) {
	_pEncodingContext = pEncodingContext;

    _subpassContents = VK_SUBPASS_CONTENTS_INLINE;
    _renderSubpassIndex = 0;
    _multiviewPassIndex = 0;
    _canUseLayeredRendering = false;

    _mtlCmdBuffer = mtlCmdBuff;        // not retained

	_cmdBuffer->setMetalObjectLabel(_mtlCmdBuffer, _cmdBuffer->_debugName);
}

// Multithread autorelease prefill style uses a dedicated autorelease pool when encoding each command.
void MVKCommandEncoder::encodeCommands(MVKCommand* command) {
	if (_prefillStyle == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_IMMEDIATE_ENCODING) {
		@autoreleasepool {
			encodeCommandsImpl(command);
		}
	} else {
		encodeCommandsImpl(command);
	}
}

void MVKCommandEncoder::encodeCommandsImpl(MVKCommand* command) {
    while(command) {
        uint32_t prevMVPassIdx = _multiviewPassIndex;
        command->encode(this);

        if(_multiviewPassIndex > prevMVPassIdx) {
            // This means we're in a multiview render pass, and we moved on to the
            // next view group. Re-encode all commands in the subpass again for this group.
            
            command = _lastMultiviewPassCmd->_next;
        } else {
            command = command->_next;
        }
    }
}

void MVKCommandEncoder::endEncoding() {
	endCurrentMetalEncoding();
	finishQueries();
}

void MVKCommandEncoder::encodeSecondary(MVKCommandBuffer* secondaryCmdBuffer) {
	MVKCommand* cmd = secondaryCmdBuffer->_head;
	while (cmd) {
		cmd->encode(this);
		cmd = cmd->_next;
	}
}

void MVKCommandEncoder::beginRendering(MVKCommand* rendCmd, const VkRenderingInfo* pRenderingInfo) {

	VkSubpassContents contents = (mvkIsAnyFlagEnabled(pRenderingInfo->flags, VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT)
								  ? VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS
								  : VK_SUBPASS_CONTENTS_INLINE);

	uint32_t maxAttCnt = (pRenderingInfo->colorAttachmentCount + 2) * 2;
	MVKImageView* imageViews[maxAttCnt];
	VkClearValue clearValues[maxAttCnt];

	uint32_t attCnt = 0;
	MVKRenderingAttachmentIterator attIter(pRenderingInfo);
	attIter.iterate([&](const VkRenderingAttachmentInfo* pAttInfo, VkImageAspectFlagBits aspect, bool isResolveAttachment)->void {
		imageViews[attCnt] = (MVKImageView*)(isResolveAttachment ? pAttInfo->resolveImageView : pAttInfo->imageView);
		clearValues[attCnt] = pAttInfo->clearValue;
		attCnt++;
	});

	// If we're resuming a suspended renderpass, continue to use the existing renderpass
	// (with updated rendering flags) and framebuffer. Otherwise, create new transient
	// renderpass and framebuffer objects from the pRenderingInfo, and retain them until
	// the renderpass is completely finished, which may span multiple command encoders.
	MVKRenderPass* mvkRP;
	MVKFramebuffer* mvkFB;
	bool isResumingSuspended = (mvkIsAnyFlagEnabled(_pEncodingContext->getRenderingFlags(), VK_RENDERING_SUSPENDING_BIT) &&
								mvkIsAnyFlagEnabled(pRenderingInfo->flags, VK_RENDERING_RESUMING_BIT));
	if (isResumingSuspended) {
		mvkRP = _pEncodingContext->getRenderPass();
		mvkRP->setRenderingFlags(pRenderingInfo->flags);
		mvkFB = _pEncodingContext->getFramebuffer();
	} else {
		auto* mvkDev = getDevice();
		mvkRP = mvkDev->createRenderPass(pRenderingInfo, nullptr);
		mvkFB = mvkDev->createFramebuffer(pRenderingInfo, nullptr);
	}
	beginRenderpass(rendCmd, contents, mvkRP, mvkFB,
					pRenderingInfo->renderArea,
					MVKArrayRef(clearValues, attCnt),
					MVKArrayRef(imageViews, attCnt),
					kMVKCommandUseBeginRendering);

	// If we've just created new transient objects, once retained by this encoder,
	// mark the objects as transient by releasing them from their initial creation
	// retain, so they will be destroyed when released at the end of the renderpass,
	// which may span multiple command encoders.
	if ( !isResumingSuspended ) {
		mvkRP->release();
		mvkFB->release();
	}
}

void MVKCommandEncoder::beginRenderpass(MVKCommand* passCmd,
										VkSubpassContents subpassContents,
										MVKRenderPass* renderPass,
										MVKFramebuffer* framebuffer,
										const VkRect2D& renderArea,
										MVKArrayRef<VkClearValue> clearValues,
										MVKArrayRef<MVKImageView*> attachments,
										MVKCommandUse cmdUse) {
	_pEncodingContext->setRenderingContext(renderPass, framebuffer);
	_renderArea = renderArea;
	_isRenderingEntireAttachment = (mvkVkOffset2DsAreEqual(_renderArea.offset, {0,0}) &&
									mvkVkExtent2DsAreEqual(_renderArea.extent, getFramebufferExtent()));
	_clearValues.assign(clearValues.begin(), clearValues.end());
	_attachments.assign(attachments.begin(), attachments.end());

	setSubpass(passCmd, subpassContents, 0, cmdUse);
}

void MVKCommandEncoder::beginNextSubpass(MVKCommand* subpassCmd, VkSubpassContents contents) {
	if (hasMoreMultiviewPasses()) {
		beginNextMultiviewPass();
	} else {
		setSubpass(subpassCmd, contents, _renderSubpassIndex + 1, kMVKCommandUseNextSubpass);
	}
}

// Sets the current render subpass to the subpass with the specified index.
// End current Metal renderpass before udpating subpass index.
void MVKCommandEncoder::setSubpass(MVKCommand* subpassCmd,
								   VkSubpassContents subpassContents,
								   uint32_t subpassIndex,
								   MVKCommandUse cmdUse) {
	encodeStoreActions();
	encodeBarrierUpdates();
	endMetalRenderEncoding();

	_lastMultiviewPassCmd = subpassCmd;
	_subpassContents = subpassContents;
	_renderSubpassIndex = subpassIndex;
	_multiviewPassIndex = 0;

	auto& mtlFeats = getMetalFeatures();
	_canUseLayeredRendering = mtlFeats.layeredRendering && (mtlFeats.multisampleLayeredRendering || getSubpass()->getSampleCount() == VK_SAMPLE_COUNT_1_BIT);

	beginMetalRenderPass(cmdUse);
}

bool MVKCommandEncoder::hasMoreMultiviewPasses() { return _multiviewPassIndex + 1 < getSubpass()->getMultiviewMetalPassCount(); }

void MVKCommandEncoder::beginNextMultiviewPass() {
	encodeStoreActions();
	_multiviewPassIndex++;
	beginMetalRenderPass(kMVKCommandUseNextSubpass);
}

// Retain encoders when prefilling, because prefilling may span multiple autorelease pools.
template<typename T>
void MVKCommandEncoder::retainIfImmediatelyEncoding(T& mtlEnc) {
	if (_cmdBuffer->_immediateCmdEncoder) { [mtlEnc retain]; }
}

// End Metal encoder and release retained encoders when immediately encoding.
template<typename T>
void MVKCommandEncoder::endMetalEncoding(T& mtlEnc) {
	[mtlEnc endEncoding];
	if (_cmdBuffer->_immediateCmdEncoder) { [mtlEnc release]; }
	mtlEnc = nil;
}

static MVKBarrierStage commandUseToBarrierStage(MVKCommandUse use) {
	switch (use) {
	case kMVKCommandUseNone:                         return kMVKBarrierStageNone; /**< No use defined. */
	case kMVKCommandUseBeginCommandBuffer:           return kMVKBarrierStageNone; /**< vkBeginCommandBuffer (prefilled VkCommandBuffer). */
	case kMVKCommandUseQueueSubmit:                  return kMVKBarrierStageNone; /**< vkQueueSubmit. */
	case kMVKCommandUseAcquireNextImage:             return kMVKBarrierStageNone; /**< vkAcquireNextImageKHR. */
	case kMVKCommandUseQueuePresent:                 return kMVKBarrierStageNone; /**< vkQueuePresentKHR. */
	case kMVKCommandUseQueueWaitIdle:                return kMVKBarrierStageNone; /**< vkQueueWaitIdle. */
	case kMVKCommandUseDeviceWaitIdle:               return kMVKBarrierStageNone; /**< vkDeviceWaitIdle. */
	case kMVKCommandUseInvalidateMappedMemoryRanges: return kMVKBarrierStageNone; /**< vkInvalidateMappedMemoryRanges. */
	case kMVKCommandUseBeginRendering:               return kMVKBarrierStageNone; /**< vkCmdBeginRendering. */
	case kMVKCommandUseBeginRenderPass:              return kMVKBarrierStageNone; /**< vkCmdBeginRenderPass. */
	case kMVKCommandUseNextSubpass:                  return kMVKBarrierStageNone; /**< vkCmdNextSubpass. */
	case kMVKCommandUseRestartSubpass:               return kMVKBarrierStageNone; /**< Create a new Metal renderpass due to Metal requirements. */
	case kMVKCommandUsePipelineBarrier:              return kMVKBarrierStageNone; /**< vkCmdPipelineBarrier. */
	case kMVKCommandUseBlitImage:                    return kMVKBarrierStageCopy; /**< vkCmdBlitImage. */
	case kMVKCommandUseCopyImage:                    return kMVKBarrierStageCopy; /**< vkCmdCopyImage. */
	case kMVKCommandUseResolveImage:                 return kMVKBarrierStageCopy; /**< vkCmdResolveImage - resolve stage. */
	case kMVKCommandUseResolveExpandImage:           return kMVKBarrierStageCopy; /**< vkCmdResolveImage - expand stage. */
	case kMVKCommandUseResolveCopyImage:             return kMVKBarrierStageCopy; /**< vkCmdResolveImage - copy stage. */
	case kMVKCommandUseCopyImageToMemory:            return kMVKBarrierStageCopy; /**< vkCopyImageToMemory host sync. */
	case kMVKCommandUseCopyBuffer:                   return kMVKBarrierStageCopy; /**< vkCmdCopyBuffer. */
	case kMVKCommandUseCopyBufferToImage:            return kMVKBarrierStageCopy; /**< vkCmdCopyBufferToImage. */
	case kMVKCommandUseCopyImageToBuffer:            return kMVKBarrierStageCopy; /**< vkCmdCopyImageToBuffer. */
	case kMVKCommandUseFillBuffer:                   return kMVKBarrierStageCopy; /**< vkCmdFillBuffer. */
	case kMVKCommandUseUpdateBuffer:                 return kMVKBarrierStageCopy; /**< vkCmdUpdateBuffer. */
	case kMVKCommandUseClearAttachments:             return kMVKBarrierStageNone; /**< vkCmdClearAttachments. */
	case kMVKCommandUseClearColorImage:              return kMVKBarrierStageCopy; /**< vkCmdClearColorImage. */
	case kMVKCommandUseClearDepthStencilImage:       return kMVKBarrierStageCopy; /**< vkCmdClearDepthStencilImage. */
	case kMVKCommandUseResetQueryPool:               return kMVKBarrierStageCopy; /**< vkCmdResetQueryPool. */
	case kMVKCommandUseDispatch:                     return kMVKBarrierStageCompute; /**< vkCmdDispatch. */
	case kMVKCommandUseTessellationVertexTessCtl:    return kMVKBarrierStageVertex; /**< vkCmdDraw* - vertex and tessellation control stages. */
	case kMVKCommandUseDrawIndirectConvertBuffers:   return kMVKBarrierStageVertex; /**< vkCmdDrawIndirect* convert indirect buffers. */
	case kMVKCommandUseCopyQueryPoolResults:         return kMVKBarrierStageCopy; /**< vkCmdCopyQueryPoolResults. */
	case kMVKCommandUseAccumOcclusionQuery:          return kMVKBarrierStageNone; /**< Any command terminating a Metal render pass with active visibility buffer. */
	case kMVKCommandConvertUint8Indices:             return kMVKBarrierStageCopy; /**< Converting a Uint8 index buffer to Uint16. */
	case kMVKCommandUseRecordGPUCounterSample:       return kMVKBarrierStageNone; /**< Any command triggering the recording of a GPU counter sample. */
	}
}



void MVKCommandEncoder::barrierWait(MVKBarrierStage stage, id<MTLRenderCommandEncoder> mtlEncoder, MTLRenderStages beforeStages) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
		auto fenceIndex = _pEncodingContext->fenceSlots.wait[stage][i];
		auto fence = _device->getFence((MVKBarrierStage)i, fenceIndex);
		[mtlEncoder waitForFence:fence beforeStages:beforeStages];
	}
}

void MVKCommandEncoder::barrierWait(MVKBarrierStage stage, id<MTLBlitCommandEncoder> mtlEncoder) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
		auto fenceIndex = _pEncodingContext->fenceSlots.wait[stage][i];
		auto fence = _device->getFence((MVKBarrierStage)i, fenceIndex);
		[mtlEncoder waitForFence:fence];
	}
}

void MVKCommandEncoder::barrierWait(MVKBarrierStage stage, id<MTLComputeCommandEncoder> mtlEncoder) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
		auto fenceIndex = _pEncodingContext->fenceSlots.wait[stage][i];
		auto fence = _device->getFence((MVKBarrierStage)i, fenceIndex);
		[mtlEncoder waitForFence:fence];
	}
}

void MVKCommandEncoder::barrierUpdate(MVKBarrierStage stage, id<MTLRenderCommandEncoder> mtlEncoder, MTLRenderStages afterStages) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	auto fence = getBarrierStageFence(stage);
	[mtlEncoder updateFence:fence afterStages:afterStages];
}

void MVKCommandEncoder::barrierUpdate(MVKBarrierStage stage, id<MTLBlitCommandEncoder> mtlEncoder) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	auto fence = getBarrierStageFence(stage);
	[mtlEncoder updateFence:fence];
}

void MVKCommandEncoder::barrierUpdate(MVKBarrierStage stage, id<MTLComputeCommandEncoder> mtlEncoder) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	auto fence = getBarrierStageFence(stage);
	[mtlEncoder updateFence:fence];
}

id<MTLFence> MVKCommandEncoder::getBarrierStageFence(MVKBarrierStage stage) {
	auto &fenceSlots = _pEncodingContext->fenceSlots;
	if (mvkAreAllFlagsEnabled(fenceSlots.updateDirtyBits, 1 << stage)) {
		mvkDisableFlags(fenceSlots.updateDirtyBits, 1 << stage);

		fenceSlots.update[stage] = (fenceSlots.update[stage] + 1) % kMVKBarrierFenceCount;
		if (fenceSlots.update[stage] == 0) fenceSlots.update[stage] = 1;
	}

	return _device->getFence(stage, fenceSlots.update[stage]);
}

void MVKCommandEncoder::setBarrier(uint64_t sourceStageMask, uint64_t destStageMask) {
	auto &fenceSlots = _pEncodingContext->fenceSlots;
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
	   if (!mvkIsAnyFlagEnabled(sourceStageMask, 1ull << i)) continue;

		for (int j = 0; j < kMVKBarrierStageCount; ++j) {
			if (!mvkIsAnyFlagEnabled(destStageMask, 1ull << j)) continue;

			fenceSlots.wait[j][i] = fenceSlots.update[i];
		}

		fenceSlots.wait[i][i] = fenceSlots.update[i];
		mvkEnableFlags(fenceSlots.updateDirtyBits, 1 << i);
	}
}


void MVKCommandEncoder::encodeBarrierWaits(MVKCommandUse use) {
	if (_mtlRenderEncoder) {
		[_mtlRenderEncoder insertDebugSignpost:@"Encoding waits"];
		barrierWait(kMVKBarrierStageVertex, _mtlRenderEncoder, MTLRenderStageVertex);
		barrierWait(kMVKBarrierStageFragment, _mtlRenderEncoder, MTLRenderStageFragment);
	}
	if (_mtlComputeEncoder) {
		auto stage = commandUseToBarrierStage(use);
		if (stage != kMVKBarrierStageNone) {
			barrierWait(stage, _mtlComputeEncoder);
		}
	}
	if (_mtlBlitEncoder) {
		auto stage = commandUseToBarrierStage(use);
		if (stage != kMVKBarrierStageNone) {
			barrierWait(stage, _mtlBlitEncoder);
		}
	}
}

void MVKCommandEncoder::encodeBarrierUpdates() {
	if (_mtlRenderEncoder) {
		barrierUpdate(kMVKBarrierStageVertex, _mtlRenderEncoder, MTLRenderStageVertex);
		barrierUpdate(kMVKBarrierStageFragment, _mtlRenderEncoder, MTLRenderStageFragment);
	}

	if (_mtlComputeEncoder) {
		MVKBarrierStage stage = commandUseToBarrierStage(_mtlComputeEncoderUse);
		if (stage != kMVKBarrierStageNone) {
			barrierUpdate(stage, _mtlComputeEncoder);
		}
	}

	if (_mtlBlitEncoder) {
		MVKBarrierStage stage = commandUseToBarrierStage(_mtlBlitEncoderUse);
		if (stage != kMVKBarrierStageNone) {
			barrierUpdate(stage, _mtlBlitEncoder);
		}
	}
}


// Creates _mtlRenderEncoder and marks cached render state as dirty so it will be set into the _mtlRenderEncoder.
void MVKCommandEncoder::beginMetalRenderPass(MVKCommandUse cmdUse) {

    endCurrentMetalEncoding();

	bool isRestart = cmdUse == kMVKCommandUseRestartSubpass;
    MTLRenderPassDescriptor* mtlRPDesc = [MTLRenderPassDescriptor renderPassDescriptor];
	getSubpass()->populateMTLRenderPassDescriptor(mtlRPDesc,
												  _multiviewPassIndex,
												  _pEncodingContext->getFramebuffer(),
												  _attachments.contents(),
												  _clearValues.contents(),
												  _isRenderingEntireAttachment,
												  isRestart);
	if (_cmdBuffer->_needsVisibilityResultMTLBuffer) {
		if ( !_pEncodingContext->visibilityResultBuffer ) {
			_pEncodingContext->visibilityResultBuffer = getTempMTLBuffer(getMetalFeatures().maxQueryBufferSize, true, true);
		}
		mtlRPDesc.visibilityResultBuffer = _pEncodingContext->visibilityResultBuffer->_mtlBuffer;
	}

	// Metal uses MTLRenderPassDescriptor properties renderTargetWidth, renderTargetHeight,
	// and renderTargetArrayLength to preallocate tile memory storage on machines using tiled
	// rendering. This memory preallocation is not necessary if we are not rendering to
	// attachments, and some apps actively define extremely oversized framebuffers when they
	// know they are not rendering to actual attachments, making this internal tile memory
	// allocation even more wasteful, occasionally to the point of triggering OOM crashes.
	VkExtent2D fbExtent = getFramebufferExtent();
    mtlRPDesc.renderTargetWidthMVK = max(min(_renderArea.offset.x + _renderArea.extent.width, fbExtent.width), 1u);
    mtlRPDesc.renderTargetHeightMVK = max(min(_renderArea.offset.y + _renderArea.extent.height, fbExtent.height), 1u);
    if (_canUseLayeredRendering) {
        uint32_t renderTargetArrayLength;
        bool found3D = false, found2D = false;
        for (uint32_t i = 0; i < 8; i++) {
            id<MTLTexture> mtlTex = mtlRPDesc.colorAttachments[i].texture;
            if (mtlTex == nil) { continue; }
            switch (mtlTex.textureType) {
                case MTLTextureType3D:
                    found3D = true;
                default:
                    found2D = true;
            }
        }

        if (getSubpass()->isMultiview()) {
            // In the case of a multiview pass, the framebuffer layer count will be one.
            // We need to use the view count for this multiview pass.
			renderTargetArrayLength = getSubpass()->getViewCountInMetalPass(_multiviewPassIndex);
        } else {
			renderTargetArrayLength = getFramebufferLayerCount();
        }
        // Metal does not allow layered render passes where some RTs are 3D and others are 2D.
        if (!(found3D && found2D) || renderTargetArrayLength > 1) {
            mtlRPDesc.renderTargetArrayLengthMVK = renderTargetArrayLength;
        }
    }

	// If programmable sample positions are supported, set them into the render pass descriptor.
	// If no custom sample positions are established, size will be zero,
	// and Metal will default to using default sample postions.
	if (getMetalFeatures().programmableSamplePositions) {
		auto sampPosns = _renderingState.getSamplePositions();
		[mtlRPDesc setSamplePositions: sampPosns.data() count: sampPosns.size()];
	}

    _mtlRenderEncoder = [_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];
	retainIfImmediatelyEncoding(_mtlRenderEncoder);
	_cmdBuffer->setMetalObjectLabel(_mtlRenderEncoder, getMTLRenderCommandEncoderName(cmdUse));

	encodeBarrierWaits(cmdUse);

	// We shouldn't clear the render area if we are restarting the Metal renderpass
	// separately from a Vulkan subpass, and we otherwise only need to clear render
	// area if we're not rendering to the entire attachment.
    if ( !isRestart && !_isRenderingEntireAttachment ) { clearRenderArea(cmdUse); }

    _graphicsPipelineState.beginMetalRenderPass();
    _graphicsResourcesState.beginMetalRenderPass();
	_depthStencilState.beginMetalRenderPass();
    _renderingState.beginMetalRenderPass();
    _vertexPushConstants.beginMetalRenderPass();
    _tessCtlPushConstants.beginMetalRenderPass();
    _tessEvalPushConstants.beginMetalRenderPass();
    _fragmentPushConstants.beginMetalRenderPass();
    _occlusionQueryState.beginMetalRenderPass();
}

void MVKCommandEncoder::restartMetalRenderPassIfNeeded() {
	if ( !_mtlRenderEncoder ) { return; }

	if (_renderingState.needsMetalRenderPassRestart()) {
		encodeStoreActions(true);
		beginMetalRenderPass(kMVKCommandUseRestartSubpass);
	}
}

void MVKCommandEncoder::encodeStoreActions(bool storeOverride) {
	getSubpass()->encodeStoreActions(this,
									 _isRenderingEntireAttachment,
									 _attachments.contents(),
									 storeOverride);
}

MVKRenderSubpass* MVKCommandEncoder::getSubpass() { return _pEncodingContext->getRenderPass()->getSubpass(_renderSubpassIndex); }

// Returns a name for use as a MTLRenderCommandEncoder label
NSString* MVKCommandEncoder::getMTLRenderCommandEncoderName(MVKCommandUse cmdUse) {
	NSString* rpName;

	rpName = _pEncodingContext->getRenderPass()->getDebugName();
	if (rpName) { return rpName; }

	rpName = _cmdBuffer->getDebugName();
	if (rpName) { return rpName; }

	return mvkMTLRenderCommandEncoderLabel(cmdUse);
}

VkExtent2D MVKCommandEncoder::getFramebufferExtent() {
	auto* mvkFB = _pEncodingContext->getFramebuffer();
	return mvkFB ? mvkFB->getExtent2D() : VkExtent2D{0,0};
}

uint32_t MVKCommandEncoder::getFramebufferLayerCount() {
	auto* mvkFB = _pEncodingContext->getFramebuffer();
	return mvkFB ? mvkFB->getLayerCount() : 0;
}

void MVKCommandEncoder::bindPipeline(VkPipelineBindPoint pipelineBindPoint, MVKPipeline* pipeline) {
    switch (pipelineBindPoint) {
        case VK_PIPELINE_BIND_POINT_GRAPHICS:
            _graphicsPipelineState.bindPipeline(pipeline);
            break;

        case VK_PIPELINE_BIND_POINT_COMPUTE:
            _computePipelineState.bindPipeline(pipeline);
            break;

        default:
            break;
    }
}

void MVKCommandEncoder::bindDescriptorSet(VkPipelineBindPoint pipelineBindPoint,
										  uint32_t descSetIndex,
										  MVKDescriptorSet* descSet,
										  MVKShaderResourceBinding& dslMTLRezIdxOffsets,
										  MVKArrayRef<uint32_t> dynamicOffsets,
										  uint32_t& dynamicOffsetIndex) {
	switch (pipelineBindPoint) {
		case VK_PIPELINE_BIND_POINT_GRAPHICS:
			_graphicsResourcesState.bindDescriptorSet(descSetIndex, descSet, dslMTLRezIdxOffsets,
													  dynamicOffsets, dynamicOffsetIndex);
			break;

		case VK_PIPELINE_BIND_POINT_COMPUTE:
			_computeResourcesState.bindDescriptorSet(descSetIndex, descSet, dslMTLRezIdxOffsets,
													 dynamicOffsets, dynamicOffsetIndex);
			break;

		default:
			break;
	}
}

void MVKCommandEncoder::signalEvent(MVKEvent* mvkEvent, bool status) {
	endCurrentMetalEncoding();
	mvkEvent->encodeSignal(_mtlCmdBuffer, status);
}

VkRect2D MVKCommandEncoder::clipToRenderArea(VkRect2D rect) {

	uint32_t raLeft = max(_renderArea.offset.x, 0);
	uint32_t raRight = raLeft + _renderArea.extent.width;
	uint32_t raBottom = max(_renderArea.offset.y, 0);
	uint32_t raTop = raBottom + _renderArea.extent.height;

	rect.offset.x      = mvkClamp<uint32_t>(rect.offset.x, raLeft, max(raRight - 1, raLeft));
	rect.offset.y      = mvkClamp<uint32_t>(rect.offset.y, raBottom, max(raTop - 1, raBottom));
	rect.extent.width  = min<uint32_t>(rect.extent.width, raRight - rect.offset.x);
	rect.extent.height = min<uint32_t>(rect.extent.height, raTop - rect.offset.y);

	return rect;
}

MTLScissorRect MVKCommandEncoder::clipToRenderArea(MTLScissorRect scissor) {
	return mvkMTLScissorRectFromVkRect2D(clipToRenderArea(mvkVkRect2DFromMTLScissorRect(scissor)));
}

void MVKCommandEncoder::finalizeDrawState(MVKGraphicsStage stage) {
    if (stage == kMVKGraphicsStageVertex) {
        // Must happen before switching encoders.
        encodeStoreActions(true);
    }
    _graphicsPipelineState.encode(stage);    	// Must do first..it sets others
	_depthStencilState.encode(stage);
    _graphicsResourcesState.encode(stage);   	// Before push constants, to allow them to override.
    _vertexPushConstants.encode(stage);
    _tessCtlPushConstants.encode(stage);
    _tessEvalPushConstants.encode(stage);
    _fragmentPushConstants.encode(stage);
	_gpuAddressableBuffersState.encode(stage);	// After resources and push constants
	_renderingState.encode(stage);
    _occlusionQueryState.encode(stage);
}

// Clears the render area of the framebuffer attachments.
void MVKCommandEncoder::clearRenderArea(MVKCommandUse cmdUse) {

	MVKClearAttachments clearAtts;
	getSubpass()->populateClearAttachments(clearAtts, _clearValues.contents());

	uint32_t clearAttCnt = (uint32_t)clearAtts.size();

	if (clearAttCnt == 0) { return; }

	if (!getSubpass()->isMultiview()) {
		VkClearRect clearRect;
		clearRect.rect = _renderArea;
		clearRect.baseArrayLayer = 0;
		clearRect.layerCount = getFramebufferLayerCount();

		// Create and execute a temporary clear attachments command.
		// To be threadsafe...do NOT acquire and return the command from the pool.
		MVKCmdClearMultiAttachments<1> cmd;
		cmd.setContent(_cmdBuffer, clearAttCnt, clearAtts.data(), 1, &clearRect, cmdUse);
		cmd.encode(this);
	} else {
		// For multiview, it is possible that some attachments need different layers cleared.
		// In that case, we'll have to clear them individually. :/
		for (auto& clearAtt : clearAtts) {
			MVKSmallVector<VkClearRect, 1> clearRects;
			getSubpass()->populateMultiviewClearRects(clearRects, this, clearAtt.colorAttachment, clearAtt.aspectMask);
			// Create and execute a temporary clear attachments command.
			// To be threadsafe...do NOT acquire and return the command from the pool.
			if (clearRects.size() == 1) {
				MVKCmdClearSingleAttachment<1> cmd;
				cmd.setContent(_cmdBuffer, 1, &clearAtt, (uint32_t)clearRects.size(), clearRects.data(), cmdUse);
				cmd.encode(this);
			} else {
				MVKCmdClearSingleAttachment<4> cmd;
				cmd.setContent(_cmdBuffer, 1, &clearAtt, (uint32_t)clearRects.size(), clearRects.data(), cmdUse);
				cmd.encode(this);
			}
		}
	}
}

void MVKCommandEncoder::beginMetalComputeEncoding(MVKCommandUse cmdUse) {
	if (cmdUse == kMVKCommandUseTessellationVertexTessCtl) {
		_graphicsResourcesState.beginMetalComputeEncoding();
	} else {
		_computeResourcesState.beginMetalComputeEncoding();
	}
}

void MVKCommandEncoder::finalizeDispatchState() {
    _computePipelineState.encode();    		// Must do first..it sets others
    _computeResourcesState.encode();   		// Before push constants, to allow them to override.
    _computePushConstants.encode();
	_gpuAddressableBuffersState.encode();	// After resources and push constants
}

void MVKCommandEncoder::endRendering() {
	endRenderpass();
}

void MVKCommandEncoder::endRenderpass() {
	if (hasMoreMultiviewPasses()) {
		beginNextMultiviewPass();
		return;
	}

	encodeStoreActions();
	encodeBarrierUpdates();
	endMetalRenderEncoding();
	if ( !mvkIsAnyFlagEnabled(_pEncodingContext->getRenderingFlags(), VK_RENDERING_SUSPENDING_BIT) ) {
		_pEncodingContext->setRenderingContext(nullptr, nullptr);
	}
	_attachments.clear();
	_renderSubpassIndex = 0;
}

void MVKCommandEncoder::endMetalRenderEncoding() {
    if (_mtlRenderEncoder == nil) { return; }

	if (_cmdBuffer->_hasStageCounterTimestampCommand) { [_mtlRenderEncoder updateFence: getStageCountersMTLFence() afterStages: MTLRenderStageFragment]; }
	endMetalEncoding(_mtlRenderEncoder);

	getSubpass()->resolveUnresolvableAttachments(this, _attachments.contents());

    _graphicsPipelineState.endMetalRenderPass();
    _graphicsResourcesState.endMetalRenderPass();
	_depthStencilState.endMetalRenderPass();
    _renderingState.endMetalRenderPass();
    _vertexPushConstants.endMetalRenderPass();
    _tessCtlPushConstants.endMetalRenderPass();
    _tessEvalPushConstants.endMetalRenderPass();
    _fragmentPushConstants.endMetalRenderPass();
    _occlusionQueryState.endMetalRenderPass();
}

void MVKCommandEncoder::endCurrentMetalEncoding() {
	encodeBarrierUpdates();
	endMetalRenderEncoding();

	_computePipelineState.markDirty();
	_computePushConstants.markDirty();
	_computeResourcesState.markDirty();

	if (_mtlComputeEncoder && _cmdBuffer->_hasStageCounterTimestampCommand) { [_mtlComputeEncoder updateFence: getStageCountersMTLFence()]; }
	endMetalEncoding(_mtlComputeEncoder);
	_mtlComputeEncoderUse = kMVKCommandUseNone;

	if (_mtlBlitEncoder && _cmdBuffer->_hasStageCounterTimestampCommand) { [_mtlBlitEncoder updateFence: getStageCountersMTLFence()]; }
	endMetalEncoding(_mtlBlitEncoder);
    _mtlBlitEncoderUse = kMVKCommandUseNone;

	encodeTimestampStageCounterSamples();
}

id<MTLComputeCommandEncoder> MVKCommandEncoder::getMTLComputeEncoder(MVKCommandUse cmdUse, bool markCurrentComputeStateDirty) {
	bool needWaits = false;
	if ( !_mtlComputeEncoder ) {
		needWaits = true;
		endCurrentMetalEncoding();
		_mtlComputeEncoder = [_mtlCmdBuffer computeCommandEncoder];
		retainIfImmediatelyEncoding(_mtlComputeEncoder);
		beginMetalComputeEncoding(cmdUse);
		markCurrentComputeStateDirty = false;	// Already marked dirty above in endCurrentMetalEncoding()
	}
	if(markCurrentComputeStateDirty) {
		_computePipelineState.markDirty();
		_computePushConstants.markDirty();
		_computeResourcesState.markDirty();
	}
	if (_mtlComputeEncoderUse != cmdUse) {
		needWaits = true;
		_mtlComputeEncoderUse = cmdUse;
		_cmdBuffer->setMetalObjectLabel(_mtlComputeEncoder, mvkMTLComputeCommandEncoderLabel(cmdUse));
	}
	if (needWaits) {
		encodeBarrierWaits(cmdUse);
	}
	return _mtlComputeEncoder;
}

id<MTLBlitCommandEncoder> MVKCommandEncoder::getMTLBlitEncoder(MVKCommandUse cmdUse) {
	bool needWaits = false;
	if ( !_mtlBlitEncoder ) {
		needWaits = true;
		endCurrentMetalEncoding();
		_mtlBlitEncoder = [_mtlCmdBuffer blitCommandEncoder];
		retainIfImmediatelyEncoding(_mtlBlitEncoder);
	}
    if (_mtlBlitEncoderUse != cmdUse) {
		needWaits = true;
        _mtlBlitEncoderUse = cmdUse;
		_cmdBuffer->setMetalObjectLabel(_mtlBlitEncoder, mvkMTLBlitCommandEncoderLabel(cmdUse));
    }
	if (needWaits) {
		encodeBarrierWaits(cmdUse);
	}
	return _mtlBlitEncoder;
}

id<MTLCommandEncoder> MVKCommandEncoder::getMTLEncoder(){
	if (_mtlRenderEncoder) { return _mtlRenderEncoder; }
	if (_mtlComputeEncoder) { return _mtlComputeEncoder; }
	if (_mtlBlitEncoder) { return _mtlBlitEncoder; }
	return nil;
}

MVKPushConstantsCommandEncoderState* MVKCommandEncoder::getPushConstants(VkShaderStageFlagBits shaderStage) {
	switch (shaderStage) {
		case VK_SHADER_STAGE_VERTEX_BIT:					return &_vertexPushConstants;
		case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:		return &_tessCtlPushConstants;
		case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:	return &_tessEvalPushConstants;
		case VK_SHADER_STAGE_FRAGMENT_BIT:					return &_fragmentPushConstants;
		case VK_SHADER_STAGE_COMPUTE_BIT:					return &_computePushConstants;
		default:
			MVKAssert(false, "Invalid shader stage: %u", shaderStage);
			return nullptr;
	}
}

void MVKCommandEncoder::setVertexBytes(id<MTLRenderCommandEncoder> mtlEncoder,
                                       const void* bytes,
                                       NSUInteger length,
									   uint32_t mtlBuffIndex,
									   bool descOverride) {
	auto& mtlFeats = getMetalFeatures();
    if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
        [mtlEncoder setVertexBytes: bytes length: length atIndex: mtlBuffIndex];
    } else {
        const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
        [mtlEncoder setVertexBuffer: mtlBuffAlloc->_mtlBuffer offset: mtlBuffAlloc->_offset atIndex: mtlBuffIndex];
    }

	if (descOverride) {
		_graphicsResourcesState.markBufferIndexOverridden(kMVKShaderStageVertex, mtlBuffIndex);
	}
}

void MVKCommandEncoder::encodeVertexAttributeBuffer(MVKMTLBufferBinding& b, bool isDynamicStride) {
	if (getMetalFeatures().dynamicVertexStride) {
#if MVK_XCODE_15
		NSUInteger mtlStride = isDynamicStride ? b.stride : MTLAttributeStrideStatic;
		if (b.isInline) {
			[_mtlRenderEncoder setVertexBytes: b.mtlBytes
									   length: b.size
							  attributeStride: mtlStride
									  atIndex: b.index];
		} else if (b.justOffset) {
			[_mtlRenderEncoder setVertexBufferOffset: b.offset
									 attributeStride: mtlStride
											 atIndex: b.index];
		} else {
			[_mtlRenderEncoder setVertexBuffer: b.mtlBuffer
										offset: b.offset
							   attributeStride: mtlStride
									   atIndex: b.index];
		}
#endif
	} else {
		if (b.isInline) {
			[_mtlRenderEncoder setVertexBytes: b.mtlBytes
									   length: b.size
									  atIndex: b.index];
		} else if (b.justOffset) {
			[_mtlRenderEncoder setVertexBufferOffset: b.offset
											 atIndex: b.index];
		} else {
			[_mtlRenderEncoder setVertexBuffer: b.mtlBuffer
										offset: b.offset
									   atIndex: b.index];
		}
	}
}

void MVKCommandEncoder::setFragmentBytes(id<MTLRenderCommandEncoder> mtlEncoder,
                                         const void* bytes,
                                         NSUInteger length,
										 uint32_t mtlBuffIndex,
										 bool descOverride) {
	auto& mtlFeats = getMetalFeatures();
    if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
        [mtlEncoder setFragmentBytes: bytes length: length atIndex: mtlBuffIndex];
    } else {
        const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
        [mtlEncoder setFragmentBuffer: mtlBuffAlloc->_mtlBuffer offset: mtlBuffAlloc->_offset atIndex: mtlBuffIndex];
    }

	if (descOverride) {
		_graphicsResourcesState.markBufferIndexOverridden(kMVKShaderStageFragment, mtlBuffIndex);
	}
}

void MVKCommandEncoder::setComputeBytes(id<MTLComputeCommandEncoder> mtlEncoder,
                                        const void* bytes,
                                        NSUInteger length,
                                        uint32_t mtlBuffIndex,
										bool descOverride) {
	auto& mtlFeats = getMetalFeatures();
	if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
        [mtlEncoder setBytes: bytes length: length atIndex: mtlBuffIndex];
    } else {
        const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
        [mtlEncoder setBuffer: mtlBuffAlloc->_mtlBuffer offset: mtlBuffAlloc->_offset atIndex: mtlBuffIndex];
    }

	if (descOverride) {
		_computeResourcesState.markBufferIndexOverridden(mtlBuffIndex);
	}
}

void MVKCommandEncoder::setComputeBytesWithStride(id<MTLComputeCommandEncoder> mtlEncoder,
                                                  const void* bytes,
                                                  NSUInteger length,
                                                  uint32_t mtlBuffIndex,
                                                  uint32_t stride,
                                                  bool descOverride) {
	auto& mtlFeats = getMetalFeatures();
	if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
		[mtlEncoder setBytes: bytes length: length attributeStride: stride atIndex: mtlBuffIndex];
	} else {
		const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
		[mtlEncoder setBuffer: mtlBuffAlloc->_mtlBuffer offset: mtlBuffAlloc->_offset attributeStride: stride atIndex: mtlBuffIndex];
	}

	if (descOverride) {
		_computeResourcesState.markBufferIndexOverridden(mtlBuffIndex);
	}
}

// Return the MTLBuffer allocation to the pool once the command buffer is done with it
const MVKMTLBufferAllocation* MVKCommandEncoder::getTempMTLBuffer(NSUInteger length, bool isPrivate, bool isDedicated) {
    MVKMTLBufferAllocation* mtlBuffAlloc = getCommandEncodingPool()->acquireMTLBufferAllocation(length, isPrivate, isDedicated);
    [_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mcb) { mtlBuffAlloc->returnToPool(); }];
    return mtlBuffAlloc;
}

MVKCommandEncodingPool* MVKCommandEncoder::getCommandEncodingPool() {
	return _cmdBuffer->getCommandPool()->getCommandEncodingPool();
}

// Copies the specified bytes into a temporary allocation within a pooled MTLBuffer, and returns the MTLBuffer allocation.
const MVKMTLBufferAllocation* MVKCommandEncoder::copyToTempMTLBufferAllocation(const void* bytes, NSUInteger length, bool isDedicated) {
	const MVKMTLBufferAllocation* mtlBuffAlloc = getTempMTLBuffer(length, false, isDedicated);
    void* pBuffData = mtlBuffAlloc->getContents();
    memcpy(pBuffData, bytes, length);

    return mtlBuffAlloc;
}


#pragma mark Queries

// Only executes on immediate-mode GPUs. Encode a GPU counter sample command on whichever Metal
// encoder is currently in use, creating a temporary BLIT encoder if no encoder is currently active.
// We only encode the GPU sample if the platform allows encoding at the associated pipeline point.
void MVKCommandEncoder::encodeGPUCounterSample(MVKGPUCounterQueryPool* mvkQryPool, uint32_t sampleIndex, MVKCounterSamplingFlags samplingPoints){
	if (_mtlRenderEncoder) {
		if (mvkIsAnyFlagEnabled(samplingPoints, MVK_COUNTER_SAMPLING_AT_DRAW)) {
			[_mtlRenderEncoder sampleCountersInBuffer: mvkQryPool->getMTLCounterBuffer() atSampleIndex: sampleIndex withBarrier: YES];
		}
	} else if (_mtlComputeEncoder) {
		if (mvkIsAnyFlagEnabled(samplingPoints, MVK_COUNTER_SAMPLING_AT_DISPATCH)) {
			[_mtlComputeEncoder sampleCountersInBuffer: mvkQryPool->getMTLCounterBuffer() atSampleIndex: sampleIndex withBarrier: YES];
		}
	} else if (mvkIsAnyFlagEnabled(samplingPoints, MVK_COUNTER_SAMPLING_AT_BLIT)) {
		[getMTLBlitEncoder(kMVKCommandUseRecordGPUCounterSample) sampleCountersInBuffer: mvkQryPool->getMTLCounterBuffer() atSampleIndex: sampleIndex withBarrier: YES];
	} else if (mvkIsAnyFlagEnabled(samplingPoints, MVK_COUNTER_SAMPLING_AT_DISPATCH)) {
		// Workaround for broken 10.15 AMD driver which crashes if you try to record to an empty blit encoder
		[getMTLComputeEncoder(kMVKCommandUseRecordGPUCounterSample) sampleCountersInBuffer: mvkQryPool->getMTLCounterBuffer() atSampleIndex: sampleIndex withBarrier: YES];
	}
}

void MVKCommandEncoder::beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
    _occlusionQueryState.beginOcclusionQuery(pQueryPool, query, flags);
    uint32_t queryCount = 1;
    if (isInRenderPass() && getSubpass()->isMultiview()) {
        queryCount = getSubpass()->getViewCountInMetalPass(_multiviewPassIndex);
    }
    addActivatedQueries(pQueryPool, query, queryCount);
}

void MVKCommandEncoder::endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
    _occlusionQueryState.endOcclusionQuery(pQueryPool, query);
}

void MVKCommandEncoder::markTimestamp(MVKTimestampQueryPool* pQueryPool, uint32_t query) {
    uint32_t queryCount = 1;
    if (isInRenderPass() && getSubpass()->isMultiview()) {
        queryCount = getSubpass()->getViewCountInMetalPass(_multiviewPassIndex);
    }
	addActivatedQueries(pQueryPool, query, queryCount);

	if (pQueryPool->hasMTLCounterBuffer()) {
		MVKCounterSamplingFlags sampPts = getMetalFeatures().counterSamplingPoints;
		for (uint32_t qOfst = 0; qOfst < queryCount; qOfst++) {
			if (mvkIsAnyFlagEnabled(sampPts, MVK_COUNTER_SAMPLING_AT_PIPELINE_STAGE)) {
				_timestampStageCounterQueries.push_back({ pQueryPool, query + qOfst });
			} else {
				encodeGPUCounterSample(pQueryPool, query + qOfst, sampPts);
			}
		}
	}
}

#if MVK_XCODE_12
// Metal stage GPU counters need to be configured in a Metal render, compute, or BLIT encoder, meaning that the
// Metal encoder needs to know about any Vulkan timestamp commands that will be executed during the execution
// of a renderpass, or set of Vulkan dispatch or BLIT commands. In addition, there are a very small number of
// staged timestamps that can be tracked in any single render, compute, or BLIT pass, meaning a renderpass
// that timestamped after each of many draw calls, would not be trackable. Finally, stage counters are only
// available on tile-based GPU's, which means draw or dispatch calls cannot be individually timestamped.
// We avoid dealing with all this complexity and mismatch between how Vulkan and Metal stage counters operate
// by deferring all timestamps to the end of any batch of Metal encoding, and add a lightweight Metal encoder
// that does minimal work (it won't timestamp if completely empty), and timestamps that work into all of the
// Vulkan timestamp queries that have been executed during the execution of the previous Metal encoder.
void MVKCommandEncoder::encodeTimestampStageCounterSamples() {
	size_t qCnt = _timestampStageCounterQueries.size();
	uint32_t qIdx = 0;
	while (qIdx < qCnt) {

		// With each BLIT pass, consume as many outstanding timestamp queries as possible.
		// Attach an query result to each of the available sample buffer attachments in the BLIT pass descriptor.
		// MTLMaxBlitPassSampleBuffers was defined in the Metal API as 4, but according to Apple, will be removed
		// in Xcode 13 as inaccurate for all platforms. Leave this value at 1 until we can figure out how to
		// accurately determine the length of sampleBufferAttachments on each platform.
		uint32_t maxMTLBlitPassSampleBuffers = 1;		// Was MTLMaxBlitPassSampleBuffers API definition
		auto* bpDesc = [MTLBlitPassDescriptor new];		// temp retained
		for (uint32_t attIdx = 0; attIdx < maxMTLBlitPassSampleBuffers && qIdx < qCnt; attIdx++, qIdx++) {
			auto* sbAttDesc = bpDesc.sampleBufferAttachments[attIdx];
			auto& tsQry = _timestampStageCounterQueries[qIdx];

			// We actually only need to use startOfEncoderSampleIndex, but apparently,
			// and contradicting docs, Metal hits an unexpected validation error if
			// endOfEncoderSampleIndex is left at MTLCounterDontSample.
			sbAttDesc.startOfEncoderSampleIndex = tsQry.query;
			sbAttDesc.endOfEncoderSampleIndex = tsQry.query;
			sbAttDesc.sampleBuffer = tsQry.queryPool->getMTLCounterBuffer();
		}

		auto* mtlEnc = [_mtlCmdBuffer blitCommandEncoderWithDescriptor: bpDesc];
		_cmdBuffer->setMetalObjectLabel(mtlEnc, mvkMTLBlitCommandEncoderLabel(kMVKCommandUseRecordGPUCounterSample));
		[bpDesc release];		// Release temp object
		[mtlEnc waitForFence: getStageCountersMTLFence()];
		[mtlEnc fillBuffer: _device->getDummyBlitMTLBuffer() range: NSMakeRange(0, 1) value: 0];
		[mtlEnc endEncoding];
	}
	_timestampStageCounterQueries.clear();
}
#else
void MVKCommandEncoder::encodeTimestampStageCounterSamples() {}
#endif

id<MTLFence> MVKCommandEncoder::getStageCountersMTLFence() {
	if ( !_stageCountersMTLFence ) {
		// Create MTLFence as local ref and pass to completion handler
		// block to release once MTLCommandBuffer no longer needs it.
		id<MTLFence> mtlFence = [getMTLDevice() newFence];
		[_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mcb) { [mtlFence release]; }];

		_stageCountersMTLFence = mtlFence;		// retained
	}
	return _stageCountersMTLFence;
}

void MVKCommandEncoder::resetQueries(MVKQueryPool* pQueryPool, uint32_t firstQuery, uint32_t queryCount) {
    addActivatedQueries(pQueryPool, firstQuery, queryCount);
}

// Marks the specified queries as activated
void MVKCommandEncoder::addActivatedQueries(MVKQueryPool* pQueryPool, uint32_t query, uint32_t queryCount) {
    if ( !_pActivatedQueries ) { _pActivatedQueries = new MVKActivatedQueries(); }
    uint32_t endQuery = query + queryCount;
    while (query < endQuery) {
        (*_pActivatedQueries)[pQueryPool].push_back(query++);
    }
}

// Register a command buffer completion handler that finishes each activated query.
// Ownership of the collection of activated queries is passed to the handler.
void MVKCommandEncoder::finishQueries() {
    if ( !_pActivatedQueries ) { return; }

    MVKActivatedQueries* pAQs = _pActivatedQueries;
    [_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mtlCmdBuff) {
        for (auto& qryPair : *pAQs) {
            qryPair.first->finishQueries(qryPair.second.contents());
        }
        delete pAQs;
    }];
    _pActivatedQueries = nullptr;
}


#pragma mark Construction

MVKCommandEncoder::MVKCommandEncoder(MVKCommandBuffer* cmdBuffer,
									 MVKPrefillMetalCommandBuffersStyle prefillStyle) : MVKBaseDeviceObject(cmdBuffer->getDevice()),
	_cmdBuffer(cmdBuffer),
	_graphicsPipelineState(this),
	_graphicsResourcesState(this),
	_computePipelineState(this),
	_computeResourcesState(this),
	_gpuAddressableBuffersState(this),
	_depthStencilState(this),
	_renderingState(this),
	_occlusionQueryState(this),
	_vertexPushConstants(this, VK_SHADER_STAGE_VERTEX_BIT),
	_tessCtlPushConstants(this, VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT),
	_tessEvalPushConstants(this, VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT),
	_fragmentPushConstants(this, VK_SHADER_STAGE_FRAGMENT_BIT),
	_computePushConstants(this, VK_SHADER_STAGE_COMPUTE_BIT),
	_prefillStyle(prefillStyle){

	_pActivatedQueries = nullptr;
	_mtlCmdBuffer = nil;
	_mtlRenderEncoder = nil;
	_mtlComputeEncoder = nil;
	_mtlComputeEncoderUse = kMVKCommandUseNone;
	_mtlBlitEncoder = nil;
	_mtlBlitEncoderUse = kMVKCommandUseNone;
	_pEncodingContext = nullptr;
	_stageCountersMTLFence = nil;
	_flushCount = 0;
}

MVKCommandEncoder::~MVKCommandEncoder() {
	[_mtlRenderEncoder release];
	[_mtlComputeEncoder release];
	[_mtlBlitEncoder release];
	// _stageCountersMTLFence is released after Metal command buffer completion
}


#pragma mark -
#pragma mark Support functions

NSString* mvkMTLRenderCommandEncoderLabel(MVKCommandUse cmdUse) {
    switch (cmdUse) {
		case kMVKCommandUseBeginRendering:                  return @"vkCmdBeginRendering RenderEncoder";
        case kMVKCommandUseBeginRenderPass:                 return @"vkCmdBeginRenderPass RenderEncoder";
        case kMVKCommandUseNextSubpass:                     return @"vkCmdNextSubpass RenderEncoder";
		case kMVKCommandUseRestartSubpass:                  return @"Metal renderpass restart RenderEncoder";
        case kMVKCommandUseBlitImage:                       return @"vkCmdBlitImage RenderEncoder";
        case kMVKCommandUseResolveImage:                    return @"vkCmdResolveImage (resolve stage) RenderEncoder";
        case kMVKCommandUseResolveExpandImage:              return @"vkCmdResolveImage (expand stage) RenderEncoder";
        case kMVKCommandUseClearColorImage:                 return @"vkCmdClearColorImage RenderEncoder";
        case kMVKCommandUseClearDepthStencilImage:          return @"vkCmdClearDepthStencilImage RenderEncoder";
        default:                                            return @"Unknown Use RenderEncoder";
    }
}

NSString* mvkMTLBlitCommandEncoderLabel(MVKCommandUse cmdUse) {
    switch (cmdUse) {
        case kMVKCommandUsePipelineBarrier:                 return @"vkCmdPipelineBarrier BlitEncoder";
        case kMVKCommandUseCopyImage:                       return @"vkCmdCopyImage BlitEncoder";
        case kMVKCommandUseResolveCopyImage:                return @"vkCmdResolveImage (copy stage) RenderEncoder";
        case kMVKCommandUseCopyBuffer:                      return @"vkCmdCopyBuffer BlitEncoder";
        case kMVKCommandUseCopyBufferToImage:               return @"vkCmdCopyBufferToImage BlitEncoder";
        case kMVKCommandUseCopyImageToBuffer:               return @"vkCmdCopyImageToBuffer BlitEncoder";
        case kMVKCommandUseFillBuffer:                      return @"vkCmdFillBuffer BlitEncoder";
        case kMVKCommandUseUpdateBuffer:                    return @"vkCmdUpdateBuffer BlitEncoder";
        case kMVKCommandUseResetQueryPool:                  return @"vkCmdResetQueryPool BlitEncoder";
        case kMVKCommandUseCopyQueryPoolResults:            return @"vkCmdCopyQueryPoolResults BlitEncoder";
		case kMVKCommandUseRecordGPUCounterSample:          return @"Record GPU Counter Sample BlitEncoder";
        default:                                            return @"Unknown Use BlitEncoder";
    }
}

NSString* mvkMTLComputeCommandEncoderLabel(MVKCommandUse cmdUse) {
    switch (cmdUse) {
        case kMVKCommandUseDispatch:                        return @"vkCmdDispatch ComputeEncoder";
        case kMVKCommandUseCopyBuffer:                      return @"vkCmdCopyBuffer ComputeEncoder";
        case kMVKCommandUseCopyBufferToImage:               return @"vkCmdCopyBufferToImage ComputeEncoder";
        case kMVKCommandUseCopyImageToBuffer:               return @"vkCmdCopyImageToBuffer ComputeEncoder";
        case kMVKCommandUseFillBuffer:                      return @"vkCmdFillBuffer ComputeEncoder";
        case kMVKCommandUseClearColorImage:                 return @"vkCmdClearColorImage ComputeEncoder";
		case kMVKCommandUseResolveImage:                    return @"Resolve Subpass Attachment ComputeEncoder";
        case kMVKCommandUseTessellationVertexTessCtl:       return @"vkCmdDraw (vertex and tess control stages) ComputeEncoder";
        case kMVKCommandUseDrawIndirectConvertBuffers:      return @"vkCmdDraw (convert indirect buffers) ComputeEncoder";
        case kMVKCommandUseCopyQueryPoolResults:            return @"vkCmdCopyQueryPoolResults ComputeEncoder";
        case kMVKCommandUseAccumOcclusionQuery:             return @"Post-render-pass occlusion query accumulation ComputeEncoder";
        case kMVKCommandConvertUint8Indices:                return @"Convert Uint8 indices to Uint16 ComputeEncoder";
        default:                                            return @"Unknown Use ComputeEncoder";
    }
}
