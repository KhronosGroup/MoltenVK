#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
output=${1:-$(mktemp -d /private/tmp/mvk-restart.XXXXXX)}
mode=${2:-cpu}
mkdir -p "$output"
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import re, sys
root, output = map(Path, sys.argv[1:])
source = (root / 'MoltenVK/MoltenVK/Commands/MVKCommandPipelineStateFactoryShaderSource.h').read_text()
start = source.index('uint perVertexRestartPrimitiveCount(')
end = source.index('\n}\n', source.index('kernel void perVertexRestart(', start)) + 3
kernel = source[start:end]
host = re.sub(r'\[\[[^]]+\]\]', '', kernel).replace('kernel ', '').replace('device ', '').replace('constant ', 'const ')
(output / 'PerVertexRestartKernel.inc').write_text(host)
(output / 'restart.metal').write_text('#include <metal_stdlib>\nusing namespace metal;\n' + kernel)
factory = source[source.index('@R"('):].replace('@R"(', 'R"(', 1)
(output / 'factory-source.cpp').write_text('#include <cstdio>\nint main() { const char* source = ' + factory + '\nstd::fputs(source, stdout); }\n')
PY
xcrun clang++ -std=c++17 -I"$root/MoltenVK/MoltenVK/Utility" "$output/factory-source.cpp" -o "$output/factory-source"
"$output/factory-source" > "$output/factory.metal"
xcrun metal -x metal -std=macos-metal2.4 -fsyntax-only -fno-modules "$output/restart.metal"
xcrun metal -x metal -std=macos-metal2.4 -fsyntax-only -fno-modules "$output/factory.metal"
if [[ "$mode" == gpu ]]; then
    xcrun clang++ -x objective-c++ -arch arm64 -std=c++17 -O1 -g -fobjc-arc -DMVK_RESTART_GPU_TESTS -Wall -Wextra -I"$root/External/Vulkan-Headers/include" -I"$root/MoltenVK/MoltenVK/Commands" "$test_dir/PerVertexRestartTests.cpp" -framework Foundation -framework Metal -o "$output/restart-gpu-tests"
    MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 "$output/restart-gpu-tests" "$output/factory.metal"
    exit
fi
[[ "$mode" == cpu ]] || { echo "Usage: $0 [output] [cpu|gpu]" >&2; exit 1; }
xcrun clang++ -arch arm64 -std=c++17 -O1 -g -fsanitize=address,undefined -Wall -Wextra -I"$output" -I"$root/External/Vulkan-Headers/include" -I"$root/MoltenVK/MoltenVK/Commands" "$test_dir/PerVertexRestartTests.cpp" -o "$output/restart-tests"
"$output/restart-tests"
