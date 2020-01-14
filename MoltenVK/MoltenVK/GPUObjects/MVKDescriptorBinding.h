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

	/** Returns the descriptor type of this layout. */
	inline VkDescriptorType getDescriptorType() { return _info.descriptorType; }

	/** Returns the immutable sampler at the index, or nullptr if immutable samplers are not used. */
	MVKSampler* getImmutableSampler(uint32_t index);

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
	friend class MVKDescriptorSet;
	friend class MVKDescriptorBinding;

	MVKDescriptorBinding* newDescriptorBinding();
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
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; };

	/** Encodes this descriptor (based on its layout binding index) on the the command encoder. */
	virtual void bind(MVKCommandEncoder* cmdEncoder,
					  VkDescriptorType descriptorType,
					  uint32_t descriptorIndex,
					  bool stages[],
					  MVKShaderResourceBinding& mtlIndexes,
					  MVKVector<uint32_t>& dynamicOffsets,
					  uint32_t* pDynamicOffsetIndex) = 0;

	/**
	 * Updates the internal binding from the specified content. The format of the content depends
	 * on the descriptor type, and is extracted from pData at the location given by srcIndex * stride.
	 */
	virtual void write(MVKDescriptorSet* mvkDescSet,
					   VkDescriptorType descriptorType,
					   uint32_t srcIndex,
					   size_t stride,
					   const void* pData) = 0;

	/**
	 * Updates the specified content arrays from the internal binding.
	 *
	 * Depending on the descriptor type, the binding content is placed into one of the
	 * specified pImageInfo, pBufferInfo, or pTexelBufferView arrays, and the other
	 * arrays are ignored (and may be a null pointer).
	 *
	 * The dstIndex parameter indicates the index of the initial descriptor element
	 * at which to start writing.
	 */
	virtual void read(MVKDescriptorSet* mvkDescSet,
					  VkDescriptorType descriptorType,
					  uint32_t dstIndex,
					  VkDescriptorImageInfo* pImageInfo,
					  VkDescriptorBufferInfo* pBufferInfo,
					  VkBufferView* pTexelBufferView,
					  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) = 0;

	/** Sets the binding layout. */
	virtual void setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) {}

};


#pragma mark -
#pragma mark MVKBufferDescriptorBinding

/** Represents a Vulkan descriptor binding tracking a buffer. */
class MVKBufferDescriptorBinding : public MVKDescriptorBinding {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkDescriptorType descriptorType,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKVector<uint32_t>& dynamicOffsets,
			  uint32_t* pDynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   VkDescriptorType descriptorType,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  VkDescriptorType descriptorType,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	~MVKBufferDescriptorBinding();

protected:
	MVKBuffer* _mvkBuffer = nullptr;
	VkDeviceSize _buffOffset = 0;
	VkDeviceSize _buffRange = 0;
};


#pragma mark -
#pragma mark MVKInlineUniformDescriptorBinding

/** Represents a Vulkan descriptor binding tracking an inline block of uniform data. */
class MVKInlineUniformDescriptorBinding : public MVKDescriptorBinding {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkDescriptorType descriptorType,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKVector<uint32_t>& dynamicOffsets,
			  uint32_t* pDynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   VkDescriptorType descriptorType,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  VkDescriptorType descriptorType,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	~MVKInlineUniformDescriptorBinding();

protected:
	id<MTLBuffer> _mtlBuffer = nil;
	uint32_t _dataSize;
};


#pragma mark -
#pragma mark MVKImageDescriptorBinding

/** Represents a Vulkan descriptor binding tracking an image. */
class MVKImageDescriptorBinding : public MVKDescriptorBinding {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkDescriptorType descriptorType,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKVector<uint32_t>& dynamicOffsets,
			  uint32_t* pDynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   VkDescriptorType descriptorType,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  VkDescriptorType descriptorType,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	~MVKImageDescriptorBinding();

protected:
	MVKImageView* _mvkImageView = nullptr;
	VkImageLayout _imageLayout = VK_IMAGE_LAYOUT_UNDEFINED;
};


#pragma mark -
#pragma mark MVKSamplerDescriptorBindingMixin

/**
 * This mixin class adds the ability for a descriptor binding to track a sampler.
 *
 * As a mixin, this class should only be used as a component of multiple inheritance.
 * Any class that inherits from this class should also inherit from MVKDescriptorBinding.
 * This requirement is to avoid the diamond problem of multiple inheritance.
 */
class MVKSamplerDescriptorBindingMixin {

protected:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkDescriptorType descriptorType,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKVector<uint32_t>& dynamicOffsets,
			  uint32_t* pDynamicOffsetIndex);

	void write(MVKDescriptorSet* mvkDescSet,
			   VkDescriptorType descriptorType,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData);

	void read(MVKDescriptorSet* mvkDescSet,
			  VkDescriptorType descriptorType,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock);

	void setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index);

	virtual ~MVKSamplerDescriptorBindingMixin();

	MVKSampler* _mvkSampler = nullptr;
	bool _hasDynamicSampler = true;
};


#pragma mark -
#pragma mark MVKSamplerDescriptorBinding

/** Represents a Vulkan descriptor binding tracking a sampler. */
class MVKSamplerDescriptorBinding : public MVKDescriptorBinding,
public MVKSamplerDescriptorBindingMixin {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkDescriptorType descriptorType,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKVector<uint32_t>& dynamicOffsets,
			  uint32_t* pDynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   VkDescriptorType descriptorType,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  VkDescriptorType descriptorType,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	void setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) override;

};


#pragma mark -
#pragma mark MVKCombinedImageSamplerDescriptorBinding

/** Represents a Vulkan descriptor binding tracking a combined image and sampler. */
class MVKCombinedImageSamplerDescriptorBinding : public MVKImageDescriptorBinding,
												 public MVKSamplerDescriptorBindingMixin {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkDescriptorType descriptorType,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKVector<uint32_t>& dynamicOffsets,
			  uint32_t* pDynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   VkDescriptorType descriptorType,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  VkDescriptorType descriptorType,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	void setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) override;

};


#pragma mark -
#pragma mark MVKTexelBufferDescriptorBinding

/** Represents a Vulkan descriptor binding tracking a texel buffer. */
class MVKTexelBufferDescriptorBinding : public MVKDescriptorBinding {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkDescriptorType descriptorType,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKVector<uint32_t>& dynamicOffsets,
			  uint32_t* pDynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   VkDescriptorType descriptorType,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  VkDescriptorType descriptorType,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	~MVKTexelBufferDescriptorBinding();

protected:
	MVKBufferView* _mvkBufferView = nullptr;
};
