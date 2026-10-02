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
#include "MVKPerVertexReplay.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKBuffer.h"
#include "MVKPipeline.h"
#include "MVKFramebuffer.h"
#include "MVKImage.h"
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
	cmdBuff->recordIndexType(indexType);
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


static VkResult recordTessPatchCount(MVKCommandBuffer* cmdBuff, uint32_t vertexCount, uint32_t instanceCount);

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

	VkResult result = recordTessPatchCount(cmdBuff, _vertexCount, _instanceCount);
	return result == VK_SUCCESS ? cmdBuff->recordPerVertexDraw(_vertexCount, _instanceCount) : result;
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
	VkResult result = diiCmd.setContent(cmdEncoder->_cmdBuffer, indirectIdxBuff->_mtlBuffer, indirectIdxBuff->_offset, 1, indirectIdxBuffStride);
	if (result != VK_SUCCESS) { cmdEncoder->_cmdBuffer->setConfigurationResult(result); return; }
	diiCmd.encode(cmdEncoder, ibb);
}

static void encodePerVertexInput(MVKCommandEncoder* cmdEncoder, MVKGraphicsPipeline* pipeline, uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance, uint32_t drawIndex, const MVKIndexMTLBufferBinding* indexBinding = nullptr, uint32_t firstIndex = 0, int32_t baseVertex = 0) {
	// A draw refused while encoding also loses the device: vkQueueSubmit() may have returned, and the submission must
	// never complete without it.
	auto reject = [&](VkResult result, const char* message) {
		cmdEncoder->_cmdBuffer->setConfigurationResult(cmdEncoder->_cmdBuffer->reportError(result, "Portable PerVertexKHR %s", message));
		cmdEncoder->getDevice()->markLost();
		cmdEncoder->stopEncoding();
	};
	auto* subpass = cmdEncoder->getSubpass();
	uint32_t viewCount = subpass->isMultiview() ? subpass->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
	uint64_t physicalInstances = uint64_t(instanceCount) * viewCount;
	if (!viewCount || physicalInstances > UINT32_MAX) { reject(VK_ERROR_OUT_OF_DEVICE_MEMORY, "view-expanded instance count exceeds uint32."); return; }
	instanceCount = uint32_t(physicalInstances);
	// Vulkan ignores primitiveRestartEnable for nonindexed draws.
	bool restart = mvkPerVertexRequiresRestartAssembly(indexBinding != nullptr, cmdEncoder->getVkGraphics().isPrimitiveRestartEnabled());
	if (restart && !mvkCanAssemblePerVertexRestart(vertexCount, instanceCount, cmdEncoder->getMetalFeatures().indirectDrawing)) { reject(VK_ERROR_FEATURE_NOT_PRESENT, "restart requires indirect drawing and uint32 dense capture record IDs."); return; }
	auto* scratch = cmdEncoder->nextPerVertexScratch();
	if (!scratch) { return; }
	id<MTLRenderPipelineState> directCaptureState = indexBinding ? nil : pipeline->getPerVertexCapturePipelineState(viewCount);
	if (!indexBinding && !directCaptureState) { reject(VK_ERROR_FEATURE_NOT_PRESENT, "direct capture view-count pipeline is unavailable."); return; }
	id<MTLComputePipelineState> captureState = nil;
	id<MTLComputePipelineState> widenState = nil;
	id<MTLComputePipelineState> restartState = nil;
	id<MTLBuffer> indexBuffer = indexBinding ? indexBinding->mtlBuffer : nil;
	VkDeviceSize indexOffset = 0;
	if (indexBinding) {
		uint32_t indexSize = mvkPerVertexIndexSize(indexBinding->vkIndexType);
		if (!indexSize) { reject(VK_ERROR_FEATURE_NOT_PRESENT, "indexed capture requires uint8, uint16 or uint32 indices."); return; }
		if (!indexBuffer || !mvkPerVertexIndexRange(vertexCount, firstIndex, indexBinding->vkIndexType, indexBinding->size, indexBinding->offset, indexBuffer.length)) { reject(VK_ERROR_UNKNOWN, "indexed capture exceeds the bound index buffer range."); return; }
		indexOffset = indexBinding->offset + uint64_t(firstIndex) * indexSize;
		captureState = pipeline->getPerVertexIndexedCapturePipelineState(restart || indexSize == 4, viewCount);
		if (restart) {
			if (!scratch->buffers[5] || scratch->buffers[5].length < mvkPerVertexRestartIndexScratchSize(vertexCount) || !scratch->buffers[6] || scratch->buffers[6].length < 68 * sizeof(uint32_t)) { reject(VK_ERROR_OUT_OF_DEVICE_MEMORY, "restart assembly scratch is unavailable."); return; }
			restartState = scratch->indexPipeline;
			if (!restartState || !restartState.threadExecutionWidth || !restartState.maxTotalThreadsPerThreadgroup) { reject(VK_ERROR_FEATURE_NOT_PRESENT, "restart assembly pipeline is unavailable."); return; }
		} else if (indexSize == 1) {
			if (!scratch->buffers[5] || scratch->buffers[5].length < uint64_t(vertexCount) * sizeof(uint16_t)) { reject(VK_ERROR_OUT_OF_DEVICE_MEMORY, "widened index scratch is unavailable."); return; }
			// Restart is disabled: 255 is a vertex index, not a sentinel. Read on GPU.
			widenState = scratch->widenUint8Pipeline ?: scratch->indexPipeline;
			if (!widenState || !widenState.maxTotalThreadsPerThreadgroup || !widenState.threadExecutionWidth) { reject(VK_ERROR_FEATURE_NOT_PRESENT, "raw uint8 index conversion is unavailable."); return; }
		}
		if (!captureState || !captureState.maxTotalThreadsPerThreadgroup || !captureState.threadExecutionWidth) { reject(VK_ERROR_FEATURE_NOT_PRESENT, "indexed compute capture pipeline is unavailable."); return; }
	}
	// Both captures end the render encoder: compute for indexed draws, a render pass boundary for nonindexed ones.
	if (const char* error = cmdEncoder->getIndexedPerVertexAttachmentError()) { reject(VK_ERROR_FEATURE_NOT_PRESENT, error); return; }
	const auto& layout = pipeline->getPerVertexCapturedLayout();
	auto topology = cmdEncoder->getVkGraphics().getPrimitiveTopology();
	bool provokingLast = cmdEncoder->getVkGraphics().getProvokingVertexMode();
	uint64_t primitivesPerInstance = mvkPerVertexPrimitiveCount(vertexCount, topology);
	uint32_t replayVertices = mvkPerVertexReplayVertexCount(topology);
	uint64_t primitiveCount = primitivesPerInstance * instanceCount;
	uint64_t replayCount = primitivesPerInstance * replayVertices;
	if (!mvkCanEncodePerVertexDraw(vertexCount, instanceCount, layout.stride, topology, cmdEncoder->getMetalFeatures().maxMTLBufferSize)) {
		reject(VK_ERROR_OUT_OF_DEVICE_MEMORY, "draw exceeds its capture or replay buffer limits.");
		return;
	}
	id<MTLBuffer> captured = scratch->buffers[0];
	id<MTLBuffer> captureParams = scratch->buffers[1];
	id<MTLBuffer> occurrences = scratch->buffers[2];
	id<MTLBuffer> primitiveIndices = scratch->buffers[3];
	*(uint32_t*)captureParams.contents = vertexCount;
	cmdEncoder->_isIndexedDraw = indexBinding != nullptr;
	if (indexBinding) {
		// Capture uses vertexCount records per instance; restart compacts occurrences within that stride.
		// Indices are read on the GPU, including writes earlier in this command buffer.
		cmdEncoder->finalizeDrawState(kMVKGraphicsStageVertex);
		if (!pipeline->hasValidMTLPipelineStates()) { return; }
		id<MTLComputeCommandEncoder> captureEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
		auto& computeState = cmdEncoder->getMtlCompute();
		if (restartState) {
			computeState.bindPipeline(captureEncoder, restartState);
			computeState.bindBuffer(captureEncoder, indexBuffer, indexOffset, 0);
			computeState.bindBuffer(captureEncoder, scratch->buffers[5], 0, 1);
			computeState.bindBuffer(captureEncoder, occurrences ?: scratch->buffers[5], 0, 2);
			computeState.bindBuffer(captureEncoder, primitiveIndices ?: scratch->buffers[5], 0, 3);
			computeState.bindBuffer(captureEncoder, scratch->buffers[4] ?: scratch->buffers[5], 0, 4);
			computeState.bindBuffer(captureEncoder, scratch->buffers[6], 0, 5);
			uint32_t params[] = {vertexCount, instanceCount, mvkPerVertexIndexSize(indexBinding->vkIndexType), uint32_t(topology), uint32_t(provokingLast), firstInstance, uint32_t(pipeline->usesPortableBarycentrics()), 0, 0, 0};
			NSUInteger width = std::min(restartState.threadExecutionWidth, restartState.maxTotalThreadsPerThreadgroup);
			mvkDispatchPerVertexRestart(vertexCount, instanceCount, topology, [&](uint32_t phase, uint32_t step, uint32_t source, uint64_t count) {
				params[7] = phase; params[8] = step; params[9] = source;
				computeState.bindBytes(captureEncoder, params, sizeof(params), 6);
				[captureEncoder dispatchThreadgroups: MTLSizeMake((count + width - 1) / width, 1, 1) threadsPerThreadgroup: MTLSizeMake(width, 1, 1)];
				[captureEncoder memoryBarrierWithScope: MTLBarrierScopeBuffers];
			});
			indexBuffer = scratch->buffers[5];
			indexOffset = 0;
			// Restore application resources after the assembly kernel occupied slots 0..6.
			computeState._exists.descriptorSetData.reset();
			cmdEncoder->finalizeDrawState(kMVKGraphicsStageVertex);
			computeState.bindPipeline(captureEncoder, captureState);
		}
		if (widenState) {
			computeState.bindPipeline(captureEncoder, widenState);
			computeState.bindBuffer(captureEncoder, indexBuffer, indexOffset, 0);
			computeState.bindBuffer(captureEncoder, scratch->buffers[5], 0, 1);
			NSUInteger width = std::min(widenState.threadExecutionWidth, widenState.maxTotalThreadsPerThreadgroup);
			// The existing raw kernel has no bounds check: dispatch exactly vertexCount threads.
			NSUInteger groups = vertexCount / width, remainder = vertexCount % width;
			if (groups) { [captureEncoder dispatchThreadgroups: MTLSizeMake(groups, 1, 1) threadsPerThreadgroup: MTLSizeMake(width, 1, 1)]; }
			if (remainder) {
				computeState.bindBuffer(captureEncoder, indexBuffer, indexOffset + groups * width, 0);
				computeState.bindBuffer(captureEncoder, scratch->buffers[5], groups * width * sizeof(uint16_t), 1);
				[captureEncoder dispatchThreadgroups: MTLSizeMake(1, 1, 1) threadsPerThreadgroup: MTLSizeMake(remainder, 1, 1)];
			}
			[captureEncoder memoryBarrierWithScope: MTLBarrierScopeBuffers];
			indexBuffer = scratch->buffers[5];
			indexOffset = 0;
			// Raw conversion overwrote slots 0/1 and the pipeline. Restore application bindings.
			computeState._exists.descriptorSetData.reset();
			cmdEncoder->finalizeDrawState(kMVKGraphicsStageVertex);
			computeState.bindPipeline(captureEncoder, captureState);
		}
		computeState.bindBuffer(captureEncoder, captured, 0, pipeline->getPerVertexCaptureBufferIndex());
		computeState.bindBuffer(captureEncoder, indexBuffer, indexOffset, pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Index]);
		if (pipeline->needsDrawIdBuffer()) { computeState.bindStructBytes(captureEncoder, &drawIndex, pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]); }
		// Preserve the signed base vertex as the uint32 bit pattern used by SPIR-V.
		[captureEncoder setStageInRegion: MTLRegionMake2D(uint32_t(baseVertex), firstInstance, vertexCount, instanceCount)];
		cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, kMVKGraphicsStageVertex, pipeline, firstInstance);
		NSUInteger width = std::min(captureState.threadExecutionWidth, captureState.maxTotalThreadsPerThreadgroup);
		if (restart) {
			// Only compact occurrences execute; grid_size (capture stride) remains the original stage-in region.
			[captureEncoder dispatchThreadgroupsWithIndirectBuffer: scratch->buffers[6] indirectBufferOffset: 0 threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
		} else if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
			[captureEncoder dispatchThreads: MTLSizeMake(vertexCount, instanceCount, 1) threadsPerThreadgroup: MTLSizeMake(width, 1, 1)];
		} else {
			[captureEncoder dispatchThreadgroups: MTLSizeMake(vertexCount, instanceCount, 1) threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
		}
		cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
	}
	cmdEncoder->_isIndexedDraw = false;
	cmdEncoder->finalizeDrawState(kMVKGraphicsStageRasterization);
	if (!pipeline->hasValidMTLPipelineStates()) { return; }
	id<MTLRenderCommandEncoder> encoder = cmdEncoder->_mtlRenderEncoder;
	auto& metalState = cmdEncoder->getMtlGraphics();
	if (!indexBinding) {
		[encoder setRenderPipelineState: directCaptureState];
		MTLPrimitiveType captureType = pipeline->capturesPerVertexTriangleLists() ? MTLPrimitiveTypeTriangle : MTLPrimitiveTypePoint;
		metalState.bindVertexBuffer(encoder, captured, 0, pipeline->getPerVertexCaptureBufferIndex());
		metalState.bindVertexBuffer(encoder, captureParams, 0, pipeline->getPerVertexCaptureParamsBufferIndex());
		cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, kMVKGraphicsStageRasterization, pipeline, firstInstance);
		if (pipeline->needsDrawIdBuffer()) { metalState.bindVertexBytes(encoder, &drawIndex, sizeof(drawIndex), pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]); }
		if (cmdEncoder->getMetalFeatures().baseVertexInstanceDrawing) {
			[encoder drawPrimitives: captureType vertexStart: firstVertex vertexCount: vertexCount instanceCount: instanceCount baseInstance: firstInstance];
		} else {
			[encoder drawPrimitives: captureType vertexStart: firstVertex vertexCount: vertexCount instanceCount: instanceCount];
		}
	}
	if (!primitiveCount) {
		[encoder setRenderPipelineState: pipeline->getMainPipelineState()];
		metalState._exists.vertex().descriptorSetData.reset();
		return;
	}
	if (!indexBinding) {
		// The replay reads what the capture wrote: separate them by a render pass boundary. Like MVKCmdPipelineBarrier,
		// this avoids memory barriers inside a render pass on Apple GPUs. Metal shader validation on iOS and iPadOS 27
		// silently ignores them, and the replay then draws nothing (Tests/PerVertexBarrierRepro, FB24976351).
		cmdEncoder->encodeStoreActions(true);
		cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
		cmdEncoder->finalizeDrawState(kMVKGraphicsStageRasterization);
		if (!pipeline->hasValidMTLPipelineStates()) { return; }
		encoder = cmdEncoder->_mtlRenderEncoder;
	}
	auto* pairs = (uint32_t*)occurrences.contents;
	auto* indices = (uint32_t*)primitiveIndices.contents;
	auto* corners = (uint32_t*)scratch->buffers[4].contents;
	if (!restart) { mvkPopulatePerVertexReplay(vertexCount, instanceCount, topology, provokingLast, pairs, indices, corners); }
	const auto& replay = pipeline->getPerVertexReplayBinding();
	const auto& fragment = pipeline->getPerVertexInputBinding();
	uint32_t replayDraw[] = {0, 0, firstInstance, uint32_t(replayCount)};
	[encoder setRenderPipelineState: pipeline->getMainPipelineState()];
	metalState.bindVertexBuffer(encoder, captured, 0, replay.vertex_buffer_index);
	metalState.bindVertexBuffer(encoder, occurrences, 0, replay.occurrence_buffer_index);
	if (corners) { metalState.bindVertexBuffer(encoder, scratch->buffers[4], 0, pipeline->getPerVertexReplayBarycentricBinding().corner_buffer_index); }
	if (restart) { metalState.bindVertexBuffer(encoder, scratch->buffers[6], 256, replay.draw_parameters_buffer_index); }
	else { metalState.bindVertexBytes(encoder, replayDraw, sizeof(replayDraw), replay.draw_parameters_buffer_index); }
	if (fragment.vertex_buffer_index != ~0u) {
		metalState.bindFragmentBuffer(encoder, captured, 0, fragment.vertex_buffer_index);
		metalState.bindFragmentBuffer(encoder, primitiveIndices, 0, fragment.primitive_index_buffer_index);
	}
	if (cmdEncoder->getPhysicalDevice()->shouldEmulateReversedDepthViewport()) {
		uint32_t viewportMask = cmdEncoder->getVkGraphics()._implicitBufferData[kMVKShaderStageVertex].emulatedReversedDepthViewportMask;
		metalState.bindVertexBytes(encoder, &viewportMask, sizeof(viewportMask), pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::EmulatedReversedDepthViewport]);
	}
	MTLPrimitiveType replayType = replayVertices == 1 ? MTLPrimitiveTypePoint : replayVertices == 2 ? MTLPrimitiveTypeLine : MTLPrimitiveTypeTriangle;
	if (restart) {
		[encoder drawPrimitives: replayType indirectBuffer: scratch->buffers[6] indirectBufferOffset: 4 * sizeof(uint32_t)];
	} else if (cmdEncoder->getMetalFeatures().baseVertexInstanceDrawing) {
		[encoder drawPrimitives: replayType vertexStart: 0 vertexCount: replayCount instanceCount: instanceCount baseInstance: firstInstance];
	} else {
		[encoder drawPrimitives: replayType vertexStart: 0 vertexCount: replayCount instanceCount: instanceCount];
	}
	metalState._exists.vertex().descriptorSetData.reset();
	metalState._exists.fragment().descriptorSetData.reset();
}

