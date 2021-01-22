/*
 * MVKDescriptor.h
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

#include "MVKImage.h"
#include "MVKSmallVector.h"

class MVKDescriptorSet;
class MVKDescriptorSetLayout;
class MVKCommandEncoder;


#pragma mark MVKShaderStageResourceBinding

/** Indicates the Metal resource indexes used by a single shader stage in a descriptor. */
typedef struct MVKShaderStageResourceBinding {
	uint16_t bufferIndex = 0;
	uint16_t textureIndex = 0;
	uint16_t samplerIndex = 0;

	MVKShaderStageResourceBinding operator+ (const MVKShaderStageResourceBinding& rhs);
	MVKShaderStageResourceBinding& operator+= (const MVKShaderStageResourceBinding& rhs);

} MVKShaderStageResourceBinding;


#pragma mark MVKShaderResourceBinding

/** Indicates the Metal resource indexes used by each shader stage in a descriptor. */
typedef struct MVKShaderResourceBinding {
	MVKShaderStageResourceBinding stages[kMVKShaderStageMax];

	uint16_t getMaxBufferIndex();
	uint16_t getMaxTextureIndex();
	uint16_t getMaxSamplerIndex();

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

	/** Returns whether this binding has a variable descriptor count. */
	inline bool hasVariableDescriptorCount() {
		return mvkIsAnyFlagEnabled(_flags, VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT_EXT);
	}

	/**
	 * Returns the number of descriptors in this layout.
	 *
	 * If this is an inline block data descriptor, always returns 1. If this descriptor
	 * has a variable descriptor count, and descSet is not null, the variable descriptor
	 * count provided to that descriptor set is returned. Otherwise returns the value
	 * defined in VkDescriptorSetLayoutBinding::descriptorCount.
	 */
	uint32_t getDescriptorCount(MVKDescriptorSet* descSet);

	/** Returns the descriptor type of this layout. */
	inline VkDescriptorType getDescriptorType() { return _info.descriptorType; }

	/** Returns the immutable sampler at the index, or nullptr if immutable samplers are not used. */
	MVKSampler* getImmutableSampler(uint32_t index);

	/** Encodes the descriptors in the descriptor set that are specified by this layout, */
	void bind(MVKCommandEncoder* cmdEncoder,
			  MVKDescriptorSet* descSet,
			  MVKShaderResourceBinding& dslMTLRezIdxOffsets,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex);

    /** Encodes this binding layout and the specified descriptor on the specified command encoder immediately. */
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
								  const VkDescriptorSetLayoutBinding* pBinding,
								  VkDescriptorBindingFlagsEXT bindingFlags);

	MVKDescriptorSetLayoutBinding(const MVKDescriptorSetLayoutBinding& binding);

	~MVKDescriptorSetLayoutBinding() override;

protected:
    friend class MVKInlineUniformBlockDescriptor;
	void initMetalResourceIndexOffsets(MVKShaderStageResourceBinding* pBindingIndexes,
									   MVKShaderStageResourceBinding* pDescSetCounts,
									   const VkDescriptorSetLayoutBinding* pBinding);
	bool validate(MVKSampler* mvkSampler);

	MVKDescriptorSetLayout* _layout;
	VkDescriptorSetLayoutBinding _info;
	VkDescriptorBindingFlagsEXT _flags;
	MVKSmallVector<MVKSampler*> _immutableSamplers;
	MVKShaderResourceBinding _mtlResourceIndexOffsets;
	bool _applyToStage[kMVKShaderStageMax];
};


#pragma mark -
#pragma mark MVKDescriptor

/** Represents a Vulkan descriptor. */
class MVKDescriptor : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; };

	virtual VkDescriptorType getDescriptorType() = 0;

	/** Encodes this descriptor (based on its layout binding index) on the the command encoder. */
	virtual void bind(MVKCommandEncoder* cmdEncoder,
					  uint32_t descriptorIndex,
					  bool stages[],
					  MVKShaderResourceBinding& mtlIndexes,
					  MVKArrayRef<uint32_t> dynamicOffsets,
					  uint32_t& dynamicOffsetIndex) = 0;

	/**
	 * Updates the internal binding from the specified content. The format of the content depends
	 * on the descriptor type, and is extracted from pData at the location given by index * stride.
	 * MVKInlineUniformBlockDescriptor uses the index as byte offset to write to.
	 */
	virtual void write(MVKDescriptorSet* mvkDescSet,
					   uint32_t index,
					   size_t stride,
					   const void* pData) = 0;

	/**
	 * Updates the specified content arrays from the internal binding.
	 *
	 * Depending on the descriptor type, the binding content is placed into one of the
	 * specified pImageInfo, pBufferInfo, or pTexelBufferView arrays, and the other
	 * arrays are ignored (and may be a null pointer).
	 *
	 * The index parameter indicates the index of the initial descriptor element
	 * at which to start writing.
	 * MVKInlineUniformBlockDescriptor uses the index as byte offset to read from.
	 */
	virtual void read(MVKDescriptorSet* mvkDescSet,
					  uint32_t index,
					  VkDescriptorImageInfo* pImageInfo,
					  VkDescriptorBufferInfo* pBufferInfo,
					  VkBufferView* pTexelBufferView,
					  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) = 0;

	/** Sets the binding layout. */
	virtual void setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) {}

	/** Resets any internal content. */
	virtual void reset() {}

	~MVKDescriptor() { reset(); }

};


