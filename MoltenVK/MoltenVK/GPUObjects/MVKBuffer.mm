/*
 * MVKBuffer.mm
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

#include "MVKBuffer.h"
#include "MVKCommandBuffer.h"
#include "MVKFoundation.h"
#include "MVKEnvironment.h"
#include "mvk_datatypes.hpp"

using namespace std;


#pragma mark -
#pragma mark MVKBuffer

void MVKBuffer::propogateDebugName() {
	if (!_debugName) { return; }
	if (_deviceMemory &&
		_deviceMemory->isDedicatedAllocation() &&
		_deviceMemory->_debugName.length == 0) {

		_deviceMemory->setDebugName(_debugName.UTF8String);
	}
	setLabelIfNotNil(_mtlBuffer, _debugName);
}


#pragma mark Resource memory

VkResult MVKBuffer::getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements) {
	if (_device->_pMetalFeatures->placementHeaps) {
		MTLSizeAndAlign sizeAndAlign = [_device->getMTLDevice() heapBufferSizeAndAlignWithLength: getByteCount() options: MTLResourceStorageModePrivate];
		pMemoryRequirements->size = sizeAndAlign.size;
		pMemoryRequirements->alignment = sizeAndAlign.align;
	} else {
		pMemoryRequirements->size = getByteCount();
		pMemoryRequirements->alignment = _byteAlignment;
	}
	pMemoryRequirements->memoryTypeBits = _device->getPhysicalDevice()->getAllMemoryTypes();
#if MVK_MACOS
	// Textures must not use shared memory
	if (mvkIsAnyFlagEnabled(_usage, VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT | VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT)) {
		mvkDisableFlag(pMemoryRequirements->memoryTypeBits, _device->getPhysicalDevice()->getHostCoherentMemoryTypes());
	}
#endif
#if MVK_IOS
	// Memoryless storage is not allowed for buffers
	mvkDisableFlag(pMemoryRequirements->memoryTypeBits, _device->getPhysicalDevice()->getLazilyAllocatedMemoryTypes());
#endif
	return VK_SUCCESS;
}

VkResult MVKBuffer::getMemoryRequirements(const void*, VkMemoryRequirements2* pMemoryRequirements) {
	pMemoryRequirements->sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
	getMemoryRequirements(&pMemoryRequirements->memoryRequirements);
	for (auto* next = (VkBaseOutStructure*)pMemoryRequirements->pNext; next; next = next->pNext) {
		switch (next->sType) {
		case VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS: {
			auto* dedicatedReqs = (VkMemoryDedicatedRequirements*)next;
			dedicatedReqs->prefersDedicatedAllocation = VK_FALSE;
			dedicatedReqs->requiresDedicatedAllocation = VK_FALSE;
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

	propogateDebugName();

	return _deviceMemory ? _deviceMemory->addBuffer(this) : VK_SUCCESS;
}

void MVKBuffer::applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
								   VkPipelineStageFlags dstStageMask,
								   VkMemoryBarrier* pMemoryBarrier,
                                   MVKCommandEncoder* cmdEncoder,
                                   MVKCommandUse cmdUse) {
#if MVK_MACOS
	if ( needsHostReadSync(srcStageMask, dstStageMask, pMemoryBarrier) ) {
		[cmdEncoder->getMTLBlitEncoder(cmdUse) synchronizeResource: getMTLBuffer()];
	}
#endif
}

void MVKBuffer::applyBufferMemoryBarrier(VkPipelineStageFlags srcStageMask,
										 VkPipelineStageFlags dstStageMask,
										 VkBufferMemoryBarrier* pBufferMemoryBarrier,
                                         MVKCommandEncoder* cmdEncoder,
                                         MVKCommandUse cmdUse) {
#if MVK_MACOS
	if ( needsHostReadSync(srcStageMask, dstStageMask, pBufferMemoryBarrier) ) {
		[cmdEncoder->getMTLBlitEncoder(cmdUse) synchronizeResource: getMTLBuffer()];
	}
#endif
}

// Returns whether the specified buffer memory barrier requires a sync between this
// buffer and host memory for the purpose of the host reading texture memory.
bool MVKBuffer::needsHostReadSync(VkPipelineStageFlags srcStageMask,
								  VkPipelineStageFlags dstStageMask,
								  VkBufferMemoryBarrier* pBufferMemoryBarrier) {
#if MVK_IOS
	return false;
#endif
#if MVK_MACOS
	return (mvkIsAnyFlagEnabled(dstStageMask, (VK_PIPELINE_STAGE_HOST_BIT)) &&
			mvkIsAnyFlagEnabled(pBufferMemoryBarrier->dstAccessMask, (VK_ACCESS_HOST_READ_BIT)) &&
			isMemoryHostAccessible() && !isMemoryHostCoherent());
#endif
}


#pragma mark Metal

id<MTLBuffer> MVKBuffer::getMTLBuffer() {
	if (_mtlBuffer) { return _mtlBuffer; }
	if (_deviceMemory) {
		if (_deviceMemory->getMTLHeap()) {
			_mtlBuffer = [_deviceMemory->getMTLHeap() newBufferWithLength: getByteCount()
																  options: _deviceMemory->getMTLResourceOptions()
																   offset: _deviceMemoryOffset];	// retained
			propogateDebugName();
			return _mtlBuffer;
		} else {
			return _deviceMemory->getMTLBuffer();
		}
	}
	return nil;
}


#pragma mark Construction

MVKBuffer::MVKBuffer(MVKDevice* device, const VkBufferCreateInfo* pCreateInfo) : MVKResource(device), _usage(pCreateInfo->usage) {
    _byteAlignment = _device->_pMetalFeatures->mtlBufferAlignment;
    _byteCount = pCreateInfo->size;
}

MVKBuffer::~MVKBuffer() {
	if (_deviceMemory) { _deviceMemory->removeBuffer(this); }
	if (_mtlBuffer) { [_mtlBuffer release]; }
}


#pragma mark -
#pragma mark MVKBufferView

void MVKBufferView::propogateDebugName() {
	setLabelIfNotNil(_mtlTexture, _debugName);
}

#pragma mark Metal

id<MTLTexture> MVKBufferView::getMTLTexture() {
    if ( !_mtlTexture && _mtlPixelFormat && _device->_pMetalFeatures->texelBuffers) {

		// Lock and check again in case another thread has created the texture.
		lock_guard<mutex> lock(_lock);
		if (_mtlTexture) { return _mtlTexture; }

        MTLTextureUsage usage = MTLTextureUsageShaderRead;
        if ( mvkIsAnyFlagEnabled(_buffer->getUsage(), VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT) ) {
            usage |= MTLTextureUsageShaderWrite;
        }
        id<MTLBuffer> mtlBuff = _buffer->getMTLBuffer();
        MTLTextureDescriptor* mtlTexDesc;
        if ( _device->_pMetalFeatures->textureBuffers ) {
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
												 offset: _mtlBufferOffset
											bytesPerRow: _mtlBytesPerRow];
		propogateDebugName();
    }
    return _mtlTexture;
}


#pragma mark Construction

MVKBufferView::MVKBufferView(MVKDevice* device, const VkBufferViewCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
    _buffer = (MVKBuffer*)pCreateInfo->buffer;
    _mtlBufferOffset = _buffer->getMTLBufferOffset() + pCreateInfo->offset;
    _mtlPixelFormat = getMTLPixelFormatFromVkFormat(pCreateInfo->format);
    VkExtent2D fmtBlockSize = mvkVkFormatBlockTexelSize(pCreateInfo->format);  // Pixel size of format
    size_t bytesPerBlock = mvkVkFormatBytesPerBlock(pCreateInfo->format);
	_mtlTexture = nil;

    // Layout texture as a 1D array of texel blocks (which are texels for non-compressed textures) that covers the bytes
    VkDeviceSize byteCount = pCreateInfo->range;
    if (byteCount == VK_WHOLE_SIZE) { byteCount = _buffer->getByteCount() - pCreateInfo->offset; }    // Remaining bytes in buffer
    size_t blockCount = byteCount / bytesPerBlock;

	if ( !_device->_pMetalFeatures->textureBuffers ) {
		// But Metal requires the texture to be a 2D texture. Determine the number of 2D rows we need and their width.
		// Multiple rows will automatically align with PoT max texture dimension, but need to align upwards if less than full single row.
		size_t maxBlocksPerRow = _device->_pMetalFeatures->maxTextureDimension / fmtBlockSize.width;
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
		_mtlBytesPerRow = byteCount;
	}

    if ( !_device->_pMetalFeatures->texelBuffers ) {
        setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Texel buffers are not supported on this device."));
    }
}

MVKBufferView::~MVKBufferView() {
    [_mtlTexture release];
    _mtlTexture = nil;
}

