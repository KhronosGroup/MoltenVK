/*
 * MVKCommandPool.mm
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

#include "MVKCommandPool.h"
#include "MVKCommandBuffer.h"
#include "MVKImage.h"
#include "MVKQueue.h"
#include "MVKDeviceMemory.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"
#include "MVKLogging.h"

using namespace std;

#pragma mark -
#pragma mark MVKCommandPool


// Reset all of the command buffers
VkResult MVKCommandPool::reset(VkCommandPoolResetFlags flags) {
	bool releaseRez = mvkAreFlagsEnabled(flags, VK_COMMAND_POOL_RESET_RELEASE_RESOURCES_BIT);

	VkCommandBufferResetFlags cmdBuffFlags = releaseRez ? VK_COMMAND_BUFFER_RESET_RELEASE_RESOURCES_BIT : 0;

	for (auto& cb : _allocatedCommandBuffers) { cb->reset(cmdBuffFlags); }

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
		_allocatedCommandBuffers.insert(mvkCmdBuff);
        pCmdBuffer[cbIdx] = mvkCmdBuff->getVkCommandBuffer();

		// Command buffers start out in a VK_NOT_READY config result
		VkResult cbRslt = mvkCmdBuff->getConfigurationResult();
		if (rslt == VK_SUCCESS && cbRslt != VK_NOT_READY) { rslt = cbRslt; }
	}
	return rslt;
}

void MVKCommandPool::freeCommandBuffers(uint32_t commandBufferCount,
										const VkCommandBuffer* pCommandBuffers) {
	for (uint32_t cbIdx = 0; cbIdx < commandBufferCount; cbIdx++) {
		MVKCommandBuffer* mvkCmdBuff = MVKCommandBuffer::getMVKCommandBuffer(pCommandBuffers[cbIdx]);
		if (_allocatedCommandBuffers.erase(mvkCmdBuff)) {
			mvkCmdBuff->reset(VK_COMMAND_BUFFER_RESET_RELEASE_RESOURCES_BIT);
			_commandBufferPool.returnObject(mvkCmdBuff);
		}
	}
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
							   const VkCommandPoolCreateInfo* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device),
	_commandBufferPool(device),
	_commandEncodingPool(this),
	_queueFamilyIndex(pCreateInfo->queueFamilyIndex),
	_cmdPipelineBarrierPool(this),
	_cmdBindPipelinePool(this),
	_cmdBeginRenderPassPool(this),
	_cmdNextSubpassPool(this),
	_cmdExecuteCommandsPool(this),
	_cmdEndRenderPassPool(this),
	_cmdBindDescriptorSetsPool(this),
	_cmdSetViewportPool(this),
	_cmdSetScissorPool(this),
    _cmdSetLineWidthPool(this),
    _cmdSetDepthBiasPool(this),
    _cmdSetBlendConstantsPool(this),
    _cmdSetDepthBoundsPool(this),
    _cmdSetStencilCompareMaskPool(this),
    _cmdSetStencilWriteMaskPool(this),
    _cmdSetStencilReferencePool(this),
	_cmdBindVertexBuffersPool(this),
	_cmdBindIndexBufferPool(this),
	_cmdDrawPool(this),
	_cmdDrawIndexedPool(this),
	_cmdDrawIndirectPool(this),
	_cmdDrawIndexedIndirectPool(this),
	_cmdCopyImagePool(this),
	_cmdBlitImagePool(this),
    _cmdResolveImagePool(this),
    _cmdFillBufferPool(this),
    _cmdUpdateBufferPool(this),
	_cmdCopyBufferPool(this),
    _cmdBufferImageCopyPool(this),
	_cmdClearAttachmentsPool(this),
	_cmdClearImagePool(this),
    _cmdBeginQueryPool(this),
    _cmdEndQueryPool(this),
	_cmdWriteTimestampPool(this),
    _cmdResetQueryPoolPool(this),
    _cmdCopyQueryPoolResultsPool(this),
	_cmdPushConstantsPool(this),
    _cmdDispatchPool(this),
    _cmdDispatchIndirectPool(this),
    _cmdPushDescriptorSetPool(this),
    _cmdPushSetWithTemplatePool(this),
	_cmdDebugMarkerBeginPool(this),
	_cmdDebugMarkerEndPool(this),
	_cmdDebugMarkerInsertPool(this)
{}

MVKCommandPool::~MVKCommandPool() {
	for (auto& mvkCB : _allocatedCommandBuffers) {
		_commandBufferPool.returnObject(mvkCB);
	}
}

