/*
 * MVKFoundation.cpp
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

#include "MVKFoundation.h"
#include "MVKLogging.h"

#define CASE_RESULT(R)  case R: return strcpy(name, #R);

char* mvkResultName(VkResult vkResult, char* name) {
	switch (vkResult) {
            CASE_RESULT(VK_SUCCESS)
            CASE_RESULT(VK_NOT_READY)
            CASE_RESULT(VK_TIMEOUT)
            CASE_RESULT(VK_EVENT_SET)
            CASE_RESULT(VK_EVENT_RESET)
            CASE_RESULT(VK_INCOMPLETE)

            CASE_RESULT(VK_ERROR_OUT_OF_HOST_MEMORY)
            CASE_RESULT(VK_ERROR_OUT_OF_DEVICE_MEMORY)
            CASE_RESULT(VK_ERROR_INITIALIZATION_FAILED)
            CASE_RESULT(VK_ERROR_DEVICE_LOST)
            CASE_RESULT(VK_ERROR_MEMORY_MAP_FAILED)
            CASE_RESULT(VK_ERROR_LAYER_NOT_PRESENT)
            CASE_RESULT(VK_ERROR_EXTENSION_NOT_PRESENT)
            CASE_RESULT(VK_ERROR_FEATURE_NOT_PRESENT)
            CASE_RESULT(VK_ERROR_INCOMPATIBLE_DRIVER)
            CASE_RESULT(VK_ERROR_TOO_MANY_OBJECTS)
            CASE_RESULT(VK_ERROR_FORMAT_NOT_SUPPORTED)
            CASE_RESULT(VK_ERROR_FRAGMENTED_POOL)

            CASE_RESULT(VK_ERROR_SURFACE_LOST_KHR)
            CASE_RESULT(VK_ERROR_NATIVE_WINDOW_IN_USE_KHR)
            CASE_RESULT(VK_SUBOPTIMAL_KHR)
            CASE_RESULT(VK_ERROR_OUT_OF_DATE_KHR)
            CASE_RESULT(VK_ERROR_INCOMPATIBLE_DISPLAY_KHR)

            CASE_RESULT(VK_ERROR_VALIDATION_FAILED_EXT)
            CASE_RESULT(VK_ERROR_INVALID_SHADER_NV)

            CASE_RESULT(VK_ERROR_OUT_OF_POOL_MEMORY)
            CASE_RESULT(VK_ERROR_INVALID_EXTERNAL_HANDLE)

		default:
			sprintf(name, "UNKNOWN_VkResult(%d)", vkResult);
			return name;
	}
}

VkResult mvkNotifyErrorWithText(VkResult vkErr, const char* errFmt, ...) {
	va_list args;
	va_start(args, errFmt);

	char vkRsltName[MVKResultNameMaxLen];
	mvkResultName(vkErr, vkRsltName);

	// Prepend the error code to the format string
	char fmtStr[strlen(vkRsltName) + strlen(errFmt) + 4];
	sprintf(fmtStr, "%s: %s", vkRsltName, errFmt);

	// Log the error
	MVKLogImplV(true, !(MVK_DEBUG), ASL_LEVEL_ERR, "***MoltenVK ERROR***", fmtStr, args);

	va_end(args);

	return vkErr;
}


#pragma mark -
#pragma mark Alignment functions

void mvkFlipVertically(void* rowMajorData, uint32_t rowCount, size_t bytesPerRow) {
	if ( !rowMajorData ) return;		// If no data, nothing to flip!

	uint8_t tmpRow[bytesPerRow];
	uint32_t lastRowIdx = rowCount - 1;
	uint32_t halfRowCnt = rowCount / 2;
	for (uintptr_t rowIdx = 0; rowIdx < halfRowCnt; rowIdx++) {
		uint8_t* lowerRow = (uint8_t*)((uintptr_t)rowMajorData + (bytesPerRow * rowIdx));
		uint8_t* upperRow = (uint8_t*)((uintptr_t)rowMajorData + (bytesPerRow * (lastRowIdx - rowIdx)));
		memcpy(tmpRow, upperRow, bytesPerRow);
		memcpy(upperRow, lowerRow, bytesPerRow);
		memcpy(lowerRow, tmpRow, bytesPerRow);
	}
}


