/*
 * MVKQueryPool.mm
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

#include "MVKQueryPool.h"
#include "MVKBuffer.h"
#include "MVKRenderPass.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandEncodingPool.h"
#include "MVKOSExtensions.h"
#include "MVKFoundation.h"

using namespace std;


#pragma mark MVKQueryPool

void MVKQueryPool::endQuery(uint32_t query, MVKCommandEncoder* cmdEncoder) {
    uint32_t queryCount = cmdEncoder->isInRenderPass() ? cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
    lock_guard<mutex> lock(_availabilityLock);
    for (uint32_t i = query; i < query + queryCount; ++i) {
        _availability[i] = DeviceAvailable;
    }
    lock_guard<mutex> copyLock(_deferredCopiesLock);
    if (!_deferredCopies.empty()) {
        // Partition by readiness.
        auto ready = std::partition(_deferredCopies.begin(), _deferredCopies.end(), [this](const DeferredCopy& copy) {
            return !areQueriesDeviceAvailable(copy.firstQuery, copy.queryCount);
        });
        // Execute the ready copies, then remove them.
        for (auto i = ready; i != _deferredCopies.end(); ++i) {
            encodeCopyResults(cmdEncoder, i->firstQuery, i->queryCount, i->destBuffer, i->destOffset, i->stride, i->flags);
        }
        _deferredCopies.erase(ready, _deferredCopies.end());
    }
}

// Mark queries as available
void MVKQueryPool::finishQueries(const MVKArrayRef<uint32_t>& queries) {
    lock_guard<mutex> lock(_availabilityLock);
    for (uint32_t qry : queries) { _availability[qry] = Available; }
    _availabilityBlocker.notify_all();      // Predicate of each wait() call will check whether all required queries are available
}

void MVKQueryPool::resetResults(uint32_t firstQuery, uint32_t queryCount, MVKCommandEncoder* cmdEncoder) {
    lock_guard<mutex> lock(_availabilityLock);
    uint32_t endQuery = firstQuery + queryCount;
    for (uint32_t query = firstQuery; query < endQuery; query++) {
        _availability[query] = Initial;
    }
}

VkResult MVKQueryPool::getResults(uint32_t firstQuery,
								  uint32_t queryCount,
								  size_t dataSize,
								  void* pData,
								  VkDeviceSize stride,
								  VkQueryResultFlags flags) {
	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }

	unique_lock<mutex> lock(_availabilityLock);

	uint32_t endQuery = firstQuery + queryCount;

	if (mvkAreAllFlagsEnabled(flags, VK_QUERY_RESULT_WAIT_BIT)) {
		_availabilityBlocker.wait(lock, [this, firstQuery, endQuery]{
			return areQueriesHostAvailable(firstQuery, endQuery);
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

bool MVKQueryPool::areQueriesDeviceAvailable(uint32_t firstQuery, uint32_t endQuery) {
    for (uint32_t query = firstQuery; query < endQuery; query++) {
        if ( _availability[query] < DeviceAvailable ) { return false; }
    }
    return true;
}

// Returns whether all the queries between the start (inclusive) and end (exclusive) queries are available.
bool MVKQueryPool::areQueriesHostAvailable(uint32_t firstQuery, uint32_t endQuery) {
    // If we lost the device, stop waiting immediately.
    if (_device->getConfigurationResult() != VK_SUCCESS) { return true; }
    for (uint32_t query = firstQuery; query < endQuery; query++) {
        if ( _availability[query] < Available ) { return false; }
    }
    return true;
}

VkResult MVKQueryPool::getResult(uint32_t query, void* pQryData, VkQueryResultFlags flags) {

	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }

	bool isAvailable = _availability[query] == Available;
	bool shouldOutput = (isAvailable || mvkAreAllFlagsEnabled(flags, VK_QUERY_RESULT_PARTIAL_BIT));
	bool shouldOutput64Bit = mvkAreAllFlagsEnabled(flags, VK_QUERY_RESULT_64_BIT);

	// Output the results of this query
	if (shouldOutput) { getResult(query, pQryData, shouldOutput64Bit); }

	// If requested, output the availability bit
	if (mvkAreAllFlagsEnabled(flags, VK_QUERY_RESULT_WITH_AVAILABILITY_BIT)) {
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

void MVKQueryPool::encodeCopyResults(MVKCommandEncoder* cmdEncoder,
									 uint32_t firstQuery,
									 uint32_t queryCount,
									 MVKBuffer* destBuffer,
									 VkDeviceSize destOffset,
									 VkDeviceSize stride,
									 VkQueryResultFlags flags) {

	// If this asked for 64-bit results with no availability and packed stride, then we can do
	// a straight copy. Otherwise, we need a shader.
	if (mvkIsAnyFlagEnabled(flags, VK_QUERY_RESULT_64_BIT) &&
		!mvkIsAnyFlagEnabled(flags, VK_QUERY_RESULT_WITH_AVAILABILITY_BIT) &&
		stride == _queryElementCount * sizeof(uint64_t) &&
		areQueriesDeviceAvailable(firstQuery, queryCount)) {

		id<MTLBlitCommandEncoder> mtlBlitCmdEnc = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyQueryPoolResults);
		NSUInteger srcOffset;
		id<MTLBuffer> srcBuff = getResultBuffer(cmdEncoder, firstQuery, queryCount, srcOffset);
		[mtlBlitCmdEnc copyFromBuffer: srcBuff
						 sourceOffset: srcOffset
							 toBuffer: destBuffer->getMTLBuffer()
					destinationOffset: destBuffer->getMTLBufferOffset() + destOffset
								 size: stride * queryCount];
		// TODO: In the case where none of the queries is ready, we can fill with 0.
	} else {
		id<MTLComputeCommandEncoder> mtlComputeCmdEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyQueryPoolResults);
		id<MTLComputePipelineState> mtlCopyResultsState = cmdEncoder->getCommandEncodingPool()->getCmdCopyQueryPoolResultsMTLComputePipelineState();
		[mtlComputeCmdEnc setComputePipelineState: mtlCopyResultsState];
		encodeSetResultBuffer(cmdEncoder, firstQuery, queryCount, 0);
		[mtlComputeCmdEnc setBuffer: destBuffer->getMTLBuffer()
							 offset: destBuffer->getMTLBufferOffset() + destOffset
							atIndex: 1];
		cmdEncoder->setComputeBytes(mtlComputeCmdEnc, &stride, sizeof(uint32_t), 2);
		cmdEncoder->setComputeBytes(mtlComputeCmdEnc, &queryCount, sizeof(uint32_t), 3);
		cmdEncoder->setComputeBytes(mtlComputeCmdEnc, &flags, sizeof(VkQueryResultFlags), 4);
		_availabilityLock.lock();
		cmdEncoder->setComputeBytes(mtlComputeCmdEnc, _availability.data(), _availability.size() * sizeof(Status), 5);
		_availabilityLock.unlock();
		// Run one thread per query. Try to fill up a subgroup.
		[mtlComputeCmdEnc dispatchThreadgroups: MTLSizeMake(max(queryCount / mtlCopyResultsState.threadExecutionWidth, NSUInteger(1)), 1, 1)
						  threadsPerThreadgroup: MTLSizeMake(min(NSUInteger(queryCount), mtlCopyResultsState.threadExecutionWidth), 1, 1)];
	}
}

void MVKQueryPool::deferCopyResults(uint32_t firstQuery,
									uint32_t queryCount,
									MVKBuffer* destBuffer,
									VkDeviceSize destOffset,
									VkDeviceSize stride,
									VkQueryResultFlags flags) {

	lock_guard<mutex> lock(_deferredCopiesLock);
	_deferredCopies.push_back({firstQuery, queryCount, destBuffer, destOffset, stride, flags});
}


#pragma mark -
#pragma mark MVKTimestampQueryPool

// Update timestamp values, then mark queries as available
void MVKTimestampQueryPool::finishQueries(const MVKArrayRef<uint32_t>& queries) {
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

id<MTLBuffer> MVKTimestampQueryPool::getResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, NSUInteger& offset) {
	const MVKMTLBufferAllocation* tempBuff = cmdEncoder->getTempMTLBuffer(queryCount * _queryElementCount * sizeof(uint64_t));
	memcpy(tempBuff->getContents(), &_timestamps[firstQuery], queryCount * _queryElementCount * sizeof(uint64_t));
	offset = tempBuff->_offset;
	return tempBuff->_mtlBuffer;
}

void MVKTimestampQueryPool::encodeSetResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, uint32_t index) {
	// No need to create a temp buffer here.
	cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyQueryPoolResults), &_timestamps[firstQuery], queryCount * _queryElementCount * sizeof(uint64_t), index);
}


#pragma mark Construction

MVKTimestampQueryPool::MVKTimestampQueryPool(MVKDevice* device,
											 const VkQueryPoolCreateInfo* pCreateInfo) :
	MVKQueryPool(device, pCreateInfo, 1), _timestamps(pCreateInfo->queryCount, 0) {
}


#pragma mark -
#pragma mark MVKOcclusionQueryPool

void MVKOcclusionQueryPool::propagateDebugName() { setLabelIfNotNil(_visibilityResultMTLBuffer, _debugName); }

// If a dedicated visibility buffer has been established, use it, otherwise fetch the
// current global visibility buffer, but don't cache it because it could be replaced later.
id<MTLBuffer> MVKOcclusionQueryPool::getVisibilityResultMTLBuffer() {
    return _visibilityResultMTLBuffer ? _visibilityResultMTLBuffer : _device->getGlobalVisibilityResultMTLBuffer();
}

NSUInteger MVKOcclusionQueryPool::getVisibilityResultOffset(uint32_t query) {
    return (NSUInteger)(_queryIndexOffset + query) * kMVKQuerySlotSizeInBytes;
}

void MVKOcclusionQueryPool::beginQuery(uint32_t query, VkQueryControlFlags flags, MVKCommandEncoder* cmdEncoder) {
    MVKQueryPool::beginQuery(query, flags, cmdEncoder);
    cmdEncoder->beginOcclusionQuery(this, query, flags);
}

void MVKOcclusionQueryPool::endQuery(uint32_t query, MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->endOcclusionQuery(this, query);
    MVKQueryPool::endQuery(query, cmdEncoder);
}

void MVKOcclusionQueryPool::resetResults(uint32_t firstQuery, uint32_t queryCount, MVKCommandEncoder* cmdEncoder) {
    MVKQueryPool::resetResults(firstQuery, queryCount, cmdEncoder);

    NSUInteger firstOffset = getVisibilityResultOffset(firstQuery);
    NSUInteger lastOffset = getVisibilityResultOffset(firstQuery + queryCount);
    if (cmdEncoder) {
        id<MTLBlitCommandEncoder> blitEncoder = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseResetQueryPool);

        [blitEncoder fillBuffer: getVisibilityResultMTLBuffer()
                          range: NSMakeRange(firstOffset, lastOffset - firstOffset)
                          value: 0];
    } else {  // Host-side reset
        id<MTLBuffer> vizBuff = getVisibilityResultMTLBuffer();
        size_t byteCount = std::min(lastOffset, vizBuff.length) - firstOffset;
        mvkClear((char *)[vizBuff contents] + firstOffset, byteCount);
    }
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

id<MTLBuffer> MVKOcclusionQueryPool::getResultBuffer(MVKCommandEncoder*, uint32_t firstQuery, uint32_t, NSUInteger& offset) {
	offset = getVisibilityResultOffset(firstQuery);
	return getVisibilityResultMTLBuffer();
}

void MVKOcclusionQueryPool::encodeSetResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t, uint32_t index) {
	[cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyQueryPoolResults) setBuffer: getVisibilityResultMTLBuffer()
																			 offset: getVisibilityResultOffset(firstQuery)
																			atIndex: index];
}

void MVKOcclusionQueryPool::beginQueryAddedTo(uint32_t query, MVKCommandBuffer* cmdBuffer) {
    NSUInteger offset = getVisibilityResultOffset(query);
    NSUInteger queryCount = 1;
    if (cmdBuffer->getLastMultiviewSubpass()) {
        // In multiview passes, one query is used for each view.
        queryCount = cmdBuffer->getLastMultiviewSubpass()->getViewCount();
    }
    NSUInteger maxOffset = getDevice()->_pMetalFeatures->maxQueryBufferSize - kMVKQuerySlotSizeInBytes * queryCount;
    if (offset > maxOffset) {
        cmdBuffer->setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCmdBeginQuery(): The query offset value %lu is larger than the maximum offset value %lu available on this device.", offset, maxOffset));
    }

    if (cmdBuffer->_initialVisibilityResultMTLBuffer == nil) {
        cmdBuffer->_initialVisibilityResultMTLBuffer = getVisibilityResultMTLBuffer();
    }
}


#pragma mark Construction

MVKOcclusionQueryPool::MVKOcclusionQueryPool(MVKDevice* device,
                                             const VkQueryPoolCreateInfo* pCreateInfo) : MVKQueryPool(device, pCreateInfo, 1) {

    if (_device->_pMVKConfig->supportLargeQueryPools) {
        _queryIndexOffset = 0;

        // Ensure we don't overflow the maximum number of queries
        uint32_t queryCount = pCreateInfo->queryCount;
        VkDeviceSize reqBuffLen = (VkDeviceSize)queryCount * kMVKQuerySlotSizeInBytes;
        VkDeviceSize maxBuffLen = _device->_pMetalFeatures->maxQueryBufferSize;
        VkDeviceSize newBuffLen = min(reqBuffLen, maxBuffLen);
        queryCount = uint32_t(newBuffLen / kMVKQuerySlotSizeInBytes);

        if (reqBuffLen > maxBuffLen) {
            reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCreateQueryPool(): Each query pool can support a maximum of %d queries.", queryCount);
        }

        NSUInteger mtlBuffLen = mvkAlignByteCount(newBuffLen, _device->_pMetalFeatures->mtlBufferAlignment);
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
	if ( !_device->_enabledFeatures.pipelineStatisticsQuery ) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateQueryPool: VK_QUERY_TYPE_PIPELINE_STATISTICS is not supported."));
	}
}


#pragma mark -
#pragma mark MVKUnsupportedQueryPool

MVKUnsupportedQueryPool::MVKUnsupportedQueryPool(MVKDevice* device,
												 const VkQueryPoolCreateInfo* pCreateInfo) : MVKQueryPool(device, pCreateInfo, 1) {
	setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateQueryPool: Unsupported query pool type: %d.", pCreateInfo->queryType));
}
