/*
 * MVKShaderModule.h
 *
 * Copyright (c) 2015-2024 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKSync.h"
#include "MVKCodec.h"
#include "MVKSmallVector.h"
#include <MoltenVKShaderConverter/SPIRVToMSLConverter.h>
#include <mutex>

#import <Metal/Metal.h>

class MVKPipelineCache;
class MVKShaderCacheIterator;
class MVKShaderLibraryCache;
class MVKShaderModule;

#pragma mark -
#pragma mark MVKShaderLibrary

/** A MTLFunction and corresponding result information resulting from a shader conversion. */
typedef struct MVKMTLFunction {
  mvk::SPIRVToMSLConversionResultInfo shaderConversionResults;
	MTLSize threadGroupSize;
	id<MTLFunction> getMTLFunction() { return _mtlFunction; }

	MVKMTLFunction(id<MTLFunction> mtlFunc, const mvk::SPIRVToMSLConversionResultInfo scRslts, MTLSize tgSize);
	MVKMTLFunction(const MVKMTLFunction& other);
	MVKMTLFunction& operator=(const MVKMTLFunction& other);
	MVKMTLFunction() {}
	~MVKMTLFunction();

private:
	id<MTLFunction> _mtlFunction = nil;

} MVKMTLFunction;

/** A MVKMTLFunction indicating an invalid MTLFunction. The mtlFunction member is nil. */
const MVKMTLFunction MVKMTLFunctionNull(nil, mvk::SPIRVToMSLConversionResultInfo(), MTLSizeMake(1, 1, 1));

/** Wraps a single MTLLibrary. */
class MVKShaderLibrary : public MVKBaseDeviceObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _owner->getVulkanAPIObject(); };

	/**
	 * Sets the entry point function name.
	 *
	 * This is usually set automatically during shader conversion from SPIR-V to MSL.
	 * For a library that was created directly from MSL, this function can be used to
	 * set the name of the function if it has a different name than the default main0().
	 */
	void setEntryPointName(std::string& funcName);

    /**
	 * Sets the number of threads in a single compute kernel workgroup, per dimension.
	 *
	 * This is usually set automatically during shader conversion from SPIR-V to MSL.
	 * For a library that was created directly from MSL, this function can be used to
	 * set the workgroup size..
	 */
    void setWorkgroupSize(uint32_t x, uint32_t y, uint32_t z);
    
	MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
					 const mvk::SPIRVToMSLConversionResult& conversionResult);

	MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
					 const mvk::SPIRVToMSLConversionResultInfo& resultInfo,
					 const MVKCompressor<std::string> compressedMSL,
					 const std::vector<std::pair<uint32_t, uint32_t> >* spec_list = nullptr);

	MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
					 const void* mslCompiledCodeData,
					 size_t mslCompiledCodeLength);

	MVKShaderLibrary(const MVKShaderLibrary& other);

	MVKShaderLibrary& operator=(const MVKShaderLibrary& other);

	~MVKShaderLibrary() override;

protected:
	friend MVKShaderCacheIterator;
	friend MVKShaderLibraryCache;
	friend MVKShaderModule;

	MVKMTLFunction getMTLFunction(const VkSpecializationInfo* pSpecializationInfo,
								  VkPipelineCreationFeedback* pShaderFeedback,
								  MVKShaderModule* shaderModule);
	void handleCompilationError(NSError* err, const char* opDesc);
    MTLFunctionConstant* getFunctionConstant(NSArray<MTLFunctionConstant*>* mtlFCs, NSUInteger mtlFCID);
	void compileLibrary(const std::string& msl,
						const std::vector<std::pair<uint32_t, uint32_t> >* spec_list = nullptr);
	void compressMSL(const std::string& msl);
	void decompressMSL(std::string& msl);
	MVKCompressor<std::string>& getCompressedMSL() { return _compressedMSL; }

	MVKVulkanAPIDeviceObject* _owner;
	id<MTLLibrary> _mtlLibrary;
	MVKCompressor<std::string> _compressedMSL;
  mvk::SPIRVToMSLConversionResultInfo _shaderConversionResultInfo;

	bool _specialized;
	std::map<std::vector<std::pair<uint32_t, uint32_t> >, MVKShaderLibrary *> _spec_variants;
};


#pragma mark -
#pragma mark MVKShaderLibraryCache

/** Represents a cache of shader libraries for one shader module. */
class MVKShaderLibraryCache : public MVKBaseDeviceObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _owner->getVulkanAPIObject(); };

	/**
	 * Returns a shader library from the shader conversion configuration sourced from the
	 * shader module, lazily creating the shader library from source code in the shader
	 * module, if needed, and if the pipeline is not configured to fail if a pipeline compile
	 * is required. In that case, the new shader library is not created, and nil is returned.
	 *
	 * If pWasAdded is not nil, this function will set it to true if a new shader library was created,
	 * and to false if an existing shader library was found and returned.
	 */
	MVKShaderLibrary* getShaderLibrary(mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
									   MVKShaderModule* shaderModule, MVKPipeline* pipeline,
									   bool* pWasAdded, VkPipelineCreationFeedback* pShaderFeedback,
									   uint64_t startTime = 0);

	MVKShaderLibraryCache(MVKVulkanAPIDeviceObject* owner) : MVKBaseDeviceObject(owner->getDevice()), _owner(owner) {};

	~MVKShaderLibraryCache() override;

