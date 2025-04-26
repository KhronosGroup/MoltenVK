<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="../Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>


#MoltenVK External Dependencies

Copyright (c) 2015-2025 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

[comment]: # "This document is written in Markdown (http://en.wikipedia.org/wiki/Markdown) format."
[comment]: # "For best results, use a Markdown reader."



Table of Contents
-----------------

- [Fetching and Building External Libraries](#fetching)
- [Updating External Library Versions](#updating)
- [Adding the *cereal* Library to the *MoltenVK Xcode* Project](#add_cereal)
- [Adding the *SPIRV-Tools* Library to the *ExternalDependencies Xcode* Project](#add_spirv-tools)
- [Adding the *SPIRV-Cross* Library to the *ExternalDependencies Xcode* Project](#add_spirv-cross)



<a name="fetching"></a>
Fetching and Building External Libraries
----------------------------------------

**MoltenVK** uses technology from the following external open-source libraries:

- [*cereal*](https://github.com/USCiLab/cereal)
- [*SPIRV-Cross*](https://github.com/KhronosGroup/SPIRV-Cross)
- [*SPIRV-Headers*](https://github.com/KhronosGroup/SPIRV-Headers)
- [*SPIRV-Tools*](https://github.com/KhronosGroup/SPIRV-Tools)
- [*volk*](https://github.com/zeux/volk)
- [*Vulkan-Headers*](https://github.com/KhronosGroup/Vulkan-Headers)
- [*Vulkan-Tools*](https://github.com/KhronosGroup/Vulkan-Tools)

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

- **_SPIRV-Cross_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/SPIRV-Cross_repo_revision` file. 
  
- **_SPIRV-Headers_**: a GitHub repository commit identifier found
  in the `ExternalRevisions/SPIRV-Headers_repo_revision` file.
  
- **_SPIRV-Tools_**: a GitHub repository commit identifier found
  in the `ExternalRevisions/_SPIRV-Tools__repo_revision` file.

- **_volk_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/Volk_repo_revision` file.

- **_Vulkan-Headers_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/Vulkan-Headers_repo_revision` file.

- **_Vulkan-Tools_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/Vulkan-Tools_repo_revision` file.

You can update which versions of the external libraries are retrieved by changing 
the value held in the corresponding `*_repo_revision` file listed above.

Once you have made changes to the `*_repo_revision` files, you can retrieve the updated 
library versions by running the `fetchDependencies` script, as described above, again.

>***Note:*** If, after updating to new versions of the external libraries, you encounter 
>build errors when building **MoltenVK**, review the instructions in the sections below 
>to ensure all necessary external library files are included in the **MoltenVK** builds.

>***Note:*** _Vulkan-Tools_ and _volk_ are not used by **MoltenVK** itself, but are used
>by the _Cube_ demo app included in the **MoltenVK** repository.



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



<a name="add_spirv-tools"></a>
Adding the *SPIRV-Tools* Library to the *ExternalDependencies Xcode* Project
----------------------------------------------------------------------------

The `ExternalDependencies` *Xcode* project is already configured to use the *SPIRV-Tools*
library. However, after updating the version of *SPIRV-Tools*, as described [above](#updating), 
if you encounter any building errors, you may need to re-add the *SPIRV-Tools* library to the 
`ExternalDependencies` *Xcode* project as follows:

1. In the *Project Navigator* panel, select the `ExternalDependencies` *Xcode* project, then 
   select the `SPIRV-Tools-macOS` target, and open the *Build Settings* tab. Locate the build 
   setting entry **Header Search Paths** (`HEADER_SEARCH_PATHS`) and add the following paths:

		$(inherited) 
		"$(SRCROOT)/External/SPIRV-Tools/" 
		"$(SRCROOT)/External/SPIRV-Tools/include" 
		"$(SRCROOT)/External/SPIRV-Tools/external/spirv-headers/include" 
		"$(SRCROOT)/External/SPIRV-Tools/build"

2. Repeat *Step 1* for the `SPIRV-Tools-iOS`, `SPIRV-Tools-tvOS`, and ` `SPIRV-Tools-xrOS` 
   targets within the `ExternalDependencies` *Xcode* project

3. In the *Project Navigator*, remove the *Group* named `source` from under the *Group* named
   `External/SPIRV-Tools`.

4. Drag the `External/SPIRV-Tools/source` file folder to the `External/SPIRV-Tools` 
   group in the *Project Navigator* panel. In the _**Choose options for adding these files**_ dialog 
   that opens, select the _**Create groups**_ option, add the files to *all* of the `SPIRV-Tools-macOS`, 
   `SPIRV-Tools-iOS`, `SPIRV-Tools-tvOS`, and `SPIRV-Tools-xrOS` targets, and click the ***Finish*** button.

5. Remove the following *Groups* from under the *Group* named `External/SPIRV-Tools/source`:
   - `fuzz`
   - `wasm`

6. In the `Scripts` folder, run `./packagePregenSpirvToolsHeaders`, which will fetch and 
   build the full `SPIRV-Tools` library and will update `Templates/spirv-tools/build.zip` 
   from the `*.h` and `*.inc` files in `External/SPIRV-Tools/build`. 
   Test by running `./fetchDependencies --all` and a **MoltenVK** build.



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
		spirv_cross_containers.hpp
		spirv_cross_error_handling.hpp
		spirv_cross_parsed_ir.cpp
		spirv_cross_parsed_ir.hpp
		spirv_cross_util.hpp
		spirv_cross.cpp
		spirv_cross.hpp
		spirv_glsl.cpp
		spirv_glsl.hpp
		spirv_msl.cpp
		spirv_msl.hpp
		spirv_parser.cpp
		spirv_parser.hpp
		spirv_reflect.cpp
		spirv_reflect.hpp
		spirv.hpp

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

		cd External/SPIRV-Cross
		./checkout_glslang_spirv_tools.sh
		./build_glslang_spirv_tools.sh
		./test_shaders.sh



