/*
 * MVKCommandResourceFactory.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"
#include <string>

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKRPSKeyBlitImg

/**
 * Key to use for looking up cached MTLRenderPipelineState instances based on MTLPixelFormat and MTLTextureType.
 *
 * This structure can be used as a key in a std::map and std::unordered_map.
 */
typedef struct MVKRPSKeyBlitImg_t {
	uint16_t srcMTLPixelFormat = 0;			/**< as MTLPixelFormat */
	uint16_t srcMTLTextureType = 0;			/**< as MTLTextureType */
	uint16_t dstMTLPixelFormat = 0;			/**< as MTLPixelFormat */
	uint16_t dstSampleCount = 0;

	bool operator==(const MVKRPSKeyBlitImg_t& rhs) const {
		if (srcMTLPixelFormat != rhs.srcMTLPixelFormat) { return false; }
		if (srcMTLTextureType != rhs.srcMTLTextureType) { return false; }
		if (dstMTLPixelFormat != rhs.dstMTLPixelFormat) { return false; }
		if (dstSampleCount != rhs.dstSampleCount) { return false; }
		return true;
	}

	inline MTLPixelFormat getSrcMTLPixelFormat() { return (MTLPixelFormat)srcMTLPixelFormat; }

	inline MTLPixelFormat getDstMTLPixelFormat() { return (MTLPixelFormat)dstMTLPixelFormat; }

	inline bool isSrcArrayType() {
		return (srcMTLTextureType == MTLTextureType2DArray ||
#if MVK_MACOS
				srcMTLTextureType == MTLTextureType2DMultisampleArray ||
#endif
				srcMTLTextureType == MTLTextureType1DArray); }

	std::size_t hash() const {
		std::size_t hash = srcMTLPixelFormat;
		hash <<= 16;
		hash |= srcMTLTextureType;
		hash <<= 16;
		hash |= dstMTLPixelFormat;
		hash <<= 16;
		hash |= dstSampleCount;
		return hash;
	}

} MVKRPSKeyBlitImg;

/**
 * Hash structure implementation for MVKRPSKeyBlitImg in std namespace,
 * so MVKRPSKeyBlitImg can be used as a key in a std::map and std::unordered_map.
 */
namespace std {
	template <>
	struct hash<MVKRPSKeyBlitImg> {
		std::size_t operator()(const MVKRPSKeyBlitImg& k) const { return k.hash(); }
	};
}


#pragma mark -
#pragma mark MVKRPSKeyClearAtt

#define kMVKClearAttachmentCount						(kMVKCachedColorAttachmentCount + 1)
#define kMVKClearAttachmentDepthStencilIndex			(kMVKClearAttachmentCount - 1)
#define kMVKClearAttachmentLayeredRenderingBitIndex		kMVKClearAttachmentCount

/**
 * Key to use for looking up cached MTLRenderPipelineState instances.
 * Indicates which attachments are used, and holds the Metal pixel formats for each
 * color attachment plus one depth/stencil attachment. Also holds the Metal sample count.
 *
 * This structure can be used as a key in a std::map and std::unordered_map.
 */
typedef struct MVKRPSKeyClearAtt_t {
    uint16_t attachmentMTLPixelFormats[kMVKClearAttachmentCount];
	uint16_t mtlSampleCount;
    uint16_t flags;			// bitcount > kMVKClearAttachmentLayeredRenderingBitIndex

    const static uint32_t bitFlag = 1;

    void enableAttachment(uint32_t attIdx) { mvkEnableFlag(flags, bitFlag << attIdx); }

    bool isAttachmentEnabled(uint32_t attIdx) { return mvkIsAnyFlagEnabled(flags, bitFlag << attIdx); }

	void enableLayeredRendering() { mvkEnableFlag(flags, bitFlag << kMVKClearAttachmentLayeredRenderingBitIndex); }

	bool isLayeredRenderingEnabled() { return mvkIsAnyFlagEnabled(flags, bitFlag << kMVKClearAttachmentLayeredRenderingBitIndex); }

    bool operator==(const MVKRPSKeyClearAtt_t& rhs) const {
        return ((flags == rhs.flags) &&
				(mtlSampleCount == rhs.mtlSampleCount) &&
                (memcmp(attachmentMTLPixelFormats, rhs.attachmentMTLPixelFormats, sizeof(attachmentMTLPixelFormats)) == 0));
    }

	std::size_t hash() const {
		std::size_t hash = mvkHash(&flags);
		hash = mvkHash(&mtlSampleCount, 1, hash);
		return mvkHash(attachmentMTLPixelFormats, kMVKClearAttachmentCount, hash);
	}

	void reset() {
		memset(this, 0, sizeof(*this));
		mtlSampleCount = mvkSampleCountFromVkSampleCountFlagBits(VK_SAMPLE_COUNT_1_BIT);
	}

	MVKRPSKeyClearAtt_t() { reset(); }

} MVKRPSKeyClearAtt;

