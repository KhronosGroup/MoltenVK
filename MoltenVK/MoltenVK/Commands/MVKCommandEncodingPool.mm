/*
 * MVKCommandEncodingPool.mm
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

#include "MVKCommandEncodingPool.h"
#include "MVKImage.h"

using namespace std;

#pragma mark -
#pragma mark MVKCommandEncodingPool

id<MTLRenderPipelineState> MVKCommandEncodingPool::getCmdClearMTLRenderPipelineState(MVKRPSKeyClearAtt& attKey) {
	id<MTLRenderPipelineState> rps = _cmdClearMTLRenderPipelineStates[attKey];
	if ( !rps ) {
		rps = _device->getCommandResourceFactory()->newCmdClearMTLRenderPipelineState(attKey);		// retained
		_cmdClearMTLRenderPipelineStates[attKey] = rps;
	}
	return rps;
}

id<MTLRenderPipelineState> MVKCommandEncodingPool::getCmdBlitImageMTLRenderPipelineState(MTLPixelFormat mtlPixFmt) {
    id<MTLRenderPipelineState> rps = _cmdBlitImageMTLRenderPipelineStates[mtlPixFmt];
    if ( !rps ) {
        rps = _device->getCommandResourceFactory()->newCmdBlitImageMTLRenderPipelineState(mtlPixFmt);	// retained
        _cmdBlitImageMTLRenderPipelineStates[mtlPixFmt] = rps;
    }
    return rps;
}

id<MTLSamplerState> MVKCommandEncodingPool::getCmdBlitImageMTLSamplerState(MTLSamplerMinMagFilter mtlFilter) {
    switch (mtlFilter) {
        case MTLSamplerMinMagFilterNearest:
            if ( !_cmdBlitImageNearestMTLSamplerState ) {
                _cmdBlitImageNearestMTLSamplerState = _device->getCommandResourceFactory()->newCmdBlitImageMTLSamplerState(mtlFilter);	// retained
            }
            return _cmdBlitImageNearestMTLSamplerState;

        case MTLSamplerMinMagFilterLinear:
            if ( !_cmdBlitImageLinearMTLSamplerState ) {
                _cmdBlitImageLinearMTLSamplerState = _device->getCommandResourceFactory()->newCmdBlitImageMTLSamplerState(mtlFilter);		// retained
            }
            return _cmdBlitImageLinearMTLSamplerState;
    }
}

id<MTLDepthStencilState> MVKCommandEncodingPool::getMTLDepthStencilState(bool useDepth, bool useStencil) {

    if (useDepth && useStencil) {
        if ( !_cmdClearDepthAndStencilDepthStencilState ) {
            _cmdClearDepthAndStencilDepthStencilState = _device->getCommandResourceFactory()->newMTLDepthStencilState(useDepth, useStencil);  // retained
        }
        return _cmdClearDepthAndStencilDepthStencilState;
    }

    if (useDepth) {
        if ( !_cmdClearDepthOnlyDepthStencilState ) {
            _cmdClearDepthOnlyDepthStencilState = _device->getCommandResourceFactory()->newMTLDepthStencilState(useDepth, useStencil);  // retained
        }
        return _cmdClearDepthOnlyDepthStencilState;
    }

    if (useStencil) {
        if ( !_cmdClearStencilOnlyDepthStencilState ) {
            _cmdClearStencilOnlyDepthStencilState = _device->getCommandResourceFactory()->newMTLDepthStencilState(useDepth, useStencil);  // retained
        }
        return _cmdClearStencilOnlyDepthStencilState;
    }

    if ( !_cmdClearDefaultDepthStencilState ) {
        _cmdClearDefaultDepthStencilState = _device->getCommandResourceFactory()->newMTLDepthStencilState(useDepth, useStencil);  // retained
    }
    return _cmdClearDefaultDepthStencilState;
}

const MVKMTLBufferAllocation* MVKCommandEncodingPool::acquireMTLBufferAllocation(NSUInteger length) {
    return _mtlBufferAllocator.acquireMTLBufferRegion(length);
}


id<MTLDepthStencilState> MVKCommandEncodingPool::getMTLDepthStencilState(MVKMTLDepthStencilDescriptorData& dsData) {
    id<MTLDepthStencilState> dss = _mtlDepthStencilStates[dsData];
    if ( !dss ) {
        dss = _device->getCommandResourceFactory()->newMTLDepthStencilState(dsData);		// retained
        _mtlDepthStencilStates[dsData] = dss;
    }
    return dss;
}

MVKImage* MVKCommandEncodingPool::getTransferMVKImage(MVKImageDescriptorData& imgData) {
    MVKImage* mvkImg = _transferImages[imgData];
    if ( !mvkImg ) {
        mvkImg = _device->getCommandResourceFactory()->newMVKImage(imgData);
        mvkImg->bindDeviceMemory(_transferImageMemory, 0);
        _transferImages[imgData] = mvkImg;
    }
    return mvkImg;
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCopyBufferBytesComputePipelineState() {
    if (_mtlCopyBufferBytesComputePipelineState == nil) {
        _mtlCopyBufferBytesComputePipelineState = _device->getCommandResourceFactory()->newCopyBytesMTLComputePipelineState();
    }
    return _mtlCopyBufferBytesComputePipelineState;
}

#pragma mark Construction

MVKCommandEncodingPool::MVKCommandEncodingPool(MVKDevice* device) : MVKBaseDeviceObject(device),
    _mtlBufferAllocator(device, device->_pMetalFeatures->maxMTLBufferSize) {

    _cmdBlitImageLinearMTLSamplerState = nil;
    _cmdBlitImageNearestMTLSamplerState = nil;
    _cmdClearDepthAndStencilDepthStencilState = nil;
    _cmdClearDepthOnlyDepthStencilState = nil;
    _cmdClearStencilOnlyDepthStencilState = nil;
    _cmdClearDefaultDepthStencilState = nil;
    _mtlCopyBufferBytesComputePipelineState = nil;

    initTextureDeviceMemory();
}

// Initializes the empty device memory used to back temporary VkImages.
void MVKCommandEncodingPool::initTextureDeviceMemory() {
    VkMemoryAllocateInfo allocInfo = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = NULL,
        .allocationSize = 0,
        .memoryTypeIndex = _device->getVulkanMemoryTypeIndex(MTLStorageModePrivate),
    };
    _transferImageMemory = _device->allocateMemory(&allocInfo, nullptr);
}

MVKCommandEncodingPool::~MVKCommandEncodingPool() {
    if (_transferImageMemory) { _transferImageMemory->destroy(); }
	destroyMetalResources();
}

/**  Ensure all cached Metal components are released. */
void MVKCommandEncodingPool::destroyMetalResources() {
    for (auto& pair : _cmdBlitImageMTLRenderPipelineStates) { [pair.second release]; }
    _cmdBlitImageMTLRenderPipelineStates.clear();

    for (auto& pair : _cmdClearMTLRenderPipelineStates) { [pair.second release]; }
    _cmdClearMTLRenderPipelineStates.clear();

    for (auto& pair : _mtlDepthStencilStates) { [pair.second release]; }
    _mtlDepthStencilStates.clear();

    for (auto& pair : _transferImages) { pair.second->destroy(); }
    _transferImages.clear();

    [_cmdBlitImageLinearMTLSamplerState release];
    _cmdBlitImageLinearMTLSamplerState = nil;

    [_cmdBlitImageNearestMTLSamplerState release];
    _cmdBlitImageNearestMTLSamplerState = nil;

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
}

