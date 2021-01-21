/*
 * MVKSurface.mm
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKInstance.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#import "MVKBlockObserver.h"

// We need to double-dereference the name to first convert to the platform symbol, then to a string.
#define STR_PLATFORM(NAME) #NAME
#define STR(NAME) STR_PLATFORM(NAME)


#pragma mark MVKSurface

MVKSurface::MVKSurface(MVKInstance* mvkInstance,
					   const VkMetalSurfaceCreateInfoEXT* pCreateInfo,
					   const VkAllocationCallbacks* pAllocator) : _mvkInstance(mvkInstance) {

	_mtlCAMetalLayer = (CAMetalLayer*)[pCreateInfo->pLayer retain];
	initLayerObserver();
}

// pCreateInfo->pView can be either a CAMetalLayer or a view (NSView/UIView).
MVKSurface::MVKSurface(MVKInstance* mvkInstance,
					   const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
					   const VkAllocationCallbacks* pAllocator) : _mvkInstance(mvkInstance) {

//	MVKLogInfo("%s(): This function is obsolete. Consider using the vkCreateMetalSurfaceEXT() function from the VK_EXT_metal_surface extension instead.", STR(vkCreate_PLATFORM_SurfaceMVK));

	// Get the platform object contained in pView
	id<NSObject> obj = (id<NSObject>)pCreateInfo->pView;

	// If it's a view (NSView/UIView), extract the layer, otherwise assume it's already a CAMetalLayer.
	if ([obj isKindOfClass: [PLATFORM_VIEW_CLASS class]]) {
		if ( !NSThread.isMainThread ) {
			MVKLogInfo("%s(): You are not calling this function from the main thread. %s should only be accessed from the main thread. When using this function outside the main thread, consider passing the CAMetalLayer itself in %s::pView, instead of the %s.",
					   STR(vkCreate_PLATFORM_SurfaceMVK), STR(PLATFORM_VIEW_CLASS), STR(Vk_PLATFORM_SurfaceCreateInfoMVK), STR(PLATFORM_VIEW_CLASS));
		}
		obj = ((PLATFORM_VIEW_CLASS*)obj).layer;
	}

	// Confirm that we were provided with a CAMetalLayer
	if ([obj isKindOfClass: [CAMetalLayer class]]) {
		_mtlCAMetalLayer = (CAMetalLayer*)[obj retain];		// retained
	} else {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED,
										   "%s(): On-screen rendering requires a layer of type CAMetalLayer.",
										   STR(vkCreate_PLATFORM_SurfaceMVK)));
		_mtlCAMetalLayer = nil;
	}

	initLayerObserver();
}

// Sometimes, the owning view can replace its CAMetalLayer. In that case, the client needs to recreate the surface.
void MVKSurface::initLayerObserver() {

	_layerObserver = nil;
	if ( ![_mtlCAMetalLayer.delegate isKindOfClass: [PLATFORM_VIEW_CLASS class]] ) { return; }

	_layerObserver = [MVKBlockObserver observerWithBlock: ^(NSString* path, id, NSDictionary*, void*) {
		if ( ![path isEqualToString: @"layer"] ) { return; }
		std::lock_guard<std::mutex> lock(this->_lock);
		[this->_mtlCAMetalLayer release];
		this->_mtlCAMetalLayer = nil;
		this->setConfigurationResult(VK_ERROR_SURFACE_LOST_KHR);
		[this->_layerObserver release];
		this->_layerObserver = nil;
	} forObject: _mtlCAMetalLayer.delegate atKeyPath: @"layer"];
}

MVKSurface::~MVKSurface() {
	std::lock_guard<std::mutex> lock(_lock);
	[_mtlCAMetalLayer release];
	[_layerObserver release];
}

