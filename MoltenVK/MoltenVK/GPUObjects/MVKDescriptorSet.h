/*
 * MVKDescriptorSet.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKSmallVector.h"
#include "MVKBitArray.h"
#include "MVKInlineArray.h"
#include <unordered_set>
#include <unordered_map>
#include <vector>

class MVKDescriptorPool;
class MVKPipelineLayout;
class MVKCommandEncoder;
class MVKResourcesCommandEncoderState;

#pragma mark MVKShaderStageResourceBinding

/** Indicates the Metal resource indexes used by a single shader stage in a descriptor. */
struct MVKShaderStageResourceBinding {
	uint32_t bufferIndex = 0;
	uint32_t textureIndex = 0;
	uint32_t samplerIndex = 0;
	uint32_t dynamicOffsetBufferIndex = 0;

	MVKShaderStageResourceBinding operator+(const MVKShaderStageResourceBinding& rhs) const { auto tmp = *this; tmp += rhs; return tmp; }
	MVKShaderStageResourceBinding& operator+=(const MVKShaderStageResourceBinding& rhs) {
		bufferIndex += rhs.bufferIndex;
		textureIndex += rhs.textureIndex;
		samplerIndex += rhs.samplerIndex;
		dynamicOffsetBufferIndex += rhs.dynamicOffsetBufferIndex;
		return *this;
	}
	void clearArgumentBufferResources() {
		bufferIndex = 0;
		textureIndex = 0;
		samplerIndex = 0;
	}
};

#pragma mark MVKShaderResourceBinding

/** Indicates the Metal resource indexes used by each shader stage in a descriptor. */
struct MVKShaderResourceBinding {
	MVKShaderStageResourceBinding stages[kMVKShaderStageCount];

	MVKShaderResourceBinding operator+(const MVKShaderResourceBinding& rhs) const { auto tmp = *this; tmp += rhs; return tmp; }
	MVKShaderResourceBinding& operator+=(const MVKShaderResourceBinding& rhs) {
		for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
			this->stages[i] += rhs.stages[i];
		}
		return *this;
	}

	void clearArgumentBufferResources() {
		for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
			stages[i].clearArgumentBufferResources();
		}
	}

	void addArgumentBuffers(uint32_t count) {
		for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
			stages[i].bufferIndex += count;
		}
	}
};

#pragma mark - Descriptor Layout

/** The way argument buffers are encoded */
enum class MVKArgumentBufferMode : uint8_t {
	Off,        /**< Direct binding only. */
	ArgEncoder, /**< Argument buffers are encoded by an argument encoder. */
	Metal3,     /**< Argument buffers are written directly, textures and samplers are 64-bit IDs, and buffers are 64-bit pointers (can add offset directly to pointer). */
};

/** Represents the layout of a descriptor in the CPU buffer */
enum class MVKDescriptorCPULayout : uint8_t {
	None,       /**< This descriptor is GPU only. */
	OneID,      /**< One Metal object (e.g. `id<MTLTexture>`, `id<MTLBuffer>`, etc). */
	OneIDMeta,  /**< One Metal object and 8 bytes of metadata, or two Metal objects (for multiplanar images). */
	TwoIDMeta,  /**< Two Metal objects and 8 bytes of metadata, or three Metal objects (for multiplanar images).  The first object is always a texture. */
	OneID2Meta, /**< One Metal object and 16 bytes of metadata (e.g. `id<MTLBuffer>`, offset, size). */
	TwoID2Meta, /**< Two Metal objects and 16 bytes of metadata (e.g. `id<MTLTexture>`, `id<MTLBuffer>`, offset, size).  The first object is always a texture. */
	InlineData, /**< Inline uniform buffer stored inline. */
};

