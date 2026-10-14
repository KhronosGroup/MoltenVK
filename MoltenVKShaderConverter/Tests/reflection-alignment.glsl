// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#version 450
struct Nested { float scalar; vec4 wide; vec2 tail[20]; };
#if VERTEX
layout(location = 0) out
#else
layout(location = 0) in
#endif
Block {
#if HEAD
    float head;
#endif
    Nested nested[2];
    vec4 end;
} values;
#if !VERTEX
layout(location = 0) out vec4 color;
#endif
void main() {
#if VERTEX
#if HEAD
    values.head = 1;
#endif
    for (int n = 0; n < 2; ++n) {
        values.nested[n].scalar = 1;
        values.nested[n].wide = vec4(1);
        for (int i = 0; i < 20; ++i) { values.nested[n].tail[i] = vec2(1); }
    }
    values.end = vec4(1);
#else
    color = values.end;
#if HEAD
    color += values.head;
#endif
    for (int n = 0; n < 2; ++n) {
        color += values.nested[n].scalar + values.nested[n].wide;
        for (int i = 0; i < 20; ++i) { color.xy += values.nested[n].tail[i]; }
    }
#endif
}
