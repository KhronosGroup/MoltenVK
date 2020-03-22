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

#include "mvk_datatypes.hpp"
#include "MVKPixelFormats.h"
#include "MVKVulkanAPIObject.h"
#include "MVKFoundation.h"
#include "MVKLogging.h"
#include <string>
#include <limits>

using namespace std;


#pragma mark -
#pragma mark Image properties

#define MVK_FMT_IMAGE_FEATS			(VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT                    \
									| VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT                   \
                                    | VK_FORMAT_FEATURE_BLIT_SRC_BIT                        \
									| VK_FORMAT_FEATURE_TRANSFER_SRC_BIT                    \
									| VK_FORMAT_FEATURE_TRANSFER_DST_BIT)

#define MVK_FMT_COLOR_INTEGER_FEATS	(MVK_FMT_IMAGE_FEATS                                    \
									| VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT                \
									| VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND_BIT          \
                                    | VK_FORMAT_FEATURE_BLIT_DST_BIT)

#define MVK_FMT_COLOR_FEATS			(MVK_FMT_COLOR_INTEGER_FEATS | VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)

#if MVK_IOS
// iOS does not support filtering of float32 values.
#	define MVK_FMT_COLOR_FLOAT32_FEATS	MVK_FMT_COLOR_INTEGER_FEATS
#else
#	define MVK_FMT_COLOR_FLOAT32_FEATS	MVK_FMT_COLOR_FEATS
#endif

#define MVK_FMT_STENCIL_FEATS		(MVK_FMT_IMAGE_FEATS | VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT)

#if MVK_IOS
// iOS does not support filtering of depth values.
#	define MVK_FMT_DEPTH_FEATS		MVK_FMT_STENCIL_FEATS
#else
#	define MVK_FMT_DEPTH_FEATS		(MVK_FMT_STENCIL_FEATS | VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)
#endif

#define MVK_FMT_COMPRESSED_FEATS	(VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT                    \
									| VK_FORMAT_FEATURE_TRANSFER_SRC_BIT                    \
									| VK_FORMAT_FEATURE_TRANSFER_DST_BIT                    \
									| VK_FORMAT_FEATURE_BLIT_SRC_BIT                        \
									| VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)

#if MVK_MACOS
// macOS does not support linear images as framebuffer attachments.
#define MVK_FMT_LINEAR_TILING_FEATS	(MVK_FMT_IMAGE_FEATS | VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)

// macOS also does not support E5B9G9R9 for anything but filtering.
#define MVK_FMT_E5B9G9R9_FEATS 		MVK_FMT_COMPRESSED_FEATS
#else
#define MVK_FMT_LINEAR_TILING_FEATS	MVK_FMT_COLOR_FEATS
#define MVK_FMT_E5B9G9R9_FEATS		MVK_FMT_COLOR_FEATS
#endif

#define MVK_FMT_BUFFER_FEATS		(VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT             \
									| VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT)

#define MVK_FMT_BUFFER_VTX_FEATS	(MVK_FMT_BUFFER_FEATS | VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT)

#define MVK_FMT_BUFFER_RDONLY_FEATS	(VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT)

#if MVK_MACOS
#define MVK_FMT_E5B9G9R9_BUFFER_FEATS 		MVK_FMT_BUFFER_RDONLY_FEATS
#else
#define MVK_FMT_E5B9G9R9_BUFFER_FEATS 		MVK_FMT_BUFFER_FEATS
#endif

#define MVK_FMT_NO_FEATS			0


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

bool MVKPixelFormats::vkFormatIsSupported(VkFormat vkFormat) {
	return getVkFormatDesc(vkFormat).isSupported();
}

bool MVKPixelFormats::mtlPixelFormatIsSupported(MTLPixelFormat mtlFormat) {
	return getMTLPixelFormatDesc(mtlFormat).isSupported();
}

bool MVKPixelFormats::mtlPixelFormatIsDepthFormat(MTLPixelFormat mtlFormat) {
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

bool MVKPixelFormats::mtlPixelFormatIsStencilFormat(MTLPixelFormat mtlFormat) {
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

bool MVKPixelFormats::mtlPixelFormatIsPVRTCFormat(MTLPixelFormat mtlFormat) {
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

MVKFormatType MVKPixelFormats::getFormatTypeFromVkFormat(VkFormat vkFormat) {
	return getVkFormatDesc(vkFormat).formatType;
}

MVKFormatType MVKPixelFormats::getFormatTypeFromMTLPixelFormat(MTLPixelFormat mtlFormat) {
	return getVkFormatDesc(mtlFormat).formatType;
}

MTLPixelFormat MVKPixelFormats::getMTLPixelFormatFromVkFormat(VkFormat vkFormat) {
	MTLPixelFormat mtlPixFmt = MTLPixelFormatInvalid;

	auto& vkDesc = getVkFormatDesc(vkFormat);
	if (vkDesc.isSupported()) {
		mtlPixFmt = vkDesc.mtlPixelFormat;
	} else if (vkFormat != VK_FORMAT_UNDEFINED) {
		// If the MTLPixelFormat is not supported but VkFormat is valid, attempt to substitute a different format.
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
			MVKBaseObject::reportError(_apiObject, VK_ERROR_FORMAT_NOT_SUPPORTED, "%s", errMsg.c_str());
		}
	}

	return mtlPixFmt;
}

VkFormat MVKPixelFormats::getVkFormatFromMTLPixelFormat(MTLPixelFormat mtlFormat) {
    return getMTLPixelFormatDesc(mtlFormat).vkFormat;
}

uint32_t MVKPixelFormats::getVkFormatBytesPerBlock(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).bytesPerBlock;
}

uint32_t MVKPixelFormats::getMTLPixelFormatBytesPerBlock(MTLPixelFormat mtlFormat) {
    return getVkFormatDesc(mtlFormat).bytesPerBlock;
}

VkExtent2D MVKPixelFormats::getVkFormatBlockTexelSize(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).blockTexelSize;
}

VkExtent2D MVKPixelFormats::getMTLPixelFormatBlockTexelSize(MTLPixelFormat mtlFormat) {
    return getVkFormatDesc(mtlFormat).blockTexelSize;
}

float MVKPixelFormats::getVkFormatBytesPerTexel(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).bytesPerTexel();
}

float MVKPixelFormats::getMTLPixelFormatBytesPerTexel(MTLPixelFormat mtlFormat) {
    return getVkFormatDesc(mtlFormat).bytesPerTexel();
}

size_t MVKPixelFormats::getVkFormatBytesPerRow(VkFormat vkFormat, uint32_t texelsPerRow) {
    auto& vkDesc = getVkFormatDesc(vkFormat);
    return mvkCeilingDivide(texelsPerRow, vkDesc.blockTexelSize.width) * vkDesc.bytesPerBlock;
}

size_t MVKPixelFormats::getMTLPixelFormatBytesPerRow(MTLPixelFormat mtlFormat, uint32_t texelsPerRow) {
	auto& vkDesc = getVkFormatDesc(mtlFormat);
    return mvkCeilingDivide(texelsPerRow, vkDesc.blockTexelSize.width) * vkDesc.bytesPerBlock;
}

size_t MVKPixelFormats::getVkFormatBytesPerLayer(VkFormat vkFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer) {
    return mvkCeilingDivide(texelRowsPerLayer, getVkFormatDesc(vkFormat).blockTexelSize.height) * bytesPerRow;
}

size_t MVKPixelFormats::getMTLPixelFormatBytesPerLayer(MTLPixelFormat mtlFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer) {
    return mvkCeilingDivide(texelRowsPerLayer, getVkFormatDesc(mtlFormat).blockTexelSize.height) * bytesPerRow;
}

