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
 * (Note that OutlinedData is one element in the descriptor regardless of descriptorCount)
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

/** Select an argument buffer mode for the given device.  Descriptor sets on the device may use this mode or Off, but not any others. */
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

/** Select an argument buffer mode for the given device descriptor layout. */
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

/** Binding metadata about immutable samplers and their ycbcr plane counts */
class ImmutableSamplerPlaneInfo {
	/**
	 * bit 0: 1 if has non-ycbcr immutable samplers
	 * bits 1:30: max ycbcr plane count
	 * bit 31: if set, this is just asking for the maximum size, and the rest of the bits don't matter
	 */
	uint32_t data;
public:
	/**
	 * Check whether the descriptor has immutable samplers.
	 * Note that this will return false on MaxSize, while hasYCBCR will return true.
	 * (Use in situations where having an immutable sampler requiers less space than not having one)
	 */
	bool hasImmutableSamplers() const { return static_cast<int32_t>(data) > 0; }
	/** Check whether the descriptor has non-ycbcr immutable samplers */
	bool hasYCBCR() const { return data >> 1; }
	/** Check whether the descriptor has ycbcr immutable samplers */
	bool hasNonYCBCR() const { return data & 1; }
	bool isMaxSize() const { return static_cast<int32_t>(data) < 0; }
	/** Get the number of planes.  If MaxSize, will return an incredibly large number. */
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
	/** Get the worst case from a size perspective, when you don't know the full details */
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
	ImmutableSamplerPlaneInfo planes = ImmutableSamplerPlaneInfo::MaxSize())
{
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
	ImmutableSamplerPlaneInfo planes = ImmutableSamplerPlaneInfo::MaxSize())
{
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

#pragma mark - MVKDescriptorSetLayoutNew

MVKDescriptorSetLayoutNew::MVKDescriptorSetLayoutNew(MVKDevice* device): MVKVulkanAPIDeviceObject(device) {}

MVKDescriptorSetLayoutNew* MVKDescriptorSetLayoutNew::Create(MVKDevice* device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo) {
	using Constructor = MVKInlineObjectConstructor<MVKDescriptorSetLayoutNew>;
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

	MVKDescriptorSetLayoutNew* ret = Constructor::Create(
		std::tuple {
			Constructor::Init(&MVKDescriptorSetLayoutNew::_mtlArgumentEncoder, argBufMode == MVKArgumentBufferMode::ArgEncoder && !isVariable),
			Constructor::Init(&MVKDescriptorSetLayoutNew::_mtlArgumentEncoderVariable, argBufMode == MVKArgumentBufferMode::ArgEncoder && isVariable),
			Constructor::Uninit(&MVKDescriptorSetLayoutNew::_bindings, numBindings),
			Constructor::Uninit(&MVKDescriptorSetLayoutNew::_immutableSamplers, numImmutableSamplers),
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

uint32_t MVKDescriptorSetLayoutNew::getBindingIndex(uint32_t binding) const {
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

MVKMTLArgumentEncoder& MVKDescriptorSetLayoutNew::getVariableArgumentEncoder(uint32_t variableCount) const {
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
		case VK_DESCRIPTOR_TYPE_MAX_ENUM:
			break;
	}
	assert(0);
	return MVKDescriptorUpdateSourceType::Unsupported;
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
	const MVKDescriptorBinding* binding, const MVKDescriptorSetNew* set,
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
	const MVKDescriptorSetLayoutNew* layout,
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

static void writeDescriptorSetBinding(
	const MVKDescriptorSetLayoutNew* layout,
	const MVKDescriptorBinding* binding, const MVKDescriptorSetNew* set, id<MTLArgumentEncoder> enc,
	const void* src, MVKDescriptorUpdateSourceType type, size_t stride,
	uint32_t start, uint32_t count)
{
	char* cpuBuffer = set->cpuBuffer + binding->cpuOffset;
	switch (binding->cpuLayout) {
#define CASE(x) case MVKDescriptorCPULayout::x: \
			writeDescriptorSetCPUBuffer<MVKDescriptorCPULayout::x>( \
				layout, *binding, cpuBuffer, src, stride, type, start, count); \
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
			[enc setTexture:tex && device->getLiveResources().isLiveHoldingLock(tex) ? tex : nil atIndex:start + i];
		} else if constexpr (Layout == MVKDescriptorGPULayout::Sampler) {
			id<MTLSamplerState> samp = *reinterpret_cast<const id<MTLSamplerState>*>(src);
			[enc setSamplerState:samp && device->getLiveResources().isLiveHoldingLock(samp) ? samp : nil atIndex:start + i];
		} else if constexpr (Layout == MVKDescriptorGPULayout::Buffer) {
			id<MTLBuffer> buf = *reinterpret_cast<const id<MTLBuffer>*>(src);
			uint64_t offset = *reinterpret_cast<const uint64_t*>(src + bufferOffsetOffset);
			if (buf && !device->getLiveResources().isLiveHoldingLock(buf)) {
				buf = nil;
				offset = 0;
			}
			[enc setBuffer:buf offset:offset atIndex:start + i];
		} else {
			static_assert(Layout != Layout, "Other layouts are unsupported");
		}
	}
}

static void copyDescriptorSetBinding(
	const MVKDescriptorSetLayoutNew* dstLayout,
	const MVKDescriptorBinding* srcBinding, const MVKDescriptorSetNew* srcSet, id<MTLArgumentEncoder> srcEnc,
	const MVKDescriptorBinding* dstBinding, const MVKDescriptorSetNew* dstSet, id<MTLArgumentEncoder> dstEnc,
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

static bool needsLiveCheckForArgBufCopy(const MVKDescriptorBinding* binding) {
	switch (binding->gpuLayout) {
		case MVKDescriptorGPULayout::Sampler:
			return !binding->hasImmutableSamplers();
		case MVKDescriptorGPULayout::Texture:
		case MVKDescriptorGPULayout::Buffer:
		case MVKDescriptorGPULayout::BufferAuxSize:
		case MVKDescriptorGPULayout::TexBufSoA:
		case MVKDescriptorGPULayout::TexSampSoA:
		case MVKDescriptorGPULayout::Tex2SampSoA:
		case MVKDescriptorGPULayout::Tex3SampSoA:
			return true;
		case MVKDescriptorGPULayout::OutlinedData:
		case MVKDescriptorGPULayout::InlineData:
		case MVKDescriptorGPULayout::None:
			return false;
	}
}

static bool needsSourceArgumentEncoderToCopy(const MVKDescriptorBinding* binding) {
	return binding->gpuLayout == MVKDescriptorGPULayout::InlineData;
}

/** Tracks the needed locks for descriptor set updating with argument encoders */
class DescriptorSetUpdateLockTracker {
	MVKMTLArgumentEncoder* dstEnc = nullptr;
	MVKMTLArgumentEncoder* srcEnc = nullptr;
	MVKDevice* liveResourceLockDevice = nullptr;

	// Texel buffers lazily create their textures, which means writes may exclusive lock the live resource lock with arg encoder locks held.
	// So the live resources lock must be taken last (and be unlocked if any new argument encoders need to be locked).

	void unlockAndNullLiveResourceLock() {
		if (auto* dev = liveResourceLockDevice) {
			liveResourceLockDevice = nullptr;
			dev->getLiveResources().lock.unlock_shared();
		}
	}

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
		assert(!liveResourceLockDevice);
		if (dstEnc == enc)
			return;
		unlockAndReplace(&dstEnc, enc);
	}

	/** Lock the dst encoder */
	void lockDst(MVKMTLArgumentEncoder* enc) {
		if (dstEnc == enc)
			return;
		if ((liveResourceLockDevice || srcEnc) && tryLock(&dstEnc, enc))
			return;
		unlockAndNullLiveResourceLock();
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
		} else if (liveResourceLockDevice) {
			if (tryLock(targetL, encoderL) && tryLock(targetH, encoderH))
				return;
		}

		if (*targetL != encoderL) {
			// Failed to lock the lower encoder, so everything needs to be unlocked and then relocked
			unlockAndNullLiveResourceLock();
			unlock(targetH); // Can't use unlockAndReplace because we need to unlock both old encoders before locking either new one
			unlock(targetL);
			*targetL = encoderL;
			*targetH = encoderH;
			encoderL->_lock.lock();
			encoderH->_lock.lock();
		} else {
			// Lower encoder can stay locked, just need to lock upper.
			unlockAndNullLiveResourceLock();
			unlockAndReplace(targetH, encoderH);
		}
	}

	void lockLiveResourceLock(MVKDevice* dev) {
		if (liveResourceLockDevice) {
			// We should always use the same device
			assert(liveResourceLockDevice == dev);
		} else {
			liveResourceLockDevice = dev;
			liveResourceLockDevice->getLiveResources().lock.lock_shared();
		}
	}

	bool hasLiveResourceLock() const { return liveResourceLockDevice; }

	~DescriptorSetUpdateLockTracker() {
		if (dstEnc) {
			dstEnc->_lock.unlock();
			if (srcEnc)
				srcEnc->_lock.unlock();
			if (liveResourceLockDevice)
				liveResourceLockDevice->getLiveResources().lock.unlock_shared();
		} else {
			assert(!srcEnc);
			assert(!liveResourceLockDevice);
		}
	}
};

void mvkUpdateDescriptorSetsNew(uint32_t numWrites, const VkWriteDescriptorSet* pDescriptorWrites,
                                uint32_t numCopies, const VkCopyDescriptorSet* pDescriptorCopies);

void mvkUpdateDescriptorSetsNew(uint32_t numWrites, const VkWriteDescriptorSet* pDescriptorWrites,
                                uint32_t numCopies, const VkCopyDescriptorSet* pDescriptorCopies)
{
	DescriptorSetUpdateLockTracker locks;
	MVKDescriptorSetNew* lastDstSet = nullptr;
	MVKDescriptorSetNew* lastSrcSet = nullptr;
	for (const auto& write : MVKArrayRef(pDescriptorWrites, numWrites)) {
		MVKDescriptorUpdateSourceType type = getDescriptorUpdateSourceType(write.descriptorType);
		uint32_t stride = getDescriptorUpdateStride(type);
		const void* src;
		switch (type) {
			case MVKDescriptorUpdateSourceType::Sampler:
			case MVKDescriptorUpdateSourceType::ImageSampler:
			case MVKDescriptorUpdateSourceType::Image:
				src = write.pImageInfo;
				break;
			case MVKDescriptorUpdateSourceType::Buffer:
				src = write.pBufferInfo;
				break;
			case MVKDescriptorUpdateSourceType::TexelBuffer:
				src = write.pTexelBufferView;
				break;
			case MVKDescriptorUpdateSourceType::InlineUniform:
				src = mvkFindStructInChain<VkWriteDescriptorSetInlineUniformBlock>(&write, VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK)->pData;
				break;
			case MVKDescriptorUpdateSourceType::Unsupported:
				return;
		}
		MVKDescriptorSetNew* set = reinterpret_cast<MVKDescriptorSetNew*>(write.dstSet);
		const MVKDescriptorSetLayoutNew* layout = set->layout;
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
		MVKDescriptorSetNew* srcSet = reinterpret_cast<MVKDescriptorSetNew*>(copy.srcSet);
		MVKDescriptorSetNew* dstSet = reinterpret_cast<MVKDescriptorSetNew*>(copy.dstSet);
		assert(srcSet->layout->argBufMode() == dstSet->layout->argBufMode());
		const MVKDescriptorSetLayoutNew* srcLayout = srcSet->layout;
		const MVKDescriptorSetLayoutNew* dstLayout = dstSet->layout;
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
			if (!locks.hasLiveResourceLock() && needsLiveCheckForArgBufCopy(dstBinding))
				locks.lockLiveResourceLock(dstLayout->getDevice());
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

void mvkUpdateDescriptorSetWithTemplateNew(VkDescriptorSet set, VkDescriptorUpdateTemplate updateTemplate, const void* pData);

/** Updates the resource bindings in the given descriptor set from the specified template. */
void mvkUpdateDescriptorSetWithTemplateNew(VkDescriptorSet set, VkDescriptorUpdateTemplate updateTemplate, const void* pData) {

	auto* dstSet = reinterpret_cast<MVKDescriptorSetNew*>(set);
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

#pragma mark - MVKDescriptorPoolNew

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

MVKDescriptorPoolNew::MVKDescriptorPoolNew(MVKDevice* device): MVKVulkanAPIDeviceObject(device) {}

MVKDescriptorPoolNew* MVKDescriptorPoolNew::Create(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo) {
	using Constructor = MVKInlineObjectConstructor<MVKDescriptorPoolNew>;
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

	MVKDescriptorPoolNew* ret = Constructor::Create(
		std::tuple {
			Constructor::Uninit(&MVKDescriptorPoolNew::_descriptorSets, pCreateInfo->maxSets),
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

MVKDescriptorPoolNew::~MVKDescriptorPoolNew() {
	[_gpuBufferObject release];
}

// Find and return an array of variable descriptor counts from the pNext chain of pCreateInfo,
// or return nullptr if the chain does not include variable descriptor counts.
static const uint32_t* getVariableDecriptorCounts(const VkDescriptorSetAllocateInfo* pAllocateInfo) {
	auto* counts = mvkFindStructInChain<VkDescriptorSetVariableDescriptorCountAllocateInfo>(pAllocateInfo, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO);
	return counts && counts->descriptorSetCount ? counts->pDescriptorCounts : nullptr;
}

VkResult MVKDescriptorPoolNew::allocateDescriptorSets(const VkDescriptorSetAllocateInfo* pAllocateInfo,
                                                      VkDescriptorSet* pDescriptorSets)
{
	const uint32_t* pVarDescCounts = getVariableDecriptorCounts(pAllocateInfo);
	const VkDescriptorSetLayout* pSetLayouts = pAllocateInfo->pSetLayouts;
	for (uint32_t dsIdx = 0, end = pAllocateInfo->descriptorSetCount; dsIdx < end; dsIdx++) {
		MVKDescriptorSetLayoutNew* mvkDSL = reinterpret_cast<MVKDescriptorSetLayoutNew*>(pSetLayouts[dsIdx]);
		if (!mvkDSL->isPushDescriptorSetLayout()) {
			if (MVKDescriptorSetNew* set = allocateDescriptorSet()) {
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

MVKDescriptorSetNew* MVKDescriptorPoolNew::allocateDescriptorSet() {
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

VkResult MVKDescriptorPoolNew::initDescriptorSet(MVKDescriptorSetLayoutNew* mvkDSL, uint32_t variableDescriptorCount, MVKDescriptorSetNew* set) {
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

VkResult MVKDescriptorPoolNew::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	if (_freeAllowed) {
		for (uint32_t i = 0; i < count; i++) {
			if (pDescriptorSets[i] == VK_NULL_HANDLE)
				continue;
			MVKDescriptorSetListItem* setItem = reinterpret_cast<MVKDescriptorSetListItem*>(pDescriptorSets[i]);
			MVKDescriptorSetNew* set = &setItem->allocated;
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
			MVKDescriptorSetNew* set = reinterpret_cast<MVKDescriptorSetNew*>(pDescriptorSets[i]);
			assert(set == &_descriptorSets[_numAllocatedDescriptorSets - count + i].allocated);
			_gpuBufferUsed -= set->gpuBufferSize;
			_cpuBufferUsed -= set->cpuBufferSize;
		}
		_numAllocatedDescriptorSets -= count;
	}
	return VK_SUCCESS;
}

VkResult MVKDescriptorPoolNew::reset(VkDescriptorPoolResetFlags flags) {
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

// The size of one Metal3 Argument Buffer slot in bytes.
static const size_t kMVKMetal3ArgBuffSlotSizeInBytes = sizeof(uint64_t);


#pragma mark -
#pragma mark MVKMetalArgumentBuffer

void MVKMetalArgumentBuffer::setArgumentBuffer(id<MTLBuffer> mtlArgBuff,
											   NSUInteger mtlArgBuffOfst,
											   NSUInteger mtlArgBuffEncSize,
											   id<MTLArgumentEncoder> mtlArgEnc) {
	_mtlArgumentBuffer = mtlArgBuff;
	_mtlArgumentBufferOffset = mtlArgBuffOfst;
	_mtlArgumentBufferEncodedSize = mtlArgBuffEncSize;

	auto* oldArgEnc = _mtlArgumentEncoder;
	_mtlArgumentEncoder = [mtlArgEnc retain];	// retained
	[_mtlArgumentEncoder setArgumentBuffer: _mtlArgumentBuffer offset: _mtlArgumentBufferOffset];
	[oldArgEnc release];
}

void MVKMetalArgumentBuffer::setBuffer(id<MTLBuffer> mtlBuff, NSUInteger offset, uint32_t index) {
	if (_mtlArgumentEncoder) {
		[_mtlArgumentEncoder setBuffer: mtlBuff offset: offset atIndex: index];
	} else {
#if MVK_XCODE_14
		*(uint64_t*)getArgumentPointer(index) = mtlBuff.gpuAddress + offset;
#endif
	}
}

void MVKMetalArgumentBuffer::setTexture(id<MTLTexture> mtlTex, uint32_t index) {
	if (_mtlArgumentEncoder) {
		[_mtlArgumentEncoder setTexture: mtlTex atIndex: index];
	} else {
#if MVK_XCODE_14
		*(MTLResourceID*)getArgumentPointer(index) = mtlTex.gpuResourceID;
#endif
	}
}

void MVKMetalArgumentBuffer::setSamplerState(id<MTLSamplerState> mtlSamp, uint32_t index) {
	if (_mtlArgumentEncoder) {
		[_mtlArgumentEncoder setSamplerState: mtlSamp atIndex: index];
	} else {
#if MVK_XCODE_14
		*(MTLResourceID*)getArgumentPointer(index) = mtlSamp.gpuResourceID;
#endif
	}
}

// Returns the address of the slot at the index within the Metal argument buffer.
// This is based on the Metal 3 design that all arg buffer slots are 64 bits.
void* MVKMetalArgumentBuffer::getArgumentPointer(uint32_t index) const {
	return (void*)((uintptr_t)_mtlArgumentBuffer.contents + _mtlArgumentBufferOffset + (index * kMVKMetal3ArgBuffSlotSizeInBytes));
}

MVKMetalArgumentBuffer::~MVKMetalArgumentBuffer() { [_mtlArgumentEncoder release]; }


#pragma mark -
#pragma mark MVKDescriptorSetLayout

void MVKDescriptorSetLayout::appendDescriptorSetBindings(
	MVKBindingList& target,
	MVKSmallVector<uint32_t, 8>& targetDynamicOffsets,
	MVKShaderStage stage,
	uint32_t index,
	MVKDescriptorSet* set,
	const MVKShaderStageResourceBinding& indexOffsets,
	const uint32_t*& dynamicOffsets)
{
	if (_isPushDescriptorLayout) return;
	if (isUsingMetalArgumentBuffers()) {
		// Bind argument buffer
		MVKMTLBufferBinding bb;
		auto& argbuf = set->getMetalArgumentBuffer();
		bb.mtlBuffer = argbuf.getMetalArgumentBuffer();
		bb.offset = argbuf.getMetalArgumentBufferOffset();
		bb.index = index;
		target.bufferBindings.push_back(bb);
		// Copy dynamic offsets
		uint32_t offsetCount = set->getDynamicOffsetDescriptorCount();
		uint32_t baseOffset = indexOffsets.dynamicOffsetBufferIndex;
		const uint32_t* dynamicOffsetsIn = dynamicOffsets;
		dynamicOffsets += offsetCount;
		for (uint32_t i = 0; i < offsetCount; i++) {
			uint32_t write = i + baseOffset;
			if (targetDynamicOffsets.size() <= write) {
				targetDynamicOffsets.resize(write + 1);
			}
			targetDynamicOffsets[write] = dynamicOffsetsIn[i];
		}
	} else {
		for (auto& binding : _bindings) {
			binding.appendBindings(target, stage, set, indexOffsets, dynamicOffsets);
		}
	}
}

static const void* getWriteParameters(VkDescriptorType type, const VkDescriptorImageInfo* pImageInfo,
                                      const VkDescriptorBufferInfo* pBufferInfo, const VkBufferView* pTexelBufferView,
                                      const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock,
                                      size_t& stride) {
    const void* pData;
    switch (type) {
    case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
    case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
    case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
    case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
        pData = pBufferInfo;
        stride = sizeof(VkDescriptorBufferInfo);
        break;

    case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
    case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
    case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
    case VK_DESCRIPTOR_TYPE_SAMPLER:
    case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
        pData = pImageInfo;
        stride = sizeof(VkDescriptorImageInfo);
        break;

    case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
    case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
        pData = pTexelBufferView;
        stride = sizeof(MVKBufferView*);
        break;

    case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
        pData = pInlineUniformBlock;
        stride = sizeof(VkWriteDescriptorSetInlineUniformBlock);
        break;

    default:
        pData = nullptr;
        stride = 0;
    }
    return pData;
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                               VkPipelineBindPoint pipelineBindPoint,
                                               MVKArrayRef<VkWriteDescriptorSet> descriptorWrites,
                                               MVKShaderResourceBinding& dslMTLRezIdxOffsets) {

    if (!_isPushDescriptorLayout) return;

	if (!cmdEncoder) { clearConfigurationResult(); }

	for (const VkWriteDescriptorSet& descWrite : descriptorWrites) {
        uint32_t dstBinding = descWrite.dstBinding;
        uint32_t dstArrayElement = descWrite.dstArrayElement;
        uint32_t descriptorCount = descWrite.descriptorCount;
        const VkDescriptorImageInfo* pImageInfo = descWrite.pImageInfo;
        const VkDescriptorBufferInfo* pBufferInfo = descWrite.pBufferInfo;
        const VkBufferView* pTexelBufferView = descWrite.pTexelBufferView;
        const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock = nullptr;
		for (const auto* next = (VkBaseInStructure*)descWrite.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
					break;
				}
				default:
					break;
			}
		}
        if (!_bindingToIndex.count(dstBinding)) continue;
        // Note: This will result in us walking off the end of the array
        // in case there are too many updates... but that's ill-defined anyway.
        for (; descriptorCount; dstBinding++) {
            if (!_bindingToIndex.count(dstBinding)) continue;
            size_t stride;
            const void* pData = getWriteParameters(descWrite.descriptorType, pImageInfo,
                                                   pBufferInfo, pTexelBufferView, pInlineUniformBlock, stride);
            uint32_t descriptorsPushed = 0;
            uint32_t bindIdx = _bindingToIndex[dstBinding];
            _bindings[bindIdx].push(cmdEncoder, pipelineBindPoint, dstArrayElement, descriptorCount,
                                    descriptorsPushed, descWrite.descriptorType,
                                    stride, pData, dslMTLRezIdxOffsets);
            pBufferInfo += descriptorsPushed;
            pImageInfo += descriptorsPushed;
            pTexelBufferView += descriptorsPushed;
        }
    }
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                               MVKDescriptorUpdateTemplate* descUpdateTemplate,
                                               const void* pData,
                                               MVKShaderResourceBinding& dslMTLRezIdxOffsets) {

    if (!_isPushDescriptorLayout ||
        descUpdateTemplate->getType() != VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS)
        return;

	if (!cmdEncoder) { clearConfigurationResult(); }
	VkPipelineBindPoint bindPoint = descUpdateTemplate->getBindPoint();
    for (uint32_t i = 0; i < descUpdateTemplate->getNumberOfEntries(); i++) {
        const VkDescriptorUpdateTemplateEntry* pEntry = descUpdateTemplate->getEntry(i);
        uint32_t dstBinding = pEntry->dstBinding;
        uint32_t dstArrayElement = pEntry->dstArrayElement;
        uint32_t descriptorCount = pEntry->descriptorCount;
        const void* pCurData = (const char*)pData + pEntry->offset;
        if (!_bindingToIndex.count(dstBinding)) continue;
        // Note: This will result in us walking off the end of the array
        // in case there are too many updates... but that's ill-defined anyway.
        for (; descriptorCount; dstBinding++) {
            if (!_bindingToIndex.count(dstBinding)) continue;
            uint32_t descriptorsPushed = 0;
            uint32_t bindIdx = _bindingToIndex[dstBinding];
            _bindings[bindIdx].push(cmdEncoder, bindPoint, dstArrayElement, descriptorCount,
                                    descriptorsPushed, pEntry->descriptorType,
                                    pEntry->stride, pCurData, dslMTLRezIdxOffsets);
            pCurData = (const char*)pCurData + pEntry->stride * descriptorsPushed;
        }
    }
}

static void populateAuxBuffer(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
							  MVKShaderStageResourceBinding buffBinding,
							  uint32_t descSetIndex,
							  uint32_t descBinding,
							  bool usingNativeTextureAtomics) {
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		mvkPopulateShaderConversionConfig(shaderConfig,
										  buffBinding,
										  MVKShaderStage(stage),
										  descSetIndex,
										  descBinding,
										  1,
										  VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
										  nullptr,
										  usingNativeTextureAtomics);
	}
}

void MVKDescriptorSetLayout::populateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
                                                            MVKShaderResourceBinding& dslMTLRezIdxOffsets,
															uint32_t descSetIndex) {
	uint32_t bindCnt = (uint32_t)_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		_bindings[bindIdx].populateShaderConversionConfig(shaderConfig, dslMTLRezIdxOffsets, descSetIndex);
	}

	// If this descriptor set is using an argument buffer, and needs a buffer size auxiliary buffer, add it.
	if (isUsingMetalArgumentBuffers() && needsBufferSizeAuxBuffer()) {
		MVKShaderStageResourceBinding buffBinding;
		buffBinding.bufferIndex = getBufferSizeBufferArgBuferIndex();
		populateAuxBuffer(shaderConfig, buffBinding, descSetIndex,
						  SPIRV_CROSS_NAMESPACE::kBufferSizeBufferBinding,
						  getMetalFeatures().nativeTextureAtomics);
	}

	// If the app is using argument buffers, but this descriptor set is 
	// not, because this is a discrete descriptor set, mark it as such.
	if(MVKDeviceTrackingMixin::isUsingMetalArgumentBuffers() && !isUsingMetalArgumentBuffers()) {
		shaderConfig.discreteDescriptorSets.push_back(descSetIndex);
	}
}

bool MVKDescriptorSetLayout::populateBindingUse(MVKBitArray& bindingUse,
                                                mvk::SPIRVToMSLConversionConfiguration& context,
                                                MVKShaderStage stage,
                                                uint32_t descSetIndex) {
	static const spv::ExecutionModel spvExecModels[] = {
		spv::ExecutionModelVertex,
		spv::ExecutionModelTessellationControl,
		spv::ExecutionModelTessellationEvaluation,
		spv::ExecutionModelFragment,
		spv::ExecutionModelGLCompute
	};

	bool descSetIsUsed = false;
	uint32_t bindCnt = (uint32_t)_bindings.size();
	bindingUse.resize(bindCnt);
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		auto& dslBind = _bindings[bindIdx];
		if (context.isResourceUsed(spvExecModels[stage], descSetIndex, dslBind.getBinding())) {
			bindingUse.enableBit(bindIdx);
			descSetIsUsed = true;
		}
	}
	return descSetIsUsed;
}

bool MVKDescriptorSetLayout::isUsingMetalArgumentBuffers() const {
	return MVKDeviceTrackingMixin::isUsingMetalArgumentBuffers() && _canUseMetalArgumentBuffer;
};

// Returns an autoreleased MTLArgumentDescriptor suitable for adding an auxiliary buffer to the argument buffer.
static MTLArgumentDescriptor* getAuxBufferArgumentDescriptor(uint32_t argIndex) {
	auto* argDesc = [MTLArgumentDescriptor argumentDescriptor];
	argDesc.dataType = MTLDataTypePointer;
	argDesc.access = MTLArgumentAccessReadWrite;
	argDesc.index = argIndex;
	argDesc.arrayLength = 1;
	return argDesc;
}

// Returns an autoreleased MTLArgumentEncoder for a descriptor set, or nil if not needed.
// Make sure any call to this function is wrapped in @autoreleasepool.
id <MTLArgumentEncoder> MVKDescriptorSetLayout::getMTLArgumentEncoder(uint32_t variableDescriptorCount) {
	auto* encoderArgs = [NSMutableArray arrayWithCapacity: _bindings.size() * 2];	// Double it to cover potential multi-resource descriptors (combo image/samp, multi-planar, etc).

	// Buffer sizes buffer at front
	if (needsBufferSizeAuxBuffer()) {
		[encoderArgs addObject: getAuxBufferArgumentDescriptor(getBufferSizeBufferArgBuferIndex())];
	}
	for (auto& dslBind : _bindings) {
		dslBind.addMTLArgumentDescriptors(encoderArgs, variableDescriptorCount);
	}
	return encoderArgs.count ? [[getMTLDevice() newArgumentEncoderWithArguments: encoderArgs] autorelease] : nil;
}

// Returns the encoded byte length of the resources from a descriptor set in an argument buffer.
size_t MVKDescriptorSetLayout::getMetal3ArgumentBufferEncodedLength(uint32_t variableDescriptorCount) {
	size_t encodedLen =  0;

	// Buffer sizes buffer at front
	if (needsBufferSizeAuxBuffer()) {
		encodedLen += kMVKMetal3ArgBuffSlotSizeInBytes;
	}
	for (auto& dslBind : _bindings) {
		encodedLen += dslBind.getMTLResourceCount(variableDescriptorCount) * kMVKMetal3ArgBuffSlotSizeInBytes;
	}
	return encodedLen;
}

uint32_t MVKDescriptorSetLayout::getDescriptorCount(uint32_t variableDescriptorCount) {
	uint32_t descCnt =  0;
	for (auto& dslBind : _bindings) {
		descCnt += dslBind.getDescriptorCount(variableDescriptorCount);
	}
	return descCnt;
}

MVKDescriptorSetLayoutBinding* MVKDescriptorSetLayout::getBinding(uint32_t binding, uint32_t bindingIndexOffset) {
	auto itr = _bindingToIndex.find(binding);
	if (itr != _bindingToIndex.end()) {
		uint32_t bindIdx = itr->second + bindingIndexOffset;
		if (bindIdx < _bindings.size()) {
			return &_bindings[bindIdx];
		}
	}
	return nullptr;
}

MVKDescriptorSetLayout::MVKDescriptorSetLayout(MVKDevice* device,
                                               const VkDescriptorSetLayoutCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	const VkDescriptorBindingFlags* pBindingFlags = nullptr;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO: {
				auto* pDescSetLayoutBindingFlags = (VkDescriptorSetLayoutBindingFlagsCreateInfo*)next;
				if (pDescSetLayoutBindingFlags->bindingCount) {
					pBindingFlags = pDescSetLayoutBindingFlags->pBindingFlags;
				}
				break;
			}
			default:
				break;
		}
	}

	_isPushDescriptorLayout = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT);
	_canUseMetalArgumentBuffer = checkCanUseArgumentBuffers(pCreateInfo);	// After _isPushDescriptorLayout

	// The bindings in VkDescriptorSetLayoutCreateInfo do not need to be provided in order of binding number.
	// However, several subsequent operations, such as the dynamic offsets in vkCmdBindDescriptorSets()
	// are ordered by binding number. To prepare for this, sort the bindings by binding number.
	struct BindInfo {
		const VkDescriptorSetLayoutBinding* pBinding;
		VkDescriptorBindingFlags bindingFlags;
	};
	MVKSmallVector<BindInfo, 64> sortedBindings;

	bool needsBuffSizeAuxBuff = false;
	uint32_t bindCnt = pCreateInfo->bindingCount;
	sortedBindings.reserve(bindCnt);
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		auto* pBind = &pCreateInfo->pBindings[bindIdx];
		sortedBindings.push_back( { pBind, pBindingFlags ? pBindingFlags[bindIdx] : 0 } );
		needsBuffSizeAuxBuff = needsBuffSizeAuxBuff || mvkNeedsBuffSizeAuxBuffer(pBind);
	}
	std::sort(sortedBindings.begin(), sortedBindings.end(), [](BindInfo bindInfo1, BindInfo bindInfo2) {
		return bindInfo1.pBinding->binding < bindInfo2.pBinding->binding;
	});

	// Create bindings. Must be done after _isPushDescriptorLayout & _canUseMetalArgumentBuffer are set.
	uint32_t dslDescCnt = 0;
	uint32_t dslMTLRezCnt = needsBuffSizeAuxBuff ? 1 : 0;	// If needed, leave a slot for the buffer sizes buffer at front.
	_bindings.reserve(bindCnt);
    for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		BindInfo& bindInfo = sortedBindings[bindIdx];
        _bindings.emplace_back(_device, this, bindInfo.pBinding, bindInfo.bindingFlags, dslDescCnt, dslMTLRezCnt);
		_bindingToIndex[bindInfo.pBinding->binding] = bindIdx;
	}

	MVKLogDebugIf(getMVKConfig().debugMode, "Created %s\n", getLogDescription().c_str());
}

std::string MVKDescriptorSetLayout::getLogDescription(std::string indent) {
	std::stringstream descStr;
	descStr << "VkDescriptorSetLayout with " << _bindings.size() << " bindings:";
	auto bindIndent = indent + "\t";
	for (auto& dlb : _bindings) {
		descStr << "\n" << bindIndent << dlb.getLogDescription(bindIndent);
	}
	return descStr.str();
}

// Check if argument buffers can be used, and return findings.
// Must be called after setting _isPushDescriptorLayout.
bool MVKDescriptorSetLayout::checkCanUseArgumentBuffers(const VkDescriptorSetLayoutCreateInfo* pCreateInfo) {

// iOS Tier 1 argument buffers do not support writable images.
#if MVK_IOS_OR_TVOS
	if (getMetalFeatures().argumentBuffersTier < MTLArgumentBuffersTier2) {
		for (uint32_t bindIdx = 0; bindIdx < pCreateInfo->bindingCount; bindIdx++) {
			switch (pCreateInfo->pBindings[bindIdx].descriptorType) {
				case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
				case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
					return false;
				default:
					break;
			}
		}
	}
#endif

	return !_isPushDescriptorLayout;	// Push descriptors don't use argument buffers
}


#pragma mark -
#pragma mark MVKDescriptorSet

VkDescriptorType MVKDescriptorSet::getDescriptorType(uint32_t binding) {
	return _layout->getBinding(binding)->getDescriptorType();
}

MVKDescriptor* MVKDescriptorSet::getDescriptor(uint32_t binding, uint32_t elementIndex) {
	return _descriptors[_layout->getDescriptorIndex(binding, elementIndex)];
}

template<typename DescriptorAction>
void MVKDescriptorSet::write(const DescriptorAction* pDescriptorAction,
							 size_t srcStride,
							 const void* pData) {

	auto* mvkDSLBind = _layout->getBinding(pDescriptorAction->dstBinding);
	if (mvkDSLBind->getDescriptorType() == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
		// For inline buffers, descriptorCount is a byte count and dstArrayElement is a byte offset.
		// If needed, Vulkan allows updates to extend into subsequent bindings that are of the same type,
		// so iterate layout bindings and their associated descriptors, until all bytes are updated.
		const auto* pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)pData;
		uint32_t numBytesToCopy = pDescriptorAction->descriptorCount;
		uint32_t dstOffset = pDescriptorAction->dstArrayElement;
		uint32_t srcOffset = 0;
		while (mvkDSLBind && numBytesToCopy > 0 && srcOffset < pInlineUniformBlock->dataSize) {
			auto* mvkDesc = (MVKInlineUniformBlockDescriptor*)_descriptors[mvkDSLBind->_descriptorIndex];
			auto numBytesMoved = mvkDesc->writeBytes(mvkDSLBind, this, dstOffset, srcOffset, numBytesToCopy, pInlineUniformBlock);
			numBytesToCopy -= numBytesMoved;
			dstOffset = 0;
			srcOffset += numBytesMoved;
			mvkDSLBind = _layout->getBinding(mvkDSLBind->getBinding(), 1);	// Next binding if needed
		}
	} else {
		// We don't test against the descriptor count of the binding, because Vulkan allows
		// updates to extend into subsequent bindings that are of the same type, if needed.
		uint32_t srcElemIdx = 0;
		uint32_t dstElemIdx = pDescriptorAction->dstArrayElement;
		uint32_t descIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding, dstElemIdx);
		uint32_t descCnt = pDescriptorAction->descriptorCount;
		while (srcElemIdx < descCnt) {
			_descriptors[descIdx++]->write(mvkDSLBind, this, dstElemIdx++, srcElemIdx++, srcStride, pData);
		}
	}
}

void MVKDescriptorSet::read(const VkCopyDescriptorSet* pDescriptorCopy,
							VkDescriptorImageInfo* pImageInfo,
							VkDescriptorBufferInfo* pBufferInfo,
							VkBufferView* pTexelBufferView,
							VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {

	MVKDescriptorSetLayoutBinding* mvkDSLBind = _layout->getBinding(pDescriptorCopy->srcBinding);
	VkDescriptorType descType = mvkDSLBind->getDescriptorType();
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
		// For inline buffers, descriptorCount is a byte count and dstArrayElement is a byte offset.
		// If needed, Vulkan allows updates to extend into subsequent bindings that are of the same type,
		// so iterate layout bindings and their associated descriptors, until all bytes are updated.
		uint32_t numBytesToCopy = pDescriptorCopy->descriptorCount;
		uint32_t dstOffset = 0;
		uint32_t srcOffset = pDescriptorCopy->srcArrayElement;
		while (mvkDSLBind && numBytesToCopy > 0 && dstOffset < pInlineUniformBlock->dataSize) {
			auto* mvkDesc = (MVKInlineUniformBlockDescriptor*)_descriptors[mvkDSLBind->_descriptorIndex];
			auto numBytesMoved = mvkDesc->readBytes(mvkDSLBind, this, dstOffset, srcOffset, numBytesToCopy, pInlineUniformBlock);
			numBytesToCopy -= numBytesMoved;
			dstOffset += numBytesMoved;
			srcOffset = 0;
			mvkDSLBind = _layout->getBinding(mvkDSLBind->getBinding(), 1);	// Next binding if needed
		}
    } else {
		// We don't test against the descriptor count of the binding, because Vulkan allows
		// updates to extend into subsequent bindings that are of the same type, if needed.
		uint32_t srcElemIdx = pDescriptorCopy->srcArrayElement;
		uint32_t dstElemIdx = 0;
		uint32_t descIdx = _layout->getDescriptorIndex(pDescriptorCopy->srcBinding, srcElemIdx);
		uint32_t descCnt = pDescriptorCopy->descriptorCount;
		while (dstElemIdx < descCnt) {
			_descriptors[descIdx++]->read(mvkDSLBind, this, dstElemIdx++, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
		}
    }
}

MVKMTLBufferAllocation* MVKDescriptorSet::acquireMTLBufferRegion(NSUInteger length) {
	return _pool->_mtlBufferAllocator.acquireMTLBufferRegion(length);
}

VkResult MVKDescriptorSet::allocate(MVKDescriptorSetLayout* layout,
									uint32_t variableDescriptorCount,
									NSUInteger mtlArgBuffOffset,
									NSUInteger mtlArgBuffEncSize,
									id<MTLArgumentEncoder> mtlArgEnc) {
	_layout = layout;
	_layout->retain();
	_variableDescriptorCount = variableDescriptorCount;
	_argumentBuffer.setArgumentBuffer(_pool->_metalArgumentBuffer, mtlArgBuffOffset, mtlArgBuffEncSize, mtlArgEnc);

	uint32_t descCnt = layout->getDescriptorCount(variableDescriptorCount);
	_descriptors.reserve(descCnt);

	uint32_t bindCnt = (uint32_t)layout->_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		MVKDescriptorSetLayoutBinding* mvkDSLBind = &layout->_bindings[bindIdx];
		uint32_t elemCnt = mvkDSLBind->getDescriptorCount(variableDescriptorCount);
		for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
			VkDescriptorType descType = mvkDSLBind->getDescriptorType();
			MVKDescriptor* mvkDesc = nullptr;
			bool dynamicAllocation = true;
			setConfigurationResult(_pool->allocateDescriptor(descType, &mvkDesc, dynamicAllocation));	// Modifies dynamicAllocation.
			if (dynamicAllocation) { _allDescriptorsAreFromPool = false; }
			if ( !wasConfigurationSuccessful() ) { return getConfigurationResult(); }
			if (mvkDesc->usesDynamicBufferOffsets()) { _dynamicOffsetDescriptorCount++; }
			_descriptors.push_back(mvkDesc);
		}
		mvkDSLBind->encodeImmutableSamplersToMetalArgumentBuffer(this);
	}

	// If needed, allocate a MTLBuffer to track buffer sizes, and add it to the argument buffer.
	if (hasMetalArgumentBuffer() && _layout->needsBufferSizeAuxBuffer()) {
		uint32_t buffSizesSlotCount = _layout->_maxBufferIndex + 1;
		_bufferSizesBuffer = acquireMTLBufferRegion(buffSizesSlotCount * sizeof(uint32_t));
		_argumentBuffer.setBuffer(_bufferSizesBuffer->_mtlBuffer,
								  _bufferSizesBuffer->_offset,
								  _layout->getBufferSizeBufferArgBuferIndex());
	}

	return getConfigurationResult();
}

void MVKDescriptorSet::free(bool isPoolReset) {
	if(_layout) { _layout->release(); }
	_layout = nullptr;
	_dynamicOffsetDescriptorCount = 0;
	_variableDescriptorCount = 0;

	if (isPoolReset) { _argumentBuffer.setArgumentBuffer(_pool->_metalArgumentBuffer, 0, 0, nil); }
	else if (_argumentBuffer.getMetalArgumentBufferEncodedSize() != 0) {
		_pool->_freeArgBuffSpace += _argumentBuffer.getMetalArgumentBufferEncodedSize();
	}

	// If this is a pool reset, and all desciptors are from the pool, we don't need to free them.
	if ( !(isPoolReset && _allDescriptorsAreFromPool) ) {
		for (auto mvkDesc : _descriptors) { _pool->freeDescriptor(mvkDesc); }
	}
	_descriptors.clear();
	_descriptors.shrink_to_fit();
	_allDescriptorsAreFromPool = true;

	if (_bufferSizesBuffer) {
		_bufferSizesBuffer->returnToPool();
		_bufferSizesBuffer = nullptr;
	}

	clearConfigurationResult();
}

void MVKDescriptorSet::setBufferSize(uint32_t descIdx, uint32_t value) {
	if (_bufferSizesBuffer) {
		*(uint32_t*)((uintptr_t)_bufferSizesBuffer->getContents() + (descIdx * sizeof(uint32_t))) = value;
	}
}

void MVKDescriptorSet::encodeAuxBufferUsage(MVKCommandEncoder& mvkEncoder, MVKShaderStage stage) {
	if (_bufferSizesBuffer) {
		MTLRenderStages mtlRendStages = MTLRenderStageVertex | MTLRenderStageFragment;
		mvkEncoder.getState().encodeResourceUsage(mvkEncoder, stage, _bufferSizesBuffer->_mtlBuffer, MTLResourceUsageRead, mtlRendStages);
	}
}

MVKDescriptorSet::MVKDescriptorSet(MVKDescriptorPool* pool) : MVKVulkanAPIDeviceObject(pool->_device), _pool(pool) {
	free(true);
}

MVKDescriptorSet::~MVKDescriptorSet() {
	if(_layout) { _layout->release(); }
}


#pragma mark -
#pragma mark MVKDescriptorTypePool

// Find the next availalble descriptor in the pool. or if the pool is exhausted, optionally create one on the fly.
// The dynamicAllocation parameter is both an input and output parameter. Incoming, dynamicAllocation indicates that,
// if there are no more descriptors in this pool, a new descriptor should be created and returned.
// On return, dynamicAllocation indicates back to the caller whether a descriptor was dynamically created.
// If a descriptor could not be found in the pool and was not created dynamically, a null descriptor is returned.
template<class DescriptorClass>
VkResult MVKDescriptorTypePool<DescriptorClass>::allocateDescriptor(VkDescriptorType descType,
																	MVKDescriptor** pMVKDesc,
																	bool& dynamicAllocation,
																	MVKDescriptorPool* pool) {
	VkResult errRslt = VK_ERROR_OUT_OF_POOL_MEMORY;
	size_t availDescIdx = _availability.getIndexOfFirstEnabledBit();
	if (availDescIdx < size()) {
		_availability.disableBit(availDescIdx);		// Mark the descriptor as taken
		*pMVKDesc = &_descriptors[availDescIdx];
		(*pMVKDesc)->reset();						// Reset descriptor before reusing.
		dynamicAllocation = false;
		return VK_SUCCESS;
	} else if (dynamicAllocation) {
		*pMVKDesc = new DescriptorClass();
		reportWarning(errRslt, "VkDescriptorPool exhausted pool of %zu %s descriptors. Allocating descriptor dynamically.", size(), mvkVkDescriptorTypeName(descType));
		return VK_SUCCESS;
	} else {
		*pMVKDesc = nullptr;
		dynamicAllocation = false;
		return reportError(errRslt, "VkDescriptorPool exhausted pool of %zu %s descriptors.", size(), mvkVkDescriptorTypeName(descType));
	}
}

// If the descriptor is from the pool, mark it as available, otherwise destroy it.
// Pooled descriptors are held in contiguous memory, so the index of the returning
// descriptor can be calculated by typed pointer differences. The descriptor will
// be reset when it is re-allocated. This streamlines a pool reset().
template<typename DescriptorClass>
void MVKDescriptorTypePool<DescriptorClass>::freeDescriptor(MVKDescriptor* mvkDesc,
															MVKDescriptorPool* pool) {
	DescriptorClass* pDesc = (DescriptorClass*)mvkDesc;
	DescriptorClass* pFirstDesc = _descriptors.data();
	int64_t descIdx = pDesc >= pFirstDesc ? pDesc - pFirstDesc : pFirstDesc - pDesc;
	if (descIdx >= 0 && descIdx < size()) {
		_availability.enableBit(descIdx);
	} else {
		mvkDesc->destroy();
	}
}

// Preallocated descriptors will be reset when they are reused
template<typename DescriptorClass>
void MVKDescriptorTypePool<DescriptorClass>::reset() {
	_availability.enableAllBits();
}

template<typename DescriptorClass>
size_t MVKDescriptorTypePool<DescriptorClass>::getRemainingDescriptorCount() {
	size_t enabledCount = 0;
	_availability.enumerateEnabledBits([&](size_t bitIdx) { enabledCount++; return true; });
	return enabledCount;
}

template<typename DescriptorClass>
MVKDescriptorTypePool<DescriptorClass>::MVKDescriptorTypePool(size_t poolSize) :
	_descriptors(poolSize),
	_availability(poolSize, true) {}


#pragma mark -
#pragma mark MVKDescriptorPool

VkResult MVKDescriptorPool::allocateDescriptorSets(const VkDescriptorSetAllocateInfo* pAllocateInfo,
												   VkDescriptorSet* pDescriptorSets) {
	const uint32_t* pVarDescCounts = nullptr;
	for (const auto* next = (VkBaseInStructure*)pAllocateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO: {
				auto* pVarDescSetVarCounts = (VkDescriptorSetVariableDescriptorCountAllocateInfo*)next;
				pVarDescCounts = pVarDescSetVarCounts->descriptorSetCount ? pVarDescSetVarCounts->pDescriptorCounts : nullptr;
			}
			default:
				break;
		}
	}

	@autoreleasepool {
		auto dsCnt = pAllocateInfo->descriptorSetCount;
		for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
			MVKDescriptorSetLayout* mvkDSL = (MVKDescriptorSetLayout*)pAllocateInfo->pSetLayouts[dsIdx];
			if ( !mvkDSL->_isPushDescriptorLayout ) {
				VkResult rslt = allocateDescriptorSet(mvkDSL, (pVarDescCounts ? pVarDescCounts[dsIdx] : 0), &pDescriptorSets[dsIdx]);
				if (rslt) {
					// Per Vulkan spec, if any descriptor set allocation fails, free any successful
					// allocations, and populate all descriptor set pointers with VK_NULL_HANDLE.
					freeDescriptorSets(dsIdx, pDescriptorSets);
					for (uint32_t i = 0; i < dsCnt; i++) { pDescriptorSets[i] = VK_NULL_HANDLE; }
					return rslt;
				}
			} else {
				pDescriptorSets[dsIdx] = VK_NULL_HANDLE;
			}
		}
	}

	return VK_SUCCESS;
}

