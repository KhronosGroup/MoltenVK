/*
 * MVKCmdAccelerationStructure.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKCommand.h"

#import <Metal/Metal.h>
#import <Metal/MTLAccelerationStructure.h>
#import <Metal/MTLAccelerationStructureTypes.h>

#pragma mark -
#pragma mark MVKCmdBuildAccelerationStructure

class MVKCmdBuildAccelerationStructure : public MVKCommand {
    
public:
    VkResult setContent(MVKCommandBuffer*                                       cmdBuff,
                        uint32_t                                                infoCount,
                        const VkAccelerationStructureBuildGeometryInfoKHR*      pInfos,
                        const VkAccelerationStructureBuildRangeInfoKHR* const*  ppBuildRangeInfos);
    
    void encode(MVKCommandEncoder* cmdEncoder) override;
protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    
    uint32_t _infoCount;
    VkAccelerationStructureBuildGeometryInfoKHR* _geometryInfos;
    VkAccelerationStructureBuildRangeInfoKHR const* _buildRangeInfos;
};

#pragma mark -
#pragma mark MVKCmdCopyAccelerationStructure

class MVKCmdCopyAccelerationStructure : public MVKCommand {
    
public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        VkAccelerationStructureKHR srcAccelerationStructure,
                        VkAccelerationStructureKHR dstAccelerationStructure);
    
    void encode(MVKCommandEncoder* cmdEncoder) override;
protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    
    id<MTLAccelerationStructure> _srcAccelerationStructure;
    id<MTLAccelerationStructure> _dstAccelerationStructure;
};

#pragma mark -
#pragma mark MVKCmdCopyAccelerationStructureToMemory

class MVKCmdCopyAccelerationStructureToMemory : public MVKCommand {
    
public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        VkAccelerationStructureKHR srcAccelerationStructure,
                        uint64_t dstAddress);
    
    void encode(MVKCommandEncoder* cmdEncoder) override;
protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    
    uint64_t _dstAddress;
    MVKDevice* _mvkDevice;
    id<MTLAccelerationStructure> _srcAccelerationStructure;
    id<MTLAccelerationStructure> _dstAccelerationStructure;
};
