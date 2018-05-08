/*
 * vulkan.mm
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
#include "MVKFoundation.h"
#include "MVKLogging.h"

/** Log that the specified Vulkan function is not yet supported, and raise an assertion. */
static VkResult MVKLogUnimplemented(const char* funcName) {
    return mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "%s() is not implemented!", funcName);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateInstance(
    const VkInstanceCreateInfo*                 pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkInstance*                                 pInstance) {

	MVKInstance* mvkInst = new MVKInstance(pCreateInfo);
	*pInstance = mvkInst->getVkInstance();
	return mvkInst->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyInstance(
    VkInstance                                  instance,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !instance ) { return; }
	MVKInstance::getMVKInstance(instance)->destroy();
}

MVK_PUBLIC_SYMBOL VkResult vkEnumeratePhysicalDevices(
    VkInstance                                  instance,
    uint32_t*                                   pPhysicalDeviceCount,
    VkPhysicalDevice*                           pPhysicalDevices) {

	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	return mvkInst->getPhysicalDevices(pPhysicalDeviceCount, pPhysicalDevices);
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceFeatures(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceFeatures*                   pFeatures) {
	
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getFeatures(pFeatures);
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceFormatProperties(
    VkPhysicalDevice                            physicalDevice,
    VkFormat                                    format,
    VkFormatProperties*                         pFormatProperties) {
	
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getFormatProperties(format, pFormatProperties);
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceImageFormatProperties(
    VkPhysicalDevice                            physicalDevice,
    VkFormat                                    format,
    VkImageType                                 type,
    VkImageTiling                               tiling,
    VkImageUsageFlags                           usage,
    VkImageCreateFlags                          flags,
    VkImageFormatProperties*                    pImageFormatProperties) {
	
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    return mvkPD->getImageFormatProperties(format, type, tiling, usage, flags, pImageFormatProperties);
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceProperties(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceProperties*                 pProperties) {

	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getProperties(pProperties);
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceQueueFamilyProperties(
	VkPhysicalDevice                            physicalDevice,
	uint32_t*                                   pQueueFamilyPropertyCount,
	VkQueueFamilyProperties*                    pQueueFamilyProperties) {
	
	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getQueueFamilyProperties(pQueueFamilyPropertyCount, pQueueFamilyProperties);
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceMemoryProperties(
    VkPhysicalDevice                            physicalDevice,
    VkPhysicalDeviceMemoryProperties*           pMemoryProperties) {

	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	mvkPD->getPhysicalDeviceMemoryProperties(pMemoryProperties);
}

MVK_PUBLIC_SYMBOL PFN_vkVoidFunction vkGetInstanceProcAddr(
    VkInstance                                  instance,
    const char*                                 pName) {

	// Handle the function that creates an instance specially.
	// In this case, the instance parameter is ignored and may be NULL.
	if (strcmp(pName, "vkCreateInstance") == 0) { return (PFN_vkVoidFunction)vkCreateInstance; }
	if (strcmp(pName, "vkEnumerateInstanceExtensionProperties") == 0) { return (PFN_vkVoidFunction)vkEnumerateInstanceExtensionProperties; }
	if (strcmp(pName, "vkEnumerateInstanceLayerProperties") == 0) { return (PFN_vkVoidFunction)vkEnumerateInstanceLayerProperties; }
    if (instance) {
        MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
        return mvkInst->getProcAddr(pName);
    }
    return NULL;
}

MVK_PUBLIC_SYMBOL PFN_vkVoidFunction vkGetDeviceProcAddr(
    VkDevice                                    device,
    const char*                                 pName) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	return mvkDev->getProcAddr(pName);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateDevice(
    VkPhysicalDevice                            physicalDevice,
    const VkDeviceCreateInfo*                   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkDevice*                                   pDevice) {

	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	MVKDevice* mvkDev = new MVKDevice(mvkPD, pCreateInfo);
	*pDevice = mvkDev->getVkDevice();
	return VK_SUCCESS;
}

MVK_PUBLIC_SYMBOL void vkDestroyDevice(
	VkDevice                                    device,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !device ) { return; }
	MVKDevice::getMVKDevice(device)->destroy();
}

MVK_PUBLIC_SYMBOL VkResult vkEnumerateInstanceExtensionProperties(
    const char*                                 pLayerName,
    uint32_t*                                   pCount,
    VkExtensionProperties*                      pProperties) {

	return MVKLayerManager::globalManager()->getLayerNamed(pLayerName)->getExtensionProperties(pCount, pProperties);
}

MVK_PUBLIC_SYMBOL VkResult vkEnumerateDeviceExtensionProperties(
    VkPhysicalDevice                            physicalDevice,
    const char*                                 pLayerName,
    uint32_t*                                   pCount,
    VkExtensionProperties*                      pProperties) {

	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	return mvkPD->getLayerManager()->getLayerNamed(pLayerName)->getExtensionProperties(pCount, pProperties);
}

MVK_PUBLIC_SYMBOL VkResult vkEnumerateInstanceLayerProperties(
    uint32_t*                                   pCount,
    VkLayerProperties*                          pProperties) {

	return MVKLayerManager::globalManager()->getLayerProperties(pCount, pProperties);
}

MVK_PUBLIC_SYMBOL VkResult vkEnumerateDeviceLayerProperties(
    VkPhysicalDevice                            physicalDevice,
    uint32_t*                                   pCount,
    VkLayerProperties*                          pProperties) {

	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	return mvkPD->getLayerManager()->getLayerProperties(pCount, pProperties);
}

MVK_PUBLIC_SYMBOL void vkGetDeviceQueue(
    VkDevice                                    device,
    uint32_t                                    queueFamilyIndex,
    uint32_t                                    queueIndex,
    VkQueue*                                    pQueue) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->getDeviceQueue(queueFamilyIndex, queueIndex, pQueue);
}

MVK_PUBLIC_SYMBOL VkResult vkQueueSubmit(
	VkQueue                                     queue,
	uint32_t                                    submitCount,
	const VkSubmitInfo*                         pSubmits,
	VkFence                                     fence) {

	MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
	return mvkQ->submit(submitCount, pSubmits, fence, kMVKCommandUseQueueSubmit);
}

MVK_PUBLIC_SYMBOL VkResult vkQueueWaitIdle(
    VkQueue                                     queue) {
	
	MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
	return mvkQ->waitIdle(kMVKCommandUseQueueWaitIdle);
}

MVK_PUBLIC_SYMBOL VkResult vkDeviceWaitIdle(
    VkDevice                                    device) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	return mvkDev->waitIdle();
}

MVK_PUBLIC_SYMBOL VkResult vkAllocateMemory(
    VkDevice                                    device,
    const VkMemoryAllocateInfo*                 pAllocateInfo,
    const VkAllocationCallbacks*                pAllocator,
    VkDeviceMemory*                             pMem) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKDeviceMemory* mvkMem = mvkDev->allocateMemory(pAllocateInfo, pAllocator);
	VkResult rslt = mvkMem->getConfigurationResult();
	*pMem = (VkDeviceMemory)((rslt == VK_SUCCESS) ? mvkMem : VK_NULL_HANDLE);
	return rslt;
}

MVK_PUBLIC_SYMBOL void vkFreeMemory(
    VkDevice                                    device,
	VkDeviceMemory                              mem,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !mem ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->freeMemory((MVKDeviceMemory*)mem, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkMapMemory(
   VkDevice                                    device,
   VkDeviceMemory                              mem,
   VkDeviceSize                                offset,
   VkDeviceSize                                size,
   VkMemoryMapFlags                            flags,
   void**                                      ppData) {

	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	return mvkMem->map(offset, size, flags, ppData);
}

MVK_PUBLIC_SYMBOL void vkUnmapMemory(
    VkDevice                                    device,
    VkDeviceMemory                              mem) {
	
	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	return mvkMem->unmap();
}

MVK_PUBLIC_SYMBOL VkResult vkFlushMappedMemoryRanges(
    VkDevice                                    device,
    uint32_t                                    memRangeCount,
    const VkMappedMemoryRange*                  pMemRanges) {

	for (uint32_t i = 0; i < memRangeCount; i++) {
		const VkMappedMemoryRange* pMem = &pMemRanges[i];
		MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)pMem->memory;
		mvkMem->flushToDevice(pMem->offset, pMem->size);
	}
	return VK_SUCCESS;
}

MVK_PUBLIC_SYMBOL VkResult vkInvalidateMappedMemoryRanges(
    VkDevice                                    device,
    uint32_t                                    memRangeCount,
    const VkMappedMemoryRange*                  pMemRanges) {
	
	for (uint32_t i = 0; i < memRangeCount; i++) {
		const VkMappedMemoryRange* pMem = &pMemRanges[i];
		MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)pMem->memory;
		mvkMem->pullFromDevice(pMem->offset, pMem->size);
	}
	return VK_SUCCESS;
}

MVK_PUBLIC_SYMBOL void vkGetDeviceMemoryCommitment(
    VkDevice                                    device,
    VkDeviceMemory                              memory,
    VkDeviceSize*                               pCommittedMemoryInBytes) {

    if ( !pCommittedMemoryInBytes ) { return; }

    MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)memory;
    *pCommittedMemoryInBytes = mvkMem->getDeviceMemoryCommitment();
}

MVK_PUBLIC_SYMBOL VkResult vkBindBufferMemory(
    VkDevice                                    device,
    VkBuffer                                    buffer,
    VkDeviceMemory                              mem,
    VkDeviceSize                                memOffset) {
	
	MVKBuffer* mvkBuff = (MVKBuffer*)buffer;
	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	return mvkBuff->bindDeviceMemory(mvkMem, memOffset);
}

MVK_PUBLIC_SYMBOL VkResult vkBindImageMemory(
    VkDevice                                    device,
    VkImage                                     image,
    VkDeviceMemory                              mem,
    VkDeviceSize                                memOffset) {
	
	MVKImage* mvkImg = (MVKImage*)image;
	MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)mem;
	return mvkImg->bindDeviceMemory(mvkMem, memOffset);
}

