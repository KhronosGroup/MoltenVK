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

	VkDescriptorType descType = getDescriptorType(pDescriptorAction->dstBinding);
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		// For inline buffers dstArrayElement is a byte offset
		MVKDescriptor* mvkDesc = getDescriptor(pDescriptorAction->dstBinding);
		if (mvkDesc->getDescriptorType() == descType) {
			mvkDesc->write(this, pDescriptorAction->dstArrayElement, stride, pData);
		}
    } else {
        uint32_t dstStartIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding, pDescriptorAction->dstArrayElement);
		uint32_t descCnt = pDescriptorAction->descriptorCount;
        for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
			MVKDescriptor* mvkDesc = _descriptors[dstStartIdx + descIdx];
			if (mvkDesc->getDescriptorType() == descType) {
				mvkDesc->write(this, descIdx, stride, pData);
			}
        }
    }
}

void MVKDescriptorSet::read(const VkCopyDescriptorSet* pDescriptorCopy,
							VkDescriptorImageInfo* pImageInfo,
							VkDescriptorBufferInfo* pBufferInfo,
							VkBufferView* pTexelBufferView,
							VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {

	VkDescriptorType descType = getDescriptorType(pDescriptorCopy->srcBinding);
	uint32_t descCnt = pDescriptorCopy->descriptorCount;
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		// For inline buffers srcArrayElement is a byte offset
		MVKDescriptor* mvkDesc = getDescriptor(pDescriptorCopy->srcBinding);
		if (mvkDesc->getDescriptorType() == descType) {
			mvkDesc->read(this, pDescriptorCopy->srcArrayElement, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
		}
    } else {
        uint32_t srcStartIdx = _layout->getDescriptorIndex(pDescriptorCopy->srcBinding, pDescriptorCopy->srcArrayElement);
        for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
			MVKDescriptor* mvkDesc = _descriptors[srcStartIdx + descIdx];
			if (mvkDesc->getDescriptorType() == descType) {
				mvkDesc->read(this, descIdx, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
			}
        }
    }
}

MVKDescriptorSet::MVKDescriptorSet(MVKDescriptorSetLayout* layout,
								   uint32_t variableDescriptorCount,
								   MVKDescriptorPool* pool) :
	MVKVulkanAPIDeviceObject(pool->_device),
	_layout(layout),
	_variableDescriptorCount(variableDescriptorCount),
	_pool(pool) {

	_descriptors.reserve(layout->getDescriptorCount());
	uint32_t bindCnt = (uint32_t)layout->_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		MVKDescriptorSetLayoutBinding* mvkDSLBind = &layout->_bindings[bindIdx];
		uint32_t descCnt = mvkDSLBind->getDescriptorCount(this);
		for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
			MVKDescriptor* mvkDesc = nullptr;
			setConfigurationResult(_pool->allocateDescriptor(mvkDSLBind->getDescriptorType(), &mvkDesc));
			if ( !wasConfigurationSuccessful() ) { break; }

			mvkDesc->setLayout(mvkDSLBind, descIdx);
			_descriptors.push_back(mvkDesc);
		}
		if ( !wasConfigurationSuccessful() ) { break; }
	}
}

MVKDescriptorSet::~MVKDescriptorSet() {
	for (auto mvkDesc : _descriptors) { _pool->freeDescriptor(mvkDesc); }
}


#pragma mark -
#pragma mark MVKDescriptorTypePreallocation

template<class DescriptorClass>
VkResult MVKDescriptorTypePreallocation<DescriptorClass>::allocateDescriptor(MVKDescriptor** pMVKDesc) {

	uint32_t descCnt = (uint32_t)_descriptors.size();

	// Preallocated descriptors that CANNOT be freed.
	// Next available index can only monotonically increase towards the limit.
	if ( !_supportAvailability ) {
		if (_nextAvailableIndex < descCnt) {
			*pMVKDesc = &_descriptors[_nextAvailableIndex++];
			return VK_SUCCESS;
		} else {
			return VK_ERROR_OUT_OF_POOL_MEMORY;
		}
	}

	// Descriptors that CAN be freed.
	// An available index might exist anywhere in the pool of descriptors.
	uint32_t origNextAvailPoolIdx = _nextAvailableIndex;

	// First start looking from most recently found available slot
	if (findDescriptor(descCnt, pMVKDesc)) { return VK_SUCCESS; }

	// Then look from beginning of the collection, in case any previous descriptors were freed
	_nextAvailableIndex = 0;
	if (findDescriptor(origNextAvailPoolIdx, pMVKDesc)) { return VK_SUCCESS; }

	return VK_ERROR_OUT_OF_POOL_MEMORY;
}

