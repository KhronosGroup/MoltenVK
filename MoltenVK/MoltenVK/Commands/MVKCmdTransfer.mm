/*
 * MVKCmdTransfer.mm
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

#include "MVKCmdTransfer.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKCommandEncodingPool.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKFramebuffer.h"
#include "MVKRenderPass.h"
#include "MTLRenderPassDescriptor+MoltenVK.h"
#include "mvk_datatypes.hpp"
#include <algorithm>
#include <sys/mman.h>


#pragma mark -
#pragma mark Support functions

// Clamps the size so that the sum of the origin and size do not exceed the maximum size.
static inline MTLSize mvkClampMTLSize(MTLSize size, MTLOrigin origin, MTLSize maxSize) {
	MTLSize clamped;
	clamped.width = std::min(size.width, maxSize.width - origin.x);
	clamped.height = std::min(size.height, maxSize.height - origin.y);
	clamped.depth = std::min(size.depth, maxSize.depth - origin.z);
	return clamped;
}


#pragma mark -
#pragma mark MVKCmdCopyImage

template <size_t N>
VkResult MVKCmdCopyImage<N>::setContent(MVKCommandBuffer* cmdBuff,
										VkImage srcImage,
										VkImageLayout srcImageLayout,
										VkImage dstImage,
										VkImageLayout dstImageLayout,
										uint32_t regionCount,
										const VkImageCopy* pRegions) {
	_srcImage = (MVKImage*)srcImage;
	_srcLayout = srcImageLayout;

	_dstImage = (MVKImage*)dstImage;
	_dstLayout = dstImageLayout;

	_vkImageCopies.clear();		// Clear for reuse
    for (uint32_t regionIdx = 0; regionIdx < regionCount; regionIdx++) {
        auto& vkIR = pRegions[regionIdx];
        VkImageCopy2 vkIR2 = {
            VK_STRUCTURE_TYPE_IMAGE_COPY_2, nullptr,
            vkIR.srcSubresource, vkIR.srcOffset,
            vkIR.dstSubresource, vkIR.dstOffset,
            vkIR.extent
        };
        
        if (auto validation = validate(cmdBuff, &vkIR2); validation != VK_SUCCESS)
            return validation;
        
        _vkImageCopies.emplace_back(std::move(vkIR2));
	}
    
	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdCopyImage<N>::setContent(MVKCommandBuffer* cmdBuff,
                                        const VkCopyImageInfo2* pCopyImageInfo) {
    _srcImage = (MVKImage*)pCopyImageInfo->srcImage;
    _srcLayout = pCopyImageInfo->srcImageLayout;

    _dstImage = (MVKImage*)pCopyImageInfo->dstImage;
    _dstLayout = pCopyImageInfo->dstImageLayout;

    _vkImageCopies.clear();        // Clear for reuse
    _vkImageCopies.reserve(pCopyImageInfo->regionCount);
    for (uint32_t regionIdx = 0; regionIdx < pCopyImageInfo->regionCount; regionIdx++) {
        auto& vkIR = pCopyImageInfo->pRegions[regionIdx];
        
        if (auto validation = validate(cmdBuff, &vkIR); validation != VK_SUCCESS)
            return validation;
        
        _vkImageCopies.push_back(vkIR);
    }
    
    return VK_SUCCESS;
}

static inline MTLPixelFormat getDepthStencilAspectFormat(const MTLPixelFormat format, const VkImageAspectFlags aspectMask) {
    if (format == MTLPixelFormatDepth32Float_Stencil8) {
        if (aspectMask & VK_IMAGE_ASPECT_DEPTH_BIT) return MTLPixelFormatDepth32Float;
        if (aspectMask & VK_IMAGE_ASPECT_STENCIL_BIT) return MTLPixelFormatStencil8;
    }
#if MVK_MACOS
    if (format == MTLPixelFormatDepth24Unorm_Stencil8 && (aspectMask & VK_IMAGE_ASPECT_STENCIL_BIT))
        return MTLPixelFormatStencil8;
#endif
    return format;
}

template <size_t N>
inline VkResult MVKCmdCopyImage<N>::validate(MVKCommandBuffer* cmdBuff, const VkImageCopy2* region) {
    uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region->srcSubresource.aspectMask);
    uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region->dstSubresource.aspectMask);

    // If the format is combined depth-stencil, use the format based on the aspect for the following checks.
    auto srcFormat = getDepthStencilAspectFormat(_srcImage->getMTLPixelFormat(srcPlaneIndex), region->srcSubresource.aspectMask);
    auto dstFormat = getDepthStencilAspectFormat(_dstImage->getMTLPixelFormat(dstPlaneIndex), region->dstSubresource.aspectMask);

    // Validate
    MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();
    if ((_dstImage->getSampleCount() != _srcImage->getSampleCount()) ||
        (pixFmts->getBytesPerBlock(srcFormat) != pixFmts->getBytesPerBlock(dstFormat))) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdCopyImage(): Cannot copy between incompatible formats, such as formats of different pixel sizes, or between images with different sample counts.");
    }
    return VK_SUCCESS;
}


template <size_t N>
void MVKCmdCopyImage<N>::encode(MVKCommandEncoder* cmdEncoder, MVKCommandUse commandUse) {
    MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
    uint32_t copyCnt = (uint32_t)_vkImageCopies.size();
    VkBufferImageCopy vkSrcCopies[copyCnt];
    VkBufferImageCopy vkDstCopies[copyCnt];
    size_t tmpBuffSize = 0;

    for (uint32_t copyIdx = 0; copyIdx < copyCnt; copyIdx++) {
        auto& vkIC = _vkImageCopies[copyIdx];
        
        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIC.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIC.dstSubresource.aspectMask);
        
        MTLPixelFormat srcMTLPixFmt = _srcImage->getMTLPixelFormat(srcPlaneIndex);
        bool isSrcCompressed = _srcImage->getIsCompressed();
        bool isSrcCombinedDepthStencilAspect = getDepthStencilAspectFormat(srcMTLPixFmt, vkIC.srcSubresource.aspectMask) != srcMTLPixFmt;
        bool canReinterpretSrc = _srcImage->hasPixelFormatView(srcPlaneIndex);

        MTLPixelFormat dstMTLPixFmt = _dstImage->getMTLPixelFormat(dstPlaneIndex);
        bool isDstCompressed = _dstImage->getIsCompressed();
        bool isDstCombinedDepthStencilAspect = getDepthStencilAspectFormat(dstMTLPixFmt, vkIC.dstSubresource.aspectMask) != dstMTLPixFmt;
        bool canReinterpretDst = _dstImage->hasPixelFormatView(dstPlaneIndex);

        bool isEitherCompressed = isSrcCompressed || isDstCompressed;
        bool isOneCombinedDepthStencilAspect = isSrcCombinedDepthStencilAspect != isDstCombinedDepthStencilAspect;
        bool canReinterpret = canReinterpretSrc || canReinterpretDst;

        // If source and destination can't be reinterpreted to matching formats use a temporary intermediary buffer
        bool useTempBuffer = (srcMTLPixFmt != dstMTLPixFmt) && (isEitherCompressed || isOneCombinedDepthStencilAspect || !canReinterpret);

        if (useTempBuffer) {
            // Add copy from source image to temp buffer.
            auto& srcCpy = vkSrcCopies[copyIdx];
            srcCpy.bufferOffset = tmpBuffSize;
            srcCpy.bufferRowLength = 0;
            srcCpy.bufferImageHeight = 0;
            srcCpy.imageSubresource = vkIC.srcSubresource;
            srcCpy.imageOffset = vkIC.srcOffset;
            srcCpy.imageExtent = vkIC.extent;

            // Add copy from temp buffer to destination image.
            // Extent is provided in source texels. If the source is compressed but the
            // destination is not, each destination pixel will consume an entire source block,
            // so we must downscale the destination extent by the size of the source block.
            // Likewise if the destination is compressed and source is not, each source pixel
            // will map to a block of pixels in the destination texture, and we need to
            // adjust destination's extent accordingly.
            VkExtent3D dstExtent = vkIC.extent;
            if (isSrcCompressed && !isDstCompressed) {
                VkExtent2D srcBlockExtent = pixFmts->getBlockTexelSize(srcMTLPixFmt);
                dstExtent.width /= srcBlockExtent.width;
                dstExtent.height /= srcBlockExtent.height;
            } else if (!isSrcCompressed && isDstCompressed) {
                VkExtent2D dstBlockExtent = pixFmts->getBlockTexelSize(dstMTLPixFmt);
                dstExtent.width *= dstBlockExtent.width;
                dstExtent.height *= dstBlockExtent.height;
            }
            auto& dstCpy = vkDstCopies[copyIdx];
            dstCpy.bufferOffset = tmpBuffSize;
            dstCpy.bufferRowLength = 0;
            dstCpy.bufferImageHeight = 0;
            dstCpy.imageSubresource = vkIC.dstSubresource;
            dstCpy.imageOffset = vkIC.dstOffset;
            dstCpy.imageExtent = dstExtent;

            size_t bytesPerRow = pixFmts->getBytesPerRow(srcMTLPixFmt, vkIC.extent.width);
            size_t bytesPerRegion = pixFmts->getBytesPerLayer(srcMTLPixFmt, bytesPerRow, vkIC.extent.height);
            tmpBuffSize += bytesPerRegion * vkIC.extent.depth;
        } else {
            // Map the source pixel format to the dest pixel format through a texture view on the reinterpretable texture.
            // If the source and dest pixel formats are the same, this will simply degenerate to the texture itself.
            MTLPixelFormat fmt = (canReinterpretSrc ? _dstImage : _srcImage)->getMTLPixelFormat(canReinterpretSrc ? dstPlaneIndex : srcPlaneIndex);
            id<MTLTexture> srcMTLTex = _srcImage->getMTLTexture(srcPlaneIndex, fmt);
            id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture(dstPlaneIndex, fmt);
            if ( !srcMTLTex || !dstMTLTex ) { return; }

            id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(commandUse);

            // If copies can be performed using direct texture-texture copying, do so
            uint32_t srcLevel = vkIC.srcSubresource.mipLevel;
            uint32_t srcBaseLayer = vkIC.srcSubresource.baseArrayLayer;
            uint32_t srcLayerCount = vkIC.srcSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
                _srcImage->getLayerCount() - srcBaseLayer :
                vkIC.srcSubresource.layerCount;
            VkExtent3D srcExtent = _srcImage->getExtent3D(srcPlaneIndex, srcLevel);
            uint32_t dstLevel = vkIC.dstSubresource.mipLevel;
            uint32_t dstBaseLayer = vkIC.dstSubresource.baseArrayLayer;
            VkExtent3D dstExtent = _dstImage->getExtent3D(dstPlaneIndex, dstLevel);
            // If the extent completely covers both images, I can copy all layers at once.
            // This will obviously not apply to copies between a 3D and 2D image.
            if (mvkVkExtent3DsAreEqual(srcExtent, vkIC.extent) && mvkVkExtent3DsAreEqual(dstExtent, vkIC.extent) &&
                [mtlBlitEnc respondsToSelector: @selector(copyFromTexture:sourceSlice:sourceLevel:toTexture:destinationSlice:destinationLevel:sliceCount:levelCount:)]) {
                assert((_srcImage->getMTLTextureType() == MTLTextureType3D) == (_dstImage->getMTLTextureType() == MTLTextureType3D));
                [mtlBlitEnc copyFromTexture: srcMTLTex
                                sourceSlice: srcBaseLayer
                                sourceLevel: srcLevel
                                  toTexture: dstMTLTex
                           destinationSlice: dstBaseLayer
                           destinationLevel: dstLevel
                                 sliceCount: srcLayerCount
                                 levelCount: 1];
            } else {
                MTLOrigin srcOrigin = mvkMTLOriginFromVkOffset3D(vkIC.srcOffset);
                MTLSize srcSize;
                uint32_t layCnt;
                if ((_srcImage->getMTLTextureType() == MTLTextureType3D) != (_dstImage->getMTLTextureType() == MTLTextureType3D)) {
                    // In the case, the number of layers to copy is in extent.depth. Use that value,
                    // then clamp the depth so we don't try to copy more than Metal will allow.
                    layCnt = vkIC.extent.depth;
                    srcSize = mvkClampMTLSize(mvkMTLSizeFromVkExtent3D(vkIC.extent),
                                              srcOrigin,
                                              mvkMTLSizeFromVkExtent3D(srcExtent));
                    srcSize.depth = 1;
                } else {
                    layCnt = srcLayerCount;
                    srcSize = mvkClampMTLSize(mvkMTLSizeFromVkExtent3D(vkIC.extent),
                                              srcOrigin,
                                              mvkMTLSizeFromVkExtent3D(srcExtent));
                }
                MTLOrigin dstOrigin = mvkMTLOriginFromVkOffset3D(vkIC.dstOffset);
                
                for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
                    // We can copy between a 3D and a 2D image easily. Just copy between
                    // one slice of the 2D image and one plane of the 3D image at a time.
                    if ((_srcImage->getMTLTextureType() == MTLTextureType3D) == (_dstImage->getMTLTextureType() == MTLTextureType3D)) {
                        [mtlBlitEnc copyFromTexture: srcMTLTex
                                        sourceSlice: srcBaseLayer + layIdx
                                        sourceLevel: srcLevel
                                       sourceOrigin: srcOrigin
                                         sourceSize: srcSize
                                          toTexture: dstMTLTex
                                   destinationSlice: dstBaseLayer + layIdx
                                   destinationLevel: dstLevel
                                  destinationOrigin: dstOrigin];
                    } else if (_srcImage->getMTLTextureType() == MTLTextureType3D) {
                        [mtlBlitEnc copyFromTexture: srcMTLTex
                                        sourceSlice: srcBaseLayer
                                        sourceLevel: srcLevel
                                       sourceOrigin: MTLOriginMake(srcOrigin.x, srcOrigin.y, srcOrigin.z + layIdx)
                                         sourceSize: srcSize
                                          toTexture: dstMTLTex
                                   destinationSlice: dstBaseLayer + layIdx
                                   destinationLevel: dstLevel
                                  destinationOrigin: dstOrigin];
                    } else {
                        assert(_dstImage->getMTLTextureType() == MTLTextureType3D);
                        [mtlBlitEnc copyFromTexture: srcMTLTex
                                        sourceSlice: srcBaseLayer + layIdx
                                        sourceLevel: srcLevel
                                       sourceOrigin: srcOrigin
                                         sourceSize: srcSize
                                          toTexture: dstMTLTex
                                   destinationSlice: dstBaseLayer
                                   destinationLevel: dstLevel
                                  destinationOrigin: MTLOriginMake(dstOrigin.x, dstOrigin.y, dstOrigin.z + layIdx)];
                    }
                }
            }
        }
    }

    if (tmpBuffSize > 0) {
        MVKBufferDescriptorData tempBuffData;
        tempBuffData.size = tmpBuffSize;
        tempBuffData.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
        VkBuffer tempBuff = (VkBuffer)cmdEncoder->getCommandEncodingPool()->getTransferMVKBuffer(tempBuffData);

        MVKCmdBufferImageCopy<N> cpyCmd;

        // Copy from source image to buffer
        // Create and execute a temporary buffer image command.
        // To be threadsafe...do NOT acquire and return the command from the pool.
        cpyCmd.setContent(cmdEncoder->_cmdBuffer, tempBuff, (VkImage)_srcImage, _srcLayout, copyCnt, vkSrcCopies, false);
        cpyCmd.encode(cmdEncoder);

        // Copy from buffer to destination image
        // Create and execute a temporary buffer image command.
        // To be threadsafe...do NOT acquire and return the command from the pool.
        cpyCmd.setContent(cmdEncoder->_cmdBuffer, tempBuff, (VkImage)_dstImage, _dstLayout, copyCnt, vkDstCopies, true);
        cpyCmd.encode(cmdEncoder);
    }
}

template class MVKCmdCopyImage<1>;
template class MVKCmdCopyImage<4>;


#pragma mark -
#pragma mark MVKCmdBlitImage

template <size_t N>
VkResult MVKCmdBlitImage<N>::setContent(MVKCommandBuffer* cmdBuff,
										VkImage srcImage,
										VkImageLayout srcImageLayout,
										VkImage dstImage,
										VkImageLayout dstImageLayout,
										uint32_t regionCount,
										const VkImageBlit* pRegions,
										VkFilter filter) {

	_srcImage = (MVKImage*)srcImage;
	_srcLayout = srcImageLayout;
	_dstImage = (MVKImage*)dstImage;
	_dstLayout = dstImageLayout;

	_filter = filter;

	bool isDestUnwritableLinear = MVK_MACOS && !cmdBuff->getMetalFeatures().renderLinearTextures && _dstImage->getIsLinear();

	_vkImageBlits.clear();		// Clear for reuse
	for (uint32_t rIdx = 0; rIdx < regionCount; rIdx++) {
		auto& vkIB = pRegions[rIdx];
        VkImageBlit2 vkIB2 = {
            VK_STRUCTURE_TYPE_IMAGE_BLIT_2, nullptr,
            vkIB.srcSubresource, vkIB.srcOffsets[0], vkIB.srcOffsets[1],
            vkIB.dstSubresource, vkIB.dstOffsets[0], vkIB.dstOffsets[1],
        };
        
        if (auto validation = validate(cmdBuff, &vkIB2, isDestUnwritableLinear); validation != VK_SUCCESS)
            return validation;
        
		_vkImageBlits.push_back(vkIB2);
	}

	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdBlitImage<N>::setContent(MVKCommandBuffer* cmdBuff,
                                        const VkBlitImageInfo2* pBlitImageInfo) {

    _srcImage = (MVKImage*)pBlitImageInfo->srcImage;
    _srcLayout = pBlitImageInfo->srcImageLayout;
    _dstImage = (MVKImage*)pBlitImageInfo->dstImage;
    _dstLayout = pBlitImageInfo->dstImageLayout;

    _filter = pBlitImageInfo->filter;

    bool isDestUnwritableLinear = MVK_MACOS && !cmdBuff->getMetalFeatures().renderLinearTextures && _dstImage->getIsLinear();

    _vkImageBlits.clear();        // Clear for reuse
    _vkImageBlits.reserve(pBlitImageInfo->regionCount);
    for (uint32_t rIdx = 0; rIdx < pBlitImageInfo->regionCount; rIdx++) {
        auto& vkIB = pBlitImageInfo->pRegions[rIdx];
        
        if (auto validation = validate(cmdBuff, &vkIB, isDestUnwritableLinear); validation != VK_SUCCESS)
            return validation;
        
        _vkImageBlits.emplace_back(vkIB);
    }

    return VK_SUCCESS;
}

template <size_t N>
inline VkResult MVKCmdBlitImage<N>::validate(MVKCommandBuffer *cmdBuff, const VkImageBlit2 *region, bool isDestUnwritableLinear) {
    // Validate - macOS linear images cannot be a scaling or inversion destination
    if (isDestUnwritableLinear && !(canCopyFormats(*region) && canCopy(*region)) ) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdBlitImage(): Scaling or inverting to a linear destination image is not supported.");
    }
    return VK_SUCCESS;
}

template <size_t N>
bool MVKCmdBlitImage<N>::canCopyFormats(const VkImageBlit2& region) {
    uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.srcSubresource.aspectMask);
    uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.dstSubresource.aspectMask);
	return ((_srcImage->getMTLPixelFormat(srcPlaneIndex) == _dstImage->getMTLPixelFormat(dstPlaneIndex)) &&
			!_srcImage->needsSwizzle() &&
			(_dstImage->getSampleCount() == _srcImage->getSampleCount()));
}

// The source and destination sizes must be equal and not be negative in any direction
template <size_t N>
bool MVKCmdBlitImage<N>::canCopy(const VkImageBlit2& region) {
	VkOffset3D srcSize = mvkVkOffset3DDifference(region.srcOffsets[1], region.srcOffsets[0]);
	VkOffset3D dstSize = mvkVkOffset3DDifference(region.dstOffsets[1], region.dstOffsets[0]);
	return (mvkVkOffset3DsAreEqual(srcSize, dstSize) &&
			(srcSize.x >= 0) && (srcSize.y >= 0) && (srcSize.z >= 0));
}

template <size_t N>
void MVKCmdBlitImage<N>::populateVertices(MVKVertexPosTex* vertices, const VkImageBlit2& region) {
    const VkOffset3D& so0 = region.srcOffsets[0];
    const VkOffset3D& so1 = region.srcOffsets[1];
    const VkOffset3D& do0 = region.dstOffsets[0];
    const VkOffset3D& do1 = region.dstOffsets[1];

    // Get the extents of the source and destination textures.
    uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.srcSubresource.aspectMask);
    uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.dstSubresource.aspectMask);
    VkExtent3D srcExtent = _srcImage->getExtent3D(srcPlaneIndex, region.srcSubresource.mipLevel);
    VkExtent3D dstExtent = _dstImage->getExtent3D(dstPlaneIndex, region.dstSubresource.mipLevel);

    // Determine the bottom-left and top-right corners of the source and destination
    // texture regions, each as a fraction of the corresponding texture size.
    CGPoint srcBL = CGPointMake((CGFloat)(so0.x) / (CGFloat)srcExtent.width,
                                (CGFloat)(srcExtent.height - so1.y) / (CGFloat)srcExtent.height);
    CGPoint srcTR = CGPointMake((CGFloat)(so1.x) / (CGFloat)srcExtent.width,
                                (CGFloat)(srcExtent.height - so0.y) / (CGFloat)srcExtent.height);
    CGPoint dstBL = CGPointMake((CGFloat)(do0.x) / (CGFloat)dstExtent.width,
                                (CGFloat)(dstExtent.height - do1.y) / (CGFloat)dstExtent.height);
    CGPoint dstTR = CGPointMake((CGFloat)(do1.x) / (CGFloat)dstExtent.width,
                                (CGFloat)(dstExtent.height - do0.y) / (CGFloat)dstExtent.height);

    // The destination region is used for vertex positions,
    // which are bounded by (-1.0 < p < 1.0) in clip-space.
    // Map texture coordinates (0.0 < p < 1.0) to vertex coordinates (-1.0 < p < 1.0).
    dstBL = CGPointMake((dstBL.x * 2.0) - 1.0, (dstBL.y * 2.0) - 1.0);
    dstTR = CGPointMake((dstTR.x * 2.0) - 1.0, (dstTR.y * 2.0) - 1.0);

    MVKVertexPosTex* pVtx;

    // Bottom left vertex
    pVtx = &vertices[0];
    pVtx->position.x = dstBL.x;
    pVtx->position.y = dstBL.y;
    pVtx->texCoord.x = srcBL.x;
    pVtx->texCoord.y = (1.0 - srcBL.y);

    // Bottom right vertex
    pVtx = &vertices[1];
    pVtx->position.x = dstTR.x;
    pVtx->position.y = dstBL.y;
    pVtx->texCoord.x = srcTR.x;
    pVtx->texCoord.y = (1.0 - srcBL.y);

    // Top left vertex
    pVtx = &vertices[2];
    pVtx->position.x = dstBL.x;
    pVtx->position.y = dstTR.y;
    pVtx->texCoord.x = srcBL.x;
    pVtx->texCoord.y = (1.0 - srcTR.y);

    // Top right vertex
    pVtx = &vertices[3];
    pVtx->position.x = dstTR.x;
    pVtx->position.y = dstTR.y;
    pVtx->texCoord.x = srcTR.x;
    pVtx->texCoord.y = (1.0 - srcTR.y);
}

template <size_t N>
void MVKCmdBlitImage<N>::encode(MVKCommandEncoder* cmdEncoder, MVKCommandUse commandUse) {

	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	size_t vkIBCnt = _vkImageBlits.size();
	VkImageCopy vkImageCopies[vkIBCnt];
	MVKImageBlitRender mvkBlitRenders[vkIBCnt];
	uint32_t copyCnt = 0;
	uint32_t blitCnt = 0;

	// Separate BLITs into those that are really just simple texture region copies,
	// and those that require rendering
	for (auto& vkIB : _vkImageBlits) {
		if (canCopyFormats(vkIB) && canCopy(vkIB)) {

			const VkOffset3D& so0 = vkIB.srcOffsets[0];
			const VkOffset3D& so1 = vkIB.srcOffsets[1];

			auto& vkIC = vkImageCopies[copyCnt++];
			vkIC.srcSubresource = vkIB.srcSubresource;
			vkIC.srcOffset = vkIB.srcOffsets[0];
			vkIC.dstSubresource = vkIB.dstSubresource;
			vkIC.dstOffset = vkIB.dstOffsets[0];
			vkIC.extent.width = so1.x - so0.x;
			vkIC.extent.height = so1.y - so0.y;
			vkIC.extent.depth = so1.z - so0.z;

		} else {
			auto& mvkIBR = mvkBlitRenders[blitCnt++];
			mvkIBR.region = vkIB;
			populateVertices(mvkIBR.vertices, vkIB);
		}
	}

	// Perform those BLITs that can be covered by simple texture copying.
	if (copyCnt) {
		MVKCmdCopyImage<N> copyCmd;
		copyCmd.setContent(cmdEncoder->_cmdBuffer,
						   (VkImage)_srcImage, _srcLayout,
						   (VkImage)_dstImage, _dstLayout,
						   copyCnt, vkImageCopies);
		copyCmd.encode(cmdEncoder, kMVKCommandUseBlitImage);
	}

	// Perform those BLITs that require rendering to destination texture.
    for (uint32_t blitIdx = 0; blitIdx < blitCnt; blitIdx++) {
        auto& mvkIBR = mvkBlitRenders[blitIdx];

        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(mvkIBR.region.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(mvkIBR.region.dstSubresource.aspectMask);

        id<MTLTexture> srcMTLTex = _srcImage->getMTLTexture(srcPlaneIndex);
        id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture(dstPlaneIndex);
        if (blitCnt && srcMTLTex && dstMTLTex) {
			if (mtlFeats.nativeTextureSwizzle &&
				_srcImage->needsSwizzle()) {
				// Use a view that has a swizzle on it.
				srcMTLTex = [srcMTLTex newTextureViewWithPixelFormat:srcMTLTex.pixelFormat
														 textureType:srcMTLTex.textureType
															  levels:NSMakeRange(0, srcMTLTex.mipmapLevelCount)
															  slices:NSMakeRange(0, srcMTLTex.arrayLength)
															 swizzle:_srcImage->getPixelFormats()->getMTLTextureSwizzleChannels(_srcImage->getVkFormat())];
				[cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer>) { [srcMTLTex release]; }];
			}
            cmdEncoder->endCurrentMetalEncoding();

            MTLRenderPassDescriptor* mtlRPD = [MTLRenderPassDescriptor renderPassDescriptor];
            MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = mtlRPD.colorAttachments[0];
            MTLRenderPassDepthAttachmentDescriptor* mtlDepthAttDesc = mtlRPD.depthAttachment;
            MTLRenderPassStencilAttachmentDescriptor* mtlStencilAttDesc = mtlRPD.stencilAttachment;
            if (mvkIsAnyFlagEnabled(mvkIBR.region.dstSubresource.aspectMask, (VK_IMAGE_ASPECT_DEPTH_BIT))) {
                mtlDepthAttDesc.loadAction = MTLLoadActionLoad;
                mtlDepthAttDesc.storeAction = MTLStoreActionStore;
                mtlDepthAttDesc.texture = dstMTLTex;
            } else {
                mtlDepthAttDesc.loadAction = MTLLoadActionDontCare;
                mtlDepthAttDesc.storeAction = MTLStoreActionDontCare;
                mtlDepthAttDesc.texture = nil;
            }
            if (mvkIsAnyFlagEnabled(mvkIBR.region.dstSubresource.aspectMask, (VK_IMAGE_ASPECT_STENCIL_BIT))) {
                mtlStencilAttDesc.loadAction = MTLLoadActionLoad;
                mtlStencilAttDesc.storeAction = MTLStoreActionStore;
                mtlStencilAttDesc.texture = dstMTLTex;
            } else {
                mtlStencilAttDesc.loadAction = MTLLoadActionDontCare;
                mtlStencilAttDesc.storeAction = MTLStoreActionDontCare;
                mtlStencilAttDesc.texture = nil;
            }
            if (!mvkIsAnyFlagEnabled(mvkIBR.region.dstSubresource.aspectMask, (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT))) {
                mtlColorAttDesc.loadAction = MTLLoadActionLoad;
                mtlColorAttDesc.storeAction = MTLStoreActionStore;
                mtlColorAttDesc.texture = dstMTLTex;
            }

            MVKRPSKeyBlitImg blitKey;
            blitKey.srcMTLPixelFormat = _srcImage->getMTLPixelFormat(srcPlaneIndex);
            blitKey.srcMTLTextureType = _srcImage->getMTLTextureType();
            if (blitKey.srcMTLTextureType == MTLTextureTypeCube || blitKey.srcMTLTextureType == MTLTextureTypeCubeArray) {
                // In this case, I'll use a temp 2D array view. That way, I don't have to
                // deal with mapping the blit coordinates to a cube direction vector.
                blitKey.srcMTLTextureType = MTLTextureType2DArray;
                srcMTLTex = [srcMTLTex newTextureViewWithPixelFormat: blitKey.getSrcMTLPixelFormat()
                                                         textureType: MTLTextureType2DArray
                                                              levels: NSMakeRange(0, srcMTLTex.mipmapLevelCount)
                                                              slices: NSMakeRange(0, srcMTLTex.arrayLength)];
                [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer>) { [srcMTLTex release]; }];
            }
            blitKey.dstMTLPixelFormat = _dstImage->getMTLPixelFormat(dstPlaneIndex);
            blitKey.srcFilter = mvkMTLSamplerMinMagFilterFromVkFilter(_filter);
            blitKey.srcAspect = mvkIBR.region.srcSubresource.aspectMask & (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT);
            blitKey.dstSampleCount = mvkSampleCountFromVkSampleCountFlagBits(_dstImage->getSampleCount());
			if (!mtlFeats.nativeTextureSwizzle &&
				_srcImage->needsSwizzle()) {
				VkComponentMapping vkMapping = _srcImage->getPixelFormats()->getVkComponentMapping(_srcImage->getVkFormat());
				blitKey.srcSwizzleR = vkMapping.r;
				blitKey.srcSwizzleG = vkMapping.g;
				blitKey.srcSwizzleB = vkMapping.b;
				blitKey.srcSwizzleA = vkMapping.a;
			}
            id<MTLRenderPipelineState> mtlRPS = cmdEncoder->getCommandEncodingPool()->getCmdBlitImageMTLRenderPipelineState(blitKey);
            bool isBlittingDepth = mvkIsAnyFlagEnabled(blitKey.srcAspect, (VK_IMAGE_ASPECT_DEPTH_BIT));
            bool isBlittingStencil = mvkIsAnyFlagEnabled(blitKey.srcAspect, (VK_IMAGE_ASPECT_STENCIL_BIT));
            id<MTLDepthStencilState> mtlDSS = cmdEncoder->getCommandEncodingPool()->getMTLDepthStencilState(isBlittingDepth, isBlittingStencil);
            
            mtlColorAttDesc.level = mvkIBR.region.dstSubresource.mipLevel;
            mtlDepthAttDesc.level = mvkIBR.region.dstSubresource.mipLevel;
            mtlStencilAttDesc.level = mvkIBR.region.dstSubresource.mipLevel;

            bool isLayeredBlit = blitKey.dstSampleCount > 1 ? mtlFeats.multisampleLayeredRendering : mtlFeats.layeredRendering;

            uint32_t srcLayCnt = mvkIBR.region.srcSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
                _srcImage->getLayerCount() - mvkIBR.region.srcSubresource.baseArrayLayer :
                 mvkIBR.region.srcSubresource.layerCount;
            uint32_t dstLayCnt = mvkIBR.region.dstSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
                _dstImage->getLayerCount() - mvkIBR.region.dstSubresource.baseArrayLayer :
                 mvkIBR.region.dstSubresource.layerCount;
            uint32_t layCnt;
            // If either image is 3D, the difference in z offset must:
            // - Equal the difference in z offset of the other subresource, if it is also 3D.
            // - Equal the number of layers in the other subresource, if it is not 3D.
            // Otherwise, the number of layers should be the same.
            if (_dstImage->getMTLTextureType() == MTLTextureType3D) {
                layCnt = mvkAbsDiff(mvkIBR.region.dstOffsets[1].z, mvkIBR.region.dstOffsets[0].z);
            } else if (blitKey.srcMTLTextureType == MTLTextureType3D) {
                layCnt = mvkAbsDiff(mvkIBR.region.srcOffsets[1].z, mvkIBR.region.srcOffsets[0].z);
            } else {
                layCnt = srcLayCnt;
            }
            if (isLayeredBlit) {
                // In this case, I can blit all layers at once with a layered draw.
                mtlRPD.renderTargetArrayLengthMVK = layCnt;
                layCnt = 1;     // Only need to run the loop once.
            }
            for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
                // Update the render pass descriptor for the texture level and slice, and create a render encoder.
                if (_dstImage->getMTLTextureType() == MTLTextureType3D) {
                    if (isLayeredBlit) {
                        // For layered blits, the layers are always in ascending order. I'll reverse the order
                        // of the 'r' coordinates if the destination is mirrored.
                        uint32_t depthPlane = std::min(mvkIBR.region.dstOffsets[0].z, mvkIBR.region.dstOffsets[1].z);
                        mtlColorAttDesc.depthPlane = depthPlane;
                        mtlDepthAttDesc.depthPlane = depthPlane;
                        mtlStencilAttDesc.depthPlane = depthPlane;
                    } else {
                        uint32_t depthPlane = mvkIBR.region.dstOffsets[0].z + (mvkIBR.region.dstOffsets[1].z > mvkIBR.region.dstOffsets[0].z ? layIdx : -(layIdx + 1));
                        mtlColorAttDesc.depthPlane = depthPlane;
                        mtlDepthAttDesc.depthPlane = depthPlane;
                        mtlStencilAttDesc.depthPlane = depthPlane;
                    }
                } else {
                    mtlColorAttDesc.slice = mvkIBR.region.dstSubresource.baseArrayLayer + layIdx;
                    mtlDepthAttDesc.slice = mvkIBR.region.dstSubresource.baseArrayLayer + layIdx;
                    mtlStencilAttDesc.slice = mvkIBR.region.dstSubresource.baseArrayLayer + layIdx;
                }
                id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPD];
				cmdEncoder->_cmdBuffer->setMetalObjectLabel(mtlRendEnc, mvkMTLRenderCommandEncoderLabel(commandUse));

				cmdEncoder->barrierWait(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

                float zIncr;
                if (blitKey.srcMTLTextureType == MTLTextureType3D) {
                    // In this case, I need to interpolate along the third dimension manually.
                    VkExtent3D srcExtent = _srcImage->getExtent3D(srcPlaneIndex, mvkIBR.region.dstSubresource.mipLevel);
                    VkOffset3D so0 = mvkIBR.region.srcOffsets[0], so1 = mvkIBR.region.srcOffsets[1];
                    // If the dst is also 3D use the z offsets, otherwise use the layers.
                    float do0z = mvkIBR.region.dstOffsets[0].z, do1z = mvkIBR.region.dstOffsets[1].z;
                    if (_dstImage->getMTLTextureType() != MTLTextureType3D) {
                        do0z = mvkIBR.region.dstSubresource.baseArrayLayer;
                        do1z = do0z + dstLayCnt;
                    }
                    float startZ = (float)so0.z / (float)srcExtent.depth;
                    float endZ = (float)so1.z / (float)srcExtent.depth;
                    if (isLayeredBlit && do0z > do1z) {
                        // Swap start and end points so interpolation moves in the right direction.
                        std::swap(startZ, endZ);
                    }
                    zIncr = (endZ - startZ) / mvkAbsDiff(do1z, do0z);
                    float z = startZ + (isLayeredBlit ? 0.0 : (layIdx + 0.5)) * zIncr;
                    for (uint32_t i = 0; i < kMVKBlitVertexCount; ++i) {
                        mvkIBR.vertices[i].texCoord.z = z;
                    }
                }
                [mtlRendEnc pushDebugGroup: @"vkCmdBlitImage"];
                [mtlRendEnc setRenderPipelineState: mtlRPS];
                [mtlRendEnc setDepthStencilState: mtlDSS];
                cmdEncoder->setVertexBytes(mtlRendEnc, mvkIBR.vertices, sizeof(mvkIBR.vertices),
										   cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex));
                if (isLayeredBlit) {
                    cmdEncoder->setVertexBytes(mtlRendEnc, &zIncr, sizeof(zIncr), 0);
                }
                if (!mvkIsOnlyAnyFlagEnabled(blitKey.srcAspect, (VK_IMAGE_ASPECT_STENCIL_BIT))) {
                    [mtlRendEnc setFragmentTexture: srcMTLTex atIndex: 0];
                }
                if (isBlittingStencil) {
                    // For stencil blits of packed depth/stencil images, I need to use a stencil view. 
                    MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
                    if (pixFmts->isDepthFormat(blitKey.getSrcMTLPixelFormat()) &&
                        pixFmts->isStencilFormat(blitKey.getSrcMTLPixelFormat())) {
                        MTLPixelFormat stencilFmt = blitKey.getSrcMTLPixelFormat();
                        if (stencilFmt == MTLPixelFormatDepth32Float_Stencil8) {

                            stencilFmt = MTLPixelFormatX32_Stencil8;
#if MVK_MACOS
                        } else if (stencilFmt == MTLPixelFormatDepth24Unorm_Stencil8) {
                            stencilFmt = MTLPixelFormatX24_Stencil8;
#endif
                        }
                        id<MTLTexture> stencilMTLTex = [srcMTLTex newTextureViewWithPixelFormat: stencilFmt];
                        [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer>) { [stencilMTLTex release]; }];
                        [mtlRendEnc setFragmentTexture: stencilMTLTex atIndex: 1];
                    } else {
                        [mtlRendEnc setFragmentTexture: srcMTLTex atIndex: 1];
                    }
                }

                struct {
                    uint slice;
                    float lod;
                } texSubRez;
                texSubRez.slice = mvkIBR.region.srcSubresource.baseArrayLayer + layIdx;
                texSubRez.lod = mvkIBR.region.srcSubresource.mipLevel;
                cmdEncoder->setFragmentBytes(mtlRendEnc, &texSubRez, sizeof(texSubRez), 0);

                NSUInteger instanceCount = isLayeredBlit ? mtlRPD.renderTargetArrayLengthMVK : 1;
                [mtlRendEnc drawPrimitives: MTLPrimitiveTypeTriangleStrip vertexStart: 0 vertexCount: kMVKBlitVertexCount instanceCount: instanceCount];

				cmdEncoder->barrierUpdate(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

				[mtlRendEnc popDebugGroup];
                [mtlRendEnc endEncoding];
            }
        }
    }
}

template class MVKCmdBlitImage<1>;
template class MVKCmdBlitImage<4>;


#pragma mark -
#pragma mark MVKCmdResolveImage

template <size_t N>
VkResult MVKCmdResolveImage<N>::setContent(MVKCommandBuffer* cmdBuff,
										   VkImage srcImage,
										   VkImageLayout srcImageLayout,
										   VkImage dstImage,
										   VkImageLayout dstImageLayout,
										   uint32_t regionCount,
										   const VkImageResolve* pRegions) {
    _srcImage = (MVKImage*)srcImage;
    _srcLayout = srcImageLayout;
    _dstImage = (MVKImage*)dstImage;
    _dstLayout = dstImageLayout;

	_vkImageResolves.clear();	// Clear for reuse
	_vkImageResolves.reserve(regionCount);
    for (uint32_t regionIdx = 0; regionIdx < regionCount; regionIdx++) {
        auto& vkIR = pRegions[regionIdx];
        VkImageResolve2 vkIR2 = {
            VK_STRUCTURE_TYPE_IMAGE_RESOLVE_2, nullptr,
            vkIR.srcSubresource, vkIR.srcOffset,
            vkIR.dstSubresource, vkIR.dstOffset,
            vkIR.extent,
        };
        
        if (auto validation = validate(cmdBuff, &vkIR2); validation != VK_SUCCESS)
            return validation;

		_vkImageResolves.emplace_back(std::move(vkIR2));
    }

	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdResolveImage<N>::setContent(MVKCommandBuffer* cmdBuff,
                                           const VkResolveImageInfo2* pResolveImageInfo) {
    _srcImage = (MVKImage*)pResolveImageInfo->srcImage;
    _srcLayout = pResolveImageInfo->srcImageLayout;
    _dstImage = (MVKImage*)pResolveImageInfo->dstImage;
    _dstLayout = pResolveImageInfo->dstImageLayout;

    _vkImageResolves.clear();    // Clear for reuse
    _vkImageResolves.reserve(pResolveImageInfo->regionCount);
    for (uint32_t regionIdx = 0; regionIdx < pResolveImageInfo->regionCount; regionIdx++) {
        auto& vkIR = pResolveImageInfo->pRegions[regionIdx];
        
        if (auto validation = validate(cmdBuff, &vkIR); validation != VK_SUCCESS)
            return validation;
        
        _vkImageResolves.push_back(vkIR);
    }

    return VK_SUCCESS;
}

template <size_t N>
inline VkResult MVKCmdResolveImage<N>::validate(MVKCommandBuffer* cmdBuff, const VkImageResolve2* region) {
    uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region->dstSubresource.aspectMask);

    // Validate
    MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();
    if ( !mvkAreAllFlagsEnabled(pixFmts->getCapabilities(_dstImage->getMTLPixelFormat(dstPlaneIndex)), kMVKMTLFmtCapsResolve) ) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdResolveImage(): %s cannot be used as a resolve destination on this device.", pixFmts->getName(_dstImage->getVkFormat()));
    }
    return VK_SUCCESS;
}

template <size_t N>
void MVKCmdResolveImage<N>::encode(MVKCommandEncoder* cmdEncoder) {

	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	size_t vkIRCnt = _vkImageResolves.size();
	VkImageBlit expansionRegions[vkIRCnt];
	VkImageCopy copyRegions[vkIRCnt];

	// If we can do layered rendering to a multisample texture, I can resolve all the layers at once.
	uint32_t layerCnt = 0;
	if (mtlFeats.multisampleLayeredRendering) {
		layerCnt = (uint32_t)_vkImageResolves.size();
	} else {
		for (VkImageResolve2& vkIR : _vkImageResolves) {
			uint32_t dstLayCnt = vkIR.dstSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
				_dstImage->getLayerCount() - vkIR.dstSubresource.baseArrayLayer :
				vkIR.dstSubresource.layerCount;
			layerCnt += dstLayCnt;
		}
	}
	MVKMetalResolveSlice mtlResolveSlices[layerCnt];

	uint32_t expCnt = 0;
	uint32_t copyCnt = 0;
	uint32_t sliceCnt = 0;

	for (const auto& vkIR : _vkImageResolves) {
        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIR.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIR.dstSubresource.aspectMask);

		VkExtent3D srcImgExt = _srcImage->getExtent3D(srcPlaneIndex, vkIR.srcSubresource.mipLevel);
		VkExtent3D dstImgExt = _dstImage->getExtent3D(dstPlaneIndex, vkIR.dstSubresource.mipLevel);

		// If the region does not cover the entire content of the destination level, expand
		// the destination content in the region to the temporary image. The purpose of this
		// expansion is to render the existing content of the destination image to the
		// temporary transfer multisample image, so that regions of that temporary transfer
		// image can then be overwritten with content from the source image, prior to
		// resolving it back to the destination image.
		if ( !mvkVkExtent3DsAreEqual(dstImgExt, vkIR.extent) ) {
			VkImageBlit& expRgn = expansionRegions[expCnt++];
			expRgn.srcSubresource = vkIR.dstSubresource;
			expRgn.srcOffsets[0] = { 0, 0, 0 };
			expRgn.srcOffsets[1] = { int32_t(dstImgExt.width), int32_t(dstImgExt.height), int32_t(dstImgExt.depth) };
			expRgn.dstSubresource = vkIR.dstSubresource;
			expRgn.dstOffsets[0] = { 0, 0, 0 };
			expRgn.dstOffsets[1] = { int32_t(dstImgExt.width), int32_t(dstImgExt.height), int32_t(dstImgExt.depth) };
		}

		// Copy the region from the source image to the temporary multisample image,
		// prior to the temporary image being resolved back to the destination image.
		// The source of this copy stage is the source image, and the destination of
		// this copy stage is the temporary transfer image.
		bool needXfrImage = !mvkVkExtent3DsAreEqual(srcImgExt, vkIR.extent) || !mvkVkExtent3DsAreEqual(dstImgExt, vkIR.extent);
		if ( needXfrImage ) {
			VkImageCopy& cpyRgn = copyRegions[copyCnt++];
			cpyRgn.srcSubresource = vkIR.srcSubresource;
			cpyRgn.srcOffset = vkIR.srcOffset;
			cpyRgn.dstSubresource = vkIR.dstSubresource;
			cpyRgn.dstOffset = vkIR.dstOffset;
			cpyRgn.extent = vkIR.extent;
		}

		// Adds a resolve slice struct for each destination layer in the resolve region.
		// Note that the source subresource for this is that of the SOURCE image if we're doing a
		// direct resolve, but that of the DESTINATION if we need a temporary transfer image.
		mtlResolveSlices[sliceCnt].dstSubresource = vkIR.dstSubresource;
		mtlResolveSlices[sliceCnt].srcSubresource = needXfrImage ? vkIR.dstSubresource : vkIR.srcSubresource;
		if (mtlFeats.multisampleLayeredRendering) {
			sliceCnt++;
		} else {
			uint32_t layCnt = vkIR.dstSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
				_dstImage->getLayerCount() - vkIR.dstSubresource.baseArrayLayer :
				vkIR.dstSubresource.layerCount;
			mtlResolveSlices[sliceCnt].dstSubresource.layerCount = 1;
			mtlResolveSlices[sliceCnt].srcSubresource.layerCount = 1;
			sliceCnt++;
			for (uint32_t layIdx = 1; layIdx < layCnt; layIdx++) {
				MVKMetalResolveSlice& rslvSlice = mtlResolveSlices[sliceCnt];
				rslvSlice = mtlResolveSlices[sliceCnt - 1];
				rslvSlice.dstSubresource.baseArrayLayer++;
				rslvSlice.srcSubresource.baseArrayLayer++;
				sliceCnt++;
			}
		}
	}

    // Expansion and copying is not required. Each mip level of the source image
    // is being resolved entirely. Resolve directly from the source image.
    MVKImage* xfrImage = _srcImage;
	if (copyCnt) {
		// Expansion and/or copying is required. Acquire a temporary transfer image, expand
		// the destination image into it if necessary, copy from the source image to the
		// temporary image, and then resolve from the temporary image to the destination image.
		MVKImageDescriptorData xferImageData;
		_dstImage->getTransferDescriptorData(xferImageData);
		xferImageData.samples = _srcImage->getSampleCount();
		xfrImage = cmdEncoder->getCommandEncodingPool()->getTransferMVKImage(xferImageData);

		if (expCnt) {
			// Expand the current content of the destination image to the temporary transfer image.
			MVKCmdBlitImage<N> expCmd;
			expCmd.setContent(cmdEncoder->_cmdBuffer,
							  (VkImage)_dstImage, _dstLayout, (VkImage)xfrImage, _dstLayout,
							  expCnt, expansionRegions, VK_FILTER_LINEAR);
			expCmd.encode(cmdEncoder, kMVKCommandUseResolveExpandImage);
		}

		// Copy the resolve regions of the source image to the temporary transfer image.
		MVKCmdCopyImage<N> copyCmd;
		copyCmd.setContent(cmdEncoder->_cmdBuffer,
						   (VkImage)_srcImage, _srcLayout,
						   (VkImage)xfrImage, _dstLayout,
						   copyCnt, copyRegions);
		copyCmd.encode(cmdEncoder, kMVKCommandUseResolveCopyImage);
	}

	cmdEncoder->endCurrentMetalEncoding();

	MTLRenderPassDescriptor* mtlRPD = [MTLRenderPassDescriptor renderPassDescriptor];
    MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = mtlRPD.colorAttachments[0];
    mtlColorAttDesc.loadAction = MTLLoadActionLoad;
    mtlColorAttDesc.storeAction = MTLStoreActionMultisampleResolve;

	// For each resolve slice, update the render pass descriptor for
	// the texture level and slice and create a render encoder.
	for (uint32_t sIdx = 0; sIdx < sliceCnt; sIdx++) {
		MVKMetalResolveSlice& rslvSlice = mtlResolveSlices[sIdx];
        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(rslvSlice.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(rslvSlice.dstSubresource.aspectMask);

        mtlColorAttDesc.texture = xfrImage->getMTLTexture(srcPlaneIndex);
        mtlColorAttDesc.resolveTexture = _dstImage->getMTLTexture(dstPlaneIndex);
		mtlColorAttDesc.level = rslvSlice.srcSubresource.mipLevel;
		mtlColorAttDesc.slice = rslvSlice.srcSubresource.baseArrayLayer;
		mtlColorAttDesc.resolveLevel = rslvSlice.dstSubresource.mipLevel;
		mtlColorAttDesc.resolveSlice = rslvSlice.dstSubresource.baseArrayLayer;
		if (rslvSlice.dstSubresource.layerCount > 1) {
			mtlRPD.renderTargetArrayLengthMVK = rslvSlice.dstSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
				_dstImage->getLayerCount() - rslvSlice.dstSubresource.baseArrayLayer :
				rslvSlice.dstSubresource.layerCount;
		}
		id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPD];
		cmdEncoder->_cmdBuffer->setMetalObjectLabel(mtlRendEnc, mvkMTLRenderCommandEncoderLabel(kMVKCommandUseResolveImage));

		[mtlRendEnc pushDebugGroup: @"vkCmdResolveImage"];
		[mtlRendEnc popDebugGroup];

		cmdEncoder->barrierWait(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);
		cmdEncoder->barrierUpdate(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

		[mtlRendEnc endEncoding];
	}
}

template class MVKCmdResolveImage<1>;
template class MVKCmdResolveImage<4>;


#pragma mark -
#pragma mark MVKCmdCopyBuffer

// Matches shader struct.
typedef struct {
	uint32_t srcOffset;
	uint32_t dstOffset;
	uint32_t size;
} MVKCmdCopyBufferInfo;

template <size_t N>
VkResult MVKCmdCopyBuffer<N>::setContent(MVKCommandBuffer* cmdBuff,
										 VkBuffer srcBuffer,
										 VkBuffer destBuffer,
										 uint32_t regionCount,
										 const VkBufferCopy* pRegions) {
	_srcBuffer = (MVKBuffer*)srcBuffer;
	_dstBuffer = (MVKBuffer*)destBuffer;

	// Add buffer regions
	_bufferCopyRegions.clear();	// Clear for reuse
	_bufferCopyRegions.reserve(regionCount);
	for (uint32_t i = 0; i < regionCount; i++) {
        auto& region = pRegions[i];
        VkBufferCopy2 region2 = {
            VK_STRUCTURE_TYPE_BUFFER_COPY_2, nullptr,
            region.srcOffset, region.dstOffset, region.size,
        };
		_bufferCopyRegions.emplace_back(std::move(region2));
	}

	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdCopyBuffer<N>::setContent(MVKCommandBuffer* cmdBuff,
                                         const VkCopyBufferInfo2* pCopyBufferInfo) {
    _srcBuffer = (MVKBuffer*)pCopyBufferInfo->srcBuffer;
    _dstBuffer = (MVKBuffer*)pCopyBufferInfo->dstBuffer;

    // Add buffer regions
    _bufferCopyRegions.clear();    // Clear for reuse
    _bufferCopyRegions.reserve(pCopyBufferInfo->regionCount);
    for (uint32_t i = 0; i < pCopyBufferInfo->regionCount; i++) {
        _bufferCopyRegions.push_back(pCopyBufferInfo->pRegions[i]);
    }

    return VK_SUCCESS;
}

template <size_t N>
void MVKCmdCopyBuffer<N>::encode(MVKCommandEncoder* cmdEncoder) {
	id<MTLBuffer> srcMTLBuff = _srcBuffer->getMTLBuffer();
	NSUInteger srcMTLBuffOffset = _srcBuffer->getMTLBufferOffset();

	id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
	NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset();

	VkDeviceSize buffAlign = cmdEncoder->getMetalFeatures().mtlCopyBufferAlignment;

	for (const auto& cpyRgn : _bufferCopyRegions) {
		const bool useComputeCopy = buffAlign > 1 && (cpyRgn.srcOffset % buffAlign != 0 ||
													  cpyRgn.dstOffset % buffAlign != 0 ||
													  cpyRgn.size      % buffAlign != 0);
		if (useComputeCopy) {
			MVKAssert(mvkFits<uint32_t>(cpyRgn.srcOffset) && mvkFits<uint32_t>(cpyRgn.dstOffset) && mvkFits<uint32_t>(cpyRgn.size),
					  "Byte-aligned buffer copy region offsets and size must each fit into a 32-bit unsigned integer.");

			MVKCmdCopyBufferInfo copyInfo;
			copyInfo.srcOffset = (uint32_t)cpyRgn.srcOffset;
			copyInfo.dstOffset = (uint32_t)cpyRgn.dstOffset;
			copyInfo.size = (uint32_t)cpyRgn.size;

			id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyBuffer, true);
			[mtlComputeEnc pushDebugGroup: @"vkCmdCopyBuffer"];
			[mtlComputeEnc setComputePipelineState: cmdEncoder->getCommandEncodingPool()->getCmdCopyBufferBytesMTLComputePipelineState()];
			[mtlComputeEnc setBuffer:srcMTLBuff offset: srcMTLBuffOffset atIndex: 0];
			[mtlComputeEnc setBuffer:dstMTLBuff offset: dstMTLBuffOffset atIndex: 1];
			[mtlComputeEnc setBytes: &copyInfo length: sizeof(copyInfo) atIndex: 2];
			[mtlComputeEnc dispatchThreadgroups: MTLSizeMake(1, 1, 1) threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
			[mtlComputeEnc popDebugGroup];
		} else {
			id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyBuffer);
			[mtlBlitEnc copyFromBuffer: srcMTLBuff
						  sourceOffset: (srcMTLBuffOffset + cpyRgn.srcOffset)
							  toBuffer: dstMTLBuff
					 destinationOffset: (dstMTLBuffOffset + cpyRgn.dstOffset)
								  size: cpyRgn.size];
		}
	}
}

template class MVKCmdCopyBuffer<1>;
template class MVKCmdCopyBuffer<4>;


#pragma mark -
#pragma mark MVKCmdBufferImageCopy

// Matches shader struct.
typedef struct {
    uint32_t srcRowStride;
    uint32_t srcRowStrideHigh;
    uint32_t srcDepthStride;
    uint32_t srcDepthStrideHigh;
    uint32_t destRowStride;
    uint32_t destRowStrideHigh;
    uint32_t destDepthStride;
    uint32_t destDepthStrideHigh;
    VkFormat format;
    VkOffset3D offset;
    VkExtent3D extent;
} MVKCmdCopyBufferToImageInfo;

template <size_t N>
VkResult MVKCmdBufferImageCopy<N>::setContent(MVKCommandBuffer* cmdBuff,
											  VkBuffer buffer,
											  VkImage image,
											  VkImageLayout imageLayout,
											  uint32_t regionCount,
											  const VkBufferImageCopy* pRegions,
											  bool toImage) {
    _buffer = (MVKBuffer*)buffer;
    _image = (MVKImage*)image;
    _toImage = toImage;

    // Add buffer regions
    _bufferImageCopyRegions.clear();     // Clear for reuse
    _bufferImageCopyRegions.reserve(regionCount);
    for (uint32_t i = 0; i < regionCount; i++) {
        const auto& region = pRegions[i];
        VkBufferImageCopy2 region2 = {
            VK_STRUCTURE_TYPE_BUFFER_IMAGE_COPY_2, nullptr,
            region.bufferOffset, region.bufferRowLength, region.bufferImageHeight,
            region.imageSubresource, region.imageOffset, region.imageExtent,
        };
        _bufferImageCopyRegions.emplace_back(std::move(region2));
    }

	return validate(cmdBuff);
}

template <size_t N>
VkResult MVKCmdBufferImageCopy<N>::setContent(MVKCommandBuffer* cmdBuff,
                                              const VkCopyBufferToImageInfo2* pCopyBufferToImageInfo) {
    _buffer = (MVKBuffer*)pCopyBufferToImageInfo->srcBuffer;
    _image = (MVKImage*)pCopyBufferToImageInfo->dstImage;
    _toImage = true;
    
    _bufferImageCopyRegions.clear();     // Clear for reuse
    _bufferImageCopyRegions.resize(pCopyBufferToImageInfo->regionCount);
    std::memcpy(_bufferImageCopyRegions.data(), pCopyBufferToImageInfo->pRegions, pCopyBufferToImageInfo->regionCount * sizeof(VkBufferImageCopy2));
    return validate(cmdBuff);
}

template <size_t N>
VkResult MVKCmdBufferImageCopy<N>::setContent(MVKCommandBuffer* cmdBuff,
                                              const VkCopyImageToBufferInfo2* pCopyImageToBufferInfo) {
    _buffer = (MVKBuffer*)pCopyImageToBufferInfo->dstBuffer;
    _image = (MVKImage*)pCopyImageToBufferInfo->srcImage;
    _toImage = false;
    
    _bufferImageCopyRegions.clear();     // Clear for reuse
    _bufferImageCopyRegions.resize(pCopyImageToBufferInfo->regionCount);
    std::memcpy(_bufferImageCopyRegions.data(), pCopyImageToBufferInfo->pRegions, pCopyImageToBufferInfo->regionCount * sizeof(VkBufferImageCopy2));
    return validate(cmdBuff);
}

template <size_t N>
inline VkResult MVKCmdBufferImageCopy<N>::validate(MVKCommandBuffer *cmdBuff) {
    for (auto& region : _bufferImageCopyRegions) {
        if (!_image->hasExpectedTexelSize()) {
            MTLPixelFormat mtlPixFmt = _image->getMTLPixelFormat(MVKImage::getPlaneFromVkImageAspectFlags(region.imageSubresource.aspectMask));
            const char* cmdName = _toImage ? "vkCmdCopyBufferToImage" : "vkCmdCopyImageToBuffer";
            return cmdBuff->reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "%s(): The image is using Metal format %s as a substitute for Vulkan format %s. Since the pixel size is different, content for the image cannot be copied to or from a buffer.", cmdName, cmdBuff->getPixelFormats()->getName(mtlPixFmt), cmdBuff->getPixelFormats()->getName(_image->getVkFormat()));
        }
    }
    return VK_SUCCESS;
}
    
template <size_t N>
void MVKCmdBufferImageCopy<N>::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLBuffer> mtlBuffer = _buffer->getMTLBuffer();
    if ( !mtlBuffer ) { return; }

	NSUInteger mtlBuffOffsetBase = _buffer->getMTLBufferOffset();
    MVKCommandUse cmdUse = _toImage ? kMVKCommandUseCopyBufferToImage : kMVKCommandUseCopyImageToBuffer;
	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();

    for (auto& cpyRgn : _bufferImageCopyRegions) {
        uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(cpyRgn.imageSubresource.aspectMask);
        MTLPixelFormat mtlPixFmt = _image->getMTLPixelFormat(planeIndex);
        id<MTLTexture> mtlTexture = _image->getMTLTexture(planeIndex);
        if ( !mtlTexture ) { continue; }

		uint32_t mipLevel = cpyRgn.imageSubresource.mipLevel;
        MTLOrigin mtlTxtOrigin = mvkMTLOriginFromVkOffset3D(cpyRgn.imageOffset);
		MTLSize mtlTxtSize = mvkClampMTLSize(mvkMTLSizeFromVkExtent3D(cpyRgn.imageExtent),
											 mtlTxtOrigin,
											 mvkMTLSizeFromVkExtent3D(_image->getExtent3D(planeIndex, mipLevel)));
		NSUInteger mtlBuffOffset = mtlBuffOffsetBase + cpyRgn.bufferOffset;

        uint32_t buffImgWd = cpyRgn.bufferRowLength;
        if (buffImgWd == 0) { buffImgWd = cpyRgn.imageExtent.width; }

        uint32_t buffImgHt = cpyRgn.bufferImageHeight;
        if (buffImgHt == 0) { buffImgHt = cpyRgn.imageExtent.height; }

        NSUInteger bytesPerRow = pixFmts->getBytesPerRow(mtlPixFmt, buffImgWd);
        NSUInteger bytesPerImg = pixFmts->getBytesPerLayer(mtlPixFmt, bytesPerRow, buffImgHt);

        // If the format combines BOTH depth and stencil, determine whether one or both
        // components are to be copied, and adjust the byte counts and copy options accordingly.
        MTLBlitOption blitOptions = MTLBlitOptionNone;
        if (pixFmts->isDepthFormat(mtlPixFmt) && pixFmts->isStencilFormat(mtlPixFmt)) {

            VkImageAspectFlags imgFlags = cpyRgn.imageSubresource.aspectMask;
            bool wantDepth = mvkAreAllFlagsEnabled(imgFlags, VK_IMAGE_ASPECT_DEPTH_BIT);
            bool wantStencil = mvkAreAllFlagsEnabled(imgFlags, VK_IMAGE_ASPECT_STENCIL_BIT);

            // The stencil component is always 1 byte per pixel.
			// Don't reduce depths of 32-bit depth/stencil formats.
            if (wantDepth && !wantStencil) {
				if (pixFmts->getBytesPerTexel(mtlPixFmt) != 4) {
					bytesPerRow -= buffImgWd;
					bytesPerImg -= buffImgWd * buffImgHt;
				}
                blitOptions |= MTLBlitOptionDepthFromDepthStencil;
            } else if (wantStencil && !wantDepth) {
                bytesPerRow = buffImgWd;
                bytesPerImg = buffImgWd * buffImgHt;
                blitOptions |= MTLBlitOptionStencilFromDepthStencil;
            }
        }

#if MVK_APPLE_SILICON
		if (pixFmts->isPVRTCFormat(mtlPixFmt)) {
			blitOptions |= MTLBlitOptionRowLinearPVRTC;
		}
#endif

#if MVK_MACOS
		// If we're copying to a compressed 3D image, the image data need to be decompressed.
		// If we're copying to mip level 0, we can skip the copy and just decode
		// directly into the image. Otherwise, we need to use an intermediate buffer.
        if (_toImage && _image->getIsCompressed() && mtlTexture.textureType == MTLTextureType3D &&
            !cmdEncoder->getMetalFeatures().native3DCompressedTextures) {

            MVKCmdCopyBufferToImageInfo info;
            info.srcRowStride = bytesPerRow & 0xffffffff;
            info.srcRowStrideHigh = bytesPerRow >> 32;
            info.srcDepthStride = bytesPerImg & 0xffffffff;
            info.srcDepthStrideHigh = bytesPerImg >> 32;
            info.destRowStride = info.destRowStrideHigh = 0;
            info.destDepthStride = info.destDepthStrideHigh = 0;
            info.format = _image->getVkFormat();
            info.offset = cpyRgn.imageOffset;
            info.extent = cpyRgn.imageExtent;
            bool needsTempBuff = mipLevel != 0;
			id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(cmdUse, false);  // Compute state will be marked dirty on next compute encoder after Blit encoder below.
            id<MTLComputePipelineState> mtlComputeState = cmdEncoder->getCommandEncodingPool()->getCmdCopyBufferToImage3DDecompressMTLComputePipelineState(needsTempBuff);
            [mtlComputeEnc pushDebugGroup: @"vkCmdCopyBufferToImage"];
            [mtlComputeEnc setComputePipelineState: mtlComputeState];
            [mtlComputeEnc setBuffer: mtlBuffer offset: mtlBuffOffset atIndex: 0];
            MVKBuffer* tempBuff;
            if (needsTempBuff) {
                NSUInteger bytesPerDestRow = pixFmts->getBytesPerRow(mtlTexture.pixelFormat, info.extent.width);
                NSUInteger bytesPerDestImg = pixFmts->getBytesPerLayer(mtlTexture.pixelFormat, bytesPerDestRow, info.extent.height);
                // We're going to copy from the temporary buffer now, so use the
                // temp buffer parameters in the copy below.
                bytesPerRow = bytesPerDestRow;
                bytesPerImg = bytesPerDestImg;
                MVKBufferDescriptorData tempBuffData;
                tempBuffData.size = bytesPerDestImg * mtlTxtSize.depth;
                tempBuffData.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
                tempBuff = cmdEncoder->getCommandEncodingPool()->getTransferMVKBuffer(tempBuffData);
                mtlBuffer = tempBuff->getMTLBuffer();
                mtlBuffOffset = tempBuff->getMTLBufferOffset();
                info.destRowStride = bytesPerDestRow & 0xffffffff;
                info.destRowStrideHigh = bytesPerDestRow >> 32;
                info.destDepthStride = bytesPerDestImg & 0xffffffff;
                info.destDepthStrideHigh = bytesPerDestImg >> 32;
                [mtlComputeEnc setBuffer: mtlBuffer offset: mtlBuffOffset atIndex: 1];
            } else {
                [mtlComputeEnc setTexture: mtlTexture atIndex: 0];
            }
            cmdEncoder->setComputeBytes(mtlComputeEnc, &info, sizeof(info), 2);

            // Now work out how big to make the grid, and from there, the size and number of threadgroups.
            // One thread is run per block. Each block decompresses to an m x n array of texels.
            // So the size of the grid is (ceil(width/m), ceil(height/n), depth).
            VkExtent2D blockExtent = pixFmts->getBlockTexelSize(mtlPixFmt);
            MTLSize mtlGridSize = MTLSizeMake(mvkCeilingDivide<NSUInteger>(mtlTxtSize.width, blockExtent.width),
                                              mvkCeilingDivide<NSUInteger>(mtlTxtSize.height, blockExtent.height),
                                              mtlTxtSize.depth);
            // Use four times the thread execution width as the threadgroup size.
            MTLSize mtlTgrpSize = MTLSizeMake(2, 2, mtlComputeState.threadExecutionWidth);
            // Then the number of threadgroups is (ceil(x/2), ceil(y/2), ceil(z/t)),
            // where 't' is the thread execution width.
            mtlGridSize.width = mvkCeilingDivide(mtlGridSize.width, mtlTgrpSize.width);
            mtlGridSize.height = mvkCeilingDivide(mtlGridSize.height, mtlTgrpSize.height);
            mtlGridSize.depth = mvkCeilingDivide(mtlGridSize.depth, mtlTgrpSize.depth);
            // There may be extra threads, but that's OK; the shader does bounds checking to
            // ensure it doesn't try to write out of bounds.
            // Alternatively, we could use the newer -[MTLComputeCommandEncoder dispatchThreads:threadsPerThreadgroup:] method,
            // but that needs Metal 2.0.
            [mtlComputeEnc dispatchThreadgroups: mtlGridSize threadsPerThreadgroup: mtlTgrpSize];
            [mtlComputeEnc popDebugGroup];

            if (!needsTempBuff) { continue; }
        }
#endif

		// Don't supply bytes per image if not an arrayed texture
		if ( !isArrayTexture() ) { bytesPerImg = 0; }

        id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(cmdUse);

        uint32_t layCnt = cpyRgn.imageSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
            _image->getLayerCount() - cpyRgn.imageSubresource.baseArrayLayer :
            cpyRgn.imageSubresource.layerCount;
        for (uint32_t lyrIdx = 0; lyrIdx < layCnt; lyrIdx++) {
            if (_toImage) {
                [mtlBlitEnc copyFromBuffer: mtlBuffer
                              sourceOffset: (mtlBuffOffset + (bytesPerImg * lyrIdx))
                         sourceBytesPerRow: bytesPerRow
                       sourceBytesPerImage: bytesPerImg
                                sourceSize: mtlTxtSize
                                 toTexture: mtlTexture
                          destinationSlice: (cpyRgn.imageSubresource.baseArrayLayer + lyrIdx)
                          destinationLevel: mipLevel
                         destinationOrigin: mtlTxtOrigin
                                   options: blitOptions];
            } else {
                [mtlBlitEnc copyFromTexture: mtlTexture
                                sourceSlice: (cpyRgn.imageSubresource.baseArrayLayer + lyrIdx)
                                sourceLevel: mipLevel
                               sourceOrigin: mtlTxtOrigin
                                 sourceSize: mtlTxtSize
                                   toBuffer: mtlBuffer
                          destinationOffset: (mtlBuffOffset + (bytesPerImg * lyrIdx))
                     destinationBytesPerRow: bytesPerRow
                   destinationBytesPerImage: bytesPerImg
                                    options: blitOptions];
            }
        }
    }
}

template <size_t N>
bool MVKCmdBufferImageCopy<N>::isArrayTexture() {
	MTLTextureType mtlTexType = _image->getMTLTextureType();
	return (mtlTexType == MTLTextureType3D ||
			mtlTexType == MTLTextureType2DArray ||
#if MVK_MACOS_OR_IOS
			mtlTexType == MTLTextureType2DMultisampleArray ||
#endif
			mtlTexType == MTLTextureType1DArray);
}

template class MVKCmdBufferImageCopy<1>;
template class MVKCmdBufferImageCopy<4>;	// To support MVKCmdCopyImage
template class MVKCmdBufferImageCopy<8>;
template class MVKCmdBufferImageCopy<16>;


#pragma mark -
#pragma mark MVKCmdClearAttachments

template <size_t N>
VkResult MVKCmdClearAttachments<N>::setContent(MVKCommandBuffer* cmdBuff,
											   uint32_t attachmentCount,
											   const VkClearAttachment* pAttachments,
											   uint32_t rectCount,
											   const VkClearRect* pRects,
											   MVKCommandUse cmdUse) {
	_rpsKey.reset();
	_commandUse = cmdUse;
	_mtlDepthVal = 0.0;
    _mtlStencilValue = 0;
	MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();

    // For each attachment to be cleared, mark it so in the render pipeline state
    // attachment key, and populate the clear color value into a uniform array.
    // Also set the depth and stencil clear value to the last clear attachment that specifies them.
    for (uint32_t i = 0; i < attachmentCount; i++) {
        auto& clrAtt = pAttachments[i];

        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_COLOR_BIT)) {
            uint32_t caIdx = clrAtt.colorAttachment;        // Might be VK_ATTACHMENT_UNUSED
            if (caIdx != VK_ATTACHMENT_UNUSED) {
                _rpsKey.enableAttachment(caIdx);
                setClearValue(caIdx, clrAtt.clearValue);
            }
        }

        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_DEPTH_BIT)) {
            _rpsKey.enableAttachment(kMVKClearAttachmentDepthIndex);
            _mtlDepthVal = pixFmts->getMTLClearDepthValue(clrAtt.clearValue);
        }

        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT)) {
            _rpsKey.enableAttachment(kMVKClearAttachmentStencilIndex);
            _mtlStencilValue = pixFmts->getMTLClearStencilValue(clrAtt.clearValue);
        }
    }

    _clearRects.clear();		// Clear for reuse
    _clearRects.reserve(rectCount);
    for (uint32_t i = 0; i < rectCount; i++) {
        _clearRects.push_back(pRects[i]);
    }

	return VK_SUCCESS;
}

// Returns the total number of vertices needed to clear all layers of all rectangles.
template <size_t N>
uint32_t MVKCmdClearAttachments<N>::getVertexCount(MVKCommandEncoder* cmdEncoder) {
	uint32_t vtxCnt = 0;
	if (cmdEncoder->getSubpass()->isMultiview()) {
		// In this case, all the layer counts will be one. We want to use the number of views in the current multiview pass.
		vtxCnt = (uint32_t)_clearRects.size() * cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) * 6;
	} else {
		for (auto& rect : _clearRects) {
			vtxCnt += 6 * rect.layerCount;
		}
	}
	return vtxCnt;
}

// Populates the vertices for all clear rectangles within an attachment of the specified size.
template <size_t N>
void MVKCmdClearAttachments<N>::populateVertices(MVKCommandEncoder* cmdEncoder, simd::float4* vertices,
												 float attWidth, float attHeight) {
	uint32_t vtxIdx = 0;
    for (auto& rect : _clearRects) {
		vtxIdx = populateVertices(cmdEncoder, vertices, vtxIdx, rect, attWidth, attHeight);
	}
}

// Populates the vertices, starting at the vertex, from the specified rectangle within
// an attachment of the specified size. Returns the next vertex that needs to be populated.
template <size_t N>
uint32_t MVKCmdClearAttachments<N>::populateVertices(MVKCommandEncoder* cmdEncoder,
													 simd::float4* vertices,
													 uint32_t startVertex,
													 VkClearRect& clearRect,
													 float attWidth,
													 float attHeight) {
	// Determine the positions of the four edges of the
    // clear rectangle as a fraction of the attachment size.
    float leftPos = (float)(clearRect.rect.offset.x) / attWidth;
    float rightPos = (float)(clearRect.rect.extent.width) / attWidth + leftPos;
    float bottomPos = (float)(clearRect.rect.offset.y) / attHeight;
    float topPos = (float)(clearRect.rect.extent.height) / attHeight + bottomPos;

    // Now transform to clip-space coordinates,
    // which are bounded by (-1.0 < p < 1.0) in clip-space.
    leftPos = (leftPos * 2.0) - 1.0;
    rightPos = (rightPos * 2.0) - 1.0;
    bottomPos = (bottomPos * 2.0) - 1.0;
    topPos = (topPos * 2.0) - 1.0;

    simd::float4 vtx;

	uint32_t vtxIdx = startVertex;
	uint32_t startLayer, endLayer;
	if (cmdEncoder->getSubpass()->isMultiview()) {
		// In a multiview pass, the baseArrayLayer will be 0 and the layerCount will be 1.
		// Use the view count instead. We already set the base slice properly in the
		// MTLRenderPassDescriptor, so we don't need to offset the starting layer.
		startLayer = 0;
		endLayer = cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex());
	} else {
		startLayer = clearRect.baseArrayLayer;
		endLayer = startLayer + clearRect.layerCount;
	}
	for (uint32_t layer = startLayer; layer < endLayer; layer++) {

		vtx.z = 0.0;
		vtx.w = layer;

		// Top left vertex	- First triangle
		vtx.y = topPos;
		vtx.x = leftPos;
		vertices[vtxIdx++] = vtx;

		// Bottom left vertex
		vtx.y = bottomPos;
		vtx.x = leftPos;
		vertices[vtxIdx++] = vtx;

		// Bottom right vertex
		vtx.y = bottomPos;
		vtx.x = rightPos;
		vertices[vtxIdx++] = vtx;

		// Bottom right vertex	- Second triangle
		vertices[vtxIdx++] = vtx;

		// Top right vertex
		vtx.y = topPos;
		vtx.x = rightPos;
		vertices[vtxIdx++] = vtx;

		// Top left vertex
		vtx.y = topPos;
		vtx.x = leftPos;
		vertices[vtxIdx++] = vtx;
	}

	return vtxIdx;
}

template <size_t N>
void MVKCmdClearAttachments<N>::encode(MVKCommandEncoder* cmdEncoder) {

	uint32_t vtxCnt = getVertexCount(cmdEncoder);
	simd::float4 vertices[vtxCnt];
	simd::float4 clearColors[kMVKClearAttachmentCount];

	VkExtent2D fbExtent = cmdEncoder->getFramebufferExtent();
#if MVK_MACOS_OR_IOS
	// I need to know if the 'renderTargetWidth' and 'renderTargetHeight' properties
	// actually do something, but [MTLRenderPassDescriptor instancesRespondToSelector: @selector(renderTargetWidth)]
	// returns NO even on systems that do support it. So we have to check an actual instance.
	MTLRenderPassDescriptor* tempRPDesc = [MTLRenderPassDescriptor new];	// temp retain
	if ([tempRPDesc respondsToSelector: @selector(renderTargetWidth)]) {
		VkRect2D renderArea = cmdEncoder->clipToRenderArea({{0, 0}, fbExtent});
		fbExtent = {renderArea.offset.x + renderArea.extent.width, renderArea.offset.y + renderArea.extent.height};
	}
	[tempRPDesc release];													// temp release
#endif
	populateVertices(cmdEncoder, vertices, fbExtent.width, fbExtent.height);

	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
    MVKRenderSubpass* subpass = cmdEncoder->getSubpass();

    // Populate the render pipeline state attachment key with info from the subpass and framebuffer.
	_rpsKey.mtlSampleCount = mvkSampleCountFromVkSampleCountFlagBits(subpass->getSampleCount());
	if (cmdEncoder->_canUseLayeredRendering &&
		(cmdEncoder->getFramebufferLayerCount() > 1 || cmdEncoder->getSubpass()->isMultiview())) {
		_rpsKey.enableLayeredRendering();
	}

    uint32_t caCnt = subpass->getColorAttachmentCount();
    for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
        if (!subpass->isColorAttachmentUsed(caIdx)) {
            // If the subpass attachment isn't actually used, don't try to clear it.
            _rpsKey.disableAttachment(caIdx);
            continue;
        }
        VkFormat vkAttFmt = subpass->getColorAttachmentFormat(caIdx);
		_rpsKey.attachmentMTLPixelFormats[caIdx] = pixFmts->getMTLPixelFormat(vkAttFmt);
		MTLClearColor mtlCC = pixFmts->getMTLClearColor(getClearValue(caIdx), vkAttFmt);
		clearColors[caIdx] = { (float)mtlCC.red, (float)mtlCC.green, (float)mtlCC.blue, (float)mtlCC.alpha};
    }

    // The depth value is the vertex position Z value.
    clearColors[kMVKClearAttachmentDepthIndex] = { _mtlDepthVal, _mtlDepthVal, _mtlDepthVal, _mtlDepthVal };

	_rpsKey.attachmentMTLPixelFormats[kMVKClearAttachmentDepthIndex] = pixFmts->getMTLPixelFormat(subpass->getDepthFormat());
	if ( !subpass->isDepthAttachmentUsed() ) { _rpsKey.disableAttachment(kMVKClearAttachmentDepthIndex); }

	_rpsKey.attachmentMTLPixelFormats[kMVKClearAttachmentStencilIndex] = pixFmts->getMTLPixelFormat(subpass->getStencilFormat());
	if ( !subpass->isStencilAttachmentUsed() ) { _rpsKey.disableAttachment(kMVKClearAttachmentStencilIndex); }

	if ( !_rpsKey.isAnyAttachmentEnabled() ) { return; }

    // Render the clear colors to the attachments
	MVKCommandEncodingPool* cmdEncPool = cmdEncoder->getCommandEncodingPool();
    id<MTLRenderCommandEncoder> mtlRendEnc = cmdEncoder->_mtlRenderEncoder;
    [mtlRendEnc pushDebugGroup: getMTLDebugGroupLabel()];
    [mtlRendEnc setRenderPipelineState: cmdEncPool->getCmdClearMTLRenderPipelineState(_rpsKey)];
    [mtlRendEnc setDepthStencilState: cmdEncPool->getMTLDepthStencilState(_rpsKey.isAttachmentUsed(kMVKClearAttachmentDepthIndex),
																		  _rpsKey.isAttachmentUsed(kMVKClearAttachmentStencilIndex))];
    [mtlRendEnc setStencilReferenceValue: _mtlStencilValue];
    [mtlRendEnc setCullMode: MTLCullModeNone];
    [mtlRendEnc setTriangleFillMode: MTLTriangleFillModeFill];
    [mtlRendEnc setDepthBias: 0 slopeScale: 0 clamp: 0];
    [mtlRendEnc setViewport: {0, 0, (double) fbExtent.width, (double) fbExtent.height, 0.0, 1.0}];
    [mtlRendEnc setScissorRect: {0, 0, fbExtent.width, fbExtent.height}];
	[mtlRendEnc setVisibilityResultMode: MTLVisibilityResultModeDisabled
								 offset: cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset];

    cmdEncoder->setVertexBytes(mtlRendEnc, clearColors, sizeof(clearColors), 0, true);
    cmdEncoder->setFragmentBytes(mtlRendEnc, clearColors, sizeof(clearColors), 0, true);
    cmdEncoder->setVertexBytes(mtlRendEnc, vertices, vtxCnt * sizeof(vertices[0]),
							   cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex), true);
    [mtlRendEnc drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: vtxCnt];
    [mtlRendEnc popDebugGroup];

	// Apple GPUs do not support rendering/writing to an attachment and then reading from
	// that attachment within a single Metal renderpass. So, if any of the attachments just
	// cleared is an input attachment, we need to restart into separate Metal renderpasses.
	if (cmdEncoder->getMetalFeatures().tileBasedDeferredRendering) {
		bool needsRenderpassRestart = false;
		for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
			if (_rpsKey.isAttachmentEnabled(caIdx) && subpass->isColorAttachmentAlsoInputAttachment(caIdx)) {
				needsRenderpassRestart = true;
				break;
			}
		}
		if (needsRenderpassRestart) {
			cmdEncoder->encodeStoreActions(true);
			cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
		}
	}

	// Return to the previous rendering state on the next render activity
	cmdEncoder->_graphicsPipelineState.markDirty();
	cmdEncoder->_graphicsResourcesState.markDirty();
	cmdEncoder->_depthStencilState.markDirty();
	cmdEncoder->_renderingState.markDirty();
	cmdEncoder->_occlusionQueryState.markDirty();
}

template <size_t N>
NSString* MVKCmdClearAttachments<N>::getMTLDebugGroupLabel() {
	switch (_commandUse) {
		case kMVKCommandUseClearAttachments:    return @"vkCmdClearAttachments";
		case kMVKCommandUseBeginRenderPass:     return @"Clear Render Area on Begin Renderpass";
		case kMVKCommandUseBeginRendering:      return @"Clear Render Area on Begin Rendering";
		case kMVKCommandUseNextSubpass:         return @"Clear Render Area on Next Subpass";
		default:                                return @"Unknown Use Clear Attachments";
	}
}

template class MVKCmdClearAttachments<1>;
template class MVKCmdClearAttachments<4>;

template class MVKCmdClearSingleAttachment<1>;
template class MVKCmdClearSingleAttachment<4>;

template class MVKCmdClearMultiAttachments<1>;
template class MVKCmdClearMultiAttachments<4>;


#pragma mark -
#pragma mark MVKCmdClearImage

template <size_t N>
VkResult MVKCmdClearImage<N>::setContent(MVKCommandBuffer* cmdBuff,
										 VkImage image,
										 VkImageLayout imageLayout,
										 const VkClearValue& clearValue,
										 uint32_t rangeCount,
										 const VkImageSubresourceRange* pRanges) {
    _image = (MVKImage*)image;
	_clearValue = clearValue;

    // Add subresource ranges
    _subresourceRanges.clear();		// Clear for reuse
    _subresourceRanges.reserve(rangeCount);
    bool isDS = isDepthStencilClear();
    for (uint32_t rangeIdx = 0; rangeIdx < rangeCount; rangeIdx++) {
        auto& vkIR = pRanges[rangeIdx];
        uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIR.aspectMask);

        // Validate
        MVKMTLFmtCaps mtlFmtCaps = cmdBuff->getPixelFormats()->getCapabilities(_image->getMTLPixelFormat(planeIndex));
		bool isDestUnwritableLinear = MVK_MACOS && !cmdBuff->getMetalFeatures().renderLinearTextures && _image->getIsLinear();
		uint32_t reqCap = isDS ? kMVKMTLFmtCapsDSAtt : (isDestUnwritableLinear ? kMVKMTLFmtCapsWrite : kMVKMTLFmtCapsColorAtt);
        if (!mvkAreAllFlagsEnabled(mtlFmtCaps, reqCap)) {
            return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdClear%sImage(): Format %s cannot be cleared on this device.", (isDS ? "DepthStencil" : "Color"), cmdBuff->getPixelFormats()->getName(_image->getVkFormat()));
        }
        
        _subresourceRanges.push_back(vkIR);
    }
    
    // Validate
    if (_image->getImageType() == VK_IMAGE_TYPE_1D) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdClear%sImage(): Native 1D images cannot be cleared on this device. Consider enabling MVK_CONFIG_TEXTURE_1D_AS_2D.", (isDS ? "DepthStencil" : "Color"));
    }

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdClearImage<N>::encode(MVKCommandEncoder* cmdEncoder) {
	bool isDS = isDepthStencilClear();
	NSString* mtlRendEncName = (isDS
								? mvkMTLRenderCommandEncoderLabel(kMVKCommandUseClearDepthStencilImage)
								: mvkMTLRenderCommandEncoderLabel(kMVKCommandUseClearColorImage));

	cmdEncoder->endCurrentMetalEncoding();

	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
	for (auto& srRange : _subresourceRanges) {
		uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(srRange.aspectMask);
        id<MTLTexture> imgMTLTex = _image->getMTLTexture(planeIndex);
        if ( !imgMTLTex ) { continue; }

#if MVK_MACOS
        if (_image->getIsLinear() && !mtlFeats.renderLinearTextures) {
            // These images cannot be rendered. Instead, use a compute shader.
            // Luckily for us, linear images only have one mip and one array layer under Metal.
            assert( !isDS );
            const bool isTextureArray = _image->getLayerCount() != 1u;
            id<MTLComputePipelineState> mtlClearState = cmdEncoder->getCommandEncodingPool()->getCmdClearColorImageMTLComputePipelineState(pixFmts->getFormatType(_image->getVkFormat()), isTextureArray);
            id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseClearColorImage, true);
            [mtlComputeEnc pushDebugGroup: @"vkCmdClearColorImage"];
            [mtlComputeEnc setComputePipelineState: mtlClearState];
            [mtlComputeEnc setTexture: imgMTLTex atIndex: 0];
            cmdEncoder->setComputeBytes(mtlComputeEnc, &_clearValue, sizeof(_clearValue), 0);
            MTLSize gridSize = mvkMTLSizeFromVkExtent3D(_image->getExtent3D());
            MTLSize tgSize = MTLSizeMake(mtlClearState.threadExecutionWidth, 1, 1);
            if (mtlFeats.nonUniformThreadgroups) {
                [mtlComputeEnc dispatchThreads: gridSize threadsPerThreadgroup: tgSize];
            } else {
                MTLSize tgCount = MTLSizeMake(gridSize.width / tgSize.width, gridSize.height, gridSize.depth);
                if (gridSize.width % tgSize.width) { tgCount.width += 1; }
                [mtlComputeEnc dispatchThreadgroups: tgCount threadsPerThreadgroup: tgSize];
            }
            [mtlComputeEnc popDebugGroup];
            continue;
        }
#endif

		MTLRenderPassDescriptor* mtlRPDesc = [MTLRenderPassDescriptor renderPassDescriptor];
		MTLRenderPassColorAttachmentDescriptor* mtlRPCADesc = nil;
		MTLRenderPassDepthAttachmentDescriptor* mtlRPDADesc = nil;
		MTLRenderPassStencilAttachmentDescriptor* mtlRPSADesc = nil;

		bool isClearingColor = !isDS && mvkIsAnyFlagEnabled(srRange.aspectMask, VK_IMAGE_ASPECT_COLOR_BIT);
		bool isClearingDepth = isDS && mvkIsAnyFlagEnabled(srRange.aspectMask, VK_IMAGE_ASPECT_DEPTH_BIT);
		bool isClearingStencil = isDS && mvkIsAnyFlagEnabled(srRange.aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT);

		if (isClearingColor) {
			mtlRPCADesc = mtlRPDesc.colorAttachments[0];
			mtlRPCADesc.texture = imgMTLTex;
			mtlRPCADesc.loadAction = MTLLoadActionClear;
			mtlRPCADesc.storeAction = MTLStoreActionStore;
			mtlRPCADesc.clearColor = pixFmts->getMTLClearColor(_clearValue, _image->getVkFormat());
		}

		if (isClearingDepth) {
			mtlRPDADesc = mtlRPDesc.depthAttachment;
			mtlRPDADesc.texture = imgMTLTex;
			mtlRPDADesc.loadAction = MTLLoadActionClear;
			mtlRPDADesc.storeAction = MTLStoreActionStore;
			mtlRPDADesc.clearDepth = pixFmts->getMTLClearDepthValue(_clearValue);
		}

		if (isClearingStencil) {
			mtlRPSADesc = mtlRPDesc.stencilAttachment;
			mtlRPSADesc.texture = imgMTLTex;
			mtlRPSADesc.loadAction = MTLLoadActionClear;
			mtlRPSADesc.storeAction = MTLStoreActionStore;
			mtlRPSADesc.clearStencil = pixFmts->getMTLClearStencilValue(_clearValue);
		}

        // Extract the mipmap levels that are to be updated
        uint32_t mipLvlStart = srRange.baseMipLevel;
        uint32_t mipLvlCnt = srRange.levelCount;
        uint32_t mipLvlEnd = (mipLvlCnt == VK_REMAINING_MIP_LEVELS
                              ? _image->getMipLevelCount()
                              : (mipLvlStart + mipLvlCnt));

        // Extract the cube or array layers (slices) that are to be updated
		bool is3D = _image->getMTLTextureType() == MTLTextureType3D;
        uint32_t layerStart = is3D ? 0 : srRange.baseArrayLayer;
        uint32_t layerCnt = srRange.layerCount;
        uint32_t layerEnd = (layerCnt == VK_REMAINING_ARRAY_LAYERS
                             ? _image->getLayerCount()
                             : (layerStart + layerCnt));

        // Iterate across mipmap levels and layers, and perform and empty render to clear each
        for (uint32_t mipLvl = mipLvlStart; mipLvl < mipLvlEnd; mipLvl++) {
			mtlRPCADesc.level = mipLvl;
			mtlRPDADesc.level = mipLvl;
			mtlRPSADesc.level = mipLvl;

			// If a 3D image, we need to get the depth for each level.
			if (is3D) {
				layerCnt = _image->getExtent3D(planeIndex, mipLvl).depth;
				layerEnd = layerStart + layerCnt;
			}

            // If we can do layered rendering, I can clear all the layers at once.
            if (mtlFeats.layeredRendering && (mtlFeats.multisampleLayeredRendering || _image->getSampleCount() == VK_SAMPLE_COUNT_1_BIT)) {
                if (is3D) {
                    mtlRPCADesc.depthPlane = layerStart;
                    mtlRPDADesc.depthPlane = layerStart;
                    mtlRPSADesc.depthPlane = layerStart;
                } else {
                    mtlRPCADesc.slice = layerStart;
                    mtlRPDADesc.slice = layerStart;
                    mtlRPSADesc.slice = layerStart;
                }
                mtlRPDesc.renderTargetArrayLengthMVK = (layerCnt == VK_REMAINING_ARRAY_LAYERS
                                                        ? (_image->getLayerCount() - layerStart)
                                                        : layerCnt);

                id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];
				cmdEncoder->_cmdBuffer->setMetalObjectLabel(mtlRendEnc, mtlRendEncName);

				cmdEncoder->barrierWait(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);
				cmdEncoder->barrierUpdate(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

                [mtlRendEnc endEncoding];
            } else {
                for (uint32_t layer = layerStart; layer < layerEnd; layer++) {
                    if (is3D) {
                        mtlRPCADesc.depthPlane = layer;
                        mtlRPDADesc.depthPlane = layer;
                        mtlRPSADesc.depthPlane = layer;
                    } else {
                        mtlRPCADesc.slice = layer;
                        mtlRPDADesc.slice = layer;
                        mtlRPSADesc.slice = layer;
                    }

                    id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];
					cmdEncoder->_cmdBuffer->setMetalObjectLabel(mtlRendEnc, mtlRendEncName);

					cmdEncoder->barrierWait(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);
					cmdEncoder->barrierUpdate(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

					[mtlRendEnc endEncoding];
                }
            }
        }
    }
}

template class MVKCmdClearImage<1>;
template class MVKCmdClearImage<4>;

template class MVKCmdClearColorImage<1>;
template class MVKCmdClearColorImage<4>;

template class MVKCmdClearDepthStencilImage<1>;
template class MVKCmdClearDepthStencilImage<4>;


#pragma mark -
#pragma mark MVKCmdFillBuffer

VkResult MVKCmdFillBuffer::setContent(MVKCommandBuffer* cmdBuff,
									  VkBuffer dstBuffer,
									  VkDeviceSize dstOffset,
									  VkDeviceSize size,
									  uint32_t data) {
    _dstBuffer = (MVKBuffer*)dstBuffer;
    _dstOffset = dstOffset;
    _dataValue = data;

	// Round down in case of VK_WHOLE_SIZE on a buffer size which is not aligned to 4 bytes.
	VkDeviceSize byteCnt = (size == VK_WHOLE_SIZE) ? (_dstBuffer->getByteCount() - _dstOffset) : size;
	VkDeviceSize wdCnt = byteCnt >> 2;
	if (mvkFits<uint32_t>(wdCnt)) {
		_wordCount = (uint32_t)wdCnt;
	} else {
		_wordCount = std::numeric_limits<uint32_t>::max();
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdFillBuffer(): Buffer fill size must fit into a 32-bit unsigned integer. Fill size %llu is too large.", wdCnt);
	}

	return VK_SUCCESS;
}

void MVKCmdFillBuffer::encode(MVKCommandEncoder* cmdEncoder) {
	if (_wordCount == 0) { return; }

	id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
	NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset() + _dstOffset;

	// Determine the number of full threadgroups we can dispatch to cover the buffer content efficiently.
	// Some GPU's report different values for max threadgroup width between the pipeline state and device,
	// so conservatively use the minimum of these two reported values.
	id<MTLComputePipelineState> cps = cmdEncoder->getCommandEncodingPool()->getCmdFillBufferMTLComputePipelineState();
	NSUInteger tgWidth = std::min(cps.maxTotalThreadsPerThreadgroup, cmdEncoder->getMTLDevice().maxThreadsPerThreadgroup.width);
	NSUInteger tgCount = _wordCount / tgWidth;

	id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseFillBuffer, true);
	[mtlComputeEnc pushDebugGroup: @"vkCmdFillBuffer"];
	[mtlComputeEnc setComputePipelineState: cps];
	[mtlComputeEnc setBytes: &_dataValue length: sizeof(_dataValue) atIndex: 1];
	[mtlComputeEnc setBuffer: dstMTLBuff offset: dstMTLBuffOffset atIndex: 0];

	// Run as many full threadgroups as will fit into the buffer content.
	if (tgCount > 0) {
		[mtlComputeEnc dispatchThreadgroups: MTLSizeMake(tgCount, 1, 1)
					  threadsPerThreadgroup: MTLSizeMake(tgWidth, 1, 1)];
	}

	// If there is left-over buffer content after running full threadgroups, or if the buffer content
	// fits within a single threadgroup, run a single partial threadgroup of the appropriate size.
	uint32_t remainderWordCount = _wordCount % tgWidth;
	if (remainderWordCount > 0) {
		if (tgCount > 0) {		// If we've already written full threadgroups, skip ahead to unwritten content
			dstMTLBuffOffset += tgCount * tgWidth * sizeof(_dataValue);
			[mtlComputeEnc setBufferOffset: dstMTLBuffOffset atIndex: 0];
		}
		[mtlComputeEnc dispatchThreadgroups: MTLSizeMake(1, 1, 1)
					  threadsPerThreadgroup: MTLSizeMake(remainderWordCount, 1, 1)];
	}

	[mtlComputeEnc popDebugGroup];
}


#pragma mark -
#pragma mark MVKCmdUpdateBuffer

VkResult MVKCmdUpdateBuffer::setContent(MVKCommandBuffer* cmdBuff,
										VkBuffer dstBuffer,
										VkDeviceSize dstOffset,
										VkDeviceSize dataSize,
										const void* pData) {
    _dstBuffer = (MVKBuffer*)dstBuffer;
    _dstOffset = dstOffset;
    _dataSize = dataSize;

    _srcDataCache.reserve(_dataSize);
    memcpy(_srcDataCache.data(), pData, _dataSize);

	return VK_SUCCESS;
}

void MVKCmdUpdateBuffer::encode(MVKCommandEncoder* cmdEncoder) {

    id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseUpdateBuffer);

    id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
    NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset() + _dstOffset;

    // Copy data to the source MTLBuffer
    MVKMTLBufferAllocation* srcMTLBufferAlloc = cmdEncoder->getCommandEncodingPool()->acquireMTLBufferAllocation(_dataSize);
    void* pBuffData = srcMTLBufferAlloc->getContents();
    memcpy(pBuffData, _srcDataCache.data(), _dataSize);

    [mtlBlitEnc copyFromBuffer: srcMTLBufferAlloc->_mtlBuffer
                  sourceOffset: srcMTLBufferAlloc->_offset
                      toBuffer: dstMTLBuff
             destinationOffset: dstMTLBuffOffset
                          size: _dataSize];

    // Return the MTLBuffer allocation to the pool once the command buffer is done with it
    [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mcb) {
        srcMTLBufferAlloc->returnToPool();
    }];
}

