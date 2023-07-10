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
    id<MTLAccelerationStructure> srcAccelerationStructure = (id<MTLAccelerationStructure>)_geometryInfos.srcAccelerationStructure;
    id<MTLAccelerationStructure> dstAccelerationStructure = (id<MTLAccelerationStructure>)_geometryInfos.dstAccelerationStructure; // Target acceleration Structure
    
    MTLAccelerationStructureDescriptor* accStructDescriptor = [MTLAccelerationStructureDescriptor new];
    accStructDescriptor.usage = MTLAccelerationStructureUsageNone;
    /*
      * The NVIDIA extension seemed to use to provide the scratch buffer offset, but not the KHR version
      * However the KHR extension does not seem to have anything similar, for now I'll leave it 0, but
      * it should be changed.
    */
    int scratchBufferOffset = 0;
    
//    [accStructEncoder buildAccelerationStructure:dstAccelerationStructure
//                                    descriptor:accStructDescriptor
//                                    scratchBuffer:nil
//                                    scratchBufferOffset:scratchBufferOffset];
}

VkResult MVKCmdCopyAccelerationStructure::setContent(MVKCommandBuffer* cmdBuff,
                    VkAccelerationStructureKHR srcAccelerationStructure,
                    VkAccelerationStructureKHR dstAccelerationStructure) {
    
    MVKAccelerationStructure* mvkSrcAccStruct = (MVKAccelerationStructure*)srcAccelerationStructure;
    MVKAccelerationStructure* mvkDstAccStruct = (MVKAccelerationStructure*)dstAccelerationStructure;
    
    _srcAccelerationStructure = mvkSrcAccStruct->getMTLAccelerationStructure();
    _dstAccelerationStructure = mvkSrcAccStruct->getMTLAccelerationStructure();
    return VK_SUCCESS;
}

void MVKCmdCopyAccelerationStructure::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLAccelerationStructureCommandEncoder> accStructEncoder = cmdEncoder->getMTLAccelerationStructureEncoder(kMVKCommandUseNone);
    
    [accStructEncoder
     copyAccelerationStructure:_srcAccelerationStructure
     toAccelerationStructure:_dstAccelerationStructure];
}
