/*
 * MVKPipeline.mm
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "mvk_datatypes.hpp"

#include <cereal/archives/binary.hpp>
#include <cereal/types/string.hpp>
#include <cereal/types/vector.hpp>

using namespace std;
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
	size_t dsCnt = descriptorSets.size;
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
                                          MVKArrayRef<VkWriteDescriptorSet> descriptorWrites,
                                          uint32_t set) {
	if (!cmdEncoder) { clearConfigurationResult(); }
	MVKDescriptorSetLayout* dsl = _descriptorSetLayouts[set];
	dsl->pushDescriptorSet(cmdEncoder, descriptorWrites, _dslMTLResourceIndexOffsets[set]);
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
	// Use VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT descriptor type as compatible with push constants in Metal.
	for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
		if (stageUsesPushConstants((MVKShaderStage)stage)) {
			mvkPopulateShaderConversionConfig(shaderConfig,
											  _pushConstantsMTLResourceIndexes.stages[stage],
											  MVKShaderStage(stage),
											  kPushConstDescSet,
											  kPushConstBinding,
											  1,
											  VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT,
											  nullptr);
		}
	}

    // Add resource bindings defined in the descriptor set layouts
	uint32_t dslCnt = getDescriptorSetCount();
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

MVKPipelineLayout::MVKPipelineLayout(MVKDevice* device,
                                     const VkPipelineLayoutCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {

	// For pipeline layout compatibility (“compatible for set N”),
	// consume the Metal resource indexes in this order:
	//   - Fixed count of argument buffers for descriptor sets (if using Metal argument buffers).
	//   - Push constants
	//   - Descriptor set content

	// If we are using Metal argument buffers, consume a fixed number
	// of buffer indexes for the Metal argument buffers themselves.
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
	uint32_t dslCnt = pCreateInfo->setLayoutCount;
	_descriptorSetLayouts.reserve(dslCnt);
	for (uint32_t i = 0; i < dslCnt; i++) {
		MVKDescriptorSetLayout* pDescSetLayout = (MVKDescriptorSetLayout*)pCreateInfo->pSetLayouts[i];
		pDescSetLayout->retain();
		_descriptorSetLayouts.push_back(pDescSetLayout);

		MVKShaderResourceBinding adjstdDSLRezOfsts = _mtlResourceCounts;
		MVKShaderResourceBinding adjstdDSLRezCnts = pDescSetLayout->_mtlResourceCounts;
		if (pDescSetLayout->isUsingMetalArgumentBuffer()) {
			adjstdDSLRezOfsts.clearArgumentBufferResources();
			adjstdDSLRezCnts.clearArgumentBufferResources();
		}
		_dslMTLResourceIndexOffsets.push_back(adjstdDSLRezOfsts);
		_mtlResourceCounts += adjstdDSLRezCnts;
	}
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

// For each descriptor set, populate the descriptor bindings used by the shader for this stage,
// and if Metal argument encoders must be dedicated to a pipeline stage, create the encoder here.
template<typename CreateInfo>
void MVKPipeline::addMTLArgumentEncoders(MVKMTLFunction& mvkMTLFunc,
										 const CreateInfo* pCreateInfo,
										 SPIRVToMSLConversionConfiguration& shaderConfig,
										 MVKShaderStage stage) {
	if ( !isUsingMetalArgumentBuffers() ) { return; }

	bool needMTLArgEnc = isUsingPipelineStageMetalArgumentBuffers();
	auto mtlFunc = mvkMTLFunc.getMTLFunction();
	for (uint32_t dsIdx = 0; dsIdx < _descriptorSetCount; dsIdx++) {
		auto* dsLayout = ((MVKPipelineLayout*)pCreateInfo->layout)->getDescriptorSetLayout(dsIdx);
		bool descSetIsUsed = dsLayout->populateBindingUse(getDescriptorBindingUse(dsIdx, stage), shaderConfig, stage, dsIdx);
		if (descSetIsUsed && needMTLArgEnc) {
			getMTLArgumentEncoder(dsIdx, stage).init([mtlFunc newArgumentEncoderWithBufferIndex: dsIdx]);
		}
	}
}

MVKPipeline::MVKPipeline(MVKDevice* device, MVKPipelineCache* pipelineCache, MVKPipelineLayout* layout, MVKPipeline* parent) :
	MVKVulkanAPIDeviceObject(device),
	_pipelineCache(pipelineCache),
	_fullImageViewSwizzle(mvkConfig().fullImageViewSwizzle),
	_descriptorSetCount(layout->getDescriptorSetCount()) {

		// Establish descriptor counts and push constants use.
		for (uint32_t stage = kMVKShaderStageVertex; stage < kMVKShaderStageCount; stage++) {
			_descriptorBufferCounts.stages[stage] = layout->_mtlResourceCounts.stages[stage].bufferIndex;
			_pushConstantsBufferIndex.stages[stage] = layout->_pushConstantsMTLResourceIndexes.stages[stage].bufferIndex;
			_stageUsesPushConstants[stage] = layout->stageUsesPushConstants((MVKShaderStage)stage);
		}
	}


#pragma mark -
#pragma mark MVKGraphicsPipeline

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
			cmdEncoder->_stencilReferenceValueState.setReferenceValues(_depthStencilInfo);

            // Rasterization
            cmdEncoder->_blendColorState.setBlendColor(_blendConstants[0], _blendConstants[1],
                                                       _blendConstants[2], _blendConstants[3], false);
            cmdEncoder->_depthBiasState.setDepthBias(_rasterInfo);
            cmdEncoder->_viewportState.setViewports(_viewports.contents(), 0, false);
            cmdEncoder->_scissorState.setScissors(_scissors.contents(), 0, false);
            cmdEncoder->_mtlPrimitiveType = _mtlPrimitiveType;

            [mtlCmdEnc setCullMode: _mtlCullMode];
            [mtlCmdEnc setFrontFacingWinding: _mtlFrontWinding];
            [mtlCmdEnc setTriangleFillMode: _mtlFillMode];

            if (_device->_enabledFeatures.depthClamp) {
                [mtlCmdEnc setDepthClipMode: _mtlDepthClipMode];
            }

            break;
    }
    cmdEncoder->_graphicsResourcesState.bindSwizzleBuffer(_swizzleBufferIndex, _needsVertexSwizzleBuffer, _needsTessCtlSwizzleBuffer, _needsTessEvalSwizzleBuffer, _needsFragmentSwizzleBuffer);
    cmdEncoder->_graphicsResourcesState.bindBufferSizeBuffer(_bufferSizeBufferIndex, _needsVertexBufferSizeBuffer, _needsTessCtlBufferSizeBuffer, _needsTessEvalBufferSizeBuffer, _needsFragmentBufferSizeBuffer);
	cmdEncoder->_graphicsResourcesState.bindDynamicOffsetBuffer(_dynamicOffsetBufferIndex, _needsVertexDynamicOffsetBuffer, _needsTessCtlDynamicOffsetBuffer, _needsTessEvalDynamicOffsetBuffer, _needsFragmentDynamicOffsetBuffer);
    cmdEncoder->_graphicsResourcesState.bindViewRangeBuffer(_viewRangeBufferIndex, _needsVertexViewRangeBuffer, _needsFragmentViewRangeBuffer);
}

bool MVKGraphicsPipeline::supportsDynamicState(VkDynamicState state) {
	for (auto& ds : _dynamicState) {
		if (state == ds) {
			// Some dynamic states have other restrictions
			switch (state) {
				case VK_DYNAMIC_STATE_DEPTH_BIAS:
					return _rasterInfo.depthBiasEnable;
				default:
					return true;
			}
		}
	}
	return false;
}

static const char vtxCompilerType[] = "Vertex stage pipeline for tessellation";

id<MTLComputePipelineState> MVKGraphicsPipeline::getTessVertexStageState() {
    MTLComputePipelineDescriptor* plDesc = [_mtlTessVertexStageDesc copy];  // temp retain a copy to be thread-safe.
    plDesc.computeFunction = _mtlTessVertexFunctions[0];
    id<MTLComputePipelineState> plState = getOrCompilePipeline(plDesc, _mtlTessVertexStageState, vtxCompilerType);
    [plDesc release];                                                       // temp release
    return plState;
}

id<MTLComputePipelineState> MVKGraphicsPipeline::getTessVertexStageIndex16State() {
    MTLComputePipelineDescriptor* plDesc = [_mtlTessVertexStageDesc copy];  // temp retain a copy to be thread-safe.
    plDesc.computeFunction = _mtlTessVertexFunctions[1];
    plDesc.stageInputDescriptor.indexType = MTLIndexTypeUInt16;
    for (uint32_t i = 0; i < 31; i++) {
		MTLBufferLayoutDescriptor* blDesc = plDesc.stageInputDescriptor.layouts[i];
        if (blDesc.stepFunction == MTLStepFunctionThreadPositionInGridX) {
                blDesc.stepFunction = MTLStepFunctionThreadPositionInGridXIndexed;
        }
    }
    id<MTLComputePipelineState> plState = getOrCompilePipeline(plDesc, _mtlTessVertexStageIndex16State, vtxCompilerType);
    [plDesc release];                                                       // temp release
    return plState;
}

id<MTLComputePipelineState> MVKGraphicsPipeline::getTessVertexStageIndex32State() {
    MTLComputePipelineDescriptor* plDesc = [_mtlTessVertexStageDesc copy];  // temp retain a copy to be thread-safe.
    plDesc.computeFunction = _mtlTessVertexFunctions[2];
    plDesc.stageInputDescriptor.indexType = MTLIndexTypeUInt32;
    for (uint32_t i = 0; i < 31; i++) {
		MTLBufferLayoutDescriptor* blDesc = plDesc.stageInputDescriptor.layouts[i];
        if (blDesc.stepFunction == MTLStepFunctionThreadPositionInGridX) {
                blDesc.stepFunction = MTLStepFunctionThreadPositionInGridXIndexed;
        }
    }
    id<MTLComputePipelineState> plState = getOrCompilePipeline(plDesc, _mtlTessVertexStageIndex32State, vtxCompilerType);
    [plDesc release];                                                       // temp release
    return plState;
}


#pragma mark Construction

// Extracts and returns a VkPipelineRenderingCreateInfo from the renderPass or pNext chain of pCreateInfo, or returns null if not found
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
	return nullptr;
}

MVKGraphicsPipeline::MVKGraphicsPipeline(MVKDevice* device,
										 MVKPipelineCache* pipelineCache,
										 MVKPipeline* parent,
										 const VkGraphicsPipelineCreateInfo* pCreateInfo) :
	MVKPipeline(device, pipelineCache, (MVKPipelineLayout*)pCreateInfo->layout, parent) {

	// Determine rasterization early, as various other structs are validated and interpreted in this context.
	const VkPipelineRenderingCreateInfo* pRendInfo = getRenderingCreateInfo(pCreateInfo);
	_isRasterizing = !isRasterizationDisabled(pCreateInfo);
	_isRasterizingColor = _isRasterizing && mvkHasColorAttachments(pRendInfo);
	_isRasterizingDepthStencil = _isRasterizing && mvkGetDepthStencilFormat(pRendInfo) != VK_FORMAT_UNDEFINED;

	// Get the tessellation shaders, if present. Do this now, because we need to extract
	// reflection data from them that informs everything else.
	for (uint32_t i = 0; i < pCreateInfo->stageCount; i++) {
		const auto* pSS = &pCreateInfo->pStages[i];
		if (pSS->stage == VK_SHADER_STAGE_VERTEX_BIT) {
			_pVertexSS = pSS;
		} else if (pSS->stage == VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT) {
			_pTessCtlSS = pSS;
		} else if (pSS->stage == VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT) {
			_pTessEvalSS = pSS;
		} else if (pSS->stage == VK_SHADER_STAGE_FRAGMENT_BIT) {
			_pFragmentSS = pSS;
		}
	}

	// Get the tessellation parameters from the shaders.
	SPIRVTessReflectionData reflectData;
	std::string reflectErrorLog;
	if (_pTessCtlSS && _pTessEvalSS) {
		if (!getTessReflectionData(((MVKShaderModule*)_pTessCtlSS->module)->getSPIRV(), _pTessCtlSS->pName, ((MVKShaderModule*)_pTessEvalSS->module)->getSPIRV(), _pTessEvalSS->pName, reflectData, reflectErrorLog) ) {
			setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to reflect tessellation shaders: %s", reflectErrorLog.c_str()));
			return;
		}
		// Unfortunately, we can't support line tessellation at this time.
		if (reflectData.patchKind == spv::ExecutionModeIsolines) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Metal does not support isoline tessellation."));
			return;
		}
	}

	// Track dynamic state
	const VkPipelineDynamicStateCreateInfo* pDS = pCreateInfo->pDynamicState;
	if (pDS) {
		for (uint32_t i = 0; i < pDS->dynamicStateCount; i++) {
			_dynamicState.push_back(pDS->pDynamicStates[i]);
		}
	}

	// Blending - must ignore allowed bad pColorBlendState pointer if rasterization disabled or no color attachments
	if (_isRasterizingColor && pCreateInfo->pColorBlendState) {
		memcpy(&_blendConstants, &pCreateInfo->pColorBlendState->blendConstants, sizeof(_blendConstants));
	}

	// Topology
	_mtlPrimitiveType = MTLPrimitiveTypePoint;
	if (pCreateInfo->pInputAssemblyState && !isRenderingPoints(pCreateInfo)) {
		_mtlPrimitiveType = mvkMTLPrimitiveTypeFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology);
		// Explicitly fail creation with triangle fan topology.
		if (pCreateInfo->pInputAssemblyState->topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
			setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "Metal does not support triangle fans."));
			return;
		}
	}

	// Tessellation - must ignore allowed bad pTessellationState pointer if not tess pipeline
	_outputControlPointCount = reflectData.numControlPoints;
	mvkSetOrClear(&_tessInfo, (_pTessCtlSS && _pTessEvalSS) ? pCreateInfo->pTessellationState : nullptr);

	// Rasterization
	_mtlCullMode = MTLCullModeNone;
	_mtlFrontWinding = MTLWindingCounterClockwise;
	_mtlFillMode = MTLTriangleFillModeFill;
	_mtlDepthClipMode = MTLDepthClipModeClip;
	bool hasRasterInfo = mvkSetOrClear(&_rasterInfo, pCreateInfo->pRasterizationState);
	if (hasRasterInfo) {
		_mtlCullMode = mvkMTLCullModeFromVkCullModeFlags(_rasterInfo.cullMode);
		_mtlFrontWinding = mvkMTLWindingFromVkFrontFace(_rasterInfo.frontFace);
		_mtlFillMode = mvkMTLTriangleFillModeFromVkPolygonMode(_rasterInfo.polygonMode);
		if (_rasterInfo.depthClampEnable) {
			if (_device->_enabledFeatures.depthClamp) {
				_mtlDepthClipMode = MTLDepthClipModeClamp;
			} else {
				setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT, "This device does not support depth clamping."));
			}
		}
	}

	// Must run after _isRasterizing and _dynamicState are populated
	initCustomSamplePositions(pCreateInfo);

	// Render pipeline state
	initMTLRenderPipelineState(pCreateInfo, reflectData);

	// Depth stencil content - clearing will disable depth and stencil testing
	// Must ignore allowed bad pDepthStencilState pointer if rasterization disabled or no depth attachment
	mvkSetOrClear(&_depthStencilInfo, _isRasterizingDepthStencil ? pCreateInfo->pDepthStencilState : nullptr);

	// Viewports and scissors - must ignore allowed bad pViewportState pointer if rasterization is disabled
	auto pVPState = _isRasterizing ? pCreateInfo->pViewportState : nullptr;
	if (pVPState) {
		uint32_t vpCnt = pVPState->viewportCount;
		_viewports.reserve(vpCnt);
		for (uint32_t vpIdx = 0; vpIdx < vpCnt; vpIdx++) {
			// If viewport is dyanamic, we still add a dummy so that the count will be tracked.
			VkViewport vp;
			if ( !supportsDynamicState(VK_DYNAMIC_STATE_VIEWPORT) ) { vp = pVPState->pViewports[vpIdx]; }
			_viewports.push_back(vp);
		}

		uint32_t sCnt = pVPState->scissorCount;
		_scissors.reserve(sCnt);
		for (uint32_t sIdx = 0; sIdx < sCnt; sIdx++) {
			// If scissor is dyanamic, we still add a dummy so that the count will be tracked.
			VkRect2D sc;
			if ( !supportsDynamicState(VK_DYNAMIC_STATE_SCISSOR) ) { sc = pVPState->pScissors[sIdx]; }
			_scissors.push_back(sc);
		}
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
void MVKGraphicsPipeline::initCustomSamplePositions(const VkGraphicsPipelineCreateInfo* pCreateInfo) {

	// Must ignore allowed bad pMultisampleState pointer if rasterization disabled
	if ( !(_isRasterizing && pCreateInfo->pMultisampleState) ) { return; }

	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pMultisampleState->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_PIPELINE_SAMPLE_LOCATIONS_STATE_CREATE_INFO_EXT: {
				auto* pSampLocnsCreateInfo = (VkPipelineSampleLocationsStateCreateInfoEXT*)next;
				_isUsingCustomSamplePositions = pSampLocnsCreateInfo->sampleLocationsEnable;
				if (_isUsingCustomSamplePositions && !supportsDynamicState(VK_DYNAMIC_STATE_SAMPLE_LOCATIONS_EXT)) {
					for (uint32_t slIdx = 0; slIdx < pSampLocnsCreateInfo->sampleLocationsInfo.sampleLocationsCount; slIdx++) {
						auto& sl = pSampLocnsCreateInfo->sampleLocationsInfo.pSampleLocations[slIdx];
						_customSamplePositions.push_back(MTLSamplePositionMake(sl.x, sl.y));
					}
				}
				break;
			}
			default:
				break;
		}
	}
}

// Constructs the underlying Metal render pipeline.
void MVKGraphicsPipeline::initMTLRenderPipelineState(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData) {
	_mtlTessVertexStageState = nil;
	_mtlTessVertexStageIndex16State = nil;
	_mtlTessVertexStageIndex32State = nil;
	_mtlTessControlStageState = nil;
	_mtlPipelineState = nil;
	_mtlTessVertexStageDesc = nil;
	for (uint32_t i = 0; i < 3; i++) { _mtlTessVertexFunctions[i] = nil; }

	if (isUsingMetalArgumentBuffers()) { _descriptorBindingUse.resize(_descriptorSetCount); }
	if (isUsingPipelineStageMetalArgumentBuffers()) { _mtlArgumentEncoders.resize(_descriptorSetCount); }

	if (!isTessellationPipeline()) {
		MTLRenderPipelineDescriptor* plDesc = newMTLRenderPipelineDescriptor(pCreateInfo, reflectData);	// temp retain
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
		}
		[plDesc release];																				// temp release
	} else {
		// In this case, we need to create three render pipelines. But, the way Metal handles
		// index buffers for compute stage-in means we have to defer creation of stage 1 until
		// draw time. In the meantime, we'll create and retain a descriptor for it.
		SPIRVToMSLConversionConfiguration shaderConfig;
		initShaderConversionConfig(shaderConfig, pCreateInfo, reflectData);

		_mtlTessVertexStageDesc = newMTLTessVertexStageDescriptor(pCreateInfo, reflectData, shaderConfig);					// retained
		MTLComputePipelineDescriptor* tcPLDesc = newMTLTessControlStageDescriptor(pCreateInfo, reflectData, shaderConfig);	// temp retained
		MTLRenderPipelineDescriptor* rastPLDesc = newMTLTessRasterStageDescriptor(pCreateInfo, reflectData, shaderConfig);	// temp retained
		if (_mtlTessVertexStageDesc && tcPLDesc && rastPLDesc) {
			if (getOrCompilePipeline(tcPLDesc, _mtlTessControlStageState, "Tessellation control")) {
				getOrCompilePipeline(rastPLDesc, _mtlPipelineState);
			}
		}
		[tcPLDesc release];		// temp release
		[rastPLDesc release];	// temp release
	}
}

// Returns a retained MTLRenderPipelineDescriptor constructed from this instance, or nil if an error occurs.
// It is the responsibility of the caller to release the returned descriptor.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::newMTLRenderPipelineDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																				 const SPIRVTessReflectionData& reflectData) {
	SPIRVToMSLConversionConfiguration shaderConfig;
	initShaderConversionConfig(shaderConfig, pCreateInfo, reflectData);

	MTLRenderPipelineDescriptor* plDesc = [MTLRenderPipelineDescriptor new];	// retained

	SPIRVShaderOutputs vtxOutputs;
	std::string errorLog;
	if (!getShaderOutputs(((MVKShaderModule*)_pVertexSS->module)->getSPIRV(), spv::ExecutionModelVertex, _pVertexSS->pName, vtxOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get vertex outputs: %s", errorLog.c_str()));
		return nil;
	}

	// Add shader stages. Compile vertex shader before others just in case conversion changes anything...like rasterizaion disable.
	if (!addVertexShaderToPipeline(plDesc, pCreateInfo, shaderConfig)) { return nil; }

	// Vertex input
	// This needs to happen before compiling the fragment shader, or we'll lose information on vertex attributes.
	if (!addVertexInputToPipeline(plDesc.vertexDescriptor, pCreateInfo->pVertexInputState, shaderConfig)) { return nil; }

	// Fragment shader - only add if rasterization is enabled
	if (!addFragmentShaderToPipeline(plDesc, pCreateInfo, shaderConfig, vtxOutputs)) { return nil; }

	// Output
	addFragmentOutputToPipeline(plDesc, pCreateInfo);

	// Metal does not allow the name of the pipeline to be changed after it has been created,
	// and we need to create the Metal pipeline immediately to provide error feedback to app.
	// The best we can do at this point is set the pipeline name from the layout.
	setLabelIfNotNil(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

	return plDesc;
}

// Returns a retained MTLComputePipelineDescriptor for the vertex stage of a tessellated draw constructed from this instance, or nil if an error occurs.
// It is the responsibility of the caller to release the returned descriptor.
MTLComputePipelineDescriptor* MVKGraphicsPipeline::newMTLTessVertexStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																				  const SPIRVTessReflectionData& reflectData,
																				  SPIRVToMSLConversionConfiguration& shaderConfig) {
	MTLComputePipelineDescriptor* plDesc = [MTLComputePipelineDescriptor new];	// retained

	// Add shader stages.
	if (!addVertexShaderToPipeline(plDesc, pCreateInfo, shaderConfig)) { return nil; }

	// Vertex input
	plDesc.stageInputDescriptor = [MTLStageInputOutputDescriptor stageInputOutputDescriptor];
	if (!addVertexInputToPipeline(plDesc.stageInputDescriptor, pCreateInfo->pVertexInputState, shaderConfig)) { return nil; }
	plDesc.stageInputDescriptor.indexBufferIndex = _indirectParamsIndex.stages[kMVKShaderStageVertex];

	plDesc.threadGroupSizeIsMultipleOfThreadExecutionWidth = YES;

	// Metal does not allow the name of the pipeline to be changed after it has been created,
	// and we need to create the Metal pipeline immediately to provide error feedback to app.
	// The best we can do at this point is set the pipeline name from the layout.
	setLabelIfNotNil(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

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
																					SPIRVToMSLConversionConfiguration& shaderConfig) {
	MTLComputePipelineDescriptor* plDesc = [MTLComputePipelineDescriptor new];		// retained

	SPIRVShaderOutputs vtxOutputs;
	std::string errorLog;
	if (!getShaderOutputs(((MVKShaderModule*)_pVertexSS->module)->getSPIRV(), spv::ExecutionModelVertex, _pVertexSS->pName, vtxOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get vertex outputs: %s", errorLog.c_str()));
		return nil;
	}

	// Add shader stages.
	if (!addTessCtlShaderToPipeline(plDesc, pCreateInfo, shaderConfig, vtxOutputs)) {
		[plDesc release];
		return nil;
	}

	// Metal does not allow the name of the pipeline to be changed after it has been created,
	// and we need to create the Metal pipeline immediately to provide error feedback to app.
	// The best we can do at this point is set the pipeline name from the layout.
	setLabelIfNotNil(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

	return plDesc;
}

// Returns a retained MTLRenderPipelineDescriptor for the last stage of a tessellated draw constructed from this instance, or nil if an error occurs.
// It is the responsibility of the caller to release the returned descriptor.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::newMTLTessRasterStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																				  const SPIRVTessReflectionData& reflectData,
																				  SPIRVToMSLConversionConfiguration& shaderConfig) {
	MTLRenderPipelineDescriptor* plDesc = [MTLRenderPipelineDescriptor new];	// retained

	SPIRVShaderOutputs tcOutputs, teOutputs;
	std::string errorLog;
	if (!getShaderOutputs(((MVKShaderModule*)_pTessCtlSS->module)->getSPIRV(), spv::ExecutionModelTessellationControl, _pTessCtlSS->pName, tcOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get tessellation control outputs: %s", errorLog.c_str()));
		return nil;
	}
	if (!getShaderOutputs(((MVKShaderModule*)_pTessEvalSS->module)->getSPIRV(), spv::ExecutionModelTessellationEvaluation, _pTessEvalSS->pName, teOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get tessellation evaluation outputs: %s", errorLog.c_str()));
		return nil;
	}

	// Add shader stages. Compile tessellation evaluation shader before others just in case conversion changes anything...like rasterizaion disable.
	if (!addTessEvalShaderToPipeline(plDesc, pCreateInfo, shaderConfig, tcOutputs)) {
		[plDesc release];
		return nil;
	}

	// Tessellation evaluation stage input
	// This needs to happen before compiling the fragment shader, or we'll lose information on shader inputs.
	plDesc.vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
	uint32_t offset = 0, patchOffset = 0, outerLoc = -1, innerLoc = -1;
	bool usedPerVertex = false, usedPerPatch = false;
	const SPIRVShaderOutput* firstVertex = nullptr, * firstPatch = nullptr;
	for (const SPIRVShaderOutput& output : tcOutputs) {
		if (output.builtin == spv::BuiltInPointSize && !reflectData.pointMode) { continue; }
		if (!shaderConfig.isShaderInputLocationUsed(output.location)) {
			if (output.perPatch && !(output.builtin == spv::BuiltInTessLevelOuter || output.builtin == spv::BuiltInTessLevelInner) ) {
				if (!firstPatch) { firstPatch = &output; }
				patchOffset += getShaderOutputSize(output);
			} else if (!output.perPatch) {
				if (!firstVertex) { firstVertex = &output; }
				offset += getShaderOutputSize(output);
			}
			continue;
		}
		if (output.perPatch && (output.builtin == spv::BuiltInTessLevelOuter || output.builtin == spv::BuiltInTessLevelInner) ) {
			uint32_t location = output.location;
			if (output.builtin == spv::BuiltInTessLevelOuter) {
				if (outerLoc != (uint32_t)(-1)) { continue; }
				if (innerLoc != (uint32_t)(-1)) {
					// For triangle tessellation, we use a single attribute. Don't add it more than once.
					if (reflectData.patchKind == spv::ExecutionModeTriangles) { continue; }
					// getShaderOutputs() assigned individual elements their own locations. Try to reduce the gap.
					location = innerLoc + 1;
				}
				outerLoc = location;
			} else {
				if (innerLoc != (uint32_t)(-1)) { continue; }
				if (outerLoc != (uint32_t)(-1)) {
					if (reflectData.patchKind == spv::ExecutionModeTriangles) { continue; }
					location = outerLoc + 1;
				}
				innerLoc = location;
			}
			plDesc.vertexDescriptor.attributes[location].bufferIndex = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding);
			if (reflectData.patchKind == spv::ExecutionModeTriangles || output.builtin == spv::BuiltInTessLevelOuter) {
				plDesc.vertexDescriptor.attributes[location].offset = 0;
				plDesc.vertexDescriptor.attributes[location].format = MTLVertexFormatHalf4;	// FIXME Should use Float4
			} else {
				plDesc.vertexDescriptor.attributes[location].offset = 8;
				plDesc.vertexDescriptor.attributes[location].format = MTLVertexFormatHalf2;	// FIXME Should use Float2
			}
		} else if (output.perPatch) {
			patchOffset = (uint32_t)mvkAlignByteCount(patchOffset, getShaderOutputAlignment(output));
			plDesc.vertexDescriptor.attributes[output.location].bufferIndex = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding);
			plDesc.vertexDescriptor.attributes[output.location].format = getPixelFormats()->getMTLVertexFormat(mvkFormatFromOutput(output));
			plDesc.vertexDescriptor.attributes[output.location].offset = patchOffset;
			patchOffset += getShaderOutputSize(output);
			if (!firstPatch) { firstPatch = &output; }
			usedPerPatch = true;
		} else {
			offset = (uint32_t)mvkAlignByteCount(offset, getShaderOutputAlignment(output));
			plDesc.vertexDescriptor.attributes[output.location].bufferIndex = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding);
			plDesc.vertexDescriptor.attributes[output.location].format = getPixelFormats()->getMTLVertexFormat(mvkFormatFromOutput(output));
			plDesc.vertexDescriptor.attributes[output.location].offset = offset;
			offset += getShaderOutputSize(output);
			if (!firstVertex) { firstVertex = &output; }
			usedPerVertex = true;
		}
	}
	if (usedPerVertex) {
		uint32_t mtlVBIdx = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding);
		plDesc.vertexDescriptor.layouts[mtlVBIdx].stepFunction = MTLVertexStepFunctionPerPatchControlPoint;
		plDesc.vertexDescriptor.layouts[mtlVBIdx].stride = mvkAlignByteCount(offset, getShaderOutputAlignment(*firstVertex));
	}
	if (usedPerPatch) {
		uint32_t mtlVBIdx = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding);
		plDesc.vertexDescriptor.layouts[mtlVBIdx].stepFunction = MTLVertexStepFunctionPerPatch;
		plDesc.vertexDescriptor.layouts[mtlVBIdx].stride = mvkAlignByteCount(patchOffset, getShaderOutputAlignment(*firstPatch));
	}
	if (outerLoc != (uint32_t)(-1) || innerLoc != (uint32_t)(-1)) {
		uint32_t mtlVBIdx = getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding);
		plDesc.vertexDescriptor.layouts[mtlVBIdx].stepFunction = MTLVertexStepFunctionPerPatch;
		plDesc.vertexDescriptor.layouts[mtlVBIdx].stride =
			reflectData.patchKind == spv::ExecutionModeTriangles ? sizeof(MTLTriangleTessellationFactorsHalf) :
																   sizeof(MTLQuadTessellationFactorsHalf);
	}

	// Fragment shader - only add if rasterization is enabled
	if (!addFragmentShaderToPipeline(plDesc, pCreateInfo, shaderConfig, teOutputs)) {
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
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "%s shader requires %s buffer, but there is no free slot to pass it.", stageNames[stage], name));
		return false;
	}
	return true;
}

// Adds a vertex shader to the pipeline description.
bool MVKGraphicsPipeline::addVertexShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													const VkGraphicsPipelineCreateInfo* pCreateInfo,
													SPIRVToMSLConversionConfiguration& shaderConfig) {
	shaderConfig.options.entryPointStage = spv::ExecutionModelVertex;
	shaderConfig.options.entryPointName = _pVertexSS->pName;
	shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.indirect_params_buffer_index = _indirectParamsIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.shader_output_buffer_index = _outputBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.view_mask_buffer_index = _viewRangeBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.capture_output_to_buffer = false;
	shaderConfig.options.mslOptions.disable_rasterization = !_isRasterizing;
    addVertexInputToShaderConversionConfig(shaderConfig, pCreateInfo);

	MVKMTLFunction func = ((MVKShaderModule*)_pVertexSS->module)->getMTLFunction(&shaderConfig, _pVertexSS->pSpecializationInfo, _pipelineCache);
	id<MTLFunction> mtlFunc = func.getMTLFunction();
	if ( !mtlFunc ) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Vertex shader function could not be compiled into pipeline. See previous logged error."));
		return false;
	}
	plDesc.vertexFunction = mtlFunc;

	auto& funcRslts = func.shaderConversionResults;
	plDesc.rasterizationEnabled = !funcRslts.isRasterizationDisabled;
	_needsVertexSwizzleBuffer = funcRslts.needsSwizzleBuffer;
	_needsVertexBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsVertexDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
	_needsVertexViewRangeBuffer = funcRslts.needsViewRangeBuffer;
	_needsVertexOutputBuffer = funcRslts.needsOutputBuffer;

	addMTLArgumentEncoders(func, pCreateInfo, shaderConfig, kMVKShaderStageVertex);

	if (funcRslts.isRasterizationDisabled) {
		_pFragmentSS = nullptr;
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
													SPIRVToMSLConversionConfiguration& shaderConfig) {
	shaderConfig.options.entryPointStage = spv::ExecutionModelVertex;
	shaderConfig.options.entryPointName = _pVertexSS->pName;
	shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.shader_index_buffer_index = _indirectParamsIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.shader_output_buffer_index = _outputBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageVertex];
	shaderConfig.options.mslOptions.capture_output_to_buffer = true;
	shaderConfig.options.mslOptions.vertex_for_tessellation = true;
	shaderConfig.options.mslOptions.disable_rasterization = true;
    addVertexInputToShaderConversionConfig(shaderConfig, pCreateInfo);

	static const CompilerMSL::Options::IndexType indexTypes[] = {
		CompilerMSL::Options::IndexType::None,
		CompilerMSL::Options::IndexType::UInt16,
		CompilerMSL::Options::IndexType::UInt32,
	};
	// We need to compile this function three times, with no indexing, 16-bit indices, and 32-bit indices.
	MVKMTLFunction func;
	for (uint32_t i = 0; i < sizeof(indexTypes)/sizeof(indexTypes[0]); i++) {
		shaderConfig.options.mslOptions.vertex_index_type = indexTypes[i];
		func = ((MVKShaderModule*)_pVertexSS->module)->getMTLFunction(&shaderConfig, _pVertexSS->pSpecializationInfo, _pipelineCache);
		id<MTLFunction> mtlFunc = func.getMTLFunction();
		if ( !mtlFunc ) {
			setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Vertex shader function could not be compiled into pipeline. See previous logged error."));
			return false;
		}
		_mtlTessVertexFunctions[i] = [mtlFunc retain];

		auto& funcRslts = func.shaderConversionResults;
		_needsVertexSwizzleBuffer = funcRslts.needsSwizzleBuffer;
		_needsVertexBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
		_needsVertexDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
		_needsVertexOutputBuffer = funcRslts.needsOutputBuffer;
	}

	addMTLArgumentEncoders(func, pCreateInfo, shaderConfig, kMVKShaderStageVertex);

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
													 SPIRVShaderOutputs& vtxOutputs) {
	shaderConfig.options.entryPointStage = spv::ExecutionModelTessellationControl;
	shaderConfig.options.entryPointName = _pTessCtlSS->pName;
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
	shaderConfig.options.mslOptions.fixed_subgroup_size = mvkIsAnyFlagEnabled(_pTessCtlSS->flags, VK_PIPELINE_SHADER_STAGE_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT_EXT) ? 0 : _device->_pMetalFeatures->maxSubgroupSize;
	addPrevStageOutputToShaderConversionConfig(shaderConfig, vtxOutputs);

	MVKMTLFunction func = ((MVKShaderModule*)_pTessCtlSS->module)->getMTLFunction(&shaderConfig, _pTessCtlSS->pSpecializationInfo, _pipelineCache);
	id<MTLFunction> mtlFunc = func.getMTLFunction();
	if ( !mtlFunc ) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Tessellation control shader function could not be compiled into pipeline. See previous logged error."));
		return false;
	}
	plDesc.computeFunction = mtlFunc;

	auto& funcRslts = func.shaderConversionResults;
	_needsTessCtlSwizzleBuffer = funcRslts.needsSwizzleBuffer;
	_needsTessCtlBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsTessCtlDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
	_needsTessCtlOutputBuffer = funcRslts.needsOutputBuffer;
	_needsTessCtlPatchOutputBuffer = funcRslts.needsPatchOutputBuffer;
	_needsTessCtlInputBuffer = funcRslts.needsInputThreadgroupMem;

	addMTLArgumentEncoders(func, pCreateInfo, shaderConfig, kMVKShaderStageTessCtl);

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
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Tessellation control shader requires per-patch output buffer, but there is no free slot to pass it."));
		return false;
	}
	if (_tessCtlLevelBufferIndex < _descriptorBufferCounts.stages[kMVKShaderStageTessCtl]) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Tessellation control shader requires tessellation level output buffer, but there is no free slot to pass it."));
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addTessEvalShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													  const VkGraphicsPipelineCreateInfo* pCreateInfo,
													  SPIRVToMSLConversionConfiguration& shaderConfig,
													  SPIRVShaderOutputs& tcOutputs) {
	shaderConfig.options.entryPointStage = spv::ExecutionModelTessellationEvaluation;
	shaderConfig.options.entryPointName = _pTessEvalSS->pName;
	shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageTessEval];
	shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageTessEval];
	shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageTessEval];
	shaderConfig.options.mslOptions.capture_output_to_buffer = false;
	shaderConfig.options.mslOptions.disable_rasterization = !_isRasterizing;
	addPrevStageOutputToShaderConversionConfig(shaderConfig, tcOutputs);

	MVKMTLFunction func = ((MVKShaderModule*)_pTessEvalSS->module)->getMTLFunction(&shaderConfig, _pTessEvalSS->pSpecializationInfo, _pipelineCache);
	id<MTLFunction> mtlFunc = func.getMTLFunction();
	if ( !mtlFunc ) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Tessellation evaluation shader function could not be compiled into pipeline. See previous logged error."));
		return false;
	}
	// Yeah, you read that right. Tess. eval functions are a kind of vertex function in Metal.
	plDesc.vertexFunction = mtlFunc;

	auto& funcRslts = func.shaderConversionResults;
	plDesc.rasterizationEnabled = !funcRslts.isRasterizationDisabled;
	_needsTessEvalSwizzleBuffer = funcRslts.needsSwizzleBuffer;
	_needsTessEvalBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsTessEvalDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;

	addMTLArgumentEncoders(func, pCreateInfo, shaderConfig, kMVKShaderStageTessEval);

	if (funcRslts.isRasterizationDisabled) {
		_pFragmentSS = nullptr;
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
													  SPIRVShaderOutputs& shaderOutputs) {
	if (_pFragmentSS) {
		shaderConfig.options.entryPointStage = spv::ExecutionModelFragment;
		shaderConfig.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageFragment];
		shaderConfig.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageFragment];
		shaderConfig.options.mslOptions.dynamic_offsets_buffer_index = _dynamicOffsetBufferIndex.stages[kMVKShaderStageFragment];
		shaderConfig.options.mslOptions.view_mask_buffer_index = _viewRangeBufferIndex.stages[kMVKShaderStageFragment];
		shaderConfig.options.entryPointName = _pFragmentSS->pName;
		shaderConfig.options.mslOptions.capture_output_to_buffer = false;
		shaderConfig.options.mslOptions.fixed_subgroup_size = mvkIsAnyFlagEnabled(_pFragmentSS->flags, VK_PIPELINE_SHADER_STAGE_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT_EXT) ? 0 : _device->_pMetalFeatures->maxSubgroupSize;
		if (_isRasterizing && pCreateInfo->pMultisampleState) {		// Must ignore allowed bad pMultisampleState pointer if rasterization disabled
			if (pCreateInfo->pMultisampleState->pSampleMask && pCreateInfo->pMultisampleState->pSampleMask[0] != 0xffffffff) {
				shaderConfig.options.mslOptions.additional_fixed_sample_mask = pCreateInfo->pMultisampleState->pSampleMask[0];
			}
			shaderConfig.options.mslOptions.force_sample_rate_shading = pCreateInfo->pMultisampleState->sampleShadingEnable && pCreateInfo->pMultisampleState->minSampleShading != 0.0f;
		}
		if (std::any_of(shaderOutputs.begin(), shaderOutputs.end(), [](const SPIRVShaderOutput& output) { return output.builtin == spv::BuiltInLayer; })) {
			shaderConfig.options.mslOptions.arrayed_subpass_input = true;
		}
		addPrevStageOutputToShaderConversionConfig(shaderConfig, shaderOutputs);

		MVKMTLFunction func = ((MVKShaderModule*)_pFragmentSS->module)->getMTLFunction(&shaderConfig, _pFragmentSS->pSpecializationInfo, _pipelineCache);
		id<MTLFunction> mtlFunc = func.getMTLFunction();
		if ( !mtlFunc ) {
			setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Fragment shader function could not be compiled into pipeline. See previous logged error."));
			return false;
		}
		plDesc.fragmentFunction = mtlFunc;

		auto& funcRslts = func.shaderConversionResults;
		_needsFragmentSwizzleBuffer = funcRslts.needsSwizzleBuffer;
		_needsFragmentBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
		_needsFragmentDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
		_needsFragmentViewRangeBuffer = funcRslts.needsViewRangeBuffer;

		addMTLArgumentEncoders(func, pCreateInfo, shaderConfig, kMVKShaderStageFragment);

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

template<class T>
bool MVKGraphicsPipeline::addVertexInputToPipeline(T* inputDesc,
												   const VkPipelineVertexInputStateCreateInfo* pVI,
												   const SPIRVToMSLConversionConfiguration& shaderConfig) {
    // Collect extension structures
    VkPipelineVertexInputDivisorStateCreateInfoEXT* pVertexInputDivisorState = nullptr;
	for (const auto* next = (VkBaseInStructure*)pVI->pNext; next; next = next->pNext) {
        switch (next->sType) {
        case VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_DIVISOR_STATE_CREATE_INFO_EXT:
            pVertexInputDivisorState = (VkPipelineVertexInputDivisorStateCreateInfoEXT*)next;
            break;
        default:
            break;
        }
    }

    // Vertex buffer bindings
	uint32_t vbCnt = pVI->vertexBindingDescriptionCount;
	uint32_t maxBinding = 0;
    for (uint32_t i = 0; i < vbCnt; i++) {
        const VkVertexInputBindingDescription* pVKVB = &pVI->pVertexBindingDescriptions[i];
        if (shaderConfig.isVertexBufferUsed(pVKVB->binding)) {

			// Vulkan allows any stride, but Metal only allows multiples of 4.
            // TODO: We could try to expand the buffer to the required alignment in that case.
			VkDeviceSize mtlVtxStrideAlignment = _device->_pMetalFeatures->vertexStrideAlignment;
            if ((pVKVB->stride % mtlVtxStrideAlignment) != 0) {
				setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Under Metal, vertex attribute binding strides must be aligned to %llu bytes.", mtlVtxStrideAlignment));
                return false;
            }

			maxBinding = max(pVKVB->binding, maxBinding);
			uint32_t vbIdx = getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
			auto vbDesc = inputDesc.layouts[vbIdx];
			if (pVKVB->stride == 0) {
				// Stride can't be 0, it will be set later to attributes' maximum offset + size
				// to prevent it from being larger than the underlying buffer permits.
				vbDesc.stride = 0;
				vbDesc.stepFunction = (decltype(vbDesc.stepFunction))MTLStepFunctionConstant;
				vbDesc.stepRate = 0;
			} else {
				vbDesc.stride = pVKVB->stride;
				vbDesc.stepFunction = (decltype(vbDesc.stepFunction))mvkMTLStepFunctionFromVkVertexInputRate(pVKVB->inputRate, isTessellationPipeline());
				vbDesc.stepRate = 1;
			}
        }
    }

    // Vertex buffer divisors (step rates)
    std::unordered_set<uint32_t> zeroDivisorBindings;
    if (pVertexInputDivisorState) {
        vbCnt = pVertexInputDivisorState->vertexBindingDivisorCount;
        for (uint32_t i = 0; i < vbCnt; i++) {
            const VkVertexInputBindingDivisorDescriptionEXT* pVKVB = &pVertexInputDivisorState->pVertexBindingDivisors[i];
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

			// Vulkan allows offsets to exceed the buffer stride, but Metal doesn't.
			// If this is the case, fetch a translated artificial buffer binding, using the same MTLBuffer,
			// but that is translated so that the reduced VA offset fits into the binding stride.
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

			auto vaDesc = inputDesc.attributes[pVKVA->location];
			auto mtlFormat = (decltype(vaDesc.format))getPixelFormats()->getMTLVertexFormat(pVKVA->format);
			if (pVKVB->stride && attrSize > pVKVB->stride) {
				/* Metal does not support overlapping loads. Truncate format vector length to prevent an assertion
				 * and hope it's not used by the shader. */
				MTLVertexFormat newFormat = mvkAdjustFormatVectorToSize((MTLVertexFormat)mtlFormat, pVKVB->stride);
				reportError(VK_SUCCESS, "Found attribute with size (%u) larger than it's binding's stride (%u). Changing descriptor format from %s to %s.",
					attrSize, pVKVB->stride, getPixelFormats()->getName((MTLVertexFormat)mtlFormat), getPixelFormats()->getName(newFormat));
				mtlFormat = (decltype(vaDesc.format))newFormat;
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
					xldtVACnt++;
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
			return xltdBind.translationBinding;
		}
	}

	// Get next available binding point and add a translation binding description for it
	uint16_t xltdBindPt = (uint16_t)(maxBinding + _translatedVertexBindings.size() + 1);
	_translatedVertexBindings.push_back( {.binding = (uint16_t)binding, .translationBinding = xltdBindPt, .translationOffset = translationOffset} );

	return xltdBindPt;
}

