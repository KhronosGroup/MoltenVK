/*
 * MVKEnvironment.h
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


#pragma once

#include "MVKCommonEnvironment.h"


/** Macro to determine the Vulkan version supported by MoltenVK. */
#define MVK_VULKAN_API_VERSION		VK_MAKE_VERSION(VK_VERSION_MAJOR(VK_API_VERSION_1_0),	\
													VK_VERSION_MINOR(VK_API_VERSION_1_0),	\
													VK_HEADER_VERSION)

/** 
 * Macro to adjust the specified Vulkan version to a value that can be compared for conformance 
 * against another Vulkan version. This macro strips the patch value from the specified Vulkan
 * version and replaces it with zero. A Vulkan version is comformant with another version if it
 * has the same or higher major and minor values, regardless of the patch value of each version.
 * In particular, by definition, a Vulkan version is conformant with another Vulkan version that
 * has a larger patch number, as long as it has a same or greater major and minor value.
 */
#define MVK_VULKAN_API_VERSION_CONFORM(api_ver)		VK_MAKE_VERSION(VK_VERSION_MAJOR(api_ver),	\
                                                                    VK_VERSION_MINOR(api_ver),	\
                                                                    0)

/** Flip the vertex coordinate in shaders. Enabled by default. */
#ifndef MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y
#   define MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y    1
#endif

/** Process command queue submissions on the same thread on which the submission call was made. Disabled by default. */
#ifndef MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS
#   define MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS    0
#endif

/** Fill a Metal command buffers when each Vulkan command buffer is filled. */
#ifndef MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS
#   define MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS    0
#endif

/**
 * The maximum number of Metal command buffers that can be concurrently
 * active per Vulkan queue. Default is Metal's default value of 64.
 */
#ifndef MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_POOL
#   define MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_POOL    64
#endif

/** Support more than 8192 occlusion queries per buffer. Enabled by default. */
#ifndef MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS
#   define MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS    1
#endif

/** Present surfaces using a command buffer. Enabled by default. */
#ifndef MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER
#   define MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER    1
#endif

/** Use nearest sampling to magnify swapchain images. Enabled by default. */
#ifndef MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST
#   define MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST    1
#endif

/** Display the MoltenVK logo watermark. Disabled by default. */
#ifndef MVK_CONFIG_DISPLAY_WATERMARK
#   define MVK_CONFIG_DISPLAY_WATERMARK    0
#endif

/** The maximum amount of time, in nanoseconds, to wait for a Metal library. Default is infinite. */
#ifndef MVK_CONFIG_METAL_COMPILE_TIMEOUT
#   define MVK_CONFIG_METAL_COMPILE_TIMEOUT    INT64_MAX
#endif

/**
 * IOSurfaces are supported on macOS, and on iOS starting with iOS 11.
 *
 * To enable IOSurface support on iOS in MoltenVK, set the iOS Deployment Target
 * (IPHONEOS_DEPLOYMENT_TARGET) build setting to 11.0 or greater when building
 * MoltenVK, and any app that uses IOSurfaces.
 */
#if MVK_MACOS
#	define MVK_SUPPORT_IOSURFACE_BOOL    1
#	define MVK_SUPPORT_INPUT_PRIMITIVE_TOPOLOGY_BOOL	1
#endif

#if MVK_IOS
#	define MVK_SUPPORT_IOSURFACE_BOOL	(__IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_11_0)
#	if !defined(__IPHONE_12_0)
#		define __IPHONE_12_0 120000
# 	endif
#	define MVK_SUPPORT_INPUT_PRIMITIVE_TOPOLOGY_BOOL	(__IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0)
#endif
