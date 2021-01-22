/*
 * MVKSurface.h
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

#pragma once

#include "MVKVulkanAPIObject.h"
#include "MVKEnvironment.h"
#include <mutex>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#ifdef VK_USE_PLATFORM_IOS_MVK
#	define PLATFORM_VIEW_CLASS	UIView
#	import <UIKit/UIView.h>
#endif

#ifdef VK_USE_PLATFORM_MACOS_MVK
#	define PLATFORM_VIEW_CLASS	NSView
#	import <AppKit/NSView.h>
#endif

class MVKInstance;

@class MVKBlockObserver;


#pragma mark MVKSurface

/** Represents a Vulkan WSI surface. */
class MVKSurface : public MVKVulkanAPIObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_SURFACE_KHR; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_SURFACE_KHR_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _mvkInstance; }

    /** Returns the CAMetalLayer underlying this surface.  */
    inline CAMetalLayer* getCAMetalLayer() {
        std::lock_guard<std::mutex> lock(_lock);
        return _mtlCAMetalLayer;
    }


#pragma mark Construction

	MVKSurface(MVKInstance* mvkInstance,
			   const VkMetalSurfaceCreateInfoEXT* pCreateInfo,
			   const VkAllocationCallbacks* pAllocator);

	MVKSurface(MVKInstance* mvkInstance,
			   const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
			   const VkAllocationCallbacks* pAllocator);

	~MVKSurface() override;

protected:
	void propagateDebugName() override {}
	void initLayerObserver();

	MVKInstance* _mvkInstance;
	CAMetalLayer* _mtlCAMetalLayer;
	std::mutex _lock;
	MVKBlockObserver* _layerObserver;
};

