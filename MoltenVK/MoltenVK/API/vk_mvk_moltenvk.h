/*
 * vk_mvk_moltenvk.h
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


/** Vulkan extension VK_MVK_moltenvk. */

#ifndef __vk_mvk_moltenvk_h_
#define __vk_mvk_moltenvk_h_ 1

#ifdef __cplusplus
extern "C" {
#endif	//  __cplusplus
	
#include <MoltenVK/mvk_vulkan.h>

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <IOSurface/IOSurfaceRef.h>
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
#define MVK_VERSION_PATCH   27

#define MVK_MAKE_VERSION(major, minor, patch)    (((major) * 10000) + ((minor) * 100) + (patch))
#define MVK_VERSION     MVK_MAKE_VERSION(MVK_VERSION_MAJOR, MVK_VERSION_MINOR, MVK_VERSION_PATCH)


#define VK_MVK_MOLTENVK_SPEC_VERSION            11
#define VK_MVK_MOLTENVK_EXTENSION_NAME          "VK_MVK_moltenvk"

/**
 * MoltenVK configuration settings.
 *
 * To change the MoltenVK configuration settings, use the vkGetMoltenVKConfigurationMVK() and
 * vkSetMoltenVKConfigurationMVK() functions to retrieve, modify, and set a copy of this structure.
 *
 * To be active, some configuration settings must be set before a VkDevice is created.
 * See the description of the individual configuration structure members for more information.
 *
 * The initial value of several of these settings is deterined when MolttenVK is compiled by the
 * presence of a DEBUG build setting, By default the DEBUG build setting is present when MoltenVK
 * is compiled in Debug mode, and not present when compiled in Release mode. The initial values
 * of the other settings are determined by other build settings when MoltenVK is compiled.
 * See the description of the individual configuration structure members for more information.
 *
 * This structure may be extended as new features are added to MoltenVK. If you are linking to
 * an implementation of MoltenVK that was compiled from a different VK_MVK_MOLTENVK_SPEC_VERSION
 * than your app was, the size of this structure in your app may be larger or smaller than the
 * struct in MoltenVK. See the description of the vkGetMoltenVKConfigurationMVK() and
 * vkSetMoltenVKConfigurationMVK() functions for information about how to handle this.
 */
typedef struct {

	/**
	 * If enabled, debugging capabilities will be enabled, including logging shader code
	 * during runtime shader conversion.
	 *
	 * Initial value is true in the presence of the DEBUG build setting, and false otherwise.
	 */
    VkBool32 debugMode;

	/**
	 * If enabled, MSL vertex shader code created during runtime shader conversion will
	 * flip the Y-axis of each vertex, as the Vulkan Y-axis is the inverse of OpenGL.
	 * An alternate way to reverse the Y-axis is to employ a negative Y-axis value on
	 * the viewport, in which case this parameter can be disabled.
	 *
	 * Initial value is set by the MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y build setting
	 * when MoltenVK is compiled. By default the MVK_CONFIG_SHADER_CONVERSION_FLIP_VERTEX_Y
	 * build setting is set to true.
	 */
    VkBool32 shaderConversionFlipVertexY;

	/**
	 * If enabled, queue command submissions (vkQueueSubmit() & vkQueuePresentKHR()) will be
	 * processed on the thread that called the submission function. If disabled, processing
	 * will be dispatched to a GCD dispatch_queue whose priority is determined by
	 * VkDeviceQueueCreateInfo::pQueuePriorities during vkCreateDevice().
	 *
	 * Initial value is set by the MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS build setting when MoltenVK
	 * is compiled. By default the MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS build setting is set to false,
	 * and command processing will be handled on a prioritizable queue thread. Changing the value of
	 * this parameter must be done before creating a VkDevice, for the change to take effect.
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
	 * When enabling this features, be aware that one Metal command buffer is required for each Vulkan
	 * command buffer. Depending on the number of command buffers that you use, you may also need to
	 * change the value of the maxActiveMetalCommandBuffersPerQueue setting.
	 *
	 * In addition, if this feature is enabled, be aware that if you have recorded commands to a
	 * Vulkan command buffer, and then choose to reset that command buffer instead of submitting it,
	 * the corresponding prefilled Metal command buffer will still be submitted. This is because Metal
	 * command buffers do not support the concept of being reset after being filled. Depending on when
	 * and how often you do this, it may cause unexpected visual artifacts and unnecessary GPU load.
	 *
	 * Initial value is set by the MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS build setting when MoltenVK
	 * is compiled. By default the MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS build setting is set to false.
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
	 * Initial value is set by the MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_POOL build setting
	 * when MoltenVK is compiled. By default the MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_POOL
	 * build setting is set to 64. Changing the value of this parameter must be done before creating
	 * a VkDevice, for the change to take effect.
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
	 * Initial value is set by the MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS build setting
	 * when MoltenVK is compiled. By default the MVK_CONFIG_SUPPORT_LARGE_QUERY_POOLS
	 * build setting is set to true.
	 */
	VkBool32 supportLargeQueryPools;

	/**
	 * If enabled, each surface presentation is scheduled using a command buffer. Enabling this
	 * setting may improve rendering frame synchronization, but may result in reduced frame rates.
	 *
	 * Initial value is set by the MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER build setting when MoltenVK
	 * is compiled. By default the MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER build setting is set to true.
	 */
	VkBool32 presentWithCommandBuffer;

	/**
	 * If enabled, swapchain images will use simple Nearest sampling when magnifying the
	 * swapchain image to fit a physical display surface. If disabled, swapchain images will
	 * use Linear sampling when magnifying the swapchain image to fit a physical display surface.
	 * Enabling this setting avoids smearing effects when swapchain images are simple interger
	 * multiples of display pixels (eg- macOS Retina, and typical of graphics apps and games),
	 * but may cause aliasing effects when using non-integer display scaling.
	 *
	 * Initial value is set by the MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST build setting
	 * when MoltenVK is compiled. By default the MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST
	 * build setting is set to true.
	 */
	VkBool32 swapchainMagFilterUseNearest;

	/**
	 * The maximum amount of time, in nanoseconds, to wait for a Metal library, function, or
	 * pipeline state object to be compiled and created by the Metal compiler. An internal error
	 * within the Metal compiler can stall the thread for up to 30 seconds. Setting this value
	 * limits that delay to a specified amount of time, allowing shader compilations to fail fast.
	 *
	 * Initial value is set by the MVK_CONFIG_METAL_COMPILE_TIMEOUT build setting when MoltenVK
	 * is compiled. By default the MVK_CONFIG_METAL_COMPILE_TIMEOUT build setting is infinite.
	 */
	uint64_t metalCompileTimeout;

	/**
	 * If enabled, per-frame performance statistics are tracked, optionally logged, and can be
	 * retrieved via the vkGetSwapchainPerformanceMVK() function, and various performance statistics
	 * are tracked, logged, and can be retrieved via the vkGetPerformanceStatisticsMVK() function.
	 *
	 * Initial value is true in the presence of the DEBUG build setting, and false otherwise.
	 */
	VkBool32 performanceTracking;

	/**
	 * If non-zero, performance statistics will be periodically logged to the console, on a repeating
	 * cycle of this many frames per swapchain. The performanceTracking capability must also be enabled.
	 *
	 * Initial value is 300 in the presence of the DEBUG build setting, and zero otherwise.
	 */
	uint32_t performanceLoggingFrameCount;

	/**
	 * If enabled, a MoltenVK logo watermark will be rendered on top of the scene.
	 * This can be enabled for publicity during demos.
	 *
	 * Initial value is set by the MVK_CONFIG_DISPLAY_WATERMARK build setting when MoltenVK
	 * is compiled. By default the MVK_CONFIG_DISPLAY_WATERMARK build setting is set to false.
	 */
	VkBool32 displayWatermark;

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
 */
typedef struct {
    uint32_t mslVersion;                        /**< The version of the Metal Shading Language available on this device. The format of the integer is MMmmpp, with two decimal digts each for Major, minor, and patch version values (eg. MSL 1.2 would appear as 010200). */
	VkBool32 indirectDrawing;                   /**< If true, draw calls support parameters held in a GPU buffer. */
	VkBool32 baseVertexInstanceDrawing;         /**< If true, draw calls support specifiying the base vertex and instance. */
    VkBool32 dynamicMTLBuffers;                 /**< If true, dynamic MTLBuffers for setting vertex, fragment, and compute bytes are supported. */
    VkBool32 shaderSpecialization;              /**< If true, shader specialization (aka Metal function constants) is supported. */
    VkBool32 ioSurfaces;                        /**< If true, VkImages can be underlaid by IOSurfaces via the vkUseIOSurfaceMVK() function, to support inter-process image transfers. */
    VkBool32 texelBuffers;                      /**< If true, texel buffers are supported, allowing the contents of a buffer to be interpreted as an image via a VkBufferView. */
	VkBool32 layeredRendering;                  /**< If true, layered rendering to multiple cube or texture array layers is supported. */
	VkBool32 presentModeImmediate;              /**< If true, immediate surface present mode (VK_PRESENT_MODE_IMMEDIATE_KHR), allowing a swapchain image to be presented immediately, without waiting for the vertical sync period of the display, is supported. */
	VkBool32 stencilViews;                      /**< If true, stencil aspect views are supported through the MTLPixelFormatX24_Stencil8 and MTLPixelFormatX32_Stencil8 formats. */
	uint32_t maxTextureDimension; 	     	  	/**< The maximum size of each texture dimension (width, height, or depth). */
	uint32_t maxPerStageBufferCount;            /**< The total number of per-stage Metal buffers available for shader uniform content and attributes. */
    uint32_t maxPerStageTextureCount;           /**< The total number of per-stage Metal textures available for shader uniform content. */
    uint32_t maxPerStageSamplerCount;           /**< The total number of per-stage Metal samplers available for shader uniform content. */
    VkDeviceSize maxMTLBufferSize;              /**< The max size of a MTLBuffer (in bytes). */
    VkDeviceSize mtlBufferAlignment;            /**< The alignment used when allocating memory for MTLBuffers. Must be PoT. */
    VkDeviceSize maxQueryBufferSize;            /**< The maximum size of an occlusion query buffer (in bytes). */
	VkDeviceSize mtlCopyBufferAlignment;        /**< The alignment required during buffer copy operations (in bytes). */
    VkSampleCountFlags supportedSampleCounts;   /**< A bitmask identifying the sample counts supported by the device. */
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
} MVKShaderCompilationPerformance;


/** MoltenVK performance of pipeline cache activities. */
typedef struct {
	MVKPerformanceTracker sizePipelineCache;			/** Calculate the size of cache data required to write MSL to pipeline cache data stream. */
	MVKPerformanceTracker writePipelineCache;			/** Write MSL to pipeline cache data stream. */
	MVKPerformanceTracker readPipelineCache;			/** Read MSL from pipeline cache data stream. */
} MVKPipelineCachePerformance;

/** MoltenVK performance of queue activities. */
typedef struct {
	MVKPerformanceTracker mtlQueueAccess;          	/** Create an MTLCommmandQueue or access an existing cached instance. */
} MVKQueuePerformance;

/**
 * MoltenVK performance. You can retrieve a copy of this structure using the vkGetPerformanceStatisticsMVK() function.
 *
 * This structure may be extended as new features are added to MoltenVK. If you are linking to
 * an implementation of MoltenVK that was compiled from a different VK_MVK_MOLTENVK_SPEC_VERSION
 * than your app was, the size of this structure in your app may be larger or smaller than the
 * struct in MoltenVK. See the description of the vkGetPerformanceStatisticsMVK() function for
 * information about how to handle this.
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


#ifdef __OBJC__

/** Returns, in the pMTLDevice pointer, the MTLDevice used by the VkPhysicalDevice. */
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
 */
VKAPI_ATTR VkResult VKAPI_CALL vkSetMTLTextureMVK(
    VkImage                                     image,
    id<MTLTexture>                              mtlTexture);

/** Returns, in the pMTLTexture pointer, the MTLTexture currently underlaying the VkImage. */
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
 */
VKAPI_ATTR VkResult VKAPI_CALL vkUseIOSurfaceMVK(
    VkImage                                     image,
    IOSurfaceRef                                ioSurface);

/**
 * Returns, in the pIOSurface pointer, the IOSurface currently underlaying the VkImage,
 * as set by the useIOSurfaceMVK() function, or returns null if the VkImage is not using
 * an IOSurface, or if the platform does not support IOSurfaces.
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
