/*
 * MVKSwapchain.mm
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

#include "MVKSurface.h"
#include "MVKSwapchain.h"
#include "MVKImage.h"
#include "MVKQueue.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKWatermark.h"
#include "MVKWatermarkTextureContent.h"
#include "MVKWatermarkShaderSource.h"
#include "mvk_datatypes.hpp"
#include "MVKLogging.h"
#import "CAMetalLayer+MoltenVK.h"
#import "MVKBlockObserver.h"

#if MVK_IOS
#	include <UIKit/UIScreen.h>
#endif

#include <libkern/OSByteOrder.h>

using namespace std;


#pragma mark -
#pragma mark MVKSwapchain

void MVKSwapchain::propogateDebugName() {
	if (_debugName) {
		size_t imgCnt = _presentableImages.size();
		for (size_t imgIdx = 0; imgIdx < imgCnt; imgIdx++) {
			NSString* nsName = [[NSString alloc] initWithFormat: @"%@(%lu)", _debugName, imgIdx];	// temp retain
			_presentableImages[imgIdx]->setDebugName(nsName.UTF8String);
			[nsName release];																		// release temp string
		}
	}
}

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
		pSwapchainImages[imgIdx] = (VkImage)_presentableImages[imgIdx];
	}

	return result;
}

VkResult MVKSwapchain::acquireNextImageKHR(uint64_t timeout,
										   VkSemaphore semaphore,
										   VkFence fence,
										   uint32_t deviceMask,
										   uint32_t* pImageIndex) {

	if ( getIsSurfaceLost() ) { return VK_ERROR_SURFACE_LOST_KHR; }

	// Find the image that has the shortest wait by finding the smallest availability measure.
	MVKPresentableSwapchainImage* minWaitImage = nullptr;
	MVKSwapchainImageAvailability minAvailability = { kMVKUndefinedLargeUInt64, false };
	uint32_t imgCnt = getImageCount();
	for (uint32_t imgIdx = 0; imgIdx < imgCnt; imgIdx++) {
		auto* img = getPresentableImage(imgIdx);
		auto imgAvail = img->getAvailability();
		if (imgAvail < minAvailability) {
			minAvailability = imgAvail;
			minWaitImage = img;
		}
	}

	// Return the index of the image with the shortest wait,
	// and signal the semaphore and fence when it's available
	*pImageIndex = minWaitImage->_swapchainIndex;
	minWaitImage->acquireAndSignalWhenAvailable((MVKSemaphore*)semaphore, (MVKFence*)fence);

	return getSurfaceStatus();
}

uint64_t MVKSwapchain::getNextAcquisitionID() { return ++_currentAcquisitionID; }

// Releases any surfaces that are not currently being displayed,
// so they can be used by a different swapchain.
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
                                                       getPixelFormats()->getBytesPerRow(__watermarkTextureFormat, __watermarkTextureWidth),
                                                       __watermarkShaderSource);
        }
		_licenseWatermark->render(mtlTexture, mtlCmdBuff, 0.02f);
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

	if (prevFrameTime == 0) { return; }		// First frame starts at first presentation

	_device->addActivityPerformance(_device->_performanceStatistics.queue.frameInterval, prevFrameTime, _lastFrameTime);

	uint32_t perfLogCntLimit = _device->_pMVKConfig->performanceLoggingFrameCount;
	if ((perfLogCntLimit > 0) && (++_currentPerfLogFrameCount >= perfLogCntLimit)) {
		_currentPerfLogFrameCount = 0;
		MVKLogInfo("Performance statistics reporting every: %d frames, avg FPS: %.2f, elapsed time: %.3f seconds:",
				   perfLogCntLimit,
				   (1000.0 / _device->_performanceStatistics.queue.frameInterval.averageDuration),
				   mvkGetElapsedMilliseconds() / 1000.0);
		_device->logPerformanceSummary();
	}
}

#if MVK_MACOS
struct CIE1931XY {
	uint16_t x;
	uint16_t y;
} __attribute__((packed));

// According to D.3.28:
//   "[x and y] specify the normalized x and y chromaticity coordinates, respectively...
//    in normalized increments of 0.00002."
static inline uint16_t FloatToCIE1931Unorm(float x) { return OSSwapHostToBigInt16((uint16_t)(x * 100000 / 2)); }
static inline CIE1931XY VkXYColorEXTToCIE1931XY(VkXYColorEXT xy) {
	return { FloatToCIE1931Unorm(xy.x), FloatToCIE1931Unorm(xy.y) };
}
#endif

void MVKSwapchain::setHDRMetadataEXT(const VkHdrMetadataEXT& metadata) {
#if MVK_MACOS
	// We were given metadata as floats, but CA wants it as specified in H.265.
	// More specifically, it wants "Mastering display colour volume" (D.2.28) and
	// "Content light level information" (D.2.35) SEI messages, with big-endian
	// integers. We have to convert.
	struct ColorVolumeSEI {
		CIE1931XY display_primaries[3];  // Green, blue, red
		CIE1931XY white_point;
		uint32_t max_display_mastering_luminance;
		uint32_t min_display_mastering_luminance;
	} __attribute__((packed));
	struct LightLevelSEI {
		uint16_t max_content_light_level;
		uint16_t max_pic_average_light_level;
	} __attribute__((packed));
	ColorVolumeSEI colorVol;
	LightLevelSEI lightLevel;
	// According to D.3.28:
	//   "For describing mastering displays that use red, green, and blue colour
	//    primaries, it is suggested that index value c equal to 0 should correspond
	//    to the green primary, c equal to 1 should correspond to the blue primary
	//    and c equal to 2 should correspond to the red colour primary."
	colorVol.display_primaries[0] = VkXYColorEXTToCIE1931XY(metadata.displayPrimaryGreen);
	colorVol.display_primaries[1] = VkXYColorEXTToCIE1931XY(metadata.displayPrimaryBlue);
	colorVol.display_primaries[2] = VkXYColorEXTToCIE1931XY(metadata.displayPrimaryRed);
	colorVol.white_point = VkXYColorEXTToCIE1931XY(metadata.whitePoint);
	// Later in D.3.28:
	//   "max_display_mastering_luminance and min_display_mastering_luminance specify
	//    the nominal maximum and minimum display luminance, respectively, of the mastering
	//    display in units of 0.0001 candelas [sic] per square metre."
	// N.B. 1 nit = 1 cd/m^2
	colorVol.max_display_mastering_luminance = OSSwapHostToBigInt32((uint32_t)(metadata.maxLuminance * 10000));
	colorVol.min_display_mastering_luminance = OSSwapHostToBigInt32((uint32_t)(metadata.minLuminance * 10000));
	lightLevel.max_content_light_level = OSSwapHostToBigInt16((uint16_t)metadata.maxContentLightLevel);
	lightLevel.max_pic_average_light_level = OSSwapHostToBigInt16((uint16_t)metadata.maxFrameAverageLightLevel);
	NSData* colorVolData = [NSData dataWithBytes: &colorVol length: sizeof(colorVol)];
	NSData* lightLevelData = [NSData dataWithBytes: &lightLevel length: sizeof(lightLevel)];
	CAEDRMetadata* caMetadata = [CAEDRMetadata HDR10MetadataWithDisplayInfo: colorVolData
																contentInfo: lightLevelData
														 opticalOutputScale: 1];
	_mtlLayer.EDRMetadata = caMetadata;
	[caMetadata release];
	[colorVolData release];
	[lightLevelData release];
	_mtlLayer.wantsExtendedDynamicRangeContent = YES;
#endif
}


#pragma mark Construction

MVKSwapchain::MVKSwapchain(MVKDevice* device,
						   const VkSwapchainCreateInfoKHR* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device),
	_surfaceLost(false),
	_currentAcquisitionID(0),
	_layerObserver(nil),
	_currentPerfLogFrameCount(0),
	_lastFrameTime(0),
	_licenseWatermark(nil),
	_presentHistoryCount(0),
	_presentHistoryIndex(0),
	_presentHistoryHeadIndex(0) {

	memset(_presentTimingHistory, 0, sizeof(_presentTimingHistory));
	// If applicable, release any surfaces (not currently being displayed) from the old swapchain.
	MVKSwapchain* oldSwapchain = (MVKSwapchain*)pCreateInfo->oldSwapchain;
	if (oldSwapchain) { oldSwapchain->releaseUndisplayedSurfaces(); }

	uint32_t imgCnt = mvkClamp(pCreateInfo->minImageCount,
							   _device->_pMetalFeatures->minSwapchainImageCount,
							   _device->_pMetalFeatures->maxSwapchainImageCount);
	initCAMetalLayer(pCreateInfo, imgCnt);
    initSurfaceImages(pCreateInfo, imgCnt);		// After initCAMetalLayer()
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
	_mtlLayer.pixelFormat = getPixelFormats()->getMTLPixelFormat(pCreateInfo->imageFormat);
	_mtlLayer.maximumDrawableCountMVK = imgCnt;
	_mtlLayer.displaySyncEnabledMVK = (pCreateInfo->presentMode != VK_PRESENT_MODE_IMMEDIATE_KHR);
	_mtlLayer.magnificationFilter = _device->_pMVKConfig->swapchainMagFilterUseNearest ? kCAFilterNearest : kCAFilterLinear;
	_mtlLayer.framebufferOnly = !mvkIsAnyFlagEnabled(pCreateInfo->imageUsage, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
																			   VK_IMAGE_USAGE_TRANSFER_DST_BIT |
																			   VK_IMAGE_USAGE_SAMPLED_BIT |
																			   VK_IMAGE_USAGE_STORAGE_BIT));
	if (pCreateInfo->compositeAlpha != VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR) {
		_mtlLayer.opaque = pCreateInfo->compositeAlpha == VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
	}

	switch (pCreateInfo->imageColorSpace) {
		case VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
			break;
		case VK_COLOR_SPACE_DISPLAY_P3_NONLINEAR_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
			_mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_EXTENDED_SRGB_LINEAR_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
			_mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_EXTENDED_SRGB_NONLINEAR_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
			_mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_DISPLAY_P3_LINEAR_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
			_mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_DCI_P3_NONLINEAR_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceDCIP3);
			_mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_BT709_NONLINEAR_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
			break;
		case VK_COLOR_SPACE_BT2020_LINEAR_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearITUR_2020);
			_mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_HDR10_ST2084_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020_PQ_EOTF);
			_mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_HDR10_HLG_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020_HLG);
			_mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_ADOBERGB_NONLINEAR_EXT:
			_mtlLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceAdobeRGB1998);
			break;
		case VK_COLOR_SPACE_PASS_THROUGH_EXT:
		default:
			// Nothing - the default is not to do color matching.
			break;
	}
	_mtlLayerOrigDrawSize = _mtlLayer.updatedDrawableSizeMVK;

	// TODO: set additional CAMetalLayer properties before extracting drawables:
	//	- presentsWithTransaction
	//	- drawsAsynchronously

	if ( [_mtlLayer.delegate isKindOfClass: [PLATFORM_VIEW_CLASS class]] ) {
		// Sometimes, the owning view can replace its CAMetalLayer. In that case, the client
		// needs to recreate the swapchain, or no content will be displayed.
		_layerObserver = [MVKBlockObserver observerWithBlock: ^(NSString* path, id, NSDictionary*, void*) {
			if ( ![path isEqualToString: @"layer"] ) { return; }
			this->_surfaceLost = true;
			[this->_layerObserver release];
			this->_layerObserver = nil;
		} forObject: _mtlLayer.delegate atKeyPath: @"layer"];
	}
}

// Initializes the array of images used for the surface of this swapchain.
// The CAMetalLayer should already be initialized when this is called.
void MVKSwapchain::initSurfaceImages(const VkSwapchainCreateInfoKHR* pCreateInfo, uint32_t imgCnt) {

    if ( getIsSurfaceLost() ) { return; }

    VkExtent2D imgExtent = mvkVkExtent2DFromCGSize(_mtlLayerOrigDrawSize);

    VkImageCreateInfo imgInfo = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = VK_NULL_HANDLE,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = getPixelFormats()->getVkFormat(_mtlLayer.pixelFormat),
        .extent = { imgExtent.width, imgExtent.height, 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = pCreateInfo->imageUsage,
        .flags = 0,
    };

	if (mvkAreAllFlagsEnabled(pCreateInfo->flags, VK_SWAPCHAIN_CREATE_MUTABLE_FORMAT_BIT_KHR)) {
		mvkEnableFlags(imgInfo.flags, VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT | VK_IMAGE_CREATE_EXTENDED_USAGE_BIT);
	}
	if (mvkAreAllFlagsEnabled(pCreateInfo->flags, VK_SWAPCHAIN_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT_KHR)) {
		// We don't really support this, but set the flag anyway.
		mvkEnableFlags(imgInfo.flags, VK_IMAGE_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT);
	}

	for (uint32_t imgIdx = 0; imgIdx < imgCnt; imgIdx++) {
		_presentableImages.push_back(_device->createPresentableSwapchainImage(&imgInfo, this, imgIdx, NULL));
	}

    MVKLogInfo("Created %d swapchain images with initial size (%d, %d).", imgCnt, imgExtent.width, imgExtent.height);
}

VkResult MVKSwapchain::getRefreshCycleDuration(VkRefreshCycleDurationGOOGLE *pRefreshCycleDuration) {
#if MVK_IOS
	NSInteger framesPerSecond = [UIScreen mainScreen].maximumFramesPerSecond;
#endif
#if MVK_MACOS
	// TODO: hook this up for macOS, probably need to use CGDisplayModeGetRefeshRate
	NSInteger framesPerSecond = 60;
#endif
	pRefreshCycleDuration->refreshDuration = 1e9 / ( uint64_t ) framesPerSecond;
	return VK_SUCCESS;
}

VkResult MVKSwapchain::getPastPresentationTiming(uint32_t *pCount, VkPastPresentationTimingGOOGLE *pPresentationTimings) {
	std::lock_guard<std::mutex> lock(_presentHistoryLock);
	if (pCount && pPresentationTimings == nullptr) {
		*pCount = _presentHistoryCount;
	} else if (pPresentationTimings) {
		uint32_t index = _presentHistoryHeadIndex;
		uint32_t countRemaining = std::min(_presentHistoryCount, *pCount);
		uint32_t outIndex = 0;
		while (countRemaining > 0) {
			pPresentationTimings[outIndex] = _presentTimingHistory[index];
			countRemaining--;
			index = (index + 1) % kMaxPresentationHistory;
			outIndex++;
		}
	}
	return VK_SUCCESS;
}

void MVKSwapchain::recordPresentTime(uint32_t presentID, uint64_t desiredPresentTime, uint64_t actualPresentTime) {
	std::lock_guard<std::mutex> lock(_presentHistoryLock);
	if (_presentHistoryCount < kMaxPresentationHistory) {
		_presentHistoryCount++;
		_presentHistoryHeadIndex = 0;
	} else {
		_presentHistoryHeadIndex = (_presentHistoryHeadIndex + 1) % kMaxPresentationHistory;
	}
	_presentTimingHistory[_presentHistoryIndex].presentID = presentID;
	_presentTimingHistory[_presentHistoryIndex].desiredPresentTime = desiredPresentTime;
	_presentTimingHistory[_presentHistoryIndex].actualPresentTime = actualPresentTime;
	// These details are not available in Metal
	_presentTimingHistory[_presentHistoryIndex].earliestPresentTime = actualPresentTime;
	_presentTimingHistory[_presentHistoryIndex].presentMargin = 0;
	_presentHistoryIndex = (_presentHistoryIndex + 1) % kMaxPresentationHistory;
}

MVKSwapchain::~MVKSwapchain() {
	for (auto& img : _presentableImages) { _device->destroyPresentableSwapchainImage(img, NULL); }

    if (_licenseWatermark) { _licenseWatermark->destroy(); }
    [this->_layerObserver release];
}

