#!/usr/bin/env python3
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
# Selects, from a fragment_shading_barycentric case list, the cases of the minimal experimental scope: vertex and
# fragment stages, provoking vertex first, no adjacency, no tessellation, no mesh, single sample. Barycentric weights
# are kept for triangles only: points and lines are not promised defined weights. Per-vertex data cases keep every
# simple topology, static and dynamic.
# Usage: select-experimental-scope.py <case list> <output list>
import sys


def in_scope(case):
    if case.endswith('.data.misc.pervertex_correctness'):
        return True
    if '.shader_combos.' in case or '.provoking_last.' in case or 'adjacency' in case:
        return False
    if not case.endswith('.vertex_shader'):
        return False
    if '.weights.' in case:
        topology = case.split('.')[6]
        return '.msaa_' not in case and topology.startswith('triangle')
    return '.data.' in case


cases = [line.strip() for line in open(sys.argv[1]) if line.strip()]
selected = [case for case in cases if in_scope(case)]
with open(sys.argv[2], 'w') as output:
    output.write(''.join(case + '\n' for case in selected))
print(f'{len(selected)} of {len(cases)} cases selected')
