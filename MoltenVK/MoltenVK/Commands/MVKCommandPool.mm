/*
 * MVKCommandPool.mm
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

#include "MVKCommandPool.h"
#include "MVKCommandBuffer.h"
#include "MVKImage.h"
#include "MVKQueue.h"
#include "MVKDeviceMemory.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"

using namespace std;

#pragma mark -
#pragma mark MVKCommandPool


// Reset all of the command buffers
VkResult MVKCommandPool::reset(VkCommandPoolResetFlags flags) {
	bool releaseRez = mvkAreAllFlagsEnabled(flags, VK_COMMAND_POOL_RESET_RELEASE_RESOURCES_BIT);

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
		if (cbRslt != VK_NOT_READY) {
			if (rslt == VK_SUCCESS) { rslt = cbRslt; }
			freeCommandBuffers(1, &pCmdBuffer[cbIdx]);
		}
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

id<MTLCommandBuffer> MVKCommandPool::getMTLCommandBuffer(MVKCommandUse cmdUse, uint32_t queueIndex) {
	return _device->getQueue(_queueFamilyIndex, queueIndex)->getMTLCommandBuffer(cmdUse, true);
}

// Clear the command type pool member variables.
void MVKCommandPool::trim() {
#	define MVK_CMD_TYPE_POOL(cmdType)  _cmd ##cmdType ##Pool.clear();
#	include "MVKCommandTypePools.def"
}


#pragma mark Construction

MVKCommandPool::MVKCommandPool(MVKDevice* device,
							   const VkCommandPoolCreateInfo* pCreateInfo,
							   bool usePooling) :
	MVKVulkanAPIDeviceObject(device),

// Initialize the command type pool member variables.
#	define MVK_CMD_TYPE_POOL_LAST(cmdType)  _cmd ##cmdType ##Pool(usePooling)
#	define MVK_CMD_TYPE_POOL(cmdType)  MVK_CMD_TYPE_POOL_LAST(cmdType),
#	include "MVKCommandTypePools.def"
	,
	_commandBufferPool(device, usePooling),
	_commandEncodingPool(this),
	_queueFamilyIndex(pCreateInfo->queueFamilyIndex)
{}

MVKCommandPool::~MVKCommandPool() {
	for (auto& mvkCB : _allocatedCommandBuffers) {
		_commandBufferPool.returnObject(mvkCB);
	}
}

#pragma mark -
#pragma mark MVKCommand subclass getTypePool() functions

// Implementations of the MVKCommand subclass getTypePool() functions.
#define MVK_TMPLT_DECL  template<>
#define MVK_CMD_TYPE_POOL(cmdType)					  										\
MVKCommandTypePool<MVKCommand>* MVKCmd ##cmdType ::getTypePool(MVKCommandPool* cmdPool) {	\
	return (MVKCommandTypePool<MVKCommand>*)&cmdPool->_cmd  ##cmdType ##Pool;				\
}
#include "MVKCommandTypePools.def"