/**
 * Hash structure implementation for MVKRPSKeyClearAtt in std namespace,
 * so MVKRPSKeyClearAtt can be used as a key in a std::map and std::unordered_map.
 */
namespace std {
    template <>
    struct hash<MVKRPSKeyClearAtt> {
        std::size_t operator()(const MVKRPSKeyClearAtt& k) const { return k.hash(); }
    };
}


#pragma mark -
#pragma mark MVKMTLDepthStencilDescriptorData

/**
 * A structure to hold configuration data for creating an MTLStencilDescriptor instance.
 *
 * The order of elements is designed to "fail-fast", with the more commonly changing elements
 * situated near the beginning of the structure so that a memory comparison will detect any
 * change as early as possible.
 */
typedef struct MVKMTLStencilDescriptorData_t {
    bool enabled;                       /**< Indicates whether stencil testing for this face is enabled. */
    uint8_t stencilCompareFunction;		/**< The stencil compare function (interpreted as MTLCompareFunction). */
    uint8_t stencilFailureOperation;	/**< The operation to take when the stencil test fails (interpreted as MTLStencilOperation). */
    uint8_t depthFailureOperation;		/**< The operation to take when the stencil test passes, but the depth test fails (interpreted as MTLStencilOperation). */
    uint8_t depthStencilPassOperation;	/**< The operation to take when both the stencil and depth tests pass (interpreted as MTLStencilOperation). */
    uint32_t readMask;					/**< The bit-mask to apply when comparing the stencil buffer value to the reference value. */
    uint32_t writeMask;					/**< The bit-mask to apply when writing values to the stencil buffer. */

    MVKMTLStencilDescriptorData_t() {

        // Start with all zeros to ensure memory comparisons will work,
        // even if the structure contains alignment gaps.
        memset(this, 0, sizeof(*this));

        enabled = false,
        stencilCompareFunction = MTLCompareFunctionAlways;
        stencilFailureOperation = MTLStencilOperationKeep;
        depthFailureOperation = MTLStencilOperationKeep;
        depthStencilPassOperation = MTLStencilOperationKeep;
        readMask = static_cast<uint32_t>(~0);
        writeMask = static_cast<uint32_t>(~0);
    }

} MVKMTLStencilDescriptorData;

/** An instance populated with default values, for use in resetting other instances to default state. */
const MVKMTLStencilDescriptorData kMVKMTLStencilDescriptorDataDefault;

/**
 * A structure to hold configuration data for creating an MTLDepthStencilDescriptor instance.
 * Instances of this structure can be used as a map key.
 *
 * The order of elements is designed to "fail-fast", with the more commonly changing elements
 * situated near the beginning of the structure so that a memory comparison will detect any
 * change as early as possible.
 */
typedef struct MVKMTLDepthStencilDescriptorData_t {
    uint8_t depthCompareFunction;		/**< The depth compare function (interpreted as MTLCompareFunction). */
    bool depthWriteEnabled;				/**< Indicates whether depth writing is enabled. */
    MVKMTLStencilDescriptorData frontFaceStencilData;
    MVKMTLStencilDescriptorData backFaceStencilData;

	bool operator==(const MVKMTLDepthStencilDescriptorData_t& rhs) const {
		return (memcmp(this, &rhs, sizeof(*this)) == 0);
	}

	std::size_t hash() const {
		return mvkHash((uint64_t*)this, sizeof(*this) / sizeof(uint64_t));
	}

    MVKMTLDepthStencilDescriptorData_t() {

        // Start with all zeros to ensure memory comparisons will work,
        // even if the structure contains alignment gaps.
        memset(this, 0, sizeof(*this));

        depthCompareFunction = MTLCompareFunctionAlways;
        depthWriteEnabled = false;

        frontFaceStencilData = kMVKMTLStencilDescriptorDataDefault;
        backFaceStencilData = kMVKMTLStencilDescriptorDataDefault;
    }

} __attribute__((aligned(sizeof(uint64_t)))) MVKMTLDepthStencilDescriptorData;

