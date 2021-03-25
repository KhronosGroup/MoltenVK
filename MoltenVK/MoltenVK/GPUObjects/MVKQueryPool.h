/*
 * MVKQueryPool.h
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

#include "MVKDevice.h"
#include "MVKSmallVector.h"
#include <mutex>
#include <condition_variable>

class MVKBuffer;
class MVKCommandBuffer;
class MVKCommandEncoder;

// The size of one query slot in bytes
#define kMVKQuerySlotSizeInBytes		sizeof(uint64_t)
#define kMVKDefaultQueryCount			64


#pragma mark -
#pragma mark MVKQueryPool

/**
 * Index of a GPU query and associated timestamp sample (if the query is a timestamp query).
 */
struct MVKActivatedQueryInfo
{
	uint32_t queryIndex;
	uint32_t timestampSampleIndex;
};

/**
 * CPU and GPU timestamps at two points in time.
 */
struct MVKTimestampCorrelationMarker {
	uint64_t cpuStart;
	uint64_t cpuEnd;
	uint64_t gpuStart;
	uint64_t gpuEnd;
};

/**
 * Manages buffers used for resolving timestamp counter samples.
 */
class MVKTimestampBuffers : public MVKBaseObject, public MVKDeviceTrackingMixin
{
public:
	MVKTimestampBuffers(MVKDevice* device);
	~MVKTimestampBuffers();
	
	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _device; }

	/** Allocates space for a new timestamp sample and return the index of the sample in the sample buffer and the sample buffer itself. */
	uint32_t allocateTimestamp(id<MTLCounterSampleBuffer>& outSampleBuffer);
	
	/** Returns the sample value at the specified index. Sample buffers must be resolved via a call to resolveTimestamps() first. */
	uint64_t getTimestamp(uint32_t index);
	
	/** Returns the number of timestamp samples  in the buffers. */
	uint32_t getTimestampCount() const { return _nextTimestampIndex; }
	
	/** Resolves the timestamp samples and copies them into a CPU readable buffer. */
	void resolveTimestamps();
	
	/**
	 * Called when this instance has been retained as a reference by another object,
	 * indicating that this instance will not be deleted until that reference is released.
	 */
	inline void retain() { _refCount++; }

	/**
	 * Called when this instance has been released as a reference from another object.
	 * Once all references have been released, this object is free to be deleted.
	 * If the destroy() function has already been called on this instance by the time
	 * this function is called, this instance will be deleted.
	 */
	inline void release() { if (--_refCount == 0) { MVKBaseObject::destroy(); } }
	
	/** Creates a new instance of the object. */
	static MVKTimestampBuffers* newObject(MVKDevice* device) { return new MVKTimestampBuffers(device); }
	
protected:
	MVKBaseObject* getBaseObject() override { return this; };
	
private:
	static constexpr uint32_t kTimestampCountPerBuffer = 128;
	
	MVKSmallVector<id<MTLCounterSampleBuffer>, 4> _bufferPool;
	uint32_t _nextTimestampIndex;
	bool _isResolved;
	std::atomic<uint32_t> _refCount;
	std::vector<uint64_t> _resolvedTimestamps;
};

/** 
 * Abstract class representing a Vulkan query pool.
 * Subclasses are specialized for specific query types.
 * Subclasses will generally override the beginQuery(), endQuery(), and getResult(uint32_t, void*, bool) member functions.
 */
class MVKQueryPool : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_QUERY_POOL; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_QUERY_POOL_EXT; }

    /** Begins the specified query. */
    virtual void beginQuery(uint32_t query, VkQueryControlFlags flags, MVKCommandEncoder* cmdEncoder) {}

    /** Ends the specified query. */
    virtual void endQuery(uint32_t query, MVKCommandEncoder* cmdEncoder);

    /** Finishes the specified queries and marks them as available. */
    virtual void finishQueries(const MVKArrayRef<MVKActivatedQueryInfo>& queries, const MVKTimestampCorrelationMarker& timestampCorrelationMarker, MVKTimestampBuffers* timestampBuffers);

	/** Resets the results and availability status of the specified queries. */
	virtual void resetResults(uint32_t firstQuery, uint32_t queryCount, MVKCommandEncoder* cmdEncoder);

	/** Copies the results of the specified queries into host memory. */
	VkResult getResults(uint32_t firstQuery,
						uint32_t queryCount,
						size_t dataSize,
						void* pData,
						VkDeviceSize stride,
						VkQueryResultFlags flags);

	/** Encodes commands to copy the results of the specified queries into device memory. */
	void encodeCopyResults(MVKCommandEncoder* cmdEncoder,
						   uint32_t firstQuery,
						   uint32_t queryCount,
						   MVKBuffer* destBuffer,
						   VkDeviceSize destOffset,
						   VkDeviceSize stride,
						   VkQueryResultFlags flags);

	/**
	 * Defers a request to copy the results of the specified queries into device memory, to be
	 * encoded when all specified queries are ready.
	 */
	void deferCopyResults(uint32_t firstQuery,
						  uint32_t queryCount,
						  MVKBuffer* destBuffer,
						  VkDeviceSize destOffset,
						  VkDeviceSize stride,
						  VkQueryResultFlags flags);

    /** Called from the MVKCmdBeginQuery command when it is added to the command buffer */
    virtual void beginQueryAddedTo(uint32_t query, MVKCommandBuffer* cmdBuffer) {};

    /** Returns whether all the queries in [firstQuery, endQuery) are available on the device. */
    bool areQueriesDeviceAvailable(uint32_t firstQuery, uint32_t endQuery);

