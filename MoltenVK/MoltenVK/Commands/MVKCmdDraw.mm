/*
 * MVKCmdDraw.mm
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCmdDraw.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKBuffer.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.h"


#pragma mark -
#pragma mark MVKCmdBindVertexBuffers

void MVKCmdBindVertexBuffers::setContent(uint32_t startBinding,
										 uint32_t bindingCount,
										 const VkBuffer* pBuffers,
										 const VkDeviceSize* pOffsets) {

    _bindings.clear();	// Clear for reuse
    _bindings.reserve(bindingCount);
    MVKMTLBufferBinding b;
    for (uint32_t bindIdx = 0; bindIdx < bindingCount; bindIdx++) {
        MVKBuffer* mvkBuffer = (MVKBuffer*)pBuffers[bindIdx];
        b.index = getDevice()->getMetalBufferIndexForVertexAttributeBinding(startBinding + bindIdx);
        b.mtlBuffer = mvkBuffer->getMTLBuffer();
        b.offset = mvkBuffer->getMTLBufferOffset() + pOffsets[bindIdx];
        _bindings.push_back(b);
    }
}

void MVKCmdBindVertexBuffers::encode(MVKCommandEncoder* cmdEncoder) {
    for (auto& b : _bindings) { cmdEncoder->_graphicsResourcesState.bindVertexBuffer(b); }
}

MVKCmdBindVertexBuffers::MVKCmdBindVertexBuffers(MVKCommandTypePool<MVKCmdBindVertexBuffers>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdBindIndexBuffer

void MVKCmdBindIndexBuffer::setContent(VkBuffer buffer,
                                       VkDeviceSize offset,
                                       VkIndexType indexType) {
	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
	_binding.mtlBuffer = mvkBuffer->getMTLBuffer();
	_binding.offset = mvkBuffer->getMTLBufferOffset() + offset;
	_binding.mtlIndexType = mvkMTLIndexTypeFromVkIndexType(indexType);
}

void MVKCmdBindIndexBuffer::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_graphicsResourcesState.bindIndexBuffer(_binding);
}

MVKCmdBindIndexBuffer::MVKCmdBindIndexBuffer(MVKCommandTypePool<MVKCmdBindIndexBuffer>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdDraw

void MVKCmdDraw::setContent(uint32_t vertexCount,
							uint32_t instanceCount,
							uint32_t firstVertex,
							uint32_t firstInstance) {
	_vertexCount = vertexCount;
	_instanceCount = instanceCount;
	_firstVertex = firstVertex;
	_firstInstance = firstInstance;

    // Validate
    clearConfigurationResult();
    if ((_firstInstance != 0) && !(getDevice()->_pMetalFeatures->baseVertexInstanceDrawing)) {
        setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDraw(): The current device does not support drawing with a non-zero base instance."));
    }
}

void MVKCmdDraw::encode(MVKCommandEncoder* cmdEncoder) {

	cmdEncoder->finalizeDrawState();	// Ensure all updated state has been submitted to Metal

	if (cmdEncoder->_pDeviceMetalFeatures->baseVertexInstanceDrawing) {
		[cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->_mtlPrimitiveType
										  vertexStart: _firstVertex
										  vertexCount: _vertexCount
										instanceCount: _instanceCount
										 baseInstance: _firstInstance];
	} else {
		[cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->_mtlPrimitiveType
										  vertexStart: _firstVertex
										  vertexCount: _vertexCount
										instanceCount: _instanceCount];
	}
}

MVKCmdDraw::MVKCmdDraw(MVKCommandTypePool<MVKCmdDraw>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {
}


#pragma mark -
#pragma mark MVKCmdDrawIndexed

void MVKCmdDrawIndexed::setContent(uint32_t indexCount,
                                   uint32_t instanceCount,
                                   uint32_t firstIndex,
                                   int32_t vertexOffset,
                                   uint32_t firstInstance) {
	_indexCount = indexCount;
	_instanceCount = instanceCount;
	_firstIndex = firstIndex;
	_vertexOffset = vertexOffset;
	_firstInstance = firstInstance;

    // Validate
    clearConfigurationResult();
    if ((_firstInstance != 0) && !(getDevice()->_pMetalFeatures->baseVertexInstanceDrawing)) {
        setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexed(): The current device does not support drawing with a non-zero base instance."));
    }
    if ((_vertexOffset != 0) && !(getDevice()->_pMetalFeatures->baseVertexInstanceDrawing)) {
        setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexed(): The current device does not support drawing with a non-zero base vertex."));
    }
}

void MVKCmdDrawIndexed::encode(MVKCommandEncoder* cmdEncoder) {

	cmdEncoder->finalizeDrawState();	// Ensure all updated state has been submitted to Metal

    MVKIndexMTLBufferBinding& ibb = cmdEncoder->_graphicsResourcesState._mtlIndexBufferBinding;
	size_t idxSize = mvkMTLIndexTypeSizeInBytes(ibb.mtlIndexType);
	VkDeviceSize idxBuffOffset = ibb.offset + (_firstIndex * idxSize);

	if (cmdEncoder->_pDeviceMetalFeatures->baseVertexInstanceDrawing) {
		[cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->_mtlPrimitiveType
												  indexCount: _indexCount
												   indexType: ibb.mtlIndexType
												 indexBuffer: ibb.mtlBuffer
										   indexBufferOffset: idxBuffOffset
											   instanceCount: _instanceCount
												  baseVertex: _vertexOffset
												baseInstance: _firstInstance];
	} else {
		[cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->_mtlPrimitiveType
												  indexCount: _indexCount
												   indexType: ibb.mtlIndexType
												 indexBuffer: ibb.mtlBuffer
										   indexBufferOffset: idxBuffOffset
											   instanceCount: _instanceCount];
	}
}

MVKCmdDrawIndexed::MVKCmdDrawIndexed(MVKCommandTypePool<MVKCmdDrawIndexed>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdDrawIndirect

void MVKCmdDrawIndirect::setContent(VkBuffer buffer,
										VkDeviceSize offset,
										uint32_t drawCount,
										uint32_t stride) {
	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
	_mtlIndirectBuffer = mvkBuffer->getMTLBuffer();
	_mtlIndirectBufferOffset = mvkBuffer->getMTLBufferOffset() + offset;
	_mtlIndirectBufferStride = stride;
	_drawCount = drawCount;

    // Validate
    clearConfigurationResult();
    if ( !(getDevice()->_pMetalFeatures->indirectDrawing) ) {
        setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndirect(): The current device does not support indirect drawing."));
    }
}

void MVKCmdDrawIndirect::encode(MVKCommandEncoder* cmdEncoder) {

    cmdEncoder->finalizeDrawState();	// Ensure all updated state has been submitted to Metal
	
	VkDeviceSize mtlIndBuffOfst = _mtlIndirectBufferOffset;
	for (uint32_t drawIdx = 0; drawIdx < _drawCount; drawIdx++) {
		[cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->_mtlPrimitiveType
									   indirectBuffer: _mtlIndirectBuffer
								 indirectBufferOffset: mtlIndBuffOfst];
		mtlIndBuffOfst += _mtlIndirectBufferStride;
	}
}

MVKCmdDrawIndirect::MVKCmdDrawIndirect(MVKCommandTypePool<MVKCmdDrawIndirect>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdDrawIndexedIndirect

void MVKCmdDrawIndexedIndirect::setContent(VkBuffer buffer,
										VkDeviceSize offset,
										uint32_t drawCount,
										uint32_t stride) {
	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
	_mtlIndirectBuffer = mvkBuffer->getMTLBuffer();
	_mtlIndirectBufferOffset = mvkBuffer->getMTLBufferOffset() + offset;
	_mtlIndirectBufferStride = stride;
	_drawCount = drawCount;

    // Validate
    clearConfigurationResult();
    if ( !(getDevice()->_pMetalFeatures->indirectDrawing) ) {
        setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexedIndirect(): The current device does not support indirect drawing."));
    }
}

void MVKCmdDrawIndexedIndirect::encode(MVKCommandEncoder* cmdEncoder) {

	cmdEncoder->finalizeDrawState();	// Ensure all updated state has been submitted to Metal

    MVKIndexMTLBufferBinding& ibb = cmdEncoder->_graphicsResourcesState._mtlIndexBufferBinding;

    VkDeviceSize mtlIndBuffOfst = _mtlIndirectBufferOffset;
	for (uint32_t drawIdx = 0; drawIdx < _drawCount; drawIdx++) {
		[cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->_mtlPrimitiveType
												   indexType: ibb.mtlIndexType
												 indexBuffer: ibb.mtlBuffer
										   indexBufferOffset: ibb.offset
											  indirectBuffer: _mtlIndirectBuffer
										indirectBufferOffset: mtlIndBuffOfst];
		mtlIndBuffOfst += _mtlIndirectBufferStride;
	}
}

MVKCmdDrawIndexedIndirect::MVKCmdDrawIndexedIndirect(MVKCommandTypePool<MVKCmdDrawIndexedIndirect>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark Command creation functions

void mvkCmdBindVertexBuffers(MVKCommandBuffer* cmdBuff,
							 uint32_t startBinding,
							 uint32_t bindingCount,
							 const VkBuffer* pBuffers,
							 const VkDeviceSize* pOffsets) {
	MVKCmdBindVertexBuffers* cmd = cmdBuff->_commandPool->_cmdBindVertexBuffersPool.acquireObject();
	cmd->setContent(startBinding, bindingCount, pBuffers, pOffsets);
	cmdBuff->addCommand(cmd);
}

void mvkCmdDraw(MVKCommandBuffer* cmdBuff,
				uint32_t vertexCount,
				uint32_t instanceCount,
				uint32_t firstVertex,
				uint32_t firstInstance) {
	MVKCmdDraw* cmd = cmdBuff->_commandPool->_cmdDrawPool.acquireObject();
	cmd->setContent(vertexCount, instanceCount, firstVertex, firstInstance);
	cmdBuff->addCommand(cmd);
}

void mvkCmdDrawIndexed(MVKCommandBuffer* cmdBuff,
					   uint32_t indexCount,
					   uint32_t instanceCount,
					   uint32_t firstIndex,
					   int32_t vertexOffset,
					   uint32_t firstInstance) {
	MVKCmdDrawIndexed* cmd = cmdBuff->_commandPool->_cmdDrawIndexedPool.acquireObject();
	cmd->setContent(indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
	cmdBuff->addCommand(cmd);
}

void mvkCmdBindIndexBuffer(MVKCommandBuffer* cmdBuff,
						   VkBuffer buffer,
						   VkDeviceSize offset,
						   VkIndexType indexType) {
	MVKCmdBindIndexBuffer* cmd = cmdBuff->_commandPool->_cmdBindIndexBufferPool.acquireObject();
	cmd->setContent(buffer, offset, indexType);
	cmdBuff->addCommand(cmd);
}

void mvkCmdDrawIndirect(MVKCommandBuffer* cmdBuff,
						VkBuffer buffer,
						VkDeviceSize offset,
						uint32_t drawCount,
						uint32_t stride) {
	MVKCmdDrawIndirect* cmd = cmdBuff->_commandPool->_cmdDrawIndirectPool.acquireObject();
	cmd->setContent(buffer, offset, drawCount, stride);
	cmdBuff->addCommand(cmd);
}

void mvkCmdDrawIndexedIndirect(MVKCommandBuffer* cmdBuff,
							   VkBuffer buffer,
							   VkDeviceSize offset,
							   uint32_t drawCount,
							   uint32_t stride) {
	MVKCmdDrawIndexedIndirect* cmd = cmdBuff->_commandPool->_cmdDrawIndexedIndirectPool.acquireObject();
	cmd->setContent(buffer, offset, drawCount, stride);
	cmdBuff->addCommand(cmd);
}


