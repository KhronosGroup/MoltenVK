/*
 * MVKQueue.h
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKSmallVector.h"
#include <mutex>
#include <condition_variable>

#import <Metal/Metal.h>

class MVKQueue;
class MVKQueueSubmission;
class MVKPhysicalDevice;
class MVKGPUCaptureScope;


#pragma mark -
#pragma mark MVKQueueFamily

/** Represents a Vulkan queue family. */
class MVKQueueFamily : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _physicalDevice->getVulkanAPIObject(); }

	/** Returns the index of this queue family. */
	uint32_t getIndex() { return _queueFamilyIndex; }

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
	MVKSmallVector<id<MTLCommandQueue>, kMVKQueueCountPerQueueFamily> _mtlQueues;
	std::mutex _qLock;
};


#pragma mark -
#pragma mark MVKQueue

/** Represents a Vulkan queue. */
class MVKQueue : public MVKDispatchableVulkanAPIObject, public MVKDeviceTrackingMixin {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_QUEUE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_QUEUE_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _device->getInstance(); }

	/** Return the name of this queue. */
	const std::string& getName() { return _name; }

#pragma mark Queue submissions

	/** Submits the specified command buffers to the queue. */
	template <typename S>
	VkResult submit(uint32_t submitCount, const S* pSubmits, VkFence fence, MVKCommandUse cmdUse);

	/** Submits the specified presentation command to the queue. */
	VkResult submit(const VkPresentInfoKHR* pPresentInfo);

	/** Block the current thread until this queue is idle. */
	VkResult waitIdle(MVKCommandUse cmdUse);

#pragma mark Metal

	/** Returns the Metal queue underlying this queue. */
	id<MTLCommandQueue> getMTLCommandQueue() { return _mtlQueue; }

	/** Returns a Metal command buffer from the Metal queue. */
	id<MTLCommandBuffer> getMTLCommandBuffer(MVKCommandUse cmdUse, bool retainRefs = false);

#pragma mark Construction
	
	/** Constructs an instance for the device and queue family. */
	MVKQueue(MVKDevice* device, MVKQueueFamily* queueFamily, uint32_t index, float priority, VkQueueGlobalPriority globalPriority);

	~MVKQueue() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKQueue() method.
     */
    VkQueue getVkQueue() { return (VkQueue)getVkHandle(); }

    /**
     * Retrieves the MVKQueue instance referenced by the VkQueue handle.
     * This is the compliment of the getVkQueue() method.
     */
    static MVKQueue* getMVKQueue(VkQueue vkQueue) {
        return (MVKQueue*)getDispatchableObject(vkQueue);
    }

protected:
	friend class MVKQueueSubmission;
	friend class MVKQueueCommandBufferSubmission;
	friend class MVKQueuePresentSurfaceSubmission;

	void propagateDebugName() override;
	void initName();
	void initExecQueue();
	void initMTLCommandQueue();
	void destroyExecQueue();
	VkResult submit(MVKQueueSubmission* qSubmit);
	NSString* getMTLCommandBufferLabel(MVKCommandUse cmdUse);
	void handleMTLCommandBufferError(id<MTLCommandBuffer> mtlCmdBuff);

	MVKQueueFamily* _queueFamily;
	std::string _name;
	dispatch_queue_t _execQueue;
	std::mutex _execQueueMutex;
	std::condition_variable _execQueueConditionVariable;
	uint32_t _execQueueJobCount = 0;
	id<MTLCommandQueue> _mtlQueue = nil;
	NSString* _mtlCmdBuffLabelBeginCommandBuffer = nil;
	NSString* _mtlCmdBuffLabelQueueSubmit = nil;
	NSString* _mtlCmdBuffLabelQueuePresent = nil;
	NSString* _mtlCmdBuffLabelDeviceWaitIdle = nil;
	NSString* _mtlCmdBuffLabelQueueWaitIdle = nil;
	NSString* _mtlCmdBuffLabelAcquireNextImage = nil;
	NSString* _mtlCmdBuffLabelInvalidateMappedMemoryRanges = nil;
	NSString* _mtlCmdBuffLabelCopyImageToMemory = nil;
	MVKGPUCaptureScope* _submissionCaptureScope = nil;
	float _priority;
	VkQueueGlobalPriority _globalPriority;
	uint32_t _index;
};


#pragma mark -
#pragma mark MVKQueueSubmission

