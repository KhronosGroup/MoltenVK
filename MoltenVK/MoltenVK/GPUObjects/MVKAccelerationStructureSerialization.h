/*
 * MVKAccelerationStructureSerialization.h
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

#pragma once

#include "vulkan/vulkan.h"

#include <cstddef>
#include <cstdint>
#include <limits>

static constexpr uint64_t kMVKAccelerationStructureSerializationMagic = 0x31303053414b564dull;
static constexpr uint32_t kMVKAccelerationStructureSerializationSchema = 1;
static constexpr uint32_t kMVKAccelerationStructureSerializationEndian = 0x01020304;
static constexpr VkDeviceSize kMVKAccelerationStructureSerializationAlignment = 256;

struct MVKSerializedAccelerationStructureHeader {
	uint8_t driverUUID[VK_UUID_SIZE];
	uint8_t compatibilityUUID[VK_UUID_SIZE];
	uint64_t serializedSize;
	uint64_t deserializedSize;
	uint64_t handleCount;
};

struct alignas(16) MVKSerializedAccelerationStructurePayloadHeader {
	uint64_t magic;
	uint32_t schema;
	uint32_t endian;
	uint32_t headerSize;
	uint32_t accelerationStructureType;
	uint64_t buildFlags;
	uint64_t createFlags;
	uint64_t recordCount;
	uint64_t recordStride;
	uint64_t recordTableOffset;
	uint64_t recordTableSize;
	uint64_t dataOffset;
	uint64_t dataSize;
	uint64_t nativeSize;
	uint64_t deserializedSize;
	uint64_t handleCount;
	uint64_t reserved[2];
};

struct alignas(16) MVKSerializedAccelerationStructureGeometryRecord {
	uint32_t geometryType;
	uint32_t geometryFlags;
	uint64_t primitiveCount;
	uint32_t vertexFormat;
	uint32_t indexType;
	uint64_t vertexStride;
	uint64_t maxVertex;
	uint64_t vertexOffset;
	uint64_t vertexSize;
	uint64_t indexOffset;
	uint64_t indexSize;
	uint64_t transformOffset;
	uint64_t transformSize;
	uint64_t aabbOffset;
	uint64_t aabbSize;
	uint64_t reserved[3];
};

struct alignas(16) MVKSerializedAccelerationStructureInstanceRecord {
	float transform[12];
	uint32_t packedData1;
	uint32_t packedData2;
	uint32_t handleSlot;
	uint32_t reserved;
};

static_assert(sizeof(MVKSerializedAccelerationStructureHeader) == 56);
static_assert(sizeof(MVKSerializedAccelerationStructurePayloadHeader) == 128);
static_assert(sizeof(MVKSerializedAccelerationStructureGeometryRecord) == 128);
static_assert(sizeof(MVKSerializedAccelerationStructureInstanceRecord) == 64);
static_assert(offsetof(MVKSerializedAccelerationStructureHeader, handleCount) == 48);

struct MVKAccelerationStructureSerializationLayout {
	VkDeviceSize payloadOffset;
	VkDeviceSize recordTableOffset;
	VkDeviceSize dataOffset;
	VkDeviceSize serializedSize;
};

static inline bool mvkAccelerationStructureSerializationAdd(VkDeviceSize a,
														  VkDeviceSize b,
														  VkDeviceSize& result) {
	if (b > std::numeric_limits<VkDeviceSize>::max() - a) { return false; }
	result = a + b;
	return true;
}

static inline bool mvkAccelerationStructureSerializationMultiply(VkDeviceSize a,
															   VkDeviceSize b,
															   VkDeviceSize& result) {
	if (a && b > std::numeric_limits<VkDeviceSize>::max() / a) { return false; }
	result = a * b;
	return true;
}

static inline bool mvkAccelerationStructureSerializationAlign(VkDeviceSize value,
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

static inline bool mvkGetAccelerationStructureSerializationLayout(
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
