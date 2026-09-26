/*
 * MVKCmdRendering.mm
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCmdRendering.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKFramebuffer.h"
#include "MVKRenderPass.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"


/**
 * Writes a value into the pipeline state a shader object draw is built from, and drops any
 * pipeline already resolved for the old value. A write that changes nothing is left alone, so
 * that re-setting the same state before every draw costs nothing.
 */
template <typename T, typename V>
static void mvkSetDynamicPipelineState(MVKCommandEncoder* cmdEncoder, T& field, V value) {
	T newValue = static_cast<T>(value);
	if (field == newValue) { return; }
	field = newValue;
	cmdEncoder->getState().invalidateShaderObjectPipeline();
}


#pragma mark -
#pragma mark MVKCmdBeginRenderPassBase

VkResult MVKCmdBeginRenderPassBase::setContent(MVKCommandBuffer* cmdBuff,
											   const VkRenderPassBeginInfo* pRenderPassBegin,
											   const VkSubpassBeginInfo* pSubpassBeginInfo) {
	_contents = pSubpassBeginInfo->contents;
	_renderPass = (MVKRenderPass*)pRenderPassBegin->renderPass;
	_framebuffer = (MVKFramebuffer*)pRenderPassBegin->framebuffer;
	_renderArea = pRenderPassBegin->renderArea;

	cmdBuff->_currentSubpassInfo.beginRenderpass(_renderPass);
	cmdBuff->_shaderObjectRecordState.setAttachmentsFromSubpass(_renderPass->getSubpass(0));

	return VK_SUCCESS;
}


#pragma mark -
#pragma mark MVKCmdBeginRenderPass

template <size_t N_CV, size_t N_A>
VkResult MVKCmdBeginRenderPass<N_CV, N_A>::setContent(MVKCommandBuffer* cmdBuff,
													  const VkRenderPassBeginInfo* pRenderPassBegin,
													  const VkSubpassBeginInfo* pSubpassBeginInfo,
													  MVKArrayRef<MVKImageView*> attachments) {
	MVKCmdBeginRenderPassBase::setContent(cmdBuff, pRenderPassBegin, pSubpassBeginInfo);

	_attachments.assign(attachments.begin(), attachments.end());
	_clearValues.assign(pRenderPassBegin->pClearValues,
						pRenderPassBegin->pClearValues + pRenderPassBegin->clearValueCount);

	return VK_SUCCESS;
}

template <size_t N_CV, size_t N_A>
void MVKCmdBeginRenderPass<N_CV, N_A>::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->beginRenderpass(this,
								_contents,
								_renderPass,
								_framebuffer,
								_renderArea,
								_clearValues.contents(),
								_attachments.contents(),
								kMVKCommandUseBeginRenderPass);
}

template class MVKCmdBeginRenderPass<1, 0>;
template class MVKCmdBeginRenderPass<2, 0>;
template class MVKCmdBeginRenderPass<9, 0>;

template class MVKCmdBeginRenderPass<1, 1>;
template class MVKCmdBeginRenderPass<2, 1>;
template class MVKCmdBeginRenderPass<9, 1>;

template class MVKCmdBeginRenderPass<1, 2>;
template class MVKCmdBeginRenderPass<2, 2>;
template class MVKCmdBeginRenderPass<9, 2>;

template class MVKCmdBeginRenderPass<1, 9>;
template class MVKCmdBeginRenderPass<2, 9>;
template class MVKCmdBeginRenderPass<9, 9>;

#pragma mark -
#pragma mark MVKCmdNextSubpass

VkResult MVKCmdNextSubpass::setContent(MVKCommandBuffer* cmdBuff,
									   VkSubpassContents contents) {
	_contents = contents;

	cmdBuff->_currentSubpassInfo.nextSubpass();
	if (cmdBuff->_currentSubpassInfo.renderpass) {
		cmdBuff->_shaderObjectRecordState.setAttachmentsFromSubpass(cmdBuff->_currentSubpassInfo.renderpass->getSubpass(cmdBuff->_currentSubpassInfo.subpassIndex));
	}

	return VK_SUCCESS;
}

VkResult MVKCmdNextSubpass::setContent(MVKCommandBuffer* cmdBuff,
									   const VkSubpassBeginInfo* pBeginSubpassInfo,
									   const VkSubpassEndInfo* pEndSubpassInfo) {
	return setContent(cmdBuff, pBeginSubpassInfo->contents);
}

void MVKCmdNextSubpass::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->beginNextSubpass(this, _contents);
}


#pragma mark -
#pragma mark MVKCmdEndRenderPass

VkResult MVKCmdEndRenderPass::setContent(MVKCommandBuffer* cmdBuff) {
	cmdBuff->_currentSubpassInfo = {};
	return VK_SUCCESS;
}

VkResult MVKCmdEndRenderPass::setContent(MVKCommandBuffer* cmdBuff,
										 const VkSubpassEndInfo* pEndSubpassInfo) {
	return setContent(cmdBuff);
}

void MVKCmdEndRenderPass::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->endRenderpass();
}