#pragma mark Construction

	MVKQueryPool(MVKDevice* device,
				 const VkQueryPoolCreateInfo* pCreateInfo,
				 const uint32_t queryElementCount) : MVKVulkanAPIDeviceObject(device),
                    _availability(pCreateInfo->queryCount, Initial),
                    _queryElementCount(queryElementCount) {}

protected:
	bool areQueriesHostAvailable(uint32_t firstQuery, uint32_t endQuery);
    VkResult getResult(uint32_t query, void* pQryData, VkQueryResultFlags flags);
	virtual void getResult(uint32_t query, void* pQryData, bool shouldOutput64Bit) {}
	virtual id<MTLBuffer> getResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, NSUInteger& offset) { return nil; }
	virtual void encodeSetResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, uint32_t index) {}

	struct DeferredCopy {
		uint32_t firstQuery;
		uint32_t queryCount;
		MVKBuffer* destBuffer;
		VkDeviceSize destOffset;
		VkDeviceSize stride;
		VkQueryResultFlags flags;
	};

	/** The possible states of a query. */
	enum Status {
		Initial,            /**< Initial state when created or reset. */
		DeviceAvailable,    /**< Query was ended and is available on the device. */
		Available           /**< Query is available to the host. */
	};

	MVKSmallVector<Status, kMVKDefaultQueryCount> _availability;
	MVKSmallVector<DeferredCopy, 4> _deferredCopies;
	uint32_t _queryElementCount;
	std::mutex _availabilityLock;
	std::condition_variable _availabilityBlocker;
	std::mutex _deferredCopiesLock;
};


#pragma mark -
#pragma mark MVKTimestampQueryPool

/** A Vulkan query pool for timestamp queries. */
class MVKTimestampQueryPool : public MVKQueryPool {
public:
    void endQuery(uint32_t query, MVKCommandEncoder* cmdEncoder) override;
    void finishQueries(const MVKArrayRef<MVKActivatedQueryInfo>& queries, const MVKTimestampCorrelationMarker& timestampCorrelationMarker, MVKTimestampBuffers* timestampBuffers) override;


#pragma mark Construction

	MVKTimestampQueryPool(MVKDevice* device, const VkQueryPoolCreateInfo* pCreateInfo);

protected:
	void propagateDebugName() override {}
	void getResult(uint32_t query, void* pQryData, bool shouldOutput64Bit) override;
	id<MTLBuffer> getResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, NSUInteger& offset) override;
	void encodeSetResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, uint32_t index) override;

	MVKSmallVector<uint64_t, kMVKDefaultQueryCount> _timestamps;
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
	void propagateDebugName() override;
    void getResult(uint32_t query, void* pQryData, bool shouldOutput64Bit) override;
	id<MTLBuffer> getResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, NSUInteger& offset) override;
	void encodeSetResultBuffer(MVKCommandEncoder* cmdEncoder, uint32_t firstQuery, uint32_t queryCount, uint32_t index) override;

    id<MTLBuffer> _visibilityResultMTLBuffer;
    uint32_t _queryIndexOffset;
};


#pragma mark -
#pragma mark MVKPipelineStatisticsQueryPool

/** A Vulkan query pool for a query pool type that tracks pipeline statistics. */
class MVKPipelineStatisticsQueryPool : public MVKQueryPool {

public:
    MVKPipelineStatisticsQueryPool(MVKDevice* device, const VkQueryPoolCreateInfo* pCreateInfo);

protected:
	void propagateDebugName() override {}
};


#pragma mark -
#pragma mark MVKUnsupportedQueryPool

/** A Vulkan query pool for a query pool type that is unsupported in Metal. */
class MVKUnsupportedQueryPool : public MVKQueryPool {

public:
	MVKUnsupportedQueryPool(MVKDevice* device, const VkQueryPoolCreateInfo* pCreateInfo);

protected:
	void propagateDebugName() override {}
};

