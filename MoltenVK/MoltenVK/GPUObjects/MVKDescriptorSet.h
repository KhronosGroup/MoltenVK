/*
 * MVKDescriptorSet.h
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

#pragma once

#include "MVKDescriptor.h"
#include "MVKSmallVector.h"
#include "MVKBitArray.h"
#include <unordered_set>
#include <unordered_map>
#include <vector>
#include <mutex>

class MVKDescriptorPool;
class MVKPipelineLayout;
class MVKCommandEncoder;


#pragma mark -
#pragma mark MVKDescriptorSetLayout

/** Tracks a MTLArgumentEncoder and its offset into a Metal argument buffer. */
typedef struct MVKMTLArgumentEncoder {
	id<MTLArgumentEncoder> mtlArgumentEncoder = nil;
	NSUInteger argumentBufferOffset = 0;
	~MVKMTLArgumentEncoder() { [mtlArgumentEncoder release]; }
} MVKMTLArgumentEncoder;

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
						   uint32_t descSetLayoutIndex,
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
	inline bool isPushDescriptorLayout() const { return _isPushDescriptorLayout; }

	/** Returns whether this layout is using an argument buffer. */
	inline bool isUsingMetalArgumentBuffer() const  { return supportsMetalArgumentBuffers() && !isPushDescriptorLayout(); };

	MVKDescriptorSetLayout(MVKDevice* device, const VkDescriptorSetLayoutCreateInfo* pCreateInfo);

protected:
	friend class MVKPipelineLayout;
	friend class MVKDescriptorPool;
	friend class MVKDescriptorSetLayoutBinding;
	friend class MVKDescriptorSet;

	void propagateDebugName() override {}
	inline uint32_t getDescriptorCount() { return _descriptorCount; }
	inline MVKDescriptorSetLayoutBinding* getBinding(uint32_t binding) { return &_bindings[_bindingToIndex[binding]]; }
	inline uint32_t getDescriptorIndex(uint32_t binding, uint32_t elementIndex = 0) { return getBinding(binding)->getDescriptorIndex(elementIndex); }
	inline NSUInteger getArgumentBufferSize() { return _argumentBufferSize; }
	const VkDescriptorBindingFlags* getBindingFlags(const VkDescriptorSetLayoutCreateInfo* pCreateInfo);
	void bindMetalArgumentBuffer(MVKDescriptorSet* descSet);
	void initMTLArgumentEncoders();

	MVKSmallVector<MVKDescriptorSetLayoutBinding> _bindings;
	std::unordered_map<uint32_t, uint32_t> _bindingToIndex;
	MVKShaderResourceBinding _mtlResourceCounts;
	MVKMTLArgumentEncoder _argumentEncoder[kMVKShaderStageCount];
	NSUInteger _argumentBufferSize;
	std::mutex _argEncodingLock;
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

	/** Returns an MTLBuffer region allocation. */
	const MVKMTLBufferAllocation* acquireMTLBufferRegion(NSUInteger length);

	MVKDescriptorSet(MVKDescriptorPool* pool);

protected:
	friend class MVKDescriptorPool;
	friend class MVKDescriptorSetLayout;
	friend class MVKDescriptorSetLayoutBinding;

	void propagateDebugName() override {}
	MVKDescriptor* getDescriptor(uint32_t binding, uint32_t elementIndex = 0);
	VkResult allocate(MVKDescriptorSetLayout* layout,
					  uint32_t variableDescriptorCount,
					  NSUInteger mtlArgumentBufferOffset);
	void free(bool isPoolReset);
	id<MTLBuffer> getMetalArgumentBuffer();
	inline NSUInteger getMetalArgumentBufferOffset() { return _mtlArgumentBufferOffset; }

	MVKSmallVector<MVKDescriptor*> _descriptors;
	MVKDescriptorSetLayout* _layout;
	MVKDescriptorPool* _pool;
	NSUInteger _mtlArgumentBufferOffset;
	uint32_t _variableDescriptorCount;
};


#pragma mark -
#pragma mark MVKDescriptorTypePreallocation

/** Support class for MVKDescriptorPool that holds preallocated instances of a single concrete descriptor class. */
template<class DescriptorClass>
class MVKDescriptorTypePreallocation : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; };

	MVKDescriptorTypePreallocation(const VkDescriptorPoolCreateInfo* pCreateInfo,
								   VkDescriptorType descriptorType);

protected:
	friend class MVKDescriptorPool;

	VkResult allocateDescriptor(MVKDescriptor** pMVKDesc);
	bool findDescriptor(uint32_t endIndex, MVKDescriptor** pMVKDesc);
	void freeDescriptor(MVKDescriptor* mvkDesc);
	void reset();

	MVKSmallVector<DescriptorClass> _descriptors;
	MVKSmallVector<bool> _availability;
	uint32_t _nextAvailableIndex;
	bool _supportAvailability;
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

	MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo);

	~MVKDescriptorPool() override;

protected:
	friend class MVKDescriptorSet;

	void propagateDebugName() override {}
	VkResult allocateDescriptorSet(MVKDescriptorSetLayout* mvkDSL, uint32_t variableDescriptorCount, VkDescriptorSet* pVKDS);
	const uint32_t* getVariableDecriptorCounts(const VkDescriptorSetAllocateInfo* pAllocateInfo);
	void freeDescriptorSet(MVKDescriptorSet* mvkDS, bool isPoolReset);
	VkResult allocateDescriptor(VkDescriptorType descriptorType, MVKDescriptor** pMVKDesc);
	void freeDescriptor(MVKDescriptor* mvkDesc);
	static NSUInteger getDescriptorByteCountForMetalArgumentBuffer(VkDescriptorType descriptorType);
	static NSUInteger getMaxInlineBlockSize(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo);

	MVKSmallVector<MVKDescriptorSet> _descriptorSets;
	MVKBitArray _descriptorSetAvailablility;
	id<MTLBuffer> _mtlArgumentBuffer;
	NSUInteger _nextMTLArgumentBufferOffset;
	MVKMTLBufferAllocator _inlineBlockMTLBufferAllocator;

	MVKDescriptorTypePreallocation<MVKUniformBufferDescriptor> _uniformBufferDescriptors;
	MVKDescriptorTypePreallocation<MVKStorageBufferDescriptor> _storageBufferDescriptors;
	MVKDescriptorTypePreallocation<MVKUniformBufferDynamicDescriptor> _uniformBufferDynamicDescriptors;
	MVKDescriptorTypePreallocation<MVKStorageBufferDynamicDescriptor> _storageBufferDynamicDescriptors;
	MVKDescriptorTypePreallocation<MVKInlineUniformBlockDescriptor> _inlineUniformBlockDescriptors;
	MVKDescriptorTypePreallocation<MVKSampledImageDescriptor> _sampledImageDescriptors;
	MVKDescriptorTypePreallocation<MVKStorageImageDescriptor> _storageImageDescriptors;
	MVKDescriptorTypePreallocation<MVKInputAttachmentDescriptor> _inputAttachmentDescriptors;
	MVKDescriptorTypePreallocation<MVKSamplerDescriptor> _samplerDescriptors;
	MVKDescriptorTypePreallocation<MVKCombinedImageSamplerDescriptor> _combinedImageSamplerDescriptors;
	MVKDescriptorTypePreallocation<MVKUniformTexelBufferDescriptor> _uniformTexelBufferDescriptors;
	MVKDescriptorTypePreallocation<MVKStorageTexelBufferDescriptor> _storageTexelBufferDescriptors;
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
