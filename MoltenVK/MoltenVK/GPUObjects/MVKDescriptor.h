/*
 * MVKDescriptor.h
 *
 * Copyright (c) 2015-2024 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKMTLBufferAllocation.h"

class MVKDescriptorSet;
class MVKDescriptorSetLayout;
class MVKCommandEncoder;
class MVKResourcesCommandEncoderState;


#pragma mark MVKShaderStageResourceBinding

/** Indicates the Metal resource indexes used by a single shader stage in a descriptor. */
typedef struct MVKShaderStageResourceBinding {
	uint32_t bufferIndex = 0;
	uint32_t textureIndex = 0;
	uint32_t samplerIndex = 0;
	uint32_t resourceIndex = 0;
	uint32_t dynamicOffsetBufferIndex = 0;

	MVKShaderStageResourceBinding operator+ (const MVKShaderStageResourceBinding& rhs);
	MVKShaderStageResourceBinding& operator+= (const MVKShaderStageResourceBinding& rhs);
	void clearArgumentBufferResources();

} MVKShaderStageResourceBinding;


#pragma mark MVKShaderResourceBinding

/** Indicates the Metal resource indexes used by each shader stage in a descriptor. */
typedef struct MVKShaderResourceBinding {
	MVKShaderStageResourceBinding stages[kMVKShaderStageCount];

	uint16_t getMaxResourceIndex();
	uint16_t getMaxBufferIndex();
	uint16_t getMaxTextureIndex();
	uint16_t getMaxSamplerIndex();

	MVKShaderResourceBinding operator+ (const MVKShaderResourceBinding& rhs);
	MVKShaderResourceBinding& operator+= (const MVKShaderResourceBinding& rhs);
	MVKShaderStageResourceBinding& getMetalResourceIndexes(MVKShaderStage stage = kMVKShaderStageVertex) { return stages[stage]; }
	void clearArgumentBufferResources();
	void addArgumentBuffers(uint32_t count);

} MVKShaderResourceBinding;

/**
 * If the shader stage binding has a binding defined for the specified stage, populates
 * the context at the descriptor set binding from the shader stage resource binding.
 */
void mvkPopulateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
									   MVKShaderStageResourceBinding& ssRB,
									   MVKShaderStage stage,
									   uint32_t descriptorSetIndex,
									   uint32_t bindingIndex,
									   uint32_t count,
									   VkDescriptorType descType,
									   MVKSampler* immutableSampler);


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
	inline bool hasVariableDescriptorCount() const {
		return mvkIsAnyFlagEnabled(_flags, VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT);
	}

	/**
	 * Returns the number of descriptors in this layout.
	 *
	 * If this is an inline block data descriptor, always returns 1. If this descriptor
	 * has a variable descriptor count, and descSet is not null, the variable descriptor
	 * count provided to that descriptor set is returned. Otherwise returns the value
	 * defined in VkDescriptorSetLayoutBinding::descriptorCount.
	 */
	uint32_t getDescriptorCount(MVKDescriptorSet* descSet = nullptr) const;

	/** Returns the descriptor type of this layout. */
	inline VkDescriptorType getDescriptorType() { return _info.descriptorType; }

	/** Returns whether this binding uses immutable samplers. */
	bool usesImmutableSamplers() { return !_immutableSamplers.empty(); }

	/** Returns the immutable sampler at the index, or nullptr if immutable samplers are not used. */
	MVKSampler* getImmutableSampler(uint32_t index) {
		return (index < _immutableSamplers.size()) ? _immutableSamplers[index] : nullptr;
	}

	/** Encodes the descriptors in the descriptor set that are specified by this layout, */
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkPipelineBindPoint pipelineBindPoint,
			  MVKDescriptorSet* descSet,
			  MVKShaderResourceBinding& dslMTLRezIdxOffsets,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex);

    /** Encodes this binding layout and the specified descriptor on the specified command encoder immediately. */
    void push(MVKCommandEncoder* cmdEncoder,
              VkPipelineBindPoint pipelineBindPoint,
              uint32_t& dstArrayElement,
              uint32_t& descriptorCount,
              uint32_t& descriptorsPushed,
              VkDescriptorType descriptorType,
              size_t stride,
              const void* pData,
              MVKShaderResourceBinding& dslMTLRezIdxOffsets);

	/** Returns the index of the descriptor within the descriptor set of the element at the index within this descriptor layout. */
	uint32_t getDescriptorIndex(uint32_t elementIndex = 0) const { return _descriptorIndex + elementIndex; }

	/**
	 * Returns the indexes into the resources, relative to the descriptor set.
	 * When using Metal argument buffers, all stages have the same values, and
	 * in that case the stage can be withheld and a default stage will be used.
	 */
	MVKShaderStageResourceBinding& getMetalResourceIndexOffsets(MVKShaderStage stage = kMVKShaderStageVertex) {
		return _mtlResourceIndexOffsets.getMetalResourceIndexes(stage);
	}

	/** Returns a bitwise OR of Metal render stages. */
	MTLRenderStages getMTLRenderStages();

	/** Returns whether this binding should be applied to the shader stage. */
	bool getApplyToStage(MVKShaderStage stage) { return _applyToStage[stage]; }

	MVKDescriptorSetLayoutBinding(MVKDevice* device,
								  MVKDescriptorSetLayout* layout,
								  const VkDescriptorSetLayoutBinding* pBinding,
								  VkDescriptorBindingFlagsEXT bindingFlags,
								  uint32_t descriptorIndex);

	MVKDescriptorSetLayoutBinding(const MVKDescriptorSetLayoutBinding& binding);

	~MVKDescriptorSetLayoutBinding() override;

