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
 vkCmdBuildAccelerationStructuresKHR - DONE
 vkCmdCopyAccelerationStructureKHR - DONE
 vkCmdCopyAccelerationStructureToMemoryKHR - DONE
 vkCmdCopyMemoryToAccelerationStructureKHR - DONE
 vkCmdWriteAccelerationStructuresPropertiesKHR
 vkCreateAccelerationStructureKHR - DONE
 vkDestroyAccelerationStructureKHR - DONE
 vkGetAccelerationStructureBuildSizesKHR - DONE
 vkGetAccelerationStructureDeviceAddressKHR - DONE
 vkGetDeviceAccelerationStructureCompatibilityKHR - DONE
*/

#pragma once

#include "MVKVulkanAPIObject.h"

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
    
    /** Gets the required build sizes for acceleration structure and scratch buffer*/
    static VkAccelerationStructureBuildSizesInfoKHR getBuildSizes();
    
    /** Gets the actual size of the acceleration structure*/
    uint64_t getMTLSize();

#pragma mark -
#pragma mark Getters and Setters
    /** Used when building the acceleration structure, to mark whether or not an acceleration structure can be updated, only to be set by MVKCmdBuildAccelerationStructure*/
    void setAllowUpdate(bool value) { _allowUpdate = value; }
    
    /** Checks if this acceleration structure is allowed to be updated*/
    bool getAllowUpdate() { return _allowUpdate; }
    
    /** Only to be called by the MVKCmdBuildAccelerationStructure, and sets the build status*/
    void setBuildStatus(bool value) { _built = value; }
    
    /** Checks if this acceleration structure has been built*/
    bool getBuildStatus() { return _built; }
    
    /** Sets the address of the acceleration structure, only to be used by MVKDevice*/
    void setDeviceAddress(uint64_t address) { _address = address; }
    
    /** Gets the address of the acceleration structure*/
    uint64_t getDeviceAddress() { return _address; }
    
    /** Returns the Metal buffer using the same memory as the acceleration structure*/
    MVKBuffer* getMVKBuffer() { return _buffer; }
    
    /** Gets the heap allocation that the acceleration structure, and buffer share*/
    id<MTLHeap> getMTLHeap() { return _heap; }
#pragma mark -
#pragma mark Construction
    MVKAccelerationStructure(MVKDevice* device) : MVKVulkanAPIDeviceObject(device) {}
    
    void destroy() override;
protected:
    void propagateDebugName() override {}
    
    id<MTLAccelerationStructure> _accelerationStructure;
    MVKBuffer* _buffer;
    id<MTLHeap> _heap;
    
    bool _allowUpdate = false;
    bool _built = false;
    uint64_t _address = 0;
};
