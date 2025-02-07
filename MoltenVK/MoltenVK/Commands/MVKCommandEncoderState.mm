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

static void bindDescriptorSets(MVKBindingList (&target)[kMVKMaxDescriptorSetCount],
                               MVKSmallVector<uint32_t, 8>& targetDynamicOffsets,
                               MVKShaderStage stage,
                               MVKPipelineLayout* layout,
                               uint32_t firstSet, uint32_t setCount, MVKDescriptorSet*const* sets,
                               uint32_t dynamicOffsetCount, const uint32_t* dynamicOffsets)
{
	[[maybe_unused]] const uint32_t* dynamicOffsetsEnd = dynamicOffsets + dynamicOffsetCount;
	for (uint32_t i = 0; i < setCount; i++) {
		uint32_t setIdx = firstSet + i;
		target[setIdx].bufferBindings.clear();
		target[setIdx].textureBindings.clear();
		target[setIdx].samplerStateBindings.clear();
		layout->appendDescriptorSetBindings(target[setIdx], targetDynamicOffsets, stage, setIdx, sets[i], dynamicOffsets);
	}
	assert(dynamicOffsets == dynamicOffsetsEnd && "All dynamic offsets should have been used, and no more than that");
}

static void bindImmediateData(id<MTLCommandEncoder> encoder,
                              MVKCommandEncoder& mvkEncoder,
                              const uint8_t* data, size_t size,
                              uint32_t idx,
                              const MVKResourceBinder& RESTRICT binder)
{
	if (size < 4096) {
		binder.setBytes(encoder, data, size, idx);
	} else {
		const MVKMTLBufferAllocation* alloc = mvkEncoder.copyToTempMTLBufferAllocation(data, size);
		binder.setBuffer(encoder, alloc->_mtlBuffer, alloc->_offset, idx);
	}
}

static void bindImmediateData(id<MTLCommandEncoder> encoder,
                              MVKCommandEncoder& mvkEncoder,
                              MVKArrayRef<const uint32_t> data,
                              uint32_t idx,
                              const MVKResourceBinder& RESTRICT binder)
{
	bindImmediateData(encoder, mvkEncoder, reinterpret_cast<const uint8_t*>(data.data()), data.byteSize(), idx, binder);
}

/** Updates a value at the given index in the given vector, resizing if needed. */
template<class V>
static void updateImplicitBuffer(V &contents, uint32_t index, uint32_t value) {
	if (index >= contents.size()) { contents.resize(index + 1); }
	contents[index] = value;
}

