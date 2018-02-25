/*
 * MVKQueue.mm
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

#include "MVKQueue.h"
#include "MVKSwapchain.h"
#include "MVKSync.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKLogging.h"

using namespace std;


#pragma mark -
#pragma mark MVKQueueFamily

MVKQueueFamily::MVKQueueFamily(MVKDevice* device,
							   const VkDeviceQueueCreateInfo* pCreateInfo,
							   const VkQueueFamilyProperties* pProperties) : MVKBaseDeviceObject(device) {
	_properties = *pProperties;

	// Create the queues
	uint32_t qCnt = pCreateInfo->queueCount;
	_queues.reserve(qCnt);
	for (uint32_t qIdx = 0; qIdx < qCnt; qIdx++) {
        _queues.push_back(new MVKQueue(_device, this, qIdx, pCreateInfo->pQueuePriorities[qIdx]));
	}
}

MVKQueueFamily::~MVKQueueFamily() {
	mvkDestroyContainerContents(_queues);
}


#pragma mark -
#pragma mark MVKQueue


#pragma mark Queue submissions

/** Submits the specified submission object to the execution queue. */
void MVKQueue::submit(MVKQueueSubmission* qSubmit) {
	if ( !qSubmit ) { return; }     // Ignore nils
	dispatch_async( _execQueue, ^{ qSubmit->execute(); } );
}

VkResult MVKQueue::submit(uint32_t submitCount, const VkSubmitInfo* pSubmits,
                          VkFence fence, MVKCommandUse cmdBuffUse) {
	VkResult rslt = VK_SUCCESS;
    for (uint32_t sIdx = 0; sIdx < submitCount; sIdx++) {
        VkFence fenceOrNil = (sIdx == (submitCount - 1)) ? fence : VK_NULL_HANDLE;	// last one gets the fence
        MVKQueueSubmission* qSub = new MVKQueueCommandBufferSubmission(_device, this, &pSubmits[sIdx], fenceOrNil, cmdBuffUse);
        if (rslt == VK_SUCCESS) { rslt = qSub->_submissionResult; }     // Extract result before submission to avoid race condition with early destruction
        submit(qSub);
    }

    // Support fence-only submission
    if (submitCount == 0 && fence) {
        MVKQueueSubmission* qSub = new MVKQueueCommandBufferSubmission(_device, this, VK_NULL_HANDLE, fence, cmdBuffUse);
        if (rslt == VK_SUCCESS) { rslt = qSub->_submissionResult; }     // Extract result before submission to avoid race condition with early destruction
        submit(qSub);
    }

    return rslt;
}

VkResult MVKQueue::submitPresentKHR(const VkPresentInfoKHR* pPresentInfo) {
	MVKQueueSubmission* qSub = new MVKQueuePresentSurfaceSubmission(_device, this, pPresentInfo);
    VkResult rslt = qSub->_submissionResult;     // Extract result before submission to avoid race condition with early destruction
	submit(qSub);
    return rslt;
}

VkResult MVKQueue::waitIdle(MVKCommandUse cmdBuffUse) {

	// Create submit struct including a temp Vulkan reference to a semaphore
	VkSemaphore vkSem4;
	VkSubmitInfo vkSbmtInfo = {
		.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
		.pNext = NULL,
		.waitSemaphoreCount = 0,
		.pWaitSemaphores = VK_NULL_HANDLE,
		.commandBufferCount = 0,
		.pCommandBuffers = VK_NULL_HANDLE,
		.signalSemaphoreCount = 1,
		.pSignalSemaphores = &vkSem4
	};

    VkSemaphoreCreateInfo vkSemInfo = {
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = NULL,
        .flags = 0,
    };

	MVKSemaphore mvkSem4(_device, &vkSemInfo);              // Construct MVKSemaphore
	vkSem4 = (VkSemaphore)&mvkSem4;                         // Set reference to MVKSemaphore in submit struct
	submit(1, &vkSbmtInfo, VK_NULL_HANDLE, cmdBuffUse);		// Submit semaphore queue
	mvkSem4.wait();                                         // Wait on the semaphore

	return VK_SUCCESS;
}

