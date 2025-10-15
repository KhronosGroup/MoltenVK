/*
 * MVKDescriptorSet.mm
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

#include "MVKDescriptorSet.h"
#include "MVKBuffer.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandEncoderState.h"
#include "MVKPipeline.h"
#include "MVKInlineObjectConstructor.h"
#include "MVKInstance.h"
#include "MVKImage.h"
#include "MVKOSExtensions.h"
#include <sstream>

static constexpr uint32_t alignDescriptorOffset(uint32_t offset, uint32_t align) {
	return (offset + align - 1) & ~(align - 1);
}

static constexpr uint32_t descriptorCPUAlign(MVKDescriptorCPULayout layout) {
	switch (layout) {
		case MVKDescriptorCPULayout::None:
		case MVKDescriptorCPULayout::InlineData:
			return 1;
		case MVKDescriptorCPULayout::OneID:
			return alignof(id);
		case MVKDescriptorCPULayout::OneIDMeta:
		case MVKDescriptorCPULayout::TwoIDMeta:
		case MVKDescriptorCPULayout::OneID2Meta:
		case MVKDescriptorCPULayout::TwoID2Meta:
			return alignof(uint64_t);
	}
}

/**
 * The number of bytes to advance when moving to the next descriptor, per descriptor element.
 * (Note that OutlinedData is one element in the descriptor regardless of descriptorCount.)
 */
static constexpr uint32_t descriptorGPUSizeMetal3(MVKDescriptorGPULayout layout) {
	switch (layout) {
		case MVKDescriptorGPULayout::None:          return 0;
		case MVKDescriptorGPULayout::Texture:       return sizeof(uint64_t);
		case MVKDescriptorGPULayout::Sampler:       return sizeof(uint64_t);
		case MVKDescriptorGPULayout::Buffer:        return sizeof(uint64_t);
		case MVKDescriptorGPULayout::InlineData:    return 1;
		case MVKDescriptorGPULayout::TexBufSoA:     return sizeof(uint64_t) * 2;
		case MVKDescriptorGPULayout::TexSampSoA:    return sizeof(uint64_t) * 2;
		case MVKDescriptorGPULayout::Tex2SampSoA:   return sizeof(uint64_t) * 3;
		case MVKDescriptorGPULayout::Tex3SampSoA:   return sizeof(uint64_t) * 4;
		case MVKDescriptorGPULayout::BufferAuxSize: return sizeof(uint64_t);
		case MVKDescriptorGPULayout::OutlinedData:  return sizeof(uint64_t);
	}
}

/** The number of bytes to advance for a descriptor with the given layout and descriptor count. */
static constexpr uint32_t descriptorGPUSizeMetal3(MVKDescriptorGPULayout layout, uint32_t descriptorCount) {
	return (layout == MVKDescriptorGPULayout::OutlinedData ? 1 : descriptorCount) * descriptorGPUSizeMetal3(layout);
}

/** The number of bytes to advance when moving within a descriptor. */
static constexpr uint32_t descriptorGPUStrideMetal3(MVKDescriptorGPULayout layout) {
	// For SoA descriptors, the stride is one descriptor even though the size is multiple.
	// For OutlinedData, stride is for the contents of the descriptor, while size is for the pointer to those contents.
	switch (layout) {
		case MVKDescriptorGPULayout::None:          return 0;
		case MVKDescriptorGPULayout::Texture:       return sizeof(uint64_t);
		case MVKDescriptorGPULayout::Sampler:       return sizeof(uint64_t);
		case MVKDescriptorGPULayout::Buffer:        return sizeof(uint64_t);
		case MVKDescriptorGPULayout::InlineData:    return 1;
		case MVKDescriptorGPULayout::TexBufSoA:     return sizeof(uint64_t);
		case MVKDescriptorGPULayout::TexSampSoA:    return sizeof(uint64_t);
		case MVKDescriptorGPULayout::Tex2SampSoA:   return sizeof(uint64_t);
		case MVKDescriptorGPULayout::Tex3SampSoA:   return sizeof(uint64_t);
		case MVKDescriptorGPULayout::BufferAuxSize: return sizeof(uint64_t);
		case MVKDescriptorGPULayout::OutlinedData:  return 1;
	}
}

static constexpr uint32_t descriptorGPUBindingCount(MVKDescriptorGPULayout layout) {
	switch (layout) {
		case MVKDescriptorGPULayout::None:          return 0;
		case MVKDescriptorGPULayout::Texture:       return 1;
		case MVKDescriptorGPULayout::Sampler:       return 1;
		case MVKDescriptorGPULayout::Buffer:        return 1;
		case MVKDescriptorGPULayout::InlineData:    return 1;
		case MVKDescriptorGPULayout::TexBufSoA:     return 2;
		case MVKDescriptorGPULayout::TexSampSoA:    return 2;
		case MVKDescriptorGPULayout::Tex2SampSoA:   return 3;
		case MVKDescriptorGPULayout::Tex3SampSoA:   return 4;
		case MVKDescriptorGPULayout::BufferAuxSize: return 1;
		case MVKDescriptorGPULayout::OutlinedData:  return 1;
	}
}

static constexpr uint32_t descriptorGPUBindingStride(MVKDescriptorGPULayout layout) {
	// For SoA descriptors, the stride is one descriptor even though the size is multiple
	switch (layout) {
		case MVKDescriptorGPULayout::None:          return 0;
		case MVKDescriptorGPULayout::Texture:       return 1;
		case MVKDescriptorGPULayout::Sampler:       return 1;
		case MVKDescriptorGPULayout::Buffer:        return 1;
		case MVKDescriptorGPULayout::InlineData:    return 1;
		case MVKDescriptorGPULayout::TexBufSoA:     return 1;
		case MVKDescriptorGPULayout::TexSampSoA:    return 1;
		case MVKDescriptorGPULayout::Tex2SampSoA:   return 1;
		case MVKDescriptorGPULayout::Tex3SampSoA:   return 1;
		case MVKDescriptorGPULayout::BufferAuxSize: return 1;
		case MVKDescriptorGPULayout::OutlinedData:  return 1;
	}
}

static uint32_t descriptorGPUAlignMetal3(MVKDescriptorGPULayout layout) {
	switch (layout) {
		case MVKDescriptorGPULayout::None:
			return 1;
		case MVKDescriptorGPULayout::InlineData:
			return 4;
		default:
			return sizeof(uint64_t); // Not alignof, the GPU's alignment requirement may be higher than the CPU's
	}
}

static bool canUseImmutableSamplers(VkDescriptorType type) {
	switch (type) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return true;
		default:
			return false;
	}
}

static bool needsDynamicOffset(VkDescriptorType type) {
	return type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC || type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC;
}

static bool needsAuxOffset(MVKDescriptorGPULayout layout) {
	switch (layout) {
		case MVKDescriptorGPULayout::BufferAuxSize:
		case MVKDescriptorGPULayout::OutlinedData:
			return true;
		default:
			return false;
	}
}

static bool needsAuxBuf(MVKDescriptorGPULayout layout) {
	return layout == MVKDescriptorGPULayout::BufferAuxSize;
}

/** Selects an argument buffer mode for the given device.  Descriptor sets on the device may use this mode or Off, but not any others. */
static MVKArgumentBufferMode pickArgumentBufferMode(MVKDevice* dev) {
	if (dev->getPhysicalDevice()->isUsingMetalArgumentBuffers()) {
		if (dev->getPhysicalDevice()->getMetalFeatures()->needsArgumentBufferEncoders)
			return MVKArgumentBufferMode::ArgEncoder;
		else
			return MVKArgumentBufferMode::Metal3;
	}
	return MVKArgumentBufferMode::Off;
}

/** Returns true if the device may disable argument buffers for non-push descriptor sets. */
static bool mayDisableArgumentBuffers(MVKDevice* dev) {
#if MVK_IOS_OR_TVOS
	// iOS Tier 1 argument buffers do not support writable images.
	return dev->getPhysicalDevice()->getMetalFeatures()->argumentBuffersTier < MTLArgumentBuffersTier2;
#else
	return false;
#endif
}

/** Selects an argument buffer mode for the given device descriptor layout. */
static MVKArgumentBufferMode pickArgumentBufferMode(MVKDevice* dev, const VkDescriptorSetLayoutCreateInfo* pCreateInfo) {
	MVKArgumentBufferMode mode = pickArgumentBufferMode(dev);
	if (mode == MVKArgumentBufferMode::Off) // The following checks only switch argument buffers off, so we can skip them if they're already off.
		return mode;
	// Push descriptors are always binding-based
	if (mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT))
		return MVKArgumentBufferMode::Off;
#if MVK_IOS_OR_TVOS
	// iOS Tier 1 argument buffers do not support writable images.
	if (dev->getPhysicalDevice()->getMetalFeatures()->argumentBuffersTier < MTLArgumentBuffersTier2) {
		for (uint32_t i = 0; i < pCreateInfo->bindingCount; i++) {
			const VkDescriptorSetLayoutBinding& bind = pCreateInfo->pBindings[i];
			if (bind.descriptorCount == 0)
				continue;
			if (bind.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE || bind.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER)
				return MVKArgumentBufferMode::Off;
		}
	}
#endif
	return mode;
}

/** Binding metadata about immutable samplers and their Y'CbCr plane counts. */
class ImmutableSamplerPlaneInfo {
	/**
	 * Bit 0: set if non-Y'CbCr-conversion immutable samplers are present.
	 * Bits 1-30: maximum Y'CbCr plane count.
	 * Bit 31: if set, this is just asking for the maximum size, and the rest of the bits don't matter.
	 */
	uint32_t data;
public:
	/**
	 * Returns whether the descriptor has immutable samplers.
	 * Note that this will return false on MaxSize, while hasYCBCR will return true.
	 * (Use in situations where having an immutable sampler requires less space than not having one.)
	 */
	bool hasImmutableSamplers() const { return static_cast<int32_t>(data) > 0; }
	/** Returns whether the descriptor has Y'CbCr immutable samplers. */
	bool hasYCBCR() const { return data >> 1; }
	/** Returns whether the descriptor has non-Y'CbCr immutable samplers. */
	bool hasNonYCBCR() const { return data & 1; }
	bool isMaxSize() const { return static_cast<int32_t>(data) < 0; }
	/** Returns the number of planes.  If requesting MaxSize, returns an indefinitely large number. */
	uint32_t planeCount() { return data >> 1; }
	ImmutableSamplerPlaneInfo(): data(0) {}
	ImmutableSamplerPlaneInfo(MVKSampler* sampler) {
		if (sampler->isYCBCR())
			data = sampler->getPlaneCount() << 1;
		else
			data = 1;
		assert(planeCount() <= 3 && "Max plane count of any supported type is 3");
	}
	void add(ImmutableSamplerPlaneInfo other) {
		data = (data + (other.data & 0xfffffffe)) | (other.data & 1);
	}
	/** Returns the worst case size, when the full details are unknown. */
	static ImmutableSamplerPlaneInfo MaxSize() {
		ImmutableSamplerPlaneInfo info;
		info.data = ~0u;
		return info;
	}
};

static ImmutableSamplerPlaneInfo getPlaneCount(const MVKDescriptorBinding& binding, MVKSampler*const* immutableSamplers) {
	ImmutableSamplerPlaneInfo info;
	if (binding.hasImmutableSamplers()) {
		for (MVKSampler* samp : MVKArrayRef(immutableSamplers + binding.immSamplerIndex, binding.descriptorCount))
			info.add(samp);
	}
	return info;
}

static MVKDescriptorResourceCount perDescriptorResourceCount(VkDescriptorType type, MVKDescriptorGPULayout argBufLayout, MVKArgumentBufferMode argBuf, MVKDevice* dev, ImmutableSamplerPlaneInfo planes) {
	MVKDescriptorResourceCount count = {};
	count.dynamicOffset = needsDynamicOffset(type);
	if (argBuf != MVKArgumentBufferMode::Off) {
		switch (argBufLayout) {
			case MVKDescriptorGPULayout::None:
				break;
			case MVKDescriptorGPULayout::Texture:
				count.texture = 1;
				break;
			case MVKDescriptorGPULayout::Sampler:
				count.sampler = 1;
				break;
			case MVKDescriptorGPULayout::Buffer:
			case MVKDescriptorGPULayout::BufferAuxSize:
			case MVKDescriptorGPULayout::InlineData:
			case MVKDescriptorGPULayout::OutlinedData:
				count.buffer = 1;
				break;
			case MVKDescriptorGPULayout::TexBufSoA:
				count.buffer = 1;
				count.texture = 1;
				break;
			case MVKDescriptorGPULayout::TexSampSoA:
				count.sampler = 1;
				count.texture = 1;
				break;
			case MVKDescriptorGPULayout::Tex2SampSoA:
				count.sampler = 1;
				count.texture = 2;
				break;
			case MVKDescriptorGPULayout::Tex3SampSoA:
				count.sampler = 1;
				count.texture = 3;
				break;
		}
	} else {
		uint32_t atomicBuffers = dev->getPhysicalDevice()->getMetalFeatures()->nativeTextureAtomics ? 0 : 1;
		switch (type) {
			case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
				count.sampler = 1;
				count.texture = std::max(1u, planes.planeCount());
				break;
			case VK_DESCRIPTOR_TYPE_SAMPLER:
				count.sampler = 1;
				break;
			case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
				count.texture = 1;
				break;
			case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
				count.texture = 1;
				count.buffer = atomicBuffers;
				break;
			case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
				count.buffer = 1;
				break;
			default:
				assert(0);
				break;
		}
	}
	return count;
}