VkFormatProperties MVKPixelFormats::getVkFormatProperties(VkFormat vkFormat) {
	VkFormatProperties fmtProps = {MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS};
	auto& vkDesc = getVkFormatDesc(vkFormat);
	if (vkDesc.isSupported()) {
		fmtProps = vkDesc.properties;
		if ( !vkDesc.vertexIsSupportedOrSubstitutable() ) {
			// If vertex format is not supported, disable vertex buffer bit
			fmtProps.bufferFeatures &= ~VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
		}
	} else {
		// If texture format is unsupported, vertex buffer format may still be.
		fmtProps.bufferFeatures |= vkDesc.properties.bufferFeatures & VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
	}
	return fmtProps;
}

const char* MVKPixelFormats::getVkFormatName(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).name;
}

const char* MVKPixelFormats::getMTLPixelFormatName(MTLPixelFormat mtlFormat) {
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

MTLVertexFormat MVKPixelFormats::getMTLVertexFormatFromVkFormat(VkFormat vkFormat) {
	MTLVertexFormat mtlVtxFmt = MTLVertexFormatInvalid;

	auto& vkDesc = getVkFormatDesc(vkFormat);
	if (vkDesc.vertexIsSupported()) {
		mtlVtxFmt = vkDesc.mtlVertexFormat;
	} else if (vkFormat != VK_FORMAT_UNDEFINED) {
		// If the MTLVertexFormat is not supported but VkFormat is valid,
		// report an error, and possibly substitute a different MTLVertexFormat.
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
		MVKBaseObject::reportError(_apiObject, VK_ERROR_FORMAT_NOT_SUPPORTED, "%s", errMsg.c_str());
	}

	return mtlVtxFmt;
}

MTLClearColor MVKPixelFormats::getMTLClearColorFromVkClearValue(VkClearValue vkClearValue,
														   VkFormat vkFormat) {
	MTLClearColor mtlClr;
	switch (getFormatTypeFromVkFormat(vkFormat)) {
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

double MVKPixelFormats::getMTLClearDepthFromVkClearValue(VkClearValue vkClearValue) {
	return vkClearValue.depthStencil.depth;
}

uint32_t MVKPixelFormats::getMTLClearStencilFromVkClearValue(VkClearValue vkClearValue) {
	return vkClearValue.depthStencil.stencil;
}

VkImageUsageFlags MVKPixelFormats::getVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsage mtlUsage,
																	  MTLPixelFormat mtlFormat) {
    VkImageUsageFlags vkImageUsageFlags = 0;

    if ( mvkAreAllFlagsEnabled(mtlUsage, MTLTextureUsageShaderRead) ) {
        mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_TRANSFER_SRC_BIT);
        mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_SAMPLED_BIT);
        mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT);
    }
    if ( mvkAreAllFlagsEnabled(mtlUsage, MTLTextureUsageRenderTarget) ) {
        mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_TRANSFER_DST_BIT);
        if (mtlPixelFormatIsDepthFormat(mtlFormat) || mtlPixelFormatIsStencilFormat(mtlFormat)) {
            mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT);
        } else {
            mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT);
        }
    }
    if ( mvkAreAllFlagsEnabled(mtlUsage, MTLTextureUsageShaderWrite) ) {
        mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_STORAGE_BIT);
    }

    return vkImageUsageFlags;
}

// Return a reference to the Vulkan format descriptor corresponding to the VkFormat.
MVKVkFormatDesc& MVKPixelFormats::getVkFormatDesc(VkFormat vkFormat) {
	uint16_t fmtIdx = (vkFormat < _vkFormatCoreCount) ? _vkFormatDescIndicesByVkFormatsCore[vkFormat] : _vkFormatDescIndicesByVkFormatsExt[vkFormat];
	return _vkFormatDescriptions[fmtIdx];
}

// Return a reference to the Metal format descriptor corresponding to the MTLPixelFormat.
MVKMTLFormatDesc& MVKPixelFormats::getMTLPixelFormatDesc(MTLPixelFormat mtlFormat) {
	uint16_t fmtIdx = (mtlFormat < _mtlPixelFormatCount) ? _mtlFormatDescIndicesByMTLPixelFormats[mtlFormat] : 0;
	return _mtlPixelFormatDescriptions[fmtIdx];
}

// Return a reference to the Metal format descriptor corresponding to the MTLVertexFormat.
MVKMTLFormatDesc& MVKPixelFormats::getMTLVertexFormatDesc(MTLVertexFormat mtlFormat) {
	uint16_t fmtIdx = (mtlFormat < _mtlVertexFormatCount) ? _mtlFormatDescIndicesByMTLVertexFormats[mtlFormat] : 0;
	return _mtlVertexFormatDescriptions[fmtIdx];
}

// Return a reference to the Vulkan format descriptor corresponding to the MTLPixelFormat.
MVKVkFormatDesc& MVKPixelFormats::getVkFormatDesc(MTLPixelFormat mtlFormat) {
	return getVkFormatDesc(getMTLPixelFormatDesc(mtlFormat).vkFormat);
}


#pragma mark Construction

MVKPixelFormats::MVKPixelFormats(MVKVulkanAPIObject* apiObject, id<MTLDevice> mtlDevice) : _apiObject(apiObject) {
	initVkFormatCapabilities();
	initMTLPixelFormatCapabilities();
	initMTLVertexFormatCapabilities();
	buildFormatMaps();
	modifyFormatCapabilitiesForMTLDevice(mtlDevice);
//	test();
}

static const MVKOSVersion kMTLFmtNA = numeric_limits<MVKOSVersion>::max();

#define addVkFormatDesc(VK_FMT, MTL_FMT, MTL_FMT_ALT, MTL_VTX_FMT, MTL_VTX_FMT_ALT, BLK_W, BLK_H, BLK_BYTE_CNT, MVK_FMT_TYPE, PIXEL_FEATS, BUFFER_FEATS)  \
	MVKAssert(fmtIdx < _vkFormatCount, "Attempting to describe %d VkFormats, but only have space for %d. Increase the value of _vkFormatCount", fmtIdx + 1, _vkFormatCount);  \
