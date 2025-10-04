/*
 * MVKPipeline.mm
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

#include "MVKPipeline.h"
#include "MVKCommandBuffer.h"
#include "MVKInlineObjectConstructor.h"
#include "MVKImage.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKStrings.h"
#include "MTLRenderPipelineDescriptor+MoltenVK.h"
#include "mvk_datatypes.hpp"
#include <sys/stat.h>
#include <sstream>

#ifndef MVK_USE_CEREAL
#define MVK_USE_CEREAL (1)
#endif

#if MVK_USE_CEREAL
#include <cereal/archives/binary.hpp>
#include <cereal/types/map.hpp>
#include <cereal/types/string.hpp>
#include <cereal/types/vector.hpp>
#endif

using namespace std;
using namespace mvk;
using namespace SPIRV_CROSS_NAMESPACE;


#pragma mark - MVKPipelineLayout

bool MVKPipelineLayout::stageUsesPushConstants(MVKShaderStage stage) const {
	return mvkIsAnyFlagEnabled(_pushConstantStages, mvkVkShaderStageFlagBitsFromMVKShaderStage(stage));
}

/** Gets the layout for use with the Metal binding API (rather than argument buffers). */
static MVKDescriptorGPULayout getBindingLayout(const MVKDescriptorBinding& binding) {
	bool hasSampler = (binding.perDescriptorResourceCount.sampler > 0) | binding.hasImmutableSamplers();
	bool hasTexture = binding.perDescriptorResourceCount.texture > 0;
	bool hasBuffer = binding.perDescriptorResourceCount.buffer > 0;
	if (hasSampler) {
		return hasTexture ? MVKDescriptorGPULayout::TexSampSoA : MVKDescriptorGPULayout::Sampler;
	} else if (hasBuffer) {
		return hasTexture ? MVKDescriptorGPULayout::TexBufSoA  : MVKDescriptorGPULayout::Buffer;
	} else  {
		return hasTexture ? MVKDescriptorGPULayout::Texture    : MVKDescriptorGPULayout::None;
	}
}

static spv::ExecutionModel spvExecModelForStage(MVKShaderStage stage) {
	switch (stage) {
		case kMVKShaderStageVertex:   return spv::ExecutionModelVertex;
		case kMVKShaderStageTessCtl:  return spv::ExecutionModelTessellationControl;
		case kMVKShaderStageTessEval: return spv::ExecutionModelTessellationEvaluation;
		case kMVKShaderStageFragment: return spv::ExecutionModelFragment;
		case kMVKShaderStageCompute:  return spv::ExecutionModelGLCompute;
		case kMVKShaderStageCount:
			break;
	}
	assert(!"Invalid stage");
	return spv::ExecutionModelMax;
}

static mvk::MSLResourceBinding makeResourceBinding(const MVKShaderStageResourceBinding& binding,
                                                   MVKShaderStage stage,
                                                   uint32_t descriptorSetIndex,
                                                   uint32_t bindingIndex,
                                                   uint32_t count,
                                                   SPIRV_CROSS_NAMESPACE::SPIRType::BaseType type,
                                                   MVKSampler* immutableSampler)
{
	mvk::MSLResourceBinding rb;
	auto& rbb = rb.resourceBinding;
	rbb.stage = spvExecModelForStage(stage);
	rbb.basetype = type;
	rbb.desc_set = descriptorSetIndex;
	rbb.binding = bindingIndex;
	rbb.count = count;
	rbb.msl_buffer = binding.bufferIndex;
	rbb.msl_texture = binding.textureIndex;
	rbb.msl_sampler = binding.samplerIndex;
	if (immutableSampler) { immutableSampler->getConstexprSampler(rb); }
	return rb;
}

static mvk::DescriptorBinding makeDescriptorBinding(MVKShaderStage stage, uint32_t descriptorSetIndex, uint32_t bindingIndex, uint32_t dynamicOffsetIndex) {
	mvk::DescriptorBinding db;
	db.stage = spvExecModelForStage(stage);
	db.descriptorSet = descriptorSetIndex;
	db.binding = bindingIndex;
	db.index = dynamicOffsetIndex;
	return db;
}

static void addResourceBindingToShaderConfig(SPIRVToMSLConversionConfiguration& shaderConfig,
                                             const MVKShaderStageResourceBinding& binding,
                                             MVKShaderStage stage,
                                             uint32_t descriptorSetIndex,
                                             uint32_t bindingIndex,
                                             uint32_t count,
                                             MVKDescriptorGPULayout layout,
                                             MVKSampler* immutableSampler = nullptr)
{
	using SPIRV_CROSS_NAMESPACE::SPIRType;
	if (count == 0) { return; }

	switch (layout) {
		case MVKDescriptorGPULayout::Texture:
			shaderConfig.resourceBindings.push_back(makeResourceBinding(binding, stage, descriptorSetIndex, bindingIndex, count, SPIRType::Image, immutableSampler));
			break;
		case MVKDescriptorGPULayout::Sampler:
			shaderConfig.resourceBindings.push_back(makeResourceBinding(binding, stage, descriptorSetIndex, bindingIndex, count, SPIRType::Sampler, immutableSampler));
			break;
		case MVKDescriptorGPULayout::Buffer:
		case MVKDescriptorGPULayout::BufferAuxSize:
			shaderConfig.resourceBindings.push_back(makeResourceBinding(binding, stage, descriptorSetIndex, bindingIndex, count, SPIRType::Void, immutableSampler));
			break;
		case MVKDescriptorGPULayout::OutlinedData:
			shaderConfig.resourceBindings.push_back(makeResourceBinding(binding, stage, descriptorSetIndex, bindingIndex, 1, SPIRType::Void, immutableSampler));
			break;
		case MVKDescriptorGPULayout::TexBufSoA:
			shaderConfig.resourceBindings.push_back(makeResourceBinding(binding, stage, descriptorSetIndex, bindingIndex, count, SPIRType::Image, immutableSampler));
			shaderConfig.resourceBindings.push_back(makeResourceBinding(binding, stage, descriptorSetIndex, bindingIndex, count, SPIRType::Void,  immutableSampler));
			break;
		case MVKDescriptorGPULayout::TexSampSoA:
		case MVKDescriptorGPULayout::Tex2SampSoA:
		case MVKDescriptorGPULayout::Tex3SampSoA:
			shaderConfig.resourceBindings.push_back(makeResourceBinding(binding, stage, descriptorSetIndex, bindingIndex, count, SPIRType::SampledImage, immutableSampler));
			break;

		case MVKDescriptorGPULayout::None:
			return;

		case MVKDescriptorGPULayout::InlineData:
			assert(!"SPIRV-Cross doesn't currently support inline data");
			return;
	}
}

void MVKPipelineLayout::populateShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig) const {
	shaderConfig.resourceBindings.clear();
	shaderConfig.discreteDescriptorSets.clear();
	shaderConfig.dynamicBufferDescriptors.clear();

	// Add any resource bindings used by push-constants.
	for (uint32_t i = 0; i < kMVKShaderStageCount; i++) {
		auto stage = static_cast<MVKShaderStage>(i);
		if (stageUsesPushConstants(stage)) {
			MVKShaderStageResourceBinding binding = {};
			binding.bufferIndex = getPushConstantResourceIndex(stage);
			addResourceBindingToShaderConfig(shaderConfig, binding, stage, kPushConstDescSet, kPushConstBinding, 1, MVKDescriptorGPULayout::Buffer);
		}
	}

	for (uint32_t dslIdx = 0; dslIdx < _descriptorSetLayouts.size(); dslIdx++) {
		MVKDescriptorSetLayout* layout = _descriptorSetLayouts[dslIdx];
		MVKShaderResourceBinding binding = _resourceIndexOffsets[dslIdx];
		uint32_t argBufResIdx = 0;
		bool argbuf = layout->argBufMode() != MVKArgumentBufferMode::Off;
		if (argbuf) {
			if (layout->needsSizeBuf()) {
				argBufResIdx++;
				for (uint32_t i = 0; i < kMVKShaderStageCount; i++) {
					auto stage = static_cast<MVKShaderStage>(i);
					addResourceBindingToShaderConfig(shaderConfig, {}, stage, dslIdx, kBufferSizeBufferBinding, 1, MVKDescriptorGPULayout::Buffer);
				}
			}
		}
		for (const MVKDescriptorBinding& desc : layout->bindings()) {
			MVKShaderStageResourceBinding resCount = desc.totalResourceCount();
			for (uint32_t i = 0; i < kMVKShaderStageCount; i++) {
				auto stage = static_cast<MVKShaderStage>(i);
				bool used = mvkIsAnyFlagEnabled(desc.stageFlags, mvkVkShaderStageFlagBitsFromMVKShaderStage(stage));
				if (argbuf) {
					binding.stages[stage].textureIndex = argBufResIdx;
					binding.stages[stage].bufferIndex = argBufResIdx + resCount.textureIndex;
					binding.stages[stage].samplerIndex = argBufResIdx + resCount.textureIndex;
				} else if (!used) {
					continue;
				}

				MVKSampler*const* immSamp = layout->getImmutableSampler(desc);
				MVKDescriptorGPULayout gpuLayout = argbuf ? desc.gpuLayout : getBindingLayout(desc);
				addResourceBindingToShaderConfig(shaderConfig, binding.stages[stage], stage, dslIdx, desc.binding, desc.descriptorCount, gpuLayout, immSamp ? *immSamp : nullptr);
				if (desc.perDescriptorResourceCount.dynamicOffset != 0 && used) {
					shaderConfig.dynamicBufferDescriptors.push_back(makeDescriptorBinding(stage, dslIdx, desc.binding, binding.stages[stage].dynamicOffsetBufferIndex));
				}
				if (argbuf) {
					if (used && desc.perDescriptorResourceCount.dynamicOffset)
						binding.stages[stage].dynamicOffsetBufferIndex += desc.descriptorCount;
				} else {
					binding.stages[stage] += resCount;
				}
			}
			argBufResIdx += resCount.textureIndex + resCount.bufferIndex + resCount.samplerIndex;
		}
		if (isUsingMetalArgumentBuffers() && !argbuf) {
			shaderConfig.discreteDescriptorSets.push_back(dslIdx);
		}
	}
}

static bool hasDynamicBuffer(VkDescriptorType type) {
	switch (type) {
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
		case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			return true;
		default:
			return false;
	}
}

static bool hasBuffer(MVKDescriptorGPULayout layout) {
	switch (layout) {
		case MVKDescriptorGPULayout::Buffer:
		case MVKDescriptorGPULayout::BufferAuxSize:
		case MVKDescriptorGPULayout::TexBufSoA:
			return true;
		default:
			return false;
	}
}

static bool isWriteable(VkDescriptorType type) {
	switch (type) {
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
		case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC:
			return true;
		default:
			return false;
	}
}

void MVKPipelineLayout::populateBindOperations(MVKPipelineBindScript& script, const SPIRVToMSLConversionConfiguration& shaderConfig, spv::ExecutionModel execModel) {
	assert(script.ops.empty());

	for (const auto& mslBinding : shaderConfig.resourceBindings) {
		if (mslBinding.resourceBinding.stage != execModel || !mslBinding.outIsUsedByShader) { continue; }
		uint32_t set = mslBinding.resourceBinding.desc_set;
		uint32_t binding = mslBinding.resourceBinding.binding;
		if (set >= _descriptorSetLayouts.size()) { assert(set == kPushConstDescSet); continue; }
		// Aux buffers are always allocated out of the same buffer as the descriptor set itself, so they'll already be resident
		if (binding == kBufferSizeBufferBinding) { continue; }
		MVKDescriptorSetLayout* layout = _descriptorSetLayouts[set];
		uint32_t descIdx = layout->getBindingIndex(binding);
		if (descIdx >= layout->bindings().size()) { assert(!"Binding missing from layout"); continue; }
		const MVKDescriptorBinding& desc = layout->bindings()[descIdx];
		auto counts = desc.perDescriptorResourceCount;
		uint32_t nonTexOffset = counts.texture * sizeof(id);
		if (!desc.descriptorCount) { continue; }
		bool partiallyBound = mvkIsAnyFlagEnabled(desc.flags, MVK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT) || getMVKConfig().liveCheckAllResources;

		if (layout->argBufMode() == MVKArgumentBufferMode::Off) {
			if (desc.cpuLayout == MVKDescriptorCPULayout::InlineData) {
				script.ops.push_back({ MVKDescriptorBindOperationCode::BindBytes, set, mslBinding.resourceBinding.msl_buffer, descIdx });
			} else {
				MVKDescriptorBindOperationCode bindTex  = partiallyBound ? MVKDescriptorBindOperationCode::BindTextureWithLiveCheck : MVKDescriptorBindOperationCode::BindTexture;
				MVKDescriptorBindOperationCode bindBuf  = partiallyBound ? MVKDescriptorBindOperationCode::BindBufferWithLiveCheck  : MVKDescriptorBindOperationCode::BindBuffer ;
				MVKDescriptorBindOperationCode bindSamp = partiallyBound ? MVKDescriptorBindOperationCode::BindSamplerWithLiveCheck : MVKDescriptorBindOperationCode::BindSampler;
				MVKDescriptorBindOperationCode bindBufDyn = partiallyBound ? MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck : MVKDescriptorBindOperationCode::BindBufferDynamic;
				uint32_t nbind = desc.descriptorCount;
				for (uint32_t i = 0; i < counts.texture; i++) {
					script.ops.push_back({ bindTex, set, mslBinding.resourceBinding.msl_texture + i * nbind, descIdx, sizeof(id) * i });
				}

				if (hasDynamicBuffer(desc.descriptorType)) {
					uint32_t dynOffset = 0;
					auto it = std::find_if(shaderConfig.dynamicBufferDescriptors.begin(), shaderConfig.dynamicBufferDescriptors.end(), [&](auto& dynBuf){
						return dynBuf.stage == execModel && dynBuf.descriptorSet == set && dynBuf.binding == binding;
					});
					if (it == shaderConfig.dynamicBufferDescriptors.end()) {
						assert(0);
					} else {
						dynOffset = it->index;
					}
					script.ops.push_back({ bindBufDyn, set, mslBinding.resourceBinding.msl_buffer, descIdx, nonTexOffset, dynOffset });
				} else if (counts.buffer > 0) {
					script.ops.push_back({ bindBuf, set, mslBinding.resourceBinding.msl_buffer, descIdx, nonTexOffset });
				}
				if (counts.sampler > 0) {
					if (desc.hasImmutableSamplers())
						bindSamp = MVKDescriptorBindOperationCode::BindImmutableSampler;
					script.ops.push_back({ bindSamp, set, mslBinding.resourceBinding.msl_sampler, descIdx, nonTexOffset });
				}
			}
		} else if (!_device->hasResidencySet()) {
			MVKDescriptorBindOperationCode useTex = partiallyBound ? MVKDescriptorBindOperationCode::UseTextureWithLiveCheck : MVKDescriptorBindOperationCode::UseResource;
			MVKDescriptorBindOperationCode useBuf = partiallyBound ? MVKDescriptorBindOperationCode::UseBufferWithLiveCheck  : MVKDescriptorBindOperationCode::UseResource;
			MVKDescriptorGPULayout gpuLayout = desc.gpuLayout;
			uint32_t target = isWriteable(desc.descriptorType);
			for (uint32_t i = 0, n = descriptorTextureCount(gpuLayout); i < n; i++) {
				script.ops.push_back({ useTex, set, target, descIdx, sizeof(id) * i });
			}
			if (hasBuffer(gpuLayout)) {
				script.ops.push_back({ useBuf, set, target, descIdx, nonTexOffset });
			}
		}
	}
}

MVKPipelineLayout::MVKPipelineLayout(MVKDevice* device): MVKVulkanAPIDeviceObject(device) {}

MVKPipelineLayout* MVKPipelineLayout::Create(MVKDevice* device, const VkPipelineLayoutCreateInfo* pCreateInfo) {
	using Constructor = MVKInlineObjectConstructor<MVKPipelineLayout>;
	MVKArrayRef layouts(reinterpret_cast<MVKDescriptorSetLayout*const*>(pCreateInfo->pSetLayouts), pCreateInfo->setLayoutCount);

	MVKPipelineLayout* ret = Constructor::Create(
		std::tuple {
			Constructor::Copy(&MVKPipelineLayout::_descriptorSetLayouts, layouts),
			Constructor::Uninit(&MVKPipelineLayout::_resourceIndexOffsets, layouts.size()),
		},
		device
	);

	for (const VkPushConstantRange& range : MVKArrayRef(pCreateInfo->pPushConstantRanges, pCreateInfo->pushConstantRangeCount)) {
		ret->_pushConstantStages |= range.stageFlags;
		ret->_pushConstantsLength = std::max(ret->_pushConstantsLength, range.offset + range.size);
	}

	// MSL structs can have a larger size than the equivalent C struct due to MSL alignment needs.
	// Typically any MSL struct that contains a float4 will also have a size that is rounded up to a multiple of a float4 size.
	// Ensure that we pass along enough content to cover this extra space even if it is never actually accessed by the shader.
	ret->_pushConstantsLength = static_cast<uint32_t>(mvkAlignByteCount(ret->_pushConstantsLength, 16));

	// We do not need to do anything special for pipeline layout compatibility, as the state tracker handles rebinding as necessary.
	// However, if we try to bind things in a way that would support direct layout compatibility, the state tracker will need to do less rebinding of buffers.
	// So consume the Metal resource indexes in this order:
	//   - Fixed count of argument buffers for descriptor sets (if using Metal argument buffers).
	//   - Push constants
	//   - Descriptor set content

	// If we are using Metal argument buffers, consume a fixed number of buffer indices for the Metal argument buffers themselves.
	for (const MVKDescriptorSetLayout* layout : layouts) {
		if (layout->argBufMode() != MVKArgumentBufferMode::Off) {
			ret->_mtlResourceCounts.addArgumentBuffers(kMVKMaxDescriptorSetCount);
			break;
		}
	}

	for (uint32_t stage = 0; stage < kMVKShaderStageCount; stage++) {
		ret->_pushConstantResourceIndices[stage] = static_cast<uint8_t>(ret->_mtlResourceCounts.stages[stage].bufferIndex);
		if (ret->stageUsesPushConstants(static_cast<MVKShaderStage>(stage)))
			++ret->_mtlResourceCounts.stages[stage].bufferIndex;
	}

	for (size_t i = 0; i < layouts.size(); i++) {
		layouts[i]->retain();
		ret->_resourceIndexOffsets[i] = ret->_mtlResourceCounts;
		MVKShaderResourceBinding count = layouts[i]->totalResourceCount();
		if (layouts[i]->argBufMode() != MVKArgumentBufferMode::Off)
			count.clearArgumentBufferResources();
		ret->_mtlResourceCounts += count;
		if (layouts[i]->isPushDescriptorSetLayout())
			ret->_pushDescriptor = i;
	}

	return ret;
}

MVKPipelineLayout::~MVKPipelineLayout() {
	for (auto dsl : _descriptorSetLayouts) { dsl->release(); }
}

#pragma mark -
#pragma mark MVKPipeline

MVKPipeline::MVKPipeline(MVKDevice* device, MVKPipelineCache* pipelineCache, MVKPipelineLayout* layout,
						 VkPipelineCreateFlags2 flags, MVKPipeline* parent) :
	MVKVulkanAPIDeviceObject(device),
	_layout(layout),
	_pipelineCache(pipelineCache),
	_flags(flags),
	_descriptorSetCount(static_cast<uint32_t>(layout->getDescriptorSetCount())),
	_fullImageViewSwizzle(getMVKConfig().fullImageViewSwizzle) {

		layout->retain();

		// Establish descriptor counts and push constants use.
		for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
			_descriptorBufferCounts.stages[stage] = layout->getResourceCounts().stages[stage].bufferIndex;
			_stageUsesPushConstants[stage] = layout->stageUsesPushConstants((MVKShaderStage)stage);
		}
	}


MVKPipeline::~MVKPipeline() {
	_layout->release();
}

#pragma mark -
#pragma mark MVKGraphicsPipeline

