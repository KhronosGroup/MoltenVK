/*
 * MVKFramebuffer.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKImage.h"
#include "MVKSmallVector.h"


#pragma mark MVKFramebuffer

/** Represents a Vulkan framebuffer. */
class MVKFramebuffer : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_FRAMEBUFFER; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_FRAMEBUFFER_EXT; }

	/** Returns the dimensions of this framebuffer. */
	inline VkExtent2D getExtent2D() { return _extent; }

	/** Returns the layers covered by this framebuffer. */
	inline uint32_t getLayerCount() { return _layerCount; }

	/** Returns the attachment at the specified index.  */
	inline MVKImageView* getAttachment(uint32_t index) { return _attachments[index]; }


#pragma mark Construction

	/** Constructs an instance for the specified device. */
	MVKFramebuffer(MVKDevice* device, const VkFramebufferCreateInfo* pCreateInfo);

protected:
	void propagateDebugName() override {}

	VkExtent2D _extent;
	uint32_t _layerCount;
	MVKSmallVector<MVKImageView*, 4> _attachments;
};

