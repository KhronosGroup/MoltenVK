/*
 * MVKCmdDebug.mm
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCmdDebug.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"

#include "MVKLogging.h"

#pragma mark -
#pragma mark MVKCmdDebugMarker

void MVKCmdDebugMarker::setContent(const char* pMarkerName, const float color[4]) {
	[_markerName release];
	_markerName = [[NSString alloc] initWithUTF8String: pMarkerName];	// retained
}

MVKCmdDebugMarker::MVKCmdDebugMarker(MVKCommandTypePool<MVKCmdDebugMarker>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

MVKCmdDebugMarker::~MVKCmdDebugMarker() {
	[_markerName release];
}

#pragma mark -
#pragma mark MVKCmdDebugMarkerBegin

// Vulkan debug groups are more general than Metal's.
// If a renderpass is active, push on the render command encoder, otherwise push on the command buffer.
void MVKCmdDebugMarkerBegin::encode(MVKCommandEncoder* cmdEncoder) {
	id<MTLRenderCommandEncoder> mtlCmdEnc = cmdEncoder->_mtlRenderEncoder;
	if (mtlCmdEnc) {
		[mtlCmdEnc pushDebugGroup: _markerName];
	} else {
		mvkPushDebugGroup(cmdEncoder->_mtlCmdBuffer, _markerName);
	}
}

MVKCmdDebugMarkerBegin::MVKCmdDebugMarkerBegin(MVKCommandTypePool<MVKCmdDebugMarkerBegin>* pool)
	: MVKCmdDebugMarker::MVKCmdDebugMarker((MVKCommandTypePool<MVKCmdDebugMarker>*)pool) {}


#pragma mark -
#pragma mark MVKCmdDebugMarkerEnd

// Vulkan debug groups are more general than Metal's.
// If a renderpass is active, pop from the render command encoder, otherwise pop from the command buffer.
void MVKCmdDebugMarkerEnd::encode(MVKCommandEncoder* cmdEncoder) {
	id<MTLRenderCommandEncoder> mtlCmdEnc = cmdEncoder->_mtlRenderEncoder;
	if (mtlCmdEnc) {
		[mtlCmdEnc popDebugGroup];
	} else {
		mvkPopDebugGroup(cmdEncoder->_mtlCmdBuffer);
	}
}

MVKCmdDebugMarkerEnd::MVKCmdDebugMarkerEnd(MVKCommandTypePool<MVKCmdDebugMarkerEnd>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdDebugMarkerInsert

void MVKCmdDebugMarkerInsert::encode(MVKCommandEncoder* cmdEncoder) {
	[cmdEncoder->getMTLEncoder() insertDebugSignpost: _markerName];
}

MVKCmdDebugMarkerInsert::MVKCmdDebugMarkerInsert(MVKCommandTypePool<MVKCmdDebugMarkerInsert>* pool)
	: MVKCmdDebugMarker::MVKCmdDebugMarker((MVKCommandTypePool<MVKCmdDebugMarker>*)pool) {}


#pragma mark -
#pragma mark Command creation functions

void mvkCmdDebugMarkerBegin(MVKCommandBuffer* cmdBuff, const VkDebugMarkerMarkerInfoEXT* pMarkerInfo) {
	MVKCmdDebugMarkerBegin* cmd = cmdBuff->_commandPool->_cmdDebugMarkerBeginPool.acquireObject();
	cmd->setContent(pMarkerInfo->pMarkerName, pMarkerInfo->color);
	cmdBuff->addCommand(cmd);
}

void mvkCmdDebugMarkerEnd(MVKCommandBuffer* cmdBuff) {
	MVKCmdDebugMarkerEnd* cmd = cmdBuff->_commandPool->_cmdDebugMarkerEndPool.acquireObject();
	cmdBuff->addCommand(cmd);
}

void mvkCmdDebugMarkerInsert(MVKCommandBuffer* cmdBuff, const VkDebugMarkerMarkerInfoEXT* pMarkerInfo) {
	MVKCmdDebugMarkerInsert* cmd = cmdBuff->_commandPool->_cmdDebugMarkerInsertPool.acquireObject();
	cmd->setContent(pMarkerInfo->pMarkerName, pMarkerInfo->color);
	cmdBuff->addCommand(cmd);
}

void mvkCmdBeginDebugUtilsLabel(MVKCommandBuffer* cmdBuff, const VkDebugUtilsLabelEXT* pLabelInfo) {
	MVKCmdDebugMarkerBegin* cmd = cmdBuff->_commandPool->_cmdDebugMarkerBeginPool.acquireObject();
	cmd->setContent(pLabelInfo->pLabelName, pLabelInfo->color);
	cmdBuff->addCommand(cmd);
}

void mvkCmdEndDebugUtilsLabel(MVKCommandBuffer* cmdBuff) {
	MVKCmdDebugMarkerEnd* cmd = cmdBuff->_commandPool->_cmdDebugMarkerEndPool.acquireObject();
	cmdBuff->addCommand(cmd);
}

void mvkCmdInsertDebugUtilsLabel(MVKCommandBuffer* cmdBuff, const VkDebugUtilsLabelEXT* pLabelInfo) {
	MVKCmdDebugMarkerInsert* cmd = cmdBuff->_commandPool->_cmdDebugMarkerInsertPool.acquireObject();
	cmd->setContent(pLabelInfo->pLabelName, pLabelInfo->color);
	cmdBuff->addCommand(cmd);
}


#pragma mark -
#pragma mark Support functions

void mvkPushDebugGroup(id<MTLCommandBuffer> mtlCmdBuffer, NSString* name) {
	if ([mtlCmdBuffer respondsToSelector: @selector(pushDebugGroup:)]) {
		[mtlCmdBuffer pushDebugGroup: name];
	}
}

void mvkPopDebugGroup(id<MTLCommandBuffer> mtlCmdBuffer) {
	if ([mtlCmdBuffer respondsToSelector: @selector(popDebugGroup)]) {
		[mtlCmdBuffer popDebugGroup];
	}
}
