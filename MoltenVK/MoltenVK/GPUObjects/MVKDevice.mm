/*
 * MVKDevice.mm
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
#include "MVKSync.h"
#include "MVKCommandPool.h"
#include "MVKFoundation.h"
#include "MVKCodec.h"
#include "MVKEnvironment.h"
#include "MVKLogging.h"
#include <MoltenVKShaderConverter/SPIRVToMSLConverter.h>
#include "vk_mvk_moltenvk.h"

#import "CAMetalLayer+MoltenVK.h"

using namespace std;


#if MVK_IOS_OR_TVOS
#	include <UIKit/UIKit.h>
#	define MVKViewClass		UIView
#endif
#if MVK_MACOS
#	include <AppKit/AppKit.h>
#	define MVKViewClass		NSView
#endif

// Mac Catalyst does not support feature sets, so we redefine them to GPU families in MVKDevice.h.
#if MVK_MACCAT
#define supportsMTLFeatureSet(MFS)	[_mtlDevice supportsFamily: MTLFeatureSet_ ##MFS]
#else
#define supportsMTLFeatureSet(MFS)	[_mtlDevice supportsFeatureSet: MTLFeatureSet_ ##MFS]
#endif

#define supportsMTLGPUFamily(GPUF)	([_mtlDevice respondsToSelector: @selector(supportsFamily:)] && [_mtlDevice supportsFamily: MTLGPUFamily ##GPUF])

// Suppress unused variable warnings to allow us to define these all in one place,
// but use them in platform-conditional code blocks.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"

static const uint32_t kAMDVendorId = 0x1002;
static const uint32_t kAppleVendorId = 0x106b;
static const uint32_t kIntelVendorId = 0x8086;
static const uint32_t kNVVendorId = 0x10de;

static const uint32_t kAMDRadeonRX5700XTDeviceId = 0x731f;
static const uint32_t kAMDRadeonRX5500XTDeviceId = 0x7340;

#pragma clang diagnostic pop


#pragma mark -
#pragma mark MVKPhysicalDevice

VkResult MVKPhysicalDevice::getExtensionProperties(const char* pLayerName, uint32_t* pCount, VkExtensionProperties* pProperties) {
	return _supportedExtensions.getProperties(pCount, pProperties);
}

void MVKPhysicalDevice::getFeatures(VkPhysicalDeviceFeatures* features) {
    *features = _features;
}

void MVKPhysicalDevice::getFeatures(VkPhysicalDeviceFeatures2* features) {
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
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MULTIVIEW_FEATURES: {
				auto* multiviewFeatures = (VkPhysicalDeviceMultiviewFeatures*)next;
				multiviewFeatures->multiview = true;
				multiviewFeatures->multiviewGeometryShader = false;
				multiviewFeatures->multiviewTessellationShader = false; // FIXME
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROTECTED_MEMORY_FEATURES: {
				auto* protectedMemFeatures = (VkPhysicalDeviceProtectedMemoryFeatures*)next;
				protectedMemFeatures->protectedMemory = false;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_YCBCR_CONVERSION_FEATURES: {
				auto* samplerYcbcrConvFeatures = (VkPhysicalDeviceSamplerYcbcrConversionFeatures*)next;
				samplerYcbcrConvFeatures->samplerYcbcrConversion = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES: {
				auto* shaderDrawParamsFeatures = (VkPhysicalDeviceShaderDrawParametersFeatures*)next;
				shaderDrawParamsFeatures->shaderDrawParameters = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_SUBGROUP_EXTENDED_TYPES_FEATURES: {
				auto* shaderSGTypesFeatures = (VkPhysicalDeviceShaderSubgroupExtendedTypesFeatures*)next;
				shaderSGTypesFeatures->shaderSubgroupExtendedTypes = _metalFeatures.simdPermute || _metalFeatures.quadPermute;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES: {
				auto* timelineSem4Features = (VkPhysicalDeviceTimelineSemaphoreFeatures*)next;
				timelineSem4Features->timelineSemaphore = true;
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
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT: {
				auto* pDescIdxFeatures = (VkPhysicalDeviceDescriptorIndexingFeaturesEXT*)next;
				pDescIdxFeatures->shaderInputAttachmentArrayDynamicIndexing = _metalFeatures.arrayOfTextures;
				pDescIdxFeatures->shaderUniformTexelBufferArrayDynamicIndexing = _metalFeatures.arrayOfTextures;
				pDescIdxFeatures->shaderStorageTexelBufferArrayDynamicIndexing = _metalFeatures.arrayOfTextures;
				pDescIdxFeatures->shaderUniformBufferArrayNonUniformIndexing = false;
				pDescIdxFeatures->shaderSampledImageArrayNonUniformIndexing = _metalFeatures.arrayOfTextures && _metalFeatures.arrayOfSamplers;
				pDescIdxFeatures->shaderStorageBufferArrayNonUniformIndexing = false;
				pDescIdxFeatures->shaderStorageImageArrayNonUniformIndexing = _metalFeatures.arrayOfTextures;
				pDescIdxFeatures->shaderInputAttachmentArrayNonUniformIndexing = _metalFeatures.arrayOfTextures;
				pDescIdxFeatures->shaderUniformTexelBufferArrayNonUniformIndexing = _metalFeatures.arrayOfTextures;
				pDescIdxFeatures->shaderStorageTexelBufferArrayNonUniformIndexing = _metalFeatures.arrayOfTextures;
				pDescIdxFeatures->descriptorBindingUniformBufferUpdateAfterBind = true;
				pDescIdxFeatures->descriptorBindingSampledImageUpdateAfterBind = true;
				pDescIdxFeatures->descriptorBindingStorageImageUpdateAfterBind = true;
				pDescIdxFeatures->descriptorBindingStorageBufferUpdateAfterBind = true;
				pDescIdxFeatures->descriptorBindingUniformTexelBufferUpdateAfterBind = true;
				pDescIdxFeatures->descriptorBindingStorageTexelBufferUpdateAfterBind = true;
				pDescIdxFeatures->descriptorBindingUpdateUnusedWhilePending = true;
				pDescIdxFeatures->descriptorBindingPartiallyBound = true;
				pDescIdxFeatures->descriptorBindingVariableDescriptorCount = true;
				pDescIdxFeatures->runtimeDescriptorArray = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT: {
				auto* interlockFeatures = (VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT*)next;
				interlockFeatures->fragmentShaderSampleInterlock = _metalFeatures.rasterOrderGroups;
				interlockFeatures->fragmentShaderPixelInterlock = _metalFeatures.rasterOrderGroups;
				interlockFeatures->fragmentShaderShadingRateInterlock = false;    // Requires variable rate shading; not supported yet in Metal
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES_EXT: {
				auto* hostQueryResetFeatures = (VkPhysicalDeviceHostQueryResetFeaturesEXT*)next;
				hostQueryResetFeatures->hostQueryReset = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_ROBUSTNESS_FEATURES_EXT: {
				auto *imageRobustnessFeatures = (VkPhysicalDeviceImageRobustnessFeaturesEXT*)next;
				imageRobustnessFeatures->robustImageAccess = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIVATE_DATA_FEATURES_EXT: {
				auto* privateDataFeatures = (VkPhysicalDevicePrivateDataFeaturesEXT*)next;
				privateDataFeatures->privateData = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT: {
				auto* robustness2Features = (VkPhysicalDeviceRobustness2FeaturesEXT*)next;
				robustness2Features->robustBufferAccess2 = false;
				robustness2Features->robustImageAccess2 = true;
				robustness2Features->nullDescriptor = false;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES_EXT: {
				auto* scalarLayoutFeatures = (VkPhysicalDeviceScalarBlockLayoutFeaturesEXT*)next;
				scalarLayoutFeatures->scalarBlockLayout = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_FEATURES_EXT: {
				auto* subgroupSizeFeatures = (VkPhysicalDeviceSubgroupSizeControlFeaturesEXT*)next;
				subgroupSizeFeatures->subgroupSizeControl = _metalFeatures.simdPermute || _metalFeatures.quadPermute;
				subgroupSizeFeatures->computeFullSubgroups = _metalFeatures.simdPermute || _metalFeatures.quadPermute;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXEL_BUFFER_ALIGNMENT_FEATURES_EXT: {
				auto* texelBuffAlignFeatures = (VkPhysicalDeviceTexelBufferAlignmentFeaturesEXT*)next;
				texelBuffAlignFeatures->texelBufferAlignment = _metalFeatures.texelBuffers && [_mtlDevice respondsToSelector: @selector(minimumLinearTextureAlignmentForPixelFormat:)];
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXTURE_COMPRESSION_ASTC_HDR_FEATURES_EXT: {
				auto* astcHDRFeatures = (VkPhysicalDeviceTextureCompressionASTCHDRFeaturesEXT*)next;
				astcHDRFeatures->textureCompressionASTC_HDR = _metalFeatures.astcHDRTextures;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VERTEX_ATTRIBUTE_DIVISOR_FEATURES_EXT: {
				auto* divisorFeatures = (VkPhysicalDeviceVertexAttributeDivisorFeaturesEXT*)next;
				divisorFeatures->vertexAttributeInstanceRateDivisor = true;
				divisorFeatures->vertexAttributeInstanceRateZeroDivisor = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR: {
				auto* portabilityFeatures = (VkPhysicalDevicePortabilitySubsetFeaturesKHR*)next;
				portabilityFeatures->constantAlphaColorBlendFactors = true;
				portabilityFeatures->events = true;
				portabilityFeatures->imageViewFormatReinterpretation = true;
				portabilityFeatures->imageViewFormatSwizzle = (_metalFeatures.nativeTextureSwizzle ||
															   _mvkInstance->getMoltenVKConfiguration()->fullImageViewSwizzle);
				portabilityFeatures->imageView2DOn3DImage = false;
				portabilityFeatures->multisampleArrayImage = _metalFeatures.multisampleArrayTextures;
				portabilityFeatures->mutableComparisonSamplers = _metalFeatures.depthSampleCompare;
				portabilityFeatures->pointPolygons = false;
				portabilityFeatures->samplerMipLodBias = false;
				portabilityFeatures->separateStencilMaskRef = true;
				portabilityFeatures->shaderSampleRateInterpolationFunctions = _metalFeatures.pullModelInterpolation;
				portabilityFeatures->tessellationIsolines = false;
				portabilityFeatures->tessellationPointMode = false;
				portabilityFeatures->triangleFans = false;
				portabilityFeatures->vertexAttributeAccessBeyondStride = true;	// Costs additional buffers. Should make configuration switch.
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_INTEGER_FUNCTIONS_2_FEATURES_INTEL: {
				auto* shaderIntFuncsFeatures = (VkPhysicalDeviceShaderIntegerFunctions2FeaturesINTEL*)next;
				shaderIntFuncsFeatures->shaderIntegerFunctions2 = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_INLINE_UNIFORM_BLOCK_FEATURES_EXT: {
				auto* inlineUniformBlockFeatures = (VkPhysicalDeviceInlineUniformBlockFeaturesEXT*)next;
				inlineUniformBlockFeatures->inlineUniformBlock = true;
				inlineUniformBlockFeatures->descriptorBindingInlineUniformBlockUpdateAfterBind = true;
				break;
			}
			default:
				break;
		}
	}
}

void MVKPhysicalDevice::getProperties(VkPhysicalDeviceProperties* properties) {
	*properties = _properties;
}

void MVKPhysicalDevice::getProperties(VkPhysicalDeviceProperties2* properties) {
	properties->sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
	properties->properties = _properties;
	for (auto* next = (VkBaseOutStructure*)properties->pNext; next; next = next->pNext) {
		switch ((uint32_t)next->sType) {
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DEPTH_STENCIL_RESOLVE_PROPERTIES: {
				auto* depthStencilResolveProps = (VkPhysicalDeviceDepthStencilResolveProperties*)next;

				// We can always support resolve from sample zero. Other modes require additional capabilities.
				depthStencilResolveProps->supportedDepthResolveModes = VK_RESOLVE_MODE_SAMPLE_ZERO_BIT;
				if (_metalFeatures.depthResolve) {
					depthStencilResolveProps->supportedDepthResolveModes |= VK_RESOLVE_MODE_MIN_BIT | VK_RESOLVE_MODE_MAX_BIT;
				}
				// Metal allows you to set the stencil resolve filter to either
				// Sample0 or DepthResolvedSample--in other words, you can always use sample 0,
				// but you can also use the sample chosen for depth resolve. This is impossible
				// to express in Vulkan.
				depthStencilResolveProps->supportedStencilResolveModes = VK_RESOLVE_MODE_SAMPLE_ZERO_BIT;
				depthStencilResolveProps->independentResolveNone = true;
				depthStencilResolveProps->independentResolve = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES: {
				auto* physicalDeviceDriverProps = (VkPhysicalDeviceDriverPropertiesKHR*)next;
				strcpy(physicalDeviceDriverProps->driverName, "MoltenVK");
				strcpy(physicalDeviceDriverProps->driverInfo, mvkGetMoltenVKVersionString(MVK_VERSION).c_str());
				physicalDeviceDriverProps->driverID = VK_DRIVER_ID_MOLTENVK;
				physicalDeviceDriverProps->conformanceVersion.major = 0;
				physicalDeviceDriverProps->conformanceVersion.minor = 0;
				physicalDeviceDriverProps->conformanceVersion.subminor = 0;
				physicalDeviceDriverProps->conformanceVersion.patch = 0;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES: {
				populate((VkPhysicalDeviceIDProperties*)next);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_3_PROPERTIES: {
				auto* maint3Props = (VkPhysicalDeviceMaintenance3Properties*)next;
				maint3Props->maxPerSetDescriptors = (_metalFeatures.maxPerStageBufferCount + _metalFeatures.maxPerStageTextureCount + _metalFeatures.maxPerStageSamplerCount) * 4;
				maint3Props->maxMemoryAllocationSize = _metalFeatures.maxMTLBufferSize;
				break;
			}
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MULTIVIEW_PROPERTIES: {
                auto* multiviewProps = (VkPhysicalDeviceMultiviewProperties*)next;
                multiviewProps->maxMultiviewViewCount = 32;
                if (canUseInstancingForMultiview()) {
                    multiviewProps->maxMultiviewInstanceIndex = std::numeric_limits<uint32_t>::max() / 32;
                } else {
                    multiviewProps->maxMultiviewInstanceIndex = std::numeric_limits<uint32_t>::max();
                }
				break;
            }
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_POINT_CLIPPING_PROPERTIES: {
				auto* pointClipProps = (VkPhysicalDevicePointClippingProperties*)next;
				pointClipProps->pointClippingBehavior = VK_POINT_CLIPPING_BEHAVIOR_ALL_CLIP_PLANES;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROTECTED_MEMORY_PROPERTIES: {
				auto* protectedMemProps = (VkPhysicalDeviceProtectedMemoryProperties*)next;
				protectedMemProps->protectedNoFault = false;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PUSH_DESCRIPTOR_PROPERTIES_KHR: {
				auto* pushDescProps = (VkPhysicalDevicePushDescriptorPropertiesKHR*)next;
				pushDescProps->maxPushDescriptors = _properties.limits.maxPerStageResources;
				break;
			}
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_PROPERTIES: {
                auto* subgroupProps = (VkPhysicalDeviceSubgroupProperties*)next;
                subgroupProps->subgroupSize = _metalFeatures.maxSubgroupSize;
                subgroupProps->supportedStages = VK_SHADER_STAGE_COMPUTE_BIT;
                if (_features.tessellationShader) {
                    subgroupProps->supportedStages |= VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT;
                }
                if (mvkOSVersionIsAtLeast(10.15, 13.0)) {
                    subgroupProps->supportedStages |= VK_SHADER_STAGE_FRAGMENT_BIT;
                }
                subgroupProps->supportedOperations = VK_SUBGROUP_FEATURE_BASIC_BIT;
                if (_metalFeatures.simdPermute || _metalFeatures.quadPermute) {
                    subgroupProps->supportedOperations |= VK_SUBGROUP_FEATURE_VOTE_BIT |
                        VK_SUBGROUP_FEATURE_BALLOT_BIT |
                        VK_SUBGROUP_FEATURE_SHUFFLE_BIT |
                        VK_SUBGROUP_FEATURE_SHUFFLE_RELATIVE_BIT;
                }
                if (_metalFeatures.simdReduction) {
                    subgroupProps->supportedOperations |= VK_SUBGROUP_FEATURE_ARITHMETIC_BIT;
                }
                if (_metalFeatures.quadPermute) {
                    subgroupProps->supportedOperations |= VK_SUBGROUP_FEATURE_QUAD_BIT;
                }
                subgroupProps->quadOperationsInAllStages = _metalFeatures.quadPermute;
				break;
            }
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_PROPERTIES: {
                auto* timelineSem4Props = (VkPhysicalDeviceTimelineSemaphoreProperties*)next;
                timelineSem4Props->maxTimelineSemaphoreValueDifference = std::numeric_limits<uint64_t>::max();
                break;
            }
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES_EXT: {
				bool isTier2 = _metalFeatures.argumentBuffers && _mtlDevice.argumentBuffersSupport == MTLArgumentBuffersTier2;
				auto* pDescIdxProps = (VkPhysicalDeviceDescriptorIndexingPropertiesEXT*)next;
				pDescIdxProps->maxUpdateAfterBindDescriptorsInAllPools				= kMVKUndefinedLargeUInt32;
				pDescIdxProps->shaderUniformBufferArrayNonUniformIndexingNative		= false;
				pDescIdxProps->shaderSampledImageArrayNonUniformIndexingNative		= _metalFeatures.arrayOfTextures && _metalFeatures.arrayOfSamplers;
				pDescIdxProps->shaderStorageBufferArrayNonUniformIndexingNative		= false;
				pDescIdxProps->shaderStorageImageArrayNonUniformIndexingNative		= _metalFeatures.arrayOfTextures;
				pDescIdxProps->shaderInputAttachmentArrayNonUniformIndexingNative	= _metalFeatures.arrayOfTextures;
				pDescIdxProps->robustBufferAccessUpdateAfterBind					= _features.robustBufferAccess;
				pDescIdxProps->quadDivergentImplicitLod								= false;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindSamplers			= isTier2 ? 2048 : _properties.limits.maxPerStageDescriptorSamplers;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindUniformBuffers	= isTier2 ? 500000 : _properties.limits.maxPerStageDescriptorUniformBuffers;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindStorageBuffers	= isTier2 ? 500000 : _properties.limits.maxPerStageDescriptorStorageBuffers;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindSampledImages	= isTier2 ? 500000 : _properties.limits.maxPerStageDescriptorSampledImages;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindStorageImages	= isTier2 ? 500000 : _properties.limits.maxPerStageDescriptorStorageImages;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindInputAttachments	= _properties.limits.maxPerStageDescriptorInputAttachments;
				pDescIdxProps->maxPerStageUpdateAfterBindResources					= isTier2 ? 500000 : _properties.limits.maxPerStageResources;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindSamplers				= isTier2 ? 2048 : _properties.limits.maxDescriptorSetSamplers;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindUniformBuffers		= isTier2 ? 500000 : _properties.limits.maxDescriptorSetUniformBuffers;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindUniformBuffersDynamic	= isTier2 ? 500000 : _properties.limits.maxDescriptorSetUniformBuffersDynamic;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindStorageBuffers		= isTier2 ? 500000 : _properties.limits.maxDescriptorSetStorageBuffers;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindStorageBuffersDynamic	= isTier2 ? 500000 : _properties.limits.maxDescriptorSetStorageBuffersDynamic;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindSampledImages			= isTier2 ? 500000 : _properties.limits.maxDescriptorSetSampledImages;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindStorageImages			= isTier2 ? 500000 : _properties.limits.maxDescriptorSetStorageImages;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindInputAttachments		= _properties.limits.maxDescriptorSetInputAttachments;
				break;
			}
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_INLINE_UNIFORM_BLOCK_PROPERTIES_EXT: {
				auto* inlineUniformBlockProps = (VkPhysicalDeviceInlineUniformBlockPropertiesEXT*)next;
				inlineUniformBlockProps->maxInlineUniformBlockSize = _metalFeatures.dynamicMTLBufferSize;
                inlineUniformBlockProps->maxPerStageDescriptorInlineUniformBlocks = _metalFeatures.dynamicMTLBufferSize ? _metalFeatures.maxPerStageDynamicMTLBufferCount - 1 : 0;    // Less one for push constants
                inlineUniformBlockProps->maxPerStageDescriptorUpdateAfterBindInlineUniformBlocks = inlineUniformBlockProps->maxPerStageDescriptorInlineUniformBlocks;
                inlineUniformBlockProps->maxDescriptorSetInlineUniformBlocks = (inlineUniformBlockProps->maxPerStageDescriptorInlineUniformBlocks * 4);
                inlineUniformBlockProps->maxDescriptorSetUpdateAfterBindInlineUniformBlocks = (inlineUniformBlockProps->maxPerStageDescriptorUpdateAfterBindInlineUniformBlocks * 4);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_PROPERTIES_EXT: {
				auto* robustness2Props = (VkPhysicalDeviceRobustness2PropertiesEXT*)next;
				// This isn't implemented yet, but when it is, I expect that we'll wind up
				// doing it manually.
				robustness2Props->robustStorageBufferAccessSizeAlignment = 1;
				robustness2Props->robustUniformBufferAccessSizeAlignment = 1;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_PROPERTIES_EXT: {
				auto* subgroupSizeProps = (VkPhysicalDeviceSubgroupSizeControlPropertiesEXT*)next;
				subgroupSizeProps->minSubgroupSize = _metalFeatures.minSubgroupSize;
				subgroupSizeProps->maxSubgroupSize = _metalFeatures.maxSubgroupSize;
				subgroupSizeProps->maxComputeWorkgroupSubgroups = _properties.limits.maxComputeWorkGroupInvocations / _metalFeatures.minSubgroupSize;
				subgroupSizeProps->requiredSubgroupSizeStages = 0;
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
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_PROPERTIES_KHR: {
				auto* portabilityProps = (VkPhysicalDevicePortabilitySubsetPropertiesKHR*)next;
				portabilityProps->minVertexInputBindingStrideAlignment = (uint32_t)_metalFeatures.vertexStrideAlignment;
				break;
			}
			default:
				break;
		}
	}
}

// Populates the device ID properties structure
void MVKPhysicalDevice::populate(VkPhysicalDeviceIDProperties* pDevIdProps) {

	size_t uuidComponentOffset;

	//  ---- Device ID ----------------------------------------------
	uuidComponentOffset = 0;
	mvkClear(&pDevIdProps->deviceUUID);

	// First 4 bytes contains GPU vendor ID
	uint32_t vendorID = _properties.vendorID;
	*(uint32_t*)&pDevIdProps->deviceUUID[uuidComponentOffset] = NSSwapHostIntToBig(vendorID);
	uuidComponentOffset += sizeof(vendorID);

	// Next 4 bytes contains GPU device ID
	uint32_t deviceID = _properties.deviceID;
	*(uint32_t*)&pDevIdProps->deviceUUID[uuidComponentOffset] = NSSwapHostIntToBig(deviceID);
	uuidComponentOffset += sizeof(deviceID);

	// Last 8 bytes contain the GPU registry ID
	uint64_t regID = mvkGetRegistryID(_mtlDevice);
	*(uint64_t*)&pDevIdProps->deviceUUID[uuidComponentOffset] = NSSwapHostLongLongToBig(regID);
	uuidComponentOffset += sizeof(regID);


	// ---- Driver ID ----------------------------------------------
	uuidComponentOffset = 0;
	mvkClear(&pDevIdProps->driverUUID);

	// First 4 bytes contains MoltenVK prefix
	const char* mvkPfx = "MVK";
	size_t mvkPfxLen = strlen(mvkPfx);
	mvkCopy(&pDevIdProps->driverUUID[uuidComponentOffset], (uint8_t*)mvkPfx, mvkPfxLen);
	uuidComponentOffset += mvkPfxLen + 1;

	// Next 4 bytes contains MoltenVK version
	uint32_t mvkVersion = MVK_VERSION;
	*(uint32_t*)&pDevIdProps->driverUUID[uuidComponentOffset] = NSSwapHostIntToBig(mvkVersion);
	uuidComponentOffset += sizeof(mvkVersion);

	// Next 4 bytes contains highest Metal feature set supported by this device
	uint32_t mtlFeatSet = getHighestMTLFeatureSet();
	*(uint32_t*)&pDevIdProps->driverUUID[uuidComponentOffset] = NSSwapHostIntToBig(mtlFeatSet);
	uuidComponentOffset += sizeof(mtlFeatSet);


	// ---- LUID ignored for Metal devices ------------------------
	mvkClear(&pDevIdProps->deviceLUID);
	pDevIdProps->deviceNodeMask = 0;
	pDevIdProps->deviceLUIDValid = VK_FALSE;
}

void MVKPhysicalDevice::getFormatProperties(VkFormat format, VkFormatProperties* pFormatProperties) {
	*pFormatProperties = _pixelFormats.getVkFormatProperties(format);
}

void MVKPhysicalDevice::getFormatProperties(VkFormat format, VkFormatProperties2KHR* pFormatProperties) {
	pFormatProperties->sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2_KHR;
	getFormatProperties(format, &pFormatProperties->formatProperties);
}

VkResult MVKPhysicalDevice::getImageFormatProperties(VkFormat format,
													 VkImageType type,
													 VkImageTiling tiling,
													 VkImageUsageFlags usage,
													 VkImageCreateFlags flags,
													 VkImageFormatProperties* pImageFormatProperties) {

	if ( !_pixelFormats.isSupported(format) ) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

	if ( !pImageFormatProperties ) { return VK_SUCCESS; }

	mvkClear(pImageFormatProperties);

	// Metal does not support creating uncompressed views of compressed formats.
	// Metal does not support split-instance images.
	if (mvkIsAnyFlagEnabled(flags, VK_IMAGE_CREATE_BLOCK_TEXEL_VIEW_COMPATIBLE_BIT | VK_IMAGE_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT)) {
		return VK_ERROR_FORMAT_NOT_SUPPORTED;
	}

	MVKFormatType mvkFmt = _pixelFormats.getFormatType(format);
	bool isChromaSubsampled = _pixelFormats.getChromaSubsamplingPlaneCount(format) > 0;
	bool isMultiPlanar = _pixelFormats.getChromaSubsamplingPlaneCount(format) > 1;
	bool isBGRG = isChromaSubsampled && !isMultiPlanar && _pixelFormats.getBlockTexelSize(format).width > 1;
	bool hasAttachmentUsage = mvkIsAnyFlagEnabled(usage, (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
														  VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
														  VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT |
														  VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT));

	// Disjoint memory requires a multiplanar format.
	if (!isMultiPlanar && mvkIsAnyFlagEnabled(flags, VK_IMAGE_CREATE_DISJOINT_BIT)) {
		return VK_ERROR_FORMAT_NOT_SUPPORTED;
	}

	VkPhysicalDeviceLimits* pLimits = &_properties.limits;
	VkExtent3D maxExt = { 1, 1, 1};
	uint32_t maxLevels = 1;
	uint32_t maxLayers = hasAttachmentUsage ? pLimits->maxFramebufferLayers : pLimits->maxImageArrayLayers;

	bool supportsMSAA =  mvkAreAllFlagsEnabled(_pixelFormats.getCapabilities(format), kMVKMTLFmtCapsMSAA);
	VkSampleCountFlags sampleCounts = supportsMSAA ? _metalFeatures.supportedSampleCounts : VK_SAMPLE_COUNT_1_BIT;

	switch (type) {
		case VK_IMAGE_TYPE_1D:
			maxExt.height = 1;
			maxExt.depth = 1;
			if (!mvkTreatTexture1DAs2D()) {
				maxExt.width = pLimits->maxImageDimension1D;
				maxLevels = 1;
				sampleCounts = VK_SAMPLE_COUNT_1_BIT;

				// Metal does not allow native 1D textures to be used as attachments
				if (hasAttachmentUsage ) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

				// Metal does not allow linear tiling on native 1D textures
				if (tiling == VK_IMAGE_TILING_LINEAR) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

				// Metal does not allow compressed or depth/stencil formats on native 1D textures
				if (mvkFmt == kMVKFormatDepthStencil) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }
				if (mvkFmt == kMVKFormatCompressed) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }
				if (isChromaSubsampled) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }
				break;
			}

			// A 420 1D image doesn't make much sense.
			if (isChromaSubsampled && _pixelFormats.getBlockTexelSize(format).height > 1) {
				return VK_ERROR_FORMAT_NOT_SUPPORTED;
			}
			// Vulkan doesn't allow 1D multisampled images.
			sampleCounts = VK_SAMPLE_COUNT_1_BIT;
			/* fallthrough */
		case VK_IMAGE_TYPE_2D:
			if (mvkIsAnyFlagEnabled(flags, VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT) ) {
				// Chroma-subsampled cube images aren't supported.
				if (isChromaSubsampled) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }
				// 1D cube images aren't supported.
				if (type == VK_IMAGE_TYPE_1D) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }
				maxExt.width = pLimits->maxImageDimensionCube;
				maxExt.height = pLimits->maxImageDimensionCube;
			} else {
				maxExt.width = pLimits->maxImageDimension2D;
				maxExt.height = (type == VK_IMAGE_TYPE_1D ? 1 : pLimits->maxImageDimension2D);
			}
			maxExt.depth = 1;
			if (tiling == VK_IMAGE_TILING_LINEAR) {
				// Linear textures have additional restrictions under Metal:
				// - They may not be depth/stencil, compressed, or chroma subsampled textures.
				//   We allow multi-planar formats because those internally use non-subsampled formats.
				if (mvkFmt == kMVKFormatDepthStencil || mvkFmt == kMVKFormatCompressed || isBGRG) {
					return VK_ERROR_FORMAT_NOT_SUPPORTED;
				}
#if MVK_MACOS
				// - On macOS, Linear textures may not be used as framebuffer attachments.
				if (hasAttachmentUsage) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }
#endif
				// Linear textures may only have one mip level, layer & sample.
				maxLevels = 1;
				maxLayers = 1;
				sampleCounts = VK_SAMPLE_COUNT_1_BIT;
			} else {
				VkFormatProperties fmtProps;
				getFormatProperties(format, &fmtProps);
				// Compressed multisampled textures aren't supported.
				// Chroma-subsampled multisampled textures aren't supported.
				// Multisampled cube textures aren't supported.
				// Non-renderable multisampled textures aren't supported.
				if (mvkFmt == kMVKFormatCompressed || isChromaSubsampled ||
					mvkIsAnyFlagEnabled(flags, VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT) ||
					!mvkIsAnyFlagEnabled(fmtProps.optimalTilingFeatures, VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT|VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) ) {
					sampleCounts = VK_SAMPLE_COUNT_1_BIT;
				}
				// BGRG and GBGR images may only have one mip level and one layer.
				// Other chroma subsampled formats may have multiple mip levels, but still only one layer.
				if (isChromaSubsampled) {
					maxLevels = isBGRG ? 1 : mvkMipmapLevels3D(maxExt);
					maxLayers = 1;
				} else {
					maxLevels = mvkMipmapLevels3D(maxExt);
				}
			}
			break;

		case VK_IMAGE_TYPE_3D:
			// Metal does not allow linear tiling on 3D textures
			if (tiling == VK_IMAGE_TILING_LINEAR) {
				return VK_ERROR_FORMAT_NOT_SUPPORTED;
			}
			// Metal does not allow compressed or depth/stencil formats on 3D textures
			if (mvkFmt == kMVKFormatDepthStencil ||
				isChromaSubsampled
#if MVK_IOS_OR_TVOS
				|| (mvkFmt == kMVKFormatCompressed && !_metalFeatures.native3DCompressedTextures)
#endif
				) {
				return VK_ERROR_FORMAT_NOT_SUPPORTED;
			}
#if MVK_MACOS
			// If this is a compressed format and there's no codec, it isn't supported.
			if ((mvkFmt == kMVKFormatCompressed) && !mvkCanDecodeFormat(format) && !_metalFeatures.native3DCompressedTextures) {
				return VK_ERROR_FORMAT_NOT_SUPPORTED;
			}
#endif
#if MVK_IOS_OR_TVOS || MVK_MACOS_APPLE_SILICON
			// ETC2 and EAC formats aren't supported for 3D textures.
			switch (format) {
				case VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK:
				case VK_FORMAT_ETC2_R8G8B8_SRGB_BLOCK:
				case VK_FORMAT_ETC2_R8G8B8A1_UNORM_BLOCK:
				case VK_FORMAT_ETC2_R8G8B8A1_SRGB_BLOCK:
				case VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK:
				case VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK:
				case VK_FORMAT_EAC_R11_UNORM_BLOCK:
				case VK_FORMAT_EAC_R11_SNORM_BLOCK:
				case VK_FORMAT_EAC_R11G11_UNORM_BLOCK:
				case VK_FORMAT_EAC_R11G11_SNORM_BLOCK:
					return VK_ERROR_FORMAT_NOT_SUPPORTED;
				default:
					break;
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
			return VK_ERROR_FORMAT_NOT_SUPPORTED;	// Illegal VkImageType
	}

	pImageFormatProperties->maxExtent = maxExt;
	pImageFormatProperties->maxMipLevels = maxLevels;
	pImageFormatProperties->maxArrayLayers = maxLayers;
	pImageFormatProperties->sampleCounts = sampleCounts;
	pImageFormatProperties->maxResourceSize = kMVKUndefinedLargeUInt64;

	return VK_SUCCESS;
}

VkResult MVKPhysicalDevice::getImageFormatProperties(const VkPhysicalDeviceImageFormatInfo2 *pImageFormatInfo,
													 VkImageFormatProperties2* pImageFormatProperties) {

	for (const auto* nextInfo = (VkBaseInStructure*)pImageFormatInfo->pNext; nextInfo; nextInfo = nextInfo->pNext) {
		switch (nextInfo->sType) {
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO: {
				// Return information about external memory support for MTLTexture.
				// Search VkImageFormatProperties2 for the corresponding VkExternalImageFormatProperties and populate it.
				auto* pExtImgFmtInfo = (VkPhysicalDeviceExternalImageFormatInfo*)nextInfo;
				for (auto* nextProps = (VkBaseOutStructure*)pImageFormatProperties->pNext; nextProps; nextProps = nextProps->pNext) {
					if (nextProps->sType == VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES) {
						auto* pExtImgFmtProps = (VkExternalImageFormatProperties*)nextProps;
						pExtImgFmtProps->externalMemoryProperties = getExternalImageProperties(pExtImgFmtInfo->handleType);
					}
				}
				break;
			}
			default:
				break;
		}
	}

    for (const auto* nextProps = (VkBaseInStructure*)pImageFormatProperties->pNext; nextProps; nextProps = nextProps->pNext) {
        switch (nextProps->sType) {
            case VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_IMAGE_FORMAT_PROPERTIES: {
                auto* samplerYcbcrConvProps = (VkSamplerYcbcrConversionImageFormatProperties*)nextProps;
                samplerYcbcrConvProps->combinedImageSamplerDescriptorCount = std::max(_pixelFormats.getChromaSubsamplingPlaneCount(pImageFormatInfo->format), (uint8_t)1u);
                break;
            }
            default:
                break;
        }
    }

	if ( !_pixelFormats.isSupported(pImageFormatInfo->format) ) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }

	return getImageFormatProperties(pImageFormatInfo->format, pImageFormatInfo->type,
									pImageFormatInfo->tiling, pImageFormatInfo->usage,
									pImageFormatInfo->flags,
									&pImageFormatProperties->imageFormatProperties);
}