_vkFormatDescriptions[fmtIdx++] = { VK_FORMAT_ ##VK_FMT, MTLPixelFormat ##MTL_FMT, MTLPixelFormat ##MTL_FMT_ALT, MTLVertexFormat ##MTL_VTX_FMT, MTLVertexFormat ##MTL_VTX_FMT_ALT,  \
{ BLK_W, BLK_H }, BLK_BYTE_CNT, kMVKFormat ##MVK_FMT_TYPE, { (MVK_FMT_ ##PIXEL_FEATS & MVK_FMT_LINEAR_TILING_FEATS), MVK_FMT_ ##PIXEL_FEATS, MVK_FMT_ ##BUFFER_FEATS }, "VK_FORMAT_" #VK_FMT, false }

void MVKPixelFormats::initVkFormatCapabilities() {

	mvkClear(_vkFormatDescriptions, _vkFormatCount);

	uint32_t fmtIdx = 0;

	// When adding to this list, be sure to ensure _vkFormatCount is large enough for the format count
	// UNDEFINED must come first.
	addVkFormatDesc( UNDEFINED, Invalid, Invalid, Invalid, Invalid, 1, 1, 0, None, NO_FEATS, NO_FEATS );

	addVkFormatDesc( R4G4_UNORM_PACK8, Invalid, Invalid, Invalid, Invalid, 1, 1, 1, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R4G4B4A4_UNORM_PACK16, ABGR4Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_FEATS );
	addVkFormatDesc( B4G4R4A4_UNORM_PACK16, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, NO_FEATS, NO_FEATS );

	addVkFormatDesc( R5G6B5_UNORM_PACK16, B5G6R5Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_FEATS );
	addVkFormatDesc( B5G6R5_UNORM_PACK16, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R5G5B5A1_UNORM_PACK16, A1BGR5Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_FEATS );
	addVkFormatDesc( B5G5R5A1_UNORM_PACK16, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( A1R5G5B5_UNORM_PACK16, BGR5A1Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_FEATS );

	addVkFormatDesc( R8_UNORM, R8Unorm, Invalid, UCharNormalized, UChar2Normalized, 1, 1, 1, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8_SNORM, R8Snorm, Invalid, CharNormalized, Char2Normalized, 1, 1, 1, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 1, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 1, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R8_UINT, R8Uint, Invalid, UChar, UChar2, 1, 1, 1, ColorUInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8_SINT, R8Sint, Invalid, Char, Char2, 1, 1, 1, ColorInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8_SRGB, R8Unorm_sRGB, Invalid, UCharNormalized, UChar2Normalized, 1, 1, 1, ColorFloat, COLOR_FEATS, BUFFER_FEATS );

	addVkFormatDesc( R8G8_UNORM, RG8Unorm, Invalid, UChar2Normalized, Invalid, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8_SNORM, RG8Snorm, Invalid, Char2Normalized, Invalid, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R8G8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R8G8_UINT, RG8Uint, Invalid, UChar2, Invalid, 1, 1, 2, ColorUInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8_SINT, RG8Sint, Invalid, Char2, Invalid, 1, 1, 2, ColorInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8_SRGB, RG8Unorm_sRGB, Invalid, UChar2Normalized, Invalid, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_FEATS );

	addVkFormatDesc( R8G8B8_UNORM, Invalid, Invalid, UChar3Normalized, Invalid, 1, 1, 3, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8B8_SNORM, Invalid, Invalid, Char3Normalized, Invalid, 1, 1, 3, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8B8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R8G8B8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R8G8B8_UINT, Invalid, Invalid, UChar3, Invalid, 1, 1, 3, ColorUInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8B8_SINT, Invalid, Invalid, Char3, Invalid, 1, 1, 3, ColorInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8B8_SRGB, Invalid, Invalid, UChar3Normalized, Invalid, 1, 1, 3, ColorFloat, COLOR_FEATS, BUFFER_FEATS );

	addVkFormatDesc( B8G8R8_UNORM, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8_SNORM, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorUInt8, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorInt8, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8_SRGB, Invalid, Invalid, Invalid, Invalid, 1, 1, 3, ColorFloat, NO_FEATS, NO_FEATS );

	addVkFormatDesc( R8G8B8A8_UNORM, RGBA8Unorm, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8B8A8_SNORM, RGBA8Snorm, Invalid, Char4Normalized, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8B8A8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R8G8B8A8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R8G8B8A8_UINT, RGBA8Uint, Invalid, UChar4, Invalid, 1, 1, 4, ColorUInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8B8A8_SINT, RGBA8Sint, Invalid, Char4, Invalid, 1, 1, 4, ColorInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R8G8B8A8_SRGB, RGBA8Unorm_sRGB, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_FEATS );

	addVkFormatDesc( B8G8R8A8_UNORM, BGRA8Unorm, Invalid, UChar4Normalized_BGRA, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( B8G8R8A8_SNORM, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8A8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8A8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8A8_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorUInt8, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8A8_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorInt8, NO_FEATS, NO_FEATS );
	addVkFormatDesc( B8G8R8A8_SRGB, BGRA8Unorm_sRGB, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_FEATS );

	addVkFormatDesc( A8B8G8R8_UNORM_PACK32, RGBA8Unorm, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( A8B8G8R8_SNORM_PACK32, RGBA8Snorm, Invalid, Char4Normalized, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( A8B8G8R8_USCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( A8B8G8R8_SSCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( A8B8G8R8_UINT_PACK32, RGBA8Uint, Invalid, UChar4, Invalid, 1, 1, 4, ColorUInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( A8B8G8R8_SINT_PACK32, RGBA8Sint, Invalid, Char4, Invalid, 1, 1, 4, ColorInt8, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( A8B8G8R8_SRGB_PACK32, RGBA8Unorm_sRGB, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_FEATS );

	addVkFormatDesc( A2R10G10B10_UNORM_PACK32, BGR10A2Unorm, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_FEATS );
	addVkFormatDesc( A2R10G10B10_SNORM_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( A2R10G10B10_USCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( A2R10G10B10_SSCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( A2R10G10B10_UINT_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorUInt16, NO_FEATS, NO_FEATS );
	addVkFormatDesc( A2R10G10B10_SINT_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorInt16, NO_FEATS, NO_FEATS );

	addVkFormatDesc( A2B10G10R10_UNORM_PACK32, RGB10A2Unorm, Invalid, UInt1010102Normalized, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( A2B10G10R10_SNORM_PACK32, Invalid, Invalid, Int1010102Normalized, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( A2B10G10R10_USCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( A2B10G10R10_SSCALED_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( A2B10G10R10_UINT_PACK32, RGB10A2Uint, Invalid, Invalid, Invalid, 1, 1, 4, ColorUInt16, COLOR_INTEGER_FEATS, BUFFER_FEATS );
	addVkFormatDesc( A2B10G10R10_SINT_PACK32, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorInt16, NO_FEATS, NO_FEATS );

	addVkFormatDesc( R16_UNORM, R16Unorm, Invalid, UShortNormalized, UShort2Normalized, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16_SNORM, R16Snorm, Invalid, ShortNormalized, Short2Normalized, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R16_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R16_UINT, R16Uint, Invalid, UShort, UShort2, 1, 1, 2, ColorUInt16, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16_SINT, R16Sint, Invalid, Short, Short2, 1, 1, 2, ColorInt16, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16_SFLOAT, R16Float, Invalid, Half, Half2, 1, 1, 2, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );

	addVkFormatDesc( R16G16_UNORM, RG16Unorm, Invalid, UShort2Normalized, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16_SNORM, RG16Snorm, Invalid, Short2Normalized, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R16G16_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R16G16_UINT, RG16Uint, Invalid, UShort2, Invalid, 1, 1, 4, ColorUInt16, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16_SINT, RG16Sint, Invalid, Short2, Invalid, 1, 1, 4, ColorInt16, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16_SFLOAT, RG16Float, Invalid, Half2, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );

	addVkFormatDesc( R16G16B16_UNORM, Invalid, Invalid, UShort3Normalized, Invalid, 1, 1, 6, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16B16_SNORM, Invalid, Invalid, Short3Normalized, Invalid, 1, 1, 6, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16B16_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 6, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R16G16B16_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 6, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R16G16B16_UINT, Invalid, Invalid, UShort3, Invalid, 1, 1, 6, ColorUInt16, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16B16_SINT, Invalid, Invalid, Short3, Invalid, 1, 1, 6, ColorInt16, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16B16_SFLOAT, Invalid, Invalid, Half3, Invalid, 1, 1, 6, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );

	addVkFormatDesc( R16G16B16A16_UNORM, RGBA16Unorm, Invalid, UShort4Normalized, Invalid, 1, 1, 8, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16B16A16_SNORM, RGBA16Snorm, Invalid, Short4Normalized, Invalid, 1, 1, 8, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16B16A16_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R16G16B16A16_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R16G16B16A16_UINT, RGBA16Uint, Invalid, UShort4, Invalid, 1, 1, 8, ColorUInt16, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16B16A16_SINT, RGBA16Sint, Invalid, Short4, Invalid, 1, 1, 8, ColorInt16, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R16G16B16A16_SFLOAT, RGBA16Float, Invalid, Half4, Invalid, 1, 1, 8, ColorFloat, COLOR_FEATS, BUFFER_VTX_FEATS );

	addVkFormatDesc( R32_UINT, R32Uint, Invalid, UInt, Invalid, 1, 1, 4, ColorUInt32, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R32_SINT, R32Sint, Invalid, Int, Invalid, 1, 1, 4, ColorInt32, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R32_SFLOAT, R32Float, Invalid, Float, Invalid, 1, 1, 4, ColorFloat, COLOR_FLOAT32_FEATS, BUFFER_VTX_FEATS );

	addVkFormatDesc( R32G32_UINT, RG32Uint, Invalid, UInt2, Invalid, 1, 1, 8, ColorUInt32, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R32G32_SINT, RG32Sint, Invalid, Int2, Invalid, 1, 1, 8, ColorInt32, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R32G32_SFLOAT, RG32Float, Invalid, Float2, Invalid, 1, 1, 8, ColorFloat, COLOR_FLOAT32_FEATS, BUFFER_VTX_FEATS );

	addVkFormatDesc( R32G32B32_UINT, Invalid, Invalid, UInt3, Invalid, 1, 1, 12, ColorUInt32, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R32G32B32_SINT, Invalid, Invalid, Int3, Invalid, 1, 1, 12, ColorInt32, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R32G32B32_SFLOAT, Invalid, Invalid, Float3, Invalid, 1, 1, 12, ColorFloat, COLOR_FLOAT32_FEATS, BUFFER_VTX_FEATS );

	addVkFormatDesc( R32G32B32A32_UINT, RGBA32Uint, Invalid, UInt4, Invalid, 1, 1, 16, ColorUInt32, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R32G32B32A32_SINT, RGBA32Sint, Invalid, Int4, Invalid, 1, 1, 16, ColorInt32, COLOR_INTEGER_FEATS, BUFFER_VTX_FEATS );
	addVkFormatDesc( R32G32B32A32_SFLOAT, RGBA32Float, Invalid, Float4, Invalid, 1, 1, 16, ColorFloat, COLOR_FLOAT32_FEATS, BUFFER_VTX_FEATS );

	addVkFormatDesc( R64_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R64_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R64_SFLOAT, Invalid, Invalid, Invalid, Invalid, 1, 1, 8, ColorFloat, NO_FEATS, NO_FEATS );

	addVkFormatDesc( R64G64_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 16, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R64G64_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 16, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R64G64_SFLOAT, Invalid, Invalid, Invalid, Invalid, 1, 1, 16, ColorFloat, NO_FEATS, NO_FEATS );

	addVkFormatDesc( R64G64B64_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 24, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R64G64B64_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 24, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R64G64B64_SFLOAT, Invalid, Invalid, Invalid, Invalid, 1, 1, 24, ColorFloat, NO_FEATS, NO_FEATS );

	addVkFormatDesc( R64G64B64A64_UINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 32, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R64G64B64A64_SINT, Invalid, Invalid, Invalid, Invalid, 1, 1, 32, ColorFloat, NO_FEATS, NO_FEATS );
	addVkFormatDesc( R64G64B64A64_SFLOAT, Invalid, Invalid, Invalid, Invalid, 1, 1, 32, ColorFloat, NO_FEATS, NO_FEATS );

	addVkFormatDesc( B10G11R11_UFLOAT_PACK32, RG11B10Float, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_FEATS );
	addVkFormatDesc( E5B9G9R9_UFLOAT_PACK32, RGB9E5Float, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, E5B9G9R9_FEATS, E5B9G9R9_BUFFER_FEATS );

	addVkFormatDesc( D32_SFLOAT, Depth32Float, Invalid, Invalid, Invalid, 1, 1, 4, DepthStencil, DEPTH_FEATS, NO_FEATS );
	addVkFormatDesc( D32_SFLOAT_S8_UINT, Depth32Float_Stencil8, Invalid, Invalid, Invalid, 1, 1, 5, DepthStencil, DEPTH_FEATS, NO_FEATS );

	addVkFormatDesc( S8_UINT, Stencil8, Invalid, Invalid, Invalid, 1, 1, 1, DepthStencil, STENCIL_FEATS, NO_FEATS );

	addVkFormatDesc( D16_UNORM, Depth16Unorm, Depth32Float, Invalid, Invalid, 1, 1, 2, DepthStencil, DEPTH_FEATS, NO_FEATS );
	addVkFormatDesc( D16_UNORM_S8_UINT, Invalid, Depth16Unorm_Stencil8, Invalid, Invalid, 1, 1, 3, DepthStencil, DEPTH_FEATS, NO_FEATS );
	addVkFormatDesc( D24_UNORM_S8_UINT, Depth24Unorm_Stencil8, Depth32Float_Stencil8, Invalid, Invalid, 1, 1, 4, DepthStencil, DEPTH_FEATS, NO_FEATS );

	addVkFormatDesc( X8_D24_UNORM_PACK32, Invalid, Depth24Unorm_Stencil8, Invalid, Invalid, 1, 1, 4, DepthStencil, DEPTH_FEATS, NO_FEATS );

	addVkFormatDesc( BC1_RGB_UNORM_BLOCK, BC1_RGBA, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( BC1_RGB_SRGB_BLOCK, BC1_RGBA_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( BC1_RGBA_UNORM_BLOCK, BC1_RGBA, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( BC1_RGBA_SRGB_BLOCK, BC1_RGBA_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( BC2_UNORM_BLOCK, BC2_RGBA, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( BC2_SRGB_BLOCK, BC2_RGBA_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( BC3_UNORM_BLOCK, BC3_RGBA, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( BC3_SRGB_BLOCK, BC3_RGBA_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( BC4_UNORM_BLOCK, BC4_RUnorm, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( BC4_SNORM_BLOCK, BC4_RSnorm, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( BC5_UNORM_BLOCK, BC5_RGUnorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( BC5_SNORM_BLOCK, BC5_RGSnorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( BC6H_UFLOAT_BLOCK, BC6H_RGBUfloat, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( BC6H_SFLOAT_BLOCK, BC6H_RGBFloat, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( BC7_UNORM_BLOCK, BC7_RGBAUnorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( BC7_SRGB_BLOCK, BC7_RGBAUnorm_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( ETC2_R8G8B8_UNORM_BLOCK, ETC2_RGB8, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ETC2_R8G8B8_SRGB_BLOCK, ETC2_RGB8_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ETC2_R8G8B8A1_UNORM_BLOCK, ETC2_RGB8A1, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ETC2_R8G8B8A1_SRGB_BLOCK, ETC2_RGB8A1_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( ETC2_R8G8B8A8_UNORM_BLOCK, EAC_RGBA8, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ETC2_R8G8B8A8_SRGB_BLOCK, EAC_RGBA8_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( EAC_R11_UNORM_BLOCK, EAC_R11Unorm, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( EAC_R11_SNORM_BLOCK, EAC_R11Snorm, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( EAC_R11G11_UNORM_BLOCK, EAC_RG11Unorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( EAC_R11G11_SNORM_BLOCK, EAC_RG11Snorm, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );

	addVkFormatDesc( ASTC_4x4_UNORM_BLOCK, ASTC_4x4_LDR, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_4x4_SRGB_BLOCK, ASTC_4x4_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_5x4_UNORM_BLOCK, ASTC_5x4_LDR, Invalid, Invalid, Invalid, 5, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_5x4_SRGB_BLOCK, ASTC_5x4_sRGB, Invalid, Invalid, Invalid, 5, 4, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_5x5_UNORM_BLOCK, ASTC_5x5_LDR, Invalid, Invalid, Invalid, 5, 5, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_5x5_SRGB_BLOCK, ASTC_5x5_sRGB, Invalid, Invalid, Invalid, 5, 5, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_6x5_UNORM_BLOCK, ASTC_6x5_LDR, Invalid, Invalid, Invalid, 6, 5, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_6x5_SRGB_BLOCK, ASTC_6x5_sRGB, Invalid, Invalid, Invalid, 6, 5, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_6x6_UNORM_BLOCK, ASTC_6x6_LDR, Invalid, Invalid, Invalid, 6, 6, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_6x6_SRGB_BLOCK, ASTC_6x6_sRGB, Invalid, Invalid, Invalid, 6, 6, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_8x5_UNORM_BLOCK, ASTC_8x5_LDR, Invalid, Invalid, Invalid, 8, 5, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_8x5_SRGB_BLOCK, ASTC_8x5_sRGB, Invalid, Invalid, Invalid, 8, 5, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_8x6_UNORM_BLOCK, ASTC_8x6_LDR, Invalid, Invalid, Invalid, 8, 6, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_8x6_SRGB_BLOCK, ASTC_8x6_sRGB, Invalid, Invalid, Invalid, 8, 6, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_8x8_UNORM_BLOCK, ASTC_8x8_LDR, Invalid, Invalid, Invalid, 8, 8, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_8x8_SRGB_BLOCK, ASTC_8x8_sRGB, Invalid, Invalid, Invalid, 8, 8, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_10x5_UNORM_BLOCK, ASTC_10x5_LDR, Invalid, Invalid, Invalid, 10, 5, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_10x5_SRGB_BLOCK, ASTC_10x5_sRGB, Invalid, Invalid, Invalid, 10, 5, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_10x6_UNORM_BLOCK, ASTC_10x6_LDR, Invalid, Invalid, Invalid, 10, 6, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_10x6_SRGB_BLOCK, ASTC_10x6_sRGB, Invalid, Invalid, Invalid, 10, 6, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_10x8_UNORM_BLOCK, ASTC_10x8_LDR, Invalid, Invalid, Invalid, 10, 8, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_10x8_SRGB_BLOCK, ASTC_10x8_sRGB, Invalid, Invalid, Invalid, 10, 8, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_10x10_UNORM_BLOCK, ASTC_10x10_LDR, Invalid, Invalid, Invalid, 10, 10, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_10x10_SRGB_BLOCK, ASTC_10x10_sRGB, Invalid, Invalid, Invalid, 10, 10, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_12x10_UNORM_BLOCK, ASTC_12x10_LDR, Invalid, Invalid, Invalid, 12, 10, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_12x10_SRGB_BLOCK, ASTC_12x10_sRGB, Invalid, Invalid, Invalid, 12, 10, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_12x12_UNORM_BLOCK, ASTC_12x12_LDR, Invalid, Invalid, Invalid, 12, 12, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( ASTC_12x12_SRGB_BLOCK, ASTC_12x12_sRGB, Invalid, Invalid, Invalid, 12, 12, 16, Compressed, COMPRESSED_FEATS, NO_FEATS );

	// Extension VK_IMG_format_pvrtc
	addVkFormatDesc( PVRTC1_2BPP_UNORM_BLOCK_IMG, PVRTC_RGBA_2BPP, Invalid, Invalid, Invalid, 8, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( PVRTC1_4BPP_UNORM_BLOCK_IMG, PVRTC_RGBA_4BPP, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( PVRTC2_2BPP_UNORM_BLOCK_IMG, Invalid, Invalid, Invalid, Invalid, 8, 4, 8, Compressed, NO_FEATS, NO_FEATS );
	addVkFormatDesc( PVRTC2_4BPP_UNORM_BLOCK_IMG, Invalid, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, NO_FEATS, NO_FEATS );
	addVkFormatDesc( PVRTC1_2BPP_SRGB_BLOCK_IMG, PVRTC_RGBA_2BPP_sRGB, Invalid, Invalid, Invalid, 8, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( PVRTC1_4BPP_SRGB_BLOCK_IMG, PVRTC_RGBA_4BPP_sRGB, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, COMPRESSED_FEATS, NO_FEATS );
	addVkFormatDesc( PVRTC2_2BPP_SRGB_BLOCK_IMG, Invalid, Invalid, Invalid, Invalid, 8, 4, 8, Compressed, NO_FEATS, NO_FEATS );
	addVkFormatDesc( PVRTC2_4BPP_SRGB_BLOCK_IMG, Invalid, Invalid, Invalid, Invalid, 4, 4, 8, Compressed, NO_FEATS, NO_FEATS );

	// Future extension VK_KHX_color_conversion and Vulkan 1.1.
	addVkFormatDesc( UNDEFINED, GBGR422, Invalid, Invalid, Invalid, 2, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_FEATS );
	addVkFormatDesc( UNDEFINED, BGRG422, Invalid, Invalid, Invalid, 2, 1, 4, ColorFloat, COLOR_FEATS, BUFFER_FEATS );

	// When adding to this list, be sure to ensure _vkFormatCount is large enough for the format count
}

#define addMTLPixelFormatDesc(MTL_FMT, IOS_SINCE, MACOS_SINCE, IOS_CAPS, MACOS_CAPS)  \
	MVKAssert(fmtIdx < _mtlPixelFormatCount, "Attempting to describe %d MTLPixelFormats, but only have space for %d. Increase the value of _mtlPixelFormatCount", fmtIdx + 1, _mtlPixelFormatCount);  \
_mtlPixelFormatDescriptions[fmtIdx++] = { .mtlPixelFormat = MTLPixelFormat ##MTL_FMT, VK_FORMAT_UNDEFINED,  \
                                          mvkSelectPlatformValue<MVKOSVersion>(MACOS_SINCE, IOS_SINCE),  \
                                          mvkSelectPlatformValue<MVKMTLFmtCaps>(kMVKMTLFmtCaps ##MACOS_CAPS, kMVKMTLFmtCaps ##IOS_CAPS),  \
                                          "MTLPixelFormat" #MTL_FMT }

void MVKPixelFormats::initMTLPixelFormatCapabilities() {

	mvkClear(_mtlPixelFormatDescriptions, _mtlPixelFormatCount);

	uint32_t fmtIdx = 0;

	// When adding to this list, be sure to ensure _mtlPixelFormatCount is large enough for the format count

	// MTLPixelFormatInvalid must come first.
	addMTLPixelFormatDesc( Invalid, kMTLFmtNA, kMTLFmtNA, None, None );

	// Ordinary 8-bit pixel formats
	addMTLPixelFormatDesc( A8Unorm, 8.0, 10.11, TexRF, TexRF );
	addMTLPixelFormatDesc( R8Unorm, 8.0, 10.11, TexAll, TexAll );
	addMTLPixelFormatDesc( R8Unorm_sRGB, 8.0, kMTLFmtNA, TexRFCMRB, None );
	addMTLPixelFormatDesc( R8Snorm, 8.0, 10.11, TexRFWCMB, TexAll );
	addMTLPixelFormatDesc( R8Uint, 8.0, 10.11, TexRWCM, TexRWCM );
	addMTLPixelFormatDesc( R8Sint, 8.0, 10.11, TexRWCM, TexRWCM );

	// Ordinary 16-bit pixel formats
	addMTLPixelFormatDesc( R16Unorm, 8.0, 10.11, TexRFWCMB, TexAll );
	addMTLPixelFormatDesc( R16Snorm, 8.0, 10.11, TexRFWCMB, TexAll );
	addMTLPixelFormatDesc( R16Uint, 8.0, 10.11, TexRWCM, TexRWCM );
	addMTLPixelFormatDesc( R16Sint, 8.0, 10.11, TexRWCM, TexRWCM );
	addMTLPixelFormatDesc( R16Float, 8.0, 10.11, TexAll, TexAll );

	addMTLPixelFormatDesc( RG8Unorm, 8.0, 10.11, TexAll, TexAll );
	addMTLPixelFormatDesc( RG8Unorm_sRGB, 8.0, kMTLFmtNA, TexRFCMRB, None );
	addMTLPixelFormatDesc( RG8Snorm, 8.0, 10.11, TexRFWCMB, TexAll );
	addMTLPixelFormatDesc( RG8Uint, 8.0, 10.11, TexRWCM, TexRWCM );
	addMTLPixelFormatDesc( RG8Sint, 8.0, 10.11, TexRWCM, TexRWCM );

	// Packed 16-bit pixel formats
	addMTLPixelFormatDesc( B5G6R5Unorm, 8.0, kMTLFmtNA, TexRFCMRB, None );
	addMTLPixelFormatDesc( A1BGR5Unorm, 8.0, kMTLFmtNA, TexRFCMRB, None );
	addMTLPixelFormatDesc( ABGR4Unorm, 8.0, kMTLFmtNA, TexRFCMRB, None );
	addMTLPixelFormatDesc( BGR5A1Unorm, 8.0, kMTLFmtNA, TexRFCMRB, None );

	// Ordinary 32-bit pixel formats
	addMTLPixelFormatDesc( R32Uint, 8.0, 10.11, TexRC, TexRWCM );
	addMTLPixelFormatDesc( R32Sint, 8.0, 10.11, TexRC, TexRWCM );
	addMTLPixelFormatDesc( R32Float, 8.0, 10.11, TexRCMB, TexAll );

	addMTLPixelFormatDesc( RG16Unorm, 8.0, 10.11, TexRFWCMB, TexAll );
	addMTLPixelFormatDesc( RG16Snorm, 8.0, 10.11, TexRFWCMB, TexAll );
	addMTLPixelFormatDesc( RG16Uint, 8.0, 10.11, TexRWCM, TexRWCM );
	addMTLPixelFormatDesc( RG16Sint, 8.0, 10.11, TexRWCM, TexRWCM );
	addMTLPixelFormatDesc( RG16Float, 8.0, 10.11, TexAll, TexAll );

	addMTLPixelFormatDesc( RGBA8Unorm, 8.0, 10.11, TexAll, TexAll );
	addMTLPixelFormatDesc( RGBA8Unorm_sRGB, 8.0, 10.11, TexRFCMRB, TexRFCMRB );
	addMTLPixelFormatDesc( RGBA8Snorm, 8.0, 10.11, TexRFWCMB, TexAll );
	addMTLPixelFormatDesc( RGBA8Uint, 8.0, 10.11, TexRWCM, TexRWCM );
	addMTLPixelFormatDesc( RGBA8Sint, 8.0, 10.11, TexRWCM, TexRWCM );

	addMTLPixelFormatDesc( BGRA8Unorm, 8.0, 10.11, TexAll, TexAll );
	addMTLPixelFormatDesc( BGRA8Unorm_sRGB, 8.0, 10.11, TexRFCMRB, TexRFCMRB );

	// Packed 32-bit pixel formats
	addMTLPixelFormatDesc( RGB10A2Unorm, 8.0, 10.11, TexRFCMRB, TexAll );
	addMTLPixelFormatDesc( RGB10A2Uint, 8.0, 10.11, TexRCM, TexRWCM );
	addMTLPixelFormatDesc( RG11B10Float, 8.0, 10.11, TexRFCMRB, TexAll );
	addMTLPixelFormatDesc( RGB9E5Float, 8.0, 10.11, TexRFCMRB, TexRF );

	// Ordinary 64-bit pixel formats
	addMTLPixelFormatDesc( RG32Uint, 8.0, 10.11, TexRC, TexRWCM );
	addMTLPixelFormatDesc( RG32Sint, 8.0, 10.11, TexRC, TexRWCM );
	addMTLPixelFormatDesc( RG32Float, 8.0, 10.11, TexRCB, TexAll );

	addMTLPixelFormatDesc( RGBA16Unorm, 8.0, 10.11, TexRFWCMB, TexAll );
	addMTLPixelFormatDesc( RGBA16Snorm, 8.0, 10.11, TexRFWCMB, TexAll );
	addMTLPixelFormatDesc( RGBA16Uint, 8.0, 10.11, TexRWCM, TexRWCM );
	addMTLPixelFormatDesc( RGBA16Sint, 8.0, 10.11, TexRWCM, TexRWCM );
	addMTLPixelFormatDesc( RGBA16Float, 8.0, 10.11, TexAll, TexAll );

	// Ordinary 128-bit pixel formats
	addMTLPixelFormatDesc( RGBA32Uint, 8.0, 10.11, TexRC, TexRWCM );
	addMTLPixelFormatDesc( RGBA32Sint, 8.0, 10.11, TexRC, TexRWCM );
	addMTLPixelFormatDesc( RGBA32Float, 8.0, 10.11, TexRC, TexAll );

	// Compressed pixel formats
	addMTLPixelFormatDesc( PVRTC_RGBA_2BPP, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( PVRTC_RGBA_4BPP, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( PVRTC_RGBA_2BPP_sRGB, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( PVRTC_RGBA_4BPP_sRGB, 8.0, kMTLFmtNA, TexRF, None );

	addMTLPixelFormatDesc( ETC2_RGB8, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( ETC2_RGB8_sRGB, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( ETC2_RGB8A1, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( ETC2_RGB8A1_sRGB, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( EAC_RGBA8, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( EAC_RGBA8_sRGB, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( EAC_R11Unorm, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( EAC_R11Snorm, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( EAC_RG11Unorm, 8.0, kMTLFmtNA, TexRF, None );
	addMTLPixelFormatDesc( EAC_RG11Snorm, 8.0, kMTLFmtNA, TexRF, None );

	addMTLPixelFormatDesc( ASTC_4x4_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_4x4_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_5x4_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_5x4_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_5x5_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_5x5_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_6x5_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_6x5_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_6x6_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_6x6_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_8x5_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_8x5_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_8x6_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_8x6_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_8x8_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_8x8_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_10x5_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_10x5_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_10x6_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_10x6_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_10x8_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_10x8_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_10x10_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_10x10_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_12x10_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_12x10_sRGB, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_12x12_LDR, 8.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( ASTC_12x12_sRGB, 8.0, kMTLFmtNA, None, None );

	addMTLPixelFormatDesc( BC1_RGBA, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC1_RGBA_sRGB, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC1_RGBA, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC1_RGBA_sRGB, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC2_RGBA, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC2_RGBA_sRGB, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC3_RGBA, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC3_RGBA_sRGB, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC4_RUnorm, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC4_RSnorm, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC5_RGUnorm, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC5_RGSnorm, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC6H_RGBUfloat, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC6H_RGBFloat, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC7_RGBAUnorm, kMTLFmtNA, 10.11, None, TexRF );
	addMTLPixelFormatDesc( BC7_RGBAUnorm_sRGB, kMTLFmtNA, 10.11, None, TexRF );

	// YUV pixel formats
	addMTLPixelFormatDesc( GBGR422, 8.0, 10.11, TexRF, TexRF );
	addMTLPixelFormatDesc( BGRG422, 8.0, 10.11, TexRF, TexRF );

	// Depth and stencil pixel formats
	addMTLPixelFormatDesc( Depth16Unorm, kMTLFmtNA, 10.12, None, None );
	addMTLPixelFormatDesc( Depth32Float, 8.0, 10.11, TexDRM, TexDRFMR );
	addMTLPixelFormatDesc( Stencil8, 8.0, 10.11, TexDRM, TexDRM );
	addMTLPixelFormatDesc( Depth24Unorm_Stencil8, kMTLFmtNA, 10.11, None, None );
	addMTLPixelFormatDesc( Depth32Float_Stencil8, 9.0, 10.11, TexDRM, TexDRFMR );
	addMTLPixelFormatDesc( X24_Stencil8, kMTLFmtNA, 10.11, None, TexDRM );
	addMTLPixelFormatDesc( X32_Stencil8, 8.0, 10.11, TexDRM, TexDRM );

	// Extended range and wide color pixel formats
	addMTLPixelFormatDesc( BGRA10_XR, 10.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( BGRA10_XR_sRGB, 10.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( BGR10_XR, 10.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( BGR10_XR_sRGB, 10.0, kMTLFmtNA, None, None );
	addMTLPixelFormatDesc( BGR10A2Unorm, 11.0, 10.13, None, None );

	// When adding to this list, be sure to ensure _mtlPixelFormatCount is large enough for the format count
}

#define addMTLVertexFormatDesc(MTL_VTX_FMT, VTX_IOS_SINCE, VTX_MACOS_SINCE, IOS_CAPS, MACOS_CAPS)  \
	MVKAssert(fmtIdx < _mtlVertexFormatCount, "Attempting to describe %d MTLVertexFormats, but only have space for %d. Increase the value of _mtlVertexFormatCount", fmtIdx + 1, _mtlVertexFormatCount);  \
	_mtlVertexFormatDescriptions[fmtIdx++] = { .mtlVertexFormat = MTLVertexFormat ##MTL_VTX_FMT, VK_FORMAT_UNDEFINED,  \
                                               mvkSelectPlatformValue<MVKOSVersion>(VTX_MACOS_SINCE, VTX_IOS_SINCE),  \
                                               mvkSelectPlatformValue<MVKMTLFmtCaps>(kMVKMTLFmtCaps ##MACOS_CAPS, kMVKMTLFmtCaps ##IOS_CAPS),  \
                                               "MTLVertexFormat" #MTL_VTX_FMT }

void MVKPixelFormats::initMTLVertexFormatCapabilities() {

	mvkClear(_mtlVertexFormatDescriptions, _mtlVertexFormatCount);

	uint32_t fmtIdx = 0;

	// When adding to this list, be sure to ensure _mtlVertexFormatCount is large enough for the format count
	// MTLVertexFormatInvalid must come first.
	addMTLVertexFormatDesc( Invalid, kMTLFmtNA, kMTLFmtNA, None, None );

	addMTLVertexFormatDesc( UChar2Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Char2Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( UChar2, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Char2, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UChar3Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Char3Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( UChar3, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Char3, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UChar4Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Char4Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( UChar4, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Char4, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UInt1010102Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Int1010102Normalized, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UShort2Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Short2Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( UShort2, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Short2, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Half2, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UShort3Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Short3Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( UShort3, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Short3, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Half3, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UShort4Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Short4Normalized, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( UShort4, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Short4, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Half4, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UInt, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Int, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Float, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UInt2, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Int2, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Float2, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UInt3, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Int3, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Float3, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UInt4, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Int4, 8.0, 10.11, BufVertex, BufVertex );
	addMTLVertexFormatDesc( Float4, 8.0, 10.11, BufVertex, BufVertex );

	addMTLVertexFormatDesc( UCharNormalized, 11.0, 10.13, None, None );
	addMTLVertexFormatDesc( CharNormalized, 11.0, 10.13, None, None );
	addMTLVertexFormatDesc( UChar, 11.0, 10.13, None, None );
	addMTLVertexFormatDesc( Char, 11.0, 10.13, None, None );

	addMTLVertexFormatDesc( UShortNormalized, 11.0, 10.13, None, None );
	addMTLVertexFormatDesc( ShortNormalized, 11.0, 10.13, None, None );
	addMTLVertexFormatDesc( UShort, 11.0, 10.13, None, None );
	addMTLVertexFormatDesc( Short, 11.0, 10.13, None, None );
	addMTLVertexFormatDesc( Half, 11.0, 10.13, None, None );

	addMTLVertexFormatDesc( UChar4Normalized_BGRA, 11.0, 10.13, None, None );

	// When adding to this list, be sure to ensure _mtlVertexFormatCount is large enough for the format count
}

// Populates the lookup maps that map Vulkan and Metal pixel formats to one-another.
void MVKPixelFormats::buildFormatMaps() {

	// Set all VkFormats, MTLPixelFormats, and MTLVertexFormats to undefined/invalid
	mvkClear(_vkFormatDescIndicesByVkFormatsCore, _vkFormatCoreCount);
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
		}
	}
}

// If the device supports the feature set, add additional capabilities to a MTLPixelFormat
void MVKPixelFormats::addMTLPixelFormatCapabilities(id<MTLDevice> mtlDevice,
													MTLFeatureSet mtlFeatSet,
													MTLPixelFormat mtlPixFmt,
													MVKMTLFmtCaps mtlFmtCaps) {
	if ( [mtlDevice supportsFeatureSet: mtlFeatSet] ) {
		auto& fmtDesc = getMTLPixelFormatDesc(mtlPixFmt);
		fmtDesc.mtlFmtCaps = (MVKMTLFmtCaps)(fmtDesc.mtlFmtCaps | mtlFmtCaps);
	}
}

// If the device supports the feature set, add additional capabilities to a MTLVertexFormat
void MVKPixelFormats::addMTLVertexFormatCapabilities(id<MTLDevice> mtlDevice,
													 MTLFeatureSet mtlFeatSet,
													 MTLVertexFormat mtlVtxFmt,
													 MVKMTLFmtCaps mtlFmtCaps) {
	if ( [mtlDevice supportsFeatureSet: mtlFeatSet] ) {
		auto& fmtDesc = getMTLVertexFormatDesc(mtlVtxFmt);
		fmtDesc.mtlFmtCaps = (MVKMTLFmtCaps)(fmtDesc.mtlFmtCaps | mtlFmtCaps);
	}
}

#define addMTLPixelFormatCapabilities(FEAT_SET, MTL_FMT, CAPS)  \
	addMTLPixelFormatCapabilities(mtlDevice, MTLFeatureSet_ ##FEAT_SET, MTLPixelFormat ##MTL_FMT, kMVKMTLFmtCaps ##CAPS)

#define addMTLVertexFormatCapabilities(FEAT_SET, MTL_FMT, CAPS)  \
	addMTLVertexFormatCapabilities(mtlDevice, MTLFeatureSet_ ##FEAT_SET, MTLVertexFormat ##MTL_FMT, kMVKMTLFmtCaps ##CAPS)

// Modifies the format capability tables based on the capabilities of the specific MTLDevice
#if MVK_MACOS
void MVKPixelFormats::modifyFormatCapabilitiesForMTLDevice(id<MTLDevice> mtlDevice) {
	if ( !mtlDevice ) { return; }

	if (mtlDevice.isDepth24Stencil8PixelFormatSupported) {
		addMTLPixelFormatCapabilities( macOS_GPUFamily1_v1, Depth24Unorm_Stencil8, TexDRFMR );
	}

	addMTLPixelFormatCapabilities( macOS_GPUFamily1_v2, Depth16Unorm, TexDRFMR );

	addMTLPixelFormatCapabilities( macOS_GPUFamily1_v3, BGR10A2Unorm, TexRFCMRB );

	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UCharNormalized, BufVertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, CharNormalized, BufVertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UChar, BufVertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, Char, BufVertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UShortNormalized, BufVertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, ShortNormalized, BufVertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UShort, BufVertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, Short, BufVertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, Half, BufVertex );
	addMTLVertexFormatCapabilities( macOS_GPUFamily1_v3, UChar4Normalized_BGRA, BufVertex );
}
#endif
#if MVK_IOS
void MVKPixelFormats::modifyFormatCapabilitiesForMTLDevice(id<MTLDevice> mtlDevice) {
	if ( !mtlDevice ) { return; }

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v3, R8Unorm_sRGB, TexAll );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, R8Unorm_sRGB, TexAll );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v1, R8Snorm, TexAll );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v3, RG8Unorm_sRGB, TexAll );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RG8Unorm_sRGB, TexAll );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v1, RG8Snorm, TexAll );

	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, R32Uint, TexRWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, R32Sint, TexRWC );

	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, R32Float, TexRWCMB );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v3, RGBA8Unorm_sRGB, TexAll );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RGBA8Unorm_sRGB, TexAll );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v1, RGBA8Snorm, TexAll );

	addMTLPixelFormatCapabilities( iOS_GPUFamily2_v3, BGRA8Unorm_sRGB, TexAll );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, BGRA8Unorm_sRGB, TexAll );

	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RGB10A2Unorm, TexAll );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RGB10A2Uint, TexRWCM );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RG11B10Float, TexAll );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, RGB9E5Float, TexAll );

	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RG32Uint, TexRWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RG32Sint, TexRWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RG32Float, TexRWCB );

	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RGBA32Uint, TexRWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RGBA32Sint, TexRWC );
	addMTLPixelFormatCapabilities( iOS_GPUFamily1_v2, RGBA32Float, TexRWC );

	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_4x4_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_4x4_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_5x4_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_5x4_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_5x5_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_5x5_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_6x5_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_6x5_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_6x6_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_6x6_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x5_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x5_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x6_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x6_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x8_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_8x8_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x5_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x5_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x6_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x6_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x8_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x8_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x10_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_10x10_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_12x10_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_12x10_sRGB, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_12x12_LDR, TexRF );
	addMTLPixelFormatCapabilities(iOS_GPUFamily2_v1, ASTC_12x12_sRGB, TexRF );

	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, Depth32Float, TexDRMR );
	addMTLPixelFormatCapabilities( iOS_GPUFamily3_v1, Depth32Float_Stencil8, TexDRMR );

	addMTLPixelFormatCapabilities(iOS_GPUFamily3_v2, BGRA10_XR, TexAll );
	addMTLPixelFormatCapabilities(iOS_GPUFamily3_v2, BGRA10_XR_sRGB, TexAll );
	addMTLPixelFormatCapabilities(iOS_GPUFamily3_v2, BGR10_XR, TexAll );
	addMTLPixelFormatCapabilities(iOS_GPUFamily3_v2, BGR10_XR_sRGB, TexAll );

	addMTLPixelFormatCapabilities(iOS_GPUFamily1_v4, BGR10A2Unorm, TexAll );

	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UCharNormalized, BufVertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, CharNormalized, BufVertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UChar, BufVertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, Char, BufVertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UShortNormalized, BufVertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, ShortNormalized, BufVertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UShort, BufVertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, Short, BufVertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, Half, BufVertex );
	addMTLVertexFormatCapabilities( iOS_GPUFamily1_v4, UChar4Normalized_BGRA, BufVertex );
}
#endif
#undef addMTLPixelFormatCapabilities
#undef addMTLVertexFormatCapabilities


#pragma mark -
#pragma mark Unit Testing

template<typename T>
void MVKPixelFormats::testFmt(const T v1, const T v2, const char* fmtName, const char* funcName) {
	MVKAssert(mvkAreEqual(&v1,&v2), "Results not equal for format %s on test %s.", fmtName, funcName);
}

// Validate the functionality of this class against the previous format data within MoltenVK.
// This is a temporary function to confirm that converting to using this class matches existing behaviour at first.
void MVKPixelFormats::test() {
	if (_apiObject) { return; }		// Only test default platform formats

	MVKLogInfo("Starting testing formats");
	for (uint32_t fmtIdx = 0; fmtIdx < _vkFormatCount; fmtIdx++) {
		auto& fd = _vkFormatDescriptions[fmtIdx];
		VkFormat vkFmt = fd.vkFormat;
		MTLPixelFormat mtlFmt = fd.mtlPixelFormat;

		if (fd.vkFormat) {
			if (fd.isSupportedOrSubstitutable()) {
				MVKLogInfo("Testing %s", fd.name);

#				define testFmt(V1, V2)	testFmt(V1, V2, fd.name, #V1)

				testFmt(vkFormatIsSupported(vkFmt), mvkVkFormatIsSupported(vkFmt));
				testFmt(mtlPixelFormatIsSupported(mtlFmt), mvkMTLPixelFormatIsSupported(mtlFmt));
				testFmt(mtlPixelFormatIsDepthFormat(mtlFmt), mvkMTLPixelFormatIsDepthFormat(mtlFmt));
				testFmt(mtlPixelFormatIsStencilFormat(mtlFmt), mvkMTLPixelFormatIsStencilFormat(mtlFmt));
				testFmt(mtlPixelFormatIsPVRTCFormat(mtlFmt), mvkMTLPixelFormatIsPVRTCFormat(mtlFmt));
				testFmt(getFormatTypeFromVkFormat(vkFmt), mvkFormatTypeFromVkFormat(vkFmt));
				testFmt(getFormatTypeFromMTLPixelFormat(mtlFmt), mvkFormatTypeFromMTLPixelFormat(mtlFmt));
				testFmt(getMTLPixelFormatFromVkFormat(vkFmt), mvkMTLPixelFormatFromVkFormat(vkFmt));
				testFmt(getVkFormatFromMTLPixelFormat(mtlFmt), mvkVkFormatFromMTLPixelFormat(mtlFmt));
				testFmt(getVkFormatBytesPerBlock(vkFmt), mvkVkFormatBytesPerBlock(vkFmt));
				testFmt(getMTLPixelFormatBytesPerBlock(mtlFmt), mvkMTLPixelFormatBytesPerBlock(mtlFmt));
				testFmt(getVkFormatBlockTexelSize(vkFmt), mvkVkFormatBlockTexelSize(vkFmt));
				testFmt(getMTLPixelFormatBlockTexelSize(mtlFmt), mvkMTLPixelFormatBlockTexelSize(mtlFmt));
				testFmt(getVkFormatBytesPerTexel(vkFmt), mvkVkFormatBytesPerTexel(vkFmt));
				testFmt(getMTLPixelFormatBytesPerTexel(mtlFmt), mvkMTLPixelFormatBytesPerTexel(mtlFmt));
				testFmt(getVkFormatBytesPerRow(vkFmt, 4), mvkVkFormatBytesPerRow(vkFmt, 4));
				testFmt(getMTLPixelFormatBytesPerRow(mtlFmt, 4), mvkMTLPixelFormatBytesPerRow(mtlFmt, 4));
				testFmt(getVkFormatBytesPerLayer(vkFmt, 256, 4), mvkVkFormatBytesPerLayer(vkFmt, 256, 4));
				testFmt(getMTLPixelFormatBytesPerLayer(mtlFmt, 256, 4), mvkMTLPixelFormatBytesPerLayer(mtlFmt, 256, 4));
				testFmt(getVkFormatProperties(vkFmt), mvkVkFormatProperties(vkFmt));
				testFmt(strcmp(getVkFormatName(vkFmt), mvkVkFormatName(vkFmt)), 0);
				testFmt(strcmp(getMTLPixelFormatName(mtlFmt), mvkMTLPixelFormatName(mtlFmt)), 0);
				testFmt(getMTLClearColorFromVkClearValue(VkClearValue(), vkFmt),
						mvkMTLClearColorFromVkClearValue(VkClearValue(), vkFmt));

				testFmt(getVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageUnknown, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageUnknown, mtlFmt));
				testFmt(getVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageShaderRead, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageShaderRead, mtlFmt));
				testFmt(getVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageShaderWrite, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageShaderWrite, mtlFmt));
				testFmt(getVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageRenderTarget, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsageRenderTarget, mtlFmt));
				testFmt(getVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsagePixelFormatView, mtlFmt),
						mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsagePixelFormatView, mtlFmt));

				testFmt(getMTLVertexFormatFromVkFormat(vkFmt), mvkMTLVertexFormatFromVkFormat(vkFmt));

#				undef testFmt

			} else {
				MVKLogInfo("%s not supported or substitutable on this device.", fd.name);
			}
		}
	}
	MVKLogInfo("Finished testing formats.\n");
}
