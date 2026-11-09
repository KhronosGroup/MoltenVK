/*
 * MVKCmdDraw.mm
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"


#pragma mark -
#pragma mark MVKCmdBindVertexBuffers

template <size_t N>
VkResult MVKCmdBindVertexBuffers<N>::setContent(MVKCommandBuffer* cmdBuff,
												uint32_t firstBinding,
												uint32_t bindingCount,
												const VkBuffer* pBuffers,
												const VkDeviceSize* pOffsets,
												const VkDeviceSize* pSizes,
												const VkDeviceSize* pStrides) {
	_firstBinding = firstBinding;
	_bindings.clear();	// Clear for reuse
    _bindings.reserve(bindingCount);
    MVKVertexMTLBufferBinding b;
    for (uint32_t bindIdx = 0; bindIdx < bindingCount; bindIdx++) {
        MVKBuffer* mvkBuffer = (MVKBuffer*)pBuffers[bindIdx];
        b.mtlBuffer = mvkBuffer->getMTLBuffer();
        b.offset = mvkBuffer->getMTLBufferOffset() + pOffsets[bindIdx];
		b.size = pSizes ? uint32_t(pSizes[bindIdx] == VK_WHOLE_SIZE ? mvkBuffer->getByteCount() - pOffsets[bindIdx] : pSizes[bindIdx]) : 0;
		b.stride = pStrides ? (uint32_t)pStrides[bindIdx] : 0;
        _bindings.push_back(b);
    }

	return VK_SUCCESS;
}
template <size_t N>
void MVKCmdBindVertexBuffers<N>::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().bindVertexBuffers(_firstBinding, _bindings.contents());
}

template class MVKCmdBindVertexBuffers<1>;
template class MVKCmdBindVertexBuffers<2>;
template class MVKCmdBindVertexBuffers<8>;


#pragma mark -
#pragma mark MVKCmdBindIndexBuffer

VkResult MVKCmdBindIndexBuffer::setContent(MVKCommandBuffer* cmdBuff,
										   VkBuffer buffer,
										   VkDeviceSize offset,
										   VkIndexType indexType) {
	return setContent(cmdBuff, buffer, offset, VK_WHOLE_SIZE, indexType);
}

VkResult MVKCmdBindIndexBuffer::setContent(MVKCommandBuffer* cmdBuff,
										   VkBuffer buffer,
										   VkDeviceSize offset,
										   VkDeviceSize size,
										   VkIndexType indexType) {
	_binding.vkIndexType = indexType;
	_binding.mtlIndexType = mvkMTLIndexTypeFromVkIndexType(indexType);

	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
	if (mvkBuffer) {
		_binding.mtlBuffer = mvkBuffer->getMTLBuffer();
		_binding.offset = mvkBuffer->getMTLBufferOffset() + offset;
		_binding.size = size == VK_WHOLE_SIZE ? mvkBuffer->getByteCount() - offset : size;
	} else {
		_binding.mtlBuffer = nullptr;
		// Must be 0 for null buffer.
		_binding.offset = 0;
		_binding.size = size == VK_WHOLE_SIZE ? mvkMTLIndexTypeSizeInBytes((MTLIndexType)_binding.mtlIndexType) : size;
	}

	return VK_SUCCESS;
}

void MVKCmdBindIndexBuffer::encode(MVKCommandEncoder* cmdEncoder) {
    if (_binding.mtlBuffer == nullptr) {
        // In the null buffer case, offset must be 0, and since we don't support nullDescriptor, the indices are undefined.
        // Thus, we can use a simple temporary buffer to stand in for the index buffer here.
        const auto* placeholderBuffer = cmdEncoder->getTempMTLBuffer(_binding.size);
        _binding.mtlBuffer = placeholderBuffer->_mtlBuffer;
        _binding.offset = placeholderBuffer->_offset;
    }

    cmdEncoder->getState().bindIndexBuffer(_binding);
}


#pragma mark -
#pragma mark MVKCmdDraw

VkResult MVKCmdDraw::setContent(MVKCommandBuffer* cmdBuff,
								uint32_t vertexCount,
								uint32_t instanceCount,
								uint32_t firstVertex,
								uint32_t firstInstance,
								uint32_t drawIndex) {
	_vertexCount = vertexCount;
	_instanceCount = instanceCount;
	_firstVertex = firstVertex;
	_firstInstance = firstInstance;
	_drawIndex = drawIndex;

    // Validate
    if ((_firstInstance != 0) && !(cmdBuff->getMetalFeatures().baseVertexInstanceDrawing)) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDraw(): The current device does not support drawing with a non-zero base instance.");
    }

	return VK_SUCCESS;
}

// Populates and encodes a MVKCmdDrawIndexedIndirect command, after populating indexed indirect buffers.
void MVKCmdDraw::encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder) {

	// Create an indexed indirect buffer and populate it from the draw arguments.
	uint32_t indirectIdxBuffStride = sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
	auto* indirectIdxBuff = cmdEncoder->getTempMTLBuffer(indirectIdxBuffStride);
	auto* pIndArg = (MTLDrawIndexedPrimitivesIndirectArguments*)indirectIdxBuff->getContents();
	pIndArg->indexCount = _vertexCount;
	// let the indirect index point to the beginning of vertex index buffer below
	pIndArg->indexStart = 0;
	pIndArg->baseVertex = 0;
	pIndArg->instanceCount = _instanceCount;
	pIndArg->baseInstance = _firstInstance;

	// Create an index buffer populated with synthetic indexes.
	// Start populating indexes directly from the beginning and align with corresponding vertexes by adding _firstVertex
	MTLIndexType mtlIdxType = MTLIndexTypeUInt32;
	auto* vtxIdxBuff = cmdEncoder->getTempMTLBuffer(mvkMTLIndexTypeSizeInBytes(mtlIdxType) * _vertexCount);
	auto* pIdxBuff = (uint32_t*)vtxIdxBuff->getContents();

	for (uint32_t idx = 0; idx < _vertexCount; idx++) {
		pIdxBuff[idx] = _firstVertex + idx;
	}

	MVKIndexMTLBufferBinding ibb;
	ibb.mtlIndexType = mtlIdxType;
	ibb.mtlBuffer = vtxIdxBuff->_mtlBuffer;
	ibb.offset = vtxIdxBuff->_offset;
	ibb.size = vtxIdxBuff->_length;

	MVKCmdDrawIndexedIndirect diiCmd;
	diiCmd.setContent(cmdEncoder->_cmdBuffer,
					  indirectIdxBuff->_mtlBuffer,
					  indirectIdxBuff->_offset,
					  1,
					  indirectIdxBuffStride);
	diiCmd.encode(cmdEncoder, ibb);
}

void MVKCmdDraw::encode(MVKCommandEncoder* cmdEncoder) {

	if (_vertexCount == 0 || _instanceCount == 0) { return; }	// Nothing to do.

	cmdEncoder->restartMetalRenderPassIfNeeded();

	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;

	// Metal doesn't support triangle fans, so encode it as triangles via an indexed indirect triangles command instead.
	if (pipeline->getVkPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
		encodeIndexedIndirect(cmdEncoder);
		return;
	}

    cmdEncoder->_isIndexedDraw = false;

	MVKPiplineStages stages;
    pipeline->getStages(stages);

    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
	struct {
		uint32_t inControlPointCount = 0;
		uint32_t patchCount = 0;
	} tessParams;
    uint32_t outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        tessParams.inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        tessParams.patchCount = mvkCeilingDivide(_vertexCount, tessParams.inControlPointCount) * _instanceCount;
    }
    if (pipeline->needsDrawIdBuffer()) {
        tempDrawIDBuff = cmdEncoder->getTempMTLBuffer(sizeof(uint32_t));

        // Zero for a single draw, or the index of this draw within a vkCmdDrawMulti*EXT() call.
        *(uint32_t*)tempDrawIDBuff->getContents() = _drawIndex;
    }
    for (uint32_t s : stages) {
        auto stage = MVKGraphicsStage(s);
        cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal

		if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

		id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;

		switch (stage) {
            case kMVKGraphicsStageVertex: {
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                if (pipeline->needsVertexOutputBuffer()) {
                    vtxOutBuff = cmdEncoder->getTempMTLBuffer(_vertexCount * _instanceCount * 4 * dvcLimits.maxVertexOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                }
                if (pipeline->needsDrawIdBuffer()) {
                    [mtlTessCtlEncoder setBuffer: tempDrawIDBuff->_mtlBuffer
                                          offset: tempDrawIDBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                }
				[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(_firstVertex, _firstInstance, _vertexCount, _instanceCount)];
				// If there are vertex bindings with a zero vertex divisor, I need to offset them by
				// _firstInstance * stride, since that is the expected behaviour for a divisor of 0.
                cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
				id<MTLComputePipelineState> vtxState = pipeline->getTessVertexStageState();
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(_vertexCount, _instanceCount, 1)
					             threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(_vertexCount, vtxState.threadExecutionWidth), _instanceCount, 1)
                                      threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
				}
                break;
			}
            case kMVKGraphicsStageTessControl: {
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                if (pipeline->needsTessCtlOutputBuffer()) {
                    tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * tessParams.patchCount * 4 * dvcLimits.maxTessellationControlPerVertexOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                          offset: tcOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::Output]];
                }
                if (pipeline->needsTessCtlPatchOutputBuffer()) {
                    tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * 4 * dvcLimits.maxTessellationControlPerPatchOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                          offset: tcPatchOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::PatchOutput]];
                }
                tcLevelBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * sizeof(MTLQuadTessellationFactorsHalf), true);
                [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                      offset: tcLevelBuff->_offset
                                     atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::TessLevel]];
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &tessParams,
                                            sizeof(tessParams),
                                            pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::IndirectParams]);
                if (pipeline->needsVertexOutputBuffer()) {
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding)];
                }
				
				NSUInteger sgSize = pipeline->getTessControlStageState().threadExecutionWidth;
				NSUInteger wgSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
				while (wgSize > dvcLimits.maxComputeWorkGroupSize[0]) {
					sgSize >>= 1;
					wgSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
				}
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(tessParams.patchCount * outControlPointCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(tessParams.patchCount * outControlPointCount, wgSize), 1, 1)
									  threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
				}
                // Running this stage prematurely ended the render pass, so we have to start it up again.
                // TODO: On iOS, maybe we could use a tile shader to avoid this.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
                break;
			}
            case kMVKGraphicsStageRasterization:
                if (pipeline->isTessellationPipeline()) {
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
                                                                offset: tcOutBuff->_offset
                                                               atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding)];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
                                                                offset: tcPatchOutBuff->_offset
                                                               atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding)];
                    }
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
                                                            offset: tcLevelBuff->_offset
                                                           atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding)];
                    [cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
                                                                        offset: tcLevelBuff->_offset
                                                                instanceStride: 0];
                    [cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
                                                    patchStart: 0
                                                    patchCount: tessParams.patchCount
                                              patchIndexBuffer: nil
                                        patchIndexBufferOffset: 0
                                                 instanceCount: 1
                                                  baseInstance: 0];
                } else {
                    MVKRenderSubpass* subpass = cmdEncoder->getSubpass();
                    uint32_t viewCount = subpass->isMultiview() ? subpass->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
                    uint32_t instanceCount = _instanceCount * viewCount;
                    cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
                    if (pipeline->needsDrawIdBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tempDrawIDBuff->_mtlBuffer
                                                                offset: tempDrawIDBuff->_offset
                                                               atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                    }
                    if (mtlFeats.baseVertexInstanceDrawing) {
                        [cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                          vertexStart: _firstVertex
                                                          vertexCount: _vertexCount
                                                        instanceCount: instanceCount
                                                         baseInstance: _firstInstance];
                    } else {
                        [cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                          vertexStart: _firstVertex
                                                          vertexCount: _vertexCount
                                                        instanceCount: instanceCount];
                    }
                }
                break;
        }
    }
}


#pragma mark -
#pragma mark MVKCmdDrawIndexed

VkResult MVKCmdDrawIndexed::setContent(MVKCommandBuffer* cmdBuff,
									   uint32_t indexCount,
									   uint32_t instanceCount,
									   uint32_t firstIndex,
									   int32_t vertexOffset,
									   uint32_t firstInstance,
									   uint32_t drawIndex) {
	_indexCount = indexCount;
	_instanceCount = instanceCount;
	_firstIndex = firstIndex;
	_vertexOffset = vertexOffset;
	_firstInstance = firstInstance;
	_drawIndex = drawIndex;

    // Validate
	auto& mtlFeats = cmdBuff->getMetalFeatures();
    if ((_firstInstance != 0) && !(mtlFeats.baseVertexInstanceDrawing)) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexed(): The current device does not support drawing with a non-zero base instance.");
    }
    if ((_vertexOffset != 0) && !(mtlFeats.baseVertexInstanceDrawing)) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexed(): The current device does not support drawing with a non-zero base vertex.");
    }

	return VK_SUCCESS;
}

// Populates and encodes a MVKCmdDrawIndexedIndirect command, after populating an indexed indirect buffer.
void MVKCmdDrawIndexed::encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder) {

	// Create an indexed indirect buffer and populate it from the draw arguments.
	uint32_t indirectIdxBuffStride = sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
	auto* indirectIdxBuff = cmdEncoder->getTempMTLBuffer(indirectIdxBuffStride);
	auto* pIndArg = (MTLDrawIndexedPrimitivesIndirectArguments*)indirectIdxBuff->getContents();
	pIndArg->indexCount = _indexCount;
	pIndArg->indexStart = _firstIndex;
	pIndArg->baseVertex = _vertexOffset;
	pIndArg->instanceCount = _instanceCount;
	pIndArg->baseInstance = _firstInstance;

	MVKCmdDrawIndexedIndirect diiCmd;
	diiCmd.setContent(cmdEncoder->_cmdBuffer,
					  indirectIdxBuff->_mtlBuffer,
					  indirectIdxBuff->_offset,
					  1,
					  indirectIdxBuffStride);
	diiCmd.encode(cmdEncoder);
}

static const MVKMTLBufferAllocation* convertUint8IndexBuffer(MVKCommandEncoder* cmdEncoder, const MVKIndexMTLBufferBinding& ibb) {
    // Copy 8-bit indices into 16-bit index buffer compatible with Metal.
    const auto numIndices = ibb.size;
    auto* uint16Buf = cmdEncoder->getTempMTLBuffer(numIndices * 2);

    cmdEncoder->encodeStoreActions(true);

    // Determine the number of full threadgroups we can dispatch to cover the buffer content efficiently.
    // Some GPU's report different values for max threadgroup width between the pipeline state and device,
    // so conservatively use the minimum of these two reported values.
    id<MTLComputePipelineState> cps = cmdEncoder->getCommandEncodingPool()->getConvertUint8IndicesMTLComputePipelineState();
    NSUInteger tgWidth = std::min(cps.maxTotalThreadsPerThreadgroup, cmdEncoder->getMTLDevice().maxThreadsPerThreadgroup.width);
    NSUInteger tgCount = numIndices / tgWidth;

    MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
    id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandConvertUint8Indices);
    state.bindPipeline(mtlComputeEnc, cps);
    state.bindBuffer(mtlComputeEnc, ibb.mtlBuffer, ibb.offset, 0);
    state.bindBuffer(mtlComputeEnc, uint16Buf->_mtlBuffer, uint16Buf->_offset, 1);

    // Run as many full threadgroups as will fit into the buffer content.
    if (tgCount > 0) {
        [mtlComputeEnc dispatchThreadgroups: MTLSizeMake(tgCount, 1, 1)
                       threadsPerThreadgroup: MTLSizeMake(tgWidth, 1, 1)];
    }

    // If there is left-over buffer content after running full threadgroups, or if the buffer content
    // fits within a single threadgroup, run a single partial threadgroup of the appropriate size.
    auto remainderIndexCount = numIndices % tgWidth;
    if (remainderIndexCount > 0) {
        if (tgCount > 0) {
            const auto indicesConverted = tgCount * tgWidth;
            state.bindBuffer(mtlComputeEnc, ibb.mtlBuffer, ibb.offset + indicesConverted, 0);
            state.bindBuffer(mtlComputeEnc, uint16Buf->_mtlBuffer, uint16Buf->_offset + indicesConverted * 2, 1);
        }
        [mtlComputeEnc dispatchThreadgroups: MTLSizeMake(1, 1, 1)
                       threadsPerThreadgroup: MTLSizeMake(remainderIndexCount, 1, 1)];
    }

    // Running this stage prematurely ended the render pass, so we have to start it up again.
    cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);

    return uint16Buf;
}

void MVKCmdDrawIndexed::encode(MVKCommandEncoder* cmdEncoder) {

	if (_indexCount == 0 || _instanceCount == 0) { return; }	// Nothing to do.

	cmdEncoder->restartMetalRenderPassIfNeeded();

	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;

	// Metal doesn't support triangle fans, so encode it as triangles via an indexed indirect triangles command instead.
	if (pipeline->getVkPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
		encodeIndexedIndirect(cmdEncoder);
		return;
	}

    cmdEncoder->_isIndexedDraw = true;

	MVKPiplineStages stages;
    pipeline->getStages(stages);

    MVKIndexMTLBufferBinding ibb = cmdEncoder->getVkGraphics()._indexBuffer;
    if (ibb.vkIndexType == VK_INDEX_TYPE_UINT8) {
        auto* converted = convertUint8IndexBuffer(cmdEncoder, ibb);
        ibb.mtlBuffer = converted->_mtlBuffer;
        ibb.offset = converted->_offset;
    }

    size_t idxSize = mvkMTLIndexTypeSizeInBytes((MTLIndexType)ibb.mtlIndexType);
    VkDeviceSize idxBuffOffset = ibb.offset + (_firstIndex * idxSize);

    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
	struct {
		uint32_t inControlPointCount = 0;
		uint32_t patchCount = 0;
	} tessParams;
    uint32_t outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        tessParams.inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        tessParams.patchCount = mvkCeilingDivide(_indexCount, tessParams.inControlPointCount) * _instanceCount;
    }
    if (pipeline->needsDrawIdBuffer()) {
        tempDrawIDBuff = cmdEncoder->getTempMTLBuffer(sizeof(uint32_t));

        // Zero for a single draw, or the index of this draw within a vkCmdDrawMulti*EXT() call.
        *(uint32_t*)tempDrawIDBuff->getContents() = _drawIndex;
    }
    for (uint32_t s : stages) {
        auto stage = MVKGraphicsStage(s);
        id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;
        cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal

		if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

        switch (stage) {
            case kMVKGraphicsStageVertex: {
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                if (pipeline->needsVertexOutputBuffer()) {
                    vtxOutBuff = cmdEncoder->getTempMTLBuffer(_indexCount * _instanceCount * 4 * dvcLimits.maxVertexOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                }
                if (pipeline->needsDrawIdBuffer()) {
                    [mtlTessCtlEncoder setBuffer: tempDrawIDBuff->_mtlBuffer
                                          offset: tempDrawIDBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                }
				[mtlTessCtlEncoder setBuffer: ibb.mtlBuffer
                                      offset: idxBuffOffset
                                     atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Index]];
				[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(_vertexOffset, _firstInstance, _indexCount, _instanceCount)];
				// If there are vertex bindings with a zero vertex divisor, I need to offset them by
				// _firstInstance * stride, since that is the expected behaviour for a divisor of 0.
                cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
				id<MTLComputePipelineState> vtxState = ibb.mtlIndexType == MTLIndexTypeUInt16 ? pipeline->getTessVertexStageIndex16State() : pipeline->getTessVertexStageIndex32State();
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(_indexCount, _instanceCount, 1)
					             threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(_indexCount, vtxState.threadExecutionWidth), _instanceCount, 1)
                                      threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
				}
                break;
			}
            case kMVKGraphicsStageTessControl: {
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                if (pipeline->needsTessCtlOutputBuffer()) {
                    tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * tessParams.patchCount * 4 * dvcLimits.maxTessellationControlPerVertexOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                          offset: tcOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::Output]];
                }
                if (pipeline->needsTessCtlPatchOutputBuffer()) {
                    tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * 4 * dvcLimits.maxTessellationControlPerPatchOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                          offset: tcPatchOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::PatchOutput]];
                }
                tcLevelBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * sizeof(MTLQuadTessellationFactorsHalf), true);
                [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                      offset: tcLevelBuff->_offset
                                     atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::TessLevel]];
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &tessParams,
                                            sizeof(tessParams),
                                            pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::IndirectParams]);
                if (pipeline->needsVertexOutputBuffer()) {
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding)];
                }
				// The vertex shader produced output in the correct order, so there's no need to use
				// an index buffer here.
				NSUInteger sgSize = pipeline->getTessControlStageState().threadExecutionWidth;
				NSUInteger wgSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
				while (wgSize > dvcLimits.maxComputeWorkGroupSize[0]) {
					sgSize >>= 1;
					wgSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
				}
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(tessParams.patchCount * outControlPointCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(tessParams.patchCount * outControlPointCount, wgSize), 1, 1)
									  threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
				}
                // Running this stage prematurely ended the render pass, so we have to start it up again.
                // TODO: On iOS, maybe we could use a tile shader to avoid this.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
                break;
			}
            case kMVKGraphicsStageRasterization:
                if (pipeline->isTessellationPipeline()) {
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
                                                                offset: tcOutBuff->_offset
                                                               atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding)];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
                                                                offset: tcPatchOutBuff->_offset
                                                               atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding)];
                    }
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
                                                            offset: tcLevelBuff->_offset
                                                           atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding)];
                    [cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
                                                                        offset: tcLevelBuff->_offset
                                                                instanceStride: 0];
                    // The tessellation control shader produced output in the correct order, so there's no need to use
                    // an index buffer here.
                    [cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
                                                    patchStart: 0
                                                    patchCount: tessParams.patchCount
                                              patchIndexBuffer: nil
                                        patchIndexBufferOffset: 0
                                                 instanceCount: 1
                                                  baseInstance: 0];
                } else {
                    MVKRenderSubpass* subpass = cmdEncoder->getSubpass();
                    uint32_t viewCount = subpass->isMultiview() ? subpass->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
                    uint32_t instanceCount = _instanceCount * viewCount;
                    cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
                    if (pipeline->needsDrawIdBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tempDrawIDBuff->_mtlBuffer
                                                                offset: tempDrawIDBuff->_offset
                                                               atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                    }
                    if (mtlFeats.baseVertexInstanceDrawing) {
                        [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                                  indexCount: _indexCount
                                                                   indexType: (MTLIndexType)ibb.mtlIndexType
                                                                 indexBuffer: ibb.mtlBuffer
                                                           indexBufferOffset: idxBuffOffset
                                                               instanceCount: instanceCount
                                                                  baseVertex: _vertexOffset
                                                                baseInstance: _firstInstance];
                    } else {
                        [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                                  indexCount: _indexCount
                                                                   indexType: (MTLIndexType)ibb.mtlIndexType
                                                                 indexBuffer: ibb.mtlBuffer
                                                           indexBufferOffset: idxBuffOffset
                                                               instanceCount: instanceCount];
                    }
                }
                break;
        }
    }
}


// This is totally arbitrary, but we're forced to do this because we don't know how many vertices
// there are at encoding time. And this will probably be inadequate for large instanced draws.
// TODO: Consider breaking up such draws using different base instance values. But this will
// require yet more munging of the indirect buffers...
static const uint32_t kMVKMaxDrawIndirectVertexCount = 1024 * KIBI;

// Converts the indirect buffers of the indirect-count draws that follow 'first' in the command list, up to the
// next command that could change buffer contents or leave the render pass, in a single compute encoder.
// Without this, each indirect-count draw ends the Metal render encoder, runs one conversion kernel, and starts a
// new render encoder, which on a tile-based GPU stores and reloads every attachment each time.
static const uint32_t kMVKMaxBatchedCountConversions = 8192;
#if MVK_MACOS
// Indexed indirect-count draws of at least this many entries run from a Metal indirect command buffer (ICB) that a compute
// kernel fills with only the real draws. Smaller ones expand to direct draws, which cost less in total.
static const uint32_t kMVKICBMinDrawCount = 129;
static const uint32_t kMVKICBSlots = 31;					// the most buffers an ICB command can bind per stage
static const uint32_t kMVKICBInlineBytesPerDraw = 2048;		// room for the inline data a draw binds

// The state of one draw as the ICB kernel reads it. Keep in sync with MVKICBEntry in the kernel source.
struct MVKICBBindingRec { uint64_t address; uint32_t slot; uint32_t pad; };
struct MVKICBEntryRec {
	uint32_t enabled;		// zero: the kernel encodes nothing and the draw runs as direct draws
	uint32_t primType;
	uint32_t indexIs16;
	uint32_t drawIdSlot;	// vertex buffer slot of the draw ID, or ~0
	uint64_t indexAddress;
	uint32_t vtxCount;
	uint32_t fragCount;
	MVKICBBindingRec vtx[kMVKICBSlots];
	MVKICBBindingRec frag[kMVKICBSlots];
};
static_assert(sizeof(MVKICBEntryRec) == 1024, "MVKICBEntryRec must match the kernel's MVKICBEntry");

// Creating an ICB costs milliseconds, and each stays in use until the GPU finishes the Metal command buffer, so a command buffer
// takes a few large ICB chunks and gives each batch a range of commands in the current one. Finished chunks are kept for reuse.
static const uint32_t kMVKICBChunkCapacity = 16384;
static const size_t kMVKICBMaxPooledChunks = 24;
static std::mutex gICBPoolMutex;
static std::unordered_map<uintptr_t, std::vector<id<MTLIndirectCommandBuffer>>> gICBPool;

static id<MTLIndirectCommandBuffer> acquireICBChunk(id<MTLDevice> device) API_AVAILABLE(macos(13.0)) {
	{
		std::lock_guard<std::mutex> lock(gICBPoolMutex);
		auto& free = gICBPool[(uintptr_t)device];
		if ( !free.empty() ) { id<MTLIndirectCommandBuffer> icb = free.back(); free.pop_back(); return icb; }
	}
	MTLIndirectCommandBufferDescriptor* desc = [MTLIndirectCommandBufferDescriptor new];
	desc.commandTypes = MTLIndirectCommandTypeDrawIndexed;
	desc.inheritPipelineState = YES;
	desc.inheritBuffers = NO;
	desc.maxVertexBufferBindCount = kMVKICBSlots;
	desc.maxFragmentBufferBindCount = kMVKICBSlots;
	id<MTLIndirectCommandBuffer> icb = [device newIndirectCommandBufferWithDescriptor: desc maxCommandCount: kMVKICBChunkCapacity options: MTLResourceStorageModePrivate];
	[desc release];
	return icb;
}

static void recycleICBChunk(id<MTLDevice> device, id<MTLIndirectCommandBuffer> icb) API_AVAILABLE(macos(13.0)) {
	{
		std::lock_guard<std::mutex> lock(gICBPoolMutex);
		auto& free = gICBPool[(uintptr_t)device];
		if (free.size() < kMVKICBMaxPooledChunks) { free.push_back(icb); return; }
	}
	[icb release];
}

// Writes the state of the draw being encoded into its ICB record, and returns the buffers the ICB commands will read, which the
// render encoder must be told to make resident. Returns false, leaving the record disabled, if the state cannot be expressed as ICB commands.
static bool fillICBEntry(MVKCommandEncoder* cmdEncoder, MVKGraphicsPipeline* pipeline, const MVKIndexMTLBufferBinding& ibb,
						 const MVKCommandEncoder::BatchedICB& rec, MVKSmallVector<id<MTLBuffer>, 64> resident[2]) {
	if ( !pipeline->hasValidMTLPipelineStates() || !pipeline->supportsIndirectCommandBuffers() ) { return false; }
	if (ibb.mtlIndexType != MTLIndexTypeUInt16 && ibb.mtlIndexType != MTLIndexTypeUInt32) { return false; }
	auto& gfx = cmdEncoder->getMtlGraphics();
	if (gfx.getPrimitiveType() > MTLPrimitiveTypeTriangleStrip) { return false; }	// the kernel handles points, lines and triangles
	// Besides the draw ID, no volatile implicit buffer may be bound per draw.
	for (MVKShaderStage st : {kMVKShaderStageVertex, kMVKShaderStageFragment}) {
		for (MVKImplicitBuffer b : pipeline->getImplicitBuffers(st).needed.removingAll(MVKNonVolatileImplicitBuffers)) {
			if (b != MVKImplicitBuffer::DrawId) { return false; }
		}
	}
	uint32_t drawIdSlot = pipeline->needsDrawIdBuffer() ? pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId] : ~0u;

	MVKICBEntryRec tmp = {};
	tmp.primType = (uint32_t)gfx.getPrimitiveType();
	tmp.indexIs16 = ibb.mtlIndexType == MTLIndexTypeUInt16;
	tmp.indexAddress = ibb.mtlBuffer.gpuAddress + ibb.offset;
	tmp.drawIdSlot = drawIdSlot;
	uint8_t* bytesDst = (uint8_t*)rec.bytesBuffer.contents + rec.bytesOffset;
	uint64_t bytesGpu = rec.bytesBuffer.gpuAddress + rec.bytesOffset;
	uint32_t bytesUsed = 0;
	for (int st = 0; st < 2; st++) {
		const MVKStageResourceBits& exists = st == 0 ? gfx._exists.vertex() : gfx._exists.fragment();
		const MVKStageResourceBindings& bindings = st == 0 ? gfx._bindings.vertex() : gfx._bindings.fragment();
		MVKICBBindingRec* out = st == 0 ? tmp.vtx : tmp.frag;
		uint32_t& count = st == 0 ? tmp.vtxCount : tmp.fragCount;
		for (uint32_t i = 0; i < kMVKMaxBufferCount; i++) {
			if ( !exists.buffers.get(i) || (st == 0 && i == drawIdSlot) ) { continue; }
			const MVKStageResourceBindings::Buffer& b = bindings.buffers[i];
			if (b.buffer) {
				if (b.offset >> 32) { return false; }	// a vertex buffer bound with a dynamic stride
				out[count++] = { b.buffer.gpuAddress + b.offset, i, 0 };
				resident[st].push_back(b.buffer);
			} else if (b == MVKStageResourceBindings::NullBuffer()) {
				continue;
			} else if (id<MTLBuffer> tempBuf = gfx._boundTemp[st][i].buffer) {	// large inline data, bound from a temporary buffer
				out[count++] = { tempBuf.gpuAddress + gfx._boundTemp[st][i].offset, i, 0 };
				resident[st].push_back(tempBuf);
			} else {																// inline data from setBytes
				const auto& bytes = gfx._boundBytes[st][i];
				uint32_t size = (uint32_t)bytes.size();
				if (size == 0) { return false; }
				uint32_t at = mvkAlignByteCount(bytesUsed, 16);
				if (at + size > kMVKICBInlineBytesPerDraw) { return false; }
				memcpy(bytesDst + at, bytes.data(), size);
				out[count++] = { bytesGpu + at, i, 0 };
				bytesUsed = at + size;
			}
		}
	}
	if (bytesUsed > 0) { resident[0].push_back(rec.bytesBuffer); resident[1].push_back(rec.bytesBuffer); }
	MVKICBEntryRec* entry = (MVKICBEntryRec*)rec.entry;
	tmp.enabled = 0;
	memcpy(entry, &tmp, sizeof(tmp));
	entry->enabled = 1;
	return true;
}
#endif
static void encodeBatchedIndirectCountConversions(MVKCommandEncoder* cmdEncoder, MVKCommand* first) {
	struct Entry { MVKCommand* cmd; MVKIndirectCountParams params; };
	MVKSmallVector<Entry, 256> batch;
	for (MVKCommand* cmd = first; cmd; cmd = cmd->_next) {
		if (cmd != first && cmd->endsIndirectCountBatch()) { break; }
		MVKIndirectCountParams params;
		if ( !cmd->getIndirectCountParams(params) ) { continue; }
		if (cmdEncoder->getBatchedCountConversion(cmd)) { continue; }	// already converted, such as when a multiview pass is encoded again
		batch.push_back({cmd, params});
		if (batch.size() >= kMVKMaxBatchedCountConversions) { break; }
	}
	if (batch.empty()) { return; }

#if MVK_MACOS
	// Plan an ICB for the indexed entries that are large enough. The draw state is not known yet: each draw writes it into its
	// record when it is encoded, and the kernel, which runs on the GPU after all encoding is done, reads it from there.
	struct ICBPlan { size_t entry; uint32_t base; uint32_t slot; };
	MVKSmallVector<ICBPlan, 64> icbPlans;
	id<MTLIndirectCommandBuffer> icb = nil;
	const MVKMTLBufferAllocation* icbRange = nullptr;
	const MVKMTLBufferAllocation* icbContainer = nullptr;
	const MVKMTLBufferAllocation* icbEntries = nullptr;
	const MVKMTLBufferAllocation* icbBytes = nullptr;
	const MVKMTLBufferAllocation* icbDrawIds = nullptr;
	uint32_t icbChunkBase = 0;
	if (@available(macOS 13.0, *)) {
		if ([cmdEncoder->getMTLDevice() supportsFamily: MTLGPUFamilyApple7] && !(cmdEncoder->getSubpass()->isMultiview() && cmdEncoder->getPhysicalDevice()->canUseInstancingForMultiview())) {
			uint32_t total = 0, maxDraws = 0;
			for (size_t i = 0; i < batch.size(); i++) {
				const MVKIndirectCountParams& p = batch[i].params;
				if (p.indexed && p.drawCount >= kMVKICBMinDrawCount && total + p.drawCount <= kMVKICBChunkCapacity) {
					icbPlans.push_back({i, total, (uint32_t)icbPlans.size()});
					total += p.drawCount;
					maxDraws = std::max(maxDraws, p.drawCount);
				}
			}
			if (total > 0) {
				if (cmdEncoder->_icbChunk == nil || cmdEncoder->_icbChunkUsed + total > kMVKICBChunkCapacity) {
					cmdEncoder->_icbChunk = acquireICBChunk(cmdEncoder->getMTLDevice());	// owned by the completion handler below
					cmdEncoder->_icbChunkUsed = 0;
					id<MTLDevice> mtlDev = cmdEncoder->getMTLDevice();
					id<MTLIndirectCommandBuffer> chunk = cmdEncoder->_icbChunk;
					if (chunk) { cmdEncoder->addCompletedHandler(^(id<MTLCommandBuffer> mcb) { recycleICBChunk(mtlDev, chunk); }); }
				}
				icb = cmdEncoder->_icbChunk;
				icbChunkBase = cmdEncoder->_icbChunkUsed;
				if (icb) { cmdEncoder->_icbChunkUsed += total; }
				if (icb) {
					size_t n = icbPlans.size();
					icbRange = cmdEncoder->getTempMTLBuffer(sizeof(MTLIndirectCommandBufferExecutionRange) * n, true);
					icbContainer = cmdEncoder->getTempMTLBuffer(sizeof(MTLResourceID), false);
					icbEntries = cmdEncoder->getTempMTLBuffer(sizeof(MVKICBEntryRec) * n, false);
					icbBytes = cmdEncoder->getTempMTLBuffer(kMVKICBInlineBytesPerDraw * n, false);
					icbDrawIds = cmdEncoder->getTempMTLBuffer(sizeof(uint32_t) * maxDraws, false);
					*(MTLResourceID*)icbContainer->getContents() = icb.gpuResourceID;
					memset(icbEntries->getContents(), 0, sizeof(MVKICBEntryRec) * n);
					uint32_t* ids = (uint32_t*)icbDrawIds->getContents();
					for (uint32_t k = 0; k < maxDraws; k++) { ids[k] = k; }
				} else {
					icbPlans.clear();
				}
			}
		}
	}
	size_t nextPlan = 0;
#endif

	cmdEncoder->encodeStoreActions(true);
	auto* computeEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
#if MVK_MACOS
	if (icb) { [computeEncoder useResource: icb usage: MTLResourceUsageRead | MTLResourceUsageWrite]; }
#endif
	for (size_t entryIdx = 0; entryIdx < batch.size(); entryIdx++) {
		auto& entry = batch[entryIdx];
		const MVKIndirectCountParams& p = entry.params;
		VkDeviceSize commandSize = p.indexed ? sizeof(MTLDrawIndexedPrimitivesIndirectArguments) : sizeof(MTLDrawPrimitivesIndirectArguments);
		auto* convertedBuffer = cmdEncoder->getTempMTLBuffer(commandSize * p.drawCount, true);
		id<MTLComputePipelineState> pipeline = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectCountConvertBuffersMTLComputePipelineState(p.indexed);
		uint32_t indirectStride = p.indirectStride;
		uint32_t drawCount = p.drawCount;
		state.bindPipeline(computeEncoder, pipeline);
		state.bindBuffer(computeEncoder, p.indirectBuffer, p.indirectOffset, 0);
		state.bindBuffer(computeEncoder, convertedBuffer->_mtlBuffer, convertedBuffer->_offset, 1);
		state.bindStructBytes(computeEncoder, &indirectStride, 2);
		state.bindStructBytes(computeEncoder, &drawCount, 3);
		state.bindBuffer(computeEncoder, p.countBuffer, p.countOffset, 4);
		NSUInteger threadWidth = pipeline.threadExecutionWidth;
		if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
			[computeEncoder dispatchThreads: MTLSizeMake(drawCount, 1, 1)
					  threadsPerThreadgroup: MTLSizeMake(threadWidth, 1, 1)];
		} else {
			[computeEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(drawCount, threadWidth), 1, 1)
						   threadsPerThreadgroup: MTLSizeMake(threadWidth, 1, 1)];
		}
#if MVK_MACOS
		if (nextPlan < icbPlans.size() && icbPlans[nextPlan].entry == entryIdx) {
			const ICBPlan& plan = icbPlans[nextPlan++];
			id<MTLComputePipelineState> icbPipelineState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndexedIndirectCountToICBMTLComputePipelineState();
			uint32_t slot = plan.slot, base = icbChunkBase + plan.base;
			NSUInteger entryOffset = icbEntries->_offset + slot * sizeof(MVKICBEntryRec);
			state.bindPipeline(computeEncoder, icbPipelineState);
			state.bindBuffer(computeEncoder, convertedBuffer->_mtlBuffer, convertedBuffer->_offset, 0);
			state.bindBuffer(computeEncoder, p.countBuffer, p.countOffset, 1);
			state.bindStructBytes(computeEncoder, &drawCount, 2);
			state.bindBuffer(computeEncoder, icbContainer->_mtlBuffer, icbContainer->_offset, 3);
			state.bindBuffer(computeEncoder, icbRange->_mtlBuffer, icbRange->_offset, 5);
			state.bindStructBytes(computeEncoder, &slot, 6);
			state.bindStructBytes(computeEncoder, &base, 7);
			state.bindBuffer(computeEncoder, icbEntries->_mtlBuffer, entryOffset, 8);
			state.bindBuffer(computeEncoder, icbDrawIds->_mtlBuffer, icbDrawIds->_offset, 9);
			NSUInteger icbWidth = icbPipelineState.threadExecutionWidth;
			if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
				[computeEncoder dispatchThreads: MTLSizeMake(drawCount, 1, 1) threadsPerThreadgroup: MTLSizeMake(icbWidth, 1, 1)];
			} else {
				[computeEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(drawCount, icbWidth), 1, 1) threadsPerThreadgroup: MTLSizeMake(icbWidth, 1, 1)];
			}
			MVKCommandEncoder::BatchedICB rec;
			rec.icb = icb;
			rec.rangeBuffer = icbRange->_mtlBuffer;
			rec.rangeOffset = icbRange->_offset + slot * sizeof(MTLIndirectCommandBufferExecutionRange);
			rec.entry = (char*)icbEntries->getContents() + slot * sizeof(MVKICBEntryRec);
			rec.bytesBuffer = icbBytes->_mtlBuffer;
			rec.bytesOffset = icbBytes->_offset + slot * kMVKICBInlineBytesPerDraw;
			rec.drawIdBuffer = icbDrawIds->_mtlBuffer;
			rec.drawIdOffset = icbDrawIds->_offset;
			cmdEncoder->setBatchedICB(entry.cmd, rec);
		}
#endif
		cmdEncoder->setBatchedCountConversion(entry.cmd, convertedBuffer);
	}
	cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
}

static const MVKMTLBufferAllocation* encodeIndirectCountConversion(
		MVKCommandEncoder* cmdEncoder,
		MVKCommand* cmd,
		id<MTLBuffer> indirectBuffer,
		VkDeviceSize indirectBufferOffset,
		uint32_t indirectBufferStride,
		id<MTLBuffer> countBuffer,
		VkDeviceSize countBufferOffset,
		uint32_t drawCount,
		bool indexed) {
	if (auto* batched = cmdEncoder->getBatchedCountConversion(cmd)) { return batched; }
	encodeBatchedIndirectCountConversions(cmdEncoder, cmd);
	if (auto* batched = cmdEncoder->getBatchedCountConversion(cmd)) { return batched; }

	VkDeviceSize commandSize = indexed ? sizeof(MTLDrawIndexedPrimitivesIndirectArguments) : sizeof(MTLDrawPrimitivesIndirectArguments);
	auto* convertedBuffer = cmdEncoder->getTempMTLBuffer(commandSize * drawCount, true);

	cmdEncoder->encodeStoreActions(true);
	auto* computeEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	id<MTLComputePipelineState> pipeline = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectCountConvertBuffersMTLComputePipelineState(indexed);
	state.bindPipeline(computeEncoder, pipeline);
	state.bindBuffer(computeEncoder, indirectBuffer, indirectBufferOffset, 0);
	state.bindBuffer(computeEncoder, convertedBuffer->_mtlBuffer, convertedBuffer->_offset, 1);
	state.bindStructBytes(computeEncoder, &indirectBufferStride, 2);
	state.bindStructBytes(computeEncoder, &drawCount, 3);
	state.bindBuffer(computeEncoder, countBuffer, countBufferOffset, 4);

	NSUInteger threadWidth = pipeline.threadExecutionWidth;
	if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
		[computeEncoder dispatchThreads: MTLSizeMake(drawCount, 1, 1)
						threadsPerThreadgroup: MTLSizeMake(threadWidth, 1, 1)];
	} else {
		[computeEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(drawCount, threadWidth), 1, 1)
						  threadsPerThreadgroup: MTLSizeMake(threadWidth, 1, 1)];
	}
	cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
	return convertedBuffer;
}

typedef struct MVKIndirectZeroDivisorVertexBuffer {
	uint32_t mtlBufferIndex;
	uint32_t stride;
	const MVKMTLBufferAllocation* allocation;
} MVKIndirectZeroDivisorVertexBuffer;

typedef MVKSmallVector<MVKIndirectZeroDivisorVertexBuffer, 4> MVKIndirectZeroDivisorVertexBuffers;

static MVKIndirectZeroDivisorVertexBuffers encodeIndirectZeroDivisorVertexBufferCopies(
		MVKCommandEncoder* cmdEncoder,
		MVKGraphicsPipeline* pipeline,
		id<MTLBuffer> indirectBuffer,
		VkDeviceSize indirectBufferOffset,
		uint32_t indirectBufferStride,
		uint32_t drawCount,
		bool indexed) {
	MVKIndirectZeroDivisorVertexBuffers copiedBuffers;
	auto bindings = pipeline->getZeroDivisorVertexBindings();
	if (drawCount == 0 || bindings.size() == 0) { return copiedBuffers; }

	cmdEncoder->encodeStoreActions(true);
	auto* computeEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	id<MTLComputePipelineState> computePipeline = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectCopyZeroDivisorVertexBuffersMTLComputePipelineState();
	uint32_t baseInstanceOffset = indexed ? 16 : 12;
	state.bindPipeline(computeEncoder, computePipeline);

	for (const auto& binding : bindings) {
		uint32_t sourceBinding = binding.first;
		VkDeviceSize translationOffset = 0;
		for (const auto& translatedBinding : pipeline->getTranslatedVertexBindings()) {
			if (translatedBinding.translationBinding == binding.first) {
				sourceBinding = translatedBinding.binding;
				translationOffset = translatedBinding.translationOffset;
				break;
			}
		}
		const auto& sourceBuffer = cmdEncoder->getVkGraphics()._vertexBuffers[sourceBinding];
		uint32_t vertexStride = pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::VertexStride) ? sourceBuffer.stride : binding.second;
		if (vertexStride == 0) { continue; }
		if (sourceBuffer.mtlBuffer == nil) { continue; }

		auto* copiedBuffer = cmdEncoder->getTempMTLBuffer((NSUInteger)drawCount * vertexStride, true);
		copiedBuffers.push_back({pipeline->getMetalBufferIndexForVertexAttributeBinding(binding.first), vertexStride, copiedBuffer});
		state.bindBuffer(computeEncoder, indirectBuffer, indirectBufferOffset, 0);
		state.bindBuffer(computeEncoder, sourceBuffer.mtlBuffer, sourceBuffer.offset + translationOffset, 1);
		state.bindBuffer(computeEncoder, copiedBuffer->_mtlBuffer, copiedBuffer->_offset, 2);
		state.bindStructBytes(computeEncoder, &indirectBufferStride, 3);
		state.bindStructBytes(computeEncoder, &drawCount, 4);
		state.bindStructBytes(computeEncoder, &vertexStride, 5);
		state.bindStructBytes(computeEncoder, &baseInstanceOffset, 6);
		if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
			[computeEncoder dispatchThreads: MTLSizeMake((NSUInteger)drawCount * vertexStride, 1, 1)
					 threadsPerThreadgroup: MTLSizeMake(computePipeline.threadExecutionWidth, 1, 1)];
		} else {
			[computeEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>((NSUInteger)drawCount * vertexStride, computePipeline.threadExecutionWidth), 1, 1)
					  threadsPerThreadgroup: MTLSizeMake(computePipeline.threadExecutionWidth, 1, 1)];
		}
	}

	cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
	return copiedBuffers;
}

static void bindIndirectZeroDivisorVertexBuffers(MVKCommandEncoder* cmdEncoder,
																					 MVKGraphicsStage stage,
																					 const MVKIndirectZeroDivisorVertexBuffers& copiedBuffers,
																					 uint32_t drawIndex) {
	for (const auto& copiedBuffer : copiedBuffers) {
		NSUInteger offset = copiedBuffer.allocation->_offset + (NSUInteger)drawIndex * copiedBuffer.stride;
		switch (stage) {
			case kMVKGraphicsStageVertex:
				[cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBuffer: copiedBuffer.allocation->_mtlBuffer
																								 offset: offset
																								atIndex: copiedBuffer.mtlBufferIndex];
				break;
			case kMVKGraphicsStageRasterization:
				[cmdEncoder->_mtlRenderEncoder setVertexBuffer: copiedBuffer.allocation->_mtlBuffer
																							  offset: offset
																							 atIndex: copiedBuffer.mtlBufferIndex];
				break;
			default:
				assert(false);
				break;
		}
	}
}

#pragma mark -
#pragma mark MVKCmdDrawIndirect

VkResult MVKCmdDrawIndirect::setContent(MVKCommandBuffer* cmdBuff,
										VkBuffer buffer,
										VkDeviceSize offset,
										uint32_t drawCount,
										uint32_t stride) {
	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
	_mtlIndirectBuffer = mvkBuffer->getMTLBuffer();
	_mtlIndirectBufferOffset = mvkBuffer->getMTLBufferOffset() + offset;
	_mtlIndirectBufferStride = stride;
	_drawCount = drawCount;
	_mtlCountBuffer = nil;
	_mtlCountBufferOffset = 0;

    // Validate
	auto& mtlFeats = cmdBuff->getMetalFeatures();
    if ( !mtlFeats.indirectDrawing ) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndirect(): The current device does not support indirect drawing.");
    }
	if (cmdBuff->_lastTessellationPipeline && !mtlFeats.indirectTessellationDrawing) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndirect(): The current device does not support indirect tessellated drawing.");
	}

	return VK_SUCCESS;
}

VkResult MVKCmdDrawIndirect::setContent(MVKCommandBuffer* cmdBuff,
											VkBuffer buffer,
											VkDeviceSize offset,
											VkBuffer countBuffer,
											VkDeviceSize countBufferOffset,
											uint32_t maxDrawCount,
											uint32_t stride) {
	VkResult result = setContent(cmdBuff, buffer, offset, maxDrawCount, stride);
	if (result != VK_SUCCESS) {
		return result;
	}
	MVKBuffer* mvkCountBuffer = (MVKBuffer*)countBuffer;
	_mtlCountBuffer = mvkCountBuffer->getMTLBuffer();
	_mtlCountBufferOffset = mvkCountBuffer->getMTLBufferOffset() + countBufferOffset;
	return VK_SUCCESS;
}

// Populates and encodes a MVKCmdDrawIndexedIndirect command, after populating indexed indirect buffers.
void MVKCmdDrawIndirect::encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder,
														 id<MTLBuffer> indirectBuffer,
														 VkDeviceSize indirectBufferOffset,
														 uint32_t indirectBufferStride) {

	// Create an indexed indirect buffer to be populated from the non-indexed indirect buffer.
	uint32_t indirectIdxBuffStride = sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
	auto* indirectIdxBuff = cmdEncoder->getTempMTLBuffer(indirectIdxBuffStride * _drawCount, true);

	// Create an index buffer to be populated with synthetic indexes.
	MTLIndexType mtlIdxType = MTLIndexTypeUInt32;
	auto* vtxIdxBuff = cmdEncoder->getTempMTLBuffer(mvkMTLIndexTypeSizeInBytes(mtlIdxType) * kMVKMaxDrawIndirectVertexCount, true);
	MVKIndexMTLBufferBinding ibb;
	ibb.mtlIndexType = mtlIdxType;
	ibb.mtlBuffer = vtxIdxBuff->_mtlBuffer;
	ibb.offset = vtxIdxBuff->_offset;
	ibb.size = vtxIdxBuff->_length;

	// Schedule a compute action to populate indexed buffers from non-indexed buffers.
	cmdEncoder->encodeStoreActions(true);
	id<MTLComputeCommandEncoder> mtlConvertEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectPopulateIndexesMTLComputePipelineState();
	state.bindPipeline(mtlConvertEncoder, mtlConvertState);
	state.bindBuffer(mtlConvertEncoder, indirectBuffer,              indirectBufferOffset,      0);
	state.bindBuffer(mtlConvertEncoder, indirectIdxBuff->_mtlBuffer, indirectIdxBuff->_offset, 1);
	state.bindStructBytes(mtlConvertEncoder, &indirectBufferStride,     2);
	state.bindStructBytes(mtlConvertEncoder, &_drawCount,               3);
	state.bindBuffer(mtlConvertEncoder, ibb.mtlBuffer, ibb.offset, 4);
	if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
		[mtlConvertEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
					 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
	} else {
		[mtlConvertEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
						  threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
	}
	// Switch back to rendering now.
	cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);

	MVKCmdDrawIndexedIndirect diiCmd;
	diiCmd.setContent(cmdEncoder->_cmdBuffer,
					  indirectIdxBuff->_mtlBuffer,
					  indirectIdxBuff->_offset,
					  _drawCount,
					  indirectIdxBuffStride);
	diiCmd.encode(cmdEncoder, ibb);
}

void MVKCmdDrawIndirect::encode(MVKCommandEncoder* cmdEncoder) {

	cmdEncoder->restartMetalRenderPassIfNeeded();
	id<MTLBuffer> indirectBuffer = _mtlIndirectBuffer;
	VkDeviceSize indirectBufferOffset = _mtlIndirectBufferOffset;
	uint32_t indirectBufferStride = _mtlIndirectBufferStride;

	if (_mtlCountBuffer && _drawCount > 0) {
		auto* convertedBuffer = encodeIndirectCountConversion(cmdEncoder,
				this,
				indirectBuffer,
				indirectBufferOffset,
				indirectBufferStride,
				_mtlCountBuffer,
				_mtlCountBufferOffset,
				_drawCount,
				false);
		indirectBuffer = convertedBuffer->_mtlBuffer;
		indirectBufferOffset = convertedBuffer->_offset;
		indirectBufferStride = sizeof(MTLDrawPrimitivesIndirectArguments);
	}

	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;
	// Metal doesn't support triangle fans, so encode it as indexed indirect triangles instead.
	if (pipeline->getVkPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
		encodeIndexedIndirect(cmdEncoder, indirectBuffer, indirectBufferOffset, indirectBufferStride);
		return;
	}

	auto zeroDivisorBuffers = encodeIndirectZeroDivisorVertexBufferCopies(cmdEncoder,
			pipeline,
			indirectBuffer,
			indirectBufferOffset,
			indirectBufferStride,
			_drawCount,
			false);

    cmdEncoder->_isIndexedDraw = false;

    bool needsInstanceAdjustment = cmdEncoder->getSubpass()->isMultiview() &&
                                   cmdEncoder->getPhysicalDevice()->canUseInstancingForMultiview();
    // The indirect calls for dispatchThreadgroups:... and drawPatches:... have different formats.
    // We have to convert from the drawPrimitives:... format to them.
    // While we're at it, we can create the temporary output buffers once and reuse them
    // for each draw.
    const MVKMTLBufferAllocation* tempIndirectBuff = nullptr;
	const MVKMTLBufferAllocation* tcParamsBuff = nullptr;
    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
    uint32_t patchCount = 0, vertexCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
	VkDeviceSize paramsIncr = 0;

    id<MTLBuffer> mtlIndBuff = indirectBuffer;
    VkDeviceSize mtlIndBuffOfst = indirectBufferOffset;
    VkDeviceSize mtlParmBuffOfst = 0;
    NSUInteger vtxThreadExecWidth = 0;
    NSUInteger tcWorkgroupSize = 0;

    if (pipeline->isTessellationPipeline()) {
        // We can't read the indirect buffer CPU-side, since it may change between
        // encoding and execution. So we don't know how big to make the buffers.
        // We must assume an arbitrarily large number of vertices may be submitted.
        // But not too many, or we'll exhaust available VRAM.
        inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        vertexCount = kMVKMaxDrawIndirectVertexCount;
        patchCount = mvkCeilingDivide(vertexCount, inControlPointCount);
        VkDeviceSize indirectSize = (2 * sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments) + sizeof(MTLStageInRegionIndirectArguments)) * _drawCount;
		paramsIncr = std::max((size_t)dvcLimits.minUniformBufferOffsetAlignment, sizeof(uint32_t) * 2);
		VkDeviceSize paramsSize = paramsIncr * _drawCount;
        tempIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize, true);
        mtlIndBuff = tempIndirectBuff->_mtlBuffer;
        mtlIndBuffOfst = tempIndirectBuff->_offset;
		tcParamsBuff = cmdEncoder->getTempMTLBuffer(paramsSize, true);
        mtlParmBuffOfst = tcParamsBuff->_offset;
        if (pipeline->needsVertexOutputBuffer()) {
            vtxOutBuff = cmdEncoder->getTempMTLBuffer(vertexCount * 4 * dvcLimits.maxVertexOutputComponents, true);
        }
        if (pipeline->needsTessCtlOutputBuffer()) {
            tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * patchCount * 4 * dvcLimits.maxTessellationControlPerVertexOutputComponents, true);
        }
        if (pipeline->needsTessCtlPatchOutputBuffer()) {
            tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(patchCount * 4 * dvcLimits.maxTessellationControlPerPatchOutputComponents, true);
        }
        tcLevelBuff = cmdEncoder->getTempMTLBuffer(patchCount * sizeof(MTLQuadTessellationFactorsHalf), true);

        vtxThreadExecWidth = pipeline->getTessVertexStageState().threadExecutionWidth;
        NSUInteger sgSize = pipeline->getTessControlStageState().threadExecutionWidth;
        tcWorkgroupSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
        while (tcWorkgroupSize > dvcLimits.maxComputeWorkGroupSize[0]) {
            sgSize >>= 1;
            tcWorkgroupSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
        }
    } else if (needsInstanceAdjustment) {
        // In this case, we need to adjust the instance count for the views being drawn.
        VkDeviceSize indirectSize = sizeof(MTLDrawPrimitivesIndirectArguments) * _drawCount;
        tempIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize, true);
        mtlIndBuff = tempIndirectBuff->_mtlBuffer;
        mtlIndBuffOfst = tempIndirectBuff->_offset;
    }

	MVKPiplineStages stages;
    pipeline->getStages(stages);

    if (pipeline->needsDrawIdBuffer()) {
        tempDrawIDBuff = cmdEncoder->getTempMTLBuffer(_drawCount * sizeof(uint32_t));

        auto* drawIDs = (uint32_t*)((char*)[tempDrawIDBuff->_mtlBuffer contents] + tempDrawIDBuff->_offset);
        for (uint32_t i = 0; i < _drawCount; i++) {
            drawIDs[i] = i;
        }
    }
    for (uint32_t drawIdx = 0; drawIdx < _drawCount; drawIdx++) {
        for (uint32_t s : stages) {
            auto stage = MVKGraphicsStage(s);
            id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;
            if (drawIdx == 0 && stage == kMVKGraphicsStageVertex && pipeline->isTessellationPipeline()) {
                // We need the indirect buffers now. This must be done before finalizing
                // draw state, or the pipeline will get overridden. This is a good time
                // to do it, since it will require switching to compute anyway. Do it all
                // at once to get it over with.
				cmdEncoder->encodeStoreActions(true);
				mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
				id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectTessConvertBuffersMTLComputePipelineState(false);
				MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
				state.bindPipeline(mtlTessCtlEncoder, mtlConvertState);
				state.bindBuffer(mtlTessCtlEncoder, indirectBuffer,                indirectBufferOffset,      0);
				state.bindBuffer(mtlTessCtlEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
				state.bindBuffer(mtlTessCtlEncoder, tcParamsBuff->_mtlBuffer,     tcParamsBuff->_offset,     2);
				state.bindStructBytes(mtlTessCtlEncoder, &indirectBufferStride,     3);
				state.bindStructBytes(mtlTessCtlEncoder, &inControlPointCount,      4);
				state.bindStructBytes(mtlTessCtlEncoder, &outControlPointCount,     5);
				state.bindStructBytes(mtlTessCtlEncoder, &_drawCount,               6);
				state.bindStructBytes(mtlTessCtlEncoder, &vtxThreadExecWidth,       7);
				state.bindStructBytes(mtlTessCtlEncoder, &tcWorkgroupSize,          8);
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
									  threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
				}
            } else if (drawIdx == 0 && needsInstanceAdjustment) {
                // Similarly, for multiview, we need to adjust the instance count now.
                // Unfortunately, this requires switching to compute.
                // TODO: Consider using tile shaders to avoid this cost.
				cmdEncoder->encodeStoreActions(true);
				id<MTLComputeCommandEncoder> mtlConvertEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
				id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectConvertBuffersMTLComputePipelineState(false);
				uint32_t viewCount = cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex());
				MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
				state.bindPipeline(mtlConvertEncoder, mtlConvertState);
				state.bindBuffer(mtlConvertEncoder, indirectBuffer,                indirectBufferOffset,      0);
				state.bindBuffer(mtlConvertEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
				state.bindStructBytes(mtlConvertEncoder, &indirectBufferStride,     2);
				state.bindStructBytes(mtlConvertEncoder, &_drawCount,               3);
				state.bindStructBytes(mtlConvertEncoder, &viewCount,                4);
                if (mtlFeats.nonUniformThreadgroups) {
					[mtlConvertEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
					             threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                } else {
                    [mtlConvertEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
                                      threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                }
                // Switch back to rendering now, since we don't have compute stages to run anyway.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
            }

            if (drawIdx == 0 || pipeline->isTessellationPipeline() || needsInstanceAdjustment) {
                cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal
            }

			if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

            switch (stage) {
                case kMVKGraphicsStageVertex:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
					bindIndirectZeroDivisorVertexBuffers(cmdEncoder, stage, zeroDivisorBuffers, drawIdx);
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                              offset: vtxOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                    }
                    if (pipeline->needsDrawIdBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tempDrawIDBuff->_mtlBuffer
                                              offset: tempDrawIDBuff->_offset + drawIdx * sizeof(uint32_t)
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                    }
					// We must assume we can read up to the maximum number of vertices.
					[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(0, 0, vertexCount, vertexCount)];
					[mtlTessCtlEncoder setStageInRegionWithIndirectBuffer: mtlIndBuff
						                             indirectBufferOffset: mtlIndBuffOfst];
					mtlIndBuffOfst += sizeof(MTLStageInRegionIndirectArguments);
					[mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
														 indirectBufferOffset: mtlIndBuffOfst
														threadsPerThreadgroup: MTLSizeMake(vtxThreadExecWidth, 1, 1)];
					mtlIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    break;
                case kMVKGraphicsStageTessControl:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                              offset: tcOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::Output]];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                              offset: tcPatchOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::PatchOutput]];
                    }
                    [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                          offset: tcLevelBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::TessLevel]];
					[mtlTessCtlEncoder setBuffer: tcParamsBuff->_mtlBuffer
										  offset: mtlParmBuffOfst
										 atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::IndirectParams]];
					mtlParmBuffOfst += paramsIncr;
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                              offset: vtxOutBuff->_offset
                                             atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding)];
                    }
                    [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
                                                         indirectBufferOffset: mtlIndBuffOfst
                                                        threadsPerThreadgroup: MTLSizeMake(tcWorkgroupSize, 1, 1)];
                    mtlIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    // Running this stage prematurely ended the render pass, so we have to start it up again.
                    // TODO: On iOS, maybe we could use a tile shader to avoid this.
                    cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
                    break;
                case kMVKGraphicsStageRasterization:
					bindIndirectZeroDivisorVertexBuffers(cmdEncoder, stage, zeroDivisorBuffers, drawIdx);
                    if (pipeline->isTessellationPipeline()) {
						if (mtlFeats.indirectTessellationDrawing) {
							if (pipeline->needsTessCtlOutputBuffer()) {
								[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
																		offset: tcOutBuff->_offset
																	   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding)];
							}
							if (pipeline->needsTessCtlPatchOutputBuffer()) {
								[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
																		offset: tcPatchOutBuff->_offset
																	   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding)];
							}
							[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
																	offset: tcLevelBuff->_offset
																   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding)];
							[cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
																				offset: tcLevelBuff->_offset
																		instanceStride: 0];
							[cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
													  patchIndexBuffer: nil
												patchIndexBufferOffset: 0
														indirectBuffer: mtlIndBuff
												  indirectBufferOffset: mtlIndBuffOfst];
						}

						mtlIndBuffOfst += sizeof(MTLDrawPatchIndirectArguments);
                    } else {
                        if (pipeline->needsDrawIdBuffer()) {
                            [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tempDrawIDBuff->_mtlBuffer
                                                                    offset: tempDrawIDBuff->_offset + drawIdx * sizeof(uint32_t)
                                                                   atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                        }
                        [cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                       indirectBuffer: mtlIndBuff
                                                 indirectBufferOffset: mtlIndBuffOfst];
                        mtlIndBuffOfst += needsInstanceAdjustment ? sizeof(MTLDrawPrimitivesIndirectArguments) : indirectBufferStride;
                    }
                    break;
            }
        }
    }
}


#pragma mark -
#pragma mark MVKCmdDrawIndexedIndirect

typedef struct MVKVertexAdjustments {
	uint8_t mtlIndexType = MTLIndexTypeUInt16;	// Enum must match enum in shader
	bool isMultiView = false;
	bool isTriangleFan = false;
	bool isPrimRestart = true;
	bool isUint8Index = false;
	bool isProvokingVertexLast = false;

	bool needsAdjustment() { return isMultiView || isTriangleFan; }
} MVKVertexAdjustments;

VkResult MVKCmdDrawIndexedIndirect::setContent(MVKCommandBuffer* cmdBuff,
											   VkBuffer buffer,
											   VkDeviceSize offset,
											   uint32_t drawCount,
											   uint32_t stride) {
	auto* mvkBuff = (MVKBuffer*)buffer;
	return setContent(cmdBuff,
					  mvkBuff->getMTLBuffer(),
					  mvkBuff->getMTLBufferOffset() + offset,
					  drawCount,
					  stride);
}

VkResult MVKCmdDrawIndexedIndirect::setContent(MVKCommandBuffer* cmdBuff,
										   id<MTLBuffer> indirectMTLBuff,
										   VkDeviceSize indirectMTLBuffOffset,
										   uint32_t drawCount,
										   uint32_t stride) {
	_mtlIndirectBuffer = indirectMTLBuff;
	_mtlIndirectBufferOffset = indirectMTLBuffOffset;
	_mtlIndirectBufferStride = stride;
	_drawCount = drawCount;
	_mtlCountBuffer = nil;
	_mtlCountBufferOffset = 0;

	// Validate
	auto& mtlFeats = cmdBuff->getMetalFeatures();
	if ( !mtlFeats.indirectDrawing ) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexedIndirect(): The current device does not support indirect drawing.");
	}
	if (cmdBuff->_lastTessellationPipeline && !mtlFeats.indirectTessellationDrawing) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexedIndirect(): The current device does not support indirect tessellated drawing.");
	}

	return VK_SUCCESS;
}

VkResult MVKCmdDrawIndexedIndirect::setContent(MVKCommandBuffer* cmdBuff,
													   VkBuffer buffer,
													   VkDeviceSize offset,
													   VkBuffer countBuffer,
													   VkDeviceSize countBufferOffset,
													   uint32_t maxDrawCount,
													   uint32_t stride) {
	VkResult result = setContent(cmdBuff, buffer, offset, maxDrawCount, stride);
	if (result != VK_SUCCESS) {
		return result;
	}
	MVKBuffer* mvkCountBuffer = (MVKBuffer*)countBuffer;
	_mtlCountBuffer = mvkCountBuffer->getMTLBuffer();
	_mtlCountBufferOffset = mvkCountBuffer->getMTLBufferOffset() + countBufferOffset;
	return VK_SUCCESS;
}

void MVKCmdDrawIndexedIndirect::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->restartMetalRenderPassIfNeeded();
	encode(cmdEncoder, cmdEncoder->getVkGraphics()._indexBuffer);
}

void MVKCmdDrawIndexedIndirect::encode(MVKCommandEncoder* cmdEncoder, const MVKIndexMTLBufferBinding& ibbOrig) {

	id<MTLBuffer> indirectBuffer = _mtlIndirectBuffer;
	VkDeviceSize indirectBufferOffset = _mtlIndirectBufferOffset;
	uint32_t indirectBufferStride = _mtlIndirectBufferStride;
	if (_mtlCountBuffer && _drawCount > 0) {
		auto* convertedBuffer = encodeIndirectCountConversion(cmdEncoder,
				this,
				indirectBuffer,
				indirectBufferOffset,
				indirectBufferStride,
				_mtlCountBuffer,
				_mtlCountBufferOffset,
				_drawCount,
				true);
		indirectBuffer = convertedBuffer->_mtlBuffer;
		indirectBufferOffset = convertedBuffer->_offset;
		indirectBufferStride = sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
	}

    cmdEncoder->_isIndexedDraw = true;

    MVKIndexMTLBufferBinding ibb = ibbOrig;
    if (ibb.vkIndexType == VK_INDEX_TYPE_UINT8) {
        auto* converted = convertUint8IndexBuffer(cmdEncoder, ibb);
        ibb.mtlBuffer = converted->_mtlBuffer;
        ibb.offset = converted->_offset;
    }

	MVKIndexMTLBufferBinding ibbTriFan = ibb;
	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;
	auto zeroDivisorBuffers = encodeIndirectZeroDivisorVertexBufferCopies(cmdEncoder,
			pipeline,
			indirectBuffer,
			indirectBufferOffset,
			indirectBufferStride,
			_drawCount,
			true);

	MVKVertexAdjustments vtxAdjmts{};
	vtxAdjmts.mtlIndexType = ibb.mtlIndexType;
	vtxAdjmts.isMultiView = (cmdEncoder->getSubpass()->isMultiview() &&
							 cmdEncoder->getPhysicalDevice()->canUseInstancingForMultiview());
	vtxAdjmts.isTriangleFan = pipeline->getVkPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN;
#if MVK_USE_METAL_PRIVATE_API
	// With private APIs for primitive restart, we need to handle disabled restart and raw Uint8 indices.
	vtxAdjmts.isPrimRestart = cmdEncoder->getState().vkGraphics().isPrimitiveRestartEnabled();
	vtxAdjmts.isUint8Index = ibb.vkIndexType == VK_INDEX_TYPE_UINT8;
	vtxAdjmts.isProvokingVertexLast = cmdEncoder->getState().vkGraphics().getProvokingVertexMode() == MTLProvokingVertexModeLast;
#endif

#if MVK_MACOS
	if (auto* prepared = cmdEncoder->getBatchedICB(this)) {
		// Describe this draw's state to the ICB kernel and run the real draws from the ICB. Anything the ICB cannot express runs
		// as the direct draws below, and the kernel then encodes no commands for this draw.
		if ( !prepared->used && !pipeline->isTessellationPipeline() && !vtxAdjmts.needsAdjustment() && zeroDivisorBuffers.empty() ) {
			cmdEncoder->finalizeDrawState(kMVKGraphicsStageRasterization);	// Ensure all updated state has been submitted to Metal
			MVKSmallVector<id<MTLBuffer>, 64> resident[2];
			if (fillICBEntry(cmdEncoder, pipeline, ibb, *prepared, resident)) {
				prepared->used = true;
				id<MTLRenderCommandEncoder> mtlEnc = cmdEncoder->_mtlRenderEncoder;
				for (auto buf : resident[0]) { [mtlEnc useResource: buf usage: MTLResourceUsageRead stages: MTLRenderStageVertex]; }
				for (auto buf : resident[1]) { [mtlEnc useResource: buf usage: MTLResourceUsageRead stages: MTLRenderStageFragment]; }
				[mtlEnc useResource: ibb.mtlBuffer usage: MTLResourceUsageRead stages: MTLRenderStageVertex];
				[mtlEnc useResource: prepared->drawIdBuffer usage: MTLResourceUsageRead stages: MTLRenderStageVertex];
				[mtlEnc executeCommandsInBuffer: prepared->icb indirectBuffer: prepared->rangeBuffer indirectBufferOffset: prepared->rangeOffset];
				return;
			}
		}
	}
#endif

	// The indirect calls for dispatchThreadgroups:... and drawPatches:... have different formats.
    // We have to convert from the drawIndexedPrimitives:... format to them.
    // While we're at it, we can create the temporary output buffers once and reuse them
    // for each draw.
    const MVKMTLBufferAllocation* tempIndirectBuff = nullptr;
    const MVKMTLBufferAllocation* tcParamsBuff = nullptr;
    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* vtxIndexBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
    uint32_t patchCount = 0, vertexCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
	VkDeviceSize paramsIncr = 0;

	id<MTLBuffer> mtlIndBuff = indirectBuffer;
    VkDeviceSize mtlIndBuffOfst = indirectBufferOffset;
    VkDeviceSize mtlTempIndBuffOfst = indirectBufferOffset;
    VkDeviceSize mtlParmBuffOfst = 0;
    NSUInteger vtxThreadExecWidth = 0;
    NSUInteger tcWorkgroupSize = 0;

    if (pipeline->isTessellationPipeline()) {
        // We can't read the indirect buffer CPU-side, since it may change between
        // encoding and execution. So we don't know how big to make the buffers.
        // We must assume an arbitrarily large number of vertices may be submitted.
        // But not too many, or we'll exhaust available VRAM.
        inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        vertexCount = kMVKMaxDrawIndirectVertexCount;
        patchCount = mvkCeilingDivide(vertexCount, inControlPointCount);
        VkDeviceSize indirectSize = (sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments) + sizeof(MTLStageInRegionIndirectArguments)) * _drawCount;
		paramsIncr = std::max((size_t)dvcLimits.minUniformBufferOffsetAlignment, sizeof(uint32_t) * 2);
		VkDeviceSize paramsSize = paramsIncr * _drawCount;
        tempIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize, true);
        mtlIndBuff = tempIndirectBuff->_mtlBuffer;
        mtlTempIndBuffOfst = tempIndirectBuff->_offset;
        tcParamsBuff = cmdEncoder->getTempMTLBuffer(paramsSize, true);
        mtlParmBuffOfst = tcParamsBuff->_offset;
        if (pipeline->needsVertexOutputBuffer()) {
            vtxOutBuff = cmdEncoder->getTempMTLBuffer(vertexCount * 4 * dvcLimits.maxVertexOutputComponents, true);
        }
        if (pipeline->needsTessCtlOutputBuffer()) {
            tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * patchCount * 4 * dvcLimits.maxTessellationControlPerVertexOutputComponents, true);
        }
        if (pipeline->needsTessCtlPatchOutputBuffer()) {
            tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(patchCount * 4 * dvcLimits.maxTessellationControlPerPatchOutputComponents, true);
        }
        tcLevelBuff = cmdEncoder->getTempMTLBuffer(patchCount * sizeof(MTLQuadTessellationFactorsHalf), true);
        vtxIndexBuff = cmdEncoder->getTempMTLBuffer(ibb.size, true);

        id<MTLComputePipelineState> vtxState;
        vtxState = ibb.mtlIndexType == MTLIndexTypeUInt16 ? pipeline->getTessVertexStageIndex16State() : pipeline->getTessVertexStageIndex32State();
        vtxThreadExecWidth = vtxState.threadExecutionWidth;

        NSUInteger sgSize = pipeline->getTessControlStageState().threadExecutionWidth;
        tcWorkgroupSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
        while (tcWorkgroupSize > dvcLimits.maxComputeWorkGroupSize[0]) {
            sgSize >>= 1;
            tcWorkgroupSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
        }
    } else if (vtxAdjmts.needsAdjustment()) {
        // In this case, we need to adjust the instance count for the views being drawn.
        VkDeviceSize indirectSize = sizeof(MTLDrawIndexedPrimitivesIndirectArguments) * _drawCount;
        tempIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize, true);
        mtlIndBuff = tempIndirectBuff->_mtlBuffer;
        mtlTempIndBuffOfst = tempIndirectBuff->_offset;
		if (vtxAdjmts.isTriangleFan) {
			auto* triVtxBuff = cmdEncoder->getTempMTLBuffer(mvkMTLIndexTypeSizeInBytes((MTLIndexType)ibb.mtlIndexType) * kMVKMaxDrawIndirectVertexCount, true);
			ibb.mtlBuffer = triVtxBuff->_mtlBuffer;
			ibb.offset = triVtxBuff->_offset;
		}
    }

	MVKPiplineStages stages;
    pipeline->getStages(stages);

    if (pipeline->needsDrawIdBuffer()) {
        tempDrawIDBuff = cmdEncoder->getTempMTLBuffer(_drawCount * sizeof(uint32_t));

        auto* drawIDs = (uint32_t*)((char*)[tempDrawIDBuff->_mtlBuffer contents] + tempDrawIDBuff->_offset);
        for (uint32_t i = 0; i < _drawCount; i++) {
            drawIDs[i] = i;
        }
    }
    for (uint32_t drawIdx = 0; drawIdx < _drawCount; drawIdx++) {
        for (uint32_t s : stages) {
            auto stage = MVKGraphicsStage(s);
            id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;
            if (stage == kMVKGraphicsStageVertex && pipeline->isTessellationPipeline()) {
				cmdEncoder->encodeStoreActions(true);
				MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                // We need the indirect buffers now. This must be done before finalizing
                // draw state, or the pipeline will get overridden. This is a good time
                // to do it, since it will require switching to compute anyway. Do it all
                // at once to get it over with.
                if (drawIdx == 0) {
                    id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectTessConvertBuffersMTLComputePipelineState(true);
                    state.bindPipeline(mtlTessCtlEncoder, mtlConvertState);
                    state.bindBuffer(mtlTessCtlEncoder, indirectBuffer,                indirectBufferOffset,      0);
                    state.bindBuffer(mtlTessCtlEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
                    state.bindBuffer(mtlTessCtlEncoder, tcParamsBuff->_mtlBuffer,     tcParamsBuff->_offset,     2);
                    state.bindStructBytes(mtlTessCtlEncoder, &indirectBufferStride,     3);
                    state.bindStructBytes(mtlTessCtlEncoder, &inControlPointCount,      4);
                    state.bindStructBytes(mtlTessCtlEncoder, &outControlPointCount,     5);
                    state.bindStructBytes(mtlTessCtlEncoder, &_drawCount,               6);
                    state.bindStructBytes(mtlTessCtlEncoder, &vtxThreadExecWidth,       7);
                    state.bindStructBytes(mtlTessCtlEncoder, &tcWorkgroupSize,          8);
                    [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
                                      threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                }
                // We actually need to make a copy of the index buffer, because there's no way to tell Metal to
                // offset an index buffer from a value in an indirect buffer. This also
                // means that, to make a copy, we have to use a compute shader.
                state.bindPipeline(mtlTessCtlEncoder, cmdEncoder->getCommandEncodingPool()->getCmdDrawIndexedCopyIndexBufferMTLComputePipelineState((MTLIndexType)ibb.mtlIndexType));
                state.bindBuffer(mtlTessCtlEncoder, ibb.mtlBuffer,            ibb.offset,            0);
                state.bindBuffer(mtlTessCtlEncoder, vtxIndexBuff->_mtlBuffer, vtxIndexBuff->_offset, 1);
                state.bindBuffer(mtlTessCtlEncoder, indirectBuffer,            mtlIndBuffOfst,        2);
                [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
													 indirectBufferOffset: mtlTempIndBuffOfst + sizeof(MTLStageInRegionIndirectArguments)
                                                    threadsPerThreadgroup: MTLSizeMake(vtxThreadExecWidth, 1, 1)];
				mtlIndBuffOfst += sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
            } else if (drawIdx == 0 && vtxAdjmts.needsAdjustment()) {
                // Similarly, for multiview, we need to adjust the instance count now.
                // Unfortunately, this requires switching to compute. Luckily, we don't also
                // have to copy the index buffer.
                // TODO: Consider using tile shaders to avoid this cost.
				cmdEncoder->encodeStoreActions(true);
				MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
				id<MTLComputeCommandEncoder> mtlConvertEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
				id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectConvertBuffersMTLComputePipelineState(true);
				uint32_t viewCount = cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex());
				state.bindPipeline(mtlConvertEncoder, mtlConvertState);
				state.bindBuffer(mtlConvertEncoder, indirectBuffer,                indirectBufferOffset,      0);
				state.bindBuffer(mtlConvertEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
				state.bindStructBytes(mtlConvertEncoder, &indirectBufferStride,     2);
				state.bindStructBytes(mtlConvertEncoder, &_drawCount,               3);
				state.bindStructBytes(mtlConvertEncoder, &viewCount,                4);
				state.bindStructBytes(mtlConvertEncoder, &vtxAdjmts,                5);
				state.bindBuffer(mtlConvertEncoder, ibb.mtlBuffer,       ibb.offset,       6);
				state.bindBuffer(mtlConvertEncoder, ibbTriFan.mtlBuffer, ibbTriFan.offset, 7);
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlConvertEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
				} else {
					[mtlConvertEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
									  threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
				}
				// Switch back to rendering now, since we don't have compute stages to run anyway.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
            }

			if (drawIdx == 0 || pipeline->isTessellationPipeline() || vtxAdjmts.needsAdjustment()) {
				cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal
			}
			if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

            switch (stage) {
                case kMVKGraphicsStageVertex:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                             offset: vtxOutBuff->_offset
                                            atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                    }
                    if (pipeline->needsDrawIdBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tempDrawIDBuff->_mtlBuffer
                                              offset: tempDrawIDBuff->_offset + drawIdx * sizeof(uint32_t)
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                    }
					[mtlTessCtlEncoder setBuffer: vtxIndexBuff->_mtlBuffer
										  offset: vtxIndexBuff->_offset
										 atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Index]];
					[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(0, 0, vertexCount, vertexCount)];
					[mtlTessCtlEncoder setStageInRegionWithIndirectBuffer: mtlIndBuff
						                             indirectBufferOffset: mtlTempIndBuffOfst];
					mtlTempIndBuffOfst += sizeof(MTLStageInRegionIndirectArguments);
					// Bind the copied zero-divisor vertex data for this indirect command.
					bindIndirectZeroDivisorVertexBuffers(cmdEncoder, stage, zeroDivisorBuffers, drawIdx);
					[mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
														 indirectBufferOffset: mtlTempIndBuffOfst
														threadsPerThreadgroup: MTLSizeMake(vtxThreadExecWidth, 1, 1)];
					mtlTempIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    break;
                case kMVKGraphicsStageTessControl:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                              offset: tcOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::Output]];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                              offset: tcPatchOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::PatchOutput]];
                    }
                    [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                          offset: tcLevelBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::TessLevel]];
					[mtlTessCtlEncoder setBuffer: tcParamsBuff->_mtlBuffer
										  offset: mtlParmBuffOfst
										 atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::IndirectParams]];
					mtlParmBuffOfst += paramsIncr;
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                              offset: vtxOutBuff->_offset
                                             atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding)];
                    }
                    [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
                                                         indirectBufferOffset: mtlTempIndBuffOfst
                                                        threadsPerThreadgroup: MTLSizeMake(tcWorkgroupSize, 1, 1)];
                    mtlTempIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    // Running this stage prematurely ended the render pass, so we have to start it up again.
                    // TODO: On iOS, maybe we could use a tile shader to avoid this.
                    cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
                    break;
                case kMVKGraphicsStageRasterization:
                    if (pipeline->isTessellationPipeline()) {
						if (mtlFeats.indirectTessellationDrawing) {
							if (pipeline->needsTessCtlOutputBuffer()) {
								[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
																		offset: tcOutBuff->_offset
																	   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding)];
							}
							if (pipeline->needsTessCtlPatchOutputBuffer()) {
								[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
																		offset: tcPatchOutBuff->_offset
																	   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding)];
							}
							[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
																	offset: tcLevelBuff->_offset
																   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding)];
							[cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
																				offset: tcLevelBuff->_offset
																		instanceStride: 0];
							[cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
							                          patchIndexBuffer: nil
							                    patchIndexBufferOffset: 0
							                            indirectBuffer: mtlIndBuff
							                      indirectBufferOffset: mtlTempIndBuffOfst];
						}

						mtlTempIndBuffOfst += sizeof(MTLDrawPatchIndirectArguments);
                    } else {
						bindIndirectZeroDivisorVertexBuffers(cmdEncoder, stage, zeroDivisorBuffers, drawIdx);
                        if (pipeline->needsDrawIdBuffer()) {
                            [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tempDrawIDBuff->_mtlBuffer
                                                                    offset: tempDrawIDBuff->_offset + drawIdx * sizeof(uint32_t)
                                                                   atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                        }
                        [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                                   indexType: (MTLIndexType)ibb.mtlIndexType
                                                                 indexBuffer: ibb.mtlBuffer
                                                           indexBufferOffset: ibb.offset
                                                              indirectBuffer: mtlIndBuff
                                                        indirectBufferOffset: mtlTempIndBuffOfst];
                        mtlTempIndBuffOfst += vtxAdjmts.needsAdjustment() ? sizeof(MTLDrawIndexedPrimitivesIndirectArguments) : indirectBufferStride;
                    }
                    break;
            }
        }
    }
}