void MVKPhysicalDevice::getExternalBufferProperties(const VkPhysicalDeviceExternalBufferInfo* pExternalBufferInfo,
													VkExternalBufferProperties* pExternalBufferProperties) {
	pExternalBufferProperties->externalMemoryProperties = getExternalBufferProperties(pExternalBufferInfo->handleType);
}

static VkExternalMemoryProperties _emptyExtMemProps = {};

VkExternalMemoryProperties& MVKPhysicalDevice::getExternalBufferProperties(VkExternalMemoryHandleTypeFlagBits handleType) {
	switch (handleType) {
		case VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_KHR:		return _mtlBufferExternalMemoryProperties;
		default: 													return _emptyExtMemProps;
	}
}

VkExternalMemoryProperties& MVKPhysicalDevice::getExternalImageProperties(VkExternalMemoryHandleTypeFlagBits handleType) {
	switch (handleType) {
		case VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR:		return _mtlTextureExternalMemoryProperties;
		default: 													return _emptyExtMemProps;
	}
}

static const VkExternalFenceProperties _emptyExtFenceProps = {VK_STRUCTURE_TYPE_EXTERNAL_FENCE_PROPERTIES, nullptr, 0, 0, 0};

void MVKPhysicalDevice::getExternalFenceProperties(const VkPhysicalDeviceExternalFenceInfo* pExternalFenceInfo,
												   VkExternalFenceProperties* pExternalFenceProperties) {
	void* next = pExternalFenceProperties->pNext;
	*pExternalFenceProperties = _emptyExtFenceProps;
	pExternalFenceProperties->pNext = next;
}

static const VkExternalSemaphoreProperties _emptyExtSemProps = {VK_STRUCTURE_TYPE_EXTERNAL_SEMAPHORE_PROPERTIES, nullptr, 0, 0, 0};

void MVKPhysicalDevice::getExternalSemaphoreProperties(const VkPhysicalDeviceExternalSemaphoreInfo* pExternalSemaphoreInfo,
													   VkExternalSemaphoreProperties* pExternalSemaphoreProperties) {
	void* next = pExternalSemaphoreProperties->pNext;
	*pExternalSemaphoreProperties = _emptyExtSemProps;
	pExternalSemaphoreProperties->pNext = next;
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
	pSurfaceCapabilities->minImageExtent = { 1, 1 };
	pSurfaceCapabilities->maxImageExtent = { _properties.limits.maxImageDimension2D, _properties.limits.maxImageDimension2D };
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

#define addSurfFmt(FMT) { if (_pixelFormats.isSupported(FMT)) { mtlFormats.push_back(FMT); } }

	MVKSmallVector<MTLPixelFormat, 16> mtlFormats;
	addSurfFmt(MTLPixelFormatBGRA8Unorm);
	addSurfFmt(MTLPixelFormatBGRA8Unorm_sRGB);
	addSurfFmt(MTLPixelFormatRGBA16Float);
#if MVK_MACOS
	addSurfFmt(MTLPixelFormatRGB10A2Unorm);
	addSurfFmt(MTLPixelFormatBGR10A2Unorm);
#if MVK_MACOS_APPLE_SILICON
	if (supportsMTLGPUFamily(Apple5)) {
		addSurfFmt(MTLPixelFormatBGRA10_XR);
		addSurfFmt(MTLPixelFormatBGRA10_XR_sRGB);
		addSurfFmt(MTLPixelFormatBGR10_XR);
		addSurfFmt(MTLPixelFormatBGR10_XR_sRGB);
	}
#endif
#endif
#if MVK_IOS_OR_TVOS
	addSurfFmt(MTLPixelFormatBGRA10_XR);
	addSurfFmt(MTLPixelFormatBGRA10_XR_sRGB);
	addSurfFmt(MTLPixelFormatBGR10_XR);
	addSurfFmt(MTLPixelFormatBGR10_XR_sRGB);
#endif

	MVKSmallVector<VkColorSpaceKHR, 16> colorSpaces;
	colorSpaces.push_back(VK_COLOR_SPACE_SRGB_NONLINEAR_KHR);
	if (getInstance()->_enabledExtensions.vk_EXT_swapchain_colorspace.enabled) {
#if MVK_MACOS
		// 10.11 supports some but not all of the color spaces specified by VK_EXT_swapchain_colorspace.
		colorSpaces.push_back(VK_COLOR_SPACE_DISPLAY_P3_NONLINEAR_EXT);
		colorSpaces.push_back(VK_COLOR_SPACE_DCI_P3_NONLINEAR_EXT);
		colorSpaces.push_back(VK_COLOR_SPACE_BT709_NONLINEAR_EXT);
		colorSpaces.push_back(VK_COLOR_SPACE_ADOBERGB_NONLINEAR_EXT);
		colorSpaces.push_back(VK_COLOR_SPACE_PASS_THROUGH_EXT);
		if (mvkOSVersionIsAtLeast(10.12)) {
			colorSpaces.push_back(VK_COLOR_SPACE_EXTENDED_SRGB_LINEAR_EXT);
			colorSpaces.push_back(VK_COLOR_SPACE_EXTENDED_SRGB_NONLINEAR_EXT);
		}
		if (mvkOSVersionIsAtLeast(10.14)) {
			colorSpaces.push_back(VK_COLOR_SPACE_DISPLAY_P3_LINEAR_EXT);
			colorSpaces.push_back(VK_COLOR_SPACE_BT2020_LINEAR_EXT);
		}
// Awaiting Xcode 12 with macOS 11.0 and iOS/tvOS 14 SDK to build.
// Coordinate with MVKSwapchain::initCAMetalLayer().
//		if (mvkOSVersionIsAtLeast(11.0)) {
//			colorSpaces.push_back(VK_COLOR_SPACE_HDR10_HLG_EXT);
//			colorSpaces.push_back(VK_COLOR_SPACE_HDR10_ST2084_EXT);
//		}
#endif
#if MVK_IOS_OR_TVOS
		// iOS 8 doesn't support anything but sRGB.
		if (mvkOSVersionIsAtLeast(9.0)) {
			colorSpaces.push_back(VK_COLOR_SPACE_DISPLAY_P3_NONLINEAR_EXT);
			colorSpaces.push_back(VK_COLOR_SPACE_DCI_P3_NONLINEAR_EXT);
			colorSpaces.push_back(VK_COLOR_SPACE_BT709_NONLINEAR_EXT);
			colorSpaces.push_back(VK_COLOR_SPACE_ADOBERGB_NONLINEAR_EXT);
			colorSpaces.push_back(VK_COLOR_SPACE_PASS_THROUGH_EXT);
		}
		if (mvkOSVersionIsAtLeast(10.0)) {
			colorSpaces.push_back(VK_COLOR_SPACE_EXTENDED_SRGB_LINEAR_EXT);
			colorSpaces.push_back(VK_COLOR_SPACE_EXTENDED_SRGB_NONLINEAR_EXT);
		}
		if (mvkOSVersionIsAtLeast(12.3)) {
			colorSpaces.push_back(VK_COLOR_SPACE_DCI_P3_LINEAR_EXT);
			colorSpaces.push_back(VK_COLOR_SPACE_BT2020_LINEAR_EXT);
		}
// Awaiting Xcode 12 with macOS 11.0 and iOS/tvOS 14 SDK to build.
// Coordinate with MVKSwapchain::initCAMetalLayer().
//		if (mvkOSVersionIsAtLeast(14.0)) {
//			colorSpaces.push_back(VK_COLOR_SPACE_HDR10_HLG_EXT);
//			colorSpaces.push_back(VK_COLOR_SPACE_HDR10_ST2084_EXT);
//		}
#endif
	}

	size_t mtlFmtsCnt = mtlFormats.size();
	size_t vkFmtsCnt = mtlFmtsCnt * colorSpaces.size();

	// If properties aren't actually being requested yet, simply update the returned count
	if ( !pSurfaceFormats ) {
		*pCount = (uint32_t)vkFmtsCnt;
		return VK_SUCCESS;
	}

	// Determine how many results we'll return, and return that number
	VkResult result = (*pCount >= vkFmtsCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(*pCount, (uint32_t)vkFmtsCnt);

	// Now populate the supplied array
	for (uint csIdx = 0, idx = 0; idx < *pCount && csIdx < colorSpaces.size(); csIdx++) {
		for (uint fmtIdx = 0; idx < *pCount && fmtIdx < mtlFmtsCnt; fmtIdx++, idx++) {
			pSurfaceFormats[idx].format = _pixelFormats.getVkFormat(mtlFormats[fmtIdx]);
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
MVKArrayRef<MVKQueueFamily*> MVKPhysicalDevice::getQueueFamilies() {
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
	return _queueFamilies.contents();
}

VkResult MVKPhysicalDevice::getQueueFamilyProperties(uint32_t* pCount,
													 VkQueueFamilyProperties* pQueueFamilyProperties) {
	auto qFams = getQueueFamilies();
	uint32_t qfCnt = uint32_t(qFams.size);

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
VkResult MVKPhysicalDevice::getMemoryProperties(VkPhysicalDeviceMemoryProperties* pMemoryProperties) {
	*pMemoryProperties = _memoryProperties;
	return VK_SUCCESS;
}

VkResult MVKPhysicalDevice::getMemoryProperties(VkPhysicalDeviceMemoryProperties2* pMemoryProperties) {
	pMemoryProperties->sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2;
	pMemoryProperties->memoryProperties = _memoryProperties;
	for (auto* next = (VkBaseOutStructure*)pMemoryProperties->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT: {
				auto* budgetProps = (VkPhysicalDeviceMemoryBudgetPropertiesEXT*)next;
				mvkClear(&budgetProps->heapBudget);
				mvkClear(&budgetProps->heapUsage);
				budgetProps->heapBudget[0] = (VkDeviceSize)getRecommendedMaxWorkingSetSize();
				budgetProps->heapUsage[0] = (VkDeviceSize)getCurrentAllocatedSize();
				if (!getHasUnifiedMemory()) {
					budgetProps->heapBudget[1] = (VkDeviceSize)mvkGetAvailableMemorySize();
					budgetProps->heapUsage[1] = (VkDeviceSize)mvkGetUsedMemorySize();
				}
				break;
			}
			default:
				break;
		}
	}
	return VK_SUCCESS;
}


#pragma mark Construction

MVKPhysicalDevice::MVKPhysicalDevice(MVKInstance* mvkInstance, id<MTLDevice> mtlDevice) :
	_mtlDevice([mtlDevice retain]),		// Set first
	_mvkInstance(mvkInstance),
	_supportedExtensions(this, true),
	_pixelFormats(this) {				// Set after _mtlDevice

	initProperties();           		// Call first.
	initMetalFeatures();        		// Call second.
	initFeatures();             		// Call third.
	initLimits();						// Call fourth.
	initExtensions();
	initMemoryProperties();
	initExternalMemoryProperties();
	initPipelineCacheUUID();			// Call penultimate
	logGPUInfo();						// Call last
}

// Initializes the physical device properties (except limits).
void MVKPhysicalDevice::initProperties() {
	mvkClear(&_properties);	// Start with everything cleared

	_properties.apiVersion = MVK_VULKAN_API_VERSION;
	_properties.driverVersion = MVK_VERSION;

	initGPUInfoProperties();
}

// Initializes the Metal-specific physical device features of this instance.
void MVKPhysicalDevice::initMetalFeatures() {

#	ifndef MVK_CONFIG_USE_MTLHEAP
#   	define MVK_CONFIG_USE_MTLHEAP    0
#	endif
	bool useMTLHeaps;
	MVK_SET_FROM_ENV_OR_BUILD_BOOL(useMTLHeaps, MVK_CONFIG_USE_MTLHEAP);

	// Start with all Metal features cleared
	mvkClear(&_metalFeatures);

	_metalFeatures.maxPerStageBufferCount = 31;
    _metalFeatures.maxMTLBufferSize = (256 * MEBI);
    _metalFeatures.dynamicMTLBufferSize = 0;
    _metalFeatures.maxPerStageDynamicMTLBufferCount = 0;

    _metalFeatures.maxPerStageSamplerCount = 16;
    _metalFeatures.maxQueryBufferSize = (64 * KIBI);

	_metalFeatures.pushConstantSizeAlignment = 16;     // Min float4 alignment for typical uniform structs.

	_metalFeatures.maxTextureLayers = (2 * KIBI);

	_metalFeatures.ioSurfaces = MVK_SUPPORT_IOSURFACE_BOOL;

	// Metal supports 2 or 3 concurrent CAMetalLayer drawables.
	_metalFeatures.minSwapchainImageCount = kMVKMinSwapchainImageCount;
	_metalFeatures.maxSwapchainImageCount = kMVKMaxSwapchainImageCount;

	_metalFeatures.vertexStrideAlignment = 4;

	_metalFeatures.maxPerStageStorageTextureCount = 8;

#if MVK_TVOS
	_metalFeatures.mslVersionEnum = MTLLanguageVersion1_1;
    _metalFeatures.mtlBufferAlignment = 64;
	_metalFeatures.mtlCopyBufferAlignment = 1;
    _metalFeatures.texelBuffers = true;
	_metalFeatures.maxTextureDimension = (8 * KIBI);
    _metalFeatures.dynamicMTLBufferSize = (4 * KIBI);
    _metalFeatures.sharedLinearTextures = true;
    _metalFeatures.maxPerStageDynamicMTLBufferCount = _metalFeatures.maxPerStageBufferCount;
	_metalFeatures.renderLinearTextures = true;

    if (supportsMTLFeatureSet(tvOS_GPUFamily1_v2)) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion1_2;
        _metalFeatures.shaderSpecialization = true;
        _metalFeatures.stencilViews = true;
		_metalFeatures.fences = true;
		_metalFeatures.deferredStoreActions = true;
    }

	if (supportsMTLFeatureSet(tvOS_GPUFamily1_v3)) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_0;
        _metalFeatures.renderWithoutAttachments = true;
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(_metalFeatures.argumentBuffers, MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS);
	}

	if (supportsMTLFeatureSet(tvOS_GPUFamily1_v4)) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_1;
		_metalFeatures.events = true;
		_metalFeatures.textureBuffers = true;
	}

	if (supportsMTLFeatureSet(tvOS_GPUFamily2_v1)) {
		_metalFeatures.indirectDrawing = true;
		_metalFeatures.baseVertexInstanceDrawing = true;
		_metalFeatures.combinedStoreResolveAction = true;
		_metalFeatures.mtlBufferAlignment = 16;     // Min float4 alignment for typical vertex buffers. MTLBuffer may go down to 4 bytes for other data.
		_metalFeatures.maxTextureDimension = (16 * KIBI);
		_metalFeatures.depthSampleCompare = true;
		_metalFeatures.arrayOfTextures = true;
		_metalFeatures.arrayOfSamplers = true;
		_metalFeatures.depthResolve = true;
	}

	if ( mvkOSVersionIsAtLeast(13.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_2;
		_metalFeatures.placementHeaps = useMTLHeaps;
		_metalFeatures.nativeTextureSwizzle = true;
		if (supportsMTLGPUFamily(Apple3)) {
			_metalFeatures.native3DCompressedTextures = true;
		}
		if (supportsMTLGPUFamily(Apple4)) {
			_metalFeatures.quadPermute = true;
		}
	}

	if (supportsMTLGPUFamily(Apple4)) {
		_metalFeatures.maxPerStageTextureCount = 96;
	} else {
		_metalFeatures.maxPerStageTextureCount = 31;
	}

#if MVK_XCODE_12
	if ( mvkOSVersionIsAtLeast(14.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_3;
	}
#endif

#endif

#if MVK_IOS
	_metalFeatures.mslVersionEnum = MTLLanguageVersion1_0;
    _metalFeatures.mtlBufferAlignment = 64;
	_metalFeatures.mtlCopyBufferAlignment = 1;
    _metalFeatures.texelBuffers = true;
	_metalFeatures.maxTextureDimension = (4 * KIBI);
    _metalFeatures.sharedLinearTextures = true;
	_metalFeatures.renderLinearTextures = true;

    if (supportsMTLFeatureSet(iOS_GPUFamily1_v2)) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion1_1;
        _metalFeatures.dynamicMTLBufferSize = (4 * KIBI);
		_metalFeatures.maxTextureDimension = (8 * KIBI);
		_metalFeatures.maxPerStageDynamicMTLBufferCount = _metalFeatures.maxPerStageBufferCount;
    }

    if (supportsMTLFeatureSet(iOS_GPUFamily1_v3)) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion1_2;
        _metalFeatures.shaderSpecialization = true;
        _metalFeatures.stencilViews = true;
		_metalFeatures.fences = true;
		_metalFeatures.deferredStoreActions = true;
    }

    if (supportsMTLFeatureSet(iOS_GPUFamily1_v4)) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_0;
        _metalFeatures.renderWithoutAttachments = true;
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(_metalFeatures.argumentBuffers, MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS);
    }

	if (supportsMTLFeatureSet(iOS_GPUFamily1_v5)) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_1;
		_metalFeatures.events = true;
		_metalFeatures.textureBuffers = true;
	}

	if (supportsMTLFeatureSet(iOS_GPUFamily3_v1)) {
		_metalFeatures.indirectDrawing = true;
		_metalFeatures.baseVertexInstanceDrawing = true;
		_metalFeatures.combinedStoreResolveAction = true;
		_metalFeatures.mtlBufferAlignment = 16;     // Min float4 alignment for typical vertex buffers. MTLBuffer may go down to 4 bytes for other data.
		_metalFeatures.maxTextureDimension = (16 * KIBI);
		_metalFeatures.depthSampleCompare = true;
		_metalFeatures.depthResolve = true;
	}

	if (supportsMTLFeatureSet(iOS_GPUFamily3_v2)) {
		_metalFeatures.arrayOfTextures = true;
	}
	if (supportsMTLFeatureSet(iOS_GPUFamily3_v3)) {
		_metalFeatures.arrayOfSamplers = true;
	}

	if (supportsMTLFeatureSet(iOS_GPUFamily4_v1)) {
		_metalFeatures.postDepthCoverage = true;
		_metalFeatures.nonUniformThreadgroups = true;
	}

	if (supportsMTLFeatureSet(iOS_GPUFamily5_v1)) {
		_metalFeatures.layeredRendering = true;
		_metalFeatures.stencilFeedback = true;
		_metalFeatures.indirectTessellationDrawing = true;
		_metalFeatures.stencilResolve = true;
	}

	if ( mvkOSVersionIsAtLeast(13.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_2;
		_metalFeatures.placementHeaps = useMTLHeaps;
		_metalFeatures.nativeTextureSwizzle = true;
		if (supportsMTLGPUFamily(Apple3)) {
			_metalFeatures.native3DCompressedTextures = true;
		}
		if (supportsMTLGPUFamily(Apple4)) {
			_metalFeatures.quadPermute = true;
		}
		if (supportsMTLGPUFamily(Apple6) ) {
			_metalFeatures.astcHDRTextures = true;
			_metalFeatures.simdPermute = true;
		}
	}

	if (supportsMTLGPUFamily(Apple4)) {
		_metalFeatures.maxPerStageTextureCount = 96;
	} else {
		_metalFeatures.maxPerStageTextureCount = 31;
	}

#if MVK_XCODE_12
	if ( mvkOSVersionIsAtLeast(14.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_3;
        _metalFeatures.multisampleArrayTextures = true;
		if ( supportsMTLGPUFamily(Apple7) ) {
			_metalFeatures.maxQueryBufferSize = (256 * KIBI);
			_metalFeatures.multisampleLayeredRendering = _metalFeatures.layeredRendering;
			_metalFeatures.samplerClampToBorder = true;
			_metalFeatures.samplerMirrorClampToEdge = true;
			_metalFeatures.simdReduction = true;
		}
	}
#endif

#endif

#if MVK_MACOS
	_metalFeatures.mslVersionEnum = MTLLanguageVersion1_1;
    _metalFeatures.maxPerStageTextureCount = 128;
    _metalFeatures.mtlBufferAlignment = 256;
	_metalFeatures.mtlCopyBufferAlignment = 4;
	_metalFeatures.baseVertexInstanceDrawing = true;
	_metalFeatures.layeredRendering = true;
	_metalFeatures.maxTextureDimension = (16 * KIBI);
	_metalFeatures.depthSampleCompare = true;
	_metalFeatures.samplerMirrorClampToEdge = true;

    if (supportsMTLFeatureSet(macOS_GPUFamily1_v2)) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion1_2;
		_metalFeatures.indirectDrawing = true;
		_metalFeatures.indirectTessellationDrawing = true;
        _metalFeatures.dynamicMTLBufferSize = (4 * KIBI);
        _metalFeatures.shaderSpecialization = true;
        _metalFeatures.stencilViews = true;
        _metalFeatures.samplerClampToBorder = true;
        _metalFeatures.combinedStoreResolveAction = true;
		_metalFeatures.deferredStoreActions = true;
        _metalFeatures.maxMTLBufferSize = (1 * GIBI);
        _metalFeatures.maxPerStageDynamicMTLBufferCount = 14;
    }

    if (supportsMTLFeatureSet(macOS_GPUFamily1_v3)) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_0;
        _metalFeatures.texelBuffers = true;
		_metalFeatures.arrayOfTextures = true;
		_metalFeatures.arrayOfSamplers = true;
		_metalFeatures.presentModeImmediate = true;
		_metalFeatures.fences = true;
		_metalFeatures.nonUniformThreadgroups = true;
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(_metalFeatures.argumentBuffers, MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS);
    }

    if (supportsMTLFeatureSet(macOS_GPUFamily1_v4)) {
        _metalFeatures.mslVersionEnum = MTLLanguageVersion2_1;
        _metalFeatures.multisampleArrayTextures = true;
		_metalFeatures.events = true;
        _metalFeatures.memoryBarriers = true;
        _metalFeatures.textureBuffers = true;
		_metalFeatures.quadPermute = true;
		_metalFeatures.simdPermute = true;
    }

	if (supportsMTLFeatureSet(macOS_GPUFamily2_v1)) {
		_metalFeatures.multisampleLayeredRendering = _metalFeatures.layeredRendering;
		_metalFeatures.stencilFeedback = true;
		_metalFeatures.depthResolve = true;
		_metalFeatures.stencilResolve = true;
		_metalFeatures.simdReduction = true;
	}

	if ( mvkOSVersionIsAtLeast(10.15) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_2;
		_metalFeatures.maxQueryBufferSize = (256 * KIBI);
		_metalFeatures.native3DCompressedTextures = true;
        _metalFeatures.renderWithoutAttachments = true;
        if ( mvkOSVersionIsAtLeast(mvkMakeOSVersion(10, 15, 6)) ) {
            _metalFeatures.sharedLinearTextures = true;
        }
		if (supportsMTLGPUFamily(Mac2)) {
			_metalFeatures.nativeTextureSwizzle = true;
			_metalFeatures.placementHeaps = useMTLHeaps;
		}
	}