/** Represents the layout of a descriptor in the GPU buffer */
enum class MVKDescriptorGPULayout : uint8_t {
	None,          /**< This descriptor is CPU only. It must be bound with the Metal binding API. */
	Texture,       /**< A single Metal texture descriptor. */
	Sampler,       /**< A single Metal sampler descriptor. */
	Buffer,        /**< A single Metal buffer pointer. */
	BufferAuxSize, /**< A single Metal buffer pointer, plus its size in an auxiliary buffer. */
	InlineData,    /**< An inline uniform buffer stored inline, with 4-byte alignment. */
	TexBufSoA,     /**< A texture pointer and a buffer pointer.  When arrayed, this is an array of textures followed by an array of pointers. */
	TexSampSoA,    /**< A texture pointer and a sampler pointer.  When arrayed, this is an array of textures followed by an array of samplers. */
	Tex2SampSoA,   /**< Two texture pointers and a sampler pointer.  When arrayed, this is 2 arrays of textures followed by an array of samplers. */
	Tex3SampSoA,   /**< Three texture pointers and a sampler pointer.  When arrayed, this is 3 arrays of textures followed by an array of samplers. */
	OutlinedData,  /**< An inline uniform buffer that is being represented as a pointer to a buffer instead, with 16-byte alignment. */
};

/** The number of each resource used by a descriptor. */
struct MVKDescriptorResourceCount {
	uint8_t texture : 2;
	uint8_t buffer : 1;
	uint8_t sampler : 1;
	uint8_t dynamicOffset : 1;

	MVKShaderStageResourceBinding operator*(uint32_t count) const {
		MVKShaderStageResourceBinding res;
		res.textureIndex = texture * count;
		res.bufferIndex = buffer * count;
		res.samplerIndex = sampler * count;
		res.dynamicOffsetBufferIndex = dynamicOffset * count;
		return res;
	}
};

/** Descriptor metadata for images. */
struct MVKDescriptorMetaImage {
	uint32_t size;
	uint32_t swizzle;
	MVKDescriptorMetaImage() = default;
	constexpr MVKDescriptorMetaImage(uint32_t size_, uint32_t swizzle_): size(size_), swizzle(swizzle_) {}
};
static_assert(sizeof(MVKDescriptorMetaImage) == sizeof(uint64_t));

/** Descriptor metadata for texel buffers. */
struct MVKDescriptorMetaTexelBuffer {
	uint32_t size;
	uint32_t pad;
	MVKDescriptorMetaTexelBuffer() = default;
	constexpr MVKDescriptorMetaTexelBuffer(uint32_t size_): size(size_), pad(0) {}
};
static_assert(sizeof(MVKDescriptorMetaTexelBuffer) == sizeof(uint64_t));

/** Descriptor metadata for buffers. */
struct MVKDescriptorMetaBuffer {
	uint32_t size;
	uint32_t pad;
	MVKDescriptorMetaBuffer() = default;
	constexpr MVKDescriptorMetaBuffer(uint32_t size_): size(size_), pad(0) {}
};
static_assert(sizeof(MVKDescriptorMetaBuffer) == sizeof(uint64_t));

/** Descriptor metadata used on the host side. */
union MVKCPUDescriptorMeta {
	uint64_t raw;
	MVKDescriptorMetaImage img;
	MVKDescriptorMetaTexelBuffer texel;
	MVKDescriptorMetaBuffer buffer;
};
/** A CPU descriptor for MVKDescriptorCPULayout::OneIDMeta. */
struct MVKCPUDescriptorOneIDMeta { id a; union { MVKCPUDescriptorMeta meta; id b; }; };
/** A CPU descriptor for MVKDescriptorCPULayout::TwoIDMeta. */
struct MVKCPUDescriptorTwoIDMeta { id a, b; union { MVKCPUDescriptorMeta meta; id c; }; };
/** A CPU descriptor for MVKDescriptorCPULayout::OneID2Meta. */
struct MVKCPUDescriptorOneID2Meta { id a; uint64_t offset; MVKCPUDescriptorMeta meta; };
/** A CPU descriptor for MVKDescriptorCPULayout::TwoID2Meta. */
struct MVKCPUDescriptorTwoID2Meta { id a, b; uint64_t offset; MVKCPUDescriptorMeta meta; };

static constexpr uint32_t descriptorCPUSize(MVKDescriptorCPULayout layout) {
	switch (layout) {
		case MVKDescriptorCPULayout::None:       return 0;
		case MVKDescriptorCPULayout::OneID:      return sizeof(id);
		case MVKDescriptorCPULayout::OneIDMeta:  return sizeof(MVKCPUDescriptorOneIDMeta);
		case MVKDescriptorCPULayout::TwoIDMeta:  return sizeof(MVKCPUDescriptorTwoIDMeta);
		case MVKDescriptorCPULayout::OneID2Meta: return sizeof(MVKCPUDescriptorOneID2Meta);
		case MVKDescriptorCPULayout::TwoID2Meta: return sizeof(MVKCPUDescriptorTwoID2Meta);
		case MVKDescriptorCPULayout::InlineData: return 1;
	}
}

