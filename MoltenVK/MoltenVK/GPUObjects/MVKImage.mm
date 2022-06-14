/*
 * MVKImage.mm
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKImage.h"
#include "MVKQueue.h"
#include "MVKSwapchain.h"
#include "MVKCommandBuffer.h"
#include "MVKCmdDebug.h"
#include "MVKEnvironment.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKCodec.h"
#import "MTLTextureDescriptor+MoltenVK.h"
#import "MTLSamplerDescriptor+MoltenVK.h"

using namespace std;
using namespace SPIRV_CROSS_NAMESPACE;

#pragma mark -
#pragma mark MVKImagePlane

MVKVulkanAPIObject* MVKImagePlane::getVulkanAPIObject() { return _image; }

id<MTLTexture> MVKImagePlane::getMTLTexture() {
    if ( !_mtlTexture && _image->_vkFormat ) {
        // Lock and check again in case another thread has created the texture.
        lock_guard<mutex> lock(_image->_lock);
        if (_mtlTexture) { return _mtlTexture; }

        MTLTextureDescriptor* mtlTexDesc = newMTLTextureDescriptor();    // temp retain
        MVKImageMemoryBinding* memoryBinding = getMemoryBinding();
		MVKDeviceMemory* dvcMem = memoryBinding->_deviceMemory;

        if (_image->_ioSurface) {
            _mtlTexture = [_image->getMTLDevice()
                           newTextureWithDescriptor: mtlTexDesc
                           iosurface: _image->_ioSurface
                           plane: _planeIndex];
        } else if (memoryBinding->_mtlTexelBuffer) {
            _mtlTexture = [memoryBinding->_mtlTexelBuffer
                           newTextureWithDescriptor: mtlTexDesc
                           offset: memoryBinding->_mtlTexelBufferOffset + _subresources[0].layout.offset
                           bytesPerRow: _subresources[0].layout.rowPitch];
        } else if (dvcMem && dvcMem->getMTLHeap() && !_image->getIsDepthStencil()) {
            // Metal support for depth/stencil from heaps is flaky
            _mtlTexture = [dvcMem->getMTLHeap()
                           newTextureWithDescriptor: mtlTexDesc
                           offset: memoryBinding->getDeviceMemoryOffset() + _subresources[0].layout.offset];
            if (_image->_isAliasable) { [_mtlTexture makeAliasable]; }
        } else if (_image->_isAliasable && dvcMem && dvcMem->isDedicatedAllocation() &&
            !contains(dvcMem->_imageMemoryBindings, memoryBinding)) {
            // This is a dedicated allocation, but it belongs to another aliasable image.
            // In this case, use the MTLTexture from the memory's dedicated image.
            // We know the other image must be aliasable, or I couldn't have been bound
            // to its memory: the memory object wouldn't allow it.
            _mtlTexture = [dvcMem->_imageMemoryBindings[0]->_image->getMTLTexture(_planeIndex, mtlTexDesc.pixelFormat) retain];
        } else {
            _mtlTexture = [_image->getMTLDevice() newTextureWithDescriptor: mtlTexDesc];
        }

        [mtlTexDesc release];                                            // temp release

        propagateDebugName();
    }
    return _mtlTexture;
}

id<MTLTexture> MVKImagePlane::getMTLTexture(MTLPixelFormat mtlPixFmt) {
    // Note: Retrieve the base texture outside of lock to avoid deadlock if it too needs to be lazily created.
    // Delegate to _image in case the method is overriden. (e.g. if it's a swapchain image)
    if (mtlPixFmt == _mtlPixFmt) { return _image->getMTLTexture(_planeIndex); }
    id<MTLTexture> mtlTex = _mtlTextureViews[mtlPixFmt];
    if ( !mtlTex ) {
        // Lock and check again in case another thread has created the view texture.
        id<MTLTexture> baseTexture = _image->getMTLTexture(_planeIndex);
        lock_guard<mutex> lock(_image->_lock);
        mtlTex = _mtlTextureViews[mtlPixFmt];
        if ( !mtlTex ) {
            mtlTex = [baseTexture newTextureViewWithPixelFormat: mtlPixFmt];    // retained
            _mtlTextureViews[mtlPixFmt] = mtlTex;
        }
    }
    return mtlTex;
}

void MVKImagePlane::releaseMTLTexture() {
    [_mtlTexture release];
    _mtlTexture = nil;

    for (auto elem : _mtlTextureViews) {
        [elem.second release];
    }
    _mtlTextureViews.clear();
}

// Returns a Metal texture descriptor constructed from the properties of this image.
// It is the caller's responsibility to release the returned descriptor object.
MTLTextureDescriptor* MVKImagePlane::newMTLTextureDescriptor() {

	// Metal before 3.0 doesn't support 3D compressed textures, so we'll decompress
	// the texture ourselves. This, then, is the *uncompressed* format.
	bool shouldSubFmt = MVK_MACOS && _image->_is3DCompressed;
	MTLPixelFormat mtlPixFmt = shouldSubFmt ? MTLPixelFormatBGRA8Unorm : _mtlPixFmt;

    VkExtent3D extent = _image->getExtent3D(_planeIndex, 0);
    MTLTextureDescriptor* mtlTexDesc = [MTLTextureDescriptor new];    // retained
    mtlTexDesc.pixelFormat = mtlPixFmt;
    mtlTexDesc.textureType = _image->_mtlTextureType;
    mtlTexDesc.width = extent.width;
    mtlTexDesc.height = extent.height;
    mtlTexDesc.depth = extent.depth;
    mtlTexDesc.mipmapLevelCount = _image->_mipLevels;
    mtlTexDesc.sampleCount = mvkSampleCountFromVkSampleCountFlagBits(_image->_samples);
    mtlTexDesc.arrayLength = _image->_arrayLayers;
	mtlTexDesc.usageMVK = _image->getMTLTextureUsage(mtlPixFmt);
    mtlTexDesc.storageModeMVK = _image->getMTLStorageMode();
    mtlTexDesc.cpuCacheMode = _image->getMTLCPUCacheMode();

    return mtlTexDesc;
}

// Initializes the subresource definitions.
void MVKImagePlane::initSubresources(const VkImageCreateInfo* pCreateInfo) {
    _subresources.reserve(_image->_mipLevels * _image->_arrayLayers);

    MVKImageSubresource subRez;
    subRez.subresource.aspectMask = VK_IMAGE_ASPECT_PLANE_0_BIT << _planeIndex;
    subRez.layoutState = pCreateInfo->initialLayout;

    VkDeviceSize offset = 0;
    if (_planeIndex > 0 && _image->_memoryBindings.size() == 1) {
        if (!_image->_isLinear && _image->getDevice()->_pMetalFeatures->placementHeaps) {
            // For textures allocated directly on the heap, we need to obey the size and alignment
            // requirements reported by the device.
            MTLTextureDescriptor* mtlTexDesc = _image->_planes[_planeIndex-1]->newMTLTextureDescriptor();    // temp retain
            MTLSizeAndAlign sizeAndAlign = [_image->getMTLDevice() heapTextureSizeAndAlignWithDescriptor: mtlTexDesc];
            [mtlTexDesc release];                                                                            // temp release
            VkSubresourceLayout& firstLayout = _image->_planes[_planeIndex-1]->_subresources[0].layout;
            offset = firstLayout.offset + sizeAndAlign.size;
            mtlTexDesc = newMTLTextureDescriptor();                                                          // temp retain
            sizeAndAlign = [_image->getMTLDevice() heapTextureSizeAndAlignWithDescriptor: mtlTexDesc];
            [mtlTexDesc release];                                                                            // temp release
            offset = mvkAlignByteRef(offset, sizeAndAlign.align);
        } else {
            auto subresources = &_image->_planes[_planeIndex-1]->_subresources;
            VkSubresourceLayout& lastLayout = (*subresources)[subresources->size()-1].layout;
            offset = lastLayout.offset+lastLayout.size;
        }
    }

    for (uint32_t mipLvl = 0; mipLvl < _image->_mipLevels; mipLvl++) {
        subRez.subresource.mipLevel = mipLvl;
        VkDeviceSize rowPitch = _image->getBytesPerRow(_planeIndex, mipLvl);
        VkDeviceSize depthPitch = _image->getBytesPerLayer(_planeIndex, mipLvl);

        VkExtent3D mipExtent = _image->getExtent3D(_planeIndex, mipLvl);
        
        for (uint32_t layer = 0; layer < _image->_arrayLayers; layer++) {
            subRez.subresource.arrayLayer = layer;

            VkSubresourceLayout& layout = subRez.layout;
            layout.offset = offset;
            layout.size = depthPitch * mipExtent.depth;
            
            layout.rowPitch = rowPitch;
            layout.depthPitch = depthPitch;

            _subresources.push_back(subRez);
            offset += layout.size;
        }
    }
}

// Returns a pointer to the internal subresource for the specified MIP level layer.
MVKImageSubresource* MVKImagePlane::getSubresource(uint32_t mipLevel, uint32_t arrayLayer) {
    uint32_t srIdx = (mipLevel * _image->_arrayLayers) + arrayLayer;
    return (srIdx < _subresources.size()) ? &_subresources[srIdx] : NULL;
}

// Updates the contents of the underlying MTLTexture, corresponding to the
// specified subresource definition, from the underlying memory buffer.
void MVKImagePlane::updateMTLTextureContent(MVKImageSubresource& subresource,
                                            VkDeviceSize offset, VkDeviceSize size) {

    VkImageSubresource& imgSubRez = subresource.subresource;
    VkSubresourceLayout& imgLayout = subresource.layout;
    size = getMemoryBinding()->getDeviceMemory()->adjustMemorySize(size, offset);
    // Check if subresource overlaps the memory range.
	if ( !overlaps(imgLayout, offset, size) ) { return; }

    // Don't update if host memory has not been mapped yet.
    void* pHostMem = getMemoryBinding()->getHostMemoryAddress();
    if ( !pHostMem ) { return; }

    VkExtent3D mipExtent = _image->getExtent3D(_planeIndex, imgSubRez.mipLevel);
    void* pImgBytes = (void*)((uintptr_t)pHostMem + imgLayout.offset);

    MTLRegion mtlRegion;
    mtlRegion.origin = MTLOriginMake(0, 0, 0);
    mtlRegion.size = mvkMTLSizeFromVkExtent3D(mipExtent);

#if MVK_MACOS
    std::unique_ptr<char[]> decompBuffer;
    if (_image->_is3DCompressed) {
        // We cannot upload the texture data directly in this case. But we
        // can upload the decompressed image data.
        std::unique_ptr<MVKCodec> codec = mvkCreateCodec(_image->getVkFormat());
        if (!codec) {
            _image->reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "A 3D texture used a compressed format that MoltenVK does not yet support.");
            return;
        }
        VkSubresourceLayout destLayout;
        destLayout.rowPitch = 4 * mipExtent.width;
        destLayout.depthPitch = destLayout.rowPitch * mipExtent.height;
        destLayout.size = destLayout.depthPitch * mipExtent.depth;
        decompBuffer = std::unique_ptr<char[]>(new char[destLayout.size]);
        codec->decompress(decompBuffer.get(), pImgBytes, destLayout, imgLayout, mipExtent);
        pImgBytes = decompBuffer.get();
        imgLayout = destLayout;
    }
#endif

    VkImageType imgType = _image->getImageType();
    VkDeviceSize bytesPerRow = (imgType != VK_IMAGE_TYPE_1D) ? imgLayout.rowPitch : 0;
    VkDeviceSize bytesPerImage = (imgType == VK_IMAGE_TYPE_3D) ? imgLayout.depthPitch : 0;

    id<MTLTexture> mtlTex = getMTLTexture();
    if (_image->getPixelFormats()->isPVRTCFormat(mtlTex.pixelFormat)) {
        bytesPerRow = 0;
        bytesPerImage = 0;
    }

    [mtlTex replaceRegion: mtlRegion
              mipmapLevel: imgSubRez.mipLevel
                    slice: imgSubRez.arrayLayer
                withBytes: pImgBytes
              bytesPerRow: bytesPerRow
            bytesPerImage: bytesPerImage];
}

// Updates the contents of the underlying memory buffer from the contents of
// the underlying MTLTexture, corresponding to the specified subresource definition.
void MVKImagePlane::getMTLTextureContent(MVKImageSubresource& subresource,
                                         VkDeviceSize offset, VkDeviceSize size) {

    VkImageSubresource& imgSubRez = subresource.subresource;
    VkSubresourceLayout& imgLayout = subresource.layout;

    // Check if subresource overlaps the memory range.
    if ( !overlaps(imgLayout, offset, size) ) { return; }

    // Don't update if host memory has not been mapped yet.
    void* pHostMem = getMemoryBinding()->getHostMemoryAddress();
    if ( !pHostMem ) { return; }

    VkExtent3D mipExtent = _image->getExtent3D(_planeIndex, imgSubRez.mipLevel);
    void* pImgBytes = (void*)((uintptr_t)pHostMem + imgLayout.offset);

    MTLRegion mtlRegion;
    mtlRegion.origin = MTLOriginMake(0, 0, 0);
    mtlRegion.size = mvkMTLSizeFromVkExtent3D(mipExtent);

    VkImageType imgType = _image->getImageType();
    VkDeviceSize bytesPerRow = (imgType != VK_IMAGE_TYPE_1D) ? imgLayout.rowPitch : 0;
    VkDeviceSize bytesPerImage = (imgType == VK_IMAGE_TYPE_3D) ? imgLayout.depthPitch : 0;

    [_mtlTexture getBytes: pImgBytes
              bytesPerRow: bytesPerRow
            bytesPerImage: bytesPerImage
               fromRegion: mtlRegion
              mipmapLevel: imgSubRez.mipLevel
                    slice: imgSubRez.arrayLayer];
}

// Returns whether subresource layout overlaps the memory range.
bool MVKImagePlane::overlaps(VkSubresourceLayout& imgLayout, VkDeviceSize offset, VkDeviceSize size) {
	VkDeviceSize memStart = offset;
	VkDeviceSize memEnd = offset + size;
	VkDeviceSize imgStart = getMemoryBinding()->_deviceMemoryOffset + imgLayout.offset;
	VkDeviceSize imgEnd = imgStart + imgLayout.size;
	return imgStart < memEnd && imgEnd > memStart;
}

void MVKImagePlane::propagateDebugName() {
    setLabelIfNotNil(_image->_planes[_planeIndex]->_mtlTexture, _image->_debugName);
}

MVKImageMemoryBinding* MVKImagePlane::getMemoryBinding() const {
    return (_image->_memoryBindings.size() > 1) ? _image->_memoryBindings[_planeIndex] : _image->_memoryBindings[0];
}

void MVKImagePlane::applyImageMemoryBarrier(VkPipelineStageFlags srcStageMask,
											VkPipelineStageFlags dstStageMask,
											MVKPipelineBarrier& barrier,
											MVKCommandEncoder* cmdEncoder,
											MVKCommandUse cmdUse) {

	// Extract the mipmap levels that are to be updated
	uint32_t mipLvlStart = barrier.baseMipLevel;
	uint32_t mipLvlEnd = (barrier.levelCount == (uint8_t)VK_REMAINING_MIP_LEVELS
						  ? _image->getMipLevelCount()
						  : (mipLvlStart + barrier.levelCount));

	// Extract the cube or array layers (slices) that are to be updated
	uint32_t layerStart = barrier.baseArrayLayer;
	uint32_t layerEnd = (barrier.layerCount == (uint16_t)VK_REMAINING_ARRAY_LAYERS
						 ? _image->getLayerCount()
						 : (layerStart + barrier.layerCount));

	MVKImageMemoryBinding* memBind = getMemoryBinding();
	bool needsSync = memBind->needsHostReadSync(srcStageMask, dstStageMask, barrier);
	bool needsPull = ((!memBind->_mtlTexelBuffer || memBind->_ownsTexelBuffer) &&
					  memBind->isMemoryHostCoherent() &&
					  barrier.newLayout == VK_IMAGE_LAYOUT_GENERAL &&
					  mvkIsAnyFlagEnabled(barrier.dstAccessMask, (VK_ACCESS_HOST_READ_BIT | VK_ACCESS_MEMORY_READ_BIT)));
	MVKDeviceMemory* dvcMem = memBind->getDeviceMemory();
	const MVKMappedMemoryRange& mappedRange = dvcMem ? dvcMem->getMappedRange() : MVKMappedMemoryRange();

	// Iterate across mipmap levels and layers, and update the image layout state for each
	for (uint32_t mipLvl = mipLvlStart; mipLvl < mipLvlEnd; mipLvl++) {
		for (uint32_t layer = layerStart; layer < layerEnd; layer++) {
			MVKImageSubresource* pImgRez = getSubresource(mipLvl, layer);
			if (pImgRez) { pImgRez->layoutState = barrier.newLayout; }
			if (needsSync) {
#if MVK_MACOS
				[cmdEncoder->getMTLBlitEncoder(cmdUse) synchronizeTexture: getMTLTexture() slice: layer level: mipLvl];
#endif
			}
			// Check if image content should be pulled into host-mapped device memory after
			// the GPU is done with it. This only applies if the image is intended to be
			// host-coherent, is not using a texel buffer, is transitioning to host-readable,
			// AND the device memory has an already-open memory mapping. If a memory mapping is
			// created later, it will pull the image contents in at that time, so it is not needed now.
			// The mapped range will be {0,0} if device memory is not currently mapped.
			if (needsPull && pImgRez && overlaps(pImgRez->layout, mappedRange.offset, mappedRange.size)) {
				pullFromDeviceOnCompletion(cmdEncoder, *pImgRez, mappedRange);
			}
		}
	}
}

// Once the command buffer completes, pull the content of the subresource into host memory.
// This is only necessary when the image memory is intended to be host-coherent, and the
// device memory is currently mapped to host memory
void MVKImagePlane::pullFromDeviceOnCompletion(MVKCommandEncoder* cmdEncoder,
											   MVKImageSubresource& subresource,
											   const MVKMappedMemoryRange& mappedRange) {

	[cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mcb) {
		getMTLTextureContent(subresource, mappedRange.offset, mappedRange.size);
	}];
}

MVKImagePlane::MVKImagePlane(MVKImage* image, uint8_t planeIndex) {
    _image = image;
    _planeIndex = planeIndex;
    _mtlTexture = nil;
}

MVKImagePlane::~MVKImagePlane() {
    releaseMTLTexture();
}


#pragma mark -
#pragma mark MVKImageMemoryBinding

VkResult MVKImageMemoryBinding::getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements) {
    pMemoryRequirements->size = _byteCount;
    pMemoryRequirements->alignment = _byteAlignment;
    return VK_SUCCESS;
}

VkResult MVKImageMemoryBinding::getMemoryRequirements(const void*, VkMemoryRequirements2* pMemoryRequirements) {
    pMemoryRequirements->sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
    for (auto* next = (VkBaseOutStructure*)pMemoryRequirements->pNext; next; next = next->pNext) {
        switch (next->sType) {
        case VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS: {
            auto* dedicatedReqs = (VkMemoryDedicatedRequirements*)next;
            bool writable = mvkIsAnyFlagEnabled(_image->getCombinedUsage(), VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT);
            bool canUseTexelBuffer = _device->_pMetalFeatures->texelBuffers && _image->_isLinear && !_image->getIsCompressed();
            dedicatedReqs->requiresDedicatedAllocation = _requiresDedicatedMemoryAllocation;
            dedicatedReqs->prefersDedicatedAllocation = (dedicatedReqs->requiresDedicatedAllocation ||
                                                        (!canUseTexelBuffer && (writable || !_device->_pMetalFeatures->placementHeaps)));
            break;
        }
        default:
            break;
        }
    }
    return VK_SUCCESS;
}

// Memory may have been mapped before image was bound, and needs to be loaded into the MTLTexture.
VkResult MVKImageMemoryBinding::bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) {
    if (_deviceMemory) { _deviceMemory->removeImageMemoryBinding(this); }
    MVKResource::bindDeviceMemory(mvkMem, memOffset);

    bool usesTexelBuffer = _device->_pMetalFeatures->texelBuffers && _deviceMemory; // Texel buffers available
    usesTexelBuffer = usesTexelBuffer && (isMemoryHostAccessible() || _device->_pMetalFeatures->placementHeaps) && _image->_isLinear && !_image->getIsCompressed(); // Applicable memory layout

    // macOS before 10.15.5 cannot use shared memory for texel buffers.
    usesTexelBuffer = usesTexelBuffer && (_device->_pMetalFeatures->sharedLinearTextures || !isMemoryHostCoherent());

    if (_image->_isLinearForAtomics || (usesTexelBuffer && _device->_pMetalFeatures->placementHeaps)) {
        if (usesTexelBuffer && _deviceMemory->ensureMTLBuffer()) {
            _mtlTexelBuffer = _deviceMemory->_mtlBuffer;
            _mtlTexelBufferOffset = getDeviceMemoryOffset();
        } else {
            // Create our own buffer for this.
            if (_deviceMemory && _deviceMemory->_mtlHeap && _image->getMTLStorageMode() == _deviceMemory->_mtlStorageMode) {
                _mtlTexelBuffer = [_deviceMemory->_mtlHeap newBufferWithLength: _byteCount options: _deviceMemory->getMTLResourceOptions() offset: getDeviceMemoryOffset()];
                if (_image->_isAliasable) { [_mtlTexelBuffer makeAliasable]; }
            } else {
                _mtlTexelBuffer = [getMTLDevice() newBufferWithLength: _byteCount options: _image->getMTLStorageMode() << MTLResourceStorageModeShift];
            }
            if (!_mtlTexelBuffer) {
                return reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not create an MTLBuffer for an image that requires a buffer backing store. Images that can be used for atomic accesses must have a texel buffer backing them.");
            }
            _mtlTexelBufferOffset = 0;
            _ownsTexelBuffer = true;
        }
    } else if (usesTexelBuffer && _deviceMemory->_mtlBuffer) {
        _mtlTexelBuffer = _deviceMemory->_mtlBuffer;
        _mtlTexelBufferOffset = getDeviceMemoryOffset();
    }

    flushToDevice(getDeviceMemoryOffset(), getByteCount());
    return _deviceMemory ? _deviceMemory->addImageMemoryBinding(this) : VK_SUCCESS;
}

void MVKImageMemoryBinding::applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
                                               VkPipelineStageFlags dstStageMask,
                                               MVKPipelineBarrier& barrier,
                                               MVKCommandEncoder* cmdEncoder,
                                               MVKCommandUse cmdUse) {
#if MVK_MACOS
    if ( needsHostReadSync(srcStageMask, dstStageMask, barrier) ) {
        for(uint8_t planeIndex = beginPlaneIndex(); planeIndex < endPlaneIndex(); planeIndex++) {
            [cmdEncoder->getMTLBlitEncoder(cmdUse) synchronizeResource: _image->_planes[planeIndex]->_mtlTexture];
        }
    }
#endif
}

void MVKImageMemoryBinding::propagateDebugName() {
    for(uint8_t planeIndex = beginPlaneIndex(); planeIndex < endPlaneIndex(); planeIndex++) {
        _image->_planes[planeIndex]->propagateDebugName();
    }
    if (_ownsTexelBuffer) {
        setLabelIfNotNil(_mtlTexelBuffer, _image->_debugName);
    }
}

// Returns whether the specified image memory barrier requires a sync between this
// texture and host memory for the purpose of the host reading texture memory.
bool MVKImageMemoryBinding::needsHostReadSync(VkPipelineStageFlags srcStageMask,
                                              VkPipelineStageFlags dstStageMask,
                                              MVKPipelineBarrier& barrier) {
#if MVK_MACOS
    return ((barrier.newLayout == VK_IMAGE_LAYOUT_GENERAL) &&
            mvkIsAnyFlagEnabled(barrier.dstAccessMask, (VK_ACCESS_HOST_READ_BIT | VK_ACCESS_MEMORY_READ_BIT)) &&
            isMemoryHostAccessible() && (!_device->_pMetalFeatures->sharedLinearTextures || !isMemoryHostCoherent()));
#endif
#if MVK_IOS_OR_TVOS
    return false;
#endif
}

bool MVKImageMemoryBinding::shouldFlushHostMemory() { return isMemoryHostAccessible() && (!_mtlTexelBuffer || _ownsTexelBuffer); }

// Flushes the device memory at the specified memory range into the MTLTexture. Updates
// all subresources that overlap the specified range and are in an updatable layout state.
VkResult MVKImageMemoryBinding::flushToDevice(VkDeviceSize offset, VkDeviceSize size) {
    if (shouldFlushHostMemory()) {
        for(uint8_t planeIndex = beginPlaneIndex(); planeIndex < endPlaneIndex(); planeIndex++) {
            for (auto& subRez : _image->_planes[planeIndex]->_subresources) {
                switch (subRez.layoutState) {
                    case VK_IMAGE_LAYOUT_UNDEFINED:
                    case VK_IMAGE_LAYOUT_PREINITIALIZED:
                    case VK_IMAGE_LAYOUT_GENERAL: {
                        _image->_planes[planeIndex]->updateMTLTextureContent(subRez, offset, size);
                        break;
                    }
                    default:
                        break;
                }
            }
        }
    }
    return VK_SUCCESS;
}

// Pulls content from the MTLTexture into the device memory at the specified memory range.
// Pulls from all subresources that overlap the specified range and are in an updatable layout state.
VkResult MVKImageMemoryBinding::pullFromDevice(VkDeviceSize offset, VkDeviceSize size) {
    if (shouldFlushHostMemory()) {
        for(uint8_t planeIndex = beginPlaneIndex(); planeIndex < endPlaneIndex(); planeIndex++) {
            for (auto& subRez : _image->_planes[planeIndex]->_subresources) {
                switch (subRez.layoutState) {
                    case VK_IMAGE_LAYOUT_GENERAL: {
                        _image->_planes[planeIndex]->getMTLTextureContent(subRez, offset, size);
                        break;
                    }
                    default:
                        break;
                }
            }
        }
    }
    return VK_SUCCESS;
}

uint8_t MVKImageMemoryBinding::beginPlaneIndex() const {
    return (_image->_memoryBindings.size() > 1) ? _planeIndex : 0;
}

uint8_t MVKImageMemoryBinding::endPlaneIndex() const {
    return (_image->_memoryBindings.size() > 1) ? _planeIndex : (uint8_t)_image->_memoryBindings.size();
}

MVKImageMemoryBinding::MVKImageMemoryBinding(MVKDevice* device, MVKImage* image, uint8_t planeIndex) : MVKResource(device), _image(image), _planeIndex(planeIndex) {
}

MVKImageMemoryBinding::~MVKImageMemoryBinding() {
    if (_deviceMemory) { _deviceMemory->removeImageMemoryBinding(this); }
    if (_ownsTexelBuffer) { [_mtlTexelBuffer release]; }
}


#pragma mark MVKImage

uint8_t MVKImage::getPlaneFromVkImageAspectFlags(VkImageAspectFlags aspectMask) {
    return (aspectMask & VK_IMAGE_ASPECT_PLANE_2_BIT) ? 2 :
           (aspectMask & VK_IMAGE_ASPECT_PLANE_1_BIT) ? 1 :
           0;
}

void MVKImage::propagateDebugName() {
    for (uint8_t planeIndex = 0; planeIndex < _planes.size(); planeIndex++) {
        _planes[planeIndex]->propagateDebugName();
    }
}

void MVKImage::flushToDevice(VkDeviceSize offset, VkDeviceSize size) {
    for (int bindingIndex = 0; bindingIndex < _memoryBindings.size(); bindingIndex++) {
        MVKImageMemoryBinding *binding = _memoryBindings[bindingIndex];
        binding->flushToDevice(offset, size);
    }
}

VkImageType MVKImage::getImageType() { return mvkVkImageTypeFromMTLTextureType(_mtlTextureType); }

bool MVKImage::getIsDepthStencil() { return getPixelFormats()->getFormatType(_vkFormat) == kMVKFormatDepthStencil; }

bool MVKImage::getIsCompressed() { return getPixelFormats()->getFormatType(_vkFormat) == kMVKFormatCompressed; }

VkExtent3D MVKImage::getExtent3D(uint8_t planeIndex, uint32_t mipLevel) {
    VkExtent3D extent = _extent;
    if (_hasChromaSubsampling && planeIndex > 0) {
        extent.width /= _planes[planeIndex]->_blockTexelSize.width;
        extent.height /= _planes[planeIndex]->_blockTexelSize.height;
    }
	return mvkMipmapLevelSizeFromBaseSize3D(extent, mipLevel);
}

VkDeviceSize MVKImage::getBytesPerRow(uint8_t planeIndex, uint32_t mipLevel) {
    MTLPixelFormat planeMTLPixFmt = getPixelFormats()->getChromaSubsamplingPlaneMTLPixelFormat(_vkFormat, planeIndex);
    size_t bytesPerRow = getPixelFormats()->getBytesPerRow(planeMTLPixFmt, getExtent3D(planeIndex, mipLevel).width);
    return mvkAlignByteCount(bytesPerRow, _rowByteAlignment);
}

VkDeviceSize MVKImage::getBytesPerLayer(uint8_t planeIndex, uint32_t mipLevel) {
    MTLPixelFormat planeMTLPixFmt = getPixelFormats()->getChromaSubsamplingPlaneMTLPixelFormat(_vkFormat, planeIndex);
    VkExtent3D extent = getExtent3D(planeIndex, mipLevel);
    size_t bytesPerRow = getBytesPerRow(planeIndex, mipLevel);
    return getPixelFormats()->getBytesPerLayer(planeMTLPixFmt, bytesPerRow, extent.height);
}

VkResult MVKImage::getSubresourceLayout(const VkImageSubresource* pSubresource,
										VkSubresourceLayout* pLayout) {
    uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(pSubresource->aspectMask);
    MVKImageSubresource* pImgRez = _planes[planeIndex]->getSubresource(pSubresource->mipLevel, pSubresource->arrayLayer);
    if ( !pImgRez ) { return VK_INCOMPLETE; }

    *pLayout = pImgRez->layout;
    return VK_SUCCESS;
}

void MVKImage::getTransferDescriptorData(MVKImageDescriptorData& imgData) {
    imgData.imageType = getImageType();
    imgData.format = getVkFormat();
    imgData.extent = _extent;
    imgData.mipLevels = _mipLevels;
    imgData.arrayLayers = _arrayLayers;
    imgData.samples = _samples;
    imgData.usage = getCombinedUsage();
}

// Returns whether an MVKImageView can have the specified format.
// If the list of pre-declared view formats is not empty,
// and the format is not on that list, the view format is not valid.
bool MVKImage::getIsValidViewFormat(VkFormat viewFormat) {
	for (VkFormat viewFmt : _viewFormats) {
		if (viewFormat == viewFmt) { return true; }
	}
	return _viewFormats.empty();
}


#pragma mark Resource memory

void MVKImage::applyImageMemoryBarrier(VkPipelineStageFlags srcStageMask,
									   VkPipelineStageFlags dstStageMask,
									   MVKPipelineBarrier& barrier,
									   MVKCommandEncoder* cmdEncoder,
									   MVKCommandUse cmdUse) {

	for (uint8_t planeIndex = 0; planeIndex < _planes.size(); planeIndex++) {
		if ( !_hasChromaSubsampling || mvkIsAnyFlagEnabled(barrier.aspectMask, (VK_IMAGE_ASPECT_PLANE_0_BIT << planeIndex)) ) {
			_planes[planeIndex]->applyImageMemoryBarrier(srcStageMask, dstStageMask, barrier, cmdEncoder, cmdUse);
		}
    }
}

VkResult MVKImage::getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements, uint8_t planeIndex) {
    pMemoryRequirements->memoryTypeBits = (_isDepthStencilAttachment)
                                          ? getPhysicalDevice()->getPrivateMemoryTypes()
                                          : getPhysicalDevice()->getAllMemoryTypes();
#if MVK_MACOS
    // Metal on macOS does not provide native support for host-coherent memory, but Vulkan requires it for Linear images
    if ( !_isLinear ) {
        mvkDisableFlags(pMemoryRequirements->memoryTypeBits, getPhysicalDevice()->getHostCoherentMemoryTypes());
    }
#endif
    // Only transient attachments may use memoryless storage.
	// Using memoryless as an input attachment requires shader framebuffer fetch, which MoltenVK does not support yet.
	// TODO: support framebuffer fetch so VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT uses color(m) in shader instead of setFragmentTexture:, which crashes Metal
    if (!mvkIsAnyFlagEnabled(getCombinedUsage(), VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT) ||
		 mvkIsAnyFlagEnabled(getCombinedUsage(), VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT) ) {
        mvkDisableFlags(pMemoryRequirements->memoryTypeBits, getPhysicalDevice()->getLazilyAllocatedMemoryTypes());
    }

    return _memoryBindings[planeIndex]->getMemoryRequirements(pMemoryRequirements);
}

VkResult MVKImage::getMemoryRequirements(const void* pInfo, VkMemoryRequirements2* pMemoryRequirements) {
    uint8_t planeIndex = 0;
	const auto* pImageInfo = (const VkImageMemoryRequirementsInfo2*)pInfo;
	for (const auto* next = (const VkBaseInStructure*)pImageInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
		case VK_STRUCTURE_TYPE_IMAGE_PLANE_MEMORY_REQUIREMENTS_INFO: {
			const auto* planeReqs = (const VkImagePlaneMemoryRequirementsInfo*)next;
            planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(planeReqs->planeAspect);
			break;
		}
		default:
			break;
		}
	}
    VkResult rslt = getMemoryRequirements(&pMemoryRequirements->memoryRequirements, planeIndex);
    if (rslt != VK_SUCCESS) { return rslt; }
    return _memoryBindings[planeIndex]->getMemoryRequirements(pInfo, pMemoryRequirements);
}

VkResult MVKImage::bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset, uint8_t planeIndex) {
    return _memoryBindings[planeIndex]->bindDeviceMemory(mvkMem, memOffset);
}

VkResult MVKImage::bindDeviceMemory2(const VkBindImageMemoryInfo* pBindInfo) {
    uint8_t planeIndex = 0;
    for (const auto* next = (const VkBaseInStructure*)pBindInfo->pNext; next; next = next->pNext) {
        switch (next->sType) {
            case VK_STRUCTURE_TYPE_BIND_IMAGE_PLANE_MEMORY_INFO: {
                const VkBindImagePlaneMemoryInfo* imagePlaneMemoryInfo = (const VkBindImagePlaneMemoryInfo*)next;
                planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(imagePlaneMemoryInfo->planeAspect);
                break;
            }
            default:
                break;
        }
    }
    return bindDeviceMemory((MVKDeviceMemory*)pBindInfo->memory, pBindInfo->memoryOffset, planeIndex);
}


#pragma mark Metal

id<MTLTexture> MVKImage::getMTLTexture(uint8_t planeIndex) {
	return _planes[planeIndex]->getMTLTexture();
}

id<MTLTexture> MVKImage::getMTLTexture(uint8_t planeIndex, MTLPixelFormat mtlPixFmt) {
    return _planes[planeIndex]->getMTLTexture(mtlPixFmt);
}

VkResult MVKImage::setMTLTexture(uint8_t planeIndex, id<MTLTexture> mtlTexture) {
	lock_guard<mutex> lock(_lock);

	if (planeIndex >= _planes.size()) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "Plane index is out of bounds. Attempted to set MTLTexture at plane index %d in VkImage that has %zu planes.", planeIndex, _planes.size()); }

	if (_planes[planeIndex]->_mtlTexture == mtlTexture) { return VK_SUCCESS; }

	releaseIOSurface();
    _planes[planeIndex]->releaseMTLTexture();
	_planes[planeIndex]->_mtlTexture = [mtlTexture retain];		// retained

    _vkFormat = getPixelFormats()->getVkFormat(mtlTexture.pixelFormat);
	_mtlTextureType = mtlTexture.textureType;
	_extent.width = uint32_t(mtlTexture.width);
	_extent.height = uint32_t(mtlTexture.height);
	_extent.depth = uint32_t(mtlTexture.depth);
	_mipLevels = uint32_t(mtlTexture.mipmapLevelCount);
	_samples = mvkVkSampleCountFlagBitsFromSampleCount(mtlTexture.sampleCount);
	_arrayLayers = uint32_t(mtlTexture.arrayLength);
	_usage = getPixelFormats()->getVkImageUsageFlags(mtlTexture.usage, mtlTexture.pixelFormat);
	_stencilUsage = _usage;

	if (_device->_pMetalFeatures->ioSurfaces) {
		_ioSurface = mtlTexture.iosurface;
		if (_ioSurface) { CFRetain(_ioSurface); }
	}

	return VK_SUCCESS;
}

void MVKImage::releaseIOSurface() {
    if (_ioSurface) {
        CFRelease(_ioSurface);
        _ioSurface = nil;
    }
}

IOSurfaceRef MVKImage::getIOSurface() { return _ioSurface; }

VkResult MVKImage::useIOSurface(IOSurfaceRef ioSurface) {
	lock_guard<mutex> lock(_lock);

	// Don't recreate existing. But special case of incoming nil if already nil means create a new IOSurface.
	if (ioSurface && _ioSurface == ioSurface) { return VK_SUCCESS; }

    if (!_device->_pMetalFeatures->ioSurfaces) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkUseIOSurfaceMVK() : IOSurfaces are not supported on this platform."); }

#if MVK_SUPPORT_IOSURFACE_BOOL

    for (uint8_t planeIndex = 0; planeIndex < _planes.size(); planeIndex++) {
        _planes[planeIndex]->releaseMTLTexture();
    }
    releaseIOSurface();

    MVKPixelFormats* pixFmts = getPixelFormats();

	if (ioSurface) {
		if (IOSurfaceGetWidth(ioSurface) != _extent.width) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface width %zu does not match VkImage width %d.", IOSurfaceGetWidth(ioSurface), _extent.width); }
		if (IOSurfaceGetHeight(ioSurface) != _extent.height) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface height %zu does not match VkImage height %d.", IOSurfaceGetHeight(ioSurface), _extent.height); }
		if (IOSurfaceGetBytesPerElement(ioSurface) != pixFmts->getBytesPerBlock(_vkFormat)) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface bytes per element %zu does not match VkImage bytes per element %d.", IOSurfaceGetBytesPerElement(ioSurface), pixFmts->getBytesPerBlock(_vkFormat)); }
		if (IOSurfaceGetElementWidth(ioSurface) != pixFmts->getBlockTexelSize(_vkFormat).width) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface element width %zu does not match VkImage element width %d.", IOSurfaceGetElementWidth(ioSurface), pixFmts->getBlockTexelSize(_vkFormat).width); }
		if (IOSurfaceGetElementHeight(ioSurface) != pixFmts->getBlockTexelSize(_vkFormat).height) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface element height %zu does not match VkImage element height %d.", IOSurfaceGetElementHeight(ioSurface), pixFmts->getBlockTexelSize(_vkFormat).height); }
        if (_hasChromaSubsampling) {
            if (IOSurfaceGetPlaneCount(ioSurface) != _planes.size()) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface plane count %zu does not match VkImage plane count %lu.", IOSurfaceGetPlaneCount(ioSurface), _planes.size()); }
            for (uint8_t planeIndex = 0; planeIndex < _planes.size(); ++planeIndex) {
                if (IOSurfaceGetWidthOfPlane(ioSurface, planeIndex) != getExtent3D(planeIndex, 0).width) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface width %zu of plane %d does not match VkImage width %d.", IOSurfaceGetWidthOfPlane(ioSurface, planeIndex), planeIndex, getExtent3D(planeIndex, 0).width); }
                if (IOSurfaceGetHeightOfPlane(ioSurface, planeIndex) != getExtent3D(planeIndex, 0).height) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface height %zu of plane %d does not match VkImage height %d.", IOSurfaceGetHeightOfPlane(ioSurface, planeIndex), planeIndex, getExtent3D(planeIndex, 0).height); }
                if (IOSurfaceGetBytesPerElementOfPlane(ioSurface, planeIndex) != _planes[planeIndex]->_bytesPerBlock) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface bytes per element %zu of plane %d does not match VkImage bytes per element %d.", IOSurfaceGetBytesPerElementOfPlane(ioSurface, planeIndex), planeIndex, _planes[planeIndex]->_bytesPerBlock); }
                if (IOSurfaceGetElementWidthOfPlane(ioSurface, planeIndex) != _planes[planeIndex]->_blockTexelSize.width) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface element width %zu of plane %d does not match VkImage element width %d.", IOSurfaceGetElementWidthOfPlane(ioSurface, planeIndex), planeIndex, _planes[planeIndex]->_blockTexelSize.width); }
                if (IOSurfaceGetElementHeightOfPlane(ioSurface, planeIndex) != _planes[planeIndex]->_blockTexelSize.height) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface element height %zu of plane %d does not match VkImage element height %d.", IOSurfaceGetElementHeightOfPlane(ioSurface, planeIndex), planeIndex, _planes[planeIndex]->_blockTexelSize.height); }
            }
        }

        _ioSurface = ioSurface;
        CFRetain(_ioSurface);
    } else {
        @autoreleasepool {
            CFMutableDictionaryRef properties = CFDictionaryCreateMutableCopy(NULL, 0, (CFDictionaryRef)@{
			    (id)kIOSurfaceWidth: @(_extent.width),
			    (id)kIOSurfaceHeight: @(_extent.height),
			    (id)kIOSurfaceBytesPerElement: @(pixFmts->getBytesPerBlock(_vkFormat)),
			    (id)kIOSurfaceElementWidth: @(pixFmts->getBlockTexelSize(_vkFormat).width),
			    (id)kIOSurfaceElementHeight: @(pixFmts->getBlockTexelSize(_vkFormat).height),
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			    (id)kIOSurfaceIsGlobal: @(true), // Deprecated but needed for interprocess transfers
#pragma clang diagnostic pop
            });
            if(_hasChromaSubsampling) {
                CFMutableArrayRef planeProperties = CFArrayCreateMutable(NULL, _planes.size(), NULL);
                for (uint8_t planeIndex = 0; planeIndex < _planes.size(); ++planeIndex) {
                    CFArrayAppendValue(planeProperties, (CFDictionaryRef)@{
                        (id)kIOSurfacePlaneWidth: @(getExtent3D(planeIndex, 0).width),
                        (id)kIOSurfacePlaneHeight: @(getExtent3D(planeIndex, 0).height),
                        (id)kIOSurfacePlaneBytesPerElement: @(_planes[planeIndex]->_bytesPerBlock),
                        (id)kIOSurfacePlaneElementWidth: @(_planes[planeIndex]->_blockTexelSize.width),
                        (id)kIOSurfacePlaneElementHeight: @(_planes[planeIndex]->_blockTexelSize.height),
                    });
                }
                CFDictionaryAddValue(properties, (id)kIOSurfacePlaneInfo, planeProperties);
                CFRelease(planeProperties);
            }
            _ioSurface = IOSurfaceCreate(properties);
            CFRelease(properties);
        }
    }

#endif

    return VK_SUCCESS;
}

MTLStorageMode MVKImage::getMTLStorageMode() {
    if ( !_memoryBindings[0]->_deviceMemory ) return MTLStorageModePrivate;

    MTLStorageMode stgMode = _memoryBindings[0]->_deviceMemory->getMTLStorageMode();

    if (_ioSurface && stgMode == MTLStorageModePrivate) { stgMode = MTLStorageModeShared; }

#if MVK_MACOS
	// For macOS prior to 10.15.5, textures cannot use Shared storage mode, so change to Managed storage mode.
    if (stgMode == MTLStorageModeShared && !_device->_pMetalFeatures->sharedLinearTextures) {
        stgMode = MTLStorageModeManaged;
    }
#endif
    return stgMode;
}

MTLCPUCacheMode MVKImage::getMTLCPUCacheMode() {
	return _memoryBindings[0]->_deviceMemory ? _memoryBindings[0]->_deviceMemory->getMTLCPUCacheMode() : MTLCPUCacheModeDefaultCache;
}

MTLTextureUsage MVKImage::getMTLTextureUsage(MTLPixelFormat mtlPixFmt) {

	// In the special case of a dedicated aliasable image, we must presume the texture can be used for anything.
	MVKDeviceMemory* dvcMem = _memoryBindings[0]->_deviceMemory;
	if (_isAliasable && dvcMem && dvcMem->isDedicatedAllocation()) { return MTLTextureUsageUnknown; }

	MVKPixelFormats* pixFmts = getPixelFormats();

	// The image view will need reinterpretation if this image is mutable, unless view formats are provided
	// and all of the view formats are either identical to, or an sRGB variation of, the incoming format.
	bool needsReinterpretation = _hasMutableFormat && _viewFormats.empty();
	for (VkFormat viewFmt : _viewFormats) {
		needsReinterpretation = needsReinterpretation || !pixFmts->compatibleAsLinearOrSRGB(mtlPixFmt, viewFmt);
	}

	MTLTextureUsage mtlUsage = pixFmts->getMTLTextureUsage(getCombinedUsage(), mtlPixFmt, _samples, _isLinear, needsReinterpretation, _hasExtendedUsage);

	// Metal before 3.0 doesn't support 3D compressed textures, so we'll
	// decompress the texture ourselves, and we need to be able to write to it.
	bool makeWritable = MVK_MACOS && _is3DCompressed;
	if (makeWritable) {
		mvkEnableFlags(mtlUsage, MTLTextureUsageShaderWrite);
	}

	return mtlUsage;
}

#pragma mark Construction

MVKImage::MVKImage(MVKDevice* device, const VkImageCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	_ioSurface = nil;

	// Stencil usage is implied to be the same as usage, unless overridden in the pNext chain.
	_usage = pCreateInfo->usage;
	_stencilUsage = _usage;

	const VkExternalMemoryImageCreateInfo* pExtMemInfo = nullptr;
	for (const auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO: {
				pExtMemInfo = (const VkExternalMemoryImageCreateInfo*)next;
				break;
			}
			case VK_STRUCTURE_TYPE_IMAGE_FORMAT_LIST_CREATE_INFO: {
				// Must set before calls to getIsValidViewFormat() below.
				auto* pFmtListInfo = (const VkImageFormatListCreateInfo*)next;
				for (uint32_t fmtIdx = 0; fmtIdx < pFmtListInfo->viewFormatCount; fmtIdx++) {
					_viewFormats.push_back(pFmtListInfo->pViewFormats[fmtIdx]);
				}
				break;
			}
			case VK_STRUCTURE_TYPE_IMAGE_STENCIL_USAGE_CREATE_INFO:
				_stencilUsage = ((VkImageStencilUsageCreateInfo*)next)->stencilUsage;
				break;
			default:
				break;
		}
	}

    // Adjust the info components to be compatible with Metal, then use the modified versions to set other
	// config info. Vulkan allows unused extent dimensions to be zero, but Metal requires minimum of one.
    uint32_t minDim = 1;
    _extent.width = max(pCreateInfo->extent.width, minDim);
	_extent.height = max(pCreateInfo->extent.height, minDim);
	_extent.depth = max(pCreateInfo->extent.depth, minDim);
    _arrayLayers = max(pCreateInfo->arrayLayers, minDim);

	// Perform validation and adjustments before configuring other settings
	bool isAttachment = mvkIsAnyFlagEnabled(pCreateInfo->usage, (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
																 VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
																 VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT |
																 VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT));
	// Texture type depends on validated samples. Other validation depends on possibly modified texture type.
	_samples = validateSamples(pCreateInfo, isAttachment);
	_mtlTextureType = mvkMTLTextureTypeFromVkImageType(pCreateInfo->imageType, _arrayLayers, _samples > VK_SAMPLE_COUNT_1_BIT);

	validateConfig(pCreateInfo, isAttachment);
	_mipLevels = validateMipLevels(pCreateInfo, isAttachment);
	_isLinear = validateLinear(pCreateInfo, isAttachment);

	MVKPixelFormats* pixFmts = getPixelFormats();
    _vkFormat = pCreateInfo->format;
    _isAliasable = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_IMAGE_CREATE_ALIAS_BIT);
	_hasMutableFormat = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT);
	_hasExtendedUsage = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_IMAGE_CREATE_EXTENDED_USAGE_BIT);

    // If this is a storage image of format R32_UINT or R32_SINT, or MUTABLE_FORMAT is set
    // and R32_UINT is in the set of possible view formats, then we must use a texel buffer,
    // or image atomics won't work.
	_isLinearForAtomics = (_isLinear && mvkIsAnyFlagEnabled(getCombinedUsage(), VK_IMAGE_USAGE_STORAGE_BIT) &&
						   ((_vkFormat == VK_FORMAT_R32_UINT || _vkFormat == VK_FORMAT_R32_SINT) ||
							(_hasMutableFormat && pixFmts->getViewClass(_vkFormat) == MVKMTLViewClass::Color32 &&
							 (getIsValidViewFormat(VK_FORMAT_R32_UINT) || getIsValidViewFormat(VK_FORMAT_R32_SINT)))));

	_is3DCompressed = (getImageType() == VK_IMAGE_TYPE_3D) && (pixFmts->getFormatType(pCreateInfo->format) == kMVKFormatCompressed) && !_device->_pMetalFeatures->native3DCompressedTextures;
	_isDepthStencilAttachment = (mvkAreAllFlagsEnabled(pCreateInfo->usage, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) ||
								 mvkAreAllFlagsEnabled(pixFmts->getVkFormatProperties(pCreateInfo->format).optimalTilingFeatures, VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT));
	_canSupportMTLTextureView = !_isDepthStencilAttachment || _device->_pMetalFeatures->stencilViews;
	_rowByteAlignment = _isLinear ? _device->getVkFormatTexelBufferAlignment(pCreateInfo->format, this) : mvkEnsurePowerOfTwo(pixFmts->getBytesPerBlock(pCreateInfo->format));

    VkExtent2D blockTexelSizeOfPlane[3];
    uint32_t bytesPerBlockOfPlane[3];
    MTLPixelFormat mtlPixFmtOfPlane[3];
	uint8_t subsamplingPlaneCount = pixFmts->getChromaSubsamplingPlanes(_vkFormat, blockTexelSizeOfPlane, bytesPerBlockOfPlane, mtlPixFmtOfPlane);
	uint8_t planeCount = std::max(subsamplingPlaneCount, (uint8_t)1);
    uint8_t memoryBindingCount = (pCreateInfo->flags & VK_IMAGE_CREATE_DISJOINT_BIT) ? planeCount : 1;
    _hasChromaSubsampling = (subsamplingPlaneCount > 0);

    for (uint8_t planeIndex = 0; planeIndex < memoryBindingCount; ++planeIndex) {
        _memoryBindings.push_back(new MVKImageMemoryBinding(device, this, planeIndex));
    }

    for (uint8_t planeIndex = 0; planeIndex < planeCount; ++planeIndex) {
        _planes.push_back(new MVKImagePlane(this, planeIndex));
        if (_hasChromaSubsampling) {
            _planes[planeIndex]->_blockTexelSize = blockTexelSizeOfPlane[planeIndex];
            _planes[planeIndex]->_bytesPerBlock = bytesPerBlockOfPlane[planeIndex];
            _planes[planeIndex]->_mtlPixFmt = mtlPixFmtOfPlane[planeIndex];
        } else {
            _planes[planeIndex]->_mtlPixFmt = getPixelFormats()->getMTLPixelFormat(_vkFormat);
        }
        _planes[planeIndex]->initSubresources(pCreateInfo);
        MVKImageMemoryBinding* memoryBinding = _planes[planeIndex]->getMemoryBinding();
        if (!_isLinear && _device->_pMetalFeatures->placementHeaps) {
            MTLTextureDescriptor* mtlTexDesc = _planes[planeIndex]->newMTLTextureDescriptor();    // temp retain
            MTLSizeAndAlign sizeAndAlign = [_device->getMTLDevice() heapTextureSizeAndAlignWithDescriptor: mtlTexDesc];
            [mtlTexDesc release];
            // Textures allocated on heaps must be aligned to the alignment reported here,
            // so make sure there's enough space to hold all the planes after alignment.
            memoryBinding->_byteCount = mvkAlignByteRef(memoryBinding->_byteCount, sizeAndAlign.align) + sizeAndAlign.size;
            memoryBinding->_byteAlignment = std::max(memoryBinding->_byteAlignment, (VkDeviceSize)sizeAndAlign.align);
        } else if (_isLinearForAtomics && _device->_pMetalFeatures->placementHeaps) {
            NSUInteger bufferLength = 0;
            for (uint32_t mipLvl = 0; mipLvl < _mipLevels; mipLvl++) {
                VkExtent3D mipExtent = getExtent3D(planeIndex, mipLvl);
                bufferLength += getBytesPerLayer(planeIndex, mipLvl) * mipExtent.depth * _arrayLayers;
            }
            MTLSizeAndAlign sizeAndAlign = [_device->getMTLDevice() heapBufferSizeAndAlignWithLength: bufferLength options: MTLResourceStorageModePrivate];
            memoryBinding->_byteCount += sizeAndAlign.size;
            memoryBinding->_byteAlignment = std::max(std::max(memoryBinding->_byteAlignment, _rowByteAlignment), (VkDeviceSize)sizeAndAlign.align);
        } else {
            for (uint32_t mipLvl = 0; mipLvl < _mipLevels; mipLvl++) {
                VkExtent3D mipExtent = getExtent3D(planeIndex, mipLvl);
                memoryBinding->_byteCount += getBytesPerLayer(planeIndex, mipLvl) * mipExtent.depth * _arrayLayers;
            }
            memoryBinding->_byteAlignment = std::max(memoryBinding->_byteAlignment, _rowByteAlignment);
        }
    }
    _hasExpectedTexelSize = _hasChromaSubsampling || (pixFmts->getBytesPerBlock(_planes[0]->_mtlPixFmt) == pixFmts->getBytesPerBlock(_vkFormat));

	if (pExtMemInfo) { initExternalMemory(pExtMemInfo->handleTypes); }

	// Setting Metal objects directly will override Vulkan settings.
	// It is responsibility of app to ensure these are consistent. Not doing so results in undefined behavior.
	const VkExportMetalObjectCreateInfoEXT* pExportInfo = nullptr;
	for (const auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_IMPORT_METAL_TEXTURE_INFO_EXT: {
				const auto* pMTLTexInfo = (VkImportMetalTextureInfoEXT*)next;
				uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(pMTLTexInfo->plane);
				setConfigurationResult(setMTLTexture(planeIndex, pMTLTexInfo->mtlTexture));
				break;
			}
			case VK_STRUCTURE_TYPE_IMPORT_METAL_IO_SURFACE_INFO_EXT: {
				const auto* pIOSurfInfo = (VkImportMetalIOSurfaceInfoEXT*)next;
				setConfigurationResult(useIOSurface(pIOSurfInfo->ioSurface));
				break;
			}
			case VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT:
				pExportInfo = (VkExportMetalObjectCreateInfoEXT*)next;
				break;
			default:
				break;
		}
	}

	// If we're expecting to export an IOSurface, and weren't give one,
	// base this image on a new IOSurface that matches its configuration.
	if (pExportInfo && pExportInfo->exportObjectType == VK_EXPORT_METAL_OBJECT_TYPE_METAL_IOSURFACE_BIT_EXT && !_ioSurface) {
		setConfigurationResult(useIOSurface(nil));
	}
}

VkSampleCountFlagBits MVKImage::validateSamples(const VkImageCreateInfo* pCreateInfo, bool isAttachment) {

	VkSampleCountFlagBits validSamples = pCreateInfo->samples;

	if (validSamples == VK_SAMPLE_COUNT_1_BIT) { return validSamples; }

	// Don't use getImageType() because it hasn't been set yet.
	if ( !((pCreateInfo->imageType == VK_IMAGE_TYPE_2D) || ((pCreateInfo->imageType == VK_IMAGE_TYPE_1D) && mvkConfig().texture1DAs2D)) ) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, multisampling can only be used with a 2D image type. Setting sample count to 1."));
		validSamples = VK_SAMPLE_COUNT_1_BIT;
	}

	if (getPixelFormats()->getFormatType(pCreateInfo->format) == kMVKFormatCompressed) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, multisampling cannot be used with compressed images. Setting sample count to 1."));
		validSamples = VK_SAMPLE_COUNT_1_BIT;
	}
	if (getPixelFormats()->getChromaSubsamplingPlaneCount(pCreateInfo->format) > 0) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, multisampling cannot be used with chroma subsampled images. Setting sample count to 1."));
		validSamples = VK_SAMPLE_COUNT_1_BIT;
	}

	if (pCreateInfo->arrayLayers > 1 && !_device->_pMetalFeatures->multisampleArrayTextures ) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : This device does not support multisampled array textures. Setting sample count to 1."));
		validSamples = VK_SAMPLE_COUNT_1_BIT;
	}

	return validSamples;
}

void MVKImage::validateConfig(const VkImageCreateInfo* pCreateInfo, bool isAttachment) {
	MVKPixelFormats* pixFmts = getPixelFormats();

	bool is2D = (getImageType() == VK_IMAGE_TYPE_2D);
	bool isChromaSubsampled = pixFmts->getChromaSubsamplingPlaneCount(pCreateInfo->format) > 0;

	if (isChromaSubsampled && !is2D) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, chroma subsampled formats may only be used with 2D images."));
	}
	if (isChromaSubsampled && mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT)) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, chroma subsampled formats may not be used with cube images."));
	}
	if (isChromaSubsampled && (pCreateInfo->arrayLayers > 1)) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Chroma-subsampled formats may only have one array layer."));
	}
	if ((pixFmts->getFormatType(pCreateInfo->format) == kMVKFormatDepthStencil) && !is2D ) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, depth/stencil formats may only be used with 2D images."));
	}
	if (isAttachment && (getImageType() == VK_IMAGE_TYPE_1D)) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Metal does not support rendering to native 1D attachments. Consider enabling MVK_CONFIG_TEXTURE_1D_AS_2D."));
	}
	if (mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_IMAGE_CREATE_BLOCK_TEXEL_VIEW_COMPATIBLE_BIT)) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Metal does not allow uncompressed views of compressed images."));
	}
	if (mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_IMAGE_CREATE_SPLIT_INSTANCE_BIND_REGIONS_BIT)) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Metal does not support split-instance memory binding."));
	}
}

uint32_t MVKImage::validateMipLevels(const VkImageCreateInfo* pCreateInfo, bool isAttachment) {
	uint32_t minDim = 1;
	uint32_t validMipLevels = max(pCreateInfo->mipLevels, minDim);

	if (validMipLevels == 1) { return validMipLevels; }

	if (getPixelFormats()->getChromaSubsamplingPlaneCount(pCreateInfo->format) == 1) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, GBGR and BGRG images cannot use mipmaps. Setting mip levels to 1."));
		validMipLevels = 1;
	}
	if (getImageType() == VK_IMAGE_TYPE_1D) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, native 1D images cannot use mipmaps. Setting mip levels to 1. Consider enabling MVK_CONFIG_TEXTURE_1D_AS_2D."));
		validMipLevels = 1;
	}

	return validMipLevels;
}

bool MVKImage::validateLinear(const VkImageCreateInfo* pCreateInfo, bool isAttachment) {

	if (pCreateInfo->tiling != VK_IMAGE_TILING_LINEAR ) { return false; }

	bool isLin = true;

	if (getImageType() != VK_IMAGE_TYPE_2D) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : If tiling is VK_IMAGE_TILING_LINEAR, imageType must be VK_IMAGE_TYPE_2D."));
		isLin = false;
	}

	if (getPixelFormats()->getFormatType(pCreateInfo->format) == kMVKFormatDepthStencil) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : If tiling is VK_IMAGE_TILING_LINEAR, format must not be a depth/stencil format."));
		isLin = false;
	}
	if (getPixelFormats()->getFormatType(pCreateInfo->format) == kMVKFormatCompressed) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : If tiling is VK_IMAGE_TILING_LINEAR, format must not be a compressed format."));
		isLin = false;
	}
	if (getPixelFormats()->getChromaSubsamplingPlaneCount(pCreateInfo->format) == 1) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : If tiling is VK_IMAGE_TILING_LINEAR, format must not be a single-plane chroma subsampled format."));
		isLin = false;
	}

	if (pCreateInfo->mipLevels > 1) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : If tiling is VK_IMAGE_TILING_LINEAR, mipLevels must be 1."));
		isLin = false;
	}

	if (pCreateInfo->arrayLayers > 1) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : If tiling is VK_IMAGE_TILING_LINEAR, arrayLayers must be 1."));
		isLin = false;
	}

	if (pCreateInfo->samples > VK_SAMPLE_COUNT_1_BIT) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : If tiling is VK_IMAGE_TILING_LINEAR, samples must be VK_SAMPLE_COUNT_1_BIT."));
		isLin = false;
	}

#if !MVK_APPLE_SILICON
	if (isAttachment) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : This device does not support rendering to linear (VK_IMAGE_TILING_LINEAR) images."));
		isLin = false;
	}
#endif

	return isLin;
}

void MVKImage::initExternalMemory(VkExternalMemoryHandleTypeFlags handleTypes) {
	if (mvkIsOnlyAnyFlagEnabled(handleTypes, VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR)) {
        auto& xmProps = getPhysicalDevice()->getExternalImageProperties(VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR);
        for(auto& memoryBinding : _memoryBindings) {
            memoryBinding->_externalMemoryHandleTypes = handleTypes;
            memoryBinding->_requiresDedicatedMemoryAllocation = memoryBinding->_requiresDedicatedMemoryAllocation || mvkIsAnyFlagEnabled(xmProps.externalMemoryFeatures, VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT);
        }
	} else {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage(): Only external memory handle type VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR is supported."));
	}
}

MVKImage::~MVKImage() {
	mvkDestroyContainerContents(_memoryBindings);
	mvkDestroyContainerContents(_planes);
    releaseIOSurface();
}


#pragma mark -
#pragma mark MVKSwapchainImage

VkResult MVKSwapchainImage::bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset, uint8_t planeIndex) {
	return VK_ERROR_OUT_OF_DEVICE_MEMORY;
}


#pragma mark Metal

// Overridden to always retrieve the MTLTexture directly from the CAMetalDrawable.
id<MTLTexture> MVKSwapchainImage::getMTLTexture(uint8_t planeIndex) { return [getCAMetalDrawable() texture]; }


#pragma mark Construction

MVKSwapchainImage::MVKSwapchainImage(MVKDevice* device,
									 const VkImageCreateInfo* pCreateInfo,
									 MVKSwapchain* swapchain,
									 uint32_t swapchainIndex) : MVKImage(device, pCreateInfo) {
	_swapchain = swapchain;
	_swapchainIndex = swapchainIndex;

	_swapchain->retain();
}

MVKSwapchainImage::~MVKSwapchainImage() {
	if (_swapchain) { _swapchain->release(); }
}


#pragma mark -
#pragma mark MVKPresentableSwapchainImage

bool MVKSwapchainImageAvailability::operator< (const MVKSwapchainImageAvailability& rhs) const {
	if (  isAvailable && !rhs.isAvailable) { return true; }
	if ( !isAvailable &&  rhs.isAvailable) { return false; }
	return acquisitionID < rhs.acquisitionID;
}

MVKSwapchainImageAvailability MVKPresentableSwapchainImage::getAvailability() {
	lock_guard<mutex> lock(_availabilityLock);

	return _availability;
}

// Makes an image available for acquisition by the app.
// If any semaphores are waiting to be signaled when this image becomes available, the
// earliest semaphore is signaled, and this image remains unavailable for other uses.
void MVKPresentableSwapchainImage::makeAvailable(const MVKSwapchainSignaler& signaler) {
	lock_guard<mutex> lock(_availabilityLock);

	// Signal the semaphore and fence, and let them know they are no longer being tracked.
	signal(signaler, nil);
	unmarkAsTracked(signaler);
}

void MVKPresentableSwapchainImage::acquireAndSignalWhenAvailable(MVKSemaphore* semaphore, MVKFence* fence) {
	lock_guard<mutex> lock(_availabilityLock);

	// Upon acquisition, update acquisition ID immediately, to move it to the back of the chain,
	// so other images will be preferred if either all images are available or no images are available.
	_availability.acquisitionID = _swapchain->getNextAcquisitionID();

	// Now that this image is being acquired, release the existing drawable and its texture.
	// This is not done earlier so the texture is retained for any post-processing such as screen captures, etc.
	releaseMetalDrawable();

	auto signaler = MVKSwapchainSignaler{fence, semaphore, semaphore ? semaphore->deferSignal() : 0};
	if (_availability.isAvailable) {
		_availability.isAvailable = false;

		// If signalling through a MTLEvent, and there's no command buffer presenting me, use an ephemeral MTLCommandBuffer.
		// Another option would be to use MTLSharedEvent in MVKSemaphore, but that might
		// impose unacceptable performance costs to handle this particular case.
		@autoreleasepool {
			MVKSemaphore* mvkSem = signaler.semaphore;
			id<MTLCommandBuffer> mtlCmdBuff = (mvkSem && mvkSem->isUsingCommandEncoding()
											   ? _device->getAnyQueue()->getMTLCommandBuffer(kMVKCommandUseAcquireNextImage)
											   : nil);
			signal(signaler, mtlCmdBuff);
			[mtlCmdBuff commit];
		}

		_preSignaler = signaler;
	} else {
		_availabilitySignalers.push_back(signaler);
	}
	markAsTracked(signaler);
}

// If present, signal the semaphore for the first waiter for the given image.
void MVKPresentableSwapchainImage::signalPresentationSemaphore(const MVKSwapchainSignaler& signaler, id<MTLCommandBuffer> mtlCmdBuff) {
	MVKSemaphore* mvkSem = signaler.semaphore;
	if (mvkSem) { mvkSem->encodeDeferredSignal(mtlCmdBuff, signaler.semaphoreSignalToken); }
}

// Signal either or both of the semaphore and fence in the specified tracker pair.
void MVKPresentableSwapchainImage::signal(const MVKSwapchainSignaler& signaler, id<MTLCommandBuffer> mtlCmdBuff) {
	if (signaler.semaphore) { signaler.semaphore->encodeDeferredSignal(mtlCmdBuff, signaler.semaphoreSignalToken); }
	if (signaler.fence) { signaler.fence->signal(); }
}

// Tell the semaphore and fence that they are being tracked for future signaling.
void MVKPresentableSwapchainImage::markAsTracked(const MVKSwapchainSignaler& signaler) {
	if (signaler.semaphore) { signaler.semaphore->retain(); }
	if (signaler.fence) { signaler.fence->retain(); }
}

// Tell the semaphore and fence that they are no longer being tracked for future signaling.
void MVKPresentableSwapchainImage::unmarkAsTracked(const MVKSwapchainSignaler& signaler) {
	if (signaler.semaphore) { signaler.semaphore->release(); }
	if (signaler.fence) { signaler.fence->release(); }
}


#pragma mark Metal

id<CAMetalDrawable> MVKPresentableSwapchainImage::getCAMetalDrawable() {
	while ( !_mtlDrawable ) {
		@autoreleasepool {      // Reclaim auto-released drawable object before end of loop
			uint64_t startTime = _device->getPerformanceTimestamp();

			_mtlDrawable = [_swapchain->_mtlLayer.nextDrawable retain];
			if ( !_mtlDrawable ) { MVKLogError("CAMetalDrawable could not be acquired."); }

			_device->addActivityPerformance(_device->_performanceStatistics.queue.nextCAMetalDrawable, startTime);
		}
	}
	return _mtlDrawable;
}

// Present the drawable and make myself available only once the command buffer has completed.
void MVKPresentableSwapchainImage::presentCAMetalDrawable(id<MTLCommandBuffer> mtlCmdBuff,
														  MVKPresentTimingInfo presentTimingInfo) {

	lock_guard<mutex> lock(_availabilityLock);

	_swapchain->willPresentSurface(getMTLTexture(0), mtlCmdBuff);

	// Get current drawable now. Don't retrieve in handler, because a new drawable might be acquired by then.
	id<CAMetalDrawable> mtlDrwbl = getCAMetalDrawable();
	[mtlCmdBuff addScheduledHandler: ^(id<MTLCommandBuffer> mcb) {
		presentCAMetalDrawable(mtlDrwbl, presentTimingInfo);
	}];

	MVKSwapchainSignaler signaler;
	// Mark this image as available if no semaphores or fences are waiting to be signaled.
	_availability.isAvailable = _availabilitySignalers.empty();
	if (_availability.isAvailable) {
		// If this image is available, signal the semaphore and fence that were associated
		// with the last time this image was acquired while available. This is a workaround for
		// when an app uses a single semaphore or fence for more than one swapchain image.
		// Because the semaphore or fence will be signaled by more than one image, it will
		// get out of sync, and the final use of the image would not be signaled as a result.
		signaler = _preSignaler;
		// Save the command buffer in case this image is acquired before presentation is finished.
	} else {
		// If this image is not yet available, extract and signal the first semaphore and fence.
		auto sigIter = _availabilitySignalers.begin();
		signaler = *sigIter;
		_availabilitySignalers.erase(sigIter);
	}

	// Ensure this image is not destroyed while awaiting MTLCommandBuffer completion
	retain();
	[mtlCmdBuff addCompletedHandler: ^(id<MTLCommandBuffer> mcb) {
		makeAvailable(signaler);
		release();
	}];

	signalPresentationSemaphore(signaler, mtlCmdBuff);
}

void MVKPresentableSwapchainImage::presentCAMetalDrawable(id<CAMetalDrawable> mtlDrawable,
														  MVKPresentTimingInfo presentTimingInfo) {

	if (presentTimingInfo.hasPresentTime) {

		// Attach present handler before presenting to avoid race condition.
		// If MTLDrawable.presentedTime/addPresentedHandler isn't supported,
		// treat it as if the present happened when requested.
#if MVK_OS_SIMULATOR
		_swapchain->recordPresentTime(presentTimingInfo);
#else
		if ([mtlDrawable respondsToSelector: @selector(addPresentedHandler:)]) {
			// Ensure this image is not destroyed while awaiting presentation
			retain();
			[mtlDrawable addPresentedHandler: ^(id<MTLDrawable> drawable) {
				_swapchain->recordPresentTime(presentTimingInfo, drawable.presentedTime * 1.0e9);
				release();
			}];
		} else {
			_swapchain->recordPresentTime(presentTimingInfo);
		}
#endif
		// Convert from nsecs to seconds for Metal
		[mtlDrawable presentAtTime: (double)presentTimingInfo.desiredPresentTime * 1.0e-9];
	} else {
		[mtlDrawable present];
	}
}

// Resets the MTLTexture and CAMetalDrawable underlying this image.
void MVKPresentableSwapchainImage::releaseMetalDrawable() {
    for (uint8_t planeIndex = 0; planeIndex < _planes.size(); ++planeIndex) {
        _planes[planeIndex]->releaseMTLTexture();
    }
    [_mtlDrawable release];
	_mtlDrawable = nil;
}


#pragma mark Construction

MVKPresentableSwapchainImage::MVKPresentableSwapchainImage(MVKDevice* device,
														   const VkImageCreateInfo* pCreateInfo,
														   MVKSwapchain* swapchain,
														   uint32_t swapchainIndex) :
	MVKSwapchainImage(device, pCreateInfo, swapchain, swapchainIndex) {

	_mtlDrawable = nil;

	_availability.acquisitionID = _swapchain->getNextAcquisitionID();
	_availability.isAvailable = true;
	_preSignaler = MVKSwapchainSignaler{nullptr, nullptr, 0};
}

MVKPresentableSwapchainImage::~MVKPresentableSwapchainImage() {
	releaseMetalDrawable();
}


#pragma mark -
#pragma mark MVKPeerSwapchainImage

VkResult MVKPeerSwapchainImage::bindDeviceMemory2(const VkBindImageMemoryInfo* pBindInfo) {
	const VkBindImageMemorySwapchainInfoKHR* swapchainInfo = nullptr;
	for (const auto* next = (const VkBaseInStructure*)pBindInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_BIND_IMAGE_MEMORY_SWAPCHAIN_INFO_KHR:
				swapchainInfo = (const VkBindImageMemorySwapchainInfoKHR*)next;
				break;
			default:
				break;
		}
	}
	if (!swapchainInfo) { return VK_ERROR_OUT_OF_DEVICE_MEMORY; }

	_swapchainIndex = swapchainInfo->imageIndex;
	return VK_SUCCESS;
}


#pragma mark Metal

id<CAMetalDrawable> MVKPeerSwapchainImage::getCAMetalDrawable() {
	return ((MVKSwapchainImage*)_swapchain->getPresentableImage(_swapchainIndex))->getCAMetalDrawable();
}


#pragma mark Construction

MVKPeerSwapchainImage::MVKPeerSwapchainImage(MVKDevice* device,
											 const VkImageCreateInfo* pCreateInfo,
											 MVKSwapchain* swapchain,
											 uint32_t swapchainIndex) :
	MVKSwapchainImage(device, pCreateInfo, swapchain, swapchainIndex) {}



#pragma mark -
#pragma mark MVKImageViewPlane

MVKVulkanAPIObject* MVKImageViewPlane::getVulkanAPIObject() { return _imageView; }

void MVKImageViewPlane::propagateDebugName() { setLabelIfNotNil(_mtlTexture, _imageView->_debugName); }


#pragma mark Metal

id<MTLTexture> MVKImageViewPlane::getMTLTexture() {
    // If we can use a Metal texture view, lazily create it, otherwise use the image texture directly.
    if (_useMTLTextureView) {
        if ( !_mtlTexture && _mtlPixFmt ) {

            // Lock and check again in case another thread created the texture view
            lock_guard<mutex> lock(_imageView->_lock);
            if (_mtlTexture) { return _mtlTexture; }

            _mtlTexture = newMTLTexture(); // retained

            propagateDebugName();
        }
        return _mtlTexture;
    } else {
        return _imageView->_image->getMTLTexture(_planeIndex);
    }
}

// Creates and returns a retained Metal texture as an
// overlay on the Metal texture of the underlying image.
id<MTLTexture> MVKImageViewPlane::newMTLTexture() {
    MTLTextureType mtlTextureType = _imageView->_mtlTextureType;
    NSRange sliceRange = NSMakeRange(_imageView->_subresourceRange.baseArrayLayer, _imageView->_subresourceRange.layerCount);
    // Fake support for 2D views of 3D textures.
    if (_imageView->_image->getImageType() == VK_IMAGE_TYPE_3D &&
        (mtlTextureType == MTLTextureType2D || mtlTextureType == MTLTextureType2DArray)) {
        mtlTextureType = MTLTextureType3D;
        sliceRange = NSMakeRange(0, 1);
    }
    id<MTLTexture> mtlTex = _imageView->_image->getMTLTexture(_planeIndex);
    if (_useNativeSwizzle) {
        return [mtlTex newTextureViewWithPixelFormat: _mtlPixFmt
                                         textureType: mtlTextureType
                                              levels: NSMakeRange(_imageView->_subresourceRange.baseMipLevel, _imageView->_subresourceRange.levelCount)
                                              slices: sliceRange
                                             swizzle: mvkMTLTextureSwizzleChannelsFromVkComponentMapping(_componentSwizzle)];    // retained
    } else {
        return [mtlTex newTextureViewWithPixelFormat: _mtlPixFmt
                                         textureType: mtlTextureType
                                              levels: NSMakeRange(_imageView->_subresourceRange.baseMipLevel, _imageView->_subresourceRange.levelCount)
                                              slices: sliceRange];    // retained
    }
}


#pragma mark Construction

MVKImageViewPlane::MVKImageViewPlane(MVKImageView* imageView,
									 uint8_t planeIndex,
									 MTLPixelFormat mtlPixFmt,
									 const VkImageViewCreateInfo* pCreateInfo) : MVKBaseDeviceObject(imageView->_device) {
    _imageView = imageView;
    _planeIndex = planeIndex;
    _mtlPixFmt = mtlPixFmt;
    _mtlTexture = nil;

	getVulkanAPIObject()->setConfigurationResult(initSwizzledMTLPixelFormat(pCreateInfo));

    // Determine whether this image view should use a Metal texture view,
    // and set the _useMTLTextureView variable appropriately.
    if ( _imageView->_image ) {
        _useMTLTextureView = _imageView->_image->_canSupportMTLTextureView;
        bool is3D = _imageView->_image->_mtlTextureType == MTLTextureType3D;
        // If the view is identical to underlying image, don't bother using a Metal view
        if (_mtlPixFmt == _imageView->_image->getMTLPixelFormat(planeIndex) &&
            (_imageView->_mtlTextureType == _imageView->_image->_mtlTextureType ||
             ((_imageView->_mtlTextureType == MTLTextureType2D || _imageView->_mtlTextureType == MTLTextureType2DArray) && is3D)) &&
            _imageView->_subresourceRange.levelCount == _imageView->_image->_mipLevels &&
            (is3D || _imageView->_subresourceRange.layerCount == _imageView->_image->_arrayLayers) &&
            !_useNativeSwizzle) {
            _useMTLTextureView = false;
        }
    } else {
        _useMTLTextureView = false;
    }
}

VkResult MVKImageViewPlane::initSwizzledMTLPixelFormat(const VkImageViewCreateInfo* pCreateInfo) {

	_useNativeSwizzle = false;
	_useShaderSwizzle = false;
	_componentSwizzle = pCreateInfo->components;
	VkImageAspectFlags aspectMask = pCreateInfo->subresourceRange.aspectMask;

#define adjustComponentSwizzleValue(comp, currVal, newVal)    if (_componentSwizzle.comp == VK_COMPONENT_SWIZZLE_ ##currVal) { _componentSwizzle.comp = VK_COMPONENT_SWIZZLE_ ##newVal; }

	// Use swizzle adjustment to bridge some differences between Vulkan and Metal pixel formats.
	// Do this ahead of other tests and adjustments so that swizzling will be enabled by tests below.
	switch (pCreateInfo->format) {
		case VK_FORMAT_BC1_RGB_UNORM_BLOCK:
		case VK_FORMAT_BC1_RGB_SRGB_BLOCK:
			// Metal doesn't support BC1_RGB, so force references to substituted BC1_RGBA alpha to 1.0.
			adjustComponentSwizzleValue(r, A, ONE);
			adjustComponentSwizzleValue(g, A, ONE);
			adjustComponentSwizzleValue(b, A, ONE);
			adjustComponentSwizzleValue(a, A, ONE);
			adjustComponentSwizzleValue(a, IDENTITY, ONE);
			break;

		default:
			break;
	}

#define SWIZZLE_MATCHES(R, G, B, A)    mvkVkComponentMappingsMatch(_componentSwizzle, {VK_COMPONENT_SWIZZLE_ ##R, VK_COMPONENT_SWIZZLE_ ##G, VK_COMPONENT_SWIZZLE_ ##B, VK_COMPONENT_SWIZZLE_ ##A} )
#define VK_COMPONENT_SWIZZLE_ANY       VK_COMPONENT_SWIZZLE_MAX_ENUM

	// If we have an identity swizzle, we're all good.
	if (SWIZZLE_MATCHES(R, G, B, A)) {

		// Identity swizzles of depth/stencil formats can require special handling.
		if (mvkIsAnyFlagEnabled(_imageView->_usage, (VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT))) {

			// If only stencil aspect is requested, possibly change to stencil-only format.
			if (aspectMask == VK_IMAGE_ASPECT_STENCIL_BIT) {
				if (_mtlPixFmt == MTLPixelFormatDepth32Float_Stencil8) {
					_mtlPixFmt = MTLPixelFormatX32_Stencil8;
				}
#if MVK_MACOS
				else if (_mtlPixFmt == MTLPixelFormatDepth24Unorm_Stencil8) {
					_mtlPixFmt = MTLPixelFormatX24_Stencil8;
				}
#endif
			}

			// When reading or sampling into a vec4 color, Vulkan expects the depth or stencil value in only the red component.
			// Metal can be inconsistent, but on most platforms populates all components with the depth or stencil value.
			// If swizzling is available, we can compensate for this by forcing the appropriate swizzle.
			if (mvkIsAnyFlagEnabled(aspectMask, VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT) && enableSwizzling()) {
				_componentSwizzle = { VK_COMPONENT_SWIZZLE_R, VK_COMPONENT_SWIZZLE_ZERO, VK_COMPONENT_SWIZZLE_ZERO, VK_COMPONENT_SWIZZLE_ONE };
			}
		}

		return VK_SUCCESS;
	}

	if (mvkIsAnyFlagEnabled(_imageView->_usage, VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT | VK_IMAGE_USAGE_STORAGE_BIT)) {
		// Vulkan forbids using image views with non-identity swizzles as storage images or attachments.
		// Let's catch some cases which are essentially identity, but would still result in Metal restricting
		// the resulting texture's usage.

		switch (_mtlPixFmt) {
			case MTLPixelFormatR8Unorm:
#if MVK_APPLE_SILICON
			case MTLPixelFormatR8Unorm_sRGB:
#endif
			case MTLPixelFormatR8Snorm:
			case MTLPixelFormatR8Uint:
			case MTLPixelFormatR8Sint:
			case MTLPixelFormatR16Unorm:
			case MTLPixelFormatR16Snorm:
			case MTLPixelFormatR16Uint:
			case MTLPixelFormatR16Sint:
			case MTLPixelFormatR16Float:
			case MTLPixelFormatR32Uint:
			case MTLPixelFormatR32Sint:
			case MTLPixelFormatR32Float:
				if (SWIZZLE_MATCHES(R, ZERO, ZERO, ONE)) {
					return VK_SUCCESS;
				}
				break;

			case MTLPixelFormatRG8Unorm:
#if MVK_APPLE_SILICON
			case MTLPixelFormatRG8Unorm_sRGB:
#endif
			case MTLPixelFormatRG8Snorm:
			case MTLPixelFormatRG8Uint:
			case MTLPixelFormatRG8Sint:
			case MTLPixelFormatRG16Unorm:
			case MTLPixelFormatRG16Snorm:
			case MTLPixelFormatRG16Uint:
			case MTLPixelFormatRG16Sint:
			case MTLPixelFormatRG16Float:
			case MTLPixelFormatRG32Uint:
			case MTLPixelFormatRG32Sint:
			case MTLPixelFormatRG32Float:
				if (SWIZZLE_MATCHES(R, G, ZERO, ONE)) {
					return VK_SUCCESS;
				}
				break;

			case MTLPixelFormatRG11B10Float:
			case MTLPixelFormatRGB9E5Float:
				if (SWIZZLE_MATCHES(R, G, B, ONE)) {
					return VK_SUCCESS;
				}
				break;

			default:
				break;
		}
	}

	switch (_mtlPixFmt) {
		case MTLPixelFormatR8Unorm:
			if (SWIZZLE_MATCHES(ZERO, ANY, ANY, R)) {
				_mtlPixFmt = MTLPixelFormatA8Unorm;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatA8Unorm:
			if (SWIZZLE_MATCHES(A, ANY, ANY, ZERO)) {
				_mtlPixFmt = MTLPixelFormatR8Unorm;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatRGBA8Unorm:
			if (SWIZZLE_MATCHES(B, G, R, A)) {
				_mtlPixFmt = MTLPixelFormatBGRA8Unorm;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatRGBA8Unorm_sRGB:
			if (SWIZZLE_MATCHES(B, G, R, A)) {
				_mtlPixFmt = MTLPixelFormatBGRA8Unorm_sRGB;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatBGRA8Unorm:
			if (SWIZZLE_MATCHES(B, G, R, A)) {
				_mtlPixFmt = MTLPixelFormatRGBA8Unorm;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatBGRA8Unorm_sRGB:
			if (SWIZZLE_MATCHES(B, G, R, A)) {
				_mtlPixFmt = MTLPixelFormatRGBA8Unorm_sRGB;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatDepth32Float_Stencil8:
			// If aspect mask looking only for stencil then change to stencil-only format even if shader swizzling is needed
			if (aspectMask == VK_IMAGE_ASPECT_STENCIL_BIT &&
				mvkIsAnyFlagEnabled(_imageView->_usage, (VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT))) {
				_mtlPixFmt = MTLPixelFormatX32_Stencil8;
				if (SWIZZLE_MATCHES(R, ANY, ANY, ANY)) {
					return VK_SUCCESS;
				}
			}
			break;

#if MVK_MACOS
		case MTLPixelFormatDepth24Unorm_Stencil8:
			// If aspect mask looking only for stencil then change to stencil-only format even if shader swizzling is needed
			if (aspectMask == VK_IMAGE_ASPECT_STENCIL_BIT &&
				mvkIsAnyFlagEnabled(_imageView->_usage, (VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT))) {
				_mtlPixFmt = MTLPixelFormatX24_Stencil8;
				if (SWIZZLE_MATCHES(R, ANY, ANY, ANY)) {
					return VK_SUCCESS;
				}
			}
			break;
#endif

		default:
			break;
	}

	// No format transformation swizzles were found, so we'll need to use either native or shader swizzling, if supported.
	if ( !enableSwizzling() ) {
		return getVulkanAPIObject()->reportError(VK_ERROR_FEATURE_NOT_PRESENT,
												 "The value of %s::components) (%s, %s, %s, %s), when applied to a VkImageView, requires full component swizzling to be enabled both at the"
												 " time when the VkImageView is created and at the time any pipeline that uses that VkImageView is compiled. Full component swizzling can"
												 " be enabled via the MVKConfiguration::fullImageViewSwizzle config parameter or MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE environment variable.",
												 pCreateInfo->image ? "vkCreateImageView(VkImageViewCreateInfo" : "vkGetPhysicalDeviceImageFormatProperties2KHR(VkPhysicalDeviceImageViewSupportEXTX",
												 mvkVkComponentSwizzleName(_componentSwizzle.r), mvkVkComponentSwizzleName(_componentSwizzle.g),
												 mvkVkComponentSwizzleName(_componentSwizzle.b), mvkVkComponentSwizzleName(_componentSwizzle.a));
	}

	return VK_SUCCESS;
}

// Enable either native or shader swizzling, depending on what is available, preferring native, and return whether successful.
bool MVKImageViewPlane::enableSwizzling() {
	_useNativeSwizzle = _device->_pMetalFeatures->nativeTextureSwizzle;
	_useShaderSwizzle = !_useNativeSwizzle && mvkConfig().fullImageViewSwizzle;
	return _useNativeSwizzle || _useShaderSwizzle;
}

MVKImageViewPlane::~MVKImageViewPlane() {
    [_mtlTexture release];
}


#pragma mark -
#pragma mark MVKImageView

void MVKImageView::propagateDebugName() {
    for (uint8_t planeIndex = 0; planeIndex < _planes.size(); planeIndex++) {
        _planes[planeIndex]->propagateDebugName();
    }
}

void MVKImageView::populateMTLRenderPassAttachmentDescriptor(MTLRenderPassAttachmentDescriptor* mtlAttDesc) {
    MVKImageViewPlane* plane = _planes[0];
    bool useView = plane->_useMTLTextureView;
    mtlAttDesc.texture = plane->getMTLTexture();
    // If a native swizzle is being applied, use the unswizzled parent texture.
    // This is relevant for depth/stencil attachments that are also sampled and might have forced swizzles.
    if (plane->_useNativeSwizzle && mtlAttDesc.texture.parentTexture) {
        useView = false;
        mtlAttDesc.texture = mtlAttDesc.texture.parentTexture;
    }
    mtlAttDesc.level = useView ? 0 : _subresourceRange.baseMipLevel;
    if (mtlAttDesc.texture.textureType == MTLTextureType3D) {
        mtlAttDesc.slice = 0;
        mtlAttDesc.depthPlane = _subresourceRange.baseArrayLayer;
    } else {
        mtlAttDesc.slice = useView ? 0 : _subresourceRange.baseArrayLayer;
        mtlAttDesc.depthPlane = 0;
    }
}

void MVKImageView::populateMTLRenderPassAttachmentDescriptorResolve(MTLRenderPassAttachmentDescriptor* mtlAttDesc) {
    MVKImageViewPlane* plane = _planes[0];
    bool useView = plane->_useMTLTextureView;
    mtlAttDesc.resolveTexture = plane->getMTLTexture();
    // If a native swizzle is being applied, use the unswizzled parent texture.
    // This is relevant for depth/stencil attachments that are also sampled and might have forced swizzles.
    if (plane->_useNativeSwizzle && mtlAttDesc.resolveTexture.parentTexture) {
        useView = false;
        mtlAttDesc.resolveTexture = mtlAttDesc.resolveTexture.parentTexture;
    }
    mtlAttDesc.resolveLevel = useView ? 0 : _subresourceRange.baseMipLevel;
    if (mtlAttDesc.resolveTexture.textureType == MTLTextureType3D) {
        mtlAttDesc.resolveSlice = 0;
        mtlAttDesc.resolveDepthPlane = useView ? 0 : _subresourceRange.baseArrayLayer;
    } else {
        mtlAttDesc.resolveSlice = useView ? 0 : _subresourceRange.baseArrayLayer;
        mtlAttDesc.resolveDepthPlane = 0;
    }
}


#pragma mark Construction

MVKImageView::MVKImageView(MVKDevice* device, const VkImageViewCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	_image = (MVKImage*)pCreateInfo->image;
    _mtlTextureType = mvkMTLTextureTypeFromVkImageViewType(pCreateInfo->viewType,
														   _image->getSampleCount() != VK_SAMPLE_COUNT_1_BIT);

	// Per spec, for depth/stencil formats, determine the appropriate usage
	// based on whether stencil or depth or both aspects are being used.
	VkImageAspectFlags aspectMask = pCreateInfo->subresourceRange.aspectMask;
	if (mvkAreAllFlagsEnabled(aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT | VK_IMAGE_ASPECT_DEPTH_BIT)) {
		_usage = _image->_usage & _image->_stencilUsage;
	} else if (mvkIsAnyFlagEnabled(aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT)) {
		_usage = _image->_stencilUsage;
	} else {
		_usage = _image->_usage;
	}
	// Image views can't be used in transfer commands.
	mvkDisableFlags(_usage, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT));

	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_IMAGE_VIEW_USAGE_CREATE_INFO: {
				auto* pViewUsageInfo = (VkImageViewUsageCreateInfo*)next;
				VkImageUsageFlags newUsage = pViewUsageInfo->usage;
				mvkDisableFlags(newUsage, (VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT));
				if (mvkAreAllFlagsEnabled(_usage, newUsage)) { _usage = newUsage; }
				break;
			}
            /* case VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_INFO_KHR: {
                const VkSamplerYcbcrConversionInfoKHR* sampConvInfo = (const VkSamplerYcbcrConversionInfoKHR*)next;
                break;
            } */
			default:
				break;
		}
	}

	VkImageType imgType = _image->getImageType();
	VkImageViewType viewType = pCreateInfo->viewType;

	// VK_KHR_maintenance1 supports taking 2D image views of 3D slices for sampling.
	// No dice in Metal. But we are able to fake out a 3D render attachment by making the Metal view
	// itself a 3D texture (when we create it), and setting the rendering depthPlane appropriately.
	if ((viewType == VK_IMAGE_VIEW_TYPE_2D || viewType == VK_IMAGE_VIEW_TYPE_2D_ARRAY) && (imgType == VK_IMAGE_TYPE_3D)) {
		if (!mvkIsOnlyAnyFlagEnabled(_usage, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImageView(): 2D views on 3D images can only be used as color attachments."));
		}
	}

	// If a 2D array view on a 2D image with layerCount 1, and the only usages are
	// attachment usages, then force the use of a 2D non-arrayed view. This is important for
	// input attachments, or they won't match the types declared in the fragment shader.
	// Sampled and storage usages are not: if we try to bind a non-arrayed 2D view
	// to a 2D image variable, we could wind up with the same problem this is intended to fix.
	if (mvkIsOnlyAnyFlagEnabled(_usage, (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
										 VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
										 VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT |
										 VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT))) {
		if (_mtlTextureType == MTLTextureType2DArray && _image->_mtlTextureType == MTLTextureType2D) {
			_mtlTextureType = MTLTextureType2D;
#if MVK_MACOS_OR_IOS
		} else if (_mtlTextureType == MTLTextureType2DMultisampleArray && _image->_mtlTextureType == MTLTextureType2DMultisample) {
			_mtlTextureType = MTLTextureType2DMultisample;
#endif
		}
	}

	// Remember the subresource range, and determine the actual number of mip levels and texture slices
    _subresourceRange = pCreateInfo->subresourceRange;
	if (_subresourceRange.levelCount == VK_REMAINING_MIP_LEVELS) {
		_subresourceRange.levelCount = _image->getMipLevelCount() - _subresourceRange.baseMipLevel;
	}
	if (_subresourceRange.layerCount == VK_REMAINING_ARRAY_LAYERS) {
		_subresourceRange.layerCount = _image->getLayerCount() - _subresourceRange.baseArrayLayer;
	}

	bool isAttachment = mvkIsAnyFlagEnabled(_usage, (VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
													 VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
													 VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT |
													 VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT));
	if (isAttachment && _subresourceRange.layerCount > 1) {
		if ( !_device->_pMetalFeatures->layeredRendering ) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImageView() : This device does not support rendering to array (layered) attachments."));
		}
		if (_image->getSampleCount() != VK_SAMPLE_COUNT_1_BIT && !_device->_pMetalFeatures->multisampleLayeredRendering ) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImageView() : This device does not support rendering to multisampled array (layered) attachments."));
		}
	}

    VkExtent2D blockTexelSizeOfPlane[3];
    uint32_t bytesPerBlockOfPlane[3];
    MTLPixelFormat mtlPixFmtOfPlane[3];
    uint8_t subsamplingPlaneCount = getPixelFormats()->getChromaSubsamplingPlanes(pCreateInfo->format, blockTexelSizeOfPlane, bytesPerBlockOfPlane, mtlPixFmtOfPlane),
            beginPlaneIndex = 0,
            endPlaneIndex = subsamplingPlaneCount;
    if (subsamplingPlaneCount == 0) {
        if (_subresourceRange.aspectMask & (VK_IMAGE_ASPECT_PLANE_0_BIT | VK_IMAGE_ASPECT_PLANE_1_BIT | VK_IMAGE_ASPECT_PLANE_2_BIT)) {
            beginPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(_subresourceRange.aspectMask);
        }
        endPlaneIndex = beginPlaneIndex + 1;
        mtlPixFmtOfPlane[beginPlaneIndex] = getPixelFormats()->getMTLPixelFormat(pCreateInfo->format);
    } else {
        if (!mvkVkComponentMappingsMatch(pCreateInfo->components, {VK_COMPONENT_SWIZZLE_R, VK_COMPONENT_SWIZZLE_G, VK_COMPONENT_SWIZZLE_B, VK_COMPONENT_SWIZZLE_A})) {
            setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImageView() : Image view swizzling for multi planar formats is not supported."));
        }
    }
    for (uint8_t planeIndex = beginPlaneIndex; planeIndex < endPlaneIndex; planeIndex++) {
        _planes.push_back(new MVKImageViewPlane(this, planeIndex, mtlPixFmtOfPlane[planeIndex], pCreateInfo));
    }
}

