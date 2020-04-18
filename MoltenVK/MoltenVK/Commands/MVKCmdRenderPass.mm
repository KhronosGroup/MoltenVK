/*
 * MVKCmdRenderPass.mm
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCmdRenderPass.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKRenderPass.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"


#pragma mark -
#pragma mark MVKCmdBeginRenderPass

MVKFuncionOverride_getTypePool(BeginRenderPass)

VkResult MVKCmdBeginRenderPass::setContent(MVKCommandBuffer* cmdBuff,
										   const VkRenderPassBeginInfo* pRenderPassBegin,
										   VkSubpassContents contents) {
	_info = *pRenderPassBegin;
	_contents = contents;
	_renderPass = (MVKRenderPass*)_info.renderPass;
	_framebuffer = (MVKFramebuffer*)_info.framebuffer;
    _loadOverride = false;
    _storeOverride = false;

	// Add clear values
	_clearValues.clear();	// Clear for reuse
	_clearValues.reserve(_info.clearValueCount);
	for (uint32_t i = 0; i < _info.clearValueCount; i++) {
		_clearValues.push_back(_info.pClearValues[i]);
	}

	cmdBuff->recordBeginRenderPass(this);

	return VK_SUCCESS;
}

void MVKCmdBeginRenderPass::encode(MVKCommandEncoder* cmdEncoder) {
//	MVKLogDebug("Encoding vkCmdBeginRenderPass(). Elapsed time: %.6f ms.", mvkGetElapsedMilliseconds());
	cmdEncoder->beginRenderpass(_contents, _renderPass, _framebuffer, _info.renderArea, &_clearValues, _loadOverride, _storeOverride);
}

MVKCmdBeginRenderPass::MVKCmdBeginRenderPass(MVKCommandTypePool<MVKCmdBeginRenderPass>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdNextSubpass

MVKFuncionOverride_getTypePool(NextSubpass)

VkResult MVKCmdNextSubpass::setContent(MVKCommandBuffer* cmdBuff,
									   VkSubpassContents contents) {
	_contents = contents;

	return VK_SUCCESS;
}

void MVKCmdNextSubpass::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->beginNextSubpass(_contents);
}

MVKCmdNextSubpass::MVKCmdNextSubpass(MVKCommandTypePool<MVKCmdNextSubpass>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdEndRenderPass

MVKFuncionOverride_getTypePool(EndRenderPass)

VkResult MVKCmdEndRenderPass::setContent(MVKCommandBuffer* cmdBuff) {
	cmdBuff->recordEndRenderPass(this);
	return VK_SUCCESS;
}

void MVKCmdEndRenderPass::encode(MVKCommandEncoder* cmdEncoder) {
//	MVKLogDebug("Encoding vkCmdEndRenderPass(). Elapsed time: %.6f ms.", mvkGetElapsedMilliseconds());
	cmdEncoder->endRenderpass();
}

MVKCmdEndRenderPass::MVKCmdEndRenderPass(MVKCommandTypePool<MVKCmdEndRenderPass>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdExecuteCommands

MVKFuncionOverride_getTypePool(ExecuteCommands)

VkResult MVKCmdExecuteCommands::setContent(MVKCommandBuffer* cmdBuff,
										   uint32_t commandBuffersCount,
										   const VkCommandBuffer* pCommandBuffers) {
	// Add clear values
	_secondaryCommandBuffers.clear();	// Clear for reuse
	_secondaryCommandBuffers.reserve(commandBuffersCount);
	for (uint32_t cbIdx = 0; cbIdx < commandBuffersCount; cbIdx++) {
		_secondaryCommandBuffers.push_back(MVKCommandBuffer::getMVKCommandBuffer(pCommandBuffers[cbIdx]));
	}

	return VK_SUCCESS;
}

void MVKCmdExecuteCommands::encode(MVKCommandEncoder* cmdEncoder) {
    for (auto& cb : _secondaryCommandBuffers) { cmdEncoder->encodeSecondary(cb); }
}

MVKCmdExecuteCommands::MVKCmdExecuteCommands(MVKCommandTypePool<MVKCmdExecuteCommands>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetViewport

MVKFuncionOverride_getTypePool(SetViewport)

VkResult MVKCmdSetViewport::setContent(MVKCommandBuffer* cmdBuff,
									   uint32_t firstViewport,
									   uint32_t viewportCount,
									   const VkViewport* pViewports) {
	_firstViewport = firstViewport;
	_mtlViewports.clear();	// Clear for reuse
	_mtlViewports.reserve(viewportCount);
	for (uint32_t i = 0; i < viewportCount; i++) {
		_mtlViewports.push_back(mvkMTLViewportFromVkViewport(pViewports[i]));
	}

	return VK_SUCCESS;
}

void MVKCmdSetViewport::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_viewportState.setViewports(_mtlViewports, _firstViewport, true);
}

MVKCmdSetViewport::MVKCmdSetViewport(MVKCommandTypePool<MVKCmdSetViewport>* pool)
		: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetScissor

MVKFuncionOverride_getTypePool(SetScissor)

VkResult MVKCmdSetScissor::setContent(MVKCommandBuffer* cmdBuff,
									  uint32_t firstScissor,
									  uint32_t scissorCount,
									  const VkRect2D* pScissors) {
	_firstScissor = firstScissor;
	_mtlScissors.clear();	// Clear for reuse
	_mtlScissors.reserve(scissorCount);
	for (uint32_t i = 0; i < scissorCount; i++) {
		_mtlScissors.push_back(mvkMTLScissorRectFromVkRect2D(pScissors[i]));
	}

	return VK_SUCCESS;
}

void MVKCmdSetScissor::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_scissorState.setScissors(_mtlScissors, _firstScissor, true);
}

MVKCmdSetScissor::MVKCmdSetScissor(MVKCommandTypePool<MVKCmdSetScissor>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetLineWidth

MVKFuncionOverride_getTypePool(SetLineWidth)

VkResult MVKCmdSetLineWidth::setContent(MVKCommandBuffer* cmdBuff,
										float lineWidth) {
    _lineWidth = lineWidth;

    // Validate
    if (_lineWidth != 1.0 || cmdBuff->getDevice()->_enabledFeatures.wideLines) {
        return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdSetLineWidth(): The current device does not support wide lines.");
    }

	return VK_SUCCESS;
}

void MVKCmdSetLineWidth::encode(MVKCommandEncoder* cmdEncoder) {}

MVKCmdSetLineWidth::MVKCmdSetLineWidth(MVKCommandTypePool<MVKCmdSetLineWidth>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetDepthBias

MVKFuncionOverride_getTypePool(SetDepthBias)

VkResult MVKCmdSetDepthBias::setContent(MVKCommandBuffer* cmdBuff,
										float depthBiasConstantFactor,
										float depthBiasSlopeFactor,
										float depthBiasClamp) {
    _depthBiasConstantFactor = depthBiasConstantFactor;
    _depthBiasSlopeFactor = depthBiasSlopeFactor;
    _depthBiasClamp = depthBiasClamp;

	return VK_SUCCESS;
}

void MVKCmdSetDepthBias::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_depthBiasState.setDepthBias(_depthBiasConstantFactor,
                                             _depthBiasSlopeFactor,
                                             _depthBiasClamp);
}

MVKCmdSetDepthBias::MVKCmdSetDepthBias(MVKCommandTypePool<MVKCmdSetDepthBias>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetBlendConstants

MVKFuncionOverride_getTypePool(SetBlendConstants)

VkResult MVKCmdSetBlendConstants::setContent(MVKCommandBuffer* cmdBuff,
											 const float blendConst[4]) {
    _red = blendConst[0];
    _green = blendConst[1];
    _blue = blendConst[2];
    _alpha = blendConst[3];

	return VK_SUCCESS;
}

void MVKCmdSetBlendConstants::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_blendColorState.setBlendColor(_red, _green, _blue, _alpha, true);
}

MVKCmdSetBlendConstants::MVKCmdSetBlendConstants(MVKCommandTypePool<MVKCmdSetBlendConstants>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetDepthBounds

MVKFuncionOverride_getTypePool(SetDepthBounds)

VkResult MVKCmdSetDepthBounds::setContent(MVKCommandBuffer* cmdBuff,
										  float minDepthBounds,
										  float maxDepthBounds) {
    _minDepthBounds = minDepthBounds;
    _maxDepthBounds = maxDepthBounds;

    // Validate
    if (cmdBuff->getDevice()->_enabledFeatures.depthBounds) {
        return reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdSetDepthBounds(): The current device does not support setting depth bounds.");
    }

	return VK_SUCCESS;
}

void MVKCmdSetDepthBounds::encode(MVKCommandEncoder* cmdEncoder) {}

MVKCmdSetDepthBounds::MVKCmdSetDepthBounds(MVKCommandTypePool<MVKCmdSetDepthBounds>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetStencilCompareMask

MVKFuncionOverride_getTypePool(SetStencilCompareMask)

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

MVKCmdSetStencilCompareMask::MVKCmdSetStencilCompareMask(MVKCommandTypePool<MVKCmdSetStencilCompareMask>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetStencilWriteMask

MVKFuncionOverride_getTypePool(SetStencilWriteMask)

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

MVKCmdSetStencilWriteMask::MVKCmdSetStencilWriteMask(MVKCommandTypePool<MVKCmdSetStencilWriteMask>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetStencilReference

MVKFuncionOverride_getTypePool(SetStencilReference)

VkResult MVKCmdSetStencilReference::setContent(MVKCommandBuffer* cmdBuff,
											   VkStencilFaceFlags faceMask,
											   uint32_t stencilReference) {
    _faceMask = faceMask;
    _stencilReference = stencilReference;

	return VK_SUCCESS;
}

void MVKCmdSetStencilReference::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_stencilReferenceValueState.setReferenceValues(_faceMask, _stencilReference);
}

MVKCmdSetStencilReference::MVKCmdSetStencilReference(MVKCommandTypePool<MVKCmdSetStencilReference>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

