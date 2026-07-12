/*
 * MVKAccelerationStructure.mm
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

#include "MVKDevice.h"
#include "MVKBuffer.h"
#include "MVKDeviceMemory.h"
#include "MVKAccelerationStructure.h"
#include "mvk_datatypes.hpp"

#include <Metal/Metal.h>
#include <cstring>
#include <memory>
#include <new>
#include <numeric>

#pragma mark -
#pragma mark MVKAcceleration Structure

static id<MTLArgumentEncoder> newAccelerationStructureReferenceEncoder(id<MTLDevice> device) {
	MTLArgumentDescriptor* accelerationStructure = [MTLArgumentDescriptor new];
	accelerationStructure.index = 0;
	accelerationStructure.access = MTLArgumentAccessReadOnly;
	accelerationStructure.dataType = MTLDataTypeInstanceAccelerationStructure;
	MTLArgumentDescriptor* metadata = [MTLArgumentDescriptor new];
	metadata.index = 1;
	metadata.access = MTLArgumentAccessReadOnly;
	metadata.dataType = MTLDataTypePointer;
	MTLArgumentDescriptor* resourceID = [MTLArgumentDescriptor new];
	resourceID.index = 2;
	resourceID.access = MTLArgumentAccessReadOnly;
	resourceID.dataType = MTLDataTypeULong;
	NSArray* arguments = [[NSArray alloc] initWithObjects:accelerationStructure, metadata, resourceID, nil];
	id<MTLArgumentEncoder> encoder = [device newArgumentEncoderWithArguments:arguments];
	[arguments release];
	[resourceID release];
	[metadata release];
	[accelerationStructure release];
	return encoder;
}

static bool encodeAccelerationStructureReference(id<MTLDevice> device,
											  id<MTLBuffer> referenceBuffer,
											  id<MTLAccelerationStructure> accelerationStructure,
											  id<MTLBuffer> instanceMetadataBuffer) {
	id<MTLArgumentEncoder> encoder = newAccelerationStructureReferenceEncoder(device);
	if (!encoder || encoder.encodedLength > referenceBuffer.length) {
		[encoder release];
		return false;
	}
	[encoder setArgumentBuffer:referenceBuffer offset:0];
	void* constantData = [encoder constantDataAtIndex:2];
	if (!constantData) {
		[encoder release];
		return false;
	}
	[encoder setAccelerationStructure:accelerationStructure atIndex:0];
	[encoder setBuffer:instanceMetadataBuffer offset:0 atIndex:1];
	MTLResourceID resourceID = accelerationStructure ? accelerationStructure.gpuResourceID : MTLResourceID{};
	static_assert(sizeof(resourceID) == sizeof(uint64_t));
	std::memcpy(constantData, &resourceID, sizeof(resourceID));
	[encoder release];
	return true;
}

class MVKAccelerationStructureCanonicalStorage {

public:
	MVKAccelerationStructureCanonicalStorage(MVKDevice* device, id<MTLBuffer> buffer) :
		_device(device), _buffer([buffer retain]) {
		_device->getLiveResources().add(_buffer);
		_device->makeResident(_buffer);
	}

	void retain() { _refCount.fetch_add(1, std::memory_order_relaxed); }

	void release() {
		if (_refCount.fetch_sub(1, std::memory_order_acq_rel) == 1) { delete this; }
	}

	id<MTLBuffer> getMTLBuffer() const { return _buffer; }

private:
	~MVKAccelerationStructureCanonicalStorage() {
		_device->removeResidency(_buffer);
		_device->getLiveResources().remove(_buffer);
		[_buffer release];
	}

	MVKDevice* _device;
	id<MTLBuffer> _buffer;
	std::atomic<uint32_t> _refCount { 1 };
};

MVKAccelerationStructureStorageGeneration::MVKAccelerationStructureStorageGeneration(
	MVKDevice* device,
	id<MTLHeap> heap,
	id<MTLAccelerationStructure> accelerationStructure,
	id<MTLBuffer> instanceMetadataBuffer,
	id<MTLBuffer> referenceBuffer,
	uint64_t nativeCapacity,
	uint64_t metadataCapacity) :
	_device(device),
	_heap([heap retain]),
	_accelerationStructure(accelerationStructure),
	_instanceMetadataBuffer(instanceMetadataBuffer),
	_referenceBuffer(referenceBuffer),
	_nativeCapacity(nativeCapacity),
	_metadataCapacity(metadataCapacity) {
	_device->getLiveResources().add(_accelerationStructure);
	_device->getLiveResources().add(_referenceBuffer);
	_device->makeResident(_accelerationStructure);
	_device->makeResident(_referenceBuffer);
	if (_instanceMetadataBuffer) {
		_device->getLiveResources().add(_instanceMetadataBuffer);
		_device->makeResident(_instanceMetadataBuffer);
	}
}

MVKAccelerationStructureStorageGeneration::~MVKAccelerationStructureStorageGeneration() {
	MVKAccelerationStructureCanonicalStorage* canonicalStorage = nullptr;
	{
		std::lock_guard<std::mutex> lock(_stateLock);
		canonicalStorage = _canonicalStorage;
		_canonicalStorage = nullptr;
		_canonicalBuffer = nil;
	}
	if (canonicalStorage) { canonicalStorage->release(); }
	_device->removeResidency(_referenceBuffer);
	_device->getLiveResources().remove(_referenceBuffer);
	_device->removeResidency(_accelerationStructure);
	_device->getLiveResources().remove(_accelerationStructure);
	if (_instanceMetadataBuffer) {
		_device->removeResidency(_instanceMetadataBuffer);
		_device->getLiveResources().remove(_instanceMetadataBuffer);
	}
	[_referenceBuffer release];
	[_instanceMetadataBuffer release];
	[_accelerationStructure release];
	[_heap release];
}

void MVKAccelerationStructureStorageGeneration::retain() {
	_refCount.fetch_add(1, std::memory_order_relaxed);
}

void MVKAccelerationStructureStorageGeneration::release() {
	if (_refCount.fetch_sub(1, std::memory_order_acq_rel) == 1) { delete this; }
}

uint64_t MVKAccelerationStructureStorageGeneration::getNativeSize() {
	std::lock_guard<std::mutex> lock(_stateLock);
	return _nativeSize;
}

uint64_t MVKAccelerationStructureStorageGeneration::getInstanceMetadataSize() {
	std::lock_guard<std::mutex> lock(_stateLock);
	return _instanceMetadataSize;
}

uint64_t MVKAccelerationStructureStorageGeneration::getSerializationSize() {
	std::lock_guard<std::mutex> lock(_stateLock);
	return _serializationSize;
}

uint64_t MVKAccelerationStructureStorageGeneration::getHandleCount() {
	std::lock_guard<std::mutex> lock(_stateLock);
	return _handleCount;
}

MVKAccelerationStructureCanonicalSnapshot
MVKAccelerationStructureStorageGeneration::retainCanonicalSnapshot() {
	std::lock_guard<std::mutex> lock(_stateLock);
	MVKAccelerationStructureCanonicalSnapshot snapshot;
	if (_canonicalStorage) { _canonicalStorage->retain(); }
	snapshot.storage = _canonicalStorage;
	snapshot.canonicalBuffer = _canonicalBuffer;
	snapshot.canonicalSize = _canonicalSize;
	snapshot.serializationSize = _serializationSize;
	return snapshot;
}

void MVKAccelerationStructureStorageGeneration::releaseCanonicalSnapshot(
	MVKAccelerationStructureCanonicalSnapshot& snapshot) {
	if (snapshot.storage) { snapshot.storage->release(); }
	snapshot = {};
}

bool MVKAccelerationStructureStorageGeneration::isCompatibleWith(uint64_t nativeCapacity,
																  uint64_t metadataCapacity) {
	std::lock_guard<std::mutex> lock(_stateLock);
	return _nativeSize <= nativeCapacity && _instanceMetadataSize <= metadataCapacity;
}

bool MVKAccelerationStructureStorageGeneration::setInstanceMetadataSize(uint64_t size) {
	std::lock_guard<std::mutex> lock(_stateLock);
	if (size > _metadataCapacity) { return false; }
	_instanceMetadataSize = size;
	return true;
}

void MVKAccelerationStructureStorageGeneration::publishBuild(
	uint64_t nativeSize,
	uint64_t instanceMetadataSize,
	uint64_t handleCount) {
	MVKAccelerationStructureCanonicalStorage* canonicalStorage = nullptr;
	{
		std::lock_guard<std::mutex> lock(_stateLock);
		canonicalStorage = _canonicalStorage;
		_canonicalStorage = nullptr;
		_canonicalBuffer = nil;
		_canonicalSize = 0;
		_serializationSize = 0;
		_nativeSize = std::min(nativeSize, _nativeCapacity);
		_instanceMetadataSize = std::min(instanceMetadataSize, _metadataCapacity);
		_handleCount = handleCount;
	}
	if (canonicalStorage) { canonicalStorage->release(); }
}

void MVKAccelerationStructureStorageGeneration::publishCanonical(id<MTLBuffer> canonicalBuffer,
														  uint64_t canonicalSize,
														  uint64_t serializationSize,
														  uint64_t handleCount) {
	{
		std::lock_guard<std::mutex> lock(_stateLock);
		if (_canonicalBuffer == canonicalBuffer) {
			_canonicalSize = canonicalSize;
			_serializationSize = serializationSize;
			_handleCount = handleCount;
			return;
		}
	}
	auto* canonicalStorage = canonicalBuffer
		? new (std::nothrow) MVKAccelerationStructureCanonicalStorage(_device, canonicalBuffer)
		: nullptr;
	if (canonicalBuffer && !canonicalStorage) { return; }
	MVKAccelerationStructureCanonicalStorage* oldStorage = nullptr;
	{
		std::lock_guard<std::mutex> lock(_stateLock);
		oldStorage = _canonicalStorage;
		_canonicalStorage = canonicalStorage;
		_canonicalBuffer = canonicalBuffer;
		_canonicalSize = canonicalSize;
		_serializationSize = serializationSize;
		_handleCount = handleCount;
	}
	if (oldStorage) { oldStorage->release(); }
}

void MVKAccelerationStructureStorageGeneration::copyContentFrom(
	MVKAccelerationStructureStorageGeneration* source,
	uint64_t nativeSizeLimit) {
	if (source == this) { return; }
	MVKAccelerationStructureCanonicalStorage* canonicalStorage = nullptr;
	id<MTLBuffer> canonicalBuffer = nil;
	uint64_t nativeSize = 0;
	uint64_t instanceMetadataSize = 0;
	uint64_t canonicalSize = 0;
	uint64_t serializationSize = 0;
	uint64_t handleCount = 0;
	{
		std::lock_guard<std::mutex> lock(source->_stateLock);
		canonicalStorage = source->_canonicalStorage;
		if (canonicalStorage) { canonicalStorage->retain(); }
		canonicalBuffer = source->_canonicalBuffer;
		nativeSize = source->_nativeSize;
		instanceMetadataSize = source->_instanceMetadataSize;
		canonicalSize = source->_canonicalSize;
		serializationSize = source->_serializationSize;
		handleCount = source->_handleCount;
	}
	MVKAccelerationStructureCanonicalStorage* oldStorage = nullptr;
	{
		std::lock_guard<std::mutex> lock(_stateLock);
		oldStorage = _canonicalStorage;
		_canonicalStorage = canonicalStorage;
		_canonicalBuffer = canonicalBuffer;
		_nativeSize = std::min({nativeSize, nativeSizeLimit, _nativeCapacity});
		_instanceMetadataSize = std::min(instanceMetadataSize, _metadataCapacity);
		_canonicalSize = canonicalSize;
		_serializationSize = serializationSize;
		_handleCount = handleCount;
	}
	if (oldStorage) { oldStorage->release(); }
}

MVKAccelerationStructureStorage::MVKAccelerationStructureStorage(
	MVKDevice* device,
	id<MTLHeap> heap,
	bool usesPlacement,
	VkDeviceSize physicalStart,
	VkDeviceAddress requestedDeviceAddress,
	VkAccelerationStructureCreateFlagsKHR createFlags,
	VkAccelerationStructureTypeKHR type,
	VkDeviceSize placementOffset) :
	_device(device),
	_heap(heap),
	_usesPlacement(usesPlacement),
	_physicalStart(physicalStart),
	_requestedDeviceAddress(requestedDeviceAddress),
	_createFlags(createFlags),
	_type(type),
	_placementOffset(placementOffset) {}

MVKAccelerationStructureStorage::~MVKAccelerationStructureStorage() {
	for (auto* generation : _generations) { generation->release(); }
}

bool MVKAccelerationStructureStorage::matches(VkDeviceSize physicalStart,
														 VkDeviceAddress requestedDeviceAddress,
														 VkAccelerationStructureCreateFlagsKHR createFlags,
														 VkAccelerationStructureTypeKHR type) const {
	return _physicalStart == physicalStart &&
		_requestedDeviceAddress == requestedDeviceAddress &&
		_createFlags == createFlags &&
		_type == type;
}

MVKAccelerationStructureStorageGeneration* MVKAccelerationStructureStorage::newGeneration(
	uint64_t nativeCapacity,
	uint64_t metadataCapacity) {
	if (!nativeCapacity) { return nullptr; }
	id<MTLDevice> mtlDevice = _device->getPhysicalDevice()->getMTLDevice();
	id<MTLAccelerationStructure> accelerationStructure = _usesPlacement
		? [_heap newAccelerationStructureWithSize:nativeCapacity offset:_placementOffset]
		: [mtlDevice newAccelerationStructureWithSize:nativeCapacity];
	id<MTLBuffer> metadataBuffer = metadataCapacity
		? [mtlDevice newBufferWithLength:std::max<uint64_t>(metadataCapacity, sizeof(uint64_t))
										 options:MTLResourceStorageModePrivate]
		: nil;
	id<MTLArgumentEncoder> encoder = newAccelerationStructureReferenceEncoder(mtlDevice);
	id<MTLBuffer> referenceBuffer = encoder
		? [mtlDevice newBufferWithLength:encoder.encodedLength options:MTLResourceStorageModeShared]
		: nil;
	[encoder release];
	if (!accelerationStructure || (metadataCapacity && !metadataBuffer) ||
		!referenceBuffer || !referenceBuffer.gpuAddress ||
		!encodeAccelerationStructureReference(mtlDevice, referenceBuffer,
												 accelerationStructure, metadataBuffer)) {
		[referenceBuffer release];
		[metadataBuffer release];
		[accelerationStructure release];
		return nullptr;
	}
	auto* generation = new (std::nothrow) MVKAccelerationStructureStorageGeneration(
		_device, _heap, accelerationStructure, metadataBuffer, referenceBuffer,
		nativeCapacity, metadataCapacity);
	if (!generation) {
		[referenceBuffer release];
		[metadataBuffer release];
		[accelerationStructure release];
	}
	return generation;
}

MVKAccelerationStructureStorageGeneration* MVKAccelerationStructureStorage::retainCurrentGeneration() {
	std::lock_guard<std::mutex> lock(_lock);
	if (_currentGeneration) { _currentGeneration->retain(); }
	return _currentGeneration;
}

MVKAccelerationStructureStorageGeneration* MVKAccelerationStructureStorage::retainInitialGeneration(
	uint64_t nativeCapacity,
	uint64_t metadataCapacity) {
	std::lock_guard<std::mutex> lock(_lock);
	if (!_currentGeneration) {
		_currentGeneration = newGeneration(nativeCapacity, metadataCapacity);
		if (_currentGeneration) { _generations.push_back(_currentGeneration); }
	}
	if (_currentGeneration) { _currentGeneration->retain(); }
	return _currentGeneration;
}

VkResult MVKAccelerationStructureStorage::retainFullWriteGeneration(
	uint64_t nativeCapacity,
	uint64_t requiredNativeSize,
	uint64_t metadataCapacity,
	uint64_t requiredMetadataSize,
	MVKAccelerationStructureStorageGeneration*& generation) {
	generation = nullptr;
	if (requiredNativeSize > nativeCapacity || requiredMetadataSize > metadataCapacity) {
		return VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}
	std::lock_guard<std::mutex> lock(_lock);
	if (!_currentGeneration ||
		_currentGeneration->getNativeCapacity() < nativeCapacity ||
		_currentGeneration->getMetadataCapacity() < requiredMetadataSize) {
		auto* nextGeneration = newGeneration(nativeCapacity, requiredMetadataSize);
		if (!nextGeneration) { return VK_ERROR_OUT_OF_DEVICE_MEMORY; }
		_generations.push_back(nextGeneration);
		nextGeneration->retain();
		generation = nextGeneration;
		return VK_SUCCESS;
	}
	_currentGeneration->retain();
	generation = _currentGeneration;
	return VK_SUCCESS;
}

bool MVKAccelerationStructureStorage::publishGeneration(
	MVKAccelerationStructureStorageGeneration* generation) {
	std::lock_guard<std::mutex> lock(_lock);
	if (!generation || !mvkContains(_generations, generation)) { return false; }
	_currentGeneration = generation;
	return true;
}

uint64_t MVKAccelerationStructure::getDeviceAddress() {
	std::lock_guard<std::mutex> lock(_lock);
	return _isBufferBound && !_isDestroyed ? _address : 0;
}

uint64_t MVKAccelerationStructure::getNativeCapacity() {
	if (!_isMaterialized.load(std::memory_order_acquire)) {
		bool materialized = false;
		materialize(materialized);
	}
	std::lock_guard<std::mutex> lock(_lock);
	return _nativeCapacity;
}

MVKAccelerationStructureStorageGeneration* MVKAccelerationStructure::retainCurrentGeneration() {
	if (!_isMaterialized.load(std::memory_order_acquire)) {
		bool materialized = false;
		materialize(materialized);
	}
	std::lock_guard<std::mutex> lock(_lock);
	if (_isDestroyed || !_isBufferBound || !_storage) { return nullptr; }
	auto* generation = _storage->retainCurrentGeneration();
	if (generation && !generation->isCompatibleWith(_nativeCapacity, _metadataCapacity)) {
		generation->release();
		return nullptr;
	}
	return generation;
}

VkDeviceSize MVKAccelerationStructure::getMTLPlacementAlignment(MVKDevice* device) {
	auto* physicalDevice = device->getPhysicalDevice();
	VkDeviceSize maxSize = physicalDevice->getMetalFeatures()->maxMTLBufferSize;
	MTLSizeAndAlign sizeAndAlign =
		[physicalDevice->getMTLDevice() heapAccelerationStructureSizeAndAlignWithSize:maxSize];
	if (!sizeAndAlign.align) { return 0; }
	VkDeviceSize gcd = std::gcd<VkDeviceSize>(256, sizeAndAlign.align);
	return sizeAndAlign.align > UINT64_MAX / (256 / gcd) ? 0 : sizeAndAlign.align * (256 / gcd);
}

MTLAccelerationStructureDescriptor* MVKAccelerationStructure::newMTLAccelerationStructureDescriptor(const VkAccelerationStructureBuildGeometryInfoKHR& buildInfo,
                                                                                                    const VkAccelerationStructureBuildRangeInfoKHR* rangeInfos,
                                                                                                    const uint32_t* maxPrimitiveCounts) {
    MTLAccelerationStructureDescriptor* descriptor = nil;

    switch (buildInfo.type) {
        default:
        case VK_ACCELERATION_STRUCTURE_TYPE_GENERIC_KHR:
            break;

        case VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR: {
            MTLPrimitiveAccelerationStructureDescriptor* primitive = [MTLPrimitiveAccelerationStructureDescriptor new];

            NSMutableArray* geoms = [NSMutableArray new];
            for (uint32_t i = 0; i < buildInfo.geometryCount; i++) {
                const VkAccelerationStructureGeometryKHR& geom = buildInfo.pGeometries
                    ? buildInfo.pGeometries[i]
                    : *buildInfo.ppGeometries[i];
                switch (geom.geometryType) {
                    default:
                        continue;

                    case VK_GEOMETRY_TYPE_TRIANGLES_KHR: {
                        const VkAccelerationStructureGeometryTrianglesDataKHR& triangleData = geom.geometry.triangles;
                        VkDeviceSize vertexOffset = 0;
                        VkDeviceSize indexOffset = 0;
                        VkDeviceSize transformOffset = 0;
                        MVKBuffer* mvkVertexBuffer = getDevice()->getBufferAtAddress(triangleData.vertexData.deviceAddress, vertexOffset);
                        MVKBuffer* mvkIndexBuffer = triangleData.indexData.deviceAddress
                            ? getDevice()->getBufferAtAddress(triangleData.indexData.deviceAddress, indexOffset)
                            : nullptr;
                        MVKBuffer* mvkTransformBuffer = triangleData.transformData.deviceAddress
                            ? getDevice()->getBufferAtAddress(triangleData.transformData.deviceAddress, transformOffset)
                            : nullptr;
                        bool useIndices = triangleData.indexType != VK_INDEX_TYPE_NONE_KHR;
                        if (rangeInfos && (!mvkVertexBuffer ||
                            (useIndices && !mvkIndexBuffer) ||
                            (triangleData.transformData.deviceAddress && !mvkTransformBuffer))) { continue; }

                        MTLAccelerationStructureTriangleGeometryDescriptor* geometryTriangles = [MTLAccelerationStructureTriangleGeometryDescriptor new];
                        if (mvkVertexBuffer) {
                            geometryTriangles.vertexBuffer = mvkVertexBuffer->getMTLBuffer();
                            geometryTriangles.vertexBufferOffset = mvkVertexBuffer->getMTLBufferOffset() + vertexOffset;
                        }
                        geometryTriangles.vertexStride = triangleData.vertexStride;
                        geometryTriangles.vertexFormat = mvkMTLAccelerationStructureVertexFormatFromVkFormat(triangleData.vertexFormat);
                        geometryTriangles.opaque = mvkIsAnyFlagEnabled(geom.flags, VK_GEOMETRY_OPAQUE_BIT_KHR);
                        geometryTriangles.allowDuplicateIntersectionFunctionInvocation = !mvkIsAnyFlagEnabled(geom.flags, VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_KHR);

                        if (mvkTransformBuffer) {
                            geometryTriangles.transformationMatrixBuffer = mvkTransformBuffer->getMTLBuffer();
                            geometryTriangles.transformationMatrixBufferOffset = mvkTransformBuffer->getMTLBufferOffset() + transformOffset;
                        }

                        if (useIndices) {
                            if (mvkIndexBuffer) {
                                geometryTriangles.indexBuffer = mvkIndexBuffer->getMTLBuffer();
                                geometryTriangles.indexBufferOffset = mvkIndexBuffer->getMTLBufferOffset() + indexOffset;
                            }
                            geometryTriangles.indexType = mvkMTLIndexTypeFromVkIndexType(triangleData.indexType);
                        }

                        if (rangeInfos) {
                            geometryTriangles.triangleCount = rangeInfos[i].primitiveCount;
                            if (mvkTransformBuffer) { geometryTriangles.transformationMatrixBufferOffset += rangeInfos[i].transformOffset; }
                            geometryTriangles.vertexBufferOffset += rangeInfos[i].firstVertex * triangleData.vertexStride;
                            if (useIndices) {
                                geometryTriangles.indexBufferOffset += rangeInfos[i].primitiveOffset;
                            } else {
                                geometryTriangles.vertexBufferOffset += rangeInfos[i].primitiveOffset;
                            }
                        } else {
                            geometryTriangles.triangleCount = maxPrimitiveCounts[i];
                        }
                        [geoms addObject:geometryTriangles];
                        [geometryTriangles release];
                    } break;

                    case VK_GEOMETRY_TYPE_AABBS_KHR: {
                        const VkAccelerationStructureGeometryAabbsDataKHR& aabbData = geom.geometry.aabbs;
                        VkDeviceSize boundingBoxOffset = 0;
                        MVKBuffer* mvkBoundingBoxBuffer = getDevice()->getBufferAtAddress(aabbData.data.deviceAddress, boundingBoxOffset);
                        if (rangeInfos && !mvkBoundingBoxBuffer) { continue; }

                        MTLAccelerationStructureBoundingBoxGeometryDescriptor* geometryAABBs = [MTLAccelerationStructureBoundingBoxGeometryDescriptor new];
                        geometryAABBs.boundingBoxStride = aabbData.stride;
                        if (mvkBoundingBoxBuffer) {
                            geometryAABBs.boundingBoxBuffer = mvkBoundingBoxBuffer->getMTLBuffer();
                            geometryAABBs.boundingBoxBufferOffset = mvkBoundingBoxBuffer->getMTLBufferOffset() + boundingBoxOffset;
                        }
                        geometryAABBs.opaque = mvkIsAnyFlagEnabled(geom.flags, VK_GEOMETRY_OPAQUE_BIT_KHR);
                        geometryAABBs.allowDuplicateIntersectionFunctionInvocation = !mvkIsAnyFlagEnabled(geom.flags, VK_GEOMETRY_NO_DUPLICATE_ANY_HIT_INVOCATION_BIT_KHR);

                        if (rangeInfos) {
                            geometryAABBs.boundingBoxCount = rangeInfos[i].primitiveCount;
                            geometryAABBs.boundingBoxBufferOffset += rangeInfos[i].primitiveOffset;
                        }
                        else {
                            geometryAABBs.boundingBoxCount = maxPrimitiveCounts[i];
                        }

                        [geoms addObject:geometryAABBs];
                        [geometryAABBs release];
                    } break;
                }
            }

            primitive.geometryDescriptors = geoms;
            [geoms release];
            descriptor = primitive;
        } break;

        case VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR: {
            if (buildInfo.geometryCount != 1) { break; }
            const VkAccelerationStructureGeometryKHR& geom = buildInfo.pGeometries
                ? buildInfo.pGeometries[0]
                : *buildInfo.ppGeometries[0];
            if (geom.geometryType != VK_GEOMETRY_TYPE_INSTANCES_KHR) { break; }

            MTLInstanceAccelerationStructureDescriptor* tlas = [MTLInstanceAccelerationStructureDescriptor new];
            tlas.instanceDescriptorType = MTLAccelerationStructureInstanceDescriptorTypeIndirect;
            tlas.instanceCount = rangeInfos ? rangeInfos[0].primitiveCount : maxPrimitiveCounts[0];

            descriptor = tlas;
        } break;
    }

    if (!descriptor) { return nil; }

    descriptor.usage = MTLAccelerationStructureUsageExtendedLimits;
    if (mvkIsAnyFlagEnabled(buildInfo.flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)) {
        descriptor.usage |= MTLAccelerationStructureUsageRefit;
    }
    if (mvkIsAnyFlagEnabled(buildInfo.flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)) {
        descriptor.usage |= MTLAccelerationStructureUsagePreferFastBuild;
    }
#if MVK_XCODE_26
	if (@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)) {
		if (mvkIsAnyFlagEnabled(buildInfo.flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR)) {
			descriptor.usage |= MTLAccelerationStructureUsagePreferFastIntersection;
		}
		if (mvkIsAnyFlagEnabled(buildInfo.flags, VK_BUILD_ACCELERATION_STRUCTURE_LOW_MEMORY_BIT_KHR)) {
			descriptor.usage |= MTLAccelerationStructureUsageMinimizeMemory;
		}
	}
#endif

    return descriptor;
}

VkAccelerationStructureBuildSizesInfoKHR MVKAccelerationStructure::getBuildSizes(VkAccelerationStructureBuildTypeKHR type,
                                                                                 const VkAccelerationStructureBuildGeometryInfoKHR* info,
                                                                                 const uint32_t* maxPrimitiveCounts) {
    VkAccelerationStructureBuildSizesInfoKHR vkBuildSizes = {
        .sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
    };

    if (type == VK_ACCELERATION_STRUCTURE_BUILD_TYPE_HOST_KHR) { return vkBuildSizes; }

    MTLAccelerationStructureDescriptor* descriptor = newMTLAccelerationStructureDescriptor(*info, nullptr, maxPrimitiveCounts);

    if ( !descriptor ) { return vkBuildSizes; }
    MTLAccelerationStructureSizes sizes = [getMTLDevice() accelerationStructureSizesWithDescriptor:descriptor];
    constexpr VkDeviceSize minSize = 256;
	MTLSizeAndAlign sizeAndAlign = [getMTLDevice() heapAccelerationStructureSizeAndAlignWithSize:sizes.accelerationStructureSize];
	VkDeviceSize placementAlignment = getMTLPlacementAlignment(getDevice());
	VkDeviceSize placementPadding = placementAlignment >= minSize ? placementAlignment - minSize : UINT64_MAX;
	bool validAlignment = placementAlignment && sizeAndAlign.align && !(placementAlignment % sizeAndAlign.align);
	vkBuildSizes.accelerationStructureSize = validAlignment && sizeAndAlign.size <= UINT64_MAX - placementPadding
		? std::max<VkDeviceSize>(sizeAndAlign.size + placementPadding, minSize)
		: UINT64_MAX;
	if (info->type == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
		constexpr VkDeviceSize metadataStride = sizeof(uint32_t) * 2;
		VkDeviceSize instanceCount = maxPrimitiveCounts[0];
		VkDeviceSize metadataSize = instanceCount <= UINT64_MAX / metadataStride
			? instanceCount * metadataStride
			: UINT64_MAX;
		vkBuildSizes.accelerationStructureSize = std::max(vkBuildSizes.accelerationStructureSize, metadataSize);
	}
    vkBuildSizes.buildScratchSize = std::max<VkDeviceSize>(sizes.buildScratchBufferSize, minSize);
    vkBuildSizes.updateScratchSize = std::max<VkDeviceSize>(sizes.refitScratchBufferSize, minSize);

    [descriptor release];

    return vkBuildSizes;
}

MVKAccelerationStructure::MVKAccelerationStructure(MVKDevice* device) : MVKVulkanAPIDeviceObject(device) {}

MVKAccelerationStructure::MVKAccelerationStructure(MVKDevice* device,
                                                   const VkAccelerationStructureCreateInfoKHR* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	_backingBuffer = (MVKBuffer*)pCreateInfo->buffer;
	_bufferOffset = pCreateInfo->offset;
	_size = pCreateInfo->size;
	_type = pCreateInfo->type;
	_createFlags = pCreateInfo->createFlags;
	_requestedDeviceAddress = pCreateInfo->deviceAddress;
	if (_backingBuffer) {
		_backingBuffer->retain();
	}
	if (_backingBuffer && _backingBuffer->addAccelerationStructure(this)) {
		bool materialized = false;
		VkResult result = materialize(materialized);
		if (result < 0) {
			setConfigurationResult(reportError(result,
				"vkCreateAccelerationStructureKHR(): Metal could not allocate acceleration-structure resources."));
		}
	} else if (!_backingBuffer) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED,
			"vkCreateAccelerationStructureKHR(): The backing buffer is null."));
	}
	getDevice()->addLiveAccelerationStructureObject(this);
}

MVKAccelerationStructure::~MVKAccelerationStructure() {
	detachBackingBuffer();
	releaseMetalResources();
}

void MVKAccelerationStructure::destroy() {
	getDevice()->removeLiveAccelerationStructureObject(this);
	{
		std::lock_guard<std::mutex> lock(_lock);
		_isDestroyed = true;
	}
	detachBackingBuffer();
	releaseMetalResources();
	MVKVulkanAPIDeviceObject::destroy();
}

VkResult MVKAccelerationStructure::getMaximumMetalSize(MVKBuffer* backingBuffer,
														MVKDeviceMemory* memory,
														VkDeviceSize bufferMemoryOffset,
														VkDeviceSize& physicalStart,
														VkDeviceSize& placementOffset,
														VkDeviceSize& metalSize) {
	bool usePlacement = memory->isAccelerationStructurePlacementCompatible();
	id<MTLHeap> heap = usePlacement ? memory->getMTLHeap() : nil;
	VkDeviceSize placementAlignment = getMTLPlacementAlignment(getDevice());
	if (!placementAlignment || _bufferOffset > UINT64_MAX - bufferMemoryOffset) {
		return VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}
	physicalStart = bufferMemoryOffset + _bufferOffset;
	VkDeviceSize displacement = usePlacement
		? (placementAlignment - physicalStart % placementAlignment) % placementAlignment
		: 0;
	if (displacement > _size || displacement > UINT64_MAX - physicalStart || displacement > UINT64_MAX - _bufferOffset) {
		return VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}
	placementOffset = physicalStart + displacement;
	VkDeviceSize bufferPlacementOffset = _bufferOffset + displacement;
	VkDeviceSize availableSize = _size - displacement;
	VkDeviceSize low = 0;
	VkDeviceSize high = std::min<VkDeviceSize>(availableSize, getMetalFeatures().maxMTLBufferSize);
	while (low < high) {
		VkDeviceSize candidate = low + (high - low) / 2 + 1;
		MTLSizeAndAlign candidateSizeAndAlign =
			[getMTLDevice() heapAccelerationStructureSizeAndAlignWithSize:candidate];
		if (candidateSizeAndAlign.size && candidateSizeAndAlign.size <= availableSize) {
			low = candidate;
		} else {
			high = candidate - 1;
		}
	}
	metalSize = low;
	MTLSizeAndAlign metalSizeAndAlign = [getMTLDevice() heapAccelerationStructureSizeAndAlignWithSize:metalSize];
	bool validAlignment = metalSizeAndAlign.align && !(placementAlignment % metalSizeAndAlign.align);
	bool bufferRangeFits = bufferPlacementOffset <= backingBuffer->getByteCount() &&
		metalSizeAndAlign.size <= backingBuffer->getByteCount() - bufferPlacementOffset;
	bool heapRangeFits = !usePlacement ||
		(placementOffset <= heap.size && metalSizeAndAlign.size <= heap.size - placementOffset);
	if (!metalSize || !metalSizeAndAlign.size || !validAlignment || !bufferRangeFits || !heapRangeFits) {
		return VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}
	return VK_SUCCESS;
}

VkResult MVKAccelerationStructure::materialize(bool& materialized) {
	materialized = false;
	MVKBuffer* backingBuffer = nullptr;
	{
		std::lock_guard<std::mutex> lock(_lock);
		if (_isDestroyed) { return VK_SUCCESS; }
		if (_isMaterialized.load(std::memory_order_relaxed)) {
			_isBufferBound = true;
			return VK_SUCCESS;
		}
		backingBuffer = _backingBuffer;
		if (backingBuffer) { backingBuffer->retain(); }
	}
	if (!backingBuffer) { return VK_SUCCESS; }
	VkDeviceSize bufferMemoryOffset = 0;
	MVKDeviceMemory* memory = backingBuffer->getAccelerationStructureMemoryBinding(bufferMemoryOffset);
	if (!memory) {
		backingBuffer->release();
		return VK_SUCCESS;
	}
	VkDeviceSize physicalStart = 0;
	VkDeviceSize placementOffset = 0;
	VkDeviceSize nativeCapacity = 0;
	VkResult result = getMaximumMetalSize(backingBuffer, memory, bufferMemoryOffset,
		physicalStart, placementOffset, nativeCapacity);
	uint64_t bufferAddress = backingBuffer->getMTLBufferGPUAddress();
	if (!bufferAddress || _bufferOffset > UINT64_MAX - bufferAddress ||
		((bufferAddress + _bufferOffset) & 0xff)) {
		result = VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}
	if (result < 0) {
		memory->release();
		backingBuffer->release();
		return result;
	}
	VkDeviceSize metadataCapacity = _type == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR
		? 0
		: std::min<VkDeviceSize>(_size, getMetalFeatures().maxMTLBufferSize);
	auto* storage = memory->acquireAccelerationStructureStorage(physicalStart,
		_requestedDeviceAddress, _createFlags, _type, placementOffset);
	if (!storage) {
		memory->release();
		backingBuffer->release();
		return VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}
	auto* generation = storage->retainInitialGeneration(nativeCapacity, 0);
	if (!generation) {
		memory->releaseAccelerationStructureStorage(storage);
		memory->release();
		backingBuffer->release();
		return VK_ERROR_OUT_OF_DEVICE_MEMORY;
	}
	generation->release();
	bool published = false;
	{
		std::lock_guard<std::mutex> lock(_lock);
		if (!_isDestroyed && !_isMaterialized.load(std::memory_order_relaxed) && _backingBuffer == backingBuffer) {
			_storage = storage;
			_storageMemory = memory;
			_nativeCapacity = nativeCapacity;
			_metadataCapacity = metadataCapacity;
			_address = _requestedDeviceAddress ? _requestedDeviceAddress : bufferAddress + _bufferOffset;
			_isMaterialized.store(true, std::memory_order_release);
			_isBufferBound = true;
			materialized = true;
			published = true;
		}
	}
	backingBuffer->release();
	if (!published) {
		memory->releaseAccelerationStructureStorage(storage);
		memory->release();
		return VK_SUCCESS;
	}
	getDevice()->addGPUAddressableAccelerationStructure(this);
	{
		std::lock_guard<std::mutex> lock(_lock);
		if (_isMaterialized.load(std::memory_order_relaxed) && _isBufferBound &&
			!_isDestroyed && _storage == storage) {
			_isGPUAddressableRegistered = true;
			return VK_SUCCESS;
		}
	}
	getDevice()->removeGPUAddressableAccelerationStructure(this);
	return VK_SUCCESS;
}

VkResult MVKAccelerationStructure::retainFullWriteGeneration(
	uint64_t requiredNativeSize,
	uint64_t requiredMetadataSize,
	MVKAccelerationStructureStorageGeneration*& generation) {
	generation = nullptr;
	if (!_isMaterialized.load(std::memory_order_acquire)) {
		bool materialized = false;
		VkResult result = materialize(materialized);
		if (result < 0) { return result; }
	}
	std::lock_guard<std::mutex> lock(_lock);
	if (_isDestroyed || !_storage) { return VK_ERROR_OUT_OF_DEVICE_MEMORY; }
	return _storage->retainFullWriteGeneration(_nativeCapacity, requiredNativeSize,
		_metadataCapacity, requiredMetadataSize, generation);
}

bool MVKAccelerationStructure::publishGeneration(
	MVKAccelerationStructureStorageGeneration* generation) {
	std::lock_guard<std::mutex> lock(_lock);
	return !_isDestroyed && _isBufferBound && _storage && _storage->publishGeneration(generation);
}

void MVKAccelerationStructure::bufferMemoryBindingFailed() {
	std::lock_guard<std::mutex> lock(_lock);
	_isBufferBound = false;
	_address = 0;
}

void MVKAccelerationStructure::releaseMetalResources() {
	MVKDeviceMemory* memory = nullptr;
	MVKAccelerationStructureStorage* storage = nullptr;
	bool registered = false;
	{
		std::lock_guard<std::mutex> lock(_lock);
		if (!_isMaterialized.load(std::memory_order_relaxed)) {
			_isBufferBound = false;
			_address = 0;
			return;
		}
		memory = _storageMemory;
		storage = _storage;
		registered = _isGPUAddressableRegistered;
		_storageMemory = nullptr;
		_storage = nullptr;
		_address = 0;
		_nativeCapacity = 0;
		_metadataCapacity = 0;
		_isMaterialized.store(false, std::memory_order_release);
		_isGPUAddressableRegistered = false;
		_isBufferBound = false;
	}
	if (registered) { getDevice()->removeGPUAddressableAccelerationStructure(this); }
	if (memory) {
		memory->releaseAccelerationStructureStorage(storage);
		memory->release();
	}
}

void MVKAccelerationStructure::detachBackingBuffer() {
	MVKBuffer* backingBuffer = nullptr;
	{
		std::lock_guard<std::mutex> lock(_lock);
		backingBuffer = _backingBuffer;
		_backingBuffer = nullptr;
	}
	if (backingBuffer) {
		backingBuffer->removeAccelerationStructure(this);
		backingBuffer->release();
	}
}
