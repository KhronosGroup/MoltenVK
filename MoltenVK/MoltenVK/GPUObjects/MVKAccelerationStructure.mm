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
            
            if(mvkIsAnyFlagEnabled(info->flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)){
                accStructDescriptor.usage += MTLAccelerationStructureUsageRefit;
            }else if(mvkIsAnyFlagEnabled(info->flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
                accStructDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
            }else{
                accStructDescriptor.usage = MTLAccelerationStructureUsageNone;
            }
            break;
        }
            
        case VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR:
        {
            if(info->pGeometries->geometryType == VK_GEOMETRY_TYPE_AABBS_KHR) { return vkBuildSizes; }
            if(info->pGeometries->geometryType == VK_GEOMETRY_TYPE_INSTANCES_KHR) { return vkBuildSizes; }
            
            if(info->pGeometries->geometryType == VK_GEOMETRY_TYPE_TRIANGLES_KHR)
            {
                accStructDescriptor = [MTLPrimitiveAccelerationStructureDescriptor new];
                
                if(mvkIsAnyFlagEnabled(info->flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)){
                    accStructDescriptor.usage += MTLAccelerationStructureUsageRefit;
                }else if(mvkIsAnyFlagEnabled(info->flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
                    accStructDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
                }else{
                    accStructDescriptor.usage = MTLAccelerationStructureUsageNone;
                }
                
                VkAccelerationStructureGeometryTrianglesDataKHR triangleGeometryData = info->pGeometries->geometry.triangles;
                uint64_t vertexBDA = triangleGeometryData.vertexData.deviceAddress;
                uint64_t indexBDA = triangleGeometryData.indexData.deviceAddress;
                MVKBuffer* mvkVertexBuffer = device->getBufferAtAddress(vertexBDA);
                MVKBuffer* mvkIndexBuffer = device->getBufferAtAddress(indexBDA);
                
                MTLAccelerationStructureTriangleGeometryDescriptor* geometryTriangles = [MTLAccelerationStructureTriangleGeometryDescriptor new];
                geometryTriangles.triangleCount = info->geometryCount;
                geometryTriangles.vertexBuffer = mvkVertexBuffer->getMTLBuffer();
//                geometryTriangles.vertexBufferOffset = _buildRangeInfos[i].primitiveOffset;
                
                geometryTriangles.indexBuffer = mvkIndexBuffer->getMTLBuffer();
                geometryTriangles.indexBufferOffset = 0; // Need to get this value
                geometryTriangles.indexType = mvkMTLIndexTypeFromVkIndexType(triangleGeometryData.indexType);
//                accStructDescriptor.geometryDescriptors = @[geometryTriangles];
            }
            break;
        }
        case VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR:
        {
            MTLInstanceAccelerationStructureDescriptor* accStructInstanceBuildDescriptor = [MTLInstanceAccelerationStructureDescriptor new];
            
            if(mvkIsAnyFlagEnabled(info->flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)){
                accStructInstanceBuildDescriptor.usage += MTLAccelerationStructureUsageRefit;
            }else if(mvkIsAnyFlagEnabled(info->flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
                accStructInstanceBuildDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
            }else{
                accStructInstanceBuildDescriptor.usage = MTLAccelerationStructureUsageNone;
            }
        }
        default:
            break;
    }
    
//    MTLAccelerationStructureSizes sizes = [device->getMTLDevi ce() accelerationStructureSizesWithDescriptor:accelerationStructureDescriptor];
//    vkBuildSizes.accelerationStructureSize = sizes.accelerationStructureSize;
//    vkBuildSizes.buildScratchSize = sizes.buildScratchBufferSize;
//    vkBuildSizes.updateScratchSize = sizes.refitScratchBufferSize;
    
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
