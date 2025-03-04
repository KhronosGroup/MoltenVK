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

#include "MVKDescriptor.h"
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
struct MVKBindingList;

#pragma mark - Descriptor Layout

/** The way argument buffers are encoded */
enum class MVKArgumentBufferMode : uint8_t {
	Off,        /**< Direct binding only */
	ArgEncoder, /**< Argument buffers encoded by an argument encoder */
	Metal3,     /**< Argument buffers written directly, textures and samplers are 64-bit IDs, and buffers are 64-bit pointers (can add offset directly to pointer) */
};

/** Represents the layout of a descriptor in the CPU buffer */
enum class MVKDescriptorCPULayout : uint8_t {
	None,       /**< This descriptor is GPU only */
	OneID,      /**< One Metal object (e.g. `id<MTLTexture>`, `id<MTLBuffer>`, etc) */
	OneIDMeta,  /**< One Metal object and 8 bytes of metadata, or two Metal objects (for multiplanar images) */
	TwoIDMeta,  /**< Two Metal objects and 8 bytes of metadata, or three Metal objects (for multiplanar images).  The first object is always a texture. */
	OneID2Meta, /**< One Metal object and 16 bytes of metadata (e.g. `id<MTLBuffer>`, offset, size) */
	TwoID2Meta, /**< Two Metal objects and 16 bytes of metadata (e.g. `id<MTLTexture>`, `id<MTLBuffer>`, offset, size).  The first object is always a texture. */
	InlineData, /**< Inline uniform buffer stored inline */
};

/** Represents the layout of a descriptor in the GPU buffer */
enum class MVKDescriptorGPULayout : uint8_t {
	None,          /**< This descriptor is CPU only (must be bound with the Metal binding API) */
	Texture,       /**< Single Metal texture descriptor */
	Sampler,       /**< Single Metal sampler descriptor */
	Buffer,        /**< Single Metal buffer pointer */
	BufferAuxSize, /**< Single Metal buffer pointer, plus size in an auxiliary buffer */
	InlineData,    /**< Inline uniform buffer stored inline (with 4-byte alignment) */
	TexBufSoA,     /**< A texture pointer and a buffer pointer.  When arrayed, this is an array of textures followed by an array of pointers. */
	TexSampSoA,    /**< A texture pointer and a sampler pointer.  When arrayed, this is an array of textures followed by an array of samplers. */
	Tex2SampSoA,   /**< 2 texture pointers and a sampler pointer.  When arrayed, this is 2 arrays of textures followed by an array of samplers. */
	Tex3SampSoA,   /**< 3 texture pointers and a sampler pointer.  When arrayed, this is 3 arrays of textures followed by an array of samplers. */
	OutlinedData,  /**< Inline uniform buffer that is being represented as a pointer to a buffer instead (with 16-byte alignment) */
};

/** The number of each resource used by a descriptor */
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

/** Descriptor metadata for images */
struct MVKDescriptorMetaImage {
	uint32_t size;
	uint32_t swizzle;
	MVKDescriptorMetaImage() = default;
	constexpr MVKDescriptorMetaImage(uint32_t size_, uint32_t swizzle_): size(size_), swizzle(swizzle_) {}
};
static_assert(sizeof(MVKDescriptorMetaImage) == sizeof(uint64_t));

/** Descriptor metadata for texel buffers */
struct MVKDescriptorMetaTexelBuffer {
	uint32_t size;
	uint32_t pad;
	MVKDescriptorMetaTexelBuffer() = default;
	constexpr MVKDescriptorMetaTexelBuffer(uint32_t size_): size(size_), pad(0) {}
};
static_assert(sizeof(MVKDescriptorMetaTexelBuffer) == sizeof(uint64_t));

/** Descriptor metadata for buffers */
struct MVKDescriptorMetaBuffer {
	uint32_t size;
	uint32_t pad;
	MVKDescriptorMetaBuffer() = default;
	constexpr MVKDescriptorMetaBuffer(uint32_t size_): size(size_), pad(0) {}
};
static_assert(sizeof(MVKDescriptorMetaBuffer) == sizeof(uint64_t));

