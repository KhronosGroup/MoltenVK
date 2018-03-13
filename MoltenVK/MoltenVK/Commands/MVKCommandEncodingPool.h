/*
 * MVKCommandEncodingPool.h
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKCommandResourceFactory.h"
#include "MVKMTLBufferAllocation.h"
#include <unordered_map>

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKCommandEncodingPool

/** 
 * Represents a pool containing transient resources that commands can use during encoding
 * onto a queue. This is distinct from a command pool, which contains resources that can be 
 * assigned to commands when their content is established.
 *
 * Access to the content within this pool is not thread-safe. All access to the content
 * of this pool should be done during the MVKCommand::encode() member functions.
 */
class MVKCommandEncodingPool : public MVKBaseDeviceObject {

public:

#pragma mark Command resources

    /**
     * Returns a MTLRenderPipelineState dedicated to rendering to a texture
     * in the specified pixel format to support certain Vulkan BLIT commands.
     */
    id<MTLRenderPipelineState> getCmdBlitImageMTLRenderPipelineState(MTLPixelFormat mtlPixFmt);

    /**
     * Returns a MTLSamplerState dedicated to rendering to a texture using the
     * specified min/mag filter value to support certain Vulkan BLIT commands.
     */
    id<MTLSamplerState> getCmdBlitImageMTLSamplerState(MTLSamplerMinMagFilter mtlFilter);

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
    const MVKMTLBufferAllocation* acquireMTLBufferAllocation(NSUInteger length);

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
     * The same image instance will be returned for two calls to this funciton with
     * the same image descriptor data. This implies that the same image instance could 
     * be used by two transfers within the same encoder or queue. This is acceptable 
     * becuase the content only needss to be valid during the transfer, and it can be 
     * reused by subsequent transfers in the same encoding run.
     */
    MVKImage* getTransferMVKImage(MVKImageDescriptorData& imgData);
    
    /**
     * Returns an MTLComputePipelineState dedicated to copying bytes between two buffers
     * with unaligned copy regions.
     */
    id<MTLComputePipelineState> getCopyBufferBytesComputePipelineState();

#pragma mark Construction

	MVKCommandEncodingPool(MVKDevice* device);

	~MVKCommandEncodingPool() override;

private:
    void initTextureDeviceMemory();
	void destroyMetalResources();

    std::unordered_map<uint32_t, id<MTLRenderPipelineState>> _cmdBlitImageMTLRenderPipelineStates;
	std::unordered_map<MVKRPSKeyClearAtt, id<MTLRenderPipelineState>> _cmdClearMTLRenderPipelineStates;
    std::unordered_map<MVKMTLDepthStencilDescriptorData, id<MTLDepthStencilState>> _mtlDepthStencilStates;
    std::unordered_map<MVKImageDescriptorData, MVKImage*> _transferImages;
    MVKDeviceMemory* _transferImageMemory;
    MVKMTLBufferAllocator _mtlBufferAllocator;
    id<MTLSamplerState> _cmdBlitImageLinearMTLSamplerState;
    id<MTLSamplerState> _cmdBlitImageNearestMTLSamplerState;
    id<MTLDepthStencilState> _cmdClearDepthOnlyDepthStencilState;
    id<MTLDepthStencilState> _cmdClearStencilOnlyDepthStencilState;
    id<MTLDepthStencilState> _cmdClearDepthAndStencilDepthStencilState;
    id<MTLDepthStencilState> _cmdClearDefaultDepthStencilState;
    id<MTLComputePipelineState> _mtlCopyBufferBytesComputePipelineState;
};

