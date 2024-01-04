/*
 * MVKCmdRendering.h
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

	MVKSmallVector<VkSampleLocationEXT, kMVKMaxSampleCount> _sampleLocations;
};


#pragma mark -
#pragma mark MVKCmdSetSampleLocationsEnable

/** Vulkan command to dynamically enable custom sample locations. */
class MVKCmdSetSampleLocationsEnable : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBool32 sampleLocationsEnable);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkBool32 _sampleLocationsEnable;
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
#pragma mark MVKCmdSetDepthBiasEnable

/** Vulkan command to dynamically enable or disable depth bias. */
class MVKCmdSetDepthBiasEnable : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBool32 depthBiasEnable);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkBool32 _depthBiasEnable;
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

	float _blendConstants[4] = {};
};


#pragma mark -
#pragma mark MVKCmdSetDepthTestEnable

/** Vulkan command to dynamically enable depth testing. */
class MVKCmdSetDepthTestEnable : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBool32 depthTestEnable);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkBool32 _depthTestEnable;
};


#pragma mark -
#pragma mark MVKCmdSetDepthWriteEnable

/** Vulkan command to dynamically enable depth writing. */
class MVKCmdSetDepthWriteEnable : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBool32 depthWriteEnable);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkBool32 _depthWriteEnable;
};


#pragma mark -
#pragma mark MVKCmdSetDepthClipEnable

/** Vulkan command to dynamically enable depth clip. */
class MVKCmdSetDepthClipEnable : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBool32 depthClipEnable);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkBool32 _depthClipEnable;
};


#pragma mark -
#pragma mark MVKCmdSetDepthCompareOp

/** Vulkan command to dynamically set the depth compare operation. */
class MVKCmdSetDepthCompareOp : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkCompareOp depthCompareOp);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkCompareOp _depthCompareOp;
};


#pragma mark -
#pragma mark MVKCmdSetStencilTestEnable

/** Vulkan command to dynamically enable stencil testing. */
class MVKCmdSetStencilTestEnable : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBool32 stencilTestEnable);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkBool32 _stencilTestEnable;
};


#pragma mark -
#pragma mark MVKCmdSetStencilOp

/** Vulkan command to dynamically set the stencil operations. */
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


#pragma mark -
#pragma mark MVKCmdSetCullMode

/** Vulkan command to dynamically set the cull mode. */
class MVKCmdSetCullMode : public MVKCommand {

public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        VkCullModeFlags cullMode);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkCullModeFlags _cullMode;
};


#pragma mark -
#pragma mark MVKCmdSetFrontFace

/** Vulkan command to dynamically set the front facing winding order. */
class MVKCmdSetFrontFace : public MVKCommand {

public:
    VkResult setContent(MVKCommandBuffer* cmdBuff,
                        VkFrontFace frontFace);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkFrontFace _frontFace;
};


#pragma mark -
#pragma mark MVKCmdSetPatchControlPoints

/** Vulkan command to dynamically set the number of patch control points. */
class MVKCmdSetPatchControlPoints : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t patchControlPoints);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	uint32_t _patchControlPoints;
};


#pragma mark -
#pragma mark MVKCmdSetPolygonMode

/** Vulkan command to dynamically set the polygon mode. */
class MVKCmdSetPolygonMode : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkPolygonMode polygonMode);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkPolygonMode _polygonMode;
};


#pragma mark -
#pragma mark MVKCmdSetPrimitiveTopology

/** Vulkan command to dynamically set the primitive topology. */
class MVKCmdSetPrimitiveTopology : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkPrimitiveTopology primitiveTopology);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkPrimitiveTopology _primitiveTopology;
};


#pragma mark -
#pragma mark MVKCmdSetPrimitiveRestartEnable

/** Vulkan command to dynamically enable or disable primitive restart functionality. */
class MVKCmdSetPrimitiveRestartEnable : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBool32 primitiveRestartEnable);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkBool32 _primitiveRestartEnable;
};


#pragma mark -
#pragma mark MVKCmdSetRasterizerDiscardEnable

/** Vulkan command to dynamically enable or disable rasterization. */
class MVKCmdSetRasterizerDiscardEnable : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkBool32 rasterizerDiscardEnable);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkBool32 _rasterizerDiscardEnable;
};

