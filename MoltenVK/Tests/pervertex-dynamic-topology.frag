#version 450
// Copyright 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// ORDINARY (default): the colour interpolated by the rasterizer, without PerVertexKHR, so that the pipeline takes
// MoltenVK's ordinary draw path.
// WEIGHTS: PerVertexKHR values and BaryCoordKHR, through the portable capture and replay.
// REFERENCE: the same output without PerVertexKHR, from the explicit triangulation of pervertex-dynamic-reference.vert.
// NOPERSPECTIVE, with WEIGHTS or REFERENCE: BaryCoordNoPerspKHR, against the weight interpolated without perspective.
// Alpha 0.5 exposes draw order when blending.
#ifdef WEIGHTS
#extension GL_EXT_fragment_shader_barycentric : require
#endif
layout(location = 0) out vec4 outputColor;
// R and G carry the first two barycentric weights; B combines the three vertex values with fixed weights by index.
// A consistent permutation of corners and weights keeps sum(value * weight) but changes all three channels.
vec4 weigh(vec3 weights, vec3 value0, vec3 value1, vec3 value2) {
	return vec4(weights.x, weights.y, 0.5 * dot(vec3(0.2, 0.3, 0.5), vec3(value0.x, value1.x, value2.x)) + 0.5 * dot(vec3(0.5, 0.2, 0.3), vec3(value0.y, value1.y, value2.y)), 0.5);
}
#if defined(WEIGHTS)
layout(location = 0) pervertexEXT in vec3 color[3];
#ifdef NOPERSPECTIVE
void main() { outputColor = weigh(gl_BaryCoordNoPerspEXT, color[0], color[1], color[2]); }
#else
void main() { outputColor = weigh(gl_BaryCoordEXT, color[0], color[1], color[2]); }
#endif
#elif defined(REFERENCE)
layout(location = 0) flat in vec3 corner0;
layout(location = 1) flat in vec3 corner1;
layout(location = 2) flat in vec3 corner2;
#ifdef NOPERSPECTIVE
layout(location = 4) noperspective in vec3 barycentric;
#else
layout(location = 3) in vec3 barycentric;
#endif
void main() { outputColor = weigh(barycentric, corner0, corner1, corner2); }
#else
layout(location = 0) in vec3 color;
void main() { outputColor = vec4(color, 0.5); }
#endif