// Portable PerVertexKHR tessellation of triangle patches with equal spacing (test-only admission, see
// MVKPipeline.mm). VS and TCS run in compute as for ordinary tessellation, the TCS writing float32 levels.
// A GPU pass classifies each patch from those levels and lays out its proven Metal topology as ordered
// corner records; TES runs in compute over those records and the replay draws them. The CPU never reads
// or infers a level. The encoder waits for the classification: levels without a proven topology lose the
// device before any later command or signal of the submission is encoded. VS/TCS effects of that draw have
// already executed by then.
static void encodePerVertexTessEval(MVKCommandEncoder* cmdEncoder, MVKGraphicsPipeline* pipeline, uint32_t vertexCount, uint32_t firstVertex, uint32_t firstInstance, uint32_t drawIndex) {
	auto lose = [&](const char* reason) {
		cmdEncoder->reportError(VK_ERROR_DEVICE_LOST, "PerVertex TES draw was not rendered: %s.", reason);
		cmdEncoder->getDevice()->markLost();
		cmdEncoder->stopEncoding();
	};
	// Encoding runs after vkQueueSubmit() returned: a draw that cannot be encoded also loses the device, so that
	// the submission never completes without it.
	auto reject = [&](VkResult result, const char* message) {
		cmdEncoder->_cmdBuffer->setConfigurationResult(cmdEncoder->_cmdBuffer->reportError(result, "PerVertex TES %s", message));
		cmdEncoder->getDevice()->markLost();
		cmdEncoder->stopEncoding();
	};
	if (const char* error = cmdEncoder->getIndexedPerVertexAttachmentError()) { reject(VK_ERROR_FEATURE_NOT_PRESENT, error); return; }
	uint32_t patches = vertexCount / 3;
	auto* scratch = cmdEncoder->nextPerVertexScratch();
	if (!scratch) { return; }
	id<MTLComputePipelineState> topology = scratch->tessTopologyPipeline;
	id<MTLBuffer> levels = scratch->buffers[11], plan = scratch->buffers[12], invocations = scratch->buffers[7];
	if (patches && (!topology || !levels || !plan || !invocations)) { reject(VK_ERROR_INITIALIZATION_FAILED, "draw has no topology scratch."); return; }
	cmdEncoder->_isIndexedDraw = false;
	cmdEncoder->finalizeDrawState(kMVKGraphicsStageVertex);
	id<MTLComputeCommandEncoder> compute = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
	auto& computeState = cmdEncoder->getState().mtlCompute();
	computeState.bindBuffer(compute, scratch->buffers[8], 0, pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]);
	// The VS reads the DrawID of this draw within its vkCmdDrawMulti*EXT() call, as for ordinary tessellation.
	if (pipeline->needsDrawIdBuffer()) { computeState.bindStructBytes(compute, &drawIndex, pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]); }
	// As for ordinary tessellation, the stage-in origin offsets attribute fetches and gl_VertexIndex/gl_InstanceIndex;
	// outputs stay indexed from 0. Divisors are refused at pipeline creation, so no zero-divisor binding needs an offset.
	[compute setStageInRegion:MTLRegionMake2D(firstVertex, firstInstance, vertexCount, 1)];
	[compute dispatchThreads:MTLSizeMake(vertexCount, 1, 1) threadsPerThreadgroup:MTLSizeMake(pipeline->getTessVertexStageState().threadExecutionWidth, 1, 1)];
	// Vulkan runs the VS for every vertex, including those that complete no patch; nothing is tessellated then.
	if (!patches) { cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass); return; }
	[compute memoryBarrierWithScope:MTLBarrierScopeBuffers];
	cmdEncoder->finalizeDrawState(kMVKGraphicsStageTessControl);
	const auto& tcs = pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids;
	computeState.bindBuffer(compute, scratch->buffers[8], 0, cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding));
	computeState.bindBuffer(compute, scratch->buffers[9], 0, tcs[MVKImplicitBuffer::Output]);
	computeState.bindBuffer(compute, scratch->buffers[10], 0, tcs[MVKImplicitBuffer::PatchOutput]);
	computeState.bindBuffer(compute, levels, 0, tcs[MVKImplicitBuffer::TessLevel]);
	uint32_t tessParams[] = {3, patches};
	computeState.bindBytes(compute, tessParams, sizeof(tessParams), tcs[MVKImplicitBuffer::IndirectParams]);
	NSUInteger groupSize = mvkLeastCommonMultiple(3u, uint32_t(pipeline->getTessControlStageState().threadExecutionWidth));
	[compute dispatchThreads:MTLSizeMake(uint64_t(patches) * 3, 1, 1) threadsPerThreadgroup:MTLSizeMake(groupSize, 1, 1)];
	[compute memoryBarrierWithScope:MTLBarrierScopeBuffers];
	// Classify patches from the written levels, prefix their triangle counts, then emit ordered corner records.
	float maxLevel = float(cmdEncoder->getDeviceProperties().limits.maxTessellationGenerationLevel);
	uint32_t primitiveIds = uint32_t(mvkPerVertexTessPrimitiveIdOffset(patches));
	uint32_t params[] = {patches, *(uint32_t*)&maxLevel, uint32_t(pipeline->perVertexTessReversesCorners()), uint32_t(scratch->buffers[4] != nil), 0, primitiveIds / 4};
	NSUInteger width = std::min(topology.threadExecutionWidth, topology.maxTotalThreadsPerThreadgroup);
	computeState.bindPipeline(compute, topology);
	computeState.bindBuffer(compute, levels, 0, 0);
	computeState.bindBuffer(compute, plan, 0, 1);
	computeState.bindBuffer(compute, invocations, 0, 2);
	computeState.bindBuffer(compute, scratch->buffers[2], 0, 3);
	computeState.bindBuffer(compute, scratch->buffers[3], 0, 4);
	computeState.bindBuffer(compute, scratch->buffers[4] ?: plan, 0, 5);
	for (uint32_t phase = 0; phase < 3; ++phase) {
		params[4] = phase;
		computeState.bindBytes(compute, params, sizeof(params), 6);
		[compute dispatchThreads:MTLSizeMake(phase == 1 ? 1 : patches, 1, 1) threadsPerThreadgroup:MTLSizeMake(phase == 1 ? 1 : width, 1, 1)];
		[compute memoryBarrierWithScope:MTLBarrierScopeBuffers];
	}
	computeState._exists.descriptorSetData.reset();
	if ( !cmdEncoder->awaitEncodedWork() ) {
		if ( !cmdEncoder->getDevice()->isLosing() ) { lose("its topology pass did not complete"); }
		return;
	}
	if (scratch->getTessEvalStatus()) { lose("a patch has tessellation levels without a proven topology"); return; }
	compute = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
	// TES reads the record count the generator wrote; surplus threads of the maximum grid return at once.
	cmdEncoder->getState().prepareTessEvalDispatch(compute, *cmdEncoder);
	const auto& tes = pipeline->getImplicitBuffers(kMVKShaderStageTessEval).ids;
	computeState.bindBuffer(compute, scratch->buffers[9], 0, cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding));
	computeState.bindBuffer(compute, scratch->buffers[10], 0, cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding));
	computeState.bindBuffer(compute, levels, 0, cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding));
	computeState.bindBuffer(compute, invocations, 0, tes[MVKImplicitBuffer::IndirectParams]);
	computeState.bindBuffer(compute, scratch->buffers[0], 0, tes[MVKImplicitBuffer::Output]);
	[compute dispatchThreads:MTLSizeMake(uint64_t(patches) * 39, 1, 1) threadsPerThreadgroup:MTLSizeMake(pipeline->getPerVertexTessEvalPipelineState().threadExecutionWidth, 1, 1)];
	// Ending compute establishes visibility for the tracked scratch buffers in render.
	cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
	cmdEncoder->finalizeDrawState(kMVKGraphicsStageRasterization);
	id<MTLRenderCommandEncoder> render = cmdEncoder->_mtlRenderEncoder;
	auto& graphics = cmdEncoder->getMtlGraphics();
	const auto& replay = pipeline->getPerVertexReplayBinding();
	const auto& fragment = pipeline->getPerVertexInputBinding();
	graphics.bindVertexBuffer(render, scratch->buffers[0], 0, replay.vertex_buffer_index);
	graphics.bindVertexBuffer(render, scratch->buffers[2], 0, replay.occurrence_buffer_index);
	graphics.bindVertexBuffer(render, plan, 256, replay.draw_parameters_buffer_index);
	if (pipeline->usesPortableBarycentrics()) { graphics.bindVertexBuffer(render, scratch->buffers[4], 0, pipeline->getPerVertexReplayBarycentricBinding().corner_buffer_index); }
	if (fragment.vertex_buffer_index != ~0u) {
		graphics.bindFragmentBuffer(render, scratch->buffers[0], 0, fragment.vertex_buffer_index);
		graphics.bindFragmentBuffer(render, scratch->buffers[3], 0, fragment.primitive_index_buffer_index);
		// Vulkan's fragment PrimitiveId after tessellation is the patch index, not the replayed triangle's.
		if (fragment.primitive_id_buffer_index != ~0u) { graphics.bindFragmentBuffer(render, plan, primitiveIds, fragment.primitive_id_buffer_index); }
	}
	if (cmdEncoder->getPhysicalDevice()->shouldEmulateReversedDepthViewport()) {
		uint32_t mask = cmdEncoder->getVkGraphics()._implicitBufferData[kMVKShaderStageVertex].emulatedReversedDepthViewportMask;
		graphics.bindVertexBytes(render, &mask, sizeof(mask), pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::EmulatedReversedDepthViewport]);
	}
	[render drawPrimitives:MTLPrimitiveTypeTriangle indirectBuffer:plan indirectBufferOffset:16];
	graphics._exists.vertex().descriptorSetData.reset();
	graphics._exists.fragment().descriptorSetData.reset();
}

