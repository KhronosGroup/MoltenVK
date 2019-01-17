/*
 * MVKPipeline.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKDescriptorSet.h"
#include "MVKShaderModule.h"
#include "MVKSync.h"
#include "MVKVector.h"
#include <MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.h>
#include <unordered_set>
#include <ostream>

#import <Metal/Metal.h>

class MVKCommandEncoder;
class MVKPipelineCache;


#pragma mark -
#pragma mark MVKPipelineLayout

struct MVKShaderAuxBufferBinding {
	uint32_t vertex = 0;
	uint32_t fragment = 0;
	uint32_t compute = 0;
};

/** Represents a Vulkan pipeline layout. */
class MVKPipelineLayout : public MVKBaseDeviceObject {

public:

	/** Binds descriptor sets to a command encoder. */
    void bindDescriptorSets(MVKCommandEncoder* cmdEncoder,
                            MVKVector<MVKDescriptorSet*>& descriptorSets,
                            uint32_t firstSet,
                            MVKVector<uint32_t>& dynamicOffsets);

	/** Populates the specified shader converter context. */
	void populateShaderConverterContext(SPIRVToMSLConverterContext& context);

	/** Updates a descriptor set in a command encoder. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   MVKVector<VkWriteDescriptorSet>& descriptorWrites,
						   uint32_t set);

	/** Updates a descriptor set from a template in a command encoder. */
	void pushDescriptorSet(MVKCommandEncoder* cmdEncoder,
						   MVKDescriptorUpdateTemplate* descriptorUpdateTemplate,
						   uint32_t set,
						   const void* pData);

	/** Returns the current auxiliary buffer bindings. */
	const MVKShaderAuxBufferBinding& getAuxBufferIndex() { return _auxBufferIndex; }

	/** Returns the number of textures in this layout. This is used to calculate the size of the auxiliary buffer. */
	uint32_t getTextureCount() { return _pushConstantsMTLResourceIndexes.getMaxTextureIndex(); }

	/** Constructs an instance for the specified device. */
	MVKPipelineLayout(MVKDevice* device, const VkPipelineLayoutCreateInfo* pCreateInfo);

protected:
	MVKVectorInline<MVKDescriptorSetLayout, 8> _descriptorSetLayouts;
	MVKVectorInline<MVKShaderResourceBinding, 8> _dslMTLResourceIndexOffsets;
	MVKVectorInline<VkPushConstantRange, 8> _pushConstants;
	MVKShaderResourceBinding _pushConstantsMTLResourceIndexes;
	MVKShaderAuxBufferBinding _auxBufferIndex;
};


#pragma mark -
#pragma mark MVKPipeline

/** Represents an abstract Vulkan pipeline. */
class MVKPipeline : public MVKBaseDeviceObject {

public:

	/** Binds this pipeline to the specified command encoder. */
	virtual void encode(MVKCommandEncoder* cmdEncoder) = 0;

	/** Returns the current auxiliary buffer bindings. */
	const MVKShaderAuxBufferBinding& getAuxBufferIndex() { return _auxBufferIndex; }

	/** Constructs an instance for the device. layout, and parent (which may be NULL). */
	MVKPipeline(MVKDevice* device, MVKPipelineCache* pipelineCache, MVKPipeline* parent) : MVKBaseDeviceObject(device),
																						   _pipelineCache(pipelineCache) {}

protected:
	MVKPipelineCache* _pipelineCache;
	MVKShaderAuxBufferBinding _auxBufferIndex;

};


#pragma mark -
#pragma mark MVKGraphicsPipeline

/** Represents an Vulkan graphics pipeline. */
class MVKGraphicsPipeline : public MVKPipeline {

public:

	/** Binds this pipeline to the specified command encoder. */
	void encode(MVKCommandEncoder* cmdEncoder) override;

    /** Returns whether this pipeline permits dynamic setting of the specifie state. */
    bool supportsDynamicState(VkDynamicState state);

	/** Constructs an instance for the device and parent (which may be NULL). */
	MVKGraphicsPipeline(MVKDevice* device,
						MVKPipelineCache* pipelineCache,
						MVKPipeline* parent,
						const VkGraphicsPipelineCreateInfo* pCreateInfo);

