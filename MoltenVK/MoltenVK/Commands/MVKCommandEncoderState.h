/*
 * MVKCommandEncoderState.h
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

#include "MVKMTLResourceBindings.h"
#include "MVKCommandResourceFactory.h"
#include "MVKDevice.h"
#include "MVKPipeline.h"
#include "MVKSmallVector.h"
#include "MVKBitArray.h"
#include <unordered_map>
#include <objc/message.h>

class MVKCommandEncoder;
class MVKGraphicsPipeline;
class MVKDescriptorSet;
class MVKOcclusionQueryPool;

struct MVKShaderImplicitRezBinding;

enum class MVKMetalGraphicsStage {
	Vertex,
	Fragment,
	Count
};

#pragma mark - Dynamic Resource Binders

/** Provides dynamic dispatch for binding resources to an encoder. */
struct MVKResourceBinder {
	typedef void (*UseResource)(id<MTLCommandEncoder> encoder, id<MTLResource> resource, MTLResourceUsage usage, MVKResourceUsageStages stages);
	SEL _setBytes;
	SEL _setBuffer;
	SEL _setOffset;
	SEL _setTexture;
	SEL _setSampler;
	UseResource useResource;
	template <typename T> static MVKResourceBinder Create() {
		return { T::selSetBytes(), T::selSetBuffer(), T::selSetOffset(), T::selSetTexture(), T::selSetSampler(), T::useResource() };
	}
	void setBytes(id<MTLCommandEncoder> encoder, const void* bytes, NSUInteger length, NSUInteger index) const {
		reinterpret_cast<void(*)(id, SEL, const void*, NSUInteger, NSUInteger)>(objc_msgSend)(encoder, _setBytes, bytes, length, index);
	}
	void setBuffer(id<MTLCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger index) const {
		reinterpret_cast<void(*)(id, SEL, id<MTLBuffer>, NSUInteger, NSUInteger)>(objc_msgSend)(encoder, _setBuffer, buffer, offset, index);
	}
	void setBufferOffset(id<MTLCommandEncoder> encoder, NSUInteger offset, NSUInteger index) const {
		reinterpret_cast<void(*)(id, SEL, NSUInteger, NSUInteger)>(objc_msgSend)(encoder, _setOffset, offset, index);
	}
	void setTexture(id<MTLCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) const {
		reinterpret_cast<void(*)(id, SEL, id<MTLTexture>, NSUInteger)>(objc_msgSend)(encoder, _setTexture, texture, index);
	}
	void setSampler(id<MTLCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) const {
		reinterpret_cast<void(*)(id, SEL, id<MTLSamplerState>, NSUInteger)>(objc_msgSend)(encoder, _setSampler, sampler, index);
	}
	enum class Stage {
		Vertex   = static_cast<uint32_t>(MVKMetalGraphicsStage::Vertex),
		Fragment = static_cast<uint32_t>(MVKMetalGraphicsStage::Fragment),
		Compute  = static_cast<uint32_t>(MVKMetalGraphicsStage::Count),
		Count
	};
	static const MVKResourceBinder& Get(Stage stage) GCC_CONST;
	static const MVKResourceBinder& Get(MVKMetalGraphicsStage stage) { return Get(static_cast<Stage>(stage)); }
	static const MVKResourceBinder& Vertex()   { return Get(Stage::Vertex); }
	static const MVKResourceBinder& Fragment() { return Get(Stage::Fragment); }
	static const MVKResourceBinder& Compute()  { return Get(Stage::Compute); }
};

