<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="../Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



#MoltenVK Demo Projects

Copyright (c) 2014-2018 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format.
For best results, use a Markdown reader.*



Table of Contents
-----------------

- [Introduction](#intro)
- [LunarG Vulkan Samples](#lunarg-vulkan-samples)
	- [Installing the LunarG `VulkanSamples` Library](#lunarg-vulkan-samples-install)
	- [*Demos*](#lunarg-vulkan-samples-demos)
	- [*API-Samples*](#lunarg-vulkan-samples-api)
	- [*Hologram*](#lunarg-vulkan-samples-hologram)
- [Khronos Vulkan Samples](#khronos-vulkan-samples)
	- [Installing the Khronos `Vulkan-Samples` Library](#khronos-vulkan-samples-install)
	- [*AsynchronousTimeWarp*](#khronos-vulkan-samples-atw)
- [Sascha Willems Vulkan Samples](#sascha-willems-vulkan-samples)
	- [Installing the *Sascha Willems* Library](#sascha-willems-install)
- [Cinder Vulkan Samples](#cinder-vulkan-samples)
	- [Installing the *Cinder* Library](#cinder-install)
	- [*Fish Tornado*](#cinder-vulkan-samples-fish-tornado)


<a name="intro"></a>
Introduction
------------

The *Xcode* projects in this folder are a set of demo applications that demonstrate
how to integrate *Vulkan* into an *Xcode* project, and demonstrate the features and
capabilities of *Vulkan* when using using **MoltenVK** on the *iOS* and *macOS* platforms.

Although the demo projects are provided with this `MoltenVK` distribution,
the source code and resources for the demo applications come from publicly-available
open-source repositories. Follow the instructions for each section below to learn
how to download the demo application source code and resources for each set of
demo applications.

To review and run all of the available demo apps, open the `Demos.xcworkspace` 
*Xcode* workspace in *Xcode*.



<a name="lunarg-vulkan-samples"></a>
LunarG Vulkan Samples
---------------------

[LunarG](https://lunarg.com), who have been involved in *Vulkan* development from the
beginning, and are one of the original developers of *Vulkan* tools and SDK's, provides
a suite of demo apps, that demonstrate a wide range of basic *Vulkan* features.

These demo apps can be found in the `LunarG-VulkanSamples` folder of this `Demos`
folder, and in the `LunarG-VulkanSamples` group in the *Xcode Project Navigator*
in the `Demos.xcworkspace` *Xcode* workspace.

These **MoltenVK** demos use a modified version of the *LunarG Vulkan Samples*, that allows
the demo apps to run under *iOS* and *macOS*. To download these modified *LunarG Vulkan Samples*, 
and link them to the demo *Xcode* projects in this `MoltenVK` distribution, follow the instructions
in the [Installing the LunarG `VulkanSamples` Library](#lunarg-vulkan-samples-install) section next.


<a name="lunarg-vulkan-samples-install"></a>
###Installing the LunarG *VulkanSamples* Library

To run the *LunarG Vulkan Samples* demo apps, **MoltenVK** uses a modified version of the
*LunarG* `VulkanSamples` library. To install this modified *LunarG* `VulkanSamples` library, 
open a *Terminal* session and perform the following command-line steps:

1. In a folder outside this `MoltenVK` distribution, clone the modified `VulkanSamples` repo:

		git clone https://github.com/brenwill/VulkanSamples.git

2. In the `MoltenVK/Demos/LunarG-VulkanSamples` folder, replace the `VulkanSamples` symlink as follows:

		ln -sfn path-to-VulkanSamples-repo-folder VulkanSamples

3. Run the `MoltenVKShaderConverter` tool to convert the *GLSL* shaders in the `VulkanSamples`
   library to *SPIR-V*:
   
		cd path-to-MoltenVK-package 
		MoltenVKShaderConverter/Tools/MoltenVKShaderConverter -gi -so -xs "-" -d Demos/LunarG-VulkanSamples/VulkanSamples/demos


<a name="lunarg-vulkan-samples-demos"></a>
###LunarG Vulkan Samples: *Demos*

This demo is a simple renderings that originally were included in the *Vulkan* SDK.

The demo can be found in the `MoltenVK/Demos/LunarG-VulkanSamples/Demos` folder, 
and in the `LunarG-VulkanSamples/Demos` group in the *Xcode Project Navigator* 
in the `Demos.xcworkspace` *Xcode* workspace.

####Cube

A basic textured cube that spins in place.

To run this demo, run either the `Cube-iOS` or `Cube-macOS` *Scheme* from within *Xcode*.

This demo is a simple example of installing **MoltenVK** as a dynamic library, instead of as
a statically-linked framework. In this demo, the **MoltenVK** dynamic library is embedded in 
the application, but it could have been installed as a system library instead.



<a name="lunarg-vulkan-samples-api"></a>
###LunarG Vulkan Samples: *API-Samples*

This *Xcode* project actually contains a large number of modular demos, with each demo
demonstrating a particular *Vulkan* feature, or suite of calls.

> **Note:** For simplicity, the `API-Samples` demos are bare-bones. Each of the `API-Samples` 
> demos renders a single frame during app startup, and then leaves the rendered image static. 
> There is no display loop or motion in any of these demos.
> **This is normal for these demos, and the demo has not "hung" or "crashed" when this occurs.**

This demo can be found in the `MoltenVK/Demos/LunarG-VulkanSamples/API-Samples` folder, 
and in the `LunarG-VulkanSamples/API-Samples` group in the *Xcode Project Navigator* in 
the `Demos.xcworkspace` *Xcode* workspace.

To run this demo, run either the `API-Samples-iOS` or `API-Samples-macOS` *Scheme* from within *Xcode*.

To specify which of the many modular demos to run, open the `Samples.h` in the `API-Samples`
project in the *Xcode Project Navigator* in the `Demos.xcworkspace` *Xcode* workspace, and
follow the instructions in the comments within that file.

To see descriptions and screenshots of each of the demos, open 
[this summary document](LunarG-VulkanSamples/VulkanSamples/samples_index.html#AdditionalVulkan),
after you have [installed](#lunarg-vulkan-samples-install) the `LunarG Vulkan Samples` repository.


<a name="lunarg-vulkan-samples-hologram"></a>
###LunarG Vulkan Samples: *Hologram*

> **Note:** In order to build the `Hologram` demo, you must have *Python3* installed
> on your build computer.

This is a sophisticated particle demo that populates command buffers from multiple threads.

This demo can be found in the `MoltenVK/Demos/LunarG-VulkanSamples/Hologram` folder, and in the 
`LunarG-VulkanSamples/Hologram` group in the *Xcode Project Navigator* in the `Demos.xcworkspace` 
*Xcode* workspace.

To run this demo, run either the `Hologram-iOS` or `Hologram-macOS` *Scheme* from within *Xcode*.

On *macOS*, once the demo is open, you can use the *Up-arrow* and *Down-arrow* keys on the 
keyboard to zoom the camera in and out of the scene. Zooming out will show more items on screen.

The demo allows some customization, by modifying the arguments passed to the demo at startup.
To customize, modify the arguments created in the `DemoViewController viewDidLoad` method
found in the `iOS/DemoViewController.mm` or `macOS/DemoViewController.mm` file.

This demo illustrates the use of the **MoltenVK** API `vkGetMoltenVKDeviceConfigurationMVK()` 
and `vkSetMoltenVKDeviceConfigurationMVK()` functions to enable **MoltenVK** debugging, including
logging the conversion of shaders from *SPIR-V* to *Metal Shading Language*. See the use of these
functions in the `Hologram/Hologram.cpp` file. To see the effect, modify the `Hologram-iOS` or 
`Hologram-macOS` *Scheme* from within *Xcode* to use the **Debug** *Build Configuration* setting.



<a name="khronos-vulkan-samples"></a>
Khronos Vulkan Samples
----------------------

[Khronos](https://khronos.org), the standards organization that developed *Vulkan* provides
a suite of demo apps, that demonstrate a range of sophisticated *Vulkan* features.

These demo apps can be found in the `Khronos-Vulkan-Samples` folder of this `Demos`
folder, and in the `Khronos-Vulkan-Samples` group in the *Xcode Project Navigator*
in the `Demos.xcworkspace` *Xcode* workspace.

These **MoltenVK** demos use a modified version of the *Khronos Vulkan Samples*, that allows
the demo apps to run under *iOS* and *macOS*. To download these modified *Khronos Vulkan Samples*, 
and link them to the demo *Xcode* projects in this `MoltenVK` distribution, follow the instructions
in the [Installing the Khronos `Vulkan-Samples` Library](#khronos-vulkan-samples-install) section next.


<a name="khronos-vulkan-samples-install"></a>
###Installing the Khronos `Vulkan-Samples` Library

To run the *Khronos Vulkan Samples* demo apps, **MoltenVK** uses a modified version of the
*Khronos* `Vulkan-Samples` library. To install this modified *Khronos* `Vulkan-Samples` library,
open a *Terminal* session and perform the following command-line steps:

1. In a folder outside this `MoltenVK` distribution, clone the modified `Vulkan-Samples` repo:

		git clone https://github.com/brenwill/Vulkan-Samples.git

2. In the `MoltenVK/Demos/Khronos-Vulkan-Samples` folder, replace the `Vulkan-Samples` symlink as follows:

		ln -sfn path-to-Vulkan-Samples-repo-folder Vulkan-Samples


<a name="khronos-vulkan-samples-atw"></a>
###Khronos Vulkan Samples: *AsynchronousTimeWarp*

This demo was contributed by *Oculus VR, LLC*, and demonstrates a variety of critical tests for
evaluating accurate synchronization between the two scene images in a virtual reality headset.

This demo can be found in the `MoltenVK/Demos/Khronos-Vulkan-Samples/AsynchronousTimeWarp` folder, 
and in the `Khronos-Vulkan-Samples/AsynchronousTimeWarp` group in the *Xcode Project Navigator* 
in the `Demos.xcworkspace` *Xcode* workspace.

You can make a large number of configuration changes to this demo, to increase or decrease the
rendering and computational load of the scene. You can set these configuration values by passing
command-line arguments to the demo at start-up. You pass these command-line arguments by setting
them in the `Arguments` tab of the `AsynchronousTimeWarp-VK-iOS` or `AsynchronousTimeWarp-VK-macOS`
*Xcode* schemes.

For example, the following command-line arguments can be used to set the scene complexity: 

- `-q [0-3]`  :  controls whether a minimal, small, medium, or large quantity of objects
                 will be rendered.
- `-w [0-3]`  :  controls whether each object will be rendered with a minimal, small, 
                 medium, or large quantity of triangles.
- `-e [0-3]`  :  controls whether a minimal, small, medium, or large number of lights
                 will be used to illuminate the scene.

On *macOS*, once the demo is open, you can also tap the `Q`, `W`, or `E` keys on the keyboard 
to cycle each of these same configuration parameters through their range of possible values.

For the full instructions for this demo, including a list and explanation of all of 
the configuration options, read the notes at the top of the `atw/atw_vulkan.c` file.

This demo illustrates the use of the **MoltenVK** API `vkGetMoltenVKDeviceConfigurationMVK()` 
and `vkSetMoltenVKDeviceConfigurationMVK()` functions to enable performance tracking and logging,
and to enable **MoltenVK** debugging, including logging the conversion of shaders from *SPIR-V* 
to *Metal Shading Language*. See the use of these functions in the `atw/atw_vulkan.c` file. 
To see the effect of shader conversion logging, modify the `AsynchronousTimeWarp-VK-iOS` or 
`AsynchronousTimeWarp-VK-macOS` *Scheme* from within *Xcode* to use the 
**Debug** *Build Configuration* setting.



<a name="sascha-willems-vulkan-samples"></a>
Sascha Willems Vulkan Samples
-----------------------------

[*Sascha Willems*](https://github.com/brenwill/Vulkan) provides an open-source library containing 
a large number of sophisticated *Vulkan* examples. The library contains support for running these
examples on *iOS* and *macOS* in *Xcode*, using **MoltenVK**.


<a name="sascha-willems-install"></a>
###Installing the *Sascha Willems* Library

To install the *Sascha Willems Vulkan* samples, open a *Terminal* session and perform 
the following command-line steps:

1. In a folder outside this `MoltenVK` distribution, clone the modified *Sascha Willems* `Vulkan` repo:

		git clone https://github.com/brenwill/Vulkan.git

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
follow the instructions in the [Installing the `Cinder` Library](#cinder-vulkan-samples-install) 
section next.


<a name="cinder-install"></a>
###Installing the *Cinder* Library

To run the *Cinder Vulkan Samples* demo apps, **MoltenVK** uses a modified version of the
*Cinder* library. To install this modified *Cinder* library, and link it to **MoltenVK**,
open a *Terminal* session and perform the following command-line steps:

1. In a folder outside this `MoltenVK` distribution, clone the modified `Cinder` repo, 
   including required submodules:

		git clone --recursive https://github.com/brenwill/Cinder.git

2. Build the core *Cinder* library:

		Cinder/xcode/fullbuild.sh

3. By default, the *Cinder Vulkan* samples expect **MoltenVK** to be installed in a directory
   beside the `Cinder` repository:
   
		Cinder/
   		MoltenVK/

   
    If you have installed **MoltenVK** somewhere else, you can redirect the *Cinder Vulkan*
    samples to the location of your **MoltenVK** installation as follows:
   
		cd Cinder/samples/_vulkan_explicit
		ln -sfn path-to-the-MoltenVK-distribution/MoltenVK



<a name="cinder-vulkan-samples-fish-tornado"></a>
###Cinder Vulkan Samples: *Fish Tornado*

This is a sophisticated simulation of a *Fish Tornado*, a swirling school of thousands of fish.

This demo can be found in the `samples/_vulkan_explicit/FishTornado` folder of the *Cinder* repository.
To build and run this demo for either *iOS* or *macOS*, open the `xcode-ios/FishTornado.xcodeproj` 
or `xcode/FishTornado.xcodeproj` *Xcode* project, respectively.