#if MVK_MACOS_APPLE_SILICON
	if ( mvkOSVersionIsAtLeast(10.16) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_3;
		if (supportsMTLGPUFamily(Apple5)) {
			// This is an Apple GPU--treat it accordingly.
			_metalFeatures.mtlCopyBufferAlignment = 1;
			_metalFeatures.mtlBufferAlignment = 16;
			_metalFeatures.maxQueryBufferSize = (64 * KIBI);
			_metalFeatures.maxPerStageDynamicMTLBufferCount = _metalFeatures.maxPerStageBufferCount;
			_metalFeatures.postDepthCoverage = true;
			_metalFeatures.renderLinearTextures = true;
		}
		if (supportsMTLGPUFamily(Apple6)) {
			_metalFeatures.astcHDRTextures = true;
		}
		if (supportsMTLGPUFamily(Apple7)) {
			_metalFeatures.maxQueryBufferSize = (256 * KIBI);
		}
	}
#endif

#endif

    // Note the selector name, which is different from the property name.
    if ( [_mtlDevice respondsToSelector: @selector(areRasterOrderGroupsSupported)] ) {
        _metalFeatures.rasterOrderGroups = _mtlDevice.rasterOrderGroupsSupported;
    }
#if MVK_XCODE_12
	if ( [_mtlDevice respondsToSelector: @selector(supportsPullModelInterpolation)] ) {
		_metalFeatures.pullModelInterpolation = _mtlDevice.supportsPullModelInterpolation;
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

    _metalFeatures.minSubgroupSize = _metalFeatures.maxSubgroupSize = 1;
#if MVK_MACOS
    if (_metalFeatures.simdPermute) {
        // Based on data from Sascha Willems' Vulkan Hardware Database.
        // This would be a lot easier and less painful if MTLDevice had properties for this...
        _metalFeatures.maxSubgroupSize = (_properties.vendorID == kAMDVendorId) ? 64 : 32;
        switch (_properties.vendorID) {
            case kIntelVendorId:
                _metalFeatures.minSubgroupSize = 8;
                break;
            case kAMDVendorId:
                switch (_properties.deviceID) {
                    case kAMDRadeonRX5700XTDeviceId:
                    case kAMDRadeonRX5500XTDeviceId:
                        _metalFeatures.minSubgroupSize = 32;
                        break;
                    default:
                        _metalFeatures.minSubgroupSize = _metalFeatures.maxSubgroupSize;
                        break;
                }
                break;
            case kAppleVendorId:
                // XXX Minimum thread execution width for Apple GPUs is unknown, but assumed to be 4. May be greater.
                _metalFeatures.minSubgroupSize = 4;
                break;
            default:
                _metalFeatures.minSubgroupSize = _metalFeatures.maxSubgroupSize;
                break;
        }
    }
#endif
#if MVK_IOS
    if (_metalFeatures.simdPermute) {
        _metalFeatures.minSubgroupSize = 4;
        _metalFeatures.maxSubgroupSize = 32;
    } else if (_metalFeatures.quadPermute) {
        _metalFeatures.minSubgroupSize = _metalFeatures.maxSubgroupSize = 4;
    }
#endif

#define setMSLVersion(maj, min)	\
	_metalFeatures.mslVersion = SPIRV_CROSS_NAMESPACE::CompilerMSL::Options::make_msl_version(maj, min);

	switch (_metalFeatures.mslVersionEnum) {
#if MVK_XCODE_12
		case MTLLanguageVersion2_3:
			setMSLVersion(2, 3);
			break;
#endif
		case MTLLanguageVersion2_2:
			setMSLVersion(2, 2);
			break;
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
#if MVK_IOS_OR_TVOS
		case MTLLanguageVersion1_0:
			setMSLVersion(1, 0);
			break;
#endif
	}
}