/** Populate a MVKStageResourceBits based on the resources used by the given shader info. */
static void populateResourceUsage(MVKPipelineStageResourceInfo& dst, SPIRVToMSLConversionConfiguration& src, SPIRVToMSLConversionResultInfo& results, spv::ExecutionModel stage) {
	dst.usesPhysicalStorageBufferAddresses = results.usesPhysicalStorageBufferAddressesCapability;
	dst.implicitBuffers.needed |= MVKImplicitBufferList(MVKImplicitBuffer::Swizzle,       results.needsSwizzleBuffer);
	dst.implicitBuffers.needed |= MVKImplicitBufferList(MVKImplicitBuffer::Output,        results.needsOutputBuffer);
	dst.implicitBuffers.needed |= MVKImplicitBufferList(MVKImplicitBuffer::PatchOutput,   results.needsPatchOutputBuffer);
	dst.implicitBuffers.needed |= MVKImplicitBufferList(MVKImplicitBuffer::BufferSize,    results.needsBufferSizeBuffer);
	dst.implicitBuffers.needed |= MVKImplicitBufferList(MVKImplicitBuffer::DynamicOffset, results.needsDynamicOffsetBuffer);
	dst.implicitBuffers.needed |= MVKImplicitBufferList(MVKImplicitBuffer::DispatchBase,  results.needsDispatchBaseBuffer);
	dst.implicitBuffers.needed |= MVKImplicitBufferList(MVKImplicitBuffer::ViewRange,     results.needsViewRangeBuffer);

	typedef SPIRV_CROSS_NAMESPACE::SPIRType SPIRType;
	bool isArgBuf[kMVKMaxDescriptorSetCount] = {};
	bool isUsed[kMVKMaxDescriptorSetCount] = {};
	if (src.options.mslOptions.argument_buffers) {
		std::fill(std::begin(isArgBuf), std::end(isArgBuf), true);
		for (uint32_t set : src.discreteDescriptorSets)
			isArgBuf[set] = false;
	}
	for (const auto& binding : src.resourceBindings) {
		if (!binding.outIsUsedByShader)
			continue;
		if (binding.resourceBinding.stage != stage)
			continue;
		if (binding.resourceBinding.desc_set == kPushConstDescSet) {
			dst.implicitBuffers.needed.add(MVKImplicitBuffer::PushConstant);
			continue;
		}
		assert(binding.resourceBinding.desc_set < kMVKMaxDescriptorSetCount);
		isUsed[binding.resourceBinding.desc_set] = true;
		if (isArgBuf[binding.resourceBinding.desc_set])
			continue;
		uint32_t count = binding.resourceBinding.count;
		switch (binding.resourceBinding.basetype) {
			case SPIRType::Image:
			case SPIRType::SampledImage:
			case SPIRType::Sampler:
				if (binding.requiresConstExprSampler) {
					assert(binding.resourceBinding.basetype != SPIRType::Image);
					count *= std::max(binding.constExprSampler.planes, 1u);
					dst.resources.textures.setRange(binding.resourceBinding.msl_texture, binding.resourceBinding.msl_texture + count);
				} else {
					if (binding.resourceBinding.basetype != SPIRType::Image)
						dst.resources.samplers.setRange(binding.resourceBinding.msl_sampler, binding.resourceBinding.msl_sampler + count);
					if (binding.resourceBinding.basetype != SPIRType::Sampler)
						dst.resources.textures.setRange(binding.resourceBinding.msl_texture, binding.resourceBinding.msl_texture + count);
				}
				break;

			default:
				dst.resources.buffers.setRange(binding.resourceBinding.msl_buffer, binding.resourceBinding.msl_buffer + count);
				break;
		}
	}
	for (uint32_t i = 0; i < kMVKMaxDescriptorSetCount; i++) {
		if (isArgBuf[i] && isUsed[i]) {
			dst.resources.buffers.set(i);
			dst.resources.descriptorSetData.set(i);
		}
	}
}

// Do updates that may require a render pass restart immediately on bind.
void MVKGraphicsPipeline::wasBound(MVKCommandEncoder* cmdEncoder) {
	if (_hasRemappedAttachmentLocations) {
		cmdEncoder->updateColorAttachmentLocations(_colorAttachmentLocations.contents());
	}
}

void MVKGraphicsPipeline::getStages(MVKPiplineStages& stages) {
    if (isTessellationPipeline()) {
        stages.push_back(kMVKGraphicsStageVertex);
        stages.push_back(kMVKGraphicsStageTessControl);
    }
    stages.push_back(kMVKGraphicsStageRasterization);
}

static const char vtxCompilerType[] = "Vertex stage pipeline for tessellation";

bool MVKGraphicsPipeline::compileTessVertexStageState(MTLComputePipelineDescriptor* vtxPLDesc,
													  MVKMTLFunction* pVtxFunctions,
													  VkPipelineCreationFeedback* pVertexFB) {
	uint64_t startTime = 0;
    if (pVertexFB) {
		startTime = mvkGetTimestamp();
	}
	vtxPLDesc.computeFunction = pVtxFunctions[0].getMTLFunction();
    bool res = !!getOrCompilePipeline(vtxPLDesc, _mtlTessVertexStageState, vtxCompilerType);

	vtxPLDesc.computeFunction = pVtxFunctions[1].getMTLFunction();
    vtxPLDesc.stageInputDescriptor.indexType = MTLIndexTypeUInt16;
    for (uint32_t i = 0; i < 31; i++) {
		MTLBufferLayoutDescriptor* blDesc = vtxPLDesc.stageInputDescriptor.layouts[i];
        if (blDesc.stepFunction == MTLStepFunctionThreadPositionInGridX) {
                blDesc.stepFunction = MTLStepFunctionThreadPositionInGridXIndexed;
        }
    }
    res |= !!getOrCompilePipeline(vtxPLDesc, _mtlTessVertexStageIndex16State, vtxCompilerType);

	vtxPLDesc.computeFunction = pVtxFunctions[2].getMTLFunction();
    vtxPLDesc.stageInputDescriptor.indexType = MTLIndexTypeUInt32;
    res |= !!getOrCompilePipeline(vtxPLDesc, _mtlTessVertexStageIndex32State, vtxCompilerType);

	if (pVertexFB) {
		if (!res) {
			// Compilation of the shader will have enabled the flag, so I need to turn it off.
			mvkDisableFlags(pVertexFB->flags, VK_PIPELINE_CREATION_FEEDBACK_VALID_BIT);
		}
		pVertexFB->duration += mvkGetElapsedNanoseconds(startTime);
	}
	return res;
}

bool MVKGraphicsPipeline::compileTessControlStageState(MTLComputePipelineDescriptor* tcPLDesc,
													   VkPipelineCreationFeedback* pTessCtlFB) {
	uint64_t startTime = 0;
    if (pTessCtlFB) {
		startTime = mvkGetTimestamp();
	}
    bool res = !!getOrCompilePipeline(tcPLDesc, _mtlTessControlStageState, "Tessellation control");
	if (pTessCtlFB) {
		if (!res) {
			mvkDisableFlags(pTessCtlFB->flags, VK_PIPELINE_CREATION_FEEDBACK_VALID_BIT);
		}
		pTessCtlFB->duration += mvkGetElapsedNanoseconds(startTime);
	}
	return res;
}


#pragma mark Construction

// Extracts and returns a VkPipelineRenderingCreateInfo from the renderPass or pNext
// chain of pCreateInfo, or returns an empty struct if neither of those are found.
// Although the Vulkan spec is vague and unclear, there are CTS that set both renderPass
// and VkPipelineRenderingCreateInfo to null in VkGraphicsPipelineCreateInfo.
static const VkPipelineRenderingCreateInfo* getRenderingCreateInfo(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	if (pCreateInfo->renderPass) {
		return ((MVKRenderPass*)pCreateInfo->renderPass)->getSubpass(pCreateInfo->subpass)->getPipelineRenderingCreateInfo();
	}
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO: return (VkPipelineRenderingCreateInfo*)next;
			default: break;
		}
	}
	static VkPipelineRenderingCreateInfo emptyRendInfo = { .sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO };
	return &emptyRendInfo;
}

static bool isBufferRobustnessEnabled(const VkPipelineRobustnessBufferBehavior behavior) {
	return behavior == VK_PIPELINE_ROBUSTNESS_BUFFER_BEHAVIOR_ROBUST_BUFFER_ACCESS ||
		   behavior == VK_PIPELINE_ROBUSTNESS_BUFFER_BEHAVIOR_ROBUST_BUFFER_ACCESS_2;
}

template <typename T>
static const VkPipelineRobustnessCreateInfo* getRobustnessCreateInfo(const T* pCreateInfo) {
	const VkPipelineRobustnessCreateInfo* pRobustnessInfo = nullptr;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_PIPELINE_ROBUSTNESS_CREATE_INFO:
				pRobustnessInfo = (VkPipelineRobustnessCreateInfo*)next;
				break;
			default:
				break;
		}
	}
	return pRobustnessInfo;
}

template <typename T>
static void warnIfBufferRobustnessEnabled(MVKPipeline* pipeline, const T* pCreateInfo) {
	if (!pCreateInfo) return;

	const VkPipelineRobustnessCreateInfo* pRobustnessInfo = getRobustnessCreateInfo(pCreateInfo);
	if (!pRobustnessInfo) return;

	if (isBufferRobustnessEnabled(pRobustnessInfo->storageBuffers) ||
		isBufferRobustnessEnabled(pRobustnessInfo->uniformBuffers) ||
		isBufferRobustnessEnabled(pRobustnessInfo->vertexInputs)) {
		pipeline->reportWarning(VK_ERROR_FEATURE_NOT_PRESENT, "Metal does not support buffer robustness.");
	}
}

static MVKShaderModule* getOrCreateShaderModule(MVKDevice* device, const VkPipelineShaderStageCreateInfo* pCreateInfo,
                                                   bool& ownsShaderModule) {
	if (pCreateInfo && pCreateInfo->module == VK_NULL_HANDLE) {
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO:
					ownsShaderModule = true;
					return new MVKShaderModule(device, (VkShaderModuleCreateInfo*)next);
				default:
					break;
			}
		}
	}
	ownsShaderModule = false;
	return pCreateInfo ? (MVKShaderModule*)pCreateInfo->module : nullptr;
}

static MVKRenderStateFlags getRenderStateFlags(VkDynamicState vk) {
	switch (vk) {
		case VK_DYNAMIC_STATE_BLEND_CONSTANTS:             return MVKRenderStateFlag::BlendConstants;
		case VK_DYNAMIC_STATE_COLOR_BLEND_EQUATION_EXT:    return MVKRenderStateFlag::ColorBlend;
		case VK_DYNAMIC_STATE_COLOR_BLEND_ENABLE_EXT:      return MVKRenderStateFlag::ColorBlendEnable;
		case VK_DYNAMIC_STATE_CULL_MODE:                   return MVKRenderStateFlag::CullMode;
		case VK_DYNAMIC_STATE_DEPTH_BIAS:                  return MVKRenderStateFlag::DepthBias;
		case VK_DYNAMIC_STATE_DEPTH_BIAS_ENABLE:           return MVKRenderStateFlag::DepthBiasEnable;
		case VK_DYNAMIC_STATE_DEPTH_BOUNDS:                return MVKRenderStateFlag::DepthBounds;
		case VK_DYNAMIC_STATE_DEPTH_BOUNDS_TEST_ENABLE:    return MVKRenderStateFlag::DepthBoundsTestEnable;
		case VK_DYNAMIC_STATE_DEPTH_CLAMP_ENABLE_EXT:      return MVKRenderStateFlag::DepthClipEnable;
		case VK_DYNAMIC_STATE_DEPTH_CLIP_ENABLE_EXT:       return MVKRenderStateFlag::DepthClipEnable;
		case VK_DYNAMIC_STATE_DEPTH_COMPARE_OP:            return MVKRenderStateFlag::DepthCompareOp;
		case VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE:           return MVKRenderStateFlag::DepthTestEnable;
		case VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE:          return MVKRenderStateFlag::DepthWriteEnable;
		case VK_DYNAMIC_STATE_FRONT_FACE:                  return MVKRenderStateFlag::FrontFace;
		case VK_DYNAMIC_STATE_LINE_RASTERIZATION_MODE_EXT: return MVKRenderStateFlag::LineRasterizationMode;
		case VK_DYNAMIC_STATE_LINE_WIDTH:                  return MVKRenderStateFlag::LineWidth;
		case VK_DYNAMIC_STATE_LOGIC_OP_EXT:                return MVKRenderStateFlag::LogicOp;
		case VK_DYNAMIC_STATE_LOGIC_OP_ENABLE_EXT:         return MVKRenderStateFlag::LogicOpEnable;
		case VK_DYNAMIC_STATE_PATCH_CONTROL_POINTS_EXT:    return MVKRenderStateFlag::PatchControlPoints;
		case VK_DYNAMIC_STATE_POLYGON_MODE_EXT:            return MVKRenderStateFlag::PolygonMode;
		case VK_DYNAMIC_STATE_PRIMITIVE_RESTART_ENABLE:    return MVKRenderStateFlag::PrimitiveRestartEnable;
		case VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY:          return MVKRenderStateFlag::PrimitiveTopology;
		case VK_DYNAMIC_STATE_RASTERIZER_DISCARD_ENABLE:   return MVKRenderStateFlag::RasterizerDiscardEnable;
		case VK_DYNAMIC_STATE_SAMPLE_LOCATIONS_EXT:        return MVKRenderStateFlag::SampleLocations;
		case VK_DYNAMIC_STATE_SAMPLE_LOCATIONS_ENABLE_EXT: return MVKRenderStateFlag::SampleLocationsEnable;
		case VK_DYNAMIC_STATE_SCISSOR:                     return MVKRenderStateFlag::Scissors;
		case VK_DYNAMIC_STATE_SCISSOR_WITH_COUNT:          return MVKRenderStateFlag::Scissors;
		case VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK:        return MVKRenderStateFlag::StencilCompareMask;
		case VK_DYNAMIC_STATE_STENCIL_OP:                  return MVKRenderStateFlag::StencilOp;
		case VK_DYNAMIC_STATE_STENCIL_REFERENCE:           return MVKRenderStateFlag::StencilReference;
		case VK_DYNAMIC_STATE_STENCIL_TEST_ENABLE:         return MVKRenderStateFlag::StencilTestEnable;
		case VK_DYNAMIC_STATE_STENCIL_WRITE_MASK:          return MVKRenderStateFlag::StencilWriteMask;
		case VK_DYNAMIC_STATE_VERTEX_INPUT_BINDING_STRIDE: return MVKRenderStateFlag::VertexStride;
		case VK_DYNAMIC_STATE_VIEWPORT:                    return MVKRenderStateFlag::Viewports;
		case VK_DYNAMIC_STATE_VIEWPORT_WITH_COUNT:         return MVKRenderStateFlag::Viewports;
		default:                                           return {};
	}
}

static void loadStencil(MVKMTLStencilDescriptorData& mtl, const VkStencilOpState& vk) {
	mtl.readMask = vk.compareMask;
	mtl.writeMask = vk.writeMask;
	mtl.op.stencilCompareFunction = mvkMTLCompareFunctionFromVkCompareOp(vk.compareOp);
	mtl.op.stencilFailureOperation = mvkMTLStencilOperationFromVkStencilOp(vk.failOp);
	mtl.op.depthFailureOperation = mvkMTLStencilOperationFromVkStencilOp(vk.depthFailOp);
	mtl.op.depthStencilPassOperation = mvkMTLStencilOperationFromVkStencilOp(vk.passOp);
}

static bool usesConstantColor(VkBlendFactor factor) {
	switch (factor) {
		case VK_BLEND_FACTOR_CONSTANT_COLOR:
		case VK_BLEND_FACTOR_CONSTANT_ALPHA:
		case VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR:
		case VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA:
			return true;
		default:
			return false;
	}
}

static bool usesConstantColor(MVKRenderStateFlags dynamic, const VkPipelineColorBlendStateCreateInfo* info) {
	if (dynamic.has(MVKRenderStateFlag::ColorBlend))
		return true;
	for (const auto& attachment : MVKArrayRef(info->pAttachments, info->attachmentCount)) {
		if (usesConstantColor(attachment.srcColorBlendFactor)) return true;
		if (usesConstantColor(attachment.dstColorBlendFactor)) return true;
		if (usesConstantColor(attachment.srcAlphaBlendFactor)) return true;
		if (usesConstantColor(attachment.dstAlphaBlendFactor)) return true;
	}
	return false;
}

