/*
 * MVKShaderModule.mm
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

#include "MVKShaderModule.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"

using namespace std;


MVKMTLFunction::MVKMTLFunction(id<MTLFunction> mtlFunc, const SPIRVToMSLConversionResultInfo scRslts, MTLSize tgSize) {
	_mtlFunction = [mtlFunc retain];		// retained
	shaderConversionResults = scRslts;
	threadGroupSize = tgSize;
}

MVKMTLFunction::MVKMTLFunction(const MVKMTLFunction& other) {
	_mtlFunction = [other._mtlFunction retain];		// retained
	shaderConversionResults = other.shaderConversionResults;
	threadGroupSize = other.threadGroupSize;
}

MVKMTLFunction& MVKMTLFunction::operator=(const MVKMTLFunction& other) {
	// Retain new object first in case it's the same object
	[other._mtlFunction retain];
	[_mtlFunction release];
	_mtlFunction = other._mtlFunction;

	shaderConversionResults = other.shaderConversionResults;
	threadGroupSize = other.threadGroupSize;
	return *this;
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

MVKMTLFunction MVKShaderLibrary::getMTLFunction(const VkSpecializationInfo* pSpecializationInfo,
												VkPipelineCreationFeedback* pShaderFeedback,
												MVKShaderModule* shaderModule) {

	if ( !_mtlLibrary ) { return MVKMTLFunctionNull; }

	@synchronized (_owner->getMTLDevice()) {
		@autoreleasepool {
			NSString* mtlFuncName = @(_shaderConversionResultInfo.entryPoint.mtlFunctionName.c_str());
			MVKDevice* mvkDev = _owner->getDevice();

			uint64_t startTime = pShaderFeedback ? mvkGetTimestamp() : mvkDev->getPerformanceTimestamp();
			id<MTLFunction> mtlFunc = [[_mtlLibrary newFunctionWithName: mtlFuncName] autorelease];
			mvkDev->addPerformanceInterval(mvkDev->_performanceStatistics.shaderCompilation.functionRetrieval, startTime);
			if (pShaderFeedback) {
				if (mtlFunc) {
					mvkEnableFlags(pShaderFeedback->flags, VK_PIPELINE_CREATION_FEEDBACK_VALID_BIT);
				}
				pShaderFeedback->duration += mvkGetElapsedNanoseconds(startTime);
			}

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
						if (pShaderFeedback) {
							startTime = mvkGetTimestamp();
						}
						mtlFunc = [fs.newMTLFunction(_mtlLibrary, mtlFuncName, mtlFCVals) autorelease];
						if (pShaderFeedback) {
							pShaderFeedback->duration += mvkGetElapsedNanoseconds(startTime);
						}
					}
				}
			}

			// Set the debug name. First try name of shader module, otherwise try name of owner.
			NSString* dbName = shaderModule-> getDebugName();
			if ( !dbName ) { dbName = _owner-> getDebugName(); }
			setLabelIfNotNil(mtlFunc, dbName);

			auto& wgSize = _shaderConversionResultInfo.entryPoint.workgroupSize;
			return MVKMTLFunction(mtlFunc, _shaderConversionResultInfo, MTLSizeMake(getWorkgroupDimensionSize(wgSize.width, pSpecializationInfo),
																				 getWorkgroupDimensionSize(wgSize.height, pSpecializationInfo),
																				 getWorkgroupDimensionSize(wgSize.depth, pSpecializationInfo)));
		}
	}
}

void MVKShaderLibrary::setEntryPointName(string& funcName) {
	_shaderConversionResultInfo.entryPoint.mtlFunctionName = funcName;
}

void MVKShaderLibrary::setWorkgroupSize(uint32_t x, uint32_t y, uint32_t z) {
	auto& wgSize = _shaderConversionResultInfo.entryPoint.workgroupSize;
	wgSize.width.size = x;
	wgSize.height.size = y;
	wgSize.depth.size = z;
}

// Sets the cached MSL source code, after first compressing it.
void MVKShaderLibrary::compressMSL(const string& msl) {
	MVKDevice* mvkDev = _owner->getDevice();
	uint64_t startTime = mvkDev->getPerformanceTimestamp();
	_compressedMSL.compress(msl, getMVKConfig().shaderSourceCompressionAlgorithm);
	mvkDev->addPerformanceInterval(mvkDev->_performanceStatistics.shaderCompilation.mslCompress, startTime);
}

// Decompresses the cached MSL into the string.
void MVKShaderLibrary::decompressMSL(string& msl) {
	MVKDevice* mvkDev = _owner->getDevice();
	uint64_t startTime = mvkDev->getPerformanceTimestamp();
	_compressedMSL.decompress(msl);
	mvkDev->addPerformanceInterval(mvkDev->_performanceStatistics.shaderCompilation.mslDecompress, startTime);
}

MVKShaderLibrary::MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
								   const SPIRVToMSLConversionResult& conversionResult) : _owner(owner) {
	_shaderConversionResultInfo = conversionResult.resultInfo;
	compressMSL(conversionResult.msl);
	compileLibrary(conversionResult.msl);
}

MVKShaderLibrary::MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
								   const SPIRVToMSLConversionResultInfo& resultInfo,
								   const MVKCompressor<std::string> compressedMSL) : _owner(owner) {
	_shaderConversionResultInfo = resultInfo;
	_compressedMSL = compressedMSL;
	string msl;
	decompressMSL(msl);
	compileLibrary(msl);
}

void MVKShaderLibrary::compileLibrary(const string& msl) {
	MVKShaderLibraryCompiler* slc = new MVKShaderLibraryCompiler(_owner);
	NSString* nsSrc = [[NSString alloc] initWithUTF8String: msl.c_str()];	// temp retained
	_mtlLibrary = slc->newMTLLibrary(nsSrc, _shaderConversionResultInfo);	// retained
	[nsSrc release];														// release temp string
	slc->destroy();
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
    mvkDev->addPerformanceInterval(mvkDev->_performanceStatistics.shaderCompilation.mslLoad, startTime);
}

MVKShaderLibrary::MVKShaderLibrary(const MVKShaderLibrary& other) {
	_owner = other._owner;
	_mtlLibrary = [other._mtlLibrary retain];
	_shaderConversionResultInfo = other._shaderConversionResultInfo;
	_compressedMSL = other._compressedMSL;
}

MVKShaderLibrary& MVKShaderLibrary::operator=(const MVKShaderLibrary& other) {
	if (_mtlLibrary != other._mtlLibrary) {
		[_mtlLibrary release];
		_mtlLibrary = [other._mtlLibrary retain];
	}
	_owner = other._owner;
	_shaderConversionResultInfo = other._shaderConversionResultInfo;
	_compressedMSL = other._compressedMSL;
	return *this;
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

MVKShaderLibrary* MVKShaderLibraryCache::getShaderLibrary(SPIRVToMSLConversionConfiguration* pShaderConfig,
														  MVKShaderModule* shaderModule, MVKPipeline* pipeline,
														  bool* pWasAdded, VkPipelineCreationFeedback* pShaderFeedback,
														  uint64_t startTime) {
	bool wasAdded = false;
	MVKShaderLibrary* shLib = findShaderLibrary(pShaderConfig, pShaderFeedback, startTime);
	if ( !shLib && !pipeline->shouldFailOnPipelineCompileRequired() ) {
		SPIRVToMSLConversionResult conversionResult;
		if (shaderModule->convert(pShaderConfig, conversionResult)) {
			shLib = addShaderLibrary(pShaderConfig, conversionResult);
			if (pShaderFeedback) {
				pShaderFeedback->duration += mvkGetElapsedNanoseconds(startTime);
			}
			wasAdded = true;
		}
	}

	if (pWasAdded) { *pWasAdded = wasAdded; }

	return shLib;
}

// Finds and returns a shader library matching the shader config, or returns nullptr if it doesn't exist.
// If a match is found, the shader config is aligned with the shader config of the matching library.
MVKShaderLibrary* MVKShaderLibraryCache::findShaderLibrary(SPIRVToMSLConversionConfiguration* pShaderConfig,
														   VkPipelineCreationFeedback* pShaderFeedback,
														   uint64_t startTime) {
	for (auto& slPair : _shaderLibraries) {
		if (slPair.first.matches(*pShaderConfig)) {
			pShaderConfig->alignWith(slPair.first);
			MVKDevice* mvkDev = _owner->getDevice();
			mvkDev->addPerformanceInterval(mvkDev->_performanceStatistics.shaderCompilation.shaderLibraryFromCache, startTime);
			if (pShaderFeedback) {
				pShaderFeedback->duration += mvkGetElapsedNanoseconds(startTime);
			}
			return slPair.second;
		}
	}
	return nullptr;
}

// Adds and returns a new shader library configured from the specified conversion configuration.
MVKShaderLibrary* MVKShaderLibraryCache::addShaderLibrary(const SPIRVToMSLConversionConfiguration* pShaderConfig,
														  const SPIRVToMSLConversionResult& conversionResult) {
	MVKShaderLibrary* shLib = new MVKShaderLibrary(_owner, conversionResult);
	_shaderLibraries.emplace_back(*pShaderConfig, shLib);
	return shLib;
}

// Adds and returns a new shader library configured from contents read from a pipeline cache.
MVKShaderLibrary* MVKShaderLibraryCache::addShaderLibrary(const SPIRVToMSLConversionConfiguration* pShaderConfig,
														  const SPIRVToMSLConversionResultInfo& resultInfo,
														  const MVKCompressor<std::string> compressedMSL) {
	MVKShaderLibrary* shLib = new MVKShaderLibrary(_owner, resultInfo, compressedMSL);
	_shaderLibraries.emplace_back(*pShaderConfig, shLib);
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

MVKMTLFunction MVKShaderModule::getMTLFunction(SPIRVToMSLConversionConfiguration* pShaderConfig,
											   const VkSpecializationInfo* pSpecializationInfo,
											   MVKPipeline* pipeline,
											   VkPipelineCreationFeedback* pShaderFeedback) {
	MVKShaderLibrary* mvkLib = _directMSLLibrary;
	if ( !mvkLib ) {
		uint64_t startTime = pShaderFeedback ? mvkGetTimestamp() : _device->getPerformanceTimestamp();
		MVKPipelineCache* pipelineCache = pipeline->getPipelineCache();
		if (pipelineCache) {
			mvkLib = pipelineCache->getShaderLibrary(pShaderConfig, this, pipeline, pShaderFeedback, startTime);
		} else {
			lock_guard<mutex> lock(_accessLock);
			mvkLib = _shaderLibraryCache.getShaderLibrary(pShaderConfig, this, pipeline, nullptr, pShaderFeedback, startTime);
		}
	} else {
		mvkLib->setEntryPointName(pShaderConfig->options.entryPointName);
		pShaderConfig->markAllInterfaceVarsAndResourcesUsed();
	}

	return mvkLib ? mvkLib->getMTLFunction(pSpecializationInfo, pShaderFeedback, this) : MVKMTLFunctionNull;
}

bool MVKShaderModule::convert(SPIRVToMSLConversionConfiguration* pShaderConfig,
							  SPIRVToMSLConversionResult& conversionResult) {
	bool shouldLogCode = getMVKConfig().debugMode;
	bool shouldLogEstimatedGLSL = shouldLogCode;

	// If the SPIR-V converter does not have any code, but the GLSL converter does,
	// convert the GLSL code to SPIR-V and set it into the SPIR-V conveter.
	if ( !_spvConverter.hasSPIRV() && _glslConverter.hasGLSL() ) {

		GLSLToSPIRVConversionResult glslConversionResult;
		uint64_t startTime = _device->getPerformanceTimestamp();
		bool wasConverted = _glslConverter.convert(getMVKGLSLConversionShaderStage(pShaderConfig), glslConversionResult, shouldLogCode, false);
		_device->addPerformanceInterval(_device->_performanceStatistics.shaderCompilation.glslToSPRIV, startTime);

		if (wasConverted) {
			if (shouldLogCode) { MVKLogInfo("%s", glslConversionResult.resultLog.c_str()); }
			_spvConverter.setSPIRV(glslConversionResult.spirv);
		} else {
			reportError(VK_ERROR_INVALID_SHADER_NV, "Unable to convert GLSL to SPIR-V:\n%s", glslConversionResult.resultLog.c_str());
		}
		shouldLogEstimatedGLSL = false;
	}

	uint64_t startTime = _device->getPerformanceTimestamp();
	bool wasConverted = _spvConverter.convert(*pShaderConfig, conversionResult, shouldLogCode, shouldLogCode, shouldLogEstimatedGLSL);
	_device->addPerformanceInterval(_device->_performanceStatistics.shaderCompilation.spirvToMSL, startTime);

	if (wasConverted) {
		if (shouldLogCode) { MVKLogInfo("%s", conversionResult.resultLog.c_str()); }
	} else {
		reportError(VK_ERROR_INVALID_SHADER_NV, "Unable to convert SPIR-V to MSL:\n%s", conversionResult.resultLog.c_str());
	}
	return wasConverted;
}

// Returns the MVKGLSLConversionShaderStage corresponding to the shader stage in the SPIR-V conversion configuration.
MVKGLSLConversionShaderStage MVKShaderModule::getMVKGLSLConversionShaderStage(SPIRVToMSLConversionConfiguration* pShaderConfig) {
	switch (pShaderConfig->options.entryPointStage) {
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
			_device->addPerformanceInterval(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

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
			_device->addPerformanceInterval(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

			SPIRVToMSLConversionResult conversionResult;
			conversionResult.msl = pMSLCode;
			_directMSLLibrary = new MVKShaderLibrary(this, conversionResult);

			break;
		}
		case kMVKMagicNumberMSLCompiledCode: {				// MSL compiled binary code
			size_t hdrSize = sizeof(MVKMSLSPIRVHeader);
			char* pMSLCode = (char*)(uintptr_t(pCreateInfo->pCode) + hdrSize);
			size_t mslCodeLen = codeSize - hdrSize;

			uint64_t startTime = _device->getPerformanceTimestamp();
			codeHash = mvkHash(&magicNum);
			codeHash = mvkHash(pMSLCode, mslCodeLen, codeHash);
			_device->addPerformanceInterval(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

			_directMSLLibrary = new MVKShaderLibrary(this, (void*)(pMSLCode), mslCodeLen);

			break;
		}
		default:											// Could be GLSL source code
			if (_device->_enabledExtensions.vk_NV_glsl_shader.enabled) {
				const char* pGLSL = (char*)pCreateInfo->pCode;
				size_t glslLen = codeSize - 1;

				uint64_t startTime = _device->getPerformanceTimestamp();
				codeHash = mvkHash(pGLSL, codeSize);
				_device->addPerformanceInterval(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

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
													   const SPIRVToMSLConversionResultInfo& shaderConversionResults) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		auto mtlDev = _owner->getMTLDevice();
		@synchronized (mtlDev) {
			auto mtlCompileOptions = _owner->getDevice()->getMTLCompileOptions(shaderConversionResults.entryPoint.supportsFastMath,
																			   shaderConversionResults.isPositionInvariant);
			MVKLogInfoIf(getMVKConfig().debugMode, "Compiling Metal shader%s.", mtlCompileOptions.fastMathEnabled ? " with FastMath enabled" : "");
			[mtlDev newLibraryWithSource: mslSourceCode
								 options: mtlCompileOptions
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

