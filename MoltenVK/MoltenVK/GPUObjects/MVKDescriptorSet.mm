/*
 * MVKDescriptorSetLayout.mm
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include <stdlib.h>

using namespace std;


#pragma mark MVKShaderStageResourceBinding

MVK_PUBLIC_SYMBOL MVKShaderStageResourceBinding MVKShaderStageResourceBinding::operator+ (const MVKShaderStageResourceBinding& rhs) {
	MVKShaderStageResourceBinding rslt;
	rslt.bufferIndex = this->bufferIndex + rhs.bufferIndex;
	rslt.textureIndex = this->textureIndex + rhs.textureIndex;
	rslt.samplerIndex = this->samplerIndex + rhs.samplerIndex;
	return rslt;
}

MVK_PUBLIC_SYMBOL MVKShaderStageResourceBinding& MVKShaderStageResourceBinding::operator+= (const MVKShaderStageResourceBinding& rhs) {
	this->bufferIndex += rhs.bufferIndex;
	this->textureIndex += rhs.textureIndex;
	this->samplerIndex += rhs.samplerIndex;
	return *this;
}


#pragma mark MVKShaderResourceBinding

MVK_PUBLIC_SYMBOL MVKShaderResourceBinding MVKShaderResourceBinding::operator+ (const MVKShaderResourceBinding& rhs) {
	MVKShaderResourceBinding rslt;
	rslt.vertexStage = this->vertexStage + rhs.vertexStage;
	rslt.fragmentStage = this->fragmentStage + rhs.fragmentStage;
    rslt.computeStage = this->computeStage + rhs.computeStage;
	return rslt;
}

MVK_PUBLIC_SYMBOL MVKShaderResourceBinding& MVKShaderResourceBinding::operator+= (const MVKShaderResourceBinding& rhs) {
	this->vertexStage += rhs.vertexStage;
	this->fragmentStage += rhs.fragmentStage;
    this->computeStage += rhs.computeStage;
	return *this;
}


#pragma mark -
#pragma mark MVKDescriptorSetLayoutBinding

void MVKDescriptorSetLayoutBinding::bind(MVKCommandEncoder* cmdEncoder,
                                         MVKDescriptorBinding& descBinding,
                                         MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                         vector<uint32_t>& dynamicOffsets,
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
                bb.mtlBuffer = descBinding._mtlBuffers[rezIdx];
                bb.offset = descBinding._mtlBufferOffsets[rezIdx] + bufferDynamicOffset;
                if (_applyToVertexStage) {
                    bb.index = mtlIdxs.vertexStage.bufferIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindVertexBuffer(bb);
                }
                if (_applyToFragmentStage) {
                    bb.index = mtlIdxs.fragmentStage.bufferIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindFragmentBuffer(bb);
                }
                if (_applyToComputeStage) {
                    bb.index = mtlIdxs.computeStage.bufferIndex + rezIdx;
                    cmdEncoder->_computeResourcesState.bindBuffer(bb);
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
            case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
            case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
            case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
            case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT: {
                tb.mtlTexture = descBinding._mtlTextures[rezIdx];
                if (_applyToVertexStage) {
                    tb.index = mtlIdxs.vertexStage.textureIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindVertexTexture(tb);
                }
                if (_applyToFragmentStage) {
                    tb.index = mtlIdxs.fragmentStage.textureIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindFragmentTexture(tb);
                }
                if (_applyToComputeStage) {
                    tb.index = mtlIdxs.computeStage.textureIndex + rezIdx;
                    cmdEncoder->_computeResourcesState.bindTexture(tb);
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_SAMPLER: {
                sb.mtlSamplerState = descBinding._mtlSamplers[rezIdx];
                if (_applyToVertexStage) {
                    sb.index = mtlIdxs.vertexStage.samplerIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindVertexSamplerState(sb);
                }
                if (_applyToFragmentStage) {
                    sb.index = mtlIdxs.fragmentStage.samplerIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindFragmentSamplerState(sb);
                }
                if (_applyToComputeStage) {
                    sb.index = mtlIdxs.computeStage.samplerIndex + rezIdx;
                    cmdEncoder->_computeResourcesState.bindSamplerState(sb);
                }
                break;
            }

            case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
                tb.mtlTexture = descBinding._mtlTextures[rezIdx];
                sb.mtlSamplerState = descBinding._mtlSamplers[rezIdx];
                if (_applyToVertexStage) {
                    tb.index = mtlIdxs.vertexStage.textureIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindVertexTexture(tb);
                    sb.index = mtlIdxs.vertexStage.samplerIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindVertexSamplerState(sb);
                }
                if (_applyToFragmentStage) {
                    tb.index = mtlIdxs.fragmentStage.textureIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindFragmentTexture(tb);
                    sb.index = mtlIdxs.fragmentStage.samplerIndex + rezIdx;
                    cmdEncoder->_graphicsResourcesState.bindFragmentSamplerState(sb);
                }
                if (_applyToComputeStage) {
                    tb.index = mtlIdxs.computeStage.textureIndex + rezIdx;
                    cmdEncoder->_computeResourcesState.bindTexture(tb);
                    sb.index = mtlIdxs.computeStage.samplerIndex + rezIdx;
                    cmdEncoder->_computeResourcesState.bindSamplerState(sb);
                }
                break;
            }

            default:
                break;
        }
    }
}

void MVKDescriptorSetLayoutBinding::populateShaderConverterContext(SPIRVToMSLConverterContext& context,
                                                                   MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                                                   uint32_t dslIndex) {

    // Establish the resource indices to use, by combining the offsets of the DSL and this DSL binding.
    MVKShaderResourceBinding mtlIdxs = _mtlResourceIndexOffsets + dslMTLRezIdxOffsets;

    if (_applyToVertexStage) {
        mvkPopulateShaderConverterContext(context,
                                          mtlIdxs.vertexStage,
                                          spv::ExecutionModelVertex,
                                          dslIndex,
                                          _info.binding);
    }

    if (_applyToFragmentStage) {
        mvkPopulateShaderConverterContext(context,
                                          mtlIdxs.fragmentStage,
                                          spv::ExecutionModelFragment,
                                          dslIndex,
                                          _info.binding);
    }

    if (_applyToComputeStage) {
        mvkPopulateShaderConverterContext(context,
                                          mtlIdxs.computeStage,
                                          spv::ExecutionModelGLCompute,
                                          dslIndex,
                                          _info.binding);
    }
}

MVKDescriptorSetLayoutBinding::MVKDescriptorSetLayoutBinding(MVKDescriptorSetLayout* layout,
                                                             const VkDescriptorSetLayoutBinding* pBinding) : MVKConfigurableObject() {

    //    MVKLogDebug("Creating MVKDescriptorSetLayoutBinding binding %d.", pBinding->binding);

    // Determine the shader stages used by this binding
    _applyToVertexStage = mvkAreFlagsEnabled(pBinding->stageFlags, VK_SHADER_STAGE_VERTEX_BIT);
    _applyToFragmentStage = mvkAreFlagsEnabled(pBinding->stageFlags, VK_SHADER_STAGE_FRAGMENT_BIT);
    _applyToComputeStage = mvkAreFlagsEnabled(pBinding->stageFlags, VK_SHADER_STAGE_COMPUTE_BIT);

    // If this binding is used by the vertex shader, set the Metal resource index
    if (_applyToVertexStage) {
        setConfigurationResult(initMetalResourceIndexOffsets(&_mtlResourceIndexOffsets.vertexStage,
                                                             &layout->_mtlResourceCounts.vertexStage, pBinding));
    }

    // If this binding is used by the fragment shader, set the Metal resource index
    if (_applyToFragmentStage) {
        setConfigurationResult(initMetalResourceIndexOffsets(&_mtlResourceIndexOffsets.fragmentStage,
                                                             &layout->_mtlResourceCounts.fragmentStage, pBinding));
    }

    // If this binding is used by a compute shader, set the Metal resource index
    if (_applyToComputeStage) {
        setConfigurationResult(initMetalResourceIndexOffsets(&_mtlResourceIndexOffsets.computeStage,
                                                             &layout->_mtlResourceCounts.computeStage, pBinding));
    }

    // If immutable samplers are defined, copy them in
    if ( pBinding->pImmutableSamplers &&
        (pBinding->descriptorType == VK_DESCRIPTOR_TYPE_SAMPLER ||
         pBinding->descriptorType == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) ) {
            _immutableSamplers.reserve(pBinding->descriptorCount);
            for (uint32_t i = 0; i < pBinding->descriptorCount; i++) {
                _immutableSamplers.push_back((MVKSampler*)pBinding->pImmutableSamplers[i]);
            }
        }

    _info = *pBinding;
    _info.pImmutableSamplers = nullptr;     // Remove dangling pointer
}

/**
 * Sets the appropriate Metal resource indexes within this binding from the 
 * specified descriptor set binding counts, and updates those counts accordingly.
 */
