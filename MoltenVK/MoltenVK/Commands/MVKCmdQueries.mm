/*
 * MVKCmdQueries.mm
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCmdQueries.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKQueryPool.h"


#pragma mark -
#pragma mark MVKCmdQuery

void MVKCmdQuery::setContent(VkQueryPool queryPool, uint32_t query) {
    _queryPool = (MVKQueryPool*)queryPool;
    _query = query;
}

MVKCmdQuery::MVKCmdQuery(MVKCommandTypePool<MVKCommand>* pool) : MVKCommand::MVKCommand(pool) {}


#pragma mark -
#pragma mark MVKCmdBeginQuery

void MVKCmdBeginQuery::added(MVKCommandBuffer* cmdBuffer) {
    _queryPool->beginQueryAddedTo(_query, cmdBuffer);
};

void MVKCmdBeginQuery::setContent(VkQueryPool queryPool, uint32_t query, VkQueryControlFlags flags) {
    MVKCmdQuery::setContent(queryPool, query);
    _flags = flags;
}

void MVKCmdBeginQuery::encode(MVKCommandEncoder* cmdEncoder) {
    _queryPool->beginQuery(_query, _flags, cmdEncoder);
}

MVKCmdBeginQuery::MVKCmdBeginQuery(MVKCommandTypePool<MVKCmdBeginQuery>* pool)
    : MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdEndQuery

void MVKCmdEndQuery::encode(MVKCommandEncoder* cmdEncoder) {
    _queryPool->endQuery(_query, cmdEncoder);
}

MVKCmdEndQuery::MVKCmdEndQuery(MVKCommandTypePool<MVKCmdEndQuery>* pool)
    : MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdWriteTimestamp

void MVKCmdWriteTimestamp::setContent(VkPipelineStageFlagBits pipelineStage,
									  VkQueryPool queryPool,
									  uint32_t query) {
    MVKCmdQuery::setContent(queryPool, query);
	_pipelineStage = pipelineStage;
}

void MVKCmdWriteTimestamp::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->markTimestamp(_queryPool, _query);
}

MVKCmdWriteTimestamp::MVKCmdWriteTimestamp(MVKCommandTypePool<MVKCmdWriteTimestamp>* pool)
		: MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdResetQueryPool

void MVKCmdResetQueryPool::setContent(VkQueryPool queryPool, uint32_t firstQuery, uint32_t queryCount) {
    MVKCmdQuery::setContent(queryPool, firstQuery);
    _queryCount = queryCount;
}

void MVKCmdResetQueryPool::encode(MVKCommandEncoder* cmdEncoder) {
    _queryPool->resetResults(_query, _queryCount, cmdEncoder);
}

MVKCmdResetQueryPool::MVKCmdResetQueryPool(MVKCommandTypePool<MVKCmdResetQueryPool>* pool)
    : MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdCopyQueryPoolResults

void MVKCmdCopyQueryPoolResults::setContent(VkQueryPool queryPool,
                                            uint32_t firstQuery,
                                            uint32_t queryCount,
                                            VkBuffer destBuffer,
                                            VkDeviceSize destOffset,
                                            VkDeviceSize destStride,
                                            VkQueryResultFlags flags) {
    MVKCmdQuery::setContent(queryPool, firstQuery);
    _queryCount = queryCount;
    _destBuffer = (MVKBuffer*) destBuffer;
    _destOffset = destOffset;
    _destStride = destStride;
    _flags = flags;
}

void MVKCmdCopyQueryPoolResults::encode(MVKCommandEncoder* cmdEncoder) {
    [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mtlCmdBuff) {
        // This can block, so it must not run on the Metal completion queue.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            _queryPool->copyQueryPoolResults(_query, _queryCount, _destBuffer, _destOffset, _destStride, _flags);
        });
    }];
}

MVKCmdCopyQueryPoolResults::MVKCmdCopyQueryPoolResults(MVKCommandTypePool<MVKCmdCopyQueryPoolResults>* pool)
    : MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark Command creation functions

void mvkCmdBeginQuery(MVKCommandBuffer* cmdBuff,
                      VkQueryPool queryPool,
                      uint32_t query,
                      VkQueryControlFlags flags) {
    MVKCmdBeginQuery* cmd = cmdBuff->_commandPool->_cmdBeginQueryPool.acquireObject();
    cmd->setContent(queryPool, query, flags);
    cmdBuff->addCommand(cmd);
}

void mvkCmdEndQuery(MVKCommandBuffer* cmdBuff,
                    VkQueryPool queryPool,
                    uint32_t query) {
    MVKCmdEndQuery* cmd = cmdBuff->_commandPool->_cmdEndQueryPool.acquireObject();
    cmd->setContent(queryPool, query);
    cmdBuff->addCommand(cmd);
}

void mvkCmdWriteTimestamp(MVKCommandBuffer* cmdBuff,
						  VkPipelineStageFlagBits pipelineStage,
						  VkQueryPool queryPool,
						  uint32_t query) {
	MVKCmdWriteTimestamp* cmd = cmdBuff->_commandPool->_cmdWriteTimestampPool.acquireObject();
	cmd->setContent(pipelineStage, queryPool, query);
	cmdBuff->addCommand(cmd);
}

void mvkCmdResetQueryPool(MVKCommandBuffer* cmdBuff,
                          VkQueryPool queryPool,
                          uint32_t firstQuery,
                          uint32_t queryCount) {
    MVKCmdResetQueryPool* cmd = cmdBuff->_commandPool->_cmdResetQueryPoolPool.acquireObject();
    cmd->setContent(queryPool, firstQuery, queryCount);
    cmdBuff->addCommand(cmd);
}

void mvkCmdCopyQueryPoolResults(MVKCommandBuffer* cmdBuff,
                                VkQueryPool queryPool,
                                uint32_t firstQuery,
                                uint32_t queryCount,
                                VkBuffer destBuffer,
                                VkDeviceSize destOffset,
                                VkDeviceSize destStride,
                                VkQueryResultFlags flags) {
    MVKCmdCopyQueryPoolResults* cmd = cmdBuff->_commandPool->_cmdCopyQueryPoolResultsPool.acquireObject();
    cmd->setContent(queryPool, firstQuery, queryCount, destBuffer, destOffset, destStride, flags);
    cmdBuff->addCommand(cmd);
}

