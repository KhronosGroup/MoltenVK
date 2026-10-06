#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
# CPU only, no Metal device: PerVertex scratch pool. Recompiles the test from source on every run.
# Usage: run-pervertex-scratch-pool-tests.sh <output directory> [MoltenVK source root whose headers are tested]
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
output=$1
root=${2:-$(cd "$test_dir/../.." && pwd)}
mkdir -p "$output"
rm -f "$output/scratch-pool-tests"
xcrun clang++ -std=c++17 -fblocks -Wall -Wextra -Werror -I"$root/MoltenVK/MoltenVK/Commands" -I"$root/MoltenVK/MoltenVK/GPUObjects" -I"$root/External/Vulkan-Headers/include" "$test_dir/PerVertexScratchPoolTests.mm" -framework Foundation -framework Metal -o "$output/scratch-pool-tests"
"$output/scratch-pool-tests"
