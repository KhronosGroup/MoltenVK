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
#include "MVKOSExtensions.h"
#include <unordered_map>

#import <Metal/Metal.h>


/** Validate these values periodically as new formats are added over time. */
static const uint32_t _vkFormatCount = 256;
static const uint32_t _vkFormatCoreCount = VK_FORMAT_ASTC_12x12_SRGB_BLOCK + 1;
static const uint32_t _mtlPixelFormatCount = MTLPixelFormatX32_Stencil8 + 2;     // The actual last enum value is not available on iOS
static const uint32_t _mtlVertexFormatCount = MTLVertexFormatHalf + 1;


#pragma mark -
#pragma mark Format descriptions

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
	inline bool vertexIsSupported() const { return (mtlVertexFormat != MTLVertexFormatInvalid); };
	inline bool vertexIsSupportedOrSubstitutable() const { return vertexIsSupported() || (mtlVertexFormatSubstitute != MTLVertexFormatInvalid); };
} MVKVkFormatDesc;

/** Describes the properties of a MTLPixelFormat or MTLVertexFormat. */
typedef struct {
	union {
		MTLPixelFormat mtlPixelFormat;
		MTLVertexFormat mtlVertexFormat;
	};
	VkFormat vkFormat;
	MVKOSVersion sinceIOSVersion;
	MVKOSVersion sinceMacOSVersion;
	const char* name;

	inline MVKOSVersion sinceOSVersion() const {
#if MVK_IOS
		return sinceIOSVersion;
#endif
#if MVK_MACOS
		return sinceMacOSVersion;
#endif
	}
	inline bool isSupported() const { return (mtlPixelFormat != MTLPixelFormatInvalid) && (mvkOSVersion() >= sinceOSVersion()); };
} MVKMTLFormatDesc;


#pragma mark -
#pragma mark MVKPixelFormats

