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

/** Old-style debug capture was deprecated in macOS 10.13 and iOS 11.0, and is not available on Mac Catalyst. */
#if MVK_MACOS
#	define MVK_NEED_OLD_DEBUG_CAPTURE    (__MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_13) && !MVK_MACCAT
#endif

#if MVK_IOS
#	define MVK_NEED_OLD_DEBUG_CAPTURE	(__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_11_0)
#endif

#if MVK_TVOS
# define MVK_NEED_OLD_DEBUG_CAPTURE		(__TV_OS_VERSION_MIN_REQUIRED < __TVOS_11_0)
#endif


void MVKGPUCaptureScope::beginScope() {
	if (_mtlCaptureScope) {
		[_mtlCaptureScope beginScope];
	} else if (_isDefault && _isFirstBoundary) {
#if MVK_NEED_OLD_DEBUG_CAPTURE
		[_mtlQueue insertDebugCaptureBoundary];
#endif
	}
	_isFirstBoundary  = false;
}

void MVKGPUCaptureScope::endScope() {
	if (_mtlCaptureScope) {
		[_mtlCaptureScope endScope];
	} else if (_isDefault) {
#if MVK_NEED_OLD_DEBUG_CAPTURE
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
	if (mvkOSVersionIsAtLeast(10.13, 11.0, 1.0)) {
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
}

MVKGPUCaptureScope::~MVKGPUCaptureScope() {
	[_mtlCaptureScope release];
	[_mtlQueue release];
}
