/*
 * MVKDescriptor.mm
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

#include "MVKDescriptor.h"
#include "MVKDescriptorSet.h"
#include "MVKBuffer.h"
#include <sstream>
#include <iomanip>


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
	rslt.dynamicOffsetBufferIndex = this->dynamicOffsetBufferIndex + rhs.dynamicOffsetBufferIndex;
	return rslt;
}

MVKShaderStageResourceBinding& MVKShaderStageResourceBinding::operator+= (const MVKShaderStageResourceBinding& rhs) {
	this->bufferIndex += rhs.bufferIndex;
	this->textureIndex += rhs.textureIndex;
	this->samplerIndex += rhs.samplerIndex;
	this->dynamicOffsetBufferIndex += rhs.dynamicOffsetBufferIndex;
	return *this;
}

void MVKShaderStageResourceBinding::clearArgumentBufferResources() {
	bufferIndex = 0;
	textureIndex = 0;
	samplerIndex = 0;
}


#pragma mark MVKShaderResourceBinding

uint32_t MVKShaderResourceBinding::getMaxBufferIndex() {
	return std::max({stages[kMVKShaderStageVertex].bufferIndex, stages[kMVKShaderStageTessCtl].bufferIndex, stages[kMVKShaderStageTessEval].bufferIndex, stages[kMVKShaderStageFragment].bufferIndex, stages[kMVKShaderStageCompute].bufferIndex});
}

uint32_t MVKShaderResourceBinding::getMaxTextureIndex() {
	return std::max({stages[kMVKShaderStageVertex].textureIndex, stages[kMVKShaderStageTessCtl].textureIndex, stages[kMVKShaderStageTessEval].textureIndex, stages[kMVKShaderStageFragment].textureIndex, stages[kMVKShaderStageCompute].textureIndex});
}

uint32_t MVKShaderResourceBinding::getMaxSamplerIndex() {
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
	}
}

void mvkPopulateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
									   MVKShaderStageResourceBinding& ssRB,
									   MVKShaderStage stage,
									   uint32_t descriptorSetIndex,
									   uint32_t bindingIndex,
									   uint32_t count,
									   VkDescriptorType descType,
									   MVKSampler* immutableSampler,
									   bool usingNativeTextureAtomics) {
	if (count == 0) { return; }

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
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
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
			if ( !usingNativeTextureAtomics ) {
				addResourceBinding(Void);
			}
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

uint32_t MVKDescriptorSetLayoutBinding::getDescriptorCount(uint32_t variableDescriptorCount) const {
	if (_info.descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
		return 1;
	}
	if (hasVariableDescriptorCount()) {
		return std::min(variableDescriptorCount, _info.descriptorCount);
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
	uint32_t descCnt = getDescriptorCount(descSet->_variableDescriptorCount);
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

            case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK: {
                const auto& inlineUniformBlock = *(VkWriteDescriptorSetInlineUniformBlock*)pData;
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
                            if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE && !getMetalFeatures().nativeTextureAtomics) {
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
                        if (_info.descriptorType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER && !getMetalFeatures().nativeTextureAtomics) {
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

// Adds MTLArgumentDescriptors to the array, and updates resource indexes consumed.
void MVKDescriptorSetLayoutBinding::addMTLArgumentDescriptors(NSMutableArray<MTLArgumentDescriptor*>* args,
															  uint32_t variableDescriptorCount) {
	switch (getDescriptorType()) {

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
			addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().bufferIndex, MTLDataTypePointer, MTLArgumentAccessReadOnly);
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().bufferIndex, MTLDataTypePointer, MTLArgumentAccessReadWrite);
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().textureIndex, MTLDataTypeTexture, MTLArgumentAccessReadOnly);
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
			addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().textureIndex, MTLDataTypeTexture, MTLArgumentAccessReadWrite);
			if (!getMetalFeatures().nativeTextureAtomics) { // Needed for emulated atomic operations
				addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().bufferIndex, MTLDataTypePointer, MTLArgumentAccessReadWrite);
			}
			break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().textureIndex, MTLDataTypeTexture, MTLArgumentAccessReadOnly);
			break;

		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().textureIndex, MTLDataTypeTexture, MTLArgumentAccessReadWrite);
			if (!getMetalFeatures().nativeTextureAtomics) { // Needed for emulated atomic operations
				addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().bufferIndex, MTLDataTypePointer, MTLArgumentAccessReadWrite);
			}
			break;

		case VK_DESCRIPTOR_TYPE_SAMPLER:
			addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().samplerIndex, MTLDataTypeSampler, MTLArgumentAccessReadOnly);
			break;

		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: {
			uint8_t maxPlaneCnt = getMaxPlaneCount();
			for (uint8_t planeIdx = 0; planeIdx < maxPlaneCnt; planeIdx++) {
				addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().textureIndex + planeIdx, MTLDataTypeTexture, MTLArgumentAccessReadOnly);
			}
			addMTLArgumentDescriptor(args, variableDescriptorCount, getMetalResourceIndexOffsets().samplerIndex, MTLDataTypeSampler, MTLArgumentAccessReadOnly);
			break;
		}

		default:
			break;
	}
}

void MVKDescriptorSetLayoutBinding::addMTLArgumentDescriptor(NSMutableArray<MTLArgumentDescriptor*>* args,
															 uint32_t variableDescriptorCount,
															 uint32_t argIndex,
															 MTLDataType dataType,
															 MTLArgumentAccess access) {
	uint32_t descCnt = getDescriptorCount(variableDescriptorCount);
	if (descCnt == 0) { return; }
	
	auto* argDesc = [MTLArgumentDescriptor argumentDescriptor];
	argDesc.dataType = dataType;
	argDesc.access = access;
	argDesc.index = argIndex;
	argDesc.arrayLength = descCnt;
	argDesc.textureType = MTLTextureType2D;

	[args addObject: argDesc];
}

uint8_t MVKDescriptorSetLayoutBinding::getMaxPlaneCount() {
	uint8_t maxPlaneCnt = 1;
	for (auto* mvkSamp : _immutableSamplers) {
		maxPlaneCnt = std::max(maxPlaneCnt, mvkSamp->getPlaneCount());
	}
	return maxPlaneCnt;
}

uint32_t MVKDescriptorSetLayoutBinding::getMTLResourceCount(uint32_t variableDescriptorCount) {
	uint32_t rezCntPerElem = 1;
	switch (_info.descriptorType) {
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			rezCntPerElem = getMaxPlaneCount() + 1;
			break;
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			rezCntPerElem = getMetalFeatures().nativeTextureAtomics ? 1 : 2;
			break;
		default:
			break;
	}
	return rezCntPerElem * getDescriptorCount(variableDescriptorCount);
}

// Encodes an immutable sampler to the Metal argument buffer.
void MVKDescriptorSetLayoutBinding::encodeImmutableSamplersToMetalArgumentBuffer(MVKDescriptorSet* mvkDescSet) {
	if ( !mvkDescSet->hasMetalArgumentBuffer() ) { return; }

	auto& mvkArgBuff = mvkDescSet->getMetalArgumentBuffer();
	size_t sCnt = _immutableSamplers.size();
	for (uint32_t sIdx = 0; sIdx < sCnt; sIdx++) {
		MVKSampler* mvkSamp = _immutableSamplers[sIdx];
		id<MTLSamplerState> mtlSamp = (mvkSamp
									   ? mvkSamp->getMTLSamplerState()
									   : getDevice()->getDefaultMTLSamplerState());
		uint32_t argIdx = getMetalResourceIndexOffsets().samplerIndex + sIdx;
		mvkArgBuff.setSamplerState(mtlSamp, argIdx);
	}
}

void MVKDescriptorSetLayoutBinding::populateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
                                                                   MVKShaderResourceBinding& dslMTLRezIdxOffsets,
                                                                   uint32_t dslIndex) {
	bool isUsingMtlArgBuff = _layout->isUsingMetalArgumentBuffers();
	// GPUs prior to M3 & A17 cannot support true runtime arrays, so use full binding array size.
	// However, in doing so, it may be necessary to disable Apple shader validation errors on those systems,
	// when descriptors contain smaller runtime arrays than declared in the binding.
	bool useRuntimeArray = isUsingMtlArgBuff && getPhysicalDevice()->getMTLDeviceCapabilities().supportsApple9;
	uint32_t descCnt = useRuntimeArray ? getDescriptorCount(1) : getDescriptorCount();

	// Establish the resource indices to use, by combining the offsets of the DSL and this DSL binding.
    MVKShaderResourceBinding mtlIdxs = _mtlResourceIndexOffsets + dslMTLRezIdxOffsets;

	MVKSampler* mvkSamp = !_immutableSamplers.empty() ? _immutableSamplers.front() : nullptr;

	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
        if (_applyToStage[stage] || isUsingMtlArgBuff) {
            mvkPopulateShaderConversionConfig(shaderConfig,
                                              mtlIdxs.stages[stage],
                                              MVKShaderStage(stage),
                                              dslIndex,
                                              _info.binding,
											  descCnt,
											  getDescriptorType(),
											  mvkSamp,
											  getMetalFeatures().nativeTextureAtomics);
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

std::string MVKDescriptorSetLayoutBinding::getLogDescription(std::string indent) {
	uint32_t elemCnt = getDescriptorCount();
	std::stringstream descStr;
	descStr << getDescriptorIndex() << ": ";
	descStr << std::left << std::setw(46) << mvkVkDescriptorTypeName(getDescriptorType()) << std::setw(0);
	descStr << "with " << (hasVariableDescriptorCount() ? "up to " : "") << elemCnt << " elements";
	descStr << " at binding " << getBinding();
	if (elemCnt == 0) { descStr << " (inactive)"; }
	return descStr.str();
}

MVKDescriptorSetLayoutBinding::MVKDescriptorSetLayoutBinding(MVKDevice* device,
															 MVKDescriptorSetLayout* layout,
															 const VkDescriptorSetLayoutBinding* pBinding,
															 VkDescriptorBindingFlagsEXT bindingFlags,
															 uint32_t& dslDescCnt,
															 uint32_t& dslMTLRezCnt) :
	MVKBaseDeviceObject(device),
	_layout(layout),
	_info(*pBinding),
	_flags(bindingFlags),
	_descriptorIndex(dslDescCnt) {

	// If immutable samplers are defined, copy them in.
	// Do this before anything else, because they are referenced in getMaxPlaneCount().
	if ( _info.pImmutableSamplers &&
		(_info.descriptorType == VK_DESCRIPTOR_TYPE_SAMPLER ||
		 _info.descriptorType == VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) ) {

		_immutableSamplers.reserve(_info.descriptorCount);
		for (uint32_t i = 0; i < _info.descriptorCount; i++) {
			_immutableSamplers.push_back((MVKSampler*)_info.pImmutableSamplers[i]);
			_immutableSamplers.back()->retain();
		}
	}
	_info.pImmutableSamplers = nullptr;     // Remove dangling pointer

	// Determine if this binding is used by this shader stage, and initialize resource indexes.
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		_applyToStage[stage] = mvkAreAllFlagsEnabled(pBinding->stageFlags, mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage(stage)));
		initMetalResourceIndexOffsets(pBinding, stage, dslMTLRezCnt);
	}

	// Update descriptor set layout counts
	uint32_t descCnt = getDescriptorCount();
	dslDescCnt += descCnt;
	dslMTLRezCnt += getMTLResourceCount();
	if (mvkNeedsBuffSizeAuxBuffer(pBinding)) {
		_layout->_maxBufferIndex = std::max(_layout->_maxBufferIndex, int32_t(_mtlResourceIndexOffsets.getMaxBufferIndex() + descCnt) - 1);
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
void MVKDescriptorSetLayoutBinding::initMetalResourceIndexOffsets(const VkDescriptorSetLayoutBinding* pBinding,
																  uint32_t stage,
																  uint32_t dslMTLRezCnt) {
	// Sets an index offset and updates both that index and the general resource index.
	// Can be used more than once for combined multi-resource descriptor types.
	// When using Metal argument buffers, we accumulate the resource indexes cummulatively, across all resource types.
#define setResourceIndexOffset(rezIdx, mtlRezCntPerElem)	\
if (isUsingMtlArgBuff) {									\
	bindIdxs.rezIdx = dslMTLRezCnt + descIdxOfst;			\
	descIdxOfst += descCnt * mtlRezCntPerElem;				\
} else if (_applyToStage[stage]) {							\
	bindIdxs.rezIdx = dslCnts.rezIdx;						\
	dslCnts.rezIdx += descCnt * mtlRezCntPerElem;			\
}															\

	bool isUsingMtlArgBuff = _layout->isUsingMetalArgumentBuffers();
	auto& mtlFeats = getMetalFeatures();
	MVKShaderStageResourceBinding& bindIdxs = _mtlResourceIndexOffsets.stages[stage];
	MVKShaderStageResourceBinding& dslCnts = _layout->_mtlResourceCounts.stages[stage];

	uint32_t descIdxOfst = 0;	// Updated in setResourceIndexOffset() to accommodate it being called more than once per desc type.
	uint32_t descCnt = getDescriptorCount();
    switch (pBinding->descriptorType) {
        case VK_DESCRIPTOR_TYPE_SAMPLER:
			setResourceIndexOffset(samplerIndex, 1);

			if (pBinding->descriptorCount > 1 && !mtlFeats.arrayOfSamplers) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of samplers.", _device->getName()));
			}
            break;

        case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
			setResourceIndexOffset(textureIndex, getMaxPlaneCount());
			setResourceIndexOffset(samplerIndex, 1);

			if (pBinding->descriptorCount > 1) {
				if ( !mtlFeats.arrayOfTextures ) {
					_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of textures.", _device->getName()));
				}
				if ( !mtlFeats.arrayOfSamplers ) {
					_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of samplers.", _device->getName()));
				}
			}
            break;

        case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
        case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
        case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			setResourceIndexOffset(textureIndex, 1);

			if (pBinding->descriptorCount > 1 && !mtlFeats.arrayOfTextures) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of textures.", _device->getName()));
			}
            break;

		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
			setResourceIndexOffset(textureIndex, 1);
			if (!getMetalFeatures().nativeTextureAtomics) { setResourceIndexOffset(bufferIndex, 1); }

			if (pBinding->descriptorCount > 1 && !mtlFeats.arrayOfTextures) {
				_layout->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Device %s does not support arrays of textures.", _device->getName()));
			}
			break;

        case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
        case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
			setResourceIndexOffset(bufferIndex, 1);
            break;

		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			setResourceIndexOffset(bufferIndex, 1);
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

uint32_t MVKBufferDescriptor::getBufferSize(VkDeviceSize dynamicOffset) {
	return uint32_t((_buffRange == VK_WHOLE_SIZE
					 ? _mvkBuffer->getByteCount() - (_mvkBuffer->getMTLBufferOffset() + _buffOffset + dynamicOffset)
					 : _buffRange));
}

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
		bb.size = getBufferSize(bufferDynamicOffset);
	}
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		if (stages[i]) {
			bb.index = mtlIndexes.stages[i].bufferIndex + elementIndex;
			BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
		}
	}
}

void MVKBufferDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
								MVKDescriptorSet* mvkDescSet,
								uint32_t dstIdx,
								uint32_t srcIdx,
								size_t srcStride,
								const void* pData) {
	auto* oldBuff = _mvkBuffer;

	const auto* pBuffInfo = &get<VkDescriptorBufferInfo>(pData, srcStride, srcIdx);
	_mvkBuffer = (MVKBuffer*)pBuffInfo->buffer;
	_buffOffset = pBuffInfo->offset;
	_buffRange = pBuffInfo->range;

	if (_mvkBuffer) { _mvkBuffer->retain(); }
	if (oldBuff) { oldBuff->release(); }

	// Write resource to Metal argument buffer
	if (mvkDescSet->hasMetalArgumentBuffer()) {
		auto& mvkArgBuff = mvkDescSet->getMetalArgumentBuffer();
		uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().bufferIndex + dstIdx;
		mvkArgBuff.setBuffer(_mvkBuffer ? _mvkBuffer->getMTLBuffer() : nil,
							 _mvkBuffer ? _mvkBuffer->getMTLBufferOffset() + _buffOffset : 0,
							 argIdx);
		mvkDescSet->setBufferSize(argIdx, getBufferSize());
	}
}

void MVKBufferDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
							   MVKDescriptorSet* mvkDescSet,
							   uint32_t dstIndex,
							   VkDescriptorImageInfo* pImageInfo,
							   VkDescriptorBufferInfo* pBufferInfo,
							   VkBufferView* pTexelBufferView,
							   VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {
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

void MVKBufferDescriptor::encodeResourceUsage(MVKResourcesCommandEncoderState* rezEncState,
											  MVKDescriptorSetLayoutBinding* mvkDSLBind,
											  MVKShaderStage stage) {
	id<MTLBuffer> mtlBuffer = _mvkBuffer ? _mvkBuffer->getMTLBuffer() : nil;
	rezEncState->encodeResourceUsage(stage, mtlBuffer, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
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

uint32_t MVKInlineUniformBlockDescriptor::writeBytes(MVKDescriptorSetLayoutBinding* mvkDSLBind,
													 MVKDescriptorSet* mvkDescSet,
													 uint32_t dstOffset,
													 uint32_t srcOffset,
													 uint32_t byteCount,
													 const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {
	uint32_t dataLen = 0;
	uint32_t dstBuffSize = mvkDSLBind->_info.descriptorCount;
	uint32_t srcBuffSize = pInlineUniformBlock->dataSize;
	if (dstOffset < dstBuffSize && srcOffset < srcBuffSize) {
		dataLen = std::min({ byteCount, dstBuffSize - dstOffset, srcBuffSize - srcOffset });
	}

	// Ensure there is a destination to write to
	if ( !_mvkMTLBufferAllocation ) { _mvkMTLBufferAllocation = mvkDescSet->acquireMTLBufferRegion(dstBuffSize); }

	uint8_t* pDstData = getData();
	uint8_t* pSrcData = (uint8_t*)pInlineUniformBlock->pData;
	if (pDstData && pSrcData && dataLen) {
		memcpy(pDstData + dstOffset, pSrcData + srcOffset, dataLen);
	}

	// Write resource to Metal argument buffer
	if (mvkDescSet->hasMetalArgumentBuffer()) {
		auto& mvkArgBuff = mvkDescSet->getMetalArgumentBuffer();
		uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().bufferIndex;
		mvkArgBuff.setBuffer(_mvkMTLBufferAllocation ? _mvkMTLBufferAllocation->_mtlBuffer : nil,
							 _mvkMTLBufferAllocation ? _mvkMTLBufferAllocation->_offset : 0,
							 argIdx);
	}

	return dataLen;
}

uint32_t MVKInlineUniformBlockDescriptor::readBytes(MVKDescriptorSetLayoutBinding* mvkDSLBind,
													MVKDescriptorSet* mvkDescSet,
													uint32_t dstOffset,
													uint32_t srcOffset,
													uint32_t byteCount,
													const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {
	uint32_t dataLen = 0;
	uint32_t dstBuffSize = pInlineUniformBlock->dataSize;
	uint32_t srcBuffSize = mvkDSLBind->_info.descriptorCount;
	if (dstOffset < dstBuffSize && srcOffset < srcBuffSize) {
		dataLen = std::min({ byteCount, dstBuffSize - dstOffset, srcBuffSize - srcOffset });
	}

	uint8_t* pDstData = (uint8_t*)pInlineUniformBlock->pData;
	uint8_t* pSrcData = getData();
	if (pDstData && pSrcData && dataLen) {
		memcpy(pDstData + dstOffset, pSrcData + srcOffset, dataLen);
	}
	return dataLen;
}

void MVKInlineUniformBlockDescriptor::encodeResourceUsage(MVKResourcesCommandEncoderState* rezEncState,
														  MVKDescriptorSetLayoutBinding* mvkDSLBind,
														  MVKShaderStage stage) {
	id<MTLBuffer> mtlBuffer = _mvkMTLBufferAllocation ? _mvkMTLBufferAllocation->_mtlBuffer : nil;
	rezEncState->encodeResourceUsage(stage, mtlBuffer, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
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
                if (descType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE && !cmdEncoder->getMetalFeatures().nativeTextureAtomics) {
                    bb.index = mtlIndexes.stages[i].bufferIndex + elementIndex + planeIndex;
                    BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
                }
            }
        }
    }
}

void MVKImageDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
							   MVKDescriptorSet* mvkDescSet,
							   uint32_t dstIdx,
							   uint32_t srcIdx,
							   size_t srcStride,
							   const void* pData) {
	auto* oldImgView = _mvkImageView;

	const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, srcStride, srcIdx);
	_mvkImageView = (MVKImageView*)pImgInfo->imageView;

	if (_mvkImageView) { _mvkImageView->retain(); }
	if (oldImgView) { oldImgView->release(); }

	// Write resource to Metal argument buffer
	if (mvkDescSet->hasMetalArgumentBuffer()) {
		auto& mvkArgBuff = mvkDescSet->getMetalArgumentBuffer();
		VkDescriptorType descType = getDescriptorType();

		uint8_t planeCount = (_mvkImageView) ? _mvkImageView->getPlaneCount() : 1;
		for (uint8_t planeIndex = 0; planeIndex < planeCount; planeIndex++) {
			uint32_t planeDescIdx = (dstIdx * planeCount) + planeIndex;

			id<MTLTexture> mtlTexture = _mvkImageView ? _mvkImageView->getMTLTexture(planeIndex) : nil;
			uint32_t texArgIdx = mvkDSLBind->getMetalResourceIndexOffsets().textureIndex + planeDescIdx;
			mvkArgBuff.setTexture(mtlTexture, texArgIdx);

			if (descType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE && !mvkDSLBind->getMetalFeatures().nativeTextureAtomics) {
				id<MTLTexture> mtlTex = mtlTexture.parentTexture ? mtlTexture.parentTexture : mtlTexture;
				id<MTLBuffer> mtlBuff = mtlTex.buffer;
				if (mtlBuff) {
					uint32_t buffArgIdx = mvkDSLBind->getMetalResourceIndexOffsets().bufferIndex + planeDescIdx;
					mvkArgBuff.setBuffer(mtlBuff, mtlTex.bufferOffset, buffArgIdx);
				}
			}
		}
	}
}

void MVKImageDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
							  MVKDescriptorSet* mvkDescSet,
							  uint32_t dstIndex,
							  VkDescriptorImageInfo* pImageInfo,
							  VkDescriptorBufferInfo* pBufferInfo,
							  VkBufferView* pTexelBufferView,
							  VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {
	auto& imgInfo = pImageInfo[dstIndex];
	imgInfo.imageView = (VkImageView)_mvkImageView;
	imgInfo.imageLayout = VK_IMAGE_LAYOUT_UNDEFINED;
}

void MVKImageDescriptor::encodeResourceUsage(MVKResourcesCommandEncoderState* rezEncState,
											 MVKDescriptorSetLayoutBinding* mvkDSLBind,
											 MVKShaderStage stage) {
	VkDescriptorType descType = getDescriptorType();
	uint8_t planeCount = (_mvkImageView) ? _mvkImageView->getPlaneCount() : 1;
	for (uint8_t planeIndex = 0; planeIndex < planeCount; planeIndex++) {
		id<MTLTexture> mtlTexture = _mvkImageView ? _mvkImageView->getMTLTexture(planeIndex) : nil;
		rezEncState->encodeResourceUsage(stage, mtlTexture, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());

		if (descType == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE && !mvkDSLBind->getMetalFeatures().nativeTextureAtomics) {
			id<MTLTexture> mtlTex = mtlTexture.parentTexture ? mtlTexture.parentTexture : mtlTexture;
			id<MTLBuffer> mtlBuff = mtlTex.buffer;
			if (mtlBuff) {
				rezEncState->encodeResourceUsage(stage, mtlBuff, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
			}
		}
	}
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

void MVKSamplerDescriptorMixin::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									  MVKDescriptorSet* mvkDescSet,
									  uint32_t dstIdx,
									  uint32_t srcIdx,
									  size_t srcStride,
									  const void* pData) {

	if (mvkDSLBind->usesImmutableSamplers()) { return; }

	auto* oldSamp = _mvkSampler;

	const auto* pImgInfo = &get<VkDescriptorImageInfo>(pData, srcStride, srcIdx);
	_mvkSampler = (MVKSampler*)pImgInfo->sampler;
	if (_mvkSampler && _mvkSampler->getRequiresConstExprSampler()) {
		_mvkSampler->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkUpdateDescriptorSets(): Tried to push an immutable sampler.");
	}

	if (_mvkSampler) { _mvkSampler->retain(); }
	if (oldSamp) { oldSamp->release(); }

	// Write resource to Metal argument buffer
	if (mvkDescSet->hasMetalArgumentBuffer()) {
		auto& mvkArgBuff = mvkDescSet->getMetalArgumentBuffer();
		MVKSampler* imutSamp = mvkDSLBind->getImmutableSampler(dstIdx);
		MVKSampler* mvkSamp = imutSamp ? imutSamp : _mvkSampler;
		id<MTLSamplerState> mtlSamp = (mvkSamp
									   ? mvkSamp->getMTLSamplerState()
									   : mvkDSLBind->getDevice()->getDefaultMTLSamplerState());
		uint32_t argIdx = mvkDSLBind->getMetalResourceIndexOffsets().samplerIndex + dstIdx;
		mvkArgBuff.setSamplerState(mtlSamp, argIdx);
	}
}

void MVKSamplerDescriptorMixin::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 MVKDescriptorSet* mvkDescSet,
									 uint32_t dstIndex,
									 VkDescriptorImageInfo* pImageInfo,
									 VkDescriptorBufferInfo* pBufferInfo,
									 VkBufferView* pTexelBufferView,
									 VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {
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

void MVKSamplerDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
								 MVKDescriptorSet* mvkDescSet,
								 uint32_t dstIdx,
								 uint32_t srcIdx,
								 size_t srcStride,
								 const void* pData) {
	MVKSamplerDescriptorMixin::write(mvkDSLBind, mvkDescSet, dstIdx, srcIdx, srcStride, pData);
}

void MVKSamplerDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
								MVKDescriptorSet* mvkDescSet,
								uint32_t dstIndex,
								VkDescriptorImageInfo* pImageInfo,
								VkDescriptorBufferInfo* pBufferInfo,
								VkBufferView* pTexelBufferView,
								VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {
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

void MVKCombinedImageSamplerDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
											  MVKDescriptorSet* mvkDescSet,
											  uint32_t dstIdx,
											  uint32_t srcIdx,
											  size_t srcStride,
											  const void* pData) {
	MVKImageDescriptor::write(mvkDSLBind, mvkDescSet, dstIdx, srcIdx, srcStride, pData);
	MVKSamplerDescriptorMixin::write(mvkDSLBind, mvkDescSet, dstIdx, srcIdx, srcStride, pData);
}

void MVKCombinedImageSamplerDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
											 MVKDescriptorSet* mvkDescSet,
											 uint32_t dstIndex,
											 VkDescriptorImageInfo* pImageInfo,
											 VkDescriptorBufferInfo* pBufferInfo,
											 VkBufferView* pTexelBufferView,
											 VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {
	MVKImageDescriptor::read(mvkDSLBind, mvkDescSet, dstIndex, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
	MVKSamplerDescriptorMixin::read(mvkDSLBind, mvkDescSet, dstIndex, pImageInfo, pBufferInfo, pTexelBufferView, pInlineUniformBlock);
}

void MVKCombinedImageSamplerDescriptor::encodeResourceUsage(MVKResourcesCommandEncoderState* rezEncState,
															MVKDescriptorSetLayoutBinding* mvkDSLBind,
															MVKShaderStage stage) {
	MVKImageDescriptor::encodeResourceUsage(rezEncState, mvkDSLBind, stage);
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
			if (descType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER && !cmdEncoder->getMetalFeatures().nativeTextureAtomics) {
				bb.index = mtlIndexes.stages[i].bufferIndex + elementIndex;
				BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bindBuffer, pipelineBindPoint, i, bb);
			}
		}
	}
}

void MVKTexelBufferDescriptor::write(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									 MVKDescriptorSet* mvkDescSet,
									 uint32_t dstIdx,
									 uint32_t srcIdx,
									 size_t srcStride,
									 const void* pData) {
	auto* oldBuffView = _mvkBufferView;

	const auto* pBuffView = &get<VkBufferView>(pData, srcStride, srcIdx);
	_mvkBufferView = (MVKBufferView*)*pBuffView;

	if (_mvkBufferView) { _mvkBufferView->retain(); }
	if (oldBuffView) { oldBuffView->release(); }

	// Write resource to Metal argument buffer
	if (mvkDescSet->hasMetalArgumentBuffer()) {
		auto& mvkArgBuff = mvkDescSet->getMetalArgumentBuffer();
		VkDescriptorType descType = getDescriptorType();
		id<MTLTexture> mtlTexture = _mvkBufferView ? _mvkBufferView->getMTLTexture() : nil;
		uint32_t texArgIdx = mvkDSLBind->getMetalResourceIndexOffsets().textureIndex + dstIdx;
		mvkArgBuff.setTexture(mtlTexture, texArgIdx);

		if (descType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER && !mvkDSLBind->getMetalFeatures().nativeTextureAtomics) {
			id<MTLBuffer> mtlBuff = mtlTexture.buffer;
			if (mtlBuff) {
				uint32_t buffArgIdx = mvkDSLBind->getMetalResourceIndexOffsets().bufferIndex + dstIdx;
				mvkArgBuff.setBuffer(mtlBuff, mtlTexture.bufferOffset, buffArgIdx);
			}
		}
	}
}

void MVKTexelBufferDescriptor::read(MVKDescriptorSetLayoutBinding* mvkDSLBind,
									MVKDescriptorSet* mvkDescSet,
									uint32_t dstIndex,
									VkDescriptorImageInfo* pImageInfo,
									VkDescriptorBufferInfo* pBufferInfo,
									VkBufferView* pTexelBufferView,
									VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock) {
	pTexelBufferView[dstIndex] = (VkBufferView)_mvkBufferView;
}

void MVKTexelBufferDescriptor::encodeResourceUsage(MVKResourcesCommandEncoderState* rezEncState,
												   MVKDescriptorSetLayoutBinding* mvkDSLBind,
												   MVKShaderStage stage) {
	VkDescriptorType descType = getDescriptorType();
	id<MTLTexture> mtlTexture = _mvkBufferView ? _mvkBufferView->getMTLTexture() : nil;
	rezEncState->encodeResourceUsage(stage, mtlTexture, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());

	if (descType == VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER && !mvkDSLBind->getMetalFeatures().nativeTextureAtomics) {
		id<MTLBuffer> mtlBuff = mtlTexture.buffer;
		if (mtlBuff) {
			rezEncState->encodeResourceUsage(stage, mtlBuff, getMTLResourceUsage(), mvkDSLBind->getMTLRenderStages());
		}
	}
}

void MVKTexelBufferDescriptor::reset() {
	if (_mvkBufferView) { _mvkBufferView->release(); }
	_mvkBufferView = nullptr;
	MVKDescriptor::reset();
}


#pragma mark -
#pragma mark Support functions


bool mvkNeedsBuffSizeAuxBuffer(const VkDescriptorSetLayoutBinding* pBinding) {
	switch (pBinding->descriptorType) {
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return pBinding->descriptorCount > 0;

		case VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK:
			return true;
		
		default:
			return false;
	}
}


#define CASE_STRINGIFY(V)  case V: return #V

const char* mvkVkDescriptorTypeName(VkDescriptorType vkDescType) {
	switch (vkDescType) {
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_SAMPLER);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_NV);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_SAMPLE_WEIGHT_IMAGE_QCOM);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_BLOCK_MATCH_IMAGE_QCOM);
		CASE_STRINGIFY(VK_DESCRIPTOR_TYPE_MUTABLE_EXT);
		default: return "VK_UNKNOWN_VkDescriptorType";
	}
}
