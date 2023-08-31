/*
 * MVKDevice.mm
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
#include "MVKStrings.h"
#include <MoltenVKShaderConverter/SPIRVToMSLConverter.h>

#import "CAMetalLayer+MoltenVK.h"

#include <cmath>

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

static const uint32_t kAMDRadeonRX5700DeviceId = 0x731f;
static const uint32_t kAMDRadeonRX5500DeviceId = 0x7340;
static const uint32_t kAMDRadeonRX6800DeviceId = 0x73bf;
static const uint32_t kAMDRadeonRX6700DeviceId = 0x73df;

static const VkExtent2D kMetalSamplePositionGridSize = { 1, 1 };
static const VkExtent2D kMetalSamplePositionGridSizeNotSupported = { 0, 0 };

static const uint32_t kMaxTimeDomains = 2;

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

	// Create a SSOT for these Vulkan 1.1 features, which can be queried via two mechanisms here.
	VkPhysicalDeviceVulkan11Features supportedFeats11 = {
		.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		.pNext = nullptr,
		.storageBuffer16BitAccess = true,
		.uniformAndStorageBuffer16BitAccess = true,
		.storagePushConstant16 = true,
		.storageInputOutput16 = true,
		.multiview = true,
		.multiviewGeometryShader = false,
		.multiviewTessellationShader = false,		// FIXME
		.variablePointersStorageBuffer = true,
		.variablePointers = true,
		.protectedMemory = false,
		.samplerYcbcrConversion = true,
		.shaderDrawParameters = true,
	};

	// Create a SSOT for these Vulkan 1.2 features, which can be queried via two mechanisms here.
	VkPhysicalDeviceVulkan12Features supportedFeats12 = {
		.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		.pNext = nullptr,
		.samplerMirrorClampToEdge = _vulkan12FeaturesNoExt.samplerMirrorClampToEdge,
		.drawIndirectCount = _vulkan12FeaturesNoExt.drawIndirectCount,
		.storageBuffer8BitAccess = true,
		.uniformAndStorageBuffer8BitAccess = true,
		.storagePushConstant8 = true,
		.shaderBufferInt64Atomics = false,
		.shaderSharedInt64Atomics = false,
		.shaderFloat16 = true,
		.shaderInt8 = true,
		.descriptorIndexing = _vulkan12FeaturesNoExt.descriptorIndexing,
		.shaderInputAttachmentArrayDynamicIndexing = _metalFeatures.arrayOfTextures,
		.shaderUniformTexelBufferArrayDynamicIndexing = _metalFeatures.arrayOfTextures,
		.shaderStorageTexelBufferArrayDynamicIndexing = _metalFeatures.arrayOfTextures,
		.shaderUniformBufferArrayNonUniformIndexing = false,
		.shaderSampledImageArrayNonUniformIndexing = _metalFeatures.arrayOfTextures && _metalFeatures.arrayOfSamplers,
		.shaderStorageBufferArrayNonUniformIndexing = false,
		.shaderStorageImageArrayNonUniformIndexing = _metalFeatures.arrayOfTextures,
		.shaderInputAttachmentArrayNonUniformIndexing = _metalFeatures.arrayOfTextures,
		.shaderUniformTexelBufferArrayNonUniformIndexing = _metalFeatures.arrayOfTextures,
		.shaderStorageTexelBufferArrayNonUniformIndexing = _metalFeatures.arrayOfTextures,
		.descriptorBindingUniformBufferUpdateAfterBind = true,
		.descriptorBindingSampledImageUpdateAfterBind = true,
		.descriptorBindingStorageImageUpdateAfterBind = true,
		.descriptorBindingStorageBufferUpdateAfterBind = true,
		.descriptorBindingUniformTexelBufferUpdateAfterBind = true,
		.descriptorBindingStorageTexelBufferUpdateAfterBind = true,
		.descriptorBindingUpdateUnusedWhilePending = true,
		.descriptorBindingPartiallyBound = true,
		.descriptorBindingVariableDescriptorCount = true,
		.runtimeDescriptorArray = true,
		.samplerFilterMinmax = _vulkan12FeaturesNoExt.samplerFilterMinmax,
		.scalarBlockLayout = true,
		.imagelessFramebuffer = true,
		.uniformBufferStandardLayout = true,
		.shaderSubgroupExtendedTypes = _metalFeatures.simdPermute || _metalFeatures.quadPermute,
		.separateDepthStencilLayouts = true,
		.hostQueryReset = true,
		.timelineSemaphore = true,
		.bufferDeviceAddress = mvkOSVersionIsAtLeast(12.05, 16.0, 1.0),
		.bufferDeviceAddressCaptureReplay = false,
		.bufferDeviceAddressMultiDevice = false,
		.vulkanMemoryModel = false,
		.vulkanMemoryModelDeviceScope = false,
		.vulkanMemoryModelAvailabilityVisibilityChains = false,
		.shaderOutputViewportIndex = _vulkan12FeaturesNoExt.shaderOutputViewportIndex,
		.shaderOutputLayer = _vulkan12FeaturesNoExt.shaderOutputLayer,
		.subgroupBroadcastDynamicId = _vulkan12FeaturesNoExt.subgroupBroadcastDynamicId,
	};

	features->sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
	features->features = _features;
	for (auto* next = (VkBaseOutStructure*)features->pNext; next; next = next->pNext) {
		switch ((uint32_t)next->sType) {
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES: {
				// Copy from supportedFeats11, but keep pNext as is.
				auto* pFeats11 = (VkPhysicalDeviceVulkan11Features*)next;
				supportedFeats11.pNext = pFeats11->pNext;
				*pFeats11 = supportedFeats11;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES: {
				// Copy from supportedFeats12, but keep pNext as is.
				auto* pFeats12 = (VkPhysicalDeviceVulkan12Features*)next;
				supportedFeats12.pNext = pFeats12->pNext;
				*pFeats12 = supportedFeats12;
				break;
			}

			// For consistency and ease of admin, keep the following list in the same order as in MVKDeviceFeatureStructs.def
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES: {
				auto* storageFeatures = (VkPhysicalDevice16BitStorageFeatures*)next;
				storageFeatures->storageBuffer16BitAccess = supportedFeats11.storageBuffer16BitAccess;
				storageFeatures->uniformAndStorageBuffer16BitAccess = supportedFeats11.uniformAndStorageBuffer16BitAccess;
				storageFeatures->storagePushConstant16 = supportedFeats11.storagePushConstant16;
				storageFeatures->storageInputOutput16 = supportedFeats11.storageInputOutput16;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_8BIT_STORAGE_FEATURES: {
				auto* storageFeatures = (VkPhysicalDevice8BitStorageFeatures*)next;
				storageFeatures->storageBuffer8BitAccess = supportedFeats12.storagePushConstant8;
				storageFeatures->uniformAndStorageBuffer8BitAccess = supportedFeats12.storagePushConstant8;
				storageFeatures->storagePushConstant8 = supportedFeats12.storagePushConstant8;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES:
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES_EXT: {
				auto* bufferDeviceAddressFeatures = (VkPhysicalDeviceBufferDeviceAddressFeatures*)next;
				bufferDeviceAddressFeatures->bufferDeviceAddress = supportedFeats12.bufferDeviceAddress;
				bufferDeviceAddressFeatures->bufferDeviceAddressCaptureReplay = supportedFeats12.bufferDeviceAddressCaptureReplay;
				bufferDeviceAddressFeatures->bufferDeviceAddressMultiDevice = supportedFeats12.bufferDeviceAddressMultiDevice;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES: {
				auto* pDescIdxFeatures = (VkPhysicalDeviceDescriptorIndexingFeatures*)next;
				pDescIdxFeatures->shaderInputAttachmentArrayDynamicIndexing = supportedFeats12.shaderInputAttachmentArrayDynamicIndexing;
				pDescIdxFeatures->shaderUniformTexelBufferArrayDynamicIndexing = supportedFeats12.shaderUniformTexelBufferArrayDynamicIndexing;
				pDescIdxFeatures->shaderStorageTexelBufferArrayDynamicIndexing = supportedFeats12.shaderStorageTexelBufferArrayDynamicIndexing;
				pDescIdxFeatures->shaderUniformBufferArrayNonUniformIndexing = supportedFeats12.shaderUniformBufferArrayNonUniformIndexing;
				pDescIdxFeatures->shaderSampledImageArrayNonUniformIndexing = supportedFeats12.shaderSampledImageArrayNonUniformIndexing;
				pDescIdxFeatures->shaderStorageBufferArrayNonUniformIndexing = supportedFeats12.shaderStorageBufferArrayNonUniformIndexing;
				pDescIdxFeatures->shaderStorageImageArrayNonUniformIndexing = supportedFeats12.shaderStorageImageArrayNonUniformIndexing;
				pDescIdxFeatures->shaderInputAttachmentArrayNonUniformIndexing = supportedFeats12.shaderInputAttachmentArrayNonUniformIndexing;
				pDescIdxFeatures->shaderUniformTexelBufferArrayNonUniformIndexing = supportedFeats12.shaderUniformTexelBufferArrayNonUniformIndexing;
				pDescIdxFeatures->shaderStorageTexelBufferArrayNonUniformIndexing = supportedFeats12.shaderStorageTexelBufferArrayNonUniformIndexing;
				pDescIdxFeatures->descriptorBindingUniformBufferUpdateAfterBind = supportedFeats12.descriptorBindingUniformBufferUpdateAfterBind;
				pDescIdxFeatures->descriptorBindingSampledImageUpdateAfterBind = supportedFeats12.descriptorBindingSampledImageUpdateAfterBind;
				pDescIdxFeatures->descriptorBindingStorageImageUpdateAfterBind = supportedFeats12.descriptorBindingStorageImageUpdateAfterBind;
				pDescIdxFeatures->descriptorBindingStorageBufferUpdateAfterBind = supportedFeats12.descriptorBindingStorageBufferUpdateAfterBind;
				pDescIdxFeatures->descriptorBindingUniformTexelBufferUpdateAfterBind = supportedFeats12.descriptorBindingUniformTexelBufferUpdateAfterBind;
				pDescIdxFeatures->descriptorBindingStorageTexelBufferUpdateAfterBind = supportedFeats12.descriptorBindingStorageTexelBufferUpdateAfterBind;
				pDescIdxFeatures->descriptorBindingUpdateUnusedWhilePending = supportedFeats12.descriptorBindingUpdateUnusedWhilePending;
				pDescIdxFeatures->descriptorBindingPartiallyBound = supportedFeats12.descriptorBindingPartiallyBound;
				pDescIdxFeatures->descriptorBindingVariableDescriptorCount = supportedFeats12.descriptorBindingVariableDescriptorCount;
				pDescIdxFeatures->runtimeDescriptorArray = supportedFeats12.runtimeDescriptorArray;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES: {
				auto* dynamicRenderingFeatures = (VkPhysicalDeviceDynamicRenderingFeatures*)next;
				dynamicRenderingFeatures->dynamicRendering = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_HOST_QUERY_RESET_FEATURES: {
				auto* hostQueryResetFeatures = (VkPhysicalDeviceHostQueryResetFeatures*)next;
				hostQueryResetFeatures->hostQueryReset = supportedFeats12.hostQueryReset;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGELESS_FRAMEBUFFER_FEATURES: {
				auto* imagelessFramebufferFeatures = (VkPhysicalDeviceImagelessFramebufferFeatures*)next;
				imagelessFramebufferFeatures->imagelessFramebuffer = supportedFeats12.imagelessFramebuffer;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_ROBUSTNESS_FEATURES: {
				auto *imageRobustnessFeatures = (VkPhysicalDeviceImageRobustnessFeatures*)next;
				imageRobustnessFeatures->robustImageAccess = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_INLINE_UNIFORM_BLOCK_FEATURES: {
				auto* inlineUniformBlockFeatures = (VkPhysicalDeviceInlineUniformBlockFeatures*)next;
				inlineUniformBlockFeatures->inlineUniformBlock = true;
				inlineUniformBlockFeatures->descriptorBindingInlineUniformBlockUpdateAfterBind = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MULTIVIEW_FEATURES: {
				auto* multiviewFeatures = (VkPhysicalDeviceMultiviewFeatures*)next;
				multiviewFeatures->multiview = supportedFeats11.multiview;
				multiviewFeatures->multiviewGeometryShader = supportedFeats11.multiviewGeometryShader;
				multiviewFeatures->multiviewTessellationShader = supportedFeats11.multiviewTessellationShader;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIVATE_DATA_FEATURES: {
				auto* privateDataFeatures = (VkPhysicalDevicePrivateDataFeatures*)next;
				privateDataFeatures->privateData = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROTECTED_MEMORY_FEATURES: {
				auto* protectedMemFeatures = (VkPhysicalDeviceProtectedMemoryFeatures*)next;
				protectedMemFeatures->protectedMemory = supportedFeats11.protectedMemory;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_YCBCR_CONVERSION_FEATURES: {
				auto* samplerYcbcrConvFeatures = (VkPhysicalDeviceSamplerYcbcrConversionFeatures*)next;
				samplerYcbcrConvFeatures->samplerYcbcrConversion = supportedFeats11.samplerYcbcrConversion;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES: {
				auto* scalarLayoutFeatures = (VkPhysicalDeviceScalarBlockLayoutFeatures*)next;
				scalarLayoutFeatures->scalarBlockLayout = supportedFeats12.scalarBlockLayout;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SEPARATE_DEPTH_STENCIL_LAYOUTS_FEATURES: {
				auto* separateDepthStencilLayoutsFeatures = (VkPhysicalDeviceSeparateDepthStencilLayoutsFeatures*)next;
				separateDepthStencilLayoutsFeatures->separateDepthStencilLayouts = supportedFeats12.separateDepthStencilLayouts;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES: {
				auto* shaderDrawParamsFeatures = (VkPhysicalDeviceShaderDrawParametersFeatures*)next;
				shaderDrawParamsFeatures->shaderDrawParameters = supportedFeats11.shaderDrawParameters;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_ATOMIC_INT64_FEATURES: {
				auto* i64Features = (VkPhysicalDeviceShaderAtomicInt64Features*)next;
				i64Features->shaderBufferInt64Atomics = supportedFeats12.shaderBufferInt64Atomics;
				i64Features->shaderSharedInt64Atomics = supportedFeats12.shaderSharedInt64Atomics;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_FLOAT16_INT8_FEATURES: {
				auto* f16Features = (VkPhysicalDeviceShaderFloat16Int8Features*)next;
				f16Features->shaderFloat16 = supportedFeats12.shaderFloat16;
				f16Features->shaderInt8 = supportedFeats12.shaderInt8;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_SUBGROUP_EXTENDED_TYPES_FEATURES: {
				auto* shaderSGTypesFeatures = (VkPhysicalDeviceShaderSubgroupExtendedTypesFeatures*)next;
				shaderSGTypesFeatures->shaderSubgroupExtendedTypes = supportedFeats12.shaderSubgroupExtendedTypes;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_FEATURES: {
				auto* subgroupSizeFeatures = (VkPhysicalDeviceSubgroupSizeControlFeatures*)next;
				subgroupSizeFeatures->subgroupSizeControl = _metalFeatures.simdPermute || _metalFeatures.quadPermute;
				subgroupSizeFeatures->computeFullSubgroups = _metalFeatures.simdPermute || _metalFeatures.quadPermute;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXTURE_COMPRESSION_ASTC_HDR_FEATURES: {
				auto* astcHDRFeatures = (VkPhysicalDeviceTextureCompressionASTCHDRFeatures*)next;
				astcHDRFeatures->textureCompressionASTC_HDR = _metalFeatures.astcHDRTextures;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES: {
				auto* timelineSem4Features = (VkPhysicalDeviceTimelineSemaphoreFeatures*)next;
				timelineSem4Features->timelineSemaphore = supportedFeats12.timelineSemaphore;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_UNIFORM_BUFFER_STANDARD_LAYOUT_FEATURES: {
				auto* uboLayoutFeatures = (VkPhysicalDeviceUniformBufferStandardLayoutFeatures*)next;
				uboLayoutFeatures->uniformBufferStandardLayout = supportedFeats12.uniformBufferStandardLayout;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VARIABLE_POINTER_FEATURES: {
				auto* varPtrFeatures = (VkPhysicalDeviceVariablePointerFeatures*)next;
				varPtrFeatures->variablePointersStorageBuffer = supportedFeats11.variablePointersStorageBuffer;
				varPtrFeatures->variablePointers = supportedFeats11.variablePointers;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_MEMORY_MODEL_FEATURES: {
				auto* vmmFeatures = (VkPhysicalDeviceVulkanMemoryModelFeatures*)next;
				vmmFeatures->vulkanMemoryModel = supportedFeats12.vulkanMemoryModel;
				vmmFeatures->vulkanMemoryModelDeviceScope = supportedFeats12.vulkanMemoryModelDeviceScope;
				vmmFeatures->vulkanMemoryModelAvailabilityVisibilityChains = supportedFeats12.vulkanMemoryModelAvailabilityVisibilityChains;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_BARYCENTRIC_FEATURES_KHR: {
				auto* barycentricFeatures = (VkPhysicalDeviceFragmentShaderBarycentricFeaturesKHR*)next;
				barycentricFeatures->fragmentShaderBarycentric = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR: {
				auto* portabilityFeatures = (VkPhysicalDevicePortabilitySubsetFeaturesKHR*)next;
				portabilityFeatures->constantAlphaColorBlendFactors = true;
				portabilityFeatures->events = true;
				portabilityFeatures->imageViewFormatReinterpretation = true;
				portabilityFeatures->imageViewFormatSwizzle = (_metalFeatures.nativeTextureSwizzle ||
															   mvkConfig().fullImageViewSwizzle);
				portabilityFeatures->imageView2DOn3DImage = false;
				portabilityFeatures->multisampleArrayImage = _metalFeatures.multisampleArrayTextures;
				portabilityFeatures->mutableComparisonSamplers = _metalFeatures.depthSampleCompare;
				portabilityFeatures->pointPolygons = false;
				portabilityFeatures->samplerMipLodBias = false;
				portabilityFeatures->separateStencilMaskRef = true;
				portabilityFeatures->shaderSampleRateInterpolationFunctions = _metalFeatures.pullModelInterpolation;
				portabilityFeatures->tessellationIsolines = false;
				portabilityFeatures->tessellationPointMode = false;
				portabilityFeatures->triangleFans = true;
				portabilityFeatures->vertexAttributeAccessBeyondStride = true;	// Costs additional buffers. Should make configuration switch.
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_4444_FORMATS_FEATURES_EXT: {
				auto* formatFeatures = (VkPhysicalDevice4444FormatsFeaturesEXT*)next;
				bool canSupport4444 = _metalFeatures.tileBasedDeferredRendering &&
									  (_metalFeatures.nativeTextureSwizzle ||
									   mvkConfig().fullImageViewSwizzle);
				formatFeatures->formatA4R4G4B4 = canSupport4444;
				formatFeatures->formatA4B4G4R4 = canSupport4444;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT: {
				auto* interlockFeatures = (VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT*)next;
				interlockFeatures->fragmentShaderSampleInterlock = _metalFeatures.rasterOrderGroups;
				interlockFeatures->fragmentShaderPixelInterlock = _metalFeatures.rasterOrderGroups;
				interlockFeatures->fragmentShaderShadingRateInterlock = false;    // Requires variable rate shading; not supported yet in Metal
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PIPELINE_CREATION_CACHE_CONTROL_FEATURES_EXT: {
				auto* pipelineCreationCacheControlFeatures = (VkPhysicalDevicePipelineCreationCacheControlFeaturesEXT*)next;
				pipelineCreationCacheControlFeatures->pipelineCreationCacheControl = true;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT: {
				auto* robustness2Features = (VkPhysicalDeviceRobustness2FeaturesEXT*)next;
				robustness2Features->robustBufferAccess2 = false;
				robustness2Features->robustImageAccess2 = true;
				robustness2Features->nullDescriptor = false;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_ATOMIC_FLOAT_FEATURES_EXT: {
				auto* atomicFloatFeatures = (VkPhysicalDeviceShaderAtomicFloatFeaturesEXT*)next;
				bool atomicFloatEnabled = _metalFeatures.mslVersion >= 030000;
				atomicFloatFeatures->shaderBufferFloat32Atomics = atomicFloatEnabled;
				atomicFloatFeatures->shaderBufferFloat32AtomicAdd = atomicFloatEnabled;
				atomicFloatFeatures->shaderBufferFloat64Atomics = false;
				atomicFloatFeatures->shaderBufferFloat64AtomicAdd = false;
				atomicFloatFeatures->shaderSharedFloat32Atomics = atomicFloatEnabled;
				atomicFloatFeatures->shaderSharedFloat32AtomicAdd = atomicFloatEnabled;
				atomicFloatFeatures->shaderSharedFloat64Atomics = false;
				atomicFloatFeatures->shaderSharedFloat64AtomicAdd = false;
				atomicFloatFeatures->shaderImageFloat32Atomics = false;
				atomicFloatFeatures->shaderImageFloat32AtomicAdd = false;
				atomicFloatFeatures->sparseImageFloat32Atomics = false;
				atomicFloatFeatures->sparseImageFloat32AtomicAdd = false;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DEMOTE_TO_HELPER_INVOCATION_FEATURES_EXT: {
				auto* demoteFeatures = (VkPhysicalDeviceShaderDemoteToHelperInvocationFeaturesEXT*)next;
				demoteFeatures->shaderDemoteToHelperInvocation = mvkOSVersionIsAtLeast(11.0, 14.0, 1.0);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SWAPCHAIN_MAINTENANCE_1_FEATURES_EXT: {
				auto* swapchainMaintenance1Features = (VkPhysicalDeviceSwapchainMaintenance1FeaturesEXT*)next;
				swapchainMaintenance1Features->swapchainMaintenance1 = true;
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
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_INTEGER_FUNCTIONS_2_FEATURES_INTEL: {
				auto* shaderIntFuncsFeatures = (VkPhysicalDeviceShaderIntegerFunctions2FeaturesINTEL*)next;
				shaderIntFuncsFeatures->shaderIntegerFunctions2 = true;
				break;
			}
			default:
				break;
		}
	}
}

void MVKPhysicalDevice::getProperties(VkPhysicalDeviceProperties* properties) {
	updateTimestampsAndPeriod();
	*properties = _properties;
}

void MVKPhysicalDevice::getProperties(VkPhysicalDeviceProperties2* properties) {

	properties->sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
	getProperties(&properties->properties);

	if ( !properties->pNext ) { return; }

	uint32_t uintMax = std::numeric_limits<uint32_t>::max();
	uint32_t maxSamplerCnt = getMaxSamplerCount();
	bool isTier2 = supportsMetalArgumentBuffers() && (_metalFeatures.argumentBuffersTier >= MTLArgumentBuffersTier2);

	// Create a SSOT for these Vulkan 1.1 properties, which can be queried via two mechanisms here.
	VkPhysicalDeviceVulkan11Properties supportedProps11;
	supportedProps11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES;
	supportedProps11.pNext = nullptr;
	populateDeviceIDProperties(&supportedProps11);
	populateSubgroupProperties(&supportedProps11);
	supportedProps11.pointClippingBehavior = VK_POINT_CLIPPING_BEHAVIOR_ALL_CLIP_PLANES;
	supportedProps11.maxMultiviewViewCount = 32;
	supportedProps11.maxMultiviewInstanceIndex = canUseInstancingForMultiview() ? uintMax / 32 : uintMax;
	supportedProps11.protectedNoFault = false;
	supportedProps11.maxPerSetDescriptors = 4 * (_metalFeatures.maxPerStageBufferCount +
												 _metalFeatures.maxPerStageTextureCount +
												 _metalFeatures.maxPerStageSamplerCount);
	supportedProps11.maxMemoryAllocationSize = _metalFeatures.maxMTLBufferSize;

	// Create a SSOT for these Vulkan 1.2 properties, which can be queried via two mechanisms here.
	VkPhysicalDeviceVulkan12Properties supportedProps12;
	supportedProps12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_PROPERTIES;
	supportedProps12.pNext = nullptr;
	supportedProps12.driverID = VK_DRIVER_ID_MOLTENVK;
	strcpy(supportedProps12.driverName, "MoltenVK");
	strcpy(supportedProps12.driverInfo, mvkGetMoltenVKVersionString(MVK_VERSION).c_str());
	supportedProps12.conformanceVersion.major = 0;
	supportedProps12.conformanceVersion.minor = 0;
	supportedProps12.conformanceVersion.subminor = 0;
	supportedProps12.conformanceVersion.patch = 0;
	supportedProps12.denormBehaviorIndependence = VK_SHADER_FLOAT_CONTROLS_INDEPENDENCE_NONE;
	supportedProps12.roundingModeIndependence = VK_SHADER_FLOAT_CONTROLS_INDEPENDENCE_NONE;
	supportedProps12.shaderSignedZeroInfNanPreserveFloat16 = true;
	supportedProps12.shaderSignedZeroInfNanPreserveFloat32 = true;
	supportedProps12.shaderSignedZeroInfNanPreserveFloat64 = false;
	supportedProps12.shaderDenormPreserveFloat16 = false;
	supportedProps12.shaderDenormPreserveFloat32 = false;
	supportedProps12.shaderDenormPreserveFloat64 = false;
	supportedProps12.shaderDenormFlushToZeroFloat16 = false;
	supportedProps12.shaderDenormFlushToZeroFloat32 = false;
	supportedProps12.shaderDenormFlushToZeroFloat64 = false;
	supportedProps12.shaderRoundingModeRTEFloat16 = false;
	supportedProps12.shaderRoundingModeRTEFloat32 = false;
	supportedProps12.shaderRoundingModeRTEFloat64 = false;
	supportedProps12.shaderRoundingModeRTZFloat16 = false;
	supportedProps12.shaderRoundingModeRTZFloat32 = false;
	supportedProps12.shaderRoundingModeRTZFloat64 = false;
	supportedProps12.maxUpdateAfterBindDescriptorsInAllPools				= kMVKUndefinedLargeUInt32;
	supportedProps12.shaderUniformBufferArrayNonUniformIndexingNative		= false;
	supportedProps12.shaderSampledImageArrayNonUniformIndexingNative		= _metalFeatures.arrayOfTextures && _metalFeatures.arrayOfSamplers;
	supportedProps12.shaderStorageBufferArrayNonUniformIndexingNative		= false;
	supportedProps12.shaderStorageImageArrayNonUniformIndexingNative		= _metalFeatures.arrayOfTextures;
	supportedProps12.shaderInputAttachmentArrayNonUniformIndexingNative		= _metalFeatures.arrayOfTextures;
	supportedProps12.robustBufferAccessUpdateAfterBind						= _features.robustBufferAccess;
	supportedProps12.quadDivergentImplicitLod								= false;
	supportedProps12.maxPerStageDescriptorUpdateAfterBindSamplers			= isTier2 ? maxSamplerCnt : _properties.limits.maxPerStageDescriptorSamplers;
	supportedProps12.maxPerStageDescriptorUpdateAfterBindUniformBuffers		= isTier2 ? 500000 : _properties.limits.maxPerStageDescriptorUniformBuffers;
	supportedProps12.maxPerStageDescriptorUpdateAfterBindStorageBuffers		= isTier2 ? 500000 : _properties.limits.maxPerStageDescriptorStorageBuffers;
	supportedProps12.maxPerStageDescriptorUpdateAfterBindSampledImages		= isTier2 ? 500000 : _properties.limits.maxPerStageDescriptorSampledImages;
	supportedProps12.maxPerStageDescriptorUpdateAfterBindStorageImages		= isTier2 ? 500000 : _properties.limits.maxPerStageDescriptorStorageImages;
	supportedProps12.maxPerStageDescriptorUpdateAfterBindInputAttachments	= _properties.limits.maxPerStageDescriptorInputAttachments;
	supportedProps12.maxPerStageUpdateAfterBindResources					= isTier2 ? 500000 : _properties.limits.maxPerStageResources;
	supportedProps12.maxDescriptorSetUpdateAfterBindSamplers				= isTier2 ? maxSamplerCnt : _properties.limits.maxDescriptorSetSamplers;
	supportedProps12.maxDescriptorSetUpdateAfterBindUniformBuffers			= isTier2 ? 500000 : _properties.limits.maxDescriptorSetUniformBuffers;
	supportedProps12.maxDescriptorSetUpdateAfterBindUniformBuffersDynamic	= isTier2 ? 500000 : _properties.limits.maxDescriptorSetUniformBuffersDynamic;
	supportedProps12.maxDescriptorSetUpdateAfterBindStorageBuffers			= isTier2 ? 500000 : _properties.limits.maxDescriptorSetStorageBuffers;
	supportedProps12.maxDescriptorSetUpdateAfterBindStorageBuffersDynamic	= isTier2 ? 500000 : _properties.limits.maxDescriptorSetStorageBuffersDynamic;
	supportedProps12.maxDescriptorSetUpdateAfterBindSampledImages			= isTier2 ? 500000 : _properties.limits.maxDescriptorSetSampledImages;
	supportedProps12.maxDescriptorSetUpdateAfterBindStorageImages			= isTier2 ? 500000 : _properties.limits.maxDescriptorSetStorageImages;
	supportedProps12.maxDescriptorSetUpdateAfterBindInputAttachments		= _properties.limits.maxDescriptorSetInputAttachments;
	supportedProps12.supportedDepthResolveModes = (_metalFeatures.depthResolve
												   ? VK_RESOLVE_MODE_SAMPLE_ZERO_BIT | VK_RESOLVE_MODE_MIN_BIT | VK_RESOLVE_MODE_MAX_BIT
												   : VK_RESOLVE_MODE_SAMPLE_ZERO_BIT);
	supportedProps12.supportedStencilResolveModes = VK_RESOLVE_MODE_SAMPLE_ZERO_BIT;	// Metal allows you to set the stencil resolve filter to either Sample0 or the same sample used for depth resolve. This is impossible to express in Vulkan.
	supportedProps12.independentResolveNone = true;
	supportedProps12.independentResolve = true;
	supportedProps12.filterMinmaxSingleComponentFormats = false;
	supportedProps12.filterMinmaxImageComponentMapping = false;
	supportedProps12.maxTimelineSemaphoreValueDifference = std::numeric_limits<uint64_t>::max();
	supportedProps12.framebufferIntegerColorSampleCounts = _metalFeatures.supportedSampleCounts;

	for (auto* next = (VkBaseOutStructure*)properties->pNext; next; next = next->pNext) {
		switch ((uint32_t)next->sType) {
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES: {
				// Copy from supportedProps11, but keep pNext as is.
				auto* pProps11 = (VkPhysicalDeviceVulkan11Properties*)next;
				supportedProps11.pNext = pProps11->pNext;
				*pProps11 = supportedProps11;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_PROPERTIES: {
				// Copy from supportedProps12, but keep pNext as is.
				auto* pProps12 = (VkPhysicalDeviceVulkan12Properties*)next;
				supportedProps12.pNext = pProps12->pNext;
				*pProps12 = supportedProps12;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES: {
				auto* dvcIDProps = (VkPhysicalDeviceIDProperties*)next;
				mvkCopy(dvcIDProps->deviceUUID, supportedProps11.deviceUUID, VK_UUID_SIZE);
				mvkCopy(dvcIDProps->driverUUID, supportedProps11.driverUUID, VK_UUID_SIZE);
				mvkCopy(dvcIDProps->deviceLUID, supportedProps11.deviceLUID, VK_LUID_SIZE);
				dvcIDProps->deviceNodeMask = supportedProps11.deviceNodeMask;
				dvcIDProps->deviceLUIDValid = supportedProps11.deviceLUIDValid;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_PROPERTIES: {
				auto* subgroupProps = (VkPhysicalDeviceSubgroupProperties*)next;
				subgroupProps->subgroupSize = supportedProps11.subgroupSize;
				subgroupProps->supportedStages = supportedProps11.subgroupSupportedStages;
				subgroupProps->supportedOperations = supportedProps11.subgroupSupportedOperations;
				subgroupProps->quadOperationsInAllStages = supportedProps11.subgroupQuadOperationsInAllStages;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_POINT_CLIPPING_PROPERTIES: {
				auto* pointClipProps = (VkPhysicalDevicePointClippingProperties*)next;
				pointClipProps->pointClippingBehavior = supportedProps11.pointClippingBehavior;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MULTIVIEW_PROPERTIES: {
				auto* multiviewProps = (VkPhysicalDeviceMultiviewProperties*)next;
				multiviewProps->maxMultiviewViewCount = supportedProps11.maxMultiviewViewCount;
				multiviewProps->maxMultiviewInstanceIndex = supportedProps11.maxMultiviewInstanceIndex;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROTECTED_MEMORY_PROPERTIES: {
				auto* protectedMemProps = (VkPhysicalDeviceProtectedMemoryProperties*)next;
				protectedMemProps->protectedNoFault = supportedProps11.protectedNoFault;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_3_PROPERTIES: {
				auto* maint3Props = (VkPhysicalDeviceMaintenance3Properties*)next;
				maint3Props->maxPerSetDescriptors = supportedProps11.maxPerSetDescriptors;
				maint3Props->maxMemoryAllocationSize = supportedProps11.maxMemoryAllocationSize;
				break;
			}

			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DEPTH_STENCIL_RESOLVE_PROPERTIES: {
				auto* depthStencilResolveProps = (VkPhysicalDeviceDepthStencilResolveProperties*)next;
				depthStencilResolveProps->supportedDepthResolveModes = supportedProps12.supportedDepthResolveModes;
				depthStencilResolveProps->supportedStencilResolveModes = supportedProps12.supportedStencilResolveModes;
				depthStencilResolveProps->independentResolveNone = supportedProps12.independentResolveNone;
				depthStencilResolveProps->independentResolve = supportedProps12.independentResolve;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES: {
				auto* physicalDeviceDriverProps = (VkPhysicalDeviceDriverProperties*)next;
				physicalDeviceDriverProps->driverID = supportedProps12.driverID;
				mvkCopy(physicalDeviceDriverProps->driverName, supportedProps12.driverName, VK_MAX_DRIVER_NAME_SIZE);
				mvkCopy(physicalDeviceDriverProps->driverInfo, supportedProps12.driverInfo, VK_MAX_DRIVER_INFO_SIZE);
				physicalDeviceDriverProps->conformanceVersion = supportedProps12.conformanceVersion;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_FILTER_MINMAX_PROPERTIES: {
				auto* sfmmProps = (VkPhysicalDeviceSamplerFilterMinmaxProperties*)next;
				sfmmProps->filterMinmaxSingleComponentFormats = supportedProps12.filterMinmaxSingleComponentFormats;
				sfmmProps->filterMinmaxImageComponentMapping = supportedProps12.filterMinmaxImageComponentMapping;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_PROPERTIES: {
                auto* timelineSem4Props = (VkPhysicalDeviceTimelineSemaphoreProperties*)next;
                timelineSem4Props->maxTimelineSemaphoreValueDifference = supportedProps12.maxTimelineSemaphoreValueDifference;
                break;
            }
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES: {
				auto* pDescIdxProps = (VkPhysicalDeviceDescriptorIndexingProperties*)next;
				pDescIdxProps->maxUpdateAfterBindDescriptorsInAllPools				= supportedProps12.maxUpdateAfterBindDescriptorsInAllPools;
				pDescIdxProps->shaderUniformBufferArrayNonUniformIndexingNative		= supportedProps12.shaderUniformBufferArrayNonUniformIndexingNative;
				pDescIdxProps->shaderSampledImageArrayNonUniformIndexingNative		= supportedProps12.shaderSampledImageArrayNonUniformIndexingNative;
				pDescIdxProps->shaderStorageBufferArrayNonUniformIndexingNative		= supportedProps12.shaderStorageBufferArrayNonUniformIndexingNative;
				pDescIdxProps->shaderStorageImageArrayNonUniformIndexingNative		= supportedProps12.shaderStorageImageArrayNonUniformIndexingNative;
				pDescIdxProps->shaderInputAttachmentArrayNonUniformIndexingNative	= supportedProps12.shaderInputAttachmentArrayNonUniformIndexingNative;
				pDescIdxProps->robustBufferAccessUpdateAfterBind					= supportedProps12.robustBufferAccessUpdateAfterBind;
				pDescIdxProps->quadDivergentImplicitLod								= supportedProps12.quadDivergentImplicitLod;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindSamplers			= supportedProps12.maxPerStageDescriptorUpdateAfterBindSamplers;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindUniformBuffers	= supportedProps12.maxPerStageDescriptorUpdateAfterBindUniformBuffers;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindStorageBuffers	= supportedProps12.maxPerStageDescriptorUpdateAfterBindStorageBuffers;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindSampledImages	= supportedProps12.maxPerStageDescriptorUpdateAfterBindSampledImages;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindStorageImages	= supportedProps12.maxPerStageDescriptorUpdateAfterBindStorageImages;
				pDescIdxProps->maxPerStageDescriptorUpdateAfterBindInputAttachments	= supportedProps12.maxPerStageDescriptorUpdateAfterBindInputAttachments;
				pDescIdxProps->maxPerStageUpdateAfterBindResources					= supportedProps12.maxPerStageUpdateAfterBindResources;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindSamplers				= supportedProps12.maxDescriptorSetUpdateAfterBindSamplers;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindUniformBuffers		= supportedProps12.maxDescriptorSetUpdateAfterBindUniformBuffers;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindUniformBuffersDynamic	= supportedProps12.maxDescriptorSetUpdateAfterBindUniformBuffersDynamic;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindStorageBuffers		= supportedProps12.maxDescriptorSetUpdateAfterBindStorageBuffers;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindStorageBuffersDynamic	= supportedProps12.maxDescriptorSetUpdateAfterBindStorageBuffersDynamic;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindSampledImages			= supportedProps12.maxDescriptorSetUpdateAfterBindSampledImages;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindStorageImages			= supportedProps12.maxDescriptorSetUpdateAfterBindStorageImages;
				pDescIdxProps->maxDescriptorSetUpdateAfterBindInputAttachments		= supportedProps12.maxDescriptorSetUpdateAfterBindInputAttachments;
				break;
			}
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_INLINE_UNIFORM_BLOCK_PROPERTIES: {
				auto* inlineUniformBlockProps = (VkPhysicalDeviceInlineUniformBlockProperties*)next;
				inlineUniformBlockProps->maxInlineUniformBlockSize = _metalFeatures.dynamicMTLBufferSize;
                inlineUniformBlockProps->maxPerStageDescriptorInlineUniformBlocks = _metalFeatures.dynamicMTLBufferSize ? _metalFeatures.maxPerStageDynamicMTLBufferCount - 1 : 0;    // Less one for push constants
                inlineUniformBlockProps->maxPerStageDescriptorUpdateAfterBindInlineUniformBlocks = inlineUniformBlockProps->maxPerStageDescriptorInlineUniformBlocks;
                inlineUniformBlockProps->maxDescriptorSetInlineUniformBlocks = (inlineUniformBlockProps->maxPerStageDescriptorInlineUniformBlocks * 4);
                inlineUniformBlockProps->maxDescriptorSetUpdateAfterBindInlineUniformBlocks = (inlineUniformBlockProps->maxPerStageDescriptorUpdateAfterBindInlineUniformBlocks * 4);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_PROPERTIES: {
				auto* subgroupSizeProps = (VkPhysicalDeviceSubgroupSizeControlProperties*)next;
				subgroupSizeProps->minSubgroupSize = _metalFeatures.minSubgroupSize;
				subgroupSizeProps->maxSubgroupSize = _metalFeatures.maxSubgroupSize;
				subgroupSizeProps->maxComputeWorkgroupSubgroups = _properties.limits.maxComputeWorkGroupInvocations / _metalFeatures.minSubgroupSize;
				subgroupSizeProps->requiredSubgroupSizeStages = 0;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXEL_BUFFER_ALIGNMENT_PROPERTIES: {
				// Save the 'next' pointer; we'll unintentionally overwrite it
				// on the next line. Put it back when we're done.
				auto* texelBuffAlignProps = (VkPhysicalDeviceTexelBufferAlignmentProperties*)next;
				void* pNext = texelBuffAlignProps->pNext;
				*texelBuffAlignProps = _texelBuffAlignProperties;
				texelBuffAlignProps->pNext = pNext;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES: {
				auto* floatControlsProperties = (VkPhysicalDeviceFloatControlsProperties*)next;
				floatControlsProperties->denormBehaviorIndependence = supportedProps12.denormBehaviorIndependence;
				floatControlsProperties->roundingModeIndependence = supportedProps12.roundingModeIndependence;
				floatControlsProperties->shaderSignedZeroInfNanPreserveFloat16 = supportedProps12.shaderSignedZeroInfNanPreserveFloat16;
				floatControlsProperties->shaderSignedZeroInfNanPreserveFloat32 = supportedProps12.shaderSignedZeroInfNanPreserveFloat32;
				floatControlsProperties->shaderSignedZeroInfNanPreserveFloat64 = supportedProps12.shaderSignedZeroInfNanPreserveFloat64;
				floatControlsProperties->shaderDenormPreserveFloat16 = supportedProps12.shaderDenormPreserveFloat16;
				floatControlsProperties->shaderDenormPreserveFloat32 = supportedProps12.shaderDenormPreserveFloat32;
				floatControlsProperties->shaderDenormPreserveFloat64 = supportedProps12.shaderDenormPreserveFloat64;
				floatControlsProperties->shaderDenormFlushToZeroFloat16 = supportedProps12.shaderDenormFlushToZeroFloat16;
				floatControlsProperties->shaderDenormFlushToZeroFloat32 = supportedProps12.shaderDenormFlushToZeroFloat32;
				floatControlsProperties->shaderDenormFlushToZeroFloat64 = supportedProps12.shaderDenormFlushToZeroFloat64;
				floatControlsProperties->shaderRoundingModeRTEFloat16 = supportedProps12.shaderRoundingModeRTEFloat16;
				floatControlsProperties->shaderRoundingModeRTEFloat32 = supportedProps12.shaderRoundingModeRTEFloat32;
				floatControlsProperties->shaderRoundingModeRTEFloat64 = supportedProps12.shaderRoundingModeRTEFloat64;
				floatControlsProperties->shaderRoundingModeRTZFloat16 = supportedProps12.shaderRoundingModeRTZFloat16;
				floatControlsProperties->shaderRoundingModeRTZFloat32 = supportedProps12.shaderRoundingModeRTZFloat32;
				floatControlsProperties->shaderRoundingModeRTZFloat64 = supportedProps12.shaderRoundingModeRTZFloat64;
				break;
			}
            case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_BARYCENTRIC_PROPERTIES_KHR: {
                auto* barycentricProperties = (VkPhysicalDeviceFragmentShaderBarycentricPropertiesKHR*)next;
                barycentricProperties->triStripVertexOrderIndependentOfProvokingVertex = false;
                break;
            }
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PUSH_DESCRIPTOR_PROPERTIES_KHR: {
				auto* pushDescProps = (VkPhysicalDevicePushDescriptorPropertiesKHR*)next;
				pushDescProps->maxPushDescriptors = _properties.limits.maxPerStageResources;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_PROPERTIES_KHR: {
				auto* portabilityProps = (VkPhysicalDevicePortabilitySubsetPropertiesKHR*)next;
				portabilityProps->minVertexInputBindingStrideAlignment = (uint32_t)_metalFeatures.vertexStrideAlignment;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_MEMORY_HOST_PROPERTIES_EXT: {
				auto* extMemHostProps = (VkPhysicalDeviceExternalMemoryHostPropertiesEXT*)next;
				extMemHostProps->minImportedHostPointerAlignment = _metalFeatures.hostMemoryPageSize;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_PROPERTIES_EXT: {
				// This isn't implemented yet, but when it is, it is expected that we'll wind up doing it manually.
				auto* robustness2Props = (VkPhysicalDeviceRobustness2PropertiesEXT*)next;
				robustness2Props->robustStorageBufferAccessSizeAlignment = 1;
				robustness2Props->robustUniformBufferAccessSizeAlignment = 1;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLE_LOCATIONS_PROPERTIES_EXT: {
				auto* sampLocnProps = (VkPhysicalDeviceSampleLocationsPropertiesEXT*)next;
				sampLocnProps->sampleLocationSampleCounts = _metalFeatures.supportedSampleCounts;
				sampLocnProps->maxSampleLocationGridSize = kMetalSamplePositionGridSize;
				sampLocnProps->sampleLocationCoordinateRange[0] = 0.0;
				sampLocnProps->sampleLocationCoordinateRange[1] = (15.0 / 16.0);
				sampLocnProps->sampleLocationSubPixelBits = 4;
				sampLocnProps->variableSampleLocations = VK_FALSE;
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VERTEX_ATTRIBUTE_DIVISOR_PROPERTIES_EXT: {
				auto* divisorProps = (VkPhysicalDeviceVertexAttributeDivisorPropertiesEXT*)next;
				divisorProps->maxVertexAttribDivisor = kMVKUndefinedLargeUInt32;
				break;
			}
			default:
				break;
		}
	}
}

// Since these are uint8_t arrays, use Big-Endian byte ordering,
// so a hex dump of the array is human readable in its parts.
void MVKPhysicalDevice::populateDeviceIDProperties(VkPhysicalDeviceVulkan11Properties* pVk11Props) {
	uint8_t* uuid;
	size_t uuidComponentOffset;

	//  ---- Device UUID ----------------------------------------------
	uuid = pVk11Props->deviceUUID;
	uuidComponentOffset = 0;
	mvkClear(uuid, VK_UUID_SIZE);

	// From Vulkan spec: deviceUUID must be universally unique for the device,
	// AND must be immutable for a given device across instances, processes,
	// driver APIs, driver versions, and system reboots.

	// First 4 bytes contains GPU vendor ID
	uint32_t vendorID = _properties.vendorID;
	*(uint32_t*)&uuid[uuidComponentOffset] = NSSwapHostIntToBig(vendorID);
	uuidComponentOffset += sizeof(vendorID);

	// Next 4 bytes contains GPU device ID
	uint32_t deviceID = _properties.deviceID;
	*(uint32_t*)&uuid[uuidComponentOffset] = NSSwapHostIntToBig(deviceID);
	uuidComponentOffset += sizeof(deviceID);

	// Last 8 bytes contain the GPU location identifier
	uint64_t locID = mvkGetLocationID(_mtlDevice);
	*(uint64_t*)&uuid[uuidComponentOffset] = NSSwapHostLongLongToBig(locID);
	uuidComponentOffset += sizeof(locID);

	// ---- Driver ID ----------------------------------------------
	uuid = pVk11Props->driverUUID;
	uuidComponentOffset = 0;
	mvkClear(uuid, VK_UUID_SIZE);

	// First 4 bytes contains MoltenVK prefix
	const char* mvkPfx = "MVK";
	size_t mvkPfxLen = strlen(mvkPfx);
	mvkCopy(&uuid[uuidComponentOffset], (uint8_t*)mvkPfx, mvkPfxLen);
	uuidComponentOffset += mvkPfxLen + 1;

	// Next 4 bytes contains MoltenVK version
	uint32_t mvkVersion = MVK_VERSION;
	*(uint32_t*)&uuid[uuidComponentOffset] = NSSwapHostIntToBig(mvkVersion);
	uuidComponentOffset += sizeof(mvkVersion);

	// Next 4 bytes contains highest GPU capability supported by this device
	uint32_t gpuCap = getHighestGPUCapability();
	*(uint32_t*)&uuid[uuidComponentOffset] = NSSwapHostIntToBig(gpuCap);
	uuidComponentOffset += sizeof(gpuCap);

	// ---- Device LUID ------------------------
	*(uint64_t*)pVk11Props->deviceLUID = NSSwapHostLongLongToBig(mvkGetRegistryID(_mtlDevice));
	pVk11Props->deviceNodeMask = 1;		// Per Vulkan spec
	pVk11Props->deviceLUIDValid = VK_TRUE;
}

void MVKPhysicalDevice::populateSubgroupProperties(VkPhysicalDeviceVulkan11Properties* pVk11Props) {
	pVk11Props->subgroupSize = _metalFeatures.maxSubgroupSize;
	pVk11Props->subgroupSupportedStages = VK_SHADER_STAGE_COMPUTE_BIT;
	if (_features.tessellationShader) {
		pVk11Props->subgroupSupportedStages |= VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT;
	}
	if (mvkOSVersionIsAtLeast(10.15, 13.0, 1.0)) {
		pVk11Props->subgroupSupportedStages |= VK_SHADER_STAGE_FRAGMENT_BIT;
	}
	pVk11Props->subgroupSupportedOperations = VK_SUBGROUP_FEATURE_BASIC_BIT;
	if (_metalFeatures.simdPermute || _metalFeatures.quadPermute) {
		pVk11Props->subgroupSupportedOperations |= (VK_SUBGROUP_FEATURE_VOTE_BIT |
													VK_SUBGROUP_FEATURE_BALLOT_BIT |
													VK_SUBGROUP_FEATURE_SHUFFLE_BIT |
													VK_SUBGROUP_FEATURE_SHUFFLE_RELATIVE_BIT);
	}
	if (_metalFeatures.simdReduction) {
		pVk11Props->subgroupSupportedOperations |= VK_SUBGROUP_FEATURE_ARITHMETIC_BIT;
	}
	if (_metalFeatures.quadPermute) {
		pVk11Props->subgroupSupportedOperations |= VK_SUBGROUP_FEATURE_QUAD_BIT;
	}
	pVk11Props->subgroupQuadOperationsInAllStages = _metalFeatures.quadPermute;
}

void MVKPhysicalDevice::getFormatProperties(VkFormat format, VkFormatProperties* pFormatProperties) {
	*pFormatProperties = _pixelFormats.getVkFormatProperties(format);
}

void MVKPhysicalDevice::getFormatProperties(VkFormat format, VkFormatProperties2KHR* pFormatProperties) {
	pFormatProperties->sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2_KHR;
	getFormatProperties(format, &pFormatProperties->formatProperties);
}

void MVKPhysicalDevice::getMultisampleProperties(VkSampleCountFlagBits samples,
												 VkMultisamplePropertiesEXT* pMultisampleProperties) {
	if (pMultisampleProperties) {
		pMultisampleProperties->maxSampleLocationGridSize = (mvkIsOnlyAnyFlagEnabled(samples, _metalFeatures.supportedSampleCounts)
															 ? kMetalSamplePositionGridSize
															 : kMetalSamplePositionGridSizeNotSupported);
	}
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
			if (!mvkConfig().texture1DAs2D) {
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
#if !MVK_APPLE_SILICON
				// - On macOS IMR GPUs, Linear textures may not be used as framebuffer attachments.
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
#if MVK_APPLE_SILICON
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

	auto usage = pImageFormatInfo->usage;
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
			case VK_STRUCTURE_TYPE_IMAGE_STENCIL_USAGE_CREATE_INFO: {
				// If the format includes a stencil component, combine any separate stencil usage with non-stencil usage.
				if (_pixelFormats.isStencilFormat(_pixelFormats.getMTLPixelFormat(pImageFormatInfo->format))) {
					usage |= ((VkImageStencilUsageCreateInfo*)nextInfo)->stencilUsage;
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
									pImageFormatInfo->tiling, usage,
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
		case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT:
		case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_MAPPED_FOREIGN_MEMORY_BIT_EXT:
			return _hostPointerExternalMemoryProperties;
		case VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_KHR:
			return _mtlBufferExternalMemoryProperties;
		default:
			return _emptyExtMemProps;
	}
}

VkExternalMemoryProperties& MVKPhysicalDevice::getExternalImageProperties(VkExternalMemoryHandleTypeFlagBits handleType) {
	switch (handleType) {
		case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT:
		case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_MAPPED_FOREIGN_MEMORY_BIT_EXT:
			return _hostPointerExternalMemoryProperties;
		case VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR:
			return _mtlTextureExternalMemoryProperties;
		default:
			return _emptyExtMemProps;
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

VkResult MVKPhysicalDevice::getCalibrateableTimeDomains(uint32_t* pTimeDomainCount, VkTimeDomainEXT* pTimeDomains) {
	if (!pTimeDomains) {
		*pTimeDomainCount = kMaxTimeDomains;
		return VK_SUCCESS;
	}
	// XXX CLOCK_MONOTONIC_RAW is mach_continuous_time(), but
	// -[MTLDevice sampleTimestamps:gpuTimestamp:] returns the CPU
	// timestamp in the mach_absolute_time() domain, which is CLOCK_UPTIME_RAW
	// (cf. Libc/gen/clock_gettime.c).
	static const VkTimeDomainEXT domains[] = { VK_TIME_DOMAIN_DEVICE_EXT, VK_TIME_DOMAIN_CLOCK_MONOTONIC_RAW_EXT };
	std::copy_n(domains, min(*pTimeDomainCount, kMaxTimeDomains), pTimeDomains);
	if (*pTimeDomainCount < kMaxTimeDomains) { return VK_INCOMPLETE; }
	*pTimeDomainCount = kMaxTimeDomains;
	return VK_SUCCESS;
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

VkResult MVKPhysicalDevice::getSurfaceCapabilities(VkSurfaceKHR surface,
												   VkSurfaceCapabilitiesKHR* pSurfaceCapabilities) {
	VkPhysicalDeviceSurfaceInfo2KHR surfaceInfo;
	surfaceInfo.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SURFACE_INFO_2_KHR;
	surfaceInfo.pNext = nullptr;
	surfaceInfo.surface = surface;

	VkSurfaceCapabilities2KHR surfaceCaps;
	surfaceCaps.sType = VK_STRUCTURE_TYPE_SURFACE_CAPABILITIES_2_KHR;
	surfaceCaps.pNext = nullptr;
	surfaceCaps.surfaceCapabilities = *pSurfaceCapabilities;

	VkResult rslt = getSurfaceCapabilities(&surfaceInfo, &surfaceCaps);

	*pSurfaceCapabilities = surfaceCaps.surfaceCapabilities;

	return rslt;
}

VkResult MVKPhysicalDevice::getSurfaceCapabilities(	const VkPhysicalDeviceSurfaceInfo2KHR* pSurfaceInfo,
												   VkSurfaceCapabilities2KHR* pSurfaceCapabilities) {

	// Retrieve the present mode if it is supplied in this query.
	VkPresentModeKHR presentMode = VK_PRESENT_MODE_MAX_ENUM_KHR;
	for (auto* next = (const VkBaseInStructure*)pSurfaceInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_SURFACE_PRESENT_MODE_EXT: {
				presentMode = ((VkSurfacePresentModeEXT*)next)->presentMode;
				break;
			}
			default:
				break;
		}
	}

	// Retrieve the scaling and present mode compatibility structs if they are supplied in this query.
	VkSurfacePresentScalingCapabilitiesEXT* pScalingCaps = nullptr;
	VkSurfacePresentModeCompatibilityEXT* pCompatibility = nullptr;
	for (auto* next = (VkBaseOutStructure*)pSurfaceCapabilities->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_SURFACE_PRESENT_SCALING_CAPABILITIES_EXT: {
				pScalingCaps = (VkSurfacePresentScalingCapabilitiesEXT*)next;
				break;
			}
			case VK_STRUCTURE_TYPE_SURFACE_PRESENT_MODE_COMPATIBILITY_EXT: {
				pCompatibility = (VkSurfacePresentModeCompatibilityEXT*)next;
				break;
			}
			default:
				break;
		}
	}

	// The CAlayer underlying the surface must be a CAMetalLayer.
	MVKSurface* surface = (MVKSurface*)pSurfaceInfo->surface;
	CAMetalLayer* mtlLayer = surface->getCAMetalLayer();
	if ( !mtlLayer ) { return surface->getConfigurationResult(); }

	VkSurfaceCapabilitiesKHR& surfCaps = pSurfaceCapabilities->surfaceCapabilities;
	surfCaps.minImageCount = _metalFeatures.minSwapchainImageCount;
	surfCaps.maxImageCount = _metalFeatures.maxSwapchainImageCount;
	surfCaps.currentExtent = mvkGetNaturalExtent(mtlLayer);
	surfCaps.minImageExtent = { 1, 1 };
	surfCaps.maxImageExtent = { _properties.limits.maxImageDimension2D, _properties.limits.maxImageDimension2D };
	surfCaps.maxImageArrayLayers = 1;
	surfCaps.supportedTransforms = (VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR);
	surfCaps.currentTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
	surfCaps.supportedCompositeAlpha = (VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR |
										VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR |
										VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR);
	surfCaps.supportedUsageFlags = (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
									VK_IMAGE_USAGE_STORAGE_BIT |
									VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
									VK_IMAGE_USAGE_TRANSFER_DST_BIT |
									VK_IMAGE_USAGE_SAMPLED_BIT);

	// Swapchain-to-surface scaling capabilities.
	if (pScalingCaps) {
		pScalingCaps->supportedPresentScaling = (VK_PRESENT_SCALING_ONE_TO_ONE_BIT_EXT |
												 VK_PRESENT_SCALING_ASPECT_RATIO_STRETCH_BIT_EXT |
												 VK_PRESENT_SCALING_STRETCH_BIT_EXT);
		pScalingCaps->supportedPresentGravityX = (VK_PRESENT_GRAVITY_MIN_BIT_EXT |
												  VK_PRESENT_GRAVITY_MAX_BIT_EXT |
												  VK_PRESENT_GRAVITY_CENTERED_BIT_EXT);
		pScalingCaps->supportedPresentGravityY = (VK_PRESENT_GRAVITY_MIN_BIT_EXT |
												  VK_PRESENT_GRAVITY_MAX_BIT_EXT |
												  VK_PRESENT_GRAVITY_CENTERED_BIT_EXT);
		pScalingCaps->minScaledImageExtent = surfCaps.minImageExtent;
		pScalingCaps->maxScaledImageExtent = surfCaps.maxImageExtent;
	}


	// Per spec, always include the queried present mode in returned compatibility results.
	MVKSmallVector<VkPresentModeKHR> compatiblePresentModes;
	if (presentMode != VK_PRESENT_MODE_MAX_ENUM_KHR) { compatiblePresentModes.push_back(presentMode); }

	// Customize results based on the provided present mode.
	switch (presentMode) {
		case VK_PRESENT_MODE_FIFO_KHR:
			// This could be dodgy, because Metal may not match the Vulkan spec's tight
			// requirements for transitioning from FIFO to IMMEDIATE, because the change to
			// IMMEDIATE may occur while some FIFO items are still on the GPU queue.
			if (_metalFeatures.presentModeImmediate) {
				compatiblePresentModes.push_back(VK_PRESENT_MODE_IMMEDIATE_KHR);
			}
			break;
		case VK_PRESENT_MODE_IMMEDIATE_KHR:
			compatiblePresentModes.push_back(VK_PRESENT_MODE_FIFO_KHR);
			surfCaps.minImageCount = surfCaps.maxImageCount;	// Recommend always using max count to avoid visual tearing.
			break;
		case VK_PRESENT_MODE_SHARED_DEMAND_REFRESH_KHR:
		case VK_PRESENT_MODE_SHARED_CONTINUOUS_REFRESH_KHR:
			// Although these are not advertised as supported, per spec, counts must be 1.
			surfCaps.minImageCount = 1;
			surfCaps.maxImageCount = 1;
			break;

		default:
			break;
	}

	// If compatible present modes are requested, return them, otherwise return the count of them.
	if (pCompatibility) {
		if (pCompatibility->pPresentModes) {
			pCompatibility->presentModeCount = min(pCompatibility->presentModeCount, (uint32_t)compatiblePresentModes.size());
			for (uint32_t pmIdx = 0; pmIdx < pCompatibility->presentModeCount; pmIdx++) {
				pCompatibility->pPresentModes[pmIdx] = compatiblePresentModes[pmIdx];
			}
		} else {
			pCompatibility->presentModeCount = (uint32_t)compatiblePresentModes.size();
		}
	}

	return VK_SUCCESS;
}

VkResult MVKPhysicalDevice::getSurfaceFormats(MVKSurface* surface,
											  uint32_t* pCount,
											  VkSurfaceFormatKHR* pSurfaceFormats) {

	// The layer underlying the surface view must be a CAMetalLayer.
	CAMetalLayer* mtlLayer = surface->getCAMetalLayer();
	if ( !mtlLayer ) { return surface->getConfigurationResult(); }

#define addSurfFmt(MTL_FMT) \
	do { \
		if (_pixelFormats.isSupported(MTLPixelFormat ##MTL_FMT)) { \
			VkFormat vkFmt = _pixelFormats.getVkFormat(MTLPixelFormat ##MTL_FMT); \
			if (vkFmt) { vkFormats.push_back(vkFmt); } \
		} \
	} while(false)

	MVKSmallVector<VkFormat, 16> vkFormats;
	addSurfFmt(BGRA8Unorm);
	addSurfFmt(BGRA8Unorm_sRGB);
	addSurfFmt(RGBA16Float);
#if MVK_MACOS
	addSurfFmt(RGB10A2Unorm);
	addSurfFmt(BGR10A2Unorm);
#endif
#if MVK_APPLE_SILICON
	addSurfFmt(BGRA10_XR);
	addSurfFmt(BGRA10_XR_sRGB);
	addSurfFmt(BGR10_XR);
	addSurfFmt(BGR10_XR_sRGB);
#endif

	MVKSmallVector<VkColorSpaceKHR, 16> colorSpaces;
	colorSpaces.push_back(VK_COLOR_SPACE_SRGB_NONLINEAR_KHR);
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
#if MVK_XCODE_12
    if (mvkOSVersionIsAtLeast(11.0)) {
        colorSpaces.push_back(VK_COLOR_SPACE_HDR10_HLG_EXT);
        colorSpaces.push_back(VK_COLOR_SPACE_HDR10_ST2084_EXT);
    }
#endif
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
#if MVK_XCODE_12
    if (mvkOSVersionIsAtLeast(14.0)) {
        colorSpaces.push_back(VK_COLOR_SPACE_HDR10_HLG_EXT);
        colorSpaces.push_back(VK_COLOR_SPACE_HDR10_ST2084_EXT);
    }
#endif
#endif

	size_t vkFmtsCnt = vkFormats.size();
	size_t vkColSpcFmtsCnt = vkFmtsCnt * colorSpaces.size();

	// If properties aren't actually being requested yet, simply update the returned count
	if ( !pSurfaceFormats ) {
		*pCount = (uint32_t)vkColSpcFmtsCnt;
		return VK_SUCCESS;
	}

	// Determine how many results we'll return, and return that number
	VkResult result = (*pCount >= vkColSpcFmtsCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(*pCount, (uint32_t)vkColSpcFmtsCnt);

	// Now populate the supplied array
	for (uint csIdx = 0, idx = 0; idx < *pCount && csIdx < colorSpaces.size(); csIdx++) {
		for (uint fmtIdx = 0; idx < *pCount && fmtIdx < vkFmtsCnt; fmtIdx++, idx++) {
			pSurfaceFormats[idx].format = vkFormats[fmtIdx];
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
	pRects[0].extent = mvkGetNaturalExtent(mtlLayer);

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
		bool specialize = mvkConfig().specializedQueueFamilies;
		uint32_t qfIdx = 0;

		qfProps.queueCount = kMVKQueueCountPerQueueFamily;
		qfProps.timestampValidBits = 64;
		qfProps.minImageTransferGranularity = { 1, 1, 1};

		// General-purpose queue family
		qfProps.queueFlags = (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT);
		_queueFamilies.push_back(new MVKQueueFamily(this, qfIdx++, &qfProps));

		// Single queue semaphore requires using a single queue for everything
		// So don't allow anyone to have more than one
		if (_vkSemaphoreStyle != MVKSemaphoreStyleSingleQueue) {
			// Dedicated graphics queue family...or another general-purpose queue family.
			if (specialize) { qfProps.queueFlags = (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_TRANSFER_BIT); }
			_queueFamilies.push_back(new MVKQueueFamily(this, qfIdx++, &qfProps));

			// Dedicated compute queue family...or another general-purpose queue family.
			if (specialize) { qfProps.queueFlags = (VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT); }
			_queueFamilies.push_back(new MVKQueueFamily(this, qfIdx++, &qfProps));

			// Dedicated transfer queue family...or another general-purpose queue family.
			if (specialize) { qfProps.queueFlags = VK_QUEUE_TRANSFER_BIT; }
			_queueFamilies.push_back(new MVKQueueFamily(this, qfIdx++, &qfProps));
		}

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

// If needed, update the timestamp period for this device, using a crude lowpass filter to level out
// wild temporary changes, particularly during initial queries before much GPU activity has occurred.
// On Apple GPUs, CPU & GPU timestamps are the same, and timestamp period never changes.
void MVKPhysicalDevice::updateTimestampsAndPeriod() {
	if (_properties.vendorID == kAppleVendorId) { return; }
	
	if ([_mtlDevice respondsToSelector: @selector(sampleTimestamps:gpuTimestamp:)]) {
		MTLTimestamp earlierCPUTs = _prevCPUTimestamp;
		MTLTimestamp earlierGPUTs = _prevGPUTimestamp;
		[_mtlDevice sampleTimestamps: &_prevCPUTimestamp gpuTimestamp: &_prevGPUTimestamp];
		double elapsedCPUNanos = _prevCPUTimestamp - earlierCPUTs;
		double elapsedGPUTicks = _prevGPUTimestamp - earlierGPUTs;
		if (elapsedCPUNanos && elapsedGPUTicks) {		// Ensure not zero
			float tsPeriod = elapsedCPUNanos / elapsedGPUTicks;
			
			// Basic lowpass filter Y = (1 - a)Y + a*X.
			// The lower a is, the slower Y will change over time.
			static const float a = 0.05;
			_properties.limits.timestampPeriod = ((1.0 - a) * _properties.limits.timestampPeriod) + (a * tsPeriod);
		}
	}
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
				mvkClear(budgetProps->heapBudget, VK_MAX_MEMORY_HEAPS);
				mvkClear(budgetProps->heapUsage, VK_MAX_MEMORY_HEAPS);
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

	initMTLDevice();
	initProperties();           		// Call first.
	initMetalFeatures();        		// Call second.
	initFeatures();             		// Call third.
	initLimits();						// Call fourth.
	initExtensions();
	initMemoryProperties();
	initExternalMemoryProperties();
	initCounterSets();
	initVkSemaphoreStyle();
	logGPUInfo();
}

void MVKPhysicalDevice::initMTLDevice() {
#if MVK_XCODE_14_3 && MVK_MACOS && !MVK_MACCAT
	if ([_mtlDevice respondsToSelector: @selector(setShouldMaximizeConcurrentCompilation:)]) {
		[_mtlDevice setShouldMaximizeConcurrentCompilation: mvkConfig().shouldMaximizeConcurrentCompilation];
		MVKLogInfoIf(mvkConfig().debugMode, "maximumConcurrentCompilationTaskCount %lu", _mtlDevice.maximumConcurrentCompilationTaskCount);
	}
#endif
}

// Initializes the physical device properties (except limits).
void MVKPhysicalDevice::initProperties() {
	mvkClear(&_properties);	// Start with everything cleared

	_properties.apiVersion = mvkConfig().apiVersionToAdvertise;
	_properties.driverVersion = MVK_VERSION;

	initGPUInfoProperties();
	initPipelineCacheUUID();
}

// Initializes the Metal-specific physical device features of this instance.
void MVKPhysicalDevice::initMetalFeatures() {

	// Start with all Metal features cleared
	mvkClear(&_metalFeatures);

	_metalFeatures.hostMemoryPageSize = mvkGetHostMemoryPageSize();

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

	// GPU-specific features
	switch (_properties.vendorID) {
		case kAMDVendorId:
			_metalFeatures.clearColorFloatRounding = MVK_FLOAT_ROUNDING_DOWN;
			break;
		case kAppleVendorId:
			// TODO: Other GPUs?
			if (!mvkOSVersionIsAtLeast(14.0, 17.0, 1.0)) {
				_metalFeatures.needsSampleDrefLodArrayWorkaround = true;
			}
			// fallthrough
		case kIntelVendorId:
		case kNVVendorId:
		default:
			_metalFeatures.clearColorFloatRounding = MVK_FLOAT_ROUNDING_NEAREST;
			break;
	}

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
	_metalFeatures.tileBasedDeferredRendering = true;

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
		_metalFeatures.argumentBuffers = true;
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
		_metalFeatures.placementHeaps = mvkConfig().useMTLHeap;
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
#if MVK_XCODE_13
	if ( mvkOSVersionIsAtLeast(15.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_4;
	}
#endif
#if MVK_XCODE_14
	if ( mvkOSVersionIsAtLeast(16.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion3_0;
	}
#endif

#if MVK_XCODE_15
    if ( mvkOSVersionIsAtLeast(17.0) ) {
        _metalFeatures.mslVersionEnum = MTLLanguageVersion3_1;
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
	_metalFeatures.tileBasedDeferredRendering = true;

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
		_metalFeatures.argumentBuffers = true;
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
		_metalFeatures.placementHeaps = mvkConfig().useMTLHeap;
#if MVK_OS_SIMULATOR
		_metalFeatures.nativeTextureSwizzle = false;
#else
		_metalFeatures.nativeTextureSwizzle = true;
#endif
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
#if MVK_XCODE_13
	if ( mvkOSVersionIsAtLeast(15.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_4;
	}
#endif
#if MVK_XCODE_14
	if ( mvkOSVersionIsAtLeast(16.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion3_0;
	}
#endif
#if MVK_XCODE_15
    if ( mvkOSVersionIsAtLeast(17.0) ) {
        _metalFeatures.mslVersionEnum = MTLLanguageVersion3_1;
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
		_metalFeatures.argumentBuffers = true;
    }

    if (supportsMTLFeatureSet(macOS_GPUFamily1_v4)) {
        _metalFeatures.mslVersionEnum = MTLLanguageVersion2_1;
        _metalFeatures.multisampleArrayTextures = true;
		_metalFeatures.events = true;
        _metalFeatures.textureBuffers = true;
    }

	if (supportsMTLFeatureSet(macOS_GPUFamily2_v1)) {
		_metalFeatures.multisampleLayeredRendering = _metalFeatures.layeredRendering;
		_metalFeatures.stencilFeedback = true;
		_metalFeatures.depthResolve = true;
		_metalFeatures.stencilResolve = true;
		_metalFeatures.simdPermute = true;
		_metalFeatures.quadPermute = true;
		_metalFeatures.simdReduction = true;
	}

	if ( mvkOSVersionIsAtLeast(10.15) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_2;
		_metalFeatures.maxQueryBufferSize = (256 * KIBI);
		_metalFeatures.native3DCompressedTextures = true;
        if ( mvkOSVersionIsAtLeast(mvkMakeOSVersion(10, 15, 6)) ) {
            _metalFeatures.sharedLinearTextures = true;
        }
		if (supportsMTLGPUFamily(Mac2)) {
			_metalFeatures.nativeTextureSwizzle = true;
			_metalFeatures.placementHeaps = mvkConfig().useMTLHeap;
			_metalFeatures.renderWithoutAttachments = true;
		}
	}

#if MVK_XCODE_12
	if ( mvkOSVersionIsAtLeast(11.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_3;
	}
#endif
#if MVK_XCODE_13
	if ( mvkOSVersionIsAtLeast(12.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion2_4;
	}
#endif
#if MVK_XCODE_14
	if ( mvkOSVersionIsAtLeast(13.0) ) {
		_metalFeatures.mslVersionEnum = MTLLanguageVersion3_0;
	}
#endif
#if MVK_XCODE_15
    if ( mvkOSVersionIsAtLeast(14.0) ) {
        _metalFeatures.mslVersionEnum = MTLLanguageVersion3_1;
    }
#endif

	// This is an Apple GPU--treat it accordingly.
	if (supportsMTLGPUFamily(Apple1)) {
		_metalFeatures.mtlCopyBufferAlignment = 1;
		_metalFeatures.mtlBufferAlignment = 16;     // Min float4 alignment for typical vertex buffers. MTLBuffer may go down to 4 bytes for other data.
		_metalFeatures.maxQueryBufferSize = (64 * KIBI);
		_metalFeatures.maxPerStageDynamicMTLBufferCount = _metalFeatures.maxPerStageBufferCount;
		_metalFeatures.postDepthCoverage = true;
		_metalFeatures.renderLinearTextures = true;
		_metalFeatures.tileBasedDeferredRendering = true;

#if MVK_XCODE_12
		if (supportsMTLGPUFamily(Apple6)) {
			_metalFeatures.astcHDRTextures = true;
		}
		if (supportsMTLGPUFamily(Apple7)) {
			_metalFeatures.maxQueryBufferSize = (256 * KIBI);
		}
#endif
	}

	// Don't use barriers in render passes on Apple GPUs. Apple GPUs don't support them,
	// and in fact Metal's validation layer will complain if you try to use them.
	if ( !supportsMTLGPUFamily(Apple1) ) {
		if (supportsMTLFeatureSet(macOS_GPUFamily1_v4)) {
			_metalFeatures.memoryBarriers = true;
		}
		_metalFeatures.textureBarriers = true;
	}

#endif

	if ( [_mtlDevice respondsToSelector: @selector(areProgrammableSamplePositionsSupported)] ) {
		_metalFeatures.programmableSamplePositions = _mtlDevice.areProgrammableSamplePositionsSupported;
	}

    if ( [_mtlDevice respondsToSelector: @selector(areRasterOrderGroupsSupported)] ) {
        _metalFeatures.rasterOrderGroups = _mtlDevice.areRasterOrderGroupsSupported;
    }
#if MVK_XCODE_12
	if ( [_mtlDevice respondsToSelector: @selector(supportsPullModelInterpolation)] ) {
		_metalFeatures.pullModelInterpolation = _mtlDevice.supportsPullModelInterpolation;
	}
#endif

#if (MVK_MACOS && !MVK_MACCAT) || (MVK_MACCAT && MVK_XCODE_14) || (MVK_IOS && MVK_XCODE_12)
	// Both current and deprecated properties are retrieved and OR'd together, due to a
	// Metal bug that, in some environments, returned true for one and false for the other.
	bool bcProp1 = false;
	bool bcProp2 = false;
	if ( [_mtlDevice respondsToSelector: @selector(supportsShaderBarycentricCoordinates)] ) {
		bcProp1 = _mtlDevice.supportsShaderBarycentricCoordinates;
	}
	if ( [_mtlDevice respondsToSelector: @selector(areBarycentricCoordsSupported)] ) {
		bcProp2 = _mtlDevice.areBarycentricCoordsSupported;
	}
	_metalFeatures.shaderBarycentricCoordinates = bcProp1 || bcProp2;
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
                    case kAMDRadeonRX5700DeviceId:
                    case kAMDRadeonRX5500DeviceId:
                    case kAMDRadeonRX6800DeviceId:
                    case kAMDRadeonRX6700DeviceId:
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
#if MVK_XCODE_15
        case MTLLanguageVersion3_1:
            setMSLVersion(3, 1);
            break;
#endif
#if MVK_XCODE_14
		case MTLLanguageVersion3_0:
			setMSLVersion(3, 0);
			break;
#endif
#if MVK_XCODE_13
		case MTLLanguageVersion2_4:
			setMSLVersion(2, 4);
			break;
#endif
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

// iOS and tvOS adjustments necessary when running on the simulator.
#if MVK_OS_SIMULATOR
	_metalFeatures.mtlBufferAlignment = 256;	// Even on Apple Silicon
#endif

	// Currently, Metal argument buffer support is in beta stage, and is only supported
	// on macOS 11.0 (Big Sur) or later, or on older versions of macOS using an Intel GPU.
	// Metal argument buffers support is not available on iOS. Development to support iOS
	// and a wider combination of GPU's on older macOS versions is under way.
#if MVK_MACOS
	_metalFeatures.descriptorSetArgumentBuffers = (_metalFeatures.argumentBuffers &&
												   (mvkOSVersionIsAtLeast(11.0) ||
													_properties.vendorID == kIntelVendorId));
#endif
	// Currently, if we don't support descriptor set argument buffers, we can't support argument buffers.
	_metalFeatures.argumentBuffers = _metalFeatures.descriptorSetArgumentBuffers;

	if ([_mtlDevice respondsToSelector: @selector(argumentBuffersSupport)]) {
		_metalFeatures.argumentBuffersTier = _mtlDevice.argumentBuffersSupport;
	}

#define checkSupportsMTLCounterSamplingPoint(mtlSP, mvkSP)  \
	if ([_mtlDevice respondsToSelector: @selector(supportsCounterSampling:)] &&  \
		[_mtlDevice supportsCounterSampling: MTLCounterSamplingPointAt ##mtlSP ##Boundary]) {  \
		_metalFeatures.counterSamplingPoints |= MVK_COUNTER_SAMPLING_AT_ ##mvkSP;  \
	}

#if MVK_XCODE_12
	checkSupportsMTLCounterSamplingPoint(Draw, DRAW);
	checkSupportsMTLCounterSamplingPoint(Dispatch, DISPATCH);
	checkSupportsMTLCounterSamplingPoint(Blit, BLIT);
	checkSupportsMTLCounterSamplingPoint(Stage, PIPELINE_STAGE);
#endif

#if MVK_MACOS
	// On macOS, if we couldn't query supported sample points (on macOS 11),
	// but the platform can support immediate-mode sample points, indicate that here.
	if (!_metalFeatures.counterSamplingPoints && mvkOSVersionIsAtLeast(10.15) && !supportsMTLGPUFamily(Apple1)) {  \
		_metalFeatures.counterSamplingPoints = MVK_COUNTER_SAMPLING_AT_DRAW | MVK_COUNTER_SAMPLING_AT_DISPATCH | MVK_COUNTER_SAMPLING_AT_BLIT;  \
	}
#endif

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
	_features.textureCompressionBC = mvkSupportsBCTextureCompression(_mtlDevice);

	_features.drawIndirectFirstInstance = _metalFeatures.indirectDrawing && _metalFeatures.baseVertexInstanceDrawing;

#if MVK_TVOS
    _features.textureCompressionETC2 = true;
    _features.textureCompressionASTC_LDR = true;
#if MVK_XCODE_12
	_features.shaderInt64 = mslVersionIsAtLeast(MTLLanguageVersion2_3) && supportsMTLGPUFamily(Apple3);
#else
	_features.shaderInt64 = false;
#endif

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
#if MVK_XCODE_12
	_features.shaderInt64 = mslVersionIsAtLeast(MTLLanguageVersion2_3) && supportsMTLGPUFamily(Apple3);
#else
	_features.shaderInt64 = false;
#endif

    if (supportsMTLFeatureSet(iOS_GPUFamily2_v1)) {
        _features.textureCompressionASTC_LDR = true;
    }

    if (supportsMTLFeatureSet(iOS_GPUFamily3_v1)) {
        _features.occlusionQueryPrecise = true;
    }

	if (supportsMTLFeatureSet(iOS_GPUFamily1_v4)) {
		_features.dualSrcBlend = true;
	}

#if MVK_OS_SIMULATOR
	_features.depthClamp = false;
#else
	if (supportsMTLFeatureSet(iOS_GPUFamily2_v4)) {
		_features.depthClamp = true;
	}
#endif

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
    _features.occlusionQueryPrecise = true;
    _features.imageCubeArray = true;
    _features.depthClamp = true;
    _features.vertexPipelineStoresAndAtomics = true;
    _features.fragmentStoresAndAtomics = true;
#if MVK_XCODE_12
	_features.shaderInt64 = mslVersionIsAtLeast(MTLLanguageVersion2_3);
#else
	_features.shaderInt64 = false;
#endif

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
#endif

	// Additional non-extension Vulkan 1.2 features.
	mvkClear(&_vulkan12FeaturesNoExt);		// Start with everything cleared
	_vulkan12FeaturesNoExt.samplerMirrorClampToEdge = _metalFeatures.samplerMirrorClampToEdge;
	_vulkan12FeaturesNoExt.drawIndirectCount = false;
	_vulkan12FeaturesNoExt.descriptorIndexing = true;
	_vulkan12FeaturesNoExt.samplerFilterMinmax = false;
	_vulkan12FeaturesNoExt.shaderOutputViewportIndex = _features.multiViewport;
	_vulkan12FeaturesNoExt.shaderOutputLayer = _metalFeatures.layeredRendering;
	_vulkan12FeaturesNoExt.subgroupBroadcastDynamicId = _metalFeatures.simdPermute || _metalFeatures.quadPermute;

}

// Initializes the physical device property limits.
void MVKPhysicalDevice::initLimits() {

#if MVK_TVOS
    _properties.limits.maxColorAttachments = kMVKMaxColorAttachmentCount;
#endif
#if MVK_IOS
    if (supportsMTLFeatureSet(iOS_GPUFamily2_v1)) {
        _properties.limits.maxColorAttachments = kMVKMaxColorAttachmentCount;
    } else {
        _properties.limits.maxColorAttachments = 4;		// < kMVKMaxColorAttachmentCount
    }
#endif
#if MVK_MACOS
    _properties.limits.maxColorAttachments = kMVKMaxColorAttachmentCount;
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
    _properties.limits.maxViewports = _features.multiViewport ? kMVKMaxViewportScissorCount : 1;

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

	_properties.limits.maxClipDistances = 8;	// Per Apple engineers.
	_properties.limits.maxCullDistances = 0;	// unsupported
	_properties.limits.maxCombinedClipAndCullDistances = max(_properties.limits.maxClipDistances,
															 _properties.limits.maxCullDistances);  // If supported, these consume the same slots.

	// Whether handled as a real texture buffer or a 2D texture, this value is likely nowhere near the size of a buffer,
	// needs to fit in 32 bits, and some apps (I'm looking at you, CTS), assume it is low when doing 32-bit math.
	_properties.limits.maxTexelBufferElements = _properties.limits.maxImageDimension2D * (4 * KIBI);
#if MVK_MACOS
	_properties.limits.maxUniformBufferRange = (64 * KIBI);
	if (supportsMTLGPUFamily(Apple5)) {
		_properties.limits.maxUniformBufferRange = (uint32_t)min(_metalFeatures.maxMTLBufferSize, (VkDeviceSize)std::numeric_limits<uint32_t>::max());
	}
#endif
#if MVK_IOS_OR_TVOS
	_properties.limits.maxUniformBufferRange = (uint32_t)min(_metalFeatures.maxMTLBufferSize, (VkDeviceSize)std::numeric_limits<uint32_t>::max());
#endif
	_properties.limits.maxStorageBufferRange = (uint32_t)min(_metalFeatures.maxMTLBufferSize, (VkDeviceSize)std::numeric_limits<uint32_t>::max());
	_properties.limits.maxPushConstantsSize = (4 * KIBI);

    _properties.limits.minMemoryMapAlignment = max(_metalFeatures.mtlBufferAlignment, (VkDeviceSize)64);	// Vulkan spec requires MIN of 64
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
                maxUniform = max(maxUniform, uint32_t(alignment));
                if (alignment > texelSize) { singleTexelUniform = false; }
            }
            if (mvkAreAllFlagsEnabled(props.bufferFeatures, VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT)) {
                maxStorage = max(maxStorage, uint32_t(alignment));
                if (alignment > texelSize) { singleTexelStorage = false; }
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
	_properties.limits.timestampPeriod = mvkGetTimestampPeriod();	// Will be 1.0 on Apple Silicon

    _properties.limits.pointSizeRange[0] = 1;
	switch (_properties.vendorID) {
		case kAppleVendorId:
			_properties.limits.pointSizeRange[1] = 511;
			break;
		case kIntelVendorId:
			_properties.limits.pointSizeRange[1] = 256;
			break;
		case kAMDVendorId:
		case kNVVendorId:
		default:
			_properties.limits.pointSizeRange[1] = 64;
			break;
	}

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

	// Max sum of API and shader values. Bias not supported in API, but can be applied in shader directly.
	// The lack of API value is covered by VkPhysicalDevicePortabilitySubsetFeaturesKHR::samplerMipLodBias.
	// Metal does not specify limit for shader value, so choose something reasonable.
	_properties.limits.maxSamplerLodBias = 4;

    _properties.limits.minTexelOffset = -8;
    _properties.limits.maxTexelOffset = 7;
    _properties.limits.minTexelGatherOffset = _properties.limits.minTexelOffset;
    _properties.limits.maxTexelGatherOffset = _properties.limits.maxTexelOffset;


    // Features with no specific limits - default to effectively unlimited int values

    _properties.limits.maxMemoryAllocationCount = kMVKUndefinedLargeUInt32;
	_properties.limits.maxSamplerAllocationCount = getMaxSamplerCount();
    _properties.limits.maxBoundDescriptorSets = kMVKMaxDescriptorSetCount;

    _properties.limits.maxComputeWorkGroupCount[0] = kMVKUndefinedLargeUInt32;
    _properties.limits.maxComputeWorkGroupCount[1] = kMVKUndefinedLargeUInt32;
    _properties.limits.maxComputeWorkGroupCount[2] = kMVKUndefinedLargeUInt32;

    _properties.limits.maxDrawIndexedIndexValue = numeric_limits<uint32_t>::max() - 1;	// Support both fullDrawIndexUint32 and automatic primitive restart.
    _properties.limits.maxDrawIndirectCount = kMVKUndefinedLargeUInt32;


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

	bool isIntegrated = getHasUnifiedMemory();
	_properties.deviceType = isIntegrated ? VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU : VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU;
	strlcpy(_properties.deviceName, _mtlDevice.name.UTF8String, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE);

	// For Apple Silicon, the Device ID is determined by the highest
	// GPU capability, which is a combination of OS version and GPU type.
	// We determine Apple Silicon directly from the GPU, instead
	// of from the build, in case we are running Rosetta2.
	if (supportsMTLGPUFamily(Apple1)) {
		_properties.vendorID = kAppleVendorId;
		_properties.deviceID = getHighestGPUCapability();
		return;
	}

	// If the device has an associated registry ID, we can use that to get the associated IOKit node.
	// The match dictionary is consumed by IOServiceGetMatchingServices and does not need to be released.
	bool isFound = false;
	io_registry_entry_t entry;
	uint64_t regID = mvkGetRegistryID(_mtlDevice);
	if (regID) {
		entry = IOServiceGetMatchingService(MACH_PORT_NULL, IORegistryEntryIDMatching(regID));
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
	if (!isFound && IOServiceGetMatchingServices(MACH_PORT_NULL,
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

#if MVK_IOS_OR_TVOS
// For Apple Silicon, the Device ID is determined by the highest
// GPU capability, which is a combination of OS version and GPU type.
void MVKPhysicalDevice::initGPUInfoProperties() {
	_properties.vendorID = kAppleVendorId;
	_properties.deviceID = getHighestGPUCapability();
	_properties.deviceType = VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
	strlcpy(_properties.deviceName, _mtlDevice.name.UTF8String, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE);
}
#endif	//MVK_IOS_OR_TVOS

// Since this is a uint8_t array, use Big-Endian byte ordering,
// so a hex dump of the array is human readable in its parts.
void MVKPhysicalDevice::initPipelineCacheUUID() {

	// Clear the UUID
	mvkClear(&_properties.pipelineCacheUUID, VK_UUID_SIZE);

	size_t uuidComponentOffset = 0;

	// First 4 bytes contains MoltenVK revision.
	// This is captured either as the MoltenVK Git revision, or if that's not available, as the MoltenVK version.
	uint32_t mvkRev = getMoltenVKGitRevision();
	if ( !mvkRev ) { mvkRev = MVK_VERSION; }
	*(uint32_t*)&_properties.pipelineCacheUUID[uuidComponentOffset] = NSSwapHostIntToBig(mvkRev);
	uuidComponentOffset += sizeof(mvkRev);

	// Next 4 bytes contains highest GPU capability supported by this device
	uint32_t gpuCap = getHighestGPUCapability();
	*(uint32_t*)&_properties.pipelineCacheUUID[uuidComponentOffset] = NSSwapHostIntToBig(gpuCap);
	uuidComponentOffset += sizeof(gpuCap);

	// Next 4 bytes contains flags based on enabled Metal features that
	// might affect the contents of the pipeline cache (mostly MSL content).
	uint32_t mtlFeatures = 0;
	mtlFeatures |= supportsMetalArgumentBuffers() << 0;
	*(uint32_t*)&_properties.pipelineCacheUUID[uuidComponentOffset] = NSSwapHostIntToBig(mtlFeatures);
	uuidComponentOffset += sizeof(mtlFeatures);
}

uint32_t MVKPhysicalDevice::getHighestGPUCapability() {

	// On newer OS's, combine OS version with highest GPU family.
	// On macOS, Apple GPU fam takes precedence over others.
	MTLGPUFamily gpuFam = MTLGPUFamily(0);
	if (supportsMTLGPUFamily(Mac1)) { gpuFam = MTLGPUFamilyMac1; }
	if (supportsMTLGPUFamily(Mac2)) { gpuFam = MTLGPUFamilyMac2; }

	if (supportsMTLGPUFamily(Apple1)) { gpuFam = MTLGPUFamilyApple1; }
	if (supportsMTLGPUFamily(Apple2)) { gpuFam = MTLGPUFamilyApple2; }
	if (supportsMTLGPUFamily(Apple3)) { gpuFam = MTLGPUFamilyApple3; }
	if (supportsMTLGPUFamily(Apple4)) { gpuFam = MTLGPUFamilyApple4; }
	if (supportsMTLGPUFamily(Apple5)) { gpuFam = MTLGPUFamilyApple5; }
#if MVK_IOS || (MVK_MACOS && MVK_XCODE_12)
	if (supportsMTLGPUFamily(Apple6)) { gpuFam = MTLGPUFamilyApple6; }
#endif
#if (MVK_IOS || MVK_MACOS) && MVK_XCODE_12
	if (supportsMTLGPUFamily(Apple7)) { gpuFam = MTLGPUFamilyApple7; }
#endif
#if MVK_XCODE_14 || (MVK_IOS && MVK_XCODE_13)
	if (supportsMTLGPUFamily(Apple8)) { gpuFam = MTLGPUFamilyApple8; }
#endif

	// Combine OS major (8 bits), OS minor (8 bits), and GPU family (16 bits)
	// into one 32-bit value summarizing highest GPU capability.
	if (gpuFam) {
		float fosMaj, fosMin;
		fosMin = modf(mvkOSVersion(), &fosMaj);
		uint8_t osMaj = (uint8_t)fosMaj;
		uint8_t osMin = (uint8_t)(fosMin * 100);
		return (osMaj << 24) + (osMin << 16) + (uint16_t)gpuFam;
	}

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
uint32_t MVKPhysicalDevice::getMoltenVKGitRevision() {

#include "mvkGitRevDerived.h"

	static const string revStr(mvkRevString, 0, 8);		// We just need the first 8 chars
	static const string lut("0123456789ABCDEF");

	uint32_t revVal = 0;
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
#if MVK_MACOS
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

// When using argument buffers, Metal imposes a hard limit on the number of MTLSamplerState
// objects that can be created within the app. When not using argument buffers, no such
// limit is imposed. This has been verified with testing up to 1M MTLSamplerStates.
uint32_t MVKPhysicalDevice::getMaxSamplerCount() {
	if (supportsMetalArgumentBuffers()) {
		return ([_mtlDevice respondsToSelector: @selector(maxArgumentBufferSamplerCount)]
				? (uint32_t)_mtlDevice.maxArgumentBufferSamplerCount : 1024);
	} else {
		return kMVKUndefinedLargeUInt32;
	}
}

void MVKPhysicalDevice::initExternalMemoryProperties() {

	// Common
	_hostPointerExternalMemoryProperties.externalMemoryFeatures = VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT;
	_hostPointerExternalMemoryProperties.exportFromImportedHandleTypes = 0;
	_hostPointerExternalMemoryProperties.compatibleHandleTypes = (VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT |
																  VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_MAPPED_FOREIGN_MEMORY_BIT_EXT);

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

	if (!_metalFeatures.samplerMirrorClampToEdge) {
		pWritableExtns->vk_KHR_sampler_mirror_clamp_to_edge.enabled = false;
	}
	if (!_metalFeatures.programmableSamplePositions) {
		pWritableExtns->vk_EXT_sample_locations.enabled = false;
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
		pWritableExtns->vk_EXT_shader_subgroup_ballot.enabled = false;
		pWritableExtns->vk_EXT_shader_subgroup_vote.enabled = false;
	}
	if (!_metalFeatures.shaderBarycentricCoordinates) {
		pWritableExtns->vk_KHR_fragment_shader_barycentric.enabled = false;
		pWritableExtns->vk_NV_fragment_shader_barycentric.enabled = false;
	}
    
    // The relevant functions are not available if not built with Xcode 14.
#if MVK_XCODE_14
    // gpuAddress requires Tier2 argument buffer support (per feedback from Apple engineers).
    if (_metalFeatures.argumentBuffersTier < MTLArgumentBuffersTier2) {
		pWritableExtns->vk_KHR_buffer_device_address.enabled = false;
		pWritableExtns->vk_EXT_buffer_device_address.enabled = false;
	}
#else
    pWritableExtns->vk_KHR_buffer_device_address.enabled = false;
    pWritableExtns->vk_EXT_buffer_device_address.enabled = false;
#endif

#if MVK_MACOS
	if (!supportsMTLGPUFamily(Apple5)) {
		pWritableExtns->vk_AMD_shader_image_load_store_lod.enabled = false;
		pWritableExtns->vk_IMG_format_pvrtc.enabled = false;
	}
#endif
}

void MVKPhysicalDevice::initCounterSets() {
	_timestampMTLCounterSet = nil;
	@autoreleasepool {
		if (_metalFeatures.counterSamplingPoints) {
			NSArray<id<MTLCounterSet>>* counterSets = _mtlDevice.counterSets;

			if (needsCounterSetRetained()) { [counterSets retain]; }

			for (id<MTLCounterSet> cs in counterSets){
				NSString* csName = cs.name;
				if ( [csName caseInsensitiveCompare: MTLCommonCounterSetTimestamp] == NSOrderedSame) {
					NSArray<id<MTLCounter>>* countersInSet = cs.counters;
					for(id<MTLCounter> ctr in countersInSet) {
						if ( [ctr.name caseInsensitiveCompare: MTLCommonCounterTimestamp] == NSOrderedSame) {
							_timestampMTLCounterSet = [cs retain];		// retained
							break;
						}
					}
					break;
				}
			}
		}
	}
}

// Determine whether Vulkan semaphores should use a MTLEvent, CPU callbacks, or should limit
// Vulkan to a single queue and use Metal's implicit guarantees that all operations submitted
// to a queue will give the same result as if they had been run in submission order.
// MTLEvents for semaphores are preferred, but can sometimes prove troublesome on some platforms,
// and so may be disabled on those platforms, unless explicitly requested. If MTLEvents are
// unusable, 
void MVKPhysicalDevice::initVkSemaphoreStyle() {

	// Default to single queue if other options unavailable.
	_vkSemaphoreStyle = MVKSemaphoreStyleSingleQueue;

	switch (mvkConfig().semaphoreSupportStyle) {
		case MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_METAL_EVENTS_WHERE_SAFE: {
			bool isNVIDIA = _properties.vendorID == kNVVendorId;
			bool isRosetta2 = _properties.vendorID == kAppleVendorId && !MVK_APPLE_SILICON;
			if (_metalFeatures.events && !(isRosetta2 || isNVIDIA)) { _vkSemaphoreStyle = MVKSemaphoreStyleUseMTLEvent; }
			break;
		}
		case MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_METAL_EVENTS:
			if (_metalFeatures.events) { _vkSemaphoreStyle = MVKSemaphoreStyleUseMTLEvent; }
			break;
		case MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_CALLBACK:
			_vkSemaphoreStyle = MVKSemaphoreStyleUseEmulation;
			break;
		case MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_SINGLE_QUEUE:
		default:
			break;
	}
}

// Workaround for a bug in Intel Iris Plus Graphics driver where the counterSets array is
// not properly retained internally, and becomes a zombie when counterSets is called more
// than once, which occurs when an app creates more than one VkInstance. This workaround
// will cause a very small memory leak on systems that do not have this bug, so we apply
// the workaround only when absolutely needed for specific devices. The list of deviceIDs
// is sourced from the list of Intel Iris Plus Graphics Gen11 tier G7 devices found here:
// https://en.wikipedia.org/wiki/List_of_Intel_graphics_processing_units#Gen11
bool MVKPhysicalDevice::needsCounterSetRetained() {

	if (_properties.vendorID != kIntelVendorId) { return false; }

	switch (_properties.deviceID) {
		case 0x8a51:
		case 0x8a52:
		case 0x8a53:
		case 0x8a5a:
		case 0x8a5c:
			return true;
		default:
			return false;
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
	logMsg += "\n\tsupports the following Metal Versions, GPU's and Feature Sets:";
	logMsg += "\n\t\tMetal Shading Language %s";

#if MVK_XCODE_14 || (MVK_IOS && MVK_XCODE_13)
	if (supportsMTLGPUFamily(Apple8)) { logMsg += "\n\t\tGPU Family Apple 8"; }
#endif
#if (MVK_IOS || MVK_MACOS) && MVK_XCODE_12
	if (supportsMTLGPUFamily(Apple7)) { logMsg += "\n\t\tGPU Family Apple 7"; }
#endif
#if MVK_IOS || (MVK_MACOS && MVK_XCODE_12)
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
	[_timestampMTLCounterSet release];
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
			if ((rslt = q->waitIdle(kMVKCommandUseDeviceWaitIdle)) != VK_SUCCESS) { return rslt; }
		}
	}
	return VK_SUCCESS;
}

VkResult MVKDevice::markLost(bool alsoMarkPhysicalDevice) {
	lock_guard<mutex> lock(_sem4Lock);

	setConfigurationResult(VK_ERROR_DEVICE_LOST);
	if (alsoMarkPhysicalDevice) { _physicalDevice->setConfigurationResult(VK_ERROR_DEVICE_LOST); }

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

	return getConfigurationResult();
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
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_LAYOUT_SUPPORT: {
				auto* pVarDescSetCountSupport = (VkDescriptorSetVariableDescriptorCountLayoutSupport*)next;
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
																  VkDescriptorSetVariableDescriptorCountLayoutSupport* pVarDescSetCountSupport) {
	// Assume we don't need this, then set appropriately if we do.
	pVarDescSetCountSupport->maxVariableDescriptorCount = 0;

	// Look for a variable length descriptor and remember its index.
	int32_t varBindingIdx = -1;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO: {
				auto* pDescSetLayoutBindingFlags = (VkDescriptorSetLayoutBindingFlagsCreateInfo*)next;
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
	mvkClear(pDeviceGroupPresentCapabilities->presentMask, VK_MAX_DEVICE_GROUP_SIZE);
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

VkResult MVKDevice::getMemoryHostPointerProperties(VkExternalMemoryHandleTypeFlagBits handleType,
												   const void* pHostPointer,
												   VkMemoryHostPointerPropertiesEXT* pMemHostPtrProps) {
	if (pMemHostPtrProps) {
		switch (handleType) {
			case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT:
			case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_MAPPED_FOREIGN_MEMORY_BIT_EXT:
				pMemHostPtrProps->memoryTypeBits = _physicalDevice->getHostVisibleMemoryTypes();
				break;
			default:
				pMemHostPtrProps->memoryTypeBits = 0;
				break;
		}
	}
	return VK_SUCCESS;
}

void MVKDevice::getCalibratedTimestamps(uint32_t timestampCount,
										const VkCalibratedTimestampInfoEXT* pTimestampInfos,
										uint64_t* pTimestamps,
										uint64_t* pMaxDeviation) {
	MTLTimestamp cpuStamp, gpuStamp;
	uint64_t cpuStart, cpuEnd;

	cpuStart = mvkGetAbsoluteTime();
	[getMTLDevice() sampleTimestamps: &cpuStamp gpuTimestamp: &gpuStamp];
	// Sample again to calculate the maximum deviation. Note that the
	// -[MTLDevice sampleTimestamps:gpuTimestamp:] method guarantees that CPU
	// timestamps are in nanoseconds. We don't want to call the method again,
	// because that could result in an expensive syscall to query the GPU time-
	// stamp.
	cpuEnd = mvkGetAbsoluteTime();
	for (uint32_t tsIdx = 0; tsIdx < timestampCount; ++tsIdx) {
		switch (pTimestampInfos[tsIdx].timeDomain) {
			case VK_TIME_DOMAIN_DEVICE_EXT:
				pTimestamps[tsIdx] = gpuStamp;
				break;
			// XXX Should be VK_TIME_DOMAIN_CLOCK_UPTIME_RAW_EXT
			case VK_TIME_DOMAIN_CLOCK_MONOTONIC_RAW_EXT:
				pTimestamps[tsIdx] = cpuStart;
				break;
			default:
				continue;
		}
	}
	*pMaxDeviation = cpuEnd - cpuStart;
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
#if MVK_APPLE_SILICON
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
    return addBuffer(new MVKBuffer(this, pCreateInfo));
}

void MVKDevice::destroyBuffer(MVKBuffer* mvkBuff,
							  const VkAllocationCallbacks* pAllocator) {
	if ( !mvkBuff ) { return; }
	removeBuffer(mvkBuff);
	mvkBuff->destroy();
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
	return addImage(mvkImg);
}

void MVKDevice::destroyImage(MVKImage* mvkImg,
							 const VkAllocationCallbacks* pAllocator) {
	if ( !mvkImg ) { return; }
	removeImage(mvkImg);
	mvkImg->destroy();
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
	auto* pImg = new MVKPresentableSwapchainImage(this, pCreateInfo, swapchain, swapchainIndex);
	addImage(pImg);
	return pImg;
}

void MVKDevice::destroyPresentableSwapchainImage(MVKPresentableSwapchainImage* mvkImg,
												 const VkAllocationCallbacks* pAllocator) {
	if ( !mvkImg ) { return; }
	removeImage(mvkImg);
	mvkImg->destroy();
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
	const VkExportMetalObjectCreateInfoEXT* pExportInfo = nullptr;
	const VkImportMetalSharedEventInfoEXT* pImportInfo = nullptr;
	for (auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO:
				pTypeCreateInfo = (VkSemaphoreTypeCreateInfo*)next;
				break;
			case VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT:
				pExportInfo = (VkExportMetalObjectCreateInfoEXT*)next;
				break;
			case VK_STRUCTURE_TYPE_IMPORT_METAL_SHARED_EVENT_INFO_EXT:
				pImportInfo = (VkImportMetalSharedEventInfoEXT*)next;
				break;
			default:
				break;
		}
	}

	if (pTypeCreateInfo && pTypeCreateInfo->semaphoreType == VK_SEMAPHORE_TYPE_TIMELINE) {
		if (_pMetalFeatures->events) {
			return new MVKTimelineSemaphoreMTLEvent(this, pCreateInfo, pTypeCreateInfo, pExportInfo, pImportInfo);
		} else {
			return new MVKTimelineSemaphoreEmulated(this, pCreateInfo, pTypeCreateInfo, pExportInfo, pImportInfo);
		}
	} else {
		switch (_physicalDevice->_vkSemaphoreStyle) {
			case MVKSemaphoreStyleUseMTLEvent:  return new MVKSemaphoreMTLEvent(this, pCreateInfo, pExportInfo, pImportInfo);
			case MVKSemaphoreStyleUseEmulation: return new MVKSemaphoreEmulated(this, pCreateInfo, pExportInfo, pImportInfo);
			case MVKSemaphoreStyleSingleQueue:  return new MVKSemaphoreSingleQueue(this, pCreateInfo, pExportInfo, pImportInfo);
		}
	}
}

void MVKDevice::destroySemaphore(MVKSemaphore* mvkSem4,
								 const VkAllocationCallbacks* pAllocator) {
	if (mvkSem4) { mvkSem4->destroy(); }
}

MVKDeferredOperation* MVKDevice::createDeferredOperation(const VkAllocationCallbacks* pAllocator) {
    return new MVKDeferredOperation(this);
}

void MVKDevice::destroyDeferredOperation(MVKDeferredOperation* mvkDeferredOperation,
                                         const VkAllocationCallbacks* pAllocator) {
    if(mvkDeferredOperation) { mvkDeferredOperation->destroy(); }
}

MVKEvent* MVKDevice::createEvent(const VkEventCreateInfo* pCreateInfo,
								 const VkAllocationCallbacks* pAllocator) {
	const VkExportMetalObjectCreateInfoEXT* pExportInfo = nullptr;
	const VkImportMetalSharedEventInfoEXT* pImportInfo = nullptr;
	for (auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT:
				pExportInfo = (VkExportMetalObjectCreateInfoEXT*)next;
				break;
			case VK_STRUCTURE_TYPE_IMPORT_METAL_SHARED_EVENT_INFO_EXT:
				pImportInfo = (VkImportMetalSharedEventInfoEXT*)next;
				break;
			default:
				break;
		}
	}

	if (_pMetalFeatures->events) {
		return new MVKEventNative(this, pCreateInfo, pExportInfo, pImportInfo);
	} else {
		return new MVKEventEmulated(this, pCreateInfo, pExportInfo, pImportInfo);
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
	bool ignoreFurtherPipelines = false;
    VkResult rslt = VK_SUCCESS;
    MVKPipelineCache* mvkPLC = (MVKPipelineCache*)pipelineCache;

    for (uint32_t plIdx = 0; plIdx < count; plIdx++) {

		// Ensure all slots are purposefully set.
		pPipelines[plIdx] = VK_NULL_HANDLE;
		if (ignoreFurtherPipelines) { continue; }

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

        // Create the pipeline and if creation was successful, insert the new pipeline in the return array.
        MVKPipeline* mvkPL = new PipelineType(this, mvkPLC, parentPL, pCreateInfo);
        VkResult plRslt = mvkPL->getConfigurationResult();
        if (plRslt == VK_SUCCESS) {
            pPipelines[plIdx] = (VkPipeline)mvkPL;
        } else {
			// If creation was unsuccessful, destroy the broken pipeline, change the result
			// code of this function, and if the VK_PIPELINE_CREATE_EARLY_RETURN_ON_FAILURE_BIT
			// flag is set, don't build any further pipelines.
			mvkPL->destroy();
			if (rslt == VK_SUCCESS) { rslt = plRslt; }
			ignoreFurtherPipelines = (_enabledPipelineCreationCacheControlFeatures.pipelineCreationCacheControl &&
									  mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_PIPELINE_CREATE_EARLY_RETURN_ON_FAILURE_BIT));
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
	const VkDescriptorUpdateTemplateCreateInfo* pCreateInfo,
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

MVKFramebuffer* MVKDevice::createFramebuffer(const VkRenderingInfo* pRenderingInfo,
											 const VkAllocationCallbacks* pAllocator) {
	return new MVKFramebuffer(this, pRenderingInfo);
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

MVKRenderPass* MVKDevice::createRenderPass(const VkRenderingInfo* pRenderingInfo,
										   const VkAllocationCallbacks* pAllocator) {
	return new MVKRenderPass(this, pRenderingInfo);
}

void MVKDevice::destroyRenderPass(MVKRenderPass* mvkRP,
								  const VkAllocationCallbacks* pAllocator) {
	if (mvkRP) { mvkRP->destroy(); }
}

MVKCommandPool* MVKDevice::createCommandPool(const VkCommandPoolCreateInfo* pCreateInfo,
											const VkAllocationCallbacks* pAllocator) {
	return new MVKCommandPool(this, pCreateInfo, mvkConfig().useCommandPooling);
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

// Look for an available pre-reserved private data slot and return its address if found.
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

// If the underlying MTLBuffer is referenced in a shader only via its gpuAddress,
// the GPU might not be aware that the MTLBuffer needs to be made resident.
// Track the buffer as needing to be made resident if a shader is bound that uses
// PhysicalStorageBufferAddresses to access the contents of the underlying MTLBuffer.
MVKBuffer* MVKDevice::addBuffer(MVKBuffer* mvkBuff) {
	if ( !mvkBuff ) { return mvkBuff; }

	lock_guard<mutex> lock(_rezLock);
	_resources.push_back(mvkBuff);
	if (mvkIsAnyFlagEnabled(mvkBuff->getUsage(), VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT)) {
		_gpuAddressableBuffers.push_back(mvkBuff);
	}
	return mvkBuff;
}

MVKBuffer* MVKDevice::removeBuffer(MVKBuffer* mvkBuff) {
	if ( !mvkBuff ) { return mvkBuff; }

	lock_guard<mutex> lock(_rezLock);
	mvkRemoveFirstOccurance(_resources, mvkBuff);
	if (mvkIsAnyFlagEnabled(mvkBuff->getUsage(), VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT)) {
		mvkRemoveFirstOccurance(_gpuAddressableBuffers, mvkBuff);
	}
	return mvkBuff;
}

void MVKDevice::encodeGPUAddressableBuffers(MVKResourcesCommandEncoderState* rezEncState, MVKShaderStage stage) {
	MTLResourceUsage mtlUsage = MTLResourceUsageRead | MTLResourceUsageWrite;
	MTLRenderStages mtlRendStage = (stage == kMVKShaderStageFragment) ? MTLRenderStageFragment : MTLRenderStageVertex;

	lock_guard<mutex> lock(_rezLock);
	for (auto& buff : _gpuAddressableBuffers) {
		rezEncState->encodeResourceUsage(stage, buff->getMTLBuffer(), mtlUsage, mtlRendStage);
	}
}

MVKImage* MVKDevice::addImage(MVKImage* mvkImg) {
	if ( !mvkImg ) { return mvkImg; }

	lock_guard<mutex> lock(_rezLock);
	for (auto& mb : mvkImg->_memoryBindings) {
		_resources.push_back(mb);
	}
	return mvkImg;
}

MVKImage* MVKDevice::removeImage(MVKImage* mvkImg) {
	if ( !mvkImg ) { return mvkImg; }

	lock_guard<mutex> lock(_rezLock);
	for (auto& mb : mvkImg->_memoryBindings) {
		mvkRemoveFirstOccurance(_resources, mb);
	}
	return mvkImg;
}

void MVKDevice::addSemaphore(MVKSemaphoreImpl* sem4) {
	lock_guard<mutex> lock(_sem4Lock);
	_awaitingSemaphores.push_back(sem4);
}

void MVKDevice::removeSemaphore(MVKSemaphoreImpl* sem4) {
	lock_guard<mutex> lock(_sem4Lock);
	mvkRemoveFirstOccurance(_awaitingSemaphores, sem4);
}

void MVKDevice::addTimelineSemaphore(MVKTimelineSemaphore* sem4, uint64_t value) {
	lock_guard<mutex> lock(_sem4Lock);
	_awaitingTimelineSem4s.emplace_back(sem4, value);
}

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
	logActivityPerformance(perfStats.shaderCompilation.mslCompress, perfStats);
	logActivityPerformance(perfStats.shaderCompilation.mslDecompress, perfStats);
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
	if (&activity == &perfStats.shaderCompilation.mslCompress) { return "Compress MSL source code after compiling a MTLLibrary"; }
	if (&activity == &perfStats.shaderCompilation.mslDecompress) { return "Decompress MSL source code during pipeline cache write"; }
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
			VkResult r = mvkMem->pullFromDevice(pMem->offset, pMem->size, &mvkBlitEnc);
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

uint32_t MVKDevice::getMultiviewMetalPassCount(uint32_t viewMask) const {
	if ( !viewMask ) { return 0; }
	if ( !_physicalDevice->canUseInstancingForMultiview() ) {
		// If we can't use instanced drawing for this, we'll have to unroll the render pass.
		return __builtin_popcount(viewMask);
	}
	uint32_t mask = viewMask;
	uint32_t count;
	// Step through each clump until there are no more clumps. I'll know this has
	// happened when the mask becomes 0, since mvkGetNextViewMaskGroup() clears each group of bits
	// as it finds them, and returns the remainder of the mask.
	for (count = 0; mask != 0; ++count) {
		mask = mvkGetNextViewMaskGroup(mask, nullptr, nullptr);
	}
	return count;
}

uint32_t MVKDevice::getFirstViewIndexInMetalPass(uint32_t viewMask, uint32_t passIdx) const {
	if ( !viewMask ) { return 0; }
	assert(passIdx < getMultiviewMetalPassCount(viewMask));
	uint32_t mask = viewMask;
	uint32_t startView = 0, viewCount = 0;
	if ( !_physicalDevice->canUseInstancingForMultiview() ) {
		for (uint32_t i = 0; mask != 0; ++i) {
			mask = mvkGetNextViewMaskGroup(mask, &startView, &viewCount);
			while (passIdx-- > 0 && viewCount-- > 0) {
				startView++;
			}
		}
	} else {
		for (uint32_t i = 0; i <= passIdx; ++i) {
			mask = mvkGetNextViewMaskGroup(mask, &startView, nullptr);
		}
	}
	return startView;
}

uint32_t MVKDevice::getViewCountInMetalPass(uint32_t viewMask, uint32_t passIdx) const {
	if ( !viewMask ) { return 0; }
	assert(passIdx < getMultiviewMetalPassCount(viewMask));
	if ( !_physicalDevice->canUseInstancingForMultiview() ) {
		return 1;
	}
	uint32_t mask = viewMask;
	uint32_t viewCount = 0;
	for (uint32_t i = 0; i <= passIdx; ++i) {
		mask = mvkGetNextViewMaskGroup(mask, nullptr, &viewCount);
	}
	return viewCount;
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
				mtlSampDesc.supportArgumentBuffers = isUsingMetalArgumentBuffers();
				_defaultMTLSamplerState = [getMTLDevice() newSamplerStateWithDescriptor: mtlSampDesc];	// retained
			}
		}
	}
	return _defaultMTLSamplerState;
}

id<MTLBuffer> MVKDevice::getDummyBlitMTLBuffer() {
	if ( !_dummyBlitMTLBuffer ) {

		// Lock and check again in case another thread has created the buffer.
		lock_guard<mutex> lock(_rezLock);
		if ( !_dummyBlitMTLBuffer ) {
			@autoreleasepool {
				_dummyBlitMTLBuffer = [getMTLDevice() newBufferWithLength: 1 options: MTLResourceStorageModePrivate];
			}
		}
	}
	return _dummyBlitMTLBuffer;
}

MTLCompileOptions* MVKDevice::getMTLCompileOptions(bool requestFastMath, bool preserveInvariance) {
	MTLCompileOptions* mtlCompOpt = [MTLCompileOptions new];
	mtlCompOpt.languageVersion = _pMetalFeatures->mslVersionEnum;
	mtlCompOpt.fastMathEnabled = (mvkConfig().fastMathEnabled == MVK_CONFIG_FAST_MATH_ALWAYS ||
								  (mvkConfig().fastMathEnabled == MVK_CONFIG_FAST_MATH_ON_DEMAND && requestFastMath));
#if MVK_XCODE_12
	if ([mtlCompOpt respondsToSelector: @selector(setPreserveInvariance:)]) {
		[mtlCompOpt setPreserveInvariance: preserveInvariance];
	}
#endif
	return [mtlCompOpt autorelease];
}

// Can't use prefilled Metal command buffers if any of the resource descriptors can be updated after binding.
bool MVKDevice::shouldPrefillMTLCommandBuffers() {
	return (mvkConfig().prefillMetalCommandBuffers &&
			!(_enabledDescriptorIndexingFeatures.descriptorBindingUniformBufferUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingSampledImageUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingStorageImageUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingStorageBufferUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingUniformTexelBufferUpdateAfterBind ||
			  _enabledDescriptorIndexingFeatures.descriptorBindingStorageTexelBufferUpdateAfterBind ||
			  _enabledInlineUniformBlockFeatures.descriptorBindingInlineUniformBlockUpdateAfterBind));
}

void MVKDevice::startAutoGPUCapture(MVKConfigAutoGPUCaptureScope autoGPUCaptureScope, id mtlCaptureObject) {

	if (_isCurrentlyAutoGPUCapturing || (mvkConfig().autoGPUCaptureScope != autoGPUCaptureScope)) { return; }

	_isCurrentlyAutoGPUCapturing = true;

	@autoreleasepool {
		MTLCaptureManager *captureMgr = [MTLCaptureManager sharedCaptureManager];

		// Before macOS 10.15 and iOS 13.0, captureDesc will just be nil
		MTLCaptureDescriptor *captureDesc = [[MTLCaptureDescriptor new] autorelease];
		captureDesc.captureObject = mtlCaptureObject;
		captureDesc.destination = MTLCaptureDestinationDeveloperTools;

		const char* filePath = mvkConfig().autoGPUCaptureOutputFilepath;
		if (strlen(filePath)) {
			if ([captureMgr respondsToSelector: @selector(supportsDestination:)] &&
				[captureMgr supportsDestination: MTLCaptureDestinationGPUTraceDocument] ) {

				NSString* expandedFilePath = [[NSString stringWithUTF8String: filePath] stringByExpandingTildeInPath];
				MVKLogInfo("Capturing GPU trace to file %s.", expandedFilePath.UTF8String);

				captureDesc.destination = MTLCaptureDestinationGPUTraceDocument;
				captureDesc.outputURL = [NSURL fileURLWithPath: expandedFilePath];

			} else {
				reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Capturing GPU traces to a file requires macOS 10.15 or iOS 13.0 and GPU capturing to be enabled. Falling back to Xcode GPU capture.");
			}
		} else {
			MVKLogInfo("Capturing GPU trace to Xcode.");
		}

		// Suppress deprecation warnings for startCaptureWithXXX: on MacCatalyst.
#		pragma clang diagnostic push
#		pragma clang diagnostic ignored "-Wdeprecated-declarations"
		if ([captureMgr respondsToSelector: @selector(startCaptureWithDescriptor:error:)] ) {
			NSError *err = nil;
			if ( ![captureMgr startCaptureWithDescriptor: captureDesc error: &err] ) {
				reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to automatically start GPU capture session (Error code %li): %s", (long)err.code, err.localizedDescription.UTF8String);
			}
		} else if ([mtlCaptureObject conformsToProtocol:@protocol(MTLCommandQueue)]) {
			[captureMgr startCaptureWithCommandQueue: mtlCaptureObject];
		} else if ([mtlCaptureObject conformsToProtocol:@protocol(MTLDevice)]) {
			[captureMgr startCaptureWithDevice: mtlCaptureObject];
		}
#		pragma clang diagnostic pop
	}
}

void MVKDevice::stopAutoGPUCapture(MVKConfigAutoGPUCaptureScope autoGPUCaptureScope) {
	if (_isCurrentlyAutoGPUCapturing && mvkConfig().autoGPUCaptureScope == autoGPUCaptureScope) {
		[[MTLCaptureManager sharedCaptureManager] stopCapture];
		_isCurrentlyAutoGPUCapturing = false;
	}
}

void MVKDevice::getMetalObjects(VkExportMetalObjectsInfoEXT* pMetalObjectsInfo) {
	for (auto* next = (VkBaseOutStructure*)pMetalObjectsInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_EXPORT_METAL_DEVICE_INFO_EXT: {
				auto* pDvcInfo = (VkExportMetalDeviceInfoEXT*)next;
				pDvcInfo->mtlDevice = getMTLDevice();
				break;
			}
			case VK_STRUCTURE_TYPE_EXPORT_METAL_COMMAND_QUEUE_INFO_EXT: {
				auto* pQInfo = (VkExportMetalCommandQueueInfoEXT*)next;
				MVKQueue* mvkQ = MVKQueue::getMVKQueue(pQInfo->queue);
				pQInfo->mtlCommandQueue = mvkQ->getMTLCommandQueue();
				break;
			}
			case VK_STRUCTURE_TYPE_EXPORT_METAL_BUFFER_INFO_EXT: {
				auto* pBuffInfo = (VkExportMetalBufferInfoEXT*)next;
				auto* mvkDevMem = (MVKDeviceMemory*)pBuffInfo->memory;
				pBuffInfo->mtlBuffer = mvkDevMem->getMTLBuffer();
				break;
			}
			case VK_STRUCTURE_TYPE_EXPORT_METAL_TEXTURE_INFO_EXT: {
				auto* pImgInfo = (VkExportMetalTextureInfoEXT*)next;
				uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(pImgInfo->plane);
				auto* mvkImg = (MVKImage*)pImgInfo->image;
				auto* mvkImgView = (MVKImageView*)pImgInfo->imageView;
				auto* mvkBuffView = (MVKBufferView*)pImgInfo->bufferView;
				if (mvkImg) {
					pImgInfo->mtlTexture = mvkImg->getMTLTexture(planeIndex);
				} else if (mvkImgView) {
					pImgInfo->mtlTexture = mvkImgView->getMTLTexture(planeIndex);
				} else {
					pImgInfo->mtlTexture = mvkBuffView->getMTLTexture();
				}
				break;
			}
			case VK_STRUCTURE_TYPE_EXPORT_METAL_IO_SURFACE_INFO_EXT: {
				auto* pIOSurfInfo = (VkExportMetalIOSurfaceInfoEXT*)next;
				auto* mvkImg = (MVKImage*)pIOSurfInfo->image;
				pIOSurfInfo->ioSurface = mvkImg->getIOSurface();
				break;
			}
			case VK_STRUCTURE_TYPE_EXPORT_METAL_SHARED_EVENT_INFO_EXT: {
				auto* pShEvtInfo = (VkExportMetalSharedEventInfoEXT*)next;
				auto* mvkSem4 = (MVKSemaphore*)pShEvtInfo->semaphore;
				auto* mvkEvt = (MVKEvent*)pShEvtInfo->event;
				if (mvkSem4) {
					pShEvtInfo->mtlSharedEvent = mvkSem4->getMTLSharedEvent();
				} else if (mvkEvt) {
					pShEvtInfo->mtlSharedEvent = mvkEvt->getMTLSharedEvent();
				}
				break;
			}
			default:
				break;
		}
	}
}


#pragma mark Construction

MVKDevice::MVKDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo) : _enabledExtensions(this) {

	// If the physical device is lost, bail.
	// Must have initialized everything accessed in destructor to null.
	if (physicalDevice->getConfigurationResult() != VK_SUCCESS) {
		setConfigurationResult(physicalDevice->getConfigurationResult());
		return;
	}

	initPerformanceTracking();
	initPhysicalDevice(physicalDevice, pCreateInfo);
	enableExtensions(pCreateInfo);
	enableFeatures(pCreateInfo);
	initQueues(pCreateInfo);
	reservePrivateData(pCreateInfo);

#if MVK_MACOS
	// After enableExtensions
	// If the VK_KHR_swapchain extension is enabled, we expect to render to the screen.
	// In a multi-GPU system, if we are using the high-power GPU and want the window system
	// to also use that GPU to avoid copying content between GPUs, force the window system
	// to use the high-power GPU by calling the MTLCreateSystemDefaultDevice() function.
	if (_enabledExtensions.vk_KHR_swapchain.enabled && mvkConfig().switchSystemGPU &&
		!(_physicalDevice->_mtlDevice.isLowPower || _physicalDevice->_mtlDevice.isHeadless) ) {
			MTLCreateSystemDefaultDevice();
	}
#endif

	// After enableExtensions && enableFeatures
	// Use Metal arg buffs if available, and either config wants them always,
	// or config wants them with descriptor indexing and descriptor indexing has been enabled.
	_isUsingMetalArgumentBuffers = (_physicalDevice->supportsMetalArgumentBuffers() &&
									(mvkConfig().useMetalArgumentBuffers == MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS_ALWAYS ||
									 (mvkConfig().useMetalArgumentBuffers == MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS_DESCRIPTOR_INDEXING &&
									  (_enabledVulkan12FeaturesNoExt.descriptorIndexing || _enabledExtensions.vk_EXT_descriptor_indexing.enabled))));

	_commandResourceFactory = new MVKCommandResourceFactory(this);

	startAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_DEVICE, getMTLDevice());

	MVKLogInfo("Created VkDevice to run on GPU %s with the following %d Vulkan extensions enabled:%s",
			   _pProperties->deviceName,
			   _enabledExtensions.getEnabledCount(),
			   _enabledExtensions.enabledNamesString("\n\t\t", true).c_str());
}

void MVKDevice::initPerformanceTracking() {

	_isPerformanceTracking = mvkConfig().performanceTracking;
	_activityPerformanceLoggingStyle = mvkConfig().activityPerformanceLoggingStyle;

	_performanceStatistics.shaderCompilation.hashShaderCode = {};
    _performanceStatistics.shaderCompilation.spirvToMSL = {};
    _performanceStatistics.shaderCompilation.mslCompile = {};
    _performanceStatistics.shaderCompilation.mslLoad = {};
	_performanceStatistics.shaderCompilation.mslCompress = {};
	_performanceStatistics.shaderCompilation.mslDecompress = {};
	_performanceStatistics.shaderCompilation.shaderLibraryFromCache = {};
    _performanceStatistics.shaderCompilation.functionRetrieval = {};
    _performanceStatistics.shaderCompilation.functionSpecialization = {};
    _performanceStatistics.shaderCompilation.pipelineCompile = {};
	_performanceStatistics.pipelineCache.sizePipelineCache = {};
	_performanceStatistics.pipelineCache.writePipelineCache = {};
	_performanceStatistics.pipelineCache.readPipelineCache = {};
	_performanceStatistics.queue.mtlQueueAccess = {};
	_performanceStatistics.queue.mtlCommandBufferCompletion = {};
	_performanceStatistics.queue.nextCAMetalDrawable = {};
	_performanceStatistics.queue.frameInterval = {};
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

	_pMetalFeatures = _physicalDevice->getMetalFeatures();
	_pProperties = &_physicalDevice->_properties;
	_pMemoryProperties = &_physicalDevice->_memoryProperties;

	switch (_physicalDevice->_vkSemaphoreStyle) {
		case MVKSemaphoreStyleUseMTLEvent:
			MVKLogInfo("Vulkan semaphores using MTLEvent.");
			break;
		case MVKSemaphoreStyleUseEmulation:
			MVKLogInfo("Vulkan semaphores using CPU callbacks upon GPU submission completion.");
			break;
		case MVKSemaphoreStyleSingleQueue:
			MVKLogInfo("Vulkan semaphores using Metal implicit guarantees within a single queue.");
			break;
	}
}

void MVKDevice::enableFeatures(const VkDeviceCreateInfo* pCreateInfo) {
	VkStructureType sType;
	VkBaseInStructure* pPrevStruct = nullptr;

	// Clear and set the sType of each VkDevice enabled feature iVar (_enabledXXXFeatures),
	// and create a chain of identical structs that will be sent to the MVKPhysicalDevice
	// to query which features are supported.
#define MVK_DEVICE_FEATURE(structName, enumName, flagCount) \
	sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_##enumName##_FEATURES; \
	mvkClear(&_enabled##structName##Features); \
	_enabled##structName##Features.sType = sType; \
	VkPhysicalDevice##structName##Features pd##structName##Features; \
	pd##structName##Features.sType = sType; \
	pd##structName##Features.pNext = pPrevStruct; \
	pPrevStruct = (VkBaseInStructure*)&pd##structName##Features;

#define MVK_DEVICE_FEATURE_EXTN(structName, enumName, extnSfx, flagCount) \
	sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_##enumName##_FEATURES_##extnSfx; \
	mvkClear(&_enabled##structName##Features); \
	_enabled##structName##Features.sType = sType; \
	VkPhysicalDevice##structName##Features##extnSfx pd##structName##Features; \
	pd##structName##Features.sType = sType; \
	pd##structName##Features.pNext = pPrevStruct; \
	pPrevStruct = (VkBaseInStructure*)&pd##structName##Features;

#include "MVKDeviceFeatureStructs.def"

	mvkClear(&_enabledVulkan12FeaturesNoExt);

	sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
	mvkClear(&_enabledFeatures);
	VkPhysicalDeviceFeatures2 pdFeats2;
	pdFeats2.sType = sType;
	pdFeats2.pNext = pPrevStruct;

	_physicalDevice->getFeatures(&pdFeats2);

	//Enable device features based on requested and available features,
	// including extended features that are requested in the pNext chain.
	if (pCreateInfo->pEnabledFeatures) {
		enableFeatures(pCreateInfo->pEnabledFeatures,
					   &_enabledFeatures.robustBufferAccess,
					   &pCreateInfo->pEnabledFeatures->robustBufferAccess,
					   &pdFeats2.features.robustBufferAccess, 55);
	}

	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch ((uint32_t)next->sType) {
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2: {
				auto* requestedFeatures = (VkPhysicalDeviceFeatures2*)next;
				enableFeatures(requestedFeatures,
							   &_enabledFeatures.robustBufferAccess,
							   &requestedFeatures->features.robustBufferAccess,
							   &pdFeats2.features.robustBufferAccess, 55);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES: {
				auto* requestedFeatures = (VkPhysicalDeviceVulkan11Features*)next;
				enableFeatures(requestedFeatures,
							   &_enabled16BitStorageFeatures.storageBuffer16BitAccess,
							   &requestedFeatures->storageBuffer16BitAccess,
							   &pd16BitStorageFeatures.storageBuffer16BitAccess, 4);
				enableFeatures(requestedFeatures,
							   &_enabledMultiviewFeatures.multiview,
							   &requestedFeatures->multiview,
							   &pdMultiviewFeatures.multiview, 3);
				enableFeatures(requestedFeatures,
							   &_enabledVariablePointerFeatures.variablePointersStorageBuffer,
							   &requestedFeatures->variablePointersStorageBuffer,
							   &pdVariablePointerFeatures.variablePointersStorageBuffer, 2);
				enableFeatures(requestedFeatures,
							   &_enabledProtectedMemoryFeatures.protectedMemory,
							   &requestedFeatures->protectedMemory,
							   &pdProtectedMemoryFeatures.protectedMemory, 1);
				enableFeatures(requestedFeatures,
							   &_enabledSamplerYcbcrConversionFeatures.samplerYcbcrConversion,
							   &requestedFeatures->samplerYcbcrConversion,
							   &pdSamplerYcbcrConversionFeatures.samplerYcbcrConversion, 1);
				enableFeatures(requestedFeatures,
							   &_enabledShaderDrawParametersFeatures.shaderDrawParameters,
							   &requestedFeatures->shaderDrawParameters,
							   &pdShaderDrawParametersFeatures.shaderDrawParameters, 1);
				break;
			}
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES: {
				auto& pdvulkan12FeaturesNoExt = _physicalDevice->_vulkan12FeaturesNoExt;
				auto* requestedFeatures = (VkPhysicalDeviceVulkan12Features*)next;
				enableFeatures(requestedFeatures,
							   &_enabledVulkan12FeaturesNoExt.samplerMirrorClampToEdge,
							   &requestedFeatures->samplerMirrorClampToEdge,
							   &pdvulkan12FeaturesNoExt.samplerMirrorClampToEdge, 2);
				enableFeatures(requestedFeatures,
							   &_enabled8BitStorageFeatures.storageBuffer8BitAccess,
							   &requestedFeatures->storageBuffer8BitAccess,
							   &pd8BitStorageFeatures.storageBuffer8BitAccess, 3);
				enableFeatures(requestedFeatures,
							   &_enabledShaderAtomicInt64Features.shaderBufferInt64Atomics,
							   &requestedFeatures->shaderBufferInt64Atomics,
							   &pdShaderAtomicInt64Features.shaderBufferInt64Atomics, 2);
				enableFeatures(requestedFeatures,
							   &_enabledShaderFloat16Int8Features.shaderFloat16,
							   &requestedFeatures->shaderFloat16,
							   &pdShaderFloat16Int8Features.shaderFloat16, 2);
				enableFeatures(requestedFeatures,
							   &_enabledVulkan12FeaturesNoExt.descriptorIndexing,
							   &requestedFeatures->descriptorIndexing,
							   &pdvulkan12FeaturesNoExt.descriptorIndexing, 1);
				enableFeatures(requestedFeatures,
							   &_enabledDescriptorIndexingFeatures.shaderInputAttachmentArrayDynamicIndexing,
							   &requestedFeatures->shaderInputAttachmentArrayDynamicIndexing,
							   &pdDescriptorIndexingFeatures.shaderInputAttachmentArrayDynamicIndexing, 20);
				enableFeatures(requestedFeatures,
							   &_enabledVulkan12FeaturesNoExt.samplerFilterMinmax,
							   &requestedFeatures->samplerFilterMinmax,
							   &pdvulkan12FeaturesNoExt.samplerFilterMinmax, 1);
				enableFeatures(requestedFeatures,
							   &_enabledScalarBlockLayoutFeatures.scalarBlockLayout,
							   &requestedFeatures->scalarBlockLayout,
							   &pdScalarBlockLayoutFeatures.scalarBlockLayout, 1);
				enableFeatures(requestedFeatures,
							   &_enabledImagelessFramebufferFeatures.imagelessFramebuffer,
							   &requestedFeatures->imagelessFramebuffer,
							   &pdImagelessFramebufferFeatures.imagelessFramebuffer, 1);
				enableFeatures(requestedFeatures,
							   &_enabledUniformBufferStandardLayoutFeatures.uniformBufferStandardLayout,
							   &requestedFeatures->uniformBufferStandardLayout,
							   &pdUniformBufferStandardLayoutFeatures.uniformBufferStandardLayout, 1);
				enableFeatures(requestedFeatures,
							   &_enabledShaderSubgroupExtendedTypesFeatures.shaderSubgroupExtendedTypes,
							   &requestedFeatures->shaderSubgroupExtendedTypes,
							   &pdShaderSubgroupExtendedTypesFeatures.shaderSubgroupExtendedTypes, 1);
				enableFeatures(requestedFeatures,
							   &_enabledSeparateDepthStencilLayoutsFeatures.separateDepthStencilLayouts,
							   &requestedFeatures->separateDepthStencilLayouts,
							   &pdSeparateDepthStencilLayoutsFeatures.separateDepthStencilLayouts, 1);
				enableFeatures(requestedFeatures,
							   &_enabledHostQueryResetFeatures.hostQueryReset,
							   &requestedFeatures->hostQueryReset,
							   &pdHostQueryResetFeatures.hostQueryReset, 1);
				enableFeatures(requestedFeatures,
							   &_enabledTimelineSemaphoreFeatures.timelineSemaphore,
							   &requestedFeatures->timelineSemaphore,
							   &pdTimelineSemaphoreFeatures.timelineSemaphore, 1);
				enableFeatures(requestedFeatures,
							   &_enabledBufferDeviceAddressFeatures.bufferDeviceAddress,
							   &requestedFeatures->bufferDeviceAddress,
							   &pdBufferDeviceAddressFeatures.bufferDeviceAddress, 3);
				enableFeatures(requestedFeatures,
							   &_enabledVulkanMemoryModelFeatures.vulkanMemoryModel,
							   &requestedFeatures->vulkanMemoryModel,
							   &pdVulkanMemoryModelFeatures.vulkanMemoryModel, 3);
				enableFeatures(requestedFeatures,
							   &_enabledVulkan12FeaturesNoExt.shaderOutputViewportIndex,
							   &requestedFeatures->shaderOutputViewportIndex,
							   &pdvulkan12FeaturesNoExt.shaderOutputViewportIndex, 3);
				break;
			}

#define MVK_DEVICE_FEATURE(structName, enumName, flagCount) \
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_##enumName##_FEATURES: { \
				enableFeatures(&_enabled##structName##Features, \
							   (VkPhysicalDevice##structName##Features*)next, \
							   &pd##structName##Features, \
							   flagCount); \
				break; \
			}
#define MVK_DEVICE_FEATURE_EXTN(structName, enumName, extnSfx, flagCount) \
			case VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_##enumName##_FEATURES_##extnSfx: { \
				enableFeatures(&_enabled##structName##Features, \
							   (VkPhysicalDevice##structName##Features##extnSfx*)next, \
							   &pd##structName##Features, \
							   flagCount); \
				break; \
			}
#include "MVKDeviceFeatureStructs.def"

			default:
				break;
		}
	}
}

template<typename S>
void MVKDevice::enableFeatures(S* pEnabled, const S* pRequested, const S* pAvailable, uint32_t count) {
	enableFeatures(pRequested,
				   (VkBool32*)mvkGetAddressOfFirstMember(pEnabled),
				   (VkBool32*)mvkGetAddressOfFirstMember(pRequested),
				   (VkBool32*)mvkGetAddressOfFirstMember(pAvailable),
				   count);
}

template<typename S>
void MVKDevice::enableFeatures(S* pRequested, VkBool32* pEnabledBools, const VkBool32* pRequestedBools, const VkBool32* pAvailableBools, uint32_t count) {
	for (uint32_t i = 0; i < count; i++) {
		pEnabledBools[i] = pRequestedBools[i] && pAvailableBools[i];
		if (pRequestedBools[i] && !pAvailableBools[i]) {
			uintptr_t mbrOffset = (uintptr_t)&pRequestedBools[i] - (uintptr_t)mvkGetAddressOfFirstMember(pRequested);
			size_t mbrIdxOrd = (mbrOffset / sizeof(VkBool32)) + 1;
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateDevice(): Requested physical device feature specified by the %zu%s flag in %s is not available on this device.", mbrIdxOrd, mvk::getOrdinalSuffix(mbrIdxOrd), mvk::getTypeName(pRequested).c_str()));
		}
	}
}

void MVKDevice::enableExtensions(const VkDeviceCreateInfo* pCreateInfo) {
	setConfigurationResult(_enabledExtensions.enable(pCreateInfo->enabledExtensionCount,
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

MVKDevice::~MVKDevice() {
	if (_activityPerformanceLoggingStyle == MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_DEVICE_LIFETIME) {
		MVKLogInfo("Device activity performance summary:");
		logPerformanceSummary();
	}

	for (auto& queues : _queuesByQueueFamilyIndex) {
		mvkDestroyContainerContents(queues);
	}

	if (_commandResourceFactory) { _commandResourceFactory->destroy(); }

    [_globalVisibilityResultMTLBuffer release];
	[_defaultMTLSamplerState release];
	[_dummyBlitMTLBuffer release];

	stopAutoGPUCapture(MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_DEVICE);

	mvkDestroyContainerContents(_privateDataSlots);
}


#pragma mark -
#pragma mark Support functions

uint64_t mvkGetRegistryID(id<MTLDevice> mtlDevice) {
	return [mtlDevice respondsToSelector: @selector(registryID)] ? mtlDevice.registryID : 0;
}

uint64_t mvkGetLocationID(id<MTLDevice> mtlDevice) {
	uint64_t hash = 0;

#if MVK_MACOS && !MVK_MACCAT
	// All of these device properties were added at the same time,
	// so only need to check for the presence of one of them.
	if ([mtlDevice respondsToSelector: @selector(location)]) {
		uint64_t val;

		val = mtlDevice.location;
		hash = mvkHash(&val, 1, hash);

		val = mtlDevice.locationNumber;
		hash = mvkHash(&val, 1, hash);

		val = mtlDevice.peerGroupID;
		hash = mvkHash(&val, 1, hash);

		val = mtlDevice.peerIndex;
		hash = mvkHash(&val, 1, hash);
	}
#endif

	return hash;
}

// If the supportsBCTextureCompression query is available, use it.
// Otherwise only macOS supports BC compression.
bool mvkSupportsBCTextureCompression(id<MTLDevice> mtlDevice) {
#if MVK_XCODE_14_3 || (MVK_XCODE_12 && MVK_MACOS && !MVK_MACCAT)
	if ([mtlDevice respondsToSelector: @selector(supportsBCTextureCompression)]) {
		return mtlDevice.supportsBCTextureCompression;
	}
#endif
	return MVK_MACOS && !MVK_MACCAT;
}