// Retrieves the first available descriptor set from the pool, and configures it.
// If none are available, returns an error.
VkResult MVKDescriptorPool::allocateDescriptorSet(MVKDescriptorSetLayout* mvkDSL,
												  uint32_t variableDescriptorCount,
												  VkDescriptorSet* pVKDS) {
	VkResult rslt = VK_ERROR_FRAGMENTED_POOL;
	size_t mtlArgBuffEncSize = 0;
	id<MTLArgumentEncoder> mtlArgEnc = nil;
	bool isUsingMetalArgBuff = mvkDSL->isUsingMetalArgumentBuffers();

	if (isUsingMetalArgBuff) {
		if (needsMetalArgumentBufferEncoders()) {
			mtlArgEnc = mvkDSL->getMTLArgumentEncoder(variableDescriptorCount);
			mtlArgBuffEncSize = mtlArgEnc.encodedLength;
		} else {
			mtlArgBuffEncSize = mvkDSL->getMetal3ArgumentBufferEncodedLength(variableDescriptorCount);
		}
		// If there isn't enough space left in the argument buffer, there's no need to check the individual pieces.
		if (mtlArgBuffEncSize > _freeArgBuffSpace) {
			// n.b. OUT_OF_POOL_MEMORY means "the total free space is not enough to satisfy the descriptor set allocation."
			// FRAGMENTED_POOL means "the total free space _is_ enough, but there's no free space big enough to hold the descriptor set."
			return VK_ERROR_OUT_OF_POOL_MEMORY;
		}
	}

	// If there aren't any available descriptor sets, there's no need to check the individual pieces.
	if (_descriptorSetAvailablility.getIndexOfFirstEnabledBit() == _descriptorSetAvailablility.size()) {
		return VK_ERROR_OUT_OF_POOL_MEMORY;
	}

	_descriptorSetAvailablility.enumerateEnabledBits([&](size_t dsIdx) {
		bool isSpaceAvail = true;		// If not using Metal arg buffers, space will always be available.
		MVKDescriptorSet* mvkDS = &_descriptorSets[dsIdx];
		NSUInteger mtlArgBuffOffset = 0;

		// If the desc set is using a Metal argument buffer, we must check if the desc set will fit in the slot
		// in the Metal argument buffer, if that slot was previously allocated for a returned descriptor set.
		if (isUsingMetalArgBuff) {
			mtlArgBuffOffset = mvkDS->getMetalArgumentBuffer().getMetalArgumentBufferOffset();

			// If the offset has not been set, and this is not the first desc set,
			// set the offset to align with the end of the previous desc set.
			if ( !mtlArgBuffOffset && dsIdx ) {
				auto& prevArgBuff = _descriptorSets[dsIdx - 1].getMetalArgumentBuffer();
				mtlArgBuffOffset = (prevArgBuff.getMetalArgumentBufferOffset() +
									mvkAlignByteCount(prevArgBuff.getMetalArgumentBufferEncodedSize(),
													  getMetalFeatures().mtlBufferAlignment));
			}

			// Get the offset of the next desc set, if one exists and
			// its offset has been set, or the end of the arg buffer.
			size_t nextDSIdx = dsIdx + 1;
			NSUInteger nextOffset = (nextDSIdx < _allocatedDescSetCount ? _descriptorSets[nextDSIdx].getMetalArgumentBuffer().getMetalArgumentBufferOffset() : 0);
			if ( !nextOffset ) { nextOffset = _metalArgumentBuffer.length; }

			isSpaceAvail = (mtlArgBuffOffset + mtlArgBuffEncSize) <= nextOffset;
		}

		if (isSpaceAvail) {
			rslt = mvkDS->allocate(mvkDSL, variableDescriptorCount, mtlArgBuffOffset, mtlArgBuffEncSize, mtlArgEnc);
			if (rslt) {
				freeDescriptorSet(mvkDS, false);
			} else {
				_descriptorSetAvailablility.disableBit(dsIdx);
				_allocatedDescSetCount = std::max(_allocatedDescSetCount, dsIdx + 1);
				if (isUsingMetalArgBuff) {
					_freeArgBuffSpace -= mtlArgBuffEncSize;
				}
				*pVKDS = (VkDescriptorSet)mvkDS;
			}
			return false;
		} else {
			return true;
		}
	});
	return rslt;
}

