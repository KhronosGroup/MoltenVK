/*
 * MVKCommandEncoderState.mm
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

#include "MVKCommandEncoderState.h"
#include "MVKCommandEncodingPool.h"
#include "MVKCommandBuffer.h"
#include "MVKRenderPass.h"
#include "MVKPipeline.h"
#include "MVKQueryPool.h"

using namespace std;


#pragma mark -
#pragma mark MVKCommandEncoderState

MVKVulkanAPIObject* MVKCommandEncoderState::getVulkanAPIObject() { return _cmdEncoder->getVulkanAPIObject(); };
MVKDevice* MVKCommandEncoderState::getDevice() { return _cmdEncoder->getDevice(); }


#pragma mark -
#pragma mark MVKPipelineCommandEncoderState

void MVKPipelineCommandEncoderState::bindPipeline(MVKPipeline* pipeline) {
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


#pragma mark -
#pragma mark MVKViewportCommandEncoderState

void MVKViewportCommandEncoderState::setViewports(const MVKArrayRef<VkViewport> viewports,
												  uint32_t firstViewport,
												  bool isSettingDynamically) {

	size_t vpCnt = viewports.size;
	uint32_t maxViewports = getDevice()->_pProperties->limits.maxViewports;
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


#pragma mark -
#pragma mark MVKScissorCommandEncoderState

void MVKScissorCommandEncoderState::setScissors(const MVKArrayRef<VkRect2D> scissors,
                                                uint32_t firstScissor,
												bool isSettingDynamically) {

	size_t sCnt = scissors.size;
	uint32_t maxScissors = getDevice()->_pProperties->limits.maxViewports;
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


#pragma mark -
#pragma mark MVKPushConstantsCommandEncoderState

void MVKPushConstantsCommandEncoderState:: setPushConstants(uint32_t offset, MVKArrayRef<char> pushConstants) {
	// MSL structs can have a larger size than the equivalent C struct due to MSL alignment needs.
	// Typically any MSL struct that contains a float4 will also have a size that is rounded up to a multiple of a float4 size.
	// Ensure that we pass along enough content to cover this extra space even if it is never actually accessed by the shader.
	size_t pcSizeAlign = getDevice()->_pMetalFeatures->pushConstantSizeAlignment;
    size_t pcSize = pushConstants.size;
	size_t pcBuffSize = mvkAlignByteCount(offset + pcSize, pcSizeAlign);
    mvkEnsureSize(_pushConstants, pcBuffSize);
    copy(pushConstants.begin(), pushConstants.end(), _pushConstants.begin() + offset);
    if (pcBuffSize > 0) { markDirty(); }
}

void MVKPushConstantsCommandEncoderState::setMTLBufferIndex(uint32_t mtlBufferIndex, bool pipelineStageUsesPushConstants) {
	if ((mtlBufferIndex != _mtlBufferIndex) || (pipelineStageUsesPushConstants != _pipelineStageUsesPushConstants)) {
		_mtlBufferIndex = mtlBufferIndex;
		_pipelineStageUsesPushConstants = pipelineStageUsesPushConstants;
		markDirty();
	}
}

// At this point, I have been marked not-dirty, under the assumption that I will make changes to the encoder.
// However, some of the paths below decide not to actually make any changes to the encoder. In that case,
// I should remain dirty until I actually do make encoder changes.
void MVKPushConstantsCommandEncoderState::encodeImpl(uint32_t stage) {
    if ( !_pipelineStageUsesPushConstants || _pushConstants.empty() ) { return; }

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

    if ( !_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK) ) {
		stencilInfo.readMask = vkStencil.compareMask;
	}
    if ( !_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_WRITE_MASK) ) {
		stencilInfo.writeMask = vkStencil.writeMask;
	}
}

// We don't check for dynamic state here, because if this is called before pipeline is set,
// it may not be accurate, and if not dynamic, pipeline will override when it is encoded anyway.
void MVKDepthStencilCommandEncoderState::setStencilCompareMask(VkStencilFaceFlags faceMask,
                                                               uint32_t stencilCompareMask) {
    if (mvkAreAllFlagsEnabled(faceMask, VK_STENCIL_FACE_FRONT_BIT)) {
        _depthStencilData.frontFaceStencilData.readMask = stencilCompareMask;
    }
    if (mvkAreAllFlagsEnabled(faceMask, VK_STENCIL_FACE_BACK_BIT)) {
        _depthStencilData.backFaceStencilData.readMask = stencilCompareMask;
    }

    markDirty();
}

// We don't check for dynamic state here, because if this is called before pipeline is set,
// it may not be accurate, and if not dynamic, pipeline will override when it is encoded anyway.
void MVKDepthStencilCommandEncoderState::setStencilWriteMask(VkStencilFaceFlags faceMask,
                                                             uint32_t stencilWriteMask) {
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


#pragma mark -
#pragma mark MVKStencilReferenceValueCommandEncoderState

void MVKStencilReferenceValueCommandEncoderState:: setReferenceValues(const VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo) {

    // If ref values are to be set dynamically, don't set them here.
    if (_cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_STENCIL_REFERENCE)) { return; }

    _frontFaceValue = vkDepthStencilInfo.front.reference;
    _backFaceValue = vkDepthStencilInfo.back.reference;
    markDirty();
}

// We don't check for dynamic state here, because if this is called before pipeline is set,
// it may not be accurate, and if not dynamic, pipeline will override when it is encoded anyway.
void MVKStencilReferenceValueCommandEncoderState::setReferenceValues(VkStencilFaceFlags faceMask,
                                                                     uint32_t stencilReference) {
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

// We don't check for dynamic state here, because if this is called before pipeline is set,
// it may not be accurate, and if not dynamic, pipeline will override when it is encoded anyway.
void MVKDepthBiasCommandEncoderState::setDepthBias(float depthBiasConstantFactor,
                                                   float depthBiasSlopeFactor,
                                                   float depthBiasClamp) {
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


#pragma mark -
#pragma mark MVKBlendColorCommandEncoderState

void MVKBlendColorCommandEncoderState::setBlendColor(float red, float green,
                                                     float blue, float alpha,
                                                     bool isDynamic) {
    // Abort if we are using dynamic, but call is not dynamic.
	if ( !isDynamic && _cmdEncoder->supportsDynamicState(VK_DYNAMIC_STATE_BLEND_CONSTANTS) ) { return; }

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


#pragma mark -
#pragma mark MVKResourcesCommandEncoderState

void MVKResourcesCommandEncoderState::bindDescriptorSet(uint32_t descSetIndex,
														MVKDescriptorSet* descSet,
														MVKShaderResourceBinding& dslMTLRezIdxOffsets,
														MVKArrayRef<uint32_t> dynamicOffsets,
														uint32_t& dynamicOffsetIndex) {

	bool dsChanged = (descSet != _boundDescriptorSets[descSetIndex]);

	_boundDescriptorSets[descSetIndex] = descSet;

	if (descSet->isUsingMetalArgumentBuffers()) {
		// If the descriptor set has changed, track new resource usage.
		if (dsChanged) {
			auto& usageDirty = _metalUsageDirtyDescriptors[descSetIndex];
			usageDirty.resize(descSet->getDescriptorCount());
			usageDirty.setAllBits();
		}

		// Update dynamic buffer offsets
		uint32_t baseDynOfstIdx = dslMTLRezIdxOffsets.getMetalResourceIndexes().dynamicOffsetBufferIndex;
		uint32_t doCnt = descSet->getDynamicOffsetDescriptorCount();
		for (uint32_t doIdx = 0; doIdx < doCnt && dynamicOffsetIndex < dynamicOffsets.size; doIdx++) {
			updateImplicitBuffer(_dynamicOffsets, baseDynOfstIdx + doIdx, dynamicOffsets[dynamicOffsetIndex++]);
		}

		// If something changed, mark dirty
		if (dsChanged || doCnt > 0) { MVKCommandEncoderState::markDirty(); }
	}
}

// Encode the dirty descriptors to the Metal argument buffer, set the Metal command encoder
// usage for each resource, and bind the Metal argument buffer to the command encoder.
void MVKResourcesCommandEncoderState::encodeMetalArgumentBuffer(MVKShaderStage stage) {
	if ( !_cmdEncoder->isUsingMetalArgumentBuffers() ) { return; }

	bool useDescSetArgBuff = _cmdEncoder->isUsingDescriptorSetMetalArgumentBuffers();

	MVKPipeline* pipeline = getPipeline();
	uint32_t dsCnt = pipeline->getDescriptorSetCount();
	for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
		auto* descSet = _boundDescriptorSets[dsIdx];
		if ( !descSet ) { continue; }

		auto* dsLayout = descSet->getLayout();

		// The Metal arg encoder can only write to one arg buffer at a time (it holds the arg buffer),
		// so we need to lock out other access to it while we are writing to it.
		auto& mvkArgEnc = useDescSetArgBuff ? dsLayout->getMTLArgumentEncoder() : pipeline->getMTLArgumentEncoder(dsIdx, stage);
		lock_guard<mutex> lock(mvkArgEnc.mtlArgumentEncodingLock);

		id<MTLBuffer> mtlArgBuffer = nil;
		NSUInteger metalArgBufferOffset = 0;
		id<MTLArgumentEncoder> mtlArgEncoder = mvkArgEnc.getMTLArgumentEncoder();
		if (useDescSetArgBuff) {
			mtlArgBuffer = descSet->getMetalArgumentBuffer();
			metalArgBufferOffset = descSet->getMetalArgumentBufferOffset();
		} else {
			// TODO: Source a different arg buffer & offset for each pipeline-stage/desccriptors set
			// Also need to only encode the descriptors that are referenced in the shader.
			// MVKMTLArgumentEncoder could include an MVKBitArray to track that and have it checked below.
		}

		if ( !(mtlArgEncoder && mtlArgBuffer) ) { continue; }

		auto& argBuffDirtyDescs = descSet->getMetalArgumentBufferDirtyDescriptors();
		auto& resourceUsageDirtyDescs = _metalUsageDirtyDescriptors[dsIdx];
		auto& shaderBindingUsage = pipeline->getDescriptorBindingUse(dsIdx, stage);

		bool mtlArgEncAttached = false;
		bool shouldBindArgBuffToStage = false;
		uint32_t dslBindCnt = dsLayout->getBindingCount();
		for (uint32_t dslBindIdx = 0; dslBindIdx < dslBindCnt; dslBindIdx++) {
			auto* dslBind = dsLayout->getBindingAt(dslBindIdx);
			if (dslBind->getApplyToStage(stage) && shaderBindingUsage.getBit(dslBindIdx)) {
				shouldBindArgBuffToStage = true;
				uint32_t elemCnt = dslBind->getDescriptorCount(descSet);
				for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
					uint32_t descIdx = dslBind->getDescriptorIndex(elemIdx);
					bool argBuffDirty = argBuffDirtyDescs.getBit(descIdx, true);
					bool resourceUsageDirty = resourceUsageDirtyDescs.getBit(descIdx, true);
					if (argBuffDirty || resourceUsageDirty) {
						// Don't attach the arg buffer to the arg encoder unless something actually needs
						// to be written to it. We often might only be updating command encoder resource usage.
						if (!mtlArgEncAttached && argBuffDirty) {
							[mtlArgEncoder setArgumentBuffer: mtlArgBuffer offset: metalArgBufferOffset];
							mtlArgEncAttached = true;
						}
						auto* mvkDesc = descSet->getDescriptorAt(descIdx);
						mvkDesc->encodeToMetalArgumentBuffer(this, mtlArgEncoder,
															 dsIdx, dslBind, elemIdx,
															 stage, argBuffDirty, true);
					}
				}
			}
		}

		// If the arg buffer was attached to the arg encoder, detach it now.
		if (mtlArgEncAttached) { [mtlArgEncoder setArgumentBuffer: nil offset: 0]; }

		// If it is needed, bind the Metal argument buffer itself to the command encoder,
		if (shouldBindArgBuffToStage) {
			MVKMTLBufferBinding bb;
			bb.mtlBuffer = descSet->getMetalArgumentBuffer();
			bb.offset = descSet->getMetalArgumentBufferOffset();
			bb.index = dsIdx;
			bindMetalArgumentBuffer(stage, bb);
		}

		// For some unexpected reason, GPU capture on Xcode 12 doesn't always correctly expose
		// the contents of Metal argument buffers. Triggering an extraction of the arg buffer
		// contents here, after filling it, seems to correct that.
		// Sigh. A bug report has been filed with Apple.
		if (getDevice()->isCurrentlyAutoGPUCapturing()) { [descSet->getMetalArgumentBuffer() contents]; }
	}
}

// Mark the resource usage as needing an update for each Metal render encoder.
void MVKResourcesCommandEncoderState::markDirty() {
	MVKCommandEncoderState::markDirty();
	if (_cmdEncoder->isUsingMetalArgumentBuffers()) {
		for (uint32_t dsIdx = 0; dsIdx < kMVKMaxDescriptorSetCount; dsIdx++) {
			_metalUsageDirtyDescriptors[dsIdx].setAllBits();
		}
	}
}

// If a swizzle is needed for this stage, iterates all the bindings and logs errors for those that need texture swizzling.
void MVKResourcesCommandEncoderState::assertMissingSwizzles(bool needsSwizzle, const char* stageName, const MVKArrayRef<MVKMTLTextureBinding> texBindings) {
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

void MVKGraphicsResourcesCommandEncoderState::bindDynamicOffsetBuffer(const MVKShaderImplicitRezBinding& binding,
																	  bool needVertexDynamicOffsetBuffer,
																	  bool needTessCtlDynamicOffsetBuffer,
																	  bool needTessEvalDynamicOffsetBuffer,
																	  bool needFragmentDynamicOffsetBuffer) {
	for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
		_shaderStageResourceBindings[i].dynamicOffsetBufferBinding.index = binding.stages[i];
	}
	_shaderStageResourceBindings[kMVKShaderStageVertex].dynamicOffsetBufferBinding.isDirty = needVertexDynamicOffsetBuffer;
	_shaderStageResourceBindings[kMVKShaderStageTessCtl].dynamicOffsetBufferBinding.isDirty = needTessCtlDynamicOffsetBuffer;
	_shaderStageResourceBindings[kMVKShaderStageTessEval].dynamicOffsetBufferBinding.isDirty = needTessEvalDynamicOffsetBuffer;
	_shaderStageResourceBindings[kMVKShaderStageFragment].dynamicOffsetBufferBinding.isDirty = needFragmentDynamicOffsetBuffer;
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
                                                             std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&, const MVKArrayRef<uint32_t>)> bindImplicitBuffer,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLTextureBinding&)> bindTexture,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLSamplerStateBinding&)> bindSampler) {

	encodeMetalArgumentBuffer(stage);

    auto& shaderStage = _shaderStageResourceBindings[stage];

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

	if (shaderStage.dynamicOffsetBufferBinding.isDirty) {
		bindImplicitBuffer(_cmdEncoder, shaderStage.dynamicOffsetBufferBinding, _dynamicOffsets.contents());
	}

    if (shaderStage.viewRangeBufferBinding.isDirty) {
        MVKSmallVector<uint32_t, 2> viewRange;
        viewRange.push_back(_cmdEncoder->getSubpass()->getFirstViewIndexInMetalPass(_cmdEncoder->getMultiviewPassIndex()));
        viewRange.push_back(_cmdEncoder->getSubpass()->getViewCountInMetalPass(_cmdEncoder->getMultiviewPassIndex()));
        bindImplicitBuffer(_cmdEncoder, shaderStage.viewRangeBufferBinding, viewRange.contents());
    }

    encodeBinding<MVKMTLBufferBinding>(shaderStage.bufferBindings, shaderStage.areBufferBindingsDirty, bindBuffer);
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
	MVKResourcesCommandEncoderState::markDirty();
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].bufferBindings, _shaderStageResourceBindings[i].areBufferBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].textureBindings, _shaderStageResourceBindings[i].areTextureBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].samplerStateBindings, _shaderStageResourceBindings[i].areSamplerStateBindingsDirty);
    }
}

void MVKGraphicsResourcesCommandEncoderState::encodeImpl(uint32_t stage) {

    MVKGraphicsPipeline* pipeline = (MVKGraphicsPipeline*)getPipeline();
    bool fullImageViewSwizzle = pipeline->fullImageViewSwizzle() || getDevice()->_pMetalFeatures->nativeTextureSwizzle;
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
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t> s)->void {
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
                           // The app may have bound more vertex attribute buffers than used by the pipeline.
                           // We must not bind those extra buffers to the shader because they might overwrite
                           // any implicit buffers used by the pipeline.
                           if (pipeline->isValidVertexBufferIndex(kMVKShaderStageVertex, b.index)) {
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
                           } else {
                               b.isDirty = true;	// We haven't written it out, so leave dirty until next time.
						   }
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t> s)->void {
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
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t> s)->void {
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
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t> s)->void {
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
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, const MVKArrayRef<uint32_t> s)->void {
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

MVKPipeline* MVKGraphicsResourcesCommandEncoderState::getPipeline() {
	return _cmdEncoder->_graphicsPipelineState.getPipeline();
}

void MVKGraphicsResourcesCommandEncoderState::bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) {
	bindBuffer(stage, buffBind);
}

void MVKGraphicsResourcesCommandEncoderState::encodeArgumentBufferResourceUsage(MVKShaderStage stage,
																				id<MTLResource> mtlResource,
																				MTLResourceUsage mtlUsage,
																				MTLRenderStages mtlStages) {
	if (mtlResource && mtlStages) {
		if (stage == kMVKShaderStageTessCtl) {
			auto* mtlCompEnc = _cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
			[mtlCompEnc useResource: mtlResource usage: mtlUsage];
		} else {
			auto* mtlRendEnc = _cmdEncoder->_mtlRenderEncoder;
			if ([mtlRendEnc respondsToSelector: @selector(useResource:usage:stages:)]) {
				[mtlRendEnc useResource: mtlResource usage: mtlUsage stages: mtlStages];
			} else {
				[mtlRendEnc useResource: mtlResource usage: mtlUsage];
			}
		}
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

void MVKComputeResourcesCommandEncoderState::bindDynamicOffsetBuffer(const MVKShaderImplicitRezBinding& binding,
																	 bool needDynamicOffsetBuffer) {
	_resourceBindings.dynamicOffsetBufferBinding.index = binding.stages[kMVKShaderStageCompute];
	_resourceBindings.dynamicOffsetBufferBinding.isDirty = needDynamicOffsetBuffer;
}

// Mark everything as dirty
void MVKComputeResourcesCommandEncoderState::markDirty() {
    MVKResourcesCommandEncoderState::markDirty();
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::encodeImpl(uint32_t) {

	encodeMetalArgumentBuffer(kMVKShaderStageCompute);

    MVKPipeline* pipeline = getPipeline();
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

	if (_resourceBindings.dynamicOffsetBufferBinding.isDirty) {
		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
									 _dynamicOffsets.data(),
									 _dynamicOffsets.size() * sizeof(uint32_t),
									 _resourceBindings.dynamicOffsetBufferBinding.index);

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

MVKPipeline* MVKComputeResourcesCommandEncoderState::getPipeline() {
	return _cmdEncoder->_computePipelineState.getPipeline();
}

void MVKComputeResourcesCommandEncoderState::bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) {
	bindBuffer(buffBind);
}

void MVKComputeResourcesCommandEncoderState::encodeArgumentBufferResourceUsage(MVKShaderStage stage,
																			   id<MTLResource> mtlResource,
																			   MTLResourceUsage mtlUsage,
																			   MTLRenderStages mtlStages) {
	if (mtlResource) {
		auto* mtlCompEnc = _cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch);
		[mtlCompEnc useResource: mtlResource usage: mtlUsage];
	}
}


#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

void MVKOcclusionQueryCommandEncoderState::endMetalRenderPass() {
	const MVKMTLBufferAllocation* vizBuff = _cmdEncoder->_pEncodingContext->visibilityResultBuffer;
    if ( !vizBuff || _mtlRenderPassQueries.empty() ) { return; }  // Nothing to do.

	id<MTLComputePipelineState> mtlAccumState = _cmdEncoder->getCommandEncodingPool()->getAccumulateOcclusionQueryResultsMTLComputePipelineState();
    id<MTLComputeCommandEncoder> mtlAccumEncoder = _cmdEncoder->getMTLComputeEncoder(kMVKCommandUseAccumOcclusionQuery);
    [mtlAccumEncoder setComputePipelineState: mtlAccumState];
    for (auto& qryLoc : _mtlRenderPassQueries) {
        // Accumulate the current results to the query pool's buffer.
        [mtlAccumEncoder setBuffer: qryLoc.queryPool->getVisibilityResultMTLBuffer()
                            offset: qryLoc.queryPool->getVisibilityResultOffset(qryLoc.query)
                           atIndex: 0];
        [mtlAccumEncoder setBuffer: vizBuff->_mtlBuffer
                            offset: vizBuff->_offset + qryLoc.visibilityBufferOffset
                           atIndex: 1];
        [mtlAccumEncoder dispatchThreadgroups: MTLSizeMake(1, 1, 1)
                        threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
    }
    _cmdEncoder->endCurrentMetalEncoding();
    _mtlRenderPassQueries.clear();
}

// The Metal visibility buffer has a finite size, and on some Metal platforms (looking at you M1),
// query offsets cannnot be reused with the same MTLCommandBuffer. If enough occlusion queries are
// begun within a single MTLCommandBuffer, it may exhaust the visibility buffer. If that occurs,
// report an error and disable further visibility tracking for the remainder of the MTLCommandBuffer.
// In most cases, a MTLCommandBuffer corresponds to a Vulkan command submit (VkSubmitInfo),
// and so the error text is framed in terms of the Vulkan submit.
void MVKOcclusionQueryCommandEncoderState::beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
	if (_cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset + kMVKQuerySlotSizeInBytes <= _cmdEncoder->_pDeviceMetalFeatures->maxQueryBufferSize) {
		bool shouldCount = _cmdEncoder->_pDeviceFeatures->occlusionQueryPrecise && mvkAreAllFlagsEnabled(flags, VK_QUERY_CONTROL_PRECISE_BIT);
		_mtlVisibilityResultMode = shouldCount ? MTLVisibilityResultModeCounting : MTLVisibilityResultModeBoolean;
		_mtlRenderPassQueries.emplace_back(pQueryPool, query, _cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset);
	} else {
		reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCmdBeginQuery(): The maximum number of queries in a single Vulkan command submission is %llu.", _cmdEncoder->_pDeviceMetalFeatures->maxQueryBufferSize / kMVKQuerySlotSizeInBytes);
		_mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
		_cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset -= kMVKQuerySlotSizeInBytes;
	}
    markDirty();
}

void MVKOcclusionQueryCommandEncoderState::endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
	_mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
	_cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset += kMVKQuerySlotSizeInBytes;
	markDirty();
}

void MVKOcclusionQueryCommandEncoderState::encodeImpl(uint32_t stage) {
	if (stage != kMVKGraphicsStageRasterization) { return; }

	[_cmdEncoder->_mtlRenderEncoder setVisibilityResultMode: _mtlVisibilityResultMode
													 offset: _cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset];
}