MVK_PUBLIC_SYMBOL void vkGetBufferMemoryRequirements(
    VkDevice                                    device,
    VkBuffer                                    buffer,
    VkMemoryRequirements*                       pMemoryRequirements) {
	
	MVKBuffer* mvkBuff = (MVKBuffer*)buffer;
	mvkBuff->getMemoryRequirements(pMemoryRequirements);
}

MVK_PUBLIC_SYMBOL void vkGetImageMemoryRequirements(
    VkDevice                                    device,
    VkImage                                     image,
    VkMemoryRequirements*                       pMemoryRequirements) {
	
	MVKImage* mvkImg = (MVKImage*)image;
	mvkImg->getMemoryRequirements(pMemoryRequirements);
}

MVK_PUBLIC_SYMBOL void vkGetImageSparseMemoryRequirements(
    VkDevice                                    device,
    VkImage                                     image,
    uint32_t*                                   pNumRequirements,
    VkSparseImageMemoryRequirements*            pSparseMemoryRequirements) {
	
	MVKLogUnimplemented("vkGetImageSparseMemoryRequirements");
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

	MVKLogUnimplemented("vkGetPhysicalDeviceSparseImageFormatProperties");
}

MVK_PUBLIC_SYMBOL VkResult vkQueueBindSparse(
	VkQueue                                     queue,
	uint32_t                                    bindInfoCount,
	const VkBindSparseInfo*                     pBindInfo,
	VkFence                                     fence) {

	return MVKLogUnimplemented("vkQueueBindSparse");
}