static constexpr uint32_t descriptorTextureCount(MVKDescriptorGPULayout layout) {
	switch (layout) {
		case MVKDescriptorGPULayout::Texture:
		case MVKDescriptorGPULayout::TexBufSoA:
		case MVKDescriptorGPULayout::TexSampSoA:
			return 1;
		case MVKDescriptorGPULayout::Tex2SampSoA:
			return 2;
		case MVKDescriptorGPULayout::Tex3SampSoA:
			return 3;
		default:
			return 0;
	}
}

enum MVKDescriptorBindingFlagBits {
	MVK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT           = VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT,
	MVK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT = VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT,
	MVK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT   = VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT,
	MVK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT             = VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT,
	MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS            = 0x0f,
	/** If set, this binding uses immutable samplers, stored on the descriptor set layout. */
	MVK_DESCRIPTOR_BINDING_USES_IMMUTABLE_SAMPLERS_BIT     = 0x80,
};

/** Metadata on a single descriptor binding in a descriptor set layout. */
struct MVKDescriptorBinding {
	uint32_t binding;                 /**< The Vulkan binding number. */
	VkDescriptorType descriptorType;  /**< The Vulkan descriptor type. */
	uint32_t descriptorCount;         /**< The number of Vulkan descriptors bound. */
	VkShaderStageFlags stageFlags;    /**< Flags from Vulkan indicating the stages that use this descriptor. */
	uint8_t flags;                    /**< MVKDescriptorBindingFlagBits */
	MVKDescriptorCPULayout cpuLayout; /**< The layout in the descriptor set's host-side storage. */
	MVKDescriptorGPULayout gpuLayout; /**< The layout in the descriptor set's device-side storage. */
	MVKDescriptorResourceCount perDescriptorResourceCount; /**< The number of resources in each descriptor. */
	uint32_t cpuOffset;               /**< The byte offset of the first descriptor of this binding in the descriptor set's CPU storage. */
	union {
		uint32_t gpuOffset; /**< The byte offset of the first descriptor of this binding in the descriptor set's GPU storage, if using direct descriptor writes. */
		uint32_t argBufID;  /**< The argument buffer of the first descriptor of this binding in the descriptor set's GPU storage, if using argument encoders. */
	};
	union {
		uint32_t auxIndex;        /**< The index into the descriptor set's metadata for auxiliary buffers (used by BufferAuxSize and OutlinedData). */
		uint32_t immSamplerIndex; /**< The index into the descriptor set layout's immutable sampler list. */
	};

	void populate(const VkDescriptorSetLayoutBinding& vk);

	/** Returns the number of descriptors in this binding. */
	uint32_t getDescriptorCount(uint32_t variableCount) const {
		if (descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK)
			return 1;
		if (mvkIsAnyFlagEnabled(flags, MVK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT))
			return variableCount;
		return descriptorCount;
	}

	/** Returns the total number of resource bindings used by this descriptor, assuming any variable descriptor counts are set to their maximum value. */
	MVKShaderStageResourceBinding totalResourceCount() const {
		return perDescriptorResourceCount * getDescriptorCount(descriptorCount);
	}

	/** Returns the total number of resource bindings used by this descriptor, with the given variable descriptor count if enabled. */
	MVKShaderStageResourceBinding totalResourceCount(uint32_t variableCount) const {
		return perDescriptorResourceCount * getDescriptorCount(variableCount);
	}

	bool hasImmutableSamplers() const { return mvkIsAnyFlagEnabled(flags, MVK_DESCRIPTOR_BINDING_USES_IMMUTABLE_SAMPLERS_BIT); }
	bool isVariable() const { return mvkIsAnyFlagEnabled(flags, MVK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT); }
};

#pragma mark - MVKDescriptorSetLayout

/** Holds and manages the lifecycle of a MTLArgumentEncoder. */
struct MVKMTLArgumentEncoder {
	std::mutex _lock;

	id<MTLArgumentEncoder> getEncoder() { return _encoder.load(std::memory_order_relaxed); }
	NSUInteger getEncodedLength() const { return _encodedLength; }

