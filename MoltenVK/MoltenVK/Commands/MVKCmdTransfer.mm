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

MVKFuncionOverride_getTypePool(CopyImage)

VkResult MVKCmdCopyImage::setContent(MVKCommandBuffer* cmdBuff,
									 VkImage srcImage,
									 VkImageLayout srcImageLayout,
									 VkImage dstImage,
									 VkImageLayout dstImageLayout,
									 uint32_t regionCount,
									 const VkImageCopy* pRegions,
									 MVKCommandUse commandUse) {

	setContent(cmdBuff, srcImage, srcImageLayout, dstImage, dstImageLayout, false, commandUse);

	MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();
	for (uint32_t i = 0; i < regionCount; i++) {
		addImageCopyRegion(pRegions[i], pixFmts);
	}

	// Validate
	if ( !_canCopyFormats ) {
		return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdCopyImage(): Cannot copy between incompatible formats, such as formats of different pixel sizes.");
	}
	if ((_srcImage->getMTLTextureType() == MTLTextureType3D) != (_dstImage->getMTLTextureType() == MTLTextureType3D)) {
		return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdCopyImage(): Metal does not support copying to or from slices of a 3D texture.");
	}

	return VK_SUCCESS;
}

// Sets common content for use by this class and subclasses
VkResult MVKCmdCopyImage::setContent(MVKCommandBuffer* cmdBuff,
									 VkImage srcImage,
									 VkImageLayout srcImageLayout,
									 VkImage dstImage,
									 VkImageLayout dstImageLayout,
									 bool formatsMustMatch,
									 MVKCommandUse commandUse) {
	MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();

	_srcImage = (MVKImage*)srcImage;
	_srcLayout = srcImageLayout;
	_srcMTLPixFmt = _srcImage->getMTLPixelFormat();
	_srcSampleCount = mvkSampleCountFromVkSampleCountFlagBits(_srcImage->getSampleCount());
	_isSrcCompressed = _srcImage->getIsCompressed();
	uint32_t srcBytesPerBlock = pixFmts->getMTLPixelFormatBytesPerBlock(_srcMTLPixFmt);

	_dstImage = (MVKImage*)dstImage;
	_dstLayout = dstImageLayout;
	_dstMTLPixFmt = _dstImage->getMTLPixelFormat();
	_dstSampleCount = mvkSampleCountFromVkSampleCountFlagBits(_dstImage->getSampleCount());
	_isDstCompressed = _dstImage->getIsCompressed();
	uint32_t dstBytesPerBlock = pixFmts->getMTLPixelFormatBytesPerBlock(_dstMTLPixFmt);

	_canCopyFormats = (_dstSampleCount == _srcSampleCount) && (formatsMustMatch
																? (_dstMTLPixFmt == _srcMTLPixFmt)
																: (dstBytesPerBlock == srcBytesPerBlock));

	_useTempBuffer = (_srcMTLPixFmt != _dstMTLPixFmt) && (_isSrcCompressed || _isDstCompressed);	// Different formats and at least one is compressed

	_commandUse = commandUse;
	_tmpBuffSize = 0;

	_imageCopyRegions.clear();		// Clear for reuse
	_srcTmpBuffImgCopies.clear();	// Clear for reuse
	_dstTmpBuffImgCopies.clear();	// Clear for reuse

	return VK_SUCCESS;
}

void MVKCmdCopyImage::addImageCopyRegion(const VkImageCopy& region, MVKPixelFormats* pixFmts) {
	if (_useTempBuffer) {
		addTempBufferImageCopyRegion(region, pixFmts);	// Convert to image->buffer->image copies
	} else {
		_imageCopyRegions.push_back(region);
	}
}

// Add an image->buffer copy and buffer->image copy to replace the image->image copy
void MVKCmdCopyImage::addTempBufferImageCopyRegion(const VkImageCopy& region, MVKPixelFormats* pixFmts) {

	// Add copy from source image to temp buffer.
	VkBufferImageCopy buffImgCpy;
	buffImgCpy.bufferOffset = _tmpBuffSize;
	buffImgCpy.bufferRowLength = 0;
	buffImgCpy.bufferImageHeight = 0;
	buffImgCpy.imageSubresource = region.srcSubresource;
	buffImgCpy.imageOffset = region.srcOffset;
	buffImgCpy.imageExtent = region.extent;
	_srcTmpBuffImgCopies.push_back(buffImgCpy);

	// Add copy from temp buffer to destination image.
	// Extent is provided in source texels. If the source is compressed but the
	// destination is not, each destination pixel will consume an entire source block,
	// so we must downscale the destination extent by the size of the source block.
	VkExtent3D dstExtent = region.extent;
	if (_isSrcCompressed && !_isDstCompressed) {
		VkExtent2D srcBlockExtent = pixFmts->getMTLPixelFormatBlockTexelSize(_srcMTLPixFmt);
		dstExtent.width /= srcBlockExtent.width;
		dstExtent.height /= srcBlockExtent.height;
	}
	buffImgCpy.bufferOffset = _tmpBuffSize;
	buffImgCpy.bufferRowLength = 0;
	buffImgCpy.bufferImageHeight = 0;
	buffImgCpy.imageSubresource = region.dstSubresource;
	buffImgCpy.imageOffset = region.dstOffset;
	buffImgCpy.imageExtent = dstExtent;
	_dstTmpBuffImgCopies.push_back(buffImgCpy);

	NSUInteger bytesPerRow = pixFmts->getMTLPixelFormatBytesPerRow(_srcMTLPixFmt, region.extent.width);
	NSUInteger bytesPerRegion = pixFmts->getMTLPixelFormatBytesPerLayer(_srcMTLPixFmt, bytesPerRow, region.extent.height);
	_tmpBuffSize += bytesPerRegion;
}

