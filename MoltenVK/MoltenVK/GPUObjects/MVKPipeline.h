/*
 * MVKPipeline.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKDescriptorSet.h"
#include "MVKShaderModule.h"
#include "MVKSync.h"
#include "MVKSmallVector.h"
#include "MVKBitArray.h"
#include <MoltenVKShaderConverter/SPIRVReflection.h>
#include <MoltenVKShaderConverter/SPIRVToMSLConverter.h>
#include <unordered_map>
#include <unordered_set>
#include <ostream>

#import <Metal/Metal.h>

class MVKCommandEncoder;
class MVKPipelineCache;


#pragma mark -
#pragma mark MVKPipelineLayout

struct MVKShaderImplicitRezBinding {
	uint32_t stages[kMVKShaderStageCount];
};

/** Represents a Vulkan pipeline layout. */
class MVKPipelineLayout : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_PIPELINE_LAYOUT; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_PIPELINE_LAYOUT_EXT; }

	/** Binds descriptor sets to a command encoder. */
    void bindDescriptorSets(MVKCommandEncoder* cmdEncoder,
							VkPipelineBindPoint pipelineBindPoint,
                            MVKArrayRef<MVKDescriptorSet*> descriptorSets,
                            uint32_t firstSet,
                            MVKArrayRef<uint32_t> dynamicOffsets);

	/** Updates a descriptor set in a command encoder. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   MVKArrayRef<VkWriteDescriptorSet> descriptorWrites,
						   uint32_t set);

	/** Updates a descriptor set from a template in a command encoder. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   MVKDescriptorUpdateTemplate* descriptorUpdateTemplate,
						   uint32_t set,
						   const void* pData);

	/** Populates the specified shader conversion config. */
	void populateShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig);

	/** Returns the number of textures in this layout. This is used to calculate the size of the swizzle buffer. */
	uint32_t getTextureCount() { return _mtlResourceCounts.getMaxTextureIndex(); }

	/** Returns the number of buffers in this layout. This is used to calculate the size of the buffer size buffer. */
	uint32_t getBufferCount() { return _mtlResourceCounts.getMaxBufferIndex(); }

	/** Returns the number of descriptor sets in this pipeline layout. */
	uint32_t getDescriptorSetCount() { return (uint32_t)_descriptorSetLayouts.size(); }

	/** Returns the number of descriptors in the descriptor set layout. */
	uint32_t getDescriptorCount(uint32_t descSetIndex) { return getDescriptorSetLayout(descSetIndex)->getDescriptorCount(); }

	/** Returns the descriptor set layout. */
	MVKDescriptorSetLayout* getDescriptorSetLayout(uint32_t descSetIndex) { return _descriptorSetLayouts[descSetIndex]; }

	/** Constructs an instance for the specified device. */
	MVKPipelineLayout(MVKDevice* device, const VkPipelineLayoutCreateInfo* pCreateInfo);

	~MVKPipelineLayout() override;

protected:
	friend class MVKPipeline;

	void propagateDebugName() override {}
	bool stageUsesPushConstants(MVKShaderStage mvkStage);

	MVKSmallVector<MVKDescriptorSetLayout*, 1> _descriptorSetLayouts;
	MVKSmallVector<MVKShaderResourceBinding, 1> _dslMTLResourceIndexOffsets;
	MVKSmallVector<VkPushConstantRange> _pushConstants;
	MVKShaderResourceBinding _mtlResourceCounts;
	MVKShaderResourceBinding _pushConstantsMTLResourceIndexes;
};


#pragma mark -
#pragma mark MVKPipeline

static const uint32_t kMVKTessCtlNumReservedBuffers = 1;
static const uint32_t kMVKTessCtlInputBufferBinding = 0;

static const uint32_t kMVKTessEvalNumReservedBuffers = 3;
static const uint32_t kMVKTessEvalInputBufferBinding = 0;
static const uint32_t kMVKTessEvalPatchInputBufferBinding = 1;
static const uint32_t kMVKTessEvalLevelBufferBinding = 2;

