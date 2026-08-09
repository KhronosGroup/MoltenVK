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
		pRaygenShaderBindingTable->stride < 32 || (pRaygenShaderBindingTable->deviceAddress & 15) ||
		(pRaygenShaderBindingTable->stride & 15)) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT,
									"vkCmdTraceRaysKHR(): The ray-generation shader binding table is invalid for the Metal backend.");
	}
	auto invalidOptionalRegion = [](const VkStridedDeviceAddressRegionKHR* region) {
		return region->size && (!region->deviceAddress || region->stride < 32 ||
			(region->deviceAddress & 15) || (region->stride & 15));
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
	_mtlCallableShaderBindingTableBuffer = nil;
	auto resolveBuffer = [&](const VkStridedDeviceAddressRegionKHR& region, id<MTLBuffer>& mtlBuffer) {
		if (!region.size) { return true; }
		VkDeviceSize offset = 0;
		MVKBuffer* buffer = cmdBuff->getDevice()->getBufferAtAddress(region.deviceAddress, offset, region.size);
		if (!buffer || offset > buffer->getByteCount() || region.size > buffer->getByteCount() - offset) {
			cmdBuff->reportError(VK_ERROR_INITIALIZATION_FAILED,
								 "vkCmdTraceRaysKHR(): A shader binding table region exceeds its buffer.");
			return false;
		}
		mtlBuffer = buffer->getMTLBuffer();
		return true;
	};
	if (!resolveBuffer(_raygenShaderBindingTable, _mtlRaygenShaderBindingTableBuffer) ||
		!resolveBuffer(_missShaderBindingTable, _mtlMissShaderBindingTableBuffer) ||
		!resolveBuffer(_hitShaderBindingTable, _mtlHitShaderBindingTableBuffer) ||
		!resolveBuffer(_callableShaderBindingTable, _mtlCallableShaderBindingTableBuffer)) {
		return VK_ERROR_INITIALIZATION_FAILED;
	}
	return VK_SUCCESS;
}

