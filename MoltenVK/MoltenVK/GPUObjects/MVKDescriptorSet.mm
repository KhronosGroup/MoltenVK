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
#include "MVKCommandBuffer.h"
#include "MVKInstance.h"
#include "MVKOSExtensions.h"

using namespace std;


#pragma mark -
#pragma mark MVKDescriptorSetLayout

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayout::bindDescriptorSet(MVKCommandEncoder* cmdEncoder,
											   MVKDescriptorSet* descSet,
											   uint32_t descSetLayoutIndex,
											   MVKShaderResourceBinding& dslMTLRezIdxOffsets,
											   MVKArrayRef<uint32_t> dynamicOffsets,
											   uint32_t& dynamicOffsetIndex) {
	if (!cmdEncoder) { clearConfigurationResult(); }
	if (_isPushDescriptorLayout ) { return; }

	lock_guard<mutex> lock(_argEncodingLock);
	bindMetalArgumentBuffer(descSet);

	for (auto& dslBind : _bindings) {
		dslBind.bind(cmdEncoder, descSet, dslMTLRezIdxOffsets, dynamicOffsets, dynamicOffsetIndex);
	}

	bindMetalArgumentBuffer(nullptr);

	// If we're using Metal argument buffer, bind it to the command encoder in each stage that will use it.
	if (cmdEncoder) {
		id<MTLBuffer> mtlArgBuff = descSet->getMetalArgumentBuffer();
		NSUInteger descSetOffset = descSet->getMetalArgumentBufferOffset();
		if (mtlArgBuff) {
			MVKMTLBufferBinding bb;
			bb.mtlBuffer = mtlArgBuff;
			bb.index = descSetLayoutIndex;
			for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
				auto& argEnc = _argumentEncoder[stage];
				if (argEnc.mtlArgumentEncoder) {
					bb.offset = descSetOffset + argEnc.argumentBufferOffset;
					cmdEncoder->bindBuffer(bb, MVKShaderStage(stage));
				}
			}
		}
	}
}

void MVKDescriptorSetLayout::bindMetalArgumentBuffer(MVKDescriptorSet* descSet) {
	id<MTLBuffer> mtlArgBuff = descSet ? descSet->getMetalArgumentBuffer() : nil;
	NSUInteger descSetOffset = descSet ? descSet->getMetalArgumentBufferOffset() : 0;
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		auto& argEnc = _argumentEncoder[stage];
		[argEnc.mtlArgumentEncoder setArgumentBuffer: mtlArgBuff
											  offset: (descSetOffset + argEnc.argumentBufferOffset)];
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
	if (supportsMetalArgumentBuffers() && !isUsingMetalArgumentBuffer()) {
		context.discreteDescriptorSets.push_back(dslIndex);
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
	sort(sortedBindings.begin(), sortedBindings.end(), [](BindInfo bindInfo1, BindInfo bindInfo2) {
		return bindInfo1.pBinding->binding < bindInfo2.pBinding->binding;
	});

	_isPushDescriptorLayout = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR);
	_descriptorCount = 0;
    _bindings.reserve(bindCnt);
    for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		BindInfo& bindInfo = sortedBindings[bindIdx];
        _bindings.emplace_back(_device, this, bindInfo.pBinding, bindInfo.bindingFlags, _descriptorCount);
		_bindingToIndex[bindInfo.pBinding->binding] = bindIdx;
		_descriptorCount += _bindings.back().getDescriptorCount();
	}

	initMTLArgumentEncoders();
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

void MVKDescriptorSetLayout::initMTLArgumentEncoders() {
	_argumentBufferSize = 0;

	if ( !isUsingMetalArgumentBuffer() ) { return; }

	auto* mvkDvc = getDevice();
	@autoreleasepool {
		id<MTLDevice> mtlDvc = mvkDvc->getMTLDevice();
		NSMutableArray<MTLArgumentDescriptor*>* args = [NSMutableArray arrayWithCapacity: _bindings.size()];
		for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
			[args removeAllObjects];
			uint32_t argIdx = 0;
			for (auto& dslBind : _bindings) {
				dslBind.addMTLArgumentDescriptors(stage, args, argIdx);
			}
			if (args.count) {
				auto& argEnc = _argumentEncoder[stage];
				argEnc.mtlArgumentEncoder = [mtlDvc newArgumentEncoderWithArguments: args];		// retained
				argEnc.argumentBufferOffset = _argumentBufferSize;
				_argumentBufferSize += mvkAlignByteCount(argEnc.mtlArgumentEncoder.encodedLength,
														 mvkDvc->_pMetalFeatures->mtlBufferAlignment);
			}
		}
	}
}