MVKGraphicsPipeline::MVKGraphicsPipeline(MVKDevice* device,
										 MVKPipelineCache* pipelineCache,
										 MVKPipeline* parent,
										 const VkGraphicsPipelineCreateInfo* pCreateInfo) :
	MVKPipeline(device, pipelineCache, (MVKPipelineLayout*)pCreateInfo->layout, getPipelineCreateFlags(pCreateInfo), parent)
{
	// Extract dynamic state first, as it can affect many configurations.
	initDynamicState(pCreateInfo);

	_primitiveTopologyClass = MTLPrimitiveTopologyClassUnspecified;
	if (pCreateInfo->pInputAssemblyState)
		_primitiveTopologyClass = mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology);
	if (!_dynamicStateFlags.has(MVKRenderStateFlag::PolygonMode) && pCreateInfo->pRasterizationState->polygonMode == VK_POLYGON_MODE_POINT)
		_primitiveTopologyClass = MTLPrimitiveTopologyClassPoint;

	// Determine rasterization early, as various other structs are validated and interpreted in this context.
	const VkPipelineRenderingCreateInfo* pRendInfo = getRenderingCreateInfo(pCreateInfo);
	_isRasterizing = !isRasterizationDisabled(pCreateInfo);
	_isRasterizingColor = _isRasterizing && mvkHasColorAttachments(pRendInfo);
	populateRenderingAttachmentInfo(pCreateInfo);

	const VkPipelineCreationFeedbackCreateInfo* pFeedbackInfo = nullptr;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_PIPELINE_CREATION_FEEDBACK_CREATE_INFO:
				pFeedbackInfo = (VkPipelineCreationFeedbackCreateInfo*)next;
				break;
			default:
				break;
		}
	}

	warnIfBufferRobustnessEnabled(this, pCreateInfo);

	// Initialize feedback. The VALID bit must be initialized, either set or cleared.
	// We'll set the VALID bits later, after successful compilation.
	VkPipelineCreationFeedback* pPipelineFB = nullptr;
	if (pFeedbackInfo) {
		pPipelineFB = pFeedbackInfo->pPipelineCreationFeedback;
		// n.b. Do *NOT* use mvkClear(). That would also clear the sType and pNext fields.
		pPipelineFB->flags = 0;
		pPipelineFB->duration = 0;
		for (uint32_t i = 0; i < pFeedbackInfo->pipelineStageCreationFeedbackCount; ++i) {
			pFeedbackInfo->pPipelineStageCreationFeedbacks[i].flags = 0;
			pFeedbackInfo->pPipelineStageCreationFeedbacks[i].duration = 0;
		}
	}

	// Get the shader stages. Do this now, because we need to extract
	// reflection data from them that informs everything else.
	const VkPipelineShaderStageCreateInfo* pVertexSS = nullptr;
	const VkPipelineShaderStageCreateInfo* pTessCtlSS = nullptr;
	const VkPipelineShaderStageCreateInfo* pTessEvalSS = nullptr;
	const VkPipelineShaderStageCreateInfo* pFragmentSS = nullptr;
	VkPipelineCreationFeedback* pVertexFB = nullptr;
	VkPipelineCreationFeedback* pTessCtlFB = nullptr;
	VkPipelineCreationFeedback* pTessEvalFB = nullptr;
	VkPipelineCreationFeedback* pFragmentFB = nullptr;
	for (uint32_t i = 0; i < pCreateInfo->stageCount; i++) {
		const auto* pSS = &pCreateInfo->pStages[i];
		switch (pSS->stage) {
			case VK_SHADER_STAGE_VERTEX_BIT:
				pVertexSS = pSS;
				if (pFeedbackInfo && pFeedbackInfo->pPipelineStageCreationFeedbacks) {
					pVertexFB = &pFeedbackInfo->pPipelineStageCreationFeedbacks[i];
				}
				break;
			case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:
				pTessCtlSS = pSS;
				if (pFeedbackInfo && pFeedbackInfo->pPipelineStageCreationFeedbacks) {
					pTessCtlFB = &pFeedbackInfo->pPipelineStageCreationFeedbacks[i];
				}
				break;
			case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:
				pTessEvalSS = pSS;
				if (pFeedbackInfo && pFeedbackInfo->pPipelineStageCreationFeedbacks) {
					pTessEvalFB = &pFeedbackInfo->pPipelineStageCreationFeedbacks[i];
				}
				break;
			case VK_SHADER_STAGE_FRAGMENT_BIT:
				pFragmentSS = pSS;
				if (pFeedbackInfo && pFeedbackInfo->pPipelineStageCreationFeedbacks) {
					pFragmentFB = &pFeedbackInfo->pPipelineStageCreationFeedbacks[i];
				}
				break;
			default:
				break;
		}
	}

	_vertexModule = getOrCreateShaderModule(device, pVertexSS, _ownsVertexModule);
	_tessCtlModule = getOrCreateShaderModule(device, pTessCtlSS, _ownsTessCtlModule);
	_tessEvalModule = getOrCreateShaderModule(device, pTessEvalSS, _ownsTessEvalModule);
	_fragmentModule = getOrCreateShaderModule(device, pFragmentSS, _ownsFragmentModule);

	warnIfBufferRobustnessEnabled(this, pVertexSS);
	warnIfBufferRobustnessEnabled(this, pTessCtlSS);
	warnIfBufferRobustnessEnabled(this, pTessEvalSS);
	warnIfBufferRobustnessEnabled(this, pFragmentSS);

	// Get the tessellation parameters from the shaders.
	SPIRVTessReflectionData reflectData;
	std::string reflectErrorLog;
	if (pTessCtlSS && pTessEvalSS) {
		_isTessellationPipeline = true;

		if (!getTessReflectionData(_tessCtlModule->getSPIRV(), pTessCtlSS->pName, _tessEvalModule->getSPIRV(), pTessEvalSS->pName, reflectData, reflectErrorLog) ) {
			setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to reflect tessellation shaders: %s", reflectErrorLog.c_str()));
			return;
		}
		// Unfortunately, we can't support line tessellation at this time.
		if (reflectData.patchKind == spv::ExecutionModeIsolines) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Metal does not support isoline tessellation."));
			return;
		}
	}

	// Tessellation - must ignore allowed bad pTessellationState pointer if not tess pipeline
	_outputControlPointCount = reflectData.numControlPoints;
	if (_isTessellationPipeline && pCreateInfo->pTessellationState)
		_staticStateData.patchControlPoints = pCreateInfo->pTessellationState->patchControlPoints;

	if (const VkPipelineRasterizationStateCreateInfo* rs = pCreateInfo->pRasterizationState) {
		_staticStateData.enable.set(MVKRenderStateEnableFlag::DepthClamp, rs->depthClampEnable);
		_staticStateData.enable.set(MVKRenderStateEnableFlag::DepthBias, rs->depthBiasEnable);
		_staticStateData.setCullMode(rs->cullMode);
		_staticStateData.setFrontFace(rs->frontFace);
		_staticStateData.setPolygonMode(rs->polygonMode);
		_staticStateData.depthBias.depthBiasClamp = rs->depthBiasClamp;
		_staticStateData.depthBias.depthBiasSlopeFactor = rs->depthBiasSlopeFactor;
		_staticStateData.depthBias.depthBiasConstantFactor = rs->depthBiasConstantFactor;
		_staticStateData.lineWidth = rs->lineWidth;
		if (const auto* line = mvkFindStructInChain<VkPipelineRasterizationLineStateCreateInfo>(rs, VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_LINE_STATE_CREATE_INFO)) {
			_staticStateData.setLineRasterizationMode(line->lineRasterizationMode);
		}
	}

	bool isRasterizingDepthStencil = _isRasterizing && (pRendInfo->depthAttachmentFormat || pRendInfo->stencilAttachmentFormat);
	if (const VkPipelineDepthStencilStateCreateInfo* ds = isRasterizingDepthStencil ? pCreateInfo->pDepthStencilState : nullptr) {
		_staticStateData.enable.set(MVKRenderStateEnableFlag::DepthTest, ds->depthTestEnable);
		_staticStateData.enable.set(MVKRenderStateEnableFlag::DepthBoundsTest, ds->depthBoundsTestEnable);
		_staticStateData.stencilReference.backFaceValue = ds->back.reference;
		_staticStateData.stencilReference.frontFaceValue = ds->front.reference;
		_staticStateData.depthBounds.minDepthBound = ds->minDepthBounds;
		_staticStateData.depthBounds.maxDepthBound = ds->maxDepthBounds;
		_staticStateData.depthStencil.stencilTestEnabled = ds->stencilTestEnable;
		_staticStateData.depthStencil.depthWriteEnabled = ds->depthWriteEnable;
		_staticStateData.depthStencil.depthCompareFunction = mvkMTLCompareFunctionFromVkCompareOp(ds->depthCompareOp);
		loadStencil(_staticStateData.depthStencil.frontFaceStencilData, ds->front);
		loadStencil(_staticStateData.depthStencil.backFaceStencilData, ds->back);
	}

	// Render pipeline state. Do this as early as possible, to fail fast if pipeline requires a fail on cache-miss.
	initMTLRenderPipelineState(pCreateInfo, reflectData, pPipelineFB, pVertexSS, pVertexFB, pTessCtlSS, pTessCtlFB, pTessEvalSS, pTessEvalFB, pFragmentSS, pFragmentFB);
	if ( !_hasValidMTLPipelineStates ) { return; }

	// Blending - must ignore allowed bad pColorBlendState pointer if rasterization disabled or no color attachments
	if (_isRasterizingColor && pCreateInfo->pColorBlendState) {
		mvkCopy(_staticStateData.blendConstants.float32, pCreateInfo->pColorBlendState->blendConstants, 4);
	}

	// Topology
	_vkPrimitiveTopology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
	bool primitiveRestart = true; // Always enabled in Metal
	if (pCreateInfo->pInputAssemblyState) {
		_vkPrimitiveTopology = pCreateInfo->pInputAssemblyState->topology;
		primitiveRestart = pCreateInfo->pInputAssemblyState->primitiveRestartEnable;
	}

	_staticStateData.primitiveType = mvkMTLPrimitiveTypeFromVkPrimitiveTopology(_vkPrimitiveTopology);
	_staticStateData.enable.set(MVKRenderStateEnableFlag::PrimitiveRestart, primitiveRestart);

	// In Metal, primitive restart cannot be disabled, so issue a warning if the app
	// has disabled it statically, or indicates that it might do so dynamically.
	// Just issue a warning here, as it is very likely the app is not actually
	// expecting to use primitive restart at all, and is disabling it "just-in-case".
	// As such, forcing an error here would be unexpected to the app (including CTS).
	// BTW, although Metal docs avoid mentioning it, testing shows that Metal does not support primitive
	// restart for list topologies, meaning VK_EXT_primitive_topology_list_restart cannot be supported.
	if (( !primitiveRestart || _dynamicStateFlags.has(MVKRenderStateFlag::PrimitiveRestartEnable)) &&
		 (_vkPrimitiveTopology == VK_PRIMITIVE_TOPOLOGY_LINE_STRIP ||
		  _vkPrimitiveTopology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP ||
		  _vkPrimitiveTopology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN ||
		  _dynamicStateFlags.has(MVKRenderStateFlag::PrimitiveTopology))) {
		reportWarning(VK_ERROR_FEATURE_NOT_PRESENT, "Metal does not support disabling primitive restart.");
	}

	// Must run after _isRasterizing and _dynamicState are populated
	initSampleLocations(pCreateInfo);

	// Viewports and scissors - must ignore allowed bad pViewportState pointer if rasterization is disabled
	if (auto pVPState = _isRasterizing ? pCreateInfo->pViewportState : nullptr) {
		// If viewports are dynamic, ignore them here.
		if (!_dynamicStateFlags.has(MVKRenderStateFlag::Viewports)) {
			uint32_t numViewports = std::min(pVPState->viewportCount, kMVKMaxViewportScissorCount);
			_staticStateData.numViewports = numViewports;
			mvkCopy(_viewports, pVPState->pViewports, numViewports);
		}

		// If scissors are dynamic, ignore them here.
		if (!_dynamicStateFlags.has(MVKRenderStateFlag::Scissors)) {
			uint32_t numScissors = std::min(pVPState->scissorCount, kMVKMaxViewportScissorCount);
			_staticStateData.numScissors = numScissors;
			mvkCopy(_scissors, pVPState->pScissors, numScissors);
		}
	}

	// Remove unneeded state
	MVKRenderStateFlags needed = MVKRenderStateFlags::all();
	if (!_dynamicStateFlags.has(MVKRenderStateFlag::StencilTestEnable) && !_staticStateData.depthStencil.stencilTestEnabled)
		needed.remove(MVKRenderStateFlag::StencilReference);
	if (!_isRasterizingColor || !usesConstantColor(_dynamicStateFlags, pCreateInfo->pColorBlendState))
		needed.remove(MVKRenderStateFlag::BlendConstants);
	if (_primitiveTopologyClass == MTLPrimitiveTopologyClassPoint || _primitiveTopologyClass == MTLPrimitiveTopologyClassLine)
		needed.removeAll({ MVKRenderStateFlag::CullMode, MVKRenderStateFlag::FrontFace });
	if (_primitiveTopologyClass == MTLPrimitiveTopologyClassPoint || _primitiveTopologyClass == MTLPrimitiveTopologyClassTriangle)
		needed.remove(MVKRenderStateFlag::LineWidth);
	if (!_isRasterizing) {
		needed &= {
			MVKRenderStateFlag::PatchControlPoints,
			MVKRenderStateFlag::PrimitiveRestartEnable,
			MVKRenderStateFlag::PrimitiveTopology,
			MVKRenderStateFlag::RasterizerDiscardEnable,
			MVKRenderStateFlag::VertexStride,
		};
	}
	_staticStateFlags = needed.removingAll(_dynamicStateFlags);
	_dynamicStateFlags &= needed;

	for (uint32_t stage = kMVKShaderStageVertex; stage < std::size(_stageResources); stage++) {
		_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::PushConstant] = _layout->getPushConstantResourceIndex(static_cast<MVKShaderStage>(stage));
	}
}

// This is executed first during pipeline creation. Do not depend on any internal state here.
void MVKGraphicsPipeline::initDynamicState(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	const auto* pDS = pCreateInfo->pDynamicState;
	if ( !pDS ) { return; }

	for (VkDynamicState s : MVKArrayRef(pDS->pDynamicStates, pDS->dynamicStateCount))
		_dynamicStateFlags |= getRenderStateFlags(s);

	// Some dynamic states have other restrictions
	if (_dynamicStateFlags.has(MVKRenderStateFlag::VertexStride)) {
		if ( !getMetalFeatures().dynamicVertexStride ) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "This device and platform does not support VK_DYNAMIC_STATE_VERTEX_INPUT_BINDING_STRIDE (macOS 14.0 or iOS/tvOS 17.0, plus either Apple4 or Mac2 GPU)."));
			_dynamicStateFlags.remove(MVKRenderStateFlag::VertexStride);
		}
	}
}

void MVKGraphicsPipeline::populateRenderingAttachmentInfo(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	const uint32_t* pColorAttLocs = nullptr;
	if (pCreateInfo->renderPass) {
		MVKRenderSubpass* subpass = ((MVKRenderPass*)pCreateInfo->renderPass)->getSubpass(pCreateInfo->subpass);
		_inputAttachmentIsDSAttachment = subpass->isInputAttachmentDepthStencilAttachment();
	} else {
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_LOCATION_INFO:
					pColorAttLocs = ((VkRenderingAttachmentLocationInfo*)next)->pColorAttachmentLocations;
					break;
				case VK_STRUCTURE_TYPE_RENDERING_INPUT_ATTACHMENT_INDEX_INFO: {
					const auto* pRendInpAttIdxInfo = (VkRenderingInputAttachmentIndexInfo*)next;
					_inputAttachmentIsDSAttachment = ((pRendInpAttIdxInfo->pDepthInputAttachmentIndex && *pRendInpAttIdxInfo->pDepthInputAttachmentIndex != VK_ATTACHMENT_UNUSED) ||
													  (pRendInpAttIdxInfo->pStencilInputAttachmentIndex && *pRendInpAttIdxInfo->pStencilInputAttachmentIndex != VK_ATTACHMENT_UNUSED));
					break;
				}
				default:
					break;
			}
		}
	}

	// Map the attachment locations from the collection defined by VkRenderingAttachmentLocationInfo.
	// If there is no VkRenderingAttachmentLocationInfo, this is just a basic copy to _colorAttachmentFormats.
	auto attCnt = getRenderingCreateInfo(pCreateInfo)->colorAttachmentCount;
	for (uint32_t attIdx = 0; attIdx < attCnt; attIdx++) {
		_colorAttachmentLocations.push_back(pColorAttLocs ? pColorAttLocs[attIdx] : attIdx);
	}
	_hasRemappedAttachmentLocations = (attCnt && pColorAttLocs);
}

// Either returns an existing pipeline state or compiles a new one.
id<MTLRenderPipelineState> MVKGraphicsPipeline::getOrCompilePipeline(MTLRenderPipelineDescriptor* plDesc,
																	 id<MTLRenderPipelineState>& plState) {
	if ( !plState ) {
		MVKRenderPipelineCompiler* plc = new MVKRenderPipelineCompiler(this);
		plState = plc->newMTLRenderPipelineState(plDesc);	// retained
		plc->destroy();
		if ( !plState ) { _hasValidMTLPipelineStates = false; }
	}
	return plState;
}

// Either returns an existing pipeline state or compiles a new one.
id<MTLComputePipelineState> MVKGraphicsPipeline::getOrCompilePipeline(MTLComputePipelineDescriptor* plDesc,
																	  id<MTLComputePipelineState>& plState,
																	  const char* compilerType) {
	if ( !plState ) {
		MVKComputePipelineCompiler* plc = new MVKComputePipelineCompiler(this, compilerType);
		plState = plc->newMTLComputePipelineState(plDesc);	// retained
		plc->destroy();
		if ( !plState ) { _hasValidMTLPipelineStates = false; }
	}
	return plState;
}

// Must run after _isRasterizing and _dynamicState are populated
void MVKGraphicsPipeline::initSampleLocations(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	// Must ignore allowed bad pMultisampleState pointer if rasterization disabled
	if ( !(_isRasterizing && pCreateInfo->pMultisampleState) ) { return; }

	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pMultisampleState->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_PIPELINE_SAMPLE_LOCATIONS_STATE_CREATE_INFO_EXT: {
				auto* pSampLocnsCreateInfo = (VkPipelineSampleLocationsStateCreateInfoEXT*)next;
				uint32_t numLocs = std::min(pSampLocnsCreateInfo->sampleLocationsInfo.sampleLocationsCount, kMVKMaxSampleCount);
				for (uint32_t slIdx = 0; slIdx < numLocs; slIdx++) {
					VkSampleLocationEXT sl = pSampLocnsCreateInfo->sampleLocationsInfo.pSampleLocations[slIdx];
					_sampleLocations[slIdx] = MTLSamplePositionMake(
						mvkClamp(sl.x, kMVKMinSampleLocationCoordinate, kMVKMaxSampleLocationCoordinate),
						mvkClamp(sl.y, kMVKMinSampleLocationCoordinate, kMVKMaxSampleLocationCoordinate));
				}
				_staticStateData.numSampleLocations = numLocs;
				_staticStateData.enable.set(MVKRenderStateEnableFlag::SampleLocations, pSampLocnsCreateInfo->sampleLocationsEnable);
				return;
			}
			default:
				break;
		}
	}
}

// Constructs the underlying Metal render pipeline.
void MVKGraphicsPipeline::initMTLRenderPipelineState(const VkGraphicsPipelineCreateInfo* pCreateInfo,
													 const SPIRVTessReflectionData& reflectData,
													 VkPipelineCreationFeedback* pPipelineFB,
													 const VkPipelineShaderStageCreateInfo* pVertexSS,
													 VkPipelineCreationFeedback* pVertexFB,
													 const VkPipelineShaderStageCreateInfo* pTessCtlSS,
													 VkPipelineCreationFeedback* pTessCtlFB,
													 const VkPipelineShaderStageCreateInfo* pTessEvalSS,
													 VkPipelineCreationFeedback* pTessEvalFB,
													 const VkPipelineShaderStageCreateInfo* pFragmentSS,
													 VkPipelineCreationFeedback* pFragmentFB) {
	_mtlTessVertexStageState = nil;
	_mtlTessVertexStageIndex16State = nil;
	_mtlTessVertexStageIndex32State = nil;
	_mtlTessControlStageState = nil;
	_mtlPipelineState = nil;

	uint64_t pipelineStart = 0;
	if (pPipelineFB) {
		pipelineStart = mvkGetTimestamp();
	}

	const char* dumpDir = getMVKConfig().shaderDumpDir;
	if (dumpDir && *dumpDir) {
		char filename[PATH_MAX];
		char text[1024];
		char* ptext = text;
		size_t full_hash = 0;
		const char* type = pTessCtlSS && pTessEvalSS ? "-tess" : "";
		auto addShader = [&](const char* type, MVKShaderModule* module) {
			if (!module) {
				return;
			}
			size_t hash = module->getKey().codeHash;
			full_hash = full_hash * 33 ^ hash;
			ptext = std::min(ptext + snprintf(ptext, std::end(text) - ptext, "%s: %016zx\n", type, hash), std::end(text) - 1);
		};
		addShader(" VS", _vertexModule);
		addShader("TCS", _tessCtlModule);
		addShader("TES", _tessEvalModule);
		addShader(" FS", _fragmentModule);
		mkdir(dumpDir, 0755);
		snprintf(filename, sizeof(filename), "%s/pipeline%s-%016zx.txt", dumpDir, type, full_hash);
		FILE* file = fopen(filename, "w");
		if (file) {
			fwrite(text, 1, ptext - text, file);
			fclose(file);
		}
	}

	if (!isTessellationPipeline()) {
		MTLRenderPipelineDescriptor* plDesc = newMTLRenderPipelineDescriptor(pCreateInfo, reflectData, pVertexSS, pVertexFB, pFragmentSS, pFragmentFB);	// temp retain
		if (plDesc) {
			auto viewMask = getRenderingCreateInfo(pCreateInfo)->viewMask;
			if (mvkIsMultiview(viewMask)) {
				// We need to adjust the step rate for per-instance attributes to account for the
				// extra instances needed to render all views. But, there's a problem: vertex input
				// descriptions are static pipeline state. If we need multiple passes, and some have
				// different numbers of views to render than others, then the step rate must be different
				// for these passes. We'll need to make a pipeline for every pass view count we can see
				// in the render pass. This really sucks.
				std::unordered_set<uint32_t> viewCounts;
				auto passCnt = getDevice()->getMultiviewMetalPassCount(viewMask);
				for (uint32_t passIdx = 0; passIdx < passCnt; ++passIdx) {
					viewCounts.insert(getDevice()->getViewCountInMetalPass(viewMask, passIdx));
				}
				auto count = viewCounts.cbegin();
				adjustVertexInputForMultiview(plDesc.vertexDescriptor, pCreateInfo->pVertexInputState, *count);
				getOrCompilePipeline(plDesc, _mtlPipelineState);
				if (viewCounts.size() > 1) {
					_multiviewMTLPipelineStates[*count] = _mtlPipelineState;
					uint32_t oldCount = *count++;
					for (auto last = viewCounts.cend(); count != last; ++count) {
						if (_multiviewMTLPipelineStates.count(*count)) { continue; }
						adjustVertexInputForMultiview(plDesc.vertexDescriptor, pCreateInfo->pVertexInputState, *count, oldCount);
						getOrCompilePipeline(plDesc, _multiviewMTLPipelineStates[*count]);
						oldCount = *count;
					}
				}
			} else {
				getOrCompilePipeline(plDesc, _mtlPipelineState);
			}
			[plDesc release];																				// temp release
		} else {
			_hasValidMTLPipelineStates = false;
		}
	} else {
		// In this case, we need to create three render pipelines. But, the way Metal handles
		// index buffers for compute stage-in means we have to create three pipelines for
		// stage 1 (five pipelines in total).
		SPIRVToMSLConversionConfiguration shaderConfig;
		initShaderConversionConfig(shaderConfig, pCreateInfo, reflectData);

		MVKMTLFunction vtxFunctions[3] = {};
		MTLComputePipelineDescriptor* vtxPLDesc = newMTLTessVertexStageDescriptor(pCreateInfo, reflectData, shaderConfig, pVertexSS, pVertexFB, pTessCtlSS, vtxFunctions);					// temp retained
		MTLComputePipelineDescriptor* tcPLDesc = newMTLTessControlStageDescriptor(pCreateInfo, reflectData, shaderConfig, pTessCtlSS, pTessCtlFB, pVertexSS, pTessEvalSS);					// temp retained
		MTLRenderPipelineDescriptor* rastPLDesc = newMTLTessRasterStageDescriptor(pCreateInfo, reflectData, shaderConfig, pTessEvalSS, pTessEvalFB, pFragmentSS, pFragmentFB, pTessCtlSS);	// temp retained
		if (vtxPLDesc && tcPLDesc && rastPLDesc) {
			if (compileTessVertexStageState(vtxPLDesc, vtxFunctions, pVertexFB)) {
				if (compileTessControlStageState(tcPLDesc, pTessCtlFB)) {
					getOrCompilePipeline(rastPLDesc, _mtlPipelineState);
				}
			}
		} else {
			_hasValidMTLPipelineStates = false;
		}
		[vtxPLDesc release];	// temp release
		[tcPLDesc release];		// temp release
		[rastPLDesc release];	// temp release
	}

	if (pPipelineFB) {
		if ( _hasValidMTLPipelineStates ) {
			mvkEnableFlags(pPipelineFB->flags, VK_PIPELINE_CREATION_FEEDBACK_VALID_BIT);
		}
		pPipelineFB->duration = mvkGetElapsedNanoseconds(pipelineStart);
	}
}

