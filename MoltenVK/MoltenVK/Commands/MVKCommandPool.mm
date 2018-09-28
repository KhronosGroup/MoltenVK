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
#include "MVKQueue.h"
#include "MVKDeviceMemory.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.h"
#include "MVKLogging.h"

using namespace std;

#pragma mark -
#pragma mark MVKCommandPool


// Reset all of the command buffers
VkResult MVKCommandPool::reset(VkCommandPoolResetFlags flags) {
	bool releaseRez = mvkAreFlagsEnabled(flags, VK_COMMAND_POOL_RESET_RELEASE_RESOURCES_BIT);

	VkCommandBufferResetFlags cmdBuffFlags = releaseRez ? VK_COMMAND_BUFFER_RESET_RELEASE_RESOURCES_BIT : 0;

	for (auto& cb : _commandBuffers) { cb->reset(cmdBuffFlags); }

	if (releaseRez) { trim(); }

	return VK_SUCCESS;
}


#pragma mark Command Buffers

VkResult MVKCommandPool::allocateCommandBuffers(const VkCommandBufferAllocateInfo* pAllocateInfo,
												VkCommandBuffer* pCmdBuffer) {
	VkResult rslt = VK_SUCCESS;
	uint32_t cbCnt = pAllocateInfo->commandBufferCount;
	for (uint32_t cbIdx = 0; cbIdx < cbCnt; cbIdx++) {
		MVKCommandBuffer* mvkCmdBuff = _commandBufferPool.acquireObject();
		mvkCmdBuff->init(pAllocateInfo);
		_commandBuffers.insert(mvkCmdBuff);
        pCmdBuffer[cbIdx] = mvkCmdBuff->getVkCommandBuffer();
		if (rslt == VK_SUCCESS) { rslt = mvkCmdBuff->getConfigurationResult(); }
	}
	return rslt;
}

void MVKCommandPool::freeCommandBuffers(uint32_t commandBufferCount,
										const VkCommandBuffer* pCommandBuffers) {
	for (uint32_t cbIdx = 0; cbIdx < commandBufferCount; cbIdx++) {
		freeCommandBuffer(MVKCommandBuffer::getMVKCommandBuffer(pCommandBuffers[cbIdx]));
	}
}

void MVKCommandPool::freeCommandBuffer(MVKCommandBuffer* mvkCmdBuff) {
	if ( !mvkCmdBuff ) { return; }

	mvkCmdBuff->reset(VK_COMMAND_BUFFER_RESET_RELEASE_RESOURCES_BIT);
	_commandBuffers.erase(mvkCmdBuff);
	_commandBufferPool.returnObject(mvkCmdBuff);
}

id<MTLCommandBuffer> MVKCommandPool::newMTLCommandBuffer(uint32_t queueIndex) {
	return [[_device->getQueue(_queueFamilyIndex, queueIndex)->getMTLCommandQueue() commandBuffer] retain];
}

void MVKCommandPool::trim() {
	_commandBufferPool.clear();
	_commandEncodingPool.clear();
	_cmdPipelineBarrierPool.clear();
	_cmdBindPipelinePool.clear();
	_cmdBeginRenderPassPool.clear();
	_cmdNextSubpassPool.clear();
	_cmdExecuteCommandsPool.clear();
	_cmdEndRenderPassPool.clear();
	_cmdBindDescriptorSetsPool.clear();
	_cmdSetViewportPool.clear();
	_cmdSetScissorPool.clear();
	_cmdSetLineWidthPool.clear();
	_cmdSetDepthBiasPool.clear();
	_cmdSetBlendConstantsPool.clear();
	_cmdSetDepthBoundsPool.clear();
	_cmdSetStencilCompareMaskPool.clear();
	_cmdSetStencilWriteMaskPool.clear();
	_cmdSetStencilReferencePool.clear();
	_cmdBindVertexBuffersPool.clear();
	_cmdBindIndexBufferPool.clear();
	_cmdDrawPool.clear();
	_cmdDrawIndexedPool.clear();
	_cmdDrawIndirectPool.clear();
	_cmdDrawIndexedIndirectPool.clear();
	_cmdCopyImagePool.clear();
	_cmdBlitImagePool.clear();
	_cmdResolveImagePool.clear();
	_cmdFillBufferPool.clear();
	_cmdUpdateBufferPool.clear();
	_cmdCopyBufferPool.clear();
	_cmdBufferImageCopyPool.clear();
	_cmdClearAttachmentsPool.clear();
	_cmdClearImagePool.clear();
	_cmdBeginQueryPool.clear();
	_cmdEndQueryPool.clear();
	_cmdWriteTimestampPool.clear();
	_cmdResetQueryPoolPool.clear();
	_cmdCopyQueryPoolResultsPool.clear();
	_cmdPushConstantsPool.clear();
	_cmdDispatchPool.clear();
	_cmdDispatchIndirectPool.clear();
	_cmdPushDescriptorSetPool.clear();
	_cmdPushSetWithTemplatePool.clear();
}


#pragma mark Construction

MVKCommandPool::MVKCommandPool(MVKDevice* device,
							   const VkCommandPoolCreateInfo* pCreateInfo) : MVKBaseDeviceObject(device),
	_commandBufferPool(device),
	_commandEncodingPool(device),
	_queueFamilyIndex(pCreateInfo->queueFamilyIndex),
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
    _cmdDispatchIndirectPool(this, true),
    _cmdPushDescriptorSetPool(this, true),
    _cmdPushSetWithTemplatePool(this, true)
{}

MVKCommandPool::~MVKCommandPool() {
	auto cmdBuffs = _commandBuffers;
	for (auto& cb : cmdBuffs) { freeCommandBuffer(cb); }
}

