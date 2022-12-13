/*
 * MVKCmdDraw.h
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

#pragma once

#include "MVKCommand.h"
#include "MVKMTLResourceBindings.h"
#include "MVKSmallVector.h"

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKCmdBindVertexBuffers

/**
 * Vulkan command to bind buffers containing vertex content.
 */
class MVKCmdBindVertexBuffers : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t startBinding,
						uint32_t bindingCount,
						const VkBuffer* pBuffers,
						const VkDeviceSize* pOffsets);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandVector<MVKMTLBufferBinding> _bindings;
};


#pragma mark -
#pragma mark MVKCmdBindIndexBuffer

/** Vulkan command to bind a vertex index buffer. */
class MVKCmdBindIndexBuffer : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkDeviceSize offset,
						VkIndexType indexType);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKIndexMTLBufferBinding _binding;
};


#pragma mark -
#pragma mark MVKCmdDraw

/** Vulkan command to draw vertices. */
class MVKCmdDraw : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t vertexCount,
						uint32_t instanceCount,
						uint32_t firstVertex,
						uint32_t firstInstance);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	uint32_t _firstVertex;
	uint32_t _vertexCount;
	uint32_t _firstInstance;
	uint32_t _instanceCount;
};


#pragma mark -
#pragma mark MVKCmdDrawIndexed

/** Vulkan command to draw indexed vertices. */
class MVKCmdDrawIndexed : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t indexCount,
						uint32_t instanceCount,
						uint32_t firstIndex,
						int32_t vertexOffset,
						uint32_t firstInstance);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	uint32_t _firstIndex;
	uint32_t _indexCount;
	int32_t	_vertexOffset;
	uint32_t _firstInstance;
	uint32_t _instanceCount;
};


#pragma mark -
#pragma mark MVKCmdDrawIndirect

/** Vulkan command to draw vertices indirectly. */
class MVKCmdDrawIndirect : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkDeviceSize offset,
						uint32_t count,
						uint32_t stride);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	id<MTLBuffer> _mtlIndirectBuffer;
	VkDeviceSize _mtlIndirectBufferOffset;
	uint32_t _mtlIndirectBufferStride;
	uint32_t _drawCount;
};


#pragma mark -
#pragma mark MVKCmdDrawIndexedIndirect

/** Vulkan command to draw indexed vertices indirectly. */
class MVKCmdDrawIndexedIndirect : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkDeviceSize offset,
						uint32_t count,
						uint32_t stride);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	id<MTLBuffer> _mtlIndirectBuffer;
	VkDeviceSize _mtlIndirectBufferOffset;
	uint32_t _mtlIndirectBufferStride;
	uint32_t _drawCount;
};
