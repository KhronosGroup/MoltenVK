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

#pragma mark -
#pragma mark MVKAcceleration Structure

id<MTLAccelerationStructure> MVKAccelerationStructure::getMTLAccelerationStructure() {
    return _accelerationStructure;
}

VkAccelerationStructureBuildSizesInfoKHR MVKAccelerationStructure::getBuildSizes(MVKDevice* device, VkAccelerationStructureBuildTypeKHR type, const VkAccelerationStructureBuildGeometryInfoKHR* info)
{
    VkAccelerationStructureBuildSizesInfoKHR vkBuildSizes{};
    MTLAccelerationStructureDescriptor* accStructDescriptor;
    
    if(type == VK_ACCELERATION_STRUCTURE_BUILD_TYPE_HOST_KHR) {
        // We can't do that, throw an error?
        return vkBuildSizes;
    }
    
    switch (info->type)
    {
        case VK_ACCELERATION_STRUCTURE_TYPE_GENERIC_KHR:
        {
            accStructDescriptor = [MTLAccelerationStructureDescriptor new];
            break;
        }
            
        case VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR:
        {
            if(info->pGeometries->geometryType == VK_GEOMETRY_TYPE_AABBS_KHR) 
            {
                accStructDescriptor = [MTLPrimitiveAccelerationStructureDescriptor new];
                MTLPrimitiveAccelerationStructureDescriptor* primitiveAccStructDescriptor = (MTLPrimitiveAccelerationStructureDescriptor*)accStructDescriptor;
                
                VkAccelerationStructureGeometryAabbsDataKHR aabbGeometryData = info->pGeometries->geometry.aabbs;
                uint64_t boundingBoxBDA = aabbGeometryData.data.deviceAddress;
                MVKBuffer* mvkBoundingBoxBuffer = device->getBufferAtAddress(boundingBoxBDA);
                
                MTLAccelerationStructureBoundingBoxGeometryDescriptor* geometryAABBs = [MTLAccelerationStructureBoundingBoxGeometryDescriptor new];
                geometryAABBs.boundingBoxCount = info->geometryCount;
                geometryAABBs.boundingBoxBuffer = mvkBoundingBoxBuffer->getMTLBuffer();
                geometryAABBs.boundingBoxStride = 0; // Need to get this
                geometryAABBs.boundingBoxBufferOffset = mvkBoundingBoxBuffer->getMTLBufferOffset();
                primitiveAccStructDescriptor.geometryDescriptors = @[geometryAABBs];
                break;
                
            }
            if(info->pGeometries->geometryType == VK_GEOMETRY_TYPE_INSTANCES_KHR) { return vkBuildSizes; }
            
            if(info->pGeometries->geometryType == VK_GEOMETRY_TYPE_TRIANGLES_KHR)
            {
                accStructDescriptor = [MTLPrimitiveAccelerationStructureDescriptor new];
                MTLPrimitiveAccelerationStructureDescriptor* primitiveAccStructDescriptor = (MTLPrimitiveAccelerationStructureDescriptor*)accStructDescriptor;
                
                VkAccelerationStructureGeometryTrianglesDataKHR triangleGeometryData = info->pGeometries->geometry.triangles;
                uint64_t vertexBDA = triangleGeometryData.vertexData.deviceAddress;
                uint64_t indexBDA = triangleGeometryData.indexData.deviceAddress;
                MVKBuffer* mvkVertexBuffer = device->getBufferAtAddress(vertexBDA);
                MVKBuffer* mvkIndexBuffer = device->getBufferAtAddress(indexBDA);
                
                MTLAccelerationStructureTriangleGeometryDescriptor* geometryTriangles = [MTLAccelerationStructureTriangleGeometryDescriptor new];
                geometryTriangles.triangleCount = info->geometryCount;
                geometryTriangles.vertexBuffer = mvkVertexBuffer->getMTLBuffer();
                geometryTriangles.vertexBufferOffset = mvkVertexBuffer->getMTLBufferOffset();
                
                geometryTriangles.indexBuffer = mvkIndexBuffer->getMTLBuffer();
                geometryTriangles.indexBufferOffset = mvkIndexBuffer->getMTLBufferOffset();
                geometryTriangles.indexType = mvkMTLIndexTypeFromVkIndexType(triangleGeometryData.indexType);
                primitiveAccStructDescriptor.geometryDescriptors = @[geometryTriangles];
                break;
            }
            else
            {
                accStructDescriptor = [MTLPrimitiveAccelerationStructureDescriptor new];
            }
            break;
        }
        case VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR:
        {
            accStructDescriptor = [MTLInstanceAccelerationStructureDescriptor new];
            MTLInstanceAccelerationStructureDescriptor* instanceAccStructDescriptor = (MTLInstanceAccelerationStructureDescriptor*)accStructDescriptor;
            
            instanceAccStructDescriptor.instanceDescriptorType = MTLAccelerationStructureInstanceDescriptorTypeDefault;
        }
        default:
            accStructDescriptor = [MTLAccelerationStructureDescriptor new];
            break;
    }
    
    if(mvkIsAnyFlagEnabled(info->flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)){
        accStructDescriptor.usage += MTLAccelerationStructureUsageRefit;
    }else if(mvkIsAnyFlagEnabled(info->flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
        accStructDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
    }else{
        accStructDescriptor.usage = MTLAccelerationStructureUsageNone;
    }
    
    MTLAccelerationStructureSizes sizes = [device->getMTLDevice() accelerationStructureSizesWithDescriptor: accStructDescriptor];
    vkBuildSizes.accelerationStructureSize = sizes.accelerationStructureSize;
    vkBuildSizes.buildScratchSize = sizes.buildScratchBufferSize;
    vkBuildSizes.updateScratchSize = sizes.refitScratchBufferSize;
    
    return vkBuildSizes;
}

uint64_t MVKAccelerationStructure::getMTLSize()
{
    if(!_built) { return 0; }
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
