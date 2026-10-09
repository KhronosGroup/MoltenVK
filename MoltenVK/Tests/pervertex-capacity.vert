// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#version 450
#if DENSE
layout(location = 0) out vec4 values[LOCATIONS - 3];
layout(location = LOCATIONS - 3) out vec2 tail[3];
#else
layout(location = 0) out float values[LOCATIONS];
#endif
void main() {
    gl_Position = vec4(float(gl_VertexIndex), 0.0, 0.0, 1.0);
#if DENSE
    for (int i = 0; i < LOCATIONS - 3; ++i) { values[i] = vec4(float(i + gl_VertexIndex)); }
    for (int i = 0; i < 3; ++i) { tail[i] = vec2(float(i + gl_VertexIndex)); }
#else
    for (int i = 0; i < LOCATIONS; ++i) { values[i] = float(i + gl_VertexIndex); }
#endif
}
