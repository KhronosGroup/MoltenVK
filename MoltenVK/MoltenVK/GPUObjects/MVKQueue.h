/*
 * MVKQueue.h
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#pragma mark Queue submissions

	/** Submits the specified command buffers to the queue. */
	VkResult submit(uint32_t submitCount, const VkSubmitInfo* pSubmits, VkFence fence, MVKCommandUse cmdUse);

	/** Submits the specified presentation command to the queue. */
	VkResult submit(const VkPresentInfoKHR* pPresentInfo);

	/** Block the current thread until this queue is idle. */
	VkResult waitIdle(MVKCommandUse cmdUse);

	/** Return the name of this queue. */
	const std::string& getName() { return _name; }


#pragma mark Metal

	/** Returns the Metal queue underlying this queue. */
	id<MTLCommandQueue> getMTLCommandQueue() { return _mtlQueue; }

	/** Returns a Metal command buffer from the Metal queue. */
	id<MTLCommandBuffer> getMTLCommandBuffer(MVKCommandUse cmdUse, bool retainRefs = false);

#pragma mark Construction
	
	/** Constructs an instance for the device and queue family. */
	MVKQueue(MVKDevice* device, MVKQueueFamily* queueFamily, uint32_t index, float priority);

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

	MVKBaseObject* getBaseObject() override { return this; };
	void propagateDebugName() override;
	void initName();
	void initExecQueue();
	void initMTLCommandQueue();
	void initGPUCaptureScopes();
	void destroyExecQueue();
	VkResult submit(MVKQueueSubmission* qSubmit);
	NSString* getMTLCommandBufferLabel(MVKCommandUse cmdUse);

	MVKQueueFamily* _queueFamily;
	uint32_t _index;
	float _priority;
	dispatch_queue_t _execQueue;
	id<MTLCommandQueue> _mtlQueue;
	std::string _name;
	NSString* _mtlCmdBuffLabelEndCommandBuffer;
	NSString* _mtlCmdBuffLabelQueueSubmit;
	NSString* _mtlCmdBuffLabelQueuePresent;
	NSString* _mtlCmdBuffLabelDeviceWaitIdle;
	NSString* _mtlCmdBuffLabelQueueWaitIdle;
	NSString* _mtlCmdBuffLabelAcquireNextImage;
	NSString* _mtlCmdBuffLabelInvalidateMappedMemoryRanges;
	MVKGPUCaptureScope* _submissionCaptureScope;
};


#pragma mark -
#pragma mark MVKQueueSubmission

/** This is an abstract class for an operation that can be submitted to an MVKQueue. */
class MVKQueueSubmission : public MVKBaseObject, public MVKConfigurableMixin {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _queue->getVulkanAPIObject(); }

	/**
	 * Executes this action on the queue and then disposes of this instance.
	 *
	 * Upon completion of this function, no further calls should be made to this instance.
	 */
	virtual void execute() = 0;

	MVKQueueSubmission(MVKQueue* queue,
					   uint32_t waitSemaphoreCount,
					   const VkSemaphore* pWaitSemaphores);

	~MVKQueueSubmission() override;

protected:
	friend class MVKQueue;

	MVKQueue* _queue;
	MVKSmallVector<std::pair<MVKSemaphore*, uint64_t>> _waitSemaphores;
};


#pragma mark -
#pragma mark MVKQueueCommandBufferSubmission

/** Submits the commands in a set of command buffers to the queue. */
class MVKQueueCommandBufferSubmission : public MVKQueueSubmission {

public:
	void execute() override;

	MVKQueueCommandBufferSubmission(MVKQueue* queue, const VkSubmitInfo* pSubmit, VkFence fence, MVKCommandUse cmdUse);

	~MVKQueueCommandBufferSubmission() override;

protected:
	friend MVKCommandBuffer;

	id<MTLCommandBuffer> getActiveMTLCommandBuffer();
	void setActiveMTLCommandBuffer(id<MTLCommandBuffer> mtlCmdBuff);
	void commitActiveMTLCommandBuffer(bool signalCompletion = false);
	virtual void finish();
	virtual void submitCommandBuffers() {}

	MVKSmallVector<std::pair<MVKSemaphore*, uint64_t>> _signalSemaphores;
	MVKFence* _fence;
	id<MTLCommandBuffer> _activeMTLCommandBuffer;
	MVKCommandUse _commandUse;
	bool _emulatedWaitDone; //Used to track if we've already waited for emulated semaphores.
};


/**
 * Submits the commands in a set of command buffers to the queue.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKQueueFullCommandBufferSubmission : public MVKQueueCommandBufferSubmission {

public:
	MVKQueueFullCommandBufferSubmission(MVKQueue* queue, const VkSubmitInfo* pSubmit, VkFence fence) :
		MVKQueueCommandBufferSubmission(queue, pSubmit, fence, kMVKCommandUseQueueSubmit) {

			// pSubmit can be null if just tracking the fence alone
			if (pSubmit) {
				uint32_t cbCnt = pSubmit->commandBufferCount;
				_cmdBuffers.reserve(cbCnt);
				for (uint32_t i = 0; i < cbCnt; i++) {
					MVKCommandBuffer* cb = MVKCommandBuffer::getMVKCommandBuffer(pSubmit->pCommandBuffers[i]);
					_cmdBuffers.push_back(cb);
					setConfigurationResult(cb->getConfigurationResult());
				}
			}
		}

protected:
	void submitCommandBuffers() override;
	void finish() override;

	MVKSmallVector<MVKCommandBuffer*, N> _cmdBuffers;
	MTLTimestamp _cpuStart = 0;
	MTLTimestamp _gpuStart = 0;
};


#pragma mark -
#pragma mark MVKQueuePresentSurfaceSubmission

/** Presents a swapchain surface image to the OS. */
class MVKQueuePresentSurfaceSubmission : public MVKQueueSubmission {

public:
	void execute() override;

	MVKQueuePresentSurfaceSubmission(MVKQueue* queue,
									 const VkPresentInfoKHR* pPresentInfo);

protected:
	void stopAutoGPUCapture();

	MVKSmallVector<MVKPresentTimingInfo, 4> _presentInfo;
};

