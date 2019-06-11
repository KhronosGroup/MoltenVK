/*
 * MVKCmdTransfer.mm
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


#pragma mark -
#pragma mark MVKCmdCopyImage

void MVKCmdCopyImage::setContent(VkImage srcImage,
								 VkImageLayout srcImageLayout,
								 VkImage dstImage,
								 VkImageLayout dstImageLayout,
								 uint32_t regionCount,
                                 const VkImageCopy* pRegions,
                                 MVKCommandUse commandUse) {
	_srcImage = (MVKImage*)srcImage;
	_srcLayout = srcImageLayout;
	_dstImage = (MVKImage*)dstImage;
	_dstLayout = dstImageLayout;
    _commandUse = commandUse;

    // Deterine the total number of texture layers being affected
    uint32_t layerCnt = 0;
    for (uint32_t i = 0; i < regionCount; i++) {
        layerCnt += pRegions[i].srcSubresource.layerCount;
    }

	// Add image regions
    _mtlTexCopyRegions.clear();     // Clear for reuse
    _mtlTexCopyRegions.reserve(layerCnt);
	for (uint32_t i = 0; i < regionCount; i++) {
		addMetalCopyRegions(&pRegions[i]);
	}

    // Validate
    if ((_srcImage->getMTLTextureType() == MTLTextureType3D) != (_dstImage->getMTLTextureType() == MTLTextureType3D)) {
        setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdCopyImage(): Metal does not support copying to or from slices of a 3D texture."));
    }
}

// Adds a Metal copy region structure for each layer in the specified copy region.
void MVKCmdCopyImage::addMetalCopyRegions(const VkImageCopy* pRegion) {

    MVKMetalCopyTextureRegion mtlImgRgn;
    mtlImgRgn.srcOrigin = mvkMTLOriginFromVkOffset3D(pRegion->srcOffset);
    mtlImgRgn.dstOrigin = mvkMTLOriginFromVkOffset3D(pRegion->dstOffset);
    mtlImgRgn.srcSize = mvkMTLSizeFromVkExtent3D(pRegion->extent);
    mtlImgRgn.srcLevel = pRegion->srcSubresource.mipLevel;
    mtlImgRgn.dstLevel = pRegion->dstSubresource.mipLevel;

    uint32_t srcBaseLayer = pRegion->srcSubresource.baseArrayLayer;
    uint32_t dstBaseLayer = pRegion->dstSubresource.baseArrayLayer;
    uint32_t layCnt = pRegion->srcSubresource.layerCount;

    for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
		mtlImgRgn.srcSlice = srcBaseLayer + layIdx;
		mtlImgRgn.dstSlice = dstBaseLayer + layIdx;
        _mtlTexCopyRegions.push_back(mtlImgRgn);
	}
}

void MVKCmdCopyImage::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLTexture> srcMTLTex = _srcImage->getMTLTexture();
    id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture();
    if ( !srcMTLTex || !dstMTLTex ) { return; }

    if (srcMTLTex.pixelFormat != dstMTLTex.pixelFormat &&
        mvkFormatTypeFromVkFormat(_dstImage->getVkFormat()) != kMVKFormatCompressed &&
        mvkFormatTypeFromVkFormat(_srcImage->getVkFormat()) != kMVKFormatCompressed) {
        // If the pixel formats don't match, Metal won't abort, but it won't
        // do the copy either. But we can easily work around that... unless the
        // source format is compressed.
        srcMTLTex = [[srcMTLTex newTextureViewWithPixelFormat: dstMTLTex.pixelFormat] autorelease];
    }

    id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(_commandUse);

    for (auto& cpyRgn : _mtlTexCopyRegions) {
        [mtlBlitEnc copyFromTexture: srcMTLTex
                        sourceSlice: cpyRgn.srcSlice
                        sourceLevel: cpyRgn.srcLevel
                       sourceOrigin: cpyRgn.srcOrigin
                         sourceSize: cpyRgn.srcSize
                          toTexture: dstMTLTex
                   destinationSlice: cpyRgn.dstSlice
                   destinationLevel: cpyRgn.dstLevel
                  destinationOrigin: cpyRgn.dstOrigin];
    }
}


#pragma mark -
#pragma mark MVKCmdBlitImage

void MVKCmdBlitImage::setContent(VkImage srcImage,
								 VkImageLayout srcImageLayout,
								 VkImage dstImage,
								 VkImageLayout dstImageLayout,
								 uint32_t regionCount,
								 const VkImageBlit* pRegions,
                                 VkFilter filter,
                                 MVKCommandUse commandUse) {
	_srcImage = (MVKImage*)srcImage;
	_srcLayout = srcImageLayout;
	_dstImage = (MVKImage*)dstImage;
	_dstLayout = dstImageLayout;

    _mtlPixFmt = _dstImage->getMTLPixelFormat();
    _mtlFilter = mvkMTLSamplerMinMagFilterFromVkFilter(filter);

	_blitKey.mtlPixFmt = (uint32_t)_mtlPixFmt;
	_blitKey.mtlTexType = (uint32_t)_srcImage->getMTLTextureType();

    _commandUse = commandUse;

	// Determine which regions can be copied and which must be rendered to the destination texture
	bool canCopyRegion[regionCount];
	uint32_t copyRegionCount = 0;
	uint32_t renderRegionCount = 0;
	for (uint32_t i = 0; i < regionCount; i++) {
		const VkImageBlit* pRegion = &pRegions[i];
		uint32_t layCnt = pRegion->srcSubresource.layerCount;
		if ( canCopy(pRegion) && (_srcImage->getMTLPixelFormat() == _mtlPixFmt) ) {
			canCopyRegion[i] = true;
			copyRegionCount += layCnt;
		} else {
			canCopyRegion[i] = false;
			renderRegionCount += layCnt;
		}
	}

	// Add copy and BLIT regions accordingly
    _mtlTexCopyRegions.clear();     // Clear for reuse
	_mtlTexCopyRegions.reserve(copyRegionCount);
    _mtlTexBlitRenders.clear();     // Clear for reuse
	_mtlTexBlitRenders.reserve(renderRegionCount);

	for (uint32_t i = 0; i < regionCount; i++) {
		const VkImageBlit* pRegion = &pRegions[i];
		if (canCopyRegion[i]) {
			addMetalCopyRegions(pRegion);
		} else {
			addMetalBlitRenders(pRegion);
		}
	}

    // Validate
    if (_blitKey.isDepthFormat() && renderRegionCount > 0) {
        setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdBlitImage(): Scaling of depth/stencil images is not supported."));
    }
    if ( !_mtlTexBlitRenders.empty() && mvkMTLPixelFormatIsStencilFormat(_mtlPixFmt)) {
        setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdBlitImage(): Stencil image formats cannot be scaled or inverted."));
    }
}

bool MVKCmdBlitImage::canCopy(const VkImageBlit* pRegion) {
	VkOffset3D srcSize = mvkVkOffset3DDifference(pRegion->srcOffsets[1], pRegion->srcOffsets[0]);
	VkOffset3D dstSize = mvkVkOffset3DDifference(pRegion->dstOffsets[1], pRegion->dstOffsets[0]);

	// The source and destination sizes must be equal and not be negative in any direction
	return (mvkVkOffset3DsAreEqual(srcSize, dstSize) &&
			(srcSize.x >= 0) && (srcSize.y >= 0) && (srcSize.z >= 0));
}

// Adds a Metal copy region structure for each layer in the specified BLIT region.
void MVKCmdBlitImage::addMetalCopyRegions(const VkImageBlit* pRegion) {

    const VkOffset3D* pSo0 = &pRegion->srcOffsets[0];
    const VkOffset3D* pSo1 = &pRegion->srcOffsets[1];

    MVKMetalCopyTextureRegion mtlImgRgn;
    mtlImgRgn.srcOrigin = mvkMTLOriginFromVkOffset3D(*pSo0);
    mtlImgRgn.dstOrigin = mvkMTLOriginFromVkOffset3D(pRegion->dstOffsets[0]);
    mtlImgRgn.srcSize = MTLSizeMake((pSo1->x - pSo0->x), (pSo1->y - pSo0->y), (pSo1->z - pSo0->z));
    mtlImgRgn.srcLevel = pRegion->srcSubresource.mipLevel;
    mtlImgRgn.dstLevel = pRegion->dstSubresource.mipLevel;

    uint32_t srcBaseLayer = pRegion->srcSubresource.baseArrayLayer;
    uint32_t dstBaseLayer = pRegion->dstSubresource.baseArrayLayer;
	uint32_t layCnt = pRegion->srcSubresource.layerCount;

    for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
		mtlImgRgn.srcSlice = srcBaseLayer + layIdx;
		mtlImgRgn.dstSlice = dstBaseLayer + layIdx;
        _mtlTexCopyRegions.push_back(mtlImgRgn);
	}
}

// Adds a Metal BLIT render region structure for each layer in the specified BLIT region.
void MVKCmdBlitImage::addMetalBlitRenders(const VkImageBlit* pRegion) {

    MVKMetalBlitTextureRender mtlBlitRndr;
    mtlBlitRndr.srcLevel = pRegion->srcSubresource.mipLevel;
    mtlBlitRndr.dstLevel = pRegion->dstSubresource.mipLevel;
    populateVertices(mtlBlitRndr.vertices, pRegion);

    uint32_t srcBaseLayer = pRegion->srcSubresource.baseArrayLayer;
	uint32_t dstBaseLayer = pRegion->dstSubresource.baseArrayLayer;
	uint32_t layCnt = pRegion->srcSubresource.layerCount;

	for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
		mtlBlitRndr.srcSlice = srcBaseLayer + layIdx;
		mtlBlitRndr.dstSlice = dstBaseLayer + layIdx;
        _mtlTexBlitRenders.push_back(mtlBlitRndr);
	}
}

// Populates the vertices in the specified array from the specified region.
void MVKCmdBlitImage::populateVertices(MVKVertexPosTex* vertices, const VkImageBlit* pRegion) {
    const VkOffset3D* pSo0 = &pRegion->srcOffsets[0];
    const VkOffset3D* pSo1 = &pRegion->srcOffsets[1];
    const VkOffset3D* pDo0 = &pRegion->dstOffsets[0];
    const VkOffset3D* pDo1 = &pRegion->dstOffsets[1];

    // Get the extents of the source and destination textures.
    VkExtent3D srcExtent = _srcImage->getExtent3D(pRegion->srcSubresource.mipLevel);
    VkExtent3D dstExtent = _dstImage->getExtent3D(pRegion->dstSubresource.mipLevel);

    // Determine the bottom-left and top-right corners of the source and destination
    // texture regions, each as a fraction of the corresponding texture size.
    CGPoint srcBL = CGPointMake((CGFloat)(pSo0->x) / (CGFloat)srcExtent.width,
                                (CGFloat)(srcExtent.height - pSo1->y) / (CGFloat)srcExtent.height);
    CGPoint srcTR = CGPointMake((CGFloat)(pSo1->x) / (CGFloat)srcExtent.width,
                                (CGFloat)(srcExtent.height - pSo0->y) / (CGFloat)srcExtent.height);
    CGPoint dstBL = CGPointMake((CGFloat)(pDo0->x) / (CGFloat)dstExtent.width,
                                (CGFloat)(dstExtent.height - pDo1->y) / (CGFloat)dstExtent.height);
    CGPoint dstTR = CGPointMake((CGFloat)(pDo1->x) / (CGFloat)dstExtent.width,
                                (CGFloat)(dstExtent.height - pDo0->y) / (CGFloat)dstExtent.height);

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
    if ( !_mtlTexCopyRegions.empty() ) {
        MVKCmdCopyImage::encode(cmdEncoder);
    }

    // Perform those BLITs that require rendering to destination texture.
    if ( !_mtlTexBlitRenders.empty() && !_blitKey.isDepthFormat() ) {

        cmdEncoder->endCurrentMetalEncoding();

        id<MTLTexture> srcMTLTex = _srcImage->getMTLTexture();
        id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture();
        if ( !srcMTLTex || !dstMTLTex ) { return; }

		bool isArrayType = _blitKey.isArrayType();

        MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = _mtlRenderPassDescriptor.colorAttachments[0];
        mtlColorAttDesc.texture = dstMTLTex;

        uint32_t vtxBuffIdx = getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex);

        MVKCommandEncodingPool* cmdEncPool = getCommandEncodingPool();

        for (auto& bltRend : _mtlTexBlitRenders) {

            // Update the render pass descriptor for the texture level and slice, and create a render encoder.
            mtlColorAttDesc.level = bltRend.dstLevel;
            mtlColorAttDesc.slice = bltRend.dstSlice;
            id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: _mtlRenderPassDescriptor];
			setLabelIfNotNil(mtlRendEnc, mvkMTLRenderCommandEncoderLabel(_commandUse));

            [mtlRendEnc pushDebugGroup: @"vkCmdBlitImage"];
            [mtlRendEnc setRenderPipelineState: cmdEncPool->getCmdBlitImageMTLRenderPipelineState(_blitKey)];
            cmdEncoder->setVertexBytes(mtlRendEnc, bltRend.vertices, sizeof(bltRend.vertices), vtxBuffIdx);
			[mtlRendEnc setFragmentTexture: srcMTLTex atIndex: 0];
			[mtlRendEnc setFragmentSamplerState: cmdEncPool->getCmdBlitImageMTLSamplerState(_mtlFilter) atIndex: 0];
			if (isArrayType) {
				cmdEncoder->setFragmentBytes(mtlRendEnc, &bltRend, sizeof(bltRend), 0);
			}
            [mtlRendEnc drawPrimitives: MTLPrimitiveTypeTriangleStrip vertexStart: 0 vertexCount: kMVKBlitVertexCount];
            [mtlRendEnc popDebugGroup];
            [mtlRendEnc endEncoding];
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

void MVKCmdResolveImage::setContent(VkImage srcImage,
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

    _srcImage->getTransferDescriptorData(_transferImageData);
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
    MVKImage* xfrImage = getCommandEncodingPool()->getTransferMVKImage(_transferImageData);

    id<MTLTexture> xfrMTLTex = xfrImage->getMTLTexture();
    id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture();
    if ( !xfrMTLTex || !dstMTLTex ) { return; }

    // Expand the current content of the destination image to the temporary transfer image.
    // Create and execute a temporary BLIT image command.
    // To be threadsafe...do NOT acquire and return the command from the pool.
    uint32_t expRgnCnt = uint32_t(_expansionRegions.size());
    if (expRgnCnt > 0) {
        MVKCmdBlitImage expandCmd(&getCommandPool()->_cmdBlitImagePool);
        expandCmd.setContent((VkImage)_dstImage, _dstLayout, (VkImage)xfrImage, _dstLayout,
                             uint32_t(_expansionRegions.size()), _expansionRegions.data(),
                             VK_FILTER_LINEAR, kMVKCommandUseResolveExpandImage);
        expandCmd.encode(cmdEncoder);
    }

    // Copy the resolve regions of the source image to the temporary transfer image.
    // Create and execute a temporary copy image command.
    // To be threadsafe...do NOT acquire and return the command from the pool.
    uint32_t cpyRgnCnt = uint32_t(_copyRegions.size());
    if (cpyRgnCnt > 0) {
        MVKCmdCopyImage copyCmd(&getCommandPool()->_cmdCopyImagePool);
        copyCmd.setContent((VkImage)_srcImage, _srcLayout, (VkImage)xfrImage, _dstLayout,
                           uint32_t(_copyRegions.size()), _copyRegions.data(), kMVKCommandUseResolveCopyImage);
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

// Matches shader struct.
typedef struct {
	uint32_t srcOffset;
	uint32_t dstOffset;
	uint32_t size;
} MVKCmdCopyBufferInfo;

void MVKCmdCopyBuffer::setContent(VkBuffer srcBuffer,
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
}

void MVKCmdCopyBuffer::encode(MVKCommandEncoder* cmdEncoder) {
	id<MTLBuffer> srcMTLBuff = _srcBuffer->getMTLBuffer();
	NSUInteger srcMTLBuffOffset = _srcBuffer->getMTLBufferOffset();

	id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
	NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset();

	VkDeviceSize buffAlign = getDevice()->_pMetalFeatures->mtlCopyBufferAlignment;

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
			[mtlComputeEnc setComputePipelineState: getCommandEncodingPool()->getCmdCopyBufferBytesMTLComputePipelineState()];
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

void MVKCmdBufferImageCopy::setContent(VkBuffer buffer,
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
    _mtlBuffImgCopyRegions.clear();     // Clear for reuse
    _mtlBuffImgCopyRegions.reserve(regionCount);
    for (uint32_t i = 0; i < regionCount; i++) {
        _mtlBuffImgCopyRegions.push_back(pRegions[i]);
    }

    // Validate
    if ( !_image->hasExpectedTexelSize() ) {
        const char* cmdName = _toImage ? "vkCmdCopyBufferToImage" : "vkCmdCopyImageToBuffer";
        setConfigurationResult(reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "%s(): The image is using Metal format %s as a substitute for Vulkan format %s. Since the pixel size is different, content for the image cannot be copied to or from a buffer.", cmdName, mvkMTLPixelFormatName(_image->getMTLPixelFormat()), mvkVkFormatName(_image->getVkFormat())));
    }
}

void MVKCmdBufferImageCopy::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLBuffer> mtlBuffer = _buffer->getMTLBuffer();
    id<MTLTexture> mtlTexture = _image->getMTLTexture();
    if ( !mtlBuffer || !mtlTexture ) { return; }

	NSUInteger mtlBuffOffsetBase = _buffer->getMTLBufferOffset();
    MTLPixelFormat mtlPixFmt = _image->getMTLPixelFormat();
    MVKCommandUse cmdUse = _toImage ? kMVKCommandUseCopyBufferToImage : kMVKCommandUseCopyImageToBuffer;

    for (auto& cpyRgn : _mtlBuffImgCopyRegions) {

        MTLOrigin mtlTxtOrigin = mvkMTLOriginFromVkOffset3D(cpyRgn.imageOffset);
        MTLSize mtlTxtSize = mvkMTLSizeFromVkExtent3D(cpyRgn.imageExtent);
		NSUInteger mtlBuffOffset = mtlBuffOffsetBase + cpyRgn.bufferOffset;

        uint32_t buffImgWd = cpyRgn.bufferRowLength;
        if (buffImgWd == 0) { buffImgWd = cpyRgn.imageExtent.width; }

        uint32_t buffImgHt = cpyRgn.bufferImageHeight;
        if (buffImgHt == 0) { buffImgHt = cpyRgn.imageExtent.height; }

        NSUInteger bytesPerRow = mvkMTLPixelFormatBytesPerRow(mtlPixFmt, buffImgWd);
        NSUInteger bytesPerImg = mvkMTLPixelFormatBytesPerLayer(mtlPixFmt, bytesPerRow, buffImgHt);

        // If the format combines BOTH depth and stencil, determine whether one or both
        // components are to be copied, and adjust the byte counts and copy options accordingly.
        MTLBlitOption blitOptions = MTLBlitOptionNone;
        if (mvkMTLPixelFormatIsDepthFormat(mtlPixFmt) && mvkMTLPixelFormatIsStencilFormat(mtlPixFmt)) {
            VkImageAspectFlags imgFlags = cpyRgn.imageSubresource.aspectMask;
            bool wantDepth = mvkAreFlagsEnabled(imgFlags, VK_IMAGE_ASPECT_DEPTH_BIT);
            bool wantStencil = mvkAreFlagsEnabled(imgFlags, VK_IMAGE_ASPECT_STENCIL_BIT);

            // The stencil component is always 1 byte per pixel.
			// Don't reduce depths of 32-bit depth/stencil formats.
            if (wantDepth && !wantStencil) {
				if (mvkMTLPixelFormatBytesPerTexel(mtlPixFmt) != 4) {
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
		if (mvkMTLPixelFormatIsPVRTCFormat(mtlPixFmt)) {
			blitOptions |= MTLBlitOptionRowLinearPVRTC;
		}
#endif

#if MVK_MACOS
        if (_toImage && mvkFormatTypeFromMTLPixelFormat(mtlPixFmt) == kMVKFormatCompressed &&
            mtlTexture.textureType == MTLTextureType3D) {
            // If we're copying to a compressed 3D image, the image data need to be decompressed.
            // If we're copying to mip level 0, we can skip the copy and just decode
            // directly into the image. Otherwise, we need to use an intermediate
            // buffer.
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
            bool needsTempBuff = cpyRgn.imageSubresource.mipLevel != 0;
            id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(cmdUse);
            id<MTLComputePipelineState> mtlComputeState = getCommandEncodingPool()->getCmdCopyBufferToImage3DDecompressMTLComputePipelineState(needsTempBuff);
            [mtlComputeEnc pushDebugGroup: @"vkCmdCopyBufferToImage"];
            [mtlComputeEnc setComputePipelineState: mtlComputeState];
            [mtlComputeEnc setBuffer: mtlBuffer offset: mtlBuffOffset atIndex: 0];
            MVKBuffer* tempBuff;
            if (needsTempBuff) {
                NSUInteger bytesPerDestRow = mvkMTLPixelFormatBytesPerRow(mtlTexture.pixelFormat, info.extent.width);
                NSUInteger bytesPerDestImg = mvkMTLPixelFormatBytesPerLayer(mtlTexture.pixelFormat, bytesPerDestRow, info.extent.height);
                // We're going to copy from the temporary buffer now, so use the
                // temp buffer parameters in the copy below.
                bytesPerRow = bytesPerDestRow;
                bytesPerImg = bytesPerDestImg;
                MVKBufferDescriptorData tempBuffData;
                tempBuffData.size = bytesPerDestImg * mtlTxtSize.depth;
                tempBuffData.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
                tempBuff = getCommandEncodingPool()->getTransferMVKBuffer(tempBuffData);
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
            VkExtent2D blockExtent = mvkMTLPixelFormatBlockTexelSize(mtlPixFmt);
            MTLSize mtlGridSize = MTLSizeMake(mvkCeilingDivide(mtlTxtSize.width, blockExtent.width),
                                              mvkCeilingDivide(mtlTxtSize.height, blockExtent.height),
                                              mtlTxtSize.depth);
            // Use four times the thread execution width as the threadgroup size.
            MTLSize mtlTgrpSize = MTLSizeMake(2, 2, mtlComputeState.threadExecutionWidth);
            // Then the number of threadgroups is (ceil(x/2), ceil(y/2), ceil(z/t)),
            // where 't' is the thread execution width.
            mtlGridSize.width = mvkCeilingDivide(mtlGridSize.width, 2);
            mtlGridSize.height = mvkCeilingDivide(mtlGridSize.height, 2);
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
                          destinationLevel: cpyRgn.imageSubresource.mipLevel
                         destinationOrigin: mtlTxtOrigin
                                   options: blitOptions];
            } else {
                [mtlBlitEnc copyFromTexture: mtlTexture
                                sourceSlice: (cpyRgn.imageSubresource.baseArrayLayer + lyrIdx)
                                sourceLevel: cpyRgn.imageSubresource.mipLevel
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


#pragma mark -
#pragma mark MVKCmdClearAttachments

void MVKCmdClearAttachments::setContent(uint32_t attachmentCount,
                                        const VkClearAttachment* pAttachments,
                                        uint32_t rectCount,
                                        const VkClearRect* pRects) {
	_rpsKey.reset();
    _mtlStencilValue = 0;
    _isClearingDepth = false;
    _isClearingStencil = false;
    float mtlDepthVal = 0.0;

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
            mtlDepthVal = mvkMTLClearDepthFromVkClearValue(clrAtt.clearValue);
        }

        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT)) {
            _isClearingStencil = true;
            _rpsKey.enableAttachment(kMVKClearAttachmentDepthStencilIndex);
            _mtlStencilValue = mvkMTLClearStencilFromVkClearValue(clrAtt.clearValue);
        }
    }

    // The depth value (including vertex position Z value) is held in the last index.
    _clearColors[kMVKClearAttachmentDepthStencilIndex] = { mtlDepthVal, mtlDepthVal, mtlDepthVal, mtlDepthVal };

    _clearRects.clear();
    _clearRects.reserve(rectCount);
    for (uint32_t i = 0; i < rectCount; i++) {
        _clearRects.push_back(pRects[i]);
    }

    _vertices.reserve(rectCount * 6);
}

/** Populates the vertices for all clear rectangles within an attachment of the specified size. */
void MVKCmdClearAttachments::populateVertices(float attWidth, float attHeight) {
    _vertices.clear();
    for (auto& rect : _clearRects) { populateVertices(rect, attWidth, attHeight); }
}

