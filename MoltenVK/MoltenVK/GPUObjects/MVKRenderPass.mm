/*
 * MVKRenderPass.mm
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKRenderPass.h"
#include "MVKFramebuffer.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandEncodingPool.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"
#include "MTLRenderPassDepthAttachmentDescriptor+MoltenVK.h"
#if MVK_MACOS_OR_IOS
#include "MTLRenderPassStencilAttachmentDescriptor+MoltenVK.h"
#endif
#include <cassert>

using namespace std;


#pragma mark -
#pragma mark MVKRenderSubpass

MVKVulkanAPIObject* MVKRenderSubpass::getVulkanAPIObject() { return _renderPass->getVulkanAPIObject(); };

bool MVKRenderSubpass::hasColorAttachments() {
	for (auto& ca : _colorAttachments) {
		if (ca.attachment != VK_ATTACHMENT_UNUSED) { return true; }
	}
	return false;
}

VkFormat MVKRenderSubpass::getColorAttachmentFormat(uint32_t colorAttIdx) {
	if (colorAttIdx < _colorAttachments.size()) {
		uint32_t rpAttIdx = _colorAttachments[colorAttIdx].attachment;
		if (rpAttIdx == VK_ATTACHMENT_UNUSED) { return VK_FORMAT_UNDEFINED; }
		return _renderPass->_attachments[rpAttIdx].getFormat();
	}
	return VK_FORMAT_UNDEFINED;
}

bool MVKRenderSubpass::isColorAttachmentUsed(uint32_t colorAttIdx) {
	if (colorAttIdx >= _colorAttachments.size()) { return false; }
	return _colorAttachments[colorAttIdx].attachment != VK_ATTACHMENT_UNUSED;
}


bool MVKRenderSubpass::isColorAttachmentAlsoInputAttachment(uint32_t colorAttIdx) {
	if (colorAttIdx >= _colorAttachments.size()) { return false; }

	uint32_t rspAttIdx = _colorAttachments[colorAttIdx].attachment;
	if (rspAttIdx == VK_ATTACHMENT_UNUSED) { return false; }

	for (auto& inAtt : _inputAttachments) {
		if (inAtt.attachment == rspAttIdx) { return true; }
	}
	return false;
}

VkFormat MVKRenderSubpass::getDepthFormat() {
	return isDepthAttachmentUsed() ? _renderPass->_attachments[_depthAttachment.attachment].getFormat() : VK_FORMAT_UNDEFINED;
}

VkFormat MVKRenderSubpass::getStencilFormat() {
	return isStencilAttachmentUsed() ? _renderPass->_attachments[_stencilAttachment.attachment].getFormat() : VK_FORMAT_UNDEFINED;
}

VkSampleCountFlagBits MVKRenderSubpass::getSampleCount() {
	for (auto& ca : _colorAttachments) {
		uint32_t rpAttIdx = ca.attachment;
		if (rpAttIdx != VK_ATTACHMENT_UNUSED) {
			return _renderPass->_attachments[rpAttIdx].getSampleCount();
		}
	}
	if (_depthAttachment.attachment != VK_ATTACHMENT_UNUSED) {
		return _renderPass->_attachments[_depthAttachment.attachment].getSampleCount();
	}
	if (_stencilAttachment.attachment != VK_ATTACHMENT_UNUSED) {
		return _renderPass->_attachments[_stencilAttachment.attachment].getSampleCount();
	}
	return VK_SAMPLE_COUNT_1_BIT;
}

// Get the portion of the view mask that will be rendered in the specified Metal render pass.
uint32_t MVKRenderSubpass::getViewMaskGroupForMetalPass(uint32_t passIdx) {
	if (!_pipelineRenderingCreateInfo.viewMask) { return 0; }
	assert(passIdx < getMultiviewMetalPassCount());
	if (!_renderPass->getPhysicalDevice()->canUseInstancingForMultiview()) {
		return 1 << getFirstViewIndexInMetalPass(passIdx);
	}
	uint32_t mask = _pipelineRenderingCreateInfo.viewMask, groupMask = 0;
	for (uint32_t i = 0; i <= passIdx; ++i) {
		mask = mvkGetNextViewMaskGroup(mask, nullptr, nullptr, &groupMask);
	}
	return groupMask;
}

uint32_t MVKRenderSubpass::getMultiviewMetalPassCount() const {
	return _renderPass->getDevice()->getMultiviewMetalPassCount(_pipelineRenderingCreateInfo.viewMask);
}

uint32_t MVKRenderSubpass::getFirstViewIndexInMetalPass(uint32_t passIdx) const {
	return _renderPass->getDevice()->getFirstViewIndexInMetalPass(_pipelineRenderingCreateInfo.viewMask, passIdx);
}

uint32_t MVKRenderSubpass::getViewCountInMetalPass(uint32_t passIdx) const {
	return _renderPass->getDevice()->getViewCountInMetalPass(_pipelineRenderingCreateInfo.viewMask, passIdx);
}

uint32_t MVKRenderSubpass::getViewCountUpToMetalPass(uint32_t passIdx) const {
	if (!_pipelineRenderingCreateInfo.viewMask) { return 0; }
	if (!_renderPass->getPhysicalDevice()->canUseInstancingForMultiview()) {
		return passIdx+1;
	}
	uint32_t mask = _pipelineRenderingCreateInfo.viewMask;
	uint32_t totalViewCount = 0;
	for (uint32_t i = 0; i <= passIdx; ++i) {
		uint32_t viewCount;
		mask = mvkGetNextViewMaskGroup(mask, nullptr, &viewCount);
		totalViewCount += viewCount;
	}
	return totalViewCount;
}

void MVKRenderSubpass::populateMTLRenderPassDescriptor(MTLRenderPassDescriptor* mtlRPDesc,
													   uint32_t passIdx,
													   MVKFramebuffer* framebuffer,
													   MVKArrayRef<MVKImageView*const> attachments,
													   MVKArrayRef<const VkClearValue> clearValues,
													   bool isRenderingEntireAttachment,
													   bool loadOverride) {
	MVKPixelFormats* pixFmts = _renderPass->getPixelFormats();

	// Populate the Metal color attachments
	uint32_t caCnt = getColorAttachmentCount();
	uint32_t caUsedCnt = 0;
	for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
		uint32_t clrRPAttIdx = _colorAttachments[caIdx].attachment;
        if (clrRPAttIdx != VK_ATTACHMENT_UNUSED) {
			++caUsedCnt;
            MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = mtlRPDesc.colorAttachments[caIdx];

            // If it exists, configure the resolve attachment first,
            // as it affects the store action of the color attachment.
            uint32_t rslvRPAttIdx = _resolveAttachments.empty() ? VK_ATTACHMENT_UNUSED : _resolveAttachments[caIdx].attachment;
            bool hasResolveAttachment = (rslvRPAttIdx != VK_ATTACHMENT_UNUSED);
			bool canResolveFormat = true;
			if (hasResolveAttachment) {
				MVKImageView* raImgView = attachments[rslvRPAttIdx];
				canResolveFormat = mvkAreAllFlagsEnabled(pixFmts->getCapabilities(raImgView->getMTLPixelFormat()), kMVKMTLFmtCapsResolve);
				if (canResolveFormat) {
					raImgView->populateMTLRenderPassAttachmentDescriptorResolve(mtlColorAttDesc);

					// In a multiview render pass, we need to override the starting layer to ensure
					// only the enabled views are loaded.
					if (isMultiview()) {
						uint32_t startView = getFirstViewIndexInMetalPass(passIdx);
						if (mtlColorAttDesc.resolveTexture.textureType == MTLTextureType3D)
							mtlColorAttDesc.resolveDepthPlane += startView;
						else
							mtlColorAttDesc.resolveSlice += startView;
					}
				}
			}

            // Configure the color attachment
            MVKAttachmentDescription* clrMVKRPAtt = &_renderPass->_attachments[clrRPAttIdx];
			if (clrMVKRPAtt->populateMTLRenderPassAttachmentDescriptor(mtlColorAttDesc, this, attachments[clrRPAttIdx],
                                                                       isRenderingEntireAttachment,
                                                                       hasResolveAttachment, canResolveFormat,
																	   false, loadOverride)) {
				mtlColorAttDesc.clearColor = pixFmts->getMTLClearColor(clearValues[clrRPAttIdx], clrMVKRPAtt->getFormat());
			}
			if (isMultiview()) {
				uint32_t startView = getFirstViewIndexInMetalPass(passIdx);
				if (mtlColorAttDesc.texture.textureType == MTLTextureType3D)
					mtlColorAttDesc.depthPlane += startView;
				else
					mtlColorAttDesc.slice += startView;
			}
		}
	}

	// Populate the Metal depth attachment
	uint32_t depthRPAttIdx = _depthAttachment.attachment;
	if (depthRPAttIdx != VK_ATTACHMENT_UNUSED) {
		MVKAttachmentDescription* depthMVKRPAtt = &_renderPass->_attachments[depthRPAttIdx];
		MVKImageView* depthImage = attachments[depthRPAttIdx];

		MVKImageView* depthRslvImage = nullptr;
		uint32_t depthRslvRPAttIdx = _depthResolveAttachment.attachment;
		if (depthRslvRPAttIdx != VK_ATTACHMENT_UNUSED) {
			depthRslvImage = attachments[depthRslvRPAttIdx];
		}

		MTLRenderPassDepthAttachmentDescriptor* mtlDepthAttDesc = mtlRPDesc.depthAttachment;
		bool hasDepthResolve = depthRslvRPAttIdx != VK_ATTACHMENT_UNUSED && _depthResolveMode != VK_RESOLVE_MODE_NONE;
		if (hasDepthResolve) {
			depthRslvImage->populateMTLRenderPassAttachmentDescriptorResolve(mtlDepthAttDesc);
			mtlDepthAttDesc.depthResolveFilterMVK = mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBits(_depthResolveMode);
			if (isMultiview()) {
				mtlDepthAttDesc.resolveSlice += getFirstViewIndexInMetalPass(passIdx);
			}
		}
		if (depthMVKRPAtt->populateMTLRenderPassAttachmentDescriptor(mtlDepthAttDesc, this, depthImage,
																	 isRenderingEntireAttachment,
																	 hasDepthResolve, true,
																	 false, loadOverride)) {
			mtlDepthAttDesc.clearDepth = pixFmts->getMTLClearDepthValue(clearValues[depthRPAttIdx]);
		}
		if (isMultiview()) {
			mtlDepthAttDesc.slice += getFirstViewIndexInMetalPass(passIdx);
		}
	}

	// Populate the Metal stencil attachment
	uint32_t stencilRPAttIdx = _stencilAttachment.attachment;
	if (stencilRPAttIdx != VK_ATTACHMENT_UNUSED) {
		MVKAttachmentDescription* stencilMVKRPAtt = &_renderPass->_attachments[stencilRPAttIdx];
		MVKImageView* stencilImage = attachments[stencilRPAttIdx];

		MVKImageView* stencilRslvImage = nullptr;
		uint32_t stencilRslvRPAttIdx = _stencilResolveAttachment.attachment;
		if (stencilRslvRPAttIdx != VK_ATTACHMENT_UNUSED) {
			stencilRslvImage = attachments[stencilRslvRPAttIdx];
		}

		MTLRenderPassStencilAttachmentDescriptor* mtlStencilAttDesc = mtlRPDesc.stencilAttachment;
		bool hasStencilResolve = (stencilRslvRPAttIdx != VK_ATTACHMENT_UNUSED && _stencilResolveMode != VK_RESOLVE_MODE_NONE);
		if (hasStencilResolve) {
			stencilRslvImage->populateMTLRenderPassAttachmentDescriptorResolve(mtlStencilAttDesc);
#if MVK_MACOS_OR_IOS
			mtlStencilAttDesc.stencilResolveFilterMVK = mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBits(_stencilResolveMode);
#endif
			if (isMultiview()) {
				mtlStencilAttDesc.resolveSlice += getFirstViewIndexInMetalPass(passIdx);
			}
		}
		if (stencilMVKRPAtt->populateMTLRenderPassAttachmentDescriptor(mtlStencilAttDesc, this, stencilImage,
																	   isRenderingEntireAttachment,
																	   hasStencilResolve, true,
																	   true, loadOverride)) {
			mtlStencilAttDesc.clearStencil = pixFmts->getMTLClearStencilValue(clearValues[stencilRPAttIdx]);
		}
		if (isMultiview()) {
			mtlStencilAttDesc.slice += getFirstViewIndexInMetalPass(passIdx);
		}
	}

	// Vulkan supports rendering without attachments, but older Metal does not.
	// If Metal does not support rendering without attachments, create a dummy attachment to pass Metal validation.
	if (caUsedCnt == 0 && depthRPAttIdx == VK_ATTACHMENT_UNUSED && stencilRPAttIdx == VK_ATTACHMENT_UNUSED) {
        if (_renderPass->getMetalFeatures().renderWithoutAttachments) {
            mtlRPDesc.defaultRasterSampleCount = mvkSampleCountFromVkSampleCountFlagBits(_defaultSampleCount);
		} else {
			MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = mtlRPDesc.colorAttachments[0];
			mtlColorAttDesc.texture = framebuffer->getDummyAttachmentMTLTexture(this, passIdx);
			mtlColorAttDesc.level = 0;
			mtlColorAttDesc.slice = 0;
			mtlColorAttDesc.depthPlane = 0;
			mtlColorAttDesc.loadAction = MTLLoadActionDontCare;
			mtlColorAttDesc.storeAction = MTLStoreActionDontCare;
		}
	}
}

void MVKRenderSubpass::encodeStoreActions(MVKCommandEncoder* cmdEncoder,
                                          bool isRenderingEntireAttachment,
                                          MVKArrayRef<MVKImageView*const> attachments,
                                          bool storeOverride) {
    if (!cmdEncoder->_mtlRenderEncoder) { return; }
	if (!_renderPass->getMetalFeatures().deferredStoreActions) { return; }

	MVKPixelFormats* pixFmts = _renderPass->getPixelFormats();
    uint32_t caCnt = getColorAttachmentCount();
    for (uint32_t caIdx = 0; caIdx < caCnt; ++caIdx) {
        uint32_t clrRPAttIdx = _colorAttachments[caIdx].attachment;
        if (clrRPAttIdx != VK_ATTACHMENT_UNUSED) {
			uint32_t rslvRPAttIdx = _resolveAttachments.empty() ? VK_ATTACHMENT_UNUSED : _resolveAttachments[caIdx].attachment;
			bool hasResolveAttachment = (rslvRPAttIdx != VK_ATTACHMENT_UNUSED);
			bool canResolveFormat = hasResolveAttachment && mvkAreAllFlagsEnabled(pixFmts->getCapabilities(attachments[rslvRPAttIdx]->getMTLPixelFormat()), kMVKMTLFmtCapsResolve);
			_renderPass->_attachments[clrRPAttIdx].encodeStoreAction(cmdEncoder, this, attachments[clrRPAttIdx], isRenderingEntireAttachment, hasResolveAttachment, canResolveFormat, caIdx, false, storeOverride);
        }
    }
	if (_depthAttachment.attachment != VK_ATTACHMENT_UNUSED) {
		_renderPass->_attachments[_depthAttachment.attachment].encodeStoreAction(cmdEncoder, this, attachments[_depthAttachment.attachment], isRenderingEntireAttachment,
																				 (_depthResolveAttachment.attachment != VK_ATTACHMENT_UNUSED && _depthResolveMode != VK_RESOLVE_MODE_NONE),
																				 true, 0, false, storeOverride);
	}
	if (_stencilAttachment.attachment != VK_ATTACHMENT_UNUSED) {
		_renderPass->_attachments[_stencilAttachment.attachment].encodeStoreAction(cmdEncoder, this, attachments[_stencilAttachment.attachment], isRenderingEntireAttachment,
																				   (_stencilResolveAttachment.attachment != VK_ATTACHMENT_UNUSED && _stencilResolveMode != VK_RESOLVE_MODE_NONE),
																				   true, 0, true, storeOverride);
	}
}

void MVKRenderSubpass::populateClearAttachments(MVKClearAttachments& clearAtts,
												MVKArrayRef<const VkClearValue> clearValues) {
	uint32_t caCnt = getColorAttachmentCount();
	for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
		uint32_t attIdx = _colorAttachments[caIdx].attachment;
		if ((attIdx != VK_ATTACHMENT_UNUSED) && _renderPass->_attachments[attIdx].shouldClearAttachment(this, false)) {
			clearAtts.push_back( { VK_IMAGE_ASPECT_COLOR_BIT, caIdx, clearValues[attIdx] } );
		}
	}

	// If depth and stencil both need clearing and are the same attachment, just clear once, otherwise, clear them separately.
	bool shouldClearDepth = (_depthAttachment.attachment != VK_ATTACHMENT_UNUSED &&
							 _renderPass->_attachments[_depthAttachment.attachment].shouldClearAttachment(this, false));
	bool shouldClearStencil = (_stencilAttachment.attachment != VK_ATTACHMENT_UNUSED &&
							   _renderPass->_attachments[_stencilAttachment.attachment].shouldClearAttachment(this, true));

	if (shouldClearDepth && shouldClearStencil && _depthAttachment.attachment == _stencilAttachment.attachment) {
		clearAtts.push_back( { VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT, 0, clearValues[_depthAttachment.attachment] } );
	} else {
		if (shouldClearDepth) {
			clearAtts.push_back( { VK_IMAGE_ASPECT_DEPTH_BIT, 0, clearValues[_depthAttachment.attachment] } );
		}
		if (shouldClearStencil) {
			clearAtts.push_back( { VK_IMAGE_ASPECT_STENCIL_BIT, 0, clearValues[_stencilAttachment.attachment] } );
		}
	}
}

void MVKRenderSubpass::populateMultiviewClearRects(MVKSmallVector<VkClearRect, 1>& clearRects,
												   MVKCommandEncoder* cmdEncoder,
												   uint32_t caIdx, VkImageAspectFlags aspectMask) {
	if (mvkIsAnyFlagEnabled(aspectMask, VK_IMAGE_ASPECT_COLOR_BIT)) {
		uint32_t clrAttIdx = _colorAttachments[caIdx].attachment;
		if (clrAttIdx != VK_ATTACHMENT_UNUSED) {
			_renderPass->_attachments[clrAttIdx].populateMultiviewClearRects(clearRects, cmdEncoder);
		}
	}

	// If depth and stencil are the same attachment, only clear once.
	if (mvkIsAnyFlagEnabled(aspectMask, VK_IMAGE_ASPECT_DEPTH_BIT) &&
		_depthAttachment.attachment != VK_ATTACHMENT_UNUSED) {

		_renderPass->_attachments[_depthAttachment.attachment].populateMultiviewClearRects(clearRects, cmdEncoder);
	}
	if (mvkIsAnyFlagEnabled(aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT) &&
		_stencilAttachment.attachment != VK_ATTACHMENT_UNUSED &&
		_stencilAttachment.attachment != _depthAttachment.attachment) {

		_renderPass->_attachments[_stencilAttachment.attachment].populateMultiviewClearRects(clearRects, cmdEncoder);
	}
}

// Returns the format capabilities required by this render subpass.
// It is possible for a subpass to use a single framebuffer attachment for multiple purposes.
// For example, a subpass may use a color or depth attachment as an input attachment as well.
// So, accumulate the capabilities from all possible attachments, just to be safe.
MVKMTLFmtCaps MVKRenderSubpass::getRequiredFormatCapabilitiesForAttachmentAt(uint32_t rpAttIdx) {
	MVKMTLFmtCaps caps = kMVKMTLFmtCapsNone;

	for (auto& att : _inputAttachments) {
		if (att.attachment == rpAttIdx) {
			mvkEnableFlags(caps, kMVKMTLFmtCapsRead);
			break;
		}
	}
	for (auto& att : _colorAttachments) {
		if (att.attachment == rpAttIdx) {
			mvkEnableFlags(caps, kMVKMTLFmtCapsColorAtt);
			break;
		}
	}
	for (auto& att : _resolveAttachments) {
		if (att.attachment == rpAttIdx) {
			mvkEnableFlags(caps, kMVKMTLFmtCapsResolve);
			break;
		}
	}
	if (_depthAttachment.attachment == rpAttIdx || _stencilAttachment.attachment == rpAttIdx) {
		mvkEnableFlags(caps, kMVKMTLFmtCapsDSAtt);
	}
	if (_depthResolveAttachment.attachment == rpAttIdx || _stencilResolveAttachment.attachment == rpAttIdx) {
		mvkEnableFlags(caps, kMVKMTLFmtCapsResolve);
	}

	return caps;
}

void MVKRenderSubpass::resolveUnresolvableAttachments(MVKCommandEncoder* cmdEncoder, MVKArrayRef<MVKImageView*const> attachments) {
	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
	size_t raCnt = _resolveAttachments.size();
	for (uint32_t raIdx = 0; raIdx < raCnt; raIdx++) {
		auto& ra = _resolveAttachments[raIdx];
		auto& ca = _colorAttachments[raIdx];
		if (ra.attachment != VK_ATTACHMENT_UNUSED && ca.attachment != VK_ATTACHMENT_UNUSED) {
			MVKImageView* raImgView = attachments[ra.attachment];
			MVKImageView* caImgView = attachments[ca.attachment];

			if ( !mvkAreAllFlagsEnabled(pixFmts->getCapabilities(raImgView->getMTLPixelFormat()), kMVKMTLFmtCapsResolve) ) {
				MVKFormatType mvkFmtType = _renderPass->getPixelFormats()->getFormatType(raImgView->getMTLPixelFormat());
				const bool isTextureArray = raImgView->getImage()->getLayerCount() != 1u;
				id<MTLComputePipelineState> mtlRslvState = cmdEncoder->getCommandEncodingPool()->getCmdResolveColorImageMTLComputePipelineState(mvkFmtType, isTextureArray);
				id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseResolveImage);
				[mtlComputeEnc setComputePipelineState: mtlRslvState];
				[mtlComputeEnc setTexture: raImgView->getMTLTexture() atIndex: 0];
				[mtlComputeEnc setTexture: caImgView->getMTLTexture() atIndex: 1];
				MTLSize gridSize = mvkMTLSizeFromVkExtent3D(raImgView->getExtent3D());
				MTLSize tgSize = MTLSizeMake(mtlRslvState.threadExecutionWidth, 1, 1);
				if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
					[mtlComputeEnc dispatchThreads: gridSize threadsPerThreadgroup: tgSize];
				} else {
					MTLSize tgCount = MTLSizeMake(gridSize.width / tgSize.width, gridSize.height, gridSize.depth);
					if (gridSize.width % tgSize.width) { tgCount.width += 1; }
					[mtlComputeEnc dispatchThreadgroups: tgCount threadsPerThreadgroup: tgSize];
				}
			}
		}
	}
}

void MVKRenderSubpass::populatePipelineRenderingCreateInfo() {
	_pipelineRenderingCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO;
	_pipelineRenderingCreateInfo.pNext = nullptr;

	uint32_t caCnt = getColorAttachmentCount();
	for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
		_colorAttachmentFormats.push_back(getColorAttachmentFormat(caIdx));
	}
	_pipelineRenderingCreateInfo.colorAttachmentCount = caCnt;
	_pipelineRenderingCreateInfo.pColorAttachmentFormats = _colorAttachmentFormats.data();
	_pipelineRenderingCreateInfo.depthAttachmentFormat = getDepthFormat();
	_pipelineRenderingCreateInfo.stencilAttachmentFormat = getStencilFormat();

	// Needed to understand if we need to force the depth/stencil write to post fragment execution
	// since Metal may try to do the write pre fragment exeuction which is against Vulkan
	bool depthAttachmentUsed = isDepthAttachmentUsed();
	bool stencilAttachmentUsed = isStencilAttachmentUsed();
	for (uint32_t i = 0u; i < _inputAttachments.size(); ++i) {
		bool isDepthInput = depthAttachmentUsed && (_inputAttachments[i].attachment == _depthAttachment.attachment) &&
							  (_inputAttachments[i].aspectMask & _depthAttachment.aspectMask);
		bool isStencilInput = stencilAttachmentUsed && (_inputAttachments[i].attachment == _stencilAttachment.attachment) &&
							  (_inputAttachments[i].aspectMask & _stencilAttachment.aspectMask);
		if (isDepthInput || isStencilInput) {
			_isInputAttachmentDepthStencilAttachment = true;
			break;
		}
	}
}

static const VkAttachmentReference2 _unusedAttachment = {VK_STRUCTURE_TYPE_ATTACHMENT_REFERENCE_2, nullptr, VK_ATTACHMENT_UNUSED, VK_IMAGE_LAYOUT_UNDEFINED, 0};

MVKRenderSubpass::MVKRenderSubpass(MVKRenderPass* renderPass, const VkSubpassDescription2* pCreateInfo) {

	VkSubpassDescriptionDepthStencilResolve* pDSResolveInfo = nullptr;
	for (auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_SUBPASS_DESCRIPTION_DEPTH_STENCIL_RESOLVE:
				pDSResolveInfo = (VkSubpassDescriptionDepthStencilResolve*)next;
				break;
			default:
				break;
		}
	}

	_renderPass = renderPass;
	_subpassIndex = (uint32_t)_renderPass->_subpasses.size();
	_pipelineRenderingCreateInfo.viewMask = pCreateInfo->viewMask;

	// Add attachments
	_inputAttachments.reserve(pCreateInfo->inputAttachmentCount);
	for (uint32_t i = 0; i < pCreateInfo->inputAttachmentCount; i++) {
		_inputAttachments.push_back(pCreateInfo->pInputAttachments[i]);
	}

	_colorAttachments.reserve(pCreateInfo->colorAttachmentCount);
	for (uint32_t i = 0; i < pCreateInfo->colorAttachmentCount; i++) {
		_colorAttachments.push_back(pCreateInfo->pColorAttachments[i]);
	}

	if (pCreateInfo->pResolveAttachments) {
		_resolveAttachments.reserve(pCreateInfo->colorAttachmentCount);
		for (uint32_t i = 0; i < pCreateInfo->colorAttachmentCount; i++) {
			_resolveAttachments.push_back(pCreateInfo->pResolveAttachments[i]);
		}
	}

	MVKPixelFormats* pixFmts = _renderPass->getPixelFormats();

	_depthAttachment = _unusedAttachment;
	_stencilAttachment = _unusedAttachment;
	const auto* pDSAtt = pCreateInfo->pDepthStencilAttachment;
	if (pDSAtt && pDSAtt->attachment != VK_ATTACHMENT_UNUSED) {
		MTLPixelFormat mtlDSFormat = pixFmts->getMTLPixelFormat(_renderPass->_attachments[pDSAtt->attachment].getFormat());
		if (pixFmts->isDepthFormat(mtlDSFormat)) {
			_depthAttachment = *pCreateInfo->pDepthStencilAttachment;
		}
		if (pixFmts->isStencilFormat(mtlDSFormat)) {
			_stencilAttachment = *pCreateInfo->pDepthStencilAttachment;
		}
	}

	_depthResolveAttachment = _unusedAttachment;
	_stencilResolveAttachment = _unusedAttachment;
	const auto* pDSRslvAtt = pDSResolveInfo ? pDSResolveInfo->pDepthStencilResolveAttachment : nullptr;
	if (pDSRslvAtt && pDSRslvAtt->attachment != VK_ATTACHMENT_UNUSED) {
		MTLPixelFormat mtlDSFormat = pixFmts->getMTLPixelFormat(_renderPass->_attachments[pDSRslvAtt->attachment].getFormat());
		if (pixFmts->isDepthFormat(mtlDSFormat)) {
			_depthResolveAttachment = *pDSResolveInfo->pDepthStencilResolveAttachment;
			_depthResolveMode = pDSResolveInfo->depthResolveMode;
		}
		if (pixFmts->isStencilFormat(mtlDSFormat)) {
			_stencilResolveAttachment = *pDSResolveInfo->pDepthStencilResolveAttachment;
			_stencilResolveMode = pDSResolveInfo->stencilResolveMode;
		}
	}

	_preserveAttachments.reserve(pCreateInfo->preserveAttachmentCount);
	for (uint32_t i = 0; i < pCreateInfo->preserveAttachmentCount; i++) {
		_preserveAttachments.push_back(pCreateInfo->pPreserveAttachments[i]);
	}

	populatePipelineRenderingCreateInfo();
}

MVKRenderSubpass::MVKRenderSubpass(MVKRenderPass* renderPass,
								   const VkSubpassDescription* pCreateInfo,
								   const VkRenderPassInputAttachmentAspectCreateInfo* pInputAspects,
								   uint32_t viewMask) {
	_renderPass = renderPass;
	_subpassIndex = (uint32_t)_renderPass->_subpasses.size();
	_pipelineRenderingCreateInfo.viewMask = viewMask;

	// Add attachments
	_inputAttachments.reserve(pCreateInfo->inputAttachmentCount);
	for (uint32_t i = 0; i < pCreateInfo->inputAttachmentCount; i++) {
		const VkAttachmentReference& att = pCreateInfo->pInputAttachments[i];
		_inputAttachments.push_back({VK_STRUCTURE_TYPE_ATTACHMENT_REFERENCE_2, nullptr, att.attachment, att.layout, VK_IMAGE_ASPECT_COLOR_BIT | VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT});
	}
	if (pInputAspects && pInputAspects->aspectReferenceCount) {
		for (uint32_t i = 0; i < pInputAspects->aspectReferenceCount; i++) {
			const VkInputAttachmentAspectReference& aspectRef = pInputAspects->pAspectReferences[i];
			if (aspectRef.subpass == _subpassIndex) {
				_inputAttachments[aspectRef.inputAttachmentIndex].aspectMask = aspectRef.aspectMask;
			}
		}
	}

	_colorAttachments.reserve(pCreateInfo->colorAttachmentCount);
	for (uint32_t i = 0; i < pCreateInfo->colorAttachmentCount; i++) {
		const VkAttachmentReference& att = pCreateInfo->pColorAttachments[i];
		_colorAttachments.push_back({VK_STRUCTURE_TYPE_ATTACHMENT_REFERENCE_2, nullptr, att.attachment, att.layout, VK_IMAGE_ASPECT_COLOR_BIT});
	}

	if (pCreateInfo->pResolveAttachments) {
		_resolveAttachments.reserve(pCreateInfo->colorAttachmentCount);
		for (uint32_t i = 0; i < pCreateInfo->colorAttachmentCount; i++) {
			const VkAttachmentReference& att = pCreateInfo->pResolveAttachments[i];
			_resolveAttachments.push_back({VK_STRUCTURE_TYPE_ATTACHMENT_REFERENCE_2, nullptr, att.attachment, att.layout, VK_IMAGE_ASPECT_COLOR_BIT});
		}
	}

	_depthAttachment = _unusedAttachment;
	_stencilAttachment = _unusedAttachment;
	if (pCreateInfo->pDepthStencilAttachment) {
		auto* dsAtt = pCreateInfo->pDepthStencilAttachment;
		uint32_t dsAttIdx = dsAtt->attachment;
		if (dsAttIdx != VK_ATTACHMENT_UNUSED) {
			MVKPixelFormats* pixFmts = _renderPass->getPixelFormats();
			MTLPixelFormat mtlDSFormat = pixFmts->getMTLPixelFormat(_renderPass->_attachments[dsAttIdx].getFormat());
			if (pixFmts->isDepthFormat(mtlDSFormat)) {
				_depthAttachment = {VK_STRUCTURE_TYPE_ATTACHMENT_REFERENCE_2, nullptr, dsAtt->attachment, dsAtt->layout, VK_IMAGE_ASPECT_DEPTH_BIT};
			}
			if (pixFmts->isStencilFormat(mtlDSFormat)) {
				_stencilAttachment = {VK_STRUCTURE_TYPE_ATTACHMENT_REFERENCE_2, nullptr, dsAtt->attachment, dsAtt->layout, VK_IMAGE_ASPECT_STENCIL_BIT};
			}
		}
	}

	_depthResolveAttachment = _unusedAttachment;
	_stencilResolveAttachment = _unusedAttachment;

	_preserveAttachments.reserve(pCreateInfo->preserveAttachmentCount);
	for (uint32_t i = 0; i < pCreateInfo->preserveAttachmentCount; i++) {
		_preserveAttachments.push_back(pCreateInfo->pPreserveAttachments[i]);
	}

	populatePipelineRenderingCreateInfo();

}

MVKRenderSubpass::MVKRenderSubpass(MVKRenderPass* renderPass, const VkRenderingInfo* pRenderingInfo) {

	_renderPass = renderPass;
	_subpassIndex = (uint32_t)_renderPass->_subpasses.size();
	_pipelineRenderingCreateInfo.viewMask = pRenderingInfo->viewMask;

	_depthAttachment = _unusedAttachment;
	_depthResolveAttachment = _unusedAttachment;
	_stencilAttachment = _unusedAttachment;
	_stencilResolveAttachment = _unusedAttachment;

	uint32_t attIdx = 0;
	MVKRenderingAttachmentIterator attIter(pRenderingInfo);
	attIter.iterate([&](const VkRenderingAttachmentInfo* pAttInfo, VkImageAspectFlagBits aspect, bool isResolveAttachment)->void {
		VkAttachmentReference2 attRef = {VK_STRUCTURE_TYPE_ATTACHMENT_REFERENCE_2, nullptr, attIdx++, pAttInfo->imageLayout, aspect};
		switch (aspect) {
			case VK_IMAGE_ASPECT_COLOR_BIT:
				if (isResolveAttachment) {
					_resolveAttachments.push_back(attRef);
				} else {
					_colorAttachments.push_back(attRef);
				}
				break;

			case VK_IMAGE_ASPECT_DEPTH_BIT:
				if (isResolveAttachment) {
					_depthResolveAttachment = attRef;
					_depthResolveMode = pAttInfo->resolveMode;
				} else {
					_depthAttachment = attRef;
				}
				break;
			case VK_IMAGE_ASPECT_STENCIL_BIT:
				if (isResolveAttachment) {
					_stencilResolveAttachment = attRef;
					_stencilResolveMode = pAttInfo->resolveMode;
				} else {
					_stencilAttachment = attRef;
				}
				break;

			default:
				break;
		}
	});

	populatePipelineRenderingCreateInfo();
}


#pragma mark -
#pragma mark MVKAttachmentDescription

MVKVulkanAPIObject* MVKAttachmentDescription::getVulkanAPIObject() { return _renderPass->getVulkanAPIObject(); };

VkFormat MVKAttachmentDescription::getFormat() { return _info.format; }

VkSampleCountFlagBits MVKAttachmentDescription::getSampleCount() { return _info.samples; }

bool MVKAttachmentDescription::populateMTLRenderPassAttachmentDescriptor(MTLRenderPassAttachmentDescriptor* mtlAttDesc,
																		 MVKRenderSubpass* subpass,
																		 MVKImageView* attachment,
																		 bool isRenderingEntireAttachment,
																		 bool hasResolveAttachment,
																		 bool canResolveFormat,
																		 bool isStencil,
																		 bool loadOverride) {
	// Populate from the attachment image view
	attachment->populateMTLRenderPassAttachmentDescriptor(mtlAttDesc);

	bool isMemorylessAttachment = false;
#if MVK_APPLE_SILICON
	isMemorylessAttachment = attachment->getMTLTexture().storageMode == MTLStorageModeMemoryless;
#endif
	bool isResuming = mvkIsAnyFlagEnabled(_renderPass->getRenderingFlags(), VK_RENDERING_RESUMING_BIT);

	// Only allow clearing of entire attachment if we're actually
	// rendering to the entire attachment AND we're in the first subpass.
	// If the renderpass was suspended, and is now being resumed, load the contents.
	MTLLoadAction mtlLA;
	if (loadOverride || isResuming || !isRenderingEntireAttachment || !isFirstUseOfAttachment(subpass)) {
		mtlLA = MTLLoadActionLoad;
    } else {
        VkAttachmentLoadOp loadOp = isStencil ? _info.stencilLoadOp : _info.loadOp;
		mtlLA = mvkMTLLoadActionFromVkAttachmentLoadOp(loadOp);
    }

	// Memoryless can be cleared, but can't be loaded, so force load to don't care.
	if (isMemorylessAttachment && mtlLA == MTLLoadActionLoad) { mtlLA = MTLLoadActionDontCare; }

	mtlAttDesc.loadAction = mtlLA;

    // If the device supports late-specified store actions, we'll use those, and then set them later.
    // That way, if we wind up doing a tessellated draw, we can set the store action to store then,
    // and then when the render pass actually ends, we can use the true store action.
    if (_renderPass->getMetalFeatures().deferredStoreActions) {
        mtlAttDesc.storeAction = MTLStoreActionUnknown;
    } else {
		// For a combined depth-stencil format in an attachment with VK_IMAGE_ASPECT_STENCIL_BIT,
		// the attachment format may have been swizzled to a stencil-only format. In this case,
		// we want to guard against an attempt to store the non-existent depth component.
		MTLPixelFormat mtlFmt = attachment->getMTLPixelFormat();
		MVKPixelFormats* pixFmts = _renderPass->getPixelFormats();
		bool isDepthFormat = pixFmts->isDepthFormat(mtlFmt);
		bool isStencilFormat = pixFmts->isStencilFormat(mtlFmt);
		if (isStencilFormat && !isStencil && !isDepthFormat) {
			mtlAttDesc.storeAction = MTLStoreActionDontCare;
		} else {
			mtlAttDesc.storeAction = getMTLStoreAction(subpass, isRenderingEntireAttachment, isMemorylessAttachment, hasResolveAttachment, canResolveFormat, isStencil, false);
		}
    }
    return (mtlLA == MTLLoadActionClear);
}

void MVKAttachmentDescription::encodeStoreAction(MVKCommandEncoder* cmdEncoder,
												 MVKRenderSubpass* subpass,
												 MVKImageView* attachment,
												 bool isRenderingEntireAttachment,
												 bool hasResolveAttachment,
												 bool canResolveFormat,
												 uint32_t caIdx,
												 bool isStencil,
												 bool storeOverride) {
	// For a combined depth-stencil format in an attachment with VK_IMAGE_ASPECT_STENCIL_BIT,
	// the attachment format may have been swizzled to a stencil-only format. In this case,
	// we must avoid either storing, or leaving unknown, the non-existent depth component.
	// We check for depth swizzling by looking at the original image format as well.
	MTLPixelFormat mtlFmt = attachment->getMTLPixelFormat();
	MVKPixelFormats* pixFmts = _renderPass->getPixelFormats();
	bool isStencilFormat = pixFmts->isStencilFormat(mtlFmt);
	bool isDepthFormat = pixFmts->isDepthFormat(mtlFmt);
	bool isDepthSwizzled = false;
	if (isStencilFormat && !isDepthFormat) {
		isDepthFormat = pixFmts->isDepthFormat(attachment->getImage()->getMTLPixelFormat());
		isDepthSwizzled = isDepthFormat;
	}
	bool isColorFormat = !(isDepthFormat || isStencilFormat);

	bool isMemorylessAttachment = false;
#if MVK_APPLE_SILICON
	isMemorylessAttachment = attachment->getMTLTexture().storageMode == MTLStorageModeMemoryless;
#endif
	MTLStoreAction storeAction = getMTLStoreAction(subpass, isRenderingEntireAttachment, isMemorylessAttachment,
												   hasResolveAttachment, canResolveFormat, isStencil, storeOverride);
	if (isColorFormat) {
		[cmdEncoder->_mtlRenderEncoder setColorStoreAction: storeAction atIndex: caIdx];
	} else if (isDepthFormat && !isStencil) {
		[cmdEncoder->_mtlRenderEncoder setDepthStoreAction: (isDepthSwizzled ? MTLStoreActionDontCare : storeAction)];
	} else if (isStencilFormat && isStencil) {
		[cmdEncoder->_mtlRenderEncoder setStencilStoreAction: storeAction];
	}
}

void MVKAttachmentDescription::populateMultiviewClearRects(MVKSmallVector<VkClearRect, 1>& clearRects, MVKCommandEncoder* cmdEncoder) {
	MVKRenderSubpass* subpass = cmdEncoder->getSubpass();
	uint32_t clearMask = subpass->getViewMaskGroupForMetalPass(cmdEncoder->getMultiviewPassIndex()) & _firstUseViewMasks[subpass->_subpassIndex];

	if (!clearMask) { return; }
	VkRect2D renderArea = cmdEncoder->clipToRenderArea({{0, 0}, {kMVKUndefinedLargeUInt32, kMVKUndefinedLargeUInt32}});
	uint32_t startView, viewCount;
	do {
		clearMask = mvkGetNextViewMaskGroup(clearMask, &startView, &viewCount);
		clearRects.push_back({renderArea, startView, viewCount});
	} while (clearMask);
}

bool MVKAttachmentDescription::isFirstUseOfAttachment(MVKRenderSubpass* subpass) {
	if ( subpass->isMultiview() ) {
		return _firstUseViewMasks[subpass->_subpassIndex] == subpass->_pipelineRenderingCreateInfo.viewMask;
	} else {
		return _firstUseSubpassIdx == subpass->_subpassIndex;
	}
}

bool MVKAttachmentDescription::isLastUseOfAttachment(MVKRenderSubpass* subpass) {
	if ( subpass->isMultiview() ) {
		return _lastUseViewMasks[subpass->_subpassIndex] == subpass->_pipelineRenderingCreateInfo.viewMask;
	} else {
		return _lastUseSubpassIdx == subpass->_subpassIndex;
	}
}

MTLStoreAction MVKAttachmentDescription::getMTLStoreAction(MVKRenderSubpass* subpass,
														   bool isRenderingEntireAttachment,
														   bool isMemorylessAttachment,
														   bool hasResolveAttachment,
														   bool canResolveFormat,
														   bool isStencil,
														   bool storeOverride) {

	// If the renderpass is going to be suspended, and resumed later, store the contents to preserve them until then.
	if (mvkIsAnyFlagEnabled(_renderPass->getRenderingFlags(), VK_RENDERING_SUSPENDING_BIT)) {
		return MTLStoreActionStore;
	}

	// If a resolve attachment exists, this attachment must resolve once complete.
    if (hasResolveAttachment && canResolveFormat && !_renderPass->getMetalFeatures().combinedStoreResolveAction) {
        return MTLStoreActionMultisampleResolve;
    }
	// Memoryless can't be stored.
	if (isMemorylessAttachment) {
		return hasResolveAttachment ? MTLStoreActionMultisampleResolve : MTLStoreActionDontCare;
	}

	// Only allow the attachment to be discarded if we're actually
	// rendering to the entire attachment and we're in the last subpass.
	if (storeOverride || !isRenderingEntireAttachment || !isLastUseOfAttachment(subpass)) {
		return hasResolveAttachment && canResolveFormat ? MTLStoreActionStoreAndMultisampleResolve : MTLStoreActionStore;
	}
	VkAttachmentStoreOp storeOp = isStencil ? _info.stencilStoreOp : _info.storeOp;
	return mvkMTLStoreActionFromVkAttachmentStoreOp(storeOp, hasResolveAttachment, canResolveFormat);
}

bool MVKAttachmentDescription::shouldClearAttachment(MVKRenderSubpass* subpass, bool isStencil) {

	// If the renderpass is being resumed after being suspended, don't clear this attachment.
	if (mvkIsAnyFlagEnabled(_renderPass->getRenderingFlags(), VK_RENDERING_RESUMING_BIT)) { return false; }

	// If the subpass is not the first subpass to use this attachment, don't clear this attachment.
	if (subpass->isMultiview()) {
		if (_firstUseViewMasks[subpass->_subpassIndex] == 0) { return false; }
	} else {
		if (subpass->_subpassIndex != _firstUseSubpassIdx) { return false; }
	}
	VkAttachmentLoadOp loadOp = isStencil ? _info.stencilLoadOp : _info.loadOp;
	return loadOp == VK_ATTACHMENT_LOAD_OP_CLEAR;
}

// Must be called after renderpass has both subpasses and attachments bound
void MVKAttachmentDescription::linkToSubpasses() {
	// Validate pixel format is supported
	MVKPixelFormats* pixFmts = _renderPass->getPixelFormats();
	if ( !pixFmts->isSupportedOrSubstitutable(_info.format) ) {
		_renderPass->setConfigurationResult(reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "vkCreateRenderPass(): Attachment format %s is not supported on this device.", _renderPass->getPixelFormats()->getName(_info.format)));
	}

	// Determine the indices of the first and last render subpasses to use this attachment.
	_firstUseSubpassIdx = kMVKUndefinedLargeUInt32;
	_lastUseSubpassIdx = 0;
	if (_renderPass->_subpasses[0].isMultiview()) {
		_firstUseViewMasks.reserve(_renderPass->_subpasses.size());
		_lastUseViewMasks.reserve(_renderPass->_subpasses.size());
	}
	for (auto& subPass : _renderPass->_subpasses) {
		// If it uses this attachment, the subpass will identify required format capabilities.
		MVKMTLFmtCaps reqCaps = subPass.getRequiredFormatCapabilitiesForAttachmentAt(_attachmentIndex);
		if (reqCaps) {
			uint32_t spIdx = subPass._subpassIndex;
			_firstUseSubpassIdx = min(spIdx, _firstUseSubpassIdx);
			_lastUseSubpassIdx = max(spIdx, _lastUseSubpassIdx);
			if ( subPass.isMultiview() ) {
				uint32_t viewMask = subPass._pipelineRenderingCreateInfo.viewMask;
				std::for_each(_lastUseViewMasks.begin(), _lastUseViewMasks.end(), [viewMask](uint32_t& mask) { mask &= ~viewMask; });
				_lastUseViewMasks.push_back(viewMask);
				std::for_each(_firstUseViewMasks.begin(), _firstUseViewMasks.end(), [&viewMask](uint32_t mask) { viewMask &= ~mask; });
				_firstUseViewMasks.push_back(viewMask);
			}

			// Validate that the attachment pixel format supports the capabilities required by the subpass.
			// Use MTLPixelFormat to look up capabilities to permit Metal format substitution.
			// It's okay if the format does not support the resolve capability, as this can be handled via a compute shader.
			MVKMTLFmtCaps availCaps = pixFmts->getCapabilities(pixFmts->getMTLPixelFormat(_info.format));
			mvkEnableFlags(availCaps, kMVKMTLFmtCapsResolve);
			if ( !mvkAreAllFlagsEnabled(availCaps, reqCaps) ) {
				_renderPass->setConfigurationResult(reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "vkCreateRenderPass(): Attachment format %s on this device does not support the VkFormat attachment capabilities required by the subpass at index %d.", _renderPass->getPixelFormats()->getName(_info.format), spIdx));
			}
		}
	}
}

MVKAttachmentDescription::MVKAttachmentDescription(MVKRenderPass* renderPass,
												   const VkAttachmentDescription* pCreateInfo) {
	_info.flags = pCreateInfo->flags;
	_info.format = pCreateInfo->format;
	_info.samples = pCreateInfo->samples;
	_info.loadOp = pCreateInfo->loadOp;
	_info.storeOp = pCreateInfo->storeOp;
	_info.stencilLoadOp = pCreateInfo->stencilLoadOp;
	_info.stencilStoreOp = pCreateInfo->stencilStoreOp;
	_info.initialLayout = pCreateInfo->initialLayout;
	_info.finalLayout = pCreateInfo->finalLayout;
	_renderPass = renderPass;
	_attachmentIndex = uint32_t(_renderPass->_attachments.size());
}

MVKAttachmentDescription::MVKAttachmentDescription(MVKRenderPass* renderPass,
												   const VkAttachmentDescription2* pCreateInfo) {
	_info = *pCreateInfo;
	_renderPass = renderPass;
	_attachmentIndex = uint32_t(_renderPass->_attachments.size());
}

MVKAttachmentDescription::MVKAttachmentDescription(MVKRenderPass* renderPass,
												   const VkRenderingAttachmentInfo* pAttInfo,
												   bool isResolveAttachment) {
	if (isResolveAttachment) {
		_info.flags = 0;
		_info.format = ((MVKImageView*)pAttInfo->resolveImageView)->getVkFormat();
		_info.samples = VK_SAMPLE_COUNT_1_BIT;
		_info.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		_info.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
		_info.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		_info.stencilStoreOp = VK_ATTACHMENT_STORE_OP_STORE;
		_info.initialLayout = pAttInfo->resolveImageLayout;
		_info.finalLayout = pAttInfo->resolveImageLayout;
	} else {
		_info.flags = 0;
		_info.format = ((MVKImageView*)pAttInfo->imageView)->getVkFormat();
		_info.samples = ((MVKImageView*)pAttInfo->imageView)->getSampleCount();
		_info.loadOp = pAttInfo->loadOp;
		_info.storeOp = pAttInfo->storeOp;
		_info.stencilLoadOp = pAttInfo->loadOp;
		_info.stencilStoreOp = pAttInfo->storeOp;
		_info.initialLayout = pAttInfo->imageLayout;
		_info.finalLayout = pAttInfo->imageLayout;
	}
	_renderPass = renderPass;
	_attachmentIndex = uint32_t(_renderPass->_attachments.size());
}


#pragma mark -
#pragma mark MVKRenderPass

MVKSubpassDependency::MVKSubpassDependency(const VkSubpassDependency& spDep, int32_t viewOffset) :
	srcSubpass(spDep.srcSubpass),
	dstSubpass(spDep.dstSubpass),
	srcStageMask(spDep.srcStageMask),
	dstStageMask(spDep.dstStageMask),
	srcAccessMask(spDep.srcAccessMask),
	dstAccessMask(spDep.dstAccessMask),
	dependencyFlags(spDep.dependencyFlags),
	viewOffset(viewOffset) {}

MVKSubpassDependency::MVKSubpassDependency(const VkSubpassDependency2& spDep, const VkMemoryBarrier2* pMemBar) :
	srcSubpass(spDep.srcSubpass),
	dstSubpass(spDep.dstSubpass),
	srcStageMask(pMemBar ? pMemBar->srcStageMask : spDep.srcStageMask),
	dstStageMask(pMemBar ? pMemBar->dstStageMask : spDep.dstStageMask),
	srcAccessMask(pMemBar ? pMemBar->srcAccessMask : spDep.srcAccessMask),
	dstAccessMask(pMemBar ? pMemBar->dstAccessMask : spDep.dstAccessMask),
	dependencyFlags(spDep.dependencyFlags),
	viewOffset(spDep.viewOffset) {}

VkExtent2D MVKRenderPass::getRenderAreaGranularity() {
    if (getMetalFeatures().tileBasedDeferredRendering) {
        // This is the tile area.
        // FIXME: We really ought to use MTLRenderCommandEncoder.tile{Width,Height}, but that requires
        // creating a command buffer.
        return { 32, 32 };
    }
    return { 1, 1 };
}

MVKRenderPass::MVKRenderPass(MVKDevice* device,
							 const VkRenderPassCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {

	const VkRenderPassInputAttachmentAspectCreateInfo* pInputAspectCreateInfo = nullptr;
	const VkRenderPassMultiviewCreateInfo* pMultiviewCreateInfo = nullptr;
	for (auto* next = (const VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
		case VK_STRUCTURE_TYPE_RENDER_PASS_INPUT_ATTACHMENT_ASPECT_CREATE_INFO:
			pInputAspectCreateInfo = (const VkRenderPassInputAttachmentAspectCreateInfo*)next;
			break;
		case VK_STRUCTURE_TYPE_RENDER_PASS_MULTIVIEW_CREATE_INFO:
			pMultiviewCreateInfo = (const VkRenderPassMultiviewCreateInfo*)next;
			break;
		default:
			break;
		}
	}

	const uint32_t* viewMasks = nullptr;
	const int32_t* viewOffsets = nullptr;
	if (pMultiviewCreateInfo && pMultiviewCreateInfo->subpassCount) {
		viewMasks = pMultiviewCreateInfo->pViewMasks;
	}
	if (pMultiviewCreateInfo && pMultiviewCreateInfo->dependencyCount) {
		viewOffsets = pMultiviewCreateInfo->pViewOffsets;
	}

	// Add attachments first so subpasses can access them during creation
	_attachments.reserve(pCreateInfo->attachmentCount);
	for (uint32_t i = 0; i < pCreateInfo->attachmentCount; i++) {
		_attachments.emplace_back(this, &pCreateInfo->pAttachments[i]);
	}

	// Add subpasses and dependencies
	_subpasses.reserve(pCreateInfo->subpassCount);
	for (uint32_t i = 0; i < pCreateInfo->subpassCount; i++) {
		_subpasses.emplace_back(this, &pCreateInfo->pSubpasses[i], pInputAspectCreateInfo, viewMasks ? viewMasks[i] : 0);
	}
	_subpassDependencies.reserve(pCreateInfo->dependencyCount);
	for (uint32_t i = 0; i < pCreateInfo->dependencyCount; i++) {
		_subpassDependencies.emplace_back(pCreateInfo->pDependencies[i], viewOffsets ? viewOffsets[i] : 0);
	}

	// Link attachments to subpasses
	for (auto& att : _attachments) {
		att.linkToSubpasses();
	}
}

MVKRenderPass::MVKRenderPass(MVKDevice* device,
							 const VkRenderPassCreateInfo2* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {

	// Add attachments first so subpasses can access them during creation
	_attachments.reserve(pCreateInfo->attachmentCount);
	for (uint32_t i = 0; i < pCreateInfo->attachmentCount; i++) {
		_attachments.emplace_back(this, &pCreateInfo->pAttachments[i]);
	}

	// Add subpasses and dependencies
	_subpasses.reserve(pCreateInfo->subpassCount);
	for (uint32_t i = 0; i < pCreateInfo->subpassCount; i++) {
		_subpasses.emplace_back(this, &pCreateInfo->pSubpasses[i]);
	}
	_subpassDependencies.reserve(pCreateInfo->dependencyCount);
	for (uint32_t i = 0; i < pCreateInfo->dependencyCount; i++) {
		auto& spDep = pCreateInfo->pDependencies[i];

		const VkMemoryBarrier2* pMemoryBarrier2 = nullptr;
		for (auto* next = (const VkBaseInStructure*)spDep.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_MEMORY_BARRIER_2:
					pMemoryBarrier2 = (const VkMemoryBarrier2*)next;
					break;
				default:
					break;
			}
		}
		_subpassDependencies.emplace_back(spDep, pMemoryBarrier2);
	}

	// Link attachments to subpasses
	for (auto& att : _attachments) {
		att.linkToSubpasses();
	}
}

MVKRenderPass::MVKRenderPass(MVKDevice* device, const VkRenderingInfo* pRenderingInfo) : MVKVulkanAPIDeviceObject(device) {

	_renderingFlags = pRenderingInfo->flags;

	// Add attachments first so subpasses can access them during creation
	uint32_t attCnt = 0;
	MVKRenderingAttachmentIterator attIter(pRenderingInfo);
	attIter.iterate([&](const VkRenderingAttachmentInfo* pAttInfo, VkImageAspectFlagBits aspect, bool isResolveAttachment)->void { attCnt++; });
	_attachments.reserve(attCnt);
	attIter.iterate([&](const VkRenderingAttachmentInfo* pAttInfo, VkImageAspectFlagBits aspect, bool isResolveAttachment)->void {
		_attachments.emplace_back(this, pAttInfo, isResolveAttachment);
	});

	// Add subpass
	_subpasses.emplace_back(this, pRenderingInfo);

	// Link attachments to subpasses
	for (auto& att : _attachments) {
		att.linkToSubpasses();
	}
}


#pragma mark -
#pragma mark MVKRenderingAttachmentIterator

void MVKRenderingAttachmentIterator::iterate(MVKRenderingAttachmentInfoOperation attOperation) {
	for (uint32_t caIdx = 0; caIdx < _renderingInfo.colorAttachmentCount; caIdx++) {
		handleAttachment(&_renderingInfo.pColorAttachments[caIdx], VK_IMAGE_ASPECT_COLOR_BIT, attOperation);
	}
	handleAttachment(_renderingInfo.pDepthAttachment, VK_IMAGE_ASPECT_DEPTH_BIT, attOperation);
	handleAttachment(_renderingInfo.pStencilAttachment, VK_IMAGE_ASPECT_STENCIL_BIT, attOperation);
}

void MVKRenderingAttachmentIterator::handleAttachment(const VkRenderingAttachmentInfo* pAttInfo,
													  VkImageAspectFlagBits aspect,
													  MVKRenderingAttachmentInfoOperation attOperation) {
	if (pAttInfo && pAttInfo->imageView) {
		attOperation(pAttInfo, aspect, false);
		if (pAttInfo->resolveImageView && pAttInfo->resolveMode != VK_RESOLVE_MODE_NONE) {
			attOperation(pAttInfo, aspect, true);
		}
	}
}

MVKRenderingAttachmentIterator::MVKRenderingAttachmentIterator(const VkRenderingInfo* pRenderingInfo) {
	_renderingInfo = *pRenderingInfo;
	_renderingInfo.pDepthAttachment   = getAttachmentInfo(pRenderingInfo->pDepthAttachment, pRenderingInfo->pStencilAttachment, false);
	_renderingInfo.pStencilAttachment = getAttachmentInfo(pRenderingInfo->pStencilAttachment, pRenderingInfo->pDepthAttachment, true);
}

// If the depth/stencil attachment is not in use, but the alternate stencil/depth attachment is,
// and the MTLPixelFormat is usable by both attachments, force the use of the alternate attachment
// for both attachments, to avoid Metal validation errors when a pipeline expects both depth and
// stencil, but only one of the attachments has been provided here.
// Check the MTLPixelFormat of the MVKImage underlying the MVKImageView, to bypass possible
// substitution of MTLPixelFormat in the MVKImageView due to swizzling, or stencil-only access.
const VkRenderingAttachmentInfo* MVKRenderingAttachmentIterator::getAttachmentInfo(const VkRenderingAttachmentInfo* pAtt,
																				   const VkRenderingAttachmentInfo* pAltAtt,
																				   bool isStencil) {
	bool useAlt = false;
	if ( !(pAtt && pAtt->imageView) && (pAltAtt && pAltAtt->imageView) ) {
		MVKImage* mvkImg = ((MVKImageView*)pAltAtt->imageView)->getImage();
		useAlt = (isStencil
				  ? mvkImg->getPixelFormats()->isStencilFormat(mvkImg->getMTLPixelFormat())
				  : mvkImg->getPixelFormats()->isDepthFormat(mvkImg->getMTLPixelFormat()));
	}
	return useAlt ? pAltAtt : pAtt;
}


#pragma mark -
#pragma mark Support functions

bool mvkIsColorAttachmentUsed(const VkPipelineRenderingCreateInfo* pRendInfo, uint32_t colorAttIdx) {
	return pRendInfo && pRendInfo->pColorAttachmentFormats[colorAttIdx];
}

bool mvkHasColorAttachments(const VkPipelineRenderingCreateInfo* pRendInfo) {
	if (pRendInfo) {
		for (uint32_t caIdx = 0; caIdx < pRendInfo->colorAttachmentCount; caIdx++) {
			if (mvkIsColorAttachmentUsed(pRendInfo, caIdx)) { return true; }
		}
	}
	return false;
}

uint32_t mvkGetNextViewMaskGroup(uint32_t viewMask, uint32_t* startView, uint32_t* viewCount, uint32_t *groupMask) {
	// First, find the first set bit. This is the start of the next clump of views to be rendered.
	// n.b. ffs(3) returns a 1-based index. This actually bit me during development of this feature.
	int pos = ffs(viewMask) - 1;
	int end = pos;
	if (groupMask) { *groupMask = 0; }
	// Now we'll step through the bits one at a time until we find a bit that isn't set.
	// This is one past the end of the next clump. Clear the bits as we go, so we can use
	// ffs(3) again on the next clump.
	// TODO: Find a way to make this faster.
	while (viewMask & (1 << end)) {
		if (groupMask) { *groupMask |= viewMask & (1 << end); }
		viewMask &= ~(1 << (end++));
	}
	if (startView) { *startView = pos; }
	if (viewCount) { *viewCount = end - pos; }
	return viewMask;
}
