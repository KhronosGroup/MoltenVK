/*
 * MVKInstance.h
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKSurface.h"
#include "MVKBaseObject.h"
#include <vector>
#include <unordered_map>
#include <string>

class MVKPhysicalDevice;


#pragma mark -
#pragma mark MVKInstance

/** Represents a Vulkan instance. */
class MVKInstance : public MVKConfigurableObject {

public:

	/** Returns the function pointer corresponding to the specified named entry point. */
	inline PFN_vkVoidFunction getProcAddr(const char* pName) { return _procAddrMap[pName]; }

	/**
	 * If pPhysicalDevices is null, the value of pCount is updated with the number of 
	 * physical devices supported by this instance.
	 *
	 * If pPhysicalDevices is not null, then pCount physical devices are copied into the array.
	 * If the number of available physical devices is less than pCount, the value of pCount is 
	 * updated to indicate the number of physical devices actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of physical
	 * devices available in this instance is larger than the specified pCount. Returns other 
	 * values if an error occurs.
	 */
	VkResult getPhysicalDevices(uint32_t* pCount, VkPhysicalDevice* pPhysicalDevices);

    /** 
     * Verifies that the list of layers are available, 
     * and returns VK_SUCCESS or VK_ERROR_LAYER_NOT_PRESENT.
     */
    VkResult verifyLayers(uint32_t count, const char* const* names);

    /**
     * Verifies that the list of extensions are available,
     * and returns VK_SUCCESS or VK_ERROR_EXTENSION_NOT_PRESENT.
     */
    VkResult verifyExtensions(uint32_t count, const char* const* names);

	/** Creates and returns a new object. */
	MVKSurface* createSurface(const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
							  const VkAllocationCallbacks* pAllocator);

	/** Destroys the specified object. */
	void destroySurface(MVKSurface* mvkSrfc,
						const VkAllocationCallbacks* pAllocator);


#pragma mark Object Creation

	/** Constructs an instance from the specified instance config. */
	MVKInstance(const VkInstanceCreateInfo* pCreateInfo);

	~MVKInstance() override;

protected:
	void initProcAddrs();
    void logVersions();

	VkApplicationInfo _appInfo;
	std::vector<MVKPhysicalDevice*> _physicalDevices;
	std::unordered_map<std::string, PFN_vkVoidFunction> _procAddrMap;
};

