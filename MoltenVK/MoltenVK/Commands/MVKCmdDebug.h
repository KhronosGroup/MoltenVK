/*
 * MVKCmdDebug.h
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

#pragma once

#include "MVKCommand.h"

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKCmdDebugMarker

/**Abstract Vulkan class to support debug markers. */
class MVKCmdDebugMarker : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff, const char* pMarkerName, const float color[4]);

	~MVKCmdDebugMarker() override;

protected:
	NSString* _markerName = nil;
};


#pragma mark -
#pragma mark MVKCmdDebugMarkerBegin

class MVKCmdDebugMarkerBegin : public MVKCmdDebugMarker {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

};


#pragma mark -
#pragma mark MVKCmdDebugMarkerEnd

class MVKCmdDebugMarkerEnd : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

};


#pragma mark -
#pragma mark MVKCmdDebugMarkerInsert

class MVKCmdDebugMarkerInsert : public MVKCmdDebugMarker {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

};


#pragma mark -
#pragma mark Support functions

void mvkPushDebugGroup(id<MTLCommandBuffer> mtlCmdBuffer, NSString* name);

void mvkPopDebugGroup(id<MTLCommandBuffer> mtlCmdBuffer);

