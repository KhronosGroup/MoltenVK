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

	/** Returns the binding number of this layout. */
	inline uint32_t getBinding() { return _info.binding; }

	/** Returns the number of descriptors in this layout. */
	inline uint32_t getDescriptorCount() { return _info.descriptorCount; }

	/**
	 * Encodes the descriptors in the descriptor set that are specified by this layout,
	 * starting with the descriptor at the index, on the the command encoder.
	 * Returns the number of descriptors that were encoded.
	 */
	uint32_t bind(MVKCommandEncoder* cmdEncoder,
				  MVKDescriptorSet* descSet,
				  uint32_t descStartIndex,
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

	MVKDescriptorSetLayoutBinding(MVKDevice* device,
								  MVKDescriptorSetLayout* layout,
								  const VkDescriptorSetLayoutBinding* pBinding);

	MVKDescriptorSetLayoutBinding(const MVKDescriptorSetLayoutBinding& binding);

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
	 * Updates the internal binding from the specified content. The format of the content depends
	 * on the descriptor type, and is extracted from pData at the location given by srcIndex * stride.
	 */
	void writeBinding(uint32_t srcIndex, size_t stride, const void* pData);

	/**
	 * Updates the specified content arrays from the internal binding.
	 *
	 * Depending on the descriptor type of the descriptor set, the binding content is
	 * placed into one of the specified pImageInfo, pBufferInfo, or pTexelBufferView
	 * arrays, and the other arrays are ignored (and may be a null pointer).
	 *
	 * The dstIndex parameter indicates the index of the initial descriptor element
	 * at which to start writing.
	 */
	void readBinding(uint32_t dstIndex,
					 VkDescriptorType& descType,
					 VkDescriptorImageInfo* pImageInfo,
					 VkDescriptorBufferInfo* pBufferInfo,
					 VkBufferView* pTexelBufferView,
					 VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock);

	MVKDescriptorBinding(MVKDescriptorSet* pDescSet, MVKDescriptorSetLayoutBinding* pBindingLayout, uint32_t index);

	~MVKDescriptorBinding();

protected:
	friend class MVKDescriptorSetLayoutBinding;

	bool validate(MVKSampler* mvkSampler) { return _pBindingLayout->validate(mvkSampler); }

	MVKDescriptorSet* _pDescSet;
	MVKDescriptorSetLayoutBinding* _pBindingLayout;
	VkDescriptorImageInfo _imageBinding = {};
	VkDescriptorBufferInfo _bufferBinding = {};
    VkWriteDescriptorSetInlineUniformBlockEXT _inlineBinding = {};
	VkBufferView _texelBufferBinding = nullptr;
	id<MTLBuffer> _mtlBuffer = nil;
	NSUInteger _mtlBufferOffset = 0;
	id<MTLTexture> _mtlTexture = nil;
	id<MTLSamplerState> _mtlSampler = nil;
	bool _hasDynamicSampler;
};
