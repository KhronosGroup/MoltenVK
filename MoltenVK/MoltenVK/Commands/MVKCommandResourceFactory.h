/*
 * MVKCommandResourceFactory.h
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include <string>

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKRPSKeyClearAtt

#define kMVKAttachmentFormatCount					9
#define kMVKAttachmentFormatDepthStencilIndex		(kMVKAttachmentFormatCount - 1)

/**
 * Key to use for looking up cached MTLRenderPipelineState instances.
 * Holds the formats for each color attachment plus one depth/stencil attachment.
 *
 * This structure can be used as a key in a std::map and std::unordered_map.
 */
typedef struct MVKRPSKeyClearAtt_t {
    uint16_t attachmentMTLPixelFormats[kMVKAttachmentFormatCount];
    uint32_t enabledFlags;
    const static uint32_t bitFlag = 1;

    void enable(uint32_t attIdx) { mvkEnableFlag(enabledFlags, bitFlag << attIdx); }

    bool isEnabled(uint32_t attIdx) { return mvkIsAnyFlagEnabled(enabledFlags, bitFlag << attIdx); }

    bool isEnabledOnly(uint32_t attIdx) {
        // Ignore depth stencil bit
        uint32_t colorFlags = enabledFlags;
        mvkDisableFlag(colorFlags, bitFlag << kMVKAttachmentFormatDepthStencilIndex);
        return mvkAreOnlyFlagsEnabled(colorFlags, bitFlag << attIdx);
    }

    bool operator==(const MVKRPSKeyClearAtt_t& rhs) const {
        return ((enabledFlags == rhs.enabledFlags) &&
                (memcmp(attachmentMTLPixelFormats, rhs.attachmentMTLPixelFormats, sizeof(attachmentMTLPixelFormats)) == 0));
    }

    void reset() { memset(this, 0, sizeof(*this)); }

    MVKRPSKeyClearAtt_t() { reset(); }
} MVKRPSKeyClearAtt;

/**
 * Hash structure implementation for MVKRPSKeyClearAtt in std namespace,
 * so MVKRPSKeyClearAtt can be used as a key in a std::map and std::unordered_map.
 */
namespace std {
    template <>
    struct hash<MVKRPSKeyClearAtt> {
        std::size_t operator()(const MVKRPSKeyClearAtt& k) const {
            std::size_t hash = mvkHash(&k.enabledFlags, 1);
            return mvkHash(k.attachmentMTLPixelFormats, kMVKAttachmentFormatCount, hash);
        }
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
    std::size_t _hash;
    uint8_t depthCompareFunction;		/**< The depth compare function (interpreted as MTLCompareFunction). */
    bool depthWriteEnabled;				/**< Indicates whether depth writing is enabled. */
    MVKMTLStencilDescriptorData frontFaceStencilData;
    MVKMTLStencilDescriptorData backFaceStencilData;

    std::size_t hash() {
        if ( !_hash ) { _hash = mvkHash((uint64_t*)this, sizeof(*this) / sizeof(uint64_t)); }
        return _hash;
    }
    void clearHash() { _hash = 0; }

    bool operator==(const MVKMTLDepthStencilDescriptorData_t& rhs) const {
        MVKMTLDepthStencilDescriptorData_t* pLHS = (MVKMTLDepthStencilDescriptorData_t*)this;
        MVKMTLDepthStencilDescriptorData_t* pRHS = (MVKMTLDepthStencilDescriptorData_t*)&rhs;

        if (pLHS == pRHS) { return true; }
        if (!pLHS) { return false; }
        if (!pRHS) { return false; }
        if (pLHS->hash() != pRHS->hash()) { return false; }

        return (memcmp(pLHS, pRHS, sizeof(*this)) == 0);
    }

    MVKMTLDepthStencilDescriptorData_t() {

        // Start with all zeros to ensure memory comparisons will work,
        // even if the structure contains alignment gaps.
        memset(this, 0, sizeof(*this));

        _hash = 0;
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
    struct hash<MVKMTLDepthStencilDescriptorData_t> {
        std::size_t operator()(const MVKMTLDepthStencilDescriptorData_t& k) const {
            MVKMTLDepthStencilDescriptorData_t* pK = (MVKMTLDepthStencilDescriptorData_t*)&k;
            return pK->hash();
        }
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

    MVKImageDescriptorData_t() { memset(this, 0, sizeof(*this)); }

} __attribute__((aligned(sizeof(uint64_t)))) MVKImageDescriptorData;

/**
 * Hash structure implementation for MVKImageDescriptorData in std namespace, so
 * MVKImageDescriptorData can be used as a key in a std::map and std::unordered_map.
 */
namespace std {
    template <>
    struct hash<MVKImageDescriptorData> {
        std::size_t operator()(const MVKImageDescriptorData& k) const {
            return mvkHash((uint64_t*)this, sizeof(*this) / sizeof(uint64_t));
        }
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

#pragma mark Command resources

	/**
	 * Returns a new MTLRenderPipelineState dedicated to rendering to a texture
	 * in the specified pixel format to support certain Vulkan BLIT commands.
	 */
	id<MTLRenderPipelineState> newCmdBlitImageMTLRenderPipelineState(MTLPixelFormat mtlPixFmt);

	/**
	 * Returns a new MTLSamplerState dedicated to rendering to a texture using the
	 * specified min/mag filter value to support certain Vulkan BLIT commands.
	 */
	id<MTLSamplerState> newCmdBlitImageMTLSamplerState(MTLSamplerMinMagFilter mtlFilter);

	/**
	 * Returns a new MTLRenderPipelineState dedicated to rendering to several 
	 * attachments to support clearing regions of those attachments.
	 */
	id<MTLRenderPipelineState> newCmdClearMTLRenderPipelineState(MVKRPSKeyClearAtt& attKey);

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

    /** Returns an autoreleased MTLStencilDescriptor constructed from the stencil data. */
    MTLStencilDescriptor* mtlMTLStencilDescriptor(MVKMTLStencilDescriptorData& sData);

    /**
     * Returns a new MVKImage configured from the specified MTLTexture configuration,
     * with content held in Private storage. The object returned can be used as a
     * temporary image during image transfers.
     */
    MVKImage* newMVKImage(MVKImageDescriptorData& imgData);


#pragma mark Construction

	MVKCommandResourceFactory(MVKDevice* device);

	~MVKCommandResourceFactory() override;

protected:
	void initMTLLibrary();
    std::string getFragFunctionSuffix(MTLPixelFormat mtlPixFmt);
    std::string getFragFunctionSuffix(MVKRPSKeyClearAtt& attKey);
    id<MTLFunction> getFunctionNamed(const char* funcName);
    id<MTLRenderPipelineState> newMTLRenderPipelineState(MTLRenderPipelineDescriptor* plDesc);

	id<MTLLibrary> _mtlLibrary;
};