static MVKDescriptorCPULayout pickCPULayout(
  VkDescriptorType type,
  uint32_t count,
  MVKArgumentBufferMode argBuf,
  MVKDevice* dev,
  ImmutableSamplerPlaneInfo planes = ImmutableSamplerPlaneInfo::MaxSize()) {
	if (count == 0)
		return MVKDescriptorCPULayout::None;
	bool nativeSwizzle = dev->getPhysicalDevice()->getMetalFeatures()->nativeTextureSwizzle;
	bool nativeTAtomic = dev->getPhysicalDevice()->getMetalFeatures()->nativeTextureAtomics;
	MVKDescriptorCPULayout sampledImg = nativeSwizzle ? MVKDescriptorCPULayout::OneID : MVKDescriptorCPULayout::OneIDMeta;
	switch (type) {
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			// Multiplanar images are for ycbcr, which requires a swizzle of IDENTITY, so we don't need to store it.
			// Immutable samplers are accessible from the layout so they also don't need to be stored.
			if (planes.planeCount() > 2 || (!planes.hasImmutableSamplers() && !nativeSwizzle))
				return MVKDescriptorCPULayout::TwoIDMeta;
			if (planes.planeCount() == 1 || (planes.hasNonYCBCR() && nativeSwizzle))
				return MVKDescriptorCPULayout::OneID;
			return MVKDescriptorCPULayout::OneIDMeta;
		case VK_DESCRIPTOR_TYPE_SAMPLER:                return planes.hasImmutableSamplers() ? MVKDescriptorCPULayout::None : MVKDescriptorCPULayout::OneID;
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:          return sampledImg;
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:          return nativeTAtomic ? sampledImg : MVKDescriptorCPULayout::TwoID2Meta;
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:   return MVKDescriptorCPULayout::OneID;
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:   return nativeTAtomic ? MVKDescriptorCPULayout::OneID : MVKDescriptorCPULayout::TwoID2Meta;
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:         return MVKDescriptorCPULayout::OneID2Meta;
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:         return MVKDescriptorCPULayout::OneID2Meta;
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC: return MVKDescriptorCPULayout::OneID2Meta;
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: return MVKDescriptorCPULayout::OneID2Meta;
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:       return sampledImg;
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:   return argBuf == MVKArgumentBufferMode::Off ? MVKDescriptorCPULayout::InlineData : MVKDescriptorCPULayout::None;
		default:                                        return MVKDescriptorCPULayout::None;
	}
}

static MVKDescriptorGPULayout pickGPULayout(
  VkDescriptorType type,
  uint32_t count,
  MVKArgumentBufferMode argBuf,
  MVKDevice* dev,
  ImmutableSamplerPlaneInfo planes = ImmutableSamplerPlaneInfo::MaxSize()) {
	if (argBuf == MVKArgumentBufferMode::Off || count == 0)
		return MVKDescriptorGPULayout::None;
	bool nativeTAtomic = dev->getPhysicalDevice()->getMetalFeatures()->nativeTextureAtomics;
	MVKDescriptorGPULayout storageImg = nativeTAtomic ? MVKDescriptorGPULayout::Texture : MVKDescriptorGPULayout::TexBufSoA;
	switch (type) {
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			if (planes.planeCount() > 2)
				return MVKDescriptorGPULayout::Tex3SampSoA;
			if (planes.planeCount() == 2)
				return MVKDescriptorGPULayout::Tex2SampSoA;
			return MVKDescriptorGPULayout::TexSampSoA;
		case VK_DESCRIPTOR_TYPE_SAMPLER:                return MVKDescriptorGPULayout::Sampler;
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:          return MVKDescriptorGPULayout::Texture;
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:          return storageImg;
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:   return MVKDescriptorGPULayout::Texture;
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:   return storageImg;
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:         return MVKDescriptorGPULayout::BufferAuxSize;
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:         return MVKDescriptorGPULayout::BufferAuxSize;
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC: return MVKDescriptorGPULayout::BufferAuxSize;
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: return MVKDescriptorGPULayout::BufferAuxSize;
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:       return MVKDescriptorGPULayout::Texture;
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:   return MVKDescriptorGPULayout::OutlinedData;
		default:                                        return MVKDescriptorGPULayout::None;
	}
}

static MTLArgumentAccess getBindingAccess(VkDescriptorType type) {
	switch (type) {
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return MTLArgumentAccessReadWrite;
		default:
			return MTLArgumentAccessReadOnly;
	}
}

static int bindingCompare(const void* a, const void* b) {
	const MVKDescriptorBinding* bindA = static_cast<const MVKDescriptorBinding*>(a);
	const MVKDescriptorBinding* bindB = static_cast<const MVKDescriptorBinding*>(b);
	if (bindA->binding < bindB->binding)
		return -1;
	if (bindA->binding > bindB->binding)
		return 1;
	if (bindA->stageFlags < bindB->stageFlags)
		return -1;
	if (bindA->stageFlags > bindB->stageFlags)
		return 1;
	return 0;
}

// Find and return an array of binding flags from the pNext chain of pCreateInfo,
// or return nullptr if the chain does not include binding flags.
static const VkDescriptorBindingFlags* getBindingFlags(const VkDescriptorSetLayoutCreateInfo* pCreateInfo) {
	auto* info = mvkFindStructInChain<VkDescriptorSetLayoutBindingFlagsCreateInfo>(pCreateInfo, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO);
	return info && info->bindingCount ? info->pBindingFlags : nullptr;
}

static MTLArgumentDescriptor* argumentDescriptor(NSUInteger index, MTLArgumentAccess access, MTLDataType type, NSUInteger arrayLength = 0) {
	MTLArgumentDescriptor* desc = [MTLArgumentDescriptor argumentDescriptor];
	[desc setIndex:index];
	[desc setAccess:access];
	[desc setDataType:type];
	[desc setArrayLength:arrayLength];
	if (type == MTLDataTypeTexture)
		[desc setTextureType:MTLTextureType2D];
	return desc;
}

static id<MTLArgumentEncoder> createArgumentEncoder(MVKArrayRef<const MVKDescriptorBinding> bindings, MVKDevice* device, bool needsAuxBuffer, uint32_t variableCount) {
	assert(bindings.size() > 0);
	@autoreleasepool {
		NSMutableArray<MTLArgumentDescriptor*>* list = [NSMutableArray array];
		if (needsAuxBuffer)
			[list addObject:argumentDescriptor(0, MTLArgumentAccessReadOnly, MTLDataTypePointer)];
		for (const auto& binding : bindings) {
			MVKDescriptorGPULayout layout = binding.gpuLayout;
			MTLArgumentAccess access = getBindingAccess(binding.descriptorType);
			uint32_t count = binding.descriptorCount;
			uint32_t index = binding.argBufID;
			if (binding.flags & MVK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT)
				count = variableCount;
			switch (layout) {
				case MVKDescriptorGPULayout::Sampler:
				case MVKDescriptorGPULayout::Buffer:
				case MVKDescriptorGPULayout::Texture:
				case MVKDescriptorGPULayout::BufferAuxSize: {
					MTLDataType type = layout == MVKDescriptorGPULayout::Sampler ? MTLDataTypeSampler :
					                   layout == MVKDescriptorGPULayout::Texture ? MTLDataTypeTexture :
					                                                               MTLDataTypePointer;
					[list addObject:argumentDescriptor(index, access, type, count)];
					break;
				}

				case MVKDescriptorGPULayout::OutlinedData:
					[list addObject:argumentDescriptor(index, access, MTLDataTypePointer)];
					break;

				case MVKDescriptorGPULayout::InlineData:
					[list addObject:argumentDescriptor(index, access, MTLDataTypeUInt, count / 4)];
					break;

				case MVKDescriptorGPULayout::Tex3SampSoA:
					[list addObject:argumentDescriptor(index, access, MTLDataTypeTexture, count)];
					index += count;
					[[fallthrough]];
				case MVKDescriptorGPULayout::Tex2SampSoA:
					[list addObject:argumentDescriptor(index, access, MTLDataTypeTexture, count)];
					index += count;
					[[fallthrough]];
				case MVKDescriptorGPULayout::TexBufSoA:
				case MVKDescriptorGPULayout::TexSampSoA: {
					MTLDataType last = layout == MVKDescriptorGPULayout::TexBufSoA ? MTLDataTypePointer : MTLDataTypeSampler;
					[list addObject:argumentDescriptor(index,         access, MTLDataTypeTexture, count)];
					[list addObject:argumentDescriptor(index + count, access, last,               count)];
					break;
				}

				case MVKDescriptorGPULayout::None:
					break;
			}
		}
		return [device->getPhysicalDevice()->getMTLDevice() newArgumentEncoderWithArguments:list];
	}
}

static uint32_t writeAuxOffsets(uint32_t* write, MVKArrayRef<const MVKDescriptorBinding> bindings, uint32_t base, uint32_t auxSize) {
	uint32_t end = base + auxSize;
	uint32_t sizeBufIdx = 1; // First is taken by the pointer to the size buf itself
	for (auto& binding : bindings) {
		auto layout = binding.gpuLayout;
		if (needsAuxOffset(layout)) {
			switch (layout) {
				case MVKDescriptorGPULayout::BufferAuxSize:
					write[binding.auxIndex] = base + sizeBufIdx * sizeof(uint32_t);
					break;
				case MVKDescriptorGPULayout::OutlinedData:
					end = alignDescriptorOffset(end, 16);
					write[binding.auxIndex] = end;
					end += binding.descriptorCount;
					break;
				default:
					assert(0);
			}
		}
		uint32_t count = descriptorGPUBindingCount(layout) * binding.descriptorCount;
		sizeBufIdx += binding.descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK ? 1 : count;
	}
	return end;
}

void MVKDescriptorBinding::populate(const VkDescriptorSetLayoutBinding& vk) {
	binding = vk.binding;
	descriptorType = vk.descriptorType;
	descriptorCount = vk.descriptorCount;
	stageFlags = vk.stageFlags;
	flags = canUseImmutableSamplers(descriptorType) && vk.pImmutableSamplers ? MVK_DESCRIPTOR_BINDING_USES_IMMUTABLE_SAMPLERS_BIT : 0;
}

#pragma mark - MVKDescriptorSetLayout

MVKDescriptorSetLayout::MVKDescriptorSetLayout(MVKDevice* device): MVKVulkanAPIDeviceObject(device) {}

