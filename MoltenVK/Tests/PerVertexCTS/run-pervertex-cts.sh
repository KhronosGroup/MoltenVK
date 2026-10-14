#!/bin/bash
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
# Runs a CTS case list against a MoltenVK test build whose test device adapters AdapterShim.c opens, in chunks run one
# after the other, each under gtimeout. When deqp-vk dies (crash, Metal assertion, timeout), the case it died on is
# recorded and the list resumes after it, so one crash never hides the remaining cases. The run stops if free disk
# space falls under 8 GiB, or if deqp-vk twice in a row dies before producing any result.
# The MoltenVK settings are those of Scripts/runcts, without its Metal API validation: "validated" adds
# MTL_DEBUG_LAYER=1 and MTL_SHADER_VALIDATION=1.
# Output: results.csv (case,status,message), summary.txt, per-status case lists, crashes.txt, runs/ (case list, qpa and log of
# each deqp-vk process), INPUTS.sha256 and ENVIRONMENT.txt.
# PERVERTEX_CTS_DIRECT=1 gives deqp-vk the library itself, without the shim: for a public build, whose extension gates
# stay closed, such as the synchronization cases that do not depend on the test adapters.
# Usage: run-pervertex-cts.sh <directory of deqp-vk> <libMoltenVK test build> <case list> <output> <validated|plain> [chunk size]
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$test_dir/../../.." && pwd)
cts=$(cd "${1:?deqp-vk directory}" && pwd)
library=$(cd "$(dirname "${2:?libMoltenVK}")" && pwd)/$(basename "$2")
caselist=$(cd "$(dirname "${3:?case list}")" && pwd)/$(basename "$3")
output=$(mkdir -p "${4:?output}" && cd "$4" && pwd)
mode=${5:?validated or plain}
chunk=${6:-500}
[[ $mode == validated || $mode == plain ]] || { echo 'mode must be validated or plain'; exit 64; }
mkdir -p "$output/runs"
shim=$output/libpervertex-cts-shim.dylib
xcrun clang -dynamiclib -O2 -Wall -Wextra -Werror -I"$root/External/Vulkan-Headers/include" "$test_dir/AdapterShim.c" -o "$shim"
vulkan_library=$shim
[[ -z ${PERVERTEX_CTS_DIRECT:-} ]] || vulkan_library=$library
{ sw_vers; uname -m; date -u; echo "mode=$mode chunk=$chunk vulkan_library=$([[ -z ${PERVERTEX_CTS_DIRECT:-} ]] && echo shim || echo direct)"; echo "moltenvk_checkout=$(git -C "$root" rev-parse HEAD)"; cat "$(dirname "$library")/../../../PROVENANCE.txt" 2>/dev/null || true; } > "$output/ENVIRONMENT.txt"
shasum -a 256 "$cts/deqp-vk" "$library" "$caselist" "$shim" > "$output/INPUTS.sha256"
validation=()
[[ $mode == plain ]] || validation=(MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1)
: > "$output/results.csv"
: > "$output/crashes.txt"
pending=$output/pending.txt
cp "$caselist" "$pending"
run=0 empty=0
while [[ -s $pending ]]; do
	free=$(/bin/df -g "$output" | awk 'NR==2{print $4}')
	(( free >= 8 )) || { echo "STOP: $free GiB free, under the 8 GiB floor"; exit 3; }
	run=$((run + 1))
	name=$output/runs/$(printf 'run-%05d' "$run")
	head -n "$chunk" "$pending" > "$name.txt"
	rc=0
	(cd "$cts" && env -u DYLD_LIBRARY_PATH -u DYLD_INSERT_LIBRARIES PERVERTEX_CTS_MOLTENVK="$library" \
		MVK_CONFIG_LOG_LEVEL=1 MVK_CONFIG_RESUME_LOST_DEVICE=1 MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1 MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE=2 \
		${validation[@]+"${validation[@]}"} gtimeout -k 10 1800 ./deqp-vk --deqp-vk-library-path="$vulkan_library" --deqp-archive-dir="$cts" \
		--deqp-log-filename="$name.qpa" --deqp-log-images=disable --deqp-log-shader-sources=disable --deqp-shadercache=disable \
		--deqp-log-decompiled-spirv=disable --deqp-caselist-file="$name.txt") > "$name.log" 2>&1 || rc=$?
	python3 "$test_dir/parse-qpa.py" "$name.qpa" > "$name.csv" 2>/dev/null || true
	# The first case of this run without a result is the one deqp-vk died on; the others go back to the list.
	result=$(python3 - "$name" "$pending" "$chunk" "$rc" <<'PY'
import sys
name, pending, chunk, rc = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
cases = open(name + ".txt").read().split()
done = {line.split(",")[0] for line in open(name + ".csv") if line.strip()}
missing = [case for case in cases if case not in done]
rest = open(pending).read().split()[chunk:]
extra = []
if missing:
    reason = "Timeout" if rc in (124, 137) else f"Crash:exit={rc}" if rc else "Missing"
    extra.append(f"{missing[0]},{reason}")
    if rc == 0:
        extra += [f"{case},Missing" for case in missing[1:]]
        missing = []
    else:
        missing = missing[1:]
open(pending, "w").write("".join(case + "\n" for case in missing + rest))
with open(name + ".csv", "a") as csv:
    csv.write("".join(line + "\n" for line in extra))
print(f"{len(done)} {extra[0] if extra else ''}")
PY
)
	cat "$name.csv" >> "$output/results.csv"
	crash=${result#* }
	if [[ -n $crash ]]; then
		echo "$crash $(basename "$name") $(grep -m1 -E 'failed assertion|ERROR|Assertion' "$name.log" | cut -c1-300)" >> "$output/crashes.txt"
	fi
	if [[ ${result%% *} == 0 && $rc != 0 ]]; then empty=$((empty + 1)); else empty=0; fi
	(( empty < 2 )) || { echo "STOP: deqp-vk died twice without a result; see $name.log"; exit 4; }
	echo "$(date -u +%H:%M:%S) $(basename "$name") results=${result%% *} exit=$rc ${crash:+died on $crash} pending=$(wc -l < "$pending" | tr -d ' ')"
done
python3 - "$output" <<'PY'
import collections, sys
output = sys.argv[1]
statuses = collections.OrderedDict()
for line in open(f"{output}/results.csv"):
    case, status, *message = line.rstrip("\n").split(",", 2)
    statuses.setdefault(status.split(":")[0], []).append(case + ("\t" + message[0] if message else ""))
with open(f"{output}/summary.txt", "w") as summary:
    for status, cases in sorted(statuses.items(), key=lambda item: -len(item[1])):
        summary.write(f"{status} {len(cases)}\n")
        open(f"{output}/{status}.txt", "w").write("".join(case + "\n" for case in cases))
print(open(f"{output}/summary.txt").read(), end="")
PY
(cd "$output" && shasum -a 256 results.csv summary.txt crashes.txt > SHA256SUMS)
