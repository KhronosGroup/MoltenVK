/*
 * MVKMTLResourceBindings.h
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "mvk_vulkan.h"

#import <Metal/Metal.h>


class MVKResource;
class MVKBuffer;
class MVKImage;


/** Describes a MTLTexture resource binding. */
typedef struct {
    union { id<MTLTexture> mtlTexture = nil; id<MTLTexture> mtlResource; }; // aliases
    uint32_t swizzle = 0;
	uint16_t index = 0;
    bool isDirty = true;
} MVKMTLTextureBinding;

/** Describes a MTLSamplerState resource binding. */
typedef struct {
    union { id<MTLSamplerState> mtlSamplerState = nil; id<MTLSamplerState> mtlResource; }; // aliases
    uint16_t index = 0;
    bool isDirty = true;
} MVKMTLSamplerStateBinding;

/** Describes a MTLBuffer resource binding. */
typedef struct {
    union { id<MTLBuffer> mtlBuffer = nil; id<MTLBuffer> mtlResource; const void* mtlBytes; }; // aliases
    VkDeviceSize offset = 0;
    uint32_t size = 0;
	uint16_t index = 0;
    bool isDirty = true;
    bool isInline = false;
} MVKMTLBufferBinding;

/** Describes a MTLBuffer resource binding as used for an index buffer. */
typedef struct {
    union { id<MTLBuffer> mtlBuffer = nil; id<MTLBuffer> mtlResource; }; // aliases
    VkDeviceSize offset = 0;
    uint8_t mtlIndexType = 0;		// MTLIndexType
    bool isDirty = true;
} MVKIndexMTLBufferBinding;

/** Concise and consistent structure for holding pipeline barrier info. */
typedef struct MVKPipelineBarrier {

	typedef enum : uint8_t {
		None,
		Memory,
		Buffer,
		Image,
	} MVKPipelineBarrierType;

	union { MVKBuffer* mvkBuffer = nullptr; MVKImage* mvkImage; MVKResource* mvkResource; };
	union {
		struct {
			VkDeviceSize offset = 0;
			VkDeviceSize size = 0;
		};
		struct {
			VkImageLayout newLayout;
			VkImageAspectFlags aspectMask;
			uint16_t baseArrayLayer;
			uint16_t layerCount;
			uint8_t baseMipLevel;
			uint8_t levelCount;
		};
	};
	VkAccessFlags srcAccessMask = 0;
	VkAccessFlags dstAccessMask = 0;
	uint8_t srcQueueFamilyIndex = 0;
	uint8_t dstQueueFamilyIndex = 0;

	MVKPipelineBarrierType type = None;

	bool isMemoryBarrier() { return type == Memory; }
	bool isBufferBarrier() { return type == Buffer; }
	bool isImageBarrier() { return type == Image; }

	MVKPipelineBarrier(const VkMemoryBarrier& vkBarrier) :
		type(Memory),
		srcAccessMask(vkBarrier.srcAccessMask),
		dstAccessMask(vkBarrier.dstAccessMask)
		{}

	MVKPipelineBarrier(const VkBufferMemoryBarrier& vkBarrier) :
		type(Buffer),
		srcAccessMask(vkBarrier.srcAccessMask),
		dstAccessMask(vkBarrier.dstAccessMask),
		srcQueueFamilyIndex(vkBarrier.srcQueueFamilyIndex),
		dstQueueFamilyIndex(vkBarrier.dstQueueFamilyIndex),
		mvkBuffer((MVKBuffer*)vkBarrier.buffer),
		offset(vkBarrier.offset),
		size(vkBarrier.size)
		{}

	MVKPipelineBarrier(const VkImageMemoryBarrier& vkBarrier) :
		type(Image),
		srcAccessMask(vkBarrier.srcAccessMask),
		dstAccessMask(vkBarrier.dstAccessMask),
		newLayout(vkBarrier.newLayout),
		srcQueueFamilyIndex(vkBarrier.srcQueueFamilyIndex),
		dstQueueFamilyIndex(vkBarrier.dstQueueFamilyIndex),
		mvkImage((MVKImage*)vkBarrier.image),
		aspectMask(vkBarrier.subresourceRange.aspectMask),
		baseMipLevel(vkBarrier.subresourceRange.baseMipLevel),
		levelCount(vkBarrier.subresourceRange.levelCount),
		baseArrayLayer(vkBarrier.subresourceRange.baseArrayLayer),
		layerCount(vkBarrier.subresourceRange.layerCount)
		{}

} MVKPipelineBarrier;