/** An instance populated with default values, for use in resetting other instances to default state. */
const MVKMTLDepthStencilDescriptorData kMVKMTLDepthStencilDescriptorDataDefault;

namespace std {
    template <>
    struct hash<MVKMTLDepthStencilDescriptorData> {
        std::size_t operator()(const MVKMTLDepthStencilDescriptorData& k) const { return k.hash(); }
    };
}


#pragma mark -
#pragma mark MVKImageDescriptorData

/**
 * Key to use for looking up cached MVKImage instances, and to create a new MVKImage when needed.
 * The contents of this structure is a subset of the contents of the VkImageCreateInfo structure.
 *
 * This structure can be used as a key in a std::map and std::unordered_map.
 */
typedef struct MVKImageDescriptorData_t {
    VkImageType              imageType;
    VkFormat                 format;
    VkExtent3D               extent;
    uint32_t                 mipLevels;
    uint32_t                 arrayLayers;
    VkSampleCountFlagBits    samples;
    VkImageUsageFlags        usage;

    bool operator==(const MVKImageDescriptorData_t& rhs) const {
        return (memcmp(this, &rhs, sizeof(*this)) == 0);
    }

	std::size_t hash() const {
		return mvkHash((uint64_t*)this, sizeof(*this) / sizeof(uint64_t));
	}

    MVKImageDescriptorData_t() { memset(this, 0, sizeof(*this)); }

} __attribute__((aligned(sizeof(uint64_t)))) MVKImageDescriptorData;

/**
 * Hash structure implementation for MVKImageDescriptorData in std namespace, so
 * MVKImageDescriptorData can be used as a key in a std::map and std::unordered_map.
 */
namespace std {
    template <>
    struct hash<MVKImageDescriptorData> {
        std::size_t operator()(const MVKImageDescriptorData& k) const { return k.hash(); }
    };
}


#pragma mark -
#pragma mark MVKBufferDescriptorData

/**
 * Key to use for looking up cached MVKBuffer instances, and to create a new MVKBuffer when needed.
 * The contents of this structure is a subset of the contents of the VkBufferCreateInfo structure.
 *
 * This structure can be used as a key in a std::map and std::unordered_map.
 */
typedef struct MVKBufferDescriptorData_t {
    VkDeviceSize             size;
    VkBufferUsageFlags       usage;

    bool operator==(const MVKBufferDescriptorData_t& rhs) const {
        return (memcmp(this, &rhs, sizeof(*this)) == 0);
    }

	std::size_t hash() const {
		return mvkHash((uint64_t*)this, sizeof(*this) / sizeof(uint64_t));
	}

    MVKBufferDescriptorData_t() { memset(this, 0, sizeof(*this)); }

} __attribute__((aligned(sizeof(uint64_t)))) MVKBufferDescriptorData;

/**
 * Hash structure implementation for MVKBufferDescriptorData in std namespace, so
 * MVKBufferDescriptorData can be used as a key in a std::map and std::unordered_map.
 */
namespace std {
    template <>
    struct hash<MVKBufferDescriptorData> {
        std::size_t operator()(const MVKBufferDescriptorData& k) const { return k.hash(); }
    };
}


#pragma mark -
#pragma mark MVKCommandResourceFactory

/** 
 * This factory class consolidates the manufacturing of various pipeline components 
 * for commands whose functionality is realized through render or compute pipelines.
 */
class MVKCommandResourceFactory : public MVKBaseDeviceObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _device->getVulkanAPIObject(); };

