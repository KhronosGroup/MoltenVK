#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
# CPU only: shared single-instance replay tables against per-draw population (ASan/UBSan).
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
output=${1:-$(mktemp -d /private/tmp/mvk-shared-replay.XXXXXX)}
mkdir -p "$output"
xcrun clang++ -arch arm64 -std=c++17 -O1 -g -fsanitize=address,undefined -Wall -Wextra -I"$root/External/Vulkan-Headers/include" -I"$root/MoltenVK/MoltenVK/Commands" "$test_dir/PerVertexSharedReplayTests.cpp" -o "$output/shared-replay-tests"
"$output/shared-replay-tests"