/** CPU descriptor metadata */
union MVKCPUDescriptorMeta {
	uint64_t raw;
	MVKDescriptorMetaImage img;
	MVKDescriptorMetaTexelBuffer texel;
	MVKDescriptorMetaBuffer buffer;
};
/** CPU descriptor for MVKDescriptorCPULayout::OneIDMeta */
struct MVKCPUDescriptorOneIDMeta { id a; union { MVKCPUDescriptorMeta meta; id b; }; };
/** CPU descriptor for MVKDescriptorCPULayout::TwoIDMeta */
struct MVKCPUDescriptorTwoIDMeta { id a, b; union { MVKCPUDescriptorMeta meta; id c; }; };
/** CPU descriptor for MVKDescriptorCPULayout::OneID2Meta */
struct MVKCPUDescriptorOneID2Meta { id a; uint64_t offset; MVKCPUDescriptorMeta meta; };
/** CPU descriptor for MVKDescriptorCPULayout::TwoID2Meta */
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
	/** If true, this binding uses immutable samplers (stored on the descriptor set layout) */
	MVK_DESCRIPTOR_BINDING_USES_IMMUTABLE_SAMPLERS_BIT     = 0x80,
};

/** Metadata on a single descriptor binding in a descriptor set layout */
struct MVKDescriptorBinding {
	uint32_t binding;                 /**< Vulkan binding */
	VkDescriptorType descriptorType;  /**< Vulkan type */
	uint32_t descriptorCount;         /**< Vulkan descriptor count */
	VkShaderStageFlags stageFlags;    /**< Vulkan stage flags */
	uint8_t flags;                    /**< MVKDescriptorBindingFlagBits */
	MVKDescriptorCPULayout cpuLayout; /**< The layout in the descriptor set's CPU storage */
	MVKDescriptorGPULayout gpuLayout; /**< The layout in the descriptor set's GPU storage */
	MVKDescriptorResourceCount perDescriptorResourceCount; /**< Resource counts per descriptor */
	uint32_t cpuOffset;               /**< The byte offset of the first descriptor of this binding in the descriptor set's CPU storage */
	union {
		uint32_t gpuOffset; /**< The byte offset of the first descriptor of this binding in the descriptor set's GPU storage, if using direct descriptor writes */
		uint32_t argBufID;  /**< The argument buffer of the first descriptor of this binding in the descriptor set's GPU storage, if using argument encoders */
	};
	union {
		uint32_t auxIndex;        /**< The index into the descriptor set's metadata for auxiliary buffers (used by BufferAuxSize and OutlinedData) */
		uint32_t immSamplerIndex; /**< The index into the descriptor set layout's immutable sampler list */
	};

	void populate(const VkDescriptorSetLayoutBinding& vk);

	/** Get the number of descriptors in this binding */
	uint32_t getDescriptorCount(uint32_t variableCount) const {
		if (descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK)
			return 1;
		if (mvkIsAnyFlagEnabled(flags, MVK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT))
			return variableCount;
		return descriptorCount;
	}

	/** Get the total number of resource bindings used by this descriptor, assuming any variable descriptor counts are set to their maximum value */
	MVKShaderStageResourceBinding totalResourceCount() const {
		return perDescriptorResourceCount * getDescriptorCount(descriptorCount);
	}

	/** Get the total number of resource bindings used by this descriptor, with the given variable descriptor count if enabled */
	MVKShaderStageResourceBinding totalResourceCount(uint32_t variableCount) const {
		return perDescriptorResourceCount * getDescriptorCount(variableCount);
	}

	bool hasImmutableSamplers() const { return mvkIsAnyFlagEnabled(flags, MVK_DESCRIPTOR_BINDING_USES_IMMUTABLE_SAMPLERS_BIT); }
	bool isVariable() const { return mvkIsAnyFlagEnabled(flags, MVK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT); }
};

#pragma mark - MVKDescriptorSetLayoutNew

/** Holds and manages the lifecycle of a MTLArgumentEncoder. */
struct MVKMTLArgumentEncoder {
	std::mutex _lock;

	id<MTLArgumentEncoder> getEncoder() { return _encoder.load(std::memory_order_relaxed); }
	NSUInteger getEncodedLength() const { return _encodedLength; }

