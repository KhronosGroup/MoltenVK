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
#include "MVKBuffer.h"


#pragma mark MVKShaderStageResourceBinding

MVKShaderStageResourceBinding MVKShaderStageResourceBinding::operator+ (const MVKShaderStageResourceBinding& rhs) {
	MVKShaderStageResourceBinding rslt;
	rslt.bufferIndex = this->bufferIndex + rhs.bufferIndex;
	rslt.textureIndex = this->textureIndex + rhs.textureIndex;
	rslt.samplerIndex = this->samplerIndex + rhs.samplerIndex;
	return rslt;
}

MVKShaderStageResourceBinding& MVKShaderStageResourceBinding::operator+= (const MVKShaderStageResourceBinding& rhs) {
	this->bufferIndex += rhs.bufferIndex;
	this->textureIndex += rhs.textureIndex;
	this->samplerIndex += rhs.samplerIndex;
	return *this;
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
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
		rslt.stages[i] = this->stages[i] + rhs.stages[i];
	}
	return rslt;
}

MVKShaderResourceBinding& MVKShaderResourceBinding::operator+= (const MVKShaderResourceBinding& rhs) {
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
		this->stages[i] += rhs.stages[i];
	}
	return *this;
}


#pragma mark -
#pragma mark MVKDescriptorSetLayoutBinding

MVKVulkanAPIObject* MVKDescriptorSetLayoutBinding::getVulkanAPIObject() { return _layout; };

MVKSampler* MVKDescriptorSetLayoutBinding::getImmutableSampler(uint32_t index) {
	return (index < _immutableSamplers.size()) ? _immutableSamplers[index] : nullptr;
}

// A null cmdEncoder can be passed to perform a validation pass
uint32_t MVKDescriptorSetLayoutBinding::bind(MVKCommandEncoder* cmdEncoder,
											 MVKDescriptorSet* descSet,
											 uint32_t descStartIndex,
											 MVKShaderResourceBinding& dslMTLRezIdxOffsets,
											 MVKArrayRef<uint32_t> dynamicOffsets,
											 uint32_t* pDynamicOffsetIndex) {

	// Establish the resource indices to use, by combining the offsets of the DSL and this DSL binding.
    MVKShaderResourceBinding mtlIdxs = _mtlResourceIndexOffsets + dslMTLRezIdxOffsets;

	uint32_t descCnt = _info.descriptorCount;
    for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
		MVKDescriptor* mvkDesc = descSet->getDescriptor(descStartIndex + descIdx);
		mvkDesc->bind(cmdEncoder, _info.descriptorType, descIdx, _applyToStage,
					  mtlIdxs, dynamicOffsets, pDynamicOffsetIndex);
    }
	return descCnt;
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

                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        bb.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
                        if (i == kMVKShaderStageCompute) {
							if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindBuffer(bb); }
                        } else {
							if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindBuffer(MVKShaderStage(i), bb); }
                        }
                    }
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: {
                const auto& inlineUniformBlock = get<VkWriteDescriptorSetInlineUniformBlockEXT>(pData, stride, rezIdx - dstArrayElement);
                bb.mtlBytes = inlineUniformBlock.pData;
                bb.size = inlineUniformBlock.dataSize;
                bb.isInline = true;
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        bb.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
                        if (i == kMVKShaderStageCompute) {
                            if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindBuffer(bb); }
                        } else {
                            if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindBuffer(MVKShaderStage(i), bb); }
                        }
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
                    tb.swizzle = (_info.descriptorType == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE) ? imageView->getPackedSwizzle(0) : 0;
                    if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
                        id<MTLTexture> mtlTex = tb.mtlTexture;
                        if (mtlTex.parentTexture) { mtlTex = mtlTex.parentTexture; }
                        bb.mtlBuffer = mtlTex.buffer;
                        bb.offset = mtlTex.bufferOffset;
                        bb.size = (uint32_t)(mtlTex.height * mtlTex.bufferBytesPerRow);
                    }
                    for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                        if (_applyToStage[i]) {
                            tb.index = mtlIdxs.stages[i].textureIndex + rezIdx + planeIndex;
                            if (i == kMVKShaderStageCompute) {
                                if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindTexture(tb); }
                            } else {
                                if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindTexture(MVKShaderStage(i), tb); }
                            }
                            if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
                                bb.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
                                if (i == kMVKShaderStageCompute) {
                                    if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindBuffer(bb); }
                                } else {
                                    if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindBuffer(MVKShaderStage(i), bb); }
                                }
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
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        tb.index = mtlIdxs.stages[i].textureIndex + rezIdx;
                        if (i == kMVKShaderStageCompute) {
							if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindTexture(tb); }
                        } else {
							if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindTexture(MVKShaderStage(i), tb); }
                        }
                        if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
                            bb.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
                            if (i == kMVKShaderStageCompute) {
                                if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindBuffer(bb); }
                            } else {
                                if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindBuffer(MVKShaderStage(i), bb); }
                            }
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
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        sb.index = mtlIdxs.stages[i].samplerIndex + rezIdx;
                        if (i == kMVKShaderStageCompute) {
							if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindSamplerState(sb); }
                        } else {
							if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindSamplerState(MVKShaderStage(i), sb); }
                        }
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
                    tb.swizzle = (imageView) ? imageView->getPackedSwizzle(0) : 0;
                    MVKSampler* sampler;
                    if (_immutableSamplers.empty()) {
                        sampler = (MVKSampler*)imageInfo.sampler;
                        validate(sampler);
                    } else {
                        sampler = _immutableSamplers[rezIdx];
                    }
                    sb.mtlSamplerState = sampler->getMTLSamplerState();
                    for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                        if (_applyToStage[i]) {
                            tb.index = mtlIdxs.stages[i].textureIndex + rezIdx + planeIndex;
                            sb.index = mtlIdxs.stages[i].samplerIndex + rezIdx;
                            if (i == kMVKShaderStageCompute) {
                                if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindTexture(tb); }
                                if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindSamplerState(sb); }
                            } else {
                                if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindTexture(MVKShaderStage(i), tb); }
                                if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindSamplerState(MVKShaderStage(i), sb); }
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
    for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
        if (_applyToStage[i]) {
            mvkPopulateShaderConverterContext(context,
                                              mtlIdxs.stages[i],
                                              models[i],
                                              dslIndex,
                                              _info.binding,
											  mvkSamp);
        }
    }
}

