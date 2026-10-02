#version 460
// Copyright 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// Explicit triangulation of one draw of PerVertexDynamicTopologyTests.mm, drawn as a triangle list without PerVertexKHR.
// Vertex k is corner k % 3 of triangle k / 3. The corners come from the draw's six vertices (4 to 9) in the order of the
// Vulkan barycentric order table, provoking vertex first, as the CTS encodes it (getDataVertexFormula in
// vktFragmentShadingBarycentricTests.cpp): list (3p, 3p+1, 3p+2); strip (p, even ? p+1 : p+2, even ? p+2 : p+1); fan
// (p+1, p+2, 0). Every vertex carries the three corner values flat and a one-hot barycentric weight.
// rotate = 1 is the negative control: the corners of every triangle turn by one, a consistent permutation.
// Positions and values repeat pervertex-indirect.vert for DrawID 0 and gl_BaseVertex & 3 == 0. VARIED_W repeats its w
// per vertex and adds the barycentric weight interpolated without perspective.
layout(push_constant) uniform Draw { uint topology; uint rotate; } draw;  // VkPrimitiveTopology: 3 list, 4 strip, 5 fan
layout(location = 0) flat out vec3 corner0;
layout(location = 1) flat out vec3 corner1;
layout(location = 2) flat out vec3 corner2;
layout(location = 3) out vec3 barycentric;
#ifdef VARIED_W
layout(location = 4) noperspective out vec3 barycentricLinear;
#endif
const vec2 corners[14] = vec2[14](vec2(4), vec2(4), vec2(4), vec2(4),
	vec2(-0.8, -0.8), vec2(0.8, -0.8), vec2(0.8, 0.8), vec2(0.8, 0.8), vec2(-0.8, 0.8), vec2(-0.8, -0.8),
	vec2(-0.8, -0.8), vec2(0.8, -0.8), vec2(0.8, 0.8), vec2(-0.8, 0.8));
uint source(uint p, uint corner) {
	corner = (corner + draw.rotate) % 3u;
	bool even = (p & 1u) == 0u;
	uint v = draw.topology == 3u ? 3u * p + corner
	       : draw.topology == 4u ? (corner == 0u ? p : even == (corner == 1u) ? p + 1u : p + 2u)
	       : (corner == 0u ? p + 1u : corner == 1u ? p + 2u : 0u);
	return 4u + v;
}
vec3 value(uint v, uint instance) {
	vec3 color = vec3(float(v % 5u) * 0.2, float(v % 3u) * 0.4 + 0.1 * float(0u), 0.25 * float(uint(gl_BaseVertex) & 3u) + 0.05 * float(gl_BaseInstance));
	return instance >= 3u ? color.gbr : color;
}
void main() {
	uint k = uint(gl_VertexIndex), p = k / 3u, corner = k % 3u, instance = uint(gl_InstanceIndex), v = source(p, corner);
	corner0 = value(source(p, 0u), instance);
	corner1 = value(source(p, 1u), instance);
	corner2 = value(source(p, 2u), instance);
	barycentric = vec3(corner == 0u, corner == 1u, corner == 2u);
#ifdef VARIED_W
	barycentricLinear = barycentric;
#endif
	vec2 position = v < 14u ? corners[v] : vec2(4.0);
	float x = instance == 2u ? -0.5 : instance >= 3u ? 0.5 : 4.0;
	gl_Position = vec4(position * vec2(0.45, 0.6) + vec2(x, -0.2 + 0.25 * float(0u)), 0.0, 1.0);
#ifdef VARIED_W
	gl_Position *= 1.0 + 0.75 * float(v % 3u);
#endif
}
