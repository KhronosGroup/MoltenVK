/*
 * MVKCmdPipeline.mm
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

#include "MVKCmdPipeline.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKPipeline.h"
#include "MVKAccelerationStructure.h"
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
			uint64_t sourceStageMask = mvkBarrierStagesFromPipelineStageFlags(b.srcStageMask), destStageMask = mvkBarrierStagesFromPipelineStageFlags(b.dstStageMask);
			cmdEncoder->setBarrier(sourceStageMask, destStageMask);
		}
	}

	// Apple GPUs do not support renderpass barriers, and do not support rendering/writing
	// to an attachment and then reading from that attachment within a single renderpass.
	// So, in the case where we are inside a Metal renderpass, we need to split those activities
	// into separate Metal renderpasses. Since this is a potentially expensive operation,
	// verify that at least one attachment is being used both as an input and render attachment
	// by checking for a VK_IMAGE_LAYOUT_GENERAL layout.
	// During subpass changes, or with dynamic rendering, if an input attachment is being used,
	// both VK_DEPENDENCY_BY_REGION_BIT and VK_ACCESS_INPUT_ATTACHMENT_READ_BIT will be set.
	if (cmdEncoder->_mtlRenderEncoder && mtlFeats.tileBasedDeferredRendering) {
		bool needsRenderpassRestart = false;
		for (auto& b : _barriers) {
			if (b.type == MVKPipelineBarrier::Image && b.newLayout == VK_IMAGE_LAYOUT_GENERAL) {
				needsRenderpassRestart = true;
				break;
			}
			if (mvkIsAnyFlagEnabled(_dependencyFlags, VK_DEPENDENCY_BY_REGION_BIT) &&
				mvkIsAnyFlagEnabled(b.dstAccessMask, VK_ACCESS_INPUT_ATTACHMENT_READ_BIT)) {

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

bool MVKCmdBindGraphicsPipeline::usesAccelerationStructures() {
	return ((MVKGraphicsPipeline*)_pipeline)->usesAccelerationStructures();
}

VkPipelineStageFlags2 MVKCmdBindGraphicsPipeline::getAccelerationStructureStages() {
	return ((MVKGraphicsPipeline*)_pipeline)->getAccelerationStructureStages();
}


#pragma mark -
#pragma mark MVKCmdBindComputePipeline

void MVKCmdBindComputePipeline::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->bindPipeline(VK_PIPELINE_BIND_POINT_COMPUTE, _pipeline);
}

bool MVKCmdBindComputePipeline::usesAccelerationStructures() {
	return ((MVKComputePipeline*)_pipeline)->usesAccelerationStructures();
}


#pragma mark -
#pragma mark MVKCmdBindRayTracingPipeline

void MVKCmdBindRayTracingPipeline::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->bindPipeline(VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, _pipeline);
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
	cmdEncoder->getState().bindDescriptorSets(_pipelineBindPoint, _pipelineLayout, _firstSet, static_cast<uint32_t>(_descriptorSets.size()), _descriptorSets.data(), static_cast<uint32_t>(dynamicOffsets.size()), dynamicOffsets.data());
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
	cmdEncoder->getState().pushConstants(_offset, static_cast<uint32_t>(_pushConstants.byteSize()), _pushConstants.data());
}

template class MVKCmdPushConstants<64>;
template class MVKCmdPushConstants<128>;
template class MVKCmdPushConstants<512>;


#pragma mark -
#pragma mark MVKCmdPushDescriptorSet

static void retainPushDescriptorResources(MVKSmallVector<MVKVulkanAPIObject*, 4>& retainedResources,
									  const MVKDescriptorSetLayout* layout, uint32_t binding,
									  VkDescriptorType type, uint32_t count,
									  const void* data, size_t stride) {
	bool immutableSamplers = layout->getBinding(binding)->hasImmutableSamplers();
	for (uint32_t i = 0; i < count; i++, data = static_cast<const char*>(data) + stride) {
		MVKVulkanAPIObject* resources[2] = {};
		switch (type) {
			case VK_DESCRIPTOR_TYPE_SAMPLER:
				if (!immutableSamplers) { resources[0] = (MVKSampler*)((VkDescriptorImageInfo*)data)->sampler; }
				break;
			case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
				resources[0] = (MVKImageView*)((VkDescriptorImageInfo*)data)->imageView;
				if (!immutableSamplers) { resources[1] = (MVKSampler*)((VkDescriptorImageInfo*)data)->sampler; }
				break;
			case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
				resources[0] = (MVKImageView*)((VkDescriptorImageInfo*)data)->imageView;
				break;
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
				resources[0] = (MVKBuffer*)((VkDescriptorBufferInfo*)data)->buffer;
				break;
			case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
				resources[0] = (MVKBufferView*)*(VkBufferView*)data;
				break;
			case VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR:
				resources[0] = (MVKAccelerationStructure*)*(VkAccelerationStructureKHR*)data;
				break;
			default:
				break;
		}
		for (auto* resource : resources) {
			if (resource) {
				resource->retain();
				retainedResources.push_back(resource);
			}
		}
	}
}

static void releasePushDescriptorResources(MVKSmallVector<MVKVulkanAPIObject*, 4>& retainedResources) {
	for (auto* resource : retainedResources) { resource->release(); }
	retainedResources.clear();
}

VkResult MVKCmdPushDescriptorSet::setContent(MVKCommandBuffer* cmdBuff,
											 VkPipelineBindPoint pipelineBindPoint,
											 VkPipelineLayout layout,
											 uint32_t set,
											 uint32_t descriptorWriteCount,
											 const VkWriteDescriptorSet* pDescriptorWrites) {
	auto* mvkLayout = (MVKPipelineLayout*)layout;
	mvkLayout->retain();
	if (_pipelineLayout) { _pipelineLayout->release(); }

	_pipelineBindPoint = pipelineBindPoint;
	_pipelineLayout = mvkLayout;
	_set = set;

	// Add the descriptor writes
	clearDescriptorWrites();	// Clear for reuse
	_descriptorWrites.reserve(descriptorWriteCount);
	bool retainResources = mvkLayout->getEnabledAccelerationStructureFeatures().accelerationStructure;
	auto* descriptorSetLayout = retainResources ? mvkLayout->getDescriptorSetLayout(set) : nullptr;
	for (uint32_t dwIdx = 0; dwIdx < descriptorWriteCount; dwIdx++) {
		_descriptorWrites.push_back(pDescriptorWrites[dwIdx]);
		VkWriteDescriptorSet& descWrite = _descriptorWrites.back();
		descWrite.pNext = nullptr;
		descWrite.pImageInfo = nullptr;
		descWrite.pBufferInfo = nullptr;
		descWrite.pTexelBufferView = nullptr;
		// Make a copy of the associated data.
		switch (descWrite.descriptorType) {
			case VK_DESCRIPTOR_TYPE_SAMPLER:
			case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT: {
				auto* info = new VkDescriptorImageInfo[descWrite.descriptorCount];
				std::copy_n(pDescriptorWrites[dwIdx].pImageInfo, descWrite.descriptorCount, info);
				descWrite.pImageInfo = info;
				if (retainResources) { retainPushDescriptorResources(_retainedResources, descriptorSetLayout,
					descWrite.dstBinding, descWrite.descriptorType, descWrite.descriptorCount, info, sizeof(*info)); }
				break;
			}
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: {
				auto* info = new VkDescriptorBufferInfo[descWrite.descriptorCount];
				std::copy_n(pDescriptorWrites[dwIdx].pBufferInfo, descWrite.descriptorCount, info);
				descWrite.pBufferInfo = info;
				if (retainResources) { retainPushDescriptorResources(_retainedResources, descriptorSetLayout,
					descWrite.dstBinding, descWrite.descriptorType, descWrite.descriptorCount, info, sizeof(*info)); }
				break;
			}
			case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER: {
				auto* views = new VkBufferView[descWrite.descriptorCount];
				std::copy_n(pDescriptorWrites[dwIdx].pTexelBufferView, descWrite.descriptorCount, views);
				descWrite.pTexelBufferView = views;
				if (retainResources) { retainPushDescriptorResources(_retainedResources, descriptorSetLayout,
					descWrite.dstBinding, descWrite.descriptorType, descWrite.descriptorCount, views, sizeof(*views)); }
				break;
			}
			default:
				break;
		}
		const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock = nullptr;
		const VkWriteDescriptorSetAccelerationStructureKHR* pAccelerationStructures = nullptr;
		for (const auto* next = (VkBaseInStructure*)pDescriptorWrites[dwIdx].pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
					break;
				}
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR: {
					pAccelerationStructures = (VkWriteDescriptorSetAccelerationStructureKHR*)next;
					break;
				}
				default:
					break;
			}
		}
		if (descWrite.descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK && pInlineUniformBlock) {
			auto *pNewInlineUniformBlock = new VkWriteDescriptorSetInlineUniformBlock(*pInlineUniformBlock);
			pNewInlineUniformBlock->pNext = nullptr;
			auto* data = new uint8_t[pInlineUniformBlock->dataSize];
			std::copy_n(static_cast<const uint8_t*>(pInlineUniformBlock->pData), pInlineUniformBlock->dataSize, data);
			pNewInlineUniformBlock->pData = data;
			descWrite.pNext = pNewInlineUniformBlock;
		} else if (descWrite.descriptorType == VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR && pAccelerationStructures) {
				auto* pNewAccelerationStructures = new VkWriteDescriptorSetAccelerationStructureKHR(*pAccelerationStructures);
				pNewAccelerationStructures->pNext = nullptr;
				auto* handles = new VkAccelerationStructureKHR[pAccelerationStructures->accelerationStructureCount];
				std::copy_n(pAccelerationStructures->pAccelerationStructures, pAccelerationStructures->accelerationStructureCount, handles);
				pNewAccelerationStructures->pAccelerationStructures = handles;
				descWrite.pNext = pNewAccelerationStructures;
				if (retainResources) { retainPushDescriptorResources(_retainedResources, descriptorSetLayout,
					descWrite.dstBinding, descWrite.descriptorType,
					pAccelerationStructures->accelerationStructureCount, handles, sizeof(*handles)); }
		}
	}

	return VK_SUCCESS;
}

void MVKCmdPushDescriptorSet::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().pushDescriptorSet(_pipelineBindPoint,
	                                         _pipelineLayout,
	                                         _set,
	                                         static_cast<uint32_t>(_descriptorWrites.size()),
	                                         _descriptorWrites.data());
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

		if (descWrite.pNext) {
			auto* next = (VkBaseInStructure*)descWrite.pNext;
			if (next->sType == VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR) {
				auto* accelerationStructures = (VkWriteDescriptorSetAccelerationStructureKHR*)next;
				delete[] accelerationStructures->pAccelerationStructures;
				delete accelerationStructures;
			} else if (next->sType == VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK) {
				auto* inlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
				delete[] static_cast<const uint8_t*>(inlineUniformBlock->pData);
				delete inlineUniformBlock;
			}
		}
	}
	_descriptorWrites.clear();
	releasePushDescriptorResources(_retainedResources);
}


#pragma mark -
#pragma mark MVKCmdPushDescriptorSetWithTemplate

VkResult MVKCmdPushDescriptorSetWithTemplate::setContent(MVKCommandBuffer* cmdBuff,
														 VkDescriptorUpdateTemplate descUpdateTemplate,
														 VkPipelineLayout layout,
														 uint32_t set,
														 const void* pData) {
	auto* mvkDUT = (MVKDescriptorUpdateTemplate*)descUpdateTemplate;
	auto* mvkLayout = (MVKPipelineLayout*)layout;
	mvkDUT->retain();
	mvkLayout->retain();
	if (_descUpdateTemplate) { _descUpdateTemplate->release(); }
	if (_pipelineLayout) { _pipelineLayout->release(); }
	_pipelineLayout = mvkLayout;
	_set = set;
	_descUpdateTemplate = mvkDUT;
	releasePushDescriptorResources(_retainedResources);

	size_t oldSize = _dataSize;
	_dataSize = _descUpdateTemplate->getSize();
	if (_dataSize > oldSize) {
		free(_pData);
		_pData = malloc(_dataSize);
	}
	if (_pData && pData) {
		mvkCopy(_pData, pData, _dataSize);
		if (mvkLayout->getEnabledAccelerationStructureFeatures().accelerationStructure) {
			auto* descriptorSetLayout = mvkLayout->getDescriptorSetLayout(set);
			for (uint32_t i = 0; i < mvkDUT->getNumberOfEntries(); i++) {
				auto* entry = mvkDUT->getEntry(i);
				retainPushDescriptorResources(_retainedResources, descriptorSetLayout,
					entry->dstBinding, entry->descriptorType, entry->descriptorCount,
					static_cast<const char*>(_pData) + entry->offset, entry->stride);
			}
		}
	}

	return VK_SUCCESS;
}

void MVKCmdPushDescriptorSetWithTemplate::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().pushDescriptorSet(_descUpdateTemplate, _pipelineLayout, _set, _pData);
}

MVKCmdPushDescriptorSetWithTemplate::~MVKCmdPushDescriptorSetWithTemplate() {
	releasePushDescriptorResources(_retainedResources);
	if (_descUpdateTemplate) { _descUpdateTemplate->release(); }
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
