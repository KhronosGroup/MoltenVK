/*
 * mvk_datatypes.mm
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

#include "MVKEnvironment.h"
#include "mvk_datatypes.hpp"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKBaseObject.h"
#include <MoltenVKSPIRVToMSLConverter/SPIRVReflection.h>
#include <unordered_map>
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

#define MVK_MAKE_FMT_STRUCT(VK_FMT, MTL_FMT, MTL_FMT_ALT, IOS_SINCE, MACOS_SINCE, BLK_W, BLK_H, BLK_BYTE_CNT, MTL_VTX_FMT, MTL_VTX_FMT_ALT, VTX_IOS_SINCE, VTX_MACOS_SINCE, CLR_TYPE, PIXEL_FEATS, BUFFER_FEATS)  \
        { VK_FMT, MTL_FMT, MTL_FMT_ALT, IOS_SINCE, MACOS_SINCE, { BLK_W, BLK_H }, BLK_BYTE_CNT, MTL_VTX_FMT, MTL_VTX_FMT_ALT, VTX_IOS_SINCE, VTX_MACOS_SINCE, CLR_TYPE, { (PIXEL_FEATS & MVK_FMT_LINEAR_TILING_FEATS), PIXEL_FEATS, BUFFER_FEATS }, #VK_FMT, #MTL_FMT }

#pragma mark Texture formats

static const MVKOSVersion kMTLFmtNA = numeric_limits<MVKOSVersion>::max();

/** Describes the properties of each VkFormat, including the corresponding Metal pixel format. */
typedef struct {
	VkFormat vk;
	MTLPixelFormat mtl;
    MTLPixelFormat mtlSubstitute;
    MVKOSVersion sinceIOSVersion;
    MVKOSVersion sinceMacOSVersion;
    VkExtent2D blockTexelSize;
	uint32_t bytesPerBlock;
	MTLVertexFormat mtlVertexFormat;
	MTLVertexFormat mtlVertexFormatSubstitute;
	MVKOSVersion vertexSinceIOSVersion;
	MVKOSVersion vertexSinceMacOSVersion;
	MVKFormatType formatType;
	VkFormatProperties properties;
    const char* vkName;
    const char* mtlName;

    inline double bytesPerTexel() const { return (double)bytesPerBlock / (double)(blockTexelSize.width * blockTexelSize.height); };

    inline MVKOSVersion sinceOSVersion() const {
#if MVK_IOS
        return sinceIOSVersion;
#endif
#if MVK_MACOS
        return sinceMacOSVersion;
#endif
    }
    inline bool isSupported() const { return (mtl != MTLPixelFormatInvalid) && (mvkOSVersion() >= sinceOSVersion()); };
    inline bool isSupportedOrSubstitutable() const { return isSupported() || (mtlSubstitute != MTLPixelFormatInvalid); };

    inline MVKOSVersion vertexSinceOSVersion() const {
#if MVK_IOS
        return vertexSinceIOSVersion;
#endif
#if MVK_MACOS
        return vertexSinceMacOSVersion;
#endif
    }
    inline bool vertexIsSupported() const { return (mtlVertexFormat != MTLVertexFormatInvalid) && (mvkOSVersion() >= vertexSinceOSVersion()); };
    inline bool vertexIsSupportedOrSubstitutable() const { return vertexIsSupported() || (mtlVertexFormatSubstitute != MTLVertexFormatInvalid); };
} MVKFormatDesc;

/** Mapping between Vulkan and Metal pixel formats. */
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
#endif

#if MVK_IOS
#   define MTLPixelFormatDepth16Unorm           MTLPixelFormatInvalid
#   define MTLPixelFormatDepth24Unorm_Stencil8  MTLPixelFormatInvalid
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


