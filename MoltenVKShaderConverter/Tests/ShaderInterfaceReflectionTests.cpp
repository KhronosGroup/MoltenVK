// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include "SPIRVReflection.h"
#include "MVKSmallVector.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
using namespace mvk;
static void check(bool value, const char* message) { if (!value) { throw std::runtime_error(message); } }
static std::vector<uint32_t> readSPIRV(const std::string& path) {
	std::ifstream file(path, std::ios::binary | std::ios::ate);
	auto size = file.tellg();
	check(file && size > 0 && size % 4 == 0, "Invalid SPIR-V fixture");
	std::vector<uint32_t> words(size_t(size) / 4);
	file.seekg(0);
	file.read(reinterpret_cast<char*>(words.data()), size);
	check(bool(file), "Cannot read fixture");
	return words;
}
static void checkActivity(const std::string& directory) {
	struct Case { const char* entry; unsigned mask; };
	const Case cases[] = {{"perspective", 1}, {"linear", 2}, {"both", 3}, {"ordinary", 0}, {"unused", 0}, {"explicit_perspective", 1}, {"explicit_linear", 2}};
	unsigned failures = 0;
	for (const char* fixture : {"active-block", "root-alias"}) {
		auto words = readSPIRV(directory + "/" + fixture + ".spv");
		const auto original = words;
		for (const auto& c : cases) {
			std::vector<SPIRVShaderInterfaceVariable> inputs;
			inputs.reserve(128); // Isolate R2 from R4; alignment mode deliberately forces reallocations.
			std::string error;
			check(getShaderInputs(words, spv::ExecutionModelFragment, c.entry, inputs, error), error.c_str());
			check(words == original, "Reflection mutated the source module");
			unsigned mask = 0;
			for (const auto& input : inputs) {
				if (input.isUsed && input.builtin == spv::BuiltInBaryCoordKHR) { mask |= 1; }
				if (input.isUsed && input.builtin == spv::BuiltInBaryCoordNoPerspKHR) { mask |= 2; }
			}
			bool passed = mask == c.mask;
			failures += !passed;
			std::cout << (passed ? "PASS " : "FAIL ") << fixture << '/' << c.entry << ": mask=" << mask << " expected=" << c.mask << '\n';
		}
	}
	check(!failures, "Root pointer aliases lost active members or activated inactive members");
}
template<typename Variables>
static void checkAlignment(const std::vector<uint32_t>& words, bool output, unsigned head, Variables& vars) {
	std::string error;
	bool success = output ? getShaderOutputs(words, spv::ExecutionModelVertex, "main", vars, error) : getShaderInputs(words, spv::ExecutionModelFragment, "main", vars, error);
	check(success, error.c_str());
	check(vars.size() == 45 + head, "Wrong flattened array/struct size");
	for (size_t i = 0; i < vars.size(); ++i) {
		unsigned width = i < head ? 1 : i == 44 + head ? 4 : (i - head) % 22 == 0 ? 1 : (i - head) % 22 == 1 ? 4 : 2;
		unsigned alignment = i == 0 || i == head || i == head + 22 ? 16 : 0;
		check(vars[i].location == i && vars[i].component == 0 && vars[i].vecWidth == width && vars[i].isUsed, "Flattened leaf metadata changed");
		check(vars[i].firstStructMemberAlignment == alignment, "Parent/nested struct alignment lost across reallocation");
		check(getShaderInterfaceVariableAlignment(vars[i]) == (alignment ? alignment : 4 * width), "Incorrect effective member alignment");
	}
}
static void checkReallocation(const std::string& directory) {
	// Reproduce the review's unreserved three-member builtin block before larger nested interfaces.
	std::vector<SPIRVShaderInterfaceVariable> block;
	std::string error;
	check(getShaderInputs(readSPIRV(directory + "/active-block.spv"), spv::ExecutionModelFragment, "perspective", block, error), error.c_str());
	check(block.size() == 3 && block[0].firstStructMemberAlignment == 16, "Builtin block alignment lost");
	for (bool output : {false, true}) {
		for (unsigned head : {0u, 1u}) {
			auto words = readSPIRV(directory + "/alignment-" + std::to_string(head) + (output ? ".vert.spv" : ".frag.spv"));
			for (unsigned reserve : {0u, 1u, 128u}) {
				std::vector<SPIRVShaderInterfaceVariable> vars;
				vars.reserve(reserve);
				checkAlignment(words, output, head, vars);
				checkAlignment(words, output, head, vars); // Reused container must match the first reflection.
			}
			MVKSmallVector<SPIRVShaderInterfaceVariable, 32> vars;
			checkAlignment(words, output, head, vars); // Same inline capacity as production, then heap growth.
			checkAlignment(words, output, head, vars);
		}
	}
	std::cout << "PASS: unreserved builtin block; nested arrays, inputs/outputs, parent alignment, std::vector and MVKSmallVector growth/reuse\n";
}
int main(int argc, char** argv) {
	try {
		check(argc == 3, "Usage: reflection-tests fixture-directory activity|alignment");
		if (std::string(argv[2]) == "activity") { checkActivity(argv[1]); }
		else { check(std::string(argv[2]) == "alignment", "Unknown test mode"); checkReallocation(argv[1]); }
		return 0;
	} catch (const std::exception& error) { std::cerr << "FAIL: " << error.what() << '\n'; return 1; }
}
