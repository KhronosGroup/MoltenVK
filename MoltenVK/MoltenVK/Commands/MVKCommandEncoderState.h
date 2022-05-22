/*
 * MVKCommandEncoderState.h
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
     * will be encoded to Metal, otherwise it is marked as clean, so the contents will NOT
     * be encoded. Default state can be left unencoded on a new Metal encoder.
     */
	virtual void beginMetalRenderPass() { if (_isModified) { markDirty(); } }

	/** Called automatically when a Metal render pass ends. */
	virtual void endMetalRenderPass() { }

	/**
	 * Called automatically when a Metal compute pass begins. If the contents have been
	 * modified from the default values, this instance is marked as dirty, so the contents
	 * will be encoded to Metal, otherwise it is marked as clean, so the contents will NOT
	 * be encoded. Default state can be left unencoded on a new Metal encoder.
	 */
	virtual void beginMetalComputeEncoding() { if (_isModified) { markDirty(); } }

    /**
     * If the content of this instance is dirty, marks this instance as no longer dirty
     * and calls the encodeImpl() function to encode the content onto the Metal encoder.
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

/** Holds encoder state established by pipeline commands. */
class MVKPipelineCommandEncoderState : public MVKCommandEncoderState {

public:

	/** Binds the pipeline. */
    void bindPipeline(MVKPipeline* pipeline);

    /** Returns the currently bound pipeline. */
    MVKPipeline* getPipeline();

    /** Constructs this instance for the specified command encoder. */
    MVKPipelineCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;

    MVKPipeline* _pipeline = nullptr;
};


#pragma mark -
#pragma mark MVKViewportCommandEncoderState

/** Holds encoder state established by viewport commands. */
class MVKViewportCommandEncoderState : public MVKCommandEncoderState {

public:

	/**
	 * Sets one or more of the viewports, starting at the first index.
	 * The isSettingDynamically indicates that the scissor is being changed dynamically,
	 * which is only allowed if the pipeline was created as VK_DYNAMIC_STATE_SCISSOR.
	 */
	void setViewports(const MVKArrayRef<VkViewport> viewports,
					  uint32_t firstViewport,
					  bool isSettingDynamically);

    /** Constructs this instance for the specified command encoder. */
    MVKViewportCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;

    MVKSmallVector<VkViewport, kMVKCachedViewportScissorCount> _viewports, _dynamicViewports;
};


#pragma mark -
#pragma mark MVKScissorCommandEncoderState

/** Holds encoder state established by viewport commands. */
class MVKScissorCommandEncoderState : public MVKCommandEncoderState {

public:

	/**
	 * Sets one or more of the scissors, starting at the first index.
	 * The isSettingDynamically indicates that the scissor is being changed dynamically,
	 * which is only allowed if the pipeline was created as VK_DYNAMIC_STATE_SCISSOR.
	 */
	void setScissors(const MVKArrayRef<VkRect2D> scissors,
					 uint32_t firstScissor,
					 bool isSettingDynamically);

    /** Constructs this instance for the specified command encoder. */
    MVKScissorCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;

    MVKSmallVector<VkRect2D, kMVKCachedViewportScissorCount> _scissors, _dynamicScissors;
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

    /** Constructs this instance for the specified command encoder. */
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

    /** 
     * Sets the stencil compare mask value of the indicated faces
     * to the specified value, from explicit dynamic command.
     */
    void setStencilCompareMask(VkStencilFaceFlags faceMask, uint32_t stencilCompareMask);

    /**
     * Sets the stencil write mask value of the indicated faces
     * to the specified value, from explicit dynamic command.
     */
    void setStencilWriteMask(VkStencilFaceFlags faceMask, uint32_t stencilWriteMask);

	void beginMetalRenderPass() override;

    /** Constructs this instance for the specified command encoder. */
    MVKDepthStencilCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;
    void setStencilState(MVKMTLStencilDescriptorData& stencilInfo,
                         const VkStencilOpState& vkStencil,
                         bool enabled);

    MVKMTLDepthStencilDescriptorData _depthStencilData = kMVKMTLDepthStencilDescriptorDataDefault;
	bool _hasDepthAttachment = false;
	bool _hasStencilAttachment = false;
};


#pragma mark -
#pragma mark MVKStencilReferenceValueCommandEncoderState

/** Holds encoder state established by stencil reference values commands. */
class MVKStencilReferenceValueCommandEncoderState : public MVKCommandEncoderState {

public:

    /** Sets the stencil references during pipeline binding. */
    void setReferenceValues(const VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo);

    /** Sets the stencil state from explicit dynamic command. */
    void setReferenceValues(VkStencilFaceFlags faceMask, uint32_t stencilReference);

    /** Constructs this instance for the specified command encoder. */
    MVKStencilReferenceValueCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;

    uint32_t _frontFaceValue = 0;
    uint32_t _backFaceValue = 0;
};


