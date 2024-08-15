/*
 * MVKDeviceMemory.h
 *
 * Copyright (c) 2015-2024 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKSmallVector.h"
#include <mutex>

#import <Metal/Metal.h>

class MVKImageMemoryBinding;

// TODO: These are inoperable placeholders until VK_KHR_external_memory_metal defines them properly
static const VkExternalMemoryHandleTypeFlagBits VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_KHR = VK_EXTERNAL_MEMORY_HANDLE_TYPE_FLAG_BITS_MAX_ENUM;
static const VkExternalMemoryHandleTypeFlagBits VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR = VK_EXTERNAL_MEMORY_HANDLE_TYPE_FLAG_BITS_MAX_ENUM;


#pragma mark MVKDeviceMemory

typedef struct MVKMemoryRange {
	VkDeviceSize offset = 0u;
	VkDeviceSize size = 0u;
} MVKMemoryRange;

/** Represents a Vulkan device-space memory allocation. */
class MVKDeviceMemory : public MVKVulkanAPIDeviceObject {

public:
	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DEVICE_MEMORY; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DEVICE_MEMORY_EXT; }

	/** Returns whether the memory is accessible from the host. */
	inline bool isMemoryHostAccessible() {
		MTLStorageMode storageMode = getMTLStorageMode();
#if MVK_APPLE_SILICON
		if (storageMode == MTLStorageModeMemoryless)
			return false;
#endif
		return (storageMode != MTLStorageModePrivate);
	}

	/** Returns whether the memory is automatically coherent between device and host. */
	inline bool isMemoryHostCoherent() { return getMTLStorageMode() == MTLStorageModeShared; }

	/** Returns whether this is a dedicated allocation. */
	inline bool isDedicatedAllocation() { return _dedicatedResourceType != DedicatedResourceType::NONE; }

	/** Returns the memory already committed by this instance. */
	inline VkDeviceSize getDeviceMemoryCommitment() { return _size; }

	/**
	 * Returns the host memory address of this memory, or NULL if the memory has not been
	 * mapped yet, or is marked as device-only and cannot be mapped to a host address.
	 */
	inline void* getHostMemoryAddress() { return _map; }

	/**
	 * Maps the memory address at the specified offset from the start of this memory allocation,
	 * and returns the address in the specified data reference.
	 */
	VkResult map(const VkMemoryMapInfoKHR* mapInfo, void** ppData);
	
	/** Unmaps a previously mapped memory range. */
	VkResult unmap(const VkMemoryUnmapInfoKHR* unmapInfo);

	/** Returns whether this device memory is currently mapped to host memory. */
	bool isMapped() { return _map; }

	/** If this memory is host-visible, the specified memory range is flushed to the device. */
	VkResult flushToDevice(VkDeviceSize offset, VkDeviceSize size);

	/**
	 * If this memory is host-visible, pulls the specified memory range from the device.
	 *
	 * If pBlitEnc is not null, it points to a holder for a MTLBlitCommandEncoder and its
	 * associated MTLCommandBuffer. If this instance has a MTLBuffer using managed memory,
	 * this function may call synchronizeResource: on the MTLBlitCommandEncoder to
	 * synchronize the GPU contents to the CPU. If the contents of the pBlitEnc do not
	 * include a MTLBlitCommandEncoder and MTLCommandBuffer, this function will create
	 * them and populate the contents into the MVKMTLBlitEncoder struct.
	 */
	VkResult pullFromDevice(VkDeviceSize offset,
							VkDeviceSize size,
							MVKMTLBlitEncoder* pBlitEnc = nullptr);


#pragma mark Metal

	/** Returns the Metal buffer underlying this memory allocation. */
	inline id<MTLBuffer> getMTLBuffer() { return _mtlBuffer; }

	/** Returns the Metal heap underlying this memory allocation. */
	inline id<MTLHeap> getMTLHeap() { return _mtlHeap; }

	/** Returns the Metal storage mode used by this memory allocation. */
	inline MTLStorageMode getMTLStorageMode() { return mvkMTLStorageMode(_options); }

	/** Returns the Metal CPU cache mode used by this memory allocation. */
	inline MTLCPUCacheMode getMTLCPUCacheMode() { return mvkMTLCPUCacheMode(_options); }

	/** Returns the Metal resource options used by this memory allocation. */
	inline MTLResourceOptions getMTLResourceOptions() { return _options; }


#pragma mark Construction

	/** Constructs an instance for the specified device. */
	MVKDeviceMemory(MVKDevice* device,
					const VkMemoryAllocateInfo* pAllocateInfo,
					const VkAllocationCallbacks* pAllocator);

	~MVKDeviceMemory() override;

protected:
	friend class MVKBuffer;
	friend class MVKImageMemoryBinding;
	friend class MVKImagePlane;

	void propagateDebugName() override;
	VkDeviceSize adjustMemorySize(VkDeviceSize size, VkDeviceSize offset);
	void checkExternalMemoryRequirements(VkExternalMemoryHandleTypeFlags handleTypes);

	// Backing memory of VkDeviceMemory. This will not be allocated if memory was imported.
	// Imported memory will directly be backed by MTLBuffer/MTLTexture since there's no way
	// to create a MTLHeap with existing memory in Metal for now.
	id<MTLHeap> _mtlHeap = nil;

	// This MTLBuffer can have 3 usages:
	// 1. When a heap is allocated, the buffer will extend the whole heap to be able to map and flush memory.
	// 2. When there's no heap, the buffer will be the backing memory of VkDeviceMemory.
	// 3. When a texture is imported, the GPU memory will be held by MTLTexture. However, if said texture is
	// host accessible, we need to provide some memory for the mapping since Metal provides nothing. In this
	// case, the buffer will hold the host memory that will later be copied to the texture once flushed.
	id<MTLBuffer> _mtlBuffer = nil;

	// If the user is importing a texture that is not backed by MTLHeap nor MTLBuffer, Metal does not expose
	// anything to be able to access the texture data such as MTLBuffer::contents. This leads us to having to
	// use the MTLTexture as the main GPU resource for the memory. If the texture is also host accessible,
	// a buffer with host visible memory will be allocated as pointed out in point 3 before.
	id<MTLTexture> _mtlTexture = nil;

	// Mapped memory.
	void* _map = nullptr;
	MVKMemoryRange _mapRange = { 0u, 0u };

	// Allocation size.
	VkDeviceSize _size = 0u;
	// Metal resource options.
	MTLResourceOptions _options = 0u;

	// When the allocation is dedicated, it will belong to one specific resource.
	union {
		MVKBuffer* _dedicatedBufferOwner = nullptr;
		MVKImage* _dedicatedImageOwner;
	};
	enum class DedicatedResourceType : uint8_t {
		NONE = 0,
		BUFFER,
		IMAGE
	};
	DedicatedResourceType _dedicatedResourceType = DedicatedResourceType::NONE;

	VkMemoryPropertyFlags _vkMemPropFlags;

	// Tracks if we need to flush from MTLBuffer to MTLTexture. Used only when memory is an imported texture
	// that had no backing MTLBuffer nor MTLHeap
	bool _requiresFlushingBufferToTexture = false;
};

