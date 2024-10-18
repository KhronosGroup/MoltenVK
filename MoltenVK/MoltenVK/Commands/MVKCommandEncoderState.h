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
#include "MVKDescriptor.h"
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
	SEL _setBytes;
	SEL _setBuffer;
	SEL _setOffset;
	SEL _setTexture;
	SEL _setSampler;
	template <typename T> static MVKResourceBinder Create() {
		return { T::selSetBytes(), T::selSetBuffer(), T::selSetOffset(), T::selSetTexture(), T::selSetSampler() };
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

#pragma mark - MVKVulkanRenderCommandEncoderState

struct MVKBindingList {
	MVKSmallVector<MVKMTLBufferBinding, 8> bufferBindings;
	MVKSmallVector<MVKMTLTextureBinding, 8> textureBindings;
	MVKSmallVector<MVKMTLSamplerStateBinding, 8> samplerStateBindings;
};

/** Tracks the state of a Vulkan render encoder. */
struct MVKVulkanGraphicsCommandEncoderState {
	MVKPipelineLayout* _layout = nullptr;
	MVKGraphicsPipeline* _pipeline = nullptr;
	MVKRenderStateData _renderState;
	VkViewport _viewports[kMVKMaxViewportScissorCount];
	VkRect2D _scissors[kMVKMaxViewportScissorCount];
	MTLSamplePosition _sampleLocations[kMVKMaxSampleCount];

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

/** Tracks the state of a Metal render encoder. */
struct MVKMetalGraphicsCommandEncoderState {
	/**
	 * If clear, ignore the binding in `bindings` and assume the Metal default value (usually nil / zero).
	 * Allows us to quickly reset to the state of a fresh command encoder without having to zero all the bindings.
	 */
	MVKOnePerGraphicsStage<MVKStageResourceBits> _exists;
	/** If set, the resource matches what is needed by the current pipeline + descriptor set. */
	MVKOnePerGraphicsStage<MVKStageResourceBits> _ready;

	id<MTLRenderPipelineState> _pipeline;

	/** Flags that mark whether a render state matches the current Vulkan render state. */
	MVKRenderStateFlags _stateReady;
	/** Other single-bit flags. */
	MVKMetalRenderEncoderStateFlags _flags;
	MVKStaticBitSet<kMVKMaxDescriptorSetCount> _descriptorSetsReady;

	MVKStencilReference _stencilReference;
	MVKColor32 _blendConstants;
	uint8_t _numViewports;
	uint8_t _numScissors;
	uint8_t _patchControlPoints;
	uint8_t _cullMode;
	uint8_t _frontFace;
	MVKPolygonMode _polygonMode;

	// Everything above here can be reset by a memset from the beginning of the struct to offsetof(struct, MEMSET_RESET_LINE)
	struct {} MEMSET_RESET_LINE;

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
	void bindResources(id<MTLRenderCommandEncoder> encoder, const MVKVulkanGraphicsCommandEncoderState& vkState);
	void prepareDraw(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, const MVKVulkanGraphicsCommandEncoderState& vkState);
	void prepareHelperDraw(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, const MVKHelperDrawState& state);
};

#pragma mark - MVKCommandEncoderStateNew

/** Holds both Metal and Vulkan state for both compute and graphics. */
class MVKCommandEncoderStateNew {
	MVKVulkanGraphicsCommandEncoderState _vkGraphics;
	MVKMetalGraphicsCommandEncoderState  _mtlGraphics;

public:
	/** Get a reference to the Vulkan graphics state.  Read-only, use methods on this class (which will invalidate associated Metal state) to modify. */
	const MVKVulkanGraphicsCommandEncoderState& vkGraphics() const { return _vkGraphics; }
	/** Get a reference to the Metal graphics state. */
	MVKMetalGraphicsCommandEncoderState& mtlGraphics() { return _mtlGraphics; }

	/**
	 * Update the given dynamic state, invalidating the passed flags on the Metal graphics state.
	 * (Use the returned reference to do the actual update to the Vulkan state.)
	 */
	MVKVulkanGraphicsCommandEncoderState& updateDynamicState(MVKRenderStateFlags state) {
		_mtlGraphics.markDirty(state);
		return _vkGraphics;
	}

	/** Get the current sample positions and mark those positions as the currently bound positions. */
	MVKArrayRef<const MTLSamplePosition> updateSamplePositions();
	/** Check if the render pass needs to be restarted before drawing with the current graphics configuration. */
	bool needsMetalRenderPassRestart();
	/** Bind everything needed to render with the current Vulkan graphics state on the current Metal graphics state. */
	void prepareDraw(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder) {
		_mtlGraphics.prepareDraw(encoder, mvkEncoder, _vkGraphics);
	}
	/** Bind everything needed to dispatch a compute-based emulation of the given stage of the current Vulkan graphics state on the current Metal compute state. */
	void prepareRenderDispatch(id<MTLComputeCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, MVKGraphicsStage stage);
	/** Bind everything needed to dispatch a Vulkan compute shader on the current Metal compute state. */
	void prepareComputeDispatch(id<MTLComputeCommandEncoder>, MVKCommandEncoder& mvkEncoder);
	/** Bind the given graphics pipeline to the Vulkan graphics state, invalidating any necessary resources. */
	void bindPipeline(MVKGraphicsPipeline* pipeline);

	/** Begin tracking for a fresh MTLRenderCommandEncoder. */
	void beginGraphicsEncoding(VkSampleCountFlags sampleCount) {
		_mtlGraphics.reset(sampleCount);
	}
};

#pragma mark -
#pragma mark MVKCommandEncoderState

/** 
 * Abstract class that holds encoder state established by Vulkan commands.
 *
 * Some Vulkan commands can be issued both inside or outside a render pass, and the state 
 * encoded by the command needs to be retained by the encoder for use by following render 
 * passes. In addition, some Vulkan commands can be issued multiple times to accumulate
 * encoded content that should be submitted in one shot to the Metal encoder.
 */
class MVKCommandEncoderState : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

    /**
     * Marks the content of this instance as dirty, relative to the
     * current or next Metal render pass, and in need of submission to Metal.
     */
    virtual void markDirty() {
        _isDirty = true;
        _isModified = true;
    }

    /**
     * Called automatically when a Metal render pass begins. If the contents have been
     * modified from the default values, this instance is marked as dirty, so the contents
     * will be encoded to Metal. Default state can be left unencoded on a new Metal encoder.
     */
	virtual void beginMetalRenderPass() { if (_isModified) { markDirty(); } }

	/** Called automatically when a Metal render pass ends. */
	virtual void endMetalRenderPass() { }

	/**
	 * Called automatically when a Metal compute pass begins. If the contents have been
	 * modified from the default values, this instance is marked as dirty, so the contents
	 * will be encoded to Metal. Default state can be left unencoded on a new Metal encoder.
	 */
	virtual void beginMetalComputeEncoding() { if (_isModified) { markDirty(); } }

    /**
     * If the content of this instance is dirty, marks this instance as no longer dirty
     * and calls the encodeImpl() function to encode the content onto the Metal encoder.
	 * Marking clean is done in advance so that subclass encodeImpl() implementations
	 * can override to leave this instance in a dirty state.
     * Subclasses must override the encodeImpl() function to do the actual work.
     */
    void encode(uint32_t stage = 0) {
        if ( !_isDirty ) { return; }

        _isDirty = false;
        encodeImpl(stage);
    }

	/** Constructs this instance for the specified command encoder. */
    MVKCommandEncoderState(MVKCommandEncoder* cmdEncoder) : _cmdEncoder(cmdEncoder) {}

protected:

	virtual void encodeImpl(uint32_t stage) = 0;
	MVKDevice* getDevice();

    MVKCommandEncoder* _cmdEncoder;
	bool _isDirty = false;
    bool _isModified = false;
};


#pragma mark -
#pragma mark MVKPipelineCommandEncoderState

/** Abstract class to hold encoder state established by pipeline commands. */
class MVKPipelineCommandEncoderState : public MVKCommandEncoderState {

public:
	void bindPipeline(MVKPipeline* pipeline);

    MVKPipeline* getPipeline();

    MVKPipelineCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;

    MVKPipeline* _pipeline = nullptr;
};


#pragma mark -
#pragma mark MVKPushConstantsCommandEncoderState

/** Holds encoder state established by push constant commands for a single shader stage. */
class MVKPushConstantsCommandEncoderState : public MVKCommandEncoderState {

public:

    /** Sets the specified push constants. */
    void setPushConstants(uint32_t offset, MVKArrayRef<char> pushConstants);

    /** Sets the index of the Metal buffer used to hold the push constants. */
    void setMTLBufferIndex(uint32_t mtlBufferIndex, bool pipelineStageUsesPushConstants);

	MVKPushConstantsCommandEncoderState(MVKCommandEncoder* cmdEncoder,
                                        VkShaderStageFlagBits shaderStage)
        : MVKCommandEncoderState(cmdEncoder), _shaderStage(shaderStage) {}

protected:
    void encodeImpl(uint32_t stage) override;
	bool isTessellating();

    MVKSmallVector<char, 128> _pushConstants;
    VkShaderStageFlagBits _shaderStage;
    uint32_t _mtlBufferIndex = 0;
	bool _pipelineStageUsesPushConstants = false;
};


#pragma mark -
#pragma mark MVKResourcesCommandEncoderState

/** Abstract resource state class for supporting encoder resources. */
class MVKResourcesCommandEncoderState : public MVKCommandEncoderState {

public:

	/** Returns the currently bound pipeline for this bind point. */
	virtual MVKPipeline* getPipeline() = 0;

	/** Binds the specified descriptor set to the specified index. */
	void bindDescriptorSet(uint32_t descSetIndex,
						   MVKDescriptorSet* descSet,
						   MVKShaderResourceBinding& dslMTLRezIdxOffsets,
						   MVKArrayRef<uint32_t> dynamicOffsets,
						   uint32_t& dynamicOffsetIndex);

	/** Encodes the indirect use of the Metal resource to the Metal command encoder. */
	virtual void encodeResourceUsage(MVKShaderStage stage,
									 id<MTLResource> mtlResource,
									 MTLResourceUsage mtlUsage,
									 MTLRenderStages mtlStages) = 0;

	void markDirty() override;

    MVKResourcesCommandEncoderState(MVKCommandEncoder* cmdEncoder) :
		MVKCommandEncoderState(cmdEncoder), _boundDescriptorSets{} {}

protected:

    // Template function that marks both the vector and all binding elements in the vector as dirty.
    template<class T>
    void markDirty(T& bindings, bool& bindingsDirtyFlag) {
        for (auto& b : bindings) { b.markDirty(); }
        bindingsDirtyFlag = true;
    }

	// Template function to find and mark as overridden the binding that uses the index.
	template<class T>
	void markBufferIndexOverridden(T& bufferBindings, uint32_t index) {
		for (auto& b : bufferBindings) {
			if (b.index == index) {
				b.isOverridden = true;
				return;
			}
		}
	}

	// Template function to mark any overridden bindings as dirty.
	template<class T>
	void markOverriddenBufferIndexesDirty(T& bufferBindings, bool& bindingsDirtyFlag) {
		for (auto& b : bufferBindings) {
			if (b.isOverridden) {
				b.markDirty();
				bindingsDirtyFlag = true;
				MVKCommandEncoderState::markDirty();
			}
		}
	}

    // Template function that updates an existing binding or adds a new binding to a vector
    // of bindings, and marks the binding, the vector, and this instance as dirty
    template<class T, class V>
    void bind(const T& b, V& bindings, bool& bindingsDirtyFlag) {
        if ( !b.mtlResource ) { return; }

        for (auto& rb : bindings) {
			if (rb.index == b.index) {
                rb.update(b);
				if (rb.isDirty) {
					bindingsDirtyFlag = true;
					MVKCommandEncoderState::markDirty();
				}
                return;
            }
        }

        bindings.push_back(b);
        bindings.back().markDirty();
		bindingsDirtyFlag = true;
		MVKCommandEncoderState::markDirty();
    }

	// For texture bindings, we also keep track of whether any bindings need a texture swizzle
	template<class V>
	void bind(const MVKMTLTextureBinding& tb, V& texBindings, bool& bindingsDirtyFlag, bool& needsSwizzleFlag) {
		bind(tb, texBindings, bindingsDirtyFlag);
		if (tb.swizzle != 0) { needsSwizzleFlag = true; }
	}

    // Template function that executes a lambda expression on each dirty element of
    // a vector of bindings, and marks the bindings and the vector as no longer dirty.
	// Clear binding isDirty flag before operation to allow operation to possibly override.
	// If it does override, leave both the bindings and this instance as dirty.
	template<class T, class V>
	void encodeBinding(V& bindings,
					   bool& bindingsDirtyFlag,
					   std::function<void(MVKCommandEncoder* cmdEncoder, T& b)> mtlOperation) {
		if (bindingsDirtyFlag) {
			bindingsDirtyFlag = false;
			for (auto& b : bindings) {
				if (b.isDirty) {
					b.isDirty = false;
					mtlOperation(_cmdEncoder, b);
					if (b.isDirty) { _isDirty = bindingsDirtyFlag = true; }
				}
			}
		}
	}

	// Updates a value at the given index in the given vector, resizing if needed.
	template<class V>
	void updateImplicitBuffer(V &contents, uint32_t index, uint32_t value) {
		if (index >= contents.size()) { contents.resize(index + 1); }
		contents[index] = value;
	}

	void assertMissingSwizzles(bool needsSwizzle, const char* stageName, MVKArrayRef<const MVKMTLTextureBinding> texBindings);
	void encodeMetalArgumentBuffer(MVKShaderStage stage);
	virtual void bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) = 0;

	template<size_t N>
	struct ResourceBindings {
		MVKSmallVector<MVKMTLBufferBinding, N> bufferBindings;
		MVKSmallVector<MVKMTLTextureBinding, N> textureBindings;
		MVKSmallVector<MVKMTLSamplerStateBinding, N> samplerStateBindings;
		MVKSmallVector<uint32_t, N> swizzleConstants;
		MVKSmallVector<uint32_t, N> bufferSizes;

		MVKMTLBufferBinding swizzleBufferBinding;
		MVKMTLBufferBinding bufferSizeBufferBinding;
		MVKMTLBufferBinding dynamicOffsetBufferBinding;
		MVKMTLBufferBinding viewRangeBufferBinding;

		bool areBufferBindingsDirty = false;
		bool areTextureBindingsDirty = false;
		bool areSamplerStateBindingsDirty = false;

		bool needsSwizzle = false;
	};

	MVKDescriptorSet* _boundDescriptorSets[kMVKMaxDescriptorSetCount];
	MVKBitArray _metalUsageDirtyDescriptors[kMVKMaxDescriptorSetCount];

	MVKSmallVector<uint32_t, 8> _dynamicOffsets;

};


