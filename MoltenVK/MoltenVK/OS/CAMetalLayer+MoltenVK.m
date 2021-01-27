/*
 * CAMetalLayer+MoltenVK.m
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


#include "CAMetalLayer+MoltenVK.h"
#include "MVKCommonEnvironment.h"

@implementation CAMetalLayer (MoltenVK)

-(CGSize) naturalDrawableSizeMVK {
    CGSize drawSize = self.bounds.size;
    CGFloat scaleFactor = self.contentsScale;
    drawSize.width = trunc(drawSize.width * scaleFactor);
    drawSize.height = trunc(drawSize.height * scaleFactor);
    return drawSize;
}

// Only update drawableSize property value if it needs to be,
// in case updating to same value causes internal reconfigurations.
-(CGSize) updatedDrawableSizeMVK {
	CGSize drawSize = self.naturalDrawableSizeMVK;
    if ( !CGSizeEqualToSize(drawSize, self.drawableSize) ) {
        self.drawableSize = drawSize;
    }
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

@end
