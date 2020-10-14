/*
 * MVKGPUCapture.mm
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

#include "MVKGPUCapture.h"
#include "MVKQueue.h"
#include "MVKOSExtensions.h"
#include "MVKEnvironment.h"


#pragma mark -
#pragma mark MVKGPUCaptureScope

#if MVK_MACOS
static MVKOSVersion kMinOSVersionMTLCaptureScope = 10.13;
#endif
#if MVK_IOS_OR_TVOS
static MVKOSVersion kMinOSVersionMTLCaptureScope = 11.0;
#endif

void MVKGPUCaptureScope::beginScope() {
	if (_mtlCaptureScope) {
		[_mtlCaptureScope beginScope];
	} else if (_isDefault && _isFirstBoundary) {
		[_mtlQueue insertDebugCaptureBoundary];
	}
	_isFirstBoundary  = false;
}

void MVKGPUCaptureScope::endScope() {
	if (_mtlCaptureScope) {
		[_mtlCaptureScope endScope];
	} else if (_isDefault) {
		[_mtlQueue insertDebugCaptureBoundary];
	}
}

void MVKGPUCaptureScope::makeDefault() {
	_isDefault = true;
	if (_mtlCaptureScope) {
		[MTLCaptureManager sharedCaptureManager].defaultCaptureScope = _mtlCaptureScope;
	}
}

MVKGPUCaptureScope::MVKGPUCaptureScope(MVKQueue* mvkQueue) : _queue(mvkQueue) {
	_mtlQueue = [_queue->getMTLCommandQueue() retain];	// retained
	if (mvkOSVersionIsAtLeast(kMinOSVersionMTLCaptureScope)) {
		_mtlCaptureScope = [[MTLCaptureManager sharedCaptureManager] newCaptureScopeWithCommandQueue: _mtlQueue];	// retained
		_mtlCaptureScope.label = @(_queue->getName().c_str());
	}
}

MVKGPUCaptureScope::~MVKGPUCaptureScope() {
	[_mtlCaptureScope release];
	[_mtlQueue release];
}
