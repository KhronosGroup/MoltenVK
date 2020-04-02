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

#include <libkern/OSByteOrder.h>

using namespace std;


#pragma mark MVKSwapchain

bool MVKSwapchainImageAvailability::operator< (const MVKSwapchainImageAvailability& rhs) const {
	if (  isAvailable && !rhs.isAvailable) { return true; }
	if ( !isAvailable &&  rhs.isAvailable) { return false; }

	if (waitCount < rhs.waitCount) { return true; }
	if (waitCount > rhs.waitCount) { return false; }

	return acquisitionID < rhs.acquisitionID;
}

void MVKSwapchain::propogateDebugName() {
	if (_debugName) {
		size_t imgCnt = _surfaceImages.size();
		for (size_t imgIdx = 0; imgIdx < imgCnt; imgIdx++) {
			NSString* nsName = [[NSString alloc] initWithFormat: @"%@(%lu)", _debugName, imgIdx];	// temp retain
			_surfaceImages[imgIdx]->setDebugName(nsName.UTF8String);
			[nsName release];																		// release temp string
		}
	}
}

uint32_t MVKSwapchain::getImageCount() { return (uint32_t)_imageAvailability.size(); }

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
    for (uint32_t imgIdx = 0; imgIdx < _imageAvailability.size(); imgIdx++) {
        const Availability& avail = _imageAvailability[imgIdx];
        if (avail.status < minAvailability) {
            minAvailability = avail.status;
            minWaitIndex = imgIdx;
        }
    }

    *pImageIndex = minWaitIndex;	// Return the index of the image with the shortest wait
    signalWhenAvailable(minWaitIndex, (MVKSemaphore*)semaphore, (MVKFence*)fence);
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

// Makes an image available for acquisition by the app.
// If any semaphores are waiting to be signaled when this image becomes available, the
// earliest semaphore is signaled, and this image remains unavailable for other uses.
void MVKSwapchain::makeAvailable(uint32_t imgIdx) {
	lock_guard<mutex> lock(_availabilityLock);
	auto& availability = _imageAvailability[imgIdx].status;

	// Mark when this event happened, relative to that of other images
	availability.acquisitionID = getNextAcquisitionID();

	// Mark this image as available if no semaphores or fences are waiting to be signaled.
	availability.isAvailable = _imageAvailability[imgIdx].signalers.empty();

	MVKSwapchainSignaler signaler;
	if (availability.isAvailable) {
		// If this image is available, signal the semaphore and fence that were associated
		// with the last time this image was acquired while available. This is a workaround for
		// when an app uses a single semaphore or fence for more than one swapchain image.
		// Becuase the semaphore or fence will be signaled by more than one image, it will
		// get out of sync, and the final use of the image would not be signaled as a result.
		signaler = _imageAvailability[imgIdx].preSignaled;
	} else {
		// If this image is not yet available, extract and signal the first semaphore and fence.
		auto& imgSignalers = _imageAvailability[imgIdx].signalers;
		auto sigIter = imgSignalers.begin();
		signaler = *sigIter;
		imgSignalers.erase(sigIter);
	}

	// Signal the semaphore and fence, and let them know they are no longer being tracked.
	signal(signaler, nil);
	unmarkAsTracked(signaler);

//	MVKLogDebug("Signaling%s swapchain image %p semaphore %p from present, with %lu remaining semaphores.", (_availability.isAvailable ? " pre-signaled" : ""), this, signaler.first, _availabilitySignalers.size());
}

