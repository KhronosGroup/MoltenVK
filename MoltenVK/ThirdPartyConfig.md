<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="../Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>

Copyright (c) 2014-2017 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format.
For best results, use a Markdown reader.*


Table of Contents
-----------------

- *Vulkan-Hpp*
	- [Using the *Vulkan-Hpp* Spec Repository with **MoltenVK**](#install_vulkan_spec)
	- [Updating the *Vulkan-Hpp* library version](#update_vulkan_spec)

- *Vulkan-LoaderAndValidationLayers*
	- [Using the *Vulkan-LoaderAndValidationLayers* Repository with **MoltenVK**](#install_vulkan_lvl)
	- [Updating the *Vulkan-LoaderAndValidationLayers* library version](#update_vulkan_lvl)


<a name="install_vulkan_spec"></a>
Using the *Vulkan-Hpp* Spec Repository with *MoltenVK*
------------------------------------------------------

**MoltenVK** uses the official *Khronos Vulkan* specification repository to provide the standard
*Vulkan* API header files and *Vulkan Specification* documentation.

To add the *Khronos Vulkan* specification repository to **MoltenVK**, open a *Terminal* 
session and perform the following command-line steps:

1. Ensure you have `python3` and `asciidoctor` installed:

		brew install python3
		sudo gem install asciidoctor

2. If you used the `--recursive` option when cloning the `MoltenVK` repository, you should already 
   have the `Vulkan-Hpp` submodule, and you can skip to *Step 3* below. If you did **_not_** 
   use the `--recursive` option when cloning the `MoltenVK` repository, retrieve the `Vulkan-Hpp` 
   submodule into the `External` directory as follows, from within the `MoltenVK` repository directory:

		git submodule update --init --recursive External/Vulkan-Hpp

3. In the `Externals` folder within the `MoltenVK` repository, build the spec and header files 
   as follows from the main directory of this `MoltenVK` repository:

		cd External
		./makeVulkanSpec



<a name="update_vulkan_spec"></a>
Updating the *Vulkan-Hpp* library version
-----------------------------------------

If you are developing enhancements to **MoltenVK**, you can update the version of `Vulkan-Hpp` 
used by **MoltenVK** to the latest version available by re-cloning and re-building the
`Vulkan-Hpp` submodule using the `getLatestVulkanSpec` script:

	cd External
	./getLatestVulkanSpec

The updated version will then be "locked in" the next time the `MoltenVK` repository is committed to `git`.



<a name="install_vulkan_lvl"></a>
Using the *Vulkan-LoaderAndValidationLayers* Spec Repository with *MoltenVK*
----------------------------------------------------------------------------

**MoltenVK** uses the *Khronos Vulkan Loader and Validation Layers* repository to allow **MoltenVK** 
to act as an *Installable Client Driver* to support the *Vulkan Loader API*.

If you used the `--recursive` option when cloning the `MoltenVK` repository, you should already
have the `Vulkan-LoaderAndValidationLayers` submodule. If you did **_not_** use the `--recursive` 
option when cloning the `MoltenVK` repository, retrieve the `Vulkan-LoaderAndValidationLayers` 
submodule into the `External` directory as follows, from within the `MoltenVK` repository directory:

	git submodule update --init External/Vulkan-LoaderAndValidationLayers



<a name="update_vulkan_lvl"></a>
Updating the *Vulkan-LoaderAndValidationLayers* library version
---------------------------------------------------------------

If you are developing enhancements to **MoltenVK**, you can update the version of `Vulkan-LoaderAndValidationLayers` 
used by **MoltenVK** to the latest version available by re-cloning and re-building the `Vulkan-LoaderAndValidationLayers` 
submodule using the `getLatestVulkanLVL` script:

	cd External
	./getLatestVulkanLVL

The updated version will then be "locked in" the next time the `MoltenVK` repository is committed to `git`.