static const MVKFormatDesc _formatDescriptions[] {
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_UNDEFINED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 0, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatNone, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R4G4_UNORM_PACK8, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 1, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R4G4B4A4_UNORM_PACK16, MTLPixelFormatABGR4Unorm, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),	// Vulkan packed is reversed
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B4G4R4A4_UNORM_PACK16, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R5G6B5_UNORM_PACK16, MTLPixelFormatB5G6R5Unorm, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),	// Vulkan packed is reversed
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B5G6R5_UNORM_PACK16, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R5G5B5A1_UNORM_PACK16, MTLPixelFormatA1BGR5Unorm, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),	// Vulkan packed is reversed
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B5G5R5A1_UNORM_PACK16, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A1R5G5B5_UNORM_PACK16, MTLPixelFormatBGR5A1Unorm, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),	// Vulkan packed is reversed

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8_UNORM, MTLPixelFormatR8Unorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 1, MTLVertexFormatUCharNormalized, MTLVertexFormatUChar2Normalized, 11.0, 10.13, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8_SNORM, MTLPixelFormatR8Snorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 1, MTLVertexFormatCharNormalized, MTLVertexFormatChar2Normalized, 11.0, 10.13, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 1, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 1, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8_UINT, MTLPixelFormatR8Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 1, MTLVertexFormatUChar, MTLVertexFormatUChar2, 11.0, 10.13, kMVKFormatColorUInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8_SINT, MTLPixelFormatR8Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 1, MTLVertexFormatChar, MTLVertexFormatChar2, 11.0, 10.13, kMVKFormatColorInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8_SRGB, MTLPixelFormatR8Unorm_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 1, 1, 1, MTLVertexFormatUCharNormalized, MTLVertexFormatUChar2Normalized, 11.0, 10.13, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8_UNORM, MTLPixelFormatRG8Unorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 2, MTLVertexFormatUChar2Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8_SNORM, MTLPixelFormatRG8Snorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 2, MTLVertexFormatChar2Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8_UINT, MTLPixelFormatRG8Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 2, MTLVertexFormatUChar2, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8_SINT, MTLPixelFormatRG8Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 2, MTLVertexFormatChar2, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8_SRGB, MTLPixelFormatRG8Unorm_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 1, 1, 2, MTLVertexFormatUChar2Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8_UNORM, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatUChar3Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8_SNORM, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatChar3Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8_UINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatUChar3, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8_SINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatChar3, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8_SRGB, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatUChar3Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8_UNORM, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8_SNORM, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8_UINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorUInt8, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8_SINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorInt8, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8_SRGB, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8A8_UNORM, MTLPixelFormatRGBA8Unorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUChar4Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8A8_SNORM, MTLPixelFormatRGBA8Snorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatChar4Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8A8_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8A8_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8A8_UINT, MTLPixelFormatRGBA8Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUChar4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8A8_SINT, MTLPixelFormatRGBA8Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatChar4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R8G8B8A8_SRGB, MTLPixelFormatRGBA8Unorm_sRGB, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUChar4Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8A8_UNORM, MTLPixelFormatBGRA8Unorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUChar4Normalized_BGRA, MTLVertexFormatInvalid, 11.0, 10.13, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8A8_SNORM, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8A8_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8A8_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8A8_UINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorUInt8, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8A8_SINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorInt8, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B8G8R8A8_SRGB, MTLPixelFormatBGRA8Unorm_sRGB, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A8B8G8R8_UNORM_PACK32, MTLPixelFormatRGBA8Unorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUChar4Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A8B8G8R8_SNORM_PACK32, MTLPixelFormatRGBA8Snorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatChar4Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A8B8G8R8_USCALED_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A8B8G8R8_SSCALED_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A8B8G8R8_UINT_PACK32, MTLPixelFormatRGBA8Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUChar4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A8B8G8R8_SINT_PACK32, MTLPixelFormatRGBA8Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatChar4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt8, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A8B8G8R8_SRGB_PACK32, MTLPixelFormatRGBA8Unorm_sRGB, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUChar4Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2R10G10B10_UNORM_PACK32, MTLPixelFormatBGR10A2Unorm, MTLPixelFormatInvalid, 11.0, 10.13, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),	// Vulkan packed is reversed
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2R10G10B10_SNORM_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2R10G10B10_USCALED_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2R10G10B10_SSCALED_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2R10G10B10_UINT_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorUInt16, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2R10G10B10_SINT_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorInt16, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
  
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2B10G10R10_UNORM_PACK32, MTLPixelFormatRGB10A2Unorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUInt1010102Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),	// Vulkan packed is reversed
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2B10G10R10_SNORM_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInt1010102Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2B10G10R10_USCALED_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2B10G10R10_SSCALED_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2B10G10R10_UINT_PACK32, MTLPixelFormatRGB10A2Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorUInt16, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_FEATS ),		// Vulkan packed is reversed
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_A2B10G10R10_SINT_PACK32, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorInt16, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16_UNORM, MTLPixelFormatR16Unorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 2, MTLVertexFormatUShortNormalized, MTLVertexFormatUShort2Normalized, 11.0, 10.13, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16_SNORM, MTLPixelFormatR16Snorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 2, MTLVertexFormatShortNormalized, MTLVertexFormatShort2Normalized, 11.0, 10.13, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16_UINT, MTLPixelFormatR16Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 2, MTLVertexFormatUShort, MTLVertexFormatUShort2, 11.0, 10.13, kMVKFormatColorUInt16, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16_SINT, MTLPixelFormatR16Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 2, MTLVertexFormatShort, MTLVertexFormatShort2, 11.0, 10.13, kMVKFormatColorInt16, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16_SFLOAT, MTLPixelFormatR16Float, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 2, MTLVertexFormatHalf, MTLVertexFormatHalf2, 11.0, 10.13, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16_UNORM, MTLPixelFormatRG16Unorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUShort2Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16_SNORM, MTLPixelFormatRG16Snorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatShort2Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16_UINT, MTLPixelFormatRG16Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUShort2, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt16, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16_SINT, MTLPixelFormatRG16Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatShort2, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt16, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16_SFLOAT, MTLPixelFormatRG16Float, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatHalf2, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16_UNORM, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 6, MTLVertexFormatUShort3Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16_SNORM, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 6, MTLVertexFormatShort3Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 6, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 6, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16_UINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 6, MTLVertexFormatUShort3, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt16, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16_SINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 6, MTLVertexFormatShort3, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt16, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16_SFLOAT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 6, MTLVertexFormatHalf3, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16A16_UNORM, MTLPixelFormatRGBA16Unorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 8, MTLVertexFormatUShort4Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16A16_SNORM, MTLPixelFormatRGBA16Snorm, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 8, MTLVertexFormatShort4Normalized, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16A16_USCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16A16_SSCALED, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16A16_UINT, MTLPixelFormatRGBA16Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 8, MTLVertexFormatUShort4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt16, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16A16_SINT, MTLPixelFormatRGBA16Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 8, MTLVertexFormatShort4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt16, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R16G16B16A16_SFLOAT, MTLPixelFormatRGBA16Float, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 8, MTLVertexFormatHalf4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32_UINT, MTLPixelFormatR32Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatUInt, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt32, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32_SINT, MTLPixelFormatR32Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatInt, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt32, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32_SFLOAT, MTLPixelFormatR32Float, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatFloat, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FLOAT32_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32G32_UINT, MTLPixelFormatRG32Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 8, MTLVertexFormatUInt2, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt32, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32G32_SINT, MTLPixelFormatRG32Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 8, MTLVertexFormatInt2, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt32, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32G32_SFLOAT, MTLPixelFormatRG32Float, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 8, MTLVertexFormatFloat2, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FLOAT32_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32G32B32_UINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 12, MTLVertexFormatUInt3, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt32, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32G32B32_SINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 12, MTLVertexFormatInt3, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt32, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32G32B32_SFLOAT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 12, MTLVertexFormatFloat3, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FLOAT32_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32G32B32A32_UINT, MTLPixelFormatRGBA32Uint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 16, MTLVertexFormatUInt4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorUInt32, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32G32B32A32_SINT, MTLPixelFormatRGBA32Sint, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 16, MTLVertexFormatInt4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorInt32, MVK_FMT_COLOR_INTEGER_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R32G32B32A32_SFLOAT, MTLPixelFormatRGBA32Float, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 16, MTLVertexFormatFloat4, MTLVertexFormatInvalid, 8.0, 10.11, kMVKFormatColorFloat, MVK_FMT_COLOR_FLOAT32_FEATS, MVK_FMT_BUFFER_VTX_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64_UINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64_SINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64_SFLOAT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64G64_UINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64G64_SINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64G64_SFLOAT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64G64B64_UINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 24, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64G64B64_SINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 24, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64G64B64_SFLOAT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 24, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64G64B64A64_UINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 32, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64G64B64A64_SINT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 32, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_R64G64B64A64_SFLOAT, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 1, 1, 32, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_B10G11R11_UFLOAT_PACK32, MTLPixelFormatRG11B10Float, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),	// Vulkan packed is reversed
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_E5B9G9R9_UFLOAT_PACK32, MTLPixelFormatRGB9E5Float, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_E5B9G9R9_FEATS, MVK_FMT_E5B9G9R9_BUFFER_FEATS ),	// Vulkan packed is reversed

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_D32_SFLOAT, MTLPixelFormatDepth32Float, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatDepthStencil, MVK_FMT_DEPTH_FEATS, MVK_FMT_NO_FEATS ),
    MVK_MAKE_FMT_STRUCT( VK_FORMAT_D32_SFLOAT_S8_UINT, MTLPixelFormatDepth32Float_Stencil8, MTLPixelFormatInvalid, 9.0, 10.11, 1, 1, 5, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatDepthStencil, MVK_FMT_DEPTH_FEATS, MVK_FMT_NO_FEATS ),

    MVK_MAKE_FMT_STRUCT( VK_FORMAT_S8_UINT, MTLPixelFormatStencil8, MTLPixelFormatInvalid, 8.0, 10.11, 1, 1, 1, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatDepthStencil, MVK_FMT_STENCIL_FEATS, MVK_FMT_NO_FEATS ),

    MVK_MAKE_FMT_STRUCT( VK_FORMAT_D16_UNORM, MTLPixelFormatDepth16Unorm, MTLPixelFormatDepth32Float, kMTLFmtNA, 10.12, 1, 1, 2, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatDepthStencil, MVK_FMT_DEPTH_FEATS, MVK_FMT_NO_FEATS ),
    MVK_MAKE_FMT_STRUCT( VK_FORMAT_D16_UNORM_S8_UINT, MTLPixelFormatInvalid, MTLPixelFormatDepth16Unorm_Stencil8, kMTLFmtNA, kMTLFmtNA, 1, 1, 3, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatDepthStencil, MVK_FMT_DEPTH_FEATS, MVK_FMT_NO_FEATS ),
    MVK_MAKE_FMT_STRUCT( VK_FORMAT_D24_UNORM_S8_UINT, MTLPixelFormatDepth24Unorm_Stencil8, MTLPixelFormatDepth32Float_Stencil8, kMTLFmtNA, 10.11, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatDepthStencil, MVK_FMT_DEPTH_FEATS, MVK_FMT_NO_FEATS ),

    MVK_MAKE_FMT_STRUCT( VK_FORMAT_X8_D24_UNORM_PACK32, MTLPixelFormatInvalid, MTLPixelFormatDepth24Unorm_Stencil8, kMTLFmtNA, kMTLFmtNA, 1, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatDepthStencil, MVK_FMT_DEPTH_FEATS, MVK_FMT_NO_FEATS ),	// Vulkan packed is reversed

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC1_RGB_UNORM_BLOCK, MTLPixelFormatBC1_RGBA, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC1_RGB_SRGB_BLOCK, MTLPixelFormatBC1_RGBA_sRGB, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC1_RGBA_UNORM_BLOCK, MTLPixelFormatBC1_RGBA, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC1_RGBA_SRGB_BLOCK, MTLPixelFormatBC1_RGBA_sRGB, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC2_UNORM_BLOCK, MTLPixelFormatBC2_RGBA, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC2_SRGB_BLOCK, MTLPixelFormatBC2_RGBA_sRGB, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC3_UNORM_BLOCK, MTLPixelFormatBC3_RGBA, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC3_SRGB_BLOCK, MTLPixelFormatBC3_RGBA_sRGB, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC4_UNORM_BLOCK, MTLPixelFormatBC4_RUnorm, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC4_SNORM_BLOCK, MTLPixelFormatBC4_RSnorm, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC5_UNORM_BLOCK, MTLPixelFormatBC5_RGUnorm, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC5_SNORM_BLOCK, MTLPixelFormatBC5_RGSnorm, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC6H_UFLOAT_BLOCK, MTLPixelFormatBC6H_RGBUfloat, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC6H_SFLOAT_BLOCK, MTLPixelFormatBC6H_RGBFloat, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC7_UNORM_BLOCK, MTLPixelFormatBC7_RGBAUnorm, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_BC7_SRGB_BLOCK, MTLPixelFormatBC7_RGBAUnorm_sRGB, MTLPixelFormatInvalid, kMTLFmtNA, 10.11, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK, MTLPixelFormatETC2_RGB8, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ETC2_R8G8B8_SRGB_BLOCK, MTLPixelFormatETC2_RGB8_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ETC2_R8G8B8A1_UNORM_BLOCK, MTLPixelFormatETC2_RGB8A1, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ETC2_R8G8B8A1_SRGB_BLOCK, MTLPixelFormatETC2_RGB8A1_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK, MTLPixelFormatEAC_RGBA8, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK, MTLPixelFormatEAC_RGBA8_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_EAC_R11_UNORM_BLOCK, MTLPixelFormatEAC_R11Unorm, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_EAC_R11_SNORM_BLOCK, MTLPixelFormatEAC_R11Snorm, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_EAC_R11G11_UNORM_BLOCK, MTLPixelFormatEAC_RG11Unorm, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_EAC_R11G11_SNORM_BLOCK, MTLPixelFormatEAC_RG11Snorm, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_4x4_UNORM_BLOCK, MTLPixelFormatASTC_4x4_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_4x4_SRGB_BLOCK, MTLPixelFormatASTC_4x4_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_5x4_UNORM_BLOCK, MTLPixelFormatASTC_5x4_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 5, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_5x4_SRGB_BLOCK, MTLPixelFormatASTC_5x4_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 5, 4, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_5x5_UNORM_BLOCK, MTLPixelFormatASTC_5x5_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 5, 5, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_5x5_SRGB_BLOCK, MTLPixelFormatASTC_5x5_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 5, 5, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_6x5_UNORM_BLOCK, MTLPixelFormatASTC_6x5_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 6, 5, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_6x5_SRGB_BLOCK, MTLPixelFormatASTC_6x5_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 6, 5, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_6x6_UNORM_BLOCK, MTLPixelFormatASTC_6x6_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 6, 6, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_6x6_SRGB_BLOCK, MTLPixelFormatASTC_6x6_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 6, 6, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_8x5_UNORM_BLOCK, MTLPixelFormatASTC_8x5_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 8, 5, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_8x5_SRGB_BLOCK, MTLPixelFormatASTC_8x5_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 8, 5, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_8x6_UNORM_BLOCK, MTLPixelFormatASTC_8x6_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 8, 6, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_8x6_SRGB_BLOCK, MTLPixelFormatASTC_8x6_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 8, 6, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_8x8_UNORM_BLOCK, MTLPixelFormatASTC_8x8_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 8, 8, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_8x8_SRGB_BLOCK, MTLPixelFormatASTC_8x8_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 8, 8, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_10x5_UNORM_BLOCK, MTLPixelFormatASTC_10x5_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 10, 5, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_10x5_SRGB_BLOCK, MTLPixelFormatASTC_10x5_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 10, 5, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_10x6_UNORM_BLOCK, MTLPixelFormatASTC_10x6_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 10, 6, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_10x6_SRGB_BLOCK, MTLPixelFormatASTC_10x6_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 10, 6, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_10x8_UNORM_BLOCK, MTLPixelFormatASTC_10x8_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 10, 8, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_10x8_SRGB_BLOCK, MTLPixelFormatASTC_10x8_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 10, 8, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_10x10_UNORM_BLOCK, MTLPixelFormatASTC_10x10_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 10, 10, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_10x10_SRGB_BLOCK, MTLPixelFormatASTC_10x10_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 10, 10, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_12x10_UNORM_BLOCK, MTLPixelFormatASTC_12x10_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 12, 10, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_12x10_SRGB_BLOCK, MTLPixelFormatASTC_12x10_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 12, 10, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_12x12_UNORM_BLOCK, MTLPixelFormatASTC_12x12_LDR, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 12, 12, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_ASTC_12x12_SRGB_BLOCK, MTLPixelFormatASTC_12x12_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 12, 12, 16, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),

	// Extension VK_IMG_format_pvrtc
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_PVRTC1_2BPP_UNORM_BLOCK_IMG, MTLPixelFormatPVRTC_RGBA_2BPP, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 8, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_PVRTC1_4BPP_UNORM_BLOCK_IMG, MTLPixelFormatPVRTC_RGBA_4BPP, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_PVRTC2_2BPP_UNORM_BLOCK_IMG, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 8, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_PVRTC2_4BPP_UNORM_BLOCK_IMG, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_PVRTC1_2BPP_SRGB_BLOCK_IMG, MTLPixelFormatPVRTC_RGBA_2BPP_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 8, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_PVRTC1_4BPP_SRGB_BLOCK_IMG, MTLPixelFormatPVRTC_RGBA_4BPP_sRGB, MTLPixelFormatInvalid, 8.0, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_COMPRESSED_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_PVRTC2_2BPP_SRGB_BLOCK_IMG, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 8, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),
	MVK_MAKE_FMT_STRUCT( VK_FORMAT_PVRTC2_4BPP_SRGB_BLOCK_IMG, MTLPixelFormatInvalid, MTLPixelFormatInvalid, kMTLFmtNA, kMTLFmtNA, 4, 4, 8, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatCompressed, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS ),

    // Future extension VK_KHX_color_conversion and Vulkan 1.1.
    MVK_MAKE_FMT_STRUCT( VK_FORMAT_UNDEFINED, MTLPixelFormatGBGR422, MTLPixelFormatInvalid, 8.0, 10.11, 2, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),
    MVK_MAKE_FMT_STRUCT( VK_FORMAT_UNDEFINED, MTLPixelFormatBGRG422, MTLPixelFormatInvalid, 8.0, 10.11, 2, 1, 4, MTLVertexFormatInvalid, MTLVertexFormatInvalid, kMTLFmtNA, kMTLFmtNA, kMVKFormatColorFloat, MVK_FMT_COLOR_FEATS, MVK_FMT_BUFFER_FEATS ),
};

