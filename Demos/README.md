<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="../Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>



#MoltenVK Demo Projects

Copyright (c) 2015-2021 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

[comment]: # "This document is written in Markdown (http://en.wikipedia.org/wiki/Markdown) format."
[comment]: # "For best results, use a Markdown reader."



Table of Contents
-----------------

- [*Cube*](#vulkan-tools-cube)
- [Khronos Vulkan-Samples](#khronos-vulkan-samples)


<a name="vulkan-tools-cube"></a>
*Cube*
------

The basic canonical *Cube* sample app from the 
[*Vulkan-Tools* repository](https://github.com/KhronosGroup/Vulkan-Tools) 
is included in this **MoltenVK** package.

This demo renders a basic textured cube that spins in place.

The demo can be found in the `Cube` folder, and in the `Cube` group in the 
*Xcode Project Navigator* in the `Demos.xcworkspace` *Xcode* workspace.

To run this demo, run the `Cube-iOS`, `Cube-tvOS`, or `Cube-macOS` *Scheme* from within *Xcode*. 
In addition to devices, this demo will also run on the `iOS Simulator` or `tvOS Simulator` destinations.

The `Cube` demo is a simple example of installing **MoltenVK** as an `XCFramework` that is 
statically linked to the application. It supports all platforms, including _Mac Catalyst_, _iOS
Simulator_ and _tvOS Simulator_, and all architectures including _Apple Silicon_.



<a name="khronos-vulkan-samples"></a>
*Khronos Vulkan Samples*
----------------------

*Khronos Group* provides a [repository](https://github.com/KhronosGroup/Vulkan-Samples) 
containing a full suite of standard *Vulkan* samples that run on **MoltenVK** on *macOS*.