/** Populates the vertices from the specified rectangle within an attachment of the specified size. */
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

    MVKCommandPool* cmdPool = getCommandPool();
    MVKRenderSubpass* subpass = cmdEncoder->getSubpass();
    VkExtent2D fbExtent = cmdEncoder->_framebuffer->getExtent2D();
    populateVertices(fbExtent.width, fbExtent.height);
    uint32_t vtxCnt = (uint32_t)_vertices.size();
    uint32_t vtxBuffIdx = getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex);

    // Populate the render pipeline state attachment key with info from the subpass and framebuffer.
	_rpsKey.mtlSampleCount = mvkSampleCountFromVkSampleCountFlagBits(subpass->getSampleCount());
	if (cmdEncoder->_isUsingLayeredRendering) { _rpsKey.enableLayeredRendering(); }

    uint32_t caCnt = subpass->getColorAttachmentCount();
    for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
        VkFormat vkAttFmt = subpass->getColorAttachmentFormat(caIdx);
		_rpsKey.attachmentMTLPixelFormats[caIdx] = cmdPool->getMTLPixelFormatFromVkFormat(vkAttFmt);
		MTLClearColor mtlCC = mvkMTLClearColorFromVkClearValue(_vkClearValues[caIdx], vkAttFmt);
		_clearColors[caIdx] = { (float)mtlCC.red, (float)mtlCC.green, (float)mtlCC.blue, (float)mtlCC.alpha};
    }

    VkFormat vkAttFmt = subpass->getDepthStencilFormat();
	MTLPixelFormat mtlAttFmt = cmdPool->getMTLPixelFormatFromVkFormat(vkAttFmt);
    _rpsKey.attachmentMTLPixelFormats[kMVKClearAttachmentDepthStencilIndex] = mtlAttFmt;
	bool isClearingDepth = _isClearingDepth && mvkMTLPixelFormatIsDepthFormat(mtlAttFmt);
	bool isClearingStencil = _isClearingStencil && mvkMTLPixelFormatIsStencilFormat(mtlAttFmt);

    // Render the clear colors to the attachments
    id<MTLRenderCommandEncoder> mtlRendEnc = cmdEncoder->_mtlRenderEncoder;
    [mtlRendEnc pushDebugGroup: @"vkCmdClearAttachments"];
    [mtlRendEnc setRenderPipelineState: getCommandEncodingPool()->getCmdClearMTLRenderPipelineState(_rpsKey)];
    [mtlRendEnc setDepthStencilState: getCommandEncodingPool()->getMTLDepthStencilState(isClearingDepth, isClearingStencil)];
    [mtlRendEnc setStencilReferenceValue: _mtlStencilValue];

    cmdEncoder->setVertexBytes(mtlRendEnc, _clearColors, sizeof(_clearColors), 0);
    cmdEncoder->setFragmentBytes(mtlRendEnc, _clearColors, sizeof(_clearColors), 0);
    cmdEncoder->setVertexBytes(mtlRendEnc, _vertices.data(), vtxCnt * sizeof(_vertices[0]), vtxBuffIdx);
    [mtlRendEnc drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: vtxCnt];
    [mtlRendEnc popDebugGroup];

	cmdEncoder->_stencilReferenceValueState.markDirty();
}