// Memory detached in destructor too, as a fail-safe.
MVKImageView::~MVKImageView() {
	detachMemory();
}

// Overridden to detach from the resource memory when the app destroys this object.
// This object can be retained in a descriptor after the app destroys it, even
// though the descriptor can't use it. But doing so retains usuable resource memory.
void MVKImageView::destroy() {
	detachMemory();
	MVKVulkanAPIDeviceObject::destroy();
}

// Potentially called twice, from destroy() and destructor, so ensure everything is nulled out.
void MVKImageView::detachMemory() {
	mvkDestroyContainerContents(_planes);
}


#pragma mark -
#pragma mark MVKSamplerYcbcrConversion

void MVKSamplerYcbcrConversion::updateConstExprSampler(MSLConstexprSampler& constExprSampler) const {
	constExprSampler.planes = _planes;
	constExprSampler.resolution = _resolution;
	constExprSampler.chroma_filter = _chroma_filter;
	constExprSampler.x_chroma_offset = _x_chroma_offset;
	constExprSampler.y_chroma_offset = _y_chroma_offset;
    for (uint32_t i = 0; i < 4; ++i) {
		constExprSampler.swizzle[i] = _swizzle[i];
    }
	constExprSampler.ycbcr_model = _ycbcr_model;
	constExprSampler.ycbcr_range = _ycbcr_range;
    constExprSampler.bpc = _bpc;
	constExprSampler.ycbcr_conversion_enable = true;
}

