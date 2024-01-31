/*
 * MTLSamplerDescriptor+MoltenVK.m
 *
 * Copyright (c) 2015-2024 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#include "MTLSamplerDescriptor+MoltenVK.h"
#include "MVKCommonEnvironment.h"


#if MVK_USE_METAL_PRIVATE_API
/** Additional methods not necessarily declared in <Metal/MTLSampler.h>. */
@interface MTLSamplerDescriptor ()

@property(nonatomic, readwrite) float lodBias;

@end
#endif

@implementation MTLSamplerDescriptor (MoltenVK)

-(MTLCompareFunction) compareFunctionMVK {
	if ( [self respondsToSelector: @selector(compareFunction)] ) { return self.compareFunction; }
	return MTLCompareFunctionNever;
}

-(void) setCompareFunctionMVK: (MTLCompareFunction) cmpFunc {
	if ( [self respondsToSelector: @selector(setCompareFunction:)] ) { self.compareFunction = cmpFunc; }
}

-(NSUInteger) borderColorMVK {
#if MVK_MACOS_OR_IOS
	if ( [self respondsToSelector: @selector(borderColor)] ) { return self.borderColor; }
#endif
	return /*MTLSamplerBorderColorTransparentBlack*/ 0;
}

-(void) setBorderColorMVK: (NSUInteger) color {
#if MVK_MACOS_OR_IOS
	if ( [self respondsToSelector: @selector(setBorderColor:)] ) { self.borderColor = (MTLSamplerBorderColor) color; }
#endif
}

#if MVK_USE_METAL_PRIVATE_API
-(float) lodBiasMVK {
	if ( [self respondsToSelector: @selector(lodBias)] ) { return self.lodBias; }
	return 0.0f;
}

-(void) setLodBiasMVK: (float) bias {
	if ( [self respondsToSelector: @selector(setLodBias:)] ) { self.lodBias = bias; }
}
#endif

@end
