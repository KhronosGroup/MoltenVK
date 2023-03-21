/*
 * MVKDeviceMemory.h
 *
 * Copyright (c) 2015-2023 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

typedef struct MVKMappedMemoryRange {
	VkDeviceSize offset = 0;
	VkDeviceSize size = 0;
} MVKMappedMemoryRange;


/** Represents a Vulkan device-space memory allocation. */
class MVKDeviceMemory : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DEVICE_MEMORY; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DEVICE_MEMORY_EXT; }

	/** Returns whether the memory is accessible from the host. */
    inline bool isMemoryHostAccessible() {
#if MVK_APPLE_SILICON
        if (_mtlStorageMode == MTLStorageModeMemoryless)
            return false;
#endif
        return (_mtlStorageMode != MTLStorageModePrivate);
    }

	/** Returns whether the memory is automatically coherent between device and host. */
    inline bool isMemoryHostCoherent() { return (_mtlStorageMode == MTLStorageModeShared); }

    /** Returns whether this is a dedicated allocation. */
    inline bool isDedicatedAllocation() { return _isDedicated; }

    /** Returns the memory already committed by this instance. */
    inline VkDeviceSize getDeviceMemoryCommitment() { return _allocationSize; }

	/**
	 * Returns the host memory address of this memory, or NULL if the memory
	 * is marked as device-only and cannot be mapped to a host address.
	 */
	inline void* getHostMemoryAddress() { return _pMemory; }

	/**
	 * Maps the memory address at the specified offset from the start of this memory allocation,
	 * and returns the address in the specified data reference.
	 */
	VkResult map(VkDeviceSize offset, VkDeviceSize size, VkMemoryMapFlags flags, void** ppData);

	/** Unmaps a previously mapped memory range. */
	void unmap();

	/**
	 * If this device memory is currently mapped to host memory, returns the range within
	 * this device memory that is currently mapped to host memory, or returns {0,0} if
	 * this device memory is not currently mapped to host memory.
	 */
	inline const MVKMappedMemoryRange& getMappedRange() { return _mappedRange; }

	/** Returns whether this device memory is currently mapped to host memory. */
	bool isMapped() { return _mappedRange.size > 0; }

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
	inline MTLStorageMode getMTLStorageMode() { return _mtlStorageMode; }

	/** Returns the Metal CPU cache mode used by this memory allocation. */
	inline MTLCPUCacheMode getMTLCPUCacheMode() { return _mtlCPUCacheMode; }

	/** Returns the Metal resource options used by this memory allocation. */
	inline MTLResourceOptions getMTLResourceOptions() { return mvkMTLResourceOptions(_mtlStorageMode, _mtlCPUCacheMode); }


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
	VkResult addBuffer(MVKBuffer* mvkBuff);
	void removeBuffer(MVKBuffer* mvkBuff);
	VkResult addImageMemoryBinding(MVKImageMemoryBinding* mvkImg);
	void removeImageMemoryBinding(MVKImageMemoryBinding* mvkImg);
	bool ensureMTLHeap();
	bool ensureMTLBuffer();
	bool ensureHostMemory();
	void freeHostMemory();
	MVKResource* getDedicatedResource();
	void initExternalMemory(VkExternalMemoryHandleTypeFlags handleTypes);

	MVKSmallVector<MVKBuffer*, 4> _buffers;
	MVKSmallVector<MVKImageMemoryBinding*, 4> _imageMemoryBindings;
	std::mutex _rezLock;
    VkDeviceSize _allocationSize = 0;
	MVKMappedMemoryRange _mappedRange;
	id<MTLBuffer> _mtlBuffer = nil;
	id<MTLHeap> _mtlHeap = nil;
	void* _pMemory = nullptr;
	void* _pHostMemory = nullptr;
	VkMemoryPropertyFlags _vkMemPropFlags;
	VkMemoryAllocateFlags _vkMemAllocFlags;
	MTLStorageMode _mtlStorageMode;
	MTLCPUCacheMode _mtlCPUCacheMode;
	bool _isDedicated = false;
	bool _isHostMemImported = false;

};

