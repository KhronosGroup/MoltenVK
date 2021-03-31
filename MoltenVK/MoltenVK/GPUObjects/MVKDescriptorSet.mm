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
#include "MVKCommandBuffer.h"
#include "MVKCommandEncoderState.h"
#include "MVKPipeline.h"
#include "MVKInstance.h"
#include "MVKOSExtensions.h"


#pragma mark -
#pragma mark MVKDescriptorSetLayout

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayout::bindDescriptorSet(MVKCommandEncoder* cmdEncoder,
											   VkPipelineBindPoint pipelineBindPoint,
											   uint32_t descSetIndex,
											   MVKDescriptorSet* descSet,
											   MVKShaderResourceBinding& dslMTLRezIdxOffsets,
											   MVKArrayRef<uint32_t> dynamicOffsets,
											   uint32_t& dynamicOffsetIndex) {
	if (!cmdEncoder) { clearConfigurationResult(); }
	if (_isPushDescriptorLayout ) { return; }

	if (cmdEncoder) { cmdEncoder->bindDescriptorSet(pipelineBindPoint, descSetIndex,
													descSet, dslMTLRezIdxOffsets,
													dynamicOffsets, dynamicOffsetIndex); }
	if ( !isUsingMetalArgumentBuffers() ) {
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

	// Mark if Metal argument buffers are in use, but this descriptor set layout is not using them.
	if (isUsingMetalArgumentBuffers() && !isUsingMetalArgumentBuffer()) {
		context.discreteDescriptorSets.push_back(dslIndex);
	}
}

void MVKDescriptorSetLayout::populateDescriptorUsage(MVKBitArray& usageArray,
													 SPIRVToMSLConversionConfiguration& context,
													 uint32_t dslIndex) {
	uint32_t bindCnt = (uint32_t)_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		auto& dslBind = _bindings[bindIdx];
		if (context.isResourceUsed(dslIndex, dslBind.getBinding())) {
			uint32_t elemCnt = dslBind.getDescriptorCount();
			for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
				usageArray.setBit(dslBind.getDescriptorIndex(elemIdx));
			}
		}
	}
}

id<MTLArgumentEncoder> MVKDescriptorSetLayout::newMTLArgumentEncoder(MVKShaderStage stage,
																	 mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
																	 uint32_t descSetIdx) {
	if ( !isUsingMetalArgumentBuffer() ) { return nil; }

	@autoreleasepool {
		NSMutableArray<MTLArgumentDescriptor*>* args = [NSMutableArray arrayWithCapacity: _bindings.size()];
		for (auto& dslBind : _bindings) {
			dslBind.addMTLArgumentDescriptors(args, stage, shaderConfig, descSetIdx);
		}
		return (args.count) ? [getMTLDevice() newArgumentEncoderWithArguments: args] : nil;
	}
}

