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

#include "MVKEnvironment.h"
#include "MVKCommandResourceFactory.h"
#include "MVKCommandPipelineStateFactoryShaderSource.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "NSString+MoltenVK.h"
#include "MTLRenderPipelineDescriptor+MoltenVK.h"
#include "MVKLogging.h"

using namespace std;


#pragma mark -
#pragma mark MVKCommandResourceFactory

id<MTLRenderPipelineState> MVKCommandResourceFactory::newCmdBlitImageMTLRenderPipelineState(MVKRPSKeyBlitImg& blitKey) {
    MTLRenderPipelineDescriptor* plDesc = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
    plDesc.label = @"CmdBlitImage";

	plDesc.vertexFunction = getFunctionNamed("vtxCmdBlitImage");
    plDesc.fragmentFunction = getBlitFragFunction(blitKey);

	plDesc.colorAttachments[0].pixelFormat = blitKey.getMTLPixelFormat();

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
    MTLRenderPipelineDescriptor* plDesc = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
    plDesc.label = @"CmdClearAttachments";
    plDesc.vertexFunction = getFunctionNamed("vtxCmdClearAttachments");
    plDesc.fragmentFunction = getClearFragFunction(attKey);
	plDesc.sampleCount = attKey.mtlSampleCount;
#if MVK_SUPPORT_INPUT_PRIMITIVE_TOPOLOGY_BOOL
	plDesc.inputPrimitiveTopologyMVK = MTLPrimitiveTopologyClassTriangle;
#endif
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
    vaDesc.format = MTLVertexFormatFloat4;
    vaDesc.bufferIndex = vtxBuffIdx;
    vaDesc.offset = vtxStride;
    vtxStride += sizeof(simd::float4);

    // Vertex attribute buffer.
    MTLVertexBufferLayoutDescriptorArray* vbDescArray = vtxDesc.layouts;
    MTLVertexBufferLayoutDescriptor* vbDesc = vbDescArray[vtxBuffIdx];
    vbDesc.stepFunction = MTLVertexStepFunctionPerVertex;
    vbDesc.stepRate = 1;
    vbDesc.stride = vtxStride;

    return newMTLRenderPipelineState(plDesc);
}

id<MTLFunction> MVKCommandResourceFactory::getBlitFragFunction(MVKRPSKeyBlitImg& blitKey) {
	id<MTLFunction> mtlFunc = nil;

	NSString* typeStr = getMTLFormatTypeString(blitKey.getMTLPixelFormat());

	bool isArrayType = blitKey.isArrayType();
	NSString* arraySuffix = isArrayType ? @"_array" : @"";
	NSString* sliceArg = isArrayType ? @", blitInfo.srcSlice" : @"";

	@autoreleasepool {
		NSMutableString* msl = [NSMutableString stringWithCapacity: (2 * KIBI) ];
		[msl appendLineMVK: @"#include <metal_stdlib>"];
		[msl appendLineMVK: @"using namespace metal;"];
		[msl appendLineMVK];
		[msl appendLineMVK: @"typedef struct {"];
		[msl appendLineMVK: @"    float4 v_position [[position]];"];
		[msl appendLineMVK: @"    float2 v_texCoord;"];
		[msl appendLineMVK: @"} VaryingsPosTex;"];
		[msl appendLineMVK];
		if (isArrayType) {
			[msl appendLineMVK: @"typedef struct {"];
			[msl appendLineMVK: @"    uint srcLevel;"];
			[msl appendLineMVK: @"    uint srcSlice;"];
			[msl appendLineMVK: @"    uint dstLevel;"];
			[msl appendLineMVK: @"    uint dstSlice;"];
			[msl appendLineMVK: @"} BlitInfo;"];
			[msl appendLineMVK];
		}

		NSString* funcName = @"fragBlit";
		[msl appendFormat: @"fragment %@4 %@(VaryingsPosTex varyings [[stage_in]],", typeStr, funcName];
		[msl appendLineMVK];
		[msl appendFormat: @"                         texture2d%@<%@> texture [[texture(0)]],", arraySuffix, typeStr];
		[msl appendLineMVK];
		if (isArrayType) {
			[msl appendLineMVK: @"                         sampler sampler [[sampler(0)]],"];
			[msl appendLineMVK: @"                         constant BlitInfo& blitInfo [[buffer(0)]]) {"];
		} else {
			[msl appendLineMVK: @"                         sampler sampler [[sampler(0)]]) {"];
		}
		[msl appendFormat: @"    return texture.sample(sampler, varyings.v_texCoord%@);", sliceArg];
		[msl appendLineMVK];
		[msl appendLineMVK: @"}"];

		mtlFunc = newMTLFunction(msl, funcName);
//		MVKLogDebug("\n%s", msl.UTF8String);
	}
	return [mtlFunc autorelease];
}