void MVKCmdTraceRays::encode(MVKCommandEncoder* cmdEncoder) {
	if (!_mtlIndirectBuffer && (!_threads.width || !_threads.height || !_threads.depth)) { return; }
	auto* pipeline = static_cast<MVKRayTracingPipeline*>(cmdEncoder->getRayTracingPipeline());
	const MVKMTLBufferAllocation* indirectDispatch = nullptr;
	if (_mtlIndirectBuffer) {
		indirectDispatch = cmdEncoder->getTempMTLBuffer(sizeof(MTLDispatchThreadgroupsIndirectArguments), true);
		id<MTLComputeCommandEncoder> convertEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTraceRays);
		auto& state = cmdEncoder->getMtlCompute();
		state.bindPipeline(convertEncoder, cmdEncoder->getCommandEncodingPool()
			->getCmdTraceRaysIndirectConvertMTLComputePipelineState());
		state.bindBuffer(convertEncoder, _mtlIndirectBuffer, _mtlIndirectBufferOffset, 0);
		state.bindBuffer(convertEncoder, indirectDispatch->_mtlBuffer, indirectDispatch->_offset, 1);
		uint32_t threadgroupWidth = pipeline->getThreadgroupSize().width;
		state.bindStructBytes(convertEncoder, &threadgroupWidth, 2);
		[convertEncoder dispatchThreads:MTLSizeMake(1, 1, 1)
			threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
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
	for (id<MTLBuffer> buffer : {_mtlRaygenShaderBindingTableBuffer, _mtlMissShaderBindingTableBuffer,
								 _mtlHitShaderBindingTableBuffer, _mtlCallableShaderBindingTableBuffer,
								 _mtlIndirectBuffer}) {
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
		uint64_t raygenAddress;
		uint64_t swizzleAddress;
		uint64_t bufferSizeAddress;
		uint64_t dynamicOffsetsAddress;
		uint64_t accelerationStructureAddressTableAddress;
		uint64_t pushConstantsAddress;
		uint64_t indirectLaunchSizeAddress;
		uint64_t descriptorSetAddresses[kMVKMaxDescriptorSetCount];
		uint32_t pipelineFlags;
		uint32_t usesIFB;
	} dispatch = {
		_missShaderBindingTable.deviceAddress,
		_missShaderBindingTable.stride,
		_hitShaderBindingTable.deviceAddress,
		_hitShaderBindingTable.stride,
		_hitShaderBindingTable.size,
		_callableShaderBindingTable.deviceAddress,
		_callableShaderBindingTable.stride,
		_raygenShaderBindingTable.deviceAddress,
	};
	if (_mtlIndirectBuffer) {
		dispatch.indirectLaunchSizeAddress = _mtlIndirectBuffer.gpuAddress + _mtlIndirectBufferOffset;
	}
	dispatch.pipelineFlags = pipeline->getRayTracingPipelineFlags();
	dispatch.usesIFB = pipeline->usesIntersectionFunctionBuffer() &&
		_hitShaderBindingTable.size >= 32 && _hitShaderBindingTable.stride &&
		_hitShaderBindingTable.stride <= (1u << 12) &&
		!(_hitShaderBindingTable.deviceAddress & 63);
	using Dispatch = decltype(dispatch);
	static_assert(offsetof(Dispatch, descriptorSetAddresses) == 14 * sizeof(uint64_t));
	static_assert(offsetof(Dispatch, pipelineFlags) == offsetof(Dispatch, descriptorSetAddresses) +
										 sizeof(dispatch.descriptorSetAddresses));
	static_assert(sizeof(Dispatch) == offsetof(Dispatch, pipelineFlags) + 2 * sizeof(uint32_t));
	const auto& vkRayTracing = cmdEncoder->getVkRayTracing();
	struct Upload {
		const void* data;
		NSUInteger size;
		NSUInteger offset;
		uint64_t* address;
	};
	MVKSmallVector<Upload, 4> uploads;
	NSUInteger uploadSize = 0;
	auto addUpload = [&](const void* data, NSUInteger size, uint64_t& address) {
		if (!size) { return; }
		uploadSize = mvkAlignByteCount(uploadSize, 16);
		uploads.push_back({ data, size, uploadSize, &address });
		uploadSize += size;
	};
	auto addImplicitData = [&](const auto& data, uint64_t& address) {
		addUpload(data.data(), data.size() * sizeof(uint32_t), address);
	};
	addImplicitData(vkRayTracing._implicitBufferData.textureSwizzles, dispatch.swizzleAddress);
	addImplicitData(vkRayTracing._implicitBufferData.bufferSizes, dispatch.bufferSizeAddress);
	addImplicitData(vkRayTracing._implicitBufferData.dynamicOffsets, dispatch.dynamicOffsetsAddress);
	if (pipeline->needsAccelerationStructureAddressTable()) {
		MVKUseResourceHelper resources;
		auto* addressTable = cmdEncoder->getAccelerationStructureAddressTable(
			resources, MVKResourceUsageStages::Compute);
		dispatch.accelerationStructureAddressTableAddress = addressTable->_mtlBuffer.gpuAddress + addressTable->_offset;
		[mtlEncoder useResource:addressTable->_mtlBuffer usage:MTLResourceUsageRead];
		resources.bindAndResetCompute(mtlEncoder);
	}
	const auto& pushConstants = cmdEncoder->getState().vkShared()._pushConstants;
	addUpload(pushConstants.data(), pushConstants.size(), dispatch.pushConstantsAddress);
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
	uploadSize = mvkAlignByteCount(uploadSize, 16);
	NSUInteger dispatchOffset = uploadSize;
	auto* dispatchAllocation = cmdEncoder->getTempMTLBuffer(uploadSize + sizeof(dispatch));
	uint8_t* uploadContents = static_cast<uint8_t*>(dispatchAllocation->getContents());
	uint64_t uploadAddress = dispatchAllocation->_mtlBuffer.gpuAddress + dispatchAllocation->_offset;
	for (const auto& upload : uploads) {
		memcpy(uploadContents + upload.offset, upload.data, upload.size);
		*upload.address = uploadAddress + upload.offset;
	}
	memcpy(uploadContents + dispatchOffset, &dispatch, sizeof(dispatch));
	[mtlEncoder setBuffer:dispatchAllocation->_mtlBuffer
				 offset:dispatchAllocation->_offset + dispatchOffset
				atIndex:pipeline->getRayTracingDispatchBufferIndex()];
	[mtlEncoder useResource:dispatchAllocation->_mtlBuffer usage:MTLResourceUsageRead];
	if (_mtlIndirectBuffer) {
		[mtlEncoder dispatchThreadgroupsWithIndirectBuffer:indirectDispatch->_mtlBuffer
									 indirectBufferOffset:indirectDispatch->_offset
									threadsPerThreadgroup:pipeline->getThreadgroupSize()];
	} else {
		[mtlEncoder dispatchThreads:_threads threadsPerThreadgroup:pipeline->getThreadgroupSize()];
	}
}
