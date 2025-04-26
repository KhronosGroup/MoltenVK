/*
 * CAMetalLayer+MoltenVK.m
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


#include "CAMetalLayer+MoltenVK.h"
#include "MVKOSExtensions.h"

#if MVK_MACOS && !MVK_MACCAT
#	include <AppKit/NSApplication.h>
#	include <AppKit/NSWindow.h>
#	include <AppKit/NSView.h>
#endif


@implementation CAMetalLayer (MoltenVK)

-(CGSize) naturalDrawableSizeMVK {
    CGSize drawSize = self.bounds.size;
    CGFloat scaleFactor = self.contentsScale;
    drawSize.width *= scaleFactor;
    drawSize.height *= scaleFactor;
    return drawSize;
}

-(BOOL) displaySyncEnabledMVK {
#if MVK_MACOS
    if ( [self respondsToSelector: @selector(displaySyncEnabled)] ) { return self.displaySyncEnabled; }
#endif
    return YES;
}

-(void) setDisplaySyncEnabledMVK: (BOOL) enabled {
#if MVK_MACOS
    if ( [self respondsToSelector: @selector(setDisplaySyncEnabled:)] ) { self.displaySyncEnabled = enabled; }
#endif
}

-(NSUInteger) maximumDrawableCountMVK {
	if ( [self respondsToSelector: @selector(maximumDrawableCount)] ) { return self.maximumDrawableCount; }
	return 0;
}

-(void) setMaximumDrawableCountMVK: (NSUInteger) count {
	if ( [self respondsToSelector: @selector(setMaximumDrawableCount:)] ) { self.maximumDrawableCount = count; }
}

-(BOOL) wantsExtendedDynamicRangeContentMVK {
#if MVK_MACOS
    return self.wantsExtendedDynamicRangeContent;
#else
    return NO;
#endif
}

-(void) setWantsExtendedDynamicRangeContentMVK: (BOOL) edr {
#if MVK_MACOS
    self.wantsExtendedDynamicRangeContent = edr;
#endif
}

-(CFStringRef) colorspaceNameMVK { return CGColorSpaceGetName(self.colorspace); }

-(void) setColorspaceNameMVK: (CFStringRef) name {
	CGColorSpaceRef csRef = CGColorSpaceCreateWithName(name);
	self.colorspace = csRef;
	CGColorSpaceRelease(csRef);
}

#if (MVK_IOS_OR_TVOS || MVK_MACCAT) && !MVK_VISIONOS
-(UIScreen*) screenMVK {
	return UIScreen.mainScreen;
}
#endif

#if MVK_MACOS && !MVK_MACCAT
-(NSScreen*) screenMVK {
	__block NSScreen* screen;
	mvkDispatchToMainAndWait(^{ screen = self.privateScreenMVKImpl; });
	return screen;
}

// Search for the screen currently displaying the layer, and default to the main screen if it can't be found.
-(NSScreen*) privateScreenMVKImpl {
	// If this layer has a delegate that is an NSView, and the view is in a window, retrieve the screen from the window.
	if ([self.delegate isKindOfClass: NSView.class]) {
		NSWindow* window = ((NSView*)self.delegate).window;
		if (window) { return window.screen; }
	} else {
		// Otherwise we need to iterate through all the windows used by this app, and
		// check if the content view is using this layer or one of its ancestor layers.
		// If a match is found, retrieve the screen from the window. It is not sufficient
		// to first search for the top structural layer, because Core Animation may add
		// a superlayer to the CAMetalLayer, independent of the content view.
		for (NSWindow* window in NSApplication.sharedApplication.windows) {
			CALayer* windowContentLayer = window.contentView.layer;
			for (CALayer* layer = self; layer; layer = layer.superlayer) {
				if (layer == windowContentLayer) { return window.screen; }
			}
		}
	}
	return NSScreen.mainScreen;		// Default to main screen if not found
}
#endif

@end
