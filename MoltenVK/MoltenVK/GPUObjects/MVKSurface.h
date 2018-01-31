/*
 * MVKSurface.h
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

#include "mvk_vulkan.h"
#include "MVKBaseObject.h"


// Expose MoltenVK Apple surface extension functionality
#ifdef VK_USE_PLATFORM_IOS_MVK
#	define vkCreate_PLATFORM_SurfaceMVK			vkCreateIOSSurfaceMVK
#	define Vk_PLATFORM_SurfaceCreateInfoMVK		VkIOSSurfaceCreateInfoMVK
#	define PLATFORM_VIEW_CLASS					UIView
#	include <UIKit/UIView.h>
#endif	// MVK_IOS

#ifdef VK_USE_PLATFORM_MACOS_MVK
#	define vkCreate_PLATFORM_SurfaceMVK			vkCreateMacOSSurfaceMVK
#	define Vk_PLATFORM_SurfaceCreateInfoMVK		VkMacOSSurfaceCreateInfoMVK
#	define PLATFORM_VIEW_CLASS					NSView
#	include <AppKit/NSView.h>
#endif	// MVK_MACOS

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

class MVKInstance;


#pragma mark MVKSurface

/** Represents a Vulkan WSI surface. */
class MVKSurface : public MVKConfigurableObject {

public:

    /** Returns the CAMetalLayer underlying this surface.  */
    inline CAMetalLayer* getCAMetalLayer() { return _mtlCAMetalLayer; }


#pragma mark Construction

	MVKSurface(MVKInstance* mvkInstance,
			   const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
			   const VkAllocationCallbacks* pAllocator);

	~MVKSurface() override;

protected:
	CAMetalLayer* _mtlCAMetalLayer;
};

