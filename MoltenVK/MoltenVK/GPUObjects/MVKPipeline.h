/*
 * MVKPipeline.h
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

	/** Returns whether or not full image view swizzling is enabled for this pipeline. */
	bool fullImageViewSwizzle() const { return _fullImageViewSwizzle; }

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

	/** Constructs an instance for the device and parent (which may be NULL). */
	MVKGraphicsPipeline(MVKDevice* device,
						MVKPipelineCache* pipelineCache,
						MVKPipeline* parent,
						const VkGraphicsPipelineCreateInfo* pCreateInfo);

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

	uint8_t _primitiveTopologyClass;
	bool _isRasterizing = false;
	bool _isRasterizingColor = false;
	bool _isTessellationPipeline = false;
	bool _inputAttachmentIsDSAttachment = false;
	bool _hasRemappedAttachmentLocations = false;
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
