#version 450
// Copyright 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// Order-sensitive weights of the three original vertex values; alpha 0.5 exposes draw order when blending.
#extension GL_EXT_fragment_shader_barycentric : require
layout(location = 0) pervertexEXT in vec3 color[3];
layout(location = 0) out vec4 outputColor;
#ifdef PORTABLE
// Also reads BaryCoordKHR, which adds nothing (a barycentric coordinate is never negative) but makes the pipeline take
// MoltenVK's portable capture and replay on every GPU, including those where plain PerVertexKHR is native.
#define ALPHA (0.5 + min(gl_BaryCoordEXT.x, 0.0))
#else
#define ALPHA 0.5
#endif
#ifdef SWAP
// Negative control: the first two corners exchanged must no longer match the reference.
void main() { outputColor = vec4(color[1] * 0.2 + color[0] * 0.3 + color[2] * 0.5, ALPHA); }
#else
void main() { outputColor = vec4(color[0] * 0.2 + color[1] * 0.3 + color[2] * 0.5, ALPHA); }
#endif