	~MVKMTLArgumentEncoder() {
		[_encoder.load(std::memory_order_relaxed) release];
	}

private:
	friend class MVKDescriptorSetLayoutNew;
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
class MVKDescriptorSetLayoutNew : public MVKVulkanAPIDeviceObject, public MVKInlineConstructible {
public:
	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT_EXT; }

	/** Construtor */
	static MVKDescriptorSetLayoutNew* Create(MVKDevice* device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo);

	/** Whether this was created with `VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR` */
	bool isPushDescriptorSetLayout() const { return _flags.has(Flag::IsPushDescriptorSetLayout); }

	/** Get the argument encoder.  Will be null if you should be using direct writes. */
	MVKMTLArgumentEncoder* mtlArgumentEncoder() { return _mtlArgumentEncoder.get(); }

	/** Gets the list of bindings (ordered by binding number). */
	MVKArrayRef<const MVKDescriptorBinding> bindings() const { return _bindings; }
	/** Gets the list of immutable samplers. */
	MVKArrayRef<MVKSampler*const> immutableSamplers() const { return _immutableSamplers; }
	/** Gets the total resource counts for the entire set. */
	const MVKShaderResourceBinding& totalResourceCount() const { return _totalResourceCount; }

	/** Get the buffer of precalculated aux offsets. */
	const uint32_t* auxOffsets() const { return _auxOffsets; }
	/** Gets the number of aux offsets.  Note that for variable descriptor sets, `auxOffsets` will be null even though this is nonzero. */
	uint32_t numAuxOffsets() const { return _numAuxOffsets; }
	/** Gets the number of uint32s needed in the buffer size aux buffer. */
	uint32_t sizeBufSize(uint32_t numVariable) const { return _sizeBufSize + (_flags.has(Flag::IsSizeBufVariable) ? numVariable : 0); }
	/** Checks whether a size buffer is needed. */
	bool needsSizeBuf() const { return _sizeBufSize || _flags.has(Flag::IsSizeBufVariable); }

	/** Gets the required CPU buffer alignment. */
	uint32_t cpuAlignment() const { return _cpuAlignment; }
	/** Gets the required GPU buffer alignment. */
	uint32_t gpuAlignment() const { return _gpuAlignment; }
	/** Gets the required CPU buffer size. */
	uint32_t cpuSize(uint32_t numVariable = 0) const { return _cpuSize + numVariable * _cpuVariableElementSize; }
	/** Gets the required GPU buffer size.  For variable descriptor sets with argument encoders, will return zero (need to get actual value from encoder). */
	uint32_t gpuSize(uint32_t numVariable = 0) const { return _gpuSize + numVariable * _gpuVariableElementSize; }
	/** Gets the offset of the aux buffers in the GPU buffer.  For variable descriptor sets with argument encoders, will return zero (need to get actual value from encoder). */
	uint32_t gpuAuxBase(uint32_t numVariable = 0) const { return _gpuAuxBase + (isMainGPUBufferVariable() ? numVariable * _gpuVariableElementSize : 0); }
	uint32_t dynamicOffsetCount(uint32_t numVariable) const { return _dynamicOffsetCount + (_flags.has(Flag::IsDynamicOffsetCountVariable) ? numVariable : 0); }
	/** Get the argument buffer mode. */
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
	 * Gets the index of the info for the given Vulkan binding.
	 *
	 * The info is part of an array ordered by binding number, so you can increment the index to go to the next binding in order.
	 */
	uint32_t getBindingIndex(uint32_t binding) const;

	/**
	 * Gets the a pointer to the info for the given Vulkan binding.
	 *
	 * The info is part of an array ordered by binding number, so you can increment the pointer to go to the next binding in order.
	 */
	const MVKDescriptorBinding* getBinding(uint32_t binding) const { return &_bindings[getBindingIndex(binding)]; }

	/** Get the argument encoder for the given variable descriptor count. */
	MVKMTLArgumentEncoder& getArgumentEncoder(uint32_t variableCount = 0) const {
		assert(_argBufMode == MVKArgumentBufferMode::ArgEncoder);
		if (isMainGPUBufferVariable())
			return getVariableArgumentEncoder(variableCount);
		else
			return getNonVariableArgumentEncoder();
	}

