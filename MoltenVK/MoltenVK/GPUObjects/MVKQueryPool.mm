/*
 * MVKQueryPool.mm
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

#include "MVKQueryPool.h"
#include "MVKBuffer.h"
#include "MVKCommandBuffer.h"
#include "MVKOSExtensions.h"
#include "MVKFoundation.h"
#include "MVKLogging.h"

using namespace std;


#pragma mark MVKQueryPool

// Mark queries as available
void MVKQueryPool::finishQueries(vector<uint32_t>& queries) {
    lock_guard<mutex> lock(_availabilityLock);
    for (uint32_t qry : queries) { _availability[qry] = true; }
    _availabilityBlocker.notify_all();      // Predicate of each wait() call will check whether all required queries are available
}

void MVKQueryPool::resetResults(uint32_t firstQuery, uint32_t queryCount, MVKCommandEncoder* cmdEncoder) {
    lock_guard<mutex> lock(_availabilityLock);
    uint32_t endQuery = firstQuery + queryCount;
    for (uint32_t query = firstQuery; query < endQuery; query++) {
        _availability[query] = false;
    }
}

VkResult MVKQueryPool::getResults(uint32_t firstQuery,
								  uint32_t queryCount,
								  size_t dataSize,
								  void* pData,
								  VkDeviceSize stride,
								  VkQueryResultFlags flags) {
	unique_lock<mutex> lock(_availabilityLock);

	uint32_t endQuery = firstQuery + queryCount;

	if (mvkAreFlagsEnabled(flags, VK_QUERY_RESULT_WAIT_BIT)) {
		_availabilityBlocker.wait(lock, [this, firstQuery, endQuery]{
			return areQueriesAvailable(firstQuery, endQuery);
		});
	}

	VkResult rqstRslt = VK_SUCCESS;
	uintptr_t pQryData = (uintptr_t)pData;
	for (uint32_t query = firstQuery; query < endQuery; query++, pQryData += stride) {
		VkResult qryRslt = getResult(query, (void*)pQryData, flags);
		if (rqstRslt == VK_SUCCESS) { rqstRslt = qryRslt; }
	}
	return rqstRslt;
}

// Returns whether all the queries between the start (inclusive) and end (exclusive) queries are available.
bool MVKQueryPool::areQueriesAvailable(uint32_t firstQuery, uint32_t endQuery) {
    for (uint32_t query = firstQuery; query < endQuery; query++) {
        if ( !_availability[query] ) { return false; }
    }
    return true;
}

VkResult MVKQueryPool::getResult(uint32_t query, void* pQryData, VkQueryResultFlags flags) {

	bool isAvailable = _availability[query];
	bool shouldOutput = (isAvailable || mvkAreFlagsEnabled(flags, VK_QUERY_RESULT_PARTIAL_BIT));
	bool shouldOutput64Bit = mvkAreFlagsEnabled(flags, VK_QUERY_RESULT_64_BIT);

	// Output the results of this query
	if (shouldOutput) { getResult(query, pQryData, shouldOutput64Bit); }

	// If requested, output the availability bit
	if (mvkAreFlagsEnabled(flags, VK_QUERY_RESULT_WITH_AVAILABILITY_BIT)) {
		if (shouldOutput64Bit) {
			uintptr_t pAvailability = (uintptr_t)pQryData + (_queryElementCount * sizeof(uint64_t));
			*(uint64_t*)pAvailability = isAvailable;
		} else {
			uintptr_t pAvailability = (uintptr_t)pQryData + (_queryElementCount * sizeof(uint32_t));
			*(uint32_t*)pAvailability = isAvailable;
		}
	}

	return shouldOutput ? VK_SUCCESS : VK_NOT_READY;
}

void MVKQueryPool::copyQueryPoolResults(uint32_t firstQuery,
                                        uint32_t queryCount,
                                        MVKBuffer* destBuffer,
                                        VkDeviceSize destOffset,
                                        VkDeviceSize destStride,
                                        VkQueryResultFlags flags) {
    if (destBuffer->isMemoryHostAccessible()) {
        void* pData = (void*)((uintptr_t)destBuffer->getMTLBuffer().contents + destBuffer->getMTLBufferOffset() + destOffset);
        size_t dataSize = destStride * queryCount;
        getResults(firstQuery, queryCount, dataSize, pData, destStride, flags);
    } else {
        mvkNotifyErrorWithText(VK_ERROR_MEMORY_MAP_FAILED, "Private GPU-only memory cannot be used for query pool results.");
    }
}


#pragma mark -
#pragma mark MVKTimestampQueryPool

// Update timestamp values, then mark queries as available
void MVKTimestampQueryPool::finishQueries(vector<uint32_t>& queries) {
    uint64_t ts = mvkGetTimestamp();
    for (uint32_t qry : queries) { _timestamps[qry] = ts; }

    MVKQueryPool::finishQueries(queries);
}

void MVKTimestampQueryPool::getResult(uint32_t query, void* pQryData, bool shouldOutput64Bit) {
	if (shouldOutput64Bit) {
		*(uint64_t*)pQryData = _timestamps[query];
	} else {
		*(uint32_t*)pQryData = (uint32_t)_timestamps[query];
	}
}


#pragma mark Construction

MVKTimestampQueryPool::MVKTimestampQueryPool(MVKDevice* device,
											 const VkQueryPoolCreateInfo* pCreateInfo) : MVKQueryPool(device, pCreateInfo, 1), _timestamps(pCreateInfo->queryCount) {
}


#pragma mark -
#pragma mark MVKOcclusionQueryPool

// If a dedicated visibility buffer has been established, use it, otherwise fetch the
// current global visibility buffer, but don't cache it because it could be replaced later.
id<MTLBuffer> MVKOcclusionQueryPool::getVisibilityResultMTLBuffer() {
    return _visibilityResultMTLBuffer ? _visibilityResultMTLBuffer : _device->getGlobalVisibilityResultMTLBuffer();
}

NSUInteger MVKOcclusionQueryPool::getVisibilityResultOffset(uint32_t query) {
    return (NSUInteger)(_queryIndexOffset + query) * kMVKQuerySlotSizeInBytes;
}

void MVKOcclusionQueryPool::beginQuery(uint32_t query, VkQueryControlFlags flags, MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->beginOcclusionQuery(this, query, flags);
}

void MVKOcclusionQueryPool::endQuery(uint32_t query, MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->endOcclusionQuery(this, query);
}

void MVKOcclusionQueryPool::resetResults(uint32_t firstQuery, uint32_t queryCount, MVKCommandEncoder* cmdEncoder) {
    MVKQueryPool::resetResults(firstQuery, queryCount, cmdEncoder);

    id<MTLBlitCommandEncoder> blitEncoder = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseResetQueryPool);
    NSUInteger firstOffset = getVisibilityResultOffset(firstQuery);
    NSUInteger lastOffset = getVisibilityResultOffset(firstQuery + queryCount);

    [blitEncoder fillBuffer: getVisibilityResultMTLBuffer()
                      range: NSMakeRange(firstOffset, lastOffset - firstOffset)
                      value: 0];
}

void MVKOcclusionQueryPool::getResult(uint32_t query, void* pQryData, bool shouldOutput64Bit) {
    NSUInteger mtlBuffOffset = getVisibilityResultOffset(query);
    uint64_t* pData = (uint64_t*)((uintptr_t)getVisibilityResultMTLBuffer().contents + mtlBuffOffset);

    if (shouldOutput64Bit) {
        *(uint64_t*)pQryData = *pData;
    } else {
        *(uint32_t*)pQryData = (uint32_t)(*pData);
    }
}

void MVKOcclusionQueryPool::beginQueryAddedTo(uint32_t query, MVKCommandBuffer* cmdBuffer) {
    NSUInteger offset = getVisibilityResultOffset(query);
    NSUInteger maxOffset = getDevice()->_pMetalFeatures->maxQueryBufferSize - kMVKQuerySlotSizeInBytes;
    if (offset > maxOffset) {
        cmdBuffer->recordResult(mvkNotifyErrorWithText(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCmdBeginQuery(): The query offset value %lu is larger than the maximum offset value %lu available on this device.", offset, maxOffset));
    }

    if (cmdBuffer->_initialVisibilityResultMTLBuffer == nil) {
        cmdBuffer->_initialVisibilityResultMTLBuffer = getVisibilityResultMTLBuffer();
    }
}


#pragma mark Construction

MVKOcclusionQueryPool::MVKOcclusionQueryPool(MVKDevice* device,
                                             const VkQueryPoolCreateInfo* pCreateInfo) : MVKQueryPool(device, pCreateInfo, 1) {

    if (_device->_mvkConfig.supportLargeQueryPools) {
        _queryIndexOffset = 0;

        // Ensure we don't overflow the maximum number of queries
        uint32_t queryCount = pCreateInfo->queryCount;
        VkDeviceSize reqBuffLen = (VkDeviceSize)queryCount * kMVKQuerySlotSizeInBytes;
        VkDeviceSize maxBuffLen = _device->_pMetalFeatures->maxQueryBufferSize;
        VkDeviceSize newBuffLen = min(reqBuffLen, maxBuffLen);
        queryCount = uint32_t(newBuffLen / kMVKQuerySlotSizeInBytes);

        if (reqBuffLen > maxBuffLen) {
            mvkNotifyErrorWithText(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCreateQueryPool(): Each query pool can support a maximum of %d queries.", queryCount);
        }

        NSUInteger mtlBuffLen = mvkAlignByteOffset(newBuffLen, _device->_pMetalFeatures->mtlBufferAlignment);
        MTLResourceOptions mtlBuffOpts = MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache;
        _visibilityResultMTLBuffer = [getMTLDevice() newBufferWithLength: mtlBuffLen options: mtlBuffOpts];     // retained

    } else {
        _queryIndexOffset = _device->expandVisibilityResultMTLBuffer(pCreateInfo->queryCount);
        _visibilityResultMTLBuffer = nil;   // Will delegate to global buffer in device on access
    }
}

MVKOcclusionQueryPool::~MVKOcclusionQueryPool() {
    [_visibilityResultMTLBuffer release];
};


#pragma mark -
#pragma mark MVKPipelineStatisticsQueryPool

MVKPipelineStatisticsQueryPool::MVKPipelineStatisticsQueryPool(MVKDevice* device,
															   const VkQueryPoolCreateInfo* pCreateInfo) : MVKQueryPool(device, pCreateInfo, 1) {
	if ( !_device->_pFeatures->pipelineStatisticsQuery ) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateQueryPool: VK_QUERY_TYPE_PIPELINE_STATISTICS is not supported."));
	}
}


#pragma mark -
#pragma mark MVKUnsupportedQueryPool

MVKUnsupportedQueryPool::MVKUnsupportedQueryPool(MVKDevice* device,
												 const VkQueryPoolCreateInfo* pCreateInfo) : MVKQueryPool(device, pCreateInfo, 1) {
	setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "vkCreateQueryPool: Unsupported query pool type: %d.", pCreateInfo->queryType));
}
