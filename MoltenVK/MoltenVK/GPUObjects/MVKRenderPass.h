/*
 * MVKRenderPass.h
 *
 * Copyright (c) 2015-2024 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKSmallVector.h"

#import <Metal/Metal.h>

class MVKRenderPass;
class MVKFramebuffer;
class MVKCommandEncoder;


// Parameters to define the sizing of inline collections
const static uint32_t kMVKDefaultAttachmentCount = 8;

/** Collection of attachment clears . */
typedef MVKSmallVector<VkClearAttachment, kMVKDefaultAttachmentCount> MVKClearAttachments;

#pragma mark -
#pragma mark MVKRenderSubpass

/** Represents a Vulkan render subpass. */
class MVKRenderSubpass : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

	/** Returns the parent render pass of this subpass. */
	MVKRenderPass* getRenderPass() { return _renderPass; }

	/** Returns the index of this subpass in its parent render pass. */
	uint32_t getSubpassIndex() { return _subpassIndex; }

	/** Returns whether this subpass has any color attachments. */
	bool hasColorAttachments();

	/** Returns the number of color attachments, which may be zero for depth-only rendering. */
	uint32_t getColorAttachmentCount() { return uint32_t(_colorAttachments.size()); }

	/** Returns the format of the color attachment at the specified index. */
	VkFormat getColorAttachmentFormat(uint32_t colorAttIdx);

	/** Returns whether or not the color attachment at the specified index is being used. */
	bool isColorAttachmentUsed(uint32_t colorAttIdx);

	/** Returns whether or not the color attachment is used as both a color attachment and an input attachment. */
	bool isColorAttachmentAlsoInputAttachment(uint32_t colorAttIdx);

	/** Returns whether or not the depth attachment is being used. */
	bool isDepthAttachmentUsed() { return _depthAttachment.attachment != VK_ATTACHMENT_UNUSED; }

	/** Returns whether or not the stencil attachment is being used. */
	bool isStencilAttachmentUsed() { return _stencilAttachment.attachment != VK_ATTACHMENT_UNUSED; }

	/** Return the depth attachment format. */
	VkFormat getDepthFormat();

	/** Return the stencil attachment format. */
	VkFormat getStencilFormat();

	/** Returns the Vulkan sample count of the attachments used in this subpass. */
	VkSampleCountFlagBits getSampleCount();

	/** Returns the default sample count for when there are no attachments used in this subpass. */
	VkSampleCountFlagBits getDefaultSampleCount() { return _defaultSampleCount; }

	/** Sets the default sample count for when there are no attachments used in this subpass. */
	void setDefaultSampleCount(VkSampleCountFlagBits count) { _defaultSampleCount = count; }

	/** Returns whether or not this is a multiview subpass. */
	bool isMultiview() const { return _pipelineRenderingCreateInfo.viewMask != 0; }

	/** Returns the multiview view mask. */
	uint32_t getViewMask() const { return _pipelineRenderingCreateInfo.viewMask; }

	/** Returns the number of Metal render passes needed to render all views. */
	uint32_t getMultiviewMetalPassCount() const;

	/** Returns the first view to be rendered in the given multiview pass. */
	uint32_t getFirstViewIndexInMetalPass(uint32_t passIdx) const;

	/** Returns the number of views to be rendered in the given multiview pass. */
	uint32_t getViewCountInMetalPass(uint32_t passIdx) const;

	/** Returns the number of views to be rendered in all multiview passes up to the given one. */
	uint32_t getViewCountUpToMetalPass(uint32_t passIdx) const;

	/** Returns pipeline rendering create info that describes this subpass. */
	const VkPipelineRenderingCreateInfo* getPipelineRenderingCreateInfo() { return &_pipelineRenderingCreateInfo; }

	/** 
	 * Populates the specified Metal MTLRenderPassDescriptor with content from this
	 * instance, the specified framebuffer, and the specified array of clear values
	 * for the specified multiview pass.
	 */
	void populateMTLRenderPassDescriptor(MTLRenderPassDescriptor* mtlRPDesc,
										 uint32_t passIdx,
										 MVKFramebuffer* framebuffer,
										 MVKArrayRef<MVKImageView*const> attachments,
										 MVKArrayRef<const VkClearValue> clearValues,
										 bool isRenderingEntireAttachment,
                                         bool loadOverride = false);

	/**
	 * Populates the specified vector with the attachments that need to be cleared
	 * when the render area is smaller than the full framebuffer size.
	 */
	void populateClearAttachments(MVKClearAttachments& clearAtts,
								  MVKArrayRef<const VkClearValue> clearValues);

	/**
	 * Populates the specified vector with VkClearRects for clearing views of a specified multiview
	 * attachment on first use, when the render area is smaller than the full framebuffer size
	 * and/or not all views used in this subpass need to be cleared.
	 */
	void populateMultiviewClearRects(MVKSmallVector<VkClearRect, 1>& clearRects,
									 MVKCommandEncoder* cmdEncoder,
									 uint32_t caIdx, VkImageAspectFlags aspectMask);

	/** If a render encoder is active, sets the store actions for all attachments to it. */
	void encodeStoreActions(MVKCommandEncoder* cmdEncoder,
							bool isRenderingEntireAttachment,
							MVKArrayRef<MVKImageView*const> attachments,
							bool storeOverride = false);

	/** Resolves any resolve attachments that cannot be handled by native Metal subpass resolve behavior. */
	void resolveUnresolvableAttachments(MVKCommandEncoder* cmdEncoder, MVKArrayRef<MVKImageView*const> attachments);

	MVKRenderSubpass(MVKRenderPass* renderPass, const VkSubpassDescription* pCreateInfo,
					 const VkRenderPassInputAttachmentAspectCreateInfo* pInputAspects,
					 uint32_t viewMask);

	MVKRenderSubpass(MVKRenderPass* renderPass, const VkSubpassDescription2* pCreateInfo);

	MVKRenderSubpass(MVKRenderPass* renderPass, const VkRenderingInfo* pRenderingInfo);