/** Represents an abstract Vulkan pipeline. */
class MVKPipeline : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_PIPELINE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_PIPELINE_EXT; }

	/** Binds this pipeline to the specified command encoder. */
	virtual void encode(MVKCommandEncoder* cmdEncoder, uint32_t stage = 0) = 0;

	/** Binds the push constants to a command encoder. */
	void bindPushConstants(MVKCommandEncoder* cmdEncoder);

	/** Returns the current indirect parameter buffer bindings. */
	const MVKShaderImplicitRezBinding& getIndirectParamsIndex() { return _indirectParamsIndex; }

	/** Returns whether or not full image view swizzling is enabled for this pipeline. */
	bool fullImageViewSwizzle() const { return _fullImageViewSwizzle; }

	/** Returns whether all internal Metal pipeline states are valid. */
	bool hasValidMTLPipelineStates() { return _hasValidMTLPipelineStates; }

	/** Returns the MTLArgumentEncoder for the descriptor set. */
	virtual MVKMTLArgumentEncoder& getMTLArgumentEncoder(uint32_t descSetIndex, MVKShaderStage stage) = 0;

	/** Returns the array of descriptor binding use for the descriptor set. */
	virtual MVKBitArray& getDescriptorBindingUse(uint32_t descSetIndex, MVKShaderStage stage) = 0;

	/** Returns the number of descriptor sets in this pipeline layout. */
	uint32_t getDescriptorSetCount() { return _descriptorSetCount; }

	/** Constructs an instance for the device. layout, and parent (which may be NULL). */
	MVKPipeline(MVKDevice* device, MVKPipelineCache* pipelineCache, MVKPipelineLayout* layout, MVKPipeline* parent);

protected:
	void propagateDebugName() override {}
	template<typename CreateInfo> void addMTLArgumentEncoders(MVKMTLFunction& mvkMTLFunc,
															  const CreateInfo* pCreateInfo,
															  SPIRVToMSLConversionConfiguration& shaderConfig,
															  MVKShaderStage stage);

	MVKPipelineCache* _pipelineCache;
	MVKShaderImplicitRezBinding _descriptorBufferCounts;
	MVKShaderImplicitRezBinding _swizzleBufferIndex;
	MVKShaderImplicitRezBinding _bufferSizeBufferIndex;
	MVKShaderImplicitRezBinding _dynamicOffsetBufferIndex;
	MVKShaderImplicitRezBinding _indirectParamsIndex;
	MVKShaderImplicitRezBinding _pushConstantsBufferIndex;
	uint32_t _descriptorSetCount;
	bool _stageUsesPushConstants[kMVKShaderStageCount];
	bool _fullImageViewSwizzle;
	bool _hasValidMTLPipelineStates = true;

};


#pragma mark -
#pragma mark MVKGraphicsPipeline

/** Describes a buffer binding to accommodate vertex attributes with offsets greater than the stride. */
struct MVKTranslatedVertexBinding {
	uint16_t binding;
	uint16_t translationBinding;
	uint32_t translationOffset;
};

/** Describes a vertex buffer binding whose divisor is zero. */
typedef std::pair<uint32_t, uint32_t> MVKZeroDivisorVertexBinding;

typedef MVKSmallVector<MVKGraphicsStage, 4> MVKPiplineStages;

struct MVKStagedMTLArgumentEncoders {
	MVKMTLArgumentEncoder stages[4] = {};
};

struct MVKStagedDescriptorBindingUse {
	MVKBitArray stages[4] = {};
};

/** Represents an Vulkan graphics pipeline. */
class MVKGraphicsPipeline : public MVKPipeline {

public:

	/** Returns the number and order of stages in this pipeline. Draws commands must encode this pipeline once per stage. */
	void getStages(MVKPiplineStages& stages);

	/** Binds this pipeline to the specified command encoder. */
	void encode(MVKCommandEncoder* cmdEncoder, uint32_t stage = 0) override;

    /** Returns whether this pipeline permits dynamic setting of the specifie state. */
    bool supportsDynamicState(VkDynamicState state);

    /** Returns whether this pipeline has tessellation shaders. */
    bool isTessellationPipeline() { return _pTessCtlSS && _pTessEvalSS && _tessInfo.patchControlPoints > 0; }

    /** Returns the number of input tessellation patch control points. */
    uint32_t getInputControlPointCount() { return _tessInfo.patchControlPoints; }

    /** Returns the number of output tessellation patch control points. */
    uint32_t getOutputControlPointCount() { return _outputControlPointCount; }

	/** Returns the current captured output buffer bindings. */
	const MVKShaderImplicitRezBinding& getOutputBufferIndex() { return _outputBufferIndex; }

