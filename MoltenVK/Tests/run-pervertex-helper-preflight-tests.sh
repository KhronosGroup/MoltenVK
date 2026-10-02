#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
output=${1:-$(mktemp -d /private/tmp/mvk-helper-preflight.XXXXXX)}
mkdir -p "$output"
# Compile the production preflight/cache method bodies against CPU-only doubles.
# Set MVK_TEST_REVISION=9f1cb26a to exercise the original implementation.
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import os, re, subprocess, sys
root, output = map(Path, sys.argv[1:])
revision = os.environ.get('MVK_TEST_REVISION')
def read(path):
    return subprocess.check_output(['git', 'show', f'{revision}:{path}'], cwd=root, text=True) if revision else (root / path).read_text()
commands = 'MoltenVK/MoltenVK/Commands/'
source = read(commands + 'MVKCommandBuffer.mm')
methods = re.findall(r'VkResult MVKCommandBuffer::reserve(?:Prefilled)?PerVertexScratch\([^\n]*\) \{\n.*?\n\}', source, re.S)
assert len(methods) in (2, 3), 'Update production-method extraction for changed signatures'
pool = read(commands + 'MVKCommandEncodingPool.mm')
getters = re.findall(r'id<MTLComputePipelineState> MVKCommandEncodingPool::get(?:ConvertUint8Indices|PerVertexRestart|PerVertexIndirect|PerVertexTessTopology)MTLComputePipelineState\([^\n]*\) \{\n.*?\n\}', pool, re.S)
assert len(getters) in (2, 3, 4)
macro = re.search(r'#define MVK_ENC_REZ_ACCESS.*?(?=\n\n)', pool, re.S).group()
(output / 'HelperPreflightMethods.inc').write_text(macro + '\n' + '\n'.join(getters + methods))
scratch = read(commands + 'MVKPerVertexScratch.h')
(output / 'MVKPerVertexScratch.h').write_text(scratch)
(output / 'HelperPreflightVersion.inc').write_text('#define MVK_TEST_HAS_PREPARED_HELPER ' + str(int('indexPipeline' in scratch)) + '\n#define MVK_TEST_HAS_INDIRECT ' + str(int('indirectPipeline' in scratch)) + '\n#define MVK_TEST_HAS_TES_TOPOLOGY ' + str(int('tessTopologyPipeline' in scratch)) + '\n')
PY
xcrun clang++ -std=c++17 -fblocks -arch arm64 -Wall -Wextra -Werror -fsanitize="${MVK_TEST_SANITIZERS:-address,undefined}" -I"$output" -I"$root/MoltenVK/MoltenVK/Commands" -I"$root/MoltenVK/MoltenVK/GPUObjects" -I"$root/External/Vulkan-Headers/include" "$test_dir/PerVertexHelperPreflightTests.mm" -framework Foundation -framework Metal -o "$output/helper-preflight-tests"
"$output/helper-preflight-tests"
