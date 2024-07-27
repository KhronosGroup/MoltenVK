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
    
    /** Populates a MTL acceleration structure descriptor given a vulkan descriptor */
    static MTLAccelerationStructureDescriptor* populateMTLDescriptor(MVKDevice* device,
                                                                     const VkAccelerationStructureBuildGeometryInfoKHR& buildInfo,
                                                                     const VkAccelerationStructureBuildRangeInfoKHR* rangeInfos,
                                                                     const uint32_t* maxPrimitiveCounts);

    /** Gets the required build sizes for acceleration structure and scratch buffer*/
    static VkAccelerationStructureBuildSizesInfoKHR getBuildSizes(MVKDevice* device,
                                                                  VkAccelerationStructureBuildTypeKHR buildType,
                                                                  const VkAccelerationStructureBuildGeometryInfoKHR* buildInfo,
                                                                  const uint32_t* maxPrimitiveCounts);
    
    /** Gets the actual size of the acceleration structure*/
    uint64_t getMTLSize();
    
#pragma mark -
#pragma mark Getters and Setters
    /** Used when building the acceleration structure, to mark whether or not an acceleration structure can be updated, only to be set by MVKCmdBuildAccelerationStructure*/
    void setAllowUpdate(bool value) { _allowUpdate = value; }
    
    /** Checks if this acceleration structure is allowed to be updated*/
    bool getAllowUpdate() const { return _allowUpdate; }
    
    /** Only to be called by the MVKCmdBuildAccelerationStructure, and sets the build status*/
    void setBuildStatus(bool value) { _built = value; }
    
    /** Checks if this acceleration structure has been built*/
    bool getBuildStatus() const { return _built; }
    
    /** Sets the address of the acceleration structure, only to be used by MVKDevice*/
    void setDeviceAddress(uint64_t address) { _address = address; }
    
    /** Gets the address of the acceleration structure*/
    uint64_t getDeviceAddress() const { return _address; }
    
    /** Returns the Metal buffer using the same memory as the acceleration structure*/
    id<MTLBuffer> getMTLBuffer() const { return _buffer; }
    
    /** Gets the heap allocation that the acceleration structure, and buffer share*/
    id<MTLHeap> getMTLHeap() const { return _heap; }
    
    MTLAccelerationStructureTriangleGeometryDescriptor* getTriangleDescriptor();
#pragma mark -
#pragma mark Construction
    MVKAccelerationStructure(MVKDevice* device);
    void destroy() override;
protected:
    void propagateDebugName() override {}
    
    id<MTLHeap> _heap;
    id<MTLAccelerationStructure> _accelerationStructure;
    id<MTLBuffer> _buffer;
    
    bool _allowUpdate = false;
    bool _built = false;
    uint64_t _address = 0;
};
