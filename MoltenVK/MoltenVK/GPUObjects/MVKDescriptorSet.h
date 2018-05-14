/*
 * MVKDescriptorSet.h
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKDevice.h"
#include "MVKImage.h"
#include <MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.h>
#include <forward_list>
#include <vector>

using namespace mvk;


class MVKDescriptorPool;
class MVKDescriptorBinding;
class MVKDescriptorSet;
class MVKDescriptorSetLayout;
class MVKPipelineLayout;
class MVKCommandEncoder;


#pragma mark MVKShaderStageResourceBinding

/** Indicates the Metal resource indexes used by a single shader stage in a descriptor binding. */
typedef struct MVKShaderStageResourceBinding {
	uint32_t bufferIndex = 0;
	uint32_t textureIndex = 0;
	uint32_t samplerIndex = 0;

	MVKShaderStageResourceBinding operator+ (const MVKShaderStageResourceBinding& rhs);
	MVKShaderStageResourceBinding& operator+= (const MVKShaderStageResourceBinding& rhs);

} MVKShaderStageResourceBinding;


#pragma mark MVKShaderResourceBinding

/** Indicates the Metal resource indexes used by each shader stage in a descriptor binding. */
typedef struct MVKShaderResourceBinding {
	MVKShaderStageResourceBinding vertexStage;
	MVKShaderStageResourceBinding fragmentStage;
    MVKShaderStageResourceBinding computeStage;

	MVKShaderResourceBinding operator+ (const MVKShaderResourceBinding& rhs);
	MVKShaderResourceBinding& operator+= (const MVKShaderResourceBinding& rhs);

} MVKShaderResourceBinding;


#pragma mark -
#pragma mark MVKDescriptorSetLayoutBinding

/** Represents a Vulkan descriptor set layout binding. */
class MVKDescriptorSetLayoutBinding : public MVKConfigurableObject {

public:

	/** Encodes this binding layout and the specified descriptor set binding on the specified command encoder. */
    void bind(MVKCommandEncoder* cmdEncoder,
              MVKDescriptorBinding& descBinding,
              MVKShaderResourceBinding& dslMTLRezIdxOffsets,
              std::vector<uint32_t>& dynamicOffsets,
              uint32_t* pDynamicOffsetIndex);

	/** Populates the specified shader converter context, at the specified descriptor set binding. */
	void populateShaderConverterContext(SPIRVToMSLConverterContext& context,
                                        MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                        uint32_t dslIndex);

	/** Constructs an instance. */
	MVKDescriptorSetLayoutBinding(MVKDescriptorSetLayout* layout,
								  const VkDescriptorSetLayoutBinding* pBinding);

protected:
	friend class MVKDescriptorBinding;

	VkResult initMetalResourceIndexOffsets(MVKShaderStageResourceBinding* pBindingIndexes,
                                           MVKShaderStageResourceBinding* pDescSetCounts,
                                           const VkDescriptorSetLayoutBinding* pBinding);

	VkDescriptorSetLayoutBinding _info;
	std::vector<MVKSampler*> _immutableSamplers;
	MVKShaderResourceBinding _mtlResourceIndexOffsets;
    bool _applyToVertexStage;
    bool _applyToFragmentStage;
    bool _applyToComputeStage;
};


#pragma mark -
#pragma mark MVKDescriptorSetLayout

/** Represents a Vulkan descriptor set layout. */
class MVKDescriptorSetLayout : public MVKBaseDeviceObject {

public:

	/** Encodes this descriptor set layout and the specified descriptor set on the specified command encoder. */
    void bindDescriptorSet(MVKCommandEncoder* cmdEncoder,
                           MVKDescriptorSet* descSet,
                           MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                           std::vector<uint32_t>& dynamicOffsets,
                           uint32_t* pDynamicOffsetIndex);


	/** Populates the specified shader converter context, at the specified DSL index. */
	void populateShaderConverterContext(SPIRVToMSLConverterContext& context,
                                        MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                        uint32_t dslIndex);

	/** Constructs an instance for the specified device. */
	MVKDescriptorSetLayout(MVKDevice* device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo);

protected:

	friend class MVKDescriptorSetLayoutBinding;
	friend class MVKPipelineLayout;
	friend class MVKDescriptorSet;

	std::vector<MVKDescriptorSetLayoutBinding> _bindings;
	MVKShaderResourceBinding _mtlResourceCounts;
};


#pragma mark -
#pragma mark MVKDescriptorBinding

/** Represents a Vulkan descriptor binding. */
class MVKDescriptorBinding : public MVKBaseObject {

public:

	/**
	 * Updates the internal element bindings from the specified content.
	 *
	 * Depending on the descriptor type of the descriptor set, the binding content is 
	 * extracted from one of the specified pImageInfo, pBufferInfo, or pTexelBufferView 
	 * arrays, and the other arrays are ignored (and may be a null pointer).
	 *
	 * The srcStartIndex parameter indicates the index of the initial pDescriptor element
	 * at which to start reading, and the dstStartIndex parameter indicates the index of 
	 * the initial internal element at which to start writing.
	 * 
	 * The count parameter indicates how many internal elements should be updated, and 
	 * may be larger than the number of descriptors that can be updated in this instance.
	 * If count is larger than the number of internal elements remaining after dstStartIndex,
	 * only the remaining elements will be updated, and the number of pDescriptors that were
	 * not read will be returned, so that the remaining unread pDescriptors can be read by 
	 * another MVKDescriptorBinding instance within the same descriptor set. If all of the
	 * remaining pDescriptors are read by this intance, this function returns zero, indicating
	 * that there is nothing left to be read by another MVKDescriptorBinding instance.
	 */
	uint32_t writeBindings(uint32_t srcStartIndex,
						   uint32_t dstStartIndex,
						   uint32_t count,
						   const VkDescriptorImageInfo* pImageInfo,
						   const VkDescriptorBufferInfo* pBufferInfo,
						   const VkBufferView* pTexelBufferView);

