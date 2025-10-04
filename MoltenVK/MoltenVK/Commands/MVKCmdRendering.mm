/*
 * MVKCmdRendering.mm
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

#include "MVKCmdRendering.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKFramebuffer.h"
#include "MVKRenderPass.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"


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
