/*
 * MVKInstance.mm
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


#include "MVKInstance.h"
#include "MVKLayers.h"
#include "MVKDevice.h"
#include "MVKFoundation.h"
#include "MVKEnvironment.h"
#include "MVKSurface.h"

using namespace std;


#pragma mark -
#pragma mark MVKInstance

VkResult MVKInstance::getPhysicalDevices(uint32_t* pCount, VkPhysicalDevice* pPhysicalDevices) {

	// Get the number of physical devices
	uint32_t pdCnt = (uint32_t)_physicalDevices.size();

	// If properties aren't actually being requested yet, simply update the returned count
	if ( !pPhysicalDevices ) {
		*pCount = pdCnt;
		return VK_SUCCESS;
	}

	// Othewise, determine how many physical devices we'll return, and return that count
	VkResult result = (*pCount <= pdCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(pdCnt, *pCount);

	// Now populate the devices
	for (uint32_t pdIdx = 0; pdIdx < *pCount; pdIdx++) {
		pPhysicalDevices[pdIdx] = _physicalDevices[pdIdx]->getVkPhysicalDevice();
	}

	return result;
}

VkResult MVKInstance::verifyLayers(uint32_t count, const char* const* names) {
    VkResult result = VK_SUCCESS;
    for (uint32_t i = 0; i < count; i++) {
        if ( !MVKLayerManager::globalManager()->getLayerNamed(names[i]) ) {
            result = mvkNotifyErrorWithText(VK_ERROR_LAYER_NOT_PRESENT, "Vulkan layer %s is not supported.", names[i]);
        }
    }
    return result;
}

VkResult MVKInstance::verifyExtensions(uint32_t count, const char* const* names) {
    VkResult result = VK_SUCCESS;
    MVKLayer* driverLayer = MVKLayerManager::globalManager()->getDriverLayer();
    for (uint32_t i = 0; i < count; i++) {
        if (!driverLayer->hasExtensionNamed(names[i])) {
            result = mvkNotifyErrorWithText(VK_ERROR_EXTENSION_NOT_PRESENT, "Vulkan extension %s is not supported.", names[i]);
        }
    }
    return result;
}

MVKSurface* MVKInstance::createSurface(const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
									   const VkAllocationCallbacks* pAllocator) {
	return new MVKSurface(this, pCreateInfo, pAllocator);
}

void MVKInstance::destroySurface(MVKSurface* mvkSrfc,
								const VkAllocationCallbacks* pAllocator) {
	mvkSrfc->destroy();
}


#pragma mark Object Creation

#define ADD_PROC_ADDR(entrypoint)	_procAddrMap[""#entrypoint] = (PFN_vkVoidFunction)&entrypoint;

/** Initializes the function pointer map. */
void MVKInstance::initProcAddrs() {

	// Instance functions
	ADD_PROC_ADDR(vkDestroyInstance);
	ADD_PROC_ADDR(vkEnumeratePhysicalDevices);
	ADD_PROC_ADDR(vkGetPhysicalDeviceFeatures);
	ADD_PROC_ADDR(vkGetPhysicalDeviceFormatProperties);
	ADD_PROC_ADDR(vkGetPhysicalDeviceImageFormatProperties);
	ADD_PROC_ADDR(vkGetPhysicalDeviceProperties);
	ADD_PROC_ADDR(vkGetPhysicalDeviceQueueFamilyProperties);
	ADD_PROC_ADDR(vkGetPhysicalDeviceMemoryProperties);
	ADD_PROC_ADDR(vkGetInstanceProcAddr);
	ADD_PROC_ADDR(vkGetDeviceProcAddr);
	ADD_PROC_ADDR(vkCreateDevice);
	ADD_PROC_ADDR(vkEnumerateDeviceExtensionProperties);
	ADD_PROC_ADDR(vkEnumerateDeviceLayerProperties);
	ADD_PROC_ADDR(vkGetPhysicalDeviceSparseImageFormatProperties);

	// Device functions:
	ADD_PROC_ADDR(vkDestroyDevice);
	ADD_PROC_ADDR(vkGetDeviceQueue);
	ADD_PROC_ADDR(vkQueueSubmit);
	ADD_PROC_ADDR(vkQueueWaitIdle);
	ADD_PROC_ADDR(vkDeviceWaitIdle);
	ADD_PROC_ADDR(vkAllocateMemory);
	ADD_PROC_ADDR(vkFreeMemory);
	ADD_PROC_ADDR(vkMapMemory);
	ADD_PROC_ADDR(vkUnmapMemory);
	ADD_PROC_ADDR(vkFlushMappedMemoryRanges);
	ADD_PROC_ADDR(vkInvalidateMappedMemoryRanges);
	ADD_PROC_ADDR(vkGetDeviceMemoryCommitment);
	ADD_PROC_ADDR(vkBindBufferMemory);
	ADD_PROC_ADDR(vkBindImageMemory);
	ADD_PROC_ADDR(vkGetBufferMemoryRequirements);
	ADD_PROC_ADDR(vkGetImageMemoryRequirements);
	ADD_PROC_ADDR(vkGetImageSparseMemoryRequirements);
	ADD_PROC_ADDR(vkQueueBindSparse);
	ADD_PROC_ADDR(vkCreateFence);
	ADD_PROC_ADDR(vkDestroyFence);
	ADD_PROC_ADDR(vkResetFences);
	ADD_PROC_ADDR(vkGetFenceStatus);
	ADD_PROC_ADDR(vkWaitForFences);
	ADD_PROC_ADDR(vkCreateSemaphore);
	ADD_PROC_ADDR(vkDestroySemaphore);
	ADD_PROC_ADDR(vkCreateEvent);
	ADD_PROC_ADDR(vkDestroyEvent);
	ADD_PROC_ADDR(vkGetEventStatus);
	ADD_PROC_ADDR(vkSetEvent);
	ADD_PROC_ADDR(vkResetEvent);
	ADD_PROC_ADDR(vkCreateQueryPool);
	ADD_PROC_ADDR(vkDestroyQueryPool);
	ADD_PROC_ADDR(vkGetQueryPoolResults);
	ADD_PROC_ADDR(vkCreateBuffer);
	ADD_PROC_ADDR(vkDestroyBuffer);
	ADD_PROC_ADDR(vkCreateBufferView);
	ADD_PROC_ADDR(vkDestroyBufferView);
	ADD_PROC_ADDR(vkCreateImage);
	ADD_PROC_ADDR(vkDestroyImage);
	ADD_PROC_ADDR(vkGetImageSubresourceLayout);
	ADD_PROC_ADDR(vkCreateImageView);
	ADD_PROC_ADDR(vkDestroyImageView);
	ADD_PROC_ADDR(vkCreateShaderModule);
	ADD_PROC_ADDR(vkDestroyShaderModule);
	ADD_PROC_ADDR(vkCreatePipelineCache);
	ADD_PROC_ADDR(vkDestroyPipelineCache);
	ADD_PROC_ADDR(vkGetPipelineCacheData);
	ADD_PROC_ADDR(vkMergePipelineCaches);
	ADD_PROC_ADDR(vkCreateGraphicsPipelines);
	ADD_PROC_ADDR(vkCreateComputePipelines);
	ADD_PROC_ADDR(vkDestroyPipeline);
	ADD_PROC_ADDR(vkCreatePipelineLayout);
	ADD_PROC_ADDR(vkDestroyPipelineLayout);
	ADD_PROC_ADDR(vkCreateSampler);
	ADD_PROC_ADDR(vkDestroySampler);
	ADD_PROC_ADDR(vkCreateDescriptorSetLayout);
	ADD_PROC_ADDR(vkDestroyDescriptorSetLayout);
	ADD_PROC_ADDR(vkCreateDescriptorPool);
	ADD_PROC_ADDR(vkDestroyDescriptorPool);
	ADD_PROC_ADDR(vkResetDescriptorPool);
	ADD_PROC_ADDR(vkAllocateDescriptorSets);
	ADD_PROC_ADDR(vkFreeDescriptorSets);
	ADD_PROC_ADDR(vkUpdateDescriptorSets);
	ADD_PROC_ADDR(vkCreateFramebuffer);
	ADD_PROC_ADDR(vkDestroyFramebuffer);
	ADD_PROC_ADDR(vkCreateRenderPass);
	ADD_PROC_ADDR(vkDestroyRenderPass);
	ADD_PROC_ADDR(vkGetRenderAreaGranularity);
	ADD_PROC_ADDR(vkCreateCommandPool);
	ADD_PROC_ADDR(vkDestroyCommandPool);
	ADD_PROC_ADDR(vkResetCommandPool);
	ADD_PROC_ADDR(vkAllocateCommandBuffers);
	ADD_PROC_ADDR(vkFreeCommandBuffers);
	ADD_PROC_ADDR(vkBeginCommandBuffer);
	ADD_PROC_ADDR(vkEndCommandBuffer);
	ADD_PROC_ADDR(vkResetCommandBuffer);
	ADD_PROC_ADDR(vkCmdBindPipeline);
	ADD_PROC_ADDR(vkCmdSetViewport);
	ADD_PROC_ADDR(vkCmdSetScissor);
	ADD_PROC_ADDR(vkCmdSetLineWidth);
	ADD_PROC_ADDR(vkCmdSetDepthBias);
	ADD_PROC_ADDR(vkCmdSetBlendConstants);
	ADD_PROC_ADDR(vkCmdSetDepthBounds);
	ADD_PROC_ADDR(vkCmdSetStencilCompareMask);
	ADD_PROC_ADDR(vkCmdSetStencilWriteMask);
	ADD_PROC_ADDR(vkCmdSetStencilReference);
	ADD_PROC_ADDR(vkCmdBindDescriptorSets);
	ADD_PROC_ADDR(vkCmdBindIndexBuffer);
	ADD_PROC_ADDR(vkCmdBindVertexBuffers);
	ADD_PROC_ADDR(vkCmdDraw);
	ADD_PROC_ADDR(vkCmdDrawIndexed);
	ADD_PROC_ADDR(vkCmdDrawIndirect);
	ADD_PROC_ADDR(vkCmdDrawIndexedIndirect);
	ADD_PROC_ADDR(vkCmdDispatch);
	ADD_PROC_ADDR(vkCmdDispatchIndirect);
	ADD_PROC_ADDR(vkCmdCopyBuffer);
	ADD_PROC_ADDR(vkCmdCopyImage);
	ADD_PROC_ADDR(vkCmdBlitImage);
	ADD_PROC_ADDR(vkCmdCopyBufferToImage);
	ADD_PROC_ADDR(vkCmdCopyImageToBuffer);
	ADD_PROC_ADDR(vkCmdUpdateBuffer);
	ADD_PROC_ADDR(vkCmdFillBuffer);
	ADD_PROC_ADDR(vkCmdClearColorImage);
	ADD_PROC_ADDR(vkCmdClearDepthStencilImage);
	ADD_PROC_ADDR(vkCmdClearAttachments);
	ADD_PROC_ADDR(vkCmdResolveImage);
	ADD_PROC_ADDR(vkCmdSetEvent);
	ADD_PROC_ADDR(vkCmdResetEvent);
	ADD_PROC_ADDR(vkCmdWaitEvents);
	ADD_PROC_ADDR(vkCmdPipelineBarrier);
	ADD_PROC_ADDR(vkCmdBeginQuery);
	ADD_PROC_ADDR(vkCmdEndQuery);
	ADD_PROC_ADDR(vkCmdResetQueryPool);
	ADD_PROC_ADDR(vkCmdWriteTimestamp);
	ADD_PROC_ADDR(vkCmdCopyQueryPoolResults);
	ADD_PROC_ADDR(vkCmdPushConstants);
	ADD_PROC_ADDR(vkCmdBeginRenderPass);
	ADD_PROC_ADDR(vkCmdNextSubpass);
	ADD_PROC_ADDR(vkCmdEndRenderPass);
	ADD_PROC_ADDR(vkCmdExecuteCommands);

	// Supported extensions:
	ADD_PROC_ADDR(vkDestroySurfaceKHR);
	ADD_PROC_ADDR(vkGetPhysicalDeviceSurfaceSupportKHR);
	ADD_PROC_ADDR(vkGetPhysicalDeviceSurfaceCapabilitiesKHR);
	ADD_PROC_ADDR(vkGetPhysicalDeviceSurfaceFormatsKHR);
	ADD_PROC_ADDR(vkGetPhysicalDeviceSurfacePresentModesKHR);
	ADD_PROC_ADDR(vkCreateSwapchainKHR);
	ADD_PROC_ADDR(vkDestroySwapchainKHR);
	ADD_PROC_ADDR(vkGetSwapchainImagesKHR);
	ADD_PROC_ADDR(vkAcquireNextImageKHR);
	ADD_PROC_ADDR(vkQueuePresentKHR);
    ADD_PROC_ADDR(vkGetMoltenVKDeviceConfigurationMVK);
    ADD_PROC_ADDR(vkSetMoltenVKDeviceConfigurationMVK);
    ADD_PROC_ADDR(vkGetPhysicalDeviceMetalFeaturesMVK);
    ADD_PROC_ADDR(vkGetSwapchainPerformanceMVK);
    ADD_PROC_ADDR(vkGetPerformanceStatisticsMVK);
    ADD_PROC_ADDR(vkGetVersionStringsMVK);
    ADD_PROC_ADDR(vkGetMTLDeviceMVK);
    ADD_PROC_ADDR(vkSetMTLTextureMVK);
    ADD_PROC_ADDR(vkGetMTLTextureMVK);
    ADD_PROC_ADDR(vkUseIOSurfaceMVK);
    ADD_PROC_ADDR(vkGetIOSurfaceMVK);

#ifdef VK_USE_PLATFORM_IOS_MVK
	ADD_PROC_ADDR(vkCreateIOSSurfaceMVK);
#endif
#ifdef VK_USE_PLATFORM_MACOS_MVK
	ADD_PROC_ADDR(vkCreateMacOSSurfaceMVK);
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ADD_PROC_ADDR(vkActivateMoltenVKLicenseMVK);    // Deprecated
    ADD_PROC_ADDR(vkActivateMoltenVKLicensesMVK);   // Deprecated
#pragma clang diagnostic pop
}