/** Provides dynamic dispatch for binding vertex buffers to an encoder. */
struct MVKVertexBufferBinder {
	SEL _setBuffer;
	SEL _setOffset;
#if MVK_XCODE_15
	SEL _setBufferDynamic;
	SEL _setOffsetDynamic;
#endif
	template <typename T> static MVKVertexBufferBinder Create() {
#if MVK_XCODE_15
		return { T::selSetBuffer(), T::selSetOffset(), T::selSetBufferDynamic(), T::selSetOffsetDynamic() };
#else
		return { T::selSetBuffer(), T::selSetOffset() };
#endif
	}
	void setBuffer(id<MTLCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger index) const {
		reinterpret_cast<void(*)(id, SEL, id<MTLBuffer>, NSUInteger, NSUInteger)>(objc_msgSend)(encoder, _setBuffer, buffer, offset, index);
	}
	void setBufferOffset(id<MTLCommandEncoder> encoder, NSUInteger offset, NSUInteger index) const {
		reinterpret_cast<void(*)(id, SEL, NSUInteger, NSUInteger)>(objc_msgSend)(encoder, _setOffset, offset, index);
	}
	void setBufferDynamic(id<MTLCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger stride, NSUInteger index) const {
#if MVK_XCODE_15
		reinterpret_cast<void(*)(id, SEL, id<MTLBuffer>, NSUInteger, NSUInteger, NSUInteger)>(objc_msgSend)(encoder, _setBufferDynamic, buffer, offset, stride, index);
#else
		assert(0);
#endif
	}
	void setBufferOffsetDynamic(id<MTLCommandEncoder> encoder, NSUInteger offset, NSUInteger stride, NSUInteger index) const {
#if MVK_XCODE_15
		reinterpret_cast<void(*)(id, SEL, NSUInteger, NSUInteger, NSUInteger)>(objc_msgSend)(encoder, _setOffsetDynamic, offset, stride, index);
#else
		assert(0);
#endif
	}
	enum class Stage {
		Vertex,
		Compute,
		Count
	};
	static const MVKVertexBufferBinder& Get(Stage stage) GCC_CONST;
	static const MVKVertexBufferBinder& Vertex()  { return Get(Stage::Vertex); }
	static const MVKVertexBufferBinder& Compute() { return Get(Stage::Compute); }
};

#pragma mark - Vulkan Command Encoder State Structs

/** Tracks state that's shared across both render and compute bind points. */
struct MVKVulkanSharedCommandEncoderState {
	MVKSmallVector<uint8_t, 128> _pushConstants;
};

struct MVKImplicitBufferData {
	MVKSmallVector<uint32_t, 8> textureSwizzles;
	MVKSmallVector<uint32_t, 8> bufferSizes;
	MVKSmallVector<uint32_t, 8> dynamicOffsets;
};

enum class MVKResourceUsageStages : uint8_t {
	Vertex   = static_cast<uint32_t>(MVKMetalGraphicsStage::Vertex),
	Fragment = static_cast<uint32_t>(MVKMetalGraphicsStage::Fragment),
	All      = static_cast<uint32_t>(MVKMetalGraphicsStage::Count),
	Count,
	Compute  = 0, // Aliases with Render stages
	None     = Count, // Should not be passed to MVKUseResourceHelper
};

struct MVKUseResourceHelper {
	struct Entry {
		MVKSmallVector<id<MTLResource>> read;
		MVKSmallVector<id<MTLResource>> readWrite;
		MVKSmallVector<id<MTLResource>>& get(bool write) { return write ? readWrite : read; }
	};
	struct ResourceInfo {
		MVKResourceUsageStages stages;
		bool write;
		bool deferred;
	};
	MVKOnePerEnumEntry<Entry, MVKResourceUsageStages> entries;
	std::unordered_map<id<MTLResource>, ResourceInfo> used;
	/** Add a resource to the list of resources to use. */
	void add(id<MTLResource> resource, MVKResourceUsageStages stage, bool write);
	/**
	 * Immediately use the given resource.
	 * (Important if you're holding a live resources lock and need to useResource before releasing the lock.)
	 */
	void addImmediate(id<MTLResource> resource, id<MTLCommandEncoder> enc, MVKResourceBinder::UseResource func, MVKResourceUsageStages stage, bool write);
	void bindAndResetGraphics(id<MTLRenderCommandEncoder> encoder);
	void bindAndResetCompute(id<MTLComputeCommandEncoder> encoder);
};

/**
 * Tracks state that is needed by all Vulkan command encoder state trackers but is independent.
 * (Commands that update these take a VkPipelineBindPoint to specify which state to update.)
 */
