#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../.." && pwd)
build="$root/build/portable-pervertex"
output=${1:-$(mktemp -d "$build/cache-roundtrip.XXXXXX")}
mkdir -p "$output"
output=$(cd "$output" && pwd)
library=${MVK_CACHE_LIBRARY:-"$build/cmake/moltenvk/MoltenVK/libMoltenVK.1.4.3.dylib"}
arch=${MVK_CACHE_ARCH:-x86_64}
cross_source=${MVK_CACHE_CROSS_SOURCE:-"$build/spirv-cross-bcc63e30"}

# Copy the real definitions, not a test reimplementation. Mutations affect only generated copies.
python3 - "$root" "$output" <<'PY'
import pathlib, re, sys
root, output = map(pathlib.Path, sys.argv[1:])
source = (root / 'MoltenVK/MoltenVK/GPUObjects/MVKPipeline.mm').read_text()
header = (root / 'MoltenVKShaderConverter/MoltenVKShaderConverter/SPIRVToMSLConverter.h').read_text()
start = '#pragma mark Cereal archive definitions'
end = 'template<class Archive>\nvoid serialize(Archive & archive, MVKShaderModuleKey& k)'
assert source.count(start) == source.count(end) == 1, 'Serializer extraction boundaries changed'
serializers = source.split(start, 1)[1].split(end, 1)[0]
variants = {'baseline': (serializers, header)}
for name, field in [('omit-multiview', 'opt.multiview'), ('omit-layered', 'opt.multiview_layered_rendering'), ('omit-cfg', 'cfg.perVertexInputBuffer'), ('omit-used-flag', 'scr.needsPerVertexInputBuffer'), ('omit-result-layout', 'scr.capturedVertexLayout')]:
    changed, count = re.subn(r',\s*' + re.escape(field) + r'\b', '', serializers)
    assert count == 1, f'Missing or repeated production field: {field}'
    variants[name] = (changed, header)
changed, count = re.subn(r',\s*cfg\.exportCapturedVertexLayout\b', '', serializers)
assert count == 1, 'Missing or repeated production field: cfg.exportCapturedVertexLayout'
variants['omit-export-layout'] = (changed, header)
for name, field in [('omit-user-fields', 'layout.components'), ('omit-builtins', 'layout.builtins')]:
    changed, count = re.subn(r',\s*' + re.escape(field) + r'\b', '', header)
    assert count == 1, f'Missing or repeated production field: {field}'
    variants[name] = (serializers, changed)
for name, (definitions, declarations) in variants.items():
    directory = output / name
    directory.mkdir(exist_ok=True)
    (directory / 'PipelineCacheSerializers.inc').write_text(definitions)
    (directory / 'SPIRVToMSLConverter.h').write_text(declarations)
PY
shasum -a 256 "$root/MoltenVK/MoltenVK/GPUObjects/MVKPipeline.mm" "$root/MoltenVKShaderConverter/MoltenVKShaderConverter/SPIRVToMSLConverter.h" "$library" > "$output/sources.sha256"
for variant in baseline omit-multiview omit-layered omit-cfg omit-export-layout omit-used-flag omit-result-layout omit-user-fields omit-builtins; do
    directory="$output/$variant"
    xcrun clang++ -arch "$arch" -mmacosx-version-min=11.0 -std=c++17 -O0 -g \
        -DSPIRV_CROSS_NAMESPACE_OVERRIDE=MVK_spirv_cross \
        -I "$directory" -I "$cross_source" -I "$root/External/cereal/include" \
        "$test_dir/PipelineCachePerVertexTests.cpp" "$library" \
        -Wl,-rpath,"$(dirname "$library")" -o "$directory/cache-test"
    status=0
    "$directory/cache-test" > "$directory/result.log" 2>&1 || status=$?
    if [[ "$variant" == baseline ]]; then
        cat "$directory/result.log"
        [[ "$status" == 0 ]] || exit "$status"
    else
        if [[ "$status" != 2 ]] || ! rg -q '^FAIL: (cfg|scr)' "$directory/result.log"; then
            cat "$directory/result.log"
            echo "FAIL: $variant did not produce the expected semantic failure (exit $status)" >&2
            exit 1
        fi
        printf 'PASS: %s detected: ' "$variant"
        cat "$directory/result.log"
    fi
done
echo "PASS: production cfg/scr round-trip and all eight omission controls; evidence: $output"
