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
#include "MVKImage.h"
#include "MVKRenderPass.h"
#include "MVKPipeline.h"
#include "MVKQueryPool.h"

using namespace std;

#if MVK_USE_METAL_PRIVATE_API
// An extension of the MTLRenderCommandEncoder protocol to declare the setLineWidth: method.
@protocol MVKMTLRenderCommandEncoderLineWidth <MTLRenderCommandEncoder>
- (void)setLineWidth:(float)width;
@end
#endif

#pragma mark - Resource Binder Structs

static MTLRenderStages getMTLStages(MVKResourceUsageStages stages) {
	switch (stages) {
		case MVKResourceUsageStages::Vertex:   return MTLRenderStageVertex;
		case MVKResourceUsageStages::Fragment: return MTLRenderStageFragment;
		case MVKResourceUsageStages::All:      return MTLRenderStageVertex | MTLRenderStageFragment;
		case MVKResourceUsageStages::Count:    break;
	}
	assert(0);
	return 0;
}

static void useResourceGraphics(id<MTLCommandEncoder> encoder, id<MTLResource> resource, MTLResourceUsage usage, MVKResourceUsageStages stages) {
	[static_cast<id<MTLRenderCommandEncoder>>(encoder) useResource:resource usage:usage stages:getMTLStages(stages)];
}

static void useResourceCompute(id<MTLCommandEncoder> encoder, id<MTLResource> resource, MTLResourceUsage usage, MVKResourceUsageStages stages) {
	[static_cast<id<MTLComputeCommandEncoder>>(encoder) useResource:resource usage:usage];
}

struct MVKFragmentBinder {
	static SEL selSetBytes()   { return @selector(setFragmentBytes:length:atIndex:); }
	static SEL selSetBuffer()  { return @selector(setFragmentBuffer:offset:atIndex:); }
	static SEL selSetOffset()  { return @selector(setFragmentBufferOffset:atIndex:); }
	static SEL selSetTexture() { return @selector(setFragmentTexture:atIndex:); }
	static SEL selSetSampler() { return @selector(setFragmentSamplerState:atIndex:); }
	static MVKResourceBinder::UseResource useResource() { return useResourceGraphics; }
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
	static MVKResourceBinder::UseResource useResource() { return useResourceGraphics; }
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
	static MVKResourceBinder::UseResource useResource() { return useResourceCompute; }
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
                       MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder) {
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
                      MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder) {
	exists.buffers.set(index);
	bindings.buffers[index] = MVKStageResourceBindings::InvalidBuffer();
	binder.setBytes(encoder, data, size, index);
}

template <bool DynamicStride>
static void bindVertexBuffer(id<MTLCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, uint32_t stride, NSUInteger index,
                             MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const MVKVertexBufferBinder& binder) {
	VkDeviceSize offsetLookup = offset;
	if constexpr (DynamicStride)
		offsetLookup ^= static_cast<VkDeviceSize>(stride ^ (1u << 31)) << 32;
	if (!exists.buffers.get(index) || bindings.buffers[index].buffer != buffer) {
		exists.buffers.set(index);
		if constexpr (DynamicStride)
			binder.setBufferDynamic(encoder, buffer, offset, stride, index);
		else
			binder.setBuffer(encoder, buffer, offset, index);
		bindings.buffers[index] = { buffer, offsetLookup };
	} else if (bindings.buffers[index].offset != offsetLookup) {
		if constexpr (DynamicStride)
			binder.setBufferOffsetDynamic(encoder, offset, stride, index);
		else
			binder.setBufferOffset(encoder, offset, index);
		bindings.buffers[index].offset = offsetLookup;
	}
}

template <typename Binder, typename Encoder>
static void bindTexture(Encoder encoder, id<MTLTexture> texture, NSUInteger index,
                        MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder) {
	if (!exists.textures.get(index) || bindings.textures[index] != texture) {
		exists.textures.set(index);
		binder.setTexture(encoder, texture, index);
		bindings.textures[index] = texture;
	}
}

template <typename Binder, typename Encoder>
static void bindSampler(Encoder encoder, id<MTLSamplerState> sampler, NSUInteger index,
                        MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder) {
	if (!exists.samplers.get(index) || bindings.samplers[index] != sampler) {
		exists.samplers.set(index);
		binder.setSampler(encoder, sampler, index);
		bindings.samplers[index] = sampler;
	}
}

static uint32_t getCPUMetaOffset(MVKDescriptorCPULayout layout) {
	switch (layout) {
		case MVKDescriptorCPULayout::OneIDMeta:  return offsetof(MVKCPUDescriptorOneIDMeta,  meta);
		case MVKDescriptorCPULayout::OneID2Meta: return offsetof(MVKCPUDescriptorOneID2Meta, meta);
		case MVKDescriptorCPULayout::TwoIDMeta:  return offsetof(MVKCPUDescriptorTwoIDMeta,  meta);
		case MVKDescriptorCPULayout::TwoID2Meta: return offsetof(MVKCPUDescriptorTwoID2Meta, meta);
		case MVKDescriptorCPULayout::None:
		case MVKDescriptorCPULayout::OneID:
		case MVKDescriptorCPULayout::InlineData:
			return 0;
	}
}

enum class ImplicitBufferData {
	BufferSize,
	TextureSwizzle,
};

static bool isTexelBuffer(VkDescriptorType type) {
	switch (type) {
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			return true;
		default:
			return false;
	}
}
static bool isImage(VkDescriptorType type) {
	switch (type) {
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return true;
		default:
			return false;
	}
}

template <ImplicitBufferData DataType>
static void bindImplicitBufferData(uint32_t* target, MVKDescriptorSetLayout* layout, const void* descriptor, VkShaderStageFlags stage, uint32_t variableCount) {
	for (const auto& binding : layout->bindings()) {
		uint32_t count = binding.isVariable() ? variableCount : binding.descriptorCount;
		assert(count <= binding.descriptorCount);
		if (!count)
			continue;
		if (!mvkIsAnyFlagEnabled(binding.stageFlags, stage))
			continue;
		if (DataType == ImplicitBufferData::BufferSize && binding.descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
			// Inline uniform blocks are bound as one buffer of size descriptorCount
			*target++ = count;
			continue;
		}
		uint32_t perDescCount;
		switch (DataType) {
			case ImplicitBufferData::BufferSize:     perDescCount = binding.perDescriptorResourceCount.buffer;  break;
			case ImplicitBufferData::TextureSwizzle: perDescCount = binding.perDescriptorResourceCount.texture; break;
		}
		if (perDescCount == 0)
			continue;
		size_t stride = descriptorCPUSize(binding.cpuLayout);
		size_t metaOff = getCPUMetaOffset(binding.cpuLayout);
		if (DataType == ImplicitBufferData::TextureSwizzle && isTexelBuffer(binding.descriptorType)) {
			mvkClear(target, count);
		} else if (metaOff == 0) {
			assert(DataType != ImplicitBufferData::BufferSize && "All buffers should have metadata");
			mvkClear(target, count);
		} else {
			const char* base = static_cast<const char*>(descriptor) + binding.cpuOffset + metaOff;
			for (uint32_t i = 0; i < count; i++, base += stride) {
				switch (DataType) {
					case ImplicitBufferData::BufferSize:
						// These are all at the same offset so the compiler should turn this into a single load
						if (isTexelBuffer(binding.descriptorType))
							target[i] = reinterpret_cast<const MVKDescriptorMetaTexelBuffer*>(base)->size;
						else if (isImage(binding.descriptorType))
							target[i] = reinterpret_cast<const MVKDescriptorMetaImage*>(base)->size;
						else
							target[i] = reinterpret_cast<const MVKDescriptorMetaBuffer*>(base)->size;
						break;
					case ImplicitBufferData::TextureSwizzle:
						target[i] = reinterpret_cast<const MVKDescriptorMetaImage*>(base)->swizzle;
						break;
				}
			}
		}
		target += perDescCount * count;
	}
}

