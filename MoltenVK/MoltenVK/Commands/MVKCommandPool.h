/*
 * MVKCommandPool.h
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
#include "MVKCommandResourceFactory.h"
#include "MVKCommand.h"
#include "MVKCmdPipeline.h"
#include "MVKCmdRenderPass.h"
#include "MVKCmdDispatch.h"
#include "MVKCmdDraw.h"
#include "MVKCmdTransfer.h"
#include "MVKCmdQueries.h"
#include "MVKMTLBufferAllocation.h"
#include <unordered_set>

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKCommandPool

/** 
 * Represents a Vulkan command pool.
 *
 * Access to a command pool in Vulkan is externally synchronized.
 * As such, unless indicated otherwise, access to the content within this command pool 
 * is generally NOT thread-safe.
 *
 * Except where noted otherwise on specific member functions, all access to the content 
 * of this pool should be done during the setContent() function of each MVKCommand, and NOT 
 * during the execution of the command via the MVKCommand::encode() member function.
 */
class MVKCommandPool : public MVKBaseDeviceObject {

public:

#pragma mark Command type pools

	MVKCommandTypePool<MVKCmdPipelineBarrier> _cmdPipelineBarrierPool;

	MVKCommandTypePool<MVKCmdBindPipeline> _cmdBindPipelinePool;

	MVKCommandTypePool<MVKCmdBeginRenderPass> _cmdBeginRenderPassPool;

	MVKCommandTypePool<MVKCmdNextSubpass> _cmdNextSubpassPool;

	MVKCommandTypePool<MVKCmdEndRenderPass> _cmdEndRenderPassPool;

	MVKCommandTypePool<MVKCmdExecuteCommands> _cmdExecuteCommandsPool;

	MVKCommandTypePool<MVKCmdBindDescriptorSets> _cmdBindDescriptorSetsPool;

	MVKCommandTypePool<MVKCmdSetViewport> _cmdSetViewportPool;

	MVKCommandTypePool<MVKCmdSetScissor> _cmdSetScissorPool;

    MVKCommandTypePool<MVKCmdSetLineWidth> _cmdSetLineWidthPool;

    MVKCommandTypePool<MVKCmdSetDepthBias> _cmdSetDepthBiasPool;

    MVKCommandTypePool<MVKCmdSetBlendConstants> _cmdSetBlendConstantsPool;

    MVKCommandTypePool<MVKCmdSetDepthBounds> _cmdSetDepthBoundsPool;

    MVKCommandTypePool<MVKCmdSetStencilCompareMask> _cmdSetStencilCompareMaskPool;

    MVKCommandTypePool<MVKCmdSetStencilWriteMask> _cmdSetStencilWriteMaskPool;

    MVKCommandTypePool<MVKCmdSetStencilReference> _cmdSetStencilReferencePool;

	MVKCommandTypePool<MVKCmdBindVertexBuffers> _cmdBindVertexBuffersPool;

	MVKCommandTypePool<MVKCmdBindIndexBuffer> _cmdBindIndexBufferPool;

	MVKCommandTypePool<MVKCmdDraw> _cmdDrawPool;

	MVKCommandTypePool<MVKCmdDrawIndexed> _cmdDrawIndexedPool;

	MVKCommandTypePool<MVKCmdDrawIndirect> _cmdDrawIndirectPool;

	MVKCommandTypePool<MVKCmdDrawIndexedIndirect> _cmdDrawIndexedIndirectPool;

	MVKCommandTypePool<MVKCmdCopyImage> _cmdCopyImagePool;

	MVKCommandTypePool<MVKCmdBlitImage> _cmdBlitImagePool;

    MVKCommandTypePool<MVKCmdResolveImage> _cmdResolveImagePool;

    MVKCommandTypePool<MVKCmdFillBuffer> _cmdFillBufferPool;

    MVKCommandTypePool<MVKCmdUpdateBuffer> _cmdUpdateBufferPool;

	MVKCommandTypePool<MVKCmdCopyBuffer> _cmdCopyBufferPool;

    MVKCommandTypePool<MVKCmdBufferImageCopy> _cmdBufferImageCopyPool;

	MVKCommandTypePool<MVKCmdClearAttachments> _cmdClearAttachmentsPool;

	MVKCommandTypePool<MVKCmdClearImage> _cmdClearImagePool;

    MVKCommandTypePool<MVKCmdBeginQuery> _cmdBeginQueryPool;

    MVKCommandTypePool<MVKCmdEndQuery> _cmdEndQueryPool;

	MVKCommandTypePool<MVKCmdWriteTimestamp> _cmdWriteTimestampPool;

    MVKCommandTypePool<MVKCmdResetQueryPool> _cmdResetQueryPoolPool;

    MVKCommandTypePool<MVKCmdCopyQueryPoolResults> _cmdCopyQueryPoolResultsPool;

	MVKCommandTypePool<MVKCmdPushConstants> _cmdPushConstantsPool;

    MVKCommandTypePool<MVKCmdDispatch> _cmdDispatchPool;

    MVKCommandTypePool<MVKCmdDispatchIndirect> _cmdDispatchIndirectPool;


#pragma mark Command resources

	/** Allocates command buffers from this pool. */
	VkResult allocateCommandBuffers(const VkCommandBufferAllocateInfo* pAllocateInfo,
									VkCommandBuffer* pCmdBuffer);

	/** Frees the specified command buffers from this pool. */
	void freeCommandBuffers(uint32_t commandBufferCount,
							const VkCommandBuffer* pCommandBuffers);


#pragma mark Construction

	/** Resets the command pool. */
	VkResult reset( VkCommandPoolResetFlags flags);

	MVKCommandPool(MVKDevice* device, const VkCommandPoolCreateInfo* pCreateInfo);

	~MVKCommandPool() override;

private:
	friend class MVKCommandBuffer;

	void addCommandBuffer(MVKCommandBuffer* cmdBuffer);
	void removeCommandBuffer(MVKCommandBuffer* cmdBuffer);

	std::unordered_set<MVKCommandBuffer*> _commandBuffers;
};

