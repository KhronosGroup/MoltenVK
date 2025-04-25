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

class MVKCommandEncoder;
class MVKGraphicsPipeline;
class MVKDescriptorSet;
class MVKOcclusionQueryPool;

struct MVKShaderImplicitRezBinding;


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
	enum StateScope {
		Static = 0,
		Dynamic,
		Count
	};

	virtual void encodeImpl(uint32_t stage) = 0;
	MVKDevice* getDevice();
	bool isDynamicState(MVKRenderStateType state);
	template <typename T> T& getContent(T* iVarAry, bool isDynamic) {
		return iVarAry[isDynamic ? StateScope::Dynamic : StateScope::Static];
	}
	template <typename T> T& getContent(T* iVarAry, MVKRenderStateType state) {
		return getContent(iVarAry, isDynamicState(state));
	}

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
#pragma mark MVKDepthStencilCommandEncoderState

/** Holds encoder state established by depth stencil commands. */
class MVKDepthStencilCommandEncoderState : public MVKCommandEncoderState {

public:

    /** Sets the depth stencil state during pipeline binding. */
    void setDepthStencilState(const VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo);

	/** Enables or disables depth testing, from explicit dynamic command. */
	void setDepthTestEnable(VkBool32 depthTestEnable);

	/** Enables or disables depth writing, from explicit dynamic command. */
	void setDepthWriteEnable(VkBool32 depthWriteEnable);

	/** Sets the depth compare operation, from explicit dynamic command. */
	void setDepthCompareOp(VkCompareOp depthCompareOp);

	/** Enables or disables stencil testing, from explicit dynamic command. */
	void setStencilTestEnable(VkBool32 stencilTestEnable);

	/** Sets the stencil operations of the indicated faces from explicit dynamic command. */
	void setStencilOp(VkStencilFaceFlags faceMask,
					  VkStencilOp failOp,
					  VkStencilOp passOp,
					  VkStencilOp depthFailOp,
					  VkCompareOp compareOp);

    /** Sets the stencil compare mask value of the indicated faces from explicit dynamic command. */
    void setStencilCompareMask(VkStencilFaceFlags faceMask, uint32_t stencilCompareMask);

    /** Sets the stencil write mask value of the indicated faces from explicit dynamic command. */
    void setStencilWriteMask(VkStencilFaceFlags faceMask, uint32_t stencilWriteMask);

	void beginMetalRenderPass() override;

    /** Constructs this instance for the specified command encoder. */
    MVKDepthStencilCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;
	MVKMTLDepthStencilDescriptorData& getData(MVKRenderStateType state) { return getContent(_depthStencilData, state); }
	template <typename T> void setContent(T& content, T value) {
		if (content != value) {
			content = value;
			markDirty();
		}
	}
	void setStencilState(MVKMTLStencilDescriptorData& sData, const VkStencilOpState& vkStencil);
	void setStencilOp(MVKMTLStencilDescriptorData& sData, VkStencilOp failOp,
					  VkStencilOp passOp, VkStencilOp depthFailOp, VkCompareOp compareOp);

	MVKMTLDepthStencilDescriptorData _depthStencilData[StateScope::Count];
	bool _depthTestEnabled[StateScope::Count] = {};
	bool _hasDepthAttachment = false;
	bool _hasStencilAttachment = false;
};


#pragma mark -
#pragma mark MVKRenderingCommandEncoderState

struct MVKDepthBias {
	float depthBiasConstantFactor;
	float depthBiasClamp;
	float depthBiasSlopeFactor;
};

struct MVKDepthBounds {
	float minDepthBound;
	float maxDepthBound;
};

struct MVKStencilReference {
	uint32_t frontFaceValue;
	uint32_t backFaceValue;
};

struct MVKMTLViewports {
	MTLViewport viewports[kMVKMaxViewportScissorCount];
	uint32_t viewportCount;
};

struct MVKMTLScissors {
	MTLScissorRect scissors[kMVKMaxViewportScissorCount];
	uint32_t scissorCount;
};

/** Holds encoder state established by various rendering state commands. */
class MVKRenderingCommandEncoderState : public MVKCommandEncoderState {
public:
	void setCullMode(VkCullModeFlags cullMode, bool isDynamic);

	void setFrontFace(VkFrontFace frontFace, bool isDynamic);

	void setPolygonMode(VkPolygonMode polygonMode, bool isDynamic);

	void setLineWidth(float lineWidth, bool isDynamic);

	void setBlendConstants(MVKColor32 blendConstants, bool isDynamic);

