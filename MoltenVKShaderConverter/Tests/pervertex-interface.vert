// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#version 450
// Export the consumer's scalar/vector leaves: matrix/array capture export is unsupported.
layout(location = 0) out Inputs { vec3 color; vec2 basis0; vec2 basis1; vec2 uv; float weight0; float weight1; } values;
layout(location = 6) out vec2 matrix0;
layout(location = 7) out vec2 matrix1;
layout(location = 8) out vec2 matrix2;
layout(location = 9) out vec2 matrix3;
layout(location = 10) out vec2 grid0;
layout(location = 11) out vec2 grid1;
layout(location = 12) out vec2 grid2;
layout(location = 13) out vec2 grid3;
layout(location = 14, component = 0) out vec2 packed;
layout(location = 14, component = 2) out vec2 ordinary;
void main() {
    gl_Position = vec4(0, 0, 0, 1);
    values.color = vec3(1);
    values.basis0 = vec2(1, 0);
    values.basis1 = vec2(0, 1);
    values.uv = vec2(1);
    values.weight0 = 1;
    values.weight1 = 2;
    matrix0 = matrix2 = vec2(1, 0);
    matrix1 = matrix3 = vec2(0, 1);
    grid0 = vec2(0, 0);
    grid1 = vec2(0, 1);
    grid2 = vec2(1, 0);
    grid3 = vec2(1, 1);
    packed = vec2(1);
    ordinary = vec2(2);
}
