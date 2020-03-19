<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



MoltenVK
========

Copyright (c) 2015-2020 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format. 
For best results, use a Markdown reader.*

[![Build Status](https://travis-ci.org/KhronosGroup/MoltenVK.svg?branch=master)](https://travis-ci.org/KhronosGroup/MoltenVK)

Table of Contents
-----------------

- [Developing Vulkan Applications on macOS and iOS](#developing_vulkan)
- [Introduction to **MoltenVK**](#intro)
- [Fetching **MoltenVK** Source Code](#install)
- [Building **MoltenVK**](#building)
- [Running the **MoltenVK** Demo Applications](#demos)
- [Using **MoltenVK** in Your Application](#using)
- [**MoltenVK** and *Vulkan* Compliance](#compliance)
- [Reporting Issues](#issues)
- [Contributing to **MoltenVK** Development](#contributing)



<a name="developing_vulkan"></a>
Developing Vulkan Applications for macOS and iOS
------------------------------------------------

The recommended method for developing a *Vulkan* application for *macOS* is to use the 
[*Vulkan SDK*](https://vulkan.lunarg.com/sdk/home).

The *Vulkan SDK* includes a  **MoltenVK** runtime library for *macOS*. *Vulkan* is a layered 
architecture that allows applications to add additional functionality without modifying the 
application itself. The *Validation Layers* included in the *Vulkan SDK* are an essential debugging
tool for application developers because they identify inappropriate use of the *Vulkan API*. 
If you are developing a *Vulkan* application for *macOS*, it is highly recommended that you use the
[*Vulkan SDK*](https://vulkan.lunarg.com/sdk/home) and the **MoltenVK** library included in it. 

If you are developing a *Vulkan* application for *iOS*, or are developing a *Vulkan* application for
*macOS* and want to use a different **MoltenVK** runtime library than provided in the *macOS Vulkan SDK*,
you can use this document to learn how to build a **MoltenVK** runtime library from source code.

To learn how to integrate the **MoltenVK** runtime library into a game or application, 
see the [`MoltenVK_Runtime_UserGuide.md `](Docs/MoltenVK_Runtime_UserGuide.md) 
document in the `Docs` directory. 



<a name="intro"></a>
Introduction to MoltenVK
------------------------

**MoltenVK** is a layered implementation of [*Vulkan 1.0*](https://www.khronos.org/vulkan) 
graphics and compute functionality, that is built on Apple's [*Metal*](https://developer.apple.com/metal) 
graphics and compute framework on both *iOS* and *macOS*. **MoltenVK** allows you to use *Vulkan* graphics 
and compute functionality to develop modern, cross-platform, high-performance graphical games and applications, 
and to run them across many platforms, including both *iOS* and *macOS*.

*Metal* uses a different shading language, the *Metal Shading Language (MSL)*, than 
*Vulkan*, which uses *SPIR-V*. **MoltenVK** automatically converts your *SPIR-V* shaders 
to their *MSL* equivalents.

To provide *Vulkan* capability to the *iOS* and *macOS* platforms, **MoltenVK** uses *Apple's* 
publicly available API's, including *Metal*. **MoltenVK** does **_not_** use any private or
undocumented API calls or features, so your app will be compatible with all standard distribution 
channels, including *Apple's App Store*.

The **MoltenVK** runtime package contains two products:

- **MoltenVK** is a driver-level implementation of the [*Vulkan 1.0*](https://www.khronos.org/vulkan) 
  graphics and compute API.

- **MoltenVKShaderConverter** converts *SPIR-V* shader code to *Metal Shading Language (MSL)*
  shader code, and converts *GLSL* shader source code to *SPIR-V* shader code and/or
  *Metal Shading Language (MSL)* shader code. The *SPIR-V* converter is included in the 
  **MoltenVK** runtime to automatically convert *SPIR-V* shaders to their *MSL* equivalents. 
  In addition, both the *SPIR-V* and *GLSL* converters can be be packaged into a stand-alone 
  command-line *macOS* tool for converting shaders at development time.



<a name="install"></a>
Fetching **MoltenVK** Source Code
---------------------------------

To fetch **MoltenVK** source code, clone this `MoltenVK` repository, and then run the 
`fetchDependencies` script to retrieve and build several external open-source libraries 
on which **MoltenVK** relies:

1. Ensure you have `cmake` and `python3` installed:

		brew install cmake
		brew install python3

   For faster dependency builds, you can also optionally install `ninja`:

		brew install ninja

2. Clone the `MoltenVK` repository:

		git clone https://github.com/KhronosGroup/MoltenVK.git

3. Retrieve and build the external libraries:

		cd MoltenVK
		./fetchDependencies

For more information about the external open-source libraries used by **MoltenVK**,
see the [`ExternalRevisions/README.md`](ExternalRevisions/README.md) document.


<a name="building"></a>
Building **MoltenVK**
-------------------

During building, **MoltenVK** references the latest *Apple SDK* frameworks. To access these frameworks, 
and to avoid build errors, be sure to use the latest publicly available version of *Xcode*.

>***Note:*** To support `IOSurfaces` on *iOS*, **MoltenVK**, and any app that uses **MoltenVK**, 
must be built with a minimum **iOS Deployment Target** (aka `IPHONEOS_DEPLOYMENT_TARGET `) build 
setting of `iOS 11.0` or greater.

Once built, the **MoltenVK** libraries can be run on *iOS* or *macOS* devices that support *Metal*.

- At runtime, **MoltenVK** requires at least *macOS 10.11* or *iOS 9* (or *iOS 11* if using `IOSurfaces`).
- Information on *macOS* devices that are compatible with *Metal* can be found in 
  [this article](http://www.idownloadblog.com/2015/06/22/how-to-find-mac-el-capitan-metal-compatible).
- Information on *iOS* devices that are compatible with *Metal* can be found in 
  [this article](https://developer.apple.com/library/content/documentation/DeviceInformation/Reference/iOSDeviceCompatibility/HardwareGPUInformation/HardwareGPUInformation.html).

The `MoltenVKPackaging.xcodeproj` *Xcode* project contains targets and schemes to build 
and package the entire **MoltenVK** runtime distribution package, or to build individual 
**MoltenVK** or **MoltenVKShaderConverter** components.

To build a **MoltenVK** runtime distribution package, suitable for testing and integrating into an app, 
open `MoltenVKPackaging.xcodeproj` in *Xcode*, and use one of the following *Xcode Schemes*, depending
on whether you want a **_Release_** or **_Debug_** configuration, and whether you want to build for both
the *iOS* and *macOS* platforms, or just one platform (in **_Release_** configuration):

- **MoltenVK Package** 
- **MoltenVK Package (Debug)** 
- **MoltenVK Package (iOS only)**
- **MoltenVK Package (macOS only)** 

Each of these`MoltenVKPackaging.xcodeproj` *Xcode* project *Schemes* puts the resulting packages in the 
`Package` directory, creating it if necessary. This directory contains separate `Release` and `Debug` 
directories, holding the most recent **_Release_** and **_Debug_** builds, respectively.

A separate `Latest` directory links to  the most recent build, regardless of whether it was a **_Release_** 
or **_Debug_** build. Effectively, the `Package/Latest` directory points to whichever of the `Package/Release` 
or `Package/Debug` directories was most recently updated.

With this packaging structure, you can follow the [instructions below](#using) to link your application 
to the **MoltenVK** libraries and frameworks in the `Package/Latest` directory, to provide the flexibility 
to test your app with either a **_Debug_** build, or a higher-performance **_Release_** build.


### Building from the Command Line

If you prefer to build **MoltenVK** from the command line, or to include the activity in a larger build script,
you can do so using the following command within the `MoltenVK` repository folder, and identifying one of the 
*Xcode Schemes* from the list above. For example, the following command will build **MoltenVK** in the 
**_Release_** configuration for both *macOS* and *iOS*:

	xcodebuild -quiet -project MoltenVKPackaging.xcodeproj -scheme "MoltenVK Package" build

Alternately, you can use the basic `Makefile` in the `MoltenVK` repository folder to build **MoltenVK** 
in the **_Release_** configuration from the command line. The following `make` targets are provided:

	make
	make all
	make macos
	make ios
	make clean
	make install

The `install` target will copy the most recently built *macOS* `MoltenVK.framework` into 
the `/Library/Frameworks` folder of your computer. Since `/Library/Frameworks` is protected, 
you will generally need to run it as `sudo make install` and enter your password.

The default `make` command with no arguments is the same as `make all`.

The `make` targets all require that *Xcode* is installed on your system. 

Building from the command line creates the same `Package` folder structure described above when building
from within *Xcode*.


### Building Within a Larger External Build Environment

If you build **MoltenVK** as part of a larger build environment, that does not use the scripts or *Xcode* 
projects provided by **MoltenVK**, you may be interested in certain build options designed to allow you to 
customize the use of **MoltenVK** within your custom build environment. These options are not available
in the default **MoltenVK** build environment described in the previous sections.

- `MoltenVKShaderConverter` uses the `SPIRV-Tools` external library to log SPIR-V code for diagnostics. 
  If this is not useful to you, you can define the `MVK_EXCLUDE_SPIRV_TOOLS` when building the 
  `MoltenVKShaderConverter` code base, and **MoltenVK** will not attempt to use code from the `SPIRV-Tools` 
  repository. In this way, you will not need to retrieve or build the `SPIRV-Tools` repository, or link to 
  a `SPIRV-Tools` external library.



<a name="demos"></a>
Running the **MoltenVK** Demo Applications
------------------------------------------

Once you have compiled and built the **MoltenVK** runtime distribution package from this **MoltenVK** repository, 
as described in the [Building **MoltenVK**](#building) section, you can explore how **MoltenVK** provides *Vulkan* 
support on *iOS* and *macOS* by investigating and running the demo applications that are included in **MoltenVK**.

The **MoltenVK** demo apps are located in the `Demos` folder. Each demo app is available as an *Xcode* project.
To review and run the included demo apps, open the `Demos/Demos.xcworkspace` workspace in *Xcode*.

Please read the [`Demos/README.md`](Demos/README.md) document for a description of each demo app, and instructions 
on running the demo apps. Several of the demo apps allow you to explore a variety of *Vulkan* features by modifying
*Xcode* build settings. Additional demos can be downloaded and built from external repositories, as described in the
[`Demos/README.md`](Demos/README.md) document



<a name="using"></a>
Using **MoltenVK** in Your Application
--------------------------------------

Once you have compiled and built the **MoltenVK** runtime distribution package from this **MoltenVK** repository, 
as described in the [Building **MoltenVK**](#building) section, follow the instructions in the Installation 
section of the [`Docs/MoltenVK_Runtime_UserGuide.md`](Docs/MoltenVK_Runtime_UserGuide.md#install) document 
in the `Docs` directory, to link the **MoltenVK** libraries and frameworks to your application.

The runtime distribution package in the `Package/Latest` directory is a stand-alone package, and you can copy 
the contents of that directory out of this **MoltenVK** repository into your own application building environment.



<a name="compliance"></a>

**MoltenVK** and *Vulkan* Compliance
------------------------------------

**MoltenVK** is designed to be a *Vulkan 1.0* driver that runs on *macOS* and *iOS* platforms by mapping *Vulkan*
capability to native *Metal* capability.

The fundamental design and development goal of **MoltenVK** is to provide this capability in a way that 
is both maximally compliant with the *Vulkan 1.0* specification, and maximally  performant.

Such compliance and performance is inherently affected by the capability available through *Metal*, as the 
native driver on *macOS* and *iOS* platforms. *Vulkan* compliance may fall into one of the following categories:

- Direct mapping between *Vulkan* capabilities and *Metal* capabilities. Within **MoltenVK**, almost all capability
  is the result of this type of direct mapping. 
  
- Synthesized compliance through alternate implementation. A very small amount of capability is provided using
  this mechanism, such as via an extra render or compute shader stage.

- Non-compliance. This appears where the capabilities of *Vulkan* and *Metal* are sufficiently different, that
  there is no practical, or reasonably performant, mechanism to implement a *Vulkan* capability in *Metal*. 
  Because of design differences between *Vulkan* and *Metal*, a very small amount of capability falls into this 
  category, and at present **MoltenVK** is **_not_** fully compliant with the *Vulkan* specification. A list of 
  known limitations is documented in the [`MoltenVK_Runtime_UserGuide.md`](Docs/MoltenVK_Runtime_UserGuide.md#limitations) 
  document in the `Docs` directory.

The **MoltenVK** development team welcomes you to [post Issues](https://github.com/KhronosGroup/MoltenVK/issues) 
of non-compliance, and engage in discussions about how compliance can be improved, and non-compliant features can 
be implemented or worked around.

**MoltenVK** is a key component of the [*Khronos Vulkan Portability Initiative*](https://www.khronos.org/vulkan/portability-initiative), 
whose intention is to provide specifications, resources, and tools to allow developers to understand and design 
their *Vulkan* apps for maximum cross-platform compatibility and portability, including on platforms, such as 
*macOS* and *iOS*, where a native *Vulkan* driver is not available. 



<a name="issues"></a>

Reporting Issues
----------------

- If you encounter an issue with the behaviour of **MoltenVK**, you can report it in the 
  [*MoltenVK Issues List*](https://github.com/KhronosGroup/MoltenVK/issues).

- If you encounter an issue with the *Vulkan SDK*, including the *Validation Layers*, you can report it in the 
  [*Vulkan SDK Issues List*](https://vulkan.lunarg.com/issue/home).

- If you explore **MoltenVK** and determine that it does not meet your requirements at this time, we would appreciate
  hearing why that is so, on the [*MoltenVK Issues List*](https://github.com/KhronosGroup/MoltenVK/issues). 
  The goal of **MoltenVK** is to increase the value of *Vulkan* as a true cross-platform ecosystem, by providing 
  *Vulkan* on *Apple* platforms. Hearing why this is currently not working for you will help us in that goal.



<a name="contributing"></a>

Contributing to **MoltenVK** Development
----------------------------------------

As a public open-source project, **MoltenVK** benefits from code contributions from a wide range of developers, 
and we encourage you to get involved and contribute code to this **MoltenVK** repository.

To contribute your code, submit a [Pull Request](https://github.com/KhronosGroup/MoltenVK/pulls) 
to this repository. The first time you do this, you will be asked to agree to the **MoltenVK** 
[Contributor License Agreement](https://cla-assistant.io/KhronosGroup/MoltenVK).


### Licensing

**MoltenVK** is licensed under the Apache 2.0 license. All new source code files should include a 
copyright header at the top, containing your authorship copyright and the Apache 2.0 licensing stub. 
You may copy the text from an existing source code file as a template.

The Apache 2.0 license guarantees that code in the **MoltenVK** repository is free of Intellectual Property
encumbrances. In submitting code to this repository, you are agreeing that the code is free of any Intellectual 
Property claims.  


### Memory Management

*Metal*, and other *Objective-C* objects in *Apple's SDK* frameworks, use reference counting for memory management. 
When instantiating *Objective-C* objects, it is important that you do not rely on implied *autorelease pools* to do 
memory management for you. Because many *Vulkan* games and apps may be ported from other platforms, they will 
typically not include autorelease pools in their threading models.

Avoid the use of the `autorelease` method, or any object creation methods that imply use of `autorelease`,
(eg- `[NSString stringWithFormat: ]`, etc). Instead, favour object creation methods that return a retained object
(eg- `[[NSString alloc] initWithFormat: ]`, etc), and manually track and release those objects. If you need to use 
autoreleased objects, wrap code blocks in an `@autoreleasepool {...}` block.


### Code Formatting

When contributing code, please honour the code formatting style found in existing **MoltenVK** source code.
In future, this will formally be enforced using `clang-format`.
