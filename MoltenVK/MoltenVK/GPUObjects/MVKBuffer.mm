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
	if (_debugName &&
		_deviceMemory &&
		_deviceMemory->isDedicatedAllocation() &&
		_deviceMemory->_debugName.length == 0) {

		_deviceMemory->setDebugName(_debugName.UTF8String);
	}
}


#pragma mark Resource memory

VkResult MVKBuffer::getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements) {
	pMemoryRequirements->size = getByteCount();
	pMemoryRequirements->alignment = _byteAlignment;
	pMemoryRequirements->memoryTypeBits = _device->getPhysicalDevice()->getAllMemoryTypes();
#if MVK_IOS
	// Memoryless storage is not allowed for buffers
	mvkDisableFlag(pMemoryRequirements->memoryTypeBits, _device->getPhysicalDevice()->getLazilyAllocatedMemoryTypes());
#endif
	return VK_SUCCESS;
}

VkResult MVKBuffer::getMemoryRequirements(const void*, VkMemoryRequirements2* pMemoryRequirements) {
	pMemoryRequirements->sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
	getMemoryRequirements(&pMemoryRequirements->memoryRequirements);
	auto* next = (VkStructureType*)pMemoryRequirements->pNext;
	while (next) {
		switch (*next) {
		case VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS: {
			auto* dedicatedReqs = (VkMemoryDedicatedRequirements*)next;
			// TODO: Maybe someday we could do something with MTLHeaps
			// and allocate non-dedicated memory from them. For now, we
			// always prefer dedicated allocations.
			dedicatedReqs->prefersDedicatedAllocation = VK_TRUE;
			dedicatedReqs->requiresDedicatedAllocation = VK_FALSE;
			next = (VkStructureType*)dedicatedReqs->pNext;
			break;
		}
		default:
			next = (VkStructureType*)((VkMemoryRequirements2*)next)->pNext;
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

/**
 * Returns whether the specified buffer memory barrier requires a sync between this
 * buffer and host memory for the purpose of the host reading texture memory.
 */
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


#pragma mark Construction

MVKBuffer::MVKBuffer(MVKDevice* device, const VkBufferCreateInfo* pCreateInfo) : MVKResource(device), _usage(pCreateInfo->usage) {
    _byteAlignment = _device->_pMetalFeatures->mtlBufferAlignment;
    _byteCount = pCreateInfo->size;
}

MVKBuffer::~MVKBuffer() {
	if (_deviceMemory) { _deviceMemory->removeBuffer(this); }
}


#pragma mark -
#pragma mark MVKBufferView

void MVKBufferView::propogateDebugName() {
	setLabelIfNotNil(_mtlTexture, _debugName);
}

#pragma mark Metal

id<MTLTexture> MVKBufferView::getMTLTexture() {
    if ( !_mtlTexture && _mtlPixelFormat &&  _device->_pMetalFeatures->texelBuffers) {

		// Lock and check again in case another thread has created the texture.
		lock_guard<mutex> lock(_lock);
		if (_mtlTexture) { return _mtlTexture; }

        MTLTextureDescriptor* mtlTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _mtlPixelFormat
                                                                                              width: _textureSize.width
                                                                                             height: _textureSize.height
                                                                                          mipmapped: NO];
#if MVK_MACOS
        // Textures on Mac cannot use shared storage, so force managed.
        if (_buffer->getMTLBuffer().storageMode == MTLStorageModeShared) {
            mtlTexDesc.storageMode = MTLStorageModeManaged;
        } else {
            mtlTexDesc.storageMode = _buffer->getMTLBuffer().storageMode;
        }
#else
        mtlTexDesc.storageMode = _buffer->getMTLBuffer().storageMode;
#endif
        mtlTexDesc.cpuCacheMode = _buffer->getMTLBuffer().cpuCacheMode;
        mtlTexDesc.usage = MTLTextureUsageShaderRead;
        if ( mvkIsAnyFlagEnabled(_buffer->getUsage(), VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT) ) {
            mtlTexDesc.usage |= MTLTextureUsageShaderWrite;
        }
		_mtlTexture = [_buffer->getMTLBuffer() newTextureWithDescriptor: mtlTexDesc
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
    if (byteCount == VK_WHOLE_SIZE) { byteCount = _buffer->getByteCount() - _mtlBufferOffset; }    // Remaining bytes in buffer
    size_t blockCount = byteCount / bytesPerBlock;

	// But Metal requires the texture to be a 2D texture. Determine the number of 2D rows we need and their width.
	// Multiple rows will automatically align with PoT max texture dimension, but need to align upwards if less than full single row.
	size_t maxBlocksPerRow = _device->_pMetalFeatures->maxTextureDimension / fmtBlockSize.width;
	size_t blocksPerRow = min(blockCount, maxBlocksPerRow);
	_mtlBytesPerRow = mvkAlignByteOffset(blocksPerRow * bytesPerBlock, _device->getVkFormatTexelBufferAlignment(pCreateInfo->format));

	size_t rowCount = blockCount / blocksPerRow;
	if (blockCount % blocksPerRow) { rowCount++; }

	_textureSize.width = uint32_t(blocksPerRow * fmtBlockSize.width);
	_textureSize.height = uint32_t(rowCount * fmtBlockSize.height);

    if ( !_device->_pMetalFeatures->texelBuffers ) {
        setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Texel buffers are not supported on this device."));
    }
}

MVKBufferView::~MVKBufferView() {
    [_mtlTexture release];
    _mtlTexture = nil;
}