static void bindMetalResources(id<MTLCommandEncoder> encoder,
                               MVKCommandEncoder& mvkEncoder,
                               MVKPipelineLayout* layout,
                               const MVKBindingList* resources,
                               const MVKSmallVector<uint32_t, 8>& dynamicOffsets,
                               const uint8_t* pushConstants,
                               const MVKImplicitBufferBindings& implicitBuffers,
                               const MVKStageResourceBits& needed,
                               MVKStageResourceBits& exists,
                               MVKStageResourceBindings& bindings,
                               const MVKResourceBinder& RESTRICT binder)
{
	auto& scratch = mvkEncoder._scratch;
	MVKArrayRef bindingLists(resources, layout->getDescriptorSetCount());
	for (const MVKBindingList& list : bindingLists) {
		for (const MVKMTLBufferBinding& b : list.bufferBindings) {
			if (!needed.buffers.get(b.index)) { continue; }
			bindBuffer(encoder, b.mtlBuffer, b.offset, b.index, exists, bindings, binder);
		}
		for (const MVKMTLTextureBinding& t : list.textureBindings) {
			if (!needed.textures.get(t.index)) { continue; }
			bindTexture(encoder, t.mtlTexture, t.index, exists, bindings, binder);
		}
		for (const MVKMTLSamplerStateBinding& s : list.samplerStateBindings) {
			if (!needed.samplers.get(s.index)) { continue; }
			bindSampler(encoder, s.mtlSamplerState, s.index, exists, bindings, binder);
		}
	}
	for (MVKImplicitBuffer buffer : implicitBuffers.needed & MVKNonVolatileImplicitBuffers) {
		assert(buffer < static_cast<MVKImplicitBuffer>(MVKNonVolatileImplicitBuffer::Count));
		MVKNonVolatileImplicitBuffer nvbuffer = static_cast<MVKNonVolatileImplicitBuffer>(buffer);
		uint32_t idx = implicitBuffers.ids[buffer];
		if (exists.buffers.get(idx) && bindings.buffers[idx] == MVKStageResourceBindings::ImplicitBuffer(buffer))
			continue;
		if (bindings.implicitBufferIndices[nvbuffer] != idx) {
			// Index is changing, invalidate the old buffer since it will no longer get updated by other invalidations
			uint32_t oldIndex = bindings.implicitBufferIndices[nvbuffer];
			bindings.implicitBufferIndices[nvbuffer] = idx;
			if (bindings.buffers[oldIndex] == MVKStageResourceBindings::ImplicitBuffer(buffer))
				bindings.buffers[oldIndex] = MVKStageResourceBindings::InvalidBuffer();
		}
		exists.buffers.set(implicitBuffers.ids[buffer]);
		bindings.buffers[idx] = MVKStageResourceBindings::ImplicitBuffer(buffer);
		switch (nvbuffer) {
			case MVKNonVolatileImplicitBuffer::PushConstant:
				bindImmediateData(encoder, mvkEncoder, pushConstants, layout->getPushConstantsLength(), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::Swizzle:
				scratch.clear();
				for (const MVKBindingList& list : bindingLists) {
					for (auto& b : list.textureBindings) {
						updateImplicitBuffer(scratch, b.index, b.swizzle);
					}
				}
				bindImmediateData(encoder, mvkEncoder, scratch.contents(), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::BufferSize:
				scratch.clear();
				for (const MVKBindingList& list : bindingLists) {
					for (auto& b : list.bufferBindings) {
						updateImplicitBuffer(scratch, b.index, b.size);
					}
				}
				bindImmediateData(encoder, mvkEncoder, scratch.contents(), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::DynamicOffset:
				bindImmediateData(encoder, mvkEncoder, dynamicOffsets.contents(), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::ViewRange: {
				uint32_t viewRange[] = {
					mvkEncoder.getSubpass()->getFirstViewIndexInMetalPass(mvkEncoder.getMultiviewPassIndex()),
					mvkEncoder.getSubpass()->getViewCountInMetalPass(mvkEncoder.getMultiviewPassIndex())
				};
				binder.setBytes(encoder, viewRange, sizeof(viewRange), idx);
				break;
			}
			case MVKNonVolatileImplicitBuffer::Count:
				assert(0);
				break;
		}
	}
	for (MVKImplicitBuffer buffer : implicitBuffers.needed.removingAll(MVKNonVolatileImplicitBuffers)) {
		// Mark needed volatile implicit buffers used in buffer tracking, they'll get set during the draw
		size_t idx = implicitBuffers.ids[buffer];
		exists.buffers.set(idx);
		bindings.buffers[idx] = MVKStageResourceBindings::InvalidBuffer();
	}
}

/**
 * Bind resources for running Vulkan graphics commands on a Metal render command encoder
 *
 * Binds resources in stage `vkStage` of `vkState` to stage `mtlStage` of `mtlState`
 */
static void bindVulkanGraphicsToMetalGraphics(
	id<MTLRenderCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanGraphicsCommandEncoderState& vkState,
	const MVKVulkanSharedCommandEncoderState& vkShared,
	MVKMetalGraphicsCommandEncoderState& mtlState,
	MVKGraphicsPipeline* pipeline,
	MVKShaderStage vkStage,
	MVKMetalGraphicsStage mtlStage)
{
	bindMetalResources(encoder,
	                   mvkEncoder,
	                   vkState._layout,
	                   vkState._descriptorSetBindings[vkStage],
	                   vkState._dynamicOffsets[vkStage],
	                   vkShared._pushConstants.data(),
	                   pipeline->getImplicitBuffers(vkStage),
	                   pipeline->getStageResources(vkStage),
	                   mtlState._exists[mtlStage],
	                   mtlState._bindings[mtlStage],
	                   MVKResourceBinder::Get(mtlStage));
}

/**
 * Bind resources for running Vulkan graphics commands on a Metal compute command encoder
 *
 * Binds resources in stage `vkStage` of `vkState` to `mtlState`
 */
static void bindVulkanGraphicsToMetalCompute(
	id<MTLComputeCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanGraphicsCommandEncoderState& vkState,
	const MVKVulkanSharedCommandEncoderState& vkShared,
	MVKMetalComputeCommandEncoderState& mtlState,
	MVKGraphicsPipeline* pipeline,
	MVKShaderStage vkStage)
{
	bindMetalResources(encoder,
	                   mvkEncoder,
	                   vkState._layout,
	                   vkState._descriptorSetBindings[vkStage],
	                   vkState._dynamicOffsets[vkStage],
	                   vkShared._pushConstants.data(),
	                   pipeline->getImplicitBuffers(vkStage),
	                   pipeline->getStageResources(vkStage),
	                   mtlState._exists,
	                   mtlState._bindings,
	                   MVKResourceBinder::Compute());
}

/** Bind resources for running Vulkan compute commands on a Metal compute command encoder */
static void bindVulkanComputeToMetalCompute(
	id<MTLComputeCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanComputeCommandEncoderState& vkState,
	const MVKVulkanSharedCommandEncoderState& vkShared,
	MVKMetalComputeCommandEncoderState& mtlState,
	MVKComputePipeline* pipeline)
{
	bindMetalResources(encoder,
	                   mvkEncoder,
	                   vkState._layout,
	                   vkState._descriptorSetBindings,
	                   vkState._dynamicOffsets,
	                   vkShared._pushConstants.data(),
	                   pipeline->getImplicitBuffers(),
	                   pipeline->getStageResources(),
	                   mtlState._exists,
	                   mtlState._bindings,
	                   MVKResourceBinder::Compute());
}

template <bool DynamicStride>
static void bindVertexBuffersTemplate(id<MTLCommandEncoder> encoder,
                                      const MVKVulkanGraphicsCommandEncoderState& vkState,
                                      MVKStageResourceBits& exists,
                                      MVKStageResourceBindings& bindings,
                                      const MVKVertexBufferBinder& RESTRICT binder)
{
	MVKGraphicsPipeline* pipeline = vkState._pipeline;
	for (size_t vkidx : pipeline->getVkVertexBuffers()) {
		const auto& buffer = vkState._vertexBuffers[vkidx];
		uint32_t idx = pipeline->getMetalBufferIndexForVertexAttributeBinding(static_cast<uint32_t>(vkidx));
		bindVertexBuffer<DynamicStride>(encoder, buffer.mtlBuffer, buffer.offset, buffer.stride,
		                                idx, exists, bindings, binder);
	}
	for (const auto& xltdBuffer : pipeline->getTranslatedVertexBindings()) {
		const auto& buffer = vkState._vertexBuffers[xltdBuffer.binding];
		uint32_t idx = pipeline->getMetalBufferIndexForVertexAttributeBinding(xltdBuffer.translationBinding);
		bindVertexBuffer<DynamicStride>(encoder, buffer.mtlBuffer, buffer.offset + xltdBuffer.translationOffset, buffer.stride,
		                                idx, exists, bindings, binder);
	}
}

static void bindVertexBuffers(id<MTLCommandEncoder> encoder,
                              const MVKVulkanGraphicsCommandEncoderState& vkState,
                              MVKStageResourceBits& exists,
                              MVKStageResourceBindings& bindings,
                              const MVKVertexBufferBinder& RESTRICT binder)
{
	if (vkState._pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::VertexStride))
		bindVertexBuffersTemplate<true> (encoder, vkState, exists, bindings, binder);
	else
		bindVertexBuffersTemplate<false>(encoder, vkState, exists, bindings, binder);
}

static void useResourcesInDescriptorSet(
	MVKCommandEncoder& mvkEncoder,
	MVKDescriptorSet* set,
	MVKBitArray& bindingUse,
	MVKDescriptorResourceUsage& descUsage,
	MVKShaderStage vkStage,
	MTLRenderStages mtlStages,
	uint32_t setIdx)
{
	auto* dsLayout = set->getLayout();

	uint32_t dslBindCnt = dsLayout->getBindingCount();
	for (uint32_t dslBindIdx = 0; dslBindIdx < dslBindCnt; dslBindIdx++) {
		auto* dslBind = dsLayout->getBindingAt(dslBindIdx);
		if (dslBind->getApplyToStage(vkStage) && bindingUse.getBit(dslBindIdx)) {
			uint32_t elemCnt = dslBind->getDescriptorCount(set->getVariableDescriptorCount());
			for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
				uint32_t descIdx = dslBind->getDescriptorIndex(elemIdx);
				if (descUsage.dirtyDescriptors[setIdx].getBit(descIdx, true)) {
					auto* mvkDesc = set->getDescriptorAt(descIdx);
					mvkDesc->encodeResourceUsage(mvkEncoder, dslBind, vkStage);
				}
			}
		}
	}
	if (descUsage.dirtyAuxBuffers.get(setIdx)) {
		descUsage.dirtyAuxBuffers.clear(setIdx);
		set->encodeAuxBufferUsage(mvkEncoder, vkStage);
	}
}

static void useResourcesInDescriptorSets(
	MVKCommandEncoder& mvkEncoder,
	MVKDescriptorSet*const (&sets)[kMVKMaxDescriptorSetCount],
	MVKPipeline* pipeline,
	MVKDescriptorResourceUsage& dirtyDescriptors,
	MVKShaderStage vkStage,
	MTLRenderStages mtlStages,
	MVKStaticBitSet<kMVKMaxDescriptorSetCount> needed)
{
	for (size_t idx : needed) {
		MVKBitArray& bindingUse = pipeline->getDescriptorBindingUse(static_cast<uint32_t>(idx), vkStage);
		useResourcesInDescriptorSet(mvkEncoder, sets[idx], bindingUse, dirtyDescriptors, vkStage, mtlStages, static_cast<uint32_t>(idx));
	}
}

/** If the contents of an implicit buffer changes, call this to ensure that the contents will be rebound before the next draw. */
static void invalidateImplicitBuffer(MVKStageResourceBindings& bindings, MVKStageResourceBits& ready, MVKNonVolatileImplicitBuffer buffer) {
	uint32_t idx = bindings.implicitBufferIndices[buffer];
	if (bindings.buffers[idx] == MVKStageResourceBindings::ImplicitBuffer(buffer)) {
		bindings.buffers[idx] = MVKStageResourceBindings::NullBuffer();
		ready.buffers.clear(idx);
	}
}

/** If the contents of an implicit buffer changes, call this to ensure that the contents will be rebound before the next draw. */
static void invalidateImplicitBuffer(MVKMetalGraphicsCommandEncoderState& state, MVKNonVolatileImplicitBuffer buffer) {
	for (uint32_t i = 0; i < static_cast<uint32_t>(MVKMetalGraphicsStage::Count); i++) {
		MVKMetalGraphicsStage stage = static_cast<MVKMetalGraphicsStage>(i);
		invalidateImplicitBuffer(state._bindings[stage], state._ready[stage], buffer);
	}
}

/** If the contents of an implicit buffer changes, call this to ensure that the contents will be rebound before the next draw. */
static void invalidateImplicitBuffer(MVKMetalComputeCommandEncoderState& state, MVKNonVolatileImplicitBuffer buffer) {
	invalidateImplicitBuffer(state._bindings, state._ready, buffer);
}

/** Invalidate the implicit buffers that depend on the contents of the bound descriptor sets. */
template <typename MTLState>
static void invalidateDescriptorSetImplicitBuffers(MTLState& state) {
	invalidateImplicitBuffer(state, MVKNonVolatileImplicitBuffer::BufferSize);
	invalidateImplicitBuffer(state, MVKNonVolatileImplicitBuffer::DynamicOffset);
	invalidateImplicitBuffer(state, MVKNonVolatileImplicitBuffer::Swizzle);
}

static void invalidateDescriptorSets(
	MVKStaticBitSet<kMVKMaxDescriptorSetCount>& valid,
	MVKDescriptorSet*const (&boundSets)[kMVKMaxDescriptorSetCount],
	MVKDescriptorSet*const* incomingSets,
	size_t firstIncoming,
	size_t numIncoming)
{
	for (size_t i = 0; i < numIncoming; i++) {
		if (boundSets[firstIncoming + i] != boundSets[i])
			valid.clear(i);
	}
}

static void resetDirtyDescriptors(
	MVKDescriptorResourceUsage& usage,
	MVKStaticBitSet<kMVKMaxDescriptorSetCount> reset,
	MVKDescriptorSet*const (&sets)[kMVKMaxDescriptorSetCount])
{
	for (size_t idx : reset) {
		usage.dirtyAuxBuffers.set(idx);
		usage.dirtyDescriptors[idx].resize(sets[idx]->getDescriptorCount());
		usage.dirtyDescriptors[idx].enableAllBits();
	}
}

static bool isGraphicsStage(MVKShaderStage stage) {
	return stage < kMVKShaderStageCompute;
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

void MVKVulkanGraphicsCommandEncoderState::bindDescriptorSets(
	MVKPipelineLayout* layout,
	uint32_t firstSet,
	uint32_t setCount,
	MVKDescriptorSet*const* sets,
	uint32_t dynamicOffsetCount,
	const uint32_t* dynamicOffsets)
{
	for (uint32_t i = 0; i <= kMVKShaderStageFragment; i++) {
		MVKShaderStage stage = static_cast<MVKShaderStage>(i);
		::bindDescriptorSets(_descriptorSetBindings[stage], _dynamicOffsets[stage], stage,
		                     layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
	}
	for (uint32_t i = 0; i < setCount; i++) {
		_descriptorSets[firstSet + i] = sets[i];
	}
}

#pragma mark - MVKVulkanComputeCommandEncoderState

void MVKVulkanComputeCommandEncoderState::bindDescriptorSets(
	MVKPipelineLayout* layout,
	uint32_t firstSet,
	uint32_t setCount,
	MVKDescriptorSet*const* sets,
	uint32_t dynamicOffsetCount,
	const uint32_t* dynamicOffsets)
{
	::bindDescriptorSets(_descriptorSetBindings, _dynamicOffsets, kMVKShaderStageCompute,
	                     layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
	for (uint32_t i = 0; i < setCount; i++) {
		_descriptorSets[firstSet + i] = sets[i];
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
	memset(static_cast<MVKMetalGraphicsCommandEncoderStateQuickReset*>(this), 0, offsetof(MVKMetalGraphicsCommandEncoderStateQuickReset, MEMSET_RESET_LINE));
	_lineWidth = 1;
	_sampleCount = getSampleCount(sampleCount);
	_depthStencil.reset();
	_renderUsageStages.clear();
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
	if (from) {
		markDirty(from->getStaticStateFlags());
		_ready.vertex().buffers.clearAllIn(from->getMtlVertexBuffers());
	}
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
	const MVKVulkanGraphicsCommandEncoderState& vk,
	const MVKVulkanSharedCommandEncoderState& vkShared)
{
	MVKGraphicsPipeline* pipeline = vk._pipeline;
	if (!pipeline->getMainPipelineState()) // Abort if pipeline could not be created.
		return;

	bool changedPipeline = false;

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
			changedPipeline = true;
		}
	}

	// State
	bindState(encoder, mvkEncoder, vk);

	// Resources
	MVKStaticBitSet<kMVKMaxDescriptorSetCount> neededDirty;
	if (mvkEncoder.isUsingMetalArgumentBuffers()) {
		MVKStaticBitSet<kMVKMaxDescriptorSetCount> neededDS = pipeline->getDescriptorsSetsNeeded(kMVKShaderStageFragment);
		if (pipeline->isTessellationPipeline()) {
			neededDS |= pipeline->getDescriptorsSetsNeeded(kMVKShaderStageTessEval);
		} else {
			neededDS |= pipeline->getDescriptorsSetsNeeded(kMVKShaderStageVertex);
		}
		neededDirty = neededDS.clearingAllIn(_descriptorSetsReady);
		resetDirtyDescriptors(_descriptorSetResources, neededDirty, vk._descriptorSets);
		_descriptorSetsReady |= neededDS;
		if (changedPipeline) // If we change pipelines, we need to recheck usage of all descriptors
			neededDirty = neededDS;
	}
	if (pipeline->isTessellationPipeline()) {
		bindVulkanGraphicsToMetalGraphics(encoder, mvkEncoder, vk, vkShared, *this, pipeline, kMVKShaderStageTessEval, MVKMetalGraphicsStage::Vertex);
		useResourcesInDescriptorSets(mvkEncoder, vk._descriptorSets, pipeline, _descriptorSetResources, kMVKShaderStageTessEval, MTLRenderStageVertex, neededDirty);
	} else {
		bindVulkanGraphicsToMetalGraphics(encoder, mvkEncoder, vk, vkShared, *this, pipeline, kMVKShaderStageVertex,   MVKMetalGraphicsStage::Vertex);
		bindVertexBuffers(encoder, vk, _exists.vertex(), _bindings.vertex(), MVKVertexBufferBinder::Vertex());
		useResourcesInDescriptorSets(mvkEncoder, vk._descriptorSets, pipeline, _descriptorSetResources, kMVKShaderStageVertex, MTLRenderStageVertex, neededDirty);
	}
	bindVulkanGraphicsToMetalGraphics(encoder, mvkEncoder, vk, vkShared, *this, pipeline, kMVKShaderStageFragment, MVKMetalGraphicsStage::Fragment);
	useResourcesInDescriptorSets(mvkEncoder, vk._descriptorSets, pipeline, _descriptorSetResources, kMVKShaderStageFragment, MTLRenderStageFragment, neededDirty);
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
	mvkEncoder._occlusionQueryState.prepareHelperDraw(encoder, &mvkEncoder);
}

#pragma mark - MVKMetalComputeCommandEncoderState


void MVKMetalComputeCommandEncoderState::bindPipeline(id<MTLComputeCommandEncoder> encoder, id<MTLComputePipelineState> pipeline) {
	_vkPipeline = nullptr;
	if (_pipeline != pipeline) {
		_pipeline = pipeline;
		[encoder setComputePipelineState:pipeline];
	}
}
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
	const MVKVulkanComputeCommandEncoderState& vk,
	const MVKVulkanSharedCommandEncoderState& vkShared)
{
	MVKComputePipeline* pipeline = vk._pipeline;
	id<MTLComputePipelineState> mtlPipeline = pipeline->getPipelineState();
	if (!mtlPipeline) // Abort if pipeline could not be created.
		return;

	_vkPipeline = pipeline;

	bool changedPipeline = false;
	if (_pipeline != mtlPipeline) {
		_pipeline = mtlPipeline;
		[encoder setComputePipelineState:mtlPipeline];
		changedPipeline = true;
	}

	if (_vkStage != kMVKShaderStageCompute) {
		memset(&_ready, 0, sizeof(_ready));
		// We bind descriptor sets differently based on what stage is getting used, so reset these
		_descriptorSetsReady.reset();
		if (_vkStage != kMVKShaderStageCount) {
			// Switching between graphics and compute, need to invalidate implicit buffers too
			invalidateDescriptorSetImplicitBuffers(*this);
		}
		_vkStage = kMVKShaderStageCompute;
	}

	MVKStaticBitSet<kMVKMaxDescriptorSetCount> neededDirty;
	if (mvkEncoder.isUsingMetalArgumentBuffers()) {
		MVKStaticBitSet<kMVKMaxDescriptorSetCount> neededDS = pipeline->getDescriptorsSetsNeeded();
		neededDirty = neededDS.clearingAllIn(_descriptorSetsReady);
		resetDirtyDescriptors(_descriptorSetResources, neededDirty, vk._descriptorSets);
		_descriptorSetsReady |= neededDS;
		if (changedPipeline)
			neededDirty = neededDS;
	}
	bindVulkanComputeToMetalCompute(encoder, mvkEncoder, vk, vkShared, *this, pipeline);
	useResourcesInDescriptorSets(mvkEncoder, vk._descriptorSets, pipeline, _descriptorSetResources, kMVKShaderStageCompute, 0, neededDirty);
}

void MVKMetalComputeCommandEncoderState::prepareRenderDispatch(
	id<MTLComputeCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanGraphicsCommandEncoderState& vk,
	const MVKVulkanSharedCommandEncoderState& vkShared,
	MVKShaderStage stage)
{
	MVKGraphicsPipeline* pipeline = vk._pipeline;
	if (!pipeline->getMainPipelineState()) // Abort if pipeline could not be created.
		return;


	bool changedPipeline = false;
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
		changedPipeline = true;
	}

	if (_vkStage != stage) {
		memset(&_ready, 0, sizeof(_ready));
		// We bind descriptor sets differently based on what stage is getting used, so reset these
		_descriptorSetsReady.reset();
		if (_vkStage == kMVKShaderStageCompute) {
			// Switching between graphics and compute, need to invalidate implicit buffers too
			invalidateDescriptorSetImplicitBuffers(*this);
		}
		_vkStage = stage;
	}

	MVKStaticBitSet<kMVKMaxDescriptorSetCount> neededDirty;
	if (mvkEncoder.isUsingMetalArgumentBuffers()) {
		MVKStaticBitSet<kMVKMaxDescriptorSetCount> neededDS = pipeline->getDescriptorsSetsNeeded(stage);
		neededDirty = neededDS.clearingAllIn(_descriptorSetsReady);
		resetDirtyDescriptors(_descriptorSetResources, neededDirty, vk._descriptorSets);
		_descriptorSetsReady |= neededDS;
		if (changedPipeline)
			neededDirty = neededDS;
	}
	bindVulkanGraphicsToMetalCompute(encoder, mvkEncoder, vk, vkShared, *this, pipeline, stage);
	if (stage == kMVKShaderStageVertex)
		bindVertexBuffers(encoder, vk, _exists, _bindings, MVKVertexBufferBinder::Compute());
	useResourcesInDescriptorSets(mvkEncoder, vk._descriptorSets, pipeline, _descriptorSetResources, stage, 0, neededDirty);
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

/** Used by applyToActiveMTLState to indicate that you want to apply to whichever state is active. */
static constexpr VkPipelineBindPoint VK_PIPELINE_BIND_POINT_ALL = VK_PIPELINE_BIND_POINT_MAX_ENUM;

static void invalidateImplicitBuffer(MVKCommandEncoderStateNew& state, VkPipelineBindPoint bindPoint, MVKNonVolatileImplicitBuffer buffer) {
	state.applyToActiveMTLState(bindPoint, [buffer](auto& mtl){ invalidateImplicitBuffer(mtl, buffer); });
}

void MVKCommandEncoderStateNew::bindGraphicsPipeline(MVKGraphicsPipeline* pipeline) {
	_mtlGraphics.changePipeline(_vkGraphics._pipeline, pipeline);
	_vkGraphics._pipeline = pipeline;
	MVKPipelineLayout* layout = pipeline->getLayout();
	if (_vkGraphics._layout != layout) {
		if (!_vkGraphics._layout || _vkGraphics._layout->getPushConstantsLength() < layout->getPushConstantsLength()) {
			mvkEnsureSize(_vkShared._pushConstants, layout->getPushConstantsLength());
			invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_GRAPHICS, MVKNonVolatileImplicitBuffer::PushConstant);
		}
		_vkGraphics._layout = layout;
	}
	// We only useResources the descriptors that are used by the pipeline, so changing the pipeline will require rebinding descriptor sets
	_mtlGraphics._descriptorSetsReady.reset();
	_mtlCompute._descriptorSetsReady.reset();
}

void MVKCommandEncoderStateNew::bindComputePipeline(MVKComputePipeline* pipeline) {
	_vkCompute._pipeline = pipeline;
	MVKPipelineLayout* layout = pipeline->getLayout();
	if (_vkCompute._layout != layout) {
		if (!_vkCompute._layout || _vkCompute._layout->getPushConstantsLength() < layout->getPushConstantsLength()) {
			mvkEnsureSize(_vkShared._pushConstants, layout->getPushConstantsLength());
			invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_COMPUTE, MVKNonVolatileImplicitBuffer::PushConstant);
		}
		_vkCompute._layout = layout;
	}
	// We only useResources the descriptors that are used by the pipeline, so changing the pipeline will require rebinding descriptor sets
	_mtlCompute._descriptorSetsReady.reset();
}

void MVKCommandEncoderStateNew::pushConstants(uint32_t offset, uint32_t size, const void* data) {
	mvkEnsureSize(_vkShared._pushConstants, offset + size);
	memcpy(_vkShared._pushConstants.data() + offset, data, size);
	invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_ALL, MVKNonVolatileImplicitBuffer::PushConstant);
}

