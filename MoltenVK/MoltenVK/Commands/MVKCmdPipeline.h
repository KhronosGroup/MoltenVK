/*
 * MVKCmdPipeline.h
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

#pragma once

#include "MVKCommand.h"
#include "MVKMTLResourceBindings.h"
#include "MVKSync.h"
#include "MVKSmallVector.h"

class MVKCommandBuffer;
class MVKPipeline;
class MVKPipelineLayout;
class MVKDescriptorSet;
class MVKDescriptorUpdateTemplate;


#pragma mark -
#pragma mark MVKCmdExecuteCommands

/**
 * Vulkan command to execute secondary command buffers.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdExecuteCommands : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t commandBuffersCount,
						const VkCommandBuffer* pCommandBuffers);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<MVKCommandBuffer*, N> _secondaryCommandBuffers;
};

// Concrete template class implementations.
typedef MVKCmdExecuteCommands<1> MVKCmdExecuteCommands1;
typedef MVKCmdExecuteCommands<16> MVKCmdExecuteCommandsMulti;


#pragma mark -
#pragma mark MVKCmdPipelineBarrier

/**
 * Vulkan command to add a pipeline barrier.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdPipelineBarrier : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						const VkDependencyInfo* pDependencyInfo);

	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkPipelineStageFlags srcStageMask,
						VkPipelineStageFlags dstStageMask,
						VkDependencyFlags dependencyFlags,
						uint32_t memoryBarrierCount,
						const VkMemoryBarrier* pMemoryBarriers,
						uint32_t bufferMemoryBarrierCount,
						const VkBufferMemoryBarrier* pBufferMemoryBarriers,
						uint32_t imageMemoryBarrierCount,
						const VkImageMemoryBarrier* pImageMemoryBarriers);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	bool coversTextures();

	MVKSmallVector<MVKPipelineBarrier, N> _barriers;
	VkDependencyFlags _dependencyFlags;
};

// Concrete template class implementations.
typedef MVKCmdPipelineBarrier<1> MVKCmdPipelineBarrier1;
typedef MVKCmdPipelineBarrier<4> MVKCmdPipelineBarrier4;
typedef MVKCmdPipelineBarrier<32> MVKCmdPipelineBarrierMulti;


#pragma mark -
#pragma mark MVKCmdBindPipeline

/** Abstract Vulkan command to bind a pipeline. */
class MVKCmdBindPipeline : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff, VkPipeline pipeline);

	virtual bool isTessellationPipeline() { return false; };

protected:
	MVKPipeline* _pipeline;

};


#pragma mark -
#pragma mark MVKCmdBindGraphicsPipeline

class MVKCmdBindGraphicsPipeline : public MVKCmdBindPipeline {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

	bool isTessellationPipeline() override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

};


#pragma mark -
#pragma mark MVKCmdBindComputePipeline

class MVKCmdBindComputePipeline : public MVKCmdBindPipeline {

public:
	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

};


#pragma mark -
#pragma mark MVKCmdBindDescriptorSetsStatic