VkResult MVKDescriptorPool::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		freeDescriptorSet((MVKDescriptorSet*)pDescriptorSets[dsIdx], false);
	}
	return VK_SUCCESS;
}

// Descriptor sets are held in contiguous memory, so the index of the returning descriptor
// set can be calculated by pointer differences, and it can be marked as available.
// Don't bother individually set descriptor set availability if pool is being reset.
void MVKDescriptorPool::freeDescriptorSet(MVKDescriptorSet* mvkDS, bool isPoolReset) {
	if ( !mvkDS ) { return; }	// Vulkan allows NULL refs.

	if (mvkDS->_pool == this) {
		mvkDS->free(isPoolReset);
		if ( !isPoolReset ) {
			size_t dsIdx = mvkDS - _descriptorSets.data();
			_descriptorSetAvailablility.enableBit(dsIdx);
		}
	} else {
		reportError(VK_ERROR_INITIALIZATION_FAILED, "A descriptor set is being returned to a descriptor pool that did not allocate it.");
	}
}

// Free allocated descriptor sets and reset descriptor pools.
// Don't waste time freeing desc sets that were never allocated.
VkResult MVKDescriptorPool::reset(VkDescriptorPoolResetFlags flags) {
	for (uint32_t dsIdx = 0; dsIdx < _allocatedDescSetCount; dsIdx++) {
		freeDescriptorSet(&_descriptorSets[dsIdx], true);
	}
	_descriptorSetAvailablility.enableAllBits();

	if (_metalArgumentBuffer) {
		_freeArgBuffSpace = _metalArgumentBuffer.length;
	}

	_uniformBufferDescriptors.reset();
	_storageBufferDescriptors.reset();
	_uniformBufferDynamicDescriptors.reset();
	_storageBufferDynamicDescriptors.reset();
	_inlineUniformBlockDescriptors.reset();
	_sampledImageDescriptors.reset();
	_storageImageDescriptors.reset();
	_inputAttachmentDescriptors.reset();
	_samplerDescriptors.reset();
	_combinedImageSamplerDescriptors.reset();
	_uniformTexelBufferDescriptors.reset();
	_storageTexelBufferDescriptors.reset();

	_allocatedDescSetCount = 0;

	return VK_SUCCESS;
}