static const uint32_t _vkFormatCoreCount = VK_FORMAT_ASTC_12x12_SRGB_BLOCK + 1;
static const uint32_t _mtlFormatCount = MTLPixelFormatX32_Stencil8 + 2;     // The actual last enum value is not available on iOS
static const uint32_t _mtlVertexFormatCount = MTLVertexFormatHalf + 1;

// Map for mapping large VkFormat values to an index.
typedef unordered_map<uint32_t, uint32_t> MVKFormatIndexByVkFormatMap;

// Vulkan core formats have small values and are mapped by simple lookup array.
// Vulkan extension formats have larger values and are mapped by a map.
// MVKFormatIndexByVkFormatMap held as global pointer to allow it to be populated during global init functions.
static uint16_t _fmtDescIndicesByVkFormatsCore[_vkFormatCoreCount];
static MVKFormatIndexByVkFormatMap* _pFmtDescIndicesByVkFormatsExt;

// Metal formats have small values and are mapped by simple lookup array.
static uint16_t _fmtDescIndicesByMTLPixelFormats[_mtlFormatCount];
static uint16_t _fmtDescIndicesByMTLVertexFormats[_mtlVertexFormatCount];

/**
 * Populates the lookup maps that map Vulkan and Metal pixel formats to one-another.
 *
 * Because both Metal and core Vulkan format value are enumerations that start at zero and are 
 * more or less consecutively enumerated, we can use a simple lookup array in each direction
 * to map the value in one architecture (as an array index) to the corresponding value in the
 * other architecture. Values that exist in one API but not the other are given a default value.
 *
 * Vulkan extension formats have very large values, and are tracked in a separate map.
 */
static void MVKInitFormatMaps() {

    // Set all VkFormats and MTLPixelFormats to undefined/invalid
    memset(_fmtDescIndicesByVkFormatsCore, 0, sizeof(_fmtDescIndicesByVkFormatsCore));
    memset(_fmtDescIndicesByMTLPixelFormats, 0, sizeof(_fmtDescIndicesByMTLPixelFormats));
    memset(_fmtDescIndicesByMTLVertexFormats, 0, sizeof(_fmtDescIndicesByMTLVertexFormats));

	_pFmtDescIndicesByVkFormatsExt = new MVKFormatIndexByVkFormatMap();

	// Iterate through the format descriptions and populate the lookup maps.
	uint32_t fmtCnt = sizeof(_formatDescriptions) / sizeof(MVKFormatDesc);
	for (uint32_t fmtIdx = 0; fmtIdx < fmtCnt; fmtIdx++) {

		// Access the mapping
		const MVKFormatDesc& tfm = _formatDescriptions[fmtIdx];

		// If the Vulkan format is defined, create a lookup between the Vulkan format
        // and an index to the format info. For core Vulkan formats, which are small
        // and consecutive, use a simple lookup array. For extension formats, use a map.
        if (tfm.vk != VK_FORMAT_UNDEFINED) {
            if (tfm.vk < _vkFormatCoreCount) {
                _fmtDescIndicesByVkFormatsCore[tfm.vk] = fmtIdx;
            } else {
				(*_pFmtDescIndicesByVkFormatsExt)[tfm.vk] = fmtIdx;
            }
        }

        // If the Metal format is defined, create a lookup between the Metal format and an
        // index to the format info. Metal formats are small, so use a simple lookup array.
		if (tfm.mtl != MTLPixelFormatInvalid) { _fmtDescIndicesByMTLPixelFormats[tfm.mtl] = fmtIdx; }
		if (tfm.mtlVertexFormat != MTLVertexFormatInvalid) { _fmtDescIndicesByMTLVertexFormats[tfm.mtlVertexFormat] = fmtIdx; }
	}
}

// Return a reference to the format description corresponding to the VkFormat.
inline const MVKFormatDesc& formatDescForVkFormat(VkFormat vkFormat) {
	uint16_t fmtIdx = (vkFormat < _vkFormatCoreCount) ? _fmtDescIndicesByVkFormatsCore[vkFormat] : (*_pFmtDescIndicesByVkFormatsExt)[vkFormat];
    return _formatDescriptions[fmtIdx];
}

// Return a reference to the format description corresponding to the MTLPixelFormat.
inline const MVKFormatDesc& formatDescForMTLPixelFormat(MTLPixelFormat mtlFormat) {
    uint16_t fmtIdx = (mtlFormat < _mtlFormatCount) ? _fmtDescIndicesByMTLPixelFormats[mtlFormat] : 0;
    return _formatDescriptions[fmtIdx];
}

