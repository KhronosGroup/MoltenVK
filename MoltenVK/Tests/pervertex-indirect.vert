#version 460
// Copyright 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// Records every invocation, then folds DrawID and first/base values into position and colour.
// REFERENCE takes DrawID from a push constant so that direct draws reproduce indirect draw N.
layout(location = 0) out vec3 color;
layout(std430, set = 0, binding = 0) buffer Effects { uint count; uint pad0, pad1, pad2; uvec4 records[]; } effects;
#ifdef REFERENCE
layout(push_constant) uniform Draw { uint drawId; } draw;
#define DRAW_ID draw.drawId
#else
#define DRAW_ID uint(gl_DrawID)
#endif
const vec2 corners[14] = vec2[14](vec2(4), vec2(4), vec2(4), vec2(4),
	vec2(-0.8, -0.8), vec2(0.8, -0.8), vec2(0.8, 0.8), vec2(0.8, 0.8), vec2(-0.8, 0.8), vec2(-0.8, -0.8),
	vec2(-0.8, -0.8), vec2(0.8, -0.8), vec2(0.8, 0.8), vec2(-0.8, 0.8));
void main() {
	uint v = uint(gl_VertexIndex), instance = uint(gl_InstanceIndex), drawId = DRAW_ID;
	uint slot = atomicAdd(effects.count, 1u);
	if (slot < 262144u) { effects.records[slot] = uvec4(v, instance, drawId | (uint(gl_BaseInstance) << 16), uint(gl_BaseVertex)); }
	vec2 p = v < 14u ? corners[v] : vec2(4.0);
	color = vec3(float(v % 5u) * 0.2, float(v % 3u) * 0.4 + 0.1 * float(drawId), 0.25 * float(uint(gl_BaseVertex) & 3u) + 0.05 * float(gl_BaseInstance));
	// Instances from 3 on overlap on the right half, so large instance counts stay visible.
	if (instance >= 3u) { color = color.gbr; }
	float x = instance == 2u ? -0.5 : instance >= 3u ? 0.5 : 4.0;
	gl_Position = vec4(p * vec2(0.45, 0.6) + vec2(x, -0.2 + 0.25 * float(drawId)), 0.0, 1.0);
#ifdef VARIED_W
	// Same window position, a different w for each corner of a triangle: perspective and linear interpolation differ.
	gl_Position *= 1.0 + 0.75 * float(v % 3u);
#endif
	gl_PointSize = 1.0;
}
