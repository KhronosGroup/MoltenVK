/*
 * MVKAccelerationStructure.h
 *
 * Copyright (c) 2015-2024 The Brenwill Workshop Ltd. (http://www.brenwill.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 vkGetDeviceAccelerationStructureCompatibilityKHR  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
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
 vkCreateAccelerationStructureKHR - Complete
 vkDestroyAccelerationStructureKHR - Complete
 vkGetAccelerationStructureBuildSizesKHR 
 vkGetAccelerationStructureDeviceAddressKHR  - Complete
 vkGetDeviceAccelerationStructureCompatibilityKHR  - Complete
*/

#pragma once

#include "MVKDevice.h"

#import <Metal/MTLAccelerationStructure.h>
#import <Metal/MTLAccelerationStructureTypes.h>

#pragma mark -
#pragma mark MVKAccelerationStructure

class MVKAccelerationStructure : public MVKVulkanAPIDeviceObject {
    
public:
    VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_ACCELERATION_STRUCTURE_KHR; }
    
    VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override {
        return VK_DEBUG_REPORT_OBJECT_TYPE_ACCELERATION_STRUCTURE_KHR_EXT;
    }
    
    id<MTLAccelerationStructure> getMTLAccelerationStructure();
    
    /**
     * Populates a MTL acceleration structure descriptor given a vulkan descriptor.
     * Exactly one of maxPrimitiveCounts and rangeInfos must not be nullpts.
     * It is the caller's responsibility to release the returned object.
     */
    MTLAccelerationStructureDescriptor* newMTLAccelerationStructureDescriptor(const VkAccelerationStructureBuildGeometryInfoKHR& buildInfo,
                                                                              const VkAccelerationStructureBuildRangeInfoKHR* rangeInfos,
                                                                              const uint32_t* maxPrimitiveCounts);

    /** Gets the required build sizes for acceleration structure and scratch buffer*/
    VkAccelerationStructureBuildSizesInfoKHR getBuildSizes(VkAccelerationStructureBuildTypeKHR buildType,
                                                           const VkAccelerationStructureBuildGeometryInfoKHR* buildInfo,
                                                           const uint32_t* maxPrimitiveCounts);
    
    /** Gets the address of the acceleration structure*/
    uint64_t getDeviceAddress() const { return _address; }
    
    /** Gets the actual size of the acceleration structure*/
    uint64_t getSize();
    
    /** Returns the Metal buffer using the same memory as the acceleration structure*/
    id<MTLBuffer> getMTLBuffer() const { return _buffer; }
    
	/** Constructs an empty instance for the specified device. */
    MVKAccelerationStructure(MVKDevice* device);

	/** Constructs an instance for the specified device. */
    MVKAccelerationStructure(MVKDevice* device, const VkAccelerationStructureCreateInfoKHR* pCreateInfo);

    ~MVKAccelerationStructure() override;

protected:
    friend class MVKDevice;

    void propagateDebugName() override {}
    
    id<MTLBuffer> _buffer = nil;
    id<MTLAccelerationStructure> _accelerationStructure = nil;
    
    bool _allowUpdate = false;
    uint64_t _address = 0;
    uint64_t _size = 0;
};
