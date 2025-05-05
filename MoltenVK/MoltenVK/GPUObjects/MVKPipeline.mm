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
#include "MVKRenderPass.h"
#include "MVKCommandBuffer.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKStrings.h"
#include "MTLRenderPipelineDescriptor+MoltenVK.h"
#if MVK_USE_METAL_PRIVATE_API
#include "MTLRenderPipelineColorAttachmentDescriptor+MoltenVK.h"
#endif
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


#pragma mark MVKPipelineLayout

// A null cmdEncoder can be passed to perform a validation pass
void MVKPipelineLayout::bindDescriptorSets(MVKCommandEncoder* cmdEncoder,
										   VkPipelineBindPoint pipelineBindPoint,
                                           MVKArrayRef<MVKDescriptorSet*> descriptorSets,
                                           uint32_t firstSet,
                                           MVKArrayRef<uint32_t> dynamicOffsets) {
	if (!cmdEncoder) { clearConfigurationResult(); }
	uint32_t dynamicOffsetIndex = 0;
	size_t dsCnt = descriptorSets.size();
	for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
		MVKDescriptorSet* descSet = descriptorSets[dsIdx];
		uint32_t dslIdx = firstSet + dsIdx;
		MVKDescriptorSetLayout* dsl = _descriptorSetLayouts[dslIdx];
		dsl->bindDescriptorSet(cmdEncoder, pipelineBindPoint,
							   dslIdx, descSet,
							   _dslMTLResourceIndexOffsets[dslIdx],
							   dynamicOffsets, dynamicOffsetIndex);
		if (!cmdEncoder) { setConfigurationResult(dsl->getConfigurationResult()); }
	}
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKPipelineLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                          VkPipelineBindPoint pipelineBindPoint,
                                          MVKArrayRef<VkWriteDescriptorSet> descriptorWrites,
                                          uint32_t set) {
	if (!cmdEncoder) { clearConfigurationResult(); }
	MVKDescriptorSetLayout* dsl = _descriptorSetLayouts[set];
	dsl->pushDescriptorSet(cmdEncoder, pipelineBindPoint, descriptorWrites, _dslMTLResourceIndexOffsets[set]);
	if (!cmdEncoder) { setConfigurationResult(dsl->getConfigurationResult()); }
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKPipelineLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                          MVKDescriptorUpdateTemplate* descUpdateTemplate,
                                          uint32_t set,
                                          const void* pData) {
	if (!cmdEncoder) { clearConfigurationResult(); }
	MVKDescriptorSetLayout* dsl = _descriptorSetLayouts[set];
	dsl->pushDescriptorSet(cmdEncoder, descUpdateTemplate, pData, _dslMTLResourceIndexOffsets[set]);
	if (!cmdEncoder) { setConfigurationResult(dsl->getConfigurationResult()); }
}

void MVKPipelineLayout::populateShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig) {
	shaderConfig.resourceBindings.clear();
	shaderConfig.discreteDescriptorSets.clear();
	shaderConfig.dynamicBufferDescriptors.clear();

	// Add any resource bindings used by push-constants.
	// Use VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK descriptor type as compatible with push constants in Metal.
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (stageUsesPushConstants((MVKShaderStage)stage)) {
			mvkPopulateShaderConversionConfig(shaderConfig,
											  _pushConstantsMTLResourceIndexes.stages[stage],
											  MVKShaderStage(stage),
											  kPushConstDescSet,
											  kPushConstBinding,
											  1,
											  VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK,
											  nullptr,
											  getMetalFeatures().nativeTextureAtomics);
		}
	}

    // Add resource bindings defined in the descriptor set layouts
	auto dslCnt = _descriptorSetLayouts.size();
	for (uint32_t dslIdx = 0; dslIdx < dslCnt; dslIdx++) {
		_descriptorSetLayouts[dslIdx]->populateShaderConversionConfig(shaderConfig,
																	  _dslMTLResourceIndexOffsets[dslIdx],
																	  dslIdx);
	}
}

bool MVKPipelineLayout::stageUsesPushConstants(MVKShaderStage mvkStage) {
	VkShaderStageFlagBits vkStage = mvkVkShaderStageFlagBitsFromMVKShaderStage(mvkStage);
	for (auto pushConst : _pushConstants) {
		if (mvkIsAnyFlagEnabled(pushConst.stageFlags, vkStage)) {
			return true;
		}
	}
	return false;
}

std::string MVKPipelineLayout::getLogDescription(std::string indent) {
	std::stringstream descStr;
	size_t dslCnt = _descriptorSetLayouts.size();
	descStr << "VkPipelineLayout with " << dslCnt << " descriptor set layouts:";
	auto descLayoutIndent = indent + "\t";
	for (uint32_t dslIdx = 0; dslIdx < dslCnt; dslIdx++) {
		descStr << "\n" << descLayoutIndent << dslIdx << ": " << _descriptorSetLayouts[dslIdx]->getLogDescription(descLayoutIndent);
	}
	return descStr.str();
}

bool MVKPipelineLayout::isUsingMetalArgumentBuffers() {
	return MVKDeviceTrackingMixin::isUsingMetalArgumentBuffers() && _canUseMetalArgumentBuffers;
}

MVKPipelineLayout::MVKPipelineLayout(MVKDevice* device,
                                     const VkPipelineLayoutCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {

	_canUseMetalArgumentBuffers = false;
	uint32_t dslCnt = pCreateInfo->setLayoutCount;
	_descriptorSetLayouts.reserve(dslCnt);
	for (uint32_t i = 0; i < dslCnt; i++) {
		MVKDescriptorSetLayout* pDescSetLayout = (MVKDescriptorSetLayout*)pCreateInfo->pSetLayouts[i];
		pDescSetLayout->retain();
		_descriptorSetLayouts.push_back(pDescSetLayout);
		_canUseMetalArgumentBuffers = _canUseMetalArgumentBuffers || pDescSetLayout->isUsingMetalArgumentBuffers();
	}

	// For pipeline layout compatibility (“compatible for set N”),
	// consume the Metal resource indexes in this order:
	//   - Fixed count of argument buffers for descriptor sets (if using Metal argument buffers).
	//   - Push constants
	//   - Descriptor set content

	// If we are using Metal argument buffers, consume a number of
	// buffer indexes covering all descriptor sets for the Metal
	// argument buffers themselves.
	if (isUsingMetalArgumentBuffers()) {
		_mtlResourceCounts.addArgumentBuffers(kMVKMaxDescriptorSetCount);
	}

	// Add push constants from config
	_pushConstants.reserve(pCreateInfo->pushConstantRangeCount);
	for (uint32_t i = 0; i < pCreateInfo->pushConstantRangeCount; i++) {
		_pushConstants.push_back(pCreateInfo->pPushConstantRanges[i]);
	}

	// Set push constant resource indexes, and consume a buffer index for any stage that uses a push constant buffer.
	_pushConstantsMTLResourceIndexes = _mtlResourceCounts;
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (stageUsesPushConstants((MVKShaderStage)stage)) {
			_mtlResourceCounts.stages[stage].bufferIndex++;
		}
	}

	// Add descriptor set layouts, accumulating the resource index offsets used by the corresponding DSL,
	// and associating the current accumulated resource index offsets with each DSL as it is added.
	for (uint32_t i = 0; i < dslCnt; i++) {
		MVKDescriptorSetLayout* pDescSetLayout = _descriptorSetLayouts[i];
		MVKShaderResourceBinding adjstdDSLRezOfsts = _mtlResourceCounts;
		MVKShaderResourceBinding adjstdDSLRezCnts = pDescSetLayout->_mtlResourceCounts;
		if (pDescSetLayout->isUsingMetalArgumentBuffers()) {
			adjstdDSLRezOfsts.clearArgumentBufferResources();
			adjstdDSLRezCnts.clearArgumentBufferResources();
		}
		_dslMTLResourceIndexOffsets.push_back(adjstdDSLRezOfsts);
		_mtlResourceCounts += adjstdDSLRezCnts;
	}

	MVKLogDebugIf(getMVKConfig().debugMode, "Created %s\n", getLogDescription().c_str());
}

