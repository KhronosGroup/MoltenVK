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
#include <numeric>

static constexpr VkDeviceSize kMVKAccelerationStructureSerializationAlignment = 256;
static constexpr uint64_t kMVKAccelerationStructureSerializationBLASBlockHeader =
	uint64_t(UINT32_MAX) << 32;

struct MVKSerializedAccelerationStructureHeader {
	uint8_t driverUUID[VK_UUID_SIZE];
	uint8_t compatibilityUUID[VK_UUID_SIZE];
	uint64_t serializedSize;
	uint64_t deserializedSize;
	uint64_t handleCountOrBlockHeader;
};

struct alignas(16) MVKSerializedAccelerationStructurePayloadHeader {
	uint32_t accelerationStructureType;
	uint32_t buildFlags;
	uint64_t recordCount;
	uint64_t dataSize;
};

struct alignas(16) MVKSerializedAccelerationStructureGeometryRecord {
	uint32_t geometryType;
	uint32_t geometryFlags;
	uint32_t primitiveCount;
	uint32_t vertexFormat;
	uint32_t indexType;
	uint32_t maxVertex;
	uint64_t vertexStride;
	uint64_t vertexOffset;
	uint64_t vertexSize;
	uint64_t indexOffset;
	uint64_t indexSize;
	uint64_t transformOffset;
	uint64_t transformSize;
	uint64_t aabbOffset;
	uint64_t aabbSize;
};

struct alignas(16) MVKSerializedAccelerationStructureInstanceRecord {
	float transform[12];
	uint32_t packedData1;
	uint32_t packedData2;
	uint32_t handleSlot;
	uint32_t reserved;
};

static_assert(sizeof(MVKSerializedAccelerationStructureHeader) == 56);
static_assert(sizeof(MVKSerializedAccelerationStructurePayloadHeader) == 32);
static_assert(sizeof(MVKSerializedAccelerationStructureGeometryRecord) == 96);
static_assert(sizeof(MVKSerializedAccelerationStructureInstanceRecord) == 64);
static_assert(offsetof(MVKSerializedAccelerationStructureHeader, handleCountOrBlockHeader) == 48);

static bool mvkAccelerationStructureSerializationAdd(VkDeviceSize a,
													 VkDeviceSize b,
													 VkDeviceSize& result) {
	if (b > std::numeric_limits<VkDeviceSize>::max() - a) { return false; }
	result = a + b;
	return true;
}

static bool mvkAccelerationStructureSerializationMultiply(VkDeviceSize a,
													  VkDeviceSize b,
													  VkDeviceSize& result) {
	if (a && b > std::numeric_limits<VkDeviceSize>::max() / a) { return false; }
	result = a * b;
	return true;
}

static bool mvkAccelerationStructureSerializationAlign(VkDeviceSize value,
											   VkDeviceSize alignment,
											   VkDeviceSize& result) {
	if (!alignment) { return false; }
	VkDeviceSize mask = alignment - 1;
	if ((alignment & mask) || value > std::numeric_limits<VkDeviceSize>::max() - mask) {
		return false;
	}
	result = (value + mask) & ~mask;
	return true;
}

static bool mvkGetAccelerationStructureSerializationHandleCount(
	const MVKSerializedAccelerationStructureHeader& header,
	VkDeviceSize& handleCount,
	bool& isBottomLevel) {
	uint32_t blockCount = static_cast<uint32_t>(header.handleCountOrBlockHeader);
	isBottomLevel = uint32_t(header.handleCountOrBlockHeader >> 32) == UINT32_MAX;
	if (isBottomLevel) {
		if (blockCount) { return false; }
		handleCount = 0;
	} else {
		handleCount = header.handleCountOrBlockHeader;
	}
	return true;
}

static bool mvkGetAccelerationStructureSerializationLayout(
	VkDeviceSize handleCount,
	VkDeviceSize recordCount,
	VkDeviceSize recordStride,
	VkDeviceSize dataSize,
	MVKAccelerationStructureSerializationLayout& layout) {
	VkDeviceSize handleBytes;
	VkDeviceSize offset;
	VkDeviceSize recordBytes;
	if (!mvkAccelerationStructureSerializationMultiply(handleCount, sizeof(VkDeviceAddress), handleBytes) ||
		!mvkAccelerationStructureSerializationAdd(sizeof(MVKSerializedAccelerationStructureHeader), handleBytes, offset) ||
		!mvkAccelerationStructureSerializationAlign(offset, kMVKAccelerationStructureSerializationAlignment, layout.payloadOffset) ||
		!mvkAccelerationStructureSerializationAdd(layout.payloadOffset, sizeof(MVKSerializedAccelerationStructurePayloadHeader), layout.recordTableOffset) ||
		!mvkAccelerationStructureSerializationMultiply(recordCount, recordStride, recordBytes) ||
		!mvkAccelerationStructureSerializationAdd(layout.recordTableOffset, recordBytes, offset) ||
		!mvkAccelerationStructureSerializationAlign(offset, 16, layout.dataOffset) ||
		!mvkAccelerationStructureSerializationAdd(layout.dataOffset, dataSize, offset) ||
		!mvkAccelerationStructureSerializationAlign(offset, kMVKAccelerationStructureSerializationAlignment, layout.serializedSize)) {
		return false;
	}
	return true;
}

NSUInteger MVKAccelerationStructureCanonicalBuild::getHandleArrayOffset() const {
	return sizeof(MVKSerializedAccelerationStructureHeader);
}

