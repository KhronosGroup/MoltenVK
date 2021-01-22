/*
 * SPIRVConversion.mm
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

#include "SPIRVConversion.h"
#include "SPIRVToMSLConverter.h"
#include "MVKCommonEnvironment.h"

#include <Foundation/Foundation.h>

using namespace mvk;


MVK_PUBLIC_SYMBOL bool mvkConvertSPIRVToMSL(uint32_t* spvCode,
                                            size_t spvLength,
                                            char** pMSL,
                                            char** pResultLog,
                                            bool shouldLogSPIRV,
                                            bool shouldLogMSL) {
    SPIRVToMSLConversionConfiguration spvCtx;
    SPIRVToMSLConverter spvConverter;
    spvConverter.setSPIRV(spvCode, spvLength);
    bool wasConverted = spvConverter.convert(spvCtx, shouldLogSPIRV, shouldLogMSL);

    if (pMSL) {
        auto& msl = spvConverter.getMSL();
        *pMSL = (char*)malloc(msl.size() + 1);
        strcpy(*pMSL, msl.data());
    }

    if (pResultLog) {
        auto log = spvConverter.getResultLog();
        *pResultLog = (char*)malloc(log.size() + 1);
        strcpy(*pResultLog, log.data());
    }

    return wasConverted;
}

MVK_PUBLIC_SYMBOL bool mvkConvertSPIRVFileToMSL(const char* spvFilepath,
                                                char** pMSL,
                                                char** pResultLog,
                                                bool shouldLogSPIRV,
                                                bool shouldLogMSL) {
    NSString* filePath = @(spvFilepath);
    if( !filePath.absolutePath )  {
        filePath =[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: filePath];
    }
    NSError* err = nil;
    NSData* spv = [NSData dataWithContentsOfFile: filePath options: 0 error: &err];
    if (err) {
        if (pResultLog) {
			NSString* errMsg = [NSString stringWithFormat: @"Unable to convert SPIR-V in file %@ to MSL (Error code %li):\n%@",
                                filePath, (long)err.code, err.localizedDescription];
            *pResultLog = (char*)malloc(errMsg.length + 1);
            strcpy(*pResultLog, errMsg.UTF8String);
        }

        if (pMSL) { *pMSL = NULL; }
        return false;
    }

    return mvkConvertSPIRVToMSL((uint32_t*)spv.bytes, spv.length, pMSL, pResultLog, shouldLogSPIRV, shouldLogMSL);
}