MVKPipelineLayout::~MVKPipelineLayout() {
	for (auto dsl : _descriptorSetLayouts) { dsl->release(); }
}


#pragma mark -
#pragma mark MVKPipeline

void MVKPipeline::bindPushConstants(MVKCommandEncoder* cmdEncoder) {
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (cmdEncoder) {
			auto* pcState = cmdEncoder->getPushConstants(mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage(stage)));
			pcState->setMTLBufferIndex(_pushConstantsBufferIndex.stages[stage], _stageUsesPushConstants[stage]);
		}
	}
}

// For each descriptor set, populate the descriptor bindings used by the shader for this stage.
template<typename CreateInfo>
void MVKPipeline::populateDescriptorSetBindingUse(MVKMTLFunction& mvkMTLFunc,
												  const CreateInfo* pCreateInfo,
												  SPIRVToMSLConversionConfiguration& shaderConfig,
												  MVKShaderStage stage) {
	if (isUsingMetalArgumentBuffers()) {
		for (uint32_t dsIdx = 0; dsIdx < _descriptorSetCount; dsIdx++) {
			auto* dsLayout = ((MVKPipelineLayout*)pCreateInfo->layout)->getDescriptorSetLayout(dsIdx);
			dsLayout->populateBindingUse(getDescriptorBindingUse(dsIdx, stage), shaderConfig, stage, dsIdx);
		}
	}
}

MVKPipeline::MVKPipeline(MVKDevice* device, MVKPipelineCache* pipelineCache, MVKPipelineLayout* layout,
						 VkPipelineCreateFlags2 flags, MVKPipeline* parent) :
	MVKVulkanAPIDeviceObject(device),
	_pipelineCache(pipelineCache),
	_flags(flags),
	_descriptorSetCount(uint32_t(layout->_descriptorSetLayouts.size())),
	_fullImageViewSwizzle(getMVKConfig().fullImageViewSwizzle) {

		// Establish descriptor counts and push constants use.
		for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
			_descriptorBufferCounts.stages[stage] = layout->_mtlResourceCounts.stages[stage].bufferIndex;
			_pushConstantsBufferIndex.stages[stage] = layout->_pushConstantsMTLResourceIndexes.stages[stage].bufferIndex;
			_stageUsesPushConstants[stage] = layout->stageUsesPushConstants((MVKShaderStage)stage);
		}
	}


#pragma mark -
#pragma mark MVKGraphicsPipeline

// Set retrieve-only rendering state when pipeline is bound, as it's too late at draw command.
void MVKGraphicsPipeline::wasBound(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_renderingState.setPatchControlPoints(_tessInfo.patchControlPoints, false);
	cmdEncoder->_renderingState.setSampleLocations(_sampleLocations.contents(), false);
	cmdEncoder->_renderingState.setSampleLocationsEnable(_sampleLocationsEnable, false);
}

void MVKGraphicsPipeline::getStages(MVKPiplineStages& stages) {
    if (isTessellationPipeline()) {
        stages.push_back(kMVKGraphicsStageVertex);
        stages.push_back(kMVKGraphicsStageTessControl);
    }
    stages.push_back(kMVKGraphicsStageRasterization);
}