static MSLSamplerFilter getSpvMinMagFilterFromVkFilter(VkFilter vkFilter) {
    switch (vkFilter) {
        case VK_FILTER_LINEAR:    return MSL_SAMPLER_FILTER_LINEAR;

        case VK_FILTER_NEAREST:
        default:
            return MSL_SAMPLER_FILTER_NEAREST;
    }
}

static MSLChromaLocation getSpvChromaLocationFromVkChromaLocation(VkChromaLocation vkChromaLocation) {
	switch (vkChromaLocation) {
		default:
		case VK_CHROMA_LOCATION_COSITED_EVEN:   return MSL_CHROMA_LOCATION_COSITED_EVEN;
		case VK_CHROMA_LOCATION_MIDPOINT:       return MSL_CHROMA_LOCATION_MIDPOINT;
	}
}

static MSLComponentSwizzle getSpvComponentSwizzleFromVkComponentMapping(VkComponentSwizzle vkComponentSwizzle) {
	switch (vkComponentSwizzle) {
		default:
		case VK_COMPONENT_SWIZZLE_IDENTITY:     return MSL_COMPONENT_SWIZZLE_IDENTITY;
		case VK_COMPONENT_SWIZZLE_ZERO:         return MSL_COMPONENT_SWIZZLE_ZERO;
		case VK_COMPONENT_SWIZZLE_ONE:          return MSL_COMPONENT_SWIZZLE_ONE;
		case VK_COMPONENT_SWIZZLE_R:            return MSL_COMPONENT_SWIZZLE_R;
		case VK_COMPONENT_SWIZZLE_G:            return MSL_COMPONENT_SWIZZLE_G;
		case VK_COMPONENT_SWIZZLE_B:            return MSL_COMPONENT_SWIZZLE_B;
		case VK_COMPONENT_SWIZZLE_A:            return MSL_COMPONENT_SWIZZLE_A;
	}
}

