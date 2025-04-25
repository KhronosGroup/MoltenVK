/*
 * MTLSamplerDescriptor+MoltenVK.h
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

#pragma once

#import <Metal/Metal.h>

/** Extensions to MTLSamplerDescriptor to support MoltenVK. */
@interface MTLSamplerDescriptor (MoltenVK)

/**
 * Replacement for the compareFunction property.
 *
 * This property allows support under all OS versions. Delegates to the compareFunction
 * property if it is available. otherwise, returns MTLTextureUsageUnknown when read and
 * does nothing when set.
 */
@property(nonatomic, readwrite) MTLCompareFunction compareFunctionMVK;

/**
 * Replacement for the borderColor property.
 *
 * This property allows support under all OS versions. Delegates to the borderColor
 * property if it is available. otherwise, returns MTLSamplerBorderColorTransparentBlack when read and
 * does nothing when set.
 */
@property(nonatomic, readwrite) /*MTLSamplerBorderColor*/ NSUInteger borderColorMVK;

/**
 * Replacement for the lodBias property.
 *
 * This property allows support under all OS versions. Delegates to the lodBias
 * property if it is available. otherwise, returns 0 when read and
 * does nothing when set.
 */
@property(nonatomic, readwrite) float lodBiasMVK;

@end