	~MVKGraphicsPipeline() override;

protected:
    void initMTLRenderPipelineState(const VkGraphicsPipelineCreateInfo* pCreateInfo);
    void initMVKShaderConverterContext(SPIRVToMSLConverterContext& _shaderContext,
                                       const VkGraphicsPipelineCreateInfo* pCreateInfo);
	MTLRenderPipelineDescriptor* getMTLRenderPipelineDescriptor(const VkGraphicsPipelineCreateInfo* pCreateInfo);
	bool isRenderingPoints(const VkGraphicsPipelineCreateInfo* pCreateInfo);

	VkPipelineRasterizationStateCreateInfo _rasterInfo;
	VkPipelineDepthStencilStateCreateInfo _depthStencilInfo;

  MVKVectorInline<MTLViewport, kMVKCachedViewportCount> _mtlViewports;
  MVKVectorInline<MTLScissorRect, kMVKCachedScissorCount> _mtlScissors;

	id<MTLRenderPipelineState> _mtlPipelineState;
	MTLCullMode _mtlCullMode;
	MTLWinding _mtlFrontWinding;
	MTLTriangleFillMode _mtlFillMode;
	MTLDepthClipMode _mtlDepthClipMode;
    MTLPrimitiveType _mtlPrimitiveType;

    float _blendConstants[4] = { 0.0, 0.0, 0.0, 1.0 };

	bool _dynamicStateEnabled[VK_DYNAMIC_STATE_RANGE_SIZE];
	bool _hasDepthStencilInfo;
	bool _needsVertexAuxBuffer = false;
	bool _needsFragmentAuxBuffer = false;
};


#pragma mark -
#pragma mark MVKComputePipeline

/** Represents an Vulkan compute pipeline. */
class MVKComputePipeline : public MVKPipeline {

public:

	/** Binds this pipeline to the specified command encoder. */
	void encode(MVKCommandEncoder* cmdEncoder) override;

	/** Constructs an instance for the device and parent (which may be NULL). */
	MVKComputePipeline(MVKDevice* device,
					   MVKPipelineCache* pipelineCache,
					   MVKPipeline* parent,
					   const VkComputePipelineCreateInfo* pCreateInfo);

	~MVKComputePipeline() override;

protected:
    MVKMTLFunction getMTLFunction(const VkComputePipelineCreateInfo* pCreateInfo);

    id<MTLComputePipelineState> _mtlPipelineState;
    MTLSize _mtlThreadgroupSize;
    bool _needsAuxBuffer = false;
};


#pragma mark -
#pragma mark MVKPipelineCache

/** Represents a Vulkan pipeline cache. */
class MVKPipelineCache : public MVKBaseDeviceObject {

public:

	/** 
	 * If pData is not null, serializes at most pDataSize bytes of the contents of the cache into that
	 * memory location, and returns the number of bytes serialized in pDataSize. If pData is null,
	 * returns the number of bytes required to serialize the contents of this pipeline cache.
	 */
	VkResult writeData(size_t* pDataSize, void* pData);

	/** Return a shader library from the specified shader context sourced from the specified shader module. */
	MVKShaderLibrary* getShaderLibrary(SPIRVToMSLConverterContext* pContext, MVKShaderModule* shaderModule);

	/** Merges the contents of the specified number of pipeline caches into this cache. */
	VkResult mergePipelineCaches(uint32_t srcCacheCount, const VkPipelineCache* pSrcCaches);

#pragma mark Construction

	/** Constructs an instance for the specified device. */
	MVKPipelineCache(MVKDevice* device, const VkPipelineCacheCreateInfo* pCreateInfo);

	~MVKPipelineCache() override;

protected:
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

	MVKRenderPipelineCompiler(MVKDevice* device) : MVKMetalCompiler(device) {
		_compilerType = "Render pipeline";
		_pPerformanceTracker = &_device->_performanceStatistics.shaderCompilation.pipelineCompile;
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


#pragma mark Construction

	MVKComputePipelineCompiler(MVKDevice* device) : MVKMetalCompiler(device) {
		_compilerType = "Compute pipeline";
		_pPerformanceTracker = &_device->_performanceStatistics.shaderCompilation.pipelineCompile;
	}

	~MVKComputePipelineCompiler() override;

protected:
	bool compileComplete(id<MTLComputePipelineState> pipelineState, NSError *error);

	id<MTLComputePipelineState> _mtlComputePipelineState = nil;
};