// Find a descriptor within a range in a preallocated collection based on availability,
// and return true if found, false if not
template<typename DescriptorClass>
bool MVKDescriptorTypePreallocation<DescriptorClass>::findDescriptor(uint32_t endIndex,
																	 MVKDescriptor** pMVKDesc) {
	while (_nextAvailableIndex < endIndex) {
		if (_availability[_nextAvailableIndex]) {
			_availability[_nextAvailableIndex] = false;
			*pMVKDesc = &_descriptors[_nextAvailableIndex];
			_nextAvailableIndex++;
			return true;
		}
		_nextAvailableIndex++;
	}
	return false;
}

// Reset a descriptor and mark it available, if applicable
template<typename DescriptorClass>
void MVKDescriptorTypePreallocation<DescriptorClass>::freeDescriptor(MVKDescriptor* mvkDesc) {

	mvkDesc->reset();

	if (_supportAvailability) {
		bool found = false;
		size_t descCnt = _descriptors.size();
		for (uint32_t descIdx = 0; !found && descIdx < descCnt; descIdx++) {
			if (&_descriptors[descIdx] == mvkDesc) {
				found = true;
				_availability[descIdx] = true;
			}
		}
	}
}

template<typename DescriptorClass>
void MVKDescriptorTypePreallocation<DescriptorClass>::reset() {
	_nextAvailableIndex = 0;
}

template<typename DescriptorClass>
MVKDescriptorTypePreallocation<DescriptorClass>::MVKDescriptorTypePreallocation(const VkDescriptorPoolCreateInfo* pCreateInfo,
																				VkDescriptorType descriptorType) {
	// There may be more than  one poolSizeCount instance for the desired VkDescriptorType.
	// Accumulate the descriptor count for the desired VkDescriptorType, and size the collections accordingly.
	uint32_t descriptorCount = 0;
	uint32_t poolCnt = pCreateInfo->poolSizeCount;
	for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
		auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
		if (poolSize.type == descriptorType) { descriptorCount += poolSize.descriptorCount; }
	}
	_descriptors.resize(descriptorCount);

	// Determine whether we need to track the availability of previously freed descriptors.
	_supportAvailability = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT);
	if (_supportAvailability) { _availability.resize(descriptorCount, true); }
	_nextAvailableIndex = 0;
}


#pragma mark -
#pragma mark MVKPreallocatedDescriptors

// Allocate a descriptor of the specified type
VkResult MVKPreallocatedDescriptors::allocateDescriptor(VkDescriptorType descriptorType,
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

void MVKPreallocatedDescriptors::freeDescriptor(MVKDescriptor* mvkDesc) {
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

void MVKPreallocatedDescriptors::reset() {
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
}

MVKPreallocatedDescriptors::MVKPreallocatedDescriptors(const VkDescriptorPoolCreateInfo* pCreateInfo) :
	_uniformBufferDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER),
	_storageBufferDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER),
	_uniformBufferDynamicDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC),
	_storageBufferDynamicDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC),
	_inlineUniformBlockDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT),
	_sampledImageDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE),
	_storageImageDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE),
	_inputAttachmentDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT),
	_samplerDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLER),
	_combinedImageSamplerDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER),
	_uniformTexelBufferDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER),
	_storageTexelBufferDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
}


#pragma mark -
#pragma mark MVKDescriptorPool