MVKDescriptorSetLayout* MVKDescriptorSetLayout::Create(MVKDevice* device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo) {
	using Constructor = MVKInlineObjectConstructor<MVKDescriptorSetLayout>;
	const VkDescriptorBindingFlags* flagList = getBindingFlags(pCreateInfo);
	uint32_t numBindings = pCreateInfo->bindingCount;
	uint32_t numImmutableSamplers = 0;
	uint32_t numAuxOffsets = 0;
	const VkDescriptorSetLayoutBinding* variableDesc = nullptr;
	bool needsSizeBuf = false;
	bool hasAnyBindings = false;

	MVKArgumentBufferMode argBufMode = pickArgumentBufferMode(device, pCreateInfo);

	for (uint32_t i = 0; i < pCreateInfo->bindingCount; i++) {
		const VkDescriptorSetLayoutBinding& bind = pCreateInfo->pBindings[i];
		if (canUseImmutableSamplers(bind.descriptorType) && bind.pImmutableSamplers)
			numImmutableSamplers += bind.descriptorCount;
		auto layout = pickGPULayout(bind.descriptorType, bind.descriptorCount, argBufMode, device);
		if (needsAuxOffset(layout))
			numAuxOffsets++;
		needsSizeBuf |= needsAuxBuf(layout);
		if (bind.descriptorCount > 0) {
			if (flagList && mvkIsAnyFlagEnabled(flagList[i], VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT))
				variableDesc = &bind;
			hasAnyBindings = true;
		}
	}

	if (!hasAnyBindings)
		argBufMode = MVKArgumentBufferMode::Off; // Metal doesn't like argument encoders with no elements

	bool isVariable = variableDesc && pickGPULayout(variableDesc->descriptorType, 1, argBufMode, device) != MVKDescriptorGPULayout::OutlinedData;
	void* auxOffsets;

	MVKDescriptorSetLayout* ret = Constructor::Create(
		std::tuple {
			Constructor::Init(&MVKDescriptorSetLayout::_mtlArgumentEncoder, argBufMode == MVKArgumentBufferMode::ArgEncoder && !isVariable),
			Constructor::Init(&MVKDescriptorSetLayout::_mtlArgumentEncoderVariable, argBufMode == MVKArgumentBufferMode::ArgEncoder && isVariable),
			Constructor::Uninit(&MVKDescriptorSetLayout::_bindings, numBindings),
			Constructor::Uninit(&MVKDescriptorSetLayout::_immutableSamplers, numImmutableSamplers),
			Constructor::Allocate(&auxOffsets, isVariable ? 0 : numAuxOffsets * sizeof(uint32_t), alignof(uint32_t)),
		},
		device
	);

	bool isPush = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT);
	ret->_auxOffsets = static_cast<uint32_t*>(auxOffsets);
	ret->_numAuxOffsets = numAuxOffsets;
	ret->_argBufMode = argBufMode;
	ret->_flags |= MVKFlagList<Flag>(Flag::IsPushDescriptorSetLayout, isPush);
	ret->_flags |= MVKFlagList<Flag>(Flag::IsVariable,                isVariable);


	for (uint32_t i = 0; i < numBindings; i++) {
		ret->_bindings[i].populate(pCreateInfo->pBindings[i]);
		if (flagList)
			ret->_bindings[i].flags |= flagList[i] & MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS;
	}

	qsort(ret->_bindings.data(), ret->_bindings.size(), sizeof(_bindings[0]), bindingCompare);

	// Gather immutable samplers
	if (numImmutableSamplers) {
		uint32_t write = 0;
		for (auto& binding : ret->_bindings) {
			if (!binding.hasImmutableSamplers())
				continue;
			const VkDescriptorSetLayoutBinding* src = pCreateInfo->pBindings;
			while (src->binding != binding.binding || src->stageFlags != binding.stageFlags)
				src++;
			binding.immSamplerIndex = write;
			mvkCopy(&ret->_immutableSamplers[write], reinterpret_cast<MVKSampler*const*>(src->pImmutableSamplers), src->descriptorCount);
			write += src->descriptorCount;
		}
		assert(write == numImmutableSamplers && "Copied all immutable samplers");
	}

	for (ret->_numLinearBindings = 0; ret->_numLinearBindings < numBindings; ret->_numLinearBindings++) {
		if (ret->_bindings[ret->_numLinearBindings].binding != ret->_numLinearBindings)
			break;
	}

	// Initialize binding layouts
	uint32_t gpuOffset = 0;
	uint32_t bindingCount = 0;
	uint32_t cpuOffset = 0;
	uint32_t auxOffset = 0;
	uint32_t cpuAlign = 1;
	uint32_t gpuAlign = 1;
	uint32_t sizeBufSize = 0;
	bool hasOutlinedData = false;
	if (needsSizeBuf && argBufMode != MVKArgumentBufferMode::Off) {
		gpuOffset += descriptorGPUSizeMetal3(MVKDescriptorGPULayout::Buffer);
		bindingCount += 1;
	}
	for (auto& binding : ret->_bindings) {
		ImmutableSamplerPlaneInfo planes = getPlaneCount(binding, ret->_immutableSamplers.data());
		MVKDescriptorCPULayout cpu = pickCPULayout(binding.descriptorType, binding.descriptorCount, argBufMode, device, planes);
		MVKDescriptorGPULayout gpu = pickGPULayout(binding.descriptorType, binding.descriptorCount, argBufMode, device, planes);
		binding.perDescriptorResourceCount = perDescriptorResourceCount(binding.descriptorType, gpu, argBufMode, device, planes);
		binding.cpuLayout = cpu;
		binding.gpuLayout = gpu;
		if (!binding.descriptorCount) {
			// Write some invalid offsets to make it more noticeable if we try to use this
			binding.cpuOffset = ~0u;
			binding.gpuOffset = ~0u;
			binding.auxIndex = ~0u;
			continue;
		}
		MVKShaderStageResourceBinding resourceCount = binding.totalResourceCount();
		for (uint32_t i = 0; i < kMVKShaderStageCount; i++) {
			auto stage = static_cast<MVKShaderStage>(i);
			if (mvkIsAnyFlagEnabled(binding.stageFlags, mvkVkShaderStageFlagBitsFromMVKShaderStage(stage)))
				ret->_totalResourceCount.stages[stage] += resourceCount;
		}
		if (!binding.isVariable())
			ret->_dynamicOffsetCount += resourceCount.dynamicOffsetBufferIndex;
		hasOutlinedData |= gpu == MVKDescriptorGPULayout::OutlinedData;
		cpuOffset = alignDescriptorOffset(cpuOffset, descriptorCPUAlign(cpu));
		cpuAlign = std::max(cpuAlign, descriptorCPUAlign(cpu));
		if (argBufMode != MVKArgumentBufferMode::ArgEncoder) {
			gpuOffset = alignDescriptorOffset(gpuOffset, descriptorGPUAlignMetal3(gpu));
			gpuAlign = std::max(gpuAlign, descriptorGPUAlignMetal3(gpu));
		}
		binding.cpuOffset = cpuOffset;
		uint32_t count = binding.descriptorCount;
		if (binding.isVariable())
			count = 0; // Variable size will be added later
		cpuOffset += descriptorCPUSize(cpu) * count;
		if (argBufMode == MVKArgumentBufferMode::ArgEncoder) {
			binding.argBufID = bindingCount;
		} else {
			binding.gpuOffset = gpuOffset;
			gpuOffset += descriptorGPUSizeMetal3(gpu, count);
		}
		bindingCount += binding.descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK ? 1 : descriptorGPUBindingCount(gpu) * count;
		if (needsAuxBuf(binding.gpuLayout))
			sizeBufSize = bindingCount;
		if (needsAuxOffset(binding.gpuLayout))
			binding.auxIndex = auxOffset++;
		else if (!binding.hasImmutableSamplers())
			binding.auxIndex = ~0u;
	}

	assert(needsSizeBuf == !!sizeBufSize);

	// Outlined data is 16-byte aligned, so the gpu buffer needs to be as well
	if (hasOutlinedData)
		gpuAlign = std::max(gpuAlign, 16u);

	ret->_sizeBufSize = sizeBufSize;
	ret->_cpuSize = cpuOffset;
	ret->_cpuAlignment = cpuAlign;

	if (isVariable) {
		MVKDescriptorBinding& variable = ret->_bindings.back();
		assert(variable.isVariable());
		ret->_flags |= MVKFlagList<Flag>(Flag::IsSizeBufVariable,            needsAuxBuf(variable.gpuLayout));
		ret->_flags |= MVKFlagList<Flag>(Flag::IsDynamicOffsetCountVariable, needsDynamicOffset(variable.descriptorType));
		ret->_cpuVariableElementSize = descriptorCPUSize(variable.cpuLayout);
		ret->_gpuAlignment = gpuAlign;
		if (argBufMode != MVKArgumentBufferMode::ArgEncoder) {
			ret->_gpuAuxBase = gpuOffset;
			ret->_gpuSize = gpuOffset;
			ret->_gpuVariableElementSize = descriptorGPUSizeMetal3(variable.gpuLayout);
			if (needsAuxBuf(variable.gpuLayout))
				ret->_gpuVariableElementSize += sizeof(uint32_t);
		}
	} else {
		if (argBufMode == MVKArgumentBufferMode::ArgEncoder) {
			id<MTLArgumentEncoder> enc = createArgumentEncoder(ret->_bindings, device, sizeBufSize != 0, 0);
			ret->_mtlArgumentEncoder->init(enc, std::memory_order_relaxed);
			gpuOffset = static_cast<uint32_t>(ret->_mtlArgumentEncoder->getEncodedLength());
			gpuAlign = std::max(gpuAlign, static_cast<uint32_t>([enc alignment]));
		}
		ret->_gpuAuxBase = gpuOffset;
		ret->_gpuSize = gpuOffset;
		ret->_gpuAlignment = gpuAlign;

		if (numAuxOffsets) {
			ret->_gpuSize = writeAuxOffsets(ret->_auxOffsets, ret->_bindings, gpuOffset, sizeBufSize * sizeof(uint32_t));
			MVKDescriptorBinding& last = ret->_bindings.back();
			if (last.descriptorCount > 0 && last.isVariable()) {
				assert(last.gpuLayout == MVKDescriptorGPULayout::OutlinedData); // Otherwise it would be handled as variable
				ret->_gpuSize -= last.descriptorCount;
				ret->_gpuVariableElementSize = 1;
				if (last.cpuLayout == MVKDescriptorCPULayout::InlineData)
					ret->_cpuVariableElementSize = 1;
			}
		}
	}

	return ret;
}

uint32_t MVKDescriptorSetLayout::getBindingIndex(uint32_t binding) const {
	if (binding < _numLinearBindings)
		return binding;
	uint32_t begin = _numLinearBindings;
	uint32_t end = static_cast<uint32_t>(_bindings.size());
	while (begin < end) {
		uint32_t mid = (begin + end) / 2;
		uint32_t entry = _bindings[mid].binding;
		if (entry == binding)
			return mid;
		else if (entry < binding)
			begin = mid + 1;
		else
			end = mid;
	}
	return static_cast<uint32_t>(_bindings.size());
}

MVKMTLArgumentEncoder& MVKDescriptorSetLayout::getVariableArgumentEncoder(uint32_t variableCount) const {
	assert(_argBufMode == MVKArgumentBufferMode::ArgEncoder);
	assert(isGPUAllocationVariable());
	MVKMTLArgumentEncoder& enc = (*_mtlArgumentEncoderVariable)[variableCount];
	if (!enc._encoder.load(std::memory_order_acquire)) [[unlikely]] {
		std::lock_guard<std::mutex> guard(enc._lock);
		if (!enc._encoder.load(std::memory_order_relaxed)) [[likely]] {
			enc.init(createArgumentEncoder(_bindings, _device, _sizeBufSize != 0, variableCount), std::memory_order_release);
		}
	}
	return enc;
}

#pragma mark Descriptor Set Updates

/** The type of data being supplied from a Vulkan descriptor update */
enum class MVKDescriptorUpdateSourceType { Unsupported, Image, ImageSampler, Sampler, Buffer, TexelBuffer, InlineUniform };

static MVKDescriptorUpdateSourceType getDescriptorUpdateSourceType(VkDescriptorType type) {
	switch (type) {
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return MVKDescriptorUpdateSourceType::ImageSampler;

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			return MVKDescriptorUpdateSourceType::Sampler;

		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			return MVKDescriptorUpdateSourceType::Image;

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			return MVKDescriptorUpdateSourceType::TexelBuffer;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return MVKDescriptorUpdateSourceType::Buffer;

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
			return MVKDescriptorUpdateSourceType::InlineUniform;

		case VK_DESCRIPTOR_TYPE_PARTITIONED_ACCELERATION_STRUCTURE_NV:
		case VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR:
		case VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_NV:
		case VK_DESCRIPTOR_TYPE_SAMPLE_WEIGHT_IMAGE_QCOM:
		case VK_DESCRIPTOR_TYPE_BLOCK_MATCH_IMAGE_QCOM:
		case VK_DESCRIPTOR_TYPE_MUTABLE_EXT:
		case VK_DESCRIPTOR_TYPE_TENSOR_ARM:
		case VK_DESCRIPTOR_TYPE_MAX_ENUM:
			break;
	}
	assert(0);
	return MVKDescriptorUpdateSourceType::Unsupported;
}

static const void* getDescriptorWriteSource(const VkWriteDescriptorSet& write, MVKDescriptorUpdateSourceType type) {
	switch (type) {
		case MVKDescriptorUpdateSourceType::Sampler:
		case MVKDescriptorUpdateSourceType::ImageSampler:
		case MVKDescriptorUpdateSourceType::Image:
			return write.pImageInfo;
		case MVKDescriptorUpdateSourceType::Buffer:
			return write.pBufferInfo;
		case MVKDescriptorUpdateSourceType::TexelBuffer:
			return write.pTexelBufferView;
		case MVKDescriptorUpdateSourceType::InlineUniform:
			return mvkFindStructInChain<VkWriteDescriptorSetInlineUniformBlock>(&write, VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK)->pData;
		case MVKDescriptorUpdateSourceType::Unsupported:
			return nullptr;
	}
}

static uint32_t getDescriptorUpdateStride(MVKDescriptorUpdateSourceType type) {
	switch (type) {
		case MVKDescriptorUpdateSourceType::Image:         return sizeof(VkDescriptorImageInfo);
		case MVKDescriptorUpdateSourceType::Sampler:       return sizeof(VkDescriptorImageInfo);
		case MVKDescriptorUpdateSourceType::ImageSampler:  return sizeof(VkDescriptorImageInfo);
		case MVKDescriptorUpdateSourceType::Buffer:        return sizeof(VkDescriptorBufferInfo);
		case MVKDescriptorUpdateSourceType::TexelBuffer:   return sizeof(VkBufferView);
		case MVKDescriptorUpdateSourceType::InlineUniform: return 1;
		case MVKDescriptorUpdateSourceType::Unsupported:   return 0;
	}
}

/** Fast path updates ignore binding boundaries and assume they can just advance a pointer. */
static bool canUseFastPathUpdate(MVKDescriptorGPULayout layout, MVKArgumentBufferMode argBufMode) {
	if (layout == MVKDescriptorGPULayout::InlineData)
		return argBufMode != MVKArgumentBufferMode::ArgEncoder;
	switch (layout) {
		case MVKDescriptorGPULayout::None:
		case MVKDescriptorGPULayout::Texture:
		case MVKDescriptorGPULayout::Sampler:
		case MVKDescriptorGPULayout::Buffer:
		case MVKDescriptorGPULayout::BufferAuxSize:
		case MVKDescriptorGPULayout::InlineData:
			return true;
		case MVKDescriptorGPULayout::TexBufSoA:
		case MVKDescriptorGPULayout::TexSampSoA:
		case MVKDescriptorGPULayout::Tex2SampSoA:
		case MVKDescriptorGPULayout::Tex3SampSoA:
		case MVKDescriptorGPULayout::OutlinedData:
			return false;
	}
}

/** Get the MTLTexture stored at the given image-representing source Vulkan update pointer. */
static id<MTLTexture> getTexture(const void* src, MVKDescriptorUpdateSourceType type) {
	switch (type) {
		case MVKDescriptorUpdateSourceType::Image: {
			auto* img = reinterpret_cast<MVKImageView*>(static_cast<const VkDescriptorImageInfo*>(src)->imageView);
			return img ? img->getMTLTexture() : nullptr;
		}
		case MVKDescriptorUpdateSourceType::TexelBuffer: {
			auto* img = *reinterpret_cast<MVKBufferView*const*>(src);
			return img ? img->getMTLTexture() : nullptr;
		}
		default:
			assert(0);
			return nullptr;
	}
}

/** Either a pointer, for MTLBuffers, or MTLResourceID, for samplers and textures. */
union MVKGPUResource {
	uint64_t gpuAddress;
	MTLResourceID resource;
};
static_assert(sizeof(MVKGPUResource) == sizeof(uint64_t));
static_assert(sizeof(MVKGPUResource) == sizeof(MTLResourceID));

template <MVKArgumentBufferMode Layout> struct MVKArgBufEncoder;

