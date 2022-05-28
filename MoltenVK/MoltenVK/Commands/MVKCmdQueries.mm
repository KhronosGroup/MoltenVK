/*
 * MVKCmdQueries.mm
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#pragma mark -
#pragma mark MVKCmdBeginQuery

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
    // In a multiview render pass, multiple queries are produced, one for each view.
    // Therefore, when encoding, we must offset the query by the number of views already
    // drawn in all previous Metal passes.
    uint32_t query = _query;
    if (cmdEncoder->getMultiviewPassIndex() > 0)
        query += cmdEncoder->getSubpass()->getViewCountUpToMetalPass(cmdEncoder->getMultiviewPassIndex() - 1);
    _queryPool->beginQuery(query, _flags, cmdEncoder);
}


#pragma mark -
#pragma mark MVKCmdEndQuery

void MVKCmdEndQuery::encode(MVKCommandEncoder* cmdEncoder) {
    uint32_t query = _query;
    if (cmdEncoder->getMultiviewPassIndex() > 0)
        query += cmdEncoder->getSubpass()->getViewCountUpToMetalPass(cmdEncoder->getMultiviewPassIndex() - 1);
    _queryPool->endQuery(query, cmdEncoder);
}


#pragma mark -
#pragma mark MVKCmdWriteTimestamp

VkResult MVKCmdWriteTimestamp::setContent(MVKCommandBuffer* cmdBuff,
										  VkPipelineStageFlagBits pipelineStage,
										  VkQueryPool queryPool,
										  uint32_t query) {

	VkResult rslt = MVKCmdQuery::setContent(cmdBuff, queryPool, query);

	_pipelineStage = pipelineStage;

	cmdBuff->recordTimestampCommand();

	return rslt;
}

void MVKCmdWriteTimestamp::encode(MVKCommandEncoder* cmdEncoder) {
    uint32_t query = _query;
    if (cmdEncoder->getMultiviewPassIndex() > 0)
        query += cmdEncoder->getSubpass()->getViewCountUpToMetalPass(cmdEncoder->getMultiviewPassIndex() - 1);
    _queryPool->endQuery(query, cmdEncoder);
}


#pragma mark -
#pragma mark MVKCmdResetQueryPool

VkResult MVKCmdResetQueryPool::setContent(MVKCommandBuffer* cmdBuff,
										  VkQueryPool queryPool,
										  uint32_t firstQuery,
										  uint32_t queryCount) {

	VkResult rslt = MVKCmdQuery::setContent(cmdBuff, queryPool, firstQuery);

	_queryCount = queryCount;

	return rslt;
}

void MVKCmdResetQueryPool::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->resetQueries(_queryPool, _query, _queryCount);
    _queryPool->resetResults(_query, _queryCount, cmdEncoder);
}


#pragma mark -
#pragma mark MVKCmdCopyQueryPoolResults

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