protected:
	friend class MVKDescriptorSetLayout;
    friend class MVKInlineUniformBlockDescriptor;
	
	void initMetalResourceIndexOffsets(const VkDescriptorSetLayoutBinding* pBinding, uint32_t stage);
	void addMTLArgumentDescriptors(NSMutableArray<MTLArgumentDescriptor*>* args);
	void addMTLArgumentDescriptor(NSMutableArray<MTLArgumentDescriptor*>* args,
								  uint32_t argIndex,
								  MTLDataType dataType,
								  MTLArgumentAccess access);
	bool isUsingMetalArgumentBuffer();
	void populateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
										MVKShaderResourceBinding& dslMTLRezIdxOffsets,
										uint32_t dslIndex);
	bool validate(MVKSampler* mvkSampler);

	MVKDescriptorSetLayout* _layout;
	VkDescriptorSetLayoutBinding _info;
	VkDescriptorBindingFlagsEXT _flags;
	MVKSmallVector<MVKSampler*> _immutableSamplers;
	MVKShaderResourceBinding _mtlResourceIndexOffsets;
	uint32_t _descriptorIndex;
	bool _applyToStage[kMVKShaderStageCount];
};


#pragma mark -
#pragma mark MVKDescriptor

/** Represents a Vulkan descriptor. */
class MVKDescriptor : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; };

	virtual VkDescriptorType getDescriptorType() = 0;

	/** Returns whether this descriptor type uses dynamic buffer offsets. */
	virtual bool usesDynamicBufferOffsets() { return false; }

	/** Encodes this descriptor (based on its layout binding index) on the the command encoder. */
	virtual void bind(MVKCommandEncoder* cmdEncoder,
					  VkPipelineBindPoint pipelineBindPoint,
					  MVKDescriptorSetLayoutBinding* mvkDSLBind,
					  uint32_t elementIndex,
					  bool stages[],
					  MVKShaderResourceBinding& mtlIndexes,
					  MVKArrayRef<uint32_t> dynamicOffsets,
					  uint32_t& dynamicOffsetIndex) = 0;

	/** Encodes this descriptor to the Metal argument buffer. */
	virtual void encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
											 id<MTLArgumentEncoder> mtlArgEncoder,
											 uint32_t descSetIndex,
											 MVKDescriptorSetLayoutBinding* mvkDSLBind,
											 uint32_t elementIndex,
											 MVKShaderStage stage,
											 bool encodeToArgBuffer,
											 bool encodeUsage) = 0;

	/**
	 * Updates the internal binding from the specified content. The format of the content depends
	 * on the descriptor type, and is extracted from pData at the location given by index * stride.
	 * MVKInlineUniformBlockDescriptor uses the index as byte offset to write to.
	 */
	virtual void write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
					   MVKDescriptorSet* mvkDescSet,
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
	virtual void read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
					  MVKDescriptorSet* mvkDescSet,
					  uint32_t index,
					  VkDescriptorImageInfo* pImageInfo,
					  VkDescriptorBufferInfo* pBufferInfo,
					  VkBufferView* pTexelBufferView,
					  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) = 0;

	/** Resets any internal content. */
	virtual void reset() {}

	~MVKDescriptor() { reset(); }

protected:
	MTLResourceUsage getMTLResourceUsage();

};


#pragma mark -
#pragma mark MVKBufferDescriptor

/** Represents a Vulkan descriptor tracking a buffer. */
class MVKBufferDescriptor : public MVKDescriptor {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkPipelineBindPoint pipelineBindPoint,
			  MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  uint32_t elementIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
									 id<MTLArgumentEncoder> mtlArgEncoder,
									 uint32_t descSetIndex,
									 MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t elementIndex,
									 MVKShaderStage stage,
									 bool encodeToArgBuffer,
									 bool encodeUsage) override;

	void write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			   MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  MVKDescriptorSet* mvkDescSet,
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
	bool usesDynamicBufferOffsets() override { return true; }
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
	bool usesDynamicBufferOffsets() override { return true; }
};


#pragma mark -
#pragma mark MVKInlineUniformBlockDescriptor

