/*
 * MVKAccelerationStructure.mm
 *
 * Copyright (c) 2015-2023 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKAccelerationStructure.h"

#include <Metal/Metal.h>

#pragma mark -
#pragma mark MVKAcceleration Structure

id<MTLAccelerationStructure> MVKAccelerationStructure::getMTLAccelerationStructure()
{
    return _accelerationStructure;
}
    
MTLAccelerationStructureDescriptor* MVKAccelerationStructure::populateMTLDescriptor(MVKDevice* device,
                                                                                    const VkAccelerationStructureBuildGeometryInfoKHR& buildInfo,
                                                                                    const VkAccelerationStructureBuildRangeInfoKHR* rangeInfos,
                                                                                    const uint32_t* maxPrimitiveCounts)
{
    MTLAccelerationStructureDescriptor* descriptor = nullptr;

    switch (buildInfo.type)
    {
        default:
            break; // TODO: throw error
        case VK_ACCELERATION_STRUCTURE_TYPE_GENERIC_KHR:
        {
            // TODO: should building generic not be allowed?
            // https://registry.khronos.org/vulkan/specs/1.3-extensions/man/html/VkAccelerationStructureTypeKHR.html
        } break;

        case VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR:
        {
            MTLPrimitiveAccelerationStructureDescriptor* primitive = [MTLPrimitiveAccelerationStructureDescriptor new];

            NSMutableArray* geoms = [NSMutableArray arrayWithCapacity:buildInfo.geometryCount];
            for (uint32_t i = 0; i < buildInfo.geometryCount; i++)
            {
                // TODO: buildInfo.ppGeometries

                const VkAccelerationStructureGeometryKHR& geom = buildInfo.pGeometries[i];
                switch (geom.geometryType)
                {
                    default:
                        break;

                    case VK_GEOMETRY_TYPE_INSTANCES_KHR:
                        break;
                    
                    case VK_GEOMETRY_TYPE_TRIANGLES_KHR:
                    {
                        const VkAccelerationStructureGeometryTrianglesDataKHR& triangleData = geom.geometry.triangles;
                        uint64_t vertexBDA = triangleData.vertexData.deviceAddress;
                        uint64_t indexBDA = triangleData.indexData.deviceAddress;
                        uint64_t transformBDA = triangleData.transformData.deviceAddress;
                        MVKBuffer* mvkVertexBuffer = device->getBufferAtAddress(vertexBDA);
                        MVKBuffer* mvkIndexBuffer = device->getBufferAtAddress(indexBDA);
                        MVKBuffer* mvkTransformBuffer = device->getBufferAtAddress(transformBDA);

                        // TODO: should validate that buffer->getMTLBufferOffset is a multiple of vertexStride. This could cause issues
                        NSUInteger vbOffset = (vertexBDA - mvkVertexBuffer->getMTLBufferGPUAddress()) + mvkVertexBuffer->getMTLBufferOffset();
                        NSUInteger ibOffset = 0;
                        NSUInteger tfOffset = 0;
                        
                        MTLAccelerationStructureTriangleGeometryDescriptor* geometryTriangles = [MTLAccelerationStructureTriangleGeometryDescriptor new];
                        geometryTriangles.vertexBuffer = mvkVertexBuffer->getMTLBuffer();
                        geometryTriangles.vertexStride = triangleData.vertexStride;

                        if (transformBDA && mvkTransformBuffer)
                        {
                            tfOffset = (transformBDA - mvkTransformBuffer->getMTLBufferGPUAddress()) + mvkTransformBuffer->getMTLBufferOffset();
                            geometryTriangles.transformationMatrixBuffer = mvkTransformBuffer->getMTLBuffer();
                        }

                        bool useIndices = indexBDA && mvkIndexBuffer && triangleData.indexType != VK_INDEX_TYPE_NONE_KHR;
                        if (useIndices)
                        {
                            ibOffset = (indexBDA - mvkIndexBuffer->getMTLBufferGPUAddress()) + mvkIndexBuffer->getMTLBufferOffset();
                            geometryTriangles.indexBuffer = mvkIndexBuffer->getMTLBuffer();
                            geometryTriangles.indexType = mvkMTLIndexTypeFromVkIndexType(triangleData.indexType);
                        }

                        if (rangeInfos)
                        {
                            // Utilize range information during build time

                            geometryTriangles.triangleCount = rangeInfos[i].primitiveCount;
                            geometryTriangles.transformationMatrixBufferOffset = tfOffset + rangeInfos[i].transformOffset;
                            geometryTriangles.vertexBufferOffset = vbOffset;
                            geometryTriangles.indexBufferOffset = ibOffset + rangeInfos[i].primitiveOffset;

                            if (!useIndices)
                                geometryTriangles.vertexBufferOffset += rangeInfos[i].primitiveOffset + rangeInfos[i].firstVertex * triangleData.vertexStride;
                        }
                        else
                        {
                            // Less information required when computing size

                            geometryTriangles.vertexBufferOffset = vbOffset;
                            geometryTriangles.triangleCount = maxPrimitiveCounts[i];
                            geometryTriangles.indexBufferOffset = ibOffset;
                            geometryTriangles.transformationMatrixBufferOffset = 0;
                        }

                        [geoms addObject:geometryTriangles];
                    } break;
                    
                    case VK_GEOMETRY_TYPE_AABBS_KHR:
                    {
                        const VkAccelerationStructureGeometryAabbsDataKHR& aabbData = geom.geometry.aabbs;
                        uint64_t boundingBoxBDA = aabbData.data.deviceAddress;
                        MVKBuffer* mvkBoundingBoxBuffer = device->getBufferAtAddress(boundingBoxBDA);

                        NSUInteger bOffset = (boundingBoxBDA - mvkBoundingBoxBuffer->getMTLBufferGPUAddress()) + mvkBoundingBoxBuffer->getMTLBufferOffset();
                        
                        MTLAccelerationStructureBoundingBoxGeometryDescriptor* geometryAABBs = [MTLAccelerationStructureBoundingBoxGeometryDescriptor new];
                        geometryAABBs.boundingBoxStride = aabbData.stride;
                        geometryAABBs.boundingBoxBuffer = mvkBoundingBoxBuffer->getMTLBuffer();
                        geometryAABBs.boundingBoxBufferOffset = bOffset;

                        if (rangeInfos)
                        {
                            geometryAABBs.boundingBoxCount = rangeInfos[i].primitiveCount;
                            geometryAABBs.boundingBoxBufferOffset += rangeInfos[i].primitiveOffset;
                        }
                        else
                            geometryAABBs.boundingBoxCount = maxPrimitiveCounts[i];

                        [geoms addObject:geometryAABBs];
                    } break;
                }
            }

            primitive.geometryDescriptors = geoms;
            descriptor = primitive;
        } break;
        
        case VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR:
        {
            accStructDescriptor = [MTLInstanceAccelerationStructureDescriptor new];
            MTLInstanceAccelerationStructureDescriptor* instanceAccStructDescriptor = (MTLInstanceAccelerationStructureDescriptor*)accStructDescriptor;
            // add bottom level acceleration structures
            
            instanceAccStructDescriptor.instanceDescriptorType = MTLAccelerationStructureInstanceDescriptorTypeDefault;
        } break;
    }

    if (!descriptor)
        return nullptr;

    if (mvkIsAnyFlagEnabled(buildInfo.flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR))
        descriptor.usage += MTLAccelerationStructureUsageRefit;
    else if (mvkIsAnyFlagEnabled(buildInfo.flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR))
        descriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
    else
        descriptor.usage = MTLAccelerationStructureUsageNone;

    return descriptor;
}

VkAccelerationStructureBuildSizesInfoKHR MVKAccelerationStructure::getBuildSizes(MVKDevice* device,
                                                                                 VkAccelerationStructureBuildTypeKHR type,
                                                                                 const VkAccelerationStructureBuildGeometryInfoKHR* info,
                                                                                 const uint32_t* maxPrimitiveCounts)
{
    VkAccelerationStructureBuildSizesInfoKHR vkBuildSizes{};
    
    // TODO: We can't perform host builds, throw an error?
    if (type == VK_ACCELERATION_STRUCTURE_BUILD_TYPE_HOST_KHR)
        return vkBuildSizes;
    
    MTLAccelerationStructureDescriptor* descriptor = populateMTLDescriptor(device, *info, maxPrimitiveCounts);

    MTLAccelerationStructureSizes sizes = [device->getMTLDevice() accelerationStructureSizesWithDescriptor:descriptor];
    vkBuildSizes.accelerationStructureSize = sizes.accelerationStructureSize;
    vkBuildSizes.buildScratchSize = sizes.buildScratchBufferSize;
    vkBuildSizes.updateScratchSize = sizes.refitScratchBufferSize;
    
    return vkBuildSizes;
}

uint64_t MVKAccelerationStructure::getMTLSize()
{
    if (!_built) { return 0; }
    return _accelerationStructure.size;
}

MVKAccelerationStructure::MVKAccelerationStructure(MVKDevice* device) : MVKVulkanAPIDeviceObject(device)
{
    MTLHeapDescriptor* heapDescriptor = [MTLHeapDescriptor new];
    heapDescriptor.storageMode = MTLStorageModePrivate;
//    heapDescriptor.size = getBuildSizes().accelerationStructureSize;
    _heap = [getMTLDevice() newHeapWithDescriptor:heapDescriptor];
    
//    _accelerationStructure = [_heap newAccelerationStructureWithSize:getBuildSizes().accelerationStructureSize];
//    _buffer = [_heap newBufferWithLength:getBuildSizes().accelerationStructureSize options:MTLResourceOptionCPUCacheModeDefault];
}

void MVKAccelerationStructure::destroy()
{
    [_heap release];
    _built = false;
}