// Returns a retained MTLRenderPipelineDescriptor constructed from this instance, or nil if an error occurs.
// It is the responsibility of the caller to release the returned descriptor.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::newMTLRenderPipelineDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																				 const SPIRVTessReflectionData& reflectData,
																				 const VkPipelineShaderStageCreateInfo* pVertexSS,
																				 VkPipelineCreationFeedback* pVertexFB,
																				 const VkPipelineShaderStageCreateInfo* pFragmentSS,
																				 VkPipelineCreationFeedback* pFragmentFB) {
	SPIRVToMSLConversionConfiguration shaderConfig;
	initShaderConversionConfig(shaderConfig, pCreateInfo, reflectData);

	MTLRenderPipelineDescriptor* plDesc = [MTLRenderPipelineDescriptor new];	// retained

	SPIRVShaderOutputs vtxOutputs;
	std::string errorLog;
	if (!getShaderOutputs(_vertexModule->getSPIRV(), spv::ExecutionModelVertex, pVertexSS->pName, vtxOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get vertex outputs: %s", errorLog.c_str()));
		return nil;
	}

	// Add shader stages. Compile vertex shader before others just in case conversion changes anything...like rasterizaion disable.
	if (!addVertexShaderToPipeline(plDesc, pCreateInfo, shaderConfig, pVertexSS, pVertexFB, pFragmentSS)) { return nil; }

	// Vertex input
	// This needs to happen before compiling the fragment shader, or we'll lose information on vertex attributes.
	if (!addVertexInputToPipeline(plDesc.vertexDescriptor, pCreateInfo->pVertexInputState, shaderConfig)) { return nil; }

	// Fragment shader - only add if rasterization is enabled
	if (!addFragmentShaderToPipeline(plDesc, pCreateInfo, shaderConfig, vtxOutputs, pFragmentSS, pFragmentFB)) { return nil; }

	// Output
	addFragmentOutputToPipeline(plDesc, pCreateInfo);

	// Metal does not allow the name of the pipeline to be changed after it has been created,
	// and we need to create the Metal pipeline immediately to provide error feedback to app.
	// The best we can do at this point is set the pipeline name from the layout.
	setMetalObjectLabel(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

	return plDesc;
}

// Returns a retained MTLComputePipelineDescriptor for the vertex stage of a tessellated draw constructed from this instance, or nil if an error occurs.
// It is the responsibility of the caller to release the returned descriptor.
MTLComputePipelineDescriptor* MVKGraphicsPipeline::newMTLTessVertexStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																				   const SPIRVTessReflectionData& reflectData,
																				   SPIRVToMSLConversionConfiguration& shaderConfig,
																				   const VkPipelineShaderStageCreateInfo* pVertexSS,
																				   VkPipelineCreationFeedback* pVertexFB,
																				   const VkPipelineShaderStageCreateInfo* pTessCtlSS,
																				   MVKMTLFunction* pVtxFunctions) {
	MTLComputePipelineDescriptor* plDesc = [MTLComputePipelineDescriptor new];	// retained

	SPIRVShaderInputs tcInputs;
	std::string errorLog;
	if (!getShaderInputs(_tessCtlModule->getSPIRV(), spv::ExecutionModelTessellationControl, pTessCtlSS->pName, tcInputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get tessellation control inputs: %s", errorLog.c_str()));
		return nil;
	}

	// Filter out anything but builtins. We couldn't do this before because we needed to make sure
	// locations were assigned correctly.
	tcInputs.erase(std::remove_if(tcInputs.begin(), tcInputs.end(), [](const SPIRVShaderInterfaceVariable& var) {
		return var.builtin != spv::BuiltInPosition && var.builtin != spv::BuiltInPointSize && var.builtin != spv::BuiltInClipDistance && var.builtin != spv::BuiltInCullDistance;
	}), tcInputs.end());

	// Add shader stages.
	if (!addVertexShaderToPipeline(plDesc, pCreateInfo, shaderConfig, tcInputs, pVertexSS, pVertexFB, pVtxFunctions)) { return nil; }

	// Vertex input
	plDesc.stageInputDescriptor = [MTLStageInputOutputDescriptor stageInputOutputDescriptor];
	if (!addVertexInputToPipeline(plDesc.stageInputDescriptor, pCreateInfo->pVertexInputState, shaderConfig)) { return nil; }
	plDesc.stageInputDescriptor.indexBufferIndex = _stageResources[kMVKShaderStageVertex].implicitBuffers.ids[MVKImplicitBuffer::Index];

	plDesc.threadGroupSizeIsMultipleOfThreadExecutionWidth = YES;

	// Metal does not allow the name of the pipeline to be changed after it has been created,
	// and we need to create the Metal pipeline immediately to provide error feedback to app.
	// The best we can do at this point is set the pipeline name from the layout.
	setMetalObjectLabel(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

	return plDesc;
}

static VkFormat mvkFormatFromOutput(const SPIRVShaderOutput& output) {
	switch (output.baseType) {
		case SPIRType::SByte:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R8_SINT;
				case 2: return VK_FORMAT_R8G8_SINT;
				case 3: return VK_FORMAT_R8G8B8_SINT;
				case 4: return VK_FORMAT_R8G8B8A8_SINT;
			}
			break;
		case SPIRType::UByte:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R8_UINT;
				case 2: return VK_FORMAT_R8G8_UINT;
				case 3: return VK_FORMAT_R8G8B8_UINT;
				case 4: return VK_FORMAT_R8G8B8A8_UINT;
			}
			break;
		case SPIRType::Short:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R16_SINT;
				case 2: return VK_FORMAT_R16G16_SINT;
				case 3: return VK_FORMAT_R16G16B16_SINT;
				case 4: return VK_FORMAT_R16G16B16A16_SINT;
			}
			break;
		case SPIRType::UShort:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R16_UINT;
				case 2: return VK_FORMAT_R16G16_UINT;
				case 3: return VK_FORMAT_R16G16B16_UINT;
				case 4: return VK_FORMAT_R16G16B16A16_UINT;
			}
			break;
		case SPIRType::Half:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R16_SFLOAT;
				case 2: return VK_FORMAT_R16G16_SFLOAT;
				case 3: return VK_FORMAT_R16G16B16_SFLOAT;
				case 4: return VK_FORMAT_R16G16B16A16_SFLOAT;
			}
			break;
		case SPIRType::Int:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R32_SINT;
				case 2: return VK_FORMAT_R32G32_SINT;
				case 3: return VK_FORMAT_R32G32B32_SINT;
				case 4: return VK_FORMAT_R32G32B32A32_SINT;
			}
			break;
		case SPIRType::UInt:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R32_UINT;
				case 2: return VK_FORMAT_R32G32_UINT;
				case 3: return VK_FORMAT_R32G32B32_UINT;
				case 4: return VK_FORMAT_R32G32B32A32_UINT;
			}
			break;
		case SPIRType::Float:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R32_SFLOAT;
				case 2: return VK_FORMAT_R32G32_SFLOAT;
				case 3: return VK_FORMAT_R32G32B32_SFLOAT;
				case 4: return VK_FORMAT_R32G32B32A32_SFLOAT;
			}
			break;
		default:
			break;
	}
	return VK_FORMAT_UNDEFINED;
}

// Returns a format of the same base type with vector length adjusted to fit size.
static MTLVertexFormat mvkAdjustFormatVectorToSize(MTLVertexFormat format, uint32_t size) {
#define MVK_ADJUST_FORMAT_CASE(size_1, type, suffix) \
	case MTLVertexFormat##type##4##suffix: if (size >= 4 * (size_1)) { return MTLVertexFormat##type##4##suffix; } \
	case MTLVertexFormat##type##3##suffix: if (size >= 3 * (size_1)) { return MTLVertexFormat##type##3##suffix; } \
	case MTLVertexFormat##type##2##suffix: if (size >= 2 * (size_1)) { return MTLVertexFormat##type##2##suffix; } \
	case MTLVertexFormat##type##suffix:    if (size >= 1 * (size_1)) { return MTLVertexFormat##type##suffix; } \
	return MTLVertexFormatInvalid;

	switch (format) {
		MVK_ADJUST_FORMAT_CASE(1, UChar, )
		MVK_ADJUST_FORMAT_CASE(1, Char, )
		MVK_ADJUST_FORMAT_CASE(1, UChar, Normalized)
		MVK_ADJUST_FORMAT_CASE(1, Char, Normalized)
		MVK_ADJUST_FORMAT_CASE(2, UShort, )
		MVK_ADJUST_FORMAT_CASE(2, Short, )
		MVK_ADJUST_FORMAT_CASE(2, UShort, Normalized)
		MVK_ADJUST_FORMAT_CASE(2, Short, Normalized)
		MVK_ADJUST_FORMAT_CASE(2, Half, )
		MVK_ADJUST_FORMAT_CASE(4, Float, )
		MVK_ADJUST_FORMAT_CASE(4, UInt, )
		MVK_ADJUST_FORMAT_CASE(4, Int, )
		default: return format;
	}
#undef MVK_ADJUST_FORMAT_CASE
}

// Returns a retained MTLComputePipelineDescriptor for the tess. control stage of a tessellated draw constructed from this instance, or nil if an error occurs.
// It is the responsibility of the caller to release the returned descriptor.
MTLComputePipelineDescriptor* MVKGraphicsPipeline::newMTLTessControlStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																					const SPIRVTessReflectionData& reflectData,
																					SPIRVToMSLConversionConfiguration& shaderConfig,
																					const VkPipelineShaderStageCreateInfo* pTessCtlSS,
																					VkPipelineCreationFeedback* pTessCtlFB,
																					const VkPipelineShaderStageCreateInfo* pVertexSS,
																					const VkPipelineShaderStageCreateInfo* pTessEvalSS) {
	MTLComputePipelineDescriptor* plDesc = [MTLComputePipelineDescriptor new];		// retained

	SPIRVShaderOutputs vtxOutputs;
	SPIRVShaderInputs teInputs;
	std::string errorLog;
	if (!getShaderOutputs(_vertexModule->getSPIRV(), spv::ExecutionModelVertex, pVertexSS->pName, vtxOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get vertex outputs: %s", errorLog.c_str()));
		return nil;
	}
	if (!getShaderInputs(_tessEvalModule->getSPIRV(), spv::ExecutionModelTessellationEvaluation, pTessEvalSS->pName, teInputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get tessellation evaluation inputs: %s", errorLog.c_str()));
		return nil;
	}

	// Filter out anything but builtins. We couldn't do this before because we needed to make sure
	// locations were assigned correctly.
	teInputs.erase(std::remove_if(teInputs.begin(), teInputs.end(), [](const SPIRVShaderInterfaceVariable& var) {
		return var.builtin != spv::BuiltInPosition && var.builtin != spv::BuiltInPointSize && var.builtin != spv::BuiltInClipDistance && var.builtin != spv::BuiltInCullDistance;
	}), teInputs.end());

	// Add shader stages.
	if (!addTessCtlShaderToPipeline(plDesc, pCreateInfo, shaderConfig, vtxOutputs, teInputs, pTessCtlSS, pTessCtlFB)) {
		[plDesc release];
		return nil;
	}

	// Metal does not allow the name of the pipeline to be changed after it has been created,
	// and we need to create the Metal pipeline immediately to provide error feedback to app.
	// The best we can do at this point is set the pipeline name from the layout.
	setMetalObjectLabel(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

	return plDesc;
}

// Returns a retained MTLRenderPipelineDescriptor for the last stage of a tessellated draw constructed from this instance, or nil if an error occurs.
// It is the responsibility of the caller to release the returned descriptor.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::newMTLTessRasterStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																				  const SPIRVTessReflectionData& reflectData,
																				  SPIRVToMSLConversionConfiguration& shaderConfig,
																				  const VkPipelineShaderStageCreateInfo* pTessEvalSS,
																				  VkPipelineCreationFeedback* pTessEvalFB,
																				  const VkPipelineShaderStageCreateInfo* pFragmentSS,
																				  VkPipelineCreationFeedback* pFragmentFB,
																				  const VkPipelineShaderStageCreateInfo* pTessCtlSS) {
	MTLRenderPipelineDescriptor* plDesc = [MTLRenderPipelineDescriptor new];	// retained

	SPIRVShaderOutputs tcOutputs, teOutputs;
	SPIRVShaderInputs teInputs;
	std::string errorLog;
	if (!getShaderOutputs(_tessCtlModule->getSPIRV(), spv::ExecutionModelTessellationControl, pTessCtlSS->pName, tcOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get tessellation control outputs: %s", errorLog.c_str()));
		return nil;
	}
	if (!getShaderOutputs(_tessEvalModule->getSPIRV(), spv::ExecutionModelTessellationEvaluation, pTessEvalSS->pName, teOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get tessellation evaluation outputs: %s", errorLog.c_str()));
		return nil;
	}

	// Add shader stages. Compile tessellation evaluation shader before others just in case conversion changes anything...like rasterizaion disable.
	if (!addTessEvalShaderToPipeline(plDesc, pCreateInfo, shaderConfig, tcOutputs, pTessEvalSS, pTessEvalFB, pFragmentSS)) {
		[plDesc release];
		return nil;
	}

	// Fragment shader - only add if rasterization is enabled
	if (!addFragmentShaderToPipeline(plDesc, pCreateInfo, shaderConfig, teOutputs, pFragmentSS, pFragmentFB)) {
		[plDesc release];
		return nil;
	}

	// Tessellation state
	addTessellationToPipeline(plDesc, reflectData, pCreateInfo->pTessellationState);

	// Output
	addFragmentOutputToPipeline(plDesc, pCreateInfo);

	return plDesc;
}

static constexpr const char* getImplicitBufferName(MVKImplicitBuffer buffer) {
	switch (buffer) {
		case MVKImplicitBuffer::PushConstant:   return "push constant";
		case MVKImplicitBuffer::Swizzle:        return "swizzle";
		case MVKImplicitBuffer::BufferSize:     return "buffer size";
		case MVKImplicitBuffer::DynamicOffset:  return "dynamic offset";
		case MVKImplicitBuffer::ViewRange:      return "view range";
		case MVKImplicitBuffer::IndirectParams: return "indirect parameter";
		case MVKImplicitBuffer::Output:         return "per-vertex output";
		case MVKImplicitBuffer::PatchOutput:    return "per-patch output";
		case MVKImplicitBuffer::TessLevel:      return "tessellation level";
		case MVKImplicitBuffer::Index:          return "index";
		case MVKImplicitBuffer::DispatchBase:   return "dispatch base";
		case MVKImplicitBuffer::Count:          break;
	}
	assert(0);
	return "unknown";
}

static bool verifyImplicitBuffers(MVKImplicitBufferBindings& buffers, const char* stageName, uint32_t limit, MVKPipeline* pipeline) {
	static constexpr MVKImplicitBufferList ignored = MVKImplicitBuffer::PushConstant; // Push constants are in the main buffer area
	for (MVKImplicitBuffer needed : buffers.needed.removingAll(ignored)) {
		if (buffers.ids[needed] < limit) {
			pipeline->setConfigurationResult(pipeline->reportError(VK_ERROR_INITIALIZATION_FAILED, "%s shader requires %s buffer, but there is no free slot to pass it.", stageName, getImplicitBufferName(needed)));
			return false;
		}
	}
	return true;
}

static void addCommonImplicitBuffersToShaderConfig(SPIRVToMSLConversionConfiguration& dst, const MVKOnePerEnumEntry<uint8_t, MVKImplicitBuffer>& src) {
	dst.options.mslOptions.swizzle_buffer_index = src[MVKImplicitBuffer::Swizzle];
	dst.options.mslOptions.buffer_size_buffer_index = src[MVKImplicitBuffer::BufferSize];
	dst.options.mslOptions.dynamic_offsets_buffer_index = src[MVKImplicitBuffer::DynamicOffset];
}

bool MVKGraphicsPipeline::verifyImplicitBuffers(MVKShaderStage stage) {
	const char* stageNames[] = {
		"Vertex",
		"Tessellation control",
		"Tessellation evaluation",
		"Fragment"
	};

	return ::verifyImplicitBuffers(_stageResources[stage].implicitBuffers, stageNames[stage], _descriptorBufferCounts.stages[stage], this);
}

// Adds a vertex shader to the pipeline description.
bool MVKGraphicsPipeline::addVertexShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													const VkGraphicsPipelineCreateInfo* pCreateInfo,
													SPIRVToMSLConversionConfiguration& shaderConfig,
													const VkPipelineShaderStageCreateInfo* pVertexSS,
													VkPipelineCreationFeedback* pVertexFB,
													const VkPipelineShaderStageCreateInfo*& pFragmentSS) {
	const auto& implicit = _stageResources[kMVKShaderStageVertex].implicitBuffers.ids;
	shaderConfig.options.entryPointStage = spv::ExecutionModelVertex;
	shaderConfig.options.entryPointName = pVertexSS->pName;
	addCommonImplicitBuffersToShaderConfig(shaderConfig, implicit);
	shaderConfig.options.mslOptions.shader_output_buffer_index = implicit[MVKImplicitBuffer::Output];
	shaderConfig.options.mslOptions.view_mask_buffer_index = implicit[MVKImplicitBuffer::ViewRange];
	shaderConfig.options.mslOptions.capture_output_to_buffer = false;
	shaderConfig.options.mslOptions.disable_rasterization = !_isRasterizing;
    addVertexInputToShaderConversionConfig(shaderConfig, pCreateInfo);

	MVKMTLFunction func = getMTLFunction(shaderConfig, pVertexSS, pVertexFB, _vertexModule, "Vertex");
	id<MTLFunction> mtlFunc = func.getMTLFunction();
	plDesc.vertexFunction = mtlFunc;
	if ( !mtlFunc ) { return false; }

	auto& funcRslts = func.shaderConversionResults;
	plDesc.rasterizationEnabled = !funcRslts.isRasterizationDisabled;
	populateResourceUsage(_stageResources[kMVKShaderStageVertex], shaderConfig, funcRslts, spv::ExecutionModelVertex);
	_layout->populateBindOperations(_stageResources[kMVKShaderStageVertex].bindScript, shaderConfig, spv::ExecutionModelVertex);

	if (funcRslts.isRasterizationDisabled) {
		pFragmentSS = nullptr;
	}

	return verifyImplicitBuffers(kMVKShaderStageVertex);
}

// Adds a vertex shader compiled as a compute kernel to the pipeline description.
bool MVKGraphicsPipeline::addVertexShaderToPipeline(MTLComputePipelineDescriptor* plDesc,
													const VkGraphicsPipelineCreateInfo* pCreateInfo,
													SPIRVToMSLConversionConfiguration& shaderConfig,
													SPIRVShaderInputs& tcInputs,
													const VkPipelineShaderStageCreateInfo* pVertexSS,
													VkPipelineCreationFeedback* pVertexFB,
													MVKMTLFunction* pVtxFunctions) {
	const auto& implicit = _stageResources[kMVKShaderStageVertex].implicitBuffers.ids;
	shaderConfig.options.entryPointStage = spv::ExecutionModelVertex;
	shaderConfig.options.entryPointName = pVertexSS->pName;
	addCommonImplicitBuffersToShaderConfig(shaderConfig, implicit);
	shaderConfig.options.mslOptions.shader_index_buffer_index = implicit[MVKImplicitBuffer::Index];
	shaderConfig.options.mslOptions.shader_output_buffer_index = implicit[MVKImplicitBuffer::Output];
	shaderConfig.options.mslOptions.capture_output_to_buffer = true;
	shaderConfig.options.mslOptions.vertex_for_tessellation = true;
	shaderConfig.options.mslOptions.disable_rasterization = true;
    addVertexInputToShaderConversionConfig(shaderConfig, pCreateInfo);
	addNextStageInputToShaderConversionConfig(shaderConfig, tcInputs);

	// We need to compile this function three times, with no indexing, 16-bit indices, and 32-bit indices.
	static const CompilerMSL::Options::IndexType indexTypes[] = {
		CompilerMSL::Options::IndexType::None,
		CompilerMSL::Options::IndexType::UInt16,
		CompilerMSL::Options::IndexType::UInt32,
	};
	MVKMTLFunction func;
	for (uint32_t i = 0; i < sizeof(indexTypes)/sizeof(indexTypes[0]); i++) {
		shaderConfig.options.mslOptions.vertex_index_type = indexTypes[i];
		func = getMTLFunction(shaderConfig, pVertexSS, pVertexFB, _vertexModule, "Vertex");
		if ( !func.getMTLFunction() ) { return false; }

		pVtxFunctions[i] = func;

		auto& funcRslts = func.shaderConversionResults;
		populateResourceUsage(_stageResources[kMVKShaderStageVertex], shaderConfig, funcRslts, spv::ExecutionModelVertex);
	}

	_layout->populateBindOperations(_stageResources[kMVKShaderStageVertex].bindScript, shaderConfig, spv::ExecutionModelVertex);

	_stageResources[kMVKShaderStageVertex].implicitBuffers.needed.set(MVKImplicitBuffer::Index, !shaderConfig.shaderInputs.empty());
	return verifyImplicitBuffers(kMVKShaderStageVertex);
}

bool MVKGraphicsPipeline::addTessCtlShaderToPipeline(MTLComputePipelineDescriptor* plDesc,
													 const VkGraphicsPipelineCreateInfo* pCreateInfo,
													 SPIRVToMSLConversionConfiguration& shaderConfig,
													 SPIRVShaderOutputs& vtxOutputs,
													 SPIRVShaderInputs& teInputs,
													 const VkPipelineShaderStageCreateInfo* pTessCtlSS,
													 VkPipelineCreationFeedback* pTessCtlFB) {
	const auto& implicit = _stageResources[kMVKShaderStageTessCtl].implicitBuffers.ids;
	shaderConfig.options.entryPointStage = spv::ExecutionModelTessellationControl;
	shaderConfig.options.entryPointName = pTessCtlSS->pName;
	addCommonImplicitBuffersToShaderConfig(shaderConfig, implicit);
	shaderConfig.options.mslOptions.indirect_params_buffer_index = implicit[MVKImplicitBuffer::IndirectParams];
	shaderConfig.options.mslOptions.shader_input_buffer_index = getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding);
	shaderConfig.options.mslOptions.shader_output_buffer_index = implicit[MVKImplicitBuffer::Output];
	shaderConfig.options.mslOptions.shader_patch_output_buffer_index = implicit[MVKImplicitBuffer::PatchOutput];
	shaderConfig.options.mslOptions.shader_tess_factor_buffer_index = implicit[MVKImplicitBuffer::TessLevel];
	shaderConfig.options.mslOptions.capture_output_to_buffer = true;
	shaderConfig.options.mslOptions.multi_patch_workgroup = true;
	shaderConfig.options.mslOptions.fixed_subgroup_size = mvkIsAnyFlagEnabled(pTessCtlSS->flags, VK_PIPELINE_SHADER_STAGE_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT) ? 0 : getMetalFeatures().maxSubgroupSize;
	addPrevStageOutputToShaderConversionConfig(shaderConfig, vtxOutputs);
	addNextStageInputToShaderConversionConfig(shaderConfig, teInputs);

	MVKMTLFunction func = getMTLFunction(shaderConfig, pTessCtlSS, pTessCtlFB, _tessCtlModule, "Tessellation control");
	id<MTLFunction> mtlFunc = func.getMTLFunction();
	if ( !mtlFunc ) { return false; }
	plDesc.computeFunction = mtlFunc;

	auto& funcRslts = func.shaderConversionResults;
	_stageResources[kMVKShaderStageTessCtl].implicitBuffers.needed.addAll({ // Always needed
		MVKImplicitBuffer::IndirectParams,
		MVKImplicitBuffer::TessLevel,
	});
	populateResourceUsage(_stageResources[kMVKShaderStageTessCtl], shaderConfig, funcRslts, spv::ExecutionModelTessellationControl);
	_layout->populateBindOperations(_stageResources[kMVKShaderStageTessCtl].bindScript, shaderConfig, spv::ExecutionModelTessellationControl);

	return verifyImplicitBuffers(kMVKShaderStageTessCtl);
}

bool MVKGraphicsPipeline::addTessEvalShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													  const VkGraphicsPipelineCreateInfo* pCreateInfo,
													  SPIRVToMSLConversionConfiguration& shaderConfig,
													  SPIRVShaderOutputs& tcOutputs,
													  const VkPipelineShaderStageCreateInfo* pTessEvalSS,
													  VkPipelineCreationFeedback* pTessEvalFB,
													  const VkPipelineShaderStageCreateInfo*& pFragmentSS) {
	const auto& implicit = _stageResources[kMVKShaderStageTessEval].implicitBuffers.ids;
	shaderConfig.options.entryPointStage = spv::ExecutionModelTessellationEvaluation;
	shaderConfig.options.entryPointName = pTessEvalSS->pName;
	addCommonImplicitBuffersToShaderConfig(shaderConfig, implicit);
	shaderConfig.options.mslOptions.shader_input_buffer_index = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding);
	shaderConfig.options.mslOptions.shader_patch_input_buffer_index = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding);
	shaderConfig.options.mslOptions.shader_tess_factor_buffer_index = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding);
	shaderConfig.options.mslOptions.capture_output_to_buffer = false;
	shaderConfig.options.mslOptions.raw_buffer_tese_input = true;
	shaderConfig.options.mslOptions.disable_rasterization = !_isRasterizing;
	addPrevStageOutputToShaderConversionConfig(shaderConfig, tcOutputs);

	MVKMTLFunction func = getMTLFunction(shaderConfig, pTessEvalSS, pTessEvalFB, _tessEvalModule, "Tessellation evaluation");
	id<MTLFunction> mtlFunc = func.getMTLFunction();
	plDesc.vertexFunction = mtlFunc;	// Yeah, you read that right. Tess. eval functions are a kind of vertex function in Metal.
	if ( !mtlFunc ) { return false; }

	auto& funcRslts = func.shaderConversionResults;
	plDesc.rasterizationEnabled = !funcRslts.isRasterizationDisabled;
	populateResourceUsage(_stageResources[kMVKShaderStageTessEval], shaderConfig, funcRslts, spv::ExecutionModelTessellationEvaluation);
	_layout->populateBindOperations(_stageResources[kMVKShaderStageTessEval].bindScript, shaderConfig, spv::ExecutionModelTessellationEvaluation);

	if (funcRslts.isRasterizationDisabled) {
		pFragmentSS = nullptr;
	}

	return verifyImplicitBuffers(kMVKShaderStageTessEval);
}

