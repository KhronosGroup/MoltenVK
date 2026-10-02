/* Copyright (c) 2026 Jean-Philippe Meunier. Licensed under the Apache License, Version 2.0. */
#pragma once
#include <spirv_msl.hpp>
#include <algorithm>
#include <cstdint>
#include <map>
#include <vector>

// PerVertexKHR leaves read the capture buffer; only ordinary active inputs need raster varyings.
template<typename Inputs>
static inline std::vector<uint32_t> mvkPerVertexReplayUserLocations(const Inputs& inputs) {
	std::vector<uint32_t> locations;
	for (const auto& input : inputs) { if (input.isUsed && !input.perVertex && input.builtin == spv::BuiltInMax) { locations.push_back(input.location); } }
	std::sort(locations.begin(), locations.end());
	locations.erase(std::unique(locations.begin(), locations.end()), locations.end());
	return locations;
}

// Component decorations can make Metal pad a location up to its highest occupied lane.
// Selection is by whole Location, exactly as in compile_captured_output_replay().
static inline uint64_t mvkPerVertexReplayVaryingComponents(const SPIRV_CROSS_NAMESPACE::MSLCapturedVertexLayout& layout, bool perspective, bool noPerspective, const std::vector<uint32_t>& userLocations) {
	std::map<uint32_t, uint32_t> widths;
	for (uint32_t location : userLocations) { widths.emplace(location, 0); }
	for (const auto& field : layout.components) {
		auto width = widths.find(field.location);
		if (width != widths.end()) { width->second = std::max(width->second, field.component + 1); }
	}
	uint64_t count = 1 + 3 * uint32_t(perspective) + 3 * uint32_t(noPerspective);
	for (const auto& width : widths) { count += width.second; }
	// Position has a dedicated rasterizer output. Conservatively charge other captured builtins.
	for (const auto& field : layout.builtins) { if (field.builtin != spv::BuiltInPosition) { ++count; } }
	return count;
}

// Retain the all-output budget for callers using the original replay overload.
static inline uint64_t mvkPerVertexReplayVaryingComponents(const SPIRV_CROSS_NAMESPACE::MSLCapturedVertexLayout& layout, bool perspective, bool noPerspective) {
	std::vector<uint32_t> locations;
	for (const auto& field : layout.components) { locations.push_back(field.location); }
	return mvkPerVertexReplayVaryingComponents(layout, perspective, noPerspective, locations);
}

static inline bool mvkPerVertexBufferIndexAvailable(uint32_t index, uint32_t descriptorCount, uint32_t bufferCount) { return index >= descriptorCount && index < bufferCount; }
