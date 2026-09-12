/*
 * MVKPipeline.h
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKRenderPass.h"
#include "MVKDescriptorSet.h"
#include "MVKShaderModule.h"
#include "MVKStateTracking.h"
#include "MVKSync.h"
#include "MVKSmallVector.h"
#include "MVKBitArray.h"
#include "MVKInlineArray.h"
#include <MoltenVKShaderConverter/SPIRVReflection.h>
#include <condition_variable>
#include <dispatch/dispatch.h>
#include <MoltenVKShaderConverter/SPIRVToMSLConverter.h>
#include <unordered_map>
#include <unordered_set>
#include <ostream>

#import <Metal/Metal.h>

class MVKCommandEncoder;
class MVKPipelineCache;

struct MVKShaderImplicitRezBinding {
	uint32_t stages[kMVKShaderStageCount];
};

#pragma mark - MVKDescriptorBindOperation

enum class MVKDescriptorBindOperationCode : uint8_t {
	BindBytes,
	BindBuffer,
	BindBufferDynamic,
	BindTexture,
	BindSampler,
	BindImmutableSampler,
	BindBufferWithLiveCheck,
	BindBufferDynamicWithLiveCheck,
	BindTextureWithLiveCheck,
	BindSamplerWithLiveCheck,
	UseResource,
	UseBufferWithLiveCheck,
	UseTextureWithLiveCheck,
};

struct MVKDescriptorBindOperation {
	MVKDescriptorBindOperationCode opcode;
	uint8_t set : 4;
	uint8_t _offset : 4; /**< Offset into the first descriptor */
	uint8_t target;      /**< For BindX, the target bind index.  For UseX, whether the resource can be written or not */
	uint8_t target2;     /**< For BindBufferDynamic, the index of the dynamic offset */
	uint32_t bindingIdx; /**< The index of the MVKDescriptorBinding in the layout */
	MVKDescriptorBindOperation() = default;
	constexpr MVKDescriptorBindOperation(MVKDescriptorBindOperationCode opcode_, uint32_t set_, uint32_t target_, uint32_t bindingIdx_, size_t offset_ = 0, uint32_t target2_ = 0)
		: opcode(opcode_), set(set_), _offset(offset_ / sizeof(id)), target(target_), target2(target2_), bindingIdx(bindingIdx_)
	{
		assert(offset_ % sizeof(id) == 0);
		assert((offset_ / sizeof(id)) <= 15);
		assert(set_    <= 15);
		assert(target_ <= UINT8_MAX);
		assert(target2_ <= UINT8_MAX);
	}
	uint32_t offset() const { return _offset * sizeof(id); }
};

struct MVKPipelineBindScript {
	MVKSmallVector<MVKDescriptorBindOperation> ops;
};

#pragma mark - MVKPipelineLayout

class MVKPipelineLayout : public MVKVulkanAPIDeviceObject, public MVKInlineConstructible {
public:
	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_PIPELINE_LAYOUT; }
	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_PIPELINE_LAYOUT_EXT; }

	/** Returns the descriptor set layout. */
	MVKDescriptorSetLayout* getDescriptorSetLayout(size_t descSetIndex) const { return _descriptorSetLayouts[descSetIndex]; }
	/** Returns the starting offsets for the given descriptor set. */
	const MVKShaderResourceBinding& getResourceBindingOffsets(uint32_t descSetIndex) const { return _resourceIndexOffsets[descSetIndex]; }
	/** Returns the number of resurces for all descriptor sets combined. */
	const MVKShaderResourceBinding& getResourceCounts() const { return _mtlResourceCounts; }
	/** Returns the number of descriptor sets. */
	size_t getDescriptorSetCount() const { return _descriptorSetLayouts.size(); }
	/** Returns the list of descriptor set layouts. */
	MVKArrayRef<MVKDescriptorSetLayout*const> getDescriptorSetLayouts() const { return _descriptorSetLayouts; }
	/** Returns the size of the push constants. */
	uint32_t getPushConstantsLength() const { return _pushConstantsLength; }
	/** Returns the buffer binding index for the given push constants. */
	uint32_t getPushConstantResourceIndex(MVKShaderStage stage) const { return _pushConstantResourceIndices[stage]; }
	/** Check whether the given stage uses push constants. */
	bool stageUsesPushConstants(MVKShaderStage stage) const;
	/** Populates the specified shader conversion config. */
	void populateShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig) const;
	/** Adds all used bindings to the given bind script. */
	void populateBindOperations(MVKPipelineBindScript& script, const mvk::SPIRVToMSLConversionConfiguration& shaderConfig, spv::ExecutionModel execModel);
	/** Does this pipeline layout have a push descriptor? */
	bool hasPushDescriptor() const { return _pushDescriptor >= 0; }
	/** If this pipeline layout has a push descriptor, returns the set ID of that descriptor. */
	size_t pushDescriptor() const { assert(hasPushDescriptor()); return _pushDescriptor; }

	/** Constructs an instance for the specified device. */
	static MVKPipelineLayout* Create(MVKDevice* device, const VkPipelineLayoutCreateInfo* pCreateInfo);
	~MVKPipelineLayout();

