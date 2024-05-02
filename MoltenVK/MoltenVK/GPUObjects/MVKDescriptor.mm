/*
 * MVKDescriptor.mm
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

#include "MVKDescriptor.h"
#include "MVKDescriptorSet.h"
#include "MVKBuffer.h"

#define BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bind, pipelineBindPoint, stage, ...) \
	do { \
		if ((stage) == kMVKShaderStageCompute) { \
			if ((cmdEncoder) && (pipelineBindPoint) == VK_PIPELINE_BIND_POINT_COMPUTE) \
				(cmdEncoder)->_computeResourcesState.bind(__VA_ARGS__); \
		} else { \
			if ((cmdEncoder) && (pipelineBindPoint) == VK_PIPELINE_BIND_POINT_GRAPHICS) \
				(cmdEncoder)->_graphicsResourcesState.bind(static_cast<MVKShaderStage>(stage), __VA_ARGS__); \
		} \
	} while (0)

#pragma mark MVKShaderStageResourceBinding

MVKShaderStageResourceBinding MVKShaderStageResourceBinding::operator+ (const MVKShaderStageResourceBinding& rhs) {
	MVKShaderStageResourceBinding rslt;
	rslt.bufferIndex = this->bufferIndex + rhs.bufferIndex;
	rslt.textureIndex = this->textureIndex + rhs.textureIndex;
	rslt.samplerIndex = this->samplerIndex + rhs.samplerIndex;
	rslt.resourceIndex = this->resourceIndex + rhs.resourceIndex;
	rslt.dynamicOffsetBufferIndex = this->dynamicOffsetBufferIndex + rhs.dynamicOffsetBufferIndex;
	return rslt;
}

MVKShaderStageResourceBinding& MVKShaderStageResourceBinding::operator+= (const MVKShaderStageResourceBinding& rhs) {
	this->bufferIndex += rhs.bufferIndex;
	this->textureIndex += rhs.textureIndex;
	this->samplerIndex += rhs.samplerIndex;
	this->resourceIndex += rhs.resourceIndex;
	this->dynamicOffsetBufferIndex += rhs.dynamicOffsetBufferIndex;
	return *this;
}

void MVKShaderStageResourceBinding::clearArgumentBufferResources() {
	bufferIndex = 0;
	textureIndex = 0;
	samplerIndex = 0;
}


#pragma mark MVKShaderResourceBinding

uint16_t MVKShaderResourceBinding::getMaxResourceIndex() {
	return std::max({stages[kMVKShaderStageVertex].resourceIndex, stages[kMVKShaderStageTessCtl].resourceIndex, stages[kMVKShaderStageTessEval].resourceIndex, stages[kMVKShaderStageFragment].resourceIndex, stages[kMVKShaderStageCompute].resourceIndex});
}

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

void MVKShaderResourceBinding::clearArgumentBufferResources() {
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		stages[i].clearArgumentBufferResources();
	}
}

void MVKShaderResourceBinding::addArgumentBuffers(uint32_t count) {
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		stages[i].bufferIndex += count;
		stages[i].resourceIndex += count;
	}
}

void mvkPopulateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
									   MVKShaderStageResourceBinding& ssRB,
									   MVKShaderStage stage,
									   uint32_t descriptorSetIndex,
									   uint32_t bindingIndex,
									   uint32_t count,
									   VkDescriptorType descType,
									   MVKSampler* immutableSampler) {

#define addResourceBinding(spvRezType)												\
	do {																			\
		mvk::MSLResourceBinding rb;													\
		auto& rbb = rb.resourceBinding;												\
		rbb.stage = spvExecModels[stage];											\
		rbb.basetype = SPIRV_CROSS_NAMESPACE::SPIRType::spvRezType;					\
		rbb.desc_set = descriptorSetIndex;											\
		rbb.binding = bindingIndex;													\
		rbb.count = count;															\
		rbb.msl_buffer = ssRB.bufferIndex;											\
		rbb.msl_texture = ssRB.textureIndex;										\
		rbb.msl_sampler = ssRB.samplerIndex;										\
		if (immutableSampler) { immutableSampler->getConstexprSampler(rb); }		\
		shaderConfig.resourceBindings.push_back(rb);								\
	} while(false)

	static const spv::ExecutionModel spvExecModels[] = {
		spv::ExecutionModelVertex,
		spv::ExecutionModelTessellationControl,
		spv::ExecutionModelTessellationEvaluation,
		spv::ExecutionModelFragment,
		spv::ExecutionModelGLCompute
	};

	switch (descType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			addResourceBinding(Void);
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: {
			addResourceBinding(Float);

			mvk::DescriptorBinding db;
			db.stage = spvExecModels[stage];
			db.descriptorSet = descriptorSetIndex;
			db.binding = bindingIndex;
			db.index = ssRB.dynamicOffsetBufferIndex;
			shaderConfig.dynamicBufferDescriptors.push_back(db);
			break;
		}

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			addResourceBinding(Image);
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			addResourceBinding(Image);
			addResourceBinding(Void);
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			addResourceBinding(Sampler);
			break;

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			addResourceBinding(SampledImage);
			break;

		default:
			addResourceBinding(Unknown);
			break;
	}
}


#pragma mark -
#pragma mark MVKDescriptorSetLayoutBinding

MVKVulkanAPIObject* MVKDescriptorSetLayoutBinding::getVulkanAPIObject() { return _layout; };

uint32_t MVKDescriptorSetLayoutBinding::getDescriptorCount(MVKDescriptorSet* descSet) const {

	if (_info.descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT) {
		return 1;
	}

	if (descSet && hasVariableDescriptorCount()) {
		return descSet->_variableDescriptorCount;
	}

	return _info.descriptorCount;
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayoutBinding::bind(MVKCommandEncoder* cmdEncoder,
										 VkPipelineBindPoint pipelineBindPoint,
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
			mvkDesc->bind(cmdEncoder, pipelineBindPoint, this, descIdx, _applyToStage, mtlIdxs, dynamicOffsets, dynamicOffsetIndex);
		}
    }
}

template<typename T>
static const T& get(const void* pData, size_t stride, uint32_t index) {
    return *(T*)((const char*)pData + stride * index);
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKDescriptorSetLayoutBinding::push(MVKCommandEncoder* cmdEncoder,
                                         VkPipelineBindPoint pipelineBindPoint,
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
                        BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
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
                        BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
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
                            BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindTexture, pipelineBindPoint, i, tb);
                            if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE && !getPhysicalDevice()->useNativeTextureAtomics()) {
                                bb.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
                                BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
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
                        BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindTexture, pipelineBindPoint, i, tb);
                        if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER && !getPhysicalDevice()->useNativeTextureAtomics()) {
                            bb.index = mtlIdxs.stages[i].bufferIndex + rezIdx;
                            BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
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
                        BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindSamplerState, pipelineBindPoint, i, sb);
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
                            BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindTexture, pipelineBindPoint, i, tb);
                            BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindSamplerState, pipelineBindPoint, i, sb);
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

bool MVKDescriptorSetLayoutBinding::isUsingMetalArgumentBuffer() { return _layout->isUsingMetalArgumentBuffer(); };

// Adds MTLArgumentDescriptors to the array, and updates resource indexes consumed.
void MVKDescriptorSetLayoutBinding::addMTLArgumentDescriptors(NSMutableArray<MTLArgumentDescriptor*>* args) {
	switch (getDescriptorType()) {

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().bufferIndex, MTLDataTypePointer, MTLArgumentAccessReadOnly);
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().bufferIndex, MTLDataTypePointer, MTLArgumentAccessReadWrite);
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().textureIndex, MTLDataTypeTexture, MTLArgumentAccessReadOnly);
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().textureIndex, MTLDataTypeTexture, MTLArgumentAccessReadWrite);
			if (!getPhysicalDevice()->useNativeTextureAtomics()) { // Needed for emulated atomic operations
				addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().bufferIndex, MTLDataTypePointer, MTLArgumentAccessReadWrite);
			}
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().textureIndex, MTLDataTypeTexture, MTLArgumentAccessReadOnly);
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().textureIndex, MTLDataTypeTexture, MTLArgumentAccessReadWrite);
			if (!getPhysicalDevice()->useNativeTextureAtomics()) { // Needed for emulated atomic operations
				addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().bufferIndex, MTLDataTypePointer, MTLArgumentAccessReadWrite);
			}
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().samplerIndex, MTLDataTypeSampler, MTLArgumentAccessReadOnly);
			break;

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().textureIndex, MTLDataTypeTexture, MTLArgumentAccessReadOnly);
			addMTLArgumentDescriptor(args, getMetalResourceIndexOffsets().samplerIndex, MTLDataTypeSampler, MTLArgumentAccessReadOnly);
			break;

		default:
			break;
	}
}

void MVKDescriptorSetLayoutBinding::addMTLArgumentDescriptor(NSMutableArray<MTLArgumentDescriptor*>* args,
															 uint32_t argIndex,
															 MTLDataType dataType,
															 MTLArgumentAccess access) {
	uint32_t descCnt = getDescriptorCount();
	if (descCnt == 0) { return; }
	
	auto* argDesc = [MTLArgumentDescriptor argumentDescriptor];
	argDesc.dataType = dataType;
	argDesc.access = access;
	argDesc.index = argIndex;
	argDesc.arrayLength = descCnt;
	argDesc.textureType = MTLTextureType2D;

	[args addObject: argDesc];
}

void MVKDescriptorSetLayoutBinding::populateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
                                                                   MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                                                   uint32_t dslIndex) {

	MVKSampler* mvkSamp = !_immutableSamplers.empty() ? _immutableSamplers.front() : nullptr;

    // Establish the resource indices to use, by combining the offsets of the DSL and this DSL binding.
    MVKShaderResourceBinding mtlIdxs = _mtlResourceIndexOffsets + dslMTLRezIdxOffsets;

	uint32_t descCnt = getDescriptorCount();
	bool isUsingMtlArgBuff = isUsingMetalArgumentBuffer();
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
        if ((_applyToStage[stage] || isUsingMtlArgBuff) && descCnt > 0) {
            mvkPopulateShaderConversionConfig(shaderConfig,
                                              mtlIdxs.stages[stage],
                                              MVKShaderStage(stage),
                                              dslIndex,
                                              _info.binding,
											  descCnt,
											  getDescriptorType(),
											  mvkSamp);
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

MTLRenderStages MVKDescriptorSetLayoutBinding::getMTLRenderStages() {
	MTLRenderStages mtlStages = 0;
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (_applyToStage[stage]) {
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

	// Determine if this binding is used by this shader stage, and initialize resource indexes.
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		_applyToStage[stage] = mvkAreAllFlagsEnabled(pBinding->stageFlags, mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage(stage)));
		initMetalResourceIndexOffsets(pBinding, stage);
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
	_immutableSamplers(binding._immutableSamplers),
	_mtlResourceIndexOffsets(binding._mtlResourceIndexOffsets),
	_descriptorIndex(binding._descriptorIndex) {

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
void MVKDescriptorSetLayoutBinding::initMetalResourceIndexOffsets(const VkDescriptorSetLayoutBinding* pBinding, uint32_t stage) {

	// Sets an index offset and updates both that index and the general resource index.
	// Can be used multiply for combined multi-resource descriptor types.
	// When using Metal argument buffers, we accumulate the resource indexes cummulatively,
	// across all resource types, and do not increase the individual resources counts
	// consumed by the descriptor set layout.
#define setResourceIndexOffset(rezIdx)														\
	do {																					\
		bool isUsingMtlArgBuff = isUsingMetalArgumentBuffer();								\
		if (_applyToStage[stage] || isUsingMtlArgBuff) {									\
			bindIdxs.rezIdx = isUsingMtlArgBuff ? dslCnts.resourceIndex : dslCnts.rezIdx;	\
			dslCnts.rezIdx += isUsingMtlArgBuff ? 0 : descCnt;								\
			bindIdxs.resourceIndex = dslCnts.resourceIndex;									\
			dslCnts.resourceIndex += descCnt;												\
		}																					\
	} while(false)

	auto& mtlFeats = getMetalFeatures();
	MVKShaderStageResourceBinding& bindIdxs = _mtlResourceIndexOffsets.stages[stage];
	MVKShaderStageResourceBinding& dslCnts = _layout->_mtlResourceCounts.stages[stage];

	uint32_t descCnt = pBinding->descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT ? 1 : pBinding->descriptorCount;
    switch (pBinding->descriptorType) {
        case VK_DESCRIPTOR_TYPE_SAMPLER:
			setResourceIndexOffset(samplerIndex);

			if (pBinding->descriptorCount > 1 && !mtlFeats.arrayOfSamplers) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of samplers.", _device->getName()));
			}
            break;

        case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			setResourceIndexOffset(textureIndex);
			setResourceIndexOffset(samplerIndex);

			if (pBinding->descriptorCount > 1) {
				if ( !mtlFeats.arrayOfTextures ) {
					_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of textures.", _device->getName()));
				}
				if ( !mtlFeats.arrayOfSamplers ) {
					_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of samplers.", _device->getName()));
				}
			}

            if (pBinding->pImmutableSamplers && _applyToStage[stage]) {
                for (uint32_t i = 0; i < pBinding->descriptorCount; i++) {
                    uint8_t planeCount = ((MVKSampler*)pBinding->pImmutableSamplers[i])->getPlaneCount();
                    if (planeCount > 1) {
                        dslCnts.textureIndex += planeCount - 1;
                    }
                }
            }
            break;

        case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
        case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
        case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			setResourceIndexOffset(textureIndex);

			if (pBinding->descriptorCount > 1 && !mtlFeats.arrayOfTextures) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of textures.", _device->getName()));
			}
            break;

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			setResourceIndexOffset(textureIndex);
			if (!getPhysicalDevice()->useNativeTextureAtomics()) setResourceIndexOffset(bufferIndex);

			if (pBinding->descriptorCount > 1 && !mtlFeats.arrayOfTextures) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of textures.", _device->getName()));
			}
			break;

        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
        case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT:
			setResourceIndexOffset(bufferIndex);
            break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			setResourceIndexOffset(bufferIndex);
			bindIdxs.dynamicOffsetBufferIndex = dslCnts.dynamicOffsetBufferIndex;
			dslCnts.dynamicOffsetBufferIndex += descCnt;

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
							   VkPipelineBindPoint pipelineBindPoint,
							   MVKDescriptorSetLayoutBinding* mvkDSLBind,
							   uint32_t elementIndex,
							   bool stages[],
							   MVKShaderResourceBinding& mtlIndexes,
							   MVKArrayRef<uint32_t> dynamicOffsets,
							   uint32_t& dynamicOffsetIndex) {
	MVKMTLBufferBinding bb;
	NSUInteger bufferDynamicOffset = (usesDynamicBufferOffsets() && dynamicOffsets.size() > dynamicOffsetIndex
									  ? dynamicOffsets[dynamicOffsetIndex++] : 0);
	if (_mvkBuffer) {
		bb.mtlBuffer = _mvkBuffer->getMTLBuffer();
		bb.offset = _mvkBuffer->getMTLBufferOffset() + _buffOffset + bufferDynamicOffset;
		if (_buffRange == VK_WHOLE_SIZE)
			bb.size = (uint32_t)(_mvkBuffer->getByteCount() - bb.offset);
		else
			bb.size = (uint32_t)_buffRange;
	}
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		if (stages[i]) {
			bb.index = mtlIndexes.stages[i].bufferIndex + elementIndex;
			BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
		}
	}
}

void MVKBufferDescriptor::encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
													  id<MTLArgumentEncoder> mtlArgEncoder,
													  uint32_t descSetIndex,
													  MVKDescriptorSetLayoutBinding* mvkDSLBind,
													  uint32_t elementIndex,
													  MVKShaderStage stage,
													  bool encodeToArgBuffer,
													  bool encodeUsage) {
	if (encodeToArgBuffer) {
		uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().bufferIndex + elementIndex;
		[mtlArgEncoder setBuffer: _mvkBuffer ? _mvkBuffer->getMTLBuffer() : nil
						  offset: _mvkBuffer ? _mvkBuffer->getMTLBufferOffset() + _buffOffset : 0
						 atIndex: argIdx];
	}
	if (encodeUsage) {
		id<MTLBuffer> mtlBuffer = _mvkBuffer ? _mvkBuffer->getMTLBuffer() : nil;
		rezEncState->encodeResourceUsage(stage, mtlBuffer, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
	}
}

void MVKBufferDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
								MVKDescriptorSet* mvkDescSet,
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
}

void MVKBufferDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
							   MVKDescriptorSet* mvkDescSet,
							   uint32_t dstIndex,
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
										   VkPipelineBindPoint pipelineBindPoint,
										   MVKDescriptorSetLayoutBinding* mvkDSLBind,
										   uint32_t elementIndex,
										   bool stages[],
										   MVKShaderResourceBinding& mtlIndexes,
										   MVKArrayRef<uint32_t> dynamicOffsets,
										   uint32_t& dynamicOffsetIndex) {
	MVKMTLBufferBinding bb;
	if (_mvkMTLBufferAllocation) {
		bb.mtlBuffer = _mvkMTLBufferAllocation->_mtlBuffer;
		bb.offset = _mvkMTLBufferAllocation->_offset;
		bb.size = mvkDSLBind->_info.descriptorCount;
	}

	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		if (stages[i]) {
			bb.index = mtlIndexes.stages[i].bufferIndex;
			BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
		}
	}
}

void MVKInlineUniformBlockDescriptor::encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
																  id<MTLArgumentEncoder> mtlArgEncoder,
																  uint32_t descSetIndex,
																  MVKDescriptorSetLayoutBinding* mvkDSLBind,
																  uint32_t elementIndex,
																  MVKShaderStage stage,
																  bool encodeToArgBuffer,
																  bool encodeUsage) {
	if (encodeToArgBuffer) {
		uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().bufferIndex;
		[mtlArgEncoder setBuffer: _mvkMTLBufferAllocation ? _mvkMTLBufferAllocation->_mtlBuffer : nil
						  offset: _mvkMTLBufferAllocation ? _mvkMTLBufferAllocation->_offset : 0
						 atIndex: argIdx];
	}
	if (encodeUsage) {
		id<MTLBuffer> mtlBuffer = _mvkMTLBufferAllocation ? _mvkMTLBufferAllocation->_mtlBuffer : nil;
		rezEncState->encodeResourceUsage(stage, mtlBuffer, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
	}
}

void MVKInlineUniformBlockDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
											MVKDescriptorSet* mvkDescSet,
											uint32_t dstOffset,
											size_t stride,
											const void* pData) {
	// Ensure there is a destination to write to
	uint32_t buffSize = mvkDSLBind->_info.descriptorCount;
	if ( !_mvkMTLBufferAllocation ) { _mvkMTLBufferAllocation = mvkDescSet->acquireMTLBufferRegion(buffSize); }

	uint8_t* data = getData();
	const auto& pInlineUniformBlock = *(VkWriteDescriptorSetInlineUniformBlockEXT*)pData;
	if (data && pInlineUniformBlock.pData && dstOffset < buffSize) {
		uint32_t dataLen = std::min(pInlineUniformBlock.dataSize, buffSize - dstOffset);
		memcpy(data + dstOffset, pInlineUniformBlock.pData, dataLen);
	}
}

void MVKInlineUniformBlockDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
										   MVKDescriptorSet* mvkDescSet,
										   uint32_t srcOffset,
										   VkDescriptorImageInfo* pImageInfo,
										   VkDescriptorBufferInfo* pBufferInfo,
										   VkBufferView* pTexelBufferView,
										   VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	uint8_t* data = getData();
	uint32_t buffSize = mvkDSLBind->_info.descriptorCount;
	if (data && pInlineUniformBlock->pData && srcOffset < buffSize) {
		uint32_t dataLen = std::min(pInlineUniformBlock->dataSize, buffSize - srcOffset);
		memcpy((void*)pInlineUniformBlock->pData, data + srcOffset, dataLen);
	}
}

void MVKInlineUniformBlockDescriptor::reset() {
	if (_mvkMTLBufferAllocation) { _mvkMTLBufferAllocation->returnToPool(); }
	_mvkMTLBufferAllocation = nullptr;
	MVKDescriptor::reset();
}


#pragma mark -
#pragma mark MVKImageDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKImageDescriptor::bind(MVKCommandEncoder* cmdEncoder,
							  VkPipelineBindPoint pipelineBindPoint,
							  MVKDescriptorSetLayoutBinding* mvkDSLBind,
							  uint32_t elementIndex,
							  bool stages[],
							  MVKShaderResourceBinding& mtlIndexes,
							  MVKArrayRef<uint32_t> dynamicOffsets,
							  uint32_t& dynamicOffsetIndex) {

	VkDescriptorType descType = getDescriptorType();
	uint8_t planeCount = (_mvkImageView) ? _mvkImageView->getPlaneCount() : 1;
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
        for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
            if (stages[i]) {
                tb.index = mtlIndexes.stages[i].textureIndex + elementIndex + planeIndex;
                BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindTexture, pipelineBindPoint, i, tb);
                if (descType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE && !cmdEncoder->getPhysicalDevice()->useNativeTextureAtomics()) {
                    bb.index = mtlIndexes.stages[i].bufferIndex + elementIndex + planeIndex;
                    BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
                }
            }
        }
    }
}

void MVKImageDescriptor::encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
													 id<MTLArgumentEncoder> mtlArgEncoder,
													 uint32_t descSetIndex,
													 MVKDescriptorSetLayoutBinding* mvkDSLBind,
													 uint32_t elementIndex,
													 MVKShaderStage stage,
													 bool encodeToArgBuffer,
													 bool encodeUsage) {
	VkDescriptorType descType = getDescriptorType();
	uint8_t planeCount = (_mvkImageView) ? _mvkImageView->getPlaneCount() : 1;

	for (uint8_t planeIndex = 0; planeIndex < planeCount; planeIndex++) {
		uint32_t planeDescIdx = (elementIndex * planeCount) + planeIndex;

		id<MTLTexture> mtlTexture = _mvkImageView ? _mvkImageView->getMTLTexture(planeIndex) : nil;
		if (encodeToArgBuffer) {
			uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().textureIndex + planeDescIdx;
			[mtlArgEncoder setTexture: mtlTexture atIndex: argIdx];
		}
		if (encodeUsage) {
			rezEncState->encodeResourceUsage(stage, mtlTexture, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
		}
		if (descType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE && !mvkDSLBind->getPhysicalDevice()->useNativeTextureAtomics()) {
			id<MTLTexture> mtlTex = mtlTexture.parentTexture ? mtlTexture.parentTexture : mtlTexture;
			id<MTLBuffer> mtlBuff = mtlTex.buffer;
			if (mtlBuff) {
				if (encodeToArgBuffer) {
					uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().bufferIndex + planeDescIdx;
					[mtlArgEncoder setBuffer: mtlBuff offset: mtlTex.bufferOffset atIndex: argIdx];
				}
				if (encodeUsage) {
					rezEncState->encodeResourceUsage(stage, mtlBuff, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
				}
			}
		}
	}
}

void MVKImageDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
							   MVKDescriptorSet* mvkDescSet,
							   uint32_t srcIndex,
							   size_t stride,
							   const void* pData) {
	auto* oldImgView = _mvkImageView;

	const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcIndex);
	_mvkImageView = (MVKImageView*)pImgInfo->imageView;

	if (_mvkImageView) { _mvkImageView->retain(); }
	if (oldImgView) { oldImgView->release(); }
}

void MVKImageDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
							  MVKDescriptorSet* mvkDescSet,
							  uint32_t dstIndex,
							  VkDescriptorImageInfo* pImageInfo,
							  VkDescriptorBufferInfo* pBufferInfo,
							  VkBufferView* pTexelBufferView,
							  VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	auto& imgInfo = pImageInfo[dstIndex];
	imgInfo.imageView = (VkImageView)_mvkImageView;
	imgInfo.imageLayout = VK_IMAGE_LAYOUT_UNDEFINED;
}

void MVKImageDescriptor::reset() {
	if (_mvkImageView) { _mvkImageView->release(); }
	_mvkImageView = nullptr;
	MVKDescriptor::reset();
}


#pragma mark -
#pragma mark MVKSamplerDescriptorMixin

// A null cmdEncoder can be passed to perform a validation pass
// Metal validation requires each sampler in an array of samplers to be populated,
// even if not used, so populate a default if one hasn't been set.
void MVKSamplerDescriptorMixin::bind(MVKCommandEncoder* cmdEncoder,
									 VkPipelineBindPoint pipelineBindPoint,
									 MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 uint32_t elementIndex,
									 bool stages[],
									 MVKShaderResourceBinding& mtlIndexes,
									 MVKArrayRef<uint32_t> dynamicOffsets,
									 uint32_t& dynamicOffsetIndex) {

	MVKSampler* imutSamp = mvkDSLBind->getImmutableSampler(elementIndex);
	MVKSampler* mvkSamp = imutSamp ? imutSamp : _mvkSampler;

	MVKMTLSamplerStateBinding sb;
	sb.mtlSamplerState = (mvkSamp
						  ? mvkSamp->getMTLSamplerState()
						  : cmdEncoder->getDevice()->getDefaultMTLSamplerState());
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		if (stages[i]) {
			sb.index = mtlIndexes.stages[i].samplerIndex + elementIndex;
			BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindSamplerState, pipelineBindPoint, i, sb);
		}
	}
}

// Metal validation requires each sampler in an array of samplers to be populated,
// even if not used, so populate a default if one hasn't been set.
void MVKSamplerDescriptorMixin::encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
															id<MTLArgumentEncoder> mtlArgEncoder,
															uint32_t descSetIndex,
															MVKDescriptorSetLayoutBinding* mvkDSLBind,
															uint32_t elementIndex,
															MVKShaderStage stage,
															bool encodeToArgBuffer) {
	if (encodeToArgBuffer) {
		MVKSampler* imutSamp = mvkDSLBind->getImmutableSampler(elementIndex);
		MVKSampler* mvkSamp = imutSamp ? imutSamp : _mvkSampler;
		id<MTLSamplerState> mtlSamp = (mvkSamp
									   ? mvkSamp->getMTLSamplerState()
									   : mvkDSLBind->getDevice()->getDefaultMTLSamplerState());
		uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().samplerIndex + elementIndex;
		[mtlArgEncoder setSamplerState: mtlSamp atIndex: argIdx];
	}
}

void MVKSamplerDescriptorMixin::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									  MVKDescriptorSet* mvkDescSet,
									  uint32_t srcIndex,
									  size_t stride,
									  const void* pData) {

	if (mvkDSLBind->usesImmutableSamplers()) { return; }

	auto* oldSamp = _mvkSampler;

	const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, stride, srcIndex);
	_mvkSampler = (MVKSampler*)pImgInfo->sampler;
	if (_mvkSampler && _mvkSampler->getRequiresConstExprSampler()) {
		_mvkSampler->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkUpdateDescriptorSets(): Tried to push an immutable sampler.");
	}

	if (_mvkSampler) { _mvkSampler->retain(); }
	if (oldSamp) { oldSamp->release(); }
}

void MVKSamplerDescriptorMixin::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 MVKDescriptorSet* mvkDescSet,
									 uint32_t dstIndex,
									 VkDescriptorImageInfo* pImageInfo,
									 VkDescriptorBufferInfo* pBufferInfo,
									 VkBufferView* pTexelBufferView,
									 VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	auto& imgInfo = pImageInfo[dstIndex];
	imgInfo.sampler = (VkSampler)_mvkSampler;
}

void MVKSamplerDescriptorMixin::reset() {
	if (_mvkSampler) { _mvkSampler->release(); }
	_mvkSampler = nullptr;
}


#pragma mark -
#pragma mark MVKSamplerDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKSamplerDescriptor::bind(MVKCommandEncoder* cmdEncoder,
								VkPipelineBindPoint pipelineBindPoint,
								MVKDescriptorSetLayoutBinding* mvkDSLBind,
								uint32_t elementIndex,
								bool stages[],
								MVKShaderResourceBinding& mtlIndexes,
								MVKArrayRef<uint32_t> dynamicOffsets,
								uint32_t& dynamicOffsetIndex) {
	MVKSamplerDescriptorMixin::bind(cmdEncoder, pipelineBindPoint, mvkDSLBind, elementIndex, stages, mtlIndexes, dynamicOffsets, dynamicOffsetIndex);
}

void MVKSamplerDescriptor::encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
													   id<MTLArgumentEncoder> mtlArgEncoder,
													   uint32_t descSetIndex,
													   MVKDescriptorSetLayoutBinding* mvkDSLBind,
													   uint32_t elementIndex,
													   MVKShaderStage stage,
													   bool encodeToArgBuffer,
													   bool encodeUsage) {
	MVKSamplerDescriptorMixin::encodeToMetalArgumentBuffer(rezEncState, mtlArgEncoder, descSetIndex, mvkDSLBind, elementIndex, stage, encodeToArgBuffer);
}

void MVKSamplerDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
								 MVKDescriptorSet* mvkDescSet,
								 uint32_t srcIndex,
								 size_t stride,
								 const void* pData) {
	MVKSamplerDescriptorMixin::write(mvkDSLBind, mvkDescSet, srcIndex, stride, pData);
}

void MVKSamplerDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
								MVKDescriptorSet* mvkDescSet,
								uint32_t dstIndex,
								VkDescriptorImageInfo* pImageInfo,
								VkDescriptorBufferInfo* pBufferInfo,
								VkBufferView* pTexelBufferView,
								VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	MVKSamplerDescriptorMixin::read(mvkDSLBind, mvkDescSet, dstIndex, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
}

void MVKSamplerDescriptor::reset() {
	MVKSamplerDescriptorMixin::reset();
	MVKDescriptor::reset();
}


#pragma mark -
#pragma mark MVKCombinedImageSamplerDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKCombinedImageSamplerDescriptor::bind(MVKCommandEncoder* cmdEncoder,
											 VkPipelineBindPoint pipelineBindPoint,
											 MVKDescriptorSetLayoutBinding* mvkDSLBind,
											 uint32_t elementIndex,
											 bool stages[],
											 MVKShaderResourceBinding& mtlIndexes,
											 MVKArrayRef<uint32_t> dynamicOffsets,
											 uint32_t& dynamicOffsetIndex) {
	MVKImageDescriptor::bind(cmdEncoder, pipelineBindPoint, mvkDSLBind, elementIndex, stages, mtlIndexes, dynamicOffsets, dynamicOffsetIndex);
	MVKSamplerDescriptorMixin::bind(cmdEncoder, pipelineBindPoint, mvkDSLBind, elementIndex, stages, mtlIndexes, dynamicOffsets, dynamicOffsetIndex);
}

void MVKCombinedImageSamplerDescriptor::encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
																	id<MTLArgumentEncoder> mtlArgEncoder,
																	uint32_t descSetIndex,
																	MVKDescriptorSetLayoutBinding* mvkDSLBind,
																	uint32_t elementIndex,
																	MVKShaderStage stage,
																	bool encodeToArgBuffer,
																	bool encodeUsage) {
	MVKImageDescriptor::encodeToMetalArgumentBuffer(rezEncState, mtlArgEncoder, descSetIndex, mvkDSLBind, elementIndex, stage, encodeToArgBuffer, encodeUsage);
	MVKSamplerDescriptorMixin::encodeToMetalArgumentBuffer(rezEncState, mtlArgEncoder, descSetIndex, mvkDSLBind, elementIndex, stage, encodeToArgBuffer);
}

void MVKCombinedImageSamplerDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
											  MVKDescriptorSet* mvkDescSet,
											  uint32_t srcIndex,
											  size_t stride,
											  const void* pData) {
	MVKImageDescriptor::write(mvkDSLBind, mvkDescSet, srcIndex, stride, pData);
	MVKSamplerDescriptorMixin::write(mvkDSLBind, mvkDescSet, srcIndex, stride, pData);
}

void MVKCombinedImageSamplerDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
											 MVKDescriptorSet* mvkDescSet,
											 uint32_t dstIndex,
											 VkDescriptorImageInfo* pImageInfo,
											 VkDescriptorBufferInfo* pBufferInfo,
											 VkBufferView* pTexelBufferView,
											 VkWriteDescriptorSetInlineUniformBlockEXT* pInlineUniformBlock) {
	MVKImageDescriptor::read(mvkDSLBind, mvkDescSet, dstIndex, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
	MVKSamplerDescriptorMixin::read(mvkDSLBind, mvkDescSet, dstIndex, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
}

void MVKCombinedImageSamplerDescriptor::reset() {
	MVKSamplerDescriptorMixin::reset();
	MVKImageDescriptor::reset();
}


#pragma mark -
#pragma mark MVKTexelBufferDescriptor

// A null cmdEncoder can be passed to perform a validation pass
void MVKTexelBufferDescriptor::bind(MVKCommandEncoder* cmdEncoder,
									VkPipelineBindPoint pipelineBindPoint,
									MVKDescriptorSetLayoutBinding* mvkDSLBind,
									uint32_t elementIndex,
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
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		if (stages[i]) {
			tb.index = mtlIndexes.stages[i].textureIndex + elementIndex;
			BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindTexture, pipelineBindPoint, i, tb);
			if (descType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER && !cmdEncoder->getPhysicalDevice()->useNativeTextureAtomics()) {
				bb.index = mtlIndexes.stages[i].bufferIndex + elementIndex;
				BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
			}
		}
	}
}
void MVKTexelBufferDescriptor::encodeToMetalArgumentBuffer(MVKResourcesCommandEncoderState* rezEncState,
														   id<MTLArgumentEncoder> mtlArgEncoder,
														   uint32_t descSetIndex,
														   MVKDescriptorSetLayoutBinding* mvkDSLBind,
														   uint32_t elementIndex,
														   MVKShaderStage stage,
														   bool encodeToArgBuffer,
														   bool encodeUsage) {
	VkDescriptorType descType = getDescriptorType();
	id<MTLTexture> mtlTexture = _mvkBufferView ? _mvkBufferView->getMTLTexture() : nil;
	if (encodeToArgBuffer) {
		uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().textureIndex + elementIndex;
		[mtlArgEncoder setTexture: mtlTexture atIndex: argIdx];
	}
	if (encodeUsage) {
		rezEncState->encodeResourceUsage(stage, mtlTexture, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
	}

	if (descType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER && !mvkDSLBind->getPhysicalDevice()->useNativeTextureAtomics()) {
		id<MTLBuffer> mtlBuff = mtlTexture.buffer;
		if (mtlBuff) {
			if (encodeToArgBuffer) {
				uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().bufferIndex + elementIndex;
				[mtlArgEncoder setBuffer: mtlBuff offset: mtlTexture.bufferOffset atIndex: argIdx];
			}
			if (encodeUsage) {
				rezEncState->encodeResourceUsage(stage, mtlBuff, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
			}
		}
	}
}

void MVKTexelBufferDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 MVKDescriptorSet* mvkDescSet,
									 uint32_t srcIndex,
									 size_t stride,
									 const void* pData) {
	auto* oldBuffView = _mvkBufferView;

	const auto* pBuffView = &get<VkBufferView>(pData, stride, srcIndex);
	_mvkBufferView = (MVKBufferView*)*pBuffView;

	if (_mvkBufferView) { _mvkBufferView->retain(); }
	if (oldBuffView) { oldBuffView->release(); }
}

void MVKTexelBufferDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									MVKDescriptorSet* mvkDescSet,
									uint32_t dstIndex,
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