void MVKCommandEncoderStateNew::bindDescriptorSets(
	VkPipelineBindPoint bindPoint,
	MVKPipelineLayout* layout,
	uint32_t firstSet,
	uint32_t setCount,
	MVKDescriptorSet*const* sets,
	uint32_t dynamicOffsetCount,
	const uint32_t* dynamicOffsets)
{
	MVKDescriptorSet*const (*boundSets)[kMVKMaxDescriptorSetCount] = nullptr;
	if (bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS) {
		boundSets = &_vkGraphics._descriptorSets;
	} else if (bindPoint == VK_PIPELINE_BIND_POINT_COMPUTE) {
		boundSets = &_vkCompute._descriptorSets;
	} else {
		return;
	}
	applyToActiveMTLState(bindPoint, [boundSets, sets, firstSet, setCount](auto& mtl){
		invalidateDescriptorSetImplicitBuffers(mtl);
		invalidateDescriptorSets(mtl._descriptorSetsReady, *boundSets, sets, firstSet, setCount);
	});
	if (bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS) {
		_vkGraphics.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
	} else if (bindPoint == VK_PIPELINE_BIND_POINT_COMPUTE) {
		_vkCompute.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
	}
}

void MVKCommandEncoderStateNew::bindVertexBuffers(uint32_t firstBinding, MVKArrayRef<const MVKVertexMTLBufferBinding> buffers) {
	mvkCopy(&_vkGraphics._vertexBuffers[firstBinding], buffers.data(), buffers.size());
	if (_mtlActiveEncoder == CommandEncoderClass::Graphics && _vkGraphics._pipeline && !_vkGraphics._pipeline->isTessellationPipeline())
		_mtlGraphics._ready.vertex().buffers.clearAllIn(_vkGraphics._pipeline->getMtlVertexBuffers());
	else if (_mtlActiveEncoder == CommandEncoderClass::Compute && _mtlCompute._vkStage == kMVKShaderStageVertex)
		_mtlCompute._ready.buffers.clearAllIn(_vkGraphics._pipeline->getMtlVertexBuffers());
}

