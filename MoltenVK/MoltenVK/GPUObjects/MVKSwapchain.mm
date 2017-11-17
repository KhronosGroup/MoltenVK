/*
 * MVKSwapchain.mm
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

#include "MVKSurface.h"
#include "MVKSwapchain.h"
#include "MVKImage.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKWatermark.h"
#include "MVKWatermarkTextureContent.h"
#include "MVKWatermarkShaderSource.h"
#include "mvk_datatypes.h"
#include "MVKLogging.h"

using namespace std;


#pragma mark MVKSwapchain

uint32_t MVKSwapchain::getImageCount() { return (uint32_t)_surfaceImages.size(); }

MVKSwapchainImage* MVKSwapchain::getImage(uint32_t index) { return _surfaceImages[index]; }

VkResult MVKSwapchain::getImages(uint32_t* pCount, VkImage* pSwapchainImages) {

	// Get the number of surface images
	uint32_t imgCnt = getImageCount();

	// If images aren't actually being requested yet, simply update the returned count
	if ( !pSwapchainImages ) {
		*pCount = imgCnt;
		return VK_SUCCESS;
	}

	// Determine how many images we'll return, and return that number
	VkResult result = (*pCount <= imgCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(*pCount, imgCnt);

	// Now populate the images
	for (uint32_t imgIdx = 0; imgIdx < *pCount; imgIdx++) {
		pSwapchainImages[imgIdx] = (VkImage)_surfaceImages[imgIdx];
	}

	return result;
}

VkResult MVKSwapchain::acquireNextImageKHR(uint64_t timeout,
                                           VkSemaphore semaphore,
                                           VkFence fence,
                                           uint32_t* pImageIndex) {
    // Find the image that has the smallest availability measure
    uint32_t minWaitIndex = 0;
    MVKSwapchainImageAvailability minAvailability = { .acquisitionID = numeric_limits<uint64_t>::max(), .waitCount = numeric_limits<uint32_t>::max(), .isAvailable = false };
    for (MVKSwapchainImage* mvkSCImg : _surfaceImages) {
        const MVKSwapchainImageAvailability* currAvailability = mvkSCImg->getAvailability();
//        MVKLogDebug("Comparing availability (isAvailable: %d waitCount: %d, acquisitionID: %d) to (isAvailable: %d waitCount: %d, acquisitionID: %d)",
//                    currAvailability->isAvailable, currAvailability->waitCount, currAvailability->acquisitionID,
//                    minAvailability.isAvailable, minAvailability.waitCount, minAvailability.acquisitionID);
        if (*currAvailability < minAvailability) {
            minAvailability = *currAvailability;
            minWaitIndex = mvkSCImg->getSwapchainIndex();
//            MVKLogDebug("Is smaller! Index: %d", minWaitIndex);
        }
    }
//    MVKLogDebug("Selected MVKSwapchainImage %p, index: %d to trigger semaphore %p and fence %p", _surfaceImages[minWaitIndex], minWaitIndex, semaphore, fence);

    *pImageIndex = minWaitIndex;	// Return the index of the image with the shortest wait

    if (semaphore || fence) {
        MVKSemaphore* mvkSem4 = (MVKSemaphore*)semaphore;
        MVKFence* mvkFence = (MVKFence*)fence;
        _surfaceImages[minWaitIndex]->signalWhenAvailable(mvkSem4, mvkFence);
    } else {
        // Interpret a NULL semaphore to mean that this function itself should block
        // until the image is available. Create temp semaphore and wait on it here.
        VkSemaphoreCreateInfo semaphoreCreateInfo = {
            .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = NULL,
        };
        MVKSemaphore mvkSem4(_device, &semaphoreCreateInfo);
        _surfaceImages[minWaitIndex]->signalWhenAvailable(&mvkSem4, NULL);
        if ( !mvkSem4.wait(timeout) ) { return VK_TIMEOUT; }
    }
    
    return getHasSurfaceSizeChanged() ? VK_SUBOPTIMAL_KHR : VK_SUCCESS;
}

bool MVKSwapchain::getHasSurfaceSizeChanged() {
	return !CGSizeEqualToSize(_mtlLayer.drawableSize, _mtlLayerOrigDrawSize);
}

uint64_t MVKSwapchain::getNextAcquisitionID() { return ++_currentAcquisitionID; }

/**
 * Releases any surfaces that are not currently being displayed,
 * so they can be used by a different swapchain.
 */