	/** Returns the current captured per-patch output buffer binding for the tess. control shader. */
	uint32_t getTessCtlPatchOutputBufferIndex() { return _tessCtlPatchOutputBufferIndex; }

	/** Returns the current tessellation level buffer binding for the tess. control shader. */
	uint32_t getTessCtlLevelBufferIndex() { return _tessCtlLevelBufferIndex; }

	/** Returns the MTLComputePipelineState object for the vertex stage of a tessellated draw with no indices. */
	id<MTLComputePipelineState> getTessVertexStageState();

	/** Returns the MTLComputePipelineState object for the vertex stage of a tessellated draw with 16-bit indices. */
	id<MTLComputePipelineState> getTessVertexStageIndex16State();

	/** Returns the MTLComputePipelineState object for the vertex stage of a tessellated draw with 32-bit indices. */
	id<MTLComputePipelineState> getTessVertexStageIndex32State();

	/** Returns the MTLComputePipelineState object for the tessellation control stage of a tessellated draw. */
	id<MTLComputePipelineState> getTessControlStageState() { return _mtlTessControlStageState; }

	/** Returns true if the vertex shader needs a buffer to store its output. */
	bool needsVertexOutputBuffer() { return _needsVertexOutputBuffer; }

	/** Returns true if the tessellation control shader needs a buffer to store its per-vertex output. */
	bool needsTessCtlOutputBuffer() { return _needsTessCtlOutputBuffer; }

	/** Returns true if the tessellation control shader needs a buffer to store its per-patch output. */
	bool needsTessCtlPatchOutputBuffer() { return _needsTessCtlPatchOutputBuffer; }

	/** Returns whether this pipeline has custom sample positions enabled. */
	bool isUsingCustomSamplePositions() { return _isUsingCustomSamplePositions; }

	/**
	 * Returns whether the MTLBuffer vertex shader buffer index is valid for a stage of this pipeline.
	 * It is if it is a descriptor binding within the descriptor binding range,
	 * or a vertex attribute binding above any implicit buffer bindings.
	 */
	bool isValidVertexBufferIndex(MVKShaderStage stage, uint32_t mtlBufferIndex);

	/** Returns the custom samples used by this pipeline. */
	MVKArrayRef<MTLSamplePosition> getCustomSamplePositions() { return _customSamplePositions.contents(); }

	/** Returns the Metal vertex buffer index to use for the specified vertex attribute binding number.  */
	uint32_t getMetalBufferIndexForVertexAttributeBinding(uint32_t binding) { return _device->getMetalBufferIndexForVertexAttributeBinding(binding); }

	/** Returns the collection of translated vertex bindings. */
	MVKArrayRef<MVKTranslatedVertexBinding> getTranslatedVertexBindings() { return _translatedVertexBindings.contents(); }

	/** Returns the collection of instance-rate vertex bindings whose divisor is zero, along with their strides. */
	MVKArrayRef<MVKZeroDivisorVertexBinding> getZeroDivisorVertexBindings() { return _zeroDivisorVertexBindings.contents(); }

	/** Returns the MTLArgumentEncoder for the descriptor set. */
	MVKMTLArgumentEncoder& getMTLArgumentEncoder(uint32_t descSetIndex, MVKShaderStage stage) override { return _mtlArgumentEncoders[descSetIndex].stages[stage]; }

	/** Returns the array of descriptor binding use for the descriptor set. */
	MVKBitArray& getDescriptorBindingUse(uint32_t descSetIndex, MVKShaderStage stage) override { return _descriptorBindingUse[descSetIndex].stages[stage]; }

	/** Constructs an instance for the device and parent (which may be NULL). */
	MVKGraphicsPipeline(MVKDevice* device,
						MVKPipelineCache* pipelineCache,
						MVKPipeline* parent,
						const VkGraphicsPipelineCreateInfo* pCreateInfo);

	~MVKGraphicsPipeline() override;

protected:
	typedef MVKSmallVector<SPIRVShaderOutput, 32> SPIRVShaderOutputs;

