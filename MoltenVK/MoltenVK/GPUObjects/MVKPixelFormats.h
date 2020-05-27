/*
 * MVKPixelFormats.h
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

#pragma once

#include "mvk_datatypes.h"
#include "MVKEnvironment.h"
#include "MVKBaseObject.h"
#include <unordered_map>

#import <Metal/Metal.h>

class MVKPhysicalDevice;


// Validate these values periodically as new formats are added over time.
static const uint32_t _vkFormatCount = 256;
static const uint32_t _vkFormatCoreCount = VK_FORMAT_ASTC_12x12_SRGB_BLOCK + 1;
static const uint32_t _mtlPixelFormatCount = MTLPixelFormatX32_Stencil8 + 2;     // The actual last enum value is not available on iOS
static const uint32_t _mtlVertexFormatCount = MTLVertexFormatHalf + 1;


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
	kMVKMTLFmtCapsDRMR     = (kMVKMTLFmtCapsDRM | kMVKMTLFmtCapsResolve),
	kMVKMTLFmtCapsDRFMR    = (kMVKMTLFmtCapsDRMR | kMVKMTLFmtCapsFilter),

} MVKMTLFmtCaps;


#pragma mark -
#pragma mark Format descriptors

/** Describes the properties of a VkFormat, including the corresponding Metal pixel and vertex format. */
typedef struct {
	VkFormat vkFormat;
	MTLPixelFormat mtlPixelFormat;
	MTLPixelFormat mtlPixelFormatSubstitute;
	MTLVertexFormat mtlVertexFormat;
	MTLVertexFormat mtlVertexFormatSubstitute;
	VkExtent2D blockTexelSize;
	uint32_t bytesPerBlock;
	MVKFormatType formatType;
	VkFormatProperties properties;
	const char* name;
	bool hasReportedSubstitution;

	inline double bytesPerTexel() const { return (double)bytesPerBlock / (double)(blockTexelSize.width * blockTexelSize.height); };

	inline bool isSupported() const { return (mtlPixelFormat != MTLPixelFormatInvalid); };
	inline bool isSupportedOrSubstitutable() const { return isSupported() || (mtlPixelFormatSubstitute != MTLPixelFormatInvalid); };
	inline MTLPixelFormat getMTLPixelFormatOrSubstitute() const { return mtlPixelFormat ? mtlPixelFormat : mtlPixelFormatSubstitute; }

	inline bool vertexIsSupported() const { return (mtlVertexFormat != MTLVertexFormatInvalid); };
	inline bool vertexIsSupportedOrSubstitutable() const { return vertexIsSupported() || (mtlVertexFormatSubstitute != MTLVertexFormatInvalid); };
	inline MTLVertexFormat getMTLVertexFormatOrSubstitute() const { return mtlVertexFormat ? mtlVertexFormat : mtlVertexFormatSubstitute; }
} MVKVkFormatDesc;

