/*
 * MVKPixelFormats.h
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

#pragma once

#include "MVKBaseObject.h"
#include "MVKOSExtensions.h"
#include "MVKInflectionMap.h"
#include "mvk_datatypes.hpp"
#include <spirv_msl.hpp>
#include <unordered_map>

#import <Metal/Metal.h>

class MVKPhysicalDevice;
struct MVKMTLDeviceCapabilities;


#pragma mark -
#pragma mark Metal format capabilities

typedef enum : uint16_t {

	kMVKMTLFmtCapsNone     = 0,
	kMVKMTLFmtCapsRead     = (1<<0),
	kMVKMTLFmtCapsFilter   = (1<<1),
	kMVKMTLFmtCapsWrite    = (1<<2),
	kMVKMTLFmtCapsAtomic   = (1<<3),
	kMVKMTLFmtCapsColorAtt = (1<<4),
	kMVKMTLFmtCapsDSAtt    = (1<<5),
	kMVKMTLFmtCapsBlend    = (1<<6),
	kMVKMTLFmtCapsMSAA     = (1<<7),
	kMVKMTLFmtCapsResolve  = (1<<8),
	kMVKMTLFmtCapsVertex   = (1<<9),

	kMVKMTLFmtCapsRF       = (kMVKMTLFmtCapsRead | kMVKMTLFmtCapsFilter),
	kMVKMTLFmtCapsRC       = (kMVKMTLFmtCapsRead | kMVKMTLFmtCapsColorAtt),
	kMVKMTLFmtCapsRCB      = (kMVKMTLFmtCapsRC | kMVKMTLFmtCapsBlend),
	kMVKMTLFmtCapsRCM      = (kMVKMTLFmtCapsRC | kMVKMTLFmtCapsMSAA),
	kMVKMTLFmtCapsRCMB     = (kMVKMTLFmtCapsRCM | kMVKMTLFmtCapsBlend),
	kMVKMTLFmtCapsRWC      = (kMVKMTLFmtCapsRC | kMVKMTLFmtCapsWrite),
	kMVKMTLFmtCapsRWCB     = (kMVKMTLFmtCapsRWC | kMVKMTLFmtCapsBlend),
	kMVKMTLFmtCapsRWCM     = (kMVKMTLFmtCapsRWC | kMVKMTLFmtCapsMSAA),
	kMVKMTLFmtCapsRWCMB    = (kMVKMTLFmtCapsRWCM | kMVKMTLFmtCapsBlend),
	kMVKMTLFmtCapsRFCMRB   = (kMVKMTLFmtCapsRCMB | kMVKMTLFmtCapsFilter | kMVKMTLFmtCapsResolve),
	kMVKMTLFmtCapsRFWCMB   = (kMVKMTLFmtCapsRWCMB | kMVKMTLFmtCapsFilter),
	kMVKMTLFmtCapsAll      = (kMVKMTLFmtCapsRFWCMB | kMVKMTLFmtCapsResolve),

	kMVKMTLFmtCapsDRM      = (kMVKMTLFmtCapsDSAtt | kMVKMTLFmtCapsRead | kMVKMTLFmtCapsMSAA),
	kMVKMTLFmtCapsDRFM     = (kMVKMTLFmtCapsDRM | kMVKMTLFmtCapsFilter),
	kMVKMTLFmtCapsDRMR     = (kMVKMTLFmtCapsDRM | kMVKMTLFmtCapsResolve),
	kMVKMTLFmtCapsDRFMR    = (kMVKMTLFmtCapsDRFM | kMVKMTLFmtCapsResolve),

	kMVKMTLFmtCapsChromaSubsampling = kMVKMTLFmtCapsRF,
	kMVKMTLFmtCapsMultiPlanar = kMVKMTLFmtCapsChromaSubsampling,
} MVKMTLFmtCaps;

inline MVKMTLFmtCaps operator|(MVKMTLFmtCaps leftCaps, MVKMTLFmtCaps rightCaps) {
	return static_cast<MVKMTLFmtCaps>(static_cast<uint32_t>(leftCaps) | rightCaps);
}

inline MVKMTLFmtCaps& operator|=(MVKMTLFmtCaps& leftCaps, MVKMTLFmtCaps rightCaps) {
	return (leftCaps = leftCaps | rightCaps);
}


#pragma mark -
#pragma mark Metal view classes

enum class MVKMTLViewClass : uint8_t {
	None,
	Color8,
	Color16,
	Color32,
	Color64,
	Color128,
	PVRTC_RGB_2BPP,
	PVRTC_RGB_4BPP,
	PVRTC_RGBA_2BPP,
	PVRTC_RGBA_4BPP,
	EAC_R11,
	EAC_RG11,
	EAC_RGBA8,
	ETC2_RGB8,
	ETC2_RGB8A1,
	ASTC_4x4,
	ASTC_5x4,
	ASTC_5x5,
	ASTC_6x5,
	ASTC_6x6,
	ASTC_8x5,
	ASTC_8x6,
	ASTC_8x8,
	ASTC_10x5,
	ASTC_10x6,
	ASTC_10x8,
	ASTC_10x10,
	ASTC_12x10,
	ASTC_12x12,
	BC1_RGBA,
	BC2_RGBA,
	BC3_RGBA,
	BC4_R,
	BC5_RG,
	BC6H_RGB,
	BC7_RGBA,
	Depth24_Stencil8,
	Depth32_Stencil8,
	BGRA10_XR,
	BGR10_XR
};


#pragma mark -
#pragma mark Format descriptors

/** Describes the properties of a VkFormat, including the corresponding Metal pixel and vertex format. */
typedef struct MVKVkFormatDesc {
	VkFormat vkFormat;
	MTLPixelFormat mtlPixelFormat;
	MTLPixelFormat mtlPixelFormatSubstitute;
	MTLVertexFormat mtlVertexFormat;
	MTLVertexFormat mtlVertexFormatSubstitute;
    uint8_t chromaSubsamplingPlaneCount;
    uint8_t chromaSubsamplingComponentBits;
	VkExtent2D blockTexelSize;
	uint32_t bytesPerBlock;
	MVKFormatType formatType;
    VkFormatProperties3 properties;
	VkComponentMapping componentMapping;
	const char* name;
	bool hasReportedSubstitution;
    
    inline double bytesPerTexel() const { return (double)bytesPerBlock / (double)(blockTexelSize.width * blockTexelSize.height); };

	inline bool isSupported() const { return (mtlPixelFormat != MTLPixelFormatInvalid || chromaSubsamplingPlaneCount > 1); };
	inline bool isSupportedOrSubstitutable() const { return isSupported() || (mtlPixelFormatSubstitute != MTLPixelFormatInvalid); };

	inline bool vertexIsSupported() const { return (mtlVertexFormat != MTLVertexFormatInvalid); };
	inline bool vertexIsSupportedOrSubstitutable() const { return vertexIsSupported() || (mtlVertexFormatSubstitute != MTLVertexFormatInvalid); };

	bool needsSwizzle() const {
		return (componentMapping.r != VK_COMPONENT_SWIZZLE_IDENTITY ||
				componentMapping.g != VK_COMPONENT_SWIZZLE_IDENTITY ||
				componentMapping.b != VK_COMPONENT_SWIZZLE_IDENTITY ||
				componentMapping.a != VK_COMPONENT_SWIZZLE_IDENTITY);
	}
} MVKVkFormatDesc;

