<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="../Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenVK" style="width:256px;height:auto">
</a>


#MoltenVK External Dependencies

Copyright (c) 2014-2018 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format.
For best results, use a Markdown reader.*



Table of Contents
-----------------

- [Fetching External Libraries](#fetching)
- [Updating External Library Versions](#updating)
- [Adding the *SPIRV-Cross* Library to the *MoltenVKShaderConverter Xcode* Project](#add_spirv-cross)
- [Adding the *SPIRV-Tools* Library to the *MoltenVKShaderConverter Xcode* Project](#add_spirv-tools)
- [Adding the *glslang* Library to the *MoltenVKShaderConverter Xcode* Project](#add_glslang)
- [Adding the *cereal* Library to the *MoltenVK Xcode* Project](#add_cereal)



<a name="fetching"></a>
Fetching External Libraries
---------------------------

**MoltenVK** uses technology from the following external open-source libraries:

- [*cereal*](https://github.com/USCiLab/cereal)
- [*SPIRV-Cross*](https://github.com/KhronosGroup/SPIRV-Cross)
- [*Vulkan-LoaderAndValidationLayers*](https://github.com/KhronosGroup/Vulkan-LoaderAndValidationLayers)
- [*glslang*](https://github.com/KhronosGroup/glslang)
- [*SPIRV-Tools*](https://github.com/KhronosGroup/SPIRV-Tools)
- [*SPIRV-Headers*](https://github.com/KhronosGroup/SPIRV-Headers)
- [*VulkanSamples*](https://github.com/LunarG/VulkanSamples)

These external open-source libraries are maintained in the `External` directory.
To retrieve these libraries from their sources, run the `fetchDependencies`  script
in the main repository directory:

	./fetchDependencies



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
  
- **_VulkanSamples_**: a GitHub repository commit identifier found in the
  `ExternalRevisions/VulkanSamples_repo_revision` file.
  
- **_Vulkan-LoaderAndValidationLayers_**: a GitHub repository commit identifier found
  in the `ExternalRevisions/Vulkan-LoaderAndValidationLayers_repo_revision` file.
  
- **_glslang_**: automatically retrieved by the *Vulkan-LoaderAndValidationLayers* repository.
  
- **_SPIRV-Tools_**: automatically retrieved by the *glslang* repository.

- **_SPIRV-Headers_**: automatically retrieved by the *glslang* repository.
  
You can update which versions of the *SPIRV-Cross*, *VulkanSamples*,
*Vulkan-LoaderAndValidationLayers*, or *cereal* libraries are retrieved, 
by changing the value held in the corresponding `*_repo_revision` file listed above.

The version of the *glslang*, *SPIRV-Tools*, and *SPIRV-Headers* libraries is 
automatically determined by the version of the *Vulkan-LoaderAndValidationLayers* 
library you have retrieved.

Once you have made changes, you can retrieve the updated library versions by running
the `fetchDependencies` script again.

>***Note:*** If, after updating to new verions of the external libraries, you encounter 
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
Adding the *SPIRV-Cross* Library to the *MoltenVKShaderConverter Xcode* Project
-------------------------------------------------------------------------------

The `MoltenVKShaderConverter` *Xcode* project is already configured to use the *SPIRV-Cross*
library. However, after updating the version of *SPIRV-Cross*, as described [above](#updating),
if you encounter any building errors, you may need to re-add the *SPIRV-Cross* library to the
`MoltenVKShaderConverter` *Xcode* project as follows:

1. In the *Project Navigator*, remove all of the files under the *Group* named 
   `MoltenVKSPIRVToMSLConverter/SPIRV-Cross`.

2. Add the following files from the `SPIRV-Cross` file folder to the `SPIRV-Cross` 
   group in the *Project Navigator* panel:

		spirv_cfg.cpp
		spirv_cfg.hpp
		spirv_common.hpp
		spirv_cross.cpp
		spirv_cross.hpp
		spirv_glsl.cpp
		spirv_glsl.hpp
		spirv_msl.cpp
		spirv_msl.hpp

   In the ***Choose options for adding these files*** dialog that opens, select the 
   ***Create groups*** option, add the files to *both* the `MoltenVKSPIRVToMSLConverter-iOS` 
   and `MoltenVKSPIRVToMSLConverter-macOS` targets, and click the ***Finish*** button.

3. ***(Optional)*** To simplify the paths used within *Xcode* to reference the added files,
   perform the following steps:
   
   1. **Create a backup of your project!** This is an intrusive and dangerous operation!
   2. In the *Finder*, right-click your `MoltenVKShaderConverter.xcodeproj` file and select 
      **_Show Package Contents_**.
   3. Open the `project.pbxproj` file in a text editor.
   4. Remove all occurrences of `path-to-SPIRV-Cross-repo-folder` from the paths to the files added above.


### Regression Testing Your Changes to *SPIRV-Cross*

If you make changes to the `SPIRV-Cross` repository, you can regression test your changes
 using the following steps:

1. Load and build the versions of `SPRIV-Tools` and `glslang` that are used by the `SPIRV-Cross` tests:

		cd External/SPIRV-Cross
		./checkout_glslang_spirv_tools.sh
		./build_glslang_spirv_tools.sh

2. Build `SPIRV-Cross`:

		make

3. Run the regression tests:

		./test_shaders.sh

4. If your changes result in different expected output for a reference shader, and the new results
   are correct, you can update the reference shader for a particular regression test by deleting
   that reference shader, in either `External/SPIRV-Cross/reference/shaders-msl` or 
   `External/SPIRV-Cross/reference/opt/shaders-msl`, and running the test again. The test will
   replace the deleted reference shader.



<a name="add_spirv-tools"></a>
Adding the *SPIRV-Tools* Library to the *MoltenVKShaderConverter Xcode* Project
-------------------------------------------------------------------------------

The `MoltenVKShaderConverter` *Xcode* project is already configured to use the *SPIRV-Tools*
library. However, after updating the version of *SPIRV-Tools*, as described [above](#updating),
if you encounter any building errors, you may need to re-add the *SPIRV-Tools* library to the
`MoltenVKShaderConverter` *Xcode* project as follows:

1. In the *Project Navigator*, remove the *Group* named `source` from under the *Group* named
   `MoltenVKSPIRVToMSLConverter/SPIRV-Tools`.

2. Drag the `SPIRV-Tools/source` file folder to the `SPIRV-Tools` group in the *Project Navigator* panel.
   In the _**Choose options for adding these files**_ dialog that opens, select the 
   _**Create groups**_ option, add the files to *both* the `MoltenVKSPIRVToMSLConverter-iOS` 
   and `MoltenVKSPIRVToMSLConverter-macOS` targets, and click the ***Finish*** button.

3. In the *Project Navigator* panel, select the `MoltenVKShaderConverter` *Xcode* project, then select the 
   `MoltenVKSPIRVToMSLConverter-macOS` target, and open the *Build Settings* tab. Locate the build setting 
   entry **Header Search Paths** (`HEADER_SEARCH_PATHS`) and add the following paths:
   
		"$(SRCROOT)/glslang/External/spirv-tools/include"
		"$(SRCROOT)/glslang/External/spirv-tools/source"
		"$(SRCROOT)/glslang/External/spirv-tools/external/spirv-headers/include"
		"$(SRCROOT)/glslang/build/External/spirv-tools"

4. Repeat *Step 3* for the `MoltenVKSPIRVToMSLConverter-iOS` target within the `MoltenVKShaderConverter` *Xcode* project

5. ***(Optional)*** To simplify the paths used within *Xcode* to reference the added files,
   perform the following steps:
   
   1. **Create a backup of your project!** This is an intrusive and dangerous operation!
   2. In the *Finder*, right-click your `MoltenVKShaderConverter.xcodeproj` file and select 
      **_Show Package Contents_**.
   3. Open the `project.pbxproj` file in a text editor.
   4. Remove all occurrences of `path-to-SPIRV-Tools-repo-folder` from the paths to the 
      `source` directory added above.



<a name="add_glslang"></a>
Adding the *glslang* Library to the *MoltenVKShaderConverter Xcode* Project
---------------------------------------------------------------------------

The `MoltenVKShaderConverter` *Xcode* project is already configured to use the *glslang*
library. However, after updating the version of *glslang*, as described [above](#updating),
if you encounter any building errors, you may need to re-add the *glslang* library to the
`MoltenVKShaderConverter` *Xcode* project as follows:

1. In the *Project Navigator*, remove all *Groups* from under the *Group* named
   `MoltenVKGLSLToSPIRVConverter/glslang`.

2. Add the following folders from the `glslang` file folder to the `glslang` *Group* in
   the *Project Navigator* panel:

		glslang
		OGLCompilersDLL
		SPIRV

   In the ***Choose options for adding these files*** dialog that opens, select the 
   ***Create groups*** option, add the files to *both* the `MoltenVKGLSLToSPIRVConverter-iOS` 
   and `MoltenVKGLSLToSPIRVConverter-macOS` targets, and click the ***Finish*** button.

3. In the *Project Navigator* panel, remove the references to the following files and folders:

		glslang/glslang/MachineIndependant/glslang.y
		glslang/glslang/OSDependent/Windows

4. ***(Optional)*** To simplify the paths used within *Xcode* to reference the added files,
   perform the following steps:
   
   1. **Create a backup of your project!** This is an intrusive and dangerous operation!
   2. In the *Finder*, right-click your `MoltenVKShaderConverter.xcodeproj` file and select 
      **_Show Package Contents_**.
   3. Open the `project.pbxproj` file in a text editor.
   4. Remove all occurrences of `path-to-glslang-repo-folder` from the paths to the 
      `glslang`, `OGLCompilersDLL`, and `SPIRV` directories added above.