	void setDepthBias(const VkPipelineRasterizationStateCreateInfo& vkRasterInfo);
	void setDepthBias(MVKDepthBias depthBias, bool isDynamic);
	void setDepthBiasEnable(VkBool32 depthBiasEnable, bool isDynamic);
	void setDepthClipEnable(bool depthClip, bool isDynamic);
	void setDepthBounds(MVKDepthBounds depthBounds, bool isDynamic);
	void setDepthBoundsTestEnable(VkBool32 depthBoundsTestEnable, bool isDynamic);
	void setStencilReferenceValues(const VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo);
	void setStencilReferenceValues(VkStencilFaceFlags faceMask, uint32_t stencilReference);

	void setViewports(const MVKArrayRef<VkViewport> viewports, uint32_t firstViewport, bool isDynamic);
	void setScissors(const MVKArrayRef<VkRect2D> scissors, uint32_t firstScissor, bool isDynamic);

	void setPrimitiveRestartEnable(VkBool32 primitiveRestartEnable, bool isDynamic);

	void setRasterizerDiscardEnable(VkBool32 rasterizerDiscardEnable, bool isDynamic);

	void setPrimitiveTopology(VkPrimitiveTopology topology, bool isDynamic);
	MTLPrimitiveType getPrimitiveType();

	void setPatchControlPoints(uint32_t patchControlPoints, bool isDynamic);
	uint32_t getPatchControlPoints();

	void setSampleLocationsEnable(VkBool32 sampleLocationsEnable, bool isDynamic);
	void setSampleLocations(const MVKArrayRef<VkSampleLocationEXT> sampleLocations, bool isDynamic);
	MVKArrayRef<MTLSamplePosition> getSamplePositions();

	void beginMetalRenderPass() override;
	bool needsMetalRenderPassRestart();

	bool isDirty(MVKRenderStateType state);
	void markDirty() override;

	MVKRenderingCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKCommandEncoderState(cmdEncoder) {}

protected:
	void encodeImpl(uint32_t stage) override;
	bool isDrawingTriangles();
	template <typename T> void setContent(MVKRenderStateType state, T* iVarAry, T* pVal, bool isDynamic) {
		auto* pIVar = &iVarAry[isDynamic ? StateScope::Dynamic : StateScope::Static];
		if( !mvkAreEqual(pVal, pIVar) ) {
			*pIVar = *pVal;
			_dirtyStates.enable(state);
			_modifiedStates.enable(state);
			MVKCommandEncoderState::markDirty();	// Avoid local markDirty() as it marks all states dirty.
		}
	}
	template <typename T> void setContent(MVKRenderStateType state, T* iVarAry, T val, bool isDynamic) {
		setContent(state, iVarAry, &val, isDynamic);
	}

	MVKSmallVector<MTLSamplePosition, kMVKMaxSampleCount> _mtlSampleLocations[StateScope::Count] = {};
	MVKMTLViewports _mtlViewports[StateScope::Count] = {};
	MVKMTLScissors _mtlScissors[StateScope::Count] = {};
	MVKColor32 _mtlBlendConstants[StateScope::Count] = {};
	MVKDepthBias _mtlDepthBias[StateScope::Count] = {};
	MVKDepthBounds _mtlDepthBounds[StateScope::Count] = {};
	MVKStencilReference _mtlStencilReference[StateScope::Count] = {};
	MTLCullMode _mtlCullMode[StateScope::Count] = { MTLCullModeNone, MTLCullModeNone };
	MTLWinding _mtlFrontFace[StateScope::Count] = { MTLWindingClockwise, MTLWindingClockwise };
	MTLPrimitiveType _mtlPrimitiveTopology[StateScope::Count] = { MTLPrimitiveTypePoint, MTLPrimitiveTypePoint };
	MTLDepthClipMode _mtlDepthClipEnable[StateScope::Count] = { MTLDepthClipModeClip, MTLDepthClipModeClip };
	MTLTriangleFillMode _mtlPolygonMode[StateScope::Count] = { MTLTriangleFillModeFill, MTLTriangleFillModeFill };
	float _mtlLineWidth[StateScope::Count] = { 1, 1 };
	uint32_t _mtlPatchControlPoints[StateScope::Count] = { 0, 0 };
	MVKRenderStateFlags _dirtyStates;
	MVKRenderStateFlags _modifiedStates;
	bool _mtlSampleLocationsEnable[StateScope::Count] = {};
	bool _mtlDepthBiasEnable[StateScope::Count] = {};
	bool _mtlPrimitiveRestartEnable[StateScope::Count] = {};
	bool _mtlRasterizerDiscardEnable[StateScope::Count] = {};
	bool _mtlDepthBoundsTestEnable[StateScope::Count] = {};
	bool _cullBothFaces[StateScope::Count] = {};
	bool _isPolygonModePoint[StateScope::Count] = {};
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


