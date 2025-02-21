/*
 * MTLRenderPassStencilAttachmentDescriptor+MoltenVK.h
 *
 * Copyright (c) 2020-2024 Chip Davis for CodeWeavers
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

/** Extensions to MTLRenderPassStencilAttachmentDescriptor to support MoltenVK. */
@interface MTLRenderPassStencilAttachmentDescriptor (MoltenVK)

/**
 * Replacement for the stencilResolveFilter property.
 *
 * This property allows support under all OS versions. Delegates to the stencilResolveFilter
 * property if it is available. Otherwise, returns MTLMultisampleStencilResolveFilterSample0 when read and does nothing when set.
 */
@property(nonatomic, readwrite) MTLMultisampleStencilResolveFilter stencilResolveFilterMVK;

@end