private:
	bool boundsCheckBindOp(uint32_t bind, uint32_t count, uint32_t limit, const char *type);
	MVKInlineArray<MVKDescriptorSetLayout*> _descriptorSetLayouts;
	MVKInlineArray<MVKShaderResourceBinding> _resourceIndexOffsets;
	uint32_t _pushConstantsLength = 0;
	VkShaderStageFlags _pushConstantStages = 0;
	MVKShaderResourceBinding _mtlResourceCounts;
	uint8_t _pushConstantResourceIndices[kMVKShaderStageCount];
	int8_t _pushDescriptor = -1;
	void propagateDebugName() override {}
	friend class MVKInlineObjectConstructor<MVKPipelineLayout>;
	MVKPipelineLayout(MVKDevice* device);
};

#pragma mark -
#pragma mark MVKPipeline

/** Bytes of zeros a vertex attribute the application never bound reads its default value from. */
static const uint32_t kMVKDefaultVertexAttributeSize = 16;

/**
 * A vertex shader input the application described no attribute for.
 *
 * Vulkan defines reading one as the default attribute value, while Metal will not build a pipeline
 * whose vertex function declares an attribute the vertex descriptor does not, so each is described
 * against a buffer of zeros, in the format the shader declares it with.
 */
struct MVKDefaultVertexAttribute {
	uint32_t location;
	uint32_t mtlVertexFormat;
};

static const uint32_t kMVKTessCtlNumReservedBuffers = 1;
static const uint32_t kMVKTessCtlInputBufferBinding = 0;

static const uint32_t kMVKTessEvalNumReservedBuffers = 3;
static const uint32_t kMVKTessEvalInputBufferBinding = 0;
static const uint32_t kMVKTessEvalPatchInputBufferBinding = 1;
static const uint32_t kMVKTessEvalLevelBufferBinding = 2;

/**
 * What a pipeline built for a set of bound shader objects needs beyond a VkGraphicsPipelineCreateInfo.
 *
 * Such a pipeline has no VkPipelineCache to record itself in, and passes the binary archive of the
 * shader that will carry it instead. The rest names the transforms the key has already decided on:
 * where blendInShader is set the fragment shader carries blending and coverage, and Metal's own
 * stages are left off; where pullVertices is set the vertex shader loads its own attributes, and
 * the pipeline is built with no vertex layout. Both then read that state from a buffer per draw.
 */
struct MVKShaderObjectPipelineConfig {
	MVKMTLBinaryArchive* binaryArchive = nullptr;
	bool neverRendersPoints = false;	/**< The key names no topology, and was folded from ones that never draw points. */
	bool dynamicDepthClip = false;		/**< The vertex shader maps the depth clip convention itself. */
	bool blendInShader = false;			/**< The fragment shader carries the fragment output operations itself. */
	bool pullVertices = false;			/**< The vertex shader loads its own attributes. */
};

/** Represents an abstract Vulkan pipeline. */
class MVKPipeline : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_PIPELINE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_PIPELINE_EXT; }

	/** Returns whether all internal Metal pipeline states are valid. */
	bool hasValidMTLPipelineStates() { return _hasValidMTLPipelineStates; }

	/** Returns the number of descriptor sets in this pipeline layout. */
	uint32_t getDescriptorSetCount() { return _descriptorSetCount; }

	/** Returns the pipeline cache used by this pipeline. */
	MVKPipelineCache* getPipelineCache() { return _pipelineCache; }

	/** Returns the pipeline layout used by this pipeline. */
	MVKPipelineLayout* getLayout() const { return _layout; }

	/** Returns whether the pipeline creation fail if a pipeline compile is required. */
	bool shouldFailOnPipelineCompileRequired() {
		return (getEnabledPipelineCreationCacheControlFeatures().pipelineCreationCacheControl &&
				mvkIsAnyFlagEnabled(_flags, VK_PIPELINE_CREATE_2_FAIL_ON_PIPELINE_COMPILE_REQUIRED_BIT));
	}

	/** Returns the pipeline create flags from a pipeline create info. */
	template <typename PipelineInfoType>
	static VkPipelineCreateFlags2 getPipelineCreateFlags(const PipelineInfoType* pCreateInfo) {
		auto flags = pCreateInfo->flags;
		for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_PIPELINE_CREATE_FLAGS_2_CREATE_INFO:
					flags |= ((VkPipelineCreateFlags2CreateInfo*)next)->flags;
					break;
				default:
					break;
			}
		}
		return flags;
	}

	/** Constructs an instance for the device. layout, and parent (which may be NULL). */
	MVKPipeline(MVKDevice* device, MVKPipelineCache* pipelineCache, MVKPipelineLayout* layout,
				VkPipelineCreateFlags2 flags, MVKPipeline* parent);

	~MVKPipeline();

protected:
	void propagateDebugName() override {}

	MVKPipelineLayout* _layout;
	MVKPipelineCache* _pipelineCache;
	MVKShaderImplicitRezBinding _descriptorBufferCounts;
	VkPipelineCreateFlags2 _flags;
	uint32_t _descriptorSetCount;
	bool _stageUsesPushConstants[kMVKShaderStageCount];
	bool _hasValidMTLPipelineStates = true;

};


#pragma mark -
#pragma mark MVKGraphicsPipeline

/** Describes a buffer binding to accommodate vertex attributes with offsets greater than the stride. */
struct MVKTranslatedVertexBinding {
	uint16_t binding;
	uint16_t translationBinding;
	uint32_t translationOffset;
	uint32_t mappedAttributeCount;
};

/** Describes a vertex buffer binding whose divisor is zero. */
typedef std::pair<uint32_t, uint32_t> MVKZeroDivisorVertexBinding;

