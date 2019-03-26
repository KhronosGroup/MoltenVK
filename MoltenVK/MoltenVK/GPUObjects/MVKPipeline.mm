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
#include "mvk_datatypes.h"

#include <cereal/archives/binary.hpp>
#include <cereal/types/string.hpp>
#include <cereal/types/vector.hpp>

using namespace std;


#pragma mark MVKPipelineLayout

void MVKPipelineLayout::bindDescriptorSets(MVKCommandEncoder* cmdEncoder,
                                           MVKVector<MVKDescriptorSet*>& descriptorSets,
                                           uint32_t firstSet,
                                           MVKVector<uint32_t>& dynamicOffsets) {

	uint32_t pDynamicOffsetIndex = 0;
	uint32_t dsCnt = (uint32_t)descriptorSets.size();
	for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
		MVKDescriptorSet* descSet = descriptorSets[dsIdx];
		uint32_t dslIdx = firstSet + dsIdx;
        _descriptorSetLayouts[dslIdx].bindDescriptorSet(cmdEncoder, descSet,
                                                        _dslMTLResourceIndexOffsets[dslIdx],
                                                        dynamicOffsets, &pDynamicOffsetIndex);
	}
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
		cmdEncoder->getPushConstants(mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage(i)))->setMTLBufferIndex(_pushConstantsMTLResourceIndexes.stages[i].bufferIndex);
	}
}

void MVKPipelineLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                          MVKVector<VkWriteDescriptorSet>& descriptorWrites,
                                          uint32_t set) {

    _descriptorSetLayouts[set].pushDescriptorSet(cmdEncoder, descriptorWrites,
                                                 _dslMTLResourceIndexOffsets[set]);
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
		cmdEncoder->getPushConstants(mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage(i)))->setMTLBufferIndex(_pushConstantsMTLResourceIndexes.stages[i].bufferIndex);
	}
}

void MVKPipelineLayout::pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
                                          MVKDescriptorUpdateTemplate* descUpdateTemplate,
                                          uint32_t set,
                                          const void* pData) {

    _descriptorSetLayouts[set].pushDescriptorSet(cmdEncoder, descUpdateTemplate,
                                                 pData,
                                                 _dslMTLResourceIndexOffsets[set]);
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
		cmdEncoder->getPushConstants(mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage(i)))->setMTLBufferIndex(_pushConstantsMTLResourceIndexes.stages[i].bufferIndex);
	}
}

void MVKPipelineLayout::populateShaderConverterContext(SPIRVToMSLConverterContext& context) {
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
										  kPushConstBinding);
	}
}

