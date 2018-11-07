/*
 * MVKBuffer.h
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

	/** Returns the memory requirements of this resource by populating the specified structure. */
	VkResult getMemoryRequirements(const void* pInfo, VkMemoryRequirements2* pMemoryRequirements) override;

	/** Binds this resource to the specified offset within the specified memory allocation. */
	VkResult bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) override;

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
	inline id<MTLBuffer> getMTLBuffer() { return _deviceMemory ? _deviceMemory->getMTLBuffer() : nullptr; }

	/** Returns the offset at which the contents of this instance starts within the underlying Metal buffer. */
	inline NSUInteger getMTLBufferOffset() { return _deviceMemoryOffset; }


#pragma mark Construction
	
	MVKBuffer(MVKDevice* device, const VkBufferCreateInfo* pCreateInfo);

	~MVKBuffer() override;

protected:
	using MVKResource::needsHostReadSync;

	bool needsHostReadSync(VkPipelineStageFlags srcStageMask,
						   VkPipelineStageFlags dstStageMask,
						   VkBufferMemoryBarrier* pBufferMemoryBarrier);
};


#pragma mark MVKBufferView

/** Represents a Vulkan buffer view. */
class MVKBufferView : public MVKBaseDeviceObject {

public:

#pragma mark Metal

    /** Returns a Metal texture that overlays this buffer view. */
    id<MTLTexture> getMTLTexture();


#pragma mark Construction

    MVKBufferView(MVKDevice* device, const VkBufferViewCreateInfo* pCreateInfo);

    ~MVKBufferView() override;

protected:
    MVKBuffer* _buffer;
	id<MTLTexture> _mtlTexture;
	MTLPixelFormat _mtlPixelFormat;
    NSUInteger _mtlBufferOffset;
	NSUInteger _mtlBytesPerRow;
    VkExtent2D _textureSize;
	std::mutex _lock;
};

