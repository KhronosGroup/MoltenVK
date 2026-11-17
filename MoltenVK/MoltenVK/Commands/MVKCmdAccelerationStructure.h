/*
 * MVKCmdAccelerationStructure.h
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

#pragma once

#include "MVKCommand.h"
#include "MVKSmallVector.h"

class MVKAccelerationStructure;
class MVKAccelerationStructureQueryPool;

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
    struct MVKAccelerationStructureBuildInfo {
        VkAccelerationStructureBuildGeometryInfoKHR info;
        MVKSmallVector<VkAccelerationStructureGeometryKHR, 3> geometries;
        MVKSmallVector<VkAccelerationStructureBuildRangeInfoKHR, 3> ranges;
    };

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

    MVKAccelerationStructure* _srcMVKAccelerationStructure;
    MVKAccelerationStructure* _dstMVKAccelerationStructure;

    VkCopyAccelerationStructureModeKHR _copyMode;
};

#pragma mark -
#pragma mark MVKCmdWriteAccelerationStructuresProperties

class MVKCmdWriteAccelerationStructuresProperties : public MVKCommand {

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

	MVKSmallVector<MVKAccelerationStructure*, 1> _accelerationStructures;
	MVKAccelerationStructureQueryPool* _queryPool;
	VkQueryType _queryType;
	uint32_t _firstQuery;
};
