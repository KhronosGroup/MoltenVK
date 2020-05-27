/*
 * MVKPixelFormats.mm
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

#include "MVKPixelFormats.h"
#include "MVKDevice.h"
#include "MVKFoundation.h"
#include "MVKLogging.h"
#include <string>

using namespace std;


// Add stub defs for unsupported MTLPixelFormats per platform
#if MVK_MACOS
#   define MTLPixelFormatABGR4Unorm             MTLPixelFormatInvalid
#   define MTLPixelFormatB5G6R5Unorm            MTLPixelFormatInvalid
#   define MTLPixelFormatA1BGR5Unorm            MTLPixelFormatInvalid
#   define MTLPixelFormatBGR5A1Unorm            MTLPixelFormatInvalid
#   define MTLPixelFormatR8Unorm_sRGB           MTLPixelFormatInvalid
#   define MTLPixelFormatRG8Unorm_sRGB          MTLPixelFormatInvalid

#   define MTLPixelFormatETC2_RGB8              MTLPixelFormatInvalid
#   define MTLPixelFormatETC2_RGB8_sRGB         MTLPixelFormatInvalid
#   define MTLPixelFormatETC2_RGB8A1            MTLPixelFormatInvalid
#   define MTLPixelFormatETC2_RGB8A1_sRGB       MTLPixelFormatInvalid
#   define MTLPixelFormatEAC_RGBA8              MTLPixelFormatInvalid
#   define MTLPixelFormatEAC_RGBA8_sRGB         MTLPixelFormatInvalid
#   define MTLPixelFormatEAC_R11Unorm           MTLPixelFormatInvalid
#   define MTLPixelFormatEAC_R11Snorm           MTLPixelFormatInvalid
#   define MTLPixelFormatEAC_RG11Unorm          MTLPixelFormatInvalid
#   define MTLPixelFormatEAC_RG11Snorm          MTLPixelFormatInvalid

#   define MTLPixelFormatASTC_4x4_LDR           MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_4x4_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_5x4_LDR           MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_5x4_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_5x5_LDR           MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_5x5_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_6x5_LDR           MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_6x5_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_6x6_LDR           MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_6x6_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_8x5_LDR           MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_8x5_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_8x6_LDR           MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_8x6_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_8x8_LDR           MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_8x8_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_10x5_LDR          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_10x5_sRGB         MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_10x6_LDR          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_10x6_sRGB         MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_10x8_LDR          MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_10x8_sRGB         MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_10x10_LDR         MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_10x10_sRGB        MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_12x10_LDR         MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_12x10_sRGB        MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_12x12_LDR         MTLPixelFormatInvalid
#   define MTLPixelFormatASTC_12x12_sRGB        MTLPixelFormatInvalid

#   define MTLPixelFormatPVRTC_RGB_2BPP         MTLPixelFormatInvalid
#   define MTLPixelFormatPVRTC_RGB_2BPP_sRGB    MTLPixelFormatInvalid
#   define MTLPixelFormatPVRTC_RGB_4BPP         MTLPixelFormatInvalid
#   define MTLPixelFormatPVRTC_RGB_4BPP_sRGB    MTLPixelFormatInvalid
#   define MTLPixelFormatPVRTC_RGBA_2BPP        MTLPixelFormatInvalid
#   define MTLPixelFormatPVRTC_RGBA_2BPP_sRGB   MTLPixelFormatInvalid
#   define MTLPixelFormatPVRTC_RGBA_4BPP        MTLPixelFormatInvalid
#   define MTLPixelFormatPVRTC_RGBA_4BPP_sRGB   MTLPixelFormatInvalid

#   define MTLPixelFormatDepth16Unorm_Stencil8  MTLPixelFormatDepth24Unorm_Stencil8
#   define MTLPixelFormatBGRA10_XR				MTLPixelFormatInvalid
#   define MTLPixelFormatBGRA10_XR_sRGB			MTLPixelFormatInvalid
#   define MTLPixelFormatBGR10_XR				MTLPixelFormatInvalid
#   define MTLPixelFormatBGR10_XR_sRGB			MTLPixelFormatInvalid
#endif

#if MVK_IOS
#   define MTLPixelFormatDepth16Unorm           MTLPixelFormatInvalid
#   define MTLPixelFormatDepth24Unorm_Stencil8  MTLPixelFormatInvalid
#   define MTLPixelFormatX24_Stencil8           MTLPixelFormatInvalid
#   define MTLPixelFormatBC1_RGBA               MTLPixelFormatInvalid
#   define MTLPixelFormatBC1_RGBA_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatBC2_RGBA               MTLPixelFormatInvalid
#   define MTLPixelFormatBC2_RGBA_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatBC3_RGBA               MTLPixelFormatInvalid
#   define MTLPixelFormatBC3_RGBA_sRGB          MTLPixelFormatInvalid
#   define MTLPixelFormatBC4_RUnorm             MTLPixelFormatInvalid
#   define MTLPixelFormatBC4_RSnorm             MTLPixelFormatInvalid
#   define MTLPixelFormatBC5_RGUnorm            MTLPixelFormatInvalid
#   define MTLPixelFormatBC5_RGSnorm            MTLPixelFormatInvalid
#   define MTLPixelFormatBC6H_RGBUfloat         MTLPixelFormatInvalid
#   define MTLPixelFormatBC6H_RGBFloat          MTLPixelFormatInvalid
#   define MTLPixelFormatBC7_RGBAUnorm          MTLPixelFormatInvalid
#   define MTLPixelFormatBC7_RGBAUnorm_sRGB     MTLPixelFormatInvalid

#   define MTLPixelFormatDepth16Unorm_Stencil8  MTLPixelFormatDepth32Float_Stencil8
#endif


#pragma mark -
#pragma mark MVKPixelFormats

MVKVulkanAPIObject* MVKPixelFormats::getVulkanAPIObject() { return _physicalDevice; };

bool MVKPixelFormats::isSupported(VkFormat vkFormat) {
	return getVkFormatDesc(vkFormat).isSupported();
}

bool MVKPixelFormats::isSupportedOrSubstitutable(VkFormat vkFormat) {
	return getVkFormatDesc(vkFormat).isSupportedOrSubstitutable();
}

bool MVKPixelFormats::isSupported(MTLPixelFormat mtlFormat) {
	return getMTLPixelFormatDesc(mtlFormat).isSupported();
}

bool MVKPixelFormats::isDepthFormat(MTLPixelFormat mtlFormat) {
	switch (mtlFormat) {
		case MTLPixelFormatDepth32Float:
#if MVK_MACOS
		case MTLPixelFormatDepth16Unorm:
		case MTLPixelFormatDepth24Unorm_Stencil8:
#endif
		case MTLPixelFormatDepth32Float_Stencil8:
			return true;
		default:
			return false;
	}
}

bool MVKPixelFormats::isStencilFormat(MTLPixelFormat mtlFormat) {
	switch (mtlFormat) {
		case MTLPixelFormatStencil8:
#if MVK_MACOS
		case MTLPixelFormatDepth24Unorm_Stencil8:
		case MTLPixelFormatX24_Stencil8:
#endif
		case MTLPixelFormatDepth32Float_Stencil8:
		case MTLPixelFormatX32_Stencil8:
			return true;
		default:
			return false;
	}
}

bool MVKPixelFormats::isPVRTCFormat(MTLPixelFormat mtlFormat) {
	switch (mtlFormat) {
#if MVK_IOS
		case MTLPixelFormatPVRTC_RGBA_2BPP:
		case MTLPixelFormatPVRTC_RGBA_2BPP_sRGB:
		case MTLPixelFormatPVRTC_RGBA_4BPP:
		case MTLPixelFormatPVRTC_RGBA_4BPP_sRGB:
		case MTLPixelFormatPVRTC_RGB_2BPP:
		case MTLPixelFormatPVRTC_RGB_2BPP_sRGB:
		case MTLPixelFormatPVRTC_RGB_4BPP:
		case MTLPixelFormatPVRTC_RGB_4BPP_sRGB:
			return true;
#endif
		default:
			return false;
	}
}

MVKFormatType MVKPixelFormats::getFormatType(VkFormat vkFormat) {
	return getVkFormatDesc(vkFormat).formatType;
}

MVKFormatType MVKPixelFormats::getFormatType(MTLPixelFormat mtlFormat) {
	return getVkFormatDesc(mtlFormat).formatType;
}

MTLPixelFormat MVKPixelFormats::getMTLPixelFormat(VkFormat vkFormat) {
	auto& vkDesc = getVkFormatDesc(vkFormat);
	MTLPixelFormat mtlPixFmt = vkDesc.mtlPixelFormat;

	// If the MTLPixelFormat is not supported but VkFormat is valid,
	// attempt to substitute a different format and potentially report an error.
	if ( !mtlPixFmt && vkFormat ) {
		mtlPixFmt = vkDesc.mtlPixelFormatSubstitute;

		// Report an error if there is no substitute, or the first time a substitution is made.
		if ( !mtlPixFmt || !vkDesc.hasReportedSubstitution ) {
			string errMsg;
			errMsg += "VkFormat ";
			errMsg += (vkDesc.name) ? vkDesc.name : to_string(vkDesc.vkFormat);
			errMsg += " is not supported on this device.";

			if (mtlPixFmt) {
				vkDesc.hasReportedSubstitution = true;

				auto& vkDescSubs = getVkFormatDesc(mtlPixFmt);
				errMsg += " Using VkFormat ";
				errMsg += (vkDescSubs.name) ? vkDescSubs.name : to_string(vkDescSubs.vkFormat);
				errMsg += " instead.";
			}
			MVKBaseObject::reportError(_physicalDevice, VK_ERROR_FORMAT_NOT_SUPPORTED, "%s", errMsg.c_str());
		}
	}

	return mtlPixFmt;
}

VkFormat MVKPixelFormats::getVkFormat(MTLPixelFormat mtlFormat) {
    return getMTLPixelFormatDesc(mtlFormat).vkFormat;
}

uint32_t MVKPixelFormats::getBytesPerBlock(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).bytesPerBlock;
}

uint32_t MVKPixelFormats::getBytesPerBlock(MTLPixelFormat mtlFormat) {
    return getVkFormatDesc(mtlFormat).bytesPerBlock;
}

VkExtent2D MVKPixelFormats::getBlockTexelSize(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).blockTexelSize;
}

VkExtent2D MVKPixelFormats::getBlockTexelSize(MTLPixelFormat mtlFormat) {
    return getVkFormatDesc(mtlFormat).blockTexelSize;
}

float MVKPixelFormats::getBytesPerTexel(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).bytesPerTexel();
}

float MVKPixelFormats::getBytesPerTexel(MTLPixelFormat mtlFormat) {
    return getVkFormatDesc(mtlFormat).bytesPerTexel();
}

size_t MVKPixelFormats::getBytesPerRow(VkFormat vkFormat, uint32_t texelsPerRow) {
    auto& vkDesc = getVkFormatDesc(vkFormat);
    return mvkCeilingDivide(texelsPerRow, vkDesc.blockTexelSize.width) * vkDesc.bytesPerBlock;
}

size_t MVKPixelFormats::getBytesPerRow(MTLPixelFormat mtlFormat, uint32_t texelsPerRow) {
	auto& vkDesc = getVkFormatDesc(mtlFormat);
    return mvkCeilingDivide(texelsPerRow, vkDesc.blockTexelSize.width) * vkDesc.bytesPerBlock;
}

size_t MVKPixelFormats::getBytesPerLayer(VkFormat vkFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer) {
    return mvkCeilingDivide(texelRowsPerLayer, getVkFormatDesc(vkFormat).blockTexelSize.height) * bytesPerRow;
}

size_t MVKPixelFormats::getBytesPerLayer(MTLPixelFormat mtlFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer) {
    return mvkCeilingDivide(texelRowsPerLayer, getVkFormatDesc(mtlFormat).blockTexelSize.height) * bytesPerRow;
}

VkFormatProperties MVKPixelFormats::getVkFormatProperties(VkFormat vkFormat) {
	return	getVkFormatDesc(vkFormat).properties;
}

MVKMTLFmtCaps MVKPixelFormats::getCapabilities(VkFormat vkFormat) {
	return getMTLPixelFormatDesc(vkFormat).mtlFmtCaps;
}

MVKMTLFmtCaps MVKPixelFormats::getCapabilities(MTLPixelFormat mtlFormat) {
	return getMTLPixelFormatDesc(mtlFormat).mtlFmtCaps;
}

const char* MVKPixelFormats::getName(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).name;
}

const char* MVKPixelFormats::getName(MTLPixelFormat mtlFormat) {
    return getMTLPixelFormatDesc(mtlFormat).name;
}

void MVKPixelFormats::enumerateSupportedFormats(VkFormatProperties properties, bool any, std::function<bool(VkFormat)> func) {
	static const auto areFeaturesSupported = [any](uint32_t a, uint32_t b) {
		if (b == 0) return true;
		if (any)
			return mvkIsAnyFlagEnabled(a, b);
		else
			return mvkAreAllFlagsEnabled(a, b);
	};
	for (auto& vkDesc : _vkFormatDescriptions) {
		if (vkDesc.isSupported() &&
			areFeaturesSupported(vkDesc.properties.linearTilingFeatures, properties.linearTilingFeatures) &&
			areFeaturesSupported(vkDesc.properties.optimalTilingFeatures, properties.optimalTilingFeatures) &&
			areFeaturesSupported(vkDesc.properties.bufferFeatures, properties.bufferFeatures)) {
			if ( !func(vkDesc.vkFormat) ) {
				break;
			}
		}
	}
}

MTLVertexFormat MVKPixelFormats::getMTLVertexFormat(VkFormat vkFormat) {
	auto& vkDesc = getVkFormatDesc(vkFormat);
	MTLVertexFormat mtlVtxFmt = vkDesc.mtlVertexFormat;

	// If the MTLVertexFormat is not supported but VkFormat is valid,
	// report an error, and possibly substitute a different MTLVertexFormat.
	if ( !mtlVtxFmt && vkFormat ) {
		string errMsg;
		errMsg += "VkFormat ";
		errMsg += (vkDesc.name) ? vkDesc.name : to_string(vkDesc.vkFormat);
		errMsg += " is not supported for vertex buffers on this device.";

		if (vkDesc.vertexIsSupportedOrSubstitutable()) {
			mtlVtxFmt = vkDesc.mtlVertexFormatSubstitute;

			auto& vkDescSubs = getVkFormatDesc(getMTLVertexFormatDesc(mtlVtxFmt).vkFormat);
			errMsg += " Using VkFormat ";
			errMsg += (vkDescSubs.name) ? vkDescSubs.name : to_string(vkDescSubs.vkFormat);
			errMsg += " instead.";
		}
		MVKBaseObject::reportError(_physicalDevice, VK_ERROR_FORMAT_NOT_SUPPORTED, "%s", errMsg.c_str());
	}

	return mtlVtxFmt;
}

MTLClearColor MVKPixelFormats::getMTLClearColor(VkClearValue vkClearValue, VkFormat vkFormat) {
	MTLClearColor mtlClr;
	switch (getFormatType(vkFormat)) {
		case kMVKFormatColorHalf:
		case kMVKFormatColorFloat:
			mtlClr.red		= vkClearValue.color.float32[0];
			mtlClr.green	= vkClearValue.color.float32[1];
			mtlClr.blue		= vkClearValue.color.float32[2];
			mtlClr.alpha	= vkClearValue.color.float32[3];
			break;
		case kMVKFormatColorUInt8:
		case kMVKFormatColorUInt16:
		case kMVKFormatColorUInt32:
			mtlClr.red		= vkClearValue.color.uint32[0];
			mtlClr.green	= vkClearValue.color.uint32[1];
			mtlClr.blue		= vkClearValue.color.uint32[2];
			mtlClr.alpha	= vkClearValue.color.uint32[3];
			break;
		case kMVKFormatColorInt8:
		case kMVKFormatColorInt16:
		case kMVKFormatColorInt32:
			mtlClr.red		= vkClearValue.color.int32[0];
			mtlClr.green	= vkClearValue.color.int32[1];
			mtlClr.blue		= vkClearValue.color.int32[2];
			mtlClr.alpha	= vkClearValue.color.int32[3];
			break;
		default:
			mtlClr.red		= 0.0;
			mtlClr.green	= 0.0;
			mtlClr.blue		= 0.0;
			mtlClr.alpha	= 1.0;
			break;
	}
	return mtlClr;
}

double MVKPixelFormats::getMTLClearDepthValue(VkClearValue vkClearValue) {
	return vkClearValue.depthStencil.depth;
}

uint32_t MVKPixelFormats::getMTLClearStencilValue(VkClearValue vkClearValue) {
	return vkClearValue.depthStencil.stencil;
}

VkImageUsageFlags MVKPixelFormats::getVkImageUsageFlags(MTLTextureUsage mtlUsage,
														MTLPixelFormat mtlFormat) {
    VkImageUsageFlags vkImageUsageFlags = 0;

    if ( mvkAreAllFlagsEnabled(mtlUsage, MTLTextureUsageShaderRead) ) {
        mvkEnableFlags(vkImageUsageFlags, VK_IMAGE_USAGE_TRANSFER_SRC_BIT);
        mvkEnableFlags(vkImageUsageFlags, VK_IMAGE_USAGE_SAMPLED_BIT);
        mvkEnableFlags(vkImageUsageFlags, VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT);
    }
    if ( mvkAreAllFlagsEnabled(mtlUsage, MTLTextureUsageRenderTarget) ) {
        mvkEnableFlags(vkImageUsageFlags, VK_IMAGE_USAGE_TRANSFER_DST_BIT);
        if (isDepthFormat(mtlFormat) || isStencilFormat(mtlFormat)) {
            mvkEnableFlags(vkImageUsageFlags, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT);
        } else {
            mvkEnableFlags(vkImageUsageFlags, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT);
        }
    }
    if ( mvkAreAllFlagsEnabled(mtlUsage, MTLTextureUsageShaderWrite) ) {
        mvkEnableFlags(vkImageUsageFlags, VK_IMAGE_USAGE_STORAGE_BIT);
    }

    return vkImageUsageFlags;
}

MTLTextureUsage MVKPixelFormats::getMTLTextureUsage(VkImageUsageFlags vkImageUsageFlags,
													MTLPixelFormat mtlFormat,
													MTLTextureUsage minUsage,
													VkBool32 allowImageCopyReinterpretation) {
	bool isDepthFmt = isDepthFormat(mtlFormat);
	bool isStencilFmt = isStencilFormat(mtlFormat);
	bool isCombinedDepthStencilFmt = isDepthFmt && isStencilFmt;
	bool isColorFormat = !(isDepthFmt || isStencilFmt);
	bool supportsStencilViews = _physicalDevice ? _physicalDevice->getMetalFeatures()->stencilViews : false;
	MVKMTLFmtCaps mtlFmtCaps = getCapabilities(mtlFormat);

	MTLTextureUsage mtlUsage = minUsage;

	// Read from...
	if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
												VK_IMAGE_USAGE_SAMPLED_BIT |
												VK_IMAGE_USAGE_STORAGE_BIT |
												VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT))) {
		mvkEnableFlags(mtlUsage, MTLTextureUsageShaderRead);
	}

	// Write to, but only if format supports writing...
	if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_STORAGE_BIT)) &&
		mvkIsAnyFlagEnabled(mtlFmtCaps, kMVKMTLFmtCapsWrite)) {

		mvkEnableFlags(mtlUsage, MTLTextureUsageShaderWrite);
	}

	// Render to but only if format supports rendering...
	if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
												VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
												VK_IMAGE_USAGE_TRANSFER_DST_BIT)) &&	// Scaling a BLIT may use rendering.
		mvkIsAnyFlagEnabled(mtlFmtCaps, (kMVKMTLFmtCapsColorAtt | kMVKMTLFmtCapsDSAtt))) {

		mvkEnableFlags(mtlUsage, MTLTextureUsageRenderTarget);
	}

	// MTLTextureUsagePixelFormatView is required only for reinterpretation of formats.  vkCmdCopyImage
	// allows format reinterpretations for formats of the same bits, so this must be set for VK_IMAGE_USAGE_TRANSFER_SRC_BIT.
	// However, on iOS GPU family 5 and later, this will disable lossless compression causing a performance impact,
	// so there is an MVKConfig option to disable this (allowImageCopyReinterpretation).  It's the application's
	// way of telling MoltenVK that it doesn't require format converting copies.
	if (allowImageCopyReinterpretation) {
		if (mvkIsAnyFlagEnabled(vkImageUsageFlags, VK_IMAGE_USAGE_TRANSFER_SRC_BIT) &&
			(isColorFormat || (isCombinedDepthStencilFmt && supportsStencilViews))) {
			mvkEnableFlags(mtlUsage, MTLTextureUsagePixelFormatView);
		}
	}

	return mtlUsage;
}

// Return a reference to the Vulkan format descriptor corresponding to the VkFormat.
MVKVkFormatDesc& MVKPixelFormats::getVkFormatDesc(VkFormat vkFormat) {
	uint16_t fmtIdx = (vkFormat < _vkFormatCoreCount) ? _vkFormatDescIndicesByVkFormatsCore[vkFormat] : _vkFormatDescIndicesByVkFormatsExt[vkFormat];
	return _vkFormatDescriptions[fmtIdx];
}

// Return a reference to the Vulkan format descriptor corresponding to the MTLPixelFormat.
MVKVkFormatDesc& MVKPixelFormats::getVkFormatDesc(MTLPixelFormat mtlFormat) {
	return getVkFormatDesc(getMTLPixelFormatDesc(mtlFormat).vkFormat);
}

// Return a reference to the Metal format descriptor corresponding to the VkFormat.
MVKMTLFormatDesc& MVKPixelFormats::getMTLPixelFormatDesc(VkFormat vkFormat) {
	return getMTLPixelFormatDesc(getVkFormatDesc(vkFormat).getMTLPixelFormatOrSubstitute());
}

// Return a reference to the Metal format descriptor corresponding to the MTLPixelFormat.
MVKMTLFormatDesc& MVKPixelFormats::getMTLPixelFormatDesc(MTLPixelFormat mtlFormat) {
	uint16_t fmtIdx = (mtlFormat < _mtlPixelFormatCount) ? _mtlFormatDescIndicesByMTLPixelFormats[mtlFormat] : 0;
	return _mtlPixelFormatDescriptions[fmtIdx];
}

// Return a reference to the Metal format descriptor corresponding to the VkFormat.
MVKMTLFormatDesc& MVKPixelFormats::getMTLVertexFormatDesc(VkFormat vkFormat) {
	return getMTLVertexFormatDesc(getVkFormatDesc(vkFormat).getMTLVertexFormatOrSubstitute());
}

// Return a reference to the Metal format descriptor corresponding to the MTLVertexFormat.
MVKMTLFormatDesc& MVKPixelFormats::getMTLVertexFormatDesc(MTLVertexFormat mtlFormat) {
	uint16_t fmtIdx = (mtlFormat < _mtlVertexFormatCount) ? _mtlFormatDescIndicesByMTLVertexFormats[mtlFormat] : 0;
	return _mtlVertexFormatDescriptions[fmtIdx];
}


#pragma mark Construction

MVKPixelFormats::MVKPixelFormats(MVKPhysicalDevice* physicalDevice) : _physicalDevice(physicalDevice) {

	// Build and update the Metal formats
	initMTLPixelFormatCapabilities();
	initMTLVertexFormatCapabilities();
	buildMTLFormatMaps();
	modifyMTLFormatCapabilities();

	// Build the Vulkan formats and link them to the Metal formats
	initVkFormatCapabilities();
	buildVkFormatMaps();

//	test();
}

#define addVkFormatDesc(VK_FMT, MTL_FMT, MTL_FMT_ALT, MTL_VTX_FMT, MTL_VTX_FMT_ALT, BLK_W, BLK_H, BLK_BYTE_CNT, MVK_FMT_TYPE)  \
	MVKAssert(fmtIdx < _vkFormatCount, "Attempting to describe %d VkFormats, but only have space for %d. Increase the value of _vkFormatCount", fmtIdx + 1, _vkFormatCount);  \
	_vkFormatDescriptions[fmtIdx++] = { VK_FORMAT_ ##VK_FMT, MTLPixelFormat ##MTL_FMT, MTLPixelFormat ##MTL_FMT_ALT, MTLVertexFormat ##MTL_VTX_FMT, MTLVertexFormat ##MTL_VTX_FMT_ALT,  \
										{ BLK_W, BLK_H }, BLK_BYTE_CNT, kMVKFormat ##MVK_FMT_TYPE, { 0, 0, 0 }, "VK_FORMAT_" #VK_FMT, false }

void MVKPixelFormats::initVkFormatCapabilities() {

	mvkClear(_vkFormatDescriptions, _vkFormatCount);

	uint32_t fmtIdx = 0;

	// When adding to this list, be sure to ensure _vkFormatCount is large enough for the format count
	// UNDEFINED must come first.
	addVkFormatDesc( UNDEFINED, Invalid, Invalid, Invalid, Invalid, 1, 1, 0, None );

	addVkFormatDesc( R4G4_UNORM_PACK8, Invalid, Invalid, Invalid, Invalid, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R4G4B4A4_UNORM_PACK16, ABGR4Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( B4G4R4A4_UNORM_PACK16, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );

	addVkFormatDesc( R5G6B5_UNORM_PACK16, B5G6R5Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( B5G6R5_UNORM_PACK16, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R5G5B5A1_UNORM_PACK16, A1BGR5Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( B5G5R5A1_UNORM_PACK16, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( A1R5G5B5_UNORM_PACK16, BGR5A1Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );

	addVkFormatDesc( R8_UNORM, R8Unorm, Invalid, UCharNormalized, UChar2Normalized, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R8_SNORM, R8Snorm, Invalid, CharNormalized, Char2Normalized, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R8_UINT, R8Uint, Invalid, UChar, UChar2, 1, 1, 1, ColorUInt8 );
	addVkFormatDesc( R8_SINT, R8Sint, Invalid, Char, Char2, 1, 1, 1, ColorInt8 );
	addVkFormatDesc( R8_SRGB, R8Unorm_sRGB, Invalid, UCharNormalized, UChar2Normalized, 1, 1, 1, ColorFloat );

	addVkFormatDesc( R8G8_UNORM, RG8Unorm, Invalid, UChar2Normalized, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R8G8_SNORM, RG8Snorm, Invalid, Char2Normalized, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R8G8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R8G8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R8G8_UINT, RG8Uint, Invalid, UChar2, Invalid, 1, 1, 2, ColorUInt8 );
	addVkFormatDesc( R8G8_SINT, RG8Sint, Invalid, Char2, Invalid, 1, 1, 2, ColorInt8 );
	addVkFormatDesc( R8G8_SRGB, RG8Unorm_sRGB, Invalid, UChar2Normalized, Invalid, 1, 1, 2, ColorFloat );

	addVkFormatDesc( R8G8B8_UNORM, Invalid, Invalid, UChar3Normalized, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( R8G8B8_SNORM, Invalid, Invalid, Char3Normalized, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( R8G8B8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( R8G8B8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( R8G8B8_UINT, Invalid, Invalid, UChar3, Invalid, 1, 1, 3, ColorUInt8 );
	addVkFormatDesc( R8G8B8_SINT, Invalid, Invalid, Char3, Invalid, 1, 1, 3, ColorInt8 );
	addVkFormatDesc( R8G8B8_SRGB, Invalid, Invalid, UChar3Normalized, Invalid, 1, 1, 3, ColorFloat );

	addVkFormatDesc( B8G8R8_UNORM, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( B8G8R8_SNORM, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( B8G8R8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( B8G8R8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( B8G8R8_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorUInt8 );
	addVkFormatDesc( B8G8R8_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorInt8 );
	addVkFormatDesc( B8G8R8_SRGB, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat );

	addVkFormatDesc( R8G8B8A8_UNORM, RGBA8Unorm, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R8G8B8A8_SNORM, RGBA8Snorm, Invalid, Char4Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R8G8B8A8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R8G8B8A8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R8G8B8A8_UINT, RGBA8Uint, Invalid, UChar4, Invalid, 1, 1, 4, ColorUInt8 );
	addVkFormatDesc( R8G8B8A8_SINT, RGBA8Sint, Invalid, Char4, Invalid, 1, 1, 4, ColorInt8 );
	addVkFormatDesc( R8G8B8A8_SRGB, RGBA8Unorm_sRGB, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat );

	addVkFormatDesc( B8G8R8A8_UNORM, BGRA8Unorm, Invalid, UChar4Normalized_BGRA, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( B8G8R8A8_SNORM, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( B8G8R8A8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( B8G8R8A8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( B8G8R8A8_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorUInt8 );
	addVkFormatDesc( B8G8R8A8_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorInt8 );
	addVkFormatDesc( B8G8R8A8_SRGB, BGRA8Unorm_sRGB, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );

	addVkFormatDesc( A8B8G8R8_UNORM_PACK32, RGBA8Unorm, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A8B8G8R8_SNORM_PACK32, RGBA8Snorm, Invalid, Char4Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A8B8G8R8_USCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A8B8G8R8_SSCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A8B8G8R8_UINT_PACK32, RGBA8Uint, Invalid, UChar4, Invalid, 1, 1, 4, ColorUInt8 );
	addVkFormatDesc( A8B8G8R8_SINT_PACK32, RGBA8Sint, Invalid, Char4, Invalid, 1, 1, 4, ColorInt8 );
	addVkFormatDesc( A8B8G8R8_SRGB_PACK32, RGBA8Unorm_sRGB, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat );

	addVkFormatDesc( A2R10G10B10_UNORM_PACK32, BGR10A2Unorm, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A2R10G10B10_SNORM_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A2R10G10B10_USCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A2R10G10B10_SSCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A2R10G10B10_UINT_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorUInt16 );
	addVkFormatDesc( A2R10G10B10_SINT_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorInt16 );

	addVkFormatDesc( A2B10G10R10_UNORM_PACK32, RGB10A2Unorm, Invalid, UInt1010102Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A2B10G10R10_SNORM_PACK32, Invalid, Invalid, Int1010102Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A2B10G10R10_USCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A2B10G10R10_SSCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A2B10G10R10_UINT_PACK32, RGB10A2Uint, Invalid, Invalid, Invalid, 1, 1, 4, ColorUInt16 );
	addVkFormatDesc( A2B10G10R10_SINT_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorInt16 );

	addVkFormatDesc( R16_UNORM, R16Unorm, Invalid, UShortNormalized, UShort2Normalized, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R16_SNORM, R16Snorm, Invalid, ShortNormalized, Short2Normalized, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R16_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R16_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R16_UINT, R16Uint, Invalid, UShort, UShort2, 1, 1, 2, ColorUInt16 );
	addVkFormatDesc( R16_SINT, R16Sint, Invalid, Short, Short2, 1, 1, 2, ColorInt16 );
	addVkFormatDesc( R16_SFLOAT, R16Float, Invalid, Half, Half2, 1, 1, 2, ColorFloat );

	addVkFormatDesc( R16G16_UNORM, RG16Unorm, Invalid, UShort2Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R16G16_SNORM, RG16Snorm, Invalid, Short2Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R16G16_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R16G16_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R16G16_UINT, RG16Uint, Invalid, UShort2, Invalid, 1, 1, 4, ColorUInt16 );
	addVkFormatDesc( R16G16_SINT, RG16Sint, Invalid, Short2, Invalid, 1, 1, 4, ColorInt16 );
	addVkFormatDesc( R16G16_SFLOAT, RG16Float, Invalid, Half2, Invalid, 1, 1, 4, ColorFloat );

	addVkFormatDesc( R16G16B16_UNORM, Invalid, Invalid, UShort3Normalized, Invalid, 1, 1, 6, ColorFloat );
	addVkFormatDesc( R16G16B16_SNORM, Invalid, Invalid, Short3Normalized, Invalid, 1, 1, 6, ColorFloat );
	addVkFormatDesc( R16G16B16_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 6, ColorFloat );
	addVkFormatDesc( R16G16B16_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 6, ColorFloat );
	addVkFormatDesc( R16G16B16_UINT, Invalid, Invalid, UShort3, Invalid, 1, 1, 6, ColorUInt16 );
	addVkFormatDesc( R16G16B16_SINT, Invalid, Invalid, Short3, Invalid, 1, 1, 6, ColorInt16 );
	addVkFormatDesc( R16G16B16_SFLOAT, Invalid, Invalid, Half3, Invalid, 1, 1, 6, ColorFloat );

	addVkFormatDesc( R16G16B16A16_UNORM, RGBA16Unorm, Invalid, UShort4Normalized, Invalid, 1, 1, 8, ColorFloat );
	addVkFormatDesc( R16G16B16A16_SNORM, RGBA16Snorm, Invalid, Short4Normalized, Invalid, 1, 1, 8, ColorFloat );
	addVkFormatDesc( R16G16B16A16_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat );
	addVkFormatDesc( R16G16B16A16_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat );
	addVkFormatDesc( R16G16B16A16_UINT, RGBA16Uint, Invalid, UShort4, Invalid, 1, 1, 8, ColorUInt16 );
	addVkFormatDesc( R16G16B16A16_SINT, RGBA16Sint, Invalid, Short4, Invalid, 1, 1, 8, ColorInt16 );
	addVkFormatDesc( R16G16B16A16_SFLOAT, RGBA16Float, Invalid, Half4, Invalid, 1, 1, 8, ColorFloat );

	addVkFormatDesc( R32_UINT, R32Uint, Invalid, UInt, Invalid, 1, 1, 4, ColorUInt32 );
	addVkFormatDesc( R32_SINT, R32Sint, Invalid, Int, Invalid, 1, 1, 4, ColorInt32 );
	addVkFormatDesc( R32_SFLOAT, R32Float, Invalid, Float, Invalid, 1, 1, 4, ColorFloat );

	addVkFormatDesc( R32G32_UINT, RG32Uint, Invalid, UInt2, Invalid, 1, 1, 8, ColorUInt32 );
	addVkFormatDesc( R32G32_SINT, RG32Sint, Invalid, Int2, Invalid, 1, 1, 8, ColorInt32 );
	addVkFormatDesc( R32G32_SFLOAT, RG32Float, Invalid, Float2, Invalid, 1, 1, 8, ColorFloat );

	addVkFormatDesc( R32G32B32_UINT, Invalid, Invalid, UInt3, Invalid, 1, 1, 12, ColorUInt32 );
	addVkFormatDesc( R32G32B32_SINT, Invalid, Invalid, Int3, Invalid, 1, 1, 12, ColorInt32 );
	addVkFormatDesc( R32G32B32_SFLOAT, Invalid, Invalid, Float3, Invalid, 1, 1, 12, ColorFloat );

	addVkFormatDesc( R32G32B32A32_UINT, RGBA32Uint, Invalid, UInt4, Invalid, 1, 1, 16, ColorUInt32 );
	addVkFormatDesc( R32G32B32A32_SINT, RGBA32Sint, Invalid, Int4, Invalid, 1, 1, 16, ColorInt32 );
	addVkFormatDesc( R32G32B32A32_SFLOAT, RGBA32Float, Invalid, Float4, Invalid, 1, 1, 16, ColorFloat );

	addVkFormatDesc( R64_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat );
	addVkFormatDesc( R64_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat );
	addVkFormatDesc( R64_SFLOAT, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat );

	addVkFormatDesc( R64G64_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 16, ColorFloat );
	addVkFormatDesc( R64G64_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 16, ColorFloat );
	addVkFormatDesc( R64G64_SFLOAT, Invalid, Invalid, Invalid, Invalid, 1, 1, 16, ColorFloat );

	addVkFormatDesc( R64G64B64_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 24, ColorFloat );
	addVkFormatDesc( R64G64B64_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 24, ColorFloat );
	addVkFormatDesc( R64G64B64_SFLOAT, Invalid, Invalid, Invalid, Invalid, 1, 1, 24, ColorFloat );

	addVkFormatDesc( R64G64B64A64_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 32, ColorFloat );
	addVkFormatDesc( R64G64B64A64_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 32, ColorFloat );
	addVkFormatDesc( R64G64B64A64_SFLOAT, Invalid, Invalid, Invalid, Invalid, 1, 1, 32, ColorFloat );

	addVkFormatDesc( B10G11R11_UFLOAT_PACK32, RG11B10Float, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( E5B9G9R9_UFLOAT_PACK32, RGB9E5Float, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );

	addVkFormatDesc( D32_SFLOAT, Depth32Float, Invalid, Invalid, Invalid, 1, 1, 4, DepthStencil );
	addVkFormatDesc( D32_SFLOAT_S8_UINT, Depth32Float_Stencil8, Invalid, Invalid, Invalid, 1, 1, 5, DepthStencil );

	addVkFormatDesc( S8_UINT, Stencil8, Invalid, Invalid, Invalid, 1, 1, 1, DepthStencil );

	addVkFormatDesc( D16_UNORM, Depth16Unorm, Depth32Float, Invalid, Invalid, 1, 1, 2, DepthStencil );
	addVkFormatDesc( D16_UNORM_S8_UINT, Invalid, Depth16Unorm_Stencil8, Invalid, Invalid, 1, 1, 3, DepthStencil );
	addVkFormatDesc( D24_UNORM_S8_UINT, Depth24Unorm_Stencil8, Depth32Float_Stencil8, Invalid, Invalid, 1, 1, 4, DepthStencil );

	addVkFormatDesc( X8_D24_UNORM_PACK32, Invalid, Depth24Unorm_Stencil8, Invalid, Invalid, 1, 1, 4, DepthStencil );

	addVkFormatDesc( BC1_RGB_UNORM_BLOCK, BC1_RGBA, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( BC1_RGB_SRGB_BLOCK, BC1_RGBA_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( BC1_RGBA_UNORM_BLOCK, BC1_RGBA, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( BC1_RGBA_SRGB_BLOCK, BC1_RGBA_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );

	addVkFormatDesc( BC2_UNORM_BLOCK, BC2_RGBA, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( BC2_SRGB_BLOCK, BC2_RGBA_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );

	addVkFormatDesc( BC3_UNORM_BLOCK, BC3_RGBA, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( BC3_SRGB_BLOCK, BC3_RGBA_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );

	addVkFormatDesc( BC4_UNORM_BLOCK, BC4_RUnorm, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( BC4_SNORM_BLOCK, BC4_RSnorm, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );

	addVkFormatDesc( BC5_UNORM_BLOCK, BC5_RGUnorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( BC5_SNORM_BLOCK, BC5_RGSnorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );

	addVkFormatDesc( BC6H_UFLOAT_BLOCK, BC6H_RGBUfloat, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( BC6H_SFLOAT_BLOCK, BC6H_RGBFloat, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );

	addVkFormatDesc( BC7_UNORM_BLOCK, BC7_RGBAUnorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( BC7_SRGB_BLOCK, BC7_RGBAUnorm_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );

	addVkFormatDesc( ETC2_R8G8B8_UNORM_BLOCK, ETC2_RGB8, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( ETC2_R8G8B8_SRGB_BLOCK, ETC2_RGB8_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( ETC2_R8G8B8A1_UNORM_BLOCK, ETC2_RGB8A1, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( ETC2_R8G8B8A1_SRGB_BLOCK, ETC2_RGB8A1_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );

	addVkFormatDesc( ETC2_R8G8B8A8_UNORM_BLOCK, EAC_RGBA8, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( ETC2_R8G8B8A8_SRGB_BLOCK, EAC_RGBA8_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );

	addVkFormatDesc( EAC_R11_UNORM_BLOCK, EAC_R11Unorm, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( EAC_R11_SNORM_BLOCK, EAC_R11Snorm, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );

	addVkFormatDesc( EAC_R11G11_UNORM_BLOCK, EAC_RG11Unorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( EAC_R11G11_SNORM_BLOCK, EAC_RG11Snorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );

	addVkFormatDesc( ASTC_4x4_UNORM_BLOCK, ASTC_4x4_LDR, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( ASTC_4x4_SRGB_BLOCK, ASTC_4x4_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( ASTC_5x4_UNORM_BLOCK, ASTC_5x4_LDR, Invalid, Invalid, Invalid, 5, 4, 16, Compressed );
	addVkFormatDesc( ASTC_5x4_SRGB_BLOCK, ASTC_5x4_sRGB, Invalid, Invalid, Invalid, 5, 4, 16, Compressed );
	addVkFormatDesc( ASTC_5x5_UNORM_BLOCK, ASTC_5x5_LDR, Invalid, Invalid, Invalid, 5, 5, 16, Compressed );
	addVkFormatDesc( ASTC_5x5_SRGB_BLOCK, ASTC_5x5_sRGB, Invalid, Invalid, Invalid, 5, 5, 16, Compressed );
	addVkFormatDesc( ASTC_6x5_UNORM_BLOCK, ASTC_6x5_LDR, Invalid, Invalid, Invalid, 6, 5, 16, Compressed );
	addVkFormatDesc( ASTC_6x5_SRGB_BLOCK, ASTC_6x5_sRGB, Invalid, Invalid, Invalid, 6, 5, 16, Compressed );
	addVkFormatDesc( ASTC_6x6_UNORM_BLOCK, ASTC_6x6_LDR, Invalid, Invalid, Invalid, 6, 6, 16, Compressed );
	addVkFormatDesc( ASTC_6x6_SRGB_BLOCK, ASTC_6x6_sRGB, Invalid, Invalid, Invalid, 6, 6, 16, Compressed );
	addVkFormatDesc( ASTC_8x5_UNORM_BLOCK, ASTC_8x5_LDR, Invalid, Invalid, Invalid, 8, 5, 16, Compressed );
	addVkFormatDesc( ASTC_8x5_SRGB_BLOCK, ASTC_8x5_sRGB, Invalid, Invalid, Invalid, 8, 5, 16, Compressed );
	addVkFormatDesc( ASTC_8x6_UNORM_BLOCK, ASTC_8x6_LDR, Invalid, Invalid, Invalid, 8, 6, 16, Compressed );
	addVkFormatDesc( ASTC_8x6_SRGB_BLOCK, ASTC_8x6_sRGB, Invalid, Invalid, Invalid, 8, 6, 16, Compressed );
	addVkFormatDesc( ASTC_8x8_UNORM_BLOCK, ASTC_8x8_LDR, Invalid, Invalid, Invalid, 8, 8, 16, Compressed );
	addVkFormatDesc( ASTC_8x8_SRGB_BLOCK, ASTC_8x8_sRGB, Invalid, Invalid, Invalid, 8, 8, 16, Compressed );
	addVkFormatDesc( ASTC_10x5_UNORM_BLOCK, ASTC_10x5_LDR, Invalid, Invalid, Invalid, 10, 5, 16, Compressed );
	addVkFormatDesc( ASTC_10x5_SRGB_BLOCK, ASTC_10x5_sRGB, Invalid, Invalid, Invalid, 10, 5, 16, Compressed );
	addVkFormatDesc( ASTC_10x6_UNORM_BLOCK, ASTC_10x6_LDR, Invalid, Invalid, Invalid, 10, 6, 16, Compressed );
	addVkFormatDesc( ASTC_10x6_SRGB_BLOCK, ASTC_10x6_sRGB, Invalid, Invalid, Invalid, 10, 6, 16, Compressed );
	addVkFormatDesc( ASTC_10x8_UNORM_BLOCK, ASTC_10x8_LDR, Invalid, Invalid, Invalid, 10, 8, 16, Compressed );
	addVkFormatDesc( ASTC_10x8_SRGB_BLOCK, ASTC_10x8_sRGB, Invalid, Invalid, Invalid, 10, 8, 16, Compressed );
	addVkFormatDesc( ASTC_10x10_UNORM_BLOCK, ASTC_10x10_LDR, Invalid, Invalid, Invalid, 10, 10, 16, Compressed );
	addVkFormatDesc( ASTC_10x10_SRGB_BLOCK, ASTC_10x10_sRGB, Invalid, Invalid, Invalid, 10, 10, 16, Compressed );
	addVkFormatDesc( ASTC_12x10_UNORM_BLOCK, ASTC_12x10_LDR, Invalid, Invalid, Invalid, 12, 10, 16, Compressed );
	addVkFormatDesc( ASTC_12x10_SRGB_BLOCK, ASTC_12x10_sRGB, Invalid, Invalid, Invalid, 12, 10, 16, Compressed );
	addVkFormatDesc( ASTC_12x12_UNORM_BLOCK, ASTC_12x12_LDR, Invalid, Invalid, Invalid, 12, 12, 16, Compressed );
	addVkFormatDesc( ASTC_12x12_SRGB_BLOCK, ASTC_12x12_sRGB, Invalid, Invalid, Invalid, 12, 12, 16, Compressed );

	// Extension VK_IMG_format_pvrtc
	addVkFormatDesc( PVRTC1_2BPP_UNORM_BLOCK_IMG, PVRTC_RGBA_2BPP, Invalid, Invalid, Invalid, 8, 4, 8, Compressed );
	addVkFormatDesc( PVRTC1_4BPP_UNORM_BLOCK_IMG, PVRTC_RGBA_4BPP, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( PVRTC2_2BPP_UNORM_BLOCK_IMG, Invalid, Invalid, Invalid, Invalid, 8, 4, 8, Compressed );
	addVkFormatDesc( PVRTC2_4BPP_UNORM_BLOCK_IMG, Invalid, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( PVRTC1_2BPP_SRGB_BLOCK_IMG, PVRTC_RGBA_2BPP_sRGB, Invalid, Invalid, Invalid, 8, 4, 8, Compressed );
	addVkFormatDesc( PVRTC1_4BPP_SRGB_BLOCK_IMG, PVRTC_RGBA_4BPP_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );
	addVkFormatDesc( PVRTC2_2BPP_SRGB_BLOCK_IMG, Invalid, Invalid, Invalid, Invalid, 8, 4, 8, Compressed );
	addVkFormatDesc( PVRTC2_4BPP_SRGB_BLOCK_IMG, Invalid, Invalid, Invalid, Invalid, 4, 4, 8, Compressed );

	// Future extension VK_KHX_color_conversion and Vulkan 1.1.
	addVkFormatDesc( UNDEFINED, GBGR422, Invalid, Invalid, Invalid, 2, 1, 4, ColorFloat );
	addVkFormatDesc( UNDEFINED, BGRG422, Invalid, Invalid, Invalid, 2, 1, 4, ColorFloat );

	// When adding to this list, be sure to ensure _vkFormatCount is large enough for the format count
}

#define addMTLPixelFormatDesc(MTL_FMT, IOS_CAPS, MACOS_CAPS)  \
	MVKAssert(fmtIdx < _mtlPixelFormatCount, "Attempting to describe %d MTLPixelFormats, but only have space for %d. Increase the value of _mtlPixelFormatCount", fmtIdx + 1, _mtlPixelFormatCount);  \
	_mtlPixelFormatDescriptions[fmtIdx++] = { .mtlPixelFormat = MTLPixelFormat ##MTL_FMT, VK_FORMAT_UNDEFINED,  \
											  mvkSelectPlatformValue<MVKMTLFmtCaps>(kMVKMTLFmtCaps ##MACOS_CAPS, kMVKMTLFmtCaps ##IOS_CAPS),  \
											  "MTLPixelFormat" #MTL_FMT }

void MVKPixelFormats::initMTLPixelFormatCapabilities() {

	mvkClear(_mtlPixelFormatDescriptions, _mtlPixelFormatCount);

	uint32_t fmtIdx = 0;

	// When adding to this list, be sure to ensure _mtlPixelFormatCount is large enough for the format count

	// MTLPixelFormatInvalid must come first.
	addMTLPixelFormatDesc( Invalid, None, None );

	// Ordinary 8-bit pixel formats
	addMTLPixelFormatDesc( A8Unorm, RF, RF );
	addMTLPixelFormatDesc( R8Unorm, All, All );
	addMTLPixelFormatDesc( R8Unorm_sRGB, RFCMRB, None );
	addMTLPixelFormatDesc( R8Snorm, RFWCMB, All );
	addMTLPixelFormatDesc( R8Uint, RWCM, RWCM );
	addMTLPixelFormatDesc( R8Sint, RWCM, RWCM );

	// Ordinary 16-bit pixel formats
	addMTLPixelFormatDesc( R16Unorm, RFWCMB, All );
	addMTLPixelFormatDesc( R16Snorm, RFWCMB, All );
	addMTLPixelFormatDesc( R16Uint, RWCM, RWCM );
	addMTLPixelFormatDesc( R16Sint, RWCM, RWCM );
	addMTLPixelFormatDesc( R16Float, All, All );

	addMTLPixelFormatDesc( RG8Unorm, All, All );
	addMTLPixelFormatDesc( RG8Unorm_sRGB, RFCMRB, None );
	addMTLPixelFormatDesc( RG8Snorm, RFWCMB, All );
	addMTLPixelFormatDesc( RG8Uint, RWCM, RWCM );
	addMTLPixelFormatDesc( RG8Sint, RWCM, RWCM );

	// Packed 16-bit pixel formats
	addMTLPixelFormatDesc( B5G6R5Unorm, RFCMRB, None );
	addMTLPixelFormatDesc( A1BGR5Unorm, RFCMRB, None );
	addMTLPixelFormatDesc( ABGR4Unorm, RFCMRB, None );
	addMTLPixelFormatDesc( BGR5A1Unorm, RFCMRB, None );

	// Ordinary 32-bit pixel formats
	addMTLPixelFormatDesc( R32Uint, RC, RWCM );
	addMTLPixelFormatDesc( R32Sint, RC, RWCM );
	addMTLPixelFormatDesc( R32Float, RCMB, All );

	addMTLPixelFormatDesc( RG16Unorm, RFWCMB, All );
	addMTLPixelFormatDesc( RG16Snorm, RFWCMB, All );
	addMTLPixelFormatDesc( RG16Uint, RWCM, RWCM );
	addMTLPixelFormatDesc( RG16Sint, RWCM, RWCM );
	addMTLPixelFormatDesc( RG16Float, All, All );

	addMTLPixelFormatDesc( RGBA8Unorm, All, All );
	addMTLPixelFormatDesc( RGBA8Unorm_sRGB, RFCMRB, RFCMRB );
	addMTLPixelFormatDesc( RGBA8Snorm, RFWCMB, All );
	addMTLPixelFormatDesc( RGBA8Uint, RWCM, RWCM );
	addMTLPixelFormatDesc( RGBA8Sint, RWCM, RWCM );

	addMTLPixelFormatDesc( BGRA8Unorm, All, All );
	addMTLPixelFormatDesc( BGRA8Unorm_sRGB, RFCMRB, RFCMRB );

	// Packed 32-bit pixel formats
	addMTLPixelFormatDesc( RGB10A2Unorm, RFCMRB, All );
	addMTLPixelFormatDesc( RGB10A2Uint, RCM, RWCM );
	addMTLPixelFormatDesc( RG11B10Float, RFCMRB, All );
	addMTLPixelFormatDesc( RGB9E5Float, RFCMRB, RF );

	// Ordinary 64-bit pixel formats
	addMTLPixelFormatDesc( RG32Uint, RC, RWCM );
	addMTLPixelFormatDesc( RG32Sint, RC, RWCM );
	addMTLPixelFormatDesc( RG32Float, RCB, All );

	addMTLPixelFormatDesc( RGBA16Unorm, RFWCMB, All );
	addMTLPixelFormatDesc( RGBA16Snorm, RFWCMB, All );
	addMTLPixelFormatDesc( RGBA16Uint, RWCM, RWCM );
	addMTLPixelFormatDesc( RGBA16Sint, RWCM, RWCM );
	addMTLPixelFormatDesc( RGBA16Float, All, All );

	// Ordinary 128-bit pixel formats
	addMTLPixelFormatDesc( RGBA32Uint, RC, RWCM );
	addMTLPixelFormatDesc( RGBA32Sint, RC, RWCM );
	addMTLPixelFormatDesc( RGBA32Float, RC, All );

	// Compressed pixel formats
	addMTLPixelFormatDesc( PVRTC_RGBA_2BPP, RF, None );
	addMTLPixelFormatDesc( PVRTC_RGBA_4BPP, RF, None );
	addMTLPixelFormatDesc( PVRTC_RGBA_2BPP_sRGB, RF, None );
	addMTLPixelFormatDesc( PVRTC_RGBA_4BPP_sRGB, RF, None );

	addMTLPixelFormatDesc( ETC2_RGB8, RF, None );
	addMTLPixelFormatDesc( ETC2_RGB8_sRGB, RF, None );
	addMTLPixelFormatDesc( ETC2_RGB8A1, RF, None );
	addMTLPixelFormatDesc( ETC2_RGB8A1_sRGB, RF, None );
	addMTLPixelFormatDesc( EAC_RGBA8, RF, None );
	addMTLPixelFormatDesc( EAC_RGBA8_sRGB, RF, None );
	addMTLPixelFormatDesc( EAC_R11Unorm, RF, None );
	addMTLPixelFormatDesc( EAC_R11Snorm, RF, None );
	addMTLPixelFormatDesc( EAC_RG11Unorm, RF, None );
	addMTLPixelFormatDesc( EAC_RG11Snorm, RF, None );

	addMTLPixelFormatDesc( ASTC_4x4_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_4x4_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_5x4_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_5x4_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_5x5_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_5x5_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_6x5_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_6x5_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_6x6_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_6x6_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_8x5_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_8x5_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_8x6_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_8x6_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_8x8_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_8x8_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_10x5_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_10x5_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_10x6_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_10x6_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_10x8_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_10x8_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_10x10_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_10x10_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_12x10_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_12x10_sRGB, None, None );
	addMTLPixelFormatDesc( ASTC_12x12_LDR, None, None );
	addMTLPixelFormatDesc( ASTC_12x12_sRGB, None, None );

	addMTLPixelFormatDesc( BC1_RGBA, None, RF );
	addMTLPixelFormatDesc( BC1_RGBA_sRGB, None, RF );
	addMTLPixelFormatDesc( BC1_RGBA, None, RF );
	addMTLPixelFormatDesc( BC1_RGBA_sRGB, None, RF );
	addMTLPixelFormatDesc( BC2_RGBA, None, RF );
	addMTLPixelFormatDesc( BC2_RGBA_sRGB, None, RF );
	addMTLPixelFormatDesc( BC3_RGBA, None, RF );
	addMTLPixelFormatDesc( BC3_RGBA_sRGB, None, RF );
	addMTLPixelFormatDesc( BC4_RUnorm, None, RF );
	addMTLPixelFormatDesc( BC4_RSnorm, None, RF );
	addMTLPixelFormatDesc( BC5_RGUnorm, None, RF );
	addMTLPixelFormatDesc( BC5_RGSnorm, None, RF );
	addMTLPixelFormatDesc( BC6H_RGBUfloat, None, RF );
	addMTLPixelFormatDesc( BC6H_RGBFloat, None, RF );
	addMTLPixelFormatDesc( BC7_RGBAUnorm, None, RF );
	addMTLPixelFormatDesc( BC7_RGBAUnorm_sRGB, None, RF );

	// YUV pixel formats
	addMTLPixelFormatDesc( GBGR422, RF, RF );
	addMTLPixelFormatDesc( BGRG422, RF, RF );

	// Depth and stencil pixel formats
	addMTLPixelFormatDesc( Depth16Unorm, None, None );
	addMTLPixelFormatDesc( Depth32Float, DRM, DRFMR );
	addMTLPixelFormatDesc( Stencil8, DRM, DRM );
	addMTLPixelFormatDesc( Depth24Unorm_Stencil8, None, None );
	addMTLPixelFormatDesc( Depth32Float_Stencil8, DRM, DRFMR );
	addMTLPixelFormatDesc( X24_Stencil8, None, DRM );
	addMTLPixelFormatDesc( X32_Stencil8, DRM, DRM );

	// Extended range and wide color pixel formats
	addMTLPixelFormatDesc( BGRA10_XR, None, None );
	addMTLPixelFormatDesc( BGRA10_XR_sRGB, None, None );
	addMTLPixelFormatDesc( BGR10_XR, None, None );
	addMTLPixelFormatDesc( BGR10_XR_sRGB, None, None );
	addMTLPixelFormatDesc( BGR10A2Unorm, None, None );

	// When adding to this list, be sure to ensure _mtlPixelFormatCount is large enough for the format count
}

#define addMTLVertexFormatDesc(MTL_VTX_FMT, IOS_CAPS, MACOS_CAPS)  \
	MVKAssert(fmtIdx < _mtlVertexFormatCount, "Attempting to describe %d MTLVertexFormats, but only have space for %d. Increase the value of _mtlVertexFormatCount", fmtIdx + 1, _mtlVertexFormatCount);  \
	_mtlVertexFormatDescriptions[fmtIdx++] = { .mtlVertexFormat = MTLVertexFormat ##MTL_VTX_FMT, VK_FORMAT_UNDEFINED,  \
                                               mvkSelectPlatformValue<MVKMTLFmtCaps>(kMVKMTLFmtCaps ##MACOS_CAPS, kMVKMTLFmtCaps ##IOS_CAPS),  \
                                               "MTLVertexFormat" #MTL_VTX_FMT }

void MVKPixelFormats::initMTLVertexFormatCapabilities() {

	mvkClear(_mtlVertexFormatDescriptions, _mtlVertexFormatCount);

	uint32_t fmtIdx = 0;

	// When adding to this list, be sure to ensure _mtlVertexFormatCount is large enough for the format count
	// MTLVertexFormatInvalid must come first.
	addMTLVertexFormatDesc( Invalid, None, None );

	addMTLVertexFormatDesc( UChar2Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( Char2Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( UChar2, Vertex, Vertex );
	addMTLVertexFormatDesc( Char2, Vertex, Vertex );

	addMTLVertexFormatDesc( UChar3Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( Char3Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( UChar3, Vertex, Vertex );
	addMTLVertexFormatDesc( Char3, Vertex, Vertex );

	addMTLVertexFormatDesc( UChar4Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( Char4Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( UChar4, Vertex, Vertex );
	addMTLVertexFormatDesc( Char4, Vertex, Vertex );

	addMTLVertexFormatDesc( UInt1010102Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( Int1010102Normalized, Vertex, Vertex );

	addMTLVertexFormatDesc( UShort2Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( Short2Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( UShort2, Vertex, Vertex );
	addMTLVertexFormatDesc( Short2, Vertex, Vertex );
	addMTLVertexFormatDesc( Half2, Vertex, Vertex );

	addMTLVertexFormatDesc( UShort3Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( Short3Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( UShort3, Vertex, Vertex );
	addMTLVertexFormatDesc( Short3, Vertex, Vertex );
	addMTLVertexFormatDesc( Half3, Vertex, Vertex );

	addMTLVertexFormatDesc( UShort4Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( Short4Normalized, Vertex, Vertex );
	addMTLVertexFormatDesc( UShort4, Vertex, Vertex );
	addMTLVertexFormatDesc( Short4, Vertex, Vertex );
	addMTLVertexFormatDesc( Half4, Vertex, Vertex );

	addMTLVertexFormatDesc( UInt, Vertex, Vertex );
	addMTLVertexFormatDesc( Int, Vertex, Vertex );
	addMTLVertexFormatDesc( Float, Vertex, Vertex );

	addMTLVertexFormatDesc( UInt2, Vertex, Vertex );
	addMTLVertexFormatDesc( Int2, Vertex, Vertex );
	addMTLVertexFormatDesc( Float2, Vertex, Vertex );

	addMTLVertexFormatDesc( UInt3, Vertex, Vertex );
	addMTLVertexFormatDesc( Int3, Vertex, Vertex );
	addMTLVertexFormatDesc( Float3, Vertex, Vertex );

	addMTLVertexFormatDesc( UInt4, Vertex, Vertex );
	addMTLVertexFormatDesc( Int4, Vertex, Vertex );
	addMTLVertexFormatDesc( Float4, Vertex, Vertex );

	addMTLVertexFormatDesc( UCharNormalized, None, None );
	addMTLVertexFormatDesc( CharNormalized, None, None );
	addMTLVertexFormatDesc( UChar, None, None );
	addMTLVertexFormatDesc( Char, None, None );

	addMTLVertexFormatDesc( UShortNormalized, None, None );
	addMTLVertexFormatDesc( ShortNormalized, None, None );
	addMTLVertexFormatDesc( UShort, None, None );
	addMTLVertexFormatDesc( Short, None, None );
	addMTLVertexFormatDesc( Half, None, None );

	addMTLVertexFormatDesc( UChar4Normalized_BGRA, None, None );

	// When adding to this list, be sure to ensure _mtlVertexFormatCount is large enough for the format count
}

// Populates the Metal lookup maps
void MVKPixelFormats::buildMTLFormatMaps() {

	// Set all MTLPixelFormats and MTLVertexFormats to undefined/invalid
	mvkClear(_mtlFormatDescIndicesByMTLPixelFormats, _mtlPixelFormatCount);
	mvkClear(_mtlFormatDescIndicesByMTLVertexFormats, _mtlVertexFormatCount);

	// Build lookup table for MTLPixelFormat specs
	for (uint32_t fmtIdx = 0; fmtIdx < _mtlPixelFormatCount; fmtIdx++) {
		MTLPixelFormat fmt = _mtlPixelFormatDescriptions[fmtIdx].mtlPixelFormat;
		if (fmt) { _mtlFormatDescIndicesByMTLPixelFormats[fmt] = fmtIdx; }
	}

	// Build lookup table for MTLVertexFormat specs
	for (uint32_t fmtIdx = 0; fmtIdx < _mtlVertexFormatCount; fmtIdx++) {
		MTLVertexFormat fmt = _mtlVertexFormatDescriptions[fmtIdx].mtlVertexFormat;
		if (fmt) { _mtlFormatDescIndicesByMTLVertexFormats[fmt] = fmtIdx; }
	}
}

// If the device supports the feature set, add additional capabilities to a MTLPixelFormat
void MVKPixelFormats::addMTLPixelFormatCapabilities(id<MTLDevice> mtlDevice,
													MTLFeatureSet mtlFeatSet,
													MTLPixelFormat mtlPixFmt,
													MVKMTLFmtCaps mtlFmtCaps) {
	if ( [mtlDevice supportsFeatureSet: mtlFeatSet] ) {
		mvkEnableFlags(getMTLPixelFormatDesc(mtlPixFmt).mtlFmtCaps, mtlFmtCaps);
	}
}

// If the device supports the feature set, add additional capabilities to a MTLVertexFormat
void MVKPixelFormats::addMTLVertexFormatCapabilities(id<MTLDevice> mtlDevice,
													 MTLFeatureSet mtlFeatSet,
													 MTLVertexFormat mtlVtxFmt,
													 MVKMTLFmtCaps mtlFmtCaps) {
	if ( [mtlDevice supportsFeatureSet: mtlFeatSet] ) {
		mvkEnableFlags(getMTLVertexFormatDesc(mtlVtxFmt).mtlFmtCaps, mtlFmtCaps);
	}
}

// If supporting a physical device, retrieve the MTLDevice from it,
// otherwise create a temp copy of the system default MTLDevice.
void MVKPixelFormats::modifyMTLFormatCapabilities() {
	if (_physicalDevice) {
		modifyMTLFormatCapabilities(_physicalDevice->getMTLDevice());
	} else {
		id<MTLDevice> mtlDevice = MTLCreateSystemDefaultDevice();	// temp retained
		modifyMTLFormatCapabilities(mtlDevice);
		[mtlDevice release];										// release temp instance
	}
}

#define addMTLPixelFormatCapabilities(FEAT_SET, MTL_FMT, CAPS)  \
	addMTLPixelFormatCapabilities(mtlDevice, MTLFeatureSet_ ##FEAT_SET, MTLPixelFormat ##MTL_FMT, kMVKMTLFmtCaps ##CAPS)

#define addMTLVertexFormatCapabilities(FEAT_SET, MTL_FMT, CAPS)  \
	addMTLVertexFormatCapabilities(mtlDevice, MTLFeatureSet_ ##FEAT_SET, MTLVertexFormat ##MTL_FMT, kMVKMTLFmtCaps ##CAPS)

// Modifies the format capability tables based on the capabilities of the specific MTLDevice
#if MVK_MACOS
void MVKPixelFormats::modifyMTLFormatCapabilities(id<MTLDevice> mtlDevice) {

	addMTLPixelFormatCapabilities( macOS_GPUFamily1_v1, R32Uint, Atomic );
	addMTLPixelFormatCapabilities( macOS_GPUFamily1_v1, R32Sint, Atomic );

	if (mtlDevice.isDepth24Stencil8PixelFormatSupported) {
		addMTLPixelFormatCapabilities( macOS_GPUFamily1_v1, Depth24Unorm_Stencil8, DRFMR );
	}

	addMTLPixelFormatCapabilities( macOS_GPUFamily1_v2, Depth16Unorm, DRFMR );

	addMTLPixelFormatCapabilities( macOS_GPUFamily1_v3, BGR10A2Unorm, RFCMRB );

	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UCharNormalized, Vertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, CharNormalized, Vertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UChar, Vertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, Char, Vertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UShortNormalized, Vertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, ShortNormalized, Vertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UShort, Vertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, Short, Vertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, Half, Vertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UChar4Normalized_BGRA, Vertex );
}
#endif
#if MVK_IOS
void MVKPixelFormats::modifyMTLFormatCapabilities(id<MTLDevice> mtlDevice) {
	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v3, R8Unorm_sRGB, All );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, R8Unorm_sRGB, All );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v1, R8Snorm, All );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v3, RG8Unorm_sRGB, All );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RG8Unorm_sRGB, All );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v1, RG8Snorm, All );

	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, R32Uint, RWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, R32Uint, Atomic );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, R32Sint, RWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, R32Sint, Atomic );

	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, R32Float, RWCMB );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v3, RGBA8Unorm_sRGB, All );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RGBA8Unorm_sRGB, All );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v1, RGBA8Snorm, All );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v3, BGRA8Unorm_sRGB, All );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, BGRA8Unorm_sRGB, All );

	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RGB10A2Unorm, All );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RGB10A2Uint, RWCM );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RG11B10Float, All );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RGB9E5Float, All );

	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RG32Uint, RWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RG32Sint, RWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RG32Float, RWCB );

	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RGBA32Uint, RWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RGBA32Sint, RWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RGBA32Float, RWC );

	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_4x4_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_4x4_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_5x4_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_5x4_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_5x5_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_5x5_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_6x5_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_6x5_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_6x6_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_6x6_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x5_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x5_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x6_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x6_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x8_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x8_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x5_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x5_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x6_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x6_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x8_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x8_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x10_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x10_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_12x10_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_12x10_sRGB, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_12x12_LDR, RF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_12x12_sRGB, RF );

	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, Depth32Float, DRMR );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, Depth32Float_Stencil8, DRMR );

	addMTLPixelFormatCapabilities(iOS_GPUFamily3_v2, BGRA10_XR, All );
	addMTLPixelFormatCapabilities(iOS_GPUFamily3_v2, BGRA10_XR_sRGB, All );
	addMTLPixelFormatCapabilities(iOS_GPUFamily3_v2, BGR10_XR, All );
	addMTLPixelFormatCapabilities(iOS_GPUFamily3_v2, BGR10_XR_sRGB, All );

	addMTLPixelFormatCapabilities(iOS_GPUFamily1_v4, BGR10A2Unorm, All );

	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UCharNormalized, Vertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, CharNormalized, Vertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UChar, Vertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, Char, Vertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UShortNormalized, Vertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, ShortNormalized, Vertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UShort, Vertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, Short, Vertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, Half, Vertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UChar4Normalized_BGRA, Vertex );
}
#endif
#undef addMTLPixelFormatCapabilities
#undef addMTLVertexFormatCapabilities

// Populates the VkFormat lookup maps and connects Vulkan and Metal pixel formats to one-another.
void MVKPixelFormats::buildVkFormatMaps() {

	// Set the VkFormats to undefined/invalid
	mvkClear(_vkFormatDescIndicesByVkFormatsCore, _vkFormatCoreCount);

	// Iterate through the VkFormat descriptions, populate the lookup maps and back pointers,
	// and validate the Metal formats for the platform and OS.
	for (uint32_t fmtIdx = 0; fmtIdx < _vkFormatCount; fmtIdx++) {
		MVKVkFormatDesc& vkDesc = _vkFormatDescriptions[fmtIdx];
		VkFormat vkFmt = vkDesc.vkFormat;
		if (vkFmt) {
			// Create a lookup between the Vulkan format and an index to the format info.
			// For core Vulkan format values, which are small and consecutive, use a simple lookup array.
			// For extension format values, which can be large, use a map.
			if (vkFmt < _vkFormatCoreCount) {
				_vkFormatDescIndicesByVkFormatsCore[vkFmt] = fmtIdx;
			} else {
				_vkFormatDescIndicesByVkFormatsExt[vkFmt] = fmtIdx;
			}

			// Populate the back reference from the Metal formats to the Vulkan format.
			// Validate the corresponding Metal formats for the platform, and clear them
			// in the Vulkan format if not supported.
			if (vkDesc.mtlPixelFormat) {
				auto& mtlDesc = getMTLPixelFormatDesc(vkDesc.mtlPixelFormat);
				if ( !mtlDesc.vkFormat ) { mtlDesc.vkFormat = vkFmt; }
				if ( !mtlDesc.isSupported() ) { vkDesc.mtlPixelFormat = MTLPixelFormatInvalid; }
			}
			if (vkDesc.mtlPixelFormatSubstitute) {
				auto& mtlDesc = getMTLPixelFormatDesc(vkDesc.mtlPixelFormatSubstitute);
				if ( !mtlDesc.isSupported() ) { vkDesc.mtlPixelFormatSubstitute = MTLPixelFormatInvalid; }
			}
			if (vkDesc.mtlVertexFormat) {
				auto& mtlDesc = getMTLVertexFormatDesc(vkDesc.mtlVertexFormat);
				if ( !mtlDesc.vkFormat ) { mtlDesc.vkFormat = vkFmt; }
				if ( !mtlDesc.isSupported() ) { vkDesc.mtlVertexFormat = MTLVertexFormatInvalid; }
			}
			if (vkDesc.mtlVertexFormatSubstitute) {
				auto& mtlDesc = getMTLVertexFormatDesc(vkDesc.mtlVertexFormatSubstitute);
				if ( !mtlDesc.isSupported() ) { vkDesc.mtlVertexFormatSubstitute = MTLVertexFormatInvalid; }
			}

			// Set Vulkan format properties
			setFormatProperties(vkDesc);
		}
	}
}

// Enumeration of Vulkan format features aligned to the MVKMTLFmtCaps enumeration.
typedef enum : VkFormatFeatureFlags {
	kMVKVkFormatFeatureFlagsTexNone     = 0,
	kMVKVkFormatFeatureFlagsTexRead     = (VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT |
										   VK_FORMAT_FEATURE_TRANSFER_SRC_BIT |
										   VK_FORMAT_FEATURE_TRANSFER_DST_BIT |
										   VK_FORMAT_FEATURE_BLIT_SRC_BIT),
	kMVKVkFormatFeatureFlagsTexFilter   = (VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT),
	kMVKVkFormatFeatureFlagsTexWrite    = (VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT),
	kMVKVkFormatFeatureFlagsTexAtomic   = (VK_FORMAT_FEATURE_STORAGE_IMAGE_ATOMIC_BIT),
	kMVKVkFormatFeatureFlagsTexColorAtt = (VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT |
										   VK_FORMAT_FEATURE_BLIT_DST_BIT),
	kMVKVkFormatFeatureFlagsTexDSAtt    = (VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT),
	kMVKVkFormatFeatureFlagsTexBlend    = (VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND_BIT),
	kMVKVkFormatFeatureFlagsBufRead     = (VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT),
	kMVKVkFormatFeatureFlagsBufWrite    = (VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT),
	kMVKVkFormatFeatureFlagsBufAtomic   = (VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_ATOMIC_BIT),
	kMVKVkFormatFeatureFlagsBufVertex   = (VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT),
} MVKVkFormatFeatureFlags;

// Sets the VkFormatProperties (optimal/linear/buffer) for the Vulkan format.
void MVKPixelFormats::setFormatProperties(MVKVkFormatDesc& vkDesc) {

#	define enableFormatFeatures(CAP, TYPE, MTL_FMT_CAPS, VK_FEATS)        \
	if (mvkAreAllFlagsEnabled(MTL_FMT_CAPS, kMVKMTLFmtCaps ##CAP)) {      \
		mvkEnableFlags(VK_FEATS, kMVKVkFormatFeatureFlags ##TYPE ##CAP);  \
	}

	VkFormat vkFmt = vkDesc.vkFormat;
	VkFormatProperties& vkProps = vkDesc.properties;
	MVKMTLFmtCaps mtlPixFmtCaps = getMTLPixelFormatDesc(vkFmt).mtlFmtCaps;

	// Set optimal tiling features first
	vkProps.optimalTilingFeatures = kMVKVkFormatFeatureFlagsTexNone;
	enableFormatFeatures(Read, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(Filter, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(Write, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(ColorAtt, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(DSAtt, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(Blend, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);

	// Linear tiling is not available to depth/stencil or compressed formats.
	vkProps.linearTilingFeatures = kMVKVkFormatFeatureFlagsTexNone;
	if ( !(vkDesc.formatType == kMVKFormatDepthStencil || vkDesc.formatType == kMVKFormatCompressed) ) {

		// Start with optimal tiling features, and modify.
		vkProps.linearTilingFeatures = vkProps.optimalTilingFeatures;

		// Linear tiling can support atomic writing for some formats, even though optimal tiling does not.
		enableFormatFeatures(Atomic, Tex, mtlPixFmtCaps, vkProps.linearTilingFeatures);

#if MVK_MACOS
		// On macOS, linear textures cannot be used as attachments, so disable those features.
		mvkDisableFlags(vkProps.linearTilingFeatures, (kMVKVkFormatFeatureFlagsTexColorAtt |
													   kMVKVkFormatFeatureFlagsTexDSAtt |
													   kMVKVkFormatFeatureFlagsTexBlend));
#endif
	}

	// Texel buffers are not available to depth/stencil or compressed formats.
	vkProps.bufferFeatures = kMVKVkFormatFeatureFlagsTexNone;
	if ( !(vkDesc.formatType == kMVKFormatDepthStencil || vkDesc.formatType == kMVKFormatCompressed) ) {
		enableFormatFeatures(Read, Buf, mtlPixFmtCaps, vkProps.bufferFeatures);
		enableFormatFeatures(Write, Buf, mtlPixFmtCaps, vkProps.bufferFeatures);
		enableFormatFeatures(Atomic, Buf, mtlPixFmtCaps, vkProps.bufferFeatures);
		enableFormatFeatures(Vertex, Buf, getMTLVertexFormatDesc(vkFmt).mtlFmtCaps, vkProps.bufferFeatures);
	}
}


#pragma mark -
#pragma mark Unit Testing

template<typename T>
void MVKPixelFormats::testFmt(const T v1, const T v2, const char* fmtName, const char* funcName) {
	MVKAssert(mvkAreEqual(&v1,&v2), "Results not equal for format %s on test %s.", fmtName, funcName);
}

void MVKPixelFormats::testProps(const VkFormatProperties p1, const VkFormatProperties p2, const char* fmtName) {
	MVKLogErrorIf(!mvkAreEqual(&p1, &p2),
				  "Properties not equal for format %s. "
				  "\n\tgetVkFormatProperties() linear %d, optimal %d, buffer %d. "
				  "\n\tmvkVkFormatProperties(): linear %d, optimal %d, buffer %d"
				  "\n\tdifference: linear %d, optimal %d, buffer %d", fmtName,
				  p1.linearTilingFeatures, p1.optimalTilingFeatures, p1.bufferFeatures,
				  p2.linearTilingFeatures, p2.optimalTilingFeatures, p2.bufferFeatures,
				  std::abs((int)p2.linearTilingFeatures - (int)p1.linearTilingFeatures),
				  std::abs((int)p2.optimalTilingFeatures - (int)p1.optimalTilingFeatures),
				  std::abs((int)p2.bufferFeatures - (int)p1.bufferFeatures));
}

// Validate the functionality of this class against the previous format data within MoltenVK.
// This is a temporary function to confirm that converting to using this class matches existing behaviour at first.
#define testFmt(V1, V2)	  testFmt(V1, V2, fd.name, #V1)
#define testProps(V1, V2)  testProps(V1, V2, fd.name)
void MVKPixelFormats::test() {
	if ( !_physicalDevice ) { return; }		// Don't test a static instance not associated with a physical device

	// If more than one GPU, only test the system default MTLDevice.
	// Can release system MTLDevice immediates because we are just comparing it's address.
	id<MTLDevice> sysMTLDvc = MTLCreateSystemDefaultDevice();		// temp retained
	[sysMTLDvc release];											// release temp instance
	if ( _physicalDevice->getMTLDevice() != sysMTLDvc ) { return; }

	MVKLogInfo("Starting testing formats");
	for (uint32_t fmtIdx = 0; fmtIdx < _vkFormatCount; fmtIdx++) {
		auto& fd = _vkFormatDescriptions[fmtIdx];
		VkFormat vkFmt = fd.vkFormat;
		MTLPixelFormat mtlFmt = fd.mtlPixelFormat;

		if (fd.vkFormat) {
			if (fd.isSupportedOrSubstitutable()) {
				MVKLogInfo("Testing %s", fd.name);

				testFmt(isSupported(vkFmt), mvkVkFormatIsSupported(vkFmt));
				testFmt(isSupported(mtlFmt), mvkMTLPixelFormatIsSupported(mtlFmt));
				testFmt(isDepthFormat(mtlFmt), mvkMTLPixelFormatIsDepthFormat(mtlFmt));
				testFmt(isStencilFormat(mtlFmt), mvkMTLPixelFormatIsStencilFormat(mtlFmt));
				testFmt(isPVRTCFormat(mtlFmt), mvkMTLPixelFormatIsPVRTCFormat(mtlFmt));
				testFmt(getFormatType(vkFmt), mvkFormatTypeFromVkFormat(vkFmt));
				testFmt(getFormatType(mtlFmt), mvkFormatTypeFromMTLPixelFormat(mtlFmt));
				testFmt(getMTLPixelFormat(vkFmt), mvkMTLPixelFormatFromVkFormat(vkFmt));
				testFmt(getVkFormat(mtlFmt), mvkVkFormatFromMTLPixelFormat(mtlFmt));
				testFmt(getBytesPerBlock(vkFmt), mvkVkFormatBytesPerBlock(vkFmt));
				testFmt(getBytesPerBlock(mtlFmt), mvkMTLPixelFormatBytesPerBlock(mtlFmt));
				testFmt(getBlockTexelSize(vkFmt), mvkVkFormatBlockTexelSize(vkFmt));
				testFmt(getBlockTexelSize(mtlFmt), mvkMTLPixelFormatBlockTexelSize(mtlFmt));
				testFmt(getBytesPerTexel(vkFmt), mvkVkFormatBytesPerTexel(vkFmt));
				testFmt(getBytesPerTexel(mtlFmt), mvkMTLPixelFormatBytesPerTexel(mtlFmt));
				testFmt(getBytesPerRow(vkFmt, 4), mvkVkFormatBytesPerRow(vkFmt, 4));
				testFmt(getBytesPerRow(mtlFmt, 4), mvkMTLPixelFormatBytesPerRow(mtlFmt, 4));
				testFmt(getBytesPerLayer(vkFmt, 256, 4), mvkVkFormatBytesPerLayer(vkFmt, 256, 4));
				testFmt(getBytesPerLayer(mtlFmt, 256, 4), mvkMTLPixelFormatBytesPerLayer(mtlFmt, 256, 4));
				testProps(getVkFormatProperties(vkFmt), mvkVkFormatProperties(vkFmt));
				testFmt(strcmp(getName(vkFmt), mvkVkFormatName(vkFmt)), 0);
				testFmt(strcmp(getName(mtlFmt), mvkMTLPixelFormatName(mtlFmt)), 0);
				testFmt(getMTLClearColor(VkClearValue(), vkFmt),
						mvkMTLClearColorFromVkClearValue(VkClearValue(), vkFmt));

				testFmt(getVkImageUsageFlags(MTLTextureUsageUnknown, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageUnknown, mtlFmt));
				testFmt(getVkImageUsageFlags(MTLTextureUsageShaderRead, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageShaderRead, mtlFmt));
				testFmt(getVkImageUsageFlags(MTLTextureUsageShaderWrite, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageShaderWrite, mtlFmt));
				testFmt(getVkImageUsageFlags(MTLTextureUsageRenderTarget, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageRenderTarget, mtlFmt));
				testFmt(getVkImageUsageFlags(MTLTextureUsagePixelFormatView, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsagePixelFormatView, mtlFmt));

				VkImageUsageFlags vkUsage;
				vkUsage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
				testFmt(getMTLTextureUsage(vkUsage, mtlFmt), mvkMTLTextureUsageFromVkImageUsageFlags(vkUsage, mtlFmt));

				vkUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_STORAGE_BIT;
				testFmt(getMTLTextureUsage(vkUsage, mtlFmt), mvkMTLTextureUsageFromVkImageUsageFlags(vkUsage, mtlFmt));

				testFmt(getMTLVertexFormat(vkFmt), mvkMTLVertexFormatFromVkFormat(vkFmt));

			} else {
				MVKLogInfo("%s not supported or substitutable on this device.", fd.name);
			}
		}
	}
	MVKLogInfo("Finished testing formats.\n");
}
#undef testFmt
#undef testProps
