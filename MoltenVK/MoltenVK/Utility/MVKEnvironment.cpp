/*
 * MVKEnvironment.cpp
 *
 * Copyright (c) 2015-2023 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKEnvironment.h"
#include "MVKOSExtensions.h"


static bool _mvkConfigInitialized = false;
static void mvkInitConfigFromEnvVars() {
	_mvkConfigInitialized = true;

	MVKConfiguration evCfg;
	std::string evGPUCapFileStrObj;

	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.debugMode,                              MVK_DEBUG);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.shaderConversionFlipVertexY,            MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.synchronousQueueSubmits,                MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.prefillMetalCommandBuffers,             MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.maxActiveMetalCommandBuffersPerQueue,   MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.supportLargeQueryPools,                 MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.presentWithCommandBuffer,               MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.swapchainMinMagFilterUseNearest,        MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST);	// Deprecated legacy env var
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.swapchainMinMagFilterUseNearest,        MVK_CONFIG_SWAPCHAIN_MIN_MAG_FILTER_USE_NEAREST);
	MVK_SET_FROM_ENV_OR_BUILD_INT64 (evCfg.metalCompileTimeout,                    MVK_CONFIG_METAL_COMPILE_TIMEOUT);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.performanceTracking,                    MVK_CONFIG_PERFORMANCE_TRACKING);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.performanceLoggingFrameCount,           MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.activityPerformanceLoggingStyle,        MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.displayWatermark,                       MVK_CONFIG_DISPLAY_WATERMARK);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.specializedQueueFamilies,               MVK_CONFIG_SPECIALIZED_QUEUE_FAMILIES);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.switchSystemGPU,                        MVK_CONFIG_SWITCH_SYSTEM_GPU);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.fullImageViewSwizzle,                   MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.defaultGPUCaptureScopeQueueFamilyIndex, MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_FAMILY_INDEX);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.defaultGPUCaptureScopeQueueIndex,       MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_INDEX);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.fastMathEnabled,                        MVK_CONFIG_FAST_MATH_ENABLED);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.logLevel,                               MVK_CONFIG_LOG_LEVEL);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.traceVulkanCalls,                       MVK_CONFIG_TRACE_VULKAN_CALLS);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.forceLowPowerGPU,                       MVK_CONFIG_FORCE_LOW_POWER_GPU);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.semaphoreUseMTLFence,                   MVK_ALLOW_METAL_FENCES);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.semaphoreSupportStyle,                  MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.autoGPUCaptureScope,                    MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE);
	MVK_SET_FROM_ENV_OR_BUILD_STRING(evCfg.autoGPUCaptureOutputFilepath,           MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE, evGPUCapFileStrObj);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.texture1DAs2D,                          MVK_CONFIG_TEXTURE_1D_AS_2D);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.preallocateDescriptors,                 MVK_CONFIG_PREALLOCATE_DESCRIPTORS);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.useCommandPooling,                      MVK_CONFIG_USE_COMMAND_POOLING);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.useMTLHeap,                             MVK_CONFIG_USE_MTLHEAP);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.apiVersionToAdvertise,                  MVK_CONFIG_API_VERSION_TO_ADVERTISE);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.advertiseExtensions,                    MVK_CONFIG_ADVERTISE_EXTENSIONS);
	MVK_SET_FROM_ENV_OR_BUILD_BOOL  (evCfg.resumeLostDevice,                       MVK_CONFIG_RESUME_LOST_DEVICE);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.useMetalArgumentBuffers,                MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS);
	MVK_SET_FROM_ENV_OR_BUILD_INT32 (evCfg.shaderSourceCompressionAlgorithm,       MVK_CONFIG_SHADER_COMPRESSION_ALGORITHM);

	// Deprected legacy VkSemaphore MVK_ALLOW_METAL_FENCES and MVK_ALLOW_METAL_EVENTS config.
	// Legacy MVK_ALLOW_METAL_EVENTS is covered by MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE,
	// but for backwards compatibility, if legacy MVK_ALLOW_METAL_EVENTS is explicitly
	// disabled, disable semaphoreUseMTLEvent (aliased as semaphoreSupportStyle value
	// MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_SINGLE_QUEUE), and let mvkSetConfig()
	// further process legacy behavior of MVK_ALLOW_METAL_FENCES.
	bool sem4UseMTLEvent;
	MVK_SET_FROM_ENV_OR_BUILD_BOOL(sem4UseMTLEvent, MVK_ALLOW_METAL_EVENTS);
	if ( !sem4UseMTLEvent ) {
		evCfg.semaphoreUseMTLEvent = (MVKVkSemaphoreSupportStyle)false;		// Disabled. Also semaphoreSupportStyle MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_SINGLE_QUEUE.
	}

	// Deprecated legacy env var MVK_CONFIG_PERFORMANCE_LOGGING_INLINE config. If legacy
	// MVK_CONFIG_PERFORMANCE_LOGGING_INLINE env var was used, and activityPerformanceLoggingStyle
	// was not already set by MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE, set
	// activityPerformanceLoggingStyle to MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_IMMEDIATE.
	bool logPerfInline;
	MVK_SET_FROM_ENV_OR_BUILD_BOOL(logPerfInline, MVK_CONFIG_PERFORMANCE_LOGGING_INLINE);
	if (logPerfInline && evCfg.activityPerformanceLoggingStyle == MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_FRAME_COUNT) {
		evCfg.activityPerformanceLoggingStyle = MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_IMMEDIATE;
	}


	mvkSetConfig(evCfg);
}

static MVKConfiguration _mvkConfig;
static std::string _autoGPUCaptureOutputFile;

// Returns the MoltenVK config, lazily initializing it if necessary.
// We initialize lazily instead of in a library constructor function to
// ensure the NSProcessInfo environment is available when called upon.
const MVKConfiguration& mvkConfig() {
	if ( !_mvkConfigInitialized ) {
		mvkInitConfigFromEnvVars();
	}
	return _mvkConfig;
}

// Sets config content, and updates any content that needs baking, including copying the contents
// of strings from the incoming MVKConfiguration member to a corresponding std::string, and then
// repointing the MVKConfiguration member to the contents of the std::string.
void mvkSetConfig(const MVKConfiguration& mvkConfig) {
	_mvkConfig = mvkConfig;

	// Ensure the API version is supported, and add the VK_HEADER_VERSION.
	_mvkConfig.apiVersionToAdvertise = std::min(_mvkConfig.apiVersionToAdvertise, MVK_VULKAN_API_VERSION);
	_mvkConfig.apiVersionToAdvertise = VK_MAKE_VERSION(VK_VERSION_MAJOR(_mvkConfig.apiVersionToAdvertise),
													   VK_VERSION_MINOR(_mvkConfig.apiVersionToAdvertise),
													   VK_HEADER_VERSION);

	// Deprecated legacy support for specific case where both legacy semaphoreUseMTLEvent
	// (now aliased to semaphoreSupportStyle) and legacy semaphoreUseMTLFence are explicitly
	// disabled by the app. In this case the app had been using CPU emulation, so use
	// MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_CALLBACK.
	if ( !_mvkConfig.semaphoreUseMTLEvent && !_mvkConfig.semaphoreUseMTLFence ) {
		_mvkConfig.semaphoreSupportStyle = MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_CALLBACK;
	}

	// Set capture file path string
	if (_mvkConfig.autoGPUCaptureOutputFilepath) {
		_autoGPUCaptureOutputFile = _mvkConfig.autoGPUCaptureOutputFilepath;
	}
	_mvkConfig.autoGPUCaptureOutputFilepath = (char*)_autoGPUCaptureOutputFile.c_str();
}