void MVKInstance::logVersions() {
    uint32_t buffLen = 32;
    char mvkVer[buffLen];
    char vkVer[buffLen];
    vkGetVersionStringsMVK(mvkVer, buffLen, vkVer, buffLen);
    MVKLogInfo("MoltenVK version %s. Vulkan version %s.", mvkVer, vkVer);
}

/**
 * Returns an autoreleased array containing the MTLDevices available on this system,
 * sorted according to power, with higher power GPU's at the front of the array.
 * This ensures that a lazy app that simply grabs the first GPU will get a high-power one by default.
 * If the MVK_FORCE_LOW_POWER_GPU is defined, the returned array will only include low-power devices.
 */
static NSArray<id<MTLDevice>>* getAvailableMTLDevices() {
#if MVK_MACOS
	NSArray* mtlDevs = [MTLCopyAllDevices() autorelease];

#ifdef MVK_FORCE_LOW_POWER_GPU
	NSMutableArray* lpDevs = [[NSMutableArray new] autorelease];
	for (id<MTLDevice> md in mtlDevs) {
		if (md.isLowPower) { [lpDevs addObject: md]; }
	}
	return lpDevs;
#else
	return [mtlDevs sortedArrayUsingComparator: ^(id<MTLDevice> md1, id<MTLDevice> md2) {
		BOOL md1IsLP = md1.isLowPower;
		BOOL md2IsLP = md2.isLowPower;

		if (md1IsLP == md2IsLP) { return NSOrderedSame; }

		return md2IsLP ? NSOrderedAscending : NSOrderedDescending;
	}];
#endif	// MVK_MACOS

#endif
#if MVK_IOS
	return [NSArray arrayWithObject: MTLCreateSystemDefaultDevice()];
#endif
}

