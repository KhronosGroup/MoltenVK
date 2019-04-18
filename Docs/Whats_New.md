<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



#What's New in MoltenVK

Copyright (c) 2014-2019 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format.
For best results, use a Markdown reader.*



MoltenVK 1.0.35
---------------

Released TBD

- Don't use setVertexBytes() for passing tessellation vertex counts.
- Fix zero local threadgroup size in indirect tessellated rendering.
- `MoltenVKShaderConverter` tool: Add MSL version and platform command-line options.
- Allow building external dependency libraries in Debug mode.



MoltenVK 1.0.34
---------------

Released 2019-04-12

- Add support for tessellation.
- Add correct function entry point handling.
- Add support for `VK_KHR_get_surface_capabilities2` extension.
- Implement newer `VK_KHR_swapchain` extension functions.
- Support the `VK_EXT_host_query_reset` extension.
- Add support for tracking device features enabled during `vkCreateDevice()`.
- Handle surface loss due to window moved between screens or a window style change.
- Allow zero offset and stride combo in `VkVertexInputBindingDescription`.
- API: Add `MVKPhysicalDeviceMetalFeatures::depthSampleCompare`.
- Fix conditions under which functions return `VK_INCOMPLETE`.
- Fix potential memory leak on synchronous command buffer submission.
- Increase shader float constant accuracy beyond 6 digits of precision.
- `fetchDependencies`: Stop on first error.
- Clean up behaviour of sparse binding functions.
- Fix a possible race condition around `MVKMTLBufferAllocation`.
- Fix memory overrun if no vertex buffer found with same binding as a vertex attribute.
- Fix PVRTC texture content loading via memory mapping.
- Fix wrong offset for `vkCmdFillBuffer()` on `VK_WHOLE_SIZE`.
- Fixed crash within `MVKPushConstantsCommandEncoderState` when accessing absent
  graphics pipeline during a compute stage.
- Fixed crash when `MTLRenderPassDescriptor renderTargetWidth` & `renderTargetHeight`
  set on older devices.
- Renderpass width/height clamped to the `renderArea` includes `offset`, not just `extent`, 
  and are set only when layered rendering is supported on device.
- Set options properly on a buffer view's `MTLTextureDescriptor`.
- Don't set `MTLSamplerDescriptor.compareFunction` on devices that don't support it.
- Disable the `shaderStorageImageArrayDynamicIndexing` feature on iOS.
- Debug build mode includes `dSYM` file for each `dylib` file.
- Explicitly build dSYM files in `BUILT_PRODUCTS_DIR` to avoid conflict between 
  macOS and iOS build locations.
- `Makefile` supports `install` target to install `MoltenVK.framework`.
  into `/Library/Frameworks/`.
- Add `MVK_CONFIG_TRACE_VULKAN_CALLS` env var and build setting to log Vulkan calls made by application.
- Log shader performance statistics in any runtime if `MVKConfiguration::performanceLoggingFrameCount` non-zero.
- Suppress visibility warning spam when building Debug macOS from SPIRV-Cross Release build.
- Support Xcode 10.2.
- Update `VK_MVK_MOLTENVK_SPEC_VERSION` to 19.
- MoltenVKShaderConverter tool:
	- Support `cs` & `csh` for compute shader file extensions.
	- Validate converted MSL with a test compilation.
	- Add option to log shader conversion performance.