typedef MVKSmallVector<MVKGraphicsStage, 4> MVKPiplineStages;


struct MVKPipelineStageResourceInfo {
	MVKPipelineBindScript bindScript;
	MVKImplicitBufferBindings implicitBuffers;
	bool usesPhysicalStorageBufferAddresses;
	MVKStageResourceBits resources;
};

/** Represents an Vulkan graphics pipeline. */
class MVKGraphicsPipeline : public MVKPipeline {

public:

	/** Returns the number and order of stages in this pipeline. Draws commands must encode this pipeline once per stage. */
	void getStages(MVKPiplineStages& stages);

	/** Called when the pipeline is bound to a command encoder. */
	void wasBound(MVKCommandEncoder* cmdEncoder);

	/** Returns whether this pipeline has tessellation shaders. */
	bool isTessellationPipeline() { return _isTessellationPipeline; }

	/** Returns the number of output tessellation patch control points. */
	uint32_t getOutputControlPointCount() { return _outputControlPointCount; }

	/** Returns the MTLRenderPipelineState for the final stage of the pipeline */
	id<MTLRenderPipelineState> getMainPipelineState() const { return _mtlPipelineState; }

	/** Returns the MTLRenderPipelineState for the final stage of the pipeline */
	id<MTLRenderPipelineState> getMultiviewPipelineState(uint32_t mv) const {
		return _multiviewMTLPipelineStates.empty() ? _mtlPipelineState : _multiviewMTLPipelineStates.find(mv)->second;
	}

	/** Returns the MTLComputePipelineState object for the vertex stage of a tessellated draw with no indices. */
	id<MTLComputePipelineState> getTessVertexStageState() { return _mtlTessVertexStageState; }

	/** Returns the MTLComputePipelineState object for the vertex stage of a tessellated draw with 16-bit indices. */
	id<MTLComputePipelineState> getTessVertexStageIndex16State() { return _mtlTessVertexStageIndex16State; }

	/** Returns the MTLComputePipelineState object for the vertex stage of a tessellated draw with 32-bit indices. */
	id<MTLComputePipelineState> getTessVertexStageIndex32State() { return _mtlTessVertexStageIndex32State; }

	/** Returns the MTLComputePipelineState object for the tessellation control stage of a tessellated draw. */
	id<MTLComputePipelineState> getTessControlStageState() { return _mtlTessControlStageState; }

	/** Returns true if the vertex shader needs the draw ID in a buffer. */
	bool needsDrawIdBuffer() const { return _stageResources[kMVKShaderStageVertex].implicitBuffers.needed.has(MVKImplicitBuffer::DrawId); }

	/** Returns true if the vertex shader needs a buffer to store its output. */
	bool needsVertexOutputBuffer() const { return _stageResources[kMVKShaderStageVertex].implicitBuffers.needed.has(MVKImplicitBuffer::Output); }

	/** Returns true if the tessellation control shader needs a buffer to store its per-vertex output. */
	bool needsTessCtlOutputBuffer() const { return _stageResources[kMVKShaderStageTessCtl].implicitBuffers.needed.has(MVKImplicitBuffer::Output); }

	/** Returns true if the tessellation control shader needs a buffer to store its per-patch output. */
	bool needsTessCtlPatchOutputBuffer() const { return _stageResources[kMVKShaderStageTessCtl].implicitBuffers.needed.has(MVKImplicitBuffer::PatchOutput); }

	/** Returns the Vulkan primitive topology. */
	VkPrimitiveTopology getVkPrimitiveTopology() { return _vkPrimitiveTopology; }

	/** Returns the Metal vertex buffer index to use for the specified vertex attribute binding number.  */
	uint32_t getMetalBufferIndexForVertexAttributeBinding(uint32_t binding) { return _device->getMetalBufferIndexForVertexAttributeBinding(binding); }

	/** Returns the collection of translated vertex bindings. */
	MVKArrayRef<MVKTranslatedVertexBinding> getTranslatedVertexBindings() { return _translatedVertexBindings.contents(); }

	/**
	 * Returns the Metal buffer index a buffer of zeros must be bound at, or -1 if none is needed.
	 *
	 * Vulkan lets a vertex shader read a location the application never described, and defines the
	 * result as the default attribute value, while Metal requires the vertex descriptor to describe
	 * every attribute the function declares. Such locations are described against this binding.
	 */
	int32_t getDefaultVertexBufferIndex() const { return _defaultVertexBufferIndex; }

	/** Returns the collection of instance-rate vertex bindings whose divisor is zero, along with their strides. */
	MVKArrayRef<MVKZeroDivisorVertexBinding> getZeroDivisorVertexBindings() { return _zeroDivisorVertexBindings.contents(); }

	/** Check if rasterization is disabled. */
	bool isRasterizationDisabled() const { return !_isRasterizing; }

	/** Returns a list of implicit buffers used by the given stage. */
	const MVKImplicitBufferBindings& getImplicitBuffers(MVKShaderStage stage) const { return getStageResources(stage).implicitBuffers; }

	/** Returns info about the given stage's bindings. */
	const MVKPipelineStageResourceInfo& getStageResources(MVKShaderStage stage) const { return _stageResources[stage]; }

