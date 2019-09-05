/*
 * MVKDevice.mm
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
#include "MVKDevice.h"
#include "MVKQueue.h"
#include "MVKSurface.h"
#include "MVKBuffer.h"
#include "MVKImage.h"
#include "MVKSwapchain.h"
#include "MVKQueryPool.h"
#include "MVKShaderModule.h"
#include "MVKPipeline.h"
#include "MVKFramebuffer.h"
#include "MVKRenderPass.h"
#include "MVKCommandPool.h"
#include "MVKFoundation.h"
#include "MVKCodec.h"
#include "MVKEnvironment.h"
#include "MVKLogging.h"
#include "MVKOSExtensions.h"
#include <MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.h>
#include "vk_mvk_moltenvk.h"
#include <mach/mach_host.h>

#import "CAMetalLayer+MoltenVK.h"

using namespace std;


#if MVK_IOS
#	include <UIKit/UIKit.h>
#	define MVKViewClass		UIView
#endif
#if MVK_MACOS
#	include <AppKit/AppKit.h>
#	define MVKViewClass		NSView
#endif


#pragma mark -
#pragma mark MVKPhysicalDevice

VkResult MVKPhysicalDevice::getExtensionProperties(const char* pLayerName, uint32_t* pCount, VkExtensionProperties* pProperties) {
	return _supportedExtensions.getProperties(pCount, pProperties);
}

void MVKPhysicalDevice::getFeatures(VkPhysicalDeviceFeatures* features) {
    if (features) { *features = _features; }
}

void MVKPhysicalDevice::getFeatures(VkPhysicalDeviceFeatures2* features) {
    if (features) {
        features->sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        features->features = _features;
        for (auto* next = (VkBaseOutStructure*)features->pNext; next; next = next->pNext) {
            switch ((uint32_t)next->sType) {
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES: {
                    auto* storageFeatures = (VkPhysicalDevice16BitStorageFeatures*)next;
                    storageFeatures->storageBuffer16BitAccess = true;
                    storageFeatures->uniformAndStorageBuffer16BitAccess = true;
                    storageFeatures->storagePushConstant16 = true;
                    storageFeatures->storageInputOutput16 = true;
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_8BIT_STORAGE_FEATURES_KHR: {
                    auto* storageFeatures = (VkPhysicalDevice8BitStorageFeaturesKHR*)next;
                    storageFeatures->storageBuffer8BitAccess = true;
                    storageFeatures->uniformAndStorageBuffer8BitAccess = true;
                    storageFeatures->storagePushConstant8 = true;
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT16_INT8_FEATURES_KHR: {
                    auto* f16Features = (VkPhysicalDeviceFloat16Int8FeaturesKHR*)next;
                    f16Features->shaderFloat16 = true;
                    f16Features->shaderInt8 = true;
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_UNIFORM_BUFFER_STANDARD_LAYOUT_FEATURES_KHR: {
                    auto* uboLayoutFeatures = (VkPhysicalDeviceUniformBufferStandardLayoutFeaturesKHR*)next;
                    uboLayoutFeatures->uniformBufferStandardLayout = true;
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VARIABLE_POINTER_FEATURES: {
                    auto* varPtrFeatures = (VkPhysicalDeviceVariablePointerFeatures*)next;
                    varPtrFeatures->variablePointersStorageBuffer = true;
                    varPtrFeatures->variablePointers = true;
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES_EXT: {
                    auto* hostQueryResetFeatures = (VkPhysicalDeviceHostQueryResetFeaturesEXT*)next;
                    hostQueryResetFeatures->hostQueryReset = true;
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES_EXT: {
                    auto* scalarLayoutFeatures = (VkPhysicalDeviceScalarBlockLayoutFeaturesEXT*)next;
                    scalarLayoutFeatures->scalarBlockLayout = true;
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXEL_BUFFER_ALIGNMENT_FEATURES_EXT: {
                    auto* texelBuffAlignFeatures = (VkPhysicalDeviceTexelBufferAlignmentFeaturesEXT*)next;
                    texelBuffAlignFeatures->texelBufferAlignment = _metalFeatures.texelBuffers && [_mtlDevice respondsToSelector: @selector(minimumLinearTextureAlignmentForPixelFormat:)];
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VERTEX_ATTRIBUTE_DIVISOR_FEATURES_EXT: {
                    auto* divisorFeatures = (VkPhysicalDeviceVertexAttributeDivisorFeaturesEXT*)next;
                    divisorFeatures->vertexAttributeInstanceRateDivisor = true;
                    divisorFeatures->vertexAttributeInstanceRateZeroDivisor = true;
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_EXTX: {
                    auto* portabilityFeatures = (VkPhysicalDevicePortabilitySubsetFeaturesEXTX*)next;
                    portabilityFeatures->triangleFans = false;
                    portabilityFeatures->separateStencilMaskRef = true;
                    portabilityFeatures->events = true;
                    portabilityFeatures->standardImageViews = _mvkInstance->getMoltenVKConfiguration()->fullImageViewSwizzle;
                    portabilityFeatures->samplerMipLodBias = false;
                    break;
                }
                case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_INTEGER_FUNCTIONS2_FEATURES_INTEL: {
                    auto* shaderIntFuncsFeatures = (VkPhysicalDeviceShaderIntegerFunctions2INTEL*)next;
                    shaderIntFuncsFeatures->shaderIntegerFunctions2 = true;
                    break;
                }
                default:
                    break;
            }
        }
    }
}

void MVKPhysicalDevice::getProperties(VkPhysicalDeviceProperties* properties) {
    if (properties) { *properties = _properties; }
}

void MVKPhysicalDevice::getProperties(VkPhysicalDeviceProperties2* properties) {
    if (properties) {
        properties->sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
        properties->properties = _properties;
		for (auto* next = (VkBaseOutStructure*)properties->pNext; next; next = next->pNext) {
			switch ((uint32_t)next->sType) {
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_POINT_CLIPPING_PROPERTIES: {
                auto* pointClipProps = (VkPhysicalDevicePointClippingProperties*)next;
                pointClipProps->pointClippingBehavior = VK_POINT_CLIPPING_BEHAVIOR_ALL_CLIP_PLANES;
                break;
            }
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_3_PROPERTIES: {
                auto* maint3Props = (VkPhysicalDeviceMaintenance3Properties*)next;
                maint3Props->maxPerSetDescriptors = (_metalFeatures.maxPerStageBufferCount + _metalFeatures.maxPerStageTextureCount + _metalFeatures.maxPerStageSamplerCount) * 4;
                maint3Props->maxMemoryAllocationSize = _metalFeatures.maxMTLBufferSize;
                break;
            }
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PUSH_DESCRIPTOR_PROPERTIES_KHR: {
                auto* pushDescProps = (VkPhysicalDevicePushDescriptorPropertiesKHR*)next;
                pushDescProps->maxPushDescriptors = _properties.limits.maxPerStageResources;
                break;
            }
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXEL_BUFFER_ALIGNMENT_PROPERTIES_EXT: {
                auto* texelBuffAlignProps = (VkPhysicalDeviceTexelBufferAlignmentPropertiesEXT*)next;
                // Save the 'next' pointer; we'll unintentionally overwrite it
                // on the next line. Put it back when we're done.
                void* savedNext = texelBuffAlignProps->pNext;
                *texelBuffAlignProps = _texelBuffAlignProperties;
                texelBuffAlignProps->pNext = savedNext;
                break;
            }
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VERTEX_ATTRIBUTE_DIVISOR_PROPERTIES_EXT: {
                auto* divisorProps = (VkPhysicalDeviceVertexAttributeDivisorPropertiesEXT*)next;
                divisorProps->maxVertexAttribDivisor = kMVKUndefinedLargeUInt32;
                break;
            }
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_PROPERTIES_EXTX: {
				auto* portabilityProps = (VkPhysicalDevicePortabilitySubsetPropertiesEXTX*)next;
				portabilityProps->minVertexInputBindingStrideAlignment = 4;
				break;
			}
            default:
                break;
            }
        }
    }
}

bool MVKPhysicalDevice::getFormatIsSupported(VkFormat format) {

	if ( !mvkVkFormatIsSupported(format) ) { return false; }

	// Special-case certain formats that not all GPU's support.
#if MVK_MACOS
	switch (mvkMTLPixelFormatFromVkFormat(format)) {
		case MTLPixelFormatDepth24Unorm_Stencil8:
			return getMTLDevice().isDepth24Stencil8PixelFormatSupported;
			break;

		default:
			break;
	}
#endif

	return true;
}

void MVKPhysicalDevice::getFormatProperties(VkFormat format, VkFormatProperties* pFormatProperties) {
    if (pFormatProperties) {
		*pFormatProperties = mvkVkFormatProperties(format, getFormatIsSupported(format));
	}
}

void MVKPhysicalDevice::getFormatProperties(VkFormat format,
                                            VkFormatProperties2KHR* pFormatProperties) {
	if (pFormatProperties) {
		pFormatProperties->sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2_KHR;
		pFormatProperties->formatProperties = mvkVkFormatProperties(format, getFormatIsSupported(format));
	}
}

VkResult MVKPhysicalDevice::getImageFormatProperties(VkFormat format,
                                                     VkImageType type,
                                                     VkImageTiling tiling,
                                                     VkImageUsageFlags usage,
                                                     VkImageCreateFlags flags,
                                                     VkImageFormatProperties* pImageFormatProperties) {

	if ( !getFormatIsSupported(format) ) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

	if ( !pImageFormatProperties ) { return VK_SUCCESS; }

	// Metal does not support creating uncompressed views of compressed formats.
	// Metal does not support split-instance images.
	if (mvkIsAnyFlagEnabled(flags, VK_IMAGE_CREATE_BLOCK_TEXEL_VIEW_COMPATIBLE_BIT | VK_IMAGE_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT)) {
		return VK_ERROR_FORMAT_NOT_SUPPORTED;
	}

	MVKFormatType mvkFmt = mvkFormatTypeFromVkFormat(format);
	bool hasAttachmentUsage = mvkIsAnyFlagEnabled(usage, (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
														  VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
														  VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT |
														  VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT));

    VkPhysicalDeviceLimits* pLimits = &_properties.limits;
    VkExtent3D maxExt;
	uint32_t maxLevels;
	uint32_t maxLayers = hasAttachmentUsage ? pLimits->maxFramebufferLayers : pLimits->maxImageArrayLayers;

	VkSampleCountFlags sampleCounts = _metalFeatures.supportedSampleCounts;
    switch (type) {
        case VK_IMAGE_TYPE_1D:
			// Metal does not allow 1D textures to be used as attachments
			if (hasAttachmentUsage) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

			// Metal does not allow linear tiling on 1D textures
			if (tiling == VK_IMAGE_TILING_LINEAR) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

			// Metal does not allow compressed or depth/stencil formats on 1D textures
			if (mvkFmt == kMVKFormatDepthStencil || mvkFmt == kMVKFormatCompressed) {
				return VK_ERROR_FORMAT_NOT_SUPPORTED;
			}
            maxExt.width = pLimits->maxImageDimension1D;
            maxExt.height = 1;
            maxExt.depth = 1;
			maxLevels = 1;
            sampleCounts = VK_SAMPLE_COUNT_1_BIT;
            break;
        case VK_IMAGE_TYPE_2D:
            if (mvkIsAnyFlagEnabled(flags, VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT) ) {
                maxExt.width = pLimits->maxImageDimensionCube;
                maxExt.height = pLimits->maxImageDimensionCube;
            } else {
                maxExt.width = pLimits->maxImageDimension2D;
                maxExt.height = pLimits->maxImageDimension2D;
            }
            maxExt.depth = 1;
			if (tiling == VK_IMAGE_TILING_LINEAR) {
				// Linear textures have additional restrictions under Metal:
				// - They may not be depth/stencil or compressed textures.
				if (mvkFmt == kMVKFormatDepthStencil || mvkFmt == kMVKFormatCompressed) {
					return VK_ERROR_FORMAT_NOT_SUPPORTED;
				}
#if MVK_MACOS
				// - On macOS, Linear textures may not be used as framebuffer attachments.
				if (hasAttachmentUsage) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }
#endif
				// Linear textures may only have one mip level. layer & sample
				maxLevels = 1;
				maxLayers = 1;
				sampleCounts = VK_SAMPLE_COUNT_1_BIT;
			} else {
				VkFormatProperties fmtProps;
				getFormatProperties(format, &fmtProps);
				// Compressed multisampled textures aren't supported.
				// Multisampled cube textures aren't supported.
				// Non-renderable multisampled textures aren't supported.
				if (mvkFmt == kMVKFormatCompressed ||
					mvkIsAnyFlagEnabled(flags, VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT) ||
					!mvkIsAnyFlagEnabled(fmtProps.optimalTilingFeatures, VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT|VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) ) {
					sampleCounts = VK_SAMPLE_COUNT_1_BIT;
				}
				maxLevels = mvkMipmapLevels3D(maxExt);
			}
            break;
        case VK_IMAGE_TYPE_3D:
            // Metal does not allow linear tiling on 3D textures
            if (tiling == VK_IMAGE_TILING_LINEAR) {
                return VK_ERROR_FORMAT_NOT_SUPPORTED;
            }
			// Metal does not allow compressed or depth/stencil formats on 3D textures
			if (mvkFmt == kMVKFormatDepthStencil
#if MVK_IOS
				|| mvkFmt == kMVKFormatCompressed
#endif
				) {
				return VK_ERROR_FORMAT_NOT_SUPPORTED;
			}
#if MVK_MACOS
			// If this is a compressed format and there's no codec, it isn't supported.
			if ((mvkFmt == kMVKFormatCompressed) && !mvkCanDecodeFormat(format)) {
				return VK_ERROR_FORMAT_NOT_SUPPORTED;
			}
#endif
            maxExt.width = pLimits->maxImageDimension3D;
            maxExt.height = pLimits->maxImageDimension3D;
            maxExt.depth = pLimits->maxImageDimension3D;
			maxLevels = mvkMipmapLevels3D(maxExt);
            maxLayers = 1;
            sampleCounts = VK_SAMPLE_COUNT_1_BIT;
            break;
        default:
			// Metal does not allow linear tiling on anything but 2D textures
			if (tiling == VK_IMAGE_TILING_LINEAR) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

			// Metal does not allow compressed or depth/stencil formats on anything but 2D textures
			if (mvkFmt == kMVKFormatDepthStencil || mvkFmt == kMVKFormatCompressed) {
				return VK_ERROR_FORMAT_NOT_SUPPORTED;
			}
            maxExt = { 1, 1, 1};
            maxLayers = 1;
			maxLevels = 1;
			sampleCounts = VK_SAMPLE_COUNT_1_BIT;
            break;
    }

    pImageFormatProperties->maxExtent = maxExt;
    pImageFormatProperties->maxMipLevels = maxLevels;
    pImageFormatProperties->maxArrayLayers = maxLayers;
    pImageFormatProperties->sampleCounts = sampleCounts;
    pImageFormatProperties->maxResourceSize = kMVKUndefinedLargeUInt64;

    return VK_SUCCESS;
}

VkResult MVKPhysicalDevice::getImageFormatProperties(const VkPhysicalDeviceImageFormatInfo2KHR *pImageFormatInfo,
                                                     VkImageFormatProperties2KHR* pImageFormatProperties) {

    if ( !pImageFormatInfo || pImageFormatInfo->sType != VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2_KHR ) {
        return VK_ERROR_FORMAT_NOT_SUPPORTED;
    }

    if ( !getFormatIsSupported(pImageFormatInfo->format) ) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

	if ( !getImageViewIsSupported(pImageFormatInfo) ) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

	if (pImageFormatProperties) {
		pImageFormatProperties->sType = VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2_KHR;
		return getImageFormatProperties(pImageFormatInfo->format, pImageFormatInfo->type,
										pImageFormatInfo->tiling, pImageFormatInfo->usage,
										pImageFormatInfo->flags,
										&pImageFormatProperties->imageFormatProperties);
	}

	return VK_SUCCESS;
}

// If the image format info links portability image view info, test if an image view of that configuration is supported
bool MVKPhysicalDevice::getImageViewIsSupported(const VkPhysicalDeviceImageFormatInfo2KHR *pImageFormatInfo) {
	auto* next = (VkStructureType*)pImageFormatInfo->pNext;
	while (next) {
		switch ((int32_t)*next) {
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_VIEW_SUPPORT_EXTX: {
				auto* portImgViewInfo = (VkPhysicalDeviceImageViewSupportEXTX*)next;

				// Create an image view and test whether it could be configured
				VkImageViewCreateInfo viewInfo = {
					.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
					.pNext = (VkStructureType*)portImgViewInfo->pNext,
					.flags = portImgViewInfo->flags,
					.image = VK_NULL_HANDLE,
					.viewType = portImgViewInfo->viewType,
					.format = portImgViewInfo->format,
					.components = portImgViewInfo->components,
					.subresourceRange = {
						.aspectMask = portImgViewInfo->aspectMask,
						.baseMipLevel = 0,
						.levelCount = 1,
						.baseArrayLayer = 0,
						.layerCount = 1},
				};
				MVKImageView imgView(VK_NULL_HANDLE, &viewInfo, _mvkInstance->getMoltenVKConfiguration());
				return imgView.getConfigurationResult() == VK_SUCCESS;
			}
			default:
				next = (VkStructureType*)((VkPhysicalDeviceFeatures2*)next)->pNext;
				break;
		}
	}

	return true;
}


#pragma mark Surfaces

VkResult MVKPhysicalDevice::getSurfaceSupport(uint32_t queueFamilyIndex,
											  MVKSurface* surface,
											  VkBool32* pSupported) {
    // Check whether this is a headless device
    bool isHeadless = false;
#if MVK_MACOS
    isHeadless = getMTLDevice().isHeadless;
#endif
    
	// If this device is headless or the surface does not have a CAMetalLayer, it is not supported.
    *pSupported = !(isHeadless || (surface->getCAMetalLayer() == nil));
	return *pSupported ? VK_SUCCESS : surface->getConfigurationResult();
}

VkResult MVKPhysicalDevice::getSurfaceCapabilities(MVKSurface* surface,
												   VkSurfaceCapabilitiesKHR* pSurfaceCapabilities) {

	// The layer underlying the surface view must be a CAMetalLayer.
	CAMetalLayer* mtlLayer = surface->getCAMetalLayer();
	if ( !mtlLayer ) { return surface->getConfigurationResult(); }

    VkExtent2D surfExtnt = mvkVkExtent2DFromCGSize(mtlLayer.naturalDrawableSizeMVK);

	pSurfaceCapabilities->minImageCount = _metalFeatures.minSwapchainImageCount;
	pSurfaceCapabilities->maxImageCount = _metalFeatures.maxSwapchainImageCount;

	pSurfaceCapabilities->currentExtent = surfExtnt;
	pSurfaceCapabilities->minImageExtent = surfExtnt;
	pSurfaceCapabilities->maxImageExtent = surfExtnt;
    pSurfaceCapabilities->maxImageArrayLayers = 1;
	pSurfaceCapabilities->supportedTransforms = (VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR);
	pSurfaceCapabilities->currentTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
    pSurfaceCapabilities->supportedCompositeAlpha = (VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR |
                                                     VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR |
                                                     VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR);
	pSurfaceCapabilities->supportedUsageFlags = (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                                                 VK_IMAGE_USAGE_STORAGE_BIT |
                                                 VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
												 VK_IMAGE_USAGE_TRANSFER_DST_BIT |
												 VK_IMAGE_USAGE_SAMPLED_BIT);
	return VK_SUCCESS;
}

VkResult MVKPhysicalDevice::getSurfaceFormats(MVKSurface* surface,
											  uint32_t* pCount,
											  VkSurfaceFormatKHR* pSurfaceFormats) {

	// The layer underlying the surface view must be a CAMetalLayer.
	CAMetalLayer* mtlLayer = surface->getCAMetalLayer();
	if ( !mtlLayer ) { return surface->getConfigurationResult(); }

	const MTLPixelFormat mtlFormats[] = {
		MTLPixelFormatBGRA8Unorm,
		MTLPixelFormatBGRA8Unorm_sRGB,
		MTLPixelFormatRGBA16Float,
		MTLPixelFormatBGR10A2Unorm,
	};

	MVKVectorInline<VkColorSpaceKHR, 16> colorSpaces;
	colorSpaces.push_back(VK_COLOR_SPACE_SRGB_NONLINEAR_KHR);
#if MVK_MACOS
	if (getInstance()->_enabledExtensions.vk_EXT_swapchain_colorspace.enabled) {
		// 10.11 supports some but not all of the color spaces specified by VK_EXT_swapchain_colorspace.
		colorSpaces.push_back(VK_COLOR_SPACE_DISPLAY_P3_NONLINEAR_EXT);
		colorSpaces.push_back(VK_COLOR_SPACE_DCI_P3_NONLINEAR_EXT);
		colorSpaces.push_back(VK_COLOR_SPACE_BT709_NONLINEAR_EXT);
		colorSpaces.push_back(VK_COLOR_SPACE_ADOBERGB_NONLINEAR_EXT);
		colorSpaces.push_back(VK_COLOR_SPACE_PASS_THROUGH_EXT);
		if (mvkOSVersion() >= 10.12) {
			colorSpaces.push_back(VK_COLOR_SPACE_EXTENDED_SRGB_LINEAR_EXT);
			colorSpaces.push_back(VK_COLOR_SPACE_EXTENDED_SRGB_NONLINEAR_EXT);
		}
	}
#endif

	uint mtlFmtsCnt = sizeof(mtlFormats) / sizeof(MTLPixelFormat);
	if (!mvkMTLPixelFormatIsSupported(MTLPixelFormatBGR10A2Unorm)) { mtlFmtsCnt--; }

	const uint vkFmtsCnt = mtlFmtsCnt * (uint)colorSpaces.size();

	// If properties aren't actually being requested yet, simply update the returned count
	if ( !pSurfaceFormats ) {
		*pCount = vkFmtsCnt;
		return VK_SUCCESS;
	}

	// Determine how many results we'll return, and return that number
	VkResult result = (*pCount >= vkFmtsCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(*pCount, vkFmtsCnt);

	// Now populate the supplied array
	for (uint csIdx = 0, idx = 0; idx < *pCount && csIdx < colorSpaces.size(); csIdx++) {
		for (uint fmtIdx = 0; idx < *pCount && fmtIdx < mtlFmtsCnt; fmtIdx++, idx++) {
			pSurfaceFormats[idx].format = mvkVkFormatFromMTLPixelFormat(mtlFormats[fmtIdx]);
			pSurfaceFormats[idx].colorSpace = colorSpaces[csIdx];
		}
	}

	return result;
}

VkResult MVKPhysicalDevice::getSurfaceFormats(MVKSurface* surface,
											  uint32_t* pCount,
											  VkSurfaceFormat2KHR* pSurfaceFormats) {
	VkResult rslt;
	if (pSurfaceFormats) {
		// Populate temp array of VkSurfaceFormatKHR then copy into array of VkSurfaceFormat2KHR.
		// The value of *pCount may be reduced during call, but will always be <= size of temp array.
		VkSurfaceFormatKHR surfFmts[*pCount];
		rslt = getSurfaceFormats(surface, pCount, surfFmts);
		for (uint32_t fmtIdx = 0; fmtIdx < *pCount; fmtIdx++) {
			auto pSF = &pSurfaceFormats[fmtIdx];
			pSF->sType = VK_STRUCTURE_TYPE_SURFACE_FORMAT_2_KHR;
			pSF->pNext = nullptr;
			pSF->surfaceFormat = surfFmts[fmtIdx];
		}
	} else {
		rslt = getSurfaceFormats(surface, pCount, (VkSurfaceFormatKHR*)nullptr);
	}
	return rslt;
}

VkResult MVKPhysicalDevice::getSurfacePresentModes(MVKSurface* surface,
												   uint32_t* pCount,
												   VkPresentModeKHR* pPresentModes) {

	// The layer underlying the surface view must be a CAMetalLayer.
	CAMetalLayer* mtlLayer = surface->getCAMetalLayer();
	if ( !mtlLayer ) { return surface->getConfigurationResult(); }

#define ADD_VK_PRESENT_MODE(VK_PM)																	\
	do {																							\
		if (pPresentModes && presentModesCnt < *pCount) { pPresentModes[presentModesCnt] = VK_PM; }	\
		presentModesCnt++;																			\
	} while(false)

	uint32_t presentModesCnt = 0;

	ADD_VK_PRESENT_MODE(VK_PRESENT_MODE_FIFO_KHR);

	if (_metalFeatures.presentModeImmediate) {
		ADD_VK_PRESENT_MODE(VK_PRESENT_MODE_IMMEDIATE_KHR);
	}

	if (pPresentModes && *pCount < presentModesCnt) {
		return VK_INCOMPLETE;
	}

	*pCount = presentModesCnt;
	return VK_SUCCESS;
}

VkResult MVKPhysicalDevice::getPresentRectangles(MVKSurface* surface,
												 uint32_t* pRectCount,
												 VkRect2D* pRects) {

	// The layer underlying the surface view must be a CAMetalLayer.
	CAMetalLayer* mtlLayer = surface->getCAMetalLayer();
	if ( !mtlLayer ) { return surface->getConfigurationResult(); }

	if ( !pRects ) {
		*pRectCount = 1;
		return VK_SUCCESS;
	}

	if (*pRectCount == 0) { return VK_INCOMPLETE; }

	*pRectCount = 1;

	pRects[0].offset = { 0, 0 };
	pRects[0].extent = mvkVkExtent2DFromCGSize(mtlLayer.naturalDrawableSizeMVK);

	return VK_SUCCESS;
}


#pragma mark Queues

// Returns the queue families supported by this instance, lazily creating them if necessary.
// Metal does not distinguish functionality between queues, which would normally lead us
// to create only only one general-purpose queue family. However, Vulkan associates command
// buffers with a queue family, whereas Metal associates command buffers with a Metal queue.
// In order to allow a Metal command buffer to be prefilled before it is formally submitted to
// a Vulkan queue, we need to enforce that each Vulkan queue family can have only one Metal queue.
// In order to provide parallel queue operations, we therefore provide multiple queue families.
// In addition, Metal queues are always general purpose, so the default behaviour is for all
// queue families to support graphics + compute + transfer, unless the app indicates it
// requires queue family specialization.
MVKVector<MVKQueueFamily*>& MVKPhysicalDevice::getQueueFamilies() {
	if (_queueFamilies.empty()) {
		VkQueueFamilyProperties qfProps;
		bool specialize = _mvkInstance->getMoltenVKConfiguration()->specializedQueueFamilies;
		uint32_t qfIdx = 0;

		qfProps.queueCount = kMVKQueueCountPerQueueFamily;
		qfProps.timestampValidBits = 64;
		qfProps.minImageTransferGranularity = { 1, 1, 1};

		// General-purpose queue family
		qfProps.queueFlags = (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT);
		_queueFamilies.push_back(new MVKQueueFamily(this, qfIdx++, &qfProps));

		// Dedicated graphics queue family...or another general-purpose queue family.
		if (specialize) { qfProps.queueFlags = (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_TRANSFER_BIT); }
		_queueFamilies.push_back(new MVKQueueFamily(this, qfIdx++, &qfProps));

		// Dedicated compute queue family...or another general-purpose queue family.
		if (specialize) { qfProps.queueFlags = (VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT); }
		_queueFamilies.push_back(new MVKQueueFamily(this, qfIdx++, &qfProps));

		// Dedicated transfer queue family...or another general-purpose queue family.
		if (specialize) { qfProps.queueFlags = VK_QUEUE_TRANSFER_BIT; }
		_queueFamilies.push_back(new MVKQueueFamily(this, qfIdx++, &qfProps));

		MVKAssert(kMVKQueueFamilyCount >= _queueFamilies.size(), "Adjust value of kMVKQueueFamilyCount.");
	}
	return _queueFamilies;
}

VkResult MVKPhysicalDevice::getQueueFamilyProperties(uint32_t* pCount,
													 VkQueueFamilyProperties* pQueueFamilyProperties) {

	auto& qFams = getQueueFamilies();
	uint32_t qfCnt = uint32_t(qFams.size());

	// If properties aren't actually being requested yet, simply update the returned count
	if ( !pQueueFamilyProperties ) {
		*pCount = qfCnt;
		return VK_SUCCESS;
	}

	// Determine how many families we'll return, and return that number
	VkResult rslt = (*pCount >= qfCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(*pCount, qfCnt);

	// Now populate the queue families
	if (pQueueFamilyProperties) {
		for (uint32_t qfIdx = 0; qfIdx < *pCount; qfIdx++) {
			qFams[qfIdx]->getProperties(&pQueueFamilyProperties[qfIdx]);
		}
	}

	return rslt;
}

VkResult MVKPhysicalDevice::getQueueFamilyProperties(uint32_t* pCount,
													 VkQueueFamilyProperties2KHR* pQueueFamilyProperties) {

	VkResult rslt;
	if (pQueueFamilyProperties) {
		// Populate temp array of VkQueueFamilyProperties then copy into array of VkQueueFamilyProperties2KHR.
		// The value of *pCount may be reduced during call, but will always be <= size of temp array.
		VkQueueFamilyProperties qProps[*pCount];
		rslt = getQueueFamilyProperties(pCount, qProps);
		for (uint32_t qpIdx = 0; qpIdx < *pCount; qpIdx++) {
			auto pQP = &pQueueFamilyProperties[qpIdx];
			pQP->sType = VK_STRUCTURE_TYPE_QUEUE_FAMILY_PROPERTIES_2_KHR;
			pQP->pNext = nullptr;
			pQP->queueFamilyProperties = qProps[qpIdx];
		}
	} else {
		rslt = getQueueFamilyProperties(pCount, (VkQueueFamilyProperties*)nullptr);
	}
	return rslt;
}


#pragma mark Memory models

/** Populates the specified memory properties with the memory characteristics of this device. */
VkResult MVKPhysicalDevice::getPhysicalDeviceMemoryProperties(VkPhysicalDeviceMemoryProperties* pMemoryProperties) {
	*pMemoryProperties = _memoryProperties;
	return VK_SUCCESS;
}

