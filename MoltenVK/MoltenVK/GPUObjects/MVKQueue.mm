/*
 * MVKQueue.mm
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
		@autoreleasepool {		// Catch any autoreleased objects created during MTLCommandQueue creation
			uint32_t maxCmdBuffs = _physicalDevice->getInstance()->getMoltenVKConfiguration()->maxActiveMetalCommandBuffersPerQueue;
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

void MVKQueue::propogateDebugName() { setLabelIfNotNil(_mtlQueue, _debugName); }


#pragma mark Queue submissions

// Execute the queue submission under an autoreleasepool to ensure transient Metal objects are autoreleased.
// This is critical for apps that don't use standard OS autoreleasing runloop threading.
static inline void execute(MVKQueueSubmission* qSubmit) { @autoreleasepool { qSubmit->execute(); } }

// Executes the submmission, either immediately, or by dispatching to an execution queue.
// Submissions to the execution queue are wrapped in a dedicated autoreleasepool.
// Relying on the dispatch queue to find time to drain the autoreleasepool can
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

VkResult MVKQueue::submit(uint32_t submitCount, const VkSubmitInfo* pSubmits, VkFence fence) {

    // Fence-only submission
    if (submitCount == 0 && fence) {
        return submit(new MVKQueueCommandBufferSubmission(this, nullptr, fence));
    }

    VkResult rslt = VK_SUCCESS;
    for (uint32_t sIdx = 0; sIdx < submitCount; sIdx++) {
        VkFence fenceOrNil = (sIdx == (submitCount - 1)) ? fence : VK_NULL_HANDLE; // last one gets the fence
        VkResult subRslt = submit(new MVKQueueCommandBufferSubmission(this, &pSubmits[sIdx], fenceOrNil));
        if (rslt == VK_SUCCESS) { rslt = subRslt; }
    }
    return rslt;
}

VkResult MVKQueue::submit(const VkPresentInfoKHR* pPresentInfo) {
	return submit(new MVKQueuePresentSurfaceSubmission(this, pPresentInfo));
}

// Create an empty submit struct and fence, submit to queue and wait on fence.
VkResult MVKQueue::waitIdle() {

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
	_trackPerformance = _queue->_device->_pMVKConfig->performanceTracking;

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

	// If using encoded semaphore waiting, do so now.
	for (auto* ws : _waitSemaphores) { ws->encodeWait(getActiveMTLCommandBuffer()); }

	// Submit each command buffer.
	for (auto& cb : _cmdBuffers) { cb->submit(this); }

	// If using encoded semaphore signaling, do so now.
	for (auto* ss : _signalSemaphores) { ss->encodeSignal(getActiveMTLCommandBuffer()); }

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

	_activeMTLCommandBuffer = [mtlCmdBuff retain];		// retained to handle prefilled
	[_activeMTLCommandBuffer enqueue];
}

// Commits and releases the currently active MTLCommandBuffer, optionally signalling
// when the MTLCommandBuffer is done. The first time this is called, it will wait on
// any semaphores. We have delayed signalling the semaphores as long as possible to
// allow as much filling of the MTLCommandBuffer as possible before forcing a wait.
void MVKQueueCommandBufferSubmission::commitActiveMTLCommandBuffer(bool signalCompletion) {

	// If using inline semaphore waiting, do so now.
	for (auto& ws : _waitSemaphores) { ws->encodeWait(nil); }

	MVKDevice* mkvDev = _queue->_device;
	uint64_t startTime = mkvDev->getPerformanceTimestamp();

	// Use getActiveMTLCommandBuffer() to ensure at least one MTLCommandBuffer is used,
	// otherwise if this instance has no content, it will not finish() and be destroyed.
	if (signalCompletion || _trackPerformance) {
		[getActiveMTLCommandBuffer() addCompletedHandler: ^(id<MTLCommandBuffer> mtlCmdBuff) {
			mkvDev->addActivityPerformance(mkvDev->_performanceStatistics.queue.mtlCommandBufferCompletion, startTime);
			if (signalCompletion) { this->finish(); }
		}];
	}

	// Use temp var because callback may destroy this instance before this function ends.
	id<MTLCommandBuffer> mtlCmdBuff = _activeMTLCommandBuffer;
	_activeMTLCommandBuffer = nil;
	[mtlCmdBuff commit];
	[mtlCmdBuff release];		// retained
}

void MVKQueueCommandBufferSubmission::finish() {

//	MVKLogDebug("Finishing submission %p. Submission count %u.", this, _subCount--);

	// Performed here instead of as part of execute() for rare case where app destroys queue
	// immediately after a waitIdle() is cleared by fence below, taking the capture scope with it.
	_queue->_submissionCaptureScope->endScope();

	// If using inline semaphore signaling, do so now.
	for (auto& ss : _signalSemaphores) { ss->encodeSignal(nil); }

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
	for (auto& ws : _waitSemaphores) { ws->encodeWait(mtlCmdBuff); }
	for (int i = 0; i < _presentInfo.size(); i++ ) {
		MVKPresentableSwapchainImage *img = _presentInfo[i].presentableImage;
		img->presentCAMetalDrawable(mtlCmdBuff, _presentInfo[i].hasPresentTime, _presentInfo[i].presentID, _presentInfo[i].desiredPresentTime);
	}
	for (auto& ws : _waitSemaphores) { ws->encodeWait(nil); }
	[mtlCmdBuff commit];

	// Let Xcode know the current frame is done, then start a new frame
	auto cs = _queue->_presentationCaptureScope;
	cs->endScope();
	cs->beginScope();

	this->destroy();
}

id<MTLCommandBuffer> MVKQueuePresentSurfaceSubmission::getMTLCommandBuffer() {
	id<MTLCommandBuffer> mtlCmdBuff = [_queue->getMTLCommandQueue() commandBufferWithUnretainedReferences];
	setLabelIfNotNil(mtlCmdBuff, @"vkQueuePresentKHR CommandBuffer");
	[mtlCmdBuff enqueue];
	return mtlCmdBuff;
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
		PresentInfo presentInfo = {};
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