void MVKGraphicsPipeline::addTessellationToPipeline(MTLRenderPipelineDescriptor* plDesc,
													const SPIRVTessReflectionData& reflectData,
													const VkPipelineTessellationStateCreateInfo* pTS) {

	VkPipelineTessellationDomainOriginStateCreateInfo* pTessDomainOriginState = nullptr;
	if (reflectData.patchKind == spv::ExecutionModeTriangles) {
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

	plDesc.maxTessellationFactor = _device->_pProperties->limits.maxTessellationGenerationLevel;
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
            }
        }
    }

    // Depth & stencil attachments
	MVKPixelFormats* pixFmts = getPixelFormats();
    MTLPixelFormat mtlDSFormat = pixFmts->getMTLPixelFormat(mvkGetDepthStencilFormat(pRendInfo));
    if (pixFmts->isDepthFormat(mtlDSFormat)) { plDesc.depthAttachmentPixelFormat = mtlDSFormat; }
    if (pixFmts->isStencilFormat(mtlDSFormat)) { plDesc.stencilAttachmentPixelFormat = mtlDSFormat; }

    // In Vulkan, it's perfectly valid to render with no attachments. In Metal we need to check for
    // support for it. If we have no attachments, then we may have to add a dummy attachment.
    if (!caCnt && !pixFmts->isDepthFormat(mtlDSFormat) && !pixFmts->isStencilFormat(mtlDSFormat) &&
        !getDevice()->_pMetalFeatures->renderWithoutAttachments) {

        MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[0];
        colorDesc.pixelFormat = MTLPixelFormatR8Unorm;
        colorDesc.writeMask = MTLColorWriteMaskNone;
    }

    // Multisampling - must ignore allowed bad pMultisampleState pointer if rasterization disabled
    if (_isRasterizing && pCreateInfo->pMultisampleState) {
        plDesc.sampleCount = mvkSampleCountFromVkSampleCountFlagBits(pCreateInfo->pMultisampleState->rasterizationSamples);
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

    shaderConfig.options.mslOptions.msl_version = _device->_pMetalFeatures->mslVersion;
    shaderConfig.options.mslOptions.texel_buffer_texture_width = _device->_pMetalFeatures->maxTextureDimension;
    shaderConfig.options.mslOptions.r32ui_linear_texture_alignment = (uint32_t)_device->getVkFormatTexelBufferAlignment(VK_FORMAT_R32_UINT, this);
	shaderConfig.options.mslOptions.texture_buffer_native = _device->_pMetalFeatures->textureBuffers;

	bool useMetalArgBuff = isUsingMetalArgumentBuffers();
	shaderConfig.options.mslOptions.argument_buffers = useMetalArgBuff;
	shaderConfig.options.mslOptions.force_active_argument_buffer_resources = useMetalArgBuff;
	shaderConfig.options.mslOptions.pad_argument_buffer_resources = useMetalArgBuff;

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
    MTLPixelFormat mtlDSFormat = pixFmts->getMTLPixelFormat(mvkGetDepthStencilFormat(pRendInfo));

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

	shaderConfig.options.mslOptions.ios_support_base_vertex_instance = getDevice()->_pMetalFeatures->baseVertexInstanceDrawing;
	shaderConfig.options.mslOptions.texture_1D_as_2D = mvkConfig().texture1DAs2D;
    shaderConfig.options.mslOptions.enable_point_size_builtin = isRenderingPoints(pCreateInfo) || reflectData.pointMode;
	shaderConfig.options.mslOptions.enable_frag_depth_builtin = pixFmts->isDepthFormat(mtlDSFormat);
	shaderConfig.options.mslOptions.enable_frag_stencil_ref_builtin = pixFmts->isStencilFormat(mtlDSFormat);
    shaderConfig.options.shouldFlipVertexY = mvkConfig().shaderConversionFlipVertexY;
    shaderConfig.options.mslOptions.swizzle_texture_samples = _fullImageViewSwizzle && !getDevice()->_pMetalFeatures->nativeTextureSwizzle;
    shaderConfig.options.mslOptions.tess_domain_origin_lower_left = pTessDomainOriginState && pTessDomainOriginState->domainOrigin == VK_TESSELLATION_DOMAIN_ORIGIN_LOWER_LEFT;
    shaderConfig.options.mslOptions.multiview = mvkIsMultiview(pRendInfo->viewMask);
    shaderConfig.options.mslOptions.multiview_layered_rendering = getPhysicalDevice()->canUseInstancingForMultiview();
    shaderConfig.options.mslOptions.view_index_from_device_index = mvkAreAllFlagsEnabled(pCreateInfo->flags, VK_PIPELINE_CREATE_VIEW_INDEX_FROM_DEVICE_INDEX_BIT);
#if MVK_MACOS
    shaderConfig.options.mslOptions.emulate_subgroups = !_device->_pMetalFeatures->simdPermute;
#endif
#if MVK_IOS_OR_TVOS
    shaderConfig.options.mslOptions.emulate_subgroups = !_device->_pMetalFeatures->quadPermute;
    shaderConfig.options.mslOptions.ios_use_simdgroup_functions = !!_device->_pMetalFeatures->simdPermute;
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
			if ((pVKVA->binding == pVKVB->binding) && (pVKVA->offset + getPixelFormats()->getBytesPerBlock(pVKVA->format) > pVKVB->stride)) {
				xltdBuffCnt++;
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
	return mtlBufferIndex < _descriptorBufferCounts.stages[stage] || mtlBufferIndex > getImplicitBufferIndex(stage, 0);
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
        si.shaderInput.location = pVKVA->location;
        si.binding = pVKVA->binding;

        // Metal can't do signedness conversions on vertex buffers (rdar://45922847). If the shader
        // and the vertex attribute have mismatched signedness, we have to fix the shader
        // to match the vertex attribute. So tell SPIRV-Cross if we're expecting an unsigned format.
        // Only do this if the attribute could be reasonably expected to fit in the shader's
        // declared type. Programs that try to invoke undefined behavior are on their own.
        switch (getPixelFormats()->getFormatType(pVKVA->format) ) {
        case kMVKFormatColorUInt8:
            si.shaderInput.format = MSL_VERTEX_FORMAT_UINT8;
            break;

        case kMVKFormatColorUInt16:
            si.shaderInput.format = MSL_VERTEX_FORMAT_UINT16;
            break;

        case kMVKFormatDepthStencil:
            // Only some depth/stencil formats have unsigned components.
            switch (pVKVA->format) {
            case VK_FORMAT_S8_UINT:
            case VK_FORMAT_D16_UNORM_S8_UINT:
            case VK_FORMAT_D24_UNORM_S8_UINT:
            case VK_FORMAT_D32_SFLOAT_S8_UINT:
                si.shaderInput.format = MSL_VERTEX_FORMAT_UINT8;
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

// Initializes the shader inputs in a shader conversion config from the previous stage output.
void MVKGraphicsPipeline::addPrevStageOutputToShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig,
                                                                     SPIRVShaderOutputs& shaderOutputs) {
    // Set the shader conversion configuration input variable information
    shaderConfig.shaderInputs.clear();
    uint32_t siCnt = (uint32_t)shaderOutputs.size();
    for (uint32_t siIdx = 0; siIdx < siCnt; siIdx++) {
		if (!shaderOutputs[siIdx].isUsed) { continue; }

        mvk::MSLShaderInput si;
        si.shaderInput.location = shaderOutputs[siIdx].location;
		si.shaderInput.component = shaderOutputs[siIdx].component;
        si.shaderInput.builtin = shaderOutputs[siIdx].builtin;
        si.shaderInput.vecsize = shaderOutputs[siIdx].vecWidth;

        switch (getPixelFormats()->getFormatType(mvkFormatFromOutput(shaderOutputs[siIdx]) ) ) {
            case kMVKFormatColorUInt8:
                si.shaderInput.format = MSL_SHADER_INPUT_FORMAT_UINT8;
                break;

            case kMVKFormatColorUInt16:
                si.shaderInput.format = MSL_SHADER_INPUT_FORMAT_UINT16;
                break;

			case kMVKFormatColorHalf:
			case kMVKFormatColorInt16:
				si.shaderInput.format = MSL_SHADER_INPUT_FORMAT_ANY16;
				break;

			case kMVKFormatColorFloat:
			case kMVKFormatColorInt32:
			case kMVKFormatColorUInt32:
				si.shaderInput.format = MSL_SHADER_INPUT_FORMAT_ANY32;
				break;

            default:
                break;
        }

        shaderConfig.shaderInputs.push_back(si);
    }
}

// We render points if either the topology or polygon fill mode dictate it
bool MVKGraphicsPipeline::isRenderingPoints(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	return ((pCreateInfo->pInputAssemblyState && (pCreateInfo->pInputAssemblyState->topology == VK_PRIMITIVE_TOPOLOGY_POINT_LIST)) ||
			(pCreateInfo->pRasterizationState && (pCreateInfo->pRasterizationState->polygonMode == VK_POLYGON_MODE_POINT)));
}

// We disable rasterization if either rasterizerDiscard is enabled or the cull mode dictates it.
bool MVKGraphicsPipeline::isRasterizationDisabled(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
	return (pCreateInfo->pRasterizationState &&
			(pCreateInfo->pRasterizationState->rasterizerDiscardEnable ||
			 ((pCreateInfo->pRasterizationState->cullMode == VK_CULL_MODE_FRONT_AND_BACK) && pCreateInfo->pInputAssemblyState &&
			  (mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology) == MTLPrimitiveTopologyClassTriangle))));
}

MVKGraphicsPipeline::~MVKGraphicsPipeline() {
	@synchronized (getMTLDevice()) {
		[_mtlTessVertexStageDesc release];

		[_mtlTessVertexStageState release];
		[_mtlTessVertexStageIndex16State release];
		[_mtlTessVertexStageIndex32State release];
		[_mtlTessControlStageState release];
		[_mtlPipelineState release];

		for (id<MTLFunction> func : _mtlTessVertexFunctions) { [func release]; }
	}
}


#pragma mark -
#pragma mark MVKComputePipeline

void MVKComputePipeline::encode(MVKCommandEncoder* cmdEncoder, uint32_t) {
	if ( !_hasValidMTLPipelineStates ) { return; }

	[cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setComputePipelineState: _mtlPipelineState];
    cmdEncoder->_mtlThreadgroupSize = _mtlThreadgroupSize;
	cmdEncoder->_computeResourcesState.bindSwizzleBuffer(_swizzleBufferIndex, _needsSwizzleBuffer);
	cmdEncoder->_computeResourcesState.bindBufferSizeBuffer(_bufferSizeBufferIndex, _needsBufferSizeBuffer);
	cmdEncoder->_computeResourcesState.bindDynamicOffsetBuffer(_dynamicOffsetBufferIndex, _needsDynamicOffsetBuffer);
}

MVKComputePipeline::MVKComputePipeline(MVKDevice* device,
									   MVKPipelineCache* pipelineCache,
									   MVKPipeline* parent,
									   const VkComputePipelineCreateInfo* pCreateInfo) :
	MVKPipeline(device, pipelineCache, (MVKPipelineLayout*)pCreateInfo->layout, parent) {

	_allowsDispatchBase = mvkAreAllFlagsEnabled(pCreateInfo->flags, VK_PIPELINE_CREATE_DISPATCH_BASE_BIT);

	if (isUsingMetalArgumentBuffers()) { _descriptorBindingUse.resize(_descriptorSetCount); }
	if (isUsingPipelineStageMetalArgumentBuffers()) { _mtlArgumentEncoders.resize(_descriptorSetCount); }

	MVKMTLFunction func = getMTLFunction(pCreateInfo);
	_mtlThreadgroupSize = func.threadGroupSize;
	_mtlPipelineState = nil;

	id<MTLFunction> mtlFunc = func.getMTLFunction();
	if (mtlFunc) {
		MTLComputePipelineDescriptor* plDesc = [MTLComputePipelineDescriptor new];	// temp retain
		plDesc.computeFunction = mtlFunc;
		plDesc.maxTotalThreadsPerThreadgroup = _mtlThreadgroupSize.width * _mtlThreadgroupSize.height * _mtlThreadgroupSize.depth;
		plDesc.threadGroupSizeIsMultipleOfThreadExecutionWidth = mvkIsAnyFlagEnabled(pCreateInfo->stage.flags, VK_PIPELINE_SHADER_STAGE_CREATE_REQUIRE_FULL_SUBGROUPS_BIT_EXT);

		// Metal does not allow the name of the pipeline to be changed after it has been created,
		// and we need to create the Metal pipeline immediately to provide error feedback to app.
		// The best we can do at this point is set the pipeline name from the layout.
		setLabelIfNotNil(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

		MVKComputePipelineCompiler* plc = new MVKComputePipelineCompiler(this);
		_mtlPipelineState = plc->newMTLComputePipelineState(plDesc);	// retained
		plc->destroy();
		[plDesc release];															// temp release

		if ( !_mtlPipelineState ) { _hasValidMTLPipelineStates = false; }
	} else {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Compute shader function could not be compiled into pipeline. See previous logged error."));
	}

	if (_needsSwizzleBuffer && _swizzleBufferIndex.stages[kMVKShaderStageCompute] > _device->_pMetalFeatures->maxPerStageBufferCount) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Compute shader requires swizzle buffer, but there is no free slot to pass it."));
	}
	if (_needsBufferSizeBuffer && _bufferSizeBufferIndex.stages[kMVKShaderStageCompute] > _device->_pMetalFeatures->maxPerStageBufferCount) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Compute shader requires buffer size buffer, but there is no free slot to pass it."));
	}
	if (_needsDynamicOffsetBuffer && _dynamicOffsetBufferIndex.stages[kMVKShaderStageCompute] > _device->_pMetalFeatures->maxPerStageBufferCount) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Compute shader requires dynamic offset buffer, but there is no free slot to pass it."));
	}
	if (_needsDispatchBaseBuffer && _indirectParamsIndex.stages[kMVKShaderStageCompute] > _device->_pMetalFeatures->maxPerStageBufferCount) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Compute shader requires dispatch base buffer, but there is no free slot to pass it."));
	}
}

