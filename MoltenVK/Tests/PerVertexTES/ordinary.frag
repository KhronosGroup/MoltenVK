#version 450
// Copyright 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
layout(location = 0) in vec3 color;
layout(location = 0) out vec4 outputColor;
#ifdef RESOURCES
layout(set = 0, binding = 1) uniform Scale { vec4 scale; } ubo;
#define SCALE * ubo.scale
#else
#define SCALE
#endif
void main() { outputColor = vec4(color, 1.0) SCALE; }