// Allocate a descriptor of the specified type
VkResult MVKDescriptorPool::allocateDescriptor(VkDescriptorType descriptorType,
											   MVKDescriptor** pMVKDesc,
											   bool& dynamicAllocation) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			return _uniformBufferDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			return _storageBufferDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			return _uniformBufferDynamicDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return _storageBufferDynamicDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
			return _inlineUniformBlockDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			return _sampledImageDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			return _storageImageDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return _inputAttachmentDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			return _samplerDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return _combinedImageSamplerDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			return _uniformTexelBufferDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			return _storageTexelBufferDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		default:
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "Unrecognized VkDescriptorType %d.", descriptorType);
	}
}

void MVKDescriptorPool::freeDescriptor(MVKDescriptor* mvkDesc) {
	VkDescriptorType descriptorType = mvkDesc->getDescriptorType();
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			return _uniformBufferDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			return _storageBufferDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			return _uniformBufferDynamicDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return _storageBufferDynamicDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
			return _inlineUniformBlockDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			return _sampledImageDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			return _storageImageDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return _inputAttachmentDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			return _samplerDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return _combinedImageSamplerDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			return _uniformTexelBufferDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			return _storageTexelBufferDescriptors.freeDescriptor(mvkDesc, this);

		default:
			reportError(VK_ERROR_INITIALIZATION_FAILED, "Unrecognized VkDescriptorType %d.", descriptorType);
	}
}