#pragma mark -
#pragma mark MVKCmdClearImage

void MVKCmdClearImage::setContent(VkImage image,
                                  VkImageLayout imageLayout,
                                  const VkClearValue& clearValue,
                                  uint32_t rangeCount,
                                  const VkImageSubresourceRange* pRanges,
                                  bool isDepthStencilClear) {
    _image = (MVKImage*)image;
    _imgLayout = imageLayout;
    _isDepthStencilClear = isDepthStencilClear;

	_mtlColorClearValue = mvkMTLClearColorFromVkClearValue(clearValue, _image->getVkFormat());
	_mtlDepthClearValue = mvkMTLClearDepthFromVkClearValue(clearValue);
	_mtlStencilClearValue = mvkMTLClearStencilFromVkClearValue(clearValue);

    // Add subresource ranges
    _subresourceRanges.clear();
    _subresourceRanges.reserve(rangeCount);
    for (uint32_t i = 0; i < rangeCount; i++) {
        _subresourceRanges.push_back(pRanges[i]);
    }
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

// Matches shader struct
typedef struct {
	uint32_t size;
	uint32_t data;
} MVKCmdFillBufferInfo;

void MVKCmdFillBuffer::setContent(VkBuffer dstBuffer,
                                  VkDeviceSize dstOffset,
                                  VkDeviceSize size,
                                  uint32_t data) {
    _dstBuffer = (MVKBuffer*)dstBuffer;
    _dstOffset = dstOffset;
    _size = size;
    _dataValue = data;
}

void MVKCmdFillBuffer::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
    VkDeviceSize dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset();
    VkDeviceSize byteCnt = (_size == VK_WHOLE_SIZE) ? (_dstBuffer->getByteCount() - _dstOffset) : _size;

    // Round up in case of VK_WHOLE_SIZE on a buffer size which is not aligned to 4 bytes.
    VkDeviceSize wordCnt = (byteCnt + 3) >> 2;

	MVKAssert(mvkFits<uint32_t>(wordCnt),
			  "Buffer fill size must fit into a 32-bit unsigned integer.");

	MVKCmdFillBufferInfo fillInfo;
	fillInfo.size = (uint32_t)wordCnt;
	fillInfo.data = _dataValue;

	id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyBuffer);
	[mtlComputeEnc pushDebugGroup: @"vkCmdFillBuffer"];
	[mtlComputeEnc setComputePipelineState: getCommandEncodingPool()->getCmdFillBufferMTLComputePipelineState()];
	[mtlComputeEnc setBuffer: dstMTLBuff offset: dstMTLBuffOffset+_dstOffset atIndex: 0];
	[mtlComputeEnc setBytes: &fillInfo length: sizeof(fillInfo) atIndex: 1];
	[mtlComputeEnc dispatchThreadgroups: MTLSizeMake(1, 1, 1) threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
	[mtlComputeEnc popDebugGroup];
}


