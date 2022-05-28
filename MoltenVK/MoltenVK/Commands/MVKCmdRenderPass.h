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
#pragma mark MVKCmdBeginRenderPassBase

/**
 * Abstract base class of MVKCmdBeginRenderPass.
 * Contains all pieces that are independent of the templated portions.
 */
class MVKCmdBeginRenderPassBase : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						const VkRenderPassBeginInfo* pRenderPassBegin,
						const VkSubpassBeginInfo* pSubpassBeginInfo);

	inline MVKRenderPass* getRenderPass() { return _renderPass; }

protected:

	MVKSmallVector<MVKSmallVector<MTLSamplePosition>> _subpassSamplePositions;
	MVKRenderPass* _renderPass;
	MVKFramebuffer* _framebuffer;
	VkRect2D _renderArea;
	VkSubpassContents _contents;
};


#pragma mark -
#pragma mark MVKCmdBeginRenderPass

/**
 * Vulkan command to begin a render pass.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N_CV, size_t N_A>
class MVKCmdBeginRenderPass : public MVKCmdBeginRenderPassBase {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						const VkRenderPassBeginInfo* pRenderPassBegin,
						const VkSubpassBeginInfo* pSubpassBeginInfo,
						MVKArrayRef<MVKImageView*> attachments);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<VkClearValue, N_CV> _clearValues;
    MVKSmallVector<MVKImageView*, N_A> _attachments;
};

// Concrete template class implementations.
typedef MVKCmdBeginRenderPass<1, 0> MVKCmdBeginRenderPass10;
typedef MVKCmdBeginRenderPass<2, 0> MVKCmdBeginRenderPass20;
typedef MVKCmdBeginRenderPass<9, 0> MVKCmdBeginRenderPassMulti0;

typedef MVKCmdBeginRenderPass<1, 1> MVKCmdBeginRenderPass11;
typedef MVKCmdBeginRenderPass<2, 1> MVKCmdBeginRenderPass21;
typedef MVKCmdBeginRenderPass<9, 1> MVKCmdBeginRenderPassMulti1;

typedef MVKCmdBeginRenderPass<1, 2> MVKCmdBeginRenderPass12;
typedef MVKCmdBeginRenderPass<2, 2> MVKCmdBeginRenderPass22;
typedef MVKCmdBeginRenderPass<9, 2> MVKCmdBeginRenderPassMulti2;

typedef MVKCmdBeginRenderPass<1, 9> MVKCmdBeginRenderPass1Multi;
typedef MVKCmdBeginRenderPass<2, 9> MVKCmdBeginRenderPass2Multi;
typedef MVKCmdBeginRenderPass<9, 9> MVKCmdBeginRenderPassMultiMulti;


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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

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

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

};


#pragma mark -
#pragma mark MVKCmdBeginRendering

/**
 * Vulkan command to begin rendering.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdBeginRendering : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer*
						cmdBuff, const VkRenderingInfo* pRenderingInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;


protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkRenderingInfo _renderingInfo;
	MVKSmallVector<VkRenderingAttachmentInfo, N> _colorAttachments;
	VkRenderingAttachmentInfo _depthAttachment;
	VkRenderingAttachmentInfo _stencilAttachment;
};

// Concrete template class implementations.
typedef MVKCmdBeginRendering<1> MVKCmdBeginRendering1;
typedef MVKCmdBeginRendering<2> MVKCmdBeginRendering2;
typedef MVKCmdBeginRendering<4> MVKCmdBeginRendering4;
typedef MVKCmdBeginRendering<8> MVKCmdBeginRenderingMulti;


#pragma mark -
#pragma mark MVKCmdEndRendering

/** Vulkan command to end the current dynamic rendering. */
class MVKCmdEndRendering : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<MTLSamplePosition, 8> _samplePositions;
};


#pragma mark -
#pragma mark MVKCmdExecuteCommands

/**
 * Vulkan command to execute secondary command buffers.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdExecuteCommands : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t commandBuffersCount,
						const VkCommandBuffer* pCommandBuffers);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<MVKCommandBuffer*, N> _secondaryCommandBuffers;
};

// Concrete template class implementations.
typedef MVKCmdExecuteCommands<1> MVKCmdExecuteCommands1;
typedef MVKCmdExecuteCommands<16> MVKCmdExecuteCommandsMulti;


#pragma mark -
#pragma mark MVKCmdSetViewport

/**
 * Vulkan command to set the viewports.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdSetViewport : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t firstViewport,
						uint32_t viewportCount,
						const VkViewport* pViewports);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<VkViewport, N> _viewports;
	uint32_t _firstViewport;
};

// Concrete template class implementations.
typedef MVKCmdSetViewport<1> MVKCmdSetViewport1;
typedef MVKCmdSetViewport<kMVKCachedViewportScissorCount> MVKCmdSetViewportMulti;


#pragma mark -
#pragma mark MVKCmdSetScissor

/**
 * Vulkan command to set the scissor rectangles.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdSetScissor : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t firstScissor,
						uint32_t scissorCount,
						const VkRect2D* pScissors);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<VkRect2D, N> _scissors;
	uint32_t _firstScissor;
};

// Concrete template class implementations.
typedef MVKCmdSetScissor<1> MVKCmdSetScissor1;
typedef MVKCmdSetScissor<kMVKCachedViewportScissorCount> MVKCmdSetScissorMulti;


#pragma mark -
#pragma mark MVKCmdSetLineWidth

/** Vulkan command to set the line width. */
class MVKCmdSetLineWidth : public MVKCommand {

public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
					float lineWidth);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

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
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    VkStencilFaceFlags _faceMask;
    uint32_t _stencilReference;
};