// Ordinary tessellation that keeps float32 TCS levels: after the TCS, Vulkan classifies them into the separate half
// factors Metal's tessellator reads (tessLevelsToHalfFactors), while the TES reads the float32 levels. The caller
// binds the TCS parameters (patch count in word 1) at index 3, then dispatches at least one thread per patch.
static MVKMetalComputeCommandEncoderState& bindTessLevelsToHalfFactors(MVKCommandEncoder* cmdEncoder, MVKGraphicsPipeline* pipeline, id<MTLComputeCommandEncoder> encoder,
																	   const MVKMTLBufferAllocation* levels, const MVKMTLBufferAllocation* factors) {
	[encoder memoryBarrierWithScope: MTLBarrierScopeBuffers];
	auto& state = cmdEncoder->getMtlCompute();
	state.bindPipeline(encoder, pipeline->getTessLevelsToHalfFactorsPipelineState());
	state.bindBuffer(encoder, levels->_mtlBuffer, levels->_offset, 0);
	state.bindBuffer(encoder, factors->_mtlBuffer, factors->_offset, 1);
	float maxLevel = float(cmdEncoder->getDeviceProperties().limits.maxTessellationGenerationLevel);
	state.bindStructBytes(encoder, &maxLevel, 2);
	state._exists.descriptorSetData.reset();
	return state;
}

