/*
 * MVKBuffer.mm
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

#include "MVKBuffer.h"
#include "MVKCommandBuffer.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.h"

using namespace std;


#pragma mark -
#pragma mark MVKBuffer

#pragma mark Resource memory

VkResult MVKBuffer::getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements) {
	pMemoryRequirements->size = getByteCount();
	pMemoryRequirements->alignment = getByteAlignment();
	pMemoryRequirements->memoryTypeBits = _device->getPhysicalDevice()->getAllMemoryTypes();
	return VK_SUCCESS;
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
			_deviceMemory->isMemoryHostAccessible() && !_deviceMemory->isMemoryHostCoherent());
#endif
}

/** Called when the bound device memory is updated. Flushes any associated resource memory. */
VkResult MVKBuffer::flushToDevice(VkDeviceSize offset, VkDeviceSize size) {
    VkResult rslt = copyMTLBufferContent(offset, size, true);

#if MVK_MACOS
    if (_deviceMemory->getMTLStorageMode() == MTLStorageModeManaged) {
        [getMTLBuffer() didModifyRange: mtlBufferRange(offset, size)];
    }
#endif

    return rslt;
}

// Called when the bound device memory is invalidated. Pulls any associated resource memory from the device.
VkResult MVKBuffer::pullFromDevice(VkDeviceSize offset, VkDeviceSize size) {
    VkResult rslt = copyMTLBufferContent(offset, size, false);

    // If we are pulling to populate a newly created device memory MTLBuffer,
    // from a previously created local MTLBuffer, remove the local MTLBuffer.
	// Use autorelease in case the earlier MTLBuffer was encoded.
    if (_mtlBuffer && _deviceMemory->getMTLBuffer()) {
        [_mtlBuffer autorelease];
        _mtlBuffer = nil;
    }

    return rslt;
}

void* MVKBuffer::map(VkDeviceSize offset, VkDeviceSize size) {
    return (void*)((uintptr_t)getMTLBuffer().contents + mtlBufferRange(offset, size).location);
}

// Copies host content into or out of the MTLBuffer.
VkResult MVKBuffer::copyMTLBufferContent(VkDeviceSize offset, VkDeviceSize size, bool intoMTLBuffer) {

    // Only copy if there is separate host memory and this buffer overlaps the host memory range
    void* pMemBase = _deviceMemory->getLogicalMappedMemory();
    if (pMemBase && doesOverlap(offset, size)) {

        NSRange copyRange = mtlBufferRange(offset, size);
        VkDeviceSize memOffset = max(offset, _deviceMemoryOffset);

//        MVKLogDebug("Copying contents %s buffer %p at buffer offset %d memory offset %d and length %d.", (intoMTLBuffer ? "to" : "from"), this, copyRange.location, memOffset, copyRange.length);

        void* pMemBytes = (void*)((uintptr_t)pMemBase + memOffset);
        void* pMTLBuffBytes = (void*)((uintptr_t)getMTLBuffer().contents + copyRange.location);

        // Copy in the direction indicated.
        // Don't copy if the source and destination are the same address, which will
        // occur if the underlying MTLBuffer comes from the device memory object.
        if (pMemBytes != pMTLBuffBytes) {
//            MVKLogDebug("Copying buffer contents.");
            if (intoMTLBuffer) {
                memcpy(pMTLBuffBytes, pMemBytes, copyRange.length);
            } else {
                memcpy(pMemBytes, pMTLBuffBytes, copyRange.length);
            }
        }
    }

    return VK_SUCCESS;
}


#pragma mark Metal

// If a local MTLBuffer already exists, use it.
// If the device memory has a MTLBuffer, use it.
// Otherwise, create a new MTLBuffer and use it from now on.
id<MTLBuffer> MVKBuffer::getMTLBuffer() {

    if (_mtlBuffer) { return _mtlBuffer; }

    id<MTLBuffer> devMemMTLBuff = _deviceMemory->getMTLBuffer();
    if (devMemMTLBuff) { return devMemMTLBuff; }

	// Lock and check again in case another thread has created the buffer.
    lock_guard<mutex> lock(_lock);
    if (_mtlBuffer) { return _mtlBuffer; }
    
    NSUInteger mtlBuffLen = mvkAlignByteOffset(_byteCount, _byteAlignment);
    _mtlBuffer = [getMTLDevice() newBufferWithLength: mtlBuffLen
                                             options: _deviceMemory->getMTLResourceOptions()];     // retained
//    MVKLogDebug("MVKBuffer %p creating local MTLBuffer of size %d.", this, _mtlBuffer.length);
    return _mtlBuffer;
}