void MVKCmdCopyImage::encode(MVKCommandEncoder* cmdEncoder) {
	// Unless we need to use an intermediary buffer copy, map the source pixel format to the
	// dest pixel format through a texture view on the source texture. If the source and dest
	// pixel formats are the same, this will simply degenerate to the source texture itself.
	MTLPixelFormat mapSrcMTLPixFmt = _useTempBuffer ? _srcMTLPixFmt : _dstMTLPixFmt;
	id<MTLTexture> srcMTLTex = _srcImage->getMTLTexture(mapSrcMTLPixFmt);
	id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture();
	if ( !srcMTLTex || !dstMTLTex ) { return; }

	id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(_commandUse);

	// If copies can be performed using direct texture-texture copying, do so
	for (auto& cpyRgn : _imageCopyRegions) {
		uint32_t  srcLevel = cpyRgn.srcSubresource.mipLevel;
		MTLOrigin srcOrigin = mvkMTLOriginFromVkOffset3D(cpyRgn.srcOffset);
		MTLSize   srcSize = mvkClampMTLSize(mvkMTLSizeFromVkExtent3D(cpyRgn.extent),
											srcOrigin,
											mvkMTLSizeFromVkExtent3D(_srcImage->getExtent3D(srcLevel)));
		uint32_t  dstLevel = cpyRgn.dstSubresource.mipLevel;
		MTLOrigin dstOrigin = mvkMTLOriginFromVkOffset3D(cpyRgn.dstOffset);
		uint32_t  srcBaseLayer = cpyRgn.srcSubresource.baseArrayLayer;
		uint32_t  dstBaseLayer = cpyRgn.dstSubresource.baseArrayLayer;
		uint32_t  layCnt = cpyRgn.srcSubresource.layerCount;

		for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
			[mtlBlitEnc copyFromTexture: srcMTLTex
							sourceSlice: srcBaseLayer + layIdx
							sourceLevel: srcLevel
						   sourceOrigin: srcOrigin
							 sourceSize: srcSize
							  toTexture: dstMTLTex
					   destinationSlice: dstBaseLayer + layIdx
					   destinationLevel: dstLevel
					  destinationOrigin: dstOrigin];
		}
	}

	// If copies could not be performed directly between images,
	// use a temporary buffer acting as a waystation between the images.
	if ( !_srcTmpBuffImgCopies.empty() ) {
		MVKBufferDescriptorData tempBuffData;
		tempBuffData.size = _tmpBuffSize;
		tempBuffData.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
		MVKBuffer* tempBuff = cmdEncoder->getCommandEncodingPool()->getTransferMVKBuffer(tempBuffData);

		MVKCmdBufferImageCopy cpyCmd(&cmdEncoder->_cmdBuffer->getCommandPool()->_cmdBufferImageCopyPool);

		// Copy from source image to buffer
		// Create and execute a temporary buffer image command.
		// To be threadsafe...do NOT acquire and return the command from the pool.
		cpyCmd.setContent(cmdEncoder->_cmdBuffer,
						  (VkBuffer) tempBuff,
						  (VkImage) _srcImage,
						  _srcLayout,
						  (uint32_t)_srcTmpBuffImgCopies.size(),
						  _srcTmpBuffImgCopies.data(),
						  false);
		cpyCmd.encode(cmdEncoder);

		// Copy from buffer to destination image
		// Create and execute a temporary buffer image command.
		// To be threadsafe...do NOT acquire and return the command from the pool.
		cpyCmd.setContent(cmdEncoder->_cmdBuffer,
						  (VkBuffer) tempBuff,
						  (VkImage) _dstImage,
						  _dstLayout,
						  (uint32_t)_dstTmpBuffImgCopies.size(),
						  _dstTmpBuffImgCopies.data(),
						  true);
		cpyCmd.encode(cmdEncoder);
	}
}


#pragma mark -
#pragma mark MVKCmdBlitImage

MVKFuncionOverride_getTypePool(BlitImage)

VkResult MVKCmdBlitImage::setContent(MVKCommandBuffer* cmdBuff,
									 VkImage srcImage,
									 VkImageLayout srcImageLayout,
									 VkImage dstImage,
									 VkImageLayout dstImageLayout,
									 uint32_t regionCount,
									 const VkImageBlit* pRegions,
									 VkFilter filter,
									 MVKCommandUse commandUse) {

	VkResult rslt = MVKCmdCopyImage::setContent(cmdBuff, srcImage, srcImageLayout, dstImage, dstImageLayout, true, commandUse);

	_blitKey.srcMTLPixelFormat = _srcMTLPixFmt;
	_blitKey.srcMTLTextureType = _srcImage->getMTLTextureType();
	_blitKey.dstMTLPixelFormat = _dstMTLPixFmt;
	_blitKey.srcFilter = mvkMTLSamplerMinMagFilterFromVkFilter(filter);
	_blitKey.dstSampleCount = _dstSampleCount;

	MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();

	_mvkImageBlitRenders.clear();		// Clear for reuse
	for (uint32_t i = 0; i < regionCount; i++) {
		addImageBlitRegion(pRegions[i], pixFmts);
	}

	// Validate
	if ( !_mvkImageBlitRenders.empty() &&
		(pixFmts->mtlPixelFormatIsDepthFormat(_srcMTLPixFmt) ||
		 pixFmts->mtlPixelFormatIsStencilFormat(_srcMTLPixFmt)) ) {

		_mvkImageBlitRenders.clear();
		return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdBlitImage(): Scaling or inverting depth/stencil images is not supported.");
	}

	return rslt;
}

void MVKCmdBlitImage::addImageBlitRegion(const VkImageBlit& region,
										 MVKPixelFormats* pixFmts) {
	if (_canCopyFormats && canCopy(region)) {
		addImageCopyRegionFromBlitRegion(region, pixFmts);	// Convert to image copy
	} else {
		MVKImageBlitRender blitRender;
		blitRender.region = region;
		populateVertices(blitRender.vertices, region);
		_mvkImageBlitRenders.push_back(blitRender);
	}
}

