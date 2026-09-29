/*
 * MVKShaderModule.mm
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

#include "MVKShaderModule.h"
#include <MoltenVKShaderConverter/SPIRVBlendInShader.h>
#include <MoltenVKShaderConverter/SPIRVVertexPulling.h>
#include "MVKPipeline.h"
#include <MoltenVKShaderConverter/SPIRVDepthClip.h>
#include "MVKFoundation.h"
#include <sys/stat.h>

using namespace std;
using namespace mvk;

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

	id<MTLLibrary> lib = _mtlLibrary;

	// If specialization happens on constants mapped to macro, find or compile a library variant
	// with proper macro definition instead of the "generic" library
	if (pSpecializationInfo && _maySpecializeWithMacro) {
		// Create the list of macro-value mapping
		vector<pair<uint32_t, MVKShaderMacroValue>> spec_list;
		for (uint32_t specIdx = 0; specIdx < pSpecializationInfo->mapEntryCount; specIdx++) {
			const VkSpecializationMapEntry* pMapEntry = &pSpecializationInfo->pMapEntries[specIdx];
			uint32_t const_id = pMapEntry->constantID;
			MVKShaderMacroValue macro_value = {};
			size_t size = min(pMapEntry->size, sizeof(macro_value.value));

			memcpy(&macro_value.value, (char *)pSpecializationInfo->pData + pMapEntry->offset, size);
			macro_value.size = size;
			if (_shaderConversionResultInfo.specializationMacros.find(const_id) != _shaderConversionResultInfo.specializationMacros.end()) {
				spec_list.push_back(make_pair(const_id, macro_value));
			}
		}

		if (!spec_list.empty()) {
			// Sort the specialization list before it is used as a key to index the variants
			std::sort(spec_list.begin(), spec_list.end());
			auto entry = _specializationVariants.find(spec_list);
			if (entry != _specializationVariants.end()) {
				lib = entry->second->_mtlLibrary;
			} else {
				MVKShaderLibrary *new_mvklib = new MVKShaderLibrary(_owner, _shaderConversionResultInfo, _compressedMSL, &spec_list);
				_specializationVariants[spec_list] = new_mvklib;
				lib = new_mvklib->_mtlLibrary;
			}
		}
	}


	@synchronized (getMTLDevice()) {
		@autoreleasepool {
			NSString* mtlFuncName = @(_shaderConversionResultInfo.entryPoint.mtlFunctionName.c_str());

			uint64_t startTime = pShaderFeedback ? mvkGetTimestamp() : getPerformanceTimestamp();
			id<MTLFunction> mtlFunc = [[lib newFunctionWithName: mtlFuncName] autorelease];
			addPerformanceInterval(getPerformanceStats().shaderCompilation.functionRetrieval, startTime);
			if (pShaderFeedback) {
				if (mtlFunc) {
					mvkEnableFlags(pShaderFeedback->flags, VK_PIPELINE_CREATION_FEEDBACK_VALID_BIT);
				}
				pShaderFeedback->duration += mvkGetElapsedNanoseconds(startTime);
			}

			if (mtlFunc) {
				// If the Metal function expects to be specialized, populate Metal function constant values from
				// the Vulkan specialization info, and compile a specialized Metal function, otherwise simply use
				// the unspecialized Metal function.
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
					mtlFunc = [fs.newMTLFunction(lib, mtlFuncName, mtlFCVals) autorelease];
					if (pShaderFeedback) {
						pShaderFeedback->duration += mvkGetElapsedNanoseconds(startTime);
					}
				}
			}

			// Set the debug name. First try name of shader module, otherwise try name of owner.
			NSString* dbName = shaderModule->getDebugName();
			if ( !dbName ) { dbName = _owner->getDebugName(); }
			_owner->setMetalObjectLabel(mtlFunc, dbName);

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
	uint64_t startTime = getPerformanceTimestamp();
	_compressedMSL.compress(msl, getMVKConfig().shaderSourceCompressionAlgorithm);
	addPerformanceInterval(getPerformanceStats().shaderCompilation.mslCompress, startTime);
}

// Decompresses the cached MSL into the string.
void MVKShaderLibrary::decompressMSL(string& msl) {
	uint64_t startTime = getPerformanceTimestamp();
	_compressedMSL.decompress(msl);
	addPerformanceInterval(getPerformanceStats().shaderCompilation.mslDecompress, startTime);
}

MVKShaderLibrary::MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
								   const SPIRVToMSLConversionResult& conversionResult) :
	MVKBaseDeviceObject(owner->getDevice()),
	_owner(owner),
	_maySpecializeWithMacro(true) {

	_shaderConversionResultInfo = conversionResult.resultInfo;
	compressMSL(conversionResult.msl);
	compileLibrary(conversionResult.msl);
}

MVKShaderLibrary::MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
								   const SPIRVToMSLConversionResultInfo& resultInfo,
								   const MVKCompressor<std::string> compressedMSL,
								   const vector<pair<uint32_t, MVKShaderMacroValue> >* specializationMacroDef) :
	MVKBaseDeviceObject(owner->getDevice()),
	_owner(owner),
	_maySpecializeWithMacro(specializationMacroDef == nullptr) {

	_shaderConversionResultInfo = resultInfo;
	_compressedMSL = compressedMSL;
	string msl;
	decompressMSL(msl);
	compileLibrary(msl, specializationMacroDef);
}

void MVKShaderLibrary::compileLibrary(const string& msl,
									  const vector<pair<uint32_t, MVKShaderMacroValue> >* specializationMacroDef) {
	MVKShaderLibraryCompiler* slc = new MVKShaderLibraryCompiler(_owner);
	NSString* nsSrc = [[NSString alloc] initWithUTF8String: msl.c_str()];	// temp retained

	// If specialization macro is used, translate the id to macro information and pass it to compiler
	vector<pair<MSLSpecializationMacroInfo, MVKShaderMacroValue>> macro_def;
	if (specializationMacroDef) {
		for (auto& def: *specializationMacroDef) {
			const auto& macro_name_iter = _shaderConversionResultInfo.specializationMacros.find(def.first);
			if (macro_name_iter != _shaderConversionResultInfo.specializationMacros.end()) {
				macro_def.push_back(make_pair(macro_name_iter->second, def.second));
			}
		}
	}

	_mtlLibrary = slc->newMTLLibrary(nsSrc, _shaderConversionResultInfo, macro_def);	// retained
	[nsSrc release];														// release temp string
	slc->destroy();
}

MVKShaderLibrary::MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
                                   const void* mslCompiledCodeData,
                                   size_t mslCompiledCodeLength) :
	MVKBaseDeviceObject(owner->getDevice()),
	_owner(owner),
	_maySpecializeWithMacro(false) {

    uint64_t startTime = getPerformanceTimestamp();
    @autoreleasepool {
        dispatch_data_t shdrData = dispatch_data_create(mslCompiledCodeData,
                                                        mslCompiledCodeLength,
                                                        NULL,
                                                        DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        NSError* err = nil;
        _mtlLibrary = [getMTLDevice() newLibraryWithData: shdrData error: &err];    // retained
        handleCompilationError(err, "Compiled shader module creation");
        [shdrData release];
    }
	addPerformanceInterval(getPerformanceStats().shaderCompilation.mslLoad, startTime);
}

MVKShaderLibrary::MVKShaderLibrary(const MVKShaderLibrary& other) :
	MVKBaseDeviceObject(other._device),
	_owner(other._owner),
	_maySpecializeWithMacro(other._maySpecializeWithMacro),
	_specializationVariants(other._specializationVariants) {

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
		_owner->setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED,
												   "%s failed (Error code %li):\n%s",
												   opDesc, (long)err.code,
												   err.localizedDescription.UTF8String));
    }
}

MVKShaderLibrary::~MVKShaderLibrary() {
	[_mtlLibrary release];

	for (auto& item: _specializationVariants) {
		delete item.second;
	}
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
			addPerformanceInterval(getPerformanceStats().shaderCompilation.shaderLibraryFromCache, startTime);
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
		uint64_t startTime = pShaderFeedback ? mvkGetTimestamp() : getPerformanceTimestamp();
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
	const auto& mvkCfg = getMVKConfig();
	bool shouldLogCode = mvkCfg.debugMode;
	bool shouldLogEstimatedGLSL = shouldLogCode && mvkCfg.shaderLogEstimatedGLSL;

	uint64_t startTime = getPerformanceTimestamp();
	bool wasConverted = _spvConverter.convert(*pShaderConfig, conversionResult, shouldLogCode, shouldLogCode, shouldLogEstimatedGLSL);
	addPerformanceInterval(getPerformanceStats().shaderCompilation.spirvToMSL, startTime);

	const char* dumpDir = getMVKConfig().shaderDumpDir;
	if (dumpDir && *dumpDir) {
		char path[PATH_MAX];
		const char* type;
		switch (pShaderConfig->options.entryPointStage) {
			case spv::ExecutionModelVertex:                 type = "-vs"; break;
			case spv::ExecutionModelTessellationControl:    type = "-tcs"; break;
			case spv::ExecutionModelTessellationEvaluation: type = "-tes"; break;
			case spv::ExecutionModelFragment:               type = "-fs"; break;
			case spv::ExecutionModelGeometry:               type = "-gs"; break;
			case spv::ExecutionModelTaskNV:                 type = "-ts"; break;
			case spv::ExecutionModelMeshNV:                 type = "-ms"; break;
			case spv::ExecutionModelGLCompute:              type = "-cs"; break;
			default:                                        type = "";    break;
		}
		mkdir(dumpDir, 0755);
		snprintf(path, sizeof(path), "%s/shader%s-%016zx.spv", dumpDir, type, _key.codeHash);
		FILE* file = fopen(path, "wb");
		if (file) {
			fwrite(_spvConverter.getSPIRV().data(), sizeof(uint32_t), _spvConverter.getSPIRV().size(), file);
			fclose(file);
		}
		snprintf(path, sizeof(path), "%s/shader%s-%016zx.metal", dumpDir, type, _key.codeHash);
		file = fopen(path, "wb");
		if (file) {
			if (wasConverted) {
				fwrite(conversionResult.msl.data(), 1, conversionResult.msl.size(), file);
				fclose(file);
			} else {
				fputs("Failed to convert:\n", file);
				fwrite(conversionResult.resultLog.data(), 1, conversionResult.resultLog.size(), file);
				fclose(file);
			}
		}
	}

	if (wasConverted) {
		if (shouldLogCode) { MVKLogInfo("%s", conversionResult.resultLog.c_str()); }
	} else {
		reportError(VK_ERROR_INITIALIZATION_FAILED, "Unable to convert SPIR-V to MSL:\n%s", conversionResult.resultLog.c_str());
	}
	return wasConverted;
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
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateShaderModule(): Shader module contains no shader code."));
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

			uint64_t startTime = getPerformanceTimestamp();
			codeHash = mvkHash(pCreateInfo->pCode, spvCount);
			addPerformanceInterval(getPerformanceStats().shaderCompilation.hashShaderCode, startTime);

			_spvConverter.setSPIRV(pCreateInfo->pCode, spvCount);

			break;
		}
		case kMVKMagicNumberMSLSourceCode: {				// MSL source code
			size_t hdrSize = sizeof(MVKMSLSPIRVHeader);
			char* pMSLCode = (char*)(uintptr_t(pCreateInfo->pCode) + hdrSize);
			size_t mslCodeLen = codeSize - hdrSize;

			uint64_t startTime = getPerformanceTimestamp();
			codeHash = mvkHash(&magicNum);
			codeHash = mvkHash(pMSLCode, mslCodeLen, codeHash);
			addPerformanceInterval(getPerformanceStats().shaderCompilation.hashShaderCode, startTime);

			SPIRVToMSLConversionResult conversionResult;
			conversionResult.msl = pMSLCode;
			_directMSLLibrary = new MVKShaderLibrary(this, conversionResult);

			break;
		}
		case kMVKMagicNumberMSLCompiledCode: {				// MSL compiled binary code
			size_t hdrSize = sizeof(MVKMSLSPIRVHeader);
			char* pMSLCode = (char*)(uintptr_t(pCreateInfo->pCode) + hdrSize);
			size_t mslCodeLen = codeSize - hdrSize;

			uint64_t startTime = getPerformanceTimestamp();
			codeHash = mvkHash(&magicNum);
			codeHash = mvkHash(pMSLCode, mslCodeLen, codeHash);
			addPerformanceInterval(getPerformanceStats().shaderCompilation.hashShaderCode, startTime);

			_directMSLLibrary = new MVKShaderLibrary(this, (void*)(pMSLCode), mslCodeLen);

			break;
		}
		default:
			setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateShaderModule(): The SPIR-V contains an invalid magic number %x.", magicNum));
			break;
	}

	_key = MVKShaderModuleKey(codeSize, codeHash);
}

MVKShaderModule::~MVKShaderModule() {
	if (_directMSLLibrary) { _directMSLLibrary->destroy(); }
}


#pragma mark -
#pragma mark MVKShader

void MVKShader::initSpecialization(const VkSpecializationInfo* pSpecInfo) {
	if ( !pSpecInfo ) { return; }

	_specializationEntries.reserve(pSpecInfo->mapEntryCount);
	for (uint32_t i = 0; i < pSpecInfo->mapEntryCount; i++) {
		_specializationEntries.push_back(pSpecInfo->pMapEntries[i]);
	}
	_specializationData.resize(pSpecInfo->dataSize);
	if (pSpecInfo->dataSize) { memcpy(_specializationData.data(), pSpecInfo->pData, pSpecInfo->dataSize); }

	_specializationInfo.mapEntryCount = pSpecInfo->mapEntryCount;
	_specializationInfo.pMapEntries = _specializationEntries.data();
	_specializationInfo.dataSize = pSpecInfo->dataSize;
	_specializationInfo.pData = _specializationData.data();
	_hasSpecializationInfo = true;
}

void MVKShader::initLayout(const VkShaderCreateInfoEXT* pCreateInfo) {
	VkPipelineLayoutCreateInfo plCreateInfo = {
		.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
		.pNext = nullptr,
		.flags = 0,
		.setLayoutCount = pCreateInfo->setLayoutCount,
		.pSetLayouts = pCreateInfo->pSetLayouts,
		.pushConstantRangeCount = pCreateInfo->pushConstantRangeCount,
		.pPushConstantRanges = pCreateInfo->pPushConstantRanges,
	};
	_pipelineLayout = MVKPipelineLayout::Create(getDevice(), &plCreateInfo);
}

void MVKShader::initFromSPIRV(const VkShaderCreateInfoEXT* pCreateInfo, const void* pCode, size_t codeSize, const char* pName) {
	VkShaderModuleCreateInfo smCreateInfo = {
		.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
		.pNext = nullptr,
		.flags = 0,
		.codeSize = codeSize,
		.pCode = (const uint32_t*)pCode,
	};
	_shaderModule = new MVKShaderModule(getDevice(), &smCreateInfo);
	setConfigurationResult(_shaderModule->getConfigurationResult());
	_entryPointName = pName ? pName : "main";

	// Only Apple GPUs can read a color attachment back in the fragment function, which the
	// rewrite depends on.
	if (_stage == VK_SHADER_STAGE_FRAGMENT_BIT && getPhysicalDevice()->getMTLDeviceCapabilities().isAppleGPU) {
		_canBlendInShader = mvk::canBlendFragmentOutputsInShader(_shaderModule->getSPIRV(), &_canDeriveCoverage);
	}

	// Loading attributes in the shader reaches the vertex buffers through their GPU addresses,
	// available on the same terms as VK_KHR_buffer_device_address, and replaces work that
	// Apple GPUs, having no vertex fetch hardware, do in the vertex function anyway.
	if (_stage == VK_SHADER_STAGE_VERTEX_BIT && getPhysicalDevice()->getMTLDeviceCapabilities().isAppleGPU &&
		getMetalFeatures().argumentBuffersTier >= MTLArgumentBuffersTier2 && mvkSupportsBufferDeviceAddress()) {
		_canPullVertices = mvk::canPullVerticesInShader(_shaderModule->getSPIRV());
	}

	reflectForPipelineKeys();
}

void MVKShader::initFromBinary(const VkShaderCreateInfoEXT* pCreateInfo) {
	// A binary that is too short to hold a header cannot be one of ours, and is rejected the
	// same way as one built by a different driver or an incompatible version of this one.
	if (pCreateInfo->codeSize < sizeof(MVKShaderBinaryHeader)) {
		setConfigurationResult(VK_INCOMPATIBLE_SHADER_BINARY_EXT);
		return;
	}

	MVKShaderBinaryHeader hdr;
	memcpy(&hdr, pCreateInfo->pCode, sizeof(hdr));

	size_t bodySize = (size_t)hdr.codeSize + hdr.nameSize + hdr.archiveSize;
	if (hdr.magic != kMVKShaderBinaryMagic ||
		hdr.version != kMVKShaderBinaryVersion ||
		memcmp(hdr.uuid, getDeviceProperties().pipelineCacheUUID, VK_UUID_SIZE) != 0 ||
		hdr.nameSize == 0 ||
		hdr.stage != (uint32_t)pCreateInfo->stage ||
		bodySize != pCreateInfo->codeSize - sizeof(MVKShaderBinaryHeader)) {

		setConfigurationResult(VK_INCOMPATIBLE_SHADER_BINARY_EXT);
		return;
	}

	const uint8_t* pBody = (const uint8_t*)pCreateInfo->pCode + sizeof(MVKShaderBinaryHeader);
	const char* pName = (const char*)(pBody + hdr.codeSize);

	// The entry point name is stored NUL-terminated, so a binary whose final byte is not a
	// NUL has been truncated or tampered with, and must not be read past.
	if (pName[hdr.nameSize - 1] != '\0') {
		setConfigurationResult(VK_INCOMPATIBLE_SHADER_BINARY_EXT);
		return;
	}

	// The pipelines this shader took part in when the binary was written. Metal decides for itself
	// whether they are usable here, and silently builds the ones that are not.
	if (hdr.archiveSize) {
		_binaryArchive.setBytes((const uint8_t*)pName + hdr.nameSize, hdr.archiveSize);

		// Opening the archive costs about as much as building a pipeline, so it happens here,
		// while the application is still creating its shaders, rather than on the draw that first
		// needs it. The shader is held for the duration, as the application may destroy it.
		retain();
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			_binaryArchive.getMTLBinaryArchiveForLookup();
			release();
		});
	}

	initFromSPIRV(pCreateInfo, pBody, hdr.codeSize, pName);
}

// Vulkan guarantees that repeated calls return the same binary for the lifetime of the shader, so
// the archive is captured the first time one is asked for and that capture is reused afterwards,
// even though later draws may have added more pipelines to it.
const std::vector<char>& MVKShader::getBinaryArchiveBytes() {
	lock_guard<mutex> lock(_binaryArchiveSnapshotLock);
	if ( !_hasBinaryArchiveSnapshot ) {
		_binaryArchiveSnapshot = _binaryArchive.getBytes();
		_hasBinaryArchiveSnapshot = true;
	}
	return _binaryArchiveSnapshot;
}

VkResult MVKShader::getBinaryData(size_t* pDataSize, void* pData) {
	const std::vector<uint32_t>& spv = _shaderModule->getSPIRV();
	const std::vector<char>& archive = getBinaryArchiveBytes();
	uint32_t codeSize = (uint32_t)(spv.size() * sizeof(uint32_t));
	uint32_t nameSize = (uint32_t)(_entryPointName.size() + 1);
	uint32_t archiveSize = (uint32_t)archive.size();
	size_t binSize = sizeof(MVKShaderBinaryHeader) + codeSize + nameSize + archiveSize;

	if ( !pData ) {
		*pDataSize = binSize;
		return VK_SUCCESS;
	}

	// Vulkan requires that a buffer too small to hold the binary is left untouched, and that
	// the size reported back is the size actually written, which in that case is none of it.
	if (*pDataSize < binSize) {
		*pDataSize = 0;
		return VK_INCOMPLETE;
	}

	MVKShaderBinaryHeader hdr = {};
	hdr.magic = kMVKShaderBinaryMagic;
	hdr.version = kMVKShaderBinaryVersion;
	memcpy(hdr.uuid, getDeviceProperties().pipelineCacheUUID, VK_UUID_SIZE);
	hdr.stage = _stage;
	hdr.codeSize = codeSize;
	hdr.nameSize = nameSize;
	hdr.archiveSize = archiveSize;

	uint8_t* pDst = (uint8_t*)pData;
	memcpy(pDst, &hdr, sizeof(hdr));
	memcpy(pDst + sizeof(hdr), spv.data(), codeSize);
	memcpy(pDst + sizeof(hdr) + codeSize, _entryPointName.c_str(), nameSize);
	if (archiveSize) { memcpy(pDst + sizeof(hdr) + codeSize + nameSize, archive.data(), archiveSize); }

	*pDataSize = binSize;
	return VK_SUCCESS;
}

// Everything a pipeline key needs to know about the SPIR-V, answered once here rather than on
// the draw that first asks. None of it can change for a given shader, and a draw that has to ask
// is on the path this extension exists to keep clear.
void MVKShader::reflectForPipelineKeys() {
	const std::vector<uint32_t>& spirv = _shaderModule->getSPIRV();
	std::string errorLog;

	// Only a shader that writes a position the rewrite can reach takes the depth clip convention
	// out of its pipeline key; anything else keeps it, and has the convention baked in as before.
	spv::ExecutionModel model;
	switch (_stage) {
		case VK_SHADER_STAGE_VERTEX_BIT:					model = spv::ExecutionModelVertex;					break;
		case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:	model = spv::ExecutionModelTessellationEvaluation;	break;
		case VK_SHADER_STAGE_GEOMETRY_BIT:					model = spv::ExecutionModelGeometry;				break;
		default:											return;		// Nothing below applies to a later stage.
	}
	_canMapDepthClip = mvk::canMapDepthClipInShader(spirv, errorLog);

	// Metal needs a pipeline that routes a layer index to declare which topology class it
	// rasterizes, so a shader that writes the built-in keeps that axis in its key. Where
	// reflection fails the shader cannot be shown not to write it, and the class stays.
	MVKSmallVector<mvk::SPIRVShaderInterfaceVariable, 32> outputs;
	if (mvk::getShaderOutputs(spirv, model, _entryPointName, outputs, errorLog)) {
		for (auto& output : outputs) {
			if (output.builtin == spv::BuiltInLayer) { _writesLayer = true; break; }
		}
	} else {
		_writesLayer = true;
	}

	// An attribute the shader never reads cannot change what is drawn, but it does change the
	// vertex descriptor a pipeline is built with, so knowing which locations are read lets draws
	// that differ only in the rest of the layout share a pipeline. The reflection expands a matrix
	// or an array across the run of locations it occupies, so each arrives here in its own right.
	if (_stage != VK_SHADER_STAGE_VERTEX_BIT) { return; }
	MVKSmallVector<mvk::SPIRVShaderInterfaceVariable, 32> inputs;
	if ( !mvk::getShaderInputs(spirv, spv::ExecutionModelVertex, _entryPointName, inputs, errorLog) ) { return; }

	_consumedVertexLocationsValid = true;
	for (auto& input : inputs) {
		if (input.builtin != spv::BuiltInMax) { continue; }		// Builtins occupy no location.
		if ( !input.isUsed ) { continue; }

		// A 64-bit type wider than two components covers two locations, which the reflection
		// above does not expand, so such a shader keeps its whole layout.
		bool is64Bit = (input.baseType == SPIRV_CROSS_NAMESPACE::SPIRType::Double ||
						input.baseType == SPIRV_CROSS_NAMESPACE::SPIRType::Int64 ||
						input.baseType == SPIRV_CROSS_NAMESPACE::SPIRType::UInt64);
		if (is64Bit || input.location >= 64) {
			_consumedVertexLocationsValid = false;
			return;
		}
		_consumedVertexLocations |= (1ull << input.location);
	}
}

MVKShader::MVKShader(MVKDevice* device, const VkShaderCreateInfoEXT* pCreateInfo) :
	MVKVulkanAPIDeviceObject(device), _binaryArchive(device) {
	_stage = pCreateInfo->stage;
	_nextStage = pCreateInfo->nextStage;
	_flags = pCreateInfo->flags;

	initSpecialization(pCreateInfo->pSpecializationInfo);
	initLayout(pCreateInfo);

	switch (pCreateInfo->codeType) {
		case VK_SHADER_CODE_TYPE_SPIRV_EXT:
			initFromSPIRV(pCreateInfo, pCreateInfo->pCode, pCreateInfo->codeSize, pCreateInfo->pName);
			break;
		case VK_SHADER_CODE_TYPE_BINARY_EXT:
			initFromBinary(pCreateInfo);
			break;
		default:
			setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateShadersEXT(): Unsupported shader code type %d.", pCreateInfo->codeType));
			break;
	}
}

MVKShader::~MVKShader() {
	if (_shaderModule) { _shaderModule->destroy(); }
	if (_pipelineLayout) { _pipelineLayout->destroy(); }
}


#pragma mark -
#pragma mark MVKShaderLibraryCompiler

id<MTLLibrary> MVKShaderLibraryCompiler::newMTLLibrary(NSString* mslSourceCode,
													   const SPIRVToMSLConversionResultInfo& shaderConversionResults,
													   const vector<pair<MSLSpecializationMacroInfo, MVKShaderMacroValue>>& specializationMacroDef) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		auto mtlDev = getMTLDevice();
		@synchronized (mtlDev) {
			@autoreleasepool {
				auto mtlCompileOptions = getDevice()->getMTLCompileOptions(shaderConversionResults.entryPoint.fpFastMathFlags,
																		   shaderConversionResults.isPositionInvariant);
				if (!specializationMacroDef.empty()) {
					size_t macro_count = specializationMacroDef.size();
					NSString *macro_names[macro_count];
					NSNumber *macro_values[macro_count];
					for (uint32_t i = 0; i < specializationMacroDef.size(); i++) {
						macro_names[i] = @(specializationMacroDef[i].first.name.c_str());
						macro_values[i] = getMacroValue(specializationMacroDef[i].first, specializationMacroDef[i].second);
					}
					mtlCompileOptions.preprocessorMacros = [NSDictionary dictionaryWithObjects: macro_values
																					   forKeys: macro_names
																						 count: macro_count];
				}
				logCompilation(mtlCompileOptions);

				[mtlDev newLibraryWithSource: mslSourceCode
									options: mtlCompileOptions
						completionHandler: ^(id<MTLLibrary> mtlLib, NSError* error) {
							bool isLate = compileComplete(mtlLib, error);
							if (isLate) { destroy(); }
						}];
			}
		}
	});

	return [_mtlLibrary retain];
}

NSNumber *MVKShaderLibraryCompiler::getMacroValue(const MSLSpecializationMacroInfo& info,
												  const MVKShaderMacroValue& value) {
	NSNumber *result;

	if (info.isFloat) {
		if (value.size == sizeof(double)) {
			result = [NSNumber numberWithDouble: value.value.f64];
		} else {
			result = [NSNumber numberWithFloat: value.value.f32];
		}
	} else {
		if (info.isSigned) {
			switch (value.size) {
				case 1:
					result = [NSNumber numberWithChar: value.value.si8];
					break;
				case 2:
					result = [NSNumber numberWithShort: value.value.si16];
					break;
				case 4:
					result = [NSNumber numberWithInt: value.value.si32];
					break;
				case 8:
					result = [NSNumber numberWithLongLong: value.value.si64];
					break;
				default:
					result = [NSNumber numberWithInt: value.value.si32];
					break;
			}
		} else {
			switch (value.size) {
				case 1:
					result = [NSNumber numberWithUnsignedChar: value.value.ui8];
					break;
				case 2:
					result = [NSNumber numberWithUnsignedShort: value.value.ui16];
					break;
				case 4:
					result = [NSNumber numberWithUnsignedInt: value.value.ui32];
					break;
				case 8:
					result = [NSNumber numberWithUnsignedLongLong: value.value.ui64];
					break;
				default:
					result = [NSNumber numberWithUnsignedInt: value.value.ui32];
					break;
			}
		}
	}

	return result;
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

void MVKShaderLibraryCompiler::logCompilation(MTLCompileOptions* mtlCompOpt) {
	if ( !getMVKConfig().debugMode ) { return; }

#if MVK_XCODE_16
	if ([mtlCompOpt respondsToSelector: @selector(mathMode)]) {
		const char* mathModeName = "Unknown";
		switch (mtlCompOpt.mathMode) {
			case MTLMathModeFast:
				mathModeName = "Fast";
				break;
			case MTLMathModeRelaxed:
				mathModeName = "Relaxed";
				break;
			case MTLMathModeSafe:
				mathModeName = "Safe";
				break;
			default:
				break;
		}
		const char* mathFPFName = "Unknown";
		switch (mtlCompOpt.mathFloatingPointFunctions) {
			case MTLMathFloatingPointFunctionsFast:
				mathFPFName = "Fast";
				break;
			case MTLMathFloatingPointFunctionsPrecise:
				mathFPFName = "Precise";
				break;
			default:
				break;
		}
		MVKLogInfo("Compiling Metal shader with MathMode %s, MathFloatingPointFunctions %s, and PreserveInvariance %sabled.",
				   mathModeName, mathFPFName, mtlCompOpt.preserveInvariance ? "en" : "dis");
	} else
#endif
	{
		MVKLogInfo("Compiling Metal shader with FastMath %sabled and PreserveInvariance %sabled.",
				   mtlCompOpt.fastMathEnabled ? "en" : "dis", mtlCompOpt.preserveInvariance ? "en" : "dis");
	}
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