	/** Get the argument encoder for the given variable descriptor count.  Only valid if `isMainGPUBufferVariable`. */
	MVKMTLArgumentEncoder& getVariableArgumentEncoder(uint32_t variableCount) const;
	/** Get the argument encoder.  Only valid if `!isMainGPUBufferVariable`. */
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
	friend class MVKInlineObjectConstructor<MVKDescriptorSetLayoutNew>;
	MVKDescriptorSetLayoutNew(MVKDevice* device);
	void propagateDebugName() override {}
};

#pragma mark - MVKDescriptorSetNew

/** Represents a Vulkan descriptor set. */
struct MVKDescriptorSetNew {
	/** The layout this descriptor set uses */
	const MVKDescriptorSetLayoutNew* layout;
	/** The argument encoder, if needed */
	MVKMTLArgumentEncoder* argEnc;
	/** CPU descriptor buffer */
	char* cpuBuffer;
	/** GPU descriptor buffer CPU pointer */
	char* gpuBuffer;
	/** Offsets for aux buffer entries */
	const uint32_t* auxIndices;
	/** GPU descriptor buffer Metal object */
	id<MTLBuffer> gpuBufferObject;
	/** The offset into the GPU buffer object used by this descriptor set */
	uint32_t gpuBufferOffset;
	/** The size of the GPU buffer */
	uint32_t gpuBufferSize;
	/** The size of the CPU buffer */
	uint32_t cpuBufferSize;
	/** The number of variable descriptors */
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

#pragma mark - MVKDescriptorPoolNew

union MVKDescriptorSetListItem;

struct MVKFreedDescriptorSet {
	/** The next descriptor set in the linked list of freed descriptor sets */
	MVKDescriptorSetListItem* next;
};

union MVKDescriptorSetListItem {
	MVKDescriptorSetNew allocated;
	MVKFreedDescriptorSet freed;
};

/**
 * Free list used internally by MVKDescriptorPoolNew
 * Kind of terrible, never resizes allocations.  Once an allocation has been made of a specific size, it's forever that size.
 * Hope: Games will allocate the same set of descriptor sets (and therefore the same sizes) over and over again, so this will work out fine
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
class MVKDescriptorPoolNew final : public MVKVulkanAPIDeviceObject, public MVKInlineConstructible {
public:
	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_POOL; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_POOL_EXT; }

	/** Constructor */
	static MVKDescriptorPoolNew* Create(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo);

	/** Allocates descriptor sets. */
	VkResult allocateDescriptorSets(const VkDescriptorSetAllocateInfo* pAllocateInfo,
	                                VkDescriptorSet* pDescriptorSets);

	/** Frees up the specified descriptor sets. */
	VkResult freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets);

	/** Destroys all currently allocated descriptor sets. */
	VkResult reset(VkDescriptorPoolResetFlags flags);

	/** Returns whether freeing descriptor sets is allowed */
	bool freeAllowed() const { return _freeAllowed; }

protected:
	MVKDescriptorSetNew* allocateDescriptorSet();
	VkResult initDescriptorSet(MVKDescriptorSetLayoutNew* mvkDSL, uint32_t variableDescriptorCount, MVKDescriptorSetNew* set);

	~MVKDescriptorPoolNew() override;

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

	friend class MVKInlineObjectConstructor<MVKDescriptorPoolNew>;
	MVKDescriptorPoolNew(MVKDevice* device);
};

#pragma mark -
#pragma mark MVKMetalArgumentBuffer

/**
 * Helper object to handle the placement of resources into a Metal Argument Buffer
 * in a consistent manner, whether or not a MTLArgumentEncoder is required.
 */
