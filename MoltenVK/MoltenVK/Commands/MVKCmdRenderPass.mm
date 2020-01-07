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

void MVKCmdBeginRenderPass::setContent(const VkRenderPassBeginInfo* pRenderPassBegin,
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
}

void MVKCmdBeginRenderPass::encode(MVKCommandEncoder* cmdEncoder) {
//	MVKLogDebug("Encoding vkCmdBeginRenderPass(). Elapsed time: %.6f ms.", mvkGetElapsedMilliseconds());
	cmdEncoder->beginRenderpass(_contents, _renderPass, _framebuffer, _info.renderArea, &_clearValues, _loadOverride, _storeOverride);
}

MVKCmdBeginRenderPass::MVKCmdBeginRenderPass(MVKCommandTypePool<MVKCmdBeginRenderPass>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdNextSubpass

void MVKCmdNextSubpass::setContent(VkSubpassContents contents) {
	_contents = contents;
}

void MVKCmdNextSubpass::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->beginNextSubpass(_contents);
}

MVKCmdNextSubpass::MVKCmdNextSubpass(MVKCommandTypePool<MVKCmdNextSubpass>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdEndRenderPass

void MVKCmdEndRenderPass::encode(MVKCommandEncoder* cmdEncoder) {
//	MVKLogDebug("Encoding vkCmdEndRenderPass(). Elapsed time: %.6f ms.", mvkGetElapsedMilliseconds());
	cmdEncoder->endRenderpass();
}

MVKCmdEndRenderPass::MVKCmdEndRenderPass(MVKCommandTypePool<MVKCmdEndRenderPass>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdExecuteCommands

void MVKCmdExecuteCommands::setContent(uint32_t commandBuffersCount,
									   const VkCommandBuffer* pCommandBuffers) {
	// Add clear values
	_secondaryCommandBuffers.clear();	// Clear for reuse
	_secondaryCommandBuffers.reserve(commandBuffersCount);
	for (uint32_t cbIdx = 0; cbIdx < commandBuffersCount; cbIdx++) {
		_secondaryCommandBuffers.push_back(MVKCommandBuffer::getMVKCommandBuffer(pCommandBuffers[cbIdx]));
	}
}

void MVKCmdExecuteCommands::encode(MVKCommandEncoder* cmdEncoder) {
    for (auto& cb : _secondaryCommandBuffers) { cmdEncoder->encodeSecondary(cb); }
}

MVKCmdExecuteCommands::MVKCmdExecuteCommands(MVKCommandTypePool<MVKCmdExecuteCommands>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetViewport

void MVKCmdSetViewport::setContent(uint32_t firstViewport, uint32_t viewportCount, const VkViewport* pViewports) {
	_firstViewport = firstViewport;
	_mtlViewports.clear();	// Clear for reuse
	_mtlViewports.reserve(viewportCount);
	for (uint32_t i = 0; i < viewportCount; i++) {
		_mtlViewports.push_back(mvkMTLViewportFromVkViewport(pViewports[i]));
	}
}

void MVKCmdSetViewport::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_viewportState.setViewports(_mtlViewports, _firstViewport, true);
}

MVKCmdSetViewport::MVKCmdSetViewport(MVKCommandTypePool<MVKCmdSetViewport>* pool)
		: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetScissor

void MVKCmdSetScissor::setContent(uint32_t firstScissor, uint32_t scissorCount, const VkRect2D* pScissors) {
	_firstScissor = firstScissor;
	_mtlScissors.clear();	// Clear for reuse
	_mtlScissors.reserve(scissorCount);
	for (uint32_t i = 0; i < scissorCount; i++) {
		_mtlScissors.push_back(mvkMTLScissorRectFromVkRect2D(pScissors[i]));
	}
}

void MVKCmdSetScissor::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_scissorState.setScissors(_mtlScissors, _firstScissor, true);
}

MVKCmdSetScissor::MVKCmdSetScissor(MVKCommandTypePool<MVKCmdSetScissor>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetLineWidth

void MVKCmdSetLineWidth::setContent(float lineWidth) {
    _lineWidth = lineWidth;

    // Validate
    if (_lineWidth != 1.0 || getDevice()->_enabledFeatures.wideLines) {
        setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdSetLineWidth(): The current device does not support wide lines."));
    }
}

void MVKCmdSetLineWidth::encode(MVKCommandEncoder* cmdEncoder) {}

MVKCmdSetLineWidth::MVKCmdSetLineWidth(MVKCommandTypePool<MVKCmdSetLineWidth>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetDepthBias

void MVKCmdSetDepthBias::setContent(float depthBiasConstantFactor,
                                    float depthBiasSlopeFactor,
                                    float depthBiasClamp) {
    _depthBiasConstantFactor = depthBiasConstantFactor;
    _depthBiasSlopeFactor = depthBiasSlopeFactor;
    _depthBiasClamp = depthBiasClamp;
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

void MVKCmdSetBlendConstants::setContent(const float blendConst[4]) {
    _red = blendConst[0];
    _green = blendConst[1];
    _blue = blendConst[2];
    _alpha = blendConst[3];
}

void MVKCmdSetBlendConstants::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_blendColorState.setBlendColor(_red, _green, _blue, _alpha, true);
}

MVKCmdSetBlendConstants::MVKCmdSetBlendConstants(MVKCommandTypePool<MVKCmdSetBlendConstants>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetDepthBounds

void MVKCmdSetDepthBounds::setContent(float minDepthBounds, float maxDepthBounds) {
    _minDepthBounds = minDepthBounds;
    _maxDepthBounds = maxDepthBounds;

    // Validate
    if (getDevice()->_enabledFeatures.depthBounds) {
        setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdSetDepthBounds(): The current device does not support setting depth bounds."));
    }
}

void MVKCmdSetDepthBounds::encode(MVKCommandEncoder* cmdEncoder) {}

MVKCmdSetDepthBounds::MVKCmdSetDepthBounds(MVKCommandTypePool<MVKCmdSetDepthBounds>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetStencilCompareMask

void MVKCmdSetStencilCompareMask::setContent(VkStencilFaceFlags faceMask,
                                             uint32_t stencilCompareMask) {
    _faceMask = faceMask;
    _stencilCompareMask = stencilCompareMask;
}

void MVKCmdSetStencilCompareMask::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_depthStencilState.setStencilCompareMask(_faceMask, _stencilCompareMask);
}

MVKCmdSetStencilCompareMask::MVKCmdSetStencilCompareMask(MVKCommandTypePool<MVKCmdSetStencilCompareMask>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetStencilWriteMask

void MVKCmdSetStencilWriteMask::setContent(VkStencilFaceFlags faceMask,
                                             uint32_t stencilWriteMask) {
    _faceMask = faceMask;
    _stencilWriteMask = stencilWriteMask;
}

void MVKCmdSetStencilWriteMask::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_depthStencilState.setStencilWriteMask(_faceMask, _stencilWriteMask);
}

MVKCmdSetStencilWriteMask::MVKCmdSetStencilWriteMask(MVKCommandTypePool<MVKCmdSetStencilWriteMask>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdSetStencilReference

void MVKCmdSetStencilReference::setContent(VkStencilFaceFlags faceMask,
                                           uint32_t stencilReference) {
    _faceMask = faceMask;
    _stencilReference = stencilReference;
}

void MVKCmdSetStencilReference::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->_stencilReferenceValueState.setReferenceValues(_faceMask, _stencilReference);
}

MVKCmdSetStencilReference::MVKCmdSetStencilReference(MVKCommandTypePool<MVKCmdSetStencilReference>* pool)
    : MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark Command creation functions

void mvkCmdBeginRenderPass(MVKCommandBuffer* cmdBuff,
						   const VkRenderPassBeginInfo* pRenderPassBegin,
						   VkSubpassContents contents) {
	MVKCmdBeginRenderPass* cmd = cmdBuff->_commandPool->_cmdBeginRenderPassPool.acquireObject();
	cmd->setContent(pRenderPassBegin, contents);
	cmdBuff->recordBeginRenderPass(cmd);
	cmdBuff->addCommand(cmd);
}

void mvkCmdNextSubpass(MVKCommandBuffer* cmdBuff, VkSubpassContents contents) {
	MVKCmdNextSubpass* cmd = cmdBuff->_commandPool->_cmdNextSubpassPool.acquireObject();
	cmd->setContent(contents);
	cmdBuff->addCommand(cmd);
}

void mvkCmdEndRenderPass(MVKCommandBuffer* cmdBuff) {
	MVKCmdEndRenderPass* cmd = cmdBuff->_commandPool->_cmdEndRenderPassPool.acquireObject();
	cmdBuff->recordEndRenderPass(cmd);
	cmdBuff->addCommand(cmd);
}

void mvkCmdExecuteCommands(MVKCommandBuffer* cmdBuff,
						   uint32_t commandBuffersCount,
						   const VkCommandBuffer* pCommandBuffers) {
	MVKCmdExecuteCommands* cmd = cmdBuff->_commandPool->_cmdExecuteCommandsPool.acquireObject();
	cmd->setContent(commandBuffersCount, pCommandBuffers);
	cmdBuff->addCommand(cmd);
}

void mvkCmdSetViewport(MVKCommandBuffer* cmdBuff,
					   uint32_t firstViewport,
					   uint32_t viewportCount,
					   const VkViewport* pViewports) {
	if (viewportCount == 0 || firstViewport > 0) { return; }		// Nothing to set

	MVKCmdSetViewport* cmd = cmdBuff->_commandPool->_cmdSetViewportPool.acquireObject();
	cmd->setContent(firstViewport, viewportCount, pViewports);
	cmdBuff->addCommand(cmd);
}

void mvkCmdSetScissor(MVKCommandBuffer* cmdBuff,
					  uint32_t firstScissor,
					  uint32_t scissorCount,
					  const VkRect2D* pScissors) {
	if (scissorCount == 0) { return; }		// Nothing to set

	MVKCmdSetScissor* cmd = cmdBuff->_commandPool->_cmdSetScissorPool.acquireObject();
	cmd->setContent(firstScissor, scissorCount, pScissors);
	cmdBuff->addCommand(cmd);
}

void mvkCmdSetLineWidth(MVKCommandBuffer* cmdBuff, float lineWidth) {
    MVKCmdSetLineWidth* cmd = cmdBuff->_commandPool->_cmdSetLineWidthPool.acquireObject();
    cmd->setContent(lineWidth);
    cmdBuff->addCommand(cmd);
}

void mvkCmdSetDepthBias(MVKCommandBuffer* cmdBuff,
                        float depthBiasConstantFactor,
                        float depthBiasClamp,
                        float depthBiasSlopeFactor) {
    MVKCmdSetDepthBias* cmd = cmdBuff->_commandPool->_cmdSetDepthBiasPool.acquireObject();
    cmd->setContent(depthBiasConstantFactor, depthBiasSlopeFactor, depthBiasClamp);
    cmdBuff->addCommand(cmd);
}

void mvkCmdSetBlendConstants(MVKCommandBuffer* cmdBuff,
                             const float blendConst[4]) {
    MVKCmdSetBlendConstants* cmd = cmdBuff->_commandPool->_cmdSetBlendConstantsPool.acquireObject();
    cmd->setContent(blendConst);
    cmdBuff->addCommand(cmd);
}

void mvkCmdSetDepthBounds(MVKCommandBuffer* cmdBuff,
                          float minDepthBounds,
                          float maxDepthBounds) {
    MVKCmdSetDepthBounds* cmd = cmdBuff->_commandPool->_cmdSetDepthBoundsPool.acquireObject();
    cmd->setContent(minDepthBounds, maxDepthBounds);
    cmdBuff->addCommand(cmd);
}

void mvkCmdSetStencilCompareMask(MVKCommandBuffer* cmdBuff,
                                 VkStencilFaceFlags faceMask,
                                 uint32_t stencilCompareMask) {
    MVKCmdSetStencilCompareMask* cmd = cmdBuff->_commandPool->_cmdSetStencilCompareMaskPool.acquireObject();
    cmd->setContent(faceMask, stencilCompareMask);
    cmdBuff->addCommand(cmd);
}

void mvkCmdSetStencilWriteMask(MVKCommandBuffer* cmdBuff,
                               VkStencilFaceFlags faceMask,
                               uint32_t stencilWriteMask) {
    MVKCmdSetStencilWriteMask* cmd = cmdBuff->_commandPool->_cmdSetStencilWriteMaskPool.acquireObject();
    cmd->setContent(faceMask, stencilWriteMask);
    cmdBuff->addCommand(cmd);
}

void mvkCmdSetStencilReference(MVKCommandBuffer* cmdBuff,
                               VkStencilFaceFlags faceMask,
                               uint32_t stencilReference) {
    MVKCmdSetStencilReference* cmd = cmdBuff->_commandPool->_cmdSetStencilReferencePool.acquireObject();
    cmd->setContent(faceMask, stencilReference);
    cmdBuff->addCommand(cmd);
}

