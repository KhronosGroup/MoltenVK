#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
# CPU only, no Metal device: PerVertex prepass state snapshot and restore, linked against the given x86_64 libMoltenVK.
# Usage: run-pervertex-prepass-state-tests.sh <libMoltenVK.1.4.3.dylib> <output directory>
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
mvk="$root/MoltenVK/MoltenVK"
dylib=$1
output=$2
mkdir -p "$output/lib"
ln -sfn "$dylib" "$output/lib/libMoltenVK.1.dylib"
xcrun clang++ -x objective-c++ -arch x86_64 -std=gnu++17 -mmacosx-version-min=11.0 -g -O0 -w -DMVK_CONFIG_LOG_LEVEL=3 -DMVK_EXCLUDE_SPIRV_TOOLS=1 -DMVK_FRAMEWORK_VERSION=1.4.3 -DMVK_USE_METAL_PRIVATE_API=0 -DSPIRV_CROSS_NAMESPACE_OVERRIDE=MVK_spirv_cross -I"$root/Common" -I"$root/External/cereal/include" -I"$root/External/SPIRV-Cross" -I"$root/External/Vulkan-Headers/include" -I"$root/MoltenVK/include" -I"$mvk/API" -I"$mvk/Commands" -I"$mvk/GPUObjects" -I"$mvk/Layers" -I"$mvk/OS" -I"$mvk/Utility" -I"$mvk/Vulkan" -I"$root/MoltenVKShaderConverter" "$test_dir/PerVertexPrepassStateTests.mm" -x none "$output/lib/libMoltenVK.1.dylib" -Wl,-rpath,"$output/lib" -framework Metal -framework Foundation -o "$output/prepass-state-tests"
arch -x86_64 "$output/prepass-state-tests"