void MVKSwapchain::releaseUndisplayedSurfaces() {}


#pragma mark Rendering

// Called automatically when a swapchain image is about to be presented to the surface by the queue.
// Activities include marking the frame interval and rendering the watermark if needed.
void MVKSwapchain::willPresentSurface(id<MTLTexture> mtlTexture, id<MTLCommandBuffer> mtlCmdBuff) {
    markFrameInterval();
    renderWatermark(mtlTexture, mtlCmdBuff);
}

// If the product has not been fully licensed, renders the watermark image to the surface.
void MVKSwapchain::renderWatermark(id<MTLTexture> mtlTexture, id<MTLCommandBuffer> mtlCmdBuff) {
    if (_device->_mvkConfig.displayWatermark) {
        if ( !_licenseWatermark ) {
            _licenseWatermark = new MVKWatermarkRandom(getMTLDevice(),
                                                       __watermarkTextureContent,
                                                       __watermarkTextureWidth,
                                                       __watermarkTextureHeight,
                                                       __watermarkTextureFormat,
                                                       mvkMTLPixelFormatBytesPerRow(__watermarkTextureFormat, __watermarkTextureWidth),
                                                       __watermarkShaderSource);
        }
        _licenseWatermark->render(mtlTexture, mtlCmdBuff, _performanceStatistics.lastFrameInterval);
    } else {
        if (_licenseWatermark) {
            delete _licenseWatermark;
            _licenseWatermark = NULL;
        }
    }
}

// Calculates and remembers the time interval between frames.
void MVKSwapchain::markFrameInterval() {
    if ( !(_device->_mvkConfig.performanceTracking || _licenseWatermark) ) { return; }

    NSTimeInterval prevFrameTime = _lastFrameTime;
    _lastFrameTime = [NSDate timeIntervalSinceReferenceDate];
    _performanceStatistics.lastFrameInterval = _lastFrameTime - prevFrameTime;

    // Low pass filter.
    // y[i] := α * x[i] + (1-α) * y[i-1]  OR
    // y[i] := y[i-1] + α * (x[i] - y[i-1])
    _performanceStatistics.averageFrameInterval += _averageFrameIntervalFilterAlpha * (_performanceStatistics.lastFrameInterval - _performanceStatistics.averageFrameInterval);
    _performanceStatistics.averageFramesPerSecond = 1.0 / _performanceStatistics.averageFrameInterval;

    uint32_t perfLogCntLimit = _device->_mvkConfig.performanceLoggingFrameCount;
    if (perfLogCntLimit > 0) {
        _currentPerfLogFrameCount++;
        if (_currentPerfLogFrameCount >= perfLogCntLimit) {
            MVKLogInfo("Frame interval: %.3f. Avg frame interval: %.3f. FPS: %.3f.",
                       _performanceStatistics.lastFrameInterval,
                       _performanceStatistics.averageFrameInterval,
                       _performanceStatistics.averageFramesPerSecond);
            _currentPerfLogFrameCount = 0;
        }
    }
}

void MVKSwapchain::getPerformanceStatistics(MVKSwapchainPerformance* pSwapchainPerf) {
    if (pSwapchainPerf) { *pSwapchainPerf = _performanceStatistics; }
}


#pragma mark Metal

id<CAMetalDrawable> MVKSwapchain::getNextCAMetalDrawable() {
    id<CAMetalDrawable> nextDrwbl = nil;
    while ( !(nextDrwbl = [_mtlLayer nextDrawable]) ) {
        MVKLogError("Drawable could not be retrieved! Elapsed time: %.6f ms.", mvkGetElapsedMilliseconds());
    }
    return nextDrwbl;
}


