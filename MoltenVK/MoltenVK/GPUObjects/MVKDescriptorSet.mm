/*
 * MVKDescriptorSetLayout.mm
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKBuffer.h"
#include "MVKFoundation.h"
#include "MVKLogging.h"
#include "mvk_datatypes.hpp"
#include <stdlib.h>

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
    MVKMTLInlineBinding ib;
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
                ib.mtlBytes = descBinding._inlineBindings[rezIdx].pData;
                ib.size = descBinding._inlineBindings[rezIdx].dataSize;
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        ib.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
                        if (i == kMVKShaderStageCompute) {
                            if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindInline(ib); }
                        } else {
                            if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindInline(MVKShaderStage(i), ib); }
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
    MVKMTLInlineBinding ib;

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
                bb.offset = bufferInfo.offset;
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
                ib.mtlBytes = inlineUniformBlock.pData;
                ib.size = inlineUniformBlock.dataSize;
                for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
                    if (_applyToStage[i]) {
                        ib.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
                        if (i == kMVKShaderStageCompute) {
                            if (cmdEncoder) { cmdEncoder->_computeResourcesState.bindInline(ib); }
                        } else {
                            if (cmdEncoder) { cmdEncoder->_graphicsResourcesState.bindInline(MVKShaderStage(i), ib); }
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
#pragma mark MVKDescriptorSetLayout

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayout::bindDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                               MVKDescriptorSet* descSet,
                                               MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                               MVKVector<uint32_t>& dynamicOffsets,
                                               uint32_t* pDynamicOffsetIndex) {

    if (_isPushDescriptorLayout) return;

	clearConfigurationResult();
    uint32_t bindCnt = (uint32_t)_bindings.size();
    for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
        _bindings[bindIdx].bind(cmdEncoder, descSet->_bindings[bindIdx],
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
	for (VkWriteDescriptorSetInlineUniformBlockEXT& inlineUniformBlock : _inlineBindings) {
		if (inlineUniformBlock.pData) {
			delete [] reinterpret_cast<const uint8_t*>(inlineUniformBlock.pData);
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


#pragma mark -
#pragma mark MVKDescriptorSet

template<typename DescriptorAction>
void MVKDescriptorSet::writeDescriptorSets(const DescriptorAction* pDescriptorAction,
                                           size_t stride, const void* pData) {
    uint32_t dstStartIdx = pDescriptorAction->dstArrayElement;
    uint32_t binding = pDescriptorAction->dstBinding;
    uint32_t origCnt = pDescriptorAction->descriptorCount;
    uint32_t remainCnt = origCnt;

    MVKDescriptorBinding* mvkDescBind = getBinding(binding);
    while (mvkDescBind && remainCnt > 0) {
        uint32_t srcStartIdx = origCnt - remainCnt;
        remainCnt = mvkDescBind->writeBindings(srcStartIdx, dstStartIdx, remainCnt,
                                               stride, pData);
        binding++;                              // If not consumed, move to next consecutive binding point
        mvkDescBind = getBinding(binding);
        dstStartIdx = 0;                        // Subsequent bindings start reading at first element
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
	uint32_t srcStartIdx = pDescriptorCopy->srcArrayElement;
    uint32_t binding = pDescriptorCopy->srcBinding;
    uint32_t origCnt = pDescriptorCopy->descriptorCount;
    uint32_t remainCnt = origCnt;

    MVKDescriptorBinding* mvkDescBind = getBinding(binding);
    while (mvkDescBind && remainCnt > 0) {
        uint32_t dstStartIdx = origCnt - remainCnt;
        remainCnt = mvkDescBind->readBindings(srcStartIdx, dstStartIdx, remainCnt, descType,
                                              pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
        binding++;                              // If not consumed, move to next consecutive binding point
        mvkDescBind = getBinding(binding);
        srcStartIdx = 0;                        // Subsequent bindings start reading at first element
    }
}

// Returns the binding instance that is assigned the specified
// binding number, or returns null if no such binding exists.
MVKDescriptorBinding* MVKDescriptorSet::getBinding(uint32_t binding) {
    for (auto& mvkDB : _bindings) { if (mvkDB.hasBinding(binding)) { return &mvkDB; } }
    return nullptr;
}

// If the layout has changed, create the binding slots, each referencing a corresponding binding layout
void MVKDescriptorSet::setLayout(MVKDescriptorSetLayout* layout) {
	if (layout != _pLayout) {
		_pLayout = layout;
		uint32_t bindCnt = (uint32_t)layout->_bindings.size();

		_bindings.clear();
		_bindings.reserve(bindCnt);
		for (uint32_t i = 0; i < bindCnt; i++) {
			_bindings.emplace_back(this, &layout->_bindings[i]);
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
