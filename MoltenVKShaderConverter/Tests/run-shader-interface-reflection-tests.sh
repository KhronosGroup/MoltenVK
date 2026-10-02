#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
cross_source=${1:?SPIRV-Cross source required}
cross_build=${2:?SPIRV-Cross library build required}
output=${3:?Output directory required}
mode=${4:-all}
mkdir -p "$output"
output=$(cd "$output" && pwd)
# Reuse the validated F1 module; place aliases BEFORE the first member, between
# the two members, and in helpers that only use InterpolateAt*.
python3 - "$test_dir" "$output" <<'PY'
from pathlib import Path
import sys
test_dir, output = map(Path, sys.argv[1:])
source = (test_dir / 'barycentric-active-block.spvasm').read_text()
replacements = {
    '%perspective_ptr = OpAccessChain %in3 %weights %u0': '%perspective_root = OpAccessChain %inblock %weights\n%perspective_ptr = OpAccessChain %in3 %perspective_root %u0',
    '%linear_ptr = OpAccessChain %in3 %weights %u1': '%linear_copy = OpCopyObject %inblock %weights\n%linear_root = OpAccessChain %inblock %linear_copy\n%linear_root2 = OpInBoundsAccessChain %inblock %linear_root\n%linear_ptr = OpAccessChain %in3 %linear_root2 %u1',
    '%both_n = OpAccessChain %in3 %weights %u1': '%both_root = OpAccessChain %inblock %weights\n%both_n = OpAccessChain %in3 %both_root %u1',
    '%ordinary_ptr = OpAccessChain %in4 %weights %u2': '%ordinary_root = OpInBoundsAccessChain %inblock %weights\n%ordinary_ptr = OpAccessChain %in4 %ordinary_root %u2',
    '%unused_entry = OpLabel': '%unused_entry = OpLabel\n%unused_root = OpAccessChain %inblock %weights',
    '%explicit_perspective_root = OpCopyObject %inblock %weights': '%explicit_perspective_root = OpAccessChain %inblock %weights',
    '%explicit_linear_root2 = OpCopyObject %inblock %explicit_linear_root': '%explicit_linear_alias_root = OpInBoundsAccessChain %inblock %explicit_linear_root\n%explicit_linear_root2 = OpCopyObject %inblock %explicit_linear_alias_root',
}
for old, new in replacements.items():
    assert source.count(old) == 1, old
    source = source.replace(old, new)
(output / 'root-alias.spvasm').write_text(source)
PY
spirv-as --target-env vulkan1.1 "$test_dir/barycentric-active-block.spvasm" -o "$output/active-block.spv"
spirv-as --target-env vulkan1.1 "$output/root-alias.spvasm" -o "$output/root-alias.spv"
for stage in vert frag; do
    vertex=0
    if [[ "$stage" == vert ]]; then vertex=1; fi
    for head in 0 1; do
        glslangValidator -V --target-env vulkan1.1 -S "$stage" -DVERTEX="$vertex" -DHEAD="$head" "$test_dir/reflection-alignment.glsl" -o "$output/alignment-$head.$stage.spv"
    done
done
for fixture in "$output"/*.spv; do spirv-val --target-env vulkan1.1 "$fixture"; done
xcrun clang++ -arch arm64 -std=c++17 -O1 -g -fsanitize=address -fno-omit-frame-pointer -DSPIRV_CROSS_NAMESPACE_OVERRIDE=MVK_spirv_cross \
    -I "$output" -I "$root/MoltenVKShaderConverter/MoltenVKShaderConverter" -I "$cross_source" \
    -I "$root/MoltenVK/MoltenVK/Utility" -I "$root/MoltenVK/MoltenVK/API" -I "$root/MoltenVK/include" -I "$root/Common" \
    "$test_dir/ShaderInterfaceReflectionTests.cpp" "$cross_build/libspirv-cross-reflect.a" "$cross_build/libspirv-cross-glsl.a" "$cross_build/libspirv-cross-core.a" \
    -o "$output/reflection-tests"
if [[ "$mode" == all ]]; then
    "$output/reflection-tests" "$output" activity
    "$output/reflection-tests" "$output" alignment
else
    "$output/reflection-tests" "$output" "$mode"
fi