- Update to latest SPIRV-Cross version:
	- MSL: Add support for Metal 2 indirect argument buffers.
	- MSL: Add support for tessellation control & evaluation shaders.
	- MSL: Support `VK_KHR_push_descriptor`.
	- MSL: Force unnamed array builtin attributes to have a name.
	- MSL: Set location of builtins based on client input.
	- MSL: Ignore duplicate builtin vertex attributes.
	- MSL: Fix crash where variable storage buffer pointers are passed down.
	- MSL: Fix infinite CAS loop on atomic_compare_exchange_weak_explicit().
	- MSL: Fix `depth2d` 4-component fixup.
	- MSL: Expand quad `gl_TessCoord` to a float3.
	- MSL: Fix depth textures which are sampled and compared against.
	- MSL: Emit proper name for optimized UBO/SSBO arrays.
	- MSL: Support emit two layers of address space.
	- MSL: Declare `gl_WorkGroupSize` constant with `[[maybe_unused]]`.
	- MSL: Fix OpLoad of array which is forced to a temporary.
	- Add stable C API and ABI.
	- Performance improvements & reduce pressure on global allocation.
	- Fix case where a struct is loaded which contains a row-major matrix.
	- Fix edge case where opaque types can be declared on stack.
	- Ensure locale handling is safe for multi-threading.
	- Add support for sanitizing address and threads.
	- Add support for `SPV_NV_ray_tracing`.
	- Support -1 index in `OpVectorShuffle`.
	- Deal more flexibly with for-loop & while-loop variations.
	- Detect invalid DoWhileLoop early.
	- Force complex loop in certain rare access chain scenarios.
	- Make locale handling threadsafe.
	- Support do-while where test is negative.
	- Emit loop header variables even for while and dowhile.
	- Properly deal with sign-dependent GLSL opcodes.
	- Deal with mismatched signs in S/U/F conversion opcodes.
	- Rewrite how we deal with locales and decimal point.
	- Fix crash when `backend.int16_t_literal_suffix` set to null.
	- Introduce customizable SPIRV-Cross namespaces and use `MVK_spirv_cross` in MoltenVK.



MoltenVK 1.0.33
---------------

Released 2019/02/28

- Support the `VK_EXT_memory_budget` extension.
- Support  8-bit part of `VK_KHR_shader_float16_int8`.
- Disable the `shaderStorageImageMultisample` feature.
- Modify README.md to direct developers to Vulkan SDK.
- Clarify Xcode version requirements in documentation.
- Use the `MTLDevice registryID` property to locate the GPU in `IOKit`.
- Add GPU device ID for *iOS A12* SoC.
- Allow logging level to be controlled with `MVK_CONFIG_LOG_LEVEL` 
  runtime environment variable.
- Allow forcing use of low-power GPU using `MVK_CONFIG_FORCE_LOW_POWER_GPU` 
  runtime environment variable.
  Set MSL version for shader compiling from Metal feature set.
- Don't warn on identity swizzles when `fullImageViewSwizzle` config setting is enabled.
- Track version of spvAux buffer struct in SPIRV-Cross and fail build if different
  than version expected by MoltenVK.
- Add static and dynamic libraries to MoltenVKShaderConverter project.
- Fix crash from use of MTLDevice registryID on early OS versions.
- `fetchDependencies`: Fix issue loading from `Vulkan-Portability_repo_revision`.
- `fetchDependencies`: Clean MoltenVK build to ensure using latest dependency libs.
- Update `VK_MVK_MOLTENVK_SPEC_VERSION` to 18.
- Update to latest dependency libraries to support SDK 1.1.101.
- Update to latest SPIRV-Cross version:
	- MSL: Implement 8-bit part of `VK_KHR_shader_float16_int8`.
	- MSL: Add a setting to capture vertex shader output to a buffer.
	- MSL: Stop passing the aux buffer around.
	- Support LUTs in single-function CFGs on Private storage class.



MoltenVK 1.0.32
---------------

Released 2019/01/28

- Add support for `VK_EXTX_portability_subset` extension.
- iOS: Support dual-source blending with iOS 11.
- iOS: Support cube arrays with A11. 
- iOS: Support layered rendering and multiple viewports with A12.
- Use combined store-resolve ops when supported and requested in renderpass.
- Fixes to values returned from `vkGetPhysicalDeviceImageFormatProperties()` 
  and `vkGetPhysicalDeviceImageFormatProperties2KHR()`.
- Log and return `VK_ERROR_FEATURE_NOT_PRESENT` error if `vkCreateImageView()` 
  requires shader swizzling but it is not enabled.
- Log and return `VK_ERROR_FEATURE_NOT_PRESENT` error if array of textures or 
  array of samplers requested but not supported.
- Treat all attributes & resources as used by shader when using pre-converted MSL.
- Allow default GPU Capture scope to be assigned to any queue in any queue family.
- VkPhysicalDevice: Correct some features and limits.
- Stop advertising atomic image support.
- vkSetMTLTextureMVK() function retains texture object.
- Log to stderr instead of stdout.
- `fetchDependencies`: build `spirv-tools` when attached via symlink.
- Enhancements to `MVKVector`, and set appropriate inline sizing usages.
- Update `VK_MVK_MOLTENVK_SPEC_VERSION` to 17.
- Update to latest SPIRV-Cross version:
	- MSL: Use correct size and alignment rules for structs.
	- MSL: Fix texture projection with Dref.
	- MSL: Deal with resource name aliasing.



