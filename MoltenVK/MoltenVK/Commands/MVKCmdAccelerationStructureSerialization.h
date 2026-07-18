/*
 * MVKCmdAccelerationStructureSerialization.h
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

#include "MVKCommand.h"
#include "MVKAccelerationStructureSerialization.h"

class MVKAccelerationStructure;
class MVKAccelerationStructureStorageGeneration;
class MVKCommandBuffer;
class MVKCommandEncoder;

enum MVKAccelerationStructurePositionFormat : uint32_t {
	kMVKAccelerationStructurePositionFormatR32G32,
	kMVKAccelerationStructurePositionFormatR32G32B32,
	kMVKAccelerationStructurePositionFormatR16G16Float,
	kMVKAccelerationStructurePositionFormatR16G16B16A16Float,
	kMVKAccelerationStructurePositionFormatR16G16Snorm,
	kMVKAccelerationStructurePositionFormatR16G16B16A16Snorm,
};

struct MVKAccelerationStructureTrianglePositionsInfo {
	uint64_t vertexAvailable;
	uint64_t indexAvailable;
	uint32_t vertexStride;
	uint32_t vertexFormat;
	uint32_t indexElementSize;
	uint32_t vertexElementSize;
	uint32_t maxVertex;
	uint32_t primitiveCount;
	uint32_t hasTransform;
	uint32_t reserved;
};

static_assert(sizeof(MVKAccelerationStructureTrianglePositionsInfo) == 48);

static inline bool mvkGetAccelerationStructurePositionFormat(
	VkFormat format,
	uint32_t& positionFormat,
	uint32_t& elementSize) {
	switch (format) {
		case VK_FORMAT_R32G32_SFLOAT:
			positionFormat = kMVKAccelerationStructurePositionFormatR32G32;
			elementSize = 2 * sizeof(float);
			return true;
		case VK_FORMAT_R32G32B32_SFLOAT:
			positionFormat = kMVKAccelerationStructurePositionFormatR32G32B32;
			elementSize = 3 * sizeof(float);
			return true;
		case VK_FORMAT_R16G16_SFLOAT:
			positionFormat = kMVKAccelerationStructurePositionFormatR16G16Float;
			elementSize = 2 * sizeof(uint16_t);
			return true;
		case VK_FORMAT_R16G16B16A16_SFLOAT:
			positionFormat = kMVKAccelerationStructurePositionFormatR16G16B16A16Float;
			elementSize = 4 * sizeof(uint16_t);
			return true;
		case VK_FORMAT_R16G16_SNORM:
			positionFormat = kMVKAccelerationStructurePositionFormatR16G16Snorm;
			elementSize = 2 * sizeof(int16_t);
			return true;
		case VK_FORMAT_R16G16B16A16_SNORM:
			positionFormat = kMVKAccelerationStructurePositionFormatR16G16B16A16Snorm;
			elementSize = 4 * sizeof(int16_t);
			return true;
		default:
			return false;
	}
}

class MVKAccelerationStructureCanonicalBuild {

public:
	~MVKAccelerationStructureCanonicalBuild();

	VkResult prepareAndEncode(MVKCommandEncoder* cmdEncoder,
							  MVKAccelerationStructure* accelerationStructure,
							  const VkAccelerationStructureBuildGeometryInfoKHR& buildInfo,
							  const VkAccelerationStructureBuildRangeInfoKHR* ranges,
							  uint64_t nativeSize);

	id<MTLBuffer> getMTLBuffer() const { return _buffer; }
	NSUInteger getRecordTableOffset() const { return static_cast<NSUInteger>(_layout.recordTableOffset); }
	NSUInteger getHandleArrayOffset() const { return sizeof(MVKSerializedAccelerationStructureHeader); }
	bool publish(MVKAccelerationStructureStorageGeneration* generation);

protected:
	id<MTLBuffer> _buffer = nil;
	MVKAccelerationStructureSerializationLayout _layout {};
	uint64_t _handleCount = 0;
	MVKCommandEncoder* _commandEncoder = nullptr;
	bool _published = false;
};

class MVKCmdCopyAccelerationStructureToMemory : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						MVKAccelerationStructure* accelerationStructure,
						VkDeviceAddress destination,
						VkCopyAccelerationStructureModeKHR mode);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKAccelerationStructure* _accelerationStructure = nullptr;
	VkDeviceAddress _destination = 0;
};

class MVKCmdCopyMemoryToAccelerationStructure : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkDeviceAddress source,
						MVKAccelerationStructure* accelerationStructure,
						VkCopyAccelerationStructureModeKHR mode);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkDeviceAddress _source = 0;
	MVKAccelerationStructure* _accelerationStructure = nullptr;
};