// Return the size of the preallocated pool for descriptors of the specified type.
// There may be more than one poolSizeCount instance for the desired VkDescriptorType.
// Accumulate the descriptor count for the desired VkDescriptorType accordingly.
// For descriptors of the VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK type,
// we accumulate the count via the pNext chain.
size_t MVKDescriptorPool::getPoolSize(const VkDescriptorPoolCreateInfo* pCreateInfo, VkDescriptorType descriptorType) {
	uint32_t descCnt = 0;
	if (descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_INLINE_UNIFORM_BLOCK_CREATE_INFO: {
					auto* pDescPoolInlineBlockCreateInfo = (VkDescriptorPoolInlineUniformBlockCreateInfo*)next;
					descCnt += pDescPoolInlineBlockCreateInfo->maxInlineUniformBlockBindings;
					break;
				}
				default:
					break;
			}
		}
	} else {
		for (uint32_t poolIdx = 0; poolIdx < pCreateInfo->poolSizeCount; poolIdx++) {
			auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
			if (poolSize.type == descriptorType) { descCnt += poolSize.descriptorCount; }
		}
	}
	return descCnt;
}

std::string MVKDescriptorPool::getLogDescription(std::string indent) {
#define STR(name) #name
#define printDescCnt(descType, spacing, descPool)  \
	if (_##descPool##Descriptors.size()) {  \
		descStr << "\n" << descCntIndent << STR(VK_DESCRIPTOR_TYPE_##descType) ": " spacing << _##descPool##Descriptors.size()  \
		<< "  (" << _##descPool##Descriptors.getRemainingDescriptorCount() << " remaining)"; }

	std::stringstream descStr;
	descStr << "VkDescriptorPool with " << _descriptorSetAvailablility.size() << " descriptor sets";
	descStr << " (reset " << (mvkIsAnyFlagEnabled(_flags, VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT) ? "or free" : "only") << ")";
	descStr << ", and pooled descriptors:";

	auto descCntIndent = indent + "\t";
	printDescCnt(UNIFORM_BUFFER, "          ", uniformBuffer);
	printDescCnt(STORAGE_BUFFER, "          ", storageBuffer);
	printDescCnt(UNIFORM_BUFFER_DYNAMIC, "  ", uniformBufferDynamic);
	printDescCnt(STORAGE_BUFFER_DYNAMIC, "  ", storageBufferDynamic);
	printDescCnt(INLINE_UNIFORM_BLOCK_EXT, "", inlineUniformBlock);
	printDescCnt(SAMPLED_IMAGE, "           ", sampledImage);
	printDescCnt(STORAGE_IMAGE, "           ", storageImage);
	printDescCnt(INPUT_ATTACHMENT, "        ", inputAttachment);
	printDescCnt(SAMPLER, "                 ", sampler);
	printDescCnt(COMBINED_IMAGE_SAMPLER, "  ", combinedImageSampler);
	printDescCnt(UNIFORM_TEXEL_BUFFER, "    ", uniformTexelBuffer);
	printDescCnt(STORAGE_TEXEL_BUFFER, "    ", storageTexelBuffer);
	return descStr.str();
}

MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device),
	_descriptorSets(pCreateInfo->maxSets, MVKDescriptorSet(this)),
	_descriptorSetAvailablility(pCreateInfo->maxSets, true),
	_mtlBufferAllocator(_device, getMetalFeatures().maxMTLBufferSize, true),
	_uniformBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER)),
	_storageBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER)),
	_uniformBufferDynamicDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC)),
	_storageBufferDynamicDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC)),
	_inlineUniformBlockDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK)),
	_sampledImageDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE)),
	_storageImageDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE)),
	_inputAttachmentDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT)),
	_samplerDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLER)),
	_combinedImageSamplerDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER)),
	_uniformTexelBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER)),
    _storageTexelBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER)),
    _flags(pCreateInfo->flags) {

		initMetalArgumentBuffer(pCreateInfo);
		MVKLogDebugIf(getMVKConfig().debugMode, "Created %s\n", getLogDescription().c_str());
	}

