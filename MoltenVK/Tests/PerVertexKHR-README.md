# Experimental PerVertexKHR capture and replay: tests

MoltenVK advertises `VK_KHR_fragment_shader_barycentric` where Metal provides barycentric coordinates, and implements it
with them; that native path does not support `PerVertexKHR` inputs. This experimental capture and replay is a separate
path, reachable only through a test entry point, in a library built for that purpose. It does not claim conformance of
the extension.

## Claimed scope

The tests below cover this scope:

- vertex and fragment pipelines from SPIR-V, through the portable capture-then-replay path, on GPUs with MSL 2.4,
  with `MVK_USE_METAL_PRIVATE_API` off;
- `PerVertexKHR` fragment inputs: scalars and vectors of `float`, `int` and `uint`, arrays and structures;
- `BaryCoordKHR` and `BaryCoordNoPerspKHR`, for triangles only. Points and lines get no defined barycentric weights;
- point lists, line lists and strips, triangle lists, strips and fans, static or dynamic
  (`VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY` within the topology class of the pipeline);
- `vkCmdDraw` and `vkCmdDrawIndexed` with `uint32` indices, a nonzero `firstVertex` or `firstIndex`, and a nonzero
  `firstInstance`, with one instance and a zero `vertexOffset`;
- `ClipDistance` written by the vertex shader;
- one sample, filled polygons, first provoking vertex, no multiview;
- alpha blending, which makes the draw order visible;
- refusal before submission of memoryless attachments that would have to cross the capture and replay passes.

Accepted by the implementation but not covered by these tests: several instances, a nonzero `vertexOffset`, primitive
restart and `uint8` or `uint16` indices, secondary command buffers, Metal command buffer prefill, and a `viewMask`
with a single view.

Outside the claimed scope, even though code for them is present: indirect and indirect count draws, tessellation,
mesh shaders, the native path for Apple10 GPUs, multisampling, multiview with more than one view, last provoking
vertex, polygon modes other than `FILL`, the private Metal API, and adjacency topologies.

## Building the experimental library

```sh
bash MoltenVK/Tests/PerVertexTES/build-library.sh <output> OFF ON
```

- Run it from the root of the MoltenVK checkout: the library embeds the `git rev-parse --short HEAD` of the current
  directory as its revision.
- `External/SPIRV-Cross` must be checked out at the revision pinned in `ExternalRevisions/SPIRV-Cross_repo_revision`,
  with no local changes.
- The arguments select an arm64 Debug build, with tessellation admission off and the test entry point linked
  (`MoltenVK/Tests/PerVertexTES/EnableTestDevice.mm`).
- The library is written to `<output>/build/moltenvk/MoltenVK/libMoltenVK.1.4.3.dylib`.

`MVK_TEST_BUILD_TYPE=Release` selects a Release build instead. The tests below were run on Debug builds only.

## Activation

An application looks up `mvkEnableTESFixtureDevice(VkPhysicalDevice)` with `dlsym`, and calls it before creating the
logical device. Despite its historical name, it only selects the experimental capture and replay path for
`VK_KHR_fragment_shader_barycentric`, and only where Metal provides barycentric coordinates. Without that call, the
extension keeps the native path: `BaryCoordKHR` and `BaryCoordNoPerspKHR` read Metal barycentric coordinates, and a
pipeline whose fragment shader reads `PerVertexKHR` inputs is not supported.

## Tests and expected results

The scripts need `python3`, `glslangValidator` and `spirv-val` on `PATH`. The CTS and dynamic topology runners
also need GNU `timeout`, installed as `gtimeout`.

All GPU runs use Metal API and shader validation (`MTL_DEBUG_LAYER=1`, `MTL_SHADER_VALIDATION=1`), one GPU workload at
a time. A skipped or `NotSupported` case in a list expected to pass is a missing result, not a pass.

| Ref. | Test | Command | Expected |
|---|---|---|---|
| A | Checks of production code paths. On the CPU: `prefill`, `helper-preflight`, `scratch`, `draw-size`, `topology`, `capture-variant`. On the GPU through Metal, without Vulkan: `restart`, `memoryless` | `bash MoltenVK/Tests/run-pervertex-<check>-tests.sh [output]`; for the GPU part, `bash MoltenVK/Tests/run-pervertex-restart-tests.sh <output> gpu` and `bash MoltenVK/Tests/run-pervertex-memoryless-tests.sh <output> --metal` | `PASS` for each |
| B | Dynamic primitive topology oracle, 14 cases: `{triangles,lines}:{direct,indexed}:{pervertex,ordinary}` and `triangles:{direct,indexed}:{weights,weights-w,weights-w-noperspective}` | `bash MoltenVK/Tests/run-pervertex-dynamic-topology-tests.sh <library> <output> 0 <case>...` | `PASS` for each |
| C | Memoryless depth and stencil attachments split across capture and replay | `bash MoltenVK/Tests/run-pervertex-split-tests.sh <library> <output> after memoryless-depth memoryless-stencil` | `REFUSED` (exit 4) for each |
| D | `dEQP-VK.fragment_shading_barycentric` cases of the claimed scope (`PerVertexCTS/experimental-vsfs-barycentric.txt`, 1201 cases) | `bash MoltenVK/Tests/PerVertexCTS/run-pervertex-cts.sh <deqp-vk directory> <library> MoltenVK/Tests/PerVertexCTS/experimental-vsfs-barycentric.txt <output> validated` | 1201 `Pass` |
| E | Ordinary topology and triangle fan cases (`PerVertexCTS/ordinary-fan-topology.txt`, 562 cases) | same command with that list | statuses of `PerVertexCTS/ordinary-fan-topology-expected.csv`: 258 `Pass`, 299 `NotSupported`, 5 `Fail` |
| F | List D without activation (native path) | `PERVERTEX_CTS_DIRECT=1` and the command of D | per case, the statuses of an upstream MoltenVK library on the same Mac |
| G | Identity and activation probe | see below | `fragmentShaderBarycentric` 1 before and after activation, where Metal provides barycentric coordinates |

