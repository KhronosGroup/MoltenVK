#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
output=${1:-$(mktemp -d "${TMPDIR:-/tmp}/mvk-draw-size.XXXXXX")}
mkdir -p "$output"
includes=(-I"$root/Common" -I"$root/MoltenVK/include" -I"$root/External/Vulkan-Headers/include")
for directory in API Commands GPUObjects Layers OS Utility Vulkan; do
    includes+=(-I"$root/MoltenVK/MoltenVK/$directory")
done
xcrun clang++ -std=c++17 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations "${includes[@]}" "$test_dir/PerVertexDrawSizeTests.mm" -framework Foundation -framework Metal -o "$output/draw-size-tests"
"$output/draw-size-tests"