// Return a reference to the format description corresponding to the MTLVertexFormat.
inline const MVKFormatDesc& formatDescForMTLVertexFormat(MTLVertexFormat mtlFormat) {
    uint16_t fmtIdx = (mtlFormat < _mtlVertexFormatCount) ? _fmtDescIndicesByMTLVertexFormats[mtlFormat] : 0;
    return _formatDescriptions[fmtIdx];
}

MVK_PUBLIC_SYMBOL bool mvkVkFormatIsSupported(VkFormat vkFormat) {
	return formatDescForVkFormat(vkFormat).isSupported();
}

MVK_PUBLIC_SYMBOL bool mvkMTLPixelFormatIsSupported(MTLPixelFormat mtlFormat) {
	return formatDescForMTLPixelFormat(mtlFormat).isSupported();
}

MVK_PUBLIC_SYMBOL MVKFormatType mvkFormatTypeFromVkFormat(VkFormat vkFormat) {
	return formatDescForVkFormat(vkFormat).formatType;
}

MVK_PUBLIC_SYMBOL MVKFormatType mvkFormatTypeFromMTLPixelFormat(MTLPixelFormat mtlFormat) {
	return formatDescForMTLPixelFormat(mtlFormat).formatType;
}

#undef mvkMTLPixelFormatFromVkFormat
MVK_PUBLIC_SYMBOL MTLPixelFormat mvkMTLPixelFormatFromVkFormat(VkFormat vkFormat) {
	return mvkMTLPixelFormatFromVkFormatInObj(vkFormat, nullptr);
}

MTLPixelFormat mvkMTLPixelFormatFromVkFormatInObj(VkFormat vkFormat, MVKBaseObject* mvkObj) {
    MTLPixelFormat mtlPixFmt = MTLPixelFormatInvalid;

    const MVKFormatDesc& fmtDesc = formatDescForVkFormat(vkFormat);
    if (fmtDesc.isSupported()) {
        mtlPixFmt = fmtDesc.mtl;
    } else if (vkFormat != VK_FORMAT_UNDEFINED) {
        // If the MTLPixelFormat is not supported but VkFormat is valid,
        // report an error, and possibly substitute a different MTLPixelFormat.
        string errMsg;
        errMsg += "VkFormat ";
        errMsg += (fmtDesc.vkName) ? fmtDesc.vkName : to_string(fmtDesc.vk);
        errMsg += " is not supported on this platform.";

        if (fmtDesc.isSupportedOrSubstitutable()) {
            mtlPixFmt = fmtDesc.mtlSubstitute;

            const MVKFormatDesc& fmtDescSubs = formatDescForMTLPixelFormat(mtlPixFmt);
            errMsg += " Using VkFormat ";
            errMsg += (fmtDescSubs.vkName) ? fmtDescSubs.vkName : to_string(fmtDescSubs.vk);
            errMsg += " instead.";
        }
		MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "%s", errMsg.c_str());
    }

    return mtlPixFmt;
}

MVK_PUBLIC_SYMBOL VkFormat mvkVkFormatFromMTLPixelFormat(MTLPixelFormat mtlFormat) {
    return formatDescForMTLPixelFormat(mtlFormat).vk;
}

MVK_PUBLIC_SYMBOL uint32_t mvkVkFormatBytesPerBlock(VkFormat vkFormat) {
    return formatDescForVkFormat(vkFormat).bytesPerBlock;
}

MVK_PUBLIC_SYMBOL uint32_t mvkMTLPixelFormatBytesPerBlock(MTLPixelFormat mtlFormat) {
    return formatDescForMTLPixelFormat(mtlFormat).bytesPerBlock;
}

MVK_PUBLIC_SYMBOL VkExtent2D mvkVkFormatBlockTexelSize(VkFormat vkFormat) {
    return formatDescForVkFormat(vkFormat).blockTexelSize;
}

MVK_PUBLIC_SYMBOL VkExtent2D mvkMTLPixelFormatBlockTexelSize(MTLPixelFormat mtlFormat) {
    return formatDescForMTLPixelFormat(mtlFormat).blockTexelSize;
}

MVK_PUBLIC_SYMBOL float mvkVkFormatBytesPerTexel(VkFormat vkFormat) {
    return formatDescForVkFormat(vkFormat).bytesPerTexel();
}

MVK_PUBLIC_SYMBOL float mvkMTLPixelFormatBytesPerTexel(MTLPixelFormat mtlFormat) {
    return formatDescForMTLPixelFormat(mtlFormat).bytesPerTexel();
}

MVK_PUBLIC_SYMBOL size_t mvkVkFormatBytesPerRow(VkFormat vkFormat, uint32_t texelsPerRow) {
    const MVKFormatDesc& fmtDesc = formatDescForVkFormat(vkFormat);
    return mvkCeilingDivide(texelsPerRow, fmtDesc.blockTexelSize.width) * fmtDesc.bytesPerBlock;
}

MVK_PUBLIC_SYMBOL size_t mvkMTLPixelFormatBytesPerRow(MTLPixelFormat mtlFormat, uint32_t texelsPerRow) {
    const MVKFormatDesc& fmtDesc = formatDescForMTLPixelFormat(mtlFormat);
    return mvkCeilingDivide(texelsPerRow, fmtDesc.blockTexelSize.width) * fmtDesc.bytesPerBlock;
}

MVK_PUBLIC_SYMBOL size_t mvkVkFormatBytesPerLayer(VkFormat vkFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer) {
    return mvkCeilingDivide(texelRowsPerLayer, formatDescForVkFormat(vkFormat).blockTexelSize.height) * bytesPerRow;
}

MVK_PUBLIC_SYMBOL size_t mvkMTLPixelFormatBytesPerLayer(MTLPixelFormat mtlFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer) {
    return mvkCeilingDivide(texelRowsPerLayer, formatDescForMTLPixelFormat(mtlFormat).blockTexelSize.height) * bytesPerRow;
}

MVK_PUBLIC_SYMBOL VkFormatProperties mvkVkFormatProperties(VkFormat vkFormat, bool assumeGPUSupportsDefault) {
	VkFormatProperties fmtProps = {MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS, MVK_FMT_NO_FEATS};
	const MVKFormatDesc& fmtDesc = formatDescForVkFormat(vkFormat);
	if (assumeGPUSupportsDefault && fmtDesc.isSupported()) {
		fmtProps = fmtDesc.properties;
		if (!fmtDesc.vertexIsSupportedOrSubstitutable()) {
			fmtProps.bufferFeatures &= ~VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
		}
	} else {
		// If texture format is unsupported, vertex buffer format may still be.
		fmtProps.bufferFeatures |= fmtDesc.properties.bufferFeatures & VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT;
	}
	return fmtProps;
}

MVK_PUBLIC_SYMBOL const char* mvkVkFormatName(VkFormat vkFormat) {
    return formatDescForVkFormat(vkFormat).vkName;
}

MVK_PUBLIC_SYMBOL const char* mvkMTLPixelFormatName(MTLPixelFormat mtlFormat) {
    return formatDescForMTLPixelFormat(mtlFormat).mtlName;
}

void mvkEnumerateSupportedFormats(VkFormatProperties properties, bool any, std::function<bool(VkFormat)> func) {
    static const auto areFeaturesSupported = [any](uint32_t a, uint32_t b) {
        if (b == 0) return true;
        if (any)
            return mvkIsAnyFlagEnabled(a, b);
        else
            return mvkAreAllFlagsEnabled(a, b);
    };
    for (auto& formatDesc : _formatDescriptions) {
        if (formatDesc.isSupported() &&
            areFeaturesSupported(formatDesc.properties.linearTilingFeatures, properties.linearTilingFeatures) &&
            areFeaturesSupported(formatDesc.properties.optimalTilingFeatures, properties.optimalTilingFeatures) &&
            areFeaturesSupported(formatDesc.properties.bufferFeatures, properties.bufferFeatures)) {
            if (!func(formatDesc.vk)) {
                break;
            }
        }
    }
}

#undef mvkMTLVertexFormatFromVkFormat
MVK_PUBLIC_SYMBOL MTLVertexFormat mvkMTLVertexFormatFromVkFormat(VkFormat vkFormat) {
	return mvkMTLVertexFormatFromVkFormatInObj(vkFormat, nullptr);
}