void MVKGraphicsPipeline::encode(MVKCommandEncoder* cmdEncoder, uint32_t stage) {
	if ( !_hasValidMTLPipelineStates ) { return; }

    id<MTLRenderCommandEncoder> mtlCmdEnc = cmdEncoder->_mtlRenderEncoder;
	id<MTLComputeCommandEncoder> tessCtlEnc;
    if ( stage == kMVKGraphicsStageRasterization && !mtlCmdEnc ) { return; }   // Pre-renderpass. Come back later.

    switch (stage) {

		case kMVKGraphicsStageVertex: {
			// Stage 1 of a tessellated draw: compute pipeline to run the vertex shader.
			// N.B. This will prematurely terminate the current subpass. We'll have to remember to start it back up again.
			// Due to yet another impedance mismatch between Metal and Vulkan, which pipeline
			// state we use depends on whether or not we have an index buffer, and if we do,
			// the kind of indices in it.

            id<MTLComputePipelineState> plState;
			const MVKIndexMTLBufferBinding& indexBuff = cmdEncoder->_graphicsResourcesState._mtlIndexBufferBinding;
            if (!cmdEncoder->_isIndexedDraw) {
                plState = getTessVertexStageState();
            } else if (indexBuff.mtlIndexType == MTLIndexTypeUInt16) {
                plState = getTessVertexStageIndex16State();
            } else {
                plState = getTessVertexStageIndex32State();
            }

			if ( !_hasValidMTLPipelineStates ) { return; }

            tessCtlEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
            [tessCtlEnc setComputePipelineState: plState];
            break;
		}

        case kMVKGraphicsStageTessControl: {
			// Stage 2 of a tessellated draw: compute pipeline to run the tess. control shader.
			if ( !_mtlTessControlStageState ) { return; }		// Abort if pipeline could not be created.

            tessCtlEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
            [tessCtlEnc setComputePipelineState: _mtlTessControlStageState];
            break;
        }

        case kMVKGraphicsStageRasterization:
			// Stage 3 of a tessellated draw:

			if ( !_mtlPipelineState ) { return; }		// Abort if pipeline could not be created.
            // Render pipeline state
			if (cmdEncoder->getSubpass()->isMultiview() && !isTessellationPipeline() && !_multiviewMTLPipelineStates.empty()) {
				[mtlCmdEnc setRenderPipelineState: _multiviewMTLPipelineStates[cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex())]];
			} else {
				[mtlCmdEnc setRenderPipelineState: _mtlPipelineState];
			}

            // Depth stencil state - Cleared _depthStencilInfo values will disable depth testing
			cmdEncoder->_depthStencilState.setDepthStencilState(_depthStencilInfo);

            // Rasterization
			cmdEncoder->_renderingState.setPrimitiveTopology(_vkPrimitiveTopology, false);
			cmdEncoder->_renderingState.setPrimitiveRestartEnable(_primitiveRestartEnable, false);
			cmdEncoder->_renderingState.setBlendConstants(_blendConstants, false);
			cmdEncoder->_renderingState.setDepthBounds({_depthStencilInfo.minDepthBounds, _depthStencilInfo.maxDepthBounds}, false);
			cmdEncoder->_renderingState.setStencilReferenceValues(_depthStencilInfo);
            cmdEncoder->_renderingState.setViewports(_viewports.contents(), 0, false);
            cmdEncoder->_renderingState.setScissors(_scissors.contents(), 0, false);
			if (_hasRasterInfo) {
				cmdEncoder->_renderingState.setCullMode(_rasterInfo.cullMode, false);
				cmdEncoder->_renderingState.setFrontFace(_rasterInfo.frontFace, false);
				cmdEncoder->_renderingState.setPolygonMode(_rasterInfo.polygonMode, false);
				cmdEncoder->_renderingState.setLineWidth(_rasterInfo.lineWidth, false);
				cmdEncoder->_renderingState.setDepthBias(_rasterInfo);
				cmdEncoder->_renderingState.setDepthClipEnable( !_rasterInfo.depthClampEnable, false );
			}
            break;
    }

	cmdEncoder->_graphicsResourcesState.markOverriddenBufferIndexesDirty();
    cmdEncoder->_graphicsResourcesState.bindSwizzleBuffer(_swizzleBufferIndex, _needsVertexSwizzleBuffer, _needsTessCtlSwizzleBuffer, _needsTessEvalSwizzleBuffer, _needsFragmentSwizzleBuffer);
    cmdEncoder->_graphicsResourcesState.bindBufferSizeBuffer(_bufferSizeBufferIndex, _needsVertexBufferSizeBuffer, _needsTessCtlBufferSizeBuffer, _needsTessEvalBufferSizeBuffer, _needsFragmentBufferSizeBuffer);
	cmdEncoder->_graphicsResourcesState.bindDynamicOffsetBuffer(_dynamicOffsetBufferIndex, _needsVertexDynamicOffsetBuffer, _needsTessCtlDynamicOffsetBuffer, _needsTessEvalDynamicOffsetBuffer, _needsFragmentDynamicOffsetBuffer);
    cmdEncoder->_graphicsResourcesState.bindViewRangeBuffer(_viewRangeBufferIndex, _needsVertexViewRangeBuffer, _needsFragmentViewRangeBuffer);
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

MVKGraphicsPipeline::MVKGraphicsPipeline(MVKDevice* device,
										 MVKPipelineCache* pipelineCache,
										 MVKPipeline* parent,
										 const VkGraphicsPipelineCreateInfo* pCreateInfo) :
	MVKPipeline(device, pipelineCache, (MVKPipelineLayout*)pCreateInfo->layout, getPipelineCreateFlags(pCreateInfo), parent) {


	// Extract dynamic state first, as it can affect many configurations.
	initDynamicState(pCreateInfo);

	// Determine rasterization early, as various other structs are validated and interpreted in this context.
	const VkPipelineRenderingCreateInfo* pRendInfo = getRenderingCreateInfo(pCreateInfo);
	_isRasterizing = !isRasterizationDisabled(pCreateInfo);
	_isRasterizingColor = _isRasterizing && mvkHasColorAttachments(pRendInfo);

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
	mvkSetOrClear(&_tessInfo, _isTessellationPipeline ? pCreateInfo->pTessellationState : nullptr);

	// Handles depth attachment being used as input attachment. However, it does not solve the issue when
	// the pipeline is created without render pass (dynamic rendering) since we won't be able to know
	// which resources will be used when rendering. Needs to be done before we do shaders
	// Potential solution would be to generate 2 pipelines, one with the workaround for the Metal issue
	// and one without it, and decide at bind time once we know the resources which one to use.
	if (pCreateInfo->renderPass) {
		MVKRenderSubpass* subpass = ((MVKRenderPass*)pCreateInfo->renderPass)->getSubpass(pCreateInfo->subpass);
		_inputAttachmentIsDSAttachment = subpass->isInputAttachmentDepthStencilAttachment();
	}

	// Render pipeline state. Do this as early as possible, to fail fast if pipeline requires a fail on cache-miss.
	initMTLRenderPipelineState(pCreateInfo, reflectData, pPipelineFB, pVertexSS, pVertexFB, pTessCtlSS, pTessCtlFB, pTessEvalSS, pTessEvalFB, pFragmentSS, pFragmentFB);
	if ( !_hasValidMTLPipelineStates ) { return; }

	// Blending - must ignore allowed bad pColorBlendState pointer if rasterization disabled or no color attachments
	if (_isRasterizingColor && pCreateInfo->pColorBlendState) {
		mvkCopy(_blendConstants.float32, pCreateInfo->pColorBlendState->blendConstants, 4);
	}

	// Topology
	_vkPrimitiveTopology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
	_primitiveRestartEnable = true;			// Always enabled in Metal
	if (pCreateInfo->pInputAssemblyState) {
		_vkPrimitiveTopology = pCreateInfo->pInputAssemblyState->topology;
		_primitiveRestartEnable = pCreateInfo->pInputAssemblyState->primitiveRestartEnable;
	}

	// In Metal, primitive restart cannot be disabled, so issue a warning if the app
	// has disabled it statically, or indicates that it might do so dynamically.
	// Just issue a warning here, as it is very likely the app is not actually
	// expecting to use primitive restart at all, and is disabling it "just-in-case".
	// As such, forcing an error here would be unexpected to the app (including CTS).
	// BTW, although Metal docs avoid mentioning it, testing shows that Metal does not support primitive
	// restart for list topologies, meaning VK_EXT_primitive_topology_list_restart cannot be supported.
	if (( !_primitiveRestartEnable || isDynamicState(PrimitiveRestartEnable)) &&
		 (_vkPrimitiveTopology == VK_PRIMITIVE_TOPOLOGY_LINE_STRIP ||
		  _vkPrimitiveTopology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP ||
		  _vkPrimitiveTopology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN ||
		  isDynamicState(PrimitiveTopology))) {
		reportWarning(VK_ERROR_FEATURE_NOT_PRESENT, "Metal does not support disabling primitive restart.");
	}

	// Rasterization
	_hasRasterInfo = mvkSetOrClear(&_rasterInfo, pCreateInfo->pRasterizationState);

	// Must run after _isRasterizing and _dynamicState are populated
	initSampleLocations(pCreateInfo);

	// Depth stencil content - clearing will disable depth and stencil testing
	// Must ignore allowed bad pDepthStencilState pointer if rasterization disabled or no depth or stencil attachment format
	bool isRasterizingDepthStencil = _isRasterizing && (pRendInfo->depthAttachmentFormat || pRendInfo->stencilAttachmentFormat);
	mvkSetOrClear(&_depthStencilInfo, isRasterizingDepthStencil ? pCreateInfo->pDepthStencilState : nullptr);

	// Viewports and scissors - must ignore allowed bad pViewportState pointer if rasterization is disabled
	auto pVPState = _isRasterizing ? pCreateInfo->pViewportState : nullptr;
	if (pVPState) {

		// If viewports are dynamic, ignore them here.
		uint32_t vpCnt = (pVPState->pViewports && !isDynamicState(Viewports)) ? pVPState->viewportCount : 0;
		_viewports.reserve(vpCnt);
		for (uint32_t vpIdx = 0; vpIdx < vpCnt; vpIdx++) {
			_viewports.push_back(pVPState->pViewports[vpIdx]);
		}

		// If scissors are dynamic, ignore them here.
		uint32_t sCnt = (pVPState->pScissors && !isDynamicState(Scissors)) ? pVPState->scissorCount : 0;
		_scissors.reserve(sCnt);
		for (uint32_t sIdx = 0; sIdx < sCnt; sIdx++) {
			_scissors.push_back(pVPState->pScissors[sIdx]);
		}
	}
}

