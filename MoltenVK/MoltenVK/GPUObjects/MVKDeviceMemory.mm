/*
 * MVKDeviceMemory.mm
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

#include "MVKDeviceMemory.h"
#include "MVKImage.h"
#include "mvk_datatypes.h"
#include "MVKFoundation.h"
#include <cstdlib>
#include <stdlib.h>

using namespace std;

#pragma mark MVKDeviceMemory

// Metal does not support the concept of mappable device memory separate from individual
// resources. There are a number of potentially conflicting requirements defined by Vulkan
// that make it a challenge to map device memory to Metal resources.
// 1) Memory can be mapped and populated prior to any resources being bound.
// 2) Coherent memory can be mapped forever and simply overwritten without regard for
//    requiring host generated update indications.
// 3) MTLTextures are never natively coherent.
// 4) MTLBuffers are restricted to smaller sizes (eg. 256MB - 1GB) than MTLTextures.
//
// To try to deal with all of this...
// 1) If the mapped range falls within a single resource, we map it directly. This allows
//    us to maximize the size of the resources (images and buffers can be larger)...and
//    coherent buffers can be mapped directly.
// 2) If we can't map to a single resource, and memory must be coherent, allocate a single
//    coherent MTLBuffer for the entire memory range. If any attached resources already have
//    content, the subsequent coherent pullFromDevice() will populate the larger MTLBuffer.
// 3) If we can't map to a single resource, and memory is not coherent, we can allocate the
//    host portion as an aligned malloc, and the individual resources will copy to and from it.
// 4) There is no way around requiring coherent memory that is used for image to be updated
//    by the host, or at least unmapped, so that we have a signal to update MTLTexture content.
VkResult MVKDeviceMemory::map(VkDeviceSize offset, VkDeviceSize size, VkMemoryMapFlags flags, void** ppData) {

    if ( !isMemoryHostAccessible() ) {
        return mvkNotifyErrorWithText(VK_ERROR_MEMORY_MAP_FAILED, "Private GPU-only memory cannot be mapped to host memory.");
    }

    if (_pMappedMemory) {
        return mvkNotifyErrorWithText(VK_ERROR_MEMORY_MAP_FAILED, "Memory is already mapped. Call vkUnmapMemory() first.");
    }

    VkDeviceSize mapSize = adjustMemorySize(size, offset);
//    MVKLogDebug("Mapping device memory %p with offset %d and size %d.", this, offset, mapSize);
    if ( !mapToUniqueResource(offset, mapSize) ) {
        if (isMemoryHostCoherent()) {
            if ( !_mtlBuffer ) {

				// Lock and check again in case another thread has created the buffer.
				lock_guard<mutex> lock(_lock);
				if ( !_mtlBuffer ) {
					NSUInteger mtlBuffLen = mvkAlignByteOffset(_allocationSize, _device->_pMetalFeatures->mtlBufferAlignment);
					_mtlBuffer = [getMTLDevice() newBufferWithLength: mtlBuffLen options: _mtlResourceOptions];     // retained
//                	MVKLogDebug("Allocating host mapped memory %p with offset %d and size %d via underlying coherent MTLBuffer %p of size %d.", this, offset, mapSize, _mtlBuffer , _mtlBuffer.length);
				}
			}
            _pLogicalMappedMemory = _mtlBuffer.contents;
            _pMappedMemory = (void*)((uintptr_t)_pLogicalMappedMemory + offset);
        } else {
//            MVKLogDebug("Allocating host mapped memory %p with offset %d and size %d via host allocation.", this, offset, mapSize);
            _pMappedMemory = allocateMappedMemory(offset, mapSize);
        }
    }

    *ppData = _pMappedMemory;
    _mapOffset = offset;
    _mapSize = mapSize;

	// Coherent memory does not require flushing by app, so we must flush now, to handle any texture updates.
	if (isMemoryHostCoherent()) { pullFromDevice(offset, size, true); }

	return VK_SUCCESS;
}

void MVKDeviceMemory::unmap() {
//    MVKLogDebug("Unapping device memory %p.", this);

    if (!_pMappedMemory) {
        mvkNotifyErrorWithText(VK_ERROR_MEMORY_MAP_FAILED, "Memory is not mapped. Call vkMapMemory() first.");
        return;
    }

	// Coherent memory does not require flushing by app, so we must flush now.
	if (isMemoryHostCoherent()) { flushToDevice(_mapOffset, _mapSize, true); }

    free(_pMappedHostAllocation);
    _pMappedHostAllocation = VK_NULL_HANDLE;
    _pMappedMemory = VK_NULL_HANDLE;
    _pLogicalMappedMemory = VK_NULL_HANDLE;

	_mapOffset = 0;
	_mapSize = 0;
}

// Attempts to map the memory defined by the offset and size to a unique resource, and returns
// whether such a mapping was possible. If it was, the mapped region is stored in _pMappedMemory.
bool MVKDeviceMemory::mapToUniqueResource(VkDeviceSize offset, VkDeviceSize size) {
	lock_guard<mutex> lock(_rezLock);
	MVKResource* uniqueRez = nullptr;
	for (auto& rez : _resources) {
		if (rez->doesContain(offset, size)) {
			if (uniqueRez) { return false; }	// More than one resource mapped to the region
			uniqueRez = rez;
		}
    }

	if (uniqueRez) {
		_pMappedMemory = uniqueRez->map(offset, size);
		return true;
	}

	return false;
}

void* MVKDeviceMemory::allocateMappedMemory(VkDeviceSize offset, VkDeviceSize size) {

    void* pMapAlloc = VK_NULL_HANDLE;

//    MVKLogDebug("Allocating %d bytes of device memory %p.", size, this);

    size_t mmAlign = _device->_pProperties->limits.minMemoryMapAlignment;
    VkDeviceSize deltaOffset = offset % mmAlign;
    int err = posix_memalign(&pMapAlloc, mmAlign, mvkAlignByteOffset(size + deltaOffset, mmAlign));
    if (err) {
        mvkNotifyErrorWithText(VK_ERROR_MEMORY_MAP_FAILED, "Could not allocate host memory to map to GPU memory.");
        return nullptr;
    }

    _pMappedHostAllocation = pMapAlloc;
    _pLogicalMappedMemory = (void*)((uintptr_t)pMapAlloc - offset);

    return (void*)((uintptr_t)pMapAlloc + deltaOffset);
}

VkResult MVKDeviceMemory::flushToDevice(VkDeviceSize offset, VkDeviceSize size, bool evenIfCoherent) {
	// Coherent memory is flushed on unmap(), so it is only flushed if forced
	if (size > 0 && isMemoryHostAccessible() && (evenIfCoherent || !isMemoryHostCoherent()) ) {
		lock_guard<mutex> lock(_rezLock);
		VkDeviceSize memSize = adjustMemorySize(size, offset);
        for (auto& rez : _resources) { rez->flushToDevice(offset, memSize); }
	}
	return VK_SUCCESS;
}

VkResult MVKDeviceMemory::pullFromDevice(VkDeviceSize offset, VkDeviceSize size, bool evenIfCoherent) {
	// Coherent memory is flushed on unmap(), so it is only flushed if forced
    VkDeviceSize memSize = adjustMemorySize(size, offset);
	if (memSize > 0 && isMemoryHostAccessible() && (evenIfCoherent || !isMemoryHostCoherent()) ) {
		lock_guard<mutex> lock(_rezLock);
        for (auto& rez : _resources) { rez->pullFromDevice(offset, memSize); }
	}
	return VK_SUCCESS;
}

/** 
 * If the size parameter is the special constant VK_WHOLE_SIZE, returns the size of memory 
 * between offset and the end of the buffer, otherwise simply returns size.
 */
