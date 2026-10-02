// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#version 450
#extension GL_EXT_fragment_shader_barycentric : require
#ifndef PERSPECTIVE
#define PERSPECTIVE 1
#endif
#ifndef LINEAR
#define LINEAR 1
#endif
#ifndef CAPTURED
#define CAPTURED 0
#endif
#if CAPTURED
layout(location = 0) pervertexEXT in vec4 value[3];
#endif
layout(location = 0) out vec4 color;
void main() {
    color = vec4(0);
#if PERSPECTIVE
    color += vec4(gl_BaryCoordEXT, 1);
#endif
#if LINEAR
    color += vec4(gl_BaryCoordNoPerspEXT, 1);
#endif
#if CAPTURED
    color += value[0] + value[1] + value[2];
#endif
}