/**
 * Vulkan command to bind descriptor sets without dynamic offsets.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdBindDescriptorSetsStatic : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkPipelineBindPoint pipelineBindPoint,
						VkPipelineLayout layout,
						uint32_t firstSet,
						uint32_t setCount,
						const VkDescriptorSet* pDescriptorSets);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	~MVKCmdBindDescriptorSetsStatic() override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	void encode(MVKCommandEncoder* cmdEncoder, MVKArrayRef<uint32_t> dynamicOffsets);

	MVKSmallVector<MVKDescriptorSet*, N> _descriptorSets;
	MVKPipelineLayout* _pipelineLayout = nullptr;
	VkPipelineBindPoint _pipelineBindPoint;
	uint32_t _firstSet;
};

// Concrete template class implementations.
typedef MVKCmdBindDescriptorSetsStatic<1> MVKCmdBindDescriptorSetsStatic1;
typedef MVKCmdBindDescriptorSetsStatic<4> MVKCmdBindDescriptorSetsStatic4;
typedef MVKCmdBindDescriptorSetsStatic<8> MVKCmdBindDescriptorSetsStaticMulti;


#pragma mark -
#pragma mark MVKCmdBindDescriptorSetsDynamic

/**
 * Vulkan command to bind descriptor sets with dynamic offsets.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdBindDescriptorSetsDynamic : public MVKCmdBindDescriptorSetsStatic<N> {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkPipelineBindPoint pipelineBindPoint,
						VkPipelineLayout layout,
						uint32_t firstSet,
						uint32_t setCount,
						const VkDescriptorSet* pDescriptorSets,
						uint32_t dynamicOffsetCount,
						const uint32_t* pDynamicOffsets);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<uint32_t, N> _dynamicOffsets;
};

// Concrete template class implementations.
typedef MVKCmdBindDescriptorSetsDynamic<4> MVKCmdBindDescriptorSetsDynamic4;
typedef MVKCmdBindDescriptorSetsDynamic<8> MVKCmdBindDescriptorSetsDynamicMulti;


#pragma mark -
#pragma mark MVKCmdPushConstants

/**
 * Vulkan command to bind push constants.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdPushConstants : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkPipelineLayout layout,
						VkShaderStageFlags stageFlags,
						uint32_t offset,
						uint32_t size,
						const void* pValues);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<char, N> _pushConstants;
	VkShaderStageFlags _stageFlags;
	uint32_t _offset;
};

// Concrete template class implementations.
typedef MVKCmdPushConstants<64> MVKCmdPushConstants64;
typedef MVKCmdPushConstants<128> MVKCmdPushConstants128;
typedef MVKCmdPushConstants<512> MVKCmdPushConstantsMulti;


#pragma mark -
#pragma mark MVKCmdPushDescriptorSet

class MVKCmdPushDescriptorSet : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkPipelineBindPoint pipelineBindPoint,
						VkPipelineLayout layout,
						uint32_t set,
						uint32_t descriptorWriteCount,
						const VkWriteDescriptorSet* pDescriptorWrites);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	~MVKCmdPushDescriptorSet() override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
	void clearDescriptorWrites();

	MVKSmallVector<VkWriteDescriptorSet, 1> _descriptorWrites;
	MVKPipelineLayout* _pipelineLayout = nullptr;
	VkPipelineBindPoint _pipelineBindPoint;
	uint32_t _set;
};


#pragma mark -
#pragma mark MVKCmdPushDescriptorSetWithTemplate

class MVKCmdPushDescriptorSetWithTemplate : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkDescriptorUpdateTemplate descUpdateTemplate,
						VkPipelineLayout layout,
						uint32_t set,
						const void* pData);

	void encode(MVKCommandEncoder* cmdEncoder) override;

	~MVKCmdPushDescriptorSetWithTemplate() override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKDescriptorUpdateTemplate* _descUpdateTemplate = nullptr;
	MVKPipelineLayout* _pipelineLayout = nullptr;
	void* _pData = nullptr;
	size_t _dataSize = 0;
	uint32_t _set = 0;
};


#pragma mark -
#pragma mark MVKCmdSetEvent

class MVKCmdSetEvent : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkEvent event,
						const VkDependencyInfo* pDependencyInfo);

	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkEvent event,
						VkPipelineStageFlags stageMask);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKEvent* _mvkEvent;
};


#pragma mark -
#pragma mark MVKCmdResetEvent

class MVKCmdResetEvent : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						VkEvent event,
						VkPipelineStageFlags2 stageMask);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKEvent* _mvkEvent;
};


#pragma mark -
#pragma mark MVKCmdWaitEvents

/** Vulkan command to wait for an event to be signaled. */
/**
 * Vulkan command to wait for an event to be signaled.
 * Template class to balance vector pre-allocations between very common low counts and fewer larger counts.
 */
template <size_t N>
class MVKCmdWaitEvents : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t eventCount,
						const VkEvent* pEvents,
						const VkDependencyInfo* pDependencyInfos);

	VkResult setContent(MVKCommandBuffer* cmdBuff,
						uint32_t eventCount,
						const VkEvent* pEvents,
						VkPipelineStageFlags srcStageMask,
						VkPipelineStageFlags dstStageMask,
						uint32_t memoryBarrierCount,
						const VkMemoryBarrier* pMemoryBarriers,
						uint32_t bufferMemoryBarrierCount,
						const VkBufferMemoryBarrier* pBufferMemoryBarriers,
						uint32_t imageMemoryBarrierCount,
						const VkImageMemoryBarrier* pImageMemoryBarriers);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<MVKEvent*, N> _mvkEvents;

};

// Concrete template class implementations.
typedef MVKCmdWaitEvents<1> MVKCmdWaitEvents1;
typedef MVKCmdWaitEvents<8> MVKCmdWaitEventsMulti;
