/*
 * MVKCmdRenderPass.h
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

#include "MVKCommand.h"
#include "MVKDevice.h"
#include "MVKSmallVector.h"

#import <Metal/Metal.h>

class MVKRenderPass;
class MVKFramebuffer;


#pragma mark -
#pragma mark MVKCmdBeginRenderPass

/**
 * Vulkan command to begin a render pass.
 */
class MVKCmdBeginRenderPass : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						const VkRenderPassBeginInfo* pRenderPassBegin,
						const VkSubpassBeginInfo* pSubpassBeginInfo,
						MVKArrayRef<MVKImageView*> attachments);

	void encode(MVKCommandEncoder* cmdEncoder) override;

    inline MVKRenderPass* getRenderPass() { return _renderPass; }

protected:
    MVKCommandVector<MVKCommandVector<MTLSamplePosition>> _subpassSamplePositions;
    MVKRenderPass* _renderPass;
    MVKFramebuffer* _framebuffer;
    VkRect2D _renderArea;
    VkSubpassContents _contents;

    MVKCommandVector<VkClearValue> _clearValues;
    MVKCommandVector<MVKImageView*> _attachments;
};


#pragma mark -
#pragma mark MVKCmdNextSubpass

/** Vulkan command to begin a render pass. */
class MVKCmdNextSubpass : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkSubpassContents contents);
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						const VkSubpassBeginInfo* pSubpassBeginInfo,
						const VkSubpassEndInfo* pSubpassEndInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	VkSubpassContents _contents;
};


#pragma mark -
#pragma mark MVKCmdEndRenderPass

/** Vulkan command to end the current render pass. */
class MVKCmdEndRenderPass : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff);
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						const VkSubpassEndInfo* pSubpassEndInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;
};


#pragma mark -
#pragma mark MVKCmdBeginRendering

/**
 * Vulkan command to begin rendering.
 */
class MVKCmdBeginRendering : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer*
						cmdBuff, const VkRenderingInfo* pRenderingInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;


protected:
	VkRenderingInfo _renderingInfo;
	MVKCommandVector<VkRenderingAttachmentInfo> _colorAttachments;
	VkRenderingAttachmentInfo _depthAttachment;
	VkRenderingAttachmentInfo _stencilAttachment;
};

#pragma mark -
#pragma mark MVKCmdEndRendering

/** Vulkan command to end the current dynamic rendering. */
class MVKCmdEndRendering : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff);

	void encode(MVKCommandEncoder* cmdEncoder) override;
};


#pragma mark -
#pragma mark MVKCmdSetSampleLocations

/** Vulkan command to dynamically set custom sample locations. */
class MVKCmdSetSampleLocations : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						const VkSampleLocationsInfoEXT* pSampleLocationsInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandVector<MTLSamplePosition> _samplePositions;
};


#pragma mark -
#pragma mark MVKCmdExecuteCommands

/**
 * Vulkan command to execute secondary command buffers.
 */
class MVKCmdExecuteCommands : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t commandBuffersCount,
						const VkCommandBuffer* pCommandBuffers);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandVector<MVKCommandBuffer*> _secondaryCommandBuffers;
};


#pragma mark -
#pragma mark MVKCmdSetViewport

/**
 * Vulkan command to set the viewports.
 */
class MVKCmdSetViewport : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t firstViewport,
						uint32_t viewportCount,
						const VkViewport* pViewports);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandVector<VkViewport> _viewports;
	uint32_t _firstViewport;
};

#pragma mark -
#pragma mark MVKCmdSetScissor

/**
 * Vulkan command to set the scissor rectangles.
 */
class MVKCmdSetScissor : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t firstScissor,
						uint32_t scissorCount,
						const VkRect2D* pScissors);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandVector<VkRect2D> _scissors;
	uint32_t _firstScissor;
};

#pragma mark -
#pragma mark MVKCmdSetLineWidth

/** Vulkan command to set the line width. */
class MVKCmdSetLineWidth : public MVKCommand {

public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
					float lineWidth);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    float _lineWidth;
};


#pragma mark -
#pragma mark MVKCmdSetDepthBias

/** Vulkan command to set the depth bias. */
class MVKCmdSetDepthBias : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						float depthBiasConstantFactor,
						float depthBiasClamp,
						float depthBiasSlopeFactor);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    float _depthBiasConstantFactor;
    float _depthBiasClamp;
    float _depthBiasSlopeFactor;
};


#pragma mark -
#pragma mark MVKCmdSetBlendConstants

/** Vulkan command to set the blend constants. */
class MVKCmdSetBlendConstants : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						const float blendConst[4]);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    float _red;
    float _green;
    float _blue;
    float _alpha;
};


#pragma mark -
#pragma mark MVKCmdSetDepthBounds

/** Vulkan command to set depth bounds. */
class MVKCmdSetDepthBounds : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						float minDepthBounds,
						float maxDepthBounds);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    float _minDepthBounds;
    float _maxDepthBounds;
};


#pragma mark -
#pragma mark MVKCmdSetStencilCompareMask

/** Vulkan command to set the stencil compare mask. */
class MVKCmdSetStencilCompareMask : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkStencilFaceFlags faceMask,
						uint32_t stencilCompareMask);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    VkStencilFaceFlags _faceMask;
    uint32_t _stencilCompareMask;
};


#pragma mark -
#pragma mark MVKCmdSetStencilWriteMask

/** Vulkan command to set the stencil write mask. */
class MVKCmdSetStencilWriteMask : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkStencilFaceFlags faceMask,
						uint32_t stencilWriteMask);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    VkStencilFaceFlags _faceMask;
    uint32_t _stencilWriteMask;
};


#pragma mark -
#pragma mark MVKCmdSetStencilReference

/** Vulkan command to set the stencil reference value. */
class MVKCmdSetStencilReference : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkStencilFaceFlags faceMask,
						uint32_t stencilReference);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    VkStencilFaceFlags _faceMask;
    uint32_t _stencilReference;
};

