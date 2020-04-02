/*
 * MVKSwapchain.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKImage.h"
#include "MVKVector.h"

class MVKWatermark;

@class MVKBlockObserver;


/** Indicates the relative availability of each image in the swapchain. */
typedef struct MVKSwapchainImageAvailability {
	uint64_t acquisitionID;			/**< When this image was last made available, relative to the other images in the swapchain. Smaller value is earlier. */
	uint32_t waitCount;				/**< The number of semaphores already waiting for this image. */
	bool isAvailable;				/**< Indicates whether this image is currently available. */

	bool operator< (const MVKSwapchainImageAvailability& rhs) const;
} MVKSwapchainImageAvailability;


#pragma mark MVKSwapchain

/** Tracks a semaphore and fence for later signaling. */
typedef std::pair<MVKSemaphore*, MVKFence*> MVKSwapchainSignaler;

/** Represents a Vulkan swapchain. */
class MVKSwapchain : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_SWAPCHAIN_KHR; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_SWAPCHAIN_KHR_EXT; }

	/** Returns the number of images in this swapchain. */
	uint32_t getImageCount();

	/** Returns the image at the specified index. */
	MVKSwapchainImage* getImage(uint32_t index);

	/**
	 * Returns the array of presentable images associated with this swapchain.
	 *
	 * If pSwapchainImages is null, the value of pCount is updated with the number of
	 * presentable images associated with this swapchain.
	 *
	 * If pSwapchainImages is not null, then pCount images are copied into the array.
	 * If the number of available images is less than pCount, the value of pCount is
	 * updated to indicate the number of images actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of supported
	 * images is larger than pCount. Returns other values if an error occurs.
	 */
	VkResult getImages(uint32_t* pCount, VkImage* pSwapchainImages);

	/** Returns the index of the next swapchain image. */
	VkResult acquireNextImageKHR(uint64_t timeout,
								 VkSemaphore semaphore,
								 VkFence fence,
								 uint32_t deviceMask,
								 uint32_t* pImageIndex);

	/** Returns whether the surface size has changed since the last time this function was called. */
	bool getHasSurfaceSizeChanged();

	/** Returns whether the parent surface is now lost and this swapchain must be recreated. */
	bool getIsSurfaceLost() { return _surfaceLost; }

	/** Returns the specified performance stats structure. */
	const MVKSwapchainPerformance* getPerformanceStatistics() { return &_performanceStatistics; }

	/** Adds HDR metadata to this swapchain. */
	void setHDRMetadataEXT(const VkHdrMetadataEXT& metadata);

	/**
	 * Registers a semaphore and/or fence that will be signaled when the image at the given index becomes available.
	 * This function accepts both a semaphore and a fence, and either none, one, or both may be provided.
	 * If this image is available already, the semaphore and fence are immediately signaled.
	 */
	void signalWhenAvailable(uint32_t imageIndex, MVKSemaphore* semaphore, MVKFence* fence);


#pragma mark Construction
	
	MVKSwapchain(MVKDevice* device, const VkSwapchainCreateInfoKHR* pCreateInfo);

	~MVKSwapchain() override;

protected:
	friend class MVKSwapchainImage;

	struct Availability {
		MVKSwapchainImageAvailability status;
		MVKVectorInline<MVKSwapchainSignaler, 1> signalers;
		MVKSwapchainSignaler preSignaled;
	};

	void propogateDebugName() override;
	void initCAMetalLayer(const VkSwapchainCreateInfoKHR* pCreateInfo, uint32_t imgCnt);
	void initSurfaceImages(const VkSwapchainCreateInfoKHR* pCreateInfo, uint32_t imgCnt);
    void initFrameIntervalTracking();
	void releaseUndisplayedSurfaces();
	uint64_t getNextAcquisitionID();
    void willPresentSurface(id<MTLTexture> mtlTexture, id<MTLCommandBuffer> mtlCmdBuff);
    void renderWatermark(id<MTLTexture> mtlTexture, id<MTLCommandBuffer> mtlCmdBuff);
    void markFrameInterval();
	void signal(MVKSwapchainSignaler& signaler, id<MTLCommandBuffer> mtlCmdBuff);
	void signalPresentationSemaphore(uint32_t imgIdx, id<MTLCommandBuffer> mtlCmdBuff);
	static void markAsTracked(MVKSwapchainSignaler& signaler);
	static void unmarkAsTracked(MVKSwapchainSignaler& signaler);
	void makeAvailable(uint32_t imgIdx);

	CAMetalLayer* _mtlLayer;
    MVKWatermark* _licenseWatermark;
	MVKVectorInline<MVKSwapchainImage*, kMVKMaxSwapchainImageCount> _surfaceImages;
	MVKVectorInline<Availability, kMVKMaxSwapchainImageCount> _imageAvailability;
	std::mutex _availabilityLock;
	std::atomic<uint64_t> _currentAcquisitionID;
    CGSize _mtlLayerOrigDrawSize;
    MVKSwapchainPerformance _performanceStatistics;
    uint64_t _lastFrameTime;
    double _averageFrameIntervalFilterAlpha;
    uint32_t _currentPerfLogFrameCount;
    std::atomic<bool> _surfaceLost;
    MVKBlockObserver* _layerObserver;
};