MVKDescriptorSetLayoutBinding::MVKDescriptorSetLayoutBinding(MVKDevice* device,
															 MVKDescriptorSetLayout* layout,
                                                             const VkDescriptorSetLayoutBinding* pBinding) : MVKBaseDeviceObject(device), _layout(layout) {

	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
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

    _info = *pBinding;
    _info.pImmutableSamplers = nullptr;     // Remove dangling pointer
}

MVKDescriptorSetLayoutBinding::MVKDescriptorSetLayoutBinding(const MVKDescriptorSetLayoutBinding& binding) :
	MVKBaseDeviceObject(binding._device), _layout(binding._layout),
	_info(binding._info), _immutableSamplers(binding._immutableSamplers),
	_mtlResourceIndexOffsets(binding._mtlResourceIndexOffsets) {

	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
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
    switch (pBinding->descriptorType) {
        case VK_DESCRIPTOR_TYPE_SAMPLER:
            pBindingIndexes->samplerIndex = pDescSetCounts->samplerIndex;
            pDescSetCounts->samplerIndex += pBinding->descriptorCount;

			if (pBinding->descriptorCount > 1 && !_device->_pMetalFeatures->arrayOfSamplers) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of samplers.", _device->getName()));
			}
            break;

        case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
            pBindingIndexes->textureIndex = pDescSetCounts->textureIndex;
            pDescSetCounts->textureIndex += pBinding->descriptorCount;
            pBindingIndexes->samplerIndex = pDescSetCounts->samplerIndex;
            pDescSetCounts->samplerIndex += pBinding->descriptorCount;

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
            pBindingIndexes->bufferIndex = pDescSetCounts->bufferIndex;
            pDescSetCounts->bufferIndex += pBinding->descriptorCount;
            // fallthrough
        case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
        case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
        case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
            pBindingIndexes->textureIndex = pDescSetCounts->textureIndex;
            pDescSetCounts->textureIndex += pBinding->descriptorCount;

			if (pBinding->descriptorCount > 1 && !_device->_pMetalFeatures->arrayOfTextures) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of textures.", _device->getName()));
			}
            break;

        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
        case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
        case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
        case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
            pBindingIndexes->bufferIndex = pDescSetCounts->bufferIndex;
            pDescSetCounts->bufferIndex += pBinding->descriptorCount;
            break;

        default:
            break;
    }
}


