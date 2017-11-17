<a class="site-logo" href="https://github.com/KhronosGroup/MoltenVK" title="MoltenVK">
	<img src="../Docs/images/MoltenVK-Logo-Banner.png" alt="MoltenV" style="width:256px;height:auto">
</a>

Copyright (c) 2014-2017 [The Brenwill Workshop Ltd.](http://www.brenwill.com)

*This document is written in [Markdown](http://en.wikipedia.org/wiki/Markdown) format.
For best results, use a Markdown reader.*


Table of Contents
-----------------

- *SPIRV-Cross*
	- [Using the *SPIRV-Cross* library with **MoltenVKShaderConverter**](#install_spirv-cross)
	- [Updating the *SPIRV-Cross* library version](#update_spirv-cross)
	- [Adding the *SPIRV-Cross* library to a new *Xcode* project](#add_spirv-cross)

- *SPIRV-Tools*
	- [Using the *SPIRV-Tools* library with **MoltenVKShaderConverter**](#install_spirv-tools)
	- [Updating the *SPIRV-Tools* library version](#update_spirv-tools)
	- [Adding the *SPIRV-Tools* library to a new *Xcode* project](#add_spirv-tools)

- *glslang*
	- [Using the *glslang* library with **MoltenVKShaderConverter**](#install_glslang)
	- [Updating the *glslang* library version](#update_glslang)
	- [Adding the *glslang* library to a new *Xcode* project](#add_glslang)



<a name="install_spirv-cross"></a>
Using the *SPIRV-Cross* library with *MoltenVKShaderConverter*
--------------------------------------------------------------

**MoltenVKShaderConverter** uses `SPIRV-Cross` to convert *SPIR-V* code to *Metal Shading Language (MSL)* source code.

If you used the `--recursive` option when cloning the `MoltenVK` repository, you should already
have the `SPIRV-Cross` submodule. If you did **_not_** use the `--recursive` option when cloning
the `MoltenVK` repository, retrieve the `SPIRV-Cross` submodule into the `External` directory 
as follows, from within the `MoltenVK` repository directory:

	git submodule update --init External/SPIRV-Cross



<a name="update_spirv-cross"></a>
Updating the *SPIRV-Cross* library version
------------------------------------------

If you are developing enhancements to **MoltenVKShaderConverter**, you can update the version of 
`SPIRV-Cross` used by **MoltenVKShaderConverter**, as follows:

	cd External
	rm -rf SPIRV-Cross
	git clone https://github.com/KhronosGroup/SPIRV-Cross.git

The updated version will then be "locked in" the next time the `MoltenVK` repository is committed to `git`.

>***Note:*** If after updating to a new verions of `SPIRV-Cross`, you encounter build errors when 
 building **MoltenVKShaderConverter**, review the [instructions below](#add_spirv-cross) to ensure 
 all necessary `SPIRV-Cross` files are included in the **MoltenVKShaderConverter** builds.

>***Note:*** As new features are added to **MoltenVK**, many are powered by the ability to convert 
 sophisticated *SPIRV* code into *MSL* code. Sometimes new **MoltenVK** features and capabilities are 
 provided solely via new `SPIRV-Cross` features. ***If you are developing enhancements for 
 MoltenVKShaderConverter, be sure to update the `SPIRV-Cross` submodule often***.


### Regression Testing Your Changes to *SPIRV-Cross*

If you make changes to the `SPIRV-Cross` submodule, you can regression test your changes by building the 
`spirv-cross` executable and running the `test_shaders.py` regression test script, using the following steps:


1. If you did not run the `External/makeAll` script, build the `SPIRV-Tools` and `glslangValidator`tools 
   (you should only need to do this once):

		cd External
		./makeSPIRVTools
		./makeglslang

2. Set your `PATH` environment variable so that the `spirv-cross` tool can find the
   `glslangValidator` and `SPIRV-Tools` tools:

		export PATH=$PATH:"../glslang/build/StandAlone:../SPIRV-Tools/build/tools"

3. Build the `spirv-cross` executable:

		cd External/SPIRV-Cross
		make

4. Run the regression tests:

		./test_shaders.py --msl shaders-msl

5. If your changes result in different expected output for a reference shader, you can update
   the reference shader for a particular regression test:
	
	1. Termporarily rename the existing reference shader file in `External/SPIRV-Cross/reference/shaders-msl`.
	2. Run the regression tests. A new reference shader will be automatically generated.
	3. Compare the new reference shader to the old one using a tool like *Xcode Version Editor*,
	   or *Xcode FileMerge*, or equivalent.
	4. Delete the old copy of the reference shader.


<a name="add_spirv-cross"></a>
Adding the *SPIRV-Cross* library to a new *Xcode* project
---------------------------------------------------------

The `MoltenVKShaderConverter` project is already configured to use the `SPIRV-Cross` library. 
However, to add the `SPIRV-Cross` library to a new *Xcode* project:

1. Follow the [instructions above](#install_spirv-cross) to create a symlink from your project
   to the location of your local clone of the `SPIRV-Cross` repository.

2. In the project navigator, add a new *Group* named `SPIRV-Cross`.

3. Add the following files from the `SPIRV-Cross` file folder to the `SPIRV-Cross` 
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

4. ***(Optional)*** If you want *Xcode* to reference the added files through symlinks (to increase
   portability) instead of resolving them, perform the following steps:
   
   1. **Create a backup of your project!** This is an intrusive and dangerous operation!
   2. In the *Finder*, right-click your `MyApp.xcodeproj` file and select *Show Package Contents*.
   3. Open the `project.pbxproj` file in a text editor.
   4. Replace all occurrences of the `path-to-SPIRV-Cross-repo-folder` (as defined by the symlink added
      [above](#install_spirv-cross)) with simply `SPIRV-Cross` (the name of the symlink). Be sure you only
      replace the part of the path that matches the `path-to-SPIRV-Cross-repo-folder`. Do not replace 
      any part of the path that indicates a subfolder within that repository folder.



<a name="install_spirv-tools"></a>
Using the *SPIRV-Tools* library with *MoltenVKShaderConverter*
--------------------------------------------------------------

**MoltenVKShaderConverter** uses `SPIRV-Tools` to log *SPIR-V* code during conversion to *Metal Shading Language (MSL)* 
source code. The `SPIRV-Tools` also requires the `SPIRV-Headers` library.

To add the `SPIRV-Tools` and `SPIRV-Headers` libraries to **MoltenVK**, open a *Terminal* session and 
perform the following command-line steps:

1. If you used the `--recursive` option when cloning the `MoltenVK` repository, you should already 
   have the `SPIRV-Tools` and `SPIRV-Headers` submodules, and you can skip to *Step 2* below. 
   If you did **_not_** use the `--recursive` option when cloning the `MoltenVK` repository, 
   retrieve the `SPIRV-Tools` and `SPIRV-Headers` submodules into the `External` directory 
   as follows, from within the `MoltenVK` repository directory:

		git submodule update --init External/SPIRV-Headers
		git submodule update --init External/SPIRV-Tools

3. In the `Externals` folder within the `MoltenVK` repository, build `SPIRV-Tools` 
   as follows from the main directory of this `MoltenVK` repository:

		cd External
		./makeSPIRVTools



<a name="update_spirv-tools"></a>
Updating the *SPIRV-Tools* library version
------------------------------------------

If you are developing enhancements to **MoltenVKShaderConverter**, you can update the version of 
`SPIRV-Tools` used by **MoltenVKShaderConverter**, as follows:

	cd External

	rm -rf SPIRV-Headers
	git clone https://github.com/KhronosGroup/SPIRV-Headers.git

	rm -rf SPIRV-Tools
	git clone https://github.com/KhronosGroup/SPIRV-Tools.git
	
	./makeSPIRVTools

The updated version will then be "locked in" the next time the `MoltenVK` repository is committed to `git`.

>***Note:*** If after updating to a new verions of `SPIRV-Tools`, you encounter build errors when 
>building **MoltenVKShaderConverter**, review the [instructions below](#add_spirv-tools) to ensure 
>all necessary `SPIRV-Tools` files are included in the **MoltenVKShaderConverter** builds.



<a name="add_spirv-tools"></a>
Adding the *SPIRV-Tools* library to a new *Xcode* project
---------------------------------------------------------

The `MoltenVKShaderConverter` project is already configured to use the `SPIRV-Tools` library. 
However, to add the `SPIRV-Tools` library to a new *Xcode* project:

1. Follow the [instructions above](#install_spirv) to create a symlink from your project
   to the location of your local clone of the `SPIRV-Tools` repository.

2. In the project navigator, add a new *Group* named `SPIRV-Tools`.

3. Drag the `SPIRV-Tools/source` folder to the `SPIRV-Tools` group in the *Project Navigator* panel.
   In the _**Choose options for adding these files**_ dialog that opens, select the 
   _**Create groups**_ option, add the files to *both* the `MoltenVKSPIRVToMSLConverter-iOS` 
   and `MoltenVKSPIRVToMSLConverter-macOS` targets, and click the ***Finish*** button.

4. In the *Project Navigator* panel, select your application's target, and open the 
   *Build Settings* tab. Locate the build setting entry **Header Search Paths** 
   (`HEADER_SEARCH_PATHS`) and add the following paths:
   
		"$(SRCROOT)/MoltenVKSPIRVToMSLConverter/SPIRV-Tools/include"
		"$(SRCROOT)/MoltenVKSPIRVToMSLConverter/SPIRV-Tools/source"
		"$(SRCROOT)/MoltenVKSPIRVToMSLConverter/SPIRV-Tools/build"
		"$(SRCROOT)/MoltenVKSPIRVToMSLConverter/SPIRV-Headers/include"

5. ***(Optional)*** If you want *Xcode* to reference the added files through symlinks (to increase
   portability) instead of resolving them, perform the following steps:
   
   1. **Create a backup of your project!** This is an intrusive and dangerous operation!
   2. In the *Finder*, right-click your `MyApp.xcodeproj` file and select *Show Package Contents*.
   3. Open the `project.pbxproj` file in a text editor.
   4. Replace all occurrences of the `path-to-SPIRV-Tools-repo-folder` (as defined by the symlink added
      [above](#install_spirv)) with simply `SPIRV-Tools` (the name of the symlink). Be sure you only
      replace the part of the path that matches the `path-to-SPIRV-Tools-repo-folder`. Do not replace 
      any part of the path that indicates a subfolder within that repository folder.



<a name="install_glslang"></a>
Using the *glslang* library with **MoltenVKShaderConverter**
------------------------------------------------------------

**MoltenVKShaderConverter** uses `glslang`, the Khronos *GLSL* reference compiler, to parse *GLSL* source code 
and convert it to *SPIR-V*.

If you used the `--recursive` option when cloning the `MoltenVK` repository, you should already have
the `glslang` submodule. If you did **_not_** use the `--recursive` option when cloning the 
`MoltenVK` repository, retrieve the `glslang` submodule into the `External` directory as follows, 
from within the `MoltenVK` repository directory:

	git submodule update --init External/glslang



<a name="update_glslang"></a>
Updating the *glslang* library version
------------------------------------------

If you are developing enhancements to **MoltenVKShaderConverter**, you can update the version of 
`glslang` used by **MoltenVKShaderConverter**, as follows:

	cd External
	rm -rf glslang
	git clone https://github.com/KhronosGroup/glslang.git
	./makeglslang

The updated version will then be "locked in" the next time the `MoltenVK` repository is committed to `git`.

>***Note:*** If after updating to a new verions of `glslang`, you encounter build errors when 
>building **MoltenVKShaderConverter**, review the [instructions below](#add_glslang) to ensure 
>all necessary `glslang` files are included in the **MoltenVKShaderConverter** builds.



<a name="add_glslang"></a>
Adding the *glslang* library to a new *Xcode* project
-----------------------------------------------------

The `MoltenVKShaderConverter` project is already configured to use the `glslang` library. 
However, to add the `glslang` library to a new *Xcode* project:

1. Follow the [instructions above](#install_glslang) to create a symlink from your project
   to the location of your local clone of the `glslang` repository, and make the required 
   modifications to the `glslang` code.

2. In the project navigator, add a new *Group* named `glslang`.

3. Add the following folders from the `glslang` file folder to the `glslang` *Group* in
   the *Project Navigator* panel:

		glslang
		OGLCompilersDLL
		SPIRV

   In the ***Choose options for adding these files*** dialog that opens, select the 
   ***Create groups*** option, add the files to *both* the `MoltenVKGLSLToSPIRVConverter-iOS` 
   and `MoltenVKGLSLToSPIRVConverter-macOS` targets, and click the ***Finish*** button.

4. In the *Project Navigator* panel, remove the references to the following files and folders:

		glslang/glslang/MachineIndependant/glslang.y
		glslang/glslang/OSDependent/Windows

5. ***(Optional)*** If you want *Xcode* to reference the added files through symlinks (to increase
   portability) instead of resolving them, perform the following steps:
   
   1. **Create a backup of your project!** This is an intrusive and dangerous operation!
   2. In the *Finder*, right-click your `MyApp.xcodeproj` file and select *Show Package Contents*.
   3. Open the `project.pbxproj` file in a text editor.
   4. Replace all occurrences of the `path-to-glslang-repo-folder` (as defined by the symlink added
      [above](#install_glslang)) with simply `glslang` (the name of the symlink). Be sure you only 
      replace the part of the path that matches the `path-to-glslang-repo-folder`. Do not replace 
      any part of the path that indicates a subfolder within that repository folder.