void MVKSwapchain::signalWhenAvailable(uint32_t imageIndex, MVKSemaphore* semaphore, MVKFence* fence) {
	lock_guard<mutex> lock(_availabilityLock);
	auto signaler = make_pair(semaphore, fence);
	auto& availability = _imageAvailability[imageIndex].status;
	if (availability.isAvailable) {
		availability.isAvailable = false;

		// If signalling through a MTLEvent, use an ephemeral MTLCommandBuffer.
		// Another option would be to use MTLSharedEvent in MVKSemaphore, but that might
		// impose unacceptable performance costs to handle this particular case.
		@autoreleasepool {
			MVKSemaphore* mvkSem = signaler.first;
			id<MTLCommandBuffer> mtlCmdBuff = (mvkSem && mvkSem->isUsingCommandEncoding()
											   ? [_device->getAnyQueue()->getMTLCommandQueue() commandBufferWithUnretainedReferences]
											   : nil);
			signal(signaler, mtlCmdBuff);
			[mtlCmdBuff commit];
		}

		_imageAvailability[imageIndex].preSignaled = signaler;
	} else {
		_imageAvailability[imageIndex].signalers.push_back(signaler);
	}
	markAsTracked(signaler);

//	MVKLogDebug("%s swapchain image %p semaphore %p in acquire with %lu other semaphores.", (_availability.isAvailable ? "Signaling" : "Tracking"), this, semaphore, _availabilitySignalers.size());
}

// Signal either or both of the semaphore and fence in the specified tracker pair.
void MVKSwapchain::signal(MVKSwapchainSignaler& signaler, id<MTLCommandBuffer> mtlCmdBuff) {
	if (signaler.first) { signaler.first->encodeSignal(mtlCmdBuff); }
	if (signaler.second) { signaler.second->signal(); }
}

// If present, signal the semaphore for the first waiter for the given image.
void MVKSwapchain::signalPresentationSemaphore(uint32_t imgIdx, id<MTLCommandBuffer> mtlCmdBuff) {
	lock_guard<mutex> lock(_availabilityLock);
	auto& imgSignalers = _imageAvailability[imgIdx].signalers;
	if ( !imgSignalers.empty() ) {
		MVKSemaphore* mvkSem = imgSignalers.front().first;
		if (mvkSem) { mvkSem->encodeSignal(mtlCmdBuff); }
	}
}

// Tell the semaphore and fence that they are being tracked for future signaling.
void MVKSwapchain::markAsTracked(MVKSwapchainSignaler& signaler) {
	if (signaler.first) { signaler.first->retain(); }
	if (signaler.second) { signaler.second->retain(); }
}

// Tell the semaphore and fence that they are no longer being tracked for future signaling.
void MVKSwapchain::unmarkAsTracked(MVKSwapchainSignaler& signaler) {
	if (signaler.first) { signaler.first->release(); }
	if (signaler.second) { signaler.second->release(); }
}


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
                                                       getPixelFormats()->getMTLPixelFormatBytesPerRow(__watermarkTextureFormat, __watermarkTextureWidth),
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
						   const VkSwapchainCreateInfoKHR* pCreateInfo) : MVKVulkanAPIDeviceObject(device), _surfaceLost(false) {
	_currentAcquisitionID = 0;
	_layerObserver = nil;

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
	_mtlLayer.pixelFormat = getPixelFormats()->getMTLPixelFormatFromVkFormat(pCreateInfo->imageFormat);
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

    if ( getIsSurfaceLost() ) {
        return;
    }

    VkExtent2D imgExtent = mvkVkExtent2DFromCGSize(_mtlLayerOrigDrawSize);

    VkImageCreateInfo imgInfo = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = VK_NULL_HANDLE,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = getPixelFormats()->getVkFormatFromMTLPixelFormat(_mtlLayer.pixelFormat),
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

	_imageAvailability.resize(imgCnt);
    for (uint32_t imgIdx = 0; imgIdx < imgCnt; imgIdx++) {
        _surfaceImages.push_back(_device->createSwapchainImage(&imgInfo, this, imgIdx, NULL));
        _imageAvailability[imgIdx].status.acquisitionID = getNextAcquisitionID();
        _imageAvailability[imgIdx].status.isAvailable = true;
        _imageAvailability[imgIdx].preSignaled = make_pair(nullptr, nullptr);
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

