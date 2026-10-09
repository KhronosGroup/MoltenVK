// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// A full-screen triangle at depth 0.5, green at every corner (PerVertexAttachmentSplitTests.mm).
#version 450
layout(location = 0) out vec3 color;
void main() {
	vec2 corners[3] = vec2[](vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
	gl_Position = vec4(corners[gl_VertexIndex], 0.5, 1.0);
	color = vec3(0.0, 1.0, 0.0);
}
