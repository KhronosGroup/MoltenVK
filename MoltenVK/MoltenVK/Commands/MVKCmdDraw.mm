/*
 * MVKCmdDraw.mm
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
	_isUint8 = indexType == VK_INDEX_TYPE_UINT8;
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
    } else if (_isUint8) {
        // Copy 8-bit indices into 16-bit index buffer compatible with Metal.
        const auto numIndices = _binding.size;
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
        state.bindBuffer(mtlComputeEnc, _binding.mtlBuffer, _binding.offset, 0);
        state.bindBuffer(mtlComputeEnc, uint16Buf->_mtlBuffer, 0, 1);

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
                state.bindBuffer(mtlComputeEnc, _binding.mtlBuffer, _binding.offset + indicesConverted, 0);
                state.bindBuffer(mtlComputeEnc, uint16Buf->_mtlBuffer, indicesConverted * 2, 1);
            }
            [mtlComputeEnc dispatchThreadgroups: MTLSizeMake(1, 1, 1)
                           threadsPerThreadgroup: MTLSizeMake(remainderIndexCount, 1, 1)];
        }

        // Running this stage prematurely ended the render pass, so we have to start it up again.
        cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);

        _binding.mtlBuffer = uint16Buf->_mtlBuffer;
        _binding.offset = uint16Buf->_offset;
    }

    cmdEncoder->getState().bindIndexBuffer(_binding);
}


#pragma mark -
#pragma mark MVKCmdDraw

VkResult MVKCmdDraw::setContent(MVKCommandBuffer* cmdBuff,
								uint32_t vertexCount,
								uint32_t instanceCount,
								uint32_t firstVertex,
								uint32_t firstInstance) {
	_vertexCount = vertexCount;
	_instanceCount = instanceCount;
	_firstVertex = firstVertex;
	_firstInstance = firstInstance;

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
					  indirectIdxBuffStride,
					  _firstInstance);
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
				[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(_firstVertex, _firstInstance, _vertexCount, _instanceCount)];
				// If there are vertex bindings with a zero vertex divisor, I need to offset them by
				// _firstInstance * stride, since that is the expected behaviour for a divisor of 0.
                cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
				id<MTLComputePipelineState> vtxState = pipeline->getTessVertexStageState();
				if (mtlFeats.nonUniformThreadgroups) {
#if MVK_MACOS_OR_IOS
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(_vertexCount, _instanceCount, 1)
                                 threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
#endif
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
#if MVK_MACOS_OR_IOS
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(tessParams.patchCount * outControlPointCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
#endif
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
									   uint32_t firstInstance) {
	_indexCount = indexCount;
	_instanceCount = instanceCount;
	_firstIndex = firstIndex;
	_vertexOffset = vertexOffset;
	_firstInstance = firstInstance;

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
					  indirectIdxBuffStride,
					  _firstInstance);
	diiCmd.encode(cmdEncoder);
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

    const MVKIndexMTLBufferBinding& ibb = cmdEncoder->getVkGraphics()._indexBuffer;
    size_t idxSize = mvkMTLIndexTypeSizeInBytes((MTLIndexType)ibb.mtlIndexType);
    VkDeviceSize idxBuffOffset = ibb.offset + (_firstIndex * idxSize);

    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
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
				[mtlTessCtlEncoder setBuffer: ibb.mtlBuffer
                                      offset: idxBuffOffset
                                     atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Index]];
				[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(_vertexOffset, _firstInstance, _indexCount, _instanceCount)];
				// If there are vertex bindings with a zero vertex divisor, I need to offset them by
				// _firstInstance * stride, since that is the expected behaviour for a divisor of 0.
                cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
				id<MTLComputePipelineState> vtxState = ibb.mtlIndexType == MTLIndexTypeUInt16 ? pipeline->getTessVertexStageIndex16State() : pipeline->getTessVertexStageIndex32State();
				if (mtlFeats.nonUniformThreadgroups) {
#if MVK_MACOS_OR_IOS
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(_indexCount, _instanceCount, 1)
                                 threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
#endif
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
#if MVK_MACOS_OR_IOS
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(tessParams.patchCount * outControlPointCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
#endif
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
static const uint32_t kMVKMaxDrawIndirectVertexCount = 128 * KIBI;

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

// Populates and encodes a MVKCmdDrawIndexedIndirect command, after populating indexed indirect buffers.
void MVKCmdDrawIndirect::encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder) {

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
	state.bindBuffer(mtlConvertEncoder, _mtlIndirectBuffer,          _mtlIndirectBufferOffset, 0);
	state.bindBuffer(mtlConvertEncoder, indirectIdxBuff->_mtlBuffer, indirectIdxBuff->_offset, 1);
	state.bindStructBytes(mtlConvertEncoder, &_mtlIndirectBufferStride, 2);
	state.bindStructBytes(mtlConvertEncoder, &_drawCount,               3);
	state.bindBuffer(mtlConvertEncoder, ibb.mtlBuffer, ibb.offset, 4);
	if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
#if MVK_MACOS_OR_IOS
		[mtlConvertEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
					 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
#endif
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
					  indirectIdxBuffStride,
					  0);
	diiCmd.encode(cmdEncoder, ibb);
}

void MVKCmdDrawIndirect::encode(MVKCommandEncoder* cmdEncoder) {

	cmdEncoder->restartMetalRenderPassIfNeeded();

	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;

	// Metal doesn't support triangle fans, so encode it as indexed indirect triangles instead.
	if (pipeline->getVkPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
		encodeIndexedIndirect(cmdEncoder);
		return;
	}

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
    uint32_t patchCount = 0, vertexCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
	VkDeviceSize paramsIncr = 0;

    id<MTLBuffer> mtlIndBuff = _mtlIndirectBuffer;
    VkDeviceSize mtlIndBuffOfst = _mtlIndirectBufferOffset;
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
        VkDeviceSize indirectSize = (2 * sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments)) * _drawCount;
        if (mtlFeats.mslVersion >= 20100) {
            indirectSize += sizeof(MTLStageInRegionIndirectArguments) * _drawCount;
        }
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
				state.bindBuffer(mtlTessCtlEncoder, _mtlIndirectBuffer,           _mtlIndirectBufferOffset,  0);
				state.bindBuffer(mtlTessCtlEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
				state.bindBuffer(mtlTessCtlEncoder, tcParamsBuff->_mtlBuffer,     tcParamsBuff->_offset,     2);
				state.bindStructBytes(mtlTessCtlEncoder, &_mtlIndirectBufferStride, 3);
				state.bindStructBytes(mtlTessCtlEncoder, &inControlPointCount,      4);
				state.bindStructBytes(mtlTessCtlEncoder, &outControlPointCount,     5);
				state.bindStructBytes(mtlTessCtlEncoder, &_drawCount,               6);
				state.bindStructBytes(mtlTessCtlEncoder, &vtxThreadExecWidth,       7);
				state.bindStructBytes(mtlTessCtlEncoder, &tcWorkgroupSize,          8);
				if (mtlFeats.nonUniformThreadgroups) {
#if MVK_MACOS_OR_IOS
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
#endif
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
				state.bindBuffer(mtlConvertEncoder, _mtlIndirectBuffer,           _mtlIndirectBufferOffset,  0);
				state.bindBuffer(mtlConvertEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
				state.bindStructBytes(mtlConvertEncoder, &_mtlIndirectBufferStride, 2);
				state.bindStructBytes(mtlConvertEncoder, &_drawCount,               3);
				state.bindStructBytes(mtlConvertEncoder, &viewCount,                4);
                if (mtlFeats.nonUniformThreadgroups) {
#if MVK_MACOS_OR_IOS
                    [mtlConvertEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
                                 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
#endif
                } else {
                    [mtlConvertEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
                                      threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                }
                // Switch back to rendering now, since we don't have compute stages to run anyway.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
            }

            cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal

			if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

            switch (stage) {
                case kMVKGraphicsStageVertex:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                              offset: vtxOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                    }
					// We must assume we can read up to the maximum number of vertices.
					[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(0, 0, vertexCount, vertexCount)];
					if ([mtlTessCtlEncoder respondsToSelector: @selector(setStageInRegionWithIndirectBuffer:indirectBufferOffset:)]) {
						[mtlTessCtlEncoder setStageInRegionWithIndirectBuffer: mtlIndBuff
						                                 indirectBufferOffset: mtlIndBuffOfst];
						mtlIndBuffOfst += sizeof(MTLStageInRegionIndirectArguments);
					}
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
#if MVK_MACOS_OR_IOS
							[cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
													  patchIndexBuffer: nil
												patchIndexBufferOffset: 0
														indirectBuffer: mtlIndBuff
												  indirectBufferOffset: mtlIndBuffOfst];
#endif
						}

						mtlIndBuffOfst += sizeof(MTLDrawPatchIndirectArguments);
                    } else {
                        [cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                       indirectBuffer: mtlIndBuff
                                                 indirectBufferOffset: mtlIndBuffOfst];
                        mtlIndBuffOfst += needsInstanceAdjustment ? sizeof(MTLDrawPrimitivesIndirectArguments) : _mtlIndirectBufferStride;
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
					  stride,
					  0);
}

VkResult MVKCmdDrawIndexedIndirect::setContent(MVKCommandBuffer* cmdBuff,
											   id<MTLBuffer> indirectMTLBuff,
											   VkDeviceSize indirectMTLBuffOffset,
											   uint32_t drawCount,
											   uint32_t stride,
											   uint32_t directCmdFirstInstance) {
	_mtlIndirectBuffer = indirectMTLBuff;
	_mtlIndirectBufferOffset = indirectMTLBuffOffset;
	_mtlIndirectBufferStride = stride;
	_drawCount = drawCount;
	_directCmdFirstInstance = directCmdFirstInstance;

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

void MVKCmdDrawIndexedIndirect::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->restartMetalRenderPassIfNeeded();
	encode(cmdEncoder, cmdEncoder->getVkGraphics()._indexBuffer);
}

void MVKCmdDrawIndexedIndirect::encode(MVKCommandEncoder* cmdEncoder, const MVKIndexMTLBufferBinding& ibbOrig) {

    cmdEncoder->_isIndexedDraw = true;

    MVKIndexMTLBufferBinding ibb = ibbOrig;
	MVKIndexMTLBufferBinding ibbTriFan = ibb;
    auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;

	MVKVertexAdjustments vtxAdjmts;
	vtxAdjmts.mtlIndexType = ibb.mtlIndexType;
	vtxAdjmts.isMultiView = (cmdEncoder->getSubpass()->isMultiview() &&
							 cmdEncoder->getPhysicalDevice()->canUseInstancingForMultiview());
	vtxAdjmts.isTriangleFan = pipeline->getVkPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN;

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
    uint32_t patchCount = 0, vertexCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
	VkDeviceSize paramsIncr = 0;

	id<MTLBuffer> mtlIndBuff = _mtlIndirectBuffer;
    VkDeviceSize mtlIndBuffOfst = _mtlIndirectBufferOffset;
    VkDeviceSize mtlTempIndBuffOfst = _mtlIndirectBufferOffset;
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
        VkDeviceSize indirectSize = (sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments)) * _drawCount;
        if (mtlFeats.mslVersion >= 20100) {
            indirectSize += sizeof(MTLStageInRegionIndirectArguments) * _drawCount;
        }
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
                    state.bindBuffer(mtlTessCtlEncoder, _mtlIndirectBuffer,           _mtlIndirectBufferOffset,  0);
                    state.bindBuffer(mtlTessCtlEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
                    state.bindBuffer(mtlTessCtlEncoder, tcParamsBuff->_mtlBuffer,     tcParamsBuff->_offset,     2);
                    state.bindStructBytes(mtlTessCtlEncoder, &_mtlIndirectBufferStride, 3);
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
                state.bindBuffer(mtlTessCtlEncoder, _mtlIndirectBuffer,       mtlIndBuffOfst,        2);
                [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
													 indirectBufferOffset: mtlTempIndBuffOfst
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
				state.bindBuffer(mtlConvertEncoder, _mtlIndirectBuffer,           _mtlIndirectBufferOffset,  0);
				state.bindBuffer(mtlConvertEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
				state.bindStructBytes(mtlConvertEncoder, &_mtlIndirectBufferStride, 2);
				state.bindStructBytes(mtlConvertEncoder, &_drawCount,               3);
				state.bindStructBytes(mtlConvertEncoder, &viewCount,                4);
				state.bindStructBytes(mtlConvertEncoder, &vtxAdjmts,                5);
				state.bindBuffer(mtlConvertEncoder, ibb.mtlBuffer,       ibb.offset,       6);
				state.bindBuffer(mtlConvertEncoder, ibbTriFan.mtlBuffer, ibbTriFan.offset, 7);
				if (mtlFeats.nonUniformThreadgroups) {
#if MVK_MACOS_OR_IOS
					[mtlConvertEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
#endif
				} else {
					[mtlConvertEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
									  threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
				}
				// Switch back to rendering now, since we don't have compute stages to run anyway.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
            }

	        cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal

			if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

            switch (stage) {
                case kMVKGraphicsStageVertex:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                             offset: vtxOutBuff->_offset
                                            atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                    }
					[mtlTessCtlEncoder setBuffer: vtxIndexBuff->_mtlBuffer
										  offset: vtxIndexBuff->_offset
										 atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Index]];
					[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(0, 0, vertexCount, vertexCount)];
					if ([mtlTessCtlEncoder respondsToSelector: @selector(setStageInRegionWithIndirectBuffer:indirectBufferOffset:)]) {
						[mtlTessCtlEncoder setStageInRegionWithIndirectBuffer: mtlIndBuff
						                                 indirectBufferOffset: mtlTempIndBuffOfst];
						mtlTempIndBuffOfst += sizeof(MTLStageInRegionIndirectArguments);
					}
					// If this is a synthetic command that originated in a direct call, and there are vertex bindings with a zero vertex
					// divisor, I need to offset them by _firstInstance * stride, since that is the expected behaviour for a divisor of 0.
					cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _directCmdFirstInstance);
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
#if MVK_MACOS_OR_IOS
							[cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
													  patchIndexBuffer: nil
												patchIndexBufferOffset: 0
														indirectBuffer: mtlIndBuff
												  indirectBufferOffset: mtlTempIndBuffOfst];
#endif
						}

						mtlTempIndBuffOfst += sizeof(MTLDrawPatchIndirectArguments);
                    } else {
						cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _directCmdFirstInstance);
                        [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                                   indexType: (MTLIndexType)ibb.mtlIndexType
                                                                 indexBuffer: ibb.mtlBuffer
                                                           indexBufferOffset: ibb.offset
                                                              indirectBuffer: mtlIndBuff
                                                        indirectBufferOffset: mtlTempIndBuffOfst];
                        mtlTempIndBuffOfst += vtxAdjmts.needsAdjustment() ? sizeof(MTLDrawIndexedPrimitivesIndirectArguments) : _mtlIndirectBufferStride;
                    }
                    break;
            }
        }
    }
}