struct MVKVulkanCommonEncoderState {
	MVKPipelineLayout* _layout = nullptr;
	MVKDescriptorSet* _descriptorSets[kMVKMaxDescriptorSetCount];
	MVKDescriptorSet _pushDescriptor = {};
	MVKSmallVector<uint8_t, 16> _pushDescData;
	void ensurePushDescriptorSize(uint32_t size);
	void setLayout(MVKPipelineLayout* layout);
	MVKVulkanCommonEncoderState() = default;
	MVKVulkanCommonEncoderState(const MVKVulkanCommonEncoderState& other);
	MVKVulkanCommonEncoderState& operator=(const MVKVulkanCommonEncoderState& other);
};

/** Tracks the state of a Vulkan render encoder. */
struct MVKVulkanGraphicsCommandEncoderState: public MVKVulkanCommonEncoderState {
	MVKGraphicsPipeline* _pipeline = nullptr;
	MVKRenderStateData _renderState;
	MVKVertexMTLBufferBinding _vertexBuffers[kMVKMaxBufferCount];
	MVKIndexMTLBufferBinding _indexBuffer;
	VkViewport _viewports[kMVKMaxViewportScissorCount];
	VkRect2D _scissors[kMVKMaxViewportScissorCount];
	MTLSamplePosition _sampleLocations[kMVKMaxSampleCount];
	MVKImplicitBufferData _implicitBufferData[kMVKShaderStageFragment + 1];

	/** Choose between the dynamic and pipeline render states based on whether the given state flag is marked dynamic on the pipeline. */
	const MVKRenderStateData& pickRenderState(MVKRenderStateFlag state) const {
		bool dynamic = _pipeline->getDynamicStateFlags().has(state);
		return *(dynamic ? &_renderState : &_pipeline->getStaticStateData());
	}
	MVKArrayRef<const MTLSamplePosition> getSamplePositions() const;
	bool isBresenhamLines() const;
	uint32_t getPatchControlPoints() const {
		return pickRenderState(MVKRenderStateFlag::PatchControlPoints).patchControlPoints;
	}

	/** Bind the given descriptor sets, placing their bindings into `_descriptorSetBindings`. */
	void bindDescriptorSets(MVKPipelineLayout* layout,
	                        uint32_t firstSet,
	                        uint32_t setCount,
	                        MVKDescriptorSet*const* sets,
	                        uint32_t dynamicOffsetCount,
	                        const uint32_t* dynamicOffsets);
};

/** Tracks the state of a Vulkan compute encoder. */
struct MVKVulkanComputeCommandEncoderState: public MVKVulkanCommonEncoderState {
	MVKComputePipeline* _pipeline = nullptr;
	MVKImplicitBufferData _implicitBufferData;

	/** Bind the given descriptor sets, placing their bindings into `_descriptorSetBindings`. */
	void bindDescriptorSets(MVKPipelineLayout* layout,
	                        uint32_t firstSet,
	                        uint32_t setCount,
	                        MVKDescriptorSet*const* sets,
	                        uint32_t dynamicOffsetCount,
	                        const uint32_t* dynamicOffsets);
};

struct MVKMetalSharedCommandEncoderState {
	/** Storage space for use by various methods to reduce alloc/free. */
	MVKSmallVector<uint32_t, 8> _scratch;

	/** Storage for tracking which objects need to have useResource called on them. */
	MVKUseResourceHelper _useResource;

	/** Which GPU addressable resources have been added to `_useResource`. */
	MVKResourceUsageStages _gpuAddressableResourceStages;

	void reset() {
		_gpuAddressableResourceStages = MVKResourceUsageStages::None;
		_useResource.used.clear();
	}
};

#pragma mark - MVKMetalRenderCommandEncoderState

