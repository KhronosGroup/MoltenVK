/*
 * MVKDescriptor.mm
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

#include "MVKDescriptor.h"
#include "MVKDescriptorSet.h"
#include "MVKCommandBuffer.h"
#include "MVKBuffer.h"


#pragma mark MVKShaderStageResourceBinding

MVKShaderStageResourceBinding MVKShaderStageResourceBinding::operator+ (const MVKShaderStageResourceBinding& rhs) {
	MVKShaderStageResourceBinding rslt;
	rslt.resourceIndex = this->resourceIndex + rhs.resourceIndex;
	rslt.bufferIndex = this->bufferIndex + rhs.bufferIndex;
	rslt.textureIndex = this->textureIndex + rhs.textureIndex;
	rslt.samplerIndex = this->samplerIndex + rhs.samplerIndex;
	return rslt;
}

MVKShaderStageResourceBinding& MVKShaderStageResourceBinding::operator+= (const MVKShaderStageResourceBinding& rhs) {
	this->resourceIndex += rhs.resourceIndex;
	this->bufferIndex += rhs.bufferIndex;
	this->textureIndex += rhs.textureIndex;
	this->samplerIndex += rhs.samplerIndex;
	return *this;
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


#pragma mark MVKShaderResourceBinding

uint16_t MVKShaderResourceBinding::getMaxBufferIndex() {
	return std::max({stages[kMVKShaderStageVertex].bufferIndex, stages[kMVKShaderStageTessCtl].bufferIndex, stages[kMVKShaderStageTessEval].bufferIndex, stages[kMVKShaderStageFragment].bufferIndex, stages[kMVKShaderStageCompute].bufferIndex});
}

uint16_t MVKShaderResourceBinding::getMaxTextureIndex() {
	return std::max({stages[kMVKShaderStageVertex].textureIndex, stages[kMVKShaderStageTessCtl].textureIndex, stages[kMVKShaderStageTessEval].textureIndex, stages[kMVKShaderStageFragment].textureIndex, stages[kMVKShaderStageCompute].textureIndex});
}

uint16_t MVKShaderResourceBinding::getMaxSamplerIndex() {
	return std::max({stages[kMVKShaderStageVertex].samplerIndex, stages[kMVKShaderStageTessCtl].samplerIndex, stages[kMVKShaderStageTessEval].samplerIndex, stages[kMVKShaderStageFragment].samplerIndex, stages[kMVKShaderStageCompute].samplerIndex});
}

MVKShaderResourceBinding MVKShaderResourceBinding::operator+ (const MVKShaderResourceBinding& rhs) {
	MVKShaderResourceBinding rslt;
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		rslt.stages[i] = this->stages[i] + rhs.stages[i];
	}
	return rslt;
}

MVKShaderResourceBinding& MVKShaderResourceBinding::operator+= (const MVKShaderResourceBinding& rhs) {
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		this->stages[i] += rhs.stages[i];
	}
	return *this;
}

MTLRenderStages mvkMTLRenderStagesFromMVKShaderStages(bool stageEnabled[]) {
	MTLRenderStages mtlStages = 0;
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (stageEnabled[stage]) {
			switch (stage) {
				case kMVKShaderStageVertex:
				case kMVKShaderStageTessCtl:
				case kMVKShaderStageTessEval:
					mtlStages |= MTLRenderStageVertex;
					break;

				case kMVKShaderStageFragment:
					mtlStages |= MTLRenderStageFragment;
					break;

				default:
					break;
			}
		}
	}
	return mtlStages;
}


#pragma mark -
#pragma mark MVKDescriptorSetLayoutBinding

MVKVulkanAPIObject* MVKDescriptorSetLayoutBinding::getVulkanAPIObject() { return _layout; };

uint32_t MVKDescriptorSetLayoutBinding::getDescriptorCount(MVKDescriptorSet* descSet) {

	if (_info.descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		return 1;
	}

	if (descSet && mvkIsAnyFlagEnabled(_flags, VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT_EXT)) {
		return descSet->_variableDescriptorCount;
	}

	return _info.descriptorCount;
}

MVKSampler* MVKDescriptorSetLayoutBinding::getImmutableSampler(uint32_t index) {
	return (index < _immutableSamplers.size()) ? _immutableSamplers[index] : nullptr;
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayoutBinding::bind(MVKCommandEncoder* cmdEncoder,
										 MVKDescriptorSet* descSet,
										 MVKShaderResourceBinding& dslMTLRezIdxOffsets,
										 MVKArrayRef<uint32_t> dynamicOffsets,
										 uint32_t& dynamicOffsetIndex) {

	// Establish the resource indices to use, by combining the offsets of the DSL and this DSL binding.
    MVKShaderResourceBinding mtlIdxs = _mtlResourceIndexOffsets + dslMTLRezIdxOffsets;

	VkDescriptorType descType = getDescriptorType();
    uint32_t descCnt = getDescriptorCount(descSet);
    for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
		MVKDescriptor* mvkDesc = descSet->getDescriptor(getBinding(), descIdx);
		if (mvkDesc->getDescriptorType() == descType) {
			mvkDesc->bind(cmdEncoder, this, descIdx, _applyToStage, mtlIdxs, dynamicOffsets, dynamicOffsetIndex);
		}
    }
}

template<typename T>
static const T& get(const void* pData, size_t stride, uint32_t index) {
    return *(T*)((const char*)pData + stride * index);
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayoutBinding::push(MVKCommandEncoder* cmdEncoder,
                                         uint32_t& dstArrayElement,
                                         uint32_t& descriptorCount,
                                         uint32_t& descriptorsPushed,
                                         VkDescriptorType descriptorType,
                                         size_t stride,
                                         const void* pData,
                                         MVKShaderResourceBinding& dslMTLRezIdxOffsets) {
    MVKMTLBufferBinding bb;
    MVKMTLTextureBinding tb;
    MVKMTLSamplerStateBinding sb;

    if (dstArrayElement >= _info.descriptorCount) {
        dstArrayElement -= _info.descriptorCount;
        return;
    }

    if (descriptorType != _info.descriptorType) {
        dstArrayElement = 0;
        if (_info.descriptorCount > descriptorCount)
            descriptorCount = 0;
        else {
            descriptorCount -= _info.descriptorCount;
            descriptorsPushed = _info.descriptorCount;
        }
        return;
    }

    // Establish the resource indices to use, by combining the offsets of the DSL and this DSL binding.
    MVKShaderResourceBinding mtlIdxs = _mtlResourceIndexOffsets + dslMTLRezIdxOffsets;

    for (uint32_t rezIdx = dstArrayElement;
         rezIdx < _info.descriptorCount && rezIdx - dstArrayElement < descriptorCount;
         rezIdx++) {
        switch (_info.descriptorType) {

            case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
            case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
            case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
            case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER: {
                const auto& bufferInfo = get<VkDescriptorBufferInfo>(pData, stride, rezIdx - dstArrayElement);
                MVKBuffer* buffer = (MVKBuffer*)bufferInfo.buffer;
                bb.mtlBuffer = buffer->getMTLBuffer();
                bb.offset = buffer->getMTLBufferOffset() + bufferInfo.offset;
                if (bufferInfo.range == VK_WHOLE_SIZE)
                    bb.size = (uint32_t)(buffer->getByteCount() - bb.offset);
                else
                    bb.size = (uint32_t)bufferInfo.range;

                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
                    if (_applyToStage[i]) {
                        bb.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
						if (cmdEncoder) { cmdEncoder->bindBuffer(bb, MVKShaderStage(i)); }
                    }
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: {
                const auto& inlineUniformBlock = *(VkWriteDescriptorSetInlineUniformBlockEXT*)pData;
                bb.mtlBytes = inlineUniformBlock.pData;
                bb.size = inlineUniformBlock.dataSize;
                bb.isInline = true;
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
                    if (_applyToStage[i]) {
                        bb.index = mtlIdxs.stages[i].bufferIndex;
						if (cmdEncoder) { cmdEncoder->bindBuffer(bb, MVKShaderStage(i)); }
                    }
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
            case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
            case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT: {
                const auto& imageInfo = get<VkDescriptorImageInfo>(pData, stride, rezIdx - dstArrayElement);
                MVKImageView* imageView = (MVKImageView*)imageInfo.imageView;
                uint8_t planeCount = (imageView) ? imageView->getPlaneCount() : 1;
                for (uint8_t planeIndex = 0; planeIndex < planeCount; planeIndex++) {
                    tb.mtlTexture = imageView->getMTLTexture(planeIndex);
                    tb.swizzle = (_info.descriptorType == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE) ? imageView->getPackedSwizzle() : 0;
                    if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
                        id<MTLTexture> mtlTex = tb.mtlTexture;
                        if (mtlTex.parentTexture) { mtlTex = mtlTex.parentTexture; }
                        bb.mtlBuffer = mtlTex.buffer;
                        bb.offset = mtlTex.bufferOffset;
                        bb.size = (uint32_t)(mtlTex.height * mtlTex.bufferBytesPerRow);
                    }
                    for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
                        if (_applyToStage[i]) {
                            tb.index = mtlIdxs.stages[i].textureIndex + rezIdx + planeIndex;
							if (cmdEncoder) { cmdEncoder->bindTexture(tb, MVKShaderStage(i)); }
                            if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
                                bb.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
								if (cmdEncoder) { cmdEncoder->bindBuffer(bb, MVKShaderStage(i)); }
                            }
                        }
                    }
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
            case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER: {
                auto* bufferView = get<MVKBufferView*>(pData, stride, rezIdx - dstArrayElement);
                tb.mtlTexture = bufferView->getMTLTexture();
                tb.swizzle = 0;
                if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
                    id<MTLTexture> mtlTex = tb.mtlTexture;
                    bb.mtlBuffer = mtlTex.buffer;
                    bb.offset = mtlTex.bufferOffset;
                    bb.size = (uint32_t)(mtlTex.height * mtlTex.bufferBytesPerRow);
                }
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
                    if (_applyToStage[i]) {
                        tb.index = mtlIdxs.stages[i].textureIndex + rezIdx;
						if (cmdEncoder) { cmdEncoder->bindTexture(tb, MVKShaderStage(i)); }
                        if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
                            bb.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
							if (cmdEncoder) { cmdEncoder->bindBuffer(bb, MVKShaderStage(i)); }
                        }
                    }
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_SAMPLER: {
                MVKSampler* sampler;
				if (_immutableSamplers.empty()) {
                    sampler = (MVKSampler*)get<VkDescriptorImageInfo>(pData, stride, rezIdx - dstArrayElement).sampler;
					validate(sampler);
				} else {
                    sampler = _immutableSamplers[rezIdx];
				}
                sb.mtlSamplerState = sampler->getMTLSamplerState();
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
                    if (_applyToStage[i]) {
                        sb.index = mtlIdxs.stages[i].samplerIndex + rezIdx;
						if (cmdEncoder) { cmdEncoder->bindSamplerState(sb, MVKShaderStage(i)); }
                    }
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
                const auto& imageInfo = get<VkDescriptorImageInfo>(pData, stride, rezIdx - dstArrayElement);
                MVKImageView* imageView = (MVKImageView*)imageInfo.imageView;
                uint8_t planeCount = (imageView) ? imageView->getPlaneCount() : 1;
                for (uint8_t planeIndex = 0; planeIndex < planeCount; planeIndex++) {
                    tb.mtlTexture = imageView->getMTLTexture(planeIndex);
                    tb.swizzle = (imageView) ? imageView->getPackedSwizzle() : 0;
                    MVKSampler* sampler;
                    if (_immutableSamplers.empty()) {
                        sampler = (MVKSampler*)imageInfo.sampler;
                        validate(sampler);
                    } else {
                        sampler = _immutableSamplers[rezIdx];
                    }
                    sb.mtlSamplerState = sampler->getMTLSamplerState();
                    for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
                        if (_applyToStage[i]) {
                            tb.index = mtlIdxs.stages[i].textureIndex + rezIdx + planeIndex;
                            sb.index = mtlIdxs.stages[i].samplerIndex + rezIdx;
							if (cmdEncoder) {
								cmdEncoder->bindTexture(tb, MVKShaderStage(i));
								cmdEncoder->bindSamplerState(sb, MVKShaderStage(i));
							}
                        }
                    }
                }
                break;
            }

            default:
                break;
        }
    }

    dstArrayElement = 0;
    if (_info.descriptorCount > descriptorCount)
        descriptorCount = 0;
    else {
        descriptorCount -= _info.descriptorCount;
        descriptorsPushed = _info.descriptorCount;
    }
}

// Adds MTLArgumentDescriptors to the array, and updates resource indexes consumed.
void MVKDescriptorSetLayoutBinding::addMTLArgumentDescriptors(uint32_t stage,
															  NSMutableArray<MTLArgumentDescriptor*>* args,
															  uint32_t& argIdx) {
	if ( !_applyToStage[stage]) { return; }

	_argumentBufferIndex[stage] = argIdx;

	switch (getDescriptorType()) {

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			addMTLArgumentDescriptor(args, MTLDataTypePointer, MTLArgumentAccessReadOnly, argIdx);
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			addMTLArgumentDescriptor(args, MTLDataTypePointer, MTLArgumentAccessReadWrite, argIdx);
			break;

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			addMTLArgumentDescriptor(args, MTLDataTypeUChar, MTLArgumentAccessReadOnly, argIdx);
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			addMTLArgumentDescriptor(args, MTLDataTypeTexture, MTLArgumentAccessReadOnly, argIdx);
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			addMTLArgumentDescriptor(args, MTLDataTypeTexture, MTLArgumentAccessReadOnly, argIdx);
			addMTLArgumentDescriptor(args, MTLDataTypePointer, MTLArgumentAccessReadOnly, argIdx);
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			addMTLArgumentDescriptor(args, MTLDataTypeTexture, MTLArgumentAccessReadWrite, argIdx);
			addMTLArgumentDescriptor(args, MTLDataTypePointer, MTLArgumentAccessReadWrite, argIdx);
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			addMTLArgumentDescriptor(args, MTLDataTypeSampler, MTLArgumentAccessReadOnly, argIdx);
			break;

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			addMTLArgumentDescriptor(args, MTLDataTypeTexture, MTLArgumentAccessReadOnly, argIdx);
			addMTLArgumentDescriptor(args, MTLDataTypeSampler, MTLArgumentAccessReadOnly, argIdx);
			break;

		default:
			break;
	}
}

// Adds an MTLArgumentDescriptor if the specified type to the array, and updates resource indexes consumed.
void MVKDescriptorSetLayoutBinding::addMTLArgumentDescriptor(NSMutableArray<MTLArgumentDescriptor*>* args,
															 MTLDataType dataType,
															 MTLArgumentAccess access,
															 uint32_t& argIdx) {
	auto* argDesc = [MTLArgumentDescriptor argumentDescriptor];
	argDesc.dataType = dataType;
	argDesc.access = access;
	argDesc.index = argIdx;
	argDesc.arrayLength = _info.descriptorCount;	// getDescriptorCount() won't work for inline block
	argDesc.textureType = MTLTextureType2D;

	[args addObject: argDesc];
	argIdx += getDescriptorCount();
}

void MVKDescriptorSetLayoutBinding::writeToMetalArgumentBuffer(id<MTLBuffer> mtlBuffer,
															   NSUInteger offset,
															   uint32_t elementIndex) {
	if ( !mtlBuffer ) { return; }

	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (_applyToStage[stage]) {
			uint32_t argIdx = getMTLArgumentBufferIndex(stage, elementIndex);
			[_layout->_argumentEncoder[stage].mtlArgumentEncoder setBuffer: mtlBuffer offset: offset atIndex: argIdx];
		}
	}
}

void MVKDescriptorSetLayoutBinding::writeToMetalArgumentBuffer(id<MTLTexture> mtlTexture,
															   uint32_t planeCount,
															   uint32_t planeIndex,
															   uint32_t elementIndex) {
	if ( !mtlTexture ) { return; }

	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (_applyToStage[stage]) {
			uint32_t argIdx = getMTLArgumentBufferIndex(stage, elementIndex * planeCount + planeIndex);
			[_layout->_argumentEncoder[stage].mtlArgumentEncoder setTexture: mtlTexture atIndex: argIdx];
		}
	}
}

void MVKDescriptorSetLayoutBinding::writeToMetalArgumentBuffer(id<MTLSamplerState> mtlSamplerState,
															   uint32_t elementIndex) {
	// Metal requires sampler, so get default if not provided.
	if ( !mtlSamplerState ) { mtlSamplerState = getDevice()->getDefaultMTLSamplerState(); }

	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (_applyToStage[stage]) {
			uint32_t argIdx = getMTLArgumentBufferIndex(stage, elementIndex);
			[_layout->_argumentEncoder[stage].mtlArgumentEncoder setSamplerState: mtlSamplerState atIndex: argIdx];
		}
	}
}

void MVKDescriptorSetLayoutBinding::writeToMetalArgumentBuffer(uint8_t* pSrcData,
															   NSUInteger dstOffset,
															   NSUInteger dataLen,
															   uint32_t elementIndex) {
	if ( !pSrcData ) { return; }

	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (_applyToStage[stage]) {
			uint32_t argIdx = getMTLArgumentBufferIndex(stage, elementIndex);
			uint8_t* pDstData = (uint8_t*)[_layout->_argumentEncoder[stage].mtlArgumentEncoder constantDataAtIndex: argIdx];
			if (pDstData) { memcpy(pDstData + dstOffset, pSrcData, dataLen); }
		}
	}
}

// If depth compare is required, but unavailable on the device, the sampler can only be used as an immutable sampler
bool MVKDescriptorSetLayoutBinding::validate(MVKSampler* mvkSampler) {
	if (mvkSampler->getRequiresConstExprSampler()) {
		mvkSampler->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdPushDescriptorSet/vkCmdPushDescriptorSetWithTemplate(): Tried to push an immutable sampler.");
		return false;
	}
	return true;
}

void MVKDescriptorSetLayoutBinding::populateShaderConverterContext(mvk::SPIRVToMSLConversionConfiguration& context,
                                                                   MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                                                   uint32_t dslIndex) {

	MVKSampler* mvkSamp = !_immutableSamplers.empty() ? _immutableSamplers.front() : nullptr;

    // Establish the resource indices to use, by combining the offsets of the DSL and this DSL binding.
    MVKShaderResourceBinding mtlIdxs = _mtlResourceIndexOffsets + dslMTLRezIdxOffsets;

    static const spv::ExecutionModel models[] = {
        spv::ExecutionModelVertex,
        spv::ExecutionModelTessellationControl,
        spv::ExecutionModelTessellationEvaluation,
        spv::ExecutionModelFragment,
        spv::ExecutionModelGLCompute
    };
    for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
        if (_applyToStage[i]) {
            mvkPopulateShaderConverterContext(context,
                                              mtlIdxs.stages[i],
                                              models[i],
                                              dslIndex,
                                              _info.binding,
											  getDescriptorCount(),
											  mvkSamp);
        }
    }
}

MVKDescriptorSetLayoutBinding::MVKDescriptorSetLayoutBinding(MVKDevice* device,
															 MVKDescriptorSetLayout* layout,
															 const VkDescriptorSetLayoutBinding* pBinding,
															 VkDescriptorBindingFlagsEXT bindingFlags,
															 uint32_t descriptorIndex) :
	MVKBaseDeviceObject(device),
	_layout(layout),
	_info(*pBinding),
	_flags(bindingFlags),
	_descriptorIndex(descriptorIndex) {

	_info.pImmutableSamplers = nullptr;     // Remove dangling pointer

	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
        // Determine if this binding is used by this shader stage
        _applyToStage[i] = mvkAreAllFlagsEnabled(pBinding->stageFlags, mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage(i)));
	    // If this binding is used by the shader, set the Metal resource index
        if (_applyToStage[i]) {
            initMetalResourceIndexOffsets(&_mtlResourceIndexOffsets.stages[i],
                                          &layout->_mtlResourceCounts.stages[i], pBinding);
        }
    }

    // If immutable samplers are defined, copy them in
    if ( pBinding->pImmutableSamplers &&
        (pBinding->descriptorType == VK_DESCRIPTOR_TYPE_SAMPLER ||
         pBinding->descriptorType == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) ) {
            _immutableSamplers.reserve(pBinding->descriptorCount);
            for (uint32_t i = 0; i < pBinding->descriptorCount; i++) {
                _immutableSamplers.push_back((MVKSampler*)pBinding->pImmutableSamplers[i]);
                _immutableSamplers.back()->retain();
            }
        }

}

MVKDescriptorSetLayoutBinding::MVKDescriptorSetLayoutBinding(const MVKDescriptorSetLayoutBinding& binding) :
	MVKBaseDeviceObject(binding._device),
	_layout(binding._layout),
	_info(binding._info),
	_flags(binding._flags),
	_descriptorIndex(binding._descriptorIndex),
	_immutableSamplers(binding._immutableSamplers),
	_mtlResourceIndexOffsets(binding._mtlResourceIndexOffsets) {

	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
        _applyToStage[i] = binding._applyToStage[i];
    }
	for (MVKSampler* sampler : _immutableSamplers) {
		sampler->retain();
	}
}

MVKDescriptorSetLayoutBinding::~MVKDescriptorSetLayoutBinding() {
	for (MVKSampler* sampler : _immutableSamplers) {
		sampler->release();
	}
}

// Sets the appropriate Metal resource indexes within this binding from the
// specified descriptor set binding counts, and updates those counts accordingly.
void MVKDescriptorSetLayoutBinding::initMetalResourceIndexOffsets(MVKShaderStageResourceBinding* pBindingIndexes,
																  MVKShaderStageResourceBinding* pDescSetCounts,
																  const VkDescriptorSetLayoutBinding* pBinding) {
	bool useArgBuffs = getDevice()->_pMetalFeatures->argumentBuffers;
	uint32_t descCnt = pBinding->descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT ? 1 : pBinding->descriptorCount;

	// Sets an index offset and updates both that index and the general resource index.
	// Can be used multiply for combined multi-resource descriptor types.
#	define setResourceIndexOffset(rezIdx) \
	do { \
		pBindingIndexes->rezIdx = useArgBuffs ?  pDescSetCounts->resourceIndex : pDescSetCounts->rezIdx; \
		pDescSetCounts->rezIdx += descCnt; \
		pBindingIndexes->resourceIndex = pDescSetCounts->resourceIndex; \
		pDescSetCounts->resourceIndex += descCnt; \
	} while(false)

    switch (pBinding->descriptorType) {
        case VK_DESCRIPTOR_TYPE_SAMPLER:
			setResourceIndexOffset(samplerIndex);

			if (pBinding->descriptorCount > 1 && !_device->_pMetalFeatures->arrayOfSamplers) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of samplers.", _device->getName()));
			}
            break;

        case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			setResourceIndexOffset(textureIndex);
			setResourceIndexOffset(samplerIndex);

			if (pBinding->descriptorCount > 1) {
				if ( !_device->_pMetalFeatures->arrayOfTextures ) {
					_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of textures.", _device->getName()));
				}
				if ( !_device->_pMetalFeatures->arrayOfSamplers ) {
					_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of samplers.", _device->getName()));
				}
                if ( pBinding->pImmutableSamplers ) {
                    _layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Sampler arrays contaning multi planar samplers are not supported."));
                }
			}

            if ( pBinding->pImmutableSamplers ) {
                for (uint32_t i = 0; i < pBinding->descriptorCount; i++) {
                    uint8_t planeCount = ((MVKSampler*)pBinding->pImmutableSamplers[i])->getPlaneCount();
                    if (planeCount > 1) {
                        pDescSetCounts->textureIndex += planeCount - 1;
                    }
                }
            }
            break;

        case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
        case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			setResourceIndexOffset(bufferIndex);
            // fallthrough
        case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
        case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
        case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			setResourceIndexOffset(textureIndex);

			if (pBinding->descriptorCount > 1 && !_device->_pMetalFeatures->arrayOfTextures) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of textures.", _device->getName()));
			}
            break;

        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
        case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
        case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			setResourceIndexOffset(bufferIndex);
            break;

        default:
            break;
    }
}


#pragma mark -
#pragma mark MVKDescriptor

MTLResourceUsage MVKDescriptor::getMTLResourceUsage() {
	MTLResourceUsage mtlUsage = MTLResourceUsageRead;
	switch (getDescriptorType()) {
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			mtlUsage |= MTLResourceUsageSample;
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			mtlUsage |= MTLResourceUsageWrite;
			break;

		default:
			break;
	}
	return mtlUsage;
}


#pragma mark -
#pragma mark MVKBufferDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKBufferDescriptor::bind(MVKCommandEncoder* cmdEncoder,
							   MVKDescriptorSetLayoutBinding* mvkDSLBind,
							   uint32_t descriptorIndex,
							   bool stages[],
							   MVKShaderResourceBinding& mtlIndexes,
							   MVKArrayRef<uint32_t> dynamicOffsets,
							   uint32_t& dynamicOffsetIndex) {
	MVKMTLBufferBinding bb;
	NSUInteger bufferDynamicOffset = 0;
	VkDescriptorType descType = getDescriptorType();
	if (descType == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC ||
		descType == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC) {
		if (dynamicOffsets.size > dynamicOffsetIndex) {
			bufferDynamicOffset = dynamicOffsets[dynamicOffsetIndex++];
		}
	}
	if (_mvkBuffer) {
		bb.mtlBuffer = _mvkBuffer->getMTLBuffer();
		bb.offset = _mvkBuffer->getMTLBufferOffset() + _buffOffset + bufferDynamicOffset;
		if (_buffRange == VK_WHOLE_SIZE)
			bb.size = (uint32_t)(_mvkBuffer->getByteCount() - bb.offset);
		else
			bb.size = (uint32_t)_buffRange;
	}

	// Update the Metal argument buffer entry with the dynamic offset
	if (descType == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC || descType == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC) {
		mvkDSLBind->writeToMetalArgumentBuffer(bb.mtlBuffer, bb.offset, descriptorIndex);
	}

	if (mvkDSLBind->usingMetalArgumentBuffer()) {
		MVKMTLArgumentBufferResourceUsage abru;
		abru.mtlResource = bb.mtlResource;
		abru.mtlUsage = getMTLResourceUsage();
		abru.mtlStages = mvkMTLRenderStagesFromMVKShaderStages(stages);
		if (cmdEncoder) { cmdEncoder->useArgumentBufferResource(abru, stages[kMVKShaderStageCompute]); }
	} else {
		// If not using Metal argument buffer, bind discretely
		for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
			if (stages[i]) {
				bb.index = mtlIndexes.stages[i].bufferIndex + descriptorIndex;
				if (cmdEncoder) { cmdEncoder->bindBuffer(bb, MVKShaderStage(i)); }
			}
		}
	}
}

void MVKBufferDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
								uint32_t srcIndex,
								size_t stride,
								const void* pData) {
	auto* oldBuff = _mvkBuffer;

	const auto* pBuffInfo = &get<VkDescriptorBufferInfo>(pData, stride, srcIndex);
	_mvkBuffer = (MVKBuffer*)pBuffInfo->buffer;
	_buffOffset = pBuffInfo->offset;
	_buffRange = pBuffInfo->range;

	if (_mvkBuffer) { _mvkBuffer->retain(); }
	if (oldBuff) { oldBuff->release(); }

	// Update the Metal argument buffer entry
	id<MTLBuffer> mtlBuffer = _mvkBuffer ? _mvkBuffer->getMTLBuffer() : nil;
	NSUInteger mtlBuffOffset = _mvkBuffer ? _mvkBuffer->getMTLBufferOffset() + _buffOffset : 0;
	mvkDSLBind->writeToMetalArgumentBuffer(mtlBuffer, mtlBuffOffset, srcIndex);
}

void MVKBufferDescriptor::read(uint32_t dstIndex,
							   VkDescriptorImageInfo* pImageInfo,
							   VkDescriptorBufferInfo* pBufferInfo,
							   VkBufferView* pTexelBufferView,
							   VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	auto& buffInfo = pBufferInfo[dstIndex];
	buffInfo.buffer = (VkBuffer)_mvkBuffer;
	buffInfo.offset = _buffOffset;
	buffInfo.range = _buffRange;
}

void MVKBufferDescriptor::reset() {
	if (_mvkBuffer) { _mvkBuffer->release(); }
	_mvkBuffer = nullptr;
	_buffOffset = 0;
	_buffRange = 0;
	MVKDescriptor::reset();
}


#pragma mark -
#pragma mark MVKInlineUniformBlockDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKInlineUniformBlockDescriptor::bind(MVKCommandEncoder* cmdEncoder,
										   MVKDescriptorSetLayoutBinding* mvkDSLBind,
										   uint32_t descriptorIndex,
										   bool stages[],
										   MVKShaderResourceBinding& mtlIndexes,
										   MVKArrayRef<uint32_t> dynamicOffsets,
										   uint32_t& dynamicOffsetIndex) {

	if (mvkDSLBind->usingMetalArgumentBuffer()) { return; }

	MVKMTLBufferBinding bb;
	bb.mtlBytes = _buffer;
	bb.size = _length;
	bb.isInline = true;
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		if (stages[i]) {
			bb.index = mtlIndexes.stages[i].bufferIndex;
			if (cmdEncoder) { cmdEncoder->bindBuffer(bb, MVKShaderStage(i)); }
		}
	}
}

void MVKInlineUniformBlockDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
                                            uint32_t dstOffset,
                                            size_t stride,
                                            const void* pData) {
	const auto& pInlineUniformBlock = *(VkWriteDescriptorSetInlineUniformBlockEXT*)pData;
	if (_buffer && pInlineUniformBlock.pData && dstOffset < _length) {
		uint32_t dataLen = std::min(pInlineUniformBlock.dataSize, _length - dstOffset);
		memcpy(_buffer + dstOffset, pInlineUniformBlock.pData, dataLen);

		// Update the Metal argument buffer entry
		mvkDSLBind->writeToMetalArgumentBuffer((uint8_t*)pInlineUniformBlock.pData, dstOffset, dataLen, 0);
	}
}

void MVKInlineUniformBlockDescriptor::read(uint32_t srcOffset,
                                           VkDescriptorImageInfo* pImageInfo,
                                           VkDescriptorBufferInfo* pBufferInfo,
                                           VkBufferView* pTexelBufferView,
                                           VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	if (_buffer && pInlineUniformBlock->pData && srcOffset < _length) {
		uint32_t dataLen = std::min(pInlineUniformBlock->dataSize, _length - srcOffset);
		memcpy((void*)pInlineUniformBlock->pData, _buffer + srcOffset, dataLen);
	}
}

void MVKInlineUniformBlockDescriptor::setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) {
    _length = dslBinding->_info.descriptorCount;
    _buffer = (uint8_t*)malloc(_length);
}

void MVKInlineUniformBlockDescriptor::reset() {
    free(_buffer);
	_buffer = nullptr;
    _length = 0;
	MVKDescriptor::reset();
}


#pragma mark -
#pragma mark MVKImageDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKImageDescriptor::bind(MVKCommandEncoder* cmdEncoder,
							  MVKDescriptorSetLayoutBinding* mvkDSLBind,
							  uint32_t descriptorIndex,
							  bool stages[],
							  MVKShaderResourceBinding& mtlIndexes,
							  MVKArrayRef<uint32_t> dynamicOffsets,
							  uint32_t& dynamicOffsetIndex) {

	VkDescriptorType descType = getDescriptorType();
	uint8_t planeCount = _mvkImageView ? _mvkImageView->getPlaneCount() : 1;
    for (uint8_t planeIndex = 0; planeIndex < planeCount; planeIndex++) {
        MVKMTLTextureBinding tb;
        MVKMTLBufferBinding bb;
        
        if (_mvkImageView) {
            tb.mtlTexture = _mvkImageView->getMTLTexture(planeIndex);
        }
        tb.swizzle = ((descType == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE ||
                       descType == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) &&
                       tb.mtlTexture) ? _mvkImageView->getPackedSwizzle() : 0;
        if (descType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE && tb.mtlTexture) {
            id<MTLTexture> mtlTex = tb.mtlTexture;
            if (mtlTex.parentTexture) { mtlTex = mtlTex.parentTexture; }
            bb.mtlBuffer = mtlTex.buffer;
            bb.offset = mtlTex.bufferOffset;
            bb.size = (uint32_t)(mtlTex.height * mtlTex.bufferBytesPerRow);
        }

		if (mvkDSLBind->usingMetalArgumentBuffer()) {
			MVKMTLArgumentBufferResourceUsage abru;
			abru.mtlResource = tb.mtlResource;
			abru.mtlUsage = getMTLResourceUsage();
			abru.mtlStages = mvkMTLRenderStagesFromMVKShaderStages(stages);
			if (cmdEncoder) { cmdEncoder->useArgumentBufferResource(abru, stages[kMVKShaderStageCompute]); }
			if (descType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
				abru.mtlResource = bb.mtlResource;
				if (cmdEncoder) { cmdEncoder->useArgumentBufferResource(abru, stages[kMVKShaderStageCompute]); }
			}
		} else {
			// If not using Metal argument buffer, bind discretely
			for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
				if (stages[i]) {
					tb.index = mtlIndexes.stages[i].textureIndex + (descriptorIndex * planeCount) + planeIndex;
					if (cmdEncoder) { cmdEncoder->bindTexture(tb, MVKShaderStage(i)); }
					if (descType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
						bb.index = mtlIndexes.stages[i].bufferIndex + (descriptorIndex * planeCount) + planeIndex;
						if (cmdEncoder) { cmdEncoder->bindBuffer(bb, MVKShaderStage(i)); }
					}
				}
			}
		}
    }
}

void MVKImageDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
							   uint32_t srcIndex,
							   size_t stride,
							   const void* pData) {
	auto* oldImgView = _mvkImageView;

	const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcIndex);
	_mvkImageView = (MVKImageView*)pImgInfo->imageView;
	_imageLayout = pImgInfo->imageLayout;

	if (_mvkImageView) { _mvkImageView->retain(); }
	if (oldImgView) { oldImgView->release(); }

	// Update the Metal argument buffer entry
	uint8_t planeCount = _mvkImageView ? _mvkImageView->getPlaneCount() : 1;
	for (uint8_t planeIndex = 0; planeIndex < planeCount; planeIndex++) {
		id<MTLTexture> mtlTexture = _mvkImageView ? _mvkImageView->getMTLTexture(planeIndex) : nil;
		mvkDSLBind->writeToMetalArgumentBuffer(mtlTexture, planeCount, planeIndex, srcIndex);

		if (getDescriptorType() == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
			id<MTLTexture> baseMTLTex = mtlTexture.parentTexture ? mtlTexture.parentTexture : mtlTexture;
			uint32_t buffArgIdx = mvkDSLBind->getDescriptorCount() * planeCount + srcIndex;
			mvkDSLBind->writeToMetalArgumentBuffer(baseMTLTex.buffer, baseMTLTex.bufferOffset, buffArgIdx);
		}
	}
}

void MVKImageDescriptor::read(uint32_t dstIndex,
							  VkDescriptorImageInfo* pImageInfo,
							  VkDescriptorBufferInfo* pBufferInfo,
							  VkBufferView* pTexelBufferView,
							  VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	auto& imgInfo = pImageInfo[dstIndex];
	imgInfo.imageView = (VkImageView)_mvkImageView;
	imgInfo.imageLayout = _imageLayout;
}

void MVKImageDescriptor::reset() {
	if (_mvkImageView) { _mvkImageView->release(); }
	_mvkImageView = nullptr;
	_imageLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	MVKDescriptor::reset();
}


#pragma mark -
#pragma mark MVKSamplerDescriptorMixin

// A null cmdEncoder can be passed to perform a validation pass
// Metal validation requires each sampler in an array of samplers to be populated,
// even if not used, so populate a default if one hasn't been set.
void MVKSamplerDescriptorMixin::bind(MVKCommandEncoder* cmdEncoder,
									 MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t descriptorIndex,
									 bool stages[],
									 MVKShaderResourceBinding& mtlIndexes,
									 MVKArrayRef<uint32_t> dynamicOffsets,
									 uint32_t& dynamicOffsetIndex) {

	if (mvkDSLBind->usingMetalArgumentBuffer()) { return; }

	MVKMTLSamplerStateBinding sb;
	sb.mtlSamplerState = (_mvkSampler
						  ? _mvkSampler->getMTLSamplerState()
						  : cmdEncoder->getDevice()->getDefaultMTLSamplerState());
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		if (stages[i]) {
			sb.index = mtlIndexes.stages[i].samplerIndex + descriptorIndex;
			if (cmdEncoder) { cmdEncoder->bindSamplerState(sb, MVKShaderStage(i)); }
		}
	}
}

void MVKSamplerDescriptorMixin::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									  uint32_t srcIndex,
									  size_t stride,
									  const void* pData) {
	if (_hasDynamicSampler) {
		auto* oldSamp = _mvkSampler;

		const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcIndex);
		_mvkSampler = (MVKSampler*)pImgInfo->sampler;
		if (_mvkSampler && _mvkSampler->getRequiresConstExprSampler()) {
			_mvkSampler->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkUpdateDescriptorSets(): Tried to push an immutable sampler.");
		}

		if (_mvkSampler) { _mvkSampler->retain(); }
		if (oldSamp) { oldSamp->release(); }
	}
}

void MVKSamplerDescriptorMixin::read(uint32_t dstIndex,
									 VkDescriptorImageInfo* pImageInfo,
									 VkDescriptorBufferInfo* pBufferInfo,
									 VkBufferView* pTexelBufferView,
									 VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	auto& imgInfo = pImageInfo[dstIndex];
	imgInfo.sampler = _hasDynamicSampler ? (VkSampler)_mvkSampler : nullptr;
}

// If the descriptor set layout binding contains immutable samplers, use them
// Otherwise the sampler will be populated dynamically at a later time.
void MVKSamplerDescriptorMixin::setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) {
	auto* oldSamp = _mvkSampler;

	_mvkSampler = dslBinding->getImmutableSampler(index);
	_hasDynamicSampler = !_mvkSampler;

	if (_mvkSampler) { _mvkSampler->retain(); }
	if (oldSamp) { oldSamp->release(); }
}

void MVKSamplerDescriptorMixin::reset() {
	if (_mvkSampler) { _mvkSampler->release(); }
	_mvkSampler = nullptr;
	_hasDynamicSampler = true;
}


#pragma mark -
#pragma mark MVKSamplerDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKSamplerDescriptor::bind(MVKCommandEncoder* cmdEncoder,
								MVKDescriptorSetLayoutBinding* mvkDSLBind,
								uint32_t descriptorIndex,
								bool stages[],
								MVKShaderResourceBinding& mtlIndexes,
								MVKArrayRef<uint32_t> dynamicOffsets,
								uint32_t& dynamicOffsetIndex) {
	MVKSamplerDescriptorMixin::bind(cmdEncoder, mvkDSLBind, descriptorIndex, stages, mtlIndexes, dynamicOffsets, dynamicOffsetIndex);
}

void MVKSamplerDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
								 uint32_t srcIndex,
								 size_t stride,
								 const void* pData) {
	MVKSamplerDescriptorMixin::write(mvkDSLBind, srcIndex, stride, pData);

	// Update the Metal argument buffer entry
	id<MTLSamplerState> mtlSampler = _mvkSampler ? _mvkSampler->getMTLSamplerState() : nil;
	mvkDSLBind->writeToMetalArgumentBuffer(mtlSampler, srcIndex);
}

void MVKSamplerDescriptor::read(uint32_t dstIndex,
								VkDescriptorImageInfo* pImageInfo,
								VkDescriptorBufferInfo* pBufferInfo,
								VkBufferView* pTexelBufferView,
								VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	MVKSamplerDescriptorMixin::read(dstIndex, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
}

void MVKSamplerDescriptor::setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) {
	MVKDescriptor::setLayout(dslBinding, index);
	MVKSamplerDescriptorMixin::setLayout(dslBinding, index);
}

void MVKSamplerDescriptor::reset() {
	MVKSamplerDescriptorMixin::reset();
	MVKDescriptor::reset();
}


#pragma mark -
#pragma mark MVKCombinedImageSamplerDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKCombinedImageSamplerDescriptor::bind(MVKCommandEncoder* cmdEncoder,
											 MVKDescriptorSetLayoutBinding* mvkDSLBind,
											 uint32_t descriptorIndex,
											 bool stages[],
											 MVKShaderResourceBinding& mtlIndexes,
											 MVKArrayRef<uint32_t> dynamicOffsets,
											 uint32_t& dynamicOffsetIndex) {
	MVKImageDescriptor::bind(cmdEncoder, mvkDSLBind, descriptorIndex, stages, mtlIndexes, dynamicOffsets, dynamicOffsetIndex);
	MVKSamplerDescriptorMixin::bind(cmdEncoder, mvkDSLBind, descriptorIndex, stages, mtlIndexes, dynamicOffsets, dynamicOffsetIndex);
}

void MVKCombinedImageSamplerDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
											  uint32_t srcIndex,
											  size_t stride,
											  const void* pData) {
	MVKImageDescriptor::write(mvkDSLBind, srcIndex, stride, pData);
	MVKSamplerDescriptorMixin::write(mvkDSLBind, srcIndex, stride, pData);

	// Update the Metal argument buffer entry
	uint8_t planeCount = _mvkImageView ? _mvkImageView->getPlaneCount() : 1;
	id<MTLSamplerState> mtlSampler = _mvkSampler ? _mvkSampler->getMTLSamplerState() : nil;
	mvkDSLBind->writeToMetalArgumentBuffer(mtlSampler, mvkDSLBind->getDescriptorCount() * planeCount + srcIndex);
}

void MVKCombinedImageSamplerDescriptor::read(uint32_t dstIndex,
											 VkDescriptorImageInfo* pImageInfo,
											 VkDescriptorBufferInfo* pBufferInfo,
											 VkBufferView* pTexelBufferView,
											 VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	MVKImageDescriptor::read(dstIndex, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
	MVKSamplerDescriptorMixin::read(dstIndex, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
}

void MVKCombinedImageSamplerDescriptor::setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) {
	MVKImageDescriptor::setLayout(dslBinding, index);
	MVKSamplerDescriptorMixin::setLayout(dslBinding, index);
}

void MVKCombinedImageSamplerDescriptor::reset() {
	MVKSamplerDescriptorMixin::reset();
	MVKImageDescriptor::reset();
}


#pragma mark -
#pragma mark MVKTexelBufferDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKTexelBufferDescriptor::bind(MVKCommandEncoder* cmdEncoder,
									MVKDescriptorSetLayoutBinding* mvkDSLBind,
									uint32_t descriptorIndex,
									bool stages[],
									MVKShaderResourceBinding& mtlIndexes,
									MVKArrayRef<uint32_t> dynamicOffsets,
									uint32_t& dynamicOffsetIndex) {
	MVKMTLTextureBinding tb;
	MVKMTLBufferBinding bb;
	VkDescriptorType descType = getDescriptorType();
	if (_mvkBufferView) {
		tb.mtlTexture = _mvkBufferView->getMTLTexture();
		if (descType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
			id<MTLTexture> mtlTex = tb.mtlTexture;
			bb.mtlBuffer = mtlTex.buffer;
			bb.offset = mtlTex.bufferOffset;
			bb.size = (uint32_t)(mtlTex.height * mtlTex.bufferBytesPerRow);
		}
	}
	if (mvkDSLBind->usingMetalArgumentBuffer()) {
		MVKMTLArgumentBufferResourceUsage abru;
		abru.mtlResource = tb.mtlResource;
		abru.mtlUsage = getMTLResourceUsage();
		abru.mtlStages = mvkMTLRenderStagesFromMVKShaderStages(stages);
		if (cmdEncoder) { cmdEncoder->useArgumentBufferResource(abru, stages[kMVKShaderStageCompute]); }
		if (descType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
			abru.mtlResource = bb.mtlResource;
			if (cmdEncoder) { cmdEncoder->useArgumentBufferResource(abru, stages[kMVKShaderStageCompute]); }
		}
	} else {
		// If not using Metal argument buffer, bind discretely
		for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
			if (stages[i]) {
				tb.index = mtlIndexes.stages[i].textureIndex + descriptorIndex;
				if (cmdEncoder) { cmdEncoder->bindTexture(tb, MVKShaderStage(i)); }
				if (descType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
					bb.index = mtlIndexes.stages[i].bufferIndex + descriptorIndex;
					if (cmdEncoder) { cmdEncoder->bindBuffer(bb, MVKShaderStage(i)); }
				}
			}
		}
	}
}

void MVKTexelBufferDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t srcIndex,
									 size_t stride,
									 const void* pData) {
	auto* oldBuffView = _mvkBufferView;

	const auto* pBuffView = &get<VkBufferView>(pData, stride, srcIndex);
	_mvkBufferView = (MVKBufferView*)*pBuffView;

	if (_mvkBufferView) { _mvkBufferView->retain(); }
	if (oldBuffView) { oldBuffView->release(); }

	// Update the Metal argument buffer entry
	id<MTLTexture> mtlTexture = _mvkBufferView ? _mvkBufferView->getMTLTexture() : nil;
	mvkDSLBind->writeToMetalArgumentBuffer(mtlTexture, 1, 0, srcIndex);

	if (getDescriptorType() == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
		uint32_t buffArgIdx = mvkDSLBind->getDescriptorCount() + srcIndex;
		mvkDSLBind->writeToMetalArgumentBuffer(mtlTexture.buffer, mtlTexture.bufferOffset, buffArgIdx);
	}
}

void MVKTexelBufferDescriptor::read(uint32_t dstIndex,
									VkDescriptorImageInfo* pImageInfo,
									VkDescriptorBufferInfo* pBufferInfo,
									VkBufferView* pTexelBufferView,
									VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	pTexelBufferView[dstIndex] = (VkBufferView)_mvkBufferView;
}

void MVKTexelBufferDescriptor::reset() {
	if (_mvkBufferView) { _mvkBufferView->release(); }
	_mvkBufferView = nullptr;
	MVKDescriptor::reset();
}
