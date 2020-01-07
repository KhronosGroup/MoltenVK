/*
 * MVKDeviceMemory.mm
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

#include "MVKDeviceMemory.h"
#include "MVKBuffer.h"
#include "MVKImage.h"
#include "MVKQueue.h"
#include "MVKEnvironment.h"
#include "mvk_datatypes.hpp"
#include "MVKFoundation.h"
#include "MVKLogging.h"
#include <cstdlib>
#include <stdlib.h>

using namespace std;


#pragma mark MVKDeviceMemory

void MVKDeviceMemory::propogateDebugName() {
	setLabelIfNotNil(_mtlHeap, _debugName);
	setLabelIfNotNil(_mtlBuffer, _debugName);
}

VkResult MVKDeviceMemory::map(VkDeviceSize offset, VkDeviceSize size, VkMemoryMapFlags flags, void** ppData) {

	if ( !isMemoryHostAccessible() ) {
		return reportError(VK_ERROR_MEMORY_MAP_FAILED, "Private GPU-only memory cannot be mapped to host memory.");
	}

	if (_isMapped) {
		return reportError(VK_ERROR_MEMORY_MAP_FAILED, "Memory is already mapped. Call vkUnmapMemory() first.");
	}

	if ( !ensureMTLBuffer() && !ensureHostMemory() ) {
		return reportError(VK_ERROR_OUT_OF_HOST_MEMORY, "Could not allocate %llu bytes of host-accessible device memory.", _allocationSize);
	}

	_mapOffset = offset;
	_mapSize = adjustMemorySize(size, offset);
	_isMapped = true;

	*ppData = (void*)((uintptr_t)_pMemory + offset);

	// Coherent memory does not require flushing by app, so we must flush now, to handle any texture updates.
	pullFromDevice(offset, size, isMemoryHostCoherent());

	return VK_SUCCESS;
}

void MVKDeviceMemory::unmap() {

	if ( !_isMapped ) {
		reportError(VK_ERROR_MEMORY_MAP_FAILED, "Memory is not mapped. Call vkMapMemory() first.");
		return;
	}

	// Coherent memory does not require flushing by app, so we must flush now.
	flushToDevice(_mapOffset, _mapSize, isMemoryHostCoherent());

	_mapOffset = 0;
	_mapSize = 0;
	_isMapped = false;
}

VkResult MVKDeviceMemory::flushToDevice(VkDeviceSize offset, VkDeviceSize size, bool evenIfCoherent) {
	// Coherent memory is flushed on unmap(), so it is only flushed if forced
	VkDeviceSize memSize = adjustMemorySize(size, offset);
	if (memSize > 0 && isMemoryHostAccessible() && (evenIfCoherent || !isMemoryHostCoherent()) ) {

#if MVK_MACOS
		if (_mtlBuffer && _mtlStorageMode == MTLStorageModeManaged) {
			[_mtlBuffer didModifyRange: NSMakeRange(offset, memSize)];
		}
#endif

		// If we have an MTLHeap object, there's no need to sync memory manually between images and the buffer.
		if (!_mtlHeap) {
			lock_guard<mutex> lock(_rezLock);
			for (auto& img : _images) { img->flushToDevice(offset, memSize); }
		}
	}
	return VK_SUCCESS;
}

VkResult MVKDeviceMemory::pullFromDevice(VkDeviceSize offset,
										 VkDeviceSize size,
										 bool evenIfCoherent,
										 MVKMTLBlitEncoder* pBlitEnc) {
	// Coherent memory is flushed on unmap(), so it is only flushed if forced
    VkDeviceSize memSize = adjustMemorySize(size, offset);
	if (memSize > 0 && isMemoryHostAccessible() && (evenIfCoherent || !isMemoryHostCoherent()) && !_mtlHeap) {
		lock_guard<mutex> lock(_rezLock);
        for (auto& img : _images) { img->pullFromDevice(offset, memSize); }

#if MVK_MACOS
		if (pBlitEnc && _mtlBuffer && _mtlStorageMode == MTLStorageModeManaged) {
			if ( !pBlitEnc->mtlCmdBuffer) { pBlitEnc->mtlCmdBuffer = [_device->getAnyQueue()->getMTLCommandQueue() commandBufferWithUnretainedReferences]; }
			if ( !pBlitEnc->mtlBlitEncoder) { pBlitEnc->mtlBlitEncoder = [pBlitEnc->mtlCmdBuffer blitCommandEncoder]; }
			[pBlitEnc->mtlBlitEncoder synchronizeResource: _mtlBuffer];
		}
#endif

	}
	return VK_SUCCESS;
}

// If the size parameter is the special constant VK_WHOLE_SIZE, returns the size of memory
// between offset and the end of the buffer, otherwise simply returns size.
VkDeviceSize MVKDeviceMemory::adjustMemorySize(VkDeviceSize size, VkDeviceSize offset) {
	return (size == VK_WHOLE_SIZE) ? (_allocationSize - offset) : size;
}

VkResult MVKDeviceMemory::addBuffer(MVKBuffer* mvkBuff) {
	lock_guard<mutex> lock(_rezLock);

	// If a dedicated alloc, ensure this buffer is the one and only buffer
	// I am dedicated to.
	if (_isDedicated && (_buffers.empty() || _buffers[0] != mvkBuff) ) {
		return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not bind VkBuffer %p to a VkDeviceMemory dedicated to resource %p. A dedicated allocation may only be used with the resource it was dedicated to.", mvkBuff, getDedicatedResource() );
	}

	if (!ensureMTLBuffer() ) {
		return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not bind a VkBuffer to a VkDeviceMemory of size %llu bytes. The maximum memory-aligned size of a VkDeviceMemory that supports a VkBuffer is %llu bytes.", _allocationSize, _device->_pMetalFeatures->maxMTLBufferSize);
	}

	// In the dedicated case, we already saved the buffer we're going to use.
	if (!_isDedicated) { _buffers.push_back(mvkBuff); }

	return VK_SUCCESS;
}

void MVKDeviceMemory::removeBuffer(MVKBuffer* mvkBuff) {
	lock_guard<mutex> lock(_rezLock);
	mvkRemoveAllOccurances(_buffers, mvkBuff);
}

VkResult MVKDeviceMemory::addImage(MVKImage* mvkImg) {
	lock_guard<mutex> lock(_rezLock);

	// If a dedicated alloc, ensure this image is the one and only image
	// I am dedicated to.
	if (_isDedicated && (_images.empty() || _images[0] != mvkImg) ) {
		return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not bind VkImage %p to a VkDeviceMemory dedicated to resource %p. A dedicated allocation may only be used with the resource it was dedicated to.", mvkImg, getDedicatedResource() );
	}

	if (!_isDedicated) { _images.push_back(mvkImg); }

	return VK_SUCCESS;
}

void MVKDeviceMemory::removeImage(MVKImage* mvkImg) {
	lock_guard<mutex> lock(_rezLock);
	mvkRemoveAllOccurances(_images, mvkImg);
}

// Ensures that this instance is backed by a MTLHeap object,
// creating the MTLHeap if needed, and returns whether it was successful.
bool MVKDeviceMemory::ensureMTLHeap() {

	if (_mtlHeap) { return true; }

	// Don't bother if we don't have placement heaps.
	if (!getDevice()->_pMetalFeatures->placementHeaps) { return true; }

	// Can't create MTLHeaps of zero size.
	if (_allocationSize == 0) { return true; }

#if MVK_MACOS
	// MTLHeaps on macOS must use private storage for now.
	if (_mtlStorageMode != MTLStorageModePrivate) { return true; }
#endif
#if MVK_IOS
	// MTLHeaps on iOS must use private or shared storage for now.
	if ( !(_mtlStorageMode == MTLStorageModePrivate ||
		   _mtlStorageMode == MTLStorageModeShared) ) { return true; }
#endif

	MTLHeapDescriptor* heapDesc = [MTLHeapDescriptor new];
	heapDesc.type = MTLHeapTypePlacement;
	heapDesc.storageMode = _mtlStorageMode;
	heapDesc.cpuCacheMode = _mtlCPUCacheMode;
	// For now, use tracked resources. Later, we should probably default
	// to untracked, since Vulkan uses explicit barriers anyway.
	heapDesc.hazardTrackingMode = MTLHazardTrackingModeTracked;
	heapDesc.size = _allocationSize;
	_mtlHeap = [_device->getMTLDevice() newHeapWithDescriptor: heapDesc];	// retained
	[heapDesc release];
	if (!_mtlHeap) { return false; }

	propogateDebugName();

	return true;
}

// Ensures that this instance is backed by a MTLBuffer object,
// creating the MTLBuffer if needed, and returns whether it was successful.
bool MVKDeviceMemory::ensureMTLBuffer() {

	if (_mtlBuffer) { return true; }

	NSUInteger memLen = mvkAlignByteCount(_allocationSize, _device->_pMetalFeatures->mtlBufferAlignment);

	if (memLen > _device->_pMetalFeatures->maxMTLBufferSize) { return false; }

	// If host memory was already allocated, it is copied into the new MTLBuffer, and then released.
	if (_mtlHeap) {
		_mtlBuffer = [_mtlHeap newBufferWithLength: memLen options: getMTLResourceOptions() offset: 0];	// retained
		if (_pHostMemory) {
			memcpy(_mtlBuffer.contents, _pHostMemory, memLen);
			freeHostMemory();
		}
		[_mtlBuffer makeAliasable];
	} else if (_pHostMemory) {
		_mtlBuffer = [getMTLDevice() newBufferWithBytes: _pHostMemory length: memLen options: getMTLResourceOptions()];     // retained
		freeHostMemory();
	} else {
		_mtlBuffer = [getMTLDevice() newBufferWithLength: memLen options: getMTLResourceOptions()];     // retained
	}
	if (!_mtlBuffer) { return false; }
	_pMemory = isMemoryHostAccessible() ? _mtlBuffer.contents : nullptr;

	propogateDebugName();

	return true;
}

// Ensures that host-accessible memory is available, allocating it if necessary.
bool MVKDeviceMemory::ensureHostMemory() {

	if (_pMemory) { return true; }

	if ( !_pHostMemory) {
		size_t memAlign = _device->_pMetalFeatures->mtlBufferAlignment;
		NSUInteger memLen = mvkAlignByteCount(_allocationSize, memAlign);
		int err = posix_memalign(&_pHostMemory, memAlign, memLen);
		if (err) { return false; }
	}

	_pMemory = _pHostMemory;

	return true;
}

void MVKDeviceMemory::freeHostMemory() {
	free(_pHostMemory);
	_pHostMemory = nullptr;
}

MVKResource* MVKDeviceMemory::getDedicatedResource() {
	MVKAssert(_isDedicated, "This method should only be called on dedicated allocations!");
	if (_buffers.empty())
		return _images[0];
	else
		return _buffers[0];
}

MVKDeviceMemory::MVKDeviceMemory(MVKDevice* device,
								 const VkMemoryAllocateInfo* pAllocateInfo,
								 const VkAllocationCallbacks* pAllocator) : MVKVulkanAPIDeviceObject(device) {
	// Set Metal memory parameters
	VkMemoryPropertyFlags vkMemProps = _device->_pMemoryProperties->memoryTypes[pAllocateInfo->memoryTypeIndex].propertyFlags;
	_mtlStorageMode = mvkMTLStorageModeFromVkMemoryPropertyFlags(vkMemProps);
	_mtlCPUCacheMode = mvkMTLCPUCacheModeFromVkMemoryPropertyFlags(vkMemProps);

	_allocationSize = pAllocateInfo->allocationSize;

	VkImage dedicatedImage = VK_NULL_HANDLE;
	VkBuffer dedicatedBuffer = VK_NULL_HANDLE;
	auto* next = (VkStructureType*)pAllocateInfo->pNext;
	while (next) {
		switch (*next) {
		case VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO: {
			auto* pDedicatedInfo = (VkMemoryDedicatedAllocateInfo*)next;
			dedicatedImage = pDedicatedInfo->image;
			dedicatedBuffer = pDedicatedInfo->buffer;
			next = (VkStructureType*)pDedicatedInfo->pNext;
			break;
		}
		default:
			next = (VkStructureType*)((VkMemoryAllocateInfo*)next)->pNext;
			break;
		}
	}

	// "Dedicated" means this memory can only be used for this image or buffer.
	if (dedicatedImage) {
#if MVK_MACOS
		if (isMemoryHostCoherent() ) {
			if (!((MVKImage*)dedicatedImage)->_isLinear) {
				setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Host-coherent VkDeviceMemory objects cannot be associated with optimal-tiling images."));
			} else {
				// Need to use the managed mode for images.
				_mtlStorageMode = MTLStorageModeManaged;
				// Nonetheless, we need a buffer to be able to map the memory at will.
				if (!ensureMTLBuffer() ) {
					setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not allocate a host-coherent VkDeviceMemory of size %llu bytes. The maximum memory-aligned size of a host-coherent VkDeviceMemory is %llu bytes.", _allocationSize, _device->_pMetalFeatures->maxMTLBufferSize));
				}
			}
		}
#endif
		_isDedicated = true;
		_images.push_back((MVKImage*)dedicatedImage);
		return;
	}

	// If we can, create a MTLHeap. This should happen before creating the buffer
	// allowing us to map its contents.
	if (!dedicatedImage && !dedicatedBuffer) {
		if (!ensureMTLHeap()) {
			setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not allocate VkDeviceMemory of size %llu bytes.", _allocationSize));
			return;
		}
	}

	// If memory needs to be coherent it must reside in an MTLBuffer, since an open-ended map() must work.
	if (isMemoryHostCoherent() && !ensureMTLBuffer() ) {
		setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not allocate a host-coherent VkDeviceMemory of size %llu bytes. The maximum memory-aligned size of a host-coherent VkDeviceMemory is %llu bytes.", _allocationSize, _device->_pMetalFeatures->maxMTLBufferSize));
	}

	if (dedicatedBuffer) {
		_isDedicated = true;
		_buffers.push_back((MVKBuffer*)dedicatedBuffer);
	}
}

MVKDeviceMemory::~MVKDeviceMemory() {
    // Unbind any resources that are using me. Iterate a copy of the collection,
    // to allow the resource to callback to remove itself from the collection.
    auto buffCopies = _buffers;
    for (auto& buf : buffCopies) { buf->bindDeviceMemory(nullptr, 0); }
	auto imgCopies = _images;
	for (auto& img : imgCopies) { img->bindDeviceMemory(nullptr, 0); }

	[_mtlBuffer release];
	_mtlBuffer = nil;

	[_mtlHeap release];
	_mtlHeap = nil;

	freeHostMemory();
}