// The source and destination sizes must be equal and not be negative in any direction
bool MVKCmdBlitImage::canCopy(const VkImageBlit& region) {
	VkOffset3D srcSize = mvkVkOffset3DDifference(region.srcOffsets[1], region.srcOffsets[0]);
	VkOffset3D dstSize = mvkVkOffset3DDifference(region.dstOffsets[1], region.dstOffsets[0]);
	return (mvkVkOffset3DsAreEqual(srcSize, dstSize) &&
			(srcSize.x >= 0) && (srcSize.y >= 0) && (srcSize.z >= 0));
}

void MVKCmdBlitImage::addImageCopyRegionFromBlitRegion(const VkImageBlit& region,
													   MVKPixelFormats* pixFmts) {
	const VkOffset3D& so0 = region.srcOffsets[0];
	const VkOffset3D& so1 = region.srcOffsets[1];

	VkImageCopy cpyRgn;
	cpyRgn.srcSubresource = region.srcSubresource;
	cpyRgn.srcOffset = region.srcOffsets[0];
	cpyRgn.dstSubresource = region.dstSubresource;
	cpyRgn.dstOffset = region.dstOffsets[0];
	cpyRgn.extent.width = so1.x - so0.x;
	cpyRgn.extent.height = so1.y - so0.y;
	cpyRgn.extent.depth = so1.z - so0.z;

	MVKCmdCopyImage::addImageCopyRegion(cpyRgn, pixFmts);
}

void MVKCmdBlitImage::populateVertices(MVKVertexPosTex* vertices, const VkImageBlit& region) {
    const VkOffset3D& so0 = region.srcOffsets[0];
    const VkOffset3D& so1 = region.srcOffsets[1];
    const VkOffset3D& do0 = region.dstOffsets[0];
    const VkOffset3D& do1 = region.dstOffsets[1];

    // Get the extents of the source and destination textures.
    VkExtent3D srcExtent = _srcImage->getExtent3D(region.srcSubresource.mipLevel);
    VkExtent3D dstExtent = _dstImage->getExtent3D(region.dstSubresource.mipLevel);

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

void MVKCmdBlitImage::encode(MVKCommandEncoder* cmdEncoder) {

	// Perform those BLITs that can be covered by simple texture copying.
	if ( !_imageCopyRegions.empty() ) {
		MVKCmdCopyImage::encode(cmdEncoder);
	}

	// Perform those BLITs that require rendering to destination texture.
	if ( !_mvkImageBlitRenders.empty() ) {

		cmdEncoder->endCurrentMetalEncoding();

		id<MTLTexture> srcMTLTex = _srcImage->getMTLTexture();
		id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture();
		if ( !srcMTLTex || !dstMTLTex ) { return; }

		MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = _mtlRenderPassDescriptor.colorAttachments[0];
		mtlColorAttDesc.texture = dstMTLTex;

		uint32_t vtxBuffIdx = cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex);
		id<MTLRenderPipelineState> mtlRPS = cmdEncoder->getCommandEncodingPool()->getCmdBlitImageMTLRenderPipelineState(_blitKey);

		for (auto& bltRend : _mvkImageBlitRenders) {

			mtlColorAttDesc.level = bltRend.region.dstSubresource.mipLevel;

			uint32_t layCnt = bltRend.region.srcSubresource.layerCount;
			for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
				// Update the render pass descriptor for the texture level and slice, and create a render encoder.
				mtlColorAttDesc.slice = bltRend.region.dstSubresource.baseArrayLayer + layIdx;
				id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: _mtlRenderPassDescriptor];
				setLabelIfNotNil(mtlRendEnc, mvkMTLRenderCommandEncoderLabel(_commandUse));

				[mtlRendEnc pushDebugGroup: @"vkCmdBlitImage"];
				[mtlRendEnc setRenderPipelineState: mtlRPS];
				cmdEncoder->setVertexBytes(mtlRendEnc, bltRend.vertices, sizeof(bltRend.vertices), vtxBuffIdx);
				[mtlRendEnc setFragmentTexture: srcMTLTex atIndex: 0];

				struct {
					uint slice;
					float lod;
				} texSubRez;
				texSubRez.slice = bltRend.region.srcSubresource.baseArrayLayer + layIdx;
				texSubRez.lod = bltRend.region.srcSubresource.mipLevel;
				cmdEncoder->setFragmentBytes(mtlRendEnc, &texSubRez, sizeof(texSubRez), 0);

				[mtlRendEnc drawPrimitives: MTLPrimitiveTypeTriangleStrip vertexStart: 0 vertexCount: kMVKBlitVertexCount];
				[mtlRendEnc popDebugGroup];
				[mtlRendEnc endEncoding];
			}
		}
	}
}


#pragma mark Construction

MVKCmdBlitImage::MVKCmdBlitImage(MVKCommandTypePool<MVKCmdBlitImage>* pool)
        : MVKCmdCopyImage::MVKCmdCopyImage((MVKCommandTypePool<MVKCmdCopyImage>*)pool) {

    initMTLRenderPassDescriptor();
}

// Create and configure the render pass descriptor
void MVKCmdBlitImage::initMTLRenderPassDescriptor() {
    _mtlRenderPassDescriptor = [[MTLRenderPassDescriptor renderPassDescriptor] retain];		// retained
    MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = _mtlRenderPassDescriptor.colorAttachments[0];
    mtlColorAttDesc.loadAction = MTLLoadActionLoad;
    mtlColorAttDesc.storeAction = MTLStoreActionStore;
}

MVKCmdBlitImage::~MVKCmdBlitImage() {
	[_mtlRenderPassDescriptor release];
}


#pragma mark -
#pragma mark MVKCmdResolveImage

MVKFuncionOverride_getTypePool(ResolveImage)