MoltenVK 1.0.31
---------------

Released 2019/01/17

- Support runtime config via runtime environment variables
- Add full ImageView swizzling to config, and disable it by default.
- Add GPU switching to config, and enable it by default.
- Add queue family specialization to config, and disable it by default.
- Enable synchronous queue submits as config default.
- Support 4 queue families.
- Pad fragment shader output to 4 components when needed.
- Add support for copying to and from PVRTC images.
- Log Vulkan versions in human readable form when reporting version error.
- Update `VK_MVK_MOLTENVK_SPEC_VERSION` to 16.
- Update copyright to 2019.
- Advertise the `VK_AMD_gpu_shader_half_float` extension.
- Support the `VK_KHR_variable_pointers` extension.
- MoltenVKShaderConverter tool exit with fail code on any file conversion fail.
- Update to latest dependency libraries for Vulkan SDK 1.1.97.
- Update to latest SPIRV-Cross version:
	- MSL: Support SPV_KHR_variable_pointers.
	- MSL: Workaround missing gradient2d() on macOS for typical cascaded shadow mapping.
	- MSL: Fix mapping of identity-swizzled components.
	- MSL: Support composites inside I/O blocks.
	- MSL: Fix case where we pass arrays to functions by value.
	- MSL: Add option to pad fragment outputs.
	- MSL: Fix passing a sampled image to a function.
	- MSL: Support std140 packing rules for float[] and float2[].
	- MSL: Fix image load/store for short vectors.
	- Performance improvements on iterating internal constructs.
	- Update copyright to 2019.



MoltenVK 1.0.30
---------------

Released 2018/12/31

- Allow 2 or 3 swapchain images to support both double and triple buffering.
- Force display to switch to GPU selected by vkCreateDevice() to avoid system 
  view compositor having to copy from that GPU to display GPU.
- Use inline buffer for pipeline auxiliary buffer.
- vkCmdCopyImage: Cast source image to the destination format.
- Result of vkGetPhysicalDeviceFormatProperties2KHR match vkGetPhysicalDeviceFormatProperties.
- MVKImage: Return error for BLOCK_TEXEL_VIEW.
- MVKDescriptorSet: Fix handling of immutable samplers.
- MVKPipeline: Forbid vertex attribute offsets >= stride.
- Fix handling of case where vertex bindings and binding indices don't match up.
- Return VK_TIMEOUT even on zero wait if fences not signalled.
- Support iOS builds for arm64e architecture.
- Improvements to building external libraries.
- Print Vulkan semantics when logging converted GLSL.
- Support uploading S3TC-compressed 3D images.



MoltenVK 1.0.29
---------------

Released 2018/12/15

- Replace use of std::vector with MVKVector to support allocations on stack.
- Add missing include MVKEnvironment.h to MVKImage.mm for IOSurfaces.
- vkCmdClearAttachments apply [[render_target_array_index]] more carefully.
- vkCmdPushDescriptorSet: Fix mapping of binding numbers to descriptor layouts.
- Forbid depth/stencil formats on anything but 2D images.
- MVKCommandPool: Destroy transfer images using the device.
- MVKPipeline: Reject non-multiple-of-4 vertex buffer strides.
- MVKPipeline: Set auxiliary buffer offsets once, on layout creation.
- MVKSampler: Support border colors.
- MVKImage: Round up byte alignment to the nearest power of 2.
- MVKImage: Don't set MTLTextureUsageRenderTarget for non-blittable formats.
- MVKImage: Support image views of 2D multisample array images.
- MVKGraphicsPipeline: Add dummy attachments even when rasterization is off.
- MVKDeviceMemory: Try creating an MTLBuffer before allocating heap memory.
- Add support for VK_FORMAT_A2R10G10B10_UNORM_PACK32.
- Support A8B8G8R8_PACK32 formats.
- Add new formats and fix existing ones.
- On macOS, VK_FORMAT_E5B9G9R9_UFLOAT_PACK32 can only be filtered.
- On macOS, linear textures cannot be blitted to.
- Depth formats cannot be used for a VkBufferView.
- Give every image format we support the BLIT_SRC feature.
- Correct supported features of compressed formats.
- Correct mapping of packed 16-bit formats.
- Add some more vertex formats.
- Don't use char/uchar for clearing/copying 8-bit formats.
- Explicitly set number of sparse image property/requirement info sets to 0.
- Retrieve linear image memory alignment requirements from Metal device.
- For each GPU, log MSL version and updated list of feature sets.
- Cube demo on iOS support Portrait and Landscape device orientation.
- Build the dylib with -fsanitize=address when asan is enabled.
- Fix name of generated dSYM file.
- Update to latest SPIRV-Cross version:
	- MSL don't emit `memory_scope` after MSL 2.0.