	~MVKMTLArgumentEncoder() {
		[getEncoder() release];
	}

private:
	friend class MVKDescriptorSetLayout;
	void init(id<MTLArgumentEncoder> encoder, std::memory_order order) {
		_encodedLength = [encoder encodedLength];
		_encoder.store(encoder, order);
	}

	std::atomic<id<MTLArgumentEncoder>> _encoder = nil;
	NSUInteger _encodedLength = 0;
};

/** Tracks a separate argument encoder for each variable descriptor count */
class MVKMTLArgumentEncoderVariable {
	std::mutex _lock;
	std::unordered_map<uint32_t, MVKMTLArgumentEncoder> _encoders;
public:
	MVKMTLArgumentEncoder& operator[](uint32_t variableCount) {
		std::lock_guard<std::mutex> guard(_lock);
		return _encoders[variableCount];
	}
};

/** Represents a Vulkan descriptor set layout. */
class MVKDescriptorSetLayout : public MVKVulkanAPIDeviceObject, public MVKInlineConstructible {
public:
	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT_EXT; }

	/** Creates a new descriptor set layout. */
	static MVKDescriptorSetLayout* Create(MVKDevice* device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo);

	/** Returns whether this layout was created with `VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR`. */
	bool isPushDescriptorSetLayout() const { return _flags.has(Flag::IsPushDescriptorSetLayout); }

	/** Returns the argument encoder.  Returns null if you should be using direct writes. */
	MVKMTLArgumentEncoder* mtlArgumentEncoder() { return _mtlArgumentEncoder.get(); }

	/** Returns the list of bindings, ordered by binding number. */
	MVKArrayRef<const MVKDescriptorBinding> bindings() const { return _bindings; }
	/** Returns the list of immutable samplers. */
	MVKArrayRef<MVKSampler*const> immutableSamplers() const { return _immutableSamplers; }
	/** Returns the total resource counts for the entire set. */
	const MVKShaderResourceBinding& totalResourceCount() const { return _totalResourceCount; }

	/** Returns the buffer of precalculated aux offsets. */
	const uint32_t* auxOffsets() const { return _auxOffsets; }
	/** Returns the number of aux offsets.  Note that for variable descriptor sets, `auxOffsets` will be null even though this is nonzero. */
	uint32_t numAuxOffsets() const { return _numAuxOffsets; }
	/** Returns the number of uint32s needed in the buffer size aux buffer. */
	uint32_t sizeBufSize(uint32_t numVariable) const { return _sizeBufSize + (_flags.has(Flag::IsSizeBufVariable) ? numVariable : 0); }
	/** Returns whether a size buffer is needed. */
	bool needsSizeBuf() const { return _sizeBufSize || _flags.has(Flag::IsSizeBufVariable); }

	/** Returns the required CPU buffer alignment. */
	uint32_t cpuAlignment() const { return _cpuAlignment; }
	/** Returns the required GPU buffer alignment. */
	uint32_t gpuAlignment() const { return _gpuAlignment; }
	/** Returns the required CPU buffer size. */
	uint32_t cpuSize(uint32_t numVariable = 0) const { return _cpuSize + numVariable * _cpuVariableElementSize; }
	/** Returns the required GPU buffer size.  For variable descriptor sets with argument encoders, returns zero; you must get the actual value from the encoder in that case. */
	uint32_t gpuSize(uint32_t numVariable = 0) const { return _gpuSize + numVariable * _gpuVariableElementSize; }
	/** Returns the offset of the aux buffers in the GPU buffer.  For variable descriptor sets with argument encoders, returns zero; you must get the actual value from the encoder in that case. */
	uint32_t gpuAuxBase(uint32_t numVariable = 0) const { return _gpuAuxBase + (isMainGPUBufferVariable() ? numVariable * _gpuVariableElementSize : 0); }
	uint32_t dynamicOffsetCount(uint32_t numVariable) const { return _dynamicOffsetCount + (_flags.has(Flag::IsDynamicOffsetCountVariable) ? numVariable : 0); }
	/** Returns the argument buffer mode. */
	MVKArgumentBufferMode argBufMode() const { return _argBufMode; }
	/** Returns whether the size of the main GPU argument buffer (not including aux buffers) is affected by variable descriptor size. */
	bool isMainGPUBufferVariable() const { return _flags.has(Flag::IsVariable); }
	/** Returns whether the size of the CPU buffer is affected by variable descriptor size. */
	bool isCPUAllocationVariable() const { return _cpuVariableElementSize != 0; }
	/** Returns whether the size of the GPU buffer is affected by variable descriptor size. */
	bool isGPUAllocationVariable() const { return _gpuVariableElementSize != 0 || isMainGPUBufferVariable(); }
	/** Returns a pointer to the immutable sampler for the given descriptor.  Subsequent array indices may be accessed by adding to the pointer, including samplers from subsequent bindings. */
	MVKSampler*const* getImmutableSampler(const MVKDescriptorBinding& desc, uint32_t arrayIndex = 0) const {
		return desc.hasImmutableSamplers() ? &_immutableSamplers[desc.immSamplerIndex + arrayIndex] : nullptr;
	}

	/**
	 * Returns the index of the info for the given Vulkan binding.
	 *
	 * The info is part of an array ordered by binding number, so you can increment the index to go to the next binding in order.
	 */
	uint32_t getBindingIndex(uint32_t binding) const;

	/**
	 * Returns a pointer to the info for the given Vulkan binding.
	 *
	 * The info is part of an array ordered by binding number, so you can increment the pointer to go to the next binding in order.
	 */
	const MVKDescriptorBinding* getBinding(uint32_t binding) const { return &_bindings[getBindingIndex(binding)]; }

	/** Returns the argument encoder for the given variable descriptor count. */
	MVKMTLArgumentEncoder& getArgumentEncoder(uint32_t variableCount = 0) const {
		assert(_argBufMode == MVKArgumentBufferMode::ArgEncoder);
		if (isMainGPUBufferVariable())
			return getVariableArgumentEncoder(variableCount);
		else
			return getNonVariableArgumentEncoder();
	}

	/** Returns the argument encoder for the given variable descriptor count.  Only valid if `isMainGPUBufferVariable`. */
	MVKMTLArgumentEncoder& getVariableArgumentEncoder(uint32_t variableCount) const;
	/** Returns the argument encoder.  Only valid if `!isMainGPUBufferVariable`. */
	MVKMTLArgumentEncoder& getNonVariableArgumentEncoder() const {
		assert(_argBufMode == MVKArgumentBufferMode::ArgEncoder);
		assert(!isMainGPUBufferVariable());
		return *_mtlArgumentEncoder;
	}