VkResult MVKDescriptorPool::allocateDescriptorSets(const VkDescriptorSetAllocateInfo* pAllocateInfo,
												   VkDescriptorSet* pDescriptorSets) {
	if (_allocatedSets.size() + pAllocateInfo->descriptorSetCount > _maxSets) {
		if (_device->_enabledExtensions.vk_KHR_maintenance1.enabled ||
			_device->getInstance()->getAPIVersion() >= VK_API_VERSION_1_1) {
			return VK_ERROR_OUT_OF_POOL_MEMORY;		// Failure is an acceptable test...don't log as error.
		} else {
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "The maximum number of descriptor sets that can be allocated by this descriptor pool is %d.", _maxSets);
		}
	}

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

// Ensure descriptor set was actually allocated, then return to pool
VkResult MVKDescriptorPool::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		MVKDescriptorSet* mvkDS = (MVKDescriptorSet*)pDescriptorSets[dsIdx];
		if (_allocatedSets.erase(mvkDS)) {
			freeDescriptorSet(mvkDS);
		}
	}
	return VK_SUCCESS;
}

// Destroy all allocated descriptor sets
VkResult MVKDescriptorPool::reset(VkDescriptorPoolResetFlags flags) {
	for (auto& mvkDS : _allocatedSets) { freeDescriptorSet(mvkDS); }
	_allocatedSets.clear();
	if (_preallocatedDescriptors) { _preallocatedDescriptors->reset(); }
	return VK_SUCCESS;
}

VkResult MVKDescriptorPool::allocateDescriptorSet(MVKDescriptorSetLayout* mvkDSL,
												  uint32_t variableDescriptorCount,
												  VkDescriptorSet* pVKDS) {
	MVKDescriptorSet* mvkDS = new MVKDescriptorSet(mvkDSL, variableDescriptorCount, this);
	VkResult rslt = mvkDS->getConfigurationResult();

	if (mvkDS->wasConfigurationSuccessful()) {
		_allocatedSets.insert(mvkDS);
		*pVKDS = (VkDescriptorSet)mvkDS;
	} else {
		freeDescriptorSet(mvkDS);
	}
	return rslt;
}

void MVKDescriptorPool::freeDescriptorSet(MVKDescriptorSet* mvkDS) { mvkDS->destroy(); }

// Allocate a descriptor of the specified type
VkResult MVKDescriptorPool::allocateDescriptor(VkDescriptorType descriptorType,
											   MVKDescriptor** pMVKDesc) {

	// If descriptors are preallocated allocate from the preallocated pools
	if (_preallocatedDescriptors) {
		return _preallocatedDescriptors->allocateDescriptor(descriptorType, pMVKDesc);
	}

	// Otherwise instantiate one of the appropriate type now
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			*pMVKDesc = new MVKUniformBufferDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			*pMVKDesc = new MVKStorageBufferDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			*pMVKDesc = new MVKUniformBufferDynamicDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			*pMVKDesc = new MVKStorageBufferDynamicDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			*pMVKDesc = new MVKInlineUniformBlockDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			*pMVKDesc = new MVKSampledImageDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			*pMVKDesc = new MVKStorageImageDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			*pMVKDesc = new MVKInputAttachmentDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			*pMVKDesc = new MVKSamplerDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			*pMVKDesc = new MVKCombinedImageSamplerDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			*pMVKDesc = new MVKUniformTexelBufferDescriptor();
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			*pMVKDesc = new MVKStorageTexelBufferDescriptor();
			break;

		default:
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "Unrecognized VkDescriptorType %d.", descriptorType);
	}
	return VK_SUCCESS;
}

// Free a descriptor, either through the preallocated pool, or directly destroy it
void MVKDescriptorPool::freeDescriptor(MVKDescriptor* mvkDesc) {
	if (_preallocatedDescriptors) {
		_preallocatedDescriptors->freeDescriptor(mvkDesc);
	} else {
		mvkDesc->destroy();
	}
}

MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device,
									 const VkDescriptorPoolCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	_maxSets = pCreateInfo->maxSets;
	_preallocatedDescriptors = mvkGetMVKConfiguration()->preallocateDescriptors ? new MVKPreallocatedDescriptors(pCreateInfo) : nullptr;
}

// Destroy all allocated descriptor sets and preallocated descriptors
MVKDescriptorPool::~MVKDescriptorPool() {
	reset(0);
	if (_preallocatedDescriptors) { _preallocatedDescriptors->destroy(); }
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
