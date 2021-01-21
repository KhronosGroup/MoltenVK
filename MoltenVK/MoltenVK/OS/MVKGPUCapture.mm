/*
 * MVKGPUCapture.mm
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
#if !MVK_MACCAT
		[_mtlQueue insertDebugCaptureBoundary];
#endif
	}
	_isFirstBoundary  = false;
}

void MVKGPUCaptureScope::endScope() {
	if (_mtlCaptureScope) {
		[_mtlCaptureScope endScope];
	} else if (_isDefault) {
#if !MVK_MACCAT
		[_mtlQueue insertDebugCaptureBoundary];
#endif
	}
}

void MVKGPUCaptureScope::makeDefault() {
	_isDefault = true;
	if (_mtlCaptureScope) {
		[MTLCaptureManager sharedCaptureManager].defaultCaptureScope = _mtlCaptureScope;
	}
}

MVKGPUCaptureScope::MVKGPUCaptureScope(MVKQueue* mvkQueue) {
	_mtlQueue = [mvkQueue->getMTLCommandQueue() retain];	// retained
	if (mvkOSVersionIsAtLeast(kMinOSVersionMTLCaptureScope)) {
		_mtlCaptureScope = [[MTLCaptureManager sharedCaptureManager] newCaptureScopeWithCommandQueue: _mtlQueue];	// retained
		_mtlCaptureScope.label = @(mvkQueue->getName().c_str());
		// Due to a retain bug in Metal when the capture layer is installed, capture scopes
		// can have too many references on them. Release the excess references so the scope--
		// and the command queue--aren't leaked. This is a horrible kludge that depends on
		// Apple not taking internal references to capture scopes, but without it, we could
		// get hung up waiting for a new queue, because the old queues are still outstanding.
		while (_mtlCaptureScope.retainCount > 1) {
			[_mtlCaptureScope release];
		}
	}
}

MVKGPUCaptureScope::~MVKGPUCaptureScope() {
	[_mtlCaptureScope release];
	[_mtlQueue release];
}
