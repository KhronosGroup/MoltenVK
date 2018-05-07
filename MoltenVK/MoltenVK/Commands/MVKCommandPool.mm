/*
 * MVKCommandPool.mm
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

#include "MVKCommandPool.h"
#include "MVKCommandBuffer.h"
#include "MVKImage.h"
#include "MVKDeviceMemory.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.h"
#include "MVKLogging.h"

using namespace std;

#pragma mark -
#pragma mark MVKCommandPool


VkResult MVKCommandPool::reset(VkCommandPoolResetFlags flags) {

	// Reset all of the command buffers
    for (auto& cb : _commandBuffers) {
		cb->reset(VK_COMMAND_BUFFER_RESET_RELEASE_RESOURCES_BIT);
	}

	return VK_SUCCESS;
}


#pragma mark Command Buffers

VkResult MVKCommandPool::allocateCommandBuffers(const VkCommandBufferAllocateInfo* pAllocateInfo,
												VkCommandBuffer* pCmdBuffer) {
	VkResult rslt = VK_SUCCESS;
	uint32_t cbCnt = pAllocateInfo->commandBufferCount;
	for (uint32_t cbIdx = 0; cbIdx < cbCnt; cbIdx++) {
		MVKCommandBuffer* mvkCmdBuff = new MVKCommandBuffer(_device, pAllocateInfo);
        pCmdBuffer[cbIdx] = mvkCmdBuff->getVkCommandBuffer();
		if (rslt == VK_SUCCESS) { rslt = mvkCmdBuff->getConfigurationResult(); }
	}
	return rslt;
}

void MVKCommandPool::freeCommandBuffers(uint32_t commandBufferCount,
										const VkCommandBuffer* pCommandBuffers) {
	for (uint32_t cbIdx = 0; cbIdx < commandBufferCount; cbIdx++) {
		VkCommandBuffer cmdBuff = pCommandBuffers[cbIdx];
		if (cmdBuff) { MVKCommandBuffer::getMVKCommandBuffer(cmdBuff)->destroy(); }
	}
}

void MVKCommandPool::addCommandBuffer(MVKCommandBuffer* cmdBuffer) {
	_commandBuffers.insert(cmdBuffer);
}

void MVKCommandPool::removeCommandBuffer(MVKCommandBuffer* cmdBuffer) {
	_commandBuffers.erase(cmdBuffer);
}


#pragma mark Construction

MVKCommandPool::MVKCommandPool(MVKDevice* device,
							   const VkCommandPoolCreateInfo* pCreateInfo) : MVKBaseDeviceObject(device),
	_cmdPipelineBarrierPool(this, true),
	_cmdBindPipelinePool(this, true),
	_cmdBeginRenderPassPool(this, true),
	_cmdNextSubpassPool(this, true),
	_cmdExecuteCommandsPool(this, true),
	_cmdEndRenderPassPool(this, true),
	_cmdBindDescriptorSetsPool(this, true),
	_cmdSetViewportPool(this, true),
	_cmdSetScissorPool(this, true),
    _cmdSetLineWidthPool(this, true),
    _cmdSetDepthBiasPool(this, true),
    _cmdSetBlendConstantsPool(this, true),
    _cmdSetDepthBoundsPool(this, true),
    _cmdSetStencilCompareMaskPool(this, true),
    _cmdSetStencilWriteMaskPool(this, true),
    _cmdSetStencilReferencePool(this, true),
	_cmdBindVertexBuffersPool(this, true),
	_cmdBindIndexBufferPool(this, true),
	_cmdDrawPool(this, true),
	_cmdDrawIndexedPool(this, true),
	_cmdDrawIndirectPool(this, true),
	_cmdDrawIndexedIndirectPool(this, true),
	_cmdCopyImagePool(this, true),
	_cmdBlitImagePool(this, true),
    _cmdResolveImagePool(this, true),
    _cmdFillBufferPool(this, true),
    _cmdUpdateBufferPool(this, true),
	_cmdCopyBufferPool(this, true),
    _cmdBufferImageCopyPool(this, true),
	_cmdClearAttachmentsPool(this, true),
	_cmdClearImagePool(this, true),
    _cmdBeginQueryPool(this, true),
    _cmdEndQueryPool(this, true),
	_cmdWriteTimestampPool(this, true),
    _cmdResetQueryPoolPool(this, true),
    _cmdCopyQueryPoolResultsPool(this, true),
	_cmdPushConstantsPool(this, true),
    _cmdDispatchPool(this, true),
    _cmdDispatchIndirectPool(this, true)
{}

// TODO: Destroying a command pool implicitly destroys all command buffers and commands created from it.

MVKCommandPool::~MVKCommandPool() {}