#pragma mark -
#pragma mark MVKCmdBeginRendering

template <size_t N>
VkResult MVKCmdBeginRendering<N>::setContent(MVKCommandBuffer* cmdBuff,
											 const VkRenderingInfo* pRenderingInfo) {
	_renderingInfo = *pRenderingInfo;

	// Copy attachments content, redirect info pointers to copied content, and remove any stale pNext refs
	_colorAttachments.assign(_renderingInfo.pColorAttachments,
							 _renderingInfo.pColorAttachments + _renderingInfo.colorAttachmentCount);
	_renderingInfo.pColorAttachments = _colorAttachments.data();
	for (auto caAtt : _colorAttachments) { caAtt.pNext = nullptr; }

	if (mvkSetOrClear(&_depthAttachment, _renderingInfo.pDepthAttachment)) {
		_renderingInfo.pDepthAttachment = &_depthAttachment;
	}
	if (mvkSetOrClear(&_stencilAttachment, _renderingInfo.pStencilAttachment)) {
		_renderingInfo.pStencilAttachment = &_stencilAttachment;
	}

	cmdBuff->_currentSubpassInfo.beginRendering(pRenderingInfo->viewMask);
	cmdBuff->_shaderObjectRecordState.setAttachmentsFromRenderingInfo(pRenderingInfo);

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdBeginRendering<N>::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->beginRendering(this, &_renderingInfo);
}

template class MVKCmdBeginRendering<1>;
template class MVKCmdBeginRendering<2>;
template class MVKCmdBeginRendering<4>;
template class MVKCmdBeginRendering<8>;


#pragma mark -
#pragma mark MVKCmdSetRenderingAttachmentLocations

// Resize dst to count, then if pSrc is not null, populate dst from it,
// otherwise fill dst with ascending values starting at zero.
template<typename Vec>
void mvkPopulateFromOrFillAscending(Vec& dst, const uint32_t* pSrc, size_t count) {
	dst.resize(count);
	for (uint32_t i = 0; i < count; i++) { dst[i] = pSrc ? pSrc[i] : i; }
}

VkResult MVKCmdSetRenderingAttachmentLocations::setContent(MVKCommandBuffer* cmdBuff,
														   const VkRenderingAttachmentLocationInfo* pLocationInfo) {
	mvkPopulateFromOrFillAscending(_colorAttachmentLocations,
								   pLocationInfo->pColorAttachmentLocations,
								   pLocationInfo->colorAttachmentCount);
	return VK_SUCCESS;
}

void MVKCmdSetRenderingAttachmentLocations::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->updateColorAttachmentLocations(_colorAttachmentLocations.contents());
}


#pragma mark -
#pragma mark MVKCmdSetRenderingInputAttachmentIndices

VkResult MVKCmdSetRenderingInputAttachmentIndices::setContent(MVKCommandBuffer* cmdBuff,
															  const VkRenderingInputAttachmentIndexInfo* pInputAttachmentIndexInfo) {
	mvkPopulateFromOrFillAscending(_colorAttachmentInputIndices,
								   pInputAttachmentIndexInfo->pColorAttachmentInputIndices,
								   pInputAttachmentIndexInfo->colorAttachmentCount);

	_hasDepthInputAttachmentIndex = pInputAttachmentIndexInfo->pDepthInputAttachmentIndex;
	_depthInputAttachmentIndex = _hasDepthInputAttachmentIndex ? *pInputAttachmentIndexInfo->pDepthInputAttachmentIndex : 0;

	_hasStencilInputAttachmentIndex = pInputAttachmentIndexInfo->pStencilInputAttachmentIndex;
	_stencilInputAttachmentIndex = _hasStencilInputAttachmentIndex ? *pInputAttachmentIndexInfo->pStencilInputAttachmentIndex : 0;

	return VK_SUCCESS;
}

void MVKCmdSetRenderingInputAttachmentIndices::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->updateAttachmentInputIndices(_colorAttachmentInputIndices.contents(),
											 _hasDepthInputAttachmentIndex ? &_depthInputAttachmentIndex : nullptr,
											 _hasStencilInputAttachmentIndex ? &_stencilInputAttachmentIndex : nullptr);
}


#pragma mark -
#pragma mark MVKCmdEndRendering

VkResult MVKCmdEndRendering::setContent(MVKCommandBuffer* cmdBuff) {
	cmdBuff->_currentSubpassInfo = {};
	return VK_SUCCESS;
}

void MVKCmdEndRendering::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->endRendering();
}


#pragma mark -
#pragma mark MVKCmdSetSampleLocations

VkResult MVKCmdSetSampleLocations::setContent(MVKCommandBuffer* cmdBuff,
											  const VkSampleLocationsInfoEXT* pSampleLocationsInfo) {
	_sampleLocations.clear();
	for (uint32_t slIdx = 0; slIdx < pSampleLocationsInfo->sampleLocationsCount; slIdx++) {
		_sampleLocations.push_back(pSampleLocationsInfo->pSampleLocations[slIdx]);
	}
	return VK_SUCCESS;
}