/** Argument buffer encoder for Metal 3 encoding */
template <> struct MVKArgBufEncoder<MVKArgumentBufferMode::Metal3> {
	MVKGPUResource* dst;
	MVKArgBufEncoder(id<MTLArgumentEncoder> enc, char* base): dst(reinterpret_cast<MVKGPUResource*>(base)) {}
	void advance(size_t stride) { dst = reinterpret_cast<MVKGPUResource*>(reinterpret_cast<char*>(dst) + stride); }
	void* constantData(size_t index) { return reinterpret_cast<char*>(dst) + index; }
	void setTexture(id<MTLTexture> tex,       size_t index = 0) { dst[index].resource = tex.gpuResourceID; }
	void setSampler(id<MTLSamplerState> samp, size_t index = 0) { dst[index].resource = samp.gpuResourceID; }
	void setBuffer(id<MTLBuffer> buf, uint64_t offset, size_t index = 0) {
		dst[index].gpuAddress = buf.gpuAddress + offset;
	}
	void setNullTexture(size_t index = 0) { dst[index].resource = {}; }
	void setNullSampler(size_t index = 0) { dst[index].resource = {}; }
	void setNullBuffer (size_t index = 0) { dst[index].gpuAddress = 0; }
	void setTexture(MVKImageView* img, size_t index = 0) { setTexture(img ? img->getMTLTexture() : nil, index); }
	void setSampler(MVKSampler* samp, size_t index = 0) { setSampler(samp ? samp->getMTLSamplerState() : nil, index); }
	void setBuffer(const VkDescriptorBufferInfo* info, size_t index = 0) {
		uint64_t addr = 0;
		if (MVKBuffer* buf = reinterpret_cast<MVKBuffer*>(info->buffer))
			addr = buf->getMTLBuffer().gpuAddress + buf->getMTLBufferOffset() + info->offset;
		dst[index].gpuAddress = addr;
	}
};

/** Argument buffer encoder for argument encoder encoding */
template <> struct MVKArgBufEncoder<MVKArgumentBufferMode::ArgEncoder> {
	id<MTLArgumentEncoder> enc;
	size_t base;
	MVKArgBufEncoder(id<MTLArgumentEncoder> enc_, char* base): enc(enc_), base(0) {}
	void advance(size_t stride) { base += stride; }
	void* constantData(uint32_t index) { return [enc constantDataAtIndex:base + index]; }
	void setTexture(id<MTLTexture> tex,       size_t index = 0) { [enc setTexture:tex atIndex:base + index]; }
	void setSampler(id<MTLSamplerState> samp, size_t index = 0) { [enc setSamplerState:samp atIndex:base + index]; }
	void setBuffer(id<MTLBuffer> buf, uint64_t offset, size_t index = 0) {
		[enc setBuffer:buf offset:static_cast<NSUInteger>(offset) atIndex:base + index];
	}
	void setNullTexture(size_t index = 0) { [enc setTexture:nil atIndex:base + index]; }
	void setNullSampler(size_t index = 0) { [enc setSamplerState:nil atIndex:base + index]; }
	void setNullBuffer (size_t index = 0) { [enc setBuffer:nil offset:0 atIndex:base + index]; }
	void setTexture(MVKImageView* img, size_t index = 0) {
		[enc setTexture:img ? img->getMTLTexture() : nil atIndex:base + index];
	}
	void setBuffer(const VkDescriptorBufferInfo* info, size_t index = 0) {
		id<MTLBuffer> mtlbuf = nil;
		NSUInteger offset = 0;
		if (MVKBuffer* buf = reinterpret_cast<MVKBuffer*>(info->buffer)) {
			mtlbuf = buf->getMTLBuffer();
			offset = buf->getMTLBufferOffset() + info->offset;
		}
		[enc setBuffer:mtlbuf offset:offset atIndex:base + index];
	}
	void setSampler(MVKSampler* samp, size_t index = 0) {
		[enc setSamplerState:samp ? samp->getMTLSamplerState() : nil atIndex:base + index];
	}
};

static constexpr size_t descriptorGPUStride(MVKArgumentBufferMode argBufMode, MVKDescriptorGPULayout layout) {
	switch (argBufMode) {
		case MVKArgumentBufferMode::Off:        assert(0); return 0;
		case MVKArgumentBufferMode::ArgEncoder: return descriptorGPUBindingStride(layout);
		case MVKArgumentBufferMode::Metal3:     return descriptorGPUStrideMetal3(layout);
	}
}

template <MVKArgumentBufferMode ArgBufMode, MVKDescriptorGPULayout Layout>
static void writeDescriptorSetGPUBuffer(
	const MVKDescriptorBinding& binding,
	id<MTLArgumentEncoder> enc_, char* base, const uint32_t* auxOffsets,
	const void* src, size_t srcStride, MVKDescriptorUpdateSourceType srcType,
	uint32_t start, uint32_t count)
{
	constexpr size_t dstStride = descriptorGPUStride(ArgBufMode, Layout);
	size_t startOffset = start * dstStride;
	MVKArgBufEncoder<ArgBufMode> enc(enc_, base);
	uint32_t baseOffset = ArgBufMode == MVKArgumentBufferMode::ArgEncoder ? binding.argBufID : binding.gpuOffset;

	if (Layout == MVKDescriptorGPULayout::OutlinedData || Layout == MVKDescriptorGPULayout::InlineData) {
		assert(srcType == MVKDescriptorUpdateSourceType::InlineUniform);
		if (Layout == MVKDescriptorGPULayout::OutlinedData) {
			base += auxOffsets[binding.auxIndex];
		} else {
			base = static_cast<char*>(enc.constantData(baseOffset));
		}
		memcpy(base + startOffset, src, count);
		return;
	} else if (Layout == MVKDescriptorGPULayout::None) {
		return;
	}

	enc.advance(baseOffset + startOffset);
	for (uint32_t i = 0; i < count; i++) {
		switch (Layout) {
			case MVKDescriptorGPULayout::Texture:
				enc.setTexture(getTexture(src, srcType));
				break;

			case MVKDescriptorGPULayout::Sampler:
				assert(srcType == MVKDescriptorUpdateSourceType::Sampler);
				if (!binding.hasImmutableSamplers())
					enc.setSampler(reinterpret_cast<MVKSampler*>(static_cast<const VkDescriptorImageInfo*>(src)->sampler));
				break;

			case MVKDescriptorGPULayout::Buffer:
				assert(srcType == MVKDescriptorUpdateSourceType::Buffer);
				enc.setBuffer(static_cast<const VkDescriptorBufferInfo*>(src));
				break;

			case MVKDescriptorGPULayout::TexBufSoA:
				if (id<MTLTexture> tex = getTexture(src, srcType)) {
					enc.setTexture(tex);
					enc.setBuffer([tex buffer], [tex bufferOffset], binding.descriptorCount);
				} else {
					enc.setNullTexture();
					enc.setNullBuffer(binding.descriptorCount);
				}
				break;

			case MVKDescriptorGPULayout::TexSampSoA: {
				assert(srcType == MVKDescriptorUpdateSourceType::ImageSampler);
				auto* info = static_cast<const VkDescriptorImageInfo*>(src);
				enc.setTexture(reinterpret_cast<MVKImageView*>(info->imageView));
				if (!binding.hasImmutableSamplers())
					enc.setSampler(reinterpret_cast<MVKSampler*>(info->sampler), binding.descriptorCount);
				break;
			}

			case MVKDescriptorGPULayout::Tex2SampSoA:
				assert(srcType == MVKDescriptorUpdateSourceType::ImageSampler);
				assert(binding.hasImmutableSamplers());
				if (auto* img = reinterpret_cast<MVKImageView*>(static_cast<const VkDescriptorImageInfo*>(src)->imageView)) {
					enc.setTexture(img->getMTLTexture(0), binding.descriptorCount * 0ull);
					enc.setTexture(img->getMTLTexture(1), binding.descriptorCount * 1ull);
				} else {
					enc.setNullTexture(binding.descriptorCount * 0ull);
					enc.setNullTexture(binding.descriptorCount * 1ull);
				}
				break;

			case MVKDescriptorGPULayout::Tex3SampSoA:
				assert(srcType == MVKDescriptorUpdateSourceType::ImageSampler);
				assert(binding.hasImmutableSamplers());
				if (auto* img = reinterpret_cast<MVKImageView*>(static_cast<const VkDescriptorImageInfo*>(src)->imageView)) {
					for (size_t j = 0; j < 3; j++)
						enc.setTexture(img->getMTLTexture(j), binding.descriptorCount * j);
				} else {
					for (size_t j = 0; j < 3; j++)
						enc.setNullTexture(binding.descriptorCount * j);
				}
				break;

			case MVKDescriptorGPULayout::BufferAuxSize: {
				assert(srcType == MVKDescriptorUpdateSourceType::Buffer);
				auto* info = static_cast<const VkDescriptorBufferInfo*>(src);
				auto* buf = reinterpret_cast<MVKBuffer*>(info->buffer);
				if (buf) {
					enc.setBuffer(buf->getMTLBuffer(), buf->getMTLBufferOffset() + info->offset);
					VkDeviceSize size = info->range == VK_WHOLE_SIZE ? buf->getByteCount() - info->offset : info->range;
					reinterpret_cast<uint32_t*>(base + auxOffsets[binding.auxIndex])[i] = static_cast<uint32_t>(size);
				} else {
					enc.setNullBuffer();
					reinterpret_cast<uint32_t*>(base + auxOffsets[binding.auxIndex])[i] = 0;
				}
				break;
			}

			case MVKDescriptorGPULayout::None:
			case MVKDescriptorGPULayout::InlineData:
			case MVKDescriptorGPULayout::OutlinedData:
				assert(0); // Handled above
		}
		src = static_cast<const char*>(src) + srcStride;
		enc.advance(dstStride);
	}
}

static void advanceBinding(const MVKDescriptorBinding** binding) {
	const MVKDescriptorBinding* current = *binding;
	const MVKDescriptorBinding* next = current + 1;
	assert(current->cpuLayout == next->cpuLayout);
	assert(current->gpuLayout == next->gpuLayout);
	*binding = next;
}

template <MVKArgumentBufferMode ArgBufMode>
static void writeDescriptorSetGPUBuffer(
	const MVKDescriptorBinding* binding, const MVKDescriptorSet* set,
	const void* src, size_t srcStride, MVKDescriptorUpdateSourceType srcType,
	id<MTLArgumentEncoder> enc,
	uint32_t start, uint32_t count)
{
	char* base = set->gpuBuffer;
	const uint32_t* auxOffsets = set->auxIndices;
	if (canUseFastPathUpdate(binding->gpuLayout, ArgBufMode)) {
		switch (binding->gpuLayout) {
#define DISPATCH(x) writeDescriptorSetGPUBuffer<ArgBufMode, MVKDescriptorGPULayout::x>(*binding, enc, base, auxOffsets, src, srcStride, srcType, start, count)
			case MVKDescriptorGPULayout::None:          break;
			case MVKDescriptorGPULayout::Texture:       DISPATCH(Texture);       break;
			case MVKDescriptorGPULayout::Sampler:       DISPATCH(Sampler);       break;
			case MVKDescriptorGPULayout::Buffer:        DISPATCH(Buffer);        break;
			case MVKDescriptorGPULayout::BufferAuxSize: DISPATCH(BufferAuxSize); break;

			case MVKDescriptorGPULayout::InlineData:
				if (ArgBufMode != MVKArgumentBufferMode::ArgEncoder)
					DISPATCH(InlineData);
				else
					assert(0); // Not fast path
				break;

			case MVKDescriptorGPULayout::TexBufSoA:
			case MVKDescriptorGPULayout::TexSampSoA:
			case MVKDescriptorGPULayout::Tex2SampSoA:
			case MVKDescriptorGPULayout::Tex3SampSoA:
			case MVKDescriptorGPULayout::OutlinedData:
				assert(0); // Not fast path
#undef DISPATCH
		}
	} else {
		while (start >= binding->descriptorCount) {
			start -= binding->descriptorCount;
			advanceBinding(&binding);
		}
		while (true) {
			uint32_t numWrite = std::min(count, binding->descriptorCount - start);
			switch (binding->gpuLayout) {
#define DISPATCH(x) writeDescriptorSetGPUBuffer<ArgBufMode, MVKDescriptorGPULayout::x>(*binding, enc, base, auxOffsets, src, srcStride, srcType, start, numWrite)
				case MVKDescriptorGPULayout::TexBufSoA:     DISPATCH(TexBufSoA);    break;
				case MVKDescriptorGPULayout::TexSampSoA:    DISPATCH(TexSampSoA);   break;
				case MVKDescriptorGPULayout::Tex2SampSoA:   DISPATCH(Tex2SampSoA);  break;
				case MVKDescriptorGPULayout::Tex3SampSoA:   DISPATCH(Tex3SampSoA);  break;
				case MVKDescriptorGPULayout::OutlinedData:  DISPATCH(OutlinedData); break;

				case MVKDescriptorGPULayout::InlineData:
					if (ArgBufMode == MVKArgumentBufferMode::ArgEncoder)
						DISPATCH(InlineData);
					else
						assert(0); // Fast path
					break;

				case MVKDescriptorGPULayout::None:
				case MVKDescriptorGPULayout::Texture:
				case MVKDescriptorGPULayout::Sampler:
				case MVKDescriptorGPULayout::Buffer:
				case MVKDescriptorGPULayout::BufferAuxSize:
					assert(0); // Fast path
#undef DISPATCH
			}
			if (start + count <= binding->descriptorCount)
				break;
			src = static_cast<const char*>(src) + numWrite * srcStride;
			count -= numWrite;
			start = 0;
			for (advanceBinding(&binding); !binding->descriptorCount; advanceBinding(&binding))
				;
		}
	}
}