void MVKCommandEncoderStateNew::bindIndexBuffer(const MVKIndexMTLBufferBinding& buffer) {
	_vkGraphics._indexBuffer = buffer;
	if (_mtlActiveEncoder == CommandEncoderClass::Compute && _mtlCompute._vkStage == kMVKShaderStageVertex)
		_mtlCompute._ready.buffers.clear(_vkGraphics._pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::IndirectParams]);
}

void MVKCommandEncoderStateNew::offsetZeroDivisorVertexBuffers(MVKCommandEncoder& mvkEncoder, MVKGraphicsStage stage, MVKGraphicsPipeline* pipeline, uint32_t firstInstance) {
	for (const auto& binding : pipeline->getZeroDivisorVertexBindings()) {
		uint32_t mtlBuffIdx = pipeline->getMetalBufferIndexForVertexAttributeBinding(binding.first);
		auto& buffer = _vkGraphics._vertexBuffers[binding.first];
		switch (stage) {
			case kMVKGraphicsStageVertex:
				[mvkEncoder.getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBufferOffset: buffer.offset + firstInstance * binding.second
				                                                                                  atIndex: mtlBuffIdx];
				break;
			case kMVKGraphicsStageRasterization:
				[mvkEncoder._mtlRenderEncoder setVertexBufferOffset:buffer.offset + firstInstance * binding.second
				                                            atIndex:mtlBuffIdx];
				break;
			default:
				assert(false); // If we hit this, something went wrong.
				break;
		}
	}
}