MVKDescriptorSetLayoutBinding* MVKDescriptorSetLayout::getBindingForDescriptorIndex(uint32_t descriptorIndex) {
	auto iter = std::lower_bound(_bindings.begin(), _bindings.end(), descriptorIndex, [](const MVKDescriptorSetLayoutBinding& dslBind, uint32_t descIdx) {
		return dslBind.getDescriptorIndex(dslBind.getDescriptorCount()) <= descIdx;
	});
	return iter != _bindings.end() ? iter : nullptr;
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

	_descriptorCount = 0;
	_metalArgumentBufferSize = 0;
	_isPushDescriptorLayout = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR);

	_bindings.reserve(bindCnt);
    for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		BindInfo& bindInfo = sortedBindings[bindIdx];
        _bindings.emplace_back(_device, this, bindInfo.pBinding, bindInfo.bindingFlags, _descriptorCount);
		_bindingToIndex[bindInfo.pBinding->binding] = bindIdx;
		_descriptorCount += _bindings.back().getDescriptorCount();
	}

	if (isUsingMetalArgumentBuffer()) {
		// Set _metalArgumentBufferSize before adding the argument buffer itself.
		_metalArgumentBufferSize = mvkAlignByteCount(_mtlResourceCounts.getMaxResourceIndex() * sizeof(id), getDevice()->_pMetalFeatures->mtlBufferAlignment);
		_mtlResourceCounts.addArgumentBuffer();
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

id<MTLBuffer> MVKDescriptorSet::getMetalArgumentBuffer() { return _pool->_metalArgumentBuffer; }

template<typename DescriptorAction>
void MVKDescriptorSet::write(const DescriptorAction* pDescriptorAction,
							 size_t stride,
							 const void* pData) {
#define writeDescriptorAt(IDX)                                    \
	do {                                                          \
		MVKDescriptor* mvkDesc = _descriptors[descIdx];           \
		if (mvkDesc->getDescriptorType() == descType) {           \
			mvkDesc->write(mvkDSLBind, this, IDX, stride, pData); \
			_metalArgumentBufferDirtyDescriptors.setBit(descIdx); \
		}                                                         \
	} while(false)

	MVKDescriptorSetLayoutBinding* mvkDSLBind = _layout->getBinding(pDescriptorAction->dstBinding);
	VkDescriptorType descType = mvkDSLBind->getDescriptorType();
	if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		// For inline buffers dstArrayElement is a byte offset
		uint32_t descIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding);
		writeDescriptorAt(pDescriptorAction->dstArrayElement);
	} else {
		uint32_t descStartIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding, pDescriptorAction->dstArrayElement);
		uint32_t elemCnt = pDescriptorAction->descriptorCount;
		for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
			uint32_t descIdx = descStartIdx + elemIdx;
			writeDescriptorAt(elemIdx);
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

// Extract bind dynamic buffer offset for each dynamic buffer descriptor, and mark the descriptor as dirty.
void MVKDescriptorSet::bindDynamicOffsets(MVKResourcesCommandEncoderState* rezEncState,
										  uint32_t descSetIndex,
										  MVKArrayRef<uint32_t> dynamicOffsets,
										  uint32_t& dynamicOffsetIndex) {
	_dynamicBufferDescriptors.enumerateEnabledBits(false, [&](size_t descIdx) {
		if (dynamicOffsetIndex >= dynamicOffsets.size) { return false; }	// We've run out of dynamic offsets
		rezEncState->bindDynamicBufferOffset(descSetIndex, (uint32_t)descIdx, dynamicOffsets[dynamicOffsetIndex++]);
		_metalArgumentBufferDirtyDescriptors.setBit(descIdx);
		return true;
	});
}

const MVKMTLBufferAllocation* MVKDescriptorSet::acquireMTLBufferRegion(NSUInteger length) {
	return _pool->_inlineBlockMTLBufferAllocator.acquireMTLBufferRegion(length);
}

VkResult MVKDescriptorSet::allocate(MVKDescriptorSetLayout* layout,
									uint32_t variableDescriptorCount,
									NSUInteger mtlArgBufferOffset) {
	_layout = layout;
	_variableDescriptorCount = variableDescriptorCount;

	// If the Metal argument buffer offset has not been set yet, set it now.
	if ( !_metalArgumentBufferOffset ) { _metalArgumentBufferOffset = mtlArgBufferOffset; }

	uint32_t descCnt = layout->getDescriptorCount();
	_descriptors.reserve(descCnt);
	_dynamicBufferDescriptors.resize(descCnt);
	_metalArgumentBufferDirtyDescriptors.resize(descCnt);

	uint32_t bindCnt = (uint32_t)layout->_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		MVKDescriptorSetLayoutBinding* mvkDSLBind = &layout->_bindings[bindIdx];
		uint32_t elemCnt = mvkDSLBind->getDescriptorCount(this);
		for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
			VkDescriptorType descType = mvkDSLBind->getDescriptorType();
			MVKDescriptor* mvkDesc = nullptr;
			setConfigurationResult(_pool->allocateDescriptor(descType, &mvkDesc));
			if ( !wasConfigurationSuccessful() ) { return getConfigurationResult(); }
			if (mvkDesc->usesDynamicBufferOffsets()) { _dynamicBufferDescriptors.setBit(_descriptors.size()); }
			_descriptors.push_back(mvkDesc);
		}
	}
	return getConfigurationResult();
}