    id<MTLRenderPipelineState> getOrCompilePipeline(MTLRenderPipelineDescriptor* plDesc, id<MTLRenderPipelineState>& plState);
    id<MTLComputePipelineState> getOrCompilePipeline(MTLComputePipelineDescriptor* plDesc, id<MTLComputePipelineState>& plState, const char* compilerType);
	void initCustomSamplePositions(const VkGraphicsPipelineCreateInfo* pCreateInfo);
    void initMTLRenderPipelineState(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData);
    void initShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig, const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData);
	void initReservedVertexAttributeBufferCount(const VkGraphicsPipelineCreateInfo* pCreateInfo);
    void addVertexInputToShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig, const VkGraphicsPipelineCreateInfo* pCreateInfo);
    void addPrevStageOutputToShaderConversionConfig(SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderOutputs& outputs);
    MTLRenderPipelineDescriptor* newMTLRenderPipelineDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData);
    MTLComputePipelineDescriptor* newMTLTessVertexStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData, SPIRVToMSLConversionConfiguration& shaderConfig);
	MTLComputePipelineDescriptor* newMTLTessControlStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData, SPIRVToMSLConversionConfiguration& shaderConfig);
	MTLRenderPipelineDescriptor* newMTLTessRasterStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const SPIRVTessReflectionData& reflectData, SPIRVToMSLConversionConfiguration& shaderConfig);
	bool addVertexShaderToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, SPIRVToMSLConversionConfiguration& shaderConfig);
	bool addVertexShaderToPipeline(MTLComputePipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, SPIRVToMSLConversionConfiguration& shaderConfig);
	bool addTessCtlShaderToPipeline(MTLComputePipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderOutputs& prevOutput);
	bool addTessEvalShaderToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderOutputs& prevOutput);
    bool addFragmentShaderToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderOutputs& prevOutput);
	template<class T>
	bool addVertexInputToPipeline(T* inputDesc, const VkPipelineVertexInputStateCreateInfo* pVI, const SPIRVToMSLConversionConfiguration& shaderConfig);
	void adjustVertexInputForMultiview(MTLVertexDescriptor* inputDesc, const VkPipelineVertexInputStateCreateInfo* pVI, uint32_t viewCount, uint32_t oldViewCount = 1);
    void addTessellationToPipeline(MTLRenderPipelineDescriptor* plDesc, const SPIRVTessReflectionData& reflectData, const VkPipelineTessellationStateCreateInfo* pTS);
    void addFragmentOutputToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo);
    bool isRenderingPoints(const VkGraphicsPipelineCreateInfo* pCreateInfo);
    bool isRasterizationDisabled(const VkGraphicsPipelineCreateInfo* pCreateInfo);
	bool verifyImplicitBuffer(bool needsBuffer, MVKShaderImplicitRezBinding& index, MVKShaderStage stage, const char* name);
	uint32_t getTranslatedVertexBinding(uint32_t binding, uint32_t translationOffset, uint32_t maxBinding);
	uint32_t getImplicitBufferIndex(MVKShaderStage stage, uint32_t bufferIndexOffset);

	const VkPipelineShaderStageCreateInfo* _pVertexSS = nullptr;
	const VkPipelineShaderStageCreateInfo* _pTessCtlSS = nullptr;
	const VkPipelineShaderStageCreateInfo* _pTessEvalSS = nullptr;
	const VkPipelineShaderStageCreateInfo* _pFragmentSS = nullptr;

	VkPipelineTessellationStateCreateInfo _tessInfo;
	VkPipelineRasterizationStateCreateInfo _rasterInfo;
	VkPipelineDepthStencilStateCreateInfo _depthStencilInfo;

	MVKSmallVector<VkViewport, kMVKCachedViewportScissorCount> _viewports;
	MVKSmallVector<VkRect2D, kMVKCachedViewportScissorCount> _scissors;
	MVKSmallVector<VkDynamicState> _dynamicState;
	MVKSmallVector<MTLSamplePosition> _customSamplePositions;
	MVKSmallVector<MVKTranslatedVertexBinding> _translatedVertexBindings;
	MVKSmallVector<MVKZeroDivisorVertexBinding> _zeroDivisorVertexBindings;
	MVKSmallVector<MVKStagedMTLArgumentEncoders> _mtlArgumentEncoders;
	MVKSmallVector<MVKStagedDescriptorBindingUse> _descriptorBindingUse;

	MTLComputePipelineDescriptor* _mtlTessVertexStageDesc = nil;
	id<MTLFunction> _mtlTessVertexFunctions[3] = {nil, nil, nil};

	id<MTLComputePipelineState> _mtlTessVertexStageState = nil;
	id<MTLComputePipelineState> _mtlTessVertexStageIndex16State = nil;
	id<MTLComputePipelineState> _mtlTessVertexStageIndex32State = nil;
	id<MTLComputePipelineState> _mtlTessControlStageState = nil;
	id<MTLRenderPipelineState> _mtlPipelineState = nil;
	std::unordered_map<uint32_t, id<MTLRenderPipelineState>> _multiviewMTLPipelineStates;
	MTLCullMode _mtlCullMode;
	MTLWinding _mtlFrontWinding;
	MTLTriangleFillMode _mtlFillMode;
	MTLDepthClipMode _mtlDepthClipMode;
	MTLPrimitiveType _mtlPrimitiveType;

    float _blendConstants[4] = { 0.0, 0.0, 0.0, 1.0 };
    uint32_t _outputControlPointCount;
	MVKShaderImplicitRezBinding _reservedVertexAttributeBufferCount;
	MVKShaderImplicitRezBinding _viewRangeBufferIndex;
	MVKShaderImplicitRezBinding _outputBufferIndex;
	uint32_t _tessCtlPatchOutputBufferIndex = 0;
	uint32_t _tessCtlLevelBufferIndex = 0;

	bool _needsVertexSwizzleBuffer = false;
	bool _needsVertexBufferSizeBuffer = false;
	bool _needsVertexDynamicOffsetBuffer = false;
	bool _needsVertexViewRangeBuffer = false;
	bool _needsVertexOutputBuffer = false;
	bool _needsTessCtlSwizzleBuffer = false;
	bool _needsTessCtlBufferSizeBuffer = false;
	bool _needsTessCtlDynamicOffsetBuffer = false;
	bool _needsTessCtlOutputBuffer = false;
	bool _needsTessCtlPatchOutputBuffer = false;
	bool _needsTessCtlInputBuffer = false;
	bool _needsTessEvalSwizzleBuffer = false;
	bool _needsTessEvalBufferSizeBuffer = false;
	bool _needsTessEvalDynamicOffsetBuffer = false;
	bool _needsFragmentSwizzleBuffer = false;
	bool _needsFragmentBufferSizeBuffer = false;
	bool _needsFragmentDynamicOffsetBuffer = false;
	bool _needsFragmentViewRangeBuffer = false;
	bool _isRasterizing = false;
	bool _isRasterizingColor = false;
	bool _isRasterizingDepthStencil = false;
	bool _isUsingCustomSamplePositions = false;
};