VkResult MVKPhysicalDevice::getPhysicalDeviceMemoryProperties(VkPhysicalDeviceMemoryProperties2* pMemoryProperties) {
	if (pMemoryProperties) {
		pMemoryProperties->sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2;
		pMemoryProperties->memoryProperties = _memoryProperties;
		auto* next = (MVKVkAPIStructHeader*)pMemoryProperties->pNext;
		while (next) {
			switch ((uint32_t)next->sType) {
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT: {
				auto* budgetProps = (VkPhysicalDeviceMemoryBudgetPropertiesEXT*)next;
				memset(budgetProps->heapBudget, 0, sizeof(budgetProps->heapBudget));
				memset(budgetProps->heapUsage, 0, sizeof(budgetProps->heapUsage));
				budgetProps->heapBudget[0] = (VkDeviceSize)mvkRecommendedMaxWorkingSetSize(_mtlDevice);
				if ( [_mtlDevice respondsToSelector: @selector(currentAllocatedSize)] ) {
					budgetProps->heapUsage[0] = (VkDeviceSize)_mtlDevice.currentAllocatedSize;
				}
				next = (MVKVkAPIStructHeader*)budgetProps->pNext;
				break;
			}
			default:
				next = (MVKVkAPIStructHeader*)next->pNext;
				break;
			}
		}
	}
	return VK_SUCCESS;
}


#pragma mark Construction

MVKPhysicalDevice::MVKPhysicalDevice(MVKInstance* mvkInstance, id<MTLDevice> mtlDevice) : _supportedExtensions(this, true) {
	_mvkInstance = mvkInstance;
	_mtlDevice = [mtlDevice retain];

	initMetalFeatures();        // Call first.
	initFeatures();             // Call second.
	initProperties();           // Call third.
	initMemoryProperties();
	initExtensions();
	logGPUInfo();
}

