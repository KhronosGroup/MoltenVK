/*
 * MVKCmdAccelerationStructure.mm
 *
 * Copyright (c) 2026 dttdrv
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

#include "MVKCmdAccelerationStructure.h"
#include "MVKCmdAccelerationStructureSerialization.h"
#include "MVKCmdDebug.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandEncoderState.h"
#include "MVKCommandPool.h"
#include "MVKAccelerationStructure.h"
#include "MVKQueryPool.h"
#include "MVKFoundation.h"

#include <Metal/Metal.h>

#pragma mark -
#pragma mark MVKCmdBuildAccelerationStructure

enum MVKAccelerationStructureConversionType : uint32_t {
    kMVKAccelerationStructureConvertInstances,
    kMVKAccelerationStructureConvertInstancePointers,
    kMVKAccelerationStructureConvertTransform,
};

static void releaseAccelerationStructureGenerationOnCompletion(
	MVKCommandEncoder* cmdEncoder,
	MVKAccelerationStructureStorageGeneration* generation) {
	[cmdEncoder->_mtlCmdBuffer addCompletedHandler:^(id<MTLCommandBuffer>) { generation->release(); }];
}

static id<MTLComputeCommandEncoder> encodeAccelerationStructureConversion(MVKCommandEncoder* cmdEncoder,
                                                                          id<MTLBuffer> srcBuffer,
                                                                          NSUInteger srcOffset,
                                                                          id<MTLBuffer> dstBuffer,
                                                                          NSUInteger dstOffset,
                                                                          id<MTLBuffer> instanceMetadata,
                                                                          uint32_t srcStride,
                                                                          uint32_t itemCount,
                                                                          MVKAccelerationStructureConversionType conversionType,
																			  id<MTLBuffer> canonicalBuffer,
																			  NSUInteger canonicalRecordOffset,
																			  NSUInteger canonicalHandleOffset) {
    if ( !itemCount ) { return nil; }
    id<MTLComputeCommandEncoder> mtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseBuildAccelerationStructureConvertBuffers);
    id<MTLComputePipelineState> mtlState =
        cmdEncoder->getCommandEncodingPool()->getCmdBuildAccelerationStructureConvertBuffersMTLComputePipelineState();
    [mtlEncoder setComputePipelineState:mtlState];
    [mtlEncoder setBuffer:srcBuffer offset:srcOffset atIndex:0];
    [mtlEncoder setBuffer:dstBuffer offset:dstOffset atIndex:1];
    [mtlEncoder setBuffer:instanceMetadata ? instanceMetadata : dstBuffer
                   offset:instanceMetadata ? 0 : dstOffset
                  atIndex:4];
    cmdEncoder->setComputeBytes(mtlEncoder, &srcStride, sizeof(srcStride), 2);
	cmdEncoder->setComputeBytes(mtlEncoder, &itemCount, sizeof(itemCount), 3);
	cmdEncoder->setComputeBytes(mtlEncoder, &conversionType, sizeof(conversionType), 5);
	id<MTLBuffer> serializationBuffer = canonicalBuffer ? canonicalBuffer : dstBuffer;
	[mtlEncoder setBuffer:serializationBuffer offset:canonicalBuffer ? canonicalRecordOffset : dstOffset atIndex:7];
	[mtlEncoder setBuffer:serializationBuffer offset:canonicalBuffer ? canonicalHandleOffset : dstOffset atIndex:8];
	uint32_t emitSerialization = canonicalBuffer != nil;
	cmdEncoder->setComputeBytes(mtlEncoder, &emitSerialization, sizeof(emitSerialization), 9);
	// The shared kernel declares this argument even though transform conversion does not read it.
	[mtlEncoder setBuffer:dstBuffer offset:dstOffset atIndex:6];
	if (conversionType != kMVKAccelerationStructureConvertTransform) {
		MVKUseResourceHelper resources;
		auto* addressTable = cmdEncoder->getAccelerationStructureAddressTable(resources,
		                                                                    MVKResourceUsageStages::Compute);
		[mtlEncoder setBuffer:addressTable->_mtlBuffer offset:addressTable->_offset atIndex:6];
		cmdEncoder->getDevice()->encodeGPUAddressableBuffers(cmdEncoder, resources, MVKResourceUsageStages::Compute);
		resources.bindAndResetCompute(mtlEncoder);
	}
    if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
        [mtlEncoder dispatchThreads:MTLSizeMake(itemCount, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(mtlState.threadExecutionWidth, 1, 1)];
    } else {
        [mtlEncoder dispatchThreadgroups:MTLSizeMake(mvkCeilingDivide<NSUInteger>(itemCount, mtlState.threadExecutionWidth), 1, 1)
                   threadsPerThreadgroup:MTLSizeMake(mtlState.threadExecutionWidth, 1, 1)];
    }
    return mtlEncoder;
}

VkResult MVKCmdBuildAccelerationStructure::setContent(MVKCommandBuffer* cmdBuff,
                                                      uint32_t infoCount,
                                                      const VkAccelerationStructureBuildGeometryInfoKHR* pInfos,
                                                      const VkAccelerationStructureBuildRangeInfoKHR* const* ppBuildRangeInfos) {
	cmdBuff->recordAccelerationStructureCommand();
    _buildInfos.clear();
    _buildInfos.reserve(infoCount);
    for (uint32_t i = 0; i < infoCount; i++) {
        MVKAccelerationStructureBuildInfo& info = _buildInfos.emplace_back();
        info.info = pInfos[i];

        info.geometries.resize(pInfos[i].geometryCount);
        info.ranges.resize(pInfos[i].geometryCount);
        for (uint32_t geomIdx = 0; geomIdx < pInfos[i].geometryCount; geomIdx++) {
            info.geometries[geomIdx] = pInfos[i].pGeometries ? pInfos[i].pGeometries[geomIdx] : *pInfos[i].ppGeometries[geomIdx];
            info.ranges[geomIdx] = ppBuildRangeInfos[i][geomIdx];
        }

        info.info.pGeometries = info.geometries.data();
    }

    return VK_SUCCESS;
}

void MVKCmdBuildAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
    for (MVKAccelerationStructureBuildInfo& entry : _buildInfos) {
        const auto& buildInfo = entry.info;
        const auto& ranges = entry.ranges;

        MVKAccelerationStructure* mvkDstAccStruct = (MVKAccelerationStructure*)buildInfo.dstAccelerationStructure;

        MVKDevice* mvkDevice = cmdEncoder->getDevice();
        VkDeviceSize scratchOffset = 0;
        MVKBuffer* mvkBuffer = mvkDevice->getBufferAtAddress(buildInfo.scratchData.deviceAddress, scratchOffset);

        if ( !mvkBuffer ) { continue; }
        id<MTLBuffer> scratchBuffer = mvkBuffer->getMTLBuffer();
        NSInteger scratchBufferOffset = mvkBuffer->getMTLBufferOffset() + scratchOffset;

        MTLAccelerationStructureDescriptor* descriptor = mvkDstAccStruct->newMTLAccelerationStructureDescriptor(buildInfo, entry.ranges.data(), nullptr);
        if ( !descriptor ) { continue; }
		MTLAccelerationStructureSizes buildSizes = [cmdEncoder->getMTLDevice() accelerationStructureSizesWithDescriptor:descriptor];
		uint64_t instanceMetadataSize = buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR
			? static_cast<uint64_t>(ranges[0].primitiveCount) * sizeof(uint32_t) * 2
			: 0;
		MVKAccelerationStructureStorageGeneration* dstGeneration = nullptr;
		VkResult generationResult = buildInfo.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR
			? mvkDstAccStruct->retainFullWriteGeneration(buildSizes.accelerationStructureSize,
													 instanceMetadataSize, dstGeneration)
			: VK_SUCCESS;
		if (buildInfo.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR) {
			dstGeneration = mvkDstAccStruct->retainCurrentGeneration();
			if (!dstGeneration || buildSizes.accelerationStructureSize > dstGeneration->getNativeCapacity() ||
				instanceMetadataSize > dstGeneration->getMetadataCapacity()) {
				generationResult = VK_ERROR_OUT_OF_DEVICE_MEMORY;
			}
		}
		if (generationResult < 0 || !dstGeneration) {
			if (dstGeneration) { dstGeneration->release(); }
			cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
				"vkCmdBuildAccelerationStructuresKHR(): The destination acceleration structure has insufficient storage capacity.");
			[descriptor release];
			continue;
		}
		id<MTLAccelerationStructure> dstAccStruct = dstGeneration->getMTLAccelerationStructure();
		MVKAccelerationStructureCanonicalBuild canonicalBuild;
		VkResult canonicalResult = canonicalBuild.prepareAndEncode(cmdEncoder, mvkDstAccStruct,
			buildInfo, ranges.data(), buildSizes.accelerationStructureSize);
		if (canonicalResult < 0) {
			cmdEncoder->reportError(canonicalResult,
				"vkCmdBuildAccelerationStructuresKHR(): The canonical build input could not be captured.");
			dstGeneration->release();
			[descriptor release];
			continue;
		}

        id<MTLComputeCommandEncoder> mtlConvertEncoder = nil;
        if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR) {
            NSArray* geometryDescriptors = ((MTLPrimitiveAccelerationStructureDescriptor*)descriptor).geometryDescriptors;
            for (uint32_t geomIdx = 0; geomIdx < buildInfo.geometryCount && geomIdx < geometryDescriptors.count; geomIdx++) {
                const VkAccelerationStructureGeometryKHR& geometry = buildInfo.pGeometries
                    ? buildInfo.pGeometries[geomIdx]
                    : *buildInfo.ppGeometries[geomIdx];
                if (geometry.geometryType != VK_GEOMETRY_TYPE_TRIANGLES_KHR ||
                    !geometry.geometry.triangles.transformData.deviceAddress) { continue; }
                MTLAccelerationStructureTriangleGeometryDescriptor* triangleDescriptor = geometryDescriptors[geomIdx];
                id<MTLBuffer> srcBuffer = triangleDescriptor.transformationMatrixBuffer;
                if ( !srcBuffer ) { continue; }
                const MVKMTLBufferAllocation* tmpBuffer = cmdEncoder->getTempMTLBuffer(sizeof(VkTransformMatrixKHR), true);
                mtlConvertEncoder = encodeAccelerationStructureConversion(cmdEncoder,
                                                                          srcBuffer,
                                                                          triangleDescriptor.transformationMatrixBufferOffset,
                                                                          tmpBuffer->_mtlBuffer,
                                                                          tmpBuffer->_offset,
                                                                          nil,
                                                                          sizeof(VkTransformMatrixKHR),
                                                                          1,
                                                                          kMVKAccelerationStructureConvertTransform,
																						  nil, 0, 0);
                triangleDescriptor.transformationMatrixBuffer = tmpBuffer->_mtlBuffer;
                triangleDescriptor.transformationMatrixBufferOffset = tmpBuffer->_offset;
            }
        }
        if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
            const VkAccelerationStructureGeometryKHR& geometry = buildInfo.pGeometries
                ? buildInfo.pGeometries[0]
                : *buildInfo.ppGeometries[0];
            const VkAccelerationStructureGeometryInstancesDataKHR& instancesData = geometry.geometry.instances;
            VkDeviceSize instanceOffset = 0;
            MVKBuffer* mvkInstancesBuffer = cmdEncoder->getDevice()->getBufferAtAddress(instancesData.data.deviceAddress, instanceOffset);
            uint32_t srcStride = instancesData.arrayOfPointers ? sizeof(VkDeviceAddress) : sizeof(VkAccelerationStructureInstanceKHR);
            uint32_t instanceCount = ranges[0].primitiveCount;
            VkDeviceSize available = mvkInstancesBuffer ? mvkInstancesBuffer->getByteCount() : 0;
            bool invalidInstances = !mvkInstancesBuffer ||
                                    instanceOffset > available ||
                                    ranges[0].primitiveOffset > available - instanceOffset ||
                                    instanceCount > (available - instanceOffset - ranges[0].primitiveOffset) / srcStride;
            if (instanceCount && invalidInstances) {
				dstGeneration->release();
                [descriptor release];
                continue;
            }
			id<MTLBuffer> instanceMetadata = dstGeneration->getInstanceMetadataMTLBuffer();
			if (!dstGeneration->setInstanceMetadataSize(instanceMetadataSize)) {
                cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
                                        "vkCmdBuildAccelerationStructuresKHR(): The destination acceleration structure has insufficient instance-metadata capacity.");
				dstGeneration->release();
                [descriptor release];
                continue;
            }
            MTLInstanceAccelerationStructureDescriptor* tlasDescriptor = (MTLInstanceAccelerationStructureDescriptor*)descriptor;
            NSUInteger tmpBufferSize = sizeof(MTLIndirectAccelerationStructureInstanceDescriptor) *
                                      (instanceCount ? instanceCount : 1);
            const MVKMTLBufferAllocation* tmpBuffer = cmdEncoder->getTempMTLBuffer(tmpBufferSize, true);
            tlasDescriptor.instanceDescriptorBuffer = tmpBuffer->_mtlBuffer;
            tlasDescriptor.instanceDescriptorBufferOffset = tmpBuffer->_offset;
            tlasDescriptor.instanceDescriptorStride = sizeof(MTLIndirectAccelerationStructureInstanceDescriptor);
            if (instanceCount) {
                NSUInteger srcOffset = mvkInstancesBuffer->getMTLBufferOffset() + instanceOffset + ranges[0].primitiveOffset;
                mtlConvertEncoder = encodeAccelerationStructureConversion(cmdEncoder,
                                                                          mvkInstancesBuffer->getMTLBuffer(),
                                                                          srcOffset,
                                                                          tmpBuffer->_mtlBuffer,
                                                                          tmpBuffer->_offset,
                                                                          instanceMetadata,
                                                                          srcStride,
                                                                          instanceCount,
                                                                          instancesData.arrayOfPointers
                                                                              ? kMVKAccelerationStructureConvertInstancePointers
                                                                              : kMVKAccelerationStructureConvertInstances,
																						  canonicalBuild.getMTLBuffer(),
																						  canonicalBuild.getRecordTableOffset(),
																						  canonicalBuild.getHandleArrayOffset());
            }
        }

		id<MTLFence> fence = nil;
		if (mtlConvertEncoder) {
			fence = [cmdEncoder->getMTLDevice() newFence];
			if (!fence) {
				cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
					"vkCmdBuildAccelerationStructuresKHR(): The conversion fence could not be allocated.");
				dstGeneration->release();
				[descriptor release];
				continue;
			}
			[mtlConvertEncoder updateFence:fence];
            [cmdEncoder->_mtlCmdBuffer addCompletedHandler:^(id<MTLCommandBuffer>) { [fence release]; }];
        }
        id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseBuildAccelerationStructure);
        if (fence) { [accStructEncoder waitForFence:fence]; }
        if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
            mvkDevice->encodeGPUAddressableAccelerationStructures(cmdEncoder, accStructEncoder);
        }

		MVKAccelerationStructureStorageGeneration* srcGeneration = nullptr;
		bool encoded = false;
		if (buildInfo.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR &&
			mvkDstAccStruct->publishGeneration(dstGeneration)) {
			cmdEncoder->invalidateAccelerationStructureAddressTable();
            [accStructEncoder buildAccelerationStructure:dstAccStruct
                                              descriptor:descriptor
                                           scratchBuffer:scratchBuffer
                                     scratchBufferOffset:scratchBufferOffset];
			encoded = true;
        } else if (buildInfo.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR) {
            MVKAccelerationStructure* mvkSrcAccStruct = (MVKAccelerationStructure*)buildInfo.srcAccelerationStructure;
			srcGeneration = mvkSrcAccStruct->retainCurrentGeneration();
			if (srcGeneration) {
				[accStructEncoder refitAccelerationStructure:srcGeneration->getMTLAccelerationStructure()
											  descriptor:descriptor
											 destination:dstAccStruct
										   scratchBuffer:scratchBuffer
									 scratchBufferOffset:scratchBufferOffset];
				encoded = true;
			}
        }
		if (encoded) {
			dstGeneration->publishBuild(buildSizes.accelerationStructureSize,
				instanceMetadataSize,
				buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR ? ranges[0].primitiveCount : 0);
			if (!canonicalBuild.publish(dstGeneration)) {
				cmdEncoder->reportError(VK_ERROR_OUT_OF_HOST_MEMORY,
					"vkCmdBuildAccelerationStructuresKHR(): The canonical build input could not be published.");
			}
			releaseAccelerationStructureGenerationOnCompletion(cmdEncoder, dstGeneration);
			if (srcGeneration) { releaseAccelerationStructureGenerationOnCompletion(cmdEncoder, srcGeneration); }
		} else {
			dstGeneration->release();
			if (srcGeneration) { srcGeneration->release(); }
		}
        [descriptor release];
    }
}

#pragma mark -
#pragma mark MVKCmdCopyAccelerationStructure

VkResult MVKCmdCopyAccelerationStructure::setContent(MVKCommandBuffer* cmdBuff,
                                                     VkAccelerationStructureKHR srcAccelerationStructure,
                                                     VkAccelerationStructureKHR dstAccelerationStructure,
                                                     VkCopyAccelerationStructureModeKHR copyMode) {
	cmdBuff->recordAccelerationStructureCommand();

	_srcMVKAccelerationStructure = (MVKAccelerationStructure*)srcAccelerationStructure;
	_dstMVKAccelerationStructure = (MVKAccelerationStructure*)dstAccelerationStructure;
    _copyMode = copyMode;

    return VK_SUCCESS;
}

void MVKCmdCopyAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
	auto* srcGeneration = _srcMVKAccelerationStructure->retainCurrentGeneration();
	if (!srcGeneration) { return; }
	uint64_t instanceMetadataSize = srcGeneration->getInstanceMetadataSize();
	uint64_t requiredNativeSize = _copyMode == VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR
		? 0
		: srcGeneration->getNativeSize();
	if (!requiredNativeSize && _copyMode != VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR) {
		requiredNativeSize = srcGeneration->getNativeCapacity();
	}
	MVKAccelerationStructureStorageGeneration* dstGeneration = nullptr;
	VkResult result = _dstMVKAccelerationStructure->retainFullWriteGeneration(
		requiredNativeSize, instanceMetadataSize, dstGeneration);
	id<MTLBuffer> srcInstanceMetadata = srcGeneration->getInstanceMetadataMTLBuffer();
	id<MTLBuffer> dstInstanceMetadata = dstGeneration
		? dstGeneration->getInstanceMetadataMTLBuffer()
		: nil;
	if (result < 0 || !dstGeneration ||
		instanceMetadataSize > srcInstanceMetadata.length ||
		!dstGeneration->setInstanceMetadataSize(instanceMetadataSize)) {
        cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
                                "vkCmdCopyAccelerationStructureKHR(): The destination acceleration structure has insufficient instance-metadata capacity.");
		if (dstGeneration) { dstGeneration->release(); }
		srcGeneration->release();
        return;
    }
	if (!_dstMVKAccelerationStructure->publishGeneration(dstGeneration)) {
		dstGeneration->release();
		srcGeneration->release();
		return;
	}
	cmdEncoder->invalidateAccelerationStructureAddressTable();
    id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseCopyAccelerationStructure);

    if(_copyMode == VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR) {
        [accStructEncoder
		 copyAndCompactAccelerationStructure:srcGeneration->getMTLAccelerationStructure()
		 toAccelerationStructure:dstGeneration->getMTLAccelerationStructure()];
    } else {
        [accStructEncoder
			 copyAccelerationStructure:srcGeneration->getMTLAccelerationStructure()
			 toAccelerationStructure:dstGeneration->getMTLAccelerationStructure()];
    }

    if (instanceMetadataSize) {
        [cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructure)
			copyFromBuffer:srcInstanceMetadata
            sourceOffset:0
			toBuffer:dstInstanceMetadata
            destinationOffset:0
            size:instanceMetadataSize];
    }
	dstGeneration->copyContentFrom(srcGeneration,
		_copyMode == VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR
			? _dstMVKAccelerationStructure->getNativeCapacity()
			: UINT64_MAX);
	releaseAccelerationStructureGenerationOnCompletion(cmdEncoder, srcGeneration);
	releaseAccelerationStructureGenerationOnCompletion(cmdEncoder, dstGeneration);
}

#pragma mark -
#pragma mark MVKCmdWriteAccelerationStructuresProperties

VkResult MVKCmdWriteAccelerationStructuresProperties::setContent(MVKCommandBuffer* cmdBuff,
                                                                 uint32_t accelerationStructureCount,
                                                                 const VkAccelerationStructureKHR* pAccelerationStructures,
                                                                 VkQueryType queryType,
                                                                 VkQueryPool queryPool,
                                                                 uint32_t firstQuery) {
	cmdBuff->recordAccelerationStructureCommand();
	switch (queryType) {
		case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR:
		case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SERIALIZATION_SIZE_KHR:
		case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SIZE_KHR:
		case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SERIALIZATION_BOTTOM_LEVEL_POINTERS_KHR:
			break;
		default:
			return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT,
										"vkCmdWriteAccelerationStructuresPropertiesKHR(): Unsupported acceleration-structure query type.");
	}
	_accelerationStructures.clear();
	_accelerationStructures.reserve(accelerationStructureCount);
	for (uint32_t index = 0; index < accelerationStructureCount; index++) {
		_accelerationStructures.push_back((MVKAccelerationStructure*)pAccelerationStructures[index]);
	}
	_queryPool = (MVKAccelerationStructureQueryPool*)queryPool;
	_queryType = queryType;
	_firstQuery = firstQuery;
	return VK_SUCCESS;
}

void MVKCmdWriteAccelerationStructuresProperties::encode(MVKCommandEncoder* cmdEncoder) {
	if (_accelerationStructures.empty()) { return; }
	if (_queryType == VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR) {
		id<MTLAccelerationStructureCommandEncoder> encoder =
			cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseWriteAccelerationStructuresProperties);
		for (uint32_t index = 0; index < _accelerationStructures.size(); index++) {
			auto* generation = _accelerationStructures[index]->retainCurrentGeneration();
			uint32_t query = _firstQuery + index;
			if (generation) {
				[encoder writeCompactedAccelerationStructureSize:generation->getMTLAccelerationStructure()
				                                      toBuffer:_queryPool->getResultMTLBuffer()
				                                        offset:_queryPool->getResultOffset(query)
				                                  sizeDataType:MTLDataTypeULong];
				releaseAccelerationStructureGenerationOnCompletion(cmdEncoder, generation);
			}
			cmdEncoder->markAccelerationStructureQuery(_queryPool, query);
			_queryPool->endQuery(query, cmdEncoder);
		}
		return;
	}
	MVKSmallVector<uint64_t, 1> values;
	MVKSmallVector<MVKAccelerationStructureStorageGeneration*, 1> generations;
	values.reserve(_accelerationStructures.size());
	generations.reserve(_accelerationStructures.size());
	for (auto* accelerationStructure : _accelerationStructures) {
		auto* generation = accelerationStructure->retainCurrentGeneration();
		if (generation) { generations.push_back(generation); }
		switch (_queryType) {
			case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SERIALIZATION_BOTTOM_LEVEL_POINTERS_KHR:
				values.push_back(generation ? generation->getHandleCount() : 0);
				break;
			case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SERIALIZATION_SIZE_KHR:
				values.push_back(generation ? generation->getSerializationSize() : 0);
				break;
			case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SIZE_KHR:
				values.push_back(generation ? generation->getNativeSize() : 0);
				break;
			default:
				values.push_back(0);
				break;
		}
	}
	NSUInteger byteCount = values.size() * sizeof(values[0]);
	const MVKMTLBufferAllocation* allocation =
		cmdEncoder->copyToTempMTLBufferAllocation(values.data(), byteCount);
	id<MTLBlitCommandEncoder> encoder =
		cmdEncoder->getMTLBlitEncoder(kMVKCommandUseWriteAccelerationStructuresProperties);
	[encoder copyFromBuffer:allocation->_mtlBuffer
	          sourceOffset:allocation->_offset
	              toBuffer:_queryPool->getResultMTLBuffer()
	     destinationOffset:_queryPool->getResultOffset(_firstQuery)
	                  size:byteCount];
	for (auto* generation : generations) {
		releaseAccelerationStructureGenerationOnCompletion(cmdEncoder, generation);
	}
	for (uint32_t index = 0; index < values.size(); index++) {
		uint32_t query = _firstQuery + index;
		cmdEncoder->markAccelerationStructureQuery(_queryPool, query);
		_queryPool->endQuery(query, cmdEncoder);
	}
}