void MVKCmdSetSampleLocations::encode(MVKCommandEncoder* cmdEncoder) {
	size_t count = std::min<size_t>(_sampleLocations.size(), kMVKMaxSampleCount);
	MVKVulkanGraphicsCommandEncoderState& state = cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::SampleLocations);
	state._renderState.numSampleLocations = static_cast<uint8_t>(count);
	MTLSamplePosition* write = state._sampleLocations;
	for (size_t i = 0; i < count; i++) {
		write[i] = MTLSamplePositionMake(
			mvkClamp(_sampleLocations[i].x, kMVKMinSampleLocationCoordinate, kMVKMaxSampleLocationCoordinate),
			mvkClamp(_sampleLocations[i].y, kMVKMinSampleLocationCoordinate, kMVKMaxSampleLocationCoordinate));
	}
}


#pragma mark -
#pragma mark MVKCmdSetSampleLocationsEnable

void MVKCmdSetSampleLocationsEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::SampleLocationsEnable)._renderState.enable.set(MVKRenderStateEnableFlag::SampleLocations, _value);
}


#pragma mark -
#pragma mark MVKCmdSetViewport

template <size_t N>
VkResult MVKCmdSetViewport<N>::setContent(MVKCommandBuffer* cmdBuff,
										  uint32_t firstViewport,
										  uint32_t viewportCount,
										  const VkViewport* pViewports) {
	_firstViewport = firstViewport;
	_viewports.clear();
	_viewports.reserve(viewportCount);
	for (uint32_t vpIdx = 0; vpIdx < viewportCount; vpIdx++) {
		_viewports.push_back(pViewports[vpIdx]);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdSetViewport<N>::encode(MVKCommandEncoder* cmdEncoder) {
	uint32_t end = std::min(_firstViewport + static_cast<uint32_t>(_viewports.size()), kMVKMaxViewportScissorCount);
	MVKVulkanGraphicsCommandEncoderState& state = cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::Viewports);
	state._renderState.numViewports = std::max(static_cast<uint8_t>(end), cmdEncoder->getVkGraphics()._renderState.numViewports);
	for (uint32_t i = _firstViewport; i < end; i++)
		state._viewports[i] = _viewports[i - _firstViewport];
}

template class MVKCmdSetViewport<1>;
template class MVKCmdSetViewport<kMVKMaxViewportScissorCount>;


#pragma mark -
#pragma mark MVKCmdSetScissor

template <size_t N>
VkResult MVKCmdSetScissor<N>::setContent(MVKCommandBuffer* cmdBuff,
										 uint32_t firstScissor,
										 uint32_t scissorCount,
										 const VkRect2D* pScissors) {
	_firstScissor = firstScissor;
	_scissors.clear();
	_scissors.reserve(scissorCount);
	for (uint32_t sIdx = 0; sIdx < scissorCount; sIdx++) {
		_scissors.push_back(pScissors[sIdx]);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdSetScissor<N>::encode(MVKCommandEncoder* cmdEncoder) {
	uint32_t end = std::min(_firstScissor + static_cast<uint32_t>(_scissors.size()), kMVKMaxViewportScissorCount);
	MVKVulkanGraphicsCommandEncoderState& state = cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::Scissors);
	state._renderState.numScissors = std::max(static_cast<uint8_t>(end), cmdEncoder->getVkGraphics()._renderState.numScissors);
	for (uint32_t i = _firstScissor; i < end; i++)
		state._scissors[i] = _scissors[i - _firstScissor];
}

template class MVKCmdSetScissor<1>;
template class MVKCmdSetScissor<kMVKMaxViewportScissorCount>;


#pragma mark -
#pragma mark MVKCmdSetDepthBias

void MVKCmdSetDepthBias::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::DepthBias)._renderState.depthBias = _value;
}


#pragma mark -
#pragma mark MVKCmdSetDepthBiasEnable

void MVKCmdSetDepthBiasEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::DepthBiasEnable)._renderState.enable.set(MVKRenderStateEnableFlag::DepthBias, _value);
}


#pragma mark -
#pragma mark MVKCmdSetBlendConstants

void MVKCmdSetBlendConstants::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::BlendConstants)._renderState.blendConstants = _value;
}


#pragma mark -
#pragma mark MVKCmdSetDepthTestEnable

void MVKCmdSetDepthTestEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::DepthTestEnable)._renderState.enable.set(MVKRenderStateEnableFlag::DepthTest, _value);
}


#pragma mark -
#pragma mark MVKCmdSetDepthWriteEnable

void MVKCmdSetDepthWriteEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::DepthWriteEnable)._renderState.depthStencil.depthWriteEnabled = _value;
}


#pragma mark -
#pragma mark MVKCmdSetDepthClipEnable

void MVKCmdSetDepthClipEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::DepthClipEnable)._renderState.enable.set(MVKRenderStateEnableFlag::DepthClamp, !_value);
}


#pragma mark -
#pragma mark MVKCmdSetDepthCompareOp

void MVKCmdSetDepthCompareOp::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::DepthCompareOp)._renderState.depthStencil.depthCompareFunction = _value;
}


