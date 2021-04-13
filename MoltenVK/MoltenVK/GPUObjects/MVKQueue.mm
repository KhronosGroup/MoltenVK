/*
 * MVKQueue.mm
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
			uint32_t maxCmdBuffs = mvkConfig()->maxActiveMetalCommandBuffersPerQueue;
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

void MVKQueue::propagateDebugName() { setLabelIfNotNil(_mtlQueue, _debugName); }


#pragma mark Queue submissions

// Execute the queue submission under an autoreleasepool to ensure transient Metal objects are autoreleased.
// This is critical for apps that don't use standard OS autoreleasing runloop threading.
static inline void execute(MVKQueueSubmission* qSubmit) { @autoreleasepool { qSubmit->execute(); } }

// Executes the submmission, either immediately, or by dispatching to an execution queue.
// Submissions to the execution queue are wrapped in a dedicated autoreleasepool.
// Relying on the dispatch queue to find time to drain the autoreleasepool can
// result in significant memory creep under heavy workloads.
VkResult MVKQueue::submit(MVKQueueSubmission* qSubmit) {
	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }

	if ( !qSubmit ) { return VK_SUCCESS; }     // Ignore nils

	VkResult rslt = qSubmit->getConfigurationResult();     // Extract result before submission to avoid race condition with early destruction
	if (_execQueue) {
		dispatch_async(_execQueue, ^{ execute(qSubmit); } );
	} else {
		execute(qSubmit);
	}
	return rslt;
}

VkResult MVKQueue::submit(uint32_t submitCount, const VkSubmitInfo* pSubmits, VkFence fence) {

    // Fence-only submission
    if (submitCount == 0 && fence) {
        return submit(new MVKQueueCommandBufferSubmission(this, nullptr, fence));
    }

    VkResult rslt = VK_SUCCESS;
    for (uint32_t sIdx = 0; sIdx < submitCount; sIdx++) {
        VkFence fenceOrNil = (sIdx == (submitCount - 1)) ? fence : VK_NULL_HANDLE; // last one gets the fence

		const VkSubmitInfo* pVkSub = &pSubmits[sIdx];
		MVKQueueCommandBufferSubmission* mvkSub;
		uint32_t cbCnt = pVkSub->commandBufferCount;
		if (cbCnt <= 1) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<1>(this, pVkSub, fenceOrNil);
		} else if (cbCnt <= 16) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<16>(this, pVkSub, fenceOrNil);
		} else if (cbCnt <= 32) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<32>(this, pVkSub, fenceOrNil);
		} else if (cbCnt <= 64) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<64>(this, pVkSub, fenceOrNil);
		} else if (cbCnt <= 128) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<128>(this, pVkSub, fenceOrNil);
		} else if (cbCnt <= 256) {
			mvkSub = new MVKQueueFullCommandBufferSubmission<256>(this, pVkSub, fenceOrNil);
		} else {
			mvkSub = new MVKQueueFullCommandBufferSubmission<512>(this, pVkSub, fenceOrNil);
		}

        VkResult subRslt = submit(mvkSub);
        if (rslt == VK_SUCCESS) { rslt = subRslt; }
    }
    return rslt;
}

VkResult MVKQueue::submit(const VkPresentInfoKHR* pPresentInfo) {
	return submit(new MVKQueuePresentSurfaceSubmission(this, pPresentInfo));
}

// Create an empty submit struct and fence, submit to queue and wait on fence.
VkResult MVKQueue::waitIdle() {

	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }

	VkFenceCreateInfo vkFenceInfo = {
		.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
		.pNext = nullptr,
		.flags = 0,
	};

	MVKFence mvkFence(_device, &vkFenceInfo);
	VkFence fence = (VkFence)&mvkFence;
	submit(0, nullptr, fence);
	return mvkWaitForFences(_device, 1, &fence, false);
}

id<MTLCommandBuffer> MVKQueue::getMTLCommandBuffer(bool retainRefs) {
#if MVK_XCODE_12
	if ([_mtlQueue respondsToSelector: @selector(commandBufferWithDescriptor:)]) {
		MTLCommandBufferDescriptor* mtlCmdBuffDesc = [MTLCommandBufferDescriptor new];	// temp retain
		mtlCmdBuffDesc.retainedReferences = retainRefs;
		if (mvkConfig()->debugMode) {
			mtlCmdBuffDesc.errorOptions |= MTLCommandBufferErrorOptionEncoderExecutionStatus;
		}
		id<MTLCommandBuffer> cmdBuff = [_mtlQueue commandBufferWithDescriptor: mtlCmdBuffDesc];
		[mtlCmdBuffDesc release];														// temp release
		return cmdBuff;
	} else
#endif
	if (retainRefs) {
		return [_mtlQueue commandBuffer];
	} else {
		return [_mtlQueue commandBufferWithUnretainedReferences];
	}
}


#pragma mark Construction

#define MVK_DISPATCH_QUEUE_QOS_CLASS		QOS_CLASS_USER_INITIATED

MVKQueue::MVKQueue(MVKDevice* device, MVKQueueFamily* queueFamily, uint32_t index, float priority)
        : MVKDeviceTrackingMixin(device) {

	_queueFamily = queueFamily;
	_index = index;
	_priority = priority;

	initName();
	initExecQueue();
	initMTLCommandQueue();
	initGPUCaptureScopes();
}

void MVKQueue::initName() {
	const char* fmt = "MoltenVKQueue-%d-%d-%.1f";
	char name[256];
	sprintf(name, fmt, _queueFamily->getIndex(), _index, _priority);
	_name = name;
}

void MVKQueue::initExecQueue() {
	_execQueue = nil;
	if ( !mvkConfig()->synchronousQueueSubmits ) {
		// Determine the dispatch queue priority
		dispatch_qos_class_t dqQOS = MVK_DISPATCH_QUEUE_QOS_CLASS;
		int dqPriority = (1.0 - _priority) * QOS_MIN_RELATIVE_PRIORITY;
		dispatch_queue_attr_t dqAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, dqQOS, dqPriority);

		// Create the dispatch queue
		_execQueue = dispatch_queue_create((getName() + "-Dispatch").c_str(), dqAttr);		// retained
	}
}

// Retrieves and initializes the Metal command queue.
void MVKQueue::initMTLCommandQueue() {
	uint64_t startTime = _device->getPerformanceTimestamp();
	_mtlQueue = _queueFamily->getMTLCommandQueue(_index);	// not retained (cached in queue family)
	_device->addActivityPerformance(_device->_performanceStatistics.queue.mtlQueueAccess, startTime);
}

// Initializes Xcode GPU capture scopes
void MVKQueue::initGPUCaptureScopes() {
	_submissionCaptureScope = new MVKGPUCaptureScope(this);

	const MVKConfiguration* pMVKConfig = mvkConfig();
	if (_queueFamily->getIndex() == pMVKConfig->defaultGPUCaptureScopeQueueFamilyIndex &&
		_index == pMVKConfig->defaultGPUCaptureScopeQueueIndex) {

		getDevice()->startAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_FRAME, _mtlQueue);
		_submissionCaptureScope->makeDefault();

	}
	_submissionCaptureScope->beginScope();	// Allow Xcode to capture the first frame if desired.
}

MVKQueue::~MVKQueue() {
	destroyExecQueue();
	_submissionCaptureScope->destroy();
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

MVKQueueSubmission::MVKQueueSubmission(MVKQueue* queue,
									   uint32_t waitSemaphoreCount,
									   const VkSemaphore* pWaitSemaphores) {
	_queue = queue;
	_waitSemaphores.reserve(waitSemaphoreCount);
	for (uint32_t i = 0; i < waitSemaphoreCount; i++) {
		_waitSemaphores.push_back(make_pair((MVKSemaphore*)pWaitSemaphores[i], (uint64_t)0));
	}
}


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmission

void MVKQueueCommandBufferSubmission::execute() {

//	MVKLogDebug("Executing submission %p.", this);

	_queue->_submissionCaptureScope->beginScope();

	// If using encoded semaphore waiting, do so now.
	for (auto& ws : _waitSemaphores) { ws.first->encodeWait(getActiveMTLCommandBuffer(), ws.second); }

	// Submit each command buffer.
	submitCommandBuffers();

	// If using encoded semaphore signaling, do so now.
	for (auto& ss : _signalSemaphores) { ss.first->encodeSignal(getActiveMTLCommandBuffer(), ss.second); }

	// Commit the last MTLCommandBuffer.
	// Nothing after this because callback might destroy this instance before this function ends.
	commitActiveMTLCommandBuffer(true);
}

// Returns the active MTLCommandBuffer, lazily retrieving it from the queue if needed.
id<MTLCommandBuffer> MVKQueueCommandBufferSubmission::getActiveMTLCommandBuffer() {
	if ( !_activeMTLCommandBuffer ) {
		setActiveMTLCommandBuffer(_queue->getMTLCommandBuffer());
	}
	return _activeMTLCommandBuffer;
}

// Commits the current active MTLCommandBuffer, if it exists, and sets a new active MTLCommandBuffer.
void MVKQueueCommandBufferSubmission::setActiveMTLCommandBuffer(id<MTLCommandBuffer> mtlCmdBuff) {

	if (_activeMTLCommandBuffer) { commitActiveMTLCommandBuffer(); }

	_activeMTLCommandBuffer = [mtlCmdBuff retain];		// retained to handle prefilled
	[_activeMTLCommandBuffer enqueue];
}

#if MVK_XCODE_12
static const char* mvkStringFromErrorState(MTLCommandEncoderErrorState errState) {
	switch (errState) {
		case MTLCommandEncoderErrorStateUnknown: return "unknown";
		case MTLCommandEncoderErrorStateAffected: return "affected";
		case MTLCommandEncoderErrorStateCompleted: return "completed";
		case MTLCommandEncoderErrorStateFaulted: return "faulted";
		case MTLCommandEncoderErrorStatePending: return "pending";
	}
	return "unknown";
}
#endif

// Commits and releases the currently active MTLCommandBuffer, optionally signalling
// when the MTLCommandBuffer is done. The first time this is called, it will wait on
// any semaphores. We have delayed signalling the semaphores as long as possible to
// allow as much filling of the MTLCommandBuffer as possible before forcing a wait.
void MVKQueueCommandBufferSubmission::commitActiveMTLCommandBuffer(bool signalCompletion) {

	// If using inline semaphore waiting, do so now.
	for (auto& ws : _waitSemaphores) { ws.first->encodeWait(nil, ws.second); }

	// If we need to signal completion, use getActiveMTLCommandBuffer() to ensure at least
	// one MTLCommandBuffer is used, otherwise if this instance has no content, it will not
	// finish(), signal the fence and semaphores ,and be destroyed.
	// Use temp var for MTLCommandBuffer commit and release because completion callback
	// may destroy this instance before this function ends.
	id<MTLCommandBuffer> mtlCmdBuff = signalCompletion ? getActiveMTLCommandBuffer() : _activeMTLCommandBuffer;
	_activeMTLCommandBuffer = nil;

	MVKDevice* mvkDev = _queue->getDevice();
	uint64_t startTime = mvkDev->getPerformanceTimestamp();
	[mtlCmdBuff addCompletedHandler: ^(id<MTLCommandBuffer> mtlCB) {
		if (mtlCB.status == MTLCommandBufferStatusError) {
			getVulkanAPIObject()->reportError(mvkDev->markLost(), "Command buffer %p \"%s\" execution failed (code %li): %s", mtlCB, mtlCB.label ? mtlCB.label.UTF8String : "", mtlCB.error.code, mtlCB.error.localizedDescription.UTF8String);
			// Some errors indicate we lost the physical device as well.
			switch (mtlCB.error.code) {
				case MTLCommandBufferErrorBlacklisted:
				// XXX This may also be used for command buffers executed in the background without the right entitlement.
				case MTLCommandBufferErrorNotPermitted:
#if MVK_MACOS && !MVK_MACCAT
				case MTLCommandBufferErrorDeviceRemoved:
#endif
					mvkDev->getPhysicalDevice()->setConfigurationResult(VK_ERROR_DEVICE_LOST);
					break;
				default:
					if (mvkConfig()->resumeLostDevice) { mvkDev->clearConfigurationResult(); }
					break;
			}
#if MVK_XCODE_12
			if (mvkConfig()->debugMode) {
				if (&MTLCommandBufferEncoderInfoErrorKey != nullptr) {
					if (NSArray<id<MTLCommandBufferEncoderInfo>>* mtlEncInfo = mtlCB.error.userInfo[MTLCommandBufferEncoderInfoErrorKey]) {
						MVKLogInfo("Encoders for %p \"%s\":", mtlCB, mtlCB.label ? mtlCB.label.UTF8String : "");
						for (id<MTLCommandBufferEncoderInfo> enc in mtlEncInfo) {
							MVKLogInfo(" - %s: %s", enc.label.UTF8String, mvkStringFromErrorState(enc.errorState));
							if (enc.debugSignposts.count > 0) {
								MVKLogInfo("   Debug signposts:");
								for (NSString* signpost in enc.debugSignposts) {
									MVKLogInfo("    - %s", signpost.UTF8String);
								}
							}
						}
					}
				}
			}
#endif
		}
#if MVK_XCODE_12
		if (mvkConfig()->debugMode) {
			bool isFirstMsg = true;
			for (id<MTLFunctionLog> log in mtlCB.logs) {
				if (isFirstMsg) {
					MVKLogInfo("Shader log messages:");
					isFirstMsg = false;
				}
				MVKLogInfo("%s", log.description.UTF8String);
			}
		}
#endif

		// Ensure finish() is the last thing the completetion callback does.
		mvkDev->addActivityPerformance(mvkDev->_performanceStatistics.queue.mtlCommandBufferCompletion, startTime);
		if (signalCompletion) { this->finish(); }
	}];

	[mtlCmdBuff commit];
	[mtlCmdBuff release];		// retained
}

void MVKQueueCommandBufferSubmission::finish() {

//	MVKLogDebug("Finishing submission %p. Submission count %u.", this, _subCount--);

	// Performed here instead of as part of execute() for rare case where app destroys queue
	// immediately after a waitIdle() is cleared by fence below, taking the capture scope with it.
	_queue->_submissionCaptureScope->endScope();

	// If using inline semaphore signaling, do so now.
	for (auto& ss : _signalSemaphores) { ss.first->encodeSignal(nil, ss.second); }

	// If a fence exists, signal it.
	if (_fence) { _fence->signal(); }

	this->destroy();
}

MVKQueueCommandBufferSubmission::MVKQueueCommandBufferSubmission(MVKQueue* queue,
																 const VkSubmitInfo* pSubmit,
																 VkFence fence)
        : MVKQueueSubmission(queue,
							 (pSubmit ? pSubmit->waitSemaphoreCount : 0),
							 (pSubmit ? pSubmit->pWaitSemaphores : nullptr)) {

    // pSubmit can be null if just tracking the fence alone
    if (pSubmit) {
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
            // Presentation doesn't support timeline semaphores, so handle wait values here.
            uint32_t wsCnt = pTimelineSubmit->waitSemaphoreValueCount;
            for (uint32_t i = 0; i < wsCnt; i++) {
                _waitSemaphores[i].second = pTimelineSubmit->pWaitSemaphoreValues[i];
            }
        }
        uint32_t ssCnt = pSubmit->signalSemaphoreCount;
        _signalSemaphores.reserve(ssCnt);
        for (uint32_t i = 0; i < ssCnt; i++) {
			auto ss = make_pair((MVKSemaphore*)pSubmit->pSignalSemaphores[i], (uint64_t)0);
            if (pTimelineSubmit) { ss.second = pTimelineSubmit->pSignalSemaphoreValues[i]; }
            _signalSemaphores.push_back(ss);
        }
    }

	_fence = (MVKFence*)fence;
	_activeMTLCommandBuffer = nil;

//	static std::atomic<uint32_t> _subCount;
//	MVKLogDebug("Creating submission %p. Submission count %u.", this, ++_subCount);
}


#pragma mark -
#pragma mark MVKQueuePresentSurfaceSubmission

void MVKQueuePresentSurfaceSubmission::execute() {
	// If the semaphores are encodable, wait on them by encoding them on the MTLCommandBuffer before presenting.
	// If the semaphores are not encodable, wait on them inline after presenting.
	// The semaphores know what to do.
	id<MTLCommandBuffer> mtlCmdBuff = getMTLCommandBuffer();
	for (auto& ws : _waitSemaphores) { ws.first->encodeWait(mtlCmdBuff, 0); }
	for (int i = 0; i < _presentInfo.size(); i++ ) {
		MVKPresentableSwapchainImage *img = _presentInfo[i].presentableImage;
		img->presentCAMetalDrawable(mtlCmdBuff, _presentInfo[i]);
	}
	for (auto& ws : _waitSemaphores) { ws.first->encodeWait(nil, 0); }
	[mtlCmdBuff commit];

	// Let Xcode know the current frame is done, then start a new frame
	auto cs = _queue->_submissionCaptureScope;
	cs->endScope();
	cs->beginScope();
	stopAutoGPUCapture();

	this->destroy();
}

id<MTLCommandBuffer> MVKQueuePresentSurfaceSubmission::getMTLCommandBuffer() {
	id<MTLCommandBuffer> mtlCmdBuff = _queue->getMTLCommandBuffer();
	setLabelIfNotNil(mtlCmdBuff, @"vkQueuePresentKHR CommandBuffer");
	[mtlCmdBuff enqueue];
	return mtlCmdBuff;
}

void MVKQueuePresentSurfaceSubmission::stopAutoGPUCapture() {
	const MVKConfiguration* pMVKConfig = mvkConfig();
	if (_queue->_queueFamily->getIndex() == pMVKConfig->defaultGPUCaptureScopeQueueFamilyIndex &&
		_queue->_index == pMVKConfig->defaultGPUCaptureScopeQueueIndex) {
		_queue->getDevice()->stopAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_FRAME);
	}
}

MVKQueuePresentSurfaceSubmission::MVKQueuePresentSurfaceSubmission(MVKQueue* queue,
																   const VkPresentInfoKHR* pPresentInfo)
	: MVKQueueSubmission(queue, pPresentInfo->waitSemaphoreCount, pPresentInfo->pWaitSemaphores) {

	const VkPresentTimesInfoGOOGLE *pPresentTimesInfoGOOGLE = nullptr;
	for ( const auto *next = ( VkBaseInStructure* ) pPresentInfo->pNext; next; next = next->pNext )
	{
		switch ( next->sType )
		{
			case VK_STRUCTURE_TYPE_PRESENT_TIMES_INFO_GOOGLE:
				pPresentTimesInfoGOOGLE = ( const VkPresentTimesInfoGOOGLE * ) next;
				break;
			default:
				break;
		}
	}

	// Populate the array of swapchain images, testing each one for status
	uint32_t scCnt = pPresentInfo->swapchainCount;
	const VkPresentTimeGOOGLE *pPresentTimesGOOGLE = nullptr;
	if ( pPresentTimesInfoGOOGLE && pPresentTimesInfoGOOGLE->pTimes ) {
		pPresentTimesGOOGLE = pPresentTimesInfoGOOGLE->pTimes;
		MVKAssert( pPresentTimesInfoGOOGLE->swapchainCount == pPresentInfo->swapchainCount, "VkPresentTimesInfoGOOGLE swapchainCount must match VkPresentInfo swapchainCount" );
	}
	VkResult* pSCRslts = pPresentInfo->pResults;
	_presentInfo.reserve(scCnt);
	for (uint32_t scIdx = 0; scIdx < scCnt; scIdx++) {
		MVKSwapchain* mvkSC = (MVKSwapchain*)pPresentInfo->pSwapchains[scIdx];
		MVKPresentTimingInfo presentInfo = {};
		presentInfo.presentableImage = mvkSC->getPresentableImage(pPresentInfo->pImageIndices[scIdx]);
		if ( pPresentTimesGOOGLE ) {
			presentInfo.hasPresentTime = true;
			presentInfo.presentID = pPresentTimesGOOGLE[scIdx].presentID;
			presentInfo.desiredPresentTime = pPresentTimesGOOGLE[scIdx].desiredPresentTime;
		} else {
			presentInfo.hasPresentTime = false;
		}
		_presentInfo.push_back(presentInfo);
		VkResult scRslt = mvkSC->getSurfaceStatus();
		if (pSCRslts) { pSCRslts[scIdx] = scRslt; }
		setConfigurationResult(scRslt);
	}
}

