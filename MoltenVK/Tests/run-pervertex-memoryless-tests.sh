#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
output=${1:-$(mktemp -d /private/tmp/mvk-memoryless.XXXXXX)}
mkdir -p "$output"
# Compile the production storage decision, not a copy of the policy.
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
source = (root / 'MoltenVK/MoltenVK/GPUObjects/MVKImage.mm').read_text()
start = source.index('MTLStorageMode MVKImage::getMTLStorageMode()')
(output / 'ImageStorageMode.inc').write_text(source[start:source.index('\n}', start) + 2])
PY
xcrun clang++ -std=c++17 -fblocks -I"$output" -I"$root/External/Vulkan-Headers/include" "$test_dir/PerVertexMemorylessTests.mm" -framework Foundation -framework Metal -o "$output/memoryless-tests"
"$output/memoryless-tests" "${2:-}"
