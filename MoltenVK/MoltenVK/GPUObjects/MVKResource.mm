/*
 * MVKResource.mm
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKResource.h"
#include "MVKCommandBuffer.h"


#pragma mark MVKResource

VkResult MVKResource::bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) {
	if (_deviceMemory) { _deviceMemory->removeResource(this); }

	_deviceMemory = mvkMem;
	_deviceMemoryOffset = memOffset;

	if (_deviceMemory) { _deviceMemory->addResource(this); }

	return VK_SUCCESS;
}

/**
 * Returns whether the specified global memory barrier requires a sync between this
 * texture and host memory for the purpose of the host reading texture memory.
 */
bool MVKResource::needsHostReadSync(VkPipelineStageFlags srcStageMask,
									VkPipelineStageFlags dstStageMask,
									VkMemoryBarrier* pMemoryBarrier) {
#if MVK_IOS
	return false;
#endif
#if MVK_MACOS
	return (mvkIsAnyFlagEnabled(dstStageMask, (VK_PIPELINE_STAGE_HOST_BIT)) &&
			mvkIsAnyFlagEnabled(pMemoryBarrier->dstAccessMask, (VK_ACCESS_HOST_READ_BIT)) &&
			_deviceMemory && _deviceMemory->isMemoryHostAccessible() && !_deviceMemory->isMemoryHostCoherent());
#endif
}

// Check if this resource overlaps the device memory offset and range
bool MVKResource::doesOverlap(VkDeviceSize offset, VkDeviceSize size) {
    VkDeviceSize memStart = offset;
    VkDeviceSize memEnd = memStart + size;
    VkDeviceSize rezStart = _deviceMemoryOffset;
    VkDeviceSize rezEnd = rezStart + _byteCount;

    return (memStart < rezEnd && memEnd > rezStart);
}

// Check if this resource completely contains the device memory offset and range
bool MVKResource::doesContain(VkDeviceSize offset, VkDeviceSize size) {
    VkDeviceSize memStart = offset;
    VkDeviceSize memEnd = memStart + size;
    VkDeviceSize rezStart = _deviceMemoryOffset;
    VkDeviceSize rezEnd = rezStart + _byteCount;

    return (memStart >= rezStart && memEnd <= rezEnd);
}


#pragma mark Construction

MVKResource::~MVKResource() {
    if (_deviceMemory) { _deviceMemory->removeResource(this); }
};