#pragma mark -
#pragma mark MVKCmdSetDepthBounds

void MVKCmdSetDepthBounds::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::DepthBounds)._renderState.depthBounds = _value;
}


#pragma mark -
#pragma mark MVKCmdSetDepthBoundsTestEnable

void MVKCmdSetDepthBoundsTestEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::DepthBoundsTestEnable)._renderState.enable.set(MVKRenderStateEnableFlag::DepthBoundsTest, _value);
}


#pragma mark -
#pragma mark MVKCmdSetStencilTestEnable

void MVKCmdSetStencilTestEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::StencilTestEnable)._renderState.depthStencil.stencilTestEnabled = _value;
}


#pragma mark -
#pragma mark MVKCmdSetStencilOp

VkResult MVKCmdSetStencilOp::setContent(MVKCommandBuffer* cmdBuff,
										VkStencilFaceFlags faceMask,
										VkStencilOp failOp,
										VkStencilOp passOp,
										VkStencilOp depthFailOp,
										VkCompareOp compareOp) {
	_faceMask = faceMask;
	_failOp = failOp;
	_passOp = passOp;
	_depthFailOp = depthFailOp;
	_compareOp = compareOp;
	return VK_SUCCESS;
}

void MVKCmdSetStencilOp::encode(MVKCommandEncoder* cmdEncoder) {
	MVKMTLStencilOps op;
	op.stencilCompareFunction = mvkMTLCompareFunctionFromVkCompareOp(_compareOp);
	op.stencilFailureOperation = mvkMTLStencilOperationFromVkStencilOp(_failOp);
	op.depthFailureOperation = mvkMTLStencilOperationFromVkStencilOp(_depthFailOp);
	op.depthStencilPassOperation = mvkMTLStencilOperationFromVkStencilOp(_passOp);
	MVKVulkanGraphicsCommandEncoderState& state = cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::StencilOp);
	if (_faceMask & VK_STENCIL_FACE_FRONT_BIT)
		state._renderState.depthStencil.frontFaceStencilData.op = op;
	if (_faceMask & VK_STENCIL_FACE_BACK_BIT)
		state._renderState.depthStencil.backFaceStencilData.op = op;
}


#pragma mark -
#pragma mark MVKCmdSetStencilCompareMask

VkResult MVKCmdSetStencilCompareMask::setContent(MVKCommandBuffer* cmdBuff,
												 VkStencilFaceFlags faceMask,
												 uint32_t stencilCompareMask) {
    _faceMask = faceMask;
    _stencilCompareMask = stencilCompareMask;

	return VK_SUCCESS;
}

void MVKCmdSetStencilCompareMask::encode(MVKCommandEncoder* cmdEncoder) {
	MVKVulkanGraphicsCommandEncoderState& state = cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::StencilCompareMask);
	if (_faceMask & VK_STENCIL_FACE_FRONT_BIT)
		state._renderState.depthStencil.frontFaceStencilData.readMask = _stencilCompareMask;
	if (_faceMask & VK_STENCIL_FACE_BACK_BIT)
		state._renderState.depthStencil.backFaceStencilData.readMask = _stencilCompareMask;
}


#pragma mark -
#pragma mark MVKCmdSetStencilWriteMask

VkResult MVKCmdSetStencilWriteMask::setContent(MVKCommandBuffer* cmdBuff,
											   VkStencilFaceFlags faceMask,
											   uint32_t stencilWriteMask) {
    _faceMask = faceMask;
    _stencilWriteMask = stencilWriteMask;

	return VK_SUCCESS;
}

void MVKCmdSetStencilWriteMask::encode(MVKCommandEncoder* cmdEncoder) {
	MVKVulkanGraphicsCommandEncoderState& state = cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::StencilWriteMask);
	if (_faceMask & VK_STENCIL_FACE_FRONT_BIT)
		state._renderState.depthStencil.frontFaceStencilData.writeMask = _stencilWriteMask;
	if (_faceMask & VK_STENCIL_FACE_BACK_BIT)
		state._renderState.depthStencil.backFaceStencilData.writeMask = _stencilWriteMask;
}


#pragma mark -
#pragma mark MVKCmdSetStencilReference

VkResult MVKCmdSetStencilReference::setContent(MVKCommandBuffer* cmdBuff,
											   VkStencilFaceFlags faceMask,
											   uint32_t stencilReference) {
    _faceMask = faceMask;
    _stencilReference = stencilReference;

	return VK_SUCCESS;
}

void MVKCmdSetStencilReference::encode(MVKCommandEncoder* cmdEncoder) {
	MVKVulkanGraphicsCommandEncoderState& state = cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::StencilReference);
	if (_faceMask & VK_STENCIL_FACE_FRONT_BIT)
		state._renderState.stencilReference.frontFaceValue = _stencilReference;
	if (_faceMask & VK_STENCIL_FACE_BACK_BIT)
		state._renderState.stencilReference.backFaceValue = _stencilReference;
}


#pragma mark -
#pragma mark MVKCmdSetCullMode

