/*
 * MVKCmdDispatch.h
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

#include "MVKCommand.h"

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKCmdDispatch

class MVKCmdDispatch : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t baseGroupX, uint32_t baseGroupY, uint32_t baseGroupZ,
						uint32_t groupCountX, uint32_t groupCountY, uint32_t groupCountZ);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	uint32_t _baseGroupX;
	uint32_t _baseGroupY;
	uint32_t _baseGroupZ;
	uint32_t _groupCountX;
	uint32_t _groupCountY;
	uint32_t _groupCountZ;
};


#pragma mark -
#pragma mark MVKCmdDispatchIndirect

class MVKCmdDispatchIndirect : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff, VkBuffer buffer, VkDeviceSize offset);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	id<MTLBuffer> _mtlIndirectBuffer;
	VkDeviceSize _mtlIndirectBufferOffset;
};

