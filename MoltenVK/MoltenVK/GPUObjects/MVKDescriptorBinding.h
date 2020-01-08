/*
 * MVKDescriptorBinding.h
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

#include "MVKImage.h"
#include "MVKVector.h"
#include <vector>

class MVKDescriptorBinding;
class MVKDescriptorSet;
class MVKDescriptorSetLayout;
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
	void populateShaderConverterContext(mvk::SPIRVToMSLConversionConfiguration& context,
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

	void initMetalResourceIndexOffsets(MVKShaderStageResourceBinding* pBindingIndexes,
									   MVKShaderStageResourceBinding* pDescSetCounts,
									   const VkDescriptorSetLayoutBinding* pBinding);
	bool validate(MVKSampler* mvkSampler);

	MVKDescriptorSetLayout* _layout;
	VkDescriptorSetLayoutBinding _info;
	std::vector<MVKSampler*> _immutableSamplers;
	MVKShaderResourceBinding _mtlResourceIndexOffsets;
	bool _applyToStage[kMVKShaderStageMax];
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
						  VkBufferView* pTexelBufferView,
						  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock);

    /** Returns whether this instance represents the specified Vulkan binding point. */
    bool hasBinding(uint32_t binding);

	/** Constructs an instance. */
	MVKDescriptorBinding(MVKDescriptorSet* pDescSet, MVKDescriptorSetLayoutBinding* pBindingLayout);

	/** Destructor. */
	~MVKDescriptorBinding();

protected:
	friend class MVKDescriptorSetLayoutBinding;

	void initMTLSamplers(MVKDescriptorSetLayoutBinding* pBindingLayout);
	bool validate(MVKSampler* mvkSampler) { return _pBindingLayout->validate(mvkSampler); }

	MVKDescriptorSet* _pDescSet;
	MVKDescriptorSetLayoutBinding* _pBindingLayout;
	std::vector<VkDescriptorImageInfo> _imageBindings;
	std::vector<VkDescriptorBufferInfo> _bufferBindings;
    std::vector<VkWriteDescriptorSetInlineUniformBlockEXT> _inlineBindings;
	std::vector<VkBufferView> _texelBufferBindings;
	std::vector<id<MTLBuffer>> _mtlBuffers;
	std::vector<NSUInteger> _mtlBufferOffsets;
	std::vector<id<MTLTexture>> _mtlTextures;
	std::vector<id<MTLSamplerState>> _mtlSamplers;
	bool _hasDynamicSamplers;
};
