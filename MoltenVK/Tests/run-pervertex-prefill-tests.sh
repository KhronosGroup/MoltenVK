#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
output=${1:?Output directory required}
mkdir -p "$output"
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import os, sys
root, output = map(Path, sys.argv[1:])
source = Path(os.environ.get('MVK_MULTIVIEW_COMMAND_SOURCE', root / 'MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm')).read_text()
parts = []
for signature in ('void MVKCommandBuffer::addCommand(', 'void MVKCommandEncoder::encodeCommandsImpl(', 'void MVKCommandBuffer::releaseRecordedCommands(', 'void MVKCommandBuffer::flushImmediateCmdEncoder('):
    start = source.index(signature)
    parts.append(source[start:source.index('\n}', start) + 2])
(output / 'PrefillMethods.inc').write_text('\n'.join(parts))
PY
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all -I"$output" "$test_dir/PerVertexPrefillTests.cpp" -o "$output/prefill-tests"
"$output/prefill-tests"