struct MVKStageResourceBindings {
	id<MTLTexture> textures[kMVKMaxTextureCount];
	struct Buffer {
		id<MTLBuffer> buffer;
		VkDeviceSize offset;
		bool operator==(Buffer other) const { return std::make_pair(buffer, offset) == std::make_pair(other.buffer, other.offset); }
		bool operator!=(Buffer other) const { return !(*this == other); }
	} buffers[kMVKMaxBufferCount];
	id<MTLSamplerState> samplers[kMVKMaxSamplerCount];
	MVKBitArray descriptorSetResourceUse[kMVKMaxDescriptorSetCount];
	MVKOnePerEnumEntry<uint8_t, MVKNonVolatileImplicitBuffer> implicitBufferIndices = {};
	static Buffer ImplicitBuffer(MVKImplicitBuffer buffer) {
		return { nil, static_cast<VkDeviceSize>(buffer) + 1 };
	}
	static Buffer ImplicitBuffer(MVKNonVolatileImplicitBuffer buffer) {
		return ImplicitBuffer(static_cast<MVKImplicitBuffer>(buffer));
	}
	static Buffer NullBuffer() { return { nil, 0 }; }
	static Buffer InvalidBuffer() { return { nil, ~0ull }; }
};

template <typename T>
struct MVKOnePerGraphicsStage: public MVKOnePerEnumEntry<T, MVKMetalGraphicsStage> {
	      T& vertex()         { return (*this)[MVKMetalGraphicsStage::Vertex]; }
	const T& vertex()   const { return (*this)[MVKMetalGraphicsStage::Vertex]; }
	      T& fragment()       { return (*this)[MVKMetalGraphicsStage::Fragment]; }
	const T& fragment() const { return (*this)[MVKMetalGraphicsStage::Fragment]; }
};

enum class MVKMetalRenderEncoderStateFlag {
	DepthBiasEnable,
	DepthBoundsEnable,
	DepthClampEnable,
	DepthTestEnable,
	RasterizationDisabledByScissor,
	ScissorDirty,
	PipelineReady,
	SamplePositionsOverridden,
	Count
};

using MVKMetalRenderEncoderStateFlags = MVKFlagList<MVKMetalRenderEncoderStateFlag>;

class MVKRenderSubpass;

/** The state for a draw inserted by MoltenVK. */
struct MVKHelperDrawState {
	id<MTLRenderPipelineState> pipeline;
	VkRect2D viewportAndScissor;
	uint32_t stencilReference;
	bool writeDepth;
	bool writeStencil;
};

/** Subset of MVKMetalGraphicsCommandEncoderState that can be reset with memset. */
struct MVKMetalGraphicsCommandEncoderStateQuickReset {
	/**
	 * If clear, ignore the binding in `bindings` and assume the Metal default value (usually nil / zero).
	 * Allows us to quickly reset to the state of a fresh command encoder without having to zero all the bindings.
	 */
	MVKOnePerGraphicsStage<MVKStageResourceBits> _exists;

	id<MTLRenderPipelineState> _pipeline;

	/** Flags that mark whether a render state matches the current Vulkan render state. */
	MVKRenderStateFlags _stateReady;
	/** Other single-bit flags. */
	MVKMetalRenderEncoderStateFlags _flags;

	MVKStencilReference _stencilReference;
	MVKColor32 _blendConstants;
	uint8_t _numViewports;
	uint8_t _numScissors;
	uint8_t _patchControlPoints;
	uint8_t _cullMode;
	uint8_t _frontFace;
	MVKPolygonMode _polygonMode;

	// Memset 0 to here to clear.
	// DO NOT memset sizeof(*this), or you'll clear padding, which is used by subclasses.
	struct {} MEMSET_RESET_LINE;
};

/** Tracks the state of a Metal render encoder. */
struct MVKMetalGraphicsCommandEncoderState : public MVKMetalGraphicsCommandEncoderStateQuickReset {
	uint8_t _primitiveType;
	uint8_t _numSamplePositions = 0;
	MVKDepthBias _depthBias;
	MVKDepthBounds _depthBounds;
	float _lineWidth;
	uint32_t _sampleCount;
	MVKMTLDepthStencilDescriptorData _depthStencil;

	MVKOnePerGraphicsStage<MVKStageResourceBindings> _bindings;