static MVKRenderStateType getRenderStateType(VkDynamicState vkDynamicState) {
	switch (vkDynamicState) {
		case VK_DYNAMIC_STATE_BLEND_CONSTANTS:             return BlendConstants;
		case VK_DYNAMIC_STATE_CULL_MODE:                   return CullMode;
		case VK_DYNAMIC_STATE_DEPTH_BIAS:                  return DepthBias;
		case VK_DYNAMIC_STATE_DEPTH_BIAS_ENABLE:           return DepthBiasEnable;
		case VK_DYNAMIC_STATE_DEPTH_BOUNDS:                return DepthBounds;
		case VK_DYNAMIC_STATE_DEPTH_BOUNDS_TEST_ENABLE:    return DepthBoundsTestEnable;
		case VK_DYNAMIC_STATE_DEPTH_CLAMP_ENABLE_EXT:      return DepthClipEnable;
		case VK_DYNAMIC_STATE_DEPTH_CLIP_ENABLE_EXT:       return DepthClipEnable;
		case VK_DYNAMIC_STATE_DEPTH_COMPARE_OP:            return DepthCompareOp;
		case VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE:           return DepthTestEnable;
		case VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE:          return DepthWriteEnable;
		case VK_DYNAMIC_STATE_FRONT_FACE:                  return FrontFace;
		case VK_DYNAMIC_STATE_LINE_WIDTH:                  return LineWidth;
		case VK_DYNAMIC_STATE_LOGIC_OP_EXT:                return LogicOp;
		case VK_DYNAMIC_STATE_LOGIC_OP_ENABLE_EXT:         return LogicOpEnable;
		case VK_DYNAMIC_STATE_PATCH_CONTROL_POINTS_EXT:    return PatchControlPoints;
		case VK_DYNAMIC_STATE_POLYGON_MODE_EXT:            return PolygonMode;
		case VK_DYNAMIC_STATE_PRIMITIVE_RESTART_ENABLE:    return PrimitiveRestartEnable;
		case VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY:          return PrimitiveTopology;
		case VK_DYNAMIC_STATE_RASTERIZER_DISCARD_ENABLE:   return RasterizerDiscardEnable;
		case VK_DYNAMIC_STATE_SAMPLE_LOCATIONS_EXT:        return SampleLocations;
		case VK_DYNAMIC_STATE_SAMPLE_LOCATIONS_ENABLE_EXT: return SampleLocationsEnable;
		case VK_DYNAMIC_STATE_SCISSOR:                     return Scissors;
		case VK_DYNAMIC_STATE_SCISSOR_WITH_COUNT:          return Scissors;
		case VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK:        return StencilCompareMask;
		case VK_DYNAMIC_STATE_STENCIL_OP:                  return StencilOp;
		case VK_DYNAMIC_STATE_STENCIL_REFERENCE:           return StencilReference;
		case VK_DYNAMIC_STATE_STENCIL_TEST_ENABLE:         return StencilTestEnable;
		case VK_DYNAMIC_STATE_STENCIL_WRITE_MASK:          return StencilWriteMask;
		case VK_DYNAMIC_STATE_VERTEX_INPUT_BINDING_STRIDE: return VertexStride;
		case VK_DYNAMIC_STATE_VIEWPORT:                    return Viewports;
		case VK_DYNAMIC_STATE_VIEWPORT_WITH_COUNT:         return Viewports;
		default:                                           return Unknown;
	}
}

// This is executed first during pipeline creation. Do not depend on any internal state here.
void MVKGraphicsPipeline::initDynamicState(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	const auto* pDS = pCreateInfo->pDynamicState;
	if ( !pDS ) { return; }

	for (uint32_t i = 0; i < pDS->dynamicStateCount; i++) {
		auto dynStateType = getRenderStateType(pDS->pDynamicStates[i]);
		bool isDynamic = true;

		// Some dynamic states have other restrictions
		switch (dynStateType) {
			case VertexStride:
				isDynamic = getMetalFeatures().dynamicVertexStride;
				if ( !isDynamic ) { setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "This device and platform does not support VK_DYNAMIC_STATE_VERTEX_INPUT_BINDING_STRIDE (macOS 14.0 or iOS/tvOS 17.0, plus either Apple4 or Mac2 GPU).")); }
				break;
			default:
				break;
		}

		if (isDynamic) { _dynamicState.enable(dynStateType); }
	}
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
				_sampleLocationsEnable = pSampLocnsCreateInfo->sampleLocationsEnable;
				for (uint32_t slIdx = 0; slIdx < pSampLocnsCreateInfo->sampleLocationsInfo.sampleLocationsCount; slIdx++) {
					_sampleLocations.push_back(pSampLocnsCreateInfo->sampleLocationsInfo.pSampleLocations[slIdx]);
				}
				break;
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

	if (isUsingMetalArgumentBuffers()) { _descriptorBindingUse.resize(_descriptorSetCount); }

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
			const VkPipelineRenderingCreateInfo* pRendInfo = getRenderingCreateInfo(pCreateInfo);
			if (pRendInfo && mvkIsMultiview(pRendInfo->viewMask)) {
				// We need to adjust the step rate for per-instance attributes to account for the
				// extra instances needed to render all views. But, there's a problem: vertex input
				// descriptions are static pipeline state. If we need multiple passes, and some have
				// different numbers of views to render than others, then the step rate must be different
				// for these passes. We'll need to make a pipeline for every pass view count we can see
				// in the render pass. This really sucks.
				std::unordered_set<uint32_t> viewCounts;
				for (uint32_t passIdx = 0; passIdx < getDevice()->getMultiviewMetalPassCount(pRendInfo->viewMask); ++passIdx) {
					viewCounts.insert(getDevice()->getViewCountInMetalPass(pRendInfo->viewMask, passIdx));
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
	plDesc.stageInputDescriptor.indexBufferIndex = _indirectParamsIndex.stages[kMVKShaderStageVertex];

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

bool MVKGraphicsPipeline::verifyImplicitBuffer(bool needsBuffer, MVKShaderImplicitRezBinding& index, MVKShaderStage stage, const char* name) {
	const char* stageNames[] = {
		"Vertex",
		"Tessellation control",
		"Tessellation evaluation",
		"Fragment"
	};
	if (needsBuffer && index.stages[stage] < _descriptorBufferCounts.stages[stage]) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "%s shader requires %s buffer, but there is no free slot to pass it.", stageNames[stage], name));
		return false;
	}
	return true;
}

