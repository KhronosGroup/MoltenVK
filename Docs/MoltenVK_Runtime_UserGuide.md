<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



MoltenVK Runtime User Guide
===========================

Copyright (c) 2015-2020 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format.
For best results, use a Markdown reader.*



Table of Contents
-----------------

- [About This Document](#about_this)
- [About **MoltenVK**](#about_moltenvk)
- [Installing **MoltenVK** in Your *Vulkan* Application](#install)
	- [Build and Runtime Requirements](#requirements)
	- [Install as Static Framework, Static Library, or Dynamic Library](#install_lib)
- [Interacting with the **MoltenVK** Runtime](#interaction)
	- [MoltenVK `VK_MVK_moltenvk` Extension](#moltenvk_extension)
	- [Configuring MoltenVK](#moltenvk_config)
- [*Metal Shading Language* Shaders](#shaders)
	- [MoltenVKShaderConverter Shader Converter Tool](#shader_converter_tool)
	- [Troubleshooting Shader Conversion](#spv_vs_msl)
- [Performance Considerations](#performance)
	- [Shader Loading Time](#shader_load_time)
	- [Swapchains](#swapchains)
	- [Xcode Configuration](#xcode_config)
	- [Metal System Trace Tool](#trace_tool)
- [Known **MoltenVK** Limitations](#limitations)



<a name="about_this"></a>
About This Document
-------------------

This document describes how to integrate the **MoltenVK** runtime distribution package into a game or
application, once **MoltenVK** has been built into a framework or library for *macOS*, *iOS*, or *tvOS*.

To learn how to use the **MoltenVK** open-source repository to build a **MoltenVK** runtime 
distribution package, see the main [`README.md`](../README.md) document in the `MoltenVK` repository.



<a name="about_moltenvk"></a>
About **MoltenVK**
------------------

**MoltenVK** is a layered implementation of [*Vulkan 1.1*](https://www.khronos.org/vulkan) 
graphics and compute functionality, that is built on Apple's [*Metal*](https://developer.apple.com/metal) 
graphics and compute framework on *macOS*, *iOS*, and *tvOS*. **MoltenVK** allows you to use *Vulkan* 
graphics and compute functionality to develop modern, cross-platform, high-performance graphical games 
and applications, and to run them across many platforms, including *macOS*, *iOS*, and *tvOS*.

*Metal* uses a different shading language, the *Metal Shading Language (MSL)*, than 
*Vulkan*, which uses *SPIR-V*. **MoltenVK** automatically converts your *SPIR-V* shaders 
to their *MSL* equivalents. This can be performed transparently at run time, using the 
**Runtime Shader Conversion** feature of **MoltenVK**, or at development time using the 
[**MoltenVKShaderConverter**](#shader_converter_tool) tool provided with this **MoltenVK** 
distribution package.

To provide *Vulkan* capability to the*macOS*, *iOS*, and *tvOS* platforms, **MoltenVK** uses 
*Apple's* publicly available API's, including *Metal*. **MoltenVK** does **_not_** use any 
private or undocumented API calls or features, so your app will be compatible with all 
standard distribution channels, including *Apple's App Store*.


<a name="install"></a>
Installing **MoltenVK** in Your *Vulkan* Application
----------------------------------------------------

<a name="requirements"></a>
### Build and Runtime Requirements

**MoltenVK** references the latest *Apple SDK* frameworks. To access these frameworks when building
your app, and to avoid build errors, be sure to use the latest publicly available version of *Xcode*.

>***Note:*** To support `IOSurfaces` on *iOS* or *tvOS*, any app that uses **MoltenVK** must be 
built with a minimum **iOS Deployment Target** (aka `IPHONEOS_DEPLOYMENT_TARGET `) build setting 
of `iOS 11.0` or greater, or a minimum **tvOS Deployment Target** (aka `TVOS_DEPLOYMENT_TARGET `)
build setting of `tvOS 11.0` or greater.

Once built, your app integrating the **MoltenVK** libraries can be run on *macOS*, *iOS* or *tvOS* 
devices that support *Metal*, or on the *Xcode* *iOS Simulator* or *tvOS Simulator*.

- At runtime, **MoltenVK** requires at least *macOS 10.11*, *iOS 9*, or *tvOS 9* 
  (or *iOS 11* or *tvOS 11* if using `IOSurfaces`).
- Information on *macOS* devices that are compatible with *Metal* can be found in 
  [this article](http://www.idownloadblog.com/2015/06/22/how-to-find-mac-el-capitan-metal-compatible).
- Information on *iOS* devices that are compatible with *Metal* can be found in 
  [this article](https://developer.apple.com/library/content/documentation/DeviceInformation/Reference/iOSDeviceCompatibility/HardwareGPUInformation/HardwareGPUInformation.html).



<a name="install_lib"></a>
### Install as Static Framework, Static Library, or Dynamic Library

Installation of **MoltenVK** is straightforward and easy!

Depending on your build and deployment needs, you can install **MoltenVK** as a *static framework*,
*static library*, or *dynamic library*, by following the steps in this section. If you are unsure 
about which linking and deployment option you need, follow the steps for installing a 
*static framework*, as it is the simplest to install.
  
>**_Note:_** Distributing an app containing a dynamic library via the *iOS App Store* or 
 *tvOS App Store* can require specialized bundling. Unless you have specific needs for 
 dynamic libraries, the recommended approach on *iOS* or *tvOS* is to link **MoltenVK** 
 to your app as a static library or framework.
 

1. Open your application in *Xcode* and select your application's target in the 
   *Project Navigator* panel.


2. Open the *Build Settings* tab.

	- If installing **MoltenVK** as a *static framework* in your application:
	    1. In the **Framework Search Paths** (aka `FRAMEWORK_SEARCH_PATHS`) 
	       setting, add an entry that points to **_one_** of the following folders:
	          - `MoltenVK/macOS/framework` *(macOS)*
	          - `MoltenVK/iOS/framework` *(iOS)*
	          - `MoltenVK/tvOS/framework` *(tvOS)*

	- If installing **MoltenVK** as a *static library* in your application:
	    1. In the **Library Search Paths** (aka `LIBRARY_SEARCH_PATHS`) setting, 
	       add an entry that points to **_one_** of the following folders:
	          - `MoltenVK/macOS/static` *(macOS)*
	          - `MoltenVK/iOS/static` *(iOS)*
	          - `MoltenVK/tvOS/static` *(tvOS)*
	          
        2. In the **Header Search Paths** (aka `HEADER_SEARCH_PATHS`) setting, 
           add an entry that points to the `MoltenVK/include` folder.

	- If installing **MoltenVK** as a *dynamic library* in your application:
	    1. In the **Library Search Paths** (aka `LIBRARY_SEARCH_PATHS`) setting, 
	       add an entry that points to **_one_** of the following folders:
	          - `MoltenVK/macOS/dynamic` *(macOS)*
	          - `MoltenVK/iOS/dynamic` *(iOS)*
	          - `MoltenVK/tvOS/dynamic` *(tvOS)*
	          
        2. In the **Header Search Paths** (aka `HEADER_SEARCH_PATHS`) setting, 
           add an entry that points to the `MoltenVK/include` folder.
        3. In the **Runpath Search Paths** (aka `LD_RUNPATH_SEARCH_PATHS`) setting, 
           add an entry that matches where the dynamic library will be located in your runtime
           environment. If the dynamic library is to be embedded within your application, 
           you would typically set this value to either:

           - `@executable_path/../Frameworks` *(macOS)*
           - `@executable_path/Frameworks` *(iOS or tvOS)*
           
           The `libMoltenVK.dylib` library is internally configured to be located at 
           `@rpath/libMoltenVK.dylib`.

3. With the *Build Settings* tab open, if using `IOSurfaces` on *iOS*, open the **iOS Deployment Target** 
   (aka `IPHONEOS_DEPLOYMENT_TARGET`) setting, and ensure it is set to a value of `iOS 11.0` or greater, 
   or if using `IOSurfaces` on *tvOS*, open the **tvOS Deployment Target** (aka `TVOS_DEPLOYMENT_TARGET`)
   setting, and ensure it is set to a value of `tvOS 11.0` or greater.

4. On the *Build Phases* tab, open the *Link Binary With Libraries* list.
   
   - For *macOS*, drag **_one_** of the following files to the *Link Binary With Libraries* list:
      - `MoltenVK/macOS/framework/MoltenVK.framework ` *(static framework)* 
      - `MoltenVK/macOS/static/libMoltenVK.a` *(static library)* 
      - `MoltenVK/macOS/dynamic/libMoltenVK.dylib` *(dynamic library)* 

   - For *iOS*, drag **_one_** of the following files to the *Link Binary With Libraries* list:
      - `MoltenVK/iOS/framework/MoltenVK.framework ` *(static framework)* 
      - `MoltenVK/iOS/static/libMoltenVK.a` *(static library)* 
      - `MoltenVK/iOS/dynamic/libMoltenVK.dylib` *(dynamic library)* 

   - For *tvOS*, drag **_one_** of the following files to the *Link Binary With Libraries* list:
      - `MoltenVK/tvOS/framework/MoltenVK.framework ` *(static framework)* 
      - `MoltenVK/tvOS/static/libMoltenVK.a` *(static library)* 
      - `MoltenVK/tvOS/dynamic/libMoltenVK.dylib` *(dynamic library)* 

5. While in the *Link Binary With Libraries* list on the *Build Phases* tab, if you do **_not_** 
   have the **Link Frameworks Automatically** (aka `CLANG_MODULES_AUTOLINK`) and 
   **Enable Modules (C and Objective-C)** (aka `CLANG_ENABLE_MODULES`) settings enabled, click
   the **+** button, and (selecting from the list of system frameworks) add the following items:
   - `libc++.tbd`
   - `Metal.framework`
   - `Foundation.framework`.
   - `QuartzCore.framework`
   - `IOKit.framework` (*macOS*)
   - `UIKit.framework` (*iOS* or *tvOS*)
   - `IOSurface.framework` (*macOS*, or *iOS* if `IPHONEOS_DEPLOYMENT_TARGET` is at least `iOS 11.0`, 
      or *tvOS* if `TVOS_DEPLOYMENT_TARGET` is at least `tvOS 11.0`)

6. If installing **MoltenVK** as a *dynamic library* in your application, arrange to install 
   the `libMoltenVK.dylib` file in your application environment:

   - To copy the `libMoltenVK.dylib` file into your application or component library:
   
        1. On the *Build Phases* tab, add a new *Copy Files* build phase.
        
        2. Set the *Destination* into which you want to place  the `libMoltenVK.dylib` file.
           Typically this will be *Frameworks* (and should match the **Runpath Search Paths** 
           (aka `LD_RUNPATH_SEARCH_PATHS`) build setting you set above).
        
        3. Drag **_one_** of the following files to the *Copy Files* list in this new build phase:
	          - `MoltenVK/macOS/dynamic/libMoltenVK.dylib` *(macOS)*
	          - `MoltenVK/iOS/dynamic/libMoltenVK.dylib` *(iOS)*
	          - `MoltenVK/tvOS/dynamic/libMoltenVK.dylib` *(tvOS)*
   
   - Alternately, you may create your own installation mechanism to install one of the 
     `MoltenVK/macOS/dynamic/libMoltenVK.dylib`, `MoltenVK/iOS/dynamic/libMoltenVK.dylib`, 
     or `MoltenVK/tvOS/dynamic/libMoltenVK.dylib` file into a standard *macOS*, *iOS*, or 
     *tvOS* system library folder on the user's device.

7. When a *Metal* app is running from *Xcode*, the default ***Scheme*** settings reduce
   performance. To improve performance and gain the benefits of *Metal*, perform the 
   following in *Xcode*:
   
	1. Open the ***Scheme Editor*** for building your main application. You can do 
	   this by selecting ***Edit Scheme...*** from the ***Scheme*** drop-down menu, or select 
	   ***Product -> Scheme -> Edit Scheme...*** from the main menu.
	2. On the ***Info*** tab, set the ***Build Configuration*** to ***Release***, and disable the 
	   ***Debug executable*** check-box.
	3. On the ***Options*** tab, disable both the ***Metal API Validation*** and ***GPU Frame Capture***
	   options. For optimal performance, you may also consider disabling the other simulation
	   and debugging options on this tab. For further information, see the 
	   [Xcode Scheme Settings and Performance](https://developer.apple.com/library/ios/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Dev-Technique/Dev-Technique.html#//apple_ref/doc/uid/TP40014221-CH8-SW3) 
	   section of Apple's *Metal Programming Guide* documentation.


The demo apps, found in the `Demos.xcworkspace`, located in the `Demos` folder, demonstrate each
of the installation techniques discussed above:

- Static Framework: `API-Samples`.
- Static library: `Hologram`.
- Dynamic library: `Cube`.



<a name="interaction"></a>
Interacting with the **MoltenVK** Runtime
-----------------------------------------

You programmatically configure and interact with the **MoltenVK** runtime through function 
calls, enumeration values, and capabilities, in exactly the same way you do with other
*Vulkan* implementations. **MoltenVK** contains several header files that define access 
to *Vulkan* and **MoltenVK** function calls.

In your application code, you access *Vulkan* features through the API defined in the standard 
`vulkan.h` header file. This file is included in the **MoltenVK** framework, and can be included 
in your source code files as follows:

	#include <vulkan/vulkan.h>

In addition to core *Vulkan* functionality, **MoltenVK**  also supports the following *Vulkan* extensions:

- `VK_KHR_16bit_storage`
- `VK_KHR_8bit_storage`
- `VK_KHR_bind_memory2`
- `VK_KHR_create_renderpass2`
- `VK_KHR_dedicated_allocation`
- `VK_KHR_depth_stencil_resolve`
- `VK_KHR_descriptor_update_template`
- `VK_KHR_device_group`
- `VK_KHR_device_group_creation`
- `VK_KHR_driver_properties`
- `VK_KHR_get_memory_requirements2`
- `VK_KHR_get_physical_device_properties2`
- `VK_KHR_get_surface_capabilities2`
- `VK_KHR_image_format_list`
- `VK_KHR_maintenance1`
- `VK_KHR_maintenance2`
- `VK_KHR_maintenance3`
- `VK_KHR_multiview`
- `VK_KHR_portability_subset`
- `VK_KHR_push_descriptor`
- `VK_KHR_relaxed_block_layout`
- `VK_KHR_sampler_mirror_clamp_to_edge` *(macOS)*
- `VK_KHR_sampler_ycbcr_conversion`
- `VK_KHR_shader_draw_parameters`
- `VK_KHR_shader_float16_int8`
- `VK_KHR_storage_buffer_storage_class`
- `VK_KHR_surface`
- `VK_KHR_swapchain`
- `VK_KHR_swapchain_mutable_format`
- `VK_KHR_uniform_buffer_standard_layout`
- `VK_KHR_variable_pointers`
- `VK_EXT_debug_marker`
- `VK_EXT_debug_report`
- `VK_EXT_debug_utils`
- `VK_EXT_fragment_shader_interlock` *(requires Metal 2.0 and Raster Order Groups)*
- `VK_EXT_host_query_reset`
- `VK_EXT_image_robustness`
- `VK_EXT_inline_uniform_block`
- `VK_EXT_memory_budget` *(requires Metal 2.0)*
- `VK_EXT_metal_surface`
- `VK_EXT_post_depth_coverage` *(iOS, requires GPU family 4)*
- `VK_EXT_robustness2`
- `VK_EXT_scalar_block_layout`
- `VK_EXT_shader_stencil_export` *(requires Mac GPU family 2 or iOS GPU family 5)*
- `VK_EXT_shader_viewport_index_layer`
- `VK_EXT_swapchain_colorspace`
- `VK_EXT_vertex_attribute_divisor`
- `VK_EXT_texel_buffer_alignment` *(requires Metal 2.0)*
- `VK_MVK_ios_surface` *(iOS) (Obsolete. Use `VK_EXT_metal_surface` instead.)*
- `VK_MVK_macos_surface` *(macOS) (Obsolete. Use `VK_EXT_metal_surface` instead.)*
- `VK_MVK_moltenvk`
- `VK_AMD_gpu_shader_half_float`
- `VK_AMD_negative_viewport_height`
- `VK_AMD_shader_image_load_store_lod` *(iOS and tvOS)*
- `VK_AMD_shader_trinary_minmax` *(requires Metal 2.1)*
- `VK_IMG_format_pvrtc` *(iOS and tvOS)*
- `VK_INTEL_shader_integer_functions2`
- `VK_NV_glsl_shader`

In order to visibly display your content on *macOS*, *iOS*, or *tvOS*, you must enable the
`VK_EXT_metal_surface` extension, and use the function defined in that extension to create a 
*Vulkan* rendering surface. You can enable the `VK_EXT_metal_surface` extension by defining the `VK_USE_PLATFORM_METAL_EXT` guard macro in your compiler build settings. See the description of 
the `mvk_vulkan.h` file below for  a convenient way to enable this extension automatically.


<a name="moltenvk_extension"></a>
### MoltenVK `VK_MVK_moltenvk` Extension

The `VK_MVK_moltenvk` *Vulkan* extension provides functionality beyond standard *Vulkan* functionality, 
to support configuration options and behaviour that is specific to the **MoltenVK** implementation of *Vulkan* 
functionality. You can access this functionality by including the `vk_mvk_moltenvk.h` header file in your code. 
The `vk_mvk_moltenvk.h` file also includes the API documentation for this `VK_MVK_moltenvk` extension.

The following API header files are included in the **MoltenVK** package, each of which 
can be included in your application source code as follows:

	#include <MoltenVK/HEADER_FILE>

where `HEADER_FILE` is one of the following:

- `vk_mvk_moltenvk.h` - Contains declarations and documentation for the functions, structures, 
  and enumerations that define the behaviour of the `VK_MVK_moltenvk` *Vulkan* extension.

- `mvk_vulkan.h` - This is a convenience header file that loads the `vulkan.h` header file
   with the appropriate **MoltenVK** *Vulkan* platform surface extension automatically 
   enabled for *macOS*, *iOS*, or *tvOS*. Use this header file in place of the `vulkan.h` 
   header file, where access to a **MoltenVK** platform surface extension is required.
   
   The `mvk_vulkan.h` header file automatically enables the `VK_USE_PLATFORM_METAL_EXT` 
   build setting and `VK_EXT_metal_surface` *Vulkan* extension.
  
- `mvk_datatypes.h` - Contains helpful functions for converting between *Vulkan* and *Metal* data types.
  You do not need to use this functionality to use **MoltenVK**, as **MoltenVK** converts between 
  *Vulkan* and *Metal* datatypes automatically (using the functions declared in this header). 
  These functions are exposed in this header for your own purposes such as interacting with *Metal* 
  directly, or simply logging data values.

>***Note:*** The functions in `vk_mvk_moltenvk.h` are not supported by the *Vulkan SDK Loader and Layers*
 framework. The opaque Vulkan objects used by the functions in `vk_mvk_moltenvk.h` (`VkInstance`, 
 `VkPhysicalDevice`, `VkShaderModule`, `VKImage`, ...), must have been retrieved directly from **MoltenVK**, 
 and not through the *Vulkan SDK Loader and Layers* framework. The *Vulkan SDK Loader and Layers* framework 
 often changes these opaque objects, and passing them from a higher layer directly to **MoltenVK** will 
 result in undefined behaviour.


<a name="moltenvk_config"></a>
### Configuring MoltenVK

The `VK_MVK_moltenvk` *Vulkan* extension provides the ability to configure and optimize 
**MoltenVK** for your particular application runtime requirements.

There are three mechanisms for setting the values of the **MoltenVK** configuration parameters:

- Runtime API via the `vkGetMoltenVKConfigurationMVK()/vkSetMoltenVKConfigurationMVK()` functions.
- Application runtime environment variables.
- Build settings at **MoltenVK** build time.

To change some of the **MoltenVK** configuration settings at runtime using a programmatic API, 
use the `vkGetMoltenVKConfigurationMVK()` and `vkSetMoltenVKConfigurationMVK()` functions to 
retrieve, modify, and set a copy of the `MVKConfiguration` structure.

The initial value of each of the configuration settings can be established at runtime 
by a corresponding environment variable, or if the environment variable is not set, 
by a corresponding build setting at the time **MoltenVK** is compiled. The environment 
variable and build setting for each configuration parameter share the same name.

There are also a number of additional runtime environment variables that are not included in the
`MVKConfiguration` structure, but that also control **MoltenVK** behaviour.

See the description of the environment variables and the `MVKConfiguration` structure parameters 
in the `vk_mvk_moltenvk.h` file for more info about configuring and optimizing **MoltenVK** 
at runtime or build time.


<a name="shaders"></a>
*Metal Shading Language* Shaders
--------------------------------

*Metal* uses a different shader language than *Vulkan*. *Vulkan* uses the new 
*SPIR-V Shading Language (SPIR-V)*, whereas *Metal* uses the *Metal Shading Language (MSL)*.

**MoltenVK** provides several options for creating and running *MSL* versions of your 
existing *SPIR-V* shaders. The following options are presented in order of increasing 
sophistication and difficulty:

- You can use the automatic **Runtime Shader Conversion** feature of **MoltenVK** to automatically 
  and transparently convert your *SPIR-V* shaders to *MSL* at runtime, by simply loading your 
  *SPIR-V* shaders as you always have, using the standard *Vulkan* `vkCreateShaderModule()` 
  function. **MoltenVK** will automatically convert the *SPIR-V* code to *MSL* at runtime.
  
- You can use the standard *Vulkan* `vkCreateShaderModule()` function to provide your own *MSL* 
  shader code. To do so, set the value of the *magic number* element of the *SPIR-V* stream to one
  of the values in the `MVKMSLMagicNumber` enumeration found in the `vk_mvk_moltenvk.h` header file. 
  
  The *magic number* element of the *SPIR-V* stream is the first element of the stream, 
  and by setting the value of this element to either `kMVKMagicNumberMSLSourceCode` or
  `kMVKMagicNumberMSLCompiledCode`, on *SPIR-V* code that you submit to the `vkCreateShaderModule()`
  function, you are indicating that the remainder of the *SPIR-V* stream contains either
  *MSL* source code, or *MSL* compiled code, respectively.

- You can use the `MoltenVKShaderConverter` command-line tool found in this **MoltenVK** distribution 
  package to convert your *SPIR-V* shaders to *MSL* source code, offline at development time,
  in order to create the appropriate *MSL* code to load at runtime. The [section below](#shaders)
  discusses how to use this tool in more detail.

You can mix and match these options in your application. For example, a convenient approach is 
to use **Runtime Shader Conversion** for most *SPIR-V* shaders, and provide pre-converted *MSL*
shader source code for the odd *SPIR-V* shader that proves problematic for runtime conversion.



<a name="shader_converter_tool"></a>
### MoltenVKShaderConverter Shader Converter Tool

The **MoltenVK** distribution package includes the `MoltenVKShaderConverter` command line tool, 
which allows you to convert your *SPIR-V* shader source code to *MSL* at development time, and 
then supply the *MSL* code to **MoltenVK** using one of the methods described in the 
[*Metal Shading Language* Shaders](#shaders) section above.

The `MoltenVKShaderConverter` tool uses the same conversion technology as the **Runtime Shader
Conversion** feature of **MoltenVK**.

The `MoltenVKShaderConverter` tool has a number of options available from the command line:

- The tool can be used to convert a single *SPIR-V* file to *MSL*, or an entire directory tree 
  of *SPIR-V* files to *MSL*. 

- The tool can be used to convert a single *OpenGL GLSL* file, or an entire directory tree 
  of *GLSL* files to either *SPIR-V* or *MSL*. 

To see a complete list of options, run the `MoltenVKShaderConverter` tool from the command 
line with no arguments.



<a name="spv_vs_msl"></a>
### Troubleshooting Shader Conversion

The shader converter technology in **MoltenVK** is quite robust, and most *SPIR-V* shaders 
can be converted to *MSL* without any problems. In the case where a conversion issue arises, 
you can address the issue as follows:

- Errors encountered during **Runtime Shader Conversion** are logged to the console.

- To help understand conversion issues during **Runtime Shader Conversion**, you can enable the 
  logging of the *SPIR-V* and *MSL* shader source code during shader conversion, by turning on 
  the `MVKConfiguration::debugMode` configuration parameter, or setting the value of the `MVK_DEBUG` 
  runtime environment variable to `1`. See the [*MoltenVK Configuration*](#moltenvk_config) 
  description above.

  Enabling debug mode in **MoltenVK** includes shader conversion logging, which causes both 
  the incoming *SPIR-V* code and the converted *MSL* source code to be logged to the console 
  in human-readable form. This allows you to manually verify the conversions, and can help 
  you diagnose issues that might occur during shader conversion.

- For minor issues, you may be able to adjust your *SPIR-V* code so that it behaves the same 
  under *Vulkan*, but is easier to automatically convert to *MSL*.
  
- For more significant issues, you can use the `MoltenVKShaderConverter` tool to convert the
  shaders at development time, adjust the *MSL* code manually so that it compiles correctly, 
  and use the *MSL* shader code instead of the *SPIR-V* code, using the techniques described
  in the [*Metal Shading Language* Shaders](#shaders) section above.

- You are also encouraged to report issues with shader conversion to the 
  [*SPIRV-Cross*](https://github.com/KhronosGroup/SPIRV-Cross/issues) project. **MoltenVK** and 
  **MoltenVKShaderConverter** make use of *SPIRV-Cross* to convert *SPIR-V* shaders to *MSL* shaders. 



<a name="performance"></a>
Performance Considerations
--------------------------

This section discusses various options for improving performance when using **MoltenVK**.


<a name="shader_load_time"></a>
### Shader Loading Time

A number of steps is require to load and compile *SPIR-V* shaders into a form that *Metal* can use. 
Although the overall process is fast, the slowest step involves converting shaders from *SPIR-V* to
*MSL* source code format.

If you have a lot of shaders, you can dramatically improve shader loading time by using the standard
*Vulkan pipeline cache* feature, to serialize shaders and store them in *MSL* form offline.
Loading *MSL* shaders via the pipeline cache serializing mechanism can be significantly faster than 
converting from *SPIR-V* to *MSL* each time.

In *Vulkan*, pipeline cache serialization for offline storage is available through the 
`vkGetPipelineCacheData()` and `vkCreatePipelineCache()` functions. Loading the pipeline cache 
from offline storage at app start-up time can dramatically improve both shader loading performance, 
and performance glitches and hiccups during runtime code if shader loading is performed then.

When using pipeline caching, nothing changes about how you load *SPIR-V* shader code. **MoltenVK** 
automatically detects that the *SPIR-V* was previously converted to *MSL*, and stored offline via 
the *Vulkan* pipeline cache serialization mechanism, and does not invoke the relatively expensive
step of converting the *SPIR-V* to *MSL* again.

As a second shader loading performance option, *Metal* also supports pre-compiled shaders, which 
can improve shader loading and set-up performance, allowing you to reduce your scene loading time. 
See the [*Metal Shading Language* Shaders](#shaders) and 
[MoltenVKShaderConverter Shader Converter Tool](#shader_converter_tool) sections above for more 
information about how to use the `MoltenVKShaderConverter` tool to create and load pre-compiled 
*Metal* shaders into **MoltenVK**. This behaviour is not standard *Vulkan* behaviour, and does not
improve performance significantly. Your first choice should be to use offline storage of pipeline
cache contents as described in the previous paragraphs.


<a name="swapchains"></a>
### Swapchains

*Metal* supports a very small number (3) of concurrent swapchain images. In addition, *Metal* can
sometimes hold onto these images during surface presentation.

**MoltenVK** supports using either 2 or 3 swapchain images. For best performance, it is recommended
that you use 3 swapchain images (triple-buffering), to ensure that at least one swapchain image will 
be available when you need to render to it. 

Using 3 swapchain images is particularly important when rendering to a full-screen surface, because 
in that situation, *Metal* uses its *Direct to Display* feature, and avoids compositing the swapchain
image onto a separate composition surface before displaying it. Although *Direct to Display* can improve 
performance throughput, it also means that *Metal* may hold onto each swapchain image a little longer 
than when using an internal compositor, which increases the risk that a swapchain image will not be a
vailable when you request it, resulting in frame delays and visual stuttering.


<a name="xcode_config"></a>
### Xcode Configuration

When a *Metal* app is running from *Xcode*, the default ***Scheme*** settings reduce performance. 
Be sure to follow the instructions for configuring your application's ***Scheme*** within *Xcode*,
found in the  in the [installation](#install) section above.


<a name="trace_tool"></a>
### Metal System Trace Tool

To help you get the best performance from your graphics app, the *Xcode Instruments* profiling tool 
includes the *Metal System Trace* template. This template can be used to provide detailed tracing of the
CPU and GPU behaviour of your application, allowing you unprecedented performance measurement
and tuning capabilities for apps using *Metal*.



<a name="limitations"></a>
Known **MoltenVK** Limitations
------------------------------

This section documents the known limitations in this version of **MoltenVK**.

- Since **MoltenVK** is an implementation of *Vulkan* functionality, it does not load 
  *Vulkan Layers* on its own. In order to use *Vulkan Layers*, such as the validation layers, 
  use the *Vulkan Loader and Layers* from the [LunarG Vulkan SDK](https://vulkan.lunarg.com).

- Application-controlled memory allocations using `VkAllocationCallbacks` are ignored.

- Pipeline statistics query pool using `VK_QUERY_TYPE_PIPELINE_STATISTICS` is not supported.

- Image content in `PVRTC` compressed formats must be loaded directly into a `VkImage` using 
  host-visible memory mapping. Loading via a staging buffer will result in malformed image content. 
