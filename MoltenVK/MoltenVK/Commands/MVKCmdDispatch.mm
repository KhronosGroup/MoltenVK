/*
 * MVKMVKCmdDispatch.mm
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

#include "MVKCmdDispatch.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKBuffer.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.h"


#pragma mark -
#pragma mark MVKCmdDraw

void MVKCmdDispatch::setContent(uint32_t x, uint32_t y, uint32_t z) {
    _mtlThreadgroupCount.width = x;
    _mtlThreadgroupCount.height = y;
    _mtlThreadgroupCount.depth = z;
}

void MVKCmdDispatch::encode(MVKCommandEncoder* cmdEncoder) {
//    MVKLogDebug("vkCmdDispatch() dispatching (%d, %d, %d) threadgroups.", _x, _y, _z);

	cmdEncoder->finalizeDispatchState();	// Ensure all updated state has been submitted to Metal
    [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) dispatchThreadgroups: _mtlThreadgroupCount
															 threadsPerThreadgroup: cmdEncoder->_mtlThreadgroupSize];
}

MVKCmdDispatch::MVKCmdDispatch(MVKCommandTypePool<MVKCmdDispatch>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {
}


#pragma mark -
#pragma mark MVKCmdDispatchIndirect

void MVKCmdDispatchIndirect::setContent(VkBuffer buffer, VkDeviceSize offset) {
	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
	_mtlIndirectBuffer = mvkBuffer->getMTLBuffer();
	_mtlIndirectBufferOffset = mvkBuffer->getMTLBufferOffset() + offset;
}

void MVKCmdDispatchIndirect::encode(MVKCommandEncoder* cmdEncoder) {
//    MVKLogDebug("vkCmdDispatchIndirect() dispatching indirectly.");

    cmdEncoder->finalizeDispatchState();	// Ensure all updated state has been submitted to Metal
    [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) dispatchThreadgroupsWithIndirectBuffer: _mtlIndirectBuffer
																				indirectBufferOffset: _mtlIndirectBufferOffset
																			   threadsPerThreadgroup: cmdEncoder->_mtlThreadgroupSize];
}

MVKCmdDispatchIndirect::MVKCmdDispatchIndirect(MVKCommandTypePool<MVKCmdDispatchIndirect>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}




#pragma mark -
#pragma mark Command creation functions

void mvkCmdDispatch(MVKCommandBuffer* cmdBuff, uint32_t x, uint32_t y, uint32_t z) {
	MVKCmdDispatch* cmd = cmdBuff->_commandPool->_cmdDispatchPool.acquireObject();
	cmd->setContent(x, y, z);
	cmdBuff->addCommand(cmd);
}

void mvkCmdDispatchIndirect(MVKCommandBuffer* cmdBuff, VkBuffer buffer, VkDeviceSize offset) {
	MVKCmdDispatchIndirect* cmd = cmdBuff->_commandPool->_cmdDispatchIndirectPool.acquireObject();
	cmd->setContent(buffer, offset);
	cmdBuff->addCommand(cmd);
}


