/*
 * SPIRVSupport.cpp
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "SPIRVSupport.h"
#include "MVKStrings.h"
#include <spirv.hpp>
#include <ostream>
#include <sstream>

#import <CoreFoundation/CFByteOrder.h>

using namespace mvk;
using namespace std;

void mvk::spirvToBytes(const vector<uint32_t>& spv, vector<char>& bytes) {
	// Assumes desired endianness.
	size_t byteCnt = spv.size() * sizeof(uint32_t);
	char* cBytes = (char*)spv.data();
	bytes.clear();
	bytes.insert(bytes.end(), cBytes, cBytes + byteCnt);
}

void mvk::spirvToHeaderBytes(const vector<uint32_t>& spv, vector<char>& bytes, const string& varName) {
	bytes.clear();
	charvectorbuf cb(&bytes);
	ostream hdr(&cb);
	size_t spvCnt = spv.size();

	hdr << "// Automatically generated. Do not edit.\n\n";
	hdr << "#include <stdint.h>\n\n";
	hdr << "\tstatic const uint32_t " << cleanseVarName(varName) << '[' << spvCnt << "] = {";

	// Output the SPIR-V content, 8 elements per line
	if (spvCnt > 0) {
		hdr << "\n\t\t" << spv.front();
		for (size_t spvIdx = 1; spvIdx < spvCnt; spvIdx++) {
			hdr << (spvIdx % 8 ? ", " : ",\n\t\t") << spv[spvIdx];
		}
	}
	hdr << "\n\t};\n";
}

void mvk::bytesToSPIRV(const vector<char>& bytes, vector<uint32_t>& spv) {
	size_t spvCnt = bytes.size() / sizeof(uint32_t);
	uint32_t* cSPV = (uint32_t*)bytes.data();
	spv.clear();
	spv.insert(spv.end(), cSPV, cSPV + spvCnt);
	ensureSPIRVEndianness(spv);
}

bool mvk::ensureSPIRVEndianness(vector<uint32_t>& spv) {
	if (spv.empty()) { return false; }					// Nothing to convert

	uint32_t magNum = spv.front();
	if (magNum == spv::MagicNumber) { return false; }	// No need to convert

	if (CFSwapInt32(magNum) == spv::MagicNumber) {		// Yep, it's SPIR-V, but wrong endianness
		for (auto& elem : spv) { elem = CFSwapInt32(elem); }
		return true;
	}
	return false;		// Not SPIR-V, so don't convert
}

// Optionally exclude including SPIRV-Tools components.
#ifdef MVK_EXCLUDE_SPIRV_TOOLS

void mvk::logSPIRV(vector<uint32_t>& /*spirv*/, string& spvLog) {
	spvLog.append("\n");
	spvLog.append("Decompiled SPIR-V is unavailable. To log decompiled SPIR-V code,\n");
	spvLog.append("build MoltenVK without the MVK_EXCLUDE_SPIRV_TOOLS build setting.");
	spvLog.append("\n");
}

#else

#include <spirv-tools/libspirv.h>

void mvk::logSPIRV(vector<uint32_t>& spirv, string& spvLog) {
	if ( !((spirv.size() > 4) &&
		   (spirv[0] == spv::MagicNumber) &&
		   (spirv[4] == 0)) ) { return; }

	uint32_t options = (SPV_BINARY_TO_TEXT_OPTION_INDENT);
	spv_text text;
	spv_diagnostic diagnostic = nullptr;
	spv_context context = spvContextCreate(SPV_ENV_VULKAN_1_2);
	spv_result_t error = spvBinaryToText(context, spirv.data(), spirv.size(), options, &text, &diagnostic);
	spvContextDestroy(context);
	if (diagnostic) {
		// Cribbed from spvDiagnosticPrint()
		stringstream diagMsgOut;
		diagMsgOut << "\nSPIR-V error (" << error << ") at ";
		if (diagnostic->isTextSource) {
			diagMsgOut << "line: " << diagnostic->position.line + 1 << " col: " << diagnostic->position.column + 1 << ": ";
		} else {
			diagMsgOut << "index: "  << diagnostic->position.index << ": ";
		}
		diagMsgOut << diagnostic->error << "\n";
		spvLog.append(diagMsgOut.str());
		spvDiagnosticDestroy(diagnostic);
	} else {
		spvLog.append(text->str, text->length);
		spvTextDestroy(text);
	}
}

#endif
