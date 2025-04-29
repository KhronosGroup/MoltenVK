/*
 * MVKCommandEncodingPool.mm
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

#include "MVKCommandEncodingPool.h"
#include "MVKCommandPool.h"
#include "MVKImage.h"

using namespace std;


#pragma mark -
#pragma mark MVKCommandEncodingPool

MVKVulkanAPIObject* MVKCommandEncodingPool::getVulkanAPIObject() { return _commandPool->getVulkanAPIObject(); };


// In order to provide thread-safety with minimal performance impact, each of these access
// functions follows a 3-step pattern:
//
// 1) Retrieve resource without locking, and if it exists, return it.
// 2) If it doesn't exist, lock, then test again if it exists, and if it does, return it.
// 3) If it still does not exist, create and cache the resource, and return it.
//
// Step 1 handles the common case where the resource exists, without the expense of a lock.
// Step 2 guards against a potential race condition where two threads get past Step 1 at
// the same time, and then both barrel ahead onto Step 3.
#define MVK_ENC_REZ_ACCESS(rezAccess, rezFactoryFunc)								\
	auto rez = rezAccess;															\
	if (rez) { return rez; }														\
																					\
	lock_guard<mutex> lock(_lock);													\
	rez = rezAccess;																\
	if (rez) { return rez; }														\
																					\
	rez = _commandPool->getDevice()->getCommandResourceFactory()->rezFactoryFunc;	\
	rezAccess = rez;																\
	return rez


id<MTLRenderPipelineState> MVKCommandEncodingPool::getCmdClearMTLRenderPipelineState(MVKRPSKeyClearAtt& attKey) {
	MVK_ENC_REZ_ACCESS(_cmdClearMTLRenderPipelineStates[attKey], newCmdClearMTLRenderPipelineState(attKey, _commandPool));
}

id<MTLRenderPipelineState> MVKCommandEncodingPool::getCmdBlitImageMTLRenderPipelineState(MVKRPSKeyBlitImg& blitKey) {
	MVK_ENC_REZ_ACCESS(_cmdBlitImageMTLRenderPipelineStates[blitKey], newCmdBlitImageMTLRenderPipelineState(blitKey, _commandPool));
}

id<MTLDepthStencilState> MVKCommandEncodingPool::getMTLDepthStencilState(bool useDepth, bool useStencil) {

    if (useDepth && useStencil) {
		MVK_ENC_REZ_ACCESS(_cmdClearDepthAndStencilDepthStencilState, newMTLDepthStencilState(useDepth, useStencil));
    }

    if (useDepth) {
		MVK_ENC_REZ_ACCESS(_cmdClearDepthOnlyDepthStencilState, newMTLDepthStencilState(useDepth, useStencil));
    }

    if (useStencil) {
		MVK_ENC_REZ_ACCESS(_cmdClearStencilOnlyDepthStencilState, newMTLDepthStencilState(useDepth, useStencil));
    }

	MVK_ENC_REZ_ACCESS(_cmdClearDefaultDepthStencilState, newMTLDepthStencilState(useDepth, useStencil));
}

MVKMTLBufferAllocation* MVKCommandEncodingPool::acquireMTLBufferAllocation(NSUInteger length, bool isPrivate, bool isDedicated) {
    MVKAssert(isPrivate || !isDedicated, "Dedicated, host-shared temporary buffers are not supported."); 
    if (isDedicated) {
        return _dedicatedMtlBufferAllocator.acquireMTLBufferRegion(length);
    }
    if (isPrivate) {
        return _privateMtlBufferAllocator.acquireMTLBufferRegion(length);
    }
    return _mtlBufferAllocator.acquireMTLBufferRegion(length);
}


id<MTLDepthStencilState> MVKCommandEncodingPool::getMTLDepthStencilState(MVKMTLDepthStencilDescriptorData& dsData) {
	MVK_ENC_REZ_ACCESS(_mtlDepthStencilStates[dsData], newMTLDepthStencilState(dsData));
}

MVKImage* MVKCommandEncodingPool::getTransferMVKImage(MVKImageDescriptorData& imgData) {
	MVK_ENC_REZ_ACCESS(_transferImages[imgData], newMVKImage(imgData));
}

MVKBuffer* MVKCommandEncodingPool::getTransferMVKBuffer(MVKBufferDescriptorData& buffData) {
	MVK_ENC_REZ_ACCESS(_transferBuffers[buffData], newMVKBuffer(buffData, _transferBufferMemory[buffData]));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdCopyBufferBytesMTLComputePipelineState() {
	MVK_ENC_REZ_ACCESS(_mtlCopyBufferBytesComputePipelineState, newCmdCopyBufferBytesMTLComputePipelineState(_commandPool));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdFillBufferMTLComputePipelineState() {
	MVK_ENC_REZ_ACCESS(_mtlFillBufferComputePipelineState, newCmdFillBufferMTLComputePipelineState(_commandPool));
}

static constexpr uint32_t getRenderpassLoadStoreStateIndex(MVKFormatType type, bool isTextureArray) {
	// Kernels for array textures are stored from slot 3 onwards
	uint32_t layeredOffset = isTextureArray ? 3u : 0u;
	switch (type) {
		case kMVKFormatColorHalf:
		case kMVKFormatColorFloat:
			return 0 + layeredOffset;
		case kMVKFormatColorInt8:
		case kMVKFormatColorInt16:
		case kMVKFormatColorInt32:
			return 1 + layeredOffset;
		case kMVKFormatColorUInt8:
		case kMVKFormatColorUInt16:
		case kMVKFormatColorUInt32:
			return 2 + layeredOffset;
		default:
			return 0 + layeredOffset;
	}
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdClearColorImageMTLComputePipelineState(MVKFormatType type, bool isTextureArray) {
	MVK_ENC_REZ_ACCESS(_mtlClearColorImageComputePipelineState[getRenderpassLoadStoreStateIndex(type, isTextureArray)], newCmdClearColorImageMTLComputePipelineState(type, _commandPool, isTextureArray));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdResolveColorImageMTLComputePipelineState(MVKFormatType type, bool isTextureArray) {
	MVK_ENC_REZ_ACCESS(_mtlResolveColorImageComputePipelineState[getRenderpassLoadStoreStateIndex(type, isTextureArray)], newCmdResolveColorImageMTLComputePipelineState(type, _commandPool, isTextureArray));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdCopyBufferToImage3DDecompressMTLComputePipelineState(bool needsTempBuff) {
	MVK_ENC_REZ_ACCESS(_mtlCopyBufferToImage3DDecompressComputePipelineState[needsTempBuff ? 1 : 0], newCmdCopyBufferToImage3DDecompressMTLComputePipelineState(needsTempBuff, _commandPool));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdDrawIndirectPopulateIndexesMTLComputePipelineState() {
	MVK_ENC_REZ_ACCESS(_mtlDrawIndirectPopulateIndexesComputePipelineState, newCmdDrawIndirectPopulateIndexesMTLComputePipelineState(_commandPool));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdDrawIndirectConvertBuffersMTLComputePipelineState(bool indexed) {
	MVK_ENC_REZ_ACCESS(_mtlDrawIndirectConvertBuffersComputePipelineState[indexed ? 1 : 0], newCmdDrawIndirectConvertBuffersMTLComputePipelineState(indexed, _commandPool));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdDrawIndirectTessConvertBuffersMTLComputePipelineState(bool indexed) {
	MVK_ENC_REZ_ACCESS(_mtlDrawIndirectTessConvertBuffersComputePipelineState[indexed ? 1 : 0], newCmdDrawIndirectTessConvertBuffersMTLComputePipelineState(indexed, _commandPool));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdDrawIndexedCopyIndexBufferMTLComputePipelineState(MTLIndexType type) {
	MVK_ENC_REZ_ACCESS(_mtlDrawIndexedCopyIndexBufferComputePipelineState[type == MTLIndexTypeUInt16 ? 1 : 0], newCmdDrawIndexedCopyIndexBufferMTLComputePipelineState(type, _commandPool));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdCopyQueryPoolResultsMTLComputePipelineState() {
	MVK_ENC_REZ_ACCESS(_mtlCopyQueryPoolResultsComputePipelineState, newCmdCopyQueryPoolResultsMTLComputePipelineState(_commandPool));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getAccumulateOcclusionQueryResultsMTLComputePipelineState() {
	MVK_ENC_REZ_ACCESS(_mtlAccumOcclusionQueryResultsComputePipelineState, newAccumulateOcclusionQueryResultsMTLComputePipelineState(_commandPool));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getConvertUint8IndicesMTLComputePipelineState() {
	MVK_ENC_REZ_ACCESS(_mtlConvertUint8IndicesComputePipelineState, newConvertUint8IndicesMTLComputePipelineState(_commandPool));
}

void MVKCommandEncodingPool::clear() {
	lock_guard<mutex> lock(_lock);
	destroyMetalResources();
}


#pragma mark Construction

MVKCommandEncodingPool::MVKCommandEncodingPool(MVKCommandPool* commandPool) : _commandPool(commandPool),
    _mtlBufferAllocator(commandPool->getDevice(), commandPool->getMetalFeatures().maxMTLBufferSize, true),
    _privateMtlBufferAllocator(commandPool->getDevice(), commandPool->getMetalFeatures().maxMTLBufferSize, true, false, MTLStorageModePrivate),
    _dedicatedMtlBufferAllocator(commandPool->getDevice(), commandPool->getMetalFeatures().maxQueryBufferSize, true, true, MTLStorageModePrivate) {
}

MVKCommandEncodingPool::~MVKCommandEncodingPool() {
	destroyMetalResources();
}

/**  Ensure all cached Metal components are released. */
void MVKCommandEncodingPool::destroyMetalResources() {
	MVKDevice* mvkDev = _commandPool->getDevice();

    for (auto& pair : _cmdBlitImageMTLRenderPipelineStates) { [pair.second release]; }
    _cmdBlitImageMTLRenderPipelineStates.clear();

    for (auto& pair : _cmdClearMTLRenderPipelineStates) { [pair.second release]; }
    _cmdClearMTLRenderPipelineStates.clear();

    for (auto& pair : _mtlDepthStencilStates) { [pair.second release]; }
    _mtlDepthStencilStates.clear();

    for (auto& pair : _transferImages) { mvkDev->destroyImage(pair.second, nullptr); }
    _transferImages.clear();

    for (auto& pair : _transferBuffers) { mvkDev->destroyBuffer(pair.second, nullptr); }
    _transferBuffers.clear();

    for (auto& pair : _transferBufferMemory) { mvkDev->freeMemory(pair.second, nullptr); }
    _transferBufferMemory.clear();

    [_cmdClearDepthAndStencilDepthStencilState release];
    _cmdClearDepthAndStencilDepthStencilState = nil;

    [_cmdClearDepthOnlyDepthStencilState release];
    _cmdClearDepthOnlyDepthStencilState = nil;

    [_cmdClearStencilOnlyDepthStencilState release];
    _cmdClearStencilOnlyDepthStencilState = nil;

    [_cmdClearDefaultDepthStencilState release];
    _cmdClearDefaultDepthStencilState = nil;

    [_mtlCopyBufferBytesComputePipelineState release];
    _mtlCopyBufferBytesComputePipelineState = nil;

    [_mtlFillBufferComputePipelineState release];
    _mtlFillBufferComputePipelineState = nil;

	[_mtlDrawIndirectPopulateIndexesComputePipelineState release];
	_mtlDrawIndirectPopulateIndexesComputePipelineState = nil;

	for (uint32_t i = 0; i < kColorImageCount; i++)
	{
		[_mtlClearColorImageComputePipelineState[i] release];
		_mtlClearColorImageComputePipelineState[i] = nil;
		[_mtlResolveColorImageComputePipelineState[i] release];
		_mtlResolveColorImageComputePipelineState[i] = nil;
	}

    [_mtlCopyBufferToImage3DDecompressComputePipelineState[0] release];
    [_mtlCopyBufferToImage3DDecompressComputePipelineState[1] release];
    _mtlCopyBufferToImage3DDecompressComputePipelineState[0] = nil;
    _mtlCopyBufferToImage3DDecompressComputePipelineState[1] = nil;

    [_mtlDrawIndirectConvertBuffersComputePipelineState[0] release];
    [_mtlDrawIndirectConvertBuffersComputePipelineState[1] release];
    _mtlDrawIndirectConvertBuffersComputePipelineState[0] = nil;
    _mtlDrawIndirectConvertBuffersComputePipelineState[1] = nil;

    [_mtlDrawIndirectTessConvertBuffersComputePipelineState[0] release];
    [_mtlDrawIndirectTessConvertBuffersComputePipelineState[1] release];
    _mtlDrawIndirectTessConvertBuffersComputePipelineState[0] = nil;
    _mtlDrawIndirectTessConvertBuffersComputePipelineState[1] = nil;

    [_mtlDrawIndexedCopyIndexBufferComputePipelineState[0] release];
    [_mtlDrawIndexedCopyIndexBufferComputePipelineState[1] release];
    _mtlDrawIndexedCopyIndexBufferComputePipelineState[0] = nil;
    _mtlDrawIndexedCopyIndexBufferComputePipelineState[1] = nil;

    [_mtlCopyQueryPoolResultsComputePipelineState release];
    _mtlCopyQueryPoolResultsComputePipelineState = nil;

    [_mtlAccumOcclusionQueryResultsComputePipelineState release];
    _mtlAccumOcclusionQueryResultsComputePipelineState = nil;

    [_mtlConvertUint8IndicesComputePipelineState release];
    _mtlConvertUint8IndicesComputePipelineState = nil;
}

