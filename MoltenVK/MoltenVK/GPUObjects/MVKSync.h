/*
 * MVKSync.h
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

#pragma once

#include "MVKDevice.h"
#include <mutex>
#include <condition_variable>
#include <unordered_set>

class MVKFenceSitter;


#pragma mark -
#pragma mark MVKSemaphoreImpl

/** 
 * A general utility semaphore object. Reservations can be made with an instance, 
 * and it will block waiting threads until reservations have been released.
 *
 * An instance can be configured so that each call to the reserve() function must be
 * matched with a separate call to the release() function before waiting threads are
 * unblocked, or it can be configured so that a single call to the release() function
 * will release all outstanding reservations and unblock all threads immediately.
 */
class MVKSemaphoreImpl : public MVKBaseObject {

public:

	/**
	 * Adds a reservation to this semaphore, incrementing the reservation count.
	 * Subsequent calls to a wait() function will block until a corresponding call
     * is made to the release() function.
	 */
	void reserve();

	/**
	 * Depending on configuration, releases one or all reservations. When all reservations
	 * have been released, unblocks all waiting threads to continue processing.
	 */
	void release();

	/** 
	 * Indefinitely blocks processing on the current thread until either any or all 
	 * (depending on configuration) outstanding reservations have been released.
     *
     * If reserveAgain is set to true, a single reservation will be added to this
     * instance once the wait is finished.
	 */
	void wait(bool reserveAgain = false);

	/**
	 * Blocks processing on the current thread until any or all (depending on configuration) outstanding
     * reservations have been released, or until the specified timeout interval in nanoseconds expires.
     *
     * If reserveAgain is set to true, a single reservation will be added once this wait is finished.
	 *
	 * Returns true if all reservations were cleared, or false if the timeout interval expired.
	 */
	bool wait(uint64_t timeout, bool reserveAgain = false);


#pragma mark Construction

	/** 
	 * Constructs an instance with the specified number of initial reservations. 
	 * This value defaults to zero, starting the semaphore in an unblocking state.
	 *
	 * The waitAll parameter indicates whether a call to the release() function is required
	 * for each call to the reserve() function (waitAll = true), or whether a single call 
	 * to the release() function will release all outstanding reservations (waitAll = true). 
	 * This value defaults to true, indicating that each call to the reserve() function will
	 * require a separate call to the release() function to cause the semaphore to stop blocking.
	 */
    MVKSemaphoreImpl(bool waitAll = true, uint32_t reservationCount = 0)
        : _shouldWaitAll(waitAll), _reservationCount(reservationCount) {}


private:
	bool operator()();
    inline void reserveImpl() { _reservationCount++; }          // Not thread-safe
    inline bool isClear() { return _reservationCount == 0; }    // Not thread-safe

	std::mutex _lock;
	std::condition_variable _blocker;
	uint32_t _reservationCount;
	bool _shouldWaitAll;
};


#pragma mark -
#pragma mark MVKSemaphore

/** Represents a Vulkan semaphore. */
class MVKSemaphore : public MVKBaseDeviceObject {

public:

	/** Indefinitely blocks processing on the current thread until this semaphore is signaled. */
	void wait();

	/** 
	 * Blocks processing on the current thread until this semaphore is 
	 * signaled, or until the specified timeout in nanoseconds expires.
	 *
	 * Returns true if this semaphore was signaled, or false if the timeout interval expired.
	 */
	bool wait(uint64_t timeout);

	/** Signals the semaphore. Unblocks all waiting threads to continue processing. */
	void signal();


#pragma mark Construction

    MVKSemaphore(MVKDevice* device, const VkSemaphoreCreateInfo* pCreateInfo)
        : MVKBaseDeviceObject(device), _blocker(false, 1) {}

protected:
	MVKSemaphoreImpl _blocker;
};


#pragma mark -
#pragma mark MVKFence

/** Represents a Vulkan fence. */
class MVKFence : public MVKBaseDeviceObject {

public:

	/**
	 * If this fence has not been signaled yet, adds the specified fence sitter to the
	 * internal list of fence sitters that will be notified when this fence is signaled,
	 * and then calls addUnsignaledFence() on the fence sitter so it is aware that it
	 * will be signaled.
	 *
	 * Does nothing if this fence has already been signaled, and does not call 
	 * addUnsignaledFence() on the fence sitter.
	 *
	 * Each fence sitter should only listen once for each fence. Adding the same fence sitter
	 * more than once in between each fence reset and signal results in undefined behaviour.
	 */
	void addSitter(MVKFenceSitter* fenceSitter);

	/** Removes the specified fence sitter. */
	void removeSitter(MVKFenceSitter* fenceSitter);

	/** Signals this fence. Notifies all waiting fence sitters. */
	void signal();

	/** Rremoves all fence sitters and resets this fence back to unsignaled state again. */
	void reset();

	/** Returns whether this fence has been signaled and not reset. */
	bool getIsSignaled();

	
#pragma mark Construction

    MVKFence(MVKDevice* device, const VkFenceCreateInfo* pCreateInfo) : MVKBaseDeviceObject(device),
    _isSignaled(mvkAreFlagsEnabled(pCreateInfo->flags, VK_FENCE_CREATE_SIGNALED_BIT)) {}

	~MVKFence() override;

protected:
	void notifySitters();

	std::mutex _lock;
	std::unordered_set<MVKFenceSitter*> _fenceSitters;
	bool _isSignaled;
};


#pragma mark -
#pragma mark MVKFenceSitter

/** An object that responds to signals from MVKFences. */
class MVKFenceSitter : public MVKBaseObject {

public:

	/**
	 * If this instance has been configured to wait for fences, blocks processing on the
	 * current thread until any or all of the fences that this instance is waiting for are
	 * signaled. If this instance has not been configured to wait for fences, this function
	 * immediately returns true.
	 *
	 * Returns whether the lock timed out while waiting.
	 */
	void wait();

	/**
	 * If this instance has been configured to wait for fences, blocks processing on the 
	 * current thread until any or all of the fences that this instance is waiting for are
	 * signaled, or until the specified timeout in nanoseconds expires. If this instance
	 * has not been configured to wait for fences, this function immediately returns true.
	 *
	 * Returns true if the required fences were triggered, or false if the timeout interval expired.
	 */
	bool wait(uint64_t timeout);


#pragma mark Construction

	/** Constructs an instance with the specified type of waiting. */
	MVKFenceSitter(bool waitAll = true) : _blocker(waitAll, 0) {}

	~MVKFenceSitter() override;

private:
	friend class MVKFence;

	void addUnsignaledFence(MVKFence* fence);
	void fenceSignaled(MVKFence* fence);

	std::mutex _lock;
	std::unordered_set<MVKFence*> _unsignaledFences;
	MVKSemaphoreImpl _blocker;
};


#pragma mark -
#pragma mark Support functions

/** Resets the specified fences. */
VkResult mvkResetFences(uint32_t fenceCount, const VkFence* pFences);

/** 
 * Blocks the current thread until any or all of the specified 
 * fences have been signaled, or the specified timeout occurs.
 */
VkResult mvkWaitForFences(uint32_t fenceCount,
						  const VkFence* pFences,
						  VkBool32 waitAll,
						  uint64_t timeout);


