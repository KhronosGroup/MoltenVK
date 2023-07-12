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
    _infoCount = infoCount;
    _geometryInfos = *pInfos;
    _buildRangeInfos = *ppBuildRangeInfos;
    
    return VK_SUCCESS;
}

void MVKCmdBuildAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseNone);
    
    MVKAccelerationStructure* mvkSrcAccelerationStructure = (MVKAccelerationStructure*)_geometryInfos.srcAccelerationStructure;
    MVKAccelerationStructure* mvkDstAccelerationStructure =    (MVKAccelerationStructure*)_geometryInfos.dstAccelerationStructure;
    
    id<MTLAccelerationStructure> srcAccelerationStructure = (id<MTLAccelerationStructure>)mvkSrcAccelerationStructure->getMTLAccelerationStructure();
    id<MTLAccelerationStructure> dstAccelerationStructure = (id<MTLAccelerationStructure>)mvkDstAccelerationStructure->getMTLAccelerationStructure();
    
    if(_geometryInfos.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR && !mvkDstAccelerationStructure->getAllowUpdate())
    {
        return;
    }
    
    MVKDevice* mvkDvc = cmdEncoder->getDevice();
    MVKBuffer* mvkBuffer = mvkDvc->getBufferAtAddress(_geometryInfos.scratchData.deviceAddress);
    
    id<MTLBuffer> scratchBuffer = mvkBuffer->getMTLBuffer();
    NSInteger scratchBufferOffset = mvkBuffer->getMTLBufferOffset();
    
    if(_geometryInfos.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR)
    {
        MTLAccelerationStructureDescriptor* accStructBuildDescriptor = [MTLAccelerationStructureDescriptor new];
        
        if(mvkIsAnyFlagEnabled(_geometryInfos.flags, VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_UPDATE_BIT_KHR)){
            accStructBuildDescriptor.usage += MTLAccelerationStructureUsageRefit;
            mvkDstAccelerationStructure->setAllowUpdate(true);
        }else if(mvkIsAnyFlagEnabled(_geometryInfos.flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
            accStructBuildDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
        }else{
            accStructBuildDescriptor.usage = MTLAccelerationStructureUsageNone;
        }
        
        [accStructEncoder buildAccelerationStructure:dstAccelerationStructure
                                descriptor:accStructBuildDescriptor
                                scratchBuffer:scratchBuffer
                                scratchBufferOffset:scratchBufferOffset];
        return;
    }
    
    if(_geometryInfos.mode == VK_BUILD_ACCELERATION_STRUCTURE_MODE_UPDATE_KHR)
    {
        MTLAccelerationStructureDescriptor* accStructRefitDescriptor = [MTLAccelerationStructureDescriptor new];
        
        if(mvkIsAnyFlagEnabled(_geometryInfos.flags, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR)){
            accStructRefitDescriptor.usage += MTLAccelerationStructureUsagePreferFastBuild;
        }
        
        [accStructEncoder refitAccelerationStructure:srcAccelerationStructure
                            descriptor:accStructRefitDescriptor
                            destination:dstAccelerationStructure
                            scratchBuffer:scratchBuffer
                            scratchBufferOffset:scratchBufferOffset];
        
        return;
    }
    
    return;
}

#pragma mark -
#pragma mark MVKCmdCopyAccelerationStructure

VkResult MVKCmdCopyAccelerationStructure::setContent(MVKCommandBuffer* cmdBuff,
                    VkAccelerationStructureKHR srcAccelerationStructure,
                    VkAccelerationStructureKHR dstAccelerationStructure) {
    
    MVKAccelerationStructure* mvkSrcAccStruct = (MVKAccelerationStructure*)srcAccelerationStructure;
    MVKAccelerationStructure* mvkDstAccStruct = (MVKAccelerationStructure*)dstAccelerationStructure;
    
    _srcAccelerationStructure = mvkSrcAccStruct->getMTLAccelerationStructure();
    _dstAccelerationStructure = mvkDstAccStruct->getMTLAccelerationStructure();
    return VK_SUCCESS;
}

void MVKCmdCopyAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseNone);
    
    [accStructEncoder
     copyAccelerationStructure:_srcAccelerationStructure
     toAccelerationStructure:_dstAccelerationStructure];
}
