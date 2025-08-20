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
#include "MVKFoundation.h"

#include <Metal/Metal.h>

#pragma mark -
#pragma mark MVKCmdBuildAccelerationStructure

VkResult MVKCmdBuildAccelerationStructure::setContent(MVKCommandBuffer* cmdBuff,
                                                      uint32_t infoCount,
                                                      const VkAccelerationStructureBuildGeometryInfoKHR* pInfos,
                                                      const VkAccelerationStructureBuildRangeInfoKHR* const* ppBuildRangeInfos) {
    _buildInfos.clear();
    _buildInfos.reserve(infoCount);
    for (uint32_t i = 0; i < infoCount; i++) {
        MVKAccelerationStructureBuildInfo& info = _buildInfos.emplace_back();
        info.info = pInfos[i];

        // TODO: ppGeometries
        info.geometries.reserve(pInfos[i].geometryCount);
        info.ranges.reserve(pInfos[i].geometryCount);
        memcpy(info.geometries.data(), pInfos[i].pGeometries, pInfos[i].geometryCount * sizeof(VkAccelerationStructureGeometryKHR));
        memcpy(info.ranges.data(), ppBuildRangeInfos[i], pInfos[i].geometryCount * sizeof(VkAccelerationStructureBuildRangeInfoKHR));

        info.info.pGeometries = info.geometries.data();
    }

    return VK_SUCCESS;
}

void MVKCmdBuildAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
    for (MVKAccelerationStructureBuildInfo& entry : _buildInfos) {
        const auto& buildInfo = entry.info;
        const auto& ranges = entry.ranges;

        MVKAccelerationStructure* mvkDstAccStruct = (MVKAccelerationStructure*)buildInfo.dstAccelerationStructure;
        id<MTLAccelerationStructure> dstAccStruct = mvkDstAccStruct->getMTLAccelerationStructure();
        
        MVKDevice* mvkDevice = cmdEncoder->getDevice();
        MVKBuffer* mvkBuffer = mvkDevice->getBufferAtAddress(buildInfo.scratchData.deviceAddress);

        // TODO: throw error if mvkBuffer is null?
        
        id<MTLBuffer> scratchBuffer = mvkBuffer->getMTLBuffer();
        NSInteger scratchBufferOffset = mvkBuffer->getMTLBufferOffset();
        
        if (buildInfo.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR) {
            MTLAccelerationStructureDescriptor* descriptor = mvkDstAccStruct->newMTLAccelerationStructureDescriptor(buildInfo, entry.ranges.data(), nullptr);

            id<MTLFence> fence = nil;
            if (buildInfo.type == VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) {
                // Only one geometry, validated in populateMTLDescriptor

                // TODO: handle instances.arrayOfPointers == true
                // TODO: ppGeometries
                const VkAccelerationStructureGeometryInstancesDataKHR& instancesData = buildInfo.pGeometries[0].geometry.instances;
                uint64_t instancesBDA = instancesData.data.deviceAddress;
                MVKBuffer* mvkInstancesBuffer = cmdEncoder->getDevice()->getBufferAtAddress(instancesBDA);
                NSUInteger bOffset = (instancesBDA - mvkInstancesBuffer->getMTLBufferGPUAddress()) + mvkInstancesBuffer->getMTLBufferOffset();

                // Allocate a transient buffer to store converted instance data
                NSUInteger tmpBuffSize = sizeof(MTLAccelerationStructureInstanceDescriptor) * ranges[0].primitiveCount;
                const MVKMTLBufferAllocation* tmpBuff = cmdEncoder->getTempMTLBuffer(tmpBuffSize, true);

                ((MTLInstanceAccelerationStructureDescriptor*)descriptor).instanceDescriptorBuffer = tmpBuff->_mtlBuffer;
                ((MTLInstanceAccelerationStructureDescriptor*)descriptor).instanceDescriptorBufferOffset = tmpBuff->_offset;

                // Dispatch compute pipeline to convert instance data
                uint32_t srcStride = sizeof(VkAccelerationStructureInstanceKHR);
                uint32_t instanceCount = ranges[0].primitiveCount;
                id<MTLComputeCommandEncoder> mtlConvertEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseBuildAccelerationStructureConvertBuffers);
                id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdBuildAccelerationStructureConvertBuffersMTLComputePipelineState();
                [mtlConvertEncoder setComputePipelineState: mtlConvertState];
                [mtlConvertEncoder setBuffer: mvkInstancesBuffer->getMTLBuffer()
                                      offset: bOffset
                                     atIndex: 0];
                [mtlConvertEncoder setBuffer: tmpBuff->_mtlBuffer
                                      offset: tmpBuff->_offset
                                     atIndex: 1];
                cmdEncoder->setComputeBytes(mtlConvertEncoder,
                                            &srcStride,
                                            sizeof(srcStride),
                                            2);
                cmdEncoder->setComputeBytes(mtlConvertEncoder,
                                            &instanceCount,
                                            sizeof(instanceCount),
                                            3);

                if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
                    [mtlConvertEncoder dispatchThreads: MTLSizeMake(instanceCount, 1, 1)
                                 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                } else {
                    [mtlConvertEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(instanceCount, mtlConvertState.threadExecutionWidth), 1, 1)
                                      threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                }
    
                // We (probably) need to insert an explicit fence here. It is not exactly clear what is going on, but based on
                // the Metal debugger, Metal does not recognize the read-write dependency between the tmpBuff and the build command.
                // Thus, we need to explicitly synchronize.
                fence = [cmdEncoder->getMTLDevice() newFence];
                [mtlConvertEncoder updateFence:fence];
                [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer>) { [fence release]; }];
            }

            id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseBuildAccelerationStructure);

            if (fence)
                [accStructEncoder waitForFence:fence];

            [accStructEncoder buildAccelerationStructure:dstAccStruct
                                              descriptor:descriptor
                                           scratchBuffer:scratchBuffer
                                     scratchBufferOffset:scratchBufferOffset];

            [descriptor release];
        }
        else if (buildInfo.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR) {
            // TODO: check if we are allowed to update, not sure if validation layers handle this

            MTLAccelerationStructureDescriptor* descriptor = [MTLAccelerationStructureDescriptor new];

            MVKAccelerationStructure* mvkSrcAccStruct = (MVKAccelerationStructure*)buildInfo.srcAccelerationStructure;
            id<MTLAccelerationStructure> srcAccStruct = mvkSrcAccStruct->getMTLAccelerationStructure();
            
            if (mvkIsAnyFlagEnabled(buildInfo.flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR))
                descriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
            
            id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseBuildAccelerationStructure);
            [accStructEncoder refitAccelerationStructure:srcAccStruct
                                              descriptor:descriptor
                                             destination:dstAccStruct
                                           scratchBuffer:scratchBuffer
                                     scratchBufferOffset:scratchBufferOffset];

            [descriptor release];
        }
    }
}

