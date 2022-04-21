/*
 * MVKFramebuffer.h
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include <mutex>

class MVKRenderSubpass;


#pragma mark MVKFramebuffer

/** Represents a Vulkan framebuffer. */
class MVKFramebuffer : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_FRAMEBUFFER; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_FRAMEBUFFER_EXT; }

	/** Returns the dimensions of this framebuffer. */
	VkExtent2D getExtent2D() { return _extent; }

	/** Returns the layers covered by this framebuffer. */
	uint32_t getLayerCount() { return _layerCount; }

	/** Returns the attachments.  */
	MVKArrayRef<MVKImageView*> getAttachments() { return _attachments.contents(); }

	/**
	 * Returns a MTLTexture for use as a dummy texture when a render subpass,
	 * that is compatible with the specified subpass, has no attachments.
	 */
	id<MTLTexture> getDummyAttachmentMTLTexture(MVKRenderSubpass* subpass, uint32_t passIdx);

#pragma mark Construction

	MVKFramebuffer(MVKDevice* device, const VkFramebufferCreateInfo* pCreateInfo);

	~MVKFramebuffer() override;

protected:
	void propagateDebugName() override {}

	MVKSmallVector<MVKImageView*, 4> _attachments;
	id<MTLTexture> _mtlDummyTex = nil;
	std::mutex _lock;
	VkExtent2D _extent;
	uint32_t _layerCount;
};


#pragma mark -
#pragma mark Support functions

/** Returns an image-less MVKFramebuffer object created from the rendering info. */
MVKFramebuffer* mvkCreateFramebuffer(MVKDevice* device,
									 const VkRenderingInfo* pRenderingInfo,
									 MVKRenderPass* mvkRenderPass);