/** Initializes the Metal-specific physical device features of this instance. */
void MVKPhysicalDevice::initMetalFeatures() {
	memset(&_metalFeatures, 0, sizeof(_metalFeatures));	// Start with everything cleared

	_metalFeatures.maxPerStageBufferCount = 31;
    _metalFeatures.maxMTLBufferSize = (256 * MEBI);
    _metalFeatures.dynamicMTLBuffers = false;

    _metalFeatures.maxPerStageSamplerCount = 16;
    _metalFeatures.maxQueryBufferSize = (64 * KIBI);

	_metalFeatures.ioSurfaces = MVK_SUPPORT_IOSURFACE_BOOL;

	// Metal supports 2 or 3 concurrent CAMetalLayer drawables.
	_metalFeatures.minSwapchainImageCount = kMVKMinSwapchainImageCount;
	_metalFeatures.maxSwapchainImageCount = kMVKMaxSwapchainImageCount;

#if MVK_IOS
	_metalFeatures.mslVersionEnum = MTLLanguageVersion1_0;
    _metalFeatures.maxPerStageTextureCount = 31;
    _metalFeatures.mtlBufferAlignment = 64;
	_metalFeatures.mtlCopyBufferAlignment = 1;
    _metalFeatures.texelBuffers = true;
	_metalFeatures.maxTextureDimension = (4 * KIBI);

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v2] ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion1_1;
        _metalFeatures.dynamicMTLBuffers = true;
		_metalFeatures.maxTextureDimension = (8 * KIBI);
    }

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v3] ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion1_2;
        _metalFeatures.shaderSpecialization = true;
        _metalFeatures.stencilViews = true;
		_metalFeatures.fences = true;
    }

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v4] ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_0;
    }

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v5] ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_1;
		_metalFeatures.events = true;
		_metalFeatures.textureBuffers = true;
	}

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v1] ) {
		_metalFeatures.indirectDrawing = true;
		_metalFeatures.baseVertexInstanceDrawing = true;
		_metalFeatures.combinedStoreResolveAction = true;
		_metalFeatures.mtlBufferAlignment = 16;     // Min float4 alignment for typical vertex buffers. MTLBuffer may go down to 4 bytes for other data.
		_metalFeatures.maxTextureDimension = (16 * KIBI);
		_metalFeatures.depthSampleCompare = true;
	}

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v2] ) {
		_metalFeatures.arrayOfTextures = true;
	}
	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v3] ) {
		_metalFeatures.arrayOfSamplers = true;
	}

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily4_v1] ) {
		_metalFeatures.postDepthCoverage = true;
	}

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily5_v1] ) {
		_metalFeatures.layeredRendering = true;
		_metalFeatures.stencilFeedback = true;
	}

#endif

#if MVK_MACOS
	_metalFeatures.mslVersionEnum = MTLLanguageVersion1_1;
    _metalFeatures.maxPerStageTextureCount = 128;
    _metalFeatures.mtlBufferAlignment = 256;
	_metalFeatures.mtlCopyBufferAlignment = 4;
	_metalFeatures.indirectDrawing = true;
	_metalFeatures.baseVertexInstanceDrawing = true;
	_metalFeatures.layeredRendering = true;
	_metalFeatures.maxTextureDimension = (16 * KIBI);
	_metalFeatures.depthSampleCompare = true;

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v2] ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion1_2;
        _metalFeatures.dynamicMTLBuffers = true;
        _metalFeatures.shaderSpecialization = true;
        _metalFeatures.stencilViews = true;
        _metalFeatures.samplerClampToBorder = true;
        _metalFeatures.combinedStoreResolveAction = true;
        _metalFeatures.maxMTLBufferSize = (1 * GIBI);
    }

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v3] ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_0;
        _metalFeatures.texelBuffers = true;
		_metalFeatures.arrayOfTextures = true;
		_metalFeatures.arrayOfSamplers = true;
		_metalFeatures.presentModeImmediate = true;
		_metalFeatures.fences = true;
    }

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v4] ) {
        _metalFeatures.mslVersionEnum = MTLLanguageVersion2_1;
        _metalFeatures.multisampleArrayTextures = true;
		_metalFeatures.events = true;
        _metalFeatures.memoryBarriers = true;
        _metalFeatures.textureBuffers = true;
    }

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily2_v1] ) {
		_metalFeatures.multisampleLayeredRendering = _metalFeatures.layeredRendering;
		_metalFeatures.stencilFeedback = true;
	}

#endif

    if ( [_mtlDevice respondsToSelector: @selector(maxBufferLength)] ) {
        _metalFeatures.maxMTLBufferSize = _mtlDevice.maxBufferLength;
    }

    for (uint32_t sc = VK_SAMPLE_COUNT_1_BIT; sc <= VK_SAMPLE_COUNT_64_BIT; sc <<= 1) {
        if ([_mtlDevice supportsTextureSampleCount: mvkSampleCountFromVkSampleCountFlagBits((VkSampleCountFlagBits)sc)]) {
            _metalFeatures.supportedSampleCounts |= sc;
        }
    }

#define setMSLVersion(maj, min)	\
	_metalFeatures.mslVersion = SPIRV_CROSS_NAMESPACE::CompilerMSL::Options::make_msl_version(maj, min);

	switch (_metalFeatures.mslVersionEnum) {
		case MTLLanguageVersion2_1:
			setMSLVersion(2, 1);
			break;
		case MTLLanguageVersion2_0:
			setMSLVersion(2, 0);
			break;
		case MTLLanguageVersion1_2:
			setMSLVersion(1, 2);
			break;
		case MTLLanguageVersion1_1:
			setMSLVersion(1, 1);
			break;
#if MVK_IOS
		case MTLLanguageVersion1_0:
			setMSLVersion(1, 0);
			break;
#endif
#if MVK_MACOS
		// Silence compiler warning catch-22 on MTLLanguageVersion1_0.
		// But allow iOS to be explicit so it warns on future enum values
		default:
			setMSLVersion(1, 0);
			break;
#endif
	}

}

/** Initializes the physical device features of this instance. */
void MVKPhysicalDevice::initFeatures() {
	memset(&_features, 0, sizeof(_features));	// Start with everything cleared

    _features.robustBufferAccess = true;  // XXX Required by Vulkan spec
    _features.fullDrawIndexUint32 = true;
    _features.independentBlend = true;
    _features.sampleRateShading = true;
    _features.depthBiasClamp = true;
    _features.fillModeNonSolid = true;
    _features.largePoints = true;
    _features.alphaToOne = true;
    _features.samplerAnisotropy = true;
    _features.shaderImageGatherExtended = true;
    _features.shaderStorageImageExtendedFormats = true;
    _features.shaderStorageImageReadWithoutFormat = true;
    _features.shaderStorageImageWriteWithoutFormat = true;
    _features.shaderUniformBufferArrayDynamicIndexing = true;
    _features.shaderStorageBufferArrayDynamicIndexing = true;
    _features.shaderClipDistance = true;
    _features.shaderInt16 = true;
    _features.multiDrawIndirect = true;
    _features.variableMultisampleRate = true;
    _features.inheritedQueries = true;

	_features.shaderSampledImageArrayDynamicIndexing = _metalFeatures.arrayOfTextures;

    if (_metalFeatures.indirectDrawing && _metalFeatures.baseVertexInstanceDrawing) {
        _features.drawIndirectFirstInstance = true;
    }

#if MVK_IOS
    _features.textureCompressionETC2 = true;

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v1] ) {
        _features.textureCompressionASTC_LDR = true;
    }

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v1] ) {
        _features.occlusionQueryPrecise = true;
    }

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v4] ) {
		_features.dualSrcBlend = true;
	}

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v4] ) {
		_features.depthClamp = true;
	}

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v2] ) {
		_features.tessellationShader = true;
		_features.shaderTessellationAndGeometryPointSize = true;
	}

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily4_v1] ) {
		_features.imageCubeArray = true;
	}
  
	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily5_v1] ) {
		_features.multiViewport = true;
	}
#endif

#if MVK_MACOS
    _features.textureCompressionBC = true;
    _features.occlusionQueryPrecise = true;
    _features.imageCubeArray = true;
    _features.depthClamp = true;
    _features.vertexPipelineStoresAndAtomics = true;
    _features.fragmentStoresAndAtomics = true;

    _features.shaderStorageImageArrayDynamicIndexing = _metalFeatures.arrayOfTextures;

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v2] ) {
        _features.tessellationShader = true;
        _features.dualSrcBlend = true;
        _features.shaderTessellationAndGeometryPointSize = true;
    }

    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v3] ) {
        _features.multiViewport = true;
    }

#endif
}


#pragma mark VkPhysicalDeviceFeatures - List of features available on the device

//typedef struct VkPhysicalDeviceFeatures {
//    VkBool32    robustBufferAccess;                           // done
//    VkBool32    fullDrawIndexUint32;                          // done
//    VkBool32    imageCubeArray;                               // done
//    VkBool32    independentBlend;                             // done
//    VkBool32    geometryShader;
//    VkBool32    tessellationShader;                           // done
//    VkBool32    sampleRateShading;                            // done
//    VkBool32    dualSrcBlend;                                 // done
//    VkBool32    logicOp;
//    VkBool32    multiDrawIndirect;                            // done
//    VkBool32    drawIndirectFirstInstance;                    // done
//    VkBool32    depthClamp;                                   // done
//    VkBool32    depthBiasClamp;                               // done
//    VkBool32    fillModeNonSolid;                             // done
//    VkBool32    depthBounds;
//    VkBool32    wideLines;
//    VkBool32    largePoints;                                  // done
//    VkBool32    alphaToOne;                                   // done
//    VkBool32    multiViewport;                                // done
//    VkBool32    samplerAnisotropy;                            // done
//    VkBool32    textureCompressionETC2;                       // done
//    VkBool32    textureCompressionASTC_LDR;                   // done
//    VkBool32    textureCompressionBC;                         // done
//    VkBool32    occlusionQueryPrecise;                        // done
//    VkBool32    pipelineStatisticsQuery;
//    VkBool32    vertexPipelineStoresAndAtomics;               // done
//    VkBool32    fragmentStoresAndAtomics;                     // done
//    VkBool32    shaderTessellationAndGeometryPointSize;       // done
//    VkBool32    shaderImageGatherExtended;                    // done
//    VkBool32    shaderStorageImageExtendedFormats;            // done
//    VkBool32    shaderStorageImageMultisample;
//    VkBool32    shaderStorageImageReadWithoutFormat;          // done
//    VkBool32    shaderStorageImageWriteWithoutFormat;         // done
//    VkBool32    shaderUniformBufferArrayDynamicIndexing;      // done
//    VkBool32    shaderSampledImageArrayDynamicIndexing;       // done
//    VkBool32    shaderStorageBufferArrayDynamicIndexing;      // done
//    VkBool32    shaderStorageImageArrayDynamicIndexing;       // done
//    VkBool32    shaderClipDistance;                           // done
//    VkBool32    shaderCullDistance;
//    VkBool32    shaderFloat64;
//    VkBool32    shaderInt64;
//    VkBool32    shaderInt16;                                  // done
//    VkBool32    shaderResourceResidency;
//    VkBool32    shaderResourceMinLod;
//    VkBool32    sparseBinding;
//    VkBool32    sparseResidencyBuffer;
//    VkBool32    sparseResidencyImage2D;
//    VkBool32    sparseResidencyImage3D;
//    VkBool32    sparseResidency2Samples;
//    VkBool32    sparseResidency4Samples;
//    VkBool32    sparseResidency8Samples;
//    VkBool32    sparseResidency16Samples;
//    VkBool32    sparseResidencyAliased;
//    VkBool32    variableMultisampleRate;                      // done
//    VkBool32    inheritedQueries;                             // done
//} VkPhysicalDeviceFeatures;

/** Initializes the physical device properties of this instance. */
void MVKPhysicalDevice::initProperties() {
	memset(&_properties, 0, sizeof(_properties));	// Start with everything cleared

	_properties.apiVersion = MVK_VULKAN_API_VERSION;
	_properties.driverVersion = MVK_VERSION;

	mvkPopulateGPUInfo(_properties, _mtlDevice);
	initPipelineCacheUUID();

	// Limits
#if MVK_IOS
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v1] ) {
        _properties.limits.maxColorAttachments = kMVKCachedColorAttachmentCount;
    } else {
        _properties.limits.maxColorAttachments = 4;		// < kMVKCachedColorAttachmentCount
    }
#endif
#if MVK_MACOS
    _properties.limits.maxColorAttachments = kMVKCachedColorAttachmentCount;
#endif

    _properties.limits.maxFragmentOutputAttachments = _properties.limits.maxColorAttachments;
    _properties.limits.maxFragmentDualSrcAttachments = _features.dualSrcBlend ? 1 : 0;

	_properties.limits.framebufferColorSampleCounts = _metalFeatures.supportedSampleCounts;
	_properties.limits.framebufferDepthSampleCounts = _metalFeatures.supportedSampleCounts;
	_properties.limits.framebufferStencilSampleCounts = _metalFeatures.supportedSampleCounts;
	_properties.limits.framebufferNoAttachmentsSampleCounts = _metalFeatures.supportedSampleCounts;
	_properties.limits.sampledImageColorSampleCounts = _metalFeatures.supportedSampleCounts;
	_properties.limits.sampledImageIntegerSampleCounts = _metalFeatures.supportedSampleCounts;
	_properties.limits.sampledImageDepthSampleCounts = _metalFeatures.supportedSampleCounts;
	_properties.limits.sampledImageStencilSampleCounts = _metalFeatures.supportedSampleCounts;
	_properties.limits.storageImageSampleCounts = VK_SAMPLE_COUNT_1_BIT;

	_properties.limits.maxSampleMaskWords = 1;

	_properties.limits.maxImageDimension1D = _metalFeatures.maxTextureDimension;
	_properties.limits.maxImageDimension2D = _metalFeatures.maxTextureDimension;
	_properties.limits.maxImageDimensionCube = _metalFeatures.maxTextureDimension;
	_properties.limits.maxFramebufferWidth = _metalFeatures.maxTextureDimension;
	_properties.limits.maxFramebufferHeight = _metalFeatures.maxTextureDimension;
	_properties.limits.maxFramebufferLayers = _metalFeatures.layeredRendering ?  256 : 1;

    _properties.limits.maxViewportDimensions[0] = _metalFeatures.maxTextureDimension;
    _properties.limits.maxViewportDimensions[1] = _metalFeatures.maxTextureDimension;
    float maxVPDim = max(_properties.limits.maxViewportDimensions[0], _properties.limits.maxViewportDimensions[1]);
    _properties.limits.viewportBoundsRange[0] = (-2.0 * maxVPDim);
    _properties.limits.viewportBoundsRange[1] = (2.0 * maxVPDim) - 1;
    _properties.limits.maxViewports = _features.multiViewport ? kMVKCachedViewportScissorCount : 1;

	_properties.limits.maxImageDimension3D = (2 * KIBI);
	_properties.limits.maxImageArrayLayers = (2 * KIBI);
	_properties.limits.maxSamplerAnisotropy = 16;

    _properties.limits.maxVertexInputAttributes = 31;
    _properties.limits.maxVertexInputBindings = 31;

    _properties.limits.maxVertexInputAttributeOffset = (4 * KIBI);
    _properties.limits.maxVertexInputBindingStride = _properties.limits.maxVertexInputAttributeOffset - 1;

	_properties.limits.maxPerStageDescriptorSamplers = _metalFeatures.maxPerStageSamplerCount;
	_properties.limits.maxPerStageDescriptorUniformBuffers = _metalFeatures.maxPerStageBufferCount;
	_properties.limits.maxPerStageDescriptorStorageBuffers = _metalFeatures.maxPerStageBufferCount;
	_properties.limits.maxPerStageDescriptorSampledImages = _metalFeatures.maxPerStageTextureCount;
	_properties.limits.maxPerStageDescriptorStorageImages = _metalFeatures.maxPerStageTextureCount;
	_properties.limits.maxPerStageDescriptorInputAttachments = _metalFeatures.maxPerStageTextureCount;

    _properties.limits.maxPerStageResources = (_metalFeatures.maxPerStageBufferCount + _metalFeatures.maxPerStageTextureCount);
    _properties.limits.maxFragmentCombinedOutputResources = _properties.limits.maxPerStageResources;

	_properties.limits.maxDescriptorSetSamplers = (_properties.limits.maxPerStageDescriptorSamplers * 4);
	_properties.limits.maxDescriptorSetUniformBuffers = (_properties.limits.maxPerStageDescriptorUniformBuffers * 4);
	_properties.limits.maxDescriptorSetUniformBuffersDynamic = (_properties.limits.maxPerStageDescriptorUniformBuffers * 4);
	_properties.limits.maxDescriptorSetStorageBuffers = (_properties.limits.maxPerStageDescriptorStorageBuffers * 4);
	_properties.limits.maxDescriptorSetStorageBuffersDynamic = (_properties.limits.maxPerStageDescriptorStorageBuffers * 4);
	_properties.limits.maxDescriptorSetSampledImages = (_properties.limits.maxPerStageDescriptorSampledImages * 4);
	_properties.limits.maxDescriptorSetStorageImages = (_properties.limits.maxPerStageDescriptorStorageImages * 4);
	_properties.limits.maxDescriptorSetInputAttachments = (_properties.limits.maxPerStageDescriptorInputAttachments * 4);

	if (_metalFeatures.textureBuffers) {
		_properties.limits.maxTexelBufferElements = (uint32_t)_metalFeatures.maxMTLBufferSize;
	} else {
		_properties.limits.maxTexelBufferElements = _properties.limits.maxImageDimension2D * _properties.limits.maxImageDimension2D;
	}