	VkViewport _viewports[kMVKMaxViewportScissorCount];
	VkRect2D _scissors[kMVKMaxViewportScissorCount];
	MTLSamplePosition _samplePositions[kMVKMaxSampleCount];

	MTLPrimitiveType getPrimitiveType() const { return static_cast<MTLPrimitiveType>(_primitiveType); }

	/** For API compatibility with MVKMetalComputeCommandEncoderState. */
	MVKArrayRef<MVKStageResourceBits> exists() { return _exists.elements; }

	/** Reset to the state of a fresh Metal render encoder. */
	void reset(VkSampleCountFlags sampleCount);

	/** Mark the given pieces of render state as dirty. */
	void markDirty(MVKRenderStateFlags flags) { _stateReady.removeAll(flags); }
	/** Mark everything dirty that needs to be marked when changing pipelines. */
	void changePipeline(MVKGraphicsPipeline* from, MVKGraphicsPipeline* to);

	void bindFragmentBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index);
	void bindFragmentBytes(id<MTLRenderCommandEncoder> encoder, const void* data, size_t size, NSUInteger index);
	void bindFragmentTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index);
	void bindFragmentSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index);
	void bindVertexBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index);
	void bindVertexBytes(id<MTLRenderCommandEncoder> encoder, const void* data, size_t size, NSUInteger index);
	void bindVertexTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index);
	void bindVertexSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index);
	template <typename T> void bindFragmentStructBytes(id<MTLComputeCommandEncoder> encoder, const T& t, NSUInteger index) { bindFragmentBytes(encoder, &t, sizeof(T), index); }
	template <typename T> void bindVertexStructBytes(id<MTLComputeCommandEncoder> encoder, const T& t, NSUInteger index) { bindVertexBytes(encoder, &t, sizeof(T), index); }
	void bindStateData(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, const MVKRenderStateData& data, MVKRenderStateFlags flags, const VkViewport* viewports, const VkRect2D* scissors);
	void bindState(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, const MVKVulkanGraphicsCommandEncoderState& vkState);
	void prepareDraw(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, const MVKVulkanGraphicsCommandEncoderState& vkState, const MVKVulkanSharedCommandEncoderState& vkShared);
	void prepareHelperDraw(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, const MVKHelperDrawState& state);
};

#pragma mark - MVKMetalComputeCommandEncoderState

/** Tracks the state of a Metal compute encoder */
struct MVKMetalComputeCommandEncoderState {
	/**
	 * If clear, ignore the binding in `bindings` and assume the Metal default value (usually nil / zero).
	 * Allows us to quickly reset to the state of a fresh command encoder without having to zero all the bindings.
	 */
	MVKStageResourceBits _exists;

	id<MTLComputePipelineState> _pipeline;

	MVKPipeline* _vkPipeline;

	// Everything above here can be reset by a memset from the beginning of the struct to offsetof(struct, MEMSET_RESET_LINE)
	struct {} MEMSET_RESET_LINE;

	/** The current stage being run on this compute encoder. */
	MVKShaderStage _vkStage = kMVKShaderStageCount;

	MVKStageResourceBindings _bindings;

	void bindPipeline(id<MTLComputeCommandEncoder> encoder, id<MTLComputePipelineState> pipeline);
	void bindBuffer(id<MTLComputeCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index);
	void bindBytes(id<MTLComputeCommandEncoder> encoder, const void* data, size_t size, NSUInteger index);
	void bindTexture(id<MTLComputeCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index);
	void bindSampler(id<MTLComputeCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index);
	template <typename T> void bindStructBytes(id<MTLComputeCommandEncoder> encoder, const T* t, NSUInteger index) { bindBytes(encoder, t, sizeof(T), index); }
	void prepareComputeDispatch(id<MTLComputeCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, const MVKVulkanComputeCommandEncoderState& vkState, const MVKVulkanSharedCommandEncoderState& vkShared);
	void prepareRenderDispatch(id<MTLComputeCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, const MVKVulkanGraphicsCommandEncoderState& vkState, const MVKVulkanSharedCommandEncoderState& vkShared, MVKShaderStage stage);

