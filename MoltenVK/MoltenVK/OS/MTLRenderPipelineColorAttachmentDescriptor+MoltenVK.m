/*
 * MTLRenderPipelineDescriptor+MoltenVK.m
 *
 * Copyright (c) 2018-2023 Chip Davis
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


#include "MVKCommonEnvironment.h"

#if MVK_USE_METAL_PRIVATE_API

#include "MTLRenderPipelineDescriptor+MoltenVK.h"

typedef NSUInteger MTLLogicOperation;

@interface MTLRenderPipelineColorAttachmentDescriptor ()

- (BOOL)isLogicOpEnabled;
- (void)setLogicOpEnabled: (BOOL)enable;
- (MTLLogicOperation)logicOp;
- (void)setLogicOp: (MTLLogicOperation)op;

@end

@implementation MTLRenderPipelineColorAttachmentDescriptor (MoltenVK)

- (BOOL)isLogicOpEnabledMVK {
	if ([self respondsToSelector:@selector(isLogicOpEnabled)]) {
		return [self isLogicOpEnabled];
	}
	return NO;
}

- (void)setLogicOpEnabledMVK: (BOOL)enable {
	if ([self respondsToSelector:@selector(setLogicOpEnabled:)]) {
		[self setLogicOpEnabled: enable];
	}
}

- (NSUInteger)logicOpMVK {
	if ([self respondsToSelector:@selector(logicOp)]) {
		return [self logicOp];
	}
	return 3 /* MTLLogicOperationCopy */;
}

- (void)setLogicOpMVK: (MTLLogicOperation)op {
	if ([self respondsToSelector:@selector(setLogicOp:)]) {
		[self setLogicOp: (MTLLogicOperation)op];
	}
}

@end

#endif	/* MVK_CONFIG_SUPPORT_METAL_SPIS */