bool MVKGraphicsPipeline::addFragmentShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													  const VkGraphicsPipelineCreateInfo* pCreateInfo,
													  SPIRVToMSLConversionConfiguration& shaderConfig,
													  SPIRVShaderOutputs& shaderOutputs,
													  const VkPipelineShaderStageCreateInfo* pFragmentSS,
													  VkPipelineCreationFeedback* pFragmentFB) {
	const auto& implicit = _stageResources[kMVKShaderStageFragment].implicitBuffers.ids;
	auto& mtlFeats = getMetalFeatures();
	if (pFragmentSS) {
		shaderConfig.options.entryPointStage = spv::ExecutionModelFragment;
		addCommonImplicitBuffersToShaderConfig(shaderConfig, implicit);
		shaderConfig.options.mslOptions.view_mask_buffer_index = implicit[MVKImplicitBuffer::ViewRange];
		shaderConfig.options.entryPointName = pFragmentSS->pName;
		shaderConfig.options.mslOptions.capture_output_to_buffer = false;
		shaderConfig.options.mslOptions.fixed_subgroup_size = mvkIsAnyFlagEnabled(pFragmentSS->flags, VK_PIPELINE_SHADER_STAGE_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT) ? 0 : mtlFeats.maxSubgroupSize;
		shaderConfig.options.mslOptions.check_discarded_frag_stores = true;
		/* Enabling makes dEQP-VK.fragment_shader_interlock.basic.discard.image.pixel_ordered.1xaa.no_sample_shading.1024x1024 and similar tests fail. Requires investigation */
		shaderConfig.options.mslOptions.force_fragment_with_side_effects_execution = false;
		shaderConfig.options.mslOptions.input_attachment_is_ds_attachment = _inputAttachmentIsDSAttachment;
		if (mtlFeats.needsSampleDrefLodArrayWorkaround) {
			shaderConfig.options.mslOptions.sample_dref_lod_array_as_grad = true;
		}
		if (_isRasterizing && pCreateInfo->pMultisampleState) {		// Must ignore allowed bad pMultisampleState pointer if rasterization disabled
#if MVK_USE_METAL_PRIVATE_API
			if (!getMVKConfig().useMetalPrivateAPI) {
#endif
				if (pCreateInfo->pMultisampleState->pSampleMask && pCreateInfo->pMultisampleState->pSampleMask[0] != 0xffffffff) {
					shaderConfig.options.mslOptions.additional_fixed_sample_mask = pCreateInfo->pMultisampleState->pSampleMask[0];
				}
#if MVK_USE_METAL_PRIVATE_API
			}
#endif
			shaderConfig.options.mslOptions.force_sample_rate_shading = pCreateInfo->pMultisampleState->sampleShadingEnable && pCreateInfo->pMultisampleState->minSampleShading != 0.0f;
		}
		if (std::any_of(shaderOutputs.begin(), shaderOutputs.end(), [](const SPIRVShaderOutput& output) { return output.builtin == spv::BuiltInLayer; })) {
			shaderConfig.options.mslOptions.arrayed_subpass_input = true;
		}
		addPrevStageOutputToShaderConversionConfig(shaderConfig, shaderOutputs);

		MVKMTLFunction func = getMTLFunction(shaderConfig, pFragmentSS, pFragmentFB, _fragmentModule, "Fragment");
		id<MTLFunction> mtlFunc = func.getMTLFunction();
		plDesc.fragmentFunction = mtlFunc;
		if ( !mtlFunc ) { return false; }

		auto& funcRslts = func.shaderConversionResults;
		populateResourceUsage(_stageResources[kMVKShaderStageFragment], shaderConfig, funcRslts, spv::ExecutionModelFragment);
		_layout->populateBindOperations(_stageResources[kMVKShaderStageFragment].bindScript, shaderConfig, spv::ExecutionModelFragment);
	}
	return verifyImplicitBuffers(kMVKShaderStageFragment);
}

#if !MVK_XCODE_15
static const NSUInteger MTLBufferLayoutStrideDynamic = NSUIntegerMax;
#endif

template<class T>
bool MVKGraphicsPipeline::addVertexInputToPipeline(T* inputDesc,
												   const VkPipelineVertexInputStateCreateInfo* pVI,
												   const SPIRVToMSLConversionConfiguration& shaderConfig) {
    // Collect extension structures
    VkPipelineVertexInputDivisorStateCreateInfo* pVertexInputDivisorState = nullptr;
	for (const auto* next = (VkBaseInStructure*)pVI->pNext; next; next = next->pNext) {
        switch (next->sType) {
        case VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_DIVISOR_STATE_CREATE_INFO:
            pVertexInputDivisorState = (VkPipelineVertexInputDivisorStateCreateInfo*)next;
            break;
        default:
            break;
        }
    }

    // Vertex buffer bindings
	bool isVtxStrideStatic = !_dynamicStateFlags.has(MVKRenderStateFlag::VertexStride);
	int32_t maxBinding = -1;
	uint32_t vbCnt = pVI->vertexBindingDescriptionCount;
    for (uint32_t i = 0; i < vbCnt; i++) {
        const VkVertexInputBindingDescription* pVKVB = &pVI->pVertexBindingDescriptions[i];
        if (shaderConfig.isVertexBufferUsed(pVKVB->binding)) {

			// Vulkan allows any stride, but Metal requires multiples of 4 on older GPUs.
            if (isVtxStrideStatic && (pVKVB->stride % getMetalFeatures().vertexStrideAlignment) != 0) {
				setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Under Metal, vertex attribute binding strides must be aligned to %llu bytes.", getMetalFeatures().vertexStrideAlignment));
                return false;
            }

			maxBinding = max<int32_t>(pVKVB->binding, maxBinding);
			uint32_t vbIdx = getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
			_mtlVertexBuffers.set(vbIdx);
			_vkVertexBuffers.set(pVKVB->binding);
			auto vbDesc = inputDesc.layouts[vbIdx];
			if (isVtxStrideStatic && pVKVB->stride == 0) {
				// Stride can't be 0, it will be set later to attributes' maximum offset + size
				// to prevent it from being larger than the underlying buffer permits.
				vbDesc.stride = 0;
				vbDesc.stepFunction = (decltype(vbDesc.stepFunction))MTLStepFunctionConstant;
				vbDesc.stepRate = 0;
			} else {
				vbDesc.stride = isVtxStrideStatic ? pVKVB->stride : MTLBufferLayoutStrideDynamic;
				vbDesc.stepFunction = (decltype(vbDesc.stepFunction))mvkMTLStepFunctionFromVkVertexInputRate(pVKVB->inputRate, isTessellationPipeline());
				vbDesc.stepRate = 1;
			}
        }
    }

    // Vertex buffer divisors (step rates)
    std::unordered_set<uint32_t> zeroDivisorBindings;
    if (pVertexInputDivisorState) {
        uint32_t vbdCnt = pVertexInputDivisorState->vertexBindingDivisorCount;
        for (uint32_t i = 0; i < vbdCnt; i++) {
            const VkVertexInputBindingDivisorDescription* pVKVB = &pVertexInputDivisorState->pVertexBindingDivisors[i];
            if (shaderConfig.isVertexBufferUsed(pVKVB->binding)) {
                uint32_t vbIdx = getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
                if ((NSUInteger)inputDesc.layouts[vbIdx].stepFunction == MTLStepFunctionPerInstance ||
					(NSUInteger)inputDesc.layouts[vbIdx].stepFunction == MTLStepFunctionThreadPositionInGridY) {
                    if (pVKVB->divisor == 0) {
                        inputDesc.layouts[vbIdx].stepFunction = (decltype(inputDesc.layouts[vbIdx].stepFunction))MTLStepFunctionConstant;
                        zeroDivisorBindings.insert(pVKVB->binding);
                    }
                    inputDesc.layouts[vbIdx].stepRate = pVKVB->divisor;
                }
            }
        }
    }

	// Vertex attributes
	uint32_t vaCnt = pVI->vertexAttributeDescriptionCount;
	for (uint32_t i = 0; i < vaCnt; i++) {
		const VkVertexInputAttributeDescription* pVKVA = &pVI->pVertexAttributeDescriptions[i];
		if (shaderConfig.isShaderInputLocationUsed(pVKVA->location)) {
			uint32_t vaBinding = pVKVA->binding;
			uint32_t vaOffset = pVKVA->offset;
			auto vaDesc = inputDesc.attributes[pVKVA->location];
			auto mtlFormat = (decltype(vaDesc.format))getPixelFormats()->getMTLVertexFormat(pVKVA->format);

			// Vulkan allows offsets to exceed the buffer stride, but Metal doesn't.
			// If this is the case, fetch a translated artificial buffer binding, using the same MTLBuffer,
			// but that is translated so that the reduced VA offset fits into the binding stride.
			if (isVtxStrideStatic) {
				const VkVertexInputBindingDescription* pVKVB = pVI->pVertexBindingDescriptions;
				uint32_t attrSize = 0;
				for (uint32_t j = 0; j < vbCnt; j++, pVKVB++) {
					if (pVKVB->binding == pVKVA->binding) {
						attrSize = getPixelFormats()->getBytesPerBlock(pVKVA->format);
						if (pVKVB->stride == 0) {
							// The step is set to constant, but we need to change stride to be non-zero for metal.
							// Look for the maximum offset + size to set as the stride.
							uint32_t vbIdx = getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
							auto vbDesc = inputDesc.layouts[vbIdx];
							uint32_t strideLowBound = vaOffset + attrSize;
							if (vbDesc.stride < strideLowBound) vbDesc.stride = strideLowBound;
						} else if (vaOffset && vaOffset + attrSize > pVKVB->stride) {
							// Move vertex attribute offset into the stride. This vertex attribute may be
							// combined with other vertex attributes into the same translated buffer binding.
							// But if the reduced offset combined with the vertex attribute size still won't
							// fit into the buffer binding stride, force the vertex attribute offset to zero,
							// effectively dedicating this vertex attribute to its own buffer binding.
							uint32_t origOffset = vaOffset;
							vaOffset %= pVKVB->stride;
							if (vaOffset + attrSize > pVKVB->stride) {
								vaOffset = 0;
							}
							vaBinding = getTranslatedVertexBinding(vaBinding, origOffset - vaOffset, maxBinding);
							if (zeroDivisorBindings.count(pVKVB->binding)) {
								zeroDivisorBindings.insert(vaBinding);
							}
						}
						break;
					}
				}
				if (pVKVB->stride && attrSize > pVKVB->stride) {
					/* Metal does not support overlapping loads. Truncate format vector length to prevent an assertion
					 * and hope it's not used by the shader. */
					MTLVertexFormat newFormat = mvkAdjustFormatVectorToSize((MTLVertexFormat)mtlFormat, pVKVB->stride);
					reportError(VK_SUCCESS, "Found attribute with size (%u) larger than it's binding's stride (%u). Changing descriptor format from %s to %s.",
								attrSize, pVKVB->stride, getPixelFormats()->getName((MTLVertexFormat)mtlFormat), getPixelFormats()->getName(newFormat));
					mtlFormat = (decltype(vaDesc.format))newFormat;
				}
			}

			vaDesc.format = mtlFormat;
			vaDesc.bufferIndex = (decltype(vaDesc.bufferIndex))getMetalBufferIndexForVertexAttributeBinding(vaBinding);
			vaDesc.offset = vaOffset;
		}
	}

	// Run through the vertex bindings. Add a new Metal vertex layout for each translated binding,
	// identical to the original layout. The translated binding will index into the same MTLBuffer,
	// but at an offset that is one or more strides away from the original.
	for (uint32_t i = 0; i < vbCnt; i++) {
		const VkVertexInputBindingDescription* pVKVB = &pVI->pVertexBindingDescriptions[i];
		uint32_t vbVACnt = shaderConfig.countShaderInputsAt(pVKVB->binding);
		if (vbVACnt > 0) {
			uint32_t vbIdx = getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
			auto vbDesc = inputDesc.layouts[vbIdx];

			uint32_t xldtVACnt = 0;
			for (auto& xltdBind : _translatedVertexBindings) {
				if (xltdBind.binding == pVKVB->binding) {
					uint32_t vbXltdIdx = getMetalBufferIndexForVertexAttributeBinding(xltdBind.translationBinding);
					auto vbXltdDesc = inputDesc.layouts[vbXltdIdx];
					vbXltdDesc.stride = vbDesc.stride;
					vbXltdDesc.stepFunction = vbDesc.stepFunction;
					vbXltdDesc.stepRate = vbDesc.stepRate;
					xldtVACnt += xltdBind.mappedAttributeCount;
					_mtlVertexBuffers.set(vbXltdIdx);
				}
			}

			// If all of the vertex attributes at this vertex buffer binding have been translated, remove it.
			if (xldtVACnt == vbVACnt) { vbDesc.stride = 0; }
		}
	}

    // Collect all bindings with zero divisors. We need to remember them so we can offset
    // the vertex buffers during a draw.
    for (uint32_t binding : zeroDivisorBindings) {
        uint32_t stride = (uint32_t)inputDesc.layouts[getMetalBufferIndexForVertexAttributeBinding(binding)].stride;
        _zeroDivisorVertexBindings.emplace_back(binding, stride);
    }

	return true;
}

// Adjusts step rates for per-instance vertex buffers based on the number of views to be drawn.
void MVKGraphicsPipeline::adjustVertexInputForMultiview(MTLVertexDescriptor* inputDesc, const VkPipelineVertexInputStateCreateInfo* pVI, uint32_t viewCount, uint32_t oldViewCount) {
	uint32_t vbCnt = pVI->vertexBindingDescriptionCount;
	const VkVertexInputBindingDescription* pVKVB = pVI->pVertexBindingDescriptions;
	for (uint32_t i = 0; i < vbCnt; ++i, ++pVKVB) {
		uint32_t vbIdx = getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
		if (inputDesc.layouts[vbIdx].stepFunction == MTLVertexStepFunctionPerInstance) {
			inputDesc.layouts[vbIdx].stepRate = inputDesc.layouts[vbIdx].stepRate / oldViewCount * viewCount;
			for (auto& xltdBind : _translatedVertexBindings) {
				if (xltdBind.binding == pVKVB->binding) {
					uint32_t vbXltdIdx = getMetalBufferIndexForVertexAttributeBinding(xltdBind.translationBinding);
					inputDesc.layouts[vbXltdIdx].stepRate = inputDesc.layouts[vbXltdIdx].stepRate / oldViewCount * viewCount;
				}
			}
		}
	}
}

// Returns a translated binding for the existing binding and translation offset, creating it if needed.
uint32_t MVKGraphicsPipeline::getTranslatedVertexBinding(uint32_t binding, uint32_t translationOffset, uint32_t maxBinding) {
	// See if a translated binding already exists (for example if more than one VA needs the same translation).
	for (auto& xltdBind : _translatedVertexBindings) {
		if (xltdBind.binding == binding && xltdBind.translationOffset == translationOffset) {
			xltdBind.mappedAttributeCount++;
			return xltdBind.translationBinding;
		}
	}

	// Get next available binding point and add a translation binding description for it
	uint16_t xltdBindPt = (uint16_t)(maxBinding + _translatedVertexBindings.size() + 1);
	_translatedVertexBindings.push_back( {.binding = (uint16_t)binding, .translationBinding = xltdBindPt, .translationOffset = translationOffset, .mappedAttributeCount = 1u} );

	return xltdBindPt;
}