// Adds a vertex shader to the pipeline description.
bool MVKGraphicsPipeline::addVertexShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													const VkGraphicsPipelineCreateInfo* pCreateInfo,
													SPIRVToMSLConversionConfiguration& shaderConfig,
													const VkPipelineShaderStageCreateInfo* pVertexSS,
													VkPipelineCreationFeedback* pVertexFB,
													const VkPipelineShaderStageCreateInfo*& pFragmentSS) {
	shaderConfig.options.entryPointStage = spv::ExecutionModelVertex;
	shaderConfig.options.entryPointName = pVertexSS->pName;
	shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.indirect_params_buffer_index = _indirectParamsIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.shader_output_buffer_index = _outputBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.view_mask_buffer_index = _viewRangeBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.capture_output_to_buffer = false;
	shaderConfig.options.mslOptions.disable_rasterization = !_isRasterizing;
    addVertexInputToShaderConversionConfig(shaderConfig, pCreateInfo);

	MVKMTLFunction func = getMTLFunction(shaderConfig, pVertexSS, pVertexFB, _vertexModule, "Vertex");
	id<MTLFunction> mtlFunc = func.getMTLFunction();
	plDesc.vertexFunction = mtlFunc;
	if ( !mtlFunc ) { return false; }

	auto& funcRslts = func.shaderConversionResults;
	plDesc.rasterizationEnabled = !funcRslts.isRasterizationDisabled;
	_needsVertexSwizzleBuffer = funcRslts.needsSwizzleBuffer;
	_needsVertexBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsVertexDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
	_needsVertexViewRangeBuffer = funcRslts.needsViewRangeBuffer;
	_needsVertexOutputBuffer = funcRslts.needsOutputBuffer;
	markIfUsingPhysicalStorageBufferAddressesCapability(funcRslts, kMVKShaderStageVertex);

	populateDescriptorSetBindingUse(func, pCreateInfo, shaderConfig, kMVKShaderStageVertex);

	if (funcRslts.isRasterizationDisabled) {
		pFragmentSS = nullptr;
	}

	// If we need the swizzle buffer and there's no place to put it, we're in serious trouble.
	if (!verifyImplicitBuffer(_needsVertexSwizzleBuffer, _swizzleBufferIndex, kMVKShaderStageVertex, "swizzle")) {
		return false;
	}
	// Ditto buffer size buffer.
	if (!verifyImplicitBuffer(_needsVertexBufferSizeBuffer, _bufferSizeBufferIndex, kMVKShaderStageVertex, "buffer size")) {
		return false;
	}
	// Ditto dynamic offset buffer.
	if (!verifyImplicitBuffer(_needsVertexDynamicOffsetBuffer, _dynamicOffsetBufferIndex, kMVKShaderStageVertex, "dynamic offset")) {
		return false;
	}
	// Ditto captured output buffer.
	if (!verifyImplicitBuffer(_needsVertexOutputBuffer, _outputBufferIndex, kMVKShaderStageVertex, "output")) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsVertexOutputBuffer, _indirectParamsIndex, kMVKShaderStageVertex, "indirect parameters")) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsVertexViewRangeBuffer, _viewRangeBufferIndex, kMVKShaderStageVertex, "view range")) {
		return false;
	}
	return true;
}

