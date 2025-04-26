/*
 * MVKCmdTransfer.h
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

#pragma once

#include "MVKCommand.h"
#include "MVKMTLBufferAllocation.h"
#include "MVKCommandResourceFactory.h"
#include "MVKFoundation.h"
#include "MVKSmallVector.h"

#import <Metal/Metal.h>

class MVKImage;
class MVKBuffer;


#pragma mark -
#pragma mark MVKCmdCopyImage

/**
 * Vulkan command to copy image regions.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdCopyImage : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkImage srcImage,
						VkImageLayout srcImageLayout,
						VkImage dstImage,
						VkImageLayout dstImageLayout,
						uint32_t regionCount,
						const VkImageCopy* pRegions);
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        const VkCopyImageInfo2* pImageInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override { encode(cmdEncoder, kMVKCommandUseCopyImage); }

	void encode(MVKCommandEncoder* cmdEncoder, MVKCommandUse commandUse);

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    VkResult validate(MVKCommandBuffer* cmdBuff, const VkImageCopy2* region);

	MVKSmallVector<VkImageCopy2, N> _vkImageCopies;
	MVKImage* _srcImage;
	MVKImage* _dstImage;
	VkImageLayout _srcLayout;
	VkImageLayout _dstLayout;
};

// Concrete template class implementations.
typedef MVKCmdCopyImage<1> MVKCmdCopyImage1;
typedef MVKCmdCopyImage<4> MVKCmdCopyImageMulti;


#pragma mark -
#pragma mark MVKCmdBlitImage

/** Number of vertices in a BLIT rectangle. */
#define kMVKBlitVertexCount		4

/** Combines a VkImageBlit with vertices to render it. */
typedef struct {
	VkImageBlit2 region;
	MVKVertexPosTex vertices[kMVKBlitVertexCount];
} MVKImageBlitRender;

/**
 * Vulkan command to BLIT image regions.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdBlitImage : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkImage srcImage,
						VkImageLayout srcImageLayout,
						VkImage dstImage,
						VkImageLayout dstImageLayout,
						uint32_t regionCount,
						const VkImageBlit* pRegions,
						VkFilter filter);
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        const VkBlitImageInfo2* pBlitImageInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override { encode(cmdEncoder, kMVKCommandUseBlitImage); }

	void encode(MVKCommandEncoder* cmdEncoder, MVKCommandUse commandUse);

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	bool canCopyFormats(const VkImageBlit2& region);
	bool canCopy(const VkImageBlit2& region);
	void populateVertices(MVKVertexPosTex* vertices, const VkImageBlit2& region);
    VkResult validate(MVKCommandBuffer* cmdBuff, const VkImageBlit2* region, bool isDestUnwritableLinear);

	MVKSmallVector<VkImageBlit2, N> _vkImageBlits;
	MVKImage* _srcImage;
	MVKImage* _dstImage;
	VkImageLayout _srcLayout;
	VkImageLayout _dstLayout;
	VkFilter _filter;
};

// Concrete template class implementations.
typedef MVKCmdBlitImage<1> MVKCmdBlitImage1;
typedef MVKCmdBlitImage<4> MVKCmdBlitImageMulti;


#pragma mark -
#pragma mark MVKCmdResolveImage

/** Describes Metal texture resolve parameters. */
typedef struct {
    VkImageSubresourceLayers srcSubresource;
    VkImageSubresourceLayers dstSubresource;
} MVKMetalResolveSlice;

