#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
cross_source=${1:?SPIRV-Cross source required}
cross_build=${2:?SPIRV-Cross library build required}
output=${3:?Output directory required}
mkdir -p "$output"
output=$(cd "$output" && pwd)
glslangValidator -V --target-env vulkan1.1 "$test_dir/portable-barycentric.vert" -o "$output/producer.spv"
glslangValidator -V --target-env vulkan1.1 -DPOINTS=1 "$test_dir/portable-barycentric.vert" -o "$output/point-producer.spv"
for mask in 1 2 3; do
    for captured in 0 1; do
        glslangValidator -V --target-env vulkan1.1 -DPERSPECTIVE=$((mask & 1)) -DLINEAR=$((mask & 2)) -DCAPTURED="$captured" "$test_dir/portable-barycentric.frag" -o "$output/fragment-$mask-$captured.spv"
    done
done
spirv-as --target-env vulkan1.1 "$cross_source/tests-other/msl_barycentric_explicit_only.spvasm" -o "$output/explicit-only.spv"
spirv-as --target-env vulkan1.1 "$cross_source/tests-other/msl_barycentric_copied_pointer.spvasm" -o "$output/copied-pointer.spv"
spirv-as --target-env vulkan1.1 "$test_dir/barycentric-active-block.spvasm" -o "$output/active-block.spv"
for locations in 15 31; do
    glslangValidator -V --target-env vulkan1.1 -DLOCATIONS="$locations" -DDENSE=1 "$root/MoltenVK/Tests/pervertex-capacity.vert" -o "$output/dense-$locations.spv"
done
for fixture in "$output"/*.spv; do spirv-val --target-env vulkan1.1 "$fixture"; done
# Exercise the production serializers without linking/loading the Metal runtime.
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
source = (root / 'MoltenVK/MoltenVK/GPUObjects/MVKPipeline.mm').read_text()
start = '#pragma mark Cereal archive definitions'
end = 'template<class Archive>\nvoid serialize(Archive & archive, MVKShaderModuleKey& k)'
assert source.count(start) == source.count(end) == 1
(output / 'PipelineCacheSerializers.inc').write_text(source.split(start, 1)[1].split(end, 1)[0])
# Compile the actual pipeline selector, so ignoring isUsed also fails the regression.
selector = source.split('bool MVKGraphicsPipeline::initPerVertexInputPipeline(', 1)[1]
selector = selector.split('for (const auto& input : inputs) {', 1)[1].split('if (!usesPerVertex && !usesPortableBarycentrics())', 1)[0]
(output / 'PipelineBarycentricSelection.inc').write_text('for (const auto& input : inputs) {' + selector)
PY
compiler_dir="$root/MoltenVKShaderConverter/MoltenVKShaderConverter"
xcrun clang++ -arch arm64 -std=c++17 -O0 -g -DMVK_EXCLUDE_SPIRV_TOOLS=1 -DSPIRV_CROSS_NAMESPACE_OVERRIDE=MVK_spirv_cross \
    -I "$output" -I "$compiler_dir" -I "$root/Common" -I "$cross_source" -I "$root/External/cereal/include" \
    -I "$root/External/Vulkan-Headers/include" -I "$root/MoltenVK/MoltenVK/Commands" \
    "$test_dir/PortableBarycentricTests.cpp" "$compiler_dir/SPIRVToMSLConverter.cpp" "$compiler_dir/SPIRVSupport.cpp" "$compiler_dir/FileSupport.mm" \
    "$cross_build/libspirv-cross-msl.a" "$cross_build/libspirv-cross-glsl.a" "$cross_build/libspirv-cross-reflect.a" "$cross_build/libspirv-cross-core.a" \
    -framework Foundation -o "$output/portable-barycentric-test"
"$output/portable-barycentric-test" "$output"
for shader in "$output"/*.metal; do xcrun metal -x metal -std=macos-metal2.4 -fsyntax-only -fno-modules "$shader"; done
echo "PASS: all generated Metal 2.4 sources; no GPU device or command submission"
