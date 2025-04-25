/*
 * MVKCmdRendering.h
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

#pragma once

#include "MVKCommand.h"
#include "MVKDevice.h"
#include "MVKSmallVector.h"
#include "MVKCommandEncoderState.h"

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

class MVKCmdEndRendering : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

};


#pragma mark -
#pragma mark MVKCmdSetSampleLocations

class MVKCmdSetSampleLocations : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						const VkSampleLocationsInfoEXT* pSampleLocationsInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<VkSampleLocationEXT, kMVKMaxSampleCount> _sampleLocations;
};


#pragma mark -
#pragma mark MVKCmdSetSampleLocationsEnable

class MVKCmdSetSampleLocationsEnable : public MVKSingleValueCommand<VkBool32> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


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
typedef MVKCmdSetViewport<kMVKMaxViewportScissorCount> MVKCmdSetViewportMulti;


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
typedef MVKCmdSetScissor<kMVKMaxViewportScissorCount> MVKCmdSetScissorMulti;


#pragma mark -
#pragma mark MVKCmdSetDepthBias

class MVKCmdSetDepthBias : public MVKSingleValueCommand<MVKDepthBias> {

public:
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetDepthBiasEnable

class MVKCmdSetDepthBiasEnable : public MVKSingleValueCommand<VkBool32> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetBlendConstants

class MVKCmdSetBlendConstants : public MVKSingleValueCommand<MVKColor32> {

public:
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetDepthTestEnable

class MVKCmdSetDepthTestEnable : public MVKSingleValueCommand<VkBool32> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetDepthWriteEnable

class MVKCmdSetDepthWriteEnable : public MVKSingleValueCommand<VkBool32> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetDepthClipEnable

class MVKCmdSetDepthClipEnable : public MVKSingleValueCommand<VkBool32> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetDepthCompareOp

class MVKCmdSetDepthCompareOp : public MVKSingleValueCommand<VkCompareOp> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetDepthBounds

class MVKCmdSetDepthBounds : public MVKSingleValueCommand<MVKDepthBounds> {

public:
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetDepthBoundsTestEnable

class MVKCmdSetDepthBoundsTestEnable : public MVKSingleValueCommand<VkBool32> {

public:
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetStencilTestEnable

class MVKCmdSetStencilTestEnable : public MVKSingleValueCommand<VkBool32> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetStencilOp

class MVKCmdSetStencilOp : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkStencilFaceFlags faceMask,
						VkStencilOp failOp,
						VkStencilOp passOp,
						VkStencilOp depthFailOp,
						VkCompareOp compareOp);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkStencilFaceFlags _faceMask;
	VkStencilOp _failOp;
	VkStencilOp _passOp;
	VkStencilOp _depthFailOp;
	VkCompareOp _compareOp;
};


#pragma mark -
#pragma mark MVKCmdSetStencilCompareMask

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


#pragma mark -
#pragma mark MVKCmdSetCullMode

class MVKCmdSetCullMode : public MVKSingleValueCommand<VkCullModeFlags> {

public:
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetFrontFace

class MVKCmdSetFrontFace : public MVKSingleValueCommand<VkFrontFace> {

public:
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetPatchControlPoints

class MVKCmdSetPatchControlPoints : public MVKSingleValueCommand<uint32_t> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetPolygonMode

class MVKCmdSetPolygonMode : public MVKSingleValueCommand<VkPolygonMode> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetLineWidth

class MVKCmdSetLineWidth : public MVKSingleValueCommand<float> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetPrimitiveTopology

class MVKCmdSetPrimitiveTopology : public MVKSingleValueCommand<VkPrimitiveTopology> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetPrimitiveRestartEnable

class MVKCmdSetPrimitiveRestartEnable : public MVKSingleValueCommand<VkBool32> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdSetRasterizerDiscardEnable

class MVKCmdSetRasterizerDiscardEnable : public MVKSingleValueCommand<VkBool32> {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};