#pragma mark -
#pragma mark MVKBufferDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKBufferDescriptor::bind(MVKCommandEncoder* cmdEncoder,
							   VkDescriptorType descriptorType,
							   uint32_t descriptorIndex,
							   bool stages[],
							   MVKShaderResourceBinding& mtlIndexes,
							   MVKArrayRef<uint32_t> dynamicOffsets,
							   uint32_t* pDynamicOffsetIndex) {
	MVKMTLBufferBinding bb;
	NSUInteger bufferDynamicOffset = 0;

	switch (descriptorType) {
		// After determining dynamic part of offset (zero otherwise), fall through to non-dynamic handling
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			if (dynamicOffsets.size > *pDynamicOffsetIndex) {
				bufferDynamicOffset = dynamicOffsets[(*pDynamicOffsetIndex)++];	// Move on to next dynamic offset (and feedback to caller)
			}
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER: {
			if (_mvkBuffer) {
				bb.mtlBuffer = _mvkBuffer->getMTLBuffer();
				bb.offset = _mvkBuffer->getMTLBufferOffset() + _buffOffset + bufferDynamicOffset;
				if (_buffRange == VK_WHOLE_SIZE)
					bb.size = (uint32_t)(_mvkBuffer->getByteCount() - bb.offset);
				else
					bb.size = (uint32_t)_buffRange;
			}
			for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
				if (stages[i]) {
					bb.index = mtlIndexes.stages[i].bufferIndex + descriptorIndex;
					if (i == kMVKShaderStageCompute) {
						if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindBuffer(bb); }
					} else {
						if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindBuffer(MVKShaderStage(i), bb); }
					}
				}
			}
			break;
		}

		default:
			break;
	}
}

void MVKBufferDescriptor::write(MVKDescriptorSet* mvkDescSet,
								VkDescriptorType descriptorType,
								uint32_t srcIndex,
								size_t stride,
								const void* pData) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: {
			auto* oldBuff = _mvkBuffer;

			const auto* pBuffInfo = &get<VkDescriptorBufferInfo>(pData, stride, srcIndex);
			_mvkBuffer = (MVKBuffer*)pBuffInfo->buffer;
			_buffOffset = pBuffInfo->offset;
			_buffRange = pBuffInfo->range;

			if (_mvkBuffer) { _mvkBuffer->retain(); }
			if (oldBuff) { oldBuff->release(); }
			break;
		}

		default:
			break;
	}
}

void MVKBufferDescriptor::read(MVKDescriptorSet* mvkDescSet,
							   VkDescriptorType descriptorType,
							   uint32_t dstIndex,
							   VkDescriptorImageInfo* pImageInfo,
							   VkDescriptorBufferInfo* pBufferInfo,
							   VkBufferView* pTexelBufferView,
							   VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: {
			auto& buffInfo = pBufferInfo[dstIndex];
			buffInfo.buffer = (VkBuffer)_mvkBuffer;
			buffInfo.offset = _buffOffset;
			buffInfo.range = _buffRange;
			break;
		}

		default:
			break;
	}
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
										   VkDescriptorType descriptorType,
										   uint32_t descriptorIndex,
										   bool stages[],
										   MVKShaderResourceBinding& mtlIndexes,
										   MVKArrayRef<uint32_t> dynamicOffsets,
										   uint32_t* pDynamicOffsetIndex) {
	MVKMTLBufferBinding bb;

	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: {
			bb.mtlBuffer = _mtlBuffer;
			bb.size = _dataSize;
			for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
				if (stages[i]) {
					bb.index = mtlIndexes.stages[i].bufferIndex + descriptorIndex;
					if (i == kMVKShaderStageCompute) {
						if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindBuffer(bb); }
					} else {
						if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindBuffer(MVKShaderStage(i), bb); }
					}
				}
			}
			break;
		}

		default:
			break;
	}
}

void MVKInlineUniformBlockDescriptor::write(MVKDescriptorSet* mvkDescSet,
									   VkDescriptorType descriptorType,
									   uint32_t srcIndex,
									   size_t stride,
									   const void* pData) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: {
			const auto& srcInlineUniformBlock = get<VkWriteDescriptorSetInlineUniformBlockEXT>(pData, stride, srcIndex);
			_dataSize = srcInlineUniformBlock.dataSize;

			[_mtlBuffer release];
			if (srcInlineUniformBlock.dataSize > 0) {
				MTLResourceOptions mtlBuffOpts = MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache;
				_mtlBuffer = [mvkDescSet->getMTLDevice() newBufferWithBytes: srcInlineUniformBlock.pData
																	 length: srcInlineUniformBlock.dataSize
																	options:mtlBuffOpts];	// retained
			} else {
				_mtlBuffer = nil;
			}

			break;
		}

		default:
			break;
	}
}