MoltenVK 1.0.28
---------------

Released 2018/12/06

- Add support for extensions:
	- VK_KHR_bind_memory2
	- VK_KHR_swapchain_mutable_format
	- VK_KHR_shader_float16_int8
	- VK_KHR_8bit_storage
	- VK_KHR_16bit_storage
	- VK_KHR_relaxed_block_layout
	- VK_KHR_maintenance3
	- VK_KHR_storage_buffer_storage_class
- Add support for 2D multisample array textures.
- Ignore fragment shader if raster discard is enabled.
- Force signedness of shader vertex attributes to match the host.
- In debug configurations, create a dSYM bundle for libMoltenVK.dylib.
- MVKImage: Take lock when setting the MTLTexture manually.
- Optimize MVKFenceSitter.
- Support parallel builds of fetchDependencies to improve build times.
- Change internal header references to increase header path flexibility.
- Update to latest SPIRV-Cross version:
	- MSL: Use an enum instead of two mutually exclusive booleans.
	- MSL: Force signedness of shader vertex attributes to match the host.
	- Support gl_HelperInvocation on GLSL and MSL.


MoltenVK 1.0.27
---------------

Released 2018/11/15

- Remove destroyed resources from descriptor sets.
- Forbid compressed formats on non-2D images.
- Update to latest dependency libraries for Vulkan SDK 1.1.92.
- Update to latest SPIRV-Cross version:
	- MSL: Print early_fragment_tests specifier before fragment shader declaration.
	- MSL: Also pack members at unaligned offsets.
	- MSL: Also pack 2- and 4- element vectors when necessary.
	- MSL: Emit wrapper for SSign (sign() for int types).
	- MSL: Support extended arithmetic opcodes.
	- Handle opcode OpSourceContinued.
	- Handle group decorations.


MoltenVK 1.0.26
---------------

Released 2018/11/06

- Fix memoryTypes order to match Vulkan spec.
- Allow linear images to use host-coherent memory.
- Generate Bitcode in iOS libraries.
- Allow all pipeline attachements to be unused.
- Perform usage checks on 3D images.
- Enhancements to dylib generation script.
- Update to latest SPIRV-Cross version:
	- MSL: Support 8 & 16 bit types.
	- MSL: Updated spec constant support.


MoltenVK 1.0.25
---------------

Released 2018/10/31

- Refactor the build environment.
	- Support creation of static library and build framework and dynamic library from it.
	- Add Makefile to better support command line or script building integration.
	- Update demos to each use one of framework, static library, and dynamic library.
	- Refactor and rename the build scripts.
	- Refactor and rename the Xcode Schemes.
	- Update build and runtime documentation.
- Update shader caching for compatibility with texture swizzling.
- Support polygonMode VK_POLYGON_MODE_POINT.
- vkCreateInstance returns VK_ERROR_INCOMPATIBLE_DRIVER if Metal not available.


MoltenVK 1.0.24
---------------

Released 2018/10/16

- Support arbitrary swizzles of image data.
- Include struct size parameter in VK_MVK_moltenvk extension functions that pass structs that 
  might change size across extension versions.
- Remove vkGetMoltenVKDeviceConfigurationMVK() & vkSetMoltenVKDeviceConfigurationMVK() functions.
- Allocate MVKDescriptorSets from a pool within MVKDescriptorPool
- Support copying between textures of compatible-sized formats
- Support VK_FORMAT_A2B10G10R10_UNORM_PACKED vertex format
- Build scripts support SRCROOT path containing spaces.


MoltenVK 1.0.23
---------------

Released 2018/09/28