typedef struct MVKMetalArgumentBuffer {
	void setBuffer(id<MTLBuffer> mtlBuff, NSUInteger offset, uint32_t index);
	void setTexture(id<MTLTexture> mtlTex, uint32_t index);
	void setSamplerState(id<MTLSamplerState> mtlSamp, uint32_t index);
	id<MTLBuffer> getMetalArgumentBuffer() { return _mtlArgumentBuffer; }
	NSUInteger getMetalArgumentBufferOffset() { return _mtlArgumentBufferOffset; }
	NSUInteger getMetalArgumentBufferEncodedSize() { return _mtlArgumentBufferEncodedSize; }
	void setArgumentBuffer(id<MTLBuffer> mtlArgBuff, NSUInteger mtlArgBuffOfst, NSUInteger mtlArgBuffEncSize, id<MTLArgumentEncoder> mtlArgEnc);
	~MVKMetalArgumentBuffer();
protected:
	void* getArgumentPointer(uint32_t index) const;
	id<MTLArgumentEncoder> _mtlArgumentEncoder = nil;
	id<MTLBuffer> _mtlArgumentBuffer = nil;
	NSUInteger _mtlArgumentBufferOffset = 0;
	NSUInteger _mtlArgumentBufferEncodedSize = 0;
} MVKMetalArgumentBuffer;


#pragma mark -
#pragma mark MVKDescriptorSetLayout

/** Represents a Vulkan descriptor set layout. */
class MVKDescriptorSetLayout : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT_EXT; }

	/** Appends the bindings from the given descriptor set to a list */
	void appendDescriptorSetBindings(MVKBindingList& target,
	                                 MVKSmallVector<uint32_t, 8>& targetDynamicOffsets,
	                                 MVKShaderStage stage,
	                                 uint32_t index,
	                                 MVKDescriptorSet* set,
	                                 const MVKShaderStageResourceBinding& indexOffsets,
	                                 const uint32_t*& dynamicOffsets);

	/** Encodes this descriptor set layout and the specified descriptor updates on the specified command encoder immediately. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   VkPipelineBindPoint pipelineBindPoint,
						   MVKArrayRef<VkWriteDescriptorSet> descriptorWrites,
						   MVKShaderResourceBinding& dslMTLRezIdxOffsets);


	/** Encodes this descriptor set layout and the updates from the given template on the specified command encoder immediately. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   MVKDescriptorUpdateTemplate* descUpdateTemplates,
						   const void* pData,
						   MVKShaderResourceBinding& dslMTLRezIdxOffsets);


	/** Populates the specified shader conversion config, at the specified DSL index. */
	void populateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
                                        MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                        uint32_t descSetIndex);

	/**
	 * Populates the bindings in this descriptor set layout used by the shader.
	 * Returns false if the shader does not use the descriptor set at all.
	 */
	bool populateBindingUse(MVKBitArray& bindingUse,
							mvk::SPIRVToMSLConversionConfiguration& context,
							MVKShaderStage stage,
							uint32_t descSetIndex);

	/** Returns the number of bindings. */
	uint32_t getBindingCount() { return (uint32_t)_bindings.size(); }

	/** Returns the binding at the index in a descriptor set layout. */
	MVKDescriptorSetLayoutBinding* getBindingAt(uint32_t index) { return &_bindings[index]; }

	/** Overridden because descriptor sets may be marked as discrete and not use an argument buffer. */
	bool isUsingMetalArgumentBuffers() const override;

	/** Returns whether descriptor sets from this layout requires an auxilliary buffer-size buffer. */
	bool needsBufferSizeAuxBuffer() { return _maxBufferIndex >= 0; }

	/** Returns a text description of this layout. */
	std::string getLogDescription(std::string indent = "");

	MVKDescriptorSetLayout(MVKDevice* device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo);

protected:

	friend class MVKDescriptorSetLayoutBinding;
	friend class MVKPipelineLayout;
	friend class MVKDescriptorSet;
	friend class MVKDescriptorPool;

	void propagateDebugName() override {}
	uint32_t getDescriptorCount(uint32_t variableDescriptorCount);
	uint32_t getDescriptorIndex(uint32_t binding, uint32_t elementIndex = 0) { return getBinding(binding)->getDescriptorIndex(elementIndex); }
	MVKDescriptorSetLayoutBinding* getBinding(uint32_t binding, uint32_t bindingIndexOffset = 0);
	uint32_t getBufferSizeBufferArgBuferIndex() { return 0; }
	id <MTLArgumentEncoder> getMTLArgumentEncoder(uint32_t variableDescriptorCount);
	size_t getMetal3ArgumentBufferEncodedLength(uint32_t variableDescriptorCount);
	bool checkCanUseArgumentBuffers(const VkDescriptorSetLayoutCreateInfo* pCreateInfo);

	MVKSmallVector<MVKDescriptorSetLayoutBinding> _bindings;
	std::unordered_map<uint32_t, uint32_t> _bindingToIndex;
	MVKShaderResourceBinding _mtlResourceCounts;
	int32_t _maxBufferIndex = -1;
	bool _isPushDescriptorLayout = false;
	bool _canUseMetalArgumentBuffer = true;
};


