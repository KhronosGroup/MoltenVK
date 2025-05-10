/*
 * MVKEnvironment.h
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


#pragma once

#include "MVKCommonEnvironment.h"
#include "mvk_vulkan.h"
#include "mvk_deprecated_api.h"
#include "MVKLogging.h"
#ifdef __cplusplus
#include <string>
#endif


// Expose MoltenVK Apple surface extension functionality
#ifdef VK_USE_PLATFORM_IOS_MVK
#	define vkCreate_PLATFORM_SurfaceMVK			vkCreateIOSSurfaceMVK
#	define Vk_PLATFORM_SurfaceCreateInfoMVK		VkIOSSurfaceCreateInfoMVK
#endif

#ifdef VK_USE_PLATFORM_MACOS_MVK
#	define vkCreate_PLATFORM_SurfaceMVK			vkCreateMacOSSurfaceMVK
#	define Vk_PLATFORM_SurfaceCreateInfoMVK		VkMacOSSurfaceCreateInfoMVK
#endif

/** Standard Vulkan variant. */
#define MVK_VULKAN_VARIANT						0

/** Macro to adjust the specified Vulkan to include the VK_HEADER_VERSION patch value. */
#define MVK_VULKAN_API_VERSION_HEADER(api_ver)	VK_MAKE_API_VERSION(MVK_VULKAN_VARIANT,  \
                                                                    VK_VERSION_MAJOR(api_ver),	\
                                                                    VK_VERSION_MINOR(api_ver),	\
                                                                    VK_HEADER_VERSION)

/** 
 * Macro to adjust the specified Vulkan version to a value that can be compared for conformance 
 * against another Vulkan version. This macro strips the patch value from the specified Vulkan
 * version and replaces it with zero. A Vulkan version is comformant with another version if it
 * has the same or higher major and minor values, regardless of the patch value of each version.
 * In particular, by definition, a Vulkan version is conformant with another Vulkan version that
 * has a larger patch number, as long as it has a same or greater major and minor value.
 */
#define MVK_VULKAN_API_VERSION_CONFORM(api_ver)	VK_MAKE_API_VERSION(MVK_VULKAN_VARIANT,  \
                                                                    VK_VERSION_MAJOR(api_ver),	\
                                                                    VK_VERSION_MINOR(api_ver),	\
                                                                    0)

/** Macro to determine the Vulkan version supported by MoltenVK. */
#define MVK_VULKAN_API_VERSION					MVK_VULKAN_API_VERSION_HEADER(VK_API_VERSION_1_3)

/**
 * IOSurfaces are supported on macOS, and on iOS starting with iOS 11.
 *
 * To enable IOSurface support on iOS in MoltenVK, set the iOS Deployment Target
 * (IPHONEOS_DEPLOYMENT_TARGET) build setting to 11.0 or greater when building
 * MoltenVK, and any app that uses IOSurfaces.
 */
#if MVK_MACOS
#	define MVK_SUPPORT_IOSURFACE_BOOL    1
#endif

#if MVK_IOS
#	define MVK_SUPPORT_IOSURFACE_BOOL	(__IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_11_0)
#endif

#if MVK_TVOS
#	define MVK_SUPPORT_IOSURFACE_BOOL (__TV_OS_VERSION_MIN_REQUIRED >= __TVOS_11_0)
#endif

#if MVK_VISIONOS
#    define MVK_SUPPORT_IOSURFACE_BOOL   1
#endif


#pragma mark -
#pragma mark MoltenVK Configuration

#ifdef __cplusplus

/** The number of members of MVKConfiguration that are strings. */
static constexpr uint32_t kMVKConfigurationStringCount = 2;

/** Global function to access MoltenVK configuration info. */
const MVKConfiguration& getGlobalMVKConfig();

/** Sets the MoltenVK global configuration content. */
void mvkSetGlobalConfig(const MVKConfiguration& srcMVKConfig);

/** 
 * Sets the content from the source config into the destination 
 * config, while using the string object to retain string content.
 */