#pragma mark -
#pragma mark MVKGraphicsResourcesCommandEncoderState

/** Holds graphics encoder resource state established by bind vertex buffer and descriptor set commands. */
class MVKGraphicsResourcesCommandEncoderState : public MVKResourcesCommandEncoderState {

public:

	/** Returns the currently bound pipeline for this bind point. */
	MVKPipeline* getPipeline() override;

    /** Binds the specified buffer for the specified shader stage. */
    void bindBuffer(MVKShaderStage stage, const MVKMTLBufferBinding& binding);

    /** Binds the specified texture for the specified shader stage. */
    void bindTexture(MVKShaderStage stage, const MVKMTLTextureBinding& binding);

    /** Binds the specified sampler state for the specified shader stage. */
    void bindSamplerState(MVKShaderStage stage, const MVKMTLSamplerStateBinding& binding);

    /** The type of index that will be used to render primitives. Exposed directly. */
    MVKIndexMTLBufferBinding _mtlIndexBufferBinding;

    /** Binds the specified index buffer. */
    void bindIndexBuffer(const MVKIndexMTLBufferBinding& binding) {
        _mtlIndexBufferBinding = binding;   // No need to track dirty state
    }

    /** Sets the current swizzle buffer state. */
    void bindSwizzleBuffer(const MVKShaderImplicitRezBinding& binding,
                           bool needVertexSwizzleBuffer,
                           bool needTessCtlSwizzleBuffer,
                           bool needTessEvalSwizzleBuffer,
                           bool needFragmentSwizzleBuffer);