void MVKCommandEncoderStateNew::encodeResourceUsage(
	MVKCommandEncoder& mvkEncoder,
	MVKShaderStage stage,
	id<MTLResource> mtlResource,
	MTLResourceUsage mtlUsage,
	MTLRenderStages mtlStages)
{
	if (mtlResource) {
		switch (_mtlActiveEncoder) {
			case CommandEncoderClass::Graphics:
				if (mtlStages) {
					if (stage == kMVKShaderStageTessCtl) {
						auto* mtlCompEnc = mvkEncoder.getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
						[mtlCompEnc useResource: mtlResource usage: mtlUsage];
					} else {
						auto* mtlRendEnc = mvkEncoder._mtlRenderEncoder;
						if ([mtlRendEnc respondsToSelector: @selector(useResource:usage:stages:)]) {
							// Within a renderpass, a resource may be used by multiple descriptor bindings,
							// each of which may assign a different usage stage. Dynamically accumulate
							// usage stages across all descriptor bindings using the resource.
							auto& accumStages = _mtlGraphics._renderUsageStages[mtlResource];
							accumStages |= mtlStages;
							[mtlRendEnc useResource: mtlResource usage: mtlUsage stages: accumStages];
						} else {
							[mtlRendEnc useResource: mtlResource usage: mtlUsage];
						}
					}
				}
				break;
			case CommandEncoderClass::Compute:
				[mvkEncoder.getMTLComputeEncoder(kMVKCommandUseDispatch) useResource: mtlResource usage: mtlUsage];
				break;
			case CommandEncoderClass::None:
				break;
		}
	}
}