private:
	enum class Flag {
		IsPushDescriptorSetLayout,    /**< Whether this was created with `VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR`. */
		IsVariable,                   /**< Whether the descriptor set is variable length. */
		IsSizeBufVariable,            /**< Whether the size buf is variable length. */
		IsDynamicOffsetCountVariable, /**< Whether the dynamic offset buffer is variable length. */
		Count
	};
	/** A list of bindings sorted by binding number. */
	MVKInlineArray<MVKDescriptorBinding> _bindings;
	/** A list of immutable samplers. */
	MVKInlineArray<MVKSampler*> _immutableSamplers;
	/** Argument encoder for encoding argument buffers. */
	MVKInlinePointer<MVKMTLArgumentEncoder> _mtlArgumentEncoder;
	/** Argument encoders for encoding variable argument buffers. */
	MVKInlinePointer<MVKMTLArgumentEncoderVariable> _mtlArgumentEncoderVariable;
	/** Offsets into aux buffers, available on non-variable descriptor sets only.  Variable descriptor sets need a different one per variable descriptor count. */
	uint32_t* _auxOffsets;
	/** The number of aux offsets needed. */
	uint32_t _numAuxOffsets = 0;
	/** The number of bindings where bindingID == offset in `_bindings` (optimization for avoiding binary search if possible). */
	uint32_t _numLinearBindings = 0;
	/** The maximum index of a buffer that needs a buffer size entry. */
	uint32_t _sizeBufSize = 0;
	/** The required size of cpu buffer minus any variable descriptors. */
	uint32_t _cpuSize = 0;
	/** If using variable descriptors, the size of each variable element in the cpu buffer. */
	uint32_t _cpuVariableElementSize = 0;
	/** The required size of gpu buffer minus any variable descriptors. */
	uint32_t _gpuSize = 0;
	/** If using variable descriptors, the size of each variable element in the gpu buffer. */
	uint32_t _gpuVariableElementSize = 0;
	/** The total number of buffers using dynamic offsets, minus any variable descriptors. */
	uint32_t _dynamicOffsetCount = 0;
	/** The length of the argument buffer portion of the GPU buffer only. */
	uint32_t _gpuAuxBase = 0;
	/** The required alignment of the CPU buffer. */
	uint32_t _cpuAlignment = 1;
	/** The required alignment of the GPU buffer. */
	uint32_t _gpuAlignment = 1;
	/** The total number of resources used by this descriptor set, including the max amount of variable descriptors. */
	MVKShaderResourceBinding _totalResourceCount = {};
	/** The argument buffer mode for this layout. */
	MVKArgumentBufferMode _argBufMode = MVKArgumentBufferMode::Off;
	/** Boolean flags. */
	MVKFlagList<Flag> _flags;
	friend class MVKInlineObjectConstructor<MVKDescriptorSetLayout>;
	MVKDescriptorSetLayout(MVKDevice* device);
	void propagateDebugName() override {}
};