#pragma mark -
#pragma mark MVKCmdCopyAccelerationStructure

VkResult MVKCmdCopyAccelerationStructure::setContent(MVKCommandBuffer* cmdBuff,
                                                     VkAccelerationStructureKHR srcAccelerationStructure,
                                                     VkAccelerationStructureKHR dstAccelerationStructure,
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

    // TODO: other copy modes

    if(_copyMode == VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR) {
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

VkResult MVKCmdCopyAccelerationStructureToMemory::setContent(MVKCommandBuffer* cmdBuff,
                                                             VkAccelerationStructureKHR srcAccelerationStructure,
                                                             uint64_t dstAddress,
                                                             VkCopyAccelerationStructureModeKHR copyMode) {
    
    MVKAccelerationStructure* mvkSrcAccStruct = (MVKAccelerationStructure*)srcAccelerationStructure;

    _copyMode = copyMode;
    _srcBuffer = mvkSrcAccStruct->getMTLBuffer();
    _dstBuffer = cmdBuff->getDevice()->getBufferAtAddress(dstAddress);

    return VK_SUCCESS;
}
                                        
void MVKCmdCopyAccelerationStructureToMemory::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLBlitCommandEncoder> blitEncoder = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructureToMemory);
    
    [blitEncoder copyFromBuffer:_srcBuffer
                   sourceOffset:0
                       toBuffer:_dstBuffer->getMTLBuffer()
              destinationOffset:_dstBuffer->getMTLBufferOffset()
                           size:_copySize];
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
    _dstAccelerationStructureBuffer = mvkDstAccStruct->getMTLBuffer();
    return VK_SUCCESS;
}

void MVKCmdCopyMemoryToAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLBlitCommandEncoder> blitEncoder = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyAccelerationStructureToMemory);
    _mvkDevice = cmdEncoder->getDevice();
    
    [blitEncoder copyFromBuffer:_srcBuffer->getMTLBuffer() sourceOffset:0 toBuffer:_dstAccelerationStructureBuffer destinationOffset:0 size:_copySize];
}

#pragma mark -
#pragma mark MVKCmdWriteAccelerationStructuresProperties

VkResult MVKCmdWriteAccelerationStructuresProperties::setContent(MVKCommandBuffer* cmdBuff,
                                                                 uint32_t accelerationStructureCount,
                                                                 const VkAccelerationStructureKHR* pAccelerationStructures,
                                                                 VkQueryType queryType,
                                                                 VkQueryPool queryPool,
                                                                 uint32_t firstQuery) {
    
    _accelerationStructureCount = accelerationStructureCount;
    _pAccelerationStructures = (const MVKAccelerationStructure*)pAccelerationStructures;
    _queryType = queryType;
    _queryPool = queryPool;
    _firstQuery = firstQuery;
    return VK_SUCCESS;
}

void MVKCmdWriteAccelerationStructuresProperties::encode(MVKCommandEncoder* cmdEncoder) {
    
    for(int i = 0; i < _accelerationStructureCount; i++) {
        // actually finish up the meat of the code here
    }
    
    switch(_queryType) {
        case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SIZE_KHR:
            break;
        case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SERIALIZATION_BOTTOM_LEVEL_POINTERS_KHR:
            break;
        case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR:
            break;
        case VK_QUERY_TYPE_ACCELERATION_STRUCTURE_SERIALIZATION_SIZE_KHR:
            break;
        default:
            break;
    }
}