#pragma mark -
#pragma mark MVKDescriptorSet

/** Represents a Vulkan descriptor set. */
class MVKDescriptorSet : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_SET; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_SET_EXT; }

	/** Returns the layout that defines this descriptor set. */
	MVKDescriptorSetLayout* getLayout() { return _layout; }

	/** Returns the descriptor type for the specified binding number. */
	VkDescriptorType getDescriptorType(uint32_t binding);

	/** Updates the resource bindings in this instance from the specified content. */
	template<typename DescriptorAction>
	void write(const DescriptorAction* pDescriptorAction, size_t srcStride, const void* pData);

	/** 
	 * Reads the resource bindings defined in the specified content 
	 * from this instance into the specified collection of bindings.
	 */
	void read(const VkCopyDescriptorSet* pDescriptorCopies,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock);

	/** Returns the descriptor at an index. */
	MVKDescriptor* getDescriptorAt(uint32_t descIndex) { return _descriptors[descIndex]; }

	/** Returns the number of descriptors in this descriptor set. */
	uint32_t getDescriptorCount() { return (uint32_t)_descriptors.size(); }

	/** Returns the count of descriptors in the binding in this descriptor set that has a variable descriptor count. */
	uint32_t getVariableDescriptorCount() const { return _variableDescriptorCount; }

	/** Returns the number of descriptors in this descriptor set that use dynamic offsets. */
	uint32_t getDynamicOffsetDescriptorCount() { return _dynamicOffsetDescriptorCount; }

	/** Returns true if this descriptor set is using a Metal argument buffer. */
	bool hasMetalArgumentBuffer() { return _layout->isUsingMetalArgumentBuffers(); };

	/** Returns the argument buffer helper object used by this descriptor set. */
	MVKMetalArgumentBuffer& getMetalArgumentBuffer() { return _argumentBuffer; }

	/** Encode the buffer sizes auxiliary buffer to the GPU. */
	void encodeAuxBufferUsage(MVKCommandEncoder& mvkEncoder, MVKShaderStage stage);

	MVKDescriptorSet(MVKDescriptorPool* pool);

	~MVKDescriptorSet() override;

protected:
	friend class MVKDescriptorSetLayoutBinding;
	friend class MVKDescriptorPool;
	friend class MVKBufferDescriptor;
	friend class MVKInlineUniformBlockDescriptor;

	void propagateDebugName() override {}
	MVKDescriptor* getDescriptor(uint32_t binding, uint32_t elementIndex = 0);
	VkResult allocate(MVKDescriptorSetLayout* layout,
					  uint32_t variableDescriptorCount,
					  NSUInteger mtlArgBuffOffset,
					  NSUInteger mtlArgBuffEncSize,
					  id<MTLArgumentEncoder> mtlArgEnc);
	void free(bool isPoolReset);
	MVKMTLBufferAllocation* acquireMTLBufferRegion(NSUInteger length);
	void setBufferSize(uint32_t descIdx, uint32_t value);

	MVKDescriptorPool* _pool;
	MVKDescriptorSetLayout* _layout = nullptr;
	MVKMTLBufferAllocation* _bufferSizesBuffer = nullptr;
	MVKSmallVector<MVKDescriptor*> _descriptors;
	MVKMetalArgumentBuffer _argumentBuffer;
	uint32_t _dynamicOffsetDescriptorCount = 0;
	uint32_t _variableDescriptorCount = 0;
	bool _allDescriptorsAreFromPool = true;
};


#pragma mark -
#pragma mark MVKDescriptorTypePool

/** Support class for MVKDescriptorPool that holds a pool of instances of a single concrete descriptor class. */
template<class DescriptorClass>
class MVKDescriptorTypePool : public MVKBaseObject {

public:

	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; };

	MVKDescriptorTypePool(size_t poolSize);