MTLVertexFormat mvkMTLVertexFormatFromVkFormatInObj(VkFormat vkFormat, MVKBaseObject* mvkObj) {
    MTLVertexFormat mtlVtxFmt = MTLVertexFormatInvalid;

    const MVKFormatDesc& fmtDesc = formatDescForVkFormat(vkFormat);
    if (fmtDesc.vertexIsSupported()) {
        mtlVtxFmt = fmtDesc.mtlVertexFormat;
    } else if (vkFormat != VK_FORMAT_UNDEFINED) {
        // If the MTLVertexFormat is not supported but VkFormat is valid,
        // report an error, and possibly substitute a different MTLVertexFormat.
        string errMsg;
        errMsg += "VkFormat ";
        errMsg += (fmtDesc.vkName) ? fmtDesc.vkName : to_string(fmtDesc.vk);
        errMsg += " is not supported for vertex buffers on this platform.";

        if (fmtDesc.vertexIsSupportedOrSubstitutable()) {
            mtlVtxFmt = fmtDesc.mtlVertexFormatSubstitute;

            const MVKFormatDesc& fmtDescSubs = formatDescForMTLVertexFormat(mtlVtxFmt);
            errMsg += " Using VkFormat ";
            errMsg += (fmtDescSubs.vkName) ? fmtDescSubs.vkName : to_string(fmtDescSubs.vk);
            errMsg += " instead.";
        }
		MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "%s", errMsg.c_str());
    }

    return mtlVtxFmt;
}

MVK_PUBLIC_SYMBOL MTLClearColor mvkMTLClearColorFromVkClearValue(VkClearValue vkClearValue,
																 VkFormat vkFormat) {
	MTLClearColor mtlClr;
	switch (mvkFormatTypeFromVkFormat(vkFormat)) {
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

MVK_PUBLIC_SYMBOL double mvkMTLClearDepthFromVkClearValue(VkClearValue vkClearValue) {
	return vkClearValue.depthStencil.depth;
}

MVK_PUBLIC_SYMBOL uint32_t mvkMTLClearStencilFromVkClearValue(VkClearValue vkClearValue) {
	return vkClearValue.depthStencil.stencil;
}

MVK_PUBLIC_SYMBOL bool mvkMTLPixelFormatIsDepthFormat(MTLPixelFormat mtlFormat) {
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

MVK_PUBLIC_SYMBOL bool mvkMTLPixelFormatIsStencilFormat(MTLPixelFormat mtlFormat) {
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

MVK_PUBLIC_SYMBOL bool mvkMTLPixelFormatIsPVRTCFormat(MTLPixelFormat mtlFormat) {
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

MVK_PUBLIC_SYMBOL MTLTextureType mvkMTLTextureTypeFromVkImageType(VkImageType vkImageType,
																  uint32_t arraySize,
																  bool isMultisample) {
	switch (vkImageType) {
		case VK_IMAGE_TYPE_1D: return (arraySize > 1 ? MTLTextureType1DArray : MTLTextureType1D);
		case VK_IMAGE_TYPE_3D: return MTLTextureType3D;
		case VK_IMAGE_TYPE_2D:
		default: {
#if MVK_MACOS
			if (arraySize > 1 && isMultisample) { return MTLTextureType2DMultisampleArray; }
#endif
			if (arraySize > 1) { return MTLTextureType2DArray; }
			if (isMultisample) { return MTLTextureType2DMultisample; }
			return MTLTextureType2D;
		}
	}
}

MVK_PUBLIC_SYMBOL VkImageType mvkVkImageTypeFromMTLTextureType(MTLTextureType mtlTextureType) {
	switch (mtlTextureType) {
		case MTLTextureType1D:
		case MTLTextureType1DArray:
			return VK_IMAGE_TYPE_1D;
		case MTLTextureType3D:
			return VK_IMAGE_TYPE_3D;
		default:
			return VK_IMAGE_TYPE_2D;
	}
}

MVK_PUBLIC_SYMBOL MTLTextureType mvkMTLTextureTypeFromVkImageViewType(VkImageViewType vkImageViewType,
																	  bool isMultisample) {
	switch (vkImageViewType) {
		case VK_IMAGE_VIEW_TYPE_1D:				return MTLTextureType1D;
		case VK_IMAGE_VIEW_TYPE_1D_ARRAY:		return MTLTextureType1DArray;
		case VK_IMAGE_VIEW_TYPE_2D:				return (isMultisample ? MTLTextureType2DMultisample : MTLTextureType2D);
		case VK_IMAGE_VIEW_TYPE_2D_ARRAY:
#if MVK_MACOS
			if (isMultisample) { return MTLTextureType2DMultisampleArray; }
#endif
			return MTLTextureType2DArray;
		case VK_IMAGE_VIEW_TYPE_3D:				return MTLTextureType3D;
		case VK_IMAGE_VIEW_TYPE_CUBE:			return MTLTextureTypeCube;
		case VK_IMAGE_VIEW_TYPE_CUBE_ARRAY:		return MTLTextureTypeCubeArray;
		default:                            	return MTLTextureType2D;
	}
}

MVK_PUBLIC_SYMBOL MTLTextureUsage mvkMTLTextureUsageFromVkImageUsageFlags(VkImageUsageFlags vkImageUsageFlags) {
    MTLTextureUsage mtlUsage = MTLTextureUsageUnknown;

	// Read from...
	if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
												VK_IMAGE_USAGE_SAMPLED_BIT |
												VK_IMAGE_USAGE_STORAGE_BIT |
												VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT))) {
		mvkEnableFlag(mtlUsage, MTLTextureUsageShaderRead);
	}

	// Write to...
	if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_STORAGE_BIT))) {
		mvkEnableFlag(mtlUsage, MTLTextureUsageShaderWrite);
	}

	// Render to...
	if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
												VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
												VK_IMAGE_USAGE_TRANSFER_DST_BIT))) {				// Scaling a BLIT may use rendering.
		mvkEnableFlag(mtlUsage, MTLTextureUsageRenderTarget);
	}

	// Create view on...
	if (mvkIsAnyFlagEnabled(vkImageUsageFlags, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT |	 				// May use temp view if transfer involves format change
												VK_IMAGE_USAGE_SAMPLED_BIT |
												VK_IMAGE_USAGE_STORAGE_BIT |
												VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT |
												VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
												VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT))) {	// D/S may be filtered out after device check
		mvkEnableFlag(mtlUsage, MTLTextureUsagePixelFormatView);
	}

    return mtlUsage;
}

