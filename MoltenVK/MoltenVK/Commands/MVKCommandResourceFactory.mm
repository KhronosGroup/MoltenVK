/*
 * MVKCommandResourceFactory.mm
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "MVKBuffer.h"
#include "NSString+MoltenVK.h"
#include "MTLRenderPipelineDescriptor+MoltenVK.h"
#include "MVKLogging.h"

using namespace std;


#pragma mark -
#pragma mark MVKCommandResourceFactory

id<MTLRenderPipelineState> MVKCommandResourceFactory::newCmdBlitImageMTLRenderPipelineState(MVKRPSKeyBlitImg& blitKey,
																							MVKVulkanAPIDeviceObject* owner) {
	id<MTLFunction> vtxFunc = newFunctionNamed("vtxCmdBlitImage");				// temp retain
	id<MTLFunction> fragFunc = newBlitFragFunction(blitKey);					// temp retain
    MTLRenderPipelineDescriptor* plDesc = [MTLRenderPipelineDescriptor new];	// temp retain
    plDesc.label = @"CmdBlitImage";

	plDesc.vertexFunction = vtxFunc;
	plDesc.fragmentFunction = fragFunc;
	plDesc.sampleCount = blitKey.dstSampleCount;

	plDesc.colorAttachments[0].pixelFormat = blitKey.getDstMTLPixelFormat();

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

    id<MTLRenderPipelineState> rps = newMTLRenderPipelineState(plDesc, owner);

	[vtxFunc release];															// temp release
	[fragFunc release];															// temp release
	[plDesc release];															// temp release

	return rps;
}

id<MTLSamplerState> MVKCommandResourceFactory::newCmdBlitImageMTLSamplerState(MTLSamplerMinMagFilter mtlFilter) {

    MTLSamplerDescriptor* sDesc = [MTLSamplerDescriptor new];					// temp retain
    sDesc.rAddressMode = MTLSamplerAddressModeClampToZero;
    sDesc.sAddressMode = MTLSamplerAddressModeClampToZero;
    sDesc.tAddressMode = MTLSamplerAddressModeClampToZero;
    sDesc.mipFilter = MTLSamplerMipFilterNotMipmapped;
    sDesc.normalizedCoordinates = YES;
    sDesc.minFilter = mtlFilter;
    sDesc.magFilter = mtlFilter;

	id<MTLSamplerState> ss = [getMTLDevice() newSamplerStateWithDescriptor: sDesc];

	[sDesc release];															// temp release

	return ss;
}

id<MTLRenderPipelineState> MVKCommandResourceFactory::newCmdClearMTLRenderPipelineState(MVKRPSKeyClearAtt& attKey,
																						MVKVulkanAPIDeviceObject* owner) {
	id<MTLFunction> vtxFunc = newClearVertFunction(attKey);						// temp retain
	id<MTLFunction> fragFunc = newClearFragFunction(attKey);					// temp retain
	MTLRenderPipelineDescriptor* plDesc = [MTLRenderPipelineDescriptor new];	// temp retain
    plDesc.label = @"CmdClearAttachments";
	plDesc.vertexFunction = vtxFunc;
    plDesc.fragmentFunction = fragFunc;
	plDesc.sampleCount = attKey.mtlSampleCount;
	plDesc.inputPrimitiveTopologyMVK = MTLPrimitiveTopologyClassTriangle;

    for (uint32_t caIdx = 0; caIdx < kMVKClearAttachmentDepthStencilIndex; caIdx++) {
        MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[caIdx];
        colorDesc.pixelFormat = (MTLPixelFormat)attKey.attachmentMTLPixelFormats[caIdx];
        colorDesc.writeMask = attKey.isAttachmentEnabled(caIdx) ? MTLColorWriteMaskAll : MTLColorWriteMaskNone;
    }
    MTLPixelFormat mtlDSFormat = (MTLPixelFormat)attKey.attachmentMTLPixelFormats[kMVKClearAttachmentDepthStencilIndex];
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

	id<MTLRenderPipelineState> rps = newMTLRenderPipelineState(plDesc, owner);

	[vtxFunc release];															// temp release
	[fragFunc release];															// temp release
	[plDesc release];															// temp release

	return rps;
}

id<MTLFunction> MVKCommandResourceFactory::newBlitFragFunction(MVKRPSKeyBlitImg& blitKey) {
	@autoreleasepool {
		NSString* typeStr = getMTLFormatTypeString(blitKey.getSrcMTLPixelFormat());

		bool isArrayType = blitKey.isSrcArrayType();
		NSString* arraySuffix = isArrayType ? @"_array" : @"";
		NSString* sliceArg = isArrayType ? @", srcSlice" : @"";

		NSMutableString* msl = [NSMutableString stringWithCapacity: (2 * KIBI) ];
		[msl appendLineMVK: @"#include <metal_stdlib>"];
		[msl appendLineMVK: @"using namespace metal;"];
		[msl appendLineMVK];
		[msl appendLineMVK: @"typedef struct {"];
		[msl appendLineMVK: @"    float4 v_position [[position]];"];
		[msl appendLineMVK: @"    float2 v_texCoord;"];
		[msl appendLineMVK: @"} VaryingsPosTex;"];
		[msl appendLineMVK];

		NSString* funcName = @"fragBlit";
		[msl appendFormat: @"fragment %@4 %@(VaryingsPosTex varyings [[stage_in]],", typeStr, funcName];
		[msl appendLineMVK];
		[msl appendFormat: @"                         texture2d%@<%@> texture [[texture(0)]],", arraySuffix, typeStr];
		[msl appendLineMVK];
		[msl appendLineMVK: @"                         sampler sampler [[sampler(0)]],"];
		[msl appendLineMVK: @"                         constant uint& srcSlice [[buffer(0)]]) {"];
		[msl appendFormat: @"    return texture.sample(sampler, varyings.v_texCoord%@);", sliceArg];
		[msl appendLineMVK];
		[msl appendLineMVK: @"}"];

//		MVKLogDebug("\n%s", msl.UTF8String);

		return newMTLFunction(msl, funcName);
	}
}

id<MTLFunction> MVKCommandResourceFactory::newClearVertFunction(MVKRPSKeyClearAtt& attKey) {
	@autoreleasepool {
		NSMutableString* msl = [NSMutableString stringWithCapacity: (2 * KIBI) ];
		[msl appendLineMVK: @"#include <metal_stdlib>"];
		[msl appendLineMVK: @"using namespace metal;"];
		[msl appendLineMVK];
		[msl appendLineMVK: @"typedef struct {"];
		[msl appendLineMVK: @"    float4 a_position [[attribute(0)]];"];
		[msl appendLineMVK: @"} AttributesPos;"];
		[msl appendLineMVK];
		[msl appendLineMVK: @"typedef struct {"];
		[msl appendLineMVK: @"    float4 colors[9];"];
		[msl appendLineMVK: @"} ClearColorsIn;"];
		[msl appendLineMVK];
		[msl appendLineMVK: @"typedef struct {"];
		[msl appendLineMVK: @"    float4 v_position [[position]];"];
		[msl appendFormat:  @"    uint layer%s;", attKey.isLayeredRenderingEnabled() ? " [[render_target_array_index]]" : ""];
		[msl appendLineMVK: @"} VaryingsPos;"];
		[msl appendLineMVK];

		NSString* funcName = @"vertClear";
		[msl appendFormat: @"vertex VaryingsPos %@(AttributesPos attributes [[stage_in]], constant ClearColorsIn& ccIn [[buffer(0)]]) {", funcName];
		[msl appendLineMVK];
		[msl appendLineMVK: @"    VaryingsPos varyings;"];
		[msl appendLineMVK: @"    varyings.v_position = float4(attributes.a_position.x, -attributes.a_position.y, ccIn.colors[8].r, 1.0);"];
		[msl appendLineMVK: @"    varyings.layer = uint(attributes.a_position.w);"];
		[msl appendLineMVK: @"    return varyings;"];
		[msl appendLineMVK: @"}"];

//		MVKLogDebug("\n%s", msl.UTF8String);

		return newMTLFunction(msl, funcName);
	}
}

id<MTLFunction> MVKCommandResourceFactory::newClearFragFunction(MVKRPSKeyClearAtt& attKey) {
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
		for (uint32_t caIdx = 0; caIdx < kMVKClearAttachmentDepthStencilIndex; caIdx++) {
			if (attKey.isAttachmentEnabled(caIdx)) {
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
		for (uint32_t caIdx = 0; caIdx < kMVKClearAttachmentDepthStencilIndex; caIdx++) {
			if (attKey.isAttachmentEnabled(caIdx)) {
				NSString* typeStr = getMTLFormatTypeString((MTLPixelFormat)attKey.attachmentMTLPixelFormats[caIdx]);
				[msl appendFormat: @"    ccOut.color%u = %@4(ccIn.colors[%u]);", caIdx, typeStr, caIdx];
				[msl appendLineMVK];
			}
		}
		[msl appendLineMVK: @"    return ccOut;"];
		[msl appendLineMVK: @"}"];

//		MVKLogDebug("\n%s", msl.UTF8String);

		return newMTLFunction(msl, funcName);
	}
}

NSString* MVKCommandResourceFactory::getMTLFormatTypeString(MTLPixelFormat mtlPixFmt) {
	switch (mvkFormatTypeFromMTLPixelFormat(mtlPixFmt)) {
		case kMVKFormatColorHalf:		return @"half";
		case kMVKFormatColorFloat:		return @"float";
		case kMVKFormatColorInt8:
		case kMVKFormatColorInt16:		return @"short";
		case kMVKFormatColorUInt8:
		case kMVKFormatColorUInt16:		return @"ushort";
		case kMVKFormatColorInt32:		return @"int";
		case kMVKFormatColorUInt32:		return @"uint";
		default:						return @"unexpected_type";
	}
}

id<MTLDepthStencilState> MVKCommandResourceFactory::newMTLDepthStencilState(bool useDepth, bool useStencil) {

	MTLDepthStencilDescriptor* dsDesc = [MTLDepthStencilDescriptor new];	// temp retain
	dsDesc.depthCompareFunction = MTLCompareFunctionAlways;
	dsDesc.depthWriteEnabled = useDepth;

	if (useStencil) {
		MTLStencilDescriptor* sDesc = [MTLStencilDescriptor new];			// temp retain
		sDesc.stencilCompareFunction = MTLCompareFunctionAlways;
		sDesc.stencilFailureOperation = MTLStencilOperationReplace;
		sDesc.depthFailureOperation = MTLStencilOperationReplace;
		sDesc.depthStencilPassOperation = MTLStencilOperationReplace;

		dsDesc.frontFaceStencil = sDesc;
		dsDesc.backFaceStencil = sDesc;

		[sDesc release];													// temp release
	} else {
		dsDesc.frontFaceStencil = nil;
		dsDesc.backFaceStencil = nil;
	}

	id<MTLDepthStencilState> dss = [getMTLDevice() newDepthStencilStateWithDescriptor: dsDesc];

	[dsDesc release];														// temp release

	return dss;
}

id<MTLDepthStencilState> MVKCommandResourceFactory::newMTLDepthStencilState(MVKMTLDepthStencilDescriptorData& dsData) {
	MTLStencilDescriptor* fsDesc = newMTLStencilDescriptor(dsData.frontFaceStencilData);	// temp retain
	MTLStencilDescriptor* bsDesc = newMTLStencilDescriptor(dsData.backFaceStencilData);		// temp retain
	MTLDepthStencilDescriptor* dsDesc = [MTLDepthStencilDescriptor new];					// temp retain
    dsDesc.depthCompareFunction = (MTLCompareFunction)dsData.depthCompareFunction;
    dsDesc.depthWriteEnabled = dsData.depthWriteEnabled;
	dsDesc.frontFaceStencil = fsDesc;
    dsDesc.backFaceStencil = bsDesc;

	id<MTLDepthStencilState> dss = [getMTLDevice() newDepthStencilStateWithDescriptor: dsDesc];

	[fsDesc release];																		// temp release
	[bsDesc release];																		// temp release
	[dsDesc release];																		// temp release

	return dss;
}

MTLStencilDescriptor* MVKCommandResourceFactory::newMTLStencilDescriptor(MVKMTLStencilDescriptorData& sData) {
    if ( !sData.enabled ) { return nil; }

    MTLStencilDescriptor* sDesc = [MTLStencilDescriptor new];		// retained
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

MVKBuffer* MVKCommandResourceFactory::newMVKBuffer(MVKBufferDescriptorData& buffData, MVKDeviceMemory*& buffMem) {
    const VkBufferCreateInfo createInfo = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = nullptr,
        .flags = 0,
        .size = buffData.size,
        .usage = buffData.usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = nullptr,
    };
    MVKBuffer* mvkBuff = _device->createBuffer(&createInfo, nullptr);
    const VkMemoryDedicatedAllocateInfo dedicatedInfo = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO,
        .pNext = nullptr,
        .image = VK_NULL_HANDLE,
        .buffer = (VkBuffer)mvkBuff,
    };
    const VkMemoryAllocateInfo allocInfo = {
    	.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
    	.pNext = &dedicatedInfo,
    	.allocationSize = buffData.size,
    	.memoryTypeIndex = _device->getVulkanMemoryTypeIndex(MTLStorageModePrivate),
    };
    buffMem = _device->allocateMemory(&allocInfo, nullptr);
    mvkBuff->bindDeviceMemory(buffMem, 0);
    return mvkBuff;
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newCmdCopyBufferBytesMTLComputePipelineState(MVKVulkanAPIDeviceObject* owner) {
	return newMTLComputePipelineState("cmdCopyBufferBytes", owner);
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newCmdFillBufferMTLComputePipelineState(MVKVulkanAPIDeviceObject* owner) {
	return newMTLComputePipelineState("cmdFillBuffer", owner);
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newCmdCopyBufferToImage3DDecompressMTLComputePipelineState(bool needTempBuf,
																												  MVKVulkanAPIDeviceObject* owner) {
	return newMTLComputePipelineState(needTempBuf
									  ? "cmdCopyBufferToImage3DDecompressTempBufferDXTn"
									  : "cmdCopyBufferToImage3DDecompressDXTn", owner);
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newCmdDrawIndirectConvertBuffersMTLComputePipelineState(bool indexed,
																											   MVKVulkanAPIDeviceObject* owner) {
	return newMTLComputePipelineState(indexed
									  ? "cmdDrawIndexedIndirectConvertBuffers"
									  : "cmdDrawIndirectConvertBuffers", owner);
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newCmdDrawIndexedCopyIndexBufferMTLComputePipelineState(MTLIndexType type,
																											   MVKVulkanAPIDeviceObject* owner) {
	return newMTLComputePipelineState(type == MTLIndexTypeUInt16
									  ? "cmdDrawIndexedCopyIndex16Buffer"
									  : "cmdDrawIndexedCopyIndex32Buffer", owner);
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newCmdCopyQueryPoolResultsMTLComputePipelineState(MVKVulkanAPIDeviceObject* owner) {
	return newMTLComputePipelineState("cmdCopyQueryPoolResultsToBuffer", owner);
}


#pragma mark Support methods

// Returns the retained MTLFunction with the name.
// The caller is responsible for releasing the returned function object.
id<MTLFunction> MVKCommandResourceFactory::newFunctionNamed(const char* funcName) {
	uint64_t startTime = _device->getPerformanceTimestamp();
	NSString* nsFuncName = [[NSString alloc] initWithUTF8String: funcName];		// temp retained
	id<MTLFunction> mtlFunc = [_mtlLibrary newFunctionWithName: nsFuncName];	// retained
	[nsFuncName release];														// temp release
	_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.functionRetrieval, startTime);
	return mtlFunc;
}

id<MTLFunction> MVKCommandResourceFactory::newMTLFunction(NSString* mslSrcCode, NSString* funcName) {
	@autoreleasepool {
		id<MTLFunction> mtlFunc = nil;
		NSError* err = nil;

		uint64_t startTime = _device->getPerformanceTimestamp();
		id<MTLLibrary> mtlLib = [getMTLDevice() newLibraryWithSource: mslSrcCode
															 options: getDevice()->getMTLCompileOptions()
															   error: &err];	// temp retain
		_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.mslCompile, startTime);

		if (err) {
			reportError(VK_ERROR_INITIALIZATION_FAILED,
						"Could not compile support shader from MSL source (Error code %li):\n%s\n%s",
						(long)err.code, mslSrcCode.UTF8String, err.localizedDescription.UTF8String);
		} else {
			startTime = _device->getPerformanceTimestamp();
			mtlFunc = [mtlLib newFunctionWithName: funcName];
			_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.functionRetrieval, startTime);
		}

		[mtlLib release];														// temp release

		return mtlFunc;
	}
}

id<MTLRenderPipelineState> MVKCommandResourceFactory::newMTLRenderPipelineState(MTLRenderPipelineDescriptor* plDesc,
																				MVKVulkanAPIDeviceObject* owner) {
	MVKRenderPipelineCompiler* plc = new MVKRenderPipelineCompiler(owner);
	id<MTLRenderPipelineState> rps = plc->newMTLRenderPipelineState(plDesc);	// retained
	plc->destroy();
    return rps;
}

id<MTLComputePipelineState> MVKCommandResourceFactory::newMTLComputePipelineState(const char* funcName,
																				  MVKVulkanAPIDeviceObject* owner) {
	id<MTLFunction> mtlFunc = newFunctionNamed(funcName);							// temp retain
	MVKComputePipelineCompiler* plc = new MVKComputePipelineCompiler(owner);
	id<MTLComputePipelineState> cps = plc->newMTLComputePipelineState(mtlFunc);		// retained
	plc->destroy();
	[mtlFunc release];																// temp release
    return cps;
}


#pragma mark Construction

MVKCommandResourceFactory::MVKCommandResourceFactory(MVKDevice* device) : MVKBaseDeviceObject(device) {
	initMTLLibrary();
	initImageDeviceMemory();
}

// Initializes the Metal shaders used for command activity.
void MVKCommandResourceFactory::initMTLLibrary() {
    @autoreleasepool {
        NSError* err = nil;
		uint64_t startTime = _device->getPerformanceTimestamp();
        _mtlLibrary = [getMTLDevice() newLibraryWithSource: _MVKStaticCmdShaderSource
                                                   options: getDevice()->getMTLCompileOptions()
                                                     error: &err];    // retained
		MVKAssert( !err, "Could not compile command shaders (Error code %li):\n%s", (long)err.code, err.localizedDescription.UTF8String);
		_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.mslCompile, startTime);
    }
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