#if MVK_MACOS
	_properties.limits.maxUniformBufferRange = (64 * KIBI);
#endif
#if MVK_IOS
	_properties.limits.maxUniformBufferRange = (uint32_t)_metalFeatures.maxMTLBufferSize;
#endif
	_properties.limits.maxStorageBufferRange = (uint32_t)_metalFeatures.maxMTLBufferSize;
	_properties.limits.maxPushConstantsSize = (4 * KIBI);

    _properties.limits.minMemoryMapAlignment = _metalFeatures.mtlBufferAlignment;
    _properties.limits.minUniformBufferOffsetAlignment = _metalFeatures.mtlBufferAlignment;
    _properties.limits.minStorageBufferOffsetAlignment = 4;
    _properties.limits.bufferImageGranularity = _metalFeatures.mtlBufferAlignment;
    _properties.limits.nonCoherentAtomSize = _metalFeatures.mtlBufferAlignment;

    if ([_mtlDevice respondsToSelector: @selector(minimumLinearTextureAlignmentForPixelFormat:)]) {
        // Figure out the greatest alignment required by all supported formats, and
        // whether or not they only require alignment to a single texel. We'll use this
        // information to fill out the VkPhysicalDeviceTexelBufferAlignmentPropertiesEXT
        // struct.
        uint32_t maxStorage = 0, maxUniform = 0;
        bool singleTexelStorage = true, singleTexelUniform = true;
        mvkEnumerateSupportedFormats({0, 0, VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT | VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT}, true, [&](VkFormat vk) {
            NSUInteger alignment;
            if ([_mtlDevice respondsToSelector: @selector(minimumTextureBufferAlignmentForPixelFormat:)]) {
                alignment = [_mtlDevice minimumTextureBufferAlignmentForPixelFormat: mvkMTLPixelFormatFromVkFormat(vk)];
            } else {
                alignment = [_mtlDevice minimumLinearTextureAlignmentForPixelFormat: mvkMTLPixelFormatFromVkFormat(vk)];
            }
            VkFormatProperties props = mvkVkFormatProperties(vk, getFormatIsSupported(vk));
            // For uncompressed formats, this is the size of a single texel.
            // Note that no implementations of Metal support compressed formats
            // in a linear texture (including texture buffers). It's likely that even
            // if they did, this would be the absolute minimum alignment.
            uint32_t texelSize = mvkVkFormatBytesPerBlock(vk);
            // From the spec:
            //   "If the size of a single texel is a multiple of three bytes, then
            //    the size of a single component of the format is used instead."
            if (texelSize % 3 == 0) {
                switch (mvkFormatTypeFromVkFormat(vk)) {
                case kMVKFormatColorInt8:
                case kMVKFormatColorUInt8:
                    texelSize = 1;
                    break;
                case kMVKFormatColorHalf:
                case kMVKFormatColorInt16:
                case kMVKFormatColorUInt16:
                    texelSize = 2;
                    break;
                case kMVKFormatColorFloat:
                case kMVKFormatColorInt32:
                case kMVKFormatColorUInt32:
                default:
                    texelSize = 4;
                    break;
                }
            }
            if (mvkAreAllFlagsEnabled(props.bufferFeatures, VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT)) {
                maxStorage = max(maxStorage, uint32_t(alignment));
                if (alignment % texelSize != 0) { singleTexelStorage = false; }
            }
            if (mvkAreAllFlagsEnabled(props.bufferFeatures, VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT)) {
                maxUniform = max(maxUniform, uint32_t(alignment));
                if (alignment % texelSize != 0) { singleTexelUniform = false; }
            }
            return true;
        });
        _texelBuffAlignProperties.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXEL_BUFFER_ALIGNMENT_PROPERTIES_EXT;
        _texelBuffAlignProperties.storageTexelBufferOffsetAlignmentBytes = maxStorage;
        _texelBuffAlignProperties.storageTexelBufferOffsetSingleTexelAlignment = singleTexelStorage;
        _texelBuffAlignProperties.uniformTexelBufferOffsetAlignmentBytes = maxUniform;
        _texelBuffAlignProperties.uniformTexelBufferOffsetSingleTexelAlignment = singleTexelUniform;
        _properties.limits.minTexelBufferOffsetAlignment = max(maxStorage, maxUniform);
    } else {
#if MVK_IOS
        if ([_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v1]) {
            _properties.limits.minTexelBufferOffsetAlignment = 16;
        } else {
            _properties.limits.minTexelBufferOffsetAlignment = 64;
        }
#endif
#if MVK_MACOS
        _properties.limits.minTexelBufferOffsetAlignment = 256;
#endif
        _texelBuffAlignProperties.storageTexelBufferOffsetAlignmentBytes = _properties.limits.minTexelBufferOffsetAlignment;
        _texelBuffAlignProperties.storageTexelBufferOffsetSingleTexelAlignment = VK_FALSE;
        _texelBuffAlignProperties.uniformTexelBufferOffsetAlignmentBytes = _properties.limits.minTexelBufferOffsetAlignment;
        _texelBuffAlignProperties.uniformTexelBufferOffsetSingleTexelAlignment = VK_FALSE;
    }

#if MVK_IOS
    _properties.limits.maxFragmentInputComponents = 60;

    if ([_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v1]) {
        _properties.limits.optimalBufferCopyOffsetAlignment = 16;
    } else {
        _properties.limits.optimalBufferCopyOffsetAlignment = 64;
    }

    if ([_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily5_v1]) {
        _properties.limits.maxTessellationGenerationLevel = 64;
        _properties.limits.maxTessellationPatchSize = 32;
    } else if ([_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v2]) {
        _properties.limits.maxTessellationGenerationLevel = 16;
        _properties.limits.maxTessellationPatchSize = 32;
    } else {
        _properties.limits.maxTessellationGenerationLevel = 0;
        _properties.limits.maxTessellationPatchSize = 0;
    }
#endif
#if MVK_MACOS
    _properties.limits.maxFragmentInputComponents = 128;
    _properties.limits.optimalBufferCopyOffsetAlignment = 256;

    if ([_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v2]) {
        _properties.limits.maxTessellationGenerationLevel = 64;
        _properties.limits.maxTessellationPatchSize = 32;
    } else {
        _properties.limits.maxTessellationGenerationLevel = 0;
        _properties.limits.maxTessellationPatchSize = 0;
    }
#endif

    _properties.limits.maxVertexOutputComponents = _properties.limits.maxFragmentInputComponents;

    if (_features.tessellationShader) {
        _properties.limits.maxTessellationControlPerVertexInputComponents = _properties.limits.maxVertexOutputComponents;
        _properties.limits.maxTessellationControlPerVertexOutputComponents = _properties.limits.maxTessellationControlPerVertexInputComponents;
        // Reserve a few for the tessellation levels.
        _properties.limits.maxTessellationControlPerPatchOutputComponents = _properties.limits.maxFragmentInputComponents - 8;
        _properties.limits.maxTessellationControlTotalOutputComponents = _properties.limits.maxTessellationPatchSize * _properties.limits.maxTessellationControlPerVertexOutputComponents + _properties.limits.maxTessellationControlPerPatchOutputComponents;
        _properties.limits.maxTessellationEvaluationInputComponents = _properties.limits.maxTessellationControlPerVertexInputComponents;
        _properties.limits.maxTessellationEvaluationOutputComponents = _properties.limits.maxTessellationEvaluationInputComponents;
    } else {
        _properties.limits.maxTessellationControlPerVertexInputComponents = 0;
        _properties.limits.maxTessellationControlPerVertexOutputComponents = 0;
        _properties.limits.maxTessellationControlPerPatchOutputComponents = 0;
        _properties.limits.maxTessellationControlTotalOutputComponents = 0;
        _properties.limits.maxTessellationEvaluationInputComponents = 0;
        _properties.limits.maxTessellationEvaluationOutputComponents = 0;
    }

    _properties.limits.optimalBufferCopyRowPitchAlignment = 1;

	_properties.limits.timestampComputeAndGraphics = VK_TRUE;
	_properties.limits.timestampPeriod = mvkGetTimestampPeriod();

    _properties.limits.pointSizeRange[0] = 1;
    _properties.limits.pointSizeRange[1] = 511;
    _properties.limits.pointSizeGranularity = 1;
    _properties.limits.lineWidthRange[0] = 1;
    _properties.limits.lineWidthRange[1] = 1;
    _properties.limits.lineWidthGranularity = 1;

    _properties.limits.standardSampleLocations = VK_TRUE;
    _properties.limits.strictLines = VK_FALSE;

	VkExtent3D wgSize = mvkVkExtent3DFromMTLSize(_mtlDevice.maxThreadsPerThreadgroup);
	_properties.limits.maxComputeWorkGroupSize[0] = wgSize.width;
	_properties.limits.maxComputeWorkGroupSize[1] = wgSize.height;
	_properties.limits.maxComputeWorkGroupSize[2] = wgSize.depth;
	_properties.limits.maxComputeWorkGroupInvocations = max({wgSize.width, wgSize.height, wgSize.depth});

	if ( [_mtlDevice respondsToSelector: @selector(maxThreadgroupMemoryLength)] ) {
		_properties.limits.maxComputeSharedMemorySize = (uint32_t)_mtlDevice.maxThreadgroupMemoryLength;
	} else {
#if MVK_IOS
		if ([_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily4_v1]) {
			_properties.limits.maxComputeSharedMemorySize = (32 * KIBI);
		} else if ([_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v1]) {
			_properties.limits.maxComputeSharedMemorySize = (16 * KIBI);
		} else {
			_properties.limits.maxComputeSharedMemorySize = ((16 * KIBI) - 32);
		}
#endif
#if MVK_MACOS
		_properties.limits.maxComputeSharedMemorySize = (32 * KIBI);
#endif
	}

    _properties.limits.minTexelOffset = -8;
    _properties.limits.maxTexelOffset = 7;
    _properties.limits.minTexelGatherOffset = _properties.limits.minTexelOffset;
    _properties.limits.maxTexelGatherOffset = _properties.limits.maxTexelOffset;

    // Features with no specific limits - default to unlimited int values

    _properties.limits.maxMemoryAllocationCount = kMVKUndefinedLargeUInt32;
    _properties.limits.maxSamplerAllocationCount = kMVKUndefinedLargeUInt32;
    _properties.limits.maxBoundDescriptorSets = kMVKUndefinedLargeUInt32;

    _properties.limits.maxComputeWorkGroupCount[0] = kMVKUndefinedLargeUInt32;
    _properties.limits.maxComputeWorkGroupCount[1] = kMVKUndefinedLargeUInt32;
    _properties.limits.maxComputeWorkGroupCount[2] = kMVKUndefinedLargeUInt32;

    _properties.limits.maxDrawIndexedIndexValue = numeric_limits<uint32_t>::max();
    _properties.limits.maxDrawIndirectCount = kMVKUndefinedLargeUInt32;

    _properties.limits.maxClipDistances = kMVKUndefinedLargeUInt32;
	_properties.limits.maxCullDistances = 0;	// unsupported
    _properties.limits.maxCombinedClipAndCullDistances = _properties.limits.maxClipDistances +
														 _properties.limits.maxCullDistances;


    // Features with unknown limits - default to Vulkan required limits
    
    _properties.limits.subPixelPrecisionBits = 4;
    _properties.limits.subTexelPrecisionBits = 4;
    _properties.limits.mipmapPrecisionBits = 4;
    _properties.limits.viewportSubPixelBits = 0;

    _properties.limits.maxSamplerLodBias = 2;

    _properties.limits.discreteQueuePriorities = 2;

    _properties.limits.minInterpolationOffset = -0.5;
    _properties.limits.maxInterpolationOffset = 0.5;
    _properties.limits.subPixelInterpolationOffsetBits = 4;


    // Unsupported features - set to zeros generally

    _properties.limits.sparseAddressSpaceSize = 0;

    _properties.limits.maxGeometryShaderInvocations = 0;
    _properties.limits.maxGeometryInputComponents = 0;
    _properties.limits.maxGeometryOutputComponents = 0;
    _properties.limits.maxGeometryOutputVertices = 0;
    _properties.limits.maxGeometryTotalOutputComponents = 0;
}


#pragma mark VkPhysicalDeviceLimits - List of feature limits available on the device

