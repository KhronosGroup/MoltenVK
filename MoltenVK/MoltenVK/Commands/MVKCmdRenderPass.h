/*
 * MVKCmdRenderPass.h
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKVector.h"

#import <Metal/Metal.h>

class MVKRenderPass;
class MVKFramebuffer;


#pragma mark -
#pragma mark MVKCmdBeginRenderPass

/** Vulkan command to begin a render pass. */
class MVKCmdBeginRenderPass : public MVKCommand, public MVKLoadStoreOverrideMixin {

public:
	void setContent(const VkRenderPassBeginInfo* pRenderPassBegin,
					VkSubpassContents contents);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdBeginRenderPass(MVKCommandTypePool<MVKCmdBeginRenderPass>* pool);

private:
	VkRenderPassBeginInfo _info;
	VkSubpassContents _contents;
	MVKRenderPass* _renderPass;
	MVKFramebuffer* _framebuffer;
	MVKVectorInline<VkClearValue, 8> _clearValues;
};


#pragma mark -
#pragma mark MVKCmdNextSubpass

/** Vulkan command to begin a render pass. */
class MVKCmdNextSubpass : public MVKCommand {

public:
	void setContent(VkSubpassContents contents);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdNextSubpass(MVKCommandTypePool<MVKCmdNextSubpass>* pool);

private:
	VkSubpassContents _contents;
};


#pragma mark -
#pragma mark MVKCmdEndRenderPass

/** Vulkan command to end the current render pass. */
class MVKCmdEndRenderPass : public MVKCommand {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdEndRenderPass(MVKCommandTypePool<MVKCmdEndRenderPass>* pool);
};


#pragma mark -
#pragma mark MVKCmdExecuteCommands

/** Vulkan command to execute secondary command buffers. */
class MVKCmdExecuteCommands : public MVKCommand {

public:
	void setContent(uint32_t commandBuffersCount, const VkCommandBuffer* pCommandBuffers);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdExecuteCommands(MVKCommandTypePool<MVKCmdExecuteCommands>* pool);

private:
	MVKVectorInline<MVKCommandBuffer*, 64> _secondaryCommandBuffers;
};

#pragma mark -
#pragma mark MVKCmdSetViewport

/** Vulkan command to set the viewports. */
class MVKCmdSetViewport : public MVKCommand {

public:
	void setContent(uint32_t firstViewport, uint32_t viewportCount, const VkViewport* pViewports);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdSetViewport(MVKCommandTypePool<MVKCmdSetViewport>* pool);

private:
	uint32_t _firstViewport;
	MVKVectorInline<MTLViewport, kMVKCachedViewportScissorCount> _mtlViewports;
};


#pragma mark -
#pragma mark MVKCmdSetScissor

/** Vulkan command to set the scissor rectangles. */
class MVKCmdSetScissor : public MVKCommand {

public:
	void setContent(uint32_t firstScissor, uint32_t scissorCount, const VkRect2D* pScissors);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdSetScissor(MVKCommandTypePool<MVKCmdSetScissor>* pool);

private:
	uint32_t _firstScissor;
	MVKVectorInline<MTLScissorRect, kMVKCachedViewportScissorCount> _mtlScissors;
};


#pragma mark -
#pragma mark MVKCmdSetLineWidth

/** Vulkan command to set the line width. */
class MVKCmdSetLineWidth : public MVKCommand {

public:
    void setContent(float lineWidth);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdSetLineWidth(MVKCommandTypePool<MVKCmdSetLineWidth>* pool);

private:
    float _lineWidth;
};


#pragma mark -
#pragma mark MVKCmdSetDepthBias

/** Vulkan command to set the depth bias. */
class MVKCmdSetDepthBias : public MVKCommand {

public:
    void setContent(float depthBiasConstantFactor,
                    float depthBiasSlopeFactor,
                    float depthBiasClamp);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdSetDepthBias(MVKCommandTypePool<MVKCmdSetDepthBias>* pool);

private:
    float _depthBiasConstantFactor;
    float _depthBiasClamp;
    float _depthBiasSlopeFactor;
};


#pragma mark -
#pragma mark MVKCmdSetBlendConstants

/** Vulkan command to set the blend constants. */
class MVKCmdSetBlendConstants : public MVKCommand {

public:
    void setContent(const float blendConst[4]);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdSetBlendConstants(MVKCommandTypePool<MVKCmdSetBlendConstants>* pool);

private:
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
    void setContent(float minDepthBounds, float maxDepthBounds);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdSetDepthBounds(MVKCommandTypePool<MVKCmdSetDepthBounds>* pool);

private:
    float _minDepthBounds;
    float _maxDepthBounds;
};