// This function is guarded against conflict with the mtlCommandBufferHasCompleted()
// function, but is not theadsafe against calls to this function itself, or to the
// registerMTLCommandBufferCountdown() function from multiple threads. It is assumed
// that this function and the registerMTLCommandBufferCountdown() function are called
// from a single thread.
id<MTLCommandBuffer> MVKQueue::makeMTLCommandBuffer(NSString* mtlCmdBuffLabel) {

	// Retrieve a MTLCommandBuffer from the MTLQueue.
	id<MTLCommandBuffer> mtlCmdBuffer = [_mtlQueue commandBufferWithUnretainedReferences];
    mtlCmdBuffer.label = mtlCmdBuffLabel;

	// Assign a unique ID to the MTLCommandBuffer, and track when it completes.
    MVKMTLCommandBufferID mtlCmdBuffID = _nextMTLCmdBuffID++;
	[mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mtlCmdBuff) {
		this->mtlCommandBufferHasCompleted(mtlCmdBuff, mtlCmdBuffID);
	}];

    // Keep a running count of the active MTLCommandBuffers.
    // This needs to be guarded against a race condition with a MTLCommandBuffer completing.
    lock_guard<mutex> lock(_completionLock);
	_activeMTLCommandBufferCount++;

	return mtlCmdBuffer;
}

// This function must be called after all corresponding calls to makeMTLCommandBuffer() and from the same thead.
void MVKQueue::registerMTLCommandBufferCountdown(MVKMTLCommandBufferCountdown* countdown) {
	lock_guard<mutex> lock(_completionLock);

	if ( !countdown->setActiveMTLCommandBufferCount(_activeMTLCommandBufferCount, _nextMTLCmdBuffID) ) {
		_completionCountdowns.push_back(countdown);
	}
}

void MVKQueue::mtlCommandBufferHasCompleted(id<MTLCommandBuffer> mtlCmdBuff, MVKMTLCommandBufferID mtlCmdBuffID) {
	lock_guard<mutex> lock(_completionLock);

	_activeMTLCommandBufferCount--;

	// Iterate through the countdowns, letting them know about the completion, and
	// remove any countdowns that have completed by eliding them out of the array.
	uint32_t ccCnt = (uint32_t)_completionCountdowns.size();
	uint32_t currCCIdx = 0;
	for (uint32_t ccIdx = 0; ccIdx < ccCnt; ccIdx++) {
		MVKMTLCommandBufferCountdown* mvkCD = _completionCountdowns[ccIdx];
		if ( !mvkCD->mtlCommandBufferHasCompleted(mtlCmdBuffID) ) {
			// Only retain the countdown if it has not just completed.
			// Move it forward in the array if any preceding countdowns have been removed.
			if (currCCIdx != ccIdx) { _completionCountdowns[currCCIdx] = mvkCD; }
			currCCIdx++;
		}
	}
	// If any countdowns were removed, clear out the extras at the end
	if (currCCIdx < ccCnt) { _completionCountdowns.resize(currCCIdx); }
}


#pragma mark Construction

#define MVK_DISPATCH_QUEUE_QOS_CLASS		QOS_CLASS_USER_INITIATED

MVKQueue::MVKQueue(MVKDevice* device, MVKQueueFamily* queueFamily, uint32_t index, float priority)
        : MVKDispatchableDeviceObject(device), _commandEncodingPool(device) {

	_queueFamily = queueFamily;
	_index = index;
	_priority = priority;
	initExecQueue();
	initMTLCommandQueue();
	_activeMTLCommandBufferCount = 0;
	_nextMTLCmdBuffID = 1;
}

/** Creates and initializes the execution dispatch queue. */
void MVKQueue::initExecQueue() {

	// Create a name for the dispatch queue
	const char* dqNameFmt = "MoltenVKDispatchQueue-%d-%d-%.1f";
	char dqName[strlen(dqNameFmt) + 32];
	sprintf(dqName, dqNameFmt, _queueFamily->getIndex(), _index, _priority);

	// Determine the dispatch queue priority
	dispatch_qos_class_t dqQOS = MVK_DISPATCH_QUEUE_QOS_CLASS;
	int dqPriority = (1.0 - _priority) * QOS_MIN_RELATIVE_PRIORITY;
	dispatch_queue_attr_t dqAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, dqQOS, dqPriority);

	// Create the dispatch queue
	_execQueue = dispatch_queue_create(dqName, dqAttr);		// retained
}