	/** Returns the list of state that is needed from the command encoder */
	const MVKRenderStateFlags& getDynamicStateFlags() const { return _dynamicStateFlags; }
	/** Returns the list of state that is stored on the pipeline */
	const MVKRenderStateFlags& getStaticStateFlags() const { return _staticStateFlags; }
	/** Returns the state data that is stored on the pipeline */
	const MVKRenderStateData& getStaticStateData() const { return _staticStateData; }
	/** Returns a list of the vertex buffers used by this pipeline by Vulkan buffer ID */
	const MVKStaticBitSet<kMVKMaxBufferCount>& getVkVertexBuffers() const { return _vkVertexBuffers; }
	/** Returns a list of the vertex buffers used by this pipeline by Metal buffer ID */
	const MVKStaticBitSet<kMVKMaxBufferCount>& getMtlVertexBuffers() const { return _mtlVertexBuffers; }
	const VkViewport* getViewports() const { return _viewports; }
	const VkRect2D* getScissors() const { return _scissors; }
	const MTLSamplePosition* getSampleLocations() const { return _sampleLocations; }
	const MTLPrimitiveTopologyClass getPrimitiveTopologyClass() const { return static_cast<MTLPrimitiveTopologyClass>(_primitiveTopologyClass); }

	/**
	 * Constructs an instance for the device and parent (which may be NULL). A pipeline built for
	 * a set of shader objects passes the extra it needs, which vkCreateGraphicsPipelines does not.
	 */
	MVKGraphicsPipeline(MVKDevice* device,
						MVKPipelineCache* pipelineCache,
						MVKPipeline* parent,
						const VkGraphicsPipelineCreateInfo* pCreateInfo,
						const MVKShaderObjectPipelineConfig& soConfig = {});

	/** Returns whether the vertex shader was rewritten to load its own attributes. */
	bool isPullingVertices() const { return _isPullingVertices; }

	/** Returns whether the fragment shader was rewritten to blend its own outputs. */
	bool isBlendInShader() const { return _isBlendInShader; }

	/** Returns the per-attachment clamp modes the in-shader blend applies, indexed by location. */
	const uint8_t* getBlendClampModes() const { return _blendClampModes; }

	~MVKGraphicsPipeline() override;

protected:
	typedef MVKSmallVector<mvk::SPIRVShaderInterfaceVariable, 32> SPIRVShaderOutputs;
	typedef MVKSmallVector<mvk::SPIRVShaderInterfaceVariable, 32> SPIRVShaderInputs;