Notes:

- Six A checks run on the CPU only, some of them with stand-in Metal objects. `restart` and `memoryless` create a
  Metal device and submit work to the GPU only with their GPU argument, `gpu` and `--metal` respectively. Without it,
  `restart` runs its CPU checks only, and `memoryless` its storage policy checks only.
- The CTS runner builds `AdapterShim.c`, which calls the test entry point before `deqp-vk` creates its devices.
  `PERVERTEX_CTS_DIRECT=1` loads the library directly, so the native path is used.
- The 5 expected failures of E:
  - 2 `restart_disabled_triangle_fan` cases also fail with an upstream library, because Metal cannot disable primitive
    restart;
  - 3 `topology_*_bind_unused_ms` cases are `NotSupported` with an upstream library, which does not support mesh
    shaders. `AdapterShim.c` also calls the test entry point of the experimental mesh path (`mvkEnableMeshTestDevice`),
    so these cases reach pipeline creation, and end with `VK_ERROR_FEATURE_NOT_PRESENT`. They fail because of the
    test shim, not on the default path.
- F compares the native path with an upstream library, case by case. On Apple M4 Pro, Apple M2 and Apple M1, both
  fail every case of list D at pipeline creation (`VK_ERROR_INITIALIZATION_FAILED`), with the same message. There, F
  shows that the native path is unchanged on list D; it does not show that the native path renders barycentric inputs.
- E's `NotSupported` statuses depend on the features of the Mac.
- List D was selected from the runnable cases of `fragment_shading_barycentric` by
  `PerVertexCTS/select-experimental-scope.py`. It excludes these cases:
  - 744 adjacency cases;
  - 690 mesh cases;
  - 108 last-provoking-vertex cases;
  - 50 multisampling cases;
  - 36 tessellation cases;
  - 22 weight cases on points and lines.

Probe G:

```sh
xcrun clang++ -arch arm64 -std=c++17 -DVK_ENABLE_BETA_EXTENSIONS -DPROBE_BARYCENTRIC_ADAPTER_ONLY \
    -IExternal/Vulkan-Headers/include MoltenVK/Tests/MacFamilyHarness/probe.mm <library> \
    -fobjc-arc -framework Foundation -framework Metal -o probe
```

The probe prints `fragmentShaderBarycentric` before and after the call to the test entry point. It also prints the
first four bytes of `pipelineCacheUUID`, which carry the library's revision. Run it with `DYLD_PRINT_LIBRARIES=1` to
confirm which library is loaded.

### Converter tests

These run on the CPU, against the SPIRV-Cross sources (`External/SPIRV-Cross`) and a build of its static libraries
with the `MVK_spirv_cross` namespace:

```sh
bash MoltenVKShaderConverter/Tests/run-per-vertex-input-tests.sh <SPIRV-Cross source> <SPIRV-Cross build> <ordinary fragment SPIR-V> [output]
bash MoltenVKShaderConverter/Tests/run-pervertex-pipeline-interface-tests.sh <SPIRV-Cross source> <SPIRV-Cross build> <output> [arch]
bash MoltenVKShaderConverter/Tests/run-portable-barycentric-tests.sh <SPIRV-Cross source> <SPIRV-Cross build> <output>
bash MoltenVKShaderConverter/Tests/run-shader-interface-reflection-tests.sh <SPIRV-Cross source> <SPIRV-Cross build> <output>
MVK_CACHE_LIBRARY=<library> MVK_CACHE_ARCH=arm64 MVK_CACHE_CROSS_SOURCE=<SPIRV-Cross source> \
    bash MoltenVKShaderConverter/Tests/run-pipeline-cache-per-vertex-tests.sh <output>
```

- They need `glslangValidator`, `spirv-as` and `spirv-val` on `PATH`. Some also compile the generated MSL with
  `xcrun metal -fsyntax-only`.
- The reflection test is built with AddressSanitizer. Link it against SPIRV-Cross libraries built with
  `-fsanitize=address`: otherwise AddressSanitizer reports false container overflows in the libc++ containers that
  cross the boundary.
- The `build/spirv-cross` directory of the library build above holds suitable uninstrumented libraries for the other
  scripts.