void MVKInlineUniformBlockDescriptor::read(MVKDescriptorSet* mvkDescSet,
									  VkDescriptorType descriptorType,
									  uint32_t dstIndex,
									  VkDescriptorImageInfo* pImageInfo,
									  VkDescriptorBufferInfo* pBufferInfo,
									  VkBufferView* pTexelBufferView,
									  VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: {
			auto& dstInlineUniformBlock = pInlineUniformBlock[dstIndex];
			void* pDstData = const_cast<void*>(dstInlineUniformBlock.pData);
			void* pSrcData = _mtlBuffer.contents;
			if (pSrcData && pDstData) {
				memcpy(pDstData, pSrcData, _dataSize);
				dstInlineUniformBlock.dataSize = _dataSize;
			} else {
				dstInlineUniformBlock.dataSize = 0;
			}
			break;
		}

		default:
			break;
	}
}

void MVKInlineUniformBlockDescriptor::reset() {
	[_mtlBuffer release];
	_mtlBuffer = nil;
	_dataSize = 0;
	MVKDescriptor::reset();
}


#pragma mark -
#pragma mark MVKImageDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKImageDescriptor::bind(MVKCommandEncoder* cmdEncoder,
							  VkDescriptorType descriptorType,
							  uint32_t descriptorIndex,
							  bool stages[],
							  MVKShaderResourceBinding& mtlIndexes,
							  MVKArrayRef<uint32_t> dynamicOffsets,
							  uint32_t* pDynamicOffsetIndex) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			break;

		default:
			return;
	}
    
    uint8_t planeCount = (_mvkImageView) ? _mvkImageView->getPlaneCount() : 1;
    for (uint8_t planeIndex = 0; planeIndex < planeCount; planeIndex++) {
        MVKMTLTextureBinding tb;
        MVKMTLBufferBinding bb;
        
        if (_mvkImageView) {
            tb.mtlTexture = _mvkImageView->getMTLTexture(planeIndex);
        }
        tb.swizzle = ((descriptorType == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE ||
                       descriptorType == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) &&
                       tb.mtlTexture) ? _mvkImageView->getPackedSwizzle(planeIndex) : 0;
        if (descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE && tb.mtlTexture) {
            id<MTLTexture> mtlTex = tb.mtlTexture;
            if (mtlTex.parentTexture) { mtlTex = mtlTex.parentTexture; }
            bb.mtlBuffer = mtlTex.buffer;
            bb.offset = mtlTex.bufferOffset;
            bb.size = (uint32_t)(mtlTex.height * mtlTex.bufferBytesPerRow);
        }
        for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
            if (stages[i]) {
                tb.index = mtlIndexes.stages[i].textureIndex + descriptorIndex + planeIndex;
                if (i == kMVKShaderStageCompute) {
                    if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindTexture(tb); }
                } else {
                    if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindTexture(MVKShaderStage(i), tb); }
                }
                if (descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
                    bb.index = mtlIndexes.stages[i].bufferIndex + descriptorIndex + planeIndex;
                    if (i == kMVKShaderStageCompute) {
                        if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindBuffer(bb); }
                    } else {
                        if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindBuffer(MVKShaderStage(i), bb); }
                    }
                }
            }
        }
    }
}

void MVKImageDescriptor::write(MVKDescriptorSet* mvkDescSet,
							   VkDescriptorType descriptorType,
							   uint32_t srcIndex,
							   size_t stride,
							   const void* pData) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			auto* oldImgView = _mvkImageView;

			const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcIndex);
			_mvkImageView = (MVKImageView*)pImgInfo->imageView;
			_imageLayout = pImgInfo->imageLayout;

			if (_mvkImageView) { _mvkImageView->retain(); }
			if (oldImgView) { oldImgView->release(); }

			break;
		}

		default:
			break;
	}
}

