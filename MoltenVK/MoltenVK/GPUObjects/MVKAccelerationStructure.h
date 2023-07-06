/*
 * MVKAccelerationStructure.h
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

/*
 Commands that need to be implemented
 
 vkCmdBuildAccelerationStructuresIndirectKHR
 vkCmdBuildAccelerationStructuresKHR
 vkCmdCopyAccelerationStructureKHR
 vkCmdCopyAccelerationStructureToMemoryKHR
 vkCmdCopyMemoryToAccelerationStructureKHR
 vkCmdWriteAccelerationStructuresPropertiesKHR
 vkCreateAccelerationStructureKHR
 vkDestroyAccelerationStructureKHR
 vkGetAccelerationStructureBuildSizesKHR - DONE
 vkGetAccelerationStructureDeviceAddressKHR
 vkGetDeviceAccelerationStructureCompatibilityKHR
 vkWriteAccelerationStructuresPropertiesKHR
*/

#pragma once

#include "MVKVulkanAPIObject.h"

#pragma mark MVKAccelerationStructure

class MVKAccelerationStructure : public MVKVulkanAPIDeviceObject {

public:
    VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_ACCELERATION_STRUCTURE_KHR; }
    
    VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override {
        return VK_DEBUG_REPORT_OBJECT_TYPE_ACCELERATION_STRUCTURE_KHR_EXT;
    }
    
    /** Gets the required build sizes for acceleration structure and scratch buffer*/
    static VkAccelerationStructureBuildSizesInfoKHR getBuildSizes();
    
    
#pragma mark Construction
    MVKAccelerationStructure(MVKDevice* device) : MVKVulkanAPIDeviceObject(device) {}
protected:
    void propagateDebugName() override {}
};