void MVKDescriptorPool::initMetalArgumentBuffer(const VkDescriptorPoolCreateInfo* pCreateInfo) {
	if ( !isUsingMetalArgumentBuffers() ) { return; }

	auto& mtlFeats = getMetalFeatures();
	@autoreleasepool {
		NSUInteger mtlBuffCnt = 0;
		NSUInteger mtlTexCnt = 0;
		NSUInteger mtlSampCnt = 0;

		uint32_t poolCnt = pCreateInfo->poolSizeCount;
		for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
			auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
			switch (poolSize.type) {
				// VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK counts handled separately below
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
					mtlBuffCnt += poolSize.descriptorCount;
					break;

				case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
				case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
				case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
					mtlTexCnt += poolSize.descriptorCount;
					break;

				case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
				case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
					mtlTexCnt += poolSize.descriptorCount;
					if (!getMetalFeatures().nativeTextureAtomics)
						mtlBuffCnt += poolSize.descriptorCount;
					break;

				case VK_DESCRIPTOR_TYPE_SAMPLER:
					mtlSampCnt += poolSize.descriptorCount;
					break;

				case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
					mtlTexCnt += poolSize.descriptorCount;
					mtlSampCnt += poolSize.descriptorCount;
					break;

				default:
					break;
			}
		}

		// VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK counts pulled separately
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_INLINE_UNIFORM_BLOCK_CREATE_INFO: {
					auto* pDescPoolInlineBlockCreateInfo = (VkDescriptorPoolInlineUniformBlockCreateInfo*)next;
					mtlBuffCnt += pDescPoolInlineBlockCreateInfo->maxInlineUniformBlockBindings;
					break;
				}
				default:
					break;
			}
		}

		// To support the SPIR-V OpArrayLength operation, for each descriptor set that 
		// contain buffers, we add an additional buffer at the end to track buffer sizes.
		mtlBuffCnt += std::min<NSUInteger>(mtlBuffCnt, pCreateInfo->maxSets);

		// Each descriptor set uses a separate Metal argument buffer, but all of these
		// descriptor set Metal argument buffers share a single MTLBuffer. This single
		// MTLBuffer needs to be large enough to hold all of the encoded resources for the
		// descriptors, plus additional buffer offset alignment space for each descriptor set.
		NSUInteger metalArgBuffSize = 0;
		if (needsMetalArgumentBufferEncoders()) {
			// If argument buffer encoders are required, depending on the platform, a Metal argument
			// buffer may have a fixed overhead storage, in addition to the storage required to hold
			// the resources. This overhead per descriptor set is conservatively calculated by measuring
			// the size of a Metal argument buffer containing one of each type of resource (S1), and
			// the size of a Metal argument buffer containing two of each type of resource (S2), and
			// then calculating the fixed overhead per argument buffer as (2 * S1 - S2). To this is
			// added the overhead due to the alignment of each descriptor set Metal argument buffer offset.
			NSUInteger overheadPerDescSet = (2 * getMetalArgumentBufferEncodedResourceStorageSize(1, 1, 1) -
											 getMetalArgumentBufferEncodedResourceStorageSize(2, 2, 2) +
											 mtlFeats.mtlBufferAlignment);

			// Measure the size of an argument buffer that would hold all of the encoded resources
			// managed in this pool, then add any overhead for all the descriptor sets.
			metalArgBuffSize = getMetalArgumentBufferEncodedResourceStorageSize(mtlBuffCnt, mtlTexCnt, mtlSampCnt);
			metalArgBuffSize += (overheadPerDescSet * (pCreateInfo->maxSets - 1));	// metalArgBuffSize already includes overhead for one descriptor set
		} else {
			// For Metal 3, encoders are not required, and each arg buffer entry fits into 64 bits.
			metalArgBuffSize = (mtlBuffCnt + mtlTexCnt + mtlSampCnt) * kMVKMetal3ArgBuffSlotSizeInBytes;
			metalArgBuffSize += (mtlFeats.mtlBufferAlignment * pCreateInfo->maxSets);
		}

		if (metalArgBuffSize) {
			NSUInteger maxMTLBuffSize = mtlFeats.maxMTLBufferSize;
			if (metalArgBuffSize > maxMTLBuffSize) {
				setConfigurationResult(reportError(VK_ERROR_FRAGMENTATION, "vkCreateDescriptorPool(): The requested descriptor storage of %d MB is larger than the maximum descriptor storage of %d MB per VkDescriptorPool.", (uint32_t)(metalArgBuffSize / MEBI), (uint32_t)(maxMTLBuffSize / MEBI)));
				metalArgBuffSize = maxMTLBuffSize;
			}
			_metalArgumentBuffer = [getMTLDevice() newBufferWithLength: metalArgBuffSize options: MTLResourceStorageModeShared];	// retained
			setMetalObjectLabel(_metalArgumentBuffer, @"Descriptor set argument buffer");
			_freeArgBuffSpace = metalArgBuffSize;
		}
	}
}

