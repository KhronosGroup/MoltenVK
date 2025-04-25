/*
 * MTLRenderPipelineDescriptor+MoltenVK.m
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


#include "MTLRenderPipelineDescriptor+MoltenVK.h"
#include "MVKCommonEnvironment.h"

#if MVK_USE_METAL_PRIVATE_API
// These properties aren't public yet.
@interface MTLRenderPipelineDescriptor ()

@property(nonatomic, readwrite) NSUInteger sampleMask;
@property(nonatomic, readwrite) float sampleCoverage;

@end
#endif

@implementation MTLRenderPipelineDescriptor (MoltenVK)

-(MTLPrimitiveTopologyClass) inputPrimitiveTopologyMVK {
	if ( [self respondsToSelector: @selector(inputPrimitiveTopology)] ) { return [self inputPrimitiveTopology]; }
	return MTLPrimitiveTopologyClassUnspecified;
}

-(void) setInputPrimitiveTopologyMVK: (MTLPrimitiveTopologyClass) topology {
	if ([self respondsToSelector: @selector(setInputPrimitiveTopology:)]) { [self setInputPrimitiveTopology:topology]; }
}

-(NSUInteger) sampleMaskMVK {
#if MVK_USE_METAL_PRIVATE_API
	if ( [self respondsToSelector: @selector(sampleMask)] ) { return self.sampleMask; }
#endif
	return 0xFFFFFFFFFFFFFFFFULL;
}

-(void) setSampleMaskMVK: (NSUInteger) mask {
#if MVK_USE_METAL_PRIVATE_API
	if ([self respondsToSelector: @selector(setSampleMask:)]) { self.sampleMask = mask; }
#endif
}

@end