MVKInstance::MVKInstance(const VkInstanceCreateInfo* pCreateInfo) {

	_appInfo.apiVersion = MVK_VULKAN_API_VERSION;	// Default
	mvkSetOrClear(&_appInfo, pCreateInfo->pApplicationInfo);

    logVersions();          // Log the MoltenVK and Vulkan versions
	initProcAddrs();		// Init function pointers

	// Populate the array of physical GPU devices
	NSArray<id<MTLDevice>>* mtlDevices = getAvailableMTLDevices();
	_physicalDevices.reserve(mtlDevices.count);
	for (id<MTLDevice> mtlDev in mtlDevices) {
		_physicalDevices.push_back(new MVKPhysicalDevice(this, mtlDev));
	}

	if (MVK_VULKAN_API_VERSION_CONFORM(MVK_VULKAN_API_VERSION) <
		MVK_VULKAN_API_VERSION_CONFORM(_appInfo.apiVersion)) {
        setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INCOMPATIBLE_DRIVER, "Request for driver version %x is not compatible with provided version %x.", _appInfo.apiVersion, MVK_VULKAN_API_VERSION));
	}

    setConfigurationResult(verifyLayers(pCreateInfo->enabledLayerCount, pCreateInfo->ppEnabledLayerNames));
    setConfigurationResult(verifyExtensions(pCreateInfo->enabledExtensionCount, pCreateInfo->ppEnabledExtensionNames));
}

MVKInstance::~MVKInstance() {
	mvkDestroyContainerContents(_physicalDevices);
}