/** Creates and initializes the Metal queue. */
void MVKQueue::initMTLCommandQueue() {
	_mtlQueue = [_device->getMTLDevice() newCommandQueue];	// retained
    [_mtlQueue insertDebugCaptureBoundary];                 // Allow Xcode to capture the first frame if desired.
}

MVKQueue::~MVKQueue() {
    // Delay destroying this queue until registerMTLCommandBufferCountdown() is done.
    // registerMTLCommandBufferCountdown() can trigger a queue submission to finish(),
    // which may trigger semaphores that control a queue waitIdle(). If that waitIdle()
    // is being called by the app just prior to device and queue destruction, a rare race
    // condition exists if registerMTLCommandBufferCountdown() does not complete before
    // this queue is destroyed. If _completionLock is destroyed along with this queue,
    // before registerMTLCommandBufferCountdown() completes, a SIGABRT crash will arise
    // in the destructor of the lock created in registerMTLCommandBufferCountdown().
    lock_guard<mutex> lock(_completionLock);
	destroyExecQueue();
	[_mtlQueue release];
}

/** Destroys the execution dispatch queue. */
void MVKQueue::destroyExecQueue() {
	dispatch_release(_execQueue);
}


#pragma mark -
#pragma mark MVKQueueSubmission

MVKQueueSubmission::MVKQueueSubmission(MVKDevice* device, MVKQueue* queue) : MVKBaseDeviceObject(device) {
	_queue = queue;
	_prev = VK_NULL_HANDLE;
	_next = VK_NULL_HANDLE;
	_submissionResult = VK_SUCCESS;
}

void MVKQueueSubmission::recordResult(VkResult vkResult) {
    if (_submissionResult == VK_SUCCESS) { _submissionResult = vkResult; }
}


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmissionCountdown

MVKQueueCommandBufferSubmissionCountdown::MVKQueueCommandBufferSubmissionCountdown(MVKQueueCommandBufferSubmission* qSub) {
	_qSub = qSub;
}

void MVKQueueCommandBufferSubmissionCountdown::finish() { _qSub->finish(); }


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmission

void MVKQueueCommandBufferSubmission::execute() {

    // Wait on each wait semaphore in turn. It doesn't matter which order they are signalled.
    for (auto& ws : _waitSemaphores) { ws->wait(); }

    // Execute each command buffer, or if no command buffers, but a fence or semaphores,
    // create an empty MTLCommandBuffer to trigger the semaphores and fence.
    if ( !_cmdBuffers.empty() ) {
		MVKCommandBufferBatchPosition cmdBuffPos = {1, uint32_t(_cmdBuffers.size()), _cmdBuffUse};
		for (auto& cb : _cmdBuffers) {
			cb->execute(this, cmdBuffPos);
			cmdBuffPos.index++;
		}
    } else {
		if (_fence || !_signalSemaphores.empty() ) {
			getActiveMTLCommandBuffer();
		}
    }

	commitActiveMTLCommandBuffer();

    // Register for callback when MTLCommandBuffers have completed
    _queue->registerMTLCommandBufferCountdown(&_cmdBuffCountdown);
}

id<MTLCommandBuffer> MVKQueueCommandBufferSubmission::getActiveMTLCommandBuffer() {
	if ( !_activeMTLCommandBuffer ) {
		_activeMTLCommandBuffer = _queue->makeMTLCommandBuffer(getMTLCommandBufferName());
		[_activeMTLCommandBuffer enqueue];
	}
	return _activeMTLCommandBuffer;
}

void MVKQueueCommandBufferSubmission::commitActiveMTLCommandBuffer() {
	[_activeMTLCommandBuffer commit];
	_activeMTLCommandBuffer = nil;			// not retained
}

