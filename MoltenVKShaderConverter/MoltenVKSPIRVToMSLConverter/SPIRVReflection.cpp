/*
 * SPIRVReflection.cpp
 *
 * Copyright (c) 2019 Chip Davis for Codeweavers
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

#include "SPIRVReflection.h"
#include "../SPIRV-Cross/spirv_parser.hpp"
#include "../SPIRV-Cross/spirv_reflect.hpp"

namespace mvk {

static const char missingPatchInputErr[] = "Neither tessellation shader specifies a patch input mode (Triangles, Quads, or Isolines).";
static const char missingWindingErr[] = "Neither tessellation shader specifies a winding order mode (VertexOrderCw or VertexOrderCcw).";
static const char missingPartitionErr[] = "Neither tessellation shader specifies a partition mode (SpacingEqual, SpacingFractionalOdd, or SpacingFractionalEven).";
static const char missingOutputVerticesErr[] = "Neither tessellation shader specifies the number of output control points.";

/** Given a tessellation control shader and a tessellation evaluation shader, both in SPIR-V format, returns tessellation reflection data. */
bool getTessReflectionData(const std::vector<uint32_t>& tesc, const std::string& tescEntryName, const std::vector<uint32_t>& tese, const std::string& teseEntryName, SPIRVTessReflectionData& reflectData, std::string& errorLog) {
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	try {
#endif
		SPIRV_CROSS_NAMESPACE::CompilerReflection tescReflect(tesc);
		SPIRV_CROSS_NAMESPACE::CompilerReflection teseReflect(tese);

		if (!tescEntryName.empty()) {
			tescReflect.set_entry_point(tescEntryName, spv::ExecutionModelTessellationControl);
		}
		if (!teseEntryName.empty()) {
			teseReflect.set_entry_point(teseEntryName, spv::ExecutionModelTessellationEvaluation);
		}

		tescReflect.compile();
		teseReflect.compile();

		const SPIRV_CROSS_NAMESPACE::Bitset& tescModes = tescReflect.get_execution_mode_bitset();
		const SPIRV_CROSS_NAMESPACE::Bitset& teseModes = teseReflect.get_execution_mode_bitset();

		// Extract the parameters from the shaders.
		if (tescModes.get(spv::ExecutionModeTriangles)) {
			reflectData.patchKind = spv::ExecutionModeTriangles;
		} else if (tescModes.get(spv::ExecutionModeQuads)) {
			reflectData.patchKind = spv::ExecutionModeQuads;
		} else if (tescModes.get(spv::ExecutionModeIsolines)) {
			reflectData.patchKind = spv::ExecutionModeIsolines;
		} else if (teseModes.get(spv::ExecutionModeTriangles)) {
			reflectData.patchKind = spv::ExecutionModeTriangles;
		} else if (teseModes.get(spv::ExecutionModeQuads)) {
			reflectData.patchKind = spv::ExecutionModeQuads;
		} else if (teseModes.get(spv::ExecutionModeIsolines)) {
			reflectData.patchKind = spv::ExecutionModeIsolines;
		} else {
			errorLog = missingPatchInputErr;
			return false;
		}

		if (tescModes.get(spv::ExecutionModeVertexOrderCw)) {
			reflectData.windingOrder = spv::ExecutionModeVertexOrderCw;
		} else if (tescModes.get(spv::ExecutionModeVertexOrderCcw)) {
			reflectData.windingOrder = spv::ExecutionModeVertexOrderCcw;
		} else if (teseModes.get(spv::ExecutionModeVertexOrderCw)) {
			reflectData.windingOrder = spv::ExecutionModeVertexOrderCw;
		} else if (teseModes.get(spv::ExecutionModeVertexOrderCcw)) {
			reflectData.windingOrder = spv::ExecutionModeVertexOrderCcw;
		} else {
			errorLog = missingWindingErr;
			return false;
		}

		reflectData.pointMode = tescModes.get(spv::ExecutionModePointMode) || teseModes.get(spv::ExecutionModePointMode);

		if (tescModes.get(spv::ExecutionModeSpacingEqual)) {
			reflectData.partitionMode = spv::ExecutionModeSpacingEqual;
		} else if (tescModes.get(spv::ExecutionModeSpacingFractionalEven)) {
			reflectData.partitionMode = spv::ExecutionModeSpacingFractionalEven;
		} else if (tescModes.get(spv::ExecutionModeSpacingFractionalOdd)) {
			reflectData.partitionMode = spv::ExecutionModeSpacingFractionalOdd;
		} else if (teseModes.get(spv::ExecutionModeSpacingEqual)) {
			reflectData.partitionMode = spv::ExecutionModeSpacingEqual;
		} else if (teseModes.get(spv::ExecutionModeSpacingFractionalEven)) {
			reflectData.partitionMode = spv::ExecutionModeSpacingFractionalEven;
		} else if (teseModes.get(spv::ExecutionModeSpacingFractionalOdd)) {
			reflectData.partitionMode = spv::ExecutionModeSpacingFractionalOdd;
		} else {
			errorLog = missingPartitionErr;
			return false;
		}

		if (tescModes.get(spv::ExecutionModeOutputVertices)) {
			reflectData.numControlPoints = tescReflect.get_execution_mode_argument(spv::ExecutionModeOutputVertices);
		} else if (teseModes.get(spv::ExecutionModeOutputVertices)) {
			reflectData.numControlPoints = teseReflect.get_execution_mode_argument(spv::ExecutionModeOutputVertices);
		} else {
			errorLog = missingOutputVerticesErr;
			return false;
		}

		return true;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	} catch (SPIRV_CROSS_NAMESPACE::CompilerError& ex) {
		errorLog = ex.what();
		return false;
	}
#endif
}

