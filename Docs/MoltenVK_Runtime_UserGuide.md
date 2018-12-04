<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



MoltenVK Runtime User Guide
===========================

Copyright (c) 2014-2018 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

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
	- [MoltenVK Extension](#moltenvk_extension)
- [*Metal Shading Language* Shaders](#shaders)
	- [MoltenVKShaderConverter Shader Converter Tool](#shader_converter_tool)
	- [Troubleshooting Shader Conversion](#spv_vs_msl)
- [Performance Considerations](#performance)
	- [Shader Loading Time](#shader_load_time)
	- [Xcode Configuration](#xcode_config)
	- [Metal System Trace Tool](#trace_tool)
- [Known **MoltenVK** Limitations](#limitations)



<a name="about_this"></a>
About This Document
-------------------

This document describes how to integrate the **MoltenVK** runtime distribution package into a game 
or application, once **MoltenVK** has been built into a framework or library for *iOS* or *macOS*.

To learn how to use the **MoltenVK** open-source repository to build a **MoltenVK** runtime 
distribution package, see the main [`README.md`](../README.md) document in the `MoltenVK` repository.



<a name="about_moltenvk"></a>
About **MoltenVK**
------------------

**MoltenVK** is an implementation of the [*Vulkan 1.0*](https://www.khronos.org/vulkan) 
graphics and compute API, that runs on Apple's [*Metal*](https://developer.apple.com/metal) 
graphics and compute framework on both *iOS* and *macOS*.

**MoltenVK** allows you to use the *Vulkan* graphics and compute API to develop modern, 
cross-platform, high-performance graphical games and applications, and to run them across 
many platforms, including both *iOS* and *macOS*.

*Metal* uses a different shading language, the *Metal Shading Language (MSL)*, than 
*Vulkan*, which uses *SPIR-V*. **MoltenVK** automatically converts your *SPIR-V* shaders 
to their *MSL* equivalents. This can be performed transparently at run time, using the 
**Runtime Shader Conversion** feature of **MoltenVK**, or at development time using the 
[**MoltenVKShaderConverter**] (#shader_converter_tool) tool provided with this **MoltenVK** 
distribution package.

To provide *Vulkan* capability to the *iOS* and *macOS* platforms, **MoltenVK** uses *Apple's* 
publicly available API's, including *Metal*. **MoltenVK** does **_not_** use any private or
undocumented API calls or features, so your app will be compatible with all standard distribution 
channels, including *Apple's App Store*.


<a name="install"></a>
Installing **MoltenVK** in Your *Vulkan* Application
----------------------------------------------------

<a name="requirements"></a>
### Build and Runtime Requirements

At development time, **MoltenVK** references advanced OS frameworks during building.
 
- *Xcode 9* or above is required to build and link **MoltenVK** projects.

Once built, **MoltenVK** can be run on *iOS* or *macOS* devices that support *Metal*.

- **MoltenVK** requires at least *macOS 10.11* or  *iOS 9*.
- Information on *macOS* devices that are compatible with *Metal* can be found in 
  [this article](http://www.idownloadblog.com/2015/06/22/how-to-find-mac-el-capitan-metal-compatible).
- Information on compatible *iOS* devices that are compatible with *Metal* can be found in 
  [this article](https://developer.apple.com/library/content/documentation/DeviceInformation/Reference/iOSDeviceCompatibility/HardwareGPUInformation/HardwareGPUInformation.html).


<a name="install_lib"></a>
### Install as Static Framework, Static Library, or Dynamic Library

Installation of **MoltenVK** is straightforward and easy!

Depending on your build and deployment needs, you can install **MoltenVK** as a *static framework*,
*static library*, or *dynamic library*, by following the steps in this section. If you are unsure 
about which linking and deployment option you need, follow the steps for installing a 
*static framework*, as it is the simplest to install.

1. Open your application in *Xcode* and select your application's target in the 
   *Project Navigator* panel.


2. Open the *Build Settings* tab.

	- If installing **MoltenVK** as a *static framework* in your application:
	    1. In the **Framework Search Paths** (aka `FRAMEWORK_SEARCH_PATHS`) 
	       setting, add an entry that points to **_one_** of the following folders:
	          - `MoltenVK/macOS/framework` *(macOS)*
	          - `MoltenVK/iOS/framework` *(iOS)*

	- If installing **MoltenVK** as a *static library* in your application:
	    1. In the **Library Search Paths** (aka `LIBRARY_SEARCH_PATHS`) setting, 
	       add an entry that points to **_one_** of the following folders:
	          - `MoltenVK/macOS/static` *(macOS)*
	          - `MoltenVK/iOS/static` *(iOS)*
        2. In the **Header Search Paths** (aka `HEADER_SEARCH_PATHS`) setting, 
           add an entry that points to the `MoltenVK/include` folder.

	- If installing **MoltenVK** as a *dynamic library* in your application:
	    1. In the **Library Search Paths** (aka `LIBRARY_SEARCH_PATHS`) setting, 
	       add an entry that points to **_one_** of the following folders:
	          - `MoltenVK/macOS/dynamic` *(macOS)*
	          - `MoltenVK/iOS/dynamic` *(iOS)*
        2. In the **Header Search Paths** (aka `HEADER_SEARCH_PATHS`) setting, 
           add an entry that points to the `MoltenVK/include` folder.
        3. In the **Runpath Search Paths** (aka `LD_RUNPATH_SEARCH_PATHS`) setting, 
           add an entry that matches where the dynamic library will be located in your runtime
           environment. If the dynamic library is to be embedded within your application, 
           you would typically set this value to either `@executable_path` or `@loader_path`. 
           The `libMoltenVK.dylib` library is internally configured to be located at 
           `@rpath/libMoltenVK.dylib`.

3. With the *Build Settings* tab open, if using `IOSurfaces` on *iOS*, open the **iOS Deployment Target** 
   (aka `IPHONEOS_DEPLOYMENT_TARGET`) setting, and ensure it is set to a value of `iOS 11.0` or greater.

4. On the *Build Phases* tab, open the *Link Binary With Libraries* list.
   
   - For *macOS*, drag **_one_** of the following files to the *Link Binary With Libraries* list:
      - `MoltenVK/macOS/framework/MoltenVK.framework ` *(static framework)* 
      - `MoltenVK/macOS/static/libMoltenVK.a` *(static library)* 
      - `MoltenVK/macOS/dynamic/libMoltenVK.dylib` *(dynamic library)* 

   - For *iOS*, drag **_one_** of the following files to the *Link Binary With Libraries* list:
      - `MoltenVK/iOS/framework/MoltenVK.framework ` *(static framework)* 
      - `MoltenVK/iOS/static/libMoltenVK.a` *(static library)* 
      - `MoltenVK/iOS/dynamic/libMoltenVK.dylib` *(dynamic library)* 

5. While in the *Link Binary With Libraries* list on the *Build Phases* tab, if you do **_not_** 
   have the **Link Frameworks Automatically** (aka `CLANG_MODULES_AUTOLINK`) and 
   **Enable Modules (C and Objective-C)** (aka `CLANG_ENABLE_MODULES`) settings enabled, click
   the **+** button, and (selecting from the list of system frameworks) add the following items:
   - `libc++.tbd`
   - `Metal.framework`
   - `Foundation.framework`.
   - `QuartzCore.framework`
   - `IOKit.framework` (*macOS*)
   - `UIKit.framework` (*iOS*)
   - `IOSurface.framework` (*macOS*, or *iOS* if `IPHONEOS_DEPLOYMENT_TARGET` is at least `iOS 11.0`)


6. If installing **MoltenVK** as a *dynamic library* in your application, arrange to install 
   the `libMoltenVK.dylib` file in your application environment:

   - To copy the `libMoltenVK.dylib` file into your application or component library:
        1. On the *Build Phases* tab, add a new *Copy Files* build phase.
        2. Set the *Destination* into which you want to place  the `libMoltenVK.dylib` file.
           Typically this will be *Executables*.
        3. Drag **_one_** of the following files to the *Copy Files* list in this new build phase:
	          - `MoltenVK/macOS/dynamic/libMoltenVK.dylib` *(macOS)*
	          - `MoltenVK/iOS/dynamic/libMoltenVK.dylib` *(iOS)*
   
   - Alternately, you may create your own installation mechanism to install either the 
     `MoltenVK/macOS/dynamic/libMoltenVK.dylib` or `MoltenVK/iOS/dynamic/libMoltenVK.dylib` 
     file into a standard *macOS* or *iOS* system library folder on the user's device.

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
*Vulkan* implementations. The `MoltenVK.framework` contains several header files that define
access to *Vulkan* and **MoltenVK** function calls.

In your application code, you access *Vulkan* features through the API defined in the standard 
`vulkan.h` header file. This file is included in the **MoltenVK** framework, and can be included 
in your source code files as follows:

	#include <vulkan/vulkan.h>

In addition to the core *Vulkan* API, **MoltenVK**  also supports the following *Vulkan* extensions:

- `VK_KHR_16bit_storage`
- `VK_KHR_dedicated_allocation`
- `VK_KHR_descriptor_update_template`
- `VK_KHR_get_memory_requirements2`
- `VK_KHR_get_physical_device_properties2`
- `VK_KHR_image_format_list`
- `VK_KHR_maintenance1`
- `VK_KHR_maintenance2`
- `VK_KHR_maintenance3`
- `VK_KHR_push_descriptor`
- `VK_KHR_relaxed_block_layout`
- `VK_KHR_sampler_mirror_clamp_to_edge`
- `VK_KHR_shader_draw_parameters`
- `VK_KHR_storage_buffer_storage_class`
- `VK_KHR_surface`
- `VK_KHR_swapchain`
- `VK_EXT_shader_viewport_index_layer`
- `VK_EXT_vertex_attribute_divisor`
- `VK_MVK_moltenvk`
- `VK_MVK_macos_surface` (macOS)
- `VK_MVK_ios_surface` (iOS)
- `VK_AMD_negative_viewport_height`
- `VK_IMG_format_pvrtc` (iOS)

In order to visibly display your content on *iOS* or *macOS*, you must enable the `VK_MVK_ios_surface` 
or `VK_MVK_macos_surface` extension, respectively, and use the functions defined for that extension
to create a *Vulkan* rendering surface.

You can enable each of these extensions by defining the `VK_USE_PLATFORM_IOS_MVK` or 
`VK_USE_PLATFORM_MACOS_MVK` guard macro in your compiler build settings. See the description
of the `mvk_vulkan.h` file below for a convenient way to enable these extensions automatically.

When using the `VK_MVK_macos_surface ` extension, the `pView` member of the `VkMacOSSurfaceCreateInfoMVK` 
structure passed in the `vkCreateMacOSSurfaceMVK` function can be either an `NSView` whose layer is a 
`CAMetalLayer`, or the `CAMetalLayer` itself. Passing the `CAMetalLayer` itself is recommended when calling
the `vkCreateMacOSSurfaceMVK` function from outside the main application thread, as `NSView` should only be
accessed from the main application thread.

When using the `VK_MVK_ios_surface ` extension, the `pView` member of the `VkIOSSurfaceCreateInfoMVK` 
structure passed in the `vkCreateIOSSurfaceMVK` function can be either a `UIView` whose layer is a 
`CAMetalLayer`, or the `CAMetalLayer` itself. Passing the `CAMetalLayer` itself is recommended when 
calling the `vkCreateIOSSurfaceMVK ` function from outside the main application thread, as `UIView` 
should only be accessed from the main application thread.

<a name="moltenvk_extension"></a>
### MoltenVK Extension

The `VK_MVK_moltenvk` *Vulkan* extension provides functionality beyond the standard *Vulkan*
API, to support configuration options, license registration, and behaviour that is specific 
to the **MoltenVK** implementation of *Vulkan*. You can access this functionality by including
the `vk_mvk_moltenvk.h` header file in your code. The `vk_mvk_moltenvk.h` file also includes 
the API documentation for this `VK_MVK_moltenvk` extension.

The following API header files are included in the **MoltenVK** package, each of which 
can be included in your application source code as follows:

	#include <MoltenVK/HEADER_FILE>

where `HEADER_FILE` is one of the following:

- `vk_mvk_moltenvk.h` - Contains declarations and documentation for the functions, structures, 
  and enumerations that define the behaviour of the `VK_MVK_moltenvk` *Vulkan* extension.

- `mvk_vulkan.h` - This is a convenience header file that loads the `vulkan.h` header file
   with the appropriate **MoltenVK** *Vulkan* platform surface extension automatically 
   enabled for *iOS* or *macOS*. Use this header file in place of the `vulkan.h` header file, 
   where access to a **MoltenVK** platform surface extension is required.
   
   - When building for *iOS*, the `mvk_vulkan.h` header file automatically enables the 
    `VK_USE_PLATFORM_IOS_MVK` build setting and `VK_MVK_ios_surface` *Vulkan* extension.
   - When building for *macOS*, the `mvk_vulkan.h` header file automatically enables the
    `VK_USE_PLATFORM_MACOS_MVK` build setting and `VK_MVK_macos_surface` *Vulkan* extension.
  
- `mvk_datatypes.h` - Contains helpful functions for converting between *Vulkan* and *Metal* data types.
  You do not need to use this functionality to use **MoltenVK**, as **MoltenVK** converts between 
  *Vulkan* and *Metal* datatypes automatically (using the functions declared in this header). 
  These functions are exposed in this header for your own purposes such as interacting with *Metal* 
  directly, or simply logging data values.



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

- To help understand conversion issues during **Runtime Shader Conversion**, you can enable
  the logging of the *SPIR-V* and *MSL* shader source code during conversion as follows:
  
  		#include <MoltenVK/vk_mvk_moltenvk.h>
  		...
  		MVKConfiguration mvkConfig;
  		size_t appConfigSize = sizeof(mvkConfig);
  		vkGetMoltenVKConfigurationMVK(vkInstance, &mvkConfig, &appConfigSize);
  		mvkConfig.debugMode = true;
  		vkSetMoltenVKConfigurationMVK(vkInstance, &mvkConfig, &appConfigSize);

  Performing these steps will enable debug mode in **MoltenVK**, which includes shader conversion 
  logging, and causes both the incoming *SPIR-V* code and the converted *MSL* source code to be 
  logged to the console (in human-readable form). This allows you to manually verify the conversions, 
  and can help you diagnose issues that might occur during shader conversion.

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

- **MoltenVK** is a Layer-0 driver implementation of *Vulkan 1.0*
  Since it takes on the role of a driver in the Vulkan architecture, it does not load *Vulkan Layers*
  on its own.
  In order to use Vulkan layers such as the validation layers, use the Vulkan loader and layers from the
  [LunarG Vulkan SDK](https://vulkan.lunarg.com).

The following *Vulkan 1.0* features have not been implemented in this version of **MoltenVK**:

- Tessellation and Geometry shader stages.

- Events:
	- `vkCreateEvent()`
	- `vkDestroyEvent()`
	- `vkGetEventStatus()`
	- `vkSetEvent()`
	- `vkResetEvent()`
	- `vkCmdSetEvent()`
	- `vkCmdResetEvent()`
	- `vkCmdWaitEvents()`

- Application-controlled memory allocations:
	- `VkAllocationCallbacks` are ignored
	 
- Sparse memory:
	- `vkGetImageSparseMemoryRequirements()`
	- `vkGetPhysicalDeviceSparseImageFormatProperties()`
	- `vkQueueBindSparse()`
	 
- Pipeline statistics query pool:
	- `vkCreateQueryPool(VK_QUERY_TYPE_PIPELINE_STATISTICS)`