#pragma mark -
#pragma mark MVKComputePipeline

/** Represents an Vulkan compute pipeline. */
class MVKComputePipeline : public MVKPipeline {

public:

	/** Binds this pipeline to the specified command encoder. */
	void encode(MVKCommandEncoder* cmdEncoder, uint32_t = 0) override;

	/** Returns if this pipeline allows non-zero dispatch bases in vkCmdDispatchBase(). */
	bool allowsDispatchBase() { return _allowsDispatchBase; }

	/** Returns the MTLArgumentEncoder for the descriptor set. */
	MVKMTLArgumentEncoder& getMTLArgumentEncoder(uint32_t descSetIndex, MVKShaderStage stage) override { return _mtlArgumentEncoders[descSetIndex]; }

	/** Returns the array of descriptor binding use for the descriptor set. */
	MVKBitArray& getDescriptorBindingUse(uint32_t descSetIndex, MVKShaderStage stage) override { return _descriptorBindingUse[descSetIndex]; }

	/** Constructs an instance for the device and parent (which may be NULL). */
	MVKComputePipeline(MVKDevice* device,
					   MVKPipelineCache* pipelineCache,
					   MVKPipeline* parent,
					   const VkComputePipelineCreateInfo* pCreateInfo);

	~MVKComputePipeline() override;

protected:
    MVKMTLFunction getMTLFunction(const VkComputePipelineCreateInfo* pCreateInfo);
	uint32_t getImplicitBufferIndex(uint32_t bufferIndexOffset);

    id<MTLComputePipelineState> _mtlPipelineState;
	MVKSmallVector<MVKMTLArgumentEncoder> _mtlArgumentEncoders;
	MVKSmallVector<MVKBitArray> _descriptorBindingUse;
    MTLSize _mtlThreadgroupSize;
    bool _needsSwizzleBuffer = false;
    bool _needsBufferSizeBuffer = false;
	bool _needsDynamicOffsetBuffer = false;
    bool _needsDispatchBaseBuffer = false;
    bool _allowsDispatchBase = false;
};


