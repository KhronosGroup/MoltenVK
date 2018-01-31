/*
 * MVKCommandResourceFactory.mm
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

#include "MVKCommandResourceFactory.h"
#include "MVKCommandPipelineStateFactoryShaderSource.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.h"
#include "MVKLogging.h"

using namespace std;


#pragma mark -
#pragma mark MVKCommandResourceFactory

id<MTLRenderPipelineState> MVKCommandResourceFactory::newCmdBlitImageMTLRenderPipelineState(MTLPixelFormat mtlPixFmt) {
    bool isDepthFormat = mvkMTLPixelFormatIsDepthFormat(mtlPixFmt);
    string fragFuncSfx = getFragFunctionSuffix(mtlPixFmt);

    MTLRenderPipelineDescriptor* plDesc = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
    plDesc.label = [NSString stringWithFormat: @"CmdBlitImage%s-%lu", fragFuncSfx.data(), (unsigned long)mtlPixFmt];

    plDesc.vertexFunction = getFunctionNamed(isDepthFormat ? "vtxCmdBlitImageD" : "vtxCmdBlitImage");
    plDesc.fragmentFunction = getFunctionNamed((string("fragCmdBlitImage") + fragFuncSfx).data());

    if ( isDepthFormat ) {
        plDesc.depthAttachmentPixelFormat = mtlPixFmt;
    } else {
        MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[0];
        colorDesc.pixelFormat = mtlPixFmt;
    }

    MTLVertexDescriptor* vtxDesc = plDesc.vertexDescriptor;

    // Vertex attribute descriptors
    MTLVertexAttributeDescriptorArray* vaDescArray = vtxDesc.attributes;
    MTLVertexAttributeDescriptor* vaDesc;
    NSUInteger vtxBuffIdx = _device->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex);
    NSUInteger vtxStride = 0;

    // Vertex location
    vaDesc = vaDescArray[0];
    vaDesc.format = MTLVertexFormatFloat2;
    vaDesc.bufferIndex = vtxBuffIdx;
    vaDesc.offset = vtxStride;
    vtxStride += sizeof(simd::float2);

    // Vertex texture coords
    vaDesc = vaDescArray[1];
    vaDesc.format = MTLVertexFormatFloat2;
    vaDesc.bufferIndex = vtxBuffIdx;
    vaDesc.offset = vtxStride;
    vtxStride += sizeof(simd::float2);

    // Vertex attribute buffer.
    MTLVertexBufferLayoutDescriptorArray* vbDescArray = vtxDesc.layouts;
    MTLVertexBufferLayoutDescriptor* vbDesc = vbDescArray[vtxBuffIdx];
    vbDesc.stepFunction = MTLVertexStepFunctionPerVertex;
    vbDesc.stepRate = 1;
    vbDesc.stride = vtxStride;

    return newMTLRenderPipelineState(plDesc);
}

id<MTLSamplerState> MVKCommandResourceFactory::newCmdBlitImageMTLSamplerState(MTLSamplerMinMagFilter mtlFilter) {

    MTLSamplerDescriptor* sDesc = [[[MTLSamplerDescriptor alloc] init] autorelease];
    sDesc.rAddressMode = MTLSamplerAddressModeClampToZero;
    sDesc.sAddressMode = MTLSamplerAddressModeClampToZero;
    sDesc.tAddressMode = MTLSamplerAddressModeClampToZero;
    sDesc.mipFilter = MTLSamplerMipFilterNotMipmapped;
    sDesc.normalizedCoordinates = YES;
    sDesc.minFilter = mtlFilter;
    sDesc.magFilter = mtlFilter;
    return [getMTLDevice() newSamplerStateWithDescriptor: sDesc];
}

id<MTLRenderPipelineState> MVKCommandResourceFactory::newCmdClearMTLRenderPipelineState(MVKRPSKeyClearAtt& attKey) {
    string fragFuncSfx = getFragFunctionSuffix(attKey);

    MTLRenderPipelineDescriptor* plDesc = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
    plDesc.label = [NSString stringWithFormat: @"CmdClearAttachments%s", fragFuncSfx.data()];
    plDesc.vertexFunction = getFunctionNamed("vtxCmdClearAttachments");
    plDesc.fragmentFunction = getFunctionNamed((string("fragCmdClearAttachments") + fragFuncSfx).data());

    for (uint32_t caIdx = 0; caIdx < kMVKAttachmentFormatDepthStencilIndex; caIdx++) {
        MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[caIdx];
        colorDesc.pixelFormat = (MTLPixelFormat)attKey.attachmentMTLPixelFormats[caIdx];
        colorDesc.writeMask = attKey.isEnabled(caIdx) ? MTLColorWriteMaskAll : MTLColorWriteMaskNone;
    }
    MTLPixelFormat mtlDSFormat = (MTLPixelFormat)attKey.attachmentMTLPixelFormats[kMVKAttachmentFormatDepthStencilIndex];
    if (mvkMTLPixelFormatIsDepthFormat(mtlDSFormat)) { plDesc.depthAttachmentPixelFormat = mtlDSFormat; }
    if (mvkMTLPixelFormatIsStencilFormat(mtlDSFormat)) { plDesc.stencilAttachmentPixelFormat = mtlDSFormat; }

    MTLVertexDescriptor* vtxDesc = plDesc.vertexDescriptor;

    // Vertex attribute descriptors
    MTLVertexAttributeDescriptorArray* vaDescArray = vtxDesc.attributes;
    MTLVertexAttributeDescriptor* vaDesc;
    NSUInteger vtxBuffIdx = _device->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex);
    NSUInteger vtxStride = 0;

    // Vertex location
    vaDesc = vaDescArray[0];
    vaDesc.format = MTLVertexFormatFloat2;
    vaDesc.bufferIndex = vtxBuffIdx;
    vaDesc.offset = vtxStride;
    vtxStride += sizeof(simd::float2);

    // Vertex attribute buffer.
    MTLVertexBufferLayoutDescriptorArray* vbDescArray = vtxDesc.layouts;
    MTLVertexBufferLayoutDescriptor* vbDesc = vbDescArray[vtxBuffIdx];
    vbDesc.stepFunction = MTLVertexStepFunctionPerVertex;
    vbDesc.stepRate = 1;
    vbDesc.stride = vtxStride;

    return newMTLRenderPipelineState(plDesc);
}

id<MTLDepthStencilState> MVKCommandResourceFactory::newMTLDepthStencilState(bool useDepth, bool useStencil) {

	MTLDepthStencilDescriptor* dsDesc = [[[MTLDepthStencilDescriptor alloc] init] autorelease];
	dsDesc.depthCompareFunction = MTLCompareFunctionAlways;
	dsDesc.depthWriteEnabled = useDepth;

	if (useStencil) {
		MTLStencilDescriptor* sDesc = [[[MTLStencilDescriptor alloc] init] autorelease];
		sDesc.stencilCompareFunction = MTLCompareFunctionAlways;
		sDesc.stencilFailureOperation = MTLStencilOperationReplace;
		sDesc.depthFailureOperation = MTLStencilOperationReplace;
		sDesc.depthStencilPassOperation = MTLStencilOperationReplace;

		dsDesc.frontFaceStencil = sDesc;
		dsDesc.backFaceStencil = sDesc;
	} else {
		dsDesc.frontFaceStencil = nil;
		dsDesc.backFaceStencil = nil;
	}

	return [getMTLDevice() newDepthStencilStateWithDescriptor: dsDesc];
}

id<MTLDepthStencilState> MVKCommandResourceFactory::newMTLDepthStencilState(MVKMTLDepthStencilDescriptorData& dsData) {
    MTLDepthStencilDescriptor* dsDesc = [[[MTLDepthStencilDescriptor alloc] init] autorelease];
    dsDesc.depthCompareFunction = (MTLCompareFunction)dsData.depthCompareFunction;
    dsDesc.depthWriteEnabled = dsData.depthWriteEnabled;
    dsDesc.frontFaceStencil = getMTLStencilDescriptor(dsData.frontFaceStencilData);
    dsDesc.backFaceStencil = getMTLStencilDescriptor(dsData.backFaceStencilData);

    return [getMTLDevice() newDepthStencilStateWithDescriptor: dsDesc];
}

MTLStencilDescriptor* MVKCommandResourceFactory::getMTLStencilDescriptor(MVKMTLStencilDescriptorData& sData) {
    if ( !sData.enabled ) { return nil; }

    MTLStencilDescriptor* sDesc = [[[MTLStencilDescriptor alloc] init] autorelease];
    sDesc.stencilCompareFunction = (MTLCompareFunction)sData.stencilCompareFunction;
    sDesc.stencilFailureOperation = (MTLStencilOperation)sData.stencilFailureOperation;
    sDesc.depthFailureOperation = (MTLStencilOperation)sData.depthFailureOperation;
    sDesc.depthStencilPassOperation = (MTLStencilOperation)sData.depthStencilPassOperation;
    sDesc.readMask = sData.readMask;
    sDesc.writeMask = sData.writeMask;
    return sDesc;
}

MVKImage* MVKCommandResourceFactory::newMVKImage(MVKImageDescriptorData& imgData) {
    const VkImageCreateInfo createInfo = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = NULL,
        .flags = 0,
        .imageType = imgData.imageType,
        .format = imgData.format,
        .extent = imgData.extent,
        .mipLevels = imgData.mipLevels,
        .arrayLayers = imgData.arrayLayers,
        .samples = imgData.samples,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = imgData.usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = nullptr,
        .initialLayout = VK_IMAGE_LAYOUT_PREINITIALIZED
    };
    return _device->createImage(&createInfo, nullptr);
}

string MVKCommandResourceFactory::getFragFunctionSuffix(MTLPixelFormat mtlPixFmt) {
    string suffix;
    switch (mvkFormatTypeFromMTLPixelFormat(mtlPixFmt)) {
        case kMVKFormatDepthStencil:
            suffix += "DS";
        case kMVKFormatColorUInt:
            suffix += "U";
        case kMVKFormatColorInt:
            suffix += "I";
        default:
            suffix += "F";
            break;
    }

    return suffix;
}

string MVKCommandResourceFactory::getFragFunctionSuffix(MVKRPSKeyClearAtt& attKey) {
    string suffix;
    if (attKey.isEnabledOnly(0)) { suffix += "0"; }
    suffix += getFragFunctionSuffix((MTLPixelFormat)attKey.attachmentMTLPixelFormats[0]);
    return suffix;
}

id<MTLFunction> MVKCommandResourceFactory::getFunctionNamed(const char* funcName) {
    NSTimeInterval startTime = _device->getPerformanceTimestamp();
    id<MTLFunction> mtlFunc = [[_mtlLibrary newFunctionWithName: @(funcName)] autorelease];
    _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.functionRetrieval, startTime);
    return mtlFunc;
}

id<MTLRenderPipelineState> MVKCommandResourceFactory::newMTLRenderPipelineState(MTLRenderPipelineDescriptor* plDesc) {
    NSTimeInterval startTime = _device->getPerformanceTimestamp();
    NSError* err = nil;
    id<MTLRenderPipelineState> rps = [getMTLDevice() newRenderPipelineStateWithDescriptor: plDesc error: &err];    // retained
    MVKAssert( !err, "Could not create %s pipeline state: %s (code %li) %s", plDesc.label.UTF8String, err.localizedDescription.UTF8String, (long)err.code, err.localizedFailureReason.UTF8String);
    _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.pipelineCompile, startTime);
    return rps;
}

#pragma mark Construction

MVKCommandResourceFactory::MVKCommandResourceFactory(MVKDevice* device) : MVKBaseDeviceObject(device) {
	initMTLLibrary();
}

/** Initializes the Metal shaders used for command activity. */
void MVKCommandResourceFactory::initMTLLibrary() {
    NSTimeInterval startTime = _device->getPerformanceTimestamp();
    @autoreleasepool {
        MTLCompileOptions* shdrOpts = [[MTLCompileOptions new] autorelease];
        NSError* err = nil;
        _mtlLibrary = [getMTLDevice() newLibraryWithSource: @(_MVKStaticCmdShaderSource)
                                                   options: shdrOpts
                                                     error: &err];    // retained
        MVKAssert( !err, "Could not compile command shaders %s (code %li) %s", err.localizedDescription.UTF8String, (long)err.code, err.localizedFailureReason.UTF8String);
    }
    _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.mslCompile, startTime);
}

MVKCommandResourceFactory::~MVKCommandResourceFactory() {
	[_mtlLibrary release];
	_mtlLibrary = nil;
}

