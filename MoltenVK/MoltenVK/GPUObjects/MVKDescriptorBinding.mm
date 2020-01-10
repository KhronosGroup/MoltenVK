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
uint32_t MVKDescriptorSetLayoutBinding::bind(MVKCommandEncoder* cmdEncoder,
											 MVKDescriptorSet* descSet,
											 uint32_t descStartIndex,
											 MVKShaderResourceBinding& dslMTLRezIdxOffsets,
											 MVKVector<uint32_t>& dynamicOffsets,
											 uint32_t* pDynamicOffsetIndex) {

	// Establish the resource indices to use, by combining the offsets of the DSL and this DSL binding.
    MVKShaderResourceBinding mtlIdxs = _mtlResourceIndexOffsets + dslMTLRezIdxOffsets;

	uint32_t descCnt = _info.descriptorCount;
    for (uint32_t descIdx = 0; descIdx < descCnt; descIdx++) {
		MVKDescriptorBinding* descBinding = descSet->getDescriptor(descStartIndex + descIdx);
		descBinding->bind(cmdEncoder, _info.descriptorType, descIdx, _applyToStage,
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
		mvkSampler->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdPushDescriptorSet/vkCmdPushDescriptorSetWithTemplate(): Depth texture samplers using a compare operation can only be used as immutable samplers on this device.");
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

MVKVulkanAPIObject* MVKDescriptorBinding::getVulkanAPIObject() { return nullptr; };

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorBinding::bind(MVKCommandEncoder* cmdEncoder,
								VkDescriptorType descriptorType,
								uint32_t descriptorIndex,
								bool stages[],
								MVKShaderResourceBinding& mtlIndexes,
								MVKVector<uint32_t>& dynamicOffsets,
								uint32_t* pDynamicOffsetIndex) {
	MVKMTLBufferBinding bb;
	MVKMTLTextureBinding tb;
	MVKMTLSamplerStateBinding sb;
	NSUInteger bufferDynamicOffset = 0;

	switch (descriptorType) {

			// After determining dynamic part of offset (zero otherwise), fall through to non-dynamic handling
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			bufferDynamicOffset = dynamicOffsets[*pDynamicOffsetIndex];
			(*pDynamicOffsetIndex)++;           // Move on to next dynamic offset (and feedback to caller)
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER: {
			MVKBuffer* mvkBuff = (MVKBuffer*)_bufferBinding.buffer;
			bb.mtlBuffer = _mtlBuffer;
			bb.offset = _mtlBufferOffset + bufferDynamicOffset;
			bb.size = mvkBuff ? (uint32_t)mvkBuff->getByteCount() : 0;
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

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: {
			bb.mtlBuffer = _mtlBuffer;
			bb.offset = _mtlBufferOffset;
			bb.size = _inlineBinding.dataSize;
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

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT: {
			tb.mtlTexture = _mtlTexture;
			if (descriptorType == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE && tb.mtlTexture) {
				tb.swizzle = ((MVKImageView*)_imageBinding.imageView)->getPackedSwizzle();
			} else {
				tb.swizzle = 0;
			}
			for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
				if (stages[i]) {
					tb.index = mtlIndexes.stages[i].textureIndex + descriptorIndex;
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
			sb.mtlSamplerState = _mtlSampler;
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

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			tb.mtlTexture = _mtlTexture;
			if (tb.mtlTexture) {
				tb.swizzle = ((MVKImageView*)_imageBinding.imageView)->getPackedSwizzle();
			} else {
				tb.swizzle = 0;
			}
			sb.mtlSamplerState = _mtlSampler;
			for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
				if (stages[i]) {
					tb.index = mtlIndexes.stages[i].textureIndex + descriptorIndex;
					sb.index = mtlIndexes.stages[i].samplerIndex + descriptorIndex;
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

void MVKDescriptorBinding::write(MVKDescriptorSet* mvkDescSet,
								 VkDescriptorType descriptorType,
								 uint32_t srcIndex,
								 size_t stride,
								 const void* pData) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER: {
			const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcIndex);
			auto* oldSampler = (MVKSampler*)_imageBinding.sampler;
			_imageBinding = *pImgInfo;
			_imageBinding.imageView = nullptr;		// Sampler only. Guard against app not explicitly clearing ImageView.
			if (_hasDynamicSampler) {
				auto* mvkSampler = (MVKSampler*)pImgInfo->sampler;
				validate(mvkSampler);
				mvkSampler->retain();
				_mtlSampler = mvkSampler ? mvkSampler->getMTLSamplerState() : nil;
			} else {
				_imageBinding.sampler = nullptr;	// Guard against app not explicitly clearing Sampler.
			}
			if (oldSampler) {
				oldSampler->release();
			}
			break;
		}
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcIndex);
			auto* mvkImageView = (MVKImageView*)pImgInfo->imageView;
			auto* oldImageView = (MVKImageView*)_imageBinding.imageView;
			auto* oldSampler = (MVKSampler*)_imageBinding.sampler;
			mvkImageView->retain();
			_imageBinding = *pImgInfo;
			_mtlTexture = mvkImageView ? mvkImageView->getMTLTexture() : nil;
			if (_hasDynamicSampler) {
				auto* mvkSampler = (MVKSampler*)pImgInfo->sampler;
				validate(mvkSampler);
				mvkSampler->retain();
				_mtlSampler = mvkSampler ? mvkSampler->getMTLSamplerState() : nil;
			} else {
				_imageBinding.sampler = nullptr;	// Guard against app not explicitly clearing Sampler.
			}
			if (oldImageView) {
				oldImageView->release();
			}
			if (oldSampler) {
				oldSampler->release();
			}
			break;
		}

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT: {
			const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcIndex);
			auto* mvkImageView = (MVKImageView*)pImgInfo->imageView;
			auto* oldImageView = (MVKImageView*)_imageBinding.imageView;
			if (mvkImageView) {
				mvkImageView->retain();
			}
			_imageBinding = *pImgInfo;
			_imageBinding.sampler = nullptr;		// ImageView only. Guard against app not explicitly clearing Sampler.
			_mtlTexture = mvkImageView ? mvkImageView->getMTLTexture() : nil;
			if (oldImageView) {
				oldImageView->release();
			}
			break;
		}

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: {
			const auto* pBuffInfo = &get<VkDescriptorBufferInfo>(pData, stride, srcIndex);
			auto* oldBuff = (MVKBuffer*)_bufferBinding.buffer;
			_bufferBinding = *pBuffInfo;
			auto* mtlBuff = (MVKBuffer*)pBuffInfo->buffer;
			if (mtlBuff) {
				mtlBuff->retain();
			}
			_mtlBuffer = mtlBuff ? mtlBuff->getMTLBuffer() : nil;
			_mtlBufferOffset = mtlBuff ? (mtlBuff->getMTLBufferOffset() + pBuffInfo->offset) : 0;
			if (oldBuff) {
				oldBuff->release();
			}
			break;
		}

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER: {
			const auto* pBuffView = &get<VkBufferView>(pData, stride, srcIndex);
			auto* mvkBuffView = (MVKBufferView*)*pBuffView;
			auto* oldBuffView = (MVKBufferView*)_texelBufferBinding;
			if (mvkBuffView) {
				mvkBuffView->retain();
			}
			_texelBufferBinding = *pBuffView;
			_mtlTexture = mvkBuffView ? mvkBuffView->getMTLTexture() : nil;
			if (oldBuffView) {
				oldBuffView->release();
			}
			break;
		}

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: {
			const auto& srcInlineUniformBlock = get<VkWriteDescriptorSetInlineUniformBlockEXT>(pData, stride, srcIndex);
			auto& dstInlineUniformBlock = _inlineBinding;
			if (srcInlineUniformBlock.dataSize != 0) {
				MTLResourceOptions mtlBuffOpts = MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache;
				_mtlBuffer = [mvkDescSet->getMTLDevice() newBufferWithBytes:srcInlineUniformBlock.pData length:srcInlineUniformBlock.dataSize options:mtlBuffOpts];
			} else {
				_mtlBuffer = nil;
			}
			dstInlineUniformBlock.dataSize = srcInlineUniformBlock.dataSize;
			dstInlineUniformBlock.pData = nullptr;
			break;
		}

		default:
			break;
	}
}

void MVKDescriptorBinding::read(MVKDescriptorSet* mvkDescSet,
								VkDescriptorType descriptorType,
								uint32_t dstIndex,
								VkDescriptorImageInfo* pImageInfo,
								VkDescriptorBufferInfo* pBufferInfo,
								VkBufferView* pTexelBufferView,
								VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	switch (descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			pImageInfo[dstIndex] = _imageBinding;
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			pBufferInfo[dstIndex] = _bufferBinding;
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			pTexelBufferView[dstIndex] = _texelBufferBinding;
			break;

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT: {
			const auto& srcInlineUniformBlock = _inlineBinding;
			auto& dstInlineUniformBlock = pInlineUniformBlock[dstIndex];
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
			break;
		}

		default:
			break;
	}
}

// If depth compare is required, but unavailable on the device, the sampler can only be used as an immutable sampler
bool MVKDescriptorBinding::validate(MVKSampler* mvkSampler) {
	if (mvkSampler->getRequiresConstExprSampler()) {
		mvkSampler->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkUpdateDescriptorSets(): Depth texture samplers using a compare operation can only be used as immutable samplers on this device.");
		return false;
	}
	return true;
}

void MVKDescriptorBinding::setLayout(MVKDescriptorSetLayoutBinding* dslBinding, uint32_t index) {
	switch (dslBinding->_info.descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			// If the descriptor set layout binding contains immutable samplers, immediately populate
			// the corresponding Metal sampler in this descriptor from it. Otherwise add a null
			// placeholder that will be populated dynamically at a later time.
			auto imtblSamps = dslBinding->_immutableSamplers;
			_hasDynamicSampler = imtblSamps.empty();
			_mtlSampler = _hasDynamicSampler ? nil : imtblSamps[index]->getMTLSamplerState();
			break;
		}

		default:
			_hasDynamicSampler = false;
			_mtlSampler = nil;
			break;
	}
}

MVKDescriptorBinding::~MVKDescriptorBinding() {
	if (_imageBinding.imageView) { ((MVKImageView*)_imageBinding.imageView)->release(); }
	if (_imageBinding.sampler) { ((MVKSampler*)_imageBinding.sampler)->release(); }
	if (_bufferBinding.buffer) { ((MVKBuffer*)_bufferBinding.buffer)->release(); }
	if (_texelBufferBinding) { ((MVKBufferView*)_texelBufferBinding)->release(); }
}