// Float32 TCS levels: outer[4], inner[2] per patch.
static constexpr size_t kMVKFloat32TessLevelSize = 6 * sizeof(float);

static constexpr bool mvkFitsFloat32TessLevels(uint64_t patchCount, uint64_t maxBufferSize) {
	return patchCount <= UINT32_MAX && patchCount <= maxBufferSize / kMVKFloat32TessLevelSize;
}

static_assert(mvkFitsFloat32TessLevels(178956970, UINT32_MAX));
static_assert(!mvkFitsFloat32TessLevels(178956971, UINT32_MAX));

static constexpr bool mvkFitsTessPatchCount(uint64_t patchCount, bool float32Levels, uint64_t maxBufferSize) {
	return patchCount <= UINT32_MAX && (!float32Levels || mvkFitsFloat32TessLevels(patchCount, maxBufferSize));
}

// Without prefill, encoding runs during vkQueueSubmit, possibly after it returned: recordTessPatchCount() refuses
// direct and indexed draws while recording, so that this check cannot silently omit an accepted draw.
static bool validateTessPatchCount(MVKCommandEncoder* cmdEncoder, uint64_t patchCount, bool float32Levels) {
	if (mvkFitsTessPatchCount(patchCount, float32Levels, cmdEncoder->getMetalFeatures().maxMTLBufferSize)) { return true; }
	auto* cmdBuffer = cmdEncoder->_cmdBuffer;
	cmdBuffer->setConfigurationResult(cmdBuffer->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Tessellation level scratch exceeds Metal buffer limits."));
	return false;
}

// The check of validateTessPatchCount(), while recording a direct or indexed draw of an ordinary tessellation pipeline.
// A failure stops the command from being recorded and fails vkEndCommandBuffer. Unknown dynamic control points are left
// to encoding.
static VkResult recordTessPatchCount(MVKCommandBuffer* cmdBuff, uint32_t vertexCount, uint32_t instanceCount) {
	auto* pipeline = cmdBuff->getRecordedTessellationPipeline();
	uint32_t controlPoints = cmdBuff->getRecordedPatchControlPoints();
	if (!pipeline || !controlPoints || !vertexCount || !instanceCount) { return VK_SUCCESS; }
	uint64_t patchCount = mvkCeilingDivide(uint64_t(vertexCount), controlPoints) * instanceCount;
	if (mvkFitsTessPatchCount(patchCount, pipeline->usesFloat32TessLevels(), cmdBuff->getMetalFeatures().maxMTLBufferSize)) { return VK_SUCCESS; }
	return cmdBuff->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Tessellation level scratch exceeds Metal buffer limits.");
}

void MVKCmdDraw::encodePerVertexInput(MVKCommandEncoder* cmdEncoder, MVKGraphicsPipeline* pipeline) {
	::encodePerVertexInput(cmdEncoder, pipeline, _vertexCount, _instanceCount, _firstVertex, _firstInstance, _drawIndex);
}

void MVKCmdDrawIndexed::encodePerVertexInput(MVKCommandEncoder* cmdEncoder, MVKGraphicsPipeline* pipeline) {
	::encodePerVertexInput(cmdEncoder, pipeline, _indexCount, _instanceCount, 0, _firstInstance, _drawIndex, &cmdEncoder->getVkGraphics()._indexBuffer, _firstIndex, _vertexOffset);
}

void MVKCmdDraw::encode(MVKCommandEncoder* cmdEncoder) {

	if (_vertexCount == 0 || _instanceCount == 0) { return; }	// Nothing to do.

	cmdEncoder->restartMetalRenderPassIfNeeded();

	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	if (pipeline->usesPerVertexTessEval()) {
		if (_instanceCount != 1) {
			cmdEncoder->_cmdBuffer->setConfigurationResult(cmdEncoder->_cmdBuffer->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "PerVertex TES draw requires one instance."));
			cmdEncoder->getDevice()->markLost();
			cmdEncoder->stopEncoding();
			return;
		}
		encodePerVertexTessEval(cmdEncoder, pipeline, _vertexCount, _firstVertex, _firstInstance, _drawIndex);
		return;
	}
	if (pipeline->usesPerVertexInputBuffer()) { encodePerVertexInput(cmdEncoder, pipeline); return; }
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;

	// Metal doesn't support triangle fans, so encode it as triangles via an indexed indirect triangles command instead.
	if (cmdEncoder->getVkGraphics().getPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
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
    const MVKMTLBufferAllocation* tcFloatLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
	struct {
		uint32_t inControlPointCount = 0;
		uint32_t patchCount = 0;
	} tessParams;
    uint32_t outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        tessParams.inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        uint64_t patchCount = mvkCeilingDivide(uint64_t(_vertexCount), tessParams.inControlPointCount) * _instanceCount;
        if (!validateTessPatchCount(cmdEncoder, patchCount, pipeline->usesFloat32TessLevels())) { return; }
        tessParams.patchCount = uint32_t(patchCount);
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
                if (pipeline->usesFloat32TessLevels()) { tcFloatLevelBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * kMVKFloat32TessLevelSize, true); }
                [mtlTessCtlEncoder setBuffer: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_mtlBuffer
                                      offset: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_offset
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
                if (tcFloatLevelBuff) {
                    auto& state = bindTessLevelsToHalfFactors(cmdEncoder, pipeline, mtlTessCtlEncoder, tcFloatLevelBuff, tcLevelBuff);
                    state.bindBytes(mtlTessCtlEncoder, &tessParams, sizeof(tessParams), 3);
                    [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(tessParams.patchCount, 64u), 1, 1)
                                      threadsPerThreadgroup: MTLSizeMake(64, 1, 1)];
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
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_mtlBuffer
                                                            offset: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_offset
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

	VkResult result = recordTessPatchCount(cmdBuff, _indexCount, _instanceCount);
	return result == VK_SUCCESS ? cmdBuff->recordPerVertexDraw(_indexCount, _instanceCount, true) : result;
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
	VkResult result = diiCmd.setContent(cmdEncoder->_cmdBuffer, indirectIdxBuff->_mtlBuffer, indirectIdxBuff->_offset, 1, indirectIdxBuffStride);
	if (result != VK_SUCCESS) { cmdEncoder->_cmdBuffer->setConfigurationResult(result); return; }
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
	if (cmdEncoder->getGraphicsPipeline()->usesPerVertexInputBuffer()) { encodePerVertexInput(cmdEncoder, cmdEncoder->getGraphicsPipeline()); return; }

	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;

	// Metal doesn't support triangle fans, so encode it as triangles via an indexed indirect triangles command instead.
	if (cmdEncoder->getVkGraphics().getPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
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
    const MVKMTLBufferAllocation* tcFloatLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
	struct {
		uint32_t inControlPointCount = 0;
		uint32_t patchCount = 0;
	} tessParams;
    uint32_t outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        tessParams.inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        uint64_t patchCount = mvkCeilingDivide(uint64_t(_indexCount), tessParams.inControlPointCount) * _instanceCount;
        if (!validateTessPatchCount(cmdEncoder, patchCount, pipeline->usesFloat32TessLevels())) { return; }
        tessParams.patchCount = uint32_t(patchCount);
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
                if (pipeline->usesFloat32TessLevels()) { tcFloatLevelBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * kMVKFloat32TessLevelSize, true); }
                [mtlTessCtlEncoder setBuffer: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_mtlBuffer
                                      offset: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_offset
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
                if (tcFloatLevelBuff) {
                    auto& state = bindTessLevelsToHalfFactors(cmdEncoder, pipeline, mtlTessCtlEncoder, tcFloatLevelBuff, tcLevelBuff);
                    state.bindBytes(mtlTessCtlEncoder, &tessParams, sizeof(tessParams), 3);
                    [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(tessParams.patchCount, 64u), 1, 1)
                                      threadsPerThreadgroup: MTLSizeMake(64, 1, 1)];
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
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_mtlBuffer
                                                            offset: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_offset
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
// Indirect tessellation draws size their scratch for this fixed vertex count: even with one control point per patch,
// its float32 levels fit any Metal buffer limit of at least 256 MiB, so validateTessPatchCount() cannot omit them.
static_assert(mvkFitsTessPatchCount(kMVKMaxDrawIndirectVertexCount, true, 256 * MEBI));

static const MVKMTLBufferAllocation* encodeIndirectCountConversion(
		MVKCommandEncoder* cmdEncoder,
		id<MTLBuffer> indirectBuffer,
		VkDeviceSize indirectBufferOffset,
		uint32_t indirectBufferStride,
		id<MTLBuffer> countBuffer,
		VkDeviceSize countBufferOffset,
		uint32_t drawCount,
		bool indexed) {
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

// Portable PerVertexKHR indirect draws. Arguments and Count may be written earlier in the same submission,
// so only the GPU reads them. Phase 0 freezes every draw's arguments and the Count on the GPU and computes the
// records they need, with the largest count a uint32 record ID can represent as its only ceiling. The encoder then
// waits for that plan, reserves the exact replay scratch from the frozen counts, and encodes the replay on a new
// Metal command buffer. A command that cannot be replayed (unrepresentable counts, indices beyond the bound
// index buffer, or scratch beyond Metal limits or memory) executes no draw and loses the device, so that nothing
// that follows it is reported complete. Apple3-10 GPUs cannot order fragment reads before later vertex writes
// inside a render encoder, so each draw ends the render encoder around its compute planning and the next draw
// reuses the hazard-tracked scratch only after Metal orders the previous replay.
static void encodePerVertexIndirect(MVKCommandEncoder* cmdEncoder, MVKGraphicsPipeline* pipeline, id<MTLBuffer> indirectBuffer, VkDeviceSize indirectOffset, uint32_t stride, uint32_t drawCount, id<MTLBuffer> countBuffer, VkDeviceSize countOffset, const MVKIndexMTLBufferBinding* indexBinding) {
	// Encoding runs after vkQueueSubmit() returned: a command that cannot be encoded also loses the device, so that
	// the submission never completes without it.
	auto reject = [&](VkResult result, const char* message) {
		cmdEncoder->_cmdBuffer->setConfigurationResult(cmdEncoder->_cmdBuffer->reportError(result, "Portable PerVertexKHR indirect %s", message));
		cmdEncoder->getDevice()->markLost();
		cmdEncoder->stopEncoding();
	};
	auto lose = [&](const char* reason) {
		cmdEncoder->reportError(VK_ERROR_DEVICE_LOST, "Portable PerVertexKHR indirect command was not executed: %s.", reason);
		cmdEncoder->getDevice()->markLost();
		cmdEncoder->stopEncoding();
	};
	auto* subpass = cmdEncoder->getSubpass();
	uint32_t viewCount = subpass->isMultiview() ? subpass->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
	auto* scratch = cmdEncoder->nextPerVertexScratch();
	if (!scratch) { return; }
	id<MTLBuffer> plan = scratch->buffers[12];
	id<MTLComputePipelineState> helper = scratch->indirectPipeline;
	if (!plan || !helper || !scratch->indirectCapacity || !viewCount) { reject(VK_ERROR_INITIALIZATION_FAILED, "draw has no planning scratch."); return; }
	if (const char* error = cmdEncoder->getIndexedPerVertexAttachmentError()) { reject(VK_ERROR_FEATURE_NOT_PRESENT, error); return; }
	uint32_t indexSize = indexBinding ? mvkPerVertexIndexSize(indexBinding->vkIndexType) : 0;
	if (indexBinding && (!indexSize || !indexBinding->mtlBuffer)) { reject(VK_ERROR_FEATURE_NOT_PRESENT, "indexed draw requires a bound uint8, uint16 or uint32 index buffer."); return; }
	// Vulkan ignores restart for nonindexed draws. Restart assembly runs on the gathered indices.
	bool restart = mvkPerVertexRequiresRestartAssembly(indexBinding != nullptr, cmdEncoder->getVkGraphics().isPrimitiveRestartEnabled());
	id<MTLComputePipelineState> restartState = restart ? scratch->indexPipeline : nil;
	if (restart && (!restartState || !restartState.threadExecutionWidth || !restartState.maxTotalThreadsPerThreadgroup)) { reject(VK_ERROR_FEATURE_NOT_PRESENT, "restart assembly helper is unavailable."); return; }
	id<MTLRenderPipelineState> directCaptureState = indexBinding ? nil : pipeline->getPerVertexCapturePipelineState(viewCount);
	id<MTLComputePipelineState> captureState = indexBinding ? pipeline->getPerVertexIndexedCapturePipelineState(true, viewCount) : nil;
	if (indexBinding ? (!captureState || !captureState.threadExecutionWidth || !captureState.maxTotalThreadsPerThreadgroup) : !directCaptureState) { reject(VK_ERROR_FEATURE_NOT_PRESENT, "capture pipeline is unavailable."); return; }
	// Indices the GPU may gather: the Vulkan binding clipped to its Metal allocation.
	uint64_t indexCapacity = 0;
	if (indexBinding && indexBinding->offset <= indexBinding->mtlBuffer.length) { indexCapacity = std::min<uint64_t>(indexBinding->size, indexBinding->mtlBuffer.length - indexBinding->offset) / indexSize; }
	auto topology = cmdEncoder->getVkGraphics().getPrimitiveTopology();
	uint32_t replayVertices = mvkPerVertexReplayVertexCount(topology);
	NSUInteger width = std::max<NSUInteger>(std::min(helper.threadExecutionWidth, helper.maxTotalThreadsPerThreadgroup), 1);
	if (restartState) { width = std::min(width, std::min(restartState.threadExecutionWidth, restartState.maxTotalThreadsPerThreadgroup)); }
	// The plan layout, including where phase 0 freezes the arguments, follows the plan's record ceiling.
	uint32_t planScanSteps = restart ? mvkPerVertexIndirectRestartScanSteps(scratch->indirectCapacity) : 0;
	if (restart && plan.length < 1024 + (planScanSteps + 3) * 256) { reject(VK_ERROR_INITIALIZATION_FAILED, "restart planning scratch is too small."); return; }
	// A single draw freezes its arguments in the plan, several draws in their own buffer (see the perVertexIndirect kernel).
	uint32_t snapshotWords = drawCount == 1 ? 48 : 0;
	id<MTLBuffer> snapshot = drawCount == 1 ? plan : scratch->buffers[13];
	if (drawCount > 1 && (!snapshot || snapshot.length < uint64_t(drawCount) * (indexBinding ? 5 : 4) * sizeof(uint32_t))) { reject(VK_ERROR_INITIALIZATION_FAILED, "argument snapshot scratch is too small."); return; }
	NSUInteger captureWidth = captureState ? std::max<NSUInteger>(std::min(captureState.threadExecutionWidth, captureState.maxTotalThreadsPerThreadgroup), 1) : 1;
	bool corners = pipeline->usesPortableBarycentrics();
	uint32_t params[19] = {drawCount, stride, indexSize, uint32_t(indexCapacity), uint32_t(indexCapacity >> 32), scratch->indirectCapacity, viewCount, uint32_t(topology),
		uint32_t(cmdEncoder->getVkGraphics().getProvokingVertexMode()), uint32_t(corners), uint32_t(countBuffer != nil), 0, uint32_t(width), uint32_t(width), uint32_t(captureWidth), 0, uint32_t(restart), planScanSteps, snapshotWords};
	auto& computeState = cmdEncoder->getMtlCompute();
	auto& metalState = cmdEncoder->getMtlGraphics();

	// Phase 0 freezes every draw of the command, then the GPU plan must complete before the replay can be sized.
	cmdEncoder->encodeStoreActions(true);
	id<MTLComputeCommandEncoder> planEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
	computeState.bindPipeline(planEncoder, helper);
	computeState.bindBuffer(planEncoder, indirectBuffer, indirectOffset, 0);
	computeState.bindBuffer(planEncoder, countBuffer ?: plan, countBuffer ? countOffset : 0, 1);
	computeState.bindBuffer(planEncoder, plan, 0, 2);
	computeState.bindBuffer(planEncoder, indexBinding ? indexBinding->mtlBuffer : plan, indexBinding ? indexBinding->offset : 0, 3);
	for (uint32_t unused = 4; unused < 8; ++unused) { computeState.bindBuffer(planEncoder, plan, 0, unused); }
	computeState.bindBytes(planEncoder, params, sizeof(params), 8);
	computeState.bindBuffer(planEncoder, snapshot, 0, 9);
	[planEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(drawCount, width), 1, 1) threadsPerThreadgroup: MTLSizeMake(width, 1, 1)];
	computeState._exists.descriptorSetData.reset();
	if (!cmdEncoder->awaitEncodedWork()) {
		if (!cmdEncoder->getDevice()->isLosing()) { lose("its GPU plan did not complete"); }
		return;
	}
	MVKPerVertexScratchRequest replayRequest{};
	NSUInteger gatheredOffset = 0;
	uint32_t scanSteps = 0;
	// Sized with the captured record stride, not the stride of the indirect arguments.
	NSUInteger snapshotOffset = NSUInteger(snapshotWords) * sizeof(uint32_t);
	if (!mvkSizePerVertexIndirectReplay(plan.contents, plan.length, static_cast<const uint8_t*>(snapshot.contents) + snapshotOffset, snapshot.length - snapshotOffset, drawCount, viewCount, pipeline->getPerVertexCapturedLayout().stride, topology, indexBinding != nullptr, restart, corners,
										cmdEncoder->getMetalFeatures().maxMTLBufferSize, replayRequest, gatheredOffset, scanSteps)) {
		uint32_t status = *(volatile const uint32_t*)plan.contents;
		lose((status & 1) ? "a draw needs more records than uint32 record IDs can represent" : (status & 2) ? "a draw reads indices beyond the bound index buffer" : "its replay scratch would exceed Metal buffer limits");
		return;
	}
	// No draw records a vertex: Count zero, or zero vertices or instances in every draw.
	if (!replayRequest.captureSize) { return; }
	if (!scratch->reserveReplay(cmdEncoder->getMTLDevice(), replayRequest)) { lose("its replay scratch could not be allocated"); return; }
	cmdEncoder->keepPerVertexScratchResident();
	params[17] = scanSteps;

	id<MTLBuffer> captured = scratch->buffers[0];
	id<MTLBuffer> occurrences = scratch->buffers[2];
	id<MTLBuffer> primitiveIndices = scratch->buffers[3];
	id<MTLBuffer> cornerBuffer = scratch->buffers[4] ?: plan;
	id<MTLBuffer> gathered = scratch->buffers[5] ?: plan;
	const auto& replay = pipeline->getPerVertexReplayBinding();
	const auto& fragment = pipeline->getPerVertexInputBinding();
	// Only the draws the GPU froze (Count, clamped to maxDrawCount): mvkSizePerVertexIndirectReplay checked the word.
	uint32_t frozenDraws = std::min(((const uint32_t*)plan.contents)[56], drawCount);
	for (uint32_t draw = 0; draw < frozenDraws; ++draw) {
		params[11] = draw;
		// Plan this draw, build its replay tables and gather its indices from the frozen arguments.
		cmdEncoder->encodeStoreActions(true);
		planEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
		computeState.bindPipeline(planEncoder, helper);
		computeState.bindBuffer(planEncoder, indirectBuffer, indirectOffset, 0);
		computeState.bindBuffer(planEncoder, countBuffer ?: plan, countBuffer ? countOffset : 0, 1);
		computeState.bindBuffer(planEncoder, plan, 0, 2);
		computeState.bindBuffer(planEncoder, indexBinding ? indexBinding->mtlBuffer : plan, indexBinding ? indexBinding->offset : 0, 3);
		computeState.bindBuffer(planEncoder, gathered, gatheredOffset, 4);
		computeState.bindBuffer(planEncoder, occurrences, 0, 5);
		computeState.bindBuffer(planEncoder, primitiveIndices, 0, 6);
		computeState.bindBuffer(planEncoder, cornerBuffer, 0, 7);
		computeState.bindBuffer(planEncoder, snapshot, 0, 9);
		auto dispatch = [&](uint32_t phase, NSUInteger groups) {
			params[15] = phase;
			computeState.bindBytes(planEncoder, params, sizeof(params), 8);
			[planEncoder dispatchThreadgroups: MTLSizeMake(groups, 1, 1) threadsPerThreadgroup: MTLSizeMake(phase == 1 ? 1 : width, 1, 1)];
			[planEncoder memoryBarrierWithScope: MTLBarrierScopeBuffers];
		};
		auto dispatchIndirect = [&](uint32_t phase, NSUInteger offset) {
			params[15] = phase;
			computeState.bindBytes(planEncoder, params, sizeof(params), 8);
			[planEncoder dispatchThreadgroupsWithIndirectBuffer: plan indirectBufferOffset: offset threadsPerThreadgroup: MTLSizeMake(width, 1, 1)];
		};
		dispatch(1, 1);
		if (!restart) { dispatchIndirect(2, 96); }
		if (indexBinding) { dispatchIndirect(3, 112); }
		[planEncoder memoryBarrierWithScope: MTLBarrierScopeBuffers];
		if (restart) {
			// perVertexRestart as for direct draws, with GPU-planned parameters and dispatch sizes.
			computeState.bindPipeline(planEncoder, restartState);
			computeState.bindBuffer(planEncoder, scratch->buffers[5], gatheredOffset, 0);
			computeState.bindBuffer(planEncoder, scratch->buffers[5], 0, 1);
			computeState.bindBuffer(planEncoder, occurrences, 0, 2);
			computeState.bindBuffer(planEncoder, primitiveIndices, 0, 3);
			computeState.bindBuffer(planEncoder, scratch->buffers[4] ?: scratch->buffers[5], 0, 4);
			computeState.bindBuffer(planEncoder, scratch->buffers[6], 0, 5);
			for (uint32_t block = 0; block < scanSteps + 3; ++block) {
				computeState.bindBuffer(planEncoder, plan, 1024 + 256 * block, 6);
				[planEncoder dispatchThreadgroupsWithIndirectBuffer: plan indirectBufferOffset: block == scanSteps + 2 ? 160 : 144 threadsPerThreadgroup: MTLSizeMake(width, 1, 1)];
				[planEncoder memoryBarrierWithScope: MTLBarrierScopeBuffers];
			}
		}
		// Restore application resources displaced by the planning kernel.
		computeState._exists.descriptorSetData.reset();
		if (indexBinding) {
			cmdEncoder->_isIndexedDraw = true;
			cmdEncoder->finalizeDrawState(kMVKGraphicsStageVertex);
			if (!pipeline->hasValidMTLPipelineStates()) { return; }
			id<MTLComputeCommandEncoder> captureEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
			computeState.bindPipeline(captureEncoder, captureState);
			computeState.bindBuffer(captureEncoder, captured, 0, pipeline->getPerVertexCaptureBufferIndex());
			// Restart captures the compacted indices; its grid_size is still the stage-in region.
			computeState.bindBuffer(captureEncoder, gathered, restart ? 0 : gatheredOffset, pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Index]);
			if (pipeline->needsDrawIdBuffer()) { computeState.bindStructBytes(captureEncoder, &draw, pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]); }
			// Origin is (vertexOffset bit pattern, firstInstance); the capture guard stops at the region size.
			[captureEncoder setStageInRegionWithIndirectBuffer: plan indirectBufferOffset: 48];
			if (restart) {
				[captureEncoder dispatchThreadgroupsWithIndirectBuffer: scratch->buffers[6] indirectBufferOffset: 0 threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
			} else {
				[captureEncoder dispatchThreadgroupsWithIndirectBuffer: plan indirectBufferOffset: 32 threadsPerThreadgroup: MTLSizeMake(captureWidth, 1, 1)];
			}
		}
		cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
		cmdEncoder->_isIndexedDraw = false;
		cmdEncoder->finalizeDrawState(kMVKGraphicsStageRasterization);
		if (!pipeline->hasValidMTLPipelineStates()) { return; }
		id<MTLRenderCommandEncoder> encoder = cmdEncoder->_mtlRenderEncoder;
		if (!indexBinding) {
			[encoder setRenderPipelineState: directCaptureState];
			metalState.bindVertexBuffer(encoder, captured, 0, pipeline->getPerVertexCaptureBufferIndex());
			metalState.bindVertexBuffer(encoder, plan, 512, pipeline->getPerVertexCaptureParamsBufferIndex());
			if (pipeline->needsDrawIdBuffer()) { metalState.bindVertexBytes(encoder, &draw, sizeof(draw), pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]); }
			MTLPrimitiveType captureType = pipeline->capturesPerVertexTriangleLists() ? MTLPrimitiveTypeTriangle : MTLPrimitiveTypePoint;
			[encoder drawPrimitives: captureType indirectBuffer: plan indirectBufferOffset: 16];
			// A render pass boundary, not an in-pass barrier, orders the capture before the replay (see the direct draw).
			cmdEncoder->encodeStoreActions(true);
			cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
			cmdEncoder->finalizeDrawState(kMVKGraphicsStageRasterization);
			if (!pipeline->hasValidMTLPipelineStates()) { return; }
			encoder = cmdEncoder->_mtlRenderEncoder;
		}
		[encoder setRenderPipelineState: pipeline->getMainPipelineState()];
		metalState.bindVertexBuffer(encoder, captured, 0, replay.vertex_buffer_index);
		metalState.bindVertexBuffer(encoder, occurrences, 0, replay.occurrence_buffer_index);
		if (scratch->buffers[4]) { metalState.bindVertexBuffer(encoder, scratch->buffers[4], 0, pipeline->getPerVertexReplayBarycentricBinding().corner_buffer_index); }
		id<MTLBuffer> replayArguments = restart ? scratch->buffers[6] : plan;
		metalState.bindVertexBuffer(encoder, replayArguments, 256, replay.draw_parameters_buffer_index);
		if (fragment.vertex_buffer_index != ~0u) {
			metalState.bindFragmentBuffer(encoder, captured, 0, fragment.vertex_buffer_index);
			metalState.bindFragmentBuffer(encoder, primitiveIndices, 0, fragment.primitive_index_buffer_index);
		}
		if (cmdEncoder->getPhysicalDevice()->shouldEmulateReversedDepthViewport()) {
			uint32_t viewportMask = cmdEncoder->getVkGraphics()._implicitBufferData[kMVKShaderStageVertex].emulatedReversedDepthViewportMask;
			metalState.bindVertexBytes(encoder, &viewportMask, sizeof(viewportMask), pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::EmulatedReversedDepthViewport]);
		}
		MTLPrimitiveType replayType = replayVertices == 1 ? MTLPrimitiveTypePoint : replayVertices == 2 ? MTLPrimitiveTypeLine : MTLPrimitiveTypeTriangle;
		[encoder drawPrimitives: replayType indirectBuffer: replayArguments indirectBufferOffset: restart ? 16 : 80];
		metalState._exists.vertex().descriptorSetData.reset();
		metalState._exists.fragment().descriptorSetData.reset();
	}
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

	// Arguments stay on the GPU; only a bounded capture capacity is reserved here.
	return drawCount ? cmdBuff->recordPerVertexIndirectDraw(false, drawCount) : VK_SUCCESS;
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
	VkResult result = diiCmd.setContent(cmdEncoder->_cmdBuffer, indirectIdxBuff->_mtlBuffer, indirectIdxBuff->_offset, _drawCount, indirectIdxBuffStride);
	if (result != VK_SUCCESS) { cmdEncoder->_cmdBuffer->setConfigurationResult(result); return; }
	diiCmd.encode(cmdEncoder, ibb);
}

