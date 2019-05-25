/*
 * MVKCmdTransfer.h
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

#pragma once

#include "MVKCommand.h"
#include "MVKMTLBufferAllocation.h"
#include "MVKCommandResourceFactory.h"
#include "MVKFoundation.h"
#include <vector>

#import <Metal/Metal.h>

class MVKImage;
class MVKBuffer;


#pragma mark -
#pragma mark MVKCmdCopyImage

/** Describes the Metal texture copying parameters. */
typedef struct {
	uint32_t	srcLevel;
	uint32_t	srcSlice;
	MTLOrigin	srcOrigin;
	MTLSize		srcSize;
	uint32_t	dstLevel;
	uint32_t	dstSlice;
	MTLOrigin	dstOrigin;
} MVKMetalCopyTextureRegion;

/** Vulkan command to copy image regions. */
class MVKCmdCopyImage : public MVKCommand {

public:
	void setContent(VkImage srcImage,
					VkImageLayout srcImageLayout,
					VkImage dstImage,
					VkImageLayout dstImageLayout,
					uint32_t regionCount,
					const VkImageCopy* pRegions,
                    MVKCommandUse commandUse = kMVKCommandUseCopyImage);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdCopyImage(MVKCommandTypePool<MVKCmdCopyImage>* pool) :
		MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

protected:
    void addMetalCopyRegions(const VkImageCopy* pRegion);

	MVKImage* _srcImage;
	VkImageLayout _srcLayout;
	MVKImage* _dstImage;
	VkImageLayout _dstLayout;
	std::vector<MVKMetalCopyTextureRegion> _mtlTexCopyRegions;
    MVKCommandUse _commandUse = kMVKCommandUseNone;
};


#pragma mark -
#pragma mark MVKCmdBlitImage

/** Number of vertices in a BLIT rectangle. */
#define kMVKBlitVertexCount		4

/** Describes Metal texture rendering parameters. */
typedef struct {
	uint32_t	srcLevel;
	uint32_t	srcSlice;
	uint32_t	dstLevel;
	uint32_t	dstSlice;
	MVKVertexPosTex vertices[kMVKBlitVertexCount];
} MVKMetalBlitTextureRender;

/** Vulkan command to BLIT image regions. */
class MVKCmdBlitImage : public MVKCmdCopyImage {

public:
	void setContent(VkImage srcImage,
					VkImageLayout srcImageLayout,
					VkImage dstImage,
					VkImageLayout dstImageLayout,
					uint32_t regionCount,
					const VkImageBlit* pRegions,
                    VkFilter filter,
                    MVKCommandUse commandUse = kMVKCommandUseBlitImage);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdBlitImage(MVKCommandTypePool<MVKCmdBlitImage>* pool);

	~MVKCmdBlitImage() override;

protected:
	bool canCopy(const VkImageBlit* pRegion);
    void addMetalCopyRegions(const VkImageBlit* pRegion);
    void addMetalBlitRenders(const VkImageBlit* pRegion);
	void populateVertices(MVKVertexPosTex* vertices, const VkImageBlit* pRegion);
    void initMTLRenderPassDescriptor();

	MTLRenderPassDescriptor* _mtlRenderPassDescriptor;
	MTLSamplerMinMagFilter _mtlFilter;
    MTLPixelFormat _mtlPixFmt;
	MVKRPSKeyBlitImg _blitKey;
	std::vector<MVKMetalBlitTextureRender> _mtlTexBlitRenders;
};


#pragma mark -
#pragma mark MVKCmdResolveImage

/** Describes Metal texture resolve parameters. */
typedef struct {
    NSUInteger	level;
    NSUInteger	slice;
} MVKMetalResolveSlice;

/** Vulkan command to resolve image regions. */
class MVKCmdResolveImage : public MVKCommand {

public:
    void setContent(VkImage srcImage,
                    VkImageLayout srcImageLayout,
                    VkImage dstImage,
                    VkImageLayout dstImageLayout,
                    uint32_t regionCount,
                    const VkImageResolve* pRegions);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdResolveImage(MVKCommandTypePool<MVKCmdResolveImage>* pool);

    ~MVKCmdResolveImage() override;

protected:
    void addExpansionRegion(const VkImageResolve& resolveRegion);
    void addCopyRegion(const VkImageResolve& resolveRegion);
    void addResolveSlices(const VkImageResolve& resolveRegion);
    void initMTLRenderPassDescriptor();