void MVKGraphicsPipeline::addTessellationToPipeline(MTLRenderPipelineDescriptor* plDesc,
													const SPIRVTessReflectionData& reflectData,
													const VkPipelineTessellationStateCreateInfo* pTS) {

	VkPipelineTessellationDomainOriginStateCreateInfo* pTessDomainOriginState = nullptr;
	if (pTS && reflectData.patchKind == spv::ExecutionModeTriangles) {
		for (const auto* next = (VkBaseInStructure*)pTS->pNext; next; next = next->pNext) {
			switch (next->sType) {
			case VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_DOMAIN_ORIGIN_STATE_CREATE_INFO:
				pTessDomainOriginState = (VkPipelineTessellationDomainOriginStateCreateInfo*)next;
				break;
			default:
				break;
			}
		}
	}

	plDesc.maxTessellationFactor = getDeviceProperties().limits.maxTessellationGenerationLevel;
	plDesc.tessellationFactorFormat = MTLTessellationFactorFormatHalf;  // FIXME Use Float when it becomes available
	plDesc.tessellationFactorStepFunction = MTLTessellationFactorStepFunctionPerPatch;
	plDesc.tessellationOutputWindingOrder = mvkMTLWindingFromSpvExecutionMode(reflectData.windingOrder);
	if (pTessDomainOriginState && pTessDomainOriginState->domainOrigin == VK_TESSELLATION_DOMAIN_ORIGIN_LOWER_LEFT) {
		// Reverse the winding order for triangle patches with lower-left domains.
		if (plDesc.tessellationOutputWindingOrder == MTLWindingClockwise) {
			plDesc.tessellationOutputWindingOrder = MTLWindingCounterClockwise;
		} else {
			plDesc.tessellationOutputWindingOrder = MTLWindingClockwise;
		}
	}
	plDesc.tessellationPartitionMode = mvkMTLTessellationPartitionModeFromSpvExecutionMode(reflectData.partitionMode);
}

void MVKGraphicsPipeline::addFragmentOutputToPipeline(MTLRenderPipelineDescriptor* plDesc,
													  const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	// Topology
	if (pCreateInfo->pInputAssemblyState)
		plDesc.inputPrimitiveTopologyMVK = getPrimitiveTopologyClass();

	const VkPipelineRenderingCreateInfo* pRendInfo = getRenderingCreateInfo(pCreateInfo);

	// Color attachments - must ignore bad pColorBlendState pointer if rasterization is disabled or subpass has no color attachments
    uint32_t caCnt = 0;
    if (_isRasterizingColor && pCreateInfo->pColorBlendState) {
        for (uint32_t caIdx = 0; caIdx < pCreateInfo->pColorBlendState->attachmentCount; caIdx++) {
            const VkPipelineColorBlendAttachmentState* pCA = &pCreateInfo->pColorBlendState->pAttachments[caIdx];

			uint32_t caLoc = _colorAttachmentLocations[caIdx];
			if (caLoc == VK_ATTACHMENT_UNUSED) { continue; }

			MTLPixelFormat mtlPixFmt = getPixelFormats()->getMTLPixelFormat(pRendInfo->pColorAttachmentFormats[caIdx]);
			MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[caLoc];
            colorDesc.pixelFormat = mtlPixFmt;

			if (colorDesc.pixelFormat == MTLPixelFormatRGB9E5Float) {
                // Metal doesn't allow disabling individual channels for a RGB9E5 render target.
                // Either all must be disabled or none must be disabled.
                // TODO: Use framebuffer fetch to support this anyway. I don't understand why Apple doesn't
                // support it, given that the only GPUs that support this in Metal also support framebuffer fetch.
                colorDesc.writeMask = pCA->colorWriteMask ? MTLColorWriteMaskAll : MTLColorWriteMaskNone;
            } else {
                colorDesc.writeMask = mvkMTLColorWriteMaskFromVkChannelFlags(pCA->colorWriteMask);
            }
            // Don't set the blend state if we're not using this attachment.
            // The pixel format will be MTLPixelFormatInvalid in that case, and
            // Metal asserts if we turn on blending with that pixel format.
            if (mtlPixFmt) {
                caCnt++;
                colorDesc.blendingEnabled = pCA->blendEnable;
                colorDesc.rgbBlendOperation = mvkMTLBlendOperationFromVkBlendOp(pCA->colorBlendOp);
                colorDesc.sourceRGBBlendFactor = mvkMTLBlendFactorFromVkBlendFactor(pCA->srcColorBlendFactor);
                colorDesc.destinationRGBBlendFactor = mvkMTLBlendFactorFromVkBlendFactor(pCA->dstColorBlendFactor);
                colorDesc.alphaBlendOperation = mvkMTLBlendOperationFromVkBlendOp(pCA->alphaBlendOp);
                colorDesc.sourceAlphaBlendFactor = mvkMTLBlendFactorFromVkBlendFactor(pCA->srcAlphaBlendFactor);
                colorDesc.destinationAlphaBlendFactor = mvkMTLBlendFactorFromVkBlendFactor(pCA->dstAlphaBlendFactor);
#if MVK_USE_METAL_PRIVATE_API
				if (getMVKConfig().useMetalPrivateAPI) {
					plDesc.logicOperationEnabledMVK = pCreateInfo->pColorBlendState->logicOpEnable;
					plDesc.logicOperationMVK = mvkMTLLogicOperationFromVkLogicOp(pCreateInfo->pColorBlendState->logicOp);
				}
#endif
            }
        }
    }

    // Depth & stencil attachment formats
	MVKPixelFormats* pixFmts = getPixelFormats();
	MTLPixelFormat mtlDepthPixFmt = pixFmts->getMTLPixelFormat(pRendInfo->depthAttachmentFormat);
	MTLPixelFormat mtlStencilPixFmt = pixFmts->getMTLPixelFormat(pRendInfo->stencilAttachmentFormat);

	if (pixFmts->isDepthFormat(mtlDepthPixFmt)) {
		plDesc.depthAttachmentPixelFormat = mtlDepthPixFmt;
	} else if (pixFmts->isDepthFormat(mtlStencilPixFmt)) {
		plDesc.depthAttachmentPixelFormat = mtlStencilPixFmt;
	}

	if (pixFmts->isStencilFormat(mtlStencilPixFmt)) {
		plDesc.stencilAttachmentPixelFormat = mtlStencilPixFmt;
	} else if (pixFmts->isStencilFormat(mtlDepthPixFmt)) {
		plDesc.stencilAttachmentPixelFormat = mtlDepthPixFmt;
	}

	// In Vulkan, it's perfectly valid to render without any attachments. In Metal, if that
	// isn't supported, and we have no attachments, then we have to add a dummy attachment.
	if (!getMetalFeatures().renderWithoutAttachments &&
		!caCnt && !pRendInfo->depthAttachmentFormat && !pRendInfo->stencilAttachmentFormat) {

        MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[0];
        colorDesc.pixelFormat = MTLPixelFormatR8Unorm;
        colorDesc.writeMask = MTLColorWriteMaskNone;
    }

    // Multisampling - must ignore allowed bad pMultisampleState pointer if rasterization disabled
    if (_isRasterizing && pCreateInfo->pMultisampleState) {
        plDesc.rasterSampleCount = mvkSampleCountFromVkSampleCountFlagBits(pCreateInfo->pMultisampleState->rasterizationSamples);
#if MVK_USE_METAL_PRIVATE_API
        if (getMVKConfig().useMetalPrivateAPI && pCreateInfo->pMultisampleState->pSampleMask) {
            plDesc.sampleMaskMVK = pCreateInfo->pMultisampleState->pSampleMask[0];
        }
#endif
        plDesc.alphaToCoverageEnabled = pCreateInfo->pMultisampleState->alphaToCoverageEnable;
        plDesc.alphaToOneEnabled = pCreateInfo->pMultisampleState->alphaToOneEnable;

		// If the pipeline uses a specific render subpass, set its default sample count
		if (pCreateInfo->renderPass) {
			((MVKRenderPass*)pCreateInfo->renderPass)->getSubpass(pCreateInfo->subpass)->setDefaultSampleCount(pCreateInfo->pMultisampleState->rasterizationSamples);
		}
    }
}

// Initializes the shader conversion config used to prepare the MSL library used by this pipeline.
void MVKGraphicsPipeline::initShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig,
													 const VkGraphicsPipelineCreateInfo* pCreateInfo,
													 const SPIRVTessReflectionData& reflectData) {

	// Tessellation - must ignore allowed bad pTessellationState pointer if not tess pipeline
    VkPipelineTessellationDomainOriginStateCreateInfo* pTessDomainOriginState = nullptr;
    if (isTessellationPipeline() && pCreateInfo->pTessellationState) {
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pTessellationState->pNext; next; next = next->pNext) {
            switch (next->sType) {
            case VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_DOMAIN_ORIGIN_STATE_CREATE_INFO:
                pTessDomainOriginState = (VkPipelineTessellationDomainOriginStateCreateInfo*)next;
                break;
            default:
                break;
            }
        }
    }

	auto& mtlFeats = getMetalFeatures();
	auto& mvkCfg = getMVKConfig();
    shaderConfig.options.mslOptions.msl_version = mtlFeats.mslVersion;
    shaderConfig.options.mslOptions.texel_buffer_texture_width = mtlFeats.maxTextureDimension;
    shaderConfig.options.mslOptions.r32ui_linear_texture_alignment = (uint32_t)_device->getVkFormatTexelBufferAlignment(VK_FORMAT_R32_UINT, this);
	shaderConfig.options.mslOptions.texture_buffer_native = mtlFeats.textureBuffers;

	bool useMetalArgBuff = isUsingMetalArgumentBuffers();
	shaderConfig.options.mslOptions.argument_buffers = useMetalArgBuff;
	shaderConfig.options.mslOptions.force_active_argument_buffer_resources = false;
	shaderConfig.options.mslOptions.pad_argument_buffer_resources = useMetalArgBuff;
	shaderConfig.options.mslOptions.argument_buffers_tier = (SPIRV_CROSS_NAMESPACE::CompilerMSL::Options::ArgumentBuffersTier)getMetalFeatures().argumentBuffersTier;
	shaderConfig.options.mslOptions.agx_manual_cube_grad_fixup = mtlFeats.needsCubeGradWorkaround;

	MVKPipelineLayout* layout = (MVKPipelineLayout*)pCreateInfo->layout;
	layout->populateShaderConversionConfig(shaderConfig);

	// Set implicit buffer indices
	// FIXME: Many of these are optional. We shouldn't set the ones that aren't
	// present--or at least, we should move the ones that are down to avoid running over
	// the limit of available buffers. But we can't know that until we compile the shaders.
	initReservedVertexAttributeBufferCount(pCreateInfo);
	for (uint32_t i = 0; i < std::size(_stageResources); i++) {
		MVKShaderStage stage = (MVKShaderStage)i;
		_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::DynamicOffset]  = getImplicitBufferIndex(stage, 0);
		_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::BufferSize]     = getImplicitBufferIndex(stage, 1);
		_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::Swizzle]        = getImplicitBufferIndex(stage, 2);
		_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::Output]         = getImplicitBufferIndex(stage, 4);
		uint32_t extra = getImplicitBufferIndex(stage, 3);
		switch (stage) {
			case kMVKShaderStageVertex:
				// Since we currently can't use multiview with tessellation or geometry shaders,
				// to conserve the number of buffer bindings, use the same bindings for the
				// view range buffer as for the tessellation index buffer.
				_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::ViewRange] = extra;
				_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::Index]     = extra;
				break;
			case kMVKShaderStageFragment:
				_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::ViewRange] = extra;
				break;
			case kMVKShaderStageTessCtl:
				_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::PatchOutput]    = getImplicitBufferIndex(stage, 5);
				_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::TessLevel]      = getImplicitBufferIndex(stage, 6);
				_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::IndirectParams] = extra;
				break;
			case kMVKShaderStageTessEval:
				_stageResources[stage].implicitBuffers.ids[MVKImplicitBuffer::IndirectParams] = extra;
				break;
			default:
				break;
		}
	}

	const VkPipelineRenderingCreateInfo* pRendInfo = getRenderingCreateInfo(pCreateInfo);
	MVKPixelFormats* pixFmts = getPixelFormats();

	// Disable any unused color attachments, because Metal validation can complain if the
	// fragment shader outputs a color value without a corresponding color attachment.
	// However, if alpha-to-coverage is enabled, we must enable the fragment shader first color output,
	// even without a color attachment present or in use, so that coverage can be calculated.
	// Must ignore allowed bad pMultisampleState pointer if rasterization disabled
	bool hasA2C = _isRasterizing && pCreateInfo->pMultisampleState && pCreateInfo->pMultisampleState->alphaToCoverageEnable;
	shaderConfig.options.mslOptions.enable_frag_output_mask = hasA2C ? 1 : 0;
	if (_isRasterizingColor && pCreateInfo->pColorBlendState) {
		for (uint32_t caIdx = 0; caIdx < pCreateInfo->pColorBlendState->attachmentCount; caIdx++) {
			if (mvkIsColorAttachmentUsed(pRendInfo, caIdx)) {
				mvkEnableFlags(shaderConfig.options.mslOptions.enable_frag_output_mask, 1 << caIdx);
			}
		}
	}

	shaderConfig.options.mslOptions.ios_support_base_vertex_instance = mtlFeats.baseVertexInstanceDrawing;
	shaderConfig.options.mslOptions.texture_1D_as_2D = mvkCfg.texture1DAs2D;
	shaderConfig.options.mslOptions.enable_point_size_builtin = isRenderingPoints() || reflectData.pointMode;
	shaderConfig.options.mslOptions.enable_point_size_default = shaderConfig.options.mslOptions.enable_point_size_builtin;
	shaderConfig.options.mslOptions.default_point_size = 1.0f; // See VK_KHR_maintenance5
	shaderConfig.options.mslOptions.enable_frag_depth_builtin = pixFmts->isDepthFormat(pixFmts->getMTLPixelFormat(pRendInfo->depthAttachmentFormat));
	shaderConfig.options.mslOptions.enable_frag_stencil_ref_builtin = pixFmts->isStencilFormat(pixFmts->getMTLPixelFormat(pRendInfo->stencilAttachmentFormat));
    shaderConfig.options.shouldFlipVertexY = mvkCfg.shaderConversionFlipVertexY;
    shaderConfig.options.shouldFixupClipSpace = isDepthClipNegativeOneToOne(pCreateInfo);
    shaderConfig.options.mslOptions.swizzle_texture_samples = _fullImageViewSwizzle && !mtlFeats.nativeTextureSwizzle;
    shaderConfig.options.mslOptions.tess_domain_origin_lower_left = pTessDomainOriginState && pTessDomainOriginState->domainOrigin == VK_TESSELLATION_DOMAIN_ORIGIN_LOWER_LEFT;
    shaderConfig.options.mslOptions.multiview = mvkIsMultiview(pRendInfo->viewMask);
    shaderConfig.options.mslOptions.multiview_layered_rendering = getPhysicalDevice()->canUseInstancingForMultiview();
    shaderConfig.options.mslOptions.view_index_from_device_index = mvkAreAllFlagsEnabled(_flags, VK_PIPELINE_CREATE_2_VIEW_INDEX_FROM_DEVICE_INDEX_BIT);
	shaderConfig.options.mslOptions.replace_recursive_inputs = mvkOSVersionIsAtLeast(14.0, 17.0, 1.0);
#if MVK_MACOS
    shaderConfig.options.mslOptions.emulate_subgroups = !mtlFeats.simdPermute;
#endif
#if MVK_IOS_OR_TVOS
    shaderConfig.options.mslOptions.emulate_subgroups = !mtlFeats.quadPermute;
    shaderConfig.options.mslOptions.ios_use_simdgroup_functions = !!mtlFeats.simdPermute;
#endif

    shaderConfig.options.tessPatchKind = reflectData.patchKind;
    shaderConfig.options.numTessControlPoints = reflectData.numControlPoints;
}

uint32_t MVKGraphicsPipeline::getImplicitBufferIndex(MVKShaderStage stage, uint32_t bufferIndexOffset) {
	return getMetalBufferIndexForVertexAttributeBinding(_reservedVertexAttributeBufferCount.stages[stage] + bufferIndexOffset);
}

// Set the number of vertex attribute buffers consumed by this pipeline at each stage.
// Any implicit buffers needed by this pipeline will be assigned indexes below the range
// defined by this count below the max number of Metal buffer bindings per stage.
// Must be called before any calls to getImplicitBufferIndex().
void MVKGraphicsPipeline::initReservedVertexAttributeBufferCount(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	int32_t maxBinding = -1;
	uint32_t xltdBuffCnt = 0;

	const VkPipelineVertexInputStateCreateInfo* pVI = pCreateInfo->pVertexInputState;
	uint32_t vaCnt = pVI->vertexAttributeDescriptionCount;
	uint32_t vbCnt = pVI->vertexBindingDescriptionCount;

	// Determine the highest binding number used by the vertex buffers
	for (uint32_t vbIdx = 0; vbIdx < vbCnt; vbIdx++) {
		const VkVertexInputBindingDescription* pVKVB = &pVI->pVertexBindingDescriptions[vbIdx];
		maxBinding = max<int32_t>(pVKVB->binding, maxBinding);

		// Iterate through the vertex attributes and determine if any need a synthetic binding buffer to
		// accommodate offsets that are outside the stride, which Vulkan supports, but Metal does not.
		// This value will be worst case, as some synthetic buffers may end up being shared.
		for (uint32_t vaIdx = 0; vaIdx < vaCnt; vaIdx++) {
			const VkVertexInputAttributeDescription* pVKVA = &pVI->pVertexAttributeDescriptions[vaIdx];

			if (pVKVA->binding == pVKVB->binding) {
				uint32_t attrSize = getPixelFormats()->getBytesPerBlock(pVKVA->format);
				uint32_t vaOffset = pVKVA->offset;
				if (vaOffset && vaOffset + attrSize > pVKVB->stride) {
					xltdBuffCnt++;
				}
			}
		}
	}

	// The number of reserved bindings we need for the vertex stage is determined from the largest vertex
	// attribute binding number, plus any synthetic buffer bindings created to support translated offsets.
	mvkClear<uint32_t>(_reservedVertexAttributeBufferCount.stages, kMVKShaderStageCount);
	_reservedVertexAttributeBufferCount.stages[kMVKShaderStageVertex] = (maxBinding + 1) + xltdBuffCnt;
	_reservedVertexAttributeBufferCount.stages[kMVKShaderStageTessCtl] = kMVKTessCtlNumReservedBuffers;
	_reservedVertexAttributeBufferCount.stages[kMVKShaderStageTessEval] = kMVKTessEvalNumReservedBuffers;
}

// Initializes the vertex attributes in a shader conversion configuration.
void MVKGraphicsPipeline::addVertexInputToShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig,
                                                                 const VkGraphicsPipelineCreateInfo* pCreateInfo) {
    // Set the shader conversion config vertex attribute information
    shaderConfig.shaderInputs.clear();
    uint32_t vaCnt = pCreateInfo->pVertexInputState->vertexAttributeDescriptionCount;
    for (uint32_t vaIdx = 0; vaIdx < vaCnt; vaIdx++) {
        const VkVertexInputAttributeDescription* pVKVA = &pCreateInfo->pVertexInputState->pVertexAttributeDescriptions[vaIdx];

        // Set binding and offset from Vulkan vertex attribute
        mvk::MSLShaderInput si;
        si.shaderVar.location = pVKVA->location;
        si.binding = pVKVA->binding;

        // Metal can't do signedness conversions on vertex buffers (rdar://45922847). If the shader
        // and the vertex attribute have mismatched signedness, we have to fix the shader
        // to match the vertex attribute. So tell SPIRV-Cross if we're expecting an unsigned format.
        // Only do this if the attribute could be reasonably expected to fit in the shader's
        // declared type. Programs that try to invoke undefined behavior are on their own.
        switch (getPixelFormats()->getFormatType(pVKVA->format) ) {
        case kMVKFormatColorUInt8:
            si.shaderVar.format = MSL_SHADER_VARIABLE_FORMAT_UINT8;
            break;

        case kMVKFormatColorUInt16:
            si.shaderVar.format = MSL_SHADER_VARIABLE_FORMAT_UINT16;
            break;

        case kMVKFormatDepthStencil:
            // Only some depth/stencil formats have unsigned components.
            switch (pVKVA->format) {
            case VK_FORMAT_S8_UINT:
            case VK_FORMAT_D16_UNORM_S8_UINT:
            case VK_FORMAT_D24_UNORM_S8_UINT:
            case VK_FORMAT_D32_SFLOAT_S8_UINT:
                si.shaderVar.format = MSL_SHADER_VARIABLE_FORMAT_UINT8;
                break;

            default:
                break;
            }
            break;

        default:
            break;

        }

        shaderConfig.shaderInputs.push_back(si);
    }
}