VkResult MVKCmdResolveImage::setContent(MVKCommandBuffer* cmdBuff,
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

    // Deterine the total number of texture layers being affected
    uint32_t layerCnt = 0;
    for (uint32_t i = 0; i < regionCount; i++) {
        layerCnt += pRegions[i].dstSubresource.layerCount;
    }

    // Resize the region arrays accordingly
    _expansionRegions.clear();              // Clear for reuse
    _expansionRegions.reserve(regionCount);
    _copyRegions.clear();                   // Clear for reuse
    _copyRegions.reserve(regionCount);
    _mtlResolveSlices.clear();              // Clear for reuse
    _mtlResolveSlices.reserve(layerCnt);

    // Add image regions
    for (uint32_t i = 0; i < regionCount; i++) {
        const VkImageResolve& rslvRgn = pRegions[i];
        addExpansionRegion(rslvRgn);
        addCopyRegion(rslvRgn);
        addResolveSlices(rslvRgn);
    }

    _dstImage->getTransferDescriptorData(_transferImageData);
	_transferImageData.samples = _srcImage->getSampleCount();

	// Validate
	if ( !mvkAreAllFlagsEnabled(cmdBuff->getPixelFormats()->getMTLPixelFormatCapabilities(_dstImage->getMTLPixelFormat()), kMVKMTLFmtCapsResolve) ) {
		return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdResolveImage(): %s cannot be used as a resolve destination on this device.", cmdBuff->getPixelFormats()->getVkFormatName(_dstImage->getVkFormat()));
	}

	return VK_SUCCESS;
}

/**
 * Adds a VkImageBlit region, constructed from the resolve region, to the internal collection
 * of expansion regions, unless the entire content of the destination texture of this command 
 * is to be resolved, an expansion region will not be added.
 *
 * The purpose of an expansion regions is to render the existing content of the destination
 * image of this command to the temporary transfer multisample image, so that regions of that 
 * temporary transfer image can then be overwritten with content from the source image of this
 * command, prior to resolving it back to the destination image of this command.
 *
 * As such, the source of this expansion stage is the destination image of this command,
 * and the destination of this expansion stage is a temp image that has the same shape
 * as the source image of this command.
 */
void MVKCmdResolveImage::addExpansionRegion(const VkImageResolve& resolveRegion) {
    uint32_t mipLvl = resolveRegion.dstSubresource.mipLevel;
    VkExtent3D srcImgExt = _srcImage->getExtent3D(mipLvl);
    VkExtent3D dstImgExt = _dstImage->getExtent3D(mipLvl);

    // No need to add an expansion region if the entire content of
    // the source image is being resolved to the destination image.
    if (mvkVkExtent3DsAreEqual(srcImgExt, resolveRegion.extent)) { return; }

    // The source of this temporary content move is the full extent of the DESTINATION
    // image of the resolve command, and the destination of this temporary content move
    // is the full extent of the SOURCE image of the resolve command.
    VkImageBlit expRgn = {
        .srcSubresource = resolveRegion.dstSubresource,
        .srcOffsets[0] = { 0, 0, 0 },
        .srcOffsets[1] = { int32_t(dstImgExt.width), int32_t(dstImgExt.height), int32_t(dstImgExt.depth) },
        .dstSubresource = resolveRegion.dstSubresource,
        .dstOffsets[0] = { 0, 0, 0 },
        .dstOffsets[1] = { int32_t(srcImgExt.width), int32_t(srcImgExt.height), int32_t(srcImgExt.depth) },
    };
    _expansionRegions.push_back(expRgn);
}

/**
 * Adds a VkImageCopy region, constructed from the resolve region,
 * to the internal collection of copy regions.
 *
 * The purpose of a copy region is to copy regions from the source image of this command to
 * the temporary image, prior to the temporary image being resolved back to the destination
 * image of this command.
 *
 * As such, the source of this copy stage is the source image of this command, and the
 * destination of this copy stage is the temporary transfer image that has the same shape 
 * as the source image of this command.
 */
void MVKCmdResolveImage::addCopyRegion(const VkImageResolve& resolveRegion) {
    VkImageCopy cpyRgn = {
        .srcSubresource = resolveRegion.srcSubresource,
        .srcOffset = resolveRegion.srcOffset,
        .dstSubresource = resolveRegion.srcSubresource,
        .dstOffset = resolveRegion.srcOffset,
        .extent = resolveRegion.extent,
    };
    _copyRegions.push_back(cpyRgn);
}

/** Adds a resolve slice struct for each destination layer in the resolve region. */
void MVKCmdResolveImage::addResolveSlices(const VkImageResolve& resolveRegion) {
    MVKMetalResolveSlice rslvSlice;
    rslvSlice.level = resolveRegion.dstSubresource.mipLevel;

    uint32_t baseLayer = resolveRegion.dstSubresource.baseArrayLayer;
    uint32_t layCnt = resolveRegion.dstSubresource.layerCount;
    for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
        rslvSlice.slice = baseLayer + layIdx;
        _mtlResolveSlices.push_back(rslvSlice);
    }
}

