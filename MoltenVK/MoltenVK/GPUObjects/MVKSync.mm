/*
 * MVKSync.mm
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

#include "MVKSync.h"
#include "MVKFoundation.h"

using namespace std;


#pragma mark -
#pragma mark MVKSemaphoreImpl

void MVKSemaphoreImpl::release() {
	lock_guard<mutex> lock(_lock);
    if (isClear()) { return; }

    // Either decrement the reservation counter, or clear it altogether
    if (_shouldWaitAll) {
		if (_reservationCount > 0) { _reservationCount--; }
    } else {
        _reservationCount = 0;
    }
    // If all reservations have been released, unblock all waiting threads
    if ( isClear() ) { _blocker.notify_all(); }
}

void MVKSemaphoreImpl::reserve() {
	lock_guard<mutex> lock(_lock);
	reserveImpl();
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

    if (reserveAgain) { reserveImpl(); }
    return isDone;
}


#pragma mark -
#pragma mark MVKSignalable

void MVKSignalable::wasAddedToSignaler() {
	lock_guard<mutex> lock(_signalerLock);

	_signalerCount++;
}

void MVKSignalable::wasRemovedFromSignaler() {
	lock_guard<mutex> lock(_signalerLock);

	if (_signalerCount > 0) { _signalerCount--; }
	maybeDestroy();
}

void MVKSignalable::destroy() {
	lock_guard<mutex> lock(_signalerLock);

	_isDestroyed = true;
	maybeDestroy();
}

void MVKSignalable::maybeDestroy() {
	if (_isDestroyed && _signalerCount == 0) {
		MVKBaseDeviceObject::destroy();
	}
}


#pragma mark -
#pragma mark MVKSemaphore

bool MVKSemaphore::wait(uint64_t timeout) {
	bool isDone = _blocker.wait(timeout, true);
	if ( !isDone && timeout > 0 ) { mvkNotifyErrorWithText(VK_TIMEOUT, "Vulkan semaphore timeout after %llu nanoseconds.", timeout); }
	return isDone;
}

void MVKSemaphore::signal() {
    _blocker.release();
}


#pragma mark -
#pragma mark MVKFence

void MVKFence::addSitter(MVKFenceSitter* fenceSitter) {
	lock_guard<mutex> lock(_lock);

	// Sitters only care about unsignaled fences. If already signaled,
	// don't add myself to the sitter and don't notify the sitter.
	if (_isSignaled) { return; }

	// Ensure each fence only added once to each fence sitter
	auto addRslt = _fenceSitters.insert(fenceSitter);	// pair with second element true if was added
	if (addRslt.second) { fenceSitter->addUnsignaledFence(this); }
}

void MVKFence::removeSitter(MVKFenceSitter* fenceSitter) {
	lock_guard<mutex> lock(_lock);
	_fenceSitters.erase(fenceSitter);
}

void MVKFence::signal() {
	lock_guard<mutex> lock(_lock);

	if (_isSignaled) { return; }	// Only signal once
	_isSignaled = true;

	// Notify all the fence sitters, and clear them from this instance.
    for (auto& fs : _fenceSitters) {
        fs->fenceSignaled(this);
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


#pragma mark Construction

MVKFence::~MVKFence() {
	lock_guard<mutex> lock(_lock);
    for (auto& fs : _fenceSitters) {
        fs->fenceSignaled(this);
    }
}


#pragma mark -
#pragma mark MVKFenceSitter

void MVKFenceSitter::addUnsignaledFence(MVKFence* fence) {
	lock_guard<mutex> lock(_lock);
	// Only reserve semaphore once per fence
	auto addRslt = _unsignaledFences.insert(fence);		// pair with second element true if was added
	if (addRslt.second) { _blocker.reserve(); }
}

void MVKFenceSitter::fenceSignaled(MVKFence* fence) {
	lock_guard<mutex> lock(_lock);
	// Only release semaphore if actually waiting for this fence
	if (_unsignaledFences.erase(fence)) { _blocker.release(); }
}

bool MVKFenceSitter::wait(uint64_t timeout) {
	bool isDone = _blocker.wait(timeout);
	if ( !isDone && timeout > 0 ) { mvkNotifyErrorWithText(VK_TIMEOUT, "Vulkan fence timeout after %llu nanoseconds.", timeout); }
	return isDone;
}


#pragma mark Construction

MVKFenceSitter::~MVKFenceSitter() {
	lock_guard<mutex> lock(_lock);
    for (auto& uf : _unsignaledFences) {
        uf->removeSitter(this);
    }
}


#pragma mark -
#pragma mark Support functions

VkResult mvkResetFences(uint32_t fenceCount, const VkFence* pFences) {
	for (uint32_t i = 0; i < fenceCount; i++) {
		((MVKFence*)pFences[i])->reset();
	}
	return VK_SUCCESS;
}

VkResult mvkWaitForFences(uint32_t fenceCount,
						  const VkFence* pFences,
						  VkBool32 waitAll,
						  uint64_t timeout) {

	// Create a blocking fence sitter and add it to each fence
	MVKFenceSitter fenceSitter(waitAll);
	for (uint32_t i = 0; i < fenceCount; i++) {
		MVKFence* mvkFence = (MVKFence*)pFences[i];
		mvkFence->addSitter(&fenceSitter);
	}
	return fenceSitter.wait(timeout) ? VK_SUCCESS : VK_TIMEOUT;
}


#pragma mark -
#pragma mark MVKMetalCompiler

// Create a compiled object by dispatching the block to the default global dispatch queue, and waiting only as long
// as the MVKDeviceConfiguration::metalCompileTimeout value. If the timeout is triggered, a Vulkan error is created.
// This approach is used to limit the lengthy time (30+ seconds!) consumed by Metal when it's internal compiler fails.
// The thread dispatch is needed because even the sync portion of the async Metal compilation methods can take well
// over a second to return when a compiler failure occurs!
void MVKMetalCompiler::compile(unique_lock<mutex>& lock, dispatch_block_t block) {
	MVKAssert( _startTime == 0, "%s compile occurred already in this instance. Instances of %s should only be used for a single compile activity.", _compilerType.c_str(), className().c_str());
	_startTime = _device->getPerformanceTimestamp();

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);

	// Limit timeout to avoid overflow since wait_for() uses wait_until()
	chrono::nanoseconds nanoTimeout(min(_device->_mvkConfig.metalCompileTimeout, kMVKUndefinedLargeUInt64));
	_blocker.wait_for(lock, nanoTimeout, [this]{ return _isCompileDone; });

	if ( !_isCompileDone ) {
		NSString* errDesc = [NSString stringWithFormat: @"Timeout after %.3f milliseconds. Likely internal Metal compiler error", (double)nanoTimeout.count() / 1e6];
		_compileError = [[NSError alloc] initWithDomain: @"MoltenVK" code: 1 userInfo: @{NSLocalizedDescriptionKey : errDesc}];	// retained
	}

	if (_compileError) { handleError(); }

	_device->addActivityPerformance(*_pPerformanceTracker, _startTime);
}

void MVKMetalCompiler::handleError() {
	setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "%s compile failed (error code %li):\n%s.", _compilerType.c_str(), (long)_compileError.code, _compileError.localizedDescription.UTF8String));
}

void MVKMetalCompiler::endCompile(NSError* compileError) {
	_compileError = [compileError retain];		// retained
	_isCompileDone = true;
	_blocker.notify_all();
	maybeDestroy();
}

void MVKMetalCompiler::destroy() {
	lock_guard<mutex> lock(_completionLock);

	_isDestroyed = true;
	maybeDestroy();
}

void MVKMetalCompiler::maybeDestroy() {
	if (_isDestroyed && _isCompileDone) {
		MVKBaseDeviceObject::destroy();
	}
}

#pragma mark Construction

MVKMetalCompiler::~MVKMetalCompiler() {
	[_compileError release];
}



