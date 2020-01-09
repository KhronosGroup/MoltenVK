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

using namespace mvk;


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
                                               MVKVector<uint32_t>& dynamicOffsets,
                                               uint32_t* pDynamicOffsetIndex) {
    if (_isPushDescriptorLayout) return;

	clearConfigurationResult();
    uint32_t bindCnt = (uint32_t)_bindings.size();
    for (uint32_t descIdx = 0, bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		descIdx += _bindings[bindIdx].bind(cmdEncoder, descSet, descIdx,
										   dslMTLRezIdxOffsets, dynamicOffsets,
										   pDynamicOffsetIndex);
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
                                               MVKVector<VkWriteDescriptorSet>& descriptorWrites,
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
            for (auto* next = (VkWriteDescriptorSetInlineUniformBlockEXT*)descWrite.pNext; next; next = (VkWriteDescriptorSetInlineUniformBlockEXT*)next->pNext)
            {
                switch (next->sType) {
                case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK_EXT: {
                    pInlineUniformBlock = next;
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

void MVKDescriptorSetLayout::populateShaderConverterContext(SPIRVToMSLConversionConfiguration& context,
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
    // Create the descriptor bindings
    _bindings.reserve(pCreateInfo->bindingCount);
    for (uint32_t i = 0; i < pCreateInfo->bindingCount; i++) {
        _bindings.emplace_back(_device, this, &pCreateInfo->pBindings[i]);
        _bindingToIndex[pCreateInfo->pBindings[i].binding] = i;
    }
}

MVKDescriptorSetLayout::~MVKDescriptorSetLayout() {
	for (auto& dsPool : _descriptorPools) { dsPool->removeDescriptorSetPool(this); }
}


#pragma mark -
#pragma mark MVKDescriptorSet

template<typename DescriptorAction>
void MVKDescriptorSet::writeDescriptorSets(const DescriptorAction* pDescriptorAction,
                                           size_t stride, const void* pData) {

	uint32_t dstStartIdx = _pLayout->getDescriptorIndex(pDescriptorAction->dstBinding,
													   pDescriptorAction->dstArrayElement);
	uint32_t descCnt = pDescriptorAction->descriptorCount;
	for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
		_bindings[dstStartIdx + descIdx].writeBinding(descIdx, stride, pData);
	}
}

// Create concrete implementations of the three variations of the writeDescriptorSets() function.
template void MVKDescriptorSet::writeDescriptorSets<VkWriteDescriptorSet>(const VkWriteDescriptorSet* pDescriptorAction,
																		  size_t stride, const void *pData);
template void MVKDescriptorSet::writeDescriptorSets<VkCopyDescriptorSet>(const VkCopyDescriptorSet* pDescriptorAction,
																		 size_t stride, const void *pData);
template void MVKDescriptorSet::writeDescriptorSets<VkDescriptorUpdateTemplateEntryKHR>(
	const VkDescriptorUpdateTemplateEntryKHR* pDescriptorAction,
	size_t stride, const void *pData);

void MVKDescriptorSet::readDescriptorSets(const VkCopyDescriptorSet* pDescriptorCopy,
										  VkDescriptorType& descType,
										  VkDescriptorImageInfo* pImageInfo,
										  VkDescriptorBufferInfo* pBufferInfo,
										  VkBufferView* pTexelBufferView,
										  VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {

	uint32_t srcStartIdx = _pLayout->getDescriptorIndex(pDescriptorCopy->srcBinding,
														pDescriptorCopy->srcArrayElement);
	uint32_t descCnt = pDescriptorCopy->descriptorCount;
	for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
		_bindings[srcStartIdx + descIdx].readBinding(descIdx, descType, pImageInfo, pBufferInfo,
													 pTexelBufferView, pInlineUniformBlock);
	}
}

// If the layout has changed, create the binding slots, each referencing a corresponding binding layout
void MVKDescriptorSet::setLayout(MVKDescriptorSetLayout* layout) {
	if (layout == _pLayout) { return; }

	_pLayout = layout;
	_bindings.clear();

	uint32_t bindCnt = (uint32_t)layout->_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		MVKDescriptorSetLayoutBinding* dslBind = &layout->_bindings[bindIdx];
		uint32_t descCnt = dslBind->getDescriptorCount();
		for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
			_bindings.emplace_back(this, dslBind, descIdx);
		}
	}
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

	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		MVKDescriptorSetLayout* mvkDSL = (MVKDescriptorSetLayout*)pSetLayouts[dsIdx];
		if ( !mvkDSL->isPushDescriptorLayout() ) {
			MVKDescriptorSet* mvkDS = getDescriptorSetPool(mvkDSL)->acquireObject();
			mvkDS->setLayout(mvkDSL);
			_allocatedSets.insert(mvkDS);
			pDescriptorSets[dsIdx] = (VkDescriptorSet)mvkDS;
		}
	}
	return VK_SUCCESS;
}

// Ensure descriptor set was actually allocated, then return to pool
VkResult MVKDescriptorPool::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		MVKDescriptorSet* mvkDS = (MVKDescriptorSet*)pDescriptorSets[dsIdx];
		if (_allocatedSets.erase(mvkDS)) { returnDescriptorSet(mvkDS); }
	}
	return VK_SUCCESS;
}

