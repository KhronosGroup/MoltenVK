// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include "MVKCmdDraw.h"
#include <array>
#include <cassert>
#include <cstdio>
#include <vector>
#include "PerVertexUint8Kernel.inc"

static void checkUint8Kernel() {
	std::array<uint8_t, 258> source{};
	for (uint32_t i = 0; i < 256; ++i) { source[1 + i] = uint8_t(i); }
	// Exact and partial threadgroups must cover the requested range, including index 255.
	for (uint32_t count : {1u, 31u, 32u, 33u, 255u, 256u}) {
		for (uint32_t width : {16u, 32u, 64u}) {
			std::vector<uint16_t> result(count + 2, 0xbeef);
			uint32_t groups = count / width, remainder = count % width;
			for (uint32_t i = 0; i < groups * width; ++i) { convertUint8IndicesRaw(source.data() + 1, result.data() + 1, i); }
			for (uint32_t i = 0; i < remainder; ++i) { convertUint8IndicesRaw(source.data() + 1 + groups * width, result.data() + 1 + groups * width, i); }
			assert(result.front() == 0xbeef && result.back() == 0xbeef);
			for (uint32_t i = 0; i < count; ++i) { assert(result[1 + i] == i); }
		}
	}
}

static void checkPayloads() {
	struct Case { VkPrimitiveTopology topology; uint32_t count; std::vector<uint32_t> triplets; };
	const Case cases[] = {
		{VK_PRIMITIVE_TOPOLOGY_POINT_LIST, 3, {0,0,0, 1,1,1, 2,2,2}},
		{VK_PRIMITIVE_TOPOLOGY_LINE_LIST, 5, {0,1,1, 2,3,3}},
		{VK_PRIMITIVE_TOPOLOGY_LINE_STRIP, 4, {0,1,1, 1,2,2, 2,3,3}}
	};
	for (const auto& c : cases) {
		for (bool last : {false, true}) {
			for (uint32_t instances : {1u, 3u}) {
				uint32_t primitives = uint32_t(c.triplets.size()) / 3;
				uint32_t vertices = mvkPerVertexReplayVertexCount(c.topology);
				uint32_t count = primitives * instances * vertices;
				constexpr uint32_t guard = 0xcafef00d;
				std::vector<uint32_t> pairs(2 * count + 2, guard), triplets(3 * primitives * instances + 2, guard), corners(count + 2, guard);
				mvkPopulatePerVertexReplay(c.count, instances, c.topology, last, pairs.data() + 1, triplets.data() + 1, corners.data() + 1);
				assert(pairs.front() == guard && pairs.back() == guard && triplets.front() == guard && triplets.back() == guard && corners.front() == guard && corners.back() == guard);
				for (uint32_t instance = 0; instance < instances; ++instance) {
					for (uint32_t primitive = 0; primitive < primitives; ++primitive) {
						uint32_t key = instance * primitives + primitive;
						for (uint32_t corner = 0; corner < 3; ++corner) {
							uint32_t record = instance * c.count + c.triplets[3 * primitive + corner];
							assert(triplets[1 + 3 * key + corner] == record);
							if (corner >= vertices) { continue; }
							uint32_t occurrence = key * vertices + corner;
							assert(pairs[1 + 2 * occurrence] == record && pairs[2 + 2 * occurrence] == key);
							assert(corners[1 + occurrence] == corner); // point (1,0,0); line endpoints (1,0,0),(0,1,0).
							// Dense capture must retain repeated indices, signed baseVertex and firstInstance.
							for (VkIndexType type : {VK_INDEX_TYPE_UINT8, VK_INDEX_TYPE_UINT16, VK_INDEX_TYPE_UINT32}) {
								const uint32_t input[] = {99, 99, 255, 7, 255, 9, 10};
								uint32_t firstIndex = 2, firstInstance = 11;
								int32_t baseVertex = -3;
								std::vector<std::array<uint32_t, 2>> captured(c.count * instances);
								for (uint32_t i = 0; i < instances; ++i) {
									for (uint32_t v = 0; v < c.count; ++v) {
										uint32_t index = type == VK_INDEX_TYPE_UINT8 ? uint8_t(input[firstIndex + v]) : type == VK_INDEX_TYPE_UINT16 ? uint16_t(input[firstIndex + v]) : input[firstIndex + v];
										captured[i * c.count + v] = {index + uint32_t(baseVertex), i + firstInstance};
									}
								}
								assert(captured[pairs[1 + 2 * occurrence]][0] == input[firstIndex + c.triplets[3 * primitive + corner]] - 3);
								assert(captured[triplets[1 + 3 * key + corner]][1] == instance + firstInstance);
							}
							// Nonindexed firstVertex is applied during capture, never to dense replay addresses.
							assert(pairs[1 + 2 * occurrence] % c.count + 17 == c.triplets[3 * primitive + corner] + 17);
						}
						uint32_t provokingCorner = last ? vertices - 1 : 0;
						assert(pairs[1 + 2 * (key * vertices + provokingCorner)] == instance * c.count + c.triplets[3 * primitive + provokingCorner]);
					}
				}
				auto saved = pairs;
				mvkPopulatePerVertexReplay(c.count, instances, c.topology, last, pairs.data() + 1, triplets.data() + 1, nullptr);
				assert(saved == pairs);
			}
		}
	}
	for (auto topology : {VK_PRIMITIVE_TOPOLOGY_POINT_LIST, VK_PRIMITIVE_TOPOLOGY_LINE_LIST, VK_PRIMITIVE_TOPOLOGY_LINE_STRIP}) {
		uint32_t sentinel = 99;
		mvkPopulatePerVertexReplay(0, 3, topology, false, &sentinel, &sentinel, &sentinel);
		mvkPopulatePerVertexReplay(3, 0, topology, true, &sentinel, &sentinel, &sentinel);
		if (topology != VK_PRIMITIVE_TOPOLOGY_POINT_LIST) { mvkPopulatePerVertexReplay(1, 3, topology, false, &sentinel, &sentinel, &sentinel); }
		assert(sentinel == 99);
	}
}

