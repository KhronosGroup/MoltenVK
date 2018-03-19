/*
 * MVKShaderModule.mm
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

#include "MVKShaderModule.h"
#include "MVKFoundation.h"
#include "vk_mvk_moltenvk.h"
#include <string>

using namespace std;


const MVKMTLFunction MVKMTLFunctionNull = { nil, MTLSizeMake(1, 1, 1) };

#pragma mark -
#pragma mark MVKShaderLibrary

static uint32_t getOffsetForConstantId(const VkSpecializationInfo* pSpecInfo, uint32_t constantId)
{
    for (uint32_t specIdx = 0; specIdx < pSpecInfo->mapEntryCount; specIdx++) {
        const VkSpecializationMapEntry* pMapEntry = &pSpecInfo->pMapEntries[specIdx];
        if (pMapEntry->constantID == constantId) { return pMapEntry->offset; }
    }

    return -1;
}

MVKMTLFunction MVKShaderLibrary::getMTLFunction(const VkSpecializationInfo* pSpecializationInfo) {

    if ( !_mtlLibrary ) { return MVKMTLFunctionNull; }

    // Ensure the function name is compatible with Metal (Metal does not allow main()
    // as a function name), and retrieve the unspecialized Metal function with that name.
    NSString* mtlFuncName = @(_entryPoint.mtlFunctionName.c_str());

    uint64_t startTime = _device->getPerformanceTimestamp();
    id<MTLFunction> mtlFunc = [[_mtlLibrary newFunctionWithName: mtlFuncName] autorelease];
    _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.functionRetrieval, startTime);

    if (mtlFunc) {
        // If the Metal device supports shader specialization, and the Metal function expects to be
        // specialized, populate Metal function constant values from the Vulkan specialization info,
        // and compiled a specialized Metal function, otherwise simply use the unspecialized Metal function.
        if (_device->_pMetalFeatures->shaderSpecialization) {
            NSArray<MTLFunctionConstant*>* mtlFCs = mtlFunc.functionConstantsDictionary.allValues;
            if (mtlFCs.count) {
                uint64_t startTimeSpec = _device->getPerformanceTimestamp();

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
                NSError* err = nil;
                mtlFunc = [[_mtlLibrary newFunctionWithName: mtlFuncName constantValues: mtlFCVals error: &err] autorelease];
                handleCompilationError(err, "Shader function specialization");
                _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.functionSpecialization, startTimeSpec);
            }
        }
    } else {
        mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "Shader module does not contain an entry point named '%s'.", mtlFuncName.UTF8String);
    }

    if (pSpecializationInfo) {
        // Get the specialization constant values for the work group size
        if (_entryPoint.workgroupSizeId.constant != 0) {
            uint32_t widthOffset = getOffsetForConstantId(pSpecializationInfo, _entryPoint.workgroupSizeId.width);
            if (widthOffset != -1) {
                _entryPoint.workgroupSize.width = *reinterpret_cast<uint32_t*>((uint8_t*)pSpecializationInfo->pData + widthOffset);
            }

            uint32_t heightOffset = getOffsetForConstantId(pSpecializationInfo, _entryPoint.workgroupSizeId.height);
            if (heightOffset != -1) {
                _entryPoint.workgroupSize.height = *reinterpret_cast<uint32_t*>((uint8_t*)pSpecializationInfo->pData + heightOffset);
            }

            uint32_t depthOffset = getOffsetForConstantId(pSpecializationInfo, _entryPoint.workgroupSizeId.depth);
            if (depthOffset != -1) {
                _entryPoint.workgroupSize.depth = *reinterpret_cast<uint32_t*>((uint8_t*)pSpecializationInfo->pData + depthOffset);
            }
        }
    }

    return { mtlFunc, MTLSizeMake(_entryPoint.workgroupSize.width, _entryPoint.workgroupSize.height, _entryPoint.workgroupSize.depth) };
}

// Returns the MTLFunctionConstant with the specified ID from the specified array of function constants.
// The specified ID is the index value contained within the function constant.
MTLFunctionConstant* MVKShaderLibrary::getFunctionConstant(NSArray<MTLFunctionConstant*>* mtlFCs, NSUInteger mtlFCID) {
    for (MTLFunctionConstant* mfc in mtlFCs) { if (mfc.index == mtlFCID) { return mfc; } }
    return nil;
}

MVKShaderLibrary::MVKShaderLibrary(MVKDevice* device, SPIRVToMSLConverter& mslConverter) : MVKBaseDeviceObject(device) {
    uint64_t startTime = _device->getPerformanceTimestamp();
    @autoreleasepool {
        MTLCompileOptions* options = [[MTLCompileOptions new] autorelease]; // TODO: what compile options apply?
        NSError* err = nil;
        _mtlLibrary = [getMTLDevice() newLibraryWithSource: @(mslConverter.getMSL().data())
                                                   options: options
                                                     error: &err];        // retained
        handleCompilationError(err, "Shader module compilation");
    }
    _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.mslCompile, startTime);

	_entryPoint = mslConverter.getEntryPoint();
}

MVKShaderLibrary::MVKShaderLibrary(MVKDevice* device,
                                   const void* mslCompiledCodeData,
                                   size_t mslCompiledCodeLength) : MVKBaseDeviceObject(device) {
    uint64_t startTime = _device->getPerformanceTimestamp();
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
    _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.mslLoad, startTime);
}

// If err object is nil, the compilation succeeded without any warnings.
// If err object exists, and the MTLLibrary was created, the compilation succeeded, but with warnings.
// If err object exists, and the MTLLibrary was not created, the compilation failed.
void MVKShaderLibrary::handleCompilationError(NSError* err, const char* opDesc) {
    if ( !err ) return;

    if (_mtlLibrary) {
        MVKLogInfo("%s succeeded with warnings (code %li):\n\n%s", opDesc, (long)err.code,
                   err.localizedDescription.UTF8String);
    } else {
        setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED,
                                                      "%s failed (code %li):\n\n%s",
                                                      opDesc, (long)err.code,
                                                      err.localizedDescription.UTF8String));
    }
}

MVKShaderLibrary::~MVKShaderLibrary() {
	[_mtlLibrary release];
}


#pragma mark -
#pragma mark MVKShaderModule

MVKMTLFunction MVKShaderModule::getMTLFunction(SPIRVToMSLConverterContext* pContext,
											   const VkSpecializationInfo* pSpecializationInfo) {
    lock_guard<mutex> lock(_accessLock);
    MVKShaderLibrary* mvkLib = getShaderLibrary(pContext);
    return mvkLib ? mvkLib->getMTLFunction(pSpecializationInfo) : MVKMTLFunctionNull;
}

MVKShaderLibrary* MVKShaderModule::getShaderLibrary(SPIRVToMSLConverterContext* pContext) {
	if (_defaultLibrary) { return _defaultLibrary; }

	MVKShaderLibrary* shLib = findShaderLibrary(pContext);
	if ( !shLib ) { shLib = addShaderLibrary(pContext); }
//	else { MVKLogDebug("Shader Module %p reusing library.", this); }
	return shLib;
}

// Finds and returns a shader library matching the specified context, or returns nullptr if it doesn't exist.
// If a match is found, the usage of the specified context is aligned with the context of the matching library.
MVKShaderLibrary* MVKShaderModule::findShaderLibrary(SPIRVToMSLConverterContext* pContext) {
    for (auto& slPair : _shaderLibraries) {
        if (slPair.first.matches(*pContext)) {
            pContext->alignUsageWith(slPair.first);
            return slPair.second;
        }
    }
    return NULL;
}

/** Adds and returns a new shader library configured from the specified context. */
MVKShaderLibrary* MVKShaderModule::addShaderLibrary(SPIRVToMSLConverterContext* pContext) {

    MVKShaderLibrary* shLib = nullptr;
    bool shouldLogCode = _device->_mvkConfig.debugMode;

    uint64_t startTime = _device->getPerformanceTimestamp();
    bool wasConverted = _converter.convert(*pContext, shouldLogCode, shouldLogCode, shouldLogCode);
    _device->addShaderCompilationEventPerformance(_device->_shaderCompilationPerformance.spirvToMSL, startTime);

    if (wasConverted) {
        if (shouldLogCode) { MVKLogInfo("%s", _converter.getResultLog().data()); }
        shLib = new MVKShaderLibrary(_device, _converter);
        _shaderLibraries.push_back(pair<SPIRVToMSLConverterContext, MVKShaderLibrary*>(*pContext, shLib));
//        MVKLogDebug("Shader Module %p compiled %d libraries.", this, _shaderLibraries.size());
    } else {
        mvkNotifyErrorWithText(VK_ERROR_FORMAT_NOT_SUPPORTED, "Unable to convert SPIR-V to MSL:\n%s", _converter.getResultLog().data());
    }
    return shLib;
}


