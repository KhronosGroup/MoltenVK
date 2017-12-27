/*
 * MVKShaderModule.h
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
    /** Returns the Metal shader function used by the specified shader state. */
    MVKMTLFunction getMTLFunction(const VkPipelineShaderStageCreateInfo* pShaderStage);

    /** Constructs an instance from the MSL source code in the specified SPIRVToMSLConverter. */
    MVKShaderLibrary(MVKDevice* device, SPIRVToMSLConverter& mslConverter);

	/** Constructs an instance from the specified compiled MSL code data. */
	MVKShaderLibrary(MVKDevice* device,
					 const void* mslCompiledCodeData,
					 size_t mslCompiledCodeLength);

	~MVKShaderLibrary() override;

protected:
    void handleCompilationError(NSError* err, const char* opDesc);
    MTLFunctionConstant* getFunctionConstant(NSArray<MTLFunctionConstant*>* mtlFCs, NSUInteger mtlFCID);

	id<MTLLibrary> _mtlLibrary;
    SPIRVEntryPointsByName _entryPoints;
};


#pragma mark -
#pragma mark MVKShaderModule

/** Represents a Vulkan shader module. */
class MVKShaderModule : public MVKBaseDeviceObject {

public:
    /** Returns the Metal shader function used by the specified shader state, or nil if it doesn't exist. */
    MVKMTLFunction getMTLFunction(const VkPipelineShaderStageCreateInfo* pShaderStage,
                                  SPIRVToMSLConverterContext* pContext);

	MVKShaderModule(MVKDevice* device, const VkShaderModuleCreateInfo* pCreateInfo);

	~MVKShaderModule() override;

protected:
	MVKShaderLibrary* getShaderLibrary(SPIRVToMSLConverterContext* pContext);
	MVKShaderLibrary* findShaderLibrary(SPIRVToMSLConverterContext* pContext);
	MVKShaderLibrary* addShaderLibrary(SPIRVToMSLConverterContext* pContext);

	SPIRVToMSLConverter _converter;
	MVKShaderLibrary* _defaultLibrary;
	std::vector<std::pair<SPIRVToMSLConverterContext, MVKShaderLibrary*>> _shaderLibraries;
    std::mutex _accessLock;
};
