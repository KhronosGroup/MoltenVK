/*
 * MVKCmdDraw.h
 *
 * Copyright (c) 2015-2023 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
						uint32_t startBinding,
						uint32_t bindingCount,
						const VkBuffer* pBuffers,
						const VkDeviceSize* pOffsets);

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

/** Vulkan command to bind a vertex index buffer. */
class MVKCmdBindIndexBuffer : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkDeviceSize offset,
						VkIndexType indexType);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	void encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder);

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


#pragma mark -
#pragma mark MVKCmdBeginTransformFeedback

/*
 * The active transform feedback buffers will capture primitives emitted from the corresponding XfbBuffer in the bound
 * graphics pipeline. Any XfbBuffer emitted that does not output to an active transform feedback buffer will not be
 * captured.
 */

template <size_t N>
class MVKCmdBeginTransformFeedback : public MVKCommand {
public:
    VkResult setContent(MVKCommandBuffer* cmdBuffer,
                        uint32_t firstCounterBuffer,
                        uint32_t counterBufferCount,
                        const VkBuffer* counterBuffers,
                        const VkDeviceSize* counterBufferOffsets);
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    MVKSmallVector<MVKMTLBufferBinding, N> _counterBuffers;
};

// Concrete template class implementations.
typedef MVKCmdBeginTransformFeedback<1> MVKCmdBeginTransformFeedback1;
typedef MVKCmdBeginTransformFeedback<2> MVKCmdBeginTransformFeedback2;
typedef MVKCmdBeginTransformFeedback<4> MVKCmdBeginTransformFeedbackMulti;

#pragma mark -
#pragma mark MVKCmdBindTransformFeedbackBuffers

/*
 * The values taken from elements i of pBuffers, pOffsets and pSizes replace the current state for the transform
 * feedback binding firstBinding + i, for i in [0, bindingCount). The transform feedback binding is updated to start
 * at the offset indicated by pOffsets[i] from the start of the buffer pBuffers[i].
 */
template <size_t N>
class MVKCmdBindTransformFeedbackBuffers : public MVKCommand {
public:
    VkResult setContent(MVKCommandBuffer* cmdBuffer,
                        uint32_t firstBinding,
                        uint32_t bindingCount,
                        const VkBuffer* pBuffers,
                        const VkDeviceSize* pOffsets,
                        const VkDeviceSize* pSizes);
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    MVKSmallVector<MVKMTLBufferBinding, N> _bindings;
};

// Concrete template class implementations.
typedef MVKCmdBindTransformFeedbackBuffers<1> MVKCmdBindTransformFeedbackBuffers1;
typedef MVKCmdBindTransformFeedbackBuffers<2> MVKCmdBindTransformFeedbackBuffers2;
typedef MVKCmdBindTransformFeedbackBuffers<4> MVKCmdBindTransformFeedbackBuffersMulti;

#pragma mark -
#pragma mark MVKCmdDrawIndirectByteCount

/*
 * Draw primitives where the vertex count is derived from the counter byte value in the counter buffer
 */

class MVKCmdDrawIndirectByteCount : public MVKCommand {
public:
    MVKCmdDrawIndirectByteCount() :
            instanceCount(0), firstInstance(0), counterBuffer(), deviceSize(), stride() {}
    VkResult setContent(MVKCommandBuffer* cmdBuffer,
                   uint32_t instanceCount,
                   uint32_t firstInstance,
                   VkBuffer counterBuffer,
                   uint32_t deviceSize,
                   uint32_t stride);
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    uint32_t instanceCount;
    uint32_t firstInstance;
    VkBuffer counterBuffer;
    uint32_t deviceSize;
    uint32_t stride;
};

#pragma mark -
#pragma mark MVKCmdEndTransformFeedback

class MVKCmdEndTransformFeedback : public MVKCommand {
public:
    VkResult setContent(MVKCommandBuffer* cmdBuffer);
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};
