/*
 * MVKDeviceMemory.h
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
#include <vector>

#import <Metal/Metal.h>

class MVKBuffer;
class MVKImage;


#pragma mark MVKDeviceMemory

/** Represents a Vulkan device-space memory allocation. */
class MVKDeviceMemory : public MVKBaseDeviceObject {

public:

	/** Returns whether the memory is accessible from the host. */
    inline bool isMemoryHostAccessible() {
#if MVK_IOS
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
	 * If this memory is host-visible, the specified memory range is flushed to the device.
	 * Normally, flushing will only occur if the device memory is non-coherent, but flushing
	 * to coherent memory can be forced by setting evenIfCoherent to true.
	 */
	VkResult flushToDevice(VkDeviceSize offset, VkDeviceSize size, bool evenIfCoherent = false);

	/**
	 * If this memory is host-visible, pulls the specified memory range from the device.
	 * Normally, pulling will only occur if the device memory is non-coherent, but pulling
	 * to coherent memory can be forced by setting evenIfCoherent to true.
	 */
	VkResult pullFromDevice(VkDeviceSize offset, VkDeviceSize size, bool evenIfCoherent = false);


#pragma mark Metal

	/** Returns the Metal buffer underlying this memory allocation. */
	inline id<MTLBuffer> getMTLBuffer() { return _mtlBuffer; }

	/** Returns the Metal storage mode used by this memory allocation. */
	inline MTLStorageMode getMTLStorageMode() { return _mtlStorageMode; }

	/** Returns the Metal CPU cache mode used by this memory allocation. */
	inline MTLCPUCacheMode getMTLCPUCacheMode() { return _mtlCPUCacheMode; }

	/** Returns the Metal reource options used by this memory allocation. */
	inline MTLResourceOptions getMTLResourceOptions() { return _mtlResourceOptions; }


#pragma mark Construction

	/** Constructs an instance for the specified device. */
	MVKDeviceMemory(MVKDevice* device,
					const VkMemoryAllocateInfo* pAllocateInfo,
					const VkAllocationCallbacks* pAllocator);

    ~MVKDeviceMemory() override;

protected:
	friend MVKBuffer;
	friend MVKImage;

	VkDeviceSize adjustMemorySize(VkDeviceSize size, VkDeviceSize offset);
	VkResult addBuffer(MVKBuffer* mvkBuff);
	void removeBuffer(MVKBuffer* mvkBuff);
	VkResult addImage(MVKImage* mvkImg);
	void removeImage(MVKImage* mvkImg);
	bool ensureMTLBuffer();
	bool ensureHostMemory();
	void freeHostMemory();
	MVKResource* getDedicatedResource();

	std::vector<MVKBuffer*> _buffers;
	std::vector<MVKImage*> _images;
	std::mutex _rezLock;
    VkDeviceSize _allocationSize = 0;
	VkDeviceSize _mapOffset = 0;
	VkDeviceSize _mapSize = 0;
	id<MTLBuffer> _mtlBuffer = nil;
	void* _pMemory = nullptr;
	void* _pHostMemory = nullptr;
	bool _isMapped = false;
	bool _isDedicated = false;
	MTLResourceOptions _mtlResourceOptions;
	MTLStorageMode _mtlStorageMode;
	MTLCPUCacheMode _mtlCPUCacheMode;
};

