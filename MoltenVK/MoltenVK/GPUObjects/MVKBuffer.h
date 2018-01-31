/*
 * MVKBuffer.h
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

#include "MVKResource.h"
#include "MVKCommandBuffer.h"

class MVKCommandEncoder;


#pragma mark MVKBuffer

/** Represents a Vulkan buffer. */
class MVKBuffer : public MVKResource {

public:

#pragma mark Resource memory

	/** Returns the memory requirements of this resource by populating the specified structure. */
	VkResult getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements) override;

	/** Applies the specified global memory barrier. */
    void applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
                            VkPipelineStageFlags dstStageMask,
                            VkMemoryBarrier* pMemoryBarrier,
                            MVKCommandEncoder* cmdEncoder,
                            MVKCommandUse cmdUse) override;

	/** Applies the specified buffer memory barrier. */
    void applyBufferMemoryBarrier(VkPipelineStageFlags srcStageMask,
                                  VkPipelineStageFlags dstStageMask,
                                  VkBufferMemoryBarrier* pBufferMemoryBarrier,
                                  MVKCommandEncoder* cmdEncoder,
                                  MVKCommandUse cmdUse);


#pragma mark Metal

	/** Returns the Metal buffer underlying this memory allocation. */
	id<MTLBuffer> getMTLBuffer();

	/** Returns the offset at which the contents of this instance starts within the underlying Metal buffer. */
	NSUInteger getMTLBufferOffset();


#pragma mark Construction
	
	MVKBuffer(MVKDevice* device, const VkBufferCreateInfo* pCreateInfo);

	~MVKBuffer() override;

protected:
	using MVKResource::needsHostReadSync;

    void* map(VkDeviceSize offset, VkDeviceSize size) override;
	VkResult flushToDevice(VkDeviceSize offset, VkDeviceSize size) override;
	VkResult pullFromDevice(VkDeviceSize offset, VkDeviceSize size) override;
    VkResult copyMTLBufferContent(VkDeviceSize offset, VkDeviceSize size, bool intoMTLBuffer);
    NSRange mtlBufferRange(VkDeviceSize offset, VkDeviceSize size);
	bool needsHostReadSync(VkPipelineStageFlags srcStageMask,
						   VkPipelineStageFlags dstStageMask,
						   VkBufferMemoryBarrier* pBufferMemoryBarrier);

    id<MTLBuffer> _mtlBuffer;
    std::mutex _lock;
};


#pragma mark MVKBufferView

/** Represents a Vulkan buffer view. */
class MVKBufferView : public MVKBaseDeviceObject {

public:


#pragma mark Resource memory

    /** Returns the number of bytes used by this buffer view. */
    inline VkDeviceSize getByteCount() { return _byteCount; };


#pragma mark Metal

    /** Returns the Metal buffer underlying this memory allocation. */
    inline id<MTLBuffer> getMTLBuffer() { return _buffer->getMTLBuffer(); }

    /** Returns the offset at which the contents of this instance starts within the underlying Metal buffer. */
    inline NSUInteger getMTLBufferOffset() { return _mtlBufferOffset; }

    /** Returns a Metal texture that overlays this buffer view. */
    id<MTLTexture> getMTLTexture();


#pragma mark Construction

    MVKBufferView(MVKDevice* device, const VkBufferViewCreateInfo* pCreateInfo);

    ~MVKBufferView() override;

protected:
    MVKBuffer* _buffer;
    NSUInteger _mtlBufferOffset;
    MTLPixelFormat _mtlPixelFormat;
    id<MTLTexture> _mtlTexture;
    VkDeviceSize _byteCount;
    VkExtent2D _textureSize;
};

