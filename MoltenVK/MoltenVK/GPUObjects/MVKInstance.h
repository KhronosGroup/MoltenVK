/*
 * MVKInstance.h
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

#pragma once

#include "MVKEnvironment.h"
#include "MVKLayers.h"
#include "MVKVulkanAPIObject.h"
#include "MVKVector.h"
#include "vk_mvk_moltenvk.h"
#include <unordered_map>
#include <string>
#include <mutex>

class MVKPhysicalDevice;
class MVKDevice;
class MVKSurface;
class MVKDebugReportCallback;
class MVKDebugUtilsMessenger;


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

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_INSTANCE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_INSTANCE_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return this; }

	/** Returns a pointer to the layer manager. */
	inline MVKLayerManager* getLayerManager() { return MVKLayerManager::globalManager(); }

	/** Returns the function pointer corresponding to the named entry point, or NULL if it doesn't exist. */
	PFN_vkVoidFunction getProcAddr(const char* pName);

	/** Returns the number of available physical devices. */
	uint32_t getPhysicalDeviceCount() { return (uint32_t)_physicalDevices.size(); }

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
	 * If pPhysicalDeviceGroups is null, the value of pCount is updated with the number of 
	 * physical device groups supported by this instance.
	 *
	 * If pPhysicalDeviceGroups is not null, then pCount physical device groups are copied into the array.
	 * If the number of available physical device groups is less than pCount, the value of pCount is 
	 * updated to indicate the number of physical device groups actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of physical
	 * device groups available in this instance is larger than the specified pCount. Returns other 
	 * values if an error occurs.
	 */
	VkResult getPhysicalDeviceGroups(uint32_t* pCount, VkPhysicalDeviceGroupProperties* pPhysicalDeviceGroupProps);

	/** Returns the driver layer. */
	MVKLayer* getDriverLayer() { return getLayerManager()->getDriverLayer(); }

	MVKSurface* createSurface(const VkMetalSurfaceCreateInfoEXT* pCreateInfo,
							  const VkAllocationCallbacks* pAllocator);

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


	MVKDebugUtilsMessenger* createDebugUtilsMessenger(const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo,
													  const VkAllocationCallbacks* pAllocator);

	void destroyDebugUtilsMessenger(MVKDebugUtilsMessenger* mvkDUM,
									const VkAllocationCallbacks* pAllocator);

	void debugUtilsMessage(VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
						   VkDebugUtilsMessageTypeFlagsEXT messageTypes,
						   const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData);

	void debugReportMessage(MVKVulkanAPIObject* mvkAPIObj, int aslLvl, const char* pMessage);

	/** Returns whether debug callbacks are being used. */
	bool hasDebugCallbacks() { return _hasDebugReportCallbacks || _hasDebugUtilsMessengers; }

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
	void initDebugCallbacks(const VkInstanceCreateInfo* pCreateInfo);
	VkDebugReportFlagsEXT getVkDebugReportFlagsFromASLLevel(int aslLvl);
	VkDebugUtilsMessageSeverityFlagBitsEXT getVkDebugUtilsMessageSeverityFlagBitsFromASLLevel(int aslLvl);
	MVKEntryPoint* getEntryPoint(const char* pName);
	void initConfig();
    void logVersions();
	VkResult verifyLayers(uint32_t count, const char* const* names);

	MVKConfiguration _mvkConfig;
	VkApplicationInfo _appInfo;
	MVKVectorInline<MVKPhysicalDevice*, 1> _physicalDevices;
	MVKVectorDefault<MVKDebugReportCallback*> _debugReportCallbacks;
	MVKVectorDefault<MVKDebugUtilsMessenger*> _debugUtilMessengers;
	std::unordered_map<std::string, MVKEntryPoint> _entryPoints;
	std::mutex _dcbLock;
	bool _hasDebugReportCallbacks;
	bool _hasDebugUtilsMessengers;
	bool _useCreationCallbacks;
	const char* _debugReportCallbackLayerPrefix;
	int32_t _autoGPUCaptureScope;
};


#pragma mark -
#pragma mark MVKDebugReportCallback

/** Represents a Vulkan Debug Report callback. */
class MVKDebugReportCallback : public MVKVulkanAPIObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DEBUG_REPORT_CALLBACK_EXT; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DEBUG_REPORT_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _mvkInstance; }

	MVKDebugReportCallback(MVKInstance* mvkInstance,
						   const VkDebugReportCallbackCreateInfoEXT* pCreateInfo,
						   bool isCreationCallback) :
	_mvkInstance(mvkInstance),
	_info(*pCreateInfo),
	_isCreationCallback(isCreationCallback) {

		_info.pNext = nullptr;
	}

protected:
	friend MVKInstance;
	
	void propogateDebugName() override {}

	MVKInstance* _mvkInstance;
	VkDebugReportCallbackCreateInfoEXT _info;
	bool _isCreationCallback;
};


#pragma mark -
#pragma mark MVKDebugUtilsMessenger

/** Represents a Vulkan Debug Utils callback. */
class MVKDebugUtilsMessenger : public MVKVulkanAPIObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DEBUG_UTILS_MESSENGER_EXT; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_UNKNOWN_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _mvkInstance; }

	MVKDebugUtilsMessenger(MVKInstance* mvkInstance,
						   const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo,
						   bool isCreationCallback) :
	_mvkInstance(mvkInstance),
	_info(*pCreateInfo),
	_isCreationCallback(isCreationCallback) {

		_info.pNext = nullptr;
	}

protected:
	friend MVKInstance;

	void propogateDebugName() override {}

	MVKInstance* _mvkInstance;
	VkDebugUtilsMessengerCreateInfoEXT _info;
	bool _isCreationCallback;
};