MVKPipelineLayout::MVKPipelineLayout(MVKDevice* device,
                                     const VkPipelineLayoutCreateInfo* pCreateInfo) : MVKBaseDeviceObject(device) {

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
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageMax; i++) {
		_auxBufferIndex.stages[i] = _pushConstantsMTLResourceIndexes.stages[i].bufferIndex + 1;
		_indirectParamsIndex.stages[i] = _auxBufferIndex.stages[i] + 1;
		_outputBufferIndex.stages[i] = _indirectParamsIndex.stages[i] + 1;
		if (i == kMVKShaderStageTessCtl) {
			_tessCtlPatchOutputBufferIndex = _outputBufferIndex.stages[i] + 1;
			_tessCtlLevelBufferIndex = _tessCtlPatchOutputBufferIndex + 1;
		}
	}
}


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

    id<MTLRenderCommandEncoder> mtlCmdEnc = cmdEncoder->_mtlRenderEncoder;
    if ( !mtlCmdEnc ) { return; }   // Pre-renderpass. Come back later.

    switch (stage) {
        case kMVKGraphicsStageVertex:
            // Stage 1 of a tessellated draw: vertex-only pipeline with rasterization disabled.
            [mtlCmdEnc setRenderPipelineState: _mtlTessVertexStageState];
            break;

        case kMVKGraphicsStageTessControl: {
            // Stage 2 of a tessellated draw: compute pipeline to run the tess. control shader.
            // N.B. This will prematurely terminate the current subpass. We'll have to remember to start it back up again.
            const MVKIndexMTLBufferBinding& indexBuff = cmdEncoder->_graphicsResourcesState._mtlIndexBufferBinding;
            id<MTLComputePipelineState> plState;
            // Due to yet another impedance mismatch between Metal and Vulkan, which pipeline
            // state we use depends on whether or not we have an index buffer, and if we do,
            // the kind of indices in it. Furthermore, to avoid fetching the wrong attribute
            // data when there are more output vertices than input vertices, we use an
            // indexed dispatch to force each instance to fetch the correct entry.
            MTLComputePipelineDescriptor* plDesc = [[_mtlTessControlStageDesc copy] autorelease];  // Use a copy to be thread-safe.
            if (!indexBuff.mtlBuffer && getInputControlPointCount() >= getOutputControlPointCount()) {
                plState = getOrCompilePipeline(plDesc, _mtlTessControlStageState);
            } else if (indexBuff.mtlIndexType == MTLIndexTypeUInt16) {
                plDesc.stageInputDescriptor.indexType = MTLIndexTypeUInt16;
                plDesc.stageInputDescriptor.layouts[kMVKTessCtlInputBufferIndex].stepFunction = MTLStepFunctionThreadPositionInGridXIndexed;
                plState = getOrCompilePipeline(plDesc, _mtlTessControlStageIndex16State);
            } else {
                plDesc.stageInputDescriptor.indexType = MTLIndexTypeUInt32;
                plDesc.stageInputDescriptor.layouts[kMVKTessCtlInputBufferIndex].stepFunction = MTLStepFunctionThreadPositionInGridXIndexed;
                plState = getOrCompilePipeline(plDesc, _mtlTessControlStageIndex32State);
            }
            id<MTLComputeCommandEncoder> tessCtlEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationControl);
            [tessCtlEnc setComputePipelineState: plState];
            if (_needsTessCtlInput) {
                [tessCtlEnc setThreadgroupMemoryLength: getDevice()->_pProperties->limits.maxTessellationControlPerVertexInputComponents * 4 * getInputControlPointCount() atIndex: 0];
            }
            break;
        }

        // Stage 3 of a tessellated draw:
        case kMVKGraphicsStageRasterization:

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
    cmdEncoder->_graphicsResourcesState.bindAuxBuffer(_auxBufferIndex, _needsVertexAuxBuffer, _needsTessCtlAuxBuffer, _needsTessEvalAuxBuffer, _needsFragmentAuxBuffer);
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
										 const VkGraphicsPipelineCreateInfo* pCreateInfo) : MVKPipeline(device, pipelineCache, parent) {

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
			setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Failed to reflect tessellation shaders: %s", reflectErrorLog.c_str()));
			return;
		}
		// Unfortunately, we can't support line tessellation at this time.
		if (reflectData.patchKind == spv::ExecutionModeIsolines) {
			setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "Metal does not support isoline tessellation."));
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
				setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "This device does not support depth clamping."));
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
id<MTLRenderPipelineState> MVKGraphicsPipeline::getOrCompilePipeline(MTLRenderPipelineDescriptor* plDesc, id<MTLRenderPipelineState>& plState) {
	if (!plState) {
		MVKRenderPipelineCompiler* plc = new MVKRenderPipelineCompiler(_device);
		plState = plc->newMTLRenderPipelineState(plDesc);	// retained
		setConfigurationResult(plc->getConfigurationResult());
		plc->destroy();
	}
	return plState;
}

// Either returns an existing pipeline state or compiles a new one.
id<MTLComputePipelineState> MVKGraphicsPipeline::getOrCompilePipeline(MTLComputePipelineDescriptor* plDesc, id<MTLComputePipelineState>& plState) {
	if (!plState) {
		MVKComputePipelineCompiler* plc = new MVKComputePipelineCompiler(_device);
		plState = plc->newMTLComputePipelineState(plDesc);	// retained
		setConfigurationResult(plc->getConfigurationResult());
		plc->destroy();
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
		SPIRVToMSLConverterContext shaderContext;
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
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::getMTLRenderPipelineDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData) {
	SPIRVToMSLConverterContext shaderContext;
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

	return plDesc;
}

// Returns a MTLRenderPipelineDescriptor for the vertex stage of a tessellated draw constructed from this instance, or nil if an error occurs.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::getMTLTessVertexStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData, SPIRVToMSLConverterContext& shaderContext) {
	MTLRenderPipelineDescriptor* plDesc = [[MTLRenderPipelineDescriptor new] autorelease];

	// Add shader stages.
	if (!addVertexShaderToPipeline(plDesc, pCreateInfo, shaderContext)) { return nil; }

	// Vertex input
	if (!addVertexInputToPipeline(plDesc, pCreateInfo->pVertexInputState, shaderContext)) { return nil; }

	// Even though this won't be used for rasterization, we still have to set up the rasterization state to
	// match the render pass, or Metal will complain.
	addFragmentOutputToPipeline(plDesc, reflectData, pCreateInfo);

	return plDesc;
}