static void bindDescriptorSets(MVKImplicitBufferData& target,
                               MVKShaderStage stage,
                               MVKPipelineLayout* layout,
                               uint32_t firstSet, uint32_t setCount, MVKDescriptorSet*const* sets,
                               uint32_t dynamicOffsetCount, const uint32_t* dynamicOffsets) {
	[[maybe_unused]] const uint32_t* dynamicOffsetsEnd = dynamicOffsets + dynamicOffsetCount;
	VkShaderStageFlags vkStage = mvkVkShaderStageFlagBitsFromMVKShaderStage(stage);
	for (uint32_t i = 0; i < setCount; i++) {
		MVKDescriptorSet* set = sets[i];
		MVKDescriptorSetLayout* setLayout = layout->getDescriptorSetLayout(firstSet + i);
		const MVKShaderStageResourceBinding& offsets = layout->getResourceBindingOffsets(firstSet + i).stages[stage];
		const MVKShaderStageResourceBinding& stride = setLayout->totalResourceCount().stages[stage];
		uint32_t varCount = set->variableDescriptorCount;
		if (uint32_t count = setLayout->dynamicOffsetCount(varCount)) {
			if (stride.dynamicOffsetBufferIndex) {
				mvkEnsureSize(target.dynamicOffsets, offsets.dynamicOffsetBufferIndex + stride.dynamicOffsetBufferIndex);
				uint32_t* write = &target.dynamicOffsets[offsets.dynamicOffsetBufferIndex];
				for (const auto& binding : setLayout->bindings()) {
					if (!binding.perDescriptorResourceCount.dynamicOffset)
						continue;
					if (binding.stageFlags & vkStage) {
						mvkCopy(write, dynamicOffsets, binding.descriptorCount);
						write += binding.descriptorCount;
					}
					dynamicOffsets += binding.descriptorCount;
				}
			} else {
				// None of the dynamic offsets are bound to this stage
				dynamicOffsets += count;
			}
		}
		if (setLayout->argBufMode() == MVKArgumentBufferMode::Off) {
			// If we grab these now, we can be guaranteed the sets are valid
			// If we wait until draw time, we can only be guaranteed statically used sets are valid
			if (!layout->getMetalFeatures().nativeTextureSwizzle && stride.textureIndex) {
				mvkEnsureSize(target.textureSwizzles, offsets.textureIndex + stride.textureIndex);
				bindImplicitBufferData<ImplicitBufferData::TextureSwizzle>(&target.textureSwizzles[offsets.textureIndex], setLayout, set->cpuBuffer, vkStage, varCount);
			}
			if (stride.bufferIndex) {
				mvkEnsureSize(target.bufferSizes, offsets.bufferIndex + stride.bufferIndex);
				bindImplicitBufferData<ImplicitBufferData::BufferSize>(&target.bufferSizes[offsets.bufferIndex], setLayout, set->cpuBuffer, vkStage, varCount);
			}
		}
	}
	assert(dynamicOffsets == dynamicOffsetsEnd && "All dynamic offsets should have been used, and no more than that");
}

static void bindImmediateData(id<MTLCommandEncoder> encoder,
                              MVKCommandEncoder& mvkEncoder,
                              const uint8_t* data, size_t size,
                              uint32_t idx,
                              const MVKResourceBinder& RESTRICT binder) {
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
                              const MVKResourceBinder& RESTRICT binder) {
	bindImmediateData(encoder, mvkEncoder, reinterpret_cast<const uint8_t*>(data.data()), data.byteSize(), idx, binder);
}

/** Updates a value at the given index in the given vector, resizing if needed. */
template<class V>
static void updateImplicitBuffer(V &contents, uint32_t index, uint32_t value) {
	if (index >= contents.size()) { contents.resize(index + 1); }
	contents[index] = value;
}

static constexpr bool isUseResource(MVKDescriptorBindOperationCode op) {
	switch (op) {
		case MVKDescriptorBindOperationCode::UseBufferWithLiveCheck:
		case MVKDescriptorBindOperationCode::UseTextureWithLiveCheck:
		case MVKDescriptorBindOperationCode::UseResource:
			return true;
		default:
			return false;
	}
}

template <MVKDescriptorBindOperationCode Op>
static void executeBindOp(id<MTLCommandEncoder> encoder,
                          MVKCommandEncoder& mvkEncoder,
                          const char* src, uint32_t count, size_t stride,
                          uint32_t target, const uint32_t* dynOffsets,
                          MVKResourceUsageStages useResourceStage,
                          MVKStageResourceBits& exists,
                          MVKStageResourceBindings& bindings,
                          const MVKResourceBinder& RESTRICT binder) {
	if (Op == MVKDescriptorBindOperationCode::BindBytes) {
		MVKStageResourceBindings::Buffer buffer = { reinterpret_cast<id<MTLBuffer>>(src), 0 };
		if (!exists.buffers.get(target) || bindings.buffers[target].buffer != buffer.buffer) {
			exists.buffers.set(target);
			bindings.buffers[target] = buffer;
			bindImmediateData(encoder, mvkEncoder, reinterpret_cast<const uint8_t*>(src), count, target, binder);
		}
		return;
	}
	MVKDevice* dev = mvkEncoder.getDevice();
	for (uint32_t i = 0; i < count; i++, src += stride) {
		id resource = *reinterpret_cast<const id*>(src);
		switch (Op) {
			case MVKDescriptorBindOperationCode::BindBytes:
				assert(0); // Handled above
				break;
			case MVKDescriptorBindOperationCode::BindBuffer:
			case MVKDescriptorBindOperationCode::BindBufferDynamic:
			case MVKDescriptorBindOperationCode::BindBufferWithLiveCheck:
			case MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck: {
				static_assert(offsetof(MVKCPUDescriptorOneID2Meta, offset) == offsetof(MVKCPUDescriptorOneID2Meta, a) + sizeof(id), "For the pointer arithmetic below");
				static_assert(offsetof(MVKCPUDescriptorTwoID2Meta, offset) == offsetof(MVKCPUDescriptorTwoID2Meta, b) + sizeof(id), "For the pointer arithmetic below");
				uint64_t offset = *reinterpret_cast<const uint64_t*>(src + sizeof(id));
				if (Op == MVKDescriptorBindOperationCode::BindBufferDynamic || Op == MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck)
					offset += dynOffsets[i];
				if ((Op == MVKDescriptorBindOperationCode::BindBufferWithLiveCheck || Op == MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck) && resource) {
					id<MTLBuffer> buffer = resource;
					if (exists.buffers.get(target + i) && bindings.buffers[target + i].buffer == buffer) {
						if (offset != bindings.buffers[target + i].offset) {
							bindings.buffers[target + i].offset = offset;
							binder.setBufferOffset(encoder, offset, target + i);
						}
					} else if (auto live = dev->getLiveResources().isLive(buffer)) {
						exists.buffers.set(target + i);
						bindings.buffers[target + i] = { buffer, offset };
						binder.setBuffer(encoder, buffer, offset, target + i);
					}
				} else {
					bindBuffer(encoder, static_cast<id<MTLBuffer>>(resource), offset, target + i, exists, bindings, binder);
				}
				break;
			}

			case MVKDescriptorBindOperationCode::BindTexture:
				bindTexture(encoder, static_cast<id<MTLTexture>>(resource), target + i, exists, bindings, binder);
				break;

			case MVKDescriptorBindOperationCode::BindTextureWithLiveCheck:
				if (id<MTLTexture> tex = resource) {
					if (exists.textures.get(target + i) && bindings.textures[target + i] == resource) {
						// Already bound
					} else if (auto live = dev->getLiveResources().isLive(tex)) {
						exists.textures.set(target + i);
						bindings.textures[target + i] = tex;
						binder.setTexture(encoder, tex, target + i);
					}
				} else {
					bindTexture(encoder, nullptr, target + i, exists, bindings, binder);
				}
				break;

			case MVKDescriptorBindOperationCode::BindSampler:
				bindSampler(encoder, static_cast<id<MTLSamplerState>>(resource), target + i, exists, bindings, binder);
				break;

			case MVKDescriptorBindOperationCode::BindSamplerWithLiveCheck:
				if (id<MTLSamplerState> samp = resource) {
					if (exists.samplers.get(target + i) && bindings.samplers[target + i] == resource) {
						// Already bound
					} else if (auto live = dev->getLiveResources().isLive(samp)) {
						exists.samplers.set(target + i);
						bindings.samplers[target + i] = samp;
						binder.setSampler(encoder, samp, target + i);
					}
				} else {
					bindSampler(encoder, nullptr, target + i, exists, bindings, binder);
				}
				break;

			case MVKDescriptorBindOperationCode::UseResource:
				if (resource)
					mvkEncoder.getState().mtlShared()._useResource.add(resource, useResourceStage, target);
				break;

			case MVKDescriptorBindOperationCode::UseBufferWithLiveCheck:
			case MVKDescriptorBindOperationCode::UseTextureWithLiveCheck:
				if (resource) {
					MVKLiveList& list = Op == MVKDescriptorBindOperationCode::UseBufferWithLiveCheck ? dev->getLiveResources().buffers : dev->getLiveResources().textures;
					if (auto live = list.isLive(resource))
						mvkEncoder.getState().mtlShared()._useResource.addImmediate(resource, encoder, binder.useResource, useResourceStage, target);
				}
				break;
		}
	}
}