MVK_PUBLIC_SYMBOL VkImageUsageFlags mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsage mtlUsage, MTLPixelFormat mtlFormat) {
    VkImageUsageFlags vkImageUsageFlags = 0;

    if ( mvkAreAllFlagsEnabled(mtlUsage, MTLTextureUsageShaderRead) ) {
        mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_TRANSFER_SRC_BIT);
        mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_SAMPLED_BIT);
        mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT);
    }
    if ( mvkAreAllFlagsEnabled(mtlUsage, MTLTextureUsageRenderTarget) ) {
        mvkEnableFlag(vkImageUsageFlags, VK_IMAGE_USAGE_TRANSFER_DST_BIT);
        if (mvkMTLPixelFormatIsDepthFormat(mtlFormat) || mvkMTLPixelFormatIsStencilFormat(mtlFormat)) {
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

MVK_PUBLIC_SYMBOL uint32_t mvkSampleCountFromVkSampleCountFlagBits(VkSampleCountFlagBits vkSampleCountFlag) {
	// The bits are already in the correct mathematical sequence (assuming only one bit is set)
	return uint32_t(vkSampleCountFlag);
}

MVK_PUBLIC_SYMBOL VkSampleCountFlagBits mvkVkSampleCountFlagBitsFromSampleCount(NSUInteger sampleCount) {
    // The bits are already in the correct mathematical sequence (assuming only POT sample counts)
    return VkSampleCountFlagBits(sampleCount);
}


#pragma mark Mipmaps

MVK_PUBLIC_SYMBOL uint32_t mvkMipmapLevels(uint32_t dim) {
	if ( !mvkIsPowerOfTwo(dim) ) { return 0; }

	uint32_t exp = 0;
	while (dim) {
		exp++;
		dim >>= 1;
	}
	return exp;
}

MVK_PUBLIC_SYMBOL uint32_t mvkMipmapLevels2D(VkExtent2D extent) {
    return mvkMipmapLevels3D(mvkVkExtent3DFromVkExtent2D(extent));
}

MVK_PUBLIC_SYMBOL uint32_t mvkMipmapLevels3D(VkExtent3D extent) {
    uint32_t maxDim = max({extent.width, extent.height, extent.depth});
    return max(mvkMipmapLevels(maxDim), 1U);
}

MVK_PUBLIC_SYMBOL VkExtent2D mvkMipmapLevelSizeFromBaseSize2D(VkExtent2D baseSize, uint32_t level) {
	return mvkVkExtent2DFromVkExtent3D(mvkMipmapLevelSizeFromBaseSize3D(mvkVkExtent3DFromVkExtent2D(baseSize), level));
}

MVK_PUBLIC_SYMBOL VkExtent3D mvkMipmapLevelSizeFromBaseSize3D(VkExtent3D baseSize, uint32_t level) {
	VkExtent3D lvlSize;
	lvlSize.width = max(baseSize.width >> level, 1U);
	lvlSize.height = max(baseSize.height >> level, 1U);
	lvlSize.depth = max(baseSize.depth >> level, 1U);
	return lvlSize;
}

MVK_PUBLIC_SYMBOL VkExtent2D mvkMipmapBaseSizeFromLevelSize2D(VkExtent2D levelSize, uint32_t level) {
	return mvkVkExtent2DFromVkExtent3D(mvkMipmapBaseSizeFromLevelSize3D(mvkVkExtent3DFromVkExtent2D(levelSize), level));
}

MVK_PUBLIC_SYMBOL VkExtent3D mvkMipmapBaseSizeFromLevelSize3D(VkExtent3D levelSize, uint32_t level) {
	VkExtent3D baseSize;
	baseSize.width = levelSize.width << level;
	baseSize.height = levelSize.height << level;
	baseSize.depth = levelSize.depth << level;
	return baseSize;
}


#pragma mark Samplers

MVK_PUBLIC_SYMBOL MTLSamplerAddressMode mvkMTLSamplerAddressModeFromVkSamplerAddressMode(VkSamplerAddressMode vkMode) {
	switch (vkMode) {
		case VK_SAMPLER_ADDRESS_MODE_REPEAT:				return MTLSamplerAddressModeRepeat;
		case VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE:			return MTLSamplerAddressModeClampToEdge;
		case VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER:		return MTLSamplerAddressModeClampToZero;
		case VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT:		return MTLSamplerAddressModeMirrorRepeat;
#if MVK_MACOS
		case VK_SAMPLER_ADDRESS_MODE_MIRROR_CLAMP_TO_EDGE:	return MTLSamplerAddressModeMirrorClampToEdge;
#endif
		default:								return MTLSamplerAddressModeClampToZero;
	}
}

#if MVK_MACOS
MVK_PUBLIC_SYMBOL MTLSamplerBorderColor mvkMTLSamplerBorderColorFromVkBorderColor(VkBorderColor vkColor) {
	switch (vkColor) {
		case VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK:	return MTLSamplerBorderColorTransparentBlack;
		case VK_BORDER_COLOR_INT_TRANSPARENT_BLACK:		return MTLSamplerBorderColorTransparentBlack;
		case VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK:		return MTLSamplerBorderColorOpaqueBlack;
		case VK_BORDER_COLOR_INT_OPAQUE_BLACK:			return MTLSamplerBorderColorOpaqueBlack;
		case VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE:		return MTLSamplerBorderColorOpaqueWhite;
		case VK_BORDER_COLOR_INT_OPAQUE_WHITE:			return MTLSamplerBorderColorOpaqueWhite;
		default:										return MTLSamplerBorderColorTransparentBlack;
	}
}
#endif

MVK_PUBLIC_SYMBOL MTLSamplerMinMagFilter mvkMTLSamplerMinMagFilterFromVkFilter(VkFilter vkFilter) {
	switch (vkFilter) {
		case VK_FILTER_NEAREST:		return MTLSamplerMinMagFilterNearest;
		case VK_FILTER_LINEAR:		return MTLSamplerMinMagFilterLinear;
		default:					return MTLSamplerMinMagFilterNearest;
	}
}

MVK_PUBLIC_SYMBOL MTLSamplerMipFilter mvkMTLSamplerMipFilterFromVkSamplerMipmapMode(VkSamplerMipmapMode vkMode) {
	switch (vkMode) {
		case VK_SAMPLER_MIPMAP_MODE_NEAREST:	return MTLSamplerMipFilterNearest;
		case VK_SAMPLER_MIPMAP_MODE_LINEAR:		return MTLSamplerMipFilterLinear;
		default:								return MTLSamplerMipFilterNotMipmapped;
	}
}


#pragma mark -
#pragma mark Render pipeline

MVK_PUBLIC_SYMBOL MTLColorWriteMask mvkMTLColorWriteMaskFromVkChannelFlags(VkColorComponentFlags vkWriteFlags) {
	MTLColorWriteMask mtlWriteMask = MTLColorWriteMaskNone;
	if (mvkAreAllFlagsEnabled(vkWriteFlags, VK_COLOR_COMPONENT_R_BIT)) { mvkEnableFlag(mtlWriteMask, MTLColorWriteMaskRed); }
	if (mvkAreAllFlagsEnabled(vkWriteFlags, VK_COLOR_COMPONENT_G_BIT)) { mvkEnableFlag(mtlWriteMask, MTLColorWriteMaskGreen); }
	if (mvkAreAllFlagsEnabled(vkWriteFlags, VK_COLOR_COMPONENT_B_BIT)) { mvkEnableFlag(mtlWriteMask, MTLColorWriteMaskBlue); }
	if (mvkAreAllFlagsEnabled(vkWriteFlags, VK_COLOR_COMPONENT_A_BIT)) { mvkEnableFlag(mtlWriteMask, MTLColorWriteMaskAlpha); }
	return mtlWriteMask;
}

MVK_PUBLIC_SYMBOL MTLBlendOperation mvkMTLBlendOperationFromVkBlendOp(VkBlendOp vkBlendOp) {
	switch (vkBlendOp) {
		case VK_BLEND_OP_ADD:				return MTLBlendOperationAdd;
		case VK_BLEND_OP_SUBTRACT:			return MTLBlendOperationSubtract;
		case VK_BLEND_OP_REVERSE_SUBTRACT:	return MTLBlendOperationReverseSubtract;
		case VK_BLEND_OP_MIN:				return MTLBlendOperationMin;
		case VK_BLEND_OP_MAX:				return MTLBlendOperationMax;
		default:							return MTLBlendOperationAdd;
	}
}

MVK_PUBLIC_SYMBOL MTLBlendFactor mvkMTLBlendFactorFromVkBlendFactor(VkBlendFactor vkBlendFactor) {
	switch (vkBlendFactor) {
		case VK_BLEND_FACTOR_ZERO:						return MTLBlendFactorZero;
		case VK_BLEND_FACTOR_ONE:						return MTLBlendFactorOne;
		case VK_BLEND_FACTOR_SRC_COLOR:					return MTLBlendFactorSourceColor;
		case VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR:		return MTLBlendFactorOneMinusSourceColor;
		case VK_BLEND_FACTOR_DST_COLOR:					return MTLBlendFactorDestinationColor;
		case VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR:		return MTLBlendFactorOneMinusDestinationColor;
		case VK_BLEND_FACTOR_SRC_ALPHA:					return MTLBlendFactorSourceAlpha;
		case VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA:		return MTLBlendFactorOneMinusSourceAlpha;
		case VK_BLEND_FACTOR_DST_ALPHA:					return MTLBlendFactorDestinationAlpha;
		case VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA:		return MTLBlendFactorOneMinusDestinationAlpha;
		case VK_BLEND_FACTOR_CONSTANT_COLOR:			return MTLBlendFactorBlendColor;
		case VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR:	return MTLBlendFactorOneMinusBlendColor;
		case VK_BLEND_FACTOR_CONSTANT_ALPHA:			return MTLBlendFactorBlendAlpha;
		case VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA:	return MTLBlendFactorOneMinusBlendAlpha;
		case VK_BLEND_FACTOR_SRC_ALPHA_SATURATE:		return MTLBlendFactorSourceAlphaSaturated;

        case VK_BLEND_FACTOR_SRC1_COLOR:				return MTLBlendFactorSource1Color;
		case VK_BLEND_FACTOR_ONE_MINUS_SRC1_COLOR:		return MTLBlendFactorOneMinusSource1Color;
		case VK_BLEND_FACTOR_SRC1_ALPHA:				return MTLBlendFactorSource1Alpha;
		case VK_BLEND_FACTOR_ONE_MINUS_SRC1_ALPHA:		return MTLBlendFactorOneMinusSource1Alpha;

        default:										return MTLBlendFactorZero;
	}
}

MVK_PUBLIC_SYMBOL MTLVertexStepFunction mvkMTLVertexStepFunctionFromVkVertexInputRate(VkVertexInputRate vkVtxStep) {
	switch (vkVtxStep) {
		case VK_VERTEX_INPUT_RATE_VERTEX:		return MTLVertexStepFunctionPerVertex;
		case VK_VERTEX_INPUT_RATE_INSTANCE:		return MTLVertexStepFunctionPerInstance;
		default:								return MTLVertexStepFunctionPerVertex;
	}
}

#undef mvkMTLPrimitiveTypeFromVkPrimitiveTopology
MVK_PUBLIC_SYMBOL MTLPrimitiveType mvkMTLPrimitiveTypeFromVkPrimitiveTopology(VkPrimitiveTopology vkTopology) {
	return mvkMTLPrimitiveTypeFromVkPrimitiveTopologyInObj(vkTopology, nullptr);
}

MTLPrimitiveType mvkMTLPrimitiveTypeFromVkPrimitiveTopologyInObj(VkPrimitiveTopology vkTopology, MVKBaseObject* mvkObj) {
	switch (vkTopology) {
		case VK_PRIMITIVE_TOPOLOGY_POINT_LIST:
			return MTLPrimitiveTypePoint;

		case VK_PRIMITIVE_TOPOLOGY_LINE_LIST:
		case VK_PRIMITIVE_TOPOLOGY_LINE_LIST_WITH_ADJACENCY:
			return MTLPrimitiveTypeLine;

		case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP:
		case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP_WITH_ADJACENCY:
			return MTLPrimitiveTypeLineStrip;

		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST_WITH_ADJACENCY:
		case VK_PRIMITIVE_TOPOLOGY_PATCH_LIST:
			return MTLPrimitiveTypeTriangle;

		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP_WITH_ADJACENCY:
			return MTLPrimitiveTypeTriangleStrip;

		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN:
		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkPrimitiveTopology value %d is not supported for rendering.", vkTopology);
			return MTLPrimitiveTypePoint;
	}
}

#undef mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology
MVK_PUBLIC_SYMBOL MTLPrimitiveTopologyClass mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology(VkPrimitiveTopology vkTopology) {
	return mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopologyInObj(vkTopology, nullptr);
}

MTLPrimitiveTopologyClass mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopologyInObj(VkPrimitiveTopology vkTopology, MVKBaseObject* mvkObj) {
	switch (vkTopology) {
		case VK_PRIMITIVE_TOPOLOGY_POINT_LIST:
			return MTLPrimitiveTopologyClassPoint;

		case VK_PRIMITIVE_TOPOLOGY_LINE_LIST:
		case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP:
		case VK_PRIMITIVE_TOPOLOGY_LINE_LIST_WITH_ADJACENCY:
		case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP_WITH_ADJACENCY:
			return MTLPrimitiveTopologyClassLine;

		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST_WITH_ADJACENCY:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP_WITH_ADJACENCY:
		case VK_PRIMITIVE_TOPOLOGY_PATCH_LIST:
			return MTLPrimitiveTopologyClassTriangle;

		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkPrimitiveTopology value %d is not supported for render pipelines.", vkTopology);
			return MTLPrimitiveTopologyClassUnspecified;
	}
}

#undef mvkMTLTriangleFillModeFromVkPolygonMode
MVK_PUBLIC_SYMBOL MTLTriangleFillMode mvkMTLTriangleFillModeFromVkPolygonMode(VkPolygonMode vkFillMode) {
	return mvkMTLTriangleFillModeFromVkPolygonModeInObj(vkFillMode, nullptr);
}

MTLTriangleFillMode mvkMTLTriangleFillModeFromVkPolygonModeInObj(VkPolygonMode vkFillMode, MVKBaseObject* mvkObj) {
	switch (vkFillMode) {
		case VK_POLYGON_MODE_FILL:
		case VK_POLYGON_MODE_POINT:
			return MTLTriangleFillModeFill;

		case VK_POLYGON_MODE_LINE:
			return MTLTriangleFillModeLines;

		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkPolygonMode value %d is not supported for render pipelines.", vkFillMode);
			return MTLTriangleFillModeFill;
	}
}

#undef mvkMTLLoadActionFromVkAttachmentLoadOp
MVK_PUBLIC_SYMBOL MTLLoadAction mvkMTLLoadActionFromVkAttachmentLoadOp(VkAttachmentLoadOp vkLoadOp) {
	return mvkMTLLoadActionFromVkAttachmentLoadOpInObj(vkLoadOp, nullptr);
}

MTLLoadAction mvkMTLLoadActionFromVkAttachmentLoadOpInObj(VkAttachmentLoadOp vkLoadOp, MVKBaseObject* mvkObj) {
	switch (vkLoadOp) {
		case VK_ATTACHMENT_LOAD_OP_LOAD:		return MTLLoadActionLoad;
		case VK_ATTACHMENT_LOAD_OP_CLEAR:		return MTLLoadActionClear;
		case VK_ATTACHMENT_LOAD_OP_DONT_CARE:	return MTLLoadActionDontCare;

		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkAttachmentLoadOp value %d is not supported.", vkLoadOp);
			return MTLLoadActionLoad;
	}
}

#undef mvkMTLStoreActionFromVkAttachmentStoreOp
MVK_PUBLIC_SYMBOL MTLStoreAction mvkMTLStoreActionFromVkAttachmentStoreOp(VkAttachmentStoreOp vkStoreOp, bool hasResolveAttachment) {
	return mvkMTLStoreActionFromVkAttachmentStoreOpInObj(vkStoreOp, hasResolveAttachment, nullptr);
}

MTLStoreAction mvkMTLStoreActionFromVkAttachmentStoreOpInObj(VkAttachmentStoreOp vkStoreOp, bool hasResolveAttachment, MVKBaseObject* mvkObj) {
	switch (vkStoreOp) {
		case VK_ATTACHMENT_STORE_OP_STORE:		return hasResolveAttachment ? MTLStoreActionStoreAndMultisampleResolve : MTLStoreActionStore;
		case VK_ATTACHMENT_STORE_OP_DONT_CARE:	return hasResolveAttachment ? MTLStoreActionMultisampleResolve : MTLStoreActionDontCare;

		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkAttachmentStoreOp value %d is not supported.", vkStoreOp);
			return MTLStoreActionStore;
	}
}

MVK_PUBLIC_SYMBOL MTLViewport mvkMTLViewportFromVkViewport(VkViewport vkViewport) {
	MTLViewport mtlViewport;
	mtlViewport.originX	= vkViewport.x;
	mtlViewport.originY	= vkViewport.y;
	mtlViewport.width	= vkViewport.width;
	mtlViewport.height	= vkViewport.height;
	mtlViewport.znear	= vkViewport.minDepth;
	mtlViewport.zfar	= vkViewport.maxDepth;
	return mtlViewport;
}

MVK_PUBLIC_SYMBOL MTLScissorRect mvkMTLScissorRectFromVkRect2D(VkRect2D vkRect) {
	MTLScissorRect mtlScissor;
	mtlScissor.x		= vkRect.offset.x;
	mtlScissor.y		= vkRect.offset.y;
	mtlScissor.width	= vkRect.extent.width;
	mtlScissor.height	= vkRect.extent.height;
	return mtlScissor;
}

MVK_PUBLIC_SYMBOL MTLCompareFunction mvkMTLCompareFunctionFromVkCompareOp(VkCompareOp vkOp) {
	switch (vkOp) {
		case VK_COMPARE_OP_NEVER:				return MTLCompareFunctionNever;
		case VK_COMPARE_OP_LESS:				return MTLCompareFunctionLess;
		case VK_COMPARE_OP_EQUAL:				return MTLCompareFunctionEqual;
		case VK_COMPARE_OP_LESS_OR_EQUAL:		return MTLCompareFunctionLessEqual;
		case VK_COMPARE_OP_GREATER:				return MTLCompareFunctionGreater;
		case VK_COMPARE_OP_NOT_EQUAL:			return MTLCompareFunctionNotEqual;
		case VK_COMPARE_OP_GREATER_OR_EQUAL:	return MTLCompareFunctionGreaterEqual;
		case VK_COMPARE_OP_ALWAYS:				return MTLCompareFunctionAlways;
		default:								return MTLCompareFunctionNever;
	}
}

MVK_PUBLIC_SYMBOL MTLStencilOperation mvkMTLStencilOperationFromVkStencilOp(VkStencilOp vkOp) {
	switch (vkOp) {
		case VK_STENCIL_OP_KEEP:					return MTLStencilOperationKeep;
		case VK_STENCIL_OP_ZERO:					return MTLStencilOperationZero;
		case VK_STENCIL_OP_REPLACE:					return MTLStencilOperationReplace;
		case VK_STENCIL_OP_INCREMENT_AND_CLAMP:		return MTLStencilOperationIncrementClamp;
		case VK_STENCIL_OP_DECREMENT_AND_CLAMP:		return MTLStencilOperationDecrementClamp;
		case VK_STENCIL_OP_INVERT:					return MTLStencilOperationInvert;
		case VK_STENCIL_OP_INCREMENT_AND_WRAP:		return MTLStencilOperationIncrementWrap;
		case VK_STENCIL_OP_DECREMENT_AND_WRAP:		return MTLStencilOperationDecrementWrap;
		default:									return MTLStencilOperationKeep;
	}
}

MVK_PUBLIC_SYMBOL MTLCullMode mvkMTLCullModeFromVkCullModeFlags(VkCullModeFlags vkCull) {
	switch (vkCull) {
		case VK_CULL_MODE_NONE:			return MTLCullModeNone;
		case VK_CULL_MODE_FRONT_BIT:	return MTLCullModeFront;
		case VK_CULL_MODE_BACK_BIT:		return MTLCullModeBack;
		default:						return MTLCullModeNone;
	}
}

MVK_PUBLIC_SYMBOL MTLWinding mvkMTLWindingFromVkFrontFace(VkFrontFace vkWinding) {
	switch (vkWinding) {
		case VK_FRONT_FACE_COUNTER_CLOCKWISE:	return MTLWindingCounterClockwise;
		case VK_FRONT_FACE_CLOCKWISE:			return MTLWindingClockwise;
		default:								return MTLWindingCounterClockwise;
	}
}

MVK_PUBLIC_SYMBOL MTLIndexType mvkMTLIndexTypeFromVkIndexType(VkIndexType vkIdxType) {
	switch (vkIdxType) {
		case VK_INDEX_TYPE_UINT32:	return MTLIndexTypeUInt32;
		case VK_INDEX_TYPE_UINT16:	return MTLIndexTypeUInt16;
		default:					return MTLIndexTypeUInt16;
	}
}

MVK_PUBLIC_SYMBOL size_t mvkMTLIndexTypeSizeInBytes(MTLIndexType mtlIdxType) {
	switch (mtlIdxType) {
		case MTLIndexTypeUInt16:	return 2;
		case MTLIndexTypeUInt32:	return 4;
	}
}

#undef mvkShaderStageFromVkShaderStageFlagBits
MVK_PUBLIC_SYMBOL MVKShaderStage mvkShaderStageFromVkShaderStageFlagBits(VkShaderStageFlagBits vkStage) {
	return mvkShaderStageFromVkShaderStageFlagBitsInObj(vkStage, nullptr);
}

MVKShaderStage mvkShaderStageFromVkShaderStageFlagBitsInObj(VkShaderStageFlagBits vkStage, MVKBaseObject* mvkObj) {
	switch (vkStage) {
		case VK_SHADER_STAGE_VERTEX_BIT:					return kMVKShaderStageVertex;
		case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:		return kMVKShaderStageTessCtl;
		case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:	return kMVKShaderStageTessEval;
		/* FIXME: VK_SHADER_STAGE_GEOMETRY_BIT */
		case VK_SHADER_STAGE_FRAGMENT_BIT:					return kMVKShaderStageFragment;
		case VK_SHADER_STAGE_COMPUTE_BIT:					return kMVKShaderStageCompute;
		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkShaderStage %x is not supported.", vkStage);
			return kMVKShaderStageMax;
	}
}

MVK_PUBLIC_SYMBOL VkShaderStageFlagBits mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage mvkStage) {
	switch (mvkStage) {
		case kMVKShaderStageVertex:		return VK_SHADER_STAGE_VERTEX_BIT;
		case kMVKShaderStageTessCtl:	return VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT;
		case kMVKShaderStageTessEval:	return VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
		/* FIXME: kMVKShaderStageGeometry */
		case kMVKShaderStageFragment:	return VK_SHADER_STAGE_FRAGMENT_BIT;
		case kMVKShaderStageCompute:	return VK_SHADER_STAGE_COMPUTE_BIT;
		case kMVKShaderStageMax:
			assert(!"This function should never be called with kMVKShaderStageMax!");
			return VK_SHADER_STAGE_ALL;
	}
}

#undef mvkMTLWindingFromSpvExecutionMode
MVK_PUBLIC_SYMBOL MTLWinding mvkMTLWindingFromSpvExecutionMode(uint32_t spvMode) {
	return mvkMTLWindingFromSpvExecutionModeInObj(spvMode, nullptr);
}

MTLWinding mvkMTLWindingFromSpvExecutionModeInObj(uint32_t spvMode, MVKBaseObject* mvkObj) {
	switch (spvMode) {
		// These are reversed due to the vertex flip.
		case spv::ExecutionModeVertexOrderCw:	return MTLWindingCounterClockwise;
		case spv::ExecutionModeVertexOrderCcw:	return MTLWindingClockwise;
		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "spv::ExecutionMode %u is not a winding order mode.\n", spvMode);
			return MTLWindingCounterClockwise;
	}
}