VkResult MVKDescriptorSetLayoutBinding::initMetalResourceIndexOffsets(MVKShaderStageResourceBinding* pBindingIndexes,
                                                                      MVKShaderStageResourceBinding* pDescSetCounts,
                                                                      const VkDescriptorSetLayoutBinding* pBinding) {
    switch (pBinding->descriptorType) {
        case VK_DESCRIPTOR_TYPE_SAMPLER:
            pBindingIndexes->samplerIndex = pDescSetCounts->samplerIndex;
            pDescSetCounts->samplerIndex += pBinding->descriptorCount;
            break;

        case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
            pBindingIndexes->textureIndex = pDescSetCounts->textureIndex;
            pDescSetCounts->textureIndex += pBinding->descriptorCount;
            pBindingIndexes->samplerIndex = pDescSetCounts->samplerIndex;
            pDescSetCounts->samplerIndex += pBinding->descriptorCount;
            break;

        case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
        case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
        case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
        case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
        case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
            pBindingIndexes->textureIndex = pDescSetCounts->textureIndex;
            pDescSetCounts->textureIndex += pBinding->descriptorCount;
            break;

        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
        case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
        case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
            pBindingIndexes->bufferIndex = pDescSetCounts->bufferIndex;
            pDescSetCounts->bufferIndex += pBinding->descriptorCount;
            break;

        default:
            break;
    }
    return VK_SUCCESS;
}


