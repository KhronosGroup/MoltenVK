/*
 * MVKCmdDispatch.h
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCommand.h"
#include "MVKMTLResourceBindings.h"

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKCmdDispatch

/** Vulkan command to dispatch compute threadgroups. */
class MVKCmdDispatch : public MVKCommand {

public:
    void setContent(uint32_t baseGroupX, uint32_t baseGroupY, uint32_t baseGroupZ,
                    uint32_t groupCountX, uint32_t groupCountY, uint32_t groupCountZ);

    void encode(MVKCommandEncoder* cmdEncoder) override;

    MVKCmdDispatch(MVKCommandTypePool<MVKCmdDispatch>* pool);

protected:
    MTLRegion  _mtlThreadgroupCount;
};


#pragma mark -
#pragma mark MVKCmdDispatchIndirect

/** Vulkan command to dispatch compute threadgroups. */
class MVKCmdDispatchIndirect : public MVKCommand {

public:
	void setContent(VkBuffer buffer, VkDeviceSize offset);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	MVKCmdDispatchIndirect(MVKCommandTypePool<MVKCmdDispatchIndirect>* pool);

protected:
	id<MTLBuffer> _mtlIndirectBuffer;
	NSUInteger _mtlIndirectBufferOffset;
};


#pragma mark -
#pragma mark Command creation functions

/** Adds a compute threadgroup dispatch command to the specified command buffer. */
void mvkCmdDispatch(MVKCommandBuffer* cmdBuff, uint32_t x, uint32_t y, uint32_t z);

/** Adds an indirect compute threadgroup dispatch command to the specified command buffer. */
void mvkCmdDispatchIndirect(MVKCommandBuffer* cmdBuff, VkBuffer buffer, VkDeviceSize offset);

/** Adds a compute threadgroup dispatch command to the specified command buffer, with thread IDs starting from the given base. */
void mvkCmdDispatchBase(MVKCommandBuffer* cmdBuff, uint32_t baseGroupX, uint32_t baseGroupY, uint32_t baseGroupZ, uint32_t groupCountX, uint32_t groupCountY, uint32_t groupCountZ);

