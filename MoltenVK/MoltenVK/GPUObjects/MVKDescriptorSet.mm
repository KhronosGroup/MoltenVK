/*
 * MVKDescriptorSet.mm
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

#include "MVKDescriptorSet.h"
#include "MVKOSExtensions.h"


#pragma mark -
#pragma mark MVKDescriptorSetLayout

// Look through the layout bindings looking for the binding number, accumulating the number
// of descriptors in each layout binding as we go, then add the element index.
uint32_t MVKDescriptorSetLayout::getDescriptorIndex(uint32_t binding, uint32_t elementIndex) {
	uint32_t descIdx = 0;
	for (auto& dslBind : _bindings) {
		if (dslBind.getBinding() == binding) { break; }
		descIdx += dslBind.getDescriptorCount();
	}
	return descIdx + elementIndex;
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayout::bindDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                               MVKDescriptorSet* descSet,
                                               MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                               MVKArrayRef<uint32_t> dynamicOffsets,
                                               uint32_t baseDynamicOffsetIndex) {
    if (_isPushDescriptorLayout) return;

	clearConfigurationResult();
    size_t bindCnt = _bindings.size();
    for (uint32_t descIdx = 0, bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		descIdx += _bindings[bindIdx].bind(cmdEncoder, descSet, descIdx,
										   dslMTLRezIdxOffsets, dynamicOffsets,
										   baseDynamicOffsetIndex);
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

	clearConfigurationResult();
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

	clearConfigurationResult();
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
    _isPushDescriptorLayout = (pCreateInfo->flags & VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR) != 0;

	// Create the descriptor layout bindings
	_descriptorCount = 0;
    _bindings.reserve(pCreateInfo->bindingCount);
	struct SortInfo
	{
		const VkDescriptorSetLayoutBinding* binding;
		uint32_t index;
	};
	std::vector<SortInfo> dynamicBindings;

    for (uint32_t i = 0; i < pCreateInfo->bindingCount; i++) {
        _bindings.emplace_back(_device, this, &pCreateInfo->pBindings[i]);
		_descriptorCount += _bindings.back().getDescriptorCount();
        _bindingToIndex[pCreateInfo->pBindings[i].binding] = i;
		if (pCreateInfo->pBindings[i].descriptorType == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC ||
			pCreateInfo->pBindings[i].descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC) {
			dynamicBindings.push_back(SortInfo{ &pCreateInfo->pBindings[i], i });
		}
	}

	// Dynamic offsets are ordered by binding index when given to vkCmdBindDescriptorSets
	// not by the order they are provided in the layout.
	// So we want to sort by binding, and then count how many dynamic offsets the binding
	// has so we can assign each binding it's first dynamic offset index
	std::sort(dynamicBindings.begin(), dynamicBindings.end(),
				[](const SortInfo &info1, const SortInfo &info2) {
					return info1.binding->binding < info2.binding->binding; });

	uint32_t curOffsetIndex = 0;
	for (auto &i : dynamicBindings) {
		_bindings[i.index].setDynamicOffsetIndex(curOffsetIndex);
		curOffsetIndex += i.binding->descriptorCount;
	}
	_dynamicDescriptorCount = curOffsetIndex;
}


#pragma mark -
#pragma mark MVKDescriptorSet

VkDescriptorType MVKDescriptorSet::getDescriptorType(uint32_t binding) {
	return _layout->getBinding(binding)->getDescriptorType();
}

template<typename DescriptorAction>
void MVKDescriptorSet::write(const DescriptorAction* pDescriptorAction,
							 size_t stride,
							 const void* pData) {

	VkDescriptorType descType = getDescriptorType(pDescriptorAction->dstBinding);
	uint32_t descCnt = pDescriptorAction->descriptorCount;
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
        uint32_t dstStartIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding, 0);
        // For inline buffers we are using the index argument as dst offset not as src descIdx
        _descriptors[dstStartIdx]->write(this, descType, pDescriptorAction->dstArrayElement, stride, pData);
    } else {
        uint32_t dstStartIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding,
        pDescriptorAction->dstArrayElement);
        for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
            _descriptors[dstStartIdx + descIdx]->write(this, descType, descIdx, stride, pData);
        }
    }
}

// Create concrete implementations of the three variations of the write() function.
template void MVKDescriptorSet::write<VkWriteDescriptorSet>(const VkWriteDescriptorSet* pDescriptorAction,
															size_t stride, const void *pData);
template void MVKDescriptorSet::write<VkCopyDescriptorSet>(const VkCopyDescriptorSet* pDescriptorAction,
														   size_t stride, const void *pData);
template void MVKDescriptorSet::write<VkDescriptorUpdateTemplateEntryKHR>(const VkDescriptorUpdateTemplateEntryKHR* pDescriptorAction,
																		  size_t stride, const void *pData);

void MVKDescriptorSet::read(const VkCopyDescriptorSet* pDescriptorCopy,
							VkDescriptorImageInfo* pImageInfo,
							VkDescriptorBufferInfo* pBufferInfo,
							VkBufferView* pTexelBufferView,
							VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {

	VkDescriptorType descType = getDescriptorType(pDescriptorCopy->srcBinding);
	uint32_t descCnt = pDescriptorCopy->descriptorCount;
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
        pInlineUniformBlock->dataSize = pDescriptorCopy->descriptorCount;
        uint32_t srcStartIdx = _layout->getDescriptorIndex(pDescriptorCopy->srcBinding, 0);
        // For inline buffers we are using the index argument as src offset not as dst descIdx
        _descriptors[srcStartIdx]->read(this, descType, pDescriptorCopy->srcArrayElement, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
    } else {
        uint32_t srcStartIdx = _layout->getDescriptorIndex(pDescriptorCopy->srcBinding,
                                                           pDescriptorCopy->srcArrayElement);
        for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
            _descriptors[srcStartIdx + descIdx]->read(this, descType, descIdx, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
        }
    }
}

// If the descriptor pool fails to allocate a descriptor, record a configuration error
MVKDescriptorSet::MVKDescriptorSet(MVKDescriptorSetLayout* layout, MVKDescriptorPool* pool) :
	MVKVulkanAPIDeviceObject(pool->_device), _layout(layout), _pool(pool) {

	_descriptors.reserve(layout->getDescriptorCount());
	uint32_t bindCnt = (uint32_t)layout->_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		MVKDescriptorSetLayoutBinding* mvkDSLBind = &layout->_bindings[bindIdx];
        MVKDescriptor* mvkDesc = nullptr;
        if (mvkDSLBind->getDescriptorType() == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
            setConfigurationResult(_pool->allocateDescriptor(mvkDSLBind->getDescriptorType(), &mvkDesc));
            if ( !wasConfigurationSuccessful() ) { break; }

            mvkDesc->setLayout(mvkDSLBind, 0);
            _descriptors.push_back(mvkDesc);
        } else {
            uint32_t descCnt = mvkDSLBind->getDescriptorCount();
            for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
                setConfigurationResult(_pool->allocateDescriptor(mvkDSLBind->getDescriptorType(), &mvkDesc));
                if ( !wasConfigurationSuccessful() ) { break; }

                mvkDesc->setLayout(mvkDSLBind, descIdx);
                _descriptors.push_back(mvkDesc);
            }
        }
		if ( !wasConfigurationSuccessful() ) { break; }
	}
}

MVKDescriptorSet::~MVKDescriptorSet() {
	for (auto mvkDesc : _descriptors) { _pool->freeDescriptor(mvkDesc); }
}


#pragma mark -
#pragma mark MVKDescriptorTypePreallocation

#ifndef MVK_CONFIG_PREALLOCATE_DESCRIPTORS
#   define MVK_CONFIG_PREALLOCATE_DESCRIPTORS    0
#endif

static bool _mvkPreallocateDescriptors = MVK_CONFIG_PREALLOCATE_DESCRIPTORS;
static bool _mvkPreallocateDescriptorsInitialized = false;

// Returns whether descriptors should be preallocated in the descriptor pools
// We do this once lazily instead of in a library constructor function to
// ensure the NSProcessInfo environment is available when called upon.
static inline bool getMVKPreallocateDescriptors() {
	if ( !_mvkPreallocateDescriptorsInitialized ) {
		_mvkPreallocateDescriptorsInitialized = true;
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(_mvkPreallocateDescriptors, MVK_CONFIG_PREALLOCATE_DESCRIPTORS);
	}
	return _mvkPreallocateDescriptors;
}

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

VkResult MVKDescriptorPool::allocateDescriptorSets(uint32_t count,
												   const VkDescriptorSetLayout* pSetLayouts,
												   VkDescriptorSet* pDescriptorSets) {
	if (_allocatedSets.size() + count > _maxSets) {
		if (_device->_enabledExtensions.vk_KHR_maintenance1.enabled) {
			return VK_ERROR_OUT_OF_POOL_MEMORY;		// Failure is an acceptable test...don't log as error.
		} else {
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "The maximum number of descriptor sets that can be allocated by this descriptor pool is %d.", _maxSets);
		}
	}

	VkResult rslt = VK_SUCCESS;
	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		MVKDescriptorSetLayout* mvkDSL = (MVKDescriptorSetLayout*)pSetLayouts[dsIdx];
		if ( !mvkDSL->isPushDescriptorLayout() ) {
			rslt = allocateDescriptorSet(mvkDSL, &pDescriptorSets[dsIdx]);
			if (rslt) { break; }
		}
	}
	return rslt;
}

// Ensure descriptor set was actually allocated, then return to pool
VkResult MVKDescriptorPool::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		MVKDescriptorSet* mvkDS = (MVKDescriptorSet*)pDescriptorSets[dsIdx];
		freeDescriptorSet(mvkDS);
		_allocatedSets.erase(mvkDS);
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
												  VkDescriptorSet* pVKDS) {
	MVKDescriptorSet* mvkDS = new MVKDescriptorSet(mvkDSL, this);
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
	_preallocatedDescriptors = getMVKPreallocateDescriptors() ? new MVKPreallocatedDescriptors(pCreateInfo) : nullptr;
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
		VkWriteDescriptorSetInlineUniformBlockEXT inlineUniformBlocks[descCnt];

		MVKDescriptorSet* srcSet = (MVKDescriptorSet*)pDescCopy->srcSet;
		srcSet->read(pDescCopy, imgInfos, buffInfos, texelBuffInfos, inlineUniformBlocks);

		MVKDescriptorSet* dstSet = (MVKDescriptorSet*)pDescCopy->dstSet;
		VkDescriptorType descType = dstSet->getDescriptorType(pDescCopy->dstBinding);
		size_t stride;
		const void* pData = getWriteParameters(descType, imgInfos, buffInfos, texelBuffInfos, inlineUniformBlocks, stride);
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
									   MVKSampler* immutableSampler) {
	mvk::MSLResourceBinding rb;

	auto& rbb = rb.resourceBinding;
	rbb.stage = stage;
	rbb.desc_set = descriptorSetIndex;
	rbb.binding = bindingIndex;
	rbb.msl_buffer = ssRB.bufferIndex;
	rbb.msl_texture = ssRB.textureIndex;
	rbb.msl_sampler = ssRB.samplerIndex;

	if (immutableSampler) { immutableSampler->getConstexprSampler(rb); }

	context.resourceBindings.push_back(rb);
}
