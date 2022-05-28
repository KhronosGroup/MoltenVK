/*
 * vk_mvk_moltenvk.mm
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "vk_mvk_moltenvk.h"
#include "MVKEnvironment.h"
#include "MVKSwapchain.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKFoundation.h"
#include "MVKShaderModule.h"
#include "MVKQueue.h"
#include <string>

using namespace std;

// If pSrc and pDst are not null, copies at most *pCopySize bytes from the contents of the
// source struct to the destination struct, and sets *pCopySize to the number of bytes copied,
// which is the smaller of the original value of *pCopySize and the actual size of the struct.
// Returns VK_SUCCESS if the original value of *pCopySize is the same as the actual size of
// the struct, or VK_INCOMPLETE otherwise. If either pSrc or pDst are null, sets the value
// of *pCopySize to the size of the struct and returns VK_SUCCESS.
template<typename S>
VkResult mvkCopy(S* pDst, const S* pSrc, size_t* pCopySize) {
	if (pSrc && pDst) {
		size_t origSize = *pCopySize;
		*pCopySize = std::min(origSize, sizeof(S));
		memcpy(pDst, pSrc, *pCopySize);
		return (*pCopySize == origSize) ? VK_SUCCESS : VK_INCOMPLETE;
	} else {
		*pCopySize = sizeof(S);
		return VK_SUCCESS;
	}
}

MVK_PUBLIC_SYMBOL VkResult vkGetMoltenVKConfigurationMVK(
	VkInstance                                  ignored,
	MVKConfiguration*                           pConfiguration,
	size_t*                                     pConfigurationSize) {

	return mvkCopy(pConfiguration, &mvkConfig(), pConfigurationSize);
}

MVK_PUBLIC_SYMBOL VkResult vkSetMoltenVKConfigurationMVK(
	VkInstance                                  ignored,
	const MVKConfiguration*                     pConfiguration,
	size_t*                                     pConfigurationSize) {

	// Start with copy of current config, in case incoming is not fully copied
	MVKConfiguration mvkCfg = mvkConfig();
	VkResult rslt = mvkCopy(&mvkCfg, pConfiguration, pConfigurationSize);
	mvkSetConfig(mvkCfg);
	return rslt;
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPhysicalDeviceMetalFeaturesMVK(
	VkPhysicalDevice                            physicalDevice,
	MVKPhysicalDeviceMetalFeatures*             pMetalFeatures,
	size_t*                                     pMetalFeaturesSize) {

	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	return mvkCopy(pMetalFeatures, mvkPD->getMetalFeatures(), pMetalFeaturesSize);
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkGetPerformanceStatisticsMVK(
	VkDevice                                    device,
	MVKPerformanceStatistics*            		pPerf,
	size_t*                                     pPerfSize) {

	MVKPerformanceStatistics mvkPerf;
	MVKDevice::getMVKDevice(device)->getPerformanceStatistics(&mvkPerf);
	return mvkCopy(pPerf, &mvkPerf, pPerfSize);
}

MVK_PUBLIC_SYMBOL void vkGetVersionStringsMVK(
	char*										pMoltenVersionStringBuffer,
	uint32_t									moltenVersionStringBufferLength,
	char*										pVulkanVersionStringBuffer,
	uint32_t									vulkanVersionStringBufferLength) {

	size_t len;

	string mvkVer = mvkGetMoltenVKVersionString(MVK_VERSION);
	len = mvkVer.copy(pMoltenVersionStringBuffer, moltenVersionStringBufferLength - 1);
	pMoltenVersionStringBuffer[len] = 0;    // terminator

	string vkVer = mvkGetVulkanVersionString(mvkConfig().apiVersionToAdvertise);
	len = vkVer.copy(pVulkanVersionStringBuffer, vulkanVersionStringBufferLength - 1);
	pVulkanVersionStringBuffer[len] = 0;    // terminator
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetMTLDeviceMVK(
    VkPhysicalDevice                           physicalDevice,
    id<MTLDevice>*                             pMTLDevice) {

    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    *pMTLDevice = mvkPD->getMTLDevice();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkSetMTLTextureMVK(
    VkImage                                     image,
    id<MTLTexture>                              mtlTexture) {

    MVKImage* mvkImg = (MVKImage*)image;
    return mvkImg->setMTLTexture(0, mtlTexture);
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetMTLTextureMVK(
    VkImage                                     image,
    id<MTLTexture>*                             pMTLTexture) {

    MVKImage* mvkImg = (MVKImage*)image;
    *pMTLTexture = mvkImg->getMTLTexture(0);
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetMTLBufferMVK(
    VkBuffer                                    buffer,
    id<MTLBuffer>*                              pMTLBuffer) {

    MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
    *pMTLBuffer = mvkBuffer->getMTLBuffer();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetMTLCommandQueueMVK(
    VkQueue                                     queue,
    id<MTLCommandQueue>*                        pMTLCommandQueue) {

    MVKQueue* mvkQueue = MVKQueue::getMVKQueue(queue);
    *pMTLCommandQueue = mvkQueue->getMTLCommandQueue();
}

MVK_PUBLIC_VULKAN_SYMBOL VkResult vkUseIOSurfaceMVK(
    VkImage                                     image,
    IOSurfaceRef                                ioSurface) {

    MVKImage* mvkImg = (MVKImage*)image;
    return mvkImg->useIOSurface(ioSurface);
}

MVK_PUBLIC_VULKAN_SYMBOL void vkGetIOSurfaceMVK(
    VkImage                                     image,
    IOSurfaceRef*                               pIOSurface) {

    MVKImage* mvkImg = (MVKImage*)image;
    *pIOSurface = mvkImg->getIOSurface();
}

MVK_PUBLIC_VULKAN_SYMBOL void vkSetWorkgroupSizeMVK(
    VkShaderModule                              shaderModule,
    uint32_t                                    x,
    uint32_t                                    y,
    uint32_t                                    z) {

    MVKShaderModule* mvkShaderModule = (MVKShaderModule*)shaderModule;
    mvkShaderModule->setWorkgroupSize(x, y, z);
}