// Returns a MTLFunction to use when creating the MTLComputePipelineState.
MVKMTLFunction MVKComputePipeline::getMTLFunction(const VkComputePipelineCreateInfo* pCreateInfo) {

    const VkPipelineShaderStageCreateInfo* pSS = &pCreateInfo->stage;
    if ( !mvkAreAllFlagsEnabled(pSS->stage, VK_SHADER_STAGE_COMPUTE_BIT) ) { return MVKMTLFunctionNull; }

    SPIRVToMSLConversionConfiguration shaderConfig;
	shaderConfig.options.entryPointName = pCreateInfo->stage.pName;
	shaderConfig.options.entryPointStage = spv::ExecutionModelGLCompute;
    shaderConfig.options.mslOptions.msl_version = _device->_pMetalFeatures->mslVersion;
    shaderConfig.options.mslOptions.texel_buffer_texture_width = _device->_pMetalFeatures->maxTextureDimension;
    shaderConfig.options.mslOptions.r32ui_linear_texture_alignment = (uint32_t)_device->getVkFormatTexelBufferAlignment(VK_FORMAT_R32_UINT, this);
	shaderConfig.options.mslOptions.swizzle_texture_samples = _fullImageViewSwizzle && !getDevice()->_pMetalFeatures->nativeTextureSwizzle;
	shaderConfig.options.mslOptions.texture_buffer_native = _device->_pMetalFeatures->textureBuffers;
	shaderConfig.options.mslOptions.dispatch_base = _allowsDispatchBase;
	shaderConfig.options.mslOptions.texture_1D_as_2D = mvkConfig().texture1DAs2D;
    shaderConfig.options.mslOptions.fixed_subgroup_size = mvkIsAnyFlagEnabled(pSS->flags, VK_PIPELINE_SHADER_STAGE_CREATE_ALLOW_VARYING_SUBGROUP_SIZE_BIT_EXT) ? 0 : _device->_pMetalFeatures->maxSubgroupSize;

	bool useMetalArgBuff = isUsingMetalArgumentBuffers();
	shaderConfig.options.mslOptions.argument_buffers = useMetalArgBuff;
	shaderConfig.options.mslOptions.force_active_argument_buffer_resources = useMetalArgBuff;
	shaderConfig.options.mslOptions.pad_argument_buffer_resources = useMetalArgBuff;

#if MVK_MACOS
    shaderConfig.options.mslOptions.emulate_subgroups = !_device->_pMetalFeatures->simdPermute;
#endif
#if MVK_IOS_OR_TVOS
    shaderConfig.options.mslOptions.emulate_subgroups = !_device->_pMetalFeatures->quadPermute;
    shaderConfig.options.mslOptions.ios_use_simdgroup_functions = !!_device->_pMetalFeatures->simdPermute;
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

    MVKMTLFunction func = ((MVKShaderModule*)pSS->module)->getMTLFunction(&shaderConfig, pSS->pSpecializationInfo, _pipelineCache);

	auto& funcRslts = func.shaderConversionResults;
	_needsSwizzleBuffer = funcRslts.needsSwizzleBuffer;
    _needsBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsDynamicOffsetBuffer = funcRslts.needsDynamicOffsetBuffer;
    _needsDispatchBaseBuffer = funcRslts.needsDispatchBaseBuffer;

	addMTLArgumentEncoders(func, pCreateInfo, shaderConfig, kMVKShaderStageCompute);

	return func;
}

