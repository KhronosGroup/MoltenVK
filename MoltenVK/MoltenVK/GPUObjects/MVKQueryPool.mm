/*
 * MVKQueryPool.mm
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

#include "MVKQueryPool.h"
#include "MVKBuffer.h"
#include "MVKRenderPass.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandEncodingPool.h"
#include "MVKOSExtensions.h"
#include "MVKFoundation.h"
#include <sys/mman.h>

using namespace std;


#pragma mark MVKQueryPool

void MVKQueryPool::endQuery(uint32_t query, MVKCommandEncoder* cmdEncoder) {
    uint32_t queryCount = cmdEncoder->isInRenderPass() ? cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
    queryCount = max(queryCount, 1u);
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
void MVKQueryPool::finishQueries(MVKArrayRef<const uint32_t> queries) {
    lock_guard<mutex> lock(_availabilityLock);
    for (uint32_t qry : queries) {
        if (_availability[qry] == DeviceAvailable) {
            _availability[qry] = Available;
        }
    }
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
	@autoreleasepool {
		NSData* srcData = getQuerySourceData(firstQuery, queryCount);
		uintptr_t pDstData = (uintptr_t)pData;
		for (uint32_t query = firstQuery; query < endQuery; query++, pDstData += stride) {
			VkResult qryRslt = getResult(query, srcData, firstQuery, (void*)pDstData, flags);
			if (rqstRslt == VK_SUCCESS) { rqstRslt = qryRslt; }
		}
	}
	return rqstRslt;
}

bool MVKQueryPool::areQueriesDeviceAvailable(uint32_t firstQuery, uint32_t endQuery) {
    for (uint32_t query = firstQuery; query < endQuery; query++) {
        if ( _availability[query] < DeviceAvailable ) { return false; }
    }
    return true;
}

// Returns whether any queries between the start (inclusive) and end (exclusive) queries,
// that were encoded to be written to by an earlier EndQuery or Timestamp command, are now available.
// Queries that were not encoded to be written, will be in Initial state.
// Queries that were encoded to be written, and are available, will be in Available state.
// Queries that were encoded to be written, but are not available, will be in DeviceAvailable state.
bool MVKQueryPool::areQueriesHostAvailable(uint32_t firstQuery, uint32_t endQuery) {
    // If we lost the device, stop waiting immediately.
    if (_device->getConfigurationResult() != VK_SUCCESS) { return true; }
    for (uint32_t query = firstQuery; query < endQuery; query++) {
        if (_availability[query] == DeviceAvailable) { return false; }
    }
    return true;
}

VkResult MVKQueryPool::getResult(uint32_t query, NSData* srcData, uint32_t srcDataQueryOffset, void* pDstData, VkQueryResultFlags flags) {

	if (_device->getConfigurationResult() != VK_SUCCESS) { return _device->getConfigurationResult(); }

	bool isAvailable = _availability[query] == Available;
	bool shouldOutput = (isAvailable || mvkAreAllFlagsEnabled(flags, VK_QUERY_RESULT_PARTIAL_BIT));
	bool shouldOutput64Bit = mvkAreAllFlagsEnabled(flags, VK_QUERY_RESULT_64_BIT);

	// Output the results of this query
	if (shouldOutput) {
		uint64_t rsltVal = ((uint64_t*)srcData.bytes)[query - srcDataQueryOffset];
		if (shouldOutput64Bit) {
			*(uint64_t*)pDstData = rsltVal;
		} else {
			*(uint32_t*)pDstData = (uint32_t)rsltVal;
		}
	}

	// If requested, output the availability bit
	if (mvkAreAllFlagsEnabled(flags, VK_QUERY_RESULT_WITH_AVAILABILITY_BIT)) {
		if (shouldOutput64Bit) {
			uintptr_t pAvailability = (uintptr_t)pDstData + (_queryElementCount * sizeof(uint64_t));
			*(uint64_t*)pAvailability = isAvailable;
		} else {
			uintptr_t pAvailability = (uintptr_t)pDstData + (_queryElementCount * sizeof(uint32_t));
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

	if (queryCount == 0) { return; }

	// If this asked for 64-bit results with no availability and packed stride, then we can do
	// a straight copy. Otherwise, we need a shader.
	if (mvkIsAnyFlagEnabled(flags, VK_QUERY_RESULT_64_BIT) &&
		!mvkIsAnyFlagEnabled(flags, VK_QUERY_RESULT_WITH_AVAILABILITY_BIT) &&
		stride == _queryElementCount * sizeof(uint64_t) &&
		areQueriesDeviceAvailable(firstQuery, queryCount)) {

		encodeDirectCopyResults(cmdEncoder, firstQuery, queryCount, destBuffer, destOffset, stride);
		// TODO: In the case where none of the queries is ready, we can fill with 0.
	} else {
		id<MTLComputePipelineState> mtlCopyResultsState = cmdEncoder->getCommandEncodingPool()->getCmdCopyQueryPoolResultsMTLComputePipelineState();
		id<MTLComputeCommandEncoder> mtlComputeCmdEnc = encodeComputeCopyResults(cmdEncoder, firstQuery, queryCount, 0);
		[mtlComputeCmdEnc setComputePipelineState: mtlCopyResultsState];
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
		NSUInteger threadCount = NSUInteger(queryCount);
		NSUInteger threadExecutionWidth = mtlCopyResultsState.threadExecutionWidth;
		NSUInteger tgWidth = min(threadCount, threadExecutionWidth);
		NSUInteger tgCount = threadCount / threadExecutionWidth;
		if(threadCount > (tgCount * threadExecutionWidth)) tgCount++;	// Round up

		[mtlComputeCmdEnc dispatchThreadgroups: MTLSizeMake(tgCount, 1, 1)
						 threadsPerThreadgroup: MTLSizeMake(tgWidth, 1, 1)];
	}
}

// If this asked for 64-bit results with no availability and packed stride, then we can do a straight copy.
void MVKQueryPool::encodeDirectCopyResults(MVKCommandEncoder* cmdEncoder,
									 uint32_t firstQuery,
									 uint32_t queryCount,
									 MVKBuffer* destBuffer,
									 VkDeviceSize destOffset,
									 VkDeviceSize stride) {

	id<MTLBlitCommandEncoder> mtlBlitCmdEnc = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyQueryPoolResults);
	NSUInteger srcOffset;
	id<MTLBuffer> srcBuff = getResultBuffer(cmdEncoder, firstQuery, queryCount, srcOffset);
	[mtlBlitCmdEnc copyFromBuffer: srcBuff
					 sourceOffset: srcOffset
						 toBuffer: destBuffer->getMTLBuffer()
				destinationOffset: destBuffer->getMTLBufferOffset() + destOffset
							 size: stride * queryCount];
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
#pragma mark MVKOcclusionQueryPool

void MVKOcclusionQueryPool::propagateDebugName() { setMetalObjectLabel(_visibilityResultMTLBuffer, _debugName); }

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

NSData* MVKOcclusionQueryPool::getQuerySourceData(uint32_t firstQuery, uint32_t queryCount) {
	id<MTLBuffer> vizBuff = getVisibilityResultMTLBuffer();
	return [NSData dataWithBytesNoCopy: (void*)((uintptr_t)vizBuff.contents + getVisibilityResultOffset(firstQuery))
								length: queryCount * kMVKQuerySlotSizeInBytes
						  freeWhenDone: false];
}

id<MTLBuffer> MVKOcclusionQueryPool::getResultBuffer(MVKCommandEncoder*, uint32_t firstQuery, uint32_t, NSUInteger& offset) {
	offset = getVisibilityResultOffset(firstQuery);
	return getVisibilityResultMTLBuffer();
}

id<MTLComputeCommandEncoder> MVKOcclusionQueryPool::encodeComputeCopyResults(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t, uint32_t index) {
	id<MTLComputeCommandEncoder> mtlCmdEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyQueryPoolResults, true);
	[mtlCmdEnc setBuffer: getVisibilityResultMTLBuffer() offset: getVisibilityResultOffset(firstQuery) atIndex: index];
	return mtlCmdEnc;
}

void MVKOcclusionQueryPool::beginQueryAddedTo(uint32_t query, MVKCommandBuffer* cmdBuffer) {
	// In multiview passes, one query is used for each view.
	NSUInteger queryCount = cmdBuffer->getViewCount();
    NSUInteger offset = getVisibilityResultOffset(query);
    NSUInteger maxOffset = getMetalFeatures().maxQueryBufferSize - kMVKQuerySlotSizeInBytes * queryCount;
    if (offset > maxOffset) {
        cmdBuffer->setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCmdBeginQuery(): The query offset value %lu is larger than the maximum offset value %lu available on this device.", offset, maxOffset));
    }

    cmdBuffer->_needsVisibilityResultMTLBuffer = true;
}


#pragma mark Construction

MVKOcclusionQueryPool::MVKOcclusionQueryPool(MVKDevice* device,
                                             const VkQueryPoolCreateInfo* pCreateInfo) : MVKQueryPool(device, pCreateInfo, 1) {

    if (getMVKConfig().supportLargeQueryPools) {
        _queryIndexOffset = 0;

        // Ensure we don't overflow the maximum number of queries
		auto& mtlFeats = getMetalFeatures();
        VkDeviceSize reqBuffLen = (VkDeviceSize)pCreateInfo->queryCount * kMVKQuerySlotSizeInBytes;
        VkDeviceSize maxBuffLen = mtlFeats.maxQueryBufferSize;
        VkDeviceSize newBuffLen = min(reqBuffLen, maxBuffLen);

        if (reqBuffLen > maxBuffLen) {
			reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
						"vkCreateQueryPool(): Each occlusion query pool can support a maximum of %d queries.",
						uint32_t(newBuffLen / kMVKQuerySlotSizeInBytes));
        }

        NSUInteger mtlBuffLen = mvkAlignByteCount(newBuffLen, mtlFeats.mtlBufferAlignment);
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
#pragma mark MVKGPUCounterQueryPool

MVKGPUCounterQueryPool::MVKGPUCounterQueryPool(MVKDevice* device, const VkQueryPoolCreateInfo* pCreateInfo) :
	MVKQueryPool(device, pCreateInfo, 1), _mtlCounterBuffer(nil) {}

// To establish the Metal counter sample buffer, this must be called from the construtors
// of subclasses, because the type of MTLCounterSet is determined by the subclass.
void MVKGPUCounterQueryPool::initMTLCounterSampleBuffer(const VkQueryPoolCreateInfo* pCreateInfo,
														id<MTLCounterSet> mtlCounterSet,
														const char* queryTypeName) {
	if ( !mtlCounterSet ) { return; }

	@autoreleasepool {
		MTLCounterSampleBufferDescriptor* tsDesc = [[[MTLCounterSampleBufferDescriptor alloc] init] autorelease];
		tsDesc.counterSet = mtlCounterSet;
		tsDesc.storageMode = MTLStorageModeShared;
		tsDesc.sampleCount = pCreateInfo->queryCount;

		NSError* err = nil;
		_mtlCounterBuffer = [getMTLDevice() newCounterSampleBufferWithDescriptor: tsDesc error: &err];
		if (err) {
			reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
						"Could not create MTLCounterSampleBuffer of size %llu, for %d queries, in query pool of type %s. Reverting to emulated behavior. (Error code %li): %s",
						(VkDeviceSize)pCreateInfo->queryCount * kMVKQuerySlotSizeInBytes, pCreateInfo->queryCount, queryTypeName, (long)err.code, err.localizedDescription.UTF8String);
		}
	}
};

MVKGPUCounterQueryPool::~MVKGPUCounterQueryPool() {
	[_mtlCounterBuffer release];
}


#pragma mark -
#pragma mark MVKTimestampQueryPool

void MVKTimestampQueryPool::endQuery(uint32_t query, MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->markTimestamp(this, query);
	MVKQueryPool::endQuery(query, cmdEncoder);
}

// If not using MTLCounterSampleBuffer, update timestamp values, then mark queries as available
void MVKTimestampQueryPool::finishQueries(MVKArrayRef<const uint32_t> queries) {
	if ( !_mtlCounterBuffer ) {
		uint64_t ts = mvkGetElapsedNanoseconds();
		for (uint32_t qry : queries) { _timestamps[qry] = ts; }
	}
	MVKQueryPool::finishQueries(queries);
}

NSData* MVKTimestampQueryPool::getQuerySourceData(uint32_t firstQuery, uint32_t queryCount) {
	if (_mtlCounterBuffer) {
		return [_mtlCounterBuffer resolveCounterRange: NSMakeRange(firstQuery, queryCount)];
	} else {
		return [NSData dataWithBytesNoCopy: (void*)&_timestamps[firstQuery]
									length: queryCount * kMVKQuerySlotSizeInBytes
							  freeWhenDone: false];
	}
}

void MVKTimestampQueryPool::encodeDirectCopyResults(MVKCommandEncoder* cmdEncoder,
													uint32_t firstQuery,
													uint32_t queryCount,
													MVKBuffer* destBuffer,
													VkDeviceSize destOffset,
													VkDeviceSize stride) {
	if (_mtlCounterBuffer) {
		id<MTLBlitCommandEncoder> mtlBlitCmdEnc = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyQueryPoolResults);
		[mtlBlitCmdEnc resolveCounters: _mtlCounterBuffer
							   inRange: NSMakeRange(firstQuery,  queryCount)
					 destinationBuffer: destBuffer->getMTLBuffer()
					 destinationOffset: destBuffer->getMTLBufferOffset() + destOffset];
	} else {
		MVKQueryPool::encodeDirectCopyResults(cmdEncoder, firstQuery, queryCount, destBuffer, destOffset, stride);
	}
}

id<MTLBuffer> MVKTimestampQueryPool::getResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, NSUInteger& offset) {
	const MVKMTLBufferAllocation* tempBuff = cmdEncoder->getTempMTLBuffer(queryCount * _queryElementCount * sizeof(uint64_t));
	void* pBuffData = tempBuff->getContents();
	size_t size = queryCount * _queryElementCount * sizeof(uint64_t);
	memcpy(pBuffData, &_timestamps[firstQuery], size);
	offset = tempBuff->_offset;
	return tempBuff->_mtlBuffer;
}

id<MTLComputeCommandEncoder> MVKTimestampQueryPool::encodeComputeCopyResults(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, uint32_t index) {
	if (_mtlCounterBuffer) {
		// We first need to resolve from the MTLCounterSampleBuffer into a temp buffer using a
		// MTLBlitCommandEncoder, before creating the compute encoder and set that temp buffer into it.
		const MVKMTLBufferAllocation* tempBuff = cmdEncoder->getTempMTLBuffer(queryCount * _queryElementCount * sizeof(uint64_t));
		id<MTLBlitCommandEncoder> mtlBlitCmdEnc = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyQueryPoolResults);
		[mtlBlitCmdEnc resolveCounters: _mtlCounterBuffer
							   inRange: NSMakeRange(firstQuery,  queryCount)
					 destinationBuffer: tempBuff->_mtlBuffer
					 destinationOffset: tempBuff->_offset];

		id<MTLComputeCommandEncoder> mtlCmdEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyQueryPoolResults, true);
		[mtlCmdEnc setBuffer: tempBuff->_mtlBuffer offset: tempBuff->_offset atIndex: index];
		return mtlCmdEnc;
	} else {
		// We can set the timestamp bytes into the compute encoder.
		id<MTLComputeCommandEncoder> mtlCmdEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyQueryPoolResults, true);
		cmdEncoder->setComputeBytes(mtlCmdEnc, &_timestamps[firstQuery], queryCount * _queryElementCount * sizeof(uint64_t), index);
		return mtlCmdEnc;
	}
}


#pragma mark Construction

MVKTimestampQueryPool::MVKTimestampQueryPool(MVKDevice* device, const VkQueryPoolCreateInfo* pCreateInfo) :
	MVKGPUCounterQueryPool(device, pCreateInfo) {

		initMTLCounterSampleBuffer(pCreateInfo, _device->getTimestampMTLCounterSet(), "VK_QUERY_TYPE_TIMESTAMP");

		// If we don't use a MTLCounterSampleBuffer, allocate memory to hold the timestamps.
		if ( !_mtlCounterBuffer ) { _timestamps.resize(pCreateInfo->queryCount, 0); }
}


#pragma mark -
#pragma mark MVKPipelineStatisticsQueryPool

MVKPipelineStatisticsQueryPool::MVKPipelineStatisticsQueryPool(MVKDevice* device,
															   const VkQueryPoolCreateInfo* pCreateInfo) : MVKGPUCounterQueryPool(device, pCreateInfo) {
	if ( !getEnabledFeatures().pipelineStatisticsQuery ) {
		setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCreateQueryPool: VK_QUERY_TYPE_PIPELINE_STATISTICS is not supported."));
	}
}


#pragma mark -
#pragma mark MVKUnsupportedQueryPool

MVKUnsupportedQueryPool::MVKUnsupportedQueryPool(MVKDevice* device,
												 const VkQueryPoolCreateInfo* pCreateInfo) : MVKQueryPool(device, pCreateInfo, 1) {
	setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateQueryPool: Unsupported query pool type: %d.", pCreateInfo->queryType));
}
