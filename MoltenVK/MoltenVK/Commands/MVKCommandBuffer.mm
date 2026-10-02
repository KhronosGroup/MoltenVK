/*
 * MVKCommandBuffer.mm
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
	const VkCommandBufferInheritanceRenderingInfo* pInheritRendInfo = nullptr;
	const VkRenderingAttachmentLocationInfo* pInheritAttLocInfo = nullptr;
	const VkRenderingInputAttachmentIndexInfo* pInheritInpAttIdxInfo = nullptr;
	_hasSecondaryInheritanceInfo = mvkSetOrClear(&_secondaryInheritanceInfo, pInheritInfo);
	if (_hasSecondaryInheritanceInfo) {
		for (const auto* next = (VkBaseInStructure*)_secondaryInheritanceInfo.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO:
					pInheritRendInfo = (VkCommandBufferInheritanceRenderingInfo*)next;
					break;
				case VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_LOCATION_INFO:
					pInheritAttLocInfo = (VkRenderingAttachmentLocationInfo*)next;
					break;
				case VK_STRUCTURE_TYPE_RENDERING_INPUT_ATTACHMENT_INDEX_INFO:
					pInheritInpAttIdxInfo = (VkRenderingInputAttachmentIndexInfo*)next;
					break;
				default:
					break;
			}
		}
	}

	_doesContinueRenderPass = mvkAreAllFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT) && _hasSecondaryInheritanceInfo;

	_hasSecondaryInheritanceRenderingInfo = mvkSetOrClear(&_secondaryInheritanceRenderingInfo, pInheritRendInfo);
	if (_hasSecondaryInheritanceRenderingInfo) {
		_secondaryInheritanceColorAttachmentFormats.assign(_secondaryInheritanceRenderingInfo.pColorAttachmentFormats,
														   _secondaryInheritanceRenderingInfo.pColorAttachmentFormats + _secondaryInheritanceRenderingInfo.colorAttachmentCount);
		_secondaryInheritanceRenderingInfo.pColorAttachmentFormats = _secondaryInheritanceColorAttachmentFormats.data();
	}

	if (_doesContinueRenderPass) {
		_currentSubpassInfo.renderpass = (MVKRenderPass*)_secondaryInheritanceInfo.renderPass;
		_currentSubpassInfo.subpassIndex = _secondaryInheritanceInfo.subpass;
		auto* framebuffer = (MVKFramebuffer*)_secondaryInheritanceInfo.framebuffer;
		auto attachments = framebuffer ? framebuffer->getAttachments() : MVKArrayRef<MVKImageView*>();
		// An empty inherited framebuffer may be imageless. Its actual views are only known by the primary.
		recordRenderPass(attachments, attachments.size() != 0);
		// Inherited sample count alone cannot tell us whether the primary has resolve views.
	}

	if (pInheritAttLocInfo) {
		_secondaryInheritanceColorAttachmentLocations.assign(pInheritAttLocInfo->pColorAttachmentLocations,
															 pInheritAttLocInfo->pColorAttachmentLocations + pInheritAttLocInfo->colorAttachmentCount);
		_hasSecondaryInheritanceColorAttachmentLocations = true;
	}

	if (pInheritInpAttIdxInfo) {
		if (pInheritInpAttIdxInfo->pColorAttachmentInputIndices) {
			_secondaryInheritanceColorAttachmentInputIndices.assign(pInheritInpAttIdxInfo->pColorAttachmentInputIndices,
																	pInheritInpAttIdxInfo->pColorAttachmentInputIndices + pInheritInpAttIdxInfo->colorAttachmentCount);
			_hasSecondaryInheritanceColorAttachmentInputIndices = true;
		}

		if (pInheritInpAttIdxInfo->pDepthInputAttachmentIndex) {
			_secondaryInheritanceDepthAttachmentInputIndex = *pInheritInpAttIdxInfo->pDepthInputAttachmentIndex;
			_hasSecondaryInheritanceDepthAttachmentInputIndex = true;
		}

		if (pInheritInpAttIdxInfo->pStencilInputAttachmentIndex) {
			_secondaryInheritanceStencilAttachmentInputIndex = *pInheritInpAttIdxInfo->pStencilInputAttachmentIndex;
			_hasSecondaryInheritanceStencilAttachmentInputIndex = true;
		}
	}

	// Immediate prefill encodes each command while it is recorded, before a queue submission exists to wait for the
	// GPU plan of a PerVertexKHR indirect draw. Devices that may capture PerVertexKHR draws encode at submission instead.
	auto prefillStyle = getMVKConfig().prefillMetalCommandBuffers;
	bool isImmediatePrefill = (prefillStyle == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_IMMEDIATE_ENCODING ||
							   prefillStyle == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_IMMEDIATE_ENCODING_NO_AUTORELEASE);
	bool mayAwaitGPUPlan = getPhysicalDevice()->isPortablePerVertexEnabled() && getEnabledFragmentShaderBarycentricFeatures().fragmentShaderBarycentric;
    if(_device->shouldPrefillMTLCommandBuffers() && !(_isSecondary || _supportsConcurrentExecution) && !(isImmediatePrefill && mayAwaitGPUPlan)) {
		@autoreleasepool {
			_prefilledMTLCmdBuffer = [_commandPool->getMTLCommandBuffer(kMVKCommandUseBeginCommandBuffer, 0) retain];    // retained
			if (isImmediatePrefill) {
				_immediateCmdEncodingContext = new MVKCommandEncodingContext;
				_immediateCmdEncodingContext->perVertexScratch = &_prefilledPerVertexScratch;
				_immediateCmdEncoder = new MVKCommandEncoder(this, prefillStyle);
				_immediateCmdEncoder->beginEncoding(_prefilledMTLCmdBuffer, _immediateCmdEncodingContext);
			}
		}
    }

    return getConfigurationResult();
}

void MVKCommandBuffer::beginSecondaryEncoding(MVKCommandEncoder* cmdEncoder) {
	if ( !_isSecondary ) { return; }

	if (_hasSecondaryInheritanceColorAttachmentLocations) {
		cmdEncoder->updateColorAttachmentLocations(_secondaryInheritanceColorAttachmentLocations.contents());
	}
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
        if (!_isReusable) { releaseRecordedCommands(); }
    }
}

VkResult MVKCommandBuffer::reset(VkCommandBufferResetFlags flags) {
    flushImmediateCmdEncoder();
	clearPrefilledMTLCommandBuffer();
	releaseRecordedCommands();
	_secondaryInheritanceInfo = {};
	_hasSecondaryInheritanceInfo = false;
	_secondaryInheritanceRenderingInfo = {};
	_hasSecondaryInheritanceRenderingInfo = false;
	_secondaryInheritanceColorAttachmentFormats.clear();
	_secondaryInheritanceColorAttachmentLocations.clear();
	_hasSecondaryInheritanceColorAttachmentLocations = false;
	_secondaryInheritanceColorAttachmentInputIndices.clear();
	_hasSecondaryInheritanceColorAttachmentInputIndices = false;
	_secondaryInheritanceDepthAttachmentInputIndex = 0;
	_hasSecondaryInheritanceDepthAttachmentInputIndex = false;
	_secondaryInheritanceStencilAttachmentInputIndex = 0;
	_hasSecondaryInheritanceStencilAttachmentInputIndex = false;
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
	_recordedPerVertexPipeline = nullptr;
	_recordedTessellationPipeline = nullptr;
	_recordedMeshPipeline = nullptr;
	_recordedPatchControlPoints = 0;
	_recordedPrimitiveTopology = VK_PRIMITIVE_TOPOLOGY_MAX_ENUM;
	_recordedAttachmentsKnown = false;
	_recordedRenderingError = nullptr;
	_recordedIndexType = VK_INDEX_TYPE_MAX_ENUM;
	_needsInheritedPerVertexAttachments = false;
	_perVertexScratchRequests.clear();
	_prefilledPerVertexScratch.clear();
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
	if (_prefilledMTLCmdBuffer && getMVKConfig().prefillMetalCommandBuffers == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_DEFERRED_ENCODING) {
		// An indirect PerVertexKHR draw or a PerVertex TES draw waits for its GPU plan or topology while encoding,
		// which needs its queue submission. Nothing is encoded yet: release the empty prefilled Metal command buffer
		// and encode at submission.
		for (const auto& request : _perVertexScratchRequests) {
			if (request.indirectCapacity || request.tessSizes[5]) {
				clearPrefilledMTLCommandBuffer();
				return;
			}
		}
		setConfigurationResult(reservePrefilledPerVertexScratch(0));
		if (!wasConfigurationSuccessful()) { return; }
		@autoreleasepool {
			MVKCommandEncodingContext encodingContext;
			encodingContext.perVertexScratch = &_prefilledPerVertexScratch;
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

    // Multiview rewinds through _next while encoding the subpass terminator.
    // Link first and retain even one-time commands until flush so replay can traverse them.
    if (_tail) { _tail->_next = command; }
    command->_next = nullptr;
    _tail = command;
    if ( !_head ) { _head = command; }
    if (_immediateCmdEncoder) { _immediateCmdEncoder->encodeCommands(command); }
}

void MVKCommandBuffer::submit(MVKQueueCommandBufferSubmission* cmdBuffSubmit, MVKCommandEncodingContext* pEncodingContext, const MVKPerVertexScratchReservations& scratch) {
	if ( !canExecute() ) { return; }

	if (_prefilledMTLCmdBuffer) {
		cmdBuffSubmit->setActiveMTLCommandBuffer(_prefilledMTLCmdBuffer);
		clearPrefilledMTLCommandBuffer();
		_prefilledPerVertexScratch.clear();
	} else {
		pEncodingContext->perVertexScratch = &scratch;
		pEncodingContext->nextPerVertexScratch = 0;
		pEncodingContext->submission = cmdBuffSubmit;
		MVKCommandEncoder encoder(this);
		encoder.encode(cmdBuffSubmit->getActiveMTLCommandBuffer(), pEncodingContext);
		pEncodingContext->submission = nullptr;
		pEncodingContext->perVertexScratch = nullptr;
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
	return max(__builtin_popcount(getViewMask()), 1);
}

uint32_t MVKCommandBuffer::getViewMask() const {
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
	return viewMask;
}

void MVKCommandBuffer::clearPrefilledMTLCommandBuffer() {

	// A prefilled Metal command buffer that was never submitted is released without being committed: Metal then
	// discards the commands the application abandoned, and frees its place in its queue, which an enqueued command
	// buffer would keep. Its handlers run now, as cleanup, while the pools they return buffers to still exist.
	if (_prefilledMTLCmdBuffer && _prefilledMTLCmdBuffer.status == MTLCommandBufferStatusNotEnqueued) {
		getDevice()->abandonMTLCommandBuffer(_prefilledMTLCmdBuffer);
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
VkResult MVKCommandBuffer::recordExecuteCommands(MVKArrayRef<MVKCommandBuffer*const> secondaryCommandBuffers) {
	size_t firstRequest = _perVertexScratchRequests.size();
	try {
		for (MVKCommandBuffer* cmdBuff : secondaryCommandBuffers) {
			if (cmdBuff->_needsVisibilityResultMTLBuffer) { _needsVisibilityResultMTLBuffer = true; }
			if (cmdBuff->_hasStageCounterTimestampCommand) { _hasStageCounterTimestampCommand = true; }
			if (cmdBuff->getConfigurationResult() != VK_SUCCESS) { return cmdBuff->getConfigurationResult(); }
			if (cmdBuff->_needsInheritedPerVertexAttachments) {
				VkResult result = validateIndexedPerVertexAttachments();
				if (result != VK_SUCCESS) { return result; }
			}
			_perVertexScratchRequests.insert(_perVertexScratchRequests.end(), cmdBuff->_perVertexScratchRequests.begin(), cmdBuff->_perVertexScratchRequests.end());
		}
	} catch (const std::bad_alloc&) { return reportError(VK_ERROR_OUT_OF_HOST_MEMORY, "Portable PerVertexKHR secondary scratch recording allocation failed."); }
	if (_immediateCmdEncoder) {
		for (size_t i = firstRequest; i < _perVertexScratchRequests.size(); ++i) {
			if (_perVertexScratchRequests[i].indirectCapacity) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR indirect draws cannot be encoded while immediately prefilling Metal command buffers."); }
		}
	}
	return _immediateCmdEncoder ? reservePrefilledPerVertexScratch(firstRequest) : VK_SUCCESS;
}

void MVKCommandBuffer::recordRenderPass(MVKArrayRef<MVKImageView*> attachments, bool attachmentsKnown) {
	_recordedAttachmentsKnown = attachmentsKnown;
	_recordedRenderingError = nullptr;
	for (auto* attachment : attachments) {
		if (attachment && attachment->getImage()->getMTLStorageMode() == MTLStorageModeMemoryless) { _recordedRenderingError = "indexed compute capture cannot preserve memoryless attachments."; }
	}
}

void MVKCommandBuffer::recordRendering(const VkRenderingInfo* renderingInfo) {
	recordRenderPass({});
	MVKRenderingAttachmentIterator attachments(renderingInfo);
	attachments.iterate([&](const VkRenderingAttachmentInfo* info, VkImageAspectFlagBits aspect, MVKImageView* attachment, bool isResolveAttachment) {
		if (!attachment) { return; }
		// Match MVKRenderSubpass: color uses non-null resolve views; depth/stencil also require a resolve mode.
		if (isResolveAttachment && info->imageView && (aspect == VK_IMAGE_ASPECT_COLOR_BIT || info->resolveMode != VK_RESOLVE_MODE_NONE)) {
			if (aspect == VK_IMAGE_ASPECT_COLOR_BIT && info->resolveMode != VK_RESOLVE_MODE_AVERAGE_BIT) { _recordedRenderingError = "indexed capture requires average-mode dynamic color resolve."; }
			if (const char* error = mvkGetPerVertexResolveError(getMetalFeatures(), getPixelFormats(), attachment->getVkFormat(), aspect, info->resolveMode, renderingInfo->flags)) { _recordedRenderingError = error; }
		}
		if (attachment->getImage()->getMTLStorageMode() == MTLStorageModeMemoryless) { _recordedRenderingError = "indexed compute capture cannot preserve memoryless attachments."; }
	});
}

VkResult MVKCommandBuffer::validateIndexedPerVertexAttachments() {
	const char* error = _recordedRenderingError;
	if (!_recordedAttachmentsKnown && !_doesContinueRenderPass) { error = "indexed compute capture requires known rendering attachments."; }
	if (_currentSubpassInfo.renderpass) {
		if (const char* resolveError = _currentSubpassInfo.renderpass->getSubpass(_currentSubpassInfo.subpassIndex)->getPerVertexResolveError()) { error = resolveError; }
	}
	return error ? reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR %s", error) : VK_SUCCESS;
}

VkResult MVKCommandBuffer::recordPerVertexDraw(uint32_t vertexCount, uint32_t instanceCount, bool indexed) {
	if (!_recordedPerVertexPipeline || !vertexCount || !instanceCount) { return VK_SUCCESS; }
	if (_recordedPerVertexPipeline->usesPerVertexTessEval()) { return recordPerVertexTessEvalDraw(vertexCount, instanceCount, indexed); }
	// Dynamic restart can change at execution. Reserve both helper paths before submission.
	bool dynamicRestart = indexed && _recordedPerVertexPipeline->getDynamicStateFlags().has(MVKRenderStateFlag::PrimitiveRestartEnable);
	bool restart = mvkPerVertexRequiresRestartAssembly(indexed, dynamicRestart || _recordedPerVertexPipeline->getStaticStateData().enable.has(MVKRenderStateEnableFlag::PrimitiveRestart));
	if (restart && !mvkCanAssemblePerVertexRestart(vertexCount, instanceCount, getMetalFeatures().indirectDrawing)) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR restart requires indirect drawing and uint32 dense capture record IDs."); }
	if (indexed && !mvkPerVertexIndexSize(_recordedIndexType)) {
		return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR indexed capture requires uint8, uint16 or uint32 indices.");
	}
	// Indexed capture runs in compute, and a render pass boundary separates a nonindexed capture from its replay:
	// either ends and restarts the render encoder. A secondary may omit its framebuffer or inherit an imageless one.
	// Revalidate in every primary.
	if (_doesContinueRenderPass) { _needsInheritedPerVertexAttachments = true; }
	VkResult result = validateIndexedPerVertexAttachments();
	if (result != VK_SUCCESS) { return result; }
	auto topology = getRecordedPerVertexTopology();
	// A dynamic topology may be any of its class, adjacency included, which capture and replay do not support.
	if (!mvkPerVertexReplayVertexCount(topology)) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR draws do not support this primitive topology."); }
	uint64_t indexScratchBytes = restart ? mvkPerVertexRestartIndexScratchSize(vertexCount) : indexed && _recordedIndexType == VK_INDEX_TYPE_UINT8 ? uint64_t(vertexCount) * sizeof(uint16_t) : 0;
	if (indexScratchBytes > getMetalFeatures().maxMTLBufferSize) { return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Portable PerVertexKHR index scratch buffer exceeds Metal limits."); }
	uint32_t viewMask = getViewMask();
	uint32_t passCount = std::max(getDevice()->getMultiviewMetalPassCount(viewMask), 1u);
	MVKPerVertexScratchRequest requests[32];
	for (uint32_t pass = 0; pass < passCount; ++pass) {
		uint32_t views = std::max(getDevice()->getViewCountInMetalPass(viewMask, pass), 1u);
		uint64_t expandedInstances = uint64_t(instanceCount) * views;
		if (expandedInstances > UINT32_MAX || !mvkCanEncodePerVertexDraw(vertexCount, uint32_t(expandedInstances), _recordedPerVertexPipeline->getPerVertexCapturedLayout().stride, topology, getMetalFeatures().maxMTLBufferSize)) {
			return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Portable PerVertexKHR draw exceeds its capture or replay buffer limits.");
		}
		if (restart && !mvkCanAssemblePerVertexRestart(vertexCount, uint32_t(expandedInstances), getMetalFeatures().indirectDrawing)) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR restart requires indirect drawing and uint32 dense capture record IDs."); }
		uint64_t primitiveCount = uint64_t(mvkPerVertexPrimitiveCount(vertexCount, topology)) * expandedInstances;
		uint64_t occurrences = primitiveCount * mvkPerVertexReplayVertexCount(topology);
		requests[pass] = {NSUInteger(uint64_t(vertexCount) * expandedInstances * _recordedPerVertexPipeline->getPerVertexCapturedLayout().stride), NSUInteger(occurrences * 2 * sizeof(uint32_t)), NSUInteger(primitiveCount * 3 * sizeof(uint32_t)), _recordedPerVertexPipeline->usesPortableBarycentrics() ? NSUInteger(occurrences * sizeof(uint32_t)) : 0, NSUInteger(indexScratchBytes), restart, dynamicRestart && _recordedIndexType == VK_INDEX_TYPE_UINT8};
	}
	size_t firstRequest = _perVertexScratchRequests.size();
	try {
		// Draw-major storage: every pass owns immutable CPU tables and independent GPU scratch.
		_perVertexScratchRequests.insert(_perVertexScratchRequests.end(), requests, requests + passCount);
	} catch (const std::bad_alloc&) { return reportError(VK_ERROR_OUT_OF_HOST_MEMORY, "Portable PerVertexKHR scratch recording allocation failed."); }
	return _immediateCmdEncoder ? reservePrefilledPerVertexScratch(firstRequest) : VK_SUCCESS;
}

// Vulkan places no bound on indirect vertex and instance counts, and they may be written on the GPU earlier in
// the same submission. Only a GPU plan, sized for the largest record count a uint32 record ID can represent,
// is reserved before submission. Once the plan completes, the queue reserves the exact replay scratch from the
// counts it froze, then encodes the replay (encodePerVertexIndirect).
VkResult MVKCommandBuffer::recordPerVertexIndirectDraw(bool indexed, uint32_t drawCount) {
	if (!_recordedPerVertexPipeline) { return VK_SUCCESS; }
	// Immediate prefill encodes each command as it is recorded, before a queue submission exists to wait for the plan.
	if (_immediateCmdEncoder) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR indirect draws cannot be encoded while immediately prefilling Metal command buffers."); }
	auto* pipeline = _recordedPerVertexPipeline;
	if (pipeline->getZeroDivisorVertexBindings().size()) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR indirect draws do not support zero-divisor vertex bindings yet."); }
	if (indexed && !mvkPerVertexIndexSize(_recordedIndexType)) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR indexed capture requires uint8, uint16 or uint32 indices."); }
	// Dynamic restart can change at execution. Reserve the restart assembly whenever it is possible.
	bool restart = indexed && (pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::PrimitiveRestartEnable) || pipeline->getStaticStateData().enable.has(MVKRenderStateEnableFlag::PrimitiveRestart));
	if (restart && !getMetalFeatures().indirectDrawing) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR restart requires indirect drawing."); }
	// Each indirect draw plans on the GPU in compute, which ends and restarts the render encoder.
	if (_doesContinueRenderPass) { _needsInheritedPerVertexAttachments = true; }
	VkResult result = validateIndexedPerVertexAttachments();
	if (result != VK_SUCCESS) { return result; }
	auto topology = getRecordedPerVertexTopology();
	if (!mvkPerVertexReplayVertexCount(topology)) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Portable PerVertexKHR indirect draws do not support this primitive topology."); }
	MVKPerVertexScratchRequest request{};
	request.restart = restart;
	request.indirectCapacity = UINT32_MAX;
	// Plan words, then one 256-byte perVertexRestart parameter block per dispatch, laid out for the plan's ceiling.
	uint64_t planSize = 1024 + (restart ? (mvkPerVertexIndirectRestartScanSteps(UINT32_MAX) + 3) * 256 : 0);
	// Several draws freeze their Vulkan commands in a buffer of their own, at their size. Vulkan bounds maxDrawCount by
	// the argument buffer, whose stride is at least that size: a legal command never exceeds the Metal limits here.
	uint64_t snapshotSize = drawCount > 1 ? uint64_t(drawCount) * (indexed ? 5 : 4) * sizeof(uint32_t) : 0;
	if (planSize > getMetalFeatures().maxMTLBufferSize || snapshotSize > getMetalFeatures().maxMTLBufferSize) { return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Portable PerVertexKHR indirect argument snapshot exceeds Metal buffer limits."); }
	request.planSize = NSUInteger(planSize);
	request.snapshotSize = NSUInteger(snapshotSize);
	// Every multiview pass plans and replays separately.
	uint32_t passCount = std::max(getDevice()->getMultiviewMetalPassCount(getViewMask()), 1u);
	size_t firstRequest = _perVertexScratchRequests.size();
	try {
		_perVertexScratchRequests.insert(_perVertexScratchRequests.end(), passCount, request);
	} catch (const std::bad_alloc&) { return reportError(VK_ERROR_OUT_OF_HOST_MEMORY, "Portable PerVertexKHR scratch recording allocation failed."); }
	return _immediateCmdEncoder ? reservePrefilledPerVertexScratch(firstRequest) : VK_SUCCESS;
}

// The GPU generator emits at most the uniform level-3 topology per triangle patch: 13 triangles,
// captured once per corner. Levels outside the proven topologies refuse the draw on the GPU.
static constexpr uint64_t kMVKPerVertexTessMaxRecordsPerPatch = 39;

VkResult MVKCommandBuffer::recordPerVertexTessEvalDraw(uint32_t vertexCount, uint32_t instanceCount, bool indexed) {
	if (indexed || instanceCount != 1 || getViewMask()) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "PerVertex TES test requires direct non-indexed draws of one instance without views."); }
	// Admission fixes three control points. Vertices that do not complete a patch are not tessellated, but
	// Vulkan still runs the VS for each of them: without a complete patch, only the VS output is reserved.
	uint64_t patches = vertexCount / 3;
	// VS/TCS/TES run in compute, which ends and restarts the render encoder.
	if (_doesContinueRenderPass) { _needsInheritedPerVertexAttachments = true; }
	VkResult result = validateIndexedPerVertexAttachments();
	if (result != VK_SUCCESS) { return result; }
	uint64_t records = patches * kMVKPerVertexTessMaxRecordsPerPatch;
	uint32_t stride = _recordedPerVertexPipeline->getPerVertexCapturedLayout().stride;
	if (records > UINT32_MAX || !mvkCanEncodePerVertexDraw(uint32_t(records), 1, stride, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, getMetalFeatures().maxMTLBufferSize)) {
		return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "PerVertex TES draw exceeds its capture or replay buffer limits.");
	}
	MVKPerVertexScratchRequest request = {NSUInteger(records * stride), NSUInteger(records * 2 * sizeof(uint32_t)), NSUInteger(records * sizeof(uint32_t)), _recordedPerVertexPipeline->usesPortableBarycentrics() ? NSUInteger(records * sizeof(uint32_t)) : 0};
	const auto& limits = getDeviceProperties().limits;
	// Invocation records, VS output, TCS vertex and patch output, float32 levels (outer[4], inner[2]),
	// then the generator plan: status, replay arguments and constants, per-patch counts and offsets, patch indices.
	uint64_t sizes[] = {patches ? 16 + records * 32 : 0, uint64_t(vertexCount) * 4 * limits.maxVertexOutputComponents, patches * 3 * 4 * limits.maxTessellationControlPerVertexOutputComponents, patches * 4 * limits.maxTessellationControlPerPatchOutputComponents, patches * 6 * sizeof(float), patches ? mvkPerVertexTessPlanSize(patches) : 0};
	for (size_t i = 0; i < std::size(sizes); ++i) {
		if (sizes[i] > getMetalFeatures().maxMTLBufferSize) { return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "PerVertex TES scratch exceeds Metal buffer limits."); }
		request.tessSizes[i] = NSUInteger(sizes[i]);
	}
	size_t firstRequest = _perVertexScratchRequests.size();
	try {
		_perVertexScratchRequests.push_back(request);
	} catch (const std::bad_alloc&) { return reportError(VK_ERROR_OUT_OF_HOST_MEMORY, "Portable PerVertexKHR scratch recording allocation failed."); }
	return _immediateCmdEncoder ? reservePrefilledPerVertexScratch(firstRequest) : VK_SUCCESS;
}

VkResult MVKCommandBuffer::reservePrefilledPerVertexScratch(size_t firstRequest) {
	try {
		std::vector<MVKPerVertexScratchRequest> requests(_perVertexScratchRequests.begin() + firstRequest, _perVertexScratchRequests.end());
		MVKPerVertexScratchReservations scratch;
		VkResult result = reservePerVertexScratch(requests, scratch);
		if (result != VK_SUCCESS) { return result; }
		_prefilledPerVertexScratch.insert(_prefilledPerVertexScratch.end(), scratch.begin(), scratch.end());
		return VK_SUCCESS;
	} catch (const std::bad_alloc&) { return VK_ERROR_OUT_OF_HOST_MEMORY; }
}

VkResult MVKCommandBuffer::reservePerVertexScratch(MVKPerVertexScratchReservations& scratch, std::unordered_set<MVKCommandBuffer*>& prefilledExecutions) {
	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }
	if (!wasConfigurationSuccessful()) { return getConfigurationResult(); }
	if (_perVertexScratchRequests.empty()) { return VK_SUCCESS; }
	// Prefilled buffers are consumed once. Do not consume them during preflight: a later
	// batch can still fail, and the application must be able to retry the whole submit.
	if (_prefilledMTLCmdBuffer && prefilledExecutions.insert(this).second) {
		scratch = _prefilledPerVertexScratch;
		return VK_SUCCESS;
	}
	return reservePerVertexScratch(_perVertexScratchRequests, scratch);
}

VkResult MVKCommandBuffer::reservePerVertexScratch(const std::vector<MVKPerVertexScratchRequest>& requests, MVKPerVertexScratchReservations& scratch) {
	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }
	MVKPerVertexScratchReservations pending;
	if (!mvkReservePerVertexScratch(getMTLDevice(), requests, pending)) {
		VkResult result = _device->getConfigurationResult();
		return result != VK_SUCCESS ? result : reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Portable PerVertexKHR scratch reservation failed.");
	}
	auto* pool = _commandPool->getCommandEncodingPool();
	for (size_t i = 0; i < requests.size(); ++i) {
		if (requests[i].indirectCapacity) {
			id<MTLComputePipelineState> state = pool->getPerVertexIndirectMTLComputePipelineState();
			VkResult result = _device->getConfigurationResult();
			if (result != VK_SUCCESS) { return result; }
			if (!state || !state.maxTotalThreadsPerThreadgroup || !state.threadExecutionWidth) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "Portable PerVertexKHR indirect planning pipeline is unavailable or has invalid dispatch limits."); }
			pending[i]->indirectPipeline = [state retain];
			if (!requests[i].restart) { continue; }
			// The restart helper is prepared now; its scratch is reserved with the replay.
			id<MTLComputePipelineState> restartState = pool->getPerVertexRestartMTLComputePipelineState();
			result = _device->getConfigurationResult();
			if (result != VK_SUCCESS) { return result; }
			if (!restartState || !restartState.maxTotalThreadsPerThreadgroup || !restartState.threadExecutionWidth) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "Portable PerVertexKHR index helper pipeline is unavailable or has invalid dispatch limits."); }
			pending[i]->indexPipeline = [restartState retain];
			continue;
		}
		if (requests[i].tessSizes[5]) {
			id<MTLComputePipelineState> state = pool->getPerVertexTessTopologyMTLComputePipelineState();
			VkResult result = _device->getConfigurationResult();
			if (result != VK_SUCCESS) { return result; }
			if (!state || !state.maxTotalThreadsPerThreadgroup || !state.threadExecutionWidth) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "PerVertex TES topology pipeline is unavailable or has invalid dispatch limits."); }
			pending[i]->tessTopologyPipeline = [state retain];
			continue;
		}
		if (!requests[i].indexSize) { continue; }
		// Secondary requests are flattened into the primary. Prepare in its pool
		// and retain with scratch so encoding never compiles a helper after success.
		id<MTLComputePipelineState> state = requests[i].restart ? pool->getPerVertexRestartMTLComputePipelineState() : pool->getConvertUint8IndicesMTLComputePipelineState(true);
		VkResult result = _device->getConfigurationResult();
		if (result != VK_SUCCESS) { return result; }
		if (!state || !state.maxTotalThreadsPerThreadgroup || !state.threadExecutionWidth) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "Portable PerVertexKHR index helper pipeline is unavailable or has invalid dispatch limits."); }
		pending[i]->indexPipeline = [state retain];
		if (requests[i].widenUint8) {
			id<MTLComputePipelineState> widen = pool->getConvertUint8IndicesMTLComputePipelineState(true);
			result = _device->getConfigurationResult();
			if (result != VK_SUCCESS) { return result; }
			if (!widen || !widen.maxTotalThreadsPerThreadgroup || !widen.threadExecutionWidth) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "Portable PerVertexKHR uint8 helper pipeline is unavailable or has invalid dispatch limits."); }
			pending[i]->widenUint8Pipeline = [widen retain];
		}
	}
	VkResult result = _device->getConfigurationResult();
	if (result != VK_SUCCESS) { return result; }
	scratch = std::move(pending);
	return VK_SUCCESS;
}

// Track whether a stage-based timestamp command has been added, so we know
// to update the timestamp command fence when ending a Metal command encoder.
void MVKCommandBuffer::recordTimestampCommand() {
	_hasStageCounterTimestampCommand = mvkIsAnyFlagEnabled(getMetalFeatures().counterSamplingPoints, MVK_COUNTER_SAMPLING_AT_PIPELINE_STAGE);
}


#pragma mark -
#pragma mark Tessellation constituent command management

// Compute binds preserve the graphics pipeline used to validate recorded draws.
bool MVKCommandBuffer::recordedGraphicsPipelineUsesPerVertexTessEval() const { return _recordedPerVertexPipeline && _recordedPerVertexPipeline->usesPerVertexTessEval(); }

void MVKCommandBuffer::recordBindPipeline(MVKCmdBindPipeline* mvkBindPipeline) {
	_lastTessellationPipeline = mvkBindPipeline->isTessellationPipeline() ? mvkBindPipeline : nullptr;
	if (auto* graphics = mvkBindPipeline->getGraphicsPipeline()) {
		_recordedPerVertexPipeline = graphics->usesPerVertexInputBuffer() ? graphics : nullptr;
		bool ordinaryTessellation = graphics->isTessellationPipeline() && !graphics->usesPerVertexTessEval() && !graphics->usesPerVertexInputBuffer();
		_recordedTessellationPipeline = ordinaryTessellation ? graphics : nullptr;
		_recordedMeshPipeline = graphics->isMeshPipeline() ? graphics : nullptr;
	}
}

VkPrimitiveTopology MVKCommandBuffer::getRecordedPerVertexTopology() const {
	bool dynamic = _recordedPerVertexPipeline->getDynamicStateFlags().has(MVKRenderStateFlag::PrimitiveTopology);
	return dynamic ? _recordedPrimitiveTopology : _recordedPerVertexPipeline->getVkPrimitiveTopology();
}

uint32_t MVKCommandBuffer::getRecordedPatchControlPoints() const {
	if (!_recordedTessellationPipeline) { return 0; }
	bool dynamic = _recordedTessellationPipeline->getDynamicStateFlags().has(MVKRenderStateFlag::PatchControlPoints);
	return dynamic ? _recordedPatchControlPoints : _recordedTessellationPipeline->getStaticStateData().patchControlPoints;
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
    while(command && !_isEncodingStopped) {
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
	secondaryCmdBuffer->beginSecondaryEncoding(this);
	MVKCommand* cmd = secondaryCmdBuffer->_head;
	while (cmd && !_isEncodingStopped) {
		cmd->encode(this);
		cmd = cmd->_next;
	}
}

bool MVKCommandEncoder::awaitEncodedWork() {
	endCurrentMetalEncoding();
	auto* submission = _pEncodingContext->submission;
	if (submission) {
		for (size_t i = 0; i < _commandBufferDebugGroups.size(); ++i) { [_mtlCmdBuffer popDebugGroup]; }
		// Released by a completed handler of the committed Metal command buffer.
		_stageCountersMTLFence = nil;
		_mtlCmdBuffer = submission->continueOnNewMTLCommandBuffer();
	} else {
		_mtlCmdBuffer = nil;
	}
	if ( !_mtlCmdBuffer ) {
		_isEncodingStopped = true;
		return false;
	}
	_cmdBuffer->setMetalObjectLabel(_mtlCmdBuffer, _cmdBuffer->_debugName);
	for (NSString* name : _commandBufferDebugGroups) { [_mtlCmdBuffer pushDebugGroup: name]; }
	return true;
}

void MVKCommandEncoder::pushCommandBufferDebugGroup(NSString* name) {
	[_mtlCmdBuffer pushDebugGroup: name];
	_commandBufferDebugGroups.push_back([name retain]);
}

void MVKCommandEncoder::popCommandBufferDebugGroup() {
	[_mtlCmdBuffer popDebugGroup];
	if (_commandBufferDebugGroups.empty()) { return; }
	[_commandBufferDebugGroups.back() release];
	_commandBufferDebugGroups.pop_back();
}

const char* MVKCommandEncoder::getIndexedPerVertexAttachmentError() {
	if (!isInRenderPass()) { return "indexed compute capture requires known rendering attachments."; }
	if (const char* error = getSubpass()->getPerVertexResolveError()) { return error; }
	// These are the begin-render-pass views, including imageless and dynamic rendering attachments.
	// An empty list in an active render pass is valid; there is no image content to preserve.
	for (auto* attachment : _attachments) {
		if (attachment && attachment->getImage()->getMTLStorageMode() == MTLStorageModeMemoryless) { return "indexed compute capture cannot preserve memoryless attachments."; }
	}
	return nullptr;
}

MVKPerVertexScratch* MVKCommandEncoder::nextPerVertexScratch() {
	auto* reservations = _pEncodingContext->perVertexScratch;
	size_t first = _pEncodingContext->nextPerVertexScratch;
	uint32_t passCount = std::max(getSubpass()->getMultiviewMetalPassCount(), 1u);
	if (!reservations || first > reservations->size() || passCount > reservations->size() - first || _multiviewPassIndex >= passCount) {
		// The draw cannot be encoded: lose the device rather than complete the submission without it.
		_cmdBuffer->setConfigurationResult(_cmdBuffer->reportError(VK_ERROR_INITIALIZATION_FAILED, "Portable PerVertexKHR draw has no scratch reservation."));
		getDevice()->markLost();
		stopEncoding();
		return nullptr;
	}
	_lastPerVertexScratch = (*reservations)[first + _multiviewPassIndex];
	_pEncodingContext->nextPerVertexScratch += passCount;
	keepPerVertexScratchResident();
	return _lastPerVertexScratch.get();
}

void MVKCommandEncoder::keepPerVertexScratchResident() {
	auto scratch = _lastPerVertexScratch;
	auto* device = getDevice();
	for (auto buffer : scratch->buffers) { if (buffer) { device->makeResident(buffer); } }
	// This also protects buffers encoded with unretained Metal command buffers and
	// prefills that outlive their Vulkan command buffer's recorded command list.
	device->addMTLCommandBufferHandler(_mtlCmdBuffer, ^(id<MTLCommandBuffer>) {
		for (auto buffer : scratch->buffers) { if (buffer) { device->removeResidency(buffer); } }
	});
}

void MVKCommandEncoder::beginRendering(MVKCommand* rendCmd, const VkRenderingInfo* pRenderingInfo) {

	VkSubpassContents contents = (mvkIsAnyFlagEnabled(pRenderingInfo->flags, VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT)
								  ? VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS
								  : VK_SUBPASS_CONTENTS_INLINE);

	// Track both rendering and resolve attachments, alternating a rendering attachment, then its corresponding resolve attachment.
	uint32_t maxAttCnt = (pRenderingInfo->colorAttachmentCount + 2) * 2;
	MVKImageView* imageViews[maxAttCnt];
	VkClearValue clearValues[maxAttCnt];

	// Assemble the list of attachments and clear values. This must be done identically to how the dynamic renderpass assembles attachments.
	uint32_t attCnt = 0;
	MVKRenderingAttachmentIterator attIter(pRenderingInfo);
	attIter.iterate([&](const VkRenderingAttachmentInfo* pAttInfo, VkImageAspectFlagBits aspect, MVKImageView* imgView, bool isResolveAttachment)->void {
		imageViews[attCnt] = imgView;
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

bool MVKCommandEncoder::isDynamicRendering() {
	MVKRenderSubpass* mvkRSP = getSubpass();
	return mvkRSP && mvkRSP->isDynamicRendering();
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
// End any active Metal encoder before capturing dependency fences and updating the subpass index.
void MVKCommandEncoder::setSubpass(MVKCommand* subpassCmd,
								   VkSubpassContents subpassContents,
								   uint32_t subpassIndex,
								   MVKCommandUse cmdUse) {
	encodeStoreActions();
	endCurrentMetalEncoding();

	MVKRenderPass* renderPass = _pEncodingContext->getRenderPass();
	if (renderPass) { renderPass->encodeSubpassDependencyBarriers(this, subpassIndex); }

	_lastMultiviewPassCmd = subpassCmd;
	_firstSubpassPerVertexScratch = _pEncodingContext->nextPerVertexScratch;
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
	_pEncodingContext->nextPerVertexScratch = _firstSubpassPerVertexScratch;
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
    case kMVKCommandUseResolveSubpassAttachment:     return kMVKBarrierStageFragment; /**< Resolve subpass attachment. */
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
		for (int stage = 0; stage < kMVKBarrierStageCount; ++stage) {
			if (mvkIsAnyFlagEnabled(_mtlComputeEncoderStages, 1 << stage)) {
				barrierUpdate((MVKBarrierStage)stage, _mtlComputeEncoder);
			}
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
		if (!_pEncodingContext->visibilityResultBuffer.buffer()) {
			_pEncodingContext->visibilityResultBuffer = _device->getVisibilityBuffer();
		}
		// Track the starting visibility offset for this Metal render pass so wrap detection compares
		// against the correct baseline even when the buffer was already partially consumed.
		_pEncodingContext->firstVisibilityResultOffsetInRenderPass = _pEncodingContext->visibilityResultBuffer.offset();
		mtlRPDesc.visibilityResultBuffer = _pEncodingContext->visibilityResultBuffer.buffer();
	}
	_hasMTLRenderEncoderVisibilityResultBuffer = (mtlRPDesc.visibilityResultBuffer != nil);

	// Metal uses MTLRenderPassDescriptor properties renderTargetWidth, renderTargetHeight,
	// and renderTargetArrayLength to preallocate tile memory storage on machines using tiled
	// rendering. This memory preallocation is not necessary if we are not rendering to
	// attachments, and some apps actively define extremely oversized framebuffers when they
	// know they are not rendering to actual attachments, making this internal tile memory
	// allocation even more wasteful, occasionally to the point of triggering OOM crashes.
	// On the other hand, if the framebuffer has no attachments and has zero extent,
	// we just set the render target extent to cover the render area.
	VkExtent2D fbExtent = getFramebufferExtent();
	VkExtent2D raFullExtent = { _renderArea.offset.x + _renderArea.extent.width, _renderArea.offset.y + _renderArea.extent.height };
    mtlRPDesc.renderTargetWidth = max(min(raFullExtent.width, (fbExtent.width ? fbExtent.width : raFullExtent.width)), 1u);
    mtlRPDesc.renderTargetHeight = max(min(raFullExtent.height, (fbExtent.height ? fbExtent.height : raFullExtent.height)), 1u);
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
            mtlRPDesc.renderTargetArrayLength = renderTargetArrayLength;
        }
    }

	// If programmable sample positions are supported, set them into the render pass descriptor.
	// If no custom sample positions are established, size will be zero,
	// and Metal will default to using default sample postions.
	if (getMetalFeatures().programmableSamplePositions) {
		auto sampPosns = _state.updateSamplePositions();
		[mtlRPDesc setSamplePositions: sampPosns.data() count: sampPosns.size()];
	}

    _mtlRenderEncoder = [_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];
	retainIfImmediatelyEncoding(_mtlRenderEncoder);
	_cmdBuffer->setMetalObjectLabel(_mtlRenderEncoder, getMTLRenderCommandEncoderName(cmdUse));
	getState().beginGraphicsEncoding(getSampleCount());

	encodeBarrierWaits(cmdUse);

	// We shouldn't clear the render area if we are restarting the Metal renderpass
	// separately from a Vulkan subpass, and we otherwise only need to clear render
	// area if we're not rendering to the entire attachment.
    if ( !isRestart && !_isRenderingEntireAttachment ) { clearRenderArea(cmdUse); }
}