template <MVKDescriptorCPULayout Layout>
static void writeDescriptorSetCPUBuffer(
	const MVKDescriptorSetLayout* layout,
	const MVKDescriptorBinding& binding,
	char* dst,
	const void* src, size_t srcStride, MVKDescriptorUpdateSourceType srcType,
	uint32_t start, uint32_t count)
{
	MVKSampler*const* immutableSamplers = layout->getImmutableSampler(binding, start);
	constexpr size_t dstStride = descriptorCPUSize(Layout);
	dst += start * dstStride;
	if (Layout == MVKDescriptorCPULayout::InlineData) {
		assert(srcType == MVKDescriptorUpdateSourceType::InlineUniform);
		memcpy(dst, src, count);
		return;
	} else if (Layout == MVKDescriptorCPULayout::None) {
		return;
	}
	for (uint32_t i = 0; i < count; i++) {
		switch (Layout) {
			case MVKDescriptorCPULayout::OneID: {
				id* desc = reinterpret_cast<id*>(dst);
				switch (srcType) {
					case MVKDescriptorUpdateSourceType::Image:
					case MVKDescriptorUpdateSourceType::ImageSampler: {
						// OneID ImageSampler is image + constexpr sampler
						auto* img = reinterpret_cast<MVKImageView*>(static_cast<const VkDescriptorImageInfo*>(src)->imageView);
						*desc = img ? img->getMTLTexture() : nil;
						break;
					}
					case MVKDescriptorUpdateSourceType::Sampler: {
						auto* samp = reinterpret_cast<MVKSampler*>(static_cast<const VkDescriptorImageInfo*>(src)->sampler);
						*desc = samp ? samp->getMTLSamplerState() : nil;
						break;
					}
					case MVKDescriptorUpdateSourceType::TexelBuffer: {
						auto* buf = *static_cast<MVKBufferView*const*>(src);
						*desc = buf ? buf->getMTLTexture() : nil;
						break;
					}
					default:
						assert(0);
				}
				break;
			}

			case MVKDescriptorCPULayout::OneIDMeta: {
				auto* desc = reinterpret_cast<MVKCPUDescriptorOneIDMeta*>(dst);
				switch (srcType) {
					case MVKDescriptorUpdateSourceType::ImageSampler: {
						auto* info = static_cast<const VkDescriptorImageInfo*>(src);
						auto* img = reinterpret_cast<MVKImageView*>(info->imageView);
						if (immutableSamplers) {
							// Two planes
							if (img) {
								id<MTLTexture> tex = img->getMTLTexture(0);
								desc->a = tex;
								if (immutableSamplers[i]->isYCBCR())
									desc->b = img->getMTLTexture(1);
								else
									desc->meta.img = { static_cast<uint32_t>([tex height] * [tex bufferBytesPerRow]), img->getPackedSwizzle() };
							} else {
								*desc = {};
							}
						} else {
							// Texture, sampler
							auto* samp = reinterpret_cast<MVKSampler*>(info->sampler);
							desc->a = img  ? img->getMTLTexture()       : nil;
							desc->b = samp ? samp->getMTLSamplerState() : nil;
						}
						break;
					}
					case MVKDescriptorUpdateSourceType::Image:
						if (auto* img = reinterpret_cast<MVKImageView*>(static_cast<const VkDescriptorImageInfo*>(src)->imageView)) {
							id<MTLTexture> tex = img->getMTLTexture();
							desc->a = tex;
							desc->meta.img = { static_cast<uint32_t>([tex height] * [tex bufferBytesPerRow]), img->getPackedSwizzle() };
						} else {
							*desc = {};
						}
						break;
					default:
						assert(0);
				}
				break;
			}

			case MVKDescriptorCPULayout::TwoIDMeta: {
				assert(srcType == MVKDescriptorUpdateSourceType::ImageSampler);
				auto* info = static_cast<const VkDescriptorImageInfo*>(src);
				auto* img = reinterpret_cast<MVKImageView*>(info->imageView);
				auto* desc = reinterpret_cast<MVKCPUDescriptorTwoIDMeta*>(dst);
				if (immutableSamplers) {
					// Three planes
					if (img) {
						id<MTLTexture> tex = img->getMTLTexture(0);
						desc->a = tex;
						if (immutableSamplers[i]->isYCBCR()) {
							desc->b = img->getMTLTexture(1);
							desc->c = img->getMTLTexture(2);
						} else {
							desc->b = nullptr;
							desc->meta.img = { static_cast<uint32_t>([tex height] * [tex bufferBytesPerRow]), img->getPackedSwizzle() };
						}
					} else {
						*desc = {};
					}
				} else {
					// Texture, sampler
					auto* samp = reinterpret_cast<MVKSampler*>(info->sampler);
					if (img) {
						id<MTLTexture> tex = img->getMTLTexture();
						desc->a = tex;
						desc->meta.img = { static_cast<uint32_t>([tex height] * [tex bufferBytesPerRow]), img->getPackedSwizzle() };
					} else {
						desc->a = nil;
						desc->meta = {};
					}
					desc->b = samp ? samp->getMTLSamplerState() : nil;
				}
				break;
			}

			case MVKDescriptorCPULayout::OneID2Meta: {
				assert(srcType == MVKDescriptorUpdateSourceType::Buffer);
				auto* info = static_cast<const VkDescriptorBufferInfo*>(src);
				auto* desc = reinterpret_cast<MVKCPUDescriptorOneID2Meta*>(dst);
				if (auto* buf = reinterpret_cast<MVKBuffer*>(info->buffer)) {
					desc->a = buf->getMTLBuffer();
					desc->offset = buf->getMTLBufferOffset() + info->offset;
					desc->meta.buffer = static_cast<uint32_t>(info->range == VK_WHOLE_SIZE ? buf->getByteCount() - info->offset : info->range);
				} else {
					*desc = {};
				}
				break;
			}

			case MVKDescriptorCPULayout::TwoID2Meta: {
				auto* desc = reinterpret_cast<MVKCPUDescriptorTwoID2Meta*>(dst);
				switch (srcType) {
					case MVKDescriptorUpdateSourceType::Image: {
						auto* img = reinterpret_cast<MVKImageView*>(static_cast<const VkDescriptorImageInfo*>(src)->imageView);
						if (img) {
							id<MTLTexture> tex = img->getMTLTexture();
							desc->a = tex;
							desc->b = [tex buffer];
							desc->offset = [tex bufferOffset];
							desc->meta.img = { static_cast<uint32_t>([tex height] * [tex bufferBytesPerRow]), img->getPackedSwizzle() };
						} else {
							*desc = {};
						}
						break;
					}
					case MVKDescriptorUpdateSourceType::TexelBuffer: {
						auto* img = *static_cast<MVKBufferView*const*>(src);
						if (img) {
							id<MTLTexture> tex = img->getMTLTexture();
							desc->a = tex;
							desc->b = [tex buffer];
							desc->offset = [tex bufferOffset];
							desc->meta.texel = static_cast<uint32_t>([tex height] * [tex bufferBytesPerRow]);
						} else {
							*desc = {};
						}
						break;
					}
					default:
						assert(0);
				}
				break;
			}

			case MVKDescriptorCPULayout::None:
			case MVKDescriptorCPULayout::InlineData:
				assert(0); // Already handled
				break;
		}
		src = static_cast<const char*>(src) + srcStride;
		dst += dstStride;
	}
}

static void writeDescriptorSetCPUBufferDispatch(
	const MVKDescriptorSetLayout* layout,
	const MVKDescriptorBinding& binding,
	char* dst,
	const void* src, size_t srcStride, MVKDescriptorUpdateSourceType srcType,
	uint32_t start, uint32_t count)
{
	switch (binding.cpuLayout) {
#define CASE(x) case MVKDescriptorCPULayout::x: \
			writeDescriptorSetCPUBuffer<MVKDescriptorCPULayout::x>( \
				layout, binding, dst, src, srcStride, srcType, start, count); \
			break;
		case MVKDescriptorCPULayout::None: break;
		CASE(OneID)
		CASE(OneIDMeta)
		CASE(TwoIDMeta)
		CASE(OneID2Meta)
		CASE(TwoID2Meta)
		CASE(InlineData)
#undef CASE
	}
}

static void writeDescriptorSetBinding(
	const MVKDescriptorSetLayout* layout,
	const MVKDescriptorBinding* binding, const MVKDescriptorSet* set, id<MTLArgumentEncoder> enc,
	const void* src, MVKDescriptorUpdateSourceType type, size_t stride,
	uint32_t start, uint32_t count)
{
	char* cpuBuffer = set->cpuBuffer + binding->cpuOffset;
	writeDescriptorSetCPUBufferDispatch(layout, *binding, cpuBuffer, src, stride, type, start, count);
	switch (layout->argBufMode()) {
		case MVKArgumentBufferMode::Off:
			break; // No GPU buffer
		case MVKArgumentBufferMode::ArgEncoder:
			writeDescriptorSetGPUBuffer<MVKArgumentBufferMode::ArgEncoder>(binding, set, src, stride, type, enc, start, count);
			break;
		case MVKArgumentBufferMode::Metal3:
			writeDescriptorSetGPUBuffer<MVKArgumentBufferMode::Metal3    >(binding, set, src, stride, type, enc, start, count);
			break;
	}
}

/**
 * Encode the bindings from cpu binding table entry `src` to the given argument encoder.
 *
 * The resources are live checked before use, since Vulkan doesn't require resources to be valid during copy.
 */
template <MVKDescriptorGPULayout Layout>
static void copyArgBuf(MVKDevice* device, id<MTLArgumentEncoder> enc,
                       const char* src, size_t srcStride,
                       uint32_t start, uint32_t count,
                       size_t bufferOffsetOffset = 0)
{
	for (uint32_t i = 0; i < count; i++, src += srcStride) {
		if constexpr (Layout == MVKDescriptorGPULayout::Texture) {
			id<MTLTexture> tex = *reinterpret_cast<const id<MTLTexture>*>(src);
			[enc setTexture:tex && device->getLiveResources().isLive(tex) ? tex : nil atIndex:start + i];
		} else if constexpr (Layout == MVKDescriptorGPULayout::Sampler) {
			id<MTLSamplerState> samp = *reinterpret_cast<const id<MTLSamplerState>*>(src);
			[enc setSamplerState:samp && device->getLiveResources().isLive(samp) ? samp : nil atIndex:start + i];
		} else if constexpr (Layout == MVKDescriptorGPULayout::Buffer) {
			id<MTLBuffer> buf = *reinterpret_cast<const id<MTLBuffer>*>(src);
			uint64_t offset = *reinterpret_cast<const uint64_t*>(src + bufferOffsetOffset);
			if (buf) {
				auto live = device->getLiveResources().isLive(buf);
				[enc setBuffer:live ? buf : nil offset:live ? offset : 0 atIndex:start + i];
			} else {
				[enc setBuffer:nil offset:0 atIndex:start + i];
			}
		} else {
			static_assert(Layout != Layout, "Other layouts are unsupported");
		}
	}
}

