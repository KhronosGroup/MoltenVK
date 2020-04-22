/*
 * MVKCmdTransfer.h
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

#pragma once

#include "MVKCommand.h"
#include "MVKMTLBufferAllocation.h"
#include "MVKCommandResourceFactory.h"
#include "MVKFoundation.h"
#include "MVKVector.h"

#import <Metal/Metal.h>

class MVKImage;
class MVKBuffer;


#pragma mark -
#pragma mark MVKCmdCopyImage

/** Vulkan command to copy image regions. */
class MVKCmdCopyImage : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkImage srcImage,
						VkImageLayout srcImageLayout,
						VkImage dstImage,
						VkImageLayout dstImageLayout,
						uint32_t regionCount,
						const VkImageCopy* pRegions,
						MVKCommandUse commandUse = kMVKCommandUseCopyImage);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkImage srcImage,
						VkImageLayout srcImageLayout,
						VkImage dstImage,
						VkImageLayout dstImageLayout,
						bool formatsMustMatch,
						MVKCommandUse commandUse);
	void addImageCopyRegion(const VkImageCopy& region, MVKPixelFormats* pixFmts);
	void addTempBufferImageCopyRegion(const VkImageCopy& region, MVKPixelFormats* pixFmts);

	MVKImage* _srcImage;
	VkImageLayout _srcLayout;
	MVKImage* _dstImage;
	VkImageLayout _dstLayout;
	uint32_t _srcSampleCount;
	uint32_t _dstSampleCount;
	bool _isSrcCompressed;
	bool _isDstCompressed;
	bool _canCopyFormats;
	bool _useTempBuffer;
	MVKVectorInline<VkImageCopy, 4> _imageCopyRegions;
	MVKVectorInline<VkBufferImageCopy, 4> _srcTmpBuffImgCopies;
	MVKVectorInline<VkBufferImageCopy, 4> _dstTmpBuffImgCopies;
	size_t _tmpBuffSize;
    MVKCommandUse _commandUse;
};


#pragma mark -
#pragma mark MVKCmdBlitImage

/** Number of vertices in a BLIT rectangle. */
#define kMVKBlitVertexCount		4

/** Combines a VkImageBlit with vertices to render it. */
typedef struct {
	VkImageBlit region;
	MVKVertexPosTex vertices[kMVKBlitVertexCount];
} MVKImageBlitRender;

/** Vulkan command to BLIT image regions. */
class MVKCmdBlitImage : public MVKCmdCopyImage {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkImage srcImage,
						VkImageLayout srcImageLayout,
						VkImage dstImage,
						VkImageLayout dstImageLayout,
						uint32_t regionCount,
						const VkImageBlit* pRegions,
						VkFilter filter,
						MVKCommandUse commandUse = kMVKCommandUseBlitImage);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdBlitImage();

	~MVKCmdBlitImage() override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	bool canCopy(const VkImageBlit& region);
	void addImageBlitRegion(const VkImageBlit& region, MVKPixelFormats* pixFmts);
	void addImageCopyRegionFromBlitRegion(const VkImageBlit& region, MVKPixelFormats* pixFmts);
	void populateVertices(MVKVertexPosTex* vertices, const VkImageBlit& region);
    void initMTLRenderPassDescriptor();

	MTLRenderPassDescriptor* _mtlRenderPassDescriptor;
	MVKRPSKeyBlitImg _blitKey;
	MVKVectorInline<MVKImageBlitRender, 4> _mvkImageBlitRenders;
};


#pragma mark -
#pragma mark MVKCmdResolveImage

/** Describes Metal texture resolve parameters. */
typedef struct {
    uint32_t	level;
    uint32_t	slice;
} MVKMetalResolveSlice;

/** Vulkan command to resolve image regions. */
class MVKCmdResolveImage : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkImage srcImage,
						VkImageLayout srcImageLayout,
						VkImage dstImage,
						VkImageLayout dstImageLayout,
						uint32_t regionCount,
						const VkImageResolve* pRegions);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdResolveImage();

    ~MVKCmdResolveImage() override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	void addExpansionRegion(const VkImageResolve& resolveRegion);
    void addCopyRegion(const VkImageResolve& resolveRegion);
    void addResolveSlices(const VkImageResolve& resolveRegion);
    void initMTLRenderPassDescriptor();

    MVKImage* _srcImage;
    VkImageLayout _srcLayout;
    MVKImage* _dstImage;
    VkImageLayout _dstLayout;
    MVKImageDescriptorData _transferImageData;
    MTLRenderPassDescriptor* _mtlRenderPassDescriptor;
	MVKVectorInline<VkImageBlit, 4> _expansionRegions;
	MVKVectorInline<VkImageCopy, 4> _copyRegions;
	MVKVectorInline<MVKMetalResolveSlice, 4> _mtlResolveSlices;
};


