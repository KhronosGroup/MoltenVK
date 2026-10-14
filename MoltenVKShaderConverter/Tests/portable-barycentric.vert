// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#version 450
layout(location = 0) in vec4 position;
layout(location = 0) out vec4 value;
out gl_PerVertex {
    vec4 gl_Position;
#ifdef POINTS
    float gl_PointSize;
#endif
};
void main() {
    gl_Position = position;
    value = position;
#ifdef POINTS
    gl_PointSize = 3.0;
#endif
}
