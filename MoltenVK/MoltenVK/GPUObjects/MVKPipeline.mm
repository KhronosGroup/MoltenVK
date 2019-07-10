/*
 * MVKPipeline.mm
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

#include "MVKPipeline.h"
#include <MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.h>
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
                                           MVKVector<MVKDescriptorSet*>& descriptorSets,
                                           uint32_t firstSet,
                                           MVKVector<uint32_t>& dynamicOffsets) {
	clearConfigurationResult();
	uint32_t pDynamicOffsetIndex = 0;
	uint32_t dsCnt = (uint32_t)descriptorSets.size();
	for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
		MVKDescriptorSet* descSet = descriptorSets[dsIdx];
		uint32_t dslIdx = firstSet + dsIdx;
		auto& dsl = _descriptorSetLayouts[dslIdx];
		dsl.bindDescriptorSet(cmdEncoder, descSet,
							  _dslMTLResourceIndexOffsets[dslIdx],
							  dynamicOffsets, &pDynamicOffsetIndex);
		setConfigurationResult(dsl.getConfigurationResult());
	}
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKPipelineLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                          MVKVector<VkWriteDescriptorSet>& descriptorWrites,
                                          uint32_t set) {
	clearConfigurationResult();
	auto& dsl = _descriptorSetLayouts[set];
	dsl.pushDescriptorSet(cmdEncoder, descriptorWrites, _dslMTLResourceIndexOffsets[set]);
	setConfigurationResult(dsl.getConfigurationResult());
}

// A null cmdEncoder can be passed to perform a validation pass
void MVKPipelineLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                          MVKDescriptorUpdateTemplate* descUpdateTemplate,
                                          uint32_t set,
                                          const void* pData) {
	clearConfigurationResult();
	auto& dsl = _descriptorSetLayouts[set];
	dsl.pushDescriptorSet(cmdEncoder, descUpdateTemplate, pData, _dslMTLResourceIndexOffsets[set]);
	setConfigurationResult(dsl.getConfigurationResult());
}

void MVKPipelineLayout::populateShaderConverterContext(SPIRVToMSLConversionConfiguration& context) {
	context.resourceBindings.clear();

    // Add resource bindings defined in the descriptor set layouts
	uint32_t dslCnt = (uint32_t)_descriptorSetLayouts.size();
	for (uint32_t dslIdx = 0; dslIdx < dslCnt; dslIdx++) {
        _descriptorSetLayouts[dslIdx].populateShaderConverterContext(context,
                                                                     _dslMTLResourceIndexOffsets[dslIdx],
                                                                     dslIdx);
	}

	// Add any resource bindings used by push-constants
	static const spv::ExecutionModel models[] = {
		spv::ExecutionModelVertex,
		spv::ExecutionModelTessellationControl,
		spv::ExecutionModelTessellationEvaluation,
		spv::ExecutionModelFragment,
		spv::ExecutionModelGLCompute
	};
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
		mvkPopulateShaderConverterContext(context,
										  _pushConstantsMTLResourceIndexes.stages[i],
										  models[i],
										  kPushConstDescSet,
										  kPushConstBinding,
										  nullptr);
	}
}

MVKPipelineLayout::MVKPipelineLayout(MVKDevice* device,
                                     const VkPipelineLayoutCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {

    // Add descriptor set layouts, accumulating the resource index offsets used by the
    // corresponding DSL, and associating the current accumulated resource index offsets
    // with each DSL as it is added. The final accumulation of resource index offsets
    // becomes the resource index offsets that will be used for push contants.

    // According to the Vulkan spec, VkDescriptorSetLayout is intended to be consumed when
    // passed to any Vulkan function, and may be safely destroyed by app immediately after.
    // In order for this pipeline layout to retain the content of a VkDescriptorSetLayout,
    // this pipeline holds onto copies of the MVKDescriptorSetLayout instances, so that the
    // originals created by the app can be safely destroyed.

	_descriptorSetLayouts.reserve(pCreateInfo->setLayoutCount);
	for (uint32_t i = 0; i < pCreateInfo->setLayoutCount; i++) {
		MVKDescriptorSetLayout* pDescSetLayout = (MVKDescriptorSetLayout*)pCreateInfo->pSetLayouts[i];
		_descriptorSetLayouts.push_back(*pDescSetLayout);
		_dslMTLResourceIndexOffsets.push_back(_pushConstantsMTLResourceIndexes);
		_pushConstantsMTLResourceIndexes += pDescSetLayout->_mtlResourceCounts;
	}

	// Add push constants
	_pushConstants.reserve(pCreateInfo->pushConstantRangeCount);
	for (uint32_t i = 0; i < pCreateInfo->pushConstantRangeCount; i++) {
		_pushConstants.push_back(pCreateInfo->pPushConstantRanges[i]);
	}

	// Set implicit buffer indices
	// FIXME: Many of these are optional. We shouldn't set the ones that aren't
	// present--or at least, we should move the ones that are down to avoid
	// running over the limit of available buffers. But we can't know that
	// until we compile the shaders.
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
		_swizzleBufferIndex.stages[i] = _pushConstantsMTLResourceIndexes.stages[i].bufferIndex + 1;
		_bufferSizeBufferIndex.stages[i] = _swizzleBufferIndex.stages[i] + 1;
		_indirectParamsIndex.stages[i] = _bufferSizeBufferIndex.stages[i] + 1;
		_outputBufferIndex.stages[i] = _indirectParamsIndex.stages[i] + 1;
		if (i == kMVKShaderStageTessCtl) {
			_tessCtlPatchOutputBufferIndex = _outputBufferIndex.stages[i] + 1;
			_tessCtlLevelBufferIndex = _tessCtlPatchOutputBufferIndex + 1;
		}
	}
}


#pragma mark -
#pragma mark MVKPipeline

void MVKPipeline::bindPushConstants(MVKCommandEncoder* cmdEncoder) {
	if (cmdEncoder) {
		for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
			cmdEncoder->getPushConstants(mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage(i)))->setMTLBufferIndex(_pushConstantsMTLResourceIndexes.stages[i].bufferIndex);
		}
	}
}

MVKPipeline::MVKPipeline(MVKDevice* device, MVKPipelineCache* pipelineCache, MVKPipelineLayout* layout, MVKPipeline* parent) :
	MVKVulkanAPIDeviceObject(device),
	_pipelineCache(pipelineCache),
	_pushConstantsMTLResourceIndexes(layout->getPushConstantBindings()),
	_fullImageViewSwizzle(device->_pMVKConfig->fullImageViewSwizzle) {}


#pragma mark -
#pragma mark MVKGraphicsPipeline

void MVKGraphicsPipeline::getStages(MVKVector<uint32_t>& stages) {
    if (isTessellationPipeline()) {
        stages.push_back(kMVKGraphicsStageVertex);
        stages.push_back(kMVKGraphicsStageTessControl);
    }
    stages.push_back(kMVKGraphicsStageRasterization);
}

void MVKGraphicsPipeline::encode(MVKCommandEncoder* cmdEncoder, uint32_t stage) {
	if ( !_hasValidMTLPipelineStates ) { return; }

    id<MTLRenderCommandEncoder> mtlCmdEnc = cmdEncoder->_mtlRenderEncoder;
    if ( stage != kMVKGraphicsStageTessControl && !mtlCmdEnc ) { return; }   // Pre-renderpass. Come back later.

    switch (stage) {

		case kMVKGraphicsStageVertex:
			// Stage 1 of a tessellated draw: vertex-only pipeline with rasterization disabled.

            [mtlCmdEnc setRenderPipelineState: _mtlTessVertexStageState];
            break;

        case kMVKGraphicsStageTessControl: {
			// Stage 2 of a tessellated draw: compute pipeline to run the tess. control shader.

			// N.B. This will prematurely terminate the current subpass. We'll have to remember to start it back up again.
			// Due to yet another impedance mismatch between Metal and Vulkan, which pipeline
			// state we use depends on whether or not we have an index buffer, and if we do,
			// the kind of indices in it. Furthermore, to avoid fetching the wrong attribute
			// data when there are more output vertices than input vertices, we use an
			// indexed dispatch to force each instance to fetch the correct entry.
            id<MTLComputePipelineState> plState;
			const char* compilerType = "Tessellation control stage pipeline";
			const MVKIndexMTLBufferBinding& indexBuff = cmdEncoder->_graphicsResourcesState._mtlIndexBufferBinding;
            MTLComputePipelineDescriptor* plDesc = [[_mtlTessControlStageDesc copy] autorelease];  // Use a copy to be thread-safe.
            if (!indexBuff.mtlBuffer && getInputControlPointCount() >= getOutputControlPointCount()) {
                plState = getOrCompilePipeline(plDesc, _mtlTessControlStageState, compilerType);
            } else if (indexBuff.mtlIndexType == MTLIndexTypeUInt16) {
                plDesc.stageInputDescriptor.indexType = MTLIndexTypeUInt16;
                plDesc.stageInputDescriptor.layouts[kMVKTessCtlInputBufferIndex].stepFunction = MTLStepFunctionThreadPositionInGridXIndexed;
                plState = getOrCompilePipeline(plDesc, _mtlTessControlStageIndex16State, compilerType);
            } else {
                plDesc.stageInputDescriptor.indexType = MTLIndexTypeUInt32;
                plDesc.stageInputDescriptor.layouts[kMVKTessCtlInputBufferIndex].stepFunction = MTLStepFunctionThreadPositionInGridXIndexed;
                plState = getOrCompilePipeline(plDesc, _mtlTessControlStageIndex32State, compilerType);
            }
			if ( !_hasValidMTLPipelineStates ) { return; }

            id<MTLComputeCommandEncoder> tessCtlEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl);
            [tessCtlEnc setComputePipelineState: plState];
            if (_needsTessCtlInput) {
                [tessCtlEnc setThreadgroupMemoryLength: getDevice()->_pProperties->limits.maxTessellationControlPerVertexInputComponents * 4 * getInputControlPointCount() atIndex: 0];
            }
            break;
        }

        case kMVKGraphicsStageRasterization:
			// Stage 3 of a tessellated draw:

			if ( !_mtlPipelineState ) { return; }		// Abort if pipeline could not be created.
            // Render pipeline state
            [mtlCmdEnc setRenderPipelineState: _mtlPipelineState];

            // Depth stencil state
            if (_hasDepthStencilInfo) {
                cmdEncoder->_depthStencilState.setDepthStencilState(_depthStencilInfo);
                cmdEncoder->_stencilReferenceValueState.setReferenceValues(_depthStencilInfo);
            } else {
                cmdEncoder->_depthStencilState.reset();
                cmdEncoder->_stencilReferenceValueState.reset();
            }

            // Rasterization
            cmdEncoder->_blendColorState.setBlendColor(_blendConstants[0], _blendConstants[1],
                                                       _blendConstants[2], _blendConstants[3], false);
            cmdEncoder->_depthBiasState.setDepthBias(_rasterInfo);
            cmdEncoder->_viewportState.setViewports(_mtlViewports, 0, false);
            cmdEncoder->_scissorState.setScissors(_mtlScissors, 0, false);
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
}

bool MVKGraphicsPipeline::supportsDynamicState(VkDynamicState state) {

    // First test if this dynamic state is explicitly turned off
    if ( (state >= VK_DYNAMIC_STATE_RANGE_SIZE) || !_dynamicStateEnabled[state] ) { return false; }

    // Some dynamic states have other restrictions
    switch (state) {
        case VK_DYNAMIC_STATE_DEPTH_BIAS:
            return _rasterInfo.depthBiasEnable;
        default:
            return true;
    }
}


#pragma mark Construction

MVKGraphicsPipeline::MVKGraphicsPipeline(MVKDevice* device,
										 MVKPipelineCache* pipelineCache,
										 MVKPipeline* parent,
										 const VkGraphicsPipelineCreateInfo* pCreateInfo) :
	MVKPipeline(device, pipelineCache, (MVKPipelineLayout*)pCreateInfo->layout, parent) {

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

	// Track dynamic state in _dynamicStateEnabled array
	memset(&_dynamicStateEnabled, false, sizeof(_dynamicStateEnabled));		// start with all dynamic state disabled
	const VkPipelineDynamicStateCreateInfo* pDS = pCreateInfo->pDynamicState;
	if (pDS) {
		for (uint32_t i = 0; i < pDS->dynamicStateCount; i++) {
			VkDynamicState ds = pDS->pDynamicStates[i];
			_dynamicStateEnabled[ds] = true;
		}
	}

	// Blending
	if (pCreateInfo->pColorBlendState) {
		memcpy(&_blendConstants, &pCreateInfo->pColorBlendState->blendConstants, sizeof(_blendConstants));
	}

	// Topology
	_mtlPrimitiveType = MTLPrimitiveTypePoint;
	if (pCreateInfo->pInputAssemblyState && !isRenderingPoints(pCreateInfo, reflectData)) {
		_mtlPrimitiveType = mvkMTLPrimitiveTypeFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology);
	}

	// Tessellation
	_outputControlPointCount = reflectData.numControlPoints;
	mvkSetOrClear(&_tessInfo, pCreateInfo->pTessellationState);

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

	// Render pipeline state
	initMTLRenderPipelineState(pCreateInfo, reflectData);

	// Depth stencil content
	_hasDepthStencilInfo = mvkSetOrClear(&_depthStencilInfo, pCreateInfo->pDepthStencilState);

	// Viewports and scissors
	if (pCreateInfo->pViewportState) {
		_mtlViewports.reserve(pCreateInfo->pViewportState->viewportCount);
		for (uint32_t i = 0; i < pCreateInfo->pViewportState->viewportCount; i++) {
			// If viewport is dyanamic, we still add a dummy so that the count will be tracked.
			MTLViewport mtlVP;
			if ( !_dynamicStateEnabled[VK_DYNAMIC_STATE_VIEWPORT] ) {
				mtlVP = mvkMTLViewportFromVkViewport(pCreateInfo->pViewportState->pViewports[i]);
			}
			_mtlViewports.push_back(mtlVP);
		}
		_mtlScissors.reserve(pCreateInfo->pViewportState->scissorCount);
		for (uint32_t i = 0; i < pCreateInfo->pViewportState->scissorCount; i++) {
			// If scissor is dyanamic, we still add a dummy so that the count will be tracked.
			MTLScissorRect mtlSc;
			if ( !_dynamicStateEnabled[VK_DYNAMIC_STATE_SCISSOR] ) {
				mtlSc = mvkMTLScissorRectFromVkRect2D(pCreateInfo->pViewportState->pScissors[i]);
			}
			_mtlScissors.push_back(mtlSc);
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

// Constructs the underlying Metal render pipeline.
void MVKGraphicsPipeline::initMTLRenderPipelineState(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData) {
	_mtlTessVertexStageState = nil;
	_mtlTessControlStageState = nil;
	_mtlTessControlStageIndex16State = nil;
	_mtlTessControlStageIndex32State = nil;
	_mtlPipelineState = nil;
	_mtlTessControlStageDesc = nil;
	if (!isTessellationPipeline()) {
		MTLRenderPipelineDescriptor* plDesc = getMTLRenderPipelineDescriptor(pCreateInfo, reflectData);
		if (plDesc) {
			getOrCompilePipeline(plDesc, _mtlPipelineState);
		}
	} else {
		// In this case, we need to create three render pipelines. But, the way Metal handles
		// index buffers for compute stage-in means we have to defer creation of stage 2 until
		// draw time. In the meantime, we'll create and retain a descriptor for it.
		SPIRVToMSLConversionConfiguration shaderContext;
		initMVKShaderConverterContext(shaderContext, pCreateInfo, reflectData);

		MTLRenderPipelineDescriptor* vtxPLDesc = getMTLTessVertexStageDescriptor(pCreateInfo, reflectData, shaderContext);
		_mtlTessControlStageDesc = getMTLTessControlStageDescriptor(pCreateInfo, reflectData, shaderContext);	// retained
		MTLRenderPipelineDescriptor* rastPLDesc = getMTLTessRasterStageDescriptor(pCreateInfo, reflectData, shaderContext);
		if (vtxPLDesc && _mtlTessControlStageDesc && rastPLDesc) {
			if (getOrCompilePipeline(vtxPLDesc, _mtlTessVertexStageState)) {
				getOrCompilePipeline(rastPLDesc, _mtlPipelineState);
			}
		}
	}
}

// Returns a MTLRenderPipelineDescriptor constructed from this instance, or nil if an error occurs.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::getMTLRenderPipelineDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																				 const SPIRVTessReflectionData& reflectData) {
	SPIRVToMSLConversionConfiguration shaderContext;
	initMVKShaderConverterContext(shaderContext, pCreateInfo, reflectData);

	MTLRenderPipelineDescriptor* plDesc = [[MTLRenderPipelineDescriptor new] autorelease];

	// Add shader stages. Compile vertex shader before others just in case conversion changes anything...like rasterizaion disable.
	if (!addVertexShaderToPipeline(plDesc, pCreateInfo, shaderContext)) { return nil; }

	// Fragment shader - only add if rasterization is enabled
	if (!addFragmentShaderToPipeline(plDesc, pCreateInfo, shaderContext)) { return nil; }

	// Vertex input
	if (!addVertexInputToPipeline(plDesc, pCreateInfo->pVertexInputState, shaderContext)) { return nil; }

	// Output
	addFragmentOutputToPipeline(plDesc, reflectData, pCreateInfo);

	// Metal does not allow the name of the pipeline to be changed after it has been created,
	// and we need to create the Metal pipeline immediately to provide error feedback to app.
	// The best we can do at this point is set the pipeline name from the layout.
	setLabelIfNotNil(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

	return plDesc;
}

// Returns a MTLRenderPipelineDescriptor for the vertex stage of a tessellated draw constructed from this instance, or nil if an error occurs.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::getMTLTessVertexStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																				  const SPIRVTessReflectionData& reflectData,
																				  SPIRVToMSLConversionConfiguration& shaderContext) {
	MTLRenderPipelineDescriptor* plDesc = [[MTLRenderPipelineDescriptor new] autorelease];

	// Add shader stages.
	if (!addVertexShaderToPipeline(plDesc, pCreateInfo, shaderContext)) { return nil; }

	// Vertex input
	if (!addVertexInputToPipeline(plDesc, pCreateInfo->pVertexInputState, shaderContext)) { return nil; }

	// Even though this won't be used for rasterization, we still have to set up the rasterization state to
	// match the render pass, or Metal will complain.
	addFragmentOutputToPipeline(plDesc, reflectData, pCreateInfo, true);

	return plDesc;
}

static uint32_t sizeOfOutput(const SPIRVShaderOutput& output) {
	uint32_t vecWidth = output.vecWidth;
	// Round up to 4 elements for 3-vectors, since that reflects how Metal lays them out.
	if (vecWidth == 3) { vecWidth = 4; }
	switch (output.baseType) {
		case SPIRType::SByte:
		case SPIRType::UByte:
			return 1 * vecWidth;
		case SPIRType::Short:
		case SPIRType::UShort:
		case SPIRType::Half:
			return 2 * vecWidth;
		case SPIRType::Int:
		case SPIRType::UInt:
		case SPIRType::Float:
		default:
			return 4 * vecWidth;
	}
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

// Returns a MTLComputePipelineDescriptor for the tess. control stage of a tessellated draw constructed from this instance, or nil if an error occurs.
MTLComputePipelineDescriptor* MVKGraphicsPipeline::getMTLTessControlStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																					const SPIRVTessReflectionData& reflectData,
																					SPIRVToMSLConversionConfiguration& shaderContext) {
	MTLComputePipelineDescriptor* plDesc = [MTLComputePipelineDescriptor new];

	std::vector<SPIRVShaderOutput> vtxOutputs;
	std::string errorLog;
	// Unfortunately, MoltenVKShaderConverter doesn't know about MVKVector, so we can't use that here.
	if (!getShaderOutputs(((MVKShaderModule*)_pVertexSS->module)->getSPIRV(), spv::ExecutionModelVertex, _pVertexSS->pName, vtxOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get vertex outputs: %s", errorLog.c_str()));
		return nil;
	}

	// Add shader stages.
	if (!addTessCtlShaderToPipeline(plDesc, pCreateInfo, shaderContext, vtxOutputs)) {
		[plDesc release];
		return nil;
	}

	// Stage input
	plDesc.stageInputDescriptor = [MTLStageInputOutputDescriptor stageInputOutputDescriptor];
	uint32_t offset = 0;
	for (const SPIRVShaderOutput& output : vtxOutputs) {
		if (output.builtin == spv::BuiltInPointSize && !reflectData.pointMode) { continue; }
		offset = (uint32_t)mvkAlignByteOffset(offset, sizeOfOutput(output));
		if (shaderContext.isVertexAttributeLocationUsed(output.location)) {
			plDesc.stageInputDescriptor.attributes[output.location].bufferIndex = kMVKTessCtlInputBufferIndex;
			plDesc.stageInputDescriptor.attributes[output.location].format = (MTLAttributeFormat)mvkMTLVertexFormatFromVkFormat(mvkFormatFromOutput(output));
			plDesc.stageInputDescriptor.attributes[output.location].offset = offset;
		}
		offset += sizeOfOutput(output);
	}
	if (vtxOutputs.size() > 0) {
		plDesc.stageInputDescriptor.layouts[kMVKTessCtlInputBufferIndex].stepFunction = MTLStepFunctionThreadPositionInGridX;
		plDesc.stageInputDescriptor.layouts[kMVKTessCtlInputBufferIndex].stride = mvkAlignByteOffset(offset, sizeOfOutput(vtxOutputs[0]));
	}
	plDesc.stageInputDescriptor.indexBufferIndex = kMVKTessCtlIndexBufferIndex;

	// Metal does not allow the name of the pipeline to be changed after it has been created,
	// and we need to create the Metal pipeline immediately to provide error feedback to app.
	// The best we can do at this point is set the pipeline name from the layout.
	setLabelIfNotNil(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

	return plDesc;
}

// Returns a MTLRenderPipelineDescriptor for the last stage of a tessellated draw constructed from this instance, or nil if an error occurs.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::getMTLTessRasterStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo,
																				  const SPIRVTessReflectionData& reflectData,
																				  SPIRVToMSLConversionConfiguration& shaderContext) {
	MTLRenderPipelineDescriptor* plDesc = [[MTLRenderPipelineDescriptor new] autorelease];

	std::vector<SPIRVShaderOutput> tcOutputs;
	std::string errorLog;
	if (!getShaderOutputs(((MVKShaderModule*)_pTessCtlSS->module)->getSPIRV(), spv::ExecutionModelTessellationControl, _pTessCtlSS->pName, tcOutputs, errorLog) ) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Failed to get tessellation control outputs: %s", errorLog.c_str()));
		return nil;
	}

	// Add shader stages. Compile tessellation evaluation shader before others just in case conversion changes anything...like rasterizaion disable.
	if (!addTessEvalShaderToPipeline(plDesc, pCreateInfo, shaderContext, tcOutputs)) {
		[plDesc release];
		return nil;
	}

	// Fragment shader - only add if rasterization is enabled
	if (!addFragmentShaderToPipeline(plDesc, pCreateInfo, shaderContext)) {
		[plDesc release];
		return nil;
	}

	// Stage input
	plDesc.vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
	uint32_t offset = 0, patchOffset = 0, outerLoc = -1, innerLoc = -1;
	bool usedPerVertex = false, usedPerPatch = false;
	const SPIRVShaderOutput* firstVertex = nullptr, * firstPatch = nullptr;
	for (const SPIRVShaderOutput& output : tcOutputs) {
		if (output.builtin == spv::BuiltInPointSize && !reflectData.pointMode) { continue; }
		if (!shaderContext.isVertexAttributeLocationUsed(output.location)) {
			if (output.perPatch && !(output.builtin == spv::BuiltInTessLevelOuter || output.builtin == spv::BuiltInTessLevelInner) ) {
				if (!firstPatch) { firstPatch = &output; }
				patchOffset += sizeOfOutput(output);
			} else if (!output.perPatch) {
				if (!firstVertex) { firstVertex = &output; }
				offset += sizeOfOutput(output);
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
			plDesc.vertexDescriptor.attributes[location].bufferIndex = kMVKTessEvalLevelBufferIndex;
			if (reflectData.patchKind == spv::ExecutionModeTriangles || output.builtin == spv::BuiltInTessLevelOuter) {
				plDesc.vertexDescriptor.attributes[location].offset = 0;
				plDesc.vertexDescriptor.attributes[location].format = MTLVertexFormatHalf4;	// FIXME Should use Float4
			} else {
				plDesc.vertexDescriptor.attributes[location].offset = 8;
				plDesc.vertexDescriptor.attributes[location].format = MTLVertexFormatHalf2;	// FIXME Should use Float2
			}
		} else if (output.perPatch) {
			patchOffset = (uint32_t)mvkAlignByteOffset(patchOffset, sizeOfOutput(output));
			plDesc.vertexDescriptor.attributes[output.location].bufferIndex = kMVKTessEvalPatchInputBufferIndex;
			plDesc.vertexDescriptor.attributes[output.location].format = mvkMTLVertexFormatFromVkFormat(mvkFormatFromOutput(output));
			plDesc.vertexDescriptor.attributes[output.location].offset = patchOffset;
			patchOffset += sizeOfOutput(output);
			if (!firstPatch) { firstPatch = &output; }
			usedPerPatch = true;
		} else {
			offset = (uint32_t)mvkAlignByteOffset(offset, sizeOfOutput(output));
			plDesc.vertexDescriptor.attributes[output.location].bufferIndex = kMVKTessEvalInputBufferIndex;
			plDesc.vertexDescriptor.attributes[output.location].format = mvkMTLVertexFormatFromVkFormat(mvkFormatFromOutput(output));
			plDesc.vertexDescriptor.attributes[output.location].offset = offset;
			offset += sizeOfOutput(output);
			if (!firstVertex) { firstVertex = &output; }
			usedPerVertex = true;
		}
	}
	if (usedPerVertex) {
		plDesc.vertexDescriptor.layouts[kMVKTessEvalInputBufferIndex].stepFunction = MTLVertexStepFunctionPerPatchControlPoint;
		plDesc.vertexDescriptor.layouts[kMVKTessEvalInputBufferIndex].stride = mvkAlignByteOffset(offset, sizeOfOutput(*firstVertex));
	}
	if (usedPerPatch) {
		plDesc.vertexDescriptor.layouts[kMVKTessEvalPatchInputBufferIndex].stepFunction = MTLVertexStepFunctionPerPatch;
		plDesc.vertexDescriptor.layouts[kMVKTessEvalPatchInputBufferIndex].stride = mvkAlignByteOffset(patchOffset, sizeOfOutput(*firstPatch));
	}
	if (outerLoc != (uint32_t)(-1) || innerLoc != (uint32_t)(-1)) {
		plDesc.vertexDescriptor.layouts[kMVKTessEvalLevelBufferIndex].stepFunction = MTLVertexStepFunctionPerPatch;
		plDesc.vertexDescriptor.layouts[kMVKTessEvalLevelBufferIndex].stride =
			reflectData.patchKind == spv::ExecutionModeTriangles ? sizeof(MTLTriangleTessellationFactorsHalf) :
																   sizeof(MTLQuadTessellationFactorsHalf);
	}

	// Tessellation state
	addTessellationToPipeline(plDesc, reflectData, pCreateInfo->pTessellationState);

	// Output
	addFragmentOutputToPipeline(plDesc, reflectData, pCreateInfo);

	return plDesc;
}

bool MVKGraphicsPipeline::verifyImplicitBuffer(bool needsBuffer, MVKShaderImplicitRezBinding& index, MVKShaderStage stage, const char* name, uint32_t reservedBuffers) {
	const char* stageNames[] = {
		"Vertex",
		"Tessellation control",
		"Tessellation evaluation",
		"Fragment"
	};
	if (needsBuffer && index.stages[stage] >= _device->_pMetalFeatures->maxPerStageBufferCount - reservedBuffers) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "%s shader requires %s buffer, but there is no free slot to pass it.", stageNames[stage], name));
		return false;
	}
	return true;
}

// Adds a vertex shader to the pipeline description.
bool MVKGraphicsPipeline::addVertexShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													const VkGraphicsPipelineCreateInfo* pCreateInfo,
													SPIRVToMSLConversionConfiguration& shaderContext) {
	uint32_t vbCnt = pCreateInfo->pVertexInputState->vertexBindingDescriptionCount;
	shaderContext.options.entryPointStage = spv::ExecutionModelVertex;
	shaderContext.options.entryPointName = _pVertexSS->pName;
	shaderContext.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageVertex];
	shaderContext.options.mslOptions.indirect_params_buffer_index = _indirectParamsIndex.stages[kMVKShaderStageVertex];
	shaderContext.options.mslOptions.shader_output_buffer_index = _outputBufferIndex.stages[kMVKShaderStageVertex];
	shaderContext.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageVertex];
	shaderContext.options.mslOptions.capture_output_to_buffer = isTessellationPipeline();
	shaderContext.options.mslOptions.disable_rasterization = isTessellationPipeline() || (pCreateInfo->pRasterizationState && (pCreateInfo->pRasterizationState->rasterizerDiscardEnable));
    addVertexInputToShaderConverterContext(shaderContext, pCreateInfo);

	MVKMTLFunction func = ((MVKShaderModule*)_pVertexSS->module)->getMTLFunction(&shaderContext, _pVertexSS->pSpecializationInfo, _pipelineCache);
	if ( !func.mtlFunction ) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Vertex shader function could not be compiled into pipeline. See previous logged error."));
		return false;
	}
	plDesc.vertexFunction = func.mtlFunction;

	auto& funcRslts = func.shaderConversionResults;
	plDesc.rasterizationEnabled = !funcRslts.isRasterizationDisabled;
	_needsVertexSwizzleBuffer = funcRslts.needsSwizzleBuffer;
	_needsVertexBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsVertexOutputBuffer = funcRslts.needsOutputBuffer;

	// If we need the swizzle buffer and there's no place to put it, we're in serious trouble.
	if (!verifyImplicitBuffer(_needsVertexSwizzleBuffer, _swizzleBufferIndex, kMVKShaderStageVertex, "swizzle", vbCnt)) {
		return false;
	}
	// Ditto buffer size buffer.
	if (!verifyImplicitBuffer(_needsVertexBufferSizeBuffer, _bufferSizeBufferIndex, kMVKShaderStageVertex, "buffer size", vbCnt)) {
		return false;
	}
	// Ditto captured output buffer.
	if (!verifyImplicitBuffer(_needsVertexOutputBuffer, _outputBufferIndex, kMVKShaderStageVertex, "output", vbCnt)) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsVertexOutputBuffer, _indirectParamsIndex, kMVKShaderStageVertex, "indirect parameters", vbCnt)) {
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addTessCtlShaderToPipeline(MTLComputePipelineDescriptor* plDesc,
													 const VkGraphicsPipelineCreateInfo* pCreateInfo,
													 SPIRVToMSLConversionConfiguration& shaderContext,
													 std::vector<SPIRVShaderOutput>& vtxOutputs) {
	shaderContext.options.entryPointStage = spv::ExecutionModelTessellationControl;
	shaderContext.options.entryPointName = _pTessCtlSS->pName;
	shaderContext.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageTessCtl];
	shaderContext.options.mslOptions.indirect_params_buffer_index = _indirectParamsIndex.stages[kMVKShaderStageTessCtl];
	shaderContext.options.mslOptions.shader_output_buffer_index = _outputBufferIndex.stages[kMVKShaderStageTessCtl];
	shaderContext.options.mslOptions.shader_patch_output_buffer_index = _tessCtlPatchOutputBufferIndex;
	shaderContext.options.mslOptions.shader_tess_factor_buffer_index = _tessCtlLevelBufferIndex;
	shaderContext.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageTessCtl];
	shaderContext.options.mslOptions.capture_output_to_buffer = true;
	addPrevStageOutputToShaderConverterContext(shaderContext, vtxOutputs);

	MVKMTLFunction func = ((MVKShaderModule*)_pTessCtlSS->module)->getMTLFunction(&shaderContext, _pTessCtlSS->pSpecializationInfo, _pipelineCache);
	if ( !func.mtlFunction ) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Tessellation control shader function could not be compiled into pipeline. See previous logged error."));
		return false;
	}
	plDesc.computeFunction = func.mtlFunction;

	auto& funcRslts = func.shaderConversionResults;
	_needsTessCtlSwizzleBuffer = funcRslts.needsSwizzleBuffer;
	_needsTessCtlBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
	_needsTessCtlOutputBuffer = funcRslts.needsOutputBuffer;
	_needsTessCtlPatchOutputBuffer = funcRslts.needsPatchOutputBuffer;
	_needsTessCtlInput = funcRslts.needsInputThreadgroupMem;

	if (!verifyImplicitBuffer(_needsTessCtlSwizzleBuffer, _swizzleBufferIndex, kMVKShaderStageTessCtl, "swizzle", kMVKTessCtlNumReservedBuffers)) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsTessCtlBufferSizeBuffer, _bufferSizeBufferIndex, kMVKShaderStageTessCtl, "buffer size", kMVKTessCtlNumReservedBuffers)) {
		return false;
	}
	if (!verifyImplicitBuffer(true, _indirectParamsIndex, kMVKShaderStageTessCtl, "indirect parameters", kMVKTessCtlNumReservedBuffers)) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsTessCtlOutputBuffer, _outputBufferIndex, kMVKShaderStageTessCtl, "per-vertex output", kMVKTessCtlNumReservedBuffers)) {
		return false;
	}
	if (_needsTessCtlPatchOutputBuffer && _tessCtlPatchOutputBufferIndex >= _device->_pMetalFeatures->maxPerStageBufferCount - kMVKTessCtlNumReservedBuffers) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Tessellation control shader requires per-patch output buffer, but there is no free slot to pass it."));
		return false;
	}
	if (_tessCtlLevelBufferIndex >= _device->_pMetalFeatures->maxPerStageBufferCount - kMVKTessCtlNumReservedBuffers) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Tessellation control shader requires tessellation level output buffer, but there is no free slot to pass it."));
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addTessEvalShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													  const VkGraphicsPipelineCreateInfo* pCreateInfo,
													  SPIRVToMSLConversionConfiguration& shaderContext,
													  std::vector<SPIRVShaderOutput>& tcOutputs) {
	shaderContext.options.entryPointStage = spv::ExecutionModelTessellationEvaluation;
	shaderContext.options.entryPointName = _pTessEvalSS->pName;
	shaderContext.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageTessEval];
	shaderContext.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageTessEval];
	shaderContext.options.mslOptions.capture_output_to_buffer = false;
	shaderContext.options.mslOptions.disable_rasterization = (pCreateInfo->pRasterizationState && (pCreateInfo->pRasterizationState->rasterizerDiscardEnable));
	addPrevStageOutputToShaderConverterContext(shaderContext, tcOutputs);

	MVKMTLFunction func = ((MVKShaderModule*)_pTessEvalSS->module)->getMTLFunction(&shaderContext, _pTessEvalSS->pSpecializationInfo, _pipelineCache);
	if ( !func.mtlFunction ) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Tessellation evaluation shader function could not be compiled into pipeline. See previous logged error."));
		return false;
	}
	// Yeah, you read that right. Tess. eval functions are a kind of vertex function in Metal.
	plDesc.vertexFunction = func.mtlFunction;

	auto& funcRslts = func.shaderConversionResults;
	plDesc.rasterizationEnabled = !funcRslts.isRasterizationDisabled;
	_needsTessEvalSwizzleBuffer = funcRslts.needsSwizzleBuffer;
	_needsTessEvalBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;

	if (!verifyImplicitBuffer(_needsTessEvalSwizzleBuffer, _swizzleBufferIndex, kMVKShaderStageTessEval, "swizzle", kMVKTessEvalNumReservedBuffers)) {
		return false;
	}
	if (!verifyImplicitBuffer(_needsTessEvalBufferSizeBuffer, _bufferSizeBufferIndex, kMVKShaderStageTessEval, "buffer size", kMVKTessEvalNumReservedBuffers)) {
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addFragmentShaderToPipeline(MTLRenderPipelineDescriptor* plDesc,
													  const VkGraphicsPipelineCreateInfo* pCreateInfo,
													  SPIRVToMSLConversionConfiguration& shaderContext) {
	if (_pFragmentSS) {
		shaderContext.options.entryPointStage = spv::ExecutionModelFragment;
		shaderContext.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageFragment];
		shaderContext.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageFragment];
		shaderContext.options.entryPointName = _pFragmentSS->pName;
		shaderContext.options.mslOptions.capture_output_to_buffer = false;

		MVKMTLFunction func = ((MVKShaderModule*)_pFragmentSS->module)->getMTLFunction(&shaderContext, _pFragmentSS->pSpecializationInfo, _pipelineCache);
		if ( !func.mtlFunction ) {
			setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "Fragment shader function could not be compiled into pipeline. See previous logged error."));
			return false;
		}
		plDesc.fragmentFunction = func.mtlFunction;

		auto& funcRslts = func.shaderConversionResults;
		_needsFragmentSwizzleBuffer = funcRslts.needsSwizzleBuffer;
		_needsFragmentBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;
		if (!verifyImplicitBuffer(_needsFragmentSwizzleBuffer, _swizzleBufferIndex, kMVKShaderStageFragment, "swizzle", 0)) {
			return false;
		}
		if (!verifyImplicitBuffer(_needsFragmentBufferSizeBuffer, _bufferSizeBufferIndex, kMVKShaderStageFragment, "buffer size", 0)) {
			return false;
		}
	}
	return true;
}

bool MVKGraphicsPipeline::addVertexInputToPipeline(MTLRenderPipelineDescriptor* plDesc,
												   const VkPipelineVertexInputStateCreateInfo* pVI,
												   const SPIRVToMSLConversionConfiguration& shaderContext) {
    // Collect extension structures
    VkPipelineVertexInputDivisorStateCreateInfoEXT* pVertexInputDivisorState = nullptr;
    auto* next = (MVKVkAPIStructHeader*)pVI->pNext;
    while (next) {
        switch (next->sType) {
        case VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_DIVISOR_STATE_CREATE_INFO_EXT:
            pVertexInputDivisorState = (VkPipelineVertexInputDivisorStateCreateInfoEXT*)next;
            next = (MVKVkAPIStructHeader*)pVertexInputDivisorState->pNext;
            break;
        default:
            next = (MVKVkAPIStructHeader*)next->pNext;
            break;
        }
    }

    // Vertex attributes
    uint32_t vaCnt = pVI->vertexAttributeDescriptionCount;
	uint32_t vbCnt = pVI->vertexBindingDescriptionCount;
    for (uint32_t i = 0; i < vaCnt; i++) {
        const VkVertexInputAttributeDescription* pVKVA = &pVI->pVertexAttributeDescriptions[i];
        if (shaderContext.isVertexAttributeLocationUsed(pVKVA->location)) {

      // Vulkan allows offsets to exceed the buffer stride, but Metal doesn't.
			// Only check non-zero offsets, as it's common for both to be zero when step rate is instance.
			if (pVKVA->offset > 0) {
				const VkVertexInputBindingDescription* pVKVB = pVI->pVertexBindingDescriptions;
				for (uint32_t j = 0; j < vbCnt; j++, pVKVB++) {
					if (pVKVB->binding == pVKVA->binding) {
						if (pVKVA->offset >= pVKVB->stride) {
							setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Under Metal, vertex attribute offsets must not exceed the vertex buffer stride."));
							return false;
						}
						break;
					}
				}
			}

			MTLVertexAttributeDescriptor* vaDesc = plDesc.vertexDescriptor.attributes[pVKVA->location];
            vaDesc.format = mvkMTLVertexFormatFromVkFormat(pVKVA->format);
            vaDesc.bufferIndex = _device->getMetalBufferIndexForVertexAttributeBinding(pVKVA->binding);
            vaDesc.offset = pVKVA->offset;
        }
    }

    // Vertex buffer bindings
    for (uint32_t i = 0; i < vbCnt; i++) {
        const VkVertexInputBindingDescription* pVKVB = &pVI->pVertexBindingDescriptions[i];
        uint32_t vbIdx = _device->getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
        if (shaderContext.isVertexBufferUsed(vbIdx)) {

			// Vulkan allows any stride, but Metal only allows multiples of 4.
            // TODO: We should try to expand the buffer to the required alignment in that case.
            if ((pVKVB->stride % 4) != 0) {
                setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Under Metal, vertex buffer strides must be aligned to four bytes."));
                return false;
            }

			MTLVertexBufferLayoutDescriptor* vbDesc = plDesc.vertexDescriptor.layouts[vbIdx];
			vbDesc.stride = (pVKVB->stride == 0) ? sizeof(simd::float4) : pVKVB->stride;      // Vulkan allows zero stride but Metal doesn't. Default to float4
            vbDesc.stepFunction = mvkMTLVertexStepFunctionFromVkVertexInputRate(pVKVB->inputRate);
            vbDesc.stepRate = 1;
        }
    }

    // Vertex buffer divisors (step rates)
    if (pVertexInputDivisorState) {
        vbCnt = pVertexInputDivisorState->vertexBindingDivisorCount;
        for (uint32_t i = 0; i < vbCnt; i++) {
            const VkVertexInputBindingDivisorDescriptionEXT* pVKVB = &pVertexInputDivisorState->pVertexBindingDivisors[i];
            uint32_t vbIdx = _device->getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
            if (shaderContext.isVertexBufferUsed(vbIdx)) {
                MTLVertexBufferLayoutDescriptor* vbDesc = plDesc.vertexDescriptor.layouts[vbIdx];
                if (vbDesc.stepFunction == MTLVertexStepFunctionPerInstance) {
                    if (pVKVB->divisor == 0)
                        vbDesc.stepFunction = MTLVertexStepFunctionConstant;
                    vbDesc.stepRate = pVKVB->divisor;
                }
            }
        }
    }

	return true;
}

void MVKGraphicsPipeline::addTessellationToPipeline(MTLRenderPipelineDescriptor* plDesc,
													const SPIRVTessReflectionData& reflectData,
													const VkPipelineTessellationStateCreateInfo* pTS) {

	VkPipelineTessellationDomainOriginStateCreateInfo* pTessDomainOriginState = nullptr;
	if (reflectData.patchKind == spv::ExecutionModeTriangles) {
		auto* next = (MVKVkAPIStructHeader*)pTS->pNext;
		while (next) {
			switch (next->sType) {
			case VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_DOMAIN_ORIGIN_STATE_CREATE_INFO:
				pTessDomainOriginState = (VkPipelineTessellationDomainOriginStateCreateInfo*)next;
				next = (MVKVkAPIStructHeader*)pTessDomainOriginState->pNext;
				break;
			default:
				next = (MVKVkAPIStructHeader*)next->pNext;
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
													  const SPIRVTessReflectionData& reflectData,
													  const VkGraphicsPipelineCreateInfo* pCreateInfo,
													  bool isTessellationVertexPipeline) {

    // Retrieve the render subpass for which this pipeline is being constructed
    MVKRenderPass* mvkRendPass = (MVKRenderPass*)pCreateInfo->renderPass;
    MVKRenderSubpass* mvkRenderSubpass = mvkRendPass->getSubpass(pCreateInfo->subpass);

	// Topology
	if (pCreateInfo->pInputAssemblyState) {
		plDesc.inputPrimitiveTopologyMVK = (isTessellationVertexPipeline || isRenderingPoints(pCreateInfo, reflectData))
												? MTLPrimitiveTopologyClassPoint
												: mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology);
	}

    // Color attachments
    uint32_t caCnt = 0;
    if (pCreateInfo->pColorBlendState) {
        for (uint32_t caIdx = 0; caIdx < pCreateInfo->pColorBlendState->attachmentCount; caIdx++) {
            const VkPipelineColorBlendAttachmentState* pCA = &pCreateInfo->pColorBlendState->pAttachments[caIdx];

            MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[caIdx];
            colorDesc.pixelFormat = getMTLPixelFormatFromVkFormat(mvkRenderSubpass->getColorAttachmentFormat(caIdx));
            colorDesc.writeMask = mvkMTLColorWriteMaskFromVkChannelFlags(pCA->colorWriteMask);
            // Don't set the blend state if we're not using this attachment.
            // The pixel format will be MTLPixelFormatInvalid in that case, and
            // Metal asserts if we turn on blending with that pixel format.
            if (mvkRenderSubpass->isColorAttachmentUsed(caIdx)) {
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
    MTLPixelFormat mtlDSFormat = getMTLPixelFormatFromVkFormat(mvkRenderSubpass->getDepthStencilFormat());
    if (mvkMTLPixelFormatIsDepthFormat(mtlDSFormat)) { plDesc.depthAttachmentPixelFormat = mtlDSFormat; }
    if (mvkMTLPixelFormatIsStencilFormat(mtlDSFormat)) { plDesc.stencilAttachmentPixelFormat = mtlDSFormat; }

    // In Vulkan, it's perfectly valid to render with no attachments. Not so
    // in Metal. If we have no attachments, then we'll have to add a dummy
    // attachment.
    if (!caCnt && !mvkMTLPixelFormatIsDepthFormat(mtlDSFormat) && !mvkMTLPixelFormatIsStencilFormat(mtlDSFormat)) {
        MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[0];
        colorDesc.pixelFormat = MTLPixelFormatR8Unorm;
        colorDesc.writeMask = MTLColorWriteMaskNone;
    }

    // Multisampling
    if (pCreateInfo->pMultisampleState) {
        plDesc.sampleCount = mvkSampleCountFromVkSampleCountFlagBits(pCreateInfo->pMultisampleState->rasterizationSamples);
        plDesc.alphaToCoverageEnabled = pCreateInfo->pMultisampleState->alphaToCoverageEnable;
        plDesc.alphaToOneEnabled = pCreateInfo->pMultisampleState->alphaToOneEnable;
    }
}

// Initializes the context used to prepare the MSL library used by this pipeline.
void MVKGraphicsPipeline::initMVKShaderConverterContext(SPIRVToMSLConversionConfiguration& shaderContext,
                                                        const VkGraphicsPipelineCreateInfo* pCreateInfo,
                                                        const SPIRVTessReflectionData& reflectData) {

    VkPipelineTessellationDomainOriginStateCreateInfo* pTessDomainOriginState = nullptr;
    if (pCreateInfo->pTessellationState) {
        auto* next = (MVKVkAPIStructHeader*)pCreateInfo->pTessellationState->pNext;
        while (next) {
            switch (next->sType) {
            case VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_DOMAIN_ORIGIN_STATE_CREATE_INFO:
                pTessDomainOriginState = (VkPipelineTessellationDomainOriginStateCreateInfo*)next;
                next = (MVKVkAPIStructHeader*)pTessDomainOriginState->pNext;
                break;
            default:
                next = (MVKVkAPIStructHeader*)next->pNext;
                break;
            }
        }
    }

    shaderContext.options.mslOptions.msl_version = _device->_pMetalFeatures->mslVersion;
    shaderContext.options.mslOptions.texel_buffer_texture_width = _device->_pMetalFeatures->maxTextureDimension;

    MVKPipelineLayout* layout = (MVKPipelineLayout*)pCreateInfo->layout;
    layout->populateShaderConverterContext(shaderContext);
    _swizzleBufferIndex = layout->getSwizzleBufferIndex();
    _bufferSizeBufferIndex = layout->getBufferSizeBufferIndex();
    _indirectParamsIndex = layout->getIndirectParamsIndex();
    _outputBufferIndex = layout->getOutputBufferIndex();
    _tessCtlPatchOutputBufferIndex = layout->getTessCtlPatchOutputBufferIndex();
    _tessCtlLevelBufferIndex = layout->getTessCtlLevelBufferIndex();

    shaderContext.options.mslOptions.enable_point_size_builtin = isRenderingPoints(pCreateInfo, reflectData);
    shaderContext.options.shouldFlipVertexY = _device->_pMVKConfig->shaderConversionFlipVertexY;
    shaderContext.options.mslOptions.swizzle_texture_samples = _fullImageViewSwizzle;
    shaderContext.options.mslOptions.tess_domain_origin_lower_left = pTessDomainOriginState && pTessDomainOriginState->domainOrigin == VK_TESSELLATION_DOMAIN_ORIGIN_LOWER_LEFT;

    shaderContext.options.tessPatchKind = reflectData.patchKind;
    shaderContext.options.numTessControlPoints = reflectData.numControlPoints;
}

// Initializes the vertex attributes in a shader converter context.
void MVKGraphicsPipeline::addVertexInputToShaderConverterContext(SPIRVToMSLConversionConfiguration& shaderContext,
                                                                 const VkGraphicsPipelineCreateInfo* pCreateInfo) {
    // Set the shader context vertex attribute information
    shaderContext.vertexAttributes.clear();
    uint32_t vaCnt = pCreateInfo->pVertexInputState->vertexAttributeDescriptionCount;
    for (uint32_t vaIdx = 0; vaIdx < vaCnt; vaIdx++) {
        const VkVertexInputAttributeDescription* pVKVA = &pCreateInfo->pVertexInputState->pVertexAttributeDescriptions[vaIdx];

        // Set binding and offset from Vulkan vertex attribute
        MSLVertexAttribute va;
        va.vertexAttribute.location = pVKVA->location;
        va.vertexAttribute.msl_buffer = _device->getMetalBufferIndexForVertexAttributeBinding(pVKVA->binding);
        va.vertexAttribute.msl_offset = pVKVA->offset;

        // Metal can't do signedness conversions on vertex buffers (rdar://45922847). If the shader
        // and the vertex attribute have mismatched signedness, we have to fix the shader
        // to match the vertex attribute. So tell SPIRV-Cross if we're expecting an unsigned format.
        // Only do this if the attribute could be reasonably expected to fit in the shader's
        // declared type. Programs that try to invoke undefined behavior are on their own.
        switch (mvkFormatTypeFromVkFormat(pVKVA->format) ) {
        case kMVKFormatColorUInt8:
            va.vertexAttribute.format = MSL_VERTEX_FORMAT_UINT8;
            break;

        case kMVKFormatColorUInt16:
            va.vertexAttribute.format = MSL_VERTEX_FORMAT_UINT16;
            break;

        case kMVKFormatDepthStencil:
            // Only some depth/stencil formats have unsigned components.
            switch (pVKVA->format) {
            case VK_FORMAT_S8_UINT:
            case VK_FORMAT_D16_UNORM_S8_UINT:
            case VK_FORMAT_D24_UNORM_S8_UINT:
            case VK_FORMAT_D32_SFLOAT_S8_UINT:
                va.vertexAttribute.format = MSL_VERTEX_FORMAT_UINT8;
                break;

            default:
                break;
            }
            break;

        default:
            break;

        }

        // Set stride and input rate of vertex attribute from corresponding Vulkan vertex bindings
        uint32_t vbCnt = pCreateInfo->pVertexInputState->vertexBindingDescriptionCount;
        for (uint32_t vbIdx = 0; vbIdx < vbCnt; vbIdx++) {
            const VkVertexInputBindingDescription* pVKVB = &pCreateInfo->pVertexInputState->pVertexBindingDescriptions[vbIdx];
            if (pVKVB->binding == pVKVA->binding) {
                va.vertexAttribute.msl_stride = pVKVB->stride;
                va.vertexAttribute.per_instance = (pVKVB->inputRate == VK_VERTEX_INPUT_RATE_INSTANCE);
                break;
            }
        }

        shaderContext.vertexAttributes.push_back(va);
    }
}

// Initializes the vertex attributes in a shader converter context from the previous stage output.
void MVKGraphicsPipeline::addPrevStageOutputToShaderConverterContext(SPIRVToMSLConversionConfiguration& shaderContext,
                                                                     std::vector<SPIRVShaderOutput>& shaderOutputs) {
    // Set the shader context vertex attribute information
    shaderContext.vertexAttributes.clear();
    uint32_t vaCnt = (uint32_t)shaderOutputs.size();
    for (uint32_t vaIdx = 0; vaIdx < vaCnt; vaIdx++) {
        MSLVertexAttribute va;
        va.vertexAttribute.location = shaderOutputs[vaIdx].location;
        va.vertexAttribute.builtin = shaderOutputs[vaIdx].builtin;

        switch (mvkFormatTypeFromVkFormat(mvkFormatFromOutput(shaderOutputs[vaIdx]) ) ) {
            case kMVKFormatColorUInt8:
                va.vertexAttribute.format = MSL_VERTEX_FORMAT_UINT8;
                break;

            case kMVKFormatColorUInt16:
                va.vertexAttribute.format = MSL_VERTEX_FORMAT_UINT16;
                break;

            default:
                break;
        }

        shaderContext.vertexAttributes.push_back(va);
    }
}

// We render points if either the topology or polygon fill mode dictate it
bool MVKGraphicsPipeline::isRenderingPoints(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData) {
	return ((pCreateInfo->pInputAssemblyState && (pCreateInfo->pInputAssemblyState->topology == VK_PRIMITIVE_TOPOLOGY_POINT_LIST)) ||
			(pCreateInfo->pRasterizationState && (pCreateInfo->pRasterizationState->polygonMode == VK_POLYGON_MODE_POINT)) ||
			(reflectData.pointMode));
}

MVKGraphicsPipeline::~MVKGraphicsPipeline() {
	[_mtlTessControlStageDesc release];

	[_mtlTessVertexStageState release];
	[_mtlTessControlStageState release];
	[_mtlTessControlStageIndex16State release];
	[_mtlTessControlStageIndex32State release];
	[_mtlPipelineState release];
}


#pragma mark -
#pragma mark MVKComputePipeline

void MVKComputePipeline::getStages(MVKVector<uint32_t>& stages) {
    stages.push_back(0);
}

void MVKComputePipeline::encode(MVKCommandEncoder* cmdEncoder, uint32_t) {
	if ( !_hasValidMTLPipelineStates ) { return; }

	[cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setComputePipelineState: _mtlPipelineState];
    cmdEncoder->_mtlThreadgroupSize = _mtlThreadgroupSize;
	cmdEncoder->_computeResourcesState.bindSwizzleBuffer(_swizzleBufferIndex, _needsSwizzleBuffer);
	cmdEncoder->_computeResourcesState.bindBufferSizeBuffer(_bufferSizeBufferIndex, _needsBufferSizeBuffer);
}

MVKComputePipeline::MVKComputePipeline(MVKDevice* device,
									   MVKPipelineCache* pipelineCache,
									   MVKPipeline* parent,
									   const VkComputePipelineCreateInfo* pCreateInfo) :
	MVKPipeline(device, pipelineCache, (MVKPipelineLayout*)pCreateInfo->layout, parent) {

	MVKMTLFunction shaderFunc = getMTLFunction(pCreateInfo);
	_mtlThreadgroupSize = shaderFunc.threadGroupSize;
	_mtlPipelineState = nil;

	if (shaderFunc.mtlFunction) {
		MTLComputePipelineDescriptor* plDesc = [[MTLComputePipelineDescriptor new] autorelease];
		plDesc.computeFunction = shaderFunc.mtlFunction;

		// Metal does not allow the name of the pipeline to be changed after it has been created,
		// and we need to create the Metal pipeline immediately to provide error feedback to app.
		// The best we can do at this point is set the pipeline name from the layout.
		setLabelIfNotNil(plDesc, ((MVKPipelineLayout*)pCreateInfo->layout)->getDebugName());

		MVKComputePipelineCompiler* plc = new MVKComputePipelineCompiler(this);
		_mtlPipelineState = plc->newMTLComputePipelineState(plDesc);	// retained
		plc->destroy();
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
}

// Returns a MTLFunction to use when creating the MTLComputePipelineState.
MVKMTLFunction MVKComputePipeline::getMTLFunction(const VkComputePipelineCreateInfo* pCreateInfo) {

    const VkPipelineShaderStageCreateInfo* pSS = &pCreateInfo->stage;
    if ( !mvkAreAllFlagsEnabled(pSS->stage, VK_SHADER_STAGE_COMPUTE_BIT) ) { return MVKMTLFunctionNull; }

    SPIRVToMSLConversionConfiguration shaderContext;
	shaderContext.options.entryPointName = pCreateInfo->stage.pName;
	shaderContext.options.entryPointStage = spv::ExecutionModelGLCompute;
    shaderContext.options.mslOptions.msl_version = _device->_pMetalFeatures->mslVersion;
    shaderContext.options.mslOptions.texel_buffer_texture_width = _device->_pMetalFeatures->maxTextureDimension;
	shaderContext.options.mslOptions.swizzle_texture_samples = _fullImageViewSwizzle;

    MVKPipelineLayout* layout = (MVKPipelineLayout*)pCreateInfo->layout;
    layout->populateShaderConverterContext(shaderContext);
    _swizzleBufferIndex = layout->getSwizzleBufferIndex();
    _bufferSizeBufferIndex = layout->getBufferSizeBufferIndex();
    shaderContext.options.mslOptions.swizzle_buffer_index = _swizzleBufferIndex.stages[kMVKShaderStageCompute];
    shaderContext.options.mslOptions.buffer_size_buffer_index = _bufferSizeBufferIndex.stages[kMVKShaderStageCompute];

    MVKMTLFunction func = ((MVKShaderModule*)pSS->module)->getMTLFunction(&shaderContext, pSS->pSpecializationInfo, _pipelineCache);

	auto& funcRslts = func.shaderConversionResults;
	_needsSwizzleBuffer = funcRslts.needsSwizzleBuffer;
    _needsBufferSizeBuffer = funcRslts.needsBufferSizeBuffer;

	return func;
}

MVKComputePipeline::~MVKComputePipeline() {
    [_mtlPipelineState release];
}


#pragma mark -
#pragma mark MVKPipelineCache

// Return a shader library from the specified shader context sourced from the specified shader module.
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
		if (memcmp(pcUUID, pDevProps->pipelineCacheUUID, VK_UUID_SIZE) != 0) { return; }

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
				opt.swizzle_buffer_index,
				opt.indirect_params_buffer_index,
				opt.shader_output_buffer_index,
				opt.shader_patch_output_buffer_index,
				opt.shader_tess_factor_buffer_index,
				opt.buffer_size_buffer_index,
				opt.shader_input_wg_index,
				opt.enable_point_size_builtin,
				opt.disable_rasterization,
				opt.capture_output_to_buffer,
				opt.swizzle_texture_samples,
				opt.tess_domain_origin_lower_left,
				opt.argument_buffers,
				opt.pad_fragment_output_components,
				opt.texture_buffer_native);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLVertexAttr& va) {
		archive(va.location,
				va.msl_buffer,
				va.msl_offset,
				va.msl_stride,
				va.per_instance,
				va.format,
				va.builtin);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLResourceBinding& rb) {
		archive(rb.stage,
				rb.desc_set,
				rb.binding,
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
				cs.compare_enable,
				cs.lod_clamp_enable,
				cs.anisotropy_enable);
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
				ep.workgroupSize.depth);
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
	void serialize(Archive & archive, MSLVertexAttribute& va) {
		archive(va.vertexAttribute,
				va.isUsedByShader);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLResourceBinding& rb) {
		archive(rb.resourceBinding,
				rb.constExprSampler,
				rb.requiresConstExprSampler,
				rb.isUsedByShader);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVToMSLConversionConfiguration& ctx) {
		archive(ctx.options, ctx.vertexAttributes, ctx.resourceBindings);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVToMSLConversionResults& scr) {
		archive(scr.entryPoint,
				scr.isRasterizationDisabled,
				scr.needsSwizzleBuffer,
				scr.needsOutputBuffer,
				scr.needsPatchOutputBuffer,
				scr.needsBufferSizeBuffer,
				scr.needsInputThreadgroupMem);
	}

}

template<class Archive>
void serialize(Archive & archive, MVKShaderModuleKey& k) {
	archive(k.codeSize, k.codeHash);
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
		[_owner->getMTLDevice() newRenderPipelineStateWithDescriptor: mtlRPLDesc
												   completionHandler: ^(id<MTLRenderPipelineState> ps, NSError* error) {
													   bool isLate = compileComplete(ps, error);
													   if (isLate) { destroy(); }
												   }];
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
		[_owner->getMTLDevice() newComputePipelineStateWithFunction: mtlFunction
												  completionHandler: ^(id<MTLComputePipelineState> ps, NSError* error) {
													  bool isLate = compileComplete(ps, error);
													  if (isLate) { destroy(); }
												  }];
	});

	return [_mtlComputePipelineState retain];
}

id<MTLComputePipelineState> MVKComputePipelineCompiler::newMTLComputePipelineState(MTLComputePipelineDescriptor* plDesc) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		[_owner->getMTLDevice() newComputePipelineStateWithDescriptor: plDesc
															  options: MTLPipelineOptionNone
													completionHandler: ^(id<MTLComputePipelineState> ps, MTLComputePipelineReflection*, NSError* error) {
														bool isLate = compileComplete(ps, error);
														if (isLate) { destroy(); }
													}];
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

