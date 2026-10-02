// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include "SPIRVToMSLConverter.h"
#include <cereal/archives/binary.hpp>
#include <cereal/types/map.hpp>
#include <cereal/types/string.hpp>
#include <cereal/types/vector.hpp>
#include "PipelineCacheSerializers.inc"
#include <iostream>
#include <sstream>
#include <stdexcept>

using namespace mvk;
using namespace SPIRV_CROSS_NAMESPACE;

static void check(bool condition, const char* message) {
	if (!condition) { throw std::runtime_error(message); }
}

static void checkLayout(const MSLCapturedVertexLayout& actual, const MSLCapturedVertexLayout& expected, const char* message) {
	check(actual.stride == expected.stride && actual.components.size() == expected.components.size() && actual.builtins.size() == expected.builtins.size(), message);
	for (size_t i = 0; i < expected.components.size(); i++) {
		const auto& a = actual.components[i];
		const auto& e = expected.components[i];
		check(a.location == e.location && a.component == e.component && a.byte_offset == e.byte_offset && a.scalar_type == e.scalar_type, message);
	}
	for (size_t i = 0; i < expected.builtins.size(); i++) {
		const auto& a = actual.builtins[i];
		const auto& e = expected.builtins[i];
		check(a.builtin == e.builtin && a.array_index == e.array_index && a.component == e.component && a.byte_offset == e.byte_offset && a.scalar_type == e.scalar_type, message);
	}
}

int main() {
	try {
		for (bool layered : {false, true}) {
		MSLCapturedVertexLayout layout;
		layout.stride = 36;
		layout.builtins.push_back({spv::BuiltInLayer, 0, 0, 32, SPIRType::UInt});
		for (uint32_t c = 0; c < 3; c++) { layout.components.push_back({2, c, 4 * c, SPIRType::Float}); }
		for (uint32_t c = 0; c < 4; c++) { layout.builtins.push_back({spv::BuiltInPosition, 0, c, 16 + 4 * c, SPIRType::Float}); }
		SPIRVToMSLConversionConfiguration cfg;
		cfg.options.entryPointName = "main";
		cfg.options.entryPointStage = spv::ExecutionModelFragment;
		cfg.options.mslOptions.set_msl_version(2, 4);
		cfg.options.mslOptions.multiview = true;
		cfg.options.mslOptions.multiview_layered_rendering = layered;
		auto otherMode = cfg;
		otherMode.options.mslOptions.multiview_layered_rendering = !layered;
		check(!cfg.matches(otherMode) && !otherMode.matches(cfg), "cfg layered mode aliases cache identity");
		cfg.setPerVertexInputBuffer(layout, {28, 29, 15});
		cfg.exportCapturedVertexLayout = true;
		SPIRVToMSLConversionResultInfo scr{};
		scr.entryPoint.mtlFunctionName = "cacheRoundTrip";
		scr.entryPoint.fpFastMathFlags = 17;
		scr.specializationMacros.emplace(7, MSLSpecializationMacroInfo{"testMacro", true, false});
		scr.needsPerVertexInputBuffer = true;
		scr.capturedVertexLayout = layout;
		std::stringstream bytes;
		{ cereal::BinaryOutputArchive output(bytes); output(cfg, scr); }
		SPIRVToMSLConversionConfiguration restoredCfg;
		SPIRVToMSLConversionResultInfo restoredScr{};
		{ cereal::BinaryInputArchive input(bytes); input(restoredCfg, restoredScr); }
		check(restoredCfg.perVertexInputBuffer.enabled, "cfg.perVertexInputBuffer lost");
		check(restoredCfg.exportCapturedVertexLayout, "cfg.exportCapturedVertexLayout lost");
		checkLayout(restoredCfg.perVertexInputBuffer.layout, layout, "cfg layout user/builtin fields lost");
		const auto& binding = restoredCfg.perVertexInputBuffer.binding;
		check(binding.vertex_buffer_index == 28 && binding.primitive_index_buffer_index == 29 && binding.primitive_index_location == 15, "cfg binding fields lost");
		check(cfg.matches(restoredCfg) && restoredCfg.matches(cfg), "cfg round-trip changed cache identity");
		check(restoredScr.needsPerVertexInputBuffer, "scr.needsPerVertexInputBuffer lost");
		checkLayout(restoredScr.capturedVertexLayout, layout, "scr.capturedVertexLayout user/builtin fields lost");
		check(restoredScr.entryPoint.mtlFunctionName == "cacheRoundTrip" && restoredScr.entryPoint.fpFastMathFlags == 17 && restoredScr.specializationMacros.at(7).name == "testMacro", "scr surrounding metadata lost");
		check(bytes.peek() == std::char_traits<char>::eof(), "Archive not fully consumed");
		std::cout << "PASS: actual MVKPipeline cfg/scr serializers preserve user fields, Position/Layer, multiview options, binding, used flag and cache identity (" << bytes.str().size() << " bytes)\n";
		}
		return 0;
	} catch (const std::exception& error) {
		std::cerr << "FAIL: " << error.what() << '\n';
		return 2;
	}
}
