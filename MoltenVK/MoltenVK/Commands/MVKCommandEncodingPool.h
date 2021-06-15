/*
 * MVKCommandEncodingPool.h
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCommandResourceFactory.h"
#include "MVKMTLBufferAllocation.h"
#include <unordered_map>
#include <mutex>

#import <Metal/Metal.h>


class MVKCommandPool;


#pragma mark -
#pragma mark MVKCommandEncodingPool

/** 
 * Represents a pool containing transient resources that commands can use during encoding
 * onto a queue. This is distinct from a command pool, which contains resources that can
 * be assigned to commands when their content is established.
 *
 * Access to the content within this pool is thread-safe.
 */
class MVKCommandEncodingPool : public MVKBaseObject {

public:

#pragma mark Command resources

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

	/** Returns a MTLRenderPipelineState to support certain Vulkan BLIT commands. */
    id<MTLRenderPipelineState> getCmdBlitImageMTLRenderPipelineState(MVKRPSKeyBlitImg& blitKey);

    /**
     * Returns a MTLDepthStencilState dedicated to rendering to several attachments
     * to support clearing regions of those attachments.
     */
    id<MTLDepthStencilState> getMTLDepthStencilState(bool useDepth, bool useStencil);

    /**
     * Acquires and returns an allocation of the specified length from within a MTLBuffer.
     *
     * The returned allocation will have a size that is the next
     * power-of-two value that is at least as big as the requested size.
     *
     * To return the returned allocation back to the pool to be reused,
     * call the returnToPool() function on the returned allocation.
     */
    MVKMTLBufferAllocation* acquireMTLBufferAllocation(NSUInteger length, bool isPrivate = false, bool isDedicated = false);

	/**
	 * Returns a MTLRenderPipelineState dedicated to rendering to several attachments
	 * to support clearing regions of those attachments.
	 */
	id<MTLRenderPipelineState> getCmdClearMTLRenderPipelineState(MVKRPSKeyClearAtt& attKey);

    /** Returns a MTLDepthStencilState configured from the specified data. */
    id<MTLDepthStencilState> getMTLDepthStencilState(MVKMTLDepthStencilDescriptorData& dsData);

    /**
     * Returns an MVKImage configured from the specified MTLTexture configuration,
     * with content held in Private storage. The object returned can be used as a
     * temporary image during image transfers.
     *
     * The same image instance will be returned for two calls to this function with
     * the same image descriptor data. This implies that the same image instance could 
     * be used by two transfers within the same encoder or queue. This is acceptable 
     * becuase the content only needs to be valid during the transfer, and it can be
     * reused by subsequent transfers in the same encoding run.
     */
    MVKImage* getTransferMVKImage(MVKImageDescriptorData& imgData);
    
    /**
     * Returns an MVKBuffer configured from the specified MTLBuffer configuration,
     * with content held in Private storage. The object returned can be used as a
     * temporary buffer during buffer-image transfers.
     *
     * The same buffer instance will be returned for two calls to this funciton with
     * the same buffer descriptor data. This implies that the same buffer instance could 
     * be used by two transfers within the same encoder or queue. This is acceptable 
     * becuase the content only needs to be valid during the transfer, and it can be 
     * reused by subsequent transfers in the same encoding run.
     */
    MVKBuffer* getTransferMVKBuffer(MVKBufferDescriptorData& buffData);
    
	/** Returns a MTLComputePipelineState for copying between two buffers with byte-aligned copy regions. */
    id<MTLComputePipelineState> getCmdCopyBufferBytesMTLComputePipelineState();

	/** Returns a MTLComputePipelineState for filling a buffer. */
	id<MTLComputePipelineState> getCmdFillBufferMTLComputePipelineState();

#if MVK_MACOS
	/** Returns a MTLComputePipelineState for clearing an image. Currently only used for 2D linear images on Mac. */
	id<MTLComputePipelineState> getCmdClearColorImageMTLComputePipelineState(MVKFormatType type);
#endif