static uint32_t sizeOfOutput(const SPIRVShaderOutput& output) {
	uint32_t vecWidth = output.vecWidth;
	// Round up to 4 elements for 3-vectors, since that reflects how Metal lays them out.
	if (vecWidth == 3) { vecWidth = 4; }
	switch (output.baseType) {
		case spirv_cross::SPIRType::SByte:
		case spirv_cross::SPIRType::UByte:
			return 1 * vecWidth;
		case spirv_cross::SPIRType::Short:
		case spirv_cross::SPIRType::UShort:
		case spirv_cross::SPIRType::Half:
			return 2 * vecWidth;
		case spirv_cross::SPIRType::Int:
		case spirv_cross::SPIRType::UInt:
		case spirv_cross::SPIRType::Float:
		default:
			return 4 * vecWidth;
	}
}

static VkFormat mvkFormatFromOutput(const SPIRVShaderOutput& output) {
	switch (output.baseType) {
		case spirv_cross::SPIRType::SByte:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R8_SINT;
				case 2: return VK_FORMAT_R8G8_SINT;
				case 3: return VK_FORMAT_R8G8B8_SINT;
				case 4: return VK_FORMAT_R8G8B8A8_SINT;
			}
			break;
		case spirv_cross::SPIRType::UByte:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R8_UINT;
				case 2: return VK_FORMAT_R8G8_UINT;
				case 3: return VK_FORMAT_R8G8B8_UINT;
				case 4: return VK_FORMAT_R8G8B8A8_UINT;
			}
			break;
		case spirv_cross::SPIRType::Short:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R16_SINT;
				case 2: return VK_FORMAT_R16G16_SINT;
				case 3: return VK_FORMAT_R16G16B16_SINT;
				case 4: return VK_FORMAT_R16G16B16A16_SINT;
			}
			break;
		case spirv_cross::SPIRType::UShort:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R16_UINT;
				case 2: return VK_FORMAT_R16G16_UINT;
				case 3: return VK_FORMAT_R16G16B16_UINT;
				case 4: return VK_FORMAT_R16G16B16A16_UINT;
			}
			break;
		case spirv_cross::SPIRType::Half:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R16_SFLOAT;
				case 2: return VK_FORMAT_R16G16_SFLOAT;
				case 3: return VK_FORMAT_R16G16B16_SFLOAT;
				case 4: return VK_FORMAT_R16G16B16A16_SFLOAT;
			}
			break;
		case spirv_cross::SPIRType::Int:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R32_SINT;
				case 2: return VK_FORMAT_R32G32_SINT;
				case 3: return VK_FORMAT_R32G32B32_SINT;
				case 4: return VK_FORMAT_R32G32B32A32_SINT;
			}
			break;
		case spirv_cross::SPIRType::UInt:
			switch (output.vecWidth) {
				case 1: return VK_FORMAT_R32_UINT;
				case 2: return VK_FORMAT_R32G32_UINT;
				case 3: return VK_FORMAT_R32G32B32_UINT;
				case 4: return VK_FORMAT_R32G32B32A32_UINT;
			}
			break;
		case spirv_cross::SPIRType::Float:
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
MTLComputePipelineDescriptor* MVKGraphicsPipeline::getMTLTessControlStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData, SPIRVToMSLConverterContext& shaderContext) {
	MTLComputePipelineDescriptor* plDesc = [MTLComputePipelineDescriptor new];

	std::vector<SPIRVShaderOutput> vtxOutputs;
	std::string errorLog;
	// Unfortunately, MoltenVKShaderConverter doesn't know about MVKVector, so we can't use that here.
	if (!getShaderOutputs(((MVKShaderModule*)_pVertexSS->module)->getSPIRV(), spv::ExecutionModelVertex, _pVertexSS->pName, vtxOutputs, errorLog) ) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Failed to get vertex outputs: %s", errorLog.c_str()));
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

	return plDesc;
}

// Returns a MTLRenderPipelineDescriptor for the last stage of a tessellated draw constructed from this instance, or nil if an error occurs.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::getMTLTessRasterStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData, SPIRVToMSLConverterContext& shaderContext) {
	MTLRenderPipelineDescriptor* plDesc = [[MTLRenderPipelineDescriptor new] autorelease];

	std::vector<SPIRVShaderOutput> tcOutputs;
	std::string errorLog;
	if (!getShaderOutputs(((MVKShaderModule*)_pTessCtlSS->module)->getSPIRV(), spv::ExecutionModelTessellationControl, _pTessCtlSS->pName, tcOutputs, errorLog) ) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Failed to get tessellation control outputs: %s", errorLog.c_str()));
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

