/*
 * MVKDescriptorSet.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKImage.h"
#include "MVKVector.h"
#include <MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.h>
#include <unordered_set>
#include <unordered_map>
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
	MVKShaderStageResourceBinding stages[kMVKShaderStageMax];

	uint32_t getMaxBufferIndex();
	uint32_t getMaxTextureIndex();
	uint32_t getMaxSamplerIndex();

	MVKShaderResourceBinding operator+ (const MVKShaderResourceBinding& rhs);
	MVKShaderResourceBinding& operator+= (const MVKShaderResourceBinding& rhs);

} MVKShaderResourceBinding;


#pragma mark -
#pragma mark MVKDescriptorSetLayoutBinding

/** Represents a Vulkan descriptor set layout binding. */
class MVKDescriptorSetLayoutBinding : public MVKBaseDeviceObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

	/** Encodes this binding layout and the specified descriptor set binding on the specified command encoder. */
    void bind(MVKCommandEncoder* cmdEncoder,
              MVKDescriptorBinding& descBinding,
              MVKShaderResourceBinding& dslMTLRezIdxOffsets,
              MVKVector<uint32_t>& dynamicOffsets,
              uint32_t* pDynamicOffsetIndex);

    /** Encodes this binding layout and the specified descriptor binding on the specified command encoder immediately. */
    void push(MVKCommandEncoder* cmdEncoder,
              uint32_t& dstArrayElement,
              uint32_t& descriptorCount,
              uint32_t& descriptorsPushed,
              VkDescriptorType descriptorType,
              size_t stride,
              const void* pData,
              MVKShaderResourceBinding& dslMTLRezIdxOffsets);

	/** Populates the specified shader converter context, at the specified descriptor set binding. */
	void populateShaderConverterContext(SPIRVToMSLConverterContext& context,
                                        MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                        uint32_t dslIndex);

	/** Constructs an instance. */
	MVKDescriptorSetLayoutBinding(MVKDevice* device,
								  MVKDescriptorSetLayout* layout,
								  const VkDescriptorSetLayoutBinding* pBinding);

	MVKDescriptorSetLayoutBinding(const MVKDescriptorSetLayoutBinding& binding);

	/** Destuctor. */
	~MVKDescriptorSetLayoutBinding() override;

protected:
	friend class MVKDescriptorBinding;
	friend class MVKPipelineLayout;

	void initMetalResourceIndexOffsets(MVKShaderStageResourceBinding* pBindingIndexes,
									   MVKShaderStageResourceBinding* pDescSetCounts,
									   const VkDescriptorSetLayoutBinding* pBinding);

	MVKDescriptorSetLayout* _layout;
	VkDescriptorSetLayoutBinding _info;
	std::vector<MVKSampler*> _immutableSamplers;
	MVKShaderResourceBinding _mtlResourceIndexOffsets;
	bool _applyToStage[kMVKShaderStageMax];
};


#pragma mark -
#pragma mark MVKDescriptorSetLayout

/** Represents a Vulkan descriptor set layout. */
class MVKDescriptorSetLayout : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT_EXT; }

	/** Encodes this descriptor set layout and the specified descriptor set on the specified command encoder. */
    void bindDescriptorSet(MVKCommandEncoder* cmdEncoder,
                           MVKDescriptorSet* descSet,
                           MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                           MVKVector<uint32_t>& dynamicOffsets,
                           uint32_t* pDynamicOffsetIndex);


	/** Encodes this descriptor set layout and the specified descriptor updates on the specified command encoder immediately. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   MVKVector<VkWriteDescriptorSet>& descriptorWrites,
						   MVKShaderResourceBinding& dslMTLRezIdxOffsets);


	/** Encodes this descriptor set layout and the updates from the given template on the specified command encoder immediately. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   MVKDescriptorUpdateTemplate* descUpdateTemplates,
						   const void* pData,
						   MVKShaderResourceBinding& dslMTLRezIdxOffsets);


	/** Populates the specified shader converter context, at the specified DSL index. */
	void populateShaderConverterContext(SPIRVToMSLConverterContext& context,
                                        MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                        uint32_t dslIndex);

	/** Returns true if this layout is for push descriptors only. */
	bool isPushDescriptorLayout() const { return _isPushDescriptorLayout; }

	/** Constructs an instance for the specified device. */
	MVKDescriptorSetLayout(MVKDevice* device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo);

protected:

	friend class MVKDescriptorSetLayoutBinding;
	friend class MVKPipelineLayout;
	friend class MVKDescriptorSet;

	void propogateDebugName() override {}
	MVKVectorInline<MVKDescriptorSetLayoutBinding, 8> _bindings;
	std::unordered_map<uint32_t, uint32_t> _bindingToIndex;
	MVKShaderResourceBinding _mtlResourceCounts;
	bool _isPushDescriptorLayout : 1;
};


#pragma mark -
#pragma mark MVKDescriptorBinding