    /** Sets the current buffer size buffer state. */
    void bindBufferSizeBuffer(const MVKShaderImplicitRezBinding& binding,
                              bool needVertexSizeBuffer,
                              bool needTessCtlSizeBuffer,
                              bool needTessEvalSizeBuffer,
                              bool needFragmentSizeBuffer);

	/** Sets the current dynamic offset buffer state. */
	void bindDynamicOffsetBuffer(const MVKShaderImplicitRezBinding& binding,
								 bool needVertexDynanicOffsetBuffer,
								 bool needTessCtlDynanicOffsetBuffer,
								 bool needTessEvalDynanicOffsetBuffer,
								 bool needFragmentDynanicOffsetBuffer);

    /** Sets the current view range buffer state. */
    void bindViewRangeBuffer(const MVKShaderImplicitRezBinding& binding,
                             bool needVertexViewBuffer,
                             bool needFragmentViewBuffer);

    void encodeBindings(MVKShaderStage stage,
                        const char* pStageName,
                        bool fullImageViewSwizzle,
                        std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&)> bindBuffer,
                        std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&, MVKArrayRef<const uint32_t>)> bindImplicitBuffer,
                        std::function<void(MVKCommandEncoder*, MVKMTLTextureBinding&)> bindTexture,
                        std::function<void(MVKCommandEncoder*, MVKMTLSamplerStateBinding&)> bindSampler);

	void encodeResourceUsage(MVKShaderStage stage,
							 id<MTLResource> mtlResource,
							 MTLResourceUsage mtlUsage,
							 MTLRenderStages mtlStages) override;

	/** Offset all buffers for vertex attribute bindings with zero divisors by the given number of strides. */
	void offsetZeroDivisorVertexBuffers(MVKGraphicsStage stage, MVKGraphicsPipeline* pipeline, uint32_t firstInstance);

	/**
	 * Marks the buffer binding using the index as having been overridden,
	 * such as by push constants or internal rendering in some transfers.
	 * */
	void markBufferIndexOverridden(MVKShaderStage stage, uint32_t mtlBufferIndex);

	/** Marks any overridden buffer indexes as dirty. */
	void markOverriddenBufferIndexesDirty();

	void endMetalRenderPass() override;

	void markDirty() override;

