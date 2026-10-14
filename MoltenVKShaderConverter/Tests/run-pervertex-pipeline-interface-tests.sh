#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
cross_source=${1:?SPIRV-Cross source directory required}
cross_build=${2:?SPIRV-Cross library build directory required}
output=${3:?Output directory required}
arch=${4:-$(uname -m)}
mkdir -p "$output"
compiler_dir="$root/MoltenVKShaderConverter/MoltenVKShaderConverter"
for stage in vert frag; do
    glslangValidator -V --target-env vulkan1.1 "$test_dir/pervertex-interface.$stage" -o "$output/interface.$stage.spv"
    spirv-val --target-env vulkan1.1 "$output/interface.$stage.spv"
done
glslangValidator -V --target-env vulkan1.1 "$test_dir/pervertex-interface-linked.frag" -o "$output/interface-linked.frag.spv"
spirv-val --target-env vulkan1.1 "$output/interface-linked.frag.spv"
# Validate the matching VS/FS block interface as well as each standalone module.
glslangValidator -V --target-env vulkan1.1 -l "$test_dir/pervertex-interface.vert" "$test_dir/pervertex-interface-linked.frag" -o "$output/linked.spv"
xcrun clang++ -arch "$arch" -std=c++17 -O0 -g -DMVK_EXCLUDE_SPIRV_TOOLS=1 -DSPIRV_CROSS_NAMESPACE_OVERRIDE=MVK_spirv_cross \
    -I "$compiler_dir" -I "$root/Common" -I "$cross_source" -I "$root/External/cereal/include" \
    "$test_dir/PerVertexPipelineInterfaceTests.cpp" "$compiler_dir/SPIRVToMSLConverter.cpp" \
    "$compiler_dir/SPIRVSupport.cpp" "$compiler_dir/FileSupport.mm" \
    "$cross_build/libspirv-cross-reflect.a" "$cross_build/libspirv-cross-msl.a" \
    "$cross_build/libspirv-cross-glsl.a" "$cross_build/libspirv-cross-core.a" \
    -framework Foundation -o "$output/pervertex-pipeline-interface-test"
"$output/pervertex-pipeline-interface-test" "$output"
"$output/pervertex-pipeline-interface-test" "$output" interface-linked.frag.spv