static void copyDescriptorSetBinding(
	const MVKDescriptorSetLayout* dstLayout,
	const MVKDescriptorBinding* srcBinding, const MVKDescriptorSet* srcSet, id<MTLArgumentEncoder> srcEnc,
	const MVKDescriptorBinding* dstBinding, const MVKDescriptorSet* dstSet, id<MTLArgumentEncoder> dstEnc,
	uint32_t srcArrayElement, uint32_t dstArrayElement, uint32_t count)
{
	assert(srcBinding->cpuLayout == dstBinding->cpuLayout);
	assert(srcBinding->gpuLayout == dstBinding->gpuLayout);
	MVKDescriptorCPULayout cpu = srcBinding->cpuLayout;
	if (cpu != MVKDescriptorCPULayout::None) {
		size_t stride = descriptorCPUSize(cpu);
		char* src = srcSet->cpuBuffer + srcBinding->cpuOffset + srcArrayElement * stride;
		char* dst = dstSet->cpuBuffer + dstBinding->cpuOffset + dstArrayElement * stride;
		memcpy(dst, src, count * stride);
	}
	MVKDescriptorGPULayout gpu = srcBinding->gpuLayout;
	MVKArgumentBufferMode argBufMode = dstLayout->argBufMode();
	if (gpu != MVKDescriptorGPULayout::None) {
		if (canUseFastPathUpdate(gpu, argBufMode)) {
			if (argBufMode != MVKArgumentBufferMode::ArgEncoder) {
				// Nice and easy
				size_t stride = descriptorGPUSizeMetal3(gpu);
				char* src = srcSet->gpuBuffer + srcBinding->gpuOffset + srcArrayElement * stride;
				char* dst = dstSet->gpuBuffer + dstBinding->gpuOffset + dstArrayElement * stride;
				memcpy(dst, src, count * stride);
			} else {
				// Argument buffers aren't designed for copying, grab from the CPU buffer
				assert(cpu != MVKDescriptorCPULayout::None);
				size_t cpuStride = descriptorCPUSize(cpu);
				MVKDevice* dev = dstLayout->getDevice();
				char* src = srcSet->cpuBuffer + srcBinding->cpuOffset + srcArrayElement * cpuStride;
				uint32_t dst = dstBinding->argBufID + dstArrayElement * descriptorGPUBindingStride(gpu);
				switch (gpu) {
					case MVKDescriptorGPULayout::None:
						break;

					case MVKDescriptorGPULayout::Texture:
						// Texture always comes first, so layout doesn't matter
						copyArgBuf<MVKDescriptorGPULayout::Texture>(dev, dstEnc, src, cpuStride, dst, count);
						break;

					case MVKDescriptorGPULayout::Sampler:
						assert(cpu == MVKDescriptorCPULayout::OneID || cpu == MVKDescriptorCPULayout::OneIDMeta);
						if (!dstBinding->hasImmutableSamplers())
							copyArgBuf<MVKDescriptorGPULayout::Sampler>(dev, dstEnc, src, cpuStride, dst, count);
						break;

					case MVKDescriptorGPULayout::Buffer:
					case MVKDescriptorGPULayout::BufferAuxSize: {
						size_t offsetOffset;
						if (cpu == MVKDescriptorCPULayout::TwoID2Meta) {
							src += offsetof(MVKCPUDescriptorTwoID2Meta, b); // Buffer is always second ID
							offsetOffset = offsetof(MVKCPUDescriptorTwoID2Meta, offset) - offsetof(MVKCPUDescriptorTwoID2Meta, b);
						} else {
							assert(cpu == MVKDescriptorCPULayout::OneID2Meta);
							offsetOffset = offsetof(MVKCPUDescriptorOneID2Meta, offset);
						}
						copyArgBuf<MVKDescriptorGPULayout::Buffer>(dev, dstEnc, src, cpuStride, dst, count, offsetOffset);
						break;
					}

					case MVKDescriptorGPULayout::InlineData:
					case MVKDescriptorGPULayout::TexBufSoA:
					case MVKDescriptorGPULayout::TexSampSoA:
					case MVKDescriptorGPULayout::Tex2SampSoA:
					case MVKDescriptorGPULayout::Tex3SampSoA:
					case MVKDescriptorGPULayout::OutlinedData:
						assert(0); // Not fast path
				}
			}
			if (needsAuxBuf(gpu)) {
				// Copy aux buffer data
				char* src = srcSet->gpuBuffer + srcSet->auxIndices[srcBinding->auxIndex] + srcArrayElement * sizeof(uint32_t);
				char* dst = dstSet->gpuBuffer + dstSet->auxIndices[dstBinding->auxIndex] + dstArrayElement * sizeof(uint32_t);
				memcpy(dst, src, count * sizeof(uint32_t));
			}
		} else {
			uint32_t srcStart = srcArrayElement;
			uint32_t dstStart = dstArrayElement;
			while (srcStart > srcBinding->descriptorCount) {
				srcStart -= srcBinding->descriptorCount;
				advanceBinding(&srcBinding);
			}
			while (dstStart > dstBinding->descriptorCount) {
				dstStart -= dstBinding->descriptorCount;
				advanceBinding(&dstBinding);
			}
			while (true) {
				uint32_t srcRemaining = srcBinding->descriptorCount - srcStart;
				uint32_t dstRemaining = dstBinding->descriptorCount - dstStart;
				uint32_t copyCount = std::min(count, std::min(srcRemaining, dstRemaining));

				if (gpu == MVKDescriptorGPULayout::OutlinedData) {
					char* src = srcSet->gpuBuffer + srcSet->auxIndices[srcBinding->auxIndex] + srcStart;
					char* dst = dstSet->gpuBuffer + dstSet->auxIndices[dstBinding->auxIndex] + dstStart;
					memcpy(dst, src, copyCount);
				} else if (gpu == MVKDescriptorGPULayout::InlineData) {
					assert(argBufMode == MVKArgumentBufferMode::ArgEncoder); // Otherwise this would be fast path
					char* dst = static_cast<char*>([dstEnc constantDataAtIndex:dstBinding->argBufID]) + dstStart;
					void* src;
					if (srcSet == dstSet) {
						src = [dstEnc constantDataAtIndex:srcBinding->argBufID];
					} else if (srcEnc == dstEnc) {
						// Both encoders are the same, so we need to swap the argument buffer out
						[dstEnc setArgumentBuffer:srcSet->gpuBufferObject offset:srcSet->gpuBufferOffset];
						src = [dstEnc constantDataAtIndex:srcBinding->argBufID];
						[dstEnc setArgumentBuffer:dstSet->gpuBufferObject offset:dstSet->gpuBufferOffset];
					} else {
						src = [srcEnc constantDataAtIndex:srcBinding->argBufID];
					}
					memcpy(dst, static_cast<char*>(src) + srcStart, copyCount);
				} else if (argBufMode != MVKArgumentBufferMode::ArgEncoder) {
					// All these are SoA with textures as the first element
					size_t elemSize = sizeof(uint64_t);
					uint32_t elems = 0;
					switch (gpu) {
						case MVKDescriptorGPULayout::TexBufSoA:   elems = 2; break;
						case MVKDescriptorGPULayout::TexSampSoA:  elems = 2; break;
						case MVKDescriptorGPULayout::Tex2SampSoA: elems = 3; break;
						case MVKDescriptorGPULayout::Tex3SampSoA: elems = 4; break;

						case MVKDescriptorGPULayout::None:
						case MVKDescriptorGPULayout::Texture:
						case MVKDescriptorGPULayout::Sampler:
						case MVKDescriptorGPULayout::Buffer:
						case MVKDescriptorGPULayout::InlineData:
						case MVKDescriptorGPULayout::BufferAuxSize:
						case MVKDescriptorGPULayout::OutlinedData:
							assert(0); // Handled elsewhere
					}
					if (srcBinding->hasImmutableSamplers())
						elems--; // Don't copy immutable samplers, they're pre-written and shouldn't be touched.
					char* src = srcSet->gpuBuffer + srcBinding->gpuOffset + srcStart * elemSize;
					char* dst = dstSet->gpuBuffer + dstBinding->gpuOffset + dstStart * elemSize;
					size_t srcAdvance = srcBinding->descriptorCount * elemSize;
					size_t dstAdvance = dstBinding->descriptorCount * elemSize;
					for (uint32_t i = 0; i < elems; i++, src += srcAdvance, dst += dstAdvance)
						memcpy(dst, src, copyCount * elemSize);
				} else {
					// All these are SoA with textures as the first element
					uint32_t ntex = 0;
					switch (gpu) {
						case MVKDescriptorGPULayout::TexBufSoA:   ntex = 1; break;
						case MVKDescriptorGPULayout::TexSampSoA:  ntex = 1; break;
						case MVKDescriptorGPULayout::Tex2SampSoA: ntex = 2; break;
						case MVKDescriptorGPULayout::Tex3SampSoA: ntex = 3; break;

						case MVKDescriptorGPULayout::None:
						case MVKDescriptorGPULayout::Texture:
						case MVKDescriptorGPULayout::Sampler:
						case MVKDescriptorGPULayout::Buffer:
						case MVKDescriptorGPULayout::InlineData:
						case MVKDescriptorGPULayout::BufferAuxSize:
						case MVKDescriptorGPULayout::OutlinedData:
							assert(0); // Handled elsewhere
					}

					size_t cpuStride = descriptorCPUSize(cpu);
					MVKDevice* dev = dstLayout->getDevice();
					char* src = srcSet->cpuBuffer + srcBinding->cpuOffset + srcStart * cpuStride;
					uint32_t dst = dstBinding->argBufID + dstStart;
					for (uint32_t i = 0; i < ntex; i++, dst += dstBinding->descriptorCount)
						copyArgBuf<MVKDescriptorGPULayout::Texture>(dev, dstEnc, src + i * sizeof(id), cpuStride, dst, copyCount);
					if (!dstBinding->hasImmutableSamplers()) {
						assert(gpu == MVKDescriptorGPULayout::TexBufSoA || gpu == MVKDescriptorGPULayout::TexSampSoA); // All multiplane descriptors use immutable samplers
						if (gpu == MVKDescriptorGPULayout::TexBufSoA) {
							assert(cpu == MVKDescriptorCPULayout::TwoID2Meta);
							size_t offsetOffset = offsetof(MVKCPUDescriptorTwoID2Meta, offset) - sizeof(id);
							copyArgBuf<MVKDescriptorGPULayout::Buffer>(dev, dstEnc, src + sizeof(id), cpuStride, dst, copyCount, offsetOffset);
						} else {
							copyArgBuf<MVKDescriptorGPULayout::Sampler>(dev, dstEnc, src + sizeof(id), cpuStride, dst, copyCount);
						}
					}
				}

				count -= copyCount;
				if (!count)
					break;

				srcStart += copyCount;
				if (copyCount == srcRemaining) {
					srcStart = 0;
					for (advanceBinding(&srcBinding); !srcBinding->descriptorCount; advanceBinding(&srcBinding))
						;
				}
				dstStart += copyCount;
				if (copyCount == dstRemaining) {
					dstStart = 0;
					for (advanceBinding(&dstBinding); !dstBinding->descriptorCount; advanceBinding(&dstBinding))
						;
				}
			}
		}
	}
}

static bool needsSourceArgumentEncoderToCopy(const MVKDescriptorBinding* binding) {
	return binding->gpuLayout == MVKDescriptorGPULayout::InlineData;
}

/** Tracks the needed locks for descriptor set updating with argument encoders */
class DescriptorSetUpdateLockTracker {
	MVKMTLArgumentEncoder* dstEnc = nullptr;
	MVKMTLArgumentEncoder* srcEnc = nullptr;

	static void unlock(MVKMTLArgumentEncoder** stored) {
		if (*stored)
			(*stored)->_lock.unlock();
	}

	static void unlockAndNull(MVKMTLArgumentEncoder** stored) {
		if (auto* enc = *stored) {
			*stored = nullptr;
			enc->_lock.unlock();
		}
	}

	static void unlockAndReplace(MVKMTLArgumentEncoder** stored, MVKMTLArgumentEncoder* enc) {
		unlock(stored);
		*stored = enc;
		enc->_lock.lock();
	}

	static bool tryLock(MVKMTLArgumentEncoder** stored, MVKMTLArgumentEncoder* enc) {
		if (enc->_lock.try_lock()) {
			unlock(stored);
			*stored = enc;
			return true;
		}
		return false;
	}

public:
	/** Lock the dst encoder, assuming the src and live locks have not been taken */
	void lockDstForWrite(MVKMTLArgumentEncoder* enc) {
		assert(!srcEnc);
		if (dstEnc == enc)
			return;
		unlockAndReplace(&dstEnc, enc);
	}

	/** Lock the dst encoder */
	void lockDst(MVKMTLArgumentEncoder* enc) {
		if (dstEnc == enc)
			return;
		if (srcEnc && tryLock(&dstEnc, enc))
			return;
		unlockAndNull(&srcEnc);
		unlockAndReplace(&dstEnc, enc);
	}

	/** Lock the src and dst encoder */
	void lockSrcDst(MVKMTLArgumentEncoder* src, MVKMTLArgumentEncoder* dst) {
		if (srcEnc == src && dstEnc == dst)
			return; // Both encoders are already locked.

		assert(src != dst); // Can't lock the same lock twice

		// To avoid deadlock, always lock the encoder at the lower address first.
		MVKMTLArgumentEncoder** targetL = &dstEnc;
		MVKMTLArgumentEncoder** targetH = &srcEnc;
		MVKMTLArgumentEncoder* encoderL = dst;
		MVKMTLArgumentEncoder* encoderH = src;
		if (encoderL > encoderH) {
			std::swap(targetL, targetH);
			std::swap(encoderL, encoderH);
		}

		// If we can lock the other encoders without blocking, we won't deadlock even if we're not following ordering rules
		if (dstEnc == dst) {
			if (tryLock(&srcEnc, src))
				return;
		} else if (srcEnc == src) {
			if (tryLock(&dstEnc, dst))
				return;
		}

		if (*targetL != encoderL) {
			// Failed to lock the lower encoder, so everything needs to be unlocked and then relocked
			unlock(targetH); // Can't use unlockAndReplace because we need to unlock both old encoders before locking either new one
			unlock(targetL);
			*targetL = encoderL;
			*targetH = encoderH;
			encoderL->_lock.lock();
			encoderH->_lock.lock();
		} else {
			// Lower encoder can stay locked, just need to lock upper.
			unlockAndReplace(targetH, encoderH);
		}
	}

	~DescriptorSetUpdateLockTracker() {
		if (dstEnc) {
			dstEnc->_lock.unlock();
			if (srcEnc)
				srcEnc->_lock.unlock();
		} else {
			assert(!srcEnc);
		}
	}
};

void mvkUpdateDescriptorSets(uint32_t numWrites, const VkWriteDescriptorSet* pDescriptorWrites,
                             uint32_t numCopies, const VkCopyDescriptorSet* pDescriptorCopies)
{
	DescriptorSetUpdateLockTracker locks;
	MVKDescriptorSet* lastDstSet = nullptr;
	MVKDescriptorSet* lastSrcSet = nullptr;
	for (const auto& write : MVKArrayRef(pDescriptorWrites, numWrites)) {
		MVKDescriptorUpdateSourceType type = getDescriptorUpdateSourceType(write.descriptorType);
		uint32_t stride = getDescriptorUpdateStride(type);
		const void* src = getDescriptorWriteSource(write, type);
		if (!src)
			continue;
		MVKDescriptorSet* set = reinterpret_cast<MVKDescriptorSet*>(write.dstSet);
		const MVKDescriptorSetLayout* layout = set->layout;
		const MVKDescriptorBinding* binding = layout->getBinding(write.dstBinding);
		id<MTLArgumentEncoder> enc = nullptr;
		if (layout->argBufMode() == MVKArgumentBufferMode::ArgEncoder) {
			enc = set->argEnc->getEncoder();
			if (lastDstSet != set) {
				lastDstSet = set;
				locks.lockDstForWrite(set->argEnc);
				[enc setArgumentBuffer:set->gpuBufferObject offset:set->gpuBufferOffset];
			}
		}
		writeDescriptorSetBinding(layout, binding, set, enc, src, type, stride, write.dstArrayElement, write.descriptorCount);
	}
	for (const auto& copy : MVKArrayRef(pDescriptorCopies, numCopies)) {
		MVKDescriptorSet* srcSet = reinterpret_cast<MVKDescriptorSet*>(copy.srcSet);
		MVKDescriptorSet* dstSet = reinterpret_cast<MVKDescriptorSet*>(copy.dstSet);
		assert(srcSet->layout->argBufMode() == dstSet->layout->argBufMode());
		const MVKDescriptorSetLayout* srcLayout = srcSet->layout;
		const MVKDescriptorSetLayout* dstLayout = dstSet->layout;
		const MVKDescriptorBinding* srcBinding = srcLayout->getBinding(copy.srcBinding);
		const MVKDescriptorBinding* dstBinding = dstLayout->getBinding(copy.dstBinding);
		id<MTLArgumentEncoder> srcEnc = nullptr;
		id<MTLArgumentEncoder> dstEnc = nullptr;
		if (dstLayout->argBufMode() == MVKArgumentBufferMode::ArgEncoder) {
			// Lock the required argument encoders...
			bool needsSrcEnc = needsSourceArgumentEncoderToCopy(dstBinding);
			dstEnc = dstSet->argEnc->getEncoder();
			if (needsSrcEnc && srcSet->argEnc != dstSet->argEnc) {
				// Needs src and dst encoders
				srcEnc = srcSet->argEnc->getEncoder();
				if (lastSrcSet != srcSet || lastDstSet != dstSet) {
					locks.lockSrcDst(srcSet->argEnc, dstSet->argEnc);
					[srcEnc setArgumentBuffer:srcSet->gpuBufferObject offset:srcSet->gpuBufferOffset];
					[dstEnc setArgumentBuffer:dstSet->gpuBufferObject offset:dstSet->gpuBufferOffset];
				}
			} else {
				// Only needs dst encoder, which needs to be locked.
				if (needsSrcEnc)
					srcEnc = dstEnc;
				if (lastDstSet != dstSet) {
					locks.lockDst(dstSet->argEnc);
					[dstEnc setArgumentBuffer:dstSet->gpuBufferObject offset:dstSet->gpuBufferOffset];
				}
			}
		}
		copyDescriptorSetBinding(dstLayout, srcBinding, srcSet, srcEnc, dstBinding, dstSet, dstEnc, copy.srcArrayElement, copy.dstArrayElement, copy.descriptorCount);
	}
}

