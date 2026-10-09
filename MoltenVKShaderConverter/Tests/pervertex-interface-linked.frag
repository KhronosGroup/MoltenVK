// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#version 450
#extension GL_EXT_fragment_shader_barycentric : require
layout(location = 0) pervertexEXT in Inputs { vec3 color; vec2 basis0; vec2 basis1; vec2 uv; float weight0; float weight1; } values[3];
layout(location = 6) pervertexEXT in vec2 matrix0[3];
layout(location = 7) pervertexEXT in vec2 matrix1[3];
layout(location = 8) pervertexEXT in vec2 matrix2[3];
layout(location = 9) pervertexEXT in vec2 matrix3[3];
layout(location = 10) pervertexEXT in vec2 grid0[3];
layout(location = 11) pervertexEXT in vec2 grid1[3];
layout(location = 12) pervertexEXT in vec2 grid2[3];
layout(location = 13) pervertexEXT in vec2 grid3[3];
layout(location = 14, component = 0) pervertexEXT in vec2 packed[3];
layout(location = 14, component = 2) in vec2 ordinary;
layout(location = 0) out vec4 color;
void main() {
    int v = int(gl_FragCoord.x) % 3;
    color = vec4(values[v].color, values[v].weight0 + values[v].weight1);
    color.xy += values[v].basis0 + values[v].basis1 + values[v].uv;
    color.xy += matrix0[v] + matrix1[v] + matrix2[v] + matrix3[v];
    color.xy += grid0[v] + grid1[v] + grid2[v] + grid3[v] + packed[v] + ordinary;
}
