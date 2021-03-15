/*
 * MVKDescriptorSet.mm
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

#include "MVKDescriptorSet.h"
#include "MVKInstance.h"
#include "MVKOSExtensions.h"


#pragma mark -
#pragma mark MVKDescriptorSetLayout

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayout::bindDescriptorSet(MVKCommandEncoder* cmdEncoder,
											   MVKDescriptorSet* descSet,
											   MVKShaderResourceBinding& dslMTLRezIdxOffsets,
											   MVKArrayRef<uint32_t> dynamicOffsets,
											   uint32_t& dynamicOffsetIndex) {
	if (!cmdEncoder) { clearConfigurationResult(); }
	if ( !_isPushDescriptorLayout ) {
		for (auto& dslBind : _bindings) {
			dslBind.bind(cmdEncoder, descSet, dslMTLRezIdxOffsets, dynamicOffsets, dynamicOffsetIndex);
		}
	}
}

static const void* getWriteParameters(VkDescriptorType type, const VkDescriptorImageInfo* pImageInfo,
                                      const VkDescriptorBufferInfo* pBufferInfo, const VkBufferView* pTexelBufferView,
                                      const VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock,
                                      size_t& stride) {
    const void* pData;
    switch (type) {
    case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
    case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
    case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
    case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
        pData = pBufferInfo;
        stride = sizeof(VkDescriptorBufferInfo);
        break;

    case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
    case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
    case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
    case VK_DESCRIPTOR_TYPE_SAMPLER:
    case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
        pData = pImageInfo;
        stride = sizeof(VkDescriptorImageInfo);
        break;

    case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
    case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
        pData = pTexelBufferView;
        stride = sizeof(MVKBufferView*);
        break;

    case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
        pData = pInlineUniformBlock;
        stride = sizeof(VkWriteDescriptorSetInlineUniformBlockEXT);
        break;

    default:
        pData = nullptr;
        stride = 0;
    }
    return pData;
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                               MVKArrayRef<VkWriteDescriptorSet>& descriptorWrites,
                                               MVKShaderResourceBinding& dslMTLRezIdxOffsets) {

    if (!_isPushDescriptorLayout) return;

	if (!cmdEncoder) { clearConfigurationResult(); }
    for (const VkWriteDescriptorSet& descWrite : descriptorWrites) {
        uint32_t dstBinding = descWrite.dstBinding;
        uint32_t dstArrayElement = descWrite.dstArrayElement;
        uint32_t descriptorCount = descWrite.descriptorCount;
        const VkDescriptorImageInfo* pImageInfo = descWrite.pImageInfo;
        const VkDescriptorBufferInfo* pBufferInfo = descWrite.pBufferInfo;
        const VkBufferView* pTexelBufferView = descWrite.pTexelBufferView;
        const VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock = nullptr;
        if (_device->_enabledExtensions.vk_EXT_inline_uniform_block.enabled) {
			for (const auto* next = (VkBaseInStructure*)descWrite.pNext; next; next = next->pNext) {
                switch (next->sType) {
                case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK_EXT: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlockEXT*)next;
                    break;
                }
                default:
                    break;
                }
            }
        }
        if (!_bindingToIndex.count(dstBinding)) continue;
        // Note: This will result in us walking off the end of the array
        // in case there are too many updates... but that's ill-defined anyway.
        for (; descriptorCount; dstBinding++) {
            if (!_bindingToIndex.count(dstBinding)) continue;
            size_t stride;
            const void* pData = getWriteParameters(descWrite.descriptorType, pImageInfo,
                                                   pBufferInfo, pTexelBufferView, pInlineUniformBlock, stride);
            uint32_t descriptorsPushed = 0;
            uint32_t bindIdx = _bindingToIndex[dstBinding];
            _bindings[bindIdx].push(cmdEncoder, dstArrayElement, descriptorCount,
                                    descriptorsPushed, descWrite.descriptorType,
                                    stride, pData, dslMTLRezIdxOffsets);
            pBufferInfo += descriptorsPushed;
            pImageInfo += descriptorsPushed;
            pTexelBufferView += descriptorsPushed;
        }
    }
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                               MVKDescriptorUpdateTemplate* descUpdateTemplate,
                                               const void* pData,
                                               MVKShaderResourceBinding& dslMTLRezIdxOffsets) {

    if (!_isPushDescriptorLayout ||
        descUpdateTemplate->getType() != VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR)
        return;

	if (!cmdEncoder) { clearConfigurationResult(); }
    for (uint32_t i = 0; i < descUpdateTemplate->getNumberOfEntries(); i++) {
        const VkDescriptorUpdateTemplateEntryKHR* pEntry = descUpdateTemplate->getEntry(i);
        uint32_t dstBinding = pEntry->dstBinding;
        uint32_t dstArrayElement = pEntry->dstArrayElement;
        uint32_t descriptorCount = pEntry->descriptorCount;
        const void* pCurData = (const char*)pData + pEntry->offset;
        if (!_bindingToIndex.count(dstBinding)) continue;
        // Note: This will result in us walking off the end of the array
        // in case there are too many updates... but that's ill-defined anyway.
        for (; descriptorCount; dstBinding++) {
            if (!_bindingToIndex.count(dstBinding)) continue;
            uint32_t descriptorsPushed = 0;
            uint32_t bindIdx = _bindingToIndex[dstBinding];
            _bindings[bindIdx].push(cmdEncoder, dstArrayElement, descriptorCount,
                                    descriptorsPushed, pEntry->descriptorType,
                                    pEntry->stride, pCurData, dslMTLRezIdxOffsets);
            pCurData = (const char*)pCurData + pEntry->stride * descriptorsPushed;
        }
    }
}

void MVKDescriptorSetLayout::populateShaderConverterContext(mvk::SPIRVToMSLConversionConfiguration& context,
                                                            MVKShaderResourceBinding& dslMTLRezIdxOffsets,
															uint32_t dslIndex) {
	uint32_t bindCnt = (uint32_t)_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		_bindings[bindIdx].populateShaderConverterContext(context, dslMTLRezIdxOffsets, dslIndex);
	}
}

MVKDescriptorSetLayout::MVKDescriptorSetLayout(MVKDevice* device,
                                               const VkDescriptorSetLayoutCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {

	uint32_t bindCnt = pCreateInfo->bindingCount;
	const auto* pBindingFlags = getBindingFlags(pCreateInfo);

	// The bindings in VkDescriptorSetLayoutCreateInfo do not need to provided in order of binding number.
	// However, several subsequent operations, such as the dynamic offsets in vkCmdBindDescriptorSets()
	// are ordered by binding number. To prepare for this, sort the bindings by binding number.
	struct BindInfo {
		const VkDescriptorSetLayoutBinding* pBinding;
		VkDescriptorBindingFlags bindingFlags;
	};
	MVKSmallVector<BindInfo, 64> sortedBindings;
	sortedBindings.reserve(bindCnt);
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		sortedBindings.push_back( { &pCreateInfo->pBindings[bindIdx], pBindingFlags ? pBindingFlags[bindIdx] : 0 } );
	}
	std::sort(sortedBindings.begin(), sortedBindings.end(), [](BindInfo bindInfo1, BindInfo bindInfo2) {
		return bindInfo1.pBinding->binding < bindInfo2.pBinding->binding;
	});

	_isPushDescriptorLayout = (pCreateInfo->flags & VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR) != 0;
	_descriptorCount = 0;
    _bindings.reserve(bindCnt);
    for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		BindInfo& bindInfo = sortedBindings[bindIdx];
        _bindings.emplace_back(_device, this, bindInfo.pBinding, bindInfo.bindingFlags);
		_bindingToIndex[bindInfo.pBinding->binding] = bindIdx;
		_bindingToDescriptorIndex[bindInfo.pBinding->binding] = _descriptorCount;
		_descriptorCount += _bindings.back().getDescriptorCount(nullptr);
	}
}

// Find and return an array of binding flags from the pNext chain of pCreateInfo,
// or return nullptr if the chain does not include binding flags.
const VkDescriptorBindingFlags* MVKDescriptorSetLayout::getBindingFlags(const VkDescriptorSetLayoutCreateInfo* pCreateInfo) {
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO_EXT: {
				auto* pDescSetLayoutBindingFlags = (VkDescriptorSetLayoutBindingFlagsCreateInfoEXT*)next;
				return pDescSetLayoutBindingFlags->bindingCount ? pDescSetLayoutBindingFlags->pBindingFlags : nullptr;
			}
			default:
				break;
		}
	}
	return nullptr;
}


#pragma mark -
#pragma mark MVKDescriptorSet

VkDescriptorType MVKDescriptorSet::getDescriptorType(uint32_t binding) {
	return _layout->getBinding(binding)->getDescriptorType();
}

MVKDescriptor* MVKDescriptorSet::getDescriptor(uint32_t binding, uint32_t elementIndex) {
	return _descriptors[_layout->getDescriptorIndex(binding, elementIndex)];
}

template<typename DescriptorAction>
void MVKDescriptorSet::write(const DescriptorAction* pDescriptorAction,
							 size_t stride,
							 const void* pData) {

	MVKDescriptorSetLayoutBinding* mvkDSLBind = _layout->getBinding(pDescriptorAction->dstBinding);
	VkDescriptorType descType = mvkDSLBind->getDescriptorType();
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		// For inline buffers dstArrayElement is a byte offset
		MVKDescriptor* mvkDesc = getDescriptor(pDescriptorAction->dstBinding);
		if (mvkDesc->getDescriptorType() == descType) {
			mvkDesc->write(mvkDSLBind, this, pDescriptorAction->dstArrayElement, stride, pData);
		}
    } else {
        uint32_t dstStartIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding, pDescriptorAction->dstArrayElement);
		uint32_t descCnt = pDescriptorAction->descriptorCount;
        for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
			MVKDescriptor* mvkDesc = _descriptors[dstStartIdx + descIdx];
			if (mvkDesc->getDescriptorType() == descType) {
				mvkDesc->write(mvkDSLBind, this, descIdx, stride, pData);
			}
        }
    }
}

void MVKDescriptorSet::read(const VkCopyDescriptorSet* pDescriptorCopy,
							VkDescriptorImageInfo* pImageInfo,
							VkDescriptorBufferInfo* pBufferInfo,
							VkBufferView* pTexelBufferView,
							VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {

	MVKDescriptorSetLayoutBinding* mvkDSLBind = _layout->getBinding(pDescriptorCopy->srcBinding);
	VkDescriptorType descType = mvkDSLBind->getDescriptorType();
	uint32_t descCnt = pDescriptorCopy->descriptorCount;
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		// For inline buffers srcArrayElement is a byte offset
		MVKDescriptor* mvkDesc = getDescriptor(pDescriptorCopy->srcBinding);
		if (mvkDesc->getDescriptorType() == descType) {
			mvkDesc->read(mvkDSLBind, this, pDescriptorCopy->srcArrayElement, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
		}
    } else {
        uint32_t srcStartIdx = _layout->getDescriptorIndex(pDescriptorCopy->srcBinding, pDescriptorCopy->srcArrayElement);
        for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
			MVKDescriptor* mvkDesc = _descriptors[srcStartIdx + descIdx];
			if (mvkDesc->getDescriptorType() == descType) {
				mvkDesc->read(mvkDSLBind, this, descIdx, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
			}
        }
    }
}

VkResult MVKDescriptorSet::allocate(MVKDescriptorSetLayout* layout, uint32_t variableDescriptorCount) {
	_layout = layout;
	_variableDescriptorCount = variableDescriptorCount;

	_descriptors.reserve(layout->getDescriptorCount());
	uint32_t bindCnt = (uint32_t)layout->_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		MVKDescriptorSetLayoutBinding* mvkDSLBind = &layout->_bindings[bindIdx];
		uint32_t descCnt = mvkDSLBind->getDescriptorCount(this);
		for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
			MVKDescriptor* mvkDesc = nullptr;
			setConfigurationResult(_pool->allocateDescriptor(mvkDSLBind->getDescriptorType(), &mvkDesc));
			if ( !wasConfigurationSuccessful() ) { return getConfigurationResult(); }
			_descriptors.push_back(mvkDesc);
		}
	}
	return getConfigurationResult();
}

void MVKDescriptorSet::free(bool isPoolReset) {
	_layout = nullptr;
	_variableDescriptorCount = 0;

	for (auto mvkDesc : _descriptors) { _pool->freeDescriptor(mvkDesc); }
	_descriptors.clear();

	clearConfigurationResult();
}

MVKDescriptorSet::MVKDescriptorSet(MVKDescriptorPool* pool) : MVKVulkanAPIDeviceObject(pool->_device), _pool(pool) {
	free(true);
}


#pragma mark -
#pragma mark MVKDescriptorTypePreallocation

// If preallocated, find the next availalble descriptor.
// If not preallocated, create one on the fly.
template<class DescriptorClass>
VkResult MVKDescriptorTypePreallocation<DescriptorClass>::allocateDescriptor(MVKDescriptor** pMVKDesc) {
	DescriptorClass* mvkDesc;
	if (isPreallocated()) {
		size_t availDescIdx = _availability.getIndexOfFirstSetBit(true);
		if (availDescIdx >= _availability.size()) { return VK_ERROR_OUT_OF_POOL_MEMORY; }
		mvkDesc = &_descriptors[availDescIdx];
		mvkDesc->reset();		// Clear before reusing.
	} else {
		mvkDesc = new DescriptorClass();
	}
	*pMVKDesc = mvkDesc;
	return VK_SUCCESS;
}

// If preallocated, descriptors are held in contiguous memory, so the index of the returning
// descriptor can be calculated by pointer differences, and it can be marked as available.
// The descriptor will be reset when it is re-allocated. This streamlines the reset() of this pool.
// If not preallocated, simply destroy returning descriptor.
template<typename DescriptorClass>
void MVKDescriptorTypePreallocation<DescriptorClass>::freeDescriptor(MVKDescriptor* mvkDesc) {
	if (isPreallocated()) {
		size_t descIdx = (DescriptorClass*)mvkDesc - _descriptors.data();
		_availability.setBit(descIdx);
	} else {
		mvkDesc->destroy();
	}
}

// Preallocated descriptors will be reset when they are reused
template<typename DescriptorClass>
void MVKDescriptorTypePreallocation<DescriptorClass>::reset() {
	_availability.setAllBits();
}

template<typename DescriptorClass>
MVKDescriptorTypePreallocation<DescriptorClass>::MVKDescriptorTypePreallocation(size_t poolSize) :
	_descriptors(poolSize),
	_availability(poolSize, true) {}


#pragma mark -
#pragma mark MVKDescriptorPool

VkResult MVKDescriptorPool::allocateDescriptorSets(const VkDescriptorSetAllocateInfo* pAllocateInfo,
												   VkDescriptorSet* pDescriptorSets) {
	VkResult rslt = VK_SUCCESS;
	const auto* pVarDescCounts = getVariableDecriptorCounts(pAllocateInfo);
	for (uint32_t dsIdx = 0; dsIdx < pAllocateInfo->descriptorSetCount; dsIdx++) {
		MVKDescriptorSetLayout* mvkDSL = (MVKDescriptorSetLayout*)pAllocateInfo->pSetLayouts[dsIdx];
		if ( !mvkDSL->isPushDescriptorLayout() ) {
			rslt = allocateDescriptorSet(mvkDSL, (pVarDescCounts ? pVarDescCounts[dsIdx] : 0), &pDescriptorSets[dsIdx]);
			if (rslt) { break; }
		}
	}
	return rslt;
}

// Find and return an array of variable descriptor counts from the pNext chain of pCreateInfo,
// or return nullptr if the chain does not include variable descriptor counts.
const uint32_t* MVKDescriptorPool::getVariableDecriptorCounts(const VkDescriptorSetAllocateInfo* pAllocateInfo) {
	for (const auto* next = (VkBaseInStructure*)pAllocateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO_EXT: {
				auto* pVarDescSetVarCounts = (VkDescriptorSetVariableDescriptorCountAllocateInfoEXT*)next;
				return pVarDescSetVarCounts->descriptorSetCount ? pVarDescSetVarCounts->pDescriptorCounts : nullptr;
			}
			default:
				break;
		}
	}
	return nullptr;
}

// Retieves the first available descriptor set from the pool, and configures it.
// If none are available, returns an error.
VkResult MVKDescriptorPool::allocateDescriptorSet(MVKDescriptorSetLayout* mvkDSL,
												  uint32_t variableDescriptorCount,
												  VkDescriptorSet* pVKDS) {

	size_t dsIdx = _descriptorSetAvailablility.getIndexOfFirstSetBit(true);
	if (dsIdx >= _descriptorSets.size()) { return VK_ERROR_OUT_OF_POOL_MEMORY; }

	MVKDescriptorSet* mvkDS = &_descriptorSets[dsIdx];
	mvkDS->allocate(mvkDSL, variableDescriptorCount);
	if (mvkDS->wasConfigurationSuccessful()) {
		*pVKDS = (VkDescriptorSet)mvkDS;
	} else {
		freeDescriptorSet(mvkDS, false);
	}
	return mvkDS->getConfigurationResult();
}

VkResult MVKDescriptorPool::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		freeDescriptorSet((MVKDescriptorSet*)pDescriptorSets[dsIdx], false);
	}
	return VK_SUCCESS;
}

// Descriptor sets are held in contiguous memory, so the index of the returning descriptor
// set can be calculated by pointer differences, and it can be marked as available.
void MVKDescriptorPool::freeDescriptorSet(MVKDescriptorSet* mvkDS, bool isPoolReset) {
	if ( !mvkDS ) { return; }	// Vulkan allows NULL refs.

	if (mvkDS->_pool == this) {
		mvkDS->free(isPoolReset);
		size_t dsIdx = mvkDS - _descriptorSets.data();
		_descriptorSetAvailablility.setBit(dsIdx);
	} else {
		reportError(VK_ERROR_INITIALIZATION_FAILED, "A descriptor set is being returned to a descriptor pool that did not allocate it.");
	}
}

// Free all descriptor sets and reset descriptor pools
VkResult MVKDescriptorPool::reset(VkDescriptorPoolResetFlags flags) {
	for (auto& mvkDS : _descriptorSets) { freeDescriptorSet(&mvkDS, true); }

	_uniformBufferDescriptors.reset();
	_storageBufferDescriptors.reset();
	_uniformBufferDynamicDescriptors.reset();
	_storageBufferDynamicDescriptors.reset();
	_inlineUniformBlockDescriptors.reset();
	_sampledImageDescriptors.reset();
	_storageImageDescriptors.reset();
	_inputAttachmentDescriptors.reset();
	_samplerDescriptors.reset();
	_combinedImageSamplerDescriptors.reset();
	_uniformTexelBufferDescriptors.reset();
	_storageTexelBufferDescriptors.reset();

	return VK_SUCCESS;
}

// Allocate a descriptor of the specified type
VkResult MVKDescriptorPool::allocateDescriptor(VkDescriptorType descriptorType,
											   MVKDescriptor** pMVKDesc) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			return _uniformBufferDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			return _storageBufferDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			return _uniformBufferDynamicDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return _storageBufferDynamicDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			return _inlineUniformBlockDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			return _sampledImageDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			return _storageImageDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return _inputAttachmentDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			return _samplerDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return _combinedImageSamplerDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			return _uniformTexelBufferDescriptors.allocateDescriptor(pMVKDesc);

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			return _storageTexelBufferDescriptors.allocateDescriptor(pMVKDesc);

		default:
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "Unrecognized VkDescriptorType %d.", descriptorType);
	}
}

void MVKDescriptorPool::freeDescriptor(MVKDescriptor* mvkDesc) {
	VkDescriptorType descriptorType = mvkDesc->getDescriptorType();
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			return _uniformBufferDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			return _storageBufferDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			return _uniformBufferDynamicDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return _storageBufferDynamicDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			return _inlineUniformBlockDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			return _sampledImageDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			return _storageImageDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return _inputAttachmentDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			return _samplerDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return _combinedImageSamplerDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			return _uniformTexelBufferDescriptors.freeDescriptor(mvkDesc);

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			return _storageTexelBufferDescriptors.freeDescriptor(mvkDesc);

		default:
			reportError(VK_ERROR_INITIALIZATION_FAILED, "Unrecognized VkDescriptorType %d.", descriptorType);
	}
}

// Return the size of the preallocated pool for descriptors of the specified type,
// or zero if we are not preallocating descriptors in the pool.
// There may be more than one poolSizeCount instance for the desired VkDescriptorType.
// Accumulate the descriptor count for the desired VkDescriptorType accordingly.
static size_t getPoolSize(const VkDescriptorPoolCreateInfo* pCreateInfo, VkDescriptorType descriptorType) {
	uint32_t descCnt = 0;
	if (mvkGetMVKConfiguration()->preallocateDescriptors) {
		uint32_t poolCnt = pCreateInfo->poolSizeCount;
		for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
			auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
			if (poolSize.type == descriptorType) { descCnt += poolSize.descriptorCount; }
		}
	}
	return descCnt;
}

MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device),
	_descriptorSets(pCreateInfo->maxSets, MVKDescriptorSet(this)),
	_descriptorSetAvailablility(pCreateInfo->maxSets, true),
	_uniformBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER)),
	_storageBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER)),
	_uniformBufferDynamicDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC)),
	_storageBufferDynamicDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC)),
	_inlineUniformBlockDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT)),
	_sampledImageDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE)),
	_storageImageDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE)),
	_inputAttachmentDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT)),
	_samplerDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLER)),
	_combinedImageSamplerDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER)),
	_uniformTexelBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER)),
	_storageTexelBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER)) {}

MVKDescriptorPool::~MVKDescriptorPool() {
	reset(0);
}


#pragma mark -
#pragma mark MVKDescriptorUpdateTemplate

const VkDescriptorUpdateTemplateEntryKHR* MVKDescriptorUpdateTemplate::getEntry(uint32_t n) const {
	return &_entries[n];
}

uint32_t MVKDescriptorUpdateTemplate::getNumberOfEntries() const {
	return (uint32_t)_entries.size();
}

VkDescriptorUpdateTemplateTypeKHR MVKDescriptorUpdateTemplate::getType() const {
	return _type;
}

MVKDescriptorUpdateTemplate::MVKDescriptorUpdateTemplate(MVKDevice* device,
														 const VkDescriptorUpdateTemplateCreateInfoKHR* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device), _type(pCreateInfo->templateType) {

	for (uint32_t i = 0; i < pCreateInfo->descriptorUpdateEntryCount; i++)
		_entries.push_back(pCreateInfo->pDescriptorUpdateEntries[i]);
}


#pragma mark -
#pragma mark Support functions

// Updates the resource bindings in the descriptor sets inditified in the specified content.
void mvkUpdateDescriptorSets(uint32_t writeCount,
							 const VkWriteDescriptorSet* pDescriptorWrites,
							 uint32_t copyCount,
							 const VkCopyDescriptorSet* pDescriptorCopies) {

	// Perform the write updates
	for (uint32_t i = 0; i < writeCount; i++) {
		const VkWriteDescriptorSet* pDescWrite = &pDescriptorWrites[i];
		size_t stride;
		MVKDescriptorSet* dstSet = (MVKDescriptorSet*)pDescWrite->dstSet;

		const VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock = nullptr;
		if (dstSet->getDevice()->_enabledExtensions.vk_EXT_inline_uniform_block.enabled) {
			for (const auto* next = (VkBaseInStructure*)pDescWrite->pNext; next; next = next->pNext) {
				switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK_EXT: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlockEXT*)next;
					break;
				}
				default:
					break;
				}
			}
		}

		const void* pData = getWriteParameters(pDescWrite->descriptorType, pDescWrite->pImageInfo,
											   pDescWrite->pBufferInfo, pDescWrite->pTexelBufferView,
											   pInlineUniformBlock, stride);
		dstSet->write(pDescWrite, stride, pData);
	}

	// Perform the copy updates by reading bindings from one set and writing to other set.
	for (uint32_t i = 0; i < copyCount; i++) {
		const VkCopyDescriptorSet* pDescCopy = &pDescriptorCopies[i];

		uint32_t descCnt = pDescCopy->descriptorCount;
		VkDescriptorImageInfo imgInfos[descCnt];
		VkDescriptorBufferInfo buffInfos[descCnt];
		VkBufferView texelBuffInfos[descCnt];

		// For inline block create a temp buffer of descCnt bytes to hold data during copy.
		uint8_t dstBuffer[descCnt];
		VkWriteDescriptorSetInlineUniformBlockEXT inlineUniformBlock;
		inlineUniformBlock.pData = dstBuffer;
		inlineUniformBlock.dataSize = descCnt;

		MVKDescriptorSet* srcSet = (MVKDescriptorSet*)pDescCopy->srcSet;
		srcSet->read(pDescCopy, imgInfos, buffInfos, texelBuffInfos, &inlineUniformBlock);

		MVKDescriptorSet* dstSet = (MVKDescriptorSet*)pDescCopy->dstSet;
		VkDescriptorType descType = dstSet->getDescriptorType(pDescCopy->dstBinding);
		size_t stride;
		const void* pData = getWriteParameters(descType, imgInfos, buffInfos, texelBuffInfos, &inlineUniformBlock, stride);
		dstSet->write(pDescCopy, stride, pData);
	}
}

// Updates the resource bindings in the given descriptor set from the specified template.
void mvkUpdateDescriptorSetWithTemplate(VkDescriptorSet descriptorSet,
										VkDescriptorUpdateTemplateKHR updateTemplate,
										const void* pData) {

	MVKDescriptorSet* dstSet = (MVKDescriptorSet*)descriptorSet;
	MVKDescriptorUpdateTemplate* pTemplate = (MVKDescriptorUpdateTemplate*)updateTemplate;

	if (pTemplate->getType() != VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET_KHR)
		return;

	// Perform the updates
	for (uint32_t i = 0; i < pTemplate->getNumberOfEntries(); i++) {
		const VkDescriptorUpdateTemplateEntryKHR* pEntry = pTemplate->getEntry(i);
		const void* pCurData = (const char*)pData + pEntry->offset;
		dstSet->write(pEntry, pEntry->stride, pCurData);
	}
}

void mvkPopulateShaderConverterContext(mvk::SPIRVToMSLConversionConfiguration& context,
									   MVKShaderStageResourceBinding& ssRB,
									   spv::ExecutionModel stage,
									   uint32_t descriptorSetIndex,
									   uint32_t bindingIndex,
									   uint32_t count,
									   MVKSampler* immutableSampler) {
	mvk::MSLResourceBinding rb;

	auto& rbb = rb.resourceBinding;
	rbb.stage = stage;
	rbb.desc_set = descriptorSetIndex;
	rbb.binding = bindingIndex;
	rbb.count = count;
	rbb.msl_buffer = ssRB.bufferIndex;
	rbb.msl_texture = ssRB.textureIndex;
	rbb.msl_sampler = ssRB.samplerIndex;

	if (immutableSampler) { immutableSampler->getConstexprSampler(rb); }

	context.resourceBindings.push_back(rb);
}