#pragma mark Construction
    
    /** Constructs this instance for the specified command encoder. */
    MVKGraphicsResourcesCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKResourcesCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;
	void bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) override;

    ResourceBindings<8> _shaderStageResourceBindings[kMVKShaderStageFragment + 1];
	std::unordered_map<id<MTLResource>, MTLRenderStages> _renderUsageStages;
};


#pragma mark -
#pragma mark MVKComputeResourcesCommandEncoderState

/** Holds compute encoder resource state established by bind vertex buffer and descriptor set commands. */
class MVKComputeResourcesCommandEncoderState : public MVKResourcesCommandEncoderState {

public:

	/** Returns the currently bound pipeline for this bind point. */
	MVKPipeline* getPipeline() override;

    /** Binds the specified buffer. */
    void bindBuffer(const MVKMTLBufferBinding& binding);

    /** Binds the specified texture. */
    void bindTexture(const MVKMTLTextureBinding& binding);

    /** Binds the specified sampler state. */
    void bindSamplerState(const MVKMTLSamplerStateBinding& binding);

    /** Sets the current swizzle buffer state. */
    void bindSwizzleBuffer(const MVKShaderImplicitRezBinding& binding, bool needSwizzleBuffer);

    /** Sets the current buffer size buffer state. */
    void bindBufferSizeBuffer(const MVKShaderImplicitRezBinding& binding, bool needSizeBuffer);

