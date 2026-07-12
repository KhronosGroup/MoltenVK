/*
 * MVKAccelerationStructure.h
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

#include "MVKDevice.h"
#include "MVKSmallVector.h"

#include <atomic>
#include <mutex>

#import <Metal/MTLAccelerationStructure.h>
#import <Metal/MTLAccelerationStructureTypes.h>

#pragma mark -
#pragma mark MVKAccelerationStructure

class MVKDeviceMemory;
class MVKAccelerationStructureStorage;
class MVKAccelerationStructureCanonicalStorage;

struct MVKAccelerationStructureCanonicalSnapshot {
	MVKAccelerationStructureCanonicalStorage* storage = nullptr;
	id<MTLBuffer> canonicalBuffer = nil;
	uint64_t canonicalSize = 0;
	uint64_t serializationSize = 0;
};

class MVKAccelerationStructureStorageGeneration {

public:
	void retain();
	void release();

	id<MTLAccelerationStructure> getMTLAccelerationStructure() const { return _accelerationStructure; }
	id<MTLBuffer> getInstanceMetadataMTLBuffer() const { return _instanceMetadataBuffer; }
	id<MTLBuffer> getReferenceMTLBuffer() const { return _referenceBuffer; }
	uint64_t getReferenceGPUAddress() const { return _referenceBuffer.gpuAddress; }
	uint64_t getNativeCapacity() const { return _nativeCapacity; }
	uint64_t getMetadataCapacity() const { return _metadataCapacity; }

	uint64_t getNativeSize();
	uint64_t getInstanceMetadataSize();
	uint64_t getSerializationSize();
	uint64_t getHandleCount();
	MVKAccelerationStructureCanonicalSnapshot retainCanonicalSnapshot();
	static void releaseCanonicalSnapshot(MVKAccelerationStructureCanonicalSnapshot& snapshot);
	bool isCompatibleWith(uint64_t nativeCapacity, uint64_t metadataCapacity);

	bool setInstanceMetadataSize(uint64_t size);
	void publishBuild(uint64_t nativeSize,
					  uint64_t instanceMetadataSize,
					  uint64_t handleCount);
	void publishCanonical(id<MTLBuffer> canonicalBuffer,
					  uint64_t canonicalSize,
					  uint64_t serializationSize,
					  uint64_t handleCount);
	void copyContentFrom(MVKAccelerationStructureStorageGeneration* source,
						 uint64_t nativeSizeLimit = UINT64_MAX);

protected:
	friend class MVKAccelerationStructureStorage;

	MVKAccelerationStructureStorageGeneration(MVKDevice* device,
										  id<MTLHeap> heap,
										  id<MTLAccelerationStructure> accelerationStructure,
										  id<MTLBuffer> instanceMetadataBuffer,
										  id<MTLBuffer> referenceBuffer,
										  uint64_t nativeCapacity,
										  uint64_t metadataCapacity);
	~MVKAccelerationStructureStorageGeneration();

	MVKDevice* _device;
	id<MTLHeap> _heap;
	id<MTLAccelerationStructure> _accelerationStructure;
	id<MTLBuffer> _instanceMetadataBuffer;
	id<MTLBuffer> _referenceBuffer;
	id<MTLBuffer> _canonicalBuffer = nil;
	MVKAccelerationStructureCanonicalStorage* _canonicalStorage = nullptr;
	std::atomic<uint32_t> _refCount { 1 };
	std::mutex _stateLock;
	uint64_t _nativeCapacity;
	uint64_t _metadataCapacity;
	uint64_t _nativeSize = 0;
	uint64_t _instanceMetadataSize = 0;
	uint64_t _canonicalSize = 0;
	uint64_t _serializationSize = 0;
	uint64_t _handleCount = 0;
};

class MVKAccelerationStructureStorage {

public:
	bool matches(VkDeviceSize physicalStart,
				 VkDeviceAddress requestedDeviceAddress,
				 VkAccelerationStructureCreateFlagsKHR createFlags,
				 VkAccelerationStructureTypeKHR type) const;
	MVKAccelerationStructureStorageGeneration* retainCurrentGeneration();
	MVKAccelerationStructureStorageGeneration* retainInitialGeneration(uint64_t nativeCapacity,
																 uint64_t metadataCapacity);
	VkResult retainFullWriteGeneration(uint64_t nativeCapacity,
									 uint64_t requiredNativeSize,
									 uint64_t metadataCapacity,
									 uint64_t requiredMetadataSize,
									 MVKAccelerationStructureStorageGeneration*& generation);
	bool publishGeneration(MVKAccelerationStructureStorageGeneration* generation);

protected:
	friend class MVKDeviceMemory;

	MVKAccelerationStructureStorage(MVKDevice* device,
									id<MTLHeap> heap,
									bool usesPlacement,
									VkDeviceSize physicalStart,
									VkDeviceAddress requestedDeviceAddress,
									VkAccelerationStructureCreateFlagsKHR createFlags,
									VkAccelerationStructureTypeKHR type,
									VkDeviceSize placementOffset);
	~MVKAccelerationStructureStorage();
	MVKAccelerationStructureStorageGeneration* newGeneration(uint64_t nativeCapacity,
																uint64_t metadataCapacity);

	MVKDevice* _device;
	id<MTLHeap> _heap;
	bool _usesPlacement;
	VkDeviceSize _physicalStart;
	VkDeviceAddress _requestedDeviceAddress;
	VkAccelerationStructureCreateFlagsKHR _createFlags;
	VkAccelerationStructureTypeKHR _type;
	VkDeviceSize _placementOffset;
	uint32_t _memberCount = 0;
	std::mutex _lock;
	MVKSmallVector<MVKAccelerationStructureStorageGeneration*, 2> _generations;
	MVKAccelerationStructureStorageGeneration* _currentGeneration = nullptr;
};

class MVKAccelerationStructure : public MVKVulkanAPIDeviceObject {

public:
    VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_ACCELERATION_STRUCTURE_KHR; }

    VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override {
        return VK_DEBUG_REPORT_OBJECT_TYPE_ACCELERATION_STRUCTURE_KHR_EXT;
    }

    MTLAccelerationStructureDescriptor* newMTLAccelerationStructureDescriptor(const VkAccelerationStructureBuildGeometryInfoKHR& buildInfo,
                                                                              const VkAccelerationStructureBuildRangeInfoKHR* rangeInfos,
                                                                              const uint32_t* maxPrimitiveCounts);

    VkAccelerationStructureBuildSizesInfoKHR getBuildSizes(VkAccelerationStructureBuildTypeKHR buildType,
                                                           const VkAccelerationStructureBuildGeometryInfoKHR* buildInfo,
                                                           const uint32_t* maxPrimitiveCounts);

    uint64_t getDeviceAddress();

	uint64_t getSize() const { return _size; }

	uint64_t getNativeCapacity();

	VkAccelerationStructureTypeKHR getAccelerationStructureType() const { return _type; }

	VkAccelerationStructureCreateFlagsKHR getCreateFlags() const { return _createFlags; }
	MVKAccelerationStructureStorageGeneration* retainCurrentGeneration();

	VkResult retainFullWriteGeneration(uint64_t requiredNativeSize,
									 uint64_t requiredMetadataSize,
									 MVKAccelerationStructureStorageGeneration*& generation);

	bool publishGeneration(MVKAccelerationStructureStorageGeneration* generation);

	static VkDeviceSize getMTLPlacementAlignment(MVKDevice* device);

    MVKAccelerationStructure(MVKDevice* device);

    MVKAccelerationStructure(MVKDevice* device, const VkAccelerationStructureCreateInfoKHR* pCreateInfo);

    ~MVKAccelerationStructure() override;

	void destroy() override;

protected:
    friend class MVKDevice;
	friend class MVKBuffer;

    void propagateDebugName() override {}
	VkResult materialize(bool& materialized);
	void bufferMemoryBindingFailed();
	void releaseMetalResources();
	void detachBackingBuffer();
	VkResult getMaximumMetalSize(MVKBuffer* backingBuffer,
							 MVKDeviceMemory* memory,
							 VkDeviceSize bufferMemoryOffset,
							 VkDeviceSize& physicalStart,
							 VkDeviceSize& placementOffset,
							 VkDeviceSize& metalSize);

	MVKBuffer* _backingBuffer = nullptr;
	MVKDeviceMemory* _storageMemory = nullptr;
	MVKAccelerationStructureStorage* _storage = nullptr;

    uint64_t _address = 0;
    uint64_t _size = 0;
	VkDeviceSize _bufferOffset = 0;
	VkDeviceAddress _requestedDeviceAddress = 0;
	VkDeviceSize _nativeCapacity = 0;
	VkDeviceSize _metadataCapacity = 0;
	VkAccelerationStructureTypeKHR _type = VK_ACCELERATION_STRUCTURE_TYPE_GENERIC_KHR;
	VkAccelerationStructureCreateFlagsKHR _createFlags = 0;
	std::mutex _lock;
	std::atomic<bool> _isMaterialized { false };
	bool _isGPUAddressableRegistered = false;
	bool _isBufferBound = false;
	bool _isDestroyed = false;
};
