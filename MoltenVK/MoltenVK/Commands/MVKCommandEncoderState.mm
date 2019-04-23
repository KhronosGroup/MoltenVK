/*
 * MVKCommandEncoderState.mm
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

void MVKPipelineCommandEncoderState::encodeImpl(uint32_t stage) {
    if (_pipeline) { _pipeline->encode(_cmdEncoder, stage); }
}

void MVKPipelineCommandEncoderState::resetImpl() {
    _pipeline = nullptr;
}


#pragma mark -
#pragma mark MVKViewportCommandEncoderState

void MVKViewportCommandEncoderState::setViewports(const MVKVector<MTLViewport> &mtlViewports,
												  uint32_t firstViewport,
												  bool isSettingDynamically) {

	uint32_t maxViewports = _cmdEncoder->getDevice()->_pProperties->limits.maxViewports;
	if ((firstViewport + mtlViewports.size() > maxViewports) ||
		(firstViewport >= maxViewports) ||
		(isSettingDynamically && mtlViewports.size() == 0))
		return;

	auto& usingMTLViewports = isSettingDynamically ? _mtlDynamicViewports : _mtlViewports;

	if (firstViewport + mtlViewports.size() > usingMTLViewports.size()) {
		usingMTLViewports.resize(firstViewport + mtlViewports.size());
	}

	bool mustSetDynamically = _cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_VIEWPORT);

	if (isSettingDynamically ||
		(!mustSetDynamically && mtlViewports.size() > 0))
		std::copy(mtlViewports.begin(), mtlViewports.end(), usingMTLViewports.begin() + firstViewport);
	else
		usingMTLViewports.clear();

	markDirty();
}

void MVKViewportCommandEncoderState::encodeImpl(uint32_t stage) {
    if (stage != kMVKGraphicsStageRasterization) { return; }
	auto& usingMTLViewports = _mtlViewports.size() > 0 ? _mtlViewports : _mtlDynamicViewports;
	MVKAssert(!usingMTLViewports.empty(), "Must specify at least one viewport");
    if (_cmdEncoder->_pDeviceFeatures->multiViewport) {
        [_cmdEncoder->_mtlRenderEncoder setViewports: &usingMTLViewports[0] count: usingMTLViewports.size()];
    } else {
        [_cmdEncoder->_mtlRenderEncoder setViewport: usingMTLViewports[0]];
    }
}

void MVKViewportCommandEncoderState::resetImpl() {
    _mtlViewports.clear();
	_mtlDynamicViewports.clear();
}


#pragma mark -
#pragma mark MVKScissorCommandEncoderState

void MVKScissorCommandEncoderState::setScissors(const MVKVector<MTLScissorRect> &mtlScissors,
                                                uint32_t firstScissor,
												bool isSettingDynamically) {

	uint32_t maxScissors = _cmdEncoder->getDevice()->_pProperties->limits.maxViewports;
	if ((firstScissor + mtlScissors.size() > maxScissors) ||
		(firstScissor >= maxScissors) ||
		(isSettingDynamically && mtlScissors.size() == 0))
		return;

	auto& usingMTLScissors = isSettingDynamically ? _mtlDynamicScissors : _mtlScissors;

	if (firstScissor + mtlScissors.size() > usingMTLScissors.size()) {
		usingMTLScissors.resize(firstScissor + mtlScissors.size());
	}

	bool mustSetDynamically = _cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_SCISSOR);

	if (isSettingDynamically ||
		(!mustSetDynamically && mtlScissors.size() > 0))
		std::copy(mtlScissors.begin(), mtlScissors.end(), usingMTLScissors.begin() + firstScissor);
	else
		usingMTLScissors.clear();

	markDirty();
}

void MVKScissorCommandEncoderState::encodeImpl(uint32_t stage) {
	if (stage != kMVKGraphicsStageRasterization) { return; }
	auto& usingMTLScissors = _mtlScissors.size() > 0 ? _mtlScissors : _mtlDynamicScissors;
	MVKAssert(!usingMTLScissors.empty(), "Must specify at least one scissor rect");
	auto clippedScissors(usingMTLScissors);
	std::for_each(clippedScissors.begin(), clippedScissors.end(), [this](MTLScissorRect& scissor) {
		scissor = _cmdEncoder->clipToRenderArea(scissor);
	});
	if (_cmdEncoder->_pDeviceFeatures->multiViewport) {
		[_cmdEncoder->_mtlRenderEncoder setScissorRects: &clippedScissors[0] count: clippedScissors.size()];
	} else {
		[_cmdEncoder->_mtlRenderEncoder setScissorRect: clippedScissors[0]];
	}
}

void MVKScissorCommandEncoderState::resetImpl() {
    _mtlScissors.clear();
	_mtlDynamicScissors.clear();
}


#pragma mark -
#pragma mark MVKPushConstantsCommandEncoderState

void MVKPushConstantsCommandEncoderState:: setPushConstants(uint32_t offset, MVKVector<char>& pushConstants) {
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

void MVKPushConstantsCommandEncoderState::encodeImpl(uint32_t stage) {
    if (_pushConstants.empty() ) { return; }

    switch (_shaderStage) {
        case VK_SHADER_STAGE_VERTEX_BIT:
            if (stage == (isTessellating() ? kMVKGraphicsStageVertex : kMVKGraphicsStageRasterization)) {
                _cmdEncoder->setVertexBytes(_cmdEncoder->_mtlRenderEncoder,
                                            _pushConstants.data(),
                                            _pushConstants.size(),
                                            _mtlBufferIndex);
            }
            break;
        case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:
            if (stage == kMVKGraphicsStageTessControl) {
                _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl),
                                             _pushConstants.data(),
                                             _pushConstants.size(),
                                             _mtlBufferIndex);
            }
            break;
        case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:
            if (isTessellating() && stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setVertexBytes(_cmdEncoder->_mtlRenderEncoder,
                                            _pushConstants.data(),
                                            _pushConstants.size(),
                                            _mtlBufferIndex);
            }
            break;
        case VK_SHADER_STAGE_FRAGMENT_BIT:
            if (stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setFragmentBytes(_cmdEncoder->_mtlRenderEncoder,
                                              _pushConstants.data(),
                                              _pushConstants.size(),
                                              _mtlBufferIndex);
            }
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

bool MVKPushConstantsCommandEncoderState::isTessellating() {
	MVKGraphicsPipeline* gp = (MVKGraphicsPipeline*)_cmdEncoder->_graphicsPipelineState.getPipeline();
	return gp ? gp->isTessellationPipeline() : false;
}

void MVKPushConstantsCommandEncoderState::resetImpl() {
    _pushConstants.clear();
}


#pragma mark -
#pragma mark MVKDepthStencilCommandEncoderState

void MVKDepthStencilCommandEncoderState:: setDepthStencilState(const VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo) {

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
                                                         const VkStencilOpState& vkStencil,
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

void MVKDepthStencilCommandEncoderState::encodeImpl(uint32_t stage) {
    if (stage != kMVKGraphicsStageRasterization && stage != kMVKGraphicsStageVertex) { return; }
    MVKRenderSubpass *subpass = _cmdEncoder->getSubpass();
    id<MTLDepthStencilState> mtlDSS = nil;
    if (stage != kMVKGraphicsStageVertex && subpass->getDepthStencilFormat() != VK_FORMAT_UNDEFINED) {
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

void MVKStencilReferenceValueCommandEncoderState:: setReferenceValues(const VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo) {

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

void MVKStencilReferenceValueCommandEncoderState::encodeImpl(uint32_t stage) {
    if (stage != kMVKGraphicsStageRasterization) { return; }
    [_cmdEncoder->_mtlRenderEncoder setStencilFrontReferenceValue: _frontFaceValue
                                               backReferenceValue: _backFaceValue];
}

void MVKStencilReferenceValueCommandEncoderState::resetImpl() {
    _frontFaceValue = 0;
    _backFaceValue = 0;
}


#pragma mark -
#pragma mark MVKDepthBiasCommandEncoderState

void MVKDepthBiasCommandEncoderState::setDepthBias(const VkPipelineRasterizationStateCreateInfo& vkRasterInfo) {

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

void MVKDepthBiasCommandEncoderState::encodeImpl(uint32_t stage) {
    if (stage != kMVKGraphicsStageRasterization) { return; }
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

void MVKBlendColorCommandEncoderState::encodeImpl(uint32_t stage) {
    if (stage != kMVKGraphicsStageRasterization) { return; }
    [_cmdEncoder->_mtlRenderEncoder setBlendColorRed: _red green: _green blue: _blue alpha: _alpha];
}

void MVKBlendColorCommandEncoderState::resetImpl() {
    _red = 0;
    _green = 0;
    _blue = 0;
    _alpha = 0;
}


#pragma mark -
#pragma mark MVKResourcesCommandEncoderState

// Updates the swizzle for an image in the given vector.
static void updateSwizzle(MVKVector<uint32_t> &constants, uint32_t index, uint32_t swizzle) {
	if (index >= constants.size()) { constants.resize(index + 1); }
	constants[index] = swizzle;
}

// If a swizzle is needed for this stage, iterates all the bindings and logs errors for those that need texture swizzling.
static void assertMissingSwizzles(bool needsSwizzle, const char* stageName, MVKVector<MVKMTLTextureBinding>& texBindings) {
	if (needsSwizzle) {
		for (MVKMTLTextureBinding& tb : texBindings) {
			VkComponentMapping vkcm = mvkUnpackSwizzle(tb.swizzle);
			if (!mvkVkComponentMappingsMatch(vkcm, {VK_COMPONENT_SWIZZLE_R, VK_COMPONENT_SWIZZLE_G, VK_COMPONENT_SWIZZLE_B, VK_COMPONENT_SWIZZLE_A})) {
				MVKLogError("Pipeline does not support component swizzle (%s, %s, %s, %s) required by a VkImageView used in the %s shader."
							" Full VkImageView component swizzling will be supported by a pipeline if the MVKConfiguration::fullImageViewSwizzle"
							" config parameter or MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE environment variable was enabled when the pipeline is compiled.",
							mvkVkComponentSwizzleName(vkcm.r), mvkVkComponentSwizzleName(vkcm.g),
							mvkVkComponentSwizzleName(vkcm.b), mvkVkComponentSwizzleName(vkcm.a), stageName);
				MVKAssert(false, "See previous logged error.");
			}
		}
	}
}


#pragma mark -
#pragma mark MVKGraphicsResourcesCommandEncoderState

void MVKGraphicsResourcesCommandEncoderState::bindBuffer(MVKShaderStage stage, const MVKMTLBufferBinding& binding) {
    bind(binding, _shaderStages[stage].bufferBindings, _shaderStages[stage].areBufferBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindTexture(MVKShaderStage stage, const MVKMTLTextureBinding& binding) {
    bind(binding, _shaderStages[stage].textureBindings, _shaderStages[stage].areTextureBindingsDirty, _shaderStages[stage].needsSwizzle);
}

void MVKGraphicsResourcesCommandEncoderState::bindSamplerState(MVKShaderStage stage, const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _shaderStages[stage].samplerStateBindings, _shaderStages[stage].areSamplerStateBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindAuxBuffer(const MVKShaderImplicitRezBinding& binding,
															bool needVertexAuxBuffer,
															bool needTessCtlAuxBuffer,
															bool needTessEvalAuxBuffer,
															bool needFragmentAuxBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCompute; i++) {
        _shaderStages[i].auxBufferBinding.index = binding.stages[i];
    }
    _shaderStages[kMVKShaderStageVertex].auxBufferBinding.isDirty = needVertexAuxBuffer;
    _shaderStages[kMVKShaderStageTessCtl].auxBufferBinding.isDirty = needTessCtlAuxBuffer;
    _shaderStages[kMVKShaderStageTessEval].auxBufferBinding.isDirty = needTessEvalAuxBuffer;
    _shaderStages[kMVKShaderStageFragment].auxBufferBinding.isDirty = needFragmentAuxBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::encodeBindings(MVKShaderStage stage,
                                                             const char* pStageName,
                                                             bool fullImageViewSwizzle,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&)> bindBuffer,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&, MVKVector<uint32_t>&)> bindAuxBuffer,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLTextureBinding&)> bindTexture,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLSamplerStateBinding&)> bindSampler) {
    auto& shaderStage = _shaderStages[stage];
    encodeBinding<MVKMTLBufferBinding>(shaderStage.bufferBindings, shaderStage.areBufferBindingsDirty, bindBuffer);

    if (shaderStage.auxBufferBinding.isDirty) {

        for (auto& b : shaderStage.textureBindings) {
            if (b.isDirty) { updateSwizzle(shaderStage.swizzleConstants, b.index, b.swizzle); }
        }

        bindAuxBuffer(_cmdEncoder, shaderStage.auxBufferBinding, shaderStage.swizzleConstants);

    } else {
        assertMissingSwizzles(shaderStage.needsSwizzle && !fullImageViewSwizzle, pStageName, shaderStage.textureBindings);
    }

    encodeBinding<MVKMTLTextureBinding>(shaderStage.textureBindings, shaderStage.areTextureBindingsDirty, bindTexture);
    encodeBinding<MVKMTLSamplerStateBinding>(shaderStage.samplerStateBindings, shaderStage.areSamplerStateBindingsDirty, bindSampler);
}

// Mark everything as dirty
void MVKGraphicsResourcesCommandEncoderState::markDirty() {
    MVKCommandEncoderState::markDirty();
    for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCompute; i++) {
        MVKResourcesCommandEncoderState::markDirty(_shaderStages[i].bufferBindings, _shaderStages[i].areBufferBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStages[i].textureBindings, _shaderStages[i].areTextureBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStages[i].samplerStateBindings, _shaderStages[i].areSamplerStateBindingsDirty);
    }
}

void MVKGraphicsResourcesCommandEncoderState::encodeImpl(uint32_t stage) {

    MVKPipeline* pipeline = _cmdEncoder->_graphicsPipelineState.getPipeline();
    bool fullImageViewSwizzle = pipeline->fullImageViewSwizzle();
    bool forTessellation = ((MVKGraphicsPipeline*)pipeline)->isTessellationPipeline();

    if (stage == (forTessellation ? kMVKGraphicsStageVertex : kMVKGraphicsStageRasterization)) {
        encodeBindings(kMVKShaderStageVertex, "vertex", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexBuffer: b.mtlBuffer
                                                                   offset: b.offset
                                                                  atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKVector<uint32_t>& s)->void {
                           cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                      s.data(),
                                                      s.size() * sizeof(uint32_t),
                                                      b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexTexture: b.mtlTexture
                                                                   atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexSamplerState: b.mtlSamplerState
                                                                        atIndex: b.index];
                       });

    }

    if (stage == kMVKGraphicsStageTessControl) {
        encodeBindings(kMVKShaderStageTessCtl, "tessellation control", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl) setBuffer: b.mtlBuffer
                                                                                                   offset: b.offset
                                                                                                  atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKVector<uint32_t>& s)->void {
                           cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl),
                                                       s.data(),
                                                       s.size() * sizeof(uint32_t),
                                                       b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl) setTexture: b.mtlTexture
                                                                                                   atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl) setSamplerState: b.mtlSamplerState
                                                                                                        atIndex: b.index];
                       });

    }

    if (forTessellation && stage == kMVKGraphicsStageRasterization) {
        encodeBindings(kMVKShaderStageTessEval, "tessellation evaluation", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexBuffer: b.mtlBuffer
                                                                   offset: b.offset
                                                                  atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKVector<uint32_t>& s)->void {
                           cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                      s.data(),
                                                      s.size() * sizeof(uint32_t),
                                                      b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexTexture: b.mtlTexture
                                                                   atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexSamplerState: b.mtlSamplerState
                                                                        atIndex: b.index];
                       });

    }

    if (stage == kMVKGraphicsStageRasterization) {
        encodeBindings(kMVKShaderStageFragment, "fragment", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setFragmentBuffer: b.mtlBuffer
                                                                     offset: b.offset
                                                                    atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKVector<uint32_t>& s)->void {
		                   cmdEncoder->setFragmentBytes(cmdEncoder->_mtlRenderEncoder,
                                                        s.data(),
                                                        s.size() * sizeof(uint32_t),
                                                        b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setFragmentTexture: b.mtlTexture
                                                                     atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setFragmentSamplerState: b.mtlSamplerState
                                                                          atIndex: b.index];
                       });
    }
}

void MVKGraphicsResourcesCommandEncoderState::resetImpl() {
    for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCompute; i++) {
        _shaderStages[i].bufferBindings.clear();
        _shaderStages[i].textureBindings.clear();
        _shaderStages[i].samplerStateBindings.clear();
        _shaderStages[i].swizzleConstants.clear();

        _shaderStages[i].areBufferBindingsDirty = false;
        _shaderStages[i].areTextureBindingsDirty = false;
        _shaderStages[i].areSamplerStateBindingsDirty = false;
        _shaderStages[i].auxBufferBinding.isDirty = false;

        _shaderStages[i].needsSwizzle = false;
    }
}


#pragma mark -
#pragma mark MVKComputeResourcesCommandEncoderState

void MVKComputeResourcesCommandEncoderState::bindBuffer(const MVKMTLBufferBinding& binding) {
    bind(binding, _bufferBindings, _areBufferBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindTexture(const MVKMTLTextureBinding& binding) {
	bind(binding, _textureBindings, _areTextureBindingsDirty, _needsSwizzle);
}

void MVKComputeResourcesCommandEncoderState::bindSamplerState(const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _samplerStateBindings, _areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindAuxBuffer(const MVKShaderImplicitRezBinding& binding,
														   bool needAuxBuffer) {
    _auxBufferBinding.index = binding.stages[kMVKShaderStageCompute];
    _auxBufferBinding.isDirty = needAuxBuffer;
}

// Mark everything as dirty
void MVKComputeResourcesCommandEncoderState::markDirty() {
    MVKCommandEncoderState::markDirty();
    MVKResourcesCommandEncoderState::markDirty(_bufferBindings, _areBufferBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_textureBindings, _areTextureBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_samplerStateBindings, _areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::encodeImpl(uint32_t) {

    bool fullImageViewSwizzle = false;
    MVKPipeline* pipeline = _cmdEncoder->_computePipelineState.getPipeline();
    if (pipeline)
        fullImageViewSwizzle = pipeline->fullImageViewSwizzle();

    encodeBinding<MVKMTLBufferBinding>(_bufferBindings, _areBufferBindingsDirty,
                                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setBuffer: b.mtlBuffer
																										offset: b.offset
																									   atIndex: b.index];
                                       });

    if (_auxBufferBinding.isDirty) {

		for (auto& b : _textureBindings) {
			if (b.isDirty) { updateSwizzle(_swizzleConstants, b.index, b.swizzle); }
		}

		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                     _swizzleConstants.data(),
                                     _swizzleConstants.size() * sizeof(uint32_t),
                                     _auxBufferBinding.index);

	} else {
		assertMissingSwizzles(_needsSwizzle && !fullImageViewSwizzle, "compute", _textureBindings);
    }

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
    _swizzleConstants.clear();

    _areBufferBindingsDirty = false;
    _areTextureBindingsDirty = false;
    _areSamplerStateBindingsDirty = false;
    _auxBufferBinding.isDirty = false;

	_needsSwizzle = false;
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

void MVKOcclusionQueryCommandEncoderState::encodeImpl(uint32_t stage) {
    if (stage != kMVKGraphicsStageRasterization) { return; }
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