//typedef struct VkPhysicalDeviceLimits {
//	uint32_t                                    maxImageDimension1D;                                // done
//	uint32_t                                    maxImageDimension2D;                                // done
//	uint32_t                                    maxImageDimension3D;                                // done
//	uint32_t                                    maxImageDimensionCube;                              // done
//	uint32_t                                    maxImageArrayLayers;                                // done
//	uint32_t                                    maxTexelBufferElements;                             // done
//	uint32_t                                    maxUniformBufferRange;                              // done
//	uint32_t                                    maxStorageBufferRange;                              // done
//	uint32_t                                    maxPushConstantsSize;                               // done
//	uint32_t                                    maxMemoryAllocationCount;                           // done
//	uint32_t                                    maxSamplerAllocationCount;                          // done
//	VkDeviceSize                                bufferImageGranularity;                             // done
//	VkDeviceSize                                sparseAddressSpaceSize;                             // done
//	uint32_t                                    maxBoundDescriptorSets;                             // done
//	uint32_t                                    maxPerStageDescriptorSamplers;				        // done
//	uint32_t                                    maxPerStageDescriptorUniformBuffers;		        // done
//	uint32_t                                    maxPerStageDescriptorStorageBuffers;		        // done
//	uint32_t                                    maxPerStageDescriptorSampledImages;			        // done
//	uint32_t                                    maxPerStageDescriptorStorageImages;			        // done
//	uint32_t                                    maxPerStageDescriptorInputAttachments;		        // done
//	uint32_t                                    maxPerStageResources;                               // done
//	uint32_t                                    maxDescriptorSetSamplers;					        // done
//	uint32_t                                    maxDescriptorSetUniformBuffers;				        // done
//	uint32_t                                    maxDescriptorSetUniformBuffersDynamic;		        // done
//	uint32_t                                    maxDescriptorSetStorageBuffers;				        // done
//	uint32_t                                    maxDescriptorSetStorageBuffersDynamic;		        // done
//	uint32_t                                    maxDescriptorSetSampledImages;				        // done
//	uint32_t                                    maxDescriptorSetStorageImages;				        // done
//	uint32_t                                    maxDescriptorSetInputAttachments;                   // done
//	uint32_t                                    maxVertexInputAttributes;                           // done
//	uint32_t                                    maxVertexInputBindings;                             // done
//	uint32_t                                    maxVertexInputAttributeOffset;                      // done
//	uint32_t                                    maxVertexInputBindingStride;                        // done
//	uint32_t                                    maxVertexOutputComponents;                          // done
//	uint32_t                                    maxTessellationGenerationLevel;                     // done
//	uint32_t                                    maxTessellationPatchSize;                           // done
//	uint32_t                                    maxTessellationControlPerVertexInputComponents;     // done
//	uint32_t                                    maxTessellationControlPerVertexOutputComponents;    // done
//	uint32_t                                    maxTessellationControlPerPatchOutputComponents;     // done
//	uint32_t                                    maxTessellationControlTotalOutputComponents;        // done
//	uint32_t                                    maxTessellationEvaluationInputComponents;           // done
//	uint32_t                                    maxTessellationEvaluationOutputComponents;          // done
//	uint32_t                                    maxGeometryShaderInvocations;                       // done
//	uint32_t                                    maxGeometryInputComponents;                         // done
//	uint32_t                                    maxGeometryOutputComponents;                        // done
//	uint32_t                                    maxGeometryOutputVertices;                          // done
//	uint32_t                                    maxGeometryTotalOutputComponents;                   // done
//	uint32_t                                    maxFragmentInputComponents;                         // done
//	uint32_t                                    maxFragmentOutputAttachments;                       // done
//	uint32_t                                    maxFragmentDualSrcAttachments;                      // done
//	uint32_t                                    maxFragmentCombinedOutputResources;                 // done
//	uint32_t                                    maxComputeSharedMemorySize;                         // done
//	uint32_t                                    maxComputeWorkGroupCount[3];                        // done
//	uint32_t                                    maxComputeWorkGroupInvocations;                     // done
//	uint32_t                                    maxComputeWorkGroupSize[3];                         // done
//	uint32_t                                    subPixelPrecisionBits;                              // done
//	uint32_t                                    subTexelPrecisionBits;                              // done
//	uint32_t                                    mipmapPrecisionBits;                                // done
//	uint32_t                                    maxDrawIndexedIndexValue;                           // done
//	uint32_t                                    maxDrawIndirectCount;                               // done
//	float                                       maxSamplerLodBias;                                  // done
//	float                                       maxSamplerAnisotropy;						        // done
//	uint32_t                                    maxViewports;								        // done
//	uint32_t                                    maxViewportDimensions[2];					        // done
//	float                                       viewportBoundsRange[2];                             // done
//	uint32_t                                    viewportSubPixelBits;                               // done
//	size_t                                      minMemoryMapAlignment;						        // done
//	VkDeviceSize                                minTexelBufferOffsetAlignment;				        // done
//	VkDeviceSize                                minUniformBufferOffsetAlignment;			        // done
//	VkDeviceSize                                minStorageBufferOffsetAlignment;			        // done
//	int32_t                                     minTexelOffset;                                     // done
//	uint32_t                                    maxTexelOffset;                                     // done
//	int32_t                                     minTexelGatherOffset;                               // done
//	uint32_t                                    maxTexelGatherOffset;                               // done
//	float                                       minInterpolationOffset;                             // done
//	float                                       maxInterpolationOffset;                             // done
//	uint32_t                                    subPixelInterpolationOffsetBits;			        // done
//	uint32_t                                    maxFramebufferWidth;						        // done
//	uint32_t                                    maxFramebufferHeight;						        // done
//	uint32_t                                    maxFramebufferLayers;						        // done
//	VkSampleCountFlags                          framebufferColorSampleCounts;				        // done
//	VkSampleCountFlags                          framebufferDepthSampleCounts;				        // done
//	VkSampleCountFlags                          framebufferStencilSampleCounts;				        // done
//	VkSampleCountFlags                          framebufferNoAttachmentsSampleCounts;		        // done
//	uint32_t                                    maxColorAttachments;						        // done
//	VkSampleCountFlags                          sampledImageColorSampleCounts;				        // done
//	VkSampleCountFlags                          sampledImageIntegerSampleCounts;			        // done
//	VkSampleCountFlags                          sampledImageDepthSampleCounts;				        // done
//	VkSampleCountFlags                          sampledImageStencilSampleCounts;			        // done
//	VkSampleCountFlags                          storageImageSampleCounts;					        // done
//	uint32_t                                    maxSampleMaskWords;                                 // done
//	VkBool32                                    timestampComputeAndGraphics;                        // done
//	float                                       timestampPeriod;							        // done
//	uint32_t                                    maxClipDistances;                                   // done
//	uint32_t                                    maxCullDistances;                                   // done
//	uint32_t                                    maxCombinedClipAndCullDistances;                    // done
//	uint32_t                                    discreteQueuePriorities;                            // done
//	float                                       pointSizeRange[2];                                  // done
//	float                                       lineWidthRange[2];                                  // done
//	float                                       pointSizeGranularity;                               // done
//	float                                       lineWidthGranularity;                               // done
//	VkBool32                                    strictLines;                                        // done
//	VkBool32                                    standardSampleLocations;                            // done
//	VkDeviceSize                                optimalBufferCopyOffsetAlignment;			        // done
//	VkDeviceSize                                optimalBufferCopyRowPitchAlignment;			        // done
//	VkDeviceSize                                nonCoherentAtomSize;                                // done
//} VkPhysicalDeviceLimits;

//typedef struct {
//	VkBool32                                    residencyStandard2DBlockShape;
//	VkBool32                                    residencyStandard2DMSBlockShape;
//	VkBool32                                    residencyStandard3DBlockShape;
//	VkBool32                                    residencyAlignedMipSize;
//	VkBool32                                    residencyNonResident;
//	VkBool32                                    residencyNonResidentStrict;
//} VkPhysicalDeviceSparseProperties;


void MVKPhysicalDevice::initPipelineCacheUUID() {

	// Clear the UUID
	memset(&_properties.pipelineCacheUUID, 0, sizeof(_properties.pipelineCacheUUID));

	size_t uuidComponentOffset = 0;

	// First 4 bytes contains MoltenVK version
	uint32_t mvkVersion = MVK_VERSION;
	*(uint32_t*)&_properties.pipelineCacheUUID[uuidComponentOffset] = NSSwapHostIntToBig(mvkVersion);
	uuidComponentOffset += sizeof(mvkVersion);

	// Next 4 bytes contains hightest Metal feature set supported by this device
	uint32_t mtlFeatSet = (uint32_t)getHighestMTLFeatureSet();
	*(uint32_t*)&_properties.pipelineCacheUUID[uuidComponentOffset] = NSSwapHostIntToBig(mtlFeatSet);
	uuidComponentOffset += sizeof(mtlFeatSet);

	// Last 8 bytes contain the first part of the SPIRV-Cross Git revision
	uint64_t spvxRev = getSpirvCrossRevision();
	*(uint64_t*)&_properties.pipelineCacheUUID[uuidComponentOffset] = NSSwapHostLongLongToBig(spvxRev);
	uuidComponentOffset += sizeof(spvxRev);
}

MTLFeatureSet MVKPhysicalDevice::getHighestMTLFeatureSet() {
#if MVK_IOS
	MTLFeatureSet maxFS = MTLFeatureSet_iOS_GPUFamily5_v1;
	MTLFeatureSet minFS = MTLFeatureSet_iOS_GPUFamily1_v1;
#endif

#if MVK_MACOS
	MTLFeatureSet maxFS = MTLFeatureSet_macOS_GPUFamily2_v1;
	MTLFeatureSet minFS = MTLFeatureSet_macOS_GPUFamily1_v1;
#endif

	for (NSUInteger fs = maxFS; fs > minFS; fs--) {
		MTLFeatureSet mtlFS = (MTLFeatureSet)fs;
		if ( [_mtlDevice supportsFeatureSet: mtlFS] ) {
			return mtlFS;
		}
	}

	return minFS;
}

// Retrieve the SPIRV-Cross Git revision hash from a derived header file that was created in the fetchDependencies script.
uint64_t MVKPhysicalDevice::getSpirvCrossRevision() {

#include <SPIRV-Cross/mvkSpirvCrossRevisionDerived.h>

	static const string revStr(spirvCrossRevisionString, 0, 16);	// We just need the first 16 chars
	static const string lut("0123456789ABCDEF");

	uint64_t revVal = 0;
	for (char c : revStr) {
		size_t cVal = lut.find(toupper(c));
		if (cVal != string::npos) {
			revVal <<= 4;
			revVal += cVal;
		}
	}
	return revVal;
}

/** Initializes the memory properties of this instance. */
void MVKPhysicalDevice::initMemoryProperties() {

	// Metal Shared:
	//	- applies to both buffers and textures
	//	- default mode for buffers on both iOS & macOS
	//	- default mode for textures on iOS
	//	- one copy of memory visible to both CPU & GPU
	//	- coherent at command buffer boundaries
	// Metal Private:
	//	- applies to both buffers and textures
	//	- accessed only by GPU through render, compute, or BLIT operations
	//	- no access by CPU
	//	- always use for framebuffers and renderable textures
	// Metal Managed:
	//	- applies to both buffers and textures
	//	- default mode for textures on macOS
	//	- two copies of each buffer or texture when discrete memory available
	//	- convenience of shared mode, performance of private mode
	//	- on unified systems behaves like shared memory and has only one copy of content
	//	- when writing, use:
	//		- buffer didModifyRange:
	//		- texture replaceRegion:
	//	- when reading, use:
	//		- encoder synchronizeResource: followed by
	//		- cmdbuff waitUntilCompleted (or completion handler)
	//		- buffer/texture getBytes:
	// Metal Memoryless:
	//	- applies only to textures used as transient render targets
	//	- only available with TBDR devices (i.e. on iOS)
	//	- no device memory is reserved at all
	//	- storage comes from tile memory
	//	- contents are undefined after rendering
	//	- use for temporary renderable textures

    _memoryProperties = (VkPhysicalDeviceMemoryProperties){
        .memoryHeapCount = 1,
        .memoryHeaps = {
            {
                .flags = (VK_MEMORY_HEAP_DEVICE_LOCAL_BIT),
                .size = (VkDeviceSize)mvkRecommendedMaxWorkingSetSize(_mtlDevice),
            },
        },
        // NB this list needs to stay sorted by propertyFlags (as bit sets)
        .memoryTypes = {
            {
                .heapIndex = 0,
                .propertyFlags = MVK_VK_MEMORY_TYPE_METAL_PRIVATE,    // Private storage
            },
#if MVK_MACOS
            {
                .heapIndex = 0,
                .propertyFlags = MVK_VK_MEMORY_TYPE_METAL_MANAGED,    // Managed storage
            },
#endif
            {
                .heapIndex = 0,
                .propertyFlags = MVK_VK_MEMORY_TYPE_METAL_SHARED,    // Shared storage
            },
#if MVK_IOS
            {
                .heapIndex = 0,
                .propertyFlags = MVK_VK_MEMORY_TYPE_METAL_MEMORYLESS,    // Memoryless storage
            },
#endif
        },
    };

#if MVK_MACOS
	_memoryProperties.memoryTypeCount = 3;
	_privateMemoryTypes			= 0x1;			// Private only
	_lazilyAllocatedMemoryTypes	= 0x0;			// Not supported on macOS
	_hostCoherentMemoryTypes 	= 0x4;			// Shared only
	_hostVisibleMemoryTypes		= 0x6;			// Shared & managed
	_allMemoryTypes				= 0x7;			// Private, shared, & managed
#endif
#if MVK_IOS
	_memoryProperties.memoryTypeCount = 2;		// Managed storage not available on iOS
	_privateMemoryTypes			= 0x1;			// Private only
	_lazilyAllocatedMemoryTypes	= 0x0;			// Not supported on this version
	_hostCoherentMemoryTypes 	= 0x2;			// Shared only
	_hostVisibleMemoryTypes		= 0x2;			// Shared only
	_allMemoryTypes				= 0x3;			// Private & shared
	if ([getMTLDevice() supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v3]) {
		_memoryProperties.memoryTypeCount = 3;	// Memoryless storage available
		_privateMemoryTypes			= 0x5;		// Private & memoryless
		_lazilyAllocatedMemoryTypes	= 0x4;		// Memoryless only
		_allMemoryTypes				= 0x7;		// Private, shared & memoryless
	}
#endif
}

void MVKPhysicalDevice::initExtensions() {
	MVKExtensionList* pWritableExtns = (MVKExtensionList*)&_supportedExtensions;
	pWritableExtns->disableAllButEnabledDeviceExtensions();

	if (!_metalFeatures.postDepthCoverage) {
		pWritableExtns->vk_EXT_post_depth_coverage.enabled = false;
	}
	if (!_metalFeatures.stencilFeedback) {
		pWritableExtns->vk_EXT_shader_stencil_export.enabled = false;
	}
}

void MVKPhysicalDevice::logGPUInfo() {
	string devTypeStr;
	switch (_properties.deviceType) {
		case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:
			devTypeStr = "Discrete";
			break;
		case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:
			devTypeStr = "Integrated";
			break;
		case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:
			devTypeStr = "Virtual";
			break;
		case VK_PHYSICAL_DEVICE_TYPE_CPU:
			devTypeStr = "CPU Emulation";
			break;
		default:
			devTypeStr = "Unknown";
			break;
	}

	string logMsg = "GPU device:";
	logMsg += "\n\t\tmodel: %s";
	logMsg += "\n\t\ttype: %s";
	logMsg += "\n\t\tvendorID: %#06x";
	logMsg += "\n\t\tdeviceID: %#06x";
	logMsg += "\n\t\tpipelineCacheUUID: %s";
	logMsg += "\n\tsupports Metal Shading Language version %s and the following Metal Feature Sets:";

#if MVK_IOS
	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily5_v1] ) { logMsg += "\n\t\tiOS GPU Family 5 v1"; }

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily4_v2] ) { logMsg += "\n\t\tiOS GPU Family 4 v2"; }
	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily4_v1] ) { logMsg += "\n\t\tiOS GPU Family 4 v1"; }

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v4] ) { logMsg += "\n\t\tiOS GPU Family 3 v4"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v3] ) { logMsg += "\n\t\tiOS GPU Family 3 v3"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v2] ) { logMsg += "\n\t\tiOS GPU Family 3 v2"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v1] ) { logMsg += "\n\t\tiOS GPU Family 3 v1"; }

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v5] ) { logMsg += "\n\t\tiOS GPU Family 2 v5"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v4] ) { logMsg += "\n\t\tiOS GPU Family 2 v4"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v3] ) { logMsg += "\n\t\tiOS GPU Family 2 v3"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v2] ) { logMsg += "\n\t\tiOS GPU Family 2 v2"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v1] ) { logMsg += "\n\t\tiOS GPU Family 2 v1"; }

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v5] ) { logMsg += "\n\t\tiOS GPU Family 1 v5"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v4] ) { logMsg += "\n\t\tiOS GPU Family 1 v4"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v3] ) { logMsg += "\n\t\tiOS GPU Family 1 v3"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v2] ) { logMsg += "\n\t\tiOS GPU Family 1 v2"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v1] ) { logMsg += "\n\t\tiOS GPU Family 1 v1"; }
#endif

#if MVK_MACOS
	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily2_v1] ) { logMsg += "\n\t\tmacOS GPU Family 2 v1"; }

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v4] ) { logMsg += "\n\t\tmacOS GPU Family 1 v4"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v3] ) { logMsg += "\n\t\tmacOS GPU Family 1 v3"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v2] ) { logMsg += "\n\t\tmacOS GPU Family 1 v2"; }
    if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_GPUFamily1_v1] ) { logMsg += "\n\t\tmacOS GPU Family 1 v1"; }

	if ( [_mtlDevice supportsFeatureSet: MTLFeatureSet_macOS_ReadWriteTextureTier2] ) { logMsg += "\n\t\tmacOS Read-Write Texture Tier 2"; }

#endif

	NSUUID* nsUUID = [[NSUUID alloc] initWithUUIDBytes: _properties.pipelineCacheUUID];		// temp retain
	MVKLogInfo(logMsg.c_str(), _properties.deviceName, devTypeStr.c_str(),
			   _properties.vendorID, _properties.deviceID, nsUUID.UUIDString.UTF8String,
			   SPIRVToMSLConversionOptions::printMSLVersion(_metalFeatures.mslVersion).c_str());
	[nsUUID release];																		// temp release
}

MVKPhysicalDevice::~MVKPhysicalDevice() {
	mvkDestroyContainerContents(_queueFamilies);
	[_mtlDevice release];
}


#pragma mark -
#pragma mark MVKDevice

// Returns core device commands and enabled extension device commands.
PFN_vkVoidFunction MVKDevice::getProcAddr(const char* pName) {
	MVKEntryPoint* pMVKPA = _physicalDevice->_mvkInstance->getEntryPoint(pName);

	bool isSupported = (pMVKPA &&								// Command exists and...
						pMVKPA->isDevice &&						// ...is a device command and...
						pMVKPA->isEnabled(_enabledExtensions));	// ...is a core or enabled extension command.

	return isSupported ? pMVKPA->functionPointer : nullptr;
}