void MVKCommandEncoder::restartMetalRenderPassIfNeeded() {
	if ( !_mtlRenderEncoder || _state.needsMetalRenderPassRestart() ||
		(_cmdBuffer->_needsVisibilityResultMTLBuffer && !_hasMTLRenderEncoderVisibilityResultBuffer) ) {
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

MVKRenderSubpass* MVKCommandEncoder::getSubpass() {
	MVKRenderPass* mvkRP = _pEncodingContext->getRenderPass();
	return mvkRP ? mvkRP->getSubpass(_renderSubpassIndex) : nullptr;
}

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
            _state.bindGraphicsPipeline(static_cast<MVKGraphicsPipeline*>(pipeline));
            static_cast<MVKGraphicsPipeline*>(pipeline)->wasBound(this);
            break;

        case VK_PIPELINE_BIND_POINT_COMPUTE:
            _state.bindComputePipeline(static_cast<MVKComputePipeline*>(pipeline));
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

// Attachment locations are changing. Need to store attachments and begin another Metal renderpass.
void MVKCommandEncoder::updateColorAttachmentLocations(const MVKArrayRef<uint32_t> colorAttLocs) {
	if (_mtlRenderEncoder && isDynamicRendering()) {
		auto atts = _pEncodingContext->getFramebuffer()->getAttachments();
		auto* mvkSP = getSubpass();
		if (mvkSP && mvkSP->isChangingColorAttachmentLocations(colorAttLocs, atts)) {
			encodeStoreActions(true);
			endMetalRenderEncoding();
			mvkSP->updateColorAttachmentLocations(colorAttLocs, atts);
		}
	}
}

// Input attachments are changing. Need to store attachments and begin another Metal renderpass.
void MVKCommandEncoder::updateAttachmentInputIndices(const MVKArrayRef<uint32_t> colorAttIdxs,
													 const uint32_t* pDepthInputAttachmentIndex,
													 const uint32_t* pStencilInputAttachmentIndex) {
	if (_mtlRenderEncoder && isDynamicRendering()) {
		auto* mvkSP = getSubpass();
		if (mvkSP && mvkSP->isChangingAttachmentInputIndices(colorAttIdxs, pDepthInputAttachmentIndex, pStencilInputAttachmentIndex)) {
			encodeStoreActions(true);
			endMetalRenderEncoding();
			mvkSP->updateAttachmentInputIndices(colorAttIdxs, pDepthInputAttachmentIndex, pStencilInputAttachmentIndex);
		}
	}
}

void MVKCommandEncoder::finalizeDrawState(MVKGraphicsStage stage) {
    if (stage == kMVKGraphicsStageVertex) {
        // Must happen before switching encoders.
        encodeStoreActions(true);
    }
	if (stage == kMVKGraphicsStageRasterization) {
		prepareDraw();
		_occlusionQueryState.encode(_mtlRenderEncoder, this);
	} else {
		getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
		prepareRenderDispatch(stage);
	}
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
	getState().beginComputeEncoding();
}

void MVKCommandEncoder::finalizeDispatchState() {
	getMTLComputeEncoder(kMVKCommandUseDispatch);
	prepareComputeDispatch();
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
	endMetalRenderEncoding();
	MVKRenderPass *renderPass = _pEncodingContext->getRenderPass();
	if (renderPass) { renderPass->encodeSubpassDependencyBarriers(this, VK_SUBPASS_EXTERNAL); }
	if ( !mvkIsAnyFlagEnabled(_pEncodingContext->getRenderingFlags(), VK_RENDERING_SUSPENDING_BIT) ) {
		_pEncodingContext->setRenderingContext(nullptr, nullptr);
	}
	_attachments.clear();
	_renderSubpassIndex = 0;
}

void MVKCommandEncoder::endMetalRenderEncoding() {
    if (_mtlRenderEncoder == nil) { return; }

	if (_cmdBuffer->_hasStageCounterTimestampCommand) { [_mtlRenderEncoder updateFence: getStageCountersMTLFence() afterStages: MTLRenderStageFragment]; }
	encodeBarrierUpdates();
	endMetalEncoding(_mtlRenderEncoder);

	getSubpass()->resolveUnresolvableAttachments(this, _attachments.contents());
	endCurrentMetalEncoding();

    _occlusionQueryState.endMetalRenderPass(this);
}

void MVKCommandEncoder::endCurrentMetalEncoding() {
	endMetalRenderEncoding();
	encodeBarrierUpdates();

	if (_mtlComputeEncoder && _cmdBuffer->_hasStageCounterTimestampCommand) { [_mtlComputeEncoder updateFence: getStageCountersMTLFence()]; }
	endMetalEncoding(_mtlComputeEncoder);
	_mtlComputeEncoderUse = kMVKCommandUseNone;
	_mtlComputeEncoderStages = 0;

	if (_mtlBlitEncoder && _cmdBuffer->_hasStageCounterTimestampCommand) { [_mtlBlitEncoder updateFence: getStageCountersMTLFence()]; }
	endMetalEncoding(_mtlBlitEncoder);
    _mtlBlitEncoderUse = kMVKCommandUseNone;

	encodeTimestampStageCounterSamples();
}

static MTLDispatchType getDispatchType(MVKCommandUse use) {
	switch (use) {
		case kMVKCommandUseAccumOcclusionQuery:
			return MTLDispatchTypeConcurrent;
		default:
			return MTLDispatchTypeSerial;
	}
}

static bool wantsSeparateComputeEncoder(MVKCommandUse use) {
	switch (use) {
		case kMVKCommandUseAccumOcclusionQuery:
			return true;
		default:
			return false;
	}
}

static bool shouldStartNewEncoder(MVKCommandUse prev, MVKCommandUse next) {
	if (prev == next)
		return false;
	if (getDispatchType(prev) != getDispatchType(next))
		return true;
	return wantsSeparateComputeEncoder(prev) || wantsSeparateComputeEncoder(next);
}

id<MTLComputeCommandEncoder> MVKCommandEncoder::getMTLComputeEncoder(MVKCommandUse cmdUse) {
	bool needWaits = false;
	if (!_mtlComputeEncoder || shouldStartNewEncoder(_mtlComputeEncoderUse, cmdUse)) {
		needWaits = true;
		endCurrentMetalEncoding();
		_mtlComputeEncoder = [_mtlCmdBuffer computeCommandEncoderWithDispatchType:getDispatchType(cmdUse)];
		retainIfImmediatelyEncoding(_mtlComputeEncoder);
		beginMetalComputeEncoding(cmdUse);
	}
	if (_mtlComputeEncoderUse != cmdUse) {
		needWaits = true;
		_mtlComputeEncoderUse = cmdUse;
		MVKBarrierStage stage = commandUseToBarrierStage(cmdUse);
		if (stage != kMVKBarrierStageNone) {
			mvkEnableFlags(_mtlComputeEncoderStages, 1 << stage);
		}
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

void MVKCommandEncoder::setVertexBytes(id<MTLRenderCommandEncoder> mtlEncoder,
                                       const void* bytes,
                                       NSUInteger length,
                                       uint32_t mtlBuffIndex) {
	auto& mtlFeats = getMetalFeatures();
	if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
		getMtlGraphics().bindVertexBytes(mtlEncoder, bytes, length, mtlBuffIndex);
	} else {
		const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
		getMtlGraphics().bindVertexBuffer(mtlEncoder, mtlBuffAlloc->_mtlBuffer, mtlBuffAlloc->_offset, mtlBuffIndex);
	}
}

void MVKCommandEncoder::setFragmentBytes(id<MTLRenderCommandEncoder> mtlEncoder,
                                         const void* bytes,
                                         NSUInteger length,
                                         uint32_t mtlBuffIndex) {
	auto& mtlFeats = getMetalFeatures();
	if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
		getMtlGraphics().bindFragmentBytes(mtlEncoder, bytes, length, mtlBuffIndex);
	} else {
		const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
		getMtlGraphics().bindFragmentBuffer(mtlEncoder, mtlBuffAlloc->_mtlBuffer, mtlBuffAlloc->_offset, mtlBuffIndex);
	}
}

void MVKCommandEncoder::setComputeBytes(id<MTLComputeCommandEncoder> mtlEncoder,
                                        const void* bytes,
                                        NSUInteger length,
                                        uint32_t mtlBuffIndex) {
	auto& mtlFeats = getMetalFeatures();
	if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
		getMtlCompute().bindBytes(mtlEncoder, bytes, length, mtlBuffIndex);
	} else {
		const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
		getMtlCompute().bindBuffer(mtlEncoder, mtlBuffAlloc->_mtlBuffer, mtlBuffAlloc->_offset, mtlBuffIndex);
	}
}

// Return the MTLBuffer allocation to the pool once the command buffer is done with it
const MVKMTLBufferAllocation* MVKCommandEncoder::getTempMTLBuffer(NSUInteger length, bool isPrivate, bool isDedicated) {
    MVKMTLBufferAllocation* mtlBuffAlloc = getCommandEncodingPool()->acquireMTLBufferAllocation(length, isPrivate, isDedicated);
    getDevice()->addMTLCommandBufferHandler(_mtlCmdBuffer, ^(id<MTLCommandBuffer> mcb) { mtlBuffAlloc->returnToPool(); });
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
	}
}

