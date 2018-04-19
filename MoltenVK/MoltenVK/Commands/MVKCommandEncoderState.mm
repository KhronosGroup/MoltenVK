/*
 * MVKCommandEncoderState.mm
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKRenderPass.h"
#include "MVKPipeline.h"
#include "MVKQueryPool.h"
#include "MVKLogging.h"
#include "mvk_datatypes.h"

using namespace std;


#pragma mark -
#pragma mark MVKPipelineCommandEncoderState

void MVKPipelineCommandEncoderState::setPipeline(MVKPipeline* pipeline) {
    _pipeline = pipeline;
    markDirty();
}

MVKPipeline* MVKPipelineCommandEncoderState::getPipeline() { return _pipeline; }

void MVKPipelineCommandEncoderState::encodeImpl() {
    if (_pipeline) { _pipeline->encode(_cmdEncoder); }
}

void MVKPipelineCommandEncoderState::resetImpl() {
    _pipeline = nullptr;
}


#pragma mark -
#pragma mark MVKViewportCommandEncoderState

void MVKViewportCommandEncoderState::setViewports(vector<MTLViewport> mtlViewports,
												  uint32_t firstViewport,
												  bool isSettingDynamically) {

	bool mustSetDynamically = _cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_VIEWPORT);

	if ((mustSetDynamically == isSettingDynamically) &&
		(firstViewport < mtlViewports.size()) &&
		(firstViewport == 0)) {

		_mtlViewport = mtlViewports[firstViewport];
		markDirty();
	}
}

void MVKViewportCommandEncoderState::encodeImpl() {
    [_cmdEncoder->_mtlRenderEncoder setViewport: _mtlViewport];
}

void MVKViewportCommandEncoderState::resetImpl() {
    _mtlViewport =  { 0, 0, 0, 0, 0, 0 };
}


#pragma mark -
#pragma mark MVKScissorCommandEncoderState

void MVKScissorCommandEncoderState::setScissors(vector<MTLScissorRect> mtlScissors,
                                                uint32_t firstScissor,
												bool isSettingDynamically) {

	bool mustSetDynamically = _cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_SCISSOR);

	if ((mustSetDynamically == isSettingDynamically) &&
		(firstScissor < mtlScissors.size()) &&
		(firstScissor == 0)) {

		_mtlScissor = mtlScissors[firstScissor];
		markDirty();
	}
}

void MVKScissorCommandEncoderState::encodeImpl() {
	[_cmdEncoder->_mtlRenderEncoder setScissorRect: _cmdEncoder->clipToRenderArea(_mtlScissor)];
}

void MVKScissorCommandEncoderState::resetImpl() {
    _mtlScissor =  { 0, 0, 0, 0 };
}


#pragma mark -
#pragma mark MVKPushConstantsCommandEncoderState

void MVKPushConstantsCommandEncoderState:: setPushConstants(uint32_t offset, vector<char>& pushConstants) {
    uint32_t pcCnt = (uint32_t)pushConstants.size();
    mvkEnsureSize(_pushConstants, offset + pcCnt);
    copy(pushConstants.begin(), pushConstants.end(), _pushConstants.begin() + offset);
    if (pcCnt > 0) { markDirty(); }
}

void MVKPushConstantsCommandEncoderState::setMTLBufferIndex(uint32_t mtlBufferIndex) {
    if (mtlBufferIndex != _mtlBufferIndex) {
        _mtlBufferIndex = mtlBufferIndex;
        markDirty();
    }
}

void MVKPushConstantsCommandEncoderState::encodeImpl() {
    if (_pushConstants.empty() ) { return; }

    switch (_shaderStage) {
        case VK_SHADER_STAGE_VERTEX_BIT:
            _cmdEncoder->setVertexBytes(_cmdEncoder->_mtlRenderEncoder,
                                        _pushConstants.data(),
                                        _pushConstants.size(),
                                        _mtlBufferIndex);
            break;
        case VK_SHADER_STAGE_FRAGMENT_BIT:
            _cmdEncoder->setFragmentBytes(_cmdEncoder->_mtlRenderEncoder,
                                          _pushConstants.data(),
                                          _pushConstants.size(),
                                          _mtlBufferIndex);
            break;
        case VK_SHADER_STAGE_COMPUTE_BIT:
            _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                         _pushConstants.data(),
                                         _pushConstants.size(),
                                         _mtlBufferIndex);
            break;
        default:
            MVKAssert(false, "Unsupported shader stage: %d", _shaderStage);
            break;
    }
}

void MVKPushConstantsCommandEncoderState::resetImpl() {
    _pushConstants.clear();
}


#pragma mark -
#pragma mark MVKDepthStencilCommandEncoderState

void MVKDepthStencilCommandEncoderState:: setDepthStencilState(VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo) {

    if (vkDepthStencilInfo.depthTestEnable) {
        _depthStencilData.depthCompareFunction = mvkMTLCompareFunctionFromVkCompareOp(vkDepthStencilInfo.depthCompareOp);
        _depthStencilData.depthWriteEnabled = vkDepthStencilInfo.depthWriteEnable;
    } else {
        _depthStencilData.depthCompareFunction = kMVKMTLDepthStencilDescriptorDataDefault.depthCompareFunction;
        _depthStencilData.depthWriteEnabled = kMVKMTLDepthStencilDescriptorDataDefault.depthWriteEnabled;
    }

    setStencilState(_depthStencilData.frontFaceStencilData, vkDepthStencilInfo.front, vkDepthStencilInfo.stencilTestEnable);
    setStencilState(_depthStencilData.backFaceStencilData, vkDepthStencilInfo.back, vkDepthStencilInfo.stencilTestEnable);

    markDirty();
}

void MVKDepthStencilCommandEncoderState::setStencilState(MVKMTLStencilDescriptorData& stencilInfo,
                                                         VkStencilOpState& vkStencil,
                                                         bool enabled) {
    if ( !enabled ) {
        stencilInfo = kMVKMTLStencilDescriptorDataDefault;
        return;
    }

    stencilInfo.enabled = true;
    stencilInfo.stencilCompareFunction = mvkMTLCompareFunctionFromVkCompareOp(vkStencil.compareOp);
    stencilInfo.stencilFailureOperation = mvkMTLStencilOperationFromVkStencilOp(vkStencil.failOp);
    stencilInfo.depthFailureOperation = mvkMTLStencilOperationFromVkStencilOp(vkStencil.depthFailOp);
    stencilInfo.depthStencilPassOperation = mvkMTLStencilOperationFromVkStencilOp(vkStencil.passOp);

    bool useCompareMask = !_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK);
    if (useCompareMask) { stencilInfo.readMask = vkStencil.compareMask; }

    bool useWriteMask = !_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_WRITE_MASK);
    if (useWriteMask) { stencilInfo.writeMask = vkStencil.writeMask; }
}

void MVKDepthStencilCommandEncoderState::setStencilCompareMask(VkStencilFaceFlags faceMask,
                                                               uint32_t stencilCompareMask) {

    // If we can't set the state, or nothing is being set, just leave
    if ( !(_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK) &&
           mvkIsAnyFlagEnabled(faceMask, VK_STENCIL_FRONT_AND_BACK)) ) { return; }

    if (mvkAreFlagsEnabled(faceMask, VK_STENCIL_FACE_FRONT_BIT)) {
        _depthStencilData.frontFaceStencilData.readMask = stencilCompareMask;
    }
    if (mvkAreFlagsEnabled(faceMask, VK_STENCIL_FACE_BACK_BIT)) {
        _depthStencilData.backFaceStencilData.readMask = stencilCompareMask;
    }

    markDirty();
}

void MVKDepthStencilCommandEncoderState::setStencilWriteMask(VkStencilFaceFlags faceMask,
                                                             uint32_t stencilWriteMask) {

    // If we can't set the state, or nothing is being set, just leave
    if ( !(_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_WRITE_MASK) &&
           mvkIsAnyFlagEnabled(faceMask, VK_STENCIL_FRONT_AND_BACK)) ) { return; }

    if (mvkAreFlagsEnabled(faceMask, VK_STENCIL_FACE_FRONT_BIT)) {
        _depthStencilData.frontFaceStencilData.writeMask = stencilWriteMask;
    }
    if (mvkAreFlagsEnabled(faceMask, VK_STENCIL_FACE_BACK_BIT)) {
        _depthStencilData.backFaceStencilData.writeMask = stencilWriteMask;
    }

    markDirty();
}

void MVKDepthStencilCommandEncoderState::encodeImpl() {
    MVKRenderSubpass *subpass = _cmdEncoder->getSubpass();
    id<MTLDepthStencilState> mtlDSS = nil;
    if (subpass->getDepthStencilFormat() != VK_FORMAT_UNDEFINED) {
        mtlDSS = _cmdEncoder->getCommandEncodingPool()->getMTLDepthStencilState(_depthStencilData);
    } else {
        // If there is no depth attachment but the depth/stencil state contains a non-always depth
        // test, Metal Validation will give the following error:
        // "validateDepthStencilState:3657: failed assertion `MTLDepthStencilDescriptor sets
        //  depth test but MTLRenderPassDescriptor has a nil depthAttachment texture'"
        // Check the subpass to see if there is a depth/stencil attachment, and if not use
        // a depth/stencil state with depth test always, depth write disabled, and no stencil state.
        mtlDSS = _cmdEncoder->getCommandEncodingPool()->getMTLDepthStencilState(false, false);
    }
    [_cmdEncoder->_mtlRenderEncoder setDepthStencilState: mtlDSS];
}

void MVKDepthStencilCommandEncoderState::resetImpl() {
    _depthStencilData = kMVKMTLDepthStencilDescriptorDataDefault;
}


#pragma mark -
#pragma mark MVKStencilReferenceValueCommandEncoderState

void MVKStencilReferenceValueCommandEncoderState:: setReferenceValues(VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo) {

    // If ref values are to be set dynamically, don't set them here.
    if (_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_REFERENCE)) { return; }

    _frontFaceValue = vkDepthStencilInfo.front.reference;
    _backFaceValue = vkDepthStencilInfo.back.reference;
    markDirty();
}

void MVKStencilReferenceValueCommandEncoderState::setReferenceValues(VkStencilFaceFlags faceMask,
                                                                     uint32_t stencilReference) {

    // If we can't set the state, or nothing is being set, just leave
    if ( !(_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_REFERENCE) &&
           mvkIsAnyFlagEnabled(faceMask, VK_STENCIL_FRONT_AND_BACK)) ) { return; }

    if (mvkAreFlagsEnabled(faceMask, VK_STENCIL_FACE_FRONT_BIT)) {
        _frontFaceValue = stencilReference;
    }
    if (mvkAreFlagsEnabled(faceMask, VK_STENCIL_FACE_BACK_BIT)) {
        _backFaceValue = stencilReference;
    }

    markDirty();
}

void MVKStencilReferenceValueCommandEncoderState::encodeImpl() {
    [_cmdEncoder->_mtlRenderEncoder setStencilFrontReferenceValue: _frontFaceValue
                                               backReferenceValue: _backFaceValue];
}

void MVKStencilReferenceValueCommandEncoderState::resetImpl() {
    _frontFaceValue = 0;
    _backFaceValue = 0;
}


#pragma mark -
#pragma mark MVKDepthBiasCommandEncoderState

void MVKDepthBiasCommandEncoderState::setDepthBias(VkPipelineRasterizationStateCreateInfo vkRasterInfo) {

    _isEnabled = vkRasterInfo.depthBiasEnable;

    // If ref values are to be set dynamically, don't set them here.
    if (_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_DEPTH_BIAS)) { return; }

    _depthBiasConstantFactor = vkRasterInfo.depthBiasConstantFactor;
    _depthBiasSlopeFactor = vkRasterInfo.depthBiasSlopeFactor;
    _depthBiasClamp = vkRasterInfo.depthBiasClamp;

    markDirty();
}

void MVKDepthBiasCommandEncoderState::setDepthBias(float depthBiasConstantFactor,
                                                   float depthBiasSlopeFactor,
                                                   float depthBiasClamp) {

    if ( !_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_DEPTH_BIAS) ) { return; }

    _depthBiasConstantFactor = depthBiasConstantFactor;
    _depthBiasSlopeFactor = depthBiasSlopeFactor;
    _depthBiasClamp = depthBiasClamp;

    markDirty();
}

void MVKDepthBiasCommandEncoderState::encodeImpl() {
    if (_isEnabled) {
        [_cmdEncoder->_mtlRenderEncoder setDepthBias: _depthBiasConstantFactor
                                          slopeScale: _depthBiasSlopeFactor
                                               clamp: _depthBiasClamp];
    } else {
        [_cmdEncoder->_mtlRenderEncoder setDepthBias: 0 slopeScale: 0 clamp: 0];
    }
}

void MVKDepthBiasCommandEncoderState::resetImpl() {
    _depthBiasConstantFactor = 0;
    _depthBiasClamp = 0;
    _depthBiasSlopeFactor = 0;
    _isEnabled = false;
}


#pragma mark -
#pragma mark MVKBlendColorCommandEncoderState

void MVKBlendColorCommandEncoderState::setBlendColor(float red, float green,
                                                     float blue, float alpha,
                                                     bool isDynamic) {

    // Abort if dynamic allowed but call is not dynamic, or vice-versa
    if ( !(_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_BLEND_CONSTANTS) == isDynamic) ) { return; }

    _red = red;
    _green = green;
    _blue = blue;
    _alpha = alpha;

    markDirty();
}

void MVKBlendColorCommandEncoderState::encodeImpl() {
    [_cmdEncoder->_mtlRenderEncoder setBlendColorRed: _red green: _green blue: _blue alpha: _alpha];
}

void MVKBlendColorCommandEncoderState::resetImpl() {
    _red = 0;
    _green = 0;
    _blue = 0;
    _alpha = 0;
}


#pragma mark -
#pragma mark MVKGraphicsResourcesCommandEncoderState

void MVKGraphicsResourcesCommandEncoderState::bindVertexBuffer(const MVKMTLBufferBinding& binding) {
    bind(binding, _vertexBufferBindings, _areVertexBufferBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindFragmentBuffer(const MVKMTLBufferBinding& binding) {
    bind(binding, _fragmentBufferBindings, _areFragmentBufferBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindVertexTexture(const MVKMTLTextureBinding& binding) {
    bind(binding, _vertexTextureBindings, _areVertexTextureBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindFragmentTexture(const MVKMTLTextureBinding& binding) {
    bind(binding, _fragmentTextureBindings, _areFragmentTextureBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindVertexSamplerState(const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _vertexSamplerStateBindings, _areVertexSamplerStateBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindFragmentSamplerState(const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _fragmentSamplerStateBindings, _areFragmentSamplerStateBindingsDirty);
}

// Mark everything as dirty
void MVKGraphicsResourcesCommandEncoderState::markDirty() {
    MVKCommandEncoderState::markDirty();
    MVKResourcesCommandEncoderState::markDirty(_vertexBufferBindings, _areVertexBufferBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_fragmentBufferBindings, _areFragmentBufferBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_vertexTextureBindings, _areVertexTextureBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_fragmentTextureBindings, _areFragmentTextureBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_vertexSamplerStateBindings, _areVertexSamplerStateBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_fragmentSamplerStateBindings, _areFragmentSamplerStateBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::encodeImpl() {

    encodeBinding<MVKMTLBufferBinding>(_vertexBufferBindings, _areVertexBufferBindingsDirty,
                                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                                           [cmdEncoder->_mtlRenderEncoder setVertexBuffer: b.mtlBuffer
                                                                                   offset: b.offset
                                                                                  atIndex: b.index];
                                       });

    encodeBinding<MVKMTLBufferBinding>(_fragmentBufferBindings, _areFragmentBufferBindingsDirty,
                                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                                           [cmdEncoder->_mtlRenderEncoder setFragmentBuffer: b.mtlBuffer
                                                                                     offset: b.offset
                                                                                    atIndex: b.index];
                                       });

    encodeBinding<MVKMTLTextureBinding>(_vertexTextureBindings, _areVertexTextureBindingsDirty,
                                        [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                                            [cmdEncoder->_mtlRenderEncoder setVertexTexture: b.mtlTexture
                                                                                    atIndex: b.index];
                                        });

    encodeBinding<MVKMTLTextureBinding>(_fragmentTextureBindings, _areFragmentTextureBindingsDirty,
                                        [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                                            [cmdEncoder->_mtlRenderEncoder setFragmentTexture: b.mtlTexture
                                                                                      atIndex: b.index];
                                        });

    encodeBinding<MVKMTLSamplerStateBinding>(_vertexSamplerStateBindings, _areVertexSamplerStateBindingsDirty,
                                             [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                                                 [cmdEncoder->_mtlRenderEncoder setVertexSamplerState: b.mtlSamplerState
                                                                                              atIndex: b.index];
                                             });

    encodeBinding<MVKMTLSamplerStateBinding>(_fragmentSamplerStateBindings, _areFragmentSamplerStateBindingsDirty,
                                             [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                                                 [cmdEncoder->_mtlRenderEncoder setFragmentSamplerState: b.mtlSamplerState
                                                                                                atIndex: b.index];
                                             });
}

void MVKGraphicsResourcesCommandEncoderState::resetImpl() {
    _vertexBufferBindings.clear();
    _fragmentBufferBindings.clear();
    _vertexTextureBindings.clear();
    _fragmentTextureBindings.clear();
    _vertexSamplerStateBindings.clear();
    _fragmentSamplerStateBindings.clear();

    _areVertexBufferBindingsDirty = false;
    _areFragmentBufferBindingsDirty = false;
    _areVertexTextureBindingsDirty = false;
    _areFragmentTextureBindingsDirty = false;
    _areVertexSamplerStateBindingsDirty = false;
    _areFragmentSamplerStateBindingsDirty = false;
}


#pragma mark -
#pragma mark MVKComputeResourcesCommandEncoderState

void MVKComputeResourcesCommandEncoderState::bindBuffer(const MVKMTLBufferBinding& binding) {
    bind(binding, _bufferBindings, _areBufferBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindTexture(const MVKMTLTextureBinding& binding) {
    bind(binding, _textureBindings, _areTextureBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindSamplerState(const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _samplerStateBindings, _areSamplerStateBindingsDirty);
}

// Mark everything as dirty
void MVKComputeResourcesCommandEncoderState::markDirty() {
    MVKCommandEncoderState::markDirty();
    MVKResourcesCommandEncoderState::markDirty(_bufferBindings, _areBufferBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_textureBindings, _areTextureBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_samplerStateBindings, _areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::encodeImpl() {

    encodeBinding<MVKMTLBufferBinding>(_bufferBindings, _areBufferBindingsDirty,
                                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setBuffer: b.mtlBuffer
																										offset: b.offset
																									   atIndex: b.index];
                                       });

    encodeBinding<MVKMTLTextureBinding>(_textureBindings, _areTextureBindingsDirty,
                                        [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                                            [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setTexture: b.mtlTexture
																										 atIndex: b.index];
                                        });

    encodeBinding<MVKMTLSamplerStateBinding>(_samplerStateBindings, _areSamplerStateBindingsDirty,
                                             [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                                                 [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setSamplerState: b.mtlSamplerState
																												   atIndex: b.index];
                                             });
}

void MVKComputeResourcesCommandEncoderState::resetImpl() {
    _bufferBindings.clear();
    _textureBindings.clear();
    _samplerStateBindings.clear();

    _areBufferBindingsDirty = false;
    _areTextureBindingsDirty = false;
    _areSamplerStateBindingsDirty = false;
}


#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

void MVKOcclusionQueryCommandEncoderState::beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {

    NSUInteger offset = pQueryPool->getVisibilityResultOffset(query);
    NSUInteger maxOffset = _cmdEncoder->_pDeviceMetalFeatures->maxQueryBufferSize - kMVKQuerySlotSizeInBytes;

    bool shouldCount = _cmdEncoder->_pDeviceFeatures->occlusionQueryPrecise && mvkAreFlagsEnabled(flags, VK_QUERY_CONTROL_PRECISE_BIT);
    _mtlVisibilityResultMode = shouldCount ? MTLVisibilityResultModeCounting : MTLVisibilityResultModeBoolean;
    _mtlVisibilityResultOffset = min(offset, maxOffset);

    _visibilityResultMTLBuffer = pQueryPool->getVisibilityResultMTLBuffer();    // not retained

    markDirty();
}

void MVKOcclusionQueryCommandEncoderState::endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
    _mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
    _mtlVisibilityResultOffset = 0;

    markDirty();
}

// If the MTLBuffer has not yet been set, see if the command buffer is configured with it
id<MTLBuffer> MVKOcclusionQueryCommandEncoderState::getVisibilityResultMTLBuffer() { return _visibilityResultMTLBuffer; }

void MVKOcclusionQueryCommandEncoderState::encodeImpl() {
    [_cmdEncoder->_mtlRenderEncoder setVisibilityResultMode: _mtlVisibilityResultMode
                                                     offset: _mtlVisibilityResultOffset];
}

void MVKOcclusionQueryCommandEncoderState::resetImpl() {
    _visibilityResultMTLBuffer = _cmdEncoder->_cmdBuffer->_initialVisibilityResultMTLBuffer;
    _mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
    _mtlVisibilityResultOffset = 0;
}

MVKOcclusionQueryCommandEncoderState::MVKOcclusionQueryCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {
    resetImpl();
}


