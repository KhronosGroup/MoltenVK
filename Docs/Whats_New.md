<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



#What's New in MoltenVK

Copyright (c) 2014-2018 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format.
For best results, use a Markdown reader.*



MoltenVK 1.0.18
---------------

Released 2018/08/15

- vkCmdFullBuffer() fills buffer using compute shader.
- Fix API for updating MVKDeviceConfiguration::synchronousQueueSubmits.
- vkGetPhysicalDeviceFormatProperties() return VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT 
  if supported, even if other format properties are not.
- Support Metal GPU capture scopes.
- Update to latest SPIRV-Cross, glslang & SPIRV-Tools.


MoltenVK 1.0.17
---------------

Released 2018/07/31

- Disable rasterization and return void from vertex shaders that write to resources.
- Add SPIRVToMSLConverterOptions::isRasterizationDisabled to allow pipeline and 
  vertex shader to communicate rasterization status.
- Track layered rendering capability.    
- Add MVKPhysicalDeviceMetalFeatures::layeredRendering.
- Add mvkStaticCmdShaderSource() to generate static MSL shader source for commands.
- Add MVKDevice::getMTLCompileOptions() to consolidate shader compilation options.
- CreatePipelines return error when fragment MSL translation fails.
- Add new vertex format VK_FORMAT_A2B10G10R10_SNORM_PACK32.
- Fix watermark timing.
- Update MoltenVK spec version to 6.
- Remove obsolete deprecated licensing functions.
- Rename folders and project for Cube demo.
- Update What's New document for earlier releases.
- Update to latest library dependencies.
- Update to latest SPIRV-Cross version.


MoltenVK 1.0.16
---------------

Released 2018/07/24

- Fixes to attachment and image clearing to pass CTS tests.
- MVKCmdClearAttachments support clearing multiple attachment layers.
- MVKCmdClearImage use renderpass clear, and support clearning multiple image layers.
- Rename mvkCmdClearImage() to mvkCmdClearColorImage().
- MVKDevice add getFormatIsSupported() to allow devices to test for format support.
- MVKFramebuffer support multiple layers.
- mvk_datatypes.h support both 2D and 3D mipmap calculations and allow
  mvkMTLPrimitiveTopologyClassFromVkPrimitiveTopology() in iOS.
- Remove support for VK_FORMAT_B10G11R11_UFLOAT_PACK32 & VK_FORMAT_E5B9G9R9_UFLOAT_PACK32
  since format components are reversed on Metal.
- Report correct workgroup sizes from MTLDevice.
- Retrieve VkPhysicalDeviceLimits::maxComputeWorkGroupSize &
  maxComputeWorkGroupInvocations & maxComputeSharedMemorySize from MTLDevice.
- Move OS extension source files to new OS directory.
- Update to latest SPIRV-Cross version.



MoltenVK 1.0.15
---------------

Released 2018/07/12

- Link IOSurface on iOS only if IPHONEOS_DEPLOYMENT_TARGET is at least iOS 11.0.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.14
---------------

Released 2018/07/04

- vkGetPhysicalDeviceImageFormatProperties() indicate 1D texture limitations.
- Fix compute shader workgroup size specialization.
- Support separate specialization for each workgroup dimension.
- Support zero as a specialization ID value.
- Set correct value for VkPhysicalDeviceLimits::maxPerStageDescriptorInputAttachments.
- Cleanup MoltenVKShaderConverterTool.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.13
---------------

Released 2018/06/28

- Support larger VkBufferViews by using 2D Metal textures.
- Swapchain return VK_ERROR_OUT_OF_DATE_KHR when window resized.
- Improve crispness of visuals on macOS Retina displays.
- Set CAMetalLayer magnificationFilter property to Nearest by default.
- Add MVKDeviceConfiguration::swapchainMagFilterUseNearest member to allow overrides.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.12
---------------

Released 2018/06/22

- Sorting Metal devices in the list of physicalDevices by whether they are headless.
- vkCmdBlitImage() support texture arrays as source and destination targets.
- vkCmdBlitImage() remove broken support for depth/stencil scaling.
- vkCmdClearImage() fixes to clearing depth and stencil formats and avoid Metal validation errors.
- Fix slice index when rendering to cube maps.
- Fix texture file copy in Cube Demo.
- fetchDeps: Add flags for pre-built repos.
- Update to latest library dependencies to match Vulkan SDK 1.1.77.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.11
---------------

Released 2018/06/12

