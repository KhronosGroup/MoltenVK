/*
 * MVKSurface.mm
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
#include "MVKInstance.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#import "MVKBlockObserver.h"


#pragma mark MVKSurface

#pragma mark Construction

#ifdef VK_USE_PLATFORM_IOS_MVK
static const char* mvkSurfaceCreateFuncName = "vkCreateIOSSurfaceMVK";
static const char* mvkSurfaceCreateStructName = "VkIOSSurfaceCreateInfoMVK";
static const char* mvkViewClassName = "UIView";
#endif

#ifdef VK_USE_PLATFORM_MACOS_MVK
static const char* mvkSurfaceCreateFuncName = "vkCreateMacOSSurfaceMVK";
static const char* mvkSurfaceCreateStructName = "VkMacOSSurfaceCreateInfoMVK";
static const char* mvkViewClassName = "NSView";
#endif

// pCreateInfo->pView can be either a CAMetalLayer or a view (NSView/UIView).
MVKSurface::MVKSurface(MVKInstance* mvkInstance,
					   const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
					   const VkAllocationCallbacks* pAllocator) {

	// Get the platform object contained in pView
	id<NSObject> obj = (id<NSObject>)pCreateInfo->pView;

	// If it's a view (NSView/UIView), extract the layer, otherwise assume it's already a CAMetalLayer.
	if ([obj isKindOfClass: [PLATFORM_VIEW_CLASS class]]) {
		if ( !NSThread.isMainThread ) {
			MVKLogInfo("%s(): You are not calling this function from the main thread. %s should only be accessed from the main thread. When using this function outside the main thread, consider passing the CAMetalLayer itself in %s::pView, instead of the %s.", mvkSurfaceCreateFuncName, mvkViewClassName, mvkSurfaceCreateStructName, mvkViewClassName);
		}
		obj = ((PLATFORM_VIEW_CLASS*)obj).layer;
	}

	// Confirm that we were provided with a CAMetalLayer
	if ([obj isKindOfClass: [CAMetalLayer class]]) {
		_mtlCAMetalLayer = (CAMetalLayer*)[obj retain];		// retained
		if ([_mtlCAMetalLayer.delegate isKindOfClass: [PLATFORM_VIEW_CLASS class]]) {
			// Sometimes, the owning view can replace its CAMetalLayer. In that case, the client
			// needs to recreate the surface.
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
	} else {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "%s(): On-screen rendering requires a layer of type CAMetalLayer.", mvkSurfaceCreateFuncName));
		_mtlCAMetalLayer = nil;
	}
}

MVKSurface::~MVKSurface() {
	std::lock_guard<std::mutex> lock(_lock);
	[_mtlCAMetalLayer release];
	[_layerObserver release];
}