void MVKCmdDrawIndirect::encode(MVKCommandEncoder* cmdEncoder) {
	if (!_drawCount) { return; }

	cmdEncoder->restartMetalRenderPassIfNeeded();
	if (auto* pipeline = cmdEncoder->getGraphicsPipeline(); pipeline->usesPerVertexInputBuffer()) {
		encodePerVertexIndirect(cmdEncoder, pipeline, _mtlIndirectBuffer, _mtlIndirectBufferOffset, _mtlIndirectBufferStride, _drawCount, _mtlCountBuffer, _mtlCountBufferOffset, nullptr);
		return;
	}
	id<MTLBuffer> indirectBuffer = _mtlIndirectBuffer;
	VkDeviceSize indirectBufferOffset = _mtlIndirectBufferOffset;
	uint32_t indirectBufferStride = _mtlIndirectBufferStride;

	if (_mtlCountBuffer && _drawCount > 0) {
		auto* convertedBuffer = encodeIndirectCountConversion(cmdEncoder,
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
	if (cmdEncoder->getVkGraphics().getPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
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
    const MVKMTLBufferAllocation* tcFloatLevelBuff = nullptr;
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
        if (!validateTessPatchCount(cmdEncoder, patchCount, pipeline->usesFloat32TessLevels())) { return; }
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
        if (pipeline->usesFloat32TessLevels()) { tcFloatLevelBuff = cmdEncoder->getTempMTLBuffer(patchCount * kMVKFloat32TessLevelSize, true); }

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
				// The TCS reads each draw's parameters at this stride, which follows minUniformBufferOffsetAlignment.
				uint32_t paramsStride = uint32_t(paramsIncr);
				state.bindStructBytes(mtlTessCtlEncoder, &paramsStride, 9);
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
                    [mtlTessCtlEncoder setBuffer: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_mtlBuffer
                                          offset: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_offset
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
                    if (tcFloatLevelBuff) {
                        // The TCS grid of this draw has at least one thread per patch.
                        auto& state = bindTessLevelsToHalfFactors(cmdEncoder, pipeline, mtlTessCtlEncoder, tcFloatLevelBuff, tcLevelBuff);
                        state.bindBuffer(mtlTessCtlEncoder, tcParamsBuff->_mtlBuffer, mtlParmBuffOfst - paramsIncr, 3);
                        [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
                                                             indirectBufferOffset: mtlIndBuffOfst - sizeof(MTLDispatchThreadgroupsIndirectArguments)
                                                            threadsPerThreadgroup: MTLSizeMake(tcWorkgroupSize, 1, 1)];
                    }
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
							[cmdEncoder->_mtlRenderEncoder setVertexBuffer: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_mtlBuffer
																	offset: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_offset
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
	if (cmdBuff->_lastTessellationPipeline && !cmdBuff->getMetalFeatures().indirectTessellationDrawing) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexedIndirect(): The current device does not support indirect tessellated drawing.");
	}
	auto* mvkBuff = (MVKBuffer*)buffer;
	VkResult result = setContent(cmdBuff,
								 mvkBuff->getMTLBuffer(),
								 mvkBuff->getMTLBufferOffset() + offset,
								 drawCount,
								 stride);
	// Arguments stay on the GPU; only a bounded capture capacity is reserved here.
	return result == VK_SUCCESS && drawCount ? cmdBuff->recordPerVertexIndirectDraw(true, drawCount) : result;
}

VkResult MVKCmdDrawIndexedIndirect::setContent(MVKCommandBuffer* cmdBuff,
										   id<MTLBuffer> indirectMTLBuff,
										   VkDeviceSize indirectMTLBuffOffset,
										   uint32_t drawCount,
										   uint32_t stride) {
	// Also used during fan encoding: recording state may describe a later pipeline.
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
	if (!_drawCount) { return; }
	cmdEncoder->restartMetalRenderPassIfNeeded();
	encode(cmdEncoder, cmdEncoder->getVkGraphics()._indexBuffer);
}

void MVKCmdDrawIndexedIndirect::encode(MVKCommandEncoder* cmdEncoder, const MVKIndexMTLBufferBinding& ibbOrig) {
	if (!_drawCount) { return; }
	if (auto* pipeline = cmdEncoder->getGraphicsPipeline(); pipeline->usesPerVertexInputBuffer()) {
		encodePerVertexIndirect(cmdEncoder, pipeline, _mtlIndirectBuffer, _mtlIndirectBufferOffset, _mtlIndirectBufferStride, _drawCount, _mtlCountBuffer, _mtlCountBufferOffset, &ibbOrig);
		return;
	}

	id<MTLBuffer> indirectBuffer = _mtlIndirectBuffer;
	VkDeviceSize indirectBufferOffset = _mtlIndirectBufferOffset;
	uint32_t indirectBufferStride = _mtlIndirectBufferStride;
	if (_mtlCountBuffer && _drawCount > 0) {
		auto* convertedBuffer = encodeIndirectCountConversion(cmdEncoder,
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
	vtxAdjmts.isTriangleFan = cmdEncoder->getVkGraphics().getPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN;
#if MVK_USE_METAL_PRIVATE_API
	// With private APIs for primitive restart, we need to handle disabled restart and raw Uint8 indices.
	vtxAdjmts.isPrimRestart = cmdEncoder->getState().vkGraphics().isPrimitiveRestartEnabled();
	vtxAdjmts.isUint8Index = ibb.vkIndexType == VK_INDEX_TYPE_UINT8;
	vtxAdjmts.isProvokingVertexLast = cmdEncoder->getState().vkGraphics().getProvokingVertexMode() == MTLProvokingVertexModeLast;
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
    const MVKMTLBufferAllocation* tcFloatLevelBuff = nullptr;
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
        if (!validateTessPatchCount(cmdEncoder, patchCount, pipeline->usesFloat32TessLevels())) { return; }
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
        if (pipeline->usesFloat32TessLevels()) { tcFloatLevelBuff = cmdEncoder->getTempMTLBuffer(patchCount * kMVKFloat32TessLevelSize, true); }
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
                    // The TCS reads each draw's parameters at this stride, which follows minUniformBufferOffsetAlignment.
                    uint32_t paramsStride = uint32_t(paramsIncr);
                    state.bindStructBytes(mtlTessCtlEncoder, &paramsStride, 9);
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
                    [mtlTessCtlEncoder setBuffer: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_mtlBuffer
                                          offset: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_offset
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
                    if (tcFloatLevelBuff) {
                        // The TCS grid of this draw has at least one thread per patch.
                        auto& state = bindTessLevelsToHalfFactors(cmdEncoder, pipeline, mtlTessCtlEncoder, tcFloatLevelBuff, tcLevelBuff);
                        state.bindBuffer(mtlTessCtlEncoder, tcParamsBuff->_mtlBuffer, mtlParmBuffOfst - paramsIncr, 3);
                        [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
                                                             indirectBufferOffset: mtlTempIndBuffOfst - sizeof(MTLDispatchThreadgroupsIndirectArguments)
                                                            threadsPerThreadgroup: MTLSizeMake(tcWorkgroupSize, 1, 1)];
                    }
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
							[cmdEncoder->_mtlRenderEncoder setVertexBuffer: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_mtlBuffer
																	offset: (tcFloatLevelBuff ? tcFloatLevelBuff : tcLevelBuff)->_offset
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


#pragma mark -
#pragma mark MVKCmdDrawMeshTasks

VkResult MVKCmdDrawMeshTasks::setContent(MVKCommandBuffer* cmdBuff, uint32_t groupCountX, uint32_t groupCountY, uint32_t groupCountZ) {
	// Metal executes nothing, and reports no error, for a mesh grid beyond its limit: refuse such a draw here rather than
	// omit it. The Metal Feature Set Tables list 1024 threadgroups on Apple7 and Apple8, 1,048,575 on Apple9 and
	// 4,194,303 on Apple10, all below Vulkan's minimum maxMeshWorkGroupTotalCount of 2^22. On Apple9 the pipeline
	// reports 1,048,576, and a grid of exactly that many threadgroups draws nothing: the reported value is exclusive.
	uint64_t groups = uint64_t(groupCountX) * groupCountY * groupCountZ;
	if (auto* mesh = cmdBuff->getRecordedMeshPipeline(); mesh && groups >= mesh->getMaxMeshThreadgroupsPerGrid()) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawMeshTasksEXT(): %llu workgroups reach the %lu this Metal mesh pipeline reports, beyond which it draws nothing.", (unsigned long long)groups, (unsigned long)mesh->getMaxMeshThreadgroupsPerGrid());
	}
	_groupCountX = groupCountX;
	_groupCountY = groupCountY;
	_groupCountZ = groupCountZ;
	return VK_SUCCESS;
}

// A mesh pipeline without task shader: one mesh threadgroup per workgroup, of the mesh shader's workgroup size.
void MVKCmdDrawMeshTasks::encode(MVKCommandEncoder* cmdEncoder) {
	if (!_groupCountX || !_groupCountY || !_groupCountZ) { return; }
	cmdEncoder->restartMetalRenderPassIfNeeded();
	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	if (!pipeline->isMeshPipeline()) { return; }
	cmdEncoder->finalizeDrawState(kMVKGraphicsStageRasterization);
	if (!pipeline->hasValidMTLPipelineStates()) { return; }
	[cmdEncoder->_mtlRenderEncoder drawMeshThreadgroups: MTLSizeMake(_groupCountX, _groupCountY, _groupCountZ)
	                        threadsPerObjectThreadgroup: MTLSizeMake(1, 1, 1)
	                          threadsPerMeshThreadgroup: pipeline->getMeshThreadgroupSize()];
}