// Adds a vertex shader compiled as a compute kernel to the pipeline description.
bool MVKGraphicsPipeline::addVertexShaderToPipeline(MTLComputePipelineDescriptor* plDesc,
													const VkGraphicsPipelineCreateInfo* pCreateInfo,
													SPIRVToMSLConversionConfiguration& shaderConfig,
													SPIRVShaderInputs& tcInputs,
													const VkPipelineShaderStageCreateInfo* pVertexSS,
													VkPipelineCreationFeedback* pVertexFB,
													MVKMTLFunction* pVtxFunctions) {
	shaderConfig.options.entryPointStage = spv::ExecutionModelVertex;
	shaderConfig.options.entryPointName = pVertexSS->pName;
	shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.shader_index_buffer_index = _indirectParamsIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.shader_output_buffer_index = _outputBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageVertex];
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
		_needsVertexSwizzleBuffer = funcRslts.needsSwizzleBuffer;
		_needsVertexBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
		_needsVertexDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
		_needsVertexOutputBuffer = funcRslts.needsOutputBuffer;
		markIfUsingPhysicalStorageBufferAddressesCapability(funcRslts, kMVKShaderStageVertex);
	}

	populateDescriptorSetBindingUse(func, pCreateInfo, shaderConfig, kMVKShaderStageVertex);

	// If we need the swizzle buffer and there's no place to put it, we're in serious trouble.
	if (!verifyImplicitBuffer(_needsVertexSwizzleBuffer, _swizzleBufferIndex, kMVKShaderStageVertex, "swizzle")) {
		return false;
	}
	// Ditto buffer size buffer.
	if (!verifyImplicitBuffer(_needsVertexBufferSizeBuffer, _bufferSizeBufferIndex, kMVKShaderStageVertex, "buffer size")) {
		return false;
	}
	// Ditto dynamic offset buffer.
	if (!verifyImplicitBuffer(_needsVertexDynamicOffsetBuffer, _dynamicOffsetBufferIndex, kMVKShaderStageVertex, "dynamic offset")) {
		return false;
	}
	// Ditto captured output buffer.
	if (!verifyImplicitBuffer(_needsVertexOutputBuffer, _outputBufferIndex, kMVKShaderStageVertex, "output")) {
		return false;
	}
	if (!verifyImplicitBuffer(!shaderConfig.shaderInputs.empty(), _indirectParamsIndex, kMVKShaderStageVertex, "index")) {
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addTessCtlShaderToPipeline(MTLComputePipelineDescriptor* plDesc,
													 const VkGraphicsPipelineCreateInfo* pCreateInfo,
													 SPIRVToMSLConversionConfiguration& shaderConfig,
													 SPIRVShaderOutputs& vtxOutputs,
													 SPIRVShaderInputs& teInputs,
													 const VkPipelineShaderStageCreateInfo* pTessCtlSS,
													 VkPipelineCreationFeedback* pTessCtlFB) {
	shaderConfig.options.entryPointStage = spv::ExecutionModelTessellationControl;
	shaderConfig.options.entryPointName = pTessCtlSS->pName;
	shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageTessCtl];
	shaderConfig.options.mslOptions.indirect_params_buffer_index = _indirectParamsIndex.stages[kMVKShaderStageTessCtl];
	shaderConfig.options.mslOptions.shader_input_buffer_index = getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding);
	shaderConfig.options.mslOptions.shader_output_buffer_index = _outputBufferIndex.stages[kMVKShaderStageTessCtl];
	shaderConfig.options.mslOptions.shader_patch_output_buffer_index = _tessCtlPatchOutputBufferIndex;
	shaderConfig.options.mslOptions.shader_tess_factor_buffer_index = _tessCtlLevelBufferIndex;
	shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageTessCtl];
	shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageTessCtl];
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
	_needsTessCtlSwizzleBuffer = funcRslts.needsSwizzleBuffer;
	_needsTessCtlBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsTessCtlDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
	_needsTessCtlOutputBuffer = funcRslts.needsOutputBuffer;
	_needsTessCtlPatchOutputBuffer = funcRslts.needsPatchOutputBuffer;
	_needsTessCtlInputBuffer = funcRslts.needsInputThreadgroupMem;
	markIfUsingPhysicalStorageBufferAddressesCapability(funcRslts, kMVKShaderStageTessCtl);

	populateDescriptorSetBindingUse(func, pCreateInfo, shaderConfig, kMVKShaderStageTessCtl);

	if (!verifyImplicitBuffer(_needsTessCtlSwizzleBuffer, _swizzleBufferIndex, kMVKShaderStageTessCtl, "swizzle")) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsTessCtlBufferSizeBuffer, _bufferSizeBufferIndex, kMVKShaderStageTessCtl, "buffer size")) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsTessCtlDynamicOffsetBuffer, _dynamicOffsetBufferIndex, kMVKShaderStageTessCtl, "dynamic offset")) {
		return false;
	}
	if (!verifyImplicitBuffer(true, _indirectParamsIndex, kMVKShaderStageTessCtl, "indirect parameters")) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsTessCtlOutputBuffer, _outputBufferIndex, kMVKShaderStageTessCtl, "per-vertex output")) {
		return false;
	}
	if (_needsTessCtlPatchOutputBuffer && _tessCtlPatchOutputBufferIndex < _descriptorBufferCounts.stages[kMVKShaderStageTessCtl]) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Tessellation control shader requires per-patch output buffer, but there is no free slot to pass it."));
		return false;
	}
	if (_tessCtlLevelBufferIndex < _descriptorBufferCounts.stages[kMVKShaderStageTessCtl]) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Tessellation control shader requires tessellation level output buffer, but there is no free slot to pass it."));
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addTessEvalShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													  const VkGraphicsPipelineCreateInfo* pCreateInfo,
													  SPIRVToMSLConversionConfiguration& shaderConfig,
													  SPIRVShaderOutputs& tcOutputs,
													  const VkPipelineShaderStageCreateInfo* pTessEvalSS,
													  VkPipelineCreationFeedback* pTessEvalFB,
													  const VkPipelineShaderStageCreateInfo*& pFragmentSS) {
	shaderConfig.options.entryPointStage = spv::ExecutionModelTessellationEvaluation;
	shaderConfig.options.entryPointName = pTessEvalSS->pName;
	shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageTessEval];
	shaderConfig.options.mslOptions.shader_input_buffer_index = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding);
	shaderConfig.options.mslOptions.shader_patch_input_buffer_index = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding);
	shaderConfig.options.mslOptions.shader_tess_factor_buffer_index = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding);
	shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageTessEval];
	shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageTessEval];
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
	_needsTessEvalSwizzleBuffer = funcRslts.needsSwizzleBuffer;
	_needsTessEvalBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsTessEvalDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
	markIfUsingPhysicalStorageBufferAddressesCapability(funcRslts, kMVKShaderStageTessEval);

	populateDescriptorSetBindingUse(func, pCreateInfo, shaderConfig, kMVKShaderStageTessEval);

	if (funcRslts.isRasterizationDisabled) {
		pFragmentSS = nullptr;
	}

	if (!verifyImplicitBuffer(_needsTessEvalSwizzleBuffer, _swizzleBufferIndex, kMVKShaderStageTessEval, "swizzle")) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsTessEvalBufferSizeBuffer, _bufferSizeBufferIndex, kMVKShaderStageTessEval, "buffer size")) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsTessEvalDynamicOffsetBuffer, _dynamicOffsetBufferIndex, kMVKShaderStageTessEval, "dynamic offset")) {
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addFragmentShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													  const VkGraphicsPipelineCreateInfo* pCreateInfo,
													  SPIRVToMSLConversionConfiguration& shaderConfig,
													  SPIRVShaderOutputs& shaderOutputs,
													  const VkPipelineShaderStageCreateInfo* pFragmentSS,
													  VkPipelineCreationFeedback* pFragmentFB) {
	auto& mtlFeats = getMetalFeatures();
	if (pFragmentSS) {
		shaderConfig.options.entryPointStage = spv::ExecutionModelFragment;
		shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageFragment];
		shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageFragment];
		shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageFragment];
		shaderConfig.options.mslOptions.view_mask_buffer_index = _viewRangeBufferIndex.stages[kMVKShaderStageFragment];
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
		_needsFragmentSwizzleBuffer = funcRslts.needsSwizzleBuffer;
		_needsFragmentBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
		_needsFragmentDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
		_needsFragmentViewRangeBuffer = funcRslts.needsViewRangeBuffer;
		markIfUsingPhysicalStorageBufferAddressesCapability(funcRslts, kMVKShaderStageFragment);

		populateDescriptorSetBindingUse(func, pCreateInfo, shaderConfig, kMVKShaderStageFragment);

		if (!verifyImplicitBuffer(_needsFragmentSwizzleBuffer, _swizzleBufferIndex, kMVKShaderStageFragment, "swizzle")) {
			return false;
		}
		if (!verifyImplicitBuffer(_needsFragmentBufferSizeBuffer, _bufferSizeBufferIndex, kMVKShaderStageFragment, "buffer size")) {
			return false;
		}
		if (!verifyImplicitBuffer(_needsFragmentDynamicOffsetBuffer, _dynamicOffsetBufferIndex, kMVKShaderStageFragment, "dynamic offset")) {
			return false;
		}
		if (!verifyImplicitBuffer(_needsFragmentViewRangeBuffer, _viewRangeBufferIndex, kMVKShaderStageFragment, "view range")) {
			return false;
		}
	}
	return true;
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
	bool isVtxStrideStatic = !isDynamicState(VertexStride);
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
			_isVertexInputBindingUsed[vbIdx] = true;
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
	if (pCreateInfo->pInputAssemblyState) {
		plDesc.inputPrimitiveTopologyMVK = isRenderingPoints(pCreateInfo)
												? MTLPrimitiveTopologyClassPoint
												: mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology);
	}

	const VkPipelineRenderingCreateInfo* pRendInfo = getRenderingCreateInfo(pCreateInfo);

	// Color attachments - must ignore bad pColorBlendState pointer if rasterization is disabled or subpass has no color attachments
    uint32_t caCnt = 0;
    if (_isRasterizingColor && pRendInfo && pCreateInfo->pColorBlendState) {
        for (uint32_t caIdx = 0; caIdx < pCreateInfo->pColorBlendState->attachmentCount; caIdx++) {
            const VkPipelineColorBlendAttachmentState* pCA = &pCreateInfo->pColorBlendState->pAttachments[caIdx];

			MTLPixelFormat mtlPixFmt = getPixelFormats()->getMTLPixelFormat(pRendInfo->pColorAttachmentFormats[caIdx]);
			MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[caIdx];
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
					colorDesc.logicOpEnabledMVK = pCreateInfo->pColorBlendState->logicOpEnable;
					colorDesc.logicOpMVK = mvkMTLLogicOperationFromVkLogicOp(pCreateInfo->pColorBlendState->logicOp);
				}
#endif
            }
        }
    }

    // Depth & stencil attachment formats
	MVKPixelFormats* pixFmts = getPixelFormats();

	MTLPixelFormat mtlDepthPixFmt = pixFmts->getMTLPixelFormat(pRendInfo->depthAttachmentFormat);
	if (pixFmts->isDepthFormat(mtlDepthPixFmt)) { plDesc.depthAttachmentPixelFormat = mtlDepthPixFmt; }

	MTLPixelFormat mtlStencilPixFmt = pixFmts->getMTLPixelFormat(pRendInfo->stencilAttachmentFormat);
	if (pixFmts->isStencilFormat(mtlStencilPixFmt)) { plDesc.stencilAttachmentPixelFormat = mtlStencilPixFmt; }

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
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		MVKShaderStage stage = (MVKShaderStage)i;
		_dynamicOffsetBufferIndex.stages[stage] = getImplicitBufferIndex(stage, 0);
		_bufferSizeBufferIndex.stages[stage] = getImplicitBufferIndex(stage, 1);
		_swizzleBufferIndex.stages[stage] = getImplicitBufferIndex(stage, 2);
		_indirectParamsIndex.stages[stage] = getImplicitBufferIndex(stage, 3);
		_outputBufferIndex.stages[stage] = getImplicitBufferIndex(stage, 4);
		if (stage == kMVKShaderStageTessCtl) {
			_tessCtlPatchOutputBufferIndex = getImplicitBufferIndex(stage, 5);
			_tessCtlLevelBufferIndex = getImplicitBufferIndex(stage, 6);
		}
	}
	// Since we currently can't use multiview with tessellation or geometry shaders,
	// to conserve the number of buffer bindings, use the same bindings for the
	// view range buffer as for the indirect paramters buffer.
	_viewRangeBufferIndex = _indirectParamsIndex;

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
	shaderConfig.options.mslOptions.texture_1D_as_2D = getMVKConfig().texture1DAs2D;
	shaderConfig.options.mslOptions.enable_point_size_builtin = isRenderingPoints(pCreateInfo) || reflectData.pointMode;
	shaderConfig.options.mslOptions.enable_point_size_default = shaderConfig.options.mslOptions.enable_point_size_builtin;
	shaderConfig.options.mslOptions.default_point_size = 1.0f; // See VK_KHR_maintenance5
	shaderConfig.options.mslOptions.enable_frag_depth_builtin = pixFmts->isDepthFormat(pixFmts->getMTLPixelFormat(pRendInfo->depthAttachmentFormat));
	shaderConfig.options.mslOptions.enable_frag_stencil_ref_builtin = pixFmts->isStencilFormat(pixFmts->getMTLPixelFormat(pRendInfo->stencilAttachmentFormat));
    shaderConfig.options.shouldFlipVertexY = getMVKConfig().shaderConversionFlipVertexY;
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