void mvkSetConfig(MVKConfiguration& dstMVKConfig, const MVKConfiguration& srcMVKConfig, std::string* stringHolders);

#endif

/**
 * Enable debug mode.
 * By default, disabled for Release builds and enabled for Debug builds.
 */
#ifndef MVK_CONFIG_DEBUG
#	define MVK_CONFIG_DEBUG		MVK_DEBUG
#endif

/** Flip the vertex coordinate in shaders. Enabled by default. */
#ifndef MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y
#   define MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y    1
#endif

/**
 * Process command queue submissions on the same thread on which the submission call was made.
 * The default value actually depends on whether MTLEvents are supported, because if MTLEvents
 * are not supported, then synchronous queues should be turned off by default to ensure the
 * CPU emulation of VkEvent behaviour does not deadlock a queue submission, whereas if MTLEvents
 * are supported, we want sychronous queues for better, and more performant, behaviour.
 * The app can of course still override this default behaviour by setting the
 * MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS env var, or the config directly.
 */
#if MVK_MACOS
#   define MVK_CONFIG_MTLEVENT_MIN_OS  10.14
#endif
#if MVK_IOS_OR_TVOS
#   define MVK_CONFIG_MTLEVENT_MIN_OS  12.0
#endif
#if MVK_VISIONOS
#   define MVK_CONFIG_MTLEVENT_MIN_OS  1.0
#endif
#ifndef MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS
#   define MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS    mvkOSVersionIsAtLeast(MVK_CONFIG_MTLEVENT_MIN_OS)
#endif

/** Fill a Metal command buffer when each Vulkan command buffer is filled. */
#ifndef MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS
#   define MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS    MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_NO_PREFILL
#endif

/**
 * The maximum number of Metal command buffers that can be concurrently
 * active per Vulkan queue. Default is Metal's default value of 64.
 */
#ifndef MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE
#   define MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE    64
#endif

/** Support more than 8192 or 32768 occlusion queries per device. Enabled by default. */
#ifndef MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS
#   define MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS    1
#endif

/** Present surfaces using a command buffer. Enabled by default. */
#ifndef MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER
#   define MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER    1
#endif

/** Use nearest sampling to minify or magnify swapchain images. Enabled by default. Second macro name is deprecated legacy. */
#ifndef MVK_CONFIG_SWAPCHAIN_MIN_MAG_FILTER_USE_NEAREST
#   define MVK_CONFIG_SWAPCHAIN_MIN_MAG_FILTER_USE_NEAREST    1
#endif
#ifndef MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST
#   define MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST    MVK_CONFIG_SWAPCHAIN_MIN_MAG_FILTER_USE_NEAREST
#endif

/** The maximum amount of time, in nanoseconds, to wait for a Metal library. Default is infinite. */
#ifndef MVK_CONFIG_METAL_COMPILE_TIMEOUT
#   define MVK_CONFIG_METAL_COMPILE_TIMEOUT    INT64_MAX
#endif

/** Track performance. Disabled by default. */
#ifndef MVK_CONFIG_PERFORMANCE_TRACKING
#   define MVK_CONFIG_PERFORMANCE_TRACKING    0
#endif

/** Log performance once every this number of frames. Default is zero (never). */
#ifndef MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT
#   define MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT    0
#endif

/** Activity performance logging style. Default is to log after a configured number of frames. */
#	ifndef MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE
#   	define MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE    MVK_CONFIG_ACTIVITY_PERFORMANCE_LOGGING_STYLE_FRAME_COUNT
#	endif
#	ifndef MVK_CONFIG_PERFORMANCE_LOGGING_INLINE	// Deprecated
#   	define MVK_CONFIG_PERFORMANCE_LOGGING_INLINE    0
#	endif

/** Display the MoltenVK logo watermark. Disabled by default. */
#ifndef MVK_CONFIG_DISPLAY_WATERMARK
#   define MVK_CONFIG_DISPLAY_WATERMARK    0
#endif

