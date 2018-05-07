/*
 * MVKQueue.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandEncodingPool.h"
#include "MVKImage.h"
#include "MVKSync.h"
#include <vector>
#include <mutex>

#import <Metal/Metal.h>

class MVKQueue;
class MVKQueueSubmission;
class MVKPhysicalDevice;


#pragma mark -
#pragma mark MVKQueueFamily

/** Represents a Vulkan queue family. */
class MVKQueueFamily : public MVKConfigurableObject {

public:

	/** Returns the index of this queue family. */
	inline uint32_t getIndex() { return _queueFamilyIndex; }

	/** Populates the specified properties structure. */
	void getProperties(VkQueueFamilyProperties* queueProperties) {
		if (queueProperties) { *queueProperties = _properties; }
	}

	/** Returns the MTLCommandQueue at the specified index. */
	id<MTLCommandQueue> getMTLCommandQueue(uint32_t queueIndex);

	/** Constructs an instance with the specified index. */
	MVKQueueFamily(MVKPhysicalDevice* physicalDevice, uint32_t queueFamilyIndex, const VkQueueFamilyProperties* pProperties);

	~MVKQueueFamily() override;

protected:
	MVKPhysicalDevice* _physicalDevice;
    uint32_t _queueFamilyIndex;
	VkQueueFamilyProperties _properties;
	std::vector<id<MTLCommandQueue>> _mtlQueues;
	std::mutex _qLock;
};


#pragma mark -
#pragma mark MVKQueue

/** Represents a Vulkan queue. */
class MVKQueue : public MVKDispatchableDeviceObject {

public:

#pragma mark Queue submissions

	/** Submits the specified command buffers to the queue. */
	VkResult submit(uint32_t submitCount, const VkSubmitInfo* pSubmits,
                    VkFence fence, MVKCommandUse cmdBuffUse);

	/** Submits the specified presentation command to the queue. */
	VkResult submitPresentKHR(const VkPresentInfoKHR* pPresentInfo);

	/** Block the current thread until this queue is idle. */
	VkResult waitIdle(MVKCommandUse cmdBuffUse);

	/**
	 * Retrieves a MTLCommandBuffer instance from the contained MTLCommandQueue, adds a 
	 * completion handler to it so that the mtlCommandBufferHasCompleted() function will 
	 * be called when the MTLCommandBuffer completes, and returns the MTLCommandBuffer.
	 */
	id<MTLCommandBuffer> makeMTLCommandBuffer(NSString* mtlCmdBuffLabel);

	/** Called automatically when the specified MTLCommandBuffer with the specified ID has completed. */
	void mtlCommandBufferHasCompleted(id<MTLCommandBuffer> mtlCmdBuff, MVKMTLCommandBufferID mtlCmdBuffID);

	/**
	 * Registers the specified countdown object. This function sets the count value
	 * of the countdown object to the current number of incomplete MTLCommandBuffers,
	 * and marks the countdown object with the ID of the most recently registered
	 * MTLCommandBuffer. The countdown object will be decremented each time any
	 * MTLCommandBuffer with an ID less than the ID of the most recent MTLCommandBuffer
	 * at the time the countdown object was registered.
	 *
	 * If the current number of incomplete MTLCommandBuffers is zero, the countdown
	 * object will indicate that it is already completed, and will not be registered.
	 */
	void registerMTLCommandBufferCountdown(MVKMTLCommandBufferCountdown* countdown);

    /** Returns the command encoding pool. */
    inline MVKCommandEncodingPool* getCommandEncodingPool() { return &_commandEncodingPool; }


#pragma mark Metal

	/** Returns the Metal queue underlying this queue. */
	inline id<MTLCommandQueue> getMTLCommandQueue() { return _mtlQueue; }

#pragma mark Construction
	
	/** Constructs an instance for the device and queue family. */
	MVKQueue(MVKDevice* device, MVKQueueFamily* queueFamily, uint32_t index, float priority);

	~MVKQueue() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKQueue() method.
     */
    inline VkQueue getVkQueue() { return (VkQueue)getVkHandle(); }

    /**
     * Retrieves the MVKQueue instance referenced by the VkQueue handle.
     * This is the compliment of the getVkQueue() method.
     */
    static inline MVKQueue* getMVKQueue(VkQueue vkQueue) {
        return (MVKQueue*)getDispatchableObject(vkQueue);
    }

protected:
	friend class MVKQueueSubmission;

	void initExecQueue();
	void initMTLCommandQueue();
	void destroyExecQueue();
	void submit(MVKQueueSubmission* qSubmit);

