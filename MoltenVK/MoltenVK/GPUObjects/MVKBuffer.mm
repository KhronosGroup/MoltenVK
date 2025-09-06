/*
 * MVKBuffer.mm
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

#include "MVKBuffer.h"
#include "MVKCommandBuffer.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"

using namespace std;


#pragma mark -
#pragma mark MVKBuffer

void MVKBuffer::propagateDebugName() {
	if (!_debugName) { return; }
	if (_deviceMemory &&
		_deviceMemory->isDedicatedAllocation() &&
		_deviceMemory->_debugName.length == 0) {

		_deviceMemory->setDebugName(_debugName.UTF8String);
	}
	setMetalObjectLabel(_mtlBuffer, _debugName);
}


#pragma mark Resource memory

VkResult MVKBuffer::getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements) {
	if (getMetalFeatures().placementHeaps) {
		MTLSizeAndAlign sizeAndAlign = [getMTLDevice() heapBufferSizeAndAlignWithLength: getByteCount() 
																				options: MTLResourceStorageModePrivate];
		pMemoryRequirements->size = sizeAndAlign.size;
		pMemoryRequirements->alignment = sizeAndAlign.align;
	} else {
		pMemoryRequirements->size = getByteCount();
		pMemoryRequirements->alignment = _byteAlignment;
	}
	pMemoryRequirements->memoryTypeBits = getPhysicalDevice()->getAllMemoryTypes();
	// Memoryless storage is not allowed for buffers
	mvkDisableFlags(pMemoryRequirements->memoryTypeBits, getPhysicalDevice()->getLazilyAllocatedMemoryTypes());
	return VK_SUCCESS;
}

VkResult MVKBuffer::getMemoryRequirements(VkMemoryRequirements2* pMemoryRequirements) {
	pMemoryRequirements->sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
	getMemoryRequirements(&pMemoryRequirements->memoryRequirements);
	for (auto* next = (VkBaseOutStructure*)pMemoryRequirements->pNext; next; next = next->pNext) {
		switch (next->sType) {
		case VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS: {
			auto* dedicatedReqs = (VkMemoryDedicatedRequirements*)next;
			dedicatedReqs->requiresDedicatedAllocation = _requiresDedicatedMemoryAllocation;
			dedicatedReqs->prefersDedicatedAllocation = dedicatedReqs->requiresDedicatedAllocation;
			break;
		}
		default:
			break;
		}
	}
	return VK_SUCCESS;
}

VkResult MVKBuffer::bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) {
	if (_deviceMemory) { _deviceMemory->removeBuffer(this); }

	MVKResource::bindDeviceMemory(mvkMem, memOffset);

#if MVK_MACOS
	if (_deviceMemory) {
		_isHostCoherentTexelBuffer = (!isUnifiedMemoryGPU() &&
									  !getMetalFeatures().sharedLinearTextures &&
									  _deviceMemory->isMemoryHostCoherent() &&
									  mvkIsAnyFlagEnabled(_usage, (VK_BUFFER_USAGE_2_UNIFORM_TEXEL_BUFFER_BIT |
																   VK_BUFFER_USAGE_2_STORAGE_TEXEL_BUFFER_BIT)));
	}
#endif

	propagateDebugName();

	VkResult result = _deviceMemory ? _deviceMemory->addBuffer(this) : VK_SUCCESS;

    // Track memory address once it is bound
    if (result == VK_SUCCESS && mvkIsAnyFlagEnabled(_usage, VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT)) {
        getDevice()->trackBufferAddress(this, true);
    }

    return result;
}

VkResult MVKBuffer::bindDeviceMemory2(const VkBindBufferMemoryInfo* pBindInfo) {
	VkResult res = bindDeviceMemory((MVKDeviceMemory*)pBindInfo->memory, pBindInfo->memoryOffset);
	for (const auto* next = (const VkBaseInStructure*)pBindInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_BIND_MEMORY_STATUS: {
				auto* pBindMemoryStatus = (const VkBindMemoryStatus*)next;
				*(pBindMemoryStatus->pResult) = res;
				break;
			}
			default:
				break;
		}
	}
	return res;
}

void MVKBuffer::applyMemoryBarrier(MVKPipelineBarrier& barrier,
                                   MVKCommandEncoder* cmdEncoder,
                                   MVKCommandUse cmdUse) {
#if MVK_MACOS
	if ( needsHostReadSync(barrier) ) {
		[cmdEncoder->getMTLBlitEncoder(cmdUse) synchronizeResource: getMTLBuffer()];
	}
#endif
}

void MVKBuffer::applyBufferMemoryBarrier(MVKPipelineBarrier& barrier,
                                         MVKCommandEncoder* cmdEncoder,
                                         MVKCommandUse cmdUse) {
#if MVK_MACOS
	if ( needsHostReadSync(barrier) ) {
		[cmdEncoder->getMTLBlitEncoder(cmdUse) synchronizeResource: getMTLBuffer()];
	}
#endif
}

// Returns whether the specified buffer memory barrier requires a sync between this
// buffer and host memory for the purpose of the host reading texture memory.
bool MVKBuffer::needsHostReadSync(MVKPipelineBarrier& barrier) {
#if MVK_MACOS
	return (!isUnifiedMemoryGPU() &&
			mvkIsAnyFlagEnabled(barrier.dstStageMask, (VK_PIPELINE_STAGE_HOST_BIT)) &&
			mvkIsAnyFlagEnabled(barrier.dstAccessMask, (VK_ACCESS_HOST_READ_BIT)) &&
			isMemoryHostAccessible() && (!isMemoryHostCoherent() || _isHostCoherentTexelBuffer));
#else
	return false;
#endif
}

bool MVKBuffer::overlaps(VkDeviceSize offset, VkDeviceSize size, VkDeviceSize &overlapOffset, VkDeviceSize &overlapSize) {
    VkDeviceSize end = offset + size;
    VkDeviceSize bufferEnd = _deviceMemoryOffset + _byteCount;
    if (offset < bufferEnd && end > _deviceMemoryOffset) {
        overlapOffset = max(_deviceMemoryOffset, offset);
        overlapSize = min(bufferEnd, end) - overlapOffset;
        return true;
    }

    return false;
}

bool MVKBuffer::shouldFlushHostMemory() { return !isUnifiedMemoryGPU() && _isHostCoherentTexelBuffer; }

// Flushes the device memory at the specified memory range into the MTLBuffer.
VkResult MVKBuffer::flushToDevice(VkDeviceSize offset, VkDeviceSize size) {
#if MVK_MACOS
    VkDeviceSize flushOffset, flushSize;
	if (shouldFlushHostMemory() && _mtlBufferCache && overlaps(offset, size, flushOffset, flushSize)) {
		memcpy(reinterpret_cast<char *>(_mtlBufferCache.contents) + flushOffset - _deviceMemoryOffset,
		       reinterpret_cast<const char *>(_deviceMemory->getHostMemoryAddress()) + flushOffset,
		       flushSize);
		[_mtlBufferCache didModifyRange: NSMakeRange(flushOffset - _deviceMemoryOffset, flushSize)];
	}
#endif
	return VK_SUCCESS;
}

// Pulls content from the MTLBuffer into the device memory at the specified memory range.
VkResult MVKBuffer::pullFromDevice(VkDeviceSize offset, VkDeviceSize size) {
#if MVK_MACOS
    VkDeviceSize pullOffset, pullSize;
	if (shouldFlushHostMemory() && _mtlBufferCache && overlaps(offset, size, pullOffset, pullSize)) {
		memcpy(reinterpret_cast<char *>(_deviceMemory->getHostMemoryAddress()) + pullOffset,
		       reinterpret_cast<const char *>(_mtlBufferCache.contents) + pullOffset - _deviceMemoryOffset,
		       pullSize);
	}
#endif
	return VK_SUCCESS;
}


#pragma mark Metal

id<MTLBuffer> MVKBuffer::getMTLBuffer() {
	if (_mtlBuffer) { return _mtlBuffer; }
    if ((!_deviceMemory || !_deviceMemory->getMTLHeap()) && mvkIsAnyFlagEnabled(_usage, VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR)) {
        lock_guard<mutex> lock(_lock);
        if (_mtlBuffer) { return _mtlBuffer; }

        MTLHeapDescriptor* heapDescriptor = [MTLHeapDescriptor new];
        heapDescriptor.type = MTLHeapTypePlacement;
        heapDescriptor.storageMode = MTLStorageModePrivate;
        heapDescriptor.cpuCacheMode = MTLCPUCacheModeDefaultCache;
        heapDescriptor.hazardTrackingMode = MTLHazardTrackingModeTracked;
        heapDescriptor.size = getByteCount();
        _mtlHeap = [getMTLDevice() newHeapWithDescriptor:heapDescriptor];
        [heapDescriptor release];
        if (!_mtlHeap) return nil;
        
        _mtlBuffer = [_mtlHeap newBufferWithLength: getByteCount()
                                           options: mvkMTLResourceOptions(MTLStorageModePrivate, MTLCPUCacheModeDefaultCache)
                                            offset: 0];

		propagateDebugName();
        return _mtlBuffer;
    }
	if (_deviceMemory) {
		if (_deviceMemory->getMTLHeap()) {
            lock_guard<mutex> lock(_lock);
            if (_mtlBuffer) { return _mtlBuffer; }
			_mtlBuffer = [_deviceMemory->getMTLHeap() newBufferWithLength: getByteCount()
																  options: _deviceMemory->getMTLResourceOptions()
																   offset: _deviceMemoryOffset];	// retained
			getDevice()->makeResident(_mtlBuffer);
			propagateDebugName();
			return _mtlBuffer;
		} else {
			return _deviceMemory->getMTLBuffer();
		}
	}
	return nil;
}

id<MTLHeap> MVKBuffer::getMTLHeap() {
    if (_mtlHeap) { return _mtlHeap; }
	if (_deviceMemory && _deviceMemory->getMTLHeap()) { return _deviceMemory->getMTLHeap(); }
    return nil;
}

id<MTLBuffer> MVKBuffer::getMTLBufferCache() {
#if MVK_MACOS
    if (_isHostCoherentTexelBuffer && !_mtlBufferCache) {
        lock_guard<mutex> lock(_lock);
        if (_mtlBufferCache) { return _mtlBufferCache; }

		_mtlBufferCache = [getMTLDevice() newBufferWithLength: getByteCount()
													  options: MTLResourceStorageModeManaged];    // retained
		getDevice()->makeResident(_mtlBufferCache);
        flushToDevice(_deviceMemoryOffset, _byteCount);
    }
#endif
    return _mtlBufferCache;
}

uint64_t MVKBuffer::getMTLBufferGPUAddress() {
#if MVK_XCODE_14
	return [getMTLBuffer() gpuAddress] + getMTLBufferOffset();
#endif
	return 0;
}

#pragma mark Construction

MVKBuffer::MVKBuffer(MVKDevice* device, const VkBufferCreateInfo* pCreateInfo) : MVKResource(device), _usage(pCreateInfo->usage) {
    _byteAlignment = getMetalFeatures().mtlBufferAlignment;
    _byteCount = pCreateInfo->size;

	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_BUFFER_USAGE_FLAGS_2_CREATE_INFO:
				_usage |= ((VkBufferUsageFlags2CreateInfo*)next)->usage;
				break;
			default:
				break;
		}
	}

	for (const auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_BUFFER_CREATE_INFO: {
				auto* pExtMemInfo = (const VkExternalMemoryBufferCreateInfo*)next;
				initExternalMemory(pExtMemInfo->handleTypes);
				break;
			}
			default:
				break;
		}
	}
}

void MVKBuffer::initExternalMemory(VkExternalMemoryHandleTypeFlags handleTypes) {
	if ( !handleTypes ) { return; }
	if (mvkIsOnlyAnyFlagEnabled(handleTypes, VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_EXT)) {
		_externalMemoryHandleTypes = handleTypes;
		auto& xmProps = getPhysicalDevice()->getExternalBufferProperties(VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_EXT);
		_requiresDedicatedMemoryAllocation = _requiresDedicatedMemoryAllocation || mvkIsAnyFlagEnabled(xmProps.externalMemoryFeatures, VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT);
	} else if (mvkIsOnlyAnyFlagEnabled(handleTypes, VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLHEAP_BIT_EXT)) {
		_externalMemoryHandleTypes = handleTypes;
		auto& xmProps = getPhysicalDevice()->getExternalBufferProperties(VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLHEAP_BIT_EXT);
		_requiresDedicatedMemoryAllocation = _requiresDedicatedMemoryAllocation || mvkIsAnyFlagEnabled(xmProps.externalMemoryFeatures, VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT);
	} else {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateBuffer(): Only external memory handle type VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLBUFFER_BIT_EXT and VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLHEAP_BIT_EXT are supported."));
	}
}

// Memory detached in destructor too, as a fail-safe.
MVKBuffer::~MVKBuffer() {
	detachMemory();
}

// Overridden to detach from the resource memory when the app destroys this object.
// This object can be retained in a descriptor after the app destroys it, even
// though the descriptor can't use it. But doing so retains usuable resource memory.
// In addition, a potential race condition exists if the app updates the descriptor
// on one thread at the same time it is destroying the buffer and freeing the device
// memory on another thread. The race condition occurs when the device memory calls
// back to this buffer to unbind from it. By detaching from the device memory here,
// (when the app destroys the buffer), even if this buffer is retained by a descriptor,
// when the device memory is freed by the app, it won't try to call back here to unbind.
void MVKBuffer::destroy() {
	detachMemory();
	MVKResource::destroy();
}

// Potentially called twice, from destroy() and destructor, so ensure everything is nulled out.
void MVKBuffer::detachMemory() {
    if ((_mtlBuffer || _deviceMemory) && mvkIsAnyFlagEnabled(_usage, VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT))
        getDevice()->trackBufferAddress(this, false);
	if (_deviceMemory) { _deviceMemory->removeBuffer(this); }
	_deviceMemory = nullptr;
	if (_mtlBuffer) getDevice()->removeResidency(_mtlBuffer);
	[_mtlBuffer release];
	_mtlBuffer = nil;
	if (_mtlBufferCache) getDevice()->removeResidency(_mtlBufferCache);
	[_mtlBufferCache release];
	_mtlBufferCache = nil;
    [_mtlHeap release];
    _mtlHeap = nil;
}


#pragma mark -
#pragma mark MVKBufferView

void MVKBufferView::propagateDebugName() {
	setMetalObjectLabel(_mtlTexture, _debugName);
}

#pragma mark Metal

id<MTLTexture> MVKBufferView::getMTLTexture() {
	auto& mtlFeats = getMetalFeatures();
    if ( !_mtlTexture && _mtlPixelFormat && mtlFeats.texelBuffers) {

		// Lock and check again in case another thread has created the texture.
		lock_guard<mutex> lock(_lock);
		if (_mtlTexture) { return _mtlTexture; }

        MTLTextureUsage usage = MTLTextureUsageShaderRead;
        if ( mvkIsAnyFlagEnabled(_usage, VK_BUFFER_USAGE_2_STORAGE_TEXEL_BUFFER_BIT) ) {
			usage |= MTLTextureUsageShaderWrite;
#if MVK_XCODE_15
			if (getMetalFeatures().nativeTextureAtomics && (_mtlPixelFormat == MTLPixelFormatR32Sint || _mtlPixelFormat == MTLPixelFormatR32Uint))
				usage |= MTLTextureUsageShaderAtomic;
#endif
        }
        id<MTLBuffer> mtlBuff;
        VkDeviceSize mtlBuffOffset;
        if ( !mtlFeats.sharedLinearTextures && _buffer->isMemoryHostCoherent() ) {
            mtlBuff = _buffer->getMTLBufferCache();
            mtlBuffOffset = _offset;
        } else {
            mtlBuff = _buffer->getMTLBuffer();
            mtlBuffOffset = _buffer->getMTLBufferOffset() + _offset;
        }
        MTLTextureDescriptor* mtlTexDesc;
        if ( mtlFeats.textureBuffers ) {
            mtlTexDesc = [MTLTextureDescriptor textureBufferDescriptorWithPixelFormat: _mtlPixelFormat
                                                                                width: _textureSize.width
                                                                      resourceOptions: (mtlBuff.cpuCacheMode << MTLResourceCPUCacheModeShift) | (mtlBuff.storageMode << MTLResourceStorageModeShift)
                                                                                usage: usage];
        } else {
            mtlTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _mtlPixelFormat
                                                                            width: _textureSize.width
                                                                           height: _textureSize.height
                                                                        mipmapped: NO];
            mtlTexDesc.storageMode = mtlBuff.storageMode;
            mtlTexDesc.cpuCacheMode = mtlBuff.cpuCacheMode;
            mtlTexDesc.usage = usage;
        }
		_mtlTexture = [mtlBuff newTextureWithDescriptor: mtlTexDesc
												 offset: mtlBuffOffset
											bytesPerRow: _mtlBytesPerRow];
		getDevice()->makeResident(_mtlTexture);
		propagateDebugName();
    }
    return _mtlTexture;
}


#pragma mark Construction

MVKBufferView::MVKBufferView(MVKDevice* device, const VkBufferViewCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	MVKPixelFormats* pixFmts = getPixelFormats();
    _buffer = (MVKBuffer*)pCreateInfo->buffer;
    _offset = pCreateInfo->offset;
    _mtlPixelFormat = pixFmts->getMTLPixelFormat(pCreateInfo->format);
    VkExtent2D fmtBlockSize = pixFmts->getBlockTexelSize(pCreateInfo->format);  // Pixel size of format
    size_t bytesPerBlock = pixFmts->getBytesPerBlock(pCreateInfo->format);
	_mtlTexture = nil;

	_usage = _buffer->getUsage();
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_BUFFER_USAGE_FLAGS_2_CREATE_INFO:
				// Buffer view usage should be a subset of the buffer usage.
				_usage &= ((VkBufferUsageFlags2CreateInfo*)next)->usage;
				break;
			default:
				break;
		}
	}

    // Layout texture as a 1D array of texel blocks (which are texels for non-compressed textures) that covers the bytes
    VkDeviceSize byteCount = pCreateInfo->range;
    if (byteCount == VK_WHOLE_SIZE) { byteCount = _buffer->getByteCount() - pCreateInfo->offset; }    // Remaining bytes in buffer
    size_t blockCount = byteCount / bytesPerBlock;

	auto& mtlFeats = getMetalFeatures();
	if ( !mtlFeats.textureBuffers ) {
		// But Metal requires the texture to be a 2D texture. Determine the number of 2D rows we need and their width.
		// Multiple rows will automatically align with PoT max texture dimension, but need to align upwards if less than full single row.
		size_t maxBlocksPerRow = mtlFeats.maxTextureDimension / fmtBlockSize.width;
		size_t blocksPerRow = min(blockCount, maxBlocksPerRow);
		_mtlBytesPerRow = mvkAlignByteCount(blocksPerRow * bytesPerBlock, _device->getVkFormatTexelBufferAlignment(pCreateInfo->format, this));

		size_t rowCount = blockCount / blocksPerRow;
		if (blockCount % blocksPerRow) { rowCount++; }

		_textureSize.width = uint32_t(blocksPerRow * fmtBlockSize.width);
		_textureSize.height = uint32_t(rowCount * fmtBlockSize.height);
	} else {
		// With native texture buffers we don't need to bother with any of that.
		// We can just use a simple 1D texel array.
		_textureSize.width = uint32_t(blockCount * fmtBlockSize.width);
		_textureSize.height = 1;
		_mtlBytesPerRow = mvkAlignByteCount(byteCount, _device->getVkFormatTexelBufferAlignment(pCreateInfo->format, this));
	}

    if ( !mtlFeats.texelBuffers ) {
        setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Texel buffers are not supported on this device."));
    }
}

// Memory detached in destructor too, as a fail-safe.
MVKBufferView::~MVKBufferView() {
	detachMemory();
}

// Overridden to detach from the resource memory when the app destroys this object.
// This object can be retained in a descriptor after the app destroys it, even
// though the descriptor can't use it. But doing so retains usuable resource memory.
void MVKBufferView::destroy() {
	detachMemory();
	MVKVulkanAPIDeviceObject::destroy();
}

// Potentially called twice, from destroy() and destructor, so ensure everything is nulled out.
void MVKBufferView::detachMemory() {
	if (_mtlTexture) getDevice()->removeResidency(_mtlTexture);
	[_mtlTexture release];
	_mtlTexture = nil;
}
