/*
 * vulkan.mm
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
#include "MVKLogging.h"

#include <pthread.h>


#pragma mark -
#pragma mark Vulkan call templates

typedef enum {
	MVKVulkanCallTraceLevelNone = 0,
	MVKVulkanCallTraceLevelFunctionName = 1,
	MVKVulkanCallTraceLevelFunctionScope = 2,
	MVKVulkanCallTraceLevelFunctionTime = 3,
	MVKVulkanCallTraceLevelFunctionMax
} MVKVulkanCallTraceLevel;

#ifndef MVK_CONFIG_TRACE_VULKAN_CALLS
#   define MVK_CONFIG_TRACE_VULKAN_CALLS    MVKVulkanCallTraceLevelNone
#endif

static uint32_t _mvkTraceVulkanCalls = MVK_CONFIG_TRACE_VULKAN_CALLS;
static bool _mvkVulkanCallTracingInitialized = false;

// Returns Vulkan call trace level from environment variable.
// We do this once lazily instead of in a library constructor function to
// ensure the NSProcessInfo environment is available when called upon.
static inline uint32_t getCallTraceLevel() {
	if ( !_mvkVulkanCallTracingInitialized ) {
		_mvkVulkanCallTracingInitialized = true;
		MVK_SET_FROM_ENV_OR_BUILD_INT32(_mvkTraceVulkanCalls, MVK_CONFIG_TRACE_VULKAN_CALLS);
	}
	return _mvkTraceVulkanCalls;
}

// Optionally log start of function calls to stderr
static inline uint64_t MVKTraceVulkanCallStartImpl(const char* funcName) {
	uint32_t traceLvl = getCallTraceLevel();

	if (traceLvl == MVKVulkanCallTraceLevelNone ||
		traceLvl >= MVKVulkanCallTraceLevelFunctionMax) { return 0; }

	uint64_t gtid, mtid;
	const uint32_t kThreadNameBuffSize = 256;
	char threadName[kThreadNameBuffSize];
	pthread_t tid = pthread_self();
	mtid = pthread_mach_thread_np(tid);		// Mach thread ID
	pthread_threadid_np(tid, &gtid);		// Global system-wide thead ID
	pthread_getname_np(tid, threadName, kThreadNameBuffSize);

	fprintf(stderr, "[mvk-trace] %s()%s [%llu/%llu/%s]\n",
			funcName, (traceLvl >= MVKVulkanCallTraceLevelFunctionScope) ? " {" : "",
			mtid, gtid, threadName);

	return (traceLvl >= MVKVulkanCallTraceLevelFunctionTime) ? mvkGetTimestamp() : 0;
}

// Optionally log end of function calls and timings to stderr
static inline void MVKTraceVulkanCallEndImpl(const char* funcName, uint64_t startTime) {
	switch(getCallTraceLevel()) {
		case MVKVulkanCallTraceLevelFunctionTime:
			fprintf(stderr, "[mvk-trace] } %s [%.4f ms]\n", funcName, mvkGetElapsedMilliseconds(startTime));
			break;
		case MVKVulkanCallTraceLevelFunctionScope:
			fprintf(stderr, "[mvk-trace] } %s\n", funcName);
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


#pragma mark -
#pragma mark Vulkan calls

MVK_PUBLIC_SYMBOL VkResult vkCreateInstance(
    const VkInstanceCreateInfo*                 pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkInstance*                                 pInstance) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = new MVKInstance(pCreateInfo);
	*pInstance = mvkInst->getVkInstance();
	VkResult rslt = mvkInst->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyInstance(
    VkInstance                                  instance,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	if (instance) { MVKInstance::getMVKInstance(instance)->destroy(); }
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkEnumeratePhysicalDevices(
    VkInstance                                  instance,
    uint32_t*                                   pPhysicalDeviceCount,
    VkPhysicalDevice*                           pPhysicalDevices) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	VkResult rslt = mvkInst->getPhysicalDevices(pPhysicalDeviceCount, pPhysicalDevices);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceFeatures(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceFeatures*                   pFeatures) {
	
	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getFeatures(pFeatures);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceFormatProperties(
    VkPhysicalDevice                            physicalDevice,
    VkFormat                                    format,
    VkFormatProperties*                         pFormatProperties) {
	
	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getFormatProperties(format, pFormatProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceImageFormatProperties(
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

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceProperties(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceProperties*                 pProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getProperties(pProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceQueueFamilyProperties(
	VkPhysicalDevice                            physicalDevice,
	uint32_t*                                   pQueueFamilyPropertyCount,
	VkQueueFamilyProperties*                    pQueueFamilyProperties) {
	
	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getQueueFamilyProperties(pQueueFamilyPropertyCount, pQueueFamilyProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceMemoryProperties(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceMemoryProperties*           pMemoryProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getMemoryProperties(pMemoryProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL PFN_vkVoidFunction vkGetInstanceProcAddr(
    VkInstance                                  instance,
    const char*                                 pName) {

	MVKTraceVulkanCallStart();

	// Handle the special platform functions where the instance parameter may be NULL.
	PFN_vkVoidFunction func = nullptr;
	if (strcmp(pName, "vkCreateInstance") == 0) {
		func = (PFN_vkVoidFunction)vkCreateInstance;
	} else if (strcmp(pName, "vkEnumerateInstanceExtensionProperties") == 0) {
		func = (PFN_vkVoidFunction)vkEnumerateInstanceExtensionProperties;
	} else if (strcmp(pName, "vkEnumerateInstanceLayerProperties") == 0) {
		func = (PFN_vkVoidFunction)vkEnumerateInstanceLayerProperties;
	} else if (instance) {
		MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
		func = mvkInst->getProcAddr(pName);
	}
	MVKTraceVulkanCallEnd();
	return func;
}

MVK_PUBLIC_SYMBOL PFN_vkVoidFunction vkGetDeviceProcAddr(
    VkDevice                                    device,
    const char*                                 pName) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	PFN_vkVoidFunction func = mvkDev->getProcAddr(pName);
	MVKTraceVulkanCallEnd();
	return func;
}

MVK_PUBLIC_SYMBOL VkResult vkCreateDevice(
    VkPhysicalDevice                            physicalDevice,
    const VkDeviceCreateInfo*                   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkDevice*                                   pDevice) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	MVKDevice* mvkDev = new MVKDevice(mvkPD, pCreateInfo);
	*pDevice = mvkDev->getVkDevice();
	VkResult rslt = mvkDev->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyDevice(
	VkDevice                                    device,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	if (device) { MVKDevice::getMVKDevice(device)->destroy(); }
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkEnumerateInstanceExtensionProperties(
    const char*                                 pLayerName,
    uint32_t*                                   pCount,
    VkExtensionProperties*                      pProperties) {

	MVKTraceVulkanCallStart();
	VkResult rslt = MVKLayerManager::globalManager()->getLayerNamed(pLayerName)->getInstanceExtensionProperties(pCount, pProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkEnumerateDeviceExtensionProperties(
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

MVK_PUBLIC_SYMBOL VkResult vkEnumerateInstanceLayerProperties(
    uint32_t*                                   pCount,
    VkLayerProperties*                          pProperties) {

	MVKTraceVulkanCallStart();
	VkResult rslt = MVKLayerManager::globalManager()->getLayerProperties(pCount, pProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkEnumerateDeviceLayerProperties(
    VkPhysicalDevice                            physicalDevice,
    uint32_t*                                   pCount,
    VkLayerProperties*                          pProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	VkResult rslt = mvkPD->getInstance()->getLayerManager()->getLayerProperties(pCount, pProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkGetDeviceQueue(
    VkDevice                                    device,
    uint32_t                                    queueFamilyIndex,
    uint32_t                                    queueIndex,
    VkQueue*                                    pQueue) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	*pQueue = mvkDev->getQueue(queueFamilyIndex, queueIndex)->getVkQueue();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkQueueSubmit(
	VkQueue                                     queue,
	uint32_t                                    submitCount,
	const VkSubmitInfo*                         pSubmits,
	VkFence                                     fence) {

	MVKTraceVulkanCallStart();
	MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
	VkResult rslt = mvkQ->submit(submitCount, pSubmits, fence);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkQueueWaitIdle(
    VkQueue                                     queue) {
	
	MVKTraceVulkanCallStart();
	MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
	VkResult rslt = mvkQ->waitIdle();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkDeviceWaitIdle(
    VkDevice                                    device) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkDev->waitIdle();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkAllocateMemory(
    VkDevice                                    device,
    const VkMemoryAllocateInfo*                 pAllocateInfo,
    const VkAllocationCallbacks*                pAllocator,
    VkDeviceMemory*                             pMem) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKDeviceMemory* mvkMem = mvkDev->allocateMemory(pAllocateInfo, pAllocator);
	VkResult rslt = mvkMem->getConfigurationResult();
	*pMem = (VkDeviceMemory)((rslt == VK_SUCCESS) ? mvkMem : VK_NULL_HANDLE);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkFreeMemory(
    VkDevice                                    device,
	VkDeviceMemory                              mem,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->freeMemory((MVKDeviceMemory*)mem, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkMapMemory(
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

MVK_PUBLIC_SYMBOL void vkUnmapMemory(
    VkDevice                                    device,
    VkDeviceMemory                              mem) {
	
	MVKTraceVulkanCallStart();
	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	mvkMem->unmap();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkFlushMappedMemoryRanges(
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

MVK_PUBLIC_SYMBOL VkResult vkInvalidateMappedMemoryRanges(
    VkDevice                                    device,
    uint32_t                                    memRangeCount,
    const VkMappedMemoryRange*                  pMemRanges) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkDev->invalidateMappedMemoryRanges(memRangeCount, pMemRanges);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkGetDeviceMemoryCommitment(
    VkDevice                                    device,
    VkDeviceMemory                              memory,
    VkDeviceSize*                               pCommittedMemoryInBytes) {

	MVKTraceVulkanCallStart();
    MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)memory;
    *pCommittedMemoryInBytes = mvkMem->getDeviceMemoryCommitment();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkBindBufferMemory(
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

MVK_PUBLIC_SYMBOL VkResult vkBindImageMemory(
    VkDevice                                    device,
    VkImage                                     image,
    VkDeviceMemory                              mem,
    VkDeviceSize                                memOffset) {
	
	MVKTraceVulkanCallStart();
	MVKImage* mvkImg = (MVKImage*)image;
	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	VkResult rslt = mvkImg->bindDeviceMemory(mvkMem, memOffset);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkGetBufferMemoryRequirements(
    VkDevice                                    device,
    VkBuffer                                    buffer,
    VkMemoryRequirements*                       pMemoryRequirements) {
	
	MVKTraceVulkanCallStart();
	MVKBuffer* mvkBuff = (MVKBuffer*)buffer;
	mvkBuff->getMemoryRequirements(pMemoryRequirements);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetImageMemoryRequirements(
    VkDevice                                    device,
    VkImage                                     image,
    VkMemoryRequirements*                       pMemoryRequirements) {
	
	MVKTraceVulkanCallStart();
	MVKImage* mvkImg = (MVKImage*)image;
	mvkImg->getMemoryRequirements(pMemoryRequirements);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetImageSparseMemoryRequirements(
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

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceSparseImageFormatProperties(
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

MVK_PUBLIC_SYMBOL VkResult vkQueueBindSparse(
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

MVK_PUBLIC_SYMBOL VkResult vkCreateFence(
    VkDevice                                    device,
    const VkFenceCreateInfo*                    pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkFence*                                    pFence) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKFence* mvkFence = mvkDev->createFence(pCreateInfo, pAllocator);
	*pFence = (VkFence)mvkFence;
	VkResult rslt = mvkFence->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyFence(
    VkDevice                                    device,
	VkFence                                     fence,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyFence((MVKFence*)fence, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkResetFences(
    VkDevice                                    device,
    uint32_t                                    fenceCount,
    const VkFence*                              pFences) {
	
	MVKTraceVulkanCallStart();
	VkResult rslt = mvkResetFences(fenceCount, pFences);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkGetFenceStatus(
    VkDevice                                    device,
    VkFence                                     fence) {
	
	MVKTraceVulkanCallStart();
	MVKFence* mvkFence = (MVKFence*)fence;
	VkResult rslt = mvkFence->getIsSignaled() ? VK_SUCCESS : VK_NOT_READY;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkWaitForFences(
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

MVK_PUBLIC_SYMBOL VkResult vkCreateSemaphore(
    VkDevice                                    device,
    const VkSemaphoreCreateInfo*                pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkSemaphore*                                pSemaphore) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKSemaphore* mvkSem4 = mvkDev->createSemaphore(pCreateInfo, pAllocator);
	*pSemaphore = (VkSemaphore)mvkSem4;
	VkResult rslt = mvkSem4->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroySemaphore(
    VkDevice                                    device,
	VkSemaphore                                 semaphore,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroySemaphore((MVKSemaphore*)semaphore, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateEvent(
    VkDevice                                    device,
    const VkEventCreateInfo*                    pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkEvent*                                    pEvent) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKEvent* mvkEvent = mvkDev->createEvent(pCreateInfo, pAllocator);
	*pEvent = (VkEvent)mvkEvent;
	VkResult rslt = mvkEvent->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyEvent(
    VkDevice                                    device,
	VkEvent                                     event,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyEvent((MVKEvent*)event, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkGetEventStatus(
    VkDevice                                    device,
    VkEvent                                     event) {
	
	MVKTraceVulkanCallStart();
	MVKEvent* mvkEvent = (MVKEvent*)event;
	VkResult rslt = mvkEvent->isSet() ? VK_EVENT_SET : VK_EVENT_RESET;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkSetEvent(
    VkDevice                                    device,
    VkEvent                                     event) {
	
	MVKTraceVulkanCallStart();
	MVKEvent* mvkEvent = (MVKEvent*)event;
	mvkEvent->signal(true);
	MVKTraceVulkanCallEnd();
	return VK_SUCCESS;
}

MVK_PUBLIC_SYMBOL VkResult vkResetEvent(
    VkDevice                                    device,
    VkEvent                                     event) {
	
	MVKTraceVulkanCallStart();
	MVKEvent* mvkEvent = (MVKEvent*)event;
	mvkEvent->signal(false);
	MVKTraceVulkanCallEnd();
	return VK_SUCCESS;
}

MVK_PUBLIC_SYMBOL VkResult vkCreateQueryPool(
    VkDevice                                    device,
    const VkQueryPoolCreateInfo*                pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkQueryPool*                                pQueryPool) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKQueryPool* mvkQP = mvkDev->createQueryPool(pCreateInfo, pAllocator);
	*pQueryPool = (VkQueryPool)mvkQP;
	VkResult rslt = mvkQP->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyQueryPool(
    VkDevice                                    device,
	VkQueryPool                                 queryPool,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyQueryPool((MVKQueryPool*)queryPool, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkGetQueryPoolResults(
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

MVK_PUBLIC_SYMBOL VkResult vkCreateBuffer(
    VkDevice                                    device,
    const VkBufferCreateInfo*                   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkBuffer*                                   pBuffer) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKBuffer* mvkBuff = mvkDev->createBuffer(pCreateInfo, pAllocator);
	*pBuffer = (VkBuffer)mvkBuff;
	VkResult rslt = mvkBuff->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyBuffer(
    VkDevice                                    device,
	VkBuffer                                    buffer,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyBuffer((MVKBuffer*)buffer, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateBufferView(
    VkDevice                                    device,
    const VkBufferViewCreateInfo*               pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkBufferView*                               pView) {
	
	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    MVKBufferView* mvkBuffView = mvkDev->createBufferView(pCreateInfo, pAllocator);
    *pView = (VkBufferView)mvkBuffView;
    VkResult rslt = mvkBuffView->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyBufferView(
    VkDevice                                    device,
	VkBufferView                                bufferView,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroyBufferView((MVKBufferView*)bufferView, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateImage(
    VkDevice                                    device,
    const VkImageCreateInfo*                    pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkImage*                                    pImage) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKImage* mvkImg = mvkDev->createImage(pCreateInfo, pAllocator);
	*pImage = (VkImage)mvkImg;
	VkResult rslt = mvkImg->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyImage(
    VkDevice                                    device,
	VkImage                                     image,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyImage((MVKImage*)image, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetImageSubresourceLayout(
    VkDevice                                    device,
    VkImage                                     image,
    const VkImageSubresource*                   pSubresource,
    VkSubresourceLayout*                        pLayout) {

	MVKTraceVulkanCallStart();
	MVKImage* mvkImg = (MVKImage*)image;
	mvkImg->getSubresourceLayout(pSubresource, pLayout);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateImageView(
    VkDevice                                    device,
    const VkImageViewCreateInfo*                pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkImageView*                                pView) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKImageView* mvkImgView = mvkDev->createImageView(pCreateInfo, pAllocator);
	*pView = (VkImageView)mvkImgView;
	VkResult rslt = mvkImgView->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyImageView(
    VkDevice                                    device,
	VkImageView                                 imageView,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyImageView((MVKImageView*)imageView, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateShaderModule(
    VkDevice                                    device,
    const VkShaderModuleCreateInfo*             pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkShaderModule*                             pShaderModule) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKShaderModule* mvkShdrMod = mvkDev->createShaderModule(pCreateInfo, pAllocator);
	*pShaderModule = (VkShaderModule)mvkShdrMod;
	VkResult rslt = mvkShdrMod->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyShaderModule(
    VkDevice                                    device,
	VkShaderModule                              shaderModule,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyShaderModule((MVKShaderModule*)shaderModule, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreatePipelineCache(
    VkDevice                                    device,
    const VkPipelineCacheCreateInfo*            pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkPipelineCache*                            pPipelineCache) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKPipelineCache* mvkPLC = mvkDev->createPipelineCache(pCreateInfo, pAllocator);
	*pPipelineCache = (VkPipelineCache)mvkPLC;
	VkResult rslt = mvkPLC->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyPipelineCache(
    VkDevice                                    device,
	VkPipelineCache                             pipelineCache,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyPipelineCache((MVKPipelineCache*)pipelineCache, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkGetPipelineCacheData(
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

MVK_PUBLIC_SYMBOL VkResult vkMergePipelineCaches(
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

MVK_PUBLIC_SYMBOL VkResult vkCreateGraphicsPipelines(
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

MVK_PUBLIC_SYMBOL VkResult vkCreateComputePipelines(
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

MVK_PUBLIC_SYMBOL void vkDestroyPipeline(
    VkDevice                                    device,
	VkPipeline                                  pipeline,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroyPipeline((MVKPipeline*)pipeline, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreatePipelineLayout(
    VkDevice                                    device,
    const VkPipelineLayoutCreateInfo*           pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkPipelineLayout*                           pPipelineLayout) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKPipelineLayout* mvkPLL = mvkDev->createPipelineLayout(pCreateInfo, pAllocator);
	*pPipelineLayout = (VkPipelineLayout)mvkPLL;
	VkResult rslt = mvkPLL->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyPipelineLayout(
    VkDevice                                    device,
	VkPipelineLayout                            pipelineLayout,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyPipelineLayout((MVKPipelineLayout*)pipelineLayout, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateSampler(
    VkDevice                                    device,
    const VkSamplerCreateInfo*                  pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkSampler*                                  pSampler) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKSampler* mvkSamp = mvkDev->createSampler(pCreateInfo, pAllocator);
	*pSampler = (VkSampler)mvkSamp;
	VkResult rslt = mvkSamp->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroySampler(
    VkDevice                                    device,
	VkSampler                                   sampler,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroySampler((MVKSampler*)sampler, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateDescriptorSetLayout(
    VkDevice                                    device,
    const VkDescriptorSetLayoutCreateInfo*      pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkDescriptorSetLayout*                      pSetLayout) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKDescriptorSetLayout* mvkDSL = mvkDev->createDescriptorSetLayout(pCreateInfo, pAllocator);
	*pSetLayout = (VkDescriptorSetLayout)mvkDSL;
	VkResult rslt = mvkDSL->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyDescriptorSetLayout(
    VkDevice                                    device,
	VkDescriptorSetLayout                       descriptorSetLayout,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyDescriptorSetLayout((MVKDescriptorSetLayout*)descriptorSetLayout, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateDescriptorPool(
    VkDevice                                    device,
    const VkDescriptorPoolCreateInfo*           pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkDescriptorPool*                           pDescriptorPool) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKDescriptorPool* mvkDP = mvkDev->createDescriptorPool(pCreateInfo, pAllocator);
	*pDescriptorPool = (VkDescriptorPool)mvkDP;
	VkResult rslt = mvkDP->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyDescriptorPool(
    VkDevice                                    device,
	VkDescriptorPool                            descriptorPool,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyDescriptorPool((MVKDescriptorPool*)descriptorPool, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkResetDescriptorPool(
	VkDevice                                    device,
	VkDescriptorPool                            descriptorPool,
	VkDescriptorPoolResetFlags                  flags) {

	MVKTraceVulkanCallStart();
	MVKDescriptorPool* mvkDP = (MVKDescriptorPool*)descriptorPool;
	VkResult rslt = mvkDP->reset(flags);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkAllocateDescriptorSets(
	VkDevice                                    device,
	const VkDescriptorSetAllocateInfo*          pAllocateInfo,
	VkDescriptorSet*                            pDescriptorSets) {

	MVKTraceVulkanCallStart();
	MVKDescriptorPool* mvkDP = (MVKDescriptorPool*)pAllocateInfo->descriptorPool;
	VkResult rslt = mvkDP->allocateDescriptorSets(pAllocateInfo->descriptorSetCount,
												  pAllocateInfo->pSetLayouts,
												  pDescriptorSets);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkFreeDescriptorSets(
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

MVK_PUBLIC_SYMBOL void vkUpdateDescriptorSets(
    VkDevice                                    device,
    uint32_t                                    writeCount,
    const VkWriteDescriptorSet*                 pDescriptorWrites,
    uint32_t                                    copyCount,
    const VkCopyDescriptorSet*                  pDescriptorCopies) {
	
	MVKTraceVulkanCallStart();
	mvkUpdateDescriptorSets(writeCount, pDescriptorWrites, copyCount, pDescriptorCopies);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateFramebuffer(
    VkDevice                                    device,
    const VkFramebufferCreateInfo*              pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkFramebuffer*                              pFramebuffer) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKFramebuffer* mvkFB = mvkDev->createFramebuffer(pCreateInfo, pAllocator);
	*pFramebuffer = (VkFramebuffer)mvkFB;
	VkResult rslt = mvkFB->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyFramebuffer(
    VkDevice                                    device,
	VkFramebuffer                               framebuffer,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyFramebuffer((MVKFramebuffer*)framebuffer, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateRenderPass(
    VkDevice                                    device,
    const VkRenderPassCreateInfo*               pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkRenderPass*                               pRenderPass) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKRenderPass* mvkRendPass = mvkDev->createRenderPass(pCreateInfo, pAllocator);
	*pRenderPass = (VkRenderPass)mvkRendPass;
	VkResult rslt = mvkRendPass->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyRenderPass(
    VkDevice                                    device,
	VkRenderPass                                renderPass,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyRenderPass((MVKRenderPass*)renderPass, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetRenderAreaGranularity(
    VkDevice                                    device,
    VkRenderPass                                renderPass,
    VkExtent2D*                                 pGranularity) {

	MVKTraceVulkanCallStart();
    MVKRenderPass* mvkRendPass = (MVKRenderPass*)renderPass;
    *pGranularity = mvkRendPass->getRenderAreaGranularity();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateCommandPool(
    VkDevice                                    device,
    const VkCommandPoolCreateInfo*              pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkCommandPool*                              pCmdPool) {
	
	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKCommandPool* mvkCmdPool = mvkDev->createCommandPool(pCreateInfo, pAllocator);
	*pCmdPool = (VkCommandPool)mvkCmdPool;
	VkResult rslt = mvkCmdPool->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyCommandPool(
    VkDevice                                    device,
	VkCommandPool                               commandPool,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyCommandPool((MVKCommandPool*)commandPool, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkResetCommandPool(
	VkDevice                                    device,
	VkCommandPool                               commandPool,
	VkCommandPoolResetFlags                     flags) {

	MVKTraceVulkanCallStart();
	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)commandPool;
	VkResult rslt = mvkCmdPool->reset(flags);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkAllocateCommandBuffers(
	VkDevice                                    device,
	const VkCommandBufferAllocateInfo*          pAllocateInfo,
	VkCommandBuffer*                            pCmdBuffer) {

	MVKTraceVulkanCallStart();
	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)pAllocateInfo->commandPool;
	VkResult rslt = mvkCmdPool->allocateCommandBuffers(pAllocateInfo, pCmdBuffer);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkFreeCommandBuffers(
    VkDevice                                    device,
	VkCommandPool                               commandPool,
	uint32_t                                    commandBufferCount,
	const VkCommandBuffer*                      pCommandBuffers) {

	MVKTraceVulkanCallStart();
	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)commandPool;
	mvkCmdPool->freeCommandBuffers(commandBufferCount, pCommandBuffers);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkBeginCommandBuffer(
    VkCommandBuffer                             commandBuffer,
    const VkCommandBufferBeginInfo*             pBeginInfo) {
	
	MVKTraceVulkanCallStart();
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	VkResult rslt = cmdBuff->begin(pBeginInfo);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkEndCommandBuffer(
    VkCommandBuffer                             commandBuffer) {
	
	MVKTraceVulkanCallStart();
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	VkResult rslt = cmdBuff->end();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkResetCommandBuffer(
    VkCommandBuffer                             commandBuffer,
    VkCommandBufferResetFlags                   flags) {

	MVKTraceVulkanCallStart();
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	VkResult rslt = cmdBuff->reset(flags);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkCmdBindPipeline(
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

MVK_PUBLIC_SYMBOL void vkCmdSetViewport(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    firstViewport,
	uint32_t                                    viewportCount,
	const VkViewport*                           pViewports) {

	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(SetViewport, viewportCount, 1, commandBuffer, firstViewport, viewportCount, pViewports);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdSetScissor(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    firstScissor,
	uint32_t                                    scissorCount,
	const VkRect2D*                             pScissors) {

	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(SetScissor, scissorCount, 1, commandBuffer, firstScissor, scissorCount, pScissors);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdSetLineWidth(
	VkCommandBuffer                             commandBuffer,
	float                                       lineWidth) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetLineWidth, commandBuffer, lineWidth);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdSetDepthBias(
	VkCommandBuffer                             commandBuffer,
	float                                       depthBiasConstantFactor,
	float                                       depthBiasClamp,
	float                                       depthBiasSlopeFactor) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetDepthBias, commandBuffer,depthBiasConstantFactor, depthBiasClamp, depthBiasSlopeFactor);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdSetBlendConstants(
	VkCommandBuffer                             commandBuffer,
	const float                                 blendConst[4]) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetBlendConstants, commandBuffer, blendConst);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdSetDepthBounds(
	VkCommandBuffer                             commandBuffer,
	float                                       minDepthBounds,
	float                                       maxDepthBounds) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetDepthBounds, commandBuffer, minDepthBounds, maxDepthBounds);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdSetStencilCompareMask(
	VkCommandBuffer                             commandBuffer,
	VkStencilFaceFlags                          faceMask,
	uint32_t                                    stencilCompareMask) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetStencilCompareMask, commandBuffer, faceMask, stencilCompareMask);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdSetStencilWriteMask(
	VkCommandBuffer                             commandBuffer,
	VkStencilFaceFlags                          faceMask,
	uint32_t                                    stencilWriteMask) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetStencilWriteMask, commandBuffer, faceMask, stencilWriteMask);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdSetStencilReference(
	VkCommandBuffer                             commandBuffer,
	VkStencilFaceFlags                          faceMask,
	uint32_t                                    stencilReference) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(SetStencilReference, commandBuffer, faceMask, stencilReference);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdBindDescriptorSets(
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

MVK_PUBLIC_SYMBOL void vkCmdBindIndexBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    VkIndexType                                 indexType) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(BindIndexBuffer, commandBuffer, buffer, offset, indexType);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdBindVertexBuffers(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    startBinding,
    uint32_t                                    bindingCount,
    const VkBuffer*                             pBuffers,
    const VkDeviceSize*                         pOffsets) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFrom2Thresholds(BindVertexBuffers, bindingCount, 1, 2, commandBuffer, startBinding, bindingCount, pBuffers, pOffsets);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdDraw(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    vertexCount,
	uint32_t                                    instanceCount,
	uint32_t                                    firstVertex,
	uint32_t                                    firstInstance) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(Draw, commandBuffer, vertexCount, instanceCount, firstVertex, firstInstance);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdDrawIndexed(
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

MVK_PUBLIC_SYMBOL void vkCmdDrawIndirect(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    uint32_t                                    drawCount,
    uint32_t                                    stride) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(DrawIndirect, commandBuffer, buffer, offset, drawCount, stride);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdDrawIndexedIndirect(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    uint32_t                                    drawCount,
    uint32_t                                    stride) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(DrawIndexedIndirect, commandBuffer, buffer, offset, drawCount, stride);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdDispatch(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    x,
    uint32_t                                    y,
    uint32_t                                    z) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(Dispatch, commandBuffer, 0, 0, 0, x, y, z);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdDispatchIndirect(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset) {
	
	MVKTraceVulkanCallStart();
    MVKAddCmd(DispatchIndirect, commandBuffer, buffer, offset);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdCopyBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    srcBuffer,
    VkBuffer                                    destBuffer,
    uint32_t                                    regionCount,
    const VkBufferCopy*                         pRegions) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(CopyBuffer, regionCount, 1, commandBuffer, srcBuffer, destBuffer, regionCount, pRegions);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdCopyImage(
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

MVK_PUBLIC_SYMBOL void vkCmdBlitImage(
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

MVK_PUBLIC_SYMBOL void vkCmdCopyBufferToImage(
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

MVK_PUBLIC_SYMBOL void vkCmdCopyImageToBuffer(
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

MVK_PUBLIC_SYMBOL void vkCmdUpdateBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    dstBuffer,
    VkDeviceSize                                dstOffset,
    VkDeviceSize                                dataSize,
    const void*                                 pData) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(UpdateBuffer, commandBuffer, dstBuffer, dstOffset, dataSize, pData);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdFillBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    dstBuffer,
    VkDeviceSize                                dstOffset,
    VkDeviceSize                                size,
    uint32_t                                    data) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(FillBuffer, commandBuffer, dstBuffer, dstOffset, size, data);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdClearColorImage(
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

MVK_PUBLIC_SYMBOL void vkCmdClearDepthStencilImage(
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

MVK_PUBLIC_SYMBOL void vkCmdClearAttachments(
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

MVK_PUBLIC_SYMBOL void vkCmdResolveImage(
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

MVK_PUBLIC_SYMBOL void vkCmdSetEvent(
    VkCommandBuffer                             commandBuffer,
    VkEvent                                     event,
    VkPipelineStageFlags                        stageMask) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(SetEvent, commandBuffer, event, stageMask);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdResetEvent(
    VkCommandBuffer                             commandBuffer,
    VkEvent                                     event,
    VkPipelineStageFlags                        stageMask) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(ResetEvent, commandBuffer, event, stageMask);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdWaitEvents(
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

MVK_PUBLIC_SYMBOL void vkCmdPipelineBarrier(
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

MVK_PUBLIC_SYMBOL void vkCmdBeginQuery(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    query,
    VkQueryControlFlags                         flags) {
	
	MVKTraceVulkanCallStart();
    MVKAddCmd(BeginQuery, commandBuffer, queryPool, query, flags);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdEndQuery(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    query) {
	
	MVKTraceVulkanCallStart();
    MVKAddCmd(EndQuery, commandBuffer, queryPool, query);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdResetQueryPool(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    firstQuery,
    uint32_t                                    queryCount) {
	
	MVKTraceVulkanCallStart();
    MVKAddCmd(ResetQueryPool, commandBuffer, queryPool, firstQuery, queryCount);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdWriteTimestamp(
	VkCommandBuffer                             commandBuffer,
	VkPipelineStageFlagBits                     pipelineStage,
	VkQueryPool                                 queryPool,
	uint32_t                                    query) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(WriteTimestamp, commandBuffer, pipelineStage, queryPool, query);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdCopyQueryPoolResults(
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

MVK_PUBLIC_SYMBOL void vkCmdPushConstants(
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

MVK_PUBLIC_SYMBOL void vkCmdBeginRenderPass(
    VkCommandBuffer                             commandBuffer,
    const VkRenderPassBeginInfo*                pRenderPassBegin,
    VkSubpassContents							contents) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFrom2Thresholds(BeginRenderPass, pRenderPassBegin->clearValueCount, 1, 2, commandBuffer,pRenderPassBegin, contents);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdNextSubpass(
    VkCommandBuffer                             commandBuffer,
    VkSubpassContents							contents) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(NextSubpass, commandBuffer, contents);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdEndRenderPass(
    VkCommandBuffer                             commandBuffer) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmd(EndRenderPass, commandBuffer);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdExecuteCommands(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    cmdBuffersCount,
    const VkCommandBuffer*						pCommandBuffers) {
	
	MVKTraceVulkanCallStart();
	MVKAddCmdFromThreshold(ExecuteCommands, cmdBuffersCount, 1, commandBuffer, cmdBuffersCount, pCommandBuffers);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_KHR_bind_memory2 extension

MVK_PUBLIC_SYMBOL VkResult vkBindBufferMemory2KHR(
	VkDevice									device,
	uint32_t									bindInfoCount,
	const VkBindBufferMemoryInfoKHR*			pBindInfos) {

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

MVK_PUBLIC_SYMBOL VkResult vkBindImageMemory2KHR(
	VkDevice									device,
	uint32_t									bindInfoCount,
	const VkBindImageMemoryInfoKHR*				pBindInfos) {

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


#pragma mark -
#pragma mark VK_KHR_descriptor_update_template extension

MVK_PUBLIC_SYMBOL VkResult vkCreateDescriptorUpdateTemplateKHR(
    VkDevice                                       device,
    const VkDescriptorUpdateTemplateCreateInfoKHR* pCreateInfo,
    const VkAllocationCallbacks*                   pAllocator,
    VkDescriptorUpdateTemplateKHR*                 pDescriptorUpdateTemplate) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    auto *mvkDUT = mvkDev->createDescriptorUpdateTemplate(pCreateInfo,
                                                          pAllocator);
    *pDescriptorUpdateTemplate = (VkDescriptorUpdateTemplateKHR)mvkDUT;
    VkResult rslt = mvkDUT->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyDescriptorUpdateTemplateKHR(
    VkDevice                                    device,
    VkDescriptorUpdateTemplateKHR               descriptorUpdateTemplate,
    const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroyDescriptorUpdateTemplate((MVKDescriptorUpdateTemplate*)descriptorUpdateTemplate, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkUpdateDescriptorSetWithTemplateKHR(
    VkDevice                                    device,
    VkDescriptorSet                             descriptorSet,
    VkDescriptorUpdateTemplateKHR               descriptorUpdateTemplate,
    const void*                                 pData) {

	MVKTraceVulkanCallStart();
    mvkUpdateDescriptorSetWithTemplate(descriptorSet, descriptorUpdateTemplate, pData);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_KHR_device_group extension

MVK_PUBLIC_SYMBOL void vkGetDeviceGroupPeerMemoryFeaturesKHR(
    VkDevice                                    device,
    uint32_t                                    heapIndex,
    uint32_t                                    localDeviceIndex,
    uint32_t                                    remoteDeviceIndex,
    VkPeerMemoryFeatureFlagsKHR*                pPeerMemoryFeatures) {

    MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->getPeerMemoryFeatures(heapIndex, localDeviceIndex, remoteDeviceIndex, pPeerMemoryFeatures);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdSetDeviceMaskKHR(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    deviceMask) {

    MVKTraceVulkanCallStart();
	// No-op for now...
//    MVKAddCmd(SetDeviceMask, commandBuffer, deviceMask);
    MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdDispatchBaseKHR(
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
#pragma mark VK_KHR_device_group_creation extension

MVK_PUBLIC_SYMBOL VkResult vkEnumeratePhysicalDeviceGroupsKHR(
    VkInstance                                  instance,
    uint32_t*                                   pPhysicalDeviceGroupCount,
    VkPhysicalDeviceGroupPropertiesKHR*         pPhysicalDeviceGroupProperties) {
    MVKTraceVulkanCallStart();
    MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
    VkResult rslt = mvkInst->getPhysicalDeviceGroups(pPhysicalDeviceGroupCount, pPhysicalDeviceGroupProperties);
    MVKTraceVulkanCallEnd();
    return rslt;
}


#pragma mark -
#pragma mark VK_KHR_get_memory_requirements2 extension

MVK_PUBLIC_SYMBOL void vkGetBufferMemoryRequirements2KHR(
    VkDevice                                    device,
    const VkBufferMemoryRequirementsInfo2KHR*   pInfo,
    VkMemoryRequirements2KHR*                   pMemoryRequirements) {

	MVKTraceVulkanCallStart();
    MVKBuffer* mvkBuff = (MVKBuffer*)pInfo->buffer;
    mvkBuff->getMemoryRequirements(pInfo, pMemoryRequirements);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetImageMemoryRequirements2KHR(
    VkDevice                                    device,
    const VkImageMemoryRequirementsInfo2KHR*    pInfo,
    VkMemoryRequirements2KHR*                   pMemoryRequirements) {

	MVKTraceVulkanCallStart();
    auto* mvkImg = (MVKImage*)pInfo->image;
    mvkImg->getMemoryRequirements(pInfo, pMemoryRequirements);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetImageSparseMemoryRequirements2KHR(
    VkDevice                                        device,
    const VkImageSparseMemoryRequirementsInfo2KHR*  pInfo,
    uint32_t*                                       pSparseMemoryRequirementCount,
    VkSparseImageMemoryRequirements2KHR*            pSparseMemoryRequirements) {

	MVKTraceVulkanCallStart();

	// Metal does not support sparse images.
	// Vulkan spec: "If the image was not created with VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT then
	// pSparseMemoryRequirementCount will be set to zero and pSparseMemoryRequirements will not be written to.".

    *pSparseMemoryRequirementCount = 0;
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_KHR_get_physical_device_properties2 extension

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceFeatures2KHR(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceFeatures2KHR*               pFeatures) {
    
	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getFeatures(pFeatures);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceProperties2KHR(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceProperties2KHR*             pProperties) {

	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getProperties(pProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceFormatProperties2KHR(
    VkPhysicalDevice                            physicalDevice,
    VkFormat                                    format,
    VkFormatProperties2KHR*                     pFormatProperties) {
    
	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getFormatProperties(format, pFormatProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceImageFormatProperties2KHR(
    VkPhysicalDevice                            physicalDevice,
    const VkPhysicalDeviceImageFormatInfo2KHR*  pImageFormatInfo,
    VkImageFormatProperties2KHR*                pImageFormatProperties) {
    
	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    VkResult rslt = mvkPD->getImageFormatProperties(pImageFormatInfo, pImageFormatProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceQueueFamilyProperties2KHR(
    VkPhysicalDevice                            physicalDevice,
    uint32_t*                                   pQueueFamilyPropertyCount,
    VkQueueFamilyProperties2KHR*                pQueueFamilyProperties) {
    
	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getQueueFamilyProperties(pQueueFamilyPropertyCount, pQueueFamilyProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceMemoryProperties2KHR(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceMemoryProperties2KHR*       pMemoryProperties) {

	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getMemoryProperties(pMemoryProperties);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceSparseImageFormatProperties2KHR(
    VkPhysicalDevice                            physicalDevice,
    const VkPhysicalDeviceSparseImageFormatInfo2KHR* pFormatInfo,
    uint32_t*                                   pPropertyCount,
    VkSparseImageFormatProperties2KHR*          pProperties) {

	MVKTraceVulkanCallStart();

	// Metal does not support sparse images.
	// Vulkan spec: "If VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT is not supported for the given arguments,
	// pPropertyCount will be set to zero upon return, and no data will be written to pProperties.".

    *pPropertyCount = 0;
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_KHR_maintenance1 extension

MVK_PUBLIC_SYMBOL void vkTrimCommandPoolKHR(
    VkDevice                                    device,
    VkCommandPool                               commandPool,
    VkCommandPoolTrimFlagsKHR                   flags) {

	MVKTraceVulkanCallStart();
	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)commandPool;
    mvkCmdPool->trim();
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_KHR_maintenance3 extension

MVK_PUBLIC_SYMBOL void vkGetDescriptorSetLayoutSupportKHR(
    VkDevice                                    device,
    const VkDescriptorSetLayoutCreateInfo*      pCreateInfo,
    VkDescriptorSetLayoutSupportKHR*            pSupport) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDevice = MVKDevice::getMVKDevice(device);
    mvkDevice->getDescriptorSetLayoutSupport(pCreateInfo, pSupport);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_KHR_push_descriptor extension

MVK_PUBLIC_SYMBOL void vkCmdPushDescriptorSetKHR(
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

MVK_PUBLIC_SYMBOL void vkCmdPushDescriptorSetWithTemplateKHR(
    VkCommandBuffer                            commandBuffer,
    VkDescriptorUpdateTemplateKHR              descriptorUpdateTemplate,
    VkPipelineLayout                           layout,
    uint32_t                                   set,
    const void*                                pData) {

	MVKTraceVulkanCallStart();
    MVKAddCmd(PushDescriptorSetWithTemplate, commandBuffer, descriptorUpdateTemplate, layout, set, pData);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_KHR_swapchain extension

MVK_PUBLIC_SYMBOL VkResult vkCreateSwapchainKHR(
    VkDevice                                 device,
    const VkSwapchainCreateInfoKHR*          pCreateInfo,
    const VkAllocationCallbacks*             pAllocator,
    VkSwapchainKHR*                          pSwapchain) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    MVKSwapchain* mvkSwpChn = mvkDev->createSwapchain(pCreateInfo, pAllocator);
    *pSwapchain = (VkSwapchainKHR)(mvkSwpChn);
    VkResult rslt = mvkSwpChn->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroySwapchainKHR(
    VkDevice                                 device,
    VkSwapchainKHR                           swapchain,
    const VkAllocationCallbacks*             pAllocator) {

	MVKTraceVulkanCallStart();
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroySwapchain((MVKSwapchain*)swapchain, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkGetSwapchainImagesKHR(
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

MVK_PUBLIC_SYMBOL VkResult vkAcquireNextImageKHR(
    VkDevice                                     device,
    VkSwapchainKHR                               swapchain,
    uint64_t                                     timeout,
    VkSemaphore                                  semaphore,
    VkFence                                      fence,
    uint32_t*                                    pImageIndex) {

	MVKTraceVulkanCallStart();
    MVKSwapchain* mvkSwapchain = (MVKSwapchain*)swapchain;
    VkResult rslt = mvkSwapchain->acquireNextImageKHR(timeout, semaphore, fence, ~0u, pImageIndex);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkQueuePresentKHR(
    VkQueue                                      queue,
    const VkPresentInfoKHR*                      pPresentInfo) {

	MVKTraceVulkanCallStart();
    MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
    VkResult rslt = mvkQ->submit(pPresentInfo);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkGetDeviceGroupPresentCapabilitiesKHR(
	VkDevice                                    device,
	VkDeviceGroupPresentCapabilitiesKHR*        pDeviceGroupPresentCapabilities) {

	MVKTraceVulkanCallStart();
	MVKDevice* mvkDevice = MVKDevice::getMVKDevice(device);
	VkResult rslt = mvkDevice->getDeviceGroupPresentCapabilities(pDeviceGroupPresentCapabilities);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkGetDeviceGroupSurfacePresentModesKHR(
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

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDevicePresentRectanglesKHR(
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

MVK_PUBLIC_SYMBOL VkResult vkAcquireNextImage2KHR(
	VkDevice                                    device,
	const VkAcquireNextImageInfoKHR*            pAcquireInfo,
	uint32_t*                                   pImageIndex) {

	MVKTraceVulkanCallStart();
	MVKSwapchain* mvkSwapchain = (MVKSwapchain*)pAcquireInfo->swapchain;
	VkResult rslt = mvkSwapchain->acquireNextImageKHR(pAcquireInfo->timeout,
													  pAcquireInfo->semaphore,
													  pAcquireInfo->fence,
													  pAcquireInfo->deviceMask,
													  pImageIndex);
	MVKTraceVulkanCallEnd();
	return rslt;
}


#pragma mark -
#pragma mark VK_KHR_surface extension

MVK_PUBLIC_SYMBOL void vkDestroySurfaceKHR(
    VkInstance                                   instance,
    VkSurfaceKHR                                 surface,
    const VkAllocationCallbacks*                 pAllocator) {

	MVKTraceVulkanCallStart();
    MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
    mvkInst->destroySurface((MVKSurface*)surface, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfaceSupportKHR(
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

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    VkPhysicalDevice                            physicalDevice,
    VkSurfaceKHR                                surface,
    VkSurfaceCapabilitiesKHR*                   pSurfaceCapabilities) {

	MVKTraceVulkanCallStart();
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    MVKSurface* mvkSrfc = (MVKSurface*)surface;
    VkResult rslt = mvkPD->getSurfaceCapabilities(mvkSrfc, pSurfaceCapabilities);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfaceFormatsKHR(
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

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfacePresentModesKHR(
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

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfaceCapabilities2KHR(
	VkPhysicalDevice                            physicalDevice,
	const VkPhysicalDeviceSurfaceInfo2KHR*      pSurfaceInfo,
	VkSurfaceCapabilities2KHR*                  pSurfaceCapabilities) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	MVKSurface* mvkSrfc = (MVKSurface*)pSurfaceInfo->surface;
	VkResult rslt = mvkPD->getSurfaceCapabilities(mvkSrfc, &pSurfaceCapabilities->surfaceCapabilities);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfaceFormats2KHR(
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
#pragma mark VK_EXT_debug_report extension

MVK_PUBLIC_SYMBOL VkResult vkCreateDebugReportCallbackEXT(
	VkInstance                                  instance,
	const VkDebugReportCallbackCreateInfoEXT*   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkDebugReportCallbackEXT*                   pCallback) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	MVKDebugReportCallback* mvkDRCB = mvkInst->createDebugReportCallback(pCreateInfo, pAllocator);
	*pCallback = (VkDebugReportCallbackEXT)mvkDRCB;
	VkResult rslt = mvkDRCB->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyDebugReportCallbackEXT(
	VkInstance                                  instance,
	VkDebugReportCallbackEXT                    callback,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	mvkInst->destroyDebugReportCallback((MVKDebugReportCallback*)callback, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkDebugReportMessageEXT(
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

MVK_PUBLIC_SYMBOL VkResult vkDebugMarkerSetObjectTagEXT(
	VkDevice                                    device,
	const VkDebugMarkerObjectTagInfoEXT*        pTagInfo) {

	MVKTraceVulkanCallStart();
	VkResult rslt = VK_SUCCESS;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkDebugMarkerSetObjectNameEXT(
	VkDevice                                    device,
	const VkDebugMarkerObjectNameInfoEXT*       pNameInfo) {

	MVKTraceVulkanCallStart();
	MVKVulkanAPIObject* mvkObj = MVKVulkanAPIObject::getMVKVulkanAPIObject(pNameInfo->objectType, pNameInfo->object);
	VkResult rslt = mvkObj ? mvkObj->setDebugName(pNameInfo->pObjectName) : VK_SUCCESS;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkCmdDebugMarkerBeginEXT(
	VkCommandBuffer                             commandBuffer,
	const VkDebugMarkerMarkerInfoEXT*           pMarkerInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerBegin, commandBuffer, pMarkerInfo->pMarkerName, pMarkerInfo->color);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdDebugMarkerEndEXT(
	VkCommandBuffer                             commandBuffer) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerEnd, commandBuffer);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdDebugMarkerInsertEXT(
	VkCommandBuffer                             commandBuffer,
	const VkDebugMarkerMarkerInfoEXT*           pMarkerInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerInsert, commandBuffer, pMarkerInfo->pMarkerName, pMarkerInfo->color);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_EXT_debug_utils extension

MVK_PUBLIC_SYMBOL VkResult vkSetDebugUtilsObjectNameEXT(
	VkDevice                                    device,
	const VkDebugUtilsObjectNameInfoEXT*        pNameInfo) {

	MVKTraceVulkanCallStart();
	MVKVulkanAPIObject* mvkObj = MVKVulkanAPIObject::getMVKVulkanAPIObject(pNameInfo->objectType, pNameInfo->objectHandle);
	VkResult rslt = mvkObj ? mvkObj->setDebugName(pNameInfo->pObjectName) : VK_SUCCESS;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkSetDebugUtilsObjectTagEXT(
	VkDevice                                    device,
	const VkDebugUtilsObjectTagInfoEXT*         pTagInfo) {

	MVKTraceVulkanCallStart();
	VkResult rslt = VK_SUCCESS;
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkQueueBeginDebugUtilsLabelEXT(
	VkQueue                                     queue,
	const VkDebugUtilsLabelEXT*                 pLabelInfo) {

	MVKTraceVulkanCallStart();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkQueueEndDebugUtilsLabelEXT(
	VkQueue                                     queue) {

	MVKTraceVulkanCallStart();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkQueueInsertDebugUtilsLabelEXT(
	VkQueue                                     queue,
	const VkDebugUtilsLabelEXT*                 pLabelInfo) {

	MVKTraceVulkanCallStart();
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdBeginDebugUtilsLabelEXT(
	VkCommandBuffer                             commandBuffer,
	const VkDebugUtilsLabelEXT*                 pLabelInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerBegin, commandBuffer, pLabelInfo->pLabelName, pLabelInfo->color);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdEndDebugUtilsLabelEXT(
	VkCommandBuffer                             commandBuffer) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerEnd, commandBuffer);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkCmdInsertDebugUtilsLabelEXT(
	VkCommandBuffer                             commandBuffer,
	const VkDebugUtilsLabelEXT*                 pLabelInfo) {

	MVKTraceVulkanCallStart();
	MVKAddCmd(DebugMarkerInsert, commandBuffer, pLabelInfo->pLabelName, pLabelInfo->color);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateDebugUtilsMessengerEXT(
	VkInstance                                  instance,
	const VkDebugUtilsMessengerCreateInfoEXT*   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkDebugUtilsMessengerEXT*                   pMessenger) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	MVKDebugUtilsMessenger* mvkDUM = mvkInst->createDebugUtilsMessenger(pCreateInfo, pAllocator);
	*pMessenger = (VkDebugUtilsMessengerEXT)mvkDUM;
	VkResult rslt = mvkDUM->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkDestroyDebugUtilsMessengerEXT(
	VkInstance                                  instance,
	VkDebugUtilsMessengerEXT                    messenger,
	const VkAllocationCallbacks*                pAllocator) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	mvkInst->destroyDebugUtilsMessenger((MVKDebugUtilsMessenger*)messenger, pAllocator);
	MVKTraceVulkanCallEnd();
}

MVK_PUBLIC_SYMBOL void vkSubmitDebugUtilsMessageEXT(
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
#pragma mark VK_EXT_hdr_metadata extension

MVK_PUBLIC_SYMBOL void vkSetHdrMetadataEXT(
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

MVK_PUBLIC_SYMBOL void vkResetQueryPoolEXT(
    VkDevice                                    device,
    VkQueryPool                                 queryPool,
    uint32_t                                    firstQuery,
    uint32_t                                    queryCount) {

	MVKTraceVulkanCallStart();
    auto* mvkQueryPool = (MVKQueryPool*)queryPool;
    mvkQueryPool->resetResults(firstQuery, queryCount, nullptr);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_KHR_external_memory_capabilities extension

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceExternalBufferPropertiesKHR(
	VkPhysicalDevice                            physicalDevice,
	const VkPhysicalDeviceExternalBufferInfo*   pExternalBufferInfo,
	VkExternalBufferProperties*                 pExternalBufferProperties) {

	MVKTraceVulkanCallStart();
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getExternalBufferProperties(pExternalBufferInfo, pExternalBufferProperties);
	MVKTraceVulkanCallEnd();
}


#pragma mark -
#pragma mark VK_EXT_metal_surface extension

MVK_PUBLIC_SYMBOL VkResult vkCreateMetalSurfaceEXT(
	VkInstance                                  instance,
	const VkMetalSurfaceCreateInfoEXT*          pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkSurfaceKHR*                               pSurface) {

	MVKTraceVulkanCallStart();
	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	MVKSurface* mvkSrfc = mvkInst->createSurface(pCreateInfo, pAllocator);
	*pSurface = (VkSurfaceKHR)mvkSrfc;
	VkResult rslt = mvkSrfc->getConfigurationResult();
	MVKTraceVulkanCallEnd();
	return rslt;
}

#pragma mark -
#pragma mark VK_GOOGLE_display_timing extension

MVK_PUBLIC_SYMBOL VkResult vkGetRefreshCycleDurationGOOGLE(
	VkDevice                                    device,
	VkSwapchainKHR                              swapchain,
	VkRefreshCycleDurationGOOGLE*               pDisplayTimingProperties) {
	MVKTraceVulkanCallStart();
	MVKSwapchain* mvkSwapchain = (MVKSwapchain*)swapchain;
	VkResult rslt = mvkSwapchain->getRefreshCycleDuration(pDisplayTimingProperties);
	MVKTraceVulkanCallEnd();
	return rslt;
}

MVK_PUBLIC_SYMBOL VkResult vkGetPastPresentationTimingGOOGLE(
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
#pragma mark iOS & macOS surface extensions

MVK_PUBLIC_SYMBOL VkResult vkCreate_PLATFORM_SurfaceMVK(
    VkInstance                                  instance,
    const Vk_PLATFORM_SurfaceCreateInfoMVK*		pCreateInfo,
    const VkAllocationCallbacks*                pAllocator,
    VkSurfaceKHR*                               pSurface) {

	MVKTraceVulkanCallStart();
    MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
    MVKSurface* mvkSrfc = mvkInst->createSurface(pCreateInfo, pAllocator);
    *pSurface = (VkSurfaceKHR)mvkSrfc;
    VkResult rslt = mvkSrfc->getConfigurationResult();
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
	if (strcmp(pName, "vk_icdNegotiateLoaderICDInterfaceVersion") == 0) {
		func = (PFN_vkVoidFunction)vk_icdNegotiateLoaderICDInterfaceVersion;
	} else if (strcmp(pName, "vk_icdGetPhysicalDeviceProcAddr") == 0) {
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

