/*
 * vk_mvk_moltenvk.mm
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


#include "MVKInstance.h"
#include "vk_mvk_moltenvk.h"
#include "MVKEnvironment.h"
#include "MVKSwapchain.h"
#include "MVKImage.h"
#include "MVKFoundation.h"
#include <string>

using namespace std;

// If pSrc and pDst are not null, copies at most *pCopySize bytes from the contents of the source struct
// to the destination struct, and sets *pCopySize to the number of bytes copied, which is the smaller of
// the original value of *pCopySize and the actual size of the struct. Returns VK_SUCCESS if the original
// value of *pCopySize is the same as the actual size of the struct, or VK_INCOMPLETE otherwise.
// If either pSrc or pDst are null, sets the value of *pCopySize to the size of the struct and returns VK_SUCCESS.
template<typename S>
VkResult mvkCopyStruct(S* pDst, const S* pSrc, size_t* pCopySize) {
	if (pSrc && pDst) {
		size_t origSize = *pCopySize;
		*pCopySize = mvkCopyStruct(pDst, pSrc, origSize);
		return (*pCopySize == origSize) ? VK_SUCCESS : VK_INCOMPLETE;
	} else {
		*pCopySize = sizeof(S);
		return VK_SUCCESS;
	}
}

MVK_PUBLIC_SYMBOL VkResult vkGetMoltenVKConfigurationMVK(
	VkInstance                                  instance,
	MVKConfiguration*                           pConfiguration,
	size_t*                                     pConfigurationSize) {

	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	return mvkCopyStruct(pConfiguration, mvkInst->getMoltenVKConfiguration(), pConfigurationSize);
}

MVK_PUBLIC_SYMBOL VkResult vkSetMoltenVKConfigurationMVK(
	VkInstance                                  instance,
	const MVKConfiguration*                     pConfiguration,
	size_t*                                     pConfigurationSize) {

	MVKInstance* mvkInst = MVKInstance::getMVKInstance(instance);
	return mvkCopyStruct((MVKConfiguration*)mvkInst->getMoltenVKConfiguration(), pConfiguration, pConfigurationSize);
}

MVK_PUBLIC_SYMBOL VkResult vkGetPhysicalDeviceMetalFeaturesMVK(
	VkPhysicalDevice                            physicalDevice,
	MVKPhysicalDeviceMetalFeatures*             pMetalFeatures,
	size_t*                                     pMetalFeaturesSize) {

	MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
	return mvkCopyStruct(pMetalFeatures, mvkPD->getMetalFeatures(), pMetalFeaturesSize);
}

MVK_PUBLIC_SYMBOL VkResult vkGetSwapchainPerformanceMVK(
	VkDevice                                    device,
	VkSwapchainKHR                              swapchain,
	MVKSwapchainPerformance*                    pSwapchainPerf,
	size_t*                                     pSwapchainPerfSize) {

	MVKSwapchain* mvkSC = (MVKSwapchain*)swapchain;
	return mvkCopyStruct(pSwapchainPerf, mvkSC->getPerformanceStatistics(), pSwapchainPerfSize);
}

MVK_PUBLIC_SYMBOL VkResult vkGetPerformanceStatisticsMVK(
	VkDevice                                    device,
	MVKPerformanceStatistics*            		pPerf,
	size_t*                                     pPerfSize) {

	MVKPerformanceStatistics mvkPerf;
	MVKDevice::getMVKDevice(device)->getPerformanceStatistics(&mvkPerf);
	return mvkCopyStruct(pPerf, &mvkPerf, pPerfSize);
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

	string vkVer = mvkGetVulkanVersionString(MVK_VULKAN_API_VERSION);
	len = vkVer.copy(pVulkanVersionStringBuffer, vulkanVersionStringBufferLength - 1);
	pVulkanVersionStringBuffer[len] = 0;    // terminator
}

MVK_PUBLIC_SYMBOL void vkGetMTLDeviceMVK(
    VkPhysicalDevice                           physicalDevice,
    id<MTLDevice>*                             pMTLDevice) {

    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    *pMTLDevice = mvkPD->getMTLDevice();
}

MVK_PUBLIC_SYMBOL VkResult vkSetMTLTextureMVK(
    VkImage                                     image,
    id<MTLTexture>                              mtlTexture) {

    MVKImage* mvkImg = (MVKImage*)image;
    return mvkImg->setMTLTexture(mtlTexture);
}

MVK_PUBLIC_SYMBOL void vkGetMTLTextureMVK(
    VkImage                                     image,
    id<MTLTexture>*                             pMTLTexture) {

    MVKImage* mvkImg = (MVKImage*)image;
    *pMTLTexture = mvkImg->getMTLTexture();
}

MVK_PUBLIC_SYMBOL VkResult vkUseIOSurfaceMVK(
    VkImage                                     image,
    IOSurfaceRef                                ioSurface) {

    MVKImage* mvkImg = (MVKImage*)image;
    return mvkImg->useIOSurface(ioSurface);
}

MVK_PUBLIC_SYMBOL void vkGetIOSurfaceMVK(
    VkImage                                     image,
    IOSurfaceRef*                               pIOSurface) {

    MVKImage* mvkImg = (MVKImage*)image;
    *pIOSurface = mvkImg->getIOSurface();
}