    id<MTLRenderPipelineState> getOrCompilePipeline(MTLRenderPipelineDescriptor* plDesc, id<MTLRenderPipelineState>& plState);
    id<MTLComputePipelineState> getOrCompilePipeline(MTLComputePipelineDescriptor* plDesc, id<MTLComputePipelineState>& plState, const char* compilerType);
	bool compileTessVertexStageState(MTLComputePipelineDescriptor* vtxPLDesc, MVKMTLFunction* pVtxFunctions, VkPipelineCreationFeedback* pVertexFB);
	bool compileTessControlStageState(MTLComputePipelineDescriptor* tcPLDesc, VkPipelineCreationFeedback* pTessCtlFB);
	void initDynamicState(const VkGraphicsPipelineCreateInfo* pCreateInfo);
	void initSampleLocations(const VkGraphicsPipelineCreateInfo* pCreateInfo);
    void initMTLRenderPipelineState(const VkGraphicsPipelineCreateInfo* pCreateInfo, const mvk::SPIRVTessReflectionData& reflectData, VkPipelineCreationFeedback* pPipelineFB, const VkPipelineShaderStageCreateInfo* pVertexSS, VkPipelineCreationFeedback* pVertexFB, const VkPipelineShaderStageCreateInfo* pTessCtlSS, VkPipelineCreationFeedback* pTessCtlFB, const VkPipelineShaderStageCreateInfo* pTessEvalSS, VkPipelineCreationFeedback* pTessEvalFB, const VkPipelineShaderStageCreateInfo* pFragmentSS, VkPipelineCreationFeedback* pFragmentFB);
    void initShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig, const VkGraphicsPipelineCreateInfo* pCreateInfo, const mvk::SPIRVTessReflectionData& reflectData);
	void initReservedVertexAttributeBufferCount(const VkGraphicsPipelineCreateInfo* pCreateInfo);
    void addVertexInputToShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig, const VkGraphicsPipelineCreateInfo* pCreateInfo);
    void addNextStageInputToShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderInputs& inputs);
    void addPrevStageOutputToShaderConversionConfig(mvk::SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderOutputs& outputs);
    MTLRenderPipelineDescriptor* newMTLRenderPipelineDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const mvk::SPIRVTessReflectionData& reflectData, const VkPipelineShaderStageCreateInfo* pVertexSS, VkPipelineCreationFeedback* pVertexFB, const VkPipelineShaderStageCreateInfo* pFragmentSS, VkPipelineCreationFeedback* pFragmentFB);
    MTLComputePipelineDescriptor* newMTLTessVertexStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const mvk::SPIRVTessReflectionData& reflectData, mvk::SPIRVToMSLConversionConfiguration& shaderConfig, const VkPipelineShaderStageCreateInfo* pVertexSS, VkPipelineCreationFeedback* pVertexFB, const VkPipelineShaderStageCreateInfo* pTessCtlSS, MVKMTLFunction* pVtxFunctions);
	MTLComputePipelineDescriptor* newMTLTessControlStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const mvk::SPIRVTessReflectionData& reflectData, mvk::SPIRVToMSLConversionConfiguration& shaderConfig, const VkPipelineShaderStageCreateInfo* pTessCtlSS, VkPipelineCreationFeedback* pTessCtlFB, const VkPipelineShaderStageCreateInfo* pVertexSS, const VkPipelineShaderStageCreateInfo* pTessEvalSS);
	MTLRenderPipelineDescriptor* newMTLTessRasterStageDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo, const mvk::SPIRVTessReflectionData& reflectData, mvk::SPIRVToMSLConversionConfiguration& shaderConfig, const VkPipelineShaderStageCreateInfo* pTessEvalSS, VkPipelineCreationFeedback* pTessEvalFB, const VkPipelineShaderStageCreateInfo* pFragmentSS, VkPipelineCreationFeedback* pFragmentFB, const VkPipelineShaderStageCreateInfo* pTessCtlSS);
	bool addVertexShaderToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, mvk::SPIRVToMSLConversionConfiguration& shaderConfig, const VkPipelineShaderStageCreateInfo* pVertexSS, VkPipelineCreationFeedback* pVertexFB, const VkPipelineShaderStageCreateInfo*& pFragmentSS);
	bool addVertexShaderToPipeline(MTLComputePipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, mvk::SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderInputs& nextInputs, const VkPipelineShaderStageCreateInfo* pVertexSS, VkPipelineCreationFeedback* pVertexFB, MVKMTLFunction* pVtxFunctions);
	bool addTessCtlShaderToPipeline(MTLComputePipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, mvk::SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderOutputs& prevOutput, SPIRVShaderInputs& nextInputs, const VkPipelineShaderStageCreateInfo* pTessCtlSS, VkPipelineCreationFeedback* pTessCtlFB);
	bool addTessEvalShaderToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, mvk::SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderOutputs& prevOutput, const VkPipelineShaderStageCreateInfo* pTessEvalSS, VkPipelineCreationFeedback* pTessEvalFB, const VkPipelineShaderStageCreateInfo*& pFragmentSS);
    bool addFragmentShaderToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo, mvk::SPIRVToMSLConversionConfiguration& shaderConfig, SPIRVShaderOutputs& prevOutput, const VkPipelineShaderStageCreateInfo* pFragmentSS, VkPipelineCreationFeedback* pFragmentFB);
	template<class T>
	bool addVertexInputToPipeline(T* inputDesc, const VkPipelineVertexInputStateCreateInfo* pVI, const mvk::SPIRVToMSLConversionConfiguration& shaderConfig);
	void initDefaultVertexAttributes(const VkPipelineVertexInputStateCreateInfo* pVI, const char* pVtxEntryName);
	void adjustVertexInputForMultiview(MTLVertexDescriptor* inputDesc, const VkPipelineVertexInputStateCreateInfo* pVI, uint32_t viewCount, uint32_t oldViewCount = 1);
    void addTessellationToPipeline(MTLRenderPipelineDescriptor* plDesc, const mvk::SPIRVTessReflectionData& reflectData, const VkPipelineTessellationStateCreateInfo* pTS);
    void addFragmentOutputToPipeline(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo);
    bool isRenderingPoints();
    bool isRasterizationDisabled(const VkGraphicsPipelineCreateInfo* pCreateInfo);
    bool isDepthClipNegativeOneToOne(const VkGraphicsPipelineCreateInfo* pCreateInfo);
	bool verifyImplicitBuffers(MVKShaderStage stage);
	uint32_t getTranslatedVertexBinding(uint32_t binding, uint32_t translationOffset, uint32_t maxBinding);
	uint32_t getImplicitBufferIndex(MVKShaderStage stage, uint32_t bufferIndexOffset);
	MVKMTLFunction getMTLFunction(mvk::SPIRVToMSLConversionConfiguration& shaderConfig,
								  const VkPipelineShaderStageCreateInfo* pShaderStage,
								  VkPipelineCreationFeedback* pStageFB,
								  MVKShaderModule* pShaderModule,
								  const char* pStageName);
	void populateRenderingAttachmentInfo(const VkGraphicsPipelineCreateInfo* pCreateInfo);

	MVKRenderStateFlags _dynamicStateFlags;
	MVKRenderStateFlags _staticStateFlags;
	MVKRenderStateData _staticStateData;

	VkViewport _viewports[kMVKMaxViewportScissorCount];
	VkRect2D _scissors[kMVKMaxViewportScissorCount];
	MTLSamplePosition _sampleLocations[kMVKMaxSampleCount];
	MVKSmallVector<MVKTranslatedVertexBinding> _translatedVertexBindings;
	MVKSmallVector<MVKDefaultVertexAttribute, 4> _defaultVertexAttributes;
	int32_t _defaultVertexBufferIndex = -1;
	MVKSmallVector<MVKZeroDivisorVertexBinding> _zeroDivisorVertexBindings;
	MVKSmallVector<MVKShaderStage> _stagesUsingPhysicalStorageBufferAddressesCapability;
	MVKSmallVector<uint32_t, kMVKDefaultAttachmentCount> _colorAttachmentLocations;
	std::unordered_map<uint32_t, id<MTLRenderPipelineState>> _multiviewMTLPipelineStates;
	MVKStaticBitSet<kMVKMaxBufferCount> _vkVertexBuffers;
	MVKStaticBitSet<kMVKMaxBufferCount> _mtlVertexBuffers;
	MVKPipelineStageResourceInfo _stageResources[kMVKShaderStageFragment + 1] = {};

	id<MTLComputePipelineState> _mtlTessVertexStageState = nil;
	id<MTLComputePipelineState> _mtlTessVertexStageIndex16State = nil;
	id<MTLComputePipelineState> _mtlTessVertexStageIndex32State = nil;
	id<MTLComputePipelineState> _mtlTessControlStageState = nil;
	id<MTLRenderPipelineState> _mtlPipelineState = nil;

	MVKShaderImplicitRezBinding _reservedVertexAttributeBufferCount;
	VkPrimitiveTopology _vkPrimitiveTopology;
	uint32_t _outputControlPointCount;

	MVKShaderModule* _vertexModule = nullptr;
	MVKShaderModule* _tessCtlModule = nullptr;
	MVKShaderModule* _tessEvalModule = nullptr;
	MVKShaderModule* _fragmentModule = nullptr;
	bool _ownsVertexModule = false;
	bool _ownsTessCtlModule = false;
	bool _ownsTessEvalModule = false;
	bool _ownsFragmentModule = false;

	// Set only for a pipeline built for shader objects, which records itself here instead of in a
	// pipeline cache, so that the shader that carries it can hand it back in its binary.
	MVKMTLBinaryArchive* _binaryArchive = nullptr;

	// A pipeline that leaves its topology class unspecified rasterizes lines and triangles alike,
	// and is told here that it will never be asked for points, which keeps the point size out of
	// the shader that an unspecified class would otherwise call for.
	bool _neverRendersPoints = false;

	// A shader object draw can change the depth clip convention, so the shader is asked to read it
	// from the state the draw supplies rather than have it baked in.
	bool _dynamicDepthClipRequested = false;

	uint8_t _primitiveTopologyClass;
	bool _blendInShaderRequested = false;
	bool _isBlendInShader = false;
	bool _pullVerticesRequested = false;
	bool _isPullingVertices = false;
	uint8_t _blendClampModes[kMVKMaxColorAttachmentCount] = {};
	bool _isRasterizing = false;
	bool _isRasterizingColor = false;
	bool _isTessellationPipeline = false;
	bool _inputAttachmentIsDSAttachment = false;
	bool _hasRemappedAttachmentLocations = false;
};


