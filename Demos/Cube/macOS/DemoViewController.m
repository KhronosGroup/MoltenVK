/*
 * DemoViewController.m
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

#import "DemoViewController.h"
#import <QuartzCore/CAMetalLayer.h>
#import <CoreVideo/CVDisplayLink.h>

#include <MoltenVK/mvk_vulkan.h>
#include "cube.c"


#pragma mark -
#pragma mark DemoViewController

@implementation DemoViewController {
	CVDisplayLinkRef _displayLink;
	struct demo demo;
	uint32_t _maxFrameCount;
	uint64_t _frameCount;
	BOOL _stop;
	BOOL _useDisplayLink;
}

/** Since this is a single-view app, initialize Vulkan as view is appearing. */
-(void) viewWillAppear {
	[super viewWillAppear];

	self.view.wantsLayer = YES;		// Back the view with a layer created by the makeBackingLayer method.

	// Enabling this will sync the rendering loop with the natural display link
	// (monitor refresh rate, typically 60 fps). Disabling this will allow the
	// rendering loop to run flat out, limited only by the rendering speed.
	_useDisplayLink = YES;

	// If this value is set to zero, the demo will render frames until the window is closed.
	// If this value is not zero, it establishes a maximum number of frames that will be
	// rendered, and once this count has been reached, the demo will stop rendering.
	// Once rendering is finished, if _useDisplayLink is false, the demo will immediately
	// clean up the Vulkan objects, or if _useDisplayLink is true, the demo will delay
	// cleaning up Vulkan objects until the window is closed.
	_maxFrameCount = 0;

	VkPresentModeKHR vkPresentMode = _useDisplayLink ? VK_PRESENT_MODE_FIFO_KHR : VK_PRESENT_MODE_IMMEDIATE_KHR;
	char vkPresentModeStr[64];
	sprintf(vkPresentModeStr, "%d", vkPresentMode);

	const char* argv[] = { "cube", "--present_mode", vkPresentModeStr };
	int argc = sizeof(argv)/sizeof(char*);
	demo_main(&demo, self.view.layer, argc, argv);

	_stop = NO;
	_frameCount = 0;
	if (_useDisplayLink) {
		CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
		CVDisplayLinkSetOutputCallback(_displayLink, &DisplayLinkCallback, self);
		CVDisplayLinkStart(_displayLink);
	} else {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			do {
				demo_draw(&demo);
				_stop = _stop || (_maxFrameCount && ++_frameCount >= _maxFrameCount);
			} while( !_stop );
			demo_cleanup(&demo);
		});
	}
}

-(void) viewDidDisappear {
	_stop = YES;
	if (_useDisplayLink) {
		CVDisplayLinkRelease(_displayLink);
		demo_cleanup(&demo);
	}

	[super viewDidDisappear];
}


#pragma mark Display loop callback function

/** Rendering loop callback function for use with a CVDisplayLink. */
static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink,
									const CVTimeStamp* now,
									const CVTimeStamp* outputTime,
									CVOptionFlags flagsIn,
									CVOptionFlags* flagsOut,
									void* target) {
	DemoViewController* demoVC =(DemoViewController*)target;
	if ( !demoVC->_stop ) {
		demo_draw(&demoVC->demo);
		demoVC->_stop = (demoVC->_maxFrameCount && ++demoVC->_frameCount >= demoVC->_maxFrameCount);
	}
	return kCVReturnSuccess;
}

@end


#pragma mark -
#pragma mark DemoView

@implementation DemoView

/** Indicates that the view wants to draw using the backing layer instead of using drawRect:.  */
-(BOOL) wantsUpdateLayer { return YES; }

/** Returns a Metal-compatible layer. */
+(Class) layerClass { return [CAMetalLayer class]; }

/** If the wantsLayer property is set to YES, this method will be invoked to return a layer instance. */
-(CALayer*) makeBackingLayer {
	CALayer* layer = [self.class.layerClass layer];
	CGSize viewScale = [self convertSizeToBacking: CGSizeMake(1.0, 1.0)];
	layer.contentsScale = MIN(viewScale.width, viewScale.height);
	return layer;
}

/**
 * If this view moves to a screen that has a different resolution scale (eg. Standard <=> Retina),
 * update the contentsScale of the layer, which will trigger a Vulkan VK_SUBOPTIMAL_KHR result, which
 * causes this demo to replace the swapchain, in order to optimize rendering for the new resolution.
 */
-(BOOL) layer: (CALayer *)layer shouldInheritContentsScale: (CGFloat)newScale fromWindow: (NSWindow *)window {
	if (newScale == layer.contentsScale) { return NO; }

	layer.contentsScale = newScale;
	return YES;
}

@end