class DescriptorSetWriteLockTracker {
	std::mutex* mtx = nullptr;
public:
	void lockDst(MVKMTLArgumentEncoder* enc) {
		if (mtx)
			mtx->unlock();
		mtx = &enc->_lock;
		mtx->lock();
	}
	~DescriptorSetWriteLockTracker() {
		if (mtx)
			mtx->unlock();
	}
};

/** Updates the resource bindings in the given descriptor set from the specified template. */
void mvkUpdateDescriptorSetWithTemplate(VkDescriptorSet set, VkDescriptorUpdateTemplate updateTemplate, const void* pData) {

	auto* dstSet = reinterpret_cast<MVKDescriptorSet*>(set);
	auto* pTemplate = reinterpret_cast<MVKDescriptorUpdateTemplate*>(updateTemplate);
	auto* layout = dstSet->layout;
	id<MTLArgumentEncoder> enc = nullptr;
	DescriptorSetWriteLockTracker locks;
	if (layout->argBufMode() == MVKArgumentBufferMode::ArgEncoder) {
		enc = dstSet->argEnc->getEncoder();
		locks.lockDst(dstSet->argEnc);
		[enc setArgumentBuffer:dstSet->gpuBufferObject offset:dstSet->gpuBufferOffset];
	}

	// Perform the updates
	for (uint32_t i = 0; i < pTemplate->getNumberOfEntries(); i++) {
		const VkDescriptorUpdateTemplateEntry* pEntry = pTemplate->getEntry(i);
		const char* pCurData = static_cast<const char*>(pData) + pEntry->offset;

		const MVKDescriptorBinding* binding = layout->getBinding(pEntry->dstBinding);
		MVKDescriptorUpdateSourceType type = getDescriptorUpdateSourceType(pEntry->descriptorType);
		writeDescriptorSetBinding(layout, binding, dstSet, enc, pCurData, type, pEntry->stride, pEntry->dstArrayElement, pEntry->descriptorCount);
	}
}

void mvkPushDescriptorSet(void* dst, MVKDescriptorSetLayout* layout, uint32_t writeCount, const VkWriteDescriptorSet* pDescriptorWrites) {
	assert(layout->argBufMode() == MVKArgumentBufferMode::Off);
	for (uint32_t i = 0; i < writeCount; i++) {
		const VkWriteDescriptorSet& write = pDescriptorWrites[i];
		MVKDescriptorUpdateSourceType type = getDescriptorUpdateSourceType(write.descriptorType);
		uint32_t stride = getDescriptorUpdateStride(type);
		const void* src = getDescriptorWriteSource(write, type);
		if (!src)
			continue;

		const MVKDescriptorBinding* binding = layout->getBinding(write.dstBinding);
		char* target = static_cast<char*>(dst) + binding->cpuOffset;
		writeDescriptorSetCPUBufferDispatch(layout, *binding, target, src, stride, type, write.dstArrayElement, write.descriptorCount);
	}
}

void mvkPushDescriptorSetTemplate(void* dst, MVKDescriptorSetLayout* layout, MVKDescriptorUpdateTemplate* updateTemplate, const void* pData) {
	assert(layout->argBufMode() == MVKArgumentBufferMode::Off);

	for (uint32_t i = 0; i < updateTemplate->getNumberOfEntries(); i++) {
		const VkDescriptorUpdateTemplateEntry* pEntry = updateTemplate->getEntry(i);
		const char* pCurData = static_cast<const char*>(pData) + pEntry->offset;

		const MVKDescriptorBinding* binding = layout->getBinding(pEntry->dstBinding);
		MVKDescriptorUpdateSourceType type = getDescriptorUpdateSourceType(pEntry->descriptorType);
		char* target = static_cast<char*>(dst) + binding->cpuOffset;
		writeDescriptorSetCPUBufferDispatch(layout, *binding, target, pCurData, pEntry->stride, type, pEntry->dstArrayElement, pEntry->descriptorCount);
	}
}

#pragma mark - MVKDescriptorPoolFreeList

void MVKDescriptorPoolFreeList::add(size_t item, size_t size) {
	_freeSize += size;
	auto entry = findEntry(size);
	if (entry != entries.end() && entry->size == size) {
		entry->items.push_back(item);
	} else {
		entries.emplace(entry, size)->items.push_back(item);
	}
}

std::optional<std::pair<size_t, size_t>> MVKDescriptorPoolFreeList::get(size_t minSize, size_t maxSize) {
	for (auto entry = findEntry(minSize); entry != entries.end() && entry->size <= maxSize; ++entry) {
		if (!entry->items.empty()) {
			size_t item = entry->items.back();
			entry->items.pop_back();
			_freeSize -= entry->size;
			return std::make_pair(item, entry->size);
		}
	}
	return std::nullopt;
}

void MVKDescriptorPoolFreeList::reset() {
	for (auto& entry : entries) {
		entry.items.clear();
	}
	_freeSize = 0;
}

std::vector<MVKDescriptorPoolFreeList::Entry>::iterator MVKDescriptorPoolFreeList::findEntry(size_t size) {
	return std::lower_bound(entries.begin(), entries.end(), size, [](const Entry& lhs, const size_t& rhs){ return lhs.size < rhs; });
}

#pragma mark - MVKDescriptorPool

static uint32_t maxGPUSize(MVKDescriptorGPULayout layout, const MVKPhysicalDeviceArgumentBufferSizes& sizes) {
	switch (layout) {
		case MVKDescriptorGPULayout::None:          return 0;
		case MVKDescriptorGPULayout::Texture:       return sizes.texture.size;
		case MVKDescriptorGPULayout::Sampler:       return sizes.sampler.size;
		case MVKDescriptorGPULayout::Buffer:        return sizes.pointer.size;
		case MVKDescriptorGPULayout::TexBufSoA:     return sizes.texture.size + sizes.pointer.size;
		case MVKDescriptorGPULayout::TexSampSoA:    return sizes.texture.size + sizes.sampler.size;
		case MVKDescriptorGPULayout::Tex2SampSoA:   return sizes.texture.size * 2 + sizes.sampler.size;
		case MVKDescriptorGPULayout::Tex3SampSoA:   return sizes.texture.size * 3 + sizes.sampler.size;
		case MVKDescriptorGPULayout::BufferAuxSize: return sizes.pointer.size; // Aux is handled separately
		case MVKDescriptorGPULayout::InlineData:
		case MVKDescriptorGPULayout::OutlinedData:
			// Should be handled separately
			assert(0);
			return 0;
	}
}

/**
 * If you need to be able to allocate up to `groups` groups of `elemAlign`-aligned elements totalling `size` bytes from a buffer
 * where each group is aligned to `groupAlign`, calculates the amount of space required to do that
 */
static uint32_t calcGroupSizeWithPadding(uint32_t size, uint32_t groups, uint32_t elemAlign, uint32_t groupAlign) {
	size += groups * (std::max(elemAlign, groupAlign) - elemAlign);
	return size & ~(groupAlign - 1);
}

MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device): MVKVulkanAPIDeviceObject(device) {}

MVKDescriptorPool* MVKDescriptorPool::Create(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo) {
	using Constructor = MVKInlineObjectConstructor<MVKDescriptorPool>;
	MVKArrayRef pools(pCreateInfo->pPoolSizes, pCreateInfo->poolSizeCount);
	MVKArgumentBufferMode argBufMode = pickArgumentBufferMode(device);
	const MVKPhysicalDeviceArgumentBufferSizes& sizes = device->getPhysicalDevice()->getArgumentBufferSizes();
	uint32_t gpuAlign = std::max(std::max<uint32_t>(sizes.texture.align, sizes.sampler.align), std::max<uint32_t>(sizes.pointer.align, 1));
	uint32_t cpuAlign = alignof(id);
	uint32_t gpuSize = 0;
	uint32_t cpuSize = 0;
	uint32_t numElem = 0;
	uint32_t numAuxOffset = 0;
	uint32_t inlineUniformSize = 0;
	bool usesAuxBuffer = false;

	for (const auto& pool : pools) {
		if (pool.type == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
			inlineUniformSize += pool.descriptorCount;
			continue;
		}
		MVKDescriptorGPULayout gpu = pickGPULayout(pool.type, 1, argBufMode, device);
		MVKDescriptorCPULayout cpu = pickCPULayout(pool.type, 1, argBufMode, device);
		numElem += descriptorGPUBindingCount(gpu) * pool.descriptorCount;
		cpuSize += alignDescriptorOffset(descriptorCPUSize(cpu), cpuAlign) * pool.descriptorCount;
		gpuSize += alignDescriptorOffset(maxGPUSize(gpu, sizes), gpuAlign) * pool.descriptorCount;
		numAuxOffset += needsAuxOffset(gpu) ? pool.descriptorCount : 0;
		usesAuxBuffer |= gpu == MVKDescriptorGPULayout::BufferAuxSize;
	}

	if (numAuxOffset) {
		// Aux offsets are allocated on the CPU buffer
		cpuSize += calcGroupSizeWithPadding(numAuxOffset * sizeof(uint32_t), pCreateInfo->maxSets, alignof(uint32_t), cpuAlign);
	}

	if (inlineUniformSize) {
		auto* info = mvkFindStructInChain<VkDescriptorPoolInlineUniformBlockCreateInfo>(pCreateInfo, VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_INLINE_UNIFORM_BLOCK_CREATE_INFO);
		if (info) {
			if (argBufMode == MVKArgumentBufferMode::Off || mayDisableArgumentBuffers(device))
				cpuSize += calcGroupSizeWithPadding(inlineUniformSize, info->maxInlineUniformBlockBindings, 4, cpuAlign);
			MVKDescriptorGPULayout gpuLayout = pickGPULayout(VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK, 1, argBufMode, device);
			if (gpuLayout == MVKDescriptorGPULayout::OutlinedData) {
				// Add space for the pointers
				gpuSize += alignDescriptorOffset(sizes.pointer.size, gpuAlign) * info->maxInlineUniformBlockBindings;
				// Outlined data is 16-byte aligned
				gpuAlign = std::max(gpuAlign, 16u);
			}
			if (gpuLayout != MVKDescriptorGPULayout::None)
				gpuSize += calcGroupSizeWithPadding(inlineUniformSize, info->maxInlineUniformBlockBindings, 4, gpuAlign);
		}
	}

	if (usesAuxBuffer) {
		// One entry is also used at the beginning of each set for the pointer to the aux buffer
		numElem += pCreateInfo->maxSets;
		gpuSize += alignDescriptorOffset(maxGPUSize(MVKDescriptorGPULayout::Buffer, sizes), gpuAlign) * pCreateInfo->maxSets;
		// The aux buffer is sized relative to the number of total elements in a descriptor, rather than the number of bindings with aux buffers
		uint32_t size = numElem * sizeof(uint32_t);
		gpuSize += calcGroupSizeWithPadding(size, pCreateInfo->maxSets, alignof(uint32_t), gpuAlign);
	}

	bool hostOnly = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_POOL_CREATE_HOST_ONLY_BIT_EXT) && argBufMode != MVKArgumentBufferMode::ArgEncoder;
	void* cpuBuffer;
	void* hostOnlyGPUBuffer;
	// Pad ourselves to reduce the amount of space wasted in driver padding
	gpuSize = alignDescriptorOffset(gpuSize, hostOnly ? gpuAlign : gpuSize < 16384 ? 256 : 16384);

	MVKDescriptorPool* ret = Constructor::Create(
		std::tuple {
			Constructor::Uninit(&MVKDescriptorPool::_descriptorSets, pCreateInfo->maxSets),
			Constructor::Allocate(&cpuBuffer, cpuSize, cpuAlign),
			Constructor::Allocate(&hostOnlyGPUBuffer, hostOnly ? gpuSize : 0, gpuAlign)
		},
		device
	);

	ret->_cpuBuffer.manualConstruct(static_cast<char*>(cpuBuffer), cpuSize);
	ret->_cpuBufferAlignment = cpuAlign;
	ret->_gpuBufferAlignment = gpuAlign;
	ret->_freeAllowed = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT);

	if (gpuSize) {
		if (hostOnly) {
			ret->_gpuBuffer = { static_cast<char*>(hostOnlyGPUBuffer), gpuSize };
		} else @autoreleasepool {
			ret->_gpuBufferObject = [device->getPhysicalDevice()->getMTLDevice() newBufferWithLength:gpuSize options:MTLResourceStorageModeShared];
			ret->_gpuBuffer = { static_cast<char*>([ret->_gpuBufferObject contents]), gpuSize };
			if (argBufMode == MVKArgumentBufferMode::Metal3)
				ret->_gpuBufferGPUAddress = ret->_gpuBufferObject.gpuAddress;
			ret->setMetalObjectLabel(ret->_gpuBufferObject, @"Descriptor set buffer");
		}
	}

	return ret;
}

MVKDescriptorPool::~MVKDescriptorPool() {
	[_gpuBufferObject release];
}

