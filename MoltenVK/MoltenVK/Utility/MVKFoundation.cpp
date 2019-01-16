/*
 * MVKFoundation.cpp
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

#include "MVKFoundation.h"
#include "MVKLogging.h"


#define CASE_STRINGIFY(V)  case V: return #V

const char* mvkVkResultName(VkResult vkResult) {
	switch (vkResult) {

			CASE_STRINGIFY(VK_SUCCESS);
			CASE_STRINGIFY(VK_NOT_READY);
			CASE_STRINGIFY(VK_TIMEOUT);
			CASE_STRINGIFY(VK_EVENT_SET);
			CASE_STRINGIFY(VK_EVENT_RESET);
			CASE_STRINGIFY(VK_INCOMPLETE);

			CASE_STRINGIFY(VK_ERROR_OUT_OF_HOST_MEMORY);
			CASE_STRINGIFY(VK_ERROR_OUT_OF_DEVICE_MEMORY);
			CASE_STRINGIFY(VK_ERROR_INITIALIZATION_FAILED);
			CASE_STRINGIFY(VK_ERROR_DEVICE_LOST);
			CASE_STRINGIFY(VK_ERROR_MEMORY_MAP_FAILED);
			CASE_STRINGIFY(VK_ERROR_LAYER_NOT_PRESENT);
			CASE_STRINGIFY(VK_ERROR_EXTENSION_NOT_PRESENT);
			CASE_STRINGIFY(VK_ERROR_FEATURE_NOT_PRESENT);
			CASE_STRINGIFY(VK_ERROR_INCOMPATIBLE_DRIVER);
			CASE_STRINGIFY(VK_ERROR_TOO_MANY_OBJECTS);
			CASE_STRINGIFY(VK_ERROR_FORMAT_NOT_SUPPORTED);
			CASE_STRINGIFY(VK_ERROR_FRAGMENTED_POOL);

			CASE_STRINGIFY(VK_ERROR_SURFACE_LOST_KHR);
			CASE_STRINGIFY(VK_ERROR_NATIVE_WINDOW_IN_USE_KHR);
			CASE_STRINGIFY(VK_SUBOPTIMAL_KHR);
			CASE_STRINGIFY(VK_ERROR_OUT_OF_DATE_KHR);
			CASE_STRINGIFY(VK_ERROR_INCOMPATIBLE_DISPLAY_KHR);

			CASE_STRINGIFY(VK_ERROR_VALIDATION_FAILED_EXT);
			CASE_STRINGIFY(VK_ERROR_INVALID_SHADER_NV);

			CASE_STRINGIFY(VK_ERROR_OUT_OF_POOL_MEMORY);
			CASE_STRINGIFY(VK_ERROR_INVALID_EXTERNAL_HANDLE);

		default: return "VK_UNKNOWN_VK_Result";
	}
}

const char* mvkVkComponentSwizzleName(VkComponentSwizzle swizzle) {
	switch (swizzle) {
			CASE_STRINGIFY(VK_COMPONENT_SWIZZLE_IDENTITY);
			CASE_STRINGIFY(VK_COMPONENT_SWIZZLE_ZERO);
			CASE_STRINGIFY(VK_COMPONENT_SWIZZLE_ONE);
			CASE_STRINGIFY(VK_COMPONENT_SWIZZLE_R);
			CASE_STRINGIFY(VK_COMPONENT_SWIZZLE_G);
			CASE_STRINGIFY(VK_COMPONENT_SWIZZLE_B);
			CASE_STRINGIFY(VK_COMPONENT_SWIZZLE_A);

		default: return "VK_UNKNOWN_VKComponentSwizzle";
	}
}

VkResult mvkNotifyErrorWithText(VkResult vkErr, const char* errFmt, ...) {
	va_list args;
	va_start(args, errFmt);

	// Prepend the error code to the format string
	const char* vkRsltName = mvkVkResultName(vkErr);
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