static MSLSamplerYCbCrModelConversion getSpvSamplerYCbCrModelConversionFromVkSamplerYcbcrModelConversion(VkSamplerYcbcrModelConversion vkSamplerYcbcrModelConversion) {
	switch (vkSamplerYcbcrModelConversion) {
		default:
		case VK_SAMPLER_YCBCR_MODEL_CONVERSION_RGB_IDENTITY:   return MSL_SAMPLER_YCBCR_MODEL_CONVERSION_RGB_IDENTITY;
		case VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_IDENTITY: return MSL_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_IDENTITY;
		case VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_709:      return MSL_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_BT_709;
		case VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_601:      return MSL_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_BT_601;
		case VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_2020:     return MSL_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_BT_2020;
	}
}

static MSLSamplerYCbCrRange getSpvSamplerYcbcrRangeFromVkSamplerYcbcrRange(VkSamplerYcbcrRange vkSamplerYcbcrRange) {
	switch (vkSamplerYcbcrRange) {
		default:
		case VK_SAMPLER_YCBCR_RANGE_ITU_FULL:   return MSL_SAMPLER_YCBCR_RANGE_ITU_FULL;
		case VK_SAMPLER_YCBCR_RANGE_ITU_NARROW: return MSL_SAMPLER_YCBCR_RANGE_ITU_NARROW;
	}
}