// Initializes the physical device features of this instance.
void MVKPhysicalDevice::initFeatures() {
	mvkClear(&_features);	// Start with everything cleared

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
    _features.inheritedQueries = true;

	_features.shaderSampledImageArrayDynamicIndexing = _metalFeatures.arrayOfTextures;

    if (_metalFeatures.indirectDrawing && _metalFeatures.baseVertexInstanceDrawing) {
        _features.drawIndirectFirstInstance = true;
    }

#if MVK_TVOS
    _features.textureCompressionETC2 = true;
    _features.textureCompressionASTC_LDR = true;

	if (supportsMTLFeatureSet(tvOS_GPUFamily1_v3)) {
		_features.dualSrcBlend = true;
	}

    if (supportsMTLFeatureSet(tvOS_GPUFamily2_v1)) {
        _features.occlusionQueryPrecise = true;
    }

	if (supportsMTLFeatureSet(tvOS_GPUFamily2_v1)) {
		_features.tessellationShader = true;
	}
#endif

#if MVK_IOS
    _features.textureCompressionETC2 = true;

    if (supportsMTLFeatureSet(iOS_GPUFamily2_v1)) {
        _features.textureCompressionASTC_LDR = true;
    }

    if (supportsMTLFeatureSet(iOS_GPUFamily3_v1)) {
        _features.occlusionQueryPrecise = true;
    }

	if (supportsMTLFeatureSet(iOS_GPUFamily1_v4)) {
		_features.dualSrcBlend = true;
	}

	if (supportsMTLFeatureSet(iOS_GPUFamily2_v4)) {
		_features.depthClamp = true;
	}

	if (supportsMTLFeatureSet(iOS_GPUFamily3_v2)) {
		_features.tessellationShader = true;
		_features.shaderTessellationAndGeometryPointSize = true;
	}

	if (supportsMTLFeatureSet(iOS_GPUFamily4_v1)) {
		_features.imageCubeArray = true;
	}
  
	if (supportsMTLFeatureSet(iOS_GPUFamily5_v1)) {
		_features.multiViewport = true;
	}

	if (supportsMTLGPUFamily(Apple6)) {
        _features.shaderResourceMinLod = true;
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

    if (supportsMTLFeatureSet(macOS_GPUFamily1_v2)) {
        _features.tessellationShader = true;
        _features.dualSrcBlend = true;
        _features.shaderTessellationAndGeometryPointSize = true;
    }

    if (supportsMTLFeatureSet(macOS_GPUFamily1_v3)) {
        _features.multiViewport = true;
    }

    if ( mvkOSVersionIsAtLeast(10.15) ) {
        _features.shaderResourceMinLod = true;
    }

    if ( supportsMTLGPUFamily(Apple5) ) {
        _features.textureCompressionETC2 = true;
        _features.textureCompressionASTC_LDR = true;
    }

#if MVK_MACOS_APPLE_SILICON
	if ([_mtlDevice respondsToSelector: @selector(supportsBCTextureCompression)]) {
		_features.textureCompressionBC = _mtlDevice.supportsBCTextureCompression;
	}
#endif
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
//    VkBool32    shaderResourceMinLod;                         // done
//    VkBool32    sparseBinding;
//    VkBool32    sparseResidencyBuffer;
//    VkBool32    sparseResidencyImage2D;
//    VkBool32    sparseResidencyImage3D;
//    VkBool32    sparseResidency2Samples;
//    VkBool32    sparseResidency4Samples;
//    VkBool32    sparseResidency8Samples;
//    VkBool32    sparseResidency16Samples;
//    VkBool32    sparseResidencyAliased;
//    VkBool32    variableMultisampleRate;
//    VkBool32    inheritedQueries;                             // done
//} VkPhysicalDeviceFeatures;

// Initializes the physical device property limits.
void MVKPhysicalDevice::initLimits() {

#if MVK_TVOS
    _properties.limits.maxColorAttachments = kMVKCachedColorAttachmentCount;
#endif
#if MVK_IOS
    if (supportsMTLFeatureSet(iOS_GPUFamily2_v1)) {
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
	_properties.limits.maxFramebufferLayers = _metalFeatures.layeredRendering ? _metalFeatures.maxTextureLayers : 1;

    _properties.limits.maxViewportDimensions[0] = _metalFeatures.maxTextureDimension;
    _properties.limits.maxViewportDimensions[1] = _metalFeatures.maxTextureDimension;
    float maxVPDim = max(_properties.limits.maxViewportDimensions[0], _properties.limits.maxViewportDimensions[1]);
    _properties.limits.viewportBoundsRange[0] = (-2.0 * maxVPDim);
    _properties.limits.viewportBoundsRange[1] = (2.0 * maxVPDim) - 1;
    _properties.limits.maxViewports = _features.multiViewport ? kMVKCachedViewportScissorCount : 1;

	_properties.limits.maxImageDimension3D = _metalFeatures.maxTextureLayers;
	_properties.limits.maxImageArrayLayers = _metalFeatures.maxTextureLayers;
	_properties.limits.maxSamplerAnisotropy = 16;

    _properties.limits.maxVertexInputAttributes = 31;
    _properties.limits.maxVertexInputBindings = 31;

    _properties.limits.maxVertexInputBindingStride = (2 * KIBI);
	_properties.limits.maxVertexInputAttributeOffset = _properties.limits.maxVertexInputBindingStride - 1;

	_properties.limits.maxPerStageDescriptorSamplers = _metalFeatures.maxPerStageSamplerCount;
	_properties.limits.maxPerStageDescriptorUniformBuffers = _metalFeatures.maxPerStageBufferCount;
	_properties.limits.maxPerStageDescriptorStorageBuffers = _metalFeatures.maxPerStageBufferCount;
	_properties.limits.maxPerStageDescriptorSampledImages = _metalFeatures.maxPerStageTextureCount;
	_properties.limits.maxPerStageDescriptorStorageImages = _metalFeatures.maxPerStageStorageTextureCount;
	_properties.limits.maxPerStageDescriptorInputAttachments = _metalFeatures.maxPerStageTextureCount;

    _properties.limits.maxPerStageResources = (_metalFeatures.maxPerStageBufferCount + _metalFeatures.maxPerStageTextureCount);
    _properties.limits.maxFragmentCombinedOutputResources = _properties.limits.maxPerStageResources;

	_properties.limits.maxDescriptorSetSamplers = (_properties.limits.maxPerStageDescriptorSamplers * 5);
	_properties.limits.maxDescriptorSetUniformBuffers = (_properties.limits.maxPerStageDescriptorUniformBuffers * 5);
	_properties.limits.maxDescriptorSetUniformBuffersDynamic = (_properties.limits.maxPerStageDescriptorUniformBuffers * 5);
	_properties.limits.maxDescriptorSetStorageBuffers = (_properties.limits.maxPerStageDescriptorStorageBuffers * 5);
	_properties.limits.maxDescriptorSetStorageBuffersDynamic = (_properties.limits.maxPerStageDescriptorStorageBuffers * 5);
	_properties.limits.maxDescriptorSetSampledImages = (_properties.limits.maxPerStageDescriptorSampledImages * 5);
	_properties.limits.maxDescriptorSetStorageImages = (_properties.limits.maxPerStageDescriptorStorageImages * 5);
	_properties.limits.maxDescriptorSetInputAttachments = (_properties.limits.maxPerStageDescriptorInputAttachments * 5);

	// Whether handled as a real texture buffer or a 2D texture, this value is likely nowhere near the size of a buffer,
	// needs to fit in 32 bits, and some apps (I'm looking at you, CTS), assume it is low when doing 32-bit math.
	_properties.limits.maxTexelBufferElements = _properties.limits.maxImageDimension2D * (4 * KIBI);
#if MVK_MACOS
	_properties.limits.maxUniformBufferRange = (64 * KIBI);
	if (supportsMTLGPUFamily(Apple5)) {
		_properties.limits.maxUniformBufferRange = (uint32_t)_metalFeatures.maxMTLBufferSize;
	}
#endif
#if MVK_IOS_OR_TVOS
	_properties.limits.maxUniformBufferRange = (uint32_t)_metalFeatures.maxMTLBufferSize;
#endif
	_properties.limits.maxStorageBufferRange = (uint32_t)_metalFeatures.maxMTLBufferSize;
	_properties.limits.maxPushConstantsSize = (4 * KIBI);

    _properties.limits.minMemoryMapAlignment = _metalFeatures.mtlBufferAlignment;
    _properties.limits.minUniformBufferOffsetAlignment = _metalFeatures.mtlBufferAlignment;
    _properties.limits.minStorageBufferOffsetAlignment = 16;
    _properties.limits.bufferImageGranularity = _metalFeatures.mtlBufferAlignment;
    _properties.limits.nonCoherentAtomSize = _metalFeatures.mtlBufferAlignment;

    if ([_mtlDevice respondsToSelector: @selector(minimumLinearTextureAlignmentForPixelFormat:)]) {
        // Figure out the greatest alignment required by all supported formats, and whether
		// or not they only require alignment to a single texel. We'll use this information
		// to fill out the VkPhysicalDeviceTexelBufferAlignmentPropertiesEXT struct.
        uint32_t maxStorage = 0, maxUniform = 0;
        bool singleTexelStorage = true, singleTexelUniform = true;
        _pixelFormats.enumerateSupportedFormats({0, 0, VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT | VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT}, true, [&](VkFormat vk) {
			MTLPixelFormat mtlFmt = _pixelFormats.getMTLPixelFormat(vk);
			if ( !mtlFmt ) { return false; }	// If format is invalid, avoid validation errors on MTLDevice format alignment calls

            NSUInteger alignment;
            if ([_mtlDevice respondsToSelector: @selector(minimumTextureBufferAlignmentForPixelFormat:)]) {
                alignment = [_mtlDevice minimumTextureBufferAlignmentForPixelFormat: mtlFmt];
            } else {
                alignment = [_mtlDevice minimumLinearTextureAlignmentForPixelFormat: mtlFmt];
            }
            VkFormatProperties& props = _pixelFormats.getVkFormatProperties(vk);
            // For uncompressed formats, this is the size of a single texel.
            // Note that no implementations of Metal support compressed formats
            // in a linear texture (including texture buffers). It's likely that even
            // if they did, this would be the absolute minimum alignment.
            uint32_t texelSize = _pixelFormats.getBytesPerBlock(vk);
            // From the spec:
            //   "If the size of a single texel is a multiple of three bytes, then
            //    the size of a single component of the format is used instead."
            if (texelSize % 3 == 0) {
                switch (_pixelFormats.getFormatType(vk)) {
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
#if MVK_TVOS
        _properties.limits.minTexelBufferOffsetAlignment = 64;
#endif
#if MVK_IOS
        if (supportsMTLFeatureSet(iOS_GPUFamily3_v1)) {
            _properties.limits.minTexelBufferOffsetAlignment = 16;
        } else {
            _properties.limits.minTexelBufferOffsetAlignment = 64;
        }
#endif
#if MVK_MACOS
        _properties.limits.minTexelBufferOffsetAlignment = 256;
		if (supportsMTLGPUFamily(Apple5)) {
			_properties.limits.minTexelBufferOffsetAlignment = 16;
		}
#endif
        _texelBuffAlignProperties.storageTexelBufferOffsetAlignmentBytes = _properties.limits.minTexelBufferOffsetAlignment;
        _texelBuffAlignProperties.storageTexelBufferOffsetSingleTexelAlignment = VK_FALSE;
        _texelBuffAlignProperties.uniformTexelBufferOffsetAlignmentBytes = _properties.limits.minTexelBufferOffsetAlignment;
        _texelBuffAlignProperties.uniformTexelBufferOffsetSingleTexelAlignment = VK_FALSE;
    }

#if MVK_TVOS
    if (mvkOSVersionIsAtLeast(13.0) && supportsMTLGPUFamily(Apple4)) {
        _properties.limits.maxFragmentInputComponents = 124;
    } else {
        _properties.limits.maxFragmentInputComponents = 60;
    }

    if (supportsMTLFeatureSet(tvOS_GPUFamily2_v1)) {
        _properties.limits.optimalBufferCopyOffsetAlignment = 16;
    } else {
        _properties.limits.optimalBufferCopyOffsetAlignment = 64;
    }

    _properties.limits.maxTessellationGenerationLevel = 16;
    _properties.limits.maxTessellationPatchSize = 32;
#endif
#if MVK_IOS
    if (mvkOSVersionIsAtLeast(13.0) && supportsMTLGPUFamily(Apple4)) {
        _properties.limits.maxFragmentInputComponents = 124;
    } else {
        _properties.limits.maxFragmentInputComponents = 60;
    }

    if (supportsMTLFeatureSet(iOS_GPUFamily3_v1)) {
        _properties.limits.optimalBufferCopyOffsetAlignment = 16;
    } else {
        _properties.limits.optimalBufferCopyOffsetAlignment = 64;
    }

    if (supportsMTLFeatureSet(iOS_GPUFamily5_v1)) {
        _properties.limits.maxTessellationGenerationLevel = 64;
        _properties.limits.maxTessellationPatchSize = 32;
    } else if (supportsMTLFeatureSet(iOS_GPUFamily3_v2)) {
        _properties.limits.maxTessellationGenerationLevel = 16;
        _properties.limits.maxTessellationPatchSize = 32;
    } else {
        _properties.limits.maxTessellationGenerationLevel = 0;
        _properties.limits.maxTessellationPatchSize = 0;
    }
#endif
#if MVK_MACOS
    _properties.limits.maxFragmentInputComponents = 124;
    _properties.limits.optimalBufferCopyOffsetAlignment = 256;
	if (supportsMTLGPUFamily(Apple5)) {
		_properties.limits.optimalBufferCopyOffsetAlignment = 16;
	}

    if (supportsMTLFeatureSet(macOS_GPUFamily1_v2)) {
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
        _properties.limits.maxTessellationControlPerPatchOutputComponents = std::max(_properties.limits.maxFragmentInputComponents - 8, 120u);
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
    _properties.limits.pointSizeRange[1] = 64;
    _properties.limits.pointSizeGranularity = 1;
    _properties.limits.lineWidthRange[0] = 1;
    _properties.limits.lineWidthRange[1] = 1;
    _properties.limits.lineWidthGranularity = 1;

    _properties.limits.standardSampleLocations = VK_TRUE;
    _properties.limits.strictLines = _properties.vendorID == kIntelVendorId || _properties.vendorID == kNVVendorId;

	VkExtent3D wgSize = mvkVkExtent3DFromMTLSize(_mtlDevice.maxThreadsPerThreadgroup);
	_properties.limits.maxComputeWorkGroupSize[0] = wgSize.width;
	_properties.limits.maxComputeWorkGroupSize[1] = wgSize.height;
	_properties.limits.maxComputeWorkGroupSize[2] = wgSize.depth;
	_properties.limits.maxComputeWorkGroupInvocations = max({wgSize.width, wgSize.height, wgSize.depth});

	if ( [_mtlDevice respondsToSelector: @selector(maxThreadgroupMemoryLength)] ) {
		_properties.limits.maxComputeSharedMemorySize = (uint32_t)_mtlDevice.maxThreadgroupMemoryLength;
	} else {
#if MVK_TVOS
		if (supportsMTLFeatureSet(tvOS_GPUFamily2_v1)) {
			_properties.limits.maxComputeSharedMemorySize = (16 * KIBI);
		} else {
			_properties.limits.maxComputeSharedMemorySize = ((16 * KIBI) - 32);
		}
#endif
#if MVK_IOS
		if (supportsMTLFeatureSet(iOS_GPUFamily4_v1)) {
			_properties.limits.maxComputeSharedMemorySize = (32 * KIBI);
		} else if (supportsMTLFeatureSet(iOS_GPUFamily3_v1)) {
			_properties.limits.maxComputeSharedMemorySize = (16 * KIBI);
		} else {
			_properties.limits.maxComputeSharedMemorySize = ((16 * KIBI) - 32);
		}
#endif
#if MVK_MACOS
		_properties.limits.maxComputeSharedMemorySize = (32 * KIBI);
#endif
	}
	_properties.limits.maxSamplerLodBias = 0;	// Bias not supported in API, but can be applied in shader directly.

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

    _properties.limits.maxDrawIndexedIndexValue = numeric_limits<uint32_t>::max();	// Must be (2^32 - 1) to support fullDrawIndexUint32
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

void MVKPhysicalDevice::initGPUInfoProperties() {

	bool isFound = false;

	bool isIntegrated = _mtlDevice.isLowPower;
	_properties.deviceType = isIntegrated ? VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU : VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU;
	strlcpy(_properties.deviceName, _mtlDevice.name.UTF8String, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE);

	if (supportsMTLGPUFamily(Apple5)) {
		// This is an Apple GPU. It won't have a 'device-id' property, so fill it in
		// like on iOS/tvOS.
		_properties.vendorID = kAppleVendorId;
#if MVK_MACOS_APPLE_SILICON
		if (supportsMTLGPUFamily(Apple7)) {
			_properties.deviceID = 0xa140;
		} else if (supportsMTLGPUFamily(Apple6)) {
			_properties.deviceID = 0xa130;
		} else {
			_properties.deviceID = 0xa120;
		}
#else
		_properties.deviceID = 0xa120;
#endif
		return;
	}

	// If the device has an associated registry ID, we can use that to get the associated IOKit node.
	// The match dictionary is consumed by IOServiceGetMatchingServices and does not need to be released.
	io_registry_entry_t entry;
	uint64_t regID = mvkGetRegistryID(_mtlDevice);
	if (regID) {
		entry = IOServiceGetMatchingService(kIOMasterPortDefault, IORegistryEntryIDMatching(regID));
		if (entry) {
			// That returned the IOGraphicsAccelerator nub. Its parent, then, is the actual PCI device.
			io_registry_entry_t parent;
			if (IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == kIOReturnSuccess) {
				isFound = true;
				_properties.vendorID = mvkGetEntryProperty(parent, CFSTR("vendor-id"));
				_properties.deviceID = mvkGetEntryProperty(parent, CFSTR("device-id"));
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
					_properties.vendorID = vendorID;
					_properties.deviceID = mvkGetEntryProperty(entry, CFSTR("device-id"));
				}
			}
		}
		IOObjectRelease(entryIterator);
	}
}

#endif	//MVK_MACOS

#if MVK_IOS

// For iOS devices, the Device ID is the SoC model (A8, A10X...), in the hex form 0xaMMX, where
//"a" is the Apple brand, MM is the SoC model number (8, 10...) and X is 1 for X version, 0 for other.
void MVKPhysicalDevice::initGPUInfoProperties() {
	NSUInteger coreCnt = NSProcessInfo.processInfo.processorCount;
	uint32_t devID = 0xa070;
#if MVK_XCODE_12
	if (supportsMTLGPUFamily(Apple7)) {
		devID = 0xa140;
	} else
#endif
	if (supportsMTLGPUFamily(Apple6)) {
		devID = 0xa130;
	} else if (supportsMTLFeatureSet(iOS_GPUFamily5_v1)) {
		devID = 0xa120;
	} else if (supportsMTLFeatureSet(iOS_GPUFamily4_v1)) {
		devID = 0xa110;
	} else if (supportsMTLFeatureSet(iOS_GPUFamily3_v1)) {
		devID = coreCnt > 2 ? 0xa101 : 0xa100;
	} else if (supportsMTLFeatureSet(iOS_GPUFamily2_v1)) {
		devID = coreCnt > 2 ? 0xa081 : 0xa080;
	}

	_properties.vendorID = kAppleVendorId;
	_properties.deviceID = devID;
	_properties.deviceType = VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
	strlcpy(_properties.deviceName, _mtlDevice.name.UTF8String, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE);
}
#endif	//MVK_IOS

#if MVK_TVOS

// For tvOS devices, the Device ID is the SoC model (A8, A10X...), in the hex form 0xaMMX, where
//"a" is the Apple brand, MM is the SoC model number (8, 10...) and X is 1 for X version, 0 for other.
void MVKPhysicalDevice::initGPUInfoProperties() {
	uint32_t devID = 0xa080;
	if (supportsMTLFeatureSet(tvOS_GPUFamily2_v1)) {
		devID = 0xa101;
	}

  _properties.vendorID = kAppleVendorId;
  _properties.deviceID = devID;
  _properties.deviceType = VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
  strlcpy(_properties.deviceName, _mtlDevice.name.UTF8String, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE);
}
#endif

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
	mvkClear(&_properties.pipelineCacheUUID);

	size_t uuidComponentOffset = 0;

	// First 8 bytes contain the first part of the MoltenVK Git revision
	uint64_t mvkRev = getMoltenVKGitRevision();
	*(uint64_t*)&_properties.pipelineCacheUUID[uuidComponentOffset] = NSSwapHostLongLongToBig(mvkRev);
	uuidComponentOffset += sizeof(mvkRev);

	// Next 4 bytes contains highest Metal feature set supported by this device
	uint32_t mtlFeatSet = getHighestMTLFeatureSet();
	*(uint32_t*)&_properties.pipelineCacheUUID[uuidComponentOffset] = NSSwapHostIntToBig(mtlFeatSet);
	uuidComponentOffset += sizeof(mtlFeatSet);

	// Last 4 bytes contains flags based on enabled Metal features that
	// might affect the contents of the pipeline cache (mostly MSL content).
	uint32_t mtlFeatures = 0;
	mtlFeatures |= ((bool)_metalFeatures.argumentBuffers) << 0;
	*(uint32_t*)&_properties.pipelineCacheUUID[uuidComponentOffset] = NSSwapHostIntToBig(mtlFeatures);
	uuidComponentOffset += sizeof(mtlFeatures);
}

uint32_t MVKPhysicalDevice::getHighestMTLFeatureSet() {

	// On newer OS's, combine highest Metal version with highest GPU family
	// (Mac & Apple GPU lists should be mutex on platform)
	uint32_t mtlVer = 0;
#if MVK_IOS_OR_TVOS
	if (mvkOSVersionIsAtLeast(13.0)) { mtlVer = 0x30000; }
	if (mvkOSVersionIsAtLeast(14.0)) { mtlVer = 0x40000; }
#endif
#if MVK_MACOS
	if (mvkOSVersionIsAtLeast(10.15)) { mtlVer = 0x30000; }
	if (mvkOSVersionIsAtLeast(10.16)) { mtlVer = 0x40000; }
#endif

	MTLGPUFamily mtlFam = MTLGPUFamily(0);
	if (supportsMTLGPUFamily(Mac1)) { mtlFam = MTLGPUFamilyMac1; }
	if (supportsMTLGPUFamily(Mac2)) { mtlFam = MTLGPUFamilyMac2; }

	if (supportsMTLGPUFamily(Apple1)) { mtlFam = MTLGPUFamilyApple1; }
	if (supportsMTLGPUFamily(Apple2)) { mtlFam = MTLGPUFamilyApple2; }
	if (supportsMTLGPUFamily(Apple3)) { mtlFam = MTLGPUFamilyApple3; }
	if (supportsMTLGPUFamily(Apple4)) { mtlFam = MTLGPUFamilyApple4; }
	if (supportsMTLGPUFamily(Apple5)) { mtlFam = MTLGPUFamilyApple5; }
#if MVK_IOS || MVK_MACOS_APPLE_SILICON
	if (supportsMTLGPUFamily(Apple6)) { mtlFam = MTLGPUFamilyApple6; }
	if (supportsMTLGPUFamily(Apple7)) { mtlFam = MTLGPUFamilyApple7; }
#endif

	// Not explicitly guaranteed to be unique...but close enough without spilling over
	uint32_t mtlFS = (mtlVer << 8) + (uint32_t)mtlFam;
	if (mtlFS) { return mtlFS; }

	// Fall back to legacy feature sets on older OS's
#if MVK_IOS
	uint32_t maxFS = (uint32_t)MTLFeatureSet_iOS_GPUFamily5_v1;
	uint32_t minFS = (uint32_t)MTLFeatureSet_iOS_GPUFamily1_v1;
#endif

#if MVK_TVOS
  uint32_t maxFS = (uint32_t)MTLFeatureSet_tvOS_GPUFamily2_v2;
  uint32_t minFS = (uint32_t)MTLFeatureSet_tvOS_GPUFamily1_v1;
#endif

#if MVK_MACOS
	uint32_t maxFS = (uint32_t)MTLFeatureSet_macOS_GPUFamily2_v1;
	uint32_t minFS = (uint32_t)MTLFeatureSet_macOS_GPUFamily1_v1;
#endif

	for (uint32_t fs = maxFS; fs > minFS; fs--) {
		if ( [_mtlDevice supportsFeatureSet: (MTLFeatureSet)fs] ) { return fs; }
	}
	return minFS;
}

// Retrieve the SPIRV-Cross Git revision hash from a derived header file,
// which is generated in advance, either statically, or more typically in
// an early build phase script, and contains a line similar to the following:
// static const char* mvkRevString = "fc0750d67cfe825b887dd2cf25a42e9d9a013eb2";
uint64_t MVKPhysicalDevice::getMoltenVKGitRevision() {

#include "mvkGitRevDerived.h"

	static const string revStr(mvkRevString, 0, 16);	// We just need the first 16 chars
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

void MVKPhysicalDevice::setMemoryHeap(uint32_t heapIndex, VkDeviceSize heapSize, VkMemoryHeapFlags heapFlags) {
	_memoryProperties.memoryHeaps[heapIndex].size = heapSize;
	_memoryProperties.memoryHeaps[heapIndex].flags = heapFlags;
}

void MVKPhysicalDevice::setMemoryType(uint32_t typeIndex, uint32_t heapIndex, VkMemoryPropertyFlags propertyFlags) {
	_memoryProperties.memoryTypes[typeIndex].heapIndex = heapIndex;
	_memoryProperties.memoryTypes[typeIndex].propertyFlags = propertyFlags;
}

// Initializes the memory properties of this instance.
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
void MVKPhysicalDevice::initMemoryProperties() {

	mvkClear(&_memoryProperties);	// Start with everything cleared

	// Main heap
	uint32_t mainHeapIdx = 0;
	setMemoryHeap(mainHeapIdx, getVRAMSize(), VK_MEMORY_HEAP_DEVICE_LOCAL_BIT);

	// Optional second heap for shared memory
	uint32_t sharedHeapIdx;
	VkMemoryPropertyFlags sharedTypePropFlags;
	if (getHasUnifiedMemory()) {
		// Shared memory goes in the single main heap in unified memory, and per Vulkan spec must be marked local
		sharedHeapIdx = mainHeapIdx;
		sharedTypePropFlags = MVK_VK_MEMORY_TYPE_METAL_SHARED | VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
	} else {
		// Define a second heap to mark the shared memory as non-local
		sharedHeapIdx = mainHeapIdx + 1;
		setMemoryHeap(sharedHeapIdx, mvkGetSystemMemorySize(), 0);
		sharedTypePropFlags = MVK_VK_MEMORY_TYPE_METAL_SHARED;
	}

	_memoryProperties.memoryHeapCount = sharedHeapIdx + 1;

	// Memory types
	uint32_t typeIdx = 0;

	// Private storage
	uint32_t privateBit = 1 << typeIdx;
	setMemoryType(typeIdx, mainHeapIdx, MVK_VK_MEMORY_TYPE_METAL_PRIVATE);
	typeIdx++;

	// Shared storage
	uint32_t sharedBit = 1 << typeIdx;
	setMemoryType(typeIdx, sharedHeapIdx, sharedTypePropFlags);
	typeIdx++;

	// Managed storage
	uint32_t managedBit = 0;
#if MVK_MACOS
	managedBit = 1 << typeIdx;
	setMemoryType(typeIdx, mainHeapIdx, MVK_VK_MEMORY_TYPE_METAL_MANAGED);
	typeIdx++;
#endif

	// Memoryless storage
	uint32_t memlessBit = 0;
#if MVK_MACOS_APPLE_SILICON
	if (supportsMTLGPUFamily(Apple5)) {
		memlessBit = 1 << typeIdx;
		setMemoryType(typeIdx, mainHeapIdx, MVK_VK_MEMORY_TYPE_METAL_MEMORYLESS);
		typeIdx++;
	}
#endif
#if MVK_IOS
	if (supportsMTLFeatureSet(iOS_GPUFamily1_v3)) {
		memlessBit = 1 << typeIdx;
		setMemoryType(typeIdx, mainHeapIdx, MVK_VK_MEMORY_TYPE_METAL_MEMORYLESS);
		typeIdx++;
	}
#endif
#if MVK_TVOS
	if (supportsMTLFeatureSet(tvOS_GPUFamily1_v2)) {
		memlessBit = 1 << typeIdx;
		setMemoryType(typeIdx, mainHeapIdx, MVK_VK_MEMORY_TYPE_METAL_MEMORYLESS);
		typeIdx++;
	}
#endif

	_memoryProperties.memoryTypeCount = typeIdx;

	_privateMemoryTypes			= privateBit | memlessBit;
	_hostVisibleMemoryTypes		= sharedBit | managedBit;
	_hostCoherentMemoryTypes 	= sharedBit;
	_lazilyAllocatedMemoryTypes	= memlessBit;
	_allMemoryTypes				= privateBit | sharedBit | managedBit | memlessBit;
}

bool MVKPhysicalDevice::getHasUnifiedMemory() {
#if MVK_IOS_OR_TVOS
	return true;
#endif
#if MVK_MACOS
	return ([_mtlDevice respondsToSelector: @selector(hasUnifiedMemory)]
			? _mtlDevice.hasUnifiedMemory : _mtlDevice.isLowPower);
#endif
}

uint64_t MVKPhysicalDevice::getVRAMSize() {
	if (getHasUnifiedMemory()) {
		return mvkGetSystemMemorySize();
	} else {
		// There's actually no way to query the total physical VRAM on the device in Metal.
		// Just default to using the recommended max working set size (i.e. the budget).
		return getRecommendedMaxWorkingSetSize();
	}
}

uint64_t MVKPhysicalDevice::getRecommendedMaxWorkingSetSize() {
#if MVK_MACOS
	if ( [_mtlDevice respondsToSelector: @selector(recommendedMaxWorkingSetSize)]) {
		return _mtlDevice.recommendedMaxWorkingSetSize;
	}
#endif
#if MVK_IOS_OR_TVOS
	// GPU and CPU use shared memory. Estimate the current free memory in the system.
	uint64_t freeMem = mvkGetAvailableMemorySize();
	if (freeMem) { return freeMem; }
#endif

	return 128 * MEBI;		// Conservative minimum for macOS GPU's & iOS shared memory
}

uint64_t MVKPhysicalDevice::getCurrentAllocatedSize() {
	if ( [_mtlDevice respondsToSelector: @selector(currentAllocatedSize)] ) {
		return _mtlDevice.currentAllocatedSize;
	}
#if MVK_IOS_OR_TVOS
	// We can use the current memory used by this process as a reasonable approximation.
	return mvkGetUsedMemorySize();
#endif
#if MVK_MACOS
	return 0;
#endif
}

void MVKPhysicalDevice::initExternalMemoryProperties() {

	// Buffers
	_mtlBufferExternalMemoryProperties.externalMemoryFeatures = (VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT |
																 VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT);
	_mtlBufferExternalMemoryProperties.exportFromImportedHandleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_KHR;
	_mtlBufferExternalMemoryProperties.compatibleHandleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_KHR;

	// Images
	_mtlTextureExternalMemoryProperties.externalMemoryFeatures = (VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT |
																  VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT |
																  VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT);
	_mtlTextureExternalMemoryProperties.exportFromImportedHandleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR;
	_mtlTextureExternalMemoryProperties.compatibleHandleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR;
}

void MVKPhysicalDevice::initExtensions() {
	MVKExtensionList* pWritableExtns = (MVKExtensionList*)&_supportedExtensions;
	pWritableExtns->disableAllButEnabledDeviceExtensions();

#if MVK_IOS_OR_TVOS
	if (!_metalFeatures.depthResolve) {
		pWritableExtns->vk_KHR_depth_stencil_resolve.enabled = false;
	}
#endif
	if (!_metalFeatures.samplerMirrorClampToEdge) {
		pWritableExtns->vk_KHR_sampler_mirror_clamp_to_edge.enabled = false;
	}
	if (!_metalFeatures.rasterOrderGroups) {
		pWritableExtns->vk_EXT_fragment_shader_interlock.enabled = false;
	}
	if (!_metalFeatures.postDepthCoverage) {
		pWritableExtns->vk_EXT_post_depth_coverage.enabled = false;
	}
	if (!_metalFeatures.stencilFeedback) {
		pWritableExtns->vk_EXT_shader_stencil_export.enabled = false;
	}
	if (!_metalFeatures.astcHDRTextures) {
		pWritableExtns->vk_EXT_texture_compression_astc_hdr.enabled = false;
	}
	if (!_metalFeatures.simdPermute && !_metalFeatures.quadPermute) {
		pWritableExtns->vk_KHR_shader_subgroup_extended_types.enabled = false;
	}
#if MVK_MACOS
	if (!supportsMTLGPUFamily(Apple5)) {
		pWritableExtns->vk_AMD_shader_image_load_store_lod.enabled = false;
		pWritableExtns->vk_IMG_format_pvrtc.enabled = false;
	}
#endif
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
	logMsg += "\n\tsupports the following Metal Versions, GPU's and Feature Sets:";
	logMsg += "\n\t\tMetal Shading Language %s";

#if MVK_IOS || MVK_MACOS_APPLE_SILICON
	if (supportsMTLGPUFamily(Apple7)) { logMsg += "\n\t\tGPU Family Apple 7"; }
	if (supportsMTLGPUFamily(Apple6)) { logMsg += "\n\t\tGPU Family Apple 6"; }
#endif
	if (supportsMTLGPUFamily(Apple5)) { logMsg += "\n\t\tGPU Family Apple 5"; }
	if (supportsMTLGPUFamily(Apple4)) { logMsg += "\n\t\tGPU Family Apple 4"; }
	if (supportsMTLGPUFamily(Apple3)) { logMsg += "\n\t\tGPU Family Apple 3"; }
	if (supportsMTLGPUFamily(Apple2)) { logMsg += "\n\t\tGPU Family Apple 2"; }
	if (supportsMTLGPUFamily(Apple1)) { logMsg += "\n\t\tGPU Family Apple 1"; }

	if (supportsMTLGPUFamily(Mac2)) { logMsg += "\n\t\tGPU Family Mac 2"; }
	if (supportsMTLGPUFamily(Mac1)) { logMsg += "\n\t\tGPU Family Mac 1"; }

	if (supportsMTLGPUFamily(Common3)) { logMsg += "\n\t\tGPU Family Common 3"; }
	if (supportsMTLGPUFamily(Common2)) { logMsg += "\n\t\tGPU Family Common 2"; }
	if (supportsMTLGPUFamily(Common1)) { logMsg += "\n\t\tGPU Family Common 1"; }

	if (supportsMTLGPUFamily(MacCatalyst2)) { logMsg += "\n\t\tGPU Family Mac Catalyst 2"; }
	if (supportsMTLGPUFamily(MacCatalyst1)) { logMsg += "\n\t\tGPU Family Mac Catalyst 1"; }

#if MVK_IOS
	if (supportsMTLFeatureSet(iOS_GPUFamily5_v1)) { logMsg += "\n\t\tiOS GPU Family 5 v1"; }

	if (supportsMTLFeatureSet(iOS_GPUFamily4_v2)) { logMsg += "\n\t\tiOS GPU Family 4 v2"; }
	if (supportsMTLFeatureSet(iOS_GPUFamily4_v1)) { logMsg += "\n\t\tiOS GPU Family 4 v1"; }

	if (supportsMTLFeatureSet(iOS_GPUFamily3_v4)) { logMsg += "\n\t\tiOS GPU Family 3 v4"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily3_v3)) { logMsg += "\n\t\tiOS GPU Family 3 v3"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily3_v2)) { logMsg += "\n\t\tiOS GPU Family 3 v2"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily3_v1)) { logMsg += "\n\t\tiOS GPU Family 3 v1"; }

	if (supportsMTLFeatureSet(iOS_GPUFamily2_v5)) { logMsg += "\n\t\tiOS GPU Family 2 v5"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily2_v4)) { logMsg += "\n\t\tiOS GPU Family 2 v4"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily2_v3)) { logMsg += "\n\t\tiOS GPU Family 2 v3"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily2_v2)) { logMsg += "\n\t\tiOS GPU Family 2 v2"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily2_v1)) { logMsg += "\n\t\tiOS GPU Family 2 v1"; }

	if (supportsMTLFeatureSet(iOS_GPUFamily1_v5)) { logMsg += "\n\t\tiOS GPU Family 1 v5"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily1_v4)) { logMsg += "\n\t\tiOS GPU Family 1 v4"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily1_v3)) { logMsg += "\n\t\tiOS GPU Family 1 v3"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily1_v2)) { logMsg += "\n\t\tiOS GPU Family 1 v2"; }
    if (supportsMTLFeatureSet(iOS_GPUFamily1_v1)) { logMsg += "\n\t\tiOS GPU Family 1 v1"; }