#pragma mark -
#pragma mark MVKCmdUpdateBuffer

void MVKCmdUpdateBuffer::setContent(VkBuffer dstBuffer,
                                    VkDeviceSize dstOffset,
                                    VkDeviceSize dataSize,
                                    const void* pData,
                                    bool useDataCache) {
    _dstBuffer = (MVKBuffer*)dstBuffer;
    _dstOffset = dstOffset;
    _dataSize = dataSize;

    _srcDataCache.reserve(_dataSize);
    memcpy(_srcDataCache.data(), pData, _dataSize);
}

void MVKCmdUpdateBuffer::encode(MVKCommandEncoder* cmdEncoder) {

    id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseUpdateBuffer);

    id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
    NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset() + _dstOffset;

    // Copy data to the source MTLBuffer
    MVKMTLBufferAllocation* srcMTLBufferAlloc = (MVKMTLBufferAllocation*)getCommandEncodingPool()->acquireMTLBufferAllocation(_dataSize);
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


#pragma mark -
#pragma mark Command creation functions

void mvkCmdCopyImage(MVKCommandBuffer* cmdBuff,
					 VkImage srcImage,
					 VkImageLayout srcImageLayout,
					 VkImage dstImage,
					 VkImageLayout dstImageLayout,
					 uint32_t regionCount,
					 const VkImageCopy* pRegions) {
	MVKCmdCopyImage* cmd = cmdBuff->_commandPool->_cmdCopyImagePool.acquireObject();
	cmd->setContent(srcImage, srcImageLayout, dstImage, dstImageLayout, regionCount, pRegions);
	cmdBuff->addCommand(cmd);
}

