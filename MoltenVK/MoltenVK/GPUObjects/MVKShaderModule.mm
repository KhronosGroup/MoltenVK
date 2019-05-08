/*
 * MVKShaderModule.mm
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

#include "MVKShaderModule.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "MVKLogging.h"
#include "vk_mvk_moltenvk.h"
#include <string>

using namespace std;


const MVKMTLFunction MVKMTLFunctionNull = { nil, MTLSizeMake(1, 1, 1) };

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

MVKMTLFunction MVKShaderLibrary::getMTLFunction(const VkSpecializationInfo* pSpecializationInfo) {

    if ( !_mtlLibrary ) { return MVKMTLFunctionNull; }

    // Ensure the function name is compatible with Metal (Metal does not allow main()
    // as a function name), and retrieve the unspecialized Metal function with that name.
    NSString* mtlFuncName = @(_entryPoint.mtlFunctionName.c_str());


	MVKDevice* mvkDev = _owner->getDevice();
    uint64_t startTime = mvkDev->getPerformanceTimestamp();
    id<MTLFunction> mtlFunc = [[_mtlLibrary newFunctionWithName: mtlFuncName] autorelease];
    mvkDev->addActivityPerformance(mvkDev->_performanceStatistics.shaderCompilation.functionRetrieval, startTime);

    if (mtlFunc) {
        // If the Metal device supports shader specialization, and the Metal function expects to be
        // specialized, populate Metal function constant values from the Vulkan specialization info,
        // and compiled a specialized Metal function, otherwise simply use the unspecialized Metal function.
        if (mvkDev->_pMetalFeatures->shaderSpecialization) {
            NSArray<MTLFunctionConstant*>* mtlFCs = mtlFunc.functionConstantsDictionary.allValues;
            if (mtlFCs.count) {
                // The Metal shader contains function constants and expects to be specialized
                // Populate the Metal function constant values from the Vulkan specialization info.
                MTLFunctionConstantValues* mtlFCVals = [[MTLFunctionConstantValues new] autorelease];
                if (pSpecializationInfo) {
                    // Iterate through the provided Vulkan specialization entries, and populate the
                    // Metal function constant value that matches the Vulkan specialization constantID.
                    for (uint32_t specIdx = 0; specIdx < pSpecializationInfo->mapEntryCount; specIdx++) {
                        const VkSpecializationMapEntry* pMapEntry = &pSpecializationInfo->pMapEntries[specIdx];
                        NSUInteger mtlFCIndex = pMapEntry->constantID;
                        MTLFunctionConstant* mtlFC = getFunctionConstant(mtlFCs, mtlFCIndex);
                        if (mtlFC) {
                            [mtlFCVals setConstantValue: &(((char*)pSpecializationInfo->pData)[pMapEntry->offset])
                                                   type: mtlFC.type
                                                atIndex: mtlFCIndex];
                        }
                    }
                }

                // Compile the specialized Metal function, and use it instead of the unspecialized Metal function.
				MVKFunctionSpecializer* fs = new MVKFunctionSpecializer(_owner);
				mtlFunc = [fs->newMTLFunction(_mtlLibrary, mtlFuncName, mtlFCVals) autorelease];
				fs->destroy();
            }
        }
    } else {
        reportError(VK_ERROR_INITIALIZATION_FAILED, "Shader module does not contain an entry point named '%s'.", mtlFuncName.UTF8String);
    }

	return { mtlFunc, MTLSizeMake(getWorkgroupDimensionSize(_entryPoint.workgroupSize.width, pSpecializationInfo),
								  getWorkgroupDimensionSize(_entryPoint.workgroupSize.height, pSpecializationInfo),
								  getWorkgroupDimensionSize(_entryPoint.workgroupSize.depth, pSpecializationInfo)) };

}

// Returns the MTLFunctionConstant with the specified ID from the specified array of function constants.
// The specified ID is the index value contained within the function constant.
MTLFunctionConstant* MVKShaderLibrary::getFunctionConstant(NSArray<MTLFunctionConstant*>* mtlFCs, NSUInteger mtlFCID) {
    for (MTLFunctionConstant* mfc in mtlFCs) { if (mfc.index == mtlFCID) { return mfc; } }
    return nil;
}

MVKShaderLibrary::MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner, const string& mslSourceCode, const SPIRVEntryPoint& entryPoint) : _owner(owner) {
	MVKShaderLibraryCompiler* slc = new MVKShaderLibraryCompiler(_owner);
	_mtlLibrary = slc->newMTLLibrary(@(mslSourceCode.c_str()));	// retained
	slc->destroy();

	_entryPoint = entryPoint;
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

MVKShaderLibrary::MVKShaderLibrary(MVKShaderLibrary& other) : _owner(other._owner) {
	_mtlLibrary = [other._mtlLibrary retain];
	_entryPoint = other._entryPoint;
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
		_owner->setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED,
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

MVKShaderLibrary* MVKShaderLibraryCache::getShaderLibrary(SPIRVToMSLConverterContext* pContext,
														  MVKShaderModule* shaderModule,
														  bool* pWasAdded) {
	bool wasAdded = false;
	MVKShaderLibrary* shLib = findShaderLibrary(pContext);
	if ( !shLib ) {
		if (shaderModule->convert(pContext)) {
			shLib = addShaderLibrary(pContext, shaderModule->getMSL(), shaderModule->getEntryPoint());
			wasAdded = true;
		}
	}

	if (pWasAdded) { *pWasAdded = wasAdded; }

	return shLib;
}

// Finds and returns a shader library matching the specified context, or returns nullptr if it doesn't exist.
// If a match is found, the specified context is aligned with the context of the matching library.
MVKShaderLibrary* MVKShaderLibraryCache::findShaderLibrary(SPIRVToMSLConverterContext* pContext) {
	for (auto& slPair : _shaderLibraries) {
		if (slPair.first.matches(*pContext)) {
			pContext->alignWith(slPair.first);
			return slPair.second;
		}
	}
	return nullptr;
}

// Adds and returns a new shader library configured from the specified context.
MVKShaderLibrary* MVKShaderLibraryCache::addShaderLibrary(SPIRVToMSLConverterContext* pContext,
														  const string& mslSourceCode,
														  const SPIRVEntryPoint& entryPoint) {
	MVKShaderLibrary* shLib = new MVKShaderLibrary(_owner, mslSourceCode, entryPoint);
	_shaderLibraries.emplace_back(*pContext, shLib);
	return shLib;
}

// Merge another shader library cache with this one. Handle null input.
void MVKShaderLibraryCache::merge(MVKShaderLibraryCache* other) {
	if ( !other ) { return; }
	for (auto& otherPair : other->_shaderLibraries) {
		if ( !findShaderLibrary(&otherPair.first) ) {
			_shaderLibraries.emplace_back(otherPair.first, new MVKShaderLibrary(*otherPair.second));
		}
	}
}

MVKShaderLibraryCache::~MVKShaderLibraryCache() {
	for (auto& slPair : _shaderLibraries) { slPair.second->destroy(); }
}


#pragma mark -
#pragma mark MVKShaderModule

MVKMTLFunction MVKShaderModule::getMTLFunction(SPIRVToMSLConverterContext* pContext,
											   const VkSpecializationInfo* pSpecializationInfo,
											   MVKPipelineCache* pipelineCache) {
	lock_guard<mutex> lock(_accessLock);
	
	MVKShaderLibrary* mvkLib = _defaultLibrary;
	if ( !mvkLib ) {
		uint64_t startTime = _device->getPerformanceTimestamp();
		if (pipelineCache) {
			mvkLib = pipelineCache->getShaderLibrary(pContext, this);
		} else {
			mvkLib = _shaderLibraryCache.getShaderLibrary(pContext, this);
		}
		_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.shaderLibraryFromCache, startTime);
	} else {
		pContext->markAllAttributesAndResourcesUsed();
	}

	return mvkLib ? mvkLib->getMTLFunction(pSpecializationInfo) : MVKMTLFunctionNull;
}

bool MVKShaderModule::convert(SPIRVToMSLConverterContext* pContext) {
	bool shouldLogCode = _device->_pMVKConfig->debugMode;

	uint64_t startTime = _device->getPerformanceTimestamp();
	bool wasConverted = _converter.convert(*pContext, shouldLogCode, shouldLogCode, shouldLogCode);
	_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.spirvToMSL, startTime);

	if (wasConverted) {
		if (shouldLogCode) { MVKLogInfo("%s", _converter.getResultLog().data()); }
	} else {
		reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "Unable to convert SPIR-V to MSL:\n%s", _converter.getResultLog().data());
	}
	return wasConverted;
}


#pragma mark Construction

MVKShaderModule::MVKShaderModule(MVKDevice* device,
								 const VkShaderModuleCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device), _shaderLibraryCache(this) {

	_defaultLibrary = nullptr;


	size_t codeSize = pCreateInfo->codeSize;

    // Ensure something is there.
    if ( (pCreateInfo->pCode == VK_NULL_HANDLE) || (codeSize < 4) ) {
		setConfigurationResult(reportError(VK_INCOMPLETE, "Shader module contains no SPIR-V code."));
		return;
	}

	size_t codeHash = 0;

	// Retrieve the magic number to determine what type of shader code has been loaded.
	uint32_t magicNum = *pCreateInfo->pCode;
	switch (magicNum) {
		case kMVKMagicNumberSPIRVCode: {                        // SPIR-V code
			size_t spvCount = (pCreateInfo->codeSize + 3) >> 2; // Round up if byte length not exactly on uint32_t boundary

			uint64_t startTime = _device->getPerformanceTimestamp();
			codeHash = mvkHash(pCreateInfo->pCode, spvCount);
			_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

			_converter.setSPIRV(pCreateInfo->pCode, spvCount);

			break;
		}
		case kMVKMagicNumberMSLSourceCode: {                    // MSL source code
			size_t hdrSize = sizeof(MVKMSLSPIRVHeader);
			char* pMSLCode = (char*)(uintptr_t(pCreateInfo->pCode) + hdrSize);
			size_t mslCodeLen = pCreateInfo->codeSize - hdrSize;

			uint64_t startTime = _device->getPerformanceTimestamp();
			codeHash = mvkHash(&magicNum);
			codeHash = mvkHash(pMSLCode, mslCodeLen, codeHash);
			_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

			_converter.setMSL(pMSLCode, nullptr);
			_defaultLibrary = new MVKShaderLibrary(this, _converter.getMSL().c_str(), _converter.getEntryPoint());

			break;
		}
		case kMVKMagicNumberMSLCompiledCode: {                  // MSL compiled binary code
			size_t hdrSize = sizeof(MVKMSLSPIRVHeader);
			char* pMSLCode = (char*)(uintptr_t(pCreateInfo->pCode) + hdrSize);
			size_t mslCodeLen = pCreateInfo->codeSize - hdrSize;

			uint64_t startTime = _device->getPerformanceTimestamp();
			codeHash = mvkHash(&magicNum);
			codeHash = mvkHash(pMSLCode, mslCodeLen, codeHash);
			_device->addActivityPerformance(_device->_performanceStatistics.shaderCompilation.hashShaderCode, startTime);

			_defaultLibrary = new MVKShaderLibrary(this, (void*)(pMSLCode), mslCodeLen);

			break;
		}
		default:
			setConfigurationResult(reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "SPIR-V contains invalid magic number %x.", magicNum));
			break;
	}

	_key = MVKShaderModuleKey(codeSize, codeHash);
}

MVKShaderModule::~MVKShaderModule() {
	if (_defaultLibrary) { _defaultLibrary->destroy(); }
}


#pragma mark -
#pragma mark MVKShaderLibraryCompiler

id<MTLLibrary> MVKShaderLibraryCompiler::newMTLLibrary(NSString* mslSourceCode) {
	unique_lock<mutex> lock(_completionLock);

	compile(lock, ^{
		[_owner->getMTLDevice() newLibraryWithSource: mslSourceCode
											 options: _owner->getDevice()->getMTLCompileOptions()
								   completionHandler: ^(id<MTLLibrary> mtlLib, NSError* error) {
									   bool isLate = compileComplete(mtlLib, error);
									   if (isLate) { destroy(); }
								   }];
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