MVKQueue* MVKDevice::getQueue(uint32_t queueFamilyIndex, uint32_t queueIndex) {
	return _queuesByQueueFamilyIndex[queueFamilyIndex][queueIndex];
}

VkResult MVKDevice::waitIdle() {
	for (auto& queues : _queuesByQueueFamilyIndex) {
		for (MVKQueue* q : queues) {
			q->waitIdle();
		}
	}
	return VK_SUCCESS;
}

void MVKDevice::getDescriptorSetLayoutSupport(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
											  VkDescriptorSetLayoutSupport* pSupport) {
	// According to the Vulkan spec:
	//   "If the descriptor set layout satisfies the VkPhysicalDeviceMaintenance3Properties::maxPerSetDescriptors
	//   limit, this command is guaranteed to return VK_TRUE in VkDescriptorSetLayout::supported...
	//   "This command does not consider other limits such as maxPerStageDescriptor*..."
	uint32_t descriptorCount = 0;
	for (uint32_t i = 0; i < pCreateInfo->bindingCount; i++) {
		descriptorCount += pCreateInfo->pBindings[i].descriptorCount;
	}
	pSupport->supported = (descriptorCount < ((_physicalDevice->_metalFeatures.maxPerStageBufferCount + _physicalDevice->_metalFeatures.maxPerStageTextureCount + _physicalDevice->_metalFeatures.maxPerStageSamplerCount) * 2));
}

VkResult MVKDevice::getDeviceGroupPresentCapabilities(VkDeviceGroupPresentCapabilitiesKHR* pDeviceGroupPresentCapabilities) {
	memset(pDeviceGroupPresentCapabilities->presentMask, 0, sizeof(pDeviceGroupPresentCapabilities->presentMask));
	pDeviceGroupPresentCapabilities->presentMask[0] = 0x1;

	pDeviceGroupPresentCapabilities->modes = VK_DEVICE_GROUP_PRESENT_MODE_LOCAL_BIT_KHR;

	return VK_SUCCESS;
}

VkResult MVKDevice::getDeviceGroupSurfacePresentModes(MVKSurface* surface, VkDeviceGroupPresentModeFlagsKHR* pModes) {
	*pModes = VK_DEVICE_GROUP_PRESENT_MODE_LOCAL_BIT_KHR;
	return VK_SUCCESS;
}

void MVKDevice::getPeerMemoryFeatures(uint32_t heapIndex, uint32_t localDevice, uint32_t remoteDevice, VkPeerMemoryFeatureFlags* pPeerMemoryFeatures) {
	*pPeerMemoryFeatures = VK_PEER_MEMORY_FEATURE_COPY_SRC_BIT | VK_PEER_MEMORY_FEATURE_COPY_DST_BIT;
}


#pragma mark Object lifecycle

uint32_t MVKDevice::getVulkanMemoryTypeIndex(MTLStorageMode mtlStorageMode) {
    VkMemoryPropertyFlags vkMemFlags;
    switch (mtlStorageMode) {
        case MTLStorageModePrivate:
            vkMemFlags = MVK_VK_MEMORY_TYPE_METAL_PRIVATE;
            break;
        case MTLStorageModeShared:
            vkMemFlags = MVK_VK_MEMORY_TYPE_METAL_SHARED;
            break;
#if MVK_MACOS
        case MTLStorageModeManaged:
            vkMemFlags = MVK_VK_MEMORY_TYPE_METAL_MANAGED;
            break;
#endif
#if MVK_IOS
        case MTLStorageModeMemoryless:
            vkMemFlags = MVK_VK_MEMORY_TYPE_METAL_MEMORYLESS;
            break;
#endif
        default:
            vkMemFlags = MVK_VK_MEMORY_TYPE_METAL_SHARED;
            break;
    }

    for (uint32_t mtIdx = 0; mtIdx < _pMemoryProperties->memoryTypeCount; mtIdx++) {
        if (_pMemoryProperties->memoryTypes[mtIdx].propertyFlags == vkMemFlags) { return mtIdx; }
    }
    MVKAssert(false, "Could not find memory type corresponding to VkMemoryPropertyFlags %d", vkMemFlags);
    return 0;
}

MVKBuffer* MVKDevice::createBuffer(const VkBufferCreateInfo* pCreateInfo,
								   const VkAllocationCallbacks* pAllocator) {
    return (MVKBuffer*)addResource(new MVKBuffer(this, pCreateInfo));
}

void MVKDevice::destroyBuffer(MVKBuffer* mvkBuff,
							  const VkAllocationCallbacks* pAllocator) {
	removeResource(mvkBuff);
	mvkBuff->destroy();
}

MVKBufferView* MVKDevice::createBufferView(const VkBufferViewCreateInfo* pCreateInfo,
                                           const VkAllocationCallbacks* pAllocator) {
    return new MVKBufferView(this, pCreateInfo);
}

void MVKDevice::destroyBufferView(MVKBufferView* mvkBuffView,
                                  const VkAllocationCallbacks* pAllocator) {
    mvkBuffView->destroy();
}

MVKImage* MVKDevice::createImage(const VkImageCreateInfo* pCreateInfo,
								 const VkAllocationCallbacks* pAllocator) {
	// If there's a VkImageSwapchainCreateInfoKHR, then we need to create a swapchain image.
	const VkImageSwapchainCreateInfoKHR* swapchainInfo = nullptr;
	for (const auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
		case VK_STRUCTURE_TYPE_IMAGE_SWAPCHAIN_CREATE_INFO_KHR:
			swapchainInfo = (const VkImageSwapchainCreateInfoKHR*)next;
			break;
		default:
			break;
		}
	}
	if (swapchainInfo) {
		return (MVKImage*)addResource(new MVKSwapchainImage(this, pCreateInfo, (MVKSwapchain*)swapchainInfo->swapchain));
	}
	return (MVKImage*)addResource(new MVKImage(this, pCreateInfo));
}

void MVKDevice::destroyImage(MVKImage* mvkImg,
							 const VkAllocationCallbacks* pAllocator) {
	removeResource(mvkImg);
	mvkImg->destroy();
}

MVKImageView* MVKDevice::createImageView(const VkImageViewCreateInfo* pCreateInfo,
										 const VkAllocationCallbacks* pAllocator) {
	return new MVKImageView(this, pCreateInfo);
}

void MVKDevice::destroyImageView(MVKImageView* mvkImgView,
								 const VkAllocationCallbacks* pAllocator) {
	mvkImgView->destroy();
}

MVKSwapchain* MVKDevice::createSwapchain(const VkSwapchainCreateInfoKHR* pCreateInfo,
										 const VkAllocationCallbacks* pAllocator) {
	return new MVKSwapchain(this, pCreateInfo);
}

void MVKDevice::destroySwapchain(MVKSwapchain* mvkSwpChn,
								 const VkAllocationCallbacks* pAllocator) {
	mvkSwpChn->destroy();
}

MVKSwapchainImage* MVKDevice::createSwapchainImage(const VkImageCreateInfo* pCreateInfo,
												   MVKSwapchain* swapchain,
												   uint32_t swapchainIndex,
												   const VkAllocationCallbacks* pAllocator) {
	return (MVKSwapchainImage*)addResource(new MVKSwapchainImage(this, pCreateInfo, swapchain, swapchainIndex));
}

void MVKDevice::destroySwapchainImage(MVKSwapchainImage* mvkImg,
									  const VkAllocationCallbacks* pAllocator) {
	removeResource(mvkImg);
	mvkImg->destroy();
}

MVKFence* MVKDevice::createFence(const VkFenceCreateInfo* pCreateInfo,
								 const VkAllocationCallbacks* pAllocator) {
	return new MVKFence(this, pCreateInfo);
}

void MVKDevice::destroyFence(MVKFence* mvkFence,
							 const VkAllocationCallbacks* pAllocator) {
	mvkFence->destroy();
}

MVKSemaphore* MVKDevice::createSemaphore(const VkSemaphoreCreateInfo* pCreateInfo,
										 const VkAllocationCallbacks* pAllocator) {
	if (_useMTLFenceForSemaphores) {
		return new MVKSemaphoreMTLFence(this, pCreateInfo);
	} else if (_useMTLEventForSemaphores) {
		return new MVKSemaphoreMTLEvent(this, pCreateInfo);
	} else {
		return new MVKSemaphoreEmulated(this, pCreateInfo);
	}
}

void MVKDevice::destroySemaphore(MVKSemaphore* mvkSem4,
								 const VkAllocationCallbacks* pAllocator) {
	mvkSem4->destroy();
}

MVKEvent* MVKDevice::createEvent(const VkEventCreateInfo* pCreateInfo,
								 const VkAllocationCallbacks* pAllocator) {
	if (_pMetalFeatures->events) {
		return new MVKEventNative(this, pCreateInfo);
	} else {
		return new MVKEventEmulated(this, pCreateInfo);
	}
}

void MVKDevice::destroyEvent(MVKEvent* mvkEvent, const VkAllocationCallbacks* pAllocator) {
	mvkEvent->destroy();
}

MVKQueryPool* MVKDevice::createQueryPool(const VkQueryPoolCreateInfo* pCreateInfo,
										 const VkAllocationCallbacks* pAllocator) {
	switch (pCreateInfo->queryType) {
        case VK_QUERY_TYPE_OCCLUSION:
            return new MVKOcclusionQueryPool(this, pCreateInfo);
		case VK_QUERY_TYPE_TIMESTAMP:
			return new MVKTimestampQueryPool(this, pCreateInfo);
		case VK_QUERY_TYPE_PIPELINE_STATISTICS:
			return new MVKPipelineStatisticsQueryPool(this, pCreateInfo);
		default:
            return new MVKUnsupportedQueryPool(this, pCreateInfo);
	}
}

void MVKDevice::destroyQueryPool(MVKQueryPool* mvkQP,
								 const VkAllocationCallbacks* pAllocator) {
	mvkQP->destroy();
}

MVKShaderModule* MVKDevice::createShaderModule(const VkShaderModuleCreateInfo* pCreateInfo,
											   const VkAllocationCallbacks* pAllocator) {
	return new MVKShaderModule(this, pCreateInfo);
}

void MVKDevice::destroyShaderModule(MVKShaderModule* mvkShdrMod,
									const VkAllocationCallbacks* pAllocator) {
	mvkShdrMod->destroy();
}

MVKPipelineCache* MVKDevice::createPipelineCache(const VkPipelineCacheCreateInfo* pCreateInfo,
												 const VkAllocationCallbacks* pAllocator) {
	return new MVKPipelineCache(this, pCreateInfo);
}

void MVKDevice::destroyPipelineCache(MVKPipelineCache* mvkPLC,
									 const VkAllocationCallbacks* pAllocator) {
	mvkPLC->destroy();
}

MVKPipelineLayout* MVKDevice::createPipelineLayout(const VkPipelineLayoutCreateInfo* pCreateInfo,
												   const VkAllocationCallbacks* pAllocator) {
	return new MVKPipelineLayout(this, pCreateInfo);
}

void MVKDevice::destroyPipelineLayout(MVKPipelineLayout* mvkPLL,
									  const VkAllocationCallbacks* pAllocator) {
	mvkPLL->destroy();
}

template<typename PipelineType, typename PipelineInfoType>
VkResult MVKDevice::createPipelines(VkPipelineCache pipelineCache,
                                    uint32_t count,
                                    const PipelineInfoType* pCreateInfos,
                                    const VkAllocationCallbacks* pAllocator,
                                    VkPipeline* pPipelines) {
    VkResult rslt = VK_SUCCESS;
    MVKPipelineCache* mvkPLC = (MVKPipelineCache*)pipelineCache;

    for (uint32_t plIdx = 0; plIdx < count; plIdx++) {
        const PipelineInfoType* pCreateInfo = &pCreateInfos[plIdx];

        // See if this pipeline has a parent. This can come either directly
        // via basePipelineHandle or indirectly via basePipelineIndex.
        MVKPipeline* parentPL = VK_NULL_HANDLE;
        if ( mvkAreAllFlagsEnabled(pCreateInfo->flags, VK_PIPELINE_CREATE_DERIVATIVE_BIT) ) {
            VkPipeline vkParentPL = pCreateInfo->basePipelineHandle;
            int32_t parentPLIdx = pCreateInfo->basePipelineIndex;
            if ( !vkParentPL && (parentPLIdx >= 0)) { vkParentPL = pPipelines[parentPLIdx]; }
            parentPL = vkParentPL ? (MVKPipeline*)vkParentPL : VK_NULL_HANDLE;
        }

        // Create the pipeline and if creation was successful, insert the new pipeline
        // in the return array and add it to the pipeline cache (if the cache was specified).
        // If creation was unsuccessful, insert NULL into the return array, change the
        // result code of this function, and destroy the broken pipeline.
        MVKPipeline* mvkPL = new PipelineType(this, mvkPLC, parentPL, pCreateInfo);
        VkResult plRslt = mvkPL->getConfigurationResult();
        if (plRslt == VK_SUCCESS) {
            pPipelines[plIdx] = (VkPipeline)mvkPL;
        } else {
            rslt = plRslt;
            pPipelines[plIdx] = VK_NULL_HANDLE;
            mvkPL->destroy();
        }
    }

    return rslt;
}

// Create concrete implementations of the two variations of the mvkCreatePipelines() function
// that we will be using. This is required since the template definition is located in this
// implementation file instead of in the header file. This is a realistic approach if the
// universe of possible template implementation variations is small and known in advance.
template VkResult MVKDevice::createPipelines<MVKGraphicsPipeline, VkGraphicsPipelineCreateInfo>(VkPipelineCache pipelineCache,
                                                                                                uint32_t count,
                                                                                                const VkGraphicsPipelineCreateInfo* pCreateInfos,
                                                                                                const VkAllocationCallbacks* pAllocator,
                                                                                                VkPipeline* pPipelines);

template VkResult MVKDevice::createPipelines<MVKComputePipeline, VkComputePipelineCreateInfo>(VkPipelineCache pipelineCache,
                                                                                              uint32_t count,
                                                                                              const VkComputePipelineCreateInfo* pCreateInfos,
                                                                                              const VkAllocationCallbacks* pAllocator,
                                                                                              VkPipeline* pPipelines);

void MVKDevice::destroyPipeline(MVKPipeline* mvkPL,
                                const VkAllocationCallbacks* pAllocator) {
    mvkPL->destroy();
}

MVKSampler* MVKDevice::createSampler(const VkSamplerCreateInfo* pCreateInfo,
									 const VkAllocationCallbacks* pAllocator) {
	return new MVKSampler(this, pCreateInfo);
}

void MVKDevice::destroySampler(MVKSampler* mvkSamp,
							   const VkAllocationCallbacks* pAllocator) {
	mvkSamp->destroy();
}

MVKDescriptorSetLayout* MVKDevice::createDescriptorSetLayout(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
															 const VkAllocationCallbacks* pAllocator) {
	return new MVKDescriptorSetLayout(this, pCreateInfo);
}

void MVKDevice::destroyDescriptorSetLayout(MVKDescriptorSetLayout* mvkDSL,
										   const VkAllocationCallbacks* pAllocator) {
	mvkDSL->destroy();
}

MVKDescriptorPool* MVKDevice::createDescriptorPool(const VkDescriptorPoolCreateInfo* pCreateInfo,
												   const VkAllocationCallbacks* pAllocator) {
	return new MVKDescriptorPool(this, pCreateInfo);
}

void MVKDevice::destroyDescriptorPool(MVKDescriptorPool* mvkDP,
									  const VkAllocationCallbacks* pAllocator) {
	mvkDP->destroy();
}

MVKDescriptorUpdateTemplate* MVKDevice::createDescriptorUpdateTemplate(
	const VkDescriptorUpdateTemplateCreateInfoKHR* pCreateInfo,
	const VkAllocationCallbacks* pAllocator) {
	return new MVKDescriptorUpdateTemplate(this, pCreateInfo);
}

void MVKDevice::destroyDescriptorUpdateTemplate(MVKDescriptorUpdateTemplate* mvkDUT,
												const VkAllocationCallbacks* pAllocator) {
	mvkDUT->destroy();
}

MVKFramebuffer* MVKDevice::createFramebuffer(const VkFramebufferCreateInfo* pCreateInfo,
											 const VkAllocationCallbacks* pAllocator) {
	return new MVKFramebuffer(this, pCreateInfo);
}

