<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="../Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



#MoltenVK Demo Projects

Copyright (c) 2015-2020 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format.
For best results, use a Markdown reader.*



Table of Contents
-----------------

- [LunarG Vulkan Samples](#lunarg-vulkan-samples)
	- [*Cube*](#lunarg-vulkan-samples-cube)
	- [*Hologram*](#lunarg-vulkan-samples-hologram)
	- [*API-Samples*](#lunarg-vulkan-samples-api)
- [Sascha Willems Vulkan Samples](#sascha-willems-vulkan-samples)
	- [Installing the *Sascha Willems* Library](#sascha-willems-install)
- [Cinder Vulkan Samples](#cinder-vulkan-samples)
	- [Installing the *Cinder* Library](#cinder-install)
	- [*Fish Tornado*](#cinder-vulkan-samples-fish-tornado)



<a name="lunarg-vulkan-samples"></a>
LunarG Vulkan Samples
---------------------

[LunarG](https://lunarg.com), who have been involved in *Vulkan* development from the
beginning, and are one of the original developers of *Vulkan* tools and SDK's, provides
a suite of demo apps, that demonstrate a wide range of basic *Vulkan* features.

These demo apps are included in **MoltenVK**, and can be found in the `LunarG-VulkanSamples` 
folder of this `Demos` folder, and in the `LunarG-VulkanSamples` group in the *Xcode Project Navigator*
in the `Demos.xcworkspace` *Xcode* workspace.


<a name="lunarg-vulkan-samples-cube"></a>
### *Cube*

A basic textured cube that spins in place.

The demo can be found in the `LunarG-VulkanSamples/Cube` folder, and in the 
`LunarG-VulkanSamples/Cube` group in the *Xcode Project Navigator* in the 
`Cube.xcworkspace` *Xcode* workspace.

To run this demo, run the `Cube-iOS`, `Cube-tvOS`, or `Cube-macOS` *Scheme* from within *Xcode*. 
In addition to devices, this demo will also run on the `iOS Simulator` or `tvOS Simulator` destinations.

The *macOS* version of this demo includes a sizable window, and represents an example of how to detect,
within your *Vulkan* code, when a window has been resized, and to modify the *Vulkan* swapchain accordingly.

The `Cube` demo is a simple example of installing **MoltenVK** as an `XCFramework` that is 
statically linked to the application. It supports all platforms, including _Mac Catalyst_, _iOS
Simulator_ and _tvOS Simulator_, and all architectures including _Apple Silicon_.


<a name="lunarg-vulkan-samples-hologram"></a>
### *Hologram*

> **_Note:_** In order to build the `Hologram` demo, you must have *Python3* installed
> on your build computer.

This is a sophisticated particle demo that populates command buffers from multiple threads.

This demo can be found in the `LunarG-VulkanSamples/Hologram` folder, and in the 
`LunarG-VulkanSamples/Hologram` group in the *Xcode Project Navigator* in the 
`Demos.xcworkspace` *Xcode* workspace.

To run this demo, run either the `Hologram-iOS` or `Hologram-macOS` *Scheme* from within *Xcode*.

On *macOS*, once the demo is open, you can use the *Up-arrow* and *Down-arrow* keys on the 
keyboard to zoom the camera in and out of the scene. Zooming out will show more items on screen.

The demo allows some customization, by modifying the arguments passed to the demo at startup.
To customize, modify the arguments created in the `DemoViewController viewDidLoad` method
found in the `iOS/DemoViewController.mm` or `macOS/DemoViewController.mm` file.

The `Hologram` demo is a simple example of installing **MoltenVK** as a *dynamic library* that is 
dynamically linked to the application. In this demo, the **MoltenVK** *dynamic library* is copied 
into and embedded in the application, but it could have been installed as a system library instead.


<a name="lunarg-vulkan-samples-api"></a>
### *API-Samples*

This *Xcode* project contains a large number of modular demos, with each demo
demonstrating a particular *Vulkan* feature, or suite of calls.

This demo can be found in the `LunarG-VulkanSamples/API-Samples` folder, and in the 
`LunarG-VulkanSamples/API-Samples` group in the *Xcode Project Navigator* in the 
`Demos.xcworkspace` *Xcode* workspace.

Each of the `API-Samples` demos loads *SPIR-V* shader code from a file. Before any of the 
`API-Samples` demos are run, these *SPIR-V* files need to be generated as follows:

	cd MoltenVK/Demos/LunarG-VulkanSamples/API-Samples
	./generateSPIRVShaders
 
You only need to do this step once. It generates the *SPIR-V* shader code files for
all of the `API-Samples` demos.

To run any of the `API-Samples` demos, run either the `API-Samples-iOS` or `API-Samples-macOS` 
*Scheme* from within *Xcode*.

To specify which of the many modular demos to run, open the `Samples.h` in the `API-Samples`
project in the *Xcode Project Navigator* in the `Demos.xcworkspace` *Xcode* workspace, and
follow the instructions in the comments within that file.

> **_Note:_** For simplicity, the `API-Samples` demos are bare-bones. Each of the `API-Samples` 
> demos renders a single frame during app startup, and then leaves the rendered image static. 
> There is no display loop or motion in any of these demos.
> **This is normal for these demos, and the demo has not "hung" or "crashed" when this occurs.**

To see descriptions and screenshots of each of the demos, open 
[this summary document](LunarG-VulkanSamples/VulkanSamples/samples_index.html#AdditionalVulkan).

The `API-Samples` demo is a simple example of installing **MoltenVK** as an `XCFramework` that 
is statically linked to the application. It supports all platforms, including _Mac Catalyst_, _iOS
Simulator_ and _tvOS Simulator_, and all architectures including _Apple Silicon_.



<a name="sascha-willems-vulkan-samples"></a>
Sascha Willems Vulkan Samples
-----------------------------

[*Sascha Willems*](https://github.com/brenwill/Vulkan) provides an open-source library containing 
a large number of sophisticated *Vulkan* samples. The library contains support for running these
examples on *iOS* and *macOS* in *Xcode*, using **MoltenVK**.


<a name="sascha-willems-install"></a>
### Installing the *Sascha Willems* Library

To install the *Sascha Willems Vulkan* samples, open a *Terminal* session and perform 
the following command-line steps:

1. In the parent directory of this `MoltenVK` repository, clone the modified *Sascha Willems* `Vulkan` repo:

		git clone https://github.com/brenwill/Vulkan.git

2. By default, the *Sascha Willems Vulkan* samples expect **MoltenVK** to be installed in a directory
   beside the `Vulkan` repository:
   
		Vulkan/
   		MoltenVK/
  
    If you have installed **MoltenVK** somewhere else, create a symlink to your **MoltenVK** installation:
   
		ln -sfn path-to-MoltenVK/MoltenVK

2. Follow the instructions in the `Vulkan\xcode\README_MoltenVK_Examples.md` document
   within the *Sascha Willems* `Vulkan` repository.



<a name="cinder-vulkan-samples"></a>
Cinder Vulkan Samples
---------------------

[*Cinder*](https://libcinder.org) is a cross-platform 3D graphics engine built in C++. 
*Cinder* supports *Vulkan*, and includes several *Vulkan* demos.

These demo apps are included as part of the *Cinder* code repository.

These **MoltenVK** demos use a modified version of *Cinder*, that allows *Vulkan* to run under 
*iOS* and *macOS*. To download the modified version of *Cinder*, and link it to **MoltenVK**, 
follow the instructions in the [Installing the *Cinder* Library](#cinder-install) 
section next.


<a name="cinder-install"></a>
### Installing the *Cinder* Library

To install the modified *Cinder* library, and link it to **MoltenVK**,
open a *Terminal* session and perform the following command-line steps:

1. In the parent directory of this `MoltenVK` repository, clone the modified `Cinder` repo, 
   including required submodules:

		git clone --recursive https://github.com/brenwill/Cinder.git

2. Build the core *Cinder* library:

		Cinder/xcode/fullbuild.sh

3. By default, the *Cinder Vulkan* samples expect **MoltenVK** to be installed in a directory
   beside the `Cinder` repository:
   
		Cinder/
   		MoltenVK/

    If you have installed **MoltenVK** somewhere else, create a symlink to your **MoltenVK** installation:
   
		ln -sfn path-to-MoltenVK/MoltenVK



<a name="cinder-vulkan-samples-fish-tornado"></a>
### *Fish Tornado*

This is a sophisticated simulation of a *Fish Tornado*, a swirling school of thousands of fish.

This demo can be found in the `samples/_vulkan_explicit/FishTornado` folder of the *Cinder* repository.
To build and run this demo for either *iOS* or *macOS*, open the `xcode-ios/FishTornado.xcodeproj` 
or `xcode/FishTornado.xcodeproj` *Xcode* project, respectively.