#pragma mark -
#pragma mark MVKBufferDescriptor

/** Represents a Vulkan descriptor tracking a buffer. */
class MVKBufferDescriptor : public MVKDescriptor {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	void reset() override;

	~MVKBufferDescriptor() { reset(); }

protected:
	MVKBuffer* _mvkBuffer = nullptr;
	VkDeviceSize _buffOffset = 0;
	VkDeviceSize _buffRange = 0;
};


#pragma mark -
#pragma mark MVKUniformBufferDescriptor

class MVKUniformBufferDescriptor : public MVKBufferDescriptor {
public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER; }
};


#pragma mark -
#pragma mark MVKUniformBufferDynamicDescriptor

class MVKUniformBufferDynamicDescriptor : public MVKBufferDescriptor {
public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC; }
};


#pragma mark -
#pragma mark MVKStorageBufferDescriptor

class MVKStorageBufferDescriptor : public MVKBufferDescriptor {
public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; }
};


#pragma mark -
#pragma mark MVKStorageBufferDynamicDescriptor

class MVKStorageBufferDynamicDescriptor : public MVKBufferDescriptor {
public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC; }
};


#pragma mark -
#pragma mark MVKInlineUniformBlockDescriptor

/** Represents a Vulkan descriptor tracking an inline block of uniform data. */
class MVKInlineUniformBlockDescriptor : public MVKDescriptor {

public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT; }

	void bind(MVKCommandEncoder* cmdEncoder,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   uint32_t dstOffset, // For inline buffers we are using this parameter as dst offset not as src descIdx
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  uint32_t srcOffset, // For inline buffers we are using this parameter as src offset not as dst descIdx
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;
    
    void setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) override;

	void reset() override;

	~MVKInlineUniformBlockDescriptor() { reset(); }

protected:
	uint8_t* _buffer = nullptr;
    uint32_t _length;
};


#pragma mark -
#pragma mark MVKImageDescriptor

/** Represents a Vulkan descriptor tracking an image. */
class MVKImageDescriptor : public MVKDescriptor {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	void reset() override;

	~MVKImageDescriptor() { reset(); }

protected:
	MVKImageView* _mvkImageView = nullptr;
	VkImageLayout _imageLayout = VK_IMAGE_LAYOUT_UNDEFINED;
};


#pragma mark -
#pragma mark MVKSampledImageDescriptor

class MVKSampledImageDescriptor : public MVKImageDescriptor {
public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE; }
};


#pragma mark -
#pragma mark MVKStorageImageDescriptor

class MVKStorageImageDescriptor : public MVKImageDescriptor {
public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_STORAGE_IMAGE; }
};


#pragma mark -
#pragma mark MVKInputAttachmentDescriptor

class MVKInputAttachmentDescriptor : public MVKImageDescriptor {
public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT; }
};


#pragma mark -
#pragma mark MVKSamplerDescriptorMixin

/**
 * This mixin class adds the ability for a descriptor to track a sampler.
 *
 * As a mixin, this class should only be used as a component of multiple inheritance.
 * Any class that inherits from this class should also inherit from MVKDescriptor.
 * This requirement is to avoid the diamond problem of multiple inheritance.
 */
class MVKSamplerDescriptorMixin {

protected:
	void bind(MVKCommandEncoder* cmdEncoder,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex);

	void write(MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData);

	void read(MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock);

	void setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index);

	void reset();

	~MVKSamplerDescriptorMixin() { reset(); }

	MVKSampler* _mvkSampler = nullptr;
	bool _hasDynamicSampler = true;
};


#pragma mark -
#pragma mark MVKSamplerDescriptor

/** Represents a Vulkan descriptor tracking a sampler. */
class MVKSamplerDescriptor : public MVKDescriptor, public MVKSamplerDescriptorMixin {

public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_SAMPLER; }

	void bind(MVKCommandEncoder* cmdEncoder,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	void setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) override;

	void reset() override;

	~MVKSamplerDescriptor() { reset(); }

};


#pragma mark -
#pragma mark MVKCombinedImageSamplerDescriptor

/** Represents a Vulkan descriptor tracking a combined image and sampler. */
class MVKCombinedImageSamplerDescriptor : public MVKImageDescriptor, public MVKSamplerDescriptorMixin {

public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; }

	void bind(MVKCommandEncoder* cmdEncoder,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	void setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) override;

	void reset() override;

	~MVKCombinedImageSamplerDescriptor() { reset(); }

};


#pragma mark -
#pragma mark MVKTexelBufferDescriptor

/** Represents a Vulkan descriptor tracking a texel buffer. */
class MVKTexelBufferDescriptor : public MVKDescriptor {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  uint32_t descriptorIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void write(MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	void reset() override;

	~MVKTexelBufferDescriptor() { reset(); }

protected:
	MVKBufferView* _mvkBufferView = nullptr;
};


#pragma mark -
#pragma mark MVKUniformTexelBufferDescriptor

class MVKUniformTexelBufferDescriptor : public MVKTexelBufferDescriptor {
public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER; }
};


#pragma mark -
#pragma mark MVKStorageTexelBufferDescriptor

class MVKStorageTexelBufferDescriptor : public MVKTexelBufferDescriptor {
public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER; }
};