	/**
	 * Updates the specified content arrays from the internal element bindings.
	 *
	 * Depending on the descriptor type of the descriptor set, the binding content is
	 * placed into one of the specified pImageInfo, pBufferInfo, or pTexelBufferView 
	 * arrays, and the other arrays are ignored (and may be a null pointer).
	 *
	 * The srcStartIndex parameter indicates the index of the initial internal element 
	 * at which to start reading, and the dstStartIndex parameter indicates the index of
	 * the initial pDescriptor element at which to start writing.
	 *
	 * The count parameter indicates how many internal elements should be read, and may
	 * be larger than the number of descriptors that can be read from this instance. 
	 * If count is larger than the number of internal elements remaining after srcStartIndex,
	 * only the remaining elements will be read, and the number of pDescriptors that were not
	 * updated will be returned, so that the remaining pDescriptors can be updated by another
	 * MVKDescriptorBinding instance within the same descriptor set. If all of the remaining
	 * pDescriptors are updated by this intance, this function returns zero, indicating that
	 * there is nothing left to be updated by another MVKDescriptorBinding instance.
	 */
	uint32_t readBindings(uint32_t srcStartIndex,
						  uint32_t dstStartIndex,
						  uint32_t count,
						  VkDescriptorImageInfo* pImageInfo,
						  VkDescriptorBufferInfo* pBufferInfo,
						  VkBufferView* pTexelBufferView);

    /** Returns whether this instance represents the specified Vulkan binding point. */
    bool hasBinding(uint32_t binding);

	/** Constructs an instance. */
	MVKDescriptorBinding(MVKDescriptorSetLayoutBinding* pBindingLayout);

protected:
	friend class MVKDescriptorSetLayoutBinding;

	void initMTLSamplers(MVKDescriptorSetLayoutBinding* pBindingLayout);

	MVKDescriptorSetLayoutBinding* _pBindingLayout;
	std::vector<VkDescriptorImageInfo> _imageBindings;
	std::vector<VkDescriptorBufferInfo> _bufferBindings;
	std::vector<VkBufferView> _texelBufferBindings;
	std::vector<id<MTLBuffer>> _mtlBuffers;
	std::vector<NSUInteger> _mtlBufferOffsets;
	std::vector<id<MTLTexture>> _mtlTextures;
	std::vector<id<MTLSamplerState>> _mtlSamplers;
	bool _hasDynamicSamplers;
};


#pragma mark -
#pragma mark MVKDescriptorSet

/** Represents a Vulkan descriptor set. */
class MVKDescriptorSet : public MVKBaseDeviceObject {

public:

	/** Updates the resource bindings in this instance from the specified content. */
	template<typename DescriptorAction>
	void writeDescriptorSets(const DescriptorAction* pDescriptorAction,
							 const VkDescriptorImageInfo* pImageInfo,
							 const VkDescriptorBufferInfo* pBufferInfo,
							 const VkBufferView* pTexelBufferView);

	/** 
	 * Reads the resource bindings defined in the specified content 
	 * from this instance into the specified collection of bindings.
	 */
	void readDescriptorSets(const VkCopyDescriptorSet* pDescriptorCopies,
							VkDescriptorImageInfo* pImageInfo,
							VkDescriptorBufferInfo* pBufferInfo,
							VkBufferView* pTexelBufferView);

	/** Constructs an instance for the specified device. */
	MVKDescriptorSet(MVKDevice* device, MVKDescriptorSetLayout* layout);

protected:
	friend class MVKDescriptorSetLayout;

    MVKDescriptorBinding* getBinding(uint32_t binding);

	std::vector<MVKDescriptorBinding> _bindings;
};


#pragma mark -
#pragma mark MVKDescriptorPool

/** Represents a Vulkan descriptor pool. */
class MVKDescriptorPool : public MVKBaseDeviceObject {

public:

	/** Allocates the specified number of descriptor sets. */
	VkResult allocateDescriptorSets(uint32_t count,
									const VkDescriptorSetLayout* pSetLayouts,
									VkDescriptorSet* pDescriptorSets);

	/** Free's up the specified descriptor set. */
	VkResult freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets);

	/** Destoys all currently allocated descriptor sets. */
	VkResult reset(VkDescriptorPoolResetFlags flags);

	/** Constructs an instance for the specified device. */
	MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo);

	/** Destructor. */
	~MVKDescriptorPool() override;

protected:
    uint32_t _maxSets;
	std::forward_list<MVKDescriptorSet*> _allocatedSets;
	size_t _allocatedSetCount;
};


#pragma mark -
#pragma mark Support functions

/** Updates the resource bindings in the descriptor sets inditified in the specified content. */
void mvkUpdateDescriptorSets(uint32_t writeCount,
							const VkWriteDescriptorSet* pDescriptorWrites,
							uint32_t copyCount,
							const VkCopyDescriptorSet* pDescriptorCopies);

/**
 * If the shader stage binding has a binding defined for the specified stage, populates
 * the context at the descriptor set binding from the shader stage resource binding.
 */
void mvkPopulateShaderConverterContext(SPIRVToMSLConverterContext& context,
									   MVKShaderStageResourceBinding& ssRB,
									   spv::ExecutionModel stage,
									   uint32_t descriptorSetIndex,
									   uint32_t bindingIndex);