// Initializes the shader outputs in a shader conversion config from the next stage input.
void MVKGraphicsPipeline::addNextStageInputToShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig,
                                                                    SPIRVShaderInputs& shaderInputs) {
    shaderConfig.shaderOutputs.clear();

	mvk::MSLShaderInterfaceVariable so;
	auto& sosv = so.shaderVar;
	for (auto& si : shaderInputs) {
		if ( !si.isUsed ) { continue; }

        sosv.location = si.location;
		sosv.component = si.component;
        sosv.builtin = si.builtin;
        sosv.vecsize = si.vecWidth;
		sosv.rate = si.perPatch ? MSL_SHADER_VARIABLE_RATE_PER_PATCH : MSL_SHADER_VARIABLE_RATE_PER_VERTEX;

        switch (getPixelFormats()->getFormatType(mvkFormatFromOutput(si) ) ) {
            case kMVKFormatColorUInt8:
                sosv.format = MSL_SHADER_VARIABLE_FORMAT_UINT8;
                break;

            case kMVKFormatColorUInt16:
                sosv.format = MSL_SHADER_VARIABLE_FORMAT_UINT16;
                break;

			case kMVKFormatColorHalf:
			case kMVKFormatColorInt16:
				sosv.format = MSL_SHADER_VARIABLE_FORMAT_ANY16;
				break;

			case kMVKFormatColorFloat:
			case kMVKFormatColorInt32:
			case kMVKFormatColorUInt32:
				sosv.format = MSL_SHADER_VARIABLE_FORMAT_ANY32;
				break;

            default:
				sosv.format = MSL_SHADER_VARIABLE_FORMAT_OTHER;
                break;
        }

        shaderConfig.shaderOutputs.push_back(so);
    }
}

// Initializes the shader inputs in a shader conversion config from the previous stage output.
void MVKGraphicsPipeline::addPrevStageOutputToShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig,
                                                                     SPIRVShaderOutputs& shaderOutputs) {
    shaderConfig.shaderInputs.clear();

	mvk::MSLShaderInput si;
	auto& sisv = si.shaderVar;
	for (auto& so : shaderOutputs) {
		if ( !so.isUsed ) { continue; }

        sisv.location = so.location;
		sisv.component = so.component;
        sisv.builtin = so.builtin;
        sisv.vecsize = so.vecWidth;
		sisv.rate = so.perPatch ? MSL_SHADER_VARIABLE_RATE_PER_PATCH : MSL_SHADER_VARIABLE_RATE_PER_VERTEX;

        switch (getPixelFormats()->getFormatType(mvkFormatFromOutput(so) ) ) {
            case kMVKFormatColorUInt8:
                sisv.format = MSL_SHADER_VARIABLE_FORMAT_UINT8;
                break;

            case kMVKFormatColorUInt16:
                sisv.format = MSL_SHADER_VARIABLE_FORMAT_UINT16;
                break;

			case kMVKFormatColorHalf:
			case kMVKFormatColorInt16:
				sisv.format = MSL_SHADER_VARIABLE_FORMAT_ANY16;
				break;

			case kMVKFormatColorFloat:
			case kMVKFormatColorInt32:
			case kMVKFormatColorUInt32:
				sisv.format = MSL_SHADER_VARIABLE_FORMAT_ANY32;
				break;

            default:
				sisv.format = MSL_SHADER_VARIABLE_FORMAT_OTHER;
                break;
        }

        shaderConfig.shaderInputs.push_back(si);
    }
}

// We render points if either the static topology or static polygon-mode dictate it.
// The topology class must be the same between static and dynamic, so point topology
// in static also implies point topology in dynamic.
// Metal does not support VK_POLYGON_MODE_POINT, but it can be emulated if the polygon mode
// is static, which allows both the topology and the pipeline topology-class to be set to points.
// This cannot be accomplished if the dynamic polygon mode has been changed to points when the
// pipeline is expecting triangles or lines, because the pipeline topology class will be incorrect.
bool MVKGraphicsPipeline::isRenderingPoints() {
	return getPrimitiveTopologyClass() == MTLPrimitiveTopologyClassPoint || getPrimitiveTopologyClass() == MTLPrimitiveTopologyClassUnspecified;
}

// We disable rasterization if either static rasterizerDiscard is enabled or the static cull mode dictates it.
bool MVKGraphicsPipeline::isRasterizationDisabled(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	if (!_dynamicStateFlags.has(MVKRenderStateFlag::RasterizerDiscardEnable) && pCreateInfo->pRasterizationState->rasterizerDiscardEnable)
		return true;
	if (!_dynamicStateFlags.has(MVKRenderStateFlag::CullMode) && pCreateInfo->pRasterizationState->cullMode == VK_CULL_MODE_FRONT_AND_BACK)
		return pCreateInfo->pInputAssemblyState && mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology) == MTLPrimitiveTopologyClassTriangle;
	return false;
}

// We ask SPIRV-Cross to fix up the clip space from [-w, w] to [0, w] if a
// VkPipelineViewportDepthClipControlCreateInfoEXT is provided with negativeOneToOne enabled.
// Must ignore allowed bad pViewportState pointer if rasterization is disabled.
bool MVKGraphicsPipeline::isDepthClipNegativeOneToOne(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	if (_isRasterizing && pCreateInfo->pViewportState ) {
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pViewportState->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_DEPTH_CLIP_CONTROL_CREATE_INFO_EXT: return ((VkPipelineViewportDepthClipControlCreateInfoEXT*)next)->negativeOneToOne;
				default: break;
			}
		}
	}
	return false;
}

MVKMTLFunction MVKGraphicsPipeline::getMTLFunction(SPIRVToMSLConversionConfiguration& shaderConfig,
												   const VkPipelineShaderStageCreateInfo* pShaderStage,
												   VkPipelineCreationFeedback* pStageFB,
												   MVKShaderModule* pShaderModule,
												   const char* pStageName) {
	MVKMTLFunction func = pShaderModule->getMTLFunction(&shaderConfig,
													    pShaderStage->pSpecializationInfo,
													    this,
													    pStageFB);
	if ( !func.getMTLFunction() ) {
		if (shouldFailOnPipelineCompileRequired()) {
			setConfigurationResult(VK_PIPELINE_COMPILE_REQUIRED);
		} else {
			setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "%s shader function could not be compiled into pipeline. See previous logged error.", pStageName));
		}
	}
	return func;
}

MVKGraphicsPipeline::~MVKGraphicsPipeline() {
	@synchronized (getMTLDevice()) {
		[_mtlTessVertexStageState release];
		[_mtlTessVertexStageIndex16State release];
		[_mtlTessVertexStageIndex32State release];
		[_mtlTessControlStageState release];
		[_mtlPipelineState release];
		if (_ownsVertexModule) delete _vertexModule;
		if (_ownsTessCtlModule) delete _tessCtlModule;
		if (_ownsTessEvalModule) delete _tessEvalModule;
		if (_ownsFragmentModule) delete _fragmentModule;
	}
}


#pragma mark -
#pragma mark MVKComputePipeline

MVKComputePipeline::MVKComputePipeline(MVKDevice* device,
									   MVKPipelineCache* pipelineCache,
									   MVKPipeline* parent,
									   const VkComputePipelineCreateInfo* pCreateInfo) :
	MVKPipeline(device, pipelineCache, (MVKPipelineLayout*)pCreateInfo->layout, getPipelineCreateFlags(pCreateInfo), parent) {

	_allowsDispatchBase = mvkAreAllFlagsEnabled(_flags, VK_PIPELINE_CREATE_2_DISPATCH_BASE_BIT);

	const VkPipelineCreationFeedbackCreateInfo* pFeedbackInfo = nullptr;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_PIPELINE_CREATION_FEEDBACK_CREATE_INFO:
				pFeedbackInfo = (VkPipelineCreationFeedbackCreateInfo*)next;
				break;
			default:
				break;
		}
	}

	warnIfBufferRobustnessEnabled(this, pCreateInfo);

	// Initialize feedback. The VALID bit must be initialized, either set or cleared.
	// We'll set the VALID bit on the stage feedback when we compile it.
	VkPipelineCreationFeedback* pPipelineFB = nullptr;
	VkPipelineCreationFeedback* pStageFB = nullptr;
	uint64_t pipelineStart = 0;
	if (pFeedbackInfo) {
		pPipelineFB = pFeedbackInfo->pPipelineCreationFeedback;
		// n.b. Do *NOT* use mvkClear().
		pPipelineFB->flags = 0;
		pPipelineFB->duration = 0;
		for (uint32_t i = 0; i < pFeedbackInfo->pipelineStageCreationFeedbackCount; ++i) {
			pFeedbackInfo->pPipelineStageCreationFeedbacks[i].flags = 0;
			pFeedbackInfo->pPipelineStageCreationFeedbacks[i].duration = 0;
		}
		pStageFB = &pFeedbackInfo->pPipelineStageCreationFeedbacks[0];
		pipelineStart = mvkGetTimestamp();
	}

	MVKMTLFunction func = getMTLFunction(pCreateInfo, pStageFB);
	_mtlThreadgroupSize = func.threadGroupSize;
	_mtlPipelineState = nil;

	id<MTLFunction> mtlFunc = func.getMTLFunction();
	if (mtlFunc) {
		MTLComputePipelineDescriptor* plDesc = [MTLComputePipelineDescriptor new];	// temp retain
		plDesc.computeFunction = mtlFunc;
		// Only available macOS 10.14+
		if ([plDesc respondsToSelector:@selector(setMaxTotalThreadsPerThreadgroup:)]) {
			plDesc.maxTotalThreadsPerThreadgroup = _mtlThreadgroupSize.width * _mtlThreadgroupSize.height * _mtlThreadgroupSize.depth;
		}
		plDesc.threadGroupSizeIsMultipleOfThreadExecutionWidth = mvkIsAnyFlagEnabled(pCreateInfo->stage.flags, VK_PIPELINE_SHADER_STAGE_CREATE_REQUIRE_FULL_SUBGROUPS_BIT);

		// Metal does not allow the name of the pipeline to be changed after it has been created,
		// and we need to create the Metal pipeline immediately to provide error feedback to app.
		// The best we can do at this point is set the pipeline name from the layout.
		setMetalObjectLabel(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

		MVKComputePipelineCompiler* plc = new MVKComputePipelineCompiler(this);
		_mtlPipelineState = plc->newMTLComputePipelineState(plDesc);	// retained
		plc->destroy();
		[plDesc release];															// temp release

		if ( !_mtlPipelineState ) { _hasValidMTLPipelineStates = false; }
	} else {
		_hasValidMTLPipelineStates = false;
	}
	if (pPipelineFB) {
		if (_hasValidMTLPipelineStates) { mvkEnableFlags(pPipelineFB->flags, VK_PIPELINE_CREATION_FEEDBACK_VALID_BIT); }
		pPipelineFB->duration = mvkGetElapsedNanoseconds(pipelineStart);
	}

	_stageResources.implicitBuffers.ids[MVKImplicitBuffer::PushConstant] = _layout->getPushConstantResourceIndex(kMVKShaderStageCompute);
	verifyImplicitBuffers(_stageResources.implicitBuffers, "Compute", _descriptorBufferCounts.stages[kMVKShaderStageCompute], this);
}

// Returns a MTLFunction to use when creating the MTLComputePipelineState.
MVKMTLFunction MVKComputePipeline::getMTLFunction(const VkComputePipelineCreateInfo* pCreateInfo,
												  VkPipelineCreationFeedback* pStageFB) {

    const VkPipelineShaderStageCreateInfo* pSS = &pCreateInfo->stage;
    if ( !mvkAreAllFlagsEnabled(pSS->stage, VK_SHADER_STAGE_COMPUTE_BIT) ) { return MVKMTLFunctionNull; }

	_module = getOrCreateShaderModule(_device, pSS, _ownsModule);

	warnIfBufferRobustnessEnabled(this, pSS);

	auto& mtlFeats = getMetalFeatures();
	auto& mvkCfg = getMVKConfig();
    SPIRVToMSLConversionConfiguration shaderConfig;
	shaderConfig.options.entryPointName = pCreateInfo->stage.pName;
	shaderConfig.options.entryPointStage = spv::ExecutionModelGLCompute;
    shaderConfig.options.mslOptions.msl_version = mtlFeats.mslVersion;
    shaderConfig.options.mslOptions.texel_buffer_texture_width = mtlFeats.maxTextureDimension;
    shaderConfig.options.mslOptions.r32ui_linear_texture_alignment = (uint32_t)_device->getVkFormatTexelBufferAlignment(VK_FORMAT_R32_UINT, this);
	shaderConfig.options.mslOptions.swizzle_texture_samples = _fullImageViewSwizzle && !mtlFeats.nativeTextureSwizzle;
	shaderConfig.options.mslOptions.texture_buffer_native = mtlFeats.textureBuffers;
	shaderConfig.options.mslOptions.dispatch_base = _allowsDispatchBase;
	shaderConfig.options.mslOptions.texture_1D_as_2D = mvkCfg.texture1DAs2D;
    shaderConfig.options.mslOptions.fixed_subgroup_size = mvkIsAnyFlagEnabled(pSS->flags, VK_PIPELINE_SHADER_STAGE_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT) ? 0 : mtlFeats.maxSubgroupSize;

	bool useMetalArgBuff = isUsingMetalArgumentBuffers();
	shaderConfig.options.mslOptions.argument_buffers = useMetalArgBuff;
	shaderConfig.options.mslOptions.force_active_argument_buffer_resources = false;
	shaderConfig.options.mslOptions.pad_argument_buffer_resources = useMetalArgBuff;
	shaderConfig.options.mslOptions.argument_buffers_tier = (SPIRV_CROSS_NAMESPACE::CompilerMSL::Options::ArgumentBuffersTier)getMetalFeatures().argumentBuffersTier;

#if MVK_MACOS
    shaderConfig.options.mslOptions.emulate_subgroups = !mtlFeats.simdPermute;
#endif
#if MVK_IOS_OR_TVOS
    shaderConfig.options.mslOptions.emulate_subgroups = !mtlFeats.quadPermute;
    shaderConfig.options.mslOptions.ios_use_simdgroup_functions = !!mtlFeats.simdPermute;
#endif

	MVKPipelineLayout* layout = (MVKPipelineLayout*)pCreateInfo->layout;
	layout->populateShaderConversionConfig(shaderConfig);

	// Set implicit buffer indices
	// FIXME: Many of these are optional. We shouldn't set the ones that aren't
	// present--or at least, we should move the ones that are down to avoid running over
	// the limit of available buffers. But we can't know that until we compile the shaders.
	_stageResources.implicitBuffers.ids[MVKImplicitBuffer::DynamicOffset] = getImplicitBufferIndex(0);
	_stageResources.implicitBuffers.ids[MVKImplicitBuffer::BufferSize]    = getImplicitBufferIndex(1);
	_stageResources.implicitBuffers.ids[MVKImplicitBuffer::Swizzle]       = getImplicitBufferIndex(2);
	_stageResources.implicitBuffers.ids[MVKImplicitBuffer::DispatchBase]  = getImplicitBufferIndex(3);

	addCommonImplicitBuffersToShaderConfig(shaderConfig, _stageResources.implicitBuffers.ids);
	shaderConfig.options.mslOptions.indirect_params_buffer_index = _stageResources.implicitBuffers.ids[MVKImplicitBuffer::DispatchBase];
	shaderConfig.options.mslOptions.replace_recursive_inputs = mvkOSVersionIsAtLeast(14.0, 17.0, 1.0);

    MVKMTLFunction func = _module->getMTLFunction(&shaderConfig, pSS->pSpecializationInfo, this, pStageFB);
	if ( !func.getMTLFunction() ) {
		if (shouldFailOnPipelineCompileRequired()) {
			setConfigurationResult(VK_PIPELINE_COMPILE_REQUIRED);
		} else {
			setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Compute shader function could not be compiled into pipeline. See previous logged error."));
		}
	}
	auto& funcRslts = func.shaderConversionResults;
	populateResourceUsage(_stageResources, shaderConfig, funcRslts, spv::ExecutionModelGLCompute);
	_layout->populateBindOperations(_stageResources.bindScript, shaderConfig, spv::ExecutionModelGLCompute);

	return func;
}

uint32_t MVKComputePipeline::getImplicitBufferIndex(uint32_t bufferIndexOffset) {
	return getMetalFeatures().maxPerStageBufferCount - (bufferIndexOffset + 1);
}

MVKComputePipeline::~MVKComputePipeline() {
	@synchronized (getMTLDevice()) {
		[_mtlPipelineState release];
		if (_ownsModule) delete _module;
	}
}


#pragma mark -
#pragma mark MVKPipelineCache

// Return a shader library from the specified shader conversion configuration sourced from the specified shader module.
MVKShaderLibrary* MVKPipelineCache::getShaderLibrary(SPIRVToMSLConversionConfiguration* pContext,
													 MVKShaderModule* shaderModule,
													 MVKPipeline* pipeline,
													 VkPipelineCreationFeedback* pShaderFeedback,
													 uint64_t startTime) {
	if (_isExternallySynchronized) {
		return getShaderLibraryImpl(pContext, shaderModule, pipeline, pShaderFeedback, startTime);
	} else {
		lock_guard<mutex> lock(_shaderCacheLock);
		return getShaderLibraryImpl(pContext, shaderModule, pipeline, pShaderFeedback, startTime);
	}
}

MVKShaderLibrary* MVKPipelineCache::getShaderLibraryImpl(SPIRVToMSLConversionConfiguration* pContext,
														 MVKShaderModule* shaderModule,
														 MVKPipeline* pipeline,
														 VkPipelineCreationFeedback* pShaderFeedback,
														 uint64_t startTime) {
	bool wasAdded = false;
	MVKShaderLibraryCache* slCache = getShaderLibraryCache(shaderModule->getKey());
	MVKShaderLibrary* shLib = slCache->getShaderLibrary(pContext, shaderModule, pipeline, &wasAdded, pShaderFeedback, startTime);
	if (wasAdded) { markDirty(); }
	else if (pShaderFeedback) { mvkEnableFlags(pShaderFeedback->flags, VK_PIPELINE_CREATION_FEEDBACK_APPLICATION_PIPELINE_CACHE_HIT_BIT); }
	return shLib;
}

// Returns a shader library cache for the specified shader module key, creating it if necessary.
MVKShaderLibraryCache* MVKPipelineCache::getShaderLibraryCache(MVKShaderModuleKey smKey) {
	MVKShaderLibraryCache* slCache = _shaderCache[smKey];
	if ( !slCache ) {
		slCache = new MVKShaderLibraryCache(this);
		_shaderCache[smKey] = slCache;
	}
	return slCache;
}


#pragma mark Streaming pipeline cache to and from offline memory

#if MVK_USE_CEREAL
static uint32_t kDataHeaderSize = (sizeof(uint32_t) * 4) + VK_UUID_SIZE;
#endif

// Entry type markers to be inserted into data stream
typedef enum {
	MVKPipelineCacheEntryTypeEOF = 0,
	MVKPipelineCacheEntryTypeShaderLibrary = 1,
} MVKPipelineCacheEntryType;

// Helper class to iterate through the shader libraries in a shader library cache in order to serialize them.
// Needs to support input of null shader library cache.
class MVKShaderCacheIterator : public MVKBaseObject {

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _pSLCache->getVulkanAPIObject(); };

protected:
	friend MVKPipelineCache;

	bool next() { return (++_index < (_pSLCache ? _pSLCache->_shaderLibraries.size() : 0)); }
	SPIRVToMSLConversionConfiguration& getShaderConversionConfig() { return _pSLCache->_shaderLibraries[_index].first; }
	MVKCompressor<std::string>& getCompressedMSL() { return _pSLCache->_shaderLibraries[_index].second->getCompressedMSL(); }
	SPIRVToMSLConversionResultInfo& getShaderConversionResultInfo() { return _pSLCache->_shaderLibraries[_index].second->_shaderConversionResultInfo; }
	MVKShaderCacheIterator(MVKShaderLibraryCache* pSLCache) : _pSLCache(pSLCache) {}

	MVKShaderLibraryCache* _pSLCache;
	size_t _count = 0;
	int32_t _index = -1;
};

