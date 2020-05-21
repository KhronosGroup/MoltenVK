/*
 * MVKImage.mm
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

#include "MVKImage.h"
#include "MVKQueue.h"
#include "MVKSwapchain.h"
#include "MVKCommandBuffer.h"
#include "MVKCmdDebug.h"
#include "MVKEnvironment.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKLogging.h"
#include "MVKCodec.h"
#import "MTLTextureDescriptor+MoltenVK.h"
#import "MTLSamplerDescriptor+MoltenVK.h"

using namespace std;
using namespace SPIRV_CROSS_NAMESPACE;


#pragma mark MVKImage

void MVKImage::propogateDebugName() { setLabelIfNotNil(_mtlTexture, _debugName); }

VkImageType MVKImage::getImageType() { return mvkVkImageTypeFromMTLTextureType(_mtlTextureType); }

VkFormat MVKImage::getVkFormat() { return getPixelFormats()->getVkFormat(_mtlPixelFormat); }

bool MVKImage::getIsDepthStencil() { return getPixelFormats()->getFormatType(_mtlPixelFormat) == kMVKFormatDepthStencil; }

bool MVKImage::getIsCompressed() { return getPixelFormats()->getFormatType(_mtlPixelFormat) == kMVKFormatCompressed; }

VkExtent3D MVKImage::getExtent3D(uint32_t mipLevel) {
	return mvkMipmapLevelSizeFromBaseSize3D(_extent, mipLevel);
}

VkDeviceSize MVKImage::getBytesPerRow(uint32_t mipLevel) {
    size_t bytesPerRow = getPixelFormats()->getBytesPerRow(_mtlPixelFormat, getExtent3D(mipLevel).width);
    return mvkAlignByteCount(bytesPerRow, _rowByteAlignment);
}

VkDeviceSize MVKImage::getBytesPerLayer(uint32_t mipLevel) {
    return getPixelFormats()->getBytesPerLayer(_mtlPixelFormat, getBytesPerRow(mipLevel), getExtent3D(mipLevel).height);
}

VkResult MVKImage::getSubresourceLayout(const VkImageSubresource* pSubresource,
										VkSubresourceLayout* pLayout) {
	MVKImageSubresource* pImgRez = getSubresource(pSubresource->mipLevel,
												  pSubresource->arrayLayer);
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
    imgData.usage = _usage;
}


#pragma mark Resource memory

void MVKImage::applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
								  VkPipelineStageFlags dstStageMask,
								  MVKPipelineBarrier& barrier,
								  MVKCommandEncoder* cmdEncoder,
								  MVKCommandUse cmdUse) {
#if MVK_MACOS
	if ( needsHostReadSync(srcStageMask, dstStageMask, barrier) ) {
		[cmdEncoder->getMTLBlitEncoder(cmdUse) synchronizeResource: getMTLTexture()];
	}
#endif
}

void MVKImage::applyImageMemoryBarrier(VkPipelineStageFlags srcStageMask,
									   VkPipelineStageFlags dstStageMask,
									   MVKPipelineBarrier& barrier,
									   MVKCommandEncoder* cmdEncoder,
									   MVKCommandUse cmdUse) {

	// Extract the mipmap levels that are to be updated
	uint32_t mipLvlStart = barrier.baseMipLevel;
	uint32_t mipLvlEnd = (barrier.levelCount == (uint8_t)VK_REMAINING_MIP_LEVELS
						  ? getMipLevelCount()
						  : (mipLvlStart + barrier.levelCount));

	// Extract the cube or array layers (slices) that are to be updated
	uint32_t layerStart = barrier.baseArrayLayer;
	uint32_t layerEnd = (barrier.layerCount == (uint16_t)VK_REMAINING_ARRAY_LAYERS
						 ? getLayerCount()
						 : (layerStart + barrier.layerCount));

#if MVK_MACOS
	bool needsSync = needsHostReadSync(srcStageMask, dstStageMask, barrier);
	id<MTLTexture> mtlTex = needsSync ? getMTLTexture() : nil;
	id<MTLBlitCommandEncoder> mtlBlitEncoder = needsSync ? cmdEncoder->getMTLBlitEncoder(cmdUse) : nil;
#endif

	// Iterate across mipmap levels and layers, and update the image layout state for each
	for (uint32_t mipLvl = mipLvlStart; mipLvl < mipLvlEnd; mipLvl++) {
		for (uint32_t layer = layerStart; layer < layerEnd; layer++) {
			MVKImageSubresource* pImgRez = getSubresource(mipLvl, layer);
			if (pImgRez) { pImgRez->layoutState = barrier.newLayout; }
#if MVK_MACOS
			if (needsSync) { [mtlBlitEncoder synchronizeTexture: mtlTex slice: layer level: mipLvl]; }
#endif
		}
	}
}

// Returns whether the specified image memory barrier requires a sync between this
// texture and host memory for the purpose of the host reading texture memory.
bool MVKImage::needsHostReadSync(VkPipelineStageFlags srcStageMask,
								 VkPipelineStageFlags dstStageMask,
								 MVKPipelineBarrier& barrier) {
#if MVK_MACOS
	return ((barrier.newLayout == VK_IMAGE_LAYOUT_GENERAL) &&
			mvkIsAnyFlagEnabled(barrier.dstAccessMask, (VK_ACCESS_HOST_READ_BIT | VK_ACCESS_MEMORY_READ_BIT)) &&
			isMemoryHostAccessible() && !isMemoryHostCoherent());
#endif
#if MVK_IOS
	return false;
#endif
}

// Returns a pointer to the internal subresource for the specified MIP level layer.
MVKImageSubresource* MVKImage::getSubresource(uint32_t mipLevel, uint32_t arrayLayer) {
	uint32_t srIdx = (mipLevel * _arrayLayers) + arrayLayer;
	return (srIdx < _subresources.size()) ? &_subresources[srIdx] : NULL;
}

VkResult MVKImage::getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements) {
	pMemoryRequirements->size = _byteCount;
	pMemoryRequirements->alignment = _byteAlignment;
	pMemoryRequirements->memoryTypeBits = (_isDepthStencilAttachment
										   ? _device->getPhysicalDevice()->getPrivateMemoryTypes()
										   : _device->getPhysicalDevice()->getAllMemoryTypes());
#if MVK_MACOS
	// Metal on macOS does not provide native support for host-coherent memory, but Vulkan requires it for Linear images
	if ( !_isLinear ) {
		mvkDisableFlags(pMemoryRequirements->memoryTypeBits, _device->getPhysicalDevice()->getHostCoherentMemoryTypes());
	}
#endif
#if MVK_IOS
	// Only transient attachments may use memoryless storage
	if (!mvkAreAllFlagsEnabled(_usage, VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT) ) {
		mvkDisableFlags(pMemoryRequirements->memoryTypeBits, _device->getPhysicalDevice()->getLazilyAllocatedMemoryTypes());
	}
#endif
	return VK_SUCCESS;
}

VkResult MVKImage::getMemoryRequirements(const void*, VkMemoryRequirements2* pMemoryRequirements) {
	pMemoryRequirements->sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
	getMemoryRequirements(&pMemoryRequirements->memoryRequirements);
	for (auto* next = (VkBaseOutStructure*)pMemoryRequirements->pNext; next; next = next->pNext) {
		switch (next->sType) {
		case VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS: {
			auto* dedicatedReqs = (VkMemoryDedicatedRequirements*)next;
			bool writable = mvkIsAnyFlagEnabled(_usage, VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT);
			dedicatedReqs->requiresDedicatedAllocation = _requiresDedicatedMemoryAllocation;
			dedicatedReqs->prefersDedicatedAllocation = (dedicatedReqs->requiresDedicatedAllocation ||
														 (!_usesTexelBuffer && (writable || !_device->_pMetalFeatures->placementHeaps)));
			break;
		}
		default:
			break;
		}
	}
	return VK_SUCCESS;
}

// Memory may have been mapped before image was bound, and needs to be loaded into the MTLTexture.
VkResult MVKImage::bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) {
	if (_deviceMemory) { _deviceMemory->removeImage(this); }

	MVKResource::bindDeviceMemory(mvkMem, memOffset);

	_usesTexelBuffer = validateUseTexelBuffer();

	flushToDevice(getDeviceMemoryOffset(), getByteCount());

	return _deviceMemory ? _deviceMemory->addImage(this) : VK_SUCCESS;
}

VkResult MVKImage::bindDeviceMemory2(const VkBindImageMemoryInfo* pBindInfo) {
	return bindDeviceMemory((MVKDeviceMemory*)pBindInfo->memory, pBindInfo->memoryOffset);
}

bool MVKImage::validateUseTexelBuffer() {
	VkExtent2D blockExt = getPixelFormats()->getBlockTexelSize(_mtlPixelFormat);
	bool isUncompressed = blockExt.width == 1 && blockExt.height == 1;

	bool useTexelBuffer = _device->_pMetalFeatures->texelBuffers;								// Texel buffers available
	useTexelBuffer = useTexelBuffer && (isMemoryHostAccessible() || _device->_pMetalFeatures->placementHeaps) && _isLinear && isUncompressed;	// Applicable memory layout
	useTexelBuffer = useTexelBuffer && _deviceMemory && _deviceMemory->_mtlBuffer;				// Buffer is available to overlay

#if MVK_MACOS
	// macOS cannot use shared memory for texel buffers.
	// Test _deviceMemory->isMemoryHostCoherent() directly because local version overrides.
	useTexelBuffer = useTexelBuffer && _deviceMemory && !_deviceMemory->isMemoryHostCoherent();
#endif

	return useTexelBuffer;
}

bool MVKImage::shouldFlushHostMemory() { return isMemoryHostAccessible() && !_usesTexelBuffer; }

// Flushes the device memory at the specified memory range into the MTLTexture. Updates
// all subresources that overlap the specified range and are in an updatable layout state.
VkResult MVKImage::flushToDevice(VkDeviceSize offset, VkDeviceSize size) {
	if (shouldFlushHostMemory()) {
		for (auto& subRez : _subresources) {
			switch (subRez.layoutState) {
				case VK_IMAGE_LAYOUT_UNDEFINED:
				case VK_IMAGE_LAYOUT_PREINITIALIZED:
				case VK_IMAGE_LAYOUT_GENERAL: {
					updateMTLTextureContent(subRez, offset, size);
					break;
				}
				default:
					break;
			}
		}
	}
	return VK_SUCCESS;
}

// Pulls content from the MTLTexture into the device memory at the specified memory range.
// Pulls from all subresources that overlap the specified range and are in an updatable layout state.
VkResult MVKImage::pullFromDevice(VkDeviceSize offset, VkDeviceSize size) {
	if (shouldFlushHostMemory()) {
		for (auto& subRez : _subresources) {
			switch (subRez.layoutState) {
				case VK_IMAGE_LAYOUT_GENERAL: {
					getMTLTextureContent(subRez, offset, size);
					break;
				}
				default:
					break;
			}
		}
	}
	return VK_SUCCESS;
}


#pragma mark Metal

id<MTLTexture> MVKImage::getMTLTexture() {
	if ( !_mtlTexture && _mtlPixelFormat ) {

		// Lock and check again in case another thread has created the texture.
		lock_guard<mutex> lock(_lock);
		if (_mtlTexture) { return _mtlTexture; }

		_mtlTexture = newMTLTexture();   // retained

		propogateDebugName();
	}
	return _mtlTexture;
}

id<MTLTexture> MVKImage::getMTLTexture(MTLPixelFormat mtlPixFmt) {
	if (mtlPixFmt == _mtlPixelFormat) { return getMTLTexture(); }

	id<MTLTexture> mtlTex = _mtlTextureViews[mtlPixFmt];
	if ( !mtlTex ) {
		// Lock and check again in case another thread has created the view texture.
		// baseTex retreived outside of lock to avoid deadlock if it too needs to be lazily created.
		id<MTLTexture> baseTex = getMTLTexture();
		lock_guard<mutex> lock(_lock);
		mtlTex = _mtlTextureViews[mtlPixFmt];
		if ( !mtlTex ) {
			mtlTex = [baseTex newTextureViewWithPixelFormat: mtlPixFmt];	// retained
			_mtlTextureViews[mtlPixFmt] = mtlTex;
		}
	}
	return mtlTex;
}

id<MTLTexture> MVKImage::newMTLTexture() {
	id<MTLTexture> mtlTex = nil;
	MTLTextureDescriptor* mtlTexDesc = newMTLTextureDescriptor();	// temp retain

	if (_ioSurface) {
		mtlTex = [getMTLDevice() newTextureWithDescriptor: mtlTexDesc iosurface: _ioSurface plane: 0];
	} else if (_usesTexelBuffer) {
		mtlTex = [_deviceMemory->_mtlBuffer newTextureWithDescriptor: mtlTexDesc
															  offset: getDeviceMemoryOffset()
														 bytesPerRow: _subresources[0].layout.rowPitch];
	} else if (_deviceMemory->_mtlHeap && !getIsDepthStencil()) {	// Metal support for depth/stencil from heaps is flaky
		mtlTex = [_deviceMemory->_mtlHeap newTextureWithDescriptor: mtlTexDesc
															offset: getDeviceMemoryOffset()];
		if (_isAliasable) [mtlTex makeAliasable];
	} else {
		mtlTex = [getMTLDevice() newTextureWithDescriptor: mtlTexDesc];
	}

	[mtlTexDesc release];											// temp release
	return mtlTex;
}

VkResult MVKImage::setMTLTexture(id<MTLTexture> mtlTexture) {
	lock_guard<mutex> lock(_lock);

	releaseMTLTexture();
	releaseIOSurface();

	_mtlTexture = [mtlTexture retain];		// retained

	_mtlPixelFormat = mtlTexture.pixelFormat;
	_mtlTextureType = mtlTexture.textureType;
	_extent.width = uint32_t(mtlTexture.width);
	_extent.height = uint32_t(mtlTexture.height);
	_extent.depth = uint32_t(mtlTexture.depth);
	_mipLevels = uint32_t(mtlTexture.mipmapLevelCount);
	_samples = mvkVkSampleCountFlagBitsFromSampleCount(mtlTexture.sampleCount);
	_arrayLayers = uint32_t(mtlTexture.arrayLength);
	_usage = getPixelFormats()->getVkImageUsageFlags(mtlTexture.usage, _mtlPixelFormat);

	if (_device->_pMetalFeatures->ioSurfaces) {
		_ioSurface = mtlTexture.iosurface;
		CFRetain(_ioSurface);
	}

	return VK_SUCCESS;
}

// Removes and releases the MTLTexture object, and all associated texture views
void MVKImage::releaseMTLTexture() {
	[_mtlTexture release];
	_mtlTexture = nil;
	for (auto elem : _mtlTextureViews) { [elem.second release]; }
	_mtlTextureViews.clear();
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

    if (!_device->_pMetalFeatures->ioSurfaces) { return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkUseIOSurfaceMVK() : IOSurfaces are not supported on this platform."); }

#if MVK_SUPPORT_IOSURFACE_BOOL

    releaseMTLTexture();
    releaseIOSurface();

	MVKPixelFormats* pixFmts = getPixelFormats();

	if (ioSurface) {
		if (IOSurfaceGetWidth(ioSurface) != _extent.width) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface width %zu does not match VkImage width %d.", IOSurfaceGetWidth(ioSurface), _extent.width); }
		if (IOSurfaceGetHeight(ioSurface) != _extent.height) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface height %zu does not match VkImage height %d.", IOSurfaceGetHeight(ioSurface), _extent.height); }
		if (IOSurfaceGetBytesPerElement(ioSurface) != pixFmts->getBytesPerBlock(_mtlPixelFormat)) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface bytes per element %zu does not match VkImage bytes per element %d.", IOSurfaceGetBytesPerElement(ioSurface), pixFmts->getBytesPerBlock(_mtlPixelFormat)); }
		if (IOSurfaceGetElementWidth(ioSurface) != pixFmts->getBlockTexelSize(_mtlPixelFormat).width) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface element width %zu does not match VkImage element width %d.", IOSurfaceGetElementWidth(ioSurface), pixFmts->getBlockTexelSize(_mtlPixelFormat).width); }
		if (IOSurfaceGetElementHeight(ioSurface) != pixFmts->getBlockTexelSize(_mtlPixelFormat).height) { return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkUseIOSurfaceMVK() : IOSurface element height %zu does not match VkImage element height %d.", IOSurfaceGetElementHeight(ioSurface), pixFmts->getBlockTexelSize(_mtlPixelFormat).height); }

        _ioSurface = ioSurface;
        CFRetain(_ioSurface);
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		@autoreleasepool {
			_ioSurface = IOSurfaceCreate((CFDictionaryRef)@{
															(id)kIOSurfaceWidth: @(_extent.width),
															(id)kIOSurfaceHeight: @(_extent.height),
															(id)kIOSurfaceBytesPerElement: @(pixFmts->getBytesPerBlock(_mtlPixelFormat)),
															(id)kIOSurfaceElementWidth: @(pixFmts->getBlockTexelSize(_mtlPixelFormat).width),
															(id)kIOSurfaceElementHeight: @(pixFmts->getBlockTexelSize(_mtlPixelFormat).height),
															(id)kIOSurfaceIsGlobal: @(true),    // Deprecated but needed for interprocess transfers
															});
		}
#pragma clang diagnostic pop

    }

#endif

    return VK_SUCCESS;
}

// Returns a Metal texture descriptor constructed from the properties of this image.
// It is the caller's responsibility to release the returned descriptor object.
MTLTextureDescriptor* MVKImage::newMTLTextureDescriptor() {
	MTLPixelFormat mtlPixFmt = _mtlPixelFormat;
	MTLTextureUsage minUsage = MTLTextureUsageUnknown;
#if MVK_MACOS
	if (_is3DCompressed) {
		// Metal before 3.0 doesn't support 3D compressed textures, so we'll decompress
		// the texture ourselves. This, then, is the *uncompressed* format.
		mtlPixFmt = MTLPixelFormatBGRA8Unorm;
		minUsage = MTLTextureUsageShaderWrite;
	}
#endif

	MTLTextureDescriptor* mtlTexDesc = [MTLTextureDescriptor new];	// retained
	mtlTexDesc.pixelFormat = mtlPixFmt;
	mtlTexDesc.textureType = _mtlTextureType;
	mtlTexDesc.width = _extent.width;
	mtlTexDesc.height = _extent.height;
	mtlTexDesc.depth = _extent.depth;
	mtlTexDesc.mipmapLevelCount = _mipLevels;
	mtlTexDesc.sampleCount = mvkSampleCountFromVkSampleCountFlagBits(_samples);
	mtlTexDesc.arrayLength = _arrayLayers;
	mtlTexDesc.usageMVK = getPixelFormats()->getMTLTextureUsage(_usage, mtlPixFmt, minUsage);
	mtlTexDesc.storageModeMVK = getMTLStorageMode();
	mtlTexDesc.cpuCacheMode = getMTLCPUCacheMode();

	return mtlTexDesc;
}

MTLStorageMode MVKImage::getMTLStorageMode() {
    if ( !_deviceMemory ) return MTLStorageModePrivate;

    MTLStorageMode stgMode = _deviceMemory->getMTLStorageMode();

    if (_ioSurface && stgMode == MTLStorageModePrivate) { stgMode = MTLStorageModeShared; }

#if MVK_MACOS
	// For macOS, textures cannot use Shared storage mode, so change to Managed storage mode.
    if (stgMode == MTLStorageModeShared) { stgMode = MTLStorageModeManaged; }
#endif
    return stgMode;
}

MTLCPUCacheMode MVKImage::getMTLCPUCacheMode() {
	return _deviceMemory ? _deviceMemory->getMTLCPUCacheMode() : MTLCPUCacheModeDefaultCache;
}

bool MVKImage::isMemoryHostCoherent() {
    return (getMTLStorageMode() == MTLStorageModeShared);
}

// Updates the contents of the underlying MTLTexture, corresponding to the
// specified subresource definition, from the underlying memory buffer.
void MVKImage::updateMTLTextureContent(MVKImageSubresource& subresource,
                                       VkDeviceSize offset, VkDeviceSize size) {

	VkImageSubresource& imgSubRez = subresource.subresource;
	VkSubresourceLayout& imgLayout = subresource.layout;

	// Check if subresource overlaps the memory range.
    VkDeviceSize memStart = offset;
    VkDeviceSize memEnd = offset + size;
    VkDeviceSize imgStart = imgLayout.offset;
    VkDeviceSize imgEnd = imgLayout.offset + imgLayout.size;
    if (imgStart >= memEnd || imgEnd <= memStart) { return; }

	// Don't update if host memory has not been mapped yet.
	void* pHostMem = getHostMemoryAddress();
	if ( !pHostMem ) { return; }

    VkExtent3D mipExtent = getExtent3D(imgSubRez.mipLevel);
    VkImageType imgType = getImageType();
    void* pImgBytes = (void*)((uintptr_t)pHostMem + imgLayout.offset);

    MTLRegion mtlRegion;
    mtlRegion.origin = MTLOriginMake(0, 0, 0);
    mtlRegion.size = mvkMTLSizeFromVkExtent3D(mipExtent);

#if MVK_MACOS
    std::unique_ptr<char[]> decompBuffer;
    if (_is3DCompressed) {
        // We cannot upload the texture data directly in this case. But we
        // can upload the decompressed image data.
        std::unique_ptr<MVKCodec> codec = mvkCreateCodec(getVkFormat());
        if (!codec) {
            reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "A 3D texture used a compressed format that MoltenVK does not yet support.");
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

	VkDeviceSize bytesPerRow = (imgType != VK_IMAGE_TYPE_1D) ? imgLayout.rowPitch : 0;
	VkDeviceSize bytesPerImage = (imgType == VK_IMAGE_TYPE_3D) ? imgLayout.depthPitch : 0;

	id<MTLTexture> mtlTex = getMTLTexture();
	if (getPixelFormats()->isPVRTCFormat(mtlTex.pixelFormat)) {
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
void MVKImage::getMTLTextureContent(MVKImageSubresource& subresource,
                                    VkDeviceSize offset, VkDeviceSize size) {

	VkImageSubresource& imgSubRez = subresource.subresource;
	VkSubresourceLayout& imgLayout = subresource.layout;

	// Check if subresource overlaps the memory range.
    VkDeviceSize memStart = offset;
    VkDeviceSize memEnd = offset + size;
    VkDeviceSize imgStart = imgLayout.offset;
    VkDeviceSize imgEnd = imgLayout.offset + imgLayout.size;
    if (imgStart >= memEnd || imgEnd <= memStart) { return; }

	// Don't update if host memory has not been mapped yet.
	void* pHostMem = getHostMemoryAddress();
	if ( !pHostMem ) { return; }

    VkExtent3D mipExtent = getExtent3D(imgSubRez.mipLevel);
    VkImageType imgType = getImageType();
    void* pImgBytes = (void*)((uintptr_t)pHostMem + imgLayout.offset);

    MTLRegion mtlRegion;
    mtlRegion.origin = MTLOriginMake(0, 0, 0);
    mtlRegion.size = mvkMTLSizeFromVkExtent3D(mipExtent);

    [getMTLTexture() getBytes: pImgBytes
                  bytesPerRow: (imgType != VK_IMAGE_TYPE_1D ? imgLayout.rowPitch : 0)
                bytesPerImage: (imgType == VK_IMAGE_TYPE_3D ? imgLayout.depthPitch : 0)
                   fromRegion: mtlRegion
                  mipmapLevel: imgSubRez.mipLevel
                        slice: imgSubRez.arrayLayer];
}


#pragma mark Construction

MVKImage::MVKImage(MVKDevice* device, const VkImageCreateInfo* pCreateInfo) : MVKResource(device) {

	_mtlTexture = nil;
	_ioSurface = nil;
	_usesTexelBuffer = false;

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
	_mtlPixelFormat = pixFmts->getMTLPixelFormat(pCreateInfo->format);
	_usage = pCreateInfo->usage;

	_is3DCompressed = (getImageType() == VK_IMAGE_TYPE_3D) && (pixFmts->getFormatType(pCreateInfo->format) == kMVKFormatCompressed) && !_device->_pMetalFeatures->native3DCompressedTextures;
	_isDepthStencilAttachment = (mvkAreAllFlagsEnabled(pCreateInfo->usage, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) ||
								 mvkAreAllFlagsEnabled(pixFmts->getVkFormatProperties(pCreateInfo->format).optimalTilingFeatures, VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT));
	_canSupportMTLTextureView = !_isDepthStencilAttachment || _device->_pMetalFeatures->stencilViews;
	_hasExpectedTexelSize = (pixFmts->getBytesPerBlock(_mtlPixelFormat) == pixFmts->getBytesPerBlock(pCreateInfo->format));

	_rowByteAlignment = _isLinear ? _device->getVkFormatTexelBufferAlignment(pCreateInfo->format, this) : mvkEnsurePowerOfTwo(pixFmts->getBytesPerBlock(pCreateInfo->format));
	if (!_isLinear && _device->_pMetalFeatures->placementHeaps) {
		MTLTextureDescriptor *mtlTexDesc = newMTLTextureDescriptor();	// temp retain
		MTLSizeAndAlign sizeAndAlign = [_device->getMTLDevice() heapTextureSizeAndAlignWithDescriptor: mtlTexDesc];
		[mtlTexDesc release];
		_byteCount = sizeAndAlign.size;
		_byteAlignment = sizeAndAlign.align;
		_isAliasable = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_IMAGE_CREATE_ALIAS_BIT);
	} else {
		// Calc _byteCount after _rowByteAlignment
		_byteAlignment = _rowByteAlignment;
		for (uint32_t mipLvl = 0; mipLvl < _mipLevels; mipLvl++) {
			_byteCount += getBytesPerLayer(mipLvl) * _extent.depth * _arrayLayers;
		}
	}

    initSubresources(pCreateInfo);

	for (const auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO: {
				auto* pExtMemInfo = (const VkExternalMemoryImageCreateInfo*)next;
				initExternalMemory(pExtMemInfo->handleTypes);
				break;
			}
			default:
				break;
		}
	}
}

VkSampleCountFlagBits MVKImage::validateSamples(const VkImageCreateInfo* pCreateInfo, bool isAttachment) {

	VkSampleCountFlagBits validSamples = pCreateInfo->samples;

	if (validSamples == VK_SAMPLE_COUNT_1_BIT) { return validSamples; }

	// Don't use getImageType() because it hasn't been set yet.
	if ( !((pCreateInfo->imageType == VK_IMAGE_TYPE_2D) || ((pCreateInfo->imageType == VK_IMAGE_TYPE_1D) && mvkTreatTexture1DAs2D())) ) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, multisampling can only be used with a 2D image type. Setting sample count to 1."));
		validSamples = VK_SAMPLE_COUNT_1_BIT;
	}

	if (getPixelFormats()->getFormatType(pCreateInfo->format) == kMVKFormatCompressed) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, multisampling cannot be used with compressed images. Setting sample count to 1."));
		validSamples = VK_SAMPLE_COUNT_1_BIT;
	}

	if (pCreateInfo->arrayLayers > 1) {
		if ( !_device->_pMetalFeatures->multisampleArrayTextures ) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : This device does not support multisampled array textures. Setting sample count to 1."));
			validSamples = VK_SAMPLE_COUNT_1_BIT;
		}
		if (isAttachment && !_device->_pMetalFeatures->multisampleLayeredRendering) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : This device does not support rendering to multisampled array (layered) attachments. Setting sample count to 1."));
			validSamples = VK_SAMPLE_COUNT_1_BIT;
		}
	}

	return validSamples;
}

void MVKImage::validateConfig(const VkImageCreateInfo* pCreateInfo, bool isAttachment) {
	MVKPixelFormats* pixFmts = getPixelFormats();

	bool is2D = (getImageType() == VK_IMAGE_TYPE_2D);
	bool isCompressed = pixFmts->getFormatType(pCreateInfo->format) == kMVKFormatCompressed;

#if MVK_IOS
	if (isCompressed && !is2D) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, compressed formats may only be used with 2D images."));
	}
#endif
#if MVK_MACOS
	if (isCompressed && !is2D) {
		if (getImageType() != VK_IMAGE_TYPE_3D) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, compressed formats may only be used with 2D or 3D images."));
		} else if (!_device->_pMetalFeatures->native3DCompressedTextures && !mvkCanDecodeFormat(pCreateInfo->format)) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, the %s compressed format may only be used with 2D images.", getPixelFormats()->getName(pCreateInfo->format)));
		}
	}
#endif

	if ((pixFmts->getFormatType(pCreateInfo->format) == kMVKFormatDepthStencil) && !is2D ) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : Under Metal, depth/stencil formats may only be used with 2D images."));
	}
	if (isAttachment && (pCreateInfo->arrayLayers > 1) && !_device->_pMetalFeatures->layeredRendering) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : This device does not support rendering to array (layered) attachments."));
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

#if MVK_MACOS
	if (isAttachment) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage() : This device does not support rendering to linear (VK_IMAGE_TILING_LINEAR) images."));
		isLin = false;
	}
#endif

	return isLin;
}


// Initializes the subresource definitions.
void MVKImage::initSubresources(const VkImageCreateInfo* pCreateInfo) {
	_subresources.reserve(_mipLevels * _arrayLayers);

	MVKImageSubresource subRez;
	subRez.layoutState = pCreateInfo->initialLayout;

	for (uint32_t mipLvl = 0; mipLvl < _mipLevels; mipLvl++) {
		subRez.subresource.mipLevel = mipLvl;

		for (uint32_t layer = 0; layer < _arrayLayers; layer++) {
			subRez.subresource.arrayLayer = layer;
			initSubresourceLayout(subRez);
			_subresources.push_back(subRez);
		}
	}
}

// Initializes the layout element of the specified image subresource.
void MVKImage::initSubresourceLayout(MVKImageSubresource& imgSubRez) {
	VkImageSubresource subresource = imgSubRez.subresource;
	uint32_t currMipLevel = subresource.mipLevel;
	uint32_t currArrayLayer = subresource.arrayLayer;

	VkDeviceSize bytesPerLayerCurrLevel = getBytesPerLayer(currMipLevel);

	// Accumulate the byte offset for the specified sub-resource.
	// This is the sum of the bytes consumed by all layers in all mipmap levels before the
	// desired level, plus the layers before the desired layer at the desired level.
	VkDeviceSize offset = 0;
	for (uint32_t mipLvl = 0; mipLvl < currMipLevel; mipLvl++) {
		offset += (getBytesPerLayer(mipLvl) * _extent.depth * _arrayLayers);
	}
	offset += (bytesPerLayerCurrLevel * currArrayLayer);

	VkSubresourceLayout& layout = imgSubRez.layout;
	layout.offset = offset;
	layout.size = bytesPerLayerCurrLevel;
	layout.rowPitch = getBytesPerRow(currMipLevel);
	layout.depthPitch = bytesPerLayerCurrLevel;
}

void MVKImage::initExternalMemory(VkExternalMemoryHandleTypeFlags handleTypes) {
	if (mvkIsOnlyAnyFlagEnabled(handleTypes, VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR)) {
		_externalMemoryHandleTypes = handleTypes;
		auto& xmProps = _device->getPhysicalDevice()->getExternalImageProperties(VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR);
		_requiresDedicatedMemoryAllocation = _requiresDedicatedMemoryAllocation || mvkIsAnyFlagEnabled(xmProps.externalMemoryFeatures, VK_EXTERNAL_MEMORY_FEATURE_DEDICATED_ONLY_BIT);
	} else {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImage(): Only external memory handle type VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_KHR is supported."));
	}
}

MVKImage::~MVKImage() {
	if (_deviceMemory) { _deviceMemory->removeImage(this); }
	releaseMTLTexture();
    releaseIOSurface();
}


#pragma mark -
#pragma mark MVKSwapchainImage

VkResult MVKSwapchainImage::bindDeviceMemory(MVKDeviceMemory*, VkDeviceSize) {
	return VK_ERROR_OUT_OF_DEVICE_MEMORY;
}


#pragma mark Metal

// Overridden to always retrieve the MTLTexture directly from the CAMetalDrawable.
id<MTLTexture> MVKSwapchainImage::getMTLTexture() { return [getCAMetalDrawable() texture]; }


#pragma mark Construction

MVKSwapchainImage::MVKSwapchainImage(MVKDevice* device,
									 const VkImageCreateInfo* pCreateInfo,
									 MVKSwapchain* swapchain,
									 uint32_t swapchainIndex) : MVKImage(device, pCreateInfo) {
	_swapchain = swapchain;
	_swapchainIndex = swapchainIndex;
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
void MVKPresentableSwapchainImage::makeAvailable() {
	lock_guard<mutex> lock(_availabilityLock);

	// Mark when this event happened, relative to that of other images
	_availability.acquisitionID = _swapchain->getNextAcquisitionID();

	// Mark this image as available if no semaphores or fences are waiting to be signaled.
	_availability.isAvailable = _availabilitySignalers.empty();

	MVKSwapchainSignaler signaler;
	if (_availability.isAvailable) {
		// If this image is available, signal the semaphore and fence that were associated
		// with the last time this image was acquired while available. This is a workaround for
		// when an app uses a single semaphore or fence for more than one swapchain image.
		// Becuase the semaphore or fence will be signaled by more than one image, it will
		// get out of sync, and the final use of the image would not be signaled as a result.
		signaler = _preSignaler;
	} else {
		// If this image is not yet available, extract and signal the first semaphore and fence.
		auto sigIter = _availabilitySignalers.begin();
		signaler = *sigIter;
		_availabilitySignalers.erase(sigIter);
	}

	// Signal the semaphore and fence, and let them know they are no longer being tracked.
	signal(signaler, nil);
	unmarkAsTracked(signaler);

//	MVKLogDebug("Signaling%s swapchain image %p semaphore %p from present, with %lu remaining semaphores.", (_availability.isAvailable ? " pre-signaled" : ""), this, signaler.first, _availabilitySignalers.size());
}

void MVKPresentableSwapchainImage::acquireAndSignalWhenAvailable(MVKSemaphore* semaphore, MVKFence* fence) {
	lock_guard<mutex> lock(_availabilityLock);

	// Now that this image is being acquired, release the existing drawable and its texture.
	// This is not done earlier so the texture is retained for any post-processing such as screen captures, etc.
	releaseMetalDrawable();

	auto signaler = make_pair(semaphore, fence);
	if (_availability.isAvailable) {
		_availability.isAvailable = false;

		// If signalling through a MTLEvent, use an ephemeral MTLCommandBuffer.
		// Another option would be to use MTLSharedEvent in MVKSemaphore, but that might
		// impose unacceptable performance costs to handle this particular case.
		@autoreleasepool {
			MVKSemaphore* mvkSem = signaler.first;
			id<MTLCommandBuffer> mtlCmdBuff = (mvkSem && mvkSem->isUsingCommandEncoding()
											   ? [_device->getAnyQueue()->getMTLCommandQueue() commandBufferWithUnretainedReferences]
											   : nil);
			signal(signaler, mtlCmdBuff);
			[mtlCmdBuff commit];
		}

		_preSignaler = signaler;
	} else {
		_availabilitySignalers.push_back(signaler);
	}
	markAsTracked(signaler);

//	MVKLogDebug("%s swapchain image %p semaphore %p in acquire with %lu other semaphores.", (_availability.isAvailable ? "Signaling" : "Tracking"), this, semaphore, _availabilitySignalers.size());
}

// If present, signal the semaphore for the first waiter for the given image.
void MVKPresentableSwapchainImage::signalPresentationSemaphore(id<MTLCommandBuffer> mtlCmdBuff) {
	lock_guard<mutex> lock(_availabilityLock);

	if ( !_availabilitySignalers.empty() ) {
		MVKSemaphore* mvkSem = _availabilitySignalers.front().first;
		if (mvkSem) { mvkSem->encodeSignal(mtlCmdBuff); }
	}
}

// Signal either or both of the semaphore and fence in the specified tracker pair.
void MVKPresentableSwapchainImage::signal(MVKSwapchainSignaler& signaler, id<MTLCommandBuffer> mtlCmdBuff) {
	if (signaler.first) { signaler.first->encodeSignal(mtlCmdBuff); }
	if (signaler.second) { signaler.second->signal(); }
}

// Tell the semaphore and fence that they are being tracked for future signaling.
void MVKPresentableSwapchainImage::markAsTracked(MVKSwapchainSignaler& signaler) {
	if (signaler.first) { signaler.first->retain(); }
	if (signaler.second) { signaler.second->retain(); }
}

// Tell the semaphore and fence that they are no longer being tracked for future signaling.
void MVKPresentableSwapchainImage::unmarkAsTracked(MVKSwapchainSignaler& signaler) {
	if (signaler.first) { signaler.first->release(); }
	if (signaler.second) { signaler.second->release(); }
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
void MVKPresentableSwapchainImage::presentCAMetalDrawable(id<MTLCommandBuffer> mtlCmdBuff, bool hasPresentTime, uint32_t presentID, uint64_t desiredPresentTime) {
	_swapchain->willPresentSurface(getMTLTexture(), mtlCmdBuff);

	NSString* scName = _swapchain->getDebugName();
	if (scName) { mvkPushDebugGroup(mtlCmdBuff, scName); }
	if (!hasPresentTime) {
		[mtlCmdBuff presentDrawable: getCAMetalDrawable()];
	}
	else {
		// Convert from nsecs to seconds
		CFTimeInterval presentTimeSeconds = ( double ) desiredPresentTime * 1.0e-9;
		[mtlCmdBuff presentDrawable: getCAMetalDrawable() atTime:(CFTimeInterval)presentTimeSeconds];
	}
	if (scName) { mvkPopDebugGroup(mtlCmdBuff); }

	signalPresentationSemaphore(mtlCmdBuff);

	retain();	// Ensure this image is not destroyed while awaiting MTLCommandBuffer completion
	[mtlCmdBuff addCompletedHandler: ^(id<MTLCommandBuffer> mcb) {
		makeAvailable();
		release();
	}];
	
	if (hasPresentTime) {
		[_mtlDrawable addPresentedHandler: ^(id<MTLDrawable> drawable) {
			// Record the presentation time
			CFTimeInterval presentedTimeSeconds = drawable.presentedTime;
			uint64_t presentedTimeNanoseconds = (uint64_t)(presentedTimeSeconds * 1.0e9);
			_swapchain->recordPresentTime(presentID, desiredPresentTime, presentedTimeNanoseconds);
		}];

	}
}

// Resets the MTLTexture and CAMetalDrawable underlying this image.
void MVKPresentableSwapchainImage::releaseMetalDrawable() {
	releaseMTLTexture();			// Release texture first so drawable will be last to release it
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
	_preSignaler = make_pair(nullptr, nullptr);
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
#pragma mark MVKImageView

void MVKImageView::propogateDebugName() { setLabelIfNotNil(_mtlTexture, _debugName); }

void MVKImageView::populateMTLRenderPassAttachmentDescriptor(MTLRenderPassAttachmentDescriptor* mtlAttDesc) {
    mtlAttDesc.texture = getMTLTexture();           // Use image view, necessary if image view format differs from image format
    mtlAttDesc.level = _useMTLTextureView ? 0 : _subresourceRange.baseMipLevel;
    if (mtlAttDesc.texture.textureType == MTLTextureType3D) {
        mtlAttDesc.slice = 0;
        mtlAttDesc.depthPlane = _useMTLTextureView ? 0 : _subresourceRange.baseArrayLayer;
    } else {
        mtlAttDesc.slice = _useMTLTextureView ? 0 : _subresourceRange.baseArrayLayer;
        mtlAttDesc.depthPlane = 0;
    }
}

void MVKImageView::populateMTLRenderPassAttachmentDescriptorResolve(MTLRenderPassAttachmentDescriptor* mtlAttDesc) {
    mtlAttDesc.resolveTexture = getMTLTexture();    // Use image view, necessary if image view format differs from image format
    mtlAttDesc.resolveLevel = _useMTLTextureView ? 0 : _subresourceRange.baseMipLevel;
    if (mtlAttDesc.resolveTexture.textureType == MTLTextureType3D) {
        mtlAttDesc.resolveSlice = 0;
        mtlAttDesc.resolveDepthPlane = _useMTLTextureView ? 0 : _subresourceRange.baseArrayLayer;
    } else {
        mtlAttDesc.resolveSlice = _useMTLTextureView ? 0 : _subresourceRange.baseArrayLayer;
        mtlAttDesc.resolveDepthPlane = 0;
    }
}


#pragma mark Metal

id<MTLTexture> MVKImageView::getMTLTexture() {
	// If we can use a Metal texture view, lazily create it, otherwise use the image texture directly.
	if (_useMTLTextureView) {
		if ( !_mtlTexture && _mtlPixelFormat ) {

			// Lock and check again in case another thread created the texture view
			lock_guard<mutex> lock(_lock);
			if (_mtlTexture) { return _mtlTexture; }

			_mtlTexture = newMTLTexture(); // retained

			propogateDebugName();
		}
		return _mtlTexture;
	} else {
		return _image->getMTLTexture();
	}
}

// Creates and returns a retained Metal texture as an
// overlay on the Metal texture of the underlying image.
id<MTLTexture> MVKImageView::newMTLTexture() {
    MTLTextureType mtlTextureType = _mtlTextureType;
    NSRange sliceRange = NSMakeRange(_subresourceRange.baseArrayLayer, _subresourceRange.layerCount);
    // Fake support for 2D views of 3D textures.
    if (_image->getImageType() == VK_IMAGE_TYPE_3D &&
        (mtlTextureType == MTLTextureType2D || mtlTextureType == MTLTextureType2DArray)) {
        mtlTextureType = MTLTextureType3D;
        sliceRange = NSMakeRange(0, 1);
    }
    if (_device->_pMetalFeatures->nativeTextureSwizzle && _packedSwizzle) {
        return [_image->getMTLTexture() newTextureViewWithPixelFormat: _mtlPixelFormat
                                                          textureType: mtlTextureType
                                                               levels: NSMakeRange(_subresourceRange.baseMipLevel, _subresourceRange.levelCount)
                                                               slices: sliceRange
                                                              swizzle: mvkMTLTextureSwizzleChannelsFromVkComponentMapping(mvkUnpackSwizzle(_packedSwizzle))];	// retained
    } else {
        return [_image->getMTLTexture() newTextureViewWithPixelFormat: _mtlPixelFormat
                                                          textureType: mtlTextureType
                                                               levels: NSMakeRange(_subresourceRange.baseMipLevel, _subresourceRange.levelCount)
                                                               slices: sliceRange];	// retained
    }
}


#pragma mark Construction

MVKImageView::MVKImageView(MVKDevice* device,
						   const VkImageViewCreateInfo* pCreateInfo,
						   const MVKConfiguration* pAltMVKConfig) : MVKVulkanAPIDeviceObject(device) {
	_image = (MVKImage*)pCreateInfo->image;
	_usage = _image->_usage;

	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_IMAGE_VIEW_USAGE_CREATE_INFO: {
				auto* pViewUsageInfo = (VkImageViewUsageCreateInfo*)next;
				if (!(pViewUsageInfo->usage & ~_usage)) { _usage = pViewUsageInfo->usage; }
				break;
			}
			default:
				break;
		}
	}

	validateImageViewConfig(pCreateInfo);

	// Remember the subresource range, and determine the actual number of mip levels and texture slices
    _subresourceRange = pCreateInfo->subresourceRange;
	if (_subresourceRange.levelCount == VK_REMAINING_MIP_LEVELS) {
		_subresourceRange.levelCount = _image->getMipLevelCount() - _subresourceRange.baseMipLevel;
	}
	if (_subresourceRange.layerCount == VK_REMAINING_ARRAY_LAYERS) {
		_subresourceRange.layerCount = _image->getLayerCount() - _subresourceRange.baseArrayLayer;
	}

	_mtlTexture = nil;
	bool useSwizzle;
	setConfigurationResult(validateSwizzledMTLPixelFormat(pCreateInfo, getPixelFormats(), this,
														  _device->_pMetalFeatures->nativeTextureSwizzle,
														  _device->_pMVKConfig->fullImageViewSwizzle,
														  _mtlPixelFormat, useSwizzle));
	_packedSwizzle = useSwizzle ? mvkPackSwizzle(pCreateInfo->components) : 0;
	_mtlTextureType = mvkMTLTextureTypeFromVkImageViewType(pCreateInfo->viewType,
														   _image->getSampleCount() != VK_SAMPLE_COUNT_1_BIT);
	initMTLTextureViewSupport();
}

// Validate whether the image view configuration can be supported
void MVKImageView::validateImageViewConfig(const VkImageViewCreateInfo* pCreateInfo) {

	// No image if we are just validating view config
	MVKImage* image = (MVKImage*)pCreateInfo->image;
	if ( !image ) { return; }

	VkImageType imgType = image->getImageType();
	VkImageViewType viewType = pCreateInfo->viewType;

	// VK_KHR_maintenance1 supports taking 2D image views of 3D slices. No dice in Metal.
	if ((viewType == VK_IMAGE_VIEW_TYPE_2D || viewType == VK_IMAGE_VIEW_TYPE_2D_ARRAY) && (imgType == VK_IMAGE_TYPE_3D)) {
		if (pCreateInfo->subresourceRange.layerCount != image->_extent.depth) {
			reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImageView(): Metal does not fully support views on a subset of a 3D texture.");
		}
		if ( !mvkIsAnyFlagEnabled(_usage, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) ) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImageView(): 2D views on 3D images can only be used as color attachments."));
		} else if (mvkIsOnlyAnyFlagEnabled(_usage, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)) {
			reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateImageView(): 2D views on 3D images can only be used as color attachments.");
		}
	}
}

VkResult MVKImageView::validateSwizzledMTLPixelFormat(const VkImageViewCreateInfo* pCreateInfo,
													  MVKPixelFormats* mvkPixFmts,
													  MVKVulkanAPIObject* apiObject,
													  bool hasNativeSwizzleSupport,
													  bool hasShaderSwizzleSupport,
													  MTLPixelFormat& mtlPixFmt,
													  bool& useSwizzle) {
	useSwizzle = false;
	mtlPixFmt = mvkPixFmts->getMTLPixelFormat(pCreateInfo->format);
	VkComponentMapping components = pCreateInfo->components;

	#define SWIZZLE_MATCHES(R, G, B, A)    mvkVkComponentMappingsMatch(components, {VK_COMPONENT_SWIZZLE_ ##R, VK_COMPONENT_SWIZZLE_ ##G, VK_COMPONENT_SWIZZLE_ ##B, VK_COMPONENT_SWIZZLE_ ##A} )
	#define VK_COMPONENT_SWIZZLE_ANY       VK_COMPONENT_SWIZZLE_MAX_ENUM

	// If we have an identity swizzle, we're all good.
	if (SWIZZLE_MATCHES(R, G, B, A)) {
		return VK_SUCCESS;
	}

	switch (mtlPixFmt) {
		case MTLPixelFormatR8Unorm:
			if (SWIZZLE_MATCHES(ZERO, ANY, ANY, R)) {
				mtlPixFmt = MTLPixelFormatA8Unorm;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatA8Unorm:
			if (SWIZZLE_MATCHES(A, ANY, ANY, ZERO)) {
				mtlPixFmt = MTLPixelFormatR8Unorm;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatRGBA8Unorm:
			if (SWIZZLE_MATCHES(B, G, R, A)) {
				mtlPixFmt = MTLPixelFormatBGRA8Unorm;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatRGBA8Unorm_sRGB:
			if (SWIZZLE_MATCHES(B, G, R, A)) {
				mtlPixFmt = MTLPixelFormatBGRA8Unorm_sRGB;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatBGRA8Unorm:
			if (SWIZZLE_MATCHES(B, G, R, A)) {
				mtlPixFmt = MTLPixelFormatRGBA8Unorm;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatBGRA8Unorm_sRGB:
			if (SWIZZLE_MATCHES(B, G, R, A)) {
				mtlPixFmt = MTLPixelFormatRGBA8Unorm_sRGB;
				return VK_SUCCESS;
			}
			break;

		case MTLPixelFormatDepth32Float_Stencil8:
			// If aspect mask looking only for stencil then change to stencil-only format even if shader swizzling is needed
			if (pCreateInfo->subresourceRange.aspectMask == VK_IMAGE_ASPECT_STENCIL_BIT) {
				mtlPixFmt = MTLPixelFormatX32_Stencil8;
				if (SWIZZLE_MATCHES(R, ANY, ANY, ANY)) {
					return VK_SUCCESS;
				}
			}
			break;

#if MVK_MACOS
		case MTLPixelFormatDepth24Unorm_Stencil8:
			// If aspect mask looking only for stencil then change to stencil-only format even if shader swizzling is needed
			if (pCreateInfo->subresourceRange.aspectMask == VK_IMAGE_ASPECT_STENCIL_BIT) {
				mtlPixFmt = MTLPixelFormatX24_Stencil8;
				if (SWIZZLE_MATCHES(R, ANY, ANY, ANY)) {
					return VK_SUCCESS;
				}
			}
			break;
#endif

		default:
			break;
	}

	// No format transformation swizzles were found, so we'll need to use either native or shader swizzling.
	useSwizzle = true;
	if (hasNativeSwizzleSupport || hasShaderSwizzleSupport ) {
		return VK_SUCCESS;
	}

	// Oh, oh. Neither native or shader swizzling is supported.
	return apiObject->reportError(VK_ERROR_FEATURE_NOT_PRESENT,
								  "The value of %s::components) (%s, %s, %s, %s), when applied to a VkImageView, requires full component swizzling to be enabled both at the"
								  " time when the VkImageView is created and at the time any pipeline that uses that VkImageView is compiled. Full component swizzling can"
								  " be enabled via the MVKConfiguration::fullImageViewSwizzle config parameter or MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE environment variable.",
								  pCreateInfo->image ? "vkCreateImageView(VkImageViewCreateInfo" : "vkGetPhysicalDeviceImageFormatProperties2KHR(VkPhysicalDeviceImageViewSupportEXTX",
								  mvkVkComponentSwizzleName(components.r), mvkVkComponentSwizzleName(components.g),
								  mvkVkComponentSwizzleName(components.b), mvkVkComponentSwizzleName(components.a));
}

// Determine whether this image view should use a Metal texture view,
// and set the _useMTLTextureView variable appropriately.
void MVKImageView::initMTLTextureViewSupport() {

	// If no image we're just validating image iview config
	if ( !_image ) {
		_useMTLTextureView = false;
		return;
	}

	_useMTLTextureView = _image->_canSupportMTLTextureView;

	bool is3D = _image->_mtlTextureType == MTLTextureType3D;
	// If the view is identical to underlying image, don't bother using a Metal view
	if (_mtlPixelFormat == _image->_mtlPixelFormat &&
		(_mtlTextureType == _image->_mtlTextureType ||
		 ((_mtlTextureType == MTLTextureType2D || _mtlTextureType == MTLTextureType2DArray) && is3D)) &&
		_subresourceRange.levelCount == _image->_mipLevels &&
		(is3D || _subresourceRange.layerCount == _image->_arrayLayers) &&
		(!_device->_pMetalFeatures->nativeTextureSwizzle || !_packedSwizzle)) {
		_useMTLTextureView = false;
	}
}

MVKImageView::~MVKImageView() {
	[_mtlTexture release];
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

// Returns an Metal sampler descriptor constructed from the properties of this image.
// It is the caller's responsibility to release the returned descriptor object.
MTLSamplerDescriptor* MVKSampler::newMTLSamplerDescriptor(const VkSamplerCreateInfo* pCreateInfo) {

	MTLSamplerDescriptor* mtlSampDesc = [MTLSamplerDescriptor new];		// retained
	mtlSampDesc.sAddressMode = mvkMTLSamplerAddressModeFromVkSamplerAddressMode(pCreateInfo->addressModeU);
	mtlSampDesc.tAddressMode = mvkMTLSamplerAddressModeFromVkSamplerAddressMode(pCreateInfo->addressModeV);
    mtlSampDesc.rAddressMode = mvkMTLSamplerAddressModeFromVkSamplerAddressMode(pCreateInfo->addressModeW);
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

	// If compareEnable is true, but dynamic samplers with depth compare are not available
	// on this device, this sampler must only be used as an immutable sampler, and will
	// be automatically hardcoded into the shader MSL. An error will be triggered if this
	// sampler is used to update or push a descriptor.
	if (pCreateInfo->compareEnable && !_requiresConstExprSampler) {
		mtlSampDesc.compareFunctionMVK = mvkMTLCompareFunctionFromVkCompareOp(pCreateInfo->compareOp);
	}

#if MVK_MACOS
	mtlSampDesc.borderColorMVK = mvkMTLSamplerBorderColorFromVkBorderColor(pCreateInfo->borderColor);
	if (_device->getPhysicalDevice()->getMetalFeatures()->samplerClampToBorder) {
		if (pCreateInfo->addressModeU == VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER) {
			mtlSampDesc.sAddressMode = MTLSamplerAddressModeClampToBorderColor;
		}
		if (pCreateInfo->addressModeV == VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER) {
			mtlSampDesc.tAddressMode = MTLSamplerAddressModeClampToBorderColor;
		}
		if (pCreateInfo->addressModeW == VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER) {
			mtlSampDesc.rAddressMode = MTLSamplerAddressModeClampToBorderColor;
		}
	}
#endif
	return mtlSampDesc;
}

MVKSampler::MVKSampler(MVKDevice* device, const VkSamplerCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	_requiresConstExprSampler = pCreateInfo->compareEnable && !_device->_pMetalFeatures->depthSampleCompare;

	MTLSamplerDescriptor* mtlSampDesc = newMTLSamplerDescriptor(pCreateInfo);	// temp retain
    _mtlSamplerState = [getMTLDevice() newSamplerStateWithDescriptor: mtlSampDesc];
	[mtlSampDesc release];														// temp release

	initConstExprSampler(pCreateInfo);
}

static MSLSamplerFilter getSpvMinMagFilterFromVkFilter(VkFilter vkFilter) {
	switch (vkFilter) {
		case VK_FILTER_LINEAR:	return MSL_SAMPLER_FILTER_LINEAR;

		case VK_FILTER_NEAREST:
		default:
			return MSL_SAMPLER_FILTER_NEAREST;
	}
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
\
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
}

MVKSampler::~MVKSampler() {
	[_mtlSamplerState release];
}