/** Advertise specialized queue families. Disabled by default. */
#ifndef MVK_CONFIG_SPECIALIZED_QUEUE_FAMILIES
#   define MVK_CONFIG_SPECIALIZED_QUEUE_FAMILIES    0
#endif

/** If the Vulkan app selects a high-power GPU, force the system to use it. Enabled by default. */
#ifndef MVK_CONFIG_SWITCH_SYSTEM_GPU
#   define MVK_CONFIG_SWITCH_SYSTEM_GPU    1
#endif

/** Support full ImageView swizzles. Disabled by default. */
#ifndef MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE
#   define MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE    0
#endif

/** Set the fastMathEnabled Metal Compiler option. Set to always use fast math by default. */
#ifndef MVK_CONFIG_FAST_MATH_ENABLED
#   define MVK_CONFIG_FAST_MATH_ENABLED    MVK_CONFIG_FAST_MATH_ALWAYS
#endif

/** Set the logging level: */
#ifndef MVK_CONFIG_LOG_LEVEL
#   define MVK_CONFIG_LOG_LEVEL    MVK_CONFIG_LOG_LEVEL_INFO
#endif

/** Set the Vulkan call logging level. */
#ifndef MVK_CONFIG_TRACE_VULKAN_CALLS
#   define MVK_CONFIG_TRACE_VULKAN_CALLS    MVK_CONFIG_TRACE_VULKAN_CALLS_NONE
#endif

/**
 * The index of the queue family whose presentation submissions will
 * be used as the default GPU Capture Scope during debugging in Xcode.
 */
#ifndef MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_FAMILY_INDEX
#   define MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_FAMILY_INDEX    0
#endif

/**
 * The index of the queue, within the queue family identified by the
 * MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_FAMILY_INDEX setting, whose presentation
 * submissions will be used as the default GPU Capture Scope during debugging in Xcode.
 */
#ifndef MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_INDEX
#   define MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_INDEX    0
#endif

/**
 * The scope under which to automatically run a GPU capture within Xcode, without the
 * developer having to trigger it manually via the Xcode UI. This is useful when trying
 * to capture a one-shot trace, such as when running a Vulkan CTS test case.
 */
#ifndef MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE
#   define MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE    	MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_NONE
#endif

/**
 * The file to capture automatic GPU traces to, instead of capturing to Xcode. This is
 * useful when trying to capture a one-shot trace, but the program cannot be run under
 * Xcode's control. Tilde paths may be used to place the trace document in a user's home
 * directory. This functionality requires macOS 10.15 or iOS 13. If left blank, automatic
 * traces will be captured to Xcode.
 */
#ifndef MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE
#	define MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE	""
#endif

/** Force the use of a low-power GPU if it exists. Disabled by default. */
#ifndef MVK_CONFIG_FORCE_LOW_POWER_GPU
#   define MVK_CONFIG_FORCE_LOW_POWER_GPU    0
#endif

/**
 * Determines the style used to implement Vulkan semaphore (VkSemaphore) functionality in Metal.
 * By default, use Metal events, if availalble, on most platforms.
 */
#ifndef MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE
#   define MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE    MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE_METAL_EVENTS_WHERE_SAFE
#endif
#ifndef MVK_CONFIG_ALLOW_METAL_EVENTS
#   define MVK_CONFIG_ALLOW_METAL_EVENTS    1
#endif
#ifndef MVK_ALLOW_METAL_EVENTS				// Deprecated
#   define MVK_ALLOW_METAL_EVENTS    		MVK_CONFIG_ALLOW_METAL_EVENTS
#endif
#ifndef MVK_CONFIG_ALLOW_METAL_FENCES
#   define MVK_CONFIG_ALLOW_METAL_FENCES    1
#endif
#ifndef MVK_ALLOW_METAL_FENCES				// Deprecated
#   define MVK_ALLOW_METAL_FENCES    		MVK_CONFIG_ALLOW_METAL_FENCES
#endif