#pragma mark - MVKDescriptorSet

/** Represents a Vulkan descriptor set. */
struct MVKDescriptorSet {
	/** The layout this descriptor set uses. */
	const MVKDescriptorSetLayout* layout;
	/** The argument encoder, if needed. */
	MVKMTLArgumentEncoder* argEnc;
	/** The host-side descriptor buffer. */
	char* cpuBuffer;
	/** Host pointer to the device-side argument buffer. */
	char* gpuBuffer;
	/** An array of offsets in the auxiliary buffer for buffers that need it. */
	const uint32_t* auxIndices;
	/** The Metal device-side argument buffer object. */
	id<MTLBuffer> gpuBufferObject;
	/** The offset into the GPU buffer object used by this descriptor set. */
	uint32_t gpuBufferOffset;
	/** The size of the GPU buffer. */
	uint32_t gpuBufferSize;
	/** The size of the CPU buffer. */
	uint32_t cpuBufferSize;
	/** The number of variable descriptors. */
	uint32_t variableDescriptorCount;

	void setGPUBuffer(id<MTLBuffer> buffer, void* contents, size_t offset, size_t size) {
		gpuBufferObject = buffer;
		gpuBufferOffset = static_cast<uint32_t>(offset);
		gpuBuffer = &static_cast<char*>(contents)[offset];
		gpuBufferSize = static_cast<uint32_t>(size);
	}

	void setCPUBuffer(void* buffer, size_t size) {
		cpuBuffer = static_cast<char*>(buffer);
		cpuBufferSize = static_cast<uint32_t>(size);
	}
};

#pragma mark - MVKDescriptorPool

union MVKDescriptorSetListItem;

struct MVKFreedDescriptorSet {
	/** The next descriptor set in the linked list of freed descriptor sets. */
	MVKDescriptorSetListItem* next;
};

union MVKDescriptorSetListItem {
	MVKDescriptorSet allocated;
	MVKFreedDescriptorSet freed;
};

/**
 * The free list used internally by MVKDescriptorPool.
 * Kind of terrible, never resizes allocations.  Once an allocation has been made of a specific size, it's forever that size.
 * Hope: Games will allocate the same set of descriptor sets (and therefore the same sizes) over and over again, so this will work out fine.
 */
class MVKDescriptorPoolFreeList {
	struct Entry {
		size_t size;
		std::vector<size_t> items;
		Entry(size_t size_): size(size_) {}
	};
	std::vector<Entry> entries;
	size_t _freeSize;

public:
	void add(size_t item, size_t size);
	std::optional<std::pair<size_t, size_t>> get(size_t minSize, size_t maxSize);
	void reset();
	size_t freeSize() const { return _freeSize; }

private:
	std::vector<Entry>::iterator findEntry(size_t size);
};

