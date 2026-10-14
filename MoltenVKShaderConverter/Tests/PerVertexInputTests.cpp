// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include "SPIRVToMSLConverter.h"
#include <cereal/archives/binary.hpp>
#include <cereal/types/vector.hpp>
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <stdexcept>

using namespace mvk;
using namespace SPIRV_CROSS_NAMESPACE;

static void check(bool value, const char* message) {
	if (!value) { throw std::runtime_error(message); }
}

static std::vector<uint32_t> readSPIRV(const char* path) {
	std::ifstream file(path, std::ios::binary | std::ios::ate);
	check(bool(file), "Cannot open fixture");
	auto size = file.tellg();
	check(size > 0 && size % 4 == 0, "Invalid fixture size");
	std::vector<uint32_t> words(size_t(size) / 4);
	file.seekg(0);
	file.read(reinterpret_cast<char*>(words.data()), size);
	check(bool(file), "Cannot read fixture");
	return words;
}

static SPIRVToMSLConversionConfiguration configuration() {
	SPIRVToMSLConversionConfiguration config;
	config.options.entryPointName = "main";
	config.options.entryPointStage = spv::ExecutionModelFragment;
	config.options.mslOptions.set_msl_version(2, 4);
	MSLCapturedVertexLayout layout;
	layout.stride = 96;
	auto add = [&](uint32_t location, uint32_t component, uint32_t offset, SPIRType::BaseType type) { layout.components.push_back({location, component, offset, type}); };
	add(0, 0, 16, SPIRType::Float);
	add(0, 1, 24, SPIRType::Float);
	add(0, 2, 20, SPIRType::Float);
	add(1, 2, 0, SPIRType::Float);
	add(1, 3, 4, SPIRType::Float);
	for (uint32_t c = 0; c < 4; c++) { add(2, c, 32 + 4 * c, SPIRType::Int); }
	for (uint32_t c = 0; c < 3; c++) { add(3, c, 48 + 4 * c, SPIRType::UInt); }
	for (uint32_t c = 0; c < 2; c++) { add(4, c, 8 + 2 * c, SPIRType::Half); }
	for (uint32_t c = 0; c < 3; c++) { add(5, c, 64 + 2 * c, SPIRType::Short); }
	for (uint32_t c = 0; c < 4; c++) { add(6, c, 72 + 2 * c, SPIRType::UShort); }
	add(7, 3, 80, SPIRType::Float);
	config.setPerVertexInputBuffer(layout, {28, 29, 15});
	mvk::MSLResourceBinding resource;
	resource.resourceBinding.stage = spv::ExecutionModelFragment;
	resource.resourceBinding.desc_set = 0;
	resource.resourceBinding.binding = 0;
	resource.resourceBinding.msl_buffer = 5;
	config.resourceBindings.push_back(resource);
	return config;
}

static std::string archive(MSLPerVertexInputBuffer input) {
	std::ostringstream bytes;
	cereal::BinaryOutputArchive output(bytes);
	output(input);
	return bytes.str();
}