void MVKDevice::destroyFramebuffer(MVKFramebuffer* mvkFB,
								   const VkAllocationCallbacks* pAllocator) {
	mvkFB->destroy();
}

MVKRenderPass* MVKDevice::createRenderPass(const VkRenderPassCreateInfo* pCreateInfo,
										   const VkAllocationCallbacks* pAllocator) {
	return new MVKRenderPass(this, pCreateInfo);
}

void MVKDevice::destroyRenderPass(MVKRenderPass* mvkRP,
								  const VkAllocationCallbacks* pAllocator) {
	mvkRP->destroy();
}

MVKCommandPool* MVKDevice::createCommandPool(const VkCommandPoolCreateInfo* pCreateInfo,
											const VkAllocationCallbacks* pAllocator) {
	return new MVKCommandPool(this, pCreateInfo);
}

void MVKDevice::destroyCommandPool(MVKCommandPool* mvkCmdPool,
								   const VkAllocationCallbacks* pAllocator) {
	mvkCmdPool->destroy();
}

MVKDeviceMemory* MVKDevice::allocateMemory(const VkMemoryAllocateInfo* pAllocateInfo,
										   const VkAllocationCallbacks* pAllocator) {
	return new MVKDeviceMemory(this, pAllocateInfo, pAllocator);
}

void MVKDevice::freeMemory(MVKDeviceMemory* mvkDevMem,
						   const VkAllocationCallbacks* pAllocator) {
	mvkDevMem->destroy();
}


#pragma mark Operations

// Adds the specified resource for tracking, and returns the added resource.
MVKResource* MVKDevice::addResource(MVKResource* rez) {
	lock_guard<mutex> lock(_rezLock);
	_resources.push_back(rez);
	return rez;
}

// Removes the specified resource for tracking and returns the removed resource.
MVKResource* MVKDevice::removeResource(MVKResource* rez) {
	lock_guard<mutex> lock(_rezLock);
	mvkRemoveFirstOccurance(_resources, rez);
	return rez;
}

void MVKDevice::applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
								   VkPipelineStageFlags dstStageMask,
								   VkMemoryBarrier* pMemoryBarrier,
                                   MVKCommandEncoder* cmdEncoder,
                                   MVKCommandUse cmdUse) {
	if (!mvkIsAnyFlagEnabled(dstStageMask, VK_PIPELINE_STAGE_HOST_BIT) ||
		!mvkIsAnyFlagEnabled(pMemoryBarrier->dstAccessMask, VK_ACCESS_HOST_READ_BIT) ) { return; }
	lock_guard<mutex> lock(_rezLock);
    for (auto& rez : _resources) {
		rez->applyMemoryBarrier(srcStageMask, dstStageMask, pMemoryBarrier, cmdEncoder, cmdUse);
	}
}

uint64_t MVKDevice::getPerformanceTimestampImpl() { return mvkGetTimestamp(); }

void MVKDevice::addActivityPerformanceImpl(MVKPerformanceTracker& activityTracker,
										   uint64_t startTime, uint64_t endTime) {
    lock_guard<mutex> lock(_perfLock);

	double currInterval = mvkGetElapsedMilliseconds(startTime, endTime);
	activityTracker.minimumDuration = ((activityTracker.minimumDuration == 0.0)
											  ? currInterval :
											  min(currInterval, activityTracker.minimumDuration));
    activityTracker.maximumDuration = max(currInterval, activityTracker.maximumDuration);
    double totalInterval = (activityTracker.averageDuration * activityTracker.count++) + currInterval;
    activityTracker.averageDuration = totalInterval / activityTracker.count;

	if (_pMVKConfig->performanceLoggingFrameCount) {
		MVKLogInfo("Performance to %s count: %d curr: %.3f ms, min: %.3f ms, max: %.3f ms, avg: %.3f ms",
				   getActivityPerformanceDescription(activityTracker),
				   activityTracker.count,
				   currInterval,
				   activityTracker.minimumDuration,
				   activityTracker.maximumDuration,
				   activityTracker.averageDuration);
	}
}

const char* MVKDevice::getActivityPerformanceDescription(MVKPerformanceTracker& activityTracker) {
	if (&activityTracker == &_performanceStatistics.shaderCompilation.hashShaderCode) { return "hash shader SPIR-V code"; }
    if (&activityTracker == &_performanceStatistics.shaderCompilation.spirvToMSL) { return "convert SPIR-V to MSL source code"; }
    if (&activityTracker == &_performanceStatistics.shaderCompilation.mslCompile) { return "compile MSL source code into a MTLLibrary"; }
    if (&activityTracker == &_performanceStatistics.shaderCompilation.mslLoad) { return "load pre-compiled MSL code into a MTLLibrary"; }
	if (&activityTracker == &_performanceStatistics.shaderCompilation.shaderLibraryFromCache) { return "retrieve shader library from the cache"; }
    if (&activityTracker == &_performanceStatistics.shaderCompilation.functionRetrieval) { return "retrieve a MTLFunction from a MTLLibrary"; }
    if (&activityTracker == &_performanceStatistics.shaderCompilation.functionSpecialization) { return "specialize a retrieved MTLFunction"; }
    if (&activityTracker == &_performanceStatistics.shaderCompilation.pipelineCompile) { return "compile MTLFunctions into a pipeline"; }
	if (&activityTracker == &_performanceStatistics.pipelineCache.sizePipelineCache) { return "calculate cache size required to write MSL to pipeline cache"; }
	if (&activityTracker == &_performanceStatistics.pipelineCache.writePipelineCache) { return "write MSL to pipeline cache"; }
	if (&activityTracker == &_performanceStatistics.pipelineCache.readPipelineCache) { return "read MSL from pipeline cache"; }
	if (&activityTracker == &_performanceStatistics.queue.mtlQueueAccess) { return "access MTLCommandQueue"; }
	if (&activityTracker == &_performanceStatistics.queue.mtlCommandBufferCompletion) { return "complete MTLCommandBuffer"; }
    return "Unknown performance activity";
}

void MVKDevice::getPerformanceStatistics(MVKPerformanceStatistics* pPerf) {
    lock_guard<mutex> lock(_perfLock);

    if (pPerf) { *pPerf = _performanceStatistics; }
}

VkResult MVKDevice::invalidateMappedMemoryRanges(uint32_t memRangeCount, const VkMappedMemoryRange* pMemRanges) {
	@autoreleasepool {
		VkResult rslt = VK_SUCCESS;
		MVKMTLBlitEncoder mvkBlitEnc;
		for (uint32_t i = 0; i < memRangeCount; i++) {
			const VkMappedMemoryRange* pMem = &pMemRanges[i];
			MVKDeviceMemory* mvkMem = (MVKDeviceMemory*)pMem->memory;
			VkResult r = mvkMem->pullFromDevice(pMem->offset, pMem->size, false, &mvkBlitEnc);
			if (rslt == VK_SUCCESS) { rslt = r; }
		}
		if (mvkBlitEnc.mtlBlitEncoder) { [mvkBlitEnc.mtlBlitEncoder endEncoding]; }
		if (mvkBlitEnc.mtlCmdBuffer) {
			[mvkBlitEnc.mtlCmdBuffer commit];
			[mvkBlitEnc.mtlCmdBuffer waitUntilCompleted];
		}
		return rslt;
	}
}


#pragma mark Metal

uint32_t MVKDevice::getMetalBufferIndexForVertexAttributeBinding(uint32_t binding) {
	return ((_pMetalFeatures->maxPerStageBufferCount - 1) - binding);
}

MTLPixelFormat MVKDevice::getMTLPixelFormatFromVkFormat(VkFormat vkFormat, MVKBaseObject* mvkObj) {
	MTLPixelFormat mtlPixFmt = mvkMTLPixelFormatFromVkFormatInObj(vkFormat, mvkObj);
#if MVK_MACOS
	if (mtlPixFmt == MTLPixelFormatDepth24Unorm_Stencil8 &&
		!getMTLDevice().isDepth24Stencil8PixelFormatSupported) {
		return MTLPixelFormatDepth32Float_Stencil8;
	}
#endif
	return mtlPixFmt;
}

VkDeviceSize MVKDevice::getVkFormatTexelBufferAlignment(VkFormat format, MVKBaseObject* mvkObj) {
	VkDeviceSize deviceAlignment = mvkMTLPixelFormatLinearTextureAlignment(getMTLPixelFormatFromVkFormat(format, mvkObj), getMTLDevice());
	return deviceAlignment ? deviceAlignment : _pProperties->limits.minTexelBufferOffsetAlignment;
}

id<MTLBuffer> MVKDevice::getGlobalVisibilityResultMTLBuffer() {
    lock_guard<mutex> lock(_vizLock);
    return _globalVisibilityResultMTLBuffer;
}

uint32_t MVKDevice::expandVisibilityResultMTLBuffer(uint32_t queryCount) {
    lock_guard<mutex> lock(_vizLock);

    // Ensure we don't overflow the maximum number of queries
    _globalVisibilityQueryCount += queryCount;
    VkDeviceSize reqBuffLen = (VkDeviceSize)_globalVisibilityQueryCount * kMVKQuerySlotSizeInBytes;
    VkDeviceSize maxBuffLen = _pMetalFeatures->maxQueryBufferSize;
    VkDeviceSize newBuffLen = min(reqBuffLen, maxBuffLen);
    _globalVisibilityQueryCount = uint32_t(newBuffLen / kMVKQuerySlotSizeInBytes);

    if (reqBuffLen > maxBuffLen) {
        reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCreateQueryPool(): A maximum of %d total queries are available on this device in its current configuration. See the API notes for the MVKConfiguration.supportLargeQueryPools configuration parameter for more info.", _globalVisibilityQueryCount);
    }

    NSUInteger mtlBuffLen = mvkAlignByteOffset(newBuffLen, _pMetalFeatures->mtlBufferAlignment);
    MTLResourceOptions mtlBuffOpts = MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache;
    [_globalVisibilityResultMTLBuffer release];
    _globalVisibilityResultMTLBuffer = [getMTLDevice() newBufferWithLength: mtlBuffLen options: mtlBuffOpts];     // retained

    return _globalVisibilityQueryCount - queryCount;     // Might be lower than requested if an overflow occurred
}


#pragma mark Construction

MVKDevice::MVKDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo) :
	_enabledFeatures(),
	_enabledStorage16Features(),
	_enabledStorage8Features(),
	_enabledF16I8Features(),
	_enabledUBOLayoutFeatures(),
	_enabledVarPtrFeatures(),
	_enabledHostQryResetFeatures(),
	_enabledScalarLayoutFeatures(),
	_enabledTexelBuffAlignFeatures(),
	_enabledVtxAttrDivFeatures(),
	_enabledPortabilityFeatures(),
	_enabledExtensions(this)
{

	initPerformanceTracking();
	initPhysicalDevice(physicalDevice, pCreateInfo);
	enableFeatures(pCreateInfo);
	enableExtensions(pCreateInfo);

    _globalVisibilityResultMTLBuffer = nil;
    _globalVisibilityQueryCount = 0;

	initMTLCompileOptions();	// Before command resource factory

	_commandResourceFactory = new MVKCommandResourceFactory(this);

	initQueues(pCreateInfo);

	if (getInstance()->_autoGPUCaptureScope == MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_DEVICE) {
		[[MTLCaptureManager sharedCaptureManager] startCaptureWithDevice: getMTLDevice()];
	}

	MVKLogInfo("Created VkDevice to run on GPU %s with the following %d Vulkan extensions enabled:%s",
			   _pProperties->deviceName,
			   _enabledExtensions.getEnabledCount(),
			   _enabledExtensions.enabledNamesString("\n\t\t", true).c_str());
}

void MVKDevice::initPerformanceTracking() {
    MVKPerformanceTracker initPerf;
    initPerf.count = 0;
    initPerf.averageDuration = 0.0;
    initPerf.minimumDuration = 0.0;
    initPerf.maximumDuration = 0.0;

	_performanceStatistics.shaderCompilation.hashShaderCode = initPerf;
    _performanceStatistics.shaderCompilation.spirvToMSL = initPerf;
    _performanceStatistics.shaderCompilation.mslCompile = initPerf;
    _performanceStatistics.shaderCompilation.mslLoad = initPerf;
	_performanceStatistics.shaderCompilation.shaderLibraryFromCache = initPerf;
    _performanceStatistics.shaderCompilation.functionRetrieval = initPerf;
    _performanceStatistics.shaderCompilation.functionSpecialization = initPerf;
    _performanceStatistics.shaderCompilation.pipelineCompile = initPerf;
	_performanceStatistics.pipelineCache.sizePipelineCache = initPerf;
	_performanceStatistics.pipelineCache.writePipelineCache = initPerf;
	_performanceStatistics.pipelineCache.readPipelineCache = initPerf;
	_performanceStatistics.queue.mtlQueueAccess = initPerf;
	_performanceStatistics.queue.mtlCommandBufferCompletion = initPerf;
}

void MVKDevice::initPhysicalDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo) {

	const VkDeviceGroupDeviceCreateInfo* pGroupCreateInfo = nullptr;
	for (const auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
		case VK_STRUCTURE_TYPE_DEVICE_GROUP_DEVICE_CREATE_INFO:
			pGroupCreateInfo = (const VkDeviceGroupDeviceCreateInfo*)next;
			break;
		default:
			break;
		}
	}

	// If I was given physical devices for a grouped device, use them.
	// At this time, we only support device groups consisting of a single member,
	// so this is sufficient for now.
	if (pGroupCreateInfo && pGroupCreateInfo->physicalDeviceCount)
		_physicalDevice = MVKPhysicalDevice::getMVKPhysicalDevice(pGroupCreateInfo->pPhysicalDevices[0]);
	else
		_physicalDevice = physicalDevice;

	_pMVKConfig = _physicalDevice->_mvkInstance->getMoltenVKConfiguration();
	_pMetalFeatures = _physicalDevice->getMetalFeatures();
	_pProperties = &_physicalDevice->_properties;
	_pMemoryProperties = &_physicalDevice->_memoryProperties;

	_useMTLFenceForSemaphores = false;
	if (_pMetalFeatures->fences) {
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(_useMTLFenceForSemaphores, MVK_ALLOW_METAL_FENCES);
	}
	_useMTLEventForSemaphores = false;
	if (_pMetalFeatures->events) {
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(_useMTLEventForSemaphores, MVK_ALLOW_METAL_EVENTS);
	}
	MVKLogInfo("Using %s for semaphores.", _useMTLFenceForSemaphores ? "MTLFence" : (_useMTLEventForSemaphores ? "MTLEvent" : "emulation"));

#if MVK_MACOS
	// If we have selected a high-power GPU and want to force the window system
	// to use it, force the window system to use a high-power GPU by calling the
	// MTLCreateSystemDefaultDevice function, and if that GPU is the same as the
	// selected GPU, update the MTLDevice instance used by the MVKPhysicalDevice.
	id<MTLDevice> mtlDevice = _physicalDevice->getMTLDevice();
	if (_pMVKConfig->switchSystemGPU && !(mtlDevice.isLowPower || mtlDevice.isHeadless) ) {
		id<MTLDevice> sysMTLDevice = MTLCreateSystemDefaultDevice();
		if (mvkGetRegistryID(sysMTLDevice) == mvkGetRegistryID(mtlDevice)) {
			_physicalDevice->replaceMTLDevice(sysMTLDevice);
		}
	}
#endif
}

