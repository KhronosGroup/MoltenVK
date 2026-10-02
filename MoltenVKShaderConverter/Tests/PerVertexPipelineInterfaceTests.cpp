// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include "SPIRVReflection.h"
#include "SPIRVToMSLConverter.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <unordered_set>

using namespace mvk;
using namespace SPIRV_CROSS_NAMESPACE;

static void check(bool value, const char* message) {
	if (!value) { throw std::runtime_error(message); }
}

static std::vector<uint32_t> readSPIRV(const std::string& path) {
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

int main(int argc, char** argv) {
	try {
		check(argc == 2 || argc == 3, "Usage: pervertex-pipeline-interface-test fixture-directory [consumer.spv]");
		std::string consumerName = argc == 3 ? argv[2] : "interface.frag.spv";
		auto consumer = readSPIRV(std::string(argv[1]) + "/" + consumerName);
		std::vector<SPIRVShaderInterfaceVariable> inputs;
		inputs.reserve(128);
		std::string error;
		check(getShaderInputs(consumer, spv::ExecutionModelFragment, "main", inputs, error), error.c_str());
		check(inputs.size() == 17, "PerVertex vertex dimension consumed varying locations (expected 16 user leaves plus FragCoord)");
		check(std::count_if(inputs.begin(), inputs.end(), [](const auto& input) { return input.perVertex; }) == 15, "Missing captured block, matrix or inner-array leaves");
		auto producer = readSPIRV(std::string(argv[1]) + "/interface.vert.spv");
		std::vector<SPIRVShaderInterfaceVariable> outputs;
		outputs.reserve(128);
		check(getShaderOutputs(producer, spv::ExecutionModelVertex, "main", outputs, error), error.c_str());
		SPIRVToMSLConverter converter;
		SPIRVToMSLConversionConfiguration capture;
		capture.options.entryPointName = "main";
		capture.options.entryPointStage = spv::ExecutionModelVertex;
		capture.options.mslOptions.set_msl_version(2, 4);
		capture.options.mslOptions.capture_output_to_buffer = true;
		capture.exportCapturedVertexLayout = true;
		SPIRVToMSLConversionResult result;
		converter.setSPIRV(producer.data(), producer.size());
		check(converter.convert(capture, result), result.resultLog.c_str());
		auto layout = result.resultInfo.capturedVertexLayout;
		check(layout.stride != 0, "Producer capture layout missing");
		std::unordered_set<uint32_t> locations;
		for (const auto& output : outputs) { if (output.builtin == spv::BuiltInMax) { locations.insert(output.location); } }
		for (const auto& input : inputs) { if (input.builtin == spv::BuiltInMax) { locations.insert(input.location); } }
		for (const auto& component : layout.components) { locations.insert(component.location); }
		uint32_t key = 0;
		while (key < 16 && locations.count(key)) { key++; }
		check(key == 15, "Dense interface lost its only free private-key location");
		SPIRVToMSLConversionConfiguration fragment;
		fragment.options.entryPointName = "main";
		fragment.options.entryPointStage = spv::ExecutionModelFragment;
		fragment.options.mslOptions.set_msl_version(2, 4);
		fragment.setPerVertexInputBuffer(layout, {28, 29, key});
		// Populate the same producer remaps as addPrevStageOutputToShaderConversionConfig.
		for (const auto& output : outputs) {
			if (!output.isUsed) { continue; }
			mvk::MSLShaderInput input;
			input.shaderVar.location = output.location;
			input.shaderVar.component = output.component;
			input.shaderVar.builtin = output.builtin;
			input.shaderVar.vecsize = output.vecWidth;
			fragment.shaderInputs.push_back(input);
		}
		converter.setSPIRV(consumer.data(), consumer.size());
		auto oldRemaps = fragment;
		CompilerReflection reflect(consumer);
		reflect.set_entry_point("main", spv::ExecutionModelFragment);
		for (auto id : reflect.get_active_interface_variables()) {
			if (reflect.get_storage_class(id) != spv::StorageClassInput || !reflect.has_decoration(id, spv::DecorationPerVertexKHR)) { continue; }
			auto location = reflect.get_decoration(id, spv::DecorationLocation);
			auto component = reflect.get_decoration(id, spv::DecorationComponent);
			auto& remaps = oldRemaps.shaderInputs;
			remaps.erase(std::remove_if(remaps.begin(), remaps.end(), [&](const auto& input) { return input.shaderVar.builtin == spv::BuiltInMax && input.shaderVar.location == location && input.shaderVar.component == component; }), remaps.end());
		}
		check(!converter.convert(oldRemaps, result), "Old base-only remap removal unexpectedly succeeded");
		check(result.resultLog.find("remapping for captured inputs") != std::string::npos, result.resultLog.c_str());
		// Apply the pipeline's flattened leaf filtering, keeping ordinary shared-location components.
		for (const auto& leaf : inputs) {
			if (!leaf.perVertex) { continue; }
			auto& remaps = fragment.shaderInputs;
			remaps.erase(std::remove_if(remaps.begin(), remaps.end(), [&](const auto& input) { return input.shaderVar.builtin == spv::BuiltInMax && input.shaderVar.location == leaf.location && input.shaderVar.component == leaf.component; }), remaps.end());
		}
		check(std::count_if(fragment.shaderInputs.begin(), fragment.shaderInputs.end(), [](const auto& input) { return input.shaderVar.builtin == spv::BuiltInMax; }) == 1, "Captured remaps remain or ordinary component was removed");
		check(std::any_of(fragment.shaderInputs.begin(), fragment.shaderInputs.end(), [](const auto& input) { return input.shaderVar.location == 14 && input.shaderVar.component == 2; }), "Ordinary component remap lost");
		check(converter.convert(fragment, result), result.resultLog.c_str());
		check(result.resultInfo.needsPerVertexInputBuffer, "Linked consumer did not use capture buffers");
		check(result.msl.find("user(locn15)") != std::string::npos, "Private key missing from linked consumer");
		std::ofstream(std::string(argv[1]) + "/" + consumerName + ".metal") << result.msl;
		CompilerMSL replay(producer);
		auto options = replay.get_msl_options();
		options.set_msl_version(2, 4);
		replay.set_msl_options(options);
		std::string replayMSL = replay.compile_captured_output_replay(layout, {0, 1, 2, key});
		check(replayMSL.find("user(locn15)") != std::string::npos, "Replay key does not match fragment");
		std::ofstream(std::string(argv[1]) + "/interface.replay.metal") << replayMSL;
		std::cout << "PASS: linked capture/replay/consumer, block/matrix/nested-array locations, shared component, dense private key, old-remap rejection\n";
		return 0;
	} catch (const std::exception& error) {
		std::cerr << error.what() << '\n';
		return 1;
	}
}