void MVKDescriptorSet::free(bool isPoolReset) {
	_layout = nullptr;
	_variableDescriptorCount = 0;

	// Only reset the Metal arg buffer offset if the entire pool is being reset
	if (isPoolReset) { _metalArgumentBufferOffset = 0; }

	// Pooled descriptors don't need to be individually freed under pool resets.
	if ( !(_pool->_hasPooledDescriptors && isPoolReset) ) {
		for (auto mvkDesc : _descriptors) { _pool->freeDescriptor(mvkDesc); }
	}
	_descriptors.clear();
	_descriptors.shrink_to_fit();
	_dynamicBufferDescriptors.resize(0);
	_metalArgumentBufferDirtyDescriptors.resize(0);

	clearConfigurationResult();
}

MVKDescriptorSet::MVKDescriptorSet(MVKDescriptorPool* pool) : MVKVulkanAPIDeviceObject(pool->_device), _pool(pool) {
	free(true);
}


#pragma mark -
#pragma mark MVKDescriptorTypePool

// If preallocated, find the next availalble descriptor.
// If not preallocated, create one on the fly.
template<class DescriptorClass>
VkResult MVKDescriptorTypePool<DescriptorClass>::allocateDescriptor(MVKDescriptor** pMVKDesc,
																			 MVKDescriptorPool* pool) {
	DescriptorClass* mvkDesc;
	if (pool->_hasPooledDescriptors) {
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
void MVKDescriptorTypePool<DescriptorClass>::freeDescriptor(MVKDescriptor* mvkDesc,
																	 MVKDescriptorPool* pool) {
	if (pool->_hasPooledDescriptors) {
		size_t descIdx = (DescriptorClass*)mvkDesc - _descriptors.data();
		_availability.setBit(descIdx);
	} else {
		mvkDesc->destroy();
	}
}

// Preallocated descriptors will be reset when they are reused
template<typename DescriptorClass>
void MVKDescriptorTypePool<DescriptorClass>::reset() {
	_availability.setAllBits();
}

template<typename DescriptorClass>
MVKDescriptorTypePool<DescriptorClass>::MVKDescriptorTypePool(size_t poolSize) :
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
			if (rslt) { return rslt; }
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
	VkResult rslt = VK_ERROR_OUT_OF_POOL_MEMORY;
	NSUInteger mtlArgBuffAllocSize = mvkDSL->_metalArgumentBufferSize;
	size_t dsCnt = _descriptorSetAvailablility.size();
	_descriptorSetAvailablility.enumerateEnabledBits(true, [&](size_t dsIdx) {
		bool isSpaceAvail = true;		// If not using Metal arg buffers, space will always be available.
		MVKDescriptorSet* mvkDS = &_descriptorSets[dsIdx];
		NSUInteger mtlArgBuffOffset = mvkDS->_metalArgumentBufferOffset;

		// If the desc set is using a Metal argument buffer, we also need to see if the desc set
		// will fit in the slot that might already have been allocated for it in the Metal argument
		// buffer from a previous allocation that was returned. If this pool has been reset recently,
		// then the desc sets will not have had a Metal argument buffer allocation assigned yet.
		if (mvkDSL->isUsingMetalArgumentBuffer()) {

			// If the offset has not been set (and it's not the first desc set except
			// on a reset pool), set the offset and update the next available offset value.
			if ( !mtlArgBuffOffset && (dsIdx || !_nextMetalArgumentBufferOffset)) {
				mtlArgBuffOffset = _nextMetalArgumentBufferOffset;
				_nextMetalArgumentBufferOffset += mtlArgBuffAllocSize;
			}

			// Get the offset of the next desc set, if one exists and
			// its offset has been set, or the end of the arg buffer.
			size_t nextDSIdx = dsIdx + 1;
			NSUInteger nextOffset = (nextDSIdx < dsCnt ? _descriptorSets[nextDSIdx]._metalArgumentBufferOffset : 0);
			if ( !nextOffset ) { nextOffset = _metalArgumentBuffer.length; }

			isSpaceAvail = (mtlArgBuffOffset + mtlArgBuffAllocSize) <= nextOffset;
		}

		if (isSpaceAvail) {
			rslt = mvkDS->allocate(mvkDSL, variableDescriptorCount, mtlArgBuffOffset);
			if (rslt) {
				freeDescriptorSet(mvkDS, false);
			} else {
				*pVKDS = (VkDescriptorSet)mvkDS;
			}
			return false;
		}
		return true;
	});
	return rslt;
}

VkResult MVKDescriptorPool::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		freeDescriptorSet((MVKDescriptorSet*)pDescriptorSets[dsIdx], false);
	}
	return VK_SUCCESS;
}

