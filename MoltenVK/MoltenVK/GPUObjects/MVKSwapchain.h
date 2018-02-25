/*
 * MVKSwapchain.h
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
#include <vector>

class MVKSwapchainImage;
class MVKWatermark;


#pragma mark MVKSwapchain

/** Represents a Vulkan swapchain. */
class MVKSwapchain : public MVKBaseDeviceObject {

public:

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
								 uint32_t* pImageIndex);

	/** Returns whether the surface size has changed since the last time this function was called. */
	bool getHasSurfaceSizeChanged();

    /** Populates the specified performance stats structure. */
    void getPerformanceStatistics(MVKSwapchainPerformance* pSwapchainPerf);


#pragma mark Metal

	/** 
	 * Returns the next Metal drawable available to provide backing for 
	 * an image in this swapchain. The returned object is autoreleased.
	 *
	 * This function may block until the next drawable is available, 
	 * and may return nil if no drawable is available at all.
	 */
	id<CAMetalDrawable> getNextCAMetalDrawable();


#pragma mark Construction
	
	MVKSwapchain(MVKDevice* device, const VkSwapchainCreateInfoKHR* pCreateInfo);

	~MVKSwapchain() override;

protected:
	friend class MVKSwapchainImage;

	void initSurfaceImages(const VkSwapchainCreateInfoKHR* pCreateInfo);
    void initFrameIntervalTracking();
	void releaseUndisplayedSurfaces();
	uint64_t getNextAcquisitionID();
    void willPresentSurface(id<MTLTexture> mtlTexture, id<MTLCommandBuffer> mtlCmdBuff);
    void renderWatermark(id<MTLTexture> mtlTexture, id<MTLCommandBuffer> mtlCmdBuff);
    void markFrameInterval();

	CAMetalLayer* _mtlLayer;
    MVKWatermark* _licenseWatermark;
	std::vector<MVKSwapchainImage*> _surfaceImages;
	std::atomic<uint64_t> _currentAcquisitionID;
    CGSize _mtlLayerOrigDrawSize;
    MVKSwapchainPerformance _performanceStatistics;
    uint64_t _lastFrameTime;
    double _averageFrameIntervalFilterAlpha;
    uint32_t _currentPerfLogFrameCount;
};

