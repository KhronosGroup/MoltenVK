/*
 * MVKShaderModule.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKSync.h"
#include <MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.h>
#include <vector>
#include <mutex>

#import <Metal/Metal.h>

class MVKPipelineCache;
class MVKShaderCacheIterator;

using namespace mvk;


#pragma mark -
#pragma mark MVKShaderLibrary

/** Specifies the SPIRV LocalSize, which is the number of threads in a compute shader workgroup. */
typedef struct {
    id<MTLFunction> mtlFunction;
    MTLSize threadGroupSize;
} MVKMTLFunction;

/** A MVKMTLFunction indicating an invalid MTLFunction. The mtlFunction member is nil. */
extern const MVKMTLFunction MVKMTLFunctionNull;

/** Wraps a single MTLLibrary. */
class MVKShaderLibrary : public MVKBaseDeviceObject {

public:
	/** Returns the Metal shader function, possibly specialized. */
	MVKMTLFunction getMTLFunction(const VkSpecializationInfo* pSpecializationInfo);

	/** Constructs an instance from the specified MSL source code. */
	MVKShaderLibrary(MVKDevice* device, const std::string& mslSourceCode, const SPIRVEntryPoint& entryPoint);

	/** Constructs an instance from the specified compiled MSL code data. */
	MVKShaderLibrary(MVKDevice* device,
					 const void* mslCompiledCodeData,
					 size_t mslCompiledCodeLength);

	/** Copy constructor. */
	MVKShaderLibrary(MVKShaderLibrary& other);

	~MVKShaderLibrary() override;

protected:
	friend MVKShaderCacheIterator;

	void handleCompilationError(NSError* err, const char* opDesc);
    MTLFunctionConstant* getFunctionConstant(NSArray<MTLFunctionConstant*>* mtlFCs, NSUInteger mtlFCID);

	id<MTLLibrary> _mtlLibrary;
	SPIRVEntryPoint _entryPoint;
	std::string _msl;
};


#pragma mark -
#pragma mark MVKShaderLibraryCache

/** Represents a cache of shader libraries for one shader module. */
class MVKShaderLibraryCache : public MVKBaseDeviceObject {

public:

	/**
	 * Returns a shader library from the specified shader context sourced from the specified shader module,
	 * lazily creating the shader library from source code in the shader module, if needed.
	 *
	 * If pWasAdded is not nil, this function will set it to true if a new shader library was created,
	 * and to false if an existing shader library was found and returned.
	 */
	MVKShaderLibrary* getShaderLibrary(SPIRVToMSLConverterContext* pContext,
									   MVKShaderModule* shaderModule,
									   bool* pWasAdded = nullptr);

	MVKShaderLibraryCache(MVKDevice* device) : MVKBaseDeviceObject(device) {};

	~MVKShaderLibraryCache() override;

protected:
	friend MVKShaderCacheIterator;
	friend MVKPipelineCache;

	MVKShaderLibrary* findShaderLibrary(SPIRVToMSLConverterContext* pContext);
	MVKShaderLibrary* addShaderLibrary(SPIRVToMSLConverterContext* pContext,
									   const std::string& mslSourceCode,
									   const SPIRVEntryPoint& entryPoint);
	void merge(MVKShaderLibraryCache* other);

	std::mutex _accessLock;
	std::vector<std::pair<SPIRVToMSLConverterContext, MVKShaderLibrary*>> _shaderLibraries;
};


#pragma mark -
#pragma mark MVKShaderModule

typedef struct MVKShaderModuleKey_t {
	std::size_t codeSize;
	std::size_t codeHash;

	bool operator==(const MVKShaderModuleKey_t& rhs) const {
		return ((codeSize == rhs.codeSize) && (codeHash == rhs.codeHash));
	}
	MVKShaderModuleKey_t(std::size_t codeSize, std::size_t codeHash) : codeSize(codeSize), codeHash(codeHash) {}
	MVKShaderModuleKey_t() :  MVKShaderModuleKey_t(0, 0) {}
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
class MVKShaderModule : public MVKBaseDeviceObject {

public:
	/** Returns the Metal shader function, possibly specialized. */
	MVKMTLFunction getMTLFunction(SPIRVToMSLConverterContext* pContext,
								  const VkSpecializationInfo* pSpecializationInfo,
								  MVKPipelineCache* pipelineCache);

	/** Convert the SPIR-V to MSL, using the specified shader conversion context. */
	bool convert(SPIRVToMSLConverterContext* pContext);

	/**
	 * Returns the Metal Shading Language source code as converted by the most recent
	 * call to convert() function, or set directly using the setMSL() function.
	 */
	inline const std::string& getMSL() { return _converter.getMSL(); }

	/**
	 * Returns information about the shader entry point as converted by the most recent
	 * call to convert() function, or set directly using the setMSL() function.
	 */
	inline const SPIRVEntryPoint& getEntryPoint() { return _converter.getEntryPoint(); }

	/** Returns a key as a means of identifying this shader module in a pipeline cache. */
	inline MVKShaderModuleKey getKey() { return _key; }

	MVKShaderModule(MVKDevice* device, const VkShaderModuleCreateInfo* pCreateInfo);

	~MVKShaderModule() override;

protected:
	friend MVKShaderCacheIterator;

	MVKShaderLibraryCache _shaderLibraryCache;
	SPIRVToMSLConverter _converter;
	MVKShaderLibrary* _defaultLibrary;
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
	 * If the Metal library compiler does not return within MVKDeviceConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLLibrary> newMTLLibrary(NSString* mslSourceCode);


#pragma mark Construction

	MVKShaderLibraryCompiler(MVKDevice* device) : MVKMetalCompiler(device) {
		_compilerType = "Shader library";
		_pPerformanceTracker = &_device->_performanceStatistics.shaderCompilation.mslCompile;
	}

	~MVKShaderLibraryCompiler() override;

protected:
	void compileComplete(id<MTLLibrary> mtlLibrary, NSError *error);
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
	 * If the Metal function compiler does not return within MVKDeviceConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLFunction> newMTLFunction(id<MTLLibrary> mtlLibrary, NSString* funcName, MTLFunctionConstantValues* constantValues);


#pragma mark Construction

	MVKFunctionSpecializer(MVKDevice* device) : MVKMetalCompiler(device) {
		_compilerType = "Function specialization";
		_pPerformanceTracker = &_device->_performanceStatistics.shaderCompilation.functionSpecialization;
	}

	~MVKFunctionSpecializer() override;

protected:
	void compileComplete(id<MTLFunction> mtlFunction, NSError *error);

	id<MTLFunction> _mtlFunction = nil;
};