void MVKCmdSetCullMode::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::CullMode)._renderState.setCullMode(_value);
}


#pragma mark -
#pragma mark MVKCmdSetFrontFace

void MVKCmdSetFrontFace::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::FrontFace)._renderState.setFrontFace(_value);
}


#pragma mark -
#pragma mark MVKCmdSetPatchControlPoints

void MVKCmdSetPatchControlPoints::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::PatchControlPoints)._renderState.patchControlPoints = static_cast<uint8_t>(_value);
}


#pragma mark -
#pragma mark MVKCmdSetPolygonMode

void MVKCmdSetPolygonMode::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::PolygonMode)._renderState.setPolygonMode(_value);
}


#pragma mark -
#pragma mark MVKCmdSetLineRasterizationMode

void MVKCmdSetLineRasterizationMode::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::LineRasterizationMode)._renderState.setLineRasterizationMode(_value);
}


#pragma mark -
#pragma mark MVKCmdSetLineWidth

void MVKCmdSetLineWidth::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::LineWidth)._renderState.lineWidth = _value;
}


#pragma mark -
#pragma mark MVKCmdSetPrimitiveTopology

void MVKCmdSetPrimitiveTopology::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::PrimitiveTopology)._renderState.primitiveType = mvkMTLPrimitiveTypeFromVkPrimitiveTopology(_value);
	// Metal bakes the topology class into a pipeline, so a shader object draw needs the Vulkan
	// topology itself, which the Metal primitive type above does not preserve.
	mvkSetDynamicPipelineState(cmdEncoder, cmdEncoder->getState().dynamicPipelineState().topology, mvkShaderObjectKeyTopology(_value));
}


#pragma mark -
#pragma mark MVKCmdSetPrimitiveRestartEnable

void MVKCmdSetPrimitiveRestartEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::PrimitiveRestartEnable)._renderState.enable.set(MVKRenderStateEnableFlag::PrimitiveRestart, _value);
}


#pragma mark -
#pragma mark MVKCmdSetRasterizerDiscardEnable

void MVKCmdSetRasterizerDiscardEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::RasterizerDiscardEnable)._renderState.enable.set(MVKRenderStateEnableFlag::RasterizerDiscard, _value);
}


#pragma mark -
#pragma mark MVKCmdSetProvokingVertexMode

void MVKCmdSetProvokingVertexMode::encode(MVKCommandEncoder* cmdEncoder) {
#if MVK_USE_METAL_PRIVATE_API
	cmdEncoder->getState().updateDynamicState(MVKRenderStateFlag::ProvokingVertexMode)._renderState.provokingVertexMode = mvkMTLProvokingVertexModeFromVkProvokingVertexMode(_value);
#endif
}



#pragma mark -
#pragma mark MVKCmdBindShaders

VkResult MVKCmdBindShaders::setContent(MVKCommandBuffer* cmdBuff,
									   uint32_t stageCount,
									   const VkShaderStageFlagBits* pStages,
									   const VkShaderEXT* pShaders) {
	_shaders.clear();
	_shaders.reserve(stageCount);
	for (uint32_t i = 0; i < stageCount; i++) {
		// pShaders may be null, which unbinds every stage named in pStages.
		MVKShader* shader = pShaders ? (MVKShader*)pShaders[i] : nullptr;
		_shaders.push_back({ pStages[i], shader });
		// Only the graphics stages MoltenVK has feed the shadow; the encoder reports the others.
		switch (pStages[i]) {
			case VK_SHADER_STAGE_VERTEX_BIT:					cmdBuff->_shaderObjectRecordState.shaders[kMVKShaderStageVertex] = shader; break;
			case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:		cmdBuff->_shaderObjectRecordState.shaders[kMVKShaderStageTessCtl] = shader; break;
			case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:	cmdBuff->_shaderObjectRecordState.shaders[kMVKShaderStageTessEval] = shader; break;
			case VK_SHADER_STAGE_FRAGMENT_BIT:					cmdBuff->_shaderObjectRecordState.shaders[kMVKShaderStageFragment] = shader; break;
			default: break;
		}
	}
	return VK_SUCCESS;
}

void MVKCmdBindShaders::encode(MVKCommandEncoder* cmdEncoder) {
	for (auto& stageShader : _shaders) {
		VkShaderStageFlagBits stage = stageShader.first;
		MVKShader* shader = stageShader.second;
		cmdEncoder->getState().bindShaders(1, &stage, &shader);
	}
}


#pragma mark -
#pragma mark MVKCmdSetVertexInput