    MVKImage* _srcImage;
    VkImageLayout _srcLayout;
    MVKImage* _dstImage;
    VkImageLayout _dstLayout;
    std::vector<VkImageBlit> _expansionRegions;
    std::vector<VkImageCopy> _copyRegions;
    MVKImageDescriptorData _transferImageData;
    MTLRenderPassDescriptor* _mtlRenderPassDescriptor;
    std::vector<MVKMetalResolveSlice> _mtlResolveSlices;
};


#pragma mark -
#pragma mark MVKCmdCopyBuffer

/** Vulkan command to copy buffer regions. */
class MVKCmdCopyBuffer : public MVKCommand {

public:
	void setContent(VkBuffer srcBuffer,
					VkBuffer destBuffer,
					uint32_t regionCount,
					const VkBufferCopy* pRegions);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdCopyBuffer(MVKCommandTypePool<MVKCmdCopyBuffer>* pool) :
		MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

protected:

	MVKBuffer* _srcBuffer;
	MVKBuffer* _dstBuffer;
	std::vector<VkBufferCopy> _mtlBuffCopyRegions;
};


#pragma mark -
#pragma mark MVKCmdBufferImageCopy

/** Command to copy either from a buffer to an image, or from an image to a buffer. */
class MVKCmdBufferImageCopy : public MVKCommand {

public:
    void setContent(VkBuffer buffer,
                    VkImage image,
                    VkImageLayout imageLayout,
                    uint32_t regionCount,
                    const VkBufferImageCopy* pRegions,
                    bool toImage);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdBufferImageCopy(MVKCommandTypePool<MVKCmdBufferImageCopy>* pool) :
		MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

protected:
    MVKBuffer* _buffer;
    MVKImage* _image;
    VkImageLayout _imageLayout;
    std::vector<VkBufferImageCopy> _mtlBuffImgCopyRegions;
    bool _toImage = false;
};


#pragma mark -
#pragma mark MVKCmdClearAttachments

/** Vulkan command to clear attachment regions. */
class MVKCmdClearAttachments : public MVKCommand {

public:
    void setContent(uint32_t attachmentCount,
                    const VkClearAttachment* pAttachments,
                    uint32_t rectCount,
                    const VkClearRect* pRects);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdClearAttachments(MVKCommandTypePool<MVKCmdClearAttachments>* pool) :
		MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

protected:
    void populateVertices(float attWidth, float attHeight);
    void populateVertices(VkClearRect& clearRect, float attWidth, float attHeight);

    std::vector<VkClearRect> _clearRects;
    std::vector<simd::float4> _vertices;
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
    void setContent(VkImage image,
                    VkImageLayout imageLayout,
                    const VkClearValue& clearValue,
                    uint32_t rangeCount,
                    const VkImageSubresourceRange* pRanges,
                    bool isDepthStencilClear);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdClearImage(MVKCommandTypePool<MVKCmdClearImage>* pool) :
		MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

protected:
    uint32_t populateMetalCopyRegions(const VkImageBlit* pRegion, uint32_t cpyRgnIdx);
    uint32_t populateMetalBlitRenders(const VkImageBlit* pRegion, uint32_t rendRgnIdx);
    void populateVertices(MVKVertexPosTex* vertices, const VkImageBlit* pRegion);
    
    MVKImage* _image;
    VkImageLayout _imgLayout;
    std::vector<VkImageSubresourceRange> _subresourceRanges;
	MTLClearColor _mtlColorClearValue;
	double _mtlDepthClearValue;
    uint32_t _mtlStencilClearValue;
    bool _isDepthStencilClear;
};


#pragma mark -
#pragma mark MVKCmdFillBuffer

/** Vulkan command to fill a buffer. */
class MVKCmdFillBuffer : public MVKCommand {

public:
    void setContent(VkBuffer dstBuffer, VkDeviceSize dstOffset, VkDeviceSize size, uint32_t data);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdFillBuffer(MVKCommandTypePool<MVKCmdFillBuffer>* pool) :
		MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

protected:
    MVKBuffer* _dstBuffer;
    VkDeviceSize _dstOffset;
    VkDeviceSize _size;
    uint32_t _dataValue;
};


#pragma mark -
#pragma mark MVKCmdUpdateBuffer