uint32_t MVKComputePipeline::getImplicitBufferIndex(uint32_t bufferIndexOffset) {
	return _device->_pMetalFeatures->maxPerStageBufferCount - (bufferIndexOffset + 1);
}

MVKComputePipeline::~MVKComputePipeline() {
	@synchronized (getMTLDevice()) {
		[_mtlPipelineState release];
	}
}


#pragma mark -
#pragma mark MVKPipelineCache

// Return a shader library from the specified shader conversion configuration sourced from the specified shader module.
MVKShaderLibrary* MVKPipelineCache::getShaderLibrary(SPIRVToMSLConversionConfiguration* pContext, MVKShaderModule* shaderModule) {
	lock_guard<mutex> lock(_shaderCacheLock);

	bool wasAdded = false;
	MVKShaderLibraryCache* slCache = getShaderLibraryCache(shaderModule->getKey());
	MVKShaderLibrary* shLib = slCache->getShaderLibrary(pContext, shaderModule, &wasAdded);
	if (wasAdded) { markDirty(); }
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

static uint32_t kDataHeaderSize = (sizeof(uint32_t) * 4) + VK_UUID_SIZE;

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
	std::string& getMSL() { return _pSLCache->_shaderLibraries[_index].second->_msl; }
	SPIRVToMSLConversionResults& getShaderConversionResults() { return _pSLCache->_shaderLibraries[_index].second->_shaderConversionResults; }
	MVKShaderCacheIterator(MVKShaderLibraryCache* pSLCache) : _pSLCache(pSLCache) {}

	MVKShaderLibraryCache* _pSLCache;
	size_t _count = 0;
	int32_t _index = -1;
};

