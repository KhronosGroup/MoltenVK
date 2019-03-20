/*
 * MVKCmdPipeline.mm
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

#include "MVKCmdPipeline.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.h"


#pragma mark -
#pragma mark MVKCmdPipelineBarrier

void MVKCmdPipelineBarrier::setContent(VkPipelineStageFlags srcStageMask,
									   VkPipelineStageFlags dstStageMask,
									   VkDependencyFlags dependencyFlags,
									   uint32_t memoryBarrierCount,
									   const VkMemoryBarrier* pMemoryBarriers,
									   uint32_t bufferMemoryBarrierCount,
									   const VkBufferMemoryBarrier* pBufferMemoryBarriers,
									   uint32_t imageMemoryBarrierCount,
									   const VkImageMemoryBarrier* pImageMemoryBarriers) {
	_srcStageMask = srcStageMask;
	_dstStageMask = dstStageMask;
	_dependencyFlags = dependencyFlags;

	_memoryBarriers.clear();	// Clear for reuse
	_memoryBarriers.reserve(memoryBarrierCount);
	for (uint32_t i = 0; i < memoryBarrierCount; i++) {
		_memoryBarriers.push_back(pMemoryBarriers[i]);
	}

	_bufferMemoryBarriers.clear();	// Clear for reuse
	_bufferMemoryBarriers.reserve(bufferMemoryBarrierCount);
	for (uint32_t i = 0; i < bufferMemoryBarrierCount; i++) {
		_bufferMemoryBarriers.push_back(pBufferMemoryBarriers[i]);
	}

	_imageMemoryBarriers.clear();	// Clear for reuse
	_imageMemoryBarriers.reserve(imageMemoryBarrierCount);
	for (uint32_t i = 0; i < imageMemoryBarrierCount; i++) {
		_imageMemoryBarriers.push_back(pImageMemoryBarriers[i]);
	}
}

void MVKCmdPipelineBarrier::encode(MVKCommandEncoder* cmdEncoder) {

#if MVK_MACOS
    // Calls below invoke MTLBlitCommandEncoder so must apply this first
	if ( [cmdEncoder->_mtlRenderEncoder respondsToSelector: @selector(memoryBarrierWithScope:afterStages:beforeStages:)] ) {
		MTLRenderStages srcStages = mvkMTLRenderStagesFromVkPipelineStageFlags(_srcStageMask);
		MTLRenderStages dstStages = mvkMTLRenderStagesFromVkPipelineStageFlags(_dstStageMask);
		for (auto& mb : _memoryBarriers) {
			MTLBarrierScope scope = mvkMTLBarrierScopeFromVkAccessFlags(mb.dstAccessMask);
			scope |= mvkMTLBarrierScopeFromVkAccessFlags(mb.srcAccessMask);
			[cmdEncoder->_mtlRenderEncoder memoryBarrierWithScope: scope
													  afterStages: srcStages
													 beforeStages: dstStages];
		}
		std::vector<id<MTLResource>> resources;
		resources.reserve(_bufferMemoryBarriers.size() + _imageMemoryBarriers.size());
		for (auto& mb : _bufferMemoryBarriers) {
			auto* mvkBuff = (MVKBuffer*)mb.buffer;
			resources.push_back(mvkBuff->getMTLBuffer());
		}
		for (auto& mb : _imageMemoryBarriers) {
			auto* mvkImg = (MVKImage*)mb.image;
			resources.push_back(mvkImg->getMTLTexture());
		}
		if ( !resources.empty() ) {
			[cmdEncoder->_mtlRenderEncoder memoryBarrierWithResources: resources.data()
																count: resources.size()
														  afterStages: srcStages
														 beforeStages: dstStages];
		}
	} else {
		if ( !(_memoryBarriers.empty() && _imageMemoryBarriers.empty()) ) {
			[cmdEncoder->_mtlRenderEncoder textureBarrier];
		}
	}
#endif

    MVKCommandUse cmdUse = kMVKCommandUsePipelineBarrier;

	// Apply global memory barriers
    for (auto& mb : _memoryBarriers) {
        getDevice()->applyMemoryBarrier(_srcStageMask, _dstStageMask, &mb, cmdEncoder, cmdUse);
    }

    // Apply specific buffer barriers
    for (auto& mb : _bufferMemoryBarriers) {
        MVKBuffer* mvkBuff = (MVKBuffer*)mb.buffer;
        mvkBuff->applyBufferMemoryBarrier(_srcStageMask, _dstStageMask, &mb, cmdEncoder, cmdUse);
    }

    // Apply specific image barriers
    for (auto& mb : _imageMemoryBarriers) {
        MVKImage* mvkImg = (MVKImage*)mb.image;
        mvkImg->applyImageMemoryBarrier(_srcStageMask, _dstStageMask, &mb, cmdEncoder, cmdUse);
    }
}

MVKCmdPipelineBarrier::MVKCmdPipelineBarrier(MVKCommandTypePool<MVKCmdPipelineBarrier>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdBindPipeline

void MVKCmdBindPipeline::setContent(VkPipelineBindPoint pipelineBindPoint, VkPipeline pipeline) {
	_bindPoint = pipelineBindPoint;
	_pipeline = (MVKPipeline*)pipeline;
}

void MVKCmdBindPipeline::encode(MVKCommandEncoder* cmdEncoder) {
    cmdEncoder->bindPipeline(_bindPoint, _pipeline);
}

MVKCmdBindPipeline::MVKCmdBindPipeline(MVKCommandTypePool<MVKCmdBindPipeline>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

bool MVKCmdBindPipeline::isTessellationPipeline() {
	if (_bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS)
		return ((MVKGraphicsPipeline*)_pipeline)->isTessellationPipeline();
	else
		return false;
}


#pragma mark -
#pragma mark MVKCmdBindDescriptorSets

void MVKCmdBindDescriptorSets::setContent(VkPipelineBindPoint pipelineBindPoint,
                                          VkPipelineLayout layout,
                                          uint32_t firstSet,
                                          uint32_t setCount,
                                          const VkDescriptorSet* pDescriptorSets,
                                          uint32_t dynamicOffsetCount,
                                          const uint32_t* pDynamicOffsets) {
	_pipelineBindPoint = pipelineBindPoint;
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_firstSet = firstSet;

	// Add the descriptor sets
	_descriptorSets.clear();	// Clear for reuse
	_descriptorSets.reserve(setCount);
	for (uint32_t dsIdx = 0; dsIdx < setCount; dsIdx++) {
		_descriptorSets.push_back((MVKDescriptorSet*)pDescriptorSets[dsIdx]);
	}

	// Add the dynamic offsets
	_dynamicOffsets.clear();	// Clear for reuse
	_dynamicOffsets.reserve(dynamicOffsetCount);
	for (uint32_t doIdx = 0; doIdx < dynamicOffsetCount; doIdx++) {
		_dynamicOffsets.push_back(pDynamicOffsets[doIdx]);
	}
}

void MVKCmdBindDescriptorSets::encode(MVKCommandEncoder* cmdEncoder) {
	_pipelineLayout->bindDescriptorSets(cmdEncoder, _descriptorSets, _firstSet, _dynamicOffsets);
}

MVKCmdBindDescriptorSets::MVKCmdBindDescriptorSets(MVKCommandTypePool<MVKCmdBindDescriptorSets>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdPushConstants

void MVKCmdPushConstants::setContent(VkPipelineLayout layout,
									 VkShaderStageFlags stageFlags,
									 uint32_t offset,
									 uint32_t size,
									 const void* pValues) {
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_stageFlags = stageFlags;
	_offset = offset;

	_pushConstants.resize(size);
  std::copy_n((char*)pValues, size, _pushConstants.begin());
}

void MVKCmdPushConstants::encode(MVKCommandEncoder* cmdEncoder) {
    VkShaderStageFlagBits stages[] = {
        VK_SHADER_STAGE_VERTEX_BIT,
        VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
        VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
        VK_SHADER_STAGE_FRAGMENT_BIT,
        VK_SHADER_STAGE_COMPUTE_BIT
    };
    for (auto stage : stages) {
        if (mvkAreFlagsEnabled(_stageFlags, stage)) {
            cmdEncoder->getPushConstants(stage)->setPushConstants(_offset, _pushConstants);
        }
    }
}

MVKCmdPushConstants::MVKCmdPushConstants(MVKCommandTypePool<MVKCmdPushConstants>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}


#pragma mark -
#pragma mark MVKCmdPushDescriptorSet

void MVKCmdPushDescriptorSet::setContent(VkPipelineBindPoint pipelineBindPoint,
                                         VkPipelineLayout layout,
                                         uint32_t set,
                                         uint32_t descriptorWriteCount,
                                         const VkWriteDescriptorSet* pDescriptorWrites) {
	_pipelineBindPoint = pipelineBindPoint;
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_set = set;

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
	}
}

void MVKCmdPushDescriptorSet::encode(MVKCommandEncoder* cmdEncoder) {
	_pipelineLayout->pushDescriptorSet(cmdEncoder, _descriptorWrites, _set);
}

MVKCmdPushDescriptorSet::MVKCmdPushDescriptorSet(MVKCommandTypePool<MVKCmdPushDescriptorSet>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

MVKCmdPushDescriptorSet::~MVKCmdPushDescriptorSet() {
	clearDescriptorWrites();
}

void MVKCmdPushDescriptorSet::clearDescriptorWrites() {
	for (VkWriteDescriptorSet &descWrite : _descriptorWrites) {
		if (descWrite.pImageInfo) delete[] descWrite.pImageInfo;
		if (descWrite.pBufferInfo) delete[] descWrite.pBufferInfo;
		if (descWrite.pTexelBufferView) delete[] descWrite.pTexelBufferView;
	}
	_descriptorWrites.clear();
}


#pragma mark -
#pragma mark MVKCmdPushDescriptorSetWithTemplate

void MVKCmdPushDescriptorSetWithTemplate::setContent(VkDescriptorUpdateTemplateKHR descUpdateTemplate,
													 VkPipelineLayout layout,
													 uint32_t set,
													 const void* pData) {
	_descUpdateTemplate = (MVKDescriptorUpdateTemplate*)descUpdateTemplate;
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_set = set;
	if (_pData) delete[] (char*)_pData;
	// Work out how big the memory block in pData is.
	const VkDescriptorUpdateTemplateEntryKHR* pEntry =
		_descUpdateTemplate->getEntry(_descUpdateTemplate->getNumberOfEntries()-1);
	size_t size = pEntry->offset;
	// If we were given a stride, use that; otherwise, assume only one info
	// struct of the appropriate type.
	if (pEntry->stride)
		size += pEntry->stride * pEntry->descriptorCount;
	else switch (pEntry->descriptorType) {

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			size += sizeof(VkDescriptorBufferInfo);
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
		case VK_DESCRIPTOR_TYPE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			size += sizeof(VkDescriptorImageInfo);
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			size += sizeof(VkBufferView);
			break;

		default:
			break;
	}
	_pData = new char[size];
	memcpy(_pData, pData, size);
}

void MVKCmdPushDescriptorSetWithTemplate::encode(MVKCommandEncoder* cmdEncoder) {
	_pipelineLayout->pushDescriptorSet(cmdEncoder, _descUpdateTemplate, _set, _pData);
}

MVKCmdPushDescriptorSetWithTemplate::MVKCmdPushDescriptorSetWithTemplate(
	MVKCommandTypePool<MVKCmdPushDescriptorSetWithTemplate>* pool)
	: MVKCommand::MVKCommand((MVKCommandTypePool<MVKCommand>*)pool) {}

MVKCmdPushDescriptorSetWithTemplate::~MVKCmdPushDescriptorSetWithTemplate() {
	if (_pData) delete[] (char*)_pData;
}


#pragma mark -
#pragma mark Command creation functions

void mvkCmdPipelineBarrier(MVKCommandBuffer* cmdBuff,
						   VkPipelineStageFlags srcStageMask,
						   VkPipelineStageFlags dstStageMask,
						   VkDependencyFlags dependencyFlags,
						   uint32_t memoryBarrierCount,
						   const VkMemoryBarrier* pMemoryBarriers,
						   uint32_t bufferMemoryBarrierCount,
						   const VkBufferMemoryBarrier* pBufferMemoryBarriers,
						   uint32_t imageMemoryBarrierCount,
						   const VkImageMemoryBarrier* pImageMemoryBarriers) {
	MVKCmdPipelineBarrier* cmd = cmdBuff->_commandPool->_cmdPipelineBarrierPool.acquireObject();
	cmd->setContent(srcStageMask, dstStageMask, dependencyFlags,
					memoryBarrierCount, pMemoryBarriers,
					bufferMemoryBarrierCount, pBufferMemoryBarriers,
					imageMemoryBarrierCount, pImageMemoryBarriers);
	cmdBuff->addCommand(cmd);
}

void mvkCmdBindPipeline(MVKCommandBuffer* cmdBuff,
						VkPipelineBindPoint pipelineBindPoint,
						VkPipeline pipeline) {
	MVKCmdBindPipeline* cmd = cmdBuff->_commandPool->_cmdBindPipelinePool.acquireObject();
	cmd->setContent(pipelineBindPoint, pipeline);
	cmdBuff->recordBindPipeline(cmd);
	cmdBuff->addCommand(cmd);
}

void mvkCmdBindDescriptorSets(MVKCommandBuffer* cmdBuff,
							  VkPipelineBindPoint pipelineBindPoint,
							  VkPipelineLayout layout,
							  uint32_t firstSet,
							  uint32_t setCount,
							  const VkDescriptorSet* pDescriptorSets,
							  uint32_t dynamicOffsetCount,
							  const uint32_t* pDynamicOffsets) {
	MVKCmdBindDescriptorSets* cmd = cmdBuff->_commandPool->_cmdBindDescriptorSetsPool.acquireObject();
	cmd->setContent(pipelineBindPoint, layout, firstSet, setCount, pDescriptorSets, dynamicOffsetCount, pDynamicOffsets);
	cmdBuff->addCommand(cmd);
}

void mvkCmdPushConstants(MVKCommandBuffer* cmdBuff,
						 VkPipelineLayout layout,
						 VkShaderStageFlags stageFlags,
						 uint32_t offset,
						 uint32_t size,
						 const void* pValues) {
	MVKCmdPushConstants* cmd = cmdBuff->_commandPool->_cmdPushConstantsPool.acquireObject();
	cmd->setContent(layout, stageFlags, offset, size, pValues);
	cmdBuff->addCommand(cmd);
}

void mvkCmdPushDescriptorSet(MVKCommandBuffer* cmdBuff,
							 VkPipelineBindPoint pipelineBindPoint,
							 VkPipelineLayout layout,
							 uint32_t set,
							 uint32_t descriptorWriteCount,
							 const VkWriteDescriptorSet* pDescriptorWrites) {
	MVKCmdPushDescriptorSet* cmd = cmdBuff->_commandPool->_cmdPushDescriptorSetPool.acquireObject();
	cmd->setContent(pipelineBindPoint, layout, set, descriptorWriteCount, pDescriptorWrites);
	cmdBuff->addCommand(cmd);
}

void mvkCmdPushDescriptorSetWithTemplate(MVKCommandBuffer* cmdBuff,
										 VkDescriptorUpdateTemplateKHR descUpdateTemplate,
										 VkPipelineLayout layout,
										 uint32_t set,
										 const void* pData) {
	MVKCmdPushDescriptorSetWithTemplate* cmd = cmdBuff->_commandPool->_cmdPushSetWithTemplatePool.acquireObject();
	cmd->setContent(descUpdateTemplate, layout, set, pData);
	cmdBuff->addCommand(cmd);
}