bool MVKGraphicsPipeline::isValidVertexBufferIndex(MVKShaderStage stage, uint32_t mtlBufferIndex) {
	return _isVertexInputBindingUsed[mtlBufferIndex] || mtlBufferIndex < _descriptorBufferCounts.stages[stage] || mtlBufferIndex > getImplicitBufferIndex(stage, 0);
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
bool MVKGraphicsPipeline::isRenderingPoints(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	return ((pCreateInfo->pInputAssemblyState &&
			 (pCreateInfo->pInputAssemblyState->topology == VK_PRIMITIVE_TOPOLOGY_POINT_LIST)) ||
			(pCreateInfo->pRasterizationState &&
			 (pCreateInfo->pRasterizationState->polygonMode == VK_POLYGON_MODE_POINT) &&
			 !isDynamicState(PolygonMode)));
}

// We disable rasterization if either static rasterizerDiscard is enabled or the static cull mode dictates it.
bool MVKGraphicsPipeline::isRasterizationDisabled(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	return (pCreateInfo->pRasterizationState &&
			((pCreateInfo->pRasterizationState->rasterizerDiscardEnable && !isDynamicState(RasterizerDiscardEnable)) ||
			 ((pCreateInfo->pRasterizationState->cullMode == VK_CULL_MODE_FRONT_AND_BACK) && !isDynamicState(CullMode) &&
			  pCreateInfo->pInputAssemblyState &&
			  (mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology) == MTLPrimitiveTopologyClassTriangle))));
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

void MVKGraphicsPipeline::markIfUsingPhysicalStorageBufferAddressesCapability(SPIRVToMSLConversionResultInfo& resultsInfo,
																			  MVKShaderStage stage) {
	if (resultsInfo.usesPhysicalStorageBufferAddressesCapability) {
		_stagesUsingPhysicalStorageBufferAddressesCapability.push_back(stage);
	}
}

bool MVKGraphicsPipeline::usesPhysicalStorageBufferAddressesCapability(MVKShaderStage stage) {
	return mvkContains(_stagesUsingPhysicalStorageBufferAddressesCapability, stage);
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

void MVKComputePipeline::encode(MVKCommandEncoder* cmdEncoder, uint32_t) {
	if ( !_hasValidMTLPipelineStates ) { return; }

	[cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setComputePipelineState: _mtlPipelineState];
    cmdEncoder->_mtlThreadgroupSize = _mtlThreadgroupSize;

	cmdEncoder->_computeResourcesState.markOverriddenBufferIndexesDirty();
	cmdEncoder->_computeResourcesState.bindSwizzleBuffer(_swizzleBufferIndex, _needsSwizzleBuffer);
	cmdEncoder->_computeResourcesState.bindBufferSizeBuffer(_bufferSizeBufferIndex, _needsBufferSizeBuffer);
	cmdEncoder->_computeResourcesState.bindDynamicOffsetBuffer(_dynamicOffsetBufferIndex, _needsDynamicOffsetBuffer);
}

MVKComputePipeline::MVKComputePipeline(MVKDevice* device,
									   MVKPipelineCache* pipelineCache,
									   MVKPipeline* parent,
									   const VkComputePipelineCreateInfo* pCreateInfo) :
	MVKPipeline(device, pipelineCache, (MVKPipelineLayout*)pCreateInfo->layout, getPipelineCreateFlags(pCreateInfo), parent) {

	_allowsDispatchBase = mvkAreAllFlagsEnabled(_flags, VK_PIPELINE_CREATE_2_DISPATCH_BASE_BIT);

	if (isUsingMetalArgumentBuffers()) { _descriptorBindingUse.resize(_descriptorSetCount); }

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

	auto& mtlFeats = getMetalFeatures();
	if (_needsSwizzleBuffer && _swizzleBufferIndex.stages[kMVKShaderStageCompute] > mtlFeats.maxPerStageBufferCount) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Compute shader requires swizzle buffer, but there is no free slot to pass it."));
	}
	if (_needsBufferSizeBuffer && _bufferSizeBufferIndex.stages[kMVKShaderStageCompute] > mtlFeats.maxPerStageBufferCount) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Compute shader requires buffer size buffer, but there is no free slot to pass it."));
	}
	if (_needsDynamicOffsetBuffer && _dynamicOffsetBufferIndex.stages[kMVKShaderStageCompute] > mtlFeats.maxPerStageBufferCount) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Compute shader requires dynamic offset buffer, but there is no free slot to pass it."));
	}
	if (_needsDispatchBaseBuffer && _indirectParamsIndex.stages[kMVKShaderStageCompute] > mtlFeats.maxPerStageBufferCount) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Compute shader requires dispatch base buffer, but there is no free slot to pass it."));
	}
}