// If pData is not null, serializes at most pDataSize bytes of the contents of the cache into that
// memory location, and returns the number of bytes serialized in pDataSize. If pData is null,
// returns the number of bytes required to serialize the contents of this pipeline cache.
// This is the compliment of the readData() function. The two must be kept aligned.
VkResult MVKPipelineCache::writeData(size_t* pDataSize, void* pData) {
	lock_guard<mutex> lock(_shaderCacheLock);

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
}

// Serializes the data in this cache to a stream
void MVKPipelineCache::writeData(ostream& outstream, bool isCounting) {

	MVKPerformanceTracker& activityTracker = isCounting
		? _device->_performanceStatistics.pipelineCache.sizePipelineCache
		: _device->_performanceStatistics.pipelineCache.writePipelineCache;

	uint32_t cacheEntryType;
	cereal::BinaryOutputArchive writer(outstream);

	// Write the data header...after ensuring correct byte-order.
	const VkPhysicalDeviceProperties* pDevProps = _device->_pProperties;
	writer(NSSwapHostIntToLittle(kDataHeaderSize));
	writer(NSSwapHostIntToLittle(VK_PIPELINE_CACHE_HEADER_VERSION_ONE));
	writer(NSSwapHostIntToLittle(pDevProps->vendorID));
	writer(NSSwapHostIntToLittle(pDevProps->deviceID));
	writer(pDevProps->pipelineCacheUUID);

	// Shader libraries
	// Output a cache entry for each shader library, including the shader module key in each entry.
	cacheEntryType = MVKPipelineCacheEntryTypeShaderLibrary;
	for (auto& scPair : _shaderCache) {
		MVKShaderModuleKey smKey = scPair.first;
		MVKShaderCacheIterator cacheIter(scPair.second);
		while (cacheIter.next()) {
			uint64_t startTime = _device->getPerformanceTimestamp();
			writer(cacheEntryType);
			writer(smKey);
			writer(cacheIter.getShaderConversionConfig());
			writer(cacheIter.getShaderConversionResults());
			writer(cacheIter.getMSL());
			_device->addActivityPerformance(activityTracker, startTime);
		}
	}

	// Mark the end of the archive
	cacheEntryType = MVKPipelineCacheEntryTypeEOF;
	writer(cacheEntryType);
}

