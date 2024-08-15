/*
 * MVKDeviceMemory.mm
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

#include "MVKDeviceMemory.h"
#include "MVKBuffer.h"
#include "MVKImage.h"
#include "MVKQueue.h"
#include "mvk_datatypes.hpp"
#include "MVKFoundation.h"
#include <cstdlib>
#include <stdlib.h>

using namespace std;


#pragma mark MVKDeviceMemory

void MVKDeviceMemory::propagateDebugName() {
	setLabelIfNotNil(_mtlHeap, _debugName);
	setLabelIfNotNil(_mtlBuffer, _debugName);
	setLabelIfNotNil(_mtlTexture, _debugName);
}

VkResult MVKDeviceMemory::map(const VkMemoryMapInfoKHR* pMemoryMapInfo, void** ppData) {
	if ( !isMemoryHostAccessible() ) {
		return reportError(VK_ERROR_MEMORY_MAP_FAILED, "Private GPU-only memory cannot be mapped to host memory.");
	}

	if (isMapped()) {
		return reportError(VK_ERROR_MEMORY_MAP_FAILED, "Memory is already mapped. Call vkUnmapMemory() first.");
	}

	_mapRange.offset = pMemoryMapInfo->offset;
	_mapRange.size = adjustMemorySize(pMemoryMapInfo->size, pMemoryMapInfo->offset);
	_map = [_mtlBuffer contents];

	*ppData = (void*)((uintptr_t)_map + pMemoryMapInfo->offset);

	// Coherent memory does not require flushing by app, so we must flush now
	// to support Metal textures that actually reside in non-coherent memory.
	if (mvkIsAnyFlagEnabled(_vkMemPropFlags, VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
		pullFromDevice(pMemoryMapInfo->offset, pMemoryMapInfo->size);
	}

	return VK_SUCCESS;
}

VkResult MVKDeviceMemory::unmap(const VkMemoryUnmapInfoKHR* pUnmapMemoryInfo) {
	if ( !isMapped() ) {
		return reportError(VK_ERROR_MEMORY_MAP_FAILED, "Memory is not mapped. Call vkMapMemory() first.");
	}

	// Coherent memory does not require flushing by app, so we must flush now
	// to support Metal textures that actually reside in non-coherent memory.
	if (mvkIsAnyFlagEnabled(_vkMemPropFlags, VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
		flushToDevice(_mapRange.offset, _mapRange.size);
	}

	_mapRange.offset = 0;
	_mapRange.size = 0;

	return VK_SUCCESS;
}

VkResult MVKDeviceMemory::flushToDevice(VkDeviceSize offset, VkDeviceSize size) {
	VkDeviceSize memSize = adjustMemorySize(size, offset);
	if (memSize == 0 || !isMemoryHostAccessible()) { return VK_SUCCESS; }

	if (_requiresFlushingBufferToTexture) {
		// TODO Aitor: Flush buffer to texture
	}

#if MVK_MACOS
	if ( !isUnifiedMemoryGPU() && _mtlBuffer && getMTLStorageMode() == MTLStorageModeManaged) {
		[_mtlBuffer didModifyRange: NSMakeRange(offset, memSize)];
	}
#endif

	return VK_SUCCESS;
}

VkResult MVKDeviceMemory::pullFromDevice(VkDeviceSize offset,
										 VkDeviceSize size,
										 MVKMTLBlitEncoder* pBlitEnc) {
	VkDeviceSize memSize = adjustMemorySize(size, offset);
	if (memSize == 0 || !isMemoryHostAccessible()) { return VK_SUCCESS; }
	
	MTLStorageMode storageMode = getMTLStorageMode();

	if (_requiresFlushingBufferToTexture) {
		// TODO Aitor: Flush texture to buffer
	}

#if MVK_MACOS
	if ( !isUnifiedMemoryGPU() && pBlitEnc && _mtlBuffer && storageMode == MTLStorageModeManaged) {
		if ( !pBlitEnc->mtlCmdBuffer) { pBlitEnc->mtlCmdBuffer = _device->getAnyQueue()->getMTLCommandBuffer(kMVKCommandUseInvalidateMappedMemoryRanges); }
		if ( !pBlitEnc->mtlBlitEncoder) { pBlitEnc->mtlBlitEncoder = [pBlitEnc->mtlCmdBuffer blitCommandEncoder]; }
		[pBlitEnc->mtlBlitEncoder synchronizeResource: _mtlBuffer];
	}
#endif

	return VK_SUCCESS;
}

// If the size parameter is the special constant VK_WHOLE_SIZE, returns the size of memory
// between offset and the end of the buffer, otherwise simply returns size.
VkDeviceSize MVKDeviceMemory::adjustMemorySize(VkDeviceSize size, VkDeviceSize offset) {
	return (size == VK_WHOLE_SIZE) ? (_size - offset) : size;
}

MVKDeviceMemory::MVKDeviceMemory(MVKDevice* device,
								 const VkMemoryAllocateInfo* pAllocateInfo,
								 const VkAllocationCallbacks* pAllocator) : MVKVulkanAPIDeviceObject(device) {
	MVKPhysicalDevice* physicalDevice = getPhysicalDevice();
	id<MTLDevice> mtlDevice = physicalDevice->getMTLDevice();

	// Set Metal memory parameters
	_vkMemPropFlags = physicalDevice->getMemoryProperties()->memoryTypes[pAllocateInfo->memoryTypeIndex].propertyFlags;
	MTLStorageMode storageMode = physicalDevice->getMTLStorageModeFromVkMemoryPropertyFlags(_vkMemPropFlags);
	MTLCPUCacheMode cpuCacheMode = mvkMTLCPUCacheModeFromVkMemoryPropertyFlags(_vkMemPropFlags);
	_options = mvkMTLResourceOptions(storageMode, cpuCacheMode);
	_size = pAllocateInfo->allocationSize;

	bool willExportMTLBuffer = false;
	VkExternalMemoryHandleTypeFlags handleTypes = 0;
	for (const auto* next = (const VkBaseInStructure*)pAllocateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO: {
				auto* pDedicatedInfo = (VkMemoryDedicatedAllocateInfo*)next;
				if (pDedicatedInfo->image) {
					_dedicatedImageOwner = reinterpret_cast<MVKImage*>(pDedicatedInfo->image);
					_dedicatedResourceType = DedicatedResourceType::IMAGE;
				} else if (pDedicatedInfo->buffer) {
					_dedicatedBufferOwner = reinterpret_cast<MVKBuffer*>(pDedicatedInfo->buffer);
					_dedicatedResourceType = DedicatedResourceType::BUFFER;
				}
				break;
			}
			case VK_STRUCTURE_TYPE_IMPORT_MEMORY_HOST_POINTER_INFO_EXT: {
				auto* pMemHostPtrInfo = (VkImportMemoryHostPointerInfoEXT*)next;
				if (mvkIsAnyFlagEnabled(_vkMemPropFlags, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
					switch (pMemHostPtrInfo->handleType) {
						case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT:
						case VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_MAPPED_FOREIGN_MEMORY_BIT_EXT:
							// Since there's no way to allocate a heap using external host memory, we default to a buffer
							_mtlBuffer = [mtlDevice newBufferWithBytesNoCopy: pMemHostPtrInfo->pHostPointer length: _size options: _options deallocator: ^(void *pointer, NSUInteger length){ free(pointer); }];
							break;
						default:
							break;
					}
				} else {
					setConfigurationResult(reportError(VK_ERROR_INVALID_EXTERNAL_HANDLE_KHR, "vkAllocateMemory(): Imported memory must be host-visible."));
					return;
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
				const auto* pMTLBufferInfo = (VkImportMetalBufferInfoEXT*)next;
				_mtlBuffer = [pMTLBufferInfo->mtlBuffer retain];	// retained
				_options = _mtlBuffer.resourceOptions;
				_size = _mtlBuffer.length;
				if (_mtlBuffer.heap)
					_mtlHeap = [_mtlBuffer.heap retain];
				break;
			}
			case VK_STRUCTURE_TYPE_IMPORT_METAL_TEXTURE_INFO_EXT: {
				const auto* pMTLTextureInfo = (VkImportMetalTextureInfoEXT*)next;
				_mtlTexture = [pMTLTextureInfo->mtlTexture retain];
				// Imported host visible textures require a way to map them. Since Metal does not provide any
				// utility to access texture data from a MTLTexture like MTLBuffer::contents.
				if (_mtlTexture.heap && _mtlTexture.heap.type == MTLHeapTypePlacement) {
					_mtlHeap = [_mtlTexture.heap retain];
					if (_mtlTexture.buffer) {
						_mtlBuffer = [_mtlTexture.buffer retain];
					} else {
						_mtlBuffer = [_mtlHeap newBufferWithLength:_size options:_options offset:_mtlTexture.heapOffset];
					}
				} else {
					if (_mtlTexture.buffer) {
						_mtlBuffer = [_mtlTexture.buffer retain];
					} else {
						void* data = malloc(_size);
						_mtlBuffer = [mtlDevice newBufferWithBytesNoCopy: data length: _size options: _options deallocator: ^(void *pointer, NSUInteger length){ free(pointer); }];
						_requiresFlushingBufferToTexture = true;
					}
				}
			}
			default:
				break;
		}
	}

	// Once we know the type of external handle
	checkExternalMemoryRequirements(handleTypes);

	// "Dedicated" means this memory can only be used for this image or buffer.
	if (_dedicatedResourceType == DedicatedResourceType::IMAGE) {
#if MVK_MACOS
		if (isMemoryHostCoherent() ) {
			if (!_dedicatedImageOwner->_isLinear) {
				setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkAllocateMemory(): Host-coherent VkDeviceMemory objects cannot be associated with optimal-tiling images."));
				return;
			} else {
				if (!getMetalFeatures().sharedLinearTextures) {
					// Need to use the managed mode for images.
					storageMode = MTLStorageModeManaged;
					_options = mvkMTLResourceOptions(storageMode, cpuCacheMode);
				}
			}
		}
#endif
	}

	// Only allocate memory if it was not imported
	if (_mtlBuffer)
		return;

	MTLHeapDescriptor* heapDesc = [MTLHeapDescriptor new];
	heapDesc.type = MTLHeapTypePlacement;
	heapDesc.resourceOptions = _options;
	// For now, use tracked resources. Later, we should probably default
	// to untracked, since Vulkan uses explicit barriers anyway.
	heapDesc.hazardTrackingMode = MTLHazardTrackingModeTracked;
	heapDesc.size = _size;
	_mtlHeap = [mtlDevice newHeapWithDescriptor: heapDesc];	// retained
	[heapDesc release];
	if (!_mtlHeap) goto fail_alloc;
	propagateDebugName();

	// Create a buffer that expands the whole heap
	// to be able to map and flush as required by the application
	if (mvkIsAnyFlagEnabled(_vkMemPropFlags, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
		_mtlBuffer = [_mtlHeap newBufferWithLength:_size options:_options];
		if (!_mtlBuffer) goto fail_alloc;
		[_mtlBuffer makeAliasable];
	}

fail_alloc:
	setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkAllocateMemory(): Could not allocate VkDeviceMemory of size %llu bytes.", _size));
}

void MVKDeviceMemory::checkExternalMemoryRequirements(VkExternalMemoryHandleTypeFlags handleTypes) {
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
	if (requiresDedicated && (_dedicatedResourceType == DedicatedResourceType::NONE)) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkAllocateMemory(): External memory requires a dedicated VkBuffer or VkImage."));
	}
}

MVKDeviceMemory::~MVKDeviceMemory() {
	if (_mtlTexture) {
		[_mtlTexture release];
		_mtlTexture = nil;

		// Having no buffer and texture being host accessible means we allocated memory for the mapping
		if (!_mtlBuffer && mvkIsAnyFlagEnabled(_vkMemPropFlags, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
			free(_map);
			_map = nullptr;
		}
	}

	if (_mtlBuffer) {
		[_mtlBuffer release];
		_mtlBuffer = nil;
	}

	if (_mtlHeap) {
		[_mtlHeap release];
		_mtlHeap = nil;
	}
}