/** Given a shader in SPIR-V format, returns output reflection data. */
bool getShaderOutputs(const std::vector<uint32_t>& spirv, spv::ExecutionModel model, const std::string& entryName, std::vector<SPIRVShaderOutput>& outputs, std::string& errorLog) {
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	try {
#endif
		SPIRV_CROSS_NAMESPACE::Parser parser(spirv);
		parser.parse();
		SPIRV_CROSS_NAMESPACE::CompilerReflection reflect(parser.get_parsed_ir());
		if (!entryName.empty()) {
			reflect.set_entry_point(entryName, model);
		}
		reflect.compile();

		outputs.clear();

		auto addSat = [](uint32_t a, uint32_t b) { return a == uint32_t(-1) ? a : a + b; };
		parser.get_parsed_ir().for_each_typed_id<SPIRV_CROSS_NAMESPACE::SPIRVariable>([&reflect, &outputs, model, addSat](uint32_t varID, const SPIRV_CROSS_NAMESPACE::SPIRVariable& var) {
			if (var.storage != spv::StorageClassOutput) { return; }

			const auto* type = &reflect.get_type(reflect.get_type_from_variable(varID).parent_type);
			bool patch = reflect.has_decoration(varID, spv::DecorationPatch);
			auto biType = spv::BuiltInMax;
			if (reflect.has_decoration(varID, spv::DecorationBuiltIn)) {
				biType = (spv::BuiltIn)reflect.get_decoration(varID, spv::DecorationBuiltIn);
			}
			uint32_t loc = -1;
			if (reflect.has_decoration(varID, spv::DecorationLocation)) {
				loc = reflect.get_decoration(varID, spv::DecorationLocation);
			}
			if (model == spv::ExecutionModelTessellationControl && !patch)
				type = &reflect.get_type(type->parent_type);

			if (type->basetype == SPIRV_CROSS_NAMESPACE::SPIRType::Struct) {
				for (uint32_t i = 0; i < type->member_types.size(); i++) {
					// Each member may have a location decoration. If not, each member
					// gets an incrementing location.
					uint32_t memberLoc = addSat(loc, i);
					if (reflect.has_member_decoration(type->self, i, spv::DecorationLocation)) {
						memberLoc = reflect.get_member_decoration(type->self, i, spv::DecorationLocation);
					}
					patch = reflect.has_member_decoration(type->self, i, spv::DecorationPatch);
					if (reflect.has_member_decoration(type->self, i, spv::DecorationBuiltIn)) {
						biType = (spv::BuiltIn)reflect.get_member_decoration(type->self, i, spv::DecorationBuiltIn);
					}
					const SPIRV_CROSS_NAMESPACE::SPIRType& memberType = reflect.get_type(type->member_types[i]);
					if (memberType.columns > 1) {
						for (uint32_t i = 0; i < memberType.columns; i++) {
							outputs.push_back({memberType.basetype, memberType.vecsize, addSat(memberLoc, i), patch, biType});
						}
					} else if (!memberType.array.empty()) {
						for (uint32_t i = 0; i < memberType.array[0]; i++) {
							outputs.push_back({memberType.basetype, memberType.vecsize, addSat(memberLoc, i), patch, biType});
						}
					} else {
						outputs.push_back({memberType.basetype, memberType.vecsize, memberLoc, patch, biType});
					}
				}
			} else if (type->columns > 1) {
				for (uint32_t i = 0; i < type->columns; i++) {
					outputs.push_back({type->basetype, type->vecsize, addSat(loc, i), patch, biType});
				}
			} else if (!type->array.empty()) {
				for (uint32_t i = 0; i < type->array[0]; i++) {
					outputs.push_back({type->basetype, type->vecsize, addSat(loc, i), patch, biType});
				}
			} else {
				outputs.push_back({type->basetype, type->vecsize, loc, patch, biType});
			}
		});
		// Sort outputs by ascending location.
		std::stable_sort(outputs.begin(), outputs.end(), [](const SPIRVShaderOutput& a, const SPIRVShaderOutput& b) {
			return a.location < b.location;
		});
		// Assign locations to outputs that don't have one.
		uint32_t loc = -1;
		for (SPIRVShaderOutput& out : outputs) {
			if (out.location == uint32_t(-1)) { out.location = loc + 1; }
			loc = out.location;
		}
		return true;
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	} catch (SPIRV_CROSS_NAMESPACE::CompilerError& ex) {
		errorLog = ex.what();
		return false;
	}
#endif
}

}
