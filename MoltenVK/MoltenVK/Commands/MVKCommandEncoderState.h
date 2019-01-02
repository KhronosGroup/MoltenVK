/*
 * MVKCommandEncoderState.h
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKVector.h"

class MVKCommandEncoder;
class MVKOcclusionQueryPool;

struct MVKShaderAuxBufferBinding;


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
    void beginMetalRenderPass() { if (_isModified) { markDirty(); } }

    /**
     * If the content of this instance is dirty, marks this instance as no longer dirty
     * and calls the encodeImpl() function to encode the content onto the Metal encoder.
     * Subclasses must override the encodeImpl() function to do the actual work.
     */
    void encode() {
        if ( !_isDirty ) { return; }

        _isDirty = false;
        encodeImpl();
    }

    /**
     * Marks this instance as dirty and calls resetImpl() function to reset this instance
     * back to initial state. Subclasses must override the resetImpl() function.
     */
    void reset() {
        _isDirty = true;
        _isModified = false;

        resetImpl();
    }

	/** Constructs this instance for the specified command encoder. */
    MVKCommandEncoderState(MVKCommandEncoder* cmdEncoder) : _cmdEncoder(cmdEncoder) {}

protected:
    virtual void encodeImpl() = 0;
    virtual void resetImpl() = 0;

    MVKCommandEncoder* _cmdEncoder;
	bool _isDirty = false;
    bool _isModified = false;
};


#pragma mark -
#pragma mark MVKPipelineCommandEncoderState

/** Holds encoder state established by pipeline commands. */
class MVKPipelineCommandEncoderState : public MVKCommandEncoderState {

public:

    /** Sets the pipeline during pipeline binding. */
    void setPipeline(MVKPipeline* pipeline);

    /** Returns the currently bound pipeline. */
    MVKPipeline* getPipeline();

    /** Constructs this instance for the specified command encoder. */
    MVKPipelineCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl() override;
    void resetImpl() override;

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
	void setViewports(const MVKVector<MTLViewport> &mtlViewports,
					  uint32_t firstViewport,
					  bool isSettingDynamically);

    /** Constructs this instance for the specified command encoder. */
    MVKViewportCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl() override;
    void resetImpl() override;

    MVKVector<MTLViewport> _mtlViewports;
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
	void setScissors(const MVKVector<MTLScissorRect> &mtlScissors,
					 uint32_t firstScissor,
					 bool isSettingDynamically);

    /** Constructs this instance for the specified command encoder. */
    MVKScissorCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl() override;
    void resetImpl() override;

    MVKVector<MTLScissorRect> _mtlScissors;
};


#pragma mark -
#pragma mark MVKPushConstantsCommandEncoderState

/** Holds encoder state established by push constant commands for a single shader stage. */
class MVKPushConstantsCommandEncoderState : public MVKCommandEncoderState {

public:

    /** Sets the specified push constants. */
    void setPushConstants(uint32_t offset, MVKVector<char>& pushConstants);

    /** Sets the index of the Metal buffer used to hold the push constants. */
    void setMTLBufferIndex(uint32_t mtlBufferIndex);

    /** Constructs this instance for the specified command encoder. */
    MVKPushConstantsCommandEncoderState(MVKCommandEncoder* cmdEncoder,
                                        VkShaderStageFlagBits shaderStage)
        : MVKCommandEncoderState(cmdEncoder), _shaderStage(shaderStage) {}

protected:
    void encodeImpl() override;
    void resetImpl() override;

    MVKVector<char> _pushConstants;
    VkShaderStageFlagBits _shaderStage;
    uint32_t _mtlBufferIndex = 0;
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

    /** Constructs this instance for the specified command encoder. */
    MVKDepthStencilCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl() override;
    void resetImpl() override;
    void setStencilState(MVKMTLStencilDescriptorData& stencilInfo,
                         const VkStencilOpState& vkStencil,
                         bool enabled);

    MVKMTLDepthStencilDescriptorData _depthStencilData;
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
    void encodeImpl() override;
    void resetImpl() override;

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
    void encodeImpl() override;
    void resetImpl() override;

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
    void encodeImpl() override;
    void resetImpl() override;

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

    /** Constructs this instance for the specified command encoder. */
    MVKResourcesCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKCommandEncoderState(cmdEncoder) {}

protected:

    // Template function that marks both the vector and all binding elements in the vector as dirty.
    template<class T>
    void markDirty(T& bindings, bool& bindingsDirtyFlag) {
        for (auto& b : bindings) { b.isDirty = true; }
        bindingsDirtyFlag = true;
    }

    // Template function that updates an existing binding or adds a new binding to a vector
    // of bindings, and marks the binding, the vector, and this instance as dirty
    template<class T, class U>
    void bind(const T& b, U& bindings, bool& bindingsDirtyFlag) {

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

    // Template function that executes a lambda expression on each dirty element of
    // a vector of bindings, and marks the bindings and the vector as no longer dirty.
    template<class T>
    void encodeBinding(MVKVector<T>& bindings,
                       bool& bindingsDirtyFlag,
                       std::function<void(MVKCommandEncoder* cmdEncoder, T& b)> mtlOperation) {
        if (bindingsDirtyFlag) {
            bindingsDirtyFlag = false;
            for (auto& b : bindings) {
                if (b.isDirty) {
                    mtlOperation(_cmdEncoder, b);
                    b.isDirty = false;
                }
            }
        }
    }

    // Updates the swizzle for an image in the given vector.
    void updateSwizzle(MVKVector<uint32_t> &constants, uint32_t index, uint32_t swizzle) {
        if (index >= constants.size()) { constants.resize(index + 1); }
        constants[index] = swizzle;
    }
};


#pragma mark -
#pragma mark MVKGraphicsResourcesCommandEncoderState

/** Holds graphics encoder resource state established by bind vertex buffer and descriptor set commands. */
class MVKGraphicsResourcesCommandEncoderState : public MVKResourcesCommandEncoderState {

public:

    /** Binds the specified vertex buffer. */
    void bindVertexBuffer(const MVKMTLBufferBinding& binding);

    /** Binds the specified fragment buffer. */
    void bindFragmentBuffer(const MVKMTLBufferBinding& binding);

    /** Binds the specified vertex texture. */
    void bindVertexTexture(const MVKMTLTextureBinding& binding);

    /** Binds the specified fragment texture. */
    void bindFragmentTexture(const MVKMTLTextureBinding& binding);

    /** Binds the specified vertex sampler state. */
    void bindVertexSamplerState(const MVKMTLSamplerStateBinding& binding);

    /** Binds the specified fragment sampler state. */
    void bindFragmentSamplerState(const MVKMTLSamplerStateBinding& binding);

    /** The type of index that will be used to render primitives. Exposed directly. */
    MVKIndexMTLBufferBinding _mtlIndexBufferBinding;

    /** Binds the specified index buffer. */
    void bindIndexBuffer(const MVKIndexMTLBufferBinding& binding) {
        _mtlIndexBufferBinding = binding;   // No need to track dirty state
    }

    /** Sets the current auxiliary buffer state. */
    void bindAuxBuffer(const MVKShaderAuxBufferBinding& binding, bool needVertexAuxBuffer, bool needFragmentAuxBuffer);


#pragma mark Construction
    
    /** Constructs this instance for the specified command encoder. */
    MVKGraphicsResourcesCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKResourcesCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl() override;
    void resetImpl() override;
    void markDirty() override;

    MVKVector<MVKMTLBufferBinding> _vertexBufferBindings;
    MVKVector<MVKMTLBufferBinding> _fragmentBufferBindings;
    MVKVector<MVKMTLTextureBinding> _vertexTextureBindings;
    MVKVector<MVKMTLTextureBinding> _fragmentTextureBindings;
    MVKVector<MVKMTLSamplerStateBinding> _vertexSamplerStateBindings;
    MVKVector<MVKMTLSamplerStateBinding> _fragmentSamplerStateBindings;
    MVKVector<uint32_t> _vertexSwizzleConstants;
    MVKVector<uint32_t> _fragmentSwizzleConstants;
    MVKMTLBufferBinding _vertexAuxBufferBinding;
    MVKMTLBufferBinding _fragmentAuxBufferBinding;

    bool _areVertexBufferBindingsDirty = false;
    bool _areFragmentBufferBindingsDirty = false;
    bool _areVertexTextureBindingsDirty = false;
    bool _areFragmentTextureBindingsDirty = false;
    bool _areVertexSamplerStateBindingsDirty = false;
    bool _areFragmentSamplerStateBindingsDirty = false;
};


#pragma mark -
#pragma mark MVKComputeResourcesCommandEncoderState

/** Holds compute encoder resource state established by bind vertex buffer and descriptor set commands. */
class MVKComputeResourcesCommandEncoderState : public MVKResourcesCommandEncoderState {

public:

    /** Binds the specified buffer. */
    void bindBuffer(const MVKMTLBufferBinding& binding);

    /** Binds the specified texture. */
    void bindTexture(const MVKMTLTextureBinding& binding);

    /** Binds the specified sampler state. */
    void bindSamplerState(const MVKMTLSamplerStateBinding& binding);

    /** Sets the current auxiliary buffer state. */
    void bindAuxBuffer(const MVKShaderAuxBufferBinding& binding);

#pragma mark Construction

    /** Constructs this instance for the specified command encoder. */
    MVKComputeResourcesCommandEncoderState(MVKCommandEncoder* cmdEncoder) : MVKResourcesCommandEncoderState(cmdEncoder) {}

protected:
    void encodeImpl() override;
    void resetImpl() override;
    void markDirty() override;

    MVKVector<MVKMTLBufferBinding> _bufferBindings;
    MVKVector<MVKMTLTextureBinding> _textureBindings;
    MVKVector<MVKMTLSamplerStateBinding> _samplerStateBindings;
    MVKVector<uint32_t> _swizzleConstants;
    MVKMTLBufferBinding _auxBufferBinding;

    bool _areBufferBindingsDirty = false;
    bool _areTextureBindingsDirty = false;
    bool _areSamplerStateBindingsDirty = false;
};


#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

/** Holds encoder state established by occlusion query commands. */
class MVKOcclusionQueryCommandEncoderState : public MVKCommandEncoderState {

public:

    /** Begins an occlusion query. */
    void beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags);

    /** Ends an occlusion query. */
    void endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query);

    /** Returns the MTLBuffer used to hold occlusion query results. */
    id<MTLBuffer> getVisibilityResultMTLBuffer();

    /** Constructs this instance for the specified command encoder. */
    MVKOcclusionQueryCommandEncoderState(MVKCommandEncoder* cmdEncoder);

protected:
    void encodeImpl() override;
    void resetImpl() override;

    id<MTLBuffer> _visibilityResultMTLBuffer = nil;
    MTLVisibilityResultMode _mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
    NSUInteger _mtlVisibilityResultOffset = 0;
};


