<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="../Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>


#MoltenVK External Dependencies

Copyright (c) 2015-2021 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

[comment]: # "This document is written in Markdown (http://en.wikipedia.org/wiki/Markdown) format."
[comment]: # "For best results, use a Markdown reader."



Table of Contents
-----------------

- [Fetching and Building External Libraries](#fetching)
- [Updating External Library Versions](#updating)
- [Adding the *cereal* Library to the *MoltenVK Xcode* Project](#add_cereal)
- [Adding the *SPIRV-Cross* Library to the *ExternalDependencies Xcode* Project](#add_spirv-cross)
- [Adding the *SPIRV-Tools* Library to the *ExternalDependencies Xcode* Project](#add_spirv-tools)
- [Adding the *glslang* Library to the *ExternalDependencies Xcode* Project](#add_glslang)



<a name="fetching"></a>
Fetching and Building External Libraries
----------------------------------------

**MoltenVK** uses technology from the following external open-source libraries:

- [*cereal*](https://github.com/USCiLab/cereal)
- [*Vulkan-Headers*](https://github.com/KhronosGroup/Vulkan-Headers)
- [*SPIRV-Cross*](https://github.com/KhronosGroup/SPIRV-Cross)
- [*glslang*](https://github.com/KhronosGroup/glslang)
- [*SPIRV-Tools*](https://github.com/KhronosGroup/SPIRV-Tools)
- [*SPIRV-Headers*](https://github.com/KhronosGroup/SPIRV-Headers)
- [*Vulkan-Tools*](https://github.com/KhronosGroup/Vulkan-Tools)
- [*VulkanSamples*](https://github.com/LunarG/VulkanSamples)

These external open-source libraries are maintained in the `External` directory.
To retrieve and build these libraries from their sources, run the `fetchDependencies`
script in the main repository directory:

	./fetchDependencies --all [--debug]

The `--debug` option will build the external libraries in Debug mode, which may
be useful when debugging and tracing calls into those libraries.


<a name="updating"></a>
Updating External Library Versions
----------------------------------

To maintain consistency between the libraries, **MoltenVK** retrieves specific 
versions of each external library. The version of each external library is 
determined as follows:

- **_cereal_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/cereal_repo_revision` file. 
  
- **_Vulkan-Headers_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/Vulkan-Headers_repo_revision` file.

- **_SPIRV-Cross_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/SPIRV-Cross_repo_revision` file. 
  
- **_glslang_**: a GitHub repository commit identifier found
  in the `ExternalRevisions/glslang_repo_revision` file.
  
- **_SPIRV-Tools_**: automatically retrieved by the *glslang* repository.

- **_SPIRV-Headers_**: automatically retrieved by the *glslang* repository.
  
- **_Vulkan-Tools_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/Vulkan-Tools_repo_revision` file.
  
- **_VulkanSamples_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/VulkanSamples_repo_revision` file.
  
You can update which versions of the *cereal*, *Vulkan-Headers*, *SPIRV-Cross*, 
*glslang*, *Vulkan-Tools*, or *VulkanSamples* libraries are retrieved by changing 
the value held in the corresponding `*_repo_revision` file listed above.

The version of the *SPIRV-Tools* and *SPIRV-Headers* libraries is automatically 
determined by the version of the *glslang* library you have retrieved.

Once you have made changes to the `*_repo_revision` files, you can retrieve the updated 
library versions by running the `fetchDependencies` script, as described above, again.

>***Note:*** If, after updating to new versions of the external libraries, you encounter 
>build errors when building **MoltenVK**, review the instructions in the sections below 
>to ensure all necessary external library files are included in the **MoltenVK** builds.



<a name="add_cereal"></a>
Adding the *cereal* Library to the *MoltenVK Xcode* Project
-----------------------------------------------------------

The `MoltenVK` *Xcode* project is already configured to use the *cereal* library. However, after 
updating the version of *cereal*, as described [above](#updating), if you encounter any building 
errors, you may need to re-add the *cereal* library to the `MoltenVK` *Xcode* project as follows:

1. In the *Project Navigator* panel, select the `MoltenVK` *Xcode* project, then the `MoltenVK`
   project target, and open the *Build Settings* tab. Locate the build setting entry 
   **Header Search Paths** (`HEADER_SEARCH_PATHS`) and add the following paths:
   
		"$(SRCROOT)/../External/cereal/include"


<a name="add_spirv-cross"></a>
Adding the *SPIRV-Cross* Library to the *ExternalDependencies Xcode* Project
----------------------------------------------------------------------------

The `ExternalDependencies` *Xcode* project is already configured to use the *SPIRV-Cross*
library. However, after updating the version of *SPIRV-Cross*, as described [above](#updating),
if you encounter any building errors, you may need to re-add the *SPIRV-Cross* library to the
`ExternalDependencies` *Xcode* project as follows:

1. In the *Project Navigator*, remove all of the files under the *Group* named 
   `External/SPIRV-Cross`.

2. Drag the following files from the `External/SPIRV-Cross` directory to the `External/SPIRV-Cross` 
   group in the *Project Navigator* panel:

		spirv_cfg.cpp
		spirv_cfg.hpp
		spirv_common.hpp
		spirv_cross_parsed_ir.cpp
		spirv_cross_parsed_ir.hpp
		spirv_cross.cpp
		spirv_cross.hpp
		spirv_glsl.cpp
		spirv_glsl.hpp
		spirv_msl.cpp
		spirv_msl.hpp
		spirv_parser.cpp
		spirv_parser.hpp

   In the ***Choose options for adding these files*** dialog that opens, select the ***Create groups*** option, 
   add the files to *all* of the `SPIRV-Cross-macOS`, `SPIRV-Cross-iOS`, and `SPIRV-Cross-tvOS` targets, 
   and click the ***Finish*** button.


### Regression Testing Your Changes to *SPIRV-Cross*

The *SPIRV-Cross* library plays an important part in providing features for **_MoltenVK_**, and if 
you are developing features for **_MoltenVK_**, you may end up making changes to *SPIRV-Cross*. 

If you make changes to the `SPIRV-Cross` repository, you can build a new version of the `libSPIRVCross.a`
static library by opening the `ExternalDependencies.xcodeproj` *Xcode* project, and running the 
**_ExternalDependencies_** *Xcode* scheme. You can then rebuild **MoltenVK** to include the new library.

While makng changes to the `SPIRV-Cross` repository, you can regression test your changes using the
following steps:

1. Load and build the versions of `SPRIV-Tools` and `glslang` that are used by the `SPIRV-Cross` tests:

		cd External/SPIRV-Cross
		./checkout_glslang_spirv_tools.sh
		./build_glslang_spirv_tools.sh

2. Build `SPIRV-Cross`:

		make

3. Run the regression tests:

		./test_shaders.sh



<a name="add_spirv-tools"></a>
Adding the *SPIRV-Tools* Library to the *ExternalDependencies Xcode* Project
----------------------------------------------------------------------------

The `ExternalDependencies` *Xcode* project is already configured to use the *SPIRV-Tools*
library. However, after updating the version of *glslang* (which adds *SPIRV-Tools*), 
as described [above](#updating), if you encounter any building errors, you may need to re-add 
the *SPIRV-Tools* library to the `ExternalDependencies` *Xcode* project as follows:

1. In the *Project Navigator* panel, select the `ExternalDependencies` *Xcode* project, then 
   select the `SPIRV-Tools-macOS` target, and open the *Build Settings* tab. Locate the build 
   setting entry **Header Search Paths** (`HEADER_SEARCH_PATHS`) and add the following paths:

		$(inherited) 
		"$(SRCROOT)/External/glslang/External/spirv-tools/"
		"$(SRCROOT)/External/glslang/External/spirv-tools/include"
		"$(SRCROOT)/External/glslang/External/spirv-tools/external/spirv-headers/include"
		"$(SRCROOT)/External/glslang/External/spirv-tools/build"

2. Repeat *Step 1* for the `SPIRV-Tools-iOS` target within the `ExternalDependencies` *Xcode* project

3. In the *Project Navigator*, remove the *Group* named `source` from under the *Group* named
   `External/SPIRV-Tools`.

4. Drag the `External/glslang/External/spirv-tools/source` file folder to the `External/SPIRV-Tools` 
   group in the *Project Navigator* panel. In the _**Choose options for adding these files**_ dialog 
   that opens, select the _**Create groups**_ option, add the files to *all* of the `SPIRV-Tools-macOS`, 
   `SPIRV-Tools-iOS`, and `SPIRV-Tools-tvOS` targets, and click the ***Finish*** button.

5. Remove the *Group* named `fuzz` from under the *Group* named `External/SPIRV-Tools/source`.

6. In the `Scripts` folder, run `./packagePregenSpirvToolsHeaders`, which will fetch and build the 
   full `SPIRV-Tools` library and will update `Templates/spirv-tools/build.zip` from the `*.h` and 
   `*.inc` files in `External/glslang/External/spirv-tools/build`. Test by running `./fetchDependencies --all` 
   and a **MoltenVK** build.



<a name="add_glslang"></a>
Adding the *glslang* Library to the *ExternalDependencies Xcode* Project
------------------------------------------------------------------------

The `ExternalDependencies` *Xcode* project is already configured to use the *glslang*
library. However, after updating the version of *glslang*, as described [above](#updating),
if you encounter any building errors, you may need to re-add the *glslang* library to the
`ExternalDependencies` *Xcode* project as follows:

1. In the *Project Navigator* panel, select the `ExternalDependencies` *Xcode* project, then 
   select the `glslang-macOS` target, and open the *Build Settings* tab. Locate the build 
   setting entry **Header Search Paths** (`HEADER_SEARCH_PATHS`) and add the following paths:

		$(inherited) 
		"$(SRCROOT)/External/glslang"
		"$(SRCROOT)/External/glslang/build/include"

2. Repeat *Step 1* for the `glslang-iOS` target within the `ExternalDependencies` *Xcode* project

3. In the *Project Navigator*, remove all *Groups* from under the *Group* named
   `External/glslang`.

4. Drag the following folders from the `External/glslang` file folder to the `External/glslang` 
   *Group* in the *Project Navigator* panel:

		glslang
		OGLCompilersDLL
		SPIRV

   In the ***Choose options for adding these files*** dialog that opens, select the ***Create groups*** option, 
   add the files to *all* of the `glslang-macOS`, `glslang-iOS`, and `glslang-tvOS` targets, and click the ***Finish*** button.

5. In the *Project Navigator* panel, remove the references to the following files and folders:

		External/glslang/glslang/MachineIndependant/glslang.y
		External/glslang/glslang/OSDependent/Windows
		External/glslang/glslang/OSDependent/Web
		External/glslang/glslang/HLSL




