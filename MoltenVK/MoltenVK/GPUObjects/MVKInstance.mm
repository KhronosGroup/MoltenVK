/*
 * MVKInstance.mm
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


#include "MVKInstance.h"
#include "MVKDevice.h"
#include "MVKFoundation.h"
#include "MVKSurface.h"
#include "MVKOSExtensions.h"
#include "MVKLogging.h"

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

void MVKInstance::debugReportMessage(MVKVulkanAPIObject* mvkAPIObj, int aslLvl, const char* pMessage) {

	if (_hasDebugReportCallbacks) {
		VkDebugReportFlagsEXT flags = getVkDebugReportFlagsFromASLLevel(aslLvl);
		uint64_t object = (uint64_t)(mvkAPIObj ? mvkAPIObj->getVkHandle() : nullptr);
		VkDebugReportObjectTypeEXT objectType = mvkAPIObj ? mvkAPIObj->getVkDebugReportObjectType() : VK_DEBUG_REPORT_OBJECT_TYPE_UNKNOWN_EXT;
		debugReportMessage(flags, objectType, object, 0, 0, _debugReportCallbackLayerPrefix, pMessage);
	}

	if (_hasDebugUtilsMessengers) {
		VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity = getVkDebugUtilsMessageSeverityFlagBitsFromASLLevel(aslLvl);
		uint64_t objectHandle = (uint64_t)(mvkAPIObj ? mvkAPIObj->getVkHandle() : nullptr);
		VkObjectType objectType = mvkAPIObj ? mvkAPIObj->getVkObjectType() : VK_OBJECT_TYPE_UNKNOWN;

		VkDebugUtilsObjectNameInfoEXT duObjName = {
			.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			.pNext = nullptr,
			.objectType = objectType,
			.objectHandle = objectHandle,
			.pObjectName = mvkAPIObj ? mvkAPIObj->getDebugName().UTF8String : nullptr
		};
		VkDebugUtilsMessengerCallbackDataEXT dumcbd = {
			.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CALLBACK_DATA_EXT,
			.pNext = nullptr,
			.flags = 0,
			.pMessageIdName = nullptr,
			.messageIdNumber = 0,
			.pMessage = pMessage,
			.queueLabelCount = 0,
			.pQueueLabels = nullptr,
			.cmdBufLabelCount = 0,
			.pCmdBufLabels = nullptr,
			.objectCount = 1,
			.pObjects = &duObjName
		};
		debugUtilsMessage(messageSeverity, VK_DEBUG_UTILS_MESSAGE_TYPE_FLAG_BITS_MAX_ENUM_EXT, &dumcbd);
	}
}

VkDebugReportFlagsEXT MVKInstance::getVkDebugReportFlagsFromASLLevel(int aslLvl) {
	switch (aslLvl) {
		case ASL_LEVEL_DEBUG:
			return VK_DEBUG_REPORT_DEBUG_BIT_EXT;

		case ASL_LEVEL_INFO:
		case ASL_LEVEL_NOTICE:
			return VK_DEBUG_REPORT_INFORMATION_BIT_EXT;

		case ASL_LEVEL_WARNING:
			return VK_DEBUG_REPORT_WARNING_BIT_EXT;

		case ASL_LEVEL_ERR:
		case ASL_LEVEL_CRIT:
		case ASL_LEVEL_ALERT:
		case ASL_LEVEL_EMERG:
		default:
			return VK_DEBUG_REPORT_ERROR_BIT_EXT;
	}
}

VkDebugUtilsMessageSeverityFlagBitsEXT MVKInstance::getVkDebugUtilsMessageSeverityFlagBitsFromASLLevel(int aslLvl) {
	switch (aslLvl) {
		case ASL_LEVEL_DEBUG:
			return VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT;

		case ASL_LEVEL_INFO:
		case ASL_LEVEL_NOTICE:
			return VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT;

		case ASL_LEVEL_WARNING:
			return VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT;

		case ASL_LEVEL_ERR:
		case ASL_LEVEL_CRIT:
		case ASL_LEVEL_ALERT:
		case ASL_LEVEL_EMERG:
		default:
			return VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
	}
}

void MVKInstance::startAutoGPUCapture(int32_t autoGPUCaptureScope, id mtlCaptureObject) {

	if (_isCurrentlyAutoGPUCapturing || (_autoGPUCaptureScope != autoGPUCaptureScope)) { return; }

	_isCurrentlyAutoGPUCapturing = true;

	@autoreleasepool {
		MTLCaptureManager *captureMgr = [MTLCaptureManager sharedCaptureManager];

		MTLCaptureDescriptor *captureDesc = [[MTLCaptureDescriptor new] autorelease];
		captureDesc.captureObject = mtlCaptureObject;
		captureDesc.destination = MTLCaptureDestinationDeveloperTools;

		if ( !_autoGPUCaptureOutputFile.empty() ) {
			if ([captureMgr respondsToSelector: @selector(supportsDestination:)] &&
				[captureMgr supportsDestination: MTLCaptureDestinationGPUTraceDocument] ) {

				NSString* filePath = [[NSString stringWithUTF8String: _autoGPUCaptureOutputFile.c_str()] stringByExpandingTildeInPath];
				MVKLogInfo("Capturing GPU trace to file %s.", filePath.UTF8String);

				captureDesc.destination = MTLCaptureDestinationGPUTraceDocument;
				captureDesc.outputURL = [NSURL fileURLWithPath: filePath];

			} else {
				reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Capturing GPU traces to a file requires macOS 10.15 or iOS 13.0. Falling back to Xcode GPU capture.");
			}
		} else {
			MVKLogInfo("Capturing GPU trace to Xcode.");
		}

		NSError *err = nil;
		if ( ![captureMgr startCaptureWithDescriptor: captureDesc error: &err] ) {
			reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to automatically start GPU capture session (Error code %li): %s", (long)err.code, err.localizedDescription.UTF8String);
		}
	}
}

void MVKInstance::stopAutoGPUCapture(int32_t autoGPUCaptureScope) {
	if (_isCurrentlyAutoGPUCapturing && _autoGPUCaptureScope == autoGPUCaptureScope) {
		[[MTLCaptureManager sharedCaptureManager] stopCapture];
		_isCurrentlyAutoGPUCapturing = false;
	}
}

#pragma mark Object Creation

// Returns an autoreleased array containing the MTLDevices available on this system, sorted according to power,
// with higher power GPU's at the front of the array. This ensures that a lazy app that simply
// grabs the first GPU will get a high-power one by default. If the MVK_CONFIG_FORCE_LOW_POWER_GPU
// env var or build setting is set, the returned array will only include low-power devices.
// If Metal is not supported, returns an empty array.
static NSArray<id<MTLDevice>>* availableMTLDevicesArray() {
	NSMutableArray* mtlDevs = [NSMutableArray array];

#if MVK_MACOS
	NSArray* rawMTLDevs = [MTLCopyAllDevices() autorelease];
	if (rawMTLDevs) {
		bool forceLowPower;
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(forceLowPower, MVK_CONFIG_FORCE_LOW_POWER_GPU);

		// Populate the array of appropriate MTLDevices
		for (id<MTLDevice> md in rawMTLDevs) {
			if ( !forceLowPower || md.isLowPower ) { [mtlDevs addObject: md]; }
		}

		// Sort by power
		[mtlDevs sortUsingComparator: ^(id<MTLDevice> md1, id<MTLDevice> md2) {
			BOOL md1IsLP = md1.isLowPower;
			BOOL md2IsLP = md2.isLowPower;

			if (md1IsLP == md2IsLP) {
				// If one device is headless and the other one is not, select the
				// one that is not headless first.
				BOOL md1IsHeadless = md1.isHeadless;
				BOOL md2IsHeadless = md2.isHeadless;
				if (md1IsHeadless == md2IsHeadless ) {
					return NSOrderedSame;
				}
				return md2IsHeadless ? NSOrderedAscending : NSOrderedDescending;
			}

			return md2IsLP ? NSOrderedAscending : NSOrderedDescending;
		}];

	}
#endif	// MVK_MACOS

#if MVK_IOS_OR_TVOS
	id<MTLDevice> md = [MTLCreateSystemDefaultDevice() autorelease];
	if (md) { [mtlDevs addObject: md]; }
#endif	// MVK_IOS_OR_TVOS

	return mtlDevs;		// retained
}

MVKInstance::MVKInstance(const VkInstanceCreateInfo* pCreateInfo) : _enabledExtensions(this) {

	initDebugCallbacks(pCreateInfo);	// Do before any creation activities

	mvkSetOrClear(&_appInfo, pCreateInfo->pApplicationInfo);
	if (_appInfo.apiVersion == 0) { _appInfo.apiVersion = VK_API_VERSION_1_0; }	// Default

	initProcAddrs();		// Init function pointers
	initConfig();

	setConfigurationResult(verifyLayers(pCreateInfo->enabledLayerCount, pCreateInfo->ppEnabledLayerNames));
	MVKExtensionList* pWritableExtns = (MVKExtensionList*)&_enabledExtensions;
	setConfigurationResult(pWritableExtns->enable(pCreateInfo->enabledExtensionCount,
												  pCreateInfo->ppEnabledExtensionNames,
												  getDriverLayer()->getSupportedInstanceExtensions()));
	logVersions();	// Log the MoltenVK and Vulkan versions

	// Populate the array of physical GPU devices.
	// This effort creates a number of autoreleased instances of Metal
	// and other Obj-C classes, so wrap it all in an autorelease pool.
	@autoreleasepool {
		NSArray<id<MTLDevice>>* mtlDevices = availableMTLDevicesArray();
		_physicalDevices.reserve(mtlDevices.count);
		for (id<MTLDevice> mtlDev in mtlDevices) {
			_physicalDevices.push_back(new MVKPhysicalDevice(this, mtlDev));
		}
	}

	if (_physicalDevices.empty()) {
		setConfigurationResult(reportError(VK_ERROR_INCOMPATIBLE_DRIVER, "Vulkan is not supported on this device. MoltenVK requires Metal, which is not available on this device."));
	}

	_isCurrentlyAutoGPUCapturing = false;

	if (MVK_MACCAT && !mvkOSVersionIsAtLeast(11.0)) {
		setConfigurationResult(reportError(VK_ERROR_INCOMPATIBLE_DRIVER, "To support Mac Catalyst, MoltenVK requires macOS 11.0 or above."));
	}

	MVKLogInfo("Created VkInstance with the following %d Vulkan extensions enabled:%s",
			   _enabledExtensions.getEnabledCount(),
			   _enabledExtensions.enabledNamesString("\n\t\t", true).c_str());

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

#define ADD_ENTRY_POINT(func, api, ext1, ext2, isDev)	_entryPoints[""#func] = { (PFN_vkVoidFunction)&func, api, ext1,  ext2,  isDev }

#define ADD_INST_ENTRY_POINT(func)						ADD_ENTRY_POINT(func, VK_API_VERSION_1_0, nullptr, nullptr, false)
#define ADD_DVC_ENTRY_POINT(func)						ADD_ENTRY_POINT(func, VK_API_VERSION_1_0, nullptr, nullptr, true)

#define ADD_INST_1_1_ENTRY_POINT(func)					ADD_ENTRY_POINT(func, VK_API_VERSION_1_1, nullptr, nullptr, false)
#define ADD_DVC_1_1_ENTRY_POINT(func)					ADD_ENTRY_POINT(func, VK_API_VERSION_1_1, nullptr, nullptr, true)

#define ADD_INST_EXT_ENTRY_POINT(func, EXT)			ADD_ENTRY_POINT(func, 0, VK_ ##EXT ##_EXTENSION_NAME, nullptr, false)
#define ADD_DVC_EXT_ENTRY_POINT(func, EXT)			ADD_ENTRY_POINT(func, 0, VK_ ##EXT ##_EXTENSION_NAME, nullptr, true)

#define ADD_INST_EXT2_ENTRY_POINT(func, EXT1, EXT2)	ADD_ENTRY_POINT(func, 0, VK_ ##EXT1 ##_EXTENSION_NAME, VK_ ##EXT2 ##_EXTENSION_NAME, false)
#define ADD_DVC_EXT2_ENTRY_POINT(func, EXT1, EXT2)	ADD_ENTRY_POINT(func, 0, VK_ ##EXT1 ##_EXTENSION_NAME, VK_ ##EXT2 ##_EXTENSION_NAME, true)

// Initializes the function pointer map.
void MVKInstance::initProcAddrs() {

	// Instance functions
	ADD_INST_ENTRY_POINT(vkDestroyInstance);
	ADD_INST_ENTRY_POINT(vkEnumeratePhysicalDevices);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceFeatures);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceFormatProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceImageFormatProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceQueueFamilyProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceMemoryProperties);
	ADD_INST_ENTRY_POINT(vkGetInstanceProcAddr);
	ADD_INST_ENTRY_POINT(vkCreateDevice);
	ADD_INST_ENTRY_POINT(vkEnumerateDeviceExtensionProperties);
	ADD_INST_ENTRY_POINT(vkEnumerateDeviceLayerProperties);
	ADD_INST_ENTRY_POINT(vkGetPhysicalDeviceSparseImageFormatProperties);

	ADD_INST_1_1_ENTRY_POINT(vkEnumeratePhysicalDeviceGroups);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceFeatures2);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceProperties2);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceFormatProperties2);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceImageFormatProperties2);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceQueueFamilyProperties2);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceMemoryProperties2);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceSparseImageFormatProperties2);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceExternalFenceProperties);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceExternalBufferProperties);
	ADD_INST_1_1_ENTRY_POINT(vkGetPhysicalDeviceExternalSemaphoreProperties);

	// Device functions:
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
	ADD_DVC_1_1_ENTRY_POINT(vkBindBufferMemory2);
	ADD_DVC_1_1_ENTRY_POINT(vkBindImageMemory2);
	ADD_DVC_1_1_ENTRY_POINT(vkGetBufferMemoryRequirements2);
	ADD_DVC_1_1_ENTRY_POINT(vkGetImageMemoryRequirements2);
	ADD_DVC_1_1_ENTRY_POINT(vkGetImageSparseMemoryRequirements2);
	ADD_DVC_1_1_ENTRY_POINT(vkGetDeviceGroupPeerMemoryFeatures);
	ADD_DVC_1_1_ENTRY_POINT(vkCreateDescriptorUpdateTemplate);
	ADD_DVC_1_1_ENTRY_POINT(vkDestroyDescriptorUpdateTemplate);
	ADD_DVC_1_1_ENTRY_POINT(vkUpdateDescriptorSetWithTemplate);
	ADD_DVC_1_1_ENTRY_POINT(vkGetDescriptorSetLayoutSupport);
	ADD_DVC_1_1_ENTRY_POINT(vkCreateSamplerYcbcrConversion);
	ADD_DVC_1_1_ENTRY_POINT(vkDestroySamplerYcbcrConversion);
	ADD_DVC_1_1_ENTRY_POINT(vkTrimCommandPool);
	ADD_DVC_1_1_ENTRY_POINT(vkCmdSetDeviceMask);
	ADD_DVC_1_1_ENTRY_POINT(vkCmdDispatchBase);

	// Instance extension functions:
	ADD_INST_EXT_ENTRY_POINT(vkEnumeratePhysicalDeviceGroupsKHR, KHR_DEVICE_GROUP_CREATION);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceExternalFencePropertiesKHR, KHR_EXTERNAL_FENCE_CAPABILITIES);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceExternalBufferPropertiesKHR, KHR_EXTERNAL_MEMORY_CAPABILITIES);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceExternalSemaphorePropertiesKHR, KHR_EXTERNAL_SEMAPHORE_CAPABILITIES);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceFeatures2KHR, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceProperties2KHR, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceFormatProperties2KHR, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceImageFormatProperties2KHR, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceQueueFamilyProperties2KHR, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceMemoryProperties2KHR, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSparseImageFormatProperties2KHR, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkDestroySurfaceKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceSupportKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceCapabilitiesKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceFormatsKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfacePresentModesKHR, KHR_SURFACE);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceCapabilities2KHR, KHR_GET_SURFACE_CAPABILITIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceSurfaceFormats2KHR, KHR_GET_SURFACE_CAPABILITIES_2);
	ADD_INST_EXT_ENTRY_POINT(vkCreateDebugReportCallbackEXT, EXT_DEBUG_REPORT);
	ADD_INST_EXT_ENTRY_POINT(vkDestroyDebugReportCallbackEXT, EXT_DEBUG_REPORT);
	ADD_INST_EXT_ENTRY_POINT(vkDebugReportMessageEXT, EXT_DEBUG_REPORT);
	ADD_INST_EXT_ENTRY_POINT(vkSetDebugUtilsObjectNameEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkSetDebugUtilsObjectTagEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkQueueBeginDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkQueueEndDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkQueueInsertDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkCmdBeginDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkCmdEndDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkCmdInsertDebugUtilsLabelEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkCreateDebugUtilsMessengerEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkDestroyDebugUtilsMessengerEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkSubmitDebugUtilsMessageEXT, EXT_DEBUG_UTILS);
	ADD_INST_EXT_ENTRY_POINT(vkCreateMetalSurfaceEXT, EXT_METAL_SURFACE);

#ifdef VK_USE_PLATFORM_IOS_MVK
	ADD_INST_EXT_ENTRY_POINT(vkCreateIOSSurfaceMVK, MVK_IOS_SURFACE);
#endif
#ifdef VK_USE_PLATFORM_MACOS_MVK
	ADD_INST_EXT_ENTRY_POINT(vkCreateMacOSSurfaceMVK, MVK_MACOS_SURFACE);
#endif

	ADD_INST_EXT_ENTRY_POINT(vkGetMoltenVKConfigurationMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkSetMoltenVKConfigurationMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetPhysicalDeviceMetalFeaturesMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetPerformanceStatisticsMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetVersionStringsMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetMTLDeviceMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkSetMTLTextureMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetMTLTextureMVK, MVK_MOLTENVK);
    ADD_INST_EXT_ENTRY_POINT(vkGetMTLBufferMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkUseIOSurfaceMVK, MVK_MOLTENVK);
	ADD_INST_EXT_ENTRY_POINT(vkGetIOSurfaceMVK, MVK_MOLTENVK);

	// Device extension functions:
	ADD_DVC_EXT_ENTRY_POINT(vkBindBufferMemory2KHR, KHR_BIND_MEMORY_2);
	ADD_DVC_EXT_ENTRY_POINT(vkBindImageMemory2KHR, KHR_BIND_MEMORY_2);
	ADD_DVC_EXT_ENTRY_POINT(vkCreateRenderPass2KHR, KHR_CREATE_RENDERPASS_2);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdBeginRenderPass2KHR, KHR_CREATE_RENDERPASS_2);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdNextSubpass2KHR, KHR_CREATE_RENDERPASS_2);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdEndRenderPass2KHR, KHR_CREATE_RENDERPASS_2);
	ADD_DVC_EXT_ENTRY_POINT(vkCreateDescriptorUpdateTemplateKHR, KHR_DESCRIPTOR_UPDATE_TEMPLATE);
	ADD_DVC_EXT_ENTRY_POINT(vkDestroyDescriptorUpdateTemplateKHR, KHR_DESCRIPTOR_UPDATE_TEMPLATE);
	ADD_DVC_EXT_ENTRY_POINT(vkUpdateDescriptorSetWithTemplateKHR, KHR_DESCRIPTOR_UPDATE_TEMPLATE);
	ADD_DVC_EXT_ENTRY_POINT(vkGetDeviceGroupPeerMemoryFeaturesKHR, KHR_DEVICE_GROUP);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdSetDeviceMaskKHR, KHR_DEVICE_GROUP);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdDispatchBaseKHR, KHR_DEVICE_GROUP);
	ADD_DVC_EXT_ENTRY_POINT(vkGetBufferMemoryRequirements2KHR, KHR_GET_MEMORY_REQUIREMENTS_2);
	ADD_DVC_EXT_ENTRY_POINT(vkGetImageMemoryRequirements2KHR, KHR_GET_MEMORY_REQUIREMENTS_2);
	ADD_DVC_EXT_ENTRY_POINT(vkGetImageSparseMemoryRequirements2KHR, KHR_GET_MEMORY_REQUIREMENTS_2);
	ADD_DVC_EXT_ENTRY_POINT(vkTrimCommandPoolKHR, KHR_MAINTENANCE1);
	ADD_DVC_EXT_ENTRY_POINT(vkGetDescriptorSetLayoutSupportKHR, KHR_MAINTENANCE3);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdPushDescriptorSetKHR, KHR_PUSH_DESCRIPTOR);
	ADD_DVC_EXT2_ENTRY_POINT(vkCmdPushDescriptorSetWithTemplateKHR, KHR_PUSH_DESCRIPTOR, KHR_DESCRIPTOR_UPDATE_TEMPLATE);
	ADD_DVC_EXT_ENTRY_POINT(vkCreateSamplerYcbcrConversionKHR, KHR_SAMPLER_YCBCR_CONVERSION);
	ADD_DVC_EXT_ENTRY_POINT(vkDestroySamplerYcbcrConversionKHR, KHR_SAMPLER_YCBCR_CONVERSION);
	ADD_DVC_EXT_ENTRY_POINT(vkCreateSwapchainKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT_ENTRY_POINT(vkDestroySwapchainKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT_ENTRY_POINT(vkGetSwapchainImagesKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT_ENTRY_POINT(vkAcquireNextImageKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT_ENTRY_POINT(vkQueuePresentKHR, KHR_SWAPCHAIN);
	ADD_DVC_EXT2_ENTRY_POINT(vkGetDeviceGroupPresentCapabilitiesKHR, KHR_SWAPCHAIN, KHR_DEVICE_GROUP);
	ADD_DVC_EXT2_ENTRY_POINT(vkGetDeviceGroupSurfacePresentModesKHR, KHR_SWAPCHAIN, KHR_DEVICE_GROUP);
	ADD_DVC_EXT2_ENTRY_POINT(vkGetPhysicalDevicePresentRectanglesKHR, KHR_SWAPCHAIN, KHR_DEVICE_GROUP);
	ADD_DVC_EXT2_ENTRY_POINT(vkAcquireNextImage2KHR, KHR_SWAPCHAIN, KHR_DEVICE_GROUP);
	ADD_DVC_EXT_ENTRY_POINT(vkGetSemaphoreCounterValueKHR, KHR_TIMELINE_SEMAPHORE);
	ADD_DVC_EXT_ENTRY_POINT(vkSignalSemaphoreKHR, KHR_TIMELINE_SEMAPHORE);
	ADD_DVC_EXT_ENTRY_POINT(vkWaitSemaphoresKHR, KHR_TIMELINE_SEMAPHORE);
	ADD_DVC_EXT_ENTRY_POINT(vkDebugMarkerSetObjectTagEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkDebugMarkerSetObjectNameEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdDebugMarkerBeginEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdDebugMarkerEndEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkCmdDebugMarkerInsertEXT, EXT_DEBUG_MARKER);
	ADD_DVC_EXT_ENTRY_POINT(vkSetHdrMetadataEXT, EXT_HDR_METADATA);
	ADD_DVC_EXT_ENTRY_POINT(vkResetQueryPoolEXT, EXT_HOST_QUERY_RESET);
	ADD_DVC_EXT_ENTRY_POINT(vkCreatePrivateDataSlotEXT, EXT_PRIVATE_DATA);
	ADD_DVC_EXT_ENTRY_POINT(vkDestroyPrivateDataSlotEXT, EXT_PRIVATE_DATA);
	ADD_DVC_EXT_ENTRY_POINT(vkGetPrivateDataEXT, EXT_PRIVATE_DATA);
	ADD_DVC_EXT_ENTRY_POINT(vkSetPrivateDataEXT, EXT_PRIVATE_DATA);
	ADD_DVC_EXT_ENTRY_POINT(vkGetRefreshCycleDurationGOOGLE, GOOGLE_DISPLAY_TIMING);
	ADD_DVC_EXT_ENTRY_POINT(vkGetPastPresentationTimingGOOGLE, GOOGLE_DISPLAY_TIMING);

}

void MVKInstance::logVersions() {
	MVKExtensionList allExtns(this, true);
	MVKLogInfo("MoltenVK version %s. Vulkan version %s.\n\tThe following %d Vulkan extensions are supported:%s",
			   mvkGetMoltenVKVersionString(MVK_VERSION).c_str(),
			   mvkGetVulkanVersionString(MVK_VULKAN_API_VERSION).c_str(),
			   allExtns.getEnabledCount(),
			   allExtns.enabledNamesString("\n\t\t", true).c_str());
}

void MVKInstance::initConfig() {
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.debugMode,                              MVK_DEBUG);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.shaderConversionFlipVertexY,            MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.synchronousQueueSubmits,                MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.prefillMetalCommandBuffers,             MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS);
	MVK_SET_FROM_ENV_OR_BUILD_INT32(_mvkConfig.maxActiveMetalCommandBuffersPerQueue,   MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.supportLargeQueryPools,                 MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.presentWithCommandBuffer,               MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.swapchainMagFilterUseNearest,           MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST);
	MVK_SET_FROM_ENV_OR_BUILD_INT64(_mvkConfig.metalCompileTimeout,                    MVK_CONFIG_METAL_COMPILE_TIMEOUT);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.performanceTracking,                    MVK_CONFIG_PERFORMANCE_TRACKING);
	MVK_SET_FROM_ENV_OR_BUILD_INT32(_mvkConfig.performanceLoggingFrameCount,           MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.displayWatermark,                       MVK_CONFIG_DISPLAY_WATERMARK);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.specializedQueueFamilies,               MVK_CONFIG_SPECIALIZED_QUEUE_FAMILIES);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.switchSystemGPU,                        MVK_CONFIG_SWITCH_SYSTEM_GPU);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.fullImageViewSwizzle,                   MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.defaultGPUCaptureScopeQueueFamilyIndex, MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_FAMILY_INDEX);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.defaultGPUCaptureScopeQueueIndex,       MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_INDEX);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL( _mvkConfig.fastMathEnabled,                        MVK_CONFIG_FAST_MATH_ENABLED);

	MVK_SET_FROM_ENV_OR_BUILD_INT32(_autoGPUCaptureScope, MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE);
	MVK_SET_FROM_ENV_OR_BUILD_STRING(_autoGPUCaptureOutputFile, MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE);
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

	lock_guard<mutex> lock(_dcbLock);
	mvkDestroyContainerContents(_debugReportCallbacks);
}