- Avoid fragment shader tracking interacting with vertex attributes.
- Restrict allowed linear tiling features for pixel formats.
- Fix bad logic when testing allowed linear tiling usage.
- Fix copying 4-byte 32-bit depth/stencil formats between buffers and textures.
- Fix MSL compilation failures on macOS 10.14 Mojave Beta.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.10
---------------

Released 2018/06/05

- Support mapping and filling device memory before binding an image to it.
- Fix vsync not being enabled in IMMEDIATE present mode. MVK_MACOS was not being defined.
- Avoid Metal validation error on MTLBuffer.contents access from private storage.
- Support using Metal texel buffer for linear images to increase host coherency. 
- MVKDeviceMemory track MVKImages and MVKBuffers separately.
- Per Vulkan spec, restrict linear images to 2D, non-array, single mipmap.
- Use texel buffer if possible for texture on coherent device memory.
- Only flush MVKImages (not MVKBuffers) when device memory mapped.
- Do not flush texel buffer images.
- Replace dependency on Vulkan-LoaderAndValidationLayers with Vulkan-Headers and Vulkan-Tools. 
- Update to latest SPIRV-Cross.



MoltenVK 1.0.9
--------------

Released 2018/05/23

- Fix an issue where the depth format in MVKCmdClearImage was not getting set correctly.
- Move surface access to UI components to main thread.
- Fix deadlock possibility between MVKFence and MVKFenceSitter.
- Fix handling of locking on deferred-destruction objects.
- vkGetPhysicalDeviceImageFormatProperties returns VK_ERROR_FORMAT_NOT_SUPPORTED 
  if the format is not supported.
- Default value of MVKDeviceConfiguration::metalCompileTimeout set to infinite.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.8
--------------

Released 2018/05/18

- Allow queue processing to be optionally handled on the submitting (render) thread.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.7
--------------

Released 2018/05/14

- Cache MTLCommandQueues for reuse to handle long delays in creating new VkDevices and VkQueues.
- Handle multiple MVKResources mapped to the same region of a single MVKDeviceMemory.
- Add Metal library, function and pipeline compilation timeout limits.
- Create copies of MVKShaderLibraries when merging pipeline caches.
- Handle NULLs when freeing command buffers.
- Replace delete with call to destroy() for all MVK objects.
- Handle null pointers in vkDestroy...() functions.
- Set default value of MVKDeviceConfiguration::supportLargeQueryPools to true by default.
- Fixes to run Vulkan CTS without crashes.
- Remove mutex locks on MVKDescriptorPool.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.5
--------------

Released 2018/05/04

- Add features to support Vulkan CTS.
- Dynamically create frag shaders for clearning attachments and images.
- Dynamically create frag shaders for blitting scaled images.
- MVKGraphicsPipeline don't create MTLRenderPipelineState if vertex function conversion fails.
- MVKComputePipeline don't create MTLComputePipelineState if compute function conversion fails.
- Handle SPIRV-Cross errors thrown during SPIR-V parsing in compiler construction.
- Set undefined property limits to large, but not max, values to avoid casting issues in app.
- Mark multiDrawIndirect features as available.
- Support VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT.
- Separate categories from MVKOSExtensions.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.4
--------------

Released 2018/04/22

- Support depth clip mode only from MTLFeatureSet_iOS_GPUFamily2_v4 onwards.
- MVKCmdClearAttachments & MVKCmdClearImage support multisampled attachments and images.
- Don't use CAMetalLayer displaySyncEnabled property if it is not available.
- Update python brew install command.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.3
--------------

Released 2018/04/18

- Add support for VK_PRESENT_MODE_IMMEDIATE_KHR swapchain presentation mode.
- Round up row and layer byte counts when copying compressed images with sizes 
  that are not integer multiples of block size.
- Queue and device wait idle handled by internal fence instead of semaphore.
- vkCmdCopyBufferToImage() & vkCmdCopyImageToBuffer() support a VkBuffer
  that is bound to an offseted position in a VkDeviceMemory.
- MVKImage::getArrayLayers() reports only layer count and excludes depth.
- Add workaround for apps that use one semaphore for all swapchain images.
- Support deferred secondary signaling of semaphore & fence acquired while image is free.
- Update to latest cube.c version.
- Use ninja if available to build dependencies.
- Build the demos in Travis-CI.
- Update to latest V-LVL, glslang & SPIRV-Tools.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.2
--------------

Released 2018/04/02

- Add support for caching converted MSL shader code offline from pipeline cache
  via vkGetPipelineCacheData(), vkCreatePipelineCache() & vkMergePipelineCaches().