protected:
	friend MVKShaderCacheIterator;
	friend MVKPipelineCache;
	friend MVKShaderModule;

	MVKShaderLibrary* findShaderLibrary(mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
										VkPipelineCreationFeedback* pShaderFeedback = nullptr,
										uint64_t startTime = 0);
	MVKShaderLibrary* addShaderLibrary(const mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
									   const mvk::SPIRVToMSLConversionResult& conversionResult);
	MVKShaderLibrary* addShaderLibrary(const mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
									   const mvk::SPIRVToMSLConversionResultInfo& resultInfo,
									   const MVKCompressor<std::string> compressedMSL);
	void merge(MVKShaderLibraryCache* other);

	MVKVulkanAPIDeviceObject* _owner;
	MVKSmallVector<std::pair<mvk::SPIRVToMSLConversionConfiguration, MVKShaderLibrary*>> _shaderLibraries;
};


#pragma mark -
#pragma mark MVKShaderModule

typedef struct MVKShaderModuleKey {
	std::size_t codeSize;
	std::size_t codeHash;

	bool operator==(const MVKShaderModuleKey& rhs) const {
		return ((codeSize == rhs.codeSize) && (codeHash == rhs.codeHash));
	}
	MVKShaderModuleKey(std::size_t codeSize, std::size_t codeHash) : codeSize(codeSize), codeHash(codeHash) {}
	MVKShaderModuleKey() :  MVKShaderModuleKey(0, 0) {}
} MVKShaderModuleKey;

/**
 * Hash structure implementation for MVKShaderModuleKey in std namespace,
 * so MVKShaderModuleKey can be used as a key in a std::map and std::unordered_map.
 */
namespace std {
	template <>
	struct hash<MVKShaderModuleKey> {
		std::size_t operator()(const MVKShaderModuleKey& k) const { return k.codeHash; }
	};
}

/** Represents a Vulkan shader module. */
class MVKShaderModule : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_SHADER_MODULE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_SHADER_MODULE_EXT; }

	/** Returns the Metal shader function, possibly specialized. */
	MVKMTLFunction getMTLFunction(mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
								  const VkSpecializationInfo* pSpecializationInfo,
								  MVKPipeline* pipeline,
								  VkPipelineCreationFeedback* pShaderFeedback);

	/** Convert the SPIR-V to MSL, using the specified shader conversion configuration. */
	bool convert(mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
               mvk::SPIRVToMSLConversionResult& conversionResult);

	/** Returns the original SPIR-V code that was specified when this object was created. */
	const std::vector<uint32_t>& getSPIRV() { return _spvConverter.getSPIRV(); }

    /** Sets the number of threads in a single compute kernel workgroup, per dimension. */
    void setWorkgroupSize(uint32_t x, uint32_t y, uint32_t z);
    
	/** Returns a key as a means of identifying this shader module in a pipeline cache. */
	MVKShaderModuleKey getKey() { return _key; }

	MVKShaderModule(MVKDevice* device, const VkShaderModuleCreateInfo* pCreateInfo);

	~MVKShaderModule() override;

protected:
	friend MVKShaderCacheIterator;

	void propagateDebugName() override {}

	MVKShaderLibraryCache _shaderLibraryCache;
	mvk::SPIRVToMSLConverter _spvConverter;
	MVKShaderLibrary* _directMSLLibrary;
	MVKShaderModuleKey _key;
    std::mutex _accessLock;
};


#pragma mark -
#pragma mark MVKShaderLibraryCompiler

/**
 * Creates a MTLLibrary from source code.
 *
 * Instances of this class are one-shot, and can only be used for a single library compilation.
 */
class MVKShaderLibraryCompiler : public MVKMetalCompiler {

public:

	/**
	 * Returns a new (retained) MTLLibrary object compiled from the MSL source code.
	 *
	 * If the Metal library compiler does not return within MVKConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLLibrary> newMTLLibrary(NSString* mslSourceCode,
								 const mvk::SPIRVToMSLConversionResultInfo& shaderConversionResults,
								 const std::vector<std::pair<uint32_t, uint32_t> >* spec_list = nullptr);


#pragma mark Construction

	MVKShaderLibraryCompiler(MVKVulkanAPIDeviceObject* owner) : MVKMetalCompiler(owner) {
		_compilerType = "Shader library";
		_pPerformanceTracker = &getPerformanceStats().shaderCompilation.mslCompile;
	}

	~MVKShaderLibraryCompiler() override;

protected:
	bool compileComplete(id<MTLLibrary> mtlLibrary, NSError *error);
	void handleError() override;

	id<MTLLibrary> _mtlLibrary = nil;
};


#pragma mark -
#pragma mark MVKFunctionSpecializer

/**
 * Compiles a specialized MTLFunction.
 *
 * Instances of this class are one-shot, and can only be used for a single function compilation.
 */
class MVKFunctionSpecializer : public MVKMetalCompiler {

public:

	/**
	 * Returns a new (retained) MTLFunction object compiled from the MTLLibrary and specialization constants.
	 *
	 * If the Metal function compiler does not return within MVKConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLFunction> newMTLFunction(id<MTLLibrary> mtlLibrary, NSString* funcName, MTLFunctionConstantValues* constantValues);


#pragma mark Construction

	MVKFunctionSpecializer(MVKVulkanAPIDeviceObject* owner) : MVKMetalCompiler(owner) {
		_compilerType = "Function specialization";
		_pPerformanceTracker = &getPerformanceStats().shaderCompilation.functionSpecialization;
	}

	~MVKFunctionSpecializer() override;

protected:
	bool compileComplete(id<MTLFunction> mtlFunction, NSError *error);

	id<MTLFunction> _mtlFunction = nil;
};
