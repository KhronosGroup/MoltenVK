/*
 * MVKMTLResourceBindings.h
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

/** Describes a MTLTexture resource binding. */
typedef struct {
    union { id<MTLTexture> mtlTexture = nil; id<MTLTexture> mtlResource; }; // aliases
    uint32_t index = 0;
    uint32_t swizzle = 0;
    bool isDirty = true;
} MVKMTLTextureBinding;

/** Describes a MTLSamplerState resource binding. */
typedef struct {
    union { id<MTLSamplerState> mtlSamplerState = nil; id<MTLSamplerState> mtlResource; }; // aliases
    uint32_t index = 0;
    bool isDirty = true;
} MVKMTLSamplerStateBinding;

/** Describes a MTLBuffer resource binding. */
typedef struct {
    union { id<MTLBuffer> mtlBuffer = nil; id<MTLBuffer> mtlResource; }; // aliases
    NSUInteger offset = 0;
    uint32_t index = 0;
    bool isDirty = true;
} MVKMTLBufferBinding;

/** Describes a MTLBuffer resource binding as used for an index buffer. */
typedef struct {
    union { id<MTLBuffer> mtlBuffer = nil; id<MTLBuffer> mtlResource; }; // aliases
    NSUInteger offset = 0;
    MTLIndexType mtlIndexType;
    bool isDirty = true;
} MVKIndexMTLBufferBinding;