void MVKImageDescriptor::read(MVKDescriptorSet* mvkDescSet,
							  VkDescriptorType descriptorType,
							  uint32_t dstIndex,
							  VkDescriptorImageInfo* pImageInfo,
							  VkDescriptorBufferInfo* pBufferInfo,
							  VkBufferView* pTexelBufferView,
							  VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			auto& imgInfo = pImageInfo[dstIndex];
			imgInfo.imageView = (VkImageView)_mvkImageView;
			imgInfo.imageLayout = _imageLayout;
			break;
		}

		default:
			break;
	}
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
void MVKSamplerDescriptorMixin::bind(MVKCommandEncoder* cmdEncoder,
									 VkDescriptorType descriptorType,
									 uint32_t descriptorIndex,
									 bool stages[],
									 MVKShaderResourceBinding& mtlIndexes,
									 MVKArrayRef<uint32_t> dynamicOffsets,
									 uint32_t* pDynamicOffsetIndex) {
	MVKMTLSamplerStateBinding sb;
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			if (_mvkSampler) {
				sb.mtlSamplerState = _mvkSampler->getMTLSamplerState();
			}
			for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
				if (stages[i]) {
					sb.index = mtlIndexes.stages[i].samplerIndex + descriptorIndex;
					if (i == kMVKShaderStageCompute) {
						if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindSamplerState(sb); }
					} else {
						if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindSamplerState(MVKShaderStage(i), sb); }
					}
				}
			}
			break;
		}

		default:
			break;
	}
}

void MVKSamplerDescriptorMixin::write(MVKDescriptorSet* mvkDescSet,
									  VkDescriptorType descriptorType,
									  uint32_t srcIndex,
									  size_t stride,
									  const void* pData) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
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
			break;
		}

		default:
			break;
	}
}

void MVKSamplerDescriptorMixin::read(MVKDescriptorSet* mvkDescSet,
									 VkDescriptorType descriptorType,
									 uint32_t dstIndex,
									 VkDescriptorImageInfo* pImageInfo,
									 VkDescriptorBufferInfo* pBufferInfo,
									 VkBufferView* pTexelBufferView,
									 VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			auto& imgInfo = pImageInfo[dstIndex];
			imgInfo.sampler = _hasDynamicSampler ? (VkSampler)_mvkSampler : nullptr;
			break;
		}

		default:
			break;
	}
}

void MVKSamplerDescriptorMixin::setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) {
	auto* oldSamp = _mvkSampler;

	_mvkSampler = nullptr;
	_hasDynamicSampler = true;

	switch (dslBinding->getDescriptorType()) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			// If the descriptor set layout binding contains immutable samplers, use them
			// Otherwise they will be populated dynamically at a later time.
			MVKSampler* imtSamp = dslBinding->getImmutableSampler(index);
			if (imtSamp) {
				_mvkSampler = imtSamp;
				_hasDynamicSampler = false;
			}
			break;
		}

		default:
			break;
	}

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
								VkDescriptorType descriptorType,
								uint32_t descriptorIndex,
								bool stages[],
								MVKShaderResourceBinding& mtlIndexes,
								MVKArrayRef<uint32_t> dynamicOffsets,
								uint32_t* pDynamicOffsetIndex) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER: {
			MVKSamplerDescriptorMixin::bind(cmdEncoder, descriptorType, descriptorIndex, stages,
											mtlIndexes, dynamicOffsets, pDynamicOffsetIndex);
			break;
		}

		default:
			break;
	}
}

void MVKSamplerDescriptor::write(MVKDescriptorSet* mvkDescSet,
								 VkDescriptorType descriptorType,
								 uint32_t srcIndex,
								 size_t stride,
								 const void* pData) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER: {
			MVKSamplerDescriptorMixin::write(mvkDescSet, descriptorType, srcIndex, stride, pData);
			break;
		}

		default:
			break;
	}
}

void MVKSamplerDescriptor::read(MVKDescriptorSet* mvkDescSet,
								VkDescriptorType descriptorType,
								uint32_t dstIndex,
								VkDescriptorImageInfo* pImageInfo,
								VkDescriptorBufferInfo* pBufferInfo,
								VkBufferView* pTexelBufferView,
								VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER: {
			MVKSamplerDescriptorMixin::read(mvkDescSet, descriptorType, dstIndex, pImageInfo,
											pBufferInfo, pTexelBufferView, pInlineUniformBlock);
			break;
		}

		default:
			break;
	}
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
											 VkDescriptorType descriptorType,
											 uint32_t descriptorIndex,
											 bool stages[],
											 MVKShaderResourceBinding& mtlIndexes,
											 MVKArrayRef<uint32_t> dynamicOffsets,
											 uint32_t* pDynamicOffsetIndex) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			MVKImageDescriptor::bind(cmdEncoder, descriptorType, descriptorIndex, stages,
									 mtlIndexes, dynamicOffsets, pDynamicOffsetIndex);
			MVKSamplerDescriptorMixin::bind(cmdEncoder, descriptorType, descriptorIndex, stages,
											mtlIndexes, dynamicOffsets, pDynamicOffsetIndex);
			break;
		}

		default:
			break;
	}
}

