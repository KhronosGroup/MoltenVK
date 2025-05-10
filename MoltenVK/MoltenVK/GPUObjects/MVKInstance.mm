/*
 * MVKInstance.mm
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


#include "MVKInstance.h"
#include "MVKDevice.h"
#include "MVKFoundation.h"
#include "MVKSurface.h"
#include "MVKOSExtensions.h"
#include "mvk_deprecated_api.h"

#include <string_view>

using namespace std;


#pragma mark -
#pragma mark MVKInstance

MVKEntryPoint* MVKInstance::getEntryPoint(const char* pName) {
	auto iter = _entryPoints.find(pName);
	return (iter != _entryPoints.end()) ? &iter->second : nullptr;
}

// Returns core instance commands, enabled instance extension commands, and all device commands.
PFN_vkVoidFunction MVKInstance::getProcAddr(const char* pName) {
	MVKEntryPoint* pMVKPA = getEntryPoint(pName);

	bool isSupported = (pMVKPA &&														// Command exists and...
						(pMVKPA->isDevice ||											// ...is a device command or...
						 pMVKPA->isEnabled(_appInfo.apiVersion, _enabledExtensions)));	// ...is a core or enabled extension command.

	return isSupported ? pMVKPA->functionPointer : nullptr;
}

VkResult MVKInstance::getPhysicalDevices(uint32_t* pCount, VkPhysicalDevice* pPhysicalDevices) {

	// Get the number of physical devices
	uint32_t pdCnt = getPhysicalDeviceCount();

	// If properties aren't actually being requested yet, simply update the returned count
	if ( !pPhysicalDevices ) {
		*pCount = pdCnt;
		return VK_SUCCESS;
	}

	// Othewise, determine how many physical devices we'll return, and return that count
	VkResult result = (*pCount >= pdCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(pdCnt, *pCount);

	// Now populate the devices
	for (uint32_t pdIdx = 0; pdIdx < *pCount; pdIdx++) {
		pPhysicalDevices[pdIdx] = _physicalDevices[pdIdx]->getVkPhysicalDevice();
	}

	return result;
}

VkResult MVKInstance::getPhysicalDeviceGroups(uint32_t* pCount, VkPhysicalDeviceGroupProperties* pPhysicalDeviceGroupProps) {

	// According to the Vulkan spec: "Every physical device *must* be in exactly one device group."
	// Since we don't really support this yet, we must return one group for every device.

	// Get the number of physical devices
	uint32_t pdCnt = getPhysicalDeviceCount();

	// If properties aren't actually being requested yet, simply update the returned count
	if ( !pPhysicalDeviceGroupProps ) {
		*pCount = pdCnt;
		return VK_SUCCESS;
	}

	// Othewise, determine how many physical device groups we'll return, and return that count
	VkResult result = (*pCount >= pdCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(pdCnt, *pCount);

	// Now populate the device groups
	for (uint32_t pdIdx = 0; pdIdx < *pCount; pdIdx++) {
		pPhysicalDeviceGroupProps[pdIdx].physicalDeviceCount = 1;
		pPhysicalDeviceGroupProps[pdIdx].physicalDevices[0] = _physicalDevices[pdIdx]->getVkPhysicalDevice();
		pPhysicalDeviceGroupProps[pdIdx].subsetAllocation = VK_FALSE;
	}

	return result;
}

MVKSurface* MVKInstance::createSurface(const VkMetalSurfaceCreateInfoEXT* pCreateInfo,
									   const VkAllocationCallbacks* pAllocator) {
	return new MVKSurface(this, pCreateInfo, pAllocator);
}

MVKSurface* MVKInstance::createSurface(const VkHeadlessSurfaceCreateInfoEXT* pCreateInfo,
									   const VkAllocationCallbacks* pAllocator) {
	return new MVKSurface(this, pCreateInfo, pAllocator);
}

MVKSurface* MVKInstance::createSurface(const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
									   const VkAllocationCallbacks* pAllocator) {
	return new MVKSurface(this, pCreateInfo, pAllocator);
}

void MVKInstance::destroySurface(MVKSurface* mvkSrfc,
								const VkAllocationCallbacks* pAllocator) {
	if (mvkSrfc) { mvkSrfc->destroy(); }
}

MVKDebugReportCallback* MVKInstance::createDebugReportCallback(const VkDebugReportCallbackCreateInfoEXT* pCreateInfo,
															   const VkAllocationCallbacks* pAllocator) {
	lock_guard<mutex> lock(_dcbLock);

	MVKDebugReportCallback* mvkDRCB = new MVKDebugReportCallback(this, pCreateInfo, _useCreationCallbacks);
	_debugReportCallbacks.push_back(mvkDRCB);
	_hasDebugReportCallbacks = true;
	return mvkDRCB;
}

void MVKInstance::destroyDebugReportCallback(MVKDebugReportCallback* mvkDRCB,
								const VkAllocationCallbacks* pAllocator) {
	if ( !mvkDRCB ) { return; }

	lock_guard<mutex> lock(_dcbLock);

	mvkRemoveAllOccurances(_debugReportCallbacks, mvkDRCB);
	_hasDebugReportCallbacks = (_debugReportCallbacks.size() != 0);
	mvkDRCB->destroy();
}

void MVKInstance::debugReportMessage(VkDebugReportFlagsEXT flags,
									 VkDebugReportObjectTypeEXT objectType,
									 uint64_t object,
									 size_t location,
									 int32_t messageCode,
									 const char* pLayerPrefix,
									 const char* pMessage) {

	// Fail fast to avoid further unnecessary processing and locking.
	if ( !(_hasDebugReportCallbacks) ) { return; }

	lock_guard<mutex> lock(_dcbLock);

	for (auto mvkDRCB : _debugReportCallbacks) {
		auto& drbcInfo = mvkDRCB->_info;
		if (drbcInfo.pfnCallback &&
			mvkIsAnyFlagEnabled(drbcInfo.flags, flags) &&
			(mvkDRCB->_isCreationCallback == _useCreationCallbacks)) {

			drbcInfo.pfnCallback(flags, objectType, object, location, messageCode, pLayerPrefix, pMessage, drbcInfo.pUserData);
		}
	}
}

MVKDebugUtilsMessenger* MVKInstance::createDebugUtilsMessenger(const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo,
															   const VkAllocationCallbacks* pAllocator) {
	lock_guard<mutex> lock(_dcbLock);

	MVKDebugUtilsMessenger* mvkDUM = new MVKDebugUtilsMessenger(this, pCreateInfo, _useCreationCallbacks);
	_debugUtilMessengers.push_back(mvkDUM);
	_hasDebugUtilsMessengers = true;
	return mvkDUM;
}

void MVKInstance::destroyDebugUtilsMessenger(MVKDebugUtilsMessenger* mvkDUM,
											 const VkAllocationCallbacks* pAllocator) {
	if ( !mvkDUM ) { return; }

	lock_guard<mutex> lock(_dcbLock);

	mvkRemoveAllOccurances(_debugUtilMessengers, mvkDUM);
	_hasDebugUtilsMessengers = (_debugUtilMessengers.size() != 0);
	mvkDUM->destroy();
}

void MVKInstance::debugUtilsMessage(VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
									VkDebugUtilsMessageTypeFlagsEXT messageTypes,
									const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData) {

	// Fail fast to avoid further unnecessary processing and locking.
	if ( !(_hasDebugUtilsMessengers) ) { return; }

	lock_guard<mutex> lock(_dcbLock);

	for (auto mvkDUM : _debugUtilMessengers) {
		auto& dumInfo = mvkDUM->_info;
		if (dumInfo.pfnUserCallback &&
			mvkIsAnyFlagEnabled(dumInfo.messageSeverity, messageSeverity) &&
			mvkIsAnyFlagEnabled(dumInfo.messageType, messageTypes) &&
			(mvkDUM->_isCreationCallback == _useCreationCallbacks)) {

			dumInfo.pfnUserCallback(messageSeverity, messageTypes, pCallbackData, dumInfo.pUserData);
		}
	}
}

void MVKInstance::debugReportMessage(MVKVulkanAPIObject* mvkAPIObj, MVKConfigLogLevel logLevel, const char* pMessage) {

	if (_hasDebugReportCallbacks) {
		VkDebugReportFlagsEXT flags = getVkDebugReportFlagsFromLogLevel(logLevel);
		uint64_t object = (uint64_t)(mvkAPIObj ? mvkAPIObj->getVkHandle() : nullptr);
		VkDebugReportObjectTypeEXT objectType = mvkAPIObj ? mvkAPIObj->getVkDebugReportObjectType() : VK_DEBUG_REPORT_OBJECT_TYPE_UNKNOWN_EXT;
		debugReportMessage(flags, objectType, object, 0, 0, _debugReportCallbackLayerPrefix, pMessage);
	}

	if (_hasDebugUtilsMessengers) {
		VkDebugUtilsObjectNameInfoEXT duObjName = {
			.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			.pNext = nullptr,
			.objectType = mvkAPIObj ? mvkAPIObj->getVkObjectType() : VK_OBJECT_TYPE_UNKNOWN,
			.objectHandle = (uint64_t)(mvkAPIObj ? mvkAPIObj->getVkHandle() : nullptr),
			.pObjectName = mvkAPIObj ? mvkAPIObj->getDebugName().UTF8String : nullptr
		};
		VkDebugUtilsMessengerCallbackDataEXT dumcbd = {
			.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CALLBACK_DATA_EXT,
			.pNext = nullptr,
			.flags = 0,
			.pMessageIdName = mvkGetReportingLevelString(logLevel),
			.messageIdNumber = 0,
			.pMessage = pMessage,
			.queueLabelCount = 0,
			.pQueueLabels = nullptr,
			.cmdBufLabelCount = 0,
			.pCmdBufLabels = nullptr,
			.objectCount = 1,
			.pObjects = &duObjName
		};
		debugUtilsMessage(getVkDebugUtilsMessageSeverityFlagBitsFromLogLevel(logLevel),
						  getVkDebugUtilsMessageTypesFlagBitsFromLogLevel(logLevel),
						  &dumcbd);
	}
}

VkDebugReportFlagsEXT MVKInstance::getVkDebugReportFlagsFromLogLevel(MVKConfigLogLevel logLevel) {
	switch (logLevel) {
		case MVK_CONFIG_LOG_LEVEL_ERROR:    return VK_DEBUG_REPORT_ERROR_BIT_EXT;
		case MVK_CONFIG_LOG_LEVEL_WARNING:  return VK_DEBUG_REPORT_WARNING_BIT_EXT;
		case MVK_CONFIG_LOG_LEVEL_INFO:     return VK_DEBUG_REPORT_INFORMATION_BIT_EXT;
		case MVK_CONFIG_LOG_LEVEL_DEBUG:    return VK_DEBUG_REPORT_DEBUG_BIT_EXT;
		default:                            return VK_DEBUG_REPORT_ERROR_BIT_EXT;
	}
}

VkDebugUtilsMessageSeverityFlagBitsEXT MVKInstance::getVkDebugUtilsMessageSeverityFlagBitsFromLogLevel(MVKConfigLogLevel logLevel) {
	switch (logLevel) {
		case MVK_CONFIG_LOG_LEVEL_ERROR:    return VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
		case MVK_CONFIG_LOG_LEVEL_WARNING:  return VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT;
		case MVK_CONFIG_LOG_LEVEL_INFO:     return VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT;
		case MVK_CONFIG_LOG_LEVEL_DEBUG:    return VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT;
		default:                            return VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
	}
}

VkDebugUtilsMessageTypeFlagsEXT MVKInstance::getVkDebugUtilsMessageTypesFlagBitsFromLogLevel(MVKConfigLogLevel logLevel) {
	switch (logLevel) {
		case MVK_CONFIG_LOG_LEVEL_ERROR:    return VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT;
		case MVK_CONFIG_LOG_LEVEL_WARNING:  return VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT;
		case MVK_CONFIG_LOG_LEVEL_DEBUG:    return VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT;
		case MVK_CONFIG_LOG_LEVEL_INFO:     return VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT;
		default:                            return VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT;
	}
}


#pragma mark Object Creation

MVKInstance::MVKInstance(const VkInstanceCreateInfo* pCreateInfo) : _enabledExtensions(this) {

	initDebugCallbacks(pCreateInfo);	// Do before any creation activities

	mvkSetOrClear(&_appInfo, pCreateInfo->pApplicationInfo);
    if (_appInfo.apiVersion == 0) {
        _appInfo.apiVersion = VK_API_VERSION_1_0;   // Default
    }
    else if (MVK_VULKAN_API_VERSION_CONFORM(_appInfo.apiVersion) > MVK_VULKAN_API_VERSION_CONFORM(MVK_VULKAN_API_VERSION)) {
        _appInfo.apiVersion = MVK_VULKAN_API_VERSION;
    }

	// Enable extensions before setting config or proc addrs.
	setConfigurationResult(verifyLayers(pCreateInfo->enabledLayerCount, pCreateInfo->ppEnabledLayerNames));
	MVKExtensionList* pWritableExtns = (MVKExtensionList*)&_enabledExtensions;
	setConfigurationResult(pWritableExtns->enable(pCreateInfo->enabledExtensionCount,
												  pCreateInfo->ppEnabledExtensionNames,
												  getDriverLayer()->getSupportedInstanceExtensions()));

	initMVKConfig(pCreateInfo);		// After extensions enabled.

	// If a maximum API version has been configured, honor it.
	auto cfgAPIVer = getMVKConfig().apiVersionToAdvertise;
	if (MVK_VULKAN_API_VERSION_CONFORM(_appInfo.apiVersion) > MVK_VULKAN_API_VERSION_CONFORM(cfgAPIVer)) {
		_appInfo.apiVersion = cfgAPIVer;
	}

	initProcAddrs();				// Init function pointers. After extensions enabled.
	logVersions();					// Log the MoltenVK and Vulkan versions. After config.

	// Populate the array of physical GPU devices.
	// This must be performed after extensions and config are established.
	// This effort creates a number of autoreleased Metal objects, so wrap it all in an autorelease pool.
	@autoreleasepool {
		NSArray<id<MTLDevice>>* mtlDevices = mvkGetAvailableMTLDevicesArray(this);
		_physicalDevices.reserve(mtlDevices.count);
		for (id<MTLDevice> mtlDev in mtlDevices) {
			_physicalDevices.push_back(new MVKPhysicalDevice(this, mtlDev));
		}
	}
    
	if (_physicalDevices.empty()) {
		setConfigurationResult(reportError(VK_ERROR_INCOMPATIBLE_DRIVER, "Vulkan is not supported on this device. MoltenVK requires Metal, which is not available on this device."));
	}

	if (MVK_MACCAT && !mvkOSVersionIsAtLeast(11.0)) {
		setConfigurationResult(reportError(VK_ERROR_INCOMPATIBLE_DRIVER, "To support Mac Catalyst, MoltenVK requires macOS 11.0 or above."));
	}

	// Warn if the Vulkan version requires buffer device address, but it is not available.
	if ( !mvkSupportsBufferDeviceAddress() && (MVK_VULKAN_API_VERSION_CONFORM(_appInfo.apiVersion) >= MVK_VULKAN_API_VERSION_CONFORM(VK_API_VERSION_1_3)) ) {
		reportWarning(VK_ERROR_FEATURE_NOT_PRESENT, "VkPhysicalDeviceVulkan12Features::bufferDeviceAddress is a mandatory feature as of Vulkan 1.3, but is not supported on this platform.");
	}

	MVKLogInfo("Created VkInstance for Vulkan version %s, as requested by app, with the following %d Vulkan extensions enabled:%s",
			   mvkGetVulkanVersionString(_appInfo.apiVersion).c_str(),
			   _enabledExtensions.getEnabledCount(),
			   _enabledExtensions.enabledNamesString("\n\t", true).c_str());

	_useCreationCallbacks = false;
}

void MVKInstance::initDebugCallbacks(const VkInstanceCreateInfo* pCreateInfo) {
	_useCreationCallbacks = true;
	_hasDebugReportCallbacks = false;
	_hasDebugUtilsMessengers = false;
	_debugReportCallbackLayerPrefix = getDriverLayer()->getName();

	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT:
				createDebugReportCallback((VkDebugReportCallbackCreateInfoEXT*)next, nullptr);
				break;
			case VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT:
				createDebugUtilsMessenger((VkDebugUtilsMessengerCreateInfoEXT*)next, nullptr);
				break;
			default:
				break;
		}
	}
}

// If the VK_EXT_layer_settings extension is enabled, initialize the local
// MVKConfiguration from the global version built from environment variables.
void MVKInstance::initMVKConfig(const VkInstanceCreateInfo* pCreateInfo) {

	if ( !_enabledExtensions.vk_EXT_layer_settings.enabled ) { return; }

	_mvkConfig = getGlobalMVKConfig();

	VkLayerSettingsCreateInfoEXT* pLSCreateInfo = nil;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_LAYER_SETTINGS_CREATE_INFO_EXT:
				pLSCreateInfo = (VkLayerSettingsCreateInfoEXT*)next;
				break;
			default:
				break;
		}
	}

	if ( !pLSCreateInfo ) { return; }

	for (uint32_t lsIdx = 0; lsIdx < pLSCreateInfo->settingCount; lsIdx++) {
		const auto* pSetting = &pLSCreateInfo->pSettings[lsIdx];

#define STR(name) #name
#define MVK_CONFIG_MEMBER(member, mbrType, name) \
		if(mvkStringsAreEqual(pSetting->pLayerName, getDriverLayer()->getName()) &&  \
		   mvkStringsAreEqual(pSetting->pSettingName, STR(MVK_CONFIG_##name))) {  \
			_mvkConfig.member = *(mbrType*)(pSetting->pValues);  \
			continue;  \
		}
#include "MVKConfigMembers.def"
	}
	mvkSetConfig(_mvkConfig, _mvkConfig, _mvkConfigStringHolders);
}

#define ADD_ENTRY_POINT_MAP(name, func, api, ext, isDev)  \
	_entryPoints[""#name] = { (PFN_vkVoidFunction)&func, ext, api,  isDev }

#define ADD_ENTRY_POINT(func, api, ext, isDev)	ADD_ENTRY_POINT_MAP(func, func, api, ext, isDev)

#define ADD_INST_ENTRY_POINT(func)				ADD_ENTRY_POINT(func, VK_API_VERSION_1_0, nullptr, false)
#define ADD_DVC_ENTRY_POINT(func)				ADD_ENTRY_POINT(func, VK_API_VERSION_1_0, nullptr, true)

// Add a core function.
#define ADD_INST_1_1_ENTRY_POINT(func)			ADD_ENTRY_POINT(func, VK_API_VERSION_1_1, nullptr, false)
#define ADD_INST_1_3_ENTRY_POINT(func)			ADD_ENTRY_POINT(func, VK_API_VERSION_1_3, nullptr, false)
#define ADD_DVC_1_1_ENTRY_POINT(func)			ADD_ENTRY_POINT(func, VK_API_VERSION_1_1, nullptr, true)
#define ADD_DVC_1_2_ENTRY_POINT(func)			ADD_ENTRY_POINT(func, VK_API_VERSION_1_2, nullptr, true)
#define ADD_DVC_1_3_ENTRY_POINT(func)			ADD_ENTRY_POINT(func, VK_API_VERSION_1_3, nullptr, true)
#define ADD_DVC_1_4_ENTRY_POINT(func)			ADD_ENTRY_POINT(func, VK_API_VERSION_1_4, nullptr, true)

// Add both the promoted core function under the promoted name, and the extension function under its original name.
#define ADD_INST_1_1_PROMOTED_ENTRY_POINT(func, EXT)	\
	ADD_INST_1_1_ENTRY_POINT(func);	\
	ADD_ENTRY_POINT_MAP(func##KHR, func, 0, VK_##EXT##_EXTENSION_NAME, false)

#define ADD_DVC_1_1_PROMOTED_ENTRY_POINT(func, EXT)	\
	ADD_DVC_1_1_ENTRY_POINT(func);	\
	ADD_ENTRY_POINT_MAP(func##KHR, func, 0, VK_##EXT##_EXTENSION_NAME, true)

#define ADD_DVC_1_2_PROMOTED_ENTRY_POINT(func, extSuffix, EXT) \
	ADD_DVC_1_2_ENTRY_POINT(func); \
	ADD_ENTRY_POINT_MAP(func##extSuffix, func, 0, VK_##EXT##_EXTENSION_NAME, true)

#define ADD_INST_1_3_PROMOTED_ENTRY_POINT(func, EXT)	\
	ADD_INST_1_3_ENTRY_POINT(func);	\
	ADD_ENTRY_POINT_MAP(func##KHR, func, 0, VK_##EXT##_EXTENSION_NAME, false)

#define ADD_DVC_1_3_PROMOTED_ENTRY_POINT(func, extSuffix, EXT) \
	ADD_DVC_1_3_ENTRY_POINT(func); \
	ADD_ENTRY_POINT_MAP(func##extSuffix, func, 0, VK_##EXT##_EXTENSION_NAME, true)

#define ADD_DVC_1_4_PROMOTED_ENTRY_POINT(func, extSuffix, EXT) \
	ADD_DVC_1_4_ENTRY_POINT(func); \
	ADD_ENTRY_POINT_MAP(func##extSuffix, func, 0, VK_##EXT##_EXTENSION_NAME, true)

// Add an extension function.
#define ADD_INST_EXT_ENTRY_POINT(func, EXT)					ADD_ENTRY_POINT(func, 0, VK_##EXT##_EXTENSION_NAME, false)
#define ADD_DVC_EXT_ENTRY_POINT(func, EXT)					ADD_ENTRY_POINT(func, 0, VK_##EXT##_EXTENSION_NAME, true)

// Add an extension function that aliases to another function from core or another extension.
#define ADD_INST_EXT_ENTRY_POINT_ALIAS(alias, func, EXT)	ADD_ENTRY_POINT_MAP(alias, func, 0, VK_##EXT##_EXTENSION_NAME, false)
#define ADD_DVC_EXT_ENTRY_POINT_ALIAS(alias, func, EXT)		ADD_ENTRY_POINT_MAP(alias, func, 0, VK_##EXT##_EXTENSION_NAME, true)

// Add a function that exists in both core and an extension. The function may have been promoted, without changing the function name.
#define ADD_INST_VER_OR_EXT_ENTRY_POINT(func, API, EXT1)	ADD_ENTRY_POINT(func, VK_API_VERSION_##API, VK_##EXT1##_EXTENSION_NAME, false)
#define ADD_DVC_VER_OR_EXT_ENTRY_POINT(func, API, EXT1)		ADD_ENTRY_POINT(func, VK_API_VERSION_##API, VK_##EXT1##_EXTENSION_NAME, true)

// Initializes the function pointer map.
void MVKInstance::initProcAddrs() {

	// Instance functions.
	ADD_INST_ENTRY_POINT(vkDestroyInstance);
	ADD_INST_ENTRY_POINT(vkEnumeratePhysicalDevices);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceFeatures);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceFormatProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceImageFormatProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceQueueFamilyProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceMemoryProperties);
	ADD_INST_ENTRY_POINT(vkCreateDevice);
	ADD_INST_ENTRY_POINT(vkEnumerateDeviceExtensionProperties);
	ADD_INST_ENTRY_POINT(vkEnumerateDeviceLayerProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceSparseImageFormatProperties);

	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkEnumeratePhysicalDeviceGroups, KHR_DEVICE_GROUP_CREATION);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceFeatures2, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceProperties2, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceFormatProperties2, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceImageFormatProperties2, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceQueueFamilyProperties2, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceMemoryProperties2, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceSparseImageFormatProperties2, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceExternalFenceProperties, KHR_EXTERNAL_FENCE_CAPABILITIES);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceExternalBufferProperties, KHR_EXTERNAL_MEMORY_CAPABILITIES);
	ADD_INST_1_1_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceExternalSemaphoreProperties, KHR_EXTERNAL_SEMAPHORE_CAPABILITIES);

	// Instance extension functions.
	ADD_INST_EXT_ENTRY_POINT(vkDestroySurfaceKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceSupportKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceCapabilitiesKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceFormatsKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfacePresentModesKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceCapabilities2KHR, KHR_GET_SURFACE_CAPABILITIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceFormats2KHR, KHR_GET_SURFACE_CAPABILITIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkCreateHeadlessSurfaceEXT, EXT_HEADLESS_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkCreateMetalSurfaceEXT, EXT_METAL_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkCreateDebugReportCallbackEXT, EXT_DEBUG_REPORT);
	ADD_INST_EXT_ENTRY_POINT(vkDestroyDebugReportCallbackEXT, EXT_DEBUG_REPORT);
	ADD_INST_EXT_ENTRY_POINT(vkDebugReportMessageEXT, EXT_DEBUG_REPORT);
	// n.b. Despite that VK_EXT_debug_utils is an instance extension, these functions are device functions.
	ADD_DVC_EXT_ENTRY_POINT(vkSetDebugUtilsObjectNameEXT, EXT_DEBUG_UTILS);
	ADD_DVC_EXT_ENTRY_POINT(vkSetDebugUtilsObjectTagEXT, EXT_DEBUG_UTILS);
	ADD_DVC_EXT_ENTRY_POINT(vkQueueBeginDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_DVC_EXT_ENTRY_POINT(vkQueueEndDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_DVC_EXT_ENTRY_POINT(vkQueueInsertDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdBeginDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdEndDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdInsertDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkCreateDebugUtilsMessengerEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkDestroyDebugUtilsMessengerEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkSubmitDebugUtilsMessageEXT, EXT_DEBUG_UTILS);

#ifdef VK_USE_PLATFORM_IOS_MVK
	ADD_INST_EXT_ENTRY_POINT(vkCreateIOSSurfaceMVK, MVK_IOS_SURFACE);
#endif
#ifdef VK_USE_PLATFORM_MACOS_MVK
	ADD_INST_EXT_ENTRY_POINT(vkCreateMacOSSurfaceMVK, MVK_MACOS_SURFACE);
#endif

	// For deprecated MoltenVK-specific functions, suppress compiler deprecation warning.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	ADD_INST_ENTRY_POINT(vkGetPerformanceStatisticsMVK);	// If VK_KHR_performance_query added, deprecate via ADD_INST_EXT_ENTRY_POINT(vkGetPerformanceStatisticsMVK, MVK_MOLTENVK).
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceMetalFeaturesMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkSetMoltenVKConfigurationMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetVersionStringsMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetMTLDeviceMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkSetMTLTextureMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetMTLTextureMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetMTLBufferMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkUseIOSurfaceMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetIOSurfaceMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetMTLCommandQueueMVK, MVK_MOLTENVK);
#pragma clang diagnostic pop

	// Device functions.
	ADD_DVC_ENTRY_POINT(vkGetDeviceProcAddr);
	ADD_DVC_ENTRY_POINT(vkDestroyDevice);
	ADD_DVC_ENTRY_POINT(vkGetDeviceQueue);
	ADD_DVC_ENTRY_POINT(vkQueueSubmit);
	ADD_DVC_ENTRY_POINT(vkQueueWaitIdle);
	ADD_DVC_ENTRY_POINT(vkDeviceWaitIdle);
	ADD_DVC_ENTRY_POINT(vkAllocateMemory);
	ADD_DVC_ENTRY_POINT(vkFreeMemory);
	ADD_DVC_ENTRY_POINT(vkMapMemory);
	ADD_DVC_ENTRY_POINT(vkUnmapMemory);
	ADD_DVC_ENTRY_POINT(vkFlushMappedMemoryRanges);
	ADD_DVC_ENTRY_POINT(vkInvalidateMappedMemoryRanges);
	ADD_DVC_ENTRY_POINT(vkGetDeviceMemoryCommitment);
	ADD_DVC_ENTRY_POINT(vkBindBufferMemory);
	ADD_DVC_ENTRY_POINT(vkBindImageMemory);
	ADD_DVC_ENTRY_POINT(vkGetBufferMemoryRequirements);
	ADD_DVC_ENTRY_POINT(vkGetImageMemoryRequirements);
	ADD_DVC_ENTRY_POINT(vkGetImageSparseMemoryRequirements);
	ADD_DVC_ENTRY_POINT(vkQueueBindSparse);
	ADD_DVC_ENTRY_POINT(vkCreateFence);
	ADD_DVC_ENTRY_POINT(vkDestroyFence);
	ADD_DVC_ENTRY_POINT(vkResetFences);
	ADD_DVC_ENTRY_POINT(vkGetFenceStatus);
	ADD_DVC_ENTRY_POINT(vkWaitForFences);
	ADD_DVC_ENTRY_POINT(vkCreateSemaphore);
	ADD_DVC_ENTRY_POINT(vkDestroySemaphore);
	ADD_DVC_ENTRY_POINT(vkCreateEvent);
	ADD_DVC_ENTRY_POINT(vkDestroyEvent);
	ADD_DVC_ENTRY_POINT(vkGetEventStatus);
	ADD_DVC_ENTRY_POINT(vkSetEvent);
	ADD_DVC_ENTRY_POINT(vkResetEvent);
	ADD_DVC_ENTRY_POINT(vkCreateQueryPool);
	ADD_DVC_ENTRY_POINT(vkDestroyQueryPool);
	ADD_DVC_ENTRY_POINT(vkGetQueryPoolResults);
	ADD_DVC_ENTRY_POINT(vkCreateBuffer);
	ADD_DVC_ENTRY_POINT(vkDestroyBuffer);
	ADD_DVC_ENTRY_POINT(vkCreateBufferView);
	ADD_DVC_ENTRY_POINT(vkDestroyBufferView);
	ADD_DVC_ENTRY_POINT(vkCreateImage);
	ADD_DVC_ENTRY_POINT(vkDestroyImage);
	ADD_DVC_ENTRY_POINT(vkGetImageSubresourceLayout);
	ADD_DVC_ENTRY_POINT(vkCreateImageView);
	ADD_DVC_ENTRY_POINT(vkDestroyImageView);
	ADD_DVC_ENTRY_POINT(vkCreateShaderModule);
	ADD_DVC_ENTRY_POINT(vkDestroyShaderModule);
	ADD_DVC_ENTRY_POINT(vkCreatePipelineCache);
	ADD_DVC_ENTRY_POINT(vkDestroyPipelineCache);
	ADD_DVC_ENTRY_POINT(vkGetPipelineCacheData);
	ADD_DVC_ENTRY_POINT(vkMergePipelineCaches);
	ADD_DVC_ENTRY_POINT(vkCreateGraphicsPipelines);
	ADD_DVC_ENTRY_POINT(vkCreateComputePipelines);
	ADD_DVC_ENTRY_POINT(vkDestroyPipeline);
	ADD_DVC_ENTRY_POINT(vkCreatePipelineLayout);
	ADD_DVC_ENTRY_POINT(vkDestroyPipelineLayout);
	ADD_DVC_ENTRY_POINT(vkCreateSampler);
	ADD_DVC_ENTRY_POINT(vkDestroySampler);
	ADD_DVC_ENTRY_POINT(vkCreateDescriptorSetLayout);
	ADD_DVC_ENTRY_POINT(vkDestroyDescriptorSetLayout);
	ADD_DVC_ENTRY_POINT(vkCreateDescriptorPool);
	ADD_DVC_ENTRY_POINT(vkDestroyDescriptorPool);
	ADD_DVC_ENTRY_POINT(vkResetDescriptorPool);
	ADD_DVC_ENTRY_POINT(vkAllocateDescriptorSets);
	ADD_DVC_ENTRY_POINT(vkFreeDescriptorSets);
	ADD_DVC_ENTRY_POINT(vkUpdateDescriptorSets);
	ADD_DVC_ENTRY_POINT(vkCreateFramebuffer);
	ADD_DVC_ENTRY_POINT(vkDestroyFramebuffer);
	ADD_DVC_ENTRY_POINT(vkCreateRenderPass);
	ADD_DVC_ENTRY_POINT(vkDestroyRenderPass);
	ADD_DVC_ENTRY_POINT(vkGetRenderAreaGranularity);
	ADD_DVC_ENTRY_POINT(vkCreateCommandPool);
	ADD_DVC_ENTRY_POINT(vkDestroyCommandPool);
	ADD_DVC_ENTRY_POINT(vkResetCommandPool);
	ADD_DVC_ENTRY_POINT(vkAllocateCommandBuffers);
	ADD_DVC_ENTRY_POINT(vkFreeCommandBuffers);
	ADD_DVC_ENTRY_POINT(vkBeginCommandBuffer);
	ADD_DVC_ENTRY_POINT(vkEndCommandBuffer);
	ADD_DVC_ENTRY_POINT(vkResetCommandBuffer);
	ADD_DVC_ENTRY_POINT(vkCmdBindPipeline);
	ADD_DVC_ENTRY_POINT(vkCmdSetViewport);
	ADD_DVC_ENTRY_POINT(vkCmdSetScissor);
	ADD_DVC_ENTRY_POINT(vkCmdSetLineWidth);
	ADD_DVC_ENTRY_POINT(vkCmdSetDepthBias);
	ADD_DVC_ENTRY_POINT(vkCmdSetBlendConstants);
	ADD_DVC_ENTRY_POINT(vkCmdSetDepthBounds);
	ADD_DVC_ENTRY_POINT(vkCmdSetStencilCompareMask);
	ADD_DVC_ENTRY_POINT(vkCmdSetStencilWriteMask);
	ADD_DVC_ENTRY_POINT(vkCmdSetStencilReference);
	ADD_DVC_ENTRY_POINT(vkCmdBindDescriptorSets);
	ADD_DVC_ENTRY_POINT(vkCmdBindIndexBuffer);
	ADD_DVC_ENTRY_POINT(vkCmdBindVertexBuffers);
	ADD_DVC_ENTRY_POINT(vkCmdDraw);
	ADD_DVC_ENTRY_POINT(vkCmdDrawIndexed);
	ADD_DVC_ENTRY_POINT(vkCmdDrawIndirect);
	ADD_DVC_ENTRY_POINT(vkCmdDrawIndexedIndirect);
	ADD_DVC_ENTRY_POINT(vkCmdDispatch);
	ADD_DVC_ENTRY_POINT(vkCmdDispatchIndirect);
	ADD_DVC_ENTRY_POINT(vkCmdCopyBuffer);
	ADD_DVC_ENTRY_POINT(vkCmdCopyImage);
	ADD_DVC_ENTRY_POINT(vkCmdBlitImage);
	ADD_DVC_ENTRY_POINT(vkCmdCopyBufferToImage);
	ADD_DVC_ENTRY_POINT(vkCmdCopyImageToBuffer);
	ADD_DVC_ENTRY_POINT(vkCmdUpdateBuffer);
	ADD_DVC_ENTRY_POINT(vkCmdFillBuffer);
	ADD_DVC_ENTRY_POINT(vkCmdClearColorImage);
	ADD_DVC_ENTRY_POINT(vkCmdClearDepthStencilImage);
	ADD_DVC_ENTRY_POINT(vkCmdClearAttachments);
	ADD_DVC_ENTRY_POINT(vkCmdResolveImage);
	ADD_DVC_ENTRY_POINT(vkCmdSetEvent);
	ADD_DVC_ENTRY_POINT(vkCmdResetEvent);
	ADD_DVC_ENTRY_POINT(vkCmdWaitEvents);
	ADD_DVC_ENTRY_POINT(vkCmdPipelineBarrier);
	ADD_DVC_ENTRY_POINT(vkCmdBeginQuery);
	ADD_DVC_ENTRY_POINT(vkCmdEndQuery);
	ADD_DVC_ENTRY_POINT(vkCmdResetQueryPool);
	ADD_DVC_ENTRY_POINT(vkCmdWriteTimestamp);
	ADD_DVC_ENTRY_POINT(vkCmdCopyQueryPoolResults);
	ADD_DVC_ENTRY_POINT(vkCmdPushConstants);
	ADD_DVC_ENTRY_POINT(vkCmdBeginRenderPass);
	ADD_DVC_ENTRY_POINT(vkCmdNextSubpass);
	ADD_DVC_ENTRY_POINT(vkCmdEndRenderPass);
	ADD_DVC_ENTRY_POINT(vkCmdExecuteCommands);

	ADD_DVC_1_1_ENTRY_POINT(vkGetDeviceQueue2);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkBindBufferMemory2, KHR_BIND_MEMORY_2);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkBindImageMemory2, KHR_BIND_MEMORY_2);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkGetBufferMemoryRequirements2, KHR_GET_MEMORY_REQUIREMENTS_2);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkGetImageMemoryRequirements2, KHR_GET_MEMORY_REQUIREMENTS_2);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkGetImageSparseMemoryRequirements2, KHR_GET_MEMORY_REQUIREMENTS_2);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkGetDeviceGroupPeerMemoryFeatures, KHR_DEVICE_GROUP);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkCreateDescriptorUpdateTemplate, KHR_DESCRIPTOR_UPDATE_TEMPLATE);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkDestroyDescriptorUpdateTemplate, KHR_DESCRIPTOR_UPDATE_TEMPLATE);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkUpdateDescriptorSetWithTemplate, KHR_DESCRIPTOR_UPDATE_TEMPLATE);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkGetDescriptorSetLayoutSupport, KHR_MAINTENANCE3);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkCreateSamplerYcbcrConversion, KHR_SAMPLER_YCBCR_CONVERSION);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkDestroySamplerYcbcrConversion, KHR_SAMPLER_YCBCR_CONVERSION);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkTrimCommandPool, KHR_MAINTENANCE1);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkCmdSetDeviceMask, KHR_DEVICE_GROUP);
	ADD_DVC_1_1_PROMOTED_ENTRY_POINT(vkCmdDispatchBase, KHR_DEVICE_GROUP);
	ADD_DVC_VER_OR_EXT_ENTRY_POINT(vkGetDeviceGroupPresentCapabilitiesKHR, 1_1, KHR_DEVICE_GROUP);	// Promoted to Vulkan 1.1 under same name
	ADD_DVC_VER_OR_EXT_ENTRY_POINT(vkGetDeviceGroupSurfacePresentModesKHR, 1_1, KHR_DEVICE_GROUP);	// Promoted to Vulkan 1.1 under same name
	ADD_DVC_VER_OR_EXT_ENTRY_POINT(vkGetPhysicalDevicePresentRectanglesKHR, 1_1, KHR_DEVICE_GROUP);	// Promoted to Vulkan 1.1 under same name
	ADD_DVC_VER_OR_EXT_ENTRY_POINT(vkAcquireNextImage2KHR, 1_1, KHR_DEVICE_GROUP);					// Promoted to Vulkan 1.1 under same name

	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkCmdBeginRenderPass2, KHR, KHR_CREATE_RENDERPASS_2);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkCmdDrawIndexedIndirectCount, KHR, KHR_DRAW_INDIRECT_COUNT);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkCmdDrawIndirectCount, KHR, KHR_DRAW_INDIRECT_COUNT);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkCmdEndRenderPass2, KHR, KHR_CREATE_RENDERPASS_2);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkCmdNextSubpass2, KHR, KHR_CREATE_RENDERPASS_2);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkCreateRenderPass2, KHR, KHR_CREATE_RENDERPASS_2);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkGetBufferDeviceAddress, KHR, KHR_BUFFER_DEVICE_ADDRESS);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkGetBufferOpaqueCaptureAddress, KHR, KHR_BUFFER_DEVICE_ADDRESS);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkGetDeviceMemoryOpaqueCaptureAddress, KHR, KHR_BUFFER_DEVICE_ADDRESS);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkGetSemaphoreCounterValue, KHR, KHR_TIMELINE_SEMAPHORE);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkGetBufferDeviceAddress, EXT, EXT_BUFFER_DEVICE_ADDRESS);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkResetQueryPool, EXT, EXT_HOST_QUERY_RESET);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkSignalSemaphore, KHR, KHR_TIMELINE_SEMAPHORE);
	ADD_DVC_1_2_PROMOTED_ENTRY_POINT(vkWaitSemaphores, KHR, KHR_TIMELINE_SEMAPHORE);

	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdBeginRendering, KHR, KHR_DYNAMIC_RENDERING);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdBindVertexBuffers2, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdBlitImage2, KHR, KHR_COPY_COMMANDS_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdCopyBuffer2, KHR, KHR_COPY_COMMANDS_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdCopyBufferToImage2, KHR, KHR_COPY_COMMANDS_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdCopyImage2, KHR, KHR_COPY_COMMANDS_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdCopyImageToBuffer2, KHR, KHR_COPY_COMMANDS_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdEndRendering, KHR, KHR_DYNAMIC_RENDERING);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdPipelineBarrier2, KHR, KHR_SYNCHRONIZATION_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdResetEvent2, KHR, KHR_SYNCHRONIZATION_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdResolveImage2, KHR, KHR_COPY_COMMANDS_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetCullMode, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetDepthBiasEnable, EXT, EXT_EXTENDED_DYNAMIC_STATE_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetDepthBoundsTestEnable, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetDepthCompareOp, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetDepthTestEnable, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetDepthWriteEnable, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetEvent2, KHR, KHR_SYNCHRONIZATION_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetFrontFace, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetPrimitiveRestartEnable, EXT, EXT_EXTENDED_DYNAMIC_STATE_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetPrimitiveTopology, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetRasterizerDiscardEnable, EXT, EXT_EXTENDED_DYNAMIC_STATE_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetScissorWithCount, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetStencilOp, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetStencilTestEnable, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdSetViewportWithCount, EXT, EXT_EXTENDED_DYNAMIC_STATE);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdWaitEvents2, KHR, KHR_SYNCHRONIZATION_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCmdWriteTimestamp2, KHR, KHR_SYNCHRONIZATION_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkCreatePrivateDataSlot, EXT, EXT_PRIVATE_DATA);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkDestroyPrivateDataSlot, EXT, EXT_PRIVATE_DATA);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkGetDeviceBufferMemoryRequirements, KHR, KHR_MAINTENANCE_4);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkGetDeviceImageMemoryRequirements, KHR, KHR_MAINTENANCE_4);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkGetDeviceImageSparseMemoryRequirements, KHR, KHR_MAINTENANCE_4);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkGetPrivateData, EXT, EXT_PRIVATE_DATA);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkQueueSubmit2, KHR, KHR_SYNCHRONIZATION_2);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkSetPrivateData, EXT, EXT_PRIVATE_DATA);
	ADD_DVC_1_3_PROMOTED_ENTRY_POINT(vkGetPhysicalDeviceToolProperties, EXT, EXT_TOOLING_INFO);

	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCmdBindIndexBuffer2, KHR, KHR_MAINTENANCE_5);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkGetRenderingAreaGranularity, KHR, KHR_MAINTENANCE_5);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkGetImageSubresourceLayout2, KHR, KHR_MAINTENANCE_5);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkGetDeviceImageSubresourceLayout, KHR, KHR_MAINTENANCE_5);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCmdBindDescriptorSets2, KHR, KHR_MAINTENANCE_6);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCmdPushConstants2, KHR, KHR_MAINTENANCE_6);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCmdPushDescriptorSet2, KHR, KHR_MAINTENANCE_6);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCmdPushDescriptorSetWithTemplate2, KHR, KHR_MAINTENANCE_6);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkMapMemory2, KHR, KHR_MAP_MEMORY_2);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkUnmapMemory2, KHR, KHR_MAP_MEMORY_2);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCmdPushDescriptorSet, KHR, KHR_PUSH_DESCRIPTOR);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCmdPushDescriptorSetWithTemplate, KHR, KHR_PUSH_DESCRIPTOR);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCopyImageToImage, EXT, EXT_HOST_IMAGE_COPY);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCopyImageToMemory, EXT, EXT_HOST_IMAGE_COPY);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkCopyMemoryToImage, EXT, EXT_HOST_IMAGE_COPY);
	ADD_DVC_EXT_ENTRY_POINT_ALIAS(vkGetImageSubresourceLayout2EXT, vkGetImageSubresourceLayout2, EXT_HOST_IMAGE_COPY);
	ADD_DVC_1_4_PROMOTED_ENTRY_POINT(vkTransitionImageLayout, EXT, EXT_HOST_IMAGE_COPY);

	// Device extension functions.
	ADD_DVC_EXT_ENTRY_POINT(vkGetCalibratedTimestampsKHR, KHR_CALIBRATED_TIMESTAMPS);
	ADD_DVC_EXT_ENTRY_POINT(vkGetPhysicalDeviceCalibrateableTimeDomainsKHR, KHR_CALIBRATED_TIMESTAMPS);
    ADD_DVC_EXT_ENTRY_POINT(vkCreateDeferredOperationKHR, KHR_DEFERRED_HOST_OPERATIONS);
    ADD_DVC_EXT_ENTRY_POINT(vkDeferredOperationJoinKHR, KHR_DEFERRED_HOST_OPERATIONS);
    ADD_DVC_EXT_ENTRY_POINT(vkDestroyDeferredOperationKHR, KHR_DEFERRED_HOST_OPERATIONS);
    ADD_DVC_EXT_ENTRY_POINT(vkGetDeferredOperationMaxConcurrencyKHR, KHR_DEFERRED_HOST_OPERATIONS);
    ADD_DVC_EXT_ENTRY_POINT(vkGetDeferredOperationResultKHR, KHR_DEFERRED_HOST_OPERATIONS);
	ADD_DVC_EXT_ENTRY_POINT(vkCreateSwapchainKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT_ENTRY_POINT(vkDestroySwapchainKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT_ENTRY_POINT(vkGetSwapchainImagesKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT_ENTRY_POINT(vkAcquireNextImageKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT_ENTRY_POINT(vkQueuePresentKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT_ENTRY_POINT(vkWaitForPresentKHR, KHR_PRESENT_WAIT);
	ADD_DVC_EXT_ENTRY_POINT_ALIAS(vkGetCalibratedTimestampsEXT, vkGetCalibratedTimestampsKHR, EXT_CALIBRATED_TIMESTAMPS);
	ADD_DVC_EXT_ENTRY_POINT_ALIAS(vkGetPhysicalDeviceCalibrateableTimeDomainsEXT, vkGetPhysicalDeviceCalibrateableTimeDomainsKHR, EXT_CALIBRATED_TIMESTAMPS);
	ADD_DVC_EXT_ENTRY_POINT(vkDebugMarkerSetObjectTagEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkDebugMarkerSetObjectNameEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdDebugMarkerBeginEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdDebugMarkerEndEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdDebugMarkerInsertEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkGetMemoryHostPointerPropertiesEXT, EXT_EXTERNAL_MEMORY_HOST);
	ADD_DVC_EXT_ENTRY_POINT(vkSetHdrMetadataEXT, EXT_HDR_METADATA);
	ADD_DVC_EXT_ENTRY_POINT(vkExportMetalObjectsEXT, EXT_METAL_OBJECTS);
	ADD_DVC_EXT_ENTRY_POINT(vkGetPhysicalDeviceMultisamplePropertiesEXT, EXT_SAMPLE_LOCATIONS);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetSampleLocationsEXT, EXT_SAMPLE_LOCATIONS);
	ADD_DVC_EXT_ENTRY_POINT(vkReleaseSwapchainImagesEXT, EXT_SWAPCHAIN_MAINTENANCE_1);
	ADD_DVC_EXT_ENTRY_POINT(vkGetRefreshCycleDurationGOOGLE, GOOGLE_DISPLAY_TIMING);
	ADD_DVC_EXT_ENTRY_POINT(vkGetPastPresentationTimingGOOGLE, GOOGLE_DISPLAY_TIMING);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetLogicOpEXT, EXT_EXTENDED_DYNAMIC_STATE_2);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetPatchControlPointsEXT, EXT_EXTENDED_DYNAMIC_STATE_2);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetAlphaToCoverageEnableEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetAlphaToOneEnableEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetColorBlendAdvancedEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetColorBlendEnableEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetColorBlendEquationEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetColorWriteMaskEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetConservativeRasterizationModeEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetDepthClampEnableEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetDepthClipEnableEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetDepthClipNegativeOneToOneEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetExtraPrimitiveOverestimationSizeEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetLineRasterizationModeEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetLineStippleEnableEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetLogicOpEnableEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetPolygonModeEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetProvokingVertexModeEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetRasterizationSamplesEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetRasterizationStreamEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetSampleLocationsEnableEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetSampleMaskEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetTessellationDomainOriginEXT, EXT_EXTENDED_DYNAMIC_STATE_3);
	ADD_DVC_EXT_ENTRY_POINT(vkGetMemoryMetalHandleEXT, EXT_EXTERNAL_MEMORY_METAL);
	ADD_DVC_EXT_ENTRY_POINT(vkGetMemoryMetalHandlePropertiesEXT, EXT_EXTERNAL_MEMORY_METAL);
}

void MVKInstance::logVersions() {
	static_assert(string_view(MVK_STRINGIFY(MVK_FRAMEWORK_VERSION)) == MVK_VERSION_STRING, "Xcode build setting CURRENT_PROJECT_VERSION must be identical to the MoltenVK version (MVK_VERSION_STRING).");

	MVKExtensionList allExtns(this, true);
	MVKLogInfo("MoltenVK version %s, supporting Vulkan version %s.\n\tThe following %d Vulkan extensions are supported:%s",
			   MVK_VERSION_STRING,
			   mvkGetVulkanVersionString(getMVKConfig().apiVersionToAdvertise).c_str(),
			   allExtns.getEnabledCount(),
			   allExtns.enabledNamesString("\n\t", true).c_str());
}

VkResult MVKInstance::verifyLayers(uint32_t count, const char* const* names) {
    VkResult result = VK_SUCCESS;
    for (uint32_t i = 0; i < count; i++) {
        if ( !getLayerManager()->getLayerNamed(names[i]) ) {
            result = reportError(VK_ERROR_LAYER_NOT_PRESENT, "Vulkan layer %s is not supported.", names[i]);
        }
    }
    return result;
}

MVKInstance::~MVKInstance() {
	_useCreationCallbacks = true;
	mvkDestroyContainerContents(_physicalDevices);

	// Since this message may invoke debug callbacks, do it before locking callbacks.
	MVKLogInfo("Destroying VkInstance for Vulkan version %s with %d Vulkan extensions enabled.",
			   mvkGetVulkanVersionString(_appInfo.apiVersion).c_str(),
			   _enabledExtensions.getEnabledCount());

	lock_guard<mutex> lock(_dcbLock);
	mvkDestroyContainerContents(_debugReportCallbacks);
	mvkDestroyContainerContents(_debugUtilMessengers);
}

