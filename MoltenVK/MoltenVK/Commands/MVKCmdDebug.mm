/*
 * MVKCmdDebug.mm
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

#include "MVKCmdDebug.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"

#include "MVKLogging.h"

#pragma mark -
#pragma mark MVKCmdDebugMarker

void MVKCmdDebugMarker::setContent(const char* pMarkerName, const float color[4]) {
	[_markerName release];
	_markerName = [@(pMarkerName) retain];
}

MVKCmdDebugMarker::MVKCmdDebugMarker(MVKCommandTypePool<MVKCmdDebugMarker>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

MVKCmdDebugMarker::~MVKCmdDebugMarker() {
	[_markerName release];
}

#pragma mark -
#pragma mark MVKCmdDebugMarkerBegin

// Vulkan debug groups are more general than Metal's.
// Always push on command buffer instead of the encoder.
void MVKCmdDebugMarkerBegin::encode(MVKCommandEncoder* cmdEncoder) {
	[cmdEncoder->_mtlCmdBuffer pushDebugGroup: _markerName];
}

MVKCmdDebugMarkerBegin::MVKCmdDebugMarkerBegin(MVKCommandTypePool<MVKCmdDebugMarkerBegin>* pool)
	: MVKCmdDebugMarker::MVKCmdDebugMarker((MVKCommandTypePool<MVKCmdDebugMarker>*)pool) {}


#pragma mark -
#pragma mark MVKCmdDebugMarkerEnd

// Vulkan debug groups are more general than Metal's.
// Always pop from command buffer instead of the encoder.
void MVKCmdDebugMarkerEnd::encode(MVKCommandEncoder* cmdEncoder) {
	[cmdEncoder->_mtlCmdBuffer popDebugGroup];
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