#pragma mark -
#pragma mark MVKCmdSetStencilCompareMask

/** Vulkan command to set the stencil compare mask. */
class MVKCmdSetStencilCompareMask : public MVKCommand {

public:
    void setContent(VkStencilFaceFlags faceMask, uint32_t stencilCompareMask);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdSetStencilCompareMask(MVKCommandTypePool<MVKCmdSetStencilCompareMask>* pool);

private:
    VkStencilFaceFlags _faceMask;
    uint32_t _stencilCompareMask;
};


#pragma mark -
#pragma mark MVKCmdSetStencilWriteMask

/** Vulkan command to set the stencil write mask. */
class MVKCmdSetStencilWriteMask : public MVKCommand {

public:
    void setContent(VkStencilFaceFlags faceMask, uint32_t stencilWriteMask);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdSetStencilWriteMask(MVKCommandTypePool<MVKCmdSetStencilWriteMask>* pool);

private:
    VkStencilFaceFlags _faceMask;
    uint32_t _stencilWriteMask;
};


#pragma mark -
#pragma mark MVKCmdSetStencilReference

/** Vulkan command to set the stencil reference value. */
class MVKCmdSetStencilReference : public MVKCommand {

public:
    void setContent(VkStencilFaceFlags faceMask, uint32_t stencilReference);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdSetStencilReference(MVKCommandTypePool<MVKCmdSetStencilReference>* pool);

private:
    VkStencilFaceFlags _faceMask;
    uint32_t _stencilReference;
};


#pragma mark -
#pragma mark Command creation functions

/** Adds a begin render pass command to the specified command buffer. */
void mvkCmdBeginRenderPass(MVKCommandBuffer* cmdBuff,
						   const VkRenderPassBeginInfo* pRenderPassBegin,
						   VkSubpassContents contents);

/** Adds a next render pass command to the specified command buffer. */
void mvkCmdNextSubpass(MVKCommandBuffer* cmdBuff, VkSubpassContents contents);

/** Adds an end render pass command to the specified command buffer. */
void mvkCmdEndRenderPass(MVKCommandBuffer* cmdBuff);

/** Adds an execute commands command to the specified command buffer. */
void mvkCmdExecuteCommands(MVKCommandBuffer* cmdBuff,
						   uint32_t commandBufferCount,
						   const VkCommandBuffer* pCommandBuffers);

/** Adds a set viewport command to the specified command buffer. */
void mvkCmdSetViewport(MVKCommandBuffer* cmdBuff,
					   uint32_t firstViewport,
					   uint32_t viewportCount,
					   const VkViewport* pViewports);

/** Adds a set scissor command to the specified command buffer. */
void mvkCmdSetScissor(MVKCommandBuffer* cmdBuff,
					  uint32_t firstScissor,
					  uint32_t scissorCount,
					  const VkRect2D* pScissors);

/** Adds a set line width command to the specified command buffer. */
void mvkCmdSetLineWidth(MVKCommandBuffer* cmdBuff, float lineWidth);

/** Adds a set depth bias command to the specified command buffer. */
void mvkCmdSetDepthBias(MVKCommandBuffer* cmdBuff,
                        float depthBiasConstantFactor,
                        float depthBiasClamp,
                        float depthBiasSlopeFactor);

/** Adds a set blend constants command to the specified command buffer. */
void mvkCmdSetBlendConstants(MVKCommandBuffer* cmdBuff,
                             const float blendConst[4]);

/** Adds a set depth bounds command to the specified command buffer. */
void mvkCmdSetDepthBounds(MVKCommandBuffer* cmdBuff,
                          float minDepthBounds,
                          float maxDepthBounds);

/** Adds a set stencil compare mask command to the specified command buffer. */
void mvkCmdSetStencilCompareMask(MVKCommandBuffer* cmdBuff,
                                 VkStencilFaceFlags faceMask,
                                 uint32_t stencilCompareMask);

/** Adds a set stencil write mask command to the specified command buffer. */
void mvkCmdSetStencilWriteMask(MVKCommandBuffer* cmdBuff,
                               VkStencilFaceFlags faceMask,
                               uint32_t stencilWriteMask);

/** Adds a set stencil reference value command to the specified command buffer. */
void mvkCmdSetStencilReference(MVKCommandBuffer* cmdBuff,
                               VkStencilFaceFlags faceMask,
                               uint32_t stencilReference);

