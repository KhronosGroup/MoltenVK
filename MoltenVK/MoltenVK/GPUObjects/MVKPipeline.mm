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
#include <MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.h>
#include "MVKRenderPass.h"
#include "MVKCommandBuffer.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKStrings.h"
#include "mvk_datatypes.h"

#include <cereal/archives/binary.hpp>
#include <cereal/types/string.hpp>
#include <cereal/types/vector.hpp>

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
	_mtlPipelineState = nil;
	MTLRenderPipelineDescriptor* plDesc = getMTLRenderPipelineDescriptor(pCreateInfo);
	if (plDesc) {
		MVKRenderPipelineCompiler* plc = new MVKRenderPipelineCompiler(_device);
		_mtlPipelineState = plc->newMTLRenderPipelineState(plDesc);	// retained
		setConfigurationResult(plc->getConfigurationResult());
		plc->destroy();
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
		shaderContext.options.entryPointName = pSS->pName;

        MVKShaderModule* mvkShdrMod = (MVKShaderModule*)pSS->module;

        // Vertex shader
        if (mvkAreFlagsEnabled(pSS->stage, VK_SHADER_STAGE_VERTEX_BIT)) {
			shaderContext.options.entryPointStage = spv::ExecutionModelVertex;
			id<MTLFunction> mtlFunction = mvkShdrMod->getMTLFunction(&shaderContext, pSS->pSpecializationInfo, _pipelineCache).mtlFunction;
			if ( !mtlFunction ) {
				setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Vertex shader function could not be compiled into pipeline. See previous error."));
				return nil;
			}
			plDesc.vertexFunction = mtlFunction;
        }

        // Fragment shader
        if (mvkAreFlagsEnabled(pSS->stage, VK_SHADER_STAGE_FRAGMENT_BIT)) {
			shaderContext.options.entryPointStage = spv::ExecutionModelFragment;
			plDesc.fragmentFunction = mvkShdrMod->getMTLFunction(&shaderContext, pSS->pSpecializationInfo, _pipelineCache).mtlFunction;
        }
    }

    // Vertex attributes
    uint32_t vaCnt = pCreateInfo->pVertexInputState->vertexAttributeDescriptionCount;
    for (uint32_t i = 0; i < vaCnt; i++) {
        const VkVertexInputAttributeDescription* pVKVA = &pCreateInfo->pVertexInputState->pVertexAttributeDescriptions[i];
        if (shaderContext.isVertexAttributeLocationUsed(pVKVA->location)) {
            MTLVertexAttributeDescriptor* vaDesc = plDesc.vertexDescriptor.attributes[pVKVA->location];
            vaDesc.format = mvkMTLVertexFormatFromVkFormat(pVKVA->format);
            vaDesc.bufferIndex = _device->getMetalBufferIndexForVertexAttributeBinding(pVKVA->binding);
            vaDesc.offset = pVKVA->offset;
        }
    }

    // Vertex buffer bindings
    uint32_t vbCnt = pCreateInfo->pVertexInputState->vertexBindingDescriptionCount;
    for (uint32_t i = 0; i < vbCnt; i++) {
        const VkVertexInputBindingDescription* pVKVB = &pCreateInfo->pVertexInputState->pVertexBindingDescriptions[i];
        uint32_t vbIdx = _device->getMetalBufferIndexForVertexAttributeBinding(pVKVB->binding);
        if (shaderContext.isVertexBufferUsed(vbIdx)) {
            MTLVertexBufferLayoutDescriptor* vbDesc = plDesc.vertexDescriptor.layouts[vbIdx];
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
	MVKMTLFunction shaderFunc = getMTLFunction(pCreateInfo);
	_mtlThreadgroupSize = shaderFunc.threadGroupSize;
	_mtlPipelineState = nil;

	if (shaderFunc.mtlFunction) {
		MVKComputePipelineCompiler* plc = new MVKComputePipelineCompiler(_device);
		_mtlPipelineState = plc->newMTLComputePipelineState(shaderFunc.mtlFunction);	// retained
		setConfigurationResult(plc->getConfigurationResult());
		plc->destroy();
	} else {
		setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Compute shader function could not be compiled into pipeline. See previous error."));
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

    MVKPipelineLayout* layout = (MVKPipelineLayout*)pCreateInfo->layout;
    layout->populateShaderConverterContext(shaderContext);

    MVKShaderModule* mvkShdrMod = (MVKShaderModule*)pSS->module;
    return mvkShdrMod->getMTLFunction(&shaderContext, pSS->pSpecializationInfo, _pipelineCache);
}


MVKComputePipeline::~MVKComputePipeline() {
    [_mtlPipelineState release];
}


#pragma mark -
#pragma mark MVKPipelineCache

/** Return a shader library from the specified shader context sourced from the specified shader module. */
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
	void serialize(Archive & archive, SPIRVEntryPoint& ep) {
		archive(ep.mtlFunctionName,
				ep.workgroupSize.width,
				ep.workgroupSize.height,
				ep.workgroupSize.depth,
				ep.workgroupSizeId.width,
				ep.workgroupSizeId.height,
				ep.workgroupSizeId.depth,
				ep.workgroupSizeId.constant);
	}

	template<class Archive>
	void serialize(Archive & archive, SPIRVToMSLConverterOptions& opt) {
		archive(opt.entryPointName,
				opt.entryPointStage,
				opt.mslVersion,
				opt.shouldFlipVertexY,
				opt.isRenderingPoints);
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
											   compileComplete(ps, error);
										   }];
	});

	return [_mtlRenderPipelineState retain];
}

void MVKRenderPipelineCompiler::compileComplete(id<MTLRenderPipelineState> mtlRenderPipelineState, NSError* compileError) {
	lock_guard<mutex> lock(_completionLock);

	_mtlRenderPipelineState = [mtlRenderPipelineState retain];		// retained
	endCompile(compileError);
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
											  compileComplete(ps, error);
										  }];
	});

	return [_mtlComputePipelineState retain];
}

void MVKComputePipelineCompiler::compileComplete(id<MTLComputePipelineState> mtlComputePipelineState, NSError* compileError) {
	lock_guard<mutex> lock(_completionLock);

	_mtlComputePipelineState = [mtlComputePipelineState retain];		// retained
	endCompile(compileError);
}

#pragma mark Construction

MVKComputePipelineCompiler::~MVKComputePipelineCompiler() {
	[_mtlComputePipelineState release];
}

