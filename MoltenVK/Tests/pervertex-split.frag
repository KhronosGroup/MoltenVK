// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// Reads the three PerVertexKHR corner colors: a portable capture and replay on GPUs without native vertex_value.
#version 450
#extension GL_EXT_fragment_shader_barycentric : require
layout(location = 0) pervertexEXT in vec3 color[];
layout(location = 0) out vec4 fragColor;
void main() { fragColor = vec4(color[0] * 0.5 + color[1] * 0.25 + color[2] * 0.25, 1.0); }
