/*
 * MVKCmdDispatch.mm
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

#include "MVKCmdDispatch.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKBuffer.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"


#pragma mark -
#pragma mark MVKCmdDispatch

VkResult MVKCmdDispatch::setContent(MVKCommandBuffer* cmdBuff,
									uint32_t baseGroupX, uint32_t baseGroupY, uint32_t baseGroupZ,
									uint32_t groupCountX, uint32_t groupCountY, uint32_t groupCountZ) {
	_baseGroupX = baseGroupX;
	_baseGroupY = baseGroupY;
	_baseGroupZ = baseGroupZ;

	_groupCountX = groupCountX;
	_groupCountY = groupCountY;
	_groupCountZ = groupCountZ;

	return VK_SUCCESS;
}

void MVKCmdDispatch::encode(MVKCommandEncoder* cmdEncoder) {
	MTLRegion mtlThreadgroupCount = MTLRegionMake3D(_baseGroupX, _baseGroupY, _baseGroupZ, _groupCountX, _groupCountY, _groupCountZ);
	cmdEncoder->finalizeDispatchState();	// Ensure all updated state has been submitted to Metal
	id<MTLComputeCommandEncoder> mtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch);
	auto* pipeline = cmdEncoder->getComputePipeline();
	if (pipeline->allowsDispatchBase()) {
		// We'll use the stage-input region to pass the base along to the shader.
		// Hopefully Metal won't complain that we didn't set up a stage-input descriptor.
		[mtlEncoder setStageInRegion: mtlThreadgroupCount];
	}
	[mtlEncoder dispatchThreadgroups: mtlThreadgroupCount.size
			   threadsPerThreadgroup: pipeline->getThreadgroupSize()];
}


#pragma mark -
#pragma mark MVKCmdDispatchIndirect

VkResult MVKCmdDispatchIndirect::setContent(MVKCommandBuffer* cmdBuff, VkBuffer buffer, VkDeviceSize offset) {
	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
	_mtlIndirectBuffer = mvkBuffer->getMTLBuffer();
	_mtlIndirectBufferOffset = mvkBuffer->getMTLBufferOffset() + offset;

	return VK_SUCCESS;
}

void MVKCmdDispatchIndirect::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->finalizeDispatchState();	// Ensure all updated state has been submitted to Metal
    [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) dispatchThreadgroupsWithIndirectBuffer: _mtlIndirectBuffer
																				indirectBufferOffset: _mtlIndirectBufferOffset
																			   threadsPerThreadgroup: cmdEncoder->getComputePipeline()->getThreadgroupSize()];
}


#pragma mark -
#pragma mark MVKCmdTraceRays

VkResult MVKCmdTraceRays::setContent(MVKCommandBuffer* cmdBuff,
									 const VkStridedDeviceAddressRegionKHR* pRaygenShaderBindingTable,
									 const VkStridedDeviceAddressRegionKHR* pMissShaderBindingTable,
									 const VkStridedDeviceAddressRegionKHR* pHitShaderBindingTable,
									 const VkStridedDeviceAddressRegionKHR* pCallableShaderBindingTable,
									 uint32_t width, uint32_t height, uint32_t depth) {
	cmdBuff->recordAccelerationStructureCommand();
	VkResult result = setShaderBindingTables(cmdBuff, pRaygenShaderBindingTable, pMissShaderBindingTable,
										  pHitShaderBindingTable, pCallableShaderBindingTable);
	if (result != VK_SUCCESS) { return result; }
	_threads = MTLSizeMake(width, height, depth);
	_mtlIndirectBuffer = nil;
	return VK_SUCCESS;
}

VkResult MVKCmdTraceRays::setContent(MVKCommandBuffer* cmdBuff,
									 const VkStridedDeviceAddressRegionKHR* pRaygenShaderBindingTable,
									 const VkStridedDeviceAddressRegionKHR* pMissShaderBindingTable,
									 const VkStridedDeviceAddressRegionKHR* pHitShaderBindingTable,
									 const VkStridedDeviceAddressRegionKHR* pCallableShaderBindingTable,
									 VkDeviceAddress indirectDeviceAddress) {
	cmdBuff->recordAccelerationStructureCommand();
	VkResult result = setShaderBindingTables(cmdBuff, pRaygenShaderBindingTable, pMissShaderBindingTable,
										  pHitShaderBindingTable, pCallableShaderBindingTable);
	if (result != VK_SUCCESS) { return result; }
	VkDeviceSize offset = 0;
	MVKBuffer* buffer = cmdBuff->getDevice()->getBufferAtAddress(indirectDeviceAddress, offset,
															  sizeof(VkTraceRaysIndirectCommandKHR));
	if (!buffer || offset > buffer->getByteCount() ||
		sizeof(VkTraceRaysIndirectCommandKHR) > buffer->getByteCount() - offset) {
		return reportError(VK_ERROR_INITIALIZATION_FAILED,
						   "vkCmdTraceRaysIndirectKHR(): The indirect device address does not reference a complete command.");
	}
	_mtlIndirectBuffer = buffer->getMTLBuffer();
	_mtlIndirectBufferOffset = buffer->getMTLBufferOffset() + offset;
	return VK_SUCCESS;
}

VkResult MVKCmdTraceRays::setShaderBindingTables(
	MVKCommandBuffer* cmdBuff,
	const VkStridedDeviceAddressRegionKHR* pRaygenShaderBindingTable,
	const VkStridedDeviceAddressRegionKHR* pMissShaderBindingTable,
	const VkStridedDeviceAddressRegionKHR* pHitShaderBindingTable,
	const VkStridedDeviceAddressRegionKHR* pCallableShaderBindingTable) {
	if (!pRaygenShaderBindingTable->deviceAddress || pRaygenShaderBindingTable->size != pRaygenShaderBindingTable->stride ||
		pRaygenShaderBindingTable->stride < sizeof(uint32_t) || (pRaygenShaderBindingTable->deviceAddress & 3) ||
		(pRaygenShaderBindingTable->stride & 3)) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT,
									"vkCmdTraceRaysKHR(): The ray-generation shader binding table is invalid for the Metal backend.");
	}
	auto invalidOptionalRegion = [](const VkStridedDeviceAddressRegionKHR* region) {
		return region->size && (!region->deviceAddress || (region->deviceAddress & 3) || (region->stride & 3));
	};
	for (auto* region : {pMissShaderBindingTable, pHitShaderBindingTable, pCallableShaderBindingTable}) {
		if (invalidOptionalRegion(region)) {
			return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT,
										"vkCmdTraceRaysKHR(): An optional shader binding table is invalid for the Metal backend.");
		}
	}
	_raygenShaderBindingTable = *pRaygenShaderBindingTable;
	_missShaderBindingTable = *pMissShaderBindingTable;
	_hitShaderBindingTable = *pHitShaderBindingTable;
	_callableShaderBindingTable = *pCallableShaderBindingTable;
	if (!_missShaderBindingTable.size) { _missShaderBindingTable = {}; }
	if (!_hitShaderBindingTable.size) { _hitShaderBindingTable = {}; }
	if (!_callableShaderBindingTable.size) { _callableShaderBindingTable = {}; }
	_mtlRaygenShaderBindingTableBuffer = nil;
	_mtlMissShaderBindingTableBuffer = nil;
	_mtlHitShaderBindingTableBuffer = nil;
	_mtlHitShaderBindingTableBufferOffset = 0;
	_mtlCallableShaderBindingTableBuffer = nil;
	_mtlCallableShaderBindingTableBufferOffset = 0;
	auto resolveBuffer = [&](const VkStridedDeviceAddressRegionKHR& region, id<MTLBuffer>& mtlBuffer,
							 VkDeviceSize* bufferOffset = nullptr) {
		if (!region.size) { return true; }
		VkDeviceSize offset = 0;
		MVKBuffer* buffer = cmdBuff->getDevice()->getBufferAtAddress(region.deviceAddress, offset, region.size);
		if (!buffer || offset > buffer->getByteCount() || region.size > buffer->getByteCount() - offset) {
			cmdBuff->reportError(VK_ERROR_INITIALIZATION_FAILED,
								 "vkCmdTraceRaysKHR(): A shader binding table region exceeds its buffer.");
			return false;
		}
		mtlBuffer = buffer->getMTLBuffer();
		if (bufferOffset) { *bufferOffset = buffer->getMTLBufferOffset() + offset; }
		return true;
	};
	if (!resolveBuffer(_raygenShaderBindingTable, _mtlRaygenShaderBindingTableBuffer) ||
		!resolveBuffer(_missShaderBindingTable, _mtlMissShaderBindingTableBuffer) ||
		!resolveBuffer(_hitShaderBindingTable, _mtlHitShaderBindingTableBuffer,
					   &_mtlHitShaderBindingTableBufferOffset) ||
		!resolveBuffer(_callableShaderBindingTable, _mtlCallableShaderBindingTableBuffer,
					   &_mtlCallableShaderBindingTableBufferOffset)) {
		return VK_ERROR_INITIALIZATION_FAILED;
	}
	return VK_SUCCESS;
}

void MVKCmdTraceRays::encode(MVKCommandEncoder* cmdEncoder) {
	if (!_mtlIndirectBuffer && (!_threads.width || !_threads.height || !_threads.depth)) { return; }
	cmdEncoder->finalizeRayTracingDispatchState();
	auto* pipeline = static_cast<MVKRayTracingPipeline*>(cmdEncoder->getRayTracingPipeline());
	auto& computeState = cmdEncoder->getMtlCompute();
	uint32_t metadataIndex = pipeline->getRayTracingInstanceMetadataBufferIndex();
	auto metadataBinding = computeState._bindings.buffers[metadataIndex];
	NSUInteger metadataSize = computeState._exists.buffers.get(metadataIndex) && metadataBinding.buffer &&
								metadataBinding.offset < metadataBinding.buffer.length
							? metadataBinding.buffer.length - metadataBinding.offset
							: 0;
	VkDeviceSize traceDataSize = metadataSize;
	VkDeviceSize maxTraceDataSize = cmdEncoder->getMetalFeatures().maxMTLBufferSize;
	auto appendTable = [&](VkDeviceSize size, VkDeviceSize& offset) {
		VkDeviceSize mask = sizeof(uint64_t) - 1;
		VkDeviceSize padding = -traceDataSize & mask;
		if (traceDataSize > maxTraceDataSize || padding > maxTraceDataSize - traceDataSize) { return false; }
		offset = traceDataSize += padding;
		if (size > maxTraceDataSize - traceDataSize) { return false; }
		traceDataSize += size;
		return true;
	};
	VkDeviceSize hitTableOffset = 0;
	VkDeviceSize callableTableOffset = 0;
	if (maxTraceDataSize < sizeof(uint64_t) ||
		!appendTable(_hitShaderBindingTable.size, hitTableOffset) ||
		!appendTable(_callableShaderBindingTable.size, callableTableOffset)) {
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdTraceRaysKHR(): The trace data exceeds the maximum Metal buffer size.");
		return;
	}
	traceDataSize = std::max<VkDeviceSize>(traceDataSize, sizeof(uint64_t));
	const MVKMTLBufferAllocation* traceData = cmdEncoder->getTempMTLBuffer(
		static_cast<NSUInteger>(traceDataSize), true);
	id<MTLBlitCommandEncoder> blitEncoder = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseTraceRays);
	if (metadataSize) {
		[blitEncoder copyFromBuffer:metadataBinding.buffer
					sourceOffset:metadataBinding.offset
					    toBuffer:traceData->_mtlBuffer
				 destinationOffset:traceData->_offset
						 size:metadataSize];
	}
	if (_mtlHitShaderBindingTableBuffer) {
		[blitEncoder copyFromBuffer:_mtlHitShaderBindingTableBuffer
					sourceOffset:_mtlHitShaderBindingTableBufferOffset
					    toBuffer:traceData->_mtlBuffer
					 destinationOffset:traceData->_offset + hitTableOffset
						 size:_hitShaderBindingTable.size];
	}
	if (_mtlCallableShaderBindingTableBuffer) {
		[blitEncoder copyFromBuffer:_mtlCallableShaderBindingTableBuffer
					sourceOffset:_mtlCallableShaderBindingTableBufferOffset
					    toBuffer:traceData->_mtlBuffer
				 destinationOffset:traceData->_offset + callableTableOffset
						 size:_callableShaderBindingTable.size];
	}
	cmdEncoder->finalizeRayTracingDispatchState();
	id<MTLComputeCommandEncoder> mtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTraceRays);
	[mtlEncoder setVisibleFunctionTable:pipeline->getRayGenerationFunctionTable()
						 atBufferIndex:pipeline->getRayGenerationFunctionTableBufferIndex()];
	[mtlEncoder setVisibleFunctionTable:pipeline->getRayTracingFunctionTable()
						 atBufferIndex:pipeline->getRayTracingFunctionTableBufferIndex()];
	[mtlEncoder setVisibleFunctionTable:pipeline->getRayTracingIntersectionFunctionTable()
						 atBufferIndex:pipeline->getRayTracingIntersectionFunctionTableBufferIndex()];
	[mtlEncoder setVisibleFunctionTable:pipeline->getRayTracingCallableFunctionTable()
						 atBufferIndex:pipeline->getRayTracingCallableFunctionTableBufferIndex()];
	[mtlEncoder setVisibleFunctionTable:pipeline->getRecursiveRayTracingFunctionTable()
						 atBufferIndex:pipeline->getRecursiveRayTracingFunctionTableBufferIndex()];
	[mtlEncoder setVisibleFunctionTable:pipeline->getRecursiveRayTracingIntersectionFunctionTable()
						 atBufferIndex:pipeline->getRecursiveRayTracingIntersectionFunctionTableBufferIndex()];
	[mtlEncoder useResource:traceData->_mtlBuffer usage:MTLResourceUsageRead];
	for (id<MTLBuffer> buffer : {_mtlRaygenShaderBindingTableBuffer, _mtlMissShaderBindingTableBuffer,
								 _mtlCallableShaderBindingTableBuffer}) {
		if (buffer) { [mtlEncoder useResource:buffer usage:MTLResourceUsageRead]; }
	}
	struct {
		uint64_t missAddress;
		uint64_t missStride;
		uint64_t hitAddress;
		uint64_t hitStride;
		uint64_t hitSize;
		uint64_t callableAddress;
		uint64_t callableStride;
		uint64_t hitTableOffset;
		uint64_t raygenAddress;
		uint64_t swizzleAddress;
		uint64_t bufferSizeAddress;
		uint64_t dynamicOffsetsAddress;
		uint64_t accelerationStructureAddressTableAddress;
		uint64_t pushConstantsAddress;
		uint64_t descriptorSetAddresses[kMVKMaxDescriptorSetCount];
		uint32_t pipelineFlags;
	} dispatch = {
		_missShaderBindingTable.deviceAddress,
		_missShaderBindingTable.stride,
		traceData->_mtlBuffer.gpuAddress + traceData->_offset,
		_hitShaderBindingTable.stride,
		_hitShaderBindingTable.size,
		_callableShaderBindingTable.size ? traceData->_mtlBuffer.gpuAddress + traceData->_offset + callableTableOffset : 0,
		_callableShaderBindingTable.stride,
		hitTableOffset,
		_raygenShaderBindingTable.deviceAddress,
	};
	dispatch.pipelineFlags = pipeline->getRayTracingPipelineFlags();
	static_assert(kMVKMaxDescriptorSetCount == 8);
	const auto& vkRayTracing = cmdEncoder->getVkRayTracing();
	auto copyImplicitData = [&](const auto& data, uint64_t& address) {
		if (data.empty()) { return; }
		auto* allocation = cmdEncoder->copyToTempMTLBufferAllocation(data.data(), data.size() * sizeof(uint32_t));
		address = allocation->_mtlBuffer.gpuAddress + allocation->_offset;
		[mtlEncoder useResource:allocation->_mtlBuffer usage:MTLResourceUsageRead];
	};
	copyImplicitData(vkRayTracing._implicitBufferData.textureSwizzles, dispatch.swizzleAddress);
	copyImplicitData(vkRayTracing._implicitBufferData.bufferSizes, dispatch.bufferSizeAddress);
	copyImplicitData(vkRayTracing._implicitBufferData.dynamicOffsets, dispatch.dynamicOffsetsAddress);
	if (pipeline->needsAccelerationStructureAddressTable()) {
		MVKUseResourceHelper resources;
		auto* addressTable = cmdEncoder->getAccelerationStructureAddressTable(
			resources, MVKResourceUsageStages::Compute);
		dispatch.accelerationStructureAddressTableAddress = addressTable->_mtlBuffer.gpuAddress + addressTable->_offset;
		[mtlEncoder useResource:addressTable->_mtlBuffer usage:MTLResourceUsageRead];
		resources.bindAndResetCompute(mtlEncoder);
	}
	const auto& pushConstants = cmdEncoder->getState().vkShared()._pushConstants;
	if (!pushConstants.empty()) {
		auto* pushConstantsAllocation = cmdEncoder->copyToTempMTLBufferAllocation(pushConstants.data(), pushConstants.size());
		dispatch.pushConstantsAddress = pushConstantsAllocation->_mtlBuffer.gpuAddress + pushConstantsAllocation->_offset;
		[mtlEncoder useResource:pushConstantsAllocation->_mtlBuffer usage:MTLResourceUsageRead];
	}
	uint32_t descriptorSetCount = vkRayTracing._layout ? vkRayTracing._layout->getDescriptorSetCount() : 0;
	for (uint32_t i = 0; i < descriptorSetCount; i++) {
		auto* descriptorSet = vkRayTracing._descriptorSets[i];
		id<MTLBuffer> buffer = descriptorSet ? descriptorSet->gpuBufferObject : nil;
		uint32_t offset = descriptorSet ? descriptorSet->gpuBufferOffset : 0;
		if (descriptorSet && vkRayTracing._layout->getDescriptorSetLayout(i)->hasAccelerationStructures()) {
			auto* snapshot = cmdEncoder->getDescriptorSetSnapshot(descriptorSet);
			buffer = snapshot ? snapshot->gpuBufferObject : nil;
			offset = snapshot ? snapshot->gpuBufferOffset : 0;
		}
		if (buffer) {
			dispatch.descriptorSetAddresses[i] = buffer.gpuAddress + offset;
			[mtlEncoder useResource:buffer usage:MTLResourceUsageRead];
		}
	}
	[mtlEncoder setBytes:&dispatch length:sizeof(dispatch) atIndex:pipeline->getRayTracingDispatchBufferIndex()];
	if (_mtlIndirectBuffer) {
		[mtlEncoder dispatchThreadgroupsWithIndirectBuffer:_mtlIndirectBuffer
									 indirectBufferOffset:_mtlIndirectBufferOffset
									threadsPerThreadgroup:pipeline->getThreadgroupSize()];
	} else {
		[mtlEncoder dispatchThreads:_threads threadsPerThreadgroup:pipeline->getThreadgroupSize()];
	}
}
