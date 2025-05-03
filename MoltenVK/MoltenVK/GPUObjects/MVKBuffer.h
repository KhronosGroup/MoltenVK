/*
 * MVKBuffer.h
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

#include "MVKResource.h"
#include "MVKCommandBuffer.h"

class MVKCommandEncoder;


#pragma mark MVKBuffer

/** Represents a Vulkan buffer. */
class MVKBuffer : public MVKResource {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_BUFFER; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_BUFFER_EXT; }

#pragma mark Resource memory

	/** Returns the memory requirements of this resource by populating the specified structure. */
	VkResult getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements);

	/** Returns the memory requirements of this resource by populating the specified structure. */
	VkResult getMemoryRequirements(VkMemoryRequirements2* pMemoryRequirements);

	/** Binds this resource to the specified offset within the specified memory allocation. */
	VkResult bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) override;

	/** Binds this resource to the specified offset within the specified memory allocation. */
	VkResult bindDeviceMemory2(const VkBindBufferMemoryInfo* pBindInfo);

	/** Applies the specified global memory barrier. */
	void applyMemoryBarrier(MVKPipelineBarrier& barrier,
							MVKCommandEncoder* cmdEncoder,
							MVKCommandUse cmdUse) override;

	/** Applies the specified buffer memory barrier. */
	void applyBufferMemoryBarrier(MVKPipelineBarrier& barrier,
								  MVKCommandEncoder* cmdEncoder,
								  MVKCommandUse cmdUse);

    /** Returns the intended usage of this buffer. */
    VkBufferUsageFlags2 getUsage() const { return _usage; }


#pragma mark Metal

	/** Returns the Metal buffer underlying this memory allocation. */
    id<MTLBuffer> getMTLBuffer();

	/** Returns the offset at which the contents of this instance starts within the underlying Metal buffer. */
	inline NSUInteger getMTLBufferOffset() { return !_deviceMemory || _deviceMemory->getMTLHeap() ? 0 : _deviceMemoryOffset; }

    /** Returns the Metal buffer used as a cache for host-coherent texel buffers. */
    id<MTLBuffer> getMTLBufferCache();
    
	/** Returns the GPU address for this MTLBuffer, respecting its offset. */
	uint64_t getMTLBufferGPUAddress();

#pragma mark Construction
	
	MVKBuffer(MVKDevice* device, const VkBufferCreateInfo* pCreateInfo);

	~MVKBuffer() override;

	void destroy() override;

protected:
	friend class MVKDeviceMemory;

	void propagateDebugName() override;
	bool needsHostReadSync(MVKPipelineBarrier& barrier);
    bool overlaps(VkDeviceSize offset, VkDeviceSize size, VkDeviceSize &overlapOffset, VkDeviceSize &overlapSize);
	bool shouldFlushHostMemory();
	VkResult flushToDevice(VkDeviceSize offset, VkDeviceSize size);
	VkResult pullFromDevice(VkDeviceSize offset, VkDeviceSize size);
	void initExternalMemory(VkExternalMemoryHandleTypeFlags handleTypes);
	void detachMemory();

	VkBufferUsageFlags2 _usage;
	bool _isHostCoherentTexelBuffer = false;
    id<MTLBuffer> _mtlBufferCache = nil;
	id<MTLBuffer> _mtlBuffer = nil;
    std::mutex _lock;
};


#pragma mark MVKBufferView

/** Represents a Vulkan buffer view. */
class MVKBufferView : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_BUFFER_VIEW; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_BUFFER_VIEW_EXT; }

#pragma mark Metal

    /** Returns a Metal texture that overlays this buffer view. */
    id<MTLTexture> getMTLTexture();


#pragma mark Construction

    MVKBufferView(MVKDevice* device, const VkBufferViewCreateInfo* pCreateInfo);

    ~MVKBufferView() override;

	void destroy() override;

protected:
	void propagateDebugName() override;
	void detachMemory();

	MVKBuffer* _buffer;
	NSUInteger _offset;
	VkBufferUsageFlags2 _usage;
	id<MTLTexture> _mtlTexture;
	MTLPixelFormat _mtlPixelFormat;
	NSUInteger _mtlBytesPerRow;
	VkExtent2D _textureSize;
	std::mutex _lock;
};

