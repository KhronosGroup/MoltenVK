/*
 * MVKGPUCapture.mm
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

#include "MVKGPUCapture.h"
#include "MVKOSExtensions.h"


#pragma mark -
#pragma mark MVKGPUCaptureScope


void MVKGPUCaptureScope::beginScope() {
	if (_mtlCaptureScope) {
		[_mtlCaptureScope beginScope];
	}
	_isFirstBoundary  = false;
}

void MVKGPUCaptureScope::endScope() {
	if (_mtlCaptureScope) {
		[_mtlCaptureScope endScope];
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
	_mtlCaptureScope = [[MTLCaptureManager sharedCaptureManager] newCaptureScopeWithCommandQueue: _mtlQueue];	// retained
	mvkQueue->setMetalObjectLabel(_mtlCaptureScope, @(mvkQueue->getName().c_str()));

	// Due to an retain bug in Metal when the capture layer is installed, capture scopes
	// on older OS versions can have too many references on them. If so, release the excess
	// references so the scope, and command queue, aren't leaked. This is a horrible kludge
	// that depends on Apple not taking internal references to capture scopes, but without it,
	// we could get hung up waiting for a new queue, because the old queues are still outstanding.
	// This bug was fixed by Apple in macOS 12.4 and iOS 15.4.
	if ( !mvkOSVersionIsAtLeast(12.04, 15.04, 1.0) ) {
		while (_mtlCaptureScope.retainCount > 1) {
			[_mtlCaptureScope release];
		}
	}
}

MVKGPUCaptureScope::~MVKGPUCaptureScope() {
	[_mtlCaptureScope release];
	[_mtlQueue release];
}