// Returns the size of a Metal argument buffer containing the number of various types
// of encoded resources. This is only required if argument buffers are required.
// Make sure any call to this function is wrapped in @autoreleasepool.
NSUInteger MVKDescriptorPool::getMetalArgumentBufferEncodedResourceStorageSize(NSUInteger bufferCount,
																			   NSUInteger textureCount,
																			   NSUInteger samplerCount) {
	NSMutableArray<MTLArgumentDescriptor*>* args = [NSMutableArray arrayWithCapacity: 3];

	NSUInteger argIdx = 0;
	[args addObject: getMTLArgumentDescriptor(MTLDataTypePointer, argIdx, bufferCount)];
	argIdx += bufferCount;
	[args addObject: getMTLArgumentDescriptor(MTLDataTypeTexture, argIdx, textureCount)];
	argIdx += textureCount;
	[args addObject: getMTLArgumentDescriptor(MTLDataTypeSampler, argIdx, samplerCount)];
	argIdx += samplerCount;

	id<MTLArgumentEncoder> argEnc = [getMTLDevice() newArgumentEncoderWithArguments: args];
	NSUInteger metalArgBuffSize = argEnc.encodedLength;
	[argEnc release];

	return metalArgBuffSize;
}

// Returns a MTLArgumentDescriptor of a particular type.
// To be conservative, use some worse-case values, in case content makes a difference in argument size.
MTLArgumentDescriptor* MVKDescriptorPool::getMTLArgumentDescriptor(MTLDataType resourceType, NSUInteger argIndex, NSUInteger count) {
	auto* argDesc = [MTLArgumentDescriptor argumentDescriptor];
	argDesc.dataType = resourceType;
	argDesc.access = MTLArgumentAccessReadWrite;
	argDesc.index = argIndex;
	argDesc.arrayLength = count;
	argDesc.textureType = MTLTextureTypeCubeArray;
	return argDesc;
}

