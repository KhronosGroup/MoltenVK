/*
 * MVKCommandEncoderState.mm
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

using namespace std;


#pragma mark -
#pragma mark MVKCommandEncoderState

MVKVulkanAPIObject* MVKCommandEncoderState::getVulkanAPIObject() { return _cmdEncoder->getVulkanAPIObject(); };


#pragma mark -
#pragma mark MVKPipelineCommandEncoderState

void MVKPipelineCommandEncoderState::setPipeline(MVKPipeline* pipeline) {
    _pipeline = pipeline;
    markDirty();
}

MVKPipeline* MVKPipelineCommandEncoderState::getPipeline() { return _pipeline; }

void MVKPipelineCommandEncoderState::encodeImpl(uint32_t stage) {
    if (_pipeline) {
		_pipeline->encode(_cmdEncoder, stage);
		_pipeline->bindPushConstants(_cmdEncoder);
	}
}

void MVKPipelineCommandEncoderState::resetImpl() {
    _pipeline = nullptr;
}


#pragma mark -
#pragma mark MVKViewportCommandEncoderState

void MVKViewportCommandEncoderState::setViewports(const MVKArrayRef<VkViewport> viewports,
												  uint32_t firstViewport,
												  bool isSettingDynamically) {

	size_t vpCnt = viewports.size;
	uint32_t maxViewports = _cmdEncoder->getDevice()->_pProperties->limits.maxViewports;
	if ((firstViewport + vpCnt > maxViewports) ||
		(firstViewport >= maxViewports) ||
		(isSettingDynamically && vpCnt == 0))
		return;

	auto& usingViewports = isSettingDynamically ? _dynamicViewports : _viewports;

	if (firstViewport + vpCnt > usingViewports.size()) {
		usingViewports.resize(firstViewport + vpCnt);
	}

	bool mustSetDynamically = _cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_VIEWPORT);
	if (isSettingDynamically || (!mustSetDynamically && vpCnt > 0)) {
		std::copy(viewports.begin(), viewports.end(), usingViewports.begin() + firstViewport);
	} else {
		usingViewports.clear();
	}

	markDirty();
}

void MVKViewportCommandEncoderState::encodeImpl(uint32_t stage) {
    if (stage != kMVKGraphicsStageRasterization) { return; }
	auto& usingViewports = _viewports.size() > 0 ? _viewports : _dynamicViewports;
	if (usingViewports.empty()) { return; }

    if (_cmdEncoder->_pDeviceFeatures->multiViewport) {
		size_t vpCnt = usingViewports.size();
		MTLViewport mtlViewports[vpCnt];
		for (uint32_t vpIdx = 0; vpIdx < vpCnt; vpIdx++) {
			mtlViewports[vpIdx] = mvkMTLViewportFromVkViewport(usingViewports[vpIdx]);
		}
#if MVK_MACOS_OR_IOS
        [_cmdEncoder->_mtlRenderEncoder setViewports: mtlViewports count: vpCnt];
#endif
	} else {
        [_cmdEncoder->_mtlRenderEncoder setViewport: mvkMTLViewportFromVkViewport(usingViewports[0])];
    }
}

void MVKViewportCommandEncoderState::resetImpl() {
    _viewports.clear();
	_dynamicViewports.clear();
}


#pragma mark -
#pragma mark MVKScissorCommandEncoderState

void MVKScissorCommandEncoderState::setScissors(const MVKArrayRef<VkRect2D> scissors,
                                                uint32_t firstScissor,
												bool isSettingDynamically) {

	size_t sCnt = scissors.size;
	uint32_t maxScissors = _cmdEncoder->getDevice()->_pProperties->limits.maxViewports;
	if ((firstScissor + sCnt > maxScissors) ||
		(firstScissor >= maxScissors) ||
		(isSettingDynamically && sCnt == 0))
		return;

	auto& usingScissors = isSettingDynamically ? _dynamicScissors : _scissors;

	if (firstScissor + sCnt > usingScissors.size()) {
		usingScissors.resize(firstScissor + sCnt);
	}

	bool mustSetDynamically = _cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_SCISSOR);
	if (isSettingDynamically || (!mustSetDynamically && sCnt > 0)) {
		std::copy(scissors.begin(), scissors.end(), usingScissors.begin() + firstScissor);
	} else {
		usingScissors.clear();
	}

	markDirty();
}

void MVKScissorCommandEncoderState::encodeImpl(uint32_t stage) {
	if (stage != kMVKGraphicsStageRasterization) { return; }
	auto& usingScissors = _scissors.size() > 0 ? _scissors : _dynamicScissors;
	if (usingScissors.empty()) { return; }

	if (_cmdEncoder->_pDeviceFeatures->multiViewport) {
		size_t sCnt = usingScissors.size();
		MTLScissorRect mtlScissors[sCnt];
		for (uint32_t sIdx = 0; sIdx < sCnt; sIdx++) {
			mtlScissors[sIdx] = mvkMTLScissorRectFromVkRect2D(_cmdEncoder->clipToRenderArea(usingScissors[sIdx]));
		}
#if MVK_MACOS_OR_IOS
		[_cmdEncoder->_mtlRenderEncoder setScissorRects: mtlScissors count: sCnt];
#endif
	} else {
		[_cmdEncoder->_mtlRenderEncoder setScissorRect: mvkMTLScissorRectFromVkRect2D(_cmdEncoder->clipToRenderArea(usingScissors[0]))];
	}
}

void MVKScissorCommandEncoderState::resetImpl() {
    _scissors.clear();
	_dynamicScissors.clear();
}


#pragma mark -
#pragma mark MVKPushConstantsCommandEncoderState

void MVKPushConstantsCommandEncoderState:: setPushConstants(uint32_t offset, MVKArrayRef<char> pushConstants) {
	// MSL structs can have a larger size than the equivalent C struct due to MSL alignment needs.
	// Typically any MSL struct that contains a float4 will also have a size that is rounded up to a multiple of a float4 size.
	// Ensure that we pass along enough content to cover this extra space even if it is never actually accessed by the shader.
	size_t pcSizeAlign = _cmdEncoder->getDevice()->_pMetalFeatures->pushConstantSizeAlignment;
    size_t pcSize = pushConstants.size;
	size_t pcBuffSize = mvkAlignByteCount(offset + pcSize, pcSizeAlign);
    mvkEnsureSize(_pushConstants, pcBuffSize);
    copy(pushConstants.begin(), pushConstants.end(), _pushConstants.begin() + offset);
    if (pcBuffSize > 0) { markDirty(); }
}

void MVKPushConstantsCommandEncoderState::setMTLBufferIndex(uint32_t mtlBufferIndex) {
    if (mtlBufferIndex != _mtlBufferIndex) {
        _mtlBufferIndex = mtlBufferIndex;
        markDirty();
    }
}

// At this point, I have been marked not-dirty, under the assumption that I will make changes to the encoder.
// However, some of the paths below decide not to actually make any changes to the encoder. In that case,
// I should remain dirty until I actually do make encoder changes.
void MVKPushConstantsCommandEncoderState::encodeImpl(uint32_t stage) {
    if (_pushConstants.empty() ) { return; }

	_isDirty = true;	// Stay dirty until I actually decide to make a change to the encoder

    switch (_shaderStage) {
        case VK_SHADER_STAGE_VERTEX_BIT:
			if (stage == kMVKGraphicsStageVertex) {
                _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                             _pushConstants.data(),
                                             _pushConstants.size(),
                                             _mtlBufferIndex);
				_isDirty = false;	// Okay, I changed the encoder
			} else if (!isTessellating() && stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setVertexBytes(_cmdEncoder->_mtlRenderEncoder,
                                            _pushConstants.data(),
                                            _pushConstants.size(),
                                            _mtlBufferIndex);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:
            if (stage == kMVKGraphicsStageTessControl) {
                _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                             _pushConstants.data(),
                                             _pushConstants.size(),
                                             _mtlBufferIndex);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:
            if (isTessellating() && stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setVertexBytes(_cmdEncoder->_mtlRenderEncoder,
                                            _pushConstants.data(),
                                            _pushConstants.size(),
                                            _mtlBufferIndex);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_FRAGMENT_BIT:
            if (stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setFragmentBytes(_cmdEncoder->_mtlRenderEncoder,
                                              _pushConstants.data(),
                                              _pushConstants.size(),
                                              _mtlBufferIndex);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_COMPUTE_BIT:
            _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                         _pushConstants.data(),
                                         _pushConstants.size(),
                                         _mtlBufferIndex);
			_isDirty = false;	// Okay, I changed the encoder
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

    if (mvkAreAllFlagsEnabled(faceMask, VK_STENCIL_FACE_FRONT_BIT)) {
        _depthStencilData.frontFaceStencilData.readMask = stencilCompareMask;
    }
    if (mvkAreAllFlagsEnabled(faceMask, VK_STENCIL_FACE_BACK_BIT)) {
        _depthStencilData.backFaceStencilData.readMask = stencilCompareMask;
    }

    markDirty();
}

void MVKDepthStencilCommandEncoderState::setStencilWriteMask(VkStencilFaceFlags faceMask,
                                                             uint32_t stencilWriteMask) {

    // If we can't set the state, or nothing is being set, just leave
    if ( !(_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_WRITE_MASK) &&
           mvkIsAnyFlagEnabled(faceMask, VK_STENCIL_FRONT_AND_BACK)) ) { return; }

    if (mvkAreAllFlagsEnabled(faceMask, VK_STENCIL_FACE_FRONT_BIT)) {
        _depthStencilData.frontFaceStencilData.writeMask = stencilWriteMask;
    }
    if (mvkAreAllFlagsEnabled(faceMask, VK_STENCIL_FACE_BACK_BIT)) {
        _depthStencilData.backFaceStencilData.writeMask = stencilWriteMask;
    }

    markDirty();
}

void MVKDepthStencilCommandEncoderState::beginMetalRenderPass() {
	MVKRenderSubpass* mvkSubpass = _cmdEncoder->getSubpass();
	MVKPixelFormats* pixFmts = _cmdEncoder->getPixelFormats();
	MTLPixelFormat mtlDSFormat = pixFmts->getMTLPixelFormat(mvkSubpass->getDepthStencilFormat());

	bool prevHasDepthAttachment = _hasDepthAttachment;
	_hasDepthAttachment = pixFmts->isDepthFormat(mtlDSFormat);
	if (_hasDepthAttachment != prevHasDepthAttachment) { markDirty(); }

	bool prevHasStencilAttachment = _hasStencilAttachment;
	_hasStencilAttachment = pixFmts->isStencilFormat(mtlDSFormat);
	if (_hasStencilAttachment != prevHasStencilAttachment) { markDirty(); }
}

void MVKDepthStencilCommandEncoderState::encodeImpl(uint32_t stage) {
	auto cmdEncPool = _cmdEncoder->getCommandEncodingPool();
	switch (stage) {
		case kMVKGraphicsStageRasterization: {
			// If renderpass does not have a depth or a stencil attachment, disable corresponding test
			MVKMTLDepthStencilDescriptorData adjustedDSData = _depthStencilData;
			adjustedDSData.disable(!_hasDepthAttachment, !_hasStencilAttachment);
			[_cmdEncoder->_mtlRenderEncoder setDepthStencilState: cmdEncPool->getMTLDepthStencilState(adjustedDSData)];
			break;
		}
		default:		// Do nothing on other stages
			break;
	}
}

void MVKDepthStencilCommandEncoderState::resetImpl() {
    _depthStencilData = kMVKMTLDepthStencilDescriptorDataDefault;
	_hasDepthAttachment = false;
	_hasStencilAttachment = false;
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

    if (mvkAreAllFlagsEnabled(faceMask, VK_STENCIL_FACE_FRONT_BIT)) {
        _frontFaceValue = stencilReference;
    }
    if (mvkAreAllFlagsEnabled(faceMask, VK_STENCIL_FACE_BACK_BIT)) {
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

// If a swizzle is needed for this stage, iterates all the bindings and logs errors for those that need texture swizzling.
void MVKResourcesCommandEncoderState::assertMissingSwizzles(bool needsSwizzle, const char* stageName, const MVKArrayRef<MVKMTLTextureBinding>& texBindings) {
	if (needsSwizzle) {
		for (auto& tb : texBindings) {
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
    bind(binding, _shaderStageResourceBindings[stage].bufferBindings, _shaderStageResourceBindings[stage].areBufferBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindTexture(MVKShaderStage stage, const MVKMTLTextureBinding& binding) {
    bind(binding, _shaderStageResourceBindings[stage].textureBindings, _shaderStageResourceBindings[stage].areTextureBindingsDirty, _shaderStageResourceBindings[stage].needsSwizzle);
}

void MVKGraphicsResourcesCommandEncoderState::bindSamplerState(MVKShaderStage stage, const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _shaderStageResourceBindings[stage].samplerStateBindings, _shaderStageResourceBindings[stage].areSamplerStateBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindSwizzleBuffer(const MVKShaderImplicitRezBinding& binding,
																bool needVertexSwizzleBuffer,
																bool needTessCtlSwizzleBuffer,
																bool needTessEvalSwizzleBuffer,
																bool needFragmentSwizzleBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        _shaderStageResourceBindings[i].swizzleBufferBinding.index = binding.stages[i];
    }
    _shaderStageResourceBindings[kMVKShaderStageVertex].swizzleBufferBinding.isDirty = needVertexSwizzleBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessCtl].swizzleBufferBinding.isDirty = needTessCtlSwizzleBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessEval].swizzleBufferBinding.isDirty = needTessEvalSwizzleBuffer;
    _shaderStageResourceBindings[kMVKShaderStageFragment].swizzleBufferBinding.isDirty = needFragmentSwizzleBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::bindBufferSizeBuffer(const MVKShaderImplicitRezBinding& binding,
																   bool needVertexSizeBuffer,
																   bool needTessCtlSizeBuffer,
																   bool needTessEvalSizeBuffer,
																   bool needFragmentSizeBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        _shaderStageResourceBindings[i].bufferSizeBufferBinding.index = binding.stages[i];
    }
    _shaderStageResourceBindings[kMVKShaderStageVertex].bufferSizeBufferBinding.isDirty = needVertexSizeBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessCtl].bufferSizeBufferBinding.isDirty = needTessCtlSizeBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessEval].bufferSizeBufferBinding.isDirty = needTessEvalSizeBuffer;
    _shaderStageResourceBindings[kMVKShaderStageFragment].bufferSizeBufferBinding.isDirty = needFragmentSizeBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::bindViewRangeBuffer(const MVKShaderImplicitRezBinding& binding,
																  bool needVertexViewBuffer,
																  bool needFragmentViewBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        _shaderStageResourceBindings[i].viewRangeBufferBinding.index = binding.stages[i];
    }
    _shaderStageResourceBindings[kMVKShaderStageVertex].viewRangeBufferBinding.isDirty = needVertexViewBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessCtl].viewRangeBufferBinding.isDirty = false;
    _shaderStageResourceBindings[kMVKShaderStageTessEval].viewRangeBufferBinding.isDirty = false;
    _shaderStageResourceBindings[kMVKShaderStageFragment].viewRangeBufferBinding.isDirty = needFragmentViewBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::encodeBindings(MVKShaderStage stage,
                                                             const char* pStageName,
                                                             bool fullImageViewSwizzle,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&)> bindBuffer,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&, const MVKArrayRef<uint32_t>&)> bindImplicitBuffer,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLTextureBinding&)> bindTexture,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLSamplerStateBinding&)> bindSampler) {
    auto& shaderStage = _shaderStageResourceBindings[stage];
    encodeBinding<MVKMTLBufferBinding>(shaderStage.bufferBindings, shaderStage.areBufferBindingsDirty, bindBuffer);

    if (shaderStage.swizzleBufferBinding.isDirty) {

        for (auto& b : shaderStage.textureBindings) {
            if (b.isDirty) { updateImplicitBuffer(shaderStage.swizzleConstants, b.index, b.swizzle); }
        }

        bindImplicitBuffer(_cmdEncoder, shaderStage.swizzleBufferBinding, shaderStage.swizzleConstants.contents());

    } else {
        assertMissingSwizzles(shaderStage.needsSwizzle && !fullImageViewSwizzle, pStageName, shaderStage.textureBindings.contents());
    }

    if (shaderStage.bufferSizeBufferBinding.isDirty) {
        for (auto& b : shaderStage.bufferBindings) {
            if (b.isDirty) { updateImplicitBuffer(shaderStage.bufferSizes, b.index, b.size); }
        }

        bindImplicitBuffer(_cmdEncoder, shaderStage.bufferSizeBufferBinding, shaderStage.bufferSizes.contents());
    }

    if (shaderStage.viewRangeBufferBinding.isDirty) {
        MVKSmallVector<uint32_t, 2> viewRange;
        viewRange.push_back(_cmdEncoder->getSubpass()->getFirstViewIndexInMetalPass(_cmdEncoder->getMultiviewPassIndex()));
        viewRange.push_back(_cmdEncoder->getSubpass()->getViewCountInMetalPass(_cmdEncoder->getMultiviewPassIndex()));
        bindImplicitBuffer(_cmdEncoder, shaderStage.viewRangeBufferBinding, viewRange.contents());
    }

    encodeBinding<MVKMTLTextureBinding>(shaderStage.textureBindings, shaderStage.areTextureBindingsDirty, bindTexture);
    encodeBinding<MVKMTLSamplerStateBinding>(shaderStage.samplerStateBindings, shaderStage.areSamplerStateBindingsDirty, bindSampler);
}

void MVKGraphicsResourcesCommandEncoderState::offsetZeroDivisorVertexBuffers(MVKGraphicsStage stage,
                                                                             MVKGraphicsPipeline* pipeline,
                                                                             uint32_t firstInstance) {
    auto& shaderStage = _shaderStageResourceBindings[kMVKShaderStageVertex];
    for (auto& binding : pipeline->getZeroDivisorVertexBindings()) {
        uint32_t mtlBuffIdx = pipeline->getMetalBufferIndexForVertexAttributeBinding(binding.first);
        auto iter = std::find_if(shaderStage.bufferBindings.begin(), shaderStage.bufferBindings.end(), [mtlBuffIdx](const MVKMTLBufferBinding& b) { return b.index == mtlBuffIdx; });
		if (!iter) { continue; }
        switch (stage) {
            case kMVKGraphicsStageVertex:
                [_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBufferOffset: iter->offset + firstInstance * binding.second
                                                                                                    atIndex: mtlBuffIdx];
                break;
            case kMVKGraphicsStageRasterization:
                [_cmdEncoder->_mtlRenderEncoder setVertexBufferOffset: iter->offset + firstInstance * binding.second
                                                              atIndex: mtlBuffIdx];
                break;
            default:
                assert(false);      // If we hit this, something went wrong.
                break;
        }
    }
}

// Mark everything as dirty
void MVKGraphicsResourcesCommandEncoderState::markDirty() {
    MVKCommandEncoderState::markDirty();
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].bufferBindings, _shaderStageResourceBindings[i].areBufferBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].textureBindings, _shaderStageResourceBindings[i].areTextureBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].samplerStateBindings, _shaderStageResourceBindings[i].areSamplerStateBindingsDirty);
    }
}

void MVKGraphicsResourcesCommandEncoderState::encodeImpl(uint32_t stage) {

    MVKGraphicsPipeline* pipeline = (MVKGraphicsPipeline*)_cmdEncoder->_graphicsPipelineState.getPipeline();
    bool fullImageViewSwizzle = pipeline->fullImageViewSwizzle() || _cmdEncoder->getDevice()->_pMetalFeatures->nativeTextureSwizzle;
    bool forTessellation = pipeline->isTessellationPipeline();

	if (stage == kMVKGraphicsStageVertex) {
        encodeBindings(kMVKShaderStageVertex, "vertex", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           if (b.isInline)
                               cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                           b.mtlBytes,
                                                           b.size,
                                                           b.index);
                           else
                               [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBuffer: b.mtlBuffer
                                                                                                             offset: b.offset
                                                                                                            atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t>& s)->void {
                           cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                       s.data,
                                                       s.size * sizeof(uint32_t),
                                                       b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setTexture: b.mtlTexture
                                                                                                         atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setSamplerState: b.mtlSamplerState
                                                                                                              atIndex: b.index];
                       });

	} else if (!forTessellation && stage == kMVKGraphicsStageRasterization) {
        encodeBindings(kMVKShaderStageVertex, "vertex", fullImageViewSwizzle,
                       [pipeline](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
					       if (b.isInline) {
                               cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                          b.mtlBytes,
                                                          b.size,
                                                          b.index);
					       } else {
                               [cmdEncoder->_mtlRenderEncoder setVertexBuffer: b.mtlBuffer
                                                                       offset: b.offset
                                                                      atIndex: b.index];

							   // Add any translated vertex bindings for this binding
							   auto xltdVtxBindings = pipeline->getTranslatedVertexBindings();
							   for (auto& xltdBind : xltdVtxBindings) {
								   if (b.index == pipeline->getMetalBufferIndexForVertexAttributeBinding(xltdBind.binding)) {
									   [cmdEncoder->_mtlRenderEncoder setVertexBuffer: b.mtlBuffer
																			   offset: b.offset + xltdBind.translationOffset
																			  atIndex: pipeline->getMetalBufferIndexForVertexAttributeBinding(xltdBind.translationBinding)];
								   }
							   }
					       }
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t>& s)->void {
                           cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                      s.data,
                                                      s.size * sizeof(uint32_t),
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
                           if (b.isInline)
                               cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                           b.mtlBytes,
                                                           b.size,
                                                           b.index);
                           else
                               [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBuffer: b.mtlBuffer
                                                                                                             offset: b.offset
                                                                                                            atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t>& s)->void {
                           cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                       s.data,
                                                       s.size * sizeof(uint32_t),
                                                       b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setTexture: b.mtlTexture
                                                                                                         atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setSamplerState: b.mtlSamplerState
                                                                                                              atIndex: b.index];
                       });

    }

    if (forTessellation && stage == kMVKGraphicsStageRasterization) {
        encodeBindings(kMVKShaderStageTessEval, "tessellation evaluation", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           if (b.isInline)
                               cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                          b.mtlBytes,
                                                          b.size,
                                                          b.index);
                           else
                               [cmdEncoder->_mtlRenderEncoder setVertexBuffer: b.mtlBuffer
                                                                       offset: b.offset
                                                                      atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t>& s)->void {
                           cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                      s.data,
                                                      s.size * sizeof(uint32_t),
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
                           if (b.isInline)
                               cmdEncoder->setFragmentBytes(cmdEncoder->_mtlRenderEncoder,
                                                            b.mtlBytes,
                                                            b.size,
                                                            b.index);
                           else
                               [cmdEncoder->_mtlRenderEncoder setFragmentBuffer: b.mtlBuffer
                                                                         offset: b.offset
                                                                        atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t>& s)->void {
                           cmdEncoder->setFragmentBytes(cmdEncoder->_mtlRenderEncoder,
                                                        s.data,
                                                        s.size * sizeof(uint32_t),
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
	for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
		_shaderStageResourceBindings[i].reset();
	}
}


#pragma mark -
#pragma mark MVKComputeResourcesCommandEncoderState

void MVKComputeResourcesCommandEncoderState::bindBuffer(const MVKMTLBufferBinding& binding) {
	bind(binding, _resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindTexture(const MVKMTLTextureBinding& binding) {
    bind(binding, _resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty, _resourceBindings.needsSwizzle);
}

void MVKComputeResourcesCommandEncoderState::bindSamplerState(const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindSwizzleBuffer(const MVKShaderImplicitRezBinding& binding,
															   bool needSwizzleBuffer) {
    _resourceBindings.swizzleBufferBinding.index = binding.stages[kMVKShaderStageCompute];
    _resourceBindings.swizzleBufferBinding.isDirty = needSwizzleBuffer;
}

void MVKComputeResourcesCommandEncoderState::bindBufferSizeBuffer(const MVKShaderImplicitRezBinding& binding,
																  bool needBufferSizeBuffer) {
    _resourceBindings.bufferSizeBufferBinding.index = binding.stages[kMVKShaderStageCompute];
    _resourceBindings.bufferSizeBufferBinding.isDirty = needBufferSizeBuffer;
}

// Mark everything as dirty
void MVKComputeResourcesCommandEncoderState::markDirty() {
    MVKCommandEncoderState::markDirty();
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::encodeImpl(uint32_t) {

    MVKPipeline* pipeline = _cmdEncoder->_computePipelineState.getPipeline();
	bool fullImageViewSwizzle = pipeline ? pipeline->fullImageViewSwizzle() : false;

    if (_resourceBindings.swizzleBufferBinding.isDirty) {
		for (auto& b : _resourceBindings.textureBindings) {
			if (b.isDirty) { updateImplicitBuffer(_resourceBindings.swizzleConstants, b.index, b.swizzle); }
		}

		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                     _resourceBindings.swizzleConstants.data(),
                                     _resourceBindings.swizzleConstants.size() * sizeof(uint32_t),
                                     _resourceBindings.swizzleBufferBinding.index);

	} else {
		assertMissingSwizzles(_resourceBindings.needsSwizzle && !fullImageViewSwizzle, "compute", _resourceBindings.textureBindings.contents());
    }

    if (_resourceBindings.bufferSizeBufferBinding.isDirty) {
		for (auto& b : _resourceBindings.bufferBindings) {
			if (b.isDirty) { updateImplicitBuffer(_resourceBindings.bufferSizes, b.index, b.size); }
		}

		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                     _resourceBindings.bufferSizes.data(),
                                     _resourceBindings.bufferSizes.size() * sizeof(uint32_t),
                                     _resourceBindings.bufferSizeBufferBinding.index);

    }

	encodeBinding<MVKMTLBufferBinding>(_resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty,
									   [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
		if (b.isInline) {
			cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
										b.mtlBytes,
										b.size,
										b.index);
		} else {
			[cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setBuffer: b.mtlBuffer
																		 offset: b.offset
																		atIndex: b.index];
		}
	});

    encodeBinding<MVKMTLTextureBinding>(_resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty,
                                        [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                                            [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setTexture: b.mtlTexture
																										 atIndex: b.index];
                                        });

    encodeBinding<MVKMTLSamplerStateBinding>(_resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty,
                                             [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                                                 [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setSamplerState: b.mtlSamplerState
																												   atIndex: b.index];
                                             });
}

void MVKComputeResourcesCommandEncoderState::resetImpl() {
	_resourceBindings.reset();
}


#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

void MVKOcclusionQueryCommandEncoderState::beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {

	_currentQuery.set(pQueryPool, query);

    NSUInteger offset = pQueryPool->getVisibilityResultOffset(query);
    NSUInteger maxOffset = _cmdEncoder->_pDeviceMetalFeatures->maxQueryBufferSize - kMVKQuerySlotSizeInBytes;

    bool shouldCount = _cmdEncoder->_pDeviceFeatures->occlusionQueryPrecise && mvkAreAllFlagsEnabled(flags, VK_QUERY_CONTROL_PRECISE_BIT);
    _mtlVisibilityResultMode = shouldCount ? MTLVisibilityResultModeCounting : MTLVisibilityResultModeBoolean;
    _mtlVisibilityResultOffset = min(offset, maxOffset);

    _visibilityResultMTLBuffer = pQueryPool->getVisibilityResultMTLBuffer();    // not retained

    markDirty();
}

void MVKOcclusionQueryCommandEncoderState::endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
	reset();
}

id<MTLBuffer> MVKOcclusionQueryCommandEncoderState::getVisibilityResultMTLBuffer() { return _visibilityResultMTLBuffer; }

void MVKOcclusionQueryCommandEncoderState::encodeImpl(uint32_t stage) {
	if (stage != kMVKGraphicsStageRasterization) { return; }

	// Metal does not allow a query to be run twice on a single render encoder.
	// If the query is active and was already used for the current Metal render encoder,
	// log an error and terminate the current query. Remember which MTLRenderEncoder
	// was used for this query to test for this situation on future queries.
	if (_mtlVisibilityResultMode != MTLVisibilityResultModeDisabled) {
		id<MTLRenderCommandEncoder> currMTLRendEnc = _cmdEncoder->_mtlRenderEncoder;
		if (currMTLRendEnc == _mtlEncodersUsed[_currentQuery]) {
			MVKLogError("vkCmdBeginQuery(): Metal does not support using the same occlusion query more than once within a single Vulkan render subpass.");
			resetImpl();
		}
		_mtlEncodersUsed[_currentQuery] = currMTLRendEnc;
	}

	[_cmdEncoder->_mtlRenderEncoder setVisibilityResultMode: _mtlVisibilityResultMode
													 offset: _mtlVisibilityResultOffset];
}

void MVKOcclusionQueryCommandEncoderState::resetImpl() {
	_currentQuery.reset();
    _visibilityResultMTLBuffer = _cmdEncoder->_cmdBuffer->_initialVisibilityResultMTLBuffer;
    _mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
    _mtlVisibilityResultOffset = 0;
}

MVKOcclusionQueryCommandEncoderState::MVKOcclusionQueryCommandEncoderState(MVKCommandEncoder* cmdEncoder)
        : MVKCommandEncoderState(cmdEncoder) {
    resetImpl();
}


