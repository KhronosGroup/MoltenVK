/*
 * MVKMTLBufferAllocation.h
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


#include "MVKFoundation.h"
#include "MVKObjectPool.h"
#include "MVKDevice.h"
#include "MVKSmallVector.h"

class MVKMTLBufferAllocationPool;


#pragma mark -
#pragma mark MVKMTLBufferAllocation

/** Defines a contiguous region of bytes within a MTLBuffer. */
class MVKMTLBufferAllocation : public MVKBaseObject, public MVKLinkableMixin<MVKMTLBufferAllocation> {

public:
    id<MTLBuffer> _mtlBuffer;
    NSUInteger _offset;
    NSUInteger _length;

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

    /**
     * Returns a pointer to the begining of this allocation memory, taking into
     * consideration this allocation's offset into the underlying MTLBuffer.
     */
    inline void* getContents() const { return (void*)((uintptr_t)_mtlBuffer.contents + _offset); }

    /** Returns the pool whence this object was created. */
    MVKMTLBufferAllocationPool* getPool() const { return _pool; }

	/** Returns this object back to the pool that created it. */
    void returnToPool();

	/** Constructs this instance with the specified pool as its origin. */
    MVKMTLBufferAllocation(MVKMTLBufferAllocationPool* pool,
                           id<MTLBuffer> mtlBuffer,
                           NSUInteger offset,
                           NSUInteger length) : _pool(pool), _mtlBuffer(mtlBuffer), _offset(offset), _length(length) {}

protected:
	MVKMTLBufferAllocationPool* _pool;

};


#pragma mark -
#pragma mark MVKMTLBufferAllocationPool

/** 
 * A pool of MVKMTLBufferAllocation instances of a single size. All MVKMTLBufferAllocation 
 * instances will have the same size, as defined when this pool is created.
 *
 * To return a MVKMTLBufferAllocation retrieved from this pool, back to this pool, 
 * call the returnToPool() function on the MVKMTLBufferAllocation instance.
 */
class MVKMTLBufferAllocationPool : public MVKObjectPool<MVKMTLBufferAllocation> {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _device->getVulkanAPIObject(); };

    /** Returns a new MVKMTLBufferAllocation instance. */
    MVKMTLBufferAllocation* newObject() override;

    /** Configures this instance to dispense MVKMTLBufferAllocation instances of the specified size. */
    MVKMTLBufferAllocationPool(MVKDevice* device, NSUInteger allocationLength, MTLStorageMode mtlStorageMode, bool isDedicated);

    ~MVKMTLBufferAllocationPool() override;

protected:
    uint32_t calcMTLBufferAllocationCount();
    void addMTLBuffer();

    NSUInteger _nextOffset;
    NSUInteger _allocationLength;
    NSUInteger _mtlBufferLength;
    MTLStorageMode _mtlStorageMode;
	MVKSmallVector<id<MTLBuffer>, 64> _mtlBuffers;
    MVKDevice* _device;
};


#pragma mark -
#pragma mark MVKMTLBufferAllocator

/**
 * A pool of MVKMTLBufferAllocation instances of any size. When requesting a MVKMTLBufferAllocation
 * from this pool, the caller can request a specific size. The MVKMTLBufferAllocation instance
 * returned from such a call will have a size that is the next power-of-two value that is
 * at least as big as the requested size.
 *
 * To return a MVKMTLBufferAllocation retrieved from this pool, back to this pool,
 * call the returnToPool() function on the MVKMTLBufferAllocation instance.
 */
class MVKMTLBufferAllocator : public MVKBaseDeviceObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _device->getVulkanAPIObject(); };

    /** 
     * Returns a MVKMTLBufferAllocation instance with a size that is the next 
     * power-of-two value that is at least as big as the requested size.
     *
     * To return the MVKMTLBufferAllocation back to the pool, call 
     * the returnToPool() function on the returned instance.
     */
    const MVKMTLBufferAllocation* acquireMTLBufferRegion(NSUInteger length);

    /**
     * Configures this instance to dispense MVKMTLBufferAllocation up to the specified
     * maximum size. Because MVKMTLBufferRegions are created with a power-of-two size,
     * the largest size of a MVKMTLBufferAllocation dispensed by this instance will be the
     * next power-of-two value that is at least as big as the specified maximum size.
	 * If makeThreadSafe is true, a lock will be applied when an allocation is acquired.
     */
    MVKMTLBufferAllocator(MVKDevice* device, NSUInteger maxRegionLength, bool makeThreadSafe = false, bool isDedicated = false, MTLStorageMode mtlStorageMode = MTLStorageModeShared);

    ~MVKMTLBufferAllocator() override;

protected:
	MVKSmallVector<MVKMTLBufferAllocationPool*, 32> _regionPools;
    NSUInteger _maxAllocationLength;
	bool _makeThreadSafe;

};

