#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
cross_source=${1:?SPIRV-Cross source directory required}
cross_build=${2:?SPIRV-Cross library build directory required}
ordinary_spirv=${3:?Ordinary fragment SPIR-V fixture required}
output=${4:-$(mktemp -d "${TMPDIR:-/tmp}/mvk-converter-pervertex.XXXXXX")}
mkdir -p "$output"
compiler_dir="$root/MoltenVKShaderConverter/MoltenVKShaderConverter"
for fixture in simple complex unsupported; do
    glslangValidator -V --target-env vulkan1.1 "$cross_source/tests-other/msl_capture_layout_$fixture.vert" -o "$output/capture-$fixture.spv"
done
glslangValidator -V --target-env vulkan1.1 "$cross_source/tests-other/msl_capture_layout_consumer.frag" -o "$output/capture-consumer.spv"
glslangValidator -V --target-env vulkan1.1 "$cross_source/tests-other/msl_tese_compute.tese" -o "$output/capture-tese.spv"
spirv-as --target-env vulkan1.1 "$cross_source/tests-other/msl_tese_primitive_builtin_block.spvasm" -o "$output/capture-tese-block.spv"
spirv-val --target-env vulkan1.1 "$output/capture-tese-block.spv"
xcrun clang++ -arch "${MVK_TEST_ARCH:-$(uname -m)}" -std=c++17 -O0 -g -DMVK_EXCLUDE_SPIRV_TOOLS=1 -DSPIRV_CROSS_NAMESPACE_OVERRIDE=MVK_spirv_cross \
    -I "$compiler_dir" -I "$root/Common" -I "$cross_source" -I "$root/External/cereal/include" \
    "$test_dir/PerVertexInputTests.cpp" "$compiler_dir/SPIRVToMSLConverter.cpp" \
    "$compiler_dir/SPIRVSupport.cpp" "$compiler_dir/FileSupport.mm" \
    "$cross_build/libspirv-cross-msl.a" "$cross_build/libspirv-cross-glsl.a" "$cross_build/libspirv-cross-core.a" \
    -framework Foundation -o "$output/per-vertex-input-test"
"$output/per-vertex-input-test" "$cross_source/tests-other/msl_per_vertex_input.spv" "$ordinary_spirv" "$output"
for shader in "$output"/*.metal; do
    xcrun metal -x metal -std=macos-metal2.4 -fsyntax-only -fno-modules "$shader"
done
echo "PASS: generated MSL syntax; output: $output"