id<MTLFunction> MVKCommandResourceFactory::getClearFragFunction(MVKRPSKeyClearAtt& attKey) {
	id<MTLFunction> mtlFunc = nil;
	@autoreleasepool {
		NSMutableString* msl = [NSMutableString stringWithCapacity: (2 * KIBI) ];
		[msl appendLineMVK: @"#include <metal_stdlib>"];
		[msl appendLineMVK: @"using namespace metal;"];
		[msl appendLineMVK];
		[msl appendLineMVK: @"typedef struct {"];
		[msl appendLineMVK: @"    float4 v_position [[position]];"];
		[msl appendLineMVK: @"} VaryingsPos;"];
		[msl appendLineMVK];
		[msl appendLineMVK: @"typedef struct {"];
		[msl appendLineMVK: @"    float4 colors[9];"];
		[msl appendLineMVK: @"} ClearColorsIn;"];
		[msl appendLineMVK];
		[msl appendLineMVK: @"typedef struct {"];
		for (uint32_t caIdx = 0; caIdx < kMVKAttachmentFormatDepthStencilIndex; caIdx++) {
			if (attKey.isEnabled(caIdx)) {
				NSString* typeStr = getMTLFormatTypeString((MTLPixelFormat)attKey.attachmentMTLPixelFormats[caIdx]);
				[msl appendFormat: @"    %@4 color%u [[color(%u)]];", typeStr, caIdx, caIdx];
				[msl appendLineMVK];
			}
		}
		[msl appendLineMVK: @"} ClearColorsOut;"];
		[msl appendLineMVK];

		NSString* funcName = @"fragClear";
		[msl appendFormat: @"fragment ClearColorsOut %@(VaryingsPos varyings [[stage_in]], constant ClearColorsIn& ccIn [[buffer(0)]]) {", funcName];
		[msl appendLineMVK];
		[msl appendLineMVK: @"    ClearColorsOut ccOut;"];
		for (uint32_t caIdx = 0; caIdx < kMVKAttachmentFormatDepthStencilIndex; caIdx++) {
			if (attKey.isEnabled(caIdx)) {
				NSString* typeStr = getMTLFormatTypeString((MTLPixelFormat)attKey.attachmentMTLPixelFormats[caIdx]);
				[msl appendFormat: @"    ccOut.color%u = %@4(ccIn.colors[%u]);", caIdx, typeStr, caIdx];
				[msl appendLineMVK];
			}
		}
		[msl appendLineMVK: @"    return ccOut;"];
		[msl appendLineMVK: @"}"];

		mtlFunc = newMTLFunction(msl, funcName);
//		MVKLogDebug("\n%s", msl.UTF8String);
	}
	return [mtlFunc autorelease];
}

