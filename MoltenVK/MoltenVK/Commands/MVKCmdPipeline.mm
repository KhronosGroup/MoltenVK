/*
 * MVKCmdPipeline.mm
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

#include "MVKCmdPipeline.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"


#pragma mark -
#pragma mark MVKCmdExecuteCommands

template <size_t N>
VkResult MVKCmdExecuteCommands<N>::setContent(MVKCommandBuffer* cmdBuff,
											  uint32_t commandBuffersCount,
											  const VkCommandBuffer* pCommandBuffers) {
	// Add clear values
	_secondaryCommandBuffers.clear();	// Clear for reuse
	_secondaryCommandBuffers.reserve(commandBuffersCount);
	for (uint32_t cbIdx = 0; cbIdx < commandBuffersCount; cbIdx++) {
		_secondaryCommandBuffers.push_back(MVKCommandBuffer::getMVKCommandBuffer(pCommandBuffers[cbIdx]));
	}
	cmdBuff->recordExecuteCommands(_secondaryCommandBuffers.contents());

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdExecuteCommands<N>::encode(MVKCommandEncoder* cmdEncoder) {
    for (auto& cb : _secondaryCommandBuffers) { cmdEncoder->encodeSecondary(cb); }
}

template class MVKCmdExecuteCommands<1>;
template class MVKCmdExecuteCommands<16>;


#pragma mark -
#pragma mark MVKCmdPipelineBarrier

template <size_t N>
VkResult MVKCmdPipelineBarrier<N>::setContent(MVKCommandBuffer* cmdBuff,
											  const VkDependencyInfo* pDependencyInfo) {
	_dependencyFlags = pDependencyInfo->dependencyFlags;

	_barriers.clear();	// Clear for reuse
	_barriers.reserve(pDependencyInfo->memoryBarrierCount + 
					  pDependencyInfo->bufferMemoryBarrierCount +
					  pDependencyInfo->imageMemoryBarrierCount);

	for (uint32_t i = 0; i < pDependencyInfo->memoryBarrierCount; i++) {
		_barriers.emplace_back(pDependencyInfo->pMemoryBarriers[i]);
	}
	for (uint32_t i = 0; i < pDependencyInfo->bufferMemoryBarrierCount; i++) {
		_barriers.emplace_back(pDependencyInfo->pBufferMemoryBarriers[i]);
	}
	for (uint32_t i = 0; i < pDependencyInfo->imageMemoryBarrierCount; i++) {
		_barriers.emplace_back(pDependencyInfo->pImageMemoryBarriers[i]);
	}

	return VK_SUCCESS;
}

static uint64_t mvkPipelineStageFlagsToBarrierStages(VkPipelineStageFlags2 flags) {
	uint64_t result = 0;

	if (mvkIsAnyFlagEnabled(flags, VK_PIPELINE_STAGE_2_VERTEX_INPUT_BIT | VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT | VK_PIPELINE_STAGE_2_TESSELLATION_CONTROL_SHADER_BIT |
							VK_PIPELINE_STAGE_2_TESSELLATION_EVALUATION_SHADER_BIT | VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT | VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT |
							VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT | VK_PIPELINE_STAGE_2_GEOMETRY_SHADER_BIT | VK_PIPELINE_STAGE_2_INDEX_INPUT_BIT |
							VK_PIPELINE_STAGE_2_VERTEX_ATTRIBUTE_INPUT_BIT | VK_PIPELINE_STAGE_2_PRE_RASTERIZATION_SHADERS_BIT | VK_PIPELINE_STAGE_2_TRANSFORM_FEEDBACK_BIT_EXT |
							VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT | VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT))
		result |= 1 << kMVKBarrierStageVertex;

	if (mvkIsAnyFlagEnabled(flags, VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT | VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT |
							VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT |
							VK_PIPELINE_STAGE_2_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR | VK_PIPELINE_STAGE_2_FRAGMENT_DENSITY_PROCESS_BIT_EXT |
							VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT | VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT))
		result |= 1 << kMVKBarrierStageFragment;

	if (mvkIsAnyFlagEnabled(flags, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT | VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT |
							VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT))
		result |= 1 << kMVKBarrierStageCompute;

	if (mvkIsAnyFlagEnabled(flags, VK_PIPELINE_STAGE_2_BLIT_BIT | VK_PIPELINE_STAGE_2_COPY_BIT | VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT |
							VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT | VK_PIPELINE_STAGE_2_TRANSFER_BIT | VK_PIPELINE_STAGE_2_RESOLVE_BIT |
							VK_PIPELINE_STAGE_2_CLEAR_BIT | VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_COPY_BIT_KHR | VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT |
							VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT))
		result |= 1 << kMVKBarrierStageCopy;

	return result;
}

template <size_t N>
VkResult MVKCmdPipelineBarrier<N>::setContent(MVKCommandBuffer* cmdBuff,
											  VkPipelineStageFlags srcStageMask,
											  VkPipelineStageFlags dstStageMask,
											  VkDependencyFlags dependencyFlags,
											  uint32_t memoryBarrierCount,
											  const VkMemoryBarrier* pMemoryBarriers,
											  uint32_t bufferMemoryBarrierCount,
											  const VkBufferMemoryBarrier* pBufferMemoryBarriers,
											  uint32_t imageMemoryBarrierCount,
											  const VkImageMemoryBarrier* pImageMemoryBarriers) {
	_dependencyFlags = dependencyFlags;

	_barriers.clear();	// Clear for reuse
	_barriers.reserve(memoryBarrierCount + bufferMemoryBarrierCount + imageMemoryBarrierCount);

	for (uint32_t i = 0; i < memoryBarrierCount; i++) {
		_barriers.emplace_back(pMemoryBarriers[i], srcStageMask, dstStageMask);
	}
	for (uint32_t i = 0; i < bufferMemoryBarrierCount; i++) {
		_barriers.emplace_back(pBufferMemoryBarriers[i], srcStageMask, dstStageMask);
	}
	for (uint32_t i = 0; i < imageMemoryBarrierCount; i++) {
		_barriers.emplace_back(pImageMemoryBarriers[i], srcStageMask, dstStageMask);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdPipelineBarrier<N>::encode(MVKCommandEncoder* cmdEncoder) {
	
	auto& mtlFeats = cmdEncoder->getMetalFeatures();

#if MVK_MACOS
	// Calls below invoke MTLBlitCommandEncoder so must apply this first.
	// Check if pipeline barriers are available and we are in a renderpass.
	if (mtlFeats.memoryBarriers && cmdEncoder->_mtlRenderEncoder) {
		for (auto& b : _barriers) {
			MTLRenderStages srcStages = mvkMTLRenderStagesFromVkPipelineStageFlags(b.srcStageMask, false);
			MTLRenderStages dstStages = mvkMTLRenderStagesFromVkPipelineStageFlags(b.dstStageMask, true);
			switch (b.type) {
				case MVKPipelineBarrier::Memory: {
					MTLBarrierScope scope = (mvkMTLBarrierScopeFromVkAccessFlags(b.srcAccessMask) |
											 mvkMTLBarrierScopeFromVkAccessFlags(b.dstAccessMask));
					[cmdEncoder->_mtlRenderEncoder memoryBarrierWithScope: scope
															  afterStages: srcStages
															 beforeStages: dstStages];
					break;
				}

				case MVKPipelineBarrier::Buffer: {
					id<MTLResource> mtlRez = b.mvkBuffer->getMTLBuffer();
					[cmdEncoder->_mtlRenderEncoder memoryBarrierWithResources: &mtlRez
																		count: 1
																  afterStages: srcStages
																 beforeStages: dstStages];
					break;
				}
				case MVKPipelineBarrier::Image: {
					uint32_t plnCnt = b.mvkImage->getPlaneCount();
					id<MTLResource> mtlRezs[plnCnt];
					for (uint8_t plnIdx = 0; plnIdx < plnCnt; plnIdx++) {
						mtlRezs[plnIdx] = b.mvkImage->getMTLTexture(plnIdx);
					}
					[cmdEncoder->_mtlRenderEncoder memoryBarrierWithResources: mtlRezs
																		count: plnCnt
																  afterStages: srcStages
																 beforeStages: dstStages];
					break;
				}
				default:
					break;
			}
		}
	}
#endif

	if (!cmdEncoder->_mtlRenderEncoder && cmdEncoder->isUsingMetalArgumentBuffers() && cmdEncoder->getDevice()->hasResidencySet()) {
		cmdEncoder->endCurrentMetalEncoding();

		for (auto& b : _barriers) {
			uint64_t sourceStageMask = mvkPipelineStageFlagsToBarrierStages(b.srcStageMask), destStageMask = mvkPipelineStageFlagsToBarrierStages(b.dstStageMask);
			cmdEncoder->setBarrier(sourceStageMask, destStageMask);
		}
	}

	// Apple GPUs do not support renderpass barriers, and do not support rendering/writing
	// to an attachment and then reading from that attachment within a single renderpass.
	// So, in the case where we are inside a Metal renderpass, we need to split those activities
	// into separate Metal renderpasses. Since this is a potentially expensive operation,
	// verify that at least one attachment is being used both as an input and render attachment
	// by checking for a VK_IMAGE_LAYOUT_GENERAL layout.
	if (cmdEncoder->_mtlRenderEncoder && mtlFeats.tileBasedDeferredRendering) {
		bool needsRenderpassRestart = false;
		for (auto& b : _barriers) {
			if (b.type == MVKPipelineBarrier::Image && b.newLayout == VK_IMAGE_LAYOUT_GENERAL) {
				needsRenderpassRestart = true;
				break;
			}
		}
		if (needsRenderpassRestart) {
			cmdEncoder->encodeStoreActions(true);
			cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
		}
	}

	MVKDevice* mvkDvc = cmdEncoder->getDevice();
	MVKCommandUse cmdUse = kMVKCommandUsePipelineBarrier;

	for (auto& b : _barriers) {
		switch (b.type) {
			case MVKPipelineBarrier::Memory:
				mvkDvc->applyMemoryBarrier(b, cmdEncoder, cmdUse);
				break;

			case MVKPipelineBarrier::Buffer:
				b.mvkBuffer->applyBufferMemoryBarrier(b, cmdEncoder, cmdUse);
				break;

			case MVKPipelineBarrier::Image:
				b.mvkImage->applyImageMemoryBarrier(b, cmdEncoder, cmdUse);
				break;

			default:
				break;
		}
	}
}

template <size_t N>
bool MVKCmdPipelineBarrier<N>::coversTextures() {
	for (auto& b : _barriers) {
		switch (b.type) {
			case MVKPipelineBarrier::Memory:	return true;
			case MVKPipelineBarrier::Image: 	return true;
			default: 							break;
		}
	}
	return false;
}

template class MVKCmdPipelineBarrier<1>;
template class MVKCmdPipelineBarrier<4>;
template class MVKCmdPipelineBarrier<32>;


#pragma mark -
#pragma mark MVKCmdBindPipeline

VkResult MVKCmdBindPipeline::setContent(MVKCommandBuffer* cmdBuff, VkPipeline pipeline) {
	_pipeline = (MVKPipeline*)pipeline;

	cmdBuff->recordBindPipeline(this);

	return VK_SUCCESS;
}


#pragma mark -
#pragma mark MVKCmdBindGraphicsPipeline

void MVKCmdBindGraphicsPipeline::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->bindPipeline(VK_PIPELINE_BIND_POINT_GRAPHICS, _pipeline);
}

bool MVKCmdBindGraphicsPipeline::isTessellationPipeline() {
	return ((MVKGraphicsPipeline*)_pipeline)->isTessellationPipeline();
}


#pragma mark -
#pragma mark MVKCmdBindComputePipeline

void MVKCmdBindComputePipeline::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->bindPipeline(VK_PIPELINE_BIND_POINT_COMPUTE, _pipeline);
}


#pragma mark -
#pragma mark MVKCmdBindDescriptorSetsStatic

template <size_t N>
VkResult MVKCmdBindDescriptorSetsStatic<N>::setContent(MVKCommandBuffer* cmdBuff,
													   VkPipelineBindPoint pipelineBindPoint,
													   VkPipelineLayout layout,
													   uint32_t firstSet,
													   uint32_t setCount,
													   const VkDescriptorSet* pDescriptorSets) {
	if (_pipelineLayout) { _pipelineLayout->release(); }

	_pipelineBindPoint = pipelineBindPoint;
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_firstSet = firstSet;

	_pipelineLayout->retain();

	// Add the descriptor sets
	_descriptorSets.clear();	// Clear for reuse
	_descriptorSets.reserve(setCount);
	for (uint32_t dsIdx = 0; dsIdx < setCount; dsIdx++) {
		_descriptorSets.push_back((MVKDescriptorSet*)pDescriptorSets[dsIdx]);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdBindDescriptorSetsStatic<N>::encode(MVKCommandEncoder* cmdEncoder) {
	encode(cmdEncoder, MVKArrayRef<uint32_t>());
}

template <size_t N>
void MVKCmdBindDescriptorSetsStatic<N>::encode(MVKCommandEncoder* cmdEncoder, MVKArrayRef<uint32_t> dynamicOffsets) {
	_pipelineLayout->bindDescriptorSets(cmdEncoder, _pipelineBindPoint, _descriptorSets.contents(), _firstSet, dynamicOffsets);
}

template <size_t N>
MVKCmdBindDescriptorSetsStatic<N>::~MVKCmdBindDescriptorSetsStatic() {
	if (_pipelineLayout) { _pipelineLayout->release(); }
}

template class MVKCmdBindDescriptorSetsStatic<1>;
template class MVKCmdBindDescriptorSetsStatic<4>;
template class MVKCmdBindDescriptorSetsStatic<8>;


#pragma mark -
#pragma mark MVKCmdBindDescriptorSetsDynamic

template <size_t N>
VkResult MVKCmdBindDescriptorSetsDynamic<N>::setContent(MVKCommandBuffer* cmdBuff,
														VkPipelineBindPoint pipelineBindPoint,
														VkPipelineLayout layout,
														uint32_t firstSet,
														uint32_t setCount,
														const VkDescriptorSet* pDescriptorSets,
														uint32_t dynamicOffsetCount,
														const uint32_t* pDynamicOffsets) {

	MVKCmdBindDescriptorSetsStatic<N>::setContent(cmdBuff, pipelineBindPoint, layout,
												  firstSet, setCount, pDescriptorSets);

	// Add the dynamic offsets
	_dynamicOffsets.clear();	// Clear for reuse
	_dynamicOffsets.reserve(dynamicOffsetCount);
	for (uint32_t doIdx = 0; doIdx < dynamicOffsetCount; doIdx++) {
		_dynamicOffsets.push_back(pDynamicOffsets[doIdx]);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdBindDescriptorSetsDynamic<N>::encode(MVKCommandEncoder* cmdEncoder) {
	MVKCmdBindDescriptorSetsStatic<N>::encode(cmdEncoder, _dynamicOffsets.contents());
}

template class MVKCmdBindDescriptorSetsDynamic<4>;
template class MVKCmdBindDescriptorSetsDynamic<8>;


#pragma mark -
#pragma mark MVKCmdPushConstants

template <size_t N>
VkResult MVKCmdPushConstants<N>::setContent(MVKCommandBuffer* cmdBuff,
											VkPipelineLayout layout,
											VkShaderStageFlags stageFlags,
											uint32_t offset,
											uint32_t size,
											const void* pValues) {
	_stageFlags = stageFlags;
	_offset = offset;

	_pushConstants.resize(size);
	std::copy_n((char*)pValues, size, _pushConstants.begin());

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdPushConstants<N>::encode(MVKCommandEncoder* cmdEncoder) {
    VkShaderStageFlagBits stages[] = {
        VK_SHADER_STAGE_VERTEX_BIT,
        VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
        VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
        VK_SHADER_STAGE_FRAGMENT_BIT,
        VK_SHADER_STAGE_COMPUTE_BIT
    };
    for (auto stage : stages) {
        if (mvkAreAllFlagsEnabled(_stageFlags, stage)) {
			cmdEncoder->getPushConstants(stage)->setPushConstants(_offset, _pushConstants.contents());
        }
    }
}

template class MVKCmdPushConstants<64>;
template class MVKCmdPushConstants<128>;
template class MVKCmdPushConstants<512>;


#pragma mark -
#pragma mark MVKCmdPushDescriptorSet

VkResult MVKCmdPushDescriptorSet::setContent(MVKCommandBuffer* cmdBuff,
											 VkPipelineBindPoint pipelineBindPoint,
											 VkPipelineLayout layout,
											 uint32_t set,
											 uint32_t descriptorWriteCount,
											 const VkWriteDescriptorSet* pDescriptorWrites) {
	if (_pipelineLayout) { _pipelineLayout->release(); }

	_pipelineBindPoint = pipelineBindPoint;
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_set = set;

	_pipelineLayout->retain();

	// Add the descriptor writes
	clearDescriptorWrites();	// Clear for reuse
	_descriptorWrites.reserve(descriptorWriteCount);
	for (uint32_t dwIdx = 0; dwIdx < descriptorWriteCount; dwIdx++) {
		_descriptorWrites.push_back(pDescriptorWrites[dwIdx]);
		VkWriteDescriptorSet& descWrite = _descriptorWrites.back();
		// Make a copy of the associated data.
		if (descWrite.pImageInfo) {
			auto* pNewImageInfo = new VkDescriptorImageInfo[descWrite.descriptorCount];
			std::copy_n(descWrite.pImageInfo, descWrite.descriptorCount, pNewImageInfo);
			descWrite.pImageInfo = pNewImageInfo;
		}
		if (descWrite.pBufferInfo) {
			auto* pNewBufferInfo = new VkDescriptorBufferInfo[descWrite.descriptorCount];
			std::copy_n(descWrite.pBufferInfo, descWrite.descriptorCount, pNewBufferInfo);
			descWrite.pBufferInfo = pNewBufferInfo;
		}
		if (descWrite.pTexelBufferView) {
			auto* pNewTexelBufferView = new VkBufferView[descWrite.descriptorCount];
			std::copy_n(descWrite.pTexelBufferView, descWrite.descriptorCount, pNewTexelBufferView);
			descWrite.pTexelBufferView = pNewTexelBufferView;
		}
		const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock = nullptr;
		for (const auto* next = (VkBaseInStructure*)descWrite.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
					break;
				}
				default:
					break;
			}
		}
		if (pInlineUniformBlock) {
			auto *pNewInlineUniformBlock = new VkWriteDescriptorSetInlineUniformBlock(*pInlineUniformBlock);
			pNewInlineUniformBlock->pNext = nullptr; // clear pNext just in case, no other extensions are supported at this time
			descWrite.pNext = pNewInlineUniformBlock;
		}
	}

	// Validate by encoding on a null encoder
	encode(nullptr);
	return _pipelineLayout->getConfigurationResult();
}

void MVKCmdPushDescriptorSet::encode(MVKCommandEncoder* cmdEncoder) {
	_pipelineLayout->pushDescriptorSet(cmdEncoder, _pipelineBindPoint, _descriptorWrites.contents(), _set);
}

MVKCmdPushDescriptorSet::~MVKCmdPushDescriptorSet() {
	clearDescriptorWrites();
	if (_pipelineLayout) { _pipelineLayout->release(); }
}

void MVKCmdPushDescriptorSet::clearDescriptorWrites() {
	for (VkWriteDescriptorSet &descWrite : _descriptorWrites) {
		if (descWrite.pImageInfo) { delete[] descWrite.pImageInfo; }
		if (descWrite.pBufferInfo) { delete[] descWrite.pBufferInfo; }
		if (descWrite.pTexelBufferView) { delete[] descWrite.pTexelBufferView; }

		const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock = nullptr;
		for (const auto* next = (VkBaseInStructure*)descWrite.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
					break;
				}
				default:
					break;
			}
		}
		if (pInlineUniformBlock) { delete pInlineUniformBlock; }
	}
	_descriptorWrites.clear();
}


#pragma mark -
#pragma mark MVKCmdPushDescriptorSetWithTemplate

VkResult MVKCmdPushDescriptorSetWithTemplate::setContent(MVKCommandBuffer* cmdBuff,
														 VkDescriptorUpdateTemplate descUpdateTemplate,
														 VkPipelineLayout layout,
														 uint32_t set,
														 const void* pData) {
	if (_pipelineLayout) { _pipelineLayout->release(); }
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_pipelineLayout->retain();
	_set = set;
	_descUpdateTemplate = (MVKDescriptorUpdateTemplate*)descUpdateTemplate;

	size_t oldSize = _dataSize;
	_dataSize = _descUpdateTemplate->getSize();
	if (_dataSize > oldSize) {
		free(_pData);
		_pData = malloc(_dataSize);
	}
	if (_pData && pData) {
		mvkCopy(_pData, pData, _dataSize);
	}

	// Validate by encoding on a null encoder
	encode(nullptr);
	return _pipelineLayout->getConfigurationResult();
}

void MVKCmdPushDescriptorSetWithTemplate::encode(MVKCommandEncoder* cmdEncoder) {
	_pipelineLayout->pushDescriptorSet(cmdEncoder, _descUpdateTemplate, _set, _pData);
}

MVKCmdPushDescriptorSetWithTemplate::~MVKCmdPushDescriptorSetWithTemplate() {
	if (_pipelineLayout) { _pipelineLayout->release(); }
	free(_pData);
}


#pragma mark -
#pragma mark MVKCmdSetEvent

VkResult MVKCmdSetEvent::setContent(MVKCommandBuffer* cmdBuff,
									VkEvent event,
									VkPipelineStageFlags stageMask) {
	_mvkEvent = (MVKEvent*)event;

	return VK_SUCCESS;
}

VkResult MVKCmdSetEvent::setContent(MVKCommandBuffer* cmdBuff,
									VkEvent event,
									const VkDependencyInfo* pDependencyInfo) {
	_mvkEvent = (MVKEvent*)event;

	return VK_SUCCESS;
}

void MVKCmdSetEvent::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->signalEvent(_mvkEvent, true);
}


#pragma mark -
#pragma mark MVKCmdResetEvent

VkResult MVKCmdResetEvent::setContent(MVKCommandBuffer* cmdBuff,
									  VkEvent event,
									  VkPipelineStageFlags2 stageMask) {
	_mvkEvent = (MVKEvent*)event;

	return VK_SUCCESS;
}

void MVKCmdResetEvent::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->signalEvent(_mvkEvent, false);
}


#pragma mark -
#pragma mark MVKCmdWaitEvents

template <size_t N>
VkResult MVKCmdWaitEvents<N>::setContent(MVKCommandBuffer* cmdBuff,
										 uint32_t eventCount,
										 const VkEvent* pEvents,
										 const VkDependencyInfo* pDependencyInfos) {
	_mvkEvents.clear();	// Clear for reuse
	_mvkEvents.reserve(eventCount);
	for (uint32_t i = 0; i < eventCount; i++) {
		_mvkEvents.push_back((MVKEvent*)pEvents[i]);
	}

	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdWaitEvents<N>::setContent(MVKCommandBuffer* cmdBuff,
										 uint32_t eventCount,
										 const VkEvent* pEvents,
										 VkPipelineStageFlags srcStageMask,
										 VkPipelineStageFlags dstStageMask,
										 uint32_t memoryBarrierCount,
										 const VkMemoryBarrier* pMemoryBarriers,
										 uint32_t bufferMemoryBarrierCount,
										 const VkBufferMemoryBarrier* pBufferMemoryBarriers,
										 uint32_t imageMemoryBarrierCount,
										 const VkImageMemoryBarrier* pImageMemoryBarriers) {
	_mvkEvents.clear();	// Clear for reuse
	_mvkEvents.reserve(eventCount);
	for (uint32_t i = 0; i < eventCount; i++) {
		_mvkEvents.push_back((MVKEvent*)pEvents[i]);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdWaitEvents<N>::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->endCurrentMetalEncoding();
	for (MVKEvent* mvkEvt : _mvkEvents) {
		mvkEvt->encodeWait(cmdEncoder->_mtlCmdBuffer);
	}
}

template class MVKCmdWaitEvents<1>;
template class MVKCmdWaitEvents<8>;