// Find and return an array of variable descriptor counts from the pNext chain of pCreateInfo,
// or return nullptr if the chain does not include variable descriptor counts.
static const uint32_t* getVariableDecriptorCounts(const VkDescriptorSetAllocateInfo* pAllocateInfo) {
	auto* counts = mvkFindStructInChain<VkDescriptorSetVariableDescriptorCountAllocateInfo>(pAllocateInfo, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO);
	return counts && counts->descriptorSetCount ? counts->pDescriptorCounts : nullptr;
}

VkResult MVKDescriptorPool::allocateDescriptorSets(const VkDescriptorSetAllocateInfo* pAllocateInfo,
                                                   VkDescriptorSet* pDescriptorSets)
{
	const uint32_t* pVarDescCounts = getVariableDecriptorCounts(pAllocateInfo);
	const VkDescriptorSetLayout* pSetLayouts = pAllocateInfo->pSetLayouts;
	for (uint32_t dsIdx = 0, end = pAllocateInfo->descriptorSetCount; dsIdx < end; dsIdx++) {
		MVKDescriptorSetLayout* mvkDSL = reinterpret_cast<MVKDescriptorSetLayout*>(pSetLayouts[dsIdx]);
		if (!mvkDSL->isPushDescriptorSetLayout()) {
			if (MVKDescriptorSet* set = allocateDescriptorSet()) {
				pDescriptorSets[dsIdx] = reinterpret_cast<VkDescriptorSet>(set);
				VkResult res = initDescriptorSet(mvkDSL, (pVarDescCounts ? pVarDescCounts[dsIdx] : 0), set);
				if (res != VK_SUCCESS) {
					// initDescriptorSet may partially fill the descriptor set if it fails, so free that too
					freeDescriptorSets(dsIdx + 1, pDescriptorSets);
					std::fill_n(pDescriptorSets, pAllocateInfo->descriptorSetCount, VK_NULL_HANDLE);
					return res;
				}
			} else {
				if (dsIdx)
					freeDescriptorSets(dsIdx, pDescriptorSets);
				std::fill_n(pDescriptorSets, pAllocateInfo->descriptorSetCount, VK_NULL_HANDLE);
				return VK_ERROR_OUT_OF_POOL_MEMORY;
			}

		}
	}
	return VK_SUCCESS;
}

static std::optional<std::pair<uint32_t, uint32_t>> allocate(bool freeAllowed, MVKDescriptorPoolFreeList& freeList, uint32_t size, uint32_t& bumpCur, size_t bumpEnd) {
	if (!size)
		return std::pair<uint32_t, uint32_t>(0, 0);
	if (freeAllowed && freeList.freeSize() >= size)
		if (auto alloc = freeList.get(size, size))
			return alloc;
	if (bumpCur + size <= bumpEnd) {
		auto res = std::pair<uint32_t, uint32_t>(bumpCur, size);
		bumpCur += size;
		return res;
	}
	return std::nullopt;
}

static VkResult pickOOMError(const MVKDescriptorPoolFreeList& free, MVKArrayRef<char> buffer, size_t bufferUsed, size_t needed) {
	size_t totalFree = free.freeSize() + buffer.size() - bufferUsed;
	return totalFree >= needed ? VK_ERROR_FRAGMENTED_POOL : VK_ERROR_OUT_OF_POOL_MEMORY;
}

MVKDescriptorSet* MVKDescriptorPool::allocateDescriptorSet() {
	if (_firstFreeDescriptorSet) {
		static_assert(offsetof(MVKDescriptorSetListItem, allocated) == 0);
		static_assert(offsetof(MVKDescriptorSetListItem, freed) == 0);
		MVKDescriptorSetListItem* set = _firstFreeDescriptorSet;
		_firstFreeDescriptorSet = set->freed.next;
		return &set->allocated;
	} else if (_numAllocatedDescriptorSets < _descriptorSets.size()) {
		return &_descriptorSets[_numAllocatedDescriptorSets++].allocated;
	} else {
		return nullptr;
	}
}

VkResult MVKDescriptorPool::initDescriptorSet(MVKDescriptorSetLayout* mvkDSL, uint32_t variableDescriptorCount, MVKDescriptorSet* set) {
	assert(mvkDSL->gpuAlignment() <= _gpuBufferAlignment);
	assert(mvkDSL->cpuAlignment() <= _cpuBufferAlignment);
	uint32_t auxOffsetSize = 0;
	uint32_t gpuBase = mvkDSL->gpuAuxBase(variableDescriptorCount);
	uint32_t cpuSize = mvkDSL->cpuSize(variableDescriptorCount);
	uint32_t gpuSize = mvkDSL->gpuSize(variableDescriptorCount);
	uint32_t sizeBufSize = mvkDSL->sizeBufSize(variableDescriptorCount);
	MVKMTLArgumentEncoder* argenc = nullptr;
	if (mvkDSL->isMainGPUBufferVariable()) {
		auxOffsetSize = mvkDSL->numAuxOffsets() * sizeof(uint32_t);
		if (mvkDSL->argBufMode() == MVKArgumentBufferMode::ArgEncoder) {
			argenc = &mvkDSL->getVariableArgumentEncoder(variableDescriptorCount);
			gpuBase = static_cast<uint32_t>(argenc->getEncodedLength());
			gpuSize = gpuBase;
		}
	} else if (mvkDSL->argBufMode() == MVKArgumentBufferMode::ArgEncoder) {
		argenc = &mvkDSL->getNonVariableArgumentEncoder();
	}

	memset(set, 0, sizeof(*set));
	set->layout = mvkDSL;
	set->argEnc = argenc;
	set->variableDescriptorCount = variableDescriptorCount;
	uint32_t cpuAllocSize = alignDescriptorOffset(cpuSize + auxOffsetSize, _cpuBufferAlignment);
	if (cpuAllocSize) {
		if (auto cpu = allocate(_freeAllowed, _cpuBufferFreeList, cpuAllocSize, _cpuBufferUsed, _cpuBuffer.size()))
			set->setCPUBuffer(&_cpuBuffer[cpu->first], cpu->second);
		else
			return pickOOMError(_cpuBufferFreeList, _cpuBuffer, _cpuBufferUsed, cpuAllocSize);
	}

	if (mvkDSL->numAuxOffsets()) {
		if (auxOffsetSize) {
			uint32_t* auxIndices = reinterpret_cast<uint32_t*>(set->cpuBuffer + cpuSize);
			set->auxIndices = auxIndices;
			if (mvkDSL->isMainGPUBufferVariable())
				gpuSize = writeAuxOffsets(auxIndices, mvkDSL->bindings(), gpuBase, sizeBufSize * sizeof(uint32_t));
		} else {
			set->auxIndices = mvkDSL->auxOffsets();
		}
	}
	uint32_t gpuAllocSize = alignDescriptorOffset(gpuSize, _gpuBufferAlignment);
	if (gpuAllocSize) {
		if (auto gpu = allocate(_freeAllowed, _gpuBufferFreeList, gpuAllocSize, _gpuBufferUsed, _gpuBuffer.size()))
			set->setGPUBuffer(_gpuBufferObject, _gpuBuffer.data(), gpu->first, gpu->second);
		else
			return pickOOMError(_gpuBufferFreeList, _gpuBuffer, _gpuBufferUsed, gpuAllocSize);
	}

	if (set->cpuBuffer)
		memset(set->cpuBuffer, 0, cpuSize);
	if (set->gpuBuffer)
		memset(set->gpuBuffer, 0, gpuSize);

	if (mvkDSL->numAuxOffsets() || mvkDSL->immutableSamplers().size() != 0) {
		// Need to write aux buffer pointers and immutable samplers to GPU buffer
		const uint32_t* indices = set->auxIndices;
		uint32_t baseOffset = set->gpuBufferOffset;
		switch (mvkDSL->argBufMode()) {
			case MVKArgumentBufferMode::ArgEncoder: {
				id<MTLBuffer> buffer = _gpuBufferObject;
				id<MTLArgumentEncoder> enc = argenc->getEncoder();
				std::lock_guard<std::mutex> guard(argenc->_lock);
				[enc setArgumentBuffer:buffer offset:baseOffset];
				if (mvkDSL->needsSizeBuf())
					[enc setBuffer:buffer offset:baseOffset + gpuBase atIndex:0];
				for (const auto& binding : mvkDSL->bindings()) {
					if (binding.gpuLayout == MVKDescriptorGPULayout::OutlinedData)
						[enc setBuffer:buffer offset:baseOffset + indices[binding.auxIndex] atIndex:binding.argBufID];
					if (binding.hasImmutableSamplers()) {
						// SPIRV-Cross doesn't use constexpr samplers with argument buffers, so we need to bind them.
						uint32_t count = binding.descriptorCount;
						uint32_t base = binding.argBufID + descriptorTextureCount(binding.gpuLayout) * count;
						MVKSampler*const* samp = &mvkDSL->immutableSamplers()[binding.immSamplerIndex];
						for (uint32_t i = 0; i < count; i++)
							[enc setSamplerState:samp[i]->getMTLSamplerState() atIndex:base + i];
					}
				}
				break;
			}
			case MVKArgumentBufferMode::Metal3: {
				uint64_t buffer = _gpuBufferGPUAddress + baseOffset;
				char* base = set->gpuBuffer;
				if (mvkDSL->needsSizeBuf())
					*reinterpret_cast<uint64_t*>(base) = buffer + gpuBase;
				for (const auto& binding : mvkDSL->bindings()) {
					if (binding.gpuLayout == MVKDescriptorGPULayout::OutlinedData)
						*reinterpret_cast<uint64_t*>(base + binding.gpuOffset) = buffer + indices[binding.auxIndex];
					if (binding.hasImmutableSamplers()) {
						// SPIRV-Cross doesn't use constexpr samplers with argument buffers, so we need to bind them.
						uint32_t count = binding.descriptorCount;
						MTLResourceID* write = reinterpret_cast<MTLResourceID*>(base + binding.gpuOffset) + descriptorTextureCount(binding.gpuLayout) * count;
						MVKSampler*const* samp = &mvkDSL->immutableSamplers()[binding.immSamplerIndex];
						for (uint32_t i = 0; i < count; i++)
							write[i] = samp[i]->getMTLSamplerState().gpuResourceID;
					}
				}
				break;
			}
			case MVKArgumentBufferMode::Off: {
				assert(mvkDSL->numAuxOffsets() == 0); // Should not need aux offsets if there's no GPU buffers
				break;
			}
		}
	}

	return VK_SUCCESS;
}

VkResult MVKDescriptorPool::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	if (_freeAllowed) {
		for (uint32_t i = 0; i < count; i++) {
			if (pDescriptorSets[i] == VK_NULL_HANDLE)
				continue;
			MVKDescriptorSetListItem* setItem = reinterpret_cast<MVKDescriptorSetListItem*>(pDescriptorSets[i]);
			MVKDescriptorSet* set = &setItem->allocated;
			if (set->cpuBufferSize)
				_cpuBufferFreeList.add(set->cpuBuffer - _cpuBuffer.data(), set->cpuBufferSize);
			if (set->gpuBufferSize)
				_gpuBufferFreeList.add(set->gpuBufferOffset, set->gpuBufferSize);
			setItem->freed.next = _firstFreeDescriptorSet;
			_firstFreeDescriptorSet = setItem;
		}
	} else {
		// This should only be called by our own allocate functions running out of memory, in which case this is the most recent allocation.
		// Just rewind all the bump allocators.
		for (uint32_t i = 0; i < count; i++) {
			MVKDescriptorSet* set = reinterpret_cast<MVKDescriptorSet*>(pDescriptorSets[i]);
			assert(set == &_descriptorSets[_numAllocatedDescriptorSets - count + i].allocated);
			_gpuBufferUsed -= set->gpuBufferSize;
			_cpuBufferUsed -= set->cpuBufferSize;
		}
		_numAllocatedDescriptorSets -= count;
	}
	return VK_SUCCESS;
}

VkResult MVKDescriptorPool::reset(VkDescriptorPoolResetFlags flags) {
	if (_freeAllowed) {
		_firstFreeDescriptorSet = nullptr;
		_cpuBufferFreeList.reset();
		_gpuBufferFreeList.reset();
	}
	_cpuBufferUsed = 0;
	_gpuBufferUsed = 0;
	_numAllocatedDescriptorSets = 0;
	return VK_SUCCESS;
}


#pragma mark -
#pragma mark MVKDescriptorUpdateTemplate

const VkDescriptorUpdateTemplateEntry* MVKDescriptorUpdateTemplate::getEntry(uint32_t n) const {
	return &_entries[n];
}

uint32_t MVKDescriptorUpdateTemplate::getNumberOfEntries() const {
	return (uint32_t)_entries.size();
}

VkDescriptorUpdateTemplateType MVKDescriptorUpdateTemplate::getType() const {
	return _type;
}

MVKDescriptorUpdateTemplate::MVKDescriptorUpdateTemplate(MVKDevice* device,
														 const VkDescriptorUpdateTemplateCreateInfo* pCreateInfo) :
MVKVulkanAPIDeviceObject(device), _pipelineBindPoint(pCreateInfo->pipelineBindPoint), _type(pCreateInfo->templateType) {

	for (uint32_t i = 0; i < pCreateInfo->descriptorUpdateEntryCount; i++) {
		const auto& entry = pCreateInfo->pDescriptorUpdateEntries[i];
		_entries.push_back(entry);

		// Accumulate the size of the template. If we were given a stride, use that;
		// otherwise, assume only one info struct of the appropriate type.
		size_t entryEnd = entry.offset;
		if (entry.stride) {
			entryEnd += entry.stride * entry.descriptorCount;
		} else {
			switch (entry.descriptorType) {
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
					entryEnd += sizeof(VkDescriptorBufferInfo);
					break;

				case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
				case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
				case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
				case VK_DESCRIPTOR_TYPE_SAMPLER:
				case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
					entryEnd += sizeof(VkDescriptorImageInfo);
					break;

				case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
				case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
					entryEnd += sizeof(VkBufferView);
					break;

				default:
					break;
			}
		}
		_size = std::max(_size, entryEnd);
	}
}