#undef mvkMTLTessellationPartitionModeFromSpvExecutionMode
MVK_PUBLIC_SYMBOL MTLTessellationPartitionMode mvkMTLTessellationPartitionModeFromSpvExecutionMode(uint32_t spvMode) {
	return mvkMTLTessellationPartitionModeFromSpvExecutionModeInObj(spvMode, nullptr);
}

MTLTessellationPartitionMode mvkMTLTessellationPartitionModeFromSpvExecutionModeInObj(uint32_t spvMode, MVKBaseObject* mvkObj) {
	switch (spvMode) {
		case spv::ExecutionModeSpacingEqual:			return MTLTessellationPartitionModeInteger;
		case spv::ExecutionModeSpacingFractionalEven:	return MTLTessellationPartitionModeFractionalEven;
		case spv::ExecutionModeSpacingFractionalOdd:	return MTLTessellationPartitionModeFractionalOdd;
		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "spv::ExecutionMode %u is not a tessellation partition mode.\n", spvMode);
			return MTLTessellationPartitionModePow2;
	}
}

MVK_PUBLIC_SYMBOL MTLRenderStages mvkMTLRenderStagesFromVkPipelineStageFlags(VkPipelineStageFlags vkStages,
																			 bool placeBarrierBefore) {
	// Although there are many combined render/compute/host stages in Vulkan, there are only two render
	// stages in Metal. If the Vulkan stage did not map ONLY to a specific Metal render stage, then if the
	// barrier is to be placed before the render stages, it should come before the vertex stage, otherwise
	// if the barrier is to be placed after the render stages, it should come after the fragment stage.
	if (placeBarrierBefore) {
		bool placeBeforeFragment = mvkIsOnlyAnyFlagEnabled(vkStages, (VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT |
																		VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT |
																		VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT |
																		VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
																		VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT));
		return placeBeforeFragment ? MTLRenderStageFragment : MTLRenderStageVertex;
	} else {
		bool placeAfterVertex = mvkIsOnlyAnyFlagEnabled(vkStages, (VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT |
																	 VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT |
																	 VK_PIPELINE_STAGE_VERTEX_INPUT_BIT |
																	 VK_PIPELINE_STAGE_VERTEX_SHADER_BIT |
																	 VK_PIPELINE_STAGE_TESSELLATION_CONTROL_SHADER_BIT |
																	 VK_PIPELINE_STAGE_TESSELLATION_EVALUATION_SHADER_BIT));
		return placeAfterVertex ? MTLRenderStageVertex : MTLRenderStageFragment;
	}
}