/** Substitute Metal 2D textures for Vulkan 1D images. Enabled by default. */
#ifndef MVK_CONFIG_TEXTURE_1D_AS_2D
#   define MVK_CONFIG_TEXTURE_1D_AS_2D    1
#endif

/** Obsolete, deprecated, and ignored. */
#ifndef MVK_CONFIG_PREALLOCATE_DESCRIPTORS
#   define MVK_CONFIG_PREALLOCATE_DESCRIPTORS    1
#endif

/** Use pooling for command resources in a VkCommandPool. Enabled by default. */
#ifndef MVK_CONFIG_USE_COMMAND_POOLING
#  	define MVK_CONFIG_USE_COMMAND_POOLING    1
#endif

/**
 * Use MTLHeap when allocating MTLBuffers and MTLTextures.
 * Enabled by default where safe to use MTLHeap on the platform.
 */
#ifndef MVK_CONFIG_USE_MTLHEAP
#  	define MVK_CONFIG_USE_MTLHEAP    MVK_CONFIG_USE_MTLHEAP_WHERE_SAFE
#endif

/** The Vulkan API version to advertise. Defaults to MVK_VULKAN_API_VERSION. */
#ifndef MVK_CONFIG_API_VERSION_TO_ADVERTISE
#  	define MVK_CONFIG_API_VERSION_TO_ADVERTISE    MVK_VULKAN_API_VERSION
#endif

/** Advertise supported extensions. Defaults to all. */
#ifndef MVK_CONFIG_ADVERTISE_EXTENSIONS
#  	define MVK_CONFIG_ADVERTISE_EXTENSIONS    MVK_CONFIG_ADVERTISE_EXTENSIONS_ALL
#endif

/** Resume MVKDevice VK_ERROR_DEVICE_LOST errors that do not cause MVKPhysicalDevice errors. Disabled by default. */
#ifndef MVK_CONFIG_RESUME_LOST_DEVICE
#   define MVK_CONFIG_RESUME_LOST_DEVICE    0
#endif

/** Support Metal argument buffers. Enabled by default. */
#ifndef MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS
#   define MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS    1
#endif

/** Compress MSL shader source code in a pipeline cache. Defaults to no compression. */
#ifndef MVK_CONFIG_SHADER_COMPRESSION_ALGORITHM
#  	define MVK_CONFIG_SHADER_COMPRESSION_ALGORITHM    MVK_CONFIG_COMPRESSION_ALGORITHM_NONE
#endif

/**
 * Maximize the concurrent executing compilation tasks.
 * This functionality requires macOS 13.3. Disabled by default.
 */
#ifndef MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION
#  	define MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION    0
#endif

/**
 * The alpha value of a lowpass filter tracking VkPhysicalDeviceLimits::timestampPeriod.
 * This can be set to a float between 0.0 and 1.0.
 */
#ifndef MVK_CONFIG_TIMESTAMP_PERIOD_LOWPASS_ALPHA
#  	define MVK_CONFIG_TIMESTAMP_PERIOD_LOWPASS_ALPHA    1.0
#endif

/**
 * Enable the use of Metal private interfaces, also known as "Service Provider Interfaces" (SPIs),
 * to support Vulkan features. Enabled by default if support is included.
 */
#ifndef MVK_CONFIG_USE_METAL_PRIVATE_API
#	define MVK_CONFIG_USE_METAL_PRIVATE_API MVK_USE_METAL_PRIVATE_API
#endif

/** If set, MVK will dump spirv input, translated msl, and pipelines into the given directory. */
#ifndef MVK_CONFIG_SHADER_DUMP_DIR
#   define MVK_CONFIG_SHADER_DUMP_DIR ""
#endif

/**
 * Enable logging estimated GLSL code during shader conversion.
 * Disabled by default.
 */
#ifndef MVK_CONFIG_SHADER_LOG_ESTIMATED_GLSL
#	define MVK_CONFIG_SHADER_LOG_ESTIMATED_GLSL		0
#endif