// Loads any data indicated by the creation info.
// This is the compliment of the writeData() function. The two must be kept aligned.
void MVKPipelineCache::readData(const VkPipelineCacheCreateInfo* pCreateInfo) {
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
		const VkPhysicalDeviceProperties* pDevProps = _device->_pProperties;

		reader(hdrComponent);	// Header size
		if (NSSwapLittleIntToHost(hdrComponent) !=  kDataHeaderSize) { return; }

		reader(hdrComponent);	// Header version
		if (NSSwapLittleIntToHost(hdrComponent) !=  VK_PIPELINE_CACHE_HEADER_VERSION_ONE) { return; }

		reader(hdrComponent);	// Vendor ID
		if (NSSwapLittleIntToHost(hdrComponent) !=  pDevProps->vendorID) { return; }

		reader(hdrComponent);	// Device ID
		if (NSSwapLittleIntToHost(hdrComponent) !=  pDevProps->deviceID) { return; }

		reader(pcUUID);			// Pipeline cache UUID
		if ( !mvkAreEqual(pcUUID, pDevProps->pipelineCacheUUID, VK_UUID_SIZE) ) { return; }

		bool done = false;
		while ( !done ) {
			reader(cacheEntryType);
			switch (cacheEntryType) {
				case MVKPipelineCacheEntryTypeShaderLibrary: {
					uint64_t startTime = _device->getPerformanceTimestamp();

					MVKShaderModuleKey smKey;
					reader(smKey);

					SPIRVToMSLConversionConfiguration shaderConversionConfig;
					reader(shaderConversionConfig);

					SPIRVToMSLConversionResults shaderConversionResults;
					reader(shaderConversionResults);

					string msl;
					reader(msl);

					// Add the shader library to the staging cache.
					MVKShaderLibraryCache* slCache = getShaderLibraryCache(smKey);
					_device->addActivityPerformance(_device->_performanceStatistics.pipelineCache.readPipelineCache, startTime);
					slCache->addShaderLibrary(&shaderConversionConfig, msl, shaderConversionResults);

					break;
				}

				default: {
					done = true;
					break;
				}
			}
		}

	} catch (cereal::Exception& ex) {
		setConfigurationResult(reportError(VK_SUCCESS, "Error reading pipeline cache data: %s", ex.what()));
	}
}