// Adds a vertex shader to the pipeline description.
bool MVKGraphicsPipeline::addVertexShaderToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, SPIRVToMSLConverterContext& shaderContext) {
	uint32_t vbCnt = pCreateInfo->pVertexInputState->vertexBindingDescriptionCount;
	shaderContext.options.entryPointStage = spv::ExecutionModelVertex;
	shaderContext.options.entryPointName = _pVertexSS->pName;
	shaderContext.options.auxBufferIndex = _auxBufferIndex.stages[kMVKShaderStageVertex];
	shaderContext.options.indirectParamsBufferIndex = _indirectParamsIndex.stages[kMVKShaderStageVertex];
	shaderContext.options.outputBufferIndex = _outputBufferIndex.stages[kMVKShaderStageVertex];
	shaderContext.options.shouldCaptureOutput = isTessellationPipeline();
	shaderContext.options.isRasterizationDisabled = isTessellationPipeline() || (pCreateInfo->pRasterizationState && (pCreateInfo->pRasterizationState->rasterizerDiscardEnable));
    addVertexInputToShaderConverterContext(shaderContext, pCreateInfo);
	id<MTLFunction> mtlFunction = ((MVKShaderModule*)_pVertexSS->module)->getMTLFunction(&shaderContext, _pVertexSS->pSpecializationInfo, _pipelineCache).mtlFunction;
	if ( !mtlFunction ) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Vertex shader function could not be compiled into pipeline. See previous logged error."));
		return false;
	}
	plDesc.vertexFunction = mtlFunction;
	plDesc.rasterizationEnabled = !shaderContext.options.isRasterizationDisabled;
	_needsVertexAuxBuffer = shaderContext.options.needsAuxBuffer;
	_needsVertexOutputBuffer = shaderContext.options.needsOutputBuffer;
	// If we need the auxiliary buffer and there's no place to put it, we're in serious trouble.
	if (_needsVertexAuxBuffer && _auxBufferIndex.stages[kMVKShaderStageVertex] >= _device->_pMetalFeatures->maxPerStageBufferCount - vbCnt) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Vertex shader requires auxiliary buffer, but there is no free slot to pass it."));
		return false;
	}
	// Ditto captured output buffer.
	if (_needsVertexOutputBuffer && _outputBufferIndex.stages[kMVKShaderStageVertex] >= _device->_pMetalFeatures->maxPerStageBufferCount - vbCnt) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Vertex shader requires output buffer, but there is no free slot to pass it."));
		return false;
	}
	if (_needsVertexOutputBuffer && _indirectParamsIndex.stages[kMVKShaderStageVertex] >= _device->_pMetalFeatures->maxPerStageBufferCount - vbCnt) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Vertex shader requires indirect parameters buffer, but there is no free slot to pass it."));
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addTessCtlShaderToPipeline(MTLComputePipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, SPIRVToMSLConverterContext& shaderContext, std::vector<SPIRVShaderOutput>& vtxOutputs) {
	shaderContext.options.entryPointStage = spv::ExecutionModelTessellationControl;
	shaderContext.options.entryPointName = _pTessCtlSS->pName;
	shaderContext.options.auxBufferIndex = _auxBufferIndex.stages[kMVKShaderStageTessCtl];
	shaderContext.options.indirectParamsBufferIndex = _indirectParamsIndex.stages[kMVKShaderStageTessCtl];
	shaderContext.options.outputBufferIndex = _outputBufferIndex.stages[kMVKShaderStageTessCtl];
	shaderContext.options.patchOutputBufferIndex = _tessCtlPatchOutputBufferIndex;
	shaderContext.options.tessLevelBufferIndex = _tessCtlLevelBufferIndex;
	shaderContext.options.shouldCaptureOutput = true;
	addPrevStageOutputToShaderConverterContext(shaderContext, vtxOutputs);
	id<MTLFunction> mtlFunction = ((MVKShaderModule*)_pTessCtlSS->module)->getMTLFunction(&shaderContext, _pTessCtlSS->pSpecializationInfo, _pipelineCache).mtlFunction;
	if ( !mtlFunction ) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Tessellation control shader function could not be compiled into pipeline. See previous logged error."));
		return false;
	}
	plDesc.computeFunction = mtlFunction;
	_needsTessCtlAuxBuffer = shaderContext.options.needsAuxBuffer;
	_needsTessCtlOutputBuffer = shaderContext.options.needsOutputBuffer;
	_needsTessCtlPatchOutputBuffer = shaderContext.options.needsPatchOutputBuffer;
	_needsTessCtlInput = shaderContext.options.needsInputThreadgroupMem;
	if (_needsTessCtlAuxBuffer && _auxBufferIndex.stages[kMVKShaderStageTessCtl] >= _device->_pMetalFeatures->maxPerStageBufferCount - kMVKTessCtlNumReservedBuffers) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Tessellation control shader requires auxiliary buffer, but there is no free slot to pass it."));
		return false;
	}
	if (_indirectParamsIndex.stages[kMVKShaderStageTessCtl] >= _device->_pMetalFeatures->maxPerStageBufferCount - kMVKTessCtlNumReservedBuffers) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Tessellation control shader requires indirect parameters buffer, but there is no free slot to pass it."));
		return false;
	}
	if (_needsTessCtlOutputBuffer && _outputBufferIndex.stages[kMVKShaderStageTessCtl] >= _device->_pMetalFeatures->maxPerStageBufferCount - kMVKTessCtlNumReservedBuffers) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Tessellation control shader requires per-vertex output buffer, but there is no free slot to pass it."));
		return false;
	}
	if (_needsTessCtlPatchOutputBuffer && _tessCtlPatchOutputBufferIndex >= _device->_pMetalFeatures->maxPerStageBufferCount - kMVKTessCtlNumReservedBuffers) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Tessellation control shader requires per-patch output buffer, but there is no free slot to pass it."));
		return false;
	}
	if (_tessCtlLevelBufferIndex >= _device->_pMetalFeatures->maxPerStageBufferCount - kMVKTessCtlNumReservedBuffers) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Tessellation control shader requires tessellation level output buffer, but there is no free slot to pass it."));
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addTessEvalShaderToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, SPIRVToMSLConverterContext& shaderContext, std::vector<SPIRVShaderOutput>& tcOutputs) {
	shaderContext.options.entryPointStage = spv::ExecutionModelTessellationEvaluation;
	shaderContext.options.entryPointName = _pTessEvalSS->pName;
	shaderContext.options.auxBufferIndex = _auxBufferIndex.stages[kMVKShaderStageTessEval];
	shaderContext.options.shouldCaptureOutput = false;
	shaderContext.options.isRasterizationDisabled = (pCreateInfo->pRasterizationState && (pCreateInfo->pRasterizationState->rasterizerDiscardEnable));
	addPrevStageOutputToShaderConverterContext(shaderContext, tcOutputs);
	id<MTLFunction> mtlFunction = ((MVKShaderModule*)_pTessEvalSS->module)->getMTLFunction(&shaderContext, _pTessEvalSS->pSpecializationInfo, _pipelineCache).mtlFunction;
	if ( !mtlFunction ) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Tessellation evaluation shader function could not be compiled into pipeline. See previous logged error."));
		return false;
	}
	// Yeah, you read that right. Tess. eval functions are a kind of vertex function in Metal.
	plDesc.vertexFunction = mtlFunction;
	plDesc.rasterizationEnabled = !shaderContext.options.isRasterizationDisabled;
	_needsTessEvalAuxBuffer = shaderContext.options.needsAuxBuffer;
	// If we need the auxiliary buffer and there's no place to put it, we're in serious trouble.
	if (_needsTessEvalAuxBuffer && _auxBufferIndex.stages[kMVKShaderStageTessEval] >= _device->_pMetalFeatures->maxPerStageBufferCount - kMVKTessEvalNumReservedBuffers) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Tessellation evaluation shader requires auxiliary buffer, but there is no free slot to pass it."));
		return false;
	}
	return true;
}