#endif

#if MVK_TVOS
    if (supportsMTLFeatureSet(tvOS_GPUFamily2_v2)) { logMsg += "\n\t\ttvOS GPU Family 2 v2"; }
    if (supportsMTLFeatureSet(tvOS_GPUFamily2_v1)) { logMsg += "\n\t\ttvOS GPU Family 2 v1"; }

    if (supportsMTLFeatureSet(tvOS_GPUFamily1_v4)) { logMsg += "\n\t\ttvOS GPU Family 1 v4"; }
    if (supportsMTLFeatureSet(tvOS_GPUFamily1_v3)) { logMsg += "\n\t\ttvOS GPU Family 1 v3"; }
    if (supportsMTLFeatureSet(tvOS_GPUFamily1_v2)) { logMsg += "\n\t\ttvOS GPU Family 1 v2"; }
    if (supportsMTLFeatureSet(tvOS_GPUFamily1_v1)) { logMsg += "\n\t\ttvOS GPU Family 1 v1"; }
#endif

#if MVK_MACOS
	if (supportsMTLFeatureSet(macOS_GPUFamily2_v1)) { logMsg += "\n\t\tmacOS GPU Family 2 v1"; }

	if (supportsMTLFeatureSet(macOS_GPUFamily1_v4)) { logMsg += "\n\t\tmacOS GPU Family 1 v4"; }
    if (supportsMTLFeatureSet(macOS_GPUFamily1_v3)) { logMsg += "\n\t\tmacOS GPU Family 1 v3"; }
    if (supportsMTLFeatureSet(macOS_GPUFamily1_v2)) { logMsg += "\n\t\tmacOS GPU Family 1 v2"; }
    if (supportsMTLFeatureSet(macOS_GPUFamily1_v1)) { logMsg += "\n\t\tmacOS GPU Family 1 v1"; }

#if !MVK_MACCAT
	if (supportsMTLFeatureSet(macOS_ReadWriteTextureTier2)) { logMsg += "\n\t\tmacOS Read-Write Texture Tier 2"; }
#endif
#endif

#if MVK_MACCAT
	if ([_mtlDevice respondsToSelector: @selector(readWriteTextureSupport)] &&
		_mtlDevice.readWriteTextureSupport == MTLReadWriteTextureTier2) {
		logMsg += "\n\t\tmacOS Read-Write Texture Tier 2";
	}
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
	uint32_t apiVersion = _physicalDevice->_mvkInstance->_appInfo.apiVersion;

	bool isSupported = (pMVKPA &&											// Command exists and...
						pMVKPA->isDevice &&									// ...is a device command and...
						pMVKPA->isEnabled(apiVersion, _enabledExtensions));	// ...is a core or enabled extension command.

	return isSupported ? pMVKPA->functionPointer : nullptr;
}

MVKQueue* MVKDevice::getQueue(uint32_t queueFamilyIndex, uint32_t queueIndex) {
	return _queuesByQueueFamilyIndex[queueFamilyIndex][queueIndex];
}

MVKQueue* MVKDevice::getQueue(const VkDeviceQueueInfo2* queueInfo) {
	return _queuesByQueueFamilyIndex[queueInfo->queueFamilyIndex][queueInfo->queueIndex];
}

MVKQueue* MVKDevice::getAnyQueue() {
	for (auto& queues : _queuesByQueueFamilyIndex) {
		for (MVKQueue* q : queues) {
			if (q) { return q; };
		}
	}
	return nullptr;
}

VkResult MVKDevice::waitIdle() {
	VkResult rslt = VK_SUCCESS;
	for (auto& queues : _queuesByQueueFamilyIndex) {
		for (MVKQueue* q : queues) {
			if ((rslt = q->waitIdle()) != VK_SUCCESS) { return rslt; }
		}
	}
	return VK_SUCCESS;
}

VkResult MVKDevice::markLost() {
	lock_guard<mutex> lock(_sem4Lock);
	setConfigurationResult(VK_ERROR_DEVICE_LOST);
	for (auto* sem4 : _awaitingSemaphores) {
		sem4->release();
	}
	for (auto& sem4AndValue : _awaitingTimelineSem4s) {
		VkSemaphoreSignalInfo signalInfo;
		signalInfo.value = sem4AndValue.second;
		sem4AndValue.first->signal(&signalInfo);
	}
	_awaitingSemaphores.clear();
	_awaitingTimelineSem4s.clear();
	return VK_ERROR_DEVICE_LOST;
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

	// Check whether the layout has a variable-count descriptor, and if so, whether we can support it.
	for (auto* next = (VkBaseOutStructure*)pSupport->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_LAYOUT_SUPPORT_EXT: {
				auto* pVarDescSetCountSupport = (VkDescriptorSetVariableDescriptorCountLayoutSupportEXT*)next;
				getDescriptorVariableDescriptorCountLayoutSupport(pCreateInfo, pSupport, pVarDescSetCountSupport);
				break;
			}
			default:
				break;
		}
	}
}

// Check whether the layout has a variable-count descriptor, and if so, whether we can support it.
void MVKDevice::getDescriptorVariableDescriptorCountLayoutSupport(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
																  VkDescriptorSetLayoutSupport* pSupport,
																  VkDescriptorSetVariableDescriptorCountLayoutSupportEXT* pVarDescSetCountSupport) {
	// Assume we don't need this, then set appropriately if we do.
	pVarDescSetCountSupport->maxVariableDescriptorCount = 0;

	// Look for a variable length descriptor and remember its index.
	int32_t varBindingIdx = -1;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO_EXT: {
				auto* pDescSetLayoutBindingFlags = (VkDescriptorSetLayoutBindingFlagsCreateInfoEXT*)next;
				for (uint32_t bindIdx = 0; bindIdx < pDescSetLayoutBindingFlags->bindingCount; bindIdx++) {
					if (mvkIsAnyFlagEnabled(pDescSetLayoutBindingFlags->pBindingFlags[bindIdx], VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT)) {
						varBindingIdx = bindIdx;
						break;
					}
				}
				break;
			}
			default:
				break;
		}
	}

	// If no variable length descriptor is found, we can skip the rest.
	if (varBindingIdx < 0) { return; }

	// Device does not support variable descriptor counts but it has been requested.
	if ( !_enabledDescriptorIndexingFeatures.descriptorBindingVariableDescriptorCount ) {
		pSupport->supported = false;
		return;
	}

	uint32_t mtlBuffCnt = 0;
	uint32_t mtlTexCnt = 0;
	uint32_t mtlSampCnt = 0;
	uint32_t requestedCount = 0;
	uint32_t maxVarDescCount = 0;

	// Determine the number of descriptors available for use by the variable descriptor by
	// accumulating the number of resources accumulated by other descriptors and subtracting
	// that from the device's per-stage max counts. This is not perfect because it does not
	// take into consideration other descriptor sets in the pipeline layout, but we can't
	// anticipate that here. The variable descriptor must have the highest binding number,
	// but it may not be the last descriptor in the array. The handling here accommodates that.
	for (uint32_t bindIdx = 0; bindIdx < pCreateInfo->bindingCount; bindIdx++) {
		auto* pBind = &pCreateInfo->pBindings[bindIdx];
		if (bindIdx == varBindingIdx) {
			requestedCount = std::max(pBind->descriptorCount, 1u);
		} else {
			switch (pBind->descriptorType) {
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
					mtlBuffCnt += pBind->descriptorCount;
					maxVarDescCount = _pMetalFeatures->maxPerStageBufferCount - mtlBuffCnt;
					break;
				case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
					maxVarDescCount = (uint32_t)min<VkDeviceSize>(_pMetalFeatures->maxMTLBufferSize, numeric_limits<uint32_t>::max());
					break;
				case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
				case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
				case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
					mtlTexCnt += pBind->descriptorCount;
					maxVarDescCount = _pMetalFeatures->maxPerStageTextureCount - mtlTexCnt;
					break;
				case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
				case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
					mtlTexCnt += pBind->descriptorCount;
					mtlBuffCnt += pBind->descriptorCount;
					maxVarDescCount = min(_pMetalFeatures->maxPerStageTextureCount - mtlTexCnt,
										  _pMetalFeatures->maxPerStageBufferCount - mtlBuffCnt);
					break;
				case VK_DESCRIPTOR_TYPE_SAMPLER:
					mtlSampCnt += pBind->descriptorCount;
					maxVarDescCount = _pMetalFeatures->maxPerStageSamplerCount - mtlSampCnt;
					break;
				case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
					mtlTexCnt += pBind->descriptorCount;
					mtlSampCnt += pBind->descriptorCount;
					maxVarDescCount = min(_pMetalFeatures->maxPerStageTextureCount - mtlTexCnt,
										  _pMetalFeatures->maxPerStageSamplerCount - mtlSampCnt);
					break;
				default:
					break;
			}
		}
	}

	// If there is enough room for the requested size, indicate the amount available,
	// otherwise indicate that the requested size cannot be supported.
	if (requestedCount < maxVarDescCount) {
		pVarDescSetCountSupport->maxVariableDescriptorCount = maxVarDescCount;
	} else {
		pSupport->supported = false;
	}
}

