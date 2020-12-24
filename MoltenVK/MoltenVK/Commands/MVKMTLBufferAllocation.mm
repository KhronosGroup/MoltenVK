/*
 * MVKMTLBufferAllocation.mm
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKMTLBufferAllocation.h"
#include "MVKLogging.h"
#include <algorithm>


#pragma mark -
#pragma mark MVKMTLBufferAllocation

MVKVulkanAPIObject* MVKMTLBufferAllocation::getVulkanAPIObject() { return _pool->getVulkanAPIObject(); };

void MVKMTLBufferAllocation::returnToPool() { _pool->returnObjectSafely(this); }


#pragma mark -
#pragma mark MVKMTLBufferAllocationPool

MVKMTLBufferAllocation* MVKMTLBufferAllocationPool::newObject() {
    // If we're at the end of the current MTLBuffer, add a new one.
    if (_nextOffset >= _mtlBufferLength) { addMTLBuffer(); }

    // Extract and return the next allocation from the current buffer,
    // which is always the last one in the array, and advance the offset
    // of future allocation to beyond this allocation.
    NSUInteger offset = _nextOffset;
    _nextOffset += _allocationLength;
    return new MVKMTLBufferAllocation(this, _mtlBuffers.back(), offset, _allocationLength);
}

// Adds a new MTLBuffer to the buffer pool and resets the next offset to the start of it
void MVKMTLBufferAllocationPool::addMTLBuffer() {
    MTLResourceOptions mbOpts = MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache;
    _mtlBuffers.push_back([_device->getMTLDevice() newBufferWithLength: _mtlBufferLength options: mbOpts]);
    _nextOffset = 0;
}


MVKMTLBufferAllocationPool::MVKMTLBufferAllocationPool(MVKDevice* device, NSUInteger allocationLength)
        : MVKObjectPool<MVKMTLBufferAllocation>(true) {
    _device = device;
    _allocationLength = allocationLength;
    _mtlBufferLength = _allocationLength * calcMTLBufferAllocationCount();
    _nextOffset = _mtlBufferLength;     // Force a MTLBuffer to be added on first access
}

// Returns the number of regions to allocate per MTLBuffer, as determined from the allocation size.
uint32_t MVKMTLBufferAllocationPool::calcMTLBufferAllocationCount() {
    if (_allocationLength <= 256 ) { return 256; }
    if (_allocationLength <= (1 * KIBI) ) { return 128; }
    if (_allocationLength <= (4 * KIBI) ) { return 64; }
    if (_allocationLength <= (256 * KIBI) ) { return (512 * KIBI) / _allocationLength; }

    return 1;
}

MVKMTLBufferAllocationPool::~MVKMTLBufferAllocationPool() {
    mvkReleaseContainerContents(_mtlBuffers);
}


#pragma mark -
#pragma mark MVKMTLBufferAllocator

const MVKMTLBufferAllocation* MVKMTLBufferAllocator::acquireMTLBufferRegion(NSUInteger length) {
	MVKAssert(length <= _maxAllocationLength, "This MVKMTLBufferAllocator has been configured to dispense MVKMTLBufferRegions no larger than %lu bytes.", (unsigned long)_maxAllocationLength);

	// Can't allocate a segment smaller than the minimum MTLBuffer alignment.
	length = std::max<NSUInteger>(length, _device->_pMetalFeatures->mtlBufferAlignment);

    // Convert max length to the next power-of-two exponent to use as a lookup
    NSUInteger p2Exp = mvkPowerOfTwoExponent(length);
	MVKMTLBufferAllocationPool* pRP = _regionPools[p2Exp];
	return _makeThreadSafe ? pRP->acquireObjectSafely() : pRP->acquireObject();
}

MVKMTLBufferAllocator::MVKMTLBufferAllocator(MVKDevice* device, NSUInteger maxRegionLength, bool makeThreadSafe) : MVKBaseDeviceObject(device) {
	_maxAllocationLength = std::max<NSUInteger>(maxRegionLength, _device->_pMetalFeatures->mtlBufferAlignment);
	_makeThreadSafe = makeThreadSafe;

    // Convert max length to the next power-of-two exponent
    NSUInteger maxP2Exp = mvkPowerOfTwoExponent(_maxAllocationLength);

    // Populate the array of region pools to cover the maximum region size
    _regionPools.reserve(maxP2Exp + 1);
    NSUInteger allocLen = 1;
    for (uint32_t p2Exp = 0; p2Exp <= maxP2Exp; p2Exp++) {
        _regionPools.push_back(new MVKMTLBufferAllocationPool(device, allocLen));
        allocLen <<= 1;
    }
}

MVKMTLBufferAllocator::~MVKMTLBufferAllocator() {
    mvkDestroyContainerContents(_regionPools);
}