bool MVKGraphicsPipeline::addFragmentShaderToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, SPIRVToMSLConverterContext& shaderContext) {
	if (_pFragmentSS) {
		shaderContext.options.entryPointStage = spv::ExecutionModelFragment;
		shaderContext.options.auxBufferIndex = _auxBufferIndex.stages[kMVKShaderStageFragment];
		shaderContext.options.entryPointName = _pFragmentSS->pName;
		shaderContext.options.shouldCaptureOutput = false;
		id<MTLFunction> mtlFunction = ((MVKShaderModule*)_pFragmentSS->module)->getMTLFunction(&shaderContext, _pFragmentSS->pSpecializationInfo, _pipelineCache).mtlFunction;
		if ( !mtlFunction ) {
			setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Fragment shader function could not be compiled into pipeline. See previous logged error."));
			return false;
		}
		plDesc.fragmentFunction = mtlFunction;
		_needsFragmentAuxBuffer = shaderContext.options.needsAuxBuffer;
		if (_needsFragmentAuxBuffer && _auxBufferIndex.stages[kMVKShaderStageFragment] >= _device->_pMetalFeatures->maxPerStageBufferCount) {
			setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Fragment shader requires auxiliary buffer, but there is no free slot to pass it."));
			return false;
		}
	}
	return true;
}