/** Vulkan command to update the contents of a buffer. */
class MVKCmdUpdateBuffer : public MVKCommand {

public:
    void setContent(VkBuffer dstBuffer,
                    VkDeviceSize dstOffset,
                    VkDeviceSize dataSize,
                    const void* pData,
                    bool useDataCache);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdUpdateBuffer(MVKCommandTypePool<MVKCmdUpdateBuffer>* pool) :
		MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

protected:
    MVKBuffer* _dstBuffer;
    VkDeviceSize _dstOffset;
    VkDeviceSize _dataSize;
    std::vector<uint8_t> _srcDataCache;
};


#pragma mark -
#pragma mark Command creation functions

/** Adds a copy image command to the specified command buffer. */
void mvkCmdCopyImage(MVKCommandBuffer* cmdBuff,
					 VkImage srcImage,
					 VkImageLayout srcImageLayout,
					 VkImage dstImage,
					 VkImageLayout dstImageLayout,
					 uint32_t regionCount,
					 const VkImageCopy* pRegions);

/** Adds a BLIT image command to the specified command buffer. */
void mvkCmdBlitImage(MVKCommandBuffer* cmdBuff,
					 VkImage srcImage,
					 VkImageLayout srcImageLayout,
					 VkImage dstImage,
					 VkImageLayout dstImageLayout,
					 uint32_t regionCount,
					 const VkImageBlit* pRegions,
					 VkFilter filter);

/** Adds a resolve image command to the specified command buffer. */
void mvkCmdResolveImage(MVKCommandBuffer* cmdBuff,
                     VkImage srcImage,
                     VkImageLayout srcImageLayout,
                     VkImage dstImage,
                     VkImageLayout dstImageLayout,
                     uint32_t regionCount,
                     const VkImageResolve* pRegions);

/** Adds a copy buffer command to the specified command buffer. */
void mvkCmdCopyBuffer(MVKCommandBuffer* cmdBuff,
					  VkBuffer srcBuffer,
					  VkBuffer dstBuffer,
					  uint32_t regionCount,
					  const VkBufferCopy* pRegions);

/** Adds a copy buffer to image command to the specified command buffer. */
void mvkCmdCopyBufferToImage(MVKCommandBuffer* cmdBuff,
                             VkBuffer srcBuffer,
                             VkImage dstImage,
                             VkImageLayout dstImageLayout,
                             uint32_t regionCount,
                             const VkBufferImageCopy* pRegions);

/** Adds a copy buffer to image command to the specified command buffer. */
void mvkCmdCopyImageToBuffer(MVKCommandBuffer* cmdBuff,
                             VkImage srcImage,
                             VkImageLayout srcImageLayout,
                             VkBuffer dstBuffer,
                             uint32_t regionCount,
                             const VkBufferImageCopy* pRegions);

/** Adds a clear attachments command to the specified command buffer. */
void mvkCmdClearAttachments(MVKCommandBuffer* cmdBuff,
                            uint32_t attachmentCount,
                            const VkClearAttachment* pAttachments,
                            uint32_t rectCount,
                            const VkClearRect* pRects);

/** Adds a clear color image command to the specified command buffer. */
void mvkCmdClearColorImage(MVKCommandBuffer* cmdBuff,
						   VkImage image,
						   VkImageLayout imageLayout,
						   const VkClearColorValue* pColor,
						   uint32_t rangeCount,
						   const VkImageSubresourceRange* pRanges);

/** Adds a clear depth stencil image command to the specified command buffer. */
void mvkCmdClearDepthStencilImage(MVKCommandBuffer* cmdBuff,
                                  VkImage image,
                                  VkImageLayout imageLayout,
                                  const VkClearDepthStencilValue* pDepthStencil,
                                  uint32_t rangeCount,
                                  const VkImageSubresourceRange* pRanges);

/** Adds a fill buffer command to the specified command buffer. */
void mvkCmdFillBuffer(MVKCommandBuffer* cmdBuff,
                      VkBuffer dstBuffer,
                      VkDeviceSize dstOffset,
                      VkDeviceSize size,
                      uint32_t data);

/** Adds a buffer update command to the specified command buffer. */
void mvkCmdUpdateBuffer(MVKCommandBuffer* cmdBuff,
                        VkBuffer dstBuffer,
                        VkDeviceSize dstOffset,
                        VkDeviceSize dataSize,
                        const void* pData);