#pragma mark -
#pragma mark MVKCmdCopyBuffer

/** Vulkan command to copy buffer regions. */
class MVKCmdCopyBuffer : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer srcBuffer,
						VkBuffer destBuffer,
						uint32_t regionCount,
						const VkBufferCopy* pRegions);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKBuffer* _srcBuffer;
	MVKBuffer* _dstBuffer;
	MVKVectorInline<VkBufferCopy, 4> _mtlBuffCopyRegions;
};


#pragma mark -
#pragma mark MVKCmdBufferImageCopy

/** Command to copy either from a buffer to an image, or from an image to a buffer. */
class MVKCmdBufferImageCopy : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkImage image,
						VkImageLayout imageLayout,
						uint32_t regionCount,
						const VkBufferImageCopy* pRegions,
						bool toImage);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	bool isArrayTexture();

    MVKBuffer* _buffer;
    MVKImage* _image;
    VkImageLayout _imageLayout;
	MVKVectorInline<VkBufferImageCopy, 4> _bufferImageCopyRegions;
    bool _toImage = false;
};


#pragma mark -
#pragma mark MVKCmdClearAttachments

/** Vulkan command to clear attachment regions. */
class MVKCmdClearAttachments : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t attachmentCount,
						const VkClearAttachment* pAttachments,
						uint32_t rectCount,
						const VkClearRect* pRects);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    void populateVertices(float attWidth, float attHeight);
    void populateVertices(VkClearRect& clearRect, float attWidth, float attHeight);

	MVKVectorInline<VkClearRect, 4> _clearRects;
	MVKVectorInline<simd::float4, (4 * 6)> _vertices;
    simd::float4 _clearColors[kMVKClearAttachmentCount];
    VkClearValue _vkClearValues[kMVKClearAttachmentCount];
    MVKRPSKeyClearAtt _rpsKey;
    uint32_t _mtlStencilValue;
    bool _isClearingDepth;
    bool _isClearingStencil;
};


#pragma mark -
#pragma mark MVKCmdClearImage

/** Vulkan command to clear an image. */
class MVKCmdClearImage : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkImage image,
						VkImageLayout imageLayout,
						const VkClearValue& clearValue,
						uint32_t rangeCount,
						const VkImageSubresourceRange* pRanges,
						bool isDepthStencilClear);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    uint32_t populateMetalCopyRegions(const VkImageBlit* pRegion, uint32_t cpyRgnIdx);
    uint32_t populateMetalBlitRenders(const VkImageBlit* pRegion, uint32_t rendRgnIdx);
    void populateVertices(MVKVertexPosTex* vertices, const VkImageBlit* pRegion);
    
    MVKImage* _image;
    VkImageLayout _imgLayout;
	MVKVectorInline<VkImageSubresourceRange, 4> _subresourceRanges;
	VkClearValue _clearValue;
    bool _isDepthStencilClear;
};


#pragma mark -
#pragma mark MVKCmdFillBuffer

/** Vulkan command to fill a buffer. */
class MVKCmdFillBuffer : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer dstBuffer,
						VkDeviceSize dstOffset,
						VkDeviceSize size,
						uint32_t data);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKBuffer* _dstBuffer;
    VkDeviceSize _dstOffset;
    uint32_t _wordCount;
    uint32_t _dataValue;
};


#pragma mark -
#pragma mark MVKCmdUpdateBuffer

/** Vulkan command to update the contents of a buffer. */
class MVKCmdUpdateBuffer : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer dstBuffer,
						VkDeviceSize dstOffset,
						VkDeviceSize dataSize,
						const void* pData);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKBuffer* _dstBuffer;
    VkDeviceSize _dstOffset;
    VkDeviceSize _dataSize;
    MVKVectorDefault<uint8_t> _srcDataCache;
};