#pragma mark -
#pragma mark MVKDescriptorSet

VkDescriptorType MVKDescriptorSet::getDescriptorType(uint32_t binding) {
	return _layout->getBinding(binding)->getDescriptorType();
}

MVKDescriptor* MVKDescriptorSet::getDescriptor(uint32_t binding, uint32_t elementIndex) {
	return _descriptors[_layout->getDescriptorIndex(binding, elementIndex)];
}

id<MTLBuffer> MVKDescriptorSet::getMetalArgumentBuffer() { return _pool->_mtlArgumentBuffer; }

template<typename DescriptorAction>
void MVKDescriptorSet::write(const DescriptorAction* pDescriptorAction,
							 size_t stride,
							 const void* pData) {

	lock_guard<mutex> lock(_layout->_argEncodingLock);
	_layout->bindMetalArgumentBuffer(this);

	MVKDescriptorSetLayoutBinding* mvkDSLBind = _layout->getBinding(pDescriptorAction->dstBinding);
	VkDescriptorType descType = mvkDSLBind->getDescriptorType();
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		// For inline buffers dstArrayElement is a byte offset
		MVKDescriptor* mvkDesc = getDescriptor(pDescriptorAction->dstBinding);
		if (mvkDesc->getDescriptorType() == descType) {
			mvkDesc->write(mvkDSLBind, this, pDescriptorAction->dstArrayElement, 0, stride, pData);
		}
    } else {
		uint32_t descStartIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding, pDescriptorAction->dstArrayElement);
		uint32_t descCnt = pDescriptorAction->descriptorCount;
		for (uint32_t srcIdx = 0; srcIdx < descCnt; srcIdx++) {
			MVKDescriptor* mvkDesc = _descriptors[descStartIdx + srcIdx];
			if (mvkDesc->getDescriptorType() == descType) {
				uint32_t dstIdx = pDescriptorAction->dstArrayElement + srcIdx;
				mvkDesc->write(mvkDSLBind, this, srcIdx, dstIdx, stride, pData);
			}
		}
	}

	// For some unexpected reason, GPU capture on Xcode 12 doesn't always correctly expose
	// the contents of Metal argument buffers. Triggering an extraction of the arg buffer
	// contents here, after filling it, seems to correct that.
	// Sigh. A bug report has been filed with Apple.
	if (getInstance()->isCurrentlyAutoGPUCapturing()) { [_pool->_mtlArgumentBuffer contents]; }

	_layout->bindMetalArgumentBuffer(nullptr);
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
		// For inline buffers srcArrayElement is a byte offset
		MVKDescriptor* mvkDesc = getDescriptor(pDescriptorCopy->srcBinding);
		if (mvkDesc->getDescriptorType() == descType) {
			mvkDesc->read(pDescriptorCopy->srcArrayElement, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
		}
    } else {
        uint32_t srcStartIdx = _layout->getDescriptorIndex(pDescriptorCopy->srcBinding, pDescriptorCopy->srcArrayElement);
        for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
			MVKDescriptor* mvkDesc = _descriptors[srcStartIdx + descIdx];
			if (mvkDesc->getDescriptorType() == descType) {
				mvkDesc->read(descIdx, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
			}
        }
    }
}

const MVKMTLBufferAllocation* MVKDescriptorSet::acquireMTLBufferRegion(NSUInteger length) {
	return _pool->_inlineBlockMTLBufferAllocator.acquireMTLBufferRegion(length);
}

VkResult MVKDescriptorSet::allocate(MVKDescriptorSetLayout* layout,
									uint32_t variableDescriptorCount,
									NSUInteger mtlArgumentBufferOffset) {
	_layout = layout;
	_variableDescriptorCount = variableDescriptorCount;

	// If the Metal argument buffer offset has not been set yet, set it now.
	if ( !_mtlArgumentBufferOffset ) { _mtlArgumentBufferOffset = mtlArgumentBufferOffset; }

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
	return getConfigurationResult();
}

void MVKDescriptorSet::free(bool isPoolReset) {
	_layout = nullptr;
	_variableDescriptorCount = 0;

	// Only reset the Metal arg buffer offset if the entire pool is being reset
	if (isPoolReset) { _mtlArgumentBufferOffset = 0; }

	for (auto mvkDesc : _descriptors) { _pool->freeDescriptor(mvkDesc); }
	_descriptors.clear();

	clearConfigurationResult();
}