// Return any allocated descriptor sets to their pools
VkResult MVKDescriptorPool::reset(VkDescriptorPoolResetFlags flags) {
	for (auto& mvkDS : _allocatedSets) { returnDescriptorSet(mvkDS); }
	_allocatedSets.clear();
	return VK_SUCCESS;
}

// Returns the descriptor set to its pool, or if that pool doesn't exist, the descriptor set is destroyed
void MVKDescriptorPool::returnDescriptorSet(MVKDescriptorSet* mvkDescSet) {
	MVKDescriptorSetLayout* dsLayout = mvkDescSet->_pLayout;
	MVKDescriptorSetPool* dsPool = dsLayout ? _descriptorSetPools[dsLayout] : nullptr;
	if (dsPool) {
		dsPool->returnObject(mvkDescSet);
	} else {
		mvkDescSet->destroy();
		_descriptorSetPools.erase(dsLayout);
	}
}

// Returns the pool of descriptor sets that use a specific layout, lazily creating it if necessary
MVKDescriptorSetPool* MVKDescriptorPool::getDescriptorSetPool(MVKDescriptorSetLayout* mvkDescSetLayout) {
	MVKDescriptorSetPool* dsp = _descriptorSetPools[mvkDescSetLayout];
	if ( !dsp ) {
		dsp = new MVKDescriptorSetPool(_device);
		_descriptorSetPools[mvkDescSetLayout] = dsp;
		mvkDescSetLayout->addDescriptorPool(this);		// tell layout to track me
	}
	return dsp;
}

// Remove the descriptor set pool associated with the descriptor set layout,
// and make sure any allocated sets don't try to return back to their pools.
void MVKDescriptorPool::removeDescriptorSetPool(MVKDescriptorSetLayout* mvkDescSetLayout) {
	MVKDescriptorSetPool* dsp = _descriptorSetPools[mvkDescSetLayout];
	if (dsp) { dsp->destroy(); }
	_descriptorSetPools.erase(mvkDescSetLayout);

	for (auto& mvkDS : _allocatedSets) {
		if (mvkDS->_pLayout == mvkDescSetLayout) { mvkDS->_pLayout = nullptr; }
	}
}

MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device,
									 const VkDescriptorPoolCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	_maxSets = pCreateInfo->maxSets;
}

// Return any allocated sets to their pools and then destroy all the pools,
// and ensure any descriptor set layouts used as keys are notified.
MVKDescriptorPool::~MVKDescriptorPool() {
	reset(0);
	for (auto& pair : _descriptorSetPools) {
		pair.first->removeDescriptorPool(this);
		if (pair.second) { pair.second->destroy(); }
	}
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
			for (auto* next = (VkWriteDescriptorSetInlineUniformBlockEXT*)pDescWrite->pNext; next; next = (VkWriteDescriptorSetInlineUniformBlockEXT*)next->pNext)
			{
				switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK_EXT: {
					pInlineUniformBlock = next;
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
		dstSet->writeDescriptorSets(pDescWrite, stride, pData);
	}

	// Perform the copy updates by reading bindings from one set and writing to other set.
	for (uint32_t i = 0; i < copyCount; i++) {
		const VkCopyDescriptorSet* pDescCopy = &pDescriptorCopies[i];

		uint32_t descCnt = pDescCopy->descriptorCount;
		VkDescriptorType descType;
		VkDescriptorImageInfo imgInfos[descCnt];
		VkDescriptorBufferInfo buffInfos[descCnt];
		VkBufferView texelBuffInfos[descCnt];
		VkWriteDescriptorSetInlineUniformBlockEXT inlineUniformBlocks[descCnt];

		MVKDescriptorSet* srcSet = (MVKDescriptorSet*)pDescCopy->srcSet;
		srcSet->readDescriptorSets(pDescCopy, descType, imgInfos, buffInfos, texelBuffInfos, inlineUniformBlocks);

		MVKDescriptorSet* dstSet = (MVKDescriptorSet*)pDescCopy->dstSet;
		size_t stride;
		const void* pData = getWriteParameters(descType, imgInfos, buffInfos, texelBuffInfos, inlineUniformBlocks, stride);
		dstSet->writeDescriptorSets(pDescCopy, stride, pData);
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
		dstSet->writeDescriptorSets(pEntry, pEntry->stride, pCurData);
	}
}

void mvkPopulateShaderConverterContext(SPIRVToMSLConversionConfiguration& context,
									   MVKShaderStageResourceBinding& ssRB,
									   spv::ExecutionModel stage,
									   uint32_t descriptorSetIndex,
									   uint32_t bindingIndex,
									   MVKSampler* immutableSampler) {
	MSLResourceBinding rb;

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
