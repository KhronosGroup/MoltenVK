/*
 * MVKFoundation.cpp
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKOSExtensions.h"


#define CASE_STRINGIFY(V)  case V: return #V

const char* mvkVkCommandName(MVKCommandUse cmdUse) {
	switch (cmdUse) {
		case kMVKCommandUseBeginCommandBuffer:           return "vkBeginCommandBuffer (prefilled VkCommandBuffer)";
		case kMVKCommandUseQueueSubmit:                  return "vkQueueSubmit";
		case kMVKCommandUseAcquireNextImage:             return "vkAcquireNextImageKHR";
		case kMVKCommandUseQueuePresent:                 return "vkQueuePresentKHR";
		case kMVKCommandUseQueueWaitIdle:                return "vkQueueWaitIdle";
		case kMVKCommandUseDeviceWaitIdle:               return "vkDeviceWaitIdle";
		case kMVKCommandUseInvalidateMappedMemoryRanges: return "vkInvalidateMappedMemoryRanges";
		case kMVKCommandUseBeginRendering:               return "vkCmdBeginRendering";
		case kMVKCommandUseBeginRenderPass:              return "vkCmdBeginRenderPass";
		case kMVKCommandUseNextSubpass:                  return "vkCmdNextSubpass";
		case kMVKCommandUseRestartSubpass:               return "Metal renderpass restart";
		case kMVKCommandUsePipelineBarrier:              return "vkCmdPipelineBarrier";
		case kMVKCommandUseBlitImage:                    return "vkCmdBlitImage";
		case kMVKCommandUseCopyImage:                    return "vkCmdCopyImage";
		case kMVKCommandUseResolveImage:                 return "vkCmdResolveImage (resolve stage)";
		case kMVKCommandUseResolveExpandImage:           return "vkCmdResolveImage (expand stage)";
		case kMVKCommandUseResolveCopyImage:             return "vkCmdResolveImage (copy stage)";
		case kMVKCommandUseCopyImageToMemory:            return "vkCopyImageToMemory host sync";
		case kMVKCommandUseCopyBuffer:                   return "vkCmdCopyBuffer";
		case kMVKCommandUseCopyBufferToImage:            return "vkCmdCopyBufferToImage";
		case kMVKCommandUseCopyImageToBuffer:            return "vkCmdCopyImageToBuffer";
		case kMVKCommandUseFillBuffer:                   return "vkCmdFillBuffer";
		case kMVKCommandUseUpdateBuffer:                 return "vkCmdUpdateBuffer";
		case kMVKCommandUseClearAttachments:             return "vkCmdClearAttachments";
		case kMVKCommandUseClearColorImage:              return "vkCmdClearColorImage";
		case kMVKCommandUseClearDepthStencilImage:       return "vkCmdClearDepthStencilImage";
		case kMVKCommandUseResetQueryPool:               return "vkCmdResetQueryPool";
		case kMVKCommandUseDispatch:                     return "vkCmdDispatch";
		case kMVKCommandUseTessellationVertexTessCtl:    return "vkCmdDraw (vertex and tess control stages)";
		case kMVKCommandUseDrawIndirectConvertBuffers:   return "vkCmdDrawIndirect (convert indirect buffers)";
		case kMVKCommandUseCopyQueryPoolResults:         return "vkCmdCopyQueryPoolResults";
		case kMVKCommandUseAccumOcclusionQuery:          return "Post-render-pass occlusion query accumulation";
		case kMVKCommandConvertUint8Indices:             return "Convert Uint8 indices to Uint16";
		case kMVKCommandUseRecordGPUCounterSample:       return "Record GPU Counter Sample";
		default:                                         return "Unknown Vulkan command";
	}
}

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

		CASE_STRINGIFY(VK_ERROR_UNKNOWN);
		CASE_STRINGIFY(VK_ERROR_OUT_OF_POOL_MEMORY);
		CASE_STRINGIFY(VK_ERROR_INVALID_EXTERNAL_HANDLE);
		CASE_STRINGIFY(VK_ERROR_FRAGMENTATION);
		CASE_STRINGIFY(VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS);
		CASE_STRINGIFY(VK_PIPELINE_COMPILE_REQUIRED);

		CASE_STRINGIFY(VK_ERROR_SURFACE_LOST_KHR);
		CASE_STRINGIFY(VK_ERROR_NATIVE_WINDOW_IN_USE_KHR);
		CASE_STRINGIFY(VK_SUBOPTIMAL_KHR);
		CASE_STRINGIFY(VK_ERROR_OUT_OF_DATE_KHR);
		CASE_STRINGIFY(VK_ERROR_INCOMPATIBLE_DISPLAY_KHR);

		CASE_STRINGIFY(VK_ERROR_VALIDATION_FAILED_EXT);
		CASE_STRINGIFY(VK_ERROR_INVALID_SHADER_NV);
		CASE_STRINGIFY(VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR);

		CASE_STRINGIFY(VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR);
		CASE_STRINGIFY(VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR);
		CASE_STRINGIFY(VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR);
		CASE_STRINGIFY(VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR);
		CASE_STRINGIFY(VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR);

		CASE_STRINGIFY(VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT);
		CASE_STRINGIFY(VK_ERROR_NOT_PERMITTED_KHR);
		CASE_STRINGIFY(VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT);
		CASE_STRINGIFY(VK_THREAD_IDLE_KHR);
		CASE_STRINGIFY(VK_THREAD_DONE_KHR);
		CASE_STRINGIFY(VK_OPERATION_DEFERRED_KHR);
		CASE_STRINGIFY(VK_OPERATION_NOT_DEFERRED_KHR);
		CASE_STRINGIFY(VK_ERROR_COMPRESSION_EXHAUSTED_EXT);

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

bool mvkSupportsBufferDeviceAddress() { return mvkOSVersionIsAtLeast(13.0, 16.0, 1.0); }


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


