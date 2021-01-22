/*
 * GLSLConversion.mm
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

#include "GLSLConversion.h"
#include "GLSLToSPIRVConverter.h"
#include "MVKCommonEnvironment.h"

#include <Foundation/Foundation.h>

using namespace mvk;


MVK_PUBLIC_SYMBOL bool mvkConvertGLSLToSPIRV(const char* glslSource,
                                             MVKGLSLConversionShaderStage shaderStage,
                                             uint32_t** pSPIRVCode,
                                             size_t *pSPIRVLength,
                                             char** pResultLog,
                                             bool shouldLogGLSL,
                                             bool shouldLogSPIRV) {
    GLSLToSPIRVConverter glslConverter;
    glslConverter.setGLSL(glslSource);
    bool wasConverted = glslConverter.convert(shaderStage, shouldLogGLSL, shouldLogSPIRV);

    size_t spvLen = 0;
    if (pSPIRVCode) {
        uint32_t* spvCode = NULL;
        if (wasConverted) {
            auto spv = glslConverter.getSPIRV();
            spvLen = spv.size() * sizeof(uint32_t);
            spvCode = (uint32_t*)malloc(spvLen);
            memcpy(spvCode, spv.data(), spvLen);
        }
        *pSPIRVCode = spvCode;
    }
    if (pSPIRVLength) { *pSPIRVLength = spvLen; }

    if (pResultLog) {
        auto log = glslConverter.getResultLog();
        *pResultLog = (char*)malloc(log.size() + 1);
        strcpy(*pResultLog, log.data());
    }

    return wasConverted;
}

MVK_PUBLIC_SYMBOL bool mvkConvertGLSLFileToSPIRV(const char* glslFilepath,
                                                 MVKGLSLConversionShaderStage shaderStage,
                                                 uint32_t** pSPIRVCode,
                                                 size_t *pSPIRVLength,
                                                 char** pResultLog,
                                                 bool shouldLogGLSL,
                                                 bool shouldLogSPIRV) {
    NSString* filePath = @(glslFilepath);
    if( !filePath.absolutePath )  {
        filePath =[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: filePath];
    }
    NSError* err = nil;
    NSString* glslSource = [NSString stringWithContentsOfFile: filePath
                                                     encoding: NSUTF8StringEncoding
                                                        error: &err];
    if (err) {
        if (pResultLog) {
            NSString* errMsg = [NSString stringWithFormat: @"Unable to convert GLSL in file %@ to SPIR-V (Error code %li):\n%@",
                                filePath, (long)err.code, err.localizedDescription];
            *pResultLog = (char*)malloc(errMsg.length + 1);
            strcpy(*pResultLog, errMsg.UTF8String);
        }

        if (pSPIRVCode) { *pSPIRVCode = NULL; }
        if (pSPIRVLength) { *pSPIRVLength = 0; }
        return false;
    }

    return mvkConvertGLSLToSPIRV(glslSource.UTF8String, shaderStage, pSPIRVCode, pSPIRVLength, pResultLog, shouldLogGLSL, shouldLogSPIRV);
}

