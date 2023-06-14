/*
 * MVKCmdQueries.h
 *
 * Copyright (c) 2015-2023 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#pragma mark MVKCmdBeginQueryIndexed

/* Vulkan Command The cmdBeginQueryIndexedEXT command operates the same as the cmdBeginQuery command,
 * except that it also accepts a query type specific index parameter.
 */
class MVKCmdBeginQueryIndexed : public MVKCmdQuery {
public:
    MVKCmdBeginQueryIndexed() :
            _mtlIndexedQueryPool(), _mtlQueryIndexedFlags(), _mtlQueryIndexedIndex() {}
    VkResult setContent(MVKCommandBuffer *cmdBuff,
                        VkQueryPool queryPool,
                        uint32_t query,
                        uint32_t flags,
                        uint32_t index);

    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    uint32_t _query;
    MVKQueryPool* _mtlIndexedQueryPool;
    uint32_t _mtlQueryIndexedFlags;
    uint32_t _mtlQueryIndexedIndex;
};

#pragma mark -
#pragma mark EndQueryIndexed

/*
 * Ends a query, also accepts a query type specific index parameter.
 */

class MVKCmdEndQueryIndexed : public MVKCmdQuery {
public:
    MVKCmdEndQueryIndexed() : index() {}
    VkResult setContent(MVKCommandBuffer* cmdBuffer,
                        VkQueryPool queryPool,
                        uint32_t query,
                        uint32_t index);
    void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
    MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

    uint32_t index;
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