NSUInteger MVKBuffer::getMTLBufferOffset() { return _mtlBuffer ? 0 : _deviceMemoryOffset; }

// Returns an NSRange that maps the specified host memory range to the MTLBuffer.
NSRange MVKBuffer::mtlBufferRange(VkDeviceSize offset, VkDeviceSize size) {
    NSUInteger localRangeLoc = min((offset > _deviceMemoryOffset) ? (offset - _deviceMemoryOffset) : 0, _byteCount);
    NSUInteger localRangeLen = min(size, _byteCount - localRangeLoc);
    return NSMakeRange(getMTLBufferOffset() + localRangeLoc, localRangeLen);
}


#pragma mark Construction

MVKBuffer::MVKBuffer(MVKDevice* device, const VkBufferCreateInfo* pCreateInfo) : MVKResource(device) {
    _byteAlignment = _device->_pMetalFeatures->mtlBufferAlignment;
    _byteCount = pCreateInfo->size;
    _mtlBuffer = nil;
}

MVKBuffer::~MVKBuffer() {
    [_mtlBuffer release];
    _mtlBuffer = nil;
}


#pragma mark -
#pragma mark MVKBufferView


#pragma mark Metal

id<MTLTexture> MVKBufferView::getMTLTexture() {
    if ( !_mtlTexture && _mtlPixelFormat &&  _device->_pMetalFeatures->texelBuffers) {

		// Lock and check again in case another thread has created the texture.
		lock_guard<mutex> lock(_lock);
		if (_mtlTexture) { return _mtlTexture; }

        VkDeviceSize byteAlign = _device->_pProperties->limits.minTexelBufferOffsetAlignment;
        NSUInteger mtlByteCnt = mvkAlignByteOffset(_byteCount, byteAlign);
        MTLTextureDescriptor* mtlTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _mtlPixelFormat
                                                                                              width: _textureSize.width
                                                                                             height: _textureSize.height
                                                                                          mipmapped: NO];
        _mtlTexture = [getMTLBuffer() newTextureWithDescriptor: mtlTexDesc
                                                        offset: _mtlBufferOffset
                                                   bytesPerRow: mtlByteCnt];
    }
    return _mtlTexture;
}


#pragma mark Construction

MVKBufferView::MVKBufferView(MVKDevice* device, const VkBufferViewCreateInfo* pCreateInfo) : MVKBaseDeviceObject(device) {
    _buffer = (MVKBuffer*)pCreateInfo->buffer;
    _mtlBufferOffset = _buffer->getMTLBufferOffset() + pCreateInfo->offset;
    _mtlPixelFormat = mtlPixelFormatFromVkFormat(pCreateInfo->format);
    _mtlTexture = nil;
    VkExtent2D fmtBlockSize = mvkVkFormatBlockTexelSize(pCreateInfo->format);  // Pixel size of format
    size_t bytesPerBlock = mvkVkFormatBytesPerBlock(pCreateInfo->format);

    // Layout texture as a 1D array of texel blocks (which are texels for non-compressed textures) that covers the bytes
    _byteCount = pCreateInfo->range;
    if (_byteCount == VK_WHOLE_SIZE) { _byteCount = _buffer->getByteCount() - _mtlBufferOffset; }    // Remaining bytes in buffer
    size_t blockCount = _byteCount / bytesPerBlock;
    _byteCount = blockCount * bytesPerBlock;            // Round down

    _textureSize.width = (uint32_t)blockCount * fmtBlockSize.width;
    _textureSize.height = fmtBlockSize.height;

    if ( !_device->_pMetalFeatures->texelBuffers ) {
        setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "Texel buffers are not supported on this device."));
    }
}

MVKBufferView::~MVKBufferView() {
    [_mtlTexture release];
    _mtlTexture = nil;
}