// Returns a MTLFunction to use when creating the MTLComputePipelineState.
MVKMTLFunction MVKComputePipeline::getMTLFunction(const VkComputePipelineCreateInfo* pCreateInfo,
												  VkPipelineCreationFeedback* pStageFB) {

    const VkPipelineShaderStageCreateInfo* pSS = &pCreateInfo->stage;
    if ( !mvkAreAllFlagsEnabled(pSS->stage, VK_SHADER_STAGE_COMPUTE_BIT) ) { return MVKMTLFunctionNull; }

	_module = getOrCreateShaderModule(_device, pSS, _ownsModule);

	warnIfBufferRobustnessEnabled(this, pSS);

	auto& mtlFeats = getMetalFeatures();
    SPIRVToMSLConversionConfiguration shaderConfig;
	shaderConfig.options.entryPointName = pCreateInfo->stage.pName;
	shaderConfig.options.entryPointStage = spv::ExecutionModelGLCompute;
    shaderConfig.options.mslOptions.msl_version = mtlFeats.mslVersion;
    shaderConfig.options.mslOptions.texel_buffer_texture_width = mtlFeats.maxTextureDimension;
    shaderConfig.options.mslOptions.r32ui_linear_texture_alignment = (uint32_t)_device->getVkFormatTexelBufferAlignment(VK_FORMAT_R32_UINT, this);
	shaderConfig.options.mslOptions.swizzle_texture_samples = _fullImageViewSwizzle && !mtlFeats.nativeTextureSwizzle;
	shaderConfig.options.mslOptions.texture_buffer_native = mtlFeats.textureBuffers;
	shaderConfig.options.mslOptions.dispatch_base = _allowsDispatchBase;
	shaderConfig.options.mslOptions.texture_1D_as_2D = getMVKConfig().texture1DAs2D;
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
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		MVKShaderStage stage = (MVKShaderStage)i;
		_dynamicOffsetBufferIndex.stages[stage] = getImplicitBufferIndex(0);
		_bufferSizeBufferIndex.stages[stage] = getImplicitBufferIndex(1);
		_swizzleBufferIndex.stages[stage] = getImplicitBufferIndex(2);
		_indirectParamsIndex.stages[stage] = getImplicitBufferIndex(3);
	}

    shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageCompute];
    shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageCompute];
	shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageCompute];
    shaderConfig.options.mslOptions.indirect_params_buffer_index = _indirectParamsIndex.stages[kMVKShaderStageCompute];
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
	_needsSwizzleBuffer = funcRslts.needsSwizzleBuffer;
    _needsBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
    _needsDispatchBaseBuffer = funcRslts.needsDispatchBaseBuffer;
	_usesPhysicalStorageBufferAddressesCapability = funcRslts.usesPhysicalStorageBufferAddressesCapability;

	populateDescriptorSetBindingUse(func, pCreateInfo, shaderConfig, kMVKShaderStageCompute);

	return func;
}

uint32_t MVKComputePipeline::getImplicitBufferIndex(uint32_t bufferIndexOffset) {
	return getMetalFeatures().maxPerStageBufferCount - (bufferIndexOffset + 1);
}

bool MVKComputePipeline::usesPhysicalStorageBufferAddressesCapability(MVKShaderStage stage) {
	return _usesPhysicalStorageBufferAddressesCapability;
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
				opt.fixed_subgroup_size,
				opt.enable_point_size_builtin,
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
				opt.argument_buffers_tier,
				opt.force_native_arrays,
				opt.enable_clip_distance_user_varying,
				opt.multi_patch_workgroup,
				opt.raw_buffer_tese_input,
				opt.vertex_for_tessellation,
				opt.arrayed_subpass_input,
				opt.ios_use_simdgroup_functions,
				opt.emulate_subgroups,
				opt.vertex_index_type,
				opt.force_sample_rate_shading,
				opt.manual_helper_invocation_updates,
				opt.check_discarded_frag_stores,
				opt.force_fragment_with_side_effects_execution,
				opt.input_attachment_is_ds_attachment,
				opt.sample_dref_lod_array_as_grad,
				opt.replace_recursive_inputs,
				opt.agx_manual_cube_grad_fixup);
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
				ep.supportsFastMath);
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
	void serialize(Archive & archive, SPIRVToMSLConversionConfiguration& ctx) {
		archive(ctx.options,
				ctx.shaderInputs,
				ctx.shaderOutputs,
				ctx.resourceBindings,
				ctx.discreteDescriptorSets);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVToMSLConversionResultInfo& scr) {
		archive(scr.entryPoint,
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
				scr.usesPhysicalStorageBufferAddressesCapability,
				scr.specializationMacros);
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

