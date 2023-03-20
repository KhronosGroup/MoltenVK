/*
 * MVKDeviceMemory.mm
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

#include "MVKDeviceMemory.h"
#include "MVKBuffer.h"
#include "MVKImage.h"
#include "MVKQueue.h"
#include "MVKEnvironment.h"
#include "mvk_datatypes.hpp"
#include "MVKFoundation.h"
#include <cstdlib>
#include <stdlib.h>

using namespace std;


#pragma mark MVKDeviceMemory

void MVKDeviceMemory::propagateDebugName() {
	setLabelIfNotNil(_mtlHeap, _debugName);
	setLabelIfNotNil(_mtlBuffer, _debugName);
}

VkResult MVKDeviceMemory::map(VkDeviceSize offset, VkDeviceSize size, VkMemoryMapFlags flags, void** ppData) {

	if ( !isMemoryHostAccessible() ) {
		return reportError(VK_ERROR_MEMORY_MAP_FAILED, "Private GPU-only memory cannot be mapped to host memory.");
	}

	if (isMapped()) {
		return reportError(VK_ERROR_MEMORY_MAP_FAILED, "Memory is already mapped. Call vkUnmapMemory() first.");
	}

	if ( !ensureMTLBuffer() && !ensureHostMemory() ) {
		return reportError(VK_ERROR_OUT_OF_HOST_MEMORY, "Could not allocate %llu bytes of host-accessible device memory.", _allocationSize);
	}

	_mappedRange.offset = offset;
	_mappedRange.size = adjustMemorySize(size, offset);

	*ppData = (void*)((uintptr_t)_pMemory + offset);

	// Coherent memory does not require flushing by app, so we must flush now
	// to support Metal textures that actually reside in non-coherent memory.
	if (mvkIsAnyFlagEnabled(_vkMemPropFlags, VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
		pullFromDevice(offset, size);
	}

	return VK_SUCCESS;
}

void MVKDeviceMemory::unmap() {

	if ( !isMapped() ) {
		reportError(VK_ERROR_MEMORY_MAP_FAILED, "Memory is not mapped. Call vkMapMemory() first.");
		return;
	}

	// Coherent memory does not require flushing by app, so we must flush now
	// to support Metal textures that actually reside in non-coherent memory.
	if (mvkIsAnyFlagEnabled(_vkMemPropFlags, VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
		flushToDevice(_mappedRange.offset, _mappedRange.size);
	}

	_mappedRange.offset = 0;
	_mappedRange.size = 0;
}

VkResult MVKDeviceMemory::flushToDevice(VkDeviceSize offset, VkDeviceSize size) {
	VkDeviceSize memSize = adjustMemorySize(size, offset);
	if (memSize == 0 || !isMemoryHostAccessible()) { return VK_SUCCESS; }

#if MVK_MACOS
	if (_mtlBuffer && _mtlStorageMode == MTLStorageModeManaged) {
		[_mtlBuffer didModifyRange: NSMakeRange(offset, memSize)];
	}
#endif

	// If we have an MTLHeap object, there's no need to sync memory manually between resources and the buffer.
	if ( !_mtlHeap ) {
		lock_guard<mutex> lock(_rezLock);
		for (auto& img : _imageMemoryBindings) { img->flushToDevice(offset, memSize); }
		for (auto& buf : _buffers) { buf->flushToDevice(offset, memSize); }
	}

	return VK_SUCCESS;
}

VkResult MVKDeviceMemory::pullFromDevice(VkDeviceSize offset,
										 VkDeviceSize size,
										 MVKMTLBlitEncoder* pBlitEnc) {
    VkDeviceSize memSize = adjustMemorySize(size, offset);
	if (memSize == 0 || !isMemoryHostAccessible()) { return VK_SUCCESS; }

#if MVK_MACOS
	if (pBlitEnc && _mtlBuffer && _mtlStorageMode == MTLStorageModeManaged) {
		if ( !pBlitEnc->mtlCmdBuffer) { pBlitEnc->mtlCmdBuffer = _device->getAnyQueue()->getMTLCommandBuffer(kMVKCommandUseInvalidateMappedMemoryRanges); }
		if ( !pBlitEnc->mtlBlitEncoder) { pBlitEnc->mtlBlitEncoder = [pBlitEnc->mtlCmdBuffer blitCommandEncoder]; }
		[pBlitEnc->mtlBlitEncoder synchronizeResource: _mtlBuffer];
	}
#endif

	// If we have an MTLHeap object, there's no need to sync memory manually between resources and the buffer.
	if ( !_mtlHeap ) {
		lock_guard<mutex> lock(_rezLock);
        for (auto& img : _imageMemoryBindings) { img->pullFromDevice(offset, memSize); }
        for (auto& buf : _buffers) { buf->pullFromDevice(offset, memSize); }
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

VkResult MVKDeviceMemory::addImageMemoryBinding(MVKImageMemoryBinding* mvkImg) {
	lock_guard<mutex> lock(_rezLock);

	// If a dedicated alloc, ensure this image is the one and only image
	// I am dedicated to. If my image is aliasable, though, allow other aliasable
	// images to bind to me.
	if (_isDedicated && (_imageMemoryBindings.empty() || !(contains(_imageMemoryBindings, mvkImg) || (_imageMemoryBindings[0]->_image->getIsAliasable() && mvkImg->_image->getIsAliasable()))) ) {
		return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not bind VkImage %p to a VkDeviceMemory dedicated to resource %p. A dedicated allocation may only be used with the resource it was dedicated to.", mvkImg, getDedicatedResource() );
	}

	if (!_isDedicated) { _imageMemoryBindings.push_back(mvkImg); }

	return VK_SUCCESS;
}

void MVKDeviceMemory::removeImageMemoryBinding(MVKImageMemoryBinding* mvkImg) {
	lock_guard<mutex> lock(_rezLock);
	mvkRemoveAllOccurances(_imageMemoryBindings, mvkImg);
}

// Ensures that this instance is backed by a MTLHeap object,
// creating the MTLHeap if needed, and returns whether it was successful.
bool MVKDeviceMemory::ensureMTLHeap() {

	if (_mtlHeap) { return true; }

	// Can't create a MTLHeap on a imported memory
	if (_isHostMemImported) { return true; }

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

	propagateDebugName();

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
		auto rezOpts = getMTLResourceOptions();
		if (_isHostMemImported) {
			_mtlBuffer = [getMTLDevice() newBufferWithBytesNoCopy: _pHostMemory length: memLen options: rezOpts deallocator: nil];	// retained
		} else {
			_mtlBuffer = [getMTLDevice() newBufferWithBytes: _pHostMemory length: memLen options: rezOpts];     // retained
		}
		freeHostMemory();
	} else {
		_mtlBuffer = [getMTLDevice() newBufferWithLength: memLen options: getMTLResourceOptions()];     // retained
	}
	if (!_mtlBuffer) { return false; }
	_pMemory = isMemoryHostAccessible() ? _mtlBuffer.contents : nullptr;

	propagateDebugName();

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
	if ( !_isHostMemImported ) { free(_pHostMemory); }
	_pHostMemory = nullptr;
}

MVKResource* MVKDeviceMemory::getDedicatedResource() {
	MVKAssert(_isDedicated, "This method should only be called on dedicated allocations!");
	return _buffers.empty() ? (MVKResource*)_imageMemoryBindings[0] : (MVKResource*)_buffers[0];
}

MVKDeviceMemory::MVKDeviceMemory(MVKDevice* device,
								 const VkMemoryAllocateInfo* pAllocateInfo,
								 const VkAllocationCallbacks* pAllocator) : MVKVulkanAPIDeviceObject(device) {
	// Set Metal memory parameters
	_vkMemPropFlags = _device->_pMemoryProperties->memoryTypes[pAllocateInfo->memoryTypeIndex].propertyFlags;
	_mtlStorageMode = mvkMTLStorageModeFromVkMemoryPropertyFlags(_vkMemPropFlags);
	_mtlCPUCacheMode = mvkMTLCPUCacheModeFromVkMemoryPropertyFlags(_vkMemPropFlags);

	_allocationSize = pAllocateInfo->allocationSize;

	bool willExportMTLBuffer = false;
	VkImage dedicatedImage = VK_NULL_HANDLE;
	VkBuffer dedicatedBuffer = VK_NULL_HANDLE;
	VkExternalMemoryHandleTypeFlags handleTypes = 0;
	for (const auto* next = (const VkBaseInStructure*)pAllocateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO: {
				auto* pDedicatedInfo = (VkMemoryDedicatedAllocateInfo*)next;
				dedicatedImage = pDedicatedInfo->image;
				dedicatedBuffer = pDedicatedInfo->buffer;
				_isDedicated = dedicatedImage || dedicatedBuffer;
				break;
			}
			case VK_STRUCTURE_TYPE_IMPORT_MEMORY_HOST_POINTER_INFO_EXT: {
				auto* pMemHostPtrInfo = (VkImportMemoryHostPointerInfoEXT*)next;
				if (mvkIsAnyFlagEnabled(_vkMemPropFlags, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
					switch (pMemHostPtrInfo->handleType) {
						case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT:
						case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_MAPPED_FOREIGN_MEMORY_BIT_EXT:
							_pHostMemory = pMemHostPtrInfo->pHostPointer;
							_isHostMemImported = true;
							break;
						default:
							break;
					}
				} else {
					setConfigurationResult(reportError(VK_ERROR_INVALID_EXTERNAL_HANDLE_KHR, "vkAllocateMemory(): Imported memory must be host-visible."));
				}
				break;
			}
			case VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO: {
				auto* pExpMemInfo = (VkExportMemoryAllocateInfo*)next;
				handleTypes = pExpMemInfo->handleTypes;
				break;
			}
			case VK_STRUCTURE_TYPE_IMPORT_METAL_BUFFER_INFO_EXT: {
				// Setting Metal objects directly will override Vulkan settings.
				// It is responsibility of app to ensure these are consistent. Not doing so results in undefined behavior.
				const auto* pMTLBuffInfo = (VkImportMetalBufferInfoEXT*)next;
				[_mtlBuffer release];							// guard against dups
				_mtlBuffer = [pMTLBuffInfo->mtlBuffer retain];	// retained
				_mtlStorageMode = _mtlBuffer.storageMode;
				_mtlCPUCacheMode = _mtlBuffer.cpuCacheMode;
				_allocationSize = _mtlBuffer.length;
				break;
			}
			case VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT: {
				const auto* pExportInfo = (VkExportMetalObjectCreateInfoEXT*)next;
				willExportMTLBuffer = pExportInfo->exportObjectType == VK_EXPORT_METAL_OBJECT_TYPE_METAL_BUFFER_BIT_EXT;
			}
			case VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO: {
				auto* pMemAllocFlagsInfo = (VkMemoryAllocateFlagsInfo*)next;
				_vkMemAllocFlags = pMemAllocFlagsInfo->flags;
				break;
			}
			default:
				break;
		}
	}

	initExternalMemory(handleTypes);	// After setting _isDedicated

	// "Dedicated" means this memory can only be used for this image or buffer.
	if (dedicatedImage) {
#if MVK_MACOS
		if (isMemoryHostCoherent() ) {
			if (!((MVKImage*)dedicatedImage)->_isLinear) {
				setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkAllocateMemory(): Host-coherent VkDeviceMemory objects cannot be associated with optimal-tiling images."));
			} else {
				if (!_device->_pMetalFeatures->sharedLinearTextures) {
					// Need to use the managed mode for images.
					_mtlStorageMode = MTLStorageModeManaged;
				}
				// Nonetheless, we need a buffer to be able to map the memory at will.
				if (!ensureMTLBuffer() ) {
					setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkAllocateMemory(): Could not allocate a host-coherent VkDeviceMemory of size %llu bytes. The maximum memory-aligned size of a host-coherent VkDeviceMemory is %llu bytes.", _allocationSize, _device->_pMetalFeatures->maxMTLBufferSize));
				}
			}
		}
#endif
        for (auto& memoryBinding : ((MVKImage*)dedicatedImage)->_memoryBindings) {
            _imageMemoryBindings.push_back(memoryBinding);
        }
		return;
	}

	if (dedicatedBuffer) {
		_buffers.push_back((MVKBuffer*)dedicatedBuffer);
	}

	// If we can, create a MTLHeap. This should happen before creating the buffer, allowing us to map its contents.
	if ( !_isDedicated ) {
		if (!ensureMTLHeap()) {
			setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkAllocateMemory(): Could not allocate VkDeviceMemory of size %llu bytes.", _allocationSize));
			return;
		}
	}

	// If memory needs to be coherent it must reside in a MTLBuffer, since an open-ended map() must work.
	// If memory was imported, a MTLBuffer must be created on it.
	// Or if a MTLBuffer will be exported, ensure it exists.
	if ((isMemoryHostCoherent() || _isHostMemImported || willExportMTLBuffer) && !ensureMTLBuffer() ) {
		setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkAllocateMemory(): Could not allocate a host-coherent or exportable VkDeviceMemory of size %llu bytes. The maximum memory-aligned size of a host-coherent VkDeviceMemory is %llu bytes.", _allocationSize, _device->_pMetalFeatures->maxMTLBufferSize));
	}
}

void MVKDeviceMemory::initExternalMemory(VkExternalMemoryHandleTypeFlags handleTypes) {
	if ( !handleTypes ) { return; }
	
	if ( !mvkIsOnlyAnyFlagEnabled(handleTypes, VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_KHR | VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkAllocateMemory(): Only external memory handle types VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_KHR or VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR are supported."));
	}

	bool requiresDedicated = false;
	if (mvkIsAnyFlagEnabled(handleTypes, VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_KHR)) {
		auto& xmProps = getPhysicalDevice()->getExternalBufferProperties(VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_KHR);
		requiresDedicated = requiresDedicated || mvkIsAnyFlagEnabled(xmProps.externalMemoryFeatures, VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT);
	}
	if (mvkIsAnyFlagEnabled(handleTypes, VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR)) {
		auto& xmProps = getPhysicalDevice()->getExternalImageProperties(VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR);
		requiresDedicated = requiresDedicated || mvkIsAnyFlagEnabled(xmProps.externalMemoryFeatures, VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT);
	}
	if (requiresDedicated && !_isDedicated) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkAllocateMemory(): External memory requires a dedicated VkBuffer or VkImage."));
	}
}

MVKDeviceMemory::~MVKDeviceMemory() {
    // Unbind any resources that are using me. Iterate a copy of the collection,
    // to allow the resource to callback to remove itself from the collection.
    auto buffCopies = _buffers;
    for (auto& buf : buffCopies) { buf->bindDeviceMemory(nullptr, 0); }
	auto imgCopies = _imageMemoryBindings;
	for (auto& img : imgCopies) { img->bindDeviceMemory(nullptr, 0); }

	[_mtlBuffer release];
	_mtlBuffer = nil;

	[_mtlHeap release];
	_mtlHeap = nil;

	freeHostMemory();
}