#pragma mark Construction

MVKShaderModule::MVKShaderModule(MVKDevice* device,
								 const VkShaderModuleCreateInfo* pCreateInfo) : MVKBaseDeviceObject(device) {
    _defaultLibrary = nullptr;

    // Ensure something is there.
    if ( (pCreateInfo->pCode != VK_NULL_HANDLE) && (pCreateInfo->codeSize >= 4) ) {

        // Retrieve the magic number to determine what type of shader code has been loaded.
        uint32_t magicNum = *pCreateInfo->pCode;
        switch (magicNum) {
            case kMVKMagicNumberSPIRVCode: {                        // SPIR-V code
                size_t spvCount = (pCreateInfo->codeSize + 3) >> 2; // Round up if byte length not exactly on uint32_t boundary
                _converter.setSPIRV(pCreateInfo->pCode, spvCount);
                break;
            }
            case kMVKMagicNumberMSLSourceCode: {                    // MSL source code
                uintptr_t pMSLCode = uintptr_t(pCreateInfo->pCode) + sizeof(MVKMSLSPIRVHeader);
				_converter.setMSL((char*)pMSLCode, nullptr);
                _defaultLibrary = new MVKShaderLibrary(_device, _converter);
                break;
            }
            case kMVKMagicNumberMSLCompiledCode: {                  // MSL compiled binary code
                uintptr_t pMSLCode = uintptr_t(pCreateInfo->pCode) + sizeof(MVKMSLSPIRVHeader);
                _defaultLibrary = new MVKShaderLibrary(_device, (void*)(pMSLCode), (pCreateInfo->codeSize - sizeof(MVKMSLSPIRVHeader)));
                break;
            }
            default:
                setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_FORMAT_NOT_SUPPORTED, "SPIR-V contains invalid magic number %x.", magicNum));
                break;
        }
    } else {
        setConfigurationResult(mvkNotifyErrorWithText(VK_INCOMPLETE, "Shader module contains no SPIR-V code."));
    }
}

MVKShaderModule::~MVKShaderModule() {
	if (_defaultLibrary) { delete _defaultLibrary; }
	for (auto& slPair : _shaderLibraries) { delete slPair.second; }
}

