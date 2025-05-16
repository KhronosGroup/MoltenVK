/*
 * MVKSwapchain.mm
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
#include <libkern/OSByteOrder.h>

#import "CAMetalLayer+MoltenVK.h"
#import "MVKBlockObserver.h"


using namespace std;


#pragma mark -
#pragma mark MVKSwapchain

void MVKSwapchain::propagateDebugName() {
	if (_debugName) {
		size_t imgCnt = _presentableImages.size();
		for (size_t imgIdx = 0; imgIdx < imgCnt; imgIdx++) {
			_presentableImages[imgIdx]->setDebugName([NSString stringWithFormat: @"%@(%lu)", _debugName, imgIdx].UTF8String);
		}
	}
}

CAMetalLayer* MVKSwapchain::getCAMetalLayer() { return _surface->getCAMetalLayer(); }

bool MVKSwapchain::isHeadless() { return _surface->isHeadless(); }

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

VkResult MVKSwapchain::acquireNextImage(uint64_t timeout,
										VkSemaphore semaphore,
										VkFence fence,
										uint32_t deviceMask,
										uint32_t* pImageIndex) {

	if ( _device->getConfigurationResult() != VK_SUCCESS ) { return _device->getConfigurationResult(); }
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
	VkResult rslt = minWaitImage->acquireAndSignalWhenAvailable((MVKSemaphore*)semaphore, (MVKFence*)fence);
	return rslt ? rslt : getSurfaceStatus();
}

VkResult MVKSwapchain::releaseImages(const VkReleaseSwapchainImagesInfoEXT* pReleaseInfo) {
	for (uint32_t imgIdxIdx = 0; imgIdxIdx < pReleaseInfo->imageIndexCount; imgIdxIdx++) {
		getPresentableImage(pReleaseInfo->pImageIndices[imgIdxIdx])->makeAvailable();
	}

	return _surface->getConfigurationResult();
}

uint64_t MVKSwapchain::getNextAcquisitionID() { return ++_currentAcquisitionID; }

bool MVKSwapchain::getIsSurfaceLost() {
	VkResult surfRslt = _surface->getConfigurationResult();
	setConfigurationResult(surfRslt);
	return surfRslt != VK_SUCCESS;
}

VkResult MVKSwapchain::getSurfaceStatus() {
	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }
	if (getIsSurfaceLost()) { return VK_ERROR_SURFACE_LOST_KHR; }
	if ( !hasOptimalSurface() ) { return VK_SUBOPTIMAL_KHR; }
	return VK_SUCCESS;
}

// This swapchain is optimally sized for the surface if the app has specified deliberate
// swapchain scaling, or if the surface is headless, or if the surface extent has not changed 
// since the swapchain was created, and the surface will not need to be scaled when composited.
bool MVKSwapchain::hasOptimalSurface() {
	if (_isDeliberatelyScaled || isHeadless()) { return true; }

	VkExtent2D surfExtent = _surface->getExtent();
	return (mvkVkExtent2DsAreEqual(surfExtent, _imageExtent) &&
			mvkVkExtent2DsAreEqual(surfExtent, _surface->getNaturalExtent()));
}


#pragma mark Rendering

// Renders the watermark image to the surface.
void MVKSwapchain::renderWatermark(id<MTLTexture> mtlTexture, id<MTLCommandBuffer> mtlCmdBuff) {
    if (getMVKConfig().displayWatermark) {
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
// Not threadsafe. Ensure this is called from a threadsafe environment.
void MVKSwapchain::markFrameInterval() {
	uint64_t prevFrameTime = _lastFrameTime;
	_lastFrameTime = mvkGetTimestamp();

	if (prevFrameTime == 0) { return; }		// First frame starts at first presentation

	addPerformanceInterval(getPerformanceStats().queue.frameInterval, prevFrameTime, _lastFrameTime, true);

	auto& mvkCfg = getMVKConfig();
	bool shouldLogOnFrames = mvkCfg.performanceTracking && mvkCfg.activityPerformanceLoggingStyle == MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_FRAME_COUNT;
	if (shouldLogOnFrames && (mvkCfg.performanceLoggingFrameCount > 0) && (++_currentPerfLogFrameCount >= mvkCfg.performanceLoggingFrameCount)) {
		_currentPerfLogFrameCount = 0;
		MVKLogInfo("Performance statistics reporting every: %d frames, avg FPS: %.2f, elapsed time: %.3f seconds:",
				   mvkCfg.performanceLoggingFrameCount,
				   (1000.0 / getPerformanceStats().queue.frameInterval.average),
				   mvkGetElapsedMilliseconds() / 1000.0);
		if (getMVKConfig().activityPerformanceLoggingStyle == MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_FRAME_COUNT) {
			_device->logPerformanceSummary();
		}
	}
}

VkResult MVKSwapchain::getRefreshCycleDuration(VkRefreshCycleDurationGOOGLE *pRefreshCycleDuration) {
	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }

#if MVK_MACOS && !MVK_MACCAT
    auto* screen = getCAMetalLayer().screenMVK;        // Will be nil if headless
	double framesPerSecond = 60;
	if (screen) {
		CGDirectDisplayID displayId = [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue];
		CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayId);
		framesPerSecond = CGDisplayModeGetRefreshRate(mode);
		CGDisplayModeRelease(mode);
#if MVK_XCODE_13
		if (framesPerSecond == 0 && [screen respondsToSelector: @selector(maximumFramesPerSecond)])
			framesPerSecond = [screen maximumFramesPerSecond];
#endif
		// Builtin panels, e.g., on MacBook, report a zero refresh rate.
		if (framesPerSecond == 0)
			framesPerSecond = 60.0;
	}
#elif MVK_IOS_OR_TVOS || MVK_MACCAT
    auto* screen = getCAMetalLayer().screenMVK;        // Will be nil if headless
	NSInteger framesPerSecond = 60;
	if ([screen respondsToSelector: @selector(maximumFramesPerSecond)]) {
		framesPerSecond = screen.maximumFramesPerSecond;
	}
#elif MVK_VISIONOS
	NSInteger framesPerSecond = 90;		// TODO: See if this can be obtained from OS instead
#endif

	pRefreshCycleDuration->refreshDuration = (uint64_t)1e9 / framesPerSecond;
	return VK_SUCCESS;
}

VkResult MVKSwapchain::getPastPresentationTiming(uint32_t *pCount, VkPastPresentationTimingGOOGLE *pPresentationTimings) {
	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }

	VkResult res = VK_SUCCESS;

	std::lock_guard<std::mutex> lock(_presentHistoryLock);
	if (pPresentationTimings == nullptr) {
		*pCount = _presentHistoryCount;
	} else {
		uint32_t countRemaining = std::min(_presentHistoryCount, *pCount);
		uint32_t outIndex = 0;

		res = (*pCount >= _presentHistoryCount) ? VK_SUCCESS : VK_INCOMPLETE;
		*pCount = countRemaining;

		while (countRemaining > 0) {
			pPresentationTimings[outIndex] = _presentTimingHistory[_presentHistoryHeadIndex];
			countRemaining--;
			_presentHistoryCount--;
			_presentHistoryHeadIndex = (_presentHistoryHeadIndex + 1) % kMaxPresentationHistory;
			outIndex++;
		}
	}

	return res;
}

VkResult MVKSwapchain::waitForPresent(uint64_t presentId, uint64_t timeout) {
	std::unique_lock lock(_currentPresentIdMutex);
	const auto success = _currentPresentIdCondVar.wait_for(lock, std::chrono::nanoseconds(timeout), [this, presentId] {
		return _currentPresentId >= presentId || getConfigurationResult() == VK_ERROR_OUT_OF_DATE_KHR;
	});
	if (getConfigurationResult() == VK_ERROR_OUT_OF_DATE_KHR) return VK_ERROR_OUT_OF_DATE_KHR;
	return success ? VK_SUCCESS : VK_TIMEOUT;
}

void MVKSwapchain::beginPresentation(const MVKImagePresentInfo& presentInfo) {
	_unpresentedImageCount++;
}

void MVKSwapchain::endPresentation(const MVKImagePresentInfo& presentInfo, uint64_t beginPresentTime, uint64_t actualPresentTime) {
	_unpresentedImageCount--;

	std::lock_guard<std::mutex> lock(_presentHistoryLock);

	markFrameInterval();
	if (_presentHistoryCount < kMaxPresentationHistory) {
		_presentHistoryCount++;
	} else {
		_presentHistoryHeadIndex = (_presentHistoryHeadIndex + 1) % kMaxPresentationHistory;
	}

	_presentTimingHistory[_presentHistoryIndex].presentID = presentInfo.presentIDGoogle;
	_presentTimingHistory[_presentHistoryIndex].desiredPresentTime = presentInfo.desiredPresentTime;
	_presentTimingHistory[_presentHistoryIndex].actualPresentTime = actualPresentTime;
	// These details are not available in Metal, but can estimate earliestPresentTime by using actualPresentTime instead
	_presentTimingHistory[_presentHistoryIndex].earliestPresentTime = actualPresentTime;
	_presentTimingHistory[_presentHistoryIndex].presentMargin = actualPresentTime > beginPresentTime ? actualPresentTime - beginPresentTime : 0;
	_presentHistoryIndex = (_presentHistoryIndex + 1) % kMaxPresentationHistory;
}

void MVKSwapchain::notifyPresentComplete(const MVKImagePresentInfo& presentInfo) {
	if (presentInfo.presentId != 0) {
		std::unique_lock pidLock(_currentPresentIdMutex);
		_currentPresentId = std::max(_currentPresentId, presentInfo.presentId);
		_currentPresentIdCondVar.notify_all();
	}
}

// Because of a regression in Metal, the most recent one or two presentations may not complete
// and call back. To work around this, if there are any uncompleted presentations, change the
// drawableSize of the CAMetalLayer, which will trigger presentation completion and callbacks.
// The drawableSize will be set to a correct size by the next swapchain created on the same surface.
void MVKSwapchain::forceUnpresentedImageCompletion() {
	if (_unpresentedImageCount) {
		getCAMetalLayer().drawableSize = { 1,1 };
	}
}

void MVKSwapchain::setLayerNeedsDisplay(const VkPresentRegionKHR* pRegion) {
	auto* mtlLayer = getCAMetalLayer();
	if (!pRegion || pRegion->rectangleCount == 0) {
		[mtlLayer setNeedsDisplay];
		return;
	}

	for (uint32_t i = 0; i < pRegion->rectangleCount; ++i) {
		CGRect cgRect = mvkCGRectFromVkRectLayerKHR(pRegion->pRectangles[i]);
#if MVK_MACOS
		// VK_KHR_incremental_present specifies an upper-left origin, but macOS by default
		// uses a lower-left origin.
		cgRect.origin.y = mtlLayer.bounds.size.height - cgRect.origin.y;
#endif
		// We were given rectangles in pixels, but -[CALayer setNeedsDisplayInRect:] wants them
		// in points, which is pixels / contentsScale.
		CGFloat scaleFactor = mtlLayer.contentsScale;
		cgRect.origin.x /= scaleFactor;
		cgRect.origin.y /= scaleFactor;
		cgRect.size.width /= scaleFactor;
		cgRect.size.height /= scaleFactor;
		[mtlLayer setNeedsDisplayInRect:cgRect];
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
static constexpr uint16_t FloatToCIE1931Unorm(float x) { return OSSwapHostToBigInt16((uint16_t)(x * 100000 / 2)); }
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
	NSData* colorVolData = [[NSData alloc] initWithBytes: &colorVol length: sizeof(colorVol)];
	NSData* lightLevelData = [[NSData alloc] initWithBytes: &lightLevel length: sizeof(lightLevel)];
    @autoreleasepool {
        CAEDRMetadata* caMetadata = [CAEDRMetadata HDR10MetadataWithDisplayInfo: colorVolData
                                                                    contentInfo: lightLevelData
                                                             opticalOutputScale: 1];
        auto* mtlLayer = getCAMetalLayer();
        mtlLayer.EDRMetadata = caMetadata;
        mtlLayer.wantsExtendedDynamicRangeContent = YES;
    }
	[colorVolData release];
	[lightLevelData release];
#endif
}


#pragma mark Construction

MVKSwapchain::MVKSwapchain(MVKDevice* device, const VkSwapchainCreateInfoKHR* pCreateInfo)
	: MVKVulkanAPIDeviceObject(device),
	_surface((MVKSurface*)pCreateInfo->surface),
	_imageExtent(pCreateInfo->imageExtent) {

	// Check if oldSwapchain is properly set
	auto* oldSwapchain = (MVKSwapchain*)pCreateInfo->oldSwapchain;
	if (oldSwapchain == _surface->_activeSwapchain) {
		_surface->setActiveSwapchain(this);
	} else {
		setConfigurationResult(reportError(VK_ERROR_NATIVE_WINDOW_IN_USE_KHR, "vkCreateSwapchainKHR(): pCreateInfo->oldSwapchain does not match the VkSwapchain that is in use by the surface"));
		return;
	}

	memset(_presentTimingHistory, 0, sizeof(_presentTimingHistory));

	// Retrieve the scaling and present mode structs if they are supplied.
	VkSwapchainPresentScalingCreateInfoEXT* pScalingInfo = nullptr;
	VkSwapchainPresentModesCreateInfoEXT* pPresentModesInfo = nullptr;
	for (auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_SWAPCHAIN_PRESENT_SCALING_CREATE_INFO_EXT: {
				pScalingInfo = (VkSwapchainPresentScalingCreateInfoEXT*)next;
				break;
			}
			case VK_STRUCTURE_TYPE_SWAPCHAIN_PRESENT_MODES_CREATE_INFO_EXT: {
				pPresentModesInfo = (VkSwapchainPresentModesCreateInfoEXT*)next;
				break;
			}
			default:
				break;
		}
	}

	_isDeliberatelyScaled = pScalingInfo && pScalingInfo->scalingBehavior;

	// Set the list of present modes that can be specified in a queue
	// present submission without causing the swapchain to be rebuilt.
	if (pPresentModesInfo) {
		for (uint32_t pmIdx = 0; pmIdx < pPresentModesInfo->presentModeCount; pmIdx++) {
			_compatiblePresentModes.push_back(pPresentModesInfo->pPresentModes[pmIdx]);
		}
	}

	auto& mtlFeats = getMetalFeatures();
	uint32_t imgCnt = mvkClamp(pCreateInfo->minImageCount,
							   mtlFeats.minSwapchainImageCount,
							   mtlFeats.maxSwapchainImageCount);
	initCAMetalLayer(pCreateInfo, pScalingInfo, imgCnt);
    initSurfaceImages(pCreateInfo, imgCnt);		// After initCAMetalLayer()
}

// kCAGravityResize is the Metal default
static CALayerContentsGravity getCALayerContentsGravity(VkSwapchainPresentScalingCreateInfoEXT* pScalingInfo) {

	if( !pScalingInfo ) {                                         return kCAGravityResize; }

	switch (pScalingInfo->scalingBehavior) {
		case VK_PRESENT_SCALING_STRETCH_BIT_EXT:                  return kCAGravityResize;
		case VK_PRESENT_SCALING_ASPECT_RATIO_STRETCH_BIT_EXT:     return kCAGravityResizeAspect;
		case VK_PRESENT_SCALING_ONE_TO_ONE_BIT_EXT:
			switch (pScalingInfo->presentGravityY) {
				case VK_PRESENT_GRAVITY_MIN_BIT_EXT:
					switch (pScalingInfo->presentGravityX) {
						case VK_PRESENT_GRAVITY_MIN_BIT_EXT:      return kCAGravityTopLeft;
						case VK_PRESENT_GRAVITY_CENTERED_BIT_EXT: return kCAGravityTop;
						case VK_PRESENT_GRAVITY_MAX_BIT_EXT:      return kCAGravityTopRight;
						default:                                  return kCAGravityTop;
					}
				case VK_PRESENT_GRAVITY_CENTERED_BIT_EXT:
					switch (pScalingInfo->presentGravityX) {
						case VK_PRESENT_GRAVITY_MIN_BIT_EXT:      return kCAGravityLeft;
						case VK_PRESENT_GRAVITY_CENTERED_BIT_EXT: return kCAGravityCenter;
						case VK_PRESENT_GRAVITY_MAX_BIT_EXT:      return kCAGravityRight;
						default:                                  return kCAGravityCenter;
					}
				case VK_PRESENT_GRAVITY_MAX_BIT_EXT:
					switch (pScalingInfo->presentGravityX) {
						case VK_PRESENT_GRAVITY_MIN_BIT_EXT:      return kCAGravityBottomLeft;
						case VK_PRESENT_GRAVITY_CENTERED_BIT_EXT: return kCAGravityBottom;
						case VK_PRESENT_GRAVITY_MAX_BIT_EXT:      return kCAGravityBottomRight;
						default:                                  return kCAGravityBottom;
					}
				default:                                          return kCAGravityCenter;
			}
		default:                                                  return kCAGravityResize;
	}
}

// Initializes the CAMetalLayer underlying the surface of this swapchain.
void MVKSwapchain::initCAMetalLayer(const VkSwapchainCreateInfoKHR* pCreateInfo,
									VkSwapchainPresentScalingCreateInfoEXT* pScalingInfo,
									uint32_t imgCnt) {

	auto* mtlLayer = getCAMetalLayer();
	if ( !mtlLayer || getIsSurfaceLost() ) { return; }

	auto minMagFilter = getMVKConfig().swapchainMinMagFilterUseNearest ? kCAFilterNearest : kCAFilterLinear;
	mtlLayer.drawableSize = mvkCGSizeFromVkExtent2D(_imageExtent);
	mtlLayer.device = getMTLDevice();
	mtlLayer.pixelFormat = getPixelFormats()->getMTLPixelFormat(pCreateInfo->imageFormat);
	mtlLayer.maximumDrawableCountMVK = imgCnt;
	mtlLayer.displaySyncEnabledMVK = (pCreateInfo->presentMode != VK_PRESENT_MODE_IMMEDIATE_KHR);
	mtlLayer.minificationFilter = minMagFilter;
	mtlLayer.magnificationFilter = minMagFilter;
	mtlLayer.contentsGravity = getCALayerContentsGravity(pScalingInfo);
	mtlLayer.framebufferOnly = !mvkIsAnyFlagEnabled(pCreateInfo->imageUsage, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
																			  VK_IMAGE_USAGE_TRANSFER_DST_BIT |
																			  VK_IMAGE_USAGE_SAMPLED_BIT |
																			  VK_IMAGE_USAGE_STORAGE_BIT)) &&
								!mvkAreAllFlagsEnabled(pCreateInfo->flags, VK_SWAPCHAIN_CREATE_MUTABLE_FORMAT_BIT_KHR);

	// Because of a regression in Metal, the most recent one or two presentations may not
	// complete and call back. Changing the CAMetalLayer drawableSize will force any incomplete
	// presentations on the oldSwapchain to complete and call back, but if the drawableSize
	// is not changing from the previous, we force those completions first.
	auto* oldSwapchain = (MVKSwapchain*)pCreateInfo->oldSwapchain;
	if (oldSwapchain && mvkVkExtent2DsAreEqual(pCreateInfo->imageExtent, _surface->getExtent())) {
		oldSwapchain->forceUnpresentedImageCompletion();
	}

	if (pCreateInfo->compositeAlpha != VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR) {
		mtlLayer.opaque = pCreateInfo->compositeAlpha == VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
	}

	switch (pCreateInfo->imageColorSpace) {
		case VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceSRGB;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = NO;
			break;
		case VK_COLOR_SPACE_DISPLAY_P3_NONLINEAR_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceDisplayP3;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_EXTENDED_SRGB_LINEAR_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceExtendedLinearSRGB;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_EXTENDED_SRGB_NONLINEAR_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceExtendedSRGB;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_DISPLAY_P3_LINEAR_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceExtendedLinearDisplayP3;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_DCI_P3_NONLINEAR_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceDCIP3;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_BT709_NONLINEAR_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceITUR_709;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = NO;
			break;
		case VK_COLOR_SPACE_BT2020_LINEAR_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceExtendedLinearITUR_2020;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
#if MVK_XCODE_12
		case VK_COLOR_SPACE_HDR10_ST2084_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceITUR_2100_PQ;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
		case VK_COLOR_SPACE_HDR10_HLG_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceITUR_2100_HLG;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = YES;
			break;
#endif
		case VK_COLOR_SPACE_ADOBERGB_NONLINEAR_EXT:
			mtlLayer.colorspaceNameMVK = kCGColorSpaceAdobeRGB1998;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = NO;
			break;
		case VK_COLOR_SPACE_PASS_THROUGH_EXT:
			mtlLayer.colorspace = nil;
			mtlLayer.wantsExtendedDynamicRangeContentMVK = NO;
			break;
		default:
			setConfigurationResult(reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "vkCreateSwapchainKHR(): Metal does not support VkColorSpaceKHR value %d.", pCreateInfo->imageColorSpace));
			break;
	}

	// TODO: set additional CAMetalLayer properties before extracting drawables:
	//	- presentsWithTransaction
	//	- drawsAsynchronously
}

// Initializes the array of images used for the surface of this swapchain.
// The CAMetalLayer should already be initialized when this is called.
void MVKSwapchain::initSurfaceImages(const VkSwapchainCreateInfoKHR* pCreateInfo, uint32_t imgCnt) {

    if ( _device->getConfigurationResult() != VK_SUCCESS ) { return; }
    if ( getIsSurfaceLost() ) { return; }

	VkImageFormatListCreateInfo fmtListInfo;
	for (const auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_IMAGE_FORMAT_LIST_CREATE_INFO: {
				fmtListInfo = *(VkImageFormatListCreateInfo*)next;
				fmtListInfo.pNext = VK_NULL_HANDLE;		// Terminate the new chain
				break;
			}
			default:
				break;
		}
	}

    VkExtent2D imgExtent = pCreateInfo->imageExtent;
    VkImageCreateInfo imgInfo = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = VK_NULL_HANDLE,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = pCreateInfo->imageFormat,
        .extent = mvkVkExtent3DFromVkExtent2D(imgExtent),
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = pCreateInfo->imageUsage,
        .flags = 0,
    };

	if (mvkAreAllFlagsEnabled(pCreateInfo->flags, VK_SWAPCHAIN_CREATE_MUTABLE_FORMAT_BIT_KHR)) {
		mvkEnableFlags(imgInfo.flags, VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT | VK_IMAGE_CREATE_EXTENDED_USAGE_BIT);
		imgInfo.pNext = &fmtListInfo;
	}
	if (mvkAreAllFlagsEnabled(pCreateInfo->flags, VK_SWAPCHAIN_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT_KHR)) {
		// We don't really support this, but set the flag anyway.
		mvkEnableFlags(imgInfo.flags, VK_IMAGE_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT);
	}

	// The VK_SWAPCHAIN_CREATE_DEFERRED_MEMORY_ALLOCATION_BIT_EXT flag is ignored, because
	// swapchain image memory allocation is provided by a MTLDrawable, which is retrieved
	// lazily, and hence is already deferred (or as deferred as we can make it).

	for (uint32_t imgIdx = 0; imgIdx < imgCnt; imgIdx++) {
		_presentableImages.push_back(_device->createPresentableSwapchainImage(&imgInfo, this, imgIdx, nullptr));
	}

	auto* mtlLayer = getCAMetalLayer();
	if (mtlLayer) {
		NSString* screenName = @"Main Screen";
#if MVK_MACOS && !MVK_MACCAT
		// To prevent deadlocks, avoid dispatching screenMVK to the main thread at the cost of a less informative log.
		if (NSThread.isMainThread) {
			auto* screen = mtlLayer.screenMVK;
			if ([screen respondsToSelector:@selector(localizedName)]) {
				screenName = screen.localizedName;
			}
		}
#endif
		MVKLogInfo("Created %d swapchain images with size (%d, %d) and contents scale %.1f in layer %s (%p) on screen %s.",
				   imgCnt, imgExtent.width, imgExtent.height, mtlLayer.contentsScale, mtlLayer.name.UTF8String, mtlLayer, screenName.UTF8String);
	} else {
		MVKLogInfo("Created %d swapchain images with size (%d, %d) on headless surface.", imgCnt, imgExtent.width, imgExtent.height);
	}
}

void MVKSwapchain::destroy() {
	// If this swapchain was not replaced by a new swapchain, remove this swapchain
	// from the surface, and force any outstanding presentations to complete.
	if (_surface->_activeSwapchain == this) {
		_surface->_activeSwapchain = nullptr;
		forceUnpresentedImageCompletion();
	}
	for (auto& img : _presentableImages) { _device->destroyPresentableSwapchainImage(img, NULL); }
	MVKVulkanAPIDeviceObject::destroy();
}

MVKSwapchain::~MVKSwapchain() {
    if (_licenseWatermark) { _licenseWatermark->destroy(); }
}

