/*
 * MVKPixelFormats.mm
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include <string>

using namespace std;

// Some Metal formats are not supported by the headers on certain platforms. However, formats have
// been 'unlocked' on some platforms with newer versions of Xcode.

// Add stub defs for unsupported MTLPixelFormats per platform
#if MVK_MACOS
#	if !MVK_XCODE_12 // macOS 11.0 / iOS 14.2
#       define MTLPixelFormatR8Unorm_sRGB           MTLPixelFormatInvalid
#       define MTLPixelFormatRG8Unorm_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatABGR4Unorm             MTLPixelFormatInvalid
#       define MTLPixelFormatB5G6R5Unorm            MTLPixelFormatInvalid
#       define MTLPixelFormatA1BGR5Unorm            MTLPixelFormatInvalid
#       define MTLPixelFormatBGR5A1Unorm            MTLPixelFormatInvalid

#       define MTLPixelFormatBGR10_XR				MTLPixelFormatInvalid
#       define MTLPixelFormatBGR10_XR_sRGB			MTLPixelFormatInvalid
#       define MTLPixelFormatBGRA10_XR				MTLPixelFormatInvalid
#       define MTLPixelFormatBGRA10_XR_sRGB			MTLPixelFormatInvalid

#       define MTLPixelFormatPVRTC_RGB_2BPP         MTLPixelFormatInvalid
#       define MTLPixelFormatPVRTC_RGB_2BPP_sRGB    MTLPixelFormatInvalid
#       define MTLPixelFormatPVRTC_RGB_4BPP         MTLPixelFormatInvalid
#       define MTLPixelFormatPVRTC_RGB_4BPP_sRGB    MTLPixelFormatInvalid
#       define MTLPixelFormatPVRTC_RGBA_2BPP        MTLPixelFormatInvalid
#       define MTLPixelFormatPVRTC_RGBA_2BPP_sRGB   MTLPixelFormatInvalid
#       define MTLPixelFormatPVRTC_RGBA_4BPP        MTLPixelFormatInvalid
#       define MTLPixelFormatPVRTC_RGBA_4BPP_sRGB   MTLPixelFormatInvalid

#       define MTLPixelFormatEAC_RGBA8              MTLPixelFormatInvalid
#       define MTLPixelFormatEAC_RGBA8_sRGB         MTLPixelFormatInvalid
#       define MTLPixelFormatEAC_R11Unorm           MTLPixelFormatInvalid
#       define MTLPixelFormatEAC_R11Snorm           MTLPixelFormatInvalid
#       define MTLPixelFormatEAC_RG11Unorm          MTLPixelFormatInvalid
#       define MTLPixelFormatEAC_RG11Snorm          MTLPixelFormatInvalid
#       define MTLPixelFormatETC2_RGB8              MTLPixelFormatInvalid
#       define MTLPixelFormatETC2_RGB8_sRGB         MTLPixelFormatInvalid
#       define MTLPixelFormatETC2_RGB8A1            MTLPixelFormatInvalid
#       define MTLPixelFormatETC2_RGB8A1_sRGB       MTLPixelFormatInvalid

#       define MTLPixelFormatASTC_4x4_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_4x4_LDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_4x4_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_5x4_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_5x4_LDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_5x4_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_5x5_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_5x5_LDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_5x5_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_6x5_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_6x5_LDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_6x5_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_6x6_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_6x6_LDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_6x6_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x5_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x5_LDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x5_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x6_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x6_LDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x6_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x8_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x8_LDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x8_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x5_HDR          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x5_LDR          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x5_sRGB         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x6_HDR          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x6_LDR          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x6_sRGB         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x8_HDR          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x8_LDR          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x8_sRGB         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x10_HDR         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x10_LDR         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x10_sRGB        MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_12x10_HDR         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_12x10_LDR         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_12x10_sRGB        MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_12x12_HDR         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_12x12_LDR         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_12x12_sRGB        MTLPixelFormatInvalid
#   endif

#   define MTLPixelFormatDepth16Unorm_Stencil8      MTLPixelFormatDepth24Unorm_Stencil8
#endif

#if MVK_IOS_OR_TVOS
#	if !MVK_XCODE_14_3   // iOS/tvOS 16.4
#       define MTLPixelFormatBC1_RGBA               MTLPixelFormatInvalid
#       define MTLPixelFormatBC1_RGBA_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatBC2_RGBA               MTLPixelFormatInvalid
#       define MTLPixelFormatBC2_RGBA_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatBC3_RGBA               MTLPixelFormatInvalid
#       define MTLPixelFormatBC3_RGBA_sRGB          MTLPixelFormatInvalid
#       define MTLPixelFormatBC4_RUnorm             MTLPixelFormatInvalid
#       define MTLPixelFormatBC4_RSnorm             MTLPixelFormatInvalid
#       define MTLPixelFormatBC5_RGUnorm            MTLPixelFormatInvalid
#       define MTLPixelFormatBC5_RGSnorm            MTLPixelFormatInvalid
#       define MTLPixelFormatBC6H_RGBUfloat         MTLPixelFormatInvalid
#       define MTLPixelFormatBC6H_RGBFloat          MTLPixelFormatInvalid
#       define MTLPixelFormatBC7_RGBAUnorm          MTLPixelFormatInvalid
#       define MTLPixelFormatBC7_RGBAUnorm_sRGB     MTLPixelFormatInvalid
#   endif

#   define MTLPixelFormatDepth16Unorm_Stencil8      MTLPixelFormatDepth32Float_Stencil8
#   define MTLPixelFormatDepth24Unorm_Stencil8      MTLPixelFormatInvalid
#   define MTLPixelFormatX24_Stencil8               MTLPixelFormatInvalid
#endif

#if MVK_VISIONOS
#   define MTLPixelFormatDepth24Unorm_Stencil8      MTLPixelFormatInvalid
#   define MTLPixelFormatDepth16Unorm_Stencil8      MTLPixelFormatInvalid
#   define MTLPixelFormatX24_Stencil8               MTLPixelFormatInvalid
#endif

#if MVK_TVOS
#       define MTLPixelFormatASTC_4x4_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_5x4_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_5x5_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_6x5_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_6x6_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x5_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x6_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_8x8_HDR           MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x5_HDR          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x6_HDR          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x8_HDR          MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_10x10_HDR         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_12x10_HDR         MTLPixelFormatInvalid
#       define MTLPixelFormatASTC_12x12_HDR         MTLPixelFormatInvalid
#endif

#if MVK_OS_SIMULATOR
#   define MTLPixelFormatR8Unorm_sRGB               MTLPixelFormatInvalid
#   define MTLPixelFormatRG8Unorm_sRGB              MTLPixelFormatInvalid
#   define MTLPixelFormatB5G6R5Unorm                MTLPixelFormatInvalid
#   define MTLPixelFormatA1BGR5Unorm                MTLPixelFormatInvalid
#   define MTLPixelFormatABGR4Unorm                 MTLPixelFormatInvalid
#   define MTLPixelFormatBGR5A1Unorm                MTLPixelFormatInvalid
#   define MTLPixelFormatBGR10_XR                   MTLPixelFormatInvalid
#   define MTLPixelFormatBGR10_XR_sRGB              MTLPixelFormatInvalid
#   define MTLPixelFormatBGRA10_XR                  MTLPixelFormatInvalid
#   define MTLPixelFormatBGRA10_XR_sRGB             MTLPixelFormatInvalid
#   define MTLPixelFormatGBGR422                    MTLPixelFormatInvalid
#   define MTLPixelFormatBGRG422                    MTLPixelFormatInvalid
#endif

#if !MVK_XCODE_15
#   define MTLVertexFormatFloatRG11B10              MTLVertexFormatInvalid
#   define MTLVertexFormatFloatRGB9E5               MTLVertexFormatInvalid
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
		case MTLPixelFormatDepth16Unorm:
		case MTLPixelFormatDepth32Float_Stencil8:
#if MVK_MACOS
		case MTLPixelFormatDepth24Unorm_Stencil8:
#endif
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
#if MVK_APPLE_SILICON
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

bool MVKPixelFormats::compatibleAsLinearOrSRGB(MTLPixelFormat mtlFormat, VkFormat vkFormat) {
	MTLPixelFormat mtlVkFmt = getMTLPixelFormat(vkFormat);
	return ((mtlVkFmt == mtlFormat) ||
			(mtlVkFmt == getMTLPixelFormatDesc(mtlFormat).mtlPixelFormatLinear) ||
			(mtlFormat == getMTLPixelFormatDesc(mtlVkFmt).mtlPixelFormatLinear));
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
	if ( !mtlPixFmt && vkFormat && vkDesc.chromaSubsamplingPlaneCount <= 1 ) {
		mtlPixFmt = vkDesc.mtlPixelFormatSubstitute;

		// Report an error if there is no substitute, or the first time a substitution is made.
		if ( !mtlPixFmt || !vkDesc.hasReportedSubstitution ) {
			string errMsg;
			errMsg += "VkFormat ";
			errMsg += vkDesc.name;
			errMsg += " is not supported on this device.";

			if (mtlPixFmt) {
				vkDesc.hasReportedSubstitution = true;

				auto& vkDescSubs = getVkFormatDesc(mtlPixFmt);
				errMsg += " Using VkFormat ";
				errMsg += vkDescSubs.name;
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

uint8_t MVKPixelFormats::getChromaSubsamplingPlaneCount(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).chromaSubsamplingPlaneCount;
}

uint8_t MVKPixelFormats::getChromaSubsamplingComponentBits(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).chromaSubsamplingComponentBits;
}

SPIRV_CROSS_NAMESPACE::MSLFormatResolution MVKPixelFormats::getChromaSubsamplingResolution(VkFormat vkFormat) {
    VkExtent2D blockTexelSize = getVkFormatDesc(vkFormat).blockTexelSize;
    return (blockTexelSize.width != 2) ? SPIRV_CROSS_NAMESPACE::MSL_FORMAT_RESOLUTION_444
        : (blockTexelSize.height != 2) ? SPIRV_CROSS_NAMESPACE::MSL_FORMAT_RESOLUTION_422
                                       : SPIRV_CROSS_NAMESPACE::MSL_FORMAT_RESOLUTION_420;
}

MTLPixelFormat MVKPixelFormats::getChromaSubsamplingPlaneMTLPixelFormat(VkFormat vkFormat, uint8_t planeIndex) {
    uint8_t planes = getChromaSubsamplingPlaneCount(vkFormat);
    uint8_t bits = getChromaSubsamplingComponentBits(vkFormat);
    switch(planes) {
        default:
        case 1:
            return getMTLPixelFormat(vkFormat);
        case 2:
            if (planeIndex == 1) {
                return (bits == 8) ? MTLPixelFormatRG8Unorm : MTLPixelFormatRG16Unorm;
            }
            /* fallthrough */
        case 3:
            return (bits == 8) ? MTLPixelFormatR8Unorm : MTLPixelFormatR16Unorm;
    }
}

uint8_t MVKPixelFormats::getChromaSubsamplingPlanes(VkFormat vkFormat, VkExtent2D blockTexelSize[3], uint32_t bytesPerBlock[3], MTLPixelFormat mtlPixFmt[3]) {
    uint8_t planes = getChromaSubsamplingPlaneCount(vkFormat);
    uint8_t bits = getChromaSubsamplingComponentBits(vkFormat);
    SPIRV_CROSS_NAMESPACE::MSLFormatResolution resolution = getChromaSubsamplingResolution(vkFormat);
    bytesPerBlock[0] = mvkCeilingDivide((uint32_t)bits/8U, 1U);
    switch(resolution) {
        default:
            return 0;
        case SPIRV_CROSS_NAMESPACE::MSL_FORMAT_RESOLUTION_444:
            blockTexelSize[0] = blockTexelSize[1] = blockTexelSize[2] = VkExtent2D{1, 1};
            break;
        case SPIRV_CROSS_NAMESPACE::MSL_FORMAT_RESOLUTION_422:
            blockTexelSize[0] = blockTexelSize[1] = blockTexelSize[2] = VkExtent2D{2, 1};
            break;
        case SPIRV_CROSS_NAMESPACE::MSL_FORMAT_RESOLUTION_420:
            blockTexelSize[0] = blockTexelSize[1] = blockTexelSize[2] = VkExtent2D{2, 2};
            break;
    }
    switch(planes) {
        default:
            return 0;
        case 1:
            bytesPerBlock[0] *= 4;
            mtlPixFmt[0] = getMTLPixelFormat(vkFormat);
            break;
        case 2:
            blockTexelSize[0] = VkExtent2D{1, 1};
            bytesPerBlock[1] = bytesPerBlock[0]*2;
            mtlPixFmt[0] = (bits == 8) ? MTLPixelFormatR8Unorm : MTLPixelFormatR16Unorm;
            mtlPixFmt[1] = (bits == 8) ? MTLPixelFormatRG8Unorm : MTLPixelFormatRG16Unorm;
            break;
        case 3:
            blockTexelSize[0] = VkExtent2D{1, 1};
            bytesPerBlock[1] = bytesPerBlock[2] = bytesPerBlock[0];
            mtlPixFmt[0] = mtlPixFmt[1] = mtlPixFmt[2] = (bits == 8) ? MTLPixelFormatR8Unorm : MTLPixelFormatR16Unorm;
            break;
    }
    return planes;
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

bool MVKPixelFormats::needsSwizzle(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).needsSwizzle();
}

