/*
 * mvk_datatypes.hpp
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#ifndef __mvkDataTypes_hpp_
#define __mvkDataTypes_hpp_ 1


#include "mvk_datatypes.h"

#include <functional>

class MVKBaseObject;
class MVKPixelFormats;

/*
 * This header file should be used internally within MoltenVK in place of mvk_datatypes.h,
 * which is part of the public external MoltenVK C API.
 */

#pragma mark -
#pragma mark Support for VK_EXT_debug_report extension

/*
 * The following function declarations are variations of functions declared in mvk_datatypes.h.
 *
 * Each function variation declared here accepts an MVKBaseObject instance, which, if not nil,
 * allows calls to MVKBaseObject::reportError() to be made from within these functions to perform
 * debug report callbacks in support of the VK_EXT_debug_report extension.
 *
 * The original functions in mvk_datatypes.h are redefined here to redirect to the equivalent
 * functions declared here, passing the calling instance, which is assumed to be an instance
 * of an MVKBaseObject subclass, which is true for all but static calling functions.
 */

MTLPrimitiveType mvkMTLPrimitiveTypeFromVkPrimitiveTopologyInObj(VkPrimitiveTopology vkTopology, MVKBaseObject* mvkObj);
#define mvkMTLPrimitiveTypeFromVkPrimitiveTopology(vkTopology) mvkMTLPrimitiveTypeFromVkPrimitiveTopologyInObj(vkTopology, this)

MTLPrimitiveTopologyClass mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopologyInObj(VkPrimitiveTopology vkTopology, MVKBaseObject* mvkObj);
#define mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology(vkTopology) mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopologyInObj(vkTopology, this)

MTLTriangleFillMode mvkMTLTriangleFillModeFromVkPolygonModeInObj(VkPolygonMode vkFillMode, MVKBaseObject* mvkObj);
#define mvkMTLTriangleFillModeFromVkPolygonMode(vkFillMode) mvkMTLTriangleFillModeFromVkPolygonModeInObj(vkFillMode, this)

MTLLoadAction mvkMTLLoadActionFromVkAttachmentLoadOpInObj(VkAttachmentLoadOp vkLoadOp, MVKBaseObject* mvkObj);
#define mvkMTLLoadActionFromVkAttachmentLoadOp(vkLoadOp) mvkMTLLoadActionFromVkAttachmentLoadOpInObj(vkLoadOp, this)

MTLStoreAction mvkMTLStoreActionFromVkAttachmentStoreOpInObj(VkAttachmentStoreOp vkStoreOp, bool hasResolveAttachment, MVKBaseObject* mvkObj);
#define mvkMTLStoreActionFromVkAttachmentStoreOp(vkStoreOp, hasResolveAttachment) mvkMTLStoreActionFromVkAttachmentStoreOpInObj(vkStoreOp, hasResolveAttachment, this)

MTLMultisampleDepthResolveFilter mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBitsInObj(VkResolveModeFlagBits vkResolveMode, MVKBaseObject* mvkObj);
#define mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBits(vkResolveMode) mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBitsInObj(vkResolveMode, this)

#if MVK_MACOS_OR_IOS
MTLMultisampleStencilResolveFilter mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBitsInObj(VkResolveModeFlagBits vkResolveMode, MVKBaseObject* mvkObj);
#define mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBits(vkResolveMode) mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBitsInObj(vkResolveMode, this)
#endif

MVKShaderStage mvkShaderStageFromVkShaderStageFlagBitsInObj(VkShaderStageFlagBits vkStage, MVKBaseObject* mvkObj);
#define mvkShaderStageFromVkShaderStageFlagBits(vkStage) mvkShaderStageFromVkShaderStageFlagBitsInObj(vkStage, this)

MTLWinding mvkMTLWindingFromSpvExecutionModeInObj(uint32_t spvMode, MVKBaseObject* mvkObj);
#define mvkMTLWindingFromSpvExecutionMode(spvMode) mvkMTLWindingFromSpvExecutionModeInObj(spvMode, this)

MTLTessellationPartitionMode mvkMTLTessellationPartitionModeFromSpvExecutionModeInObj(uint32_t spvMode, MVKBaseObject* mvkObj);
#define mvkMTLTessellationPartitionModeFromSpvExecutionMode(spvMode) mvkMTLTessellationPartitionModeFromSpvExecutionModeInObj(spvMode, this)

#endif