	/** For API compatibility with MVKMetalGraphicsCommandEncoderState. */
	MVKArrayRef<MVKStageResourceBits> exists() { return {&_exists, 1}; }

	void reset();
};

#pragma mark - MVKCommandEncoderState

/** Holds both Metal and Vulkan state for both compute and graphics. */
class MVKCommandEncoderState {
	MVKVulkanSharedCommandEncoderState   _vkShared;
	MVKVulkanGraphicsCommandEncoderState _vkGraphics;
	MVKVulkanComputeCommandEncoderState  _vkCompute;
	MVKMetalSharedCommandEncoderState    _mtlShared;
	MVKMetalGraphicsCommandEncoderState  _mtlGraphics;
	MVKMetalComputeCommandEncoderState   _mtlCompute;
	enum class CommandEncoderClass {
		None,
		Graphics,
		Compute
	};
	/** The type of Metal encoder, if any, that is currently active. */
	CommandEncoderClass _mtlActiveEncoder;

	/** Get the encoder state associated with the given bind point, or nullptr if the bindPoint isn't supported. */
	MVKVulkanCommonEncoderState* getVkEncoderState(VkPipelineBindPoint bindPoint);

public:
	/** Get a reference to the Vulkan state shared between graphics and compute.  Read-only, use methods on this class (which will invalidate associated Metal state) to modify. */
	const MVKVulkanSharedCommandEncoderState&   vkShared()   const { return _vkShared; }
	/** Get a reference to the Vulkan graphics state.  Read-only, use methods on this class (which will invalidate associated Metal state) to modify. */
	const MVKVulkanGraphicsCommandEncoderState& vkGraphics() const { return _vkGraphics; }
	/** Get a reference to the Vulkan compute state.  Read-only, use methods on this class (which will invalidate associated Metal state) to modify. */
	const MVKVulkanComputeCommandEncoderState&  vkCompute()  const { return _vkCompute; }
	/** Returns a reference to the Metal state shared between graphics and compute. */
	MVKMetalSharedCommandEncoderState&   mtlShared()   { return _mtlShared; }
	/** Returns a reference to the Metal graphics state. */
	MVKMetalGraphicsCommandEncoderState& mtlGraphics() { return _mtlGraphics; }
	/** Returns a reference to the Metal compute state. */
	MVKMetalComputeCommandEncoderState&  mtlCompute()  { return _mtlCompute; }

	/**
	 * Updates the given dynamic state, invalidating the passed flags on the Metal graphics state.
	 * Use the returned reference to do the actual update to the Vulkan state.
	 */
	MVKVulkanGraphicsCommandEncoderState& updateDynamicState(MVKRenderStateFlags state) {
		_mtlGraphics.markDirty(state);
		return _vkGraphics;
	}

