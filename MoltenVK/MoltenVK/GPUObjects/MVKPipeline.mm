/*
 * MVKPipeline.mm
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

#include "MVKPipeline.h"
#include "MVKRenderPass.h"
#include "MVKCommandBuffer.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.h"

using namespace std;


#pragma mark MVKPipelineLayout

void MVKPipelineLayout::bindDescriptorSets(MVKCommandEncoder* cmdEncoder,
                                           vector<MVKDescriptorSet*>& descriptorSets,
                                           uint32_t firstSet,
                                           vector<uint32_t>& dynamicOffsets) {

	uint32_t pDynamicOffsetIndex = 0;
	uint32_t dsCnt = (uint32_t)descriptorSets.size();
	for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
		MVKDescriptorSet* descSet = descriptorSets[dsIdx];
		uint32_t dslIdx = firstSet + dsIdx;
        _descriptorSetLayouts[dslIdx].bindDescriptorSet(cmdEncoder, descSet,
                                                        _dslMTLResourceIndexOffsets[dslIdx],
                                                        dynamicOffsets, &pDynamicOffsetIndex);
	}
	cmdEncoder->getPushConstants(VK_SHADER_STAGE_VERTEX_BIT)->setMTLBufferIndex(_pushConstantsMTLResourceIndexOffsets.vertexStage.bufferIndex);
	cmdEncoder->getPushConstants(VK_SHADER_STAGE_FRAGMENT_BIT)->setMTLBufferIndex(_pushConstantsMTLResourceIndexOffsets.fragmentStage.bufferIndex);
    cmdEncoder->getPushConstants(VK_SHADER_STAGE_COMPUTE_BIT)->setMTLBufferIndex(_pushConstantsMTLResourceIndexOffsets.computeStage.bufferIndex);
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
    mvkPopulateShaderConverterContext(context,
                                      _pushConstantsMTLResourceIndexOffsets.vertexStage,
                                      spv::ExecutionModelVertex,
                                      kPushConstDescSet,
                                      kPushConstBinding);

    mvkPopulateShaderConverterContext(context,
                                      _pushConstantsMTLResourceIndexOffsets.fragmentStage,
                                      spv::ExecutionModelFragment,
                                      kPushConstDescSet,
                                      kPushConstBinding);

    mvkPopulateShaderConverterContext(context,
                                      _pushConstantsMTLResourceIndexOffsets.computeStage,
                                      spv::ExecutionModelGLCompute,
                                      kPushConstDescSet,
                                      kPushConstBinding);
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
		_dslMTLResourceIndexOffsets.push_back(_pushConstantsMTLResourceIndexOffsets);
		_pushConstantsMTLResourceIndexOffsets += pDescSetLayout->_mtlResourceCounts;
	}

	// Add push constants
	_pushConstants.reserve(pCreateInfo->pushConstantRangeCount);
	for (uint32_t i = 0; i < pCreateInfo->pushConstantRangeCount; i++) {
		_pushConstants.push_back(pCreateInfo->pPushConstantRanges[i]);
	}
}


#pragma mark -
#pragma mark MVKGraphicsPipeline

void MVKGraphicsPipeline::encode(MVKCommandEncoder* cmdEncoder) {

	id<MTLRenderCommandEncoder> mtlCmdEnc = cmdEncoder->_mtlRenderEncoder;
    if ( !mtlCmdEnc ) { return; }   // Pre-renderpass. Come back later.

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

    if (_device->_pMetalFeatures->depthClipMode) {
        [mtlCmdEnc setDepthClipMode: _mtlDepthClipMode];
    }
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

    // Track dynamic state in _dynamicStateEnabled array
	memset(&_dynamicStateEnabled, false, sizeof(_dynamicStateEnabled));		// start with all dynamic state disabled
	const VkPipelineDynamicStateCreateInfo* pDS = pCreateInfo->pDynamicState;
	if (pDS) {
		for (uint32_t i = 0; i < pDS->dynamicStateCount; i++) {
			VkDynamicState ds = pDS->pDynamicStates[i];
			_dynamicStateEnabled[ds] = true;
		}
	}

    if (pCreateInfo->pColorBlendState) {
        memcpy(&_blendConstants, &pCreateInfo->pColorBlendState->blendConstants, sizeof(_blendConstants));
    }

    if (pCreateInfo->pInputAssemblyState) {
        _mtlPrimitiveType = mvkMTLPrimitiveTypeFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology);
    }

	// Add raster content - must occur before initMTLRenderPipelineState() for rasterizerDiscardEnable
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
            if (_device->_pMetalFeatures->depthClipMode) {
                _mtlDepthClipMode = MTLDepthClipModeClamp;
            } else {
                setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FEATURE_NOT_PRESENT, "This device does not support depth clamping."));
            }
        }
	}

	// Render pipeline state
	initMTLRenderPipelineState(pCreateInfo);

	// Depth stencil content
	_hasDepthStencilInfo = mvkSetOrClear(&_depthStencilInfo, pCreateInfo->pDepthStencilState);

	// Add viewports and scissors
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

/** Constructs the underlying Metal render pipeline. */
void MVKGraphicsPipeline::initMTLRenderPipelineState(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
    @autoreleasepool {
        _mtlPipelineState = nil;

        MTLRenderPipelineDescriptor* plDesc = getMTLRenderPipelineDescriptor(pCreateInfo);
        if (plDesc) {
            uint64_t startTime = _device->getPerformanceTimestamp();
            NSError* psError = nil;
            _mtlPipelineState = [getMTLDevice() newRenderPipelineStateWithDescriptor: plDesc error: &psError];  // retained
            if (psError) {
                setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Could not create render pipeline:\n%s.", psError.description.UTF8String));
            }
            _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.pipelineCompile, startTime);
        }
    }
}