template <typename Fn>
void MVKCommandEncoderStateNew::applyToActiveMTLState(VkPipelineBindPoint bindPoint, Fn&& fn) {
	switch (_mtlActiveEncoder) {
		case CommandEncoderClass::Graphics:
			if (bindPoint != VK_PIPELINE_BIND_POINT_COMPUTE)
				std::forward<Fn>(fn)(_mtlGraphics);
			break;
		case CommandEncoderClass::Compute:
			if (bindPoint == VK_PIPELINE_BIND_POINT_COMPUTE && _mtlCompute._vkStage != kMVKShaderStageCompute)
				break;
			if (bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS && !isGraphicsStage(_mtlCompute._vkStage))
				break;
			std::forward<Fn>(fn)(_mtlCompute);
			break;
		default:
			break;
	}
}

#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

void MVKOcclusionQueryCommandEncoderState::beginMetalRenderPass(MVKCommandEncoder* cmdEncoder) {
	if (_mtlVisibilityResultMode != MTLVisibilityResultModeDisabled)
		_dirty = true;
}

// Metal resets the query counter at a render pass boundary, so copy results to the query pool's accumulation buffer.
// Don't copy occlusion info until after rasterization, as Metal renderpasses can be ended prematurely during tessellation.
void MVKOcclusionQueryCommandEncoderState::endMetalRenderPass(MVKCommandEncoder* cmdEncoder) {
	const MVKMTLBufferAllocation* vizBuff = cmdEncoder->_pEncodingContext->visibilityResultBuffer;
	if ( !_hasRasterized || !vizBuff || _mtlRenderPassQueries.empty() ) { return; }  // Nothing to do.

	id<MTLComputePipelineState> mtlAccumState = cmdEncoder->getCommandEncodingPool()->getAccumulateOcclusionQueryResultsMTLComputePipelineState();
	id<MTLComputeCommandEncoder> mtlAccumEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseAccumOcclusionQuery);
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	state.bindPipeline(mtlAccumEncoder, mtlAccumState);
	for (auto& qryLoc : _mtlRenderPassQueries) {
		// Accumulate the current results to the query pool's buffer.
		state.bindBuffer(mtlAccumEncoder, qryLoc.queryPool->getVisibilityResultMTLBuffer(), qryLoc.queryPool->getVisibilityResultOffset(qryLoc.query), 0);
		state.bindBuffer(mtlAccumEncoder, vizBuff->_mtlBuffer, vizBuff->_offset + qryLoc.visibilityBufferOffset, 1);
		[mtlAccumEncoder dispatchThreadgroups: MTLSizeMake(1, 1, 1)
		                threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
	}
	_mtlRenderPassQueries.clear();
	_hasRasterized = false;
	_dirty = false;
}