MVK_PUBLIC_SYMBOL VkResult vkCreateFence(
    VkDevice                                    device,
    const VkFenceCreateInfo*                    pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkFence*                                    pFence) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKFence* mvkFence = mvkDev->createFence(pCreateInfo, pAllocator);
	*pFence = (VkFence)mvkFence;
	return mvkFence->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyFence(
    VkDevice                                    device,
	VkFence                                     fence,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !fence ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyFence((MVKFence*)fence, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkResetFences(
    VkDevice                                    device,
    uint32_t                                    fenceCount,
    const VkFence*                              pFences) {
	
	return mvkResetFences(fenceCount, pFences);
}

MVK_PUBLIC_SYMBOL VkResult vkGetFenceStatus(
    VkDevice                                    device,
    VkFence                                     fence) {
	
	MVKFence* mvkFence = (MVKFence*)fence;
	return mvkFence->getIsSignaled() ? VK_SUCCESS : VK_NOT_READY;
}

MVK_PUBLIC_SYMBOL VkResult vkWaitForFences(
    VkDevice                                    device,
    uint32_t                                    fenceCount,
    const VkFence*                              pFences,
    VkBool32                                    waitAll,
    uint64_t                                    timeout) {
	
	return mvkWaitForFences(fenceCount, pFences, waitAll, timeout);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateSemaphore(
    VkDevice                                    device,
    const VkSemaphoreCreateInfo*                pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkSemaphore*                                pSemaphore) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKSemaphore* mvkSem4 = mvkDev->createSemaphore(pCreateInfo, pAllocator);
	*pSemaphore = (VkSemaphore)mvkSem4;
	return mvkSem4->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroySemaphore(
    VkDevice                                    device,
	VkSemaphore                                 semaphore,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !semaphore ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroySemaphore((MVKSemaphore*)semaphore, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateEvent(
    VkDevice                                    device,
    const VkEventCreateInfo*                    pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkEvent*                                    pEvent) {
	
	return MVKLogUnimplemented("vkCreateEvent");
}

MVK_PUBLIC_SYMBOL void vkDestroyEvent(
    VkDevice                                    device,
	VkEvent                                     event,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !event ) { return; }
	MVKLogUnimplemented("vkDestroyEvent");
}

MVK_PUBLIC_SYMBOL VkResult vkGetEventStatus(
    VkDevice                                    device,
    VkEvent                                     event) {
	
	return MVKLogUnimplemented("vkGetEventStatus");
}

MVK_PUBLIC_SYMBOL VkResult vkSetEvent(
    VkDevice                                    device,
    VkEvent                                     event) {
	
	return MVKLogUnimplemented("vkSetEvent");
}

MVK_PUBLIC_SYMBOL VkResult vkResetEvent(
    VkDevice                                    device,
    VkEvent                                     event) {
	
	return MVKLogUnimplemented("vkResetEvent");
}

MVK_PUBLIC_SYMBOL VkResult vkCreateQueryPool(
    VkDevice                                    device,
    const VkQueryPoolCreateInfo*                pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkQueryPool*                                pQueryPool) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKQueryPool* mvkQP = mvkDev->createQueryPool(pCreateInfo, pAllocator);
	*pQueryPool = (VkQueryPool)mvkQP;
	return mvkQP->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyQueryPool(
    VkDevice                                    device,
	VkQueryPool                                 queryPool,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !queryPool ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyQueryPool((MVKQueryPool*)queryPool, pAllocator);
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

	MVKQueryPool* mvkQP = (MVKQueryPool*)queryPool;
	return mvkQP->getResults(firstQuery, queryCount, dataSize, pData, stride, flags);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateBuffer(
    VkDevice                                    device,
    const VkBufferCreateInfo*                   pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkBuffer*                                   pBuffer) {

	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKBuffer* mvkBuff = mvkDev->createBuffer(pCreateInfo, pAllocator);
	*pBuffer = (VkBuffer)mvkBuff;
	return mvkBuff->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyBuffer(
    VkDevice                                    device,
	VkBuffer                                    buffer,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !buffer ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyBuffer((MVKBuffer*)buffer, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateBufferView(
    VkDevice                                    device,
    const VkBufferViewCreateInfo*               pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkBufferView*                               pView) {
	
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    MVKBufferView* mvkBuffView = mvkDev->createBufferView(pCreateInfo, pAllocator);
    *pView = (VkBufferView)mvkBuffView;
    return mvkBuffView->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyBufferView(
    VkDevice                                    device,
	VkBufferView                                bufferView,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !bufferView ) { return; }
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroyBufferView((MVKBufferView*)bufferView, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateImage(
    VkDevice                                    device,
    const VkImageCreateInfo*                    pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkImage*                                    pImage) {

	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKImage* mvkImg = mvkDev->createImage(pCreateInfo, pAllocator);
	*pImage = (VkImage)mvkImg;
	return mvkImg->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyImage(
    VkDevice                                    device,
	VkImage                                     image,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !image ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyImage((MVKImage*)image, pAllocator);
}

MVK_PUBLIC_SYMBOL void vkGetImageSubresourceLayout(
    VkDevice                                    device,
    VkImage                                     image,
    const VkImageSubresource*                   pSubresource,
    VkSubresourceLayout*                        pLayout) {

	MVKImage* mvkImg = (MVKImage*)image;
	mvkImg->getSubresourceLayout(pSubresource, pLayout);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateImageView(
    VkDevice                                    device,
    const VkImageViewCreateInfo*                pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkImageView*                                pView) {

	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKImageView* mvkImgView = mvkDev->createImageView(pCreateInfo, pAllocator);
	*pView = (VkImageView)mvkImgView;
	return mvkImgView->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyImageView(
    VkDevice                                    device,
	VkImageView                                 imageView,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !imageView ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyImageView((MVKImageView*)imageView, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateShaderModule(
    VkDevice                                    device,
    const VkShaderModuleCreateInfo*             pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkShaderModule*                             pShaderModule) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKShaderModule* mvkShdrMod = mvkDev->createShaderModule(pCreateInfo, pAllocator);
	*pShaderModule = (VkShaderModule)mvkShdrMod;
	return mvkShdrMod->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyShaderModule(
    VkDevice                                    device,
	VkShaderModule                              shaderModule,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !shaderModule ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyShaderModule((MVKShaderModule*)shaderModule, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreatePipelineCache(
    VkDevice                                    device,
    const VkPipelineCacheCreateInfo*            pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkPipelineCache*                            pPipelineCache) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKPipelineCache* mvkPLC = mvkDev->createPipelineCache(pCreateInfo, pAllocator);
	*pPipelineCache = (VkPipelineCache)mvkPLC;
	return mvkPLC->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyPipelineCache(
    VkDevice                                    device,
	VkPipelineCache                             pipelineCache,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !pipelineCache ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyPipelineCache((MVKPipelineCache*)pipelineCache, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkGetPipelineCacheData(
	VkDevice                                    device,
	VkPipelineCache                             pipelineCache,
	size_t*                                     pDataSize,
	void*                                       pData) {

	MVKPipelineCache* mvkPLC = (MVKPipelineCache*)pipelineCache;
	return mvkPLC->writeData(pDataSize, pData);
}

MVK_PUBLIC_SYMBOL VkResult vkMergePipelineCaches(
    VkDevice                                    device,
    VkPipelineCache                             destCache,
    uint32_t                                    srcCacheCount,
    const VkPipelineCache*                      pSrcCaches) {
	
	MVKPipelineCache* mvkPLC = (MVKPipelineCache*)destCache;
	return mvkPLC->mergePipelineCaches(srcCacheCount, pSrcCaches);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateGraphicsPipelines(
    VkDevice                                    device,
    VkPipelineCache                             pipelineCache,
    uint32_t                                    count,
    const VkGraphicsPipelineCreateInfo*         pCreateInfos,
	const VkAllocationCallbacks*                pAllocator,
    VkPipeline*                                 pPipelines) {
	
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	return mvkDev->createPipelines<MVKGraphicsPipeline, VkGraphicsPipelineCreateInfo>(pipelineCache, count, pCreateInfos, pAllocator, pPipelines);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateComputePipelines(
    VkDevice                                    device,
    VkPipelineCache                             pipelineCache,
    uint32_t                                    count,
    const VkComputePipelineCreateInfo*          pCreateInfos,
	const VkAllocationCallbacks*                pAllocator,
    VkPipeline*                                 pPipelines) {
	
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    return mvkDev->createPipelines<MVKComputePipeline, VkComputePipelineCreateInfo>(pipelineCache, count, pCreateInfos, pAllocator, pPipelines);
}

MVK_PUBLIC_SYMBOL void vkDestroyPipeline(
    VkDevice                                    device,
	VkPipeline                                  pipeline,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !pipeline ) { return; }
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroyPipeline((MVKPipeline*)pipeline, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreatePipelineLayout(
    VkDevice                                    device,
    const VkPipelineLayoutCreateInfo*           pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkPipelineLayout*                           pPipelineLayout) {

	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKPipelineLayout* mvkPLL = mvkDev->createPipelineLayout(pCreateInfo, pAllocator);
	*pPipelineLayout = (VkPipelineLayout)mvkPLL;
	return mvkPLL->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyPipelineLayout(
    VkDevice                                    device,
	VkPipelineLayout                            pipelineLayout,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !pipelineLayout ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyPipelineLayout((MVKPipelineLayout*)pipelineLayout, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateSampler(
    VkDevice                                    device,
    const VkSamplerCreateInfo*                  pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkSampler*                                  pSampler) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKSampler* mvkSamp = mvkDev->createSampler(pCreateInfo, pAllocator);
	*pSampler = (VkSampler)mvkSamp;
	return mvkSamp->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroySampler(
    VkDevice                                    device,
	VkSampler                                   sampler,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !sampler ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroySampler((MVKSampler*)sampler, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateDescriptorSetLayout(
    VkDevice                                    device,
    const VkDescriptorSetLayoutCreateInfo*      pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
	VkDescriptorSetLayout*                      pSetLayout) {

	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKDescriptorSetLayout* mvkDSL = mvkDev->createDescriptorSetLayout(pCreateInfo, pAllocator);
	*pSetLayout = (VkDescriptorSetLayout)mvkDSL;
	return mvkDSL->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyDescriptorSetLayout(
    VkDevice                                    device,
	VkDescriptorSetLayout                       descriptorSetLayout,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !descriptorSetLayout ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyDescriptorSetLayout((MVKDescriptorSetLayout*)descriptorSetLayout, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateDescriptorPool(
    VkDevice                                    device,
    const VkDescriptorPoolCreateInfo*           pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkDescriptorPool*                           pDescriptorPool) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKDescriptorPool* mvkDP = mvkDev->createDescriptorPool(pCreateInfo, pAllocator);
	*pDescriptorPool = (VkDescriptorPool)mvkDP;
	return mvkDP->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyDescriptorPool(
    VkDevice                                    device,
	VkDescriptorPool                            descriptorPool,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !descriptorPool ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyDescriptorPool((MVKDescriptorPool*)descriptorPool, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkResetDescriptorPool(
	VkDevice                                    device,
	VkDescriptorPool                            descriptorPool,
	VkDescriptorPoolResetFlags                  flags) {

	MVKDescriptorPool* mvkDP = (MVKDescriptorPool*)descriptorPool;
	return mvkDP->reset(flags);
}

MVK_PUBLIC_SYMBOL VkResult vkAllocateDescriptorSets(
	VkDevice                                    device,
	const VkDescriptorSetAllocateInfo*          pAllocateInfo,
	VkDescriptorSet*                            pDescriptorSets) {

	MVKDescriptorPool* mvkDP = (MVKDescriptorPool*)pAllocateInfo->descriptorPool;
	return mvkDP->allocateDescriptorSets(pAllocateInfo->descriptorSetCount,
										 pAllocateInfo->pSetLayouts,
										 pDescriptorSets);
}

MVK_PUBLIC_SYMBOL VkResult vkFreeDescriptorSets(
    VkDevice                                    device,
    VkDescriptorPool                            descriptorPool,
    uint32_t                                    count,
	const VkDescriptorSet*                      pDescriptorSets) {

	MVKDescriptorPool* mvkDP = (MVKDescriptorPool*)descriptorPool;
	return mvkDP->freeDescriptorSets(count, pDescriptorSets);
}

MVK_PUBLIC_SYMBOL void vkUpdateDescriptorSets(
    VkDevice                                    device,
    uint32_t                                    writeCount,
    const VkWriteDescriptorSet*                 pDescriptorWrites,
    uint32_t                                    copyCount,
    const VkCopyDescriptorSet*                  pDescriptorCopies) {
	
	mvkUpdateDescriptorSets(writeCount, pDescriptorWrites, copyCount, pDescriptorCopies);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateFramebuffer(
    VkDevice                                    device,
    const VkFramebufferCreateInfo*              pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkFramebuffer*                              pFramebuffer) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKFramebuffer* mvkFB = mvkDev->createFramebuffer(pCreateInfo, pAllocator);
	*pFramebuffer = (VkFramebuffer)mvkFB;
	return mvkFB->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyFramebuffer(
    VkDevice                                    device,
	VkFramebuffer                               framebuffer,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !framebuffer ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyFramebuffer((MVKFramebuffer*)framebuffer, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkCreateRenderPass(
    VkDevice                                    device,
    const VkRenderPassCreateInfo*               pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkRenderPass*                               pRenderPass) {

	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKRenderPass* mvkRendPass = mvkDev->createRenderPass(pCreateInfo, pAllocator);
	*pRenderPass = (VkRenderPass)mvkRendPass;
	return mvkRendPass->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyRenderPass(
    VkDevice                                    device,
	VkRenderPass                                renderPass,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !renderPass ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyRenderPass((MVKRenderPass*)renderPass, pAllocator);
}

MVK_PUBLIC_SYMBOL void vkGetRenderAreaGranularity(
    VkDevice                                    device,
    VkRenderPass                                renderPass,
    VkExtent2D*                                 pGranularity) {

    if ( !pGranularity ) { return; }

    MVKRenderPass* mvkRendPass = (MVKRenderPass*)renderPass;
    *pGranularity = mvkRendPass->getRenderAreaGranularity();
}

MVK_PUBLIC_SYMBOL VkResult vkCreateCommandPool(
    VkDevice                                    device,
    const VkCommandPoolCreateInfo*              pCreateInfo,
	const VkAllocationCallbacks*                pAllocator,
    VkCommandPool*                              pCmdPool) {
	
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	MVKCommandPool* mvkCmdPool = mvkDev->createCommandPool(pCreateInfo, pAllocator);
	*pCmdPool = (VkCommandPool)mvkCmdPool;
	return mvkCmdPool->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroyCommandPool(
    VkDevice                                    device,
	VkCommandPool                               commandPool,
	const VkAllocationCallbacks*                pAllocator) {

	if ( !commandPool ) { return; }
	MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
	mvkDev->destroyCommandPool((MVKCommandPool*)commandPool, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkResetCommandPool(
	VkDevice                                    device,
	VkCommandPool                               commandPool,
	VkCommandPoolResetFlags                     flags) {

	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)commandPool;
	return mvkCmdPool->reset(flags);
}

MVK_PUBLIC_SYMBOL VkResult vkAllocateCommandBuffers(
	VkDevice                                    device,
	const VkCommandBufferAllocateInfo*          pAllocateInfo,
	VkCommandBuffer*                            pCmdBuffer) {

	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)pAllocateInfo->commandPool;
	return mvkCmdPool->allocateCommandBuffers(pAllocateInfo, pCmdBuffer);
}

MVK_PUBLIC_SYMBOL void vkFreeCommandBuffers(
    VkDevice                                    device,
	VkCommandPool                               commandPool,
	uint32_t                                    commandBufferCount,
	const VkCommandBuffer*                      pCommandBuffers) {

	MVKCommandPool* mvkCmdPool = (MVKCommandPool*)commandPool;
	mvkCmdPool->freeCommandBuffers(commandBufferCount, pCommandBuffers);
}

MVK_PUBLIC_SYMBOL VkResult vkBeginCommandBuffer(
    VkCommandBuffer                             commandBuffer,
    const VkCommandBufferBeginInfo*             pBeginInfo) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	return cmdBuff->begin(pBeginInfo);
}

MVK_PUBLIC_SYMBOL VkResult vkEndCommandBuffer(
    VkCommandBuffer                             commandBuffer) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	return cmdBuff->end();
}

MVK_PUBLIC_SYMBOL VkResult vkResetCommandBuffer(
    VkCommandBuffer                             commandBuffer,
    VkCommandBufferResetFlags                   flags) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	return cmdBuff->reset(flags);
}

MVK_PUBLIC_SYMBOL void vkCmdBindPipeline(
    VkCommandBuffer                             commandBuffer,
    VkPipelineBindPoint                         pipelineBindPoint,
    VkPipeline                                  pipeline) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdBindPipeline(cmdBuff, pipelineBindPoint, pipeline);
}

MVK_PUBLIC_SYMBOL void vkCmdSetViewport(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    firstViewport,
	uint32_t                                    viewportCount,
	const VkViewport*                           pViewports) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdSetViewport(cmdBuff, firstViewport, viewportCount, pViewports);
}

MVK_PUBLIC_SYMBOL void vkCmdSetScissor(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    firstScissor,
	uint32_t                                    scissorCount,
	const VkRect2D*                             pScissors) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdSetScissor(cmdBuff, firstScissor, scissorCount, pScissors);
}

MVK_PUBLIC_SYMBOL void vkCmdSetLineWidth(
	VkCommandBuffer                             commandBuffer,
	float                                       lineWidth) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdSetLineWidth(cmdBuff, lineWidth);
}

MVK_PUBLIC_SYMBOL void vkCmdSetDepthBias(
	VkCommandBuffer                             commandBuffer,
	float                                       depthBiasConstantFactor,
	float                                       depthBiasClamp,
	float                                       depthBiasSlopeFactor) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdSetDepthBias(cmdBuff,depthBiasConstantFactor, depthBiasClamp, depthBiasSlopeFactor);
}

MVK_PUBLIC_SYMBOL void vkCmdSetBlendConstants(
	VkCommandBuffer                             commandBuffer,
	const float                                 blendConst[4]) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdSetBlendConstants(cmdBuff, blendConst);
}

MVK_PUBLIC_SYMBOL void vkCmdSetDepthBounds(
	VkCommandBuffer                             commandBuffer,
	float                                       minDepthBounds,
	float                                       maxDepthBounds) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdSetDepthBounds(cmdBuff, minDepthBounds, maxDepthBounds);
}

MVK_PUBLIC_SYMBOL void vkCmdSetStencilCompareMask(
	VkCommandBuffer                             commandBuffer,
	VkStencilFaceFlags                          faceMask,
	uint32_t                                    stencilCompareMask) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdSetStencilCompareMask(cmdBuff, faceMask, stencilCompareMask);
}

MVK_PUBLIC_SYMBOL void vkCmdSetStencilWriteMask(
	VkCommandBuffer                             commandBuffer,
	VkStencilFaceFlags                          faceMask,
	uint32_t                                    stencilWriteMask) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdSetStencilWriteMask(cmdBuff, faceMask, stencilWriteMask);
}

MVK_PUBLIC_SYMBOL void vkCmdSetStencilReference(
	VkCommandBuffer                             commandBuffer,
	VkStencilFaceFlags                          faceMask,
	uint32_t                                    stencilReference) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdSetStencilReference(cmdBuff, faceMask, stencilReference);
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
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdBindDescriptorSets(cmdBuff, pipelineBindPoint, layout, firstSet, setCount,
							 pDescriptorSets, dynamicOffsetCount, pDynamicOffsets);
}

MVK_PUBLIC_SYMBOL void vkCmdBindIndexBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    VkIndexType                                 indexType) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdBindIndexBuffer(cmdBuff, buffer, offset, indexType);
}

MVK_PUBLIC_SYMBOL void vkCmdBindVertexBuffers(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    startBinding,
    uint32_t                                    bindingCount,
    const VkBuffer*                             pBuffers,
    const VkDeviceSize*                         pOffsets) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdBindVertexBuffers(cmdBuff, startBinding, bindingCount, pBuffers, pOffsets);
}

MVK_PUBLIC_SYMBOL void vkCmdDraw(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    vertexCount,
	uint32_t                                    instanceCount,
	uint32_t                                    firstVertex,
	uint32_t                                    firstInstance) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdDraw(cmdBuff, vertexCount, instanceCount, firstVertex, firstInstance);
}

MVK_PUBLIC_SYMBOL void vkCmdDrawIndexed(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    indexCount,
	uint32_t                                    instanceCount,
	uint32_t                                    firstIndex,
	int32_t                                     vertexOffset,
	uint32_t                                    firstInstance) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdDrawIndexed(cmdBuff, indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
}

MVK_PUBLIC_SYMBOL void vkCmdDrawIndirect(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    uint32_t                                    drawCount,
    uint32_t                                    stride) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdDrawIndirect(cmdBuff, buffer, offset, drawCount, stride);
}

MVK_PUBLIC_SYMBOL void vkCmdDrawIndexedIndirect(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset,
    uint32_t                                    drawCount,
    uint32_t                                    stride) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdDrawIndexedIndirect(cmdBuff, buffer, offset, drawCount, stride);
}

MVK_PUBLIC_SYMBOL void vkCmdDispatch(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    x,
    uint32_t                                    y,
    uint32_t                                    z) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdDispatch(cmdBuff, x, y, z);
}

MVK_PUBLIC_SYMBOL void vkCmdDispatchIndirect(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    buffer,
    VkDeviceSize                                offset) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdDispatchIndirect(cmdBuff, buffer, offset);
}

MVK_PUBLIC_SYMBOL void vkCmdCopyBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    srcBuffer,
    VkBuffer                                    destBuffer,
    uint32_t                                    regionCount,
    const VkBufferCopy*                         pRegions) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdCopyBuffer(cmdBuff, srcBuffer, destBuffer, regionCount, pRegions);
}

MVK_PUBLIC_SYMBOL void vkCmdCopyImage(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     srcImage,
    VkImageLayout                               srcImageLayout,
    VkImage                                     dstImage,
    VkImageLayout                               dstImageLayout,
    uint32_t                                    regionCount,
    const VkImageCopy*                          pRegions) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdCopyImage(cmdBuff,
					srcImage, srcImageLayout,
					dstImage, dstImageLayout,
					regionCount, pRegions);
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
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdBlitImage(cmdBuff,
					srcImage, srcImageLayout,
					dstImage, dstImageLayout,
					regionCount, pRegions, filter);
}

MVK_PUBLIC_SYMBOL void vkCmdCopyBufferToImage(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    srcBuffer,
    VkImage                                     dstImage,
    VkImageLayout                               dstImageLayout,
    uint32_t                                    regionCount,
    const VkBufferImageCopy*                    pRegions) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdCopyBufferToImage(cmdBuff, srcBuffer, dstImage,
                            dstImageLayout, regionCount, pRegions);
}

MVK_PUBLIC_SYMBOL void vkCmdCopyImageToBuffer(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     srcImage,
    VkImageLayout                               srcImageLayout,
    VkBuffer                                    dstBuffer,
    uint32_t                                    regionCount,
    const VkBufferImageCopy*                    pRegions) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdCopyImageToBuffer(cmdBuff, srcImage, srcImageLayout,
                            dstBuffer, regionCount, pRegions);
}

MVK_PUBLIC_SYMBOL void vkCmdUpdateBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    dstBuffer,
    VkDeviceSize                                dstOffset,
    VkDeviceSize                                dataSize,
    const void*                                 pData) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdUpdateBuffer(cmdBuff, dstBuffer, dstOffset, dataSize, pData);
}

MVK_PUBLIC_SYMBOL void vkCmdFillBuffer(
    VkCommandBuffer                             commandBuffer,
    VkBuffer                                    dstBuffer,
    VkDeviceSize                                dstOffset,
    VkDeviceSize                                size,
    uint32_t                                    data) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdFillBuffer(cmdBuff, dstBuffer, dstOffset, size, data);
}

MVK_PUBLIC_SYMBOL void vkCmdClearColorImage(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     image,
    VkImageLayout                               imageLayout,
    const VkClearColorValue*                    pColor,
    uint32_t                                    rangeCount,
    const VkImageSubresourceRange*              pRanges) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdClearImage(cmdBuff, image, imageLayout, pColor, rangeCount, pRanges);
}

MVK_PUBLIC_SYMBOL void vkCmdClearDepthStencilImage(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     image,
    VkImageLayout                               imageLayout,
    const VkClearDepthStencilValue*             pDepthStencil,
    uint32_t                                    rangeCount,
    const VkImageSubresourceRange*              pRanges) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdClearDepthStencilImage(cmdBuff, image, imageLayout, pDepthStencil, rangeCount, pRanges);
}

MVK_PUBLIC_SYMBOL void vkCmdClearAttachments(
	VkCommandBuffer                             commandBuffer,
	uint32_t                                    attachmentCount,
	const VkClearAttachment*                    pAttachments,
	uint32_t                                    rectCount,
	const VkClearRect*                          pRects) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdClearAttachments(cmdBuff, attachmentCount, pAttachments, rectCount, pRects);
}

MVK_PUBLIC_SYMBOL void vkCmdResolveImage(
    VkCommandBuffer                             commandBuffer,
    VkImage                                     srcImage,
    VkImageLayout                               srcImageLayout,
    VkImage                                     dstImage,
    VkImageLayout                               dstImageLayout,
    uint32_t                                    regionCount,
    const VkImageResolve*                       pRegions) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdResolveImage(cmdBuff, srcImage, srcImageLayout,
                       dstImage, dstImageLayout, regionCount, pRegions);
}

MVK_PUBLIC_SYMBOL void vkCmdSetEvent(
    VkCommandBuffer                             commandBuffer,
    VkEvent                                     event,
    VkPipelineStageFlags                        stageMask) {
	
	MVKLogUnimplemented("vkCmdSetEvent");
}

MVK_PUBLIC_SYMBOL void vkCmdResetEvent(
    VkCommandBuffer                             commandBuffer,
    VkEvent                                     event,
    VkPipelineStageFlags                        stageMask) {
	
	MVKLogUnimplemented("vkCmdResetEvent");
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

	MVKLogUnimplemented("vkCmdWaitEvents");
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

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdPipelineBarrier(cmdBuff, srcStageMask, dstStageMask,
						  dependencyFlags, memoryBarrierCount, pMemoryBarriers,
						  bufferMemoryBarrierCount, pBufferMemoryBarriers,
						  imageMemoryBarrierCount, pImageMemoryBarriers);
}

MVK_PUBLIC_SYMBOL void vkCmdBeginQuery(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    query,
    VkQueryControlFlags                         flags) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdBeginQuery(cmdBuff, queryPool, query, flags);
}

MVK_PUBLIC_SYMBOL void vkCmdEndQuery(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    query) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdEndQuery(cmdBuff, queryPool, query);
}

MVK_PUBLIC_SYMBOL void vkCmdResetQueryPool(
    VkCommandBuffer                             commandBuffer,
    VkQueryPool                                 queryPool,
    uint32_t                                    firstQuery,
    uint32_t                                    queryCount) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdResetQueryPool(cmdBuff, queryPool, firstQuery, queryCount);
}

MVK_PUBLIC_SYMBOL void vkCmdWriteTimestamp(
	VkCommandBuffer                             commandBuffer,
	VkPipelineStageFlagBits                     pipelineStage,
	VkQueryPool                                 queryPool,
	uint32_t                                    query) {

    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdWriteTimestamp(cmdBuff, pipelineStage, queryPool, query);
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
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
    mvkCmdCopyQueryPoolResults(cmdBuff, queryPool, firstQuery, queryCount,
                               destBuffer, destOffset, destStride, flags);
}

MVK_PUBLIC_SYMBOL void vkCmdPushConstants(
    VkCommandBuffer                             commandBuffer,
    VkPipelineLayout                            layout,
    VkShaderStageFlags                          stageFlags,
    uint32_t                                    offset,
    uint32_t                                    size,
    const void*                                 pValues) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdPushConstants(cmdBuff, layout, stageFlags, offset, size, pValues);
}

