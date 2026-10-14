// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// Shared single-instance replay tables must equal, as a prefix, the tables each draw would have populated.
#include "MVKPerVertexReplay.h"
#include <cassert>
#include <cstdio>
#include <vector>

struct Tables { std::vector<uint32_t> pairs, indices, corners; };

static Tables populate(uint32_t vertexCount, uint32_t instances, VkPrimitiveTopology topology, bool provokingLast) {
	uint64_t primitives = std::max<uint64_t>(uint64_t(mvkPerVertexPrimitiveCount(vertexCount, topology)) * instances, 1);
	uint64_t occurrences = primitives * mvkPerVertexReplayVertexCount(topology);
	Tables t{std::vector<uint32_t>(occurrences * 2, 0xdeadbeef), std::vector<uint32_t>(primitives * 3, 0xdeadbeef), std::vector<uint32_t>(occurrences, 0xdeadbeef)};
	mvkPopulatePerVertexReplay(vertexCount, instances, topology, provokingLast, t.pairs.data(), t.indices.data(), t.corners.data());
	return t;
}

static bool isPrefix(const std::vector<uint32_t>& small, const std::vector<uint32_t>& large, size_t count) {
	return count <= large.size() && std::equal(small.begin(), small.begin() + count, large.begin());
}

static bool prefixMatches(uint32_t vertexCount, uint32_t instances, VkPrimitiveTopology topology, bool provokingLast) {
	uint64_t primitives = uint64_t(mvkPerVertexPrimitiveCount(vertexCount, topology)) * instances;
	uint64_t occurrences = primitives * mvkPerVertexReplayVertexCount(topology);
	Tables draw = populate(vertexCount, instances, topology, provokingLast);
	Tables shared = populate(mvkPerVertexSharedReplayVertexCount(vertexCount * instances), 1, topology, provokingLast);
	return isPrefix(draw.pairs, shared.pairs, occurrences * 2) && isPrefix(draw.indices, shared.indices, primitives * 3) && isPrefix(draw.corners, shared.corners, occurrences);
}

int main() {
	const VkPrimitiveTopology topologies[] = {VK_PRIMITIVE_TOPOLOGY_POINT_LIST, VK_PRIMITIVE_TOPOLOGY_LINE_LIST, VK_PRIMITIVE_TOPOLOGY_LINE_STRIP, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN};
	const uint32_t larges[] = {1023, 1024, 1025, 4097, 65535, 196608};
	unsigned checks = 0;
	for (auto topology : topologies) {
		for (bool provokingLast : {false, true}) {
			for (uint32_t n = 0; n <= 300; ++n) { assert(prefixMatches(n, 1, topology, provokingLast)); ++checks; }
			for (uint32_t n : larges) { assert(prefixMatches(n, 1, topology, provokingLast)); ++checks; }
			// Every admitted draw, instanced ones included, reads exactly its own tables from the shared ones.
			for (uint32_t instances = 2; instances <= 4; ++instances) {
				for (uint32_t n = 0; n <= 120; ++n) {
					if (mvkPerVertexReplayIsSizeIndependent(false, topology, n, instances)) { assert(prefixMatches(n, instances, topology, provokingLast)); ++checks; }
				}
			}
		}
	}
	// The guard is necessary: dangling list vertices and instanced strips shift records by the vertex count.
	assert(!mvkPerVertexReplayIsSizeIndependent(false, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, 7, 2) && !prefixMatches(7, 2, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, false));
	assert(!mvkPerVertexReplayIsSizeIndependent(false, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, 4, 2) && !prefixMatches(4, 2, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, false));
	assert(mvkPerVertexReplayIsSizeIndependent(false, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, 6, 2));
	assert(!mvkPerVertexReplayIsSizeIndependent(true, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, 6, 1));
	assert(!mvkPerVertexReplayIsSizeIndependent(false, VK_PRIMITIVE_TOPOLOGY_POINT_LIST, 0x10000, 0x10000));
	// Capacity covers every count and only doubles.
	for (uint32_t n : {0u, 1u, 1024u, 1025u, 0x80000000u, 0x80000001u, UINT32_MAX}) { assert(mvkPerVertexSharedReplayVertexCount(n) >= n); }
	printf("shared replay tables: %u prefix checks passed\n", checks);
	return 0;
}
