/*
 * MVKSurface.mm
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
#include "MVKInstance.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "mvk_datatypes.hpp"

#import "CAMetalLayer+MoltenVK.h"
#import "MVKBlockObserver.h"

#ifdef VK_USE_PLATFORM_IOS_MVK
#	define PLATFORM_VIEW_CLASS	UIView
#	import <UIKit/UIView.h>
#endif

#ifdef VK_USE_PLATFORM_MACOS_MVK
#	define PLATFORM_VIEW_CLASS	NSView
#	import <AppKit/NSView.h>
#endif


// We need to double-dereference the name to first convert to the platform symbol, then to a string.
#define STR_PLATFORM(NAME) #NAME
#define STR(NAME) STR_PLATFORM(NAME)

// As defined in the Vulkan spec, represents an undefined extent.
// Spec is currently somewhat ambiguous about whether an undefined surface extent should be updated
// once a swapchain is attached, but consensus amoung the spec authors is that it should not.
static constexpr VkExtent2D kMVKUndefinedExtent = {0xFFFFFFFF, 0xFFFFFFFF};


#pragma mark MVKSurface

CAMetalLayer* MVKSurface::getCAMetalLayer() {
	std::lock_guard<std::mutex> lock(_layerLock);
	return _mtlCAMetalLayer;
}

VkExtent2D MVKSurface::getExtent() {
	return _mtlCAMetalLayer ? mvkVkExtent2DFromCGSize(_mtlCAMetalLayer.drawableSize) : kMVKUndefinedExtent;
}

VkExtent2D MVKSurface::getNaturalExtent() {
	return _mtlCAMetalLayer ? mvkVkExtent2DFromCGSize(_mtlCAMetalLayer.naturalDrawableSizeMVK) : kMVKUndefinedExtent;
}

void MVKSurface::setActiveSwapchain(MVKSwapchain* swapchain) {
	_activeSwapchain = swapchain;
}

MVKSurface::MVKSurface(MVKInstance* mvkInstance,
					   const VkMetalSurfaceCreateInfoEXT* pCreateInfo,
					   const VkAllocationCallbacks* pAllocator) : _mvkInstance(mvkInstance) {
	initLayer((CAMetalLayer*)pCreateInfo->pLayer, "vkCreateMetalSurfaceEXT", false);
}

MVKSurface::MVKSurface(MVKInstance* mvkInstance,
					   const VkHeadlessSurfaceCreateInfoEXT* pCreateInfo,
					   const VkAllocationCallbacks* pAllocator) : _mvkInstance(mvkInstance) {
	initLayer(nil, "vkCreateHeadlessSurfaceEXT", true);
}

// pCreateInfo->pView can be either a CAMetalLayer or a view (NSView/UIView).
MVKSurface::MVKSurface(MVKInstance* mvkInstance,
					   const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
					   const VkAllocationCallbacks* pAllocator) : _mvkInstance(mvkInstance) {
	MVKLogWarn("%s() is deprecated. Use vkCreateMetalSurfaceEXT() from the VK_EXT_metal_surface extension.", STR(vkCreate_PLATFORM_SurfaceMVK));

	// Get the platform object contained in pView
	// If it's a view (NSView/UIView), extract the layer, otherwise assume it's already a CAMetalLayer.
	id<NSObject> obj = (id<NSObject>)pCreateInfo->pView;
	if ([obj isKindOfClass: [PLATFORM_VIEW_CLASS class]]) {
		__block id<NSObject> layer;
		mvkDispatchToMainAndWait(^{ layer = ((PLATFORM_VIEW_CLASS*)obj).layer; });
		obj = layer;
	}

	// Confirm that we were provided with a CAMetalLayer
	initLayer([obj isKindOfClass: CAMetalLayer.class] ? (CAMetalLayer*)obj : nil, STR(vkCreate_PLATFORM_SurfaceMVK), false);
}

void MVKSurface::initLayer(CAMetalLayer* mtlLayer, const char* vkFuncName, bool isHeadless) {

	_mtlCAMetalLayer = [mtlLayer retain];	// retained
	if ( !_mtlCAMetalLayer && !isHeadless ) { setConfigurationResult(reportError(VK_ERROR_SURFACE_LOST_KHR, "%s(): On-screen rendering requires a layer of type CAMetalLayer.", vkFuncName)); }

	// Sometimes, the owning view can replace its CAMetalLayer.
	// When that happens, the app needs to recreate the surface.
	if ([_mtlCAMetalLayer.delegate isKindOfClass: [PLATFORM_VIEW_CLASS class]]) {
		_layerObserver = [MVKBlockObserver observerWithBlock: ^(NSString* path, id, NSDictionary*, void*) {
			if ([path isEqualToString: @"layer"]) { this->releaseLayer(); }
		} forObject: _mtlCAMetalLayer.delegate atKeyPath: @"layer"];
	}
}

void MVKSurface::releaseLayer() {
	std::lock_guard<std::mutex> lock(_layerLock);
	setConfigurationResult(VK_ERROR_SURFACE_LOST_KHR);
	[_mtlCAMetalLayer release];
	_mtlCAMetalLayer = nil;
	[_layerObserver release];
	_layerObserver = nil;
}

MVKSurface::~MVKSurface() {
	releaseLayer();
}