#pragma mark -
#pragma mark MVKShaderObjectPipelines

class MVKShader;
class MVKComputePipeline;

/**
 * Everything a set of bound shader objects must be paired with to make a Metal pipeline.
 *
 * Vulkan lets a shader object defer all of this to draw time, while Metal needs it before a
 * MTLRenderPipelineState can be built, so a draw can only be served by a pipeline built for
 * these exact values. The struct is plain data with no padding left uninitialized, so it can
 * be hashed and compared as raw bytes.
 */
struct MVKShaderObjectPipelineKey {
	MVKShader* shaders[kMVKShaderStageCount];
	MVKDynamicVertexInput vertexInput;
	MVKDynamicPipelineState pipelineState;
	VkFormat colorAttachmentFormats[kMVKMaxColorAttachmentCount];
	VkFormat depthAttachmentFormat;
	VkFormat stencilAttachmentFormat;
	uint32_t colorAttachmentCount;
	uint32_t viewMask;
	uint32_t pullVertices;

	/**
	 * Folds the key down to what a Metal pipeline is actually built from, so that draws differing
	 * only in state no pipeline can read, or that the shaders carry for themselves, share one.
	 *
	 * Every site that looks a key up must apply this, and apply it the same way, or the draw and
	 * the prefetch that was meant to anticipate it would not name the same pipeline.
	 */
	void canonicalize(MVKPixelFormats* pixFmts, bool dynamicVertexStride);

	/** Returns a key with every byte, padding included, cleared. */
	static MVKShaderObjectPipelineKey zeroed() {
		MVKShaderObjectPipelineKey key;
		memset(&key, 0, sizeof(key));
		return key;
	}

	bool operator==(const MVKShaderObjectPipelineKey& other) const {
		return memcmp(this, &other, sizeof(*this)) == 0;
	}
	std::size_t hash() const {
		return mvkHash((const uint64_t*)this, sizeof(*this) / sizeof(uint64_t));
	}

private:
	/**
	 * Replaces each binding's stride with the smallest one that lays the attributes out the same
	 * way, and marks the strides as coming from the vertex buffer bindings, so that draws
	 * differing only in stride share a pipeline.
	 *
	 * Metal can set the stride per draw where dynamicVertexStride is supported, so the value
	 * baked into a pipeline does not matter, with one exception: MoltenVK synthesizes a
	 * translation buffer for an attribute whose offset and size exceed the stride, and that
	 * decision is baked. A stride large enough to hold every attribute needs no translation, so
	 * all such strides are equivalent and collapse to one. A smaller stride does need it, and
	 * keeps its own value and its own pipeline, as does a stride of zero, which Metal expresses
	 * as a constant step function rather than as a stride.
	 *
	 * See setVertexBuffer:offset:attributeStride:atIndex: in
	 * https://developer.apple.com/documentation/metal/mtlrendercommandencoder
	 */
	void canonicalizeVertexStrides(MVKPixelFormats* pixFmts);

	/**
	 * Drops the topology from the key where Metal does not need the pipeline to declare a
	 * topology class, so that draws differing only in topology share one pipeline.
	 *
	 * Metal only consults the class where it has to route something: a layered target needs it to
	 * place the layer index, and tessellation feeds patches through it. Anything else can leave it
	 * unspecified, and one such pipeline rasterizes points, lines and triangles alike.
	 *
	 * See inputPrimitiveTopology in
	 * https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor
	 */
	void canonicalizeTopology();