#pragma mark Construction

MVKSwapchain::MVKSwapchain(MVKDevice* device,
						   const VkSwapchainCreateInfoKHR* pCreateInfo) : MVKBaseDeviceObject(device) {
	_currentAcquisitionID = 0;

	// If applicable, release any surfaces (not currently being displayed) from the old swapchain.
	MVKSwapchain* oldSwapchain = (MVKSwapchain*)pCreateInfo->oldSwapchain;
	if (oldSwapchain) { oldSwapchain->releaseUndisplayedSurfaces(); }

	// Get the layer underlying the surface view, which must be a CAMetalLayer.
	MVKSurface* mvkSrfc = (MVKSurface*)pCreateInfo->surface;
	_mtlLayer = mvkSrfc->getCAMetalLayer();
	_mtlLayer.device = getMTLDevice();
	_mtlLayer.pixelFormat = mtlPixelFormatFromVkFormat(pCreateInfo->imageFormat);
    _mtlLayer.framebufferOnly = !mvkIsAnyFlagEnabled(pCreateInfo->imageUsage, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                                                                               VK_IMAGE_USAGE_TRANSFER_DST_BIT |
                                                                               VK_IMAGE_USAGE_SAMPLED_BIT |
                                                                               VK_IMAGE_USAGE_STORAGE_BIT));

	// TODO: set additional CAMetalLayer properties before extracting drawables:
	//	- presentsWithTransaction
	//	- drawsAsynchronously
    //  - colorspace (macOS only) Vulkan only supports sRGB colorspace for now.
    //  - wantsExtendedDynamicRangeContent (macOS only)

    initSurfaceImages(pCreateInfo);
    initFrameIntervalTracking();

    _licenseWatermark = NULL;
}

/** Initializes the array of images used for the surfaces of this swapchain. */
void MVKSwapchain::initSurfaceImages(const VkSwapchainCreateInfoKHR* pCreateInfo) {

    _mtlLayerOrigDrawSize = _mtlLayer.updatedDrawableSizeMVK;
    VkExtent2D imgExtent = mvkVkExtent2DFromCGSize(_mtlLayerOrigDrawSize);

    const VkImageCreateInfo imgInfo = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = VK_NULL_HANDLE,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = mvkVkFormatFromMTLPixelFormat(_mtlLayer.pixelFormat),
        .extent = { imgExtent.width, imgExtent.height, 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = pCreateInfo->imageUsage,
        .flags = 0,
    };

    uint32_t imgCnt = MVK_MAX_SWAPCHAIN_SURFACE_IMAGE_COUNT;
    _surfaceImages.reserve(imgCnt);
    for (uint32_t imgIdx = 0; imgIdx < imgCnt; imgIdx++) {
        _surfaceImages.push_back(_device->createSwapchainImage(&imgInfo, this, NULL));
    }

    MVKLogInfo("Created %d swapchain images with initial size (%d, %d).", imgCnt, imgExtent.width, imgExtent.height);
}

// Initialize frame interval tracking, including start time and filtering parameters.
void MVKSwapchain::initFrameIntervalTracking() {
    _performanceStatistics.lastFrameInterval = 0;
    _performanceStatistics.averageFrameInterval = 0;
    _performanceStatistics.averageFramesPerSecond = 0;
    _currentPerfLogFrameCount = 0;

    _lastFrameTime = [NSDate timeIntervalSinceReferenceDate];

    // Establish the alpha parameter of a low-pass filter for averaging frame intervals.
    double RC_over_dt = 10;
    _averageFrameIntervalFilterAlpha = 1.0 / (1 + RC_over_dt);
}

MVKSwapchain::~MVKSwapchain() {
	for (auto& img : _surfaceImages) { _device->destroySwapchainImage(img, NULL); }

    if (_licenseWatermark) { delete _licenseWatermark; }
}

