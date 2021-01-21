/*
 * MVKVulkanAPIObject.mm
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKVulkanAPIObject.h"

using namespace std;


#pragma mark -
#pragma mark MVKVulkanAPIObject

VkResult MVKVulkanAPIObject::setDebugName(const char* pObjectName) {
	if (pObjectName) {
		[_debugName release];
		_debugName = [[NSString alloc] initWithUTF8String: pObjectName];	// retained
		propagateDebugName();
	}
	return VK_SUCCESS;
}

MVKVulkanAPIObject* MVKVulkanAPIObject::getMVKVulkanAPIObject(VkDebugReportObjectTypeEXT objType, uint64_t object) {
	void* pVkObj = (void*)object;
	switch (objType) {
		case VK_DEBUG_REPORT_OBJECT_TYPE_INSTANCE_EXT:
		case VK_DEBUG_REPORT_OBJECT_TYPE_PHYSICAL_DEVICE_EXT:
		case VK_DEBUG_REPORT_OBJECT_TYPE_DEVICE_EXT:
		case VK_DEBUG_REPORT_OBJECT_TYPE_QUEUE_EXT:
		case VK_DEBUG_REPORT_OBJECT_TYPE_COMMAND_BUFFER_EXT:
			return MVKDispatchableVulkanAPIObject::getDispatchableObject(pVkObj);
		default:
			return (MVKVulkanAPIObject*)pVkObj;
	}
}

MVKVulkanAPIObject* MVKVulkanAPIObject::getMVKVulkanAPIObject(VkObjectType objType, uint64_t objectHandle) {
	void* pVkObj = (void*)objectHandle;
	switch (objType) {
		case VK_OBJECT_TYPE_INSTANCE:
		case VK_OBJECT_TYPE_PHYSICAL_DEVICE:
		case VK_OBJECT_TYPE_DEVICE:
		case VK_OBJECT_TYPE_QUEUE:
		case VK_OBJECT_TYPE_COMMAND_BUFFER:
			return MVKDispatchableVulkanAPIObject::getDispatchableObject(pVkObj);
		default:
			return (MVKVulkanAPIObject*)pVkObj;
	}
}

MVKVulkanAPIObject::~MVKVulkanAPIObject() {
	[_debugName release];
}
