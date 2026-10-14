// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include "MVKCmdDraw.h"
#include <cassert>
#include <cstdio>

int main() {
	constexpr auto list = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
	constexpr auto strip = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
	constexpr auto fan = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN;
	assert(mvkCanEncodePerVertexDraw(0, UINT32_MAX, 0, list, 0));
	assert(mvkCanEncodePerVertexDraw(UINT32_MAX, 0, 0, fan, 0));
	assert(!mvkCanEncodePerVertexDraw(3, 1, 0, list, 1024));
	// Capture fits exactly; one more instance exceeds the rounded allocation ceiling.
	assert(mvkCanEncodePerVertexDraw(4, 2, 16, list, 128));
	assert(!mvkCanEncodePerVertexDraw(4, 3, 16, list, 128));
	assert(!mvkCanEncodePerVertexDraw(4, 3, 16, list, 255));
	assert(mvkCanEncodePerVertexDraw(4, 3, 16, list, 256));
	// Replay pairs, rather than captured records, are the limiting allocation.
	assert(mvkCanEncodePerVertexDraw(5, 1, 1, list, 64));
	assert(mvkCanEncodePerVertexDraw(4, 1, 1, strip, 64));
	assert(!mvkCanEncodePerVertexDraw(5, 1, 1, strip, 64));
	assert(mvkCanEncodePerVertexDraw(4, 1, 1, fan, 64));
	assert(!mvkCanEncodePerVertexDraw(5, 1, 1, fan, 64));
	assert(mvkCanEncodePerVertexDraw(3, 2, 1, fan, 64));
	assert(!mvkCanEncodePerVertexDraw(3, 3, 1, fan, 64));
	assert(mvkCanEncodePerVertexDraw(2, 1, 16, fan, 32));
	assert(!mvkCanEncodePerVertexDraw(2, 1, 16, fan, 31));
	// Indexing must fit uint32 even on devices with very large buffer limits.
	assert(mvkCanEncodePerVertexDraw(1, UINT32_MAX, 1, list, UINT64_MAX));
	assert(!mvkCanEncodePerVertexDraw(2, UINT32_MAX, 1, list, UINT64_MAX));
	assert(!mvkCanEncodePerVertexDraw(UINT32_MAX, UINT32_MAX, UINT32_MAX, fan, UINT64_MAX));
	assert(mvkCanEncodePerVertexDraw(UINT32_MAX / 2, 1, 1, list, UINT64_MAX));
	assert(!mvkCanEncodePerVertexDraw(UINT32_MAX / 2 + 2, 1, 1, list, UINT64_MAX));
	assert(!mvkCanEncodePerVertexDraw(UINT32_MAX / 2, 1, 1, strip, UINT64_MAX));
	std::puts("PASS: 22 production PerVertex draw-size boundary checks (CPU only)");
}
