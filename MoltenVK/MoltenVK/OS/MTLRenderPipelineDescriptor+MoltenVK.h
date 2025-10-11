/*
 * MTLRenderPipelineDescriptor+MoltenVK.h
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


/** Extensions to MTLRenderPassDescriptor to support MoltenVK. */
@interface MTLRenderPipelineDescriptor (MoltenVK)

/**
 * Replacement for the sampleMask property.
 *
 * This property allows support under all OS versions. Delegates to the sampleMask
 * property if it is available. otherwise, returns 0xFFFFFFFF when
 * read and does nothing when set.
 */
@property(nonatomic, readwrite) NSUInteger sampleMaskMVK;

/**
 * Replacement for the logicOperationEnabled property.
 *
 * This property allows support under all OS versions. Delegates to the logicOperationEnabled
 * property if it is available. otherwise, returns NO when read and does nothing when set.
 */
@property(nonatomic, readwrite, getter=isLogicOperationEnabledMVK) BOOL logicOperationEnabledMVK;

/**
 * Replacement for the logicOperation property.
 *
 * This property allows support under all OS versions. Delegates to the logicOperation
 * property if it is available. otherwise, returns MTLLogicOperationCopy when
 * read and does nothing when set.
 *
 * The value is treated as an NSUInteger to support OS versions on which the enum is unavailable.
 */
@property(nonatomic, readwrite) NSUInteger logicOperationMVK;

@end


/** Extensions to MTLMeshRenderPassDescriptor to support MoltenVK. */
@interface MTLMeshRenderPipelineDescriptor (MoltenVK)

/**
 * Replacement for the sampleMask property.
 *
 * This property allows support under all OS versions. Delegates to the sampleMask
 * property if it is available. otherwise, returns 0xFFFFFFFF when
 * read and does nothing when set.
 */
@property(nonatomic, readwrite) NSUInteger sampleMaskMVK;

/**
 * Replacement for the logicOperationEnabled property.
 *
 * This property allows support under all OS versions. Delegates to the logicOperationEnabled
 * property if it is available. otherwise, returns NO when read and does nothing when set.
 */
@property(nonatomic, readwrite, getter=isLogicOperationEnabledMVK) BOOL logicOperationEnabledMVK;

/**
 * Replacement for the logicOperation property.
 *
 * This property allows support under all OS versions. Delegates to the logicOperation
 * property if it is available. otherwise, returns MTLLogicOperationCopy when
 * read and does nothing when set.
 *
 * The value is treated as an NSUInteger to support OS versions on which the enum is unavailable.
 */
@property(nonatomic, readwrite) NSUInteger logicOperationMVK;

@end