void MVKCmdResolveImage::encode(MVKCommandEncoder* cmdEncoder) {
    MVKImage* xfrImage = cmdEncoder->getCommandEncodingPool()->getTransferMVKImage(_transferImageData);

    id<MTLTexture> xfrMTLTex = xfrImage->getMTLTexture();
    id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture();
    if ( !xfrMTLTex || !dstMTLTex ) { return; }

    // Expand the current content of the destination image to the temporary transfer image.
    // Create and execute a temporary BLIT image command.
    // To be threadsafe...do NOT acquire and return the command from the pool.
    uint32_t expRgnCnt = uint32_t(_expansionRegions.size());
    if (expRgnCnt > 0) {
        MVKCmdBlitImage expandCmd(&cmdEncoder->_cmdBuffer->getCommandPool()->_cmdBlitImagePool);
        expandCmd.setContent(cmdEncoder->_cmdBuffer,
							 (VkImage)_dstImage, _dstLayout, (VkImage)xfrImage, _dstLayout,
                             expRgnCnt, _expansionRegions.data(),
                             VK_FILTER_LINEAR, kMVKCommandUseResolveExpandImage);
        expandCmd.encode(cmdEncoder);
    }

    // Copy the resolve regions of the source image to the temporary transfer image.
    // Create and execute a temporary copy image command.
    // To be threadsafe...do NOT acquire and return the command from the pool.
    uint32_t cpyRgnCnt = uint32_t(_copyRegions.size());
    if (cpyRgnCnt > 0) {
        MVKCmdCopyImage copyCmd(&cmdEncoder->_cmdBuffer->getCommandPool()->_cmdCopyImagePool);
        copyCmd.setContent(cmdEncoder->_cmdBuffer,
						   (VkImage)_srcImage, _srcLayout, (VkImage)xfrImage, _dstLayout,
                           cpyRgnCnt, _copyRegions.data(), kMVKCommandUseResolveCopyImage);
        copyCmd.encode(cmdEncoder);
    }

    cmdEncoder->endCurrentMetalEncoding();

    MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = _mtlRenderPassDescriptor.colorAttachments[0];
    mtlColorAttDesc.texture = xfrMTLTex;
    mtlColorAttDesc.resolveTexture = dstMTLTex;

    for (auto& rslvSlice : _mtlResolveSlices) {

        // Update the render pass descriptor for the texture level and slice, and create a render encoder.
        mtlColorAttDesc.level = rslvSlice.level;
        mtlColorAttDesc.slice = rslvSlice.slice;
        mtlColorAttDesc.resolveLevel = rslvSlice.level;
        mtlColorAttDesc.resolveSlice = rslvSlice.slice;
        id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: _mtlRenderPassDescriptor];
		setLabelIfNotNil(mtlRendEnc, mvkMTLRenderCommandEncoderLabel(kMVKCommandUseResolveImage));

        [mtlRendEnc pushDebugGroup: @"vkCmdResolveImage"];
        [mtlRendEnc popDebugGroup];
        [mtlRendEnc endEncoding];
    }
}

MVKCmdResolveImage::MVKCmdResolveImage(MVKCommandTypePool<MVKCmdResolveImage>* pool)
        : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {

    initMTLRenderPassDescriptor();
}

// Create and configure the render pass descriptor
void MVKCmdResolveImage::initMTLRenderPassDescriptor() {
    _mtlRenderPassDescriptor = [[MTLRenderPassDescriptor renderPassDescriptor] retain];		// retained
    MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = _mtlRenderPassDescriptor.colorAttachments[0];
    mtlColorAttDesc.loadAction = MTLLoadActionLoad;
    mtlColorAttDesc.storeAction = MTLStoreActionMultisampleResolve;
}

MVKCmdResolveImage::~MVKCmdResolveImage() {
    [_mtlRenderPassDescriptor release];
}


#pragma mark -
#pragma mark MVKCmdCopyBuffer

MVKFuncionOverride_getTypePool(CopyBuffer)

// Matches shader struct.
typedef struct {
	uint32_t srcOffset;
	uint32_t dstOffset;
	uint32_t size;
} MVKCmdCopyBufferInfo;

VkResult MVKCmdCopyBuffer::setContent(MVKCommandBuffer* cmdBuff,
									  VkBuffer srcBuffer,
									  VkBuffer destBuffer,
									  uint32_t regionCount,
									  const VkBufferCopy* pRegions) {
	_srcBuffer = (MVKBuffer*)srcBuffer;
	_dstBuffer = (MVKBuffer*)destBuffer;

	// Add buffer regions
	_mtlBuffCopyRegions.clear();	// Clear for reuse
	_mtlBuffCopyRegions.reserve(regionCount);
	for (uint32_t i = 0; i < regionCount; i++) {
		_mtlBuffCopyRegions.push_back(pRegions[i]);
	}

	return VK_SUCCESS;
}

void MVKCmdCopyBuffer::encode(MVKCommandEncoder* cmdEncoder) {
	id<MTLBuffer> srcMTLBuff = _srcBuffer->getMTLBuffer();
	NSUInteger srcMTLBuffOffset = _srcBuffer->getMTLBufferOffset();

	id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
	NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset();

	VkDeviceSize buffAlign = cmdEncoder->getDevice()->_pMetalFeatures->mtlCopyBufferAlignment;

	for (auto& cpyRgn : _mtlBuffCopyRegions) {
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


#pragma mark -
#pragma mark MVKCmdBufferImageCopy

MVKFuncionOverride_getTypePool(BufferImageCopy)

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

VkResult MVKCmdBufferImageCopy::setContent(MVKCommandBuffer* cmdBuff,
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
    }

    // Validate
    if ( !_image->hasExpectedTexelSize() ) {
        const char* cmdName = _toImage ? "vkCmdCopyBufferToImage" : "vkCmdCopyImageToBuffer";
        return reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "%s(): The image is using Metal format %s as a substitute for Vulkan format %s. Since the pixel size is different, content for the image cannot be copied to or from a buffer.", cmdName, cmdBuff->getPixelFormats()->getMTLPixelFormatName(_image->getMTLPixelFormat()), cmdBuff->getPixelFormats()->getVkFormatName(_image->getVkFormat()));
    }

	return VK_SUCCESS;
}