MVKSamplerYcbcrConversion::MVKSamplerYcbcrConversion(MVKDevice* device, const VkSamplerYcbcrConversionCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	MVKPixelFormats* pixFmts = getPixelFormats();
	_planes = std::max(pixFmts->getChromaSubsamplingPlaneCount(pCreateInfo->format), (uint8_t)1u);
	_bpc = pixFmts->getChromaSubsamplingComponentBits(pCreateInfo->format);
	_resolution = pixFmts->getChromaSubsamplingResolution(pCreateInfo->format);
	_chroma_filter = getSpvMinMagFilterFromVkFilter(pCreateInfo->chromaFilter);
	_x_chroma_offset = getSpvChromaLocationFromVkChromaLocation(pCreateInfo->xChromaOffset);
	_y_chroma_offset = getSpvChromaLocationFromVkChromaLocation(pCreateInfo->yChromaOffset);
	_swizzle[0] = getSpvComponentSwizzleFromVkComponentMapping(pCreateInfo->components.r);
	_swizzle[1] = getSpvComponentSwizzleFromVkComponentMapping(pCreateInfo->components.g);
	_swizzle[2] = getSpvComponentSwizzleFromVkComponentMapping(pCreateInfo->components.b);
	_swizzle[3] = getSpvComponentSwizzleFromVkComponentMapping(pCreateInfo->components.a);
	_ycbcr_model = getSpvSamplerYCbCrModelConversionFromVkSamplerYcbcrModelConversion(pCreateInfo->ycbcrModel);
	_ycbcr_range = getSpvSamplerYcbcrRangeFromVkSamplerYcbcrRange(pCreateInfo->ycbcrRange);
	_forceExplicitReconstruction = pCreateInfo->forceExplicitReconstruction;
}


