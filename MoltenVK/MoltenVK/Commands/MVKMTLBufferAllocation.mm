/*
 * MVKMTLBufferAllocation.mm
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include <limits>


#pragma mark -
#pragma mark MVKMTLBufferAllocation

MVKVulkanAPIObject* MVKMTLBufferAllocation::getVulkanAPIObject() { return _pool->getVulkanAPIObject(); };

void MVKMTLBufferAllocation::returnToPool() { _pool->returnAllocation(this); }


#pragma mark -
#pragma mark MVKMTLBufferAllocationPool

// Allocate a new MTLBuffer page in the lowest available slot or append a new page slot
size_t MVKMTLBufferAllocationPool::allocatePage() {
    size_t targetIdx = _mtlBuffers.size();
    for (size_t i = 0; i < _mtlBuffers.size(); ++i) {
        if (_mtlBuffers[i].mtlBuffer == nil) {
            targetIdx = i;
            break;
        }
    }
    if (targetIdx == _mtlBuffers.size()) {
        _mtlBuffers.emplace_back();
    }

    MTLResourceOptions mbOpts = (_mtlStorageMode << MTLResourceStorageModeShift)
                              | MTLResourceCPUCacheModeDefaultCache;
    id<MTLBuffer> newBuffer = [getMTLDevice() newBufferWithLength: _mtlBufferLength
                                                          options: mbOpts];
    MVKAssert(newBuffer, "Could not allocate MTLBuffer of length %lu", (unsigned long)_mtlBufferLength);
    if (!newBuffer) { return _mtlBuffers.size(); }

    getDevice()->makeResident(newBuffer);

    auto& page = _mtlBuffers[targetIdx];
    page.mtlBuffer = newBuffer;
    page.totalSlots = (uint32_t)(_mtlBufferLength / _allocationLength);
    page.activeCount = 0;
    page.nextUnallocatedSlot = 0;
    page.isVolatile = false;
    page.freeSlices.clear();

    return targetIdx;
}

// Pop an allocation slice from the specified page
MVKMTLBufferAllocation* MVKMTLBufferAllocationPool::popSliceFromPage(size_t pageIndex) {
    auto& page = _mtlBuffers[pageIndex];
    MVKMTLBufferAllocation* ba = nullptr;
    if (!page.freeSlices.empty()) {
        ba = page.freeSlices.back();
        page.freeSlices.pop_back();
        ba->_mtlBuffer = page.mtlBuffer;
    } else if (page.nextUnallocatedSlot < page.totalSlots) {
        uint32_t slot = page.nextUnallocatedSlot++;
        NSUInteger offset = (NSUInteger)slot * _allocationLength;
        if (!_freeAllocationHandles.empty()) {
            ba = _freeAllocationHandles.back();
            _freeAllocationHandles.pop_back();
            ba->_mtlBuffer = page.mtlBuffer;
            ba->_offset = offset;
            ba->_length = _allocationLength;
            ba->_pool = this;
            ba->_poolIndex = pageIndex;
        } else {
            ba = new MVKMTLBufferAllocation(this, page.mtlBuffer, offset, _allocationLength, pageIndex);
        }
    } else {
        return nullptr;
    }

    if (!page.activeCount++) {
        if (page.isVolatile) {
            if ([page.mtlBuffer setPurgeableState: MTLPurgeableStateNonVolatile] == MTLPurgeableStateEmpty) {
                getDevice()->removeResidency(page.mtlBuffer);
                [page.mtlBuffer release];
                MTLResourceOptions mbOpts = (_mtlStorageMode << MTLResourceStorageModeShift)
                                          | MTLResourceCPUCacheModeDefaultCache;
                page.mtlBuffer = [getMTLDevice() newBufferWithLength: _mtlBufferLength options: mbOpts];
                if (!page.mtlBuffer) {
                    page.activeCount = 0;
                    page.totalSlots = 0;
                    page.nextUnallocatedSlot = 0;
                    page.isVolatile = false;
                    for (auto* slice : page.freeSlices) {
                        slice->_mtlBuffer = nil;
                        slice->_poolIndex = std::numeric_limits<uint64_t>::max();
                        _freeAllocationHandles.push_back(slice);
                    }
                    page.freeSlices.clear();
                    ba->_mtlBuffer = nil;
                    ba->_poolIndex = std::numeric_limits<uint64_t>::max();
                    _freeAllocationHandles.push_back(ba);
                    return nullptr;
                }
                getDevice()->makeResident(page.mtlBuffer);
                ba->_mtlBuffer = page.mtlBuffer;
                for (auto* slice : page.freeSlices) {
                    slice->_mtlBuffer = page.mtlBuffer;
                }
            }
            page.isVolatile = false;
        }
    }
    return ba;
}

MVKMTLBufferAllocation* MVKMTLBufferAllocationPool::acquireAllocationUnlocked() {
    // Lowest-Index First (Bin-Packing): always pack allocations into the lowest-index active page
    for (size_t i = 0; i < _mtlBuffers.size(); ++i) {
        if (_mtlBuffers[i].mtlBuffer != nil && _mtlBuffers[i].activeCount < _mtlBuffers[i].totalSlots) {
            MVKMTLBufferAllocation* ba = popSliceFromPage(i);
            if (ba) { return ba; }
        }
    }

    // No existing page has room; allocate a new page
    size_t newPageIdx = allocatePage();
    if (newPageIdx < _mtlBuffers.size()) {
        return popSliceFromPage(newPageIdx);
    }

    return nullptr;
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
    if (ba->_poolIndex < _mtlBuffers.size()) {
        auto& page = _mtlBuffers[ba->_poolIndex];
        if (page.activeCount > 0) {
            if (!--page.activeCount) {
                if (page.mtlBuffer != nil) {
                    [page.mtlBuffer setPurgeableState: MTLPurgeableStateVolatile];
                    page.isVolatile = true;
                }
                _dirtyFlag = true;
            }
            page.freeSlices.push_back(ba);
            return;
        }
    }

    // Backing page was trimmed or released
    ba->_mtlBuffer = nil;
    ba->_poolIndex = std::numeric_limits<uint64_t>::max();
    _freeAllocationHandles.push_back(ba);
}

void MVKMTLBufferAllocationPool::returnAllocation(MVKMTLBufferAllocation* ba) {
    if (_isThreadSafe) {
        std::lock_guard<std::mutex> lock(_lock);
        returnAllocationUnlocked(ba);
    } else {
        returnAllocationUnlocked(ba);
    }
}

void MVKMTLBufferAllocationPool::returnAllocationsUnlocked(MVKMTLBufferAllocation** allocations, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        returnAllocationUnlocked(allocations[i]);
    }
}

void MVKMTLBufferAllocationPool::returnAllocations(MVKMTLBufferAllocation** allocations, size_t count) {
    if (count == 0) return;
    if (_isThreadSafe) {
        std::lock_guard<std::mutex> lock(_lock);
        returnAllocationsUnlocked(allocations, count);
    } else {
        returnAllocationsUnlocked(allocations, count);
    }
}

MVKMTLBufferAllocationPool::MVKMTLBufferAllocationPool(MVKDevice* device, NSUInteger allocationLength, bool makeThreadSafe,
													   bool isDedicated, MTLStorageMode mtlStorageMode) :
	MVKBaseDeviceObject(device),
	_allocationLength(allocationLength),
	_mtlStorageMode(mtlStorageMode),
	_isThreadSafe(makeThreadSafe) {

    _mtlBufferLength = _allocationLength * (isDedicated ? 1 : calcMTLBufferAllocationCount());
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
    MVKSmallVector<id<MTLBuffer>, 16> bufsToRemove;
    for (auto& page : _mtlBuffers) {
        if (page.mtlBuffer) {
            bufsToRemove.push_back(page.mtlBuffer);
        }
        for (auto* ba : page.freeSlices) {
            delete ba;
        }
        page.freeSlices.clear();
    }
    _mtlBuffers.clear();

    if (!bufsToRemove.empty()) {
        getDevice()->removeResidencies(bufsToRemove.data(), bufsToRemove.size());
        for (id<MTLBuffer> buf : bufsToRemove) {
            [buf release];
        }
    }

    for (auto* ba : _freeAllocationHandles) {
        delete ba;
    }
    _freeAllocationHandles.clear();
}

void MVKMTLBufferAllocationPool::trimUnlocked() {
    if (_mtlBuffers.empty() || !_dirtyFlag) return;

    MVKSmallVector<id<MTLBuffer>, 16> buffersToRemoveResidency;
    for (size_t i = 0; i < _mtlBuffers.size(); ++i) {
        auto& page = _mtlBuffers[i];
        if (page.mtlBuffer == nil) continue;
        if (page.activeCount > 0) continue;

        // Reclaim all free slices of this page back to handle cache
        for (auto* ba : page.freeSlices) {
            ba->_mtlBuffer = nil;
            ba->_poolIndex = std::numeric_limits<uint64_t>::max();
            _freeAllocationHandles.push_back(ba);
        }
        page.freeSlices.clear();

        buffersToRemoveResidency.push_back(page.mtlBuffer);
        page.mtlBuffer = nil;
        page.totalSlots = 0;
        page.nextUnallocatedSlot = 0;
        page.isVolatile = false;
    }

    if (!buffersToRemoveResidency.empty()) {
        getDevice()->removeResidencies(buffersToRemoveResidency.data(), buffersToRemoveResidency.size());
        for (id<MTLBuffer> buf : buffersToRemoveResidency) {
            [buf release];
        }
    }

    // Shrink excess free handles
    uint32_t maxCachedHandles = 2 * (uint32_t)(_mtlBufferLength / _allocationLength);
    while (_freeAllocationHandles.size() > maxCachedHandles) {
        delete _freeAllocationHandles.back();
        _freeAllocationHandles.pop_back();
    }

    while (!_mtlBuffers.empty() && _mtlBuffers.back().mtlBuffer == nil) {
        _mtlBuffers.pop_back();
    }

    _dirtyFlag = false;
}

void MVKMTLBufferAllocationPool::trim() {
    if (_isThreadSafe) {
        std::lock_guard<std::mutex> lock(_lock);
        trimUnlocked();
    } else {
        trimUnlocked();
    }
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

void MVKMTLBufferAllocator::trim() {
    for (auto* pool : _regionPools) {
        pool->trim();
    }
}