// Returns a MTLRenderPipelineDescriptor constructed from this instance, or nil if an error occurs.
MTLRenderPipelineDescriptor* MVKGraphicsPipeline::getMTLRenderPipelineDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo) {
    SPIRVToMSLConverterContext shaderContext;
    initMVKShaderConverterContext(shaderContext, pCreateInfo);

    // Retrieve the render subpass for which this pipeline is being constructed
    MVKRenderPass* mvkRendPass = (MVKRenderPass*)pCreateInfo->renderPass;
    MVKRenderSubpass* mvkRenderSubpass = mvkRendPass->getSubpass(pCreateInfo->subpass);

    MTLRenderPipelineDescriptor* plDesc = [[MTLRenderPipelineDescriptor new] autorelease];

    // Add shader stages
    for (uint32_t i = 0; i < pCreateInfo->stageCount; i++) {
        const VkPipelineShaderStageCreateInfo* pSS = &pCreateInfo->pStages[i];

        MVKShaderModule* mvkShdrMod = (MVKShaderModule*)pSS->module;

        // Vertex shader
        if (mvkAreFlagsEnabled(pSS->stage, VK_SHADER_STAGE_VERTEX_BIT)) {
            plDesc.vertexFunction = mvkShdrMod->getMTLFunction(pSS, &shaderContext).mtlFunction;
        }

        // Fragment shader
        if (mvkAreFlagsEnabled(pSS->stage, VK_SHADER_STAGE_FRAGMENT_BIT)) {
			plDesc.fragmentFunction = mvkShdrMod->getMTLFunction(pSS, &shaderContext).mtlFunction;
        }
    }

    MTLVertexDescriptor* vtxDesc = plDesc.vertexDescriptor;

    // Vertex attributes
    MTLVertexAttributeDescriptorArray* vaArray = vtxDesc.attributes;
    uint32_t vaCnt = pCreateInfo->pVertexInputState->vertexAttributeDescriptionCount;
    for (uint32_t i = 0; i < vaCnt; i++) {
        const VkVertexInputAttributeDescription* pVKVA = &pCreateInfo->pVertexInputState->pVertexAttributeDescriptions[i];
        if (shaderContext.isVertexAttributeLocationUsed(pVKVA->location)) {
            MTLVertexAttributeDescriptor* vaDesc = vaArray[pVKVA->location];
            vaDesc.format = mvkMTLVertexFormatFromVkFormat(pVKVA->format);
            vaDesc.bufferIndex = _device->getMetalBufferIndexForVertexAttributeBinding(pVKVA->binding);
            vaDesc.offset = pVKVA->offset;
        }
    }

    // Vertex buffer bindings
    MTLVertexBufferLayoutDescriptorArray* vbArray = vtxDesc.layouts;
    uint32_t vbCnt = pCreateInfo->pVertexInputState->vertexBindingDescriptionCount;
    for (uint32_t i = 0; i < vbCnt; i++) {
        const VkVertexInputBindingDescription* pVKVB = &pCreateInfo->pVertexInputState->pVertexBindingDescriptions[i];
        uint32_t vbIdx = _device->getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
        if (shaderContext.isVertexBufferUsed(vbIdx)) {
            MTLVertexBufferLayoutDescriptor* vbDesc = vbArray[vbIdx];
            vbDesc.stride = (pVKVB->stride == 0) ? sizeof(simd::float4) : pVKVB->stride;      // Vulkan allows zero stride but Metal doesn't. Default to float4
            vbDesc.stepFunction = mvkMTLVertexStepFunctionFromVkVertexInputRate(pVKVB->inputRate);
            vbDesc.stepRate = 1;
        }
    }

    // Color attachments
    if (pCreateInfo->pColorBlendState) {
        for (uint32_t caIdx = 0; caIdx < pCreateInfo->pColorBlendState->attachmentCount; caIdx++) {
            const VkPipelineColorBlendAttachmentState* pCA = &pCreateInfo->pColorBlendState->pAttachments[caIdx];

            MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[caIdx];
            colorDesc.pixelFormat = mtlPixelFormatFromVkFormat(mvkRenderSubpass->getColorAttachmentFormat(caIdx));
            colorDesc.writeMask = mvkMTLColorWriteMaskFromVkChannelFlags(pCA->colorWriteMask);
            colorDesc.blendingEnabled = pCA->blendEnable;
            colorDesc.rgbBlendOperation = mvkMTLBlendOperationFromVkBlendOp(pCA->colorBlendOp);
            colorDesc.sourceRGBBlendFactor = mvkMTLBlendFactorFromVkBlendFactor(pCA->srcColorBlendFactor);
            colorDesc.destinationRGBBlendFactor = mvkMTLBlendFactorFromVkBlendFactor(pCA->dstColorBlendFactor);
            colorDesc.alphaBlendOperation = mvkMTLBlendOperationFromVkBlendOp(pCA->alphaBlendOp);
            colorDesc.sourceAlphaBlendFactor = mvkMTLBlendFactorFromVkBlendFactor(pCA->srcAlphaBlendFactor);
            colorDesc.destinationAlphaBlendFactor = mvkMTLBlendFactorFromVkBlendFactor(pCA->dstAlphaBlendFactor);
        }
    }

    // Depth & stencil attachments
    MTLPixelFormat mtlDSFormat = mtlPixelFormatFromVkFormat(mvkRenderSubpass->getDepthStencilFormat());
    if (mvkMTLPixelFormatIsDepthFormat(mtlDSFormat)) { plDesc.depthAttachmentPixelFormat = mtlDSFormat; }
    if (mvkMTLPixelFormatIsStencilFormat(mtlDSFormat)) { plDesc.stencilAttachmentPixelFormat = mtlDSFormat; }

    // Rasterization
    plDesc.rasterizationEnabled = !_rasterInfo.rasterizerDiscardEnable;
    if (pCreateInfo->pMultisampleState) {
        plDesc.sampleCount = mvkSampleCountFromVkSampleCountFlagBits(pCreateInfo->pMultisampleState->rasterizationSamples);
        plDesc.alphaToCoverageEnabled = pCreateInfo->pMultisampleState->alphaToCoverageEnable;
        plDesc.alphaToOneEnabled = pCreateInfo->pMultisampleState->alphaToOneEnable;
    }

#if MVK_MACOS
    if (pCreateInfo->pInputAssemblyState) {
        plDesc.inputPrimitiveTopology = mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology(pCreateInfo->pInputAssemblyState->topology);
    }
#endif

    return plDesc;
}