VkResult MVKCmdSetVertexInput::setContent(MVKCommandBuffer* cmdBuff,
										  uint32_t vertexBindingDescriptionCount,
										  const VkVertexInputBindingDescription2EXT* pVertexBindingDescriptions,
										  uint32_t vertexAttributeDescriptionCount,
										  const VkVertexInputAttributeDescription2EXT* pVertexAttributeDescriptions) {
	_bindings.clear();
	_bindings.reserve(vertexBindingDescriptionCount);
	for (uint32_t i = 0; i < vertexBindingDescriptionCount; i++) {
		const auto& vb = pVertexBindingDescriptions[i];
		_bindings.push_back({ vb.binding, vb.stride, vb.divisor, (uint32_t)vb.inputRate });
	}

	_attributes.clear();
	_attributes.reserve(vertexAttributeDescriptionCount);
	for (uint32_t i = 0; i < vertexAttributeDescriptionCount; i++) {
		const auto& va = pVertexAttributeDescriptions[i];
		_attributes.push_back({ va.location, va.binding, (uint32_t)va.format, va.offset });
	}

	auto& rsVI = cmdBuff->_shaderObjectRecordState.vertexInput;
	memset(&rsVI, 0, sizeof(rsVI));
	rsVI.bindingCount = std::min((uint32_t)_bindings.size(), kMVKMaxVertexInputBindingCount);
	rsVI.attributeCount = std::min((uint32_t)_attributes.size(), kMVKMaxVertexInputAttributeCount);
	for (uint32_t i = 0; i < rsVI.bindingCount; i++) { rsVI.bindings[i] = _bindings[i]; }
	for (uint32_t i = 0; i < rsVI.attributeCount; i++) { rsVI.attributes[i] = _attributes[i]; }
	return VK_SUCCESS;
}

void MVKCmdSetVertexInput::encode(MVKCommandEncoder* cmdEncoder) {
	// Zeroed so that the unused tail compares equal between two calls that set the same layout.
	MVKDynamicVertexInput vtxInput;
	memset(&vtxInput, 0, sizeof(vtxInput));
	vtxInput.bindingCount = std::min((uint32_t)_bindings.size(), kMVKMaxVertexInputBindingCount);
	vtxInput.attributeCount = std::min((uint32_t)_attributes.size(), kMVKMaxVertexInputAttributeCount);
	for (uint32_t i = 0; i < vtxInput.bindingCount; i++) { vtxInput.bindings[i] = _bindings[i]; }
	for (uint32_t i = 0; i < vtxInput.attributeCount; i++) { vtxInput.attributes[i] = _attributes[i]; }
	vtxInput.stridesFromVertexBuffers = 0;		// This call is now the most recent to set the stride.

	cmdEncoder->getState().setVertexInput(vtxInput);
}


#pragma mark -
#pragma mark MVKCmdSetRasterizationSamples

void MVKCmdSetRasterizationSamples::encode(MVKCommandEncoder* cmdEncoder) {
	mvkSetDynamicPipelineState(cmdEncoder, cmdEncoder->getState().dynamicPipelineState().rasterizationSamples, _value);
}


#pragma mark -
#pragma mark MVKCmdSetAlphaToCoverageEnable

void MVKCmdSetAlphaToCoverageEnable::encode(MVKCommandEncoder* cmdEncoder) {
	mvkSetDynamicPipelineState(cmdEncoder, cmdEncoder->getState().dynamicPipelineState().alphaToCoverageEnable, _value ? 1 : 0);
}


#pragma mark -
#pragma mark MVKCmdSetAlphaToOneEnable

void MVKCmdSetAlphaToOneEnable::encode(MVKCommandEncoder* cmdEncoder) {
	mvkSetDynamicPipelineState(cmdEncoder, cmdEncoder->getState().dynamicPipelineState().alphaToOneEnable, _value ? 1 : 0);
}


#pragma mark -
#pragma mark MVKCmdSetLogicOpEnable

void MVKCmdSetLogicOpEnable::encode(MVKCommandEncoder* cmdEncoder) {
	mvkSetDynamicPipelineState(cmdEncoder, cmdEncoder->getState().dynamicPipelineState().logicOpEnable, _value ? 1 : 0);
}


#pragma mark -
#pragma mark MVKCmdSetLogicOp

void MVKCmdSetLogicOp::encode(MVKCommandEncoder* cmdEncoder) {
	mvkSetDynamicPipelineState(cmdEncoder, cmdEncoder->getState().dynamicPipelineState().logicOp, _value);
}


#pragma mark -
#pragma mark MVKCmdSetTessellationDomainOrigin

void MVKCmdSetTessellationDomainOrigin::encode(MVKCommandEncoder* cmdEncoder) {
	mvkSetDynamicPipelineState(cmdEncoder, cmdEncoder->getState().dynamicPipelineState().domainOrigin, _value);
}


#pragma mark -
#pragma mark MVKCmdSetDepthClipNegativeOneToOne

void MVKCmdSetDepthClipNegativeOneToOne::encode(MVKCommandEncoder* cmdEncoder) {
	mvkSetDynamicPipelineState(cmdEncoder, cmdEncoder->getState().dynamicPipelineState().negativeOneToOne, _value ? 1 : 0);
	// A shader that maps the convention for itself reads it from here rather than from the
	// pipeline it was compiled into.
	cmdEncoder->getState().setGraphicsDepthClipNegativeOneToOne(_value);
}


#pragma mark -
#pragma mark MVKCmdSetLineStippleEnable