	/** Returns the current sample positions and marks those positions as the currently bound positions. */
	MVKArrayRef<const MTLSamplePosition> updateSamplePositions();
	/** Checks if the render pass needs to be restarted before drawing with the current graphics configuration. */
	bool needsMetalRenderPassRestart();
	/** Binds everything needed to render with the current Vulkan graphics state on the current Metal graphics state. */
	void prepareDraw(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder) {
		_mtlGraphics.prepareDraw(encoder, mvkEncoder, _vkGraphics, _vkShared);
	}
	/** Binds everything needed to dispatch a compute-based emulation of the given stage of the current Vulkan graphics state on the current Metal compute state. */
	void prepareRenderDispatch(id<MTLComputeCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, MVKGraphicsStage stage) {
		assert(stage == kMVKGraphicsStageVertex || stage == kMVKGraphicsStageTessControl);
		MVKShaderStage shaderStage = stage == kMVKGraphicsStageVertex ? kMVKShaderStageVertex : kMVKShaderStageTessCtl;
		_mtlCompute.prepareRenderDispatch(encoder, mvkEncoder, _vkGraphics, _vkShared, shaderStage);
	}
	/** Binds everything needed to dispatch a Vulkan compute shader on the current Metal compute state. */
	void prepareComputeDispatch(id<MTLComputeCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder) {
		_mtlCompute.prepareComputeDispatch(encoder, mvkEncoder, _vkCompute, _vkShared);
	}
	/** Binds the given graphics pipeline to the Vulkan graphics state, invalidating any necessary resources. */
	void bindGraphicsPipeline(MVKGraphicsPipeline* pipeline);
	/** Binds the given compute pipeline to the Vulkan graphics state, invalidating any necessary resources. */
	void bindComputePipeline(MVKComputePipeline* pipeline);
	/** Binds the given push constants to the Vulkan state, invalidating any necessary resources. */
	void pushConstants(uint32_t offset, uint32_t size, const void* data);
	/** Binds the given descriptor sets to the Vulkan state, invalidating any necessary resources. */
	void bindDescriptorSets(VkPipelineBindPoint bindPoint,
	                        MVKPipelineLayout* layout,
	                        uint32_t firstSet,
	                        uint32_t setCount,
	                        MVKDescriptorSet*const* sets,
	                        uint32_t dynamicOffsetCount,
	                        const uint32_t* dynamicOffsets);
	/** Applies the given descriptor set writes to the push descriptor set on bindPoint. */
	void pushDescriptorSet(VkPipelineBindPoint bindPoint, MVKPipelineLayout* layout, uint32_t set, uint32_t writeCount, const VkWriteDescriptorSet* writes);
	/** Applies the given descriptor update template to the push descriptor to its specified bindPoint. */
	void pushDescriptorSet(MVKDescriptorUpdateTemplate* updateTemplate, MVKPipelineLayout* layout, uint32_t set, const void* data);
	/** Binds the given vertex buffers to the Vulkan state, invalidating any necessary resources. */
	void bindVertexBuffers(uint32_t firstBinding, MVKArrayRef<const MVKVertexMTLBufferBinding> buffers);
	/** Binds the given index buffer to the Vulkan state, invalidating any necessary resources. */
	void bindIndexBuffer(const MVKIndexMTLBufferBinding& buffer);
	void offsetZeroDivisorVertexBuffers(MVKCommandEncoder& mvkEncoder, MVKGraphicsStage stage, MVKGraphicsPipeline* pipeline, uint32_t firstInstance);

	/** Begins tracking for a fresh MTLRenderCommandEncoder. */
	void beginGraphicsEncoding(VkSampleCountFlags sampleCount);
	/** Begins tracking for a fresh MTLComputeCommandEncoder. */
	void beginComputeEncoding();

	/**
	 * Calls the given function on either the Metal graphics or compute state tracker, whichever one is active (or neither if neither is active).
	 * `bindPoint` can be used to only call the function if the given Vulkan pipeline is being encoded to the active encoder.
	 */
	template <typename Fn>
	void applyToActiveMTLState(VkPipelineBindPoint bindPoint, Fn&& fn);
};

#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

/** Holds encoder state established by occlusion query commands. */
class MVKOcclusionQueryCommandEncoderState {

public:
	void beginMetalRenderPass(MVKCommandEncoder* cmdEncoder);
	void endMetalRenderPass(MVKCommandEncoder* cmdEncoder);

    /** Begins an occlusion query. */
    void beginOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags);

    /** Ends an occlusion query. */
    void endOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query);

	void encode(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder* mvkEncoder);

	void prepareHelperDraw(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder* mvkEncoder);

private:
	void beginOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query, MTLVisibilityResultMode mode);

	typedef struct OcclusionQueryLocation {
		MVKOcclusionQueryPool* queryPool = nullptr;
		uint32_t query = 0;
		NSUInteger visibilityBufferOffset = 0;

		OcclusionQueryLocation(MVKOcclusionQueryPool* qPool, uint32_t qIdx, NSUInteger vbOfst)
		: queryPool(qPool), query(qIdx), visibilityBufferOffset(vbOfst) {}

	} OcclusionQueryLocation;

	MVKSmallVector<OcclusionQueryLocation> _mtlRenderPassQueries;
    MTLVisibilityResultMode _mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
	bool _hasRasterized = false;
	bool _dirty = false;
};