protected:
	friend class MVKDescriptorPool;

	VkResult allocateDescriptor(VkDescriptorType descType, MVKDescriptor** pMVKDesc, bool& dynamicAllocation, MVKDescriptorPool* pool);
	void freeDescriptor(MVKDescriptor* mvkDesc, MVKDescriptorPool* pool);
	void reset();
	size_t size() { return _availability.size(); }
	size_t getRemainingDescriptorCount();

	MVKSmallVector<DescriptorClass> _descriptors;
	MVKBitArray _availability;
};


#pragma mark -
#pragma mark MVKDescriptorPool

/** Represents a Vulkan descriptor pool. */
class MVKDescriptorPool : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_POOL; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_POOL_EXT; }

	/** Allocates descriptor sets. */
	VkResult allocateDescriptorSets(const VkDescriptorSetAllocateInfo* pAllocateInfo,
									VkDescriptorSet* pDescriptorSets);

	/** Free's up the specified descriptor set. */
	VkResult freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets);

	/** Destroys all currently allocated descriptor sets. */
	VkResult reset(VkDescriptorPoolResetFlags flags);

	/** Returns a text description of this pool. */
	std::string getLogDescription(std::string indent = "");

	MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo);

	~MVKDescriptorPool() override;

protected:
	friend class MVKDescriptorSet;
	template<class> friend class MVKDescriptorTypePool;

	void propagateDebugName() override {}
	VkResult allocateDescriptorSet(MVKDescriptorSetLayout* mvkDSL, uint32_t variableDescriptorCount, VkDescriptorSet* pVKDS);
	void freeDescriptorSet(MVKDescriptorSet* mvkDS, bool isPoolReset);
	VkResult allocateDescriptor(VkDescriptorType descriptorType, MVKDescriptor** pMVKDesc, bool& dynamicAllocation);
	void freeDescriptor(MVKDescriptor* mvkDesc);
	void initMetalArgumentBuffer(const VkDescriptorPoolCreateInfo* pCreateInfo);
	NSUInteger getMetalArgumentBufferEncodedResourceStorageSize(NSUInteger bufferCount, NSUInteger textureCount, NSUInteger samplerCount);
	MTLArgumentDescriptor* getMTLArgumentDescriptor(MTLDataType resourceType, NSUInteger argIndex, NSUInteger count);
	size_t getPoolSize(const VkDescriptorPoolCreateInfo* pCreateInfo, VkDescriptorType descriptorType);

	MVKSmallVector<MVKDescriptorSet> _descriptorSets;
	MVKBitArray _descriptorSetAvailablility;
	MVKMTLBufferAllocator _mtlBufferAllocator;
	id<MTLBuffer> _metalArgumentBuffer = nil;

	MVKDescriptorTypePool<MVKUniformBufferDescriptor> _uniformBufferDescriptors;
	MVKDescriptorTypePool<MVKStorageBufferDescriptor> _storageBufferDescriptors;
	MVKDescriptorTypePool<MVKUniformBufferDynamicDescriptor> _uniformBufferDynamicDescriptors;
	MVKDescriptorTypePool<MVKStorageBufferDynamicDescriptor> _storageBufferDynamicDescriptors;
	MVKDescriptorTypePool<MVKInlineUniformBlockDescriptor> _inlineUniformBlockDescriptors;
	MVKDescriptorTypePool<MVKSampledImageDescriptor> _sampledImageDescriptors;
	MVKDescriptorTypePool<MVKStorageImageDescriptor> _storageImageDescriptors;
	MVKDescriptorTypePool<MVKInputAttachmentDescriptor> _inputAttachmentDescriptors;
	MVKDescriptorTypePool<MVKSamplerDescriptor> _samplerDescriptors;
	MVKDescriptorTypePool<MVKCombinedImageSamplerDescriptor> _combinedImageSamplerDescriptors;
	MVKDescriptorTypePool<MVKUniformTexelBufferDescriptor> _uniformTexelBufferDescriptors;
	MVKDescriptorTypePool<MVKStorageTexelBufferDescriptor> _storageTexelBufferDescriptors;

	VkDescriptorPoolCreateFlags _flags = 0;
	size_t _allocatedDescSetCount = 0;
	size_t _freeArgBuffSpace = 0;
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