NSString* MVKCommandResourceFactory::getMTLFormatTypeString(MTLPixelFormat mtlPixFmt) {
	switch (mvkFormatTypeFromMTLPixelFormat(mtlPixFmt)) {
		case kMVKFormatColorHalf:		return @"half";
		case kMVKFormatColorFloat:		return @"float";
		case kMVKFormatColorInt8:		return @"char";
		case kMVKFormatColorUInt8:		return @"uchar";
		case kMVKFormatColorInt16:		return @"short";
		case kMVKFormatColorUInt16:		return @"ushort";
		case kMVKFormatColorInt32:		return @"int";
		case kMVKFormatColorUInt32:		return @"uint";
		default:						return @"unexpected_type";
	}
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
	MVKImage* mvkImg = _device->createImage(&createInfo, nullptr);
	mvkImg->bindDeviceMemory(_transferImageMemory, 0);
	return mvkImg;
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newCmdCopyBufferBytesMTLComputePipelineState() {
	return newMTLComputePipelineState(getFunctionNamed("cmdCopyBufferBytes"));
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newCmdFillBufferMTLComputePipelineState() {
	return newMTLComputePipelineState(getFunctionNamed("cmdFillBuffer"));
}


#pragma mark Support methods

id<MTLFunction> MVKCommandResourceFactory::getFunctionNamed(const char* funcName) {
    uint64_t startTime = _device->getPerformanceTimestamp();
    id<MTLFunction> mtlFunc = [[_mtlLibrary newFunctionWithName: @(funcName)] autorelease];
    _device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.functionRetrieval, startTime);
    return mtlFunc;
}

id<MTLFunction> MVKCommandResourceFactory::newMTLFunction(NSString* mslSrcCode, NSString* funcName) {
	uint64_t startTime = _device->getPerformanceTimestamp();
	NSError* err = nil;
	id<MTLLibrary> mtlLib = [[getMTLDevice() newLibraryWithSource: mslSrcCode
														  options: getDevice()->getMTLCompileOptions()
															error: &err] autorelease];
	_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.mslCompile, startTime);
	if (err) {
		mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Could not compile support shader from MSL source:\n%s\n %s (code %li) %s", mslSrcCode.UTF8String, err.localizedDescription.UTF8String, (long)err.code, err.localizedFailureReason.UTF8String);
		return nil;
	}

	startTime = _device->getPerformanceTimestamp();
	id<MTLFunction> mtlFunc = [mtlLib newFunctionWithName: funcName];
	_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.functionRetrieval, startTime);
	return mtlFunc;
}

id<MTLRenderPipelineState> MVKCommandResourceFactory::newMTLRenderPipelineState(MTLRenderPipelineDescriptor* plDesc) {
	MVKRenderPipelineCompiler* plc = new MVKRenderPipelineCompiler(_device);
	id<MTLRenderPipelineState> rps = plc->newMTLRenderPipelineState(plDesc);	// retained
	plc->destroy();
    return rps;
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newMTLComputePipelineState(id<MTLFunction> mtlFunction) {
	MVKComputePipelineCompiler* plc = new MVKComputePipelineCompiler(_device);
	id<MTLComputePipelineState> cps = plc->newMTLComputePipelineState(mtlFunction);		// retained
	plc->destroy();
    return cps;
}


#pragma mark Construction

MVKCommandResourceFactory::MVKCommandResourceFactory(MVKDevice* device) : MVKBaseDeviceObject(device) {
	initMTLLibrary();
	initImageDeviceMemory();
}

// Initializes the Metal shaders used for command activity.
void MVKCommandResourceFactory::initMTLLibrary() {
    uint64_t startTime = _device->getPerformanceTimestamp();
    @autoreleasepool {
        NSError* err = nil;
        _mtlLibrary = [getMTLDevice() newLibraryWithSource: mvkStaticCmdShaderSource(_device)
                                                   options: getDevice()->getMTLCompileOptions()
                                                     error: &err];    // retained
        MVKAssert( !err, "Could not compile command shaders %s (code %li) %s", err.localizedDescription.UTF8String, (long)err.code, err.localizedFailureReason.UTF8String);
    }
    _device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.mslCompile, startTime);
}

// Initializes the empty device memory used to back temporary VkImages.
void MVKCommandResourceFactory::initImageDeviceMemory() {
	VkMemoryAllocateInfo allocInfo = {
		.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
		.pNext = NULL,
		.allocationSize = 0,
		.memoryTypeIndex = _device->getVulkanMemoryTypeIndex(MTLStorageModePrivate),
	};
	_transferImageMemory = _device->allocateMemory(&allocInfo, nullptr);
}

MVKCommandResourceFactory::~MVKCommandResourceFactory() {
	[_mtlLibrary release];
	_mtlLibrary = nil;
	if (_transferImageMemory) { _transferImageMemory->destroy(); }
}

