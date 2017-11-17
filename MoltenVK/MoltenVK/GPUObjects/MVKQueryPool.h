/*
 * MVKQueryPool.h
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKDevice.h"
#include <vector>
#include <mutex>
#include <condition_variable>

class MVKBuffer;
class MVKCommandBuffer;
class MVKCommandEncoder;

// The size of one query slot in bytes
#define kMVKQuerySlotSizeInBytes      sizeof(uint64_t)


#pragma mark -
#pragma mark MVKQueryPool

/** 
 * Abstract class representing a Vulkan query pool.
 * Subclasses are specialized for specific query types.
 * Subclasses will generally override the beginQuery(), endQuery(), and getResult(uint32_t, void*, bool) member functions.
 */
class MVKQueryPool : public MVKBaseDeviceObject {

public:

    /** Begins the specified query. */
    virtual void beginQuery(uint32_t query, VkQueryControlFlags flags, MVKCommandEncoder* cmdEncoder) {}

    /** Ends the specified query. */
    virtual void endQuery(uint32_t query, MVKCommandEncoder* cmdEncoder) {}

    /** Finishes the specified queries and marks them as available. */
    virtual void finishQueries(std::vector<uint32_t>& queries);

	/** Resets the results and availability status of the specified queries. */
	virtual void resetResults(uint32_t firstQuery, uint32_t queryCount, MVKCommandEncoder* cmdEncoder);

	/** Copies the results of the specified queries into host memory. */
	VkResult getResults(uint32_t firstQuery,
						uint32_t queryCount,
						size_t dataSize,
						void* pData,
						VkDeviceSize stride,
						VkQueryResultFlags flags);

	/** Copies the results of the specified queries into a buffer. */
    virtual void copyQueryPoolResults(uint32_t firstQuery,
                                      uint32_t queryCount,
                                      MVKBuffer* destBuffer,
                                      VkDeviceSize destOffset,
                                      VkDeviceSize destStride,
                                      VkQueryResultFlags flags);

    /** Called from the MVKCmdBeginQuery command when it is added to the command buffer */
    virtual void beginQueryAddedTo(uint32_t query, MVKCommandBuffer* cmdBuffer) {};


#pragma mark Construction

	MVKQueryPool(MVKDevice* device,
				 const VkQueryPoolCreateInfo* pCreateInfo,
				 const uint32_t queryElementCount) : MVKBaseDeviceObject(device),
                    _availability(pCreateInfo->queryCount),
                    _queryElementCount(queryElementCount) {}

protected:
	bool areQueriesAvailable(uint32_t firstQuery, uint32_t endQuery);
    VkResult getResult(uint32_t query, void* pQryData, VkQueryResultFlags flags);
	virtual void getResult(uint32_t query, void* pQryData, bool shouldOutput64Bit) {}

	std::vector<bool> _availability;
	uint32_t _queryElementCount;
	std::mutex _availabilityLock;
	std::condition_variable _availabilityBlocker;
};


#pragma mark -
#pragma mark MVKTimestampQueryPool

/** A Vulkan query pool for timestamp queries. */
class MVKTimestampQueryPool : public MVKQueryPool {

public:
    void finishQueries(std::vector<uint32_t>& queries) override;


#pragma mark Construction

	MVKTimestampQueryPool(MVKDevice* device, const VkQueryPoolCreateInfo* pCreateInfo);

protected:
	void getResult(uint32_t query, void* pQryData, bool shouldOutput64Bit) override;

	std::vector<uint64_t> _timestamps;
};


#pragma mark -
#pragma mark MVKOcclusionQueryPool

/** A Vulkan query pool for occlusion queries. */
class MVKOcclusionQueryPool : public MVKQueryPool {

public:

    /** Returns the MTLBuffer used to hold occlusion query results. */
    id<MTLBuffer> getVisibilityResultMTLBuffer();

    /** Returns the offset of the specified query in the visibility MTLBuffer. */
    NSUInteger getVisibilityResultOffset(uint32_t query);

    void beginQuery(uint32_t query, VkQueryControlFlags flags, MVKCommandEncoder* cmdEncoder) override;
    void endQuery(uint32_t query, MVKCommandEncoder* cmdEncoder) override;
    void resetResults(uint32_t firstQuery, uint32_t queryCount, MVKCommandEncoder* cmdEncoder) override;
    void beginQueryAddedTo(uint32_t query, MVKCommandBuffer* cmdBuffer) override;


#pragma mark Construction

    MVKOcclusionQueryPool(MVKDevice* device, const VkQueryPoolCreateInfo* pCreateInfo);

    ~MVKOcclusionQueryPool() override;

protected:
    void getResult(uint32_t query, void* pQryData, bool shouldOutput64Bit) override;

    id<MTLBuffer> _visibilityResultMTLBuffer;
    uint32_t _queryIndexOffset;
};


#pragma mark -
#pragma mark MVKUnsupportedQueryPool

/** A Vulkan query pool for a query pool type that is unsupported in Metal. */
class MVKUnsupportedQueryPool : public MVKQueryPool {

public:
    MVKUnsupportedQueryPool(MVKDevice* device, const VkQueryPoolCreateInfo* pCreateInfo);

};

