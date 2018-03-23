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
#include <MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.h>
#include <vector>
#include <mutex>

#import <Metal/Metal.h>

class MVKPipelineCache;

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
	MVKShaderLibrary(MVKDevice* device, const char* mslSourceCode, const SPIRVEntryPoint& entryPoint);

	/** Constructs an instance from the specified compiled MSL code data. */
	MVKShaderLibrary(MVKDevice* device,
					 const void* mslCompiledCodeData,
					 size_t mslCompiledCodeLength);

	~MVKShaderLibrary() override;

protected:
    void handleCompilationError(NSError* err, const char* opDesc);
    MTLFunctionConstant* getFunctionConstant(NSArray<MTLFunctionConstant*>* mtlFCs, NSUInteger mtlFCID);

	id<MTLLibrary> _mtlLibrary;
	SPIRVEntryPoint _entryPoint;
};


#pragma mark -
#pragma mark MVKShaderLibraryCache

/** Represents a cache of shader libraries for one shader module. */
class MVKShaderLibraryCache : public MVKBaseDeviceObject {

public:

	/** Return a shader library from the specified shader context sourced from the specified shader module. */
	MVKShaderLibrary* getShaderLibrary(SPIRVToMSLConverterContext* pContext, MVKShaderModule* shaderModule);

	MVKShaderLibraryCache(MVKDevice* device) : MVKBaseDeviceObject(device) {};

	~MVKShaderLibraryCache() override;

protected:
	MVKShaderLibrary* findShaderLibrary(SPIRVToMSLConverterContext* pContext);
	MVKShaderLibrary* addShaderLibrary(SPIRVToMSLConverterContext* pContext,
									   const char* mslSourceCode,
									   const SPIRVEntryPoint& entryPoint);

	std::mutex _accessLock;
	std::size_t _shaderModuleHash;
	std::vector<std::pair<SPIRVToMSLConverterContext, MVKShaderLibrary*>> _shaderLibraries;
};


#pragma mark -
#pragma mark MVKShaderModule

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
	 * Returns the Metal Shading Language source code most recently converted
	 * by the convert() function, or set directly using the setMSL() function.
	 */
	inline const std::string& getMSL() { return _converter.getMSL(); }

	/** Returns information about the shader entry point. */
	inline const SPIRVEntryPoint& getEntryPoint() { return _converter.getEntryPoint(); }

	/** Returns a key as a means of identifying this shader module in a pipeline cache. */
	inline std::size_t getKey() { return _key; }

	MVKShaderModule(MVKDevice* device, const VkShaderModuleCreateInfo* pCreateInfo);

	~MVKShaderModule() override;

protected:
	MVKShaderLibraryCache _shaderLibraryCache;
	SPIRVToMSLConverter _converter;
	MVKShaderLibrary* _defaultLibrary;
	std::size_t _key;
    std::mutex _accessLock;
};