/** Describes the properties of a MTLPixelFormat or MTLVertexFormat. */
typedef struct MVKMTLFormatDesc {
	union {
		MTLPixelFormat mtlPixelFormat;
		MTLVertexFormat mtlVertexFormat;
	};
	VkFormat vkFormat;
	MVKMTLFmtCaps mtlFmtCaps;
	MVKMTLViewClass mtlViewClass;
	MTLPixelFormat mtlPixelFormatLinear;
	const char* name;

	inline bool isSupported() const { return (mtlPixelFormat != MTLPixelFormatInvalid) && (mtlFmtCaps != kMVKMTLFmtCapsNone); };
} MVKMTLFormatDesc;


#pragma mark -
#pragma mark MVKPixelFormats

/** Helper class to manage pixel format capabilities and conversions.  */
class MVKPixelFormats : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

	/** Returns whether the VkFormat is supported by this implementation. */
	bool isSupported(VkFormat vkFormat);

	/** Returns whether the VkFormat is supported by this implementation, or can be substituted by one that is. */
	bool isSupportedOrSubstitutable(VkFormat vkFormat);

	/** Returns whether the MTLPixelFormat is supported by this implementation. */
	bool isSupported(MTLPixelFormat mtlFormat);

	/** Returns whether the specified Metal MTLPixelFormat can be used as a depth format. */
	bool isDepthFormat(MTLPixelFormat mtlFormat);

	/** Returns whether the specified Metal MTLPixelFormat can be used as a stencil format. */
	bool isStencilFormat(MTLPixelFormat mtlFormat);

	/** Returns whether the specified Metal MTLPixelFormat is a PVRTC format. */
	bool isPVRTCFormat(MTLPixelFormat mtlFormat);

	/**
	 * Returns whether the VkFormat only differs from the MTLPixelFormat in that one may be the sRGB
	 * version of the other. Either or both the VkFormat and MTLPixelFormat may be a linear or sRGB format.
	 * Returns true if any of the following are true:
	 *   - The MTLPixelFormat is the Metal version of the VkFormat.
	 *   - The MTLPixelFormat is the Metal sRGB version of the linear VkFormat.
	 *   - The MTLPixelFormat is the Metal linear version of the sRGB VkFormat.
	 * Returns false if none of those conditions apply.
	 */
	bool compatibleAsLinearOrSRGB(MTLPixelFormat mtlFormat, VkFormat vkFormat);

	/** Returns the format type corresponding to the specified Vulkan VkFormat, */
	MVKFormatType getFormatType(VkFormat vkFormat);

	/** Returns the format type corresponding to the specified Metal MTLPixelFormat, */
	MVKFormatType getFormatType(MTLPixelFormat mtlFormat);

	/**
	 * Returns the Metal MTLPixelFormat corresponding to the specified Vulkan VkFormat,
	 * or returns MTLPixelFormatInvalid if no corresponding MTLPixelFormat exists.
	 */
	MTLPixelFormat getMTLPixelFormat(VkFormat vkFormat);

	/**
	 * Returns the Vulkan VkFormat corresponding to the specified Metal MTLPixelFormat,
	 * or returns VK_FORMAT_UNDEFINED if no corresponding VkFormat exists.
	 */
	VkFormat getVkFormat(MTLPixelFormat mtlFormat);

	/**
	 * Returns the size, in bytes, of a texel block of the specified Vulkan format.
	 * For uncompressed formats, the returned value corresponds to the size in bytes of a single texel.
	 */
	uint32_t getBytesPerBlock(VkFormat vkFormat);

	/**
	 * Returns the size, in bytes, of a texel block of the specified Metal format.
	 * For uncompressed formats, the returned value corresponds to the size in bytes of a single texel.
	 */
	uint32_t getBytesPerBlock(MTLPixelFormat mtlFormat);

	/**
	 * Returns the size of the compression block, measured in texels for a Vulkan format.
	 * The returned value will be {1, 1} for non-compressed formats without chroma-subsampling.
	 */
	VkExtent2D getBlockTexelSize(VkFormat vkFormat);

	/**
	 * Returns the size of the compression block, measured in texels for a Metal format.
	 * The returned value will be {1, 1} for non-compressed formats without chroma-subsampling.
	 */
	VkExtent2D getBlockTexelSize(MTLPixelFormat mtlFormat);

	/** Returns the number of planes of the specified chroma-subsampling (YCbCr) VkFormat */
	uint8_t getChromaSubsamplingPlaneCount(VkFormat vkFormat);

	/** Returns the number of bits per channel of the specified chroma-subsampling (YCbCr) VkFormat */
	uint8_t getChromaSubsamplingComponentBits(VkFormat vkFormat);

	/** Returns the MSLFormatResolution of the specified chroma-subsampling (YCbCr) VkFormat */
	SPIRV_CROSS_NAMESPACE::MSLFormatResolution getChromaSubsamplingResolution(VkFormat vkFormat);

	/** Returns the MTLPixelFormat of the specified chroma-subsampling (YCbCr) VkFormat for the specified plane. */
	MTLPixelFormat getChromaSubsamplingPlaneMTLPixelFormat(VkFormat vkFormat, uint8_t planeIndex);

    /** Returns the number of planes, blockTexelSize,  bytesPerBlock and mtlPixFmt of each plane of the specified chroma-subsampling (YCbCr) VkFormat into the given arrays */
    uint8_t getChromaSubsamplingPlanes(VkFormat vkFormat, VkExtent2D blockTexelSize[3], uint32_t bytesPerBlock[3], MTLPixelFormat mtlPixFmt[3]);

	/**
	 * Returns the size, in bytes, of a texel of the specified Vulkan format.
	 * The returned value may be fractional for certain compressed formats.
	 */
	float getBytesPerTexel(VkFormat vkFormat);

	/**
	 * Returns the size, in bytes, of a texel of the specified Metal format.
	 * The returned value may be fractional for certain compressed formats.
	 */
	float getBytesPerTexel(MTLPixelFormat mtlFormat);

	/**
	 * Returns the size, in bytes, of a row of texels of the specified Vulkan format.
	 *
	 * For compressed formats, this takes into consideration the compression block size,
	 * and texelsPerRow should specify the width in texels, not blocks. The result is rounded
	 * up if texelsPerRow is not an integer multiple of the compression block width.
	 */
	size_t getBytesPerRow(VkFormat vkFormat, uint32_t texelsPerRow);

	/**
	 * Returns the size, in bytes, of a row of texels of the specified Metal format.
	 *
	 * For compressed formats, this takes into consideration the compression block size,
	 * and texelsPerRow should specify the width in texels, not blocks. The result is rounded
	 * up if texelsPerRow is not an integer multiple of the compression block width.
	 */
	size_t getBytesPerRow(MTLPixelFormat mtlFormat, uint32_t texelsPerRow);

	/**
	 * Returns the size, in bytes, of a texture layer of the specified Vulkan format.
	 *
	 * For compressed formats, this takes into consideration the compression block size,
	 * and texelRowsPerLayer should specify the height in texels, not blocks. The result is
	 * rounded up if texelRowsPerLayer is not an integer multiple of the compression block height.
	 */
	size_t getBytesPerLayer(VkFormat vkFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer);

	/**
	 * Returns the size, in bytes, of a texture layer of the specified Metal format.
	 * For compressed formats, this takes into consideration the compression block size,
	 * and texelRowsPerLayer should specify the height in texels, not blocks. The result is
	 * rounded up if texelRowsPerLayer is not an integer multiple of the compression block height.
	 */
	size_t getBytesPerLayer(MTLPixelFormat mtlFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer);

	/** Returns whether or not the specified Vulkan format requires swizzling to use with Metal. */
	bool needsSwizzle(VkFormat vkFormat);

	/** Returns any VkComponentMapping needed to use the specified Vulkan format. */
	VkComponentMapping getVkComponentMapping(VkFormat vkFormat);

	/**
	 * Returns the inverse of the VkComponentMapping needed to use the specified Vulkan format.
	 * If the original mapping is not a one-to-one function, the behaviour is undefined.
	 */
	VkComponentMapping getInverseComponentMapping(VkFormat vkFormat);

	/** Returns any MTLTextureSwizzleChannels needed to use the specified Vulkan format. */
	MTLTextureSwizzleChannels getMTLTextureSwizzleChannels(VkFormat vkFormat);

	/** Returns the default properties for the specified Vulkan format. */
    VkFormatProperties getVkFormatProperties(VkFormat format);
	VkFormatProperties3& getVkFormatProperties3(VkFormat vkFormat);

	/** Returns the Metal format capabilities supported by the specified Vulkan format, without substitution. */
	MVKMTLFmtCaps getCapabilities(VkFormat vkFormat, bool isExtended = false);

	/** Returns the Metal format capabilities supported by the specified Metal format. */
	MVKMTLFmtCaps getCapabilities(MTLPixelFormat mtlFormat, bool isExtended = false);

	/** Returns the Metal view class of the specified Vulkan format. */
	MVKMTLViewClass getViewClass(VkFormat vkFormat);

	/** Returns the Metal view class of the specified Metal format. */
	MVKMTLViewClass getViewClass(MTLPixelFormat mtlFormat);

	/** Returns the name of the specified Vulkan format. */
	const char* getName(VkFormat vkFormat);

	/** Returns the name of the specified Metal pixel format. */
	const char* getName(MTLPixelFormat mtlFormat);

	/** Returns the name of the specified Metal vertex format. */
	const char* getName(MTLVertexFormat mtlFormat);

	/**
	 * Returns the MTLClearColor value corresponding to the color value in the VkClearValue,
	 * extracting the color value that is VkFormat for the VkFormat.
	 */
	MTLClearColor getMTLClearColor(VkClearValue vkClearValue, VkFormat vkFormat);

	/** Returns the Metal depth value corresponding to the depth value in the specified VkClearValue. */
	double getMTLClearDepthValue(VkClearValue vkClearValue);

	/** Returns the Metal stencil value corresponding to the stencil value in the specified VkClearValue. */
	uint32_t getMTLClearStencilValue(VkClearValue vkClearValue);

	/** Returns the Vulkan image usage from the Metal texture usage and format. */
	VkImageUsageFlags getVkImageUsageFlags(MTLTextureUsage mtlUsage, MTLPixelFormat mtlFormat);

	/**
	 * Returns the Metal texture usage from the Vulkan image usage and Metal format.
     * isLinear further restricts the allowed usage to those that are valid for linear textures.
	 * needsReinterpretation indicates an image view with a format that needs reinterpretation will be applied.
     * isExtended expands the allowed usage to those that are valid for all formats which
     * can be used in a view created from the specified format.
	 */
	MTLTextureUsage getMTLTextureUsage(VkImageUsageFlags vkImageUsageFlags,
									   MTLPixelFormat mtlFormat,
									   VkSampleCountFlagBits samples = VK_SAMPLE_COUNT_1_BIT,
                                       bool isLinear = false,
                                       bool needsReinterpretation = true,
                                       bool isExtended = false,
									   bool supportAtomics = false);

	/** Enumerates all formats that support the given features, calling a specified function for each one. */
	void enumerateSupportedFormats(const VkFormatProperties3& properties, bool any, std::function<bool(VkFormat)> func);

	/**
	 * Returns the Metal MTLVertexFormat corresponding to the specified
	 * Vulkan VkFormat as used as a vertex attribute format.
	 */
	MTLVertexFormat getMTLVertexFormat(VkFormat vkFormat);
    
    static VkFormatFeatureFlags convertFormatPropertiesFlagBits(VkFormatFeatureFlags2 flags);
