/*
 * MTLTextureDescriptor+MoltenVK.h
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

/** Extensions to MTLTextureDescriptor to support MoltenVK. */
@interface MTLTextureDescriptor (MoltenVK)

/**
 * Replacement for the usage property.
 *
 * This property allows support under all OS versions. Delegates to the usage property if it
 * is available. otherwise, returns MTLTextureUsageUnknown when read and does nothing when set.
 */
@property(nonatomic, readwrite) MTLTextureUsage usageMVK;

/**
 * Replacement for the storageMode property.
 *
 * This property allows support under all OS versions. Delegates to the storageMode
 * property if it is available. otherwise, returns MTLStorageModeShared when read
 * and does nothing when set.
 */
@property(nonatomic, readwrite) MTLStorageMode storageModeMVK;

@end