VkResult MVKDevice::getDeviceGroupPresentCapabilities(VkDeviceGroupPresentCapabilitiesKHR* pDeviceGroupPresentCapabilities) {
	mvkClear(&pDeviceGroupPresentCapabilities->presentMask);
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
#if MVK_IOS_OR_TVOS || MVK_MACOS_APPLE_SILICON
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
	if (mvkBuff) {
		removeResource(mvkBuff);
		mvkBuff->destroy();
	}
}

MVKBufferView* MVKDevice::createBufferView(const VkBufferViewCreateInfo* pCreateInfo,
                                           const VkAllocationCallbacks* pAllocator) {
    return new MVKBufferView(this, pCreateInfo);
}

void MVKDevice::destroyBufferView(MVKBufferView* mvkBuffView,
                                  const VkAllocationCallbacks* pAllocator) {
	if (mvkBuffView) { mvkBuffView->destroy(); }
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
    MVKImage* mvkImg = (swapchainInfo)
        ? new MVKPeerSwapchainImage(this, pCreateInfo, (MVKSwapchain*)swapchainInfo->swapchain, uint32_t(-1))
        : new MVKImage(this, pCreateInfo);
    for (auto& memoryBinding : mvkImg->_memoryBindings) {
        addResource(memoryBinding);
    }
	return mvkImg;
}

void MVKDevice::destroyImage(MVKImage* mvkImg,
							 const VkAllocationCallbacks* pAllocator) {
	if (mvkImg) {
		for (auto& memoryBinding : mvkImg->_memoryBindings) {
            removeResource(memoryBinding);
        }
		mvkImg->destroy();
	}
}

MVKImageView* MVKDevice::createImageView(const VkImageViewCreateInfo* pCreateInfo,
										 const VkAllocationCallbacks* pAllocator) {
	return new MVKImageView(this, pCreateInfo);
}

void MVKDevice::destroyImageView(MVKImageView* mvkImgView,
								 const VkAllocationCallbacks* pAllocator) {
	if (mvkImgView) { mvkImgView->destroy(); }
}

MVKSwapchain* MVKDevice::createSwapchain(const VkSwapchainCreateInfoKHR* pCreateInfo,
										 const VkAllocationCallbacks* pAllocator) {
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

	return new MVKSwapchain(this, pCreateInfo);
}

void MVKDevice::destroySwapchain(MVKSwapchain* mvkSwpChn,
								 const VkAllocationCallbacks* pAllocator) {
	if (mvkSwpChn) { mvkSwpChn->destroy(); }
}

MVKPresentableSwapchainImage* MVKDevice::createPresentableSwapchainImage(const VkImageCreateInfo* pCreateInfo,
																		 MVKSwapchain* swapchain,
																		 uint32_t swapchainIndex,
																		 const VkAllocationCallbacks* pAllocator) {
    MVKPresentableSwapchainImage* mvkImg = new MVKPresentableSwapchainImage(this, pCreateInfo, swapchain, swapchainIndex);
    for (auto& memoryBinding : mvkImg->_memoryBindings) {
        addResource(memoryBinding);
    }
    return mvkImg;
}

void MVKDevice::destroyPresentableSwapchainImage(MVKPresentableSwapchainImage* mvkImg,
												 const VkAllocationCallbacks* pAllocator) {
	if (mvkImg) {
		for (auto& memoryBinding : mvkImg->_memoryBindings) {
            removeResource(memoryBinding);
        }
		mvkImg->destroy();
	}
}

MVKFence* MVKDevice::createFence(const VkFenceCreateInfo* pCreateInfo,
								 const VkAllocationCallbacks* pAllocator) {
	return new MVKFence(this, pCreateInfo);
}

void MVKDevice::destroyFence(MVKFence* mvkFence,
							 const VkAllocationCallbacks* pAllocator) {
	if (mvkFence) { mvkFence->destroy(); }
}

MVKSemaphore* MVKDevice::createSemaphore(const VkSemaphoreCreateInfo* pCreateInfo,
										 const VkAllocationCallbacks* pAllocator) {
	const VkSemaphoreTypeCreateInfo* pTypeCreateInfo = nullptr;
	for (auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO:
				pTypeCreateInfo = (VkSemaphoreTypeCreateInfo*)next;
				break;
			default:
				break;
		}
	}
	if (pTypeCreateInfo && pTypeCreateInfo->semaphoreType == VK_SEMAPHORE_TYPE_TIMELINE) {
		if (_pMetalFeatures->events) {
			return new MVKTimelineSemaphoreMTLEvent(this, pCreateInfo, pTypeCreateInfo);
		} else {
			return new MVKTimelineSemaphoreEmulated(this, pCreateInfo, pTypeCreateInfo);
		}
	} else {
		if (_useMTLEventForSemaphores) {
			return new MVKSemaphoreMTLEvent(this, pCreateInfo);
		} else if (_useMTLFenceForSemaphores) {
			return new MVKSemaphoreMTLFence(this, pCreateInfo);
		} else {
			return new MVKSemaphoreEmulated(this, pCreateInfo);
		}
	}
}

void MVKDevice::destroySemaphore(MVKSemaphore* mvkSem4,
								 const VkAllocationCallbacks* pAllocator) {
	if (mvkSem4) { mvkSem4->destroy(); }
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
	if (mvkEvent) { mvkEvent->destroy(); }
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
	if (mvkQP) { mvkQP->destroy(); }
}

MVKShaderModule* MVKDevice::createShaderModule(const VkShaderModuleCreateInfo* pCreateInfo,
											   const VkAllocationCallbacks* pAllocator) {
	return new MVKShaderModule(this, pCreateInfo);
}

void MVKDevice::destroyShaderModule(MVKShaderModule* mvkShdrMod,
									const VkAllocationCallbacks* pAllocator) {
	if (mvkShdrMod) { mvkShdrMod->destroy(); }
}

MVKPipelineCache* MVKDevice::createPipelineCache(const VkPipelineCacheCreateInfo* pCreateInfo,
												 const VkAllocationCallbacks* pAllocator) {
	return new MVKPipelineCache(this, pCreateInfo);
}

void MVKDevice::destroyPipelineCache(MVKPipelineCache* mvkPLC,
									 const VkAllocationCallbacks* pAllocator) {
	if (mvkPLC) { mvkPLC->destroy(); }
}

MVKPipelineLayout* MVKDevice::createPipelineLayout(const VkPipelineLayoutCreateInfo* pCreateInfo,
												   const VkAllocationCallbacks* pAllocator) {
	return new MVKPipelineLayout(this, pCreateInfo);
}

void MVKDevice::destroyPipelineLayout(MVKPipelineLayout* mvkPLL,
									  const VkAllocationCallbacks* pAllocator) {
	if (mvkPLL) { mvkPLL->destroy(); }
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
	if (mvkPL) { mvkPL->destroy(); }
}

MVKSampler* MVKDevice::createSampler(const VkSamplerCreateInfo* pCreateInfo,
									 const VkAllocationCallbacks* pAllocator) {
	return new MVKSampler(this, pCreateInfo);
}

void MVKDevice::destroySampler(MVKSampler* mvkSamp,
							   const VkAllocationCallbacks* pAllocator) {
	if (mvkSamp) { mvkSamp->destroy(); }
}

MVKSamplerYcbcrConversion* MVKDevice::createSamplerYcbcrConversion(const VkSamplerYcbcrConversionCreateInfo* pCreateInfo,
																   const VkAllocationCallbacks* pAllocator) {
	return new MVKSamplerYcbcrConversion(this, pCreateInfo);
}

void MVKDevice::destroySamplerYcbcrConversion(MVKSamplerYcbcrConversion* mvkSampConv,
											  const VkAllocationCallbacks* pAllocator) {
	mvkSampConv->destroy();
}

MVKDescriptorSetLayout* MVKDevice::createDescriptorSetLayout(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
															 const VkAllocationCallbacks* pAllocator) {
	return new MVKDescriptorSetLayout(this, pCreateInfo);
}

void MVKDevice::destroyDescriptorSetLayout(MVKDescriptorSetLayout* mvkDSL,
										   const VkAllocationCallbacks* pAllocator) {
	if (mvkDSL) { mvkDSL->destroy(); }
}

MVKDescriptorPool* MVKDevice::createDescriptorPool(const VkDescriptorPoolCreateInfo* pCreateInfo,
												   const VkAllocationCallbacks* pAllocator) {
	return new MVKDescriptorPool(this, pCreateInfo);
}

void MVKDevice::destroyDescriptorPool(MVKDescriptorPool* mvkDP,
									  const VkAllocationCallbacks* pAllocator) {
	if (mvkDP) { mvkDP->destroy(); }
}

MVKDescriptorUpdateTemplate* MVKDevice::createDescriptorUpdateTemplate(
	const VkDescriptorUpdateTemplateCreateInfoKHR* pCreateInfo,
	const VkAllocationCallbacks* pAllocator) {
	return new MVKDescriptorUpdateTemplate(this, pCreateInfo);
}

void MVKDevice::destroyDescriptorUpdateTemplate(MVKDescriptorUpdateTemplate* mvkDUT,
												const VkAllocationCallbacks* pAllocator) {
	if (mvkDUT) { mvkDUT->destroy(); }
}

MVKFramebuffer* MVKDevice::createFramebuffer(const VkFramebufferCreateInfo* pCreateInfo,
											 const VkAllocationCallbacks* pAllocator) {
	return new MVKFramebuffer(this, pCreateInfo);
}

void MVKDevice::destroyFramebuffer(MVKFramebuffer* mvkFB,
								   const VkAllocationCallbacks* pAllocator) {
	if (mvkFB) { mvkFB->destroy(); }
}

MVKRenderPass* MVKDevice::createRenderPass(const VkRenderPassCreateInfo* pCreateInfo,
										   const VkAllocationCallbacks* pAllocator) {
	return new MVKRenderPass(this, pCreateInfo);
}

MVKRenderPass* MVKDevice::createRenderPass(const VkRenderPassCreateInfo2* pCreateInfo,
										   const VkAllocationCallbacks* pAllocator) {
	return new MVKRenderPass(this, pCreateInfo);
}

void MVKDevice::destroyRenderPass(MVKRenderPass* mvkRP,
								  const VkAllocationCallbacks* pAllocator) {
	if (mvkRP) { mvkRP->destroy(); }
}

MVKCommandPool* MVKDevice::createCommandPool(const VkCommandPoolCreateInfo* pCreateInfo,
											const VkAllocationCallbacks* pAllocator) {
	return new MVKCommandPool(this, pCreateInfo, _useCommandPooling);
}

void MVKDevice::destroyCommandPool(MVKCommandPool* mvkCmdPool,
								   const VkAllocationCallbacks* pAllocator) {
	if (mvkCmdPool) { mvkCmdPool->destroy(); }
}

MVKDeviceMemory* MVKDevice::allocateMemory(const VkMemoryAllocateInfo* pAllocateInfo,
										   const VkAllocationCallbacks* pAllocator) {
	return new MVKDeviceMemory(this, pAllocateInfo, pAllocator);
}

void MVKDevice::freeMemory(MVKDeviceMemory* mvkDevMem,
						   const VkAllocationCallbacks* pAllocator) {
	if (mvkDevMem) { mvkDevMem->destroy(); }
}

// Look for an available pre-reserved private data slot and return it's address if found.
// Otherwise create a new instance and return it.
VkResult MVKDevice::createPrivateDataSlot(const VkPrivateDataSlotCreateInfoEXT* pCreateInfo,
										  const VkAllocationCallbacks* pAllocator,
										  VkPrivateDataSlotEXT* pPrivateDataSlot) {
	MVKPrivateDataSlot* mvkPDS = nullptr;

	size_t slotCnt = _privateDataSlots.size();
	for (size_t slotIdx = 0; slotIdx < slotCnt; slotIdx++) {
		if ( _privateDataSlotsAvailability[slotIdx] ) {
			_privateDataSlotsAvailability[slotIdx] = false;
			mvkPDS = _privateDataSlots[slotIdx];
			break;
		}
	}

	if ( !mvkPDS ) { mvkPDS = new MVKPrivateDataSlot(this); }

	*pPrivateDataSlot = (VkPrivateDataSlotEXT)mvkPDS;
	return VK_SUCCESS;
}

// If the private data slot is one of the pre-reserved slots, clear it and mark it as available.
// Otherwise destroy it.
void MVKDevice::destroyPrivateDataSlot(VkPrivateDataSlotEXT privateDataSlot,
									   const VkAllocationCallbacks* pAllocator) {

	MVKPrivateDataSlot* mvkPDS = (MVKPrivateDataSlot*)privateDataSlot;

	size_t slotCnt = _privateDataSlots.size();
	for (size_t slotIdx = 0; slotIdx < slotCnt; slotIdx++) {
		if (mvkPDS == _privateDataSlots[slotIdx]) {
			mvkPDS->clearData();
			_privateDataSlotsAvailability[slotIdx] = true;
			return;
		}
	}

	mvkPDS->destroy();
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

// Adds the specified host semaphore to be woken upon device loss.
void MVKDevice::addSemaphore(MVKSemaphoreImpl* sem4) {
	lock_guard<mutex> lock(_sem4Lock);
	_awaitingSemaphores.push_back(sem4);
}

// Removes the specified host semaphore.
void MVKDevice::removeSemaphore(MVKSemaphoreImpl* sem4) {
	lock_guard<mutex> lock(_sem4Lock);
	mvkRemoveFirstOccurance(_awaitingSemaphores, sem4);
}

// Adds the specified timeline semaphore to be woken at the specified value upon device loss.
void MVKDevice::addTimelineSemaphore(MVKTimelineSemaphore* sem4, uint64_t value) {
	lock_guard<mutex> lock(_sem4Lock);
	_awaitingTimelineSem4s.emplace_back(sem4, value);
}

// Removes the specified timeline semaphore.
void MVKDevice::removeTimelineSemaphore(MVKTimelineSemaphore* sem4, uint64_t value) {
	lock_guard<mutex> lock(_sem4Lock);
	mvkRemoveFirstOccurance(_awaitingTimelineSem4s, make_pair(sem4, value));
}

void MVKDevice::applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
								   VkPipelineStageFlags dstStageMask,
								   MVKPipelineBarrier& barrier,
								   MVKCommandEncoder* cmdEncoder,
								   MVKCommandUse cmdUse) {
	if (!mvkIsAnyFlagEnabled(dstStageMask, VK_PIPELINE_STAGE_HOST_BIT) ||
		!mvkIsAnyFlagEnabled(barrier.dstAccessMask, VK_ACCESS_HOST_READ_BIT) ) { return; }
	lock_guard<mutex> lock(_rezLock);
	for (auto& rez : _resources) {
		rez->applyMemoryBarrier(srcStageMask, dstStageMask, barrier, cmdEncoder, cmdUse);
	}
}

void MVKDevice::updateActivityPerformance(MVKPerformanceTracker& activity,
										  uint64_t startTime, uint64_t endTime) {

	double currInterval = mvkGetElapsedMilliseconds(startTime, endTime);
	lock_guard<mutex> lock(_perfLock);

	activity.latestDuration = currInterval;
	activity.minimumDuration = ((activity.minimumDuration == 0.0)
								? currInterval :
								min(currInterval, activity.minimumDuration));
	activity.maximumDuration = max(currInterval, activity.maximumDuration);
	double totalInterval = (activity.averageDuration * activity.count++) + currInterval;
	activity.averageDuration = totalInterval / activity.count;
}

void MVKDevice::logActivityPerformance(MVKPerformanceTracker& activity, MVKPerformanceStatistics& perfStats, bool isInline) {
	MVKLogInfo("%s%s%s avg: %.3f ms, latest: %.3f ms, min: %.3f ms, max: %.3f ms, count: %d",
			   (isInline ? "" : "  "),
			   getActivityPerformanceDescription(activity, perfStats),
			   (isInline ? " performance" : ""),
			   activity.averageDuration,
			   activity.latestDuration,
			   activity.minimumDuration,
			   activity.maximumDuration,
			   activity.count);
}

