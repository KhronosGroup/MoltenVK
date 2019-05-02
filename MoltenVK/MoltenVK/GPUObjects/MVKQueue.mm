/*
 * MVKQueue.mm
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

#include "MVKInstance.h"
#include "MVKQueue.h"
#include "MVKSwapchain.h"
#include "MVKSync.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKGPUCapture.h"
#include "MVKLogging.h"

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
		uint32_t maxCmdBuffs = _physicalDevice->getInstance()->getMoltenVKConfiguration()->maxActiveMetalCommandBuffersPerQueue;
		mtlQ = [_physicalDevice->getMTLDevice() newCommandQueueWithMaxCommandBufferCount: maxCmdBuffs];		// retained
		_mtlQueues[queueIndex] = mtlQ;
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


#pragma mark Queue submissions

// Execute the queue submission under an autorelease pool to ensure transient Metal objects are autoreleased.
// This is critical for apps that don't use standard OS autoreleasing runloop threading.
static inline void execute(MVKQueueSubmission* qSubmit) { @autoreleasepool { qSubmit->execute(); } }

// Executes the submmission, either immediately, or by dispatching to an execution queue.
// Submissions to the execution queue are wrapped in a dedicated autorelease pool.
// Relying on the dispatch queue to find time to drain the autorelease pool can
// result in significant memory creep under heavy workloads.
VkResult MVKQueue::submit(MVKQueueSubmission* qSubmit) {
	if ( !qSubmit ) { return VK_SUCCESS; }     // Ignore nils

	VkResult rslt = qSubmit->getConfigurationResult();     // Extract result before submission to avoid race condition with early destruction
	if (_execQueue) {
		dispatch_async(_execQueue, ^{ execute(qSubmit); } );
	} else {
		execute(qSubmit);
	}
	return rslt;
}

VkResult MVKQueue::submit(uint32_t submitCount, const VkSubmitInfo* pSubmits,
                          VkFence fence, MVKCommandUse cmdBuffUse) {

    // Fence-only submission
    if (submitCount == 0 && fence) {
        return submit(new MVKQueueCommandBufferSubmission(this, nullptr, fence, cmdBuffUse));
    }

    VkResult rslt = VK_SUCCESS;
    for (uint32_t sIdx = 0; sIdx < submitCount; sIdx++) {
        VkFence fenceOrNil = (sIdx == (submitCount - 1)) ? fence : VK_NULL_HANDLE; // last one gets the fence
        VkResult subRslt = submit(new MVKQueueCommandBufferSubmission(this, &pSubmits[sIdx], fenceOrNil, cmdBuffUse));
        if (rslt == VK_SUCCESS) { rslt = subRslt; }
    }
    return rslt;
}

VkResult MVKQueue::submit(const VkPresentInfoKHR* pPresentInfo) {
	return submit(new MVKQueuePresentSurfaceSubmission(this, pPresentInfo));
}

// Create an empty submit struct and fence, submit to queue and wait on fence.
VkResult MVKQueue::waitIdle(MVKCommandUse cmdBuffUse) {

	VkFenceCreateInfo vkFenceInfo = {
		.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
		.pNext = nullptr,
		.flags = 0,
	};

	MVKFence mvkFence(_device, &vkFenceInfo);
	VkFence fence = (VkFence)&mvkFence;
	submit(0, nullptr, fence, cmdBuffUse);
	return mvkWaitForFences(_device, 1, &fence, false);
}


#pragma mark Construction

#define MVK_DISPATCH_QUEUE_QOS_CLASS		QOS_CLASS_USER_INITIATED

MVKQueue::MVKQueue(MVKDevice* device, MVKQueueFamily* queueFamily, uint32_t index, float priority)
        : MVKDeviceTrackingMixin(device) {

	_queueFamily = queueFamily;
	_index = index;
	_priority = priority;
	_nextMTLCmdBuffID = 1;

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
	if ( !_device->_pMVKConfig->synchronousQueueSubmits ) {
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
	const MVKConfiguration* pMVKConfig = getInstance()->getMoltenVKConfiguration();

	_submissionCaptureScope = new MVKGPUCaptureScope(this, "CommandBuffer-Submission");

	_presentationCaptureScope = new MVKGPUCaptureScope(this, "Surface-Presentation");
	if (_queueFamily->getIndex() == pMVKConfig->defaultGPUCaptureScopeQueueFamilyIndex &&
		_index == pMVKConfig->defaultGPUCaptureScopeQueueIndex) {
		_presentationCaptureScope->makeDefault();
	}
	_presentationCaptureScope->beginScope();	// Allow Xcode to capture the first frame if desired.
}

MVKQueue::~MVKQueue() {
	destroyExecQueue();
	_submissionCaptureScope->destroy();
	_presentationCaptureScope->destroy();
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
	_prev = VK_NULL_HANDLE;
	_next = VK_NULL_HANDLE;

	_isAwaitingSemaphores = waitSemaphoreCount > 0;
	_waitSemaphores.reserve(waitSemaphoreCount);
	for (uint32_t i = 0; i < waitSemaphoreCount; i++) {
		_waitSemaphores.push_back((MVKSemaphore*)pWaitSemaphores[i]);
	}
}


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmission

void MVKQueueCommandBufferSubmission::execute() {

//	MVKLogDebug("Executing submission %p.", this);

	_queue->_submissionCaptureScope->beginScope();

    // Submit each command buffer.
	for (auto& cb : _cmdBuffers) { cb->submit(this); }

	// If a fence or semaphores were provided, ensure that a MTLCommandBuffer
	// is available to trigger them, in case no command buffers were provided.
	if (_fence || !_signalSemaphores.empty()) { getActiveMTLCommandBuffer(); }

	// Commit the last MTLCommandBuffer.
	// Nothing after this because callback might destroy this instance before this function ends.
	commitActiveMTLCommandBuffer(true);
}

// Returns the active MTLCommandBuffer, lazily retrieving it from the queue if needed.
id<MTLCommandBuffer> MVKQueueCommandBufferSubmission::getActiveMTLCommandBuffer() {
	if ( !_activeMTLCommandBuffer ) {
		setActiveMTLCommandBuffer([_queue->_mtlQueue commandBufferWithUnretainedReferences]);
	}
	return _activeMTLCommandBuffer;
}

// Commits the current active MTLCommandBuffer, if it exists, and sets a new active MTLCommandBuffer.
void MVKQueueCommandBufferSubmission::setActiveMTLCommandBuffer(id<MTLCommandBuffer> mtlCmdBuff) {

	if (_activeMTLCommandBuffer) { commitActiveMTLCommandBuffer(); }

	_activeMTLCommandBuffer = mtlCmdBuff;	// not retained
	_activeMTLCommandBuffer.label = mvkMTLCommandBufferLabel(_cmdBuffUse);
	[_activeMTLCommandBuffer enqueue];
}

// Commits and releases the currently active MTLCommandBuffer, optionally signalling
// when the MTLCommandBuffer is done. The first time this is called, it will wait on
// any semaphores. We have delayed signalling the semaphores as long as possible to
// allow as much filling of the MTLCommandBuffer as possible before forcing a wait.
void MVKQueueCommandBufferSubmission::commitActiveMTLCommandBuffer(bool signalCompletion) {

	if (_isAwaitingSemaphores) {
		_isAwaitingSemaphores = false;
		for (auto& ws : _waitSemaphores) { ws->wait(); }
	}

	if (signalCompletion) {
		[_activeMTLCommandBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mtlCmdBuff) {
			this->finish();
		}];
	}

	// Use temp var because callback may destroy this instance before this function ends.
	id<MTLCommandBuffer> mtlCmdBuff = _activeMTLCommandBuffer;
	_activeMTLCommandBuffer = nil;			// not retained
	[mtlCmdBuff commit];
}

void MVKQueueCommandBufferSubmission::finish() {

//	MVKLogDebug("Finishing submission %p. Submission count %u.", this, _subCount--);

	// Performed here instead of as part of execute() for rare case where app destroys queue
	// immediately after a waitIdle() is cleared by fence below, taking the capture scope with it.
	_queue->_submissionCaptureScope->endScope();

	// Signal each of the signal semaphores.
    for (auto& ss : _signalSemaphores) { ss->signal(); }

	// If a fence exists, signal it.
	if (_fence) { _fence->signal(); }

    this->destroy();
}

MVKQueueCommandBufferSubmission::MVKQueueCommandBufferSubmission(MVKQueue* queue,
																 const VkSubmitInfo* pSubmit,
																 VkFence fence,
                                                                 MVKCommandUse cmdBuffUse)
        : MVKQueueSubmission(queue,
							 (pSubmit ? pSubmit->waitSemaphoreCount : 0),
							 (pSubmit ? pSubmit->pWaitSemaphores : nullptr)) {

    // pSubmit can be null if just tracking the fence alone
    if (pSubmit) {
        uint32_t cbCnt = pSubmit->commandBufferCount;
        _cmdBuffers.reserve(cbCnt);
        for (uint32_t i = 0; i < cbCnt; i++) {
            MVKCommandBuffer* cb = MVKCommandBuffer::getMVKCommandBuffer(pSubmit->pCommandBuffers[i]);
            _cmdBuffers.push_back(cb);
            setConfigurationResult(cb->getConfigurationResult());
        }

        uint32_t ssCnt = pSubmit->signalSemaphoreCount;
        _signalSemaphores.reserve(ssCnt);
        for (uint32_t i = 0; i < ssCnt; i++) {
            _signalSemaphores.push_back((MVKSemaphore*)pSubmit->pSignalSemaphores[i]);
        }
    }

	_fence = (MVKFence*)fence;
    _cmdBuffUse= cmdBuffUse;
	_activeMTLCommandBuffer = nil;

//	static std::atomic<uint32_t> _subCount;
//	MVKLogDebug("Creating submission %p. Submission count %u.", this, ++_subCount);
}


#pragma mark -
#pragma mark MVKQueuePresentSurfaceSubmission

void MVKQueuePresentSurfaceSubmission::execute() {
    id<MTLCommandQueue> mtlQ = _queue->getMTLCommandQueue();

	MVKDevice* mvkDev = _queue->getDevice();
	if (mvkDev->_pMVKConfig->presentWithCommandBuffer || mvkDev->_pMVKConfig->displayWatermark) {
		// Create a command buffer, present surfaces via the command buffer,
		// then wait on the semaphores before committing.
		id<MTLCommandBuffer> mtlCmdBuff = [mtlQ commandBufferWithUnretainedReferences];
		mtlCmdBuff.label = mvkMTLCommandBufferLabel(kMVKCommandUseQueuePresent);
		[mtlCmdBuff enqueue];

		for (auto& si : _surfaceImages) { si->presentCAMetalDrawable(mtlCmdBuff); }
		for (auto& ws : _waitSemaphores) { ws->wait(); }

		[mtlCmdBuff commit];
	} else {
		// Wait on semaphores, then present directly.
		for (auto& ws : _waitSemaphores) { ws->wait(); }
		for (auto& si : _surfaceImages) { si->presentCAMetalDrawable(nil); }
	}

    // Let Xcode know the current frame is done, then start a new frame
	auto cs = _queue->_presentationCaptureScope;
	cs->endScope();
	cs->beginScope();

    this->destroy();
}

MVKQueuePresentSurfaceSubmission::MVKQueuePresentSurfaceSubmission(MVKQueue* queue,
																   const VkPresentInfoKHR* pPresentInfo)
		: MVKQueueSubmission(queue, pPresentInfo->waitSemaphoreCount, pPresentInfo->pWaitSemaphores) {

	// Populate the array of swapchain images, testing each one for a change in surface size
	_surfaceImages.reserve(pPresentInfo->swapchainCount);
	for (uint32_t i = 0; i < pPresentInfo->swapchainCount; i++) {
		MVKSwapchain* mvkSC = (MVKSwapchain*)pPresentInfo->pSwapchains[i];
		_surfaceImages.push_back(mvkSC->getImage(pPresentInfo->pImageIndices[i]));
		// Surface loss takes precedence over out-of-date errors.
		if (mvkSC->getIsSurfaceLost()) {
			setConfigurationResult(VK_ERROR_SURFACE_LOST_KHR);
		} else if (mvkSC->getHasSurfaceSizeChanged() && getConfigurationResult() != VK_ERROR_SURFACE_LOST_KHR) {
			setConfigurationResult(VK_ERROR_OUT_OF_DATE_KHR);
		}
	}
}