- Add support for features:
	- shaderStorageImageMultisample
	- shaderStorageImageReadWithoutFormat
	- shaderStorageImageWriteWithoutFormat
	- shaderUniformBufferArrayDynamicIndexing
	- shaderSampledImageArrayDynamicIndexing
	- shaderStorageBufferArrayDynamicIndexing
	- shaderStorageImageArrayDynamicIndexing
- Support reduced render area
- Support rasterization to missing attachment
- Allocate MVKCommandBuffers from a pool within MVKCommandPool.
- Update glslang version
- Update to latest SPIRV-Cross version:
	- MSL: Improve coordinate handling for buffer reads.
	- MSL: Expand arrays of buffers passed as input.


MoltenVK 1.0.22
---------------

Released 2018/09/25

- Add support for extensions:
	- VK_KHR_maintenance2
    - VK_EXT_vertex_attribute_divisor
    - VK_KHR_sampler_mirror_clamp_to_edge
    - VK_KHR_image_format_list
    - VK_KHR_dedicated_allocation
    - VK_KHR_get_memory_requirements2
    - VK_EXT_shader_viewport_index_layer
- Support multiple viewports and scissor rectangles.
- Support sampleRateShading.
- Support pre-filling Metal command buffer on same thread as Vulkan command buffer.
- Support passing either a CAMetalLayer or an NSView/UIView in the pView member 
  when creating a surface.
- Support views of the stencil aspect of depth/stencil images.
- Improvements to subviews on 3D textures.
- Enforce single queue per queue family to improve Metal command buffer handling.
- Set Metal render target sizes on iOS.
- Fix potential deadlocks on query results and fences.
- Fix memory leak on SPIRV conversion.
- Update to Vulkan header 1.1.85 and latest version of library dependencies.
- Update to latest SPIRV-Cross version:
	- MSL: Handle the ViewportIndex builtin.
	- MSL: Handle the SamplePosition builtin.
	- MSL: Fix OpAtomicIIncrement and OpAtomicIDecrement.
	- MSL: Support array of arrays composites and copying.
	- MSL: Fix issues with casting of builtin integer vectors.


MoltenVK 1.0.21
---------------

Released 2018/09/08

- Add support for extensions:
    - VK_KHR_descriptor_update_template
- Create 3D MTLTextureViews for 2D image views of 3D textures.
- Allow building and packaging MoltenVK for of only iOS or only macOS.
- Move packaging scripts out of Xcode projects and into script files.
- vkUpdateDescriptorSet: Handle copies of uninitialized descriptors.
- vkCmdFillBuffer & vkCmdCopyBuffers: Use dispatch call that supports older OS versions.
- Update to latest SPIRV-Cross version:
	- MSL: Emit F{Min,Max,Clamp} as fast:: and N{Min,Max,Clamp} as precise
	- MSL: Implement multisampled array textures.
	- MSL: Emit spvTexelBufferCoord() on ImageWrite to a Buffer.
	- MSL: Handle interpolation qualifiers.
	- MSL: Account for components when assigning locations to varyings.
	- MSL: Do not emit function constants for version < 1.2.


MoltenVK 1.0.20
---------------

Released 2018/09/01

- Add support for extensions:
    - VK_KHR_maintenance1
	- VK_KHR_shader_draw_parameters
	- VK_KHR_get_physical_device_properties2
	- VK_KHR_push_descriptor
- Add ability to track and access supported and enabled extensions.
- Update to latest SPIRV-Cross version.


MoltenVK 1.0.19
---------------

Released 2018/08/23

- Move MoltenVK config to instance instead of device.
- Add MVKConfiguration and deprecate MVKDeviceConfiguration.
- Add vkGetMoltenVKConfigurationMVK() and deprecate vkGetMoltenVKDeviceConfigurationMVK().
- Add vkSetMoltenVKConfigurationMVK() and deprecate vkSetMoltenVKDeviceConfigurationMVK().
- Add build setting overrides for all initial MVKConfiguration member values.
- Support Xcode 10: Explicitly specify MoltenVKSPIRVToMSLConverter as prelink library.
- Update to Vulkan header 1.1.83 and latest version of library dependencies.


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
- Update to latest SPIRV-Cross.
- Update copyright dates to 2018.



MoltenVK 1.0.0
--------------

Released 2018/02/26

Initial open-source release!

