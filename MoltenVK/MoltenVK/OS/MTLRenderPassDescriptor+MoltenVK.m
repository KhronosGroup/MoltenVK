/*
 * MTLRenderPassDescriptor+MoltenVK.m
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


#include "MTLRenderPassDescriptor+MoltenVK.h"
#include "MVKCommonEnvironment.h"

@implementation MTLRenderPassDescriptor (MoltenVK)

-(NSUInteger) renderTargetArrayLengthMVK {

#if MVK_MACOS
	return self.renderTargetArrayLength;
#endif
#if MVK_TVOS
  return 0;
#endif
#if MVK_IOS_OR_VISIONOS
	if ( [self respondsToSelector: @selector(renderTargetArrayLength)] ) {
		return self.renderTargetArrayLength;
	}
	return 0;
#endif

}

-(void) setRenderTargetArrayLengthMVK: (NSUInteger) length {

#if MVK_MACOS
	self.renderTargetArrayLength = length;
#endif
#if MVK_IOS_OR_VISIONOS
	if ( [self respondsToSelector: @selector(setRenderTargetArrayLength:)] ) {
		self.renderTargetArrayLength = length;
	}
#endif

}

-(NSUInteger) renderTargetWidthMVK {

#if MVK_TVOS
	return 0;
#else
    if ([self respondsToSelector: @selector(renderTargetWidth)])
        return self.renderTargetWidth;
    return 0;
#endif

}

-(void) setRenderTargetWidthMVK: (NSUInteger) width {

#if !MVK_TVOS
	if ([self respondsToSelector: @selector(setRenderTargetWidth:)])
		self.renderTargetWidth = width;
#endif

}

-(NSUInteger) renderTargetHeightMVK {

#if MVK_TVOS
	return 0;
#else
	if ([self respondsToSelector: @selector(renderTargetHeight)])
		return self.renderTargetHeight;
	return 0;
#endif

}

-(void) setRenderTargetHeightMVK: (NSUInteger) height {

#if !MVK_TVOS
	if ([self respondsToSelector: @selector(setRenderTargetHeight:)])
		self.renderTargetHeight = height;
#endif

}

@end
