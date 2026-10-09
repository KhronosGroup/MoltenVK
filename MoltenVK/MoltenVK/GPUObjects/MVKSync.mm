/*
 * MVKSync.mm
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

#include "MVKSync.h"
#include "MVKFoundation.h"
#include <chrono>

using namespace std;


#pragma mark -
#pragma mark MVKSemaphoreImpl

bool MVKSemaphoreImpl::release() {
	lock_guard<mutex> lock(_lock);
    if (_cancelled || isClear()) { return true; }

    // Either decrement the reservation counter, or clear it altogether
    if (_shouldWaitAll) {
		if (_reservationCount > 0) { _reservationCount--; }
    } else {
        _reservationCount = 0;
    }
    // If all reservations have been released, unblock all waiting threads
    if ( isClear() ) { _blocker.notify_all(); }
    return isClear();
}

void MVKSemaphoreImpl::cancel() {
	lock_guard<mutex> lock(_lock);
	_cancelled = true;
	_reservationCount = 0;
	_blocker.notify_all();
}

void MVKSemaphoreImpl::reserve() {
	lock_guard<mutex> lock(_lock);
	if (!_cancelled) { _reservationCount++; }
}

bool MVKSemaphoreImpl::isReserved() {
	lock_guard<mutex> lock(_lock);
	return !isClear();
}

uint32_t MVKSemaphoreImpl::getReservationCount() {
	lock_guard<mutex> lock(_lock);
	return _reservationCount;
}

bool MVKSemaphoreImpl::wait(uint64_t timeout, bool reserveAgain) {
    unique_lock<mutex> lock(_lock);

    bool isDone;
    if (timeout == 0) {
		isDone = isClear();
	} else if (timeout == UINT64_MAX) {
		_blocker.wait(lock, [this]{ return isClear(); });
		isDone = true;
	} else {
        // Limit timeout to avoid overflow since wait_for() uses wait_until()
        uint64_t nanoTimeout = min(timeout, kMVKUndefinedLargeUInt64);
        chrono::nanoseconds nanos(nanoTimeout);
        isDone = _blocker.wait_for(lock, nanos, [this]{ return isClear(); });
    }

	if (reserveAgain && !_cancelled) { _reservationCount++; }
    return isDone;
}

MVKSemaphoreImpl::~MVKSemaphoreImpl() {
    // Acquire the lock to ensure proper ordering.
    lock_guard<mutex> lock(_lock);
}


#pragma mark -
#pragma mark MVKSemaphoreSingleQueue

void MVKSemaphoreSingleQueue::encodeWait(id<MTLCommandBuffer> mtlCmdBuff, uint64_t) {
	// Metal will handle all synchronization for us automatically
}

void MVKSemaphoreSingleQueue::encodeSignal(id<MTLCommandBuffer> mtlCmdBuff, uint64_t) {
	// Metal will handle all synchronization for us automatically
}

uint64_t MVKSemaphoreSingleQueue::deferSignal() {
	return 0;
}

void MVKSemaphoreSingleQueue::encodeDeferredSignal(id<MTLCommandBuffer> mtlCmdBuff, uint64_t) {
	encodeSignal(mtlCmdBuff, 0);
}

MVKSemaphoreSingleQueue::MVKSemaphoreSingleQueue(MVKDevice* device,
                                                 const VkSemaphoreCreateInfo* pCreateInfo,
                                                 const VkExportMetalObjectCreateInfoEXT* pExportInfo,
                                                 const VkImportMetalSharedEventInfoEXT* pImportInfo) : MVKSemaphore(device, pCreateInfo) {
	if ((pImportInfo && pImportInfo->mtlSharedEvent) || (pExportInfo && pExportInfo->exportObjectType == VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT)) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateEvent(): MTLSharedEvent is not available with VkSemaphores that use implicit synchronization."));
	}
}

MVKSemaphoreSingleQueue::~MVKSemaphoreSingleQueue() = default;


#pragma mark -
#pragma mark MVKSemaphoreMTLEvent

void MVKSemaphoreMTLEvent::encodeWait(id<MTLCommandBuffer> mtlCmdBuff, uint64_t) {
	if (mtlCmdBuff) { encodeReservedWait(mtlCmdBuff, _mtlEventValue++); }
}

uint64_t MVKSemaphoreMTLEvent::reserveWait() {
	return _mtlEventValue++;
}

void MVKSemaphoreMTLEvent::encodeReservedWait(id<MTLCommandBuffer> mtlCmdBuff, uint64_t reservation) {
	if ( !mtlCmdBuff ) { return; }
	uint64_t maxValue = _maxEncodedWaitValue.load();
	while (maxValue < reservation && !_maxEncodedWaitValue.compare_exchange_weak(maxValue, reservation)) {}
	if ( !_isLossReleased.exchange(true) ) { _device->addLossReleasable(this); }
	[mtlCmdBuff encodeWaitForEvent: _mtlEvent value: reservation];
}

// Releases the highest wait encoded so far, which covers every lower one since Metal event values never decrease.
// Not the next value: that is the generation of the next Vulkan signal, which an external Metal client of an
// imported or exported event may be waiting for. A wait reserved but not yet encoded is released by the next call.
bool MVKSemaphoreMTLEvent::releaseWaitsAfterLoss(id<MTLCommandBuffer> mtlCmdBuff) {
	uint64_t value = _maxEncodedWaitValue.load();
	if ( !value ) { return true; }
	if (mtlCmdBuff) {
		[mtlCmdBuff encodeSignalEvent: _mtlEvent value: value];
	} else if (_mtlEvent.signaledValue < value) {
		_mtlEvent.signaledValue = value;
	}
	return true;
}

// Queue submissions signal through encodeSubmissionSignal(), and swapchains through deferSignal().
void MVKSemaphoreMTLEvent::encodeSignal(id<MTLCommandBuffer> mtlCmdBuff, uint64_t) {
	if (mtlCmdBuff) { [mtlCmdBuff encodeSignalEvent: _mtlEvent value: _mtlEventValue]; }
}

// A binary semaphore pairs each wait with the signal that executes before it, which is not always the one submitted
// first: a signal submitted earlier on another queue may wait for work that a later signal releases (B/A/C/D in
// MoltenVK/Tests/PerVertexBinarySemaphoreOrderTests.mm). Waits take their value in submission order. A signal takes
// the value after the one its semaphore holds when it executes. It is encoded in Metal only while no other signal of
// this semaphore is pending, so that none can execute before it; that one may still be preempted by a later signal,
// see completeSubmissionSignal(). Any other signal sets the value from the host once its submission completes, after
// its work and before its fence. An imported event may be signalled outside Vulkan: its signals always wait for
// completion. A swapchain signal (deferSignal()) cannot overlap them, because acquisition requires a semaphore with
// no pending operation; its value is accounted for all the same.
uint64_t MVKSemaphoreMTLEvent::encodeSubmissionSignal(id<MTLCommandBuffer> mtlCmdBuff, uint64_t) {
	lock_guard<mutex> lock(_signalLock);
	if (_pendingSubmissionSignals++ || _isImported || !mtlCmdBuff) { return 0; }
	_metalSignalValue = std::max(_mtlEvent.signaledValue, _lastDeferredSignalValue) + 1;
	_isMetalSignalPreempted = false;
	[mtlCmdBuff encodeSignalEvent: _mtlEvent value: _metalSignalValue];
	return _metalSignalValue;
}

// The signal encoded in Metal is complete unless a signal set from the host took its value first: its own Metal
// signal did nothing, and it then takes the next value like any other signal. That other signal had executed before
// it, as a binary semaphore must be unsignaled when a signal executes.
void MVKSemaphoreMTLEvent::completeSubmissionSignal(uint64_t token) {
	lock_guard<mutex> lock(_signalLock);
	_pendingSubmissionSignals--;
	if (token) {
		_metalSignalValue = 0;
		if ( !_isMetalSignalPreempted ) { return; }
	}
	uint64_t value = _mtlEvent.signaledValue + 1;
	if (value == _metalSignalValue) { _isMetalSignalPreempted = true; }
	_mtlEvent.signaledValue = value;
}

uint64_t MVKSemaphoreMTLEvent::deferSignal() {
	lock_guard<mutex> lock(_signalLock);
	_lastDeferredSignalValue = _mtlEventValue;
	return _mtlEventValue;
}

void MVKSemaphoreMTLEvent::encodeDeferredSignal(id<MTLCommandBuffer> mtlCmdBuff, uint64_t deferToken) {
	[mtlCmdBuff encodeSignalEvent: _mtlEvent value: deferToken];
}

MVKSemaphoreMTLEvent::MVKSemaphoreMTLEvent(MVKDevice* device,
										   const VkSemaphoreCreateInfo* pCreateInfo,
										   const VkExportMetalObjectCreateInfoEXT* pExportInfo,
										   const VkImportMetalSharedEventInfoEXT* pImportInfo) : MVKSemaphore(device, pCreateInfo) {
	// Import a MTLSharedEvent, or create one: signals set from the host need a shared event.
	_isImported = pImportInfo && pImportInfo->mtlSharedEvent;
	_mtlEvent = _isImported ? [pImportInfo->mtlSharedEvent retain] : [getMTLDevice() newSharedEvent];	// retained
	_mtlEventValue = _mtlEvent.signaledValue + 1;
}

MVKSemaphoreMTLEvent::~MVKSemaphoreMTLEvent() {
	if (_isLossReleased) { _device->removeLossReleasable(this); }
    [_mtlEvent release];
}


#pragma mark -
#pragma mark MVKSemaphoreEmulated

void MVKSemaphoreEmulated::encodeWait(id<MTLCommandBuffer> mtlCmdBuff, uint64_t) {
	// Only queue submissions wait here, while encoding: a device loss cancels this wait at once.
	if ( !mtlCmdBuff ) {
		_device->addEncodingSemaphore(&_blocker);
		_blocker.wait(UINT64_MAX, true);
		_device->removeEncodingSemaphore(&_blocker);
	}
}

void MVKSemaphoreEmulated::encodeSignal(id<MTLCommandBuffer> mtlCmdBuff, uint64_t) {
	if ( !mtlCmdBuff ) { _blocker.release(); }
}

uint64_t MVKSemaphoreEmulated::deferSignal() {
	return 0;
}

void MVKSemaphoreEmulated::encodeDeferredSignal(id<MTLCommandBuffer> mtlCmdBuff, uint64_t) {
	encodeSignal(mtlCmdBuff, 0);
}

MVKSemaphoreEmulated::MVKSemaphoreEmulated(MVKDevice* device,
										   const VkSemaphoreCreateInfo* pCreateInfo,
										   const VkExportMetalObjectCreateInfoEXT* pExportInfo,
										   const VkImportMetalSharedEventInfoEXT* pImportInfo) :
	MVKSemaphore(device, pCreateInfo),
	_blocker(false, 1) {

	if ((pImportInfo && pImportInfo->mtlSharedEvent) || (pExportInfo && pExportInfo->exportObjectType == VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT)) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateEvent(): MTLSharedEvent is not available with VkSemaphores that use CPU emulation."));
	}
}


#pragma mark -
#pragma mark MVKTimelineSemaphoreMTLEvent

// Nil mtlCmdBuff will do nothing.
void MVKTimelineSemaphoreMTLEvent::encodeWait(id<MTLCommandBuffer> mtlCmdBuff, uint64_t value) {
	if ( !mtlCmdBuff ) { return; }
	uint64_t maxValue = _maxEncodedWaitValue.load();
	while (maxValue < value && !_maxEncodedWaitValue.compare_exchange_weak(maxValue, value)) {}
	if ( !_isLossReleased.exchange(true) ) { _device->addLossReleasable(this); }
	[mtlCmdBuff encodeWaitForEvent: _mtlEvent value: value];
}

// Metal event values never decrease, so a value already reached is unaffected.
bool MVKTimelineSemaphoreMTLEvent::releaseWaitsAfterLoss(id<MTLCommandBuffer> mtlCmdBuff) {
	uint64_t value = _maxEncodedWaitValue.load();
	if ( !value ) { return true; }
	if (mtlCmdBuff) {
		[mtlCmdBuff encodeSignalEvent: _mtlEvent value: value];
	} else if (_mtlEvent.signaledValue < value) {
		_mtlEvent.signaledValue = value;
	}
	return true;
}

// Nil mtlCmdBuff will do nothing.
void MVKTimelineSemaphoreMTLEvent::encodeSignal(id<MTLCommandBuffer> mtlCmdBuff, uint64_t value) {
	[mtlCmdBuff encodeSignalEvent: _mtlEvent value: value];
}

void MVKTimelineSemaphoreMTLEvent::signal(const VkSemaphoreSignalInfo* pSignalInfo) {
	_mtlEvent.signaledValue = pSignalInfo->value;
}

bool MVKTimelineSemaphoreMTLEvent::registerWait(MVKFenceSitter* sitter, const VkSemaphoreWaitInfo* pWaitInfo, uint32_t index) {
	if (_mtlEvent.signaledValue >= pWaitInfo->pValues[index]) { return true; }
	lock_guard<mutex> lock(_lock);
	sitter->await();
	auto addRslt = _sitters.emplace(sitter, nullptr);
	if (addRslt.second) {
		// Metal may run the listener after this wait has ended, or never. It holds only a token, which the wait detaches
		// when it ends, never the waiter or this semaphore: the waiter's address may be that of a later wait by then.
		auto token = std::make_shared<MVKTimelineWaitToken>();
		token->sitter = sitter;
		addRslt.first->second = token;
		_device->addSemaphore(&sitter->_blocker);
		[_mtlEvent notifyListener: sitter->getMTLSharedEventListener()
						  atValue: pWaitInfo->pValues[index]
							block: ^(id<MTLSharedEvent>, uint64_t) {
			lock_guard<mutex> tokenLock(token->lock);
			if (token->sitter) { token->sitter->signaled(); }
		}];
	}
	return false;
}

void MVKTimelineSemaphoreMTLEvent::unregisterWait(MVKFenceSitter* sitter) {
	lock_guard<mutex> lock(_lock);
	_device->removeSemaphore(&sitter->_blocker);
	auto found = _sitters.find(sitter);
	if (found == _sitters.end()) { return; }
	auto token = found->second;
	_sitters.erase(found);
	lock_guard<mutex> tokenLock(token->lock);
	token->sitter = nullptr;
}

MVKTimelineSemaphoreMTLEvent::MVKTimelineSemaphoreMTLEvent(MVKDevice* device,
														   const VkSemaphoreCreateInfo* pCreateInfo,
														   const VkSemaphoreTypeCreateInfo* pTypeCreateInfo,
														   const VkExportMetalObjectCreateInfoEXT* pExportInfo,
														   const VkImportMetalSharedEventInfoEXT* pImportInfo) : MVKTimelineSemaphore(device, pCreateInfo) {

	// Import or create a Metal event
	_mtlEvent = (pImportInfo && pImportInfo->mtlSharedEvent
				 ? [pImportInfo->mtlSharedEvent retain]
				 : [getMTLDevice() newSharedEvent]);	//retained

	if (pTypeCreateInfo) {
		_mtlEvent.signaledValue = pTypeCreateInfo->initialValue;
	}
}

MVKTimelineSemaphoreMTLEvent::~MVKTimelineSemaphoreMTLEvent() {
	if (_isLossReleased) { _device->removeLossReleasable(this); }
    [_mtlEvent release];
}


#pragma mark -
#pragma mark MVKFence

void MVKFence::addSitter(MVKFenceSitter* fenceSitter) {
	lock_guard<mutex> lock(_lock);

	// We only care about unsignaled fences. If already signaled,
	// don't add myself to the sitter and don't signal the sitter.
	if (_isSignaled) { return; }

	// Ensure each fence only added once to each fence sitter
	auto addRslt = _fenceSitters.insert(fenceSitter);	// pair with second element true if was added
	if (addRslt.second) {
		_device->addSemaphore(&fenceSitter->_blocker);
		fenceSitter->await();
	}
}

void MVKFence::removeSitter(MVKFenceSitter* fenceSitter) {
	lock_guard<mutex> lock(_lock);

	_device->removeSemaphore(&fenceSitter->_blocker);
	_fenceSitters.erase(fenceSitter);
}

void MVKFence::signal() {
	lock_guard<mutex> lock(_lock);

	if (_isSignaled) { return; }	// Only signal once
	_isSignaled = true;

	// Notify all the fence sitters, and clear them from this instance.
    for (auto& fs : _fenceSitters) {
        fs->signaled();
    }
	_fenceSitters.clear();
}

void MVKFence::reset() {
	lock_guard<mutex> lock(_lock);

	_isSignaled = false;
	_fenceSitters.clear();
}

bool MVKFence::getIsSignaled() {
	lock_guard<mutex> lock(_lock);

	return _isSignaled;
}


#pragma mark -
#pragma mark MVKFenceSitter

MTLSharedEventListener* MVKFenceSitter::getMTLSharedEventListener() {
	// TODO: Use dispatch queue from device?
	if (!_listener) { _listener = [MTLSharedEventListener new]; }
	return _listener;
}


#pragma mark -
#pragma mark MVKEventNative

// Odd == set / Even == reset.
bool MVKEventNative::isSet() { return _mtlEvent.signaledValue & 1; }

void MVKEventNative::signal(bool status) {
	if (isSet() != status) {
		_mtlEvent.signaledValue += 1;
	}
}

void MVKEventNative::encodeSignal(id<MTLCommandBuffer> mtlCmdBuff, bool status) {
	if (isSet() != status) {
		[mtlCmdBuff encodeSignalEvent: _mtlEvent value: _mtlEvent.signaledValue + 1];
	}
}

void MVKEventNative::encodeWait(id<MTLCommandBuffer> mtlCmdBuff) {
	if ( !isSet() ) {
		uint64_t value = _mtlEvent.signaledValue + 1;
		uint64_t maxValue = _maxEncodedWaitValue.load();
		while (maxValue < value && !_maxEncodedWaitValue.compare_exchange_weak(maxValue, value)) {}
		if ( !_isLossReleased.exchange(true) ) { _device->addLossReleasable(this); }
		[mtlCmdBuff encodeWaitForEvent: _mtlEvent value: value];
	}
}

// Like MVKSemaphoreMTLEvent: sets the event to the highest wait encoded so far, never beyond it, since an external
// Metal client of an imported or exported event may wait for a later value.
bool MVKEventNative::releaseWaitsAfterLoss(id<MTLCommandBuffer> mtlCmdBuff) {
	uint64_t value = _maxEncodedWaitValue.load();
	if ( !value ) { return true; }
	if (mtlCmdBuff) {
		[mtlCmdBuff encodeSignalEvent: _mtlEvent value: value];
	} else if (_mtlEvent.signaledValue < value) {
		_mtlEvent.signaledValue = value;
	}
	return true;
}

MVKEventNative::MVKEventNative(MVKDevice* device,
							   const VkEventCreateInfo* pCreateInfo,
							   const VkExportMetalObjectCreateInfoEXT* pExportInfo,
							   const VkImportMetalSharedEventInfoEXT* pImportInfo) :
	MVKEvent(device, pCreateInfo, pExportInfo, pImportInfo) {

	// Import or create a Metal event
	_mtlEvent = (pImportInfo
				 ? [pImportInfo->mtlSharedEvent retain]
				 : [getMTLDevice() newSharedEvent]);	//retained
}

MVKEventNative::~MVKEventNative() {
	if (_isLossReleased) { _device->removeLossReleasable(this); }
	[_mtlEvent release];
}


#pragma mark -
#pragma mark Support functions

// Returns what remains of a host wait timeout in nanoseconds, UINT64_MAX meaning infinite.
static uint64_t mvkRemainingTimeout(chrono::steady_clock::time_point startTime, uint64_t timeout) {
	if (timeout == UINT64_MAX) { return UINT64_MAX; }
	uint64_t elapsed = chrono::duration_cast<chrono::nanoseconds>(chrono::steady_clock::now() - startTime).count();
	return elapsed < timeout ? timeout - elapsed : 0;
}

VkResult mvkResetFences(uint32_t fenceCount, const VkFence* pFences) {
	for (uint32_t i = 0; i < fenceCount; i++) {
		((MVKFence*)pFences[i])->reset();
	}
	return VK_SUCCESS;
}

// Create a blocking fence sitter, add it to each fence, wait, then remove it.
VkResult mvkWaitForFences(MVKDevice* device,
						  uint32_t fenceCount,
						  const VkFence* pFences,
						  VkBool32 waitAll,
						  uint64_t timeout) {

	if (device->getConfigurationResult() != VK_SUCCESS) {
		return device->getConfigurationResult();
	}

	auto startTime = chrono::steady_clock::now();
	MVKFenceSitter fenceSitter(waitAll);

	for (uint32_t i = 0; i < fenceCount; i++) {
		((MVKFence*)pFences[i])->addSitter(&fenceSitter);
	}

	bool finished = fenceSitter.wait(timeout);
	VkResult rslt = device->getHostWaitResult(finished, mvkRemainingTimeout(startTime, timeout));

	for (uint32_t i = 0; i < fenceCount; i++) {
		((MVKFence*)pFences[i])->removeSitter(&fenceSitter);
	}

	return rslt;
}

// Create a blocking fence sitter, add it to each semaphore, wait, then remove it.
VkResult mvkWaitSemaphores(MVKDevice* device,
						   const VkSemaphoreWaitInfo* pWaitInfo,
						   uint64_t timeout) {

	if (device->getConfigurationResult() != VK_SUCCESS) {
		return device->getConfigurationResult();
	}

	auto startTime = chrono::steady_clock::now();
	bool waitAny = mvkIsAnyFlagEnabled(pWaitInfo->flags, VK_SEMAPHORE_WAIT_ANY_BIT);
	bool alreadySignaled = false;
	MVKFenceSitter fenceSitter(!waitAny);

	for (uint32_t i = 0; i < pWaitInfo->semaphoreCount; i++) {
		if (((MVKTimelineSemaphore*)pWaitInfo->pSemaphores[i])->registerWait(&fenceSitter, pWaitInfo, i) && waitAny) {
			// In this case, we don't need to wait.
			alreadySignaled = true;
			break;
		}
	}

	bool finished = alreadySignaled || fenceSitter.wait(timeout);
	VkResult rslt = device->getHostWaitResult(finished, mvkRemainingTimeout(startTime, timeout));

	for (uint32_t i = 0; i < pWaitInfo->semaphoreCount; i++) {
		((MVKTimelineSemaphore*)pWaitInfo->pSemaphores[i])->unregisterWait(&fenceSitter);
	}

	return rslt;
}


#pragma mark -
#pragma mark MVKMetalCompiler

// Create a compiled object by dispatching the block to the default global dispatch queue, and waiting only as long
// as the MVKConfiguration::metalCompileTimeout value. If the timeout is triggered, a Vulkan error is created.
// This approach is used to limit the lengthy time (30+ seconds!) consumed by Metal when it's internal compiler fails.
// The thread dispatch is needed because even the sync portion of the async Metal compilation methods can take well
// over a second to return when a compiler failure occurs!
void MVKMetalCompiler::compile(unique_lock<mutex>& lock, dispatch_block_t block) {
	MVKAssert( _startTime == 0, "%s compile occurred already in this instance. Instances of %s should only be used for a single compile activity.", _compilerType.c_str(), getClassName().c_str());

	_startTime = getPerformanceTimestamp();

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ @autoreleasepool { block(); } });

	// Limit timeout to avoid overflow since wait_for() uses wait_until()
	chrono::nanoseconds nanoTimeout(min(getMVKConfig().metalCompileTimeout, kMVKUndefinedLargeUInt64));
	_blocker.wait_for(lock, nanoTimeout, [this]{ return _isCompileDone; });

	if ( !_isCompileDone ) {
		@autoreleasepool {
			NSString* errDesc = [NSString stringWithFormat: @"Timeout after %.3f milliseconds. Likely internal Metal compiler error", (double)nanoTimeout.count() / 1e6];
			_compileError = [[NSError alloc] initWithDomain: @(kMVKMoltenVKDriverLayerName) code: 1 userInfo: @{NSLocalizedDescriptionKey : errDesc}];	// retained
		}
	}

	if (_compileError) { handleError(); }

	addPerformanceInterval(*_pPerformanceTracker, _startTime);
}

void MVKMetalCompiler::handleError() {
	_owner->setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED,
											   "%s compile failed (Error code %li):\n%s.",
											   _compilerType.c_str(), (long)_compileError.code,
											   _compileError.localizedDescription.UTF8String));
}

// Returns whether the compilation came in late, after the compiler was destroyed.
bool MVKMetalCompiler::endCompile(NSError* compileError) {
	_compileError = [compileError retain];		// retained
	_isCompileDone = true;
	_blocker.notify_all();
	return _isDestroyed;
}

void MVKMetalCompiler::destroy() {
	if (markDestroyed()) { MVKBaseObject::destroy(); }
}

// Marks this object as destroyed, and returns whether the compilation is complete.
bool MVKMetalCompiler::markDestroyed() {
	lock_guard<mutex> lock(_completionLock);

	_isDestroyed = true;
	return _isCompileDone;
}


#pragma mark Construction

MVKMetalCompiler::~MVKMetalCompiler() {
	[_compileError release];
}

#pragma mark -
#pragma mark MVKDeferredOperation

// Call appropriate function from MVKDeferredOperationFunctionPointer with parameters.
// While executing, the function can call setOperationResult() and setMaxConcurrency()
// to update status of the operation, and should return a VkResult that is returned here.
VkResult MVKDeferredOperation::join() {
	switch(_functionType) {
		// .....
        default: return VK_SUCCESS;
    };
}

void MVKDeferredOperation::deferOperation(const MVKDeferredOperationFunctionPointer& pointer,
										  MVKDeferredOperationFunctionType type,
										  void** parameters,
										  uint32_t paramCount) {
    _functionPointer = pointer;
    _functionType = type;

	_functionParameters.reserve(paramCount);
	for(int i = 0; i < paramCount; i++) {
        _functionParameters.push_back(parameters[i]);
    }

	updateResults(VK_SUCCESS, mvkGetAvaliableCPUCores());
}

VkResult MVKDeferredOperation::getOperationResult() {
	lock_guard<mutex> lock(_lock);
	return _operationResult;
}

void MVKDeferredOperation::setOperationResult(VkResult opResult) {
	lock_guard<mutex> lock(_lock);
	_operationResult = opResult;
}

uint32_t MVKDeferredOperation::getMaxConcurrency() {
	lock_guard<mutex> lock(_lock);
	return _maxConcurrency;
}

void MVKDeferredOperation::setMaxConcurrency(uint32_t maxConCurr) {
	lock_guard<mutex> lock(_lock);
	_maxConcurrency = maxConCurr;
}

void MVKDeferredOperation::updateResults(VkResult opResult, uint32_t maxConCurr) {
	lock_guard<mutex> lock(_lock);
	_operationResult = opResult;
	_maxConcurrency = maxConCurr;
}