void mvkCmdBlitImage(MVKCommandBuffer* cmdBuff,
					 VkImage srcImage,
					 VkImageLayout srcImageLayout,
					 VkImage dstImage,
					 VkImageLayout dstImageLayout,
					 uint32_t regionCount,
					 const VkImageBlit* pRegions,
					 VkFilter filter) {
	MVKCmdBlitImage* cmd = cmdBuff->_commandPool->_cmdBlitImagePool.acquireObject();
	cmd->setContent(srcImage, srcImageLayout, dstImage, dstImageLayout, regionCount, pRegions, filter);
	cmdBuff->addCommand(cmd);
}

void mvkCmdResolveImage(MVKCommandBuffer* cmdBuff,
                        VkImage srcImage,
                        VkImageLayout srcImageLayout,
                        VkImage dstImage,
                        VkImageLayout dstImageLayout,
                        uint32_t regionCount,
                        const VkImageResolve* pRegions) {
    MVKCmdResolveImage* cmd = cmdBuff->_commandPool->_cmdResolveImagePool.acquireObject();
    cmd->setContent(srcImage, srcImageLayout, dstImage, dstImageLayout, regionCount, pRegions);
    cmdBuff->addCommand(cmd);
}

void mvkCmdCopyBuffer(MVKCommandBuffer* cmdBuff,
					  VkBuffer srcBuffer,
					  VkBuffer dstBuffer,
					  uint32_t regionCount,
					  const VkBufferCopy* pRegions) {
	MVKCmdCopyBuffer* cmd = cmdBuff->_commandPool->_cmdCopyBufferPool.acquireObject();
	cmd->setContent(srcBuffer, dstBuffer, regionCount, pRegions);
	cmdBuff->addCommand(cmd);
}