	/**
	 * Folds state the built pipeline never reads to one value, so that draws differing only in
	 * state that cannot reach Metal share a pipeline.
	 *
	 * Blend state belongs to an attachment that is being rendered to, a blend equation is read
	 * only where blending is enabled, a logic op only where it is enabled, and a domain origin
	 * only where there is a tessellation stage to apply it. A sample mask is consulted only for
	 * the samples the draw has, so one covering all of them is the same as no mask at all.
	 */
	void canonicalizeUnusedState();

	/**
	 * Drops vertex attributes the vertex shader does not read, so that draws differing only in
	 * the rest of the layout share a pipeline.
	 *
	 * Vulkan lets a layout describe attributes a shader ignores, and they reach nothing but the
	 * vertex descriptor the pipeline is built with, so a draw that changes one of them is asking
	 * for a pipeline that draws exactly what the last one did. Where the locations a shader reads
	 * cannot be established, the whole layout is kept.
	 */
	void canonicalizeVertexAttributes();

	/**
	 * Hands the fragment output operations to the fragment shader where the draw actually uses
	 * one, and clears the state it then reads from a buffer instead.
	 *
	 * Metal bakes blending, the colour write mask, the sample mask, alpha to coverage and alpha
	 * to one into the pipeline, and the sample mask into the shader itself, so under
	 * VK_EXT_shader_object, where a draw can change any of them, each combination would cost a
	 * pipeline and a compile. Handing them to the shader leaves a single Metal pipeline per set
	 * of shaders, and changing any of the state costs a buffer update rather than a build.
	 *
	 * A draw that writes every channel straight through with the defaults is left alone. It uses
	 * none of these operations, so it would gain no pipeline, and the rewritten shader reads the
	 * attachment it writes and writes a sample mask, which gives up the hidden surface removal
	 * and the early depth test that opaque geometry depends on. That leaves exactly two shapes of
	 * fragment shader, which is one bit in the key rather than a value per configuration.
	 */
	void canonicalizeFragmentOutputState();

	/** Returns whether any attachment being rendered to blends or masks a channel. */
	bool blendsOrMasks() const;

	/** Returns whether the draw departs from the defaults for the sample mask or the alpha operations. */
	bool coversPartially() const;

	/** Clears the vertex layout a shader that loads its own attributes reads from a buffer instead. */
	void dropVertexInput() {
		memset(&vertexInput, 0, sizeof(vertexInput));
		pullVertices = 1;
	}
};

static_assert(sizeof(MVKShaderObjectPipelineKey) % sizeof(uint64_t) == 0,
			  "The key is hashed as whole 64-bit words, so its size must be a multiple of one.");

struct MVKShaderObjectPipelineKeyHash {
	std::size_t operator()(const MVKShaderObjectPipelineKey& key) const { return key.hash(); }
};

/**
 * Builds and retains the pipelines that bound shader objects and render state amount to.
 *
 * A shader object cannot be translated to MSL when it is created, because MoltenVK generates
 * MSL that depends on the adjoining stages and on the vertex layout, so the work is deferred
 * to the first draw that pairs a particular combination up. Pipelines are kept until the
 * device is destroyed, or until one of the shaders they were built from is.
 */
class MVKShaderObjectPipelines : public MVKBaseObject {

public:

	MVKVulkanAPIObject* getVulkanAPIObject() override;

	/**
	 * Returns the pipeline for the given key, building it on first use. Returns null on failure.
	 *
	 * The build runs outside the cache lock, so different keys build in parallel. A second caller
	 * for a key that is already being built waits for that build rather than starting another.
	 */
	MVKGraphicsPipeline* getPipeline(const MVKShaderObjectPipelineKey& key, bool* pWasBuilt = nullptr);

	/**
	 * Builds the pipeline for the given key on a background thread, if it is not already cached
	 * or being built. Called when a draw is recorded, so that by the time the command buffer is
	 * submitted the pipeline it needs already exists, and the submit path finds it instead of
	 * building it. The shaders in the key are retained for the duration of the build.
	 */
	void prefetchPipeline(const MVKShaderObjectPipelineKey& key);

	/** Discards every pipeline built from the given shader, which is about to be destroyed. */
	void removeShader(MVKShader* shader);

	/**
	 * Returns the compute pipeline for the given shader, building it on first use.
	 *
	 * A compute shader has no adjoining stages and no render state, so unlike a graphics shader
	 * it needs nothing beyond itself, and each one maps to a single pipeline.
	 */
	MVKComputePipeline* getComputePipeline(MVKShader* shader);

	MVKShaderObjectPipelines(MVKDevice* device) : _device(device), _prefetches(dispatch_group_create()) {}

	~MVKShaderObjectPipelines();

protected:
	MVKGraphicsPipeline* newPipeline(const MVKShaderObjectPipelineKey& key);
	MVKComputePipeline* newComputePipeline(MVKShader* shader);

	MVKDevice* _device;
	/** A cache entry. While building is set the pipeline is not yet valid and waiters block on _built. */
	struct Entry {
		MVKGraphicsPipeline* pipeline = nullptr;
		bool building = false;
	};
	std::unordered_map<MVKShaderObjectPipelineKey, Entry, MVKShaderObjectPipelineKeyHash> _pipelines;
	std::unordered_map<MVKShader*, MVKComputePipeline*> _computePipelines;
	std::mutex _lock;
	std::condition_variable _built;
	dispatch_group_t _prefetches;
};


