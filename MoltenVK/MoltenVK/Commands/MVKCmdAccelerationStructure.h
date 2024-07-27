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
#include "MVKSmallVector.h"

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
    struct MVKAccelerationStructureBuildInfo
    {
        VkAccelerationStructureBuildGeometryInfoKHR info;
        MVKSmallVector<VkAccelerationStructureGeometryKHR, 3> geometries;
        MVKSmallVector<VkAccelerationStructureBuildRangeInfoKHR, 3> ranges;
    };
protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    
    MVKSmallVector<MVKAccelerationStructureBuildInfo, 1> _buildInfos;
};

#pragma mark -
#pragma mark MVKCmdCopyAccelerationStructure

class MVKCmdCopyAccelerationStructure : public MVKCommand {
    
public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        VkAccelerationStructureKHR srcAccelerationStructure,
                        VkAccelerationStructureKHR dstAccelerationStructure,
                        VkCopyAccelerationStructureModeKHR copyMode);
    
    void encode(MVKCommandEncoder* cmdEncoder) override;
protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    id<MTLAccelerationStructure> _srcAccelerationStructure;
    id<MTLAccelerationStructure> _dstAccelerationStructure;
    
    VkCopyAccelerationStructureModeKHR _copyMode;
};

#pragma mark -
#pragma mark MVKCmdCopyAccelerationStructureToMemory

class MVKCmdCopyAccelerationStructureToMemory : public MVKCommand {
    
public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        VkAccelerationStructureKHR srcAccelerationStructure,
                        uint64_t dstAddress,
                        VkCopyAccelerationStructureModeKHR copyMode);
    
    void encode(MVKCommandEncoder* cmdEncoder) override;
protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    
    id<MTLAccelerationStructure> _srcAccelerationStructure;
    id<MTLBuffer> _srcAccelerationStructureBuffer;
    MVKBuffer* _dstBuffer;
    uint64_t _copySize;
    
    uint64_t _dstAddress;
    MVKDevice* _mvkDevice;
    VkCopyAccelerationStructureModeKHR _copyMode;
};

#pragma mark -
#pragma mark MVKCmdCopyMemoryToAccelerationStructure

class MVKCmdCopyMemoryToAccelerationStructure: public MVKCommand {
    
public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        uint64_t srcAddress,
                        VkAccelerationStructureKHR dstAccelerationStructure,
                        VkCopyAccelerationStructureModeKHR copyMode);
    
    void encode(MVKCommandEncoder* cmdEncoder) override;
protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    
    MVKBuffer* _srcBuffer;
    id<MTLAccelerationStructure> _dstAccelerationStructure;
    id<MTLBuffer> _dstAccelerationStructureBuffer;
    uint32_t _copySize;
    
    uint64_t _srcAddress;
    MVKDevice* _mvkDevice;
    VkCopyAccelerationStructureModeKHR _copyMode;
};

#pragma mark -
#pragma mark MVKCmdWriteAccelerationStructuresProperties

class MVKCmdWriteAccelerationStructuresProperties: public MVKCommand {
    
public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        uint32_t accelerationStructureCount,
                        const VkAccelerationStructureKHR* pAccelerationStructures,
                        VkQueryType queryType,
                        VkQueryPool queryPool,
                        uint32_t firstQuery);
    
    void encode(MVKCommandEncoder* cmdEncoder) override;
protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
    
    uint32_t _accelerationStructureCount;
    const MVKAccelerationStructure* _pAccelerationStructures;
    VkQueryType _queryType;
    VkQueryPool _queryPool;
    uint32_t _firstQuery;
};