/**
 * Vulkan command to resolve image regions.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdResolveImage : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkImage srcImage,
						VkImageLayout srcImageLayout,
						VkImage dstImage,
						VkImageLayout dstImageLayout,
						uint32_t regionCount,
						const VkImageResolve* pRegions);
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        const VkResolveImageInfo2* pResolveImageInfo);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    VkResult validate(MVKCommandBuffer* cmdBuff, const VkImageResolve2* region);

	MVKSmallVector<VkImageResolve2, N> _vkImageResolves;
    MVKImage* _srcImage;
	MVKImage* _dstImage;
    VkImageLayout _srcLayout;
    VkImageLayout _dstLayout;
};

// Concrete template class implementations.
typedef MVKCmdResolveImage<1> MVKCmdResolveImage1;
typedef MVKCmdResolveImage<4> MVKCmdResolveImageMulti;


#pragma mark -
#pragma mark MVKCmdCopyBuffer

/**
 * Vulkan command to copy buffer regions.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdCopyBuffer : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer srcBuffer,
						VkBuffer destBuffer,
						uint32_t regionCount,
						const VkBufferCopy* pRegions);
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        const VkCopyBufferInfo2* pCopyBufferInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<VkBufferCopy2, N> _bufferCopyRegions;
	MVKBuffer* _srcBuffer;
	MVKBuffer* _dstBuffer;
};

// Concrete template class implementations.
typedef MVKCmdCopyBuffer<1> MVKCmdCopyBuffer1;
typedef MVKCmdCopyBuffer<4> MVKCmdCopyBufferMulti;


#pragma mark -
#pragma mark MVKCmdBufferImageCopy

/**
 * Vulkan command to copy either from a buffer to an image, or from an image to a buffer.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdBufferImageCopy : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkImage image,
						VkImageLayout imageLayout,
						uint32_t regionCount,
						const VkBufferImageCopy* pRegions,
						bool toImage);
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        const VkCopyBufferToImageInfo2* pBufferToImageInfo);
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        const VkCopyImageToBufferInfo2* pImageToBufferInfo);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	bool isArrayTexture();
    VkResult validate(MVKCommandBuffer* cmdBuff);

	MVKSmallVector<VkBufferImageCopy2, N> _bufferImageCopyRegions;
    MVKBuffer* _buffer;
    MVKImage* _image;
    bool _toImage = false;
};

// Concrete template class implementations.
typedef MVKCmdBufferImageCopy<1> MVKCmdBufferImageCopy1;
typedef MVKCmdBufferImageCopy<4> MVKCmdBufferImageCopy4;	// To support MVKCmdCopyImage
typedef MVKCmdBufferImageCopy<8> MVKCmdBufferImageCopy8;
typedef MVKCmdBufferImageCopy<16> MVKCmdBufferImageCopyMulti;


#pragma mark -
#pragma mark MVKCmdClearAttachments

/**
 * Abstract Vulkan command to clear attachment regions.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdClearAttachments : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t attachmentCount,
						const VkClearAttachment* pAttachments,
						uint32_t rectCount,
						const VkClearRect* pRects,
						MVKCommandUse cmdUse = kMVKCommandUseClearAttachments);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    uint32_t getVertexCount(MVKCommandEncoder* cmdEncoder);
    void populateVertices(MVKCommandEncoder* cmdEncoder, simd::float4* vertices,
						  float attWidth, float attHeight);
	uint32_t populateVertices(MVKCommandEncoder* cmdEncoder, simd::float4* vertices,
							  uint32_t startVertex, VkClearRect& clearRect,
							  float attWidth, float attHeight);
	virtual VkClearValue& getClearValue(uint32_t attIdx) = 0;
	virtual void setClearValue(uint32_t attIdx, const VkClearValue& clearValue) = 0;
	NSString* getMTLDebugGroupLabel();

	MVKSmallVector<VkClearRect, N> _clearRects;
    MVKRPSKeyClearAtt _rpsKey;
	float _mtlDepthVal;
	uint32_t _mtlStencilValue;
	MVKCommandUse _commandUse;
};


#pragma mark -
#pragma mark MVKCmdClearSingleAttachment

/**
 * Vulkan command to clear regions in a single attachment.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdClearSingleAttachment : public MVKCmdClearAttachments<N> {

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	VkClearValue& getClearValue(uint32_t attIdx) override { return _vkClearValue; }
	void setClearValue(uint32_t attIdx, const VkClearValue& clearValue) override { _vkClearValue = clearValue; }

	VkClearValue _vkClearValue;
};

typedef MVKCmdClearSingleAttachment<1> MVKCmdClearSingleAttachment1;
typedef MVKCmdClearSingleAttachment<4> MVKCmdClearSingleAttachmentMulti;


#pragma mark -
#pragma mark MVKCmdClearMultiAttachments

/**
 * Vulkan command to clear regions multiple attachment.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdClearMultiAttachments : public MVKCmdClearAttachments<N> {

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	VkClearValue& getClearValue(uint32_t attIdx) override { return _vkClearValues[attIdx]; }
	void setClearValue(uint32_t attIdx, const VkClearValue& clearValue) override { _vkClearValues[attIdx] = clearValue; }

	VkClearValue _vkClearValues[kMVKMaxColorAttachmentCount];
};

typedef MVKCmdClearMultiAttachments<1> MVKCmdClearMultiAttachments1;
typedef MVKCmdClearMultiAttachments<4> MVKCmdClearMultiAttachmentsMulti;


#pragma mark -
#pragma mark MVKCmdClearImage

/**
 * Abstract Vulkan command to clear an image.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdClearImage : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkImage image,
						VkImageLayout imageLayout,
						const VkClearValue& clearValue,
						uint32_t rangeCount,
						const VkImageSubresourceRange* pRanges);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    uint32_t populateMetalCopyRegions(const VkImageBlit* pRegion, uint32_t cpyRgnIdx);
    uint32_t populateMetalBlitRenders(const VkImageBlit* pRegion, uint32_t rendRgnIdx);
    void populateVertices(MVKVertexPosTex* vertices, const VkImageBlit* pRegion);
	virtual bool isDepthStencilClear() = 0;

	MVKSmallVector<VkImageSubresourceRange, N> _subresourceRanges;
	MVKImage* _image;
	VkClearValue _clearValue;
};

#pragma mark -
#pragma mark MVKCmdClearColorImage

/**
 * Abstract Vulkan command to clear a color image.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdClearColorImage : public MVKCmdClearImage<N> {

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	bool isDepthStencilClear() override { return false; }
};

typedef MVKCmdClearColorImage<1> MVKCmdClearColorImage1;
typedef MVKCmdClearColorImage<4> MVKCmdClearColorImageMulti;


#pragma mark -
#pragma mark MVKCmdClearDepthStencilImage

/**
 * Abstract Vulkan command to clear a depth stencil image.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdClearDepthStencilImage : public MVKCmdClearImage<N> {

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	bool isDepthStencilClear() override { return true; }
};

typedef MVKCmdClearDepthStencilImage<1> MVKCmdClearDepthStencilImage1;
typedef MVKCmdClearDepthStencilImage<4> MVKCmdClearDepthStencilImageMulti;


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

	MVKSmallVector<uint8_t> _srcDataCache;
	MVKBuffer* _dstBuffer;
    VkDeviceSize _dstOffset;
    VkDeviceSize _dataSize;
};
