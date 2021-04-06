/*
 * MVKDescriptorSet.h
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKDescriptor.h"
#include "MVKSmallVector.h"
#include "MVKBitArray.h"
#include <unordered_set>
#include <unordered_map>
#include <vector>

class MVKDescriptorPool;
class MVKPipelineLayout;
class MVKCommandEncoder;


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
						   MVKArrayRef<uint32_t> dynamicOffsets,
						   uint32_t& dynamicOffsetIndex);

	/** Encodes this descriptor set layout and the specified descriptor updates on the specified command encoder immediately. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   MVKArrayRef<VkWriteDescriptorSet>& descriptorWrites,
						   MVKShaderResourceBinding& dslMTLRezIdxOffsets);


	/** Encodes this descriptor set layout and the updates from the given template on the specified command encoder immediately. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   MVKDescriptorUpdateTemplate* descUpdateTemplates,
						   const void* pData,
						   MVKShaderResourceBinding& dslMTLRezIdxOffsets);


	/** Populates the specified shader converter context, at the specified DSL index. */
	void populateShaderConverterContext(mvk::SPIRVToMSLConversionConfiguration& context,
                                        MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                        uint32_t dslIndex);

	/** Returns true if this layout is for push descriptors only. */
	bool isPushDescriptorLayout() const { return _isPushDescriptorLayout; }

	MVKDescriptorSetLayout(MVKDevice* device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo);

protected:

	friend class MVKDescriptorSetLayoutBinding;
	friend class MVKPipelineLayout;
	friend class MVKDescriptorSet;
	friend class MVKDescriptorPool;

	void propagateDebugName() override {}
	inline uint32_t getDescriptorCount() { return _descriptorCount; }
	inline uint32_t getDescriptorIndex(uint32_t binding, uint32_t elementIndex = 0) { return getBinding(binding)->getDescriptorIndex(elementIndex); }
	inline MVKDescriptorSetLayoutBinding* getBinding(uint32_t binding) { return &_bindings[_bindingToIndex[binding]]; }
	const VkDescriptorBindingFlags* getBindingFlags(const VkDescriptorSetLayoutCreateInfo* pCreateInfo);

	MVKSmallVector<MVKDescriptorSetLayoutBinding> _bindings;
	std::unordered_map<uint32_t, uint32_t> _bindingToIndex;
	MVKShaderResourceBinding _mtlResourceCounts;
	uint32_t _descriptorCount;
	bool _isPushDescriptorLayout;
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

	/** Returns the descriptor type for the specified binding number. */
	VkDescriptorType getDescriptorType(uint32_t binding);

	/** Updates the resource bindings in this instance from the specified content. */
	template<typename DescriptorAction>
	void write(const DescriptorAction* pDescriptorAction, size_t stride, const void* pData);

	/** 
	 * Reads the resource bindings defined in the specified content 
	 * from this instance into the specified collection of bindings.
	 */
	void read(const VkCopyDescriptorSet* pDescriptorCopies,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock);

	MVKDescriptorSet(MVKDescriptorPool* pool);

protected:
	friend class MVKDescriptorSetLayoutBinding;
	friend class MVKDescriptorPool;

	void propagateDebugName() override {}
	MVKDescriptor* getDescriptor(uint32_t binding, uint32_t elementIndex = 0);
	VkResult allocate(MVKDescriptorSetLayout* layout, uint32_t variableDescriptorCount);
	void free(bool isPoolReset);

	MVKDescriptorPool* _pool;
	MVKDescriptorSetLayout* _layout;
	MVKSmallVector<MVKDescriptor*> _descriptors;
	uint32_t _variableDescriptorCount;
};


#pragma mark -
#pragma mark MVKDescriptorTypePool

/** Support class for MVKDescriptorPool that holds a pool of instances of a single concrete descriptor class. */
template<class DescriptorClass>
class MVKDescriptorTypePool : public MVKBaseObject {

public:

	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; };

	MVKDescriptorTypePool(size_t poolSize);