// Returns an NSString suitable for use as a label
NSString* MVKQueueCommandBufferSubmission::getMTLCommandBufferName() {
    switch (_cmdBuffUse) {
        case kMVKCommandUseQueueSubmit:
            return [NSString stringWithFormat: @"%@ (virtual for sync)", mvkMTLCommandBufferLabel(_cmdBuffUse)];
        default:
            return mvkMTLCommandBufferLabel(_cmdBuffUse);
    }
}

void MVKQueueCommandBufferSubmission::finish() {

	// Signal each of the signal semaphores.
    for (auto& ss : _signalSemaphores) { ss->signal(); }

    // If a fence exists, signal it.
    if (_fence) { _fence->signal(); }
    
    delete this;
}

MVKQueueCommandBufferSubmission::MVKQueueCommandBufferSubmission(MVKDevice* device,
																 MVKQueue* queue,
																 const VkSubmitInfo* pSubmit,
                                                                 VkFence fence,
                                                                 MVKCommandUse cmdBuffUse)
        : MVKQueueSubmission(device, queue), _cmdBuffCountdown(this) {

    // pSubmit can be null if just tracking the fence alone
    if (pSubmit) {
        uint32_t cbCnt = pSubmit->commandBufferCount;
        _cmdBuffers.reserve(cbCnt);
        for (uint32_t i = 0; i < cbCnt; i++) {
            MVKCommandBuffer* cb = MVKCommandBuffer::getMVKCommandBuffer(pSubmit->pCommandBuffers[i]);
            _cmdBuffers.push_back(cb);
            recordResult(cb->getRecordingResult());
        }

        uint32_t wsCnt = pSubmit->waitSemaphoreCount;
        _waitSemaphores.reserve(wsCnt);
        for (uint32_t i = 0; i < wsCnt; i++) {
            _waitSemaphores.push_back((MVKSemaphore*)pSubmit->pWaitSemaphores[i]);
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
}


#pragma mark -
#pragma mark MVKQueuePresentSurfaceSubmission

#define MVK_PRESENT_VIA_CMD_BUFFER		0

void MVKQueuePresentSurfaceSubmission::execute() {

    // Wait on each of the wait semaphores in turn. It doesn't matter which order they are signalled.
    for (auto& ws : _waitSemaphores) { ws->wait(); }

    id<MTLCommandQueue> mtlQ = _queue->getMTLCommandQueue();
	id<MTLCommandBuffer> mtlCmdBuff = nil;

	if (_device->_mvkConfig.displayWatermark || MVK_PRESENT_VIA_CMD_BUFFER) {
		mtlCmdBuff = [mtlQ commandBufferWithUnretainedReferences];
		mtlCmdBuff.label = mvkMTLCommandBufferLabel(kMVKCommandUseQueuePresent);
	}

    for (auto& si : _surfaceImages) { si->presentCAMetalDrawable(mtlCmdBuff); }

	[mtlCmdBuff commit];

    // Let Xcode know the frame is done, in case command buffer is not used
    if (_device->_mvkConfig.debugMode) { [mtlQ insertDebugCaptureBoundary]; }

    delete this;
}

MVKQueuePresentSurfaceSubmission::MVKQueuePresentSurfaceSubmission(MVKDevice* device,
																   MVKQueue* queue,
																   const VkPresentInfoKHR* pPresentInfo) : MVKQueueSubmission(device, queue) {
	uint32_t wsCnt = pPresentInfo->waitSemaphoreCount;
	_waitSemaphores.reserve(wsCnt);
	for (uint32_t i = 0; i < wsCnt; i++) {
		_waitSemaphores.push_back((MVKSemaphore*)pPresentInfo->pWaitSemaphores[i]);
	}

	// Populate the array of swapchain images, testing each one for a change in surface size
	_surfaceImages.reserve(pPresentInfo->swapchainCount);
	for (uint32_t i = 0; i < pPresentInfo->swapchainCount; i++) {
		MVKSwapchain* mvkSC = (MVKSwapchain*)pPresentInfo->pSwapchains[i];
		_surfaceImages.push_back(mvkSC->getImage(pPresentInfo->pImageIndices[i]));
		if (mvkSC->getHasSurfaceSizeChanged()) {
			_submissionResult = VK_SUBOPTIMAL_KHR;
		}
	}
}

