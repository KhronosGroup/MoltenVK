/*
 * MVKCmdDraw.mm
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

#include "MVKCmdDraw.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKBuffer.h"
#include "MVKPipeline.h"
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
    for (auto& b : _bindings) { cmdEncoder->_graphicsResourcesState.bindBuffer(kMVKShaderStageVertex, b); }
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

    auto* pipeline = (MVKGraphicsPipeline*)cmdEncoder->_graphicsPipelineState.getPipeline();

    MVKVectorInline<uint32_t, 4> stages;
    pipeline->getStages(stages);

    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    uint32_t patchCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        inControlPointCount = pipeline->getInputControlPointCount();
        outControlPointCount = pipeline->getOutputControlPointCount();
        patchCount = (uint32_t)mvkCeilingDivide(_vertexCount, inControlPointCount);
    }
    for (uint32_t s : stages) {
        auto stage = MVKGraphicsStage(s);
        cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal
        id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;

        switch (stage) {
            case kMVKGraphicsStageVertex:
                if (pipeline->needsVertexOutputBuffer()) {
                    vtxOutBuff = cmdEncoder->getTempMTLBuffer(_vertexCount * _instanceCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxVertexOutputComponents);
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: vtxOutBuff->_mtlBuffer
                                                            offset: vtxOutBuff->_offset
                                                           atIndex: pipeline->getOutputBufferIndex().stages[kMVKShaderStageVertex]];
                    // The shader only needs the number of vertices, so that's all we'll give it.
                    cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                               &_vertexCount,
                                               sizeof(_vertexCount),
                                               pipeline->getIndirectParamsIndex().stages[kMVKShaderStageVertex]);
                }
                if (cmdEncoder->_pDeviceMetalFeatures->baseVertexInstanceDrawing) {
                    [cmdEncoder->_mtlRenderEncoder drawPrimitives: MTLPrimitiveTypePoint
                                                      vertexStart: _firstVertex
                                                      vertexCount: _vertexCount
                                                    instanceCount: _instanceCount
                                                     baseInstance: _firstInstance];
                } else {
                    [cmdEncoder->_mtlRenderEncoder drawPrimitives: MTLPrimitiveTypePoint
                                                      vertexStart: _firstVertex
                                                      vertexCount: _vertexCount
                                                    instanceCount: _instanceCount];
                }
                // Mark pipeline, resources, and tess control push constants as dirty
                // so I apply them during the next stage.
                cmdEncoder->_graphicsPipelineState.beginMetalRenderPass();
                cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
                cmdEncoder->getPushConstants(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT)->beginMetalRenderPass();
                break;
            case kMVKGraphicsStageTessControl:
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl);
                if (pipeline->needsTessCtlOutputBuffer()) {
                    tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * patchCount * _instanceCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxTessellationControlPerVertexOutputComponents);
                    [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                          offset: tcOutBuff->_offset
                                         atIndex: pipeline->getOutputBufferIndex().stages[kMVKShaderStageTessCtl]];
                }
                if (pipeline->needsTessCtlPatchOutputBuffer()) {
                    tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(_instanceCount * patchCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxTessellationControlPerPatchOutputComponents);
                    [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                          offset: tcPatchOutBuff->_offset
                                         atIndex: pipeline->getTessCtlPatchOutputBufferIndex()];
                }
                tcLevelBuff = cmdEncoder->getTempMTLBuffer(_instanceCount * patchCount * sizeof(MTLQuadTessellationFactorsHalf));
                [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                      offset: tcLevelBuff->_offset
                                     atIndex: pipeline->getTessCtlLevelBufferIndex()];
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &inControlPointCount,
                                            sizeof(inControlPointCount),
                                            pipeline->getIndirectParamsIndex().stages[kMVKShaderStageTessCtl]);
                if (pipeline->needsVertexOutputBuffer()) {
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: kMVKTessCtlInputBufferIndex];
                    [mtlTessCtlEncoder setStageInRegion: MTLRegionMake1D(0, _instanceCount * std::max(_vertexCount, outControlPointCount * patchCount))];
                }
                if (outControlPointCount > inControlPointCount) {
                    // In this case, we use an index buffer to avoid stepping over some of the input points.
                    const MVKMTLBufferAllocation* tcIndexBuff = cmdEncoder->getTempMTLBuffer(_instanceCount * patchCount * outControlPointCount * 4);
                    auto* indices = (uint32_t*)tcIndexBuff->getContents();
                    uint32_t index = 0;
                    for (uint32_t i = 0; i < outControlPointCount * patchCount; i++) {
                        if ((i % outControlPointCount) < inControlPointCount) {
                            indices[i] = index++;
                        } else {
                            indices[i] = 0;
                        }
                    }
                    [mtlTessCtlEncoder setBuffer: tcIndexBuff->_mtlBuffer
                                          offset: tcIndexBuff->_offset
                                         atIndex: kMVKTessCtlIndexBufferIndex];
                }
                [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(_instanceCount * patchCount, 1, 1)
                                  threadsPerThreadgroup: MTLSizeMake(std::max(inControlPointCount, outControlPointCount), 1, 1)];
                // Running this stage prematurely ended the render pass, so we have to start it up again.
                // TODO: On iOS, maybe we could use a tile shader to avoid this.
                cmdEncoder->beginMetalRenderPass();
                break;
            case kMVKGraphicsStageRasterization:
                if (pipeline->isTessellationPipeline()) {
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
                                                                offset: tcOutBuff->_offset
                                                               atIndex: kMVKTessEvalInputBufferIndex];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
                                                                offset: tcPatchOutBuff->_offset
                                                               atIndex: kMVKTessEvalPatchInputBufferIndex];
                    }
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
                                                            offset: tcLevelBuff->_offset
                                                           atIndex: kMVKTessEvalLevelBufferIndex];
                    [cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
                                                                        offset: tcLevelBuff->_offset
                                                                instanceStride: 0];
                    [cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
                                                    patchStart: 0
                                                    patchCount: _instanceCount * patchCount
                                              patchIndexBuffer: nil
                                        patchIndexBufferOffset: 0
                                                 instanceCount: 1
                                                  baseInstance: 0];
                    // Mark pipeline, resources, and tess control push constants as dirty
                    // so I apply them during the next stage.
                    cmdEncoder->_graphicsPipelineState.beginMetalRenderPass();
                    cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
                    cmdEncoder->getPushConstants(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT)->beginMetalRenderPass();
                } else {
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
                break;
        }
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

    auto* pipeline = (MVKGraphicsPipeline*)cmdEncoder->_graphicsPipelineState.getPipeline();

    MVKVectorInline<uint32_t, 4> stages;
    pipeline->getStages(stages);

    MVKIndexMTLBufferBinding& ibb = cmdEncoder->_graphicsResourcesState._mtlIndexBufferBinding;
    size_t idxSize = mvkMTLIndexTypeSizeInBytes(ibb.mtlIndexType);
    VkDeviceSize idxBuffOffset = ibb.offset + (_firstIndex * idxSize);

    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tcIndexBuff = nullptr;
    uint32_t patchCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        inControlPointCount = pipeline->getInputControlPointCount();
        outControlPointCount = pipeline->getOutputControlPointCount();
        patchCount = (uint32_t)mvkCeilingDivide(_indexCount, inControlPointCount);
    }
    for (uint32_t s : stages) {
        auto stage = MVKGraphicsStage(s);
        id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;
        if (stage == kMVKGraphicsStageTessControl && (outControlPointCount > inControlPointCount || _instanceCount > 1)) {
            // We need make a copy of the old index buffer so we can insert gaps where
            // there are more output points than input points, and also to add more indices
            // to handle instancing. Do it now, before finalizing draw state, or the
            // pipeline will get overridden.
            // Yeah, this sucks. But there aren't many good ways for dealing with this issue.
            mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl);
            tcIndexBuff = cmdEncoder->getTempMTLBuffer(_instanceCount * patchCount * outControlPointCount * idxSize);
            id<MTLComputePipelineState> mtlCopyIndexState = getCommandEncodingPool()->getCmdDrawIndexedCopyIndexBufferMTLComputePipelineState(ibb.mtlIndexType);
            [mtlTessCtlEncoder setComputePipelineState: mtlCopyIndexState];
            [mtlTessCtlEncoder setBuffer: ibb.mtlBuffer
                                  offset: ibb.offset
                                 atIndex: 0];
            [mtlTessCtlEncoder setBuffer: tcIndexBuff->_mtlBuffer
                                  offset: tcIndexBuff->_offset
                                 atIndex: 1];
            cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                        &inControlPointCount,
                                        sizeof(inControlPointCount),
                                        2);
            cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                        &outControlPointCount,
                                        sizeof(outControlPointCount),
                                        3);
            MTLDrawIndexedPrimitivesIndirectArguments params;
            params.indexCount = _indexCount;
            params.instanceCount = _instanceCount;
            params.indexStart = _firstIndex;
            cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                        &params,
                                        sizeof(params),
                                        4);
            [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(1, 1, 1) threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
        }
        cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal

        switch (stage) {
            case kMVKGraphicsStageVertex:
                if (pipeline->needsVertexOutputBuffer()) {
                    vtxOutBuff = cmdEncoder->getTempMTLBuffer(_indexCount * _instanceCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxVertexOutputComponents);
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: vtxOutBuff->_mtlBuffer
                                                            offset: vtxOutBuff->_offset
                                                           atIndex: pipeline->getOutputBufferIndex().stages[kMVKShaderStageVertex]];
                    // The shader only needs the number of vertices, so that's all we'll give it.
                    cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                               &_indexCount,
                                               sizeof(_indexCount),
                                               pipeline->getIndirectParamsIndex().stages[kMVKShaderStageVertex]);
                }
                if (cmdEncoder->_pDeviceMetalFeatures->baseVertexInstanceDrawing) {
                    [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: MTLPrimitiveTypePoint
                                                              indexCount: _indexCount
                                                               indexType: ibb.mtlIndexType
                                                             indexBuffer: ibb.mtlBuffer
                                                       indexBufferOffset: idxBuffOffset
                                                           instanceCount: _instanceCount
                                                              baseVertex: _vertexOffset
                                                            baseInstance: _firstInstance];
                } else {
                    [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: MTLPrimitiveTypePoint
                                                              indexCount: _indexCount
                                                               indexType: ibb.mtlIndexType
                                                             indexBuffer: ibb.mtlBuffer
                                                       indexBufferOffset: idxBuffOffset
                                                           instanceCount: _instanceCount];
                }
                // Mark pipeline, resources, and tess control push constants as dirty
                // so I apply them during the next stage.
                cmdEncoder->_graphicsPipelineState.beginMetalRenderPass();
                cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
                cmdEncoder->getPushConstants(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT)->beginMetalRenderPass();
                break;
            case kMVKGraphicsStageTessControl:
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl);
                if (pipeline->needsTessCtlOutputBuffer()) {
                    tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * patchCount * _instanceCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxTessellationControlPerVertexOutputComponents);
                    [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                          offset: tcOutBuff->_offset
                                         atIndex: pipeline->getOutputBufferIndex().stages[kMVKShaderStageTessCtl]];
                }
                if (pipeline->needsTessCtlPatchOutputBuffer()) {
                    tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(_instanceCount * patchCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxTessellationControlPerPatchOutputComponents);
                    [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                          offset: tcPatchOutBuff->_offset
                                         atIndex: pipeline->getTessCtlPatchOutputBufferIndex()];
                }
                tcLevelBuff = cmdEncoder->getTempMTLBuffer(_instanceCount * patchCount * sizeof(MTLQuadTessellationFactorsHalf));
                [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                      offset: tcLevelBuff->_offset
                                     atIndex: pipeline->getTessCtlLevelBufferIndex()];
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &inControlPointCount,
                                            sizeof(inControlPointCount),
                                            pipeline->getIndirectParamsIndex().stages[kMVKShaderStageTessCtl]);
                if (pipeline->needsVertexOutputBuffer()) {
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: kMVKTessCtlInputBufferIndex];
                    [mtlTessCtlEncoder setStageInRegion: MTLRegionMake1D(0, _instanceCount * std::max(_indexCount, outControlPointCount * patchCount))];
                }
                if (outControlPointCount > inControlPointCount || _instanceCount > 1) {
                    [mtlTessCtlEncoder setBuffer: tcIndexBuff->_mtlBuffer
                                          offset: tcIndexBuff->_offset
                                         atIndex: kMVKTessCtlIndexBufferIndex];
                } else {
                    [mtlTessCtlEncoder setBuffer: ibb.mtlBuffer
                                          offset: idxBuffOffset
                                         atIndex: kMVKTessCtlIndexBufferIndex];
                }
                [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(_instanceCount * patchCount, 1, 1)
                                  threadsPerThreadgroup: MTLSizeMake(std::max(inControlPointCount, outControlPointCount), 1, 1)];
                // Running this stage prematurely ended the render pass, so we have to start it up again.
                // TODO: On iOS, maybe we could use a tile shader to avoid this.
                cmdEncoder->beginMetalRenderPass();
                break;
            case kMVKGraphicsStageRasterization:
                if (pipeline->isTessellationPipeline()) {
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
                                                                offset: tcOutBuff->_offset
                                                               atIndex: kMVKTessEvalInputBufferIndex];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
                                                                offset: tcPatchOutBuff->_offset
                                                               atIndex: kMVKTessEvalPatchInputBufferIndex];
                    }
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
                                                            offset: tcLevelBuff->_offset
                                                           atIndex: kMVKTessEvalLevelBufferIndex];
                    [cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
                                                                        offset: tcLevelBuff->_offset
                                                                instanceStride: 0];
                    // The tessellation control shader produced output in the correct order, so there's no need to use
                    // an index buffer here.
                    [cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
                                                    patchStart: 0
                                                    patchCount: _instanceCount * patchCount
                                              patchIndexBuffer: nil
                                        patchIndexBufferOffset: 0
                                                 instanceCount: 1
                                                  baseInstance: 0];
                    // Mark pipeline, resources, and tess control push constants as dirty
                    // so I apply them during the next stage.
                    cmdEncoder->_graphicsPipelineState.beginMetalRenderPass();
                    cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
                    cmdEncoder->getPushConstants(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT)->beginMetalRenderPass();
                } else {
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
                break;
        }
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

// This is totally arbitrary, but we're forced to do this because we don't know how many vertices
// there are at encoding time. And this will probably be inadequate for large instanced draws.
// TODO: Consider breaking up such draws using different base instance values. But this will
// require yet more munging of the indirect buffers...
static const uint32_t kMVKDrawIndirectVertexCountUpperBound = 131072;

void MVKCmdDrawIndirect::encode(MVKCommandEncoder* cmdEncoder) {

    auto* pipeline = (MVKGraphicsPipeline*)cmdEncoder->_graphicsPipelineState.getPipeline();
    // The indirect calls for dispatchThreadgroups:... and drawPatches:... have different formats.
    // We have to convert from the drawPrimitives:... format to them.
    // While we're at it, we can create the temporary output buffers once and reuse them
    // for each draw.
    const MVKMTLBufferAllocation* tcIndirectBuff = nullptr;
    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tcIndexBuff = nullptr;
    uint32_t patchCount = 0, vertexCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        // We can't read the indirect buffer CPU-side, since it may change between
        // encoding and execution. So we don't know how big to make the buffers.
        // We must assume an arbitrarily large number of vertices may be submitted.
        // But not too many, or we'll exhaust available VRAM.
        inControlPointCount = pipeline->getInputControlPointCount();
        outControlPointCount = pipeline->getOutputControlPointCount();
        vertexCount = kMVKDrawIndirectVertexCountUpperBound;
        patchCount = (uint32_t)mvkCeilingDivide(vertexCount, inControlPointCount);
        VkDeviceSize indirectSize = (sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments)) * _drawCount;
        if (cmdEncoder->_pDeviceMetalFeatures->mslVersion >= 20100) {
            indirectSize += sizeof(MTLStageInRegionIndirectArguments) * _drawCount;
        }
        tcIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize);
        if (pipeline->needsVertexOutputBuffer()) {
            vtxOutBuff = cmdEncoder->getTempMTLBuffer(vertexCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxVertexOutputComponents);
        }
        if (pipeline->needsTessCtlOutputBuffer()) {
            tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * patchCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxTessellationControlPerVertexOutputComponents);
        }
        if (pipeline->needsTessCtlPatchOutputBuffer()) {
            tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(patchCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxTessellationControlPerPatchOutputComponents);
        }
        tcLevelBuff = cmdEncoder->getTempMTLBuffer(patchCount * sizeof(MTLQuadTessellationFactorsHalf));
        if (outControlPointCount > inControlPointCount) {
            // In this case, we use an index buffer to avoid stepping over some of the input points.
            tcIndexBuff = cmdEncoder->getTempMTLBuffer(patchCount * outControlPointCount * 4);
            auto* indices = (uint32_t*)tcIndexBuff->getContents();
            uint32_t index = 0;
            for (uint32_t i = 0; i < tcIndexBuff->_length / 4; i++) {
                if ((i % outControlPointCount) < inControlPointCount) {
                    indices[i] = index++;
                } else {
                    indices[i] = 0;
                }
            }
        }
    }

    MVKVectorInline<uint32_t, 4> stages;
    pipeline->getStages(stages);

    VkDeviceSize mtlIndBuffOfst = _mtlIndirectBufferOffset;
    VkDeviceSize mtlTCIndBuffOfst = tcIndirectBuff ? tcIndirectBuff->_offset : 0;
    for (uint32_t drawIdx = 0; drawIdx < _drawCount; drawIdx++) {
        for (uint32_t s : stages) {
            auto stage = MVKGraphicsStage(s);
            id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;
            if (drawIdx == 0 && stage == kMVKGraphicsStageTessControl) {
                // We need the indirect buffers now. This must be done before finalizing
                // draw state, or the pipeline will get overridden. This is a good time
                // to do it, since it will require switching to compute anyway. Do it all
                // at once to get it over with.
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl);
                id<MTLComputePipelineState> mtlConvertState = getCommandEncodingPool()->getCmdDrawIndirectConvertBuffersMTLComputePipelineState(false);
                [mtlTessCtlEncoder setComputePipelineState: mtlConvertState];
                [mtlTessCtlEncoder setBuffer: _mtlIndirectBuffer
                                      offset: _mtlIndirectBufferOffset
                                     atIndex: 0];
                [mtlTessCtlEncoder setBuffer: tcIndirectBuff->_mtlBuffer
                                      offset: tcIndirectBuff->_offset
                                     atIndex: 1];
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &_mtlIndirectBufferStride,
                                            sizeof(_mtlIndirectBufferStride),
                                            2);
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &inControlPointCount,
                                            sizeof(inControlPointCount),
                                            3);
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &outControlPointCount,
                                            sizeof(inControlPointCount),
                                            4);
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &_drawCount,
                                            sizeof(_drawCount),
                                            5);
                [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
                                  threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 0, 0)];
            }

            cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal

            switch (stage) {
                case kMVKGraphicsStageVertex:
                    if (pipeline->needsVertexOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: vtxOutBuff->_mtlBuffer
                                                                offset: vtxOutBuff->_offset
                                                               atIndex: pipeline->getOutputBufferIndex().stages[kMVKShaderStageVertex]];
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: _mtlIndirectBuffer
                                                                offset: mtlIndBuffOfst
                                                              atIndex: pipeline->getIndirectParamsIndex().stages[kMVKShaderStageVertex]];
                    }
                    [cmdEncoder->_mtlRenderEncoder drawPrimitives: MTLPrimitiveTypePoint
                                                   indirectBuffer: _mtlIndirectBuffer
                                             indirectBufferOffset: mtlIndBuffOfst];
                    mtlIndBuffOfst += _mtlIndirectBufferStride;
                    // Mark pipeline, resources, and tess control push constants as dirty
                    // so I apply them during the next stage.
                    cmdEncoder->_graphicsPipelineState.beginMetalRenderPass();
                    cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
                    cmdEncoder->getPushConstants(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT)->beginMetalRenderPass();
                    break;
                case kMVKGraphicsStageTessControl:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl);
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                              offset: tcOutBuff->_offset
                                             atIndex: pipeline->getOutputBufferIndex().stages[kMVKShaderStageTessCtl]];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                              offset: tcPatchOutBuff->_offset
                                             atIndex: pipeline->getTessCtlPatchOutputBufferIndex()];
                    }
                    [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                          offset: tcLevelBuff->_offset
                                         atIndex: pipeline->getTessCtlLevelBufferIndex()];
                    cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                                &inControlPointCount,
                                                sizeof(inControlPointCount),
                                                pipeline->getIndirectParamsIndex().stages[kMVKShaderStageTessCtl]);
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                              offset: vtxOutBuff->_offset
                                             atIndex: kMVKTessCtlInputBufferIndex];
                        if ([mtlTessCtlEncoder respondsToSelector: @selector(setStageInRegionWithIndirectBuffer:indirectBufferOffset:)]) {
                            [mtlTessCtlEncoder setStageInRegionWithIndirectBuffer: tcIndirectBuff->_mtlBuffer
                                                             indirectBufferOffset: mtlTCIndBuffOfst];
                            mtlTCIndBuffOfst += sizeof(MTLStageInRegionIndirectArguments);
                        } else {
                            // We must assume we can read up to the maximum number of vertices.
                            [mtlTessCtlEncoder setStageInRegion: MTLRegionMake1D(0, std::max(inControlPointCount, outControlPointCount) * patchCount)];
                        }
                    }
                    if (outControlPointCount > inControlPointCount) {
                        [mtlTessCtlEncoder setBuffer: tcIndexBuff->_mtlBuffer
                                              offset: tcIndexBuff->_offset
                                             atIndex: kMVKTessCtlIndexBufferIndex];
                    }
                    [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: tcIndirectBuff->_mtlBuffer
                                                         indirectBufferOffset: mtlTCIndBuffOfst
                                                        threadsPerThreadgroup: MTLSizeMake(std::max(inControlPointCount, outControlPointCount), 1, 1)];
                    mtlTCIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    // Running this stage prematurely ended the render pass, so we have to start it up again.
                    // TODO: On iOS, maybe we could use a tile shader to avoid this.
                    cmdEncoder->beginMetalRenderPass();
                    break;
                case kMVKGraphicsStageRasterization:
                    if (pipeline->isTessellationPipeline()) {
                        if (pipeline->needsTessCtlOutputBuffer()) {
                            [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
                                                                    offset: tcOutBuff->_offset
                                                                   atIndex: kMVKTessEvalInputBufferIndex];
                        }
                        if (pipeline->needsTessCtlPatchOutputBuffer()) {
                            [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
                                                                    offset: tcPatchOutBuff->_offset
                                                                   atIndex: kMVKTessEvalPatchInputBufferIndex];
                        }
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
                                                                offset: tcLevelBuff->_offset
                                                               atIndex: kMVKTessEvalLevelBufferIndex];
                        [cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
                                                                            offset: tcLevelBuff->_offset
                                                                    instanceStride: 0];
                        [cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
                                                  patchIndexBuffer: nil
                                            patchIndexBufferOffset: 0
                                                    indirectBuffer: tcIndirectBuff->_mtlBuffer
                                              indirectBufferOffset: mtlTCIndBuffOfst];
                        mtlTCIndBuffOfst += sizeof(MTLDrawPatchIndirectArguments);
                        // Mark pipeline, resources, and tess control push constants as dirty
                        // so I apply them during the next stage.
                        cmdEncoder->_graphicsPipelineState.beginMetalRenderPass();
                        cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
                        cmdEncoder->getPushConstants(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT)->beginMetalRenderPass();
                    } else {
                        [cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->_mtlPrimitiveType
                                                       indirectBuffer: _mtlIndirectBuffer
                                                 indirectBufferOffset: mtlIndBuffOfst];
                            mtlIndBuffOfst += _mtlIndirectBufferStride;
                    }
                    break;
            }
        }
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

    MVKIndexMTLBufferBinding& ibb = cmdEncoder->_graphicsResourcesState._mtlIndexBufferBinding;
    size_t idxSize = mvkMTLIndexTypeSizeInBytes(ibb.mtlIndexType);
    auto* pipeline = (MVKGraphicsPipeline*)cmdEncoder->_graphicsPipelineState.getPipeline();
    // The indirect calls for dispatchThreadgroups:... and drawPatches:... have different formats.
    // We have to convert from the drawIndexedPrimitives:... format to them.
    // While we're at it, we can create the temporary output buffers once and reuse them
    // for each draw.
    const MVKMTLBufferAllocation* tcIndirectBuff = nullptr;
    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tcIndexBuff = nullptr;
    uint32_t patchCount = 0, vertexCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        // We can't read the indirect buffer CPU-side, since it may change between
        // encoding and execution. So we don't know how big to make the buffers.
        // We must assume an arbitrarily large number of vertices may be submitted.
        // But not too many, or we'll exhaust available VRAM.
        inControlPointCount = pipeline->getInputControlPointCount();
        outControlPointCount = pipeline->getOutputControlPointCount();
        vertexCount = kMVKDrawIndirectVertexCountUpperBound;
        patchCount = (uint32_t)mvkCeilingDivide(vertexCount, inControlPointCount);
        VkDeviceSize indirectSize = (sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments)) * _drawCount;
        if (cmdEncoder->_pDeviceMetalFeatures->mslVersion >= 20100) {
            indirectSize += sizeof(MTLStageInRegionIndirectArguments) * _drawCount;
        }
        tcIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize);
        if (pipeline->needsVertexOutputBuffer()) {
            vtxOutBuff = cmdEncoder->getTempMTLBuffer(vertexCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxVertexOutputComponents);
        }
        if (pipeline->needsTessCtlOutputBuffer()) {
            tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * patchCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxTessellationControlPerVertexOutputComponents);
        }
        if (pipeline->needsTessCtlPatchOutputBuffer()) {
            tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(patchCount * 4 * cmdEncoder->_pDeviceProperties->limits.maxTessellationControlPerPatchOutputComponents);
        }
        tcLevelBuff = cmdEncoder->getTempMTLBuffer(patchCount * sizeof(MTLQuadTessellationFactorsHalf));
        tcIndexBuff = cmdEncoder->getTempMTLBuffer(patchCount * outControlPointCount * idxSize);
    }

    MVKVectorInline<uint32_t, 4> stages;
    pipeline->getStages(stages);

    VkDeviceSize mtlIndBuffOfst = _mtlIndirectBufferOffset;
    VkDeviceSize mtlTCIndBuffOfst = tcIndirectBuff ? tcIndirectBuff->_offset : 0;
    for (uint32_t drawIdx = 0; drawIdx < _drawCount; drawIdx++) {
        for (uint32_t s : stages) {
            auto stage = MVKGraphicsStage(s);
            id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;
            if (stage == kMVKGraphicsStageTessControl) {
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl);
                // We need the indirect buffers now. This must be done before finalizing
                // draw state, or the pipeline will get overridden. This is a good time
                // to do it, since it will require switching to compute anyway. Do it all
                // at once to get it over with.
                if (drawIdx == 0) {
                    id<MTLComputePipelineState> mtlConvertState = getCommandEncodingPool()->getCmdDrawIndirectConvertBuffersMTLComputePipelineState(true);
                    [mtlTessCtlEncoder setComputePipelineState: mtlConvertState];
                    [mtlTessCtlEncoder setBuffer: _mtlIndirectBuffer
                                          offset: _mtlIndirectBufferOffset
                                         atIndex: 0];
                    [mtlTessCtlEncoder setBuffer: tcIndirectBuff->_mtlBuffer
                                          offset: tcIndirectBuff->_offset
                                         atIndex: 1];
                    cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                                &_mtlIndirectBufferStride,
                                                sizeof(_mtlIndirectBufferStride),
                                                2);
                    cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                                &inControlPointCount,
                                                sizeof(inControlPointCount),
                                                3);
                    cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                                &outControlPointCount,
                                                sizeof(inControlPointCount),
                                                4);
                    cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                                &_drawCount,
                                                sizeof(_drawCount),
                                                5);
                    [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
                                      threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                }
                // We actually need to make a copy of the index buffer, regardless of whether
                // or not there are gaps in it, because there's no way to tell Metal to
                // offset an index buffer from a value in an indirect buffer. This also
                // means that, to make a copy, we have to use a compute shader.
                id<MTLComputePipelineState> mtlCopyIndexState = getCommandEncodingPool()->getCmdDrawIndexedCopyIndexBufferMTLComputePipelineState(ibb.mtlIndexType);
                [mtlTessCtlEncoder setComputePipelineState: mtlCopyIndexState];
                [mtlTessCtlEncoder setBuffer: ibb.mtlBuffer
                                      offset: ibb.offset
                                     atIndex: 0];
                [mtlTessCtlEncoder setBuffer: tcIndexBuff->_mtlBuffer
                                      offset: tcIndexBuff->_offset
                                     atIndex: 1];
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &inControlPointCount,
                                            sizeof(inControlPointCount),
                                            2);
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &outControlPointCount,
                                            sizeof(outControlPointCount),
                                            3);
                [mtlTessCtlEncoder setBuffer: tcIndirectBuff->_mtlBuffer
                                      offset: mtlTCIndBuffOfst
                                     atIndex: 4];
                [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(1, 1, 1) threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
            }

	        cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal

            switch (stage) {
                case kMVKGraphicsStageVertex:
                    if (pipeline->needsVertexOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: vtxOutBuff->_mtlBuffer
                                                                offset: vtxOutBuff->_offset
                                                               atIndex: pipeline->getOutputBufferIndex().stages[kMVKShaderStageVertex]];
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: _mtlIndirectBuffer
                                                                offset: mtlIndBuffOfst
                                                              atIndex: pipeline->getIndirectParamsIndex().stages[kMVKShaderStageVertex]];
                    }
                    [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: MTLPrimitiveTypePoint
                                                               indexType: ibb.mtlIndexType
                                                             indexBuffer: ibb.mtlBuffer
                                                       indexBufferOffset: ibb.offset
                                                          indirectBuffer: _mtlIndirectBuffer
                                                    indirectBufferOffset: mtlIndBuffOfst];
                    mtlIndBuffOfst += _mtlIndirectBufferStride;
                    // Mark pipeline, resources, and tess control push constants as dirty
                    // so I apply them during the next stage.
                    cmdEncoder->_graphicsPipelineState.beginMetalRenderPass();
                    cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
                    cmdEncoder->getPushConstants(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT)->beginMetalRenderPass();
                    break;
                case kMVKGraphicsStageTessControl:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl);
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                              offset: tcOutBuff->_offset
                                             atIndex: pipeline->getOutputBufferIndex().stages[kMVKShaderStageTessCtl]];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                              offset: tcPatchOutBuff->_offset
                                             atIndex: pipeline->getTessCtlPatchOutputBufferIndex()];
                    }
                    [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                          offset: tcLevelBuff->_offset
                                         atIndex: pipeline->getTessCtlLevelBufferIndex()];
                    cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                                &inControlPointCount,
                                                sizeof(inControlPointCount),
                                                pipeline->getIndirectParamsIndex().stages[kMVKShaderStageTessCtl]);
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                              offset: vtxOutBuff->_offset
                                             atIndex: kMVKTessCtlInputBufferIndex];
                        if ([mtlTessCtlEncoder respondsToSelector: @selector(setStageInRegionWithIndirectBuffer:indirectBufferOffset:)]) {
                            [mtlTessCtlEncoder setStageInRegionWithIndirectBuffer: tcIndirectBuff->_mtlBuffer
                                                             indirectBufferOffset: mtlTCIndBuffOfst];
                            mtlTCIndBuffOfst += sizeof(MTLStageInRegionIndirectArguments);
                        } else {
                            // We must assume we can read up to the maximum number of vertices.
                            [mtlTessCtlEncoder setStageInRegion: MTLRegionMake1D(0, std::max(inControlPointCount, outControlPointCount) * patchCount)];
                        }
                    }
                    [mtlTessCtlEncoder setBuffer: tcIndexBuff->_mtlBuffer
                                          offset: tcIndexBuff->_offset
                                         atIndex: kMVKTessCtlIndexBufferIndex];
                    [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: tcIndirectBuff->_mtlBuffer
                                                         indirectBufferOffset: mtlTCIndBuffOfst
                                                        threadsPerThreadgroup: MTLSizeMake(std::max(inControlPointCount, outControlPointCount), 1, 1)];
                    mtlTCIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    // Running this stage prematurely ended the render pass, so we have to start it up again.
                    // TODO: On iOS, maybe we could use a tile shader to avoid this.
                    cmdEncoder->beginMetalRenderPass();
                    break;
                case kMVKGraphicsStageRasterization:
                    if (pipeline->isTessellationPipeline()) {
                        if (pipeline->needsTessCtlOutputBuffer()) {
                            [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
                                                                    offset: tcOutBuff->_offset
                                                                   atIndex: kMVKTessEvalInputBufferIndex];
                        }
                        if (pipeline->needsTessCtlPatchOutputBuffer()) {
                            [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
                                                                    offset: tcPatchOutBuff->_offset
                                                                   atIndex: kMVKTessEvalPatchInputBufferIndex];
                        }
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
                                                                offset: tcLevelBuff->_offset
                                                               atIndex: kMVKTessEvalLevelBufferIndex];
                        [cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
                                                                            offset: tcLevelBuff->_offset
                                                                    instanceStride: 0];
                        [cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
                                                  patchIndexBuffer: nil
                                            patchIndexBufferOffset: 0
                                                    indirectBuffer: tcIndirectBuff->_mtlBuffer
                                              indirectBufferOffset: mtlTCIndBuffOfst];
                        mtlTCIndBuffOfst += sizeof(MTLDrawPatchIndirectArguments);
                        // Mark pipeline, resources, and tess control push constants as dirty
                        // so I apply them during the next stage.
                        cmdEncoder->_graphicsPipelineState.beginMetalRenderPass();
                        cmdEncoder->_graphicsResourcesState.beginMetalRenderPass();
                        cmdEncoder->getPushConstants(VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT)->beginMetalRenderPass();
                    } else {
                        [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->_mtlPrimitiveType
                                                                   indexType: ibb.mtlIndexType
                                                                 indexBuffer: ibb.mtlBuffer
                                                           indexBufferOffset: ibb.offset
                                                              indirectBuffer: _mtlIndirectBuffer
                                                        indirectBufferOffset: mtlIndBuffOfst];
                        mtlIndBuffOfst += _mtlIndirectBufferStride;
                    }
                    break;
            }
        }
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