protected:
	friend class MVKDescriptorPool;

	VkResult allocateDescriptor(MVKDescriptor** pMVKDesc, MVKDescriptorPool* pool);
	void freeDescriptor(MVKDescriptor* mvkDesc, MVKDescriptorPool* pool);
	void reset();

	MVKSmallVector<DescriptorClass> _descriptors;
	MVKBitArray _availability;
};


#pragma mark -
#pragma mark MVKDescriptorPool

/** Represents a Vulkan descriptor pool. */
class MVKDescriptorPool : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DESCRIPTOR_POOL; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DESCRIPTOR_POOL_EXT; }

	/** Allocates descriptor sets. */
	VkResult allocateDescriptorSets(const VkDescriptorSetAllocateInfo* pAllocateInfo,
									VkDescriptorSet* pDescriptorSets);

	/** Free's up the specified descriptor set. */
	VkResult freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets);

	/** Destroys all currently allocated descriptor sets. */
	VkResult reset(VkDescriptorPoolResetFlags flags);

	MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo, bool poolDescriptors);

	~MVKDescriptorPool() override;

protected:
	friend class MVKDescriptorSet;
	template<class> friend class MVKDescriptorTypePool;

	void propagateDebugName() override {}
	const uint32_t* getVariableDecriptorCounts(const VkDescriptorSetAllocateInfo* pAllocateInfo);
	VkResult allocateDescriptorSet(MVKDescriptorSetLayout* mvkDSL, uint32_t variableDescriptorCount, VkDescriptorSet* pVKDS);
	void freeDescriptorSet(MVKDescriptorSet* mvkDS, bool isPoolReset);
	VkResult allocateDescriptor(VkDescriptorType descriptorType, MVKDescriptor** pMVKDesc);
	void freeDescriptor(MVKDescriptor* mvkDesc);

	MVKSmallVector<MVKDescriptorSet> _descriptorSets;
	MVKBitArray _descriptorSetAvailablility;

	MVKDescriptorTypePool<MVKUniformBufferDescriptor> _uniformBufferDescriptors;
	MVKDescriptorTypePool<MVKStorageBufferDescriptor> _storageBufferDescriptors;
	MVKDescriptorTypePool<MVKUniformBufferDynamicDescriptor> _uniformBufferDynamicDescriptors;
	MVKDescriptorTypePool<MVKStorageBufferDynamicDescriptor> _storageBufferDynamicDescriptors;
	MVKDescriptorTypePool<MVKInlineUniformBlockDescriptor> _inlineUniformBlockDescriptors;
	MVKDescriptorTypePool<MVKSampledImageDescriptor> _sampledImageDescriptors;
	MVKDescriptorTypePool<MVKStorageImageDescriptor> _storageImageDescriptors;
	MVKDescriptorTypePool<MVKInputAttachmentDescriptor> _inputAttachmentDescriptors;
	MVKDescriptorTypePool<MVKSamplerDescriptor> _samplerDescriptors;
	MVKDescriptorTypePool<MVKCombinedImageSamplerDescriptor> _combinedImageSamplerDescriptors;
	MVKDescriptorTypePool<MVKUniformTexelBufferDescriptor> _uniformTexelBufferDescriptors;
	MVKDescriptorTypePool<MVKStorageTexelBufferDescriptor> _storageTexelBufferDescriptors;
	bool _hasPooledDescriptors;
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
	void propagateDebugName() override {}

	VkDescriptorUpdateTemplateTypeKHR _type;
	MVKSmallVector<VkDescriptorUpdateTemplateEntryKHR, 1> _entries;
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
void mvkPopulateShaderConverterContext(mvk::SPIRVToMSLConversionConfiguration& context,
									   MVKShaderStageResourceBinding& ssRB,
									   spv::ExecutionModel stage,
									   uint32_t descriptorSetIndex,
									   uint32_t bindingIndex,
									   uint32_t count,
									   MVKSampler* immutableSampler);