MVK_PUBLIC_SYMBOL MTLBarrierScope mvkMTLBarrierScopeFromVkAccessFlags(VkAccessFlags vkAccess) {
	MTLBarrierScope mtlScope = MTLBarrierScope(0);
	if ( mvkIsAnyFlagEnabled(vkAccess, VK_ACCESS_INDIRECT_COMMAND_READ_BIT | VK_ACCESS_INDEX_READ_BIT | VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT | VK_ACCESS_UNIFORM_READ_BIT) ) {
		mtlScope |= MTLBarrierScopeBuffers;
	}
	if ( mvkIsAnyFlagEnabled(vkAccess, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT) ) {
		mtlScope |= MTLBarrierScopeBuffers | MTLBarrierScopeTextures;
	}
#if MVK_MACOS
	if ( mvkIsAnyFlagEnabled(vkAccess, VK_ACCESS_INPUT_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT | VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT) ) {
		mtlScope |= MTLBarrierScopeRenderTargets;
	}
#endif
	return mtlScope;
}


#pragma mark -
#pragma mark Memory options

MVK_PUBLIC_SYMBOL MTLStorageMode mvkMTLStorageModeFromVkMemoryPropertyFlags(VkMemoryPropertyFlags vkFlags) {

	// If not visible to the host: Private
	if ( !mvkAreAllFlagsEnabled(vkFlags, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) ) {
#if MVK_IOS
		// iOS: If lazily allocated, Memoryless
		if (mvkAreAllFlagsEnabled(vkFlags, VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT)) {
			return MTLStorageModeMemoryless;
		}
#endif
		return MTLStorageModePrivate;
	}

	// If visible to the host and coherent: Shared
	if (mvkAreAllFlagsEnabled(vkFlags, VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
		return MTLStorageModeShared;
	}

	// If visible to the host, and not coherent: Managed on macOS, Shared on iOS
#if MVK_MACOS
	return MTLStorageModeManaged;
#else
	return MTLStorageModeShared;
#endif
}

MVK_PUBLIC_SYMBOL MTLCPUCacheMode mvkMTLCPUCacheModeFromVkMemoryPropertyFlags(VkMemoryPropertyFlags vkFlags) {
	return MTLCPUCacheModeDefaultCache;
}

MVK_PUBLIC_SYMBOL MTLResourceOptions mvkMTLResourceOptions(MTLStorageMode mtlStorageMode,
														   MTLCPUCacheMode mtlCPUCacheMode) {
	return (mtlStorageMode << MTLResourceStorageModeShift) | (mtlCPUCacheMode << MTLResourceCPUCacheModeShift);
}


#pragma mark -
#pragma mark Library initialization

/**
 * Called automatically when the framework is loaded and initialized.
 *
 * Initialize various data type lookups.
 */
static bool _mvkDataTypesInitialized = false;
__attribute__((constructor)) static void MVKInitDataTypes() {
	if (_mvkDataTypesInitialized ) { return; }

	MVKInitFormatMaps();

	_mvkDataTypesInitialized = true;
}

	

