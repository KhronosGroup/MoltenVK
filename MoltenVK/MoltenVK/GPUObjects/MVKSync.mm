/*
 * MVKSync.mm
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
        _reservationCount--;
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

void MVKSemaphoreImpl::wait(bool reserveAgain) {
	unique_lock<mutex> lock(_lock);
	_blocker.wait(lock, [this]{ return isClear(); });
    if (reserveAgain) { reserveImpl(); }
}

bool MVKSemaphoreImpl::wait(uint64_t timeout, bool reserveAgain) {
    unique_lock<mutex> lock(_lock);

    bool isDone;
    if (timeout > 0) {
        // Limit timeout to avoid overflow since wait_for() uses wait_until()
        uint64_t nanoTimeout = min(timeout, numeric_limits<uint64_t>::max() >> 4);
        chrono::nanoseconds nanos(nanoTimeout);
        isDone = _blocker.wait_for(lock, nanos, [this]{ return isClear(); });
    } else {
        isDone = isClear();
    }

    if (reserveAgain) { reserveImpl(); }
    return isDone;
}


#pragma mark -
#pragma mark MVKSemaphore

void MVKSemaphore::wait() {
//    MVKLogDebug("Waiting on semaphore %p. Elapsed time: %.6f ms.", this, mvkGetElapsedMilliseconds());
    _blocker.wait(true);
//    MVKLogDebug("Done waiting on semaphore %p. Elapsed time: %.6f ms.", this, mvkGetElapsedMilliseconds());
}

bool MVKSemaphore::wait(uint64_t timeout) {
//    MVKLogDebug("Waiting on semaphore %p for max timeout %llu. Elapsed time: %.6f ms.", this, timeout, mvkGetElapsedMilliseconds());
	bool isDone = _blocker.wait(timeout, true);
//    MVKLogDebug("Done waiting on semaphore %p. Elapsed time: %.6f ms.", this, mvkGetElapsedMilliseconds());
	if ( !isDone && timeout > 0 ) { mvkNotifyErrorWithText(VK_TIMEOUT, "Vulkan semaphore timeout after %d nanoseconds.", timeout); }
	return isDone;
}

void MVKSemaphore::signal() {
    _blocker.release();
//    MVKLogDebug("Signalled semaphore %p. Elapsed time: %.6f ms.", this, mvkGetElapsedMilliseconds());
}


#pragma mark -
#pragma mark MVKFence

void MVKFence::addSitter(MVKFenceSitter* fenceSitter) {
	lock_guard<mutex> lock(_lock);

	// Sitters only care about unsignaled fences. If already signaled,
	// don't add myself to the sitter and don't notify the sitter.
	if (_isSignaled) {
//        MVKLogDebug("Fence %p already signaled. Sitter not added. Elapsed time: %.6f ms.", this, mvkGetElapsedMilliseconds());
        return;
    }

	// Ensure each fence only added once to each fence sitter
	auto addRslt = _fenceSitters.insert(fenceSitter);	// pair with second element true if was added
	if (addRslt.second) { fenceSitter->addUnsignaledFence(this); }

//    MVKLogDebug("Fence %p adding sitter %d. Elapsed time: %.6f ms.", this, _fenceSitters.size(), mvkGetElapsedMilliseconds());
}

void MVKFence::removeSitter(MVKFenceSitter* fenceSitter) {
	lock_guard<mutex> lock(_lock);
//    MVKLogDebug("Fence %p removing sitter %d. Elapsed time: %.6f ms.", this, _fenceSitters.size(), mvkGetElapsedMilliseconds());
	_fenceSitters.erase(fenceSitter);
}

void MVKFence::signal() {
	lock_guard<mutex> lock(_lock);

	if (_isSignaled) { return; }	// Only signal once
	_isSignaled = true;

//    MVKLogDebug("Fence %p with %d sitters signaled. Elapsed time: %.6f ms.", this , _fenceSitters.size(), mvkGetElapsedMilliseconds());

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
//    MVKLogDebug("Reset fence %p. Elapsed time: %.6f ms.", this, mvkGetElapsedMilliseconds());
}

bool MVKFence::getIsSignaled() {
	lock_guard<mutex> lock(_lock);
//    MVKLogDebug("Checking fence %p status: %ssignaled. Elapsed time: %.6f ms.", this, (_isSignaled ? "" : "un"), mvkGetElapsedMilliseconds());
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

void MVKFenceSitter::wait() { _blocker.wait(); }

bool MVKFenceSitter::wait(uint64_t timeout) {
	bool isDone = _blocker.wait(timeout);
	if ( !isDone && timeout > 0 ) { mvkNotifyErrorWithText(VK_TIMEOUT, "Vulkan fence timeout after %d nanoseconds.", timeout); }
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

//	MVKLogDebug("Waiting for fences. Elapsed time: %.6f ms.", mvkGetElapsedMilliseconds());

	// Create a blocking fence sitter and add it to each fence
	MVKFenceSitter fenceSitter(waitAll);
	for (uint32_t i = 0; i < fenceCount; i++) {
		MVKFence* mvkFence = (MVKFence*)pFences[i];
		mvkFence->addSitter(&fenceSitter);
	}
	VkResult rslt = fenceSitter.wait(timeout) ? VK_SUCCESS : VK_TIMEOUT;

//	MVKLogDebug("Fences done. Elapsed time: %.6f ms.", mvkGetElapsedMilliseconds());

	return rslt;
}