// The Metal visibility buffer has a finite size, and on some Metal platforms (looking at you M1),
// query offsets cannnot be reused with the same MTLCommandBuffer. If enough occlusion queries are
// begun within a single MTLCommandBuffer, it may exhaust the visibility buffer. If that occurs,
// report an error and disable further visibility tracking for the remainder of the MTLCommandBuffer.
// In most cases, a MTLCommandBuffer corresponds to a Vulkan command submit (VkSubmitInfo),
// and so the error text is framed in terms of the Vulkan submit.
void MVKOcclusionQueryCommandEncoderState::beginOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query, MTLVisibilityResultMode mode) {
	if (cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset + kMVKQuerySlotSizeInBytes <= cmdEncoder->getMetalFeatures().maxQueryBufferSize) {
		_mtlVisibilityResultMode = mode;
		_mtlRenderPassQueries.emplace_back(pQueryPool, query, cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset);
	} else {
		cmdEncoder->reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCmdBeginQuery(): The maximum number of queries in a single Vulkan command submission is %llu.", cmdEncoder->getMetalFeatures().maxQueryBufferSize / kMVKQuerySlotSizeInBytes);
		_mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
		cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset -= kMVKQuerySlotSizeInBytes;
	}
	_hasRasterized = false;
	_dirty = true;
}