bool MVKGraphicsPipeline::addVertexInputToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkPipelineVertexInputStateCreateInfo* pVI, const SPIRVToMSLConverterContext& shaderContext) {
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
							setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Under Metal, vertex attribute offsets must not exceed the vertex buffer stride."));
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
                setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Under Metal, vertex buffer strides must be aligned to four bytes."));
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

void MVKGraphicsPipeline::addTessellationToPipeline(MTLRenderPipelineDescriptor* plDesc, const SPIRVTessReflectionData& reflectData, const VkPipelineTessellationStateCreateInfo* pTS) {

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

void MVKGraphicsPipeline::addFragmentOutputToPipeline(MTLRenderPipelineDescriptor* plDesc, const SPIRVTessReflectionData& reflectData, const VkGraphicsPipelineCreateInfo* pCreateInfo) {

    // Retrieve the render subpass for which this pipeline is being constructed
    MVKRenderPass* mvkRendPass = (MVKRenderPass*)pCreateInfo->renderPass;
    MVKRenderSubpass* mvkRenderSubpass = mvkRendPass->getSubpass(pCreateInfo->subpass);

	// Topology
	if (pCreateInfo->pInputAssemblyState) {
		plDesc.inputPrimitiveTopologyMVK = isRenderingPoints(pCreateInfo, reflectData)
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
void MVKGraphicsPipeline::initMVKShaderConverterContext(SPIRVToMSLConverterContext& shaderContext,
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

    shaderContext.options.mslVersion = _device->_pMetalFeatures->mslVersion;
    shaderContext.options.texelBufferTextureWidth = _device->_pMetalFeatures->maxTextureDimension;

    MVKPipelineLayout* layout = (MVKPipelineLayout*)pCreateInfo->layout;
    layout->populateShaderConverterContext(shaderContext);
    _auxBufferIndex = layout->getAuxBufferIndex();
    _indirectParamsIndex = layout->getIndirectParamsIndex();
    _outputBufferIndex = layout->getOutputBufferIndex();
    _tessCtlPatchOutputBufferIndex = layout->getTessCtlPatchOutputBufferIndex();
    _tessCtlLevelBufferIndex = layout->getTessCtlLevelBufferIndex();

    shaderContext.options.isRenderingPoints = isRenderingPoints(pCreateInfo, reflectData);
    shaderContext.options.shouldFlipVertexY = _device->_pMVKConfig->shaderConversionFlipVertexY;
    shaderContext.options.shouldSwizzleTextureSamples = _fullImageViewSwizzle;
    shaderContext.options.tessDomainOriginInLowerLeft = pTessDomainOriginState && pTessDomainOriginState->domainOrigin == VK_TESSELLATION_DOMAIN_ORIGIN_LOWER_LEFT;

    shaderContext.options.tessPatchKind = reflectData.patchKind;
    shaderContext.options.numTessControlPoints = reflectData.numControlPoints;
}

// Initializes the vertex attributes in a shader converter context.
void MVKGraphicsPipeline::addVertexInputToShaderConverterContext(SPIRVToMSLConverterContext& shaderContext,
                                                                 const VkGraphicsPipelineCreateInfo* pCreateInfo) {
    // Set the shader context vertex attribute information
    shaderContext.vertexAttributes.clear();
    uint32_t vaCnt = pCreateInfo->pVertexInputState->vertexAttributeDescriptionCount;
    for (uint32_t vaIdx = 0; vaIdx < vaCnt; vaIdx++) {
        const VkVertexInputAttributeDescription* pVKVA = &pCreateInfo->pVertexInputState->pVertexAttributeDescriptions[vaIdx];

        // Set binding and offset from Vulkan vertex attribute
        MSLVertexAttribute va;
        va.location = pVKVA->location;
        va.mslBuffer = _device->getMetalBufferIndexForVertexAttributeBinding(pVKVA->binding);
        va.mslOffset = pVKVA->offset;

        // Metal can't do signedness conversions on vertex buffers (rdar://45922847). If the shader
        // and the vertex attribute have mismatched signedness, we have to fix the shader
        // to match the vertex attribute. So tell SPIRV-Cross if we're expecting an unsigned format.
        // Only do this if the attribute could be reasonably expected to fit in the shader's
        // declared type. Programs that try to invoke undefined behavior are on their own.
        switch (mvkFormatTypeFromVkFormat(pVKVA->format) ) {
        case kMVKFormatColorUInt8:
            va.format = MSLVertexFormat::UInt8;
            break;

        case kMVKFormatColorUInt16:
            va.format = MSLVertexFormat::UInt16;
            break;

        case kMVKFormatDepthStencil:
            // Only some depth/stencil formats have unsigned components.
            switch (pVKVA->format) {
            case VK_FORMAT_S8_UINT:
            case VK_FORMAT_D16_UNORM_S8_UINT:
            case VK_FORMAT_D24_UNORM_S8_UINT:
            case VK_FORMAT_D32_SFLOAT_S8_UINT:
                va.format = MSLVertexFormat::UInt8;
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
                va.mslStride = pVKVB->stride;
                va.isPerInstance = (pVKVB->inputRate == VK_VERTEX_INPUT_RATE_INSTANCE);
                break;
            }
        }

        shaderContext.vertexAttributes.push_back(va);
    }
}

// Initializes the vertex attributes in a shader converter context from the previous stage output.
void MVKGraphicsPipeline::addPrevStageOutputToShaderConverterContext(SPIRVToMSLConverterContext& shaderContext,
                                                                     std::vector<SPIRVShaderOutput>& shaderOutputs) {
    // Set the shader context vertex attribute information
    shaderContext.vertexAttributes.clear();
    uint32_t vaCnt = (uint32_t)shaderOutputs.size();
    for (uint32_t vaIdx = 0; vaIdx < vaCnt; vaIdx++) {
        MSLVertexAttribute va;
        va.location = shaderOutputs[vaIdx].location;
        va.builtin = shaderOutputs[vaIdx].builtin;

        switch (mvkFormatTypeFromVkFormat(mvkFormatFromOutput(shaderOutputs[vaIdx]) ) ) {
            case kMVKFormatColorUInt8:
                va.format = MSLVertexFormat::UInt8;
                break;

            case kMVKFormatColorUInt16:
                va.format = MSLVertexFormat::UInt16;
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
    [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setComputePipelineState: _mtlPipelineState];
    cmdEncoder->_mtlThreadgroupSize = _mtlThreadgroupSize;
	cmdEncoder->_computeResourcesState.bindAuxBuffer(_auxBufferIndex, _needsAuxBuffer);
}

MVKComputePipeline::MVKComputePipeline(MVKDevice* device,
									   MVKPipelineCache* pipelineCache,
									   MVKPipeline* parent,
									   const VkComputePipelineCreateInfo* pCreateInfo) : MVKPipeline(device, pipelineCache, parent) {
	MVKMTLFunction shaderFunc = getMTLFunction(pCreateInfo);
	_mtlThreadgroupSize = shaderFunc.threadGroupSize;
	_mtlPipelineState = nil;

	if (shaderFunc.mtlFunction) {
		MVKComputePipelineCompiler* plc = new MVKComputePipelineCompiler(_device);
		_mtlPipelineState = plc->newMTLComputePipelineState(shaderFunc.mtlFunction);	// retained
		setConfigurationResult(plc->getConfigurationResult());
		plc->destroy();
	} else {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Compute shader function could not be compiled into pipeline. See previous logged error."));
	}

	if (_needsAuxBuffer && _auxBufferIndex.stages[kMVKShaderStageCompute] > _device->_pMetalFeatures->maxPerStageBufferCount) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Compute shader requires auxiliary buffer, but there is no free slot to pass it."));
	}
}

// Returns a MTLFunction to use when creating the MTLComputePipelineState.
MVKMTLFunction MVKComputePipeline::getMTLFunction(const VkComputePipelineCreateInfo* pCreateInfo) {

    const VkPipelineShaderStageCreateInfo* pSS = &pCreateInfo->stage;
    if ( !mvkAreFlagsEnabled(pSS->stage, VK_SHADER_STAGE_COMPUTE_BIT) ) { return MVKMTLFunctionNull; }

    SPIRVToMSLConverterContext shaderContext;
	shaderContext.options.entryPointName = pCreateInfo->stage.pName;
	shaderContext.options.entryPointStage = spv::ExecutionModelGLCompute;
    shaderContext.options.mslVersion = _device->_pMetalFeatures->mslVersion;
	shaderContext.options.shouldSwizzleTextureSamples = _fullImageViewSwizzle;

    MVKPipelineLayout* layout = (MVKPipelineLayout*)pCreateInfo->layout;
    layout->populateShaderConverterContext(shaderContext);
    _auxBufferIndex = layout->getAuxBufferIndex();
    shaderContext.options.auxBufferIndex = _auxBufferIndex.stages[kMVKShaderStageCompute];

    MVKShaderModule* mvkShdrMod = (MVKShaderModule*)pSS->module;
    MVKMTLFunction func = mvkShdrMod->getMTLFunction(&shaderContext, pSS->pSpecializationInfo, _pipelineCache);
    _needsAuxBuffer = shaderContext.options.needsAuxBuffer;
    return func;
}

MVKComputePipeline::~MVKComputePipeline() {
    [_mtlPipelineState release];
}


#pragma mark -
#pragma mark MVKPipelineCache

// Return a shader library from the specified shader context sourced from the specified shader module.
MVKShaderLibrary* MVKPipelineCache::getShaderLibrary(SPIRVToMSLConverterContext* pContext, MVKShaderModule* shaderModule) {
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
		slCache = new MVKShaderLibraryCache(_device);
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

// Ceral archive definitions
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
	void serialize(Archive & archive, SPIRVToMSLConverterOptions& opt) {
		archive(opt.entryPointName,
				opt.entryPointStage,
				opt.mslVersion,
				opt.texelBufferTextureWidth,
				opt.auxBufferIndex,
				opt.shouldFlipVertexY,
				opt.isRenderingPoints,
				opt.shouldSwizzleTextureSamples,
				opt.isRasterizationDisabled,
				opt.needsAuxBuffer);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLVertexAttribute& va) {
		archive(va.location,
				va.mslBuffer,
				va.mslOffset,
				va.mslStride,
				va.isPerInstance,
				va.isUsedByShader);
	}

	template<class Archive>
	void serialize(Archive & archive, MSLResourceBinding& rb) {
		archive(rb.stage,
				rb.descriptorSet,
				rb.binding,
				rb.mslBuffer,
				rb.mslTexture,
				rb.mslSampler,
				rb.isUsedByShader);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVToMSLConverterContext& ctx) {
		archive(ctx.options, ctx.vertexAttributes, ctx.resourceBindings);
	}

}

template<class Archive>
void serialize(Archive & archive, MVKShaderModuleKey& k) {
	archive(k.codeSize, k.codeHash);
}

// Helper class to iterate through the shader libraries in a shader library cache in order to serialize them.
// Needs to support input of null shader library cache.
class MVKShaderCacheIterator : MVKBaseObject {
protected:
	friend MVKPipelineCache;

	bool next() { return (++_index < (_pSLCache ? _pSLCache->_shaderLibraries.size() : 0)); }
	SPIRVToMSLConverterContext& getShaderContext() { return _pSLCache->_shaderLibraries[_index].first; }
	std::string& getMSL() { return _pSLCache->_shaderLibraries[_index].second->_msl; }
	SPIRVEntryPoint& getEntryPoint() { return _pSLCache->_shaderLibraries[_index].second->_entryPoint; }
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
		return mvkNotifyErrorWithText(VK_INCOMPLETE, "Error writing pipeline cache data: %s", ex.what());
	}
}

// Serializes the data in this cache to a stream
void MVKPipelineCache::writeData(ostream& outstream, bool isCounting) {

	MVKPerformanceTracker& shaderCompilationEvent = isCounting
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
			writer(cacheIter.getShaderContext());
			writer(cacheIter.getEntryPoint());
			writer(cacheIter.getMSL());
			_device->addActivityPerformance(shaderCompilationEvent, startTime);
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

					SPIRVToMSLConverterContext shaderContext;
					reader(shaderContext);

					SPIRVEntryPoint entryPoint;
					reader(entryPoint);

					string msl;
					reader(msl);

					// Add the shader library to the staging cache.
					MVKShaderLibraryCache* slCache = getShaderLibraryCache(smKey);
					_device->addActivityPerformance(_device->_performanceStatistics.pipelineCache.readPipelineCache, startTime);
					slCache->addShaderLibrary(&shaderContext, msl, entryPoint);

					break;
				}

				default: {
					done = true;
					break;
				}
			}
		}

	} catch (cereal::Exception& ex) {
		setConfigurationResult(mvkNotifyErrorWithText(VK_SUCCESS, "Error reading pipeline cache data: %s", ex.what()));
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


#pragma mark Construction

MVKPipelineCache::MVKPipelineCache(MVKDevice* device, const VkPipelineCacheCreateInfo* pCreateInfo) : MVKBaseDeviceObject(device) {
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
		[getMTLDevice() newRenderPipelineStateWithDescriptor: mtlRPLDesc
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
		[getMTLDevice() newComputePipelineStateWithFunction: mtlFunction
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
		[getMTLDevice() newComputePipelineStateWithDescriptor: plDesc
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