// Descriptor sets are held in contiguous memory, so the index of the returning descriptor
// set can be calculated by pointer differences, and it can be marked as available.
// Don't bother individually set descriptor set availability if pool is being reset.
void MVKDescriptorPool::freeDescriptorSet(MVKDescriptorSet* mvkDS, bool isPoolReset) {
	if ( !mvkDS ) { return; }	// Vulkan allows NULL refs.

	if (mvkDS->_pool == this) {
		mvkDS->free(isPoolReset);
		if ( !isPoolReset ) {
			size_t dsIdx = mvkDS - _descriptorSets.data();
			_descriptorSetAvailablility.setBit(dsIdx);
		}
	} else {
		reportError(VK_ERROR_INITIALIZATION_FAILED, "A descriptor set is being returned to a descriptor pool that did not allocate it.");
	}
}

// Free all descriptor sets and reset descriptor pools
VkResult MVKDescriptorPool::reset(VkDescriptorPoolResetFlags flags) {
	for (auto& mvkDS : _descriptorSets) { freeDescriptorSet(&mvkDS, true); }
	_descriptorSetAvailablility.setAllBits();

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
			return _uniformBufferDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			return _storageBufferDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			return _uniformBufferDynamicDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return _storageBufferDynamicDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			return _inlineUniformBlockDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			return _sampledImageDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			return _storageImageDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return _inputAttachmentDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			return _samplerDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return _combinedImageSamplerDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			return _uniformTexelBufferDescriptors.allocateDescriptor(pMVKDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			return _storageTexelBufferDescriptors.allocateDescriptor(pMVKDesc, this);

		default:
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "Unrecognized VkDescriptorType %d.", descriptorType);
	}
}

void MVKDescriptorPool::freeDescriptor(MVKDescriptor* mvkDesc) {
	VkDescriptorType descriptorType = mvkDesc->getDescriptorType();
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			return _uniformBufferDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			return _storageBufferDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			return _uniformBufferDynamicDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return _storageBufferDynamicDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			return _inlineUniformBlockDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			return _sampledImageDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			return _storageImageDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return _inputAttachmentDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			return _samplerDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return _combinedImageSamplerDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			return _uniformTexelBufferDescriptors.freeDescriptor(mvkDesc, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			return _storageTexelBufferDescriptors.freeDescriptor(mvkDesc, this);

		default:
			reportError(VK_ERROR_INITIALIZATION_FAILED, "Unrecognized VkDescriptorType %d.", descriptorType);
	}
}

// Return the size of the preallocated pool for descriptors of the specified type,
// or zero if we are not preallocating descriptors in the pool.
// There may be more than one poolSizeCount instance for the desired VkDescriptorType.
// Accumulate the descriptor count for the desired VkDescriptorType accordingly.
static size_t getPoolSize(const VkDescriptorPoolCreateInfo* pCreateInfo, VkDescriptorType descriptorType, bool poolDescriptors) {
	uint32_t descCnt = 0;
	if (poolDescriptors) {
		uint32_t poolCnt = pCreateInfo->poolSizeCount;
		for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
			auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
			if (poolSize.type == descriptorType) { descCnt += poolSize.descriptorCount; }
		}
	}
	return descCnt;
}

