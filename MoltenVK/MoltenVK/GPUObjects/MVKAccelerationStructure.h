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
	NSUInteger getCompactedSizeOffset() const { return _referenceBuffer.length - sizeof(uint64_t); }
	void relinquishReferenceResidency() { _ownsReferenceResidency = false; }
	uint64_t getNativeCapacity() const { return _nativeCapacity; }
	uint64_t getMetadataCapacity() const { return _metadataCapacity; }

	uint64_t getNativeSize();
	bool isCompacted();
	uint64_t getInstanceMetadataSize();
	uint64_t getSerializationSize();
	uint64_t getHandleCount();
	MVKAccelerationStructureCanonicalSnapshot retainCanonicalSnapshot();
	static void releaseCanonicalSnapshot(MVKAccelerationStructureCanonicalSnapshot& snapshot);
	bool setInstanceMetadataSize(uint64_t size);
	bool publishBuild(uint64_t nativeSize,
					 uint64_t instanceMetadataSize,
						 uint64_t handleCount,
						 id<MTLBuffer> canonicalBuffer,
						 uint64_t serializationSize,
						 bool adoptsCanonicalResidency = false,
						 MVKAccelerationStructureCanonicalSnapshot* publishedSnapshot = nullptr);
	void copyContentFrom(MVKAccelerationStructureStorageGeneration* source,
						 bool compacted = false);

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
	bool _ownsReferenceResidency = true;
	MVKAccelerationStructureCanonicalStorage* _canonicalStorage = nullptr;
	std::atomic<uint32_t> _refCount { 1 };
	std::mutex _stateLock;
	uint64_t _nativeCapacity;
	uint64_t _metadataCapacity;
	uint64_t _nativeSize = 0;
	bool _isCompacted = false;
	uint64_t _instanceMetadataSize = 0;
	uint64_t _serializationSize = 0;
	uint64_t _handleCount = 0;
};

class MVKAccelerationStructureStorage {

public:
	bool matches(VkDeviceSize physicalStart) const;
	MVKAccelerationStructureStorageGeneration* retainCurrentGeneration();
	id<MTLBuffer> getReferenceMTLBuffer() const { return _referenceBuffer; }
	uint64_t getReferenceGPUAddress() const { return _referenceBuffer.gpuAddress; }
	bool ensureInitialGeneration(uint64_t nativeCapacity,
							 bool usesPlacement,
							 VkDeviceSize placementOffset);
	VkResult retainFullWriteGeneration(uint64_t nativeCapacity,
									 uint64_t requiredNativeSize,
									 uint64_t requiredMetadataSize,
									 MVKAccelerationStructureStorageGeneration*& generation);
	bool publishGeneration(MVKAccelerationStructureStorageGeneration* generation);

protected:
	friend class MVKDeviceMemory;

	MVKAccelerationStructureStorage(MVKDevice* device,
									id<MTLHeap> heap,
									VkDeviceSize physicalStart);
	~MVKAccelerationStructureStorage();
	MVKAccelerationStructureStorageGeneration* newGeneration(uint64_t nativeCapacity,
															 bool usesPlacement,
															 VkDeviceSize placementOffset,
															 uint64_t metadataCapacity);

	MVKDevice* _device;
	id<MTLHeap> _heap;
	id<MTLBuffer> _referenceBuffer = nil;
	VkDeviceSize _physicalStart;
	uint32_t _memberCount = 0;
	std::mutex _lock;
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
	id<MTLBuffer> getReferenceMTLBuffer();

	uint64_t getSize() const { return _size; }

	VkAccelerationStructureTypeKHR getAccelerationStructureType() const { return _type; }

	MVKAccelerationStructureStorageGeneration* retainCurrentGeneration();

	VkResult retainFullWriteGeneration(uint64_t requiredNativeSize,
									 MVKAccelerationStructureStorageGeneration*& generation);
	VkResult retainFullWriteGeneration(uint64_t requiredNativeSize,
	                                     uint64_t requiredMetadataSize,
	                                     MVKAccelerationStructureStorageGeneration*& generation);

	bool publishGeneration(MVKAccelerationStructureStorageGeneration* generation);

	static VkDeviceSize getMTLPlacementAlignment(MVKDevice* device);
	static void applyMTLUsage(MTLAccelerationStructureDescriptor* descriptor,
						  VkBuildAccelerationStructureFlagsKHR flags);

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
	VkResult getMetalStorageInfo(MVKBuffer* backingBuffer,
								MVKDeviceMemory* memory,
								VkDeviceSize bufferMemoryOffset,
								VkDeviceSize& physicalStart,
								bool& usesPlacement,
								VkDeviceSize& placementOffset,
								VkDeviceSize& nativeCapacity);

	MVKBuffer* _backingBuffer = nullptr;
	MVKDeviceMemory* _storageMemory = nullptr;
	MVKAccelerationStructureStorage* _storage = nullptr;

	uint64_t _address = 0;
	uint64_t _size = 0;
	VkDeviceSize _bufferOffset = 0;
	VkDeviceSize _nativeCapacity = 0;
	VkDeviceSize _metadataCapacity = 0;
	VkAccelerationStructureTypeKHR _type = VK_ACCELERATION_STRUCTURE_TYPE_GENERIC_KHR;
	std::mutex _lock;
	std::atomic<bool> _isMaterialized { false };
	bool _isGPUAddressableRegistered = false;
	bool _isBufferBound = false;
	bool _isDestroyed = false;
};
