/*
 * MVKDescriptorBinding.mm
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

#include "MVKDescriptorBinding.h"
#include "MVKDescriptorSet.h"
#include "MVKBuffer.h"

using namespace std;
using namespace mvk;


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

uint32_t MVKShaderResourceBinding::getMaxBufferIndex() {
	return max({stages[kMVKShaderStageVertex].bufferIndex, stages[kMVKShaderStageTessCtl].bufferIndex, stages[kMVKShaderStageTessEval].bufferIndex, stages[kMVKShaderStageFragment].bufferIndex, stages[kMVKShaderStageCompute].bufferIndex});
}

uint32_t MVKShaderResourceBinding::getMaxTextureIndex() {
	return max({stages[kMVKShaderStageVertex].textureIndex, stages[kMVKShaderStageTessCtl].textureIndex, stages[kMVKShaderStageTessEval].textureIndex, stages[kMVKShaderStageFragment].textureIndex, stages[kMVKShaderStageCompute].textureIndex});
}

uint32_t MVKShaderResourceBinding::getMaxSamplerIndex() {
	return max({stages[kMVKShaderStageVertex].samplerIndex, stages[kMVKShaderStageTessCtl].samplerIndex, stages[kMVKShaderStageTessEval].samplerIndex, stages[kMVKShaderStageFragment].samplerIndex, stages[kMVKShaderStageCompute].samplerIndex});
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

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayoutBinding::bind(MVKCommandEncoder* cmdEncoder,
                                         MVKDescriptorBinding& descBinding,
                                         MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                         MVKVector<uint32_t>& dynamicOffsets,
                                         uint32_t* pDynamicOffsetIndex) {
    MVKMTLBufferBinding bb;
    MVKMTLTextureBinding tb;
    MVKMTLSamplerStateBinding sb;
    NSUInteger bufferDynamicOffset = 0;

    // Establish the resource indices to use, by combining the offsets of the DSL and this DSL binding.
    MVKShaderResourceBinding mtlIdxs = _mtlResourceIndexOffsets + dslMTLRezIdxOffsets;

    for (uint32_t rezIdx = 0; rezIdx < _info.descriptorCount; rezIdx++) {
        switch (_info.descriptorType) {

            // After determining dynamic part of offset (zero otherwise), fall through to non-dynamic handling
            case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
            case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
                bufferDynamicOffset = dynamicOffsets[*pDynamicOffsetIndex];
                (*pDynamicOffsetIndex)++;           // Move on to next dynamic offset (and feedback to caller)
            case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
            case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER: {
				MVKBuffer* mvkBuff = (MVKBuffer*)descBinding._bufferBindings[rezIdx].buffer;
                bb.mtlBuffer = descBinding._mtlBuffers[rezIdx];
                bb.offset = descBinding._mtlBufferOffsets[rezIdx] + bufferDynamicOffset;
				bb.size = mvkBuff ? (uint32_t)mvkBuff->getByteCount() : 0;
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
                bb.mtlBuffer = descBinding._mtlBuffers[rezIdx];
                bb.offset = descBinding._mtlBufferOffsets[rezIdx];
                bb.size = descBinding._inlineBindings[rezIdx].dataSize;
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
            case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
            case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
            case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT: {
                tb.mtlTexture = descBinding._mtlTextures[rezIdx];
                if (_info.descriptorType == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE && tb.mtlTexture) {
                    tb.swizzle = ((MVKImageView*)descBinding._imageBindings[rezIdx].imageView)->getPackedSwizzle();
                } else {
                    tb.swizzle = 0;
                }
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        tb.index = mtlIdxs.stages[i].textureIndex + rezIdx;
                        if (i == kMVKShaderStageCompute) {
							if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindTexture(tb); }
                        } else {
							if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindTexture(MVKShaderStage(i), tb); }
                        }
                    }
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_SAMPLER: {
                sb.mtlSamplerState = descBinding._mtlSamplers[rezIdx];
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
                tb.mtlTexture = descBinding._mtlTextures[rezIdx];
                if (tb.mtlTexture) {
                    tb.swizzle = ((MVKImageView*)descBinding._imageBindings[rezIdx].imageView)->getPackedSwizzle();
                } else {
                    tb.swizzle = 0;
                }
                sb.mtlSamplerState = descBinding._mtlSamplers[rezIdx];
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        tb.index = mtlIdxs.stages[i].textureIndex + rezIdx;
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
                break;
            }

            default:
                break;
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
				bb.size = (uint32_t)buffer->getByteCount();
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
                tb.mtlTexture = imageView->getMTLTexture();
                if (_info.descriptorType == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE && imageView) {
                    tb.swizzle = imageView->getPackedSwizzle();
                } else {
                    tb.swizzle = 0;
                }
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        tb.index = mtlIdxs.stages[i].textureIndex + rezIdx;
                        if (i == kMVKShaderStageCompute) {
							if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindTexture(tb); }
                        } else {
							if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindTexture(MVKShaderStage(i), tb); }
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
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        tb.index = mtlIdxs.stages[i].textureIndex + rezIdx;
                        if (i == kMVKShaderStageCompute) {
							if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindTexture(tb); }
                        } else {
							if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindTexture(MVKShaderStage(i), tb); }
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
                tb.mtlTexture = imageView->getMTLTexture();
                if (imageView) {
                    tb.swizzle = imageView->getPackedSwizzle();
                } else {
                    tb.swizzle = 0;
                }
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
                        tb.index = mtlIdxs.stages[i].textureIndex + rezIdx;
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
		_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkUpdateDescriptorSets(): Depth texture samplers using a compare operation can only be used as immutable samplers on this device."));
		return false;
	}
	return true;
}

void MVKDescriptorSetLayoutBinding::populateShaderConverterContext(SPIRVToMSLConversionConfiguration& context,
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
			}
            break;

        case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
        case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
        case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
        case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
        case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
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
#pragma mark MVKDescriptorBinding

MVKVulkanAPIObject* MVKDescriptorBinding::getVulkanAPIObject() { return _pDescSet->getVulkanAPIObject(); };

uint32_t MVKDescriptorBinding::writeBindings(uint32_t srcStartIndex,
											 uint32_t dstStartIndex,
											 uint32_t count,
											 size_t stride,
											 const void* pData) {

	uint32_t dstCnt = MIN(count, _pBindingLayout->_info.descriptorCount - dstStartIndex);

	switch (_pBindingLayout->_info.descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
			for (uint32_t i = 0; i < dstCnt; i++) {
				uint32_t dstIdx = dstStartIndex + i;
				const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcStartIndex + i);
				auto* oldSampler = (MVKSampler*)_imageBindings[dstIdx].sampler;
				_imageBindings[dstIdx] = *pImgInfo;
				_imageBindings[dstIdx].imageView = nullptr;		// Sampler only. Guard against app not explicitly clearing ImageView.
				if (_hasDynamicSamplers) {
					auto* mvkSampler = (MVKSampler*)pImgInfo->sampler;
					validate(mvkSampler);
					mvkSampler->retain();
					_mtlSamplers[dstIdx] = mvkSampler ? mvkSampler->getMTLSamplerState() : nil;
				} else {
					_imageBindings[dstIdx].sampler = nullptr;	// Guard against app not explicitly clearing Sampler.
				}
				if (oldSampler) {
					oldSampler->release();
				}
			}
			break;

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			for (uint32_t i = 0; i < dstCnt; i++) {
				uint32_t dstIdx = dstStartIndex + i;
				const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcStartIndex + i);
				auto* mvkImageView = (MVKImageView*)pImgInfo->imageView;
				auto* oldImageView = (MVKImageView*)_imageBindings[dstIdx].imageView;
				auto* oldSampler = (MVKSampler*)_imageBindings[dstIdx].sampler;
				mvkImageView->retain();
				_imageBindings[dstIdx] = *pImgInfo;
				_mtlTextures[dstIdx] = mvkImageView ? mvkImageView->getMTLTexture() : nil;
				if (_hasDynamicSamplers) {
					auto* mvkSampler = (MVKSampler*)pImgInfo->sampler;
					validate(mvkSampler);
					mvkSampler->retain();
					_mtlSamplers[dstIdx] = mvkSampler ? mvkSampler->getMTLSamplerState() : nil;
				} else {
					_imageBindings[dstIdx].sampler = nullptr;	// Guard against app not explicitly clearing Sampler.
				}
				if (oldImageView) {
					oldImageView->release();
				}
				if (oldSampler) {
					oldSampler->release();
				}
			}
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			for (uint32_t i = 0; i < dstCnt; i++) {
				uint32_t dstIdx = dstStartIndex + i;
				const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcStartIndex + i);
                auto* mvkImageView = (MVKImageView*)pImgInfo->imageView;
                auto* oldImageView = (MVKImageView*)_imageBindings[dstIdx].imageView;
                if (mvkImageView) {
                    mvkImageView->retain();
                }
				_imageBindings[dstIdx] = *pImgInfo;
				_imageBindings[dstIdx].sampler = nullptr;		// ImageView only. Guard against app not explicitly clearing Sampler.
				_mtlTextures[dstIdx] = mvkImageView ? mvkImageView->getMTLTexture() : nil;
                if (oldImageView) {
                    oldImageView->release();
                }
			}
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			for (uint32_t i = 0; i < dstCnt; i++) {
				uint32_t dstIdx = dstStartIndex + i;
				const auto* pBuffInfo = &get<VkDescriptorBufferInfo>(pData, stride, srcStartIndex + i);
				auto* oldBuff = (MVKBuffer*)_bufferBindings[dstIdx].buffer;
				_bufferBindings[dstIdx] = *pBuffInfo;
                auto* mtlBuff = (MVKBuffer*)pBuffInfo->buffer;
                if (mtlBuff) {
                    mtlBuff->retain();
                }
				_mtlBuffers[dstIdx] = mtlBuff ? mtlBuff->getMTLBuffer() : nil;
				_mtlBufferOffsets[dstIdx] = mtlBuff ? (mtlBuff->getMTLBufferOffset() + pBuffInfo->offset) : 0;
				if (oldBuff) {
					oldBuff->release();
				}
			}
			break;

        case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
        case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
            for (uint32_t i = 0; i < dstCnt; i++) {
                uint32_t dstIdx = dstStartIndex + i;
                const auto* pBuffView = &get<VkBufferView>(pData, stride, srcStartIndex + i);
                auto* mvkBuffView = (MVKBufferView*)*pBuffView;
				auto* oldBuffView = (MVKBufferView*)_texelBufferBindings[dstIdx];
                if (mvkBuffView) {
                    mvkBuffView->retain();
                }
                _texelBufferBindings[dstIdx] = *pBuffView;
                _mtlTextures[dstIdx] = mvkBuffView ? mvkBuffView->getMTLTexture() : nil;
				if (oldBuffView) {
					oldBuffView->release();
				}
            }
			break;

        case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
            for (uint32_t i = 0; i < dstCnt; i++) {
                uint32_t dstIdx = dstStartIndex + i;
                const auto& srcInlineUniformBlock = get<VkWriteDescriptorSetInlineUniformBlockEXT>(pData, stride, srcStartIndex + i);
                auto& dstInlineUniformBlock = _inlineBindings[dstIdx];
                if (srcInlineUniformBlock.dataSize != 0) {
                    MTLResourceOptions mtlBuffOpts = MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache;
                    _mtlBuffers[dstIdx] = [_pDescSet->getMTLDevice() newBufferWithBytes:srcInlineUniformBlock.pData length:srcInlineUniformBlock.dataSize options:mtlBuffOpts];
                } else {
                    _mtlBuffers[dstIdx] = nil;
                }
                dstInlineUniformBlock.dataSize = srcInlineUniformBlock.dataSize;
                dstInlineUniformBlock.pData = nullptr;
            }
            break;

		default:
			break;
	}

	return count - dstCnt;
}

uint32_t MVKDescriptorBinding::readBindings(uint32_t srcStartIndex,
											uint32_t dstStartIndex,
											uint32_t count,
											VkDescriptorType& descType,
											VkDescriptorImageInfo* pImageInfo,
											VkDescriptorBufferInfo* pBufferInfo,
											VkBufferView* pTexelBufferView,
											VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {

	uint32_t srcCnt = MIN(count, _pBindingLayout->_info.descriptorCount - srcStartIndex);

	descType = _pBindingLayout->_info.descriptorType;
	switch (_pBindingLayout->_info.descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			for (uint32_t i = 0; i < srcCnt; i++) {
				pImageInfo[dstStartIndex + i] = _imageBindings[srcStartIndex + i];
			}
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			for (uint32_t i = 0; i < srcCnt; i++) {
				pBufferInfo[dstStartIndex + i] = _bufferBindings[srcStartIndex + i];
			}
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			for (uint32_t i = 0; i < srcCnt; i++) {
				pTexelBufferView[dstStartIndex + i] = _texelBufferBindings[srcStartIndex + i];
			}
			break;

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			for (uint32_t i = 0; i < srcCnt; i++) {
				const auto& srcInlineUniformBlock = _inlineBindings[srcStartIndex + i];
				auto& dstInlineUniformBlock = pInlineUniformBlock[dstStartIndex + i];
				if (dstInlineUniformBlock.pData && dstInlineUniformBlock.pData != srcInlineUniformBlock.pData)
					delete [] reinterpret_cast<const uint8_t*>(dstInlineUniformBlock.pData);
				if (srcInlineUniformBlock.dataSize != 0) {
					dstInlineUniformBlock.pData = reinterpret_cast<const void*>(new uint8_t*[srcInlineUniformBlock.dataSize]);
					if (srcInlineUniformBlock.pData) {
						memcpy(const_cast<void*>(dstInlineUniformBlock.pData), srcInlineUniformBlock.pData, srcInlineUniformBlock.dataSize);
					}
				} else {
					dstInlineUniformBlock.pData = nullptr;
				}
				dstInlineUniformBlock.dataSize = srcInlineUniformBlock.dataSize;
			}
			break;

		default:
			break;
	}

	return count - srcCnt;
}

bool MVKDescriptorBinding::hasBinding(uint32_t binding) {
	return _pBindingLayout->_info.binding == binding;
}

MVKDescriptorBinding::MVKDescriptorBinding(MVKDescriptorSet* pDescSet, MVKDescriptorSetLayoutBinding* pBindingLayout) : _pDescSet(pDescSet) {

	uint32_t descCnt = pBindingLayout->_info.descriptorCount;

	// Create space for the binding and Metal resources and populate with NULL and zero values
	switch (pBindingLayout->_info.descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
			_imageBindings.resize(descCnt, VkDescriptorImageInfo());
			initMTLSamplers(pBindingLayout);
			break;

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			_imageBindings.resize(descCnt, VkDescriptorImageInfo());
			_mtlTextures.resize(descCnt, nil);
			initMTLSamplers(pBindingLayout);
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			_imageBindings.resize(descCnt, VkDescriptorImageInfo());
			_mtlTextures.resize(descCnt, nil);
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			_bufferBindings.resize(descCnt, VkDescriptorBufferInfo());
			_mtlBuffers.resize(descCnt, nil);
			_mtlBufferOffsets.resize(descCnt, 0);
			break;

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: {
			static const VkWriteDescriptorSetInlineUniformBlockEXT inlineUniformBlock {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK_EXT, nullptr, 0, nullptr};
			_inlineBindings.resize(descCnt, inlineUniformBlock);
            _mtlBuffers.resize(descCnt, nil);
            _mtlBufferOffsets.resize(descCnt, 0);
			break;
		}

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			_texelBufferBindings.resize(descCnt, nil);
            _mtlTextures.resize(descCnt, nil);
			break;

		default:
			break;
	}

    // Okay to hold layout as a pointer. From the Vulkan spec...
    // "VkDescriptorSetLayout objects may be accessed by commands that operate on descriptor
    //  sets allocated using that layout, and those descriptor sets must not be updated with
    //  vkUpdateDescriptorSets after the descriptor set layout has been destroyed.
    _pBindingLayout = pBindingLayout;
}

MVKDescriptorBinding::~MVKDescriptorBinding() {
	for (const VkDescriptorImageInfo& imgInfo : _imageBindings) {
		if (imgInfo.imageView) {
			((MVKImageView*)imgInfo.imageView)->release();
		}
		if (imgInfo.sampler) {
			((MVKSampler*)imgInfo.sampler)->release();
		}
	}
	for (const VkDescriptorBufferInfo& buffInfo : _bufferBindings) {
		if (buffInfo.buffer) {
			((MVKBuffer*)buffInfo.buffer)->release();
		}
	}
	for (VkBufferView buffView : _texelBufferBindings) {
		if (buffView) {
			((MVKBufferView*)buffView)->release();
		}
	}
}

/**
 * If the descriptor set layout binding contains immutable samplers, immediately populate
 * the corresponding Metal sampler in this descriptor binding from it. Otherwise add a null
 * placeholder that will be populated dynamically at a later time.
 */
void MVKDescriptorBinding::initMTLSamplers(MVKDescriptorSetLayoutBinding* pBindingLayout) {
    uint32_t descCnt = pBindingLayout->_info.descriptorCount;
    auto imtblSamps = pBindingLayout->_immutableSamplers;
    _hasDynamicSamplers = imtblSamps.empty();

    _mtlSamplers.reserve(descCnt);
    for (uint32_t i = 0; i < descCnt; i++) {
		_mtlSamplers.push_back(_hasDynamicSamplers ? nil : imtblSamps[i]->getMTLSamplerState());
    }
}