VkComponentMapping MVKPixelFormats::getVkComponentMapping(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).componentMapping;
}

VkComponentMapping MVKPixelFormats::getInverseComponentMapping(VkFormat vkFormat) {
#define INVERT_SWIZZLE(x, X, Y) \
			case VK_COMPONENT_SWIZZLE_##X: \
				inverse.x = VK_COMPONENT_SWIZZLE_##Y; \
				break
#define INVERT_MAPPING(y, Y) \
		switch (mapping.y) { \
			case VK_COMPONENT_SWIZZLE_IDENTITY: \
				inverse.y = VK_COMPONENT_SWIZZLE_IDENTITY; \
				break; \
			INVERT_SWIZZLE(r, R, Y); \
			INVERT_SWIZZLE(g, G, Y); \
			INVERT_SWIZZLE(b, B, Y); \
			INVERT_SWIZZLE(a, A, Y); \
			default: break; \
		}
	VkComponentMapping mapping = getVkComponentMapping(vkFormat), inverse;
	INVERT_MAPPING(r, R)
	INVERT_MAPPING(g, G)
	INVERT_MAPPING(b, B)
	INVERT_MAPPING(a, A)
	return inverse;
#undef INVERT_MAPPING
#undef INVERT_SWIZZLE
}

MTLTextureSwizzleChannels MVKPixelFormats::getMTLTextureSwizzleChannels(VkFormat vkFormat) {
	return mvkMTLTextureSwizzleChannelsFromVkComponentMapping(getVkComponentMapping(vkFormat));
}

VkFormatProperties3& MVKPixelFormats::getVkFormatProperties3(VkFormat vkFormat) {
	return getVkFormatDesc(vkFormat).properties;
}

VkFormatProperties MVKPixelFormats::getVkFormatProperties(VkFormat vkFormat) {
    auto& properties = getVkFormatProperties3(vkFormat);
    VkFormatProperties ret;
    ret.linearTilingFeatures = MVKPixelFormats::convertFormatPropertiesFlagBits(properties.linearTilingFeatures);
    ret.optimalTilingFeatures = MVKPixelFormats::convertFormatPropertiesFlagBits(properties.optimalTilingFeatures);
    ret.bufferFeatures = MVKPixelFormats::convertFormatPropertiesFlagBits(properties.bufferFeatures);
    return ret;
}

MVKMTLFmtCaps MVKPixelFormats::getCapabilities(VkFormat vkFormat, bool isExtended) {
	return getCapabilities(getVkFormatDesc(vkFormat).mtlPixelFormat, isExtended);
}

MVKMTLFmtCaps MVKPixelFormats::getCapabilities(MTLPixelFormat mtlFormat, bool isExtended) {
    MVKMTLFormatDesc& mtlDesc = getMTLPixelFormatDesc(mtlFormat);
    MVKMTLFmtCaps caps = mtlDesc.mtlFmtCaps;
    if (!isExtended || mtlDesc.mtlViewClass == MVKMTLViewClass::None) { return caps; }
    // Now get caps of all formats in the view class.
    for (auto& otherDesc : _mtlPixelFormatDescriptions) {
        if (otherDesc.mtlViewClass == mtlDesc.mtlViewClass) { caps |= otherDesc.mtlFmtCaps; }
    }
    return caps;
}

MVKMTLViewClass MVKPixelFormats::getViewClass(VkFormat vkFormat) {
    return getMTLPixelFormatDesc(getVkFormatDesc(vkFormat).mtlPixelFormat).mtlViewClass;
}

MVKMTLViewClass MVKPixelFormats::getViewClass(MTLPixelFormat mtlFormat) {
    return getMTLPixelFormatDesc(mtlFormat).mtlViewClass;
}

const char* MVKPixelFormats::getName(VkFormat vkFormat) {
    return getVkFormatDesc(vkFormat).name;
}

const char* MVKPixelFormats::getName(MTLPixelFormat mtlFormat) {
    return getMTLPixelFormatDesc(mtlFormat).name;
}

const char* MVKPixelFormats::getName(MTLVertexFormat mtlFormat) {
    return getMTLVertexFormatDesc(mtlFormat).name;
}

void MVKPixelFormats::enumerateSupportedFormats(const VkFormatProperties3& properties, bool any, std::function<bool(VkFormat)> func) {
	static const auto areFeaturesSupported = [any](VkFlags64 a, VkFlags64 b) {
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
		errMsg += vkDesc.name;
		errMsg += " is not supported for vertex buffers on this device.";

		if (vkDesc.vertexIsSupportedOrSubstitutable()) {
			mtlVtxFmt = vkDesc.mtlVertexFormatSubstitute;

			auto& vkDescSubs = getVkFormatDesc(getMTLVertexFormatDesc(mtlVtxFmt).vkFormat);
			errMsg += " Using VkFormat ";
			errMsg += vkDescSubs.name;
			errMsg += " instead.";
		}
		MVKBaseObject::reportError(_physicalDevice, VK_ERROR_FORMAT_NOT_SUPPORTED, "%s", errMsg.c_str());
	}

	return mtlVtxFmt;
}

MTLClearColor MVKPixelFormats::getMTLClearColor(VkClearValue vkClearValue, VkFormat vkFormat) {
	MTLClearColor mtlClr;
	// The VkComponentMapping (and its MTLTextureSwizzleChannels equivalent) define the *sources*
	// for the texture color components for reading. Since we're *writing* to the texture,
	// we need to *invert* the mapping.
	// n.b. Bad things might happen if the original swizzle isn't one-to-one!
	VkComponentMapping inverseMap = getInverseComponentMapping(vkFormat);
	switch (getFormatType(vkFormat)) {
		case kMVKFormatColorHalf:
		case kMVKFormatColorFloat: {
			mtlClr.red		= mvkVkClearColorFloatValueFromVkComponentSwizzle(vkClearValue.color.float32, 0, inverseMap.r);
			mtlClr.green	= mvkVkClearColorFloatValueFromVkComponentSwizzle(vkClearValue.color.float32, 1, inverseMap.g);
			mtlClr.blue		= mvkVkClearColorFloatValueFromVkComponentSwizzle(vkClearValue.color.float32, 2, inverseMap.b);
			mtlClr.alpha	= mvkVkClearColorFloatValueFromVkComponentSwizzle(vkClearValue.color.float32, 3, inverseMap.a);

			if (_physicalDevice && _physicalDevice->getMetalFeatures()->clearColorFloatRounding == MVK_FLOAT_ROUNDING_DOWN) {
				// For normalized formats, increment the clear value by half the ULP
				// (i.e. 1/(2*(2**component_size - 1))), to force Metal to round up.
				// This should fix some problems with clear values being off by one ULP on some platforms.
				// This adjustment is not performed on SRGB formats, which Vulkan
				// requires to be treated as linear, with the value managed by the app.
#define OFFSET_NORM(MIN_VAL, COLOR, BIT_WIDTH)  \
	if (mtlClr.COLOR > (MIN_VAL) && mtlClr.COLOR < 1.0) {  \
		mtlClr.COLOR += 1.0 / (2.0 * ((1U << (BIT_WIDTH)) - 1));  \
	}
#define OFFSET_UNORM(COLOR, BIT_WIDTH)    OFFSET_NORM(0.0, COLOR, BIT_WIDTH)
#define OFFSET_SNORM(COLOR, BIT_WIDTH)    OFFSET_NORM(-1.0, COLOR, BIT_WIDTH - 1)
				switch (vkFormat) {
					case VK_FORMAT_R4G4B4A4_UNORM_PACK16:
					case VK_FORMAT_B4G4R4A4_UNORM_PACK16:
					case VK_FORMAT_A4R4G4B4_UNORM_PACK16:
					case VK_FORMAT_A4B4G4R4_UNORM_PACK16:
						OFFSET_UNORM(red, 4)
						OFFSET_UNORM(green, 4)
						OFFSET_UNORM(blue, 4)
						OFFSET_UNORM(alpha, 4)
						break;
					case VK_FORMAT_R5G6B5_UNORM_PACK16:
					case VK_FORMAT_B5G6R5_UNORM_PACK16:
						OFFSET_UNORM(red, 5)
						OFFSET_UNORM(green, 6)
						OFFSET_UNORM(blue, 5)
						break;
					case VK_FORMAT_R5G5B5A1_UNORM_PACK16:
					case VK_FORMAT_B5G5R5A1_UNORM_PACK16:
					case VK_FORMAT_A1R5G5B5_UNORM_PACK16:
					case VK_FORMAT_A1B5G5R5_UNORM_PACK16:
						OFFSET_UNORM(red, 5)
						OFFSET_UNORM(green, 5)
						OFFSET_UNORM(blue, 5)
						OFFSET_UNORM(alpha, 1)
						break;
					case VK_FORMAT_A8_UNORM:
						OFFSET_UNORM(alpha, 8)
						break;
					case VK_FORMAT_R8_UNORM:
						OFFSET_UNORM(red, 8)
						break;
					case VK_FORMAT_R8_SNORM:
						OFFSET_SNORM(red, 8)
						break;
					case VK_FORMAT_R8G8_UNORM:
						OFFSET_UNORM(red, 8)
						OFFSET_UNORM(green, 8)
						break;
					case VK_FORMAT_R8G8_SNORM:
						OFFSET_SNORM(red, 8)
						OFFSET_SNORM(green, 8)
						break;
					case VK_FORMAT_R8G8B8A8_UNORM:
					case VK_FORMAT_B8G8R8A8_UNORM:
					case VK_FORMAT_B8G8R8A8_SNORM:
					case VK_FORMAT_B8G8R8A8_UINT:
					case VK_FORMAT_B8G8R8A8_SINT:
					case VK_FORMAT_A8B8G8R8_UNORM_PACK32:
						OFFSET_UNORM(red, 8)
						OFFSET_UNORM(green, 8)
						OFFSET_UNORM(blue, 8)
						OFFSET_UNORM(alpha, 8)
						break;
					case VK_FORMAT_R8G8B8A8_SNORM:
						OFFSET_SNORM(red, 8)
						OFFSET_SNORM(green, 8)
						OFFSET_SNORM(blue, 8)
						OFFSET_SNORM(alpha, 8)
						break;
					case VK_FORMAT_A2R10G10B10_UNORM_PACK32:
					case VK_FORMAT_A2B10G10R10_UNORM_PACK32:
						OFFSET_UNORM(red, 10)
						OFFSET_UNORM(green, 10)
						OFFSET_UNORM(blue, 10)
						OFFSET_UNORM(alpha, 2)
						break;
					case VK_FORMAT_R16_UNORM:
						OFFSET_UNORM(red, 16)
						break;
					case VK_FORMAT_R16_SNORM:
						OFFSET_SNORM(red, 16)
						break;
					case VK_FORMAT_R16G16_UNORM:
						OFFSET_UNORM(red, 16)
						OFFSET_UNORM(green, 16)
						break;
					case VK_FORMAT_R16G16_SNORM:
						OFFSET_SNORM(red, 16)
						OFFSET_SNORM(green, 16)
						break;
					case VK_FORMAT_R16G16B16A16_UNORM:
						OFFSET_UNORM(red, 16)
						OFFSET_UNORM(green, 16)
						OFFSET_UNORM(blue, 16)
						OFFSET_UNORM(alpha, 16)
						break;
					case VK_FORMAT_R16G16B16A16_SNORM:
						OFFSET_SNORM(red, 16)
						OFFSET_SNORM(green, 16)
						OFFSET_SNORM(blue, 16)
						OFFSET_SNORM(alpha, 16)
						break;
					default:
						break;
				}
#undef OFFSET_UNORM
#undef OFFSET_SNORM
#undef OFFSET_NORM
			}
			break;
		}
		case kMVKFormatColorUInt8:
		case kMVKFormatColorUInt16:
		case kMVKFormatColorUInt32:
			mtlClr.red   = mvkVkClearColorUIntValueFromVkComponentSwizzle(vkClearValue.color.uint32, 0, inverseMap.r);
			mtlClr.green = mvkVkClearColorUIntValueFromVkComponentSwizzle(vkClearValue.color.uint32, 1, inverseMap.g);
			mtlClr.blue  = mvkVkClearColorUIntValueFromVkComponentSwizzle(vkClearValue.color.uint32, 2, inverseMap.b);
			mtlClr.alpha = mvkVkClearColorUIntValueFromVkComponentSwizzle(vkClearValue.color.uint32, 3, inverseMap.a);
			break;
		case kMVKFormatColorInt8:
		case kMVKFormatColorInt16:
		case kMVKFormatColorInt32:
			mtlClr.red   = mvkVkClearColorIntValueFromVkComponentSwizzle(vkClearValue.color.int32, 0, inverseMap.r);
			mtlClr.green = mvkVkClearColorIntValueFromVkComponentSwizzle(vkClearValue.color.int32, 1, inverseMap.g);
			mtlClr.blue  = mvkVkClearColorIntValueFromVkComponentSwizzle(vkClearValue.color.int32, 2, inverseMap.b);
			mtlClr.alpha = mvkVkClearColorIntValueFromVkComponentSwizzle(vkClearValue.color.int32, 3, inverseMap.a);
			break;
		default:
			mtlClr.red   = 0.0;
			mtlClr.green = 0.0;
			mtlClr.blue  = 0.0;
			mtlClr.alpha = 1.0;
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
													VkSampleCountFlagBits samples,
                                                    bool isLinear,
                                                    bool needsReinterpretation,
                                                    bool isExtended,
													bool supportAtomics) {
	bool isDepthFmt = isDepthFormat(mtlFormat);
	bool isStencilFmt = isStencilFormat(mtlFormat);
	bool isCombinedDepthStencilFmt = isDepthFmt && isStencilFmt;
	bool isColorFormat = !(isDepthFmt || isStencilFmt);
	bool supportsStencilViews = _physicalDevice ? _physicalDevice->getMetalFeatures()->stencilViews : false;
	MVKMTLFmtCaps mtlFmtCaps = getCapabilities(mtlFormat, isExtended);

	MTLTextureUsage mtlUsage = MTLTextureUsageUnknown;

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

#if MVK_XCODE_15
	if (supportAtomics && (mtlFormat == MTLPixelFormatR32Uint || mtlFormat == MTLPixelFormatR32Sint)) {
		mvkEnableFlags(mtlUsage, MTLTextureUsageShaderAtomic);
	}
#endif

#if MVK_MACOS
    // Clearing a linear image may use shader writes.
    if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_TRANSFER_DST_BIT)) &&
        mvkIsAnyFlagEnabled(mtlFmtCaps, kMVKMTLFmtCapsWrite) && isLinear) {

		mvkEnableFlags(mtlUsage, MTLTextureUsageShaderWrite);
    }
