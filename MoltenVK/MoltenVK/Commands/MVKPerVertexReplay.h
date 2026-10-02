/* Copyright (c) 2026 Jean-Philippe Meunier. Licensed under the Apache License, Version 2.0. */
#pragma once
#include <vulkan/vulkan.h>
#include <algorithm>
#include <cstdint>
#include <unordered_set>

// Vulkan ignores restart for nonindexed draws; indexed restart needs GPU primitive assembly.
static inline bool mvkPerVertexRequiresRestartAssembly(bool indexed, bool primitiveRestart) { return indexed && primitiveRestart; }

// Dense capture record IDs are uint32. Buffer sizes are checked separately before reservation.
static inline bool mvkCanAssemblePerVertexRestart(uint32_t count, uint32_t instances, bool indirectDrawing) { return indirectDrawing && uint64_t(count) * instances <= UINT32_MAX; }

// Compact UINT32 indices followed by two ping-pong scans of four uints per input index.
static inline uint64_t mvkPerVertexRestartIndexScratchSize(uint32_t count) { return uint64_t(count) * 9 * sizeof(uint32_t); }

// Indirect restart encodes the scan steps of the largest admissible count; surplus steps only copy.
static inline uint32_t mvkPerVertexIndirectRestartScanSteps(uint32_t capacity) {
	uint32_t steps = 0;
	for (uint64_t step = 1; step < capacity; step *= 2) { ++steps; }
	return steps;
}

// Zero also identifies topologies outside the portable capture/replay contract.
static inline uint32_t mvkPerVertexReplayVertexCount(VkPrimitiveTopology topology) {
	switch (topology) {
		case VK_PRIMITIVE_TOPOLOGY_POINT_LIST: return 1;
		case VK_PRIMITIVE_TOPOLOGY_LINE_LIST: case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP: return 2;
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP: case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN: return 3;
		default: return 0;
	}
}

static inline uint32_t mvkPerVertexPrimitiveCount(uint32_t vertexCount, VkPrimitiveTopology topology) {
	switch (topology) {
		case VK_PRIMITIVE_TOPOLOGY_POINT_LIST: return vertexCount;
		case VK_PRIMITIVE_TOPOLOGY_LINE_LIST: return vertexCount / 2;
		case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP: return vertexCount > 1 ? vertexCount - 1 : 0;
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: return vertexCount / 3;
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP: case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN: return vertexCount > 2 ? vertexCount - 2 : 0;
		default: return 0;
	}
}

// Each callback is a separate dispatch followed by a buffer barrier. No invocation scans a draw.
template<typename Dispatch>
static inline void mvkDispatchPerVertexRestart(uint32_t count, uint32_t instances, VkPrimitiveTopology topology, Dispatch&& dispatch) {
	dispatch(0, 0, 0, std::max(count, 1u));
	if (!count) { return; }
	uint32_t source = 0;
	for (uint64_t step = 1; step < count; step *= 2) {
		dispatch(1, uint32_t(step), source, count);
		source ^= 1;
	}
	dispatch(2, 0, source, count);
	uint64_t primitives = uint64_t(mvkPerVertexPrimitiveCount(count, topology)) * instances;
	if (primitives) { dispatch(3, 0, source, primitives); }
}

static inline uint32_t mvkPerVertexIndexSize(VkIndexType type) {
	switch (type) {
		case VK_INDEX_TYPE_UINT8: return 1;
		case VK_INDEX_TYPE_UINT16: return 2;
		case VK_INDEX_TYPE_UINT32: return 4;
		default: return 0;
	}
}

// Validate both the Vulkan binding and its underlying Metal allocation without overflowing.
static inline bool mvkPerVertexIndexRange(uint32_t count, uint32_t firstIndex, VkIndexType type, uint64_t bindingSize, uint64_t bindingOffset, uint64_t bufferSize) {
	uint32_t size = mvkPerVertexIndexSize(type);
	uint64_t start = uint64_t(firstIndex) * size, bytes = uint64_t(count) * size;
	return size && start <= bindingSize && bytes <= bindingSize - start && bindingOffset <= bufferSize && start <= bufferSize - bindingOffset && bytes <= bufferSize - bindingOffset - start;
}

// Caller checks counts and buffer bounds with mvkCanEncodePerVertexDraw before allocating.
// Records are dense (instance, input occurrence), including for indexed capture on the GPU.
// PerVertexKHR always uses three records; point/line raster replay uses only one/two vertices.
static inline void mvkPopulatePerVertexReplay(uint32_t vertexCount, uint32_t instanceCount, VkPrimitiveTopology topology, bool provokingLast, uint32_t* pairs, uint32_t* indices, uint32_t* corners) {
	uint32_t primitiveCount = mvkPerVertexPrimitiveCount(vertexCount, topology);
	uint32_t replayVertices = mvkPerVertexReplayVertexCount(topology);
	for (uint32_t instance = 0; instance < instanceCount; instance++) {
		for (uint32_t primitive = 0; primitive < primitiveCount; primitive++) {
			uint32_t key = instance * primitiveCount + primitive;
			uint32_t vertices[] = {primitive * 3, primitive * 3 + 1, primitive * 3 + 2};
			// Vulkan primsrast-barycentric-order-table and -last-vertex. MoltenVK
			// advertises triStripVertexOrderIndependentOfProvokingVertex = false.
			// These orders preserve winding and the replay primitive's provoking vertex.
			if (topology == VK_PRIMITIVE_TOPOLOGY_POINT_LIST) {
				vertices[0] = vertices[1] = vertices[2] = primitive;
			} else if (replayVertices == 2) {
				vertices[0] = topology == VK_PRIMITIVE_TOPOLOGY_LINE_LIST ? primitive * 2 : primitive;
				vertices[1] = vertices[2] = vertices[0] + 1;
			} else if (topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP) {
				vertices[0] = primitive; vertices[1] = primitive + 1; vertices[2] = primitive + 2;
				if (primitive & 1) { std::swap(vertices[provokingLast ? 0 : 1], vertices[provokingLast ? 1 : 2]); }
			} else if (topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
				vertices[0] = provokingLast ? 0 : primitive + 1;
				vertices[1] = provokingLast ? primitive + 1 : primitive + 2;
				vertices[2] = provokingLast ? primitive + 2 : 0;
			}
			for (uint32_t vertex = 0; vertex < 3; vertex++) {
				uint32_t record = instance * vertexCount + vertices[vertex];
				indices[3 * key + vertex] = record;
				if (vertex >= replayVertices) { continue; }
				uint32_t occurrence = key * replayVertices + vertex;
				pairs[2 * occurrence] = record;
				pairs[2 * occurrence + 1] = key;
				if (corners) { corners[occurrence] = vertex; }
			}
		}
	}
}

// Reserve whole locations: a private float3 must not share an application's Component lanes.
static inline uint32_t mvkAllocatePerVertexVaryingLocation(std::unordered_set<uint32_t>& locations, uint32_t maxLocations) {
	for (uint32_t location = 0; location < maxLocations; ++location) {
		if (locations.insert(location).second) { return location; }
	}
	return ~0u;
}
