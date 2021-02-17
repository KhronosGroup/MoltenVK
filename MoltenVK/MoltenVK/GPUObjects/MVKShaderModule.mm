/*
 * MVKShaderModule.mm
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKShaderModule.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include <string>

using namespace std;


MVKMTLFunction::MVKMTLFunction(id<MTLFunction> mtlFunc, const SPIRVToMSLConversionResults scRslts, MTLSize tgSize) {
	_mtlFunction = [mtlFunc retain];		// retained
	shaderConversionResults = scRslts;
	threadGroupSize = tgSize;
}

MVKMTLFunction::MVKMTLFunction(const MVKMTLFunction& other) {
	_mtlFunction = [other._mtlFunction retain];		// retained
	shaderConversionResults = other.shaderConversionResults;
	threadGroupSize = other.threadGroupSize;
}

MVKMTLFunction::~MVKMTLFunction() {
	[_mtlFunction release];
}


#pragma mark -
#pragma mark MVKShaderLibrary

// If the size of the workgroup dimension is specialized, extract it from the
// specialization info, otherwise use the value specified in the SPIR-V shader code.
static uint32_t getWorkgroupDimensionSize(const SPIRVWorkgroupSizeDimension& wgDim, const VkSpecializationInfo* pSpecInfo) {
	if (wgDim.isSpecialized && pSpecInfo) {
		for (uint32_t specIdx = 0; specIdx < pSpecInfo->mapEntryCount; specIdx++) {
			const VkSpecializationMapEntry* pMapEntry = &pSpecInfo->pMapEntries[specIdx];
			if (pMapEntry->constantID == wgDim.specializationID) {
				return *reinterpret_cast<uint32_t*>((uintptr_t)pSpecInfo->pData + pMapEntry->offset) ;
			}
		}
	}
	return wgDim.size;
}

MVKMTLFunction MVKShaderLibrary::getMTLFunction(const VkSpecializationInfo* pSpecializationInfo, MVKShaderModule* shaderModule) {

	if ( !_mtlLibrary ) { return MVKMTLFunctionNull; }

	@synchronized (_owner->getMTLDevice()) {
		@autoreleasepool {
			NSString* mtlFuncName = @(_shaderConversionResults.entryPoint.mtlFunctionName.c_str());
			MVKDevice* mvkDev = _owner->getDevice();

			uint64_t startTime = mvkDev->getPerformanceTimestamp();
			id<MTLFunction> mtlFunc = [[_mtlLibrary newFunctionWithName: mtlFuncName] autorelease];
			mvkDev->addActivityPerformance(mvkDev->_performanceStatistics.shaderCompilation.functionRetrieval, startTime);

			if (mtlFunc) {
				// If the Metal device supports shader specialization, and the Metal function expects to be specialized,
				// populate Metal function constant values from the Vulkan specialization info, and compile a specialized
				// Metal function, otherwise simply use the unspecialized Metal function.
				if (mvkDev->_pMetalFeatures->shaderSpecialization) {
					NSArray<MTLFunctionConstant*>* mtlFCs = mtlFunc.functionConstantsDictionary.allValues;
					if (mtlFCs.count > 0) {
						// The Metal shader contains function constants and expects to be specialized.
						// Populate the Metal function constant values from the Vulkan specialization info.
						MTLFunctionConstantValues* mtlFCVals = [[MTLFunctionConstantValues new] autorelease];
						if (pSpecializationInfo) {
							// Iterate through the provided Vulkan specialization entries, and populate the
							// Metal function constant value that matches the Vulkan specialization constantID.
							for (uint32_t specIdx = 0; specIdx < pSpecializationInfo->mapEntryCount; specIdx++) {
								const VkSpecializationMapEntry* pMapEntry = &pSpecializationInfo->pMapEntries[specIdx];
								for (MTLFunctionConstant* mfc in mtlFCs) {
									if (mfc.index == pMapEntry->constantID) {
										[mtlFCVals setConstantValue: ((char*)pSpecializationInfo->pData + pMapEntry->offset)
															   type: mfc.type
															atIndex: mfc.index];
										break;
									}
								}
							}
						}

						// Compile the specialized Metal function, and use it instead of the unspecialized Metal function.
						MVKFunctionSpecializer fs(_owner);
						mtlFunc = [fs.newMTLFunction(_mtlLibrary, mtlFuncName, mtlFCVals) autorelease];
					}
				}
			} else {
				reportError(VK_ERROR_INVALID_SHADER_NV, "Shader module does not contain an entry point named '%s'.", mtlFuncName.UTF8String);
			}

			// Set the debug name. First try name of shader module, otherwise try name of owner.
			NSString* dbName = shaderModule-> getDebugName();
			if ( !dbName ) { dbName = _owner-> getDebugName(); }
			setLabelIfNotNil(mtlFunc, dbName);

			auto& wgSize = _shaderConversionResults.entryPoint.workgroupSize;
			return MVKMTLFunction(mtlFunc, _shaderConversionResults, MTLSizeMake(getWorkgroupDimensionSize(wgSize.width, pSpecializationInfo),
																				 getWorkgroupDimensionSize(wgSize.height, pSpecializationInfo),
																				 getWorkgroupDimensionSize(wgSize.depth, pSpecializationInfo)));
		}
	}
}

void MVKShaderLibrary::setEntryPointName(string& funcName) {
	_shaderConversionResults.entryPoint.mtlFunctionName = funcName;
}

void MVKShaderLibrary::setWorkgroupSize(uint32_t x, uint32_t y, uint32_t z) {
	auto& wgSize = _shaderConversionResults.entryPoint.workgroupSize;
	wgSize.width.size = x;
	wgSize.height.size = y;
	wgSize.depth.size = z;
}

MVKShaderLibrary::MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
								   const string& mslSourceCode,
								   const SPIRVToMSLConversionResults& shaderConversionResults) : _owner(owner) {
	MVKShaderLibraryCompiler* slc = new MVKShaderLibraryCompiler(_owner);

	NSString* nsSrc = [[NSString alloc] initWithUTF8String: mslSourceCode.c_str()];					// temp retained
	_mtlLibrary = slc->newMTLLibrary(nsSrc, shaderConversionResults);	// retained
	[nsSrc release];	// release temp string

	slc->destroy();

	_shaderConversionResults = shaderConversionResults;
	_msl = mslSourceCode;
}

MVKShaderLibrary::MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
                                   const void* mslCompiledCodeData,
                                   size_t mslCompiledCodeLength) : _owner(owner) {
	MVKDevice* mvkDev = _owner->getDevice();
    uint64_t startTime = mvkDev->getPerformanceTimestamp();
    @autoreleasepool {
        dispatch_data_t shdrData = dispatch_data_create(mslCompiledCodeData,
                                                        mslCompiledCodeLength,
                                                        NULL,
                                                        DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        NSError* err = nil;
        _mtlLibrary = [mvkDev->getMTLDevice() newLibraryWithData: shdrData error: &err];    // retained
        handleCompilationError(err, "Compiled shader module creation");
        [shdrData release];
    }
    mvkDev->addActivityPerformance(mvkDev->_performanceStatistics.shaderCompilation.mslLoad, startTime);
}

MVKShaderLibrary::MVKShaderLibrary(const MVKShaderLibrary& other) : _owner(other._owner) {
	_mtlLibrary = [other._mtlLibrary retain];
	_shaderConversionResults = other._shaderConversionResults;
	_msl = other._msl;
}

// If err object is nil, the compilation succeeded without any warnings.
// If err object exists, and the MTLLibrary was created, the compilation succeeded, but with warnings.
// If err object exists, and the MTLLibrary was not created, the compilation failed.
void MVKShaderLibrary::handleCompilationError(NSError* err, const char* opDesc) {
    if ( !err ) return;

    if (_mtlLibrary) {
        MVKLogInfo("%s succeeded with warnings (Error code %li):\n%s", opDesc, (long)err.code, err.localizedDescription.UTF8String);
    } else {
		_owner->setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV,
												   "%s failed (Error code %li):\n%s",
												   opDesc, (long)err.code,
												   err.localizedDescription.UTF8String));
    }
}

MVKShaderLibrary::~MVKShaderLibrary() {
	[_mtlLibrary release];
}


#pragma mark -
#pragma mark MVKShaderLibraryCache

MVKShaderLibrary* MVKShaderLibraryCache::getShaderLibrary(SPIRVToMSLConversionConfiguration* pContext,
														  MVKShaderModule* shaderModule,
														  bool* pWasAdded) {
	bool wasAdded = false;
	MVKShaderLibrary* shLib = findShaderLibrary(pContext);
	if ( !shLib ) {
		if (shaderModule->convert(pContext)) {
			shLib = addShaderLibrary(pContext, shaderModule->getMSL(), shaderModule->getConversionResults());
			wasAdded = true;
		}
	}

	if (pWasAdded) { *pWasAdded = wasAdded; }

	return shLib;
}

// Finds and returns a shader library matching the specified context, or returns nullptr if it doesn't exist.
// If a match is found, the specified context is aligned with the context of the matching library.
MVKShaderLibrary* MVKShaderLibraryCache::findShaderLibrary(SPIRVToMSLConversionConfiguration* pContext) {
	for (auto& slPair : _shaderLibraries) {
		if (slPair.first.matches(*pContext)) {
			pContext->alignWith(slPair.first);
			return slPair.second;
		}
	}
	return nullptr;
}

// Adds and returns a new shader library configured from the specified context.
MVKShaderLibrary* MVKShaderLibraryCache::addShaderLibrary(SPIRVToMSLConversionConfiguration* pContext,
														  const string& mslSourceCode,
														  const SPIRVToMSLConversionResults& shaderConversionResults) {
	MVKShaderLibrary* shLib = new MVKShaderLibrary(_owner, mslSourceCode, shaderConversionResults);
	_shaderLibraries.emplace_back(*pContext, shLib);
	return shLib;
}

// Merge another shader library cache with this one. Handle null input.
void MVKShaderLibraryCache::merge(MVKShaderLibraryCache* other) {
	if ( !other ) { return; }
	for (auto& otherPair : other->_shaderLibraries) {
		if ( !findShaderLibrary(&otherPair.first) ) {
			_shaderLibraries.emplace_back(otherPair.first, new MVKShaderLibrary(*otherPair.second));
			_shaderLibraries.back().second->_owner = _owner;
		}
	}
}

MVKShaderLibraryCache::~MVKShaderLibraryCache() {
	for (auto& slPair : _shaderLibraries) { slPair.second->destroy(); }
}


#pragma mark -
#pragma mark MVKShaderModule

MVKMTLFunction MVKShaderModule::getMTLFunction(SPIRVToMSLConversionConfiguration* pContext,
											   const VkSpecializationInfo* pSpecializationInfo,
											   MVKPipelineCache* pipelineCache) {
	lock_guard<mutex> lock(_accessLock);
	
	MVKShaderLibrary* mvkLib = _directMSLLibrary;
	if ( !mvkLib ) {
		uint64_t startTime = _device->getPerformanceTimestamp();
		if (pipelineCache) {
			mvkLib = pipelineCache->getShaderLibrary(pContext, this);
		} else {
			mvkLib = _shaderLibraryCache.getShaderLibrary(pContext, this);
		}
		_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.shaderLibraryFromCache, startTime);
	} else {
		mvkLib->setEntryPointName(pContext->options.entryPointName);
		pContext->markAllInputsAndResourcesUsed();
	}

	return mvkLib ? mvkLib->getMTLFunction(pSpecializationInfo, this) : MVKMTLFunctionNull;
}

bool MVKShaderModule::convert(SPIRVToMSLConversionConfiguration* pContext) {
	bool shouldLogCode = mvkGetMVKConfiguration()->debugMode;
	bool shouldLogEstimatedGLSL = shouldLogCode;

	// If the SPIR-V converter does not have any code, but the GLSL converter does,
	// convert the GLSL code to SPIR-V and set it into the SPIR-V conveter.
	if ( !_spvConverter.hasSPIRV() && _glslConverter.hasGLSL() ) {

		uint64_t startTime = _device->getPerformanceTimestamp();
		bool wasConverted = _glslConverter.convert(getMVKGLSLConversionShaderStage(pContext), shouldLogCode, false);
		_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.glslToSPRIV, startTime);

		if (wasConverted) {
			if (shouldLogCode) { MVKLogInfo("%s", _glslConverter.getResultLog().c_str()); }
			_spvConverter.setSPIRV(_glslConverter.getSPIRV());
		} else {
			reportError(VK_ERROR_INVALID_SHADER_NV, "Unable to convert GLSL to SPIR-V:\n%s", _glslConverter.getResultLog().c_str());
		}
		shouldLogEstimatedGLSL = false;
	}

	uint64_t startTime = _device->getPerformanceTimestamp();
	bool wasConverted = _spvConverter.convert(*pContext, shouldLogCode, shouldLogCode, shouldLogEstimatedGLSL);
	_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.spirvToMSL, startTime);

	if (wasConverted) {
		if (shouldLogCode) { MVKLogInfo("%s", _spvConverter.getResultLog().c_str()); }
	} else {
		reportError(VK_ERROR_INVALID_SHADER_NV, "Unable to convert SPIR-V to MSL:\n%s", _spvConverter.getResultLog().c_str());
	}
	return wasConverted;
}

// Returns the MVKGLSLConversionShaderStage corresponding to the shader stage in the SPIR-V converter context.
MVKGLSLConversionShaderStage MVKShaderModule::getMVKGLSLConversionShaderStage(SPIRVToMSLConversionConfiguration* pContext) {
	switch (pContext->options.entryPointStage) {
		case spv::ExecutionModelVertex:						return kMVKGLSLConversionShaderStageVertex;
		case spv::ExecutionModelTessellationControl:		return kMVKGLSLConversionShaderStageTessControl;
		case spv::ExecutionModelTessellationEvaluation:		return kMVKGLSLConversionShaderStageTessEval;
		case spv::ExecutionModelGeometry:					return kMVKGLSLConversionShaderStageGeometry;
		case spv::ExecutionModelFragment:					return kMVKGLSLConversionShaderStageFragment;
		case spv::ExecutionModelGLCompute:					return kMVKGLSLConversionShaderStageCompute;
		case spv::ExecutionModelKernel:						return kMVKGLSLConversionShaderStageCompute;

		default:
			MVKAssert(false, "Bad shader stage provided for GLSL to SPIR-V conversion.");
			return kMVKGLSLConversionShaderStageAuto;
	}
}

void MVKShaderModule::setWorkgroupSize(uint32_t x, uint32_t y, uint32_t z) {
	_spvConverter.setWorkgroupSize(x, y, z);
	if(_directMSLLibrary) { _directMSLLibrary->setWorkgroupSize(x, y, z); }
}


#pragma mark Construction

MVKShaderModule::MVKShaderModule(MVKDevice* device,
								 const VkShaderModuleCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device), _shaderLibraryCache(this) {

	_directMSLLibrary = nullptr;

	size_t codeSize = pCreateInfo->codeSize;

    // Ensure something is there.
    if ( (pCreateInfo->pCode == VK_NULL_HANDLE) || (codeSize < 4) ) {
		setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "vkCreateShaderModule(): Shader module contains no shader code."));
		return;
	}

	size_t codeHash = 0;

	// Retrieve the magic number to determine what type of shader code has been loaded.
	// NOTE: Shader code should be submitted as SPIR-V. Although some simple direct MSL shaders may work,
	// direct loading of MSL source code or compiled MSL code is not officially supported at this time.
	// Future versions of MoltenVK may support direct MSL submission again.
	uint32_t magicNum = *pCreateInfo->pCode;
	switch (magicNum) {
		case kMVKMagicNumberSPIRVCode: {					// SPIR-V code
			size_t spvCount = (codeSize + 3) >> 2;			// Round up if byte length not exactly on uint32_t boundary

			uint64_t startTime = _device->getPerformanceTimestamp();
			codeHash = mvkHash(pCreateInfo->pCode, spvCount);
			_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

			_spvConverter.setSPIRV(pCreateInfo->pCode, spvCount);

			break;
		}
		case kMVKMagicNumberMSLSourceCode: {				// MSL source code
			size_t hdrSize = sizeof(MVKMSLSPIRVHeader);
			char* pMSLCode = (char*)(uintptr_t(pCreateInfo->pCode) + hdrSize);
			size_t mslCodeLen = codeSize - hdrSize;

			uint64_t startTime = _device->getPerformanceTimestamp();
			codeHash = mvkHash(&magicNum);
			codeHash = mvkHash(pMSLCode, mslCodeLen, codeHash);
			_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

			_spvConverter.setMSL(pMSLCode, nullptr);
			_directMSLLibrary = new MVKShaderLibrary(this, _spvConverter.getMSL().c_str(), _spvConverter.getConversionResults());

			break;
		}
		case kMVKMagicNumberMSLCompiledCode: {				// MSL compiled binary code
			size_t hdrSize = sizeof(MVKMSLSPIRVHeader);
			char* pMSLCode = (char*)(uintptr_t(pCreateInfo->pCode) + hdrSize);
			size_t mslCodeLen = codeSize - hdrSize;

			uint64_t startTime = _device->getPerformanceTimestamp();
			codeHash = mvkHash(&magicNum);
			codeHash = mvkHash(pMSLCode, mslCodeLen, codeHash);
			_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

			_directMSLLibrary = new MVKShaderLibrary(this, (void*)(pMSLCode), mslCodeLen);

			break;
		}
		default:											// Could be GLSL source code
			if (_device->_enabledExtensions.vk_NV_glsl_shader.enabled) {
				const char* pGLSL = (char*)pCreateInfo->pCode;
				size_t glslLen = codeSize - 1;

				uint64_t startTime = _device->getPerformanceTimestamp();
				codeHash = mvkHash(pGLSL, codeSize);
				_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

				_glslConverter.setGLSL(pGLSL, glslLen);
			} else {
				setConfigurationResult(reportError(VK_ERROR_INVALID_SHADER_NV, "vkCreateShaderModule(): The SPIR-V contains an invalid magic number %x.", magicNum));
			}
			break;
	}

	_key = MVKShaderModuleKey(codeSize, codeHash);
}

MVKShaderModule::~MVKShaderModule() {
	if (_directMSLLibrary) { _directMSLLibrary->destroy(); }
}


#pragma mark -
#pragma mark MVKShaderLibraryCompiler

id<MTLLibrary> MVKShaderLibraryCompiler::newMTLLibrary(NSString* mslSourceCode,
													   const SPIRVToMSLConversionResults& shaderConversionResults) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		auto mtlDev = _owner->getMTLDevice();
		@synchronized (mtlDev) {
			[mtlDev newLibraryWithSource: mslSourceCode
								 options: _owner->getDevice()->getMTLCompileOptions(shaderConversionResults.entryPoint.supportsFastMath,
																					shaderConversionResults.isPositionInvariant)
					   completionHandler: ^(id<MTLLibrary> mtlLib, NSError* error) {
						   bool isLate = compileComplete(mtlLib, error);
						   if (isLate) { destroy(); }
					   }];
		}
	});

	return [_mtlLibrary retain];
}

void MVKShaderLibraryCompiler::handleError() {
	if (_mtlLibrary) {
		MVKLogInfo("%s compilation succeeded with warnings (Error code %li):\n%s", _compilerType.c_str(),
				   (long)_compileError.code, _compileError.localizedDescription.UTF8String);
	} else {
		MVKMetalCompiler::handleError();
	}
}

bool MVKShaderLibraryCompiler::compileComplete(id<MTLLibrary> mtlLibrary, NSError* compileError) {
	lock_guard<mutex> lock(_completionLock);

	_mtlLibrary = [mtlLibrary retain];		// retained
	return endCompile(compileError);
}

#pragma mark Construction

MVKShaderLibraryCompiler::~MVKShaderLibraryCompiler() {
	[_mtlLibrary release];
}


#pragma mark -
#pragma mark MVKFunctionSpecializer

id<MTLFunction> MVKFunctionSpecializer::newMTLFunction(id<MTLLibrary> mtlLibrary,
													   NSString* funcName,
													   MTLFunctionConstantValues* constantValues) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		[mtlLibrary newFunctionWithName: funcName
						 constantValues: constantValues
					  completionHandler: ^(id<MTLFunction> mtlFunc, NSError* error) {
						  bool isLate = compileComplete(mtlFunc, error);
						  if (isLate) { destroy(); }
					  }];
	});

	return [_mtlFunction retain];
}

bool MVKFunctionSpecializer::compileComplete(id<MTLFunction> mtlFunction, NSError* compileError) {
	lock_guard<mutex> lock(_completionLock);

	_mtlFunction = [mtlFunction retain];		// retained
	return endCompile(compileError);
}

#pragma mark Construction

MVKFunctionSpecializer::~MVKFunctionSpecializer() {
	[_mtlFunction release];
}