void MVKCommandEncoder::beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
    _occlusionQueryState.beginOcclusionQuery(this, pQueryPool, query, flags);
    uint32_t queryCount = 1;
    if (isInRenderPass() && getSubpass()->isMultiview()) {
        queryCount = getSubpass()->getViewCountInMetalPass(_multiviewPassIndex);
    }
    addActivatedQueries(pQueryPool, query, queryCount);
}

void MVKCommandEncoder::endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
    _occlusionQueryState.endOcclusionQuery(this, pQueryPool, query);
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

id<MTLFence> MVKCommandEncoder::getStageCountersMTLFence() {
	if ( !_stageCountersMTLFence ) {
		// Create MTLFence as local ref and pass to completion handler
		// block to release once MTLCommandBuffer no longer needs it.
		id<MTLFence> mtlFence = [getMTLDevice() newFence];
		getDevice()->addMTLCommandBufferHandler(_mtlCmdBuffer, ^(id<MTLCommandBuffer> mcb) { [mtlFence release]; });

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
    // The Metal completion handler may run after the Vulkan submission signals.
    // Keep each pool alive until the handler has finished marking its queries.
    auto [it, inserted] = _pActivatedQueries->try_emplace(pQueryPool);
    if (inserted) {
        pQueryPool->retain();
    }
    uint32_t endQuery = query + queryCount;
    while (query < endQuery) {
        it->second.push_back(query++);
    }
}

// Register a command buffer completion handler that finishes each activated query.
// Ownership of the collection of activated queries is passed to the handler.
void MVKCommandEncoder::finishQueries() {
    if ( !_pActivatedQueries ) { return; }

    MVKActivatedQueries* pAQs = _pActivatedQueries;
    _pActivatedQueries = nullptr;
    // After a failed continuation, no Metal command buffer remains to complete the queries.
    if ( !_mtlCmdBuffer ) {
        delete pAQs;
        return;
    }
    getDevice()->addMTLCommandBufferHandler(_mtlCmdBuffer, ^(id<MTLCommandBuffer> mtlCmdBuff) {
        // An abandoned command buffer never ran its queries.
        if (mtlCmdBuff.status != MTLCommandBufferStatusNotEnqueued) {
            for (auto& qryPair : *pAQs) {
                qryPair.first->finishQueries(qryPair.second.contents());
                qryPair.first->release();
            }
        }
        delete pAQs;
    });
}


#pragma mark Construction

MVKCommandEncoder::MVKCommandEncoder(MVKCommandBuffer* cmdBuffer, MVKPrefillMetalCommandBuffersStyle prefillStyle)
	: MVKBaseDeviceObject(cmdBuffer->getDevice())
	, _cmdBuffer(cmdBuffer)
	, _prefillStyle(prefillStyle) {
	_pActivatedQueries = nullptr;
	_mtlCmdBuffer = nil;
	_mtlRenderEncoder = nil;
	_hasMTLRenderEncoderVisibilityResultBuffer = false;
	_mtlComputeEncoder = nil;
	_mtlComputeEncoderUse = kMVKCommandUseNone;
	_mtlComputeEncoderStages = 0;
	_mtlBlitEncoder = nil;
	_mtlBlitEncoderUse = kMVKCommandUseNone;
	_pEncodingContext = nullptr;
	_stageCountersMTLFence = nil;
	_flushCount = 0;
}

MVKCommandEncoder::~MVKCommandEncoder() {
	for (NSString* name : _commandBufferDebugGroups) { [name release]; }
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
        case kMVKCommandUseResolveSubpassAttachment:        return @"Resolve Subpass Attachment RenderEncoder";
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
        case kMVKCommandUseResolveSubpassAttachment:        return @"Resolve Subpass Attachment ComputeEncoder";
        case kMVKCommandUseTessellationVertexTessCtl:       return @"vkCmdDraw (vertex and tess control stages) ComputeEncoder";
        case kMVKCommandUseDrawIndirectConvertBuffers:      return @"vkCmdDraw (convert indirect buffers) ComputeEncoder";
        case kMVKCommandUseCopyQueryPoolResults:            return @"vkCmdCopyQueryPoolResults ComputeEncoder";
        case kMVKCommandUseAccumOcclusionQuery:             return @"Post-render-pass occlusion query accumulation ComputeEncoder";
        case kMVKCommandConvertUint8Indices:                return @"Convert Uint8 indices to Uint16 ComputeEncoder";
        default:                                            return @"Unknown Use ComputeEncoder";
    }
}
