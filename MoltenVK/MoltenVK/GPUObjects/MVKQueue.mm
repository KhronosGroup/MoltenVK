/*
 * MVKQueue.mm
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

#include "MVKInstance.h"
#include "MVKQueue.h"
#include "MVKSurface.h"
#include "MVKSwapchain.h"
#include "MVKSync.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKGPUCapture.h"

using namespace std;


#pragma mark -
#pragma mark MVKQueueFamily

// MTLCommandQueues are cached in MVKQueueFamily/MVKPhysicalDevice because they are very
// limited in number. An app that creates multiple VkDevices over time (such as a test suite)
// will soon find 15 second delays when creating subsequent MTLCommandQueues.
id<MTLCommandQueue> MVKQueueFamily::getMTLCommandQueue(uint32_t queueIndex) {
	lock_guard<mutex> lock(_qLock);
	id<MTLCommandQueue> mtlQ = _mtlQueues[queueIndex];
	if ( !mtlQ ) {
		@autoreleasepool {		// Catch any autoreleased objects created during MTLCommandQueue creation
			uint32_t maxCmdBuffs = getMVKConfig().maxActiveMetalCommandBuffersPerQueue;
			mtlQ = [_physicalDevice->getMTLDevice() newCommandQueueWithMaxCommandBufferCount: maxCmdBuffs];		// retained
			_mtlQueues[queueIndex] = mtlQ;
		}
	}
	return mtlQ;
}

MVKQueueFamily::MVKQueueFamily(MVKPhysicalDevice* physicalDevice, uint32_t queueFamilyIndex, const VkQueueFamilyProperties* pProperties) {
	_physicalDevice = physicalDevice;
	_queueFamilyIndex = queueFamilyIndex;
	_properties = *pProperties;
	_mtlQueues.assign(_properties.queueCount, nil);
}

MVKQueueFamily::~MVKQueueFamily() {
	mvkReleaseContainerContents(_mtlQueues);
}


#pragma mark -
#pragma mark MVKQueue

void MVKQueue::propagateDebugName() { setMetalObjectLabel(_mtlQueue, _debugName); }


#pragma mark Queue submissions

// Execute the queue submission under an autoreleasepool to ensure transient Metal objects are autoreleased.
// This is critical for apps that don't use standard OS autoreleasing runloop threading.
static inline VkResult execute(MVKQueueSubmission* qSubmit) { @autoreleasepool { return qSubmit->execute(); } }

// Executes the submmission, either immediately, or by dispatching to an execution queue.
// Submissions to the execution queue are wrapped in a dedicated autoreleasepool.
// Relying on the dispatch queue to find time to drain the autoreleasepool can
// result in significant memory creep under heavy workloads.
VkResult MVKQueue::submit(MVKQueueSubmission* qSubmit) {
	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }

	if ( !qSubmit ) { return VK_SUCCESS; }     // Ignore nils

	// Extract result before submission to avoid race condition with early destruction
	// Submit regardless of config result, to ensure submission semaphores and fences are signalled.
	// The submissions will ensure a misconfiguration will be safe to execute.
	VkResult rslt = qSubmit->getConfigurationResult();
	if (_execQueue) {
		std::unique_lock lock(_execQueueMutex);
		_execQueueJobCount++;

		dispatch_async(_execQueue, ^{
			execute(qSubmit);

			std::unique_lock execLock(_execQueueMutex);
			if (!--_execQueueJobCount)
				_execQueueConditionVariable.notify_all();
		} );
	} else {
		rslt = execute(qSubmit);
	}
	return rslt;
}

static inline uint32_t getCommandBufferCount(const VkSubmitInfo2* pSubmitInfo) { return pSubmitInfo->commandBufferInfoCount; }
static inline uint32_t getCommandBufferCount(const VkSubmitInfo* pSubmitInfo) { return pSubmitInfo->commandBufferCount; }

template <typename S>
VkResult MVKQueue::submit(uint32_t submitCount, const S* pSubmits, VkFence fence, MVKCommandUse cmdUse) {

    // Fence-only submission
    if (submitCount == 0 && fence) {
        return submit(new MVKQueueCommandBufferSubmission(this, (S*)nullptr, fence, cmdUse));
    }

    VkResult rslt = VK_SUCCESS;
    for (uint32_t sIdx = 0; sIdx < submitCount; sIdx++) {
        VkFence fenceOrNil = (sIdx == (submitCount - 1)) ? fence : VK_NULL_HANDLE; // last one gets the fence

		const S* pVkSub = &pSubmits[sIdx];
		MVKQueueCommandBufferSubmission* mvkSub;
		uint32_t cbCnt = getCommandBufferCount(pVkSub);
		if (cbCnt <= 1) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<1>(this, pVkSub, fenceOrNil, cmdUse);
		} else if (cbCnt <= 16) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<16>(this, pVkSub, fenceOrNil, cmdUse);
		} else if (cbCnt <= 32) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<32>(this, pVkSub, fenceOrNil, cmdUse);
		} else if (cbCnt <= 64) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<64>(this, pVkSub, fenceOrNil, cmdUse);
		} else if (cbCnt <= 128) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<128>(this, pVkSub, fenceOrNil, cmdUse);
		} else if (cbCnt <= 256) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<256>(this, pVkSub, fenceOrNil, cmdUse);
		} else {
			mvkSub = new MVKQueueFullCommandBufferSubmission<512>(this, pVkSub, fenceOrNil, cmdUse);
		}

        VkResult subRslt = submit(mvkSub);
        if (rslt == VK_SUCCESS) { rslt = subRslt; }
    }
    return rslt;
}

// Concrete implementations of templated MVKQueue::submit().
template VkResult MVKQueue::submit(uint32_t submitCount, const VkSubmitInfo2* pSubmits, VkFence fence, MVKCommandUse cmdUse);
template VkResult MVKQueue::submit(uint32_t submitCount, const VkSubmitInfo* pSubmits, VkFence fence, MVKCommandUse cmdUse);

VkResult MVKQueue::submit(const VkPresentInfoKHR* pPresentInfo) {
	return submit(new MVKQueuePresentSurfaceSubmission(this, pPresentInfo));
}

VkResult MVKQueue::waitIdle(MVKCommandUse cmdUse) {

	VkResult rslt = _device->getConfigurationResult();
	if (rslt != VK_SUCCESS) { return rslt; }

	if (_execQueue) {
		std::unique_lock lock(_execQueueMutex);
		while (_execQueueJobCount)
			_execQueueConditionVariable.wait(lock);
	}

	@autoreleasepool {
		auto* mtlCmdBuff = getMTLCommandBuffer(cmdUse);
		[mtlCmdBuff commit];
		[mtlCmdBuff waitUntilCompleted];
	}

	return VK_SUCCESS;
}

id<MTLCommandBuffer> MVKQueue::getMTLCommandBuffer(MVKCommandUse cmdUse, bool retainRefs) {
	id<MTLCommandBuffer> mtlCmdBuff = nil;
	uint64_t startTime = getPerformanceTimestamp();
#if MVK_XCODE_12
	if ([_mtlQueue respondsToSelector: @selector(commandBufferWithDescriptor:)]) {
		MTLCommandBufferDescriptor* mtlCmdBuffDesc = [MTLCommandBufferDescriptor new];	// temp retain
		mtlCmdBuffDesc.retainedReferences = retainRefs;
		if (getMVKConfig().debugMode) {
			mtlCmdBuffDesc.errorOptions |= MTLCommandBufferErrorOptionEncoderExecutionStatus;
		}
		mtlCmdBuff = [_mtlQueue commandBufferWithDescriptor: mtlCmdBuffDesc];
		[mtlCmdBuffDesc release];														// temp release
	} else
#endif
	if (retainRefs) {
		mtlCmdBuff = [_mtlQueue commandBuffer];
	} else {
		mtlCmdBuff = [_mtlQueue commandBufferWithUnretainedReferences];
	}
	addPerformanceInterval(getPerformanceStats().queue.retrieveMTLCommandBuffer, startTime);
	NSString* mtlCmdBuffLabel = getMTLCommandBufferLabel(cmdUse);
	setMetalObjectLabel(mtlCmdBuff, mtlCmdBuffLabel);
	[mtlCmdBuff addCompletedHandler: ^(id<MTLCommandBuffer> mtlCB) { handleMTLCommandBufferError(mtlCB); }];

	if ( !mtlCmdBuff ) { reportError(VK_ERROR_OUT_OF_POOL_MEMORY, "%s could not be acquired.", mtlCmdBuffLabel.UTF8String); }
	return mtlCmdBuff;
}

NSString* MVKQueue::getMTLCommandBufferLabel(MVKCommandUse cmdUse) {
#define CASE_GET_LABEL(cu)  \
	case kMVKCommandUse ##cu:  \
		if ( !_mtlCmdBuffLabel ##cu ) { _mtlCmdBuffLabel ##cu = [[NSString stringWithFormat: @"%s MTLCommandBuffer on Queue %d-%d", mvkVkCommandName(kMVKCommandUse ##cu), _queueFamily->getIndex(), _index] retain]; }  \
		return _mtlCmdBuffLabel ##cu

	switch (cmdUse) {
		CASE_GET_LABEL(BeginCommandBuffer);
		CASE_GET_LABEL(QueueSubmit);
		CASE_GET_LABEL(QueuePresent);
		CASE_GET_LABEL(QueueWaitIdle);
		CASE_GET_LABEL(DeviceWaitIdle);
		CASE_GET_LABEL(AcquireNextImage);
		CASE_GET_LABEL(InvalidateMappedMemoryRanges);
		CASE_GET_LABEL(CopyImageToMemory);
		default:
			MVKAssert(false, "Uncached MTLCommandBuffer label for command use %s.", mvkVkCommandName(cmdUse));
			return [NSString stringWithFormat: @"%s MTLCommandBuffer on Queue %d-%d", mvkVkCommandName(cmdUse), _queueFamily->getIndex(), _index];
	}
#undef CASE_GET_LABEL
}

#if MVK_XCODE_12
static const char* mvkStringFromMTLCommandEncoderErrorState(MTLCommandEncoderErrorState errState) {
	switch (errState) {
		case MTLCommandEncoderErrorStateUnknown:   return "unknown";
		case MTLCommandEncoderErrorStateAffected:  return "affected";
		case MTLCommandEncoderErrorStateCompleted: return "completed";
		case MTLCommandEncoderErrorStateFaulted:   return "faulted";
		case MTLCommandEncoderErrorStatePending:   return "pending";
	}
	return "unknown";
}
#endif

void MVKQueue::handleMTLCommandBufferError(id<MTLCommandBuffer> mtlCmdBuff) {
	if (mtlCmdBuff.status != MTLCommandBufferStatusError) { return; }

	// If a command buffer error has occurred, report the error. If the error affects
	// the physical device, always mark both the device and physical device as lost.
	// If the error is local to this command buffer, optionally mark the device (but not the
	// physical device) as lost, depending on the value of MVKConfiguration::resumeLostDevice.
	VkResult vkErr = VK_ERROR_UNKNOWN;
	bool markDeviceLoss = !getMVKConfig().resumeLostDevice;
	bool markPhysicalDeviceLoss = false;
	switch (mtlCmdBuff.error.code) {
		case MTLCommandBufferErrorBlacklisted:
		case MTLCommandBufferErrorNotPermitted:	// May also be used for command buffers executed in the background without the right entitlement.
#if MVK_MACOS && !MVK_MACCAT
		case MTLCommandBufferErrorDeviceRemoved:
#endif
			vkErr = VK_ERROR_DEVICE_LOST;
			markDeviceLoss = true;
			markPhysicalDeviceLoss = true;
			break;
		case MTLCommandBufferErrorTimeout:
			vkErr = VK_TIMEOUT;
			break;
#if MVK_XCODE_13
		case MTLCommandBufferErrorStackOverflow:
#endif
		case MTLCommandBufferErrorPageFault:
		case MTLCommandBufferErrorOutOfMemory:
		default:
			vkErr = VK_ERROR_OUT_OF_DEVICE_MEMORY;
			break;
	}
	if (markDeviceLoss) {
		getDevice()->stopAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_DEVICE);
		getDevice()->markLost(markPhysicalDeviceLoss);
	}
	reportResult(vkErr, (markDeviceLoss ? MVK_CONFIG_LOG_LEVEL_ERROR : MVK_CONFIG_LOG_LEVEL_WARNING),
				 "%s VkDevice after MTLCommandBuffer \"%s\" execution failed (code %li): %s",
				 (markDeviceLoss ? "Lost" : "Resumed"),
				 (mtlCmdBuff.label ? mtlCmdBuff.label.UTF8String : ""),
				 mtlCmdBuff.error.code, mtlCmdBuff.error.localizedDescription.UTF8String);

#if MVK_XCODE_12
	if (&MTLCommandBufferEncoderInfoErrorKey != nullptr) {
		if (NSArray<id<MTLCommandBufferEncoderInfo>>* mtlEncInfo = mtlCmdBuff.error.userInfo[MTLCommandBufferEncoderInfoErrorKey]) {
			MVKLogInfo("Encoders for %p \"%s\":", mtlCmdBuff, mtlCmdBuff.label ? mtlCmdBuff.label.UTF8String : "");
			for (id<MTLCommandBufferEncoderInfo> enc in mtlEncInfo) {
				MVKLogInfo(" - %s: %s", enc.label.UTF8String, mvkStringFromMTLCommandEncoderErrorState(enc.errorState));
				if (enc.debugSignposts.count > 0) {
					MVKLogInfo("   Debug signposts:");
					for (NSString* signpost in enc.debugSignposts) {
						MVKLogInfo("    - %s", signpost.UTF8String);
					}
				}
			}
		}
	}
	if ([mtlCmdBuff respondsToSelector: @selector(logs)]) {
		bool isFirstMsg = true;
		for (id<MTLFunctionLog> log in mtlCmdBuff.logs) {
			if (isFirstMsg) {
				MVKLogInfo("Shader log messages:");
				isFirstMsg = false;
			}
			MVKLogInfo("%s", log.description.UTF8String);
		}
	}
#endif
}

#pragma mark Construction

MVKQueue::MVKQueue(MVKDevice* device, MVKQueueFamily* queueFamily, uint32_t index, float priority, VkQueueGlobalPriority globalPriority) : MVKDeviceTrackingMixin(device) {
	_queueFamily = queueFamily;
	_index = index;
	_priority = priority;
	_globalPriority = globalPriority;

	initName();
	initExecQueue();
	initMTLCommandQueue();
}

void MVKQueue::initName() {
	const char* fmt = "MoltenVKQueue-%d-%d-%.1f";
	char name[256];
	snprintf(name, sizeof(name)/sizeof(char), fmt, _queueFamily->getIndex(), _index, _priority);
	_name = name;
}

void MVKQueue::initExecQueue() {
	_execQueue = nil;
	if ( !getMVKConfig().synchronousQueueSubmits ) {
		// Determine the dispatch queue priority
		dispatch_qos_class_t dqQOS;
		switch (_globalPriority) {
			case VK_QUEUE_GLOBAL_PRIORITY_LOW:
				dqQOS = QOS_CLASS_UTILITY;
				break;
			case VK_QUEUE_GLOBAL_PRIORITY_HIGH:
				dqQOS = QOS_CLASS_USER_INTERACTIVE;
				break;
			case VK_QUEUE_GLOBAL_PRIORITY_MEDIUM:
			default: // Fall back to default (medium)
				dqQOS = QOS_CLASS_USER_INITIATED;
				break;
		}
		int dqPriority = (1.0 - _priority) * QOS_MIN_RELATIVE_PRIORITY;
		dispatch_queue_attr_t dqAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, dqQOS, dqPriority);

		// Create the dispatch queue
		_execQueue = dispatch_queue_create((getName() + "-Dispatch").c_str(), dqAttr);		// retained
	}
}

// Retrieves and initializes the Metal command queue and Xcode GPU capture scopes
void MVKQueue::initMTLCommandQueue() {
	_mtlQueue = _queueFamily->getMTLCommandQueue(_index);	// not retained (cached in queue family)
	_device->addResidencySet(_mtlQueue);

	_submissionCaptureScope = new MVKGPUCaptureScope(this);
	if (_queueFamily->getIndex() == getMVKConfig().defaultGPUCaptureScopeQueueFamilyIndex &&
		_index == getMVKConfig().defaultGPUCaptureScopeQueueIndex) {
		getDevice()->startAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_FRAME, _mtlQueue);
		_submissionCaptureScope->makeDefault();
	}
	_submissionCaptureScope->beginScope();	// Allow Xcode to capture the first frame if desired.
}

MVKQueue::~MVKQueue() {
	destroyExecQueue();
	_submissionCaptureScope->destroy();
	_device->removeResidencySet(_mtlQueue);

	[_mtlCmdBuffLabelBeginCommandBuffer release];
	[_mtlCmdBuffLabelQueueSubmit release];
	[_mtlCmdBuffLabelQueuePresent release];
	[_mtlCmdBuffLabelDeviceWaitIdle release];
	[_mtlCmdBuffLabelQueueWaitIdle release];
	[_mtlCmdBuffLabelAcquireNextImage release];
	[_mtlCmdBuffLabelInvalidateMappedMemoryRanges release];
}

// Destroys the execution dispatch queue.
void MVKQueue::destroyExecQueue() {
	if (_execQueue) {
		dispatch_release(_execQueue);
		_execQueue = nullptr;
	}
}


#pragma mark -
#pragma mark MVKQueueSubmission

void MVKSemaphoreSubmitInfo::encodeWait(id<MTLCommandBuffer> mtlCmdBuff) {
	if (_semaphore) { _semaphore->encodeWait(mtlCmdBuff, value); }
}

void MVKSemaphoreSubmitInfo::encodeSignal(id<MTLCommandBuffer> mtlCmdBuff) {
	if (_semaphore) { _semaphore->encodeSignal(mtlCmdBuff, value); }
}

MVKSemaphoreSubmitInfo::MVKSemaphoreSubmitInfo(const VkSemaphoreSubmitInfo& semaphoreSubmitInfo) :
	_semaphore((MVKSemaphore*)semaphoreSubmitInfo.semaphore),
	value(semaphoreSubmitInfo.value),
	stageMask(semaphoreSubmitInfo.stageMask),
	deviceIndex(semaphoreSubmitInfo.deviceIndex) {
		if (_semaphore) { _semaphore->retain(); }
}

MVKSemaphoreSubmitInfo::MVKSemaphoreSubmitInfo(const VkSemaphore semaphore,
											   VkPipelineStageFlags stageMask) :
	_semaphore((MVKSemaphore*)semaphore),
	value(0),
	stageMask(stageMask),
	deviceIndex(0) {
		if (_semaphore) { _semaphore->retain(); }
}

MVKSemaphoreSubmitInfo::MVKSemaphoreSubmitInfo(const MVKSemaphoreSubmitInfo& other) :
	_semaphore(other._semaphore),
	value(other.value),
	stageMask(other.stageMask),
	deviceIndex(other.deviceIndex) {
		if (_semaphore) { _semaphore->retain(); }
}

MVKSemaphoreSubmitInfo& MVKSemaphoreSubmitInfo::operator=(const MVKSemaphoreSubmitInfo& other) {
	// Retain new object first in case it's the same object
	if (other._semaphore) {other._semaphore->retain(); }
	if (_semaphore) { _semaphore->release(); }
	_semaphore = other._semaphore;

	value = other.value;
	stageMask = other.stageMask;
	deviceIndex = other.deviceIndex;
	return *this;
}

MVKSemaphoreSubmitInfo::~MVKSemaphoreSubmitInfo() {
	if (_semaphore) { _semaphore->release(); }
}

MVKCommandBufferSubmitInfo::MVKCommandBufferSubmitInfo(const VkCommandBufferSubmitInfo& commandBufferInfo) :
	commandBuffer(MVKCommandBuffer::getMVKCommandBuffer(commandBufferInfo.commandBuffer)),
	deviceMask(commandBufferInfo.deviceMask) {}

MVKCommandBufferSubmitInfo::MVKCommandBufferSubmitInfo(VkCommandBuffer commandBuffer) :
	commandBuffer(MVKCommandBuffer::getMVKCommandBuffer(commandBuffer)),
	deviceMask(0) {}

MVKQueueSubmission::MVKQueueSubmission(MVKQueue* queue,
									   uint32_t waitSemaphoreInfoCount,
									   const VkSemaphoreSubmitInfo* pWaitSemaphoreSubmitInfos) : 
	MVKBaseDeviceObject(queue->getDevice()),
	_queue(queue) {

	_queue->retain();	// Retain here and release in destructor. See note for MVKQueueCommandBufferSubmission::finish().
	_creationTime = getPerformanceTimestamp();

	_waitSemaphores.reserve(waitSemaphoreInfoCount);
	for (uint32_t i = 0; i < waitSemaphoreInfoCount; i++) {
		_waitSemaphores.emplace_back(pWaitSemaphoreSubmitInfos[i]);
	}
}

MVKQueueSubmission::MVKQueueSubmission(MVKQueue* queue,
									   uint32_t waitSemaphoreCount,
									   const VkSemaphore* pWaitSemaphores,
									   const VkPipelineStageFlags* pWaitDstStageMask) :
	MVKBaseDeviceObject(queue->getDevice()),
	_queue(queue) {

	_queue->retain();	// Retain here and release in destructor. See note for MVKQueueCommandBufferSubmission::finish().
	_creationTime = getPerformanceTimestamp();

	_waitSemaphores.reserve(waitSemaphoreCount);
	for (uint32_t i = 0; i < waitSemaphoreCount; i++) {
		_waitSemaphores.emplace_back(pWaitSemaphores[i], pWaitDstStageMask ? pWaitDstStageMask[i] : 0);
	}
}

MVKQueueSubmission::~MVKQueueSubmission() {
	_queue->release();
}


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmission

VkResult MVKQueueCommandBufferSubmission::execute() {

	_queue->_submissionCaptureScope->beginScope();

	// If using encoded semaphore waiting, do so now.
	for (auto& ws : _waitSemaphores) { ws.encodeWait(getActiveMTLCommandBuffer()); }

	// Wait time from an async vkQueueSubmit() call to starting submit and encoding of the command buffers
	addPerformanceInterval(_queue->getPerformanceStats().queue.waitSubmitCommandBuffers, _creationTime);

	// Submit each command buffer.
	submitCommandBuffers();

	// If using encoded semaphore signaling, do so now.
	for (auto& ss : _signalSemaphores) { ss.encodeSignal(getActiveMTLCommandBuffer()); }

	// Commit the last MTLCommandBuffer.
	// Nothing after this because callback might destroy this instance before this function ends.
	return commitActiveMTLCommandBuffer(true);
}

// Returns the active MTLCommandBuffer, lazily retrieving it from the queue if needed.
id<MTLCommandBuffer> MVKQueueCommandBufferSubmission::getActiveMTLCommandBuffer() {
	if ( !_activeMTLCommandBuffer ) {
		setActiveMTLCommandBuffer(_queue->getMTLCommandBuffer(_commandUse));
	}
	return _activeMTLCommandBuffer;
}

// Commits the current active MTLCommandBuffer, if it exists, and sets a new active MTLCommandBuffer.
void MVKQueueCommandBufferSubmission::setActiveMTLCommandBuffer(id<MTLCommandBuffer> mtlCmdBuff) {

	if (_activeMTLCommandBuffer) { commitActiveMTLCommandBuffer(); }

	_activeMTLCommandBuffer = [mtlCmdBuff retain];		// retained to handle prefilled
	[_activeMTLCommandBuffer enqueue];
}

// Commits and releases the currently active MTLCommandBuffer, optionally signalling
// when the MTLCommandBuffer is done. The first time this is called, it will wait on
// any semaphores. We have delayed signalling the semaphores as long as possible to
// allow as much filling of the MTLCommandBuffer as possible before forcing a wait.
VkResult MVKQueueCommandBufferSubmission::commitActiveMTLCommandBuffer(bool signalCompletion) {

	// If using inline semaphore waiting, do so now.
	// When prefilled command buffers are used, multiple commits will happen because native semaphore
	// waits need to be committed before the prefilled command buffer is committed. Since semaphores
	// will reset their internal signal flag on wait, we need to make sure that we only wait once, otherwise we will freeze.
	// Another option to wait on emulated semaphores once is to do it in the execute function, but doing it here
	// should be more performant when prefilled command buffers aren't used, because we spend time encoding commands
	// first, thus giving the command buffer signalling these semaphores more time to complete.
	if ( !_emulatedWaitDone ) {
		for (auto& ws : _waitSemaphores) { ws.encodeWait(nil); }
		_emulatedWaitDone = true;
	}

	// The visibility result buffer will be returned to its pool when the active MTLCommandBuffer
	// finishes executing, and therefore cannot be used beyond the active MTLCommandBuffer.
	// By now, it's been submitted to the MTLCommandBuffer, so remove it from the encoding context,
	// to ensure a fresh one will be used by commands executing on any subsequent MTLCommandBuffers.
	_encodingContext.visibilityResultBuffer = nullptr;

	// If this is the last command buffer in the submission, we're losing the context and need synchronize
	// current barrier fences to the ones at index 0, which will be what the next submision starts with.
	if (isUsingMetalArgumentBuffers() && signalCompletion) {
		_encodingContext.syncFences(getDevice(), _activeMTLCommandBuffer);
	}

	// If we need to signal completion, use getActiveMTLCommandBuffer() to ensure at least
	// one MTLCommandBuffer is used, otherwise if this instance has no content, it will not
	// finish(), signal the fence and semaphores, and be destroyed.
	// Use temp var for MTLCommandBuffer commit and release because completion callback
	// may destroy this instance before this function ends.
	id<MTLCommandBuffer> mtlCmdBuff = signalCompletion ? getActiveMTLCommandBuffer() : _activeMTLCommandBuffer;
	_activeMTLCommandBuffer = nil;

	uint64_t startTime = getPerformanceTimestamp();
	[mtlCmdBuff addCompletedHandler: ^(id<MTLCommandBuffer> mtlCB) {
		addPerformanceInterval(getPerformanceStats().queue.mtlCommandBufferExecution, startTime);
		if (signalCompletion) { this->finish(); }	// Must be the last thing the completetion callback does.
	}];

	// Retrieve the result before committing MTLCommandBuffer, because finish() will destroy this instance.
	VkResult rslt = mtlCmdBuff ? getConfigurationResult() : VK_ERROR_OUT_OF_POOL_MEMORY;
	[mtlCmdBuff commit];
	[mtlCmdBuff release];		// retained

	// If we need to signal completion, but an error occurred and the MTLCommandBuffer
	// was not created, call the finish() function directly.
	if (signalCompletion && !mtlCmdBuff) { finish(); }

	return rslt;
}

// Be sure to retain() any API objects referenced in this function, and release() them in the
// destructor (or superclass destructor). It is possible for rare race conditions to result
// in the app destroying API objects before this function completes execution. For example,
// this may occur if a GPU semaphore here triggers another submission that triggers a fence,
// and the app immediately destroys objects. Rare, but it has been encountered.
void MVKQueueCommandBufferSubmission::finish() {

	// Performed here instead of as part of execute() for rare case where app destroys queue
	// immediately after a waitIdle() is cleared by fence below, taking the capture scope with it.
	_queue->_submissionCaptureScope->endScope();

	// If using inline semaphore signaling, do so now.
	for (auto& ss : _signalSemaphores) { ss.encodeSignal(nil); }

	// If a fence exists, signal it.
	if (_fence) { _fence->signal(); }

	this->destroy();
}

// On device loss, the fence and signal semaphores may be signalled early, and they might then
// be destroyed on the waiting thread before this submission is done with them. We therefore
// retain() each here to ensure they live long enough for this submission to finish using them.
MVKQueueCommandBufferSubmission::MVKQueueCommandBufferSubmission(MVKQueue* queue,
																 const VkSubmitInfo2* pSubmit,
																 VkFence fence,
																 MVKCommandUse cmdUse) :
	MVKQueueSubmission(queue,
					   pSubmit ? pSubmit->waitSemaphoreInfoCount : 0,
					   pSubmit ? pSubmit->pWaitSemaphoreInfos : nullptr),
	_fence((MVKFence*)fence),
	_commandUse(cmdUse) {
	
	if (_fence) { _fence->retain(); }

	// pSubmit can be null if just tracking the fence alone
	if (pSubmit) {
		uint32_t ssCnt = pSubmit->signalSemaphoreInfoCount;
		_signalSemaphores.reserve(ssCnt);
		for (uint32_t i = 0; i < ssCnt; i++) {
			_signalSemaphores.emplace_back(pSubmit->pSignalSemaphoreInfos[i]);
		}
	}
}

// On device loss, the fence and signal semaphores may be signalled early, and they might then
// be destroyed on the waiting thread before this submission is done with them. We therefore
// retain() each here to ensure they live long enough for this submission to finish using them.
MVKQueueCommandBufferSubmission::MVKQueueCommandBufferSubmission(MVKQueue* queue,
																 const VkSubmitInfo* pSubmit,
																 VkFence fence,
																 MVKCommandUse cmdUse)
	: MVKQueueSubmission(queue,
						 pSubmit ? pSubmit->waitSemaphoreCount : 0,
						 pSubmit ? pSubmit->pWaitSemaphores : nullptr,
						 pSubmit ? pSubmit->pWaitDstStageMask : nullptr),

	_fence((MVKFence*)fence),
	_commandUse(cmdUse) {
	
	if (_fence) { _fence->retain(); }

    // pSubmit can be null if just tracking the fence alone
    if (pSubmit) {
		uint32_t ssCnt = pSubmit->signalSemaphoreCount;
		_signalSemaphores.reserve(ssCnt);
		for (uint32_t i = 0; i < ssCnt; i++) {
			_signalSemaphores.emplace_back(pSubmit->pSignalSemaphores[i], 0);
		}

		VkTimelineSemaphoreSubmitInfo* pTimelineSubmit = nullptr;
        for (const auto* next = (const VkBaseInStructure*)pSubmit->pNext; next; next = next->pNext) {
            switch (next->sType) {
                case VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO:
                    pTimelineSubmit = (VkTimelineSemaphoreSubmitInfo*)next;
                    break;
                default:
                    break;
            }
        }
        if (pTimelineSubmit) {
            uint32_t wsvCnt = pTimelineSubmit->waitSemaphoreValueCount;
            for (uint32_t i = 0; i < wsvCnt; i++) {
                _waitSemaphores[i].value = pTimelineSubmit->pWaitSemaphoreValues[i];
            }

			uint32_t ssvCnt = pTimelineSubmit->signalSemaphoreValueCount;
			for (uint32_t i = 0; i < ssvCnt; i++) {
				_signalSemaphores[i].value = pTimelineSubmit->pSignalSemaphoreValues[i];
			}
        }
    }
}

MVKQueueCommandBufferSubmission::~MVKQueueCommandBufferSubmission() {
	if (_fence) { _fence->release(); }
}


template <size_t N>
void MVKQueueFullCommandBufferSubmission<N>::submitCommandBuffers() {
	uint64_t startTime = getPerformanceTimestamp();

	for (auto& cbInfo : _cmdBuffers) { cbInfo.commandBuffer->submit(this, &_encodingContext); }

	addPerformanceInterval(getPerformanceStats().queue.submitCommandBuffers, startTime);
}

template <size_t N>
MVKQueueFullCommandBufferSubmission<N>::MVKQueueFullCommandBufferSubmission(MVKQueue* queue,
																			const VkSubmitInfo2* pSubmit,
																			VkFence fence,
																			MVKCommandUse cmdUse)
	: MVKQueueCommandBufferSubmission(queue, pSubmit, fence, cmdUse) {

	if (pSubmit) {
		uint32_t cbCnt = pSubmit->commandBufferInfoCount;
		_cmdBuffers.reserve(cbCnt);
		for (uint32_t i = 0; i < cbCnt; i++) {
			_cmdBuffers.emplace_back(pSubmit->pCommandBufferInfos[i]);
			setConfigurationResult(_cmdBuffers.back().commandBuffer->getConfigurationResult());
		}
	}
}

template <size_t N>
MVKQueueFullCommandBufferSubmission<N>::MVKQueueFullCommandBufferSubmission(MVKQueue* queue,
																			const VkSubmitInfo* pSubmit,
																			VkFence fence,
																			MVKCommandUse cmdUse)
	: MVKQueueCommandBufferSubmission(queue, pSubmit, fence, cmdUse) {

	if (pSubmit) {
		uint32_t cbCnt = pSubmit->commandBufferCount;
		_cmdBuffers.reserve(cbCnt);
		for (uint32_t i = 0; i < cbCnt; i++) {
			_cmdBuffers.emplace_back(pSubmit->pCommandBuffers[i]);
			setConfigurationResult(_cmdBuffers.back().commandBuffer->getConfigurationResult());
		}
	}
}


#pragma mark -
#pragma mark MVKQueuePresentSurfaceSubmission

// If the semaphores are encodable, wait on them by encoding them on the MTLCommandBuffer before presenting.
// If the semaphores are not encodable, wait on them inline after presenting.
// The semaphores know what to do.
VkResult MVKQueuePresentSurfaceSubmission::execute() {
	// MTLCommandBuffer retain references to avoid rare case where objects are destroyed too early.
	// Although testing could not determine which objects were being lost, queue present MTLCommandBuffers
	// are used only once per frame, and retain so few objects, that blanket retention is still performant.
	id<MTLCommandBuffer> mtlCmdBuff = _queue->getMTLCommandBuffer(kMVKCommandUseQueuePresent, true);

	for (auto& ws : _waitSemaphores) {
		ws.encodeWait(mtlCmdBuff);	// Encoded semaphore waits
		ws.encodeWait(nil);			// Inline semaphore waits
	}

	// Wait time from an async vkQueuePresentKHR() call to starting presentation of the swapchains
	addPerformanceInterval(getPerformanceStats().queue.waitPresentSwapchains, _creationTime);

	for (int i = 0; i < _presentInfo.size(); i++ ) {
		setConfigurationResult(_presentInfo[i].presentableImage->presentCAMetalDrawable(mtlCmdBuff, _presentInfo[i]));
	}

	if (_queue->_queueFamily->getIndex() == getMVKConfig().defaultGPUCaptureScopeQueueFamilyIndex &&
		_queue->_index == getMVKConfig().defaultGPUCaptureScopeQueueIndex) {
		getDevice()->stopAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_ON_DEMAND);
		getDevice()->startAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_ON_DEMAND, _queue->getMTLCommandQueue());
	}

	if ( !mtlCmdBuff ) { setConfigurationResult(VK_ERROR_OUT_OF_POOL_MEMORY); }	// Check after images may set error.

	// Add completion callback to the MTLCommandBuffer to call finish(), 
	// or if the MTLCommandBuffer could not be created, call finish() directly.
	// Retrieve the result first, because finish() will destroy this instance.
	VkResult rslt = getConfigurationResult();
	if (mtlCmdBuff) {
		[mtlCmdBuff addCompletedHandler: ^(id<MTLCommandBuffer> mtlCB) { this->finish(); }];
		[mtlCmdBuff commit];
	} else {
		finish();
	}
	return rslt;
}

void MVKQueuePresentSurfaceSubmission::finish() {

	// Let Xcode know the current frame is done, then start a new frame,
	// and if auto GPU capture is active, and it's time to stop it, do so.
	auto cs = _queue->_submissionCaptureScope;
	cs->endScope();
	cs->beginScope();
	if (_queue->_queueFamily->getIndex() == getMVKConfig().defaultGPUCaptureScopeQueueFamilyIndex &&
		_queue->_index == getMVKConfig().defaultGPUCaptureScopeQueueIndex) {
		getDevice()->stopAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_FRAME);
	}

	this->destroy();
}

MVKQueuePresentSurfaceSubmission::MVKQueuePresentSurfaceSubmission(MVKQueue* queue,
																   const VkPresentInfoKHR* pPresentInfo)
	: MVKQueueSubmission(queue, pPresentInfo->waitSemaphoreCount, pPresentInfo->pWaitSemaphores, nullptr) {

	const VkPresentTimesInfoGOOGLE* pPresentTimesInfo = nullptr;
	const VkSwapchainPresentFenceInfoEXT* pPresentFenceInfo = nullptr;
	const VkSwapchainPresentModeInfoEXT* pPresentModeInfo = nullptr;
	const VkPresentRegionsKHR* pPresentRegions = nullptr;
	const VkPresentIdKHR* pPresentId = nullptr;
	for (auto* next = (const VkBaseInStructure*)pPresentInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_PRESENT_REGIONS_KHR:
				pPresentRegions = (const VkPresentRegionsKHR*) next;
				break;
			case VK_STRUCTURE_TYPE_PRESENT_ID_KHR:
				pPresentId = (const VkPresentIdKHR*) next;
				break;
			case VK_STRUCTURE_TYPE_SWAPCHAIN_PRESENT_FENCE_INFO_EXT:
				pPresentFenceInfo = (const VkSwapchainPresentFenceInfoEXT*) next;
				break;
			case VK_STRUCTURE_TYPE_SWAPCHAIN_PRESENT_MODE_INFO_EXT:
				pPresentModeInfo = (const VkSwapchainPresentModeInfoEXT*) next;
				break;
			case VK_STRUCTURE_TYPE_PRESENT_TIMES_INFO_GOOGLE:
				pPresentTimesInfo = (const VkPresentTimesInfoGOOGLE*) next;
				break;
			default:
				break;
		}
	}

	// Populate the array of swapchain images, testing each one for status
	uint32_t scCnt = pPresentInfo->swapchainCount;
	const VkPresentTimeGOOGLE* pPresentTimes = nullptr;
	if (pPresentTimesInfo) {
		pPresentTimes = pPresentTimesInfo->pTimes;
		MVKAssert(pPresentTimesInfo->swapchainCount == scCnt, "VkPresentTimesInfoGOOGLE swapchainCount must match VkPresentInfo swapchainCount.");
	}
	const VkPresentModeKHR* pPresentModes = nullptr;
	if (pPresentModeInfo) {
		pPresentModes = pPresentModeInfo->pPresentModes;
		MVKAssert(pPresentModeInfo->swapchainCount == scCnt, "VkSwapchainPresentModeInfoEXT swapchainCount must match VkPresentInfo swapchainCount.");
	}
	const VkFence* pFences = nullptr;
	if (pPresentFenceInfo) {
		pFences = pPresentFenceInfo->pFences;
		MVKAssert(pPresentFenceInfo->swapchainCount == scCnt, "VkSwapchainPresentFenceInfoEXT swapchainCount must match VkPresentInfo swapchainCount.");
	}
	const VkPresentRegionKHR* pRegions = nullptr;
	if (pPresentRegions) {
		pRegions = pPresentRegions->pRegions;
	}
	const uint64_t* pPresentIds = nullptr;
	if (pPresentId) {
		pPresentIds = pPresentId->pPresentIds;
	}

	VkResult* pSCRslts = pPresentInfo->pResults;
	_presentInfo.reserve(scCnt);
	for (uint32_t scIdx = 0; scIdx < scCnt; scIdx++) {
		MVKSwapchain* mvkSC = (MVKSwapchain*)pPresentInfo->pSwapchains[scIdx];
		MVKImagePresentInfo presentInfo = {};	// Start with everything zeroed
		presentInfo.queue = _queue;
		presentInfo.presentableImage = mvkSC->getPresentableImage(pPresentInfo->pImageIndices[scIdx]);
		presentInfo.presentMode = pPresentModes ? pPresentModes[scIdx] : VK_PRESENT_MODE_MAX_ENUM_KHR;
		presentInfo.fence = pFences ? (MVKFence*)pFences[scIdx] : nullptr;
		presentInfo.presentId = pPresentIds ? pPresentIds[scIdx] : 0;
		if (pPresentTimes) {
			presentInfo.presentIDGoogle = pPresentTimes[scIdx].presentID;
			presentInfo.desiredPresentTime = pPresentTimes[scIdx].desiredPresentTime;
		}
		mvkSC->setLayerNeedsDisplay(pRegions ? &pRegions[scIdx] : nullptr);
		_presentInfo.push_back(presentInfo);
		VkResult scRslt = mvkSC->getSurfaceStatus();
		if (pSCRslts) { pSCRslts[scIdx] = scRslt; }
		setConfigurationResult(scRslt);
	}
}

