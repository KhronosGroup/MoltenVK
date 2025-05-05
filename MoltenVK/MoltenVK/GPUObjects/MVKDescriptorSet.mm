/*
 * MVKDescriptorSet.mm
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
											   NSUInteger mtlArgBuffEncSize,
											   id<MTLArgumentEncoder> mtlArgEnc) {
	_mtlArgumentBuffer = mtlArgBuff;
	_mtlArgumentBufferOffset = mtlArgBuffOfst;
	_mtlArgumentBufferEncodedSize = mtlArgBuffEncSize;

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
                                      const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock,
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

    case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
        pData = pInlineUniformBlock;
        stride = sizeof(VkWriteDescriptorSetInlineUniformBlock);
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

	for (const VkWriteDescriptorSet& descWrite : descriptorWrites) {
        uint32_t dstBinding = descWrite.dstBinding;
        uint32_t dstArrayElement = descWrite.dstArrayElement;
        uint32_t descriptorCount = descWrite.descriptorCount;
        const VkDescriptorImageInfo* pImageInfo = descWrite.pImageInfo;
        const VkDescriptorBufferInfo* pBufferInfo = descWrite.pBufferInfo;
        const VkBufferView* pTexelBufferView = descWrite.pTexelBufferView;
        const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock = nullptr;
		for (const auto* next = (VkBaseInStructure*)descWrite.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
					break;
				}
				default:
					break;
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
        descUpdateTemplate->getType() != VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS)
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
						  SPIRV_CROSS_NAMESPACE::kBufferSizeBufferBinding,
						  getMetalFeatures().nativeTextureAtomics);
	}

	// If the app is using argument buffers, but this descriptor set is 
	// not, because this is a discrete descriptor set, mark it as such.
	if(MVKDeviceTrackingMixin::isUsingMetalArgumentBuffers() && !isUsingMetalArgumentBuffers()) {
		shaderConfig.discreteDescriptorSets.push_back(descSetIndex);
	}
}

bool MVKDescriptorSetLayout::populateBindingUse(MVKBitArray& bindingUse,
                                                mvk::SPIRVToMSLConversionConfiguration& context,
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
			bindingUse.enableBit(bindIdx);
			descSetIsUsed = true;
		}
	}
	return descSetIsUsed;
}

bool MVKDescriptorSetLayout::isUsingMetalArgumentBuffers() {
	return MVKDeviceTrackingMixin::isUsingMetalArgumentBuffers() && _canUseMetalArgumentBuffer;
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
size_t MVKDescriptorSetLayout::getMetal3ArgumentBufferEncodedLength(uint32_t variableDescriptorCount) {
	size_t encodedLen =  0;

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

MVKDescriptorSetLayoutBinding* MVKDescriptorSetLayout::getBinding(uint32_t binding, uint32_t bindingIndexOffset) {
	auto itr = _bindingToIndex.find(binding);
	if (itr != _bindingToIndex.end()) {
		uint32_t bindIdx = itr->second + bindingIndexOffset;
		if (bindIdx < _bindings.size()) {
			return &_bindings[bindIdx];
		}
	}
	return nullptr;
}

MVKDescriptorSetLayout::MVKDescriptorSetLayout(MVKDevice* device,
                                               const VkDescriptorSetLayoutCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
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

	_isPushDescriptorLayout = mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT);
	_canUseMetalArgumentBuffer = checkCanUseArgumentBuffers(pCreateInfo);	// After _isPushDescriptorLayout

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

	// Create bindings. Must be done after _isPushDescriptorLayout & _canUseMetalArgumentBuffer are set.
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

std::string MVKDescriptorSetLayout::getLogDescription(std::string indent) {
	std::stringstream descStr;
	descStr << "VkDescriptorSetLayout with " << _bindings.size() << " bindings:";
	auto bindIndent = indent + "\t";
	for (auto& dlb : _bindings) {
		descStr << "\n" << bindIndent << dlb.getLogDescription(bindIndent);
	}
	return descStr.str();
}

// Check if argument buffers can be used, and return findings.
// Must be called after setting _isPushDescriptorLayout.
bool MVKDescriptorSetLayout::checkCanUseArgumentBuffers(const VkDescriptorSetLayoutCreateInfo* pCreateInfo) {

// iOS Tier 1 argument buffers do not support writable images.
#if MVK_IOS_OR_TVOS
	if (getMetalFeatures().argumentBuffersTier < MTLArgumentBuffersTier2) {
		for (uint32_t bindIdx = 0; bindIdx < pCreateInfo->bindingCount; bindIdx++) {
			switch (pCreateInfo->pBindings[bindIdx].descriptorType) {
				case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
				case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
					return false;
				default:
					break;
			}
		}
	}
#endif

	return !_isPushDescriptorLayout;	// Push descriptors don't use argument buffers
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

	auto* mvkDSLBind = _layout->getBinding(pDescriptorAction->dstBinding);
	if (mvkDSLBind->getDescriptorType() == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
		// For inline buffers, descriptorCount is a byte count and dstArrayElement is a byte offset.
		// If needed, Vulkan allows updates to extend into subsequent bindings that are of the same type,
		// so iterate layout bindings and their associated descriptors, until all bytes are updated.
		const auto* pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)pData;
		uint32_t numBytesToCopy = pDescriptorAction->descriptorCount;
		uint32_t dstOffset = pDescriptorAction->dstArrayElement;
		uint32_t srcOffset = 0;
		while (mvkDSLBind && numBytesToCopy > 0 && srcOffset < pInlineUniformBlock->dataSize) {
			auto* mvkDesc = (MVKInlineUniformBlockDescriptor*)_descriptors[mvkDSLBind->_descriptorIndex];
			auto numBytesMoved = mvkDesc->writeBytes(mvkDSLBind, this, dstOffset, srcOffset, numBytesToCopy, pInlineUniformBlock);
			numBytesToCopy -= numBytesMoved;
			dstOffset = 0;
			srcOffset += numBytesMoved;
			mvkDSLBind = _layout->getBinding(mvkDSLBind->getBinding(), 1);	// Next binding if needed
		}
	} else {
		// We don't test against the descriptor count of the binding, because Vulkan allows
		// updates to extend into subsequent bindings that are of the same type, if needed.
		uint32_t srcElemIdx = 0;
		uint32_t dstElemIdx = pDescriptorAction->dstArrayElement;
		uint32_t descIdx = _layout->getDescriptorIndex(pDescriptorAction->dstBinding, dstElemIdx);
		uint32_t descCnt = pDescriptorAction->descriptorCount;
		while (srcElemIdx < descCnt) {
			_descriptors[descIdx++]->write(mvkDSLBind, this, dstElemIdx++, srcElemIdx++, srcStride, pData);
		}
	}
}

void MVKDescriptorSet::read(const VkCopyDescriptorSet* pDescriptorCopy,
							VkDescriptorImageInfo* pImageInfo,
							VkDescriptorBufferInfo* pBufferInfo,
							VkBufferView* pTexelBufferView,
							VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {

	MVKDescriptorSetLayoutBinding* mvkDSLBind = _layout->getBinding(pDescriptorCopy->srcBinding);
	VkDescriptorType descType = mvkDSLBind->getDescriptorType();
    if (descType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
		// For inline buffers, descriptorCount is a byte count and dstArrayElement is a byte offset.
		// If needed, Vulkan allows updates to extend into subsequent bindings that are of the same type,
		// so iterate layout bindings and their associated descriptors, until all bytes are updated.
		uint32_t numBytesToCopy = pDescriptorCopy->descriptorCount;
		uint32_t dstOffset = 0;
		uint32_t srcOffset = pDescriptorCopy->srcArrayElement;
		while (mvkDSLBind && numBytesToCopy > 0 && dstOffset < pInlineUniformBlock->dataSize) {
			auto* mvkDesc = (MVKInlineUniformBlockDescriptor*)_descriptors[mvkDSLBind->_descriptorIndex];
			auto numBytesMoved = mvkDesc->readBytes(mvkDSLBind, this, dstOffset, srcOffset, numBytesToCopy, pInlineUniformBlock);
			numBytesToCopy -= numBytesMoved;
			dstOffset += numBytesMoved;
			srcOffset = 0;
			mvkDSLBind = _layout->getBinding(mvkDSLBind->getBinding(), 1);	// Next binding if needed
		}
    } else {
		// We don't test against the descriptor count of the binding, because Vulkan allows
		// updates to extend into subsequent bindings that are of the same type, if needed.
		uint32_t srcElemIdx = pDescriptorCopy->srcArrayElement;
		uint32_t dstElemIdx = 0;
		uint32_t descIdx = _layout->getDescriptorIndex(pDescriptorCopy->srcBinding, srcElemIdx);
		uint32_t descCnt = pDescriptorCopy->descriptorCount;
		while (dstElemIdx < descCnt) {
			_descriptors[descIdx++]->read(mvkDSLBind, this, dstElemIdx++, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
		}
    }
}

MVKMTLBufferAllocation* MVKDescriptorSet::acquireMTLBufferRegion(NSUInteger length) {
	return _pool->_mtlBufferAllocator.acquireMTLBufferRegion(length);
}

VkResult MVKDescriptorSet::allocate(MVKDescriptorSetLayout* layout,
									uint32_t variableDescriptorCount,
									NSUInteger mtlArgBuffOffset,
									NSUInteger mtlArgBuffEncSize,
									id<MTLArgumentEncoder> mtlArgEnc) {
	_layout = layout;
	_layout->retain();
	_variableDescriptorCount = variableDescriptorCount;
	_argumentBuffer.setArgumentBuffer(_pool->_metalArgumentBuffer, mtlArgBuffOffset, mtlArgBuffEncSize, mtlArgEnc);

	uint32_t descCnt = layout->getDescriptorCount(variableDescriptorCount);
	_descriptors.reserve(descCnt);

	uint32_t bindCnt = (uint32_t)layout->_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		MVKDescriptorSetLayoutBinding* mvkDSLBind = &layout->_bindings[bindIdx];
		uint32_t elemCnt = mvkDSLBind->getDescriptorCount(variableDescriptorCount);
		for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
			VkDescriptorType descType = mvkDSLBind->getDescriptorType();
			MVKDescriptor* mvkDesc = nullptr;
			bool dynamicAllocation = true;
			setConfigurationResult(_pool->allocateDescriptor(descType, &mvkDesc, dynamicAllocation));	// Modifies dynamicAllocation.
			if (dynamicAllocation) { _allDescriptorsAreFromPool = false; }
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
	if(_layout) { _layout->release(); }
	_layout = nullptr;
	_dynamicOffsetDescriptorCount = 0;
	_variableDescriptorCount = 0;

	if (isPoolReset) { _argumentBuffer.setArgumentBuffer(_pool->_metalArgumentBuffer, 0, 0, nil); }

	// If this is a pool reset, and all desciptors are from the pool, we don't need to free them.
	if ( !(isPoolReset && _allDescriptorsAreFromPool) ) {
		for (auto mvkDesc : _descriptors) { _pool->freeDescriptor(mvkDesc); }
	}
	_descriptors.clear();
	_descriptors.shrink_to_fit();
	_allDescriptorsAreFromPool = true;

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

MVKDescriptorSet::~MVKDescriptorSet() {
	if(_layout) { _layout->release(); }
}


#pragma mark -
#pragma mark MVKDescriptorTypePool

// Find the next availalble descriptor in the pool. or if the pool is exhausted, optionally create one on the fly.
// The dynamicAllocation parameter is both an input and output parameter. Incoming, dynamicAllocation indicates that,
// if there are no more descriptors in this pool, a new descriptor should be created and returned.
// On return, dynamicAllocation indicates back to the caller whether a descriptor was dynamically created.
// If a descriptor could not be found in the pool and was not created dynamically, a null descriptor is returned.
template<class DescriptorClass>
VkResult MVKDescriptorTypePool<DescriptorClass>::allocateDescriptor(VkDescriptorType descType,
																	MVKDescriptor** pMVKDesc,
																	bool& dynamicAllocation,
																	MVKDescriptorPool* pool) {
	VkResult errRslt = VK_ERROR_OUT_OF_POOL_MEMORY;
	size_t availDescIdx = _availability.getIndexOfFirstEnabledBit();
	if (availDescIdx < size()) {
		_availability.disableBit(availDescIdx);		// Mark the descriptor as taken
		*pMVKDesc = &_descriptors[availDescIdx];
		(*pMVKDesc)->reset();						// Reset descriptor before reusing.
		dynamicAllocation = false;
		return VK_SUCCESS;
	} else if (dynamicAllocation) {
		*pMVKDesc = new DescriptorClass();
		reportWarning(errRslt, "VkDescriptorPool exhausted pool of %zu %s descriptors. Allocating descriptor dynamically.", size(), mvkVkDescriptorTypeName(descType));
		return VK_SUCCESS;
	} else {
		*pMVKDesc = nullptr;
		dynamicAllocation = false;
		return reportError(errRslt, "VkDescriptorPool exhausted pool of %zu %s descriptors.", size(), mvkVkDescriptorTypeName(descType));
	}
}

// If the descriptor is from the pool, mark it as available, otherwise destroy it.
// Pooled descriptors are held in contiguous memory, so the index of the returning
// descriptor can be calculated by typed pointer differences. The descriptor will
// be reset when it is re-allocated. This streamlines a pool reset().
template<typename DescriptorClass>
void MVKDescriptorTypePool<DescriptorClass>::freeDescriptor(MVKDescriptor* mvkDesc,
															MVKDescriptorPool* pool) {
	DescriptorClass* pDesc = (DescriptorClass*)mvkDesc;
	DescriptorClass* pFirstDesc = _descriptors.data();
	int64_t descIdx = pDesc >= pFirstDesc ? pDesc - pFirstDesc : pFirstDesc - pDesc;
	if (descIdx >= 0 && descIdx < size()) {
		_availability.enableBit(descIdx);
	} else {
		mvkDesc->destroy();
	}
}

// Preallocated descriptors will be reset when they are reused
template<typename DescriptorClass>
void MVKDescriptorTypePool<DescriptorClass>::reset() {
	_availability.enableAllBits();
}

template<typename DescriptorClass>
size_t MVKDescriptorTypePool<DescriptorClass>::getRemainingDescriptorCount() {
	size_t enabledCount = 0;
	_availability.enumerateEnabledBits([&](size_t bitIdx) { enabledCount++; return true; });
	return enabledCount;
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
		auto dsCnt = pAllocateInfo->descriptorSetCount;
		for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
			MVKDescriptorSetLayout* mvkDSL = (MVKDescriptorSetLayout*)pAllocateInfo->pSetLayouts[dsIdx];
			if ( !mvkDSL->_isPushDescriptorLayout ) {
				VkResult rslt = allocateDescriptorSet(mvkDSL, (pVarDescCounts ? pVarDescCounts[dsIdx] : 0), &pDescriptorSets[dsIdx]);
				if (rslt) {
					// Per Vulkan spec, if any descriptor set allocation fails, free any successful
					// allocations, and populate all descriptor set pointers with VK_NULL_HANDLE.
					freeDescriptorSets(dsIdx, pDescriptorSets);
					for (uint32_t i = 0; i < dsCnt; i++) { pDescriptorSets[i] = VK_NULL_HANDLE; }
					return rslt;
				}
			} else {
				pDescriptorSets[dsIdx] = VK_NULL_HANDLE;
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
	VkResult rslt = VK_ERROR_FRAGMENTED_POOL;
	size_t mtlArgBuffEncSize = 0;
	id<MTLArgumentEncoder> mtlArgEnc = nil;
	bool isUsingMetalArgBuff = mvkDSL->isUsingMetalArgumentBuffers();

	if (isUsingMetalArgBuff) {
		if (needsMetalArgumentBufferEncoders()) {
			mtlArgEnc = mvkDSL->getMTLArgumentEncoder(variableDescriptorCount);
			mtlArgBuffEncSize = mtlArgEnc.encodedLength;
		} else {
			mtlArgBuffEncSize = mvkDSL->getMetal3ArgumentBufferEncodedLength(variableDescriptorCount);
		}
	}

	_descriptorSetAvailablility.enumerateEnabledBits([&](size_t dsIdx) {
		bool isSpaceAvail = true;		// If not using Metal arg buffers, space will always be available.
		MVKDescriptorSet* mvkDS = &_descriptorSets[dsIdx];
		NSUInteger mtlArgBuffOffset = 0;

		// If the desc set is using a Metal argument buffer, we must check if the desc set will fit in the slot
		// in the Metal argument buffer, if that slot was previously allocated for a returned descriptor set.
		if (isUsingMetalArgBuff) {
			mtlArgBuffOffset = mvkDS->getMetalArgumentBuffer().getMetalArgumentBufferOffset();

			// If the offset has not been set, and this is not the first desc set,
			// set the offset to align with the end of the previous desc set.
			if ( !mtlArgBuffOffset && dsIdx ) {
				auto& prevArgBuff = _descriptorSets[dsIdx - 1].getMetalArgumentBuffer();
				mtlArgBuffOffset = (prevArgBuff.getMetalArgumentBufferOffset() +
									mvkAlignByteCount(prevArgBuff.getMetalArgumentBufferEncodedSize(),
													  getMetalFeatures().mtlBufferAlignment));
			}

			// Get the offset of the next desc set, if one exists and
			// its offset has been set, or the end of the arg buffer.
			size_t nextDSIdx = dsIdx + 1;
			NSUInteger nextOffset = (nextDSIdx < _allocatedDescSetCount ? _descriptorSets[nextDSIdx].getMetalArgumentBuffer().getMetalArgumentBufferOffset() : 0);
			if ( !nextOffset ) { nextOffset = _metalArgumentBuffer.length; }

			isSpaceAvail = (mtlArgBuffOffset + mtlArgBuffEncSize) <= nextOffset;
		}

		if (isSpaceAvail) {
			rslt = mvkDS->allocate(mvkDSL, variableDescriptorCount, mtlArgBuffOffset, mtlArgBuffEncSize, mtlArgEnc);
			if (rslt) {
				freeDescriptorSet(mvkDS, false);
			} else {
				_descriptorSetAvailablility.disableBit(dsIdx);
				_allocatedDescSetCount = std::max(_allocatedDescSetCount, dsIdx + 1);
				*pVKDS = (VkDescriptorSet)mvkDS;
			}
			return false;
		} else {
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
			_descriptorSetAvailablility.enableBit(dsIdx);
		}
	} else {
		reportError(VK_ERROR_INITIALIZATION_FAILED, "A descriptor set is being returned to a descriptor pool that did not allocate it.");
	}
}

// Free allocated descriptor sets and reset descriptor pools.
// Don't waste time freeing desc sets that were never allocated.
VkResult MVKDescriptorPool::reset(VkDescriptorPoolResetFlags flags) {
	for (uint32_t dsIdx = 0; dsIdx < _allocatedDescSetCount; dsIdx++) {
		freeDescriptorSet(&_descriptorSets[dsIdx], true);
	}
	_descriptorSetAvailablility.enableAllBits();

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

	_allocatedDescSetCount = 0;

	return VK_SUCCESS;
}

// Allocate a descriptor of the specified type
VkResult MVKDescriptorPool::allocateDescriptor(VkDescriptorType descriptorType,
											   MVKDescriptor** pMVKDesc,
											   bool& dynamicAllocation) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			return _uniformBufferDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			return _storageBufferDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			return _uniformBufferDynamicDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return _storageBufferDynamicDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
			return _inlineUniformBlockDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
			return _sampledImageDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			return _storageImageDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return _inputAttachmentDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			return _samplerDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			return _combinedImageSamplerDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			return _uniformTexelBufferDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			return _storageTexelBufferDescriptors.allocateDescriptor(descriptorType, pMVKDesc, dynamicAllocation, this);

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

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
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

// Return the size of the preallocated pool for descriptors of the specified type.
// There may be more than one poolSizeCount instance for the desired VkDescriptorType.
// Accumulate the descriptor count for the desired VkDescriptorType accordingly.
// For descriptors of the VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK type,
// we accumulate the count via the pNext chain.
size_t MVKDescriptorPool::getPoolSize(const VkDescriptorPoolCreateInfo* pCreateInfo, VkDescriptorType descriptorType) {
	uint32_t descCnt = 0;
	if (descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_INLINE_UNIFORM_BLOCK_CREATE_INFO: {
					auto* pDescPoolInlineBlockCreateInfo = (VkDescriptorPoolInlineUniformBlockCreateInfo*)next;
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

std::string MVKDescriptorPool::getLogDescription(std::string indent) {
#define STR(name) #name
#define printDescCnt(descType, spacing, descPool)  \
	if (_##descPool##Descriptors.size()) {  \
		descStr << "\n" << descCntIndent << STR(VK_DESCRIPTOR_TYPE_##descType) ": " spacing << _##descPool##Descriptors.size()  \
		<< "  (" << _##descPool##Descriptors.getRemainingDescriptorCount() << " remaining)"; }

	std::stringstream descStr;
	descStr << "VkDescriptorPool with " << _descriptorSetAvailablility.size() << " descriptor sets";
	descStr << " (reset " << (mvkIsAnyFlagEnabled(_flags, VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT) ? "or free" : "only") << ")";
	descStr << ", and pooled descriptors:";

	auto descCntIndent = indent + "\t";
	printDescCnt(UNIFORM_BUFFER, "          ", uniformBuffer);
	printDescCnt(STORAGE_BUFFER, "          ", storageBuffer);
	printDescCnt(UNIFORM_BUFFER_DYNAMIC, "  ", uniformBufferDynamic);
	printDescCnt(STORAGE_BUFFER_DYNAMIC, "  ", storageBufferDynamic);
	printDescCnt(INLINE_UNIFORM_BLOCK_EXT, "", inlineUniformBlock);
	printDescCnt(SAMPLED_IMAGE, "           ", sampledImage);
	printDescCnt(STORAGE_IMAGE, "           ", storageImage);
	printDescCnt(INPUT_ATTACHMENT, "        ", inputAttachment);
	printDescCnt(SAMPLER, "                 ", sampler);
	printDescCnt(COMBINED_IMAGE_SAMPLER, "  ", combinedImageSampler);
	printDescCnt(UNIFORM_TEXEL_BUFFER, "    ", uniformTexelBuffer);
	printDescCnt(STORAGE_TEXEL_BUFFER, "    ", storageTexelBuffer);
	return descStr.str();
}

MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device, const VkDescriptorPoolCreateInfo* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device),
	_descriptorSets(pCreateInfo->maxSets, MVKDescriptorSet(this)),
	_descriptorSetAvailablility(pCreateInfo->maxSets, true),
	_mtlBufferAllocator(_device, getMetalFeatures().maxMTLBufferSize, true),
	_uniformBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER)),
	_storageBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER)),
	_uniformBufferDynamicDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC)),
	_storageBufferDynamicDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC)),
	_inlineUniformBlockDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK)),
	_sampledImageDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE)),
	_storageImageDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE)),
	_inputAttachmentDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT)),
	_samplerDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_SAMPLER)),
	_combinedImageSamplerDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER)),
	_uniformTexelBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER)),
    _storageTexelBufferDescriptors(getPoolSize(pCreateInfo, VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER)),
    _flags(pCreateInfo->flags) {

		initMetalArgumentBuffer(pCreateInfo);
		MVKLogDebugIf(getMVKConfig().debugMode, "Created %s\n", getLogDescription().c_str());
	}

void MVKDescriptorPool::initMetalArgumentBuffer(const VkDescriptorPoolCreateInfo* pCreateInfo) {
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
				// VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK counts handled separately below
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

		// VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK counts pulled separately
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_INLINE_UNIFORM_BLOCK_CREATE_INFO: {
					auto* pDescPoolInlineBlockCreateInfo = (VkDescriptorPoolInlineUniformBlockCreateInfo*)next;
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
			setMetalObjectLabel(_metalArgumentBuffer, @"Descriptor set argument buffer");
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

	for (uint32_t i = 0; i < pCreateInfo->descriptorUpdateEntryCount; i++) {
		const auto& entry = pCreateInfo->pDescriptorUpdateEntries[i];
		_entries.push_back(entry);

		// Accumulate the size of the template. If we were given a stride, use that;
		// otherwise, assume only one info struct of the appropriate type.
		size_t entryEnd = entry.offset;
		if (entry.stride) {
			entryEnd += entry.stride * entry.descriptorCount;
		} else {
			switch (entry.descriptorType) {
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
					entryEnd += sizeof(VkDescriptorBufferInfo);
					break;

				case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
				case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
				case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
				case VK_DESCRIPTOR_TYPE_SAMPLER:
				case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
					entryEnd += sizeof(VkDescriptorImageInfo);
					break;

				case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
				case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
					entryEnd += sizeof(VkBufferView);
					break;

				default:
					break;
			}
		}
		_size = std::max(_size, entryEnd);
	}
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

		if( !dstSet ) { continue; }		// Nulls are permitted

		const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock = nullptr;
		for (const auto* next = (VkBaseInStructure*)pDescWrite->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
					break;
				}
				default:
					break;
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
		VkWriteDescriptorSetInlineUniformBlock inlineUniformBlock;
		inlineUniformBlock.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK;
		inlineUniformBlock.pNext = nullptr;
		inlineUniformBlock.pData = dstBuffer;
		inlineUniformBlock.dataSize = descCnt;

		MVKDescriptorSet* srcSet = (MVKDescriptorSet*)pDescCopy->srcSet;
		MVKDescriptorSet* dstSet = (MVKDescriptorSet*)pDescCopy->dstSet;
		if( !srcSet || !dstSet ) { continue; }		// Nulls are permitted

		srcSet->read(pDescCopy, imgInfos, buffInfos, texelBuffInfos, &inlineUniformBlock);
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
		VkWriteDescriptorSetInlineUniformBlock inlineUniformBlock;
		if (pEntry->descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
			inlineUniformBlock.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK;
			inlineUniformBlock.pNext = nullptr;
			inlineUniformBlock.pData = pCurData;
			inlineUniformBlock.dataSize = pEntry->descriptorCount;
			pCurData = &inlineUniformBlock;
		}
		dstSet->write(pEntry, pEntry->stride, pCurData);
	}
}
