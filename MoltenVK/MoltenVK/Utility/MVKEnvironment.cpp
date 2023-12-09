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
#include "MVKFoundation.h"


// Return the expected size of MVKConfiguration, based on contents of MVKConfigMembers.def.
static constexpr uint32_t getExpectedMVKConfigurationSize() {
#define MVK_CONFIG_MEMBER(member, mbrType, name)         cfgSize += sizeof(mbrType);
	uint32_t cfgSize = 0;
#include "MVKConfigMembers.def"
	return cfgSize;
}

static bool _mvkConfigInitialized = false;
static void mvkInitConfigFromEnvVars() {
	static_assert(getExpectedMVKConfigurationSize() == sizeof(MVKConfiguration), "MVKConfigMembers.def does not match the members of MVKConfiguration.");

	_mvkConfigInitialized = true;

	MVKConfiguration evCfg;
	std::string evGPUCapFileStrObj;

#define STR(name) #name

#define MVK_CONFIG_MEMBER(member, mbrType, name) \
	evCfg.member = (mbrType)mvkGetEnvVarNumber(STR(MVK_CONFIG_##name), MVK_CONFIG_##name);

#define MVK_CONFIG_MEMBER_STRING(member, mbrType, name) \
	evCfg.member = mvkGetEnvVarString(STR(MVK_CONFIG_##name), evGPUCapFileStrObj, MVK_CONFIG_##name);

#include "MVKConfigMembers.def"

	// At this point, debugMode has been set by env var MVK_CONFIG_DEBUG.
	// MVK_CONFIG_DEBUG replaced the deprecataed MVK_DEBUG env var, so for 
	// legacy use, if the MVK_DEBUG env var is explicitly set, override debugMode.
	double noEV = -3.1415;		// An unlikely env var value.
	double cvMVKDebug = mvkGetEnvVarNumber("MVK_DEBUG", noEV);
	if (cvMVKDebug != noEV) { evCfg.debugMode = cvMVKDebug; }

	// Deprected legacy VkSemaphore MVK_ALLOW_METAL_FENCES and MVK_ALLOW_METAL_EVENTS config.
	// Legacy MVK_ALLOW_METAL_EVENTS is covered by MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE,
	// but for backwards compatibility, if legacy MVK_ALLOW_METAL_EVENTS is explicitly
	// disabled, disable semaphoreUseMTLEvent (aliased as semaphoreSupportStyle value
	// MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_SINGLE_QUEUE), and let mvkSetConfig()
	// further process legacy behavior of MVK_ALLOW_METAL_FENCES.
	if ( !mvkGetEnvVarNumber("MVK_CONFIG_ALLOW_METAL_EVENTS", 1.0) ) {
		evCfg.semaphoreUseMTLEvent = (MVKVkSemaphoreSupportStyle)false;		// Disabled. Also semaphoreSupportStyle MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_SINGLE_QUEUE.
	}

	// Deprecated legacy env var MVK_CONFIG_PERFORMANCE_LOGGING_INLINE config. If legacy
	// MVK_CONFIG_PERFORMANCE_LOGGING_INLINE env var was used, and activityPerformanceLoggingStyle
	// was not already set by MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE, set
	// activityPerformanceLoggingStyle to MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_IMMEDIATE.
	bool logPerfInline = mvkGetEnvVarNumber("MVK_CONFIG_PERFORMANCE_LOGGING_INLINE", 0.0);
	if (logPerfInline && evCfg.activityPerformanceLoggingStyle == MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_FRAME_COUNT) {
		evCfg.activityPerformanceLoggingStyle = MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_IMMEDIATE;
	}

	mvkSetConfig(evCfg);
}

static MVKConfiguration _mvkConfig;
static std::string _autoGPUCaptureOutputFilepath;

// Returns the MoltenVK config, lazily initializing it if necessary.
// We initialize lazily instead of in a library constructor function to
// ensure the NSProcessInfo environment is available when called upon.
const MVKConfiguration& mvkConfig() {
	if ( !_mvkConfigInitialized ) {
		mvkInitConfigFromEnvVars();
	}
	return _mvkConfig;
}

void mvkSetConfig(const MVKConfiguration& mvkConfig) {
	mvkSetConfig(_mvkConfig, mvkConfig, _autoGPUCaptureOutputFilepath);
}

// Sets destination config content from the source content, validates content, 
// and updates any content that needs baking, including copying the contents of
// strings from the incoming MVKConfiguration member to a corresponding std::string,
// and then repointing the MVKConfiguration member to the contents of the std::string.
void mvkSetConfig(MVKConfiguration& dstMVKConfig,
				  const MVKConfiguration& srcMVKConfig,
				  std::string& autoGPUCaptureOutputFilepath) {

	dstMVKConfig = srcMVKConfig;

	// Ensure the API version is supported, and add the VK_HEADER_VERSION.
	dstMVKConfig.apiVersionToAdvertise = std::min(dstMVKConfig.apiVersionToAdvertise, MVK_VULKAN_API_VERSION);
	dstMVKConfig.apiVersionToAdvertise = VK_MAKE_VERSION(VK_VERSION_MAJOR(dstMVKConfig.apiVersionToAdvertise),
														 VK_VERSION_MINOR(dstMVKConfig.apiVersionToAdvertise),
														 VK_HEADER_VERSION);

	// Deprecated legacy support for specific case where both legacy semaphoreUseMTLEvent
	// (now aliased to semaphoreSupportStyle) and legacy semaphoreUseMTLFence are explicitly
	// disabled by the app. In this case the app had been using CPU emulation, so use
	// MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_CALLBACK.
	if ( !dstMVKConfig.semaphoreUseMTLEvent && !dstMVKConfig.semaphoreUseMTLFence ) {
		dstMVKConfig.semaphoreSupportStyle = MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_CALLBACK;
	}

	// Set capture file path string
	if (dstMVKConfig.autoGPUCaptureOutputFilepath) {
		autoGPUCaptureOutputFilepath = dstMVKConfig.autoGPUCaptureOutputFilepath;
	}
	dstMVKConfig.autoGPUCaptureOutputFilepath = autoGPUCaptureOutputFilepath.c_str();

	// Clamp timestampPeriodLowPassAlpha between 0.0 and 1.0.
	dstMVKConfig.timestampPeriodLowPassAlpha = mvkClamp(dstMVKConfig.timestampPeriodLowPassAlpha, 0.0f, 1.0f);
}

