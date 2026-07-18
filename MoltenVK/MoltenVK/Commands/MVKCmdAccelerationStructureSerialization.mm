/*
 * MVKCmdAccelerationStructureSerialization.mm
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

#include "MVKCmdAccelerationStructureSerialization.h"
#include "MVKAccelerationStructure.h"
#include "MVKBuffer.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "mvk_datatypes.hpp"

#include <Metal/Metal.h>
#include <algorithm>
#include <cstring>
#include <limits>

struct MVKAccelerationStructureCanonicalCopy {
	id<MTLBuffer> source;
	NSUInteger sourceOffset;
	VkDeviceSize destinationOffset;
	VkDeviceSize size;
};

struct MVKAccelerationStructureCanonicalIndexedVerticesInfo {
	uint64_t indexOffset;
	uint64_t vertexOffset;
	uint64_t vertexStride;
	uint64_t vertexAvailable;
	uint64_t destinationOffset;
	uint32_t itemCount;
	uint32_t indexElementSize;
	uint32_t vertexElementSize;
	uint32_t maxVertex;
};

static_assert(sizeof(MVKAccelerationStructureCanonicalIndexedVerticesInfo) == 56);

struct MVKAccelerationStructureCanonicalIndexedVertices {
	id<MTLBuffer> indices;
	id<MTLBuffer> vertices;
	MVKAccelerationStructureCanonicalIndexedVerticesInfo info;
};

struct MVKAddressedBufferRange {
	id<MTLBuffer> buffer = nil;
	NSUInteger offset = 0;
	VkDeviceSize remaining = 0;
};

static void trackAccelerationStructureBuffer(MVKDevice* device, id<MTLBuffer> buffer);
static void untrackAccelerationStructureBuffer(MVKDevice* device, id<MTLBuffer> buffer);
static void releaseCanonicalSnapshotOnCompletion(
	MVKCommandEncoder* cmdEncoder,
	MVKAccelerationStructureCanonicalSnapshot snapshot);

static bool getAddressedBufferRange(MVKDevice* device,
									VkDeviceAddress address,
									VkDeviceSize requiredSize,
									MVKAddressedBufferRange& range) {
	VkDeviceSize bufferOffset = 0;
	MVKBuffer* buffer = device->getBufferAtAddress(address, bufferOffset, requiredSize);
	if (!buffer || bufferOffset > buffer->getByteCount()) { return false; }
	VkDeviceSize metalOffset;
	if (!mvkAccelerationStructureSerializationAdd(buffer->getMTLBufferOffset(), bufferOffset, metalOffset) ||
		metalOffset > std::numeric_limits<NSUInteger>::max() ||
		metalOffset > buffer->getMTLBuffer().length) {
		return false;
	}
	range.buffer = buffer->getMTLBuffer();
	range.offset = static_cast<NSUInteger>(metalOffset);
	range.remaining = std::min<VkDeviceSize>(buffer->getByteCount() - bufferOffset,
		range.buffer.length - range.offset);
	return requiredSize <= range.remaining;
}

static bool reserveCanonicalSpan(VkDeviceSize size,
								 VkDeviceSize& dataSize,
								 VkDeviceSize& offset) {
	if (!size) {
		offset = 0;
		return true;
	}
	if (!mvkAccelerationStructureSerializationAlign(dataSize, 16, offset)) { return false; }
	return mvkAccelerationStructureSerializationAdd(offset, size, dataSize);
}

static bool addCanonicalCopy(MVKDevice* device,
							 VkDeviceAddress address,
							 VkDeviceSize sourceRelativeOffset,
							 VkDeviceSize size,
							 VkDeviceSize destinationOffset,
							 MVKSmallVector<MVKAccelerationStructureCanonicalCopy, 8>& copies) {
	if (!size) { return true; }
	VkDeviceSize sourceAddress;
	if (!address ||
		!mvkAccelerationStructureSerializationAdd(address, sourceRelativeOffset, sourceAddress)) {
		return false;
	}
	MVKAddressedBufferRange range;
	if (!getAddressedBufferRange(device, sourceAddress, size, range)) { return false; }
	copies.push_back({range.buffer,
					  range.offset,
					  destinationOffset,
					  size});
	return true;
}

static bool addCanonicalDataSpan(MVKDevice* device,
								 VkDeviceAddress address,
								 VkDeviceSize sourceRelativeOffset,
								 VkDeviceSize size,
								 VkDeviceSize& dataSize,
								 VkDeviceSize& recordOffset,
								 MVKSmallVector<MVKAccelerationStructureCanonicalCopy, 8>& copies) {
	if (!reserveCanonicalSpan(size, dataSize, recordOffset)) { return false; }
	return addCanonicalCopy(device, address, sourceRelativeOffset, size, recordOffset, copies);
}

static uint64_t accelerationStructureIndexSize(VkIndexType indexType) {
	switch (indexType) {
		case VK_INDEX_TYPE_UINT16: return sizeof(uint16_t);
		case VK_INDEX_TYPE_UINT32: return sizeof(uint32_t);
		default: return 0;
	}
}

static void encodeCanonicalBytes(MVKCommandEncoder* cmdEncoder,
								 id<MTLBuffer> destination,
								 VkDeviceSize destinationOffset,
								 const void* bytes,
								 NSUInteger size) {
	if (!size) { return; }
	const MVKMTLBufferAllocation* source = cmdEncoder->copyToTempMTLBufferAllocation(bytes, size);
	[cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructure)
		copyFromBuffer:source->_mtlBuffer
		sourceOffset:source->_offset
		toBuffer:destination
		destinationOffset:static_cast<NSUInteger>(destinationOffset)
		size:size];
}

static bool encodeCanonicalIndexedVertices(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> destination,
	const MVKAccelerationStructureCanonicalIndexedVertices& vertices) {
	id<MTLComputePipelineState> pipeline = cmdEncoder->getCommandEncodingPool()
		->getCmdSerializeAccelerationStructureIndexedVerticesMTLComputePipelineState();
	if (!pipeline) { return false; }
	id<MTLComputeCommandEncoder> encoder =
		cmdEncoder->getMTLComputeEncoder(kMVKCommandUseBuildAccelerationStructureConvertBuffers);
	[encoder setComputePipelineState:pipeline];
	[encoder setBuffer:vertices.indices offset:0 atIndex:0];
	[encoder setBuffer:vertices.vertices offset:0 atIndex:1];
	[encoder setBuffer:destination offset:0 atIndex:2];
	cmdEncoder->setComputeBytes(encoder, &vertices.info, sizeof(vertices.info), 3);
	if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
		[encoder dispatchThreads:MTLSizeMake(vertices.info.itemCount, 1, 1)
			threadsPerThreadgroup:MTLSizeMake(pipeline.threadExecutionWidth, 1, 1)];
	} else {
		[encoder dispatchThreadgroups:MTLSizeMake(
				mvkCeilingDivide<NSUInteger>(vertices.info.itemCount, pipeline.threadExecutionWidth), 1, 1)
			threadsPerThreadgroup:MTLSizeMake(pipeline.threadExecutionWidth, 1, 1)];
	}
	return true;
}

MVKAccelerationStructureCanonicalBuild::~MVKAccelerationStructureCanonicalBuild() {
	if (_buffer && !_published && _commandEncoder) {
		MVKDevice* device = _commandEncoder->getDevice();
		id<MTLBuffer> buffer = [_buffer retain];
		trackAccelerationStructureBuffer(device, buffer);
		[_commandEncoder->_mtlCmdBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
			untrackAccelerationStructureBuffer(device, buffer);
			[buffer release];
		}];
	}
	[_buffer release];
}

VkResult MVKAccelerationStructureCanonicalBuild::prepareAndEncode(
	MVKCommandEncoder* cmdEncoder,
	MVKAccelerationStructure* accelerationStructure,
	const VkAccelerationStructureBuildGeometryInfoKHR& buildInfo,
	const VkAccelerationStructureBuildRangeInfoKHR* ranges,
	uint64_t nativeSize) {
	[_buffer release];
	_buffer = nil;
	_layout = {};
	_handleCount = 0;
	_commandEncoder = nullptr;
	_published = false;

	MVKSmallVector<MVKSerializedAccelerationStructureGeometryRecord, 4> records;
	MVKSmallVector<MVKAccelerationStructureCanonicalCopy, 8> copies;
	MVKSmallVector<MVKAccelerationStructureCanonicalIndexedVertices, 4> indexedVertices;
	VkDeviceSize dataSize = 0;
	VkDeviceSize recordStride = 0;
	VkDeviceSize recordCount = 0;

	if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR) {
		recordStride = sizeof(MVKSerializedAccelerationStructureGeometryRecord);
		recordCount = buildInfo.geometryCount;
		records.resize(buildInfo.geometryCount);
		for (uint32_t index = 0; index < buildInfo.geometryCount; index++) {
			const VkAccelerationStructureGeometryKHR& geometry = buildInfo.pGeometries
				? buildInfo.pGeometries[index] : *buildInfo.ppGeometries[index];
			const VkAccelerationStructureBuildRangeInfoKHR& range = ranges[index];
			auto& record = records[index];
			record.geometryType = geometry.geometryType;
			record.geometryFlags = geometry.flags;
			record.primitiveCount = range.primitiveCount;

			if (geometry.geometryType == VK_GEOMETRY_TYPE_TRIANGLES_KHR) {
				const auto& triangles = geometry.geometry.triangles;
				uint64_t formatSize = mvkVkFormatBytesPerBlock(triangles.vertexFormat);
				record.vertexFormat = triangles.vertexFormat;
				if (!formatSize || formatSize > std::numeric_limits<uint32_t>::max() ||
					(range.primitiveCount && !triangles.vertexStride)) {
					return VK_ERROR_INITIALIZATION_FAILED;
				}
				if (triangles.indexType == VK_INDEX_TYPE_NONE_KHR) {
					uint64_t vertexCount;
					VkDeviceSize vertexSourceOffset;
					if (!mvkAccelerationStructureSerializationMultiply(range.primitiveCount, 3, vertexCount) ||
						!mvkAccelerationStructureSerializationMultiply(range.firstVertex, triangles.vertexStride, vertexSourceOffset) ||
						!mvkAccelerationStructureSerializationAdd(vertexSourceOffset, range.primitiveOffset, vertexSourceOffset)) {
						return VK_ERROR_INITIALIZATION_FAILED;
					}
					record.indexType = VK_INDEX_TYPE_NONE_KHR;
					record.vertexStride = triangles.vertexStride;
					record.maxVertex = vertexCount ? vertexCount - 1 : 0;
					if (vertexCount) {
						VkDeviceSize lastVertexOffset;
						if (!mvkAccelerationStructureSerializationMultiply(vertexCount - 1, triangles.vertexStride, lastVertexOffset) ||
							!mvkAccelerationStructureSerializationAdd(lastVertexOffset, formatSize, record.vertexSize) ||
							!addCanonicalDataSpan(cmdEncoder->getDevice(), triangles.vertexData.deviceAddress,
								vertexSourceOffset, record.vertexSize, dataSize, record.vertexOffset, copies)) {
							return VK_ERROR_INITIALIZATION_FAILED;
						}
					}
				} else {
					uint64_t indexElementSize = accelerationStructureIndexSize(triangles.indexType);
					VkDeviceSize itemCount;
					VkDeviceSize indexSize;
					VkDeviceSize vertexSize;
					VkDeviceSize vertexSourceOffset;
					if (!indexElementSize ||
						!mvkAccelerationStructureSerializationMultiply(range.primitiveCount, 3, itemCount) ||
						itemCount > std::numeric_limits<uint32_t>::max() ||
						!mvkAccelerationStructureSerializationMultiply(itemCount, indexElementSize, indexSize) ||
						!mvkAccelerationStructureSerializationMultiply(itemCount, formatSize, vertexSize) ||
						!mvkAccelerationStructureSerializationMultiply(range.firstVertex, triangles.vertexStride, vertexSourceOffset)) {
						return VK_ERROR_INITIALIZATION_FAILED;
					}
					record.indexType = VK_INDEX_TYPE_NONE_KHR;
					record.vertexStride = formatSize;
					record.maxVertex = itemCount ? itemCount - 1 : 0;
					record.vertexSize = vertexSize;
					if (itemCount) {
						VkDeviceAddress indexAddress;
						VkDeviceAddress vertexAddress;
						MVKAddressedBufferRange indexRange;
						MVKAddressedBufferRange vertexRange;
						if (!reserveCanonicalSpan(vertexSize, dataSize, record.vertexOffset) ||
							!triangles.indexData.deviceAddress ||
							!triangles.vertexData.deviceAddress ||
							!mvkAccelerationStructureSerializationAdd(triangles.indexData.deviceAddress,
								range.primitiveOffset, indexAddress) ||
							!mvkAccelerationStructureSerializationAdd(triangles.vertexData.deviceAddress,
								vertexSourceOffset, vertexAddress) ||
							!getAddressedBufferRange(cmdEncoder->getDevice(), indexAddress, indexSize, indexRange) ||
							!getAddressedBufferRange(cmdEncoder->getDevice(), vertexAddress, formatSize, vertexRange)) {
							return VK_ERROR_INITIALIZATION_FAILED;
						}
						indexedVertices.push_back({indexRange.buffer,
							vertexRange.buffer,
							{indexRange.offset,
							 vertexRange.offset,
							 triangles.vertexStride,
							 vertexRange.remaining,
							 record.vertexOffset,
							 static_cast<uint32_t>(itemCount),
							 static_cast<uint32_t>(indexElementSize),
							 static_cast<uint32_t>(formatSize),
							 triangles.maxVertex}});
					}
				}
				if (triangles.transformData.deviceAddress) {
					record.transformSize = sizeof(VkTransformMatrixKHR);
					if (!addCanonicalDataSpan(cmdEncoder->getDevice(), triangles.transformData.deviceAddress,
							range.transformOffset, record.transformSize, dataSize, record.transformOffset, copies)) {
						return VK_ERROR_INITIALIZATION_FAILED;
					}
				}
			} else if (geometry.geometryType == VK_GEOMETRY_TYPE_AABBS_KHR) {
				const auto& aabbs = geometry.geometry.aabbs;
				record.vertexStride = aabbs.stride;
				if (range.primitiveCount) {
					VkDeviceSize lastAABBOffset;
					if (!aabbs.stride ||
						!mvkAccelerationStructureSerializationMultiply(range.primitiveCount - 1, aabbs.stride, lastAABBOffset) ||
						!mvkAccelerationStructureSerializationAdd(lastAABBOffset, sizeof(VkAabbPositionsKHR), record.aabbSize) ||
						!addCanonicalDataSpan(cmdEncoder->getDevice(), aabbs.data.deviceAddress,
							range.primitiveOffset, record.aabbSize, dataSize, record.aabbOffset, copies)) {
						return VK_ERROR_INITIALIZATION_FAILED;
					}
				}
			} else {
				return VK_ERROR_FEATURE_NOT_PRESENT;
			}
		}
	} else if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
		if (buildInfo.geometryCount != 1) { return VK_ERROR_INITIALIZATION_FAILED; }
		const VkAccelerationStructureGeometryKHR& geometry = buildInfo.pGeometries
			? buildInfo.pGeometries[0] : *buildInfo.ppGeometries[0];
		if (geometry.geometryType != VK_GEOMETRY_TYPE_INSTANCES_KHR) {
			return VK_ERROR_INITIALIZATION_FAILED;
		}
		recordStride = sizeof(MVKSerializedAccelerationStructureInstanceRecord);
		recordCount = ranges[0].primitiveCount;
		_handleCount = recordCount;
	} else {
		return VK_ERROR_FEATURE_NOT_PRESENT;
	}

	if (!mvkGetAccelerationStructureSerializationLayout(_handleCount, recordCount,
			recordStride, dataSize, _layout) ||
		_layout.serializedSize > std::numeric_limits<NSUInteger>::max() ||
		_layout.serializedSize > cmdEncoder->getMetalFeatures().maxMTLBufferSize) {
		return VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}

	for (auto& record : records) {
		if ((record.vertexSize && !mvkAccelerationStructureSerializationAdd(_layout.dataOffset, record.vertexOffset, record.vertexOffset)) ||
			(record.transformSize && !mvkAccelerationStructureSerializationAdd(_layout.dataOffset, record.transformOffset, record.transformOffset)) ||
			(record.aabbSize && !mvkAccelerationStructureSerializationAdd(_layout.dataOffset, record.aabbOffset, record.aabbOffset))) {
			return VK_ERROR_INITIALIZATION_FAILED;
		}
	}
	for (auto& copy : copies) {
		if (!mvkAccelerationStructureSerializationAdd(_layout.dataOffset,
				copy.destinationOffset, copy.destinationOffset)) {
			return VK_ERROR_INITIALIZATION_FAILED;
		}
	}
	for (auto& vertices : indexedVertices) {
		if (!mvkAccelerationStructureSerializationAdd(_layout.dataOffset,
				vertices.info.destinationOffset, vertices.info.destinationOffset)) {
			return VK_ERROR_INITIALIZATION_FAILED;
		}
	}

	MVKSerializedAccelerationStructureHeader header {};
	cmdEncoder->getDevice()->getAccelerationStructureSerializationUUIDs(header.driverUUID,
															 header.compatibilityUUID);
	header.serializedSize = _layout.serializedSize;
	header.deserializedSize = accelerationStructure->getSize();
	header.handleCount = _handleCount;

	MVKSerializedAccelerationStructurePayloadHeader payload {};
	payload.magic = kMVKAccelerationStructureSerializationMagic;
	payload.schema = kMVKAccelerationStructureSerializationSchema;
	payload.endian = kMVKAccelerationStructureSerializationEndian;
	payload.headerSize = sizeof(payload);
	payload.accelerationStructureType = buildInfo.type;
	payload.buildFlags = buildInfo.flags;
	payload.createFlags = accelerationStructure->getCreateFlags();
	payload.recordCount = recordCount;
	payload.recordStride = recordStride;
	payload.recordTableOffset = _layout.recordTableOffset;
	payload.recordTableSize = recordCount * recordStride;
	payload.dataOffset = _layout.dataOffset;
	payload.dataSize = dataSize;
	payload.nativeSize = nativeSize;
	payload.deserializedSize = header.deserializedSize;
	payload.handleCount = _handleCount;

	_buffer = [cmdEncoder->getMTLDevice() newBufferWithLength:static_cast<NSUInteger>(_layout.serializedSize)
												 options:MTLResourceStorageModePrivate];
	if (!_buffer) { return VK_ERROR_OUT_OF_DEVICE_MEMORY; }
	_commandEncoder = cmdEncoder;

	id<MTLBlitCommandEncoder> encoder =
		cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructure);
	[encoder fillBuffer:_buffer range:NSMakeRange(0, static_cast<NSUInteger>(_layout.serializedSize)) value:0];
	encodeCanonicalBytes(cmdEncoder, _buffer, 0, &header, sizeof(header));
	encodeCanonicalBytes(cmdEncoder, _buffer, _layout.payloadOffset, &payload, sizeof(payload));
	encodeCanonicalBytes(cmdEncoder, _buffer, _layout.recordTableOffset,
					 records.data(), static_cast<NSUInteger>(records.size() * sizeof(records[0])));
	encoder = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructure);
	for (const auto& copy : copies) {
		[encoder copyFromBuffer:copy.source
			sourceOffset:copy.sourceOffset
			toBuffer:_buffer
			destinationOffset:static_cast<NSUInteger>(copy.destinationOffset)
			size:static_cast<NSUInteger>(copy.size)];
	}
	for (const auto& vertices : indexedVertices) {
		if (!encodeCanonicalIndexedVertices(cmdEncoder, _buffer, vertices)) {
			return VK_ERROR_INITIALIZATION_FAILED;
		}
	}
	return VK_SUCCESS;
}

bool MVKAccelerationStructureCanonicalBuild::publish(
	MVKAccelerationStructureStorageGeneration* generation) {
	if (!_buffer || !generation) { return false; }
	generation->publishCanonical(_buffer, _layout.serializedSize,
		_layout.serializedSize, _handleCount);
	auto snapshot = generation->retainCanonicalSnapshot();
	_published = snapshot.canonicalBuffer == _buffer &&
		snapshot.serializationSize == _layout.serializedSize;
	if (_published) { releaseCanonicalSnapshotOnCompletion(_commandEncoder, snapshot); }
	else { MVKAccelerationStructureStorageGeneration::releaseCanonicalSnapshot(snapshot); }
	return _published;
}

static void releaseCanonicalSnapshotOnCompletion(
	MVKCommandEncoder* cmdEncoder,
	MVKAccelerationStructureCanonicalSnapshot snapshot) {
	[cmdEncoder->_mtlCmdBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
		auto completedSnapshot = snapshot;
		MVKAccelerationStructureStorageGeneration::releaseCanonicalSnapshot(completedSnapshot);
	}];
}

VkResult MVKCmdCopyAccelerationStructureToMemory::setContent(
	MVKCommandBuffer* cmdBuff,
	MVKAccelerationStructure* accelerationStructure,
	VkDeviceAddress destination,
	VkCopyAccelerationStructureModeKHR mode) {
	cmdBuff->recordAccelerationStructureCommand();
	if (mode != VK_COPY_ACCELERATION_STRUCTURE_MODE_SERIALIZE_KHR) {
		return cmdBuff->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyAccelerationStructureToMemoryKHR(): The copy mode is not SERIALIZE.");
	}
	_accelerationStructure = accelerationStructure;
	_destination = destination;
	return VK_SUCCESS;
}

void MVKCmdCopyAccelerationStructureToMemory::encode(MVKCommandEncoder* cmdEncoder) {
	auto* generation = _accelerationStructure
		? _accelerationStructure->retainCurrentGeneration()
		: nullptr;
	if (!generation) { return; }
	auto snapshot = generation->retainCanonicalSnapshot();
	generation->release();
	bool valid = snapshot.canonicalBuffer && snapshot.serializationSize &&
		snapshot.canonicalSize >= snapshot.serializationSize &&
		snapshot.serializationSize <= snapshot.canonicalBuffer.length &&
		snapshot.serializationSize <= std::numeric_limits<NSUInteger>::max();
	VkDeviceSize destinationOffset = 0;
	MVKBuffer* destination = valid
		? cmdEncoder->getDevice()->getBufferAtAddress(_destination, destinationOffset,
													 snapshot.serializationSize)
		: nullptr;
	VkDeviceSize metalOffset = 0;
	valid = destination &&
		mvkAccelerationStructureSerializationAdd(destination->getMTLBufferOffset(),
			destinationOffset, metalOffset) &&
		metalOffset <= std::numeric_limits<NSUInteger>::max() &&
		snapshot.serializationSize <= std::numeric_limits<NSUInteger>::max() - metalOffset &&
		metalOffset + snapshot.serializationSize <= destination->getMTLBuffer().length;
	if (!valid) {
		MVKAccelerationStructureStorageGeneration::releaseCanonicalSnapshot(snapshot);
		cmdEncoder->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyAccelerationStructureToMemoryKHR(): The canonical acceleration structure or destination range is invalid.");
		return;
	}
	releaseCanonicalSnapshotOnCompletion(cmdEncoder, snapshot);
	[cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructure)
		copyFromBuffer:snapshot.canonicalBuffer
		sourceOffset:0
		toBuffer:destination->getMTLBuffer()
		destinationOffset:static_cast<NSUInteger>(metalOffset)
		size:static_cast<NSUInteger>(snapshot.serializationSize)];
}

static void trackAccelerationStructureBuffer(MVKDevice* device, id<MTLBuffer> buffer) {
	device->getLiveResources().add(buffer);
	device->makeResident(buffer);
}

static void untrackAccelerationStructureBuffer(MVKDevice* device, id<MTLBuffer> buffer) {
	device->removeResidency(buffer);
	device->getLiveResources().remove(buffer);
}

static void releaseAccelerationStructureBuffer(MVKDevice* device, id<MTLBuffer> buffer) {
	if (!buffer) { return; }
	untrackAccelerationStructureBuffer(device, buffer);
	[buffer release];
}

static id<MTLBuffer> readAccelerationStructureBytes(
	MVKCommandEncoder* cmdEncoder,
	const MVKAddressedBufferRange& source,
	NSUInteger size) {
	id<MTLBuffer> staging = [cmdEncoder->getMTLDevice() newBufferWithLength:size
														 options:MTLResourceStorageModeShared];
	if (!staging) { return nil; }
	trackAccelerationStructureBuffer(cmdEncoder->getDevice(), staging);
	[cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructure)
		copyFromBuffer:source.buffer
		sourceOffset:source.offset
		toBuffer:staging
		destinationOffset:0
		size:size];
	if (cmdEncoder->splitForHostReadback() != VK_SUCCESS) {
		releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), staging);
		return nil;
	}
	return staging;
}

static bool validateAccelerationStructureHeader(
	MVKDevice* device,
	const MVKSerializedAccelerationStructureHeader& header,
	VkDeviceSize remaining) {
	uint8_t driverUUID[VK_UUID_SIZE];
	uint8_t compatibilityUUID[VK_UUID_SIZE];
	device->getAccelerationStructureSerializationUUIDs(driverUUID, compatibilityUUID);
	VkDeviceSize handleBytes;
	VkDeviceSize minimumSize;
	return !std::memcmp(header.driverUUID, driverUUID, sizeof(driverUUID)) &&
		!std::memcmp(header.compatibilityUUID, compatibilityUUID, sizeof(compatibilityUUID)) &&
		header.serializedSize >= kMVKAccelerationStructureSerializationAlignment &&
		!(header.serializedSize % kMVKAccelerationStructureSerializationAlignment) &&
		header.serializedSize <= remaining &&
		header.serializedSize <= device->getPhysicalDevice()->getMetalFeatures()->maxMTLBufferSize &&
		header.serializedSize <= std::numeric_limits<NSUInteger>::max() &&
		header.deserializedSize &&
		mvkAccelerationStructureSerializationMultiply(header.handleCount,
			sizeof(VkDeviceAddress), handleBytes) &&
		mvkAccelerationStructureSerializationAdd(sizeof(header), handleBytes, minimumSize) &&
		minimumSize <= header.serializedSize;
}

struct MVKValidatedAccelerationStructureSerialization {
	MVKSerializedAccelerationStructureHeader header {};
	MVKSerializedAccelerationStructurePayloadHeader payload {};
	MVKAccelerationStructureSerializationLayout layout {};
};

template<class T>
static bool readAccelerationStructureSerializationValue(id<MTLBuffer> buffer,
														  VkDeviceSize offset,
														  T& value) {
	if (offset > buffer.length || sizeof(T) > buffer.length - offset) { return false; }
	std::memcpy(&value, static_cast<const uint8_t*>(buffer.contents) + offset, sizeof(T));
	return true;
}

static bool validateAccelerationStructureSerialization(
	MVKDevice* device,
	id<MTLBuffer> buffer,
	const MVKSerializedAccelerationStructureHeader& expectedHeader,
	MVKValidatedAccelerationStructureSerialization& serialization) {
	if (!readAccelerationStructureSerializationValue(buffer, 0, serialization.header) ||
		std::memcmp(&serialization.header, &expectedHeader, sizeof(expectedHeader)) ||
		!validateAccelerationStructureHeader(device, serialization.header, buffer.length)) {
		return false;
	}
	VkDeviceSize handleBytes;
	VkDeviceSize payloadOffset;
	if (!mvkAccelerationStructureSerializationMultiply(serialization.header.handleCount,
			sizeof(VkDeviceAddress), handleBytes) ||
		!mvkAccelerationStructureSerializationAdd(sizeof(serialization.header), handleBytes, payloadOffset) ||
		!mvkAccelerationStructureSerializationAlign(payloadOffset,
			kMVKAccelerationStructureSerializationAlignment, payloadOffset) ||
		!readAccelerationStructureSerializationValue(buffer, payloadOffset, serialization.payload)) {
		return false;
	}
	const auto& payload = serialization.payload;
	VkDeviceSize expectedStride;
	if (payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR) {
		expectedStride = sizeof(MVKSerializedAccelerationStructureGeometryRecord);
		if (payload.handleCount || serialization.header.handleCount) { return false; }
	} else if (payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
		expectedStride = sizeof(MVKSerializedAccelerationStructureInstanceRecord);
		if (payload.recordCount != payload.handleCount ||
			payload.handleCount != serialization.header.handleCount ||
			payload.handleCount > std::numeric_limits<uint32_t>::max() || payload.dataSize) {
			return false;
		}
	} else {
		return false;
	}
	VkDeviceSize recordTableSize;
	if (payload.magic != kMVKAccelerationStructureSerializationMagic ||
		payload.schema != kMVKAccelerationStructureSerializationSchema ||
		payload.endian != kMVKAccelerationStructureSerializationEndian ||
		payload.headerSize != sizeof(payload) ||
		payload.buildFlags > std::numeric_limits<VkBuildAccelerationStructureFlagsKHR>::max() ||
		payload.createFlags > std::numeric_limits<VkAccelerationStructureCreateFlagsKHR>::max() ||
		payload.recordStride != expectedStride ||
		payload.deserializedSize != serialization.header.deserializedSize ||
		!payload.nativeSize ||
		payload.reserved[0] || payload.reserved[1] ||
		!mvkAccelerationStructureSerializationMultiply(payload.recordCount,
			payload.recordStride, recordTableSize) ||
		payload.recordTableSize != recordTableSize ||
		!mvkGetAccelerationStructureSerializationLayout(payload.handleCount,
			payload.recordCount, payload.recordStride, payload.dataSize, serialization.layout) ||
		serialization.layout.payloadOffset != payloadOffset ||
		serialization.layout.recordTableOffset != payload.recordTableOffset ||
		serialization.layout.dataOffset != payload.dataOffset ||
		serialization.layout.serializedSize != serialization.header.serializedSize) {
		return false;
	}
	return true;
}

static bool isAccelerationStructureDestinationTypeCompatible(
	MVKAccelerationStructure* accelerationStructure,
	const MVKSerializedAccelerationStructurePayloadHeader& payload) {
	VkAccelerationStructureTypeKHR type = accelerationStructure->getAccelerationStructureType();
	return type == VK_ACCELERATION_STRUCTURE_TYPE_GENERIC_KHR ||
		type == payload.accelerationStructureType;
}

static bool validateAccelerationStructureSerializationSpan(
	const MVKValidatedAccelerationStructureSerialization& serialization,
	VkDeviceSize offset,
	VkDeviceSize size) {
	if (!size) { return offset == 0; }
	VkDeviceSize dataEnd;
	return offset >= serialization.layout.dataOffset &&
		mvkAccelerationStructureSerializationAdd(serialization.layout.dataOffset,
			serialization.payload.dataSize, dataEnd) &&
		offset <= dataEnd && size <= dataEnd - offset;
}

static bool isZeroed(const uint64_t* values, size_t count) {
	for (size_t index = 0; index < count; index++) {
		if (values[index]) { return false; }
	}
	return true;
}

static void applyAccelerationStructureUsage(MTLAccelerationStructureDescriptor* descriptor,
											 VkBuildAccelerationStructureFlagsKHR flags) {
	descriptor.usage = MTLAccelerationStructureUsageExtendedLimits;
	if (mvkIsAnyFlagEnabled(flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)) {
		descriptor.usage |= MTLAccelerationStructureUsageRefit;
	}
	if (mvkIsAnyFlagEnabled(flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)) {
		descriptor.usage |= MTLAccelerationStructureUsagePreferFastBuild;
	}
#if MVK_XCODE_26
	if (@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)) {
		if (mvkIsAnyFlagEnabled(flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR)) {
			descriptor.usage |= MTLAccelerationStructureUsagePreferFastIntersection;
		}
		if (mvkIsAnyFlagEnabled(flags, VK_BUILD_ACCELERATION_STRUCTURE_LOW_MEMORY_BIT_KHR)) {
			descriptor.usage |= MTLAccelerationStructureUsageMinimizeMemory;
		}
	}
#endif
}

static bool encodeDeserializedBLASTrianglePositions(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> serializationBuffer,
	const MVKValidatedAccelerationStructureSerialization& serialization,
	MTLPrimitiveAccelerationStructureDescriptor* descriptor,
	id<MTLComputeCommandEncoder>& computeEncoder) {
	constexpr NSUInteger primitiveDataStride = 3 * 3 * sizeof(float);
	struct TrianglePositions {
		MTLAccelerationStructureTriangleGeometryDescriptor* geometry;
		MVKAccelerationStructureTrianglePositionsInfo info;
	};
	MVKSmallVector<TrianglePositions, 4> trianglePositions;
	bool hasPrimitives = false;
	NSArray* geometries = descriptor.geometryDescriptors;
	for (uint64_t index = 0; index < serialization.payload.recordCount; index++) {
		MVKSerializedAccelerationStructureGeometryRecord record;
		VkDeviceSize recordOffset;
		if (!mvkAccelerationStructureSerializationMultiply(index,
				serialization.payload.recordStride, recordOffset) ||
			!mvkAccelerationStructureSerializationAdd(serialization.layout.recordTableOffset,
				recordOffset, recordOffset) ||
			!readAccelerationStructureSerializationValue(serializationBuffer, recordOffset, record)) {
			return false;
		}
		if (record.geometryType != VK_GEOMETRY_TYPE_TRIANGLES_KHR) { continue; }

		uint32_t positionFormat = 0;
		uint32_t vertexElementSize = 0;
		if (index >= geometries.count ||
			!mvkGetAccelerationStructurePositionFormat(static_cast<VkFormat>(record.vertexFormat),
				positionFormat, vertexElementSize) ||
			record.primitiveCount > std::numeric_limits<uint32_t>::max() ||
			record.vertexStride > std::numeric_limits<uint32_t>::max() ||
			record.maxVertex > std::numeric_limits<uint32_t>::max() ||
			record.primitiveCount >
				cmdEncoder->getMetalFeatures().maxMTLBufferSize / primitiveDataStride) {
			return false;
		}

		MTLAccelerationStructureTriangleGeometryDescriptor* geometry = geometries[index];
		if (record.primitiveCount && (!geometry.vertexBuffer ||
			geometry.vertexBufferOffset > geometry.vertexBuffer.length ||
			record.vertexSize > geometry.vertexBuffer.length - geometry.vertexBufferOffset ||
			(geometry.transformationMatrixBuffer &&
			 (geometry.transformationMatrixBufferOffset > geometry.transformationMatrixBuffer.length ||
			  sizeof(VkTransformMatrixKHR) > geometry.transformationMatrixBuffer.length -
				geometry.transformationMatrixBufferOffset)))) {
			return false;
		}
		MVKAccelerationStructureTrianglePositionsInfo info {
			.vertexAvailable = record.vertexSize,
			.indexAvailable = 0,
			.vertexStride = static_cast<uint32_t>(record.vertexStride),
			.vertexFormat = positionFormat,
			.indexElementSize = 0,
			.vertexElementSize = vertexElementSize,
			.maxVertex = static_cast<uint32_t>(record.maxVertex),
			.primitiveCount = static_cast<uint32_t>(record.primitiveCount),
			.hasTransform = geometry.transformationMatrixBuffer != nil,
		};
		trianglePositions.push_back({geometry, info});
		hasPrimitives |= record.primitiveCount != 0;
	}

	id<MTLComputePipelineState> pipeline = hasPrimitives
		? cmdEncoder->getCommandEncodingPool()
			->getCmdBuildAccelerationStructureTrianglePositionsMTLComputePipelineState()
		: nil;
	if (hasPrimitives && !pipeline) { return false; }
	for (const auto& positionsInfo : trianglePositions) {
		auto* geometry = positionsInfo.geometry;
		const auto& info = positionsInfo.info;
		NSUInteger dataSize = std::max<NSUInteger>(primitiveDataStride,
			static_cast<NSUInteger>(info.primitiveCount) * primitiveDataStride);
		const MVKMTLBufferAllocation* positions = cmdEncoder->getTempMTLBuffer(dataSize, true);
		if (!positions || !positions->_mtlBuffer) { return false; }
		geometry.primitiveDataBuffer = positions->_mtlBuffer;
		geometry.primitiveDataBufferOffset = positions->_offset;
		geometry.primitiveDataElementSize = primitiveDataStride;
		geometry.primitiveDataStride = primitiveDataStride;
		if (!info.primitiveCount) { continue; }

		computeEncoder = cmdEncoder->getMTLComputeEncoder(
			kMVKCommandUseBuildAccelerationStructureConvertBuffers);
		[computeEncoder setComputePipelineState:pipeline];
		[computeEncoder setBuffer:geometry.vertexBuffer
						 offset:geometry.vertexBufferOffset
						atIndex:0];
		[computeEncoder setBuffer:geometry.vertexBuffer
						 offset:geometry.vertexBufferOffset
						atIndex:1];
		[computeEncoder setBuffer:geometry.transformationMatrixBuffer ?: positions->_mtlBuffer
						 offset:geometry.transformationMatrixBuffer
							? geometry.transformationMatrixBufferOffset : positions->_offset
						atIndex:2];
		[computeEncoder setBuffer:positions->_mtlBuffer offset:positions->_offset atIndex:3];
		cmdEncoder->setComputeBytes(computeEncoder, &info, sizeof(info), 4);
		if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
			[computeEncoder dispatchThreads:MTLSizeMake(info.primitiveCount, 1, 1)
				 threadsPerThreadgroup:MTLSizeMake(pipeline.threadExecutionWidth, 1, 1)];
		} else {
			[computeEncoder dispatchThreadgroups:MTLSizeMake(
					mvkCeilingDivide<NSUInteger>(info.primitiveCount, pipeline.threadExecutionWidth), 1, 1)
					  threadsPerThreadgroup:MTLSizeMake(pipeline.threadExecutionWidth, 1, 1)];
		}
	}
	return true;
}

static MTLAccelerationStructureDescriptor* newDeserializedBLASDescriptor(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> serializationBuffer,
	const MVKValidatedAccelerationStructureSerialization& serialization,
	id<MTLComputeCommandEncoder>& computeEncoder) {
	NSMutableArray* geometries = [NSMutableArray new];
	for (uint64_t index = 0; index < serialization.payload.recordCount; index++) {
		MVKSerializedAccelerationStructureGeometryRecord record;
		VkDeviceSize recordOffset;
		if (!mvkAccelerationStructureSerializationMultiply(index,
				serialization.payload.recordStride, recordOffset) ||
			!mvkAccelerationStructureSerializationAdd(serialization.layout.recordTableOffset,
				recordOffset, recordOffset) ||
			!readAccelerationStructureSerializationValue(serializationBuffer, recordOffset, record) ||
			!isZeroed(record.reserved, 3) ||
			record.primitiveCount > std::numeric_limits<NSUInteger>::max() ||
			record.vertexStride > std::numeric_limits<NSUInteger>::max()) {
			[geometries release];
			return nil;
		}

		if (record.geometryType == VK_GEOMETRY_TYPE_TRIANGLES_KHR) {
			uint64_t formatSize = mvkVkFormatBytesPerBlock(static_cast<VkFormat>(record.vertexFormat));
			uint64_t vertexCount = 0;
			uint64_t expectedVertexSize = 0;
			if (!formatSize ||
				mvkMTLAccelerationStructureVertexFormatFromVkFormat(static_cast<VkFormat>(record.vertexFormat)) == MTLAttributeFormatInvalid ||
				record.indexType != VK_INDEX_TYPE_NONE_KHR ||
				record.aabbOffset || record.aabbSize ||
				record.indexOffset || record.indexSize ||
				(record.primitiveCount && !record.vertexStride) ||
				!mvkAccelerationStructureSerializationMultiply(record.primitiveCount, 3, vertexCount) ||
				record.maxVertex != (vertexCount ? vertexCount - 1 : 0)) {
				[geometries release];
				return nil;
			}
			if (vertexCount) {
				VkDeviceSize lastVertexOffset;
				if (!mvkAccelerationStructureSerializationMultiply(vertexCount - 1,
						record.vertexStride, lastVertexOffset) ||
					!mvkAccelerationStructureSerializationAdd(lastVertexOffset,
						formatSize, expectedVertexSize)) {
					[geometries release];
					return nil;
				}
			}
			if (record.vertexSize != expectedVertexSize ||
				!validateAccelerationStructureSerializationSpan(serialization,
					record.vertexOffset, record.vertexSize) ||
				!validateAccelerationStructureSerializationSpan(serialization,
					record.transformOffset, record.transformSize) ||
				(record.transformSize && record.transformSize != sizeof(VkTransformMatrixKHR)) ||
				record.vertexOffset > std::numeric_limits<NSUInteger>::max()) {
				[geometries release];
				return nil;
			}

			MTLAccelerationStructureTriangleGeometryDescriptor* geometry =
				[MTLAccelerationStructureTriangleGeometryDescriptor new];
			geometry.triangleCount = static_cast<NSUInteger>(record.primitiveCount);
			geometry.vertexStride = static_cast<NSUInteger>(record.vertexStride);
			geometry.vertexFormat = mvkMTLAccelerationStructureVertexFormatFromVkFormat(
				static_cast<VkFormat>(record.vertexFormat));
			if (record.vertexSize) {
				geometry.vertexBuffer = serializationBuffer;
				geometry.vertexBufferOffset = static_cast<NSUInteger>(record.vertexOffset);
			} else {
				id<MTLBuffer> emptyVertexBuffer = [cmdEncoder->getMTLDevice()
					newBufferWithLength:sizeof(float) * 3
					options:MTLResourceStorageModePrivate];
				if (!emptyVertexBuffer) {
					[geometry release];
					[geometries release];
					return nil;
				}
				geometry.vertexBuffer = emptyVertexBuffer;
				[emptyVertexBuffer release];
			}
			if (record.transformSize) {
				float source[12];
				float transform[12];
				std::memcpy(source,
					static_cast<const uint8_t*>(serializationBuffer.contents) + record.transformOffset,
					sizeof(source));
				transform[0] = source[0]; transform[1] = source[4]; transform[2] = source[8];
				transform[3] = source[1]; transform[4] = source[5]; transform[5] = source[9];
				transform[6] = source[2]; transform[7] = source[6]; transform[8] = source[10];
				transform[9] = source[3]; transform[10] = source[7]; transform[11] = source[11];
				const MVKMTLBufferAllocation* allocation =
					cmdEncoder->copyToTempMTLBufferAllocation(transform, sizeof(transform));
				geometry.transformationMatrixBuffer = allocation->_mtlBuffer;
				geometry.transformationMatrixBufferOffset = allocation->_offset;
			}
			geometry.opaque = mvkIsAnyFlagEnabled(record.geometryFlags, VK_GEOMETRY_OPAQUE_BIT_KHR);
			geometry.allowDuplicateIntersectionFunctionInvocation =
				!mvkIsAnyFlagEnabled(record.geometryFlags,
					VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_KHR);
			[geometries addObject:geometry];
			[geometry release];
		} else if (record.geometryType == VK_GEOMETRY_TYPE_AABBS_KHR) {
			VkDeviceSize expectedSize = 0;
			if (record.primitiveCount) {
				VkDeviceSize lastOffset;
				if (!record.vertexStride ||
					!mvkAccelerationStructureSerializationMultiply(record.primitiveCount - 1,
						record.vertexStride, lastOffset) ||
					!mvkAccelerationStructureSerializationAdd(lastOffset,
						sizeof(VkAabbPositionsKHR), expectedSize)) {
					[geometries release];
					return nil;
				}
			}
			if (record.vertexFormat || record.indexType || record.maxVertex ||
				record.vertexOffset || record.vertexSize || record.indexOffset || record.indexSize ||
				record.transformOffset || record.transformSize || record.aabbSize != expectedSize ||
				!validateAccelerationStructureSerializationSpan(serialization,
					record.aabbOffset, record.aabbSize) ||
				record.aabbOffset > std::numeric_limits<NSUInteger>::max()) {
				[geometries release];
				return nil;
			}
			MTLAccelerationStructureBoundingBoxGeometryDescriptor* geometry =
				[MTLAccelerationStructureBoundingBoxGeometryDescriptor new];
			geometry.boundingBoxCount = static_cast<NSUInteger>(record.primitiveCount);
			geometry.boundingBoxStride = record.primitiveCount ||
				record.vertexStride >= sizeof(VkAabbPositionsKHR)
				? static_cast<NSUInteger>(record.vertexStride) : sizeof(VkAabbPositionsKHR);
			if (record.aabbSize) {
				geometry.boundingBoxBuffer = serializationBuffer;
				geometry.boundingBoxBufferOffset = static_cast<NSUInteger>(record.aabbOffset);
			} else {
				id<MTLBuffer> emptyBoundingBoxBuffer = [cmdEncoder->getMTLDevice()
					newBufferWithLength:sizeof(VkAabbPositionsKHR)
					options:MTLResourceStorageModePrivate];
				if (!emptyBoundingBoxBuffer) {
					[geometry release];
					[geometries release];
					return nil;
				}
				geometry.boundingBoxBuffer = emptyBoundingBoxBuffer;
				[emptyBoundingBoxBuffer release];
			}
			geometry.opaque = mvkIsAnyFlagEnabled(record.geometryFlags, VK_GEOMETRY_OPAQUE_BIT_KHR);
			geometry.allowDuplicateIntersectionFunctionInvocation =
				!mvkIsAnyFlagEnabled(record.geometryFlags,
					VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_KHR);
			[geometries addObject:geometry];
			[geometry release];
		} else {
			[geometries release];
			return nil;
		}
	}
	if (!serialization.payload.recordCount) {
		id<MTLBuffer> emptyVertexBuffer = [cmdEncoder->getMTLDevice()
			newBufferWithLength:sizeof(float) * 3
			options:MTLResourceStorageModePrivate];
		if (!emptyVertexBuffer) {
			[geometries release];
			return nil;
		}
		MTLAccelerationStructureTriangleGeometryDescriptor* geometry =
			[MTLAccelerationStructureTriangleGeometryDescriptor new];
		geometry.vertexBuffer = emptyVertexBuffer;
		geometry.vertexStride = sizeof(float) * 3;
		[geometries addObject:geometry];
		[geometry release];
		[emptyVertexBuffer release];
	}
	MTLPrimitiveAccelerationStructureDescriptor* descriptor =
		[MTLPrimitiveAccelerationStructureDescriptor new];
	descriptor.geometryDescriptors = geometries;
	[geometries release];
	applyAccelerationStructureUsage(descriptor,
		static_cast<VkBuildAccelerationStructureFlagsKHR>(serialization.payload.buildFlags));
	if (mvkIsAnyFlagEnabled(serialization.payload.buildFlags,
			VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_DATA_ACCESS_BIT_KHR) &&
		!encodeDeserializedBLASTrianglePositions(cmdEncoder, serializationBuffer,
			serialization, descriptor, computeEncoder)) {
		[descriptor release];
		return nil;
	}
	return descriptor;
}

static MTLAccelerationStructureDescriptor* newDeserializedTLASDescriptor(
	id<MTLBuffer> serializationBuffer,
	const MVKValidatedAccelerationStructureSerialization& serialization) {
	for (uint64_t index = 0; index < serialization.payload.recordCount; index++) {
		MVKSerializedAccelerationStructureInstanceRecord record;
		VkDeviceSize recordOffset;
		if (!mvkAccelerationStructureSerializationMultiply(index,
				serialization.payload.recordStride, recordOffset) ||
			!mvkAccelerationStructureSerializationAdd(serialization.layout.recordTableOffset,
				recordOffset, recordOffset) ||
			!readAccelerationStructureSerializationValue(serializationBuffer, recordOffset, record) ||
			record.handleSlot >= serialization.payload.handleCount || record.reserved) {
			return nil;
		}
	}
	MTLInstanceAccelerationStructureDescriptor* descriptor =
		[MTLInstanceAccelerationStructureDescriptor new];
	descriptor.instanceDescriptorType = MTLAccelerationStructureInstanceDescriptorTypeIndirect;
	descriptor.instanceCount = static_cast<NSUInteger>(serialization.payload.recordCount);
	applyAccelerationStructureUsage(descriptor,
		static_cast<VkBuildAccelerationStructureFlagsKHR>(serialization.payload.buildFlags));
	return descriptor;
}

static id<MTLComputeCommandEncoder> encodeDeserializedTLASInstances(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> serializationBuffer,
	const MVKValidatedAccelerationStructureSerialization& serialization,
	MVKAccelerationStructureStorageGeneration* generation,
	MTLInstanceAccelerationStructureDescriptor* descriptor) {
	uint32_t itemCount = static_cast<uint32_t>(serialization.payload.recordCount);
	if (!itemCount) { return nil; }
	VkDeviceSize descriptorBytes;
	if (!mvkAccelerationStructureSerializationMultiply(itemCount,
			sizeof(MTLIndirectAccelerationStructureInstanceDescriptor), descriptorBytes) ||
		descriptorBytes > std::numeric_limits<NSUInteger>::max()) {
		return nil;
	}
	const MVKMTLBufferAllocation* instances =
		cmdEncoder->getTempMTLBuffer(static_cast<NSUInteger>(descriptorBytes), true);
	descriptor.instanceDescriptorBuffer = instances->_mtlBuffer;
	descriptor.instanceDescriptorBufferOffset = instances->_offset;
	descriptor.instanceDescriptorStride = sizeof(MTLIndirectAccelerationStructureInstanceDescriptor);

	id<MTLComputePipelineState> pipeline = cmdEncoder->getCommandEncodingPool()
		->getCmdDeserializeAccelerationStructureInstancesMTLComputePipelineState();
	if (!pipeline) { return nil; }
	id<MTLComputeCommandEncoder> encoder =
		cmdEncoder->getMTLComputeEncoder(kMVKCommandUseBuildAccelerationStructureConvertBuffers);
	[encoder setComputePipelineState:pipeline];
	[encoder setBuffer:serializationBuffer
			 offset:static_cast<NSUInteger>(serialization.layout.recordTableOffset)
			atIndex:0];
	[encoder setBuffer:serializationBuffer
			 offset:sizeof(MVKSerializedAccelerationStructureHeader)
			atIndex:1];
	[encoder setBuffer:instances->_mtlBuffer offset:instances->_offset atIndex:2];
	[encoder setBuffer:generation->getInstanceMetadataMTLBuffer() offset:0 atIndex:3];
	cmdEncoder->setComputeBytes(encoder, &itemCount, sizeof(itemCount), 4);
	MVKUseResourceHelper resources;
	const MVKMTLBufferAllocation* addressTable =
		cmdEncoder->getAccelerationStructureAddressTable(resources, MVKResourceUsageStages::Compute);
	[encoder setBuffer:addressTable->_mtlBuffer offset:addressTable->_offset atIndex:5];
	resources.bindAndResetCompute(encoder);
	if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
		[encoder dispatchThreads:MTLSizeMake(itemCount, 1, 1)
			threadsPerThreadgroup:MTLSizeMake(pipeline.threadExecutionWidth, 1, 1)];
	} else {
		[encoder dispatchThreadgroups:MTLSizeMake(
				mvkCeilingDivide<NSUInteger>(itemCount, pipeline.threadExecutionWidth), 1, 1)
			threadsPerThreadgroup:MTLSizeMake(pipeline.threadExecutionWidth, 1, 1)];
	}
	return encoder;
}

static void releaseDeserializationResourcesOnCompletion(
	MVKCommandEncoder* cmdEncoder,
	MVKAccelerationStructureStorageGeneration* generation,
	id<MTLBuffer> serializationBuffer) {
	MVKDevice* device = cmdEncoder->getDevice();
	[cmdEncoder->_mtlCmdBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
		generation->release();
		releaseAccelerationStructureBuffer(device, serializationBuffer);
	}];
}

static void releaseDeserializationBufferOnCompletion(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> serializationBuffer) {
	MVKDevice* device = cmdEncoder->getDevice();
	[cmdEncoder->_mtlCmdBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
		releaseAccelerationStructureBuffer(device, serializationBuffer);
	}];
}

VkResult MVKCmdCopyMemoryToAccelerationStructure::setContent(
	MVKCommandBuffer* cmdBuff,
	VkDeviceAddress source,
	MVKAccelerationStructure* accelerationStructure,
	VkCopyAccelerationStructureModeKHR mode) {
	cmdBuff->recordAccelerationStructureCommand();
	if (mode != VK_COPY_ACCELERATION_STRUCTURE_MODE_DESERIALIZE_KHR) {
		return cmdBuff->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The copy mode is not DESERIALIZE.");
	}
	_source = source;
	_accelerationStructure = accelerationStructure;
	cmdBuff->recordHostReadbackCommand();
	return VK_SUCCESS;
}

void MVKCmdCopyMemoryToAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
	MVKAddressedBufferRange source;
	if (!_accelerationStructure ||
		!getAddressedBufferRange(cmdEncoder->getDevice(), _source,
			sizeof(MVKSerializedAccelerationStructureHeader), source)) {
		cmdEncoder->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized header is outside the source buffer.");
		return;
	}
	id<MTLBuffer> headerBuffer = readAccelerationStructureBytes(cmdEncoder, source,
		sizeof(MVKSerializedAccelerationStructureHeader));
	MVKSerializedAccelerationStructureHeader header;
	if (!headerBuffer) {
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized header could not be read.");
		return;
	}
	std::memcpy(&header, headerBuffer.contents, sizeof(header));
	releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), headerBuffer);
	if (!validateAccelerationStructureHeader(cmdEncoder->getDevice(), header, source.remaining) ||
		header.deserializedSize > _accelerationStructure->getSize()) {
		cmdEncoder->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized header is incompatible or invalid.");
		return;
	}

	if (!getAddressedBufferRange(cmdEncoder->getDevice(), _source,
			header.serializedSize, source)) {
		cmdEncoder->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized payload is outside the source buffer.");
		return;
	}
	id<MTLBuffer> serializationBuffer = readAccelerationStructureBytes(cmdEncoder, source,
		static_cast<NSUInteger>(header.serializedSize));
	if (!serializationBuffer) {
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized payload could not be read.");
		return;
	}

	MVKValidatedAccelerationStructureSerialization serialization;
	if (!validateAccelerationStructureSerialization(cmdEncoder->getDevice(),
			serializationBuffer, header, serialization) ||
		!isAccelerationStructureDestinationTypeCompatible(_accelerationStructure,
			serialization.payload)) {
		releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized payload or destination is incompatible.");
		return;
	}

	id<MTLComputeCommandEncoder> computeEncoder = nil;
	MTLAccelerationStructureDescriptor* descriptor =
		serialization.payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR
			? newDeserializedBLASDescriptor(cmdEncoder, serializationBuffer, serialization, computeEncoder)
			: newDeserializedTLASDescriptor(serializationBuffer, serialization);
	if (!descriptor) {
		if (computeEncoder) {
			releaseDeserializationBufferOnCompletion(cmdEncoder, serializationBuffer);
		} else {
			releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		}
		cmdEncoder->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized records are invalid.");
		return;
	}

	MTLAccelerationStructureSizes sizes =
		[cmdEncoder->getMTLDevice() accelerationStructureSizesWithDescriptor:descriptor];
	VkDeviceSize metadataSize = 0;
	if ((serialization.payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR &&
		 !mvkAccelerationStructureSerializationMultiply(serialization.payload.recordCount,
			 sizeof(uint32_t) * 2, metadataSize)) ||
		!sizes.accelerationStructureSize ||
		sizes.accelerationStructureSize != serialization.payload.nativeSize ||
		!sizes.buildScratchBufferSize ||
		sizes.buildScratchBufferSize > std::numeric_limits<NSUInteger>::max()) {
		[descriptor release];
		if (computeEncoder) {
			releaseDeserializationBufferOnCompletion(cmdEncoder, serializationBuffer);
		} else {
			releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		}
		cmdEncoder->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized build sizes are invalid.");
		return;
	}

	const MVKMTLBufferAllocation* scratch = cmdEncoder->getTempMTLBuffer(
		static_cast<NSUInteger>(sizes.buildScratchBufferSize), true);
	id<MTLBuffer> canonicalBuffer =
		[cmdEncoder->getMTLDevice() newBufferWithLength:static_cast<NSUInteger>(header.serializedSize)
													 options:MTLResourceStorageModePrivate];
	if (!canonicalBuffer) {
		[descriptor release];
		if (computeEncoder) {
			releaseDeserializationBufferOnCompletion(cmdEncoder, serializationBuffer);
		} else {
			releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		}
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The canonical buffer could not be allocated.");
		return;
	}

	MVKAccelerationStructureStorageGeneration* generation = nullptr;
	VkResult result = _accelerationStructure->retainFullWriteGeneration(
		sizes.accelerationStructureSize, metadataSize, generation);
	if (result < 0 || !generation) {
		if (generation) { generation->release(); }
		[canonicalBuffer release];
		[descriptor release];
		if (computeEncoder) {
			releaseDeserializationBufferOnCompletion(cmdEncoder, serializationBuffer);
		} else {
			releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		}
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The destination acceleration structure is too small.");
		return;
	}

	if (serialization.payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
		computeEncoder = encodeDeserializedTLASInstances(cmdEncoder, serializationBuffer,
			serialization, generation, (MTLInstanceAccelerationStructureDescriptor*)descriptor);
		if (serialization.payload.recordCount && !computeEncoder) {
			generation->release();
			[canonicalBuffer release];
			[descriptor release];
			releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
			cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
				"vkCmdCopyMemoryToAccelerationStructureKHR(): The instance conversion could not be encoded.");
			return;
		}
	}
	id<MTLFence> fence = computeEncoder ? [cmdEncoder->getMTLDevice() newFence] : nil;
	if (computeEncoder && !fence) {
		[canonicalBuffer release];
		[descriptor release];
		releaseDeserializationResourcesOnCompletion(cmdEncoder, generation, serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The conversion fence could not be allocated.");
		return;
	}
	if (computeEncoder) {
		[computeEncoder updateFence:fence];
		[cmdEncoder->_mtlCmdBuffer addCompletedHandler:^(id<MTLCommandBuffer>) { [fence release]; }];
	}
	if (!_accelerationStructure->publishGeneration(generation)) {
		[canonicalBuffer release];
		[descriptor release];
		if (computeEncoder) {
			releaseDeserializationResourcesOnCompletion(cmdEncoder, generation, serializationBuffer);
		} else {
			generation->release();
			releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		}
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The destination generation could not be published.");
		return;
	}
	cmdEncoder->invalidateAccelerationStructureAddressTable();

	id<MTLAccelerationStructureCommandEncoder> encoder =
		cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseBuildAccelerationStructure);
	if (fence) { [encoder waitForFence:fence]; }
	if (serialization.payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
		cmdEncoder->getDevice()->encodeGPUAddressableAccelerationStructures(cmdEncoder, encoder);
	}
	[encoder buildAccelerationStructure:generation->getMTLAccelerationStructure()
						 descriptor:descriptor
					  scratchBuffer:scratch->_mtlBuffer
				scratchBufferOffset:scratch->_offset];
	generation->publishBuild(sizes.accelerationStructureSize, metadataSize,
		serialization.payload.handleCount);
	generation->publishCanonical(canonicalBuffer, header.serializedSize,
		header.serializedSize, header.handleCount);
	auto canonicalSnapshot = generation->retainCanonicalSnapshot();
	bool canonicalPublished = canonicalSnapshot.canonicalBuffer == canonicalBuffer &&
		canonicalSnapshot.serializationSize == header.serializedSize;
	if (!canonicalPublished) {
		MVKAccelerationStructureStorageGeneration::releaseCanonicalSnapshot(canonicalSnapshot);
		[canonicalBuffer release];
		[descriptor release];
		releaseDeserializationResourcesOnCompletion(cmdEncoder, generation, serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_OUT_OF_HOST_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The canonical buffer could not be published.");
		return;
	}
	releaseCanonicalSnapshotOnCompletion(cmdEncoder, canonicalSnapshot);
	[cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructure)
		copyFromBuffer:serializationBuffer
		sourceOffset:0
		toBuffer:canonicalBuffer
		destinationOffset:0
		size:static_cast<NSUInteger>(header.serializedSize)];
	[canonicalBuffer release];
	[descriptor release];
	releaseDeserializationResourcesOnCompletion(cmdEncoder, generation, serializationBuffer);
}