	MVKQueueFamily* _queueFamily;
	uint32_t _index;
	float _priority;
	dispatch_queue_t _execQueue;
	id<MTLCommandQueue> _mtlQueue;
	std::vector<MVKMTLCommandBufferCountdown*> _completionCountdowns;
	std::mutex _completionLock;
	uint32_t _activeMTLCommandBufferCount;
	MVKMTLCommandBufferID _nextMTLCmdBuffID;
    MVKCommandEncodingPool _commandEncodingPool;
};


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmissionCountdown

/** Counts down MTLCommandBuffers on behalf of an MVKQueueCommandBufferSubmission instance. */
class MVKQueueCommandBufferSubmissionCountdown : public MVKMTLCommandBufferCountdown {

public:

	/** Constructs an instance. */
	MVKQueueCommandBufferSubmissionCountdown(MVKQueueCommandBufferSubmission* qSub);

protected:

	/** Performs the action to take when the count has reached zero. */
	virtual void finish();

	MVKQueueCommandBufferSubmission* _qSub;
};


#pragma mark -
#pragma mark MVKQueueSubmission

/** This is an abstract class for an operation that can be submitted to an MVKQueue. */
class MVKQueueSubmission : public MVKBaseDeviceObject {

public:

	/** 
	 * Executes this action on the queue and then disposes of this instance.
	 *
	 * Upon completion of this function, no further calls should be made to this instance.
	 */
	virtual void execute() = 0;

	MVKQueueSubmission(MVKDevice* device,
					   MVKQueue* queue,
					   uint32_t waitSemaphoreCount,
					   const VkSemaphore* pWaitSemaphores);

protected:
	friend class MVKQueue;

   void recordResult(VkResult vkResult);

	MVKQueue* _queue;
	MVKQueueSubmission* _prev;
	MVKQueueSubmission* _next;
	VkResult _submissionResult;
	std::vector<MVKSemaphore*> _waitSemaphores;
	bool _isAwaitingSemaphores;
};


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmission

/** Submits the commands in a set of command buffers to the queue. */
class MVKQueueCommandBufferSubmission : public MVKQueueSubmission {

public:

	/**
	 * Executes this action on the queue and then disposes of this instance.
	 *
	 * Upon completion of this function, no further calls should be made to this instance.
	 */
	virtual void execute();

	/** Automatically called once all the MTLCommandBuffers have completed execution. */
	void finish();

	/** Returns the active MTLCommandBuffer instance, lazily retrieving it from the queue if needed. */
	id<MTLCommandBuffer> getActiveMTLCommandBuffer();

	/** Commits and releases the currently active MTLCommandBuffer. */
	void commitActiveMTLCommandBuffer();

	/** 
     * Constructs an instance for the device and queue.
     * pSubmit may be VK_NULL_HANDLE to create an instance that triggers a fence without submitting any actual command buffers.
     */
	MVKQueueCommandBufferSubmission(MVKDevice* device,
									MVKQueue* queue,
									const VkSubmitInfo* pSubmit,
									VkFence fence,
                                    MVKCommandUse cmdBuffUse);

    /** Constructs an instance for the device and queue, with a fence, but without actual command buffers. */
    MVKQueueCommandBufferSubmission(MVKDevice* device, MVKQueue* queue, VkFence fence);

protected:
	friend MVKCommandEncoder;

    NSString* getMTLCommandBufferName();

	MVKQueueCommandBufferSubmissionCountdown _cmdBuffCountdown;
	std::vector<MVKCommandBuffer*> _cmdBuffers;
	std::vector<MVKSemaphore*> _signalSemaphores;
	MVKFence* _fence;
    MVKCommandUse _cmdBuffUse;
	id<MTLCommandBuffer> _activeMTLCommandBuffer;
};


#pragma mark -
#pragma mark MVKQueuePresentSurfaceSubmission

/** Presents a swapchain surface image to the OS. */
class MVKQueuePresentSurfaceSubmission : public MVKQueueSubmission {

public:

	/**
	 * Executes this action on the queue and then disposes of this instance.
	 *
	 * Upon completion of this function, no further calls should be made to this instance.
	 */
	virtual void execute();

	/** Constructs an instance for the device and queue. */
	MVKQueuePresentSurfaceSubmission(MVKDevice* device,
									 MVKQueue* queue,
									 const VkPresentInfoKHR* pPresentInfo);

protected:
	std::vector<MVKSwapchainImage*> _surfaceImages;
};