void MVKCmdBufferImageCopy::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLBuffer> mtlBuffer = _buffer->getMTLBuffer();
    id<MTLTexture> mtlTexture = _image->getMTLTexture();
    if ( !mtlBuffer || !mtlTexture ) { return; }

	NSUInteger mtlBuffOffsetBase = _buffer->getMTLBufferOffset();
    MTLPixelFormat mtlPixFmt = _image->getMTLPixelFormat();
    MVKCommandUse cmdUse = _toImage ? kMVKCommandUseCopyBufferToImage : kMVKCommandUseCopyImageToBuffer;
	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();

    for (auto& cpyRgn : _bufferImageCopyRegions) {

		uint32_t mipLevel = cpyRgn.imageSubresource.mipLevel;
        MTLOrigin mtlTxtOrigin = mvkMTLOriginFromVkOffset3D(cpyRgn.imageOffset);
		MTLSize mtlTxtSize = mvkClampMTLSize(mvkMTLSizeFromVkExtent3D(cpyRgn.imageExtent),
											 mtlTxtOrigin,
											 mvkMTLSizeFromVkExtent3D(_image->getExtent3D(mipLevel)));
		NSUInteger mtlBuffOffset = mtlBuffOffsetBase + cpyRgn.bufferOffset;

        uint32_t buffImgWd = cpyRgn.bufferRowLength;
        if (buffImgWd == 0) { buffImgWd = cpyRgn.imageExtent.width; }

        uint32_t buffImgHt = cpyRgn.bufferImageHeight;
        if (buffImgHt == 0) { buffImgHt = cpyRgn.imageExtent.height; }

        NSUInteger bytesPerRow = pixFmts->getMTLPixelFormatBytesPerRow(mtlPixFmt, buffImgWd);
        NSUInteger bytesPerImg = pixFmts->getMTLPixelFormatBytesPerLayer(mtlPixFmt, bytesPerRow, buffImgHt);

        // If the format combines BOTH depth and stencil, determine whether one or both
        // components are to be copied, and adjust the byte counts and copy options accordingly.
        MTLBlitOption blitOptions = MTLBlitOptionNone;
        if (pixFmts->mtlPixelFormatIsDepthFormat(mtlPixFmt) &&
			pixFmts->mtlPixelFormatIsStencilFormat(mtlPixFmt)) {

            VkImageAspectFlags imgFlags = cpyRgn.imageSubresource.aspectMask;
            bool wantDepth = mvkAreAllFlagsEnabled(imgFlags, VK_IMAGE_ASPECT_DEPTH_BIT);
            bool wantStencil = mvkAreAllFlagsEnabled(imgFlags, VK_IMAGE_ASPECT_STENCIL_BIT);

            // The stencil component is always 1 byte per pixel.
			// Don't reduce depths of 32-bit depth/stencil formats.
            if (wantDepth && !wantStencil) {
				if (pixFmts->getMTLPixelFormatBytesPerTexel(mtlPixFmt) != 4) {
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

#if MVK_IOS
		if (pixFmts->mtlPixelFormatIsPVRTCFormat(mtlPixFmt)) {
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
                NSUInteger bytesPerDestRow = pixFmts->getMTLPixelFormatBytesPerRow(mtlTexture.pixelFormat, info.extent.width);
                NSUInteger bytesPerDestImg = pixFmts->getMTLPixelFormatBytesPerLayer(mtlTexture.pixelFormat, bytesPerDestRow, info.extent.height);
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
            VkExtent2D blockExtent = pixFmts->getMTLPixelFormatBlockTexelSize(mtlPixFmt);
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

bool MVKCmdBufferImageCopy::isArrayTexture() {
	MTLTextureType mtlTexType = _image->getMTLTextureType();
	return (mtlTexType == MTLTextureType3D ||
			mtlTexType == MTLTextureType2DArray ||
#if MVK_MACOS
			mtlTexType == MTLTextureType2DMultisampleArray ||
#endif
			mtlTexType == MTLTextureType1DArray);
}


#pragma mark -
#pragma mark MVKCmdClearAttachments

MVKFuncionOverride_getTypePool(ClearAttachments)

VkResult MVKCmdClearAttachments::setContent(MVKCommandBuffer* cmdBuff,
											uint32_t attachmentCount,
											const VkClearAttachment* pAttachments,
											uint32_t rectCount,
											const VkClearRect* pRects) {
	_rpsKey.reset();
    _mtlStencilValue = 0;
    _isClearingDepth = false;
    _isClearingStencil = false;
    float mtlDepthVal = 0.0;
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
                _vkClearValues[caIdx] = clrAtt.clearValue;
            }
        }

        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_DEPTH_BIT)) {
            _isClearingDepth = true;
            _rpsKey.enableAttachment(kMVKClearAttachmentDepthStencilIndex);
            mtlDepthVal = pixFmts->getMTLClearDepthFromVkClearValue(clrAtt.clearValue);
        }

        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT)) {
            _isClearingStencil = true;
            _rpsKey.enableAttachment(kMVKClearAttachmentDepthStencilIndex);
            _mtlStencilValue = pixFmts->getMTLClearStencilFromVkClearValue(clrAtt.clearValue);
        }
    }

    // The depth value (including vertex position Z value) is held in the last index.
    _clearColors[kMVKClearAttachmentDepthStencilIndex] = { mtlDepthVal, mtlDepthVal, mtlDepthVal, mtlDepthVal };

    _clearRects.clear();		// Clear for reuse
    _clearRects.reserve(rectCount);
    for (uint32_t i = 0; i < rectCount; i++) {
        _clearRects.push_back(pRects[i]);
    }

	_vertices.clear();			// Clear for reuse
    _vertices.reserve(rectCount * 6);

	return VK_SUCCESS;
}

// Populates the vertices for all clear rectangles within an attachment of the specified size.
void MVKCmdClearAttachments::populateVertices(float attWidth, float attHeight) {
    for (auto& rect : _clearRects) { populateVertices(rect, attWidth, attHeight); }
}