#pragma mark -
#pragma mark MVKComputePipeline

/** Represents an Vulkan compute pipeline. */
class MVKComputePipeline : public MVKPipeline {

public:
	/** Returns if this pipeline allows non-zero dispatch bases in vkCmdDispatchBase(). */
	bool allowsDispatchBase() { return _allowsDispatchBase; }

	/** Returns the MTLRenderPipelineState for the final stage of the pipeline */
	id<MTLComputePipelineState> getPipelineState() const { return _mtlPipelineState; }

	/** Returns a list of implicit buffers used by the given stage. */
	const MVKImplicitBufferBindings& getImplicitBuffers(MVKShaderStage stage = kMVKShaderStageCompute) const { return getStageResources(stage).implicitBuffers; }

	/** Returns a list of which stage resources are used by the given stage. */
	const MVKPipelineStageResourceInfo& getStageResources(MVKShaderStage stage = kMVKShaderStageCompute) const {
		assert(stage == kMVKShaderStageCompute && "Input is just for API compatibility with MVKGraphicsPipeline");
		return _stageResources;
	}

	/** Returns the threadgroup size */
	const MTLSize& getThreadgroupSize() const { return _mtlThreadgroupSize; }

	/** Constructs an instance for the device and parent (which may be NULL). */
	MVKComputePipeline(MVKDevice* device,
					   MVKPipelineCache* pipelineCache,
					   MVKPipeline* parent,
					   const VkComputePipelineCreateInfo* pCreateInfo);

	~MVKComputePipeline() override;

protected:
    MVKMTLFunction getMTLFunction(const VkComputePipelineCreateInfo* pCreateInfo,
								  VkPipelineCreationFeedback* pStageFB);
	uint32_t getImplicitBufferIndex(uint32_t bufferIndexOffset);

    id<MTLComputePipelineState> _mtlPipelineState;
	MVKPipelineStageResourceInfo _stageResources = {};
    MTLSize _mtlThreadgroupSize;
	bool _allowsDispatchBase = false;

	MVKShaderModule* _module = nullptr;
	bool _ownsModule = false;
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

	/**
	 * Return a shader library for the shader conversion configuration, from the
	 * pipeline's pipeline cache, or compiled from source in the shader module.
	 */
	MVKShaderLibrary* getShaderLibrary(mvk::SPIRVToMSLConversionConfiguration* pContext,
									   MVKShaderModule* shaderModule,
									   MVKPipeline* pipeline,
									   VkPipelineCreationFeedback* pShaderFeedback = nullptr,
									   uint64_t startTime = 0);

	/** Merges the contents of the specified number of pipeline caches into this cache. */
	VkResult mergePipelineCaches(uint32_t srcCacheCount, const VkPipelineCache* pSrcCaches);

	/** Returns the archive of compiled pipelines this cache carries between runs. */
	MVKMTLBinaryArchive* getBinaryArchive() { return &_mtlBinaryArchive; }

#pragma mark Construction

	/** Constructs an instance for the specified device. */
	MVKPipelineCache(MVKDevice* device, const VkPipelineCacheCreateInfo* pCreateInfo);

	~MVKPipelineCache() override;

protected:
	void propagateDebugName() override {}
	MVKShaderLibraryCache* getShaderLibraryCache(MVKShaderModuleKey smKey);
	void readData(const VkPipelineCacheCreateInfo* pCreateInfo);
	void writeData(std::ostream& outstream, bool isCounting = false);
	MVKShaderLibrary* getShaderLibraryImpl(mvk::SPIRVToMSLConversionConfiguration* pContext,
										   MVKShaderModule* shaderModule,
										   MVKPipeline* pipeline,
										   VkPipelineCreationFeedback* pShaderFeedback,
										   uint64_t startTime);
	VkResult writeDataImpl(size_t* pDataSize, void* pData);
	VkResult mergePipelineCachesImpl(uint32_t srcCacheCount, const VkPipelineCache* pSrcCaches);
	void markDirty();

	std::unordered_map<MVKShaderModuleKey, MVKShaderLibraryCache*> _shaderCache;
	MVKMTLBinaryArchive _mtlBinaryArchive;
	size_t _dataSize = 0;
	std::mutex _shaderCacheLock;
	bool _isExternallySynchronized = false;
	bool _isMergeInternallySynchronized = false;
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
		_pPerformanceTracker = &getPerformanceStats().shaderCompilation.pipelineCompile;
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
	 * Returns a new (retained) MTLComputePipelineState object compiled from the MTLComputePipelineDescriptor.
	 *
	 * If the Metal pipeline compiler does not return within MVKConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLComputePipelineState> newMTLComputePipelineState(MTLComputePipelineDescriptor* plDesc);


#pragma mark Construction

	MVKComputePipelineCompiler(MVKVulkanAPIDeviceObject* owner, const char* compilerType = nullptr) : MVKMetalCompiler(owner) {
		_compilerType = compilerType ? compilerType : "Compute pipeline";
		_pPerformanceTracker = &getPerformanceStats().shaderCompilation.pipelineCompile;
	}

	~MVKComputePipelineCompiler() override;

protected:
	bool compileComplete(id<MTLComputePipelineState> pipelineState, NSError *error);

	id<MTLComputePipelineState> _mtlComputePipelineState = nil;
};


#pragma mark -
#pragma mark Support functions

/** Validate the definitions of the Cereal Archives. */
void mvkValidateCeralArchiveDefinitions();