void MVKCmdSetLineStippleEnable::encode(MVKCommandEncoder* cmdEncoder) {
	// Metal has no line stipple, so MoltenVK reports the feature unsupported and only VK_FALSE
	// is a legal value here. Nothing needs recording, but the entry point must exist because
	// enabling shader objects makes every dynamic state setter callable.
}


#pragma mark -
#pragma mark MVKCmdSetColorBlendEnable

VkResult MVKCmdSetColorBlendEnable::setContent(MVKCommandBuffer* cmdBuff,
											   uint32_t firstAttachment,
											   uint32_t attachmentCount,
											   const VkBool32* pValues) {
	_firstAttachment = firstAttachment;
	_values.clear();
	_values.reserve(attachmentCount);
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	for (uint32_t i = 0; i < attachmentCount; i++) {
		_values.push_back(pValues[i]);
		if (firstAttachment + i < kMVKMaxColorAttachmentCount) { rs.blendAttachments[firstAttachment + i].blendEnable = pValues[i]; }
	}
	return VK_SUCCESS;
}

void MVKCmdSetColorBlendEnable::encode(MVKCommandEncoder* cmdEncoder) {
	auto& dps = cmdEncoder->getState().dynamicPipelineState();
	for (uint32_t i = 0; i < _values.size(); i++) {
		uint32_t attIdx = _firstAttachment + i;
		if (attIdx >= kMVKMaxColorAttachmentCount) { break; }
		mvkSetDynamicPipelineState(cmdEncoder, dps.blendAttachments[attIdx].blendEnable, _values[i]);
	}
}


#pragma mark -
#pragma mark MVKCmdSetColorBlendEquation

VkResult MVKCmdSetColorBlendEquation::setContent(MVKCommandBuffer* cmdBuff,
												 uint32_t firstAttachment,
												 uint32_t attachmentCount,
												 const VkColorBlendEquationEXT* pValues) {
	_firstAttachment = firstAttachment;
	_values.clear();
	_values.reserve(attachmentCount);
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	for (uint32_t i = 0; i < attachmentCount; i++) {
		_values.push_back(pValues[i]);
		if (firstAttachment + i < kMVKMaxColorAttachmentCount) {
			auto& ba = rs.blendAttachments[firstAttachment + i];
			ba.srcColorBlendFactor = pValues[i].srcColorBlendFactor; ba.dstColorBlendFactor = pValues[i].dstColorBlendFactor; ba.colorBlendOp = pValues[i].colorBlendOp;
			ba.srcAlphaBlendFactor = pValues[i].srcAlphaBlendFactor; ba.dstAlphaBlendFactor = pValues[i].dstAlphaBlendFactor; ba.alphaBlendOp = pValues[i].alphaBlendOp;
		}
	}
	return VK_SUCCESS;
}

void MVKCmdSetColorBlendEquation::encode(MVKCommandEncoder* cmdEncoder) {
	auto& dps = cmdEncoder->getState().dynamicPipelineState();
	for (uint32_t i = 0; i < _values.size(); i++) {
		uint32_t attIdx = _firstAttachment + i;
		if (attIdx >= kMVKMaxColorAttachmentCount) { break; }
		auto& ba = dps.blendAttachments[attIdx];
		mvkSetDynamicPipelineState(cmdEncoder, ba.srcColorBlendFactor, _values[i].srcColorBlendFactor);
		mvkSetDynamicPipelineState(cmdEncoder, ba.dstColorBlendFactor, _values[i].dstColorBlendFactor);
		mvkSetDynamicPipelineState(cmdEncoder, ba.colorBlendOp,        _values[i].colorBlendOp);
		mvkSetDynamicPipelineState(cmdEncoder, ba.srcAlphaBlendFactor, _values[i].srcAlphaBlendFactor);
		mvkSetDynamicPipelineState(cmdEncoder, ba.dstAlphaBlendFactor, _values[i].dstAlphaBlendFactor);
		mvkSetDynamicPipelineState(cmdEncoder, ba.alphaBlendOp,        _values[i].alphaBlendOp);
	}
}


#pragma mark -
#pragma mark MVKCmdSetColorWriteMask

VkResult MVKCmdSetColorWriteMask::setContent(MVKCommandBuffer* cmdBuff,
											 uint32_t firstAttachment,
											 uint32_t attachmentCount,
											 const VkColorComponentFlags* pValues) {
	_firstAttachment = firstAttachment;
	_values.clear();
	_values.reserve(attachmentCount);
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	for (uint32_t i = 0; i < attachmentCount; i++) {
		_values.push_back(pValues[i]);
		if (firstAttachment + i < kMVKMaxColorAttachmentCount) { rs.blendAttachments[firstAttachment + i].colorWriteMask = pValues[i]; }
	}
	return VK_SUCCESS;
}

void MVKCmdSetColorWriteMask::encode(MVKCommandEncoder* cmdEncoder) {
	auto& dps = cmdEncoder->getState().dynamicPipelineState();
	for (uint32_t i = 0; i < _values.size(); i++) {
		uint32_t attIdx = _firstAttachment + i;
		if (attIdx >= kMVKMaxColorAttachmentCount) { break; }
		mvkSetDynamicPipelineState(cmdEncoder, dps.blendAttachments[attIdx].colorWriteMask, _values[i]);
	}
}