/** Represents a Vulkan descriptor pool. */
class MVKDescriptorPool final : public MVKVulkanAPIDeviceObject, public MVKInlineConstructible {
public:
	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_POOL; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_POOL_EXT; }

	/** Creates a new descriptor pool instance. */
	static MVKDescriptorPool* Create(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo);

	/** Allocates descriptor sets. */
	VkResult allocateDescriptorSets(const VkDescriptorSetAllocateInfo* pAllocateInfo,
	                                VkDescriptorSet* pDescriptorSets);

	/** Frees up the specified descriptor sets. */
	VkResult freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets);

	/** Destroys all currently allocated descriptor sets. */
	VkResult reset(VkDescriptorPoolResetFlags flags);

	/** Returns whether freeing descriptor sets is allowed. */
	bool freeAllowed() const { return _freeAllowed; }

protected:
	MVKDescriptorSet* allocateDescriptorSet();
	VkResult initDescriptorSet(MVKDescriptorSetLayout* mvkDSL, uint32_t variableDescriptorCount, MVKDescriptorSet* set);

	~MVKDescriptorPool() override;

	void propagateDebugName() override {}

private:
	uint32_t _gpuBufferAlignment = 0;
	uint32_t _cpuBufferAlignment = 0;
	uint32_t _numAllocatedDescriptorSets = 0;
	uint32_t _cpuBufferUsed = 0;
	uint32_t _gpuBufferUsed = 0;
	bool _freeAllowed;
	MVKInlineArray<MVKDescriptorSetListItem> _descriptorSets;
	MVKInlineArray<char> _cpuBuffer;
	MVKArrayRef<char> _gpuBuffer;
	id<MTLBuffer> _gpuBufferObject = nullptr;
	uint64_t _gpuBufferGPUAddress = 0;
	MVKDescriptorSetListItem* _firstFreeDescriptorSet = nullptr;
	MVKDescriptorPoolFreeList _cpuBufferFreeList;
	MVKDescriptorPoolFreeList _gpuBufferFreeList;

	friend class MVKInlineObjectConstructor<MVKDescriptorPool>;
	MVKDescriptorPool(MVKDevice* device);
};


#pragma mark -
#pragma mark MVKDescriptorUpdateTemplate

/** Represents a Vulkan descriptor update template. */
class MVKDescriptorUpdateTemplate : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_UPDATE_TEMPLATE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_UPDATE_TEMPLATE_EXT; }

	/** Get the nth update template entry. */
	const VkDescriptorUpdateTemplateEntry* getEntry(uint32_t n) const;

	/** Get the total number of entries. */
	uint32_t getNumberOfEntries() const;

	/** Get the total number of bytes of data requried by this template. */
	size_t getSize() const { return _size; }

	/** Get the type of this template. */
	VkDescriptorUpdateTemplateType getType() const;

	/** Get the bind point of this template */
	VkPipelineBindPoint getBindPoint() const { return _pipelineBindPoint; }

	/** Constructs an instance for the specified device. */
	MVKDescriptorUpdateTemplate(MVKDevice* device, const VkDescriptorUpdateTemplateCreateInfo* pCreateInfo);

	/** Destructor. */
	~MVKDescriptorUpdateTemplate() override = default;

protected:
	void propagateDebugName() override {}

	MVKSmallVector<VkDescriptorUpdateTemplateEntry, 1> _entries;
	size_t _size = 0;
	VkPipelineBindPoint _pipelineBindPoint;
	VkDescriptorUpdateTemplateType _type;
};

#pragma mark -
#pragma mark Support functions

/** Updates the resource bindings in the descriptor sets inditified in the specified content. */
void mvkUpdateDescriptorSets(uint32_t writeCount,
							const VkWriteDescriptorSet* pDescriptorWrites,
							uint32_t copyCount,
							const VkCopyDescriptorSet* pDescriptorCopies);

/** Updates the resource bindings in the given descriptor set from the specified template. */
void mvkUpdateDescriptorSetWithTemplate(VkDescriptorSet descriptorSet,
										VkDescriptorUpdateTemplate updateTemplate,
										const void* pData);

/** Updates the resource bindings in the given descriptor set with the given writes, ignoring their dstSet parameter and using the given dst cpu buffer instead. */
void mvkPushDescriptorSet(void* dst, MVKDescriptorSetLayout* layout,
                          uint32_t writeCount, const VkWriteDescriptorSet* pDescriptorWrites);

/** Updates the resource bindings in the given descriptor set with the given template. */
void mvkPushDescriptorSetTemplate(void* dst, MVKDescriptorSetLayout* layout,
                                  MVKDescriptorUpdateTemplate* updateTemplate, const void* pData);