#pragma mark -
#pragma mark MVKSampler

bool MVKSampler::getConstexprSampler(mvk::MSLResourceBinding& resourceBinding) {
	resourceBinding.requiresConstExprSampler = _requiresConstExprSampler;
	if (_requiresConstExprSampler) {
		resourceBinding.constExprSampler = _constExprSampler;
	}
	return _requiresConstExprSampler;
}

// Ensure available Metal features.
MTLSamplerAddressMode MVKSampler::getMTLSamplerAddressMode(VkSamplerAddressMode vkMode) {
	if ((vkMode == VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER && !_device->_pMetalFeatures->samplerClampToBorder) ||
		(vkMode == VK_SAMPLER_ADDRESS_MODE_MIRROR_CLAMP_TO_EDGE && !_device->_pMetalFeatures->samplerMirrorClampToEdge)) {
		return MTLSamplerAddressModeClampToZero;
	}
	return mvkMTLSamplerAddressModeFromVkSamplerAddressMode(vkMode);
}

// Returns an Metal sampler descriptor constructed from the properties of this image.
// It is the caller's responsibility to release the returned descriptor object.
MTLSamplerDescriptor* MVKSampler::newMTLSamplerDescriptor(const VkSamplerCreateInfo* pCreateInfo) {

	MTLSamplerDescriptor* mtlSampDesc = [MTLSamplerDescriptor new];		// retained
	mtlSampDesc.sAddressMode = getMTLSamplerAddressMode(pCreateInfo->addressModeU);
	mtlSampDesc.tAddressMode = getMTLSamplerAddressMode(pCreateInfo->addressModeV);
    if (!pCreateInfo->unnormalizedCoordinates) {
        mtlSampDesc.rAddressMode = getMTLSamplerAddressMode(pCreateInfo->addressModeW);
    }
#if MVK_MACOS_OR_IOS
	mtlSampDesc.borderColorMVK = mvkMTLSamplerBorderColorFromVkBorderColor(pCreateInfo->borderColor);
#endif

	mtlSampDesc.minFilter = mvkMTLSamplerMinMagFilterFromVkFilter(pCreateInfo->minFilter);
	mtlSampDesc.magFilter = mvkMTLSamplerMinMagFilterFromVkFilter(pCreateInfo->magFilter);
    mtlSampDesc.mipFilter = (pCreateInfo->unnormalizedCoordinates
                             ? MTLSamplerMipFilterNotMipmapped
                             : mvkMTLSamplerMipFilterFromVkSamplerMipmapMode(pCreateInfo->mipmapMode));
	mtlSampDesc.lodMinClamp = pCreateInfo->minLod;
	mtlSampDesc.lodMaxClamp = pCreateInfo->maxLod;
	mtlSampDesc.maxAnisotropy = (pCreateInfo->anisotropyEnable
								 ? mvkClamp(pCreateInfo->maxAnisotropy, 1.0f, _device->_pProperties->limits.maxSamplerAnisotropy)
								 : 1);
	mtlSampDesc.normalizedCoordinates = !pCreateInfo->unnormalizedCoordinates;
	mtlSampDesc.supportArgumentBuffers = isUsingMetalArgumentBuffers();

	// If compareEnable is true, but dynamic samplers with depth compare are not available
	// on this device, this sampler must only be used as an immutable sampler, and will
	// be automatically hardcoded into the shader MSL. An error will be triggered if this
	// sampler is used to update or push a descriptor.
	if (pCreateInfo->compareEnable && !_requiresConstExprSampler) {
		mtlSampDesc.compareFunctionMVK = mvkMTLCompareFunctionFromVkCompareOp(pCreateInfo->compareOp);
	}

	return mtlSampDesc;
}