static void executeBindOps(id<MTLCommandEncoder> encoder,
                           MVKCommandEncoder& mvkEncoder,
                           const MVKVulkanCommonEncoderState& common,
                           const MVKImplicitBufferData& implicitBufferData,
                           MVKArrayRef<const MVKDescriptorBindOperation> ops,
                           MVKResourceUsageStages useResourceStage,
                           MVKStageResourceBits& exists,
                           MVKStageResourceBindings& bindings,
                           const MVKResourceBinder& RESTRICT binder) {
	bool didUseResource = false;
	for (const MVKDescriptorBindOperation& op : ops) {
		MVKDescriptorSet* set = common._descriptorSets[op.set];
		uint32_t target = op.target;
		MVKDescriptorSetLayout* setLayout = common._layout->getDescriptorSetLayout(op.set);
		const MVKDescriptorBinding& binding = setLayout->bindings()[op.bindingIdx];
		const char* src = set->cpuBuffer + binding.cpuOffset + op.offset();
		const uint32_t* dynOffs = implicitBufferData.dynamicOffsets.data() + op.target2;
		uint32_t count = binding.isVariable() ? set->variableDescriptorCount : binding.descriptorCount;
		size_t stride = descriptorCPUSize(binding.cpuLayout);

		if (isUseResource(op.opcode)) {
			// Unlike binds, useResource can't be undone by binding something else
			// So we can store a list of which resources have been used in a bit array and use that to early exit on repeat binds
			// Some resources (e.g. multi-planar textures) can require multiple bind ops to fully bind, mark in a separate pass after all bind ops have executed
			if (bindings.descriptorSetResourceUse[op.set].get(op.bindingIdx))
				continue;
			didUseResource = true;
		}

		switch (op.opcode) {
#define CASE(x) case MVKDescriptorBindOperationCode::x: \
				executeBindOp<MVKDescriptorBindOperationCode::x>( \
					encoder, mvkEncoder, src, count, stride, target, dynOffs, useResourceStage, exists, bindings, binder); \
				break;
			CASE(BindBytes)
			CASE(BindBuffer)
			CASE(BindBufferDynamic)
			CASE(BindTexture)
			CASE(BindSampler)
			CASE(BindBufferWithLiveCheck)
			CASE(BindBufferDynamicWithLiveCheck)
			CASE(BindTextureWithLiveCheck)
			CASE(BindSamplerWithLiveCheck)
			CASE(UseResource)
			CASE(UseBufferWithLiveCheck)
			CASE(UseTextureWithLiveCheck)
#undef CASE
			case MVKDescriptorBindOperationCode::BindImmutableSampler: {
				MVKSampler*const* samplers = &setLayout->immutableSamplers()[binding.immSamplerIndex];
				for (uint32_t i = 0; i < count; i++)
					bindSampler(encoder, samplers[i]->getMTLSamplerState(), target + i, exists, bindings, binder);
				break;
			}
		}
	}

	if (didUseResource) {
		for (const MVKDescriptorBindOperation& op : ops) {
			if (isUseResource(op.opcode) && !bindings.descriptorSetResourceUse[op.set].get(op.bindingIdx))
				bindings.descriptorSetResourceUse[op.set].set(op.bindingIdx);
		}
	}
}

template <typename T, int N>
static MVKArrayRef<const T> getImplicitBindingData(const MVKSmallVector<T, N>& data, size_t limit) {
	return MVKArrayRef(data.data(), std::min(data.size(), limit));
}

static MVKResourceUsageStages getUseResourceStage(MVKMetalGraphicsStage stage) {
	// The single-stage enums are the same
	return static_cast<MVKResourceUsageStages>(stage);
}

/** Check if `add` is a subset of `current` */
static bool isCompatible(MVKResourceUsageStages current, MVKResourceUsageStages add) {
	if (current == add)
		return true;
	if (current == MVKResourceUsageStages::All)
		return true;
	return false;
}

static MVKResourceUsageStages combineStages(MVKResourceUsageStages a, MVKResourceUsageStages b) {
	if (a == b)
		return a;
	return MVKResourceUsageStages::All;
}

