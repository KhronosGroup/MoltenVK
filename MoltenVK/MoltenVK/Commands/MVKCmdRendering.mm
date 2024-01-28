/*
 * MVKCmdRendering.mm
 *
 * Copyright (c) 2015-2024 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
	cmdEncoder->_renderingState.setSampleLocations(_sampleLocations.contents(), true);
}


#pragma mark -
#pragma mark MVKCmdSetSampleLocationsEnable

VkResult MVKCmdSetSampleLocationsEnable::setContent(MVKCommandBuffer* cmdBuff,
													VkBool32 sampleLocationsEnable) {
	_sampleLocationsEnable = sampleLocationsEnable;
	return VK_SUCCESS;
}

void MVKCmdSetSampleLocationsEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setSampleLocationsEnable(_sampleLocationsEnable, true);
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
	cmdEncoder->_renderingState.setViewports(_viewports.contents(), _firstViewport, true);
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
    cmdEncoder->_renderingState.setScissors(_scissors.contents(), _firstScissor, true);
}

template class MVKCmdSetScissor<1>;
template class MVKCmdSetScissor<kMVKMaxViewportScissorCount>;


#pragma mark -
#pragma mark MVKCmdSetDepthBias

VkResult MVKCmdSetDepthBias::setContent(MVKCommandBuffer* cmdBuff,
										float depthBiasConstantFactor,
										float depthBiasClamp,
										float depthBiasSlopeFactor) {
    _depthBiasConstantFactor = depthBiasConstantFactor;
    _depthBiasSlopeFactor = depthBiasSlopeFactor;
    _depthBiasClamp = depthBiasClamp;

	return VK_SUCCESS;
}

void MVKCmdSetDepthBias::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setDepthBias(_depthBiasConstantFactor,
											   _depthBiasSlopeFactor,
											   _depthBiasClamp);
}


#pragma mark -
#pragma mark MVKCmdSetDepthBiasEnable

VkResult MVKCmdSetDepthBiasEnable::setContent(MVKCommandBuffer* cmdBuff,
											  VkBool32 depthBiasEnable) {
	_depthBiasEnable = depthBiasEnable;
	return VK_SUCCESS;
}

void MVKCmdSetDepthBiasEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setDepthBiasEnable(_depthBiasEnable);
}


#pragma mark -
#pragma mark MVKCmdSetBlendConstants

VkResult MVKCmdSetBlendConstants::setContent(MVKCommandBuffer* cmdBuff,
											 const float blendConst[4]) {
	mvkCopy(_blendConstants, blendConst, 4);
	return VK_SUCCESS;
}

void MVKCmdSetBlendConstants::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_renderingState.setBlendConstants(_blendConstants, true);
}


#pragma mark -
#pragma mark MVKCmdSetDepthTestEnable

VkResult MVKCmdSetDepthTestEnable::setContent(MVKCommandBuffer* cmdBuff,
											  VkBool32 depthTestEnable) {
	_depthTestEnable = depthTestEnable;
	return VK_SUCCESS;
}

void MVKCmdSetDepthTestEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_depthStencilState.setDepthTestEnable(_depthTestEnable);
}


#pragma mark -
#pragma mark MVKCmdSetDepthWriteEnable

VkResult MVKCmdSetDepthWriteEnable::setContent(MVKCommandBuffer* cmdBuff,
											   VkBool32 depthWriteEnable) {
	_depthWriteEnable = depthWriteEnable;
	return VK_SUCCESS;
}

void MVKCmdSetDepthWriteEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_depthStencilState.setDepthWriteEnable(_depthWriteEnable);
}


#pragma mark -
#pragma mark MVKCmdSetDepthClipEnable

VkResult MVKCmdSetDepthClipEnable::setContent(MVKCommandBuffer* cmdBuff,
											  VkBool32 depthClipEnable) {
	_depthClipEnable = depthClipEnable;
	return VK_SUCCESS;
}

void MVKCmdSetDepthClipEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setDepthClipEnable(_depthClipEnable, true);
}


#pragma mark -
#pragma mark MVKCmdSetDepthCompareOp

VkResult MVKCmdSetDepthCompareOp::setContent(MVKCommandBuffer* cmdBuff,
											 VkCompareOp depthCompareOp) {
	_depthCompareOp = depthCompareOp;
	return VK_SUCCESS;
}

void MVKCmdSetDepthCompareOp::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_depthStencilState.setDepthCompareOp(_depthCompareOp);
}


#pragma mark -
#pragma mark MVKCmdSetStencilTestEnable

VkResult MVKCmdSetStencilTestEnable::setContent(MVKCommandBuffer* cmdBuff,
											  VkBool32 stencilTestEnable) {
	_stencilTestEnable = stencilTestEnable;
	return VK_SUCCESS;
}

void MVKCmdSetStencilTestEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_depthStencilState.setStencilTestEnable(_stencilTestEnable);
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
	cmdEncoder->_depthStencilState.setStencilOp(_faceMask, _failOp, _passOp, _depthFailOp, _compareOp);
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
    cmdEncoder->_depthStencilState.setStencilCompareMask(_faceMask, _stencilCompareMask);
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
    cmdEncoder->_depthStencilState.setStencilWriteMask(_faceMask, _stencilWriteMask);
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
    cmdEncoder->_renderingState.setStencilReferenceValues(_faceMask, _stencilReference);
}


#pragma mark -
#pragma mark MVKCmdSetCullMode

VkResult MVKCmdSetCullMode::setContent(MVKCommandBuffer* cmdBuff,
                                       VkCullModeFlags cullMode) {
	_cullMode = cullMode;
	return VK_SUCCESS;
}

void MVKCmdSetCullMode::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setCullMode(_cullMode, true);
}


#pragma mark -
#pragma mark MVKCmdSetFrontFace

VkResult MVKCmdSetFrontFace::setContent(MVKCommandBuffer* cmdBuff,
                                       VkFrontFace frontFace) {
	_frontFace = frontFace;
	return VK_SUCCESS;
}

void MVKCmdSetFrontFace::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setFrontFace(_frontFace, true);
}


#pragma mark -
#pragma mark MVKCmdSetPatchControlPoints

VkResult MVKCmdSetPatchControlPoints::setContent(MVKCommandBuffer* cmdBuff,
												 uint32_t patchControlPoints) {
	_patchControlPoints = patchControlPoints;
	return VK_SUCCESS;
}

void MVKCmdSetPatchControlPoints::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setPatchControlPoints(_patchControlPoints, true);
}


#pragma mark -
#pragma mark MVKCmdSetPolygonMode

VkResult MVKCmdSetPolygonMode::setContent(MVKCommandBuffer* cmdBuff,
										  VkPolygonMode polygonMode) {
	_polygonMode = polygonMode;
	return VK_SUCCESS;
}

void MVKCmdSetPolygonMode::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setPolygonMode(_polygonMode, true);
}


#pragma mark -
#pragma mark MVKCmdSetLineWidth

VkResult MVKCmdSetLineWidth::setContent(MVKCommandBuffer* cmdBuff,
										float lineWidth) {
	_lineWidth = lineWidth;
	return VK_SUCCESS;
}

void MVKCmdSetLineWidth::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setLineWidth(_lineWidth, true);
}


#pragma mark -
#pragma mark MVKCmdSetPrimitiveTopology

VkResult MVKCmdSetPrimitiveTopology::setContent(MVKCommandBuffer* cmdBuff,
												VkPrimitiveTopology primitiveTopology) {
	_primitiveTopology = primitiveTopology;
	return VK_SUCCESS;
}

void MVKCmdSetPrimitiveTopology::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setPrimitiveTopology(_primitiveTopology, true);
}


#pragma mark -
#pragma mark MVKCmdSetPrimitiveRestartEnable

VkResult MVKCmdSetPrimitiveRestartEnable::setContent(MVKCommandBuffer* cmdBuff,
													 VkBool32 primitiveRestartEnable) {
	_primitiveRestartEnable = primitiveRestartEnable;
	return VK_SUCCESS;
}

void MVKCmdSetPrimitiveRestartEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setPrimitiveRestartEnable(_primitiveRestartEnable, true);
}


#pragma mark -
#pragma mark MVKCmdSetRasterizerDiscardEnable

VkResult MVKCmdSetRasterizerDiscardEnable::setContent(MVKCommandBuffer* cmdBuff,
													  VkBool32 rasterizerDiscardEnable) {
	_rasterizerDiscardEnable = rasterizerDiscardEnable;
	return VK_SUCCESS;
}

void MVKCmdSetRasterizerDiscardEnable::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setRasterizerDiscardEnable(_rasterizerDiscardEnable, true);
}