VkResult MVKPipelineCache::writeData(size_t* pDataSize, void* pData) {
	if (_isExternallySynchronized) {
		return writeDataImpl(pDataSize, pData);
	} else {
		lock_guard<mutex> lock(_shaderCacheLock);
		return writeDataImpl(pDataSize, pData);
	}
}

// If pData is not null, serializes at most pDataSize bytes of the contents of the cache into that
// memory location, and returns the number of bytes serialized in pDataSize. If pData is null,
// returns the number of bytes required to serialize the contents of this pipeline cache.
// This is the compliment of the readData() function. The two must be kept aligned.
VkResult MVKPipelineCache::writeDataImpl(size_t* pDataSize, void* pData) {
#if MVK_USE_CEREAL
	try {

		if ( !pDataSize ) { return VK_SUCCESS; }

		if (pData) {
			if (*pDataSize >= _dataSize) {
				mvk::membuf mb((char*)pData, _dataSize);
				ostream outStream(&mb);
				writeData(outStream);
				*pDataSize = _dataSize;
				return VK_SUCCESS;
			} else {
				*pDataSize = 0;
				return VK_INCOMPLETE;
			}
		} else {
			if (_dataSize == 0) {
				mvk::countbuf cb;
				ostream outStream(&cb);
				writeData(outStream, true);
				_dataSize = cb.buffSize;
			}
			*pDataSize = _dataSize;
			return VK_SUCCESS;
		}

	} catch (cereal::Exception& ex) {
		*pDataSize = 0;
		return reportError(VK_INCOMPLETE, "Error writing pipeline cache data: %s", ex.what());
	}
#else
	*pDataSize = 0;
	return reportError(VK_INCOMPLETE, "Pipeline cache serialization is unavailable. To enable pipeline cache serialization, build MoltenVK with MVK_USE_CEREAL=1 build setting.");
#endif
}

// Serializes the data in this cache to a stream
void MVKPipelineCache::writeData(ostream& outstream, bool isCounting) {
#if MVK_USE_CEREAL
	MVKPerformanceTracker& perfTracker = isCounting
		? getPerformanceStats().pipelineCache.sizePipelineCache
		: getPerformanceStats().pipelineCache.writePipelineCache;

	uint32_t cacheEntryType;
	cereal::BinaryOutputArchive writer(outstream);

	// Write the data header...after ensuring correct byte-order.
	auto& devProps = getDeviceProperties();
	writer(NSSwapHostIntToLittle(kDataHeaderSize));
	writer(NSSwapHostIntToLittle(VK_PIPELINE_CACHE_HEADER_VERSION_ONE));
	writer(NSSwapHostIntToLittle(devProps.vendorID));
	writer(NSSwapHostIntToLittle(devProps.deviceID));
	writer(devProps.pipelineCacheUUID);

	// Shader libraries
	// Output a cache entry for each shader library, including the shader module key in each entry.
	cacheEntryType = MVKPipelineCacheEntryTypeShaderLibrary;
	for (auto& scPair : _shaderCache) {
		MVKShaderModuleKey smKey = scPair.first;
		MVKShaderCacheIterator cacheIter(scPair.second);
		while (cacheIter.next()) {
			uint64_t startTime = getPerformanceTimestamp();
			writer(cacheEntryType);
			writer(smKey);
			writer(cacheIter.getShaderConversionConfig());
			writer(cacheIter.getShaderConversionResultInfo());
			writer(cacheIter.getCompressedMSL());
			addPerformanceInterval(perfTracker, startTime);
		}
	}

	// Mark the end of the archive
	cacheEntryType = MVKPipelineCacheEntryTypeEOF;
	writer(cacheEntryType);
#else
	MVKAssert(false, "Pipeline cache serialization is unavailable. To enable pipeline cache serialization, build MoltenVK with MVK_USE_CEREAL=1 build setting.");
#endif
}

// Loads any data indicated by the creation info.
// This is the compliment of the writeData() function. The two must be kept aligned.
void MVKPipelineCache::readData(const VkPipelineCacheCreateInfo* pCreateInfo) {
#if MVK_USE_CEREAL
	try {

		size_t byteCount = pCreateInfo->initialDataSize;
		uint32_t cacheEntryType;

		// Must be able to read the header and at least one cache entry type.
		if (byteCount < kDataHeaderSize + sizeof(cacheEntryType)) { return; }

		mvk::membuf mb((char*)pCreateInfo->pInitialData, byteCount);
		istream inStream(&mb);
		cereal::BinaryInputArchive reader(inStream);

		// Read the data header...and ensure correct byte-order.
		uint32_t hdrComponent;
		uint8_t pcUUID[VK_UUID_SIZE];
		auto& dvcProps = getDeviceProperties();

		reader(hdrComponent);	// Header size
		if (NSSwapLittleIntToHost(hdrComponent) !=  kDataHeaderSize) { return; }

		reader(hdrComponent);	// Header version
		if (NSSwapLittleIntToHost(hdrComponent) !=  VK_PIPELINE_CACHE_HEADER_VERSION_ONE) { return; }

		reader(hdrComponent);	// Vendor ID
		if (NSSwapLittleIntToHost(hdrComponent) !=  dvcProps.vendorID) { return; }

		reader(hdrComponent);	// Device ID
		if (NSSwapLittleIntToHost(hdrComponent) !=  dvcProps.deviceID) { return; }

		reader(pcUUID);			// Pipeline cache UUID
		if ( !mvkAreEqual(pcUUID, dvcProps.pipelineCacheUUID, VK_UUID_SIZE) ) { return; }

		bool done = false;
		while ( !done ) {
			reader(cacheEntryType);
			switch (cacheEntryType) {
				case MVKPipelineCacheEntryTypeShaderLibrary: {
					uint64_t startTime = getPerformanceTimestamp();

					MVKShaderModuleKey smKey;
					reader(smKey);

					SPIRVToMSLConversionConfiguration shaderConversionConfig;
					reader(shaderConversionConfig);

					SPIRVToMSLConversionResultInfo resultInfo;
					reader(resultInfo);

					MVKCompressor<std::string> compressedMSL;
					reader(compressedMSL);

					// Add the shader library to the staging cache.
					MVKShaderLibraryCache* slCache = getShaderLibraryCache(smKey);
					addPerformanceInterval(getPerformanceStats().pipelineCache.readPipelineCache, startTime);
					slCache->addShaderLibrary(&shaderConversionConfig, resultInfo, compressedMSL);

					break;
				}

				default: {
					done = true;
					break;
				}
			}
		}

	} catch (cereal::Exception& ex) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Error reading pipeline cache data: %s", ex.what()));
	}
#else
	setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Pipeline cache serialization is unavailable. To enable pipeline cache serialization, build MoltenVK with MVK_USE_CEREAL=1 build setting."));
#endif
}

// Mark the cache as dirty, so that existing streaming info is released
void MVKPipelineCache::markDirty() {
	_dataSize = 0;
}

VkResult MVKPipelineCache::mergePipelineCaches(uint32_t srcCacheCount, const VkPipelineCache* pSrcCaches) {
	if (!_isMergeInternallySynchronized) {
		return mergePipelineCachesImpl(srcCacheCount, pSrcCaches);
	} else {
		lock_guard<mutex> lock(_shaderCacheLock);
		return mergePipelineCachesImpl(srcCacheCount, pSrcCaches);
	}
}

VkResult MVKPipelineCache::mergePipelineCachesImpl(uint32_t srcCacheCount, const VkPipelineCache* pSrcCaches) {
	for (uint32_t srcIdx = 0; srcIdx < srcCacheCount; srcIdx++) {
		MVKPipelineCache* srcPLC = (MVKPipelineCache*)pSrcCaches[srcIdx];
		for (auto& srcPair : srcPLC->_shaderCache) {
			getShaderLibraryCache(srcPair.first)->merge(srcPair.second);
		}
	}
	markDirty();

	return VK_SUCCESS;
}


#pragma mark Cereal archive definitions

namespace SPIRV_CROSS_NAMESPACE {

	template<class Archive>
	void serialize(Archive & archive, CompilerMSL::Options& opt) {
		archive(opt.platform,
				opt.msl_version,
				opt.texel_buffer_texture_width,
				opt.r32ui_linear_texture_alignment,
				opt.r32ui_alignment_constant_id,
				opt.swizzle_buffer_index,
				opt.indirect_params_buffer_index,
				opt.shader_output_buffer_index,
				opt.shader_patch_output_buffer_index,
				opt.shader_tess_factor_buffer_index,
				opt.buffer_size_buffer_index,
				opt.view_mask_buffer_index,
				opt.dynamic_offsets_buffer_index,
				opt.shader_input_buffer_index,
				opt.shader_index_buffer_index,
				opt.shader_patch_input_buffer_index,
				opt.shader_input_wg_index,
				opt.device_index,
				opt.enable_frag_output_mask,
				opt.additional_fixed_sample_mask,
				opt.enable_point_size_builtin,
				opt.enable_point_size_default,
				opt.default_point_size,
				opt.enable_frag_depth_builtin,
				opt.enable_frag_stencil_ref_builtin,
				opt.disable_rasterization,
				opt.capture_output_to_buffer,
				opt.swizzle_texture_samples,
				opt.tess_domain_origin_lower_left,
				opt.multiview,
				opt.multiview_layered_rendering,
				opt.view_index_from_device_index,
				opt.dispatch_base,
				opt.texture_1D_as_2D,
				opt.argument_buffers,
				opt.argument_buffers_tier,
				opt.runtime_array_rich_descriptor,
				opt.enable_base_index_zero,
				opt.pad_fragment_output_components,
				opt.ios_support_base_vertex_instance,
				opt.use_framebuffer_fetch_subpasses,
				opt.invariant_float_math,
				opt.emulate_cube_array,
				opt.enable_decoration_binding,
				opt.texture_buffer_native,
				opt.force_active_argument_buffer_resources,
				opt.pad_argument_buffer_resources,
				opt.force_native_arrays,
				opt.enable_clip_distance_user_varying,
				opt.multi_patch_workgroup,
				opt.raw_buffer_tese_input,
				opt.vertex_for_tessellation,
				opt.arrayed_subpass_input,
				opt.ios_use_simdgroup_functions,
				opt.emulate_subgroups,
				opt.fixed_subgroup_size,
				opt.vertex_index_type,
				opt.force_sample_rate_shading,
				opt.manual_helper_invocation_updates,
				opt.check_discarded_frag_stores,
				opt.sample_dref_lod_array_as_grad,
				opt.readwrite_texture_fences,
				opt.replace_recursive_inputs,
				opt.agx_manual_cube_grad_fixup,
				opt.force_fragment_with_side_effects_execution,
				opt.input_attachment_is_ds_attachment,
				opt.auto_disable_rasterization);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLShaderInterfaceVariable& si) {
		archive(si.location,
				si.component,
				si.format,
				si.builtin,
				si.vecsize,
				si.rate);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLResourceBinding& rb) {
		archive(rb.stage,
				rb.basetype,
				rb.desc_set,
				rb.binding,
				rb.count,
				rb.msl_buffer,
				rb.msl_texture,
				rb.msl_sampler);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLConstexprSampler& cs) {
		archive(cs.coord,
				cs.min_filter,
				cs.mag_filter,
				cs.mip_filter,
				cs.s_address,
				cs.t_address,
				cs.r_address,
				cs.compare_func,
				cs.border_color,
				cs.lod_clamp_min,
				cs.lod_clamp_max,
				cs.max_anisotropy,
				cs.planes,
				cs.resolution,
				cs.chroma_filter,
				cs.x_chroma_offset,
				cs.y_chroma_offset,
				cs.swizzle,
				cs.ycbcr_model,
				cs.ycbcr_range,
				cs.bpc,
				cs.compare_enable,
				cs.lod_clamp_enable,
				cs.anisotropy_enable,
				cs.ycbcr_conversion_enable);
	}

}

namespace mvk {

	template<class Archive>
	void serialize(Archive & archive, SPIRVWorkgroupSizeDimension& wsd) {
		archive(wsd.size,
				wsd.specializationID,
				wsd.isSpecialized);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVEntryPoint& ep) {
		archive(ep.mtlFunctionName,
				ep.workgroupSize.width,
				ep.workgroupSize.height,
				ep.workgroupSize.depth,
				ep.fpFastMathFlags);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVToMSLConversionOptions& opt) {
		archive(opt.mslOptions,
				opt.entryPointName,
				opt.entryPointStage,
				opt.tessPatchKind,
				opt.numTessControlPoints,
				opt.shouldFlipVertexY,
				opt.shouldFixupClipSpace);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLShaderInterfaceVariable& si) {
		archive(si.shaderVar,
				si.binding,
				si.outIsUsedByShader);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLResourceBinding& rb) {
		archive(rb.resourceBinding,
				rb.constExprSampler,
				rb.requiresConstExprSampler,
				rb.outIsUsedByShader);
	}

	template<class Archive>
	void serialize(Archive & archive, DescriptorBinding& db) {
		archive(db.stage,
				db.descriptorSet,
				db.binding,
				db.index);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVToMSLConversionConfiguration& cfg) {
		archive(cfg.options,
				cfg.shaderInputs,
				cfg.shaderOutputs,
				cfg.resourceBindings,
				cfg.discreteDescriptorSets,
				cfg.dynamicBufferDescriptors);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVToMSLConversionResultInfo& scr) {
		archive(scr.entryPoint,
				scr.specializationMacros,
				scr.isRasterizationDisabled,
				scr.isPositionInvariant,
				scr.needsSwizzleBuffer,
				scr.needsOutputBuffer,
				scr.needsPatchOutputBuffer,
				scr.needsBufferSizeBuffer,
				scr.needsDynamicOffsetBuffer,
				scr.needsInputThreadgroupMem,
				scr.needsDispatchBaseBuffer,
				scr.needsViewRangeBuffer,
				scr.usesPhysicalStorageBufferAddressesCapability);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLSpecializationMacroInfo& info) {
		archive(info.name,
				info.isFloat,
				info.isSigned);
	}

}

template<class Archive>
void serialize(Archive & archive, MVKShaderModuleKey& k) {
	archive(k.codeSize,
			k.codeHash);
}

template<class Archive, class C>
void serialize(Archive & archive, MVKCompressor<C>& comp) {
	archive(comp._compressed,
			comp._uncompressedSize,
			comp._algorithm);
}


#pragma mark Construction

MVKPipelineCache::MVKPipelineCache(MVKDevice* device, const VkPipelineCacheCreateInfo* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device),
	_isExternallySynchronized(getEnabledPipelineCreationCacheControlFeatures().pipelineCreationCacheControl &&
							  mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_PIPELINE_CACHE_CREATE_EXTERNALLY_SYNCHRONIZED_BIT)),
	_isMergeInternallySynchronized(getEnabledPipelineCreationCacheControlFeatures().pipelineCreationCacheControl &&
								   mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_PIPELINE_CACHE_CREATE_INTERNALLY_SYNCHRONIZED_MERGE_BIT_KHR)) {

	readData(pCreateInfo);
}

MVKPipelineCache::~MVKPipelineCache() {
	for (auto& pair : _shaderCache) { pair.second->destroy(); }
	_shaderCache.clear();
}


#pragma mark -
#pragma mark MVKRenderPipelineCompiler

id<MTLRenderPipelineState> MVKRenderPipelineCompiler::newMTLRenderPipelineState(MTLRenderPipelineDescriptor* mtlRPLDesc) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		auto mtlDev = getMTLDevice();
		@synchronized (mtlDev) {
			[mtlDev newRenderPipelineStateWithDescriptor: mtlRPLDesc
									   completionHandler: ^(id<MTLRenderPipelineState> ps, NSError* error) {
										   bool isLate = compileComplete(ps, error);
										   if (isLate) { destroy(); }
									   }];
		}
	});

	return [_mtlRenderPipelineState retain];
}

bool MVKRenderPipelineCompiler::compileComplete(id<MTLRenderPipelineState> mtlRenderPipelineState, NSError* compileError) {
	lock_guard<mutex> lock(_completionLock);

	_mtlRenderPipelineState = [mtlRenderPipelineState retain];		// retained
	return endCompile(compileError);
}

#pragma mark Construction

MVKRenderPipelineCompiler::~MVKRenderPipelineCompiler() {
	[_mtlRenderPipelineState release];
}


#pragma mark -
#pragma mark MVKComputePipelineCompiler

id<MTLComputePipelineState> MVKComputePipelineCompiler::newMTLComputePipelineState(MTLComputePipelineDescriptor* plDesc) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		auto mtlDev = getMTLDevice();
		@synchronized (mtlDev) {
			[mtlDev newComputePipelineStateWithDescriptor: plDesc
												  options: MTLPipelineOptionNone
										completionHandler: ^(id<MTLComputePipelineState> ps, MTLComputePipelineReflection*, NSError* error) {
											bool isLate = compileComplete(ps, error);
											if (isLate) { destroy(); }
										}];
		}
	});

	return [_mtlComputePipelineState retain];
}

bool MVKComputePipelineCompiler::compileComplete(id<MTLComputePipelineState> mtlComputePipelineState, NSError* compileError) {
	lock_guard<mutex> lock(_completionLock);

	_mtlComputePipelineState = [mtlComputePipelineState retain];		// retained
	return endCompile(compileError);
}

#pragma mark Construction

MVKComputePipelineCompiler::~MVKComputePipelineCompiler() {
	[_mtlComputePipelineState release];
}


#pragma mark -
#pragma mark Support functions

// Validate that the Cereal Archive covers the entire struct, to ensure consistency and accuracy.
// Ideally this should be a compile-time validation, but that doesn't appear to be possible, so we
// validate by serializing a struct and seeing if all the bytes of the struct have been serialized.
// Since sizeof() also includes gaps between the struct members, padByteCnt can be used to specify
// the amount of padding in the struct. This function works best for simple data structs. Care should
// be taken with structs that contain strings or collections, as streaming size depends on contents,
// and potentially an upgrade to the stdc++ library. Changes to basic struct sizes may affect the
// padding of aggregate structs that contain them.
template<class C>
static size_t mvkValidateCerealArchiveSize(size_t padByteCnt = 0) {
	int64_t missingBytes = 0;
#if MVK_USE_CEREAL
	mvk::countbuf cb;
	ostream outStream(&cb);
	cereal::BinaryOutputArchive writer(outStream);
	C obj = C();
	writer(obj);
	missingBytes = int64_t(sizeof(C)) - int64_t(cb.buffSize + padByteCnt);
	if (missingBytes) {
		printf("[MVK-BUILD-ERROR] Cereal serialization Archive for %s is not completely defined."
			   " Missing %lld bytes. Struct size is %zu (including an expected %zu bytes of padding)"
			   " and Cereal Archive size is %zu. The Cereal Archive definition may be missing members.\n",
			   mvk::getTypeName(&obj).c_str(), missingBytes, sizeof(C), padByteCnt, cb.buffSize);
	}
#endif
	return missingBytes;
}

void mvkValidateCeralArchiveDefinitions() {
	[[maybe_unused]] size_t missingBytes = 0;
	missingBytes += mvkValidateCerealArchiveSize<SPIRV_CROSS_NAMESPACE::CompilerMSL::Options>(5);
	missingBytes += mvkValidateCerealArchiveSize<SPIRV_CROSS_NAMESPACE::MSLShaderInterfaceVariable>();
	missingBytes += mvkValidateCerealArchiveSize<SPIRV_CROSS_NAMESPACE::MSLResourceBinding>();
	missingBytes += mvkValidateCerealArchiveSize<SPIRV_CROSS_NAMESPACE::MSLConstexprSampler>();
	missingBytes += mvkValidateCerealArchiveSize<mvk::SPIRVWorkgroupSizeDimension>(3);
	missingBytes += mvkValidateCerealArchiveSize<mvk::SPIRVEntryPoint>(20);						// Contains string
	missingBytes += mvkValidateCerealArchiveSize<mvk::SPIRVToMSLConversionOptions>(23);			// Contains string
	missingBytes += mvkValidateCerealArchiveSize<mvk::MSLShaderInterfaceVariable>(3);
	missingBytes += mvkValidateCerealArchiveSize<mvk::MSLResourceBinding>(2);
	missingBytes += mvkValidateCerealArchiveSize<mvk::DescriptorBinding>();
	missingBytes += mvkValidateCerealArchiveSize<mvk::SPIRVToMSLConversionConfiguration>(103);	// Contains collection
	missingBytes += mvkValidateCerealArchiveSize<mvk::SPIRVToMSLConversionResultInfo>(41);		// Contains collection
	missingBytes += mvkValidateCerealArchiveSize<mvk::MSLSpecializationMacroInfo>(22);			// Contains string
	missingBytes += mvkValidateCerealArchiveSize<MVKShaderModuleKey>();
	missingBytes += mvkValidateCerealArchiveSize<MVKCompressor<std::string>>(20);				// Contains collection
	assert(missingBytes == 0 && "Cereal Archive definitions incomplete. See previous logged errors.");
}