VkDeviceSize MVKDeviceMemory::adjustMemorySize(VkDeviceSize size, VkDeviceSize offset) {
	return (size == VK_WHOLE_SIZE) ? (_allocationSize - offset) : size;
}

void MVKDeviceMemory::addResource(MVKResource* rez) {
	lock_guard<mutex> lock(_rezLock);
	_resources.push_back(rez);
}

void MVKDeviceMemory::removeResource(MVKResource* rez) {
	lock_guard<mutex> lock(_rezLock);
	mvkRemoveAllOccurances(_resources, rez);
}

MVKDeviceMemory::MVKDeviceMemory(MVKDevice* device,
								 const VkMemoryAllocateInfo* pAllocateInfo,
								 const VkAllocationCallbacks* pAllocator) : MVKBaseDeviceObject(device) {
	_allocationSize = pAllocateInfo->allocationSize;
	_mtlBuffer = nil;
	_mapOffset = 0;
	_mapSize = 0;

    _pMappedHostAllocation = VK_NULL_HANDLE;
    _pMappedMemory = VK_NULL_HANDLE;
    _pLogicalMappedMemory = VK_NULL_HANDLE;

	// Set Metal memory parameters
	VkMemoryPropertyFlags vkMemProps = _device->_pMemoryProperties->memoryTypes[pAllocateInfo->memoryTypeIndex].propertyFlags;
	_mtlResourceOptions = mvkMTLResourceOptionsFromVkMemoryPropertyFlags(vkMemProps);
	_mtlStorageMode = mvkMTLStorageModeFromVkMemoryPropertyFlags(vkMemProps);
	_mtlCPUCacheMode = mvkMTLCPUCacheModeFromVkMemoryPropertyFlags(vkMemProps);
}

MVKDeviceMemory::~MVKDeviceMemory() {
    // Unbind any resources that are using me. Iterate a copy of the collection,
    // to allow the resource to callback to remove itself from the collection.
    auto rezCopies = _resources;
    for (auto& rez : rezCopies) { rez->bindDeviceMemory(nullptr, 0); }

	[_mtlBuffer release];
	_mtlBuffer = nil;
}
