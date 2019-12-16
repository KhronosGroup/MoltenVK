/*
 * vk_mvk_moltenvk.h
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


/** Vulkan extension VK_MVK_moltenvk. */

#ifndef __vk_mvk_moltenvk_h_
#define __vk_mvk_moltenvk_h_ 1

#ifdef __cplusplus
extern "C" {
#endif	//  __cplusplus
	
#include "mvk_vulkan.h"

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <IOSurface/IOSurfaceRef.h>
#else
typedef unsigned long MTLLanguageVersion;
#endif


/**
 * The version number of MoltenVK is a single integer value, derived from the Major, Minor,
 * and Patch version values, where each of the Major, Minor, and Patch components is allocated
 * two decimal digits, in the format MjMnPt. This creates a version number that is both human
 * readable and allows efficient computational comparisons to a single integer number.
 *
 * The following examples illustrate how the MoltenVK version number is built from its components:
 *   - 002000    (version 0.20.0)
 *   - 010000    (version 1.0.0)
 *   - 030104    (version 3.1.4)
 *   - 401215    (version 4.12.15)
 */
#define MVK_VERSION_MAJOR   1
#define MVK_VERSION_MINOR   0
#define MVK_VERSION_PATCH   39

#define MVK_MAKE_VERSION(major, minor, patch)    (((major) * 10000) + ((minor) * 100) + (patch))
#define MVK_VERSION     MVK_MAKE_VERSION(MVK_VERSION_MAJOR, MVK_VERSION_MINOR, MVK_VERSION_PATCH)

#define VK_MVK_MOLTENVK_SPEC_VERSION            23
#define VK_MVK_MOLTENVK_EXTENSION_NAME          "VK_MVK_moltenvk"

/**
 * MoltenVK configuration settings.
 *
 * To be active, some configuration settings must be set before a VkDevice is created.
 * See the description of the individual configuration structure members for more information.
 *
 * There are three mechanisms for setting the values of the MoltenVK configuration parameters:
 *   - Runtime API via the vkGetMoltenVKConfigurationMVK()/vkSetMoltenVKConfigurationMVK() functions.
 *   - Application runtime environment variables.
 *   - Build settings at MoltenVK build time.
 *
 * To change the MoltenVK configuration settings at runtime using a programmatic API,
 * use the vkGetMoltenVKConfigurationMVK() and vkSetMoltenVKConfigurationMVK() functions
 * to retrieve, modify, and set a copy of the MVKConfiguration structure.
 *
 * The initial value of each of the configuration settings can established at runtime
 * by a corresponding environment variable, or if the environment variable is not set,
 * by a corresponding build setting at the time MoltenVK is compiled. The environment
 * variable and build setting for each configuration parameter share the same name.
 *
 * For example, the initial value of the shaderConversionFlipVertexY configuration setting
 * is set by the MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y at runtime, or by the
 * MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y build setting when MoltenVK is compiled.
 *
 * This structure may be extended as new features are added to MoltenVK. If you are linking to
 * an implementation of MoltenVK that was compiled from a different VK_MVK_MOLTENVK_SPEC_VERSION
 * than your app was, the size of this structure in your app may be larger or smaller than the
 * struct in MoltenVK. See the description of the vkGetMoltenVKConfigurationMVK() and
 * vkSetMoltenVKConfigurationMVK() functions for information about how to handle this.
 *
 * TO SUPPORT DYNAMIC LINKING TO THIS STRUCTURE AS DESCRIBED ABOVE, THIS STRUCTURE SHOULD NOT
 * BE CHANGED EXCEPT TO ADD ADDITIONAL MEMBERS ON THE END. EXISTING MEMBERS, AND THEIR ORDER,
 * SHOULD NOT BE CHANGED.
 *
 * In addition to the configuration parmeters in this structure, there are several settings that
 * can be configured through runtime environment variables or MoltenVK compile-time build settings:
 *
 * 1. The MVK_CONFIG_LOG_LEVEL runtime environment variable or MoltenVK compile-time build setting
 *    controls the level of logging performned by MoltenVK using the following numeric values:
 *      0: No logging.
 *      1: Log errors only.
 *      2: Log errors and informational messages.
 *    If none of these is set, errors and informational messages are logged.
 *
 * 2. The MVK_CONFIG_TRACE_VULKAN_CALLS runtime environment variable or MoltenVK compile-time build
 *    setting causes MoltenVK to log the name of each Vulkan call made by the application. The logging
 *    format options can be controlled by setting the value of MVK_CONFIG_TRACE_VULKAN_CALLS as follows:
 *        0: No Vulkan call logging.
 *        1: Log the name of each Vulkan call when the call is entered.
 *        2: Log the name of each Vulkan call when the call is entered and exited. This effectively
 *           brackets any other logging activity within the scope of the Vulkan call.
 *        3: Same as option 2, plus logs the time spent inside the Vulkan function.
 *    If none of these is set, no Vulkan call logging will occur.
 *
 * 3. Setting the MVK_CONFIG_FORCE_LOW_POWER_GPU runtime environment variable or MoltenVK compile-time
 *    build setting to 1 will force MoltenVK to use a low-power GPU, if one is availble on the device.
 *    By default, this setting is disabled, allowing both low-power and high-power GPU's to be used.
 *
 * 4. Setting the MVK_ALLOW_METAL_FENCES or MVK_ALLOW_METAL_EVENTS runtime environment variable
 *    or MoltenVK compile-time build setting to 1 will cause MoltenVK to use MTLFence or MTLEvent,
 *    respectively, if it is available on the device, for VkSemaphore synchronization behaviour.
 *    If both variables are set, MVK_ALLOW_METAL_FENCES takes priority over MVK_ALLOW_METAL_EVENTS.
 *    If both are disabled, or if MTLFence or MTLEvent is not available on the device, MoltenVK
 *    will use CPU synchronization to control VkSemaphore synchronization behaviour.
 *    By default, MVK_ALLOW_METAL_FENCES is enabled and MVK_ALLOW_METAL_EVENTS is disabled,
 *    meaning MoltenVK will use MTLFences, if they are available, to control VkSemaphore
 *    synchronization behaviour, by default.
 *
 * 5. The MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE runtime environment variable or MoltenVK compile-time
 *    build setting controls whether Xcode should run an automatic GPU capture without the user
 *    having to trigger it manually via the Xcode user interface, and controls the scope under
 *    which that GPU capture will occur. This is useful when trying to capture a one-shot GPU
 *    trace, such as when running a Vulkan CTS test case. For the automatic GPU capture to occur,
 *    the Xcode scheme under which the app is run must have the Metal GPU capture option turned on.
 *    MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE should not be set to manually trigger a GPU capture via the
 *    Xcode user interface.
 *      0: No automatic GPU capture.
 *      1: Capture all GPU commands issued during the lifetime of the VkDevice.
 *    If none of these is set, no automatic GPU capture will occur.
 *
 * 6. The MVK_CONFIG_TEXTURE_1D_AS_2D runtime environment variable or MoltenVK compile-time build
 *    setting controls whether MoltenVK should use a Metal 2D texture with a height of 1 for a
 *    Vulkan 1D image, or use a native Metal 1D texture. Metal imposes significant restrictions
 *    on native 1D textures, including not being renderable, clearable, or permitting mipmaps.
 *    Using a Metal 2D texture allows Vulkan 1D textures to support this additional functionality.
 *    This setting is enabled by default, and MoltenVK will use a Metal 2D texture for each Vulkan 1D image.
 */
typedef struct {

	/**
	 * If enabled, debugging capabilities will be enabled, including logging
	 * shader code during runtime shader conversion.
	 *
	 * The value of this parameter may be changed at any time during application runtime,
	 * and the changed value will immediately effect subsequent MoltenVK behaviour.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_DEBUG
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter is false if MoltenVK was
	 * built in Release mode, and true if MoltenVK was built in Debug mode.
	 */
    VkBool32 debugMode;

	/**
	 * If enabled, MSL vertex shader code created during runtime shader conversion will
	 * flip the Y-axis of each vertex, as the Vulkan Y-axis is the inverse of OpenGL.
	 *
	 * An alternate way to reverse the Y-axis is to employ a negative Y-axis value on
	 * the viewport, in which case this parameter can be disabled.
	 *
	 * The value of this parameter may be changed at any time during application runtime,
	 * and the changed value will immediately effect subsequent MoltenVK behaviour.
	 * Specifically, this parameter can be enabled when compiling some pipelines,
	 * and disabled when compiling others. Existing pipelines are not automatically
	 * re-compiled when this parameter is changed.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to true.
	 */
    VkBool32 shaderConversionFlipVertexY;

	/**
	 * If enabled, queue command submissions (vkQueueSubmit() & vkQueuePresentKHR()) will be
	 * processed on the thread that called the submission function. If disabled, processing
	 * will be dispatched to a GCD dispatch_queue whose priority is determined by
	 * VkDeviceQueueCreateInfo::pQueuePriorities during vkCreateDevice().
	 *
	 * The value of this parameter must be changed before creating a VkDevice,
	 * for the change to take effect.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to true for macOS 10.14
	 * and above or iOS 12 and above, and false otherwise. The reason for this distinction
	 * is that this feature should be disabled when emulation is required to support VkEvents
	 * because native support for events (MTLEvent) is not available.
	 */
	VkBool32 synchronousQueueSubmits;

	/**
	 * If enabled, where possible, a Metal command buffer will be created and filled when each
	 * Vulkan command buffer is filled. For applications that parallelize the filling of Vulkan
	 * commmand buffers across multiple threads, this allows the Metal command buffers to also
	 * be filled on the same parallel thread. Because each command buffer is filled separately,
	 * this requires that each Vulkan command buffer requires a dedicated Metal command buffer.
	 *
	 * If disabled, a single Metal command buffer will be created and filled when the Vulkan
	 * command buffers are submitted to the Vulkan queue. This allows a single Metal command
	 * buffer to be used for all of the Vulkan command buffers in a queue submission. The
	 * Metal command buffer is filled on the thread that processes the command queue submission.
	 *
	 * Depending on the nature of your application, you may find performance is improved by filling
	 * the Metal command buffers on parallel threads, or you may find that performance is improved by
	 * consolidating all Vulkan command buffers onto a single Metal command buffer during queue submission.
	 *
	 * Prefilling of a Metal command buffer will not occur during the filling of secondary command
	 * buffers (VK_COMMAND_BUFFER_LEVEL_SECONDARY), or for primary command buffers that are intended
	 * to be submitted to multiple queues concurrently (VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT).
	 *
	 * When enabling this feature, be aware that one Metal command buffer is required for each Vulkan
	 * command buffer. Depending on the number of command buffers that you use, you may also need to
	 * change the value of the maxActiveMetalCommandBuffersPerQueue setting.
	 *
	 * In addition, if this feature is enabled, be aware that if you have recorded commands to a
	 * Vulkan command buffer, and then choose to reset that command buffer instead of submitting it,
	 * the corresponding prefilled Metal command buffer will still be submitted. This is because Metal
	 * command buffers do not support the concept of being reset after being filled. Depending on when
	 * and how often you do this, it may cause unexpected visual artifacts and unnecessary GPU load.
	 *
	 * The value of this parameter may be changed at any time during application runtime,
	 * and the changed value will immediately effect subsequent MoltenVK behaviour.
	 * Specifically, this parameter can be enabled when filling some command buffers,
	 * and disabled when filling others.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to false.
	 */
	VkBool32 prefillMetalCommandBuffers;

	/**
	 * The maximum number of Metal command buffers that can be concurrently active per Vulkan queue.
	 * The number of active Metal command buffers required depends on the prefillMetalCommandBuffers
	 * setting. If prefillMetalCommandBuffers is enabled, one Metal command buffer is required per
	 * Vulkan command buffer. If prefillMetalCommandBuffers is disabled, one Metal command buffer
	 * is required per command buffer queue submission, which may be significantly less than the
	 * number of Vulkan command buffers.
	 *
	 * The value of this parameter must be changed before creating a VkDevice,
	 * for the change to take effect.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to 64.
	 */
	uint32_t maxActiveMetalCommandBuffersPerQueue;

	/**
	 * Metal allows only 8192 occlusion queries per MTLBuffer. If enabled, MoltenVK
	 * allocates a MTLBuffer for each query pool, allowing each query pool to support
	 * 8192 queries, which may slow performance or cause unexpected behaviour if the query
	 * pool is not established prior to a Metal renderpass, or if the query pool is changed
	 * within a renderpass. If disabled, one MTLBuffer will be shared by all query pools,
	 * which improves performance, but limits the total device queries to 8192.
	 *
	 * The value of this parameter may be changed at any time during application runtime,
	 * and the changed value will immediately effect subsequent MoltenVK behaviour.
	 * Specifically, this parameter can be enabled when creating some query pools,
	 * and disabled when creating others.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to true.
	 */
	VkBool32 supportLargeQueryPools;

	/** Obsolete, ignored, and deprecated. All surface presentations are performed with a command buffer. */
	VkBool32 presentWithCommandBuffer;

	/**
	 * If enabled, swapchain images will use simple Nearest sampling when magnifying the
	 * swapchain image to fit a physical display surface. If disabled, swapchain images will
	 * use Linear sampling when magnifying the swapchain image to fit a physical display surface.
	 * Enabling this setting avoids smearing effects when swapchain images are simple interger
	 * multiples of display pixels (eg- macOS Retina, and typical of graphics apps and games),
	 * but may cause aliasing effects when using non-integer display scaling.
	 *
	 * The value of this parameter may be changed before creating a VkSwapchain,
	 * for the change to take effect.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to true.
	 */
	VkBool32 swapchainMagFilterUseNearest;

	/**
	 * The maximum amount of time, in nanoseconds, to wait for a Metal library, function, or
	 * pipeline state object to be compiled and created by the Metal compiler. An internal error
	 * within the Metal compiler can stall the thread for up to 30 seconds. Setting this value
	 * limits that delay to a specified amount of time, allowing shader compilations to fail fast.
	 *
	 * The value of this parameter may be changed at any time during application runtime,
	 * and the changed value will immediately effect subsequent MoltenVK behaviour.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_METAL_COMPILE_TIMEOUT
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to infinite.
	 */
	uint64_t metalCompileTimeout;

	/**
	 * If enabled, performance statistics, as defined by the MVKPerformanceStatistics structure,
	 * are collected, and can be retrieved via the vkGetPerformanceStatisticsMVK() function.
	 *
	 * You can also use the performanceLoggingFrameCount parameter to automatically log the
	 * performance statistics collected by this parameter.
	 *
	 * The value of this parameter may be changed at any time during application runtime,
	 * and the changed value will immediately effect subsequent MoltenVK behaviour.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_PERFORMANCE_TRACKING
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to false.
	 */
	VkBool32 performanceTracking;

	/**
	 * If non-zero, performance statistics, as defined by the MVKPerformanceStatistics structure,
	 * will be logged to the console. Frame-based statistics will be logged, on a repeating cycle,
	 * once per this many frames. Non-frame-based statistics will be logged as they occur.
	 *
	 * The performanceTracking parameter must also be enabled. If this parameter is zero, or
	 * the performanceTracking parameter is disabled, no performance statistics will be logged.
	 *
	 * The value of this parameter may be changed at any time during application runtime,
	 * and the changed value will immediately effect subsequent MoltenVK behaviour.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to zero.
	 */
	uint32_t performanceLoggingFrameCount;

	/**
	 * If enabled, a MoltenVK logo watermark will be rendered on top of the scene.
	 * This can be enabled for publicity during demos.
	 *
	 * The value of this parameter may be changed at any time during application runtime,
	 * and the changed value will immediately effect subsequent MoltenVK behaviour.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_DISPLAY_WATERMARK
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to false.
	 */
	VkBool32 displayWatermark;

	/**
	 * Metal does not distinguish functionality between queues, which would normally mean only
	 * a single general-purpose queue family with multiple queues is needed. However, Vulkan
	 * associates command buffers with a queue family, whereas Metal associates command buffers
	 * with a specific Metal queue. In order to allow a Metal command buffer to be prefilled
	 * before is is formally submitted to a Vulkan queue, each Vulkan queue family can support
	 * only a single Metal queue. As a result, in order to provide parallel queue operations,
	 * MoltenVK provides multiple queue families, each with a single queue.
	 *
	 * If this parameter is disabled, all queue families will be advertised as having general-purpose
	 * graphics + compute + transfer functionality, which is how the actual Metal queues behave.
	 *
	 * If this parameter is enabled, one queue family will be advertised as having general-purpose
	 * graphics + compute + transfer functionality, and the remaining queue families will be advertised
	 * as having specialized graphics OR compute OR transfer functionality, to make it easier for some
	 * apps to select a queue family with the appropriate requirements.
	 *
	 * The value of this parameter must be changed before creating a VkDevice, and before
	 * querying a VkPhysicalDevice for queue family properties, for the change to take effect.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_SPECIALIZED_QUEUE_FAMILIES
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to false.
	 */
	VkBool32 specializedQueueFamilies;

	/**
	 * If enabled, when the app creates a VkDevice from a VkPhysicalDevice (GPU) that is neither
	 * headless nor low-power, and is different than the GPU used by the windowing system, the
	 * windowing system will be forced to switch to use the GPU selected by the Vulkan app.
	 * When the Vulkan app is ended, the windowing system will automatically switch back to
	 * using the previous GPU, depending on the usage requirements of other running apps.
	 *
	 * If disabled, the Vulkan app will render using its selected GPU, and if the windowing
	 * system uses a different GPU, the windowing system compositor will automatically copy
	 * framebuffer content from the app GPU to the windowing system GPU.
	 *
	 * The value of this parmeter has no effect on systems with a single GPU, or when the
	 * Vulkan app creates a VkDevice from a low-power or headless VkPhysicalDevice (GPU).
	 *
	 * Switching the windowing system GPU to match the Vulkan app GPU maximizes app performance,
	 * because it avoids the windowing system compositor from having to copy framebuffer content
	 * between GPUs on each rendered frame. However, doing so forces the entire system to
	 * potentially switch to using a GPU that may consume more power while the app is running.
	 *
	 * Some Vulkan apps may want to render using a high-power GPU, but leave it up to the
	 * system window compositor to determine how best to blend content with the windowing
	 * system, and as a result, may want to disable this parameter.
	 *
	 * The value of this parameter must be changed before creating a VkDevice,
	 * for the change to take effect.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_SWITCH_SYSTEM_GPU
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to true.
	 */
	VkBool32 switchSystemGPU;

	/**
	 * If enabled, arbitrary VkImageView component swizzles are supported, as defined
	 * in VkImageViewCreateInfo::components when creating a VkImageView.
	 *
	 * If disabled, a very limited set of VkImageView component swizzles are supported
	 * via format substitutions.
	 *
	 * Metal does not natively support per-texture swizzling. If this parameter is enabled
	 * both when a VkImageView is created, and when any pipeline that uses that VkImageView
	 * is compiled, VkImageView swizzling is automatically performed in the converted Metal
	 * shader code during all texture sampling and reading operations, regardless of whether
	 * a swizzle is required for the VkImageView associated with the Metal texture.
	 * This may result in reduced performance.
	 *
	 * The value of this parameter may be changed at any time during application runtime,
	 * and the changed value will immediately effect subsequent MoltenVK behaviour.
	 * Specifically, this parameter can be enabled when creating VkImageViews that need it,
	 * and compiling pipelines that use those VkImageViews, and can be disabled when creating
	 * VkImageViews that don't need it, and compiling pipelines that use those VkImageViews.
	 *
	 * Existing pipelines are not automatically re-compiled when this parameter is changed.
	 *
	 * An error is logged and returned during VkImageView creation if that VkImageView
	 * requires full image view swizzling and this feature is not enabled. An error is
	 * also logged when a pipeline that was not compiled with full image view swizzling
	 * is presented with a VkImageView that is expecting it.
	 *
	 * An error is also retuned and logged when a VkPhysicalDeviceImageFormatInfo2KHR is passed
	 * in a call to vkGetPhysicalDeviceImageFormatProperties2KHR() to query for an VkImageView
	 * format that will require full swizzling to be enabled, and this feature is not enabled.
	 *
	 * If this parameter is disabled, the following limited set of VkImageView swizzles are
	 * supported by MoltenVK, via automatic format substitution:
	 *
	 * Texture format			       Swizzle
	 * --------------                  -------
	 * VK_FORMAT_R8_UNORM              ZERO, ANY, ANY, RED
	 * VK_FORMAT_A8_UNORM              ALPHA, ANY, ANY, ZERO
	 * VK_FORMAT_R8G8B8A8_UNORM        BLUE, GREEN, RED, ALPHA
	 * VK_FORMAT_R8G8B8A8_SRGB         BLUE, GREEN, RED, ALPHA
	 * VK_FORMAT_B8G8R8A8_UNORM        BLUE, GREEN, RED, ALPHA
	 * VK_FORMAT_B8G8R8A8_SRGB         BLUE, GREEN, RED, ALPHA
	 * VK_FORMAT_D32_SFLOAT_S8_UINT    RED, ANY, ANY, ANY (stencil only)
	 * VK_FORMAT_D24_UNORM_S8_UINT     RED, ANY, ANY, ANY (stencil only)
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to false.
	 */
	VkBool32 fullImageViewSwizzle;

	/**
	 * The index of the queue family whose presentation submissions will
	 * be used as the default GPU Capture Scope during debugging in Xcode.
	 *
	 * The value of this parameter must be changed before creating a VkDevice,
	 * for the change to take effect.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_FAMILY_INDEX
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to zero (the first queue family).
	 */
	uint32_t defaultGPUCaptureScopeQueueFamilyIndex;

	/**
	 * The index of the queue, within the queue family identified by the
	 * defaultGPUCaptureScopeQueueFamilyIndex parameter, whose presentation submissions
	 * will be used as the default GPU Capture Scope during debugging in Xcode.
	 *
	 * The value of this parameter must be changed before creating a VkDevice,
	 * for the change to take effect.
	 *
	 * The initial value or this parameter is set by the
	 * MVK_CONFIG_DEFAULT_GPU_CAPTURE_SCOPE_QUEUE_INDEX
	 * runtime environment variable or MoltenVK compile-time build setting.
	 * If neither is set, the value of this parameter defaults to zero (the first queue).
	 */
	uint32_t defaultGPUCaptureScopeQueueIndex;

} MVKConfiguration;

/**
 * Features provided by the current implementation of Metal on the current device. You can
 * retrieve a copy of this structure using the vkGetPhysicalDeviceMetalFeaturesMVK() function.
 *
 * This structure may be extended as new features are added to MoltenVK. If you are linking to
 * an implementation of MoltenVK that was compiled from a different VK_MVK_MOLTENVK_SPEC_VERSION
 * than your app was, the size of this structure in your app may be larger or smaller than the
 * struct in MoltenVK. See the description of the vkGetPhysicalDeviceMetalFeaturesMVK() function
 * for information about how to handle this.
 *
 * TO SUPPORT DYNAMIC LINKING TO THIS STRUCTURE AS DESCRIBED ABOVE, THIS STRUCTURE SHOULD NOT
 * BE CHANGED EXCEPT TO ADD ADDITIONAL MEMBERS ON THE END. EXISTING MEMBERS, AND THEIR ORDER,
 * SHOULD NOT BE CHANGED.
 */
typedef struct {
    uint32_t mslVersion;                        /**< The version of the Metal Shading Language available on this device. The format of the integer is MMmmpp, with two decimal digts each for Major, minor, and patch version values (eg. MSL 1.2 would appear as 010200). */
	VkBool32 indirectDrawing;                   /**< If true, draw calls support parameters held in a GPU buffer. */
	VkBool32 baseVertexInstanceDrawing;         /**< If true, draw calls support specifiying the base vertex and instance. */
    uint32_t dynamicMTLBufferSize;              /**< If greater than zero, dynamic MTLBuffers for setting vertex, fragment, and compute bytes are supported, and their content must be below this value. */
    VkBool32 shaderSpecialization;              /**< If true, shader specialization (aka Metal function constants) is supported. */
    VkBool32 ioSurfaces;                        /**< If true, VkImages can be underlaid by IOSurfaces via the vkUseIOSurfaceMVK() function, to support inter-process image transfers. */
    VkBool32 texelBuffers;                      /**< If true, texel buffers are supported, allowing the contents of a buffer to be interpreted as an image via a VkBufferView. */
	VkBool32 layeredRendering;                  /**< If true, layered rendering to multiple cube or texture array layers is supported. */
	VkBool32 presentModeImmediate;              /**< If true, immediate surface present mode (VK_PRESENT_MODE_IMMEDIATE_KHR), allowing a swapchain image to be presented immediately, without waiting for the vertical sync period of the display, is supported. */
	VkBool32 stencilViews;                      /**< If true, stencil aspect views are supported through the MTLPixelFormatX24_Stencil8 and MTLPixelFormatX32_Stencil8 formats. */
	VkBool32 multisampleArrayTextures;          /**< If true, MTLTextureType2DMultisampleArray is supported. */
	VkBool32 samplerClampToBorder;              /**< If true, the border color set when creating a sampler will be respected. */
	uint32_t maxTextureDimension; 	     	  	/**< The maximum size of each texture dimension (width, height, or depth). */
	uint32_t maxPerStageBufferCount;            /**< The total number of per-stage Metal buffers available for shader uniform content and attributes. */
    uint32_t maxPerStageTextureCount;           /**< The total number of per-stage Metal textures available for shader uniform content. */
    uint32_t maxPerStageSamplerCount;           /**< The total number of per-stage Metal samplers available for shader uniform content. */
    VkDeviceSize maxMTLBufferSize;              /**< The max size of a MTLBuffer (in bytes). */
    VkDeviceSize mtlBufferAlignment;            /**< The alignment used when allocating memory for MTLBuffers. Must be PoT. */
    VkDeviceSize maxQueryBufferSize;            /**< The maximum size of an occlusion query buffer (in bytes). */
	VkDeviceSize mtlCopyBufferAlignment;        /**< The alignment required during buffer copy operations (in bytes). */
    VkSampleCountFlags supportedSampleCounts;   /**< A bitmask identifying the sample counts supported by the device. */
	uint32_t minSwapchainImageCount;	 	  	/**< The minimum number of swapchain images that can be supported by a surface. */
	uint32_t maxSwapchainImageCount;	 	  	/**< The maximum number of swapchain images that can be supported by a surface. */
	VkBool32 combinedStoreResolveAction;		/**< If true, the device supports VK_ATTACHMENT_STORE_OP_STORE with a simultaneous resolve attachment. */
	VkBool32 arrayOfTextures;			 	  	/**< If true, arrays of textures is supported. */
	VkBool32 arrayOfSamplers;			 	  	/**< If true, arrays of texture samplers is supported. */
	MTLLanguageVersion mslVersionEnum;			/**< The version of the Metal Shading Language available on this device, as a Metal enumeration. */
	VkBool32 depthSampleCompare;				/**< If true, depth texture samplers support the comparison of the pixel value against a reference value. */
	VkBool32 events;							/**< If true, Metal synchronization events (MTLEvent) are supported. */
	VkBool32 memoryBarriers;					/**< If true, full memory barriers within Metal render passes are supported. */
	VkBool32 multisampleLayeredRendering;       /**< If true, layered rendering to multiple multi-sampled cube or texture array layers is supported. */
	VkBool32 stencilFeedback;					/**< If true, fragment shaders that write to [[stencil]] outputs are supported. */
	VkBool32 textureBuffers;					/**< If true, textures of type MTLTextureTypeBuffer are supported. */
	VkBool32 postDepthCoverage;					/**< If true, coverage masks in fragment shaders post-depth-test are supported. */
	VkBool32 fences;							/**< If true, Metal synchronization fences (MTLFence) are supported. */
	VkBool32 rasterOrderGroups;					/**< If true, Raster order groups in fragment shaders are supported. */
	VkBool32 native3DCompressedTextures;		/**< If true, 3D compressed images are supported natively, without manual decompression. */
	VkBool32 nativeTextureSwizzle;				/**< If true, component swizzle is supported natively, without manual swizzling in shaders. */
	VkBool32 placementHeaps;					/**< If true, MTLHeap objects support placement of resources. */
} MVKPhysicalDeviceMetalFeatures;

/**
 * MoltenVK swapchain performance statistics. You can retrieve a copy of this structure using
 * the vkGetSwapchainPerformanceMVK() function.
 *
 * This structure may be extended as new features are added to MoltenVK. If you are linking to
 * an implementation of MoltenVK that was compiled from a different VK_MVK_MOLTENVK_SPEC_VERSION
 * than your app was, the size of this structure in your app may be larger or smaller than the
 * struct in MoltenVK. See the description of the vkGetSwapchainPerformanceMVK() function for
 * information about how to handle this.
 *
 * TO SUPPORT DYNAMIC LINKING TO THIS STRUCTURE AS DESCRIBED ABOVE, THIS STRUCTURE SHOULD NOT
 * BE CHANGED EXCEPT TO ADD ADDITIONAL MEMBERS ON THE END. EXISTING MEMBERS, AND THEIR ORDER,
 * SHOULD NOT BE CHANGED.
 */
typedef struct {
    double lastFrameInterval;           /**< The time interval between this frame and the immediately previous frame, in milliseconds. */
    double averageFrameInterval;        /**< The rolling average time interval between frames, in miliseconds. This value has less volatility than the lastFrameInterval value. */
    double averageFramesPerSecond;      /**< The rolling average number of frames per second. This is simply the 1000 divided by the averageFrameInterval value. */
} MVKSwapchainPerformance;

/** MoltenVK performance of a particular type of activity. */
typedef struct {
    uint32_t count;             /**< The number of activities of this type. */
    double averageDuration;     /**< The average duration of the activity, in milliseconds. */
    double minimumDuration;     /**< The minimum duration of the activity, in milliseconds. */
    double maximumDuration;     /**< The maximum duration of the activity, in milliseconds. */
} MVKPerformanceTracker;

/** MoltenVK performance of shader compilation activities. */
typedef struct {
	MVKPerformanceTracker hashShaderCode;				/** Create a hash from the incoming shader code. */
    MVKPerformanceTracker spirvToMSL;					/** Convert SPIR-V to MSL source code. */
    MVKPerformanceTracker mslCompile;					/** Compile MSL source code into a MTLLibrary. */
    MVKPerformanceTracker mslLoad;						/** Load pre-compiled MSL code into a MTLLibrary. */
	MVKPerformanceTracker shaderLibraryFromCache;		/** Retrieve a shader library from the cache, lazily creating it if needed. */
    MVKPerformanceTracker functionRetrieval;			/** Retrieve a MTLFunction from a MTLLibrary. */
    MVKPerformanceTracker functionSpecialization;		/** Specialize a retrieved MTLFunction. */
    MVKPerformanceTracker pipelineCompile;				/** Compile MTLFunctions into a pipeline. */
	MVKPerformanceTracker glslToSPRIV;					/** Convert GLSL to SPIR-V code. */
} MVKShaderCompilationPerformance;


/** MoltenVK performance of pipeline cache activities. */
typedef struct {
	MVKPerformanceTracker sizePipelineCache;			/** Calculate the size of cache data required to write MSL to pipeline cache data stream. */
	MVKPerformanceTracker writePipelineCache;			/** Write MSL to pipeline cache data stream. */
	MVKPerformanceTracker readPipelineCache;			/** Read MSL from pipeline cache data stream. */
} MVKPipelineCachePerformance;

/** MoltenVK performance of queue activities. */
typedef struct {
	MVKPerformanceTracker mtlQueueAccess;               /** Create an MTLCommmandQueue or access an existing cached instance. */
	MVKPerformanceTracker mtlCommandBufferCompletion;   /** Completion of a MTLCommandBuffer on the GPU, from commit to completion callback. */
} MVKQueuePerformance;

/**
 * MoltenVK performance. You can retrieve a copy of this structure using the vkGetPerformanceStatisticsMVK() function.
 *
 * This structure may be extended as new features are added to MoltenVK. If you are linking to
 * an implementation of MoltenVK that was compiled from a different VK_MVK_MOLTENVK_SPEC_VERSION
 * than your app was, the size of this structure in your app may be larger or smaller than the
 * struct in MoltenVK. See the description of the vkGetPerformanceStatisticsMVK() function for
 * information about how to handle this.
 *
 * TO SUPPORT DYNAMIC LINKING TO THIS STRUCTURE AS DESCRIBED ABOVE, THIS STRUCTURE SHOULD NOT
 * BE CHANGED EXCEPT TO ADD ADDITIONAL MEMBERS ON THE END. EXISTING MEMBERS, AND THEIR ORDER,
 * SHOULD NOT BE CHANGED.
 */
typedef struct {
	MVKShaderCompilationPerformance shaderCompilation;	/** Shader compilations activities. */
	MVKPipelineCachePerformance pipelineCache;			/** Pipeline cache activities. */
	MVKQueuePerformance queue;          				/** Queue activities. */
} MVKPerformanceStatistics;


#pragma mark -
#pragma mark Function types

typedef VkResult (VKAPI_PTR *PFN_vkGetMoltenVKConfigurationMVK)(VkInstance instance, MVKConfiguration* pConfiguration, size_t* pConfigurationSize);
typedef VkResult (VKAPI_PTR *PFN_vkSetMoltenVKConfigurationMVK)(VkInstance instance, MVKConfiguration* pConfiguration, size_t* pConfigurationSize);
typedef VkResult (VKAPI_PTR *PFN_vkGetPhysicalDeviceMetalFeaturesMVK)(VkPhysicalDevice physicalDevice, MVKPhysicalDeviceMetalFeatures* pMetalFeatures, size_t* pMetalFeaturesSize);
typedef VkResult (VKAPI_PTR *PFN_vkGetSwapchainPerformanceMVK)(VkDevice device, VkSwapchainKHR swapchain, MVKSwapchainPerformance* pSwapchainPerf, size_t* pSwapchainPerfSize);
typedef VkResult (VKAPI_PTR *PFN_vkGetPerformanceStatisticsMVK)(VkDevice device, MVKPerformanceStatistics* pPerf, size_t* pPerfSize);
typedef void (VKAPI_PTR *PFN_vkGetVersionStringsMVK)(char* pMoltenVersionStringBuffer, uint32_t moltenVersionStringBufferLength, char* pVulkanVersionStringBuffer, uint32_t vulkanVersionStringBufferLength);

#ifdef __OBJC__
typedef void (VKAPI_PTR *PFN_vkGetMTLDeviceMVK)(VkPhysicalDevice physicalDevice, id<MTLDevice>* pMTLDevice);
typedef VkResult (VKAPI_PTR *PFN_vkSetMTLTextureMVK)(VkImage image, id<MTLTexture> mtlTexture);
typedef void (VKAPI_PTR *PFN_vkGetMTLTextureMVK)(VkImage image, id<MTLTexture>* pMTLTexture);
typedef VkResult (VKAPI_PTR *PFN_vkUseIOSurfaceMVK)(VkImage image, IOSurfaceRef ioSurface);
typedef void (VKAPI_PTR *PFN_vkGetIOSurfaceMVK)(VkImage image, IOSurfaceRef* pIOSurface);
#endif // __OBJC__


#pragma mark -
#pragma mark Function prototypes

#ifndef VK_NO_PROTOTYPES

/** 
 * Populates the pConfiguration structure with the current MoltenVK configuration settings.
 *
 * To change a specific configuration value, call vkGetMoltenVKConfigurationMVK() to retrieve
 * the current configuration, make changes, and call  vkSetMoltenVKConfigurationMVK() to
 * update all of the values.
 *
 * To be active, some configuration settings must be set before a VkDevice is created.
 * See the description of the MVKConfiguration members for more information.
 *
 * If you are linking to an implementation of MoltenVK that was compiled from a different
 * VK_MVK_MOLTENVK_SPEC_VERSION than your app was, the size of the MVKConfiguration structure
 * in your app may be larger or smaller than the same struct as expected by MoltenVK.
 *
 * When calling this function, set the value of *pConfigurationSize to sizeof(MVKConfiguration),
 * to tell MoltenVK the limit of the size of your MVKConfiguration structure. Upon return from
 * this function, the value of *pConfigurationSize will hold the actual number of bytes copied
 * into your passed MVKConfiguration structure, which will be the smaller of what your app
 * thinks is the size of MVKConfiguration, and what MoltenVK thinks it is. This represents the
 * safe access area within the structure for both MoltenVK and your app.
 *
 * If the size that MoltenVK expects for MVKConfiguration is different than the value passed in
 * *pConfigurationSize, this function will return VK_INCOMPLETE, otherwise it will return VK_SUCCESS.
 *
 * Although it is not necessary, you can use this function to determine in advance the value
 * that MoltenVK expects the size of MVKConfiguration to be by setting the value of pConfiguration
 * to NULL. In that case, this function will set *pConfigurationSize to the size that MoltenVK
 * expects MVKConfiguration to be.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkInstance object you provide here must have been retrieved directly from MoltenVK,
 * and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan objects
 * are often changed by layers, and passing them from one layer to another, or from
 * a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR VkResult VKAPI_CALL vkGetMoltenVKConfigurationMVK(
	VkInstance                                  instance,
	MVKConfiguration*                           pConfiguration,
	size_t*                                     pConfigurationSize);

/** 
 * Sets the MoltenVK configuration settings to those found in the pConfiguration structure.
 *
 * To change a specific configuration value, call vkGetMoltenVKConfigurationMVK()
 * to retrieve the current configuration, make changes, and call
 * vkSetMoltenVKConfigurationMVK() to update all of the values.
 *
 * To be active, some configuration settings must be set before a VkDevice is created.
 * See the description of the MVKConfiguration members for more information.
 *
 * If you are linking to an implementation of MoltenVK that was compiled from a different
 * VK_MVK_MOLTENVK_SPEC_VERSION than your app was, the size of the MVKConfiguration structure
 * in your app may be larger or smaller than the same struct as expected by MoltenVK.
 *
 * When calling this function, set the value of *pConfigurationSize to sizeof(MVKConfiguration),
 * to tell MoltenVK the limit of the size of your MVKConfiguration structure. Upon return from
 * this function, the value of *pConfigurationSize will hold the actual number of bytes copied
 * out of your passed MVKConfiguration structure, which will be the smaller of what your app
 * thinks is the size of MVKConfiguration, and what MoltenVK thinks it is. This represents the
 * safe access area within the structure for both MoltenVK and your app.
 *
 * If the size that MoltenVK expects for MVKConfiguration is different than the value passed in
 * *pConfigurationSize, this function will return VK_INCOMPLETE, otherwise it will return VK_SUCCESS.
 *
 * Although it is not necessary, you can use this function to determine in advance the value
 * that MoltenVK expects the size of MVKConfiguration to be by setting the value of pConfiguration
 * to NULL. In that case, this function will set *pConfigurationSize to the size that MoltenVK
 * expects MVKConfiguration to be.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkInstance object you provide here must have been retrieved directly from MoltenVK,
 * and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan objects
 * are often changed by layers, and passing them from one layer to another, or from
 * a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR VkResult VKAPI_CALL vkSetMoltenVKConfigurationMVK(
	VkInstance                                  instance,
	const MVKConfiguration*                     pConfiguration,
	size_t*                                     pConfigurationSize);

/** 
 * Populates the pMetalFeatures structure with the Metal-specific features
 * supported by the specified physical device. 
 *
 * If you are linking to an implementation of MoltenVK that was compiled from a different
 * VK_MVK_MOLTENVK_SPEC_VERSION than your app was, the size of the MVKPhysicalDeviceMetalFeatures
 * structure in your app may be larger or smaller than the same struct as expected by MoltenVK.
 *
 * When calling this function, set the value of *pMetalFeaturesSize to sizeof(MVKPhysicalDeviceMetalFeatures),
 * to tell MoltenVK the limit of the size of your MVKPhysicalDeviceMetalFeatures structure. Upon return from
 * this function, the value of *pMetalFeaturesSize will hold the actual number of bytes copied into your
 * passed MVKPhysicalDeviceMetalFeatures structure, which will be the smaller of what your app thinks is the
 * size of MVKPhysicalDeviceMetalFeatures, and what MoltenVK thinks it is. This represents the safe access
 * area within the structure for both MoltenVK and your app.
 *
 * If the size that MoltenVK expects for MVKPhysicalDeviceMetalFeatures is different than the value passed in
 * *pMetalFeaturesSize, this function will return VK_INCOMPLETE, otherwise it will return VK_SUCCESS.
 *
 * Although it is not necessary, you can use this function to determine in advance the value that MoltenVK
 * expects the size of MVKPhysicalDeviceMetalFeatures to be by setting the value of pMetalFeatures to NULL.
 * In that case, this function will set *pMetalFeaturesSize to the size that MoltenVK expects
 * MVKPhysicalDeviceMetalFeatures to be.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkPhysicalDevice object you provide here must have been retrieved directly from
 * MoltenVK, and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan
 * objects are often changed by layers, and passing them from one layer to another,
 * or from a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR VkResult VKAPI_CALL vkGetPhysicalDeviceMetalFeaturesMVK(
	VkPhysicalDevice                            physicalDevice,
	MVKPhysicalDeviceMetalFeatures*             pMetalFeatures,
	size_t*                                     pMetalFeaturesSize);

/**
 * Populates the pSwapchainPerf structure with the current performance statistics for the swapchain.
 *
 * If you are linking to an implementation of MoltenVK that was compiled from a different
 * VK_MVK_MOLTENVK_SPEC_VERSION than your app was, the size of the MVKSwapchainPerformance
 * structure in your app may be larger or smaller than the same struct as expected by MoltenVK.
 *
 * When calling this function, set the value of *pSwapchainPerfSize to sizeof(MVKSwapchainPerformance),
 * to tell MoltenVK the limit of the size of your MVKSwapchainPerformance structure. Upon return from
 * this function, the value of *pSwapchainPerfSize will hold the actual number of bytes copied into
 * your passed MVKSwapchainPerformance structure, which will be the smaller of what your app thinks
 * is the size of MVKSwapchainPerformance, and what MoltenVK thinks it is. This represents the safe
 * access area within the structure for both MoltenVK and your app.
 *
 * If the size that MoltenVK expects for MVKSwapchainPerformance is different than the value passed in
 * *pSwapchainPerfSize, this function will return VK_INCOMPLETE, otherwise it will return VK_SUCCESS.
 *
 * Although it is not necessary, you can use this function to determine in advance the value
 * that MoltenVK expects the size of MVKSwapchainPerformance to be by setting the value of
 * pSwapchainPerf to NULL. In that case, this function will set *pSwapchainPerfSize to the
 * size that MoltenVK expects MVKSwapchainPerformance to be.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkDevice and VkSwapchainKHR objects you provide here must have been retrieved directly
 * from MoltenVK, and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan
 * objects are often changed by layers, and passing them from one layer to another,
 * or from a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR VkResult VKAPI_CALL vkGetSwapchainPerformanceMVK(
	VkDevice                                    device,
	VkSwapchainKHR                              swapchain,
	MVKSwapchainPerformance*                    pSwapchainPerf,
	size_t*                                     pSwapchainPerfSize);

/**
 * Populates the pPerf structure with the current performance statistics for the device.
 *
 * If you are linking to an implementation of MoltenVK that was compiled from a different
 * VK_MVK_MOLTENVK_SPEC_VERSION than your app was, the size of the MVKPerformanceStatistics
 * structure in your app may be larger or smaller than the same struct as expected by MoltenVK.
 *
 * When calling this function, set the value of *pPerfSize to sizeof(MVKPerformanceStatistics),
 * to tell MoltenVK the limit of the size of your MVKPerformanceStatistics structure. Upon return
 * from this function, the value of *pPerfSize will hold the actual number of bytes copied into
 * your passed MVKPerformanceStatistics structure, which will be the smaller of what your app
 * thinks is the size of MVKPerformanceStatistics, and what MoltenVK thinks it is. This
 * represents the safe access area within the structure for both MoltenVK and your app.
 *
 * If the size that MoltenVK expects for MVKPerformanceStatistics is different than the value passed
 * in *pPerfSize, this function will return VK_INCOMPLETE, otherwise it will return VK_SUCCESS.
 *
 * Although it is not necessary, you can use this function to determine in advance the value
 * that MoltenVK expects the size of MVKPerformanceStatistics to be by setting the value of
 * pPerf to NULL. In that case, this function will set *pPerfSize to the size that MoltenVK
 * expects MVKPerformanceStatistics to be.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkDevice object you provide here must have been retrieved directly from
 * MoltenVK, and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan
 * objects are often changed by layers, and passing them from one layer to another,
 * or from a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR VkResult VKAPI_CALL vkGetPerformanceStatisticsMVK(
	VkDevice                                    device,
	MVKPerformanceStatistics*            		pPerf,
	size_t*                                     pPerfSize);

/**
 * Returns a human readable version of the MoltenVK and Vulkan versions.
 *
 * This function is provided as a convenience for reporting. Use the MVK_VERSION, 
 * VK_API_VERSION_1_0, and VK_HEADER_VERSION macros for programmatically accessing
 * the corresponding version numbers.
 */
VKAPI_ATTR void VKAPI_CALL vkGetVersionStringsMVK(
    char*                                       pMoltenVersionStringBuffer,
    uint32_t                                    moltenVersionStringBufferLength,
    char*                                       pVulkanVersionStringBuffer,
    uint32_t                                    vulkanVersionStringBufferLength);

/**
 * Sets the number of threads in a workgroup for a compute kernel.
 *
 * This needs to be called if you are creating compute shader modules from MSL
 * source code or MSL compiled code. Workgroup size is determined automatically
 * if you're using SPIR-V.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkShaderModule object you provide here must have been retrieved directly from
 * MoltenVK, and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan
 * objects are often changed by layers, and passing them from one layer to another,
 * or from a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR void VKAPI_CALL vkSetWorkgroupSizeMVK(
    VkShaderModule                              shaderModule,
    uint32_t                                    x,
    uint32_t                                    y,
    uint32_t                                    z);

#ifdef __OBJC__

/**
 * Returns, in the pMTLDevice pointer, the MTLDevice used by the VkPhysicalDevice.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkPhysicalDevice object you provide here must have been retrieved directly from
 * MoltenVK, and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan
 * objects are often changed by layers, and passing them from one layer to another,
 * or from a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR void VKAPI_CALL vkGetMTLDeviceMVK(
    VkPhysicalDevice                           physicalDevice,
    id<MTLDevice>*                             pMTLDevice);

/**
 * Sets the VkImage to use the specified MTLTexture.
 *
 * Any differences in the properties of mtlTexture and this image will modify the
 * properties of this image.
 *
 * If a MTLTexture has already been created for this image, it will be destroyed.
 *
 * Returns VK_SUCCESS.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkImage object you provide here must have been retrieved directly from
 * MoltenVK, and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan
 * objects are often changed by layers, and passing them from one layer to another,
 * or from a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR VkResult VKAPI_CALL vkSetMTLTextureMVK(
    VkImage                                     image,
    id<MTLTexture>                              mtlTexture);

/**
 * Returns, in the pMTLTexture pointer, the MTLTexture currently underlaying the VkImage.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkImage object you provide here must have been retrieved directly from
 * MoltenVK, and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan
 * objects are often changed by layers, and passing them from one layer to another,
 * or from a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR void VKAPI_CALL vkGetMTLTextureMVK(
    VkImage                                     image,
    id<MTLTexture>*                             pMTLTexture);

/**
 * Indicates that a VkImage should use an IOSurface to underlay the Metal texture.
 *
 * If ioSurface is not null, it will be used as the IOSurface, and any differences
 * in the properties of that IOSurface will modify the properties of this image.
 *
 * If ioSurface is null, this image will create and use an IOSurface
 * whose properties are compatible with the properties of this image.
 *
 * If a MTLTexture has already been created for this image, it will be destroyed.
 *
 * IOSurfaces are supported on the following platforms:
 *   -  macOS 10.11 and above
 *   -  iOS 11.0 and above
 *
 * To enable IOSurface support, ensure the Deployment Target build setting
 * (MACOSX_DEPLOYMENT_TARGET or IPHONEOS_DEPLOYMENT_TARGET) is set to at least
 * one of the values above when compiling MoltenVK, and any app that uses MoltenVK.
 *
 * Returns:
 *   - VK_SUCCESS.
 *   - VK_ERROR_FEATURE_NOT_PRESENT if IOSurfaces are not supported on the platform.
 *   - VK_ERROR_INITIALIZATION_FAILED if ioSurface is specified and is not compatible with this VkImage.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkImage object you provide here must have been retrieved directly from
 * MoltenVK, and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan
 * objects are often changed by layers, and passing them from one layer to another,
 * or from a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR VkResult VKAPI_CALL vkUseIOSurfaceMVK(
    VkImage                                     image,
    IOSurfaceRef                                ioSurface);

/**
 * Returns, in the pIOSurface pointer, the IOSurface currently underlaying the VkImage,
 * as set by the useIOSurfaceMVK() function, or returns null if the VkImage is not using
 * an IOSurface, or if the platform does not support IOSurfaces.
 *
 * This function is not supported by the Vulkan SDK Loader and Layers framework.
 * The VkImage object you provide here must have been retrieved directly from
 * MoltenVK, and not through the Vulkan SDK Loader and Layers framework. Opaque Vulkan
 * objects are often changed by layers, and passing them from one layer to another,
 * or from a layer directly to MoltenVK, will result in undefined behaviour.
 */
VKAPI_ATTR void VKAPI_CALL vkGetIOSurfaceMVK(
    VkImage                                     image,
    IOSurfaceRef*                               pIOSurface);

#endif // __OBJC__


#pragma mark -
#pragma mark Shaders

/**
 * Enumerates the magic number values to set in the MVKMSLSPIRVHeader when
 * submitting a SPIR-V stream that contains either Metal Shading Language source
 * code or Metal Shading Language compiled binary code in place of SPIR-V code.
 */
typedef enum {
    kMVKMagicNumberSPIRVCode        = 0x07230203,    /**< SPIR-V stream contains standard SPIR-V code. */
    kMVKMagicNumberMSLSourceCode    = 0x19960412,    /**< SPIR-V stream contains Metal Shading Language source code. */
    kMVKMagicNumberMSLCompiledCode  = 0x19981215,    /**< SPIR-V stream contains Metal Shading Language compiled binary code. */
} MVKMSLMagicNumber;

/**
 * Describes the header at the start of an SPIR-V stream, when it contains either
 * Metal Shading Language source code or Metal Shading Language compiled binary code.
 *
 * To submit MSL source code to the vkCreateShaderModule() function in place of SPIR-V
 * code, prepend a MVKMSLSPIRVHeader containing the kMVKMagicNumberMSLSourceCode magic
 * number to the MSL source code. The MSL source code must be null-terminated.
 *
 * To submit MSL compiled binary code to the vkCreateShaderModule() function in place of
 * SPIR-V code, prepend a MVKMSLSPIRVHeader containing the kMVKMagicNumberMSLCompiledCode
 * magic number to the MSL compiled binary code.
 *
 * In both cases, the pCode element of VkShaderModuleCreateInfo should pointer to the
 * location of the MVKMSLSPIRVHeader, and the MSL code should start at the byte immediately
 * after the MVKMSLSPIRVHeader.
 *
 * The codeSize element of VkShaderModuleCreateInfo should be set to the entire size of
 * the submitted code memory, including the additional sizeof(MVKMSLSPIRVHeader) bytes
 * taken up by the MVKMSLSPIRVHeader, and, in the case of MSL source code, including
 * the null-terminator byte.
 */
typedef uint32_t MVKMSLSPIRVHeader;


#endif // VK_NO_PROTOTYPES


#ifdef __cplusplus
}
#endif	//  __cplusplus

#endif