#pragma mark -
#pragma mark MVKDescriptorSetLayout

void MVKDescriptorSetLayout::bindDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                               MVKDescriptorSet* descSet,
                                               MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                               vector<uint32_t>& dynamicOffsets,
                                               uint32_t* pDynamicOffsetIndex) {

    uint32_t bindCnt = (uint32_t)_bindings.size();
    for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
        _bindings[bindIdx].bind(cmdEncoder, descSet->_bindings[bindIdx],
                                dslMTLRezIdxOffsets, dynamicOffsets,
                                pDynamicOffsetIndex);
    }
}

void MVKDescriptorSetLayout::populateShaderConverterContext(SPIRVToMSLConverterContext& context,
                                                            MVKShaderResourceBinding& dslMTLRezIdxOffsets,
															uint32_t dslIndex) {
	uint32_t bindCnt = (uint32_t)_bindings.size();
	for (uint32_t bindIdx = 0; bindIdx < bindCnt; bindIdx++) {
		_bindings[bindIdx].populateShaderConverterContext(context, dslMTLRezIdxOffsets, dslIndex);
	}
}

MVKDescriptorSetLayout::MVKDescriptorSetLayout(MVKDevice* device,
                                               const VkDescriptorSetLayoutCreateInfo* pCreateInfo) : MVKBaseDeviceObject(device) {
    // Create the descriptor bindings
    _bindings.reserve(pCreateInfo->bindingCount);
    for (uint32_t i = 0; i < pCreateInfo->bindingCount; i++) {
        _bindings.emplace_back(this, &pCreateInfo->pBindings[i]);
        setConfigurationResult(_bindings.back().getConfigurationResult());
    }
}


#pragma mark -
#pragma mark MVKDescriptorBinding

