/*
 * mvk_datatypes.mm
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

#include "MVKEnvironment.h"
#include "mvk_datatypes.hpp"
#include "MVKPixelFormats.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKBaseObject.h"
#include <MoltenVKShaderConverter/SPIRVReflection.h>
#include <unordered_map>
#include <string>
#include <limits>

using namespace std;


#pragma mark Pixel formats

static std::unique_ptr<MVKPixelFormats> _platformPixelFormats;

static MVKPixelFormats* getPlatformPixelFormats() {
	if ( !_platformPixelFormats ) { _platformPixelFormats.reset(new MVKPixelFormats()); }
	return _platformPixelFormats.get();
}

MVK_PUBLIC_SYMBOL bool mvkVkFormatIsSupported(VkFormat vkFormat) {
	return getPlatformPixelFormats()->isSupported(vkFormat);
}

MVK_PUBLIC_SYMBOL bool mvkMTLPixelFormatIsSupported(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->isSupported(mtlFormat);
}

MVK_PUBLIC_SYMBOL MVKFormatType mvkFormatTypeFromVkFormat(VkFormat vkFormat) {
	return getPlatformPixelFormats()->getFormatType(vkFormat);
}

MVK_PUBLIC_SYMBOL MVKFormatType mvkFormatTypeFromMTLPixelFormat(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->getFormatType(mtlFormat);
}

MVK_PUBLIC_SYMBOL MTLPixelFormat mvkMTLPixelFormatFromVkFormat(VkFormat vkFormat) {
	return getPlatformPixelFormats()->getMTLPixelFormat(vkFormat);
}

MVK_PUBLIC_SYMBOL VkFormat mvkVkFormatFromMTLPixelFormat(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->getVkFormat(mtlFormat);
}

MVK_PUBLIC_SYMBOL uint32_t mvkVkFormatBytesPerBlock(VkFormat vkFormat) {
	return getPlatformPixelFormats()->getBytesPerBlock(vkFormat);
}

MVK_PUBLIC_SYMBOL uint32_t mvkMTLPixelFormatBytesPerBlock(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->getBytesPerBlock(mtlFormat);
}

MVK_PUBLIC_SYMBOL VkExtent2D mvkVkFormatBlockTexelSize(VkFormat vkFormat) {
	return getPlatformPixelFormats()->getBlockTexelSize(vkFormat);
}

MVK_PUBLIC_SYMBOL VkExtent2D mvkMTLPixelFormatBlockTexelSize(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->getBlockTexelSize(mtlFormat);
}

MVK_PUBLIC_SYMBOL float mvkVkFormatBytesPerTexel(VkFormat vkFormat) {
	return getPlatformPixelFormats()->getBytesPerTexel(vkFormat);
}

MVK_PUBLIC_SYMBOL float mvkMTLPixelFormatBytesPerTexel(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->getBytesPerTexel(mtlFormat);
}

MVK_PUBLIC_SYMBOL size_t mvkVkFormatBytesPerRow(VkFormat vkFormat, uint32_t texelsPerRow) {
	return getPlatformPixelFormats()->getBytesPerRow(vkFormat, texelsPerRow);
}

MVK_PUBLIC_SYMBOL size_t mvkMTLPixelFormatBytesPerRow(MTLPixelFormat mtlFormat, uint32_t texelsPerRow) {
	return getPlatformPixelFormats()->getBytesPerRow(mtlFormat, texelsPerRow);
}

MVK_PUBLIC_SYMBOL size_t mvkVkFormatBytesPerLayer(VkFormat vkFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer) {
	return getPlatformPixelFormats()->getBytesPerLayer(vkFormat, bytesPerRow, texelRowsPerLayer);
}

MVK_PUBLIC_SYMBOL size_t mvkMTLPixelFormatBytesPerLayer(MTLPixelFormat mtlFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer) {
	return getPlatformPixelFormats()->getBytesPerLayer(mtlFormat, bytesPerRow, texelRowsPerLayer);
}

MVK_PUBLIC_SYMBOL VkFormatProperties mvkVkFormatProperties(VkFormat vkFormat) {
	return getPlatformPixelFormats()->getVkFormatProperties(vkFormat);
}

MVK_PUBLIC_SYMBOL const char* mvkVkFormatName(VkFormat vkFormat) {
	return getPlatformPixelFormats()->getName(vkFormat);
}

MVK_PUBLIC_SYMBOL const char* mvkMTLPixelFormatName(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->getName(mtlFormat);
}

MVK_PUBLIC_SYMBOL MTLVertexFormat mvkMTLVertexFormatFromVkFormat(VkFormat vkFormat) {
	return getPlatformPixelFormats()->getMTLVertexFormat(vkFormat);
}

MVK_PUBLIC_SYMBOL MTLClearColor mvkMTLClearColorFromVkClearValue(VkClearValue vkClearValue,
																 VkFormat vkFormat) {
	return getPlatformPixelFormats()->getMTLClearColor(vkClearValue, vkFormat);
}

MVK_PUBLIC_SYMBOL double mvkMTLClearDepthFromVkClearValue(VkClearValue vkClearValue) {
	return getPlatformPixelFormats()->getMTLClearDepthValue(vkClearValue);
}

MVK_PUBLIC_SYMBOL uint32_t mvkMTLClearStencilFromVkClearValue(VkClearValue vkClearValue) {
	return getPlatformPixelFormats()->getMTLClearStencilValue(vkClearValue);
}

MVK_PUBLIC_SYMBOL bool mvkMTLPixelFormatIsDepthFormat(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->isDepthFormat(mtlFormat);
}

MVK_PUBLIC_SYMBOL bool mvkMTLPixelFormatIsStencilFormat(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->isStencilFormat(mtlFormat);
}

MVK_PUBLIC_SYMBOL bool mvkMTLPixelFormatIsPVRTCFormat(MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->isPVRTCFormat(mtlFormat);
}


#undef mvkMTLTextureTypeFromVkImageType
MVK_PUBLIC_SYMBOL MTLTextureType mvkMTLTextureTypeFromVkImageType(VkImageType vkImageType,
																  uint32_t arraySize,
																  bool isMultisample) {
	return mvkMTLTextureTypeFromVkImageTypeObj(vkImageType, arraySize, isMultisample, nullptr);
}

MTLTextureType mvkMTLTextureTypeFromVkImageTypeObj(VkImageType vkImageType,
												   uint32_t arraySize,
												   bool isMultisample,
												   MVKBaseObject* mvkObj) {
	switch (vkImageType) {
		case VK_IMAGE_TYPE_3D: return MTLTextureType3D;
		case VK_IMAGE_TYPE_1D: return (mvkGetMVKConfig(mvkObj).texture1DAs2D
									   ? mvkMTLTextureTypeFromVkImageType(VK_IMAGE_TYPE_2D, arraySize, isMultisample)
									   : (arraySize > 1 ? MTLTextureType1DArray : MTLTextureType1D));
		case VK_IMAGE_TYPE_2D:
		default: {
#if MVK_MACOS_OR_IOS
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

#undef mvkMTLTextureTypeFromVkImageViewType
MVK_PUBLIC_SYMBOL MTLTextureType mvkMTLTextureTypeFromVkImageViewType(VkImageViewType vkImageViewType,
																	  bool isMultisample) {
	return mvkMTLTextureTypeFromVkImageViewTypeObj(vkImageViewType, isMultisample, nullptr);
}

MTLTextureType mvkMTLTextureTypeFromVkImageViewTypeObj(VkImageViewType vkImageViewType,
													   bool isMultisample,
													   MVKBaseObject* mvkObj) {
	switch (vkImageViewType) {
		case VK_IMAGE_VIEW_TYPE_3D:			return MTLTextureType3D;
		case VK_IMAGE_VIEW_TYPE_CUBE:		return MTLTextureTypeCube;
		case VK_IMAGE_VIEW_TYPE_CUBE_ARRAY:	return MTLTextureTypeCubeArray;
		case VK_IMAGE_VIEW_TYPE_1D:			return mvkGetMVKConfig(mvkObj).texture1DAs2D ? mvkMTLTextureTypeFromVkImageViewType(VK_IMAGE_VIEW_TYPE_2D, isMultisample) : MTLTextureType1D;
		case VK_IMAGE_VIEW_TYPE_1D_ARRAY:	return mvkGetMVKConfig(mvkObj).texture1DAs2D ? mvkMTLTextureTypeFromVkImageViewType(VK_IMAGE_VIEW_TYPE_2D_ARRAY, isMultisample) : MTLTextureType1DArray;

		case VK_IMAGE_VIEW_TYPE_2D_ARRAY:
#if MVK_MACOS
			if (isMultisample) { return MTLTextureType2DMultisampleArray; }
#endif
			return MTLTextureType2DArray;

		case VK_IMAGE_VIEW_TYPE_2D:
		default:
			return (isMultisample ? MTLTextureType2DMultisample : MTLTextureType2D);
	}
}

MVK_PUBLIC_SYMBOL MTLTextureUsage mvkMTLTextureUsageFromVkImageUsageFlags(VkImageUsageFlags vkImageUsageFlags, MTLPixelFormat mtlPixFmt) {
	return getPlatformPixelFormats()->getMTLTextureUsage(vkImageUsageFlags, mtlPixFmt);
}

MVK_PUBLIC_SYMBOL VkImageUsageFlags mvkVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsage mtlUsage, MTLPixelFormat mtlFormat) {
	return getPlatformPixelFormats()->getVkImageUsageFlags(mtlUsage, mtlFormat);
}

MVK_PUBLIC_SYMBOL uint32_t mvkSampleCountFromVkSampleCountFlagBits(VkSampleCountFlagBits vkSampleCountFlag) {
	// The bits are already in the correct mathematical sequence (assuming only one bit is set)
	return uint32_t(vkSampleCountFlag);
}

MVK_PUBLIC_SYMBOL VkSampleCountFlagBits mvkVkSampleCountFlagBitsFromSampleCount(NSUInteger sampleCount) {
    // The bits are already in the correct mathematical sequence (assuming only POT sample counts)
    return VkSampleCountFlagBits(sampleCount);
}

MVK_PUBLIC_SYMBOL MTLTextureSwizzle mvkMTLTextureSwizzleFromVkComponentSwizzle(VkComponentSwizzle vkSwizzle) {
	switch (vkSwizzle) {
		case VK_COMPONENT_SWIZZLE_ZERO:		return MTLTextureSwizzleZero;
		case VK_COMPONENT_SWIZZLE_ONE:		return MTLTextureSwizzleOne;
		case VK_COMPONENT_SWIZZLE_R:		return MTLTextureSwizzleRed;
		case VK_COMPONENT_SWIZZLE_G:		return MTLTextureSwizzleGreen;
		case VK_COMPONENT_SWIZZLE_B:		return MTLTextureSwizzleBlue;
		case VK_COMPONENT_SWIZZLE_A:		return MTLTextureSwizzleAlpha;
		default:							return MTLTextureSwizzleRed;
	}
}

MVK_PUBLIC_SYMBOL MTLTextureSwizzleChannels mvkMTLTextureSwizzleChannelsFromVkComponentMapping(VkComponentMapping vkMapping) {
#define convert(v, d) \
    v == VK_COMPONENT_SWIZZLE_IDENTITY ? MTLTextureSwizzle##d : mvkMTLTextureSwizzleFromVkComponentSwizzle(v)
    return MTLTextureSwizzleChannelsMake(convert(vkMapping.r, Red), convert(vkMapping.g, Green), convert(vkMapping.b, Blue), convert(vkMapping.a, Alpha));
#undef convert
}

MVK_PUBLIC_SYMBOL float mvkVkClearColorFloatValueFromVkComponentSwizzle(float *colors, uint32_t index, VkComponentSwizzle vkSwizzle) {
	switch (vkSwizzle) {
		case VK_COMPONENT_SWIZZLE_IDENTITY:	return colors[index];
		case VK_COMPONENT_SWIZZLE_ZERO:		return 0.f;
		case VK_COMPONENT_SWIZZLE_ONE:		return 1.f;
		case VK_COMPONENT_SWIZZLE_R:		return colors[0];
		case VK_COMPONENT_SWIZZLE_G:		return colors[1];
		case VK_COMPONENT_SWIZZLE_B:		return colors[2];
		case VK_COMPONENT_SWIZZLE_A:		return colors[3];
		default:							return colors[index];
	}
}

MVK_PUBLIC_SYMBOL uint32_t mvkVkClearColorUIntValueFromVkComponentSwizzle(uint32_t *colors, uint32_t index, VkComponentSwizzle vkSwizzle) {
	switch (vkSwizzle) {
		case VK_COMPONENT_SWIZZLE_IDENTITY:	return colors[index];
		case VK_COMPONENT_SWIZZLE_ZERO:		return 0U;
		case VK_COMPONENT_SWIZZLE_ONE:		return 1U;
		case VK_COMPONENT_SWIZZLE_R:		return colors[0];
		case VK_COMPONENT_SWIZZLE_G:		return colors[1];
		case VK_COMPONENT_SWIZZLE_B:		return colors[2];
		case VK_COMPONENT_SWIZZLE_A:		return colors[3];
		default:							return colors[index];
	}
}

MVK_PUBLIC_SYMBOL int32_t mvkVkClearColorIntValueFromVkComponentSwizzle(int32_t *colors, uint32_t index, VkComponentSwizzle vkSwizzle) {
	switch (vkSwizzle) {
		case VK_COMPONENT_SWIZZLE_IDENTITY:	return colors[index];
		case VK_COMPONENT_SWIZZLE_ZERO:		return 0;
		case VK_COMPONENT_SWIZZLE_ONE:		return 1;
		case VK_COMPONENT_SWIZZLE_R:		return colors[0];
		case VK_COMPONENT_SWIZZLE_G:		return colors[1];
		case VK_COMPONENT_SWIZZLE_B:		return colors[2];
		case VK_COMPONENT_SWIZZLE_A:		return colors[3];
		default:							return colors[index];
	}
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
		case VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT:		return MTLSamplerAddressModeMirrorRepeat;
#if MVK_MACOS || (MVK_IOS && MVK_XCODE_12)
		case VK_SAMPLER_ADDRESS_MODE_MIRROR_CLAMP_TO_EDGE:	return MTLSamplerAddressModeMirrorClampToEdge;
		case VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER:		return MTLSamplerAddressModeClampToBorderColor;
#endif
		default:											return MTLSamplerAddressModeClampToZero;
	}
}

#if MVK_MACOS_OR_IOS
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
	if (mvkAreAllFlagsEnabled(vkWriteFlags, VK_COLOR_COMPONENT_R_BIT)) { mvkEnableFlags(mtlWriteMask, MTLColorWriteMaskRed); }
	if (mvkAreAllFlagsEnabled(vkWriteFlags, VK_COLOR_COMPONENT_G_BIT)) { mvkEnableFlags(mtlWriteMask, MTLColorWriteMaskGreen); }
	if (mvkAreAllFlagsEnabled(vkWriteFlags, VK_COLOR_COMPONENT_B_BIT)) { mvkEnableFlags(mtlWriteMask, MTLColorWriteMaskBlue); }
	if (mvkAreAllFlagsEnabled(vkWriteFlags, VK_COLOR_COMPONENT_A_BIT)) { mvkEnableFlags(mtlWriteMask, MTLColorWriteMaskAlpha); }
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

#if MVK_USE_METAL_PRIVATE_API

// This isn't in any public header yet. I'm really just guessing based on the D3D11 values here.
typedef NS_ENUM(NSUInteger, MTLLogicOperation) {
	MTLLogicOperationClear,
	MTLLogicOperationSet,
	MTLLogicOperationCopy,
	MTLLogicOperationCopyInverted,
	MTLLogicOperationNoop,
	MTLLogicOperationInvert,
	MTLLogicOperationAnd,
	MTLLogicOperationNand,
	MTLLogicOperationOr,
	MTLLogicOperationNor,
	MTLLogicOperationXor,
	MTLLogicOperationEquivalence,
	MTLLogicOperationAndReverse,
	MTLLogicOperationAndInverted,
	MTLLogicOperationOrReverse,
	MTLLogicOperationOrInverted,
};

MVK_PUBLIC_SYMBOL NSUInteger mvkMTLLogicOperationFromVkLogicOp(VkLogicOp vkLogicOp) {
	switch (vkLogicOp) {
		case VK_LOGIC_OP_CLEAR:			return MTLLogicOperationClear;
		case VK_LOGIC_OP_AND:			return MTLLogicOperationAnd;
		case VK_LOGIC_OP_AND_REVERSE:	return MTLLogicOperationAndReverse;
		case VK_LOGIC_OP_COPY:			return MTLLogicOperationCopy;
		case VK_LOGIC_OP_AND_INVERTED:	return MTLLogicOperationAndInverted;
		case VK_LOGIC_OP_NO_OP:			return MTLLogicOperationNoop;
		case VK_LOGIC_OP_XOR:			return MTLLogicOperationXor;
		case VK_LOGIC_OP_OR:			return MTLLogicOperationOr;
		case VK_LOGIC_OP_NOR:			return MTLLogicOperationNor;
		case VK_LOGIC_OP_EQUIVALENT:	return MTLLogicOperationEquivalence;
		case VK_LOGIC_OP_INVERT:		return MTLLogicOperationInvert;
		case VK_LOGIC_OP_OR_REVERSE:	return MTLLogicOperationOrReverse;
		case VK_LOGIC_OP_COPY_INVERTED:	return MTLLogicOperationCopyInverted;
		case VK_LOGIC_OP_OR_INVERTED:	return MTLLogicOperationOrInverted;
		case VK_LOGIC_OP_NAND:			return MTLLogicOperationNand;
		case VK_LOGIC_OP_SET:			return MTLLogicOperationSet;
		default:						return MTLLogicOperationCopy;
	}
}

#endif

MVK_PUBLIC_SYMBOL MTLVertexStepFunction mvkMTLVertexStepFunctionFromVkVertexInputRate(VkVertexInputRate vkVtxStep) {
	switch (vkVtxStep) {
		case VK_VERTEX_INPUT_RATE_VERTEX:		return MTLVertexStepFunctionPerVertex;
		case VK_VERTEX_INPUT_RATE_INSTANCE:		return MTLVertexStepFunctionPerInstance;
		default:								return MTLVertexStepFunctionPerVertex;
	}
}

MVK_PUBLIC_SYMBOL MTLStepFunction mvkMTLStepFunctionFromVkVertexInputRate(VkVertexInputRate vkVtxStep, bool forTess) {
	if (!forTess) {
		return (MTLStepFunction)mvkMTLVertexStepFunctionFromVkVertexInputRate(vkVtxStep);
	}
	switch (vkVtxStep) {
		case VK_VERTEX_INPUT_RATE_VERTEX:		return MTLStepFunctionThreadPositionInGridX;
		case VK_VERTEX_INPUT_RATE_INSTANCE:		return MTLStepFunctionThreadPositionInGridY;
		default:								return MTLStepFunctionThreadPositionInGridX;
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
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN:
			return MTLPrimitiveTypeTriangle;

		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP_WITH_ADJACENCY:
			return MTLPrimitiveTypeTriangleStrip;

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
			return MTLTriangleFillModeFill;

		// Metal does not support VK_POLYGON_MODE_POINT. Next best option is lines.
		case VK_POLYGON_MODE_POINT:
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
		// Metal does not support VK_ATTACHMENT_LOAD_OP_NONE. Next best option is load.
		case VK_ATTACHMENT_LOAD_OP_NONE:
		case VK_ATTACHMENT_LOAD_OP_LOAD:		return MTLLoadActionLoad;
		case VK_ATTACHMENT_LOAD_OP_CLEAR:		return MTLLoadActionClear;
		case VK_ATTACHMENT_LOAD_OP_DONT_CARE:	return MTLLoadActionDontCare;

		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkAttachmentLoadOp value %d is not supported.", vkLoadOp);
			return MTLLoadActionLoad;
	}
}

#undef mvkMTLStoreActionFromVkAttachmentStoreOp
MVK_PUBLIC_SYMBOL MTLStoreAction mvkMTLStoreActionFromVkAttachmentStoreOp(VkAttachmentStoreOp vkStoreOp, bool hasResolveAttachment, bool canResolveFormat) {
	return mvkMTLStoreActionFromVkAttachmentStoreOpInObj(vkStoreOp, hasResolveAttachment, canResolveFormat, nullptr);
}

// If we need to resolve, but the format doesn't support it, we must store the attachment so we can run a post-renderpass compute shader to perform the resolve.
MTLStoreAction mvkMTLStoreActionFromVkAttachmentStoreOpInObj(VkAttachmentStoreOp vkStoreOp, bool hasResolveAttachment, bool canResolveFormat, MVKBaseObject* mvkObj) {
	switch (vkStoreOp) {
		// Metal does not support VK_ATTACHMENT_STORE_OP_NONE. Next best option is store.
		case VK_ATTACHMENT_STORE_OP_NONE:
		case VK_ATTACHMENT_STORE_OP_STORE:
			return hasResolveAttachment && canResolveFormat ? MTLStoreActionStoreAndMultisampleResolve : MTLStoreActionStore;

		case VK_ATTACHMENT_STORE_OP_DONT_CARE:
			return hasResolveAttachment ? (canResolveFormat ? MTLStoreActionMultisampleResolve : MTLStoreActionStore) : MTLStoreActionDontCare;

		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkAttachmentStoreOp value %d is not supported.", vkStoreOp);
			return MTLStoreActionStore;
	}
}

#undef mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBits
MVK_PUBLIC_SYMBOL MTLMultisampleDepthResolveFilter mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBits(VkResolveModeFlagBits vkResolveMode) {
	return mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBitsInObj(vkResolveMode, nullptr);
}

MTLMultisampleDepthResolveFilter mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBitsInObj(VkResolveModeFlagBits vkResolveMode, MVKBaseObject* mvkObj) {
	switch (vkResolveMode) {
		case VK_RESOLVE_MODE_SAMPLE_ZERO_BIT:	return MTLMultisampleDepthResolveFilterSample0;
		case VK_RESOLVE_MODE_MIN_BIT:			return MTLMultisampleDepthResolveFilterMin;
		case VK_RESOLVE_MODE_MAX_BIT:			return MTLMultisampleDepthResolveFilterMax;

		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkResolveModeFlagBits value %d is not supported.", vkResolveMode);
			return MTLMultisampleDepthResolveFilterSample0;
	}
}

#if MVK_MACOS_OR_IOS
#undef mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBits
MVK_PUBLIC_SYMBOL MTLMultisampleStencilResolveFilter mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBits(VkResolveModeFlagBits vkResolveMode) {
	return mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBitsInObj(vkResolveMode, nullptr);
}

MTLMultisampleStencilResolveFilter mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBitsInObj(VkResolveModeFlagBits vkResolveMode, MVKBaseObject* mvkObj) {
	switch (vkResolveMode) {
		case VK_RESOLVE_MODE_SAMPLE_ZERO_BIT:	return MTLMultisampleStencilResolveFilterSample0;

		default:
			MVKBaseObject::reportError(mvkObj, VK_ERROR_FORMAT_NOT_SUPPORTED, "VkResolveModeFlagBits value %d is not supported.", vkResolveMode);
			return MTLMultisampleStencilResolveFilterSample0;
	}
}
#endif

MVK_PUBLIC_SYMBOL MTLViewport mvkMTLViewportFromVkViewport(VkViewport vkViewport) {
	return {
		.originX = vkViewport.x,
		.originY = vkViewport.y,
		.width   = vkViewport.width,
		.height  = vkViewport.height,
		.znear   = vkViewport.minDepth,
		.zfar    = vkViewport.maxDepth
	};
}

MVK_PUBLIC_SYMBOL MTLScissorRect mvkMTLScissorRectFromVkRect2D(VkRect2D vkRect) {
	return {
		.x      = (NSUInteger)max(vkRect.offset.x, 0),
		.y      = (NSUInteger)max(vkRect.offset.y, 0),
		.width  = vkRect.extent.width,
		.height = vkRect.extent.height
	};
}

MVK_PUBLIC_SYMBOL VkRect2D mvkVkRect2DFromMTLScissorRect(MTLScissorRect mtlScissorRect) {
	return {
		.offset = { .x = (int32_t)mtlScissorRect.x, 
					.y = (int32_t)mtlScissorRect.y },
		.extent = { .width = (uint32_t)mtlScissorRect.width, 
					.height = (uint32_t)mtlScissorRect.height }
	};
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
		// Converted to Uint16 internally.
		case VK_INDEX_TYPE_UINT8:
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
			return kMVKShaderStageCount;
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
		case kMVKShaderStageCount:
			assert(!"This function should never be called with kMVKShaderStageCount!");
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

MVK_PUBLIC_SYMBOL MTLRenderStages mvkMTLRenderStagesFromVkPipelineStageFlags(VkPipelineStageFlags2 vkStages,
																			 bool placeBarrierBefore) {
	// Although there are many combined render/compute/host stages in Vulkan, there are only two render
	// stages in Metal. If the Vulkan stage did not map ONLY to a specific Metal render stage, then if the
	// barrier is to be placed before the render stages, it should come before the vertex stage, otherwise
	// if the barrier is to be placed after the render stages, it should come after the fragment stage.
	if (placeBarrierBefore) {
		bool placeBeforeFragment = mvkIsOnlyAnyFlagEnabled(vkStages, (VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT |
																		VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT |
																		VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT |
																		VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT |
																		VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT));
		return placeBeforeFragment ? MTLRenderStageFragment : MTLRenderStageVertex;
	} else {
		bool placeAfterVertex = mvkIsOnlyAnyFlagEnabled(vkStages, (VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT |
																	 VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT |
																	 VK_PIPELINE_STAGE_2_VERTEX_INPUT_BIT |
																	 VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT |
																	 VK_PIPELINE_STAGE_2_TESSELLATION_CONTROL_SHADER_BIT |
																	 VK_PIPELINE_STAGE_2_TESSELLATION_EVALUATION_SHADER_BIT));
		return placeAfterVertex ? MTLRenderStageVertex : MTLRenderStageFragment;
	}
}

MVK_PUBLIC_SYMBOL MTLBarrierScope mvkMTLBarrierScopeFromVkAccessFlags(VkAccessFlags2 vkAccess) {
	MTLBarrierScope mtlScope = MTLBarrierScope(0);
	if ( mvkIsAnyFlagEnabled(vkAccess, (VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT | 
										VK_ACCESS_2_INDEX_READ_BIT |
										VK_ACCESS_2_VERTEX_ATTRIBUTE_READ_BIT | 
										VK_ACCESS_2_UNIFORM_READ_BIT)) ) {
		mtlScope |= MTLBarrierScopeBuffers;
	}
	if ( mvkIsAnyFlagEnabled(vkAccess, (VK_ACCESS_2_SHADER_READ_BIT | 
										VK_ACCESS_2_SHADER_WRITE_BIT |
										VK_ACCESS_2_MEMORY_READ_BIT | 
										VK_ACCESS_2_MEMORY_WRITE_BIT)) ) {
		mtlScope |= MTLBarrierScopeBuffers | MTLBarrierScopeTextures;
	}
#if MVK_MACOS
	if ( mvkIsAnyFlagEnabled(vkAccess, (VK_ACCESS_2_INPUT_ATTACHMENT_READ_BIT | 
										VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT |
										VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT | 
										VK_ACCESS_2_MEMORY_READ_BIT |
										VK_ACCESS_2_MEMORY_WRITE_BIT)) ) {
		mtlScope |= MTLBarrierScopeRenderTargets;
	}
#endif
	return mtlScope;
}


#pragma mark -
#pragma mark Geometry conversions

MVK_PUBLIC_SYMBOL VkExtent2D mvkVkExtent2DFromCGSize(CGSize cgSize) {
	VkExtent2D vkExt;
	vkExt.width = mvkRoundHalfToEven(cgSize.width);
	vkExt.height = mvkRoundHalfToEven(cgSize.height);
	return vkExt;
}

MVK_PUBLIC_SYMBOL CGSize mvkCGSizeFromVkExtent2D(VkExtent2D vkExtent) {
	return CGSizeMake(vkExtent.width, vkExtent.height);
}

MVK_PUBLIC_SYMBOL CGPoint mvkCGPointFromVkOffset2D(VkOffset2D vkOffset) {
	return CGPointMake(vkOffset.x, vkOffset.y);
}

MVK_PUBLIC_SYMBOL CGRect mvkCGRectFromVkRectLayerKHR(VkRectLayerKHR vkRect) {
	return { mvkCGPointFromVkOffset2D(vkRect.offset), mvkCGSizeFromVkExtent2D(vkRect.extent) };
}


#pragma mark -
#pragma mark Memory options

MVK_PUBLIC_SYMBOL MTLCPUCacheMode mvkMTLCPUCacheModeFromVkMemoryPropertyFlags(VkMemoryPropertyFlags vkFlags) {
	return MTLCPUCacheModeDefaultCache;
}

MVK_PUBLIC_SYMBOL MTLResourceOptions mvkMTLResourceOptions(MTLStorageMode mtlStorageMode,
														   MTLCPUCacheMode mtlCPUCacheMode) {
	return (mtlStorageMode << MTLResourceStorageModeShift) | (mtlCPUCacheMode << MTLResourceCPUCacheModeShift);
}
