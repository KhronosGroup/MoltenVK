#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
output=${1:-$(mktemp -d /private/tmp/mvk-scratch.XXXXXX)}
architecture=${2:-$(uname -m)}
mkdir -p "$output"
xcrun clang++ -std=c++17 -fblocks -arch "$architecture" -Wall -Wextra -Werror -I"$root/MoltenVK/MoltenVK/Commands" -I"$root/MoltenVK/MoltenVK/GPUObjects" -I"$root/External/Vulkan-Headers/include" "$test_dir/PerVertexScratchTests.mm" -framework Foundation -framework Metal -o "$output/scratch-tests-$architecture"
if [[ "$architecture" == "$(uname -m)" ]]; then
    "$output/scratch-tests-$architecture"
else
    echo "COMPILED: scratch-tests-$architecture (execution skipped on $(uname -m) host)"
fi