void MVKDevice::logPerformanceSummary() {
	if (_logActivityPerformanceInline) { return; }

	// Get a copy to minimize time under lock
	MVKPerformanceStatistics perfStats;
	getPerformanceStatistics(&perfStats);

	logActivityPerformance(perfStats.queue.frameInterval, perfStats);
	logActivityPerformance(perfStats.queue.nextCAMetalDrawable, perfStats);
	logActivityPerformance(perfStats.queue.mtlCommandBufferCompletion, perfStats);
	logActivityPerformance(perfStats.queue.mtlQueueAccess, perfStats);
	logActivityPerformance(perfStats.shaderCompilation.hashShaderCode, perfStats);
	logActivityPerformance(perfStats.shaderCompilation.spirvToMSL, perfStats);
	logActivityPerformance(perfStats.shaderCompilation.mslCompile, perfStats);
	logActivityPerformance(perfStats.shaderCompilation.mslLoad, perfStats);
	logActivityPerformance(perfStats.shaderCompilation.shaderLibraryFromCache, perfStats);
	logActivityPerformance(perfStats.shaderCompilation.functionRetrieval, perfStats);
	logActivityPerformance(perfStats.shaderCompilation.functionSpecialization, perfStats);
	logActivityPerformance(perfStats.shaderCompilation.pipelineCompile, perfStats);
	logActivityPerformance(perfStats.pipelineCache.sizePipelineCache, perfStats);
	logActivityPerformance(perfStats.pipelineCache.readPipelineCache, perfStats);
	logActivityPerformance(perfStats.pipelineCache.writePipelineCache, perfStats);
}

const char* MVKDevice::getActivityPerformanceDescription(MVKPerformanceTracker& activity, MVKPerformanceStatistics& perfStats) {
	if (&activity == &perfStats.shaderCompilation.hashShaderCode) { return "Hash shader SPIR-V code"; }
	if (&activity == &perfStats.shaderCompilation.spirvToMSL) { return "Convert SPIR-V to MSL source code"; }
	if (&activity == &perfStats.shaderCompilation.mslCompile) { return "Compile MSL source code into a MTLLibrary"; }
	if (&activity == &perfStats.shaderCompilation.mslLoad) { return "Load pre-compiled MSL code into a MTLLibrary"; }
	if (&activity == &perfStats.shaderCompilation.shaderLibraryFromCache) { return "Retrieve shader library from the cache"; }
	if (&activity == &perfStats.shaderCompilation.functionRetrieval) { return "Retrieve a MTLFunction from a MTLLibrary"; }
	if (&activity == &perfStats.shaderCompilation.functionSpecialization) { return "Specialize a retrieved MTLFunction"; }
	if (&activity == &perfStats.shaderCompilation.pipelineCompile) { return "Compile MTLFunctions into a pipeline"; }
	if (&activity == &perfStats.pipelineCache.sizePipelineCache) { return "Calculate cache size required to write MSL to pipeline cache"; }
	if (&activity == &perfStats.pipelineCache.readPipelineCache) { return "Read MSL from pipeline cache"; }
	if (&activity == &perfStats.pipelineCache.writePipelineCache) { return "Write MSL to pipeline cache"; }
	if (&activity == &perfStats.queue.mtlQueueAccess) { return "Access MTLCommandQueue"; }
	if (&activity == &perfStats.queue.mtlCommandBufferCompletion) { return "Complete MTLCommandBuffer"; }
	if (&activity == &perfStats.queue.nextCAMetalDrawable) { return "Retrieve a CAMetalDrawable from CAMetalLayer"; }
	if (&activity == &perfStats.queue.frameInterval) { return "Frame interval"; }
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

VkDeviceSize MVKDevice::getVkFormatTexelBufferAlignment(VkFormat format, MVKBaseObject* mvkObj) {
	VkDeviceSize deviceAlignment = 0;
	id<MTLDevice> mtlDev = getMTLDevice();
	MVKPixelFormats* mvkPixFmts = getPixelFormats();
	if ([mtlDev respondsToSelector: @selector(minimumLinearTextureAlignmentForPixelFormat:)]) {
		MTLPixelFormat mtlPixFmt = mvkPixFmts->getMTLPixelFormat(format);
		if (mvkPixFmts->getChromaSubsamplingPlaneCount(format) >= 2) {
			// Use plane 1 to get the alignment requirements. In a 2-plane format, this will
			// typically have stricter alignment requirements due to it being a 2-component format.
			mtlPixFmt = mvkPixFmts->getChromaSubsamplingPlaneMTLPixelFormat(format, 1);
		}
		deviceAlignment = [mtlDev minimumLinearTextureAlignmentForPixelFormat: mtlPixFmt];
	}
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

    NSUInteger mtlBuffLen = mvkAlignByteCount(newBuffLen, _pMetalFeatures->mtlBufferAlignment);
    MTLResourceOptions mtlBuffOpts = MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache;
    [_globalVisibilityResultMTLBuffer release];
    _globalVisibilityResultMTLBuffer = [getMTLDevice() newBufferWithLength: mtlBuffLen options: mtlBuffOpts];     // retained

    return _globalVisibilityQueryCount - queryCount;     // Might be lower than requested if an overflow occurred
}

id<MTLSamplerState> MVKDevice::getDefaultMTLSamplerState() {
	if ( !_defaultMTLSamplerState ) {

		// Lock and check again in case another thread has created the sampler.
		lock_guard<mutex> lock(_rezLock);
		if ( !_defaultMTLSamplerState ) {
			@autoreleasepool {
				MTLSamplerDescriptor* mtlSampDesc = [[MTLSamplerDescriptor new] autorelease];
				_defaultMTLSamplerState = [getMTLDevice() newSamplerStateWithDescriptor: mtlSampDesc];	// retained
			}
		}
	}
	return _defaultMTLSamplerState;
}

// Can't use prefilled Metal command buffers if any of the resource descriptors can be updated after binding.
bool MVKDevice::shouldPrefillMTLCommandBuffers() {
	return (_pMVKConfig->prefillMetalCommandBuffers &&
			!(_enabledDescriptorIndexingFeatures.descriptorBindingUniformBufferUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingSampledImageUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingStorageImageUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingStorageBufferUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingUniformTexelBufferUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingStorageTexelBufferUpdateAfterBind ||
			  _enabledInlineUniformBlockFeatures.descriptorBindingInlineUniformBlockUpdateAfterBind));
}


#pragma mark Construction

MVKDevice::MVKDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo) :
	_enabledFeatures(),
	_enabledStorage16Features(),
	_enabledStorage8Features(),
	_enabledF16I8Features(),
	_enabledUBOLayoutFeatures(),
	_enabledVarPtrFeatures(),
	_enabledDescriptorIndexingFeatures(),
	_enabledInlineUniformBlockFeatures(),
	_enabledInterlockFeatures(),
	_enabledHostQryResetFeatures(),
	_enabledSamplerYcbcrConversionFeatures(),
	_enabledScalarLayoutFeatures(),
	_enabledTexelBuffAlignFeatures(),
	_enabledVtxAttrDivFeatures(),
	_enabledPrivateDataFeatures(),
	_enabledPortabilityFeatures(),
	_enabledExtensions(this)
{
	// If the physical device is lost, bail.
	if (physicalDevice->getConfigurationResult() != VK_SUCCESS) {
		setConfigurationResult(physicalDevice->getConfigurationResult());
		return;
	}

	initPerformanceTracking();
	initPhysicalDevice(physicalDevice, pCreateInfo);
	enableFeatures(pCreateInfo);
	enableExtensions(pCreateInfo);
	initQueues(pCreateInfo);
	reservePrivateData(pCreateInfo);

    _globalVisibilityResultMTLBuffer = nil;
    _globalVisibilityQueryCount = 0;

	_defaultMTLSamplerState = nil;

	initMTLCompileOptions();	// Before command resource factory

	_commandResourceFactory = new MVKCommandResourceFactory(this);

	getInstance()->startAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_DEVICE, getMTLDevice());

	MVKLogInfo("Created VkDevice to run on GPU %s with the following %d Vulkan extensions enabled:%s",
			   _pProperties->deviceName,
			   _enabledExtensions.getEnabledCount(),
			   _enabledExtensions.enabledNamesString("\n\t\t", true).c_str());
}

void MVKDevice::initPerformanceTracking() {
#	ifndef MVK_CONFIG_PERFORMANCE_LOGGING_INLINE
#   	define MVK_CONFIG_PERFORMANCE_LOGGING_INLINE    0
#	endif
	MVK_SET_FROM_ENV_OR_BUILD_BOOL(_logActivityPerformanceInline, MVK_CONFIG_PERFORMANCE_LOGGING_INLINE);

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
	_performanceStatistics.queue.nextCAMetalDrawable = initPerf;
	_performanceStatistics.queue.frameInterval = initPerf;
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

	// Indicates whether semaphores should use a MTLFence if available.
	// Set by the MVK_ALLOW_METAL_FENCES environment variable if MTLFences are available.
	// This should be a temporary fix after some repair to semaphore handling.
	_useMTLFenceForSemaphores = false;
	if (_pMetalFeatures->fences) {
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(_useMTLFenceForSemaphores, MVK_ALLOW_METAL_FENCES);
	}

	// Indicates whether semaphores should use a MTLEvent if available.
	// Set by the MVK_ALLOW_METAL_EVENTS environment variable if MTLEvents are available.
	// This should be a temporary fix after some repair to semaphore handling.
	_useMTLEventForSemaphores = false;
	if (_pMetalFeatures->events) {
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(_useMTLEventForSemaphores, MVK_ALLOW_METAL_EVENTS);
	}
	MVKLogInfo("Using %s for Vulkan semaphores.", _useMTLEventForSemaphores ? "MTLEvent" : (_useMTLFenceForSemaphores ? "MTLFence" : "emulation"));

#	ifndef MVK_CONFIG_USE_COMMAND_POOLING
#   	define MVK_CONFIG_USE_COMMAND_POOLING    1
#	endif
	MVK_SET_FROM_ENV_OR_BUILD_BOOL(_useCommandPooling, MVK_CONFIG_USE_COMMAND_POOLING);
}

void MVKDevice::enableFeatures(const VkDeviceCreateInfo* pCreateInfo) {

	// Start with all features disabled
	mvkClear(&_enabledFeatures);
	mvkClear(&_enabledStorage16Features);
	mvkClear(&_enabledStorage8Features);
	mvkClear(&_enabledF16I8Features);
	mvkClear(&_enabledUBOLayoutFeatures);
	mvkClear(&_enabledVarPtrFeatures);
	mvkClear(&_enabledDescriptorIndexingFeatures);
	mvkClear(&_enabledInlineUniformBlockFeatures);
	mvkClear(&_enabledInterlockFeatures);
	mvkClear(&_enabledHostQryResetFeatures);
	mvkClear(&_enabledSamplerYcbcrConversionFeatures);
	mvkClear(&_enabledPrivateDataFeatures);
	mvkClear(&_enabledScalarLayoutFeatures);
	mvkClear(&_enabledTexelBuffAlignFeatures);
	mvkClear(&_enabledVtxAttrDivFeatures);
	mvkClear(&_enabledPortabilityFeatures);

	// Fetch the available physical device features.
	VkPhysicalDevicePortabilitySubsetFeaturesKHR pdPortabilityFeatures;
	pdPortabilityFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR;
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

	VkPhysicalDevicePrivateDataFeaturesEXT pdPrivateDataFeatures;
	pdPrivateDataFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIVATE_DATA_FEATURES_EXT;
	pdPrivateDataFeatures.pNext = &pdScalarLayoutFeatures;

	VkPhysicalDeviceSamplerYcbcrConversionFeatures pdSamplerYcbcrConversionFeatures;
	pdSamplerYcbcrConversionFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_YCBCR_CONVERSION_FEATURES;
	pdSamplerYcbcrConversionFeatures.pNext = &pdPrivateDataFeatures;

	VkPhysicalDeviceHostQueryResetFeaturesEXT pdHostQryResetFeatures;
	pdHostQryResetFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES_EXT;
	pdHostQryResetFeatures.pNext = &pdSamplerYcbcrConversionFeatures;

	VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT pdInterlockFeatures;
	pdInterlockFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT;
	pdInterlockFeatures.pNext = &pdHostQryResetFeatures;

	VkPhysicalDeviceInlineUniformBlockFeaturesEXT pdInlnUnfmBlkFeatures;
	pdInlnUnfmBlkFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_INLINE_UNIFORM_BLOCK_FEATURES_EXT;
	pdInlnUnfmBlkFeatures.pNext = &pdInterlockFeatures;

	VkPhysicalDeviceDescriptorIndexingFeaturesEXT pdDescIdxFeatures;
	pdDescIdxFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT;
	pdDescIdxFeatures.pNext = &pdInlnUnfmBlkFeatures;

	VkPhysicalDeviceVariablePointerFeatures pdVarPtrFeatures;
	pdVarPtrFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VARIABLE_POINTER_FEATURES;
	pdVarPtrFeatures.pNext = &pdDescIdxFeatures;

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

	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
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
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT: {
				auto* requestedFeatures = (VkPhysicalDeviceDescriptorIndexingFeaturesEXT*)next;
				enableFeatures(&_enabledDescriptorIndexingFeatures.shaderInputAttachmentArrayDynamicIndexing,
							   &requestedFeatures->shaderInputAttachmentArrayDynamicIndexing,
							   &pdDescIdxFeatures.shaderInputAttachmentArrayDynamicIndexing, 20);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_INLINE_UNIFORM_BLOCK_FEATURES_EXT: {
				auto* requestedFeatures = (VkPhysicalDeviceInlineUniformBlockFeaturesEXT*)next;
				enableFeatures(&_enabledInlineUniformBlockFeatures.inlineUniformBlock,
							   &requestedFeatures->inlineUniformBlock,
							   &pdInlnUnfmBlkFeatures.inlineUniformBlock, 2);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT: {
				auto* requestedFeatures = (VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT*)next;
				enableFeatures(&_enabledInterlockFeatures.fragmentShaderSampleInterlock,
							   &requestedFeatures->fragmentShaderSampleInterlock,
							   &pdInterlockFeatures.fragmentShaderSampleInterlock, 3);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES_EXT: {
				auto* requestedFeatures = (VkPhysicalDeviceHostQueryResetFeaturesEXT*)next;
				enableFeatures(&_enabledHostQryResetFeatures.hostQueryReset,
							   &requestedFeatures->hostQueryReset,
							   &pdHostQryResetFeatures.hostQueryReset, 1);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_YCBCR_CONVERSION_FEATURES: {
				auto* requestedFeatures = (VkPhysicalDeviceSamplerYcbcrConversionFeatures*)next;
				enableFeatures(&_enabledSamplerYcbcrConversionFeatures.samplerYcbcrConversion,
							   &requestedFeatures->samplerYcbcrConversion,
							   &pdSamplerYcbcrConversionFeatures.samplerYcbcrConversion, 1);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIVATE_DATA_FEATURES_EXT: {
				auto* requestedFeatures = (VkPhysicalDevicePrivateDataFeaturesEXT*)next;
				enableFeatures(&_enabledPrivateDataFeatures.privateData,
							   &requestedFeatures->privateData,
							   &pdPrivateDataFeatures.privateData, 1);
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
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR: {
				auto* requestedFeatures = (VkPhysicalDevicePortabilitySubsetFeaturesKHR*)next;
				enableFeatures(&_enabledPortabilityFeatures.constantAlphaColorBlendFactors,
							   &requestedFeatures->constantAlphaColorBlendFactors,
							   &pdPortabilityFeatures.constantAlphaColorBlendFactors, 15);
				break;
			}
			default:
				break;
		}
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
	auto qFams = _physicalDevice->getQueueFamilies();
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

void MVKDevice::reservePrivateData(const VkDeviceCreateInfo* pCreateInfo) {
	size_t slotCnt = 0;
	for (const auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DEVICE_PRIVATE_DATA_CREATE_INFO_EXT: {
				auto* pPDCreateInfo = (const VkDevicePrivateDataCreateInfoEXT*)next;
				slotCnt += pPDCreateInfo->privateDataSlotRequestCount;
				break;
			}
			default:
				break;
		}
	}

	_privateDataSlots.reserve(slotCnt);
	_privateDataSlotsAvailability.reserve(slotCnt);
	for (uint32_t slotIdx = 0; slotIdx < slotCnt; slotIdx++) {
		_privateDataSlots.push_back(new MVKPrivateDataSlot(this));
		_privateDataSlotsAvailability.push_back(true);
	}
}

void MVKDevice::initMTLCompileOptions() {
	_mtlCompileOptions = [MTLCompileOptions new];	// retained
	_mtlCompileOptions.languageVersion = _pMetalFeatures->mslVersionEnum;
	_mtlCompileOptions.fastMathEnabled = _pMVKConfig->fastMathEnabled;
}

MVKDevice::~MVKDevice() {
	for (auto& queues : _queuesByQueueFamilyIndex) {
		mvkDestroyContainerContents(queues);
	}
	_commandResourceFactory->destroy();

	[_mtlCompileOptions release];
    [_globalVisibilityResultMTLBuffer release];
	[_defaultMTLSamplerState release];

	getInstance()->stopAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_DEVICE);

	mvkDestroyContainerContents(_privateDataSlots);
}


#pragma mark -
#pragma mark Support functions

uint64_t mvkGetRegistryID(id<MTLDevice> mtlDevice) {
	return [mtlDevice respondsToSelector: @selector(registryID)] ? mtlDevice.registryID : 0;
}