static void checkBounds() {
	assert(!mvkPerVertexRequiresRestartAssembly(false, false));
	assert(!mvkPerVertexRequiresRestartAssembly(false, true)); // Legal nonindexed draws ignore restart.
	assert(!mvkPerVertexRequiresRestartAssembly(true, false)); // UINT8 255 is an ordinary index.
	assert(mvkPerVertexRequiresRestartAssembly(true, true)); // Reject before capture or scratch use.
	const auto point = VK_PRIMITIVE_TOPOLOGY_POINT_LIST, line = VK_PRIMITIVE_TOPOLOGY_LINE_LIST, strip = VK_PRIMITIVE_TOPOLOGY_LINE_STRIP;
	assert(mvkCanEncodePerVertexDraw(2, 1, 1, point, 32));
	assert(!mvkCanEncodePerVertexDraw(3, 1, 1, point, 32)); // triplets, not occurrence pairs, are limiting.
	assert(mvkCanEncodePerVertexDraw(4, 1, 1, line, 32));
	assert(!mvkCanEncodePerVertexDraw(6, 1, 1, line, 32));
	assert(mvkCanEncodePerVertexDraw(3, 1, 1, strip, 32));
	assert(!mvkCanEncodePerVertexDraw(4, 1, 1, strip, 32));
	assert(mvkCanEncodePerVertexDraw(1, 2, 1, point, 32));
	assert(!mvkCanEncodePerVertexDraw(1, 3, 1, point, 32));
	assert(!mvkCanEncodePerVertexDraw(1, 1, 1, point, 0));
	assert(!mvkCanEncodePerVertexDraw(1, 1, 0, point, 32));
	assert(mvkCanEncodePerVertexDraw(UINT32_MAX / 3, 1, 1, point, UINT64_MAX));
	assert(!mvkCanEncodePerVertexDraw(UINT32_MAX / 3 + 1, 1, 1, point, UINT64_MAX));
	assert(!mvkCanEncodePerVertexDraw(UINT32_MAX, UINT32_MAX, UINT32_MAX, strip, UINT64_MAX));
	assert(!mvkCanEncodePerVertexDraw(4, 1, 1, VK_PRIMITIVE_TOPOLOGY_LINE_LIST_WITH_ADJACENCY, 1024));
	assert(!mvkCanEncodePerVertexDraw(3, 1, 1, VK_PRIMITIVE_TOPOLOGY_PATCH_LIST, 1024));
	for (auto type : {VK_INDEX_TYPE_UINT8, VK_INDEX_TYPE_UINT16, VK_INDEX_TYPE_UINT32}) {
		uint64_t size = mvkPerVertexIndexSize(type);
		assert(mvkPerVertexIndexRange(3, 2, type, 5 * size, 7, 7 + 5 * size));
		assert(!mvkPerVertexIndexRange(3, 2, type, 5 * size - 1, 7, 7 + 5 * size));
		assert(!mvkPerVertexIndexRange(3, 2, type, 5 * size, 7, 7 + 5 * size - 1));
		assert(!mvkPerVertexIndexRange(3, 2, type, 5 * size, UINT64_MAX, UINT64_MAX));
		assert(!mvkPerVertexIndexRange(3, 2, type, 5 * size, 8, 7));
		assert(!mvkPerVertexIndexRange(1, UINT32_MAX, type, size * UINT32_MAX, 0, UINT64_MAX));
		assert(mvkPerVertexIndexRange(UINT32_MAX, UINT32_MAX, type, 2 * size * UINT32_MAX, 0, UINT64_MAX));
	}
	assert(!mvkPerVertexIndexRange(1, 0, VK_INDEX_TYPE_NONE_KHR, 100, 0, 100));
}

int main() {
	checkUint8Kernel();
	checkPayloads();
	checkBounds();
	std::puts("PASS: point/line-list/line-strip triplets and raster corners, both provoking modes, indexed/nonindexed instance address models, production UINT8 kernel (all byte values and dispatch tails), sentinels, empty/incomplete primitives, unsupported topologies and integer/buffer boundaries (CPU only)");
}