MVK_PUBLIC_SYMBOL void vkCmdBeginRenderPass(
    VkCommandBuffer                             commandBuffer,
    const VkRenderPassBeginInfo*                pRenderPassBegin,
    VkSubpassContents							contents) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdBeginRenderPass(cmdBuff,pRenderPassBegin, contents);
}

MVK_PUBLIC_SYMBOL void vkCmdNextSubpass(
    VkCommandBuffer                             commandBuffer,
    VkSubpassContents							contents) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdNextSubpass(cmdBuff, contents);
}

MVK_PUBLIC_SYMBOL void vkCmdEndRenderPass(
    VkCommandBuffer                             commandBuffer) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdEndRenderPass(cmdBuff);
}

MVK_PUBLIC_SYMBOL void vkCmdExecuteCommands(
    VkCommandBuffer                             commandBuffer,
    uint32_t                                    cmdBuffersCount,
    const VkCommandBuffer*						pCommandBuffers) {
	
    MVKCommandBuffer* cmdBuff = MVKCommandBuffer::getMVKCommandBuffer(commandBuffer);
	mvkCmdExecuteCommands(cmdBuff, cmdBuffersCount, pCommandBuffers);
}


#pragma mark -
#pragma mark VK_KHR_swapchain extension

MVK_PUBLIC_SYMBOL VkResult vkCreateSwapchainKHR(
    VkDevice                                 device,
    const VkSwapchainCreateInfoKHR*          pCreateInfo,
    const VkAllocationCallbacks*             pAllocator,
    VkSwapchainKHR*                          pSwapchain) {

    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    MVKSwapchain* mvkSwpChn = mvkDev->createSwapchain(pCreateInfo, pAllocator);
    *pSwapchain = (VkSwapchainKHR)(mvkSwpChn);
    return mvkSwpChn->getConfigurationResult();
}