static void checkCaptureLayout(SPIRVToMSLConverter& converter, SPIRVToMSLConversionResult& result, const std::string& directory) {
	auto equal = [](const MSLCapturedVertexLayout& a, const MSLCapturedVertexLayout& b) {
		return MSLPerVertexInputBuffer{true, a, {}}.matches(MSLPerVertexInputBuffer{true, b, {}});
	};
	for (bool complex : {false, true}) {
		for (bool alternate : {false, true}) {
			auto words = readSPIRV((directory + (complex ? "/capture-complex.spv" : "/capture-simple.spv")).c_str());
			SPIRVToMSLConversionConfiguration config;
			config.options.entryPointName = "main";
			config.options.entryPointStage = spv::ExecutionModelVertex;
			config.options.mslOptions.set_msl_version(2, 4);
			config.options.mslOptions.capture_output_to_buffer = true;
			config.exportCapturedVertexLayout = true;
			config.options.mslOptions.vertex_for_tessellation = !complex && alternate;
			config.options.mslOptions.force_native_arrays = complex && alternate;
			if (complex) {
				mvk::MSLShaderInterfaceVariable output;
				output.shaderVar.builtin = spv::BuiltInPosition;
				output.shaderVar.location = 1;
				config.shaderOutputs.push_back(output);
			}
			CompilerMSL reference(words);
			reference.set_msl_options(config.options.mslOptions);
			for (const auto& output : config.shaderOutputs) { reference.add_msl_shader_output(output.shaderVar); }
			reference.compile();
			auto expected = reference.get_msl_captured_vertex_layout();
			converter.setSPIRV(words.data(), words.size());
			check(converter.convert(config, result), "Capture conversion failed");
			auto layout = result.resultInfo.capturedVertexLayout;
			check(result.resultInfo.needsOutputBuffer && equal(layout, expected), "Exported layout differs from compiler reflection");
			check(layout.stride == (complex ? 112u : 32u) && layout.components.size() == (complex ? 13u : 3u), "Wrong physical ABI or builtin/padding lane leaked");
			check(layout.builtins.size() == (complex ? 9u : 4u), "Missing captured builtin scalars");
			std::stringstream bytes;
			{ cereal::BinaryOutputArchive output(bytes); output(layout); }
			MSLCapturedVertexLayout restored;
			{ cereal::BinaryInputArchive input(bytes); input(restored); }
			check(equal(restored, layout), "Captured result layout lost fields in round-trip");
			for (unsigned field = 0; field < 12; field++) {
				auto changed = restored;
				switch (field) {
					case 0: changed.stride += 4; break;
					case 1: changed.components[0].location++; break;
					case 2: changed.components[0].component++; break;
					case 3: changed.components[0].byte_offset += 4; break;
					case 4: changed.components[0].scalar_type = SPIRType::Int; break;
					case 5: changed.components.pop_back(); break;
					case 6: changed.builtins[0].builtin = spv::BuiltInPointSize; break;
					case 7: changed.builtins[0].array_index++; break;
					case 8: changed.builtins[0].component++; break;
					case 9: changed.builtins[0].byte_offset += 4; break;
					case 10: changed.builtins[0].scalar_type = SPIRType::Int; break;
					case 11: changed.builtins.pop_back(); break;
				}
				check(!equal(changed, layout), "Layout equality ignored a physical ABI field");
				check(archive(MSLPerVertexInputBuffer{true, changed, {}}) != archive(MSLPerVertexInputBuffer{true, layout, {}}), "Layout serialization ignored a physical ABI field");
			}
			std::ofstream output(directory + "/capture-" + (complex ? "complex" : "simple") + (alternate ? "-alternate" : "") + ".metal");
			output << result.msl << "\nstatic_assert(sizeof(main0_out) == " << layout.stride << ", \"captured stride\");\n";
			check(bool(output), "Cannot write capture MSL");
			if (!complex) {
				auto consumer = readSPIRV((directory + "/capture-consumer.spv").c_str());
				converter.setSPIRV(consumer.data(), consumer.size());
				SPIRVToMSLConversionConfiguration fragment;
				fragment.options.entryPointName = "main";
				fragment.options.entryPointStage = spv::ExecutionModelFragment;
				fragment.options.mslOptions.set_msl_version(2, 4);
				fragment.setPerVertexInputBuffer(restored, {28, 29, 15});
				check(converter.convert(fragment, result), "Restored producer layout rejected by fragment consumer");
				check(result.resultInfo.needsPerVertexInputBuffer, "Fragment did not use restored producer layout");
				check(equal(result.resultInfo.capturedVertexLayout, {}), "Fragment retained stale producer layout");
				std::ofstream fragmentOutput(directory + (alternate ? "/capture-consumer-alternate.metal" : "/capture-consumer.metal"));
				fragmentOutput << result.msl;
				check(bool(fragmentOutput), "Cannot write consumer MSL");
			}
			converter.setSPIRV(words.data(), words.size());
			config.options.mslOptions.capture_output_to_buffer = false;
			config.exportCapturedVertexLayout = false;
			config.options.mslOptions.vertex_for_tessellation = false;
			result.resultInfo.capturedVertexLayout = restored;
			check(converter.convert(config, result), "Ordinary vertex conversion failed");
			check(equal(result.resultInfo.capturedVertexLayout, {}), "Ordinary conversion retained stale producer layout");
		}
	}
	// Ordinary tessellation also captures vertex output, but must not request the portable physical ABI.
	{
		auto words = readSPIRV((directory + "/capture-complex.spv").c_str());
		converter.setSPIRV(words.data(), words.size());
		SPIRVToMSLConversionConfiguration ordinary;
		ordinary.options.entryPointName = "main";
		ordinary.options.entryPointStage = spv::ExecutionModelVertex;
		ordinary.options.mslOptions.set_msl_version(2, 4);
		ordinary.options.mslOptions.capture_output_to_buffer = true;
		ordinary.options.mslOptions.vertex_for_tessellation = true;
		check(converter.convert(ordinary, result), "Ordinary tessellation capture rejected by portable layout export");
		check(result.resultInfo.capturedVertexLayout.stride == 0, "Ordinary tessellation unexpectedly exported a portable layout");
	}
	// TES compute capture exports the same physical layout contract as vertex capture.
	for (const char* fixture : {"capture-tese", "capture-tese-block"}) {
		auto words = readSPIRV((directory + "/" + fixture + ".spv").c_str());
		SPIRVToMSLConversionConfiguration tess;
		tess.options.entryPointName = "main";
		tess.options.entryPointStage = spv::ExecutionModelTessellationEvaluation;
		tess.options.numTessControlPoints = 3;
		tess.options.shouldFlipVertexY = false;
		tess.options.mslOptions.set_msl_version(2, 4);
		tess.options.mslOptions.capture_output_to_buffer = true;
		tess.options.mslOptions.raw_buffer_tese_input = true;
		tess.options.mslOptions.tese_as_compute = true;
		tess.exportCapturedVertexLayout = true;
		CompilerMSL reference(words);
		reference.set_execution_mode(spv::ExecutionModeOutputVertices, 3);
		reference.set_msl_options(tess.options.mslOptions);
		reference.compile();
		auto expected = reference.get_msl_captured_vertex_layout();
		converter.setSPIRV(words.data(), words.size());
		check(converter.convert(tess, result), "TES capture conversion failed");
		check(result.resultInfo.needsOutputBuffer && equal(result.resultInfo.capturedVertexLayout, expected), "TES converter did not export the captured physical layout");
		std::ofstream output(directory + "/" + fixture + ".metal");
		output << result.msl;
		check(bool(output), "Cannot write TES capture MSL");
	}
	auto unsupported = readSPIRV((directory + "/capture-unsupported.spv").c_str());
	converter.setSPIRV(unsupported.data(), unsupported.size());
	SPIRVToMSLConversionConfiguration config;
	config.options.mslOptions.set_msl_version(2, 4);
	config.options.mslOptions.capture_output_to_buffer = true;
	config.exportCapturedVertexLayout = true;
	// Leave entryPointStage unspecified to exercise execution-model inference from SPIR-V.
	result.resultInfo.capturedVertexLayout.stride = 123;
	result.resultInfo.capturedVertexLayout.components.push_back({0, 0, 0, SPIRType::Float});
	result.resultInfo.capturedVertexLayout.builtins.push_back({spv::BuiltInPosition, 0, 0, 16, SPIRType::Float});
	result.resultLog.clear();
	check(!converter.convert(config, result), "Unsupported capture layout returned success");
	check(result.resultLog.find("16/32-bit") != std::string::npos, result.resultLog.c_str());
	check(result.msl.empty() && equal(result.resultInfo.capturedVertexLayout, {}), "Failed export retained partial or stale output");
	std::cout << "PASS: 4 producer exports match compiler reflection and round-trip, 48 equality/serialization mutations including builtins, 2 restored-layout consumers, inactive/failed result reset\n";
}