MVKDescriptorPool::~MVKDescriptorPool() {
	reset(0);
	[_metalArgumentBuffer release];
	_metalArgumentBuffer = nil;
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


#pragma mark -
#pragma mark Support functions

// Updates the resource bindings in the descriptor sets inditified in the specified content.
void mvkUpdateDescriptorSets(uint32_t writeCount,
							 const VkWriteDescriptorSet* pDescriptorWrites,
							 uint32_t copyCount,
							 const VkCopyDescriptorSet* pDescriptorCopies) {

	// Perform the write updates
	for (uint32_t i = 0; i < writeCount; i++) {
		const VkWriteDescriptorSet* pDescWrite = &pDescriptorWrites[i];
		size_t stride;
		MVKDescriptorSet* dstSet = (MVKDescriptorSet*)pDescWrite->dstSet;

		if( !dstSet ) { continue; }		// Nulls are permitted

		const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock = nullptr;
		for (const auto* next = (VkBaseInStructure*)pDescWrite->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
					break;
				}
				default:
					break;
			}
		}

		const void* pData = getWriteParameters(pDescWrite->descriptorType, pDescWrite->pImageInfo,
											   pDescWrite->pBufferInfo, pDescWrite->pTexelBufferView,
											   pInlineUniformBlock, stride);
		dstSet->write(pDescWrite, stride, pData);
	}

	// Perform the copy updates by reading bindings from one set and writing to other set.
	for (uint32_t i = 0; i < copyCount; i++) {
		const VkCopyDescriptorSet* pDescCopy = &pDescriptorCopies[i];

		uint32_t descCnt = pDescCopy->descriptorCount;
		VkDescriptorImageInfo imgInfos[descCnt];
		VkDescriptorBufferInfo buffInfos[descCnt];
		VkBufferView texelBuffInfos[descCnt];

		// For inline block create a temp buffer of descCnt bytes to hold data during copy.
		uint8_t dstBuffer[descCnt];
		VkWriteDescriptorSetInlineUniformBlock inlineUniformBlock;
		inlineUniformBlock.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK;
		inlineUniformBlock.pNext = nullptr;
		inlineUniformBlock.pData = dstBuffer;
		inlineUniformBlock.dataSize = descCnt;

		MVKDescriptorSet* srcSet = (MVKDescriptorSet*)pDescCopy->srcSet;
		MVKDescriptorSet* dstSet = (MVKDescriptorSet*)pDescCopy->dstSet;
		if( !srcSet || !dstSet ) { continue; }		// Nulls are permitted

		srcSet->read(pDescCopy, imgInfos, buffInfos, texelBuffInfos, &inlineUniformBlock);
		VkDescriptorType descType = dstSet->getDescriptorType(pDescCopy->dstBinding);
		size_t stride;
		const void* pData = getWriteParameters(descType, imgInfos, buffInfos, texelBuffInfos, &inlineUniformBlock, stride);
		dstSet->write(pDescCopy, stride, pData);
	}
}

// Updates the resource bindings in the given descriptor set from the specified template.
void mvkUpdateDescriptorSetWithTemplate(VkDescriptorSet descriptorSet,
										VkDescriptorUpdateTemplate updateTemplate,
										const void* pData) {

	MVKDescriptorSet* dstSet = (MVKDescriptorSet*)descriptorSet;
	MVKDescriptorUpdateTemplate* pTemplate = (MVKDescriptorUpdateTemplate*)updateTemplate;

	if (pTemplate->getType() != VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET)
		return;

	// Perform the updates
	for (uint32_t i = 0; i < pTemplate->getNumberOfEntries(); i++) {
		const VkDescriptorUpdateTemplateEntry* pEntry = pTemplate->getEntry(i);
		const void* pCurData = (const char*)pData + pEntry->offset;

		// For inline block, wrap the raw data in in inline update struct.
		VkWriteDescriptorSetInlineUniformBlock inlineUniformBlock;
		if (pEntry->descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
			inlineUniformBlock.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK;
			inlineUniformBlock.pNext = nullptr;
			inlineUniformBlock.pData = pCurData;
			inlineUniformBlock.dataSize = pEntry->descriptorCount;
			pCurData = &inlineUniformBlock;
		}
		dstSet->write(pEntry, pEntry->stride, pCurData);
	}
}