MVKDescriptorSet::MVKDescriptorSet(MVKDescriptorPool* pool) : MVKVulkanAPIDeviceObject(pool->_device), _pool(pool) {
	free(true);
}


#pragma mark -
#pragma mark MVKDescriptorTypePreallocation

#ifndef MVK_CONFIG_PREALLOCATE_DESCRIPTORS
#   define MVK_CONFIG_PREALLOCATE_DESCRIPTORS    1
#endif

// Returns whether descriptors should be preallocated in the descriptor pools
// We do this once lazily instead of in a library constructor function to
// ensure the NSProcessInfo environment is available when called upon.
static inline bool mvkShouldPreallocateDescriptors() {
	static bool _mvkShouldPreallocateDescriptors = MVK_CONFIG_PREALLOCATE_DESCRIPTORS;
	static bool _mvkShouldPreallocateDescriptorsInitialized = false;
	if ( !_mvkShouldPreallocateDescriptorsInitialized ) {
		_mvkShouldPreallocateDescriptorsInitialized = true;
		MVK_SET_FROM_ENV_OR_BUILD_BOOL(_mvkShouldPreallocateDescriptors, MVK_CONFIG_PREALLOCATE_DESCRIPTORS);
	}
	return _mvkShouldPreallocateDescriptors;
}

template<class DescriptorClass>
VkResult MVKDescriptorTypePreallocation<DescriptorClass>::allocateDescriptor(MVKDescriptor** pMVKDesc) {

	// If we don't preallocate, create and return an instance on the fly.
	if ( !mvkShouldPreallocateDescriptors() ) {
		*pMVKDesc = new DescriptorClass();
		return VK_SUCCESS;
	}

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

	// If we don't preallocate, create and return an instance on the fly.
	if ( !mvkShouldPreallocateDescriptors() ) {
		mvkDesc->destroy();
		return;
	}

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
	// Determine whether we need to track the availability of previously freed descriptors.
	_supportAvailability = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT);
	_nextAvailableIndex = 0;

	if (mvkShouldPreallocateDescriptors()) {
		// There may be more than  one poolSizeCount instance for the desired VkDescriptorType.
		// Accumulate the descriptor count for the desired VkDescriptorType, and size the collections accordingly.
		uint32_t descriptorCount = 0;
		uint32_t poolCnt = pCreateInfo->poolSizeCount;
		for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
			auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
			if (poolSize.type == descriptorType) { descriptorCount += poolSize.descriptorCount; }
		}

		_descriptors.resize(descriptorCount);
		if (_supportAvailability) { _availability.resize(descriptorCount, true); }
	}
}


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

// Ensure descriptor set was actually allocated, then return to pool
VkResult MVKDescriptorPool::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		freeDescriptorSet((MVKDescriptorSet*)pDescriptorSets[dsIdx], false);
	}
	return VK_SUCCESS;
}

// Free all descriptor sets.
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

	_nextMTLArgumentBufferOffset = 0;

	return VK_SUCCESS;
}

// Retieves the first available descriptor set, and configures it.
// If none are available, returns an error.
VkResult MVKDescriptorPool::allocateDescriptorSet(MVKDescriptorSetLayout* mvkDSL,
												  uint32_t variableDescriptorCount,
												  VkDescriptorSet* pVKDS) {
	NSUInteger mtlArgBuffAllocSize = mvkDSL->getArgumentBufferSize();
	size_t dsCnt = _descriptorSets.size();
	size_t dsIdx = 0;
	while (true) {
		dsIdx = _descriptorSetAvailablility.getIndexOfFirstSetBit(dsIdx, true);
		if (dsIdx >= dsCnt) { return VK_ERROR_OUT_OF_POOL_MEMORY; }

		bool isSpaceAvail = true;		// If not using Metal arg buffers, space will always be available.
		MVKDescriptorSet* mvkDS = &_descriptorSets[dsIdx];
		NSUInteger mtlArgBuffOffset = mvkDS->getMetalArgumentBufferOffset();

		// If the desc set is using a Metal argument buffer, we also need to see if the desc set
		// will fit in the slot that might already have been allocated for it in the Metal argument
		// buffer from a previous allocation that was returned. If this pool has been reset recently,
		// then the desc sets will not have had a Metal argument buffer allocation assigned yet.
		if (mvkDSL->isUsingMetalArgumentBuffer()) {

			// If the offset has not been set (and it's not the first desc set except
			// on a reset pool), set the offset and update the next available offset value.
			if ( !mtlArgBuffOffset && (dsIdx || !_nextMTLArgumentBufferOffset)) {
				mtlArgBuffOffset = _nextMTLArgumentBufferOffset;
				_nextMTLArgumentBufferOffset += mtlArgBuffAllocSize;
			}

			// Get the offset of the next desc set, if one exists and
			// its offset has been set, or the end of the arg buffer.
			size_t nextDSIdx = dsIdx + 1;
			NSUInteger nextOffset = (nextDSIdx < dsCnt ? _descriptorSets[nextDSIdx].getMetalArgumentBufferOffset() : 0);
			if ( !nextOffset ) { nextOffset = _mtlArgumentBuffer.length; }

			isSpaceAvail = (mtlArgBuffOffset + mtlArgBuffAllocSize) <= nextOffset;
		}

		if (isSpaceAvail) {
			mvkDS->allocate(mvkDSL, variableDescriptorCount, mtlArgBuffOffset);
			if (mvkDS->wasConfigurationSuccessful()) {
				*pVKDS = (VkDescriptorSet)mvkDS;
			} else {
				freeDescriptorSet(mvkDS, false);
			}
			return mvkDS->getConfigurationResult();
		}
		dsIdx++;	// Skip to next desc set and resume looking
	}
}