/** Represents a Vulkan descriptor tracking an inline block of uniform data. */
class MVKInlineUniformBlockDescriptor : public MVKDescriptor {

public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT; }

	void bind(MVKCommandEncoder* cmdEncoder,
			  VkPipelineBindPoint pipelineBindPoint,
			  MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  uint32_t elementIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
									 id<MTLArgumentEncoder> mtlArgEncoder,
									 uint32_t descSetIndex,
									 MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t elementIndex,
									 MVKShaderStage stage,
									 bool encodeToArgBuffer,
									 bool encodeUsage) override;

	void write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			   MVKDescriptorSet* mvkDescSet,
			   uint32_t dstOffset, // For inline buffers we are using this parameter as dst offset not as src descIdx
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  MVKDescriptorSet* mvkDescSet,
			  uint32_t srcOffset, // For inline buffers we are using this parameter as src offset not as dst descIdx
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;
    
	void reset() override;

	~MVKInlineUniformBlockDescriptor() { reset(); }

protected:
	inline uint8_t* getData() { return _mvkMTLBufferAllocation ? (uint8_t*)_mvkMTLBufferAllocation->getContents() : nullptr; }

	MVKMTLBufferAllocation* _mvkMTLBufferAllocation = nullptr;
};


#pragma mark -
#pragma mark MVKImageDescriptor

/** Represents a Vulkan descriptor tracking an image. */
class MVKImageDescriptor : public MVKDescriptor {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkPipelineBindPoint pipelineBindPoint,
			  MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  uint32_t elementIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
									 id<MTLArgumentEncoder> mtlArgEncoder,
									 uint32_t descSetIndex,
									 MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t elementIndex,
									 MVKShaderStage stage,
									 bool encodeToArgBuffer,
									 bool encodeUsage) override;

	void write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			   MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	void reset() override;

	~MVKImageDescriptor() { reset(); }

protected:
	MVKImageView* _mvkImageView = nullptr;
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
			  VkPipelineBindPoint pipelineBindPoint,
			  MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  uint32_t elementIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex);

	void encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
									 id<MTLArgumentEncoder> mtlArgEncoder,
									 uint32_t descSetIndex,
									 MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t elementIndex,
									 MVKShaderStage stage,
									 bool encodeToArgBuffer);

	void write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			   MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData);

	void read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock);

	void reset();

	~MVKSamplerDescriptorMixin() { reset(); }

	MVKSampler* _mvkSampler = nullptr;
};


#pragma mark -
#pragma mark MVKSamplerDescriptor

/** Represents a Vulkan descriptor tracking a sampler. */
class MVKSamplerDescriptor : public MVKDescriptor, public MVKSamplerDescriptorMixin {

public:
	VkDescriptorType getDescriptorType() override { return VK_DESCRIPTOR_TYPE_SAMPLER; }

	void bind(MVKCommandEncoder* cmdEncoder,
			  VkPipelineBindPoint pipelineBindPoint,
			  MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  uint32_t elementIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
									 id<MTLArgumentEncoder> mtlArgEncoder,
									 uint32_t descSetIndex,
									 MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t elementIndex,
									 MVKShaderStage stage,
									 bool encodeToArgBuffer,
									 bool encodeUsage) override;

	void write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			   MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

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
			  VkPipelineBindPoint pipelineBindPoint,
			  MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  uint32_t elementIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
									 id<MTLArgumentEncoder> mtlArgEncoder,
									 uint32_t descSetIndex,
									 MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t elementIndex,
									 MVKShaderStage stage,
									 bool encodeToArgBuffer,
									 bool encodeUsage) override;

	void write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			   MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  MVKDescriptorSet* mvkDescSet,
			  uint32_t dstIndex,
			  VkDescriptorImageInfo* pImageInfo,
			  VkDescriptorBufferInfo* pBufferInfo,
			  VkBufferView* pTexelBufferView,
			  VkWriteDescriptorSetInlineUniformBlockEXT* inlineUniformBlock) override;

	void reset() override;

	~MVKCombinedImageSamplerDescriptor() { reset(); }

};


#pragma mark -
#pragma mark MVKTexelBufferDescriptor

/** Represents a Vulkan descriptor tracking a texel buffer. */
class MVKTexelBufferDescriptor : public MVKDescriptor {

public:
	void bind(MVKCommandEncoder* cmdEncoder,
			  VkPipelineBindPoint pipelineBindPoint,
			  MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  uint32_t elementIndex,
			  bool stages[],
			  MVKShaderResourceBinding& mtlIndexes,
			  MVKArrayRef<uint32_t> dynamicOffsets,
			  uint32_t& dynamicOffsetIndex) override;

	void encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
									 id<MTLArgumentEncoder> mtlArgEncoder,
									 uint32_t descSetIndex,
									 MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t elementIndex,
									 MVKShaderStage stage,
									 bool encodeToArgBuffer,
									 bool encodeUsage) override;

	void write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			   MVKDescriptorSet* mvkDescSet,
			   uint32_t srcIndex,
			   size_t stride,
			   const void* pData) override;

	void read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
			  MVKDescriptorSet* mvkDescSet,
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