void MVKDevice::enableFeatures(const VkDeviceCreateInfo* pCreateInfo) {

	// Start with all features disabled
	memset((void*)&_enabledFeatures, 0, sizeof(_enabledFeatures));
	memset((void*)&_enabledStorage16Features, 0, sizeof(_enabledStorage16Features));
	memset((void*)&_enabledStorage8Features, 0, sizeof(_enabledStorage8Features));
	memset((void*)&_enabledF16I8Features, 0, sizeof(_enabledF16I8Features));
	memset((void*)&_enabledUBOLayoutFeatures, 0, sizeof(_enabledUBOLayoutFeatures));
	memset((void*)&_enabledVarPtrFeatures, 0, sizeof(_enabledVarPtrFeatures));
	memset((void*)&_enabledHostQryResetFeatures, 0, sizeof(_enabledHostQryResetFeatures));
	memset((void*)&_enabledScalarLayoutFeatures, 0, sizeof(_enabledScalarLayoutFeatures));
	memset((void*)&_enabledTexelBuffAlignFeatures, 0, sizeof(_enabledTexelBuffAlignFeatures));
	memset((void*)&_enabledVtxAttrDivFeatures, 0, sizeof(_enabledVtxAttrDivFeatures));
	memset((void*)&_enabledPortabilityFeatures, 0, sizeof(_enabledPortabilityFeatures));

	// Fetch the available physical device features.
	VkPhysicalDevicePortabilitySubsetFeaturesEXTX pdPortabilityFeatures;
	pdPortabilityFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_EXTX;
	pdPortabilityFeatures.pNext = NULL;

	VkPhysicalDeviceVertexAttributeDivisorFeaturesEXT pdVtxAttrDivFeatures;
	pdVtxAttrDivFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VERTEX_ATTRIBUTE_DIVISOR_FEATURES_EXT;
	pdVtxAttrDivFeatures.pNext = &pdPortabilityFeatures;

	VkPhysicalDeviceTexelBufferAlignmentFeaturesEXT pdTexelBuffAlignFeatures;
	pdTexelBuffAlignFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXEL_BUFFER_ALIGNMENT_FEATURES_EXT;
	pdTexelBuffAlignFeatures.pNext = &pdVtxAttrDivFeatures;

	VkPhysicalDeviceScalarBlockLayoutFeaturesEXT pdScalarLayoutFeatures;
	pdScalarLayoutFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES_EXT;
	pdScalarLayoutFeatures.pNext = &pdTexelBuffAlignFeatures;

	VkPhysicalDeviceHostQueryResetFeaturesEXT pdHostQryResetFeatures;
	pdHostQryResetFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES_EXT;
	pdHostQryResetFeatures.pNext = &pdScalarLayoutFeatures;

	VkPhysicalDeviceVariablePointerFeatures pdVarPtrFeatures;
	pdVarPtrFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VARIABLE_POINTER_FEATURES;
	pdVarPtrFeatures.pNext = &pdHostQryResetFeatures;

	VkPhysicalDeviceUniformBufferStandardLayoutFeaturesKHR pdUBOLayoutFeatures;
	pdUBOLayoutFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_UNIFORM_BUFFER_STANDARD_LAYOUT_FEATURES_KHR;
	pdUBOLayoutFeatures.pNext = &pdVarPtrFeatures;

	VkPhysicalDeviceFloat16Int8FeaturesKHR pdF16I8Features;
	pdF16I8Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT16_INT8_FEATURES_KHR;
	pdF16I8Features.pNext = &pdUBOLayoutFeatures;

	VkPhysicalDevice8BitStorageFeaturesKHR pdStorage8Features;
	pdStorage8Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_8BIT_STORAGE_FEATURES_KHR;
	pdStorage8Features.pNext = &pdF16I8Features;

	VkPhysicalDevice16BitStorageFeatures pdStorage16Features;
	pdStorage16Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES;
	pdStorage16Features.pNext = &pdStorage8Features;

	VkPhysicalDeviceFeatures2 pdFeats2;
	pdFeats2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
	pdFeats2.pNext = &pdStorage16Features;

	_physicalDevice->getFeatures(&pdFeats2);

	//Enable device features based on requested and available features
	if (pCreateInfo->pEnabledFeatures) {
		enableFeatures(&_enabledFeatures.robustBufferAccess,
					   &pCreateInfo->pEnabledFeatures->robustBufferAccess,
					   &pdFeats2.features.robustBufferAccess, 55);
	}

	auto* next = (MVKVkAPIStructHeader*)pCreateInfo->pNext;
	while (next) {
		switch ((uint32_t)next->sType) {
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2: {
				auto* requestedFeatures = (VkPhysicalDeviceFeatures2*)next;
				enableFeatures(&_enabledFeatures.robustBufferAccess,
							   &requestedFeatures->features.robustBufferAccess,
							   &pdFeats2.features.robustBufferAccess, 55);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES: {
				auto* requestedFeatures = (VkPhysicalDevice16BitStorageFeatures*)next;
				enableFeatures(&_enabledStorage16Features.storageBuffer16BitAccess,
							   &requestedFeatures->storageBuffer16BitAccess,
							   &pdStorage16Features.storageBuffer16BitAccess, 4);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_8BIT_STORAGE_FEATURES_KHR: {
				auto* requestedFeatures = (VkPhysicalDevice8BitStorageFeaturesKHR*)next;
				enableFeatures(&_enabledStorage8Features.storageBuffer8BitAccess,
							   &requestedFeatures->storageBuffer8BitAccess,
							   &pdStorage8Features.storageBuffer8BitAccess, 3);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT16_INT8_FEATURES_KHR: {
				auto* requestedFeatures = (VkPhysicalDeviceFloat16Int8FeaturesKHR*)next;
				enableFeatures(&_enabledF16I8Features.shaderFloat16,
							   &requestedFeatures->shaderFloat16,
							   &pdF16I8Features.shaderFloat16, 2);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_UNIFORM_BUFFER_STANDARD_LAYOUT_FEATURES_KHR: {
				auto* requestedFeatures = (VkPhysicalDeviceUniformBufferStandardLayoutFeaturesKHR*)next;
				enableFeatures(&_enabledUBOLayoutFeatures.uniformBufferStandardLayout,
							   &requestedFeatures->uniformBufferStandardLayout,
							   &pdUBOLayoutFeatures.uniformBufferStandardLayout, 1);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VARIABLE_POINTER_FEATURES: {
				auto* requestedFeatures = (VkPhysicalDeviceVariablePointerFeatures*)next;
				enableFeatures(&_enabledVarPtrFeatures.variablePointersStorageBuffer,
							   &requestedFeatures->variablePointersStorageBuffer,
							   &pdVarPtrFeatures.variablePointersStorageBuffer, 2);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES_EXT: {
				auto* requestedFeatures = (VkPhysicalDeviceHostQueryResetFeaturesEXT*)next;
				enableFeatures(&_enabledHostQryResetFeatures.hostQueryReset,
							   &requestedFeatures->hostQueryReset,
							   &pdHostQryResetFeatures.hostQueryReset, 1);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES_EXT: {
				auto* requestedFeatures = (VkPhysicalDeviceScalarBlockLayoutFeaturesEXT*)next;
				enableFeatures(&_enabledScalarLayoutFeatures.scalarBlockLayout,
							   &requestedFeatures->scalarBlockLayout,
							   &pdScalarLayoutFeatures.scalarBlockLayout, 1);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXEL_BUFFER_ALIGNMENT_FEATURES_EXT: {
				auto* requestedFeatures = (VkPhysicalDeviceTexelBufferAlignmentFeaturesEXT*)next;
				enableFeatures(&_enabledTexelBuffAlignFeatures.texelBufferAlignment,
							   &requestedFeatures->texelBufferAlignment,
							   &pdTexelBuffAlignFeatures.texelBufferAlignment, 1);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VERTEX_ATTRIBUTE_DIVISOR_FEATURES_EXT: {
				auto* requestedFeatures = (VkPhysicalDeviceVertexAttributeDivisorFeaturesEXT*)next;
				enableFeatures(&_enabledVtxAttrDivFeatures.vertexAttributeInstanceRateDivisor,
							   &requestedFeatures->vertexAttributeInstanceRateDivisor,
							   &pdVtxAttrDivFeatures.vertexAttributeInstanceRateDivisor, 2);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_EXTX: {
				auto* requestedFeatures = (VkPhysicalDevicePortabilitySubsetFeaturesEXTX*)next;
				enableFeatures(&_enabledPortabilityFeatures.triangleFans,
							   &requestedFeatures->triangleFans,
							   &pdPortabilityFeatures.triangleFans, 5);
				break;
			}
			default:
				break;
		}
		next = (MVKVkAPIStructHeader*)next->pNext;
	}
}

void MVKDevice::enableFeatures(const VkBool32* pEnable, const VkBool32* pRequested, const VkBool32* pAvailable, uint32_t count) {
	for (uint32_t i = 0; i < count; i++) {
		((VkBool32*)pEnable)[i] = pRequested[i] && pAvailable[i];
		if (pRequested[i] && !pAvailable[i]) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateDevice(): Requested feature is not available on this device."));
		}
	}
}

void MVKDevice::enableExtensions(const VkDeviceCreateInfo* pCreateInfo) {
	MVKExtensionList* pWritableExtns = (MVKExtensionList*)&_enabledExtensions;
	setConfigurationResult(pWritableExtns->enable(pCreateInfo->enabledExtensionCount,
												  pCreateInfo->ppEnabledExtensionNames,
												  &_physicalDevice->_supportedExtensions));
}

// Create the command queues
void MVKDevice::initQueues(const VkDeviceCreateInfo* pCreateInfo) {
	auto& qFams = _physicalDevice->getQueueFamilies();
	uint32_t qrCnt = pCreateInfo->queueCreateInfoCount;
	for (uint32_t qrIdx = 0; qrIdx < qrCnt; qrIdx++) {
		const VkDeviceQueueCreateInfo* pQFInfo = &pCreateInfo->pQueueCreateInfos[qrIdx];
		uint32_t qfIdx = pQFInfo->queueFamilyIndex;
		MVKQueueFamily* qFam = qFams[qfIdx];
		VkQueueFamilyProperties qfProps;
		qFam->getProperties(&qfProps);

		// Ensure an entry for this queue family exists
		uint32_t qfCntMin = qfIdx + 1;
		if (_queuesByQueueFamilyIndex.size() < qfCntMin) {
			_queuesByQueueFamilyIndex.resize(qfCntMin);
		}
		auto& queues = _queuesByQueueFamilyIndex[qfIdx];
		uint32_t qCnt = min(pQFInfo->queueCount, qfProps.queueCount);
		for (uint32_t qIdx = 0; qIdx < qCnt; qIdx++) {
			queues.push_back(new MVKQueue(this, qFam, qIdx, pQFInfo->pQueuePriorities[qIdx]));
		}
	}
}

void MVKDevice::initMTLCompileOptions() {
	_mtlCompileOptions = [MTLCompileOptions new];	// retained
	_mtlCompileOptions.languageVersion = _pMetalFeatures->mslVersionEnum;
}

MVKDevice::~MVKDevice() {
	for (auto& queues : _queuesByQueueFamilyIndex) {
		mvkDestroyContainerContents(queues);
	}
	_commandResourceFactory->destroy();

	[_mtlCompileOptions release];
    [_globalVisibilityResultMTLBuffer release];

	if (getInstance()->_autoGPUCaptureScope == MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_DEVICE) {
		[[MTLCaptureManager sharedCaptureManager] stopCapture];
	}
}


#pragma mark -
#pragma mark Support functions

uint64_t mvkRecommendedMaxWorkingSetSize(id<MTLDevice> mtlDevice) {

#if MVK_MACOS
	if ( [mtlDevice respondsToSelector: @selector(recommendedMaxWorkingSetSize)]) {
		return mtlDevice.recommendedMaxWorkingSetSize;
	}
#endif
#if MVK_IOS
	// GPU and CPU use shared memory. Estimate the current free memory in the system.
	mach_port_t host_port;
	mach_msg_type_number_t host_size;
	vm_size_t pagesize;
	host_port = mach_host_self();
	host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
	host_page_size(host_port, &pagesize);
	vm_statistics_data_t vm_stat;
	if (host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size) == KERN_SUCCESS ) {
		return vm_stat.free_count * pagesize;
	}
#endif

	return 128 * MEBI;		// Conservative minimum for macOS GPU's & iOS shared memory
}

#if MVK_MACOS

static uint32_t mvkGetEntryProperty(io_registry_entry_t entry, CFStringRef propertyName) {

	uint32_t value = 0;

	CFTypeRef cfProp = IORegistryEntrySearchCFProperty(entry,
													   kIOServicePlane,
													   propertyName,
													   kCFAllocatorDefault,
													   kIORegistryIterateRecursively |
													   kIORegistryIterateParents);
	if (cfProp) {
		const uint32_t* pValue = reinterpret_cast<const uint32_t*>(CFDataGetBytePtr((CFDataRef)cfProp));
		if (pValue) { value = *pValue; }
		CFRelease(cfProp);
	}

	return value;
}

void mvkPopulateGPUInfo(VkPhysicalDeviceProperties& devProps, id<MTLDevice> mtlDevice) {

	static const uint32_t kIntelVendorId = 0x8086;
	bool isFound = false;

	bool isIntegrated = mtlDevice.isLowPower;
	devProps.deviceType = isIntegrated ? VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU : VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU;
	strlcpy(devProps.deviceName, mtlDevice.name.UTF8String, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE);

	// If the device has an associated registry ID, we can use that to get the associated IOKit node.
	// The match dictionary is consumed by IOServiceGetMatchingServices and does not need to be released.
	io_registry_entry_t entry;
	uint64_t regID = mvkGetRegistryID(mtlDevice);
	if (regID) {
		entry = IOServiceGetMatchingService(kIOMasterPortDefault, IORegistryEntryIDMatching(regID));
		if (entry) {
			// That returned the IOGraphicsAccelerator nub. Its parent, then, is the actual
			// PCI device.
			io_registry_entry_t parent;
			if (IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == kIOReturnSuccess) {
				isFound = true;
				devProps.vendorID = mvkGetEntryProperty(parent, CFSTR("vendor-id"));
				devProps.deviceID = mvkGetEntryProperty(parent, CFSTR("device-id"));
				IOObjectRelease(parent);
			}
			IOObjectRelease(entry);
		}
	}
	// Iterate all GPU's, looking for a match.
	// The match dictionary is consumed by IOServiceGetMatchingServices and does not need to be released.
	io_iterator_t entryIterator;
	if (!isFound && IOServiceGetMatchingServices(kIOMasterPortDefault,
												 IOServiceMatching("IOPCIDevice"),
												 &entryIterator) == kIOReturnSuccess) {
		while ( !isFound && (entry = IOIteratorNext(entryIterator)) ) {
			if (mvkGetEntryProperty(entry, CFSTR("class-code")) == 0x30000) {	// 0x30000 : DISPLAY_VGA

				// The Intel GPU will always be marked as integrated.
				// Return on a match of either Intel && low power, or non-Intel and non-low-power.
				uint32_t vendorID = mvkGetEntryProperty(entry, CFSTR("vendor-id"));
				if ( (vendorID == kIntelVendorId) == isIntegrated) {
					isFound = true;
					devProps.vendorID = vendorID;
					devProps.deviceID = mvkGetEntryProperty(entry, CFSTR("device-id"));
				}
			}
		}
		IOObjectRelease(entryIterator);
	}
}

#endif	//MVK_MACOS

#if MVK_IOS

void mvkPopulateGPUInfo(VkPhysicalDeviceProperties& devProps, id<MTLDevice> mtlDevice) {
	// For iOS devices, the Device ID is the SoC model (A8, A10X...), in the hex form 0xaMMX, where
	//"a" is the Apple brand, MM is the SoC model number (8, 10...) and X is 1 for X version, 0 for other.
	NSUInteger coreCnt = NSProcessInfo.processInfo.processorCount;
	uint32_t devID = 0xa070;
	if ([mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily5_v1]) {
		devID = 0xa120;
	} else if ([mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily4_v1]) {
		devID = 0xa110;
	} else if ([mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v1]) {
		devID = coreCnt > 2 ? 0xa101 : 0xa100;
	} else if ([mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v1]) {
		devID = coreCnt > 2 ? 0xa081 : 0xa080;
	}

	devProps.vendorID = 0x0000106b;	// Apple's PCI ID
	devProps.deviceID = devID;
	devProps.deviceType = VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
	strlcpy(devProps.deviceName, mtlDevice.name.UTF8String, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE);
}
#endif	//MVK_IOS

uint64_t mvkGetRegistryID(id<MTLDevice> mtlDevice) {
	return [mtlDevice respondsToSelector: @selector(registryID)] ? mtlDevice.registryID : 0;
}

VkDeviceSize mvkMTLPixelFormatLinearTextureAlignment(MTLPixelFormat mtlPixelFormat,
													 id<MTLDevice> mtlDevice) {
	if ([mtlDevice respondsToSelector: @selector(minimumLinearTextureAlignmentForPixelFormat:)]) {
		return [mtlDevice minimumLinearTextureAlignmentForPixelFormat: mtlPixelFormat];
	} else {
		return 0;
	}
}