/** Describes the properties of a MTLPixelFormat or MTLVertexFormat. */
typedef struct {
	union {
		MTLPixelFormat mtlPixelFormat;
		MTLVertexFormat mtlVertexFormat;
	};
	VkFormat vkFormat;
	MVKMTLFmtCaps mtlFmtCaps;
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
	 * The returned value will be {1, 1} for non-compressed formats.
	 */
	VkExtent2D getBlockTexelSize(VkFormat vkFormat);

	/**
	 * Returns the size of the compression block, measured in texels for a Metal format.
	 * The returned value will be {1, 1} for non-compressed formats.
	 */
	VkExtent2D getBlockTexelSize(MTLPixelFormat mtlFormat);

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

	/** Returns the default properties for the specified Vulkan format. */
	VkFormatProperties getVkFormatProperties(VkFormat vkFormat);

	/** Returns the Metal format capabilities supported by the specified Vulkan format. */
	MVKMTLFmtCaps getCapabilities(VkFormat vkFormat);

	/** Returns the Metal format capabilities supported by the specified Metal format. */
	MVKMTLFmtCaps getCapabilities(MTLPixelFormat mtlFormat);

	/** Returns the name of the specified Vulkan format. */
	const char* getName(VkFormat vkFormat);

	/** Returns the name of the specified Metal pixel format. */
	const char* getName(MTLPixelFormat mtlFormat);

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
	 * Returns the Metal texture usage from the Vulkan image usage and Metal format, ensuring that at least the
	 * usages in minUsage are included, even if they wouldn't naturally be included based on the other two parameters.
	 */
	MTLTextureUsage getMTLTextureUsage(VkImageUsageFlags vkImageUsageFlags,
									   MTLPixelFormat mtlFormat,
									   MTLTextureUsage minUsage = MTLTextureUsageUnknown,
									   VkBool32 allowImageCopyFormatReinterpretation = true);

	/** Enumerates all formats that support the given features, calling a specified function for each one. */
	void enumerateSupportedFormats(VkFormatProperties properties, bool any, std::function<bool(VkFormat)> func);

	/**
	 * Returns the Metal MTLVertexFormat corresponding to the specified
	 * Vulkan VkFormat as used as a vertex attribute format.
	 */
	MTLVertexFormat getMTLVertexFormat(VkFormat vkFormat);


#pragma mark Construction

	MVKPixelFormats(MVKPhysicalDevice* physicalDevice = nullptr);

protected:
	MVKVkFormatDesc& getVkFormatDesc(VkFormat vkFormat);
	MVKVkFormatDesc& getVkFormatDesc(MTLPixelFormat mtlFormat);
	MVKMTLFormatDesc& getMTLPixelFormatDesc(VkFormat vkFormat);
	MVKMTLFormatDesc& getMTLPixelFormatDesc(MTLPixelFormat mtlFormat);
	MVKMTLFormatDesc& getMTLVertexFormatDesc(VkFormat vkFormat);
	MVKMTLFormatDesc& getMTLVertexFormatDesc(MTLVertexFormat mtlFormat);
	void initVkFormatCapabilities();
	void initMTLPixelFormatCapabilities();
	void initMTLVertexFormatCapabilities();
	void buildMTLFormatMaps();
	void buildVkFormatMaps();
	void setFormatProperties(MVKVkFormatDesc& vkDesc);
	void modifyMTLFormatCapabilities();
	void modifyMTLFormatCapabilities(id<MTLDevice> mtlDevice);
	void addMTLPixelFormatCapabilities(id<MTLDevice> mtlDevice,
									   MTLFeatureSet mtlFeatSet,
									   MTLPixelFormat mtlPixFmt,
									   MVKMTLFmtCaps mtlFmtCaps);
	void addMTLVertexFormatCapabilities(id<MTLDevice> mtlDevice,
										MTLFeatureSet mtlFeatSet,
										MTLVertexFormat mtlVtxFmt,
										MVKMTLFmtCaps mtlFmtCaps);

	template<typename T>
	void testFmt(const T v1, const T v2, const char* fmtName, const char* funcName);
	void testProps(const VkFormatProperties p1, const VkFormatProperties p2, const char* fmtName);
	void test();

	MVKPhysicalDevice* _physicalDevice;
	MVKVkFormatDesc _vkFormatDescriptions[_vkFormatCount];
	MVKMTLFormatDesc _mtlPixelFormatDescriptions[_mtlPixelFormatCount];
	MVKMTLFormatDesc _mtlVertexFormatDescriptions[_mtlVertexFormatCount];

	// Vulkan core formats have small values and are mapped by simple lookup array.
	// Vulkan extension formats have larger values and are mapped by a map.
	uint16_t _vkFormatDescIndicesByVkFormatsCore[_vkFormatCoreCount];
	std::unordered_map<uint32_t, uint32_t> _vkFormatDescIndicesByVkFormatsExt;

	// Metal formats have small values and are mapped by simple lookup array.
	uint16_t _mtlFormatDescIndicesByMTLPixelFormats[_mtlPixelFormatCount];
	uint16_t _mtlFormatDescIndicesByMTLVertexFormats[_mtlVertexFormatCount];
};