#pragma mark -
#pragma mark MVKCmdSetSampleMask

VkResult MVKCmdSetSampleMask::setContent(MVKCommandBuffer* cmdBuff,
										 VkSampleCountFlagBits samples,
										 const VkSampleMask* pSampleMask) {
	// Metal carries a single 32-bit sample mask, and MoltenVK supports at most 32 samples,
	// so only the first word of the Vulkan array can ever be meaningful.
	_sampleMask = pSampleMask ? pSampleMask[0] : ~0u;
	cmdBuff->_shaderObjectRecordState.pipelineState.sampleMask = _sampleMask;
	return VK_SUCCESS;
}

void MVKCmdSetSampleMask::encode(MVKCommandEncoder* cmdEncoder) {
	mvkSetDynamicPipelineState(cmdEncoder, cmdEncoder->getState().dynamicPipelineState().sampleMask, _sampleMask);
}


#pragma mark -
#pragma mark MVKCmdSetColorWriteEnable

// VK_EXT_color_write_enable is not advertised, because turning writes off for an attachment means
// rebuilding a Metal pipeline, which only the shader object path can do. The command is reachable
// through VK_EXT_shader_object, where it does take effect.
VkResult MVKCmdSetColorWriteEnable::setContent(MVKCommandBuffer* cmdBuff,
											   uint32_t attachmentCount,
											   const VkBool32* pColorWriteEnables) {
	_values.clear();
	_values.reserve(attachmentCount);
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	for (uint32_t i = 0; i < attachmentCount; i++) {
		_values.push_back(pColorWriteEnables[i]);
		if (i < kMVKMaxColorAttachmentCount) { rs.colorWriteEnables[i] = pColorWriteEnables[i]; }
	}
	return VK_SUCCESS;
}

void MVKCmdSetColorWriteEnable::encode(MVKCommandEncoder* cmdEncoder) {
	auto& dps = cmdEncoder->getState().dynamicPipelineState();
	for (uint32_t i = 0; i < _values.size() && i < kMVKMaxColorAttachmentCount; i++) {
		mvkSetDynamicPipelineState(cmdEncoder, dps.colorWriteEnables[i], _values[i]);
	}
}


#pragma mark -
#pragma mark Record-time shadow for shader object prefetch

// Each setter also writes the value into the command buffer's record-time shadow, so that a
// draw recorded afterwards can start building its pipeline before the command buffer is
// submitted. The encoder keeps its own authoritative copy, written when the command encodes.

VkResult MVKCmdSetRasterizationSamples::setContent(MVKCommandBuffer* cmdBuff, VkSampleCountFlagBits value) {
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	rs.rasterizationSamples = value;
	return MVKSingleValueCommand<VkSampleCountFlagBits>::setContent(cmdBuff, value);
}

VkResult MVKCmdSetAlphaToCoverageEnable::setContent(MVKCommandBuffer* cmdBuff, VkBool32 value) {
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	rs.alphaToCoverageEnable = value ? 1 : 0;
	return MVKSingleValueCommand<VkBool32>::setContent(cmdBuff, value);
}

VkResult MVKCmdSetAlphaToOneEnable::setContent(MVKCommandBuffer* cmdBuff, VkBool32 value) {
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	rs.alphaToOneEnable = value ? 1 : 0;
	return MVKSingleValueCommand<VkBool32>::setContent(cmdBuff, value);
}

VkResult MVKCmdSetLogicOpEnable::setContent(MVKCommandBuffer* cmdBuff, VkBool32 value) {
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	rs.logicOpEnable = value ? 1 : 0;
	return MVKSingleValueCommand<VkBool32>::setContent(cmdBuff, value);
}

VkResult MVKCmdSetLogicOp::setContent(MVKCommandBuffer* cmdBuff, VkLogicOp value) {
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	rs.logicOp = value;
	return MVKSingleValueCommand<VkLogicOp>::setContent(cmdBuff, value);
}

VkResult MVKCmdSetTessellationDomainOrigin::setContent(MVKCommandBuffer* cmdBuff, VkTessellationDomainOrigin value) {
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	rs.domainOrigin = value;
	return MVKSingleValueCommand<VkTessellationDomainOrigin>::setContent(cmdBuff, value);
}

VkResult MVKCmdSetDepthClipNegativeOneToOne::setContent(MVKCommandBuffer* cmdBuff, VkBool32 value) {
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	rs.negativeOneToOne = value ? 1 : 0;
	return MVKSingleValueCommand<VkBool32>::setContent(cmdBuff, value);
}

VkResult MVKCmdSetPrimitiveTopology::setContent(MVKCommandBuffer* cmdBuff, VkPrimitiveTopology value) {
	auto& rs = cmdBuff->_shaderObjectRecordState.pipelineState;
	rs.topology = mvkShaderObjectKeyTopology(value);
	return MVKSingleValueCommand<VkPrimitiveTopology>::setContent(cmdBuff, value);
}
