/*
 * MVKAccelerationStructure.mm
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

#include "MVKDevice.h"
#include "MVKAccelerationStructure.h"

#pragma mark -
#pragma mark MVKAcceleration Structure

id<MTLAccelerationStructure> MVKAccelerationStructure::getMTLAccelerationStructure() {
    return _accelerationStructure;
}

VkAccelerationStructureBuildSizesInfoKHR MVKAccelerationStructure::getBuildSizes()
{
    VkAccelerationStructureBuildSizesInfoKHR vkBuildSizes{};
        
    MTLAccelerationStructureSizes mtlBuildSizes;
    vkBuildSizes.accelerationStructureSize = mtlBuildSizes.accelerationStructureSize;
    vkBuildSizes.buildScratchSize = mtlBuildSizes.buildScratchBufferSize;
    vkBuildSizes.updateScratchSize = mtlBuildSizes.refitScratchBufferSize;
    
    return vkBuildSizes;
}

uint64_t MVKAccelerationStructure::getMTLSize()
{
    if(!_built) { return 0; }
    return _accelerationStructure.size;
}

void MVKAccelerationStructure::destroy()
{
    // TODO
    _built = false;
}