#endif

	// Render to but only if format supports rendering...
	if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
												VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
												VK_IMAGE_USAGE_TRANSFER_DST_BIT)) &&	// Scaling a BLIT may use rendering.
		mvkIsAnyFlagEnabled(mtlFmtCaps, (kMVKMTLFmtCapsColorAtt | kMVKMTLFmtCapsDSAtt))) {

#if MVK_MACOS
        if(!isLinear || (_physicalDevice && _physicalDevice->getMetalFeatures()->renderLinearTextures)) {
            mvkEnableFlags(mtlUsage, MTLTextureUsageRenderTarget);
        }
#else
        mvkEnableFlags(mtlUsage, MTLTextureUsageRenderTarget);
#endif
	}

	// Resolving an MSAA color attachment whose format Metal cannot resolve natively, may use a compute shader
	// to perform theh resolve, by reading from the multisample texture and writing to the single-sample texture.
	if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)) &&
		!mvkIsAnyFlagEnabled(mtlFmtCaps, kMVKMTLFmtCapsResolve)) {

		mvkEnableFlags(mtlUsage, samples == VK_SAMPLE_COUNT_1_BIT ? MTLTextureUsageShaderWrite : MTLTextureUsageShaderRead);
	}

	bool pfv = false;

	// Swizzle emulation may need to reinterpret
	needsReinterpretation |= !_physicalDevice->getMetalFeatures()->nativeTextureSwizzle;

	pfv |= isColorFormat && needsReinterpretation &&
	       mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_SAMPLED_BIT |
	                                               VK_IMAGE_USAGE_STORAGE_BIT |
	                                               VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT |
	                                               VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT));
	pfv |= isCombinedDepthStencilFmt && supportsStencilViews &&
	       mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT | // May use temp view if transfer involves format change
	                                               VK_IMAGE_USAGE_SAMPLED_BIT |
	                                               VK_IMAGE_USAGE_STORAGE_BIT |
	                                               VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT));

	if (pfv) {
		mvkEnableFlags(mtlUsage, MTLTextureUsagePixelFormatView);
	}

	return mtlUsage;
}

// Return a reference to the Vulkan format descriptor corresponding to the VkFormat.
MVKVkFormatDesc& MVKPixelFormats::getVkFormatDesc(VkFormat vkFormat) {
	return _vkFormatDescriptions[vkFormat];
}

// Return a reference to the Vulkan format descriptor corresponding to the MTLPixelFormat.
MVKVkFormatDesc& MVKPixelFormats::getVkFormatDesc(MTLPixelFormat mtlFormat) {
	return getVkFormatDesc(getMTLPixelFormatDesc(mtlFormat).vkFormat);
}

// Return a reference to the Metal format descriptor corresponding to the MTLPixelFormat.
MVKMTLFormatDesc& MVKPixelFormats::getMTLPixelFormatDesc(MTLPixelFormat mtlFormat) {
	return _mtlPixelFormatDescriptions[mtlFormat];
}

// Return a reference to the Metal format descriptor corresponding to the MTLVertexFormat.
MVKMTLFormatDesc& MVKPixelFormats::getMTLVertexFormatDesc(MTLVertexFormat mtlFormat) {
	return _mtlVertexFormatDescriptions[mtlFormat];
}

VkFormatFeatureFlags MVKPixelFormats::convertFormatPropertiesFlagBits(VkFormatFeatureFlags2 flags) {
    // Truncate to 32-bits and just return. All current values are identical.
    return static_cast<VkFormatFeatureFlags>(flags);
}


#pragma mark Construction

MVKPixelFormats::MVKPixelFormats(MVKPhysicalDevice* physicalDevice) : _physicalDevice(physicalDevice) {

	const auto& gpuCaps = _physicalDevice ? _physicalDevice->getMTLDeviceCapabilities() : MVKMTLDeviceCapabilities(getMTLDevice());

	// Build and update the Metal formats
	initMTLPixelFormatCapabilities(gpuCaps);
	initMTLVertexFormatCapabilities(gpuCaps);
	modifyMTLFormatCapabilities(gpuCaps);

	// Build the Vulkan formats and link them to the Metal formats
	initVkFormatCapabilities();
	buildVkFormatMaps(gpuCaps);
}

// Call this sparsely. If there is no physical device, this operation may be costly.
// If supporting a physical device, retrieve the MTLDevice from it, otherwise
// retrieve the array of physical GPU devices, and use the first one.
// Retrieving the GPUs creates a number of autoreleased instances of Metal
// and other Obj-C classes, so wrap it all in an autorelease pool.
id<MTLDevice> MVKPixelFormats::getMTLDevice() {
	if (_physicalDevice) { return _physicalDevice->getMTLDevice(); }
	@autoreleasepool {
		auto* mtlDevs = mvkGetAvailableMTLDevicesArray(nullptr);
		return mtlDevs.count ? mtlDevs[0] : nil;
	}
}

