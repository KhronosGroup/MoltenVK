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
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKAccelerationStructure.h"
#include "MVKQueryPool.h"
#include "MVKFoundation.h"

#include <Metal/Metal.h>

#pragma mark -
#pragma mark MVKCmdBuildAccelerationStructure

id<MTLComputeCommandEncoder> mvkEncodeAccelerationStructureConversion(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> srcBuffer,
	NSUInteger srcOffset,
	id<MTLBuffer> dstBuffer,
	NSUInteger dstOffset,
	uint32_t srcStride,
	uint32_t itemCount,
	MVKAccelerationStructureConversionType conversionType,
	id<MTLBuffer> canonicalBuffer,
	NSUInteger canonicalRecordOffset,
	NSUInteger canonicalHandleOffset,
	id<MTLBuffer> instanceMetadata) {
	if (!itemCount) { return nil; }
	id<MTLComputeCommandEncoder> mtlEncoder =
		cmdEncoder->getMTLComputeEncoder(kMVKCommandUseBuildAccelerationStructureConvertBuffers);
	id<MTLComputePipelineState> mtlState = cmdEncoder->getCommandEncodingPool()
		->getCmdBuildAccelerationStructureConvertBuffersMTLComputePipelineState();
	if (!mtlEncoder || !mtlState) { return nil; }
	[mtlEncoder setComputePipelineState:mtlState];
	[mtlEncoder setBuffer:srcBuffer offset:srcOffset atIndex:0];
	[mtlEncoder setBuffer:dstBuffer offset:dstOffset atIndex:1];
	cmdEncoder->setComputeBytes(mtlEncoder, &srcStride, sizeof(srcStride), 2);
	cmdEncoder->setComputeBytes(mtlEncoder, &itemCount, sizeof(itemCount), 3);
	cmdEncoder->setComputeBytes(mtlEncoder, &conversionType, sizeof(conversionType), 4);
	id<MTLBuffer> serializationBuffer = canonicalBuffer ? canonicalBuffer : dstBuffer;
	[mtlEncoder setBuffer:serializationBuffer offset:canonicalBuffer ? canonicalRecordOffset : dstOffset atIndex:6];
	[mtlEncoder setBuffer:serializationBuffer offset:canonicalBuffer ? canonicalHandleOffset : dstOffset atIndex:7];
	[mtlEncoder setBuffer:instanceMetadata ? instanceMetadata : dstBuffer
	                 offset:instanceMetadata ? 0 : dstOffset
	                atIndex:8];
	[mtlEncoder setBuffer:dstBuffer offset:dstOffset atIndex:5];
	if (conversionType != kMVKAccelerationStructureConvertTransform) {
		auto* referenceTable = cmdEncoder->getAccelerationStructureReferenceTable();
		[mtlEncoder setBuffer:referenceTable->_mtlBuffer
					 offset:referenceTable->_offset
					atIndex:5];
	}
	if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
		[mtlEncoder dispatchThreads:MTLSizeMake(itemCount, 1, 1)
			threadsPerThreadgroup:MTLSizeMake(mtlState.threadExecutionWidth, 1, 1)];
	} else {
		[mtlEncoder dispatchThreadgroups:MTLSizeMake(
				mvkCeilingDivide<NSUInteger>(itemCount, mtlState.threadExecutionWidth), 1, 1)
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
		bool hasBuildPrimitives = false;
		for (const auto& range : ranges) {
			hasBuildPrimitives = hasBuildPrimitives || range.primitiveCount;
		}

        MVKAccelerationStructure* mvkDstAccStruct = (MVKAccelerationStructure*)buildInfo.dstAccelerationStructure;

        MVKDevice* mvkDevice = cmdEncoder->getDevice();
        VkDeviceSize scratchOffset = 0;
        MVKBuffer* mvkBuffer = mvkDevice->getBufferAtAddress(buildInfo.scratchData.deviceAddress, scratchOffset);

        if ( !mvkBuffer ) { continue; }
        id<MTLBuffer> scratchBuffer = mvkBuffer->getMTLBuffer();
        NSInteger scratchBufferOffset = mvkBuffer->getMTLBufferOffset() + scratchOffset;

		if (buildInfo.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR && !hasBuildPrimitives) {
			MVKAccelerationStructure* mvkSrcAccStruct =
				(MVKAccelerationStructure*)buildInfo.srcAccelerationStructure;
			auto* dstGeneration = mvkDstAccStruct->retainCurrentGeneration();
			auto* srcGeneration = mvkSrcAccStruct->retainCurrentGeneration();
			uint64_t nativeSize = srcGeneration ? srcGeneration->getNativeSize() : 0;
			uint64_t metadataSize = srcGeneration ? srcGeneration->getInstanceMetadataSize() : 0;
			if (!dstGeneration || !srcGeneration || nativeSize > dstGeneration->getNativeCapacity() ||
				metadataSize > dstGeneration->getMetadataCapacity()) {
				if (dstGeneration) { dstGeneration->release(); }
				if (srcGeneration) { srcGeneration->release(); }
				cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
					"vkCmdBuildAccelerationStructuresKHR(): The destination acceleration structure has insufficient storage capacity.");
				continue;
			}

			id<MTLAccelerationStructure> dstAccStruct = dstGeneration->getMTLAccelerationStructure();
			id<MTLAccelerationStructure> srcAccStruct = srcGeneration->getMTLAccelerationStructure();
			if (srcAccStruct != dstAccStruct) {
				auto* accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(
					kMVKCommandUseBuildAccelerationStructure);
				[accStructEncoder copyAccelerationStructure:srcAccStruct
									 toAccelerationStructure:dstAccStruct];
			}
			if (metadataSize) {
				[cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructure)
					copyFromBuffer:srcGeneration->getInstanceMetadataMTLBuffer()
					sourceOffset:0
					toBuffer:dstGeneration->getInstanceMetadataMTLBuffer()
					destinationOffset:0
					size:metadataSize];
			}
			dstGeneration->copyContentFrom(srcGeneration);
			cmdEncoder->retainAccelerationStructureGeneration(dstGeneration);
			cmdEncoder->retainAccelerationStructureGeneration(srcGeneration);
			continue;
		}

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
			buildInfo, ranges.data());
		if (canonicalResult < 0) {
			cmdEncoder->reportError(canonicalResult,
				"vkCmdBuildAccelerationStructuresKHR(): The canonical build input could not be captured.");
			dstGeneration->release();
			[descriptor release];
			continue;
		}

		bool validTransforms = true;
        if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR) {
            NSArray* geometryDescriptors = ((MTLPrimitiveAccelerationStructureDescriptor*)descriptor).geometryDescriptors;
            for (uint32_t geomIdx = 0; geomIdx < buildInfo.geometryCount && geomIdx < geometryDescriptors.count; geomIdx++) {
                const VkAccelerationStructureGeometryKHR& geometry = buildInfo.pGeometries
                    ? buildInfo.pGeometries[geomIdx]
                    : *buildInfo.ppGeometries[geomIdx];
				if (geometry.geometryType != VK_GEOMETRY_TYPE_TRIANGLES_KHR) { continue; }
                MTLAccelerationStructureTriangleGeometryDescriptor* triangleDescriptor = geometryDescriptors[geomIdx];
				if (geometry.geometry.triangles.transformData.deviceAddress) {
					id<MTLBuffer> srcBuffer = triangleDescriptor.transformationMatrixBuffer;
					if (!srcBuffer) {
						validTransforms = false;
						break;
					}
					const MVKMTLBufferAllocation* tmpBuffer =
						cmdEncoder->getTempMTLBuffer(sizeof(VkTransformMatrixKHR), true);
					if (!tmpBuffer || !tmpBuffer->_mtlBuffer) {
						validTransforms = false;
						break;
					}
						validTransforms = mvkEncodeAccelerationStructureConversion(cmdEncoder,
																  srcBuffer,
																  triangleDescriptor.transformationMatrixBufferOffset,
																  tmpBuffer->_mtlBuffer,
																  tmpBuffer->_offset,
																  sizeof(VkTransformMatrixKHR),
																  1,
																  kMVKAccelerationStructureConvertTransform,
																  nil, 0, 0) != nil;
					if (!validTransforms) { break; }
					triangleDescriptor.transformationMatrixBuffer = tmpBuffer->_mtlBuffer;
					triangleDescriptor.transformationMatrixBufferOffset = tmpBuffer->_offset;
				}
            }
        }
		if (!validTransforms) {
			cmdEncoder->reportError(VK_ERROR_FEATURE_NOT_PRESENT,
				"vkCmdBuildAccelerationStructuresKHR(): Triangle transforms could not be converted.");
			dstGeneration->release();
			[descriptor release];
			continue;
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
            NSUInteger descriptorSize = mvkDevice->getAccelerationStructureInstanceDescriptorSize();
            NSUInteger tmpBufferSize = descriptorSize * (instanceCount ? instanceCount : 1);
            const MVKMTLBufferAllocation* tmpBuffer = cmdEncoder->getTempMTLBuffer(tmpBufferSize, true);
			if (!tmpBuffer || !tmpBuffer->_mtlBuffer) {
				dstGeneration->release();
				[descriptor release];
				continue;
			}
            tlasDescriptor.instanceDescriptorBuffer = tmpBuffer->_mtlBuffer;
            tlasDescriptor.instanceDescriptorBufferOffset = tmpBuffer->_offset;
            tlasDescriptor.instanceDescriptorStride = descriptorSize;
            if (instanceCount) {
                NSUInteger srcOffset = mvkInstancesBuffer->getMTLBufferOffset() + instanceOffset + ranges[0].primitiveOffset;
					if (!mvkEncodeAccelerationStructureConversion(cmdEncoder,
																  mvkInstancesBuffer->getMTLBuffer(),
                                                                          srcOffset,
                                                                          tmpBuffer->_mtlBuffer,
                                                                          tmpBuffer->_offset,
                                                                          srcStride,
                                                                          instanceCount,
																  instancesData.arrayOfPointers
																	  ? kMVKAccelerationStructureConvertInstancePointers
																	  : kMVKAccelerationStructureConvertInstances,
														  canonicalBuild.getMTLBuffer(),
														  canonicalBuild.getRecordTableOffset(),
														  canonicalBuild.getHandleArrayOffset(),
														  instanceMetadata)) {
					dstGeneration->release();
					[descriptor release];
					continue;
				}
				if (!mvkDevice->usesIndirectAccelerationStructureInstanceDescriptors()) {
					const auto& instances = cmdEncoder->getAccelerationStructureInstances();
					tlasDescriptor.instancedAccelerationStructures =
						[NSArray arrayWithObjects:instances.data() count:instances.size()];
				}
            }
        }

		id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseBuildAccelerationStructure);
		if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
            mvkDevice->encodeGPUAddressableAccelerationStructures(cmdEncoder, accStructEncoder);
        }

		MVKAccelerationStructureStorageGeneration* srcGeneration = nullptr;
		bool encoded = false;
		if (buildInfo.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR &&
			mvkDstAccStruct->publishGeneration(dstGeneration)) {
			cmdEncoder->invalidateAccelerationStructureAddressTable();
			cmdEncoder->invalidateAccelerationStructureReferenceTable();
            [accStructEncoder buildAccelerationStructure:dstAccStruct
                                              descriptor:descriptor
                                           scratchBuffer:scratchBuffer
                                     scratchBufferOffset:scratchBufferOffset];
			encoded = true;
        } else if (buildInfo.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR) {
			MVKAccelerationStructure* mvkSrcAccStruct = (MVKAccelerationStructure*)buildInfo.srcAccelerationStructure;
			srcGeneration = mvkSrcAccStruct->retainCurrentGeneration();
			if (srcGeneration) {
				id<MTLAccelerationStructure> srcAccStruct = srcGeneration->getMTLAccelerationStructure();
				if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR) {
					[accStructEncoder refitAccelerationStructure:srcAccStruct
											  descriptor:descriptor
											 destination:dstAccStruct
										  scratchBuffer:scratchBuffer
									scratchBufferOffset:scratchBufferOffset
											 options:MTLAccelerationStructureRefitOptionVertexData];
				} else {
					[accStructEncoder refitAccelerationStructure:srcAccStruct
											  descriptor:descriptor
											 destination:dstAccStruct
										  scratchBuffer:scratchBuffer
									scratchBufferOffset:scratchBufferOffset];
				}
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
			cmdEncoder->retainAccelerationStructureGeneration(dstGeneration);
			cmdEncoder->retainAccelerationStructureGeneration(srcGeneration);
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
	uint64_t requiredNativeSize = srcGeneration->getNativeSize();
	if (!requiredNativeSize) {
		requiredNativeSize = srcGeneration->getNativeCapacity();
	}
	if (_copyMode == VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR) {
		requiredNativeSize = std::min(
			requiredNativeSize, _dstMVKAccelerationStructure->getSize());
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
                                "vkCmdCopyAccelerationStructureKHR(): The destination acceleration structure has insufficient capacity.");
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
	cmdEncoder->invalidateAccelerationStructureReferenceTable();
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
			? dstGeneration->getNativeCapacity()
			: UINT64_MAX);
	cmdEncoder->retainAccelerationStructureGeneration(srcGeneration);
	cmdEncoder->retainAccelerationStructureGeneration(dstGeneration);
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
		case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SIZE_KHR:
		case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SERIALIZATION_BOTTOM_LEVEL_POINTERS_KHR:
		case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SERIALIZATION_SIZE_KHR:
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
				cmdEncoder->retainAccelerationStructureGeneration(generation);
			}
			cmdEncoder->markAccelerationStructureQuery(_queryPool, query);
			_queryPool->endQuery(query, cmdEncoder);
		}
		return;
	}
	MVKSmallVector<uint64_t, 1> values;
	values.reserve(_accelerationStructures.size());
	for (auto* accelerationStructure : _accelerationStructures) {
		auto* generation = accelerationStructure->retainCurrentGeneration();
		uint64_t value = 0;
		if (generation) {
			switch (_queryType) {
				case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SIZE_KHR:
					value = generation->getNativeSize();
					break;
				case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SERIALIZATION_BOTTOM_LEVEL_POINTERS_KHR:
					value = generation->getHandleCount();
					break;
				default:
					value = generation->getSerializationSize();
					break;
			}
		}
		values.push_back(value);
		if (generation) { generation->release(); }
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
	for (uint32_t index = 0; index < values.size(); index++) {
		uint32_t query = _firstQuery + index;
		cmdEncoder->markAccelerationStructureQuery(_queryPool, query);
		_queryPool->endQuery(query, cmdEncoder);
	}
}
