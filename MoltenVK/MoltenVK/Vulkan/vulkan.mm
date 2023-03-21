/*
 * vulkan.mm
 *
 * Copyright (c) 2015-2023 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#include "MVKLayers.h"
#include "MVKInstance.h"
#include "MVKDevice.h"
#include "MVKCommandPool.h"
#include "MVKCommandBuffer.h"
#include "MVKCmdPipeline.h"
#include "MVKCmdDraw.h"
#include "MVKCmdTransfer.h"
#include "MVKCmdQueries.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKDeviceMemory.h"
#include "MVKDescriptorSet.h"
#include "MVKRenderpass.h"
#include "MVKShaderModule.h"
#include "MVKPipeline.h"
#include "MVKFramebuffer.h"
#include "MVKSync.h"
#include "MVKQueue.h"
#include "MVKQueryPool.h"
#include "MVKSwapchain.h"
#include "MVKSurface.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"

#include <pthread.h>


#pragma mark -
#pragma mark Vulkan call templates

// Optionally log start of function calls to stderr
static inline uint64_t MVKTraceVulkanCallStartImpl(const char* funcName) {

	bool includeThread = false;
	bool includeExit = false;
	bool includeDuration = false;

	switch (mvkConfig().traceVulkanCalls) {
		case MVK_CONFIG_TRACE_VULKAN_CALLS_DURATION:
			includeDuration = true;		// fallthrough
		case MVK_CONFIG_TRACE_VULKAN_CALLS_ENTER_EXIT:
			includeExit = true;			// fallthrough
		case MVK_CONFIG_TRACE_VULKAN_CALLS_ENTER:
			break;

		case MVK_CONFIG_TRACE_VULKAN_CALLS_DURATION_THREAD_ID:
			includeDuration = true;		// fallthrough
		case MVK_CONFIG_TRACE_VULKAN_CALLS_ENTER_EXIT_THREAD_ID:
			includeExit = true;			// fallthrough
		case MVK_CONFIG_TRACE_VULKAN_CALLS_ENTER_THREAD_ID:
			includeThread = true;		// fallthrough
			break;

		case MVK_CONFIG_TRACE_VULKAN_CALLS_NONE:
		default:
			return 0;
	}

	if (includeThread) {
		uint64_t gtid, mtid;
		const uint32_t kThreadNameBuffSize = 256;
		char threadName[kThreadNameBuffSize];
		pthread_t tid = pthread_self();
		mtid = pthread_mach_thread_np(tid);		// Mach thread ID
		pthread_threadid_np(tid, &gtid);		// Global system-wide thead ID
		pthread_getname_np(tid, threadName, kThreadNameBuffSize);
		fprintf(stderr, "[mvk-trace] %s()%s [%llu/%llu/%s]\n", funcName, includeExit ? " {" : "", mtid, gtid, threadName);
	} else {
		fprintf(stderr, "[mvk-trace] %s()%s\n", funcName, includeExit ? " {" : "");
	}

	return includeDuration ? mvkGetTimestamp() : 0;
}

// Optionally log end of function calls and timings to stderr
static inline void MVKTraceVulkanCallEndImpl(const char* funcName, uint64_t startTime) {
	switch(mvkConfig().traceVulkanCalls) {
		case MVK_CONFIG_TRACE_VULKAN_CALLS_ENTER_EXIT:
		case MVK_CONFIG_TRACE_VULKAN_CALLS_ENTER_EXIT_THREAD_ID:
			fprintf(stderr, "[mvk-trace] } %s\n", funcName);
			break;
		case MVK_CONFIG_TRACE_VULKAN_CALLS_DURATION:
		case MVK_CONFIG_TRACE_VULKAN_CALLS_DURATION_THREAD_ID:
			fprintf(stderr, "[mvk-trace] } %s [%.4f ms]\n", funcName, mvkGetElapsedMilliseconds(startTime));
			break;
		default:
			break;
	}
}

#define MVKTraceVulkanCallStart()	uint64_t tvcStartTime = MVKTraceVulkanCallStartImpl(__FUNCTION__)
#define MVKTraceVulkanCallEnd()		MVKTraceVulkanCallEndImpl(__FUNCTION__, tvcStartTime)

// Create and configure a command of particular type.
// If the command is configured correctly, add it to the buffer,
// otherwise indicate the configuration error to the command buffer.
#define MVKAddCmd(cmdType, vkCmdBuff, ...)  													\
	MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(vkCmdBuff);				\
	MVKCmd ##cmdType* cmd = cmdBuff->getCommandPool()->_cmd ##cmdType ##Pool.acquireObject();	\
	VkResult cmdRslt = cmd->setContent(cmdBuff, ##__VA_ARGS__);									\
	if (cmdRslt == VK_SUCCESS) {																\
		cmdBuff->addCommand(cmd);																\
	} else {																					\
		cmdBuff->setConfigurationResult(cmdRslt);												\
	}

// Add one of two commands, based on comparing a command parameter against a threshold value
#define MVKAddCmdFromThreshold(baseCmdType, value, threshold, vkCmdBuff, ...)					\
	if (value <= threshold) {																	\
		MVKAddCmd(baseCmdType ##threshold, vkCmdBuff, ##__VA_ARGS__);							\
	} else {																					\
		MVKAddCmd(baseCmdType ##Multi, vkCmdBuff, ##__VA_ARGS__);								\
	}

// Add one of three commands, based on comparing a command parameter against two threshold values
#define MVKAddCmdFrom2Thresholds(baseCmdType, value, threshold1, threshold2, vkCmdBuff, ...)	\
	if (value <= threshold1) {																	\
		MVKAddCmd(baseCmdType ##threshold1, vkCmdBuff, ##__VA_ARGS__);							\
	} else if (value <= threshold2) {															\
		MVKAddCmd(baseCmdType ##threshold2, vkCmdBuff, ##__VA_ARGS__);							\
	} else {																					\
		MVKAddCmd(baseCmdType ##Multi, vkCmdBuff, ##__VA_ARGS__);								\
	}


// Add one of four commands, based on comparing a command parameter against two threshold values
#define MVKAddCmdFrom3Thresholds(baseCmdType, value, threshold1, threshold2, threshold3, vkCmdBuff, ...)	\
	if (value <= threshold1) {																				\
		MVKAddCmd(baseCmdType ##threshold1, vkCmdBuff, ##__VA_ARGS__);										\
	} else if (value <= threshold2) {																		\
		MVKAddCmd(baseCmdType ##threshold2, vkCmdBuff, ##__VA_ARGS__);										\
	} else if (value <= threshold3) {																		\
		MVKAddCmd(baseCmdType ##threshold3, vkCmdBuff, ##__VA_ARGS__);										\
	} else {																								\
		MVKAddCmd(baseCmdType ##Multi, vkCmdBuff, ##__VA_ARGS__);											\
	}

// Add one of nine commands, based on comparing a command parameter against four threshold values
#define MVKAddCmdFrom5Thresholds(baseCmdType, value1, arg1Threshold1, arg1Threshold2,			\
								 value2, arg2Threshold1, arg2Threshold2, arg2Threshold3,		\
								 vkCmdBuff, ...)												\
	if (value1 <= arg1Threshold1 && value2 <= arg2Threshold1) {									\
		MVKAddCmd(baseCmdType ##arg1Threshold1 ##arg2Threshold1, vkCmdBuff, ##__VA_ARGS__);		\
	} else if (value1 <= arg1Threshold2 && value2 <= arg2Threshold1) {							\
		MVKAddCmd(baseCmdType ##arg1Threshold1 ##arg2Threshold1, vkCmdBuff, ##__VA_ARGS__);		\
	} else if (value1 > arg1Threshold2 && value2 <= arg2Threshold1) {							\
		MVKAddCmd(baseCmdType ##Multi ##arg2Threshold1, vkCmdBuff, ##__VA_ARGS__);				\
	} else if (value1 <= arg1Threshold1 && value2 <= arg2Threshold2) {							\
		MVKAddCmd(baseCmdType ##arg1Threshold1 ##arg2Threshold2, vkCmdBuff, ##__VA_ARGS__);		\
	} else if (value1 <= arg1Threshold2 && value2 <= arg2Threshold2) {							\
		MVKAddCmd(baseCmdType ##arg1Threshold2 ##arg2Threshold2, vkCmdBuff, ##__VA_ARGS__);		\
	} else if (value1 > arg1Threshold2 && value2 <= arg2Threshold2) {							\
		MVKAddCmd(baseCmdType ##Multi ##arg2Threshold2, vkCmdBuff, ##__VA_ARGS__);				\
	} else if (value1 <= arg1Threshold1 && value2 <= arg2Threshold3) {							\
		MVKAddCmd(baseCmdType ##arg1Threshold1 ##arg2Threshold3, vkCmdBuff, ##__VA_ARGS__);		\
	} else if (value1 <= arg1Threshold2 && value2 <= arg2Threshold3) {							\
		MVKAddCmd(baseCmdType ##arg1Threshold2 ##arg2Threshold3, vkCmdBuff, ##__VA_ARGS__);		\
	} else if (value1 > arg1Threshold2 && value2 <= arg2Threshold3) {							\
		MVKAddCmd(baseCmdType ##Multi ##arg2Threshold3, vkCmdBuff, ##__VA_ARGS__);				\
	} else if (value1 <= arg1Threshold1 && value2 > arg2Threshold3) {							\
		MVKAddCmd(baseCmdType ##arg1Threshold1 ##Multi, vkCmdBuff, ##__VA_ARGS__);				\
	} else if (value1 <= arg1Threshold2 && value2 > arg2Threshold3) {							\
		MVKAddCmd(baseCmdType ##arg1Threshold2 ##Multi, vkCmdBuff, ##__VA_ARGS__);				\
	} else {																					\
		MVKAddCmd(baseCmdType ##Multi ##Multi, vkCmdBuff, ##__VA_ARGS__);						\
	}

// Define an extension call as an alias of a core call
#define MVK_PUBLIC_VULKAN_CORE_ALIAS(vkf, ext)	MVK_PUBLIC_VULKAN_ALIAS(vkf##ext, vkf)

#define MVK_PUBLIC_VULKAN_STUB(name, ret, ...) MVK_PUBLIC_VULKAN_SYMBOL ret name(__VA_ARGS__) { \
	assert(false); \
	return (ret)0; \
}

#define MVK_PUBLIC_VULKAN_STUB_VKRESULT(name, ...) MVK_PUBLIC_VULKAN_SYMBOL VkResult name(__VA_ARGS__) { \
	assert(false); \
	return VK_ERROR_FEATURE_NOT_PRESENT; \
}

#pragma mark -
#pragma mark Vulkan 1.0 calls

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateInstance(
    const VkInstanceCreateInfo*                 pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkInstance*                                 pInstance) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = new MVKInstance(pCreateInfo);
	*pInstance = mvkInst->getVkInstance();
	VkResult rslt = mvkInst->getConfigurationResult();
	if (rslt < 0) { *pInstance = nullptr; mvkInst->destroy(); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyInstance(
    VkInstance                                  instance,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	if (instance) { MVKInstance::getMVKInstance(instance)->destroy(); }
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkEnumeratePhysicalDevices(
    VkInstance                                  instance,
    uint32_t*                                   pPhysicalDeviceCount,
    VkPhysicalDevice*                           pPhysicalDevices) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	VkResult rslt = mvkInst->getPhysicalDevices(pPhysicalDeviceCount, pPhysicalDevices);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceFeatures(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceFeatures*                   pFeatures) {
	
	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getFeatures(pFeatures);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceFormatProperties(
    VkPhysicalDevice                            physicalDevice,
    VkFormat                                    format,
    VkFormatProperties*                         pFormatProperties) {
	
	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getFormatProperties(format, pFormatProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDeviceImageFormatProperties(
    VkPhysicalDevice                            physicalDevice,
    VkFormat                                    format,
    VkImageType                                 type,
    VkImageTiling                               tiling,
    VkImageUsageFlags                           usage,
    VkImageCreateFlags                          flags,
    VkImageFormatProperties*                    pImageFormatProperties) {
	
	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    VkResult rslt = mvkPD->getImageFormatProperties(format, type, tiling, usage, flags, pImageFormatProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceProperties(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceProperties*                 pProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getProperties(pProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceQueueFamilyProperties(
	VkPhysicalDevice                            physicalDevice,
	uint32_t*                                   pQueueFamilyPropertyCount,
	VkQueueFamilyProperties*                    pQueueFamilyProperties) {
	
	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getQueueFamilyProperties(pQueueFamilyPropertyCount, pQueueFamilyProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceMemoryProperties(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceMemoryProperties*           pMemoryProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getMemoryProperties(pMemoryProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL PFN_vkVoidFunction vkGetInstanceProcAddr(
    VkInstance                                  instance,
    const char*                                 pName) {

	// Handle the special platform functions where the instance parameter may be NULL.
	PFN_vkVoidFunction func = nullptr;
	MVKTraceVulkanCallStart();
	if (mvkStringsAreEqual(pName, "vkGetInstanceProcAddr")) {
		func = (PFN_vkVoidFunction)vkGetInstanceProcAddr;
	} else if (mvkStringsAreEqual(pName, "vkCreateInstance")) {
		func = (PFN_vkVoidFunction)vkCreateInstance;
	} else if (mvkStringsAreEqual(pName, "vkEnumerateInstanceExtensionProperties")) {
		func = (PFN_vkVoidFunction)vkEnumerateInstanceExtensionProperties;
	} else if (mvkStringsAreEqual(pName, "vkEnumerateInstanceLayerProperties")) {
		func = (PFN_vkVoidFunction)vkEnumerateInstanceLayerProperties;
	} else if (mvkStringsAreEqual(pName, "vkEnumerateInstanceVersion")) {
		func = (PFN_vkVoidFunction)vkEnumerateInstanceVersion;
	} else if (instance) {
		MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
		func = mvkInst->getProcAddr(pName);
	}
	MVKTraceVulkanCallEnd();
	return func;
}

MVK_PUBLIC_VULKAN_SYMBOL PFN_vkVoidFunction vkGetDeviceProcAddr(
    VkDevice                                    device,
    const char*                                 pName) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	PFN_vkVoidFunction func = mvkDev->getProcAddr(pName);
	MVKTraceVulkanCallEnd();
	return func;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateDevice(
    VkPhysicalDevice                            physicalDevice,
    const VkDeviceCreateInfo*                   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkDevice*                                   pDevice) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	MVKDevice* mvkDev = new MVKDevice(mvkPD, pCreateInfo);
	*pDevice = mvkDev->getVkDevice();
	VkResult rslt = mvkDev->getConfigurationResult();
	if (rslt < 0) { *pDevice = nullptr; mvkDev->destroy(); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyDevice(
	VkDevice                                    device,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	if (device) { MVKDevice::getMVKDevice(device)->destroy(); }
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkEnumerateInstanceExtensionProperties(
    const char*                                 pLayerName,
    uint32_t*                                   pCount,
    VkExtensionProperties*                      pProperties) {

	MVKTraceVulkanCallStart();
	VkResult rslt = MVKLayerManager::globalManager()->getLayerNamed(pLayerName)->getInstanceExtensionProperties(pCount, pProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkEnumerateDeviceExtensionProperties(
    VkPhysicalDevice                            physicalDevice,
    const char*                                 pLayerName,
    uint32_t*                                   pCount,
    VkExtensionProperties*                      pProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	VkResult rslt = mvkPD->getExtensionProperties(pLayerName, pCount, pProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkEnumerateInstanceLayerProperties(
    uint32_t*                                   pCount,
    VkLayerProperties*                          pProperties) {

	MVKTraceVulkanCallStart();
	VkResult rslt = MVKLayerManager::globalManager()->getLayerProperties(pCount, pProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkEnumerateDeviceLayerProperties(
    VkPhysicalDevice                            physicalDevice,
    uint32_t*                                   pCount,
    VkLayerProperties*                          pProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	VkResult rslt = mvkPD->getInstance()->getLayerManager()->getLayerProperties(pCount, pProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetDeviceQueue(
    VkDevice                                    device,
    uint32_t                                    queueFamilyIndex,
    uint32_t                                    queueIndex,
    VkQueue*                                    pQueue) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	*pQueue = mvkDev->getQueue(queueFamilyIndex, queueIndex)->getVkQueue();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkQueueSubmit(
	VkQueue                                     queue,
	uint32_t                                    submitCount,
	const VkSubmitInfo*                         pSubmits,
	VkFence                                     fence) {

	MVKTraceVulkanCallStart();
	MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
	VkResult rslt = mvkQ->submit(submitCount, pSubmits, fence, kMVKCommandUseQueueSubmit);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkQueueWaitIdle(
    VkQueue                                     queue) {
	
	MVKTraceVulkanCallStart();
	MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
	VkResult rslt = mvkQ->waitIdle(kMVKCommandUseQueueWaitIdle);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkDeviceWaitIdle(
    VkDevice                                    device) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkDev->waitIdle();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkAllocateMemory(
    VkDevice                                    device,
    const VkMemoryAllocateInfo*                 pAllocateInfo,
    const VkAllocationCallbacks*                pAllocator,
    VkDeviceMemory*                             pMem) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKDeviceMemory* mvkMem = mvkDev->allocateMemory(pAllocateInfo, pAllocator);
	VkResult rslt = mvkMem->getConfigurationResult();
	*pMem = (VkDeviceMemory)((rslt == VK_SUCCESS) ? mvkMem : VK_NULL_HANDLE);
    if (rslt != VK_SUCCESS) { mvkDev->freeMemory(mvkMem, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkFreeMemory(
    VkDevice                                    device,
	VkDeviceMemory                              mem,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->freeMemory((MVKDeviceMemory*)mem, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkMapMemory(
   VkDevice                                    device,
   VkDeviceMemory                              mem,
   VkDeviceSize                                offset,
   VkDeviceSize                                size,
   VkMemoryMapFlags                            flags,
   void**                                      ppData) {

	MVKTraceVulkanCallStart();
	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	VkResult rslt = mvkMem->map(offset, size, flags, ppData);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkUnmapMemory(
    VkDevice                                    device,
    VkDeviceMemory                              mem) {
	
	MVKTraceVulkanCallStart();
	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	mvkMem->unmap();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkFlushMappedMemoryRanges(
    VkDevice                                    device,
    uint32_t                                    memRangeCount,
    const VkMappedMemoryRange*                  pMemRanges) {

	MVKTraceVulkanCallStart();
	VkResult rslt = VK_SUCCESS;
	for (uint32_t i = 0; i < memRangeCount; i++) {
		const VkMappedMemoryRange* pMem = &pMemRanges[i];
		MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)pMem->memory;
		VkResult r = mvkMem->flushToDevice(pMem->offset, pMem->size);
		if (rslt == VK_SUCCESS) { rslt = r; }
	}
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkInvalidateMappedMemoryRanges(
    VkDevice                                    device,
    uint32_t                                    memRangeCount,
    const VkMappedMemoryRange*                  pMemRanges) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkDev->invalidateMappedMemoryRanges(memRangeCount, pMemRanges);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetDeviceMemoryCommitment(
    VkDevice                                    device,
    VkDeviceMemory                              memory,
    VkDeviceSize*                               pCommittedMemoryInBytes) {

	MVKTraceVulkanCallStart();
    MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)memory;
    *pCommittedMemoryInBytes = mvkMem->getDeviceMemoryCommitment();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkBindBufferMemory(
    VkDevice                                    device,
    VkBuffer                                    buffer,
    VkDeviceMemory                              mem,
    VkDeviceSize                                memOffset) {
	
	MVKTraceVulkanCallStart();
	MVKBuffer* mvkBuff = (MVKBuffer*)buffer;
	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	VkResult rslt = mvkBuff->bindDeviceMemory(mvkMem, memOffset);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkBindImageMemory(
    VkDevice                                    device,
    VkImage                                     image,
    VkDeviceMemory                              mem,
    VkDeviceSize                                memOffset) {
	
	MVKTraceVulkanCallStart();
	MVKImage* mvkImg = (MVKImage*)image;
	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	VkResult rslt = mvkImg->bindDeviceMemory(mvkMem, memOffset, 0);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetBufferMemoryRequirements(
    VkDevice                                    device,
    VkBuffer                                    buffer,
    VkMemoryRequirements*                       pMemoryRequirements) {
	
	MVKTraceVulkanCallStart();
	MVKBuffer* mvkBuff = (MVKBuffer*)buffer;
	mvkBuff->getMemoryRequirements(pMemoryRequirements);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetImageMemoryRequirements(
    VkDevice                                    device,
    VkImage                                     image,
    VkMemoryRequirements*                       pMemoryRequirements) {
	
	MVKTraceVulkanCallStart();
	MVKImage* mvkImg = (MVKImage*)image;
	mvkImg->getMemoryRequirements(pMemoryRequirements, 0);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetImageSparseMemoryRequirements(
    VkDevice                                    device,
    VkImage                                     image,
    uint32_t*                                   pNumRequirements,
    VkSparseImageMemoryRequirements*            pSparseMemoryRequirements) {

	MVKTraceVulkanCallStart();

	// Metal does not support sparse images.
	// Vulkan spec: "If the image was not created with VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT then
	// pSparseMemoryRequirementCount will be set to zero and pSparseMemoryRequirements will not be written to.".

	*pNumRequirements = 0;
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceSparseImageFormatProperties(
	VkPhysicalDevice                            physicalDevice,
	VkFormat                                    format,
	VkImageType                                 type,
	VkSampleCountFlagBits                       samples,
	VkImageUsageFlags                           usage,
	VkImageTiling                               tiling,
	uint32_t*                                   pPropertyCount,
	VkSparseImageFormatProperties*              pProperties) {

	MVKTraceVulkanCallStart();

	// Metal does not support sparse images.
	// Vulkan spec: "If VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT is not supported for the given arguments,
	// pPropertyCount will be set to zero upon return, and no data will be written to pProperties.".

	*pPropertyCount = 0;
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkQueueBindSparse(
	VkQueue                                     queue,
	uint32_t                                    bindInfoCount,
	const VkBindSparseInfo*                     pBindInfo,
	VkFence                                     fence) {

	MVKTraceVulkanCallStart();
	MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
	VkResult rslt = mvkQ->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkQueueBindSparse(): Sparse binding is not supported.");
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateFence(
    VkDevice                                    device,
    const VkFenceCreateInfo*                    pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkFence*                                    pFence) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKFence* mvkFence = mvkDev->createFence(pCreateInfo, pAllocator);
	*pFence = (VkFence)mvkFence;
	VkResult rslt = mvkFence->getConfigurationResult();
	if (rslt < 0) { *pFence = VK_NULL_HANDLE; mvkDev->destroyFence(mvkFence, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyFence(
    VkDevice                                    device,
	VkFence                                     fence,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyFence((MVKFence*)fence, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkResetFences(
    VkDevice                                    device,
    uint32_t                                    fenceCount,
    const VkFence*                              pFences) {
	
	MVKTraceVulkanCallStart();
	VkResult rslt = mvkResetFences(fenceCount, pFences);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetFenceStatus(
    VkDevice                                    device,
    VkFence                                     fence) {
	
	MVKTraceVulkanCallStart();
	VkResult rslt = MVKDevice::getMVKDevice(device)->getConfigurationResult();
	if (rslt == VK_SUCCESS) {
		MVKFence* mvkFence = (MVKFence*)fence;
		rslt = mvkFence->getIsSignaled() ? VK_SUCCESS : VK_NOT_READY;
	}
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkWaitForFences(
    VkDevice                                    device,
    uint32_t                                    fenceCount,
    const VkFence*                              pFences,
    VkBool32                                    waitAll,
    uint64_t                                    timeout) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkWaitForFences(mvkDev, fenceCount, pFences, waitAll, timeout);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateSemaphore(
    VkDevice                                    device,
    const VkSemaphoreCreateInfo*                pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkSemaphore*                                pSemaphore) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKSemaphore* mvkSem4 = mvkDev->createSemaphore(pCreateInfo, pAllocator);
	*pSemaphore = (VkSemaphore)mvkSem4;
	VkResult rslt = mvkSem4->getConfigurationResult();
	if (rslt < 0) { *pSemaphore = VK_NULL_HANDLE; mvkDev->destroySemaphore(mvkSem4, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroySemaphore(
    VkDevice                                    device,
	VkSemaphore                                 semaphore,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroySemaphore((MVKSemaphore*)semaphore, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateEvent(
    VkDevice                                    device,
    const VkEventCreateInfo*                    pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkEvent*                                    pEvent) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKEvent* mvkEvent = mvkDev->createEvent(pCreateInfo, pAllocator);
	*pEvent = (VkEvent)mvkEvent;
	VkResult rslt = mvkEvent->getConfigurationResult();
	if (rslt < 0) { *pEvent = VK_NULL_HANDLE; mvkDev->destroyEvent(mvkEvent, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyEvent(
    VkDevice                                    device,
	VkEvent                                     event,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyEvent((MVKEvent*)event, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetEventStatus(
    VkDevice                                    device,
    VkEvent                                     event) {
	
	MVKTraceVulkanCallStart();
	VkResult rslt = MVKDevice::getMVKDevice(device)->getConfigurationResult();
	if (rslt == VK_SUCCESS) {
		MVKEvent* mvkEvent = (MVKEvent*)event;
		rslt = mvkEvent->isSet() ? VK_EVENT_SET : VK_EVENT_RESET;
	}
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkSetEvent(
    VkDevice                                    device,
    VkEvent                                     event) {
	
	MVKTraceVulkanCallStart();
	MVKEvent* mvkEvent = (MVKEvent*)event;
	mvkEvent->signal(true);
	MVKTraceVulkanCallEnd();
	return VK_SUCCESS;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkResetEvent(
    VkDevice                                    device,
    VkEvent                                     event) {
	
	MVKTraceVulkanCallStart();
	MVKEvent* mvkEvent = (MVKEvent*)event;
	mvkEvent->signal(false);
	MVKTraceVulkanCallEnd();
	return VK_SUCCESS;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateQueryPool(
    VkDevice                                    device,
    const VkQueryPoolCreateInfo*                pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkQueryPool*                                pQueryPool) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKQueryPool* mvkQP = mvkDev->createQueryPool(pCreateInfo, pAllocator);
	*pQueryPool = (VkQueryPool)mvkQP;
	VkResult rslt = mvkQP->getConfigurationResult();
	if (rslt < 0) { *pQueryPool = VK_NULL_HANDLE; mvkDev->destroyQueryPool(mvkQP, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyQueryPool(
    VkDevice                                    device,
	VkQueryPool                                 queryPool,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyQueryPool((MVKQueryPool*)queryPool, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetQueryPoolResults(
	VkDevice                                    device,
	VkQueryPool                                 queryPool,
	uint32_t                                    firstQuery,
	uint32_t                                    queryCount,
	size_t                                      dataSize,
	void*                                       pData,
	VkDeviceSize                                stride,
	VkQueryResultFlags                          flags) {

	MVKTraceVulkanCallStart();
	MVKQueryPool* mvkQP = (MVKQueryPool*)queryPool;
	VkResult rslt = mvkQP->getResults(firstQuery, queryCount, dataSize, pData, stride, flags);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateBuffer(
    VkDevice                                    device,
    const VkBufferCreateInfo*                   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkBuffer*                                   pBuffer) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKBuffer* mvkBuff = mvkDev->createBuffer(pCreateInfo, pAllocator);
	*pBuffer = (VkBuffer)mvkBuff;
	VkResult rslt = mvkBuff->getConfigurationResult();
	if (rslt < 0) { *pBuffer = VK_NULL_HANDLE; mvkDev->destroyBuffer(mvkBuff, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyBuffer(
    VkDevice                                    device,
	VkBuffer                                    buffer,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyBuffer((MVKBuffer*)buffer, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateBufferView(
    VkDevice                                    device,
    const VkBufferViewCreateInfo*               pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkBufferView*                               pView) {
	
	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    MVKBufferView* mvkBuffView = mvkDev->createBufferView(pCreateInfo, pAllocator);
    *pView = (VkBufferView)mvkBuffView;
    VkResult rslt = mvkBuffView->getConfigurationResult();
	if (rslt < 0) { *pView = VK_NULL_HANDLE; mvkDev->destroyBufferView(mvkBuffView, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyBufferView(
    VkDevice                                    device,
	VkBufferView                                bufferView,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroyBufferView((MVKBufferView*)bufferView, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateImage(
    VkDevice                                    device,
    const VkImageCreateInfo*                    pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkImage*                                    pImage) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKImage* mvkImg = mvkDev->createImage(pCreateInfo, pAllocator);
	*pImage = (VkImage)mvkImg;
	VkResult rslt = mvkImg->getConfigurationResult();
	if (rslt < 0) { *pImage = VK_NULL_HANDLE; mvkDev->destroyImage(mvkImg, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyImage(
    VkDevice                                    device,
	VkImage                                     image,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyImage((MVKImage*)image, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetImageSubresourceLayout(
    VkDevice                                    device,
    VkImage                                     image,
    const VkImageSubresource*                   pSubresource,
    VkSubresourceLayout*                        pLayout) {

	MVKTraceVulkanCallStart();
	MVKImage* mvkImg = (MVKImage*)image;
	mvkImg->getSubresourceLayout(pSubresource, pLayout);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateImageView(
    VkDevice                                    device,
    const VkImageViewCreateInfo*                pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkImageView*                                pView) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKImageView* mvkImgView = mvkDev->createImageView(pCreateInfo, pAllocator);
	*pView = (VkImageView)mvkImgView;
	VkResult rslt = mvkImgView->getConfigurationResult();
	if (rslt < 0) { *pView = VK_NULL_HANDLE; mvkDev->destroyImageView(mvkImgView, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyImageView(
    VkDevice                                    device,
	VkImageView                                 imageView,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyImageView((MVKImageView*)imageView, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateShaderModule(
    VkDevice                                    device,
    const VkShaderModuleCreateInfo*             pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkShaderModule*                             pShaderModule) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKShaderModule* mvkShdrMod = mvkDev->createShaderModule(pCreateInfo, pAllocator);
	*pShaderModule = (VkShaderModule)mvkShdrMod;
	VkResult rslt = mvkShdrMod->getConfigurationResult();
	if (rslt < 0) { *pShaderModule = VK_NULL_HANDLE; mvkDev->destroyShaderModule(mvkShdrMod, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyShaderModule(
    VkDevice                                    device,
	VkShaderModule                              shaderModule,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyShaderModule((MVKShaderModule*)shaderModule, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreatePipelineCache(
    VkDevice                                    device,
    const VkPipelineCacheCreateInfo*            pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkPipelineCache*                            pPipelineCache) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKPipelineCache* mvkPLC = mvkDev->createPipelineCache(pCreateInfo, pAllocator);
	*pPipelineCache = (VkPipelineCache)mvkPLC;
	VkResult rslt = mvkPLC->getConfigurationResult();
	if (rslt < 0) { *pPipelineCache = VK_NULL_HANDLE; mvkDev->destroyPipelineCache(mvkPLC, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyPipelineCache(
    VkDevice                                    device,
	VkPipelineCache                             pipelineCache,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyPipelineCache((MVKPipelineCache*)pipelineCache, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPipelineCacheData(
	VkDevice                                    device,
	VkPipelineCache                             pipelineCache,
	size_t*                                     pDataSize,
	void*                                       pData) {

	MVKTraceVulkanCallStart();
	MVKPipelineCache* mvkPLC = (MVKPipelineCache*)pipelineCache;
	VkResult rslt = mvkPLC->writeData(pDataSize, pData);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkMergePipelineCaches(
    VkDevice                                    device,
    VkPipelineCache                             destCache,
    uint32_t                                    srcCacheCount,
    const VkPipelineCache*                      pSrcCaches) {
	
	MVKTraceVulkanCallStart();
	MVKPipelineCache* mvkPLC = (MVKPipelineCache*)destCache;
	VkResult rslt = mvkPLC->mergePipelineCaches(srcCacheCount, pSrcCaches);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateGraphicsPipelines(
    VkDevice                                    device,
    VkPipelineCache                             pipelineCache,
    uint32_t                                    count,
    const VkGraphicsPipelineCreateInfo*         pCreateInfos,
	const VkAllocationCallbacks*                pAllocator,
    VkPipeline*                                 pPipelines) {
	
	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkDev->createPipelines<MVKGraphicsPipeline, VkGraphicsPipelineCreateInfo>(pipelineCache, count, pCreateInfos, pAllocator, pPipelines);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateComputePipelines(
    VkDevice                                    device,
    VkPipelineCache                             pipelineCache,
    uint32_t                                    count,
    const VkComputePipelineCreateInfo*          pCreateInfos,
	const VkAllocationCallbacks*                pAllocator,
    VkPipeline*                                 pPipelines) {
	
	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    VkResult rslt = mvkDev->createPipelines<MVKComputePipeline, VkComputePipelineCreateInfo>(pipelineCache, count, pCreateInfos, pAllocator, pPipelines);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyPipeline(
    VkDevice                                    device,
	VkPipeline                                  pipeline,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroyPipeline((MVKPipeline*)pipeline, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreatePipelineLayout(
    VkDevice                                    device,
    const VkPipelineLayoutCreateInfo*           pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkPipelineLayout*                           pPipelineLayout) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKPipelineLayout* mvkPLL = mvkDev->createPipelineLayout(pCreateInfo, pAllocator);
	*pPipelineLayout = (VkPipelineLayout)mvkPLL;
	VkResult rslt = mvkPLL->getConfigurationResult();
	if (rslt < 0) { *pPipelineLayout = VK_NULL_HANDLE; mvkDev->destroyPipelineLayout(mvkPLL, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyPipelineLayout(
    VkDevice                                    device,
	VkPipelineLayout                            pipelineLayout,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyPipelineLayout((MVKPipelineLayout*)pipelineLayout, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateSampler(
    VkDevice                                    device,
    const VkSamplerCreateInfo*                  pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkSampler*                                  pSampler) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKSampler* mvkSamp = mvkDev->createSampler(pCreateInfo, pAllocator);
	*pSampler = (VkSampler)mvkSamp;
	VkResult rslt = mvkSamp->getConfigurationResult();
	if (rslt < 0) { *pSampler = VK_NULL_HANDLE; mvkDev->destroySampler(mvkSamp, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroySampler(
    VkDevice                                    device,
	VkSampler                                   sampler,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroySampler((MVKSampler*)sampler, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateDescriptorSetLayout(
    VkDevice                                    device,
    const VkDescriptorSetLayoutCreateInfo*      pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkDescriptorSetLayout*                      pSetLayout) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKDescriptorSetLayout* mvkDSL = mvkDev->createDescriptorSetLayout(pCreateInfo, pAllocator);
	*pSetLayout = (VkDescriptorSetLayout)mvkDSL;
	VkResult rslt = mvkDSL->getConfigurationResult();
	if (rslt < 0) { *pSetLayout = VK_NULL_HANDLE; mvkDev->destroyDescriptorSetLayout(mvkDSL, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyDescriptorSetLayout(
    VkDevice                                    device,
	VkDescriptorSetLayout                       descriptorSetLayout,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyDescriptorSetLayout((MVKDescriptorSetLayout*)descriptorSetLayout, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateDescriptorPool(
    VkDevice                                    device,
    const VkDescriptorPoolCreateInfo*           pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkDescriptorPool*                           pDescriptorPool) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKDescriptorPool* mvkDP = mvkDev->createDescriptorPool(pCreateInfo, pAllocator);
	*pDescriptorPool = (VkDescriptorPool)mvkDP;
	VkResult rslt = mvkDP->getConfigurationResult();
	if (rslt < 0) { *pDescriptorPool = VK_NULL_HANDLE; mvkDev->destroyDescriptorPool(mvkDP, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyDescriptorPool(
    VkDevice                                    device,
	VkDescriptorPool                            descriptorPool,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyDescriptorPool((MVKDescriptorPool*)descriptorPool, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkResetDescriptorPool(
	VkDevice                                    device,
	VkDescriptorPool                            descriptorPool,
	VkDescriptorPoolResetFlags                  flags) {

	MVKTraceVulkanCallStart();
	MVKDescriptorPool* mvkDP = (MVKDescriptorPool*)descriptorPool;
	VkResult rslt = mvkDP->reset(flags);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkAllocateDescriptorSets(
	VkDevice                                    device,
	const VkDescriptorSetAllocateInfo*          pAllocateInfo,
	VkDescriptorSet*                            pDescriptorSets) {

	MVKTraceVulkanCallStart();
	MVKDescriptorPool* mvkDP = (MVKDescriptorPool*)pAllocateInfo->descriptorPool;
	VkResult rslt = mvkDP->allocateDescriptorSets(pAllocateInfo, pDescriptorSets);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkFreeDescriptorSets(
    VkDevice                                    device,
    VkDescriptorPool                            descriptorPool,
    uint32_t                                    count,
	const VkDescriptorSet*                      pDescriptorSets) {

	MVKTraceVulkanCallStart();
	MVKDescriptorPool* mvkDP = (MVKDescriptorPool*)descriptorPool;
	VkResult rslt = mvkDP->freeDescriptorSets(count, pDescriptorSets);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkUpdateDescriptorSets(
    VkDevice                                    device,
    uint32_t                                    writeCount,
    const VkWriteDescriptorSet*                 pDescriptorWrites,
    uint32_t                                    copyCount,
    const VkCopyDescriptorSet*                  pDescriptorCopies) {
	
	MVKTraceVulkanCallStart();
	mvkUpdateDescriptorSets(writeCount, pDescriptorWrites, copyCount, pDescriptorCopies);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateFramebuffer(
    VkDevice                                    device,
    const VkFramebufferCreateInfo*              pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkFramebuffer*                              pFramebuffer) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKFramebuffer* mvkFB = mvkDev->createFramebuffer(pCreateInfo, pAllocator);
	*pFramebuffer = (VkFramebuffer)mvkFB;
	VkResult rslt = mvkFB->getConfigurationResult();
	if (rslt < 0) { *pFramebuffer = VK_NULL_HANDLE; mvkDev->destroyFramebuffer(mvkFB, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyFramebuffer(
    VkDevice                                    device,
	VkFramebuffer                               framebuffer,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyFramebuffer((MVKFramebuffer*)framebuffer, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateRenderPass(
    VkDevice                                    device,
    const VkRenderPassCreateInfo*               pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkRenderPass*                               pRenderPass) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKRenderPass* mvkRendPass = mvkDev->createRenderPass(pCreateInfo, pAllocator);
	*pRenderPass = (VkRenderPass)mvkRendPass;
	VkResult rslt = mvkRendPass->getConfigurationResult();
	if (rslt < 0) { *pRenderPass = VK_NULL_HANDLE; mvkDev->destroyRenderPass(mvkRendPass, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyRenderPass(
    VkDevice                                    device,
	VkRenderPass                                renderPass,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyRenderPass((MVKRenderPass*)renderPass, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetRenderAreaGranularity(
    VkDevice                                    device,
    VkRenderPass                                renderPass,
    VkExtent2D*                                 pGranularity) {

	MVKTraceVulkanCallStart();
    MVKRenderPass* mvkRendPass = (MVKRenderPass*)renderPass;
    *pGranularity = mvkRendPass->getRenderAreaGranularity();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateCommandPool(
    VkDevice                                    device,
    const VkCommandPoolCreateInfo*              pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkCommandPool*                              pCmdPool) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKCommandPool* mvkCmdPool = mvkDev->createCommandPool(pCreateInfo, pAllocator);
	*pCmdPool = (VkCommandPool)mvkCmdPool;
	VkResult rslt = mvkCmdPool->getConfigurationResult();
	if (rslt < 0) { *pCmdPool = VK_NULL_HANDLE; mvkDev->destroyCommandPool(mvkCmdPool, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyCommandPool(
    VkDevice                                    device,
	VkCommandPool                               commandPool,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyCommandPool((MVKCommandPool*)commandPool, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkResetCommandPool(
	VkDevice                                    device,
	VkCommandPool                               commandPool,
	VkCommandPoolResetFlags                     flags) {

	MVKTraceVulkanCallStart();
	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)commandPool;
	VkResult rslt = mvkCmdPool->reset(flags);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkAllocateCommandBuffers(
	VkDevice                                    device,
	const VkCommandBufferAllocateInfo*          pAllocateInfo,
	VkCommandBuffer*                            pCmdBuffer) {

	MVKTraceVulkanCallStart();
	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)pAllocateInfo->commandPool;
	VkResult rslt = mvkCmdPool->allocateCommandBuffers(pAllocateInfo, pCmdBuffer);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkFreeCommandBuffers(
    VkDevice                                    device,
	VkCommandPool                               commandPool,
	uint32_t                                    commandBufferCount,
	const VkCommandBuffer*                      pCommandBuffers) {

	MVKTraceVulkanCallStart();
	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)commandPool;
	mvkCmdPool->freeCommandBuffers(commandBufferCount, pCommandBuffers);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkBeginCommandBuffer(
    VkCommandBuffer                             commandBuffer,
    const VkCommandBufferBeginInfo*             pBeginInfo) {
	
	MVKTraceVulkanCallStart();
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	VkResult rslt = cmdBuff->begin(pBeginInfo);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkEndCommandBuffer(
    VkCommandBuffer                             commandBuffer) {
	
	MVKTraceVulkanCallStart();
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	VkResult rslt = cmdBuff->end();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkResetCommandBuffer(
    VkCommandBuffer                             commandBuffer,
    VkCommandBufferResetFlags                   flags) {

	MVKTraceVulkanCallStart();
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	VkResult rslt = cmdBuff->reset(flags);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBindPipeline(
    VkCommandBuffer                             commandBuffer,
    VkPipelineBindPoint                         pipelineBindPoint,
    VkPipeline                                  pipeline) {
	
	MVKTraceVulkanCallStart();
	switch (pipelineBindPoint) {
		case VK_PIPELINE_BIND_POINT_GRAPHICS: {
			MVKAddCmd(BindGraphicsPipeline, commandBuffer, pipeline);
			break;
		}
		case VK_PIPELINE_BIND_POINT_COMPUTE: {
			MVKAddCmd(BindComputePipeline, commandBuffer, pipeline);
			break;
		}
		default:
			break;
	}
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetViewport(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    firstViewport,
	uint32_t                                    viewportCount,
	const VkViewport*                           pViewports) {

	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(SetViewport, viewportCount, 1, commandBuffer, firstViewport, viewportCount, pViewports);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetScissor(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    firstScissor,
	uint32_t                                    scissorCount,
	const VkRect2D*                             pScissors) {

	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(SetScissor, scissorCount, 1, commandBuffer, firstScissor, scissorCount, pScissors);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetLineWidth(
	VkCommandBuffer                             commandBuffer,
	float                                       lineWidth) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetLineWidth, commandBuffer, lineWidth);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetDepthBias(
	VkCommandBuffer                             commandBuffer,
	float                                       depthBiasConstantFactor,
	float                                       depthBiasClamp,
	float                                       depthBiasSlopeFactor) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetDepthBias, commandBuffer,depthBiasConstantFactor, depthBiasClamp, depthBiasSlopeFactor);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetBlendConstants(
	VkCommandBuffer                             commandBuffer,
	const float                                 blendConst[4]) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetBlendConstants, commandBuffer, blendConst);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetDepthBounds(
	VkCommandBuffer                             commandBuffer,
	float                                       minDepthBounds,
	float                                       maxDepthBounds) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetDepthBounds, commandBuffer, minDepthBounds, maxDepthBounds);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetStencilCompareMask(
	VkCommandBuffer                             commandBuffer,
	VkStencilFaceFlags                          faceMask,
	uint32_t                                    stencilCompareMask) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetStencilCompareMask, commandBuffer, faceMask, stencilCompareMask);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetStencilWriteMask(
	VkCommandBuffer                             commandBuffer,
	VkStencilFaceFlags                          faceMask,
	uint32_t                                    stencilWriteMask) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetStencilWriteMask, commandBuffer, faceMask, stencilWriteMask);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetStencilReference(
	VkCommandBuffer                             commandBuffer,
	VkStencilFaceFlags                          faceMask,
	uint32_t                                    stencilReference) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetStencilReference, commandBuffer, faceMask, stencilReference);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBindDescriptorSets(
    VkCommandBuffer                             commandBuffer,
    VkPipelineBindPoint                         pipelineBindPoint,
    VkPipelineLayout                            layout,
    uint32_t                                    firstSet,
    uint32_t                                    setCount,
    const VkDescriptorSet*                      pDescriptorSets,
    uint32_t                                    dynamicOffsetCount,
    const uint32_t*                             pDynamicOffsets) {
	
	MVKTraceVulkanCallStart();
	if (dynamicOffsetCount) {
		MVKAddCmdFromThreshold(BindDescriptorSetsDynamic, setCount, 4, commandBuffer, pipelineBindPoint, layout,
				  firstSet, setCount, pDescriptorSets, dynamicOffsetCount, pDynamicOffsets);
	} else {
		MVKAddCmdFrom2Thresholds(BindDescriptorSetsStatic, setCount, 1, 4, commandBuffer, pipelineBindPoint, layout,
				  firstSet, setCount, pDescriptorSets);
	}
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBindIndexBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    VkIndexType                                 indexType) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(BindIndexBuffer, commandBuffer, buffer, offset, indexType);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBindVertexBuffers(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    startBinding,
    uint32_t                                    bindingCount,
    const VkBuffer*                             pBuffers,
    const VkDeviceSize*                         pOffsets) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFrom2Thresholds(BindVertexBuffers, bindingCount, 1, 2, commandBuffer, startBinding, bindingCount, pBuffers, pOffsets);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDraw(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    vertexCount,
	uint32_t                                    instanceCount,
	uint32_t                                    firstVertex,
	uint32_t                                    firstInstance) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(Draw, commandBuffer, vertexCount, instanceCount, firstVertex, firstInstance);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDrawIndexed(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    indexCount,
	uint32_t                                    instanceCount,
	uint32_t                                    firstIndex,
	int32_t                                     vertexOffset,
	uint32_t                                    firstInstance) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DrawIndexed, commandBuffer, indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDrawIndirect(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    uint32_t                                    drawCount,
    uint32_t                                    stride) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(DrawIndirect, commandBuffer, buffer, offset, drawCount, stride);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDrawIndexedIndirect(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    uint32_t                                    drawCount,
    uint32_t                                    stride) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(DrawIndexedIndirect, commandBuffer, buffer, offset, drawCount, stride);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDispatch(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    x,
    uint32_t                                    y,
    uint32_t                                    z) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(Dispatch, commandBuffer, 0, 0, 0, x, y, z);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDispatchIndirect(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset) {
	
	MVKTraceVulkanCallStart();
    MVKAddCmd(DispatchIndirect, commandBuffer, buffer, offset);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdCopyBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    srcBuffer,
    VkBuffer                                    destBuffer,
    uint32_t                                    regionCount,
    const VkBufferCopy*                         pRegions) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(CopyBuffer, regionCount, 1, commandBuffer, srcBuffer, destBuffer, regionCount, pRegions);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdCopyImage(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     srcImage,
    VkImageLayout                               srcImageLayout,
    VkImage                                     dstImage,
    VkImageLayout                               dstImageLayout,
    uint32_t                                    regionCount,
    const VkImageCopy*                          pRegions) {

	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(CopyImage, regionCount, 1, commandBuffer,
						   srcImage, srcImageLayout, dstImage, dstImageLayout, regionCount, pRegions);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBlitImage(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     srcImage,
    VkImageLayout                               srcImageLayout,
    VkImage                                     dstImage,
    VkImageLayout                               dstImageLayout,
    uint32_t                                    regionCount,
    const VkImageBlit*                          pRegions,
    VkFilter                                    filter) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(BlitImage, regionCount, 1, commandBuffer,
						   srcImage, srcImageLayout, dstImage, dstImageLayout, regionCount, pRegions, filter);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdCopyBufferToImage(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    srcBuffer,
    VkImage                                     dstImage,
    VkImageLayout                               dstImageLayout,
    uint32_t                                    regionCount,
    const VkBufferImageCopy*                    pRegions) {
	
	MVKTraceVulkanCallStart();
    MVKAddCmdFrom3Thresholds(BufferImageCopy, regionCount, 1, 4, 8, commandBuffer,
							 srcBuffer, dstImage, dstImageLayout, regionCount, pRegions, true);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdCopyImageToBuffer(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     srcImage,
    VkImageLayout                               srcImageLayout,
    VkBuffer                                    dstBuffer,
    uint32_t                                    regionCount,
    const VkBufferImageCopy*                    pRegions) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFrom3Thresholds(BufferImageCopy, regionCount, 1, 4, 8, commandBuffer,
							 dstBuffer, srcImage, srcImageLayout, regionCount, pRegions, false);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdUpdateBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    dstBuffer,
    VkDeviceSize                                dstOffset,
    VkDeviceSize                                dataSize,
    const void*                                 pData) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(UpdateBuffer, commandBuffer, dstBuffer, dstOffset, dataSize, pData);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdFillBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    dstBuffer,
    VkDeviceSize                                dstOffset,
    VkDeviceSize                                size,
    uint32_t                                    data) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(FillBuffer, commandBuffer, dstBuffer, dstOffset, size, data);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdClearColorImage(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     image,
    VkImageLayout                               imageLayout,
    const VkClearColorValue*                    pColor,
    uint32_t                                    rangeCount,
    const VkImageSubresourceRange*              pRanges) {
	
	MVKTraceVulkanCallStart();
	VkClearValue clrVal;
	clrVal.color = *pColor;
	MVKAddCmdFromThreshold(ClearColorImage, rangeCount, 1, commandBuffer,
						   image, imageLayout, clrVal, rangeCount, pRanges);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdClearDepthStencilImage(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     image,
    VkImageLayout                               imageLayout,
    const VkClearDepthStencilValue*             pDepthStencil,
    uint32_t                                    rangeCount,
    const VkImageSubresourceRange*              pRanges) {

	MVKTraceVulkanCallStart();
	VkClearValue clrVal;
	clrVal.depthStencil = *pDepthStencil;
    MVKAddCmdFromThreshold(ClearDepthStencilImage, rangeCount, 1, commandBuffer,
						   image, imageLayout, clrVal, rangeCount, pRanges);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdClearAttachments(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    attachmentCount,
	const VkClearAttachment*                    pAttachments,
	uint32_t                                    rectCount,
	const VkClearRect*                          pRects) {

	MVKTraceVulkanCallStart();
	if (attachmentCount > 1) {
		MVKAddCmdFromThreshold(ClearMultiAttachments, rectCount, 1, commandBuffer,
							   attachmentCount, pAttachments, rectCount, pRects);
	} else {
		MVKAddCmdFromThreshold(ClearSingleAttachment, rectCount, 1, commandBuffer,
							   attachmentCount, pAttachments, rectCount, pRects);
	}
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdResolveImage(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     srcImage,
    VkImageLayout                               srcImageLayout,
    VkImage                                     dstImage,
    VkImageLayout                               dstImageLayout,
    uint32_t                                    regionCount,
    const VkImageResolve*                       pRegions) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(ResolveImage, regionCount, 1, commandBuffer,
						   srcImage, srcImageLayout, dstImage, dstImageLayout, regionCount, pRegions);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetEvent(
    VkCommandBuffer                             commandBuffer,
    VkEvent                                     event,
    VkPipelineStageFlags                        stageMask) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(SetEvent, commandBuffer, event, stageMask);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdResetEvent(
    VkCommandBuffer                             commandBuffer,
    VkEvent                                     event,
    VkPipelineStageFlags                        stageMask) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(ResetEvent, commandBuffer, event, stageMask);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdWaitEvents(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    eventCount,
	const VkEvent*                              pEvents,
	VkPipelineStageFlags                        srcStageMask,
	VkPipelineStageFlags                        dstStageMask,
	uint32_t                                    memoryBarrierCount,
	const VkMemoryBarrier*                      pMemoryBarriers,
	uint32_t                                    bufferMemoryBarrierCount,
	const VkBufferMemoryBarrier*                pBufferMemoryBarriers,
	uint32_t                                    imageMemoryBarrierCount,
	const VkImageMemoryBarrier*                 pImageMemoryBarriers) {

	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(WaitEvents, eventCount, 1, commandBuffer,
						   eventCount, pEvents, srcStageMask, dstStageMask,
						   memoryBarrierCount, pMemoryBarriers,
						   bufferMemoryBarrierCount, pBufferMemoryBarriers,
						   imageMemoryBarrierCount, pImageMemoryBarriers);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdPipelineBarrier(
	VkCommandBuffer                             commandBuffer,
	VkPipelineStageFlags                        srcStageMask,
	VkPipelineStageFlags                        dstStageMask,
	VkDependencyFlags                           dependencyFlags,
	uint32_t                                    memoryBarrierCount,
	const VkMemoryBarrier*                      pMemoryBarriers,
	uint32_t                                    bufferMemoryBarrierCount,
	const VkBufferMemoryBarrier*                pBufferMemoryBarriers,
	uint32_t                                    imageMemoryBarrierCount,
	const VkImageMemoryBarrier*                 pImageMemoryBarriers) {

	MVKTraceVulkanCallStart();
	uint32_t barrierCount = memoryBarrierCount + bufferMemoryBarrierCount + imageMemoryBarrierCount;
	MVKAddCmdFrom2Thresholds(PipelineBarrier, barrierCount, 1, 4, commandBuffer,
							   srcStageMask, dstStageMask, dependencyFlags,
							   memoryBarrierCount, pMemoryBarriers,
							   bufferMemoryBarrierCount, pBufferMemoryBarriers,
							   imageMemoryBarrierCount, pImageMemoryBarriers);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBeginQuery(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    query,
    VkQueryControlFlags                         flags) {
	
	MVKTraceVulkanCallStart();
    MVKAddCmd(BeginQuery, commandBuffer, queryPool, query, flags);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdEndQuery(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    query) {
	
	MVKTraceVulkanCallStart();
    MVKAddCmd(EndQuery, commandBuffer, queryPool, query);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdResetQueryPool(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    firstQuery,
    uint32_t                                    queryCount) {
	
	MVKTraceVulkanCallStart();
    MVKAddCmd(ResetQueryPool, commandBuffer, queryPool, firstQuery, queryCount);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdWriteTimestamp(
	VkCommandBuffer                             commandBuffer,
	VkPipelineStageFlagBits                     pipelineStage,
	VkQueryPool                                 queryPool,
	uint32_t                                    query) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(WriteTimestamp, commandBuffer, pipelineStage, queryPool, query);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdCopyQueryPoolResults(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    firstQuery,
    uint32_t                                    queryCount,
    VkBuffer                                    destBuffer,
    VkDeviceSize                                destOffset,
    VkDeviceSize                                destStride,
    VkQueryResultFlags                          flags) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(CopyQueryPoolResults, commandBuffer, queryPool, firstQuery,
			  queryCount, destBuffer, destOffset, destStride, flags);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdPushConstants(
    VkCommandBuffer                             commandBuffer,
    VkPipelineLayout                            layout,
    VkShaderStageFlags                          stageFlags,
    uint32_t                                    offset,
    uint32_t                                    size,
    const void*                                 pValues) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFrom2Thresholds(PushConstants, size, 64, 128, commandBuffer, layout, stageFlags, offset, size, pValues);
	MVKTraceVulkanCallEnd();
}

// Consolidation function
static void mvkCmdBeginRenderPass(
	VkCommandBuffer								commandBuffer,
	const VkRenderPassBeginInfo*				pRenderPassBegin,
	const VkSubpassBeginInfo*					pSubpassBeginInfo) {

	VkRenderPassAttachmentBeginInfo* pAttachmentBegin = nullptr;
	for (const auto* next = (VkBaseInStructure*)pRenderPassBegin->pNext; next; next = next->pNext) {
		switch(next->sType) {
			case VK_STRUCTURE_TYPE_RENDER_PASS_ATTACHMENT_BEGIN_INFO: {
				pAttachmentBegin = (VkRenderPassAttachmentBeginInfo*)next;
				break;
			}
			default:
				break;
		}
	}
	auto attachments = (pAttachmentBegin
						? MVKArrayRef<MVKImageView*>((MVKImageView**)pAttachmentBegin->pAttachments,
													 pAttachmentBegin->attachmentCount)
						: ((MVKFramebuffer*)pRenderPassBegin->framebuffer)->getAttachments());
	
	MVKAddCmdFrom5Thresholds(BeginRenderPass,
							 pRenderPassBegin->clearValueCount, 1, 2,
							 attachments.size, 0, 1, 2,
							 commandBuffer,
							 pRenderPassBegin,
							 pSubpassBeginInfo,
							 attachments);
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBeginRenderPass(
    VkCommandBuffer                             commandBuffer,
    const VkRenderPassBeginInfo*                pRenderPassBegin,
    VkSubpassContents							contents) {

	MVKTraceVulkanCallStart();

	VkSubpassBeginInfo spBeginInfo;
	spBeginInfo.sType = VK_STRUCTURE_TYPE_SUBPASS_BEGIN_INFO;
	spBeginInfo.pNext = nullptr;
	spBeginInfo.contents = contents;

	mvkCmdBeginRenderPass(commandBuffer, pRenderPassBegin, &spBeginInfo);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdNextSubpass(
    VkCommandBuffer                             commandBuffer,
    VkSubpassContents							contents) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(NextSubpass, commandBuffer, contents);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdEndRenderPass(
    VkCommandBuffer                             commandBuffer) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(EndRenderPass, commandBuffer);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdExecuteCommands(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    cmdBuffersCount,
    const VkCommandBuffer*						pCommandBuffers) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(ExecuteCommands, cmdBuffersCount, 1, commandBuffer, cmdBuffersCount, pCommandBuffers);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark Vulkan 1.1 calls

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkEnumerateInstanceVersion(
    uint32_t*                                   pApiVersion) {

    MVKTraceVulkanCallStart();
    *pApiVersion = mvkConfig().apiVersionToAdvertise;
    MVKTraceVulkanCallEnd();
    return VK_SUCCESS;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkEnumeratePhysicalDeviceGroups(
    VkInstance                                  instance,
    uint32_t*                                   pPhysicalDeviceGroupCount,
    VkPhysicalDeviceGroupProperties*            pPhysicalDeviceGroupProperties) {
    MVKTraceVulkanCallStart();
    MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
    VkResult rslt = mvkInst->getPhysicalDeviceGroups(pPhysicalDeviceGroupCount, pPhysicalDeviceGroupProperties);
    MVKTraceVulkanCallEnd();
    return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceFeatures2(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceFeatures2*                  pFeatures) {
    
	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getFeatures(pFeatures);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceProperties2(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceProperties2*                pProperties) {

	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getProperties(pProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceFormatProperties2(
    VkPhysicalDevice                            physicalDevice,
    VkFormat                                    format,
    VkFormatProperties2*                        pFormatProperties) {
    
	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getFormatProperties(format, pFormatProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDeviceImageFormatProperties2(
    VkPhysicalDevice                            physicalDevice,
    const VkPhysicalDeviceImageFormatInfo2*     pImageFormatInfo,
    VkImageFormatProperties2*                   pImageFormatProperties) {
    
	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    VkResult rslt = mvkPD->getImageFormatProperties(pImageFormatInfo, pImageFormatProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceQueueFamilyProperties2(
    VkPhysicalDevice                            physicalDevice,
    uint32_t*                                   pQueueFamilyPropertyCount,
    VkQueueFamilyProperties2*                   pQueueFamilyProperties) {
    
	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getQueueFamilyProperties(pQueueFamilyPropertyCount, pQueueFamilyProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceMemoryProperties2(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceMemoryProperties2*          pMemoryProperties) {

	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getMemoryProperties(pMemoryProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceSparseImageFormatProperties2(
    VkPhysicalDevice                              physicalDevice,
    const VkPhysicalDeviceSparseImageFormatInfo2* pFormatInfo,
    uint32_t*                                     pPropertyCount,
    VkSparseImageFormatProperties2*               pProperties) {

	MVKTraceVulkanCallStart();

	// Metal does not support sparse images.
	// Vulkan spec: "If VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT is not supported for the given arguments,
	// pPropertyCount will be set to zero upon return, and no data will be written to pProperties.".

    *pPropertyCount = 0;
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceExternalFenceProperties(
	VkPhysicalDevice                            physicalDevice,
	const VkPhysicalDeviceExternalFenceInfo*    pExternalFenceInfo,
	VkExternalFenceProperties*                  pExternalFenceProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getExternalFenceProperties(pExternalFenceInfo, pExternalFenceProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceExternalBufferProperties(
	VkPhysicalDevice                            physicalDevice,
	const VkPhysicalDeviceExternalBufferInfo*   pExternalBufferInfo,
	VkExternalBufferProperties*                 pExternalBufferProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getExternalBufferProperties(pExternalBufferInfo, pExternalBufferProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPhysicalDeviceExternalSemaphoreProperties(
	VkPhysicalDevice                             physicalDevice,
	const VkPhysicalDeviceExternalSemaphoreInfo* pExternalSemaphoreInfo,
	VkExternalSemaphoreProperties*               pExternalSemaphoreProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getExternalSemaphoreProperties(pExternalSemaphoreInfo, pExternalSemaphoreProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetDeviceQueue2(
    VkDevice                                    device,
    const VkDeviceQueueInfo2*                   pQueueInfo,
    VkQueue*                                    pQueue) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	*pQueue = mvkDev->getQueue(pQueueInfo)->getVkQueue();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkBindBufferMemory2(
	VkDevice									device,
	uint32_t									bindInfoCount,
	const VkBindBufferMemoryInfo*				pBindInfos) {

	MVKTraceVulkanCallStart();
	VkResult rslt = VK_SUCCESS;
	for (uint32_t i = 0; i < bindInfoCount; ++i) {
		MVKBuffer* mvkBuff = (MVKBuffer*)pBindInfos[i].buffer;
		VkResult r = mvkBuff->bindDeviceMemory2(&pBindInfos[i]);
		if (rslt == VK_SUCCESS) { rslt = r; }
	}
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkBindImageMemory2(
	VkDevice									device,
	uint32_t									bindInfoCount,
	const VkBindImageMemoryInfo*				pBindInfos) {

	MVKTraceVulkanCallStart();
	VkResult rslt = VK_SUCCESS;
	for (uint32_t i = 0; i < bindInfoCount; ++i) {
		MVKImage* mvkImg = (MVKImage*)pBindInfos[i].image;
		VkResult r = mvkImg->bindDeviceMemory2(&pBindInfos[i]);
		if (rslt == VK_SUCCESS) { rslt = r; }
	}
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetBufferMemoryRequirements2(
    VkDevice                                    device,
    const VkBufferMemoryRequirementsInfo2*      pInfo,
    VkMemoryRequirements2*                      pMemoryRequirements) {

	MVKTraceVulkanCallStart();
    MVKBuffer* mvkBuff = (MVKBuffer*)pInfo->buffer;
    mvkBuff->getMemoryRequirements(pInfo, pMemoryRequirements);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetImageMemoryRequirements2(
    VkDevice                                    device,
    const VkImageMemoryRequirementsInfo2*       pInfo,
    VkMemoryRequirements2*                      pMemoryRequirements) {

	MVKTraceVulkanCallStart();
    auto* mvkImg = (MVKImage*)pInfo->image;
    mvkImg->getMemoryRequirements(pInfo, pMemoryRequirements);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetImageSparseMemoryRequirements2(
    VkDevice                                        device,
    const VkImageSparseMemoryRequirementsInfo2*     pInfo,
    uint32_t*                                       pSparseMemoryRequirementCount,
    VkSparseImageMemoryRequirements2*               pSparseMemoryRequirements) {

	MVKTraceVulkanCallStart();

	// Metal does not support sparse images.
	// Vulkan spec: "If the image was not created with VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT then
	// pSparseMemoryRequirementCount will be set to zero and pSparseMemoryRequirements will not be written to.".

    *pSparseMemoryRequirementCount = 0;
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetDeviceGroupPeerMemoryFeatures(
    VkDevice                                    device,
    uint32_t                                    heapIndex,
    uint32_t                                    localDeviceIndex,
    uint32_t                                    remoteDeviceIndex,
    VkPeerMemoryFeatureFlags*                   pPeerMemoryFeatures) {

    MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->getPeerMemoryFeatures(heapIndex, localDeviceIndex, remoteDeviceIndex, pPeerMemoryFeatures);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateDescriptorUpdateTemplate(
    VkDevice                                       device,
    const VkDescriptorUpdateTemplateCreateInfo*    pCreateInfo,
    const VkAllocationCallbacks*                   pAllocator,
    VkDescriptorUpdateTemplate*                    pDescriptorUpdateTemplate) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    auto *mvkDUT = mvkDev->createDescriptorUpdateTemplate(pCreateInfo,
                                                          pAllocator);
    *pDescriptorUpdateTemplate = (VkDescriptorUpdateTemplate)mvkDUT;
    VkResult rslt = mvkDUT->getConfigurationResult();
    if (rslt < 0) {
        *pDescriptorUpdateTemplate = VK_NULL_HANDLE;
        mvkDev->destroyDescriptorUpdateTemplate(mvkDUT, pAllocator);
    }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyDescriptorUpdateTemplate(
    VkDevice                                    device,
    VkDescriptorUpdateTemplate                  descriptorUpdateTemplate,
    const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroyDescriptorUpdateTemplate((MVKDescriptorUpdateTemplate*)descriptorUpdateTemplate, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkUpdateDescriptorSetWithTemplate(
    VkDevice                                    device,
    VkDescriptorSet                             descriptorSet,
    VkDescriptorUpdateTemplate                  descriptorUpdateTemplate,
    const void*                                 pData) {

	MVKTraceVulkanCallStart();
    mvkUpdateDescriptorSetWithTemplate(descriptorSet, descriptorUpdateTemplate, pData);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetDescriptorSetLayoutSupport(
    VkDevice                                    device,
    const VkDescriptorSetLayoutCreateInfo*      pCreateInfo,
    VkDescriptorSetLayoutSupport*               pSupport) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDevice = MVKDevice::getMVKDevice(device);
    mvkDevice->getDescriptorSetLayoutSupport(pCreateInfo, pSupport);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateSamplerYcbcrConversion(
    VkDevice                                    device,
    const VkSamplerYcbcrConversionCreateInfo*   pCreateInfo,
    const VkAllocationCallbacks*                pAllocator,
    VkSamplerYcbcrConversion*                   pYcbcrConversion) {

    MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKSamplerYcbcrConversion* mvkSampConv = mvkDev->createSamplerYcbcrConversion(pCreateInfo, pAllocator);
	*pYcbcrConversion = (VkSamplerYcbcrConversion)mvkSampConv;
	VkResult rslt = mvkSampConv->getConfigurationResult();
    if (rslt < 0) {
        *pYcbcrConversion = VK_NULL_HANDLE;
        mvkDev->destroySamplerYcbcrConversion(mvkSampConv, pAllocator);
    }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroySamplerYcbcrConversion(
    VkDevice                                    device,
    VkSamplerYcbcrConversion                    ycbcrConversion,
    const VkAllocationCallbacks*                pAllocator) {

    MVKTraceVulkanCallStart();
	if ( !ycbcrConversion ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroySamplerYcbcrConversion((MVKSamplerYcbcrConversion*)ycbcrConversion, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkTrimCommandPool(
    VkDevice                                    device,
    VkCommandPool                               commandPool,
    VkCommandPoolTrimFlags                      flags) {

	MVKTraceVulkanCallStart();
	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)commandPool;
    mvkCmdPool->trim();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdSetDeviceMask(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    deviceMask) {

    MVKTraceVulkanCallStart();
	// No-op for now...
//    MVKAddCmd(SetDeviceMask, commandBuffer, deviceMask);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDispatchBase(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    baseGroupX,
    uint32_t                                    baseGroupY,
    uint32_t                                    baseGroupZ,
    uint32_t                                    groupCountX,
    uint32_t                                    groupCountY,
    uint32_t                                    groupCountZ) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(Dispatch, commandBuffer, baseGroupX, baseGroupY, baseGroupZ, groupCountX, groupCountY, groupCountZ);
	MVKTraceVulkanCallEnd();
}

#pragma mark -
#pragma mark Vulkan 1.2 calls

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBeginRenderPass2(
	VkCommandBuffer								commandBuffer,
	const VkRenderPassBeginInfo*				pRenderPassBegin,
	const VkSubpassBeginInfo*					pSubpassBeginInfo) {

	MVKTraceVulkanCallStart();
	mvkCmdBeginRenderPass(commandBuffer, pRenderPassBegin, pSubpassBeginInfo);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDrawIndexedIndirectCount(
	VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    VkBuffer                                    countBuffer,
    VkDeviceSize                                countBufferOffset,
    uint32_t                                    maxDrawCount,
    uint32_t                                    stride) {

	MVKTraceVulkanCallStart();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDrawIndirectCount(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    VkBuffer                                    countBuffer,
    VkDeviceSize                                countBufferOffset,
    uint32_t                                    maxDrawCount,
    uint32_t                                    stride) {

	MVKTraceVulkanCallStart();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdEndRenderPass2(
	VkCommandBuffer								commandBuffer,
	const VkSubpassEndInfo*						pSubpassEndInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(EndRenderPass, commandBuffer, pSubpassEndInfo);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdNextSubpass2(
	VkCommandBuffer								commandBuffer,
	const VkSubpassBeginInfo*					pSubpassBeginInfo,
	const VkSubpassEndInfo*						pSubpassEndInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(NextSubpass, commandBuffer, pSubpassBeginInfo, pSubpassEndInfo);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateRenderPass2(
	VkDevice									device,
	const VkRenderPassCreateInfo2*				pCreateInfo,
	const VkAllocationCallbacks*				pAllocator,
	VkRenderPass*								pRenderPass) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKRenderPass* mvkRendPass = mvkDev->createRenderPass(pCreateInfo, pAllocator);
	*pRenderPass = (VkRenderPass)mvkRendPass;
	VkResult rslt = mvkRendPass->getConfigurationResult();
    if (rslt < 0) { *pRenderPass = VK_NULL_HANDLE; mvkDev->destroyRenderPass(mvkRendPass, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkDeviceAddress vkGetBufferDeviceAddress(
	VkDevice                                    device,
	const VkBufferDeviceAddressInfo*            pInfo) {
	
	MVKTraceVulkanCallStart();
	uint64_t result = ((MVKBuffer*)pInfo->buffer)->getMTLBufferGPUAddress();
	MVKTraceVulkanCallEnd();
	return (VkDeviceAddress)result;
}

MVK_PUBLIC_VULKAN_SYMBOL uint64_t vkGetBufferOpaqueCaptureAddress(
	VkDevice                                    device,
	const VkBufferDeviceAddressInfo*            pInfo) {
	
	return 0;
}

MVK_PUBLIC_VULKAN_SYMBOL uint64_t vkGetDeviceMemoryOpaqueCaptureAddress(
	VkDevice                                    device,
	const VkDeviceMemoryOpaqueCaptureAddressInfo*            pInfo) {
	
	return 0;
}


MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetSemaphoreCounterValue(
	VkDevice									device,
	VkSemaphore									semaphore,
	uint64_t*									pValue) {

	MVKTraceVulkanCallStart();
	VkResult rslt = MVKDevice::getMVKDevice(device)->getConfigurationResult();
	if (rslt == VK_SUCCESS) {
		auto* mvkSem4 = (MVKTimelineSemaphore*)semaphore;
		*pValue = mvkSem4->getCounterValue();
	}
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkResetQueryPool(
    VkDevice                                    device,
    VkQueryPool                                 queryPool,
    uint32_t                                    firstQuery,
    uint32_t                                    queryCount) {

	MVKTraceVulkanCallStart();
    auto* mvkQueryPool = (MVKQueryPool*)queryPool;
    mvkQueryPool->resetResults(firstQuery, queryCount, nullptr);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkSignalSemaphore(
	VkDevice									device,
	const VkSemaphoreSignalInfo*				pSignalInfo) {

	MVKTraceVulkanCallStart();
	auto* mvkSem4 = (MVKTimelineSemaphore*)pSignalInfo->semaphore;
	mvkSem4->signal(pSignalInfo);
	MVKTraceVulkanCallEnd();
	return VK_SUCCESS;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkWaitSemaphores(
	VkDevice									device,
	const VkSemaphoreWaitInfo*				    pWaitInfo,
	uint64_t									timeout) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkWaitSemaphores(mvkDev, pWaitInfo, timeout);
	MVKTraceVulkanCallEnd();
	return rslt;
}

#pragma mark -
#pragma mark Vulkan 1.3 calls

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBeginRendering(
        VkCommandBuffer                             commandBuffer,
        const VkRenderingInfo*                      pRenderingInfo) {

    MVKTraceVulkanCallStart();
    MVKAddCmdFrom3Thresholds(BeginRendering, pRenderingInfo->colorAttachmentCount,
                             1, 2, 4, commandBuffer, pRenderingInfo);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdEndRendering(
        VkCommandBuffer                             commandBuffer) {

    MVKTraceVulkanCallStart();
    MVKAddCmd(EndRendering, commandBuffer);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_STUB(vkCmdBindVertexBuffers2, void, VkCommandBuffer, uint32_t, uint32_t, const VkBuffer*, const VkDeviceSize*, const VkDeviceSize*, const VkDeviceSize*)

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBlitImage2(
        VkCommandBuffer                             commandBuffer,
        const VkBlitImageInfo2*                     pBlitImageInfo) {
    MVKTraceVulkanCallStart();
    MVKAddCmdFromThreshold(BlitImage, pBlitImageInfo->regionCount, 1, commandBuffer,
                           pBlitImageInfo);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdCopyBuffer2(
        VkCommandBuffer commandBuffer,
        const VkCopyBufferInfo2* pCopyBufferInfo) {
    MVKTraceVulkanCallStart();
    MVKAddCmdFromThreshold(CopyBuffer, pCopyBufferInfo->regionCount, 1, commandBuffer, pCopyBufferInfo);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdCopyBufferToImage2(
        VkCommandBuffer                             commandBuffer,
        const VkCopyBufferToImageInfo2*             pCopyBufferToImageInfo) {
    MVKTraceVulkanCallStart();
    MVKAddCmdFrom3Thresholds(BufferImageCopy, pCopyBufferToImageInfo->regionCount, 1, 4, 8, commandBuffer,
                             pCopyBufferToImageInfo);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdCopyImage2(
        VkCommandBuffer                             commandBuffer,
        const VkCopyImageInfo2*                     pCopyImageInfo) {
    MVKTraceVulkanCallStart();
    MVKAddCmdFromThreshold(CopyImage, pCopyImageInfo->regionCount, 1, commandBuffer,
                           pCopyImageInfo);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdCopyImageToBuffer2(
        VkCommandBuffer                             commandBuffer,
        const VkCopyImageToBufferInfo2*             pCopyImageInfo) {
    MVKTraceVulkanCallStart();
    MVKAddCmdFrom3Thresholds(BufferImageCopy, pCopyImageInfo->regionCount, 1, 4, 8, commandBuffer,
                             pCopyImageInfo);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_STUB(vkCmdPipelineBarrier2, void, VkCommandBuffer, const VkDependencyInfo*)
MVK_PUBLIC_VULKAN_STUB(vkCmdResetEvent2, void, VkCommandBuffer, VkEvent, VkPipelineStageFlags2 stageMask)

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdResolveImage2(
        VkCommandBuffer commandBuffer,
        const VkResolveImageInfo2* pResolveImageInfo) {
    MVKTraceVulkanCallStart();
    MVKAddCmdFromThreshold(ResolveImage, pResolveImageInfo->regionCount, 1, commandBuffer,
                           pResolveImageInfo);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_STUB(vkCmdSetCullMode, void, VkCommandBuffer, VkCullModeFlags)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetDepthBiasEnable, void, VkCommandBuffer, VkBool32)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetDepthBoundsTestEnable, void, VkCommandBuffer, VkBool32)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetDepthCompareOp, void, VkCommandBuffer, VkCompareOp)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetDepthTestEnable, void, VkCommandBuffer, VkBool32)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetDepthWriteEnable, void, VkCommandBuffer, VkBool32)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetEvent2, void, VkCommandBuffer, VkEvent, const VkDependencyInfo*)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetFrontFace, void, VkCommandBuffer, VkFrontFace)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetPrimitiveRestartEnable, void, VkCommandBuffer, VkBool32)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetPrimitiveTopology, void, VkCommandBuffer, VkPrimitiveTopology)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetRasterizerDiscardEnable, void, VkCommandBuffer, VkBool32)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetScissorWithCount, void, VkCommandBuffer, uint32_t, const VkRect2D*)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetStencilOp, void, VkCommandBuffer, VkStencilFaceFlags, VkStencilOp, VkStencilOp, VkStencilOp, VkCompareOp)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetStencilTestEnable, void, VkCommandBuffer, VkBool32)
MVK_PUBLIC_VULKAN_STUB(vkCmdSetViewportWithCount, void, VkCommandBuffer, uint32_t, const VkViewport*)
MVK_PUBLIC_VULKAN_STUB(vkCmdWaitEvents2, void, VkCommandBuffer, uint32_t, const VkEvent*, const VkDependencyInfo*)
MVK_PUBLIC_VULKAN_STUB(vkCmdWriteTimestamp2, void, VkCommandBuffer, VkPipelineStageFlags2, VkQueryPool, uint32_t)
MVK_PUBLIC_VULKAN_STUB_VKRESULT(vkCreatePrivateDataSlot, VkDevice, const VkPrivateDataSlotCreateInfo*, const VkAllocationCallbacks*, VkPrivateDataSlot*)
MVK_PUBLIC_VULKAN_STUB(vkDestroyPrivateDataSlot, void, VkDevice, VkPrivateDataSlot, const VkAllocationCallbacks*)
MVK_PUBLIC_VULKAN_STUB(vkGetDeviceBufferMemoryRequirements, void, VkDevice, const VkDeviceBufferMemoryRequirements*, VkMemoryRequirements2*)
MVK_PUBLIC_VULKAN_STUB(vkGetDeviceImageMemoryRequirements, void, VkDevice, const VkDeviceImageMemoryRequirements*, VkMemoryRequirements2*)
MVK_PUBLIC_VULKAN_STUB(vkGetDeviceImageSparseMemoryRequirements, void, VkDevice, const VkDeviceImageMemoryRequirements*, uint32_t*, VkSparseImageMemoryRequirements2*)
MVK_PUBLIC_VULKAN_STUB_VKRESULT(vkGetPhysicalDeviceToolProperties, VkPhysicalDevice, uint32_t*, VkPhysicalDeviceToolProperties*)
MVK_PUBLIC_VULKAN_STUB(vkGetPrivateData, void, VkDevice, VkObjectType, uint64_t, VkPrivateDataSlot, uint64_t*)
MVK_PUBLIC_VULKAN_STUB_VKRESULT(vkQueueSubmit2, VkQueue, uint32_t, const VkSubmitInfo2*, VkFence)
MVK_PUBLIC_VULKAN_STUB_VKRESULT(vkSetPrivateData, VkDevice, VkObjectType, uint64_t, VkPrivateDataSlot, uint64_t)

#pragma mark -
#pragma mark VK_KHR_bind_memory2 extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkBindBufferMemory2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkBindImageMemory2, KHR);


#pragma mark -
#pragma mark VK_KHR_buffer_device_address

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetBufferDeviceAddress, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetBufferOpaqueCaptureAddress, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetDeviceMemoryOpaqueCaptureAddress, KHR);


#pragma mark -
#pragma mark VK_KHR_copy_commands2 extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdBlitImage2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdCopyBuffer2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdCopyBufferToImage2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdCopyImage2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdCopyImageToBuffer2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdResolveImage2, KHR);


#pragma mark -
#pragma mark VK_KHR_create_renderpass2 extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCreateRenderPass2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdBeginRenderPass2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdNextSubpass2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdEndRenderPass2, KHR);


#pragma mark -
#pragma mark VK_KHR_dynamic_rendering extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdBeginRendering, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdEndRendering, KHR);


#pragma mark -
#pragma mark VK_KHR_descriptor_update_template extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCreateDescriptorUpdateTemplate, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkDestroyDescriptorUpdateTemplate, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkUpdateDescriptorSetWithTemplate, KHR);


#pragma mark -
#pragma mark VK_KHR_device_group extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetDeviceGroupPeerMemoryFeatures, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdSetDeviceMask, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdDispatchBase, KHR);


#pragma mark -
#pragma mark VK_KHR_device_group_creation extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkEnumeratePhysicalDeviceGroups, KHR);


#pragma mark -
#pragma mark VK_KHR_draw_indirect_count

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdDrawIndexedIndirectCount, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdDrawIndirectCount, KHR);


#pragma mark -
#pragma mark VK_KHR_external_fence_capabilities extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceExternalFenceProperties, KHR);


#pragma mark -
#pragma mark VK_KHR_external_memory_capabilities extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceExternalBufferProperties, KHR);


#pragma mark -
#pragma mark VK_KHR_external_semaphore_capabilities extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceExternalSemaphoreProperties, KHR);


#pragma mark -
#pragma mark VK_KHR_get_memory_requirements2 extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetBufferMemoryRequirements2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetImageMemoryRequirements2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetImageSparseMemoryRequirements2, KHR);


#pragma mark -
#pragma mark VK_KHR_get_physical_device_properties2 extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceFeatures2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceProperties2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceFormatProperties2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceImageFormatProperties2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceQueueFamilyProperties2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceMemoryProperties2, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetPhysicalDeviceSparseImageFormatProperties2, KHR);


#pragma mark -
#pragma mark VK_KHR_maintenance1 extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkTrimCommandPool, KHR);


#pragma mark -
#pragma mark VK_KHR_maintenance3 extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetDescriptorSetLayoutSupport, KHR);


#pragma mark -
#pragma mark VK_KHR_push_descriptor extension

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdPushDescriptorSetKHR(
    VkCommandBuffer                             commandBuffer,
    VkPipelineBindPoint                         pipelineBindPoint,
    VkPipelineLayout                            layout,
    uint32_t                                    set,
    uint32_t                                    descriptorWriteCount,
    const VkWriteDescriptorSet*                 pDescriptorWrites) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(PushDescriptorSet, commandBuffer, pipelineBindPoint, layout, set, descriptorWriteCount, pDescriptorWrites);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdPushDescriptorSetWithTemplateKHR(
    VkCommandBuffer                            commandBuffer,
    VkDescriptorUpdateTemplate              descriptorUpdateTemplate,
    VkPipelineLayout                           layout,
    uint32_t                                   set,
    const void*                                pData) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(PushDescriptorSetWithTemplate, commandBuffer, descriptorUpdateTemplate, layout, set, pData);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_KHR_sampler_ycbcr_conversion extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCreateSamplerYcbcrConversion, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkDestroySamplerYcbcrConversion, KHR);


#pragma mark -
#pragma mark VK_KHR_swapchain extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateSwapchainKHR(
    VkDevice                                 device,
    const VkSwapchainCreateInfoKHR*          pCreateInfo,
    const VkAllocationCallbacks*             pAllocator,
    VkSwapchainKHR*                          pSwapchain) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    VkResult rslt = mvkDev->getConfigurationResult();
    if (rslt == VK_SUCCESS) {
        MVKSwapchain* mvkSwpChn = mvkDev->createSwapchain(pCreateInfo, pAllocator);
        *pSwapchain = (VkSwapchainKHR)(mvkSwpChn);
        rslt = mvkSwpChn->getConfigurationResult();
        if (rslt < 0) { *pSwapchain = VK_NULL_HANDLE; mvkDev->destroySwapchain(mvkSwpChn, pAllocator); }
    }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroySwapchainKHR(
    VkDevice                                 device,
    VkSwapchainKHR                           swapchain,
    const VkAllocationCallbacks*             pAllocator) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroySwapchain((MVKSwapchain*)swapchain, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetSwapchainImagesKHR(
    VkDevice                                 device,
    VkSwapchainKHR                           swapchain,
    uint32_t*                                pCount,
    VkImage*                                 pSwapchainImages) {

	MVKTraceVulkanCallStart();
    MVKSwapchain* mvkSwapchain = (MVKSwapchain*)swapchain;
    VkResult rslt = mvkSwapchain->getImages(pCount, pSwapchainImages);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkAcquireNextImageKHR(
    VkDevice                                     device,
    VkSwapchainKHR                               swapchain,
    uint64_t                                     timeout,
    VkSemaphore                                  semaphore,
    VkFence                                      fence,
    uint32_t*                                    pImageIndex) {

	MVKTraceVulkanCallStart();
    MVKSwapchain* mvkSwapchain = (MVKSwapchain*)swapchain;
    VkResult rslt = mvkSwapchain->acquireNextImage(timeout, semaphore, fence, ~0u, pImageIndex);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkQueuePresentKHR(
    VkQueue                                      queue,
    const VkPresentInfoKHR*                      pPresentInfo) {

	MVKTraceVulkanCallStart();
    MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
    VkResult rslt = mvkQ->submit(pPresentInfo);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetDeviceGroupPresentCapabilitiesKHR(
	VkDevice                                    device,
	VkDeviceGroupPresentCapabilitiesKHR*        pDeviceGroupPresentCapabilities) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDevice = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkDevice->getDeviceGroupPresentCapabilities(pDeviceGroupPresentCapabilities);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetDeviceGroupSurfacePresentModesKHR(
	VkDevice                                    device,
	VkSurfaceKHR                                surface,
	VkDeviceGroupPresentModeFlagsKHR*           pModes) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDevice = MVKDevice::getMVKDevice(device);
	MVKSurface* mvkSrfc = (MVKSurface*)surface;
	VkResult rslt = mvkDevice->getDeviceGroupSurfacePresentModes(mvkSrfc, pModes);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDevicePresentRectanglesKHR(
	VkPhysicalDevice                            physicalDevice,
	VkSurfaceKHR                                surface,
	uint32_t*                                   pRectCount,
	VkRect2D*                                   pRects) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	MVKSurface* mvkSrfc = (MVKSurface*)surface;
	VkResult rslt = mvkPD->getPresentRectangles(mvkSrfc, pRectCount, pRects);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkAcquireNextImage2KHR(
	VkDevice                                    device,
	const VkAcquireNextImageInfoKHR*            pAcquireInfo,
	uint32_t*                                   pImageIndex) {

	MVKTraceVulkanCallStart();
	MVKSwapchain* mvkSwapchain = (MVKSwapchain*)pAcquireInfo->swapchain;
	VkResult rslt = mvkSwapchain->acquireNextImage(pAcquireInfo->timeout,
												   pAcquireInfo->semaphore,
												   pAcquireInfo->fence,
												   pAcquireInfo->deviceMask,
												   pImageIndex);
	MVKTraceVulkanCallEnd();
	return rslt;
}

#pragma mark -
#pragma mark VK_EXT_swapchain_maintenance1 extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkReleaseSwapchainImagesEXT(
	VkDevice                                    device,
	const VkReleaseSwapchainImagesInfoEXT*      pReleaseInfo) {

	MVKTraceVulkanCallStart();
	MVKSwapchain* mvkSwapchain = (MVKSwapchain*)pReleaseInfo->swapchain;
	VkResult rslt = mvkSwapchain->releaseImages(pReleaseInfo);
	MVKTraceVulkanCallEnd();
	return rslt;
}


#pragma mark -
#pragma mark VK_KHR_surface extension

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroySurfaceKHR(
    VkInstance                                   instance,
    VkSurfaceKHR                                 surface,
    const VkAllocationCallbacks*                 pAllocator) {

	MVKTraceVulkanCallStart();
    MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
    mvkInst->destroySurface((MVKSurface*)surface, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDeviceSurfaceSupportKHR(
    VkPhysicalDevice                            physicalDevice,
    uint32_t                                    queueFamilyIndex,
    VkSurfaceKHR                                surface,
    VkBool32*                                   pSupported) {

	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    MVKSurface* mvkSrfc = (MVKSurface*)surface;
    VkResult rslt = mvkPD->getSurfaceSupport(queueFamilyIndex, mvkSrfc, pSupported);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    VkPhysicalDevice                            physicalDevice,
    VkSurfaceKHR                                surface,
    VkSurfaceCapabilitiesKHR*                   pSurfaceCapabilities) {

	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    VkResult rslt = mvkPD->getSurfaceCapabilities(surface, pSurfaceCapabilities);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDeviceSurfaceFormatsKHR(
    VkPhysicalDevice                            physicalDevice,
    VkSurfaceKHR                                surface,
    uint32_t*                                   pSurfaceFormatCount,
    VkSurfaceFormatKHR*                         pSurfaceFormats) {

	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    MVKSurface* mvkSrfc = (MVKSurface*)surface;
    VkResult rslt = mvkPD->getSurfaceFormats(mvkSrfc, pSurfaceFormatCount, pSurfaceFormats);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDeviceSurfacePresentModesKHR(
    VkPhysicalDevice                            physicalDevice,
    VkSurfaceKHR                                surface,
    uint32_t*                                   pPresentModeCount,
    VkPresentModeKHR*                           pPresentModes) {

	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    MVKSurface* mvkSrfc = (MVKSurface*)surface;
    VkResult rslt = mvkPD->getSurfacePresentModes(mvkSrfc, pPresentModeCount, pPresentModes);
	MVKTraceVulkanCallEnd();
	return rslt;
}


#pragma mark -
#pragma mark VK_KHR_get_surface_capabilities2 extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDeviceSurfaceCapabilities2KHR(
	VkPhysicalDevice                            physicalDevice,
	const VkPhysicalDeviceSurfaceInfo2KHR*      pSurfaceInfo,
	VkSurfaceCapabilities2KHR*                  pSurfaceCapabilities) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	VkResult rslt = mvkPD->getSurfaceCapabilities(pSurfaceInfo, pSurfaceCapabilities);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDeviceSurfaceFormats2KHR(
	VkPhysicalDevice                            physicalDevice,
	const VkPhysicalDeviceSurfaceInfo2KHR*      pSurfaceInfo,
	uint32_t*                                   pSurfaceFormatCount,
	VkSurfaceFormat2KHR*                        pSurfaceFormats) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	MVKSurface* mvkSrfc = (MVKSurface*)pSurfaceInfo->surface;
	VkResult rslt = mvkPD->getSurfaceFormats(mvkSrfc, pSurfaceFormatCount, pSurfaceFormats);
	MVKTraceVulkanCallEnd();
	return rslt;
}


#pragma mark -
#pragma mark VK_KHR_timeline_semaphore

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetSemaphoreCounterValue, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkSignalSemaphore, KHR);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkWaitSemaphores, KHR);


#pragma mark -
#pragma mark VK_EXT_buffer_device_address extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkGetBufferDeviceAddress, EXT);


#pragma mark -
#pragma mark VK_EXT_debug_report extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateDebugReportCallbackEXT(
	VkInstance                                  instance,
	const VkDebugReportCallbackCreateInfoEXT*   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkDebugReportCallbackEXT*                   pCallback) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	MVKDebugReportCallback* mvkDRCB = mvkInst->createDebugReportCallback(pCreateInfo, pAllocator);
	*pCallback = (VkDebugReportCallbackEXT)mvkDRCB;
	VkResult rslt = mvkDRCB->getConfigurationResult();
    if (rslt < 0) { *pCallback = VK_NULL_HANDLE; mvkInst->destroyDebugReportCallback(mvkDRCB, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyDebugReportCallbackEXT(
	VkInstance                                  instance,
	VkDebugReportCallbackEXT                    callback,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	mvkInst->destroyDebugReportCallback((MVKDebugReportCallback*)callback, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDebugReportMessageEXT(
	VkInstance                                  instance,
	VkDebugReportFlagsEXT                       flags,
	VkDebugReportObjectTypeEXT                  objectType,
	uint64_t                                    object,
	size_t                                      location,
	int32_t                                     messageCode,
	const char*                                 pLayerPrefix,
	const char*                                 pMessage) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	mvkInst->debugReportMessage(flags, objectType, object, location, messageCode, pLayerPrefix, pMessage);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_EXT_debug_marker extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkDebugMarkerSetObjectTagEXT(
	VkDevice                                    device,
	const VkDebugMarkerObjectTagInfoEXT*        pTagInfo) {

	MVKTraceVulkanCallStart();
	VkResult rslt = VK_SUCCESS;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkDebugMarkerSetObjectNameEXT(
	VkDevice                                    device,
	const VkDebugMarkerObjectNameInfoEXT*       pNameInfo) {

	MVKTraceVulkanCallStart();
	MVKVulkanAPIObject* mvkObj = MVKVulkanAPIObject::getMVKVulkanAPIObject(pNameInfo->objectType, pNameInfo->object);
	VkResult rslt = mvkObj ? mvkObj->setDebugName(pNameInfo->pObjectName) : VK_SUCCESS;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDebugMarkerBeginEXT(
	VkCommandBuffer                             commandBuffer,
	const VkDebugMarkerMarkerInfoEXT*           pMarkerInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerBegin, commandBuffer, pMarkerInfo->pMarkerName, pMarkerInfo->color);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDebugMarkerEndEXT(
	VkCommandBuffer                             commandBuffer) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerEnd, commandBuffer);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdDebugMarkerInsertEXT(
	VkCommandBuffer                             commandBuffer,
	const VkDebugMarkerMarkerInfoEXT*           pMarkerInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerInsert, commandBuffer, pMarkerInfo->pMarkerName, pMarkerInfo->color);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_EXT_debug_utils extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkSetDebugUtilsObjectNameEXT(
	VkDevice                                    device,
	const VkDebugUtilsObjectNameInfoEXT*        pNameInfo) {

	MVKTraceVulkanCallStart();
	MVKVulkanAPIObject* mvkObj = MVKVulkanAPIObject::getMVKVulkanAPIObject(pNameInfo->objectType, pNameInfo->objectHandle);
	VkResult rslt = mvkObj ? mvkObj->setDebugName(pNameInfo->pObjectName) : VK_SUCCESS;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkSetDebugUtilsObjectTagEXT(
	VkDevice                                    device,
	const VkDebugUtilsObjectTagInfoEXT*         pTagInfo) {

	MVKTraceVulkanCallStart();
	VkResult rslt = VK_SUCCESS;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkQueueBeginDebugUtilsLabelEXT(
	VkQueue                                     queue,
	const VkDebugUtilsLabelEXT*                 pLabelInfo) {

	MVKTraceVulkanCallStart();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkQueueEndDebugUtilsLabelEXT(
	VkQueue                                     queue) {

	MVKTraceVulkanCallStart();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkQueueInsertDebugUtilsLabelEXT(
	VkQueue                                     queue,
	const VkDebugUtilsLabelEXT*                 pLabelInfo) {

	MVKTraceVulkanCallStart();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdBeginDebugUtilsLabelEXT(
	VkCommandBuffer                             commandBuffer,
	const VkDebugUtilsLabelEXT*                 pLabelInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerBegin, commandBuffer, pLabelInfo->pLabelName, pLabelInfo->color);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdEndDebugUtilsLabelEXT(
	VkCommandBuffer                             commandBuffer) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerEnd, commandBuffer);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkCmdInsertDebugUtilsLabelEXT(
	VkCommandBuffer                             commandBuffer,
	const VkDebugUtilsLabelEXT*                 pLabelInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerInsert, commandBuffer, pLabelInfo->pLabelName, pLabelInfo->color);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateDebugUtilsMessengerEXT(
	VkInstance                                  instance,
	const VkDebugUtilsMessengerCreateInfoEXT*   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkDebugUtilsMessengerEXT*                   pMessenger) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	MVKDebugUtilsMessenger* mvkDUM = mvkInst->createDebugUtilsMessenger(pCreateInfo, pAllocator);
	*pMessenger = (VkDebugUtilsMessengerEXT)mvkDUM;
	VkResult rslt = mvkDUM->getConfigurationResult();
    if (rslt < 0) { *pMessenger = VK_NULL_HANDLE; mvkInst->destroyDebugUtilsMessenger(mvkDUM, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyDebugUtilsMessengerEXT(
	VkInstance                                  instance,
	VkDebugUtilsMessengerEXT                    messenger,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	mvkInst->destroyDebugUtilsMessenger((MVKDebugUtilsMessenger*)messenger, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkSubmitDebugUtilsMessageEXT(
	VkInstance                                  instance,
	VkDebugUtilsMessageSeverityFlagBitsEXT      messageSeverity,
	VkDebugUtilsMessageTypeFlagsEXT             messageTypes,
	const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	mvkInst->debugUtilsMessage(messageSeverity, messageTypes, pCallbackData);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_EXT_external_memory_host extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetMemoryHostPointerPropertiesEXT(
	VkDevice                                    device,
	VkExternalMemoryHandleTypeFlagBits          handleType,
	const void*                                 pHostPointer,
	VkMemoryHostPointerPropertiesEXT*           pMemoryHostPointerProperties) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDvc = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkDvc->getMemoryHostPointerProperties(handleType, pHostPointer, pMemoryHostPointerProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}


#pragma mark -
#pragma mark VK_EXT_hdr_metadata extension

MVK_PUBLIC_VULKAN_SYMBOL void vkSetHdrMetadataEXT(
	VkDevice                                    device,
	uint32_t                                    swapchainCount,
	const VkSwapchainKHR*                       pSwapchains,
	const VkHdrMetadataEXT*                     pMetadata) {

	MVKTraceVulkanCallStart();
	for (uint32_t i = 0; i < swapchainCount; i++) {
		auto* mvkSwpChn = (MVKSwapchain*)pSwapchains[i];
		mvkSwpChn->setHDRMetadataEXT(pMetadata[i]);
	}
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_EXT_host_query_reset extension

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkResetQueryPool, EXT);


#pragma mark -
#pragma mark VK_EXT_metal_surface extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreateMetalSurfaceEXT(
	VkInstance                                  instance,
	const VkMetalSurfaceCreateInfoEXT*          pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkSurfaceKHR*                               pSurface) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	MVKSurface* mvkSrfc = mvkInst->createSurface(pCreateInfo, pAllocator);
	*pSurface = (VkSurfaceKHR)mvkSrfc;
	VkResult rslt = mvkSrfc->getConfigurationResult();
    if (rslt < 0) { *pSurface = VK_NULL_HANDLE; mvkInst->destroySurface(mvkSrfc, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}


#pragma mark -
#pragma mark VK_EXT_metal_objects extension

MVK_PUBLIC_VULKAN_SYMBOL void vkExportMetalObjectsEXT(
	VkDevice                                    device,
	VkExportMetalObjectsInfoEXT*                pMetalObjectsInfo) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDvc = MVKDevice::getMVKDevice(device);
	mvkDvc->getMetalObjects(pMetalObjectsInfo);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_EXT_private_data extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreatePrivateDataSlotEXT(
	VkDevice                                    device,
	const VkPrivateDataSlotCreateInfoEXT*       pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkPrivateDataSlotEXT*                       pPrivateDataSlot) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkDev->createPrivateDataSlot(pCreateInfo, pAllocator, pPrivateDataSlot);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkDestroyPrivateDataSlotEXT(
	VkDevice                                    device,
	VkPrivateDataSlotEXT                        privateDataSlot,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyPrivateDataSlot(privateDataSlot, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkSetPrivateDataEXT(
	VkDevice                                    device,
	VkObjectType                                objectType,
	uint64_t                                    objectHandle,
	VkPrivateDataSlotEXT                        privateDataSlot,
	uint64_t                                    data) {

	MVKTraceVulkanCallStart();
	MVKPrivateDataSlot* mvkPDS = (MVKPrivateDataSlot*)privateDataSlot;
	mvkPDS->setData(objectType, objectHandle, data);
	MVKTraceVulkanCallEnd();
	return VK_SUCCESS;
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetPrivateDataEXT(
	VkDevice                                    device,
	VkObjectType                                objectType,
	uint64_t                                    objectHandle,
	VkPrivateDataSlotEXT                        privateDataSlot,
	uint64_t*                                   pData) {

	MVKTraceVulkanCallStart();
	MVKPrivateDataSlot* mvkPDS = (MVKPrivateDataSlot*)privateDataSlot;
	*pData = mvkPDS->getData(objectType, objectHandle);
	MVKTraceVulkanCallEnd();
}

#pragma mark -
#pragma mark VK_EXT_sample_locations extension

void vkGetPhysicalDeviceMultisamplePropertiesEXT(
	VkPhysicalDevice                            physicalDevice,
	VkSampleCountFlagBits                       samples,
	VkMultisamplePropertiesEXT*                 pMultisampleProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getMultisampleProperties(samples, pMultisampleProperties);
	MVKTraceVulkanCallEnd();
}

void vkCmdSetSampleLocationsEXT(
	VkCommandBuffer                             commandBuffer,
	const VkSampleLocationsInfoEXT*             pSampleLocationsInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(SetSampleLocations, commandBuffer, pSampleLocationsInfo);
	MVKTraceVulkanCallEnd();
}

#pragma mark -
#pragma mark VK_GOOGLE_display_timing extension

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetRefreshCycleDurationGOOGLE(
	VkDevice                                    device,
	VkSwapchainKHR                              swapchain,
	VkRefreshCycleDurationGOOGLE*               pDisplayTimingProperties) {

	MVKTraceVulkanCallStart();
	MVKSwapchain* mvkSwapchain = (MVKSwapchain*)swapchain;
	VkResult rslt = mvkSwapchain->getRefreshCycleDuration(pDisplayTimingProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPastPresentationTimingGOOGLE(
	VkDevice                                    device,
	VkSwapchainKHR                              swapchain,
	uint32_t*                                   pPresentationTimingCount,
	VkPastPresentationTimingGOOGLE*             pPresentationTimings) {

	MVKTraceVulkanCallStart();
	MVKSwapchain* mvkSwapchain = (MVKSwapchain*)swapchain;
	VkResult rslt = mvkSwapchain->getPastPresentationTiming(pPresentationTimingCount, pPresentationTimings);
	MVKTraceVulkanCallEnd();
	return rslt;
}

#pragma mark -
#pragma mark VK_AMD_draw_indirect_count

MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdDrawIndexedIndirectCount, AMD);
MVK_PUBLIC_VULKAN_CORE_ALIAS(vkCmdDrawIndirectCount, AMD);

#pragma mark -
#pragma mark iOS & macOS surface extensions

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkCreate_PLATFORM_SurfaceMVK(
    VkInstance                                  instance,
    const Vk_PLATFORM_SurfaceCreateInfoMVK*		pCreateInfo,
    const VkAllocationCallbacks*                pAllocator,
    VkSurfaceKHR*                               pSurface) {

	MVKTraceVulkanCallStart();
    MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
    MVKSurface* mvkSrfc = mvkInst->createSurface(pCreateInfo, pAllocator);
    *pSurface = (VkSurfaceKHR)mvkSrfc;
    VkResult rslt = mvkSrfc->getConfigurationResult();
    if (rslt < 0) { *pSurface = VK_NULL_HANDLE; mvkInst->destroySurface(mvkSrfc, pAllocator); }
	MVKTraceVulkanCallEnd();
	return rslt;
}


#pragma mark -
#pragma mark Loader and Layer ICD interface extension

#ifdef __cplusplus
extern "C" {
#endif    //  __cplusplus

	VKAPI_ATTR VkResult VKAPI_CALL vk_icdNegotiateLoaderICDInterfaceVersion(uint32_t* pSupportedVersion);
	VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vk_icdGetInstanceProcAddr(VkInstance instance, const char* name);
	VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vk_icdGetPhysicalDeviceProcAddr(VkInstance instance, const char* name);

#ifdef __cplusplus
}
#endif    //  __cplusplus


MVK_PUBLIC_SYMBOL VkResult vk_icdNegotiateLoaderICDInterfaceVersion(
	uint32_t*                                   pSupportedVersion) {

	MVKTraceVulkanCallStart();

	// This ICD expects to be loaded by a loader of at least version 5.
	VkResult rslt = VK_SUCCESS;
	if (pSupportedVersion && *pSupportedVersion >= 5) {
		*pSupportedVersion = 5;
	} else {
		rslt = VK_ERROR_INCOMPATIBLE_DRIVER;
	}
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL PFN_vkVoidFunction vk_icdGetInstanceProcAddr(
	VkInstance                                  instance,
	const char*                                 pName) {

	MVKTraceVulkanCallStart();

	PFN_vkVoidFunction func = nullptr;
	if (mvkStringsAreEqual(pName, "vk_icdNegotiateLoaderICDInterfaceVersion")) {
		func = (PFN_vkVoidFunction)vk_icdNegotiateLoaderICDInterfaceVersion;
	} else if (mvkStringsAreEqual(pName, "vk_icdGetPhysicalDeviceProcAddr")) {
		func = (PFN_vkVoidFunction)vk_icdGetPhysicalDeviceProcAddr;
	} else {
		func = vkGetInstanceProcAddr(instance, pName);
	}
	MVKTraceVulkanCallEnd();
	return func;
}

MVK_PUBLIC_SYMBOL PFN_vkVoidFunction vk_icdGetPhysicalDeviceProcAddr(
	VkInstance                                  instance,
	const char*                                 pName) {

	MVKTraceVulkanCallStart();
	PFN_vkVoidFunction func = vk_icdGetInstanceProcAddr(instance, pName);
	MVKTraceVulkanCallEnd();
	return func;
}