uint32_t MVKDescriptorBinding::writeBindings(uint32_t srcStartIndex,
											 uint32_t dstStartIndex,
											 uint32_t count,
											 const VkDescriptorImageInfo* pImageInfo,
											 const VkDescriptorBufferInfo* pBufferInfo,
											 const VkBufferView* pTexelBufferView) {

	uint32_t dstCnt = MIN(count, _pBindingLayout->_info.descriptorCount - dstStartIndex);

	switch (_pBindingLayout->_info.descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
			for (uint32_t i = 0; i < dstCnt; i++) {
				uint32_t dstIdx = dstStartIndex + i;
				const VkDescriptorImageInfo* pImgInfo = &pImageInfo[srcStartIndex + i];
				_imageBindings[dstIdx] = *pImgInfo;
				if (_hasDynamicSamplers) {
					_mtlSamplers[dstIdx] = ((MVKSampler*)pImgInfo->sampler)->getMTLSamplerState();
				}
			}
			break;

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			for (uint32_t i = 0; i < dstCnt; i++) {
				uint32_t dstIdx = dstStartIndex + i;
				const VkDescriptorImageInfo* pImgInfo = &pImageInfo[srcStartIndex + i];
				_imageBindings[dstIdx] = *pImgInfo;
				_mtlTextures[dstIdx] = ((MVKImageView*)pImgInfo->imageView)->getMTLTexture();
				if (_hasDynamicSamplers) {
					_mtlSamplers[dstIdx] = ((MVKSampler*)pImgInfo->sampler)->getMTLSamplerState();
				}
			}
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			for (uint32_t i = 0; i < dstCnt; i++) {
				uint32_t dstIdx = dstStartIndex + i;
				const VkDescriptorImageInfo* pImgInfo = &pImageInfo[srcStartIndex + i];
				_imageBindings[dstIdx] = *pImgInfo;
				_mtlTextures[dstIdx] = ((MVKImageView*)pImgInfo->imageView)->getMTLTexture();
			}
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			for (uint32_t i = 0; i < dstCnt; i++) {
				uint32_t dstIdx = dstStartIndex + i;
				const VkDescriptorBufferInfo* pBuffInfo = &pBufferInfo[srcStartIndex + i];
				_bufferBindings[dstIdx] = *pBuffInfo;
                MVKBuffer* mtlBuff = (MVKBuffer*)pBuffInfo->buffer;
				_mtlBuffers[dstIdx] = mtlBuff->getMTLBuffer();
				_mtlBufferOffsets[dstIdx] = mtlBuff->getMTLBufferOffset() + pBuffInfo->offset;
			}
			break;

        case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
        case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
            for (uint32_t i = 0; i < dstCnt; i++) {
                uint32_t dstIdx = dstStartIndex + i;
                const VkBufferView* pBuffView = &pTexelBufferView[srcStartIndex + i];
                _texelBufferBindings[dstIdx] = *pBuffView;
                _mtlTextures[dstIdx] = ((MVKBufferView*)*pBuffView)->getMTLTexture();
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
											VkDescriptorImageInfo* pImageInfo,
											VkDescriptorBufferInfo* pBufferInfo,
											VkBufferView* pTexelBufferView) {

	uint32_t srcCnt = MIN(count, _pBindingLayout->_info.descriptorCount - srcStartIndex);

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

		default:
			break;
	}

	return count - srcCnt;
}

bool MVKDescriptorBinding::hasBinding(uint32_t binding) {
    return _pBindingLayout->_info.binding == binding;
}

MVKDescriptorBinding::MVKDescriptorBinding(MVKDescriptorSetLayoutBinding* pBindingLayout) : MVKBaseObject() {

	uint32_t descCnt = pBindingLayout->_info.descriptorCount;

	// Create space for the binding and Metal resources and populate with NULL and zero values
	switch (pBindingLayout->_info.descriptorType) {
		case VK_DESCRIPTOR_TYPE_SAMPLER:
			_imageBindings.resize(descCnt, VkDescriptorImageInfo());
			initMTLSamplers(pBindingLayout);
			break;

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			_imageBindings.resize(descCnt, VkDescriptorImageInfo());
			_mtlTextures.resize(descCnt, VK_NULL_HANDLE);
			initMTLSamplers(pBindingLayout);
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			_imageBindings.resize(descCnt, VkDescriptorImageInfo());
			_mtlTextures.resize(descCnt, VK_NULL_HANDLE);
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			_bufferBindings.resize(descCnt, VkDescriptorBufferInfo());
			_mtlBuffers.resize(descCnt, VK_NULL_HANDLE);
			_mtlBufferOffsets.resize(descCnt, 0);
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			_texelBufferBindings.resize(descCnt, VK_NULL_HANDLE);
            _mtlTextures.resize(descCnt, VK_NULL_HANDLE);
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
        _mtlSamplers.push_back(_hasDynamicSamplers ? VK_NULL_HANDLE : imtblSamps[i]->getMTLSamplerState());
    }
}


#pragma mark -
#pragma mark MVKDescriptorSet

template<typename DescriptorAction>
void MVKDescriptorSet::writeDescriptorSets(const DescriptorAction* pDescriptorAction,
                                           const VkDescriptorImageInfo* pImageInfo,
                                           const VkDescriptorBufferInfo* pBufferInfo,
                                           const VkBufferView* pTexelBufferView) {
    uint32_t dstStartIdx = pDescriptorAction->dstArrayElement;
    uint32_t binding = pDescriptorAction->dstBinding;
    uint32_t origCnt = pDescriptorAction->descriptorCount;
    uint32_t remainCnt = origCnt;

//    MVKLogDebug("Writing descriptor sets with buffer info %p starting at binding point %d.", pBufferInfo, binding);

    MVKDescriptorBinding* mvkDescBind = getBinding(binding);
    while (mvkDescBind && remainCnt > 0) {

//        MVKLogDebug("Writing MVKDescriptorBinding with binding point %d.", binding);

        uint32_t srcStartIdx = origCnt - remainCnt;
        remainCnt = mvkDescBind->writeBindings(srcStartIdx, dstStartIdx, remainCnt,
                                               pImageInfo, pBufferInfo, pTexelBufferView);

        binding++;                              // If not consumed, move to next consecutive binding point
        mvkDescBind = getBinding(binding);
        dstStartIdx = 0;                        // Subsequent bindings start reading at first element
    }
}

// Create concrete implementations of the two variations of the writeDescriptorSets() function.
template void MVKDescriptorSet::writeDescriptorSets<VkWriteDescriptorSet>(const VkWriteDescriptorSet* pDescriptorAction,
																		  const VkDescriptorImageInfo* pImageInfo,
																		  const VkDescriptorBufferInfo* pBufferInfo,
																		  const VkBufferView* pTexelBufferView);
template void MVKDescriptorSet::writeDescriptorSets<VkCopyDescriptorSet>(const VkCopyDescriptorSet* pDescriptorAction,
																		 const VkDescriptorImageInfo* pImageInfo,
																		 const VkDescriptorBufferInfo* pBufferInfo,
																		 const VkBufferView* pTexelBufferView);

void MVKDescriptorSet::readDescriptorSets(const VkCopyDescriptorSet* pDescriptorCopy,
										  VkDescriptorImageInfo* pImageInfo,
										  VkDescriptorBufferInfo* pBufferInfo,
										  VkBufferView* pTexelBufferView) {
	uint32_t srcStartIdx = pDescriptorCopy->srcArrayElement;
    uint32_t binding = pDescriptorCopy->srcBinding;
    uint32_t origCnt = pDescriptorCopy->descriptorCount;
    uint32_t remainCnt = origCnt;

//    MVKLogDebug("Reading descriptor sets with buffer info %p starting at binding point %d.", pBufferInfo, binding);

    MVKDescriptorBinding* mvkDescBind = getBinding(binding);
    while (mvkDescBind && remainCnt > 0) {

//        MVKLogDebug("Reading MVKDescriptorBinding with binding point %d.", binding);

        uint32_t dstStartIdx = origCnt - remainCnt;
        remainCnt = mvkDescBind->readBindings(srcStartIdx, dstStartIdx, remainCnt,
                                              pImageInfo, pBufferInfo, pTexelBufferView);

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

MVKDescriptorSet::MVKDescriptorSet(MVKDevice* device,
								   MVKDescriptorSetLayout* layout) : MVKBaseDeviceObject(device) {

	// Create the binding slots, each referencing a corresponding binding layout
	uint32_t bindCnt = (uint32_t)layout->_bindings.size();
	_bindings.reserve(bindCnt);
	for (uint32_t i = 0; i < bindCnt; i++) {
        _bindings.emplace_back(&layout->_bindings[i]);
	}
}


#pragma mark -
#pragma mark MVKDescriptorPool

VkResult MVKDescriptorPool::allocateDescriptorSets(uint32_t count,
												   const VkDescriptorSetLayout* pSetLayouts,
												   VkDescriptorSet* pDescriptorSets) {
	if (_allocatedSetCount + count > _maxSets) {
		return mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "The maximum number of descriptor sets that can be allocated by this descriptor pool is %d.", _maxSets);
	}

	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		MVKDescriptorSetLayout* mvkDSL = (MVKDescriptorSetLayout*)pSetLayouts[dsIdx];
		MVKDescriptorSet* mvkDescSet = new MVKDescriptorSet(_device, mvkDSL);
		_allocatedSets.push_front(mvkDescSet);
		pDescriptorSets[dsIdx] = (VkDescriptorSet)mvkDescSet;
		_allocatedSetCount++;
	}
	return VK_SUCCESS;
}

VkResult MVKDescriptorPool::freeDescriptorSets(uint32_t count, const VkDescriptorSet* pDescriptorSets) {
	for (uint32_t dsIdx = 0; dsIdx < count; dsIdx++) {
		MVKDescriptorSet* mvkDS = (MVKDescriptorSet*)pDescriptorSets[dsIdx];
		if (mvkDS) {
			_allocatedSets.remove(mvkDS);
			_allocatedSetCount--;
			mvkDS->destroy();
		}
	}
	return VK_SUCCESS;
}

VkResult MVKDescriptorPool::reset(VkDescriptorPoolResetFlags flags) {
	mvkDestroyContainerContents(_allocatedSets);
	_allocatedSetCount = 0;
	return VK_SUCCESS;
}

MVKDescriptorPool::MVKDescriptorPool(MVKDevice* device,
									 const VkDescriptorPoolCreateInfo* pCreateInfo) : MVKBaseDeviceObject(device) {
	_maxSets = pCreateInfo->maxSets;
	_allocatedSetCount = 0;
}

// TODO: Destroying a descriptor pool implicitly destroys all descriptor sets created from it.

MVKDescriptorPool::~MVKDescriptorPool() {
//	MVKLogDebug("Pool %p destroyed with %d descriptor sets.", this, _allocatedSetCount);
	reset(0);
}


#pragma mark -
#pragma mark Support functions

/** Updates the resource bindings in the descriptor sets inditified in the specified content. */
void mvkUpdateDescriptorSets(uint32_t writeCount,
							 const VkWriteDescriptorSet* pDescriptorWrites,
							 uint32_t copyCount,
							 const VkCopyDescriptorSet* pDescriptorCopies) {

	// Perform the write updates
	for (uint32_t i = 0; i < writeCount; i++) {
		const VkWriteDescriptorSet* pDescWrite = &pDescriptorWrites[i];
		MVKDescriptorSet* dstSet = (MVKDescriptorSet*)pDescWrite->dstSet;
		dstSet->writeDescriptorSets(pDescWrite,
									pDescWrite->pImageInfo,
									pDescWrite->pBufferInfo,
									pDescWrite->pTexelBufferView);
	}

	// Perform the copy updates by reading bindings from one set and writing to other set.
	for (uint32_t i = 0; i < copyCount; i++) {
		const VkCopyDescriptorSet* pDescCopy = &pDescriptorCopies[i];

		uint32_t descCnt = pDescCopy->descriptorCount;
		VkDescriptorImageInfo imgInfos[descCnt];
		VkDescriptorBufferInfo buffInfos[descCnt];
		VkBufferView texelBuffInfos[descCnt];

		MVKDescriptorSet* srcSet = (MVKDescriptorSet*)pDescCopy->srcSet;
		srcSet->readDescriptorSets(pDescCopy, imgInfos, buffInfos, texelBuffInfos);

		MVKDescriptorSet* dstSet = (MVKDescriptorSet*)pDescCopy->dstSet;
		dstSet->writeDescriptorSets(pDescCopy, imgInfos, buffInfos, texelBuffInfos);
	}
}

void mvkPopulateShaderConverterContext(SPIRVToMSLConverterContext& context,
									   MVKShaderStageResourceBinding& ssRB,
									   spv::ExecutionModel stage,
									   uint32_t descriptorSetIndex,
									   uint32_t bindingIndex) {
	MSLResourceBinding ctxRB;
    ctxRB.stage = stage;
    ctxRB.descriptorSet = descriptorSetIndex;
    ctxRB.binding = bindingIndex;
    ctxRB.mslBuffer = ssRB.bufferIndex;
    ctxRB.mslTexture = ssRB.textureIndex;
    ctxRB.mslSampler = ssRB.samplerIndex;
    context.resourceBindings.push_back(ctxRB);
}


