/*
 * MVKCommandEncoderState.mm
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

#include "MVKCommandEncoderState.h"
#include "MVKCommandEncodingPool.h"
#include "MVKCommandBuffer.h"
#include "MVKRenderPass.h"
#include "MVKPipeline.h"
#include "MVKQueryPool.h"

using namespace std;

#if MVK_USE_METAL_PRIVATE_API
// An extension of the MTLRenderCommandEncoder protocol to declare the setLineWidth: method.
@protocol MVKMTLRenderCommandEncoderLineWidth <MTLRenderCommandEncoder>
- (void)setLineWidth:(float)width;
@end

// An extension of the MTLRenderCommandEncoder protocol containing a declaration of the
// -setDepthBoundsTestAMD:minDepth:maxDepth: method.
@protocol MVKMTLRenderCommandEncoderDepthBoundsAMD <MTLRenderCommandEncoder>
- (void)setDepthBoundsTestAMD:(BOOL)enable minDepth:(float)minDepth maxDepth:(float)maxDepth;
@end
#endif

#pragma mark - Resource Binder Structs

struct MVKFragmentBinder {
	static SEL selSetBytes()   { return @selector(setFragmentBytes:length:atIndex:); }
	static SEL selSetBuffer()  { return @selector(setFragmentBuffer:offset:atIndex:); }
	static SEL selSetOffset()  { return @selector(setFragmentBufferOffset:atIndex:); }
	static SEL selSetTexture() { return @selector(setFragmentTexture:atIndex:); }
	static SEL selSetSampler() { return @selector(setFragmentSamplerState:atIndex:); }
	static void setBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger index) {
		[encoder setFragmentBuffer:buffer offset:offset atIndex:index];
	}
	static void setBufferOffset(id<MTLRenderCommandEncoder> encoder, NSUInteger offset, NSUInteger index) {
		[encoder setFragmentBufferOffset:offset atIndex:index];
	}
	static void setBytes(id<MTLRenderCommandEncoder> encoder, const void* bytes, NSUInteger length, NSUInteger index) {
		[encoder setFragmentBytes:bytes length:length atIndex:index];
	}
	static void setTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
		[encoder setFragmentTexture:texture atIndex:index];
	}
	static void setSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
		[encoder setFragmentSamplerState:sampler atIndex:index];
	}
};

struct MVKVertexBinder {
	static SEL selSetBytes()   { return @selector(setVertexBytes:length:atIndex:); }
	static SEL selSetBuffer()  { return @selector(setVertexBuffer:offset:atIndex:); }
	static SEL selSetOffset()  { return @selector(setVertexBufferOffset:atIndex:); }
	static SEL selSetTexture() { return @selector(setVertexTexture:atIndex:); }
	static SEL selSetSampler() { return @selector(setVertexSamplerState:atIndex:); }
#if MVK_XCODE_15
	static SEL selSetBufferDynamic() { return @selector(setVertexBuffer:offset:attributeStride:atIndex:); }
	static SEL selSetOffsetDynamic() { return @selector(setVertexBufferOffset:attributeStride:atIndex:); }
#endif
	static void setBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger index) {
		[encoder setVertexBuffer:buffer offset:offset atIndex:index];
	}
	static void setBufferOffset(id<MTLRenderCommandEncoder> encoder, NSUInteger offset, NSUInteger index) {
		[encoder setVertexBufferOffset:offset atIndex:index];
	}
	static void setBufferDynamic(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger stride, NSUInteger index) {
#if MVK_XCODE_15
		[encoder setVertexBuffer:buffer offset:offset attributeStride:stride atIndex:index];
#else
		assert(0);
#endif
	}
	static void setBufferOffsetDynamic(id<MTLRenderCommandEncoder> encoder, NSUInteger offset, NSUInteger stride, NSUInteger index) {
#if MVK_XCODE_15
		[encoder setVertexBufferOffset:offset attributeStride:stride atIndex:index];
#else
		assert(0);
#endif
	}
	static void setBytes(id<MTLRenderCommandEncoder> encoder, const void* bytes, NSUInteger length, NSUInteger index) {
		[encoder setVertexBytes:bytes length:length atIndex:index];
	}
	static void setTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
		[encoder setVertexTexture:texture atIndex:index];
	}
	static void setSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
		[encoder setVertexSamplerState:sampler atIndex:index];
	}
};

struct MVKComputeBinder {
	static SEL selSetBytes()   { return @selector(setBytes:length:atIndex:); }
	static SEL selSetBuffer()  { return @selector(setBuffer:offset:atIndex:); }
	static SEL selSetOffset()  { return @selector(setBufferOffset:atIndex:); }
	static SEL selSetTexture() { return @selector(setTexture:atIndex:); }
	static SEL selSetSampler() { return @selector(setSamplerState:atIndex:); }
#if MVK_XCODE_15
	static SEL selSetBufferDynamic() { return @selector(setBuffer:offset:attributeStride:atIndex:); }
	static SEL selSetOffsetDynamic() { return @selector(setBufferOffset:attributeStride:atIndex:); }
#endif
	static void setBuffer(id<MTLComputeCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger index) {
		[encoder setBuffer:buffer offset:offset atIndex:index];
	}
	static void setBufferOffset(id<MTLComputeCommandEncoder> encoder, NSUInteger offset, NSUInteger index) {
		[encoder setBufferOffset:offset atIndex:index];
	}
	static void setBufferDynamic(id<MTLComputeCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger stride, NSUInteger index) {
#if MVK_XCODE_15
		[encoder setBuffer:buffer offset:offset attributeStride:stride atIndex:index];
#else
		assert(0);
#endif
	}
	static void setBufferOffsetDynamic(id<MTLComputeCommandEncoder> encoder, NSUInteger offset, NSUInteger stride, NSUInteger index) {
#if MVK_XCODE_15
		[encoder setBufferOffset:offset attributeStride:stride atIndex:index];
#else
		assert(0);
#endif
	}
	static void setBytes(id<MTLComputeCommandEncoder> encoder, const void* bytes, NSUInteger length, NSUInteger index) {
		[encoder setBytes:bytes length:length atIndex:index];
	}
	static void setTexture(id<MTLComputeCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
		[encoder setTexture:texture atIndex:index];
	}
	static void setSampler(id<MTLComputeCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
		[encoder setSamplerState:sampler atIndex:index];
	}
};

template <typename T> struct ResourceBinderTable {
	T values[static_cast<uint32_t>(T::Stage::Count)];
	constexpr const T& operator[](typename T::Stage stage) const {
		assert(stage < T::Stage::Count);
		return values[static_cast<uint32_t>(stage)];
	}
	constexpr T& operator[](typename T::Stage stage) {
		assert(stage < T::Stage::Count);
		return values[static_cast<uint32_t>(stage)];
	}
};

static ResourceBinderTable<MVKResourceBinder> GenResourceBinders() {
	ResourceBinderTable<MVKResourceBinder> res = {};
	res[MVKResourceBinder::Stage::Vertex]   = MVKResourceBinder::Create<MVKVertexBinder>();
	res[MVKResourceBinder::Stage::Fragment] = MVKResourceBinder::Create<MVKFragmentBinder>();
	res[MVKResourceBinder::Stage::Compute]  = MVKResourceBinder::Create<MVKComputeBinder>();
	return res;
}

static ResourceBinderTable<MVKVertexBufferBinder> GenVertexBufferBinders() {
	ResourceBinderTable<MVKVertexBufferBinder> res = {};
	res[MVKVertexBufferBinder::Stage::Vertex]   = MVKVertexBufferBinder::Create<MVKVertexBinder>();
	res[MVKVertexBufferBinder::Stage::Compute]  = MVKVertexBufferBinder::Create<MVKComputeBinder>();
	return res;
}

const MVKResourceBinder& MVKResourceBinder::Get(Stage stage) {
	static const ResourceBinderTable<MVKResourceBinder> table = GenResourceBinders();
	return table[stage];
}

const MVKVertexBufferBinder& MVKVertexBufferBinder::Get(Stage stage) {
	static const ResourceBinderTable<MVKVertexBufferBinder> table = GenVertexBufferBinders();
	return table[stage];
}

#pragma mark - Resource Binding Functions

template <typename Binder, typename Encoder>
static void bindBuffer(Encoder encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index,
                       MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder)
{
	if (buffer) {
		if (!exists.buffers.get(index) || bindings.buffers[index].buffer != buffer) {
			exists.buffers.set(index);
			binder.setBuffer(encoder, buffer, offset, index);
			bindings.buffers[index] = { buffer, offset };
		} else if (bindings.buffers[index].offset != offset) {
			binder.setBufferOffset(encoder, offset, index);
			bindings.buffers[index].offset = offset;
		}
	} else if (exists.buffers.get(index)) {
		exists.buffers.clear(index);
		binder.setBuffer(encoder, nil, 0, index);
	}
}

template <typename Binder, typename Encoder>
static void bindBytes(Encoder encoder, const void* data, size_t size, NSUInteger index,
                      MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder)
{
	exists.buffers.set(index);
	bindings.buffers[index] = MVKStageResourceBindings::InvalidBuffer();
	binder.setBytes(encoder, data, size, index);
}

template <bool DynamicStride>
static void bindVertexBuffer(id<MTLCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, uint32_t stride, NSUInteger index,
                             MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const MVKVertexBufferBinder& binder)
{
	VkDeviceSize offsetLookup = offset;
	if (DynamicStride)
		offsetLookup ^= static_cast<VkDeviceSize>(stride ^ (1u << 31)) << 32;
	if (!exists.buffers.get(index) || bindings.buffers[index].buffer != buffer) {
		exists.buffers.set(index);
		if (DynamicStride)
			binder.setBufferDynamic(encoder, buffer, offset, stride, index);
		else
			binder.setBuffer(encoder, buffer, offset, index);
		bindings.buffers[index] = { buffer, offsetLookup };
	} else if (bindings.buffers[index].offset != offsetLookup) {
		if (DynamicStride)
			binder.setBufferOffsetDynamic(encoder, offset, stride, index);
		else
			binder.setBufferOffset(encoder, offset, index);
		bindings.buffers[index].offset = offsetLookup;
	}
}

template <typename Binder, typename Encoder>
static void bindTexture(Encoder encoder, id<MTLTexture> texture, NSUInteger index,
                        MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder)
{
	if (!exists.textures.get(index) || bindings.textures[index] != texture) {
		exists.textures.set(index);
		binder.setTexture(encoder, texture, index);
		bindings.textures[index] = texture;
	}
}

template <typename Binder, typename Encoder>
static void bindSampler(Encoder encoder, id<MTLSamplerState> sampler, NSUInteger index,
                        MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder)
{
	if (!exists.samplers.get(index) || bindings.samplers[index] != sampler) {
		exists.samplers.set(index);
		binder.setSampler(encoder, sampler, index);
		bindings.samplers[index] = sampler;
	}
}

#pragma mark - MVKVulkanGraphicsCommandEncoderState

MVKArrayRef<const MTLSamplePosition> MVKVulkanGraphicsCommandEncoderState::getSamplePositions() const {
	MVKArrayRef<const MTLSamplePosition> res;
	if (_pipeline) {
		if (pickRenderState(MVKRenderStateFlag::SampleLocationsEnable).enable.has(MVKRenderStateEnableFlag::SampleLocations)) {
			bool dynamic = _pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::SampleLocations);
			uint32_t count = (dynamic ? &_renderState : &_pipeline->getStaticStateData())->numSampleLocations;
			const MTLSamplePosition* samples = dynamic ? _sampleLocations : _pipeline->getSampleLocations();
			res = MVKArrayRef(samples, count);
		}
	}
	return res;
}

bool MVKVulkanGraphicsCommandEncoderState::isBresenhamLines() const {
	if (!_pipeline)
		return false;
	if (pickRenderState(MVKRenderStateFlag::LineRasterizationMode).lineRasterizationMode != MVKLineRasterizationMode::Bresenham)
		return false;

	switch (pickRenderState(MVKRenderStateFlag::PrimitiveTopology).primitiveType) {
		case MTLPrimitiveTypeLine:
		case MTLPrimitiveTypeLineStrip:
			return true;

		case MTLPrimitiveTypeTriangle:
		case MTLPrimitiveTypeTriangleStrip:
			return pickRenderState(MVKRenderStateFlag::PolygonMode).polygonMode == MVKPolygonMode::Lines;

		default:
			return false;
	}
}

#pragma mark - MVKMetalGraphicsCommandEncoderState

static uint32_t getSampleCount(VkSampleCountFlags vk) {
	if (vk <= VK_SAMPLE_COUNT_1_BIT)
		return 1;
	if (vk <= VK_SAMPLE_COUNT_2_BIT)
		return 2;
	if (vk <= VK_SAMPLE_COUNT_4_BIT)
		return 4;
	static_assert(kMVKMaxSampleCount == 8, "Cases need update");
	return 8;
}

void MVKMetalGraphicsCommandEncoderState::reset(VkSampleCountFlags sampleCount) {
	memset(this, 0, offsetof(MVKMetalGraphicsCommandEncoderState, MEMSET_RESET_LINE));
	_lineWidth = 1;
	_sampleCount = getSampleCount(sampleCount);
	_depthStencil.reset();
}

void MVKMetalGraphicsCommandEncoderState::bindFragmentBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index) {
	_ready.fragment().buffers.set(index, false);
	bindBuffer(encoder, buffer, offset, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindFragmentBytes(id<MTLRenderCommandEncoder> encoder, const void* data, size_t size, NSUInteger index) {
	_ready.fragment().buffers.set(index, false);
	bindBytes(encoder, data, size, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindFragmentTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
	_ready.fragment().textures.set(index, false);
	bindTexture(encoder, texture, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindFragmentSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
	_ready.fragment().samplers.set(index, false);
	bindSampler(encoder, sampler, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index) {
	_ready.vertex().buffers.set(index, false);
	bindBuffer(encoder, buffer, offset, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexBytes(id<MTLRenderCommandEncoder> encoder, const void* data, size_t size, NSUInteger index) {
	_ready.vertex().buffers.set(index, false);
	bindBytes(encoder, data, size, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
	_ready.vertex().textures.set(index, false);
	bindTexture(encoder, texture, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
	_ready.vertex().samplers.set(index, false);
	bindSampler(encoder, sampler, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}

void MVKMetalGraphicsCommandEncoderState::changePipeline(MVKGraphicsPipeline* from, MVKGraphicsPipeline* to) {
	_flags.remove(MVKMetalRenderEncoderStateFlag::PipelineReady);
	// Everything that was static is now dirty
	if (from)
		markDirty(from->getStaticStateFlags());
	if (to)
		markDirty(to->getStaticStateFlags());
}

static constexpr MVKRenderStateFlags FlagsViewportScissor {
	MVKRenderStateFlag::Viewports,
	MVKRenderStateFlag::Scissors,
};

static constexpr MVKRenderStateFlags FlagsMetalState {
	MVKRenderStateFlag::BlendConstants,
	MVKRenderStateFlag::DepthClipEnable,
	MVKRenderStateFlag::FrontFace,
	MVKRenderStateFlag::StencilReference,
#if MVK_USE_METAL_PRIVATE_API
	MVKRenderStateFlag::LineWidth,
#endif
};

static constexpr MVKRenderStateFlags FlagsHandledByBindStateData = FlagsViewportScissor | FlagsMetalState;

void MVKMetalGraphicsCommandEncoderState::bindStateData(
	id<MTLRenderCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKRenderStateData& data,
	MVKRenderStateFlags flags,
	const VkViewport* viewports,
	const VkRect2D* scissors)
{
	if (flags.hasAny(FlagsViewportScissor)) {
		if (flags.has(MVKRenderStateFlag::Viewports) &&
		    (_numViewports != data.numViewports || !mvkAreEqual(_viewports, viewports, data.numViewports)))
		{
			_numViewports = data.numViewports;
			mvkCopy(_viewports, viewports, data.numViewports);
			MTLViewport mtlViewports[kMVKMaxViewportScissorCount];
			uint32_t numViewports = data.numViewports;
			for (uint32_t i = 0; i < numViewports; i++) {
				mtlViewports[i].width = viewports[i].width;
				mtlViewports[i].height = viewports[i].height;
				mtlViewports[i].originX = viewports[i].x;
				mtlViewports[i].originY = viewports[i].y;
				mtlViewports[i].znear = viewports[i].minDepth;
				mtlViewports[i].zfar = viewports[i].maxDepth;
			}
			if (numViewports == 1) {
				[encoder setViewport:mtlViewports[0]];
			} else {
#if MVK_MACOS_OR_IOS
				[encoder setViewports:mtlViewports count:numViewports];
#endif
			}
		}
		if (flags.has(MVKRenderStateFlag::Scissors) &&
			(_numScissors != data.numScissors || !mvkAreEqual(_scissors, scissors, data.numScissors)))
		{
			if (!_flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor) || _numScissors != data.numScissors)
				_flags.add(MVKMetalRenderEncoderStateFlag::ScissorDirty);
			_numScissors = data.numScissors;
			mvkCopy(_scissors, scissors, data.numScissors);
		}
	}

	if (flags.hasAny(FlagsMetalState)) {
		if (flags.has(MVKRenderStateFlag::BlendConstants) && !mvkAreEqual(&_blendConstants, &data.blendConstants)) {
			_blendConstants = data.blendConstants;
			const float* c = data.blendConstants.float32;
			[encoder setBlendColorRed:c[0] green:c[1] blue:c[2] alpha:c[3]];
		}
		if (flags.has(MVKRenderStateFlag::DepthClipEnable)) {
			bool enable = data.enable.has(MVKRenderStateEnableFlag::DepthClamp);
			if (_flags.has(MVKMetalRenderEncoderStateFlag::DepthClampEnable) != enable) {
				_flags.flip(MVKMetalRenderEncoderStateFlag::DepthClampEnable);
				[encoder setDepthClipMode:enable ? MTLDepthClipModeClamp : MTLDepthClipModeClip];
			}
		}
		if (flags.has(MVKRenderStateFlag::FrontFace) && _frontFace != data.frontFace) {
			_frontFace = data.frontFace;
			[encoder setFrontFacingWinding:static_cast<MTLWinding>(data.frontFace)];
		}
		if (flags.has(MVKRenderStateFlag::StencilReference) && !mvkAreEqual(&_stencilReference, &data.stencilReference)) {
			_stencilReference = data.stencilReference;
			if (_stencilReference.frontFaceValue == _stencilReference.backFaceValue)
				[encoder setStencilReferenceValue:_stencilReference.frontFaceValue];
			else
				[encoder setStencilFrontReferenceValue:_stencilReference.frontFaceValue backReferenceValue:_stencilReference.backFaceValue];
		}
#if MVK_USE_METAL_PRIVATE_API
		if (flags.has(MVKRenderStateFlag::LineWidth) && _lineWidth != data.lineWidth && mvkEncoder.getMVKConfig().useMetalPrivateAPI) {
			_lineWidth = data.lineWidth;
			auto lineWidthRendEnc = static_cast<id<MVKMTLRenderCommandEncoderLineWidth>>(encoder);
			if ([lineWidthRendEnc respondsToSelector:@selector(setLineWidth:)]) {
				[lineWidthRendEnc setLineWidth:_lineWidth];
			}
		}
#endif
	}
}

void MVKMetalGraphicsCommandEncoderState::bindState(
	id<MTLRenderCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanGraphicsCommandEncoderState& vk)
{
	MVKGraphicsPipeline* pipeline = vk._pipeline;
	MVKRenderStateFlags staticStateFlags = pipeline->getStaticStateFlags();
	MVKRenderStateFlags dynamicStateFlags = pipeline->getDynamicStateFlags();
	MVKRenderStateFlags anyStateNeeded = (staticStateFlags | dynamicStateFlags).removingAll(_stateReady);
	const MVKRenderStateData& staticStateData = pipeline->getStaticStateData();
	const MVKRenderStateData& dynamicStateData = vk._renderState;
#define PICK_STATE(x) (dynamicStateFlags.has(MVKRenderStateFlag::x) ? &dynamicStateData : &staticStateData)
	// Handle anything that requires data from multiple (possibly different) sources out here

	// Polygon mode and primitive topology need to be handled specially, as we implement point mode by switching the primitive topology
	// Cull mode and discard both are specially handled only when using dynamic state
	// Whether cull mode discards is affected by whether we're rendering triangles, so do all of them at once
	static constexpr MVKRenderStateFlags FlagsWithSpecialHandling = {
		MVKRenderStateFlag::CullMode,
		MVKRenderStateFlag::PolygonMode,
		MVKRenderStateFlag::PrimitiveTopology,
		MVKRenderStateFlag::RasterizerDiscardEnable,
	};
	if (anyStateNeeded.hasAny(FlagsWithSpecialHandling)) {
		// Special handling, static can override dynamic due to Metal not supporting full dynamic topology
		_stateReady.addAll(FlagsWithSpecialHandling);
		uint8_t prim = PICK_STATE(PrimitiveTopology)->primitiveType;
		MVKPolygonMode fill = PICK_STATE(PolygonMode)->polygonMode;
		if (fill == MVKPolygonMode::Point) {
			MTLPrimitiveTopologyClass topologyClass = pipeline->getPrimitiveTopologyClass();
			if (topologyClass == MTLPrimitiveTopologyClassPoint || topologyClass == MTLPrimitiveTopologyClassUnspecified) {
				// Supported by pipeline, yay
				prim = MTLPrimitiveTypePoint;
			} else {
				// Not supported, lines are probably closer than fill
				fill = MVKPolygonMode::Lines;
				mvkEncoder.reportWarning(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdSetPolygonMode(): Metal does not support setting VK_POLYGON_MODE_POINT dynamically.");
			}
		}
		_primitiveType = prim;
		bool isTriangle = prim == MTLPrimitiveTypeTriangle || prim == MTLPrimitiveTypeTriangleStrip;
		// Fill mode only affects triangles in Metal, might as well save a few API calls
		if (isTriangle && fill != _polygonMode) {
			_polygonMode = fill;
			[encoder setTriangleFillMode:static_cast<MTLTriangleFillMode>(fill)];
		}
		// Same for cull mode
		uint8_t cull = PICK_STATE(CullMode)->cullMode;
		if (isTriangle && cull != _cullMode) {
			_cullMode = cull;
			[encoder setCullMode:static_cast<MTLCullMode>(cull)];
		}

		MVKRenderStateEnableFlags dynEnable = dynamicStateData.enable;
		bool dynRasterizationDisable = isTriangle && dynamicStateFlags.has(MVKRenderStateFlag::CullMode) && dynEnable.has(MVKRenderStateEnableFlag::CullBothFaces);
		dynRasterizationDisable |= dynamicStateFlags.has(MVKRenderStateFlag::RasterizerDiscardEnable) && dynEnable.has(MVKRenderStateEnableFlag::RasterizerDiscard);
		bool staticRasterizationDisable = pipeline->isRasterizationDisabled();

		if (dynRasterizationDisable != _flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor) && !staticRasterizationDisable) {
			_flags.flip(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor);
			_flags.add(MVKMetalRenderEncoderStateFlag::ScissorDirty);
		}
	}

	// Depth stencil has many sources that all go together into one Metal DepthStencilState
	static constexpr MVKRenderStateFlags FlagsDepthStencil {
		MVKRenderStateFlag::DepthCompareOp,
		MVKRenderStateFlag::DepthTestEnable,
		MVKRenderStateFlag::DepthWriteEnable,
		MVKRenderStateFlag::StencilCompareMask,
		MVKRenderStateFlag::StencilOp,
		MVKRenderStateFlag::StencilTestEnable,
		MVKRenderStateFlag::StencilWriteMask,
	};
	if (anyStateNeeded.hasAny(FlagsDepthStencil)) {
		_stateReady.addAll(FlagsDepthStencil);
		MVKRenderSubpass* subpass = mvkEncoder.getSubpass();
		MVKMTLDepthStencilDescriptorData desc;
		if (subpass->isStencilAttachmentUsed() && PICK_STATE(StencilTestEnable)->depthStencil.stencilTestEnabled) {
			const MVKMTLDepthStencilDescriptorData& op = PICK_STATE(StencilOp)->depthStencil;
			desc.backFaceStencilData.op = op.backFaceStencilData.op;
			desc.frontFaceStencilData.op = op.frontFaceStencilData.op;
			const MVKMTLDepthStencilDescriptorData& read = PICK_STATE(StencilCompareMask)->depthStencil;
			desc.backFaceStencilData.readMask = read.backFaceStencilData.readMask;
			desc.frontFaceStencilData.readMask = read.frontFaceStencilData.readMask;
			const MVKMTLDepthStencilDescriptorData& write = PICK_STATE(StencilWriteMask)->depthStencil;
			desc.backFaceStencilData.writeMask = write.backFaceStencilData.writeMask;
			desc.frontFaceStencilData.writeMask = write.frontFaceStencilData.writeMask;
		}
		if (subpass->isDepthAttachmentUsed() && PICK_STATE(DepthTestEnable)->enable.has(MVKRenderStateEnableFlag::DepthTest)) {
			desc.depthWriteEnabled = PICK_STATE(DepthWriteEnable)->depthStencil.depthWriteEnabled;
			desc.depthCompareFunction = PICK_STATE(DepthCompareOp)->depthStencil.depthCompareFunction;
		}
		desc.simplify(true);
		if (!mvkAreEqual(&desc, &_depthStencil)) {
			_depthStencil = desc;
			[encoder setDepthStencilState:mvkEncoder.getCommandEncodingPool()->getMTLDepthStencilState(desc)];
		}
	}

	// Flags with a separate enable flag can come from two places at once
	static constexpr MVKRenderStateFlags FlagsWithEnable {
		MVKRenderStateFlag::DepthBias,
		MVKRenderStateFlag::DepthBiasEnable,
#if MVK_USE_METAL_PRIVATE_API
		MVKRenderStateFlag::DepthBounds,
		MVKRenderStateFlag::DepthBoundsTestEnable,
#endif
	};
	if (anyStateNeeded.hasAny(FlagsWithEnable)) {
		_stateReady.addAll(anyStateNeeded & FlagsWithEnable);
		if (anyStateNeeded.hasAny({ MVKRenderStateFlag::DepthBias, MVKRenderStateFlag::DepthBiasEnable })) {
			bool wasEnabled = _flags.has(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
			if (PICK_STATE(DepthBiasEnable)->enable.has(MVKRenderStateEnableFlag::DepthBias)) {
				const MVKDepthBias& src = PICK_STATE(DepthBias)->depthBias;
				if (!wasEnabled || !mvkAreEqual(&src, &_depthBias)) {
					_flags.add(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
					_depthBias = src;
					[encoder setDepthBias:src.depthBiasConstantFactor
					           slopeScale:src.depthBiasSlopeFactor
					                clamp:src.depthBiasClamp];
				}
			} else if (wasEnabled) {
				_flags.remove(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
				[encoder setDepthBias:0 slopeScale:0 clamp:0];
			}
		}
#if MVK_USE_METAL_PRIVATE_API
		if (anyStateNeeded.hasAny({ MVKRenderStateFlag::DepthBounds, MVKRenderStateFlag::DepthBoundsTestEnable }) &&
		    mvkEncoder.getEnabledFeatures().depthBounds && mvkEncoder.getMVKConfig().useMetalPrivateAPI)
		{
			auto encoder_ = static_cast<id<MVKMTLRenderCommandEncoderDepthBoundsAMD>>(encoder);
			bool wasEnabled = _flags.has(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
			if (PICK_STATE(DepthBoundsTestEnable)->enable.has(MVKRenderStateEnableFlag::DepthBoundsTest)) {
				const MVKDepthBounds& src = PICK_STATE(DepthBounds)->depthBounds;
				if (!wasEnabled || !mvkAreEqual(&src, &_depthBounds)) {
					_flags.add(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
					_depthBounds = src;
					[encoder_ setDepthBoundsTestAMD:YES
					                       minDepth:src.minDepthBound
					                       maxDepth:src.maxDepthBound];
				}
			} else if (wasEnabled) {
				_flags.remove(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
				[encoder_ setDepthBoundsTestAMD:NO
				                       minDepth:0.0f
				                       maxDepth:1.0f];
			}
		}
#endif
	}
#undef PICK_STATE

	// For all the things that are sourced from one place, do them in two separate calls to bindStateData
	MVKRenderStateFlags handledByBindStateData = anyStateNeeded & FlagsHandledByBindStateData;
	_stateReady.addAll(handledByBindStateData);
	if (MVKRenderStateFlags neededStatic = handledByBindStateData & staticStateFlags; !neededStatic.empty()) {
		bindStateData(encoder, mvkEncoder, staticStateData, neededStatic, pipeline->getViewports(), pipeline->getScissors());
	}
	if (MVKRenderStateFlags neededDynamic = handledByBindStateData & dynamicStateFlags; !neededDynamic.empty()) {
		bindStateData(encoder, mvkEncoder, dynamicStateData, neededDynamic, vk._viewports, vk._scissors);
	}

	// Scissor can be affected by a number of things so do it at the end
	if (_flags.has(MVKMetalRenderEncoderStateFlag::ScissorDirty)) {
		_flags.remove(MVKMetalRenderEncoderStateFlag::ScissorDirty);
		MTLScissorRect mtlScissors[kMVKMaxViewportScissorCount];
		uint32_t numScissors = _numScissors;
		if (_flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor)) {
			mvkClear(mtlScissors, numScissors);
		} else {
			for (uint32_t i = 0; i < numScissors; i++)
				mtlScissors[i] = mvkMTLScissorRectFromVkRect2D(mvkEncoder.clipToRenderArea(_scissors[i]));
		}
		if (numScissors == 1) {
			[encoder setScissorRect:mtlScissors[0]];
		} else {
#if MVK_MACOS_OR_IOS
			[encoder setScissorRects:mtlScissors count:numScissors];
#endif
		}
	}
}

void MVKMetalGraphicsCommandEncoderState::prepareDraw(
	id<MTLRenderCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanGraphicsCommandEncoderState& vk)
{
	MVKGraphicsPipeline* pipeline = vk._pipeline;
	if (!pipeline->getMainPipelineState()) // Abort if pipeline could not be created.
		return;

	// Pipeline
	if (!_flags.has(MVKMetalRenderEncoderStateFlag::PipelineReady)) {
		_flags.add(MVKMetalRenderEncoderStateFlag::PipelineReady);
		id<MTLRenderPipelineState> mtlPipeline;
		const MVKRenderSubpass* subpass = mvkEncoder.getSubpass();
		if (subpass->isMultiview() && !pipeline->isTessellationPipeline()) {
			mtlPipeline = pipeline->getMultiviewPipelineState(subpass->getViewCountInMetalPass(mvkEncoder.getMultiviewPassIndex()));
		} else {
			mtlPipeline = pipeline->getMainPipelineState();
		}
		if (mtlPipeline != _pipeline) {
			_pipeline = mtlPipeline;
			[encoder setRenderPipelineState:mtlPipeline];
		}
		pipeline->encode(&mvkEncoder, kMVKGraphicsStageRasterization);
		pipeline->bindPushConstants(&mvkEncoder);
	}

	// State
	bindState(encoder, mvkEncoder, vk);
}

void MVKMetalGraphicsCommandEncoderState::prepareHelperDraw(
	id<MTLRenderCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKHelperDrawState& state)
{
	_stateReady.removeAll({
		MVKRenderStateFlag::CullMode,
		MVKRenderStateFlag::DepthBiasEnable,
		MVKRenderStateFlag::DepthBoundsTestEnable,
		MVKRenderStateFlag::DepthCompareOp,
		MVKRenderStateFlag::DepthTestEnable,
		MVKRenderStateFlag::DepthWriteEnable,
		MVKRenderStateFlag::LineWidth,
		MVKRenderStateFlag::PolygonMode,
		MVKRenderStateFlag::RasterizerDiscardEnable,
		MVKRenderStateFlag::Scissors,
		MVKRenderStateFlag::StencilCompareMask,
		MVKRenderStateFlag::StencilOp,
		MVKRenderStateFlag::StencilReference,
		MVKRenderStateFlag::StencilTestEnable,
		MVKRenderStateFlag::StencilWriteMask,
		MVKRenderStateFlag::Viewports,
	});
	_flags.removeAll({
		MVKMetalRenderEncoderStateFlag::PipelineReady,
	});
	if (_pipeline != state.pipeline) {
		_pipeline = state.pipeline;
		[encoder setRenderPipelineState:state.pipeline];
	}
	if (_cullMode != MTLCullModeNone) {
		_cullMode = MTLCullModeNone;
		[encoder setCullMode:MTLCullModeNone];
	}
	if (_flags.has(MVKMetalRenderEncoderStateFlag::DepthBiasEnable)) {
		_flags.remove(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
		[encoder setDepthBias:0 slopeScale:0 clamp:0];
	}
	if (_polygonMode != MVKPolygonMode::Fill) {
		_polygonMode = MVKPolygonMode::Fill;
		[encoder setTriangleFillMode:MTLTriangleFillModeFill];
	}
	MVKMTLDepthStencilDescriptorData ds = MVKMTLDepthStencilDescriptorData::Write(state.writeDepth, state.writeStencil);
	if (!mvkAreEqual(&_depthStencil, &ds)) {
		_depthStencil = ds;
		[encoder setDepthStencilState:mvkEncoder.getCommandEncodingPool()->getMTLDepthStencilState(state.writeDepth, state.writeStencil)];
	}
	if (state.writeStencil && (_stencilReference.backFaceValue  != state.stencilReference
	                        || _stencilReference.frontFaceValue != state.stencilReference))
	{
		_stencilReference.backFaceValue  = state.stencilReference;
		_stencilReference.frontFaceValue = state.stencilReference;
		[encoder setStencilReferenceValue:state.stencilReference];
	}
	if (_flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor)
	    || _numScissors != 1 || !mvkAreEqual(&_scissors[0], &state.viewportAndScissor))
	{
		_flags.remove(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor);
		_numScissors = 1;
		_scissors[0] = state.viewportAndScissor;
		[encoder setScissorRect:mvkMTLScissorRectFromVkRect2D(state.viewportAndScissor)];
	}
	VkViewport viewport = {
		static_cast<float>(state.viewportAndScissor.offset.x),
		static_cast<float>(state.viewportAndScissor.offset.y),
		static_cast<float>(state.viewportAndScissor.extent.width),
		static_cast<float>(state.viewportAndScissor.extent.height),
		0,
		1
	};
	if (_numViewports != 1 || !mvkAreEqual(&_viewports[0], &viewport)) {
		_numViewports = 1;
		_viewports[0] = viewport;
		[encoder setViewport:mvkMTLViewportFromVkViewport(viewport)];
	}
	[encoder setVisibilityResultMode:MTLVisibilityResultModeDisabled
	                          offset:mvkEncoder._pEncodingContext->mtlVisibilityResultOffset];
	mvkEncoder._occlusionQueryState.markDirty();
}

#pragma mark - MVKMetalComputeCommandEncoderState

void MVKMetalComputeCommandEncoderState::bindBuffer(id<MTLComputeCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index) {
	_ready.buffers.set(index, false);
	::bindBuffer(encoder, buffer, offset, index, _exists, _bindings, MVKComputeBinder());
}
void MVKMetalComputeCommandEncoderState::bindBytes(id<MTLComputeCommandEncoder> encoder, const void* data, size_t size, NSUInteger index) {
	_ready.buffers.set(index, false);
	::bindBytes(encoder, data, size, index, _exists, _bindings, MVKComputeBinder());
}
void MVKMetalComputeCommandEncoderState::bindTexture(id<MTLComputeCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
	_ready.textures.set(index, false);
	::bindTexture(encoder, texture, index, _exists, _bindings, MVKComputeBinder());
}
void MVKMetalComputeCommandEncoderState::bindSampler(id<MTLComputeCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
	_ready.samplers.set(index, false);
	::bindSampler(encoder, sampler, index, _exists, _bindings, MVKComputeBinder());
}

void MVKMetalComputeCommandEncoderState::prepareComputeDispatch(
	id<MTLComputeCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanComputeCommandEncoderState& vk)
{
	MVKComputePipeline* pipeline = vk._pipeline;
	id<MTLComputePipelineState> mtlPipeline = pipeline->getPipelineState();
	if (!mtlPipeline) // Abort if pipeline could not be created.
		return;

	_vkPipeline = pipeline;

	if (_pipeline != mtlPipeline) {
		_pipeline = mtlPipeline;
		[encoder setComputePipelineState:mtlPipeline];
		pipeline->encode(&mvkEncoder);
		pipeline->bindPushConstants(&mvkEncoder);
	}

	if (_vkStage != kMVKShaderStageCompute) {
		memset(&_ready, 0, sizeof(_ready));
		_vkStage = kMVKShaderStageCompute;
	}
}

void MVKMetalComputeCommandEncoderState::prepareRenderDispatch(
	id<MTLComputeCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanGraphicsCommandEncoderState& vk,
	MVKShaderStage stage)
{
	MVKGraphicsPipeline* pipeline = vk._pipeline;
	if (!pipeline->getMainPipelineState()) // Abort if pipeline could not be created.
		return;

	id<MTLComputePipelineState> mtlPipeline = nil;
	if (stage == kMVKShaderStageVertex) {
		if (!mvkEncoder._isIndexedDraw) {
			mtlPipeline = pipeline->getTessVertexStageState();
		} else if (vk._indexBuffer.mtlIndexType == MTLIndexTypeUInt16) {
			mtlPipeline = pipeline->getTessVertexStageIndex16State();
		} else {
			mtlPipeline = pipeline->getTessVertexStageIndex32State();
		}
	} else if (stage == kMVKShaderStageTessCtl) {
		mtlPipeline = pipeline->getTessControlStageState();
	} else {
		assert(0);
	}

	if (_vkPipeline != pipeline) {
		if (_vkStage == kMVKShaderStageVertex) {
			_ready.buffers.clearAllIn(static_cast<MVKGraphicsPipeline*>(_vkPipeline)->getMtlVertexBuffers());
		}
		_vkPipeline = pipeline;
	}

	if (_pipeline != mtlPipeline) {
		_pipeline = mtlPipeline;
		[encoder setComputePipelineState:mtlPipeline];
		pipeline->encode(&mvkEncoder, stage);
		pipeline->bindPushConstants(&mvkEncoder);
	}

	if (_vkStage != stage) {
		memset(&_ready, 0, sizeof(_ready));
		_vkStage = stage;
	}
}

void MVKMetalComputeCommandEncoderState::reset() {
	memset(this, 0, offsetof(MVKMetalComputeCommandEncoderState, MEMSET_RESET_LINE));
	_vkStage = kMVKShaderStageCount;
}

#pragma mark - MVKCommandEncoderStateNew

static constexpr MVKRenderStateFlags SampleLocationFlags {
	MVKRenderStateFlag::SampleLocations,
	MVKRenderStateFlag::SampleLocationsEnable,
};

static constexpr MTLSamplePosition kSampPosCenter = {0.5, 0.5};
static MTLSamplePosition kSamplePositionsAllCenter[] = { kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter };
static_assert(sizeof(kSamplePositionsAllCenter) / sizeof(MTLSamplePosition) == kMVKMaxSampleCount, "kSamplePositionsAllCenter is not competely populated.");

static MVKArrayRef<const MTLSamplePosition> getSamplePositions(const MVKVulkanGraphicsCommandEncoderState& vk, bool locOverride, uint32_t sampleCount) {
	if (locOverride)
		return MVKArrayRef(kSamplePositionsAllCenter, sampleCount);
	return vk.getSamplePositions();
}

MVKArrayRef<const MTLSamplePosition> MVKCommandEncoderStateNew::updateSamplePositions() {
	// Multisample Bresenham lines require sampling from the pixel center.
	bool locOverride = _mtlGraphics._sampleCount > 1 && _vkGraphics.isBresenhamLines();
	if (locOverride == _mtlGraphics._flags.has(MVKMetalRenderEncoderStateFlag::SamplePositionsOverridden) && _mtlGraphics._stateReady.hasAll(SampleLocationFlags))
		return MVKArrayRef(_mtlGraphics._samplePositions, _mtlGraphics._numSamplePositions);
	MVKArrayRef<const MTLSamplePosition> res = getSamplePositions(_vkGraphics, locOverride, _mtlGraphics._sampleCount);
	_mtlGraphics._stateReady.addAll(SampleLocationFlags);
	_mtlGraphics._flags.set(MVKMetalRenderEncoderStateFlag::SamplePositionsOverridden, locOverride);
	_mtlGraphics._numSamplePositions = res.size();
	if (res.size() > 0)
		mvkCopy(_mtlGraphics._samplePositions, res.data(), res.size());
	return res;
}

bool MVKCommandEncoderStateNew::needsMetalRenderPassRestart() {
	// Multisample Bresenham lines require sampling from the pixel center.
	bool locOverride = _mtlGraphics._sampleCount > 1 && _vkGraphics.isBresenhamLines();
	if (locOverride == _mtlGraphics._flags.has(MVKMetalRenderEncoderStateFlag::SamplePositionsOverridden) && _mtlGraphics._stateReady.hasAll(SampleLocationFlags))
		return false;
	MVKArrayRef<const MTLSamplePosition> positions = getSamplePositions(_vkGraphics, locOverride, _mtlGraphics._sampleCount);
	size_t count = positions.size();
	bool res = count != _mtlGraphics._numSamplePositions || !mvkAreEqual(positions.data(), _mtlGraphics._samplePositions, count);
	if (!res)
		_mtlGraphics._stateReady.addAll(SampleLocationFlags);
	return res;
}

void MVKCommandEncoderStateNew::bindGraphicsPipeline(MVKGraphicsPipeline* pipeline) {
	_mtlGraphics.changePipeline(_vkGraphics._pipeline, pipeline);
	_vkGraphics._pipeline = pipeline;
}

void MVKCommandEncoderStateNew::bindComputePipeline(MVKComputePipeline* pipeline) {
	_vkCompute._pipeline = pipeline;
}

void MVKCommandEncoderStateNew::bindIndexBuffer(const MVKIndexMTLBufferBinding& buffer) {
	_vkGraphics._indexBuffer = buffer;
	if (_mtlActiveEncoder == CommandEncoderClass::Compute && _mtlCompute._vkStage == kMVKShaderStageVertex)
		_mtlCompute._ready.buffers.clear(_vkGraphics._pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::IndirectParams]);
}

#pragma mark -
#pragma mark MVKCommandEncoderState

MVKVulkanAPIObject* MVKCommandEncoderState::getVulkanAPIObject() { return _cmdEncoder->getVulkanAPIObject(); };

MVKDevice* MVKCommandEncoderState::getDevice() { return _cmdEncoder->getDevice(); }


#pragma mark -
#pragma mark MVKPipelineCommandEncoderState

void MVKPipelineCommandEncoderState::bindPipeline(MVKPipeline* pipeline) {
	if (pipeline == _pipeline) { return; }

	_pipeline = pipeline;
	_pipeline->wasBound(_cmdEncoder);
	markDirty();
}

MVKPipeline* MVKPipelineCommandEncoderState::getPipeline() { return _pipeline; }

void MVKPipelineCommandEncoderState::encodeImpl(uint32_t stage) {
    if (_pipeline) {
		_pipeline->encode(_cmdEncoder, stage);
		_pipeline->bindPushConstants(_cmdEncoder);
	}
}


#pragma mark -
#pragma mark MVKPushConstantsCommandEncoderState

void MVKPushConstantsCommandEncoderState:: setPushConstants(uint32_t offset, MVKArrayRef<char> pushConstants) {
	// MSL structs can have a larger size than the equivalent C struct due to MSL alignment needs.
	// Typically any MSL struct that contains a float4 will also have a size that is rounded up to a multiple of a float4 size.
	// Ensure that we pass along enough content to cover this extra space even if it is never actually accessed by the shader.
	size_t pcSizeAlign = _cmdEncoder->getMetalFeatures().pushConstantSizeAlignment;
    size_t pcSize = pushConstants.size();
	size_t pcBuffSize = mvkAlignByteCount(offset + pcSize, pcSizeAlign);
    mvkEnsureSize(_pushConstants, pcBuffSize);
    copy(pushConstants.begin(), pushConstants.end(), _pushConstants.begin() + offset);
    if (pcBuffSize > 0) { markDirty(); }
}

void MVKPushConstantsCommandEncoderState::setMTLBufferIndex(uint32_t mtlBufferIndex, bool pipelineStageUsesPushConstants) {
	if ((mtlBufferIndex != _mtlBufferIndex) || (pipelineStageUsesPushConstants != _pipelineStageUsesPushConstants)) {
		_mtlBufferIndex = mtlBufferIndex;
		_pipelineStageUsesPushConstants = pipelineStageUsesPushConstants;
		markDirty();
	}
}

// At this point, I have been marked not-dirty, under the assumption that I will make changes to the encoder.
// However, some of the paths below decide not to actually make any changes to the encoder. In that case,
// I should remain dirty until I actually do make encoder changes.
void MVKPushConstantsCommandEncoderState::encodeImpl(uint32_t stage) {
    if ( !_pipelineStageUsesPushConstants || _pushConstants.empty() ) { return; }

	_isDirty = true;	// Stay dirty until I actually decide to make a change to the encoder

    switch (_shaderStage) {
        case VK_SHADER_STAGE_VERTEX_BIT:
			if (stage == kMVKGraphicsStageVertex) {
                _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                             _pushConstants.data(),
                                             _pushConstants.size(),
                                             _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageVertex);
				_isDirty = false;	// Okay, I changed the encoder
			} else if (!isTessellating() && stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setVertexBytes(_cmdEncoder->_mtlRenderEncoder,
                                            _pushConstants.data(),
                                            _pushConstants.size(),
                                            _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageVertex);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:
            if (stage == kMVKGraphicsStageTessControl) {
                _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                             _pushConstants.data(),
                                             _pushConstants.size(),
                                             _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageTessCtl);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:
            if (isTessellating() && stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setVertexBytes(_cmdEncoder->_mtlRenderEncoder,
                                            _pushConstants.data(),
                                            _pushConstants.size(),
                                            _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageTessEval);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_FRAGMENT_BIT:
            if (stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setFragmentBytes(_cmdEncoder->_mtlRenderEncoder,
                                              _pushConstants.data(),
                                              _pushConstants.size(),
                                              _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageFragment);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_COMPUTE_BIT:
            _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                         _pushConstants.data(),
                                         _pushConstants.size(),
                                         _mtlBufferIndex, true);
			_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageCompute);
			_isDirty = false;	// Okay, I changed the encoder
            break;
        default:
            MVKAssert(false, "Unsupported shader stage: %d", _shaderStage);
            break;
    }
}

bool MVKPushConstantsCommandEncoderState::isTessellating() {
	auto* gp = _cmdEncoder->getGraphicsPipeline();
	return gp ? gp->isTessellationPipeline() : false;
}


#pragma mark -
#pragma mark MVKResourcesCommandEncoderState

void MVKResourcesCommandEncoderState::bindDescriptorSet(uint32_t descSetIndex,
														MVKDescriptorSet* descSet,
														MVKShaderResourceBinding& dslMTLRezIdxOffsets,
														MVKArrayRef<uint32_t> dynamicOffsets,
														uint32_t& dynamicOffsetIndex) {

	bool dsChanged = (descSet != _boundDescriptorSets[descSetIndex]);

	_boundDescriptorSets[descSetIndex] = descSet;

	if (descSet->hasMetalArgumentBuffer()) {
		// If the descriptor set has changed, track new resource usage.
		if (dsChanged) {
			auto& usageDirty = _metalUsageDirtyDescriptors[descSetIndex];
			usageDirty.resize(descSet->getDescriptorCount());
			usageDirty.enableAllBits();
		}

		// Update dynamic buffer offsets
		uint32_t baseDynOfstIdx = dslMTLRezIdxOffsets.getMetalResourceIndexes().dynamicOffsetBufferIndex;
		uint32_t doCnt = descSet->getDynamicOffsetDescriptorCount();
		for (uint32_t doIdx = 0; doIdx < doCnt && dynamicOffsetIndex < dynamicOffsets.size(); doIdx++) {
			updateImplicitBuffer(_dynamicOffsets, baseDynOfstIdx + doIdx, dynamicOffsets[dynamicOffsetIndex++]);
		}

		// If something changed, mark dirty
		if (dsChanged || doCnt > 0) { MVKCommandEncoderState::markDirty(); }
	}
}

// Encode the Metal command encoder usage for each resource,
// and bind the Metal argument buffer to the command encoder.
void MVKResourcesCommandEncoderState::encodeMetalArgumentBuffer(MVKShaderStage stage) {
	if ( !_cmdEncoder->isUsingMetalArgumentBuffers() ) { return; }

	bool isUsingResidencySet = getDevice()->hasResidencySet();
	MVKPipeline* pipeline = getPipeline();
	uint32_t dsCnt = pipeline->getDescriptorSetCount();
	for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
		auto* descSet = _boundDescriptorSets[dsIdx];
		if ( !(descSet && descSet->hasMetalArgumentBuffer()) ) { continue; }

		auto* dsLayout = descSet->getLayout();
		auto& resourceUsageDirtyDescs = _metalUsageDirtyDescriptors[dsIdx];
		auto& shaderBindingUsage = pipeline->getDescriptorBindingUse(dsIdx, stage);
		bool shouldBindArgBuffToStage = false;
		
		// Iterate the bindings. If we're using a residency set, the only thing we need to determine
		// is whether to bind the Metal arg buffer for the desc set. Once we know that, we can abort fast.
		// Otherwise, we have to labouriously set the residency usage for each resource.
		uint32_t dslBindCnt = dsLayout->getBindingCount();
		for (uint32_t dslBindIdx = 0; dslBindIdx < dslBindCnt; dslBindIdx++) {
			auto* dslBind = dsLayout->getBindingAt(dslBindIdx);
			if (dslBind->getApplyToStage(stage) && shaderBindingUsage.getBit(dslBindIdx)) {
				shouldBindArgBuffToStage = true;
				if (isUsingResidencySet) break;	// Now that we know we need to bind arg buffer, we're done with this desc layout.
				uint32_t elemCnt = dslBind->getDescriptorCount(descSet->getVariableDescriptorCount());
				for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
					uint32_t descIdx = dslBind->getDescriptorIndex(elemIdx);
					if (resourceUsageDirtyDescs.getBit(descIdx, true)) {
						auto* mvkDesc = descSet->getDescriptorAt(descIdx);
						mvkDesc->encodeResourceUsage(this, dslBind, stage);
					}
				}
			}
		}
		descSet->encodeAuxBufferUsage(this, stage);


		// If it is needed, bind the Metal argument buffer itself to the command encoder,
		if (shouldBindArgBuffToStage) {
			auto& mvkArgBuff = descSet->getMetalArgumentBuffer();
			MVKMTLBufferBinding bb;
			bb.mtlBuffer = mvkArgBuff.getMetalArgumentBuffer();
			bb.offset = mvkArgBuff.getMetalArgumentBufferOffset();
			bb.index = dsIdx;
			bindMetalArgumentBuffer(stage, bb);
		}

		// For some unexpected reason, GPU capture on Xcode 12 doesn't always correctly expose
		// the contents of Metal argument buffers. Triggering an extraction of the arg buffer
		// contents here, after filling it, seems to correct that.
		// Sigh. A bug report has been filed with Apple.
		if (getDevice()->isCurrentlyAutoGPUCapturing()) { [descSet->getMetalArgumentBuffer().getMetalArgumentBuffer() contents]; }
	}
}

// Mark the resource usage as needing an update for each Metal render encoder.
void MVKResourcesCommandEncoderState::markDirty() {
	MVKCommandEncoderState::markDirty();
	if (_cmdEncoder->isUsingMetalArgumentBuffers()) {
		for (uint32_t dsIdx = 0; dsIdx < kMVKMaxDescriptorSetCount; dsIdx++) {
			_metalUsageDirtyDescriptors[dsIdx].enableAllBits();
		}
	}
}

// If a swizzle is needed for this stage, iterates all the bindings and logs errors for those that need texture swizzling.
void MVKResourcesCommandEncoderState::assertMissingSwizzles(bool needsSwizzle, const char* stageName, MVKArrayRef<const MVKMTLTextureBinding> texBindings) {
	if (needsSwizzle) {
		for (auto& tb : texBindings) {
			VkComponentMapping vkcm = mvkUnpackSwizzle(tb.swizzle);
			if (!mvkVkComponentMappingsMatch(vkcm, {VK_COMPONENT_SWIZZLE_R, VK_COMPONENT_SWIZZLE_G, VK_COMPONENT_SWIZZLE_B, VK_COMPONENT_SWIZZLE_A})) {
				MVKLogError("Pipeline does not support component swizzle (%s, %s, %s, %s) required by a VkImageView used in the %s shader."
							" Full VkImageView component swizzling will be supported by a pipeline if the MVKConfiguration::fullImageViewSwizzle"
							" config parameter or MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE environment variable was enabled when the pipeline is compiled.",
							mvkVkComponentSwizzleName(vkcm.r), mvkVkComponentSwizzleName(vkcm.g),
							mvkVkComponentSwizzleName(vkcm.b), mvkVkComponentSwizzleName(vkcm.a), stageName);
				MVKAssert(false, "See previous logged error.");
			}
		}
	}
}


#pragma mark -
#pragma mark MVKGraphicsResourcesCommandEncoderState

void MVKGraphicsResourcesCommandEncoderState::bindBuffer(MVKShaderStage stage, const MVKMTLBufferBinding& binding) {
    bind(binding, _shaderStageResourceBindings[stage].bufferBindings, _shaderStageResourceBindings[stage].areBufferBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindTexture(MVKShaderStage stage, const MVKMTLTextureBinding& binding) {
    bind(binding, _shaderStageResourceBindings[stage].textureBindings, _shaderStageResourceBindings[stage].areTextureBindingsDirty, _shaderStageResourceBindings[stage].needsSwizzle);
}

void MVKGraphicsResourcesCommandEncoderState::bindSamplerState(MVKShaderStage stage, const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _shaderStageResourceBindings[stage].samplerStateBindings, _shaderStageResourceBindings[stage].areSamplerStateBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindSwizzleBuffer(const MVKShaderImplicitRezBinding& binding,
																bool needVertexSwizzleBuffer,
																bool needTessCtlSwizzleBuffer,
																bool needTessEvalSwizzleBuffer,
																bool needFragmentSwizzleBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        _shaderStageResourceBindings[i].swizzleBufferBinding.index = binding.stages[i];
    }
    _shaderStageResourceBindings[kMVKShaderStageVertex].swizzleBufferBinding.isDirty = needVertexSwizzleBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessCtl].swizzleBufferBinding.isDirty = needTessCtlSwizzleBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessEval].swizzleBufferBinding.isDirty = needTessEvalSwizzleBuffer;
    _shaderStageResourceBindings[kMVKShaderStageFragment].swizzleBufferBinding.isDirty = needFragmentSwizzleBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::bindBufferSizeBuffer(const MVKShaderImplicitRezBinding& binding,
																   bool needVertexSizeBuffer,
																   bool needTessCtlSizeBuffer,
																   bool needTessEvalSizeBuffer,
																   bool needFragmentSizeBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        _shaderStageResourceBindings[i].bufferSizeBufferBinding.index = binding.stages[i];
    }
    _shaderStageResourceBindings[kMVKShaderStageVertex].bufferSizeBufferBinding.isDirty = needVertexSizeBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessCtl].bufferSizeBufferBinding.isDirty = needTessCtlSizeBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessEval].bufferSizeBufferBinding.isDirty = needTessEvalSizeBuffer;
    _shaderStageResourceBindings[kMVKShaderStageFragment].bufferSizeBufferBinding.isDirty = needFragmentSizeBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::bindDynamicOffsetBuffer(const MVKShaderImplicitRezBinding& binding,
																	  bool needVertexDynamicOffsetBuffer,
																	  bool needTessCtlDynamicOffsetBuffer,
																	  bool needTessEvalDynamicOffsetBuffer,
																	  bool needFragmentDynamicOffsetBuffer) {
	for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
		_shaderStageResourceBindings[i].dynamicOffsetBufferBinding.index = binding.stages[i];
	}
	_shaderStageResourceBindings[kMVKShaderStageVertex].dynamicOffsetBufferBinding.isDirty = needVertexDynamicOffsetBuffer;
	_shaderStageResourceBindings[kMVKShaderStageTessCtl].dynamicOffsetBufferBinding.isDirty = needTessCtlDynamicOffsetBuffer;
	_shaderStageResourceBindings[kMVKShaderStageTessEval].dynamicOffsetBufferBinding.isDirty = needTessEvalDynamicOffsetBuffer;
	_shaderStageResourceBindings[kMVKShaderStageFragment].dynamicOffsetBufferBinding.isDirty = needFragmentDynamicOffsetBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::bindViewRangeBuffer(const MVKShaderImplicitRezBinding& binding,
																  bool needVertexViewBuffer,
																  bool needFragmentViewBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        _shaderStageResourceBindings[i].viewRangeBufferBinding.index = binding.stages[i];
    }
    _shaderStageResourceBindings[kMVKShaderStageVertex].viewRangeBufferBinding.isDirty = needVertexViewBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessCtl].viewRangeBufferBinding.isDirty = false;
    _shaderStageResourceBindings[kMVKShaderStageTessEval].viewRangeBufferBinding.isDirty = false;
    _shaderStageResourceBindings[kMVKShaderStageFragment].viewRangeBufferBinding.isDirty = needFragmentViewBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::encodeBindings(MVKShaderStage stage,
                                                             const char* pStageName,
                                                             bool fullImageViewSwizzle,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&)> bindBuffer,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&, MVKArrayRef<const uint32_t>)> bindImplicitBuffer,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLTextureBinding&)> bindTexture,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLSamplerStateBinding&)> bindSampler) {

	encodeMetalArgumentBuffer(stage);

    auto& shaderStage = _shaderStageResourceBindings[stage];

    if (shaderStage.swizzleBufferBinding.isDirty) {

        for (auto& b : shaderStage.textureBindings) {
            if (b.isDirty) { updateImplicitBuffer(shaderStage.swizzleConstants, b.index, b.swizzle); }
        }

        bindImplicitBuffer(_cmdEncoder, shaderStage.swizzleBufferBinding, shaderStage.swizzleConstants.contents());

    } else {
        assertMissingSwizzles(shaderStage.needsSwizzle && !fullImageViewSwizzle, pStageName, shaderStage.textureBindings.contents());
    }

    if (shaderStage.bufferSizeBufferBinding.isDirty) {
        for (auto& b : shaderStage.bufferBindings) {
            if (b.isDirty) { updateImplicitBuffer(shaderStage.bufferSizes, b.index, b.size); }
        }

        bindImplicitBuffer(_cmdEncoder, shaderStage.bufferSizeBufferBinding, shaderStage.bufferSizes.contents());
    }

	if (shaderStage.dynamicOffsetBufferBinding.isDirty) {
		bindImplicitBuffer(_cmdEncoder, shaderStage.dynamicOffsetBufferBinding, _dynamicOffsets.contents());
	}

    if (shaderStage.viewRangeBufferBinding.isDirty) {
        MVKSmallVector<uint32_t, 2> viewRange;
        viewRange.push_back(_cmdEncoder->getSubpass()->getFirstViewIndexInMetalPass(_cmdEncoder->getMultiviewPassIndex()));
        viewRange.push_back(_cmdEncoder->getSubpass()->getViewCountInMetalPass(_cmdEncoder->getMultiviewPassIndex()));
        bindImplicitBuffer(_cmdEncoder, shaderStage.viewRangeBufferBinding, viewRange.contents());
    }

	bool wereBufferBindingsDirty = shaderStage.areBufferBindingsDirty;
    encodeBinding<MVKMTLBufferBinding>(shaderStage.bufferBindings, shaderStage.areBufferBindingsDirty, bindBuffer);
    encodeBinding<MVKMTLTextureBinding>(shaderStage.textureBindings, shaderStage.areTextureBindingsDirty, bindTexture);
    encodeBinding<MVKMTLSamplerStateBinding>(shaderStage.samplerStateBindings, shaderStage.areSamplerStateBindingsDirty, bindSampler);

	// If any buffers have been bound, mark the GPU addressable buffers as needed.
	if (wereBufferBindingsDirty && !shaderStage.areBufferBindingsDirty ) {
		_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(MVKShaderStage(stage));
	}
}

void MVKGraphicsResourcesCommandEncoderState::offsetZeroDivisorVertexBuffers(MVKGraphicsStage stage,
                                                                             MVKGraphicsPipeline* pipeline,
                                                                             uint32_t firstInstance) {
    auto& shaderStage = _shaderStageResourceBindings[kMVKShaderStageVertex];
    for (auto& binding : pipeline->getZeroDivisorVertexBindings()) {
        uint32_t mtlBuffIdx = pipeline->getMetalBufferIndexForVertexAttributeBinding(binding.first);
        auto iter = std::find_if(shaderStage.bufferBindings.begin(), shaderStage.bufferBindings.end(), [mtlBuffIdx](const MVKMTLBufferBinding& b) { return b.index == mtlBuffIdx; });
		if (!iter) { continue; }
        switch (stage) {
            case kMVKGraphicsStageVertex:
                [_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBufferOffset: iter->offset + firstInstance * binding.second
                                                                                                    atIndex: mtlBuffIdx];
                break;
            case kMVKGraphicsStageRasterization:
                [_cmdEncoder->_mtlRenderEncoder setVertexBufferOffset: iter->offset + firstInstance * binding.second
                                                              atIndex: mtlBuffIdx];
                break;
            default:
                assert(false);      // If we hit this, something went wrong.
                break;
        }
    }
}

void MVKGraphicsResourcesCommandEncoderState::endMetalRenderPass() {
	MVKResourcesCommandEncoderState::endMetalRenderPass();
	_renderUsageStages.clear();
}

// Mark everything as dirty
void MVKGraphicsResourcesCommandEncoderState::markDirty() {
	MVKResourcesCommandEncoderState::markDirty();
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].bufferBindings, _shaderStageResourceBindings[i].areBufferBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].textureBindings, _shaderStageResourceBindings[i].areTextureBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].samplerStateBindings, _shaderStageResourceBindings[i].areSamplerStateBindingsDirty);
    }
}

void MVKGraphicsResourcesCommandEncoderState::encodeImpl(uint32_t stage) {

	auto* pipeline = _cmdEncoder->getGraphicsPipeline();
    bool fullImageViewSwizzle = pipeline->fullImageViewSwizzle() || _cmdEncoder->getMetalFeatures().nativeTextureSwizzle;
    bool forTessellation = pipeline->isTessellationPipeline();
	bool isDynamicVertexStride = pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::VertexStride) && _cmdEncoder->getMetalFeatures().dynamicVertexStride;

	if (stage == kMVKGraphicsStageVertex) {
        encodeBindings(kMVKShaderStageVertex, "vertex", fullImageViewSwizzle,
                       [isDynamicVertexStride](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           if (isDynamicVertexStride) {
#if MVK_XCODE_15
                               if (b.isInline)
                                   cmdEncoder->setComputeBytesWithStride(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                                         b.mtlBytes,
                                                                         b.size,
                                                                         b.index,
                                                                         b.stride);
                               else if (b.justOffset)
                                   [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl)
                                                setBufferOffset: b.offset
                                                attributeStride: b.stride
                                                atIndex: b.index];
                               else
                                   [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl)
                                                setBuffer: b.mtlBuffer
                                                   offset: b.offset
                                          attributeStride: b.stride
                                                  atIndex: b.index];
#endif
                           } else {
                               if (b.isInline)
                                   cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                               b.mtlBytes,
                                                               b.size,
                                                               b.index);
                               else if (b.justOffset)
                                   [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl)
                                                setBufferOffset: b.offset
                                                atIndex: b.index];
                               else
                                   [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl)
                                                setBuffer: b.mtlBuffer
                                                   offset: b.offset
                                                  atIndex: b.index];
                           }
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                       s.data(),
                                                       s.byteSize(),
                                                       b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setTexture: b.mtlTexture
                                                                                                         atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setSamplerState: b.mtlSamplerState
                                                                                                              atIndex: b.index];
                       });

	} else if (!forTessellation && stage == kMVKGraphicsStageRasterization) {
        auto& shaderStage = _shaderStageResourceBindings[kMVKShaderStageVertex];
        encodeBindings(kMVKShaderStageVertex, "vertex", fullImageViewSwizzle,
					   [pipeline, isDynamicVertexStride](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           // The app may have bound more vertex attribute buffers than used by the pipeline.
                           // We must not bind those extra buffers to the shader because they might overwrite
                           // any implicit buffers used by the pipeline.
                           if (pipeline->isValidVertexBufferIndex(kMVKShaderStageVertex, b.index)) {
                               cmdEncoder->encodeVertexAttributeBuffer(b, isDynamicVertexStride);

							   // Add any translated vertex bindings for this binding
							   if ( !b.isInline ) {
                                   auto xltdVtxBindings = pipeline->getTranslatedVertexBindings();
                                   for (auto& xltdBind : xltdVtxBindings) {
                                       if (b.index == pipeline->getMetalBufferIndexForVertexAttributeBinding(xltdBind.binding)) {
                                           MVKMTLBufferBinding bx = { 
                                               .mtlBuffer = b.mtlBuffer,
                                               .offset = b.offset + xltdBind.translationOffset,
                                               .stride = b.stride,
											   .index = static_cast<uint16_t>(pipeline->getMetalBufferIndexForVertexAttributeBinding(xltdBind.translationBinding)) };
										   cmdEncoder->encodeVertexAttributeBuffer(bx, isDynamicVertexStride);
                                       }
                                   }
                               }
                           } else {
                               b.isDirty = true;	// We haven't written it out, so leave dirty until next time.
						   }
                       },
                       [&shaderStage](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                      s.data(),
                                                      s.byteSize(),
                                                      b.index);
                           for (auto& bufb : shaderStage.bufferBindings) {
                               if (bufb.index == b.index) {
                                   // Vertex attribute occupying the same index should be marked dirty
                                   // so it will be updated when enabled
                                   bufb.markDirty();
                               }
                           }
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexTexture: b.mtlTexture
                                                                   atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexSamplerState: b.mtlSamplerState
                                                                        atIndex: b.index];
                       });

    }

    if (stage == kMVKGraphicsStageTessControl) {
        encodeBindings(kMVKShaderStageTessCtl, "tessellation control", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           if (b.isInline)
                               cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                           b.mtlBytes,
                                                           b.size,
                                                           b.index);
                           else if (b.justOffset)
                               [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBufferOffset: b.offset
                                                                                                                  atIndex: b.index];
                           else
                               [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBuffer: b.mtlBuffer
                                                                                                             offset: b.offset
                                                                                                            atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                       s.data(),
                                                       s.byteSize(),
                                                       b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setTexture: b.mtlTexture
                                                                                                         atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setSamplerState: b.mtlSamplerState
                                                                                                              atIndex: b.index];
                       });

    }

    if (forTessellation && stage == kMVKGraphicsStageRasterization) {
        encodeBindings(kMVKShaderStageTessEval, "tessellation evaluation", fullImageViewSwizzle,
					   [isDynamicVertexStride](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           cmdEncoder->encodeVertexAttributeBuffer(b, isDynamicVertexStride);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                      s.data(),
                                                      s.byteSize(),
                                                      b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexTexture: b.mtlTexture
                                                                   atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexSamplerState: b.mtlSamplerState
                                                                        atIndex: b.index];
                       });

    }

    if (stage == kMVKGraphicsStageRasterization) {
        encodeBindings(kMVKShaderStageFragment, "fragment", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           if (b.isInline)
                               cmdEncoder->setFragmentBytes(cmdEncoder->_mtlRenderEncoder,
                                                            b.mtlBytes,
                                                            b.size,
                                                            b.index);
                           else if (b.justOffset)
                               [cmdEncoder->_mtlRenderEncoder setFragmentBufferOffset: b.offset
                                                                              atIndex: b.index];
                           else
                               [cmdEncoder->_mtlRenderEncoder setFragmentBuffer: b.mtlBuffer
                                                                         offset: b.offset
                                                                        atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setFragmentBytes(cmdEncoder->_mtlRenderEncoder,
                                                        s.data(),
                                                        s.byteSize(),
                                                        b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setFragmentTexture: b.mtlTexture
                                                                     atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setFragmentSamplerState: b.mtlSamplerState
                                                                          atIndex: b.index];
                       });
    }
}

MVKPipeline* MVKGraphicsResourcesCommandEncoderState::getPipeline() {
	return _cmdEncoder->getVkGraphics()._pipeline;
}

void MVKGraphicsResourcesCommandEncoderState::bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) {
	bindBuffer(stage, buffBind);
}

void MVKGraphicsResourcesCommandEncoderState::encodeResourceUsage(MVKShaderStage stage,
																  id<MTLResource> mtlResource,
																  MTLResourceUsage mtlUsage,
																  MTLRenderStages mtlStages) {
	if (mtlResource && mtlStages) {
		if (stage == kMVKShaderStageTessCtl) {
			auto* mtlCompEnc = _cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
			[mtlCompEnc useResource: mtlResource usage: mtlUsage];
		} else {
			auto* mtlRendEnc = _cmdEncoder->_mtlRenderEncoder;
			if ([mtlRendEnc respondsToSelector: @selector(useResource:usage:stages:)]) {
				// Within a renderpass, a resource may be used by multiple descriptor bindings,
				// each of which may assign a different usage stage. Dynamically accumulate
				// usage stages across all descriptor bindings using the resource.
				auto& accumStages = _renderUsageStages[mtlResource];
				accumStages |= mtlStages;
				[mtlRendEnc useResource: mtlResource usage: mtlUsage stages: accumStages];
			} else {
				[mtlRendEnc useResource: mtlResource usage: mtlUsage];
			}
		}
	}
}

void MVKGraphicsResourcesCommandEncoderState::markBufferIndexOverridden(MVKShaderStage stage, uint32_t mtlBufferIndex) {
	auto& stageRezBinds = _shaderStageResourceBindings[stage];
	MVKResourcesCommandEncoderState::markBufferIndexOverridden(stageRezBinds.bufferBindings, mtlBufferIndex);
}

void MVKGraphicsResourcesCommandEncoderState::markOverriddenBufferIndexesDirty() {
	for (auto& stageRezBinds : _shaderStageResourceBindings) {
		MVKResourcesCommandEncoderState::markOverriddenBufferIndexesDirty(stageRezBinds.bufferBindings, stageRezBinds.areBufferBindingsDirty);
	}
}


#pragma mark -
#pragma mark MVKComputeResourcesCommandEncoderState

void MVKComputeResourcesCommandEncoderState::bindBuffer(const MVKMTLBufferBinding& binding) {
	bind(binding, _resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindTexture(const MVKMTLTextureBinding& binding) {
    bind(binding, _resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty, _resourceBindings.needsSwizzle);
}

void MVKComputeResourcesCommandEncoderState::bindSamplerState(const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindSwizzleBuffer(const MVKShaderImplicitRezBinding& binding,
															   bool needSwizzleBuffer) {
    _resourceBindings.swizzleBufferBinding.index = binding.stages[kMVKShaderStageCompute];
    _resourceBindings.swizzleBufferBinding.isDirty = needSwizzleBuffer;
}

void MVKComputeResourcesCommandEncoderState::bindBufferSizeBuffer(const MVKShaderImplicitRezBinding& binding,
																  bool needBufferSizeBuffer) {
    _resourceBindings.bufferSizeBufferBinding.index = binding.stages[kMVKShaderStageCompute];
    _resourceBindings.bufferSizeBufferBinding.isDirty = needBufferSizeBuffer;
}

void MVKComputeResourcesCommandEncoderState::bindDynamicOffsetBuffer(const MVKShaderImplicitRezBinding& binding,
																	 bool needDynamicOffsetBuffer) {
	_resourceBindings.dynamicOffsetBufferBinding.index = binding.stages[kMVKShaderStageCompute];
	_resourceBindings.dynamicOffsetBufferBinding.isDirty = needDynamicOffsetBuffer;
}

// Mark everything as dirty
void MVKComputeResourcesCommandEncoderState::markDirty() {
    MVKResourcesCommandEncoderState::markDirty();
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::encodeImpl(uint32_t) {

	encodeMetalArgumentBuffer(kMVKShaderStageCompute);

    if (_resourceBindings.swizzleBufferBinding.isDirty) {
		for (auto& b : _resourceBindings.textureBindings) {
			if (b.isDirty) { updateImplicitBuffer(_resourceBindings.swizzleConstants, b.index, b.swizzle); }
		}

		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                     _resourceBindings.swizzleConstants.data(),
                                     _resourceBindings.swizzleConstants.size() * sizeof(uint32_t),
                                     _resourceBindings.swizzleBufferBinding.index);

	} else {
		MVKPipeline* pipeline = getPipeline();
		bool fullImageViewSwizzle = pipeline ? pipeline->fullImageViewSwizzle() : false;
		assertMissingSwizzles(_resourceBindings.needsSwizzle && !fullImageViewSwizzle, "compute", _resourceBindings.textureBindings.contents());
    }

    if (_resourceBindings.bufferSizeBufferBinding.isDirty) {
		for (auto& b : _resourceBindings.bufferBindings) {
			if (b.isDirty) { updateImplicitBuffer(_resourceBindings.bufferSizes, b.index, b.size); }
		}

		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                     _resourceBindings.bufferSizes.data(),
                                     _resourceBindings.bufferSizes.size() * sizeof(uint32_t),
                                     _resourceBindings.bufferSizeBufferBinding.index);

    }

	if (_resourceBindings.dynamicOffsetBufferBinding.isDirty) {
		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
									 _dynamicOffsets.data(),
									 _dynamicOffsets.size() * sizeof(uint32_t),
									 _resourceBindings.dynamicOffsetBufferBinding.index);

	}

	bool wereBufferBindingsDirty = _resourceBindings.areBufferBindingsDirty;
	encodeBinding<MVKMTLBufferBinding>(_resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty,
									   [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
		if (b.isInline) {
			cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
										b.mtlBytes,
										b.size,
										b.index);
        } else if (b.justOffset) {
            [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch)
                        setBufferOffset: b.offset
                                atIndex: b.index];

        } else {
			[cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setBuffer: b.mtlBuffer
																		 offset: b.offset
																		atIndex: b.index];
		}
	});

    encodeBinding<MVKMTLTextureBinding>(_resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty,
                                        [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                                            [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setTexture: b.mtlTexture
																										 atIndex: b.index];
                                        });

    encodeBinding<MVKMTLSamplerStateBinding>(_resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty,
                                             [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                                                 [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setSamplerState: b.mtlSamplerState
																												   atIndex: b.index];
                                             });

	// If any buffers have been bound, mark the GPU addressable buffers as needed.
	if (wereBufferBindingsDirty && !_resourceBindings.areBufferBindingsDirty ) {
		_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageCompute);
	}
}

MVKPipeline* MVKComputeResourcesCommandEncoderState::getPipeline() {
	return _cmdEncoder->getComputePipeline();
}

void MVKComputeResourcesCommandEncoderState::bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) {
	bindBuffer(buffBind);
}

void MVKComputeResourcesCommandEncoderState::encodeResourceUsage(MVKShaderStage stage,
																 id<MTLResource> mtlResource,
																 MTLResourceUsage mtlUsage,
																 MTLRenderStages mtlStages) {
	if (mtlResource) {
		auto* mtlCompEnc = _cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch);
		[mtlCompEnc useResource: mtlResource usage: mtlUsage];
	}
}

void MVKComputeResourcesCommandEncoderState::markBufferIndexOverridden(uint32_t mtlBufferIndex) {
	MVKResourcesCommandEncoderState::markBufferIndexOverridden(_resourceBindings.bufferBindings, mtlBufferIndex);
}

void MVKComputeResourcesCommandEncoderState::markOverriddenBufferIndexesDirty() {
	MVKResourcesCommandEncoderState::markOverriddenBufferIndexesDirty(_resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty);
}


#pragma mark -
#pragma mark MVKGPUAddressableBuffersCommandEncoderState

void MVKGPUAddressableBuffersCommandEncoderState::useGPUAddressableBuffersInStage(MVKShaderStage shaderStage) {
	MVKPipeline* pipeline = (shaderStage == kMVKShaderStageCompute
							 ? (MVKPipeline*)_cmdEncoder->getComputePipeline()
							 : (MVKPipeline*)_cmdEncoder->getGraphicsPipeline());
	if (pipeline && pipeline->usesPhysicalStorageBufferAddressesCapability(shaderStage)) {
		_usageStages[shaderStage] = true;
		markDirty();
	}
}

void MVKGPUAddressableBuffersCommandEncoderState::encodeImpl(uint32_t stage) {
	auto* mvkDev = getDevice();
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		MVKShaderStage shaderStage = MVKShaderStage(i);
		if (_usageStages[shaderStage]) {
			MVKResourcesCommandEncoderState* rezEncState = (shaderStage == kMVKShaderStageCompute
															? (MVKResourcesCommandEncoderState*)&_cmdEncoder->_computeResourcesState
															: (MVKResourcesCommandEncoderState*)&_cmdEncoder->_graphicsResourcesState);
			mvkDev->encodeGPUAddressableBuffers(rezEncState, shaderStage);
		}
	}
	mvkClear(_usageStages, kMVKShaderStageCount);
}


#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

// Metal resets the query counter at a render pass boundary, so copy results to the query pool's accumulation buffer.
// Don't copy occlusion info until after rasterization, as Metal renderpasses can be ended prematurely during tessellation.
void MVKOcclusionQueryCommandEncoderState::endMetalRenderPass() {
	const MVKMTLBufferAllocation* vizBuff = _cmdEncoder->_pEncodingContext->visibilityResultBuffer;
    if ( !_hasRasterized || !vizBuff || _mtlRenderPassQueries.empty() ) { return; }  // Nothing to do.

	id<MTLComputePipelineState> mtlAccumState = _cmdEncoder->getCommandEncodingPool()->getAccumulateOcclusionQueryResultsMTLComputePipelineState();
    id<MTLComputeCommandEncoder> mtlAccumEncoder = _cmdEncoder->getMTLComputeEncoder(kMVKCommandUseAccumOcclusionQuery, true);
    [mtlAccumEncoder setComputePipelineState: mtlAccumState];
    for (auto& qryLoc : _mtlRenderPassQueries) {
        // Accumulate the current results to the query pool's buffer.
        [mtlAccumEncoder setBuffer: qryLoc.queryPool->getVisibilityResultMTLBuffer()
                            offset: qryLoc.queryPool->getVisibilityResultOffset(qryLoc.query)
                           atIndex: 0];
        [mtlAccumEncoder setBuffer: vizBuff->_mtlBuffer
                            offset: vizBuff->_offset + qryLoc.visibilityBufferOffset
                           atIndex: 1];
        [mtlAccumEncoder dispatchThreadgroups: MTLSizeMake(1, 1, 1)
                        threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
    }
    _mtlRenderPassQueries.clear();
	_hasRasterized = false;
}

// The Metal visibility buffer has a finite size, and on some Metal platforms (looking at you M1),
// query offsets cannnot be reused with the same MTLCommandBuffer. If enough occlusion queries are
// begun within a single MTLCommandBuffer, it may exhaust the visibility buffer. If that occurs,
// report an error and disable further visibility tracking for the remainder of the MTLCommandBuffer.
// In most cases, a MTLCommandBuffer corresponds to a Vulkan command submit (VkSubmitInfo),
// and so the error text is framed in terms of the Vulkan submit.
void MVKOcclusionQueryCommandEncoderState::beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
	if (_cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset + kMVKQuerySlotSizeInBytes <= _cmdEncoder->getMetalFeatures().maxQueryBufferSize) {
		bool shouldCount = _cmdEncoder->getEnabledFeatures().occlusionQueryPrecise && mvkAreAllFlagsEnabled(flags, VK_QUERY_CONTROL_PRECISE_BIT);
		_mtlVisibilityResultMode = shouldCount ? MTLVisibilityResultModeCounting : MTLVisibilityResultModeBoolean;
		_mtlRenderPassQueries.emplace_back(pQueryPool, query, _cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset);
	} else {
		reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCmdBeginQuery(): The maximum number of queries in a single Vulkan command submission is %llu.", _cmdEncoder->getMetalFeatures().maxQueryBufferSize / kMVKQuerySlotSizeInBytes);
		_mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
		_cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset -= kMVKQuerySlotSizeInBytes;
	}
	_hasRasterized = false;
    markDirty();
}

void MVKOcclusionQueryCommandEncoderState::endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
	_mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
	_cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset += kMVKQuerySlotSizeInBytes;
	_hasRasterized = true;	// Handle begin and end query with no rasterizing before end of renderpass.
	markDirty();
}

void MVKOcclusionQueryCommandEncoderState::encodeImpl(uint32_t stage) {
	if (stage != kMVKGraphicsStageRasterization) { return; }

	_hasRasterized = true;
	[_cmdEncoder->_mtlRenderEncoder setVisibilityResultMode: _mtlVisibilityResultMode
													 offset: _cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset];
}
