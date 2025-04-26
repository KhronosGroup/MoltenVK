/*
 * MVKMTLBufferAllocation.mm
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

#include "MVKMTLBufferAllocation.h"


#pragma mark -
#pragma mark MVKMTLBufferAllocation

MVKVulkanAPIObject* MVKMTLBufferAllocation::getVulkanAPIObject() { return _pool->getVulkanAPIObject(); };

void MVKMTLBufferAllocation::returnToPool() { _pool->returnAllocation(this); }


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
    return new MVKMTLBufferAllocation(this, _mtlBuffers.back().mtlBuffer, offset, _allocationLength, _mtlBuffers.size() - 1);
}

// Adds a new MTLBuffer to the buffer pool and resets the next offset to the start of it
void MVKMTLBufferAllocationPool::addMTLBuffer() {
    MTLResourceOptions mbOpts = (_mtlStorageMode << MTLResourceStorageModeShift) | MTLResourceCPUCacheModeDefaultCache;
    _mtlBuffers.push_back({ [getMTLDevice() newBufferWithLength: _mtlBufferLength options: mbOpts], 0 });
	getDevice()->makeResident(_mtlBuffers.back().mtlBuffer);
    _nextOffset = 0;
}

MVKMTLBufferAllocation* MVKMTLBufferAllocationPool::acquireAllocationUnlocked() {
    MVKMTLBufferAllocation* ba = acquireObject();
    if (!_mtlBuffers[ba->_poolIndex].allocationCount++) {
        [ba->_mtlBuffer setPurgeableState: MTLPurgeableStateNonVolatile];
    }
    return ba;
}

MVKMTLBufferAllocation* MVKMTLBufferAllocationPool::acquireAllocation() {
    if (_isThreadSafe) {
        std::lock_guard<std::mutex> lock(_lock);
        return acquireAllocationUnlocked();
    } else {
        return acquireAllocationUnlocked();
    }
}

void MVKMTLBufferAllocationPool::returnAllocationUnlocked(MVKMTLBufferAllocation* ba) {
    if (!--_mtlBuffers[ba->_poolIndex].allocationCount) {
        [ba->_mtlBuffer setPurgeableState: MTLPurgeableStateVolatile];
    }
    returnObject(ba);
}

void MVKMTLBufferAllocationPool::returnAllocation(MVKMTLBufferAllocation* ba) {
    if (_isThreadSafe) {
        std::lock_guard<std::mutex> lock(_lock);
        returnAllocationUnlocked(ba);
    } else {
        returnAllocationUnlocked(ba);
    }
}

MVKMTLBufferAllocationPool::MVKMTLBufferAllocationPool(MVKDevice* device, NSUInteger allocationLength, bool makeThreadSafe,
													   bool isDedicated, MTLStorageMode mtlStorageMode) :
	MVKObjectPool<MVKMTLBufferAllocation>(true),
	MVKDeviceTrackingMixin(device) {

    _allocationLength = allocationLength;
	_isThreadSafe = makeThreadSafe;
    _mtlBufferLength = _allocationLength * (isDedicated ? 1 : calcMTLBufferAllocationCount());
    _mtlStorageMode = mtlStorageMode;
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
    for (uint32_t bufferIndex = 0; bufferIndex < _mtlBuffers.size(); ++bufferIndex) {
		getDevice()->removeResidency(_mtlBuffers[bufferIndex].mtlBuffer);
        [_mtlBuffers[bufferIndex].mtlBuffer release];
    }
    _mtlBuffers.clear();
}


#pragma mark -
#pragma mark MVKMTLBufferAllocator

MVKMTLBufferAllocation* MVKMTLBufferAllocator::acquireMTLBufferRegion(NSUInteger length) {
	MVKAssert(length <= _maxAllocationLength, "This MVKMTLBufferAllocator has been configured to dispense MVKMTLBufferRegions no larger than %lu bytes.", (unsigned long)_maxAllocationLength);

	// Can't allocate a segment smaller than the minimum MTLBuffer alignment.
	length = std::max<NSUInteger>(length, getMetalFeatures().mtlBufferAlignment);

    // Convert max length to the next power-of-two exponent to use as a lookup
    NSUInteger p2Exp = mvkPowerOfTwoExponent(length);
    return _regionPools[p2Exp]->acquireAllocation();
}

MVKMTLBufferAllocator::MVKMTLBufferAllocator(MVKDevice* device, NSUInteger maxRegionLength, bool makeThreadSafe, bool isDedicated, MTLStorageMode mtlStorageMode) : MVKBaseDeviceObject(device) {
	_maxAllocationLength = std::max<NSUInteger>(maxRegionLength, getMetalFeatures().mtlBufferAlignment);
	_isThreadSafe = makeThreadSafe;

    // Convert max length to the next power-of-two exponent
    NSUInteger maxP2Exp = mvkPowerOfTwoExponent(_maxAllocationLength);

    // Populate the array of region pools to cover the maximum region size
    _regionPools.reserve(maxP2Exp + 1);
    NSUInteger allocLen = 1;
    for (uint32_t p2Exp = 0; p2Exp <= maxP2Exp; p2Exp++) {
        _regionPools.push_back(new MVKMTLBufferAllocationPool(device, allocLen, makeThreadSafe, isDedicated, mtlStorageMode));
        allocLen <<= 1;
    }
}

MVKMTLBufferAllocator::~MVKMTLBufferAllocator() {
    mvkDestroyContainerContents(_regionPools);
}

