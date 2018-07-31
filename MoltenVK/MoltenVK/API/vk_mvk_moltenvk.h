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
	
#include <vulkan/vulkan.h>

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
#define MVK_VERSION_PATCH   17

#define MVK_MAKE_VERSION(major, minor, patch)    (((major) * 10000) + ((minor) * 100) + (patch))
#define MVK_VERSION     MVK_MAKE_VERSION(MVK_VERSION_MAJOR, MVK_VERSION_MINOR, MVK_VERSION_PATCH)


#define VK_MVK_MOLTENVK_SPEC_VERSION            6
#define VK_MVK_MOLTENVK_EXTENSION_NAME			"VK_MVK_moltenvk"

/**
 * MoltenVK configuration settings.
 *
 * The default value of several of these settings is deterined at build time by the presence
 * of a DEBUG build setting, By default the DEBUG build setting is defined when MoltenVK is
 * compiled in Debug mode, and not defined when compiled in Release mode.
 */
typedef struct {
    VkBool32 debugMode;                     /**< If enabled, several debugging capabilities will be enabled. Shader code will be logged during Runtime Shader Conversion. Adjusts settings that might trigger Metal validation but are otherwise acceptable to Metal runtime. Improves support for Xcode GPU Frame Capture. Default value is true in the presence of the DEBUG build setting, and false otherwise. */
    VkBool32 shaderConversionFlipVertexY;   /**< If enabled, MSL vertex shader code created during Runtime Shader Conversion will flip the Y-axis of each vertex, as Vulkan coordinate system is inverse of OpenGL. Default is true. */
	VkBool32 synchronousQueueSubmits;       /**< If enabled, queue command submissions (vkQueueSubmit() & vkQueuePresentKHR()) will be processed on the thread that called the submission function. If disabled, processing will be dispatched to a GCD dispatch_queue whose priority is determined by VkDeviceQueueCreateInfo::pQueuePriorities during vkCreateDevice(). This setting affects how much command processing should be performed on the rendering thread, or offloaded to a secondary thread. Default value is false, and command processing will be handled on a prioritizable queue thread. */
    VkBool32 supportLargeQueryPools;        /**< Metal allows only 8192 occlusion queries per MTLBuffer. If enabled, MoltenVK allocates a MTLBuffer for each query pool, allowing each query pool to support 8192 queries, which may slow performance or cause unexpected behaviour if the query pool is not established prior to a Metal renderpass, or if the query pool is changed within a Metal renderpass. If disabled, one MTLBuffer will be shared by all query pools, which improves performance, but limits the total device queries to 8192. Default value is true. */
	VkBool32 presentWithCommandBuffer;      /**< If enabled, each surface presentation is scheduled using a command buffer. Enabling this setting may improve rendering frame synchronization, but may result in reduced frame rates. Default value is false if the MVK_PRESENT_WITHOUT_COMMAND_BUFFER build setting is defined when MoltenVK is compiled, and true otherwise. By default the MVK_PRESENT_WITHOUT_COMMAND_BUFFER build setting is not defined and the value of this setting is true. */
	VkBool32 swapchainMagFilterUseNearest;  /**< If enabled, swapchain images will use simple Nearest sampling when magnifying the swapchain image to fit a physical display surface. If disabled, swapchain images will use Linear sampling when magnifying the swapchain image to fit a physical display surface. Enabling this setting avoids smearing effects when swapchain images are simple interger multiples of display pixels (eg- macOS Retina, and typical of graphics apps and games), but may cause aliasing effects when using non-integer display scaling. Default value is true. */
    VkBool32 displayWatermark;              /**< If enabled, a MoltenVK logo watermark will be rendered on top of the scene. This can be enabled for publicity during demos. Default value is true if the MVK_DISPLAY_WATERMARK build setting is defined when MoltenVK is compiled, and false otherwise. By default the MVK_DISPLAY_WATERMARK build setting is not defined. */
    VkBool32 performanceTracking;           /**< If enabled, per-frame performance statistics are tracked, optionally logged, and can be retrieved via the vkGetSwapchainPerformanceMVK() function, and various performance statistics are tracked, logged, and can be retrieved via the vkGetPerformanceStatisticsMVK() function. Default value is true in the presence of the DEBUG build setting, and false otherwise. */
    uint32_t performanceLoggingFrameCount;  /**< If non-zero, performance statistics will be periodically logged to the console, on a repeating cycle of this many frames per swapchain. The performanceTracking capability must also be enabled. Default value is 300 in the presence of the DEBUG build setting, and zero otherwise. */
	uint64_t metalCompileTimeout;			/**< The maximum amount of time, in nanoseconds, to wait for a Metal library, function or pipeline state object to be compiled and created. If an internal error occurs with the Metal compiler, it can stall the thread for up to 30 seconds. Setting this value limits the delay to that amount of time. Default value is infinite. */
} MVKDeviceConfiguration;

