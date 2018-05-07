/*
 * vk_mvk_moltenvk.mm
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


#include "vk_mvk_moltenvk.h"
#include "MVKEnvironment.h"
#include "MVKSwapchain.h"
#include "MVKImage.h"
#include <string>

using namespace std;


MVK_PUBLIC_SYMBOL void vkGetMoltenVKDeviceConfigurationMVK(
    VkDevice                                    device,
    MVKDeviceConfiguration*                     pConfiguration) {

    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    if (pConfiguration) { *pConfiguration = mvkDev->_mvkConfig; }
}

MVK_PUBLIC_SYMBOL VkResult vkSetMoltenVKDeviceConfigurationMVK(
    VkDevice                                    device,
    MVKDeviceConfiguration*                     pConfiguration) {

    MVKDevice* mvkDev = MVKDevice::getMVKDevice(device);
    if (pConfiguration) { *(MVKDeviceConfiguration*)&mvkDev->_mvkConfig = *pConfiguration; }
    return VK_SUCCESS;
}

MVK_PUBLIC_SYMBOL void vkGetPhysicalDeviceMetalFeaturesMVK(
    VkPhysicalDevice                            physicalDevice,
    MVKPhysicalDeviceMetalFeatures*             pMetalFeatures) {
    
    MVKPhysicalDevice* mvkPD = MVKPhysicalDevice::getMVKPhysicalDevice(physicalDevice);
    mvkPD->getMetalFeatures(pMetalFeatures);
}

MVK_PUBLIC_SYMBOL void vkGetSwapchainPerformanceMVK(
    VkDevice                                     device,
    VkSwapchainKHR                               swapchain,
    MVKSwapchainPerformance*                     pSwapchainPerf) {

    MVKSwapchain* mvkSwapchain = (MVKSwapchain*)swapchain;
    mvkSwapchain->getPerformanceStatistics(pSwapchainPerf);
}

MVK_PUBLIC_SYMBOL void vkGetPerformanceStatisticsMVK(
    VkDevice                                    device,
    MVKPerformanceStatistics*            		pPerf) {

    MVKDevice::getMVKDevice(device)->getPerformanceStatistics(pPerf);
}

MVK_PUBLIC_SYMBOL void vkGetVersionStringsMVK(
    char* pMoltenVersionStringBuffer,
    uint32_t moltenVersionStringBufferLength,
    char* pVulkanVersionStringBuffer,
    uint32_t vulkanVersionStringBufferLength) {

    size_t len;

    string mvkVer;
    mvkVer += to_string(MVK_VERSION / 10000);
    mvkVer += ".";
    mvkVer += to_string((MVK_VERSION % 10000) / 100);
    mvkVer += ".";
    mvkVer += to_string(MVK_VERSION % 100);
    len = mvkVer.copy(pMoltenVersionStringBuffer, moltenVersionStringBufferLength - 1);
    pMoltenVersionStringBuffer[len] = 0;    // terminator

    string vkVer;
    vkVer += to_string(VK_VERSION_MAJOR(MVK_VULKAN_API_VERSION));
    vkVer += ".";
    vkVer += to_string(VK_VERSION_MINOR(MVK_VULKAN_API_VERSION));
    vkVer += ".";
    vkVer += to_string(VK_VERSION_PATCH(MVK_VULKAN_API_VERSION));
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

// Deprecated license function
MVK_PUBLIC_SYMBOL VkResult vkActivateMoltenVKLicenseMVK(const char* licenseID, const char* licenseKey, VkBool32 acceptLicenseTermsAndConditions) { return VK_SUCCESS; }