void mvkCmdCopyBufferToImage(MVKCommandBuffer* cmdBuff,
                             VkBuffer srcBuffer,
                             VkImage dstImage,
                             VkImageLayout dstImageLayout,
                             uint32_t regionCount,
                             const VkBufferImageCopy* pRegions) {
    MVKCmdBufferImageCopy* cmd = cmdBuff->_commandPool->_cmdBufferImageCopyPool.acquireObject();
    cmd->setContent(srcBuffer, dstImage, dstImageLayout, regionCount, pRegions, true);
    cmdBuff->addCommand(cmd);
}

void mvkCmdCopyImageToBuffer(MVKCommandBuffer* cmdBuff,
                             VkImage srcImage,
                             VkImageLayout srcImageLayout,
                             VkBuffer dstBuffer,
                             uint32_t regionCount,
                             const VkBufferImageCopy* pRegions) {
    MVKCmdBufferImageCopy* cmd = cmdBuff->_commandPool->_cmdBufferImageCopyPool.acquireObject();
    cmd->setContent(dstBuffer, srcImage, srcImageLayout, regionCount, pRegions, false);
    cmdBuff->addCommand(cmd);
}

void mvkCmdClearAttachments(MVKCommandBuffer* cmdBuff,
                            uint32_t attachmentCount,
                            const VkClearAttachment* pAttachments,
                            uint32_t rectCount,
                            const VkClearRect* pRects) {
    MVKCmdClearAttachments* cmd = cmdBuff->_commandPool->_cmdClearAttachmentsPool.acquireObject();
    cmd->setContent(attachmentCount, pAttachments, rectCount, pRects);
    cmdBuff->addCommand(cmd);
}