static void bindMetalResources(id<MTLCommandEncoder> encoder,
                               MVKCommandEncoder& mvkEncoder,
                               const MVKVulkanCommonEncoderState& common,
                               const MVKPipelineStageResourceInfo& resources,
                               const MVKImplicitBufferData& implicitBufferData,
                               const uint8_t* pushConstants,
                               MVKShaderStage vkStage,
                               MVKResourceUsageStages useResourceStage,
                               MVKStageResourceBits& exists,
                               MVKStageResourceBindings& bindings,
                               const MVKResourceBinder& RESTRICT binder) {
	// Clear descriptor set resource use bitarray for new sets and bind them
	MVKStaticBitSet<kMVKMaxDescriptorSetCount> setsNeeded = resources.resources.descriptorSetData.clearingAllIn(exists.descriptorSetData);
	exists.descriptorSetData |= resources.resources.descriptorSetData;
	for (size_t idx : setsNeeded) {
		MVKDescriptorSet* set = common._descriptorSets[idx];
		const MVKDescriptorSetLayout* layout = common._layout->getDescriptorSetLayout(idx);
		bindings.descriptorSetResourceUse[idx].resizeAndClear(layout->bindings().size());
		bindBuffer(encoder, set->gpuBufferObject, set->gpuBufferOffset, idx, exists, bindings, binder);
	}

	executeBindOps(encoder, mvkEncoder, common, implicitBufferData, resources.bindScript.ops.contents(), useResourceStage, exists, bindings, binder);

	MVKMetalSharedCommandEncoderState& mtlShared = mvkEncoder.getState().mtlShared();
	if (resources.usesPhysicalStorageBufferAddresses && !isCompatible(mtlShared._gpuAddressableResourceStages, useResourceStage)) {
		if (mtlShared._gpuAddressableResourceStages == MVKResourceUsageStages::None)
			mtlShared._gpuAddressableResourceStages = useResourceStage;
		else
			mtlShared._gpuAddressableResourceStages = combineStages(mtlShared._gpuAddressableResourceStages, useResourceStage);
		mvkEncoder.getDevice()->encodeGPUAddressableBuffers(mtlShared._useResource, useResourceStage);
	}

	const MVKShaderStageResourceBinding& resourceCounts = common._layout->getResourceCounts().stages[vkStage];
	for (MVKImplicitBuffer buffer : resources.implicitBuffers.needed & MVKNonVolatileImplicitBuffers) {
		assert(buffer < static_cast<MVKImplicitBuffer>(MVKNonVolatileImplicitBuffer::Count));
		MVKNonVolatileImplicitBuffer nvbuffer = static_cast<MVKNonVolatileImplicitBuffer>(buffer);
		uint32_t idx = resources.implicitBuffers.ids[buffer];
		if (exists.buffers.get(idx) && bindings.buffers[idx] == MVKStageResourceBindings::ImplicitBuffer(buffer))
			continue;
		if (bindings.implicitBufferIndices[nvbuffer] != idx) {
			// Index is changing, invalidate the old buffer since it will no longer get updated by other invalidations
			uint32_t oldIndex = bindings.implicitBufferIndices[nvbuffer];
			bindings.implicitBufferIndices[nvbuffer] = idx;
			if (bindings.buffers[oldIndex] == MVKStageResourceBindings::ImplicitBuffer(buffer))
				bindings.buffers[oldIndex] = MVKStageResourceBindings::InvalidBuffer();
		}
		exists.buffers.set(resources.implicitBuffers.ids[buffer]);
		bindings.buffers[idx] = MVKStageResourceBindings::ImplicitBuffer(buffer);
		switch (nvbuffer) {
			case MVKNonVolatileImplicitBuffer::PushConstant:
				bindImmediateData(encoder, mvkEncoder, pushConstants, common._layout->getPushConstantsLength(), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::Swizzle:
				bindImmediateData(encoder, mvkEncoder, getImplicitBindingData(implicitBufferData.textureSwizzles, resourceCounts.textureIndex), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::BufferSize:
				bindImmediateData(encoder, mvkEncoder, getImplicitBindingData(implicitBufferData.bufferSizes, resourceCounts.bufferIndex), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::DynamicOffset:
				bindImmediateData(encoder, mvkEncoder, getImplicitBindingData(implicitBufferData.dynamicOffsets, resourceCounts.dynamicOffsetBufferIndex), idx, binder);
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
	for (MVKImplicitBuffer buffer : resources.implicitBuffers.needed.removingAll(MVKNonVolatileImplicitBuffers)) {
		// Mark needed volatile implicit buffers used in buffer tracking, they'll get set during the draw
		size_t idx = resources.implicitBuffers.ids[buffer];
		exists.buffers.set(idx);
		bindings.buffers[idx] = MVKStageResourceBindings::InvalidBuffer();
	}
}

/**
 * Binds resources for running Vulkan graphics commands on a Metal render command encoder.
 *
 * Binds resources in stage `vkStage` of `vkState` to stage `mtlStage` of `mtlState`.
 */
static void bindVulkanGraphicsToMetalGraphics(
  id<MTLRenderCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKVulkanGraphicsCommandEncoderState& vkState,
  const MVKVulkanSharedCommandEncoderState& vkShared,
  MVKMetalGraphicsCommandEncoderState& mtlState,
  MVKGraphicsPipeline* pipeline,
  MVKShaderStage vkStage,
  MVKMetalGraphicsStage mtlStage) {
	bindMetalResources(encoder,
	                   mvkEncoder,
	                   vkState,
	                   pipeline->getStageResources(vkStage),
	                   vkState._implicitBufferData[vkStage],
	                   vkShared._pushConstants.data(),
	                   vkStage,
	                   getUseResourceStage(mtlStage),
	                   mtlState._exists[mtlStage],
	                   mtlState._bindings[mtlStage],
	                   MVKResourceBinder::Get(mtlStage));
}

/**
 * Binds resources for running Vulkan graphics commands on a Metal compute command encoder.
 *
 * Binds resources in stage `vkStage` of `vkState` to `mtlState`.
 */
static void bindVulkanGraphicsToMetalCompute(
  id<MTLComputeCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKVulkanGraphicsCommandEncoderState& vkState,
  const MVKVulkanSharedCommandEncoderState& vkShared,
  MVKMetalComputeCommandEncoderState& mtlState,
  MVKGraphicsPipeline* pipeline,
  MVKShaderStage vkStage) {
	bindMetalResources(encoder,
	                   mvkEncoder,
	                   vkState,
	                   pipeline->getStageResources(vkStage),
	                   vkState._implicitBufferData[vkStage],
	                   vkShared._pushConstants.data(),
	                   vkStage,
	                   MVKResourceUsageStages::Compute,
	                   mtlState._exists,
	                   mtlState._bindings,
	                   MVKResourceBinder::Compute());
}

/** Binds resources for running Vulkan compute commands on a Metal compute command encoder. */
static void bindVulkanComputeToMetalCompute(
  id<MTLComputeCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKVulkanComputeCommandEncoderState& vkState,
  const MVKVulkanSharedCommandEncoderState& vkShared,
  MVKMetalComputeCommandEncoderState& mtlState,
  MVKComputePipeline* pipeline) {
	bindMetalResources(encoder,
	                   mvkEncoder,
	                   vkState,
	                   pipeline->getStageResources(),
	                   vkState._implicitBufferData,
	                   vkShared._pushConstants.data(),
	                   kMVKShaderStageCompute,
	                   MVKResourceUsageStages::Compute,
	                   mtlState._exists,
	                   mtlState._bindings,
	                   MVKResourceBinder::Compute());
}

template <bool DynamicStride>
static void bindVertexBuffersTemplate(id<MTLCommandEncoder> encoder,
                                      const MVKVulkanGraphicsCommandEncoderState& vkState,
                                      MVKStageResourceBits& exists,
                                      MVKStageResourceBindings& bindings,
                                      const MVKVertexBufferBinder& RESTRICT binder) {
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
                              const MVKVertexBufferBinder& RESTRICT binder) {
	if (vkState._pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::VertexStride))
		bindVertexBuffersTemplate<true> (encoder, vkState, exists, bindings, binder);
	else
		bindVertexBuffersTemplate<false>(encoder, vkState, exists, bindings, binder);
}

/** If the contents of an implicit buffer changes, call this to ensure that the contents will be rebound before the next draw. */
static void invalidateImplicitBuffer(MVKStageResourceBindings& bindings, MVKNonVolatileImplicitBuffer buffer) {
	uint32_t idx = bindings.implicitBufferIndices[buffer];
	if (bindings.buffers[idx] == MVKStageResourceBindings::ImplicitBuffer(buffer)) {
		bindings.buffers[idx] = MVKStageResourceBindings::NullBuffer();
	}
}

/** If the contents of an implicit buffer changes, call this to ensure that the contents will be rebound before the next draw. */
static void invalidateImplicitBuffer(MVKMetalGraphicsCommandEncoderState& state, MVKNonVolatileImplicitBuffer buffer) {
	for (uint32_t i = 0; i < static_cast<uint32_t>(MVKMetalGraphicsStage::Count); i++) {
		MVKMetalGraphicsStage stage = static_cast<MVKMetalGraphicsStage>(i);
		invalidateImplicitBuffer(state._bindings[stage], buffer);
	}
}

/** If the contents of an implicit buffer changes, call this to ensure that the contents will be rebound before the next draw. */
static void invalidateImplicitBuffer(MVKMetalComputeCommandEncoderState& state, MVKNonVolatileImplicitBuffer buffer) {
	invalidateImplicitBuffer(state._bindings, buffer);
}

/** Invalidate the implicit buffers that depend on the contents of the bound descriptor sets. */
template <typename MTLState>
static void invalidateDescriptorSetImplicitBuffers(MTLState& state) {
	invalidateImplicitBuffer(state, MVKNonVolatileImplicitBuffer::BufferSize);
	invalidateImplicitBuffer(state, MVKNonVolatileImplicitBuffer::DynamicOffset);
	invalidateImplicitBuffer(state, MVKNonVolatileImplicitBuffer::Swizzle);
}

static bool isGraphicsStage(MVKShaderStage stage) {
	return stage < kMVKShaderStageCompute;
}

#pragma mark - MVKUseResourceHelper

static constexpr MTLResourceUsage MTLResourceUsageReadWrite = MTLResourceUsageRead | MTLResourceUsageWrite;

static bool isCompatible(MVKUseResourceHelper::ResourceInfo current, MVKUseResourceHelper::ResourceInfo add) {
	if (!current.write && add.write)
		return false;
	return isCompatible(current.stages, add.stages);
}

void MVKUseResourceHelper::add(id<MTLResource> resource, MVKResourceUsageStages stage, bool write) {
	ResourceInfo info { stage, write, true };
	auto res = used.emplace(resource, info);
	if (res.second || !isCompatible(res.first->second, info)) {
		ResourceInfo& stored = res.first->second;
		if (!res.second) {
			stored.deferred = true;
			stored.write |= info.write;
			stored.stages = combineStages(stored.stages, info.stages);
		}
		entries[stored.stages].get(stored.write).push_back(resource);
	}
}

void MVKUseResourceHelper::addImmediate(id<MTLResource> resource, id<MTLCommandEncoder> enc, MVKResourceBinder::UseResource func, MVKResourceUsageStages stage, bool write) {
	ResourceInfo info { stage, write, false };
	auto res = used.emplace(resource, info);
	if (res.second || !isCompatible(res.first->second, info)) {
		ResourceInfo& stored = res.first->second;
		if (!res.second) {
			stored.write |= info.write;
			stored.stages = combineStages(stored.stages, info.stages);
		}
		// For ordering reasons, if it's deferred, we need to do this write deferred as well.
		// Otherwise a deferred useResource for a narrower usage could overwrite this one.
		// Conveniently, if it was deferred once, it must be staying alive, so no problems there.
		if (stored.deferred)
			entries[stored.stages].get(stored.write).push_back(resource);
		else
			func(enc, resource, write ? MTLResourceUsageReadWrite : MTLResourceUsageRead, stored.stages);
	}
}

void MVKUseResourceHelper::bindAndResetGraphics(id<MTLRenderCommandEncoder> encoder) {
	// If a resource is used multiple times on different stages, it may appear in multiple lists.
	// As long as the iteration order hits stages that combine multiple render stages after the stages it combines,
	// this should be OK, as the last useResource will be the one for the most comprehensive list of stages.
	for (uint32_t i = 0; i < std::size(entries.elements); i++) {
		MVKResourceUsageStages stages = static_cast<MVKResourceUsageStages>(i);
		MTLRenderStages mtlStages = getMTLStages(stages);
		Entry& entry = entries[stages];
		if (!entry.read.empty()) {
			if ([encoder respondsToSelector:@selector(useResources:count:usage:stages:)])
				[encoder useResources:entry.read.data() count:entry.read.size() usage:MTLResourceUsageRead stages:mtlStages];
			else
				[encoder useResources:entry.read.data() count:entry.read.size() usage:MTLResourceUsageRead];
			entry.read.clear();
		}
		if (!entry.readWrite.empty()) {
			if ([encoder respondsToSelector:@selector(useResources:count:usage:stages:)])
				[encoder useResources:entry.readWrite.data() count:entry.readWrite.size() usage:MTLResourceUsageReadWrite stages:mtlStages];
			else
				[encoder useResources:entry.readWrite.data() count:entry.readWrite.size() usage:MTLResourceUsageReadWrite];
			entry.readWrite.clear();
		}
	}
}
void MVKUseResourceHelper::bindAndResetCompute(id<MTLComputeCommandEncoder> encoder) {
	Entry& entry = entries[MVKResourceUsageStages::Compute];
	if (!entry.read.empty()) {
		[encoder useResources:entry.read.data() count:entry.read.size() usage:MTLResourceUsageRead];
		entry.read.clear();
	}
	if (!entry.readWrite.empty()) {
		[encoder useResources:entry.readWrite.data() count:entry.readWrite.size() usage:MTLResourceUsageReadWrite];
		entry.readWrite.clear();
	}
	for (uint32_t i = 1; i < std::size(entries.elements); i++) {
		// Compute should never fill any but the first set
		assert(entries.elements[i].read.empty());
		assert(entries.elements[i].readWrite.empty());
	}
}

#pragma mark - MVKVulkanCommonCommandEncoderState

void MVKVulkanCommonEncoderState::ensurePushDescriptorSize(uint32_t size) {
	if (size > _pushDescData.size()) {
		_pushDescData.resize(size);
		_pushDescriptor.cpuBuffer = reinterpret_cast<char*>(_pushDescData.data());
	}
}

void MVKVulkanCommonEncoderState::setLayout(MVKPipelineLayout* layout) {
	_layout = layout;
	if (layout && layout->hasPushDescriptor()) {
		size_t idx = layout->pushDescriptor();
		_descriptorSets[idx] = &_pushDescriptor;
		MVKDescriptorSetLayout* dsl = layout->getDescriptorSetLayout(idx);
		uint32_t size = dsl->cpuSize();
		_pushDescriptor.cpuBufferSize = size;
		ensurePushDescriptorSize(size);
	}
}

MVKVulkanCommonEncoderState::MVKVulkanCommonEncoderState(const MVKVulkanCommonEncoderState& other) {
	memcpy(_descriptorSets, other._descriptorSets, sizeof(_descriptorSets));
	_pushDescriptor = other._pushDescriptor;
	setLayout(other._layout);
	memcpy(_pushDescriptor.cpuBuffer, other._pushDescriptor.cpuBuffer, _pushDescriptor.cpuBufferSize);
}

MVKVulkanCommonEncoderState& MVKVulkanCommonEncoderState::operator=(const MVKVulkanCommonEncoderState& other) {
	memmove(_descriptorSets, other._descriptorSets, sizeof(_descriptorSets));
	_pushDescriptor = other._pushDescriptor;
	setLayout(other._layout);
	memmove(_pushDescriptor.cpuBuffer, other._pushDescriptor.cpuBuffer, _pushDescriptor.cpuBufferSize);
	return *this;
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
		::bindDescriptorSets(_implicitBufferData[stage], stage, layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
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
	::bindDescriptorSets(_implicitBufferData, kMVKShaderStageCompute, layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
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
}

void MVKMetalGraphicsCommandEncoderState::bindFragmentBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index) {
	bindBuffer(encoder, buffer, offset, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindFragmentBytes(id<MTLRenderCommandEncoder> encoder, const void* data, size_t size, NSUInteger index) {
	bindBytes(encoder, data, size, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindFragmentTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
	bindTexture(encoder, texture, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindFragmentSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
	bindSampler(encoder, sampler, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index) {
	bindBuffer(encoder, buffer, offset, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexBytes(id<MTLRenderCommandEncoder> encoder, const void* data, size_t size, NSUInteger index) {
	bindBytes(encoder, data, size, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
	bindTexture(encoder, texture, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
	bindSampler(encoder, sampler, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}

void MVKMetalGraphicsCommandEncoderState::changePipeline(MVKGraphicsPipeline* from, MVKGraphicsPipeline* to) {
	_flags.remove(MVKMetalRenderEncoderStateFlag::PipelineReady);
	// Everything that was static is now dirty
	if (from) {
		markDirty(from->getStaticStateFlags());
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
  const VkRect2D* scissors) {
	if (flags.hasAny(FlagsViewportScissor)) {
		if (flags.has(MVKRenderStateFlag::Viewports) &&
		  (_numViewports != data.numViewports || !mvkAreEqual(_viewports, viewports, data.numViewports))) {
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
		  (_numScissors != data.numScissors || !mvkAreEqual(_scissors, scissors, data.numScissors))) {
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
#if MVK_XCODE_26
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
#if MVK_XCODE_26
		if (anyStateNeeded.hasAny({ MVKRenderStateFlag::DepthBounds, MVKRenderStateFlag::DepthBoundsTestEnable }) &&
		    mvkEncoder.getMetalFeatures().depthBoundsTest)
		{
			bool wasEnabled = _flags.has(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
			if (PICK_STATE(DepthBoundsTestEnable)->enable.has(MVKRenderStateEnableFlag::DepthBoundsTest)) {
				const MVKDepthBounds& src = PICK_STATE(DepthBounds)->depthBounds;
				if (!wasEnabled || !mvkAreEqual(&src, &_depthBounds)) {
					_flags.add(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
					_depthBounds = src;
					[encoder setDepthTestMinBound:src.minDepthBound maxBound:src.maxDepthBound];
				}
			} else if (wasEnabled) {
				_flags.remove(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
				[encoder setDepthTestMinBound:0.0f maxBound:1.0f];
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
  const MVKVulkanSharedCommandEncoderState& vkShared) {
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
	}

	// State
	bindState(encoder, mvkEncoder, vk);

	// Resources
	if (pipeline->isTessellationPipeline()) {
		bindVulkanGraphicsToMetalGraphics(encoder, mvkEncoder, vk, vkShared, *this, pipeline, kMVKShaderStageTessEval, MVKMetalGraphicsStage::Vertex);
	} else {
		bindVulkanGraphicsToMetalGraphics(encoder, mvkEncoder, vk, vkShared, *this, pipeline, kMVKShaderStageVertex,   MVKMetalGraphicsStage::Vertex);
		bindVertexBuffers(encoder, vk, _exists.vertex(), _bindings.vertex(), MVKVertexBufferBinder::Vertex());
	}
	bindVulkanGraphicsToMetalGraphics(encoder, mvkEncoder, vk, vkShared, *this, pipeline, kMVKShaderStageFragment, MVKMetalGraphicsStage::Fragment);
	mvkEncoder.getState().mtlShared()._useResource.bindAndResetGraphics(encoder);
}

void MVKMetalGraphicsCommandEncoderState::prepareHelperDraw(
  id<MTLRenderCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKHelperDrawState& state) {
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
	::bindBuffer(encoder, buffer, offset, index, _exists, _bindings, MVKComputeBinder());
}
void MVKMetalComputeCommandEncoderState::bindBytes(id<MTLComputeCommandEncoder> encoder, const void* data, size_t size, NSUInteger index) {
	::bindBytes(encoder, data, size, index, _exists, _bindings, MVKComputeBinder());
}
void MVKMetalComputeCommandEncoderState::bindTexture(id<MTLComputeCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
	::bindTexture(encoder, texture, index, _exists, _bindings, MVKComputeBinder());
}
void MVKMetalComputeCommandEncoderState::bindSampler(id<MTLComputeCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
	::bindSampler(encoder, sampler, index, _exists, _bindings, MVKComputeBinder());
}

void MVKMetalComputeCommandEncoderState::prepareComputeDispatch(
  id<MTLComputeCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKVulkanComputeCommandEncoderState& vk,
  const MVKVulkanSharedCommandEncoderState& vkShared) {
	MVKComputePipeline* pipeline = vk._pipeline;
	id<MTLComputePipelineState> mtlPipeline = pipeline->getPipelineState();
	if (!mtlPipeline) // Abort if pipeline could not be created.
		return;

	_vkPipeline = pipeline;

	if (_pipeline != mtlPipeline) {
		_pipeline = mtlPipeline;
		[encoder setComputePipelineState:mtlPipeline];
	}

	if (_vkStage != kMVKShaderStageCompute) {
		if (_vkStage != kMVKShaderStageCount) {
			// Switching between graphics and compute, need to invalidate implicit buffers too
			invalidateDescriptorSetImplicitBuffers(*this);
			_exists.descriptorSetData.reset();
		}
		_vkStage = kMVKShaderStageCompute;
	}

	bindVulkanComputeToMetalCompute(encoder, mvkEncoder, vk, vkShared, *this, pipeline);
	mvkEncoder.getState().mtlShared()._useResource.bindAndResetCompute(encoder);
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
		_vkPipeline = pipeline;
	}

	if (_pipeline != mtlPipeline) {
		_pipeline = mtlPipeline;
		[encoder setComputePipelineState:mtlPipeline];
	}

	if (_vkStage != stage) {
		if (_vkStage == kMVKShaderStageCompute) {
			// Switching between graphics and compute, need to invalidate implicit buffers too
			invalidateDescriptorSetImplicitBuffers(*this);
			_exists.descriptorSetData.reset();
		}
		_vkStage = stage;
	}

	bindVulkanGraphicsToMetalCompute(encoder, mvkEncoder, vk, vkShared, *this, pipeline, stage);
	if (stage == kMVKShaderStageVertex)
		bindVertexBuffers(encoder, vk, _exists, _bindings, MVKVertexBufferBinder::Compute());
	mvkEncoder.getState().mtlShared()._useResource.bindAndResetCompute(encoder);
}

void MVKMetalComputeCommandEncoderState::reset() {
	memset(this, 0, offsetof(MVKMetalComputeCommandEncoderState, MEMSET_RESET_LINE));
	_vkStage = kMVKShaderStageCount;
}

#pragma mark - MVKCommandEncoderState

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

MVKArrayRef<const MTLSamplePosition> MVKCommandEncoderState::updateSamplePositions() {
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

bool MVKCommandEncoderState::needsMetalRenderPassRestart() {
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

static void invalidateImplicitBuffer(MVKCommandEncoderState& state, VkPipelineBindPoint bindPoint, MVKNonVolatileImplicitBuffer buffer) {
	state.applyToActiveMTLState(bindPoint, [buffer](auto& mtl){ invalidateImplicitBuffer(mtl, buffer); });
}

void MVKCommandEncoderState::bindGraphicsPipeline(MVKGraphicsPipeline* pipeline) {
	_mtlGraphics.changePipeline(_vkGraphics._pipeline, pipeline);
	_vkGraphics._pipeline = pipeline;
	MVKPipelineLayout* layout = pipeline->getLayout();
	if (_vkGraphics._layout != layout) {
		if (!_vkGraphics._layout || _vkGraphics._layout->getPushConstantsLength() < layout->getPushConstantsLength()) {
			mvkEnsureSize(_vkShared._pushConstants, layout->getPushConstantsLength());
			invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_GRAPHICS, MVKNonVolatileImplicitBuffer::PushConstant);
		}
		_vkGraphics.setLayout(layout);
	}
}

void MVKCommandEncoderState::bindComputePipeline(MVKComputePipeline* pipeline) {
	_vkCompute._pipeline = pipeline;
	MVKPipelineLayout* layout = pipeline->getLayout();
	if (_vkCompute._layout != layout) {
		if (!_vkCompute._layout || _vkCompute._layout->getPushConstantsLength() < layout->getPushConstantsLength()) {
			mvkEnsureSize(_vkShared._pushConstants, layout->getPushConstantsLength());
			invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_COMPUTE, MVKNonVolatileImplicitBuffer::PushConstant);
		}
		_vkCompute.setLayout(layout);
	}
}

void MVKCommandEncoderState::pushConstants(uint32_t offset, uint32_t size, const void* data) {
	mvkEnsureSize(_vkShared._pushConstants, offset + size);
	memcpy(_vkShared._pushConstants.data() + offset, data, size);
	invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_ALL, MVKNonVolatileImplicitBuffer::PushConstant);
}

void MVKCommandEncoderState::bindDescriptorSets(
  VkPipelineBindPoint bindPoint,
  MVKPipelineLayout* layout,
  uint32_t firstSet,
  uint32_t setCount,
  MVKDescriptorSet*const* sets,
  uint32_t dynamicOffsetCount,
  const uint32_t* dynamicOffsets) {
	auto affected = MVKStaticBitSet<kMVKMaxDescriptorSetCount>::range(firstSet, firstSet + setCount);
	applyToActiveMTLState(bindPoint, [affected](auto& mtl){
		invalidateDescriptorSetImplicitBuffers(mtl);
		for (MVKStageResourceBits& exists : mtl.exists()) {
			exists.descriptorSetData.clearAllIn(affected);
		}
	});
	if (bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS) {
		_vkGraphics.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
	} else if (bindPoint == VK_PIPELINE_BIND_POINT_COMPUTE) {
		_vkCompute.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
	}
}

MVKVulkanCommonEncoderState* MVKCommandEncoderState::getVkEncoderState(VkPipelineBindPoint bindPoint) {
	switch (bindPoint) {
		case VK_PIPELINE_BIND_POINT_GRAPHICS: return &_vkGraphics;
		case VK_PIPELINE_BIND_POINT_COMPUTE:  return &_vkCompute;
		default: return nullptr;
	}
}

void MVKCommandEncoderState::pushDescriptorSet(VkPipelineBindPoint bindPoint, MVKPipelineLayout* layout, uint32_t set, uint32_t writeCount, const VkWriteDescriptorSet* writes) {
	assert(layout->pushDescriptor() == set);
	if (MVKVulkanCommonEncoderState* state = getVkEncoderState(bindPoint)) [[likely]] {
		MVKDescriptorSetLayout* dsl = layout->getDescriptorSetLayout(set);
		state->ensurePushDescriptorSize(dsl->cpuSize());
		mvkPushDescriptorSet(state->_pushDescriptor.cpuBuffer, dsl, writeCount, writes);
	}
}

void MVKCommandEncoderState::pushDescriptorSet(MVKDescriptorUpdateTemplate* updateTemplate, MVKPipelineLayout* layout, uint32_t set, const void* data) {
	assert(layout->pushDescriptor() == set);
	if (MVKVulkanCommonEncoderState* state = getVkEncoderState(updateTemplate->getBindPoint())) [[likely]] {
		MVKDescriptorSetLayout* dsl = layout->getDescriptorSetLayout(set);
		state->ensurePushDescriptorSize(dsl->cpuSize());
		mvkPushDescriptorSetTemplate(state->_pushDescriptor.cpuBuffer, dsl, updateTemplate, data);
	}
}

void MVKCommandEncoderState::bindVertexBuffers(uint32_t firstBinding, MVKArrayRef<const MVKVertexMTLBufferBinding> buffers) {
	mvkCopy(&_vkGraphics._vertexBuffers[firstBinding], buffers.data(), buffers.size());
}

void MVKCommandEncoderState::bindIndexBuffer(const MVKIndexMTLBufferBinding& buffer) {
	_vkGraphics._indexBuffer = buffer;
}

void MVKCommandEncoderState::offsetZeroDivisorVertexBuffers(MVKCommandEncoder& mvkEncoder, MVKGraphicsStage stage, MVKGraphicsPipeline* pipeline, uint32_t firstInstance) {
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

void MVKCommandEncoderState::beginGraphicsEncoding(VkSampleCountFlags sampleCount) {
	_mtlGraphics.reset(sampleCount);
	_mtlShared.reset();
	_mtlActiveEncoder = CommandEncoderClass::Graphics;
}

void MVKCommandEncoderState::beginComputeEncoding() {
	_mtlCompute.reset();
	_mtlShared.reset();
	_mtlActiveEncoder = CommandEncoderClass::Compute;
}

template <typename Fn>
void MVKCommandEncoderState::applyToActiveMTLState(VkPipelineBindPoint bindPoint, Fn&& fn) {
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

/// Used to indicate that the current metal visibility result mode needs to be set regardless of what mode is wanted
/// (when visibility queries are currently active but on the wrong index).
static constexpr uint8_t VisibilityResultModeNeedsUpdate = 0xff;

static bool isMetalVisibilityActive(uint8_t mode) {
	// return false for both Disabled and NeedsUpdate
	static_assert(static_cast<int8_t>(MTLVisibilityResultModeDisabled) <= 0);
	static_assert(static_cast<int8_t>(VisibilityResultModeNeedsUpdate) <= 0);
	static_assert(static_cast<int8_t>(MTLVisibilityResultModeBoolean)  > 0);
	static_assert(static_cast<int8_t>(MTLVisibilityResultModeCounting) > 0);
	return static_cast<int8_t>(mode) > 0;
}

struct alignas(8) QueryResultOffsets {
	uint32_t dst;
	uint32_t src;
};

// Metal resets the query counter at a render pass boundary, so copy results to the query pool's accumulation buffer.
// Don't copy occlusion info until after rasterization, as Metal renderpasses can be ended prematurely during tessellation.
void MVKOcclusionQueryCommandEncoderState::endMetalRenderPass(MVKCommandEncoder* cmdEncoder) {
	nextMetalQuery(cmdEncoder);
	_metalVisibilityResultMode = MTLVisibilityResultModeDisabled;
	_lastFenceUpdate = nullptr;
	if (!_shouldAccumulate || _mtlRenderPassQueries.empty()) { return; }

	_shouldAccumulate = false;
	cmdEncoder->_pEncodingContext->firstVisibilityResultOffsetInRenderPass = cmdEncoder->_pEncodingContext->visibilityResultBuffer.offset();
	const MVKVisibilityBuffer& vizBuff = cmdEncoder->_pEncodingContext->visibilityResultBuffer;
	if (!vizBuff.buffer()) {
		assert(0 && "Has visibility results but no buffer to write them to");
		_mtlRenderPassQueries.clear();
		return;
	}

	id<MTLComputePipelineState> mtlAccumState = cmdEncoder->getCommandEncodingPool()->getAccumulateOcclusionQueryResultsMTLComputePipelineState();
	id<MTLComputeCommandEncoder> mtlAccumEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseAccumOcclusionQuery);
	for (uint32_t i = 0; i < _numCopyFences; i++) {
		[mtlAccumEncoder waitForFence:_copyFences[i].write];
		[mtlAccumEncoder updateFence:_copyFences[i].read];
	}
	_numCopyFences = 0;
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	state.bindPipeline(mtlAccumEncoder, mtlAccumState);
	state.bindBuffer(mtlAccumEncoder, vizBuff.buffer(), 0, 2);
	static constexpr size_t max_size = 4096 / sizeof(QueryResultOffsets);
	QueryResultOffsets offsets[std::min(max_size, _mtlRenderPassQueries.size())];
	uint32_t idx = 0;
	uint32_t executionWidth = static_cast<uint32_t>([mtlAccumState threadExecutionWidth]);
	const auto& mtlFeats = cmdEncoder->getMetalFeatures();
	for (auto cur = _mtlRenderPassQueries.begin(), end = _mtlRenderPassQueries.end(); cur < end; cur++) {
		offsets[idx].dst = cur->query;
		offsets[idx].src = cur->visibilityBufferOffset / kMVKQuerySlotSizeInBytes;
		idx++;
		auto next = cur + 1;
		if (next == end || idx >= max_size || next->queryPool != cur->queryPool) {
			// Send what we've collected
			uint32_t count = idx;
			idx = 0;
			state.bindBuffer(mtlAccumEncoder, cur->queryPool->getVisibilityResultMTLBuffer(), 0, 1);
			MTLSize tgsize = MTLSizeMake(executionWidth, 1, 1);
			if (mtlFeats.nonUniformThreadgroups) {
				state.bindBytes(mtlAccumEncoder, offsets, count * sizeof(QueryResultOffsets), 0);
				[mtlAccumEncoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:tgsize];
			} else {
				uint32_t rest = 0;
				if (count >= executionWidth) {
					uint32_t first = count / executionWidth;
					rest = first * executionWidth;
					count -= rest;
					state.bindBytes(mtlAccumEncoder, offsets, rest * sizeof(QueryResultOffsets), 0);
					[mtlAccumEncoder dispatchThreadgroups:MTLSizeMake(first, 1, 1) threadsPerThreadgroup:tgsize];
				}
				if (count) {
					state.bindBytes(mtlAccumEncoder, offsets + rest, count * sizeof(QueryResultOffsets), 0);
					[mtlAccumEncoder dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(count, 1, 1)];
				}
			}
		}
	}
	_mtlRenderPassQueries.clear();
}

// The Metal visibility buffer has a finite size, and on some Metal platforms (looking at you M1),
// query offsets cannnot be reused with the same MTLCommandBuffer. If enough occlusion queries are
// begun within a single MTLCommandBuffer, it may exhaust the visibility buffer. If that occurs,
// report an error and disable further visibility tracking for the remainder of the MTLCommandBuffer.
// In most cases, a MTLCommandBuffer corresponds to a Vulkan command submit (VkSubmitInfo),
// and so the error text is framed in terms of the Vulkan submit.
void MVKOcclusionQueryCommandEncoderState::beginOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
	assert(!_currentPool && "Shouldn't have active query when beginning a new one!");
	bool shouldCount = mvkAreAllFlagsEnabled(flags, VK_QUERY_CONTROL_PRECISE_BIT);
	_currentVisibilityResultMode = shouldCount ? MTLVisibilityResultModeCounting : MTLVisibilityResultModeBoolean;
	_currentPool = pQueryPool;
	_currentQueryIndex = query;
}

void MVKOcclusionQueryCommandEncoderState::endOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
	assert(_currentPool == pQueryPool && _currentQueryIndex == query && "Ended query that wasn't active!");
	_shouldAccumulate = true;
	if (cmdEncoder->_mtlRenderEncoder) {
		nextMetalQuery(cmdEncoder);
		_metalVisibilityResultMode = VisibilityResultModeNeedsUpdate;
	} else {
		// Called outside of a render pass
		// Run accumulation immediately
		endMetalRenderPass(cmdEncoder);
	}
	_currentVisibilityResultMode = MTLVisibilityResultModeDisabled;
	_currentPool = nullptr;
}

void MVKOcclusionQueryCommandEncoderState::nextMetalQuery(MVKCommandEncoder* cmdEncoder) {
	if (!isMetalVisibilityActive(_metalVisibilityResultMode))
		return; // No draws were run
	MVKVisibilityBuffer& buffer = cmdEncoder->_pEncodingContext->visibilityResultBuffer;
	if (_mtlRenderPassQueries.empty() || buffer.isFirstWithCurrentFence()) {
		assert(_numCopyFences < std::size(_copyFences));
		if (_numCopyFences < std::size(_copyFences)) {
			auto current = buffer.currentFence();
			_copyFences[_numCopyFences++] = { current.read, current.write };
		}
	}
	_mtlRenderPassQueries.emplace_back(_currentPool, _currentQueryIndex, buffer.offset());
	uint32_t offset = buffer.advanceOffset();
	if (offset == cmdEncoder->_pEncodingContext->firstVisibilityResultOffsetInRenderPass) {
		// We went through a whole visibility buffer in one render pass!  Guess we need to accumulate now...
		cmdEncoder->encodeStoreActions(true);
		cmdEncoder->endMetalRenderEncoding();
		_shouldAccumulate = true;
		endMetalRenderPass(cmdEncoder);
	} else if (_numCopyFences >= 2) {
		// Getting pretty full, accumulate soon so we don't have to split a render pass if possible
		_shouldAccumulate = true;
	}
}

void MVKOcclusionQueryCommandEncoderState::prepareHelperDraw(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder* mvkEncoder) {
	if (_metalVisibilityResultMode != MTLVisibilityResultModeDisabled) {
		nextMetalQuery(mvkEncoder);
		_metalVisibilityResultMode = MTLVisibilityResultModeDisabled;
		[encoder setVisibilityResultMode:MTLVisibilityResultModeDisabled
		                          offset:mvkEncoder->_pEncodingContext->visibilityResultBuffer.offset()];
	}
}

void MVKOcclusionQueryCommandEncoderState::encode(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder* mvkEncoder) {
	auto current = static_cast<MTLVisibilityResultMode>(_currentVisibilityResultMode);
	if (_metalVisibilityResultMode == current)
		return;
	MVKVisibilityBuffer& buffer = mvkEncoder->_pEncodingContext->visibilityResultBuffer;
	_metalVisibilityResultMode = current;
	[encoder setVisibilityResultMode:current
	                          offset:buffer.offset()];
	if (current != MTLVisibilityResultModeDisabled) {
		auto fence = buffer.currentFence();
		if (_lastFenceUpdate != fence.write) {
			_lastFenceUpdate = fence.write;
			[encoder waitForFence:fence.prevRead beforeStages:MTLRenderStageFragment];
			[encoder  updateFence:fence.write     afterStages:MTLRenderStageFragment];
		}
	}
}