void MVKCombinedImageSamplerDescriptor::write(MVKDescriptorSet* mvkDescSet,
											  VkDescriptorType descriptorType,
											  uint32_t srcIndex,
											  size_t stride,
											  const void* pData) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			MVKImageDescriptor::write(mvkDescSet, descriptorType, srcIndex, stride, pData);
			MVKSamplerDescriptorMixin::write(mvkDescSet, descriptorType, srcIndex, stride, pData);
			break;
		}

		default:
			break;
	}
}

void MVKCombinedImageSamplerDescriptor::read(MVKDescriptorSet* mvkDescSet,
											 VkDescriptorType descriptorType,
											 uint32_t dstIndex,
											 VkDescriptorImageInfo* pImageInfo,
											 VkDescriptorBufferInfo* pBufferInfo,
											 VkBufferView* pTexelBufferView,
											 VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			MVKImageDescriptor::read(mvkDescSet, descriptorType, dstIndex, pImageInfo,
									 pBufferInfo, pTexelBufferView, pInlineUniformBlock);
			MVKSamplerDescriptorMixin::read(mvkDescSet, descriptorType, dstIndex, pImageInfo,
											pBufferInfo, pTexelBufferView, pInlineUniformBlock);
			break;
		}

		default:
			break;
	}
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
									VkDescriptorType descriptorType,
									uint32_t descriptorIndex,
									bool stages[],
									MVKShaderResourceBinding& mtlIndexes,
									MVKArrayRef<uint32_t> dynamicOffsets,
									uint32_t* pDynamicOffsetIndex) {
	MVKMTLTextureBinding tb;
	MVKMTLBufferBinding bb;
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER: {
			if (_mvkBufferView) {
				tb.mtlTexture = _mvkBufferView->getMTLTexture();
				if (descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
					id<MTLTexture> mtlTex = tb.mtlTexture;
					bb.mtlBuffer = mtlTex.buffer;
					bb.offset = mtlTex.bufferOffset;
					bb.size = (uint32_t)(mtlTex.height * mtlTex.bufferBytesPerRow);
				}
			}
			for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
				if (stages[i]) {
					tb.index = mtlIndexes.stages[i].textureIndex + descriptorIndex;
					if (i == kMVKShaderStageCompute) {
						if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindTexture(tb); }
					} else {
						if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindTexture(MVKShaderStage(i), tb); }
					}
					if (descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER) {
						bb.index = mtlIndexes.stages[i].bufferIndex + descriptorIndex;
						if (i == kMVKShaderStageCompute) {
							if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindBuffer(bb); }
						} else {
							if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindBuffer(MVKShaderStage(i), bb); }
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

void MVKTexelBufferDescriptor::write(MVKDescriptorSet* mvkDescSet,
									 VkDescriptorType descriptorType,
									 uint32_t srcIndex,
									 size_t stride,
									 const void* pData) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER: {
			auto* oldBuffView = _mvkBufferView;

			const auto* pBuffView = &get<VkBufferView>(pData, stride, srcIndex);
			_mvkBufferView = (MVKBufferView*)*pBuffView;

			if (_mvkBufferView) { _mvkBufferView->retain(); }
			if (oldBuffView) { oldBuffView->release(); }

			break;
		}

		default:
			break;
	}
}

void MVKTexelBufferDescriptor::read(MVKDescriptorSet* mvkDescSet,
									VkDescriptorType descriptorType,
									uint32_t dstIndex,
									VkDescriptorImageInfo* pImageInfo,
									VkDescriptorBufferInfo* pBufferInfo,
									VkBufferView* pTexelBufferView,
									VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER: {
			pTexelBufferView[dstIndex] = (VkBufferView)_mvkBufferView;
			break;
		}

		default:
			break;
	}
}

void MVKTexelBufferDescriptor::reset() {
	if (_mvkBufferView) { _mvkBufferView->release(); }
	_mvkBufferView = nullptr;
	MVKDescriptor::reset();
}
