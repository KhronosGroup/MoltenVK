/*
 * MVKCmdQueries.mm
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

#include "MVKCmdQueries.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKQueryPool.h"


#pragma mark -
#pragma mark MVKCmdQuery

VkResult MVKCmdQuery::setContent(MVKCommandBuffer* cmdBuff,
								 VkQueryPool queryPool,
								 uint32_t query) {
    _queryPool = (MVKQueryPool*)queryPool;
    _query = query;

	return VK_SUCCESS;
}

MVKCmdQuery::MVKCmdQuery(MVKCommandTypePool<MVKCommand>* pool) : MVKCommand::MVKCommand(pool) {}


#pragma mark -
#pragma mark MVKCmdBeginQuery

MVKFuncionOverride_getTypePool(BeginQuery)

VkResult MVKCmdBeginQuery::setContent(MVKCommandBuffer* cmdBuff,
									  VkQueryPool queryPool,
									  uint32_t query,
									  VkQueryControlFlags flags) {

    VkResult rslt = MVKCmdQuery::setContent(cmdBuff, queryPool, query);

	_flags = flags;
	_queryPool->beginQueryAddedTo(_query, cmdBuff);

	return rslt;
}

void MVKCmdBeginQuery::encode(MVKCommandEncoder* cmdEncoder) {
    _queryPool->beginQuery(_query, _flags, cmdEncoder);
}

MVKCmdBeginQuery::MVKCmdBeginQuery(MVKCommandTypePool<MVKCmdBeginQuery>* pool)
    : MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdEndQuery

MVKFuncionOverride_getTypePool(EndQuery)

void MVKCmdEndQuery::encode(MVKCommandEncoder* cmdEncoder) {
    _queryPool->endQuery(_query, cmdEncoder);
}

MVKCmdEndQuery::MVKCmdEndQuery(MVKCommandTypePool<MVKCmdEndQuery>* pool)
    : MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdWriteTimestamp

MVKFuncionOverride_getTypePool(WriteTimestamp)

VkResult MVKCmdWriteTimestamp::setContent(MVKCommandBuffer* cmdBuff,
										  VkPipelineStageFlagBits pipelineStage,
										  VkQueryPool queryPool,
										  uint32_t query) {

	VkResult rslt = MVKCmdQuery::setContent(cmdBuff, queryPool, query);

	_pipelineStage = pipelineStage;

	return rslt;
}

void MVKCmdWriteTimestamp::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->markTimestamp(_queryPool, _query);
}

MVKCmdWriteTimestamp::MVKCmdWriteTimestamp(MVKCommandTypePool<MVKCmdWriteTimestamp>* pool)
		: MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdResetQueryPool

MVKFuncionOverride_getTypePool(ResetQueryPool)

VkResult MVKCmdResetQueryPool::setContent(MVKCommandBuffer* cmdBuff,
										  VkQueryPool queryPool,
										  uint32_t firstQuery,
										  uint32_t queryCount) {

	VkResult rslt = MVKCmdQuery::setContent(cmdBuff, queryPool, firstQuery);

	_queryCount = queryCount;

	return rslt;
}

void MVKCmdResetQueryPool::encode(MVKCommandEncoder* cmdEncoder) {
    _queryPool->resetResults(_query, _queryCount, cmdEncoder);
}

MVKCmdResetQueryPool::MVKCmdResetQueryPool(MVKCommandTypePool<MVKCmdResetQueryPool>* pool)
    : MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdCopyQueryPoolResults

MVKFuncionOverride_getTypePool(CopyQueryPoolResults)

VkResult MVKCmdCopyQueryPoolResults::setContent(MVKCommandBuffer* cmdBuff,
												VkQueryPool queryPool,
												uint32_t firstQuery,
												uint32_t queryCount,
												VkBuffer destBuffer,
												VkDeviceSize destOffset,
												VkDeviceSize destStride,
												VkQueryResultFlags flags) {

	VkResult rslt = MVKCmdQuery::setContent(cmdBuff, queryPool, firstQuery);

	_queryCount = queryCount;
    _destBuffer = (MVKBuffer*) destBuffer;
    _destOffset = destOffset;
    _destStride = destStride;
    _flags = flags;

	return rslt;
}

void MVKCmdCopyQueryPoolResults::encode(MVKCommandEncoder* cmdEncoder) {
    // What happens now depends on whether or not I was added before or after the query ended.
    if (!_queryPool->areQueriesDeviceAvailable(_query, _queryCount) && mvkIsAnyFlagEnabled(_flags, VK_QUERY_RESULT_WAIT_BIT)) {
        // Defer this until the queries will be done.
        _queryPool->deferCopyResults(_query, _queryCount, _destBuffer, _destOffset, _destStride, _flags);
    } else {
        _queryPool->encodeCopyResults(cmdEncoder, _query, _queryCount, _destBuffer, _destOffset, _destStride, _flags);
    }
}

MVKCmdCopyQueryPoolResults::MVKCmdCopyQueryPoolResults(MVKCommandTypePool<MVKCmdCopyQueryPoolResults>* pool)
    : MVKCmdQuery::MVKCmdQuery((MVKCommandTypePool<MVKCommand>*)pool) {}