// Mark the cache as dirty, so that existing streaming info is released
void MVKPipelineCache::markDirty() {
	_dataSize = 0;
}

VkResult MVKPipelineCache::mergePipelineCaches(uint32_t srcCacheCount, const VkPipelineCache* pSrcCaches) {
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
				opt.force_native_arrays,
				opt.enable_clip_distance_user_varying,
				opt.multi_patch_workgroup,
				opt.vertex_for_tessellation,
				opt.arrayed_subpass_input,
				opt.ios_use_simdgroup_functions,
				opt.emulate_subgroups,
				opt.vertex_index_type,
				opt.force_sample_rate_shading);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLShaderInput& si) {
		archive(si.location,
				si.component,
				si.format,
				si.builtin,
				si.vecsize);
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
				opt.shouldFlipVertexY);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLShaderInput& si) {
		archive(si.shaderInput,
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
				ctx.resourceBindings,
				ctx.discreteDescriptorSets);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVToMSLConversionResults& scr) {
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
				scr.needsViewRangeBuffer);
	}

}

template<class Archive>
void serialize(Archive & archive, MVKShaderModuleKey& k) {
	archive(k.codeSize,
			k.codeHash);
}


#pragma mark Construction

MVKPipelineCache::MVKPipelineCache(MVKDevice* device, const VkPipelineCacheCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
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
		auto mtlDev = _owner->getMTLDevice();
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

id<MTLComputePipelineState> MVKComputePipelineCompiler::newMTLComputePipelineState(id<MTLFunction> mtlFunction) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		auto mtlDev = _owner->getMTLDevice();
		@synchronized (mtlDev) {
			[mtlDev newComputePipelineStateWithFunction: mtlFunction
									  completionHandler: ^(id<MTLComputePipelineState> ps, NSError* error) {
										  bool isLate = compileComplete(ps, error);
										  if (isLate) { destroy(); }
									  }];
		}
	});

	return [_mtlComputePipelineState retain];
}

id<MTLComputePipelineState> MVKComputePipelineCompiler::newMTLComputePipelineState(MTLComputePipelineDescriptor* plDesc) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		auto mtlDev = _owner->getMTLDevice();
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

