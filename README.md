<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



MoltenVK
========

Copyright (c) 2014-2017 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format. 
For best results, use a Markdown reader.*



Table of Contents
-----------------

- [About This Document](#about_this)
- [Introduction](#intro)
- [Installing **MoltenVK**](#install)
- [Third-Party Libraries](#third-party)
	- [Updating the Third-Party Library Versions](#update_third-party)
- [Building **MoltenVK**](#building)
- [Using **MoltenVK** in Your Application](#using)
- [Third-Party Credits](#credits)



<a name="about_this"></a>
About This Document
-------------------

This document describes how to use the **MoltenVK** open-source repository to build a **MoltenVK** 
runtime distribution package.

To learn how to integrate the **MoltenVK** runtime into a game or application, see the 
[**MoltenVK Runtime User Guide**](Docs/MoltenVK_Runtime_UserGuide.md) document in the `Docs` directory. 



<a name="intro"></a>
Introduction
------------

**MoltenVK** contains two products:

- **MoltenVK** is an implementation of the [*Vulkan*](https://www.khronos.org/vulkan) 
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

**MoltenVK** relies on several third-party open-source libraries, which are described in the 
[next section](#third-party). The easiest way to install **MoltenVK** is to recursively clone 
this `MoltenVK` repository, and then run the `External/makeAll` script to create necessary 
components within the third-party libraries.

1. Ensure you have `python3` and `asciidoctor` installed:

		brew install python3
		sudo gem install asciidoctor

2. Recursively clone the `MoltenVK` repository:

		git clone --recursive https://github.com/KhronosGroup/MoltenVK.git

3. Run the third-party build script:

		cd MoltenVK/External
		./makeAll

See the [next section](#third-party) for more information about the third-party libraries, 
and how to work with them within the **MoltenVK** development environment.


<a name="third-party"></a>
Third-Party Libraries
---------------------

**MoltenVK** makes use of several third-party open-source libraries.
Development of some of these components is managed separately, and are retrieved into
**MoltenVK** as submodule repositories.

If you used the `--recursive` option when cloning this repository, as described 
[above](#install), all third party libraries will have been retrieved.

If you did not use the `--recursive` option when cloning this repository, you can retrieve 
and install these libraries into your `MoltenVK` repository environment as follows from within
the `MoltenVK` repository:

	git submodule update --init --recursive
	cd External
	./makeAll


<a name="update_third-party"></a>
###Updating the Third-Party Library Versions

If you are developing enhancements to **MoltenVK**, you can update the versions of the 
Third-Party libraries used by **MoltenVK** to the latest versions available by re-cloning 
and re-building the submodules using the `getLatestAll` script:

	cd External
	./getLatestAll

The updated versions will then be "locked in" the next time the `MoltenVK` repository is committed to `git`.

This procdure updates all of the Third-Party library submodules. To update only a single submodule,
or for more information about the various Third-Party libraries and submodules used by **MoltenVK**,
please refer to the following documents:

- [`MoltenVK/ThirdPartyConfig.md`](MoltenVK/ThirdPartyConfig.md)
- [`MoltenVKShaderConverter/ThirdPartyConfig.md`](MoltenVKShaderConverter/ThirdPartyConfig.md)



<a name="building"></a>
Building **MoltenVK**
-------------------

>***Note:*** Before attempting to build **MoltenVK**, be sure you have followed the 
instructions in the [*Third-Party Components*](#third-party) section above to retrieve 
and install the required third-party components.

>***Note:*** At runtime, **MoltenVK** can run on *iOS 9* and *macOS 11.0* devices, 
>but it does reference advanced OS frameworks during building. *Xcode 9* 
>or above is required to build **MoltenVK**, and build and link **MoltenVK** projects.

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

Once you have built the **MoltenVK** runtime distribution package, the **MoltenVK** demo apps can be 
accessed from the `Demos/Demos.xcworkspace` *Xcode* workspace. This is the same workspace that is 
included in the **MoltenVK** runtime distribution package, and you can use it to build and run the
**MoltenVK** demo apps, or to add new demos to this **MoltenVK** repository.



<a name="using"></a>
Using **MoltenVK** in Your Application
--------------------------------------

Once you have compiled and built the **MoltenVK** runtime distribution package from this **MoltenVK** 
repository, as described in the [previous section](#building), follow the instructions in the installation 
section of the [**MoltenVK Runtime User Guide**](Docs/MoltenVK_Runtime_UserGuide.md#install) document in the
`Docs` directory of the **MoltenVK** runtime distribution package found in the `Package/Latest` directory,
to link the **MoltenVK** frameworks and libraries in the `Package/Latest` directory to your application.

The runtime distribution package in the `Package/Latest` directory is a stand-alone package, and you can copy 
the contents of that directory out of this **MoltenVK** repository into your own application building environment.



<a name="credits"></a>
Third-Party Credits
-------------------

**MoltenVK** uses technology from the following open-source frameworks:

- [*Vulkan-Hpp*](https://github.com/KhronosGroup/Vulkan-Hpp)
- [*Vulkan-Docs*](https://github.com/KhronosGroup/Vulkan-Docs)
- [*Vulkan-LoaderAndValidationLayers*](https://github.com/KhronosGroup/Vulkan-LoaderAndValidationLayers)
- [*tinyxml2*](https://github.com/leethomason/tinyxml2)

**MoltenVKShaderConverter** uses technology from the following open-source frameworks:

- [*SPIRV-Cross*](https://github.com/KhronosGroup/SPIRV-Cross)
- [*SPIRV-Tools*](https://github.com/KhronosGroup/SPIRV-Tools)
- [*glslang*](https://github.com/KhronosGroup/glslang)
