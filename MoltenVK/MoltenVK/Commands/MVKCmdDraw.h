/*
 * MVKCmdDraw.h
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
#include "MVKMTLResourceBindings.h"
#include "MVKSmallVector.h"

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKCmdBindVertexBuffers

/**
 * Vulkan command to bind buffers containing vertex content.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdBindVertexBuffers : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t firstBinding,
						uint32_t bindingCount,
						const VkBuffer* pBuffers,
						const VkDeviceSize* pOffsets,
						const VkDeviceSize* pSizes,
						const VkDeviceSize* pStrides);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    MVKSmallVector<MVKMTLBufferBinding, N> _bindings;
};

// Concrete template class implementations.
typedef MVKCmdBindVertexBuffers<1> MVKCmdBindVertexBuffers1;
typedef MVKCmdBindVertexBuffers<2> MVKCmdBindVertexBuffers2;
typedef MVKCmdBindVertexBuffers<8> MVKCmdBindVertexBuffersMulti;


#pragma mark -
#pragma mark MVKCmdBindIndexBuffer

class MVKCmdBindIndexBuffer : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkDeviceSize offset,
						VkIndexType indexType);

	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkDeviceSize offset,
						VkDeviceSize size,
						VkIndexType indexType);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    MVKIndexMTLBufferBinding _binding;
    bool _isUint8;
};


#pragma mark -
#pragma mark MVKCmdDraw

class MVKCmdDraw : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t vertexCount,
						uint32_t instanceCount,
						uint32_t firstVertex,
						uint32_t firstInstance);

    void encode(MVKCommandEncoder* cmdEncoder) override;
	void encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder);

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	uint32_t _firstVertex;
	uint32_t _vertexCount;
	uint32_t _firstInstance;
	uint32_t _instanceCount;
};


#pragma mark -
#pragma mark MVKCmdDrawIndexed

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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	void encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder);

	uint32_t _firstIndex;
	uint32_t _indexCount;
	int32_t	_vertexOffset;
	uint32_t _firstInstance;
	uint32_t _instanceCount;
};


#pragma mark -
#pragma mark MVKCmdDrawIndirect

class MVKCmdDrawIndirect : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkDeviceSize offset,
						uint32_t count,
						uint32_t stride);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	void encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder);

	id<MTLBuffer> _mtlIndirectBuffer;
	VkDeviceSize _mtlIndirectBufferOffset;
	uint32_t _mtlIndirectBufferStride;
	uint32_t _drawCount;
};


#pragma mark -
#pragma mark MVKCmdDrawIndexedIndirect

class MVKCmdDrawIndexedIndirect : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkDeviceSize offset,
						uint32_t count,
						uint32_t stride);

	VkResult setContent(MVKCommandBuffer* cmdBuff,
						id<MTLBuffer> indirectMTLBuff,
						VkDeviceSize indirectMTLBuffOffset,
						uint32_t drawCount,
						uint32_t stride,
						uint32_t directCmdFirstInstance);

	void encode(MVKCommandEncoder* cmdEncoder) override;
	void encode(MVKCommandEncoder* cmdEncoder, const MVKIndexMTLBufferBinding& ibbOrig);

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	id<MTLBuffer> _mtlIndirectBuffer;
	VkDeviceSize _mtlIndirectBufferOffset;
	uint32_t _mtlIndirectBufferStride;
	uint32_t _drawCount;
	uint32_t _directCmdFirstInstance;
};
