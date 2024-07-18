/*
 * MVKDescriptorSet.mm
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

#include "MVKDescriptorSet.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandEncoderState.h"
#include "MVKPipeline.h"
#include "MVKInstance.h"
#include "MVKOSExtensions.h"
#include <sstream>


// The size of one Metal3 Argument Buffer slot in bytes.
static const size_t kMVKMetal3ArgBuffSlotSizeInBytes = sizeof(uint64_t);


#pragma mark -
#pragma mark MVKMetalArgumentBuffer

void MVKMetalArgumentBuffer::setArgumentBuffer(id<MTLBuffer> mtlArgBuff,
											   NSUInteger mtlArgBuffOfst,
											   id<MTLArgumentEncoder> mtlArgEnc) {
	_mtlArgumentBuffer = mtlArgBuff;
	_mtlArgumentBufferOffset = mtlArgBuffOfst;

	auto* oldArgEnc = _mtlArgumentEncoder;
	_mtlArgumentEncoder = [mtlArgEnc retain];	// retained
	[_mtlArgumentEncoder setArgumentBuffer: _mtlArgumentBuffer offset: _mtlArgumentBufferOffset];
	[oldArgEnc release];
}

void MVKMetalArgumentBuffer::setBuffer(id<MTLBuffer> mtlBuff, NSUInteger offset, uint32_t index) {
	if (_mtlArgumentEncoder) {
		[_mtlArgumentEncoder setBuffer: mtlBuff offset: offset atIndex: index];
	} else {
#if MVK_XCODE_14
		*(uint64_t*)getArgumentPointer(index) = mtlBuff.gpuAddress + offset;
#endif
	}
}

void MVKMetalArgumentBuffer::setTexture(id<MTLTexture> mtlTex, uint32_t index) {
	if (_mtlArgumentEncoder) {
		[_mtlArgumentEncoder setTexture: mtlTex atIndex: index];
	} else {
#if MVK_XCODE_14
		*(MTLResourceID*)getArgumentPointer(index) = mtlTex.gpuResourceID;
#endif
	}
}

void MVKMetalArgumentBuffer::setSamplerState(id<MTLSamplerState> mtlSamp, uint32_t index) {
	if (_mtlArgumentEncoder) {
		[_mtlArgumentEncoder setSamplerState: mtlSamp atIndex: index];
	} else {
#if MVK_XCODE_14
		*(MTLResourceID*)getArgumentPointer(index) = mtlSamp.gpuResourceID;
#endif
	}
}

// Returns the address of the slot at the index within the Metal argument buffer.
// This is based on the Metal 3 design that all arg buffer slots are 64 bits.
void* MVKMetalArgumentBuffer::getArgumentPointer(uint32_t index) const {
	return (void*)((uintptr_t)_mtlArgumentBuffer.contents + _mtlArgumentBufferOffset + (index * kMVKMetal3ArgBuffSlotSizeInBytes));
}

MVKMetalArgumentBuffer::~MVKMetalArgumentBuffer() { [_mtlArgumentEncoder release]; }


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
			dslBind.bind(cmdEncoder, pipelineBindPoint, descSet, dslMTLRezIdxOffsets, dynamicOffsets, dynamicOffsetIndex);
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
                                               VkPipelineBindPoint pipelineBindPoint,
                                               MVKArrayRef<VkWriteDescriptorSet> descriptorWrites,
                                               MVKShaderResourceBinding& dslMTLRezIdxOffsets) {

    if (!_isPushDescriptorLayout) return;

	if (!cmdEncoder) { clearConfigurationResult(); }

	auto& enabledExtns = getEnabledExtensions();
	for (const VkWriteDescriptorSet& descWrite : descriptorWrites) {
        uint32_t dstBinding = descWrite.dstBinding;
        uint32_t dstArrayElement = descWrite.dstArrayElement;
        uint32_t descriptorCount = descWrite.descriptorCount;
        const VkDescriptorImageInfo* pImageInfo = descWrite.pImageInfo;
        const VkDescriptorBufferInfo* pBufferInfo = descWrite.pBufferInfo;
        const VkBufferView* pTexelBufferView = descWrite.pTexelBufferView;
        const VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock = nullptr;
        if (enabledExtns.vk_EXT_inline_uniform_block.enabled) {
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
            _bindings[bindIdx].push(cmdEncoder, pipelineBindPoint, dstArrayElement, descriptorCount,
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
	VkPipelineBindPoint bindPoint = descUpdateTemplate->getBindPoint();
    for (uint32_t i = 0; i < descUpdateTemplate->getNumberOfEntries(); i++) {
        const VkDescriptorUpdateTemplateEntry* pEntry = descUpdateTemplate->getEntry(i);
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
            _bindings[bindIdx].push(cmdEncoder, bindPoint, dstArrayElement, descriptorCount,
                                    descriptorsPushed, pEntry->descriptorType,
                                    pEntry->stride, pCurData, dslMTLRezIdxOffsets);
            pCurData = (const char*)pCurData + pEntry->stride * descriptorsPushed;
        }
    }
}

static void populateAuxBuffer(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
							  MVKShaderStageResourceBinding buffBinding,
							  uint32_t descSetIndex,
							  uint32_t descBinding,
							  bool usingNativeTextureAtomics) {
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		mvkPopulateShaderConversionConfig(shaderConfig,
										  buffBinding,
										  MVKShaderStage(stage),
										  descSetIndex,
										  descBinding,
										  1,
										  VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
										  nullptr,
										  usingNativeTextureAtomics);
	}
}

void MVKDescriptorSetLayout::populateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
                                                            MVKShaderResourceBinding& dslMTLRezIdxOffsets,
															uint32_t descSetIndex) {
	uint32_t bindCnt = (uint32_t)_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		_bindings[bindIdx].populateShaderConversionConfig(shaderConfig, dslMTLRezIdxOffsets, descSetIndex);
	}

	// If this descriptor set is using an argument buffer, and needs a buffer size auxiliary buffer, add it.
	if (isUsingMetalArgumentBuffers() && needsBufferSizeAuxBuffer()) {
		MVKShaderStageResourceBinding buffBinding;
		buffBinding.bufferIndex = getBufferSizeBufferArgBuferIndex();
		populateAuxBuffer(shaderConfig, buffBinding, descSetIndex,
						  MVK_spirv_cross::kBufferSizeBufferBinding,
						  getMetalFeatures().nativeTextureAtomics);
	}

	// If the app is using argument buffers, but this descriptor set is 
	// not, because this is a discrete descriptor set, mark it as such.
	if(MVKDeviceTrackingMixin::isUsingMetalArgumentBuffers() && !isUsingMetalArgumentBuffers()) {
		shaderConfig.discreteDescriptorSets.push_back(descSetIndex);
	}
}

bool MVKDescriptorSetLayout::populateBindingUse(MVKBitArray& bindingUse,
												SPIRVToMSLConversionConfiguration& context,
												MVKShaderStage stage,
												uint32_t descSetIndex) {
	static const spv::ExecutionModel spvExecModels[] = {
		spv::ExecutionModelVertex,
		spv::ExecutionModelTessellationControl,
		spv::ExecutionModelTessellationEvaluation,
		spv::ExecutionModelFragment,
		spv::ExecutionModelGLCompute
	};

	bool descSetIsUsed = false;
	uint32_t bindCnt = (uint32_t)_bindings.size();
	bindingUse.resize(bindCnt);
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		auto& dslBind = _bindings[bindIdx];
		if (context.isResourceUsed(spvExecModels[stage], descSetIndex, dslBind.getBinding())) {
			bindingUse.setBit(bindIdx);
			descSetIsUsed = true;
		}
	}
	return descSetIsUsed;
}

bool MVKDescriptorSetLayout::isUsingMetalArgumentBuffers() {
	return MVKDeviceTrackingMixin::isUsingMetalArgumentBuffers() && !_isPushDescriptorLayout;
};

// Returns an autoreleased MTLArgumentDescriptor suitable for adding an auxiliary buffer to the argument buffer.
static MTLArgumentDescriptor* getAuxBufferArgumentDescriptor(uint32_t argIndex) {
	auto* argDesc = [MTLArgumentDescriptor argumentDescriptor];
	argDesc.dataType = MTLDataTypePointer;
	argDesc.access = MTLArgumentAccessReadWrite;
	argDesc.index = argIndex;
	argDesc.arrayLength = 1;
	return argDesc;
}

// Returns an autoreleased MTLArgumentEncoder for a descriptor set, or nil if not needed.
// Make sure any call to this function is wrapped in @autoreleasepool.
id <MTLArgumentEncoder> MVKDescriptorSetLayout::getMTLArgumentEncoder(uint32_t variableDescriptorCount) {
	auto* encoderArgs = [NSMutableArray arrayWithCapacity: _bindings.size() * 2];	// Double it to cover potential multi-resource descriptors (combo image/samp, multi-planar, etc).

	// Buffer sizes buffer at front
	if (needsBufferSizeAuxBuffer()) {
		[encoderArgs addObject: getAuxBufferArgumentDescriptor(getBufferSizeBufferArgBuferIndex())];
	}
	for (auto& dslBind : _bindings) {
		dslBind.addMTLArgumentDescriptors(encoderArgs, variableDescriptorCount);
	}
	return encoderArgs.count ? [[getMTLDevice() newArgumentEncoderWithArguments: encoderArgs] autorelease] : nil;
}

// Returns the encoded byte length of the resources from a descriptor set in an argument buffer.
uint64_t MVKDescriptorSetLayout::getMetal3ArgumentBufferEncodedLength(uint32_t variableDescriptorCount) {
	uint64_t encodedLen =  0;

	// Buffer sizes buffer at front
	if (needsBufferSizeAuxBuffer()) {
		encodedLen += kMVKMetal3ArgBuffSlotSizeInBytes;
	}
	for (auto& dslBind : _bindings) {
		encodedLen += dslBind.getMTLResourceCount(variableDescriptorCount) * kMVKMetal3ArgBuffSlotSizeInBytes;
	}
	return encodedLen;
}

uint32_t MVKDescriptorSetLayout::getDescriptorCount(uint32_t variableDescriptorCount) {
	uint32_t descCnt =  0;
	for (auto& dslBind : _bindings) {
		descCnt += dslBind.getDescriptorCount(variableDescriptorCount);
	}
	return descCnt;
}

MVKDescriptorSetLayout::MVKDescriptorSetLayout(MVKDevice* device,
                                               const VkDescriptorSetLayoutCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {

	_isPushDescriptorLayout = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR);

	const VkDescriptorBindingFlags* pBindingFlags = nullptr;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO: {
				auto* pDescSetLayoutBindingFlags = (VkDescriptorSetLayoutBindingFlagsCreateInfo*)next;
				if (pDescSetLayoutBindingFlags->bindingCount) {
					pBindingFlags = pDescSetLayoutBindingFlags->pBindingFlags;
				}
				break;
			}
			default:
				break;
		}
	}

	// The bindings in VkDescriptorSetLayoutCreateInfo do not need to be provided in order of binding number.
	// However, several subsequent operations, such as the dynamic offsets in vkCmdBindDescriptorSets()
	// are ordered by binding number. To prepare for this, sort the bindings by binding number.
	struct BindInfo {
		const VkDescriptorSetLayoutBinding* pBinding;
		VkDescriptorBindingFlags bindingFlags;
	};
	MVKSmallVector<BindInfo, 64> sortedBindings;

	bool needsBuffSizeAuxBuff = false;
	uint32_t bindCnt = pCreateInfo->bindingCount;
	sortedBindings.reserve(bindCnt);
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		auto* pBind = &pCreateInfo->pBindings[bindIdx];
		sortedBindings.push_back( { pBind, pBindingFlags ? pBindingFlags[bindIdx] : 0 } );
		needsBuffSizeAuxBuff = needsBuffSizeAuxBuff || mvkNeedsBuffSizeAuxBuffer(pBind);
	}
	std::sort(sortedBindings.begin(), sortedBindings.end(), [](BindInfo bindInfo1, BindInfo bindInfo2) {
		return bindInfo1.pBinding->binding < bindInfo2.pBinding->binding;
	});

	uint32_t dslDescCnt = 0;
	uint32_t dslMTLRezCnt = needsBuffSizeAuxBuff ? 1 : 0;	// If needed, leave a slot for the buffer sizes buffer at front.
	_bindings.reserve(bindCnt);
    for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		BindInfo& bindInfo = sortedBindings[bindIdx];
        _bindings.emplace_back(_device, this, bindInfo.pBinding, bindInfo.bindingFlags, dslDescCnt, dslMTLRezCnt);
		_bindingToIndex[bindInfo.pBinding->binding] = bindIdx;
	}

	MVKLogDebugIf(getMVKConfig().debugMode, "Created %s\n", getLogDescription().c_str());
}

std::string MVKDescriptorSetLayout::getLogDescription() {
	std::stringstream descStr;
	descStr << "VkDescriptorSetLayout " << this << " with " << _bindings.size() << " bindings:";
	for (auto& dlb : _bindings) {
		descStr << "\n\t" << dlb.getLogDescription();
	}
	return descStr.str();
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
							 size_t srcStride,
							 const void* pData) {

	MVKDescriptorSetLayoutBinding* mvkDSLBind = _layout->getBinding(pDescriptorAction->dstBinding);
	VkDescriptorType descType = mvkDSLBind->getDescriptorType();
	if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		// For inline buffers dstArrayElement is a byte offset
		uint32_t descIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding);
		_descriptors[descIdx]->write(mvkDSLBind, this, pDescriptorAction->dstArrayElement, 0, srcStride, pData);
	} else {
		uint32_t descStartIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding, pDescriptorAction->dstArrayElement);
		uint32_t dstStartIdx = pDescriptorAction->dstArrayElement;
		uint32_t elemCnt = std::min(pDescriptorAction->descriptorCount, (uint32_t)_descriptors.size() - descStartIdx);
		for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
			uint32_t descIdx = descStartIdx + elemIdx;
			_descriptors[descIdx]->write(mvkDSLBind, this, dstStartIdx + elemIdx, elemIdx, srcStride, pData);
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
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		// For inline buffers srcArrayElement is a byte offset
		MVKDescriptor* mvkDesc = getDescriptor(pDescriptorCopy->srcBinding);
		if (mvkDesc->getDescriptorType() == descType) {
			mvkDesc->read(mvkDSLBind, this, pDescriptorCopy->srcArrayElement, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
		}
    } else {
        uint32_t srcStartIdx = _layout->getDescriptorIndex(pDescriptorCopy->srcBinding, pDescriptorCopy->srcArrayElement);
		uint32_t descCnt = std::min(pDescriptorCopy->descriptorCount, (uint32_t)_descriptors.size() - srcStartIdx);
        for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
			MVKDescriptor* mvkDesc = _descriptors[srcStartIdx + descIdx];
			if (mvkDesc->getDescriptorType() == descType) {
				mvkDesc->read(mvkDSLBind, this, descIdx, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
			}
        }
    }
}

MVKMTLBufferAllocation* MVKDescriptorSet::acquireMTLBufferRegion(NSUInteger length) {
	return _pool->_mtlBufferAllocator.acquireMTLBufferRegion(length);
}

VkResult MVKDescriptorSet::allocate(MVKDescriptorSetLayout* layout,
									uint32_t variableDescriptorCount,
									NSUInteger mtlArgBufferOffset,
									id<MTLArgumentEncoder> mtlArgEnc) {
	_layout = layout;
	_variableDescriptorCount = variableDescriptorCount;
	_argumentBuffer.setArgumentBuffer(_pool->_metalArgumentBuffer, mtlArgBufferOffset, mtlArgEnc);

	uint32_t descCnt = layout->getDescriptorCount(variableDescriptorCount);
	_descriptors.reserve(descCnt);

	uint32_t bindCnt = (uint32_t)layout->_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		MVKDescriptorSetLayoutBinding* mvkDSLBind = &layout->_bindings[bindIdx];
		uint32_t elemCnt = mvkDSLBind->getDescriptorCount(variableDescriptorCount);
		for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
			VkDescriptorType descType = mvkDSLBind->getDescriptorType();
			MVKDescriptor* mvkDesc = nullptr;
			setConfigurationResult(_pool->allocateDescriptor(descType, &mvkDesc));
			if ( !wasConfigurationSuccessful() ) { return getConfigurationResult(); }
			if (mvkDesc->usesDynamicBufferOffsets()) { _dynamicOffsetDescriptorCount++; }
			_descriptors.push_back(mvkDesc);
		}
		mvkDSLBind->encodeImmutableSamplersToMetalArgumentBuffer(this);
	}

	// If needed, allocate a MTLBuffer to track buffer sizes, and add it to the argument buffer.
	if (hasMetalArgumentBuffer() && _layout->needsBufferSizeAuxBuffer()) {
		uint32_t buffSizesSlotCount = _layout->_maxBufferIndex + 1;
		_bufferSizesBuffer = acquireMTLBufferRegion(buffSizesSlotCount * sizeof(uint32_t));
		_argumentBuffer.setBuffer(_bufferSizesBuffer->_mtlBuffer,
								  _bufferSizesBuffer->_offset,
								  _layout->getBufferSizeBufferArgBuferIndex());
	}

	return getConfigurationResult();
}

void MVKDescriptorSet::free(bool isPoolReset) {
	_layout = nullptr;
	_dynamicOffsetDescriptorCount = 0;
	_variableDescriptorCount = 0;

	if (isPoolReset) { _argumentBuffer.setArgumentBuffer(_pool->_metalArgumentBuffer, 0, nil); }

	// Pooled descriptors don't need to be individually freed under pool resets.
	if ( !(_pool->_hasPooledDescriptors && isPoolReset) ) {
		for (auto mvkDesc : _descriptors) { _pool->freeDescriptor(mvkDesc); }
	}
	_descriptors.clear();
	_descriptors.shrink_to_fit();

	if (_bufferSizesBuffer) {
		_bufferSizesBuffer->returnToPool();
		_bufferSizesBuffer = nullptr;
	}

	clearConfigurationResult();
}

void MVKDescriptorSet::setBufferSize(uint32_t descIdx, uint32_t value) {
	if (_bufferSizesBuffer) {
		*(uint32_t*)((uintptr_t)_bufferSizesBuffer->getContents() + (descIdx * sizeof(uint32_t))) = value;
	}
}

void MVKDescriptorSet::encodeAuxBufferUsage(MVKResourcesCommandEncoderState* rezEncState, MVKShaderStage stage) {
	if (_bufferSizesBuffer) {
		MTLRenderStages mtlRendStages = MTLRenderStageVertex | MTLRenderStageFragment;
		rezEncState->encodeResourceUsage(stage, _bufferSizesBuffer->_mtlBuffer, MTLResourceUsageRead, mtlRendStages);
	}
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
	const uint32_t* pVarDescCounts = nullptr;
	for (const auto* next = (VkBaseInStructure*)pAllocateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO: {
				auto* pVarDescSetVarCounts = (VkDescriptorSetVariableDescriptorCountAllocateInfo*)next;
				pVarDescCounts = pVarDescSetVarCounts->descriptorSetCount ? pVarDescSetVarCounts->pDescriptorCounts : nullptr;
			}
			default:
				break;
		}
	}

	@autoreleasepool {
		for (uint32_t dsIdx = 0; dsIdx < pAllocateInfo->descriptorSetCount; dsIdx++) {
			MVKDescriptorSetLayout* mvkDSL = (MVKDescriptorSetLayout*)pAllocateInfo->pSetLayouts[dsIdx];
			if ( !mvkDSL->_isPushDescriptorLayout ) {
				VkResult rslt = allocateDescriptorSet(mvkDSL, (pVarDescCounts ? pVarDescCounts[dsIdx] : 0), &pDescriptorSets[dsIdx]);
				if (rslt) { return rslt; }
			}
		}
	}

	return VK_SUCCESS;
}

// Retrieves the first available descriptor set from the pool, and configures it.
// If none are available, returns an error.
VkResult MVKDescriptorPool::allocateDescriptorSet(MVKDescriptorSetLayout* mvkDSL,
												  uint32_t variableDescriptorCount,
												  VkDescriptorSet* pVKDS) {
	VkResult rslt = VK_ERROR_OUT_OF_POOL_MEMORY;
	uint64_t mtlArgBuffEncSize = 0;
	id<MTLArgumentEncoder> mtlArgEnc = nil;
	if (mvkDSL->isUsingMetalArgumentBuffers()) {
		if (needsMetalArgumentBufferEncoders()) {
			mtlArgEnc = mvkDSL->getMTLArgumentEncoder(variableDescriptorCount);
			mtlArgBuffEncSize = mtlArgEnc.encodedLength;
		} else {
			mtlArgBuffEncSize = mvkDSL->getMetal3ArgumentBufferEncodedLength(variableDescriptorCount);
		}
	}
	uint64_t mtlArgBuffEncAlignedSize = mvkAlignByteCount(mtlArgBuffEncSize, getMetalFeatures().mtlBufferAlignment);

	size_t dsCnt = _descriptorSetAvailablility.size();
	_descriptorSetAvailablility.enumerateEnabledBits(true, [&](size_t dsIdx) {
		bool isSpaceAvail = true;		// If not using Metal arg buffers, space will always be available.
		MVKDescriptorSet* mvkDS = &_descriptorSets[dsIdx];
		NSUInteger mtlArgBuffOffset = mvkDS->getMetalArgumentBuffer().getMetalArgumentBufferOffset();

		// If the desc set is using a Metal argument buffer, we also need to see if the desc set
		// will fit in the slot that might already have been allocated for it in the Metal argument
		// buffer from a previous allocation that was returned. If this pool has been reset recently,
		// then the desc sets will not have had a Metal argument buffer allocation assigned yet.
		if (mtlArgBuffEncSize) {

			// If the offset has not been set (and it's not the first desc set except
			// on a reset pool), set the offset and update the next available offset value.
			if ( !mtlArgBuffOffset && (dsIdx || !_nextMetalArgumentBufferOffset)) {
				mtlArgBuffOffset = _nextMetalArgumentBufferOffset;
				_nextMetalArgumentBufferOffset += mtlArgBuffEncAlignedSize;
			}

			// Get the offset of the next desc set, if one exists and
			// its offset has been set, or the end of the arg buffer.
			size_t nextDSIdx = dsIdx + 1;
			NSUInteger nextOffset = (nextDSIdx < dsCnt ? _descriptorSets[nextDSIdx].getMetalArgumentBuffer().getMetalArgumentBufferOffset() : 0);
			if ( !nextOffset ) { nextOffset = _metalArgumentBuffer.length; }

			isSpaceAvail = (mtlArgBuffOffset + mtlArgBuffEncSize) <= nextOffset;
		}

		if (isSpaceAvail) {
			rslt = mvkDS->allocate(mvkDSL, variableDescriptorCount, mtlArgBuffOffset, mtlArgEnc);
			if (rslt) {
				freeDescriptorSet(mvkDS, false);
			} else {
				*pVKDS = (VkDescriptorSet)mvkDS;
			}
			return false;
		} else {
			_descriptorSetAvailablility.setBit(dsIdx);	// We didn't consume this one after all, so it's still available
			return true;
		}
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

// Free allocated descriptor sets and reset descriptor pools.
// Don't waste time freeing desc sets that were never allocated.
VkResult MVKDescriptorPool::reset(VkDescriptorPoolResetFlags flags) {
	size_t dsCnt = _descriptorSetAvailablility.getLowestNeverClearedBitIndex();
	for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
		freeDescriptorSet(&_descriptorSets[dsIdx], true);
	}
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

	_nextMetalArgumentBufferOffset = 0;

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
// For descriptors of the VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT type,
// we accumulate the count via the pNext chain.
size_t MVKDescriptorPool::getPoolSize(const VkDescriptorPoolCreateInfo* pCreateInfo,
									  VkDescriptorType descriptorType) {

	if ( !_hasPooledDescriptors ) { return 0; }

	uint32_t descCnt = 0;
	if (descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_INLINE_UNIFORM_BLOCK_CREATE_INFO_EXT: {
					auto* pDescPoolInlineBlockCreateInfo = (VkDescriptorPoolInlineUniformBlockCreateInfoEXT*)next;
					descCnt += pDescPoolInlineBlockCreateInfo->maxInlineUniformBlockBindings;
					break;
				}
				default:
					break;
			}
		}
	} else {
		for (uint32_t poolIdx = 0; poolIdx < pCreateInfo->poolSizeCount; poolIdx++) {
			auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
			if (poolSize.type == descriptorType) { descCnt += poolSize.descriptorCount; }
		}
	}
	return descCnt;
}

std::string MVKDescriptorPool::getLogDescription() {
	std::stringstream descStr;
	descStr << "VkDescriptorPool " << this << " with " << _descriptorSetAvailablility.size() << " descriptor sets, and descriptors:";
	descStr << "\n\tVK_DESCRIPTOR_TYPE_UNIFORM_BUFFER: "           << _uniformBufferDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_STORAGE_BUFFER: "           << _storageBufferDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC: "   << _uniformBufferDynamicDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: "   << _storageBufferDynamicDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: " << _inlineUniformBlockDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_SAMPLED_IMAGE: "            << _sampledImageDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_STORAGE_IMAGE: "            << _storageImageDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT: "         << _inputAttachmentDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_SAMPLER: "                  << _samplerDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: "   << _combinedImageSamplerDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER: "     << _uniformTexelBufferDescriptors._availability.size();
	descStr << "\n\tVK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER: "     << _storageTexelBufferDescriptors._availability.size();
	return descStr.str();
}

MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device),
    _hasPooledDescriptors(getMVKConfig().preallocateDescriptors),		// Set this first! Accessed by MVKDescriptorSet constructor and getPoolSize() in following lines.
	_descriptorSets(pCreateInfo->maxSets, MVKDescriptorSet(this)),
	_descriptorSetAvailablility(pCreateInfo->maxSets, true),
	_mtlBufferAllocator(_device, getMetalFeatures().maxMTLBufferSize, true),
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
    _storageTexelBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER)) {

		initMetalArgumentBuffer(pCreateInfo);
		MVKLogDebugIf(getMVKConfig().debugMode, "Created %s\n", getLogDescription().c_str());
	}

void MVKDescriptorPool::initMetalArgumentBuffer(const VkDescriptorPoolCreateInfo* pCreateInfo) {
	_metalArgumentBuffer = nil;
	_nextMetalArgumentBufferOffset = 0;

	if ( !isUsingMetalArgumentBuffers() ) { return; }

	auto& mtlFeats = getMetalFeatures();
	@autoreleasepool {
		NSUInteger mtlBuffCnt = 0;
		NSUInteger mtlTexCnt = 0;
		NSUInteger mtlSampCnt = 0;

		uint32_t poolCnt = pCreateInfo->poolSizeCount;
		for (uint32_t poolIdx = 0; poolIdx < poolCnt; poolIdx++) {
			auto& poolSize = pCreateInfo->pPoolSizes[poolIdx];
			switch (poolSize.type) {
				// VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT counts handled separately below
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
					mtlBuffCnt += poolSize.descriptorCount;
					break;

				case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
				case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
				case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
					mtlTexCnt += poolSize.descriptorCount;
					break;

				case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
				case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
					mtlTexCnt += poolSize.descriptorCount;
					if (!getMetalFeatures().nativeTextureAtomics)
						mtlBuffCnt += poolSize.descriptorCount;
					break;

				case VK_DESCRIPTOR_TYPE_SAMPLER:
					mtlSampCnt += poolSize.descriptorCount;
					break;

				case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
					mtlTexCnt += poolSize.descriptorCount;
					mtlSampCnt += poolSize.descriptorCount;
					break;

				default:
					break;
			}
		}

		// VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT counts pulled separately
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_INLINE_UNIFORM_BLOCK_CREATE_INFO_EXT: {
					auto* pDescPoolInlineBlockCreateInfo = (VkDescriptorPoolInlineUniformBlockCreateInfoEXT*)next;
					mtlBuffCnt += pDescPoolInlineBlockCreateInfo->maxInlineUniformBlockBindings;
					break;
				}
				default:
					break;
			}
		}

		// To support the SPIR-V OpArrayLength operation, for each descriptor set that 
		// contain buffers, we add an additional buffer at the end to track buffer sizes.
		mtlBuffCnt += std::min<NSUInteger>(mtlBuffCnt, pCreateInfo->maxSets);

		// Each descriptor set uses a separate Metal argument buffer, but all of these
		// descriptor set Metal argument buffers share a single MTLBuffer. This single
		// MTLBuffer needs to be large enough to hold all of the encoded resources for the
		// descriptors, plus additional buffer offset alignment space for each descriptor set.
		NSUInteger metalArgBuffSize = 0;
		if (needsMetalArgumentBufferEncoders()) {
			// If argument buffer encoders are required, depending on the platform, a Metal argument
			// buffer may have a fixed overhead storage, in addition to the storage required to hold
			// the resources. This overhead per descriptor set is conservatively calculated by measuring
			// the size of a Metal argument buffer containing one of each type of resource (S1), and
			// the size of a Metal argument buffer containing two of each type of resource (S2), and
			// then calculating the fixed overhead per argument buffer as (2 * S1 - S2). To this is
			// added the overhead due to the alignment of each descriptor set Metal argument buffer offset.
			NSUInteger overheadPerDescSet = (2 * getMetalArgumentBufferEncodedResourceStorageSize(1, 1, 1) -
											 getMetalArgumentBufferEncodedResourceStorageSize(2, 2, 2) +
											 mtlFeats.mtlBufferAlignment);

			// Measure the size of an argument buffer that would hold all of the encoded resources
			// managed in this pool, then add any overhead for all the descriptor sets.
			metalArgBuffSize = getMetalArgumentBufferEncodedResourceStorageSize(mtlBuffCnt, mtlTexCnt, mtlSampCnt);
			metalArgBuffSize += (overheadPerDescSet * (pCreateInfo->maxSets - 1));	// metalArgBuffSize already includes overhead for one descriptor set
		} else {
			// For Metal 3, encoders are not required, and each arg buffer entry fits into 64 bits.
			metalArgBuffSize = (mtlBuffCnt + mtlTexCnt + mtlSampCnt) * kMVKMetal3ArgBuffSlotSizeInBytes;
			metalArgBuffSize += (mtlFeats.mtlBufferAlignment * pCreateInfo->maxSets);
		}

		if (metalArgBuffSize) {
			NSUInteger maxMTLBuffSize = mtlFeats.maxMTLBufferSize;
			if (metalArgBuffSize > maxMTLBuffSize) {
				setConfigurationResult(reportError(VK_ERROR_FRAGMENTATION, "vkCreateDescriptorPool(): The requested descriptor storage of %d MB is larger than the maximum descriptor storage of %d MB per VkDescriptorPool.", (uint32_t)(metalArgBuffSize / MEBI), (uint32_t)(maxMTLBuffSize / MEBI)));
				metalArgBuffSize = maxMTLBuffSize;
			}
			_metalArgumentBuffer = [getMTLDevice() newBufferWithLength: metalArgBuffSize options: MTLResourceStorageModeShared];	// retained
			_metalArgumentBuffer.label = @"Descriptor set argument buffer";
		}
	}
}

// Returns the size of a Metal argument buffer containing the number of various types
// of encoded resources. This is only required if argument buffers are required.
// Make sure any call to this function is wrapped in @autoreleasepool.
NSUInteger MVKDescriptorPool::getMetalArgumentBufferEncodedResourceStorageSize(NSUInteger bufferCount,
																			   NSUInteger textureCount,
																			   NSUInteger samplerCount) {
	NSMutableArray<MTLArgumentDescriptor*>* args = [NSMutableArray arrayWithCapacity: 3];

	NSUInteger argIdx = 0;
	[args addObject: getMTLArgumentDescriptor(MTLDataTypePointer, argIdx, bufferCount)];
	argIdx += bufferCount;
	[args addObject: getMTLArgumentDescriptor(MTLDataTypeTexture, argIdx, textureCount)];
	argIdx += textureCount;
	[args addObject: getMTLArgumentDescriptor(MTLDataTypeSampler, argIdx, samplerCount)];
	argIdx += samplerCount;

	id<MTLArgumentEncoder> argEnc = [getMTLDevice() newArgumentEncoderWithArguments: args];
	NSUInteger metalArgBuffSize = argEnc.encodedLength;
	[argEnc release];

	return metalArgBuffSize;
}

// Returns a MTLArgumentDescriptor of a particular type.
// To be conservative, use some worse-case values, in case content makes a difference in argument size.
MTLArgumentDescriptor* MVKDescriptorPool::getMTLArgumentDescriptor(MTLDataType resourceType, NSUInteger argIndex, NSUInteger count) {
	auto* argDesc = [MTLArgumentDescriptor argumentDescriptor];
	argDesc.dataType = resourceType;
	argDesc.access = MTLArgumentAccessReadWrite;
	argDesc.index = argIndex;
	argDesc.arrayLength = count;
	argDesc.textureType = MTLTextureTypeCubeArray;
	return argDesc;
}

MVKDescriptorPool::~MVKDescriptorPool() {
	reset(0);
	[_metalArgumentBuffer release];
	_metalArgumentBuffer = nil;
}


#pragma mark -
#pragma mark MVKDescriptorUpdateTemplate

const VkDescriptorUpdateTemplateEntry* MVKDescriptorUpdateTemplate::getEntry(uint32_t n) const {
	return &_entries[n];
}

uint32_t MVKDescriptorUpdateTemplate::getNumberOfEntries() const {
	return (uint32_t)_entries.size();
}

VkDescriptorUpdateTemplateType MVKDescriptorUpdateTemplate::getType() const {
	return _type;
}

MVKDescriptorUpdateTemplate::MVKDescriptorUpdateTemplate(MVKDevice* device,
														 const VkDescriptorUpdateTemplateCreateInfo* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device), _pipelineBindPoint(pCreateInfo->pipelineBindPoint), _type(pCreateInfo->templateType) {

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
		if (dstSet->getEnabledExtensions().vk_EXT_inline_uniform_block.enabled) {
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
		inlineUniformBlock.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK_EXT;
		inlineUniformBlock.pNext = nullptr;
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
										VkDescriptorUpdateTemplate updateTemplate,
										const void* pData) {

	MVKDescriptorSet* dstSet = (MVKDescriptorSet*)descriptorSet;
	MVKDescriptorUpdateTemplate* pTemplate = (MVKDescriptorUpdateTemplate*)updateTemplate;

	if (pTemplate->getType() != VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET)
		return;

	// Perform the updates
	for (uint32_t i = 0; i < pTemplate->getNumberOfEntries(); i++) {
		const VkDescriptorUpdateTemplateEntry* pEntry = pTemplate->getEntry(i);
		const void* pCurData = (const char*)pData + pEntry->offset;

		// For inline block, wrap the raw data in in inline update struct.
		VkWriteDescriptorSetInlineUniformBlockEXT inlineUniformBlock;
		if (pEntry->descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
			inlineUniformBlock.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK_EXT;
			inlineUniformBlock.pNext = nullptr;
			inlineUniformBlock.pData = pCurData;
			inlineUniformBlock.dataSize = pEntry->descriptorCount;
			pCurData = &inlineUniformBlock;
		}
		dstSet->write(pEntry, pEntry->stride, pCurData);
	}
}