	/** Returns a MTLComputePipelineState for decompressing a buffer into a 3D image. */
	id<MTLComputePipelineState> getCmdCopyBufferToImage3DDecompressMTLComputePipelineState(bool needsTempBuff);

	/** Returns a MTLComputePipelineState for converting an indirect buffer for use in a multiview draw. */
	id<MTLComputePipelineState> getCmdDrawIndirectMultiviewConvertBuffersMTLComputePipelineState(bool indexed);

	/** Returns a MTLComputePipelineState for converting an indirect buffer for use in a tessellated draw. */
	id<MTLComputePipelineState> getCmdDrawIndirectTessConvertBuffersMTLComputePipelineState(bool indexed);

	/** Returns a MTLComputePipelineState for copying an index buffer for use in an indirect tessellated draw. */
	id<MTLComputePipelineState> getCmdDrawIndexedCopyIndexBufferMTLComputePipelineState(MTLIndexType type);

	/** Returns a MTLComputePipelineState for copying query results to a buffer. */
	id<MTLComputePipelineState> getCmdCopyQueryPoolResultsMTLComputePipelineState();

	/** Returns a MTLComputePipelineState for accumulating occlusion query results over multiple render passes. */
	id<MTLComputePipelineState> getAccumulateOcclusionQueryResultsMTLComputePipelineState();

	/** Deletes all the internal resources. */
	void clear();

#pragma mark Construction

	MVKCommandEncodingPool(MVKCommandPool* commandPool);

	~MVKCommandEncodingPool() override;

protected:
	void destroyMetalResources();

	MVKCommandPool* _commandPool;
	std::mutex _lock;
    std::unordered_map<MVKRPSKeyBlitImg, id<MTLRenderPipelineState>> _cmdBlitImageMTLRenderPipelineStates;
	std::unordered_map<MVKRPSKeyClearAtt, id<MTLRenderPipelineState>> _cmdClearMTLRenderPipelineStates;
    std::unordered_map<MVKMTLDepthStencilDescriptorData, id<MTLDepthStencilState>> _mtlDepthStencilStates;
    std::unordered_map<MVKImageDescriptorData, MVKImage*> _transferImages;
    std::unordered_map<MVKBufferDescriptorData, MVKBuffer*> _transferBuffers;
    std::unordered_map<MVKBufferDescriptorData, MVKDeviceMemory*> _transferBufferMemory;
    MVKMTLBufferAllocator _mtlBufferAllocator;
    MVKMTLBufferAllocator _privateMtlBufferAllocator;
    MVKMTLBufferAllocator _dedicatedMtlBufferAllocator;
    id<MTLDepthStencilState> _cmdClearDepthOnlyDepthStencilState = nil;
    id<MTLDepthStencilState> _cmdClearStencilOnlyDepthStencilState = nil;
    id<MTLDepthStencilState> _cmdClearDepthAndStencilDepthStencilState = nil;
    id<MTLDepthStencilState> _cmdClearDefaultDepthStencilState = nil;
    id<MTLComputePipelineState> _mtlCopyBufferBytesComputePipelineState = nil;
	id<MTLComputePipelineState> _mtlFillBufferComputePipelineState = nil;
#if MVK_MACOS
	id<MTLComputePipelineState> _mtlClearColorImageComputePipelineState[3] = {nil, nil, nil};
#endif
	id<MTLComputePipelineState> _mtlCopyBufferToImage3DDecompressComputePipelineState[2] = {nil, nil};
	id<MTLComputePipelineState> _mtlDrawIndirectMultiviewConvertBuffersComputePipelineState[2] = {nil, nil};
	id<MTLComputePipelineState> _mtlDrawIndirectTessConvertBuffersComputePipelineState[2] = {nil, nil};
	id<MTLComputePipelineState> _mtlDrawIndexedCopyIndexBufferComputePipelineState[2] = {nil, nil};
	id<MTLComputePipelineState> _mtlCopyQueryPoolResultsComputePipelineState = nil;
	id<MTLComputePipelineState> _mtlAccumOcclusionQueryResultsComputePipelineState = nil;
};

