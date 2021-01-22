/*
 * MVKCmdQueries.h
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

#pragma once

#include "MVKCommand.h"
#include "MVKBuffer.h"

class MVKQueryPool;


#pragma mark -
#pragma mark MVKCmdQuery

/** Abstract Vulkan command to manage queries. */
class MVKCmdQuery : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkQueryPool queryPool,
						uint32_t query);

protected:
    MVKQueryPool* _queryPool;
    uint32_t _query;
};


#pragma mark -
#pragma mark MVKCmdBeginQuery

/** Vulkan command to begin a query. */
class MVKCmdBeginQuery : public MVKCmdQuery {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkQueryPool queryPool,
						uint32_t query,
						VkQueryControlFlags flags);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    VkQueryControlFlags _flags;
};


#pragma mark -
#pragma mark MVKCmdEndQuery

/** Vulkan command to end a query. */
class MVKCmdEndQuery : public MVKCmdQuery {

public:
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

};


#pragma mark -
#pragma mark MVKCmdWriteTimestamp

/** Vulkan command to write a timestamp. */
class MVKCmdWriteTimestamp : public MVKCmdQuery {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkPipelineStageFlagBits pipelineStage,
						VkQueryPool queryPool,
						uint32_t query);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    VkPipelineStageFlagBits _pipelineStage;
};


#pragma mark -
#pragma mark MVKCmdResetQueryPool

/** Vulkan command to reset the results in a query pool. */
class MVKCmdResetQueryPool : public MVKCmdQuery {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkQueryPool queryPool,
						uint32_t firstQuery,
						uint32_t queryCount);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    uint32_t _queryCount;
};


#pragma mark -
#pragma mark MVKCmdCopyQueryPoolResults

/** Vulkan command to reset the results in a query pool. */
class MVKCmdCopyQueryPoolResults : public MVKCmdQuery {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkQueryPool queryPool,
						uint32_t firstQuery,
						uint32_t queryCount,
						VkBuffer destBuffer,
						VkDeviceSize destOffset,
						VkDeviceSize destStride,
						VkQueryResultFlags flags);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    MVKBuffer* _destBuffer;
    VkDeviceSize _destOffset;
    VkDeviceSize _destStride;
    VkQueryResultFlags _flags;
	uint32_t _queryCount;
};
