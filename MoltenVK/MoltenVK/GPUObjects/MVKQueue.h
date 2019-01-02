/*
 * MVKQueue.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKCommandBuffer.h"
#include "MVKImage.h"
#include "MVKSync.h"
#include "MVKVector.h"
#include <vector>
#include <mutex>

#import <Metal/Metal.h>

class MVKQueue;
class MVKQueueSubmission;
class MVKPhysicalDevice;
class MVKGPUCaptureScope;


#pragma mark -
#pragma mark MVKQueueFamily

/** Represents a Vulkan queue family. */
class MVKQueueFamily : public MVKConfigurableObject {

public:

	/** Returns the index of this queue family. */
	inline uint32_t getIndex() { return _queueFamilyIndex; }

	/** Populates the specified properties structure. */
	inline void getProperties(VkQueueFamilyProperties* queueProperties) {
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
	VkResult submit(const VkPresentInfoKHR* pPresentInfo);

	/** Block the current thread until this queue is idle. */
	VkResult waitIdle(MVKCommandUse cmdBuffUse);

	/** Return the name of this queue. */
	inline const std::string& getName() { return _name; }


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
	friend class MVKQueueCommandBufferSubmission;
	friend class MVKQueuePresentSurfaceSubmission;

	void initName();
	void initExecQueue();
	void initMTLCommandQueue();
	void initGPUCaptureScopes();
	void destroyExecQueue();
	VkResult submit(MVKQueueSubmission* qSubmit);

	MVKQueueFamily* _queueFamily;
	uint32_t _index;
	float _priority;
	dispatch_queue_t _execQueue;
	id<MTLCommandQueue> _mtlQueue;
	std::string _name;
	MVKMTLCommandBufferID _nextMTLCmdBuffID;
	MVKGPUCaptureScope* _submissionCaptureScope;
	MVKGPUCaptureScope* _presentationCaptureScope;
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
	MVKVector<MVKSemaphore*> _waitSemaphores;
	bool _isAwaitingSemaphores;
};


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmission

/** Submits the commands in a set of command buffers to the queue. */
class MVKQueueCommandBufferSubmission : public MVKQueueSubmission {

public:
	void execute() override;

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
	friend MVKCommandBuffer;

	id<MTLCommandBuffer> getActiveMTLCommandBuffer();
	void setActiveMTLCommandBuffer(id<MTLCommandBuffer> mtlCmdBuff);
	void commitActiveMTLCommandBuffer(bool signalCompletion = false);
	void finish();

	MVKVector<MVKCommandBuffer*> _cmdBuffers;
	MVKVector<MVKSemaphore*> _signalSemaphores;
	MVKFence* _fence;
    MVKCommandUse _cmdBuffUse;
	id<MTLCommandBuffer> _activeMTLCommandBuffer;
};


#pragma mark -
#pragma mark MVKQueuePresentSurfaceSubmission

/** Presents a swapchain surface image to the OS. */
class MVKQueuePresentSurfaceSubmission : public MVKQueueSubmission {

public:
	void execute() override;

	/** Constructs an instance for the device and queue. */
	MVKQueuePresentSurfaceSubmission(MVKDevice* device,
									 MVKQueue* queue,
									 const VkPresentInfoKHR* pPresentInfo);

protected:
	MVKVector<MVKSwapchainImage*> _surfaceImages;
};

