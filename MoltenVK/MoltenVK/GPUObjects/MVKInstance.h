/*
 * MVKInstance.h
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

#pragma once

#include "MVKEnvironment.h"
#include "MVKLayers.h"
#include "MVKVulkanAPIObject.h"
#include "vk_mvk_moltenvk.h"
#include <vector>
#include <unordered_map>
#include <string>
#include <mutex>

class MVKPhysicalDevice;
class MVKDevice;
class MVKSurface;
class MVKDebugReportCallback;


/** Tracks info about entry point function pointer addresses. */
typedef struct {
	PFN_vkVoidFunction functionPointer;
	const char* ext1Name;
	const char* ext2Name;
	bool isDevice;

	bool isCore() { return !ext1Name && !ext2Name; }
	bool isEnabled(const MVKExtensionList& extList) {
		return isCore() || extList.isEnabled(ext1Name) || extList.isEnabled(ext2Name);
	}
} MVKEntryPoint;


#pragma mark -
#pragma mark MVKInstance

/** Represents a Vulkan instance. */
class MVKInstance : public MVKDispatchableVulkanAPIObject {

public:

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_INSTANCE_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return this; }

	/** Returns a pointer to the layer manager. */
	inline MVKLayerManager* getLayerManager() { return MVKLayerManager::globalManager(); }

	/** Returns the function pointer corresponding to the named entry point, or NULL if it doesn't exist. */
	PFN_vkVoidFunction getProcAddr(const char* pName);

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

	/** Returns the driver layer. */
	MVKLayer* getDriverLayer() { return MVKLayerManager::globalManager()->getDriverLayer(); }

	MVKSurface* createSurface(const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
							  const VkAllocationCallbacks* pAllocator);

	void destroySurface(MVKSurface* mvkSrfc,
						const VkAllocationCallbacks* pAllocator);

	MVKDebugReportCallback* createDebugReportCallback(const VkDebugReportCallbackCreateInfoEXT* pCreateInfo,
													  const VkAllocationCallbacks* pAllocator);

	void destroyDebugReportCallback(MVKDebugReportCallback* mvkDRCB,
									const VkAllocationCallbacks* pAllocator);

	void debugReportMessage(VkDebugReportFlagsEXT flags,
							VkDebugReportObjectTypeEXT objectType,
							uint64_t object,
							size_t location,
							int32_t messageCode,
							const char* pLayerPrefix,
							const char* pMessage);

	void debugReportMessage(MVKVulkanAPIObject* mvkAPIObj, int aslLvl, const char* pMessage);

	/** Returns whether debug report callbacks are being used. */
	bool hasDebugReportCallbacks() { return _hasDebugReportCallbacks; }

	/** Returns the MoltenVK configuration settings. */
	const MVKConfiguration* getMoltenVKConfiguration() { return &_mvkConfig; }

	/** Returns the MoltenVK configuration settings. */
	void setMoltenVKConfiguration(MVKConfiguration* mvkConfig) { _mvkConfig = *mvkConfig; }

	/** The list of Vulkan extensions, indicating whether each has been enabled by the app. */
	const MVKExtensionList _enabledExtensions;


#pragma mark Object Creation

	/** Constructs an instance from the specified instance config. */
	MVKInstance(const VkInstanceCreateInfo* pCreateInfo);

	~MVKInstance() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKInstance() method.
     */
    inline VkInstance getVkInstance() { return (VkInstance)getVkHandle(); }

    /**
     * Retrieves the MVKInstance instance referenced by the VkInstance handle.
     * This is the compliment of the getVkInstance() method.
     */
    static inline MVKInstance* getMVKInstance(VkInstance vkInstance) {
        return (MVKInstance*)getDispatchableObject(vkInstance);
    }

protected:
	friend MVKDevice;

	void propogateDebugName() override {}
	void initProcAddrs();
	void initCreationDebugReportCallbacks(const VkInstanceCreateInfo* pCreateInfo);
	VkDebugReportFlagsEXT getVkDebugReportFlagsFromASLLevel(int aslLvl);
	MVKEntryPoint* getEntryPoint(const char* pName);
	void initConfig();
    void logVersions();
	VkResult verifyLayers(uint32_t count, const char* const* names);

	MVKConfiguration _mvkConfig;
	VkApplicationInfo _appInfo;
	std::vector<MVKPhysicalDevice*> _physicalDevices;
	std::unordered_map<std::string, MVKEntryPoint> _entryPoints;
	std::vector<MVKDebugReportCallback*> _debugReportCallbacks;
	std::mutex _drcbLock;
	bool _hasDebugReportCallbacks;
	bool _useCreationCallbacks;
	const char* _debugReportCallbackLayerPrefix;
};


#pragma mark -
#pragma mark MVKDebugReportCallback

/** Represents a Vulkan Debug Report callback. */
class MVKDebugReportCallback : public MVKVulkanAPIObject {

public:

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DEBUG_REPORT_CALLBACK_EXT_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _mvkInstance; }

	MVKDebugReportCallback(MVKInstance* mvkInstance,
						   const VkDebugReportCallbackCreateInfoEXT* pCreateInfo,
						   bool isCreationCallback) :
	_mvkInstance(mvkInstance), _info(*pCreateInfo), _isCreationCallback(isCreationCallback) {
		_info.pNext = nullptr;
	}

protected:
	friend MVKInstance;
	
	void propogateDebugName() override {}

	MVKInstance* _mvkInstance;
	VkDebugReportCallbackCreateInfoEXT _info;
	bool _isCreationCallback;
};