int main(int argc, char** argv) {
	try {
		check(argc == 4, "Usage: test typed-pervertex.spv ordinary.spv output-directory");
		auto original = configuration();
		check(!SPIRVToMSLConversionConfiguration{}.perVertexInputBuffer.enabled, "Portable input must default off");
		check(!SPIRVToMSLConversionResultInfo{}.needsPerVertexInputBuffer, "Used flag must default off");
		std::vector<std::function<void(MSLPerVertexInputBuffer&)>> changes = {
			[](auto& value) { value.enabled = false; },
			[](auto& value) { value.layout.stride += 4; },
			[](auto& value) { value.layout.components[0].location++; },
			[](auto& value) { value.layout.components[0].component++; },
			[](auto& value) { value.layout.components[0].byte_offset += 4; },
			[](auto& value) { value.layout.components[0].scalar_type = SPIRType::Int; },
			[](auto& value) { value.layout.components.pop_back(); },
			[](auto& value) { value.binding.vertex_buffer_index--; },
			[](auto& value) { value.binding.primitive_index_buffer_index--; },
			[](auto& value) { value.binding.primitive_index_location++; },
			[](auto& value) { value.binding.primitive_id_buffer_index = 27; }
		};
		for (auto& change : changes) {
			auto changed = original;
			change(changed.perVertexInputBuffer);
			check(!original.matches(changed) && !changed.matches(original), "ABI change lost in cache matching");
			check(archive(original.perVertexInputBuffer) != archive(changed.perVertexInputBuffer), "ABI change lost in serialization");
			std::istringstream bytes(archive(changed.perVertexInputBuffer));
			cereal::BinaryInputArchive input(bytes);
			MSLPerVertexInputBuffer restored;
			input(restored);
			check(archive(restored) == archive(changed.perVertexInputBuffer), "ABI round-trip lost a field");
		}
		auto config = original;
		check(config.matches(original), "Copy should match");
		config.alignWith(original);
		check(config.matches(original), "Alignment changed the input ABI");
		SPIRVToMSLConverter converter;
		auto words = readSPIRV(argv[1]);
		converter.setSPIRV(words.data(), words.size());
		SPIRVToMSLConversionResult result;
		for (bool arguments : {false, true}) {
			for (bool arrays : {false, true}) {
				config = original;
				config.options.mslOptions.argument_buffers = arguments;
				config.options.mslOptions.force_native_arrays = arrays;
				check(converter.convert(config, result), result.resultLog.c_str());
				check(result.resultInfo.needsPerVertexInputBuffer, "Active shader lost used flag");
				check(result.msl.find("* 96ul + 24ul") != std::string::npos, "Explicit physical ABI lost");
				check(result.msl.find("[[buffer(28)]]") != std::string::npos && result.msl.find("[[buffer(29)]]") != std::string::npos, "Explicit buffer indices lost");
				check(result.msl.find("user(locn15)") != std::string::npos, "Private location lost");
				check(result.msl.find("vertex_value") == std::string::npos && result.msl.find("[[primitive_id]]") == std::string::npos, "Portable output uses native path");
				std::ofstream file(std::string(argv[3]) + "/" + (arguments ? "arguments" : "classic") + (arrays ? "-arrays" : "") + ".metal");
				file << result.msl;
				check(bool(file), "Cannot write MSL");
			}
		}
		auto rejects = [&](const std::function<void(SPIRVToMSLConversionConfiguration&)>& change, const char* diagnostic) {
			config = original;
			change(config);
			result.resultInfo.needsPerVertexInputBuffer = true;
			result.msl = "stale shader";
			result.resultLog.clear();
			check(!converter.convert(config, result), "Rejected configuration returned success");
			check(!result.resultInfo.needsPerVertexInputBuffer && result.msl.empty(), "Failed conversion retained successful result");
			check(result.resultLog.find(diagnostic) != std::string::npos, result.resultLog.c_str());
		};
		rejects([](auto& c) { c.perVertexInputBuffer.enabled = false; }, "PerVertexKHR");
		rejects([](auto& c) { c.options.mslOptions.set_msl_version(2, 3); }, "MSL 2.4");
		rejects([](auto& c) { c.options.mslOptions.supports_per_vertex_fragment_input = true; }, "mutually exclusive");
		rejects([](auto& c) { c.perVertexInputBuffer.layout.stride = 0; }, "nonzero producer stride");
		rejects([](auto& c) { c.perVertexInputBuffer.binding.vertex_buffer_index = 5; }, "collides");
		rejects([](auto& c) { c.perVertexInputBuffer.layout.components[0].scalar_type = SPIRType::Int; }, "type mismatch");
		words = readSPIRV(argv[2]);
		converter.setSPIRV(words.data(), words.size());
		config = original;
		result.resultInfo.needsPerVertexInputBuffer = true;
		check(converter.convert(config, result), result.resultLog.c_str());
		check(!result.resultInfo.needsPerVertexInputBuffer, "Inactive shader retained used flag");
		auto ordinaryMSL = result.msl;
		config.perVertexInputBuffer.enabled = false;
		check(converter.convert(config, result), result.resultLog.c_str());
		check(result.msl == ordinaryMSL, "Inactive portable input changed ordinary shader");
		std::cout << "PASS: 11 cache identity/serialization mutations, 4 active variants, 6 rejections, inactive reuse and unchanged ordinary MSL\n";
		checkCaptureLayout(converter, result, argv[3]);
		return 0;
	} catch (const std::exception& error) {
		std::cerr << error.what() << '\n';
		return 1;
	}
}