// Although poolDescriptors is derived from MVKConfiguration, it is passed in here to ensure all components of this instance see a SVOT for this value.
// Alternate might have been to force _hasPooledDescriptors to be set first by changing member declaration order in class declaration.
MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo, bool poolDescriptors) :
	MVKVulkanAPIDeviceObject(device),
	_descriptorSets(pCreateInfo->maxSets, MVKDescriptorSet(this)),
	_descriptorSetAvailablility(pCreateInfo->maxSets, true),
	_uniformBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, poolDescriptors)),
	_storageBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, poolDescriptors)),
	_uniformBufferDynamicDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, poolDescriptors)),
	_storageBufferDynamicDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, poolDescriptors)),
	_inlineUniformBlockDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT, poolDescriptors)),
	_sampledImageDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, poolDescriptors)),
	_storageImageDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, poolDescriptors)),
	_inputAttachmentDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, poolDescriptors)),
	_samplerDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLER, poolDescriptors)),
	_combinedImageSamplerDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, poolDescriptors)),
	_uniformTexelBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER, poolDescriptors)),
	_storageTexelBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, poolDescriptors)),
	_inlineBlockMTLBufferAllocator(device, getMaxInlineBlockSize(pCreateInfo), true),
	_hasPooledDescriptors(poolDescriptors) {
		initMetalArgumentBuffer(pCreateInfo);
	}

void MVKDescriptorPool::initMetalArgumentBuffer(const VkDescriptorPoolCreateInfo* pCreateInfo) {
	_metalArgumentBuffer = nil;
	_nextMetalArgumentBufferOffset = 0;

	if ( !isUsingMetalArgumentBuffers() ) { return; }

	NSUInteger mtlArgBuffSize = 0;
	uint32_t poolCnt = pCreateInfo->poolSizeCount;
	for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
		auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
		mtlArgBuffSize += getDescriptorByteCountForMetalArgumentBuffer(poolSize.type) * poolSize.descriptorCount;
	}

	// Leave room for each desc set to be aligned
	mtlArgBuffSize += pCreateInfo->maxSets * _device->_pMetalFeatures->mtlBufferAlignment;

	if (mtlArgBuffSize) {
		_metalArgumentBuffer = [getMTLDevice() newBufferWithLength: mtlArgBuffSize options: MTLResourceStorageModeShared];	// retained
		_metalArgumentBuffer.label = @"Argument buffer";
	}
}

NSUInteger MVKDescriptorPool::getDescriptorByteCountForMetalArgumentBuffer(VkDescriptorType descriptorType) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return sizeof(id<MTLBuffer>);

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			return 1;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return sizeof(id<MTLTexture>);

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			return sizeof(id<MTLTexture>) + sizeof(id<MTLBuffer>);

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			return sizeof(id<MTLSamplerState>);

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return sizeof(id<MTLTexture>) + sizeof(id<MTLSamplerState>);

		default:
			return 0;
	}
}

NSUInteger MVKDescriptorPool::getMaxInlineBlockSize(const VkDescriptorPoolCreateInfo* pCreateInfo) {
	NSUInteger maxInlineBlockSize = 0;
	uint32_t poolCnt = pCreateInfo->poolSizeCount;
	for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
		auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
		if (poolSize.type == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
			NSUInteger iubSize = getDescriptorByteCountForMetalArgumentBuffer(poolSize.type) * poolSize.descriptorCount;
			maxInlineBlockSize = std::max(iubSize, maxInlineBlockSize);
		}
	}
	return std::min<NSUInteger>(maxInlineBlockSize, _device->_pMetalFeatures->maxMTLBufferSize);
}

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