// Populates the vertices from the specified rectangle within an attachment of the specified size.
void MVKCmdClearAttachments::populateVertices(VkClearRect& clearRect, float attWidth, float attHeight) {

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

	uint32_t startLayer = clearRect.baseArrayLayer;
	uint32_t endLayer = startLayer + clearRect.layerCount;
	for (uint32_t layer = startLayer; layer < endLayer; layer++) {

		vtx.z = 0.0;
		vtx.w = layer;

		// Top left vertex	- First triangle
		vtx.y = topPos;
		vtx.x = leftPos;
		_vertices.push_back(vtx);

		// Bottom left vertex
		vtx.y = bottomPos;
		vtx.x = leftPos;
		_vertices.push_back(vtx);

		// Bottom right vertex
		vtx.y = bottomPos;
		vtx.x = rightPos;
		_vertices.push_back(vtx);

		// Bottom right vertex	- Second triangle
		_vertices.push_back(vtx);

		// Top right vertex
		vtx.y = topPos;
		vtx.x = rightPos;
		_vertices.push_back(vtx);

		// Top left vertex
		vtx.y = topPos;
		vtx.x = leftPos;
		_vertices.push_back(vtx);
	}
}

void MVKCmdClearAttachments::encode(MVKCommandEncoder* cmdEncoder) {

	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
    MVKRenderSubpass* subpass = cmdEncoder->getSubpass();
    VkExtent2D fbExtent = cmdEncoder->_framebuffer->getExtent2D();
    populateVertices(fbExtent.width, fbExtent.height);
    uint32_t vtxCnt = (uint32_t)_vertices.size();
    uint32_t vtxBuffIdx = cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex);

    // Populate the render pipeline state attachment key with info from the subpass and framebuffer.
	_rpsKey.mtlSampleCount = mvkSampleCountFromVkSampleCountFlagBits(subpass->getSampleCount());
	if (cmdEncoder->_isUsingLayeredRendering) { _rpsKey.enableLayeredRendering(); }

    uint32_t caCnt = subpass->getColorAttachmentCount();
    for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
        VkFormat vkAttFmt = subpass->getColorAttachmentFormat(caIdx);
		_rpsKey.attachmentMTLPixelFormats[caIdx] = pixFmts->getMTLPixelFormatFromVkFormat(vkAttFmt);
		MTLClearColor mtlCC = pixFmts->getMTLClearColorFromVkClearValue(_vkClearValues[caIdx], vkAttFmt);
		_clearColors[caIdx] = { (float)mtlCC.red, (float)mtlCC.green, (float)mtlCC.blue, (float)mtlCC.alpha};
    }

    VkFormat vkAttFmt = subpass->getDepthStencilFormat();
	MTLPixelFormat mtlAttFmt = pixFmts->getMTLPixelFormatFromVkFormat(vkAttFmt);
    _rpsKey.attachmentMTLPixelFormats[kMVKClearAttachmentDepthStencilIndex] = mtlAttFmt;

	bool isClearingDepth = _isClearingDepth && pixFmts->mtlPixelFormatIsDepthFormat(mtlAttFmt);
	bool isClearingStencil = _isClearingStencil && pixFmts->mtlPixelFormatIsStencilFormat(mtlAttFmt);

    // Render the clear colors to the attachments
	MVKCommandEncodingPool* cmdEncPool = cmdEncoder->getCommandEncodingPool();
    id<MTLRenderCommandEncoder> mtlRendEnc = cmdEncoder->_mtlRenderEncoder;
    [mtlRendEnc pushDebugGroup: @"vkCmdClearAttachments"];
    [mtlRendEnc setRenderPipelineState: cmdEncPool->getCmdClearMTLRenderPipelineState(_rpsKey)];
    [mtlRendEnc setDepthStencilState: cmdEncPool->getMTLDepthStencilState(isClearingDepth, isClearingStencil)];
    [mtlRendEnc setStencilReferenceValue: _mtlStencilValue];

    cmdEncoder->setVertexBytes(mtlRendEnc, _clearColors, sizeof(_clearColors), 0);
    cmdEncoder->setFragmentBytes(mtlRendEnc, _clearColors, sizeof(_clearColors), 0);
    cmdEncoder->setVertexBytes(mtlRendEnc, _vertices.data(), vtxCnt * sizeof(_vertices[0]), vtxBuffIdx);
    [mtlRendEnc drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: vtxCnt];
    [mtlRendEnc popDebugGroup];

	// Return to the previous rendering state on the next render activity
	cmdEncoder->_graphicsPipelineState.markDirty();
	cmdEncoder->_depthStencilState.markDirty();
	cmdEncoder->_stencilReferenceValueState.markDirty();
	cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
}


#pragma mark -
#pragma mark MVKCmdClearImage

MVKFuncionOverride_getTypePool(ClearImage)

VkResult MVKCmdClearImage::setContent(MVKCommandBuffer* cmdBuff,
									  VkImage image,
									  VkImageLayout imageLayout,
									  const VkClearValue& clearValue,
									  uint32_t rangeCount,
									  const VkImageSubresourceRange* pRanges,
									  bool isDepthStencilClear) {
    _image = (MVKImage*)image;
    _imgLayout = imageLayout;
    _isDepthStencilClear = isDepthStencilClear;

	MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();
	_mtlColorClearValue = pixFmts->getMTLClearColorFromVkClearValue(clearValue, _image->getVkFormat());
	_mtlDepthClearValue = pixFmts->getMTLClearDepthFromVkClearValue(clearValue);
	_mtlStencilClearValue = pixFmts->getMTLClearStencilFromVkClearValue(clearValue);

    // Add subresource ranges
    _subresourceRanges.clear();		// Clear for reuse
    _subresourceRanges.reserve(rangeCount);
    for (uint32_t i = 0; i < rangeCount; i++) {
        _subresourceRanges.push_back(pRanges[i]);
    }

	// Validate
	if (_image->getImageType() == VK_IMAGE_TYPE_1D) {
		return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdClearImage(): Native 1D images cannot be cleared on this device. Consider enabling MVK_CONFIG_TEXTURE_1D_AS_2D.");
	}
	MVKMTLFmtCaps mtlFmtCaps = pixFmts->getMTLPixelFormatCapabilities(_image->getMTLPixelFormat());
	if ((_isDepthStencilClear && !mvkAreAllFlagsEnabled(mtlFmtCaps, kMVKMTLFmtCapsDSAtt)) ||
		( !_isDepthStencilClear && !mvkAreAllFlagsEnabled(mtlFmtCaps, kMVKMTLFmtCapsColorAtt))) {
		return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdClearImage(): Format %s cannot be cleared on this device.", pixFmts->getVkFormatName(_image->getVkFormat()));
	}

	return VK_SUCCESS;
}