typedef struct MVKSemaphoreSubmitInfo {
private:
	MVKSemaphore* _semaphore;
public:
	uint64_t value;
	VkPipelineStageFlags2 stageMask;
	uint32_t deviceIndex;

	void encodeWait(id<MTLCommandBuffer> mtlCmdBuff);
	void encodeSignal(id<MTLCommandBuffer> mtlCmdBuff);
	MVKSemaphoreSubmitInfo(const VkSemaphoreSubmitInfo& semaphoreSubmitInfo);
	MVKSemaphoreSubmitInfo(const VkSemaphore semaphore, VkPipelineStageFlags stageMask);
	MVKSemaphoreSubmitInfo(const MVKSemaphoreSubmitInfo& other);
	MVKSemaphoreSubmitInfo& operator=(const MVKSemaphoreSubmitInfo& other);
	~MVKSemaphoreSubmitInfo();

} MVKSemaphoreSubmitInfo;

/** This is an abstract class for an operation that can be submitted to an MVKQueue. */
class MVKQueueSubmission : public MVKBaseDeviceObject, public MVKConfigurableMixin {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _queue->getVulkanAPIObject(); }

	/**
	 * Executes this action on the queue and then disposes of this instance.
	 *
	 * Upon completion of this function, no further calls should be made to this instance.
	 */
	virtual VkResult execute() = 0;

	MVKQueueSubmission(MVKQueue* queue,
					   uint32_t waitSemaphoreInfoCount,
					   const VkSemaphoreSubmitInfo* pWaitSemaphoreSubmitInfos);

	MVKQueueSubmission(MVKQueue* queue,
					   uint32_t waitSemaphoreCount,
					   const VkSemaphore* pWaitSemaphores,
					   const VkPipelineStageFlags* pWaitDstStageMask);

	~MVKQueueSubmission() override;

protected:
	friend class MVKQueue;

	virtual void finish() = 0;
	MVKDevice* getDevice() { return _queue->getDevice(); }

	MVKQueue* _queue;
	MVKSmallVector<MVKSemaphoreSubmitInfo> _waitSemaphores;
	uint64_t _creationTime;
};


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmission

typedef struct MVKCommandBufferSubmitInfo {
	MVKCommandBuffer* commandBuffer;
	uint32_t deviceMask;

	MVKCommandBufferSubmitInfo(const VkCommandBufferSubmitInfo& commandBufferInfo);
	MVKCommandBufferSubmitInfo(VkCommandBuffer commandBuffer);

} MVKCommandBufferSubmitInfo;

/**
 * Submits an empty set of command buffers to the queue.
 * Used for fence-only command submissions.
 */
class MVKQueueCommandBufferSubmission : public MVKQueueSubmission {

public:
	VkResult execute() override;

	MVKQueueCommandBufferSubmission(MVKQueue* queue, 
									const VkSubmitInfo2* pSubmit,
									VkFence fence, 
									MVKCommandUse cmdUse);

	MVKQueueCommandBufferSubmission(MVKQueue* queue, 
									const VkSubmitInfo* pSubmit,
									VkFence fence,
									MVKCommandUse cmdUse);

	~MVKQueueCommandBufferSubmission() override;

protected:
	friend MVKCommandBuffer;

	id<MTLCommandBuffer> getActiveMTLCommandBuffer();
	void setActiveMTLCommandBuffer(id<MTLCommandBuffer> mtlCmdBuff);
	VkResult commitActiveMTLCommandBuffer(bool signalCompletion = false);
	void finish() override;
	virtual void submitCommandBuffers() {}

	MVKCommandEncodingContext _encodingContext;
	MVKSmallVector<MVKSemaphoreSubmitInfo> _signalSemaphores;
	MVKFence* _fence = nullptr;
	id<MTLCommandBuffer> _activeMTLCommandBuffer = nil;
	MVKCommandUse _commandUse = kMVKCommandUseNone;
	bool _emulatedWaitDone = false;		//Used to track if we've already waited for emulated semaphores.
};


/**
 * Submits the commands in a set of command buffers to the queue.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKQueueFullCommandBufferSubmission : public MVKQueueCommandBufferSubmission {

public:
	MVKQueueFullCommandBufferSubmission(MVKQueue* queue, 
										const VkSubmitInfo2* pSubmit,
										VkFence fence,
										MVKCommandUse cmdUse);

	MVKQueueFullCommandBufferSubmission(MVKQueue* queue, 
										const VkSubmitInfo* pSubmit,
										VkFence fence,
										MVKCommandUse cmdUse);

protected:
	void submitCommandBuffers() override;

	MVKSmallVector<MVKCommandBufferSubmitInfo, N> _cmdBuffers;
};


#pragma mark -
#pragma mark MVKQueuePresentSurfaceSubmission

/** Presents a swapchain surface image to the OS. */
class MVKQueuePresentSurfaceSubmission : public MVKQueueSubmission {

public:
	VkResult execute() override;

	MVKQueuePresentSurfaceSubmission(MVKQueue* queue,
									 const VkPresentInfoKHR* pPresentInfo);

protected:
	void finish() override;

	MVKSmallVector<MVKImagePresentInfo, 4> _presentInfo;
};