struct MVKAccelerationStructureCanonicalCopy {
	id<MTLBuffer> source;
	NSUInteger sourceOffset;
	VkDeviceSize destinationOffset;
	VkDeviceSize size;
};

struct MVKAccelerationStructureCanonicalGatherInfo {
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

static_assert(sizeof(MVKAccelerationStructureCanonicalGatherInfo) == 56);

struct MVKAccelerationStructureCanonicalGather {
	id<MTLBuffer> indices;
	id<MTLBuffer> vertices;
	MVKAccelerationStructureCanonicalGatherInfo info;
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

static bool reserveCanonicalVertexSpan(VkDeviceSize size,
									   VkDeviceSize stride,
									   VkDeviceSize dataOffset,
									   VkDeviceSize& dataSize,
									   VkDeviceSize& offset) {
	if (!size) {
		offset = 0;
		return true;
	}
	if (!stride) { return false; }
	VkDeviceSize gcd = std::gcd<VkDeviceSize>(16, stride);
	VkDeviceSize factor = 16 / gcd;
	if (stride > std::numeric_limits<VkDeviceSize>::max() / factor) { return false; }
	VkDeviceSize alignment = stride * factor;
	VkDeviceSize absoluteOffset;
	if (!mvkAccelerationStructureSerializationAdd(dataOffset, dataSize, absoluteOffset)) {
		return false;
	}
	VkDeviceSize remainder = absoluteOffset % alignment;
	if (remainder && !mvkAccelerationStructureSerializationAdd(
			absoluteOffset, alignment - remainder, absoluteOffset)) {
		return false;
	}
	offset = absoluteOffset - dataOffset;
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

static bool encodeCanonicalGather(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> destination,
	const MVKAccelerationStructureCanonicalGather& gather) {
	id<MTLComputePipelineState> pipeline = cmdEncoder->getCommandEncodingPool()
		->getCmdSerializeAccelerationStructureGatherMTLComputePipelineState();
	if (!pipeline) { return false; }
	id<MTLComputeCommandEncoder> encoder =
		cmdEncoder->getMTLComputeEncoder(kMVKCommandUseBuildAccelerationStructureConvertBuffers);
	[encoder setComputePipelineState:pipeline];
	[encoder setBuffer:gather.indices offset:0 atIndex:0];
	[encoder setBuffer:gather.vertices offset:0 atIndex:1];
	[encoder setBuffer:destination offset:0 atIndex:2];
	cmdEncoder->setComputeBytes(encoder, &gather.info, sizeof(gather.info), 3);
	if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
		[encoder dispatchThreads:MTLSizeMake(gather.info.itemCount, 1, 1)
			threadsPerThreadgroup:MTLSizeMake(pipeline.threadExecutionWidth, 1, 1)];
	} else {
		[encoder dispatchThreadgroups:MTLSizeMake(
				mvkCeilingDivide<NSUInteger>(gather.info.itemCount, pipeline.threadExecutionWidth), 1, 1)
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
	const VkAccelerationStructureBuildRangeInfoKHR* ranges) {
	[_buffer release];
	_buffer = nil;
	_layout = {};
	_handleCount = 0;
	_commandEncoder = nullptr;
	_published = false;

	MVKSmallVector<MVKSerializedAccelerationStructureGeometryRecord, 4> records;
	MVKSmallVector<MVKAccelerationStructureCanonicalCopy, 8> copies;
	MVKSmallVector<MVKAccelerationStructureCanonicalGather, 4> gathers;
	VkDeviceSize dataSize = 0;
	VkDeviceSize recordStride = 0;
	VkDeviceSize recordCount = 0;
	VkDeviceSize canonicalDataOffset = 0;

	if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR) {
		recordStride = sizeof(MVKSerializedAccelerationStructureGeometryRecord);
		recordCount = buildInfo.geometryCount;
		MVKAccelerationStructureSerializationLayout baseLayout;
		if (!mvkGetAccelerationStructureSerializationLayout(0, recordCount,
				recordStride, 0, baseLayout)) {
			return VK_ERROR_OUT_OF_DEVICE_MEMORY;
		}
		canonicalDataOffset = baseLayout.dataOffset;
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
					VkDeviceSize vertexCount;
					VkDeviceSize vertexSourceOffset;
					VkDeviceSize vertexSize;
					if (!mvkAccelerationStructureSerializationMultiply(range.primitiveCount, 3, vertexCount) ||
						!mvkAccelerationStructureSerializationMultiply(range.firstVertex, triangles.vertexStride, vertexSourceOffset) ||
						!mvkAccelerationStructureSerializationAdd(vertexSourceOffset, range.primitiveOffset, vertexSourceOffset) ||
						!mvkAccelerationStructureSerializationMultiply(vertexCount, formatSize, vertexSize)) {
						return VK_ERROR_INITIALIZATION_FAILED;
					}
					record.indexType = VK_INDEX_TYPE_NONE_KHR;
					record.vertexStride = formatSize;
					record.maxVertex = vertexCount ? vertexCount - 1 : 0;
					if (vertexCount) {
						VkDeviceAddress vertexAddress;
						MVKAddressedBufferRange vertexRange;
						VkDeviceSize vertexDestination;
						if (vertexCount > std::numeric_limits<uint32_t>::max() ||
							!mvkAccelerationStructureSerializationAdd(triangles.vertexData.deviceAddress,
								vertexSourceOffset, vertexAddress) ||
							!getAddressedBufferRange(cmdEncoder->getDevice(), vertexAddress,
								formatSize, vertexRange) ||
							!reserveCanonicalVertexSpan(vertexSize, record.vertexStride,
								canonicalDataOffset, dataSize, record.vertexOffset) ||
							!mvkAccelerationStructureSerializationAdd(canonicalDataOffset,
								record.vertexOffset, vertexDestination)) {
							return VK_ERROR_INITIALIZATION_FAILED;
						}
						record.vertexSize = vertexSize;
						VkDeviceSize copyAlignment = cmdEncoder->getMetalFeatures().mtlCopyBufferAlignment;
						bool blitAligned = copyAlignment <= 1 ||
							(!(vertexRange.offset % copyAlignment) &&
							 !(vertexDestination % copyAlignment) &&
							 !(vertexSize % copyAlignment));
						if (triangles.vertexStride == formatSize &&
							vertexSize <= vertexRange.remaining && blitAligned) {
							copies.push_back({vertexRange.buffer, vertexRange.offset,
								record.vertexOffset, vertexSize});
						} else {
							gathers.push_back({vertexRange.buffer, vertexRange.buffer,
								{0,
								 vertexRange.offset,
								 triangles.vertexStride,
								 vertexRange.remaining,
								 record.vertexOffset,
								 static_cast<uint32_t>(vertexCount),
								 0,
								 static_cast<uint32_t>(formatSize),
								 static_cast<uint32_t>(vertexCount - 1)}});
						}
					}
				} else {
					uint64_t indexElementSize = accelerationStructureIndexSize(triangles.indexType);
					VkDeviceSize itemCount;
					VkDeviceSize indexSize;
					VkDeviceSize deindexedVertexSize;
					VkDeviceSize vertexSourceOffset;
					if (!indexElementSize ||
						!mvkAccelerationStructureSerializationMultiply(range.primitiveCount, 3, itemCount) ||
						!mvkAccelerationStructureSerializationMultiply(itemCount, indexElementSize, indexSize) ||
						!mvkAccelerationStructureSerializationMultiply(itemCount, formatSize, deindexedVertexSize) ||
						!mvkAccelerationStructureSerializationMultiply(range.firstVertex, triangles.vertexStride, vertexSourceOffset)) {
						return VK_ERROR_INITIALIZATION_FAILED;
					}
					if (!itemCount) {
						record.indexType = VK_INDEX_TYPE_NONE_KHR;
						record.vertexStride = formatSize;
					} else {
						if (triangles.maxVertex < range.firstVertex) {
							return VK_ERROR_INITIALIZATION_FAILED;
						}
						VkDeviceSize maxRelativeVertex = triangles.maxVertex - range.firstVertex;
						VkDeviceSize indexedVertexSize;
						if (!mvkAccelerationStructureSerializationMultiply(maxRelativeVertex,
								triangles.vertexStride, indexedVertexSize) ||
							!mvkAccelerationStructureSerializationAdd(indexedVertexSize,
								formatSize, indexedVertexSize)) {
							return VK_ERROR_INITIALIZATION_FAILED;
						}
						VkDeviceAddress indexAddress;
						VkDeviceAddress vertexAddress;
						MVKAddressedBufferRange indexRange;
						MVKAddressedBufferRange vertexRange;
						if (!triangles.indexData.deviceAddress ||
							!triangles.vertexData.deviceAddress ||
							!mvkAccelerationStructureSerializationAdd(triangles.indexData.deviceAddress,
								range.primitiveOffset, indexAddress) ||
							!mvkAccelerationStructureSerializationAdd(triangles.vertexData.deviceAddress,
								vertexSourceOffset, vertexAddress) ||
							!getAddressedBufferRange(cmdEncoder->getDevice(), indexAddress, indexSize, indexRange) ||
							!getAddressedBufferRange(cmdEncoder->getDevice(), vertexAddress, formatSize, vertexRange)) {
							return VK_ERROR_INITIALIZATION_FAILED;
						}

						VkDeviceSize deindexedDataSize = dataSize;
						VkDeviceSize deindexedVertexOffset;
						bool deindexedValid = itemCount <= std::numeric_limits<uint32_t>::max() &&
							reserveCanonicalVertexSpan(deindexedVertexSize,
								formatSize, canonicalDataOffset, deindexedDataSize, deindexedVertexOffset);
						VkDeviceSize indexedDataSize = dataSize;
						VkDeviceSize indexOffset;
						VkDeviceSize indexedVertexOffset;
						bool indexedValid = reserveCanonicalSpan(indexSize, indexedDataSize, indexOffset) &&
							reserveCanonicalVertexSpan(indexedVertexSize, triangles.vertexStride,
								canonicalDataOffset, indexedDataSize, indexedVertexOffset);
						VkDeviceSize vertexFirstDataSize = dataSize;
						VkDeviceSize vertexFirstIndexOffset;
						VkDeviceSize vertexFirstVertexOffset;
						bool vertexFirstValid = reserveCanonicalVertexSpan(indexedVertexSize,
							triangles.vertexStride, canonicalDataOffset,
							vertexFirstDataSize, vertexFirstVertexOffset) &&
							reserveCanonicalSpan(indexSize, vertexFirstDataSize, vertexFirstIndexOffset);
						if (vertexFirstValid && (!indexedValid || vertexFirstDataSize < indexedDataSize)) {
							indexedValid = true;
							indexedDataSize = vertexFirstDataSize;
							indexOffset = vertexFirstIndexOffset;
							indexedVertexOffset = vertexFirstVertexOffset;
						}
						VkDeviceSize indexDestination;
						VkDeviceSize vertexDestination;
						indexedValid = indexedValid &&
							mvkAccelerationStructureSerializationAdd(canonicalDataOffset,
								indexOffset, indexDestination) &&
							mvkAccelerationStructureSerializationAdd(canonicalDataOffset,
								indexedVertexOffset, vertexDestination);
						VkDeviceSize copyAlignment = cmdEncoder->getMetalFeatures().mtlCopyBufferAlignment;
						VkDeviceSize indexedCopySize;
						bool blitAligned = indexedValid && (copyAlignment <= 1 ||
							(!(indexRange.offset % copyAlignment) && !(indexDestination % copyAlignment) &&
							 !(indexSize % copyAlignment) && !(vertexRange.offset % copyAlignment) &&
							 !(vertexDestination % copyAlignment) && !(indexedVertexSize % copyAlignment)));
						bool preserveIndices = indexedVertexSize <= vertexRange.remaining &&
							blitAligned &&
							mvkAccelerationStructureSerializationAdd(indexSize,
								indexedVertexSize, indexedCopySize) &&
							indexedCopySize <= deindexedVertexSize &&
							(!deindexedValid || indexedDataSize <= deindexedDataSize);
						if (!preserveIndices && !deindexedValid) {
							return VK_ERROR_OUT_OF_DEVICE_MEMORY;
						}

						if (preserveIndices) {
							dataSize = indexedDataSize;
							record.indexType = triangles.indexType;
							record.vertexStride = triangles.vertexStride;
							record.maxVertex = maxRelativeVertex;
							record.indexOffset = indexOffset;
							record.indexSize = indexSize;
							record.vertexOffset = indexedVertexOffset;
							record.vertexSize = indexedVertexSize;
							if (!addCanonicalCopy(cmdEncoder->getDevice(), triangles.indexData.deviceAddress,
									range.primitiveOffset, record.indexSize, record.indexOffset, copies) ||
								!addCanonicalCopy(cmdEncoder->getDevice(), triangles.vertexData.deviceAddress,
									vertexSourceOffset, record.vertexSize, record.vertexOffset, copies)) {
								return VK_ERROR_INITIALIZATION_FAILED;
							}
						} else {
							dataSize = deindexedDataSize;
							record.indexType = VK_INDEX_TYPE_NONE_KHR;
							record.vertexStride = formatSize;
							record.maxVertex = itemCount - 1;
							record.vertexOffset = deindexedVertexOffset;
							record.vertexSize = deindexedVertexSize;
							gathers.push_back({indexRange.buffer,
								vertexRange.buffer,
								{indexRange.offset,
								 vertexRange.offset,
								 triangles.vertexStride,
								 vertexRange.remaining,
								 record.vertexOffset,
								 static_cast<uint32_t>(itemCount),
								 static_cast<uint32_t>(indexElementSize),
								 static_cast<uint32_t>(formatSize),
								 static_cast<uint32_t>(maxRelativeVertex)}});
						}
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
				record.vertexStride = sizeof(VkAabbPositionsKHR);
				if (range.primitiveCount) {
					VkDeviceAddress aabbAddress;
					MVKAddressedBufferRange aabbRange;
					VkDeviceSize aabbDestination;
					if (!aabbs.stride ||
						!mvkAccelerationStructureSerializationMultiply(range.primitiveCount,
							sizeof(VkAabbPositionsKHR), record.aabbSize) ||
						!mvkAccelerationStructureSerializationAdd(aabbs.data.deviceAddress,
							range.primitiveOffset, aabbAddress) ||
						!getAddressedBufferRange(cmdEncoder->getDevice(), aabbAddress,
							sizeof(VkAabbPositionsKHR), aabbRange) ||
						!reserveCanonicalSpan(record.aabbSize, dataSize, record.aabbOffset) ||
						!mvkAccelerationStructureSerializationAdd(canonicalDataOffset,
							record.aabbOffset, aabbDestination)) {
						return VK_ERROR_INITIALIZATION_FAILED;
					}
					VkDeviceSize copyAlignment = cmdEncoder->getMetalFeatures().mtlCopyBufferAlignment;
					bool blitAligned = copyAlignment <= 1 ||
						(!(aabbRange.offset % copyAlignment) &&
						 !(aabbDestination % copyAlignment) &&
						 !(record.aabbSize % copyAlignment));
					if (aabbs.stride == sizeof(VkAabbPositionsKHR) &&
						record.aabbSize <= aabbRange.remaining && blitAligned) {
						copies.push_back({aabbRange.buffer, aabbRange.offset,
							record.aabbOffset, record.aabbSize});
					} else {
						gathers.push_back({aabbRange.buffer, aabbRange.buffer,
							{0,
							 aabbRange.offset,
							 aabbs.stride,
							 aabbRange.remaining,
							 record.aabbOffset,
							 range.primitiveCount,
							 0,
							 sizeof(VkAabbPositionsKHR),
							 range.primitiveCount - 1}});
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
		(buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR &&
			_layout.dataOffset != canonicalDataOffset) ||
		_layout.serializedSize > std::numeric_limits<NSUInteger>::max() ||
		_layout.serializedSize > cmdEncoder->getMetalFeatures().maxMTLBufferSize) {
		return VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}

	for (auto& record : records) {
		if ((record.vertexSize && !mvkAccelerationStructureSerializationAdd(_layout.dataOffset, record.vertexOffset, record.vertexOffset)) ||
			(record.indexSize && !mvkAccelerationStructureSerializationAdd(_layout.dataOffset, record.indexOffset, record.indexOffset)) ||
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
	for (auto& gather : gathers) {
		if (!mvkAccelerationStructureSerializationAdd(_layout.dataOffset,
				gather.info.destinationOffset, gather.info.destinationOffset)) {
			return VK_ERROR_INITIALIZATION_FAILED;
		}
	}

	MVKSerializedAccelerationStructureHeader header {};
	cmdEncoder->getDevice()->getAccelerationStructureSerializationUUIDs(header.driverUUID,
															 header.compatibilityUUID);
	header.serializedSize = _layout.serializedSize;
	header.deserializedSize = accelerationStructure->getSize();
	header.handleCountOrBlockHeader = buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR
		? kMVKAccelerationStructureSerializationBLASBlockHeader : _handleCount;

	MVKSerializedAccelerationStructurePayloadHeader payload {};
	payload.accelerationStructureType = buildInfo.type;
	payload.buildFlags = buildInfo.flags;
	payload.recordCount = recordCount;
	payload.dataSize = dataSize;

	_buffer = [cmdEncoder->getMTLDevice() newBufferWithLength:static_cast<NSUInteger>(_layout.serializedSize)
												 options:MTLResourceStorageModePrivate];
	if (!_buffer) { return VK_ERROR_OUT_OF_DEVICE_MEMORY; }
	_commandEncoder = cmdEncoder;

	NSUInteger metadataSize = static_cast<NSUInteger>(_layout.dataOffset);
	const MVKMTLBufferAllocation* metadata = cmdEncoder->getTempMTLBuffer(metadataSize);
	uint8_t* metadataContents = metadata
		? static_cast<uint8_t*>(metadata->getContents()) : nullptr;
	if (!metadata || !metadata->_mtlBuffer || !metadataContents) {
		return VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}
	memset(metadataContents, 0, metadataSize);
	memcpy(metadataContents, &header, sizeof(header));
	memcpy(metadataContents + _layout.payloadOffset, &payload, sizeof(payload));
	if (!records.empty()) {
		memcpy(metadataContents + _layout.recordTableOffset,
			   records.data(), records.size() * sizeof(records[0]));
	}
	id<MTLBlitCommandEncoder> encoder =
		cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructure);
	[encoder copyFromBuffer:metadata->_mtlBuffer
		sourceOffset:metadata->_offset
		toBuffer:_buffer
		destinationOffset:0
		size:metadataSize];
	for (const auto& copy : copies) {
		[encoder copyFromBuffer:copy.source
			sourceOffset:copy.sourceOffset
			toBuffer:_buffer
			destinationOffset:static_cast<NSUInteger>(copy.destinationOffset)
			size:static_cast<NSUInteger>(copy.size)];
	}
	for (const auto& gather : gathers) {
		if (!encodeCanonicalGather(cmdEncoder, _buffer, gather)) {
			return VK_ERROR_INITIALIZATION_FAILED;
		}
	}
	return VK_SUCCESS;
}

bool MVKAccelerationStructureCanonicalBuild::publish(
	MVKAccelerationStructureStorageGeneration* generation,
	uint64_t nativeSize,
	uint64_t instanceMetadataSize) {
	if (!_buffer || !generation) { return false; }
	MVKAccelerationStructureCanonicalSnapshot snapshot;
	if (!generation->publishBuild(nativeSize, instanceMetadataSize, _handleCount,
			_buffer, _layout.serializedSize, false, &snapshot)) {
		return false;
	}
	_published = true;
	releaseCanonicalSnapshotOnCompletion(_commandEncoder, snapshot);
	return true;
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
	cmdBuff->recordAccelerationStructureCommand(
		VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_COPY_BIT_KHR |
		VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR);
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
	device->makeResident(buffer);
}

static void untrackAccelerationStructureBuffer(MVKDevice* device, id<MTLBuffer> buffer) {
	device->removeResidency(buffer);
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
	VkDeviceSize handleCount;
	bool isBottomLevel;
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
		mvkGetAccelerationStructureSerializationHandleCount(header, handleCount, isBottomLevel) &&
		mvkAccelerationStructureSerializationMultiply(handleCount,
			sizeof(VkDeviceAddress), handleBytes) &&
		mvkAccelerationStructureSerializationAdd(sizeof(header), handleBytes, minimumSize) &&
		minimumSize <= header.serializedSize;
}

struct MVKValidatedAccelerationStructureSerialization {
	MVKSerializedAccelerationStructureHeader header {};
	MVKSerializedAccelerationStructurePayloadHeader payload {};
	MVKAccelerationStructureSerializationLayout layout {};
	VkDeviceSize handleCount = 0;
	bool isBottomLevel = false;
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
	if (!mvkGetAccelerationStructureSerializationHandleCount(serialization.header,
			serialization.handleCount, serialization.isBottomLevel) ||
		!mvkAccelerationStructureSerializationMultiply(serialization.handleCount,
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
		if (!serialization.isBottomLevel) { return false; }
	} else if (payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
		expectedStride = sizeof(MVKSerializedAccelerationStructureInstanceRecord);
		if (serialization.isBottomLevel || payload.recordCount != serialization.handleCount ||
			serialization.handleCount > std::numeric_limits<uint32_t>::max() ||
			payload.dataSize) {
			return false;
		}
	} else {
		return false;
	}
	if (!mvkGetAccelerationStructureSerializationLayout(serialization.handleCount,
			payload.recordCount, expectedStride, payload.dataSize, serialization.layout) ||
		serialization.layout.payloadOffset != payloadOffset ||
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

static MTLAccelerationStructureDescriptor* newDeserializedBLASDescriptor(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> serializationBuffer,
	const MVKValidatedAccelerationStructureSerialization& serialization) {
	NSMutableArray* geometries = [NSMutableArray new];
	for (uint64_t index = 0; index < serialization.payload.recordCount; index++) {
		MVKSerializedAccelerationStructureGeometryRecord record;
		VkDeviceSize recordOffset;
		if (!mvkAccelerationStructureSerializationMultiply(index,
				sizeof(record), recordOffset) ||
			!mvkAccelerationStructureSerializationAdd(serialization.layout.recordTableOffset,
				recordOffset, recordOffset) ||
			!readAccelerationStructureSerializationValue(serializationBuffer, recordOffset, record) ||
			record.vertexStride > std::numeric_limits<NSUInteger>::max()) {
			[geometries release];
			return nil;
		}

		if (record.geometryType == VK_GEOMETRY_TYPE_TRIANGLES_KHR) {
			uint64_t formatSize = mvkVkFormatBytesPerBlock(static_cast<VkFormat>(record.vertexFormat));
			uint64_t vertexCount = 0;
			uint64_t expectedVertexSize = 0;
			uint64_t expectedIndexSize = 0;
			VkIndexType indexType = static_cast<VkIndexType>(record.indexType);
			uint64_t indexElementSize = accelerationStructureIndexSize(indexType);
			bool indexed = indexElementSize != 0;
			if (!formatSize ||
				mvkMTLAccelerationStructureVertexFormatFromVkFormat(static_cast<VkFormat>(record.vertexFormat)) == MTLAttributeFormatInvalid ||
				(!indexed && indexType != VK_INDEX_TYPE_NONE_KHR) ||
				record.aabbOffset || record.aabbSize ||
				(record.primitiveCount && !record.vertexStride) ||
				!mvkAccelerationStructureSerializationMultiply(record.primitiveCount, 3, vertexCount)) {
				[geometries release];
				return nil;
			}
			if (vertexCount) {
				uint64_t lastVertex = indexed ? record.maxVertex : vertexCount - 1;
				if ((!indexed && record.maxVertex != lastVertex) ||
					!mvkAccelerationStructureSerializationMultiply(lastVertex,
						record.vertexStride, expectedVertexSize) ||
					!mvkAccelerationStructureSerializationAdd(expectedVertexSize,
						formatSize, expectedVertexSize) ||
					(indexed && !mvkAccelerationStructureSerializationMultiply(vertexCount,
						indexElementSize, expectedIndexSize))) {
					[geometries release];
					return nil;
				}
			} else if (indexed || record.maxVertex) {
				[geometries release];
				return nil;
			}
			if (record.vertexSize != expectedVertexSize ||
				record.indexSize != expectedIndexSize ||
				!validateAccelerationStructureSerializationSpan(serialization,
					record.vertexOffset, record.vertexSize) ||
				!validateAccelerationStructureSerializationSpan(serialization,
					record.indexOffset, record.indexSize) ||
				!validateAccelerationStructureSerializationSpan(serialization,
					record.transformOffset, record.transformSize) ||
				(record.transformSize && record.transformSize != sizeof(VkTransformMatrixKHR)) ||
				record.vertexOffset > std::numeric_limits<NSUInteger>::max() ||
				record.indexOffset > std::numeric_limits<NSUInteger>::max() ||
				(record.vertexSize && record.vertexOffset % 16) ||
				(record.indexSize && record.indexOffset % 16) ||
				(record.vertexSize && record.vertexOffset % record.vertexStride) ||
				(indexed && record.indexOffset % indexElementSize) ||
				(record.transformSize && record.transformOffset % 16)) {
				[geometries release];
				return nil;
			}

			MTLAccelerationStructureTriangleGeometryDescriptor* geometry =
				[MTLAccelerationStructureTriangleGeometryDescriptor new];
			geometry.triangleCount = static_cast<NSUInteger>(record.primitiveCount);
			geometry.vertexStride = static_cast<NSUInteger>(record.vertexStride);
			geometry.vertexFormat = mvkMTLAccelerationStructureVertexFormatFromVkFormat(
				static_cast<VkFormat>(record.vertexFormat));
			geometry.intersectionFunctionTableOffset = static_cast<NSUInteger>(index);
			geometry.vertexBuffer = serializationBuffer;
			if (record.vertexSize) {
				geometry.vertexBufferOffset = static_cast<NSUInteger>(record.vertexOffset);
			}
			if (indexed) {
				geometry.indexBuffer = serializationBuffer;
				geometry.indexBufferOffset = static_cast<NSUInteger>(record.indexOffset);
				geometry.indexType = mvkMTLIndexTypeFromVkIndexType(indexType);
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
				if (!allocation || !allocation->_mtlBuffer || !allocation->getContents()) {
					[geometry release];
					[geometries release];
					cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
						"Acceleration-structure transform storage could not be allocated.");
					return nil;
				}
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
			geometry.intersectionFunctionTableOffset = static_cast<NSUInteger>(index);
			geometry.boundingBoxBuffer = serializationBuffer;
			if (record.aabbSize) {
				geometry.boundingBoxBufferOffset = static_cast<NSUInteger>(record.aabbOffset);
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
		MTLAccelerationStructureTriangleGeometryDescriptor* geometry =
			[MTLAccelerationStructureTriangleGeometryDescriptor new];
		geometry.vertexBuffer = serializationBuffer;
		geometry.vertexStride = sizeof(float) * 3;
		[geometries addObject:geometry];
		[geometry release];
	}
	MTLPrimitiveAccelerationStructureDescriptor* descriptor =
		[MTLPrimitiveAccelerationStructureDescriptor new];
	descriptor.geometryDescriptors = geometries;
	[geometries release];
	MVKAccelerationStructure::applyMTLUsage(descriptor,
		static_cast<VkBuildAccelerationStructureFlagsKHR>(serialization.payload.buildFlags));
	return descriptor;
}

static MTLAccelerationStructureDescriptor* newDeserializedTLASDescriptor(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> serializationBuffer,
	const MVKValidatedAccelerationStructureSerialization& serialization) {
	for (uint64_t index = 0; index < serialization.payload.recordCount; index++) {
		MVKSerializedAccelerationStructureInstanceRecord record;
		VkDeviceSize recordOffset;
		if (!mvkAccelerationStructureSerializationMultiply(index,
				sizeof(record), recordOffset) ||
			!mvkAccelerationStructureSerializationAdd(serialization.layout.recordTableOffset,
				recordOffset, recordOffset) ||
			!readAccelerationStructureSerializationValue(serializationBuffer, recordOffset, record) ||
			record.handleSlot >= serialization.handleCount || record.reserved) {
			return nil;
		}
	}
	MTLInstanceAccelerationStructureDescriptor* descriptor =
		[MTLInstanceAccelerationStructureDescriptor new];
	descriptor.instanceDescriptorType =
		cmdEncoder->getDevice()->getAccelerationStructureInstanceDescriptorType();
	descriptor.instanceCount = static_cast<NSUInteger>(serialization.payload.recordCount);
	MVKAccelerationStructure::applyMTLUsage(descriptor,
		static_cast<VkBuildAccelerationStructureFlagsKHR>(serialization.payload.buildFlags));
	return descriptor;
}

static id<MTLComputeCommandEncoder> encodeDeserializedTLASInstances(
	MVKCommandEncoder* cmdEncoder,
	id<MTLBuffer> serializationBuffer,
	const MVKValidatedAccelerationStructureSerialization& serialization,
	MTLInstanceAccelerationStructureDescriptor* descriptor,
	id<MTLBuffer> instanceMetadata) {
	uint32_t itemCount = static_cast<uint32_t>(serialization.payload.recordCount);
	if (!itemCount) { return nil; }
	MVKDevice* device = cmdEncoder->getDevice();
	NSUInteger descriptorSize = device->getAccelerationStructureInstanceDescriptorSize();
	VkDeviceSize descriptorBytes;
	if (!mvkAccelerationStructureSerializationMultiply(itemCount,
			descriptorSize, descriptorBytes) ||
		descriptorBytes > std::numeric_limits<NSUInteger>::max()) {
		return nil;
	}
	const MVKMTLBufferAllocation* instances =
		cmdEncoder->getTempMTLBuffer(static_cast<NSUInteger>(descriptorBytes), true);
	if (!instances || !instances->_mtlBuffer) { return nil; }
	descriptor.instanceDescriptorBuffer = instances->_mtlBuffer;
	descriptor.instanceDescriptorBufferOffset = instances->_offset;
	descriptor.instanceDescriptorStride = descriptorSize;

	id<MTLComputeCommandEncoder> encoder =
		mvkEncodeAccelerationStructureConversion(cmdEncoder,
			serializationBuffer, static_cast<NSUInteger>(serialization.layout.recordTableOffset),
			instances->_mtlBuffer, instances->_offset,
			sizeof(MVKSerializedAccelerationStructureInstanceRecord), itemCount,
		kMVKAccelerationStructureDeserializeInstances,
		serializationBuffer, static_cast<NSUInteger>(serialization.layout.recordTableOffset),
		sizeof(MVKSerializedAccelerationStructureHeader), instanceMetadata);
	if (!encoder) { return nil; }
	if (!device->usesIndirectAccelerationStructureInstanceDescriptors()) {
		const auto& accelerationStructures = cmdEncoder->getAccelerationStructureInstances();
		descriptor.instancedAccelerationStructures =
			[NSArray arrayWithObjects:accelerationStructures.data()
						   count:accelerationStructures.size()];
	}
	return encoder;
}

static void releaseDeserializationResourcesOnCompletion(
	MVKCommandEncoder* cmdEncoder,
	MVKAccelerationStructureStorageGeneration* generation,
	id<MTLBuffer> serializationBuffer,
	bool canonicalOwnsResidency = false) {
	MVKDevice* device = cmdEncoder->getDevice();
	[cmdEncoder->_mtlCmdBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
		generation->release();
		if (canonicalOwnsResidency) { [serializationBuffer release]; }
		else { releaseAccelerationStructureBuffer(device, serializationBuffer); }
	}];
}

VkResult MVKCmdCopyMemoryToAccelerationStructure::setContent(
	MVKCommandBuffer* cmdBuff,
	VkDeviceAddress source,
	MVKAccelerationStructure* accelerationStructure,
	VkCopyAccelerationStructureModeKHR mode) {
	cmdBuff->recordAccelerationStructureCommand(
		VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_COPY_BIT_KHR |
		VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR);
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
			? newDeserializedBLASDescriptor(cmdEncoder, serializationBuffer, serialization)
			: newDeserializedTLASDescriptor(cmdEncoder, serializationBuffer, serialization);
	if (!descriptor) {
		releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized records are invalid.");
		return;
	}

	MTLAccelerationStructureSizes sizes =
		[cmdEncoder->getMTLDevice() accelerationStructureSizesWithDescriptor:descriptor];
	if (!sizes.accelerationStructureSize ||
		!sizes.buildScratchBufferSize ||
		sizes.buildScratchBufferSize > std::numeric_limits<NSUInteger>::max()) {
		[descriptor release];
		releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The serialized build sizes are invalid.");
		return;
	}

	const MVKMTLBufferAllocation* scratch = cmdEncoder->getTempMTLBuffer(
		static_cast<NSUInteger>(sizes.buildScratchBufferSize), true);
	if (!scratch || !scratch->_mtlBuffer) {
		[descriptor release];
		releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The build scratch buffer could not be allocated.");
		return;
	}

	MVKAccelerationStructureStorageGeneration* generation = nullptr;
	uint64_t instanceMetadataSize =
		serialization.payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR
			? serialization.payload.recordCount * sizeof(uint32_t)
			: 0;
	VkResult result = _accelerationStructure->retainFullWriteGeneration(
		sizes.accelerationStructureSize, instanceMetadataSize, generation);
	if (result < 0 || !generation) {
		if (generation) { generation->release(); }
		[descriptor release];
		releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The destination acceleration structure is too small.");
		return;
	}
	if (!generation->setInstanceMetadataSize(instanceMetadataSize)) {
		generation->release();
		[descriptor release];
		releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The destination instance metadata is too large.");
		return;
	}

	if (serialization.payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
		computeEncoder = encodeDeserializedTLASInstances(cmdEncoder, serializationBuffer,
			serialization, (MTLInstanceAccelerationStructureDescriptor*)descriptor,
			generation->getInstanceMetadataMTLBuffer());
		if (serialization.payload.recordCount && !computeEncoder) {
			generation->release();
			[descriptor release];
			releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
			cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
				"vkCmdCopyMemoryToAccelerationStructureKHR(): The instance conversion could not be encoded.");
			return;
		}
	}
	if (!mvkEncodeAccelerationStructureReferenceUpdate(
			cmdEncoder, _accelerationStructure, generation)) {
		generation->release();
		[descriptor release];
		releaseAccelerationStructureBuffer(cmdEncoder->getDevice(), serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The stable acceleration-structure reference could not be updated.");
		return;
	}
	auto* previousGeneration = _accelerationStructure->retainCurrentGeneration();
	if (previousGeneration == generation && previousGeneration) {
		previousGeneration->release();
		previousGeneration = nullptr;
	}
	id<MTLAccelerationStructureCommandEncoder> encoder =
		cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseBuildAccelerationStructure);
	if (serialization.payload.accelerationStructureType == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
		cmdEncoder->getDevice()->encodeGPUAddressableAccelerationStructures(cmdEncoder, encoder);
	}
	MVKAccelerationStructureCanonicalSnapshot canonicalSnapshot;
	bool canonicalOwnsResidency = generation->publishBuild(
		sizes.accelerationStructureSize, instanceMetadataSize, serialization.handleCount,
		serializationBuffer, header.serializedSize, true, &canonicalSnapshot);
	if (!canonicalOwnsResidency) {
		if (previousGeneration) { previousGeneration->release(); }
		[descriptor release];
		releaseDeserializationResourcesOnCompletion(cmdEncoder, generation, serializationBuffer);
		cmdEncoder->reportError(VK_ERROR_OUT_OF_HOST_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The canonical buffer could not be published.");
		return;
	}
	if (!_accelerationStructure->publishGeneration(generation)) {
		MVKAccelerationStructureStorageGeneration::releaseCanonicalSnapshot(canonicalSnapshot);
		if (previousGeneration) { previousGeneration->release(); }
		[descriptor release];
		releaseDeserializationResourcesOnCompletion(cmdEncoder, generation,
			serializationBuffer, true);
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"vkCmdCopyMemoryToAccelerationStructureKHR(): The destination generation could not be published.");
		return;
	}
	cmdEncoder->retainAccelerationStructureGeneration(previousGeneration);
	cmdEncoder->invalidateAccelerationStructureAddressTable();
	cmdEncoder->invalidateAccelerationStructureReferenceTable();
	[encoder buildAccelerationStructure:generation->getMTLAccelerationStructure()
						 descriptor:descriptor
					  scratchBuffer:scratch->_mtlBuffer
				 scratchBufferOffset:scratch->_offset];
	releaseCanonicalSnapshotOnCompletion(cmdEncoder, canonicalSnapshot);
	[descriptor release];
	releaseDeserializationResourcesOnCompletion(cmdEncoder, generation,
		serializationBuffer, true);
}