/** Initializes the context used to prepare the MSL library used by this pipeline. */
void MVKGraphicsPipeline::initMVKShaderConverterContext(SPIRVToMSLConverterContext& shaderContext,
                                                        const VkGraphicsPipelineCreateInfo* pCreateInfo) {

    shaderContext.options.mslVersion = _device->_pMetalFeatures->mslVersion;

    MVKPipelineLayout* layout = (MVKPipelineLayout*)pCreateInfo->layout;
    layout->populateShaderConverterContext(shaderContext);

    shaderContext.options.isRenderingPoints = (pCreateInfo->pInputAssemblyState && (pCreateInfo->pInputAssemblyState->topology == VK_PRIMITIVE_TOPOLOGY_POINT_LIST));
    shaderContext.options.shouldFlipVertexY = _device->_mvkConfig.shaderConversionFlipVertexY;

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

MVKGraphicsPipeline::~MVKGraphicsPipeline() {
	[_mtlPipelineState release];
}


#pragma mark -
#pragma mark MVKComputePipeline

void MVKComputePipeline::encode(MVKCommandEncoder* cmdEncoder) {
    [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setComputePipelineState: _mtlPipelineState];
    cmdEncoder->_mtlThreadgroupSize = _mtlThreadgroupSize;
}

MVKComputePipeline::MVKComputePipeline(MVKDevice* device,
									   MVKPipelineCache* pipelineCache,
									   MVKPipeline* parent,
									   const VkComputePipelineCreateInfo* pCreateInfo) : MVKPipeline(device, pipelineCache, parent) {
    @autoreleasepool {
        MVKMTLFunction shaderFunc = getMTLFunction(pCreateInfo);
        _mtlThreadgroupSize = shaderFunc.threadGroupSize;
        _mtlPipelineState = nil;

        NSError* psError = nil;
        uint64_t startTime = _device->getPerformanceTimestamp();
        _mtlPipelineState = [getMTLDevice() newComputePipelineStateWithFunction: shaderFunc.mtlFunction error: &psError];  // retained
        if (psError) {
            setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Could not create compute pipeline:\n%s.", psError.description.UTF8String));
        }
        _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.pipelineCompile, startTime);

    }
}

// Returns a MTLFunction to use when creating the MTLComputePipelineState.
MVKMTLFunction MVKComputePipeline::getMTLFunction(const VkComputePipelineCreateInfo* pCreateInfo) {

    const VkPipelineShaderStageCreateInfo* pSS = &pCreateInfo->stage;
    if ( !mvkAreFlagsEnabled(pSS->stage, VK_SHADER_STAGE_COMPUTE_BIT) ) { return MVKMTLFunctionNull; }

    SPIRVToMSLConverterContext shaderContext;
    shaderContext.options.mslVersion = _device->_pMetalFeatures->mslVersion;

    MVKPipelineLayout* layout = (MVKPipelineLayout*)pCreateInfo->layout;
    layout->populateShaderConverterContext(shaderContext);

    MVKShaderModule* mvkShdrMod = (MVKShaderModule*)pSS->module;
    return mvkShdrMod->getMTLFunction(pSS, &shaderContext);
}


MVKComputePipeline::~MVKComputePipeline() {
    [_mtlPipelineState release];
}
