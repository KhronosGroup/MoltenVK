/*
 * MVKCmdTransfer.mm
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

#include "MVKCmdTransfer.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKCommandEncodingPool.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKFramebuffer.h"
#include "MVKRenderPass.h"
#include "MTLRenderPassDescriptor+MoltenVK.h"
#include "MVKEnvironment.h"
#include "MVKLogging.h"
#include "mvk_datatypes.hpp"
#include <algorithm>


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
        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIR.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIR.dstSubresource.aspectMask);
    
        // Validate
        MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();
        if ((_dstImage->getSampleCount() != _srcImage->getSampleCount()) ||
            (pixFmts->getBytesPerBlock(_dstImage->getMTLPixelFormat(dstPlaneIndex)) != pixFmts->getBytesPerBlock(_srcImage->getMTLPixelFormat(srcPlaneIndex)))) {
            return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdCopyImage(): Cannot copy between incompatible formats, such as formats of different pixel sizes, or between images with different sample counts.");
        }
        
		_vkImageCopies.push_back(vkIR);
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

    _srcImage->flushToDevice(0, VK_WHOLE_SIZE);

    for (uint32_t copyIdx = 0; copyIdx < copyCnt; copyIdx++) {
        auto& vkIC = _vkImageCopies[copyIdx];
        
        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIC.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIC.dstSubresource.aspectMask);
        
        MTLPixelFormat srcMTLPixFmt = _srcImage->getMTLPixelFormat(srcPlaneIndex);
        bool isSrcCompressed = _srcImage->getIsCompressed();

        MTLPixelFormat dstMTLPixFmt = _dstImage->getMTLPixelFormat(dstPlaneIndex);
        bool isDstCompressed = _dstImage->getIsCompressed();

        // If source and destination have different formats and at least one is compressed, use a temporary intermediary buffer
        bool useTempBuffer = (srcMTLPixFmt != dstMTLPixFmt) && (isSrcCompressed || isDstCompressed);

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
            tmpBuffSize += bytesPerRegion;
        } else {
            // Map the source pixel format to the dest pixel format through a texture view on the source texture.
            // If the source and dest pixel formats are the same, this will simply degenerate to the source texture itself.
            id<MTLTexture> srcMTLTex = _srcImage->getMTLTexture(srcPlaneIndex, _dstImage->getMTLPixelFormat(dstPlaneIndex));
            id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture(dstPlaneIndex);
            if ( !srcMTLTex || !dstMTLTex ) { return; }

            id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(commandUse);

            // If copies can be performed using direct texture-texture copying, do so
            uint32_t srcLevel = vkIC.srcSubresource.mipLevel;
            uint32_t srcBaseLayer = vkIC.srcSubresource.baseArrayLayer;
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
                                 sliceCount: vkIC.srcSubresource.layerCount
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
                    layCnt = vkIC.srcSubresource.layerCount;
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

	bool isDestUnwritableLinear = MVK_MACOS && !cmdBuff->getDevice()->_pMetalFeatures->renderLinearTextures && _dstImage->getIsLinear();

	_vkImageBlits.clear();		// Clear for reuse
	for (uint32_t rIdx = 0; rIdx < regionCount; rIdx++) {
		auto& vkIB = pRegions[rIdx];

		// Validate - macOS linear images cannot be a scaling or inversion destination
		if (isDestUnwritableLinear && !(canCopyFormats(vkIB) && canCopy(vkIB)) ) {
			return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdBlitImage(): Scaling or inverting to a linear destination image is not supported.");
		}

		_vkImageBlits.push_back(vkIB);
	}

	return VK_SUCCESS;
}

template <size_t N>
bool MVKCmdBlitImage<N>::canCopyFormats(const VkImageBlit& region) {
    uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.srcSubresource.aspectMask);
    uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.dstSubresource.aspectMask);
	return ((_srcImage->getMTLPixelFormat(srcPlaneIndex) == _dstImage->getMTLPixelFormat(dstPlaneIndex)) &&
			(_dstImage->getSampleCount() == _srcImage->getSampleCount()));
}

// The source and destination sizes must be equal and not be negative in any direction
template <size_t N>
bool MVKCmdBlitImage<N>::canCopy(const VkImageBlit& region) {
	VkOffset3D srcSize = mvkVkOffset3DDifference(region.srcOffsets[1], region.srcOffsets[0]);
	VkOffset3D dstSize = mvkVkOffset3DDifference(region.dstOffsets[1], region.dstOffsets[0]);
	return (mvkVkOffset3DsAreEqual(srcSize, dstSize) &&
			(srcSize.x >= 0) && (srcSize.y >= 0) && (srcSize.z >= 0));
}

template <size_t N>
void MVKCmdBlitImage<N>::populateVertices(MVKVertexPosTex* vertices, const VkImageBlit& region) {
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

	size_t vkIBCnt = _vkImageBlits.size();
	VkImageCopy vkImageCopies[vkIBCnt];
	MVKImageBlitRender mvkBlitRenders[vkIBCnt];
	uint32_t copyCnt = 0;
	uint32_t blitCnt = 0;

	// Separate BLITs into those that are really just simple texure region copies,
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
                [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer>) {
                    [srcMTLTex release];
                }];
            }
            blitKey.dstMTLPixelFormat = _dstImage->getMTLPixelFormat(dstPlaneIndex);
            blitKey.srcFilter = mvkMTLSamplerMinMagFilterFromVkFilter(_filter);
            blitKey.srcAspect = mvkIBR.region.srcSubresource.aspectMask & (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT);
            blitKey.dstSampleCount = mvkSampleCountFromVkSampleCountFlagBits(_dstImage->getSampleCount());
            id<MTLRenderPipelineState> mtlRPS = cmdEncoder->getCommandEncodingPool()->getCmdBlitImageMTLRenderPipelineState(blitKey);
            bool isBlittingDepth = mvkIsAnyFlagEnabled(blitKey.srcAspect, (VK_IMAGE_ASPECT_DEPTH_BIT));
            bool isBlittingStencil = mvkIsAnyFlagEnabled(blitKey.srcAspect, (VK_IMAGE_ASPECT_STENCIL_BIT));
            id<MTLDepthStencilState> mtlDSS = cmdEncoder->getCommandEncodingPool()->getMTLDepthStencilState(isBlittingDepth, isBlittingStencil);
            
            uint32_t vtxBuffIdx = cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex);
            
            mtlColorAttDesc.level = mvkIBR.region.dstSubresource.mipLevel;
            mtlDepthAttDesc.level = mvkIBR.region.dstSubresource.mipLevel;
            mtlStencilAttDesc.level = mvkIBR.region.dstSubresource.mipLevel;

            bool isLayeredBlit = blitKey.dstSampleCount > 1 ? cmdEncoder->getDevice()->_pMetalFeatures->multisampleLayeredRendering : cmdEncoder->getDevice()->_pMetalFeatures->layeredRendering;
            
            uint32_t layCnt = mvkIBR.region.srcSubresource.layerCount;
            if (_dstImage->getMTLTextureType() == MTLTextureType3D) {
                layCnt = mvkAbsDiff(mvkIBR.region.dstOffsets[1].z, mvkIBR.region.dstOffsets[0].z);
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
                setLabelIfNotNil(mtlRendEnc, mvkMTLRenderCommandEncoderLabel(commandUse));

                float zIncr;
                if (blitKey.srcMTLTextureType == MTLTextureType3D) {
                    // In this case, I need to interpolate along the third dimension manually.
                    VkExtent3D srcExtent = _srcImage->getExtent3D(srcPlaneIndex, mvkIBR.region.dstSubresource.mipLevel);
                    VkOffset3D so0 = mvkIBR.region.srcOffsets[0], so1 = mvkIBR.region.srcOffsets[1];
                    VkOffset3D do0 = mvkIBR.region.dstOffsets[0], do1 = mvkIBR.region.dstOffsets[1];
                    float startZ = (float)so0.z / (float)srcExtent.depth;
                    float endZ = (float)so1.z / (float)srcExtent.depth;
                    if (isLayeredBlit && do0.z > do1.z) {
                        // Swap start and end points so interpolation moves in the right direction.
                        std::swap(startZ, endZ);
                    }
                    zIncr = (endZ - startZ) / mvkAbsDiff(do1.z, do0.z);
                    float z = startZ + (isLayeredBlit ? 0.0 : (layIdx + 0.5)) * zIncr;
                    for (uint32_t i = 0; i < kMVKBlitVertexCount; ++i) {
                        mvkIBR.vertices[i].texCoord.z = z;
                    }
                }
                [mtlRendEnc pushDebugGroup: @"vkCmdBlitImage"];
                [mtlRendEnc setRenderPipelineState: mtlRPS];
                [mtlRendEnc setDepthStencilState: mtlDSS];
                cmdEncoder->setVertexBytes(mtlRendEnc, mvkIBR.vertices, sizeof(mvkIBR.vertices), vtxBuffIdx);
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
                        [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer>) {
                            [stencilMTLTex release];
                        }];
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
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIR.dstSubresource.aspectMask);

        // Validate
        MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();
        if ( !mvkAreAllFlagsEnabled(pixFmts->getCapabilities(_dstImage->getMTLPixelFormat(dstPlaneIndex)), kMVKMTLFmtCapsResolve) ) {
            return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdResolveImage(): %s cannot be used as a resolve destination on this device.", pixFmts->getName(_dstImage->getVkFormat()));
        }

		_vkImageResolves.push_back(vkIR);
    }

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdResolveImage<N>::encode(MVKCommandEncoder* cmdEncoder) {

	size_t vkIRCnt = _vkImageResolves.size();
	VkImageBlit expansionRegions[vkIRCnt];
	VkImageCopy copyRegions[vkIRCnt];

	// If we can do layered rendering to a multisample texture, I can resolve all the layers at once.
	uint32_t layerCnt = 0;
	if (cmdEncoder->getDevice()->_pMetalFeatures->multisampleLayeredRendering) {
		layerCnt = (uint32_t)_vkImageResolves.size();
	} else {
		for (VkImageResolve& vkIR : _vkImageResolves) { layerCnt += vkIR.dstSubresource.layerCount; }
	}
	MVKMetalResolveSlice mtlResolveSlices[layerCnt];

	uint32_t expCnt = 0;
	uint32_t copyCnt = 0;
	uint32_t sliceCnt = 0;

	for (VkImageResolve& vkIR : _vkImageResolves) {
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
		if (cmdEncoder->getDevice()->_pMetalFeatures->multisampleLayeredRendering) {
			sliceCnt++;
		} else {
			uint32_t layCnt = vkIR.dstSubresource.layerCount;
			mtlResolveSlices[sliceCnt].dstSubresource.layerCount = 1;
			mtlResolveSlices[sliceCnt].srcSubresource.layerCount = 1;
			for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
				MVKMetalResolveSlice& rslvSlice = mtlResolveSlices[sliceCnt++];
				rslvSlice = mtlResolveSlices[sliceCnt - 2];
				rslvSlice.dstSubresource.baseArrayLayer++;
				rslvSlice.srcSubresource.baseArrayLayer++;
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
			mtlRPD.renderTargetArrayLengthMVK = rslvSlice.dstSubresource.layerCount;
		}
		id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPD];
		setLabelIfNotNil(mtlRendEnc, mvkMTLRenderCommandEncoderLabel(kMVKCommandUseResolveImage));

		[mtlRendEnc pushDebugGroup: @"vkCmdResolveImage"];
		[mtlRendEnc popDebugGroup];
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
		_bufferCopyRegions.push_back(pRegions[i]);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdCopyBuffer<N>::encode(MVKCommandEncoder* cmdEncoder) {
	id<MTLBuffer> srcMTLBuff = _srcBuffer->getMTLBuffer();
	NSUInteger srcMTLBuffOffset = _srcBuffer->getMTLBufferOffset();

	id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
	NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset();

	VkDeviceSize buffAlign = cmdEncoder->getDevice()->_pMetalFeatures->mtlCopyBufferAlignment;

	for (auto& cpyRgn : _bufferCopyRegions) {
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

			id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyBuffer);
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
    _imageLayout = imageLayout;
    _toImage = toImage;

    // Add buffer regions
    _bufferImageCopyRegions.clear();     // Clear for reuse
    _bufferImageCopyRegions.reserve(regionCount);
    for (uint32_t i = 0; i < regionCount; i++) {
        _bufferImageCopyRegions.push_back(pRegions[i]);
        
        // Validate
        if ( !_image->hasExpectedTexelSize() ) {
            MTLPixelFormat mtlPixFmt = _image->getMTLPixelFormat(MVKImage::getPlaneFromVkImageAspectFlags(pRegions[i].imageSubresource.aspectMask));
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

#if MVK_IOS_OR_TVOS || MVK_MACOS_APPLE_SILICON
		if (pixFmts->isPVRTCFormat(mtlPixFmt)) {
			blitOptions |= MTLBlitOptionRowLinearPVRTC;
		}
#endif

#if MVK_MACOS
		// If we're copying to a compressed 3D image, the image data need to be decompressed.
		// If we're copying to mip level 0, we can skip the copy and just decode
		// directly into the image. Otherwise, we need to use an intermediate buffer.
        if (_toImage && _image->getIsCompressed() && mtlTexture.textureType == MTLTextureType3D &&
            !cmdEncoder->getDevice()->_pMetalFeatures->native3DCompressedTextures) {

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
            id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(cmdUse);
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

        for (uint32_t lyrIdx = 0; lyrIdx < cpyRgn.imageSubresource.layerCount; lyrIdx++) {
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
											   const VkClearRect* pRects) {
	_rpsKey.reset();
	_mtlDepthVal = 0.0;
    _mtlStencilValue = 0;
    _isClearingDepth = false;
    _isClearingStencil = false;
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
            _isClearingDepth = true;
            _rpsKey.enableAttachment(kMVKClearAttachmentDepthStencilIndex);
            _mtlDepthVal = pixFmts->getMTLClearDepthValue(clrAtt.clearValue);
        }

        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT)) {
            _isClearingStencil = true;
            _rpsKey.enableAttachment(kMVKClearAttachmentDepthStencilIndex);
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

	VkExtent2D fbExtent = cmdEncoder->_framebuffer->getExtent2D();
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
    uint32_t vtxBuffIdx = cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex);

    // Populate the render pipeline state attachment key with info from the subpass and framebuffer.
	_rpsKey.mtlSampleCount = mvkSampleCountFromVkSampleCountFlagBits(subpass->getSampleCount());
	if (cmdEncoder->_canUseLayeredRendering &&
		(cmdEncoder->_framebuffer->getLayerCount() > 1 || cmdEncoder->getSubpass()->isMultiview())) {
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

    // The depth value (including vertex position Z value) is held in the last index.
    clearColors[kMVKClearAttachmentDepthStencilIndex] = { _mtlDepthVal, _mtlDepthVal, _mtlDepthVal, _mtlDepthVal };

    VkFormat vkAttFmt = subpass->getDepthStencilFormat();
	MTLPixelFormat mtlAttFmt = pixFmts->getMTLPixelFormat(vkAttFmt);
    _rpsKey.attachmentMTLPixelFormats[kMVKClearAttachmentDepthStencilIndex] = mtlAttFmt;

	bool isClearingDepth = _isClearingDepth && pixFmts->isDepthFormat(mtlAttFmt);
	bool isClearingStencil = _isClearingStencil && pixFmts->isStencilFormat(mtlAttFmt);
    if (!isClearingDepth && !isClearingStencil) {
        // If the subpass attachment isn't actually used, don't try to clear it.
        _rpsKey.disableAttachment(kMVKClearAttachmentDepthStencilIndex);
    }

	if (!_rpsKey.isAnyAttachmentEnabled()) {
		// Nothing to do.
		return;
	}

    // Render the clear colors to the attachments
	MVKCommandEncodingPool* cmdEncPool = cmdEncoder->getCommandEncodingPool();
    id<MTLRenderCommandEncoder> mtlRendEnc = cmdEncoder->_mtlRenderEncoder;
    [mtlRendEnc pushDebugGroup: @"vkCmdClearAttachments"];
    [mtlRendEnc setRenderPipelineState: cmdEncPool->getCmdClearMTLRenderPipelineState(_rpsKey)];
    [mtlRendEnc setDepthStencilState: cmdEncPool->getMTLDepthStencilState(isClearingDepth, isClearingStencil)];
    [mtlRendEnc setStencilReferenceValue: _mtlStencilValue];
    [mtlRendEnc setCullMode: MTLCullModeNone];
    [mtlRendEnc setTriangleFillMode: MTLTriangleFillModeFill];
    [mtlRendEnc setDepthBias: 0 slopeScale: 0 clamp: 0];
    [mtlRendEnc setViewport: {0, 0, (double) fbExtent.width, (double) fbExtent.height, 0.0, 1.0}];
    [mtlRendEnc setScissorRect: {0, 0, fbExtent.width, fbExtent.height}];

    cmdEncoder->setVertexBytes(mtlRendEnc, clearColors, sizeof(clearColors), 0);
    cmdEncoder->setFragmentBytes(mtlRendEnc, clearColors, sizeof(clearColors), 0);
    cmdEncoder->setVertexBytes(mtlRendEnc, vertices, vtxCnt * sizeof(vertices[0]), vtxBuffIdx);
    [mtlRendEnc drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: vtxCnt];
    [mtlRendEnc popDebugGroup];

	// Return to the previous rendering state on the next render activity
	cmdEncoder->_graphicsPipelineState.markDirty();
	cmdEncoder->_depthStencilState.markDirty();
	cmdEncoder->_stencilReferenceValueState.markDirty();
    cmdEncoder->_depthBiasState.markDirty();
    cmdEncoder->_viewportState.markDirty();
    cmdEncoder->_scissorState.markDirty();
	cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
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
		bool isDestUnwritableLinear = MVK_MACOS && !cmdBuff->getDevice()->_pMetalFeatures->renderLinearTextures && _image->getIsLinear();
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

	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
	for (auto& srRange : _subresourceRanges) {
		uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(srRange.aspectMask);
        id<MTLTexture> imgMTLTex = _image->getMTLTexture(planeIndex);
        if ( !imgMTLTex ) { continue; }

#if MVK_MACOS
        if ( _image->getIsLinear() && !cmdEncoder->getDevice()->_pMetalFeatures->renderLinearTextures ) {
            // These images cannot be rendered. Instead, use a compute shader.
            // Luckily for us, linear images only have one mip and one array layer under Metal.
            assert( !isDS );
            id<MTLComputePipelineState> mtlClearState = cmdEncoder->getCommandEncodingPool()->getCmdClearColorImageMTLComputePipelineState(pixFmts->getFormatType(_image->getVkFormat()));
            id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseClearColorImage);
            [mtlComputeEnc pushDebugGroup: @"vkCmdClearColorImage"];
            [mtlComputeEnc setComputePipelineState: mtlClearState];
            [mtlComputeEnc setTexture: imgMTLTex atIndex: 0];
            cmdEncoder->setComputeBytes(mtlComputeEnc, &_clearValue, sizeof(_clearValue), 0);
            MTLSize gridSize = mvkMTLSizeFromVkExtent3D(_image->getExtent3D());
            MTLSize tgSize = MTLSizeMake(mtlClearState.threadExecutionWidth, 1, 1);
            if (cmdEncoder->getDevice()->_pMetalFeatures->nonUniformThreadgroups) {
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
            if (cmdEncoder->getDevice()->_pMetalFeatures->layeredRendering &&
                (_image->getSampleCount() == VK_SAMPLE_COUNT_1_BIT || cmdEncoder->getDevice()->_pMetalFeatures->multisampleLayeredRendering)) {
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
                setLabelIfNotNil(mtlRendEnc, mtlRendEncName);
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
                    setLabelIfNotNil(mtlRendEnc, mtlRendEncName);
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

	id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseFillBuffer);
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
    MVKMTLBufferAllocation* srcMTLBufferAlloc = (MVKMTLBufferAllocation*)cmdEncoder->getCommandEncodingPool()->acquireMTLBufferAllocation(_dataSize);
    memcpy(srcMTLBufferAlloc->getContents(), _srcDataCache.data(), _dataSize);

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