MVKSampler::MVKSampler(MVKDevice* device, const VkSamplerCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
    _ycbcrConversion = NULL;
    for (const auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_INFO_KHR: {
				const VkSamplerYcbcrConversionInfoKHR* sampConvInfo = (const VkSamplerYcbcrConversionInfoKHR*)next;
				_ycbcrConversion = (MVKSamplerYcbcrConversion*)(sampConvInfo->conversion);
				break;
			}
			default:
				break;
		}
	}

	_requiresConstExprSampler = (pCreateInfo->compareEnable && !_device->_pMetalFeatures->depthSampleCompare) || _ycbcrConversion;

	@autoreleasepool {
		auto mtlDev = getMTLDevice();
		@synchronized (mtlDev) {
			_mtlSamplerState = [mtlDev newSamplerStateWithDescriptor: [newMTLSamplerDescriptor(pCreateInfo) autorelease]];
		}
	}

	initConstExprSampler(pCreateInfo);
}

static MSLSamplerMipFilter getSpvMipFilterFromVkMipMode(VkSamplerMipmapMode vkMipMode) {
	switch (vkMipMode) {
		case VK_SAMPLER_MIPMAP_MODE_LINEAR:		return MSL_SAMPLER_MIP_FILTER_LINEAR;
		case VK_SAMPLER_MIPMAP_MODE_NEAREST:	return MSL_SAMPLER_MIP_FILTER_NEAREST;

		default:
			return MSL_SAMPLER_MIP_FILTER_NONE;
	}
}

