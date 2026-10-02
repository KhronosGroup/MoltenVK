#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
output=${1:-$(mktemp -d /private/tmp/mvk-topology.XXXXXX)}
mkdir -p "$output"
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import re, sys
root, output = map(Path, sys.argv[1:])
source = (root / 'MoltenVK/MoltenVK/Commands/MVKCommandPipelineStateFactoryShaderSource.h').read_text()
kernel, = re.findall(r'kernel void convertUint8IndicesRaw\([^}]+\}', source)
# Execute the actual production kernel body on CPU; only remove Metal declarations/attributes.
host = re.sub(r'\[\[[^]]+\]\]', '', kernel).replace('kernel ', '').replace('device ', '').replace('uint pos', 'uint32_t pos')
(output / 'PerVertexUint8Kernel.inc').write_text(host)
(output / 'uint8-raw.metal').write_text('#include <metal_stdlib>\nusing namespace metal;\n' + kernel)
PY
xcrun metal -x metal -std=macos-metal2.4 -fsyntax-only -fno-modules "$output/uint8-raw.metal"
includes=(-I"$output" -I"$root/Common" -I"$root/MoltenVK/include" -I"$root/External/Vulkan-Headers/include")
for directory in API Commands GPUObjects Layers OS Utility Vulkan; do
    includes+=(-I"$root/MoltenVK/MoltenVK/$directory")
done
xcrun clang++ -arch arm64 -std=c++17 -fsanitize=address,undefined -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations "${includes[@]}" "$test_dir/PerVertexTopologyTests.mm" -framework Foundation -framework Metal -o "$output/topology-tests"
"$output/topology-tests"