/** Features provided by the current implementation of Metal on the current device. */
typedef struct {
    uint32_t mslVersion;                        /**< The version of the Metal Shading Language available on this device. The format of the integer is MMmmpp, with two decimal digts each for Major, minor, and patch version values (eg. MSL 1.2 would appear as 010200). */
	VkBool32 indirectDrawing;                   /**< If true, draw calls support parameters held in a GPU buffer. */
	VkBool32 baseVertexInstanceDrawing;         /**< If true, draw calls support specifiying the base vertex and instance. */
    VkBool32 dynamicMTLBuffers;                 /**< If true, dynamic MTLBuffers for setting vertex, fragment, and compute bytes are supported. */
    VkBool32 shaderSpecialization;              /**< If true, shader specialization (aka Metal function constants) is supported. */
    VkBool32 ioSurfaces;                        /**< If true, VkImages can be underlaid by IOSurfaces via the vkUseIOSurfaceMVK() function, to support inter-process image transfers. */
    VkBool32 texelBuffers;                      /**< If true, texel buffers are supported, allowing the contents of a buffer to be interpreted as an image via a VkBufferView. */
    VkBool32 depthClipMode;                     /**< If true, depth clipping and depth clamping per the VkGraphicsPipelineCreateInfo::VkPipelineRasterizationStateCreateInfo::depthClampEnable flag is supported. */
	VkBool32 layeredRendering;                  /**< If true, layered rendering to multiple cube or texture array layers is supported. */
	VkBool32 presentModeImmediate;              /**< If true, immediate surface present mode (VK_PRESENT_MODE_IMMEDIATE_KHR), allowing a swapchain image to be presented immediately, without waiting for the vertical sync period of the display, is supported. */
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

/** MoltenVK swapchain performance statistics. */
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

/** MoltenVK performance. */
typedef struct {
	MVKShaderCompilationPerformance shaderCompilation;	/** Shader compilations activities. */
	MVKPipelineCachePerformance pipelineCache;			/** Pipeline cache activities. */
	MVKQueuePerformance queue;          				/** Queue activities. */
} MVKPerformanceStatistics;


#pragma mark -
#pragma mark Function types

typedef void (VKAPI_PTR *PFN_vkGetMoltenVKDeviceConfigurationMVK)(VkDevice device, MVKDeviceConfiguration* pConfiguration);
typedef VkResult (VKAPI_PTR *PFN_vkSetMoltenVKDeviceConfigurationMVK)(VkDevice device, MVKDeviceConfiguration* pConfiguration);
typedef void (VKAPI_PTR *PFN_vkGetPhysicalDeviceMetalFeaturesMVK)(VkPhysicalDevice physicalDevice, MVKPhysicalDeviceMetalFeatures* pMetalFeatures);
typedef void (VKAPI_PTR *PFN_vkGetSwapchainPerformanceMVK)(VkDevice device, VkSwapchainKHR swapchain, MVKSwapchainPerformance* pSwapchainPerf);
typedef void (VKAPI_PTR *PFN_vkGetPerformanceStatisticsMVK)(VkDevice device, MVKPerformanceStatistics* pPerf);
typedef void (VKAPI_PTR *PFN_vkGetVersionStringsMVK)(char* pMoltenVersionStringBuffer, uint32_t moltenVersionStringBufferLength, char* pVulkanVersionStringBuffer, uint32_t vulkanVersionStringBufferLength);

#ifdef __OBJC__
typedef void (VKAPI_PTR *PFN_vkGetMTLDeviceMVK)(VkPhysicalDevice physicalDevice, id<MTLDevice>* pMTLDevice);
typedef VkResult (VKAPI_PTR *PFN_vkSetMTLTextureMVK)(VkImage image, id<MTLTexture> mtlTexture);
typedef void (VKAPI_PTR *PFN_vkGetMTLTextureMVK)(VkImage image, id<MTLTexture>* pMTLTexture);
typedef VkResult (VKAPI_PTR *PFN_vkUseIOSurfaceMVK)(VkImage image, IOSurfaceRef ioSurface);
typedef void (VKAPI_PTR *PFN_vkGetIOSurfaceMVK)(VkImage image, IOSurfaceRef* pIOSurface);
#endif // __OBJC__

#pragma mark Deprecated license functions
typedef VkResult (VKAPI_PTR *PFN_vkActivateMoltenVKLicenseMVK)(const char* licenseID, const char* licenseKey, VkBool32 acceptLicenseTermsAndConditions);
typedef VkResult (VKAPI_PTR *PFN_vkActivateMoltenVKLicensesMVK)();


#pragma mark -
#pragma mark Function prototypes

#ifndef VK_NO_PROTOTYPES

/** 
 * Populates the pConfiguration structure with the current MoltenVK configuration settings 
 * of the specified device. 
 *
 * To change a specific configuration value, call vkGetMoltenVKDeviceConfigurationMVK()
 * to retrieve the current configuration, make changes, and call 
 * vkSetMoltenVKDeviceConfigurationMVK() to update all of the values.
 */
VKAPI_ATTR void VKAPI_CALL vkGetMoltenVKDeviceConfigurationMVK(
    VkDevice                                    device,
    MVKDeviceConfiguration*                     pConfiguration);

/** 
 * Sets the MoltenVK configuration settings of the specified device to those found in the 
 * pConfiguration structure.
 *
 * To change a specific configuration value, call vkGetMoltenVKDeviceConfigurationMVK()
 * to retrieve the current configuration, make changes, and call
 * vkSetMoltenVKDeviceConfigurationMVK() to update all of the values.
 */
VKAPI_ATTR VkResult VKAPI_CALL vkSetMoltenVKDeviceConfigurationMVK(
    VkDevice                                    device,
    MVKDeviceConfiguration*                     pConfiguration);

/** 
 * Populates the pMetalFeatures structure with the Metal-specific features
 * supported by the specified physical device. 
 */
VKAPI_ATTR void VKAPI_CALL vkGetPhysicalDeviceMetalFeaturesMVK(
	VkPhysicalDevice                            physicalDevice,
	MVKPhysicalDeviceMetalFeatures*             pMetalFeatures);

/**
 * Populates the specified MVKSwapchainPerformance structure with
 * the current performance statistics for the specified swapchain.
 */
VKAPI_ATTR void VKAPI_CALL vkGetSwapchainPerformanceMVK(
    VkDevice                                    device,
    VkSwapchainKHR                              swapchain,
    MVKSwapchainPerformance*                    pSwapchainPerf);

/**
 * Populates the specified MVKPerformanceStatistics structure with
 * the current performance statistics for the specified device.
 */
VKAPI_ATTR void VKAPI_CALL vkGetPerformanceStatisticsMVK(
    VkDevice                                    device,
    MVKPerformanceStatistics*            		pPerf);

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