#pragma mark Command resources

	/** Returns a new MTLRenderPipelineState to support certain Vulkan BLIT commands. */
	id<MTLRenderPipelineState> newCmdBlitImageMTLRenderPipelineState(MVKRPSKeyBlitImg& blitKey,
																	 MVKVulkanAPIDeviceObject* owner);

	/**
	 * Returns a new MTLSamplerState dedicated to rendering to a texture using the
	 * specified min/mag filter value to support certain Vulkan BLIT commands.
	 */
	id<MTLSamplerState> newCmdBlitImageMTLSamplerState(MTLSamplerMinMagFilter mtlFilter);

	/**
	 * Returns a new MTLRenderPipelineState dedicated to rendering to several 
	 * attachments to support clearing regions of those attachments.
	 */
	id<MTLRenderPipelineState> newCmdClearMTLRenderPipelineState(MVKRPSKeyClearAtt& attKey,
																 MVKVulkanAPIDeviceObject* owner);

	/**
	 * Returns a new MTLDepthStencilState dedicated to rendering to several 
	 * attachments to support clearing regions of those attachments.
	 */
	id<MTLDepthStencilState> newMTLDepthStencilState(bool useDepth, bool useStencil);

    /**
     * Returns a new MTLDepthStencilState configured from the specified data.
     * Returns nil if the specified data indicates depth and stencil testing is disabled.
     */
    id<MTLDepthStencilState> newMTLDepthStencilState(MVKMTLDepthStencilDescriptorData& dsData);

    /** Returns an retained MTLStencilDescriptor constructed from the stencil data. */
    MTLStencilDescriptor* newMTLStencilDescriptor(MVKMTLStencilDescriptorData& sData);

    /**
     * Returns a new MVKImage configured with content held in Private storage.
	 * The image returned is bound to an empty device memory, and can be used
	 * as a temporary image during image transfers.
     */
    MVKImage* newMVKImage(MVKImageDescriptorData& imgData);
    
    /**
     * Returns a new MVKBuffer configured with content held in Private storage.
     * The buffer returned is bound to a new device memory, also returned, and
     * can be used as a temporary buffer during buffer-image transfers.
     */
    MVKBuffer* newMVKBuffer(MVKBufferDescriptorData& buffData, MVKDeviceMemory*& buffMem);
    
    /** Returns a new MTLComputePipelineState for copying between two buffers with byte-aligned copy regions. */
    id<MTLComputePipelineState> newCmdCopyBufferBytesMTLComputePipelineState(MVKVulkanAPIDeviceObject* owner);

	/** Returns a new MTLComputePipelineState for filling a buffer. */
	id<MTLComputePipelineState> newCmdFillBufferMTLComputePipelineState(MVKVulkanAPIDeviceObject* owner);

	/** Returns a new MTLComputePipelineState for copying between a buffer holding compressed data and a 3D image. */
	id<MTLComputePipelineState> newCmdCopyBufferToImage3DDecompressMTLComputePipelineState(bool needTempBuf,
																						   MVKVulkanAPIDeviceObject* owner);

	/** Returns a new MTLComputePipelineState for converting an indirect buffer for use in a tessellated draw. */
	id<MTLComputePipelineState> newCmdDrawIndirectConvertBuffersMTLComputePipelineState(bool indexed,
																						MVKVulkanAPIDeviceObject* owner);

	/** Returns a new MTLComputePipelineState for copying an index buffer for use in a tessellated draw. */
	id<MTLComputePipelineState> newCmdDrawIndexedCopyIndexBufferMTLComputePipelineState(MTLIndexType type,
																						MVKVulkanAPIDeviceObject* owner);

	/** Returns a new MTLComputePipelineState for copying query results to a buffer. */
	id<MTLComputePipelineState> newCmdCopyQueryPoolResultsMTLComputePipelineState(MVKVulkanAPIDeviceObject* owner);


#pragma mark Construction

	MVKCommandResourceFactory(MVKDevice* device);

	~MVKCommandResourceFactory() override;

protected:
	void initMTLLibrary();
	void initImageDeviceMemory();
	id<MTLFunction> newBlitFragFunction(MVKRPSKeyBlitImg& blitKey);
	id<MTLFunction> newClearVertFunction(MVKRPSKeyClearAtt& attKey);
	id<MTLFunction> newClearFragFunction(MVKRPSKeyClearAtt& attKey);
	NSString* getMTLFormatTypeString(MTLPixelFormat mtlPixFmt);
    id<MTLFunction> newFunctionNamed(const char* funcName);
	id<MTLFunction> newMTLFunction(NSString* mslSrcCode, NSString* funcName);
	id<MTLRenderPipelineState> newMTLRenderPipelineState(MTLRenderPipelineDescriptor* plDesc,
														 MVKVulkanAPIDeviceObject* owner);
	id<MTLComputePipelineState> newMTLComputePipelineState(const char* funcName,
														   MVKVulkanAPIDeviceObject* owner);

	id<MTLLibrary> _mtlLibrary;
	MVKDeviceMemory* _transferImageMemory;
};

