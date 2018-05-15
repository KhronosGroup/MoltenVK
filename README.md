<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



MoltenVK
========

Copyright (c) 2014-2018 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format. 
For best results, use a Markdown reader.*

[![Build Status](https://travis-ci.org/KhronosGroup/MoltenVK.svg?branch=master)](https://travis-ci.org/KhronosGroup/MoltenVK)

Table of Contents
-----------------

- [About This Document](#about_this)
- [Introduction](#intro)
- [Installing **MoltenVK**](#install)
- [Building **MoltenVK**](#building)
- [Running the **MoltenVK** Demo Applications](#demos)
- [Using **MoltenVK** in Your Application](#using)
- [**MoltenVK** and *Vulkan* Compliance](#compliance)
- [Contributing to **MoltenVK** Development](#contributing)



<a name="about_this"></a>
About This Document
-------------------

This document describes how to use the **MoltenVK** open-source repository to build a **MoltenVK** 
runtime distribution package.

To learn how to integrate the **MoltenVK** runtime into a game or application, see the 
[`Docs/MoltenVK_Runtime_UserGuide.md `](Docs/MoltenVK_Runtime_UserGuide.md) document in the `Docs` directory. 

If you are just looking for a pre-built **MoltenVK** runtime binary, you can download it as part of the 
[*LunarG SDK*](https://vulkan.lunarg.com).



<a name="intro"></a>
Introduction
------------

**MoltenVK** contains two products:

- **MoltenVK** is an implementation of the [*Vulkan 1.0*](https://www.khronos.org/vulkan) 
  graphics and compute API, that runs on Apple's [*Metal*](https://developer.apple.com/metal) 
  graphics and compute framework on both *iOS* and *macOS*.

- **MoltenVKShaderConverter** converts *SPIR-V* shader code to *Metal Shading Language (MSL)*
  shader source code, and converts *GLSL* shader source code to *SPIR-V* shader code and/or
  *Metal Shading Language (MSL)* shader source code, for use with **MoltenVK**. The converter
  can run at runtime as a component of the *MoltenVK* runtime, or it can be packaged into a 
  stand-alone command-line *macOS* tool. The *Xcode* project contains several targets, 
  reflecting this multi-use capability.



<a name="install"></a>
Installing **MoltenVK**
-----------------------

To install **MoltenVK**, clone this `MoltenVK` repository, and then run the 
`fetchDependencies` script to retrieve and build several external 
open-source libraries on which **MoltenVK** relies:

1. Ensure you have `cmake` and `python3` installed:

		brew install cmake
		brew install python

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

At development time, **MoltenVK** references advanced OS frameworks during building.
 
- *Xcode 9* or above is required to build and link **MoltenVK** projects.

Once built, **MoltenVK** can be run on *iOS* or *macOS* devices that support *Metal*.

- **MoltenVK** requires at least *macOS 10.11* or  *iOS 9*.
- Information on *macOS* devices that are compatible with *Metal* can be found in 
  [this article](http://www.idownloadblog.com/2015/06/22/how-to-find-mac-el-capitan-metal-compatible).
- Information on compatible *iOS* devices that are compatible with *Metal* can be found in 
  [this article](https://developer.apple.com/library/content/documentation/DeviceInformation/Reference/iOSDeviceCompatibility/HardwareGPUInformation/HardwareGPUInformation.html).

The `MoltenVKPackaging.xcodeproj` *Xcode* project contains targets and schemes to build 
and package the entire **MoltenVK** runtime distribution package, or to build individual 
**MoltenVK** or **MoltenVKShaderConverter** components.

To build a **MoltenVK** runtime distribution package, suitable for testing and integrating into an app, 
open `MoltenVKPackaging.xcodeproj` in *Xcode*, and use one of the following *Xcode Schemes*:

- **MoltenVK (Release)** - build the entire **MoltenVK** runtime distribution package using the 
  *Release* configuration.
- **MoltenVK (Debug)** - build the entire **MoltenVK** runtime distribution package using the 
  *Debug* configuration.

Each of these`MoltenVKPackaging.xcodeproj` *Xcode* project *Schemes* puts the resulting packages in the 
`Package` directory, creating it if necessary. This directory contains separate `Release` and `Debug` 
directories, holding the most recent **Release** and **Debug** builds, respectively.

A separate `Latest` directory links to  the most recent build, regardless of whether it was a **Release** 
or **Debug** build. Effectively, the `Package/Latest` directory points to whichever of the `Package/Release` 
or `Package/Debug` directories was most recently updated.

With this packaging structure, you can follow the [instructions below](#using) to link your application 
to the **MoltenVK** frameworks in the `Package/Latest` directory, to provide the flexibility to test your 
app with either a **Debug** build, or a higher-performance **Release** build.


### Building from the Command Line

If you prefer to build **MoltenVK** from the command line, or to include the activity in a larger build script,
you can do so using the following command from within the `MoltenVK` repository:

	xcodebuild -project MoltenVKPackaging.xcodeproj -scheme "MoltenVK (Release)" build

or

	xcodebuild -project MoltenVKPackaging.xcodeproj -scheme "MoltenVK (Debug)" build



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
section of the [`Docs/MoltenVK_Runtime_UserGuide.md`](Docs/MoltenVK_Runtime_UserGuide.md#install) document in the
`Docs` directory, to link the **MoltenVK** frameworks and libraries to your application.

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
  known limitations is documented in the [`Docs/MoltenVK_Runtime_UserGuide.md`](Docs/MoltenVK_Runtime_UserGuide.md#limitations) 
  document in the `Docs` directory.

The **MoltenVK** development team welcomes you to [post Issues](https://github.com/KhronosGroup/MoltenVK/issues) 
of non-compliance, and engage in discussions about how compliance can be improved, and non-compliant features can 
be implemented or worked around.

**MoltenVK** is a key component of the [*Khronos Vulkan Portability Initiative*](https://www.khronos.org/vulkan/portability-initiative), 
whose intention is to provide specifications, resources, and tools to allow developers to understand and design 
their *Vulkan* apps for maximum cross-platform compatibility and portability, including on platforms, such as 
*macOS* and *iOS*, where a native *Vulkan* driver is not avaialble. 



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


### Code Formatting

When contirbuting code, please honour the code formatting style found in existing **MoltenVK** source code.
In future, this will formally be enforced using `clang-format`.
