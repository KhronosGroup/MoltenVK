/*
 * MVKSurface.h
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

#pragma once

#include "MVKVulkanAPIObject.h"
#include <mutex>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

class MVKInstance;
class MVKSwapchain;

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

    /** Returns the CAMetalLayer underlying this surface. */
	CAMetalLayer* getCAMetalLayer();

	/** Returns the extent of this surface. */
	VkExtent2D getExtent();

	/** Returns the extent for which the underlying CAMetalLayer will not need to be scaled when composited. */
	VkExtent2D getNaturalExtent();

	/** Returns whether this surface is headless. */
	bool isHeadless() { return !_mtlCAMetalLayer && wasConfigurationSuccessful(); }

#pragma mark Construction

	MVKSurface(MVKInstance* mvkInstance,
			   const VkMetalSurfaceCreateInfoEXT* pCreateInfo,
			   const VkAllocationCallbacks* pAllocator);

	MVKSurface(MVKInstance* mvkInstance,
			   const VkHeadlessSurfaceCreateInfoEXT* pCreateInfo,
			   const VkAllocationCallbacks* pAllocator);

	MVKSurface(MVKInstance* mvkInstance,
			   const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
			   const VkAllocationCallbacks* pAllocator);

	~MVKSurface() override;

protected:
	friend class MVKSwapchain;

	void propagateDebugName() override {}
	void setActiveSwapchain(MVKSwapchain* swapchain);
	void initLayer(CAMetalLayer* mtlLayer, const char* vkFuncName, bool isHeadless);
	void releaseLayer();

	std::mutex _layerLock;
	MVKInstance* _mvkInstance = nullptr;
	CAMetalLayer* _mtlCAMetalLayer = nil;
	MVKBlockObserver* _layerObserver = nil;
	MVKSwapchain* _activeSwapchain = nullptr;
};

