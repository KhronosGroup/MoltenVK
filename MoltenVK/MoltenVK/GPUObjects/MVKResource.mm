/*
 * MVKResource.mm
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKEnvironment.h"


struct MVKBindDeviceMemoryInfo {
	VkStructureType sType;
	void* pNext;
	union {
		VkBuffer buffer;
		VkImage image;
	};
	VkDeviceMemory memory;
	VkDeviceSize memoryOffset;
};


#pragma mark MVKResource

VkResult MVKResource::bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) {
	// Don't do anything with a non-zero offset into a dedicated allocation.
	if (mvkMem && mvkMem->isDedicatedAllocation() && memOffset) {
		_deviceMemory = nullptr;
		return VK_SUCCESS;
	}
	_deviceMemory = mvkMem;
	_deviceMemoryOffset = memOffset;
	return VK_SUCCESS;
}

VkResult MVKResource::bindDeviceMemory2(const void* pBindInfo) {
	auto* mvkBindInfo = (const MVKBindDeviceMemoryInfo*)pBindInfo;
	return bindDeviceMemory((MVKDeviceMemory*)mvkBindInfo->memory, mvkBindInfo->memoryOffset);
}

// Returns whether the specified global memory barrier requires a sync between this
// texture and host memory for the purpose of the host reading texture memory.
bool MVKResource::needsHostReadSync(VkPipelineStageFlags srcStageMask,
									VkPipelineStageFlags dstStageMask,
									VkMemoryBarrier* pMemoryBarrier) {
#if MVK_IOS
	return false;
#endif
#if MVK_MACOS
	return (mvkIsAnyFlagEnabled(dstStageMask, (VK_PIPELINE_STAGE_HOST_BIT)) &&
			mvkIsAnyFlagEnabled(pMemoryBarrier->dstAccessMask, (VK_ACCESS_HOST_READ_BIT)) &&
			isMemoryHostAccessible() && !isMemoryHostCoherent());
#endif
}

