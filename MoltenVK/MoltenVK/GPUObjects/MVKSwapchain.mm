/*
 * MVKSwapchain.mm
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
#import "CAMetalLayer+MoltenVK.h"
#import "MVKBlockObserver.h"

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
	VkResult result = (*pCount >= imgCnt) ? VK_SUCCESS : VK_INCOMPLETE;
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
										   uint32_t deviceMask,
                                           uint32_t* pImageIndex) {

    if ( getIsSurfaceLost() ) { return VK_ERROR_SURFACE_LOST_KHR; }

    // Find the image that has the smallest availability measure
    uint32_t minWaitIndex = 0;
    MVKSwapchainImageAvailability minAvailability = { .acquisitionID = kMVKUndefinedLargeUInt64,
													  .waitCount = kMVKUndefinedLargeUInt32,
													  .isAvailable = false };
    for (MVKSwapchainImage* mvkSCImg : _surfaceImages) {
        const MVKSwapchainImageAvailability* currAvailability = mvkSCImg->getAvailability();
        if (*currAvailability < minAvailability) {
            minAvailability = *currAvailability;
            minWaitIndex = mvkSCImg->getSwapchainIndex();
        }
    }

    *pImageIndex = minWaitIndex;	// Return the index of the image with the shortest wait
    _surfaceImages[minWaitIndex]->signalWhenAvailable((MVKSemaphore*)semaphore, (MVKFence*)fence);
    return getHasSurfaceSizeChanged() ? VK_ERROR_OUT_OF_DATE_KHR : VK_SUCCESS;
}

bool MVKSwapchain::getHasSurfaceSizeChanged() {
	return !CGSizeEqualToSize(_mtlLayer.naturalDrawableSizeMVK, _mtlLayerOrigDrawSize);
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
    if (_device->_pMVKConfig->displayWatermark) {
        if ( !_licenseWatermark ) {
            _licenseWatermark = new MVKWatermarkRandom(getMTLDevice(),
                                                       __watermarkTextureContent,
                                                       __watermarkTextureWidth,
                                                       __watermarkTextureHeight,
                                                       __watermarkTextureFormat,
                                                       mvkMTLPixelFormatBytesPerRow(__watermarkTextureFormat, __watermarkTextureWidth),
                                                       __watermarkShaderSource);
        }
        _licenseWatermark->render(mtlTexture, mtlCmdBuff, _performanceStatistics.lastFrameInterval / 1000.0);
    } else {
        if (_licenseWatermark) {
            _licenseWatermark->destroy();
            _licenseWatermark = nullptr;
        }
    }
}

// Calculates and remembers the time interval between frames.
void MVKSwapchain::markFrameInterval() {
    if ( !(_device->_pMVKConfig->performanceTracking || _licenseWatermark) ) { return; }

    uint64_t prevFrameTime = _lastFrameTime;
    _lastFrameTime = mvkGetTimestamp();
    _performanceStatistics.lastFrameInterval = mvkGetElapsedMilliseconds(prevFrameTime, _lastFrameTime);

    // Low pass filter.
    // y[i] := α * x[i] + (1-α) * y[i-1]  OR
    // y[i] := y[i-1] + α * (x[i] - y[i-1])
    _performanceStatistics.averageFrameInterval += _averageFrameIntervalFilterAlpha * (_performanceStatistics.lastFrameInterval - _performanceStatistics.averageFrameInterval);
    _performanceStatistics.averageFramesPerSecond = 1000.0 / _performanceStatistics.averageFrameInterval;

// Uncomment for per-frame logging.
//	MVKLogDebug("Frame interval: %.2f ms. Avg frame interval: %.2f ms. Frame number: %d.",
//				_performanceStatistics.lastFrameInterval,
//				_performanceStatistics.averageFrameInterval,
//				_currentPerfLogFrameCount + 1);

    uint32_t perfLogCntLimit = _device->_pMVKConfig->performanceLoggingFrameCount;
    if ((perfLogCntLimit > 0) && (++_currentPerfLogFrameCount >= perfLogCntLimit)) {
		_currentPerfLogFrameCount = 0;
		MVKLogInfo("Frame interval: %.2f ms. Avg frame interval: %.2f ms. Avg FPS: %.2f. Reporting every: %d frames. Elapsed time: %.3f seconds.",
				   _performanceStatistics.lastFrameInterval,
				   _performanceStatistics.averageFrameInterval,
				   _performanceStatistics.averageFramesPerSecond,
				   perfLogCntLimit,
				   mvkGetElapsedMilliseconds() / 1000.0);
	}
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
						   const VkSwapchainCreateInfoKHR* pCreateInfo) : MVKBaseDeviceObject(device), _surfaceLost(false) {
	_currentAcquisitionID = 0;

	// If applicable, release any surfaces (not currently being displayed) from the old swapchain.
	MVKSwapchain* oldSwapchain = (MVKSwapchain*)pCreateInfo->oldSwapchain;
	if (oldSwapchain) { oldSwapchain->releaseUndisplayedSurfaces(); }

	uint32_t imgCnt = mvkClamp(pCreateInfo->minImageCount,
							   _device->_pMetalFeatures->minSwapchainImageCount,
							   _device->_pMetalFeatures->maxSwapchainImageCount);
	initCAMetalLayer(pCreateInfo, imgCnt);
    initSurfaceImages(pCreateInfo, imgCnt);		// After initCAMetalLayer()
    initFrameIntervalTracking();

    _licenseWatermark = NULL;
}

// Initializes the CAMetalLayer underlying the surface of this swapchain.
void MVKSwapchain::initCAMetalLayer(const VkSwapchainCreateInfoKHR* pCreateInfo, uint32_t imgCnt) {

	MVKSurface* mvkSrfc = (MVKSurface*)pCreateInfo->surface;
	if ( !mvkSrfc->getCAMetalLayer() ) {
		setConfigurationResult(mvkSrfc->getConfigurationResult());
		_surfaceLost = true;
		return;
	}

	_mtlLayer = mvkSrfc->getCAMetalLayer();
	_mtlLayer.device = getMTLDevice();
	_mtlLayer.pixelFormat = getMTLPixelFormatFromVkFormat(pCreateInfo->imageFormat);
	_mtlLayer.maximumDrawableCountMVK = imgCnt;
	_mtlLayer.displaySyncEnabledMVK = (pCreateInfo->presentMode != VK_PRESENT_MODE_IMMEDIATE_KHR);
	_mtlLayer.magnificationFilter = _device->_pMVKConfig->swapchainMagFilterUseNearest ? kCAFilterNearest : kCAFilterLinear;
	_mtlLayer.framebufferOnly = !mvkIsAnyFlagEnabled(pCreateInfo->imageUsage, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
																			   VK_IMAGE_USAGE_TRANSFER_DST_BIT |
																			   VK_IMAGE_USAGE_SAMPLED_BIT |
																			   VK_IMAGE_USAGE_STORAGE_BIT));
	_mtlLayerOrigDrawSize = _mtlLayer.updatedDrawableSizeMVK;

	// TODO: set additional CAMetalLayer properties before extracting drawables:
	//	- presentsWithTransaction
	//	- drawsAsynchronously
	//  - colorspace (macOS only) Vulkan only supports sRGB colorspace for now.
	//  - wantsExtendedDynamicRangeContent (macOS only)

	if ( [_mtlLayer.delegate isKindOfClass: [PLATFORM_VIEW_CLASS class]] ) {
		// Sometimes, the owning view can replace its CAMetalLayer. In that case, the client
		// needs to recreate the swapchain, or no content will be displayed.
		_layerObserver = [MVKBlockObserver observerWithBlock: ^(NSString* path, id, NSDictionary*, void*) {
			if ( ![path isEqualTo: @"layer"] ) { return; }
			this->_surfaceLost = true;
			[this->_layerObserver release];
			this->_layerObserver = nil;
		} forObject: _mtlLayer.delegate atKeyPath: @"layer"];
	}
}

// Initializes the array of images used for the surface of this swapchain.
// The CAMetalLayer should already be initialized when this is called.
void MVKSwapchain::initSurfaceImages(const VkSwapchainCreateInfoKHR* pCreateInfo, uint32_t imgCnt) {

    if ( getIsSurfaceLost() ) {
        return;
    }

    VkExtent2D imgExtent = mvkVkExtent2DFromCGSize(_mtlLayerOrigDrawSize);

    VkImageCreateInfo imgInfo = {
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

	if (mvkAreFlagsEnabled(pCreateInfo->flags, VK_SWAPCHAIN_CREATE_MUTABLE_FORMAT_BIT_KHR)) {
		mvkEnableFlag(imgInfo.flags, VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT | VK_IMAGE_CREATE_EXTENDED_USAGE_BIT);
	}

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

	_lastFrameTime = mvkGetTimestamp();

    // Establish the alpha parameter of a low-pass filter for averaging frame intervals.
    double RC_over_dt = 10.0;
    _averageFrameIntervalFilterAlpha = 1.0 / (1.0 + RC_over_dt);
}

MVKSwapchain::~MVKSwapchain() {
	for (auto& img : _surfaceImages) { _device->destroySwapchainImage(img, NULL); }

    if (_licenseWatermark) { _licenseWatermark->destroy(); }
    [this->_layerObserver release];
}