void MVKOcclusionQueryCommandEncoderState::beginOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
	bool shouldCount = cmdEncoder->getEnabledFeatures().occlusionQueryPrecise && mvkAreAllFlagsEnabled(flags, VK_QUERY_CONTROL_PRECISE_BIT);
	beginOcclusionQuery(cmdEncoder, pQueryPool, query, shouldCount ? MTLVisibilityResultModeCounting : MTLVisibilityResultModeBoolean);
}

void MVKOcclusionQueryCommandEncoderState::endOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
	_mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
	cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset += kMVKQuerySlotSizeInBytes;
	_hasRasterized = true;	// Handle begin and end query with no rasterizing before end of renderpass.
	_dirty = true;
}

void MVKOcclusionQueryCommandEncoderState::prepareHelperDraw(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder* mvkEncoder) {
	if (_mtlVisibilityResultMode != MTLVisibilityResultModeDisabled) {
		if (!_dirty) {
			[encoder setVisibilityResultMode:MTLVisibilityResultModeDisabled
			                          offset:mvkEncoder->_pEncodingContext->mtlVisibilityResultOffset];
			mvkEncoder->_pEncodingContext->mtlVisibilityResultOffset += kMVKQuerySlotSizeInBytes;
			_dirty = true;
		}
	} else if (_dirty) {
		[encoder setVisibilityResultMode:MTLVisibilityResultModeDisabled
		                          offset:mvkEncoder->_pEncodingContext->mtlVisibilityResultOffset];
		_dirty = false;
		_hasRasterized = true;
	}
}

void MVKOcclusionQueryCommandEncoderState::encode(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder* mvkEncoder) {
	if (!_dirty)
		return;
	_dirty = false;
	_hasRasterized = true;
	[encoder setVisibilityResultMode:_mtlVisibilityResultMode
	                          offset:mvkEncoder->_pEncodingContext->mtlVisibilityResultOffset];
}
