/*
 * MVKFramebuffer.h
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include <vector>


#pragma mark MVKFramebuffer

/** Represents a Vulkan framebuffer. */
class MVKFramebuffer : public MVKBaseDeviceObject {

public:

	/** Returns the dimensions of this framebuffer. */
	inline VkExtent2D getExtent2D() { return _extent; }

	/** Returns the attachment at the specified index.  */
	inline MVKImageView* getAttachment(uint32_t index) { return _attachments[index]; }


#pragma mark Construction

	/** Constructs an instance for the specified device. */
	MVKFramebuffer(MVKDevice* device, const VkFramebufferCreateInfo* pCreateInfo);

protected:
    VkExtent2D _extent;
	std::vector<MVKImageView*> _attachments;
};

