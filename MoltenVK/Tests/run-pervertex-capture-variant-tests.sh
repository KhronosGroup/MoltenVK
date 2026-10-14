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
objects = root / 'MoltenVK/MoltenVK/GPUObjects'
source = Path(os.environ.get('MVK_MULTIVIEW_PIPELINE_SOURCE', objects / 'MVKPipeline.mm')).read_text()
header = (objects / 'MVKPipeline.h').read_text()
start = source.index('void MVKGraphicsPipeline::adjustVertexInputForMultiview(')
parts = [source[start:source.index('\n}', start) + 2]]
for name, return_type, args in [('getPerVertexCapturePipelineState', 'id<MTLRenderPipelineState>', 'uint32_t viewCount'), ('getPerVertexIndexedCapturePipelineState', 'id<MTLComputePipelineState>', 'bool index32, uint32_t viewCount')]:
    start = header.index(' const {', header.index(name + '('))
    parts.append(return_type + ' MVKGraphicsPipeline::' + name + '(' + args + ')' + header[start:header.index('\n\t}', start) + 3])
start = source.index('bool captured = ', source.index('bool MVKGraphicsPipeline::addPerVertexReplayShaderToPipeline('))
parts.append('bool MVKGraphicsPipeline::build(MTLRenderPipelineDescriptor* plDesc, const VkGraphicsPipelineCreateInfo* pCreateInfo) { int shaderConfig = 0; const void* pVertexSS = nullptr; (void)shaderConfig; (void)pVertexSS;\n' + source[start:source.index('\n\tplDesc.inputPrimitiveTopology', start)] + '\nreturn captured;\n}')
start = source.index('\tfor (uint32_t i = 0; i < 31; i++)', source.index('bool MVKGraphicsPipeline::addPerVertexIndexedCapturePipelines('))
parts.append('bool MVKGraphicsPipeline::addPerVertexIndexedCapturePipelines(MTLVertexDescriptor* vertexDesc, int, const void*, uint32_t viewCount) { auto* plDesc = [MTLComputePipelineDescriptor new]; plDesc.stageInputDescriptor = [MTLStageInputOutputDescriptor stageInputOutputDescriptor];\n' + source[start:source.index('\n\tMSLPerVertexInputBuffer expectedLayout', start)] + '\nauto& states = _perVertexCapturePipelineStates[viewCount]; states.index16 = (id<MTLComputePipelineState>)[plDesc.stageInputDescriptor copy]; states.index32 = (id<MTLComputePipelineState>)[plDesc.stageInputDescriptor copy]; [plDesc release]; return true;\n}')
(output / 'CaptureVariantMethods.inc').write_text('\n'.join(parts))
PY
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -Wno-unused-parameter -fsanitize=address,undefined -fno-sanitize-recover=all \
    -I"$output" -I"$root/External/Vulkan-Headers/include" "$test_dir/PerVertexCaptureVariantTests.mm" -framework Foundation -framework Metal -o "$output/capture-variant-tests"
"$output/capture-variant-tests"