- Present using command buffer by default.
- Support SPIR-V containing multiple entry points.
- Add option for per-frame performance logging via un-commentable logging code.
- VkPhysicalDeviceProperties::pipelineCacheUUID value derived from MoltenVK 
  version and highest supported Metal feature set.
- vkCmdClearAttachments() don't attempt to clear non-existing depth & stencil attachments.
- Always clamp scissors to render area to avoid Metal validation error.
- Move fetchDependencies to top directory.
- Turn caching of Externals off in .travis.yml.
- Add instructions in README.md about building MoltenVK via the command line.
- Update to latest SPIRV-Cross.



MoltenVK 1.0.1
--------------

Released 2018/03/19

- Add support for Vulkan Loader and Validation Layer API version 5.
- Add support for LunarG Vulkan Loader ICD API.
- Add Vulkan Loader and Validation Layer ICD JSON file.
- Fix vkGetInstanceProcAddr to work with 1.1 loader.
- Use fetchDependencies script instead of submodules.
- Align versioning of external libraries with those used by LunarG SDK.
- Combine multiple VkCommandBuffers into a single MTLCommandBuffer.
- On command buffer submission, defer waiting on semaphores until just before 
  MTLCommandBuffer is committed.
- Retrieve heap size from MTLDevice on macOS and from free shared system memory on iOS.
- Allow color attachment on depth-only rendering.
- Allow color attachment when clearing depth only.
- Support DXT1 RGB texture compression.
- Support VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT on VkFormats that are not supported 
  as texture formats under Metal.
- Don't check if texture is coherent on macOS, since it never is.
- Setup push constants for compute shaders.
- Check if storage mode is not shared when checking if synchronize is needed.
- Log which GPU is attached to a VkDevice.
- Sort multiple GPU's to put higher-power GPU's at front of list.
- Populate VkPhysicalDeviceProperties vendorID, deviceID and pipelineCacheUUID.
- Ensure scissors fit inside renderpass area to avoid Metal validation assertions.
- Consolidate setting of viewport and scissors by pipeline and command.
- Make MVKBuffer::getMTLBuffer() thread-safe.
- Fix Metal validation error with a renderpass with no depth attachment.
- Use pipelineStatisticsQuery feature to determine whether pipeline stats are available.
- Modify MVKImageView to fix MTLTexture used for renderpasses.
- Fix vkBindImageMemory crash when multiple simultaneous threads are binding to 
  different offsets in the of the same VkDeviceMemory.
- Don't align push constant buffer.
- Fix vkCmdCopyBuffer when copying unaligned regions.
- Added workgroup size specialization constants
- Fix SPIRV-Cross OOM conditions with multiple consecutive two-vector OpVectorShuffles.
- Support non-square row-major matrix conversions.
- Fix vkCmdBlitImage between images of different sizes.
- Add ability to write SPIR-V to file for debugging purposes.
- Update ThirdPartyConfig.md to latest use of SPIRV-Cross testability.
- Fixes to compute workgroup sizes and barriers.
- Improved extraction of entry point name and workgroup size from SPIR-V.
- Consolidate to a single ThirdPartyConfig.md document.
- MSL enhancements to nested function use of globals.
- Support customizing MSL based on iOS or macOS platform.
- MSL threadgroup barrier memory scope only on iOS MSL 2.0.
- MVKBufferView add lock when creating MTLTexture.
- MVKDeviceMemory add lock when creating MTLBuffer during memory mapping.
- MVKMTLBufferAllocator does not need to be threadsafe.
- Cleanup syntax on other lock handling to add consistency.
- Consolidate timestamps and performance tracking.
- Derive vkCmdCopyBuffer() alignment requirement at runtime.
- Don't log error from vkGetPhysicalDeviceFormatProperties() if format not supported.
- Add printf-like macros to MVKLogImpl and mvkNotifyErrorWithText.
- Updates to dylib building process. Use clang instead of libtool.
- Allow MoltenVK to be installed and built without asciidoctor.
- Add CI support using Travis CI.
- Automatically install demo apps.
- Cube demo generate SPIR-V as part of demo project build.
- Disable watermark in debug builds.
- Add build and runtime OS and device requirements to documentation.
- Add Compliance and Contribution sections to README.md.
- Remove executable permissions from non-executable files.
- Update to latest SPRIV-Cross.
- Update copyright dates to 2018.



MoltenVK 1.0.0
--------------

Released 2018/02/26

Initial open-source release!