#pragma mark Construction

	MVKPixelFormats(MVKPhysicalDevice* physicalDevice = nullptr);

protected:
	MVKVkFormatDesc& getVkFormatDesc(VkFormat vkFormat);
	MVKVkFormatDesc& getVkFormatDesc(MTLPixelFormat mtlFormat);
	MVKMTLFormatDesc& getMTLPixelFormatDesc(MTLPixelFormat mtlFormat);
	MVKMTLFmtCaps& getMTLPixelFormatCapsIf(MTLPixelFormat mtlPixFmt, bool cond);
	MVKMTLFormatDesc& getMTLVertexFormatDesc(MTLVertexFormat mtlFormat);
	id<MTLDevice> getMTLDevice();
	void initVkFormatCapabilities();
	void initMTLPixelFormatCapabilities(const MVKMTLDeviceCapabilities& gpuCaps);
	void initMTLVertexFormatCapabilities(const MVKMTLDeviceCapabilities& gpuCaps);
	void modifyMTLFormatCapabilities(const MVKMTLDeviceCapabilities& gpuCaps);
	void buildVkFormatMaps(const MVKMTLDeviceCapabilities& gpuCaps);
	void setFormatProperties(MVKVkFormatDesc& vkDesc, const MVKMTLDeviceCapabilities& gpuCaps);
	void addMTLPixelFormatDescImpl(MTLPixelFormat mtlPixFmt, MTLPixelFormat mtlPixFmtLinear,
								   MVKMTLViewClass viewClass, MVKMTLFmtCaps fmtCaps, const char* name);
	void addValidatedMTLPixelFormatDesc(MTLPixelFormat mtlPixFmt, MTLPixelFormat mtlPixFmtLinear,
										MVKMTLViewClass viewClass, MVKMTLFmtCaps appleGPUCaps, MVKMTLFmtCaps macGPUCaps,
										const MVKMTLDeviceCapabilities& mtlDevCaps, const char* name);
	void addMTLVertexFormatDescImpl(MTLVertexFormat mtlVtxFmt, MVKMTLFmtCaps vtxCap, const char* name);

	MVKPhysicalDevice* _physicalDevice;
	MVKInflectionMap<VkFormat, MVKVkFormatDesc, VK_FORMAT_ASTC_12x12_SRGB_BLOCK + 1> _vkFormatDescriptions;
	MVKInflectionMap<uint16_t, MVKMTLFormatDesc, MTLPixelFormatX32_Stencil8 + 2> _mtlPixelFormatDescriptions;  // The actual last enum value is not available on iOS
	MVKSmallVector<MVKMTLFormatDesc> _mtlVertexFormatDescriptions;
};