	/** Sets the current dynamic offset buffer state. */
	void bindDynamicOffsetBuffer(const MVKShaderImplicitRezBinding& binding, bool needDynamicOffsetBuffer);

	void encodeResourceUsage(MVKShaderStage stage,
							 id<MTLResource> mtlResource,
							 MTLResourceUsage mtlUsage,
							 MTLRenderStages mtlStages) override;

	/**
	 * Marks the buffer binding using the index as having been overridden,
	 * such as by push constants or internal rendering in some transfers.
	 * */
	void markBufferIndexOverridden(uint32_t mtlBufferIndex);

	/** Marks any overridden buffer indexes as dirty. */
	void markOverriddenBufferIndexesDirty();

    void markDirty() override;

#pragma mark Construction

    /** Constructs this instance for the specified command encoder. */
    MVKComputeResourcesCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKResourcesCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t) override;
	void bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) override;

	ResourceBindings<4> _resourceBindings;
};


#pragma mark -
#pragma mark MVKGPUAddressableBuffersCommandEncoderState

/** Tracks whether the GPU-addressable buffers need to be used. */
class MVKGPUAddressableBuffersCommandEncoderState : public MVKCommandEncoderState {

public:

	/** Marks that GPU addressable buffers may be needed in the specified shader stage. */
	void useGPUAddressableBuffersInStage(MVKShaderStage shaderStage);

	MVKGPUAddressableBuffersCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKCommandEncoderState(cmdEncoder) {}

protected:
	void encodeImpl(uint32_t stage) override;

	bool _usageStages[kMVKShaderStageCount] = {};
};


#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

/** Holds encoder state established by occlusion query commands. */
class MVKOcclusionQueryCommandEncoderState : public MVKCommandEncoderState {

public:

	void endMetalRenderPass() override;

    /** Begins an occlusion query. */
    void beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags);

    /** Ends an occlusion query. */
    void endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query);

	MVKOcclusionQueryCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t) override;

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
};