protected:
	friend class MVKRenderPass;
	friend class MVKAttachmentDescription;

	uint32_t getViewMaskGroupForMetalPass(uint32_t passIdx);
	MVKMTLFmtCaps getRequiredFormatCapabilitiesForAttachmentAt(uint32_t rpAttIdx);
	void populatePipelineRenderingCreateInfo();

	MVKRenderPass* _renderPass;
	MVKSmallVector<VkAttachmentReference2, kMVKDefaultAttachmentCount> _inputAttachments;
	MVKSmallVector<VkAttachmentReference2, kMVKDefaultAttachmentCount> _colorAttachments;
	MVKSmallVector<VkAttachmentReference2, kMVKDefaultAttachmentCount> _resolveAttachments;
	MVKSmallVector<uint32_t, kMVKDefaultAttachmentCount> _preserveAttachments;
	MVKSmallVector<VkFormat, kMVKDefaultAttachmentCount> _colorAttachmentFormats;
	VkPipelineRenderingCreateInfo _pipelineRenderingCreateInfo;
	VkAttachmentReference2 _depthAttachment;
	VkAttachmentReference2 _stencilAttachment;
	VkAttachmentReference2 _depthResolveAttachment;
	VkAttachmentReference2 _stencilResolveAttachment;
	VkResolveModeFlagBits _depthResolveMode = VK_RESOLVE_MODE_NONE;
	VkResolveModeFlagBits _stencilResolveMode = VK_RESOLVE_MODE_NONE;
	VkSampleCountFlagBits _defaultSampleCount = VK_SAMPLE_COUNT_1_BIT;
	uint32_t _subpassIndex;
};


#pragma mark -
#pragma mark MVKAttachmentDescription

/** Represents an attachment within a Vulkan render pass. */
class MVKAttachmentDescription : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

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
												   MVKImageView* attachment,
                                                   bool isRenderingEntireAttachment,
												   bool hasResolveAttachment,
												   bool canResolveFormat,
                                                   bool isStencil,
                                                   bool loadOverride);

	/** If a render encoder is active, sets the store action for this attachment to it. */
	void encodeStoreAction(MVKCommandEncoder* cmdEncoder,
						   MVKRenderSubpass* subpass,
						   MVKImageView* attachment,
						   bool isRenderingEntireAttachment,
						   bool hasResolveAttachment,
						   bool canResolveFormat,
						   uint32_t caIdx,
					   	   bool isStencil,
						   bool storeOverride = false);

	/** Populates the specified vector with VkClearRects for clearing views of a multiview attachment on first use. */
	void populateMultiviewClearRects(MVKSmallVector<VkClearRect, 1>& clearRects, MVKCommandEncoder* cmdEncoder);

    /** Returns whether this attachment should be cleared in the subpass. */
    bool shouldClearAttachment(MVKRenderSubpass* subpass, bool isStencil);

	MVKAttachmentDescription(MVKRenderPass* renderPass,
							const VkAttachmentDescription* pCreateInfo);

	MVKAttachmentDescription(MVKRenderPass* renderPass,
							const VkAttachmentDescription2* pCreateInfo);

	MVKAttachmentDescription(MVKRenderPass* renderPass,
							const VkRenderingAttachmentInfo* pAttInfo,
							bool isResolveAttachment);

protected:
	friend class MVKRenderPass;
	friend class MVKRenderSubpass;

	bool isFirstUseOfAttachment(MVKRenderSubpass* subpass);
	bool isLastUseOfAttachment(MVKRenderSubpass* subpass);
	MTLStoreAction getMTLStoreAction(MVKRenderSubpass* subpass,
									 bool isRenderingEntireAttachment,
									 bool isMemorylessAttachment,
									 bool hasResolveAttachment,
									 bool canResolveFormat,
									 bool isStencil,
									 bool storeOverride);
	void linkToSubpasses();

	VkAttachmentDescription2 _info;
	MVKRenderPass* _renderPass;
	uint32_t _attachmentIndex;
	uint32_t _firstUseSubpassIdx;
	uint32_t _lastUseSubpassIdx;
	MVKSmallVector<uint32_t> _firstUseViewMasks;
	MVKSmallVector<uint32_t> _lastUseViewMasks;
};