void mvkCmdClearColorImage(MVKCommandBuffer* cmdBuff,
						   VkImage image,
						   VkImageLayout imageLayout,
						   const VkClearColorValue* pColor,
						   uint32_t rangeCount,
						   const VkImageSubresourceRange* pRanges) {
    MVKCmdClearImage* cmd = cmdBuff->_commandPool->_cmdClearImagePool.acquireObject();
    VkClearValue clrVal;
    clrVal.color = *pColor;
    cmd->setContent(image, imageLayout, clrVal, rangeCount, pRanges, false);
    cmdBuff->addCommand(cmd);
}

void mvkCmdClearDepthStencilImage(MVKCommandBuffer* cmdBuff,
                                  VkImage image,
                                  VkImageLayout imageLayout,
                                  const VkClearDepthStencilValue* pDepthStencil,
                                  uint32_t rangeCount,
                                  const VkImageSubresourceRange* pRanges) {
    MVKCmdClearImage* cmd = cmdBuff->_commandPool->_cmdClearImagePool.acquireObject();
    VkClearValue clrVal;
    clrVal.depthStencil = *pDepthStencil;
    cmd->setContent(image, imageLayout, clrVal, rangeCount, pRanges, true);
    cmdBuff->addCommand(cmd);
}

void mvkCmdFillBuffer(MVKCommandBuffer* cmdBuff,
                      VkBuffer dstBuffer,
                      VkDeviceSize dstOffset,
                      VkDeviceSize size,
                      uint32_t data) {
    MVKCmdFillBuffer* cmd = cmdBuff->_commandPool->_cmdFillBufferPool.acquireObject();
    cmd->setContent(dstBuffer, dstOffset, size, data);
    cmdBuff->addCommand(cmd);
}

void mvkCmdUpdateBuffer(MVKCommandBuffer* cmdBuff,
                        VkBuffer dstBuffer,
                        VkDeviceSize dstOffset,
                        VkDeviceSize dataSize,
                        const void* pData) {
    MVKCmdUpdateBuffer* cmd = cmdBuff->_commandPool->_cmdUpdateBufferPool.acquireObject();
    cmd->setContent(dstBuffer, dstOffset, dataSize, pData, cmdBuff->getIsReusable());
    cmdBuff->addCommand(cmd);
}