#define addVkFormatDescFull(VK_FMT, MTL_FMT, MTL_FMT_ALT, MTL_VTX_FMT, MTL_VTX_FMT_ALT, CSPC, CSCB, BLK_W, BLK_H, BLK_BYTE_CNT, MVK_FMT_TYPE, SWIZ_R, SWIZ_G, SWIZ_B, SWIZ_A)  \
	vkFmt = VK_FORMAT_ ##VK_FMT;  \
	_vkFormatDescriptions[vkFmt] = { vkFmt, MTLPixelFormat ##MTL_FMT, MTLPixelFormat ##MTL_FMT_ALT, MTLVertexFormat ##MTL_VTX_FMT, MTLVertexFormat ##MTL_VTX_FMT_ALT,  \
									 CSPC, CSCB, { BLK_W, BLK_H }, BLK_BYTE_CNT, kMVKFormat ##MVK_FMT_TYPE, { VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_3, nullptr, 0, 0, 0 }, \
									 { VK_COMPONENT_SWIZZLE_ ##SWIZ_R, VK_COMPONENT_SWIZZLE_ ##SWIZ_G, VK_COMPONENT_SWIZZLE_ ##SWIZ_B, VK_COMPONENT_SWIZZLE_ ##SWIZ_A }, \
									 "VK_FORMAT_" #VK_FMT, false }

#define addVkFormatDesc(VK_FMT, MTL_FMT, MTL_FMT_ALT, MTL_VTX_FMT, MTL_VTX_FMT_ALT, BLK_W, BLK_H, BLK_BYTE_CNT, MVK_FMT_TYPE)  \
    addVkFormatDescFull(VK_FMT, MTL_FMT, MTL_FMT_ALT, MTL_VTX_FMT, MTL_VTX_FMT_ALT, 0, 0, BLK_W, BLK_H, BLK_BYTE_CNT, MVK_FMT_TYPE, IDENTITY, IDENTITY, IDENTITY, IDENTITY)

#define addVkFormatDescSwizzled(VK_FMT, MTL_FMT, MTL_FMT_ALT, MTL_VTX_FMT, MTL_VTX_FMT_ALT, BLK_W, BLK_H, BLK_BYTE_CNT, MVK_FMT_TYPE, SWIZ_R, SWIZ_G, SWIZ_B, SWIZ_A)  \
    addVkFormatDescFull(VK_FMT, MTL_FMT, MTL_FMT_ALT, MTL_VTX_FMT, MTL_VTX_FMT_ALT, 0, 0, BLK_W, BLK_H, BLK_BYTE_CNT, MVK_FMT_TYPE, SWIZ_R, SWIZ_G, SWIZ_B, SWIZ_A)

#define addVkFormatDescChromaSubsampling(VK_FMT, MTL_FMT, CSPC, CSCB, BLK_W, BLK_H, BLK_BYTE_CNT)  \
	addVkFormatDescFull(VK_FMT, MTL_FMT, Invalid, Invalid, Invalid, CSPC, CSCB, BLK_W, BLK_H, BLK_BYTE_CNT, ColorFloat, IDENTITY, IDENTITY, IDENTITY, IDENTITY)

void MVKPixelFormats::initVkFormatCapabilities() {
	VkFormat vkFmt;
	_vkFormatDescriptions.reserve(KIBI);	// High estimate to future-proof against allocations as elements are added. shrink_to_fit() below will collapse.

	// UNDEFINED must come first.
	addVkFormatDesc( UNDEFINED, Invalid, Invalid, Invalid, Invalid, 1, 1, 0, None );

	addVkFormatDesc( R4G4_UNORM_PACK8, Invalid, Invalid, Invalid, Invalid, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R4G4B4A4_UNORM_PACK16, ABGR4Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDescSwizzled( B4G4R4A4_UNORM_PACK16, ABGR4Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, B, G, R, A );
	addVkFormatDescSwizzled( A4R4G4B4_UNORM_PACK16, ABGR4Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, G, B, A, R );
	addVkFormatDescSwizzled( A4B4G4R4_UNORM_PACK16, ABGR4Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, A, B, G, R );

	addVkFormatDesc( R5G6B5_UNORM_PACK16, B5G6R5Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDescSwizzled( B5G6R5_UNORM_PACK16, B5G6R5Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, B, G, R, A );
	addVkFormatDesc( R5G5B5A1_UNORM_PACK16, A1BGR5Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDescSwizzled( B5G5R5A1_UNORM_PACK16, A1BGR5Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, B, G, R, A );
	addVkFormatDesc( A1R5G5B5_UNORM_PACK16, BGR5A1Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDescSwizzled( A1B5G5R5_UNORM_PACK16, BGR5A1Unorm, Invalid, Invalid, Invalid, 1, 1, 2, ColorFloat, B, G, R, A );

	addVkFormatDesc( A8_UNORM, A8Unorm, Invalid, UCharNormalized, UChar2Normalized, 1, 1, 1, ColorFloat );

	addVkFormatDesc( R8_UNORM, R8Unorm, Invalid, UCharNormalized, UChar2Normalized, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R8_SNORM, R8Snorm, Invalid, CharNormalized, Char2Normalized, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R8_USCALED, Invalid, Invalid, UChar, UChar2, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R8_SSCALED, Invalid, Invalid, Char, Char2, 1, 1, 1, ColorFloat );
	addVkFormatDesc( R8_UINT, R8Uint, Invalid, UChar, UChar2, 1, 1, 1, ColorUInt8 );
	addVkFormatDesc( R8_SINT, R8Sint, Invalid, Char, Char2, 1, 1, 1, ColorInt8 );
	addVkFormatDesc( R8_SRGB, R8Unorm_sRGB, Invalid, UCharNormalized, UChar2Normalized, 1, 1, 1, ColorFloat );

	addVkFormatDesc( R8G8_UNORM, RG8Unorm, Invalid, UChar2Normalized, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R8G8_SNORM, RG8Snorm, Invalid, Char2Normalized, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R8G8_USCALED, Invalid, Invalid, UChar2, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R8G8_SSCALED, Invalid, Invalid, Char2, Invalid, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R8G8_UINT, RG8Uint, Invalid, UChar2, Invalid, 1, 1, 2, ColorUInt8 );
	addVkFormatDesc( R8G8_SINT, RG8Sint, Invalid, Char2, Invalid, 1, 1, 2, ColorInt8 );
	addVkFormatDesc( R8G8_SRGB, RG8Unorm_sRGB, Invalid, UChar2Normalized, Invalid, 1, 1, 2, ColorFloat );

	addVkFormatDesc( R8G8B8_UNORM, Invalid, Invalid, UChar3Normalized, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( R8G8B8_SNORM, Invalid, Invalid, Char3Normalized, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( R8G8B8_USCALED, Invalid, Invalid, UChar3, Invalid, 1, 1, 3, ColorFloat );
	addVkFormatDesc( R8G8B8_SSCALED, Invalid, Invalid, Char3, Invalid, 1, 1, 3, ColorFloat );
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
	addVkFormatDesc( R8G8B8A8_USCALED, Invalid, Invalid, UChar4, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R8G8B8A8_SSCALED, Invalid, Invalid, Char4, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R8G8B8A8_UINT, RGBA8Uint, Invalid, UChar4, Invalid, 1, 1, 4, ColorUInt8 );
	addVkFormatDesc( R8G8B8A8_SINT, RGBA8Sint, Invalid, Char4, Invalid, 1, 1, 4, ColorInt8 );
	addVkFormatDesc( R8G8B8A8_SRGB, RGBA8Unorm_sRGB, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat );

	addVkFormatDesc( B8G8R8A8_UNORM, BGRA8Unorm, Invalid, UChar4Normalized_BGRA, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDescSwizzled( B8G8R8A8_SNORM, RGBA8Snorm, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat, B, G, R, A );
	addVkFormatDesc( B8G8R8A8_USCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( B8G8R8A8_SSCALED, Invalid, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDescSwizzled( B8G8R8A8_UINT, RGBA8Uint, Invalid, Invalid, Invalid, 1, 1, 4, ColorUInt8, B, G, R, A );
	addVkFormatDescSwizzled( B8G8R8A8_SINT, RGBA8Sint, Invalid, Invalid, Invalid, 1, 1, 4, ColorInt8, B, G, R, A );
	addVkFormatDesc( B8G8R8A8_SRGB, BGRA8Unorm_sRGB, Invalid, Invalid, Invalid, 1, 1, 4, ColorFloat );

	addVkFormatDesc( A8B8G8R8_UNORM_PACK32, RGBA8Unorm, Invalid, UChar4Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A8B8G8R8_SNORM_PACK32, RGBA8Snorm, Invalid, Char4Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A8B8G8R8_USCALED_PACK32, Invalid, Invalid, UChar4, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( A8B8G8R8_SSCALED_PACK32, Invalid, Invalid, Char4, Invalid, 1, 1, 4, ColorFloat );
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
	addVkFormatDesc( R16_USCALED, Invalid, Invalid, UShort, UShort2, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R16_SSCALED, Invalid, Invalid, Short, Short2, 1, 1, 2, ColorFloat );
	addVkFormatDesc( R16_UINT, R16Uint, Invalid, UShort, UShort2, 1, 1, 2, ColorUInt16 );
	addVkFormatDesc( R16_SINT, R16Sint, Invalid, Short, Short2, 1, 1, 2, ColorInt16 );
	addVkFormatDesc( R16_SFLOAT, R16Float, Invalid, Half, Half2, 1, 1, 2, ColorFloat );

	addVkFormatDesc( R16G16_UNORM, RG16Unorm, Invalid, UShort2Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R16G16_SNORM, RG16Snorm, Invalid, Short2Normalized, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R16G16_USCALED, Invalid, Invalid, UShort2, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R16G16_SSCALED, Invalid, Invalid, Short2, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( R16G16_UINT, RG16Uint, Invalid, UShort2, Invalid, 1, 1, 4, ColorUInt16 );
	addVkFormatDesc( R16G16_SINT, RG16Sint, Invalid, Short2, Invalid, 1, 1, 4, ColorInt16 );
	addVkFormatDesc( R16G16_SFLOAT, RG16Float, Invalid, Half2, Invalid, 1, 1, 4, ColorFloat );

	addVkFormatDesc( R16G16B16_UNORM, Invalid, Invalid, UShort3Normalized, Invalid, 1, 1, 6, ColorFloat );
	addVkFormatDesc( R16G16B16_SNORM, Invalid, Invalid, Short3Normalized, Invalid, 1, 1, 6, ColorFloat );
	addVkFormatDesc( R16G16B16_USCALED, Invalid, Invalid, UShort3, Invalid, 1, 1, 6, ColorFloat );
	addVkFormatDesc( R16G16B16_SSCALED, Invalid, Invalid, Short3, Invalid, 1, 1, 6, ColorFloat );
	addVkFormatDesc( R16G16B16_UINT, Invalid, Invalid, UShort3, Invalid, 1, 1, 6, ColorUInt16 );
	addVkFormatDesc( R16G16B16_SINT, Invalid, Invalid, Short3, Invalid, 1, 1, 6, ColorInt16 );
	addVkFormatDesc( R16G16B16_SFLOAT, Invalid, Invalid, Half3, Invalid, 1, 1, 6, ColorFloat );

	addVkFormatDesc( R16G16B16A16_UNORM, RGBA16Unorm, Invalid, UShort4Normalized, Invalid, 1, 1, 8, ColorFloat );
	addVkFormatDesc( R16G16B16A16_SNORM, RGBA16Snorm, Invalid, Short4Normalized, Invalid, 1, 1, 8, ColorFloat );
	addVkFormatDesc( R16G16B16A16_USCALED, Invalid, Invalid, UShort4, Invalid, 1, 1, 8, ColorFloat );
	addVkFormatDesc( R16G16B16A16_SSCALED, Invalid, Invalid, Short4, Invalid, 1, 1, 8, ColorFloat );
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

	addVkFormatDesc( B10G11R11_UFLOAT_PACK32, RG11B10Float, Invalid, FloatRG11B10, Invalid, 1, 1, 4, ColorFloat );
	addVkFormatDesc( E5B9G9R9_UFLOAT_PACK32, RGB9E5Float, Invalid, FloatRGB9E5, Invalid, 1, 1, 4, ColorFloat );
	
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
	addVkFormatDesc( ASTC_4x4_SFLOAT_BLOCK, ASTC_4x4_HDR, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( ASTC_4x4_SRGB_BLOCK, ASTC_4x4_sRGB, Invalid, Invalid, Invalid, 4, 4, 16, Compressed );
	addVkFormatDesc( ASTC_5x4_UNORM_BLOCK, ASTC_5x4_LDR, Invalid, Invalid, Invalid, 5, 4, 16, Compressed );
	addVkFormatDesc( ASTC_5x4_SFLOAT_BLOCK, ASTC_5x4_HDR, Invalid, Invalid, Invalid, 5, 4, 16, Compressed );
	addVkFormatDesc( ASTC_5x4_SRGB_BLOCK, ASTC_5x4_sRGB, Invalid, Invalid, Invalid, 5, 4, 16, Compressed );
	addVkFormatDesc( ASTC_5x5_UNORM_BLOCK, ASTC_5x5_LDR, Invalid, Invalid, Invalid, 5, 5, 16, Compressed );
	addVkFormatDesc( ASTC_5x5_SFLOAT_BLOCK, ASTC_5x5_HDR, Invalid, Invalid, Invalid, 5, 5, 16, Compressed );
	addVkFormatDesc( ASTC_5x5_SRGB_BLOCK, ASTC_5x5_sRGB, Invalid, Invalid, Invalid, 5, 5, 16, Compressed );
	addVkFormatDesc( ASTC_6x5_UNORM_BLOCK, ASTC_6x5_LDR, Invalid, Invalid, Invalid, 6, 5, 16, Compressed );
	addVkFormatDesc( ASTC_6x5_SFLOAT_BLOCK, ASTC_6x5_HDR, Invalid, Invalid, Invalid, 6, 5, 16, Compressed );
	addVkFormatDesc( ASTC_6x5_SRGB_BLOCK, ASTC_6x5_sRGB, Invalid, Invalid, Invalid, 6, 5, 16, Compressed );
	addVkFormatDesc( ASTC_6x6_UNORM_BLOCK, ASTC_6x6_LDR, Invalid, Invalid, Invalid, 6, 6, 16, Compressed );
	addVkFormatDesc( ASTC_6x6_SFLOAT_BLOCK, ASTC_6x6_HDR, Invalid, Invalid, Invalid, 6, 6, 16, Compressed );
	addVkFormatDesc( ASTC_6x6_SRGB_BLOCK, ASTC_6x6_sRGB, Invalid, Invalid, Invalid, 6, 6, 16, Compressed );
	addVkFormatDesc( ASTC_8x5_UNORM_BLOCK, ASTC_8x5_LDR, Invalid, Invalid, Invalid, 8, 5, 16, Compressed );
	addVkFormatDesc( ASTC_8x5_SFLOAT_BLOCK, ASTC_8x5_HDR, Invalid, Invalid, Invalid, 8, 5, 16, Compressed );
	addVkFormatDesc( ASTC_8x5_SRGB_BLOCK, ASTC_8x5_sRGB, Invalid, Invalid, Invalid, 8, 5, 16, Compressed );
	addVkFormatDesc( ASTC_8x6_UNORM_BLOCK, ASTC_8x6_LDR, Invalid, Invalid, Invalid, 8, 6, 16, Compressed );
	addVkFormatDesc( ASTC_8x6_SFLOAT_BLOCK, ASTC_8x6_HDR, Invalid, Invalid, Invalid, 8, 6, 16, Compressed );
	addVkFormatDesc( ASTC_8x6_SRGB_BLOCK, ASTC_8x6_sRGB, Invalid, Invalid, Invalid, 8, 6, 16, Compressed );
	addVkFormatDesc( ASTC_8x8_UNORM_BLOCK, ASTC_8x8_LDR, Invalid, Invalid, Invalid, 8, 8, 16, Compressed );
	addVkFormatDesc( ASTC_8x8_SFLOAT_BLOCK, ASTC_8x8_HDR, Invalid, Invalid, Invalid, 8, 8, 16, Compressed );
	addVkFormatDesc( ASTC_8x8_SRGB_BLOCK, ASTC_8x8_sRGB, Invalid, Invalid, Invalid, 8, 8, 16, Compressed );
	addVkFormatDesc( ASTC_10x5_UNORM_BLOCK, ASTC_10x5_LDR, Invalid, Invalid, Invalid, 10, 5, 16, Compressed );
	addVkFormatDesc( ASTC_10x5_SFLOAT_BLOCK, ASTC_10x5_HDR, Invalid, Invalid, Invalid, 10, 5, 16, Compressed );
	addVkFormatDesc( ASTC_10x5_SRGB_BLOCK, ASTC_10x5_sRGB, Invalid, Invalid, Invalid, 10, 5, 16, Compressed );
	addVkFormatDesc( ASTC_10x6_UNORM_BLOCK, ASTC_10x6_LDR, Invalid, Invalid, Invalid, 10, 6, 16, Compressed );
	addVkFormatDesc( ASTC_10x6_SFLOAT_BLOCK, ASTC_10x6_HDR, Invalid, Invalid, Invalid, 10, 6, 16, Compressed );
	addVkFormatDesc( ASTC_10x6_SRGB_BLOCK, ASTC_10x6_sRGB, Invalid, Invalid, Invalid, 10, 6, 16, Compressed );
	addVkFormatDesc( ASTC_10x8_UNORM_BLOCK, ASTC_10x8_LDR, Invalid, Invalid, Invalid, 10, 8, 16, Compressed );
	addVkFormatDesc( ASTC_10x8_SFLOAT_BLOCK, ASTC_10x8_HDR, Invalid, Invalid, Invalid, 10, 8, 16, Compressed );
	addVkFormatDesc( ASTC_10x8_SRGB_BLOCK, ASTC_10x8_sRGB, Invalid, Invalid, Invalid, 10, 8, 16, Compressed );
	addVkFormatDesc( ASTC_10x10_UNORM_BLOCK, ASTC_10x10_LDR, Invalid, Invalid, Invalid, 10, 10, 16, Compressed );
	addVkFormatDesc( ASTC_10x10_SFLOAT_BLOCK, ASTC_10x10_HDR, Invalid, Invalid, Invalid, 10, 10, 16, Compressed );
	addVkFormatDesc( ASTC_10x10_SRGB_BLOCK, ASTC_10x10_sRGB, Invalid, Invalid, Invalid, 10, 10, 16, Compressed );
	addVkFormatDesc( ASTC_12x10_UNORM_BLOCK, ASTC_12x10_LDR, Invalid, Invalid, Invalid, 12, 10, 16, Compressed );
	addVkFormatDesc( ASTC_12x10_SFLOAT_BLOCK, ASTC_12x10_HDR, Invalid, Invalid, Invalid, 12, 10, 16, Compressed );
	addVkFormatDesc( ASTC_12x10_SRGB_BLOCK, ASTC_12x10_sRGB, Invalid, Invalid, Invalid, 12, 10, 16, Compressed );
	addVkFormatDesc( ASTC_12x12_UNORM_BLOCK, ASTC_12x12_LDR, Invalid, Invalid, Invalid, 12, 12, 16, Compressed );
	addVkFormatDesc( ASTC_12x12_SFLOAT_BLOCK, ASTC_12x12_HDR, Invalid, Invalid, Invalid, 12, 12, 16, Compressed );
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

	// Extension VK_KHR_sampler_ycbcr_conversion
    addVkFormatDescChromaSubsampling( G8B8G8R8_422_UNORM, GBGR422, 1, 8, 2, 1, 4 );
    addVkFormatDescChromaSubsampling( B8G8R8G8_422_UNORM, BGRG422, 1, 8, 2, 1, 4 );
    addVkFormatDescChromaSubsampling( G8_B8_R8_3PLANE_420_UNORM, Invalid, 3, 8, 2, 2, 6 );
    addVkFormatDescChromaSubsampling( G8_B8R8_2PLANE_420_UNORM, Invalid, 2, 8, 2, 2, 6 );
    addVkFormatDescChromaSubsampling( G8_B8_R8_3PLANE_422_UNORM, Invalid, 3, 8, 2, 1, 4 );
    addVkFormatDescChromaSubsampling( G8_B8R8_2PLANE_422_UNORM, Invalid, 2, 8, 2, 1, 4 );
    addVkFormatDescChromaSubsampling( G8_B8_R8_3PLANE_444_UNORM, Invalid, 3, 8, 1, 1, 3 );
    addVkFormatDescChromaSubsampling( R10X6_UNORM_PACK16, R16Unorm, 0, 10, 1, 1, 2 );
    addVkFormatDescChromaSubsampling( R10X6G10X6_UNORM_2PACK16, RG16Unorm, 0, 10, 1, 1, 4 );
    addVkFormatDescChromaSubsampling( R10X6G10X6B10X6A10X6_UNORM_4PACK16, RGBA16Unorm, 0, 10, 1, 1, 8 );
    addVkFormatDescChromaSubsampling( G10X6B10X6G10X6R10X6_422_UNORM_4PACK16, Invalid, 1, 10, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( B10X6G10X6R10X6G10X6_422_UNORM_4PACK16, Invalid, 1, 10, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( G10X6_B10X6_R10X6_3PLANE_420_UNORM_3PACK16, Invalid, 3, 10, 2, 2, 12 );
    addVkFormatDescChromaSubsampling( G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16, Invalid, 2, 10, 2, 2, 12 );
    addVkFormatDescChromaSubsampling( G10X6_B10X6_R10X6_3PLANE_422_UNORM_3PACK16, Invalid, 3, 10, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( G10X6_B10X6R10X6_2PLANE_422_UNORM_3PACK16, Invalid, 2, 10, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( G10X6_B10X6_R10X6_3PLANE_444_UNORM_3PACK16, Invalid, 3, 10, 1, 1, 6 );
    addVkFormatDescChromaSubsampling( R12X4_UNORM_PACK16, R16Unorm, 0, 12, 1, 1, 2 );
    addVkFormatDescChromaSubsampling( R12X4G12X4_UNORM_2PACK16, RG16Unorm, 0, 12, 1, 1, 4 );
    addVkFormatDescChromaSubsampling( R12X4G12X4B12X4A12X4_UNORM_4PACK16, RGBA16Unorm, 0, 12, 1, 1, 8 );
    addVkFormatDescChromaSubsampling( G12X4B12X4G12X4R12X4_422_UNORM_4PACK16, Invalid, 1, 12, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( B12X4G12X4R12X4G12X4_422_UNORM_4PACK16, Invalid, 1, 12, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( G12X4_B12X4_R12X4_3PLANE_420_UNORM_3PACK16, Invalid, 3, 12, 2, 2, 12 );
    addVkFormatDescChromaSubsampling( G12X4_B12X4R12X4_2PLANE_420_UNORM_3PACK16, Invalid, 2, 12, 2, 2, 12 );
    addVkFormatDescChromaSubsampling( G12X4_B12X4_R12X4_3PLANE_422_UNORM_3PACK16, Invalid, 3, 12, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( G12X4_B12X4R12X4_2PLANE_422_UNORM_3PACK16, Invalid, 2, 12, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( G12X4_B12X4_R12X4_3PLANE_444_UNORM_3PACK16, Invalid, 3, 12, 1, 1, 6 );
    addVkFormatDescChromaSubsampling( G16B16G16R16_422_UNORM, Invalid, 1, 16, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( B16G16R16G16_422_UNORM, Invalid, 1, 16, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( G16_B16_R16_3PLANE_420_UNORM, Invalid, 3, 16, 2, 2, 12 );
    addVkFormatDescChromaSubsampling( G16_B16R16_2PLANE_420_UNORM, Invalid, 2, 16, 2, 2, 12 );
    addVkFormatDescChromaSubsampling( G16_B16_R16_3PLANE_422_UNORM, Invalid, 3, 16, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( G16_B16R16_2PLANE_422_UNORM, Invalid, 2, 16, 2, 1, 8 );
    addVkFormatDescChromaSubsampling( G16_B16_R16_3PLANE_444_UNORM, Invalid, 3, 16, 1, 1, 6 );

	_vkFormatDescriptions.shrink_to_fit();
}

void MVKPixelFormats::addMTLPixelFormatDescImpl(MTLPixelFormat mtlPixFmt, MTLPixelFormat mtlPixFmtLinear,
												MVKMTLViewClass viewClass, MVKMTLFmtCaps fmtCaps, const char* name) {
	_mtlPixelFormatDescriptions[mtlPixFmt] = { .mtlPixelFormat = mtlPixFmt, VK_FORMAT_UNDEFINED, fmtCaps, viewClass, mtlPixFmtLinear, name };
}

// Verify mtlFmt exists on platform, to avoid overwriting the MTLPixelFormatInvalid entry.
// Select the appropriate capabilities for the GPU. Apple Silicon on Mac is a blend of both Apple and Mac caps.
void MVKPixelFormats::addValidatedMTLPixelFormatDesc(MTLPixelFormat mtlPixFmt, MTLPixelFormat mtlPixFmtLinear,
													 MVKMTLViewClass viewClass, MVKMTLFmtCaps appleGPUCaps, MVKMTLFmtCaps macGPUCaps,
													 const MVKMTLDeviceCapabilities& mtlDevCaps, const char* name) {
	if ( !mtlPixFmt) { return; }

	MVKMTLFmtCaps fmtCaps = kMVKMTLFmtCapsNone;
	if (mtlDevCaps.isAppleGPU && mtlDevCaps.supportsMac1) {
		mvkEnableFlags(fmtCaps, appleGPUCaps);
		mvkEnableFlags(fmtCaps, macGPUCaps);
	} else {
		fmtCaps = mtlDevCaps.isAppleGPU ? appleGPUCaps : macGPUCaps;
	}
	addMTLPixelFormatDescImpl(mtlPixFmt, mtlPixFmtLinear, viewClass, fmtCaps, name);
}

#define addMTLPixelFormatDescFull(mtlFmt, mtlFmtLinear, viewClass, appleGPUCaps, macGPUCaps)  \
	addValidatedMTLPixelFormatDesc(MTLPixelFormat ##mtlFmt, MTLPixelFormat ##mtlFmtLinear, MVKMTLViewClass:: viewClass,  \
	                               appleGPUCaps, macGPUCaps, gpuCaps, "MTLPixelFormat" #mtlFmt)

#define addMTLPixelFormatDesc(mtlFmt, viewClass, appleGPUCaps, macGPUCaps)  \
	addMTLPixelFormatDescFull(mtlFmt, mtlFmt, viewClass, kMVKMTLFmtCaps ##appleGPUCaps, kMVKMTLFmtCaps ##macGPUCaps)

#define addMTLPixelFormatDescSRGB(mtlFmt, viewClass, appleGPUCaps, macGPUCaps, mtlFmtLinear)  \
	/* Cannot write to sRGB textures in the simulator */  \
	if(MVK_OS_SIMULATOR) { MVKMTLFmtCaps appleFmtCaps = kMVKMTLFmtCaps ##appleGPUCaps;  \
	                       mvkDisableFlags(appleFmtCaps, kMVKMTLFmtCapsWrite);  \
	                       addMTLPixelFormatDescFull(mtlFmt, mtlFmtLinear, viewClass, appleFmtCaps, kMVKMTLFmtCaps ##macGPUCaps); }  \
	else                 { addMTLPixelFormatDescFull(mtlFmt, mtlFmtLinear, viewClass, kMVKMTLFmtCaps ##appleGPUCaps, kMVKMTLFmtCaps ##macGPUCaps); }

void MVKPixelFormats::initMTLPixelFormatCapabilities(const MVKMTLDeviceCapabilities& gpuCaps) {
	_mtlPixelFormatDescriptions.reserve(KIBI);	// High estimate to future-proof against allocations as elements are added. shrink_to_fit() below will collapse.

	// MTLPixelFormatInvalid must come first. Use addMTLPixelFormatDescImpl to avoid guard code.
	addMTLPixelFormatDescImpl( MTLPixelFormatInvalid, MTLPixelFormatInvalid, MVKMTLViewClass::None, kMVKMTLFmtCapsNone, "MTLPixelFormatInvalid" );

	// Ordinary 8-bit pixel formats
	addMTLPixelFormatDesc    ( A8Unorm, Color8, All, All );
	addMTLPixelFormatDesc    ( R8Unorm, Color8, All, All );
	addMTLPixelFormatDescSRGB( R8Unorm_sRGB, Color8, All, None, R8Unorm );
	addMTLPixelFormatDesc    ( R8Snorm, Color8, All, All );
	addMTLPixelFormatDesc    ( R8Uint, Color8, RWCM, RWCM );
	addMTLPixelFormatDesc    ( R8Sint, Color8, RWCM, RWCM );

	// Ordinary 16-bit pixel formats
	addMTLPixelFormatDesc    ( R16Unorm, Color16, RFWCMB, All );
	addMTLPixelFormatDesc    ( R16Snorm, Color16, RFWCMB, All );
	addMTLPixelFormatDesc    ( R16Uint, Color16, RWCM, RWCM );
	addMTLPixelFormatDesc    ( R16Sint, Color16, RWCM, RWCM );
	addMTLPixelFormatDesc    ( R16Float, Color16, All, All );

	addMTLPixelFormatDesc    ( RG8Unorm, Color16, All, All );
	addMTLPixelFormatDescSRGB( RG8Unorm_sRGB, Color16, All, None, RG8Unorm );
	addMTLPixelFormatDesc    ( RG8Snorm, Color16, All, All );
	addMTLPixelFormatDesc    ( RG8Uint, Color16, RWCM, RWCM );
	addMTLPixelFormatDesc    ( RG8Sint, Color16, RWCM, RWCM );

	// Packed 16-bit pixel formats
	addMTLPixelFormatDesc    ( B5G6R5Unorm, Color16, RFCMRB, None );
	addMTLPixelFormatDesc    ( A1BGR5Unorm, Color16, RFCMRB, None );
	addMTLPixelFormatDesc    ( ABGR4Unorm, Color16, RFCMRB, None );
	addMTLPixelFormatDesc    ( BGR5A1Unorm, Color16, RFCMRB, None );

	// Ordinary 32-bit pixel formats
	addMTLPixelFormatDesc    ( R32Uint, Color32, RWC, RWCM );
	addMTLPixelFormatDesc    ( R32Sint, Color32, RWC, RWCM );
	addMTLPixelFormatDesc    ( R32Float, Color32, All, All );

	addMTLPixelFormatDesc    ( RG16Unorm, Color32, RFWCMB, All );
	addMTLPixelFormatDesc    ( RG16Snorm, Color32, RFWCMB, All );
	addMTLPixelFormatDesc    ( RG16Uint, Color32, RWCM, RWCM );
	addMTLPixelFormatDesc    ( RG16Sint, Color32, RWCM, RWCM );
	addMTLPixelFormatDesc    ( RG16Float, Color32, All, All );

	addMTLPixelFormatDesc    ( RGBA8Unorm, Color32, All, All );
	addMTLPixelFormatDescSRGB( RGBA8Unorm_sRGB, Color32, All, RFCMRB, RGBA8Unorm );
	addMTLPixelFormatDesc    ( RGBA8Snorm, Color32, All, All );
	addMTLPixelFormatDesc    ( RGBA8Uint, Color32, RWCM, RWCM );
	addMTLPixelFormatDesc    ( RGBA8Sint, Color32, RWCM, RWCM );

	addMTLPixelFormatDesc    ( BGRA8Unorm, Color32, All, All );
	addMTLPixelFormatDescSRGB( BGRA8Unorm_sRGB, Color32, All, RFCMRB, BGRA8Unorm );

	// Packed 32-bit pixel formats
	addMTLPixelFormatDesc    ( RGB10A2Unorm, Color32, All, All );
	addMTLPixelFormatDesc    ( BGR10A2Unorm, Color32, All, All );
	addMTLPixelFormatDesc    ( RGB10A2Uint, Color32, RWCM, RWCM );
	addMTLPixelFormatDesc    ( RG11B10Float, Color32, All, All );
	addMTLPixelFormatDesc    ( RGB9E5Float, Color32, All, RF );

	// Ordinary 64-bit pixel formats
	addMTLPixelFormatDesc    ( RG32Uint, Color64, RWCM, RWCM );
	addMTLPixelFormatDesc    ( RG32Sint, Color64, RWCM, RWCM );
	addMTLPixelFormatDesc    ( RG32Float, Color64, All, All );

	addMTLPixelFormatDesc    ( RGBA16Unorm, Color64, RFWCMB, All );
	addMTLPixelFormatDesc    ( RGBA16Snorm, Color64, RFWCMB, All );
	addMTLPixelFormatDesc    ( RGBA16Uint, Color64, RWCM, RWCM );
	addMTLPixelFormatDesc    ( RGBA16Sint, Color64, RWCM, RWCM );
	addMTLPixelFormatDesc    ( RGBA16Float, Color64, All, All );

	// Ordinary 128-bit pixel formats
	addMTLPixelFormatDesc    ( RGBA32Uint, Color128, RWC, RWCM );
	addMTLPixelFormatDesc    ( RGBA32Sint, Color128, RWC, RWCM );
	addMTLPixelFormatDesc    ( RGBA32Float, Color128, All, All );

	// Compressed pixel formats
	addMTLPixelFormatDesc    ( PVRTC_RGBA_2BPP, PVRTC_RGBA_2BPP, RF, None );
	addMTLPixelFormatDescSRGB( PVRTC_RGBA_2BPP_sRGB, PVRTC_RGBA_2BPP, RF, None, PVRTC_RGBA_2BPP );
	addMTLPixelFormatDesc    ( PVRTC_RGBA_4BPP, PVRTC_RGBA_4BPP, RF, None );
	addMTLPixelFormatDescSRGB( PVRTC_RGBA_4BPP_sRGB, PVRTC_RGBA_4BPP, RF, None, PVRTC_RGBA_4BPP );

	addMTLPixelFormatDesc    ( ETC2_RGB8, ETC2_RGB8, RF, None );
	addMTLPixelFormatDescSRGB( ETC2_RGB8_sRGB, ETC2_RGB8, RF, None, ETC2_RGB8 );
	addMTLPixelFormatDesc    ( ETC2_RGB8A1, ETC2_RGB8A1, RF, None );
	addMTLPixelFormatDescSRGB( ETC2_RGB8A1_sRGB, ETC2_RGB8A1, RF, None, ETC2_RGB8A1 );
	addMTLPixelFormatDesc    ( EAC_RGBA8, EAC_RGBA8, RF, None );
	addMTLPixelFormatDescSRGB( EAC_RGBA8_sRGB, EAC_RGBA8, RF, None, EAC_RGBA8 );
	addMTLPixelFormatDesc    ( EAC_R11Unorm, EAC_R11, RF, None );
	addMTLPixelFormatDesc    ( EAC_R11Snorm, EAC_R11, RF, None );
	addMTLPixelFormatDesc    ( EAC_RG11Unorm, EAC_RG11, RF, None );
	addMTLPixelFormatDesc    ( EAC_RG11Snorm, EAC_RG11, RF, None );

	addMTLPixelFormatDesc    ( ASTC_4x4_LDR, ASTC_4x4, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_4x4_sRGB, ASTC_4x4, RF, None, ASTC_4x4_LDR );
	addMTLPixelFormatDesc    ( ASTC_4x4_HDR, ASTC_4x4, RF, None );
	addMTLPixelFormatDesc    ( ASTC_5x4_LDR, ASTC_5x4, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_5x4_sRGB, ASTC_5x4, RF, None, ASTC_5x4_LDR );
	addMTLPixelFormatDesc    ( ASTC_5x4_HDR, ASTC_5x4, RF, None );
	addMTLPixelFormatDesc    ( ASTC_5x5_LDR, ASTC_5x5, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_5x5_sRGB, ASTC_5x5, RF, None, ASTC_5x5_LDR );
	addMTLPixelFormatDesc    ( ASTC_5x5_HDR, ASTC_5x5, RF, None );
	addMTLPixelFormatDesc    ( ASTC_6x5_LDR, ASTC_6x5, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_6x5_sRGB, ASTC_6x5, RF, None, ASTC_6x5_LDR );
	addMTLPixelFormatDesc    ( ASTC_6x5_HDR, ASTC_6x5, RF, None );
	addMTLPixelFormatDesc    ( ASTC_6x6_LDR, ASTC_6x6, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_6x6_sRGB, ASTC_6x6, RF, None, ASTC_6x6_LDR );
	addMTLPixelFormatDesc    ( ASTC_6x6_HDR, ASTC_6x6, RF, None );
	addMTLPixelFormatDesc    ( ASTC_8x5_LDR, ASTC_8x5, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_8x5_sRGB, ASTC_8x5, RF, None, ASTC_8x5_LDR );
	addMTLPixelFormatDesc    ( ASTC_8x5_HDR, ASTC_8x5, RF, None );
	addMTLPixelFormatDesc    ( ASTC_8x6_LDR, ASTC_8x6, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_8x6_sRGB, ASTC_8x6, RF, None, ASTC_8x6_LDR );
	addMTLPixelFormatDesc    ( ASTC_8x6_HDR, ASTC_8x6, RF, None );
	addMTLPixelFormatDesc    ( ASTC_8x8_LDR, ASTC_8x8, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_8x8_sRGB, ASTC_8x8, RF, None, ASTC_8x8_LDR );
	addMTLPixelFormatDesc    ( ASTC_8x8_HDR, ASTC_8x8, RF, None );
	addMTLPixelFormatDesc    ( ASTC_10x5_LDR, ASTC_10x5, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_10x5_sRGB, ASTC_10x5, RF, None, ASTC_10x5_LDR );
	addMTLPixelFormatDesc    ( ASTC_10x5_HDR, ASTC_10x5, RF, None );
	addMTLPixelFormatDesc    ( ASTC_10x6_LDR, ASTC_10x6, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_10x6_sRGB, ASTC_10x6, RF, None, ASTC_10x6_LDR );
	addMTLPixelFormatDesc    ( ASTC_10x6_HDR, ASTC_10x6, RF, None );
	addMTLPixelFormatDesc    ( ASTC_10x8_LDR, ASTC_10x8, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_10x8_sRGB, ASTC_10x8, RF, None, ASTC_10x8_LDR );
	addMTLPixelFormatDesc    ( ASTC_10x8_HDR, ASTC_10x8, RF, None );
	addMTLPixelFormatDesc    ( ASTC_10x10_LDR, ASTC_10x10, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_10x10_sRGB, ASTC_10x10, RF, None, ASTC_10x10_LDR );
	addMTLPixelFormatDesc    ( ASTC_10x10_HDR, ASTC_10x10, RF, None );
	addMTLPixelFormatDesc    ( ASTC_12x10_LDR, ASTC_12x10, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_12x10_sRGB, ASTC_12x10, RF, None, ASTC_12x10_LDR );
	addMTLPixelFormatDesc    ( ASTC_12x10_HDR, ASTC_12x10, RF, None );
	addMTLPixelFormatDesc    ( ASTC_12x12_LDR, ASTC_12x12, RF, None );
	addMTLPixelFormatDescSRGB( ASTC_12x12_sRGB, ASTC_12x12, RF, None, ASTC_12x12_LDR );
	addMTLPixelFormatDesc    ( ASTC_12x12_HDR, ASTC_12x12, RF, None );

	addMTLPixelFormatDesc    ( BC1_RGBA, BC1_RGBA, RF, RF );
	addMTLPixelFormatDescSRGB( BC1_RGBA_sRGB, BC1_RGBA, RF, RF, BC1_RGBA );
	addMTLPixelFormatDesc    ( BC2_RGBA, BC2_RGBA, RF, RF );
	addMTLPixelFormatDescSRGB( BC2_RGBA_sRGB, BC2_RGBA, RF, RF, BC2_RGBA );
	addMTLPixelFormatDesc    ( BC3_RGBA, BC3_RGBA, RF, RF );
	addMTLPixelFormatDescSRGB( BC3_RGBA_sRGB, BC3_RGBA, RF, RF, BC3_RGBA );
	addMTLPixelFormatDesc    ( BC4_RUnorm, BC4_R, RF, RF );
	addMTLPixelFormatDesc    ( BC4_RSnorm, BC4_R, RF, RF );
	addMTLPixelFormatDesc    ( BC5_RGUnorm, BC5_RG, RF, RF );
	addMTLPixelFormatDesc    ( BC5_RGSnorm, BC5_RG, RF, RF );
	addMTLPixelFormatDesc    ( BC6H_RGBUfloat, BC6H_RGB, RF, RF );
	addMTLPixelFormatDesc    ( BC6H_RGBFloat, BC6H_RGB, RF, RF );
	addMTLPixelFormatDesc    ( BC7_RGBAUnorm, BC7_RGBA, RF, RF );
	addMTLPixelFormatDescSRGB( BC7_RGBAUnorm_sRGB, BC7_RGBA, RF, RF, BC7_RGBAUnorm );

	// YUV pixel formats
	addMTLPixelFormatDesc    ( GBGR422, None, RF, RF );
	addMTLPixelFormatDesc    ( BGRG422, None, RF, RF );

	// Extended range and wide color pixel formats
	addMTLPixelFormatDesc    ( BGRA10_XR, BGRA10_XR, All, None );
	addMTLPixelFormatDescSRGB( BGRA10_XR_sRGB, BGRA10_XR, All, None, BGRA10_XR );
	addMTLPixelFormatDesc    ( BGR10_XR, BGR10_XR, All, None );
	addMTLPixelFormatDescSRGB( BGR10_XR_sRGB, BGR10_XR, All, None, BGR10_XR );

	// Depth and stencil pixel formats
	addMTLPixelFormatDesc    ( Depth16Unorm, None, DRFMR, DRFMR );
	addMTLPixelFormatDesc    ( Depth32Float, None, DRMR, DRFMR );
	addMTLPixelFormatDesc    ( Stencil8, None, DRM, DRM );
	addMTLPixelFormatDesc    ( Depth24Unorm_Stencil8, Depth24_Stencil8, None, DRFMR );
	addMTLPixelFormatDesc    ( Depth32Float_Stencil8, Depth32_Stencil8, DRMR, DRFMR );
	addMTLPixelFormatDesc    ( X24_Stencil8, Depth24_Stencil8, None, DRM );
	addMTLPixelFormatDesc    ( X32_Stencil8, Depth32_Stencil8, DRM, DRM );

	_mtlPixelFormatDescriptions.shrink_to_fit();
}

// If necessary, resize vector with empty elements
void MVKPixelFormats::addMTLVertexFormatDescImpl(MTLVertexFormat mtlVtxFmt, MVKMTLFmtCaps vtxCap, const char* name) {
	if (mtlVtxFmt >= _mtlVertexFormatDescriptions.size()) { _mtlVertexFormatDescriptions.resize(mtlVtxFmt + 1, {}); }
	_mtlVertexFormatDescriptions[mtlVtxFmt] = { .mtlVertexFormat = mtlVtxFmt, VK_FORMAT_UNDEFINED, vtxCap, MVKMTLViewClass::None, MTLPixelFormatInvalid, name };
}

// Check mtlVtx exists on platform, to avoid overwriting the MTLVertexFormatInvalid entry.
#define addMTLVertexFormatDesc(mtlVtx)  if (MTLVertexFormat ##mtlVtx) { addMTLVertexFormatDescImpl(MTLVertexFormat ##mtlVtx, kMVKMTLFmtCapsVertex, "MTLVertexFormat" #mtlVtx); }

void MVKPixelFormats::initMTLVertexFormatCapabilities(const MVKMTLDeviceCapabilities& gpuCaps) {
	_mtlVertexFormatDescriptions.resize(MTLVertexFormatHalf + 3, {});

	// MTLVertexFormatInvalid must come first. Use addMTLVertexFormatDescImpl to avoid guard code.
	addMTLVertexFormatDescImpl(MTLVertexFormatInvalid, kMVKMTLFmtCapsNone, "MTLVertexFormatInvalid");

	addMTLVertexFormatDesc( UChar2Normalized );
	addMTLVertexFormatDesc( Char2Normalized );
	addMTLVertexFormatDesc( UChar2 );
	addMTLVertexFormatDesc( Char2 );

	addMTLVertexFormatDesc( UChar3Normalized );
	addMTLVertexFormatDesc( Char3Normalized );
	addMTLVertexFormatDesc( UChar3 );
	addMTLVertexFormatDesc( Char3 );

	addMTLVertexFormatDesc( UChar4Normalized );
	addMTLVertexFormatDesc( Char4Normalized );
	addMTLVertexFormatDesc( UChar4 );
	addMTLVertexFormatDesc( Char4 );

	addMTLVertexFormatDesc( UInt1010102Normalized );
	addMTLVertexFormatDesc( Int1010102Normalized );

	addMTLVertexFormatDesc( UShort2Normalized );
	addMTLVertexFormatDesc( Short2Normalized );
	addMTLVertexFormatDesc( UShort2 );
	addMTLVertexFormatDesc( Short2 );
	addMTLVertexFormatDesc( Half2 );

	addMTLVertexFormatDesc( UShort3Normalized );
	addMTLVertexFormatDesc( Short3Normalized );
	addMTLVertexFormatDesc( UShort3 );
	addMTLVertexFormatDesc( Short3 );
	addMTLVertexFormatDesc( Half3 );

	addMTLVertexFormatDesc( UShort4Normalized );
	addMTLVertexFormatDesc( Short4Normalized );
	addMTLVertexFormatDesc( UShort4 );
	addMTLVertexFormatDesc( Short4 );
	addMTLVertexFormatDesc( Half4 );

	addMTLVertexFormatDesc( UInt );
	addMTLVertexFormatDesc( Int );
	addMTLVertexFormatDesc( Float );

	addMTLVertexFormatDesc( UInt2 );
	addMTLVertexFormatDesc( Int2 );
	addMTLVertexFormatDesc( Float2 );

	addMTLVertexFormatDesc( UInt3 );
	addMTLVertexFormatDesc( Int3 );
	addMTLVertexFormatDesc( Float3 );

	addMTLVertexFormatDesc( UInt4 );
	addMTLVertexFormatDesc( Int4 );
	addMTLVertexFormatDesc( Float4 );

	addMTLVertexFormatDesc( UCharNormalized );
	addMTLVertexFormatDesc( CharNormalized );
	addMTLVertexFormatDesc( UChar );
	addMTLVertexFormatDesc( Char );

	addMTLVertexFormatDesc( UShortNormalized );
	addMTLVertexFormatDesc( ShortNormalized );
	addMTLVertexFormatDesc( UShort );
	addMTLVertexFormatDesc( Short );
	addMTLVertexFormatDesc( Half );

	addMTLVertexFormatDesc( UChar4Normalized_BGRA );
	
	if (gpuCaps.supportsApple5 || gpuCaps.supportsMac2) {
		addMTLVertexFormatDesc( FloatRG11B10 );
		addMTLVertexFormatDesc( FloatRGB9E5 );
	}

	_mtlVertexFormatDescriptions.shrink_to_fit();
}

// Return a reference to the format capabilities, so the caller can manipulate them.
// Check mtlPixFmt exists on platform, to avoid overwriting the MTLPixelFormatInvalid entry.
// When returning the dummy, reset it on each access because it can be written to by caller.
MVKMTLFmtCaps& MVKPixelFormats::getMTLPixelFormatCapsIf(MTLPixelFormat mtlPixFmt, bool cond) {
	static MVKMTLFmtCaps dummyFmtCaps;
	if (mtlPixFmt && cond) {
		return getMTLPixelFormatDesc(mtlPixFmt).mtlFmtCaps;
	} else {
		dummyFmtCaps = kMVKMTLFmtCapsNone;
		return dummyFmtCaps;
	}
}

#define setMTLPixFmtCapsIf(cond, mtlFmt, caps)           getMTLPixelFormatCapsIf(MTLPixelFormat ##mtlFmt, cond) = kMVKMTLFmtCaps ##caps;
#define setMTLPixFmtCapsIfGPU(gpuFam, mtlFmt, caps)      setMTLPixFmtCapsIf(gpuCaps.supports ##gpuFam, mtlFmt, caps)

#define enableMTLPixFmtCapsIf(cond, mtlFmt, caps)        mvkEnableFlags(getMTLPixelFormatCapsIf(MTLPixelFormat ##mtlFmt, cond), kMVKMTLFmtCaps ##caps);
#define enableMTLPixFmtCapsIfGPU(gpuFam, mtlFmt, caps)   enableMTLPixFmtCapsIf(gpuCaps.supports ##gpuFam, mtlFmt, caps)

#define disableMTLPixFmtCapsIf(cond, mtlFmt, caps)       mvkDisableFlags(getMTLPixelFormatCapsIf(MTLPixelFormat ##mtlFmt, cond), kMVKMTLFmtCaps ##caps);
#define disableMTLPixFmtCapsIfGPU(gpuFam, mtlFmt, caps)  disableMTLPixFmtCapsIf(gpuCaps.supports ##gpuFam, mtlFmt, caps)

// Modifies the format capability tables based on the capabilities of the specific MTLDevice
void MVKPixelFormats::modifyMTLFormatCapabilities(const MVKMTLDeviceCapabilities& gpuCaps) {

	bool noVulkanSupport =  false;		// Indicated supported in Metal but not Vulkan or SPIR-V.
	bool notMac =  gpuCaps.isAppleGPU && !gpuCaps.supportsMac1;
	bool iosOnly1 = notMac && !gpuCaps.supportsApple2;
	bool iosOnly2 = notMac && !gpuCaps.supportsApple3;
	bool iosOnly6 = notMac && !gpuCaps.supportsApple7;
	bool iosOnly8 = notMac && !gpuCaps.supportsApple9;

	setMTLPixFmtCapsIf( iosOnly2, A8Unorm, RF );
	setMTLPixFmtCapsIf( iosOnly1, R8Unorm_sRGB, RFCMRB );
	setMTLPixFmtCapsIf( iosOnly1, R8Snorm, RFWCMB );

	setMTLPixFmtCapsIf( iosOnly1, RG8Unorm_sRGB, RFCMRB );
	setMTLPixFmtCapsIf( iosOnly1, RG8Snorm, RFWCMB );

	enableMTLPixFmtCapsIfGPU( Apple6, R32Uint, Atomic );
	enableMTLPixFmtCapsIfGPU( Mac2,   R32Uint, Atomic );
	enableMTLPixFmtCapsIfGPU( Apple6, R32Sint, Atomic );
	enableMTLPixFmtCapsIfGPU( Mac2,   R32Sint, Atomic );

	setMTLPixFmtCapsIf( iosOnly8, R32Float, RWCMB );

	setMTLPixFmtCapsIf( iosOnly1, RGBA8Unorm_sRGB, RFCMRB );
	setMTLPixFmtCapsIf( iosOnly1, RGBA8Snorm, RFWCMB );
	setMTLPixFmtCapsIf( iosOnly1, BGRA8Unorm_sRGB, RFCMRB );

	setMTLPixFmtCapsIf( iosOnly2, RGB10A2Unorm, RFCMRB );
	setMTLPixFmtCapsIf( iosOnly2, RGB10A2Uint, RCM );
	setMTLPixFmtCapsIf( iosOnly2, RG11B10Float, RFCMRB );
	setMTLPixFmtCapsIf( iosOnly2, RGB9E5Float, RFCMRB );

	// Blending is actually supported for RGB9E5Float, but format channels cannot
	// be individually write-enabled during blending on macOS. Disabling blending
	// on macOS is the least-intrusive way to handle this in a Vulkan-friendly way.
	disableMTLPixFmtCapsIfGPU( Mac1, RGB9E5Float, Blend);

	// RGB9E5Float cannot be used as a render target on the simulator
	disableMTLPixFmtCapsIf( MVK_OS_SIMULATOR, RGB9E5Float, ColorAtt );

	setMTLPixFmtCapsIf( iosOnly6, RG32Uint, RWC );
	setMTLPixFmtCapsIf( iosOnly6, RG32Sint, RWC );

	// Metal supports reading both R&G into as one 64-bit atomic operation, but Vulkan and SPIR-V do not.
	// Including this here so we remember to update this if support is added to Vulkan in the future.
	bool atomic64 = noVulkanSupport && (gpuCaps.supportsApple9 || (gpuCaps.supportsApple8 && gpuCaps.supportsMac2));
	enableMTLPixFmtCapsIf( atomic64, RG32Uint, Atomic );

	setMTLPixFmtCapsIf( iosOnly8, RG32Float, RWCMB );
	setMTLPixFmtCapsIf( iosOnly6, RG32Float, RWCB );

	setMTLPixFmtCapsIf( iosOnly8, RGBA32Float, RWCM );
	setMTLPixFmtCapsIf( iosOnly6, RGBA32Float, RWC );

	bool msaa32 = gpuCaps.supports32BitMSAA;
	enableMTLPixFmtCapsIf(msaa32, R32Uint, MSAA );
	enableMTLPixFmtCapsIf(msaa32, R32Sint, MSAA );
	enableMTLPixFmtCapsIf(msaa32, R32Float, Resolve );
	enableMTLPixFmtCapsIf(msaa32, RG32Uint, MSAA );
	enableMTLPixFmtCapsIf(msaa32, RG32Sint, MSAA );
	enableMTLPixFmtCapsIf(msaa32, RG32Float, Resolve );
	enableMTLPixFmtCapsIf(msaa32, RGBA32Uint, MSAA );
	enableMTLPixFmtCapsIf(msaa32, RGBA32Sint, MSAA );
	enableMTLPixFmtCapsIf(msaa32, RGBA32Float, Resolve );

	bool floatFB = gpuCaps.supports32BitFloatFiltering;
	enableMTLPixFmtCapsIf( floatFB, R32Float, Filter );
	enableMTLPixFmtCapsIf( floatFB, RG32Float, Filter );
	enableMTLPixFmtCapsIf( floatFB, RGBA32Float, Filter );
	enableMTLPixFmtCapsIf( floatFB, RGBA32Float, Blend );	// Undocumented by confirmed through testing

	bool noHDR_ASTC = !gpuCaps.supportsApple6;
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_4x4_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_5x4_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_5x5_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_6x5_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_6x6_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_8x5_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_8x6_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_8x8_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_10x5_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_10x6_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_10x8_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_10x10_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_12x10_HDR, None );
	setMTLPixFmtCapsIf( noHDR_ASTC, ASTC_12x12_HDR, None );

	bool noBC = !gpuCaps.supportsBCTextureCompression;
	setMTLPixFmtCapsIf( noBC, BC1_RGBA, None );
	setMTLPixFmtCapsIf( noBC, BC1_RGBA_sRGB, None );
	setMTLPixFmtCapsIf( noBC, BC2_RGBA, None );
	setMTLPixFmtCapsIf( noBC, BC2_RGBA_sRGB, None );
	setMTLPixFmtCapsIf( noBC, BC3_RGBA, None );
	setMTLPixFmtCapsIf( noBC, BC3_RGBA_sRGB, None );
	setMTLPixFmtCapsIf( noBC, BC4_RUnorm, None );
	setMTLPixFmtCapsIf( noBC, BC4_RSnorm, None );
	setMTLPixFmtCapsIf( noBC, BC5_RGUnorm, None );
	setMTLPixFmtCapsIf( noBC, BC5_RGSnorm, None );
	setMTLPixFmtCapsIf( noBC, BC6H_RGBUfloat, None );
	setMTLPixFmtCapsIf( noBC, BC6H_RGBFloat, None );
	setMTLPixFmtCapsIf( noBC, BC7_RGBAUnorm, None );
	setMTLPixFmtCapsIf( noBC, BC7_RGBAUnorm_sRGB, None );

	setMTLPixFmtCapsIf( iosOnly2, BGRA10_XR, None );
	setMTLPixFmtCapsIf( iosOnly2, BGRA10_XR_sRGB, None );
	setMTLPixFmtCapsIf( iosOnly2, BGR10_XR, None );
	setMTLPixFmtCapsIf( iosOnly2, BGR10_XR_sRGB, None );

	setMTLPixFmtCapsIf( iosOnly2, Depth16Unorm, DRFM );
	setMTLPixFmtCapsIf( iosOnly2, Depth32Float, DRM );

	setMTLPixFmtCapsIf( !gpuCaps.supportsDepth24Stencil8, Depth24Unorm_Stencil8, None );
	setMTLPixFmtCapsIf( iosOnly2, Depth32Float_Stencil8, DRM );
}

// Connects Vulkan and Metal pixel formats to one-another.
void MVKPixelFormats::buildVkFormatMaps(const MVKMTLDeviceCapabilities& gpuCaps) {
	for (auto& vkDesc : _vkFormatDescriptions) {
		if (vkDesc.needsSwizzle()) {
			bool supportsNativeTextureSwizzle = ((gpuCaps.isAppleGPU || gpuCaps.supportsMac2)
												 && mvkOSVersionIsAtLeast(10.15, 13.0, 1.0));
			if (!supportsNativeTextureSwizzle && !getMVKConfig().fullImageViewSwizzle) {
				vkDesc.mtlPixelFormat = vkDesc.mtlPixelFormatSubstitute = MTLPixelFormatInvalid;
			}
		}

		// Populate the back reference from the Metal formats to the Vulkan format.
		// Validate the corresponding Metal formats for the platform, and clear them
		// if the Vulkan format if not supported.
		if (vkDesc.mtlPixelFormat) {
			auto& mtlDesc = getMTLPixelFormatDesc(vkDesc.mtlPixelFormat);
			if ( !mtlDesc.vkFormat ) { mtlDesc.vkFormat = vkDesc.vkFormat; }
			if ( !mtlDesc.isSupported() ) { vkDesc.mtlPixelFormat = MTLPixelFormatInvalid; }
		}
		if (vkDesc.mtlPixelFormatSubstitute) {
			auto& mtlDesc = getMTLPixelFormatDesc(vkDesc.mtlPixelFormatSubstitute);
			if ( !mtlDesc.isSupported() ) { vkDesc.mtlPixelFormatSubstitute = MTLPixelFormatInvalid; }
		}
		if (vkDesc.mtlVertexFormat) {
			auto& mtlDesc = getMTLVertexFormatDesc(vkDesc.mtlVertexFormat);
			if ( !mtlDesc.vkFormat ) { mtlDesc.vkFormat = vkDesc.vkFormat; }
			if ( !mtlDesc.isSupported() ) { vkDesc.mtlVertexFormat = MTLVertexFormatInvalid; }
		}
		if (vkDesc.mtlVertexFormatSubstitute) {
			auto& mtlDesc = getMTLVertexFormatDesc(vkDesc.mtlVertexFormatSubstitute);
			if ( !mtlDesc.isSupported() ) { vkDesc.mtlVertexFormatSubstitute = MTLVertexFormatInvalid; }
		}

		// Set Vulkan format properties
		setFormatProperties(vkDesc, gpuCaps);
	}
}

// Enumeration of Vulkan format features aligned to the MVKMTLFmtCaps enumeration.
typedef enum : VkFormatFeatureFlags2 {
	kMVKVkFormatFeatureFlagsTexNone     = 0,
	kMVKVkFormatFeatureFlagsTexRead     = (VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_BIT |
										   VK_FORMAT_FEATURE_2_TRANSFER_SRC_BIT |
										   VK_FORMAT_FEATURE_2_TRANSFER_DST_BIT |
										   VK_FORMAT_FEATURE_2_HOST_IMAGE_TRANSFER_BIT |
										   VK_FORMAT_FEATURE_2_BLIT_SRC_BIT),
	kMVKVkFormatFeatureFlagsTexFilter   = (VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_FILTER_LINEAR_BIT),
	kMVKVkFormatFeatureFlagsTexWrite    = (VK_FORMAT_FEATURE_2_STORAGE_IMAGE_BIT |
										   VK_FORMAT_FEATURE_2_STORAGE_READ_WITHOUT_FORMAT_BIT |
										   VK_FORMAT_FEATURE_2_STORAGE_WRITE_WITHOUT_FORMAT_BIT),
	kMVKVkFormatFeatureFlagsTexAtomic   = (VK_FORMAT_FEATURE_2_STORAGE_IMAGE_ATOMIC_BIT),
	kMVKVkFormatFeatureFlagsTexColorAtt = (VK_FORMAT_FEATURE_2_COLOR_ATTACHMENT_BIT |
										   VK_FORMAT_FEATURE_2_BLIT_DST_BIT),
	kMVKVkFormatFeatureFlagsTexDSAtt    = (VK_FORMAT_FEATURE_2_DEPTH_STENCIL_ATTACHMENT_BIT |
										   VK_FORMAT_FEATURE_2_BLIT_DST_BIT),
	kMVKVkFormatFeatureFlagsTexBlend    = (VK_FORMAT_FEATURE_2_COLOR_ATTACHMENT_BLEND_BIT),
    kMVKVkFormatFeatureFlagsTexChromaSubsampling = (VK_FORMAT_FEATURE_2_MIDPOINT_CHROMA_SAMPLES_BIT |
                                                    VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_YCBCR_CONVERSION_LINEAR_FILTER_BIT),
    kMVKVkFormatFeatureFlagsTexMultiPlanar       = (VK_FORMAT_FEATURE_2_COSITED_CHROMA_SAMPLES_BIT |
                                                    VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_YCBCR_CONVERSION_SEPARATE_RECONSTRUCTION_FILTER_BIT |
                                                    VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_BIT |
                                                    VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_YCBCR_CONVERSION_CHROMA_RECONSTRUCTION_EXPLICIT_FORCEABLE_BIT |
                                                    VK_FORMAT_FEATURE_2_DISJOINT_BIT),
	kMVKVkFormatFeatureFlagsBufRead     = (VK_FORMAT_FEATURE_2_UNIFORM_TEXEL_BUFFER_BIT),
	kMVKVkFormatFeatureFlagsBufWrite    = (VK_FORMAT_FEATURE_2_STORAGE_TEXEL_BUFFER_BIT |
                                                                                   VK_FORMAT_FEATURE_2_STORAGE_READ_WITHOUT_FORMAT_BIT |
                                                                                   VK_FORMAT_FEATURE_2_STORAGE_WRITE_WITHOUT_FORMAT_BIT),
	kMVKVkFormatFeatureFlagsBufAtomic   = (VK_FORMAT_FEATURE_2_STORAGE_TEXEL_BUFFER_ATOMIC_BIT),
	kMVKVkFormatFeatureFlagsBufVertex   = (VK_FORMAT_FEATURE_2_VERTEX_BUFFER_BIT),
} MVKVkFormatFeatureFlags;

// Sets the VkFormatProperties (optimal/linear/buffer) for the Vulkan format.
void MVKPixelFormats::setFormatProperties(MVKVkFormatDesc& vkDesc, const MVKMTLDeviceCapabilities& gpuCaps) {

#	define enableFormatFeatures(CAP, TYPE, MTL_FMT_CAPS, VK_FEATS)        \
	if (mvkAreAllFlagsEnabled(MTL_FMT_CAPS, kMVKMTLFmtCaps ##CAP)) {      \
		mvkEnableFlags(VK_FEATS, kMVKVkFormatFeatureFlags ##TYPE ##CAP);  \
	}

	VkFormatProperties3& vkProps = vkDesc.properties;
	MVKMTLFmtCaps mtlPixFmtCaps = getMTLPixelFormatDesc(vkDesc.mtlPixelFormat).mtlFmtCaps;
    vkProps.optimalTilingFeatures = kMVKVkFormatFeatureFlagsTexNone;
    vkProps.linearTilingFeatures = kMVKVkFormatFeatureFlagsTexNone;

    // Chroma subsampling and multi planar features
    uint8_t chromaSubsamplingPlaneCount = getChromaSubsamplingPlaneCount(vkDesc.vkFormat);
    uint8_t chromaSubsamplingComponentBits = getChromaSubsamplingComponentBits(vkDesc.vkFormat);
    if (chromaSubsamplingComponentBits > 0) {
        if (mtlPixFmtCaps != 0 || chromaSubsamplingPlaneCount > 1) {
            mtlPixFmtCaps = kMVKMTLFmtCapsRF;
        }
        enableFormatFeatures(ChromaSubsampling, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
    }
    if (chromaSubsamplingPlaneCount > 1) {
        enableFormatFeatures(MultiPlanar, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
    }

	// Optimal tiling features
	enableFormatFeatures(Read, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(Filter, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(Write, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(Atomic, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(ColorAtt, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(DSAtt, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);
	enableFormatFeatures(Blend, Tex, mtlPixFmtCaps, vkProps.optimalTilingFeatures);

	if (isDepthFormat(vkDesc.mtlPixelFormat) && mvkIsAnyFlagEnabled(vkProps.optimalTilingFeatures, VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_BIT)) {
		vkProps.optimalTilingFeatures |= VK_FORMAT_FEATURE_2_SAMPLED_IMAGE_DEPTH_COMPARISON_BIT;
	}

	// Vulkan forbids blits between chroma-subsampled formats.
	// If we can't write the stencil reference from the shader, we can't blit stencil.
	bool supportsStencilFeedback = gpuCaps.supportsApple5 || gpuCaps.supportsMac2;
	if (chromaSubsamplingComponentBits > 0 || (isStencilFormat(vkDesc.mtlPixelFormat) && !supportsStencilFeedback)) {
		mvkDisableFlags(vkProps.optimalTilingFeatures, (VK_FORMAT_FEATURE_2_BLIT_SRC_BIT | VK_FORMAT_FEATURE_2_BLIT_DST_BIT));
	}

	// These formats require swizzling. In order to support rendering, we'll have to swizzle
	// in the fragment shader, but that hasn't been implemented yet.
	if (vkDesc.needsSwizzle()) {
		mvkDisableFlags(vkProps.optimalTilingFeatures, (kMVKVkFormatFeatureFlagsTexColorAtt |
														kMVKVkFormatFeatureFlagsTexBlend));
	}

	// Linear tiling is not available to depth/stencil or compressed formats.
	// GBGR and BGRG formats also do not support linear tiling in Metal.
	if ( !(vkDesc.formatType == kMVKFormatDepthStencil || vkDesc.formatType == kMVKFormatCompressed ||
		   (chromaSubsamplingPlaneCount == 1 && vkDesc.blockTexelSize.width > 1)) ) {
		// Start with optimal tiling features, and modify.
		vkProps.linearTilingFeatures = vkProps.optimalTilingFeatures;

#if !MVK_APPLE_SILICON
		// On macOS IMR GPUs, linear textures cannot be used as attachments, so disable those features.
		mvkDisableFlags(vkProps.linearTilingFeatures, (kMVKVkFormatFeatureFlagsTexColorAtt |
													   kMVKVkFormatFeatureFlagsTexDSAtt |
													   kMVKVkFormatFeatureFlagsTexBlend));
#endif
	}

	// Texel buffers are not available to depth/stencil, compressed, or chroma subsampled formats.
	// Additionally, format swizzles are not applied to texel buffers yet.
	vkProps.bufferFeatures = kMVKVkFormatFeatureFlagsTexNone;
	if ( !(vkDesc.formatType == kMVKFormatDepthStencil || vkDesc.formatType == kMVKFormatCompressed ||
		   chromaSubsamplingComponentBits > 0 || vkDesc.needsSwizzle()) ) {
		enableFormatFeatures(Read, Buf, mtlPixFmtCaps, vkProps.bufferFeatures);
		enableFormatFeatures(Write, Buf, mtlPixFmtCaps, vkProps.bufferFeatures);
		enableFormatFeatures(Atomic, Buf, mtlPixFmtCaps, vkProps.bufferFeatures);
		enableFormatFeatures(Vertex, Buf, getMTLVertexFormatDesc(vkDesc.mtlVertexFormat).mtlFmtCaps, vkProps.bufferFeatures);
	}
}