static MSLSamplerAddress getSpvAddressModeFromVkAddressMode(VkSamplerAddressMode vkAddrMode) {
	switch (vkAddrMode) {
		case VK_SAMPLER_ADDRESS_MODE_REPEAT:			return MSL_SAMPLER_ADDRESS_REPEAT;
		case VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT:	return MSL_SAMPLER_ADDRESS_MIRRORED_REPEAT;
		case VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER:	return MSL_SAMPLER_ADDRESS_CLAMP_TO_BORDER;

		case VK_SAMPLER_ADDRESS_MODE_MIRROR_CLAMP_TO_EDGE:
		case VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE:
		default:
			return MSL_SAMPLER_ADDRESS_CLAMP_TO_EDGE;
	}
}

static MSLSamplerCompareFunc getSpvCompFuncFromVkCompOp(VkCompareOp vkCompOp) {
	switch (vkCompOp) {
		case VK_COMPARE_OP_LESS:				return MSL_SAMPLER_COMPARE_FUNC_LESS;
		case VK_COMPARE_OP_EQUAL:				return MSL_SAMPLER_COMPARE_FUNC_EQUAL;
		case VK_COMPARE_OP_LESS_OR_EQUAL:		return MSL_SAMPLER_COMPARE_FUNC_LESS_EQUAL;
		case VK_COMPARE_OP_GREATER:				return MSL_SAMPLER_COMPARE_FUNC_GREATER;
		case VK_COMPARE_OP_NOT_EQUAL:			return MSL_SAMPLER_COMPARE_FUNC_NOT_EQUAL;
		case VK_COMPARE_OP_GREATER_OR_EQUAL:	return MSL_SAMPLER_COMPARE_FUNC_GREATER_EQUAL;
		case VK_COMPARE_OP_ALWAYS:				return MSL_SAMPLER_COMPARE_FUNC_ALWAYS;

		case VK_COMPARE_OP_NEVER:
		default:
			return MSL_SAMPLER_COMPARE_FUNC_NEVER;
	}
}

static MSLSamplerBorderColor getSpvBorderColorFromVkBorderColor(VkBorderColor vkBorderColor) {
	switch (vkBorderColor) {
		case VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK:
		case VK_BORDER_COLOR_INT_OPAQUE_BLACK:
			return MSL_SAMPLER_BORDER_COLOR_OPAQUE_BLACK;

		case VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE:
		case VK_BORDER_COLOR_INT_OPAQUE_WHITE:
			return MSL_SAMPLER_BORDER_COLOR_OPAQUE_WHITE;

		case VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK:
		case VK_BORDER_COLOR_INT_TRANSPARENT_BLACK:
		default:
			return MSL_SAMPLER_BORDER_COLOR_TRANSPARENT_BLACK;
	}
}

void MVKSampler::initConstExprSampler(const VkSamplerCreateInfo* pCreateInfo) {
	if ( !_requiresConstExprSampler ) { return; }

	_constExprSampler.coord = pCreateInfo->unnormalizedCoordinates ? MSL_SAMPLER_COORD_PIXEL : MSL_SAMPLER_COORD_NORMALIZED;
	_constExprSampler.min_filter = getSpvMinMagFilterFromVkFilter(pCreateInfo->minFilter);
	_constExprSampler.mag_filter = getSpvMinMagFilterFromVkFilter(pCreateInfo->magFilter);
	_constExprSampler.mip_filter = getSpvMipFilterFromVkMipMode(pCreateInfo->mipmapMode);
	_constExprSampler.s_address = getSpvAddressModeFromVkAddressMode(pCreateInfo->addressModeU);
	_constExprSampler.t_address = getSpvAddressModeFromVkAddressMode(pCreateInfo->addressModeV);
	_constExprSampler.r_address = getSpvAddressModeFromVkAddressMode(pCreateInfo->addressModeW);
	_constExprSampler.compare_func = getSpvCompFuncFromVkCompOp(pCreateInfo->compareOp);
	_constExprSampler.border_color = getSpvBorderColorFromVkBorderColor(pCreateInfo->borderColor);
	_constExprSampler.lod_clamp_min = pCreateInfo->minLod;
	_constExprSampler.lod_clamp_max = pCreateInfo->maxLod;
	_constExprSampler.max_anisotropy = pCreateInfo->maxAnisotropy;
	_constExprSampler.compare_enable = pCreateInfo->compareEnable;
	_constExprSampler.lod_clamp_enable = false;
	_constExprSampler.anisotropy_enable = pCreateInfo->anisotropyEnable;
    if (_ycbcrConversion) {
        _ycbcrConversion->updateConstExprSampler(_constExprSampler);
    }
}

// Memory detached in destructor too, as a fail-safe.
MVKSampler::~MVKSampler() {
	detachMemory();
}

// Overridden to detach from the resource memory when the app destroys this object.
// This object can be retained in a descriptor after the app destroys it, even
// though the descriptor can't use it. But doing so retains usuable resource memory.
void MVKSampler::destroy() {
	detachMemory();
	MVKVulkanAPIDeviceObject::destroy();
}

// Potentially called twice, from destroy() and destructor, so ensure everything is nulled out.
void MVKSampler::detachMemory() {
	@synchronized (getMTLDevice()) {
		[_mtlSamplerState release];
		_mtlSamplerState = nil;
	}
}
