/*
 * MTLRenderPipelineDescriptor+MoltenVK.h
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#pragma once

#import <Metal/Metal.h>


/** Extensions to MTLRenderPassDescriptor to support MoltenVK. */
@interface MTLRenderPipelineDescriptor (MoltenVK)

#if MVK_SUPPORT_INPUT_PRIMITIVE_TOPOLOGY_BOOL
/**
 * Replacement for the inputPrimitiveTopology property.
 *
 * This property allows support under all OS versions. Delegates to the inputPrimitiveTopology
 * property if it is available. otherwise, returns MTLPrimitiveTopologyClassUnspecified when
 * read and does nothing when set.
 */
@property(nonatomic, readwrite) MTLPrimitiveTopologyClass inputPrimitiveTopologyMVK;
#endif
@end