#pragma mark -
#pragma mark MVKDepthBiasCommandEncoderState

/** Holds encoder state established by depth bias commands. */
class MVKDepthBiasCommandEncoderState : public MVKCommandEncoderState {

public:

    /** Sets the depth bias during pipeline binding. */
    void setDepthBias(const VkPipelineRasterizationStateCreateInfo& vkRasterInfo);

    /** Sets the depth bias dynamically. */
    void setDepthBias(float depthBiasConstantFactor,
                      float depthBiasSlopeFactor,
                      float depthBiasClamp);

    /** Constructs this instance for the specified command encoder. */
    MVKDepthBiasCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;

    float _depthBiasConstantFactor = 0;
    float _depthBiasClamp = 0;
    float _depthBiasSlopeFactor = 0;
    bool _isEnabled = false;
};


#pragma mark -
#pragma mark MVKBlendColorCommandEncoderState

/** Holds encoder state established by blend color commands. */
class MVKBlendColorCommandEncoderState : public MVKCommandEncoderState {

public:

    /** Sets the blend color, either as part of pipeline binding, or dynamically. */
    void setBlendColor(float red, float green,
                       float blue, float alpha,
                       bool isDynamic);

    /** Constructs this instance for the specified command encoder. */
    MVKBlendColorCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;

    float _red = 0;
    float _green = 0;
    float _blue = 0;
    float _alpha = 0;
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

	/** Encodes the Metal resource to the Metal command encoder. */
	virtual void encodeArgumentBufferResourceUsage(MVKShaderStage stage,
												   id<MTLResource> mtlResource,
												   MTLResourceUsage mtlUsage,
												   MTLRenderStages mtlStages) = 0;

    MVKResourcesCommandEncoderState(MVKCommandEncoder* cmdEncoder) :
		MVKCommandEncoderState(cmdEncoder), _boundDescriptorSets{} {}

protected:
	void markDirty() override;

    // Template function that marks both the vector and all binding elements in the vector as dirty.
    template<class T>
    void markDirty(T& bindings, bool& bindingsDirtyFlag) {
        for (auto& b : bindings) { b.isDirty = true; }
        bindingsDirtyFlag = true;
    }

    // Template function that updates an existing binding or adds a new binding to a vector
    // of bindings, and marks the binding, the vector, and this instance as dirty
    template<class T, class V>
    void bind(const T& b, V& bindings, bool& bindingsDirtyFlag) {

        if ( !b.mtlResource ) { return; }

        T db = b;   // Copy that can be marked dirty
        MVKCommandEncoderState::markDirty();
        bindingsDirtyFlag = true;
        db.isDirty = true;

        for (auto iter = bindings.begin(), end = bindings.end(); iter != end; ++iter) {
            if( iter->index == db.index ) {
                *iter = db;
                return;
            }
        }
        bindings.push_back(db);
    }

	// For texture bindings, we also keep track of whether any bindings need a texture swizzle
	template<class V>
	void bind(const MVKMTLTextureBinding& tb, V& texBindings, bool& bindingsDirtyFlag, bool& needsSwizzleFlag) {
		bind(tb, texBindings, bindingsDirtyFlag);
		if (tb.swizzle != 0) { needsSwizzleFlag = true; }
	}

    // Template function that executes a lambda expression on each dirty element of
    // a vector of bindings, and marks the bindings and the vector as no longer dirty.
	// Clear isDirty flag before operation to allow operation to possibly override.
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
					if (b.isDirty) { bindingsDirtyFlag = true; }
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

	void assertMissingSwizzles(bool needsSwizzle, const char* stageName, const MVKArrayRef<MVKMTLTextureBinding> texBindings);
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
                        std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&, const MVKArrayRef<uint32_t>)> bindImplicitBuffer,
                        std::function<void(MVKCommandEncoder*, MVKMTLTextureBinding&)> bindTexture,
                        std::function<void(MVKCommandEncoder*, MVKMTLSamplerStateBinding&)> bindSampler);

	void encodeArgumentBufferResourceUsage(MVKShaderStage stage,
										   id<MTLResource> mtlResource,
										   MTLResourceUsage mtlUsage,
										   MTLRenderStages mtlStages) override;

	/** Offset all buffers for vertex attribute bindings with zero divisors by the given number of strides. */
	void offsetZeroDivisorVertexBuffers(MVKGraphicsStage stage, MVKGraphicsPipeline* pipeline, uint32_t firstInstance);

#pragma mark Construction
    
    /** Constructs this instance for the specified command encoder. */
    MVKGraphicsResourcesCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKResourcesCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl(uint32_t stage) override;
    void markDirty() override;
	void bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) override;

    ResourceBindings<8> _shaderStageResourceBindings[4];
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

	void encodeArgumentBufferResourceUsage(MVKShaderStage stage,
										   id<MTLResource> mtlResource,
										   MTLResourceUsage mtlUsage,
										   MTLRenderStages mtlStages) override;

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
};