// Descriptor sets are held in contiguous memory, so the index of the returning descriptor
// set can be calculated by pointer differences, and it can be marked as available.
void MVKDescriptorPool::freeDescriptorSet(MVKDescriptorSet* mvkDS, bool isPoolReset) {
	if ( !mvkDS ) { return; }	// Vulkan allows NULL refs.

	if (mvkDS->_pool != this) { reportError(VK_ERROR_INITIALIZATION_FAILED, "A descriptor set is being returned to a descriptor pool that did not allocate it."); }

	mvkDS->free(isPoolReset);
	size_t dsIdx = mvkDS - _descriptorSets.data();
	_descriptorSetAvailablility.setBit(dsIdx);
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

MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device),
	_descriptorSets(pCreateInfo->maxSets, MVKDescriptorSet(this)),
	_descriptorSetAvailablility(pCreateInfo->maxSets, true),
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
	_storageTexelBufferDescriptors(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER),
	_inlineBlockMTLBufferAllocator(device, getMaxInlineBlockSize(device, pCreateInfo), true) {

	_mtlArgumentBuffer = nil;
	_nextMTLArgumentBufferOffset = 0;
	if (supportsMetalArgumentBuffers()) {
		NSUInteger mtlArgBuffSize = 0;
		uint32_t poolCnt = pCreateInfo->poolSizeCount;
		for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
			auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
			mtlArgBuffSize += getDescriptorByteCountForMetalArgumentBuffer(poolSize.type) * poolSize.descriptorCount;
		}
		mtlArgBuffSize += pCreateInfo->maxSets * _device->_pMetalFeatures->mtlBufferAlignment;	// Leave room for each desc set to be aligned

		// Each shader stage uses it's own arg buffer layout. As a result, we need to significantly
		// overallocate space here, since we don't yet know how the descriptor set layouts will make
		// use of the descriptors across each pipeline stage. Ideally, the same MVKMTLArgumentEncoder
		// should be used across all pipeline stages, but that doesn't seem to be possible with present
		// combination of SPIRV-Cross and Metal behaviour.
		mtlArgBuffSize *= kMVKShaderStageCount;

		if (mtlArgBuffSize) {
			_mtlArgumentBuffer = [getMTLDevice() newBufferWithLength: mtlArgBuffSize options: MTLResourceStorageModeShared];	// retained
			_mtlArgumentBuffer.label = @"Argument buffer";
		}
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

NSUInteger MVKDescriptorPool::getMaxInlineBlockSize(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo) {
	if ( !device->_pMetalFeatures->argumentBuffers || MVKInlineUniformBlockDescriptor::shouldEmbedInlineBlocksInMetalAgumentBuffer()) { return 0; }

	NSUInteger maxInlineBlockSize = 0;
	uint32_t poolCnt = pCreateInfo->poolSizeCount;
	for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
		auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
		if (poolSize.type == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
			NSUInteger iubSize = getDescriptorByteCountForMetalArgumentBuffer(poolSize.type) * poolSize.descriptorCount;
			maxInlineBlockSize = std::max(iubSize, maxInlineBlockSize);
		}
	}
	return std::min<NSUInteger>(maxInlineBlockSize, device->_pMetalFeatures->maxMTLBufferSize);
}

// Destroy all allocated descriptor sets and preallocated descriptors
MVKDescriptorPool::~MVKDescriptorPool() {
	reset(0);
	[_mtlArgumentBuffer release];
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