#pragma mark -
#pragma mark MVKRenderPass

/** Collects together VkSubpassDependency and VkMemoryBarrier2. */
typedef struct MVKSubpassDependency {
	uint32_t              srcSubpass;
	uint32_t              dstSubpass;
	VkPipelineStageFlags2 srcStageMask;
	VkPipelineStageFlags2 dstStageMask;
	VkAccessFlags2        srcAccessMask;
	VkAccessFlags2        dstAccessMask;
	VkDependencyFlags     dependencyFlags;
	int32_t               viewOffset;

	MVKSubpassDependency(const VkSubpassDependency& spDep, int32_t viewOffset);
	MVKSubpassDependency(const VkSubpassDependency2& spDep, const VkMemoryBarrier2* pMemBar);

} MVKSubpassDependency;

/** Represents a Vulkan render pass. */
class MVKRenderPass : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_RENDER_PASS; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_RENDER_PASS_EXT; }

    /** Returns the granularity of the render area of this instance.  */
    VkExtent2D getRenderAreaGranularity();

	/** Returns the number of subpasses. */
	size_t getSubpassCount() { return _subpasses.size(); }

	/** Returns the subpass at the specified index. */
	MVKRenderSubpass* getSubpass(uint32_t subpassIndex) { return &_subpasses[subpassIndex]; }

	/** Returns whether or not this render pass is a multiview render pass. */
	bool isMultiview() const;

	/** Returns the dynamic rendering flags. */
	VkRenderingFlags getRenderingFlags() { return _renderingFlags; }

	/** Sets the dynamic rendering flags. */
	void setRenderingFlags(VkRenderingFlags renderingFlags) { _renderingFlags = renderingFlags; }

	MVKRenderPass(MVKDevice* device, const VkRenderPassCreateInfo* pCreateInfo);

	MVKRenderPass(MVKDevice* device, const VkRenderPassCreateInfo2* pCreateInfo);

	MVKRenderPass(MVKDevice* device, const VkRenderingInfo* pRenderingInfo);

protected:
	friend class MVKRenderSubpass;
	friend class MVKAttachmentDescription;

	void propagateDebugName() override {}

	MVKSmallVector<MVKAttachmentDescription> _attachments;
	MVKSmallVector<MVKRenderSubpass> _subpasses;
	MVKSmallVector<MVKSubpassDependency> _subpassDependencies;
	VkRenderingFlags _renderingFlags = 0;

};


#pragma mark -
#pragma mark MVKRenderingAttachmentIterator

typedef std::function<void(const VkRenderingAttachmentInfo* pAttInfo,
						   VkImageAspectFlagBits aspect,
						   bool isResolveAttachment)> MVKRenderingAttachmentInfoOperation;

/**
 * Iterates the attachments in a VkRenderingInfo, and processes an operation
 * on each attachment, once for the imageView, and once for the resolveImageView.
 *
 * Attachments are sequentially processed in this order:
 *     [color, color-resolve], ...,
 *     depth, depth-resolve,
 *     stencil, stencil-resolve
 * skipping any attachments that do not have a VkImageView
 */
class MVKRenderingAttachmentIterator : public MVKBaseObject {

public:

	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; }

	/** Iterates the attachments with the specified lambda function. */
	void iterate(MVKRenderingAttachmentInfoOperation attOperation);

	MVKRenderingAttachmentIterator(const VkRenderingInfo* pRenderingInfo);

protected:
	void handleAttachment(const VkRenderingAttachmentInfo* pAttInfo,
						  VkImageAspectFlagBits aspect,
						  MVKRenderingAttachmentInfoOperation attOperation);
	const VkRenderingAttachmentInfo* getAttachmentInfo(const VkRenderingAttachmentInfo* pAtt,
													   const VkRenderingAttachmentInfo* pAltAtt,
													   bool isStencil);

	VkRenderingInfo _renderingInfo;
};


#pragma mark -
#pragma mark Support functions

/** Returns whether the view mask uses multiview. */
static constexpr bool mvkIsMultiview(uint32_t viewMask) { return viewMask != 0; }

/** Returns whether the attachment is being used. */
bool mvkIsColorAttachmentUsed(const VkPipelineRenderingCreateInfo* pRendInfo, uint32_t colorAttIdx);

/** Returns whether any attachment is being used. */
bool mvkHasColorAttachments(const VkPipelineRenderingCreateInfo* pRendInfo);

/**
 * Extracts the first view, number of views, and the portion of the mask
 * to be rendered from the lowest clump of set bits in a view mask.
 */
uint32_t mvkGetNextViewMaskGroup(uint32_t viewMask, uint32_t* startView,
								 uint32_t* viewCount, uint32_t *groupMask = nullptr);