/** Represents a Vulkan descriptor binding. */
class MVKDescriptorBinding : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

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
						   size_t stride,
						   const void* pData);

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
						  VkDescriptorType& descType,
						  VkDescriptorImageInfo* pImageInfo,
						  VkDescriptorBufferInfo* pBufferInfo,
						  VkBufferView* pTexelBufferView);

    /** Returns whether this instance represents the specified Vulkan binding point. */
    bool hasBinding(uint32_t binding);

	/** Constructs an instance. */
	MVKDescriptorBinding(MVKDescriptorSet* pDescSet, MVKDescriptorSetLayoutBinding* pBindingLayout);

	/** Destructor. */
	~MVKDescriptorBinding();

protected:
	friend class MVKDescriptorSetLayoutBinding;

	void initMTLSamplers(MVKDescriptorSetLayoutBinding* pBindingLayout);

	MVKDescriptorSet* _pDescSet;
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
class MVKDescriptorSet : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_SET; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_SET_EXT; }

	/** Updates the resource bindings in this instance from the specified content. */
	template<typename DescriptorAction>
	void writeDescriptorSets(const DescriptorAction* pDescriptorAction,
							 size_t stride,
							 const void* pData);

	/** 
	 * Reads the resource bindings defined in the specified content 
	 * from this instance into the specified collection of bindings.
	 */
	void readDescriptorSets(const VkCopyDescriptorSet* pDescriptorCopies,
							VkDescriptorType& descType,
							VkDescriptorImageInfo* pImageInfo,
							VkDescriptorBufferInfo* pBufferInfo,
							VkBufferView* pTexelBufferView);

	/**
	 * Instances of this class can participate in a linked list or pool. When so participating,
	 * this is a reference to the next instance in the list or pool. This value should only be
	 * managed and set by the list or pool.
	 */
	MVKDescriptorSet* _next;

	MVKDescriptorSet(MVKDevice* device) : MVKVulkanAPIDeviceObject(device) {}

protected:
	friend class MVKDescriptorSetLayout;
	friend class MVKDescriptorPool;

	void propogateDebugName() override {}
	void setLayout(MVKDescriptorSetLayout* layout);
    MVKDescriptorBinding* getBinding(uint32_t binding);

	MVKDescriptorSetLayout* _pLayout = nullptr;
	std::vector<MVKDescriptorBinding> _bindings;
};


#pragma mark -
#pragma mark MVKDescriptorPool

typedef MVKDeviceObjectPool<MVKDescriptorSet> MVKDescriptorSetPool;

/** Represents a Vulkan descriptor pool. */
class MVKDescriptorPool : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_POOL; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_POOL_EXT; }

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
	void propogateDebugName() override {}
	MVKDescriptorSetPool* getDescriptorSetPool(MVKDescriptorSetLayout* mvkDescSetLayout);

	uint32_t _maxSets;
	std::unordered_set<MVKDescriptorSet*> _allocatedSets;
	std::unordered_map<MVKDescriptorSetLayout*, MVKDescriptorSetPool*> _descriptorSetPools;
};


#pragma mark -
#pragma mark MVKDescriptorUpdateTemplate

/** Represents a Vulkan descriptor update template. */
class MVKDescriptorUpdateTemplate : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_UPDATE_TEMPLATE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_UPDATE_TEMPLATE_EXT; }

	/** Get the nth update template entry. */
	const VkDescriptorUpdateTemplateEntryKHR* getEntry(uint32_t n) const;

	/** Get the total number of entries. */
	uint32_t getNumberOfEntries() const;

	/** Get the type of this template. */
	VkDescriptorUpdateTemplateTypeKHR getType() const;

	/** Constructs an instance for the specified device. */
	MVKDescriptorUpdateTemplate(MVKDevice* device, const VkDescriptorUpdateTemplateCreateInfoKHR* pCreateInfo);

	/** Destructor. */
	~MVKDescriptorUpdateTemplate() override = default;

protected:
	void propogateDebugName() override {}

	VkDescriptorUpdateTemplateTypeKHR _type;
	std::vector<VkDescriptorUpdateTemplateEntryKHR> _entries;
};

#pragma mark -
#pragma mark Support functions

/** Updates the resource bindings in the descriptor sets inditified in the specified content. */
void mvkUpdateDescriptorSets(uint32_t writeCount,
							const VkWriteDescriptorSet* pDescriptorWrites,
							uint32_t copyCount,
							const VkCopyDescriptorSet* pDescriptorCopies);

/** Updates the resource bindings in the given descriptor set from the specified template. */
void mvkUpdateDescriptorSetWithTemplate(VkDescriptorSet descriptorSet,
										VkDescriptorUpdateTemplateKHR updateTemplate,
										const void* pData);

/**
 * If the shader stage binding has a binding defined for the specified stage, populates
 * the context at the descriptor set binding from the shader stage resource binding.
 */
void mvkPopulateShaderConverterContext(SPIRVToMSLConverterContext& context,
									   MVKShaderStageResourceBinding& ssRB,
									   spv::ExecutionModel stage,
									   uint32_t descriptorSetIndex,
									   uint32_t bindingIndex);