void MVKCmdClearImage::encode(MVKCommandEncoder* cmdEncoder) {
	id<MTLTexture> imgMTLTex = _image->getMTLTexture();
    if ( !imgMTLTex ) { return; }

	NSString* mtlRendEncName = (_isDepthStencilClear
								? mvkMTLRenderCommandEncoderLabel(kMVKCommandUseClearDepthStencilImage)
								: mvkMTLRenderCommandEncoderLabel(kMVKCommandUseClearColorImage));

	cmdEncoder->endCurrentMetalEncoding();

	for (auto& srRange : _subresourceRanges) {

		MTLRenderPassDescriptor* mtlRPDesc = [MTLRenderPassDescriptor renderPassDescriptor];
		MTLRenderPassColorAttachmentDescriptor* mtlRPCADesc = nil;
		MTLRenderPassDepthAttachmentDescriptor* mtlRPDADesc = nil;
		MTLRenderPassStencilAttachmentDescriptor* mtlRPSADesc = nil;

		bool isClearingColor = !_isDepthStencilClear && mvkIsAnyFlagEnabled(srRange.aspectMask, VK_IMAGE_ASPECT_COLOR_BIT);
        bool isClearingDepth = _isDepthStencilClear && mvkIsAnyFlagEnabled(srRange.aspectMask, VK_IMAGE_ASPECT_DEPTH_BIT);
        bool isClearingStencil = _isDepthStencilClear && mvkIsAnyFlagEnabled(srRange.aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT);

		if (isClearingColor) {
			mtlRPCADesc = mtlRPDesc.colorAttachments[0];
			mtlRPCADesc.texture = imgMTLTex;
			mtlRPCADesc.loadAction = MTLLoadActionClear;
			mtlRPCADesc.storeAction = MTLStoreActionStore;
			mtlRPCADesc.clearColor = _mtlColorClearValue;
		}

		if (isClearingDepth) {
			mtlRPDADesc = mtlRPDesc.depthAttachment;
			mtlRPDADesc.texture = imgMTLTex;
			mtlRPDADesc.loadAction = MTLLoadActionClear;
			mtlRPDADesc.storeAction = MTLStoreActionStore;
			mtlRPDADesc.clearDepth = _mtlDepthClearValue;
		}

		if (isClearingStencil) {
			mtlRPSADesc = mtlRPDesc.stencilAttachment;
			mtlRPSADesc.texture = imgMTLTex;
			mtlRPSADesc.loadAction = MTLLoadActionClear;
			mtlRPSADesc.storeAction = MTLStoreActionStore;
			mtlRPSADesc.clearStencil = _mtlStencilClearValue;
		}

        // Extract the mipmap levels that are to be updated
        uint32_t mipLvlStart = srRange.baseMipLevel;
        uint32_t mipLvlCnt = srRange.levelCount;
        uint32_t mipLvlEnd = (mipLvlCnt == VK_REMAINING_MIP_LEVELS
                              ? _image->getMipLevelCount()
                              : (mipLvlStart + mipLvlCnt));

        // Extract the cube or array layers (slices) that are to be updated
        uint32_t layerStart = srRange.baseArrayLayer;
        uint32_t layerCnt = srRange.layerCount;
        uint32_t layerEnd = (layerCnt == VK_REMAINING_ARRAY_LAYERS
                             ? _image->getLayerCount()
                             : (layerStart + layerCnt));

        // Iterate across mipmap levels and layers, and perform and empty render to clear each
        for (uint32_t mipLvl = mipLvlStart; mipLvl < mipLvlEnd; mipLvl++) {
			mtlRPCADesc.level = mipLvl;
			mtlRPDADesc.level = mipLvl;
			mtlRPSADesc.level = mipLvl;

            for (uint32_t layer = layerStart; layer < layerEnd; layer++) {
                mtlRPCADesc.slice = layer;
				mtlRPDADesc.slice = layer;
				mtlRPSADesc.slice = layer;

                id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];
				setLabelIfNotNil(mtlRendEnc, mtlRendEncName);
                [mtlRendEnc endEncoding];
            }
        }
    }
}


#pragma mark -
#pragma mark MVKCmdFillBuffer

MVKFuncionOverride_getTypePool(FillBuffer)

VkResult MVKCmdFillBuffer::setContent(MVKCommandBuffer* cmdBuff,
									  VkBuffer dstBuffer,
									  VkDeviceSize dstOffset,
									  VkDeviceSize size,
									  uint32_t data) {
    _dstBuffer = (MVKBuffer*)dstBuffer;
    _dstOffset = dstOffset;
    _dataValue = data;

	// Round up in case of VK_WHOLE_SIZE on a buffer size which is not aligned to 4 bytes.
	VkDeviceSize byteCnt = (size == VK_WHOLE_SIZE) ? (_dstBuffer->getByteCount() - _dstOffset) : size;
	VkDeviceSize wdCnt = (byteCnt + 3) >> 2;
	if (mvkFits<uint32_t>(wdCnt)) {
		_wordCount = (uint32_t)wdCnt;
	} else {
		_wordCount = std::numeric_limits<uint32_t>::max();
		return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdFillBuffer(): Buffer fill size must fit into a 32-bit unsigned integer. Fill size %llu is too large.", wdCnt);
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

MVKFuncionOverride_getTypePool(UpdateBuffer)

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

