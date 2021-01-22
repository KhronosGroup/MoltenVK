/*
 * MVKGPUCapture.h
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKQueue.h"

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKGPUCaptureScope

/**
 * Represents a capture scope for capturing GPU activity within Xcode.
 *
 * If the OS supports the MTLCaptureScope protocol, this class creates and wraps an MTLCaptureScope
 * instance for a MTLQueue, otherwise it interacts directly with the MTLQueue to define capture boundaries.
 */
class MVKGPUCaptureScope : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; }

	/** Marks the beginning boundary of a capture scope. */
	void beginScope();

	/** Marks the end boundary of a capture scope. */
	void endScope();

	/** Makes this instance the default capture scope within Xcode. */
	void makeDefault();

	/**
	 * Constructs an instance for the specified queue.
	 *
	 * If the queue has a debug name, it will be displayed in Xcode when selecting a capture scope to use.
	 */
	MVKGPUCaptureScope(MVKQueue* mvkQueue);

	~MVKGPUCaptureScope() override;

protected:
	id<MTLCaptureScope> _mtlCaptureScope = nil;
	id<MTLCommandQueue> _mtlQueue = nil;
	bool _isFirstBoundary = true;
	bool _isDefault = false;
};





