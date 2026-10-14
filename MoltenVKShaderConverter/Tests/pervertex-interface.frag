// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#version 450
#extension GL_EXT_fragment_shader_barycentric : require
struct Nested { vec2 uv; float weights[2]; };
layout(location = 0) pervertexEXT in Inputs { vec3 color; mat2 basis; Nested nested; } values[3];
layout(location = 6) pervertexEXT in mat2 matrices[3][2];
layout(location = 10) pervertexEXT in vec2 grid[3][2][2];
layout(location = 14, component = 0) pervertexEXT in vec2 packed[3];
layout(location = 14, component = 2) in vec2 ordinary;
layout(location = 0) out vec4 color;
void main() {
    int v = int(gl_FragCoord.x) % 3;
    color = vec4(values[v].color, values[v].nested.weights[v % 2]);
    color.xy += values[v].basis[v % 2] + values[v].nested.uv;
    color.xy += matrices[v][v % 2][0] + grid[v][1][v % 2] + packed[v] + ordinary;
}