MVK_PUBLIC_SYMBOL void vkDestroySwapchainKHR(
    VkDevice                                 device,
    VkSwapchainKHR                           swapchain,
    const VkAllocationCallbacks*             pAllocator) {

	if ( !swapchain ) { return; }
    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    mvkDev->destroySwapchain((MVKSwapchain*)swapchain, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkGetSwapchainImagesKHR(
    VkDevice                                 device,
    VkSwapchainKHR                           swapchain,
    uint32_t*                                pCount,
    VkImage*                                 pSwapchainImages) {

    MVKSwapchain* mvkSwapchain = (MVKSwapchain*)swapchain;
    return mvkSwapchain->getImages(pCount, pSwapchainImages);
}

MVK_PUBLIC_SYMBOL VkResult vkAcquireNextImageKHR(
    VkDevice                                     device,
    VkSwapchainKHR                               swapchain,
    uint64_t                                     timeout,
    VkSemaphore                                  semaphore,
    VkFence                                      fence,
    uint32_t*                                    pImageIndex) {

    MVKSwapchain* mvkSwapchain = (MVKSwapchain*)swapchain;
    return mvkSwapchain->acquireNextImageKHR(timeout, semaphore, fence, pImageIndex);
}

MVK_PUBLIC_SYMBOL VkResult vkQueuePresentKHR(
    VkQueue                                      queue,
    const VkPresentInfoKHR*                      pPresentInfo) {

    MVKQueue* mvkQ = MVKQueue::getMVKQueue(queue);
    return mvkQ->submitPresentKHR(pPresentInfo);
}


#pragma mark -
#pragma mark VK_KHR_surface extension

MVK_PUBLIC_SYMBOL void vkDestroySurfaceKHR(
    VkInstance                                   instance,
    VkSurfaceKHR                                 surface,
    const VkAllocationCallbacks*                 pAllocator) {

	if ( !surface ) { return; }
    MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
    mvkInst->destroySurface((MVKSurface*)surface, pAllocator);
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfaceSupportKHR(
    VkPhysicalDevice                            physicalDevice,
    uint32_t                                    queueFamilyIndex,
    VkSurfaceKHR                                surface,
    VkBool32*                                   pSupported) {

    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    MVKSurface* mvkSrfc = (MVKSurface*)surface;
    return mvkPD->getSurfaceSupport(queueFamilyIndex, mvkSrfc, pSupported);
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    VkPhysicalDevice                            physicalDevice,
    VkSurfaceKHR                                surface,
    VkSurfaceCapabilitiesKHR*                   pSurfaceCapabilities) {

    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    MVKSurface* mvkSrfc = (MVKSurface*)surface;
    return mvkPD->getSurfaceCapabilities(mvkSrfc, pSurfaceCapabilities);
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfaceFormatsKHR(
    VkPhysicalDevice                            physicalDevice,
    VkSurfaceKHR                                surface,
    uint32_t*                                   pSurfaceFormatCount,
    VkSurfaceFormatKHR*                         pSurfaceFormats) {

    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    MVKSurface* mvkSrfc = (MVKSurface*)surface;
    return mvkPD->getSurfaceFormats(mvkSrfc, pSurfaceFormatCount, pSurfaceFormats);
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceSurfacePresentModesKHR(
    VkPhysicalDevice                            physicalDevice,
    VkSurfaceKHR                                surface,
    uint32_t*                                   pPresentModeCount,
    VkPresentModeKHR*                           pPresentModes) {

    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    MVKSurface* mvkSrfc = (MVKSurface*)surface;
    return mvkPD->getSurfacePresentModes(mvkSrfc, pPresentModeCount, pPresentModes);
}


#pragma mark -
#pragma mark iOS & macOS surface extensions

MVK_PUBLIC_SYMBOL VkResult vkCreate_PLATFORM_SurfaceMVK(
    VkInstance                                  instance,
    const Vk_PLATFORM_SurfaceCreateInfoMVK*		pCreateInfo,
    const VkAllocationCallbacks*                pAllocator,
    VkSurfaceKHR*                               pSurface) {

    MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
    MVKSurface* mvkSrfc = mvkInst->createSurface(pCreateInfo, pAllocator);
    *pSurface = (VkSurfaceKHR)mvkSrfc;
    return mvkSrfc->getConfigurationResult();
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

	// This ICD expects to be loaded by a loader of at least version 5.
	if (pSupportedVersion && *pSupportedVersion >= 5) {
		*pSupportedVersion = 5;
		return VK_SUCCESS;
	}

	return VK_ERROR_INCOMPATIBLE_DRIVER;
}

MVK_PUBLIC_SYMBOL PFN_vkVoidFunction vk_icdGetInstanceProcAddr(
	VkInstance                                  instance,
	const char*                                 pName) {

	if (strcmp(pName, "vk_icdNegotiateLoaderICDInterfaceVersion") == 0) { return (PFN_vkVoidFunction)vk_icdNegotiateLoaderICDInterfaceVersion; }
	if (strcmp(pName, "vk_icdGetPhysicalDeviceProcAddr") == 0) { return (PFN_vkVoidFunction)vk_icdGetPhysicalDeviceProcAddr; }

	return vkGetInstanceProcAddr(instance, pName);
}

MVK_PUBLIC_SYMBOL PFN_vkVoidFunction vk_icdGetPhysicalDeviceProcAddr(
	VkInstance                                  instance,
	const char*                                 pName) {

	return vk_icdGetInstanceProcAddr(instance, pName);
}

