/*
 * MVKRenderPass.h
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

#pragma once

#include "MVKDevice.h"
#include <vector>

#import <Metal/Metal.h>

class MVKRenderPass;
class MVKFramebuffer;


#pragma mark -
#pragma mark MVKRenderSubpass

/** Represents a Vulkan render subpass. */
class MVKRenderSubpass : public MVKBaseObject {

public:

	/** Returns the number of color attachments, which may be zero for depth-only rendering. */
	inline uint32_t getColorAttachmentCount() { return uint32_t(_colorAttachments.size()); }

	/** Returns the format of the color attachment at the specified index. */
	VkFormat getColorAttachmentFormat(uint32_t colorAttIdx);

	/** Returns the format of the depth/stencil attachment. */
	VkFormat getDepthStencilFormat();

	/** Returns the Vulkan sample count of the attachments used in this subpass. */
	VkSampleCountFlagBits getSampleCount();

	/** 
	 * Populates the specified Metal MTLRenderPassDescriptor with content from this
	 * instance, the specified framebuffer, and the specified array of clear values.
	 */
	void populateMTLRenderPassDescriptor(MTLRenderPassDescriptor* mtlRPDesc,
										 MVKFramebuffer* framebuffer,
										 std::vector<VkClearValue>& clearValues,
										 bool isRenderingEntireAttachment);

	/**
	 * Populates the specified vector with the attachments that need to be cleared
	 * when the render area is smaller than the full framebuffer size.
	 */
	void populateClearAttachments(std::vector<VkClearAttachment>& clearAtts,
								  std::vector<VkClearValue>& clearValues);

	/** Constructs an instance for the specified parent renderpass. */
	MVKRenderSubpass(MVKRenderPass* renderPass, const VkSubpassDescription* pCreateInfo);

private:

	friend class MVKRenderPass;
	friend class MVKRenderPassAttachment;

	bool isUsingAttachmentAt(uint32_t rpAttIdx);

	MVKRenderPass* _renderPass;
	uint32_t _subpassIndex;
	std::vector<VkAttachmentReference> _inputAttachments;
	std::vector<VkAttachmentReference> _colorAttachments;
	std::vector<VkAttachmentReference> _resolveAttachments;
	std::vector<uint32_t> _preserveAttachments;
	VkAttachmentReference _depthStencilAttachment;
};


#pragma mark -
#pragma mark MVKRenderPassAttachment

/** Represents an attachment within a Vulkan render pass. */
class MVKRenderPassAttachment : public MVKBaseObject {

public:
    friend MVKRenderSubpass;

    /** Returns the Vulkan format of this attachment. */
    VkFormat getFormat();

	/** Returns the Vulkan sample count of this attachment. */
	VkSampleCountFlagBits getSampleCount();

    /**
     * Populates the specified Metal color attachment description with the load and store actions for
     * the specified render subpass, and returns whether the load action will clear the attachment.
     */
    bool populateMTLRenderPassAttachmentDescriptor(MTLRenderPassAttachmentDescriptor* mtlAttDesc,
                                                   MVKRenderSubpass* subpass,
                                                   bool isRenderingEntireAttachment,
                                                   bool hasResolveAttachment,
                                                   bool isStencil);

    /** Returns whether this attachment should be cleared in the subpass. */
    bool shouldUseClearAttachment(MVKRenderSubpass* subpass);

	/** Constructs an instance for the specified parent renderpass. */
	MVKRenderPassAttachment(MVKRenderPass* renderPass,
							const VkAttachmentDescription* pCreateInfo);

protected:
	VkAttachmentDescription _info;
	MVKRenderPass* _renderPass;
	uint32_t _attachmentIndex;
	uint32_t _firstUseSubpassIdx;
	uint32_t _lastUseSubpassIdx;
};


#pragma mark -
#pragma mark MVKRenderPass

/** Represents a Vulkan render pass. */
class MVKRenderPass : public MVKBaseDeviceObject {

public:

    /** Returns the granularity of the render area of this instance.  */
    VkExtent2D getRenderAreaGranularity();

	/** Returns the format of the color attachment at the specified index. */
	MVKRenderSubpass* getSubpass(uint32_t subpassIndex);

	/** Constructs an instance for the specified device. */
	MVKRenderPass(MVKDevice* device, const VkRenderPassCreateInfo* pCreateInfo);

private:

	friend class MVKRenderSubpass;
	friend class MVKRenderPassAttachment;

	std::vector<MVKRenderSubpass> _subpasses;
	std::vector<MVKRenderPassAttachment> _attachments;
	std::vector<VkSubpassDependency> _subpassDependencies;

};

