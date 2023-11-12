/*
 * MVKCmdAccelerationStructure.mm
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

#include "MVKCmdAccelerationStructure.h"
#include "MVKCmdDebug.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"

#include "MVKAccelerationStructure.h"

#pragma mark -
#pragma mark MVKCmdBuildAccelerationStructure

VkResult MVKCmdBuildAccelerationStructure::setContent(MVKCommandBuffer*                                       cmdBuff,
                                                      uint32_t                                                infoCount,
                                                      const VkAccelerationStructureBuildGeometryInfoKHR*      pInfos,
                                                      const VkAccelerationStructureBuildRangeInfoKHR* const*  ppBuildRangeInfos) {
    VkAccelerationStructureBuildGeometryInfoKHR geoInfo = *pInfos;
    
    _mvkDevice = cmdBuff->getDevice();
    _infoCount = infoCount;
    _geometryInfos = &geoInfo;
    _buildRangeInfos = *ppBuildRangeInfos;
    
    return VK_SUCCESS;
}

void MVKCmdBuildAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseBuildAccelerationStructure);
    
    for(int i = 0; i < _infoCount; i++)
    {
        MVKAccelerationStructure* mvkSrcAccelerationStructure = (MVKAccelerationStructure*)_geometryInfos[i].srcAccelerationStructure;
        MVKAccelerationStructure* mvkDstAccelerationStructure = (MVKAccelerationStructure*)_geometryInfos[i].dstAccelerationStructure;
        
        id<MTLAccelerationStructure> srcAccelerationStructure = (id<MTLAccelerationStructure>)mvkSrcAccelerationStructure->getMTLAccelerationStructure();
        id<MTLAccelerationStructure> dstAccelerationStructure = (id<MTLAccelerationStructure>)mvkDstAccelerationStructure->getMTLAccelerationStructure();
        
        if(_geometryInfos[i].mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR && !mvkDstAccelerationStructure->getAllowUpdate())
        {
            continue;
        }
        
        MVKDevice* mvkDvc = cmdEncoder->getDevice();
        MVKBuffer* mvkBuffer = mvkDvc->getBufferAtAddress(_geometryInfos[i].scratchData.deviceAddress);
        
        id<MTLBuffer> scratchBuffer = mvkBuffer->getMTLBuffer();
        NSInteger scratchBufferOffset = mvkBuffer->getMTLBufferOffset();
        
        if(_geometryInfos[i].mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR)
        {
            if(_geometryInfos[i].type == VK_ACCELERATION_STRUCTURE_TYPE_GENERIC_KHR)
            {
                MTLAccelerationStructureDescriptor* accStructBuildDescriptor = [MTLAccelerationStructureDescriptor new];
                
                if(mvkIsAnyFlagEnabled(_geometryInfos[i].flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)){
                    accStructBuildDescriptor.usage += MTLAccelerationStructureUsageRefit;
                    mvkDstAccelerationStructure->setAllowUpdate(true);
                }else if(mvkIsAnyFlagEnabled(_geometryInfos[i].flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
                    accStructBuildDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
                }else{
                    accStructBuildDescriptor.usage = MTLAccelerationStructureUsageNone;
                }
                
                [accStructEncoder buildAccelerationStructure:dstAccelerationStructure
                                                    descriptor:accStructBuildDescriptor
                                                    scratchBuffer:scratchBuffer
                                                    scratchBufferOffset:scratchBufferOffset];
            }
            
            if(_geometryInfos[i].type == VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR)
            {
                if(_geometryInfos[i].pGeometries->geometryType == VK_GEOMETRY_TYPE_INSTANCES_KHR) { return; }
                
                if(_geometryInfos[i].pGeometries->geometryType == VK_GEOMETRY_TYPE_TRIANGLES_KHR)
                {
                    MTLPrimitiveAccelerationStructureDescriptor* accStructTriangleBuildDescriptor = [MTLPrimitiveAccelerationStructureDescriptor new];
                    
                    if(mvkIsAnyFlagEnabled(_geometryInfos[i].flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)){
                        accStructTriangleBuildDescriptor.usage += MTLAccelerationStructureUsageRefit;
                        mvkDstAccelerationStructure->setAllowUpdate(true);
                    }else if(mvkIsAnyFlagEnabled(_geometryInfos[i].flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
                        accStructTriangleBuildDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
                    }else{
                        accStructTriangleBuildDescriptor.usage = MTLAccelerationStructureUsageNone;
                    }
                    
                    VkAccelerationStructureGeometryTrianglesDataKHR triangleGeometryData = _geometryInfos[i].pGeometries->geometry.triangles;
                    uint64_t vertexBDA = triangleGeometryData.vertexData.deviceAddress;
                    uint64_t indexBDA = triangleGeometryData.indexData.deviceAddress;
                    MVKBuffer* mvkVertexBuffer = _mvkDevice->getBufferAtAddress(vertexBDA);
                    MVKBuffer* mvkIndexBuffer = _mvkDevice->getBufferAtAddress(indexBDA);
                    
                    MTLAccelerationStructureTriangleGeometryDescriptor* geometryTriangles = [MTLAccelerationStructureTriangleGeometryDescriptor new];
                    geometryTriangles.triangleCount = _geometryInfos[i].geometryCount;
                    geometryTriangles.vertexBuffer = mvkVertexBuffer->getMTLBuffer();
                    geometryTriangles.vertexBufferOffset = _buildRangeInfos[i].primitiveOffset;
                    
                    geometryTriangles.indexBuffer = mvkIndexBuffer->getMTLBuffer();
                    geometryTriangles.indexBufferOffset = 0; // Need to get this value
                    geometryTriangles.indexType = mvkMTLIndexTypeFromVkIndexType(triangleGeometryData.indexType);
                    accStructTriangleBuildDescriptor.geometryDescriptors = @[geometryTriangles];
                    
                    [accStructEncoder buildAccelerationStructure:dstAccelerationStructure
                                                      descriptor:accStructTriangleBuildDescriptor
                                                   scratchBuffer:scratchBuffer
                                             scratchBufferOffset:scratchBufferOffset];
                }
                // Need to implement AABBS
                if(_geometryInfos[i].pGeometries->geometryType == VK_GEOMETRY_TYPE_AABBS_KHR)
                {
                    MTLPrimitiveAccelerationStructureDescriptor* accStructTriangleBuildDescriptor = [MTLPrimitiveAccelerationStructureDescriptor new];
                    
                    if(mvkIsAnyFlagEnabled(_geometryInfos[i].flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)){
                        accStructTriangleBuildDescriptor.usage += MTLAccelerationStructureUsageRefit;
                        mvkDstAccelerationStructure->setAllowUpdate(true);
                    }else if(mvkIsAnyFlagEnabled(_geometryInfos[i].flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
                        accStructTriangleBuildDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
                    }else{
                        accStructTriangleBuildDescriptor.usage = MTLAccelerationStructureUsageNone;
                    }
                    
                    VkAccelerationStructureGeometryTrianglesDataKHR triangleGeometryData = _geometryInfos[i].pGeometries->geometry.triangles;
                    uint64_t vertexBDA = triangleGeometryData.vertexData.deviceAddress;
                    uint64_t indexBDA = triangleGeometryData.indexData.deviceAddress;
                    MVKBuffer* mvkVertexBuffer = _mvkDevice->getBufferAtAddress(vertexBDA);
                    MVKBuffer* mvkIndexBuffer = _mvkDevice->getBufferAtAddress(indexBDA);
                    
                    MTLAccelerationStructureTriangleGeometryDescriptor* geometryTriangles = [MTLAccelerationStructureTriangleGeometryDescriptor new];
                    geometryTriangles.triangleCount = _geometryInfos[i].geometryCount;
                    geometryTriangles.vertexBuffer = mvkVertexBuffer->getMTLBuffer();
                    geometryTriangles.vertexBufferOffset = _buildRangeInfos[i].primitiveOffset;
                    
                    geometryTriangles.indexBuffer = mvkIndexBuffer->getMTLBuffer();
                    geometryTriangles.indexBufferOffset = 0; // Need to get this value
                    geometryTriangles.indexType = mvkMTLIndexTypeFromVkIndexType(triangleGeometryData.indexType);
                    accStructTriangleBuildDescriptor.geometryDescriptors = @[geometryTriangles];
                    
                    [accStructEncoder buildAccelerationStructure:dstAccelerationStructure
                                                      descriptor:accStructTriangleBuildDescriptor
                                                   scratchBuffer:scratchBuffer
                                             scratchBufferOffset:scratchBufferOffset];
                }
            }
            
            if(_geometryInfos[i].type == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR)
            {
                MTLInstanceAccelerationStructureDescriptor* accStructInstanceBuildDescriptor = [MTLInstanceAccelerationStructureDescriptor new];
                
                if(mvkIsAnyFlagEnabled(_geometryInfos[i].flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)){
                    accStructInstanceBuildDescriptor.usage += MTLAccelerationStructureUsageRefit;
                    mvkDstAccelerationStructure->setAllowUpdate(true);
                }else if(mvkIsAnyFlagEnabled(_geometryInfos[i].flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
                    accStructInstanceBuildDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
                }else{
                    accStructInstanceBuildDescriptor.usage = MTLAccelerationStructureUsageNone;
                }
            }
        }
        
        if(_geometryInfos[i].mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR)
        {
            MTLAccelerationStructureDescriptor* accStructRefitDescriptor = [MTLAccelerationStructureDescriptor new];
            
            if(mvkIsAnyFlagEnabled(_geometryInfos[i].flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
                accStructRefitDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
            }
            
            [accStructEncoder refitAccelerationStructure:srcAccelerationStructure
                                              descriptor:accStructRefitDescriptor
                                             destination:dstAccelerationStructure
                                           scratchBuffer:scratchBuffer
                                     scratchBufferOffset:scratchBufferOffset];
        }
    }
    
    return;
}

#pragma mark -
#pragma mark MVKCmdCopyAccelerationStructure

VkResult MVKCmdCopyAccelerationStructure::setContent(MVKCommandBuffer*                  cmdBuff,
                                                     VkAccelerationStructureKHR         srcAccelerationStructure,
                                                     VkAccelerationStructureKHR         dstAccelerationStructure,
                                                     VkCopyAccelerationStructureModeKHR copyMode) {
    
    MVKAccelerationStructure* mvkSrcAccStruct = (MVKAccelerationStructure*)srcAccelerationStructure;
    MVKAccelerationStructure* mvkDstAccStruct = (MVKAccelerationStructure*)dstAccelerationStructure;
    
    _srcAccelerationStructure = mvkSrcAccStruct->getMTLAccelerationStructure();
    _dstAccelerationStructure = mvkDstAccStruct->getMTLAccelerationStructure();
    _copyMode = copyMode;
    return VK_SUCCESS;
}

void MVKCmdCopyAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseCopyAccelerationStructure);
    if(_copyMode == VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR)
    {
        [accStructEncoder
         copyAndCompactAccelerationStructure:_srcAccelerationStructure
         toAccelerationStructure:_dstAccelerationStructure];
        
        return;
    }
    
    [accStructEncoder
         copyAccelerationStructure:_srcAccelerationStructure
         toAccelerationStructure:_dstAccelerationStructure];
}

#pragma mark -
#pragma mark MVKCmdCopyAccelerationStructureToMemory

VkResult MVKCmdCopyAccelerationStructureToMemory::setContent(MVKCommandBuffer*                  cmdBuff,
                                                             VkAccelerationStructureKHR         srcAccelerationStructure,
                                                             uint64_t                           dstAddress,
                                                             VkCopyAccelerationStructureModeKHR copyMode) {
    _dstAddress = dstAddress;
    _copyMode = copyMode;
    
    MVKAccelerationStructure* mvkSrcAccStruct = (MVKAccelerationStructure*)srcAccelerationStructure;
    _srcAccelerationStructure = mvkSrcAccStruct->getMTLAccelerationStructure();
    
    _dstBuffer = _mvkDevice->getBufferAtAddress(_dstAddress);
    return VK_SUCCESS;
}
                                        
void MVKCmdCopyAccelerationStructureToMemory::encode(MVKCommandEncoder* cmdEncoder) {
    _mvkDevice = cmdEncoder->getDevice();
    
    if(_copyMode != VK_COPY_ACCELERATION_STRUCTURE_MODE_SERIALIZE_KHR || !_dstBuffer->getDeviceMemory()->isMemoryHostAccessible()){
        return;
    }
    
    memcpy(_dstBuffer->getDeviceMemory()->getHostMemoryAddress(), (void*)_srcAccelerationStructure, sizeof(_srcAccelerationStructure));
}

#pragma mark -
#pragma mark MVKCmdCopyMemoryToAccelerationStructure

VkResult MVKCmdCopyMemoryToAccelerationStructure::setContent(MVKCommandBuffer* cmdBuff,
                                                                uint64_t srcAddress,
                                                                VkAccelerationStructureKHR dstAccelerationStructure,
                                                                VkCopyAccelerationStructureModeKHR copyMode) {
    _srcAddress = srcAddress;
    _copyMode = copyMode;
    
    _srcBuffer = _mvkDevice->getBufferAtAddress(_srcAddress);
    
    MVKAccelerationStructure* mvkDstAccStruct = (MVKAccelerationStructure*)dstAccelerationStructure;
    _dstAccelerationStructure = mvkDstAccStruct->getMTLAccelerationStructure();
    return VK_SUCCESS;
}

void MVKCmdCopyMemoryToAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseCopyMemoryToAccelerationStructure);
    _mvkDevice = cmdEncoder->getDevice();
    
    if(_copyMode != VK_COPY_ACCELERATION_STRUCTURE_MODE_DESERIALIZE_KHR){
        return;
    }
    
    void* serializedAccStruct = _srcBuffer->getHostMemoryAddress();
    if(!serializedAccStruct){
        return; // Should I remove this? For this to work, the memory can't be device only, but the spec does not seem to restrict this
    }

    MVKAccelerationStructure* mvkSrcAccStruct = (MVKAccelerationStructure*)serializedAccStruct;
    id<MTLAccelerationStructure> srcAccelerationStructure = mvkSrcAccStruct->getMTLAccelerationStructure();
    
    [accStructEncoder
         copyAccelerationStructure:srcAccelerationStructure
         toAccelerationStructure:_dstAccelerationStructure];
}