#pragma mark -
#pragma mark MVKPipelineCache

/** Represents a Vulkan pipeline cache. */
class MVKPipelineCache : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_PIPELINE_CACHE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_PIPELINE_CACHE_EXT; }

	/** 
	 * If pData is not null, serializes at most pDataSize bytes of the contents of the cache into that
	 * memory location, and returns the number of bytes serialized in pDataSize. If pData is null,
	 * returns the number of bytes required to serialize the contents of this pipeline cache.
	 */
	VkResult writeData(size_t* pDataSize, void* pData);

	/** Return a shader library from the shader conversion configuration and sourced from the specified shader module. */
	MVKShaderLibrary* getShaderLibrary(SPIRVToMSLConversionConfiguration* pContext, MVKShaderModule* shaderModule);

	/** Merges the contents of the specified number of pipeline caches into this cache. */
	VkResult mergePipelineCaches(uint32_t srcCacheCount, const VkPipelineCache* pSrcCaches);

#pragma mark Construction

	/** Constructs an instance for the specified device. */
	MVKPipelineCache(MVKDevice* device, const VkPipelineCacheCreateInfo* pCreateInfo);

	~MVKPipelineCache() override;

protected:
	void propagateDebugName() override {}
	MVKShaderLibraryCache* getShaderLibraryCache(MVKShaderModuleKey smKey);
	void readData(const VkPipelineCacheCreateInfo* pCreateInfo);
	void writeData(std::ostream& outstream, bool isCounting = false);
	void markDirty();

	std::unordered_map<MVKShaderModuleKey, MVKShaderLibraryCache*> _shaderCache;
	size_t _dataSize = 0;
	std::mutex _shaderCacheLock;
};


#pragma mark -
#pragma mark MVKRenderPipelineCompiler

/**
 * Creates a MTLRenderPipelineState from a descriptor.
 *
 * Instances of this class are one-shot, and can only be used for a single pipeline compilation.
 */
class MVKRenderPipelineCompiler : public MVKMetalCompiler {

public:

	/**
	 * Returns a new (retained) MTLRenderPipelineState object compiled from the descriptor.
	 *
	 * If the Metal pipeline compiler does not return within MVKConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLRenderPipelineState> newMTLRenderPipelineState(MTLRenderPipelineDescriptor* mtlRPLDesc);


#pragma mark Construction

	MVKRenderPipelineCompiler(MVKVulkanAPIDeviceObject* owner) : MVKMetalCompiler(owner) {
		_compilerType = "Render pipeline";
		_pPerformanceTracker = &_owner->getDevice()->_performanceStatistics.shaderCompilation.pipelineCompile;
	}

	~MVKRenderPipelineCompiler() override;

protected:
	bool compileComplete(id<MTLRenderPipelineState> pipelineState, NSError *error);

	id<MTLRenderPipelineState> _mtlRenderPipelineState = nil;
};


#pragma mark -
#pragma mark MVKComputePipelineCompiler

/**
 * Creates a MTLComputePipelineState from a MTLFunction.
 *
 * Instances of this class are one-shot, and can only be used for a single pipeline compilation.
 */
class MVKComputePipelineCompiler : public MVKMetalCompiler {

public:

	/**
	 * Returns a new (retained) MTLComputePipelineState object compiled from the MTLFunction.
	 *
	 * If the Metal pipeline compiler does not return within MVKConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLComputePipelineState> newMTLComputePipelineState(id<MTLFunction> mtlFunction);

	/**
	 * Returns a new (retained) MTLComputePipelineState object compiled from the MTLComputePipelineDescriptor.
	 *
	 * If the Metal pipeline compiler does not return within MVKConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLComputePipelineState> newMTLComputePipelineState(MTLComputePipelineDescriptor* plDesc);


#pragma mark Construction

	MVKComputePipelineCompiler(MVKVulkanAPIDeviceObject* owner, const char* compilerType = nullptr) : MVKMetalCompiler(owner) {
		_compilerType = compilerType ? compilerType : "Compute pipeline";
		_pPerformanceTracker = &_owner->getDevice()->_performanceStatistics.shaderCompilation.pipelineCompile;
	}

	~MVKComputePipelineCompiler() override;

protected:
	bool compileComplete(id<MTLComputePipelineState> pipelineState, NSError *error);

	id<MTLComputePipelineState> _mtlComputePipelineState = nil;
};