/** Helper class to manage pixel format capabilities and conversions.  */
class MVKPixelFormats : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _apiObject; };

	/** Returns whether the VkFormat is supported by this implementation. */
	bool vkFormatIsSupported(VkFormat vkFormat);

	/** Returns whether the MTLPixelFormat is supported by this implementation. */
	bool mtlPixelFormatIsSupported(MTLPixelFormat mtlFormat);

	/** Returns whether the specified Metal MTLPixelFormat can be used as a depth format. */
	bool mtlPixelFormatIsDepthFormat(MTLPixelFormat mtlFormat);

	/** Returns whether the specified Metal MTLPixelFormat can be used as a stencil format. */
	bool mtlPixelFormatIsStencilFormat(MTLPixelFormat mtlFormat);

	/** Returns whether the specified Metal MTLPixelFormat is a PVRTC format. */
	bool mtlPixelFormatIsPVRTCFormat(MTLPixelFormat mtlFormat);

	/** Returns the format type corresponding to the specified Vulkan VkFormat, */
	MVKFormatType getFormatTypeFromVkFormat(VkFormat vkFormat);

	/** Returns the format type corresponding to the specified Metal MTLPixelFormat, */
	MVKFormatType getFormatTypeFromMTLPixelFormat(MTLPixelFormat mtlFormat);

	/**
	 * Returns the Metal MTLPixelFormat corresponding to the specified Vulkan VkFormat,
	 * or returns MTLPixelFormatInvalid if no corresponding MTLPixelFormat exists.
	 */
	MTLPixelFormat getMTLPixelFormatFromVkFormat(VkFormat vkFormat);

	/**
	 * Returns the Vulkan VkFormat corresponding to the specified Metal MTLPixelFormat,
	 * or returns VK_FORMAT_UNDEFINED if no corresponding VkFormat exists.
	 */
	VkFormat getVkFormatFromMTLPixelFormat(MTLPixelFormat mtlFormat);

	/**
	 * Returns the size, in bytes, of a texel block of the specified Vulkan format.
	 * For uncompressed formats, the returned value corresponds to the size in bytes of a single texel.
	 */
	uint32_t getVkFormatBytesPerBlock(VkFormat vkFormat);

	/**
	 * Returns the size, in bytes, of a texel block of the specified Metal format.
	 * For uncompressed formats, the returned value corresponds to the size in bytes of a single texel.
	 */
	uint32_t getMTLPixelFormatBytesPerBlock(MTLPixelFormat mtlFormat);

	/**
	 * Returns the size of the compression block, measured in texels for a Vulkan format.
	 * The returned value will be {1, 1} for non-compressed formats.
	 */
	VkExtent2D getVkFormatBlockTexelSize(VkFormat vkFormat);

	/**
	 * Returns the size of the compression block, measured in texels for a Metal format.
	 * The returned value will be {1, 1} for non-compressed formats.
	 */
	VkExtent2D getMTLPixelFormatBlockTexelSize(MTLPixelFormat mtlFormat);

	/**
	 * Returns the size, in bytes, of a texel of the specified Vulkan format.
	 * The returned value may be fractional for certain compressed formats.
	 */
	float getVkFormatBytesPerTexel(VkFormat vkFormat);

	/**
	 * Returns the size, in bytes, of a texel of the specified Metal format.
	 * The returned value may be fractional for certain compressed formats.
	 */
	float getMTLPixelFormatBytesPerTexel(MTLPixelFormat mtlFormat);

	/**
	 * Returns the size, in bytes, of a row of texels of the specified Vulkan format.
	 *
	 * For compressed formats, this takes into consideration the compression block size,
	 * and texelsPerRow should specify the width in texels, not blocks. The result is rounded
	 * up if texelsPerRow is not an integer multiple of the compression block width.
	 */
	size_t getVkFormatBytesPerRow(VkFormat vkFormat, uint32_t texelsPerRow);

	/**
	 * Returns the size, in bytes, of a row of texels of the specified Metal format.
	 *
	 * For compressed formats, this takes into consideration the compression block size,
	 * and texelsPerRow should specify the width in texels, not blocks. The result is rounded
	 * up if texelsPerRow is not an integer multiple of the compression block width.
	 */
	size_t getMTLPixelFormatBytesPerRow(MTLPixelFormat mtlFormat, uint32_t texelsPerRow);

	/**
	 * Returns the size, in bytes, of a texture layer of the specified Vulkan format.
	 *
	 * For compressed formats, this takes into consideration the compression block size,
	 * and texelRowsPerLayer should specify the height in texels, not blocks. The result is
	 * rounded up if texelRowsPerLayer is not an integer multiple of the compression block height.
	 */
	size_t getVkFormatBytesPerLayer(VkFormat vkFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer);

	/**
	 * Returns the size, in bytes, of a texture layer of the specified Metal format.
	 * For compressed formats, this takes into consideration the compression block size,
	 * and texelRowsPerLayer should specify the height in texels, not blocks. The result is
	 * rounded up if texelRowsPerLayer is not an integer multiple of the compression block height.
	 */
	size_t getMTLPixelFormatBytesPerLayer(MTLPixelFormat mtlFormat, size_t bytesPerRow, uint32_t texelRowsPerLayer);

	/** Returns the default properties for the specified Vulkan format. */
	VkFormatProperties getVkFormatProperties(VkFormat vkFormat);

	/** Returns the name of the specified Vulkan format. */
	const char* getVkFormatName(VkFormat vkFormat);

	/** Returns the name of the specified Metal pixel format. */
	const char* getMTLPixelFormatName(MTLPixelFormat mtlFormat);

	/**
	 * Returns the MTLClearColor value corresponding to the color value in the VkClearValue,
	 * extracting the color value that is VkFormat for the VkFormat.
	 */
	MTLClearColor getMTLClearColorFromVkClearValue(VkClearValue vkClearValue,
												   VkFormat vkFormat);

	/** Returns the Metal depth value corresponding to the depth value in the specified VkClearValue. */
	double getMTLClearDepthFromVkClearValue(VkClearValue vkClearValue);

	/** Returns the Metal stencil value corresponding to the stencil value in the specified VkClearValue. */
	uint32_t getMTLClearStencilFromVkClearValue(VkClearValue vkClearValue);

	/** Returns the Vulkan image usage from the Metal texture usage and format. */
	VkImageUsageFlags getVkImageUsageFlagsFromMTLTextureUsage(MTLTextureUsage mtlUsage, MTLPixelFormat mtlFormat);

	/** Enumerates all formats that support the given features, calling a specified function for each one. */
	void enumerateSupportedFormats(VkFormatProperties properties, bool any, std::function<bool(VkFormat)> func);

	/**
	 * Returns the Metal MTLVertexFormat corresponding to the specified
	 * Vulkan VkFormat as used as a vertex attribute format.
	 */
	MTLVertexFormat getMTLVertexFormatFromVkFormat(VkFormat vkFormat);


#pragma mark Construction

	MVKPixelFormats(MVKVulkanAPIObject* apiObject, id<MTLDevice> mtlDevice);

	MVKPixelFormats() : MVKPixelFormats(nullptr, nil) {}

protected:
	MVKVkFormatDesc& getDescForVkFormat(VkFormat vkFormat);
	MVKMTLFormatDesc& getDescForMTLPixelFormat(MTLPixelFormat mtlFormat);
	MVKMTLFormatDesc& getDescForMTLVertexFormat(MTLVertexFormat mtlFormat);
	void initVkFormatCapabilities();
	void initMTLPixelFormatCapabilities();
	void initMTLVertexFormatCapabilities();
	void buildFormatMaps();
	void modifyFormatCapabilitiesForMTLDevice(id<MTLDevice> mtlDevice);
	void disableMTLPixelFormat(MTLPixelFormat mtlFormat);

	template<typename T>
	void testFmt(const T v1, const T v2, const char* fmtName, const char* funcName);
	void test();

	MVKVulkanAPIObject* _apiObject;
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
