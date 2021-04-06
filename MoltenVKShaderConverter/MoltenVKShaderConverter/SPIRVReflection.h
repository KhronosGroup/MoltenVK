/*
 * SPIRVReflection.h
 *
 * Copyright (c) 2019-2021 Chip Davis for Codeweavers
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

#ifndef __SPIRVReflection_h_
#define __SPIRVReflection_h_ 1

#include <spirv.hpp>
#include <spirv_common.hpp>
#include <spirv_parser.hpp>
#include <spirv_reflect.hpp>
#include <string>
#include <vector>

namespace mvk {

#pragma mark -
#pragma mark SPIRVTessReflectionData

	/** Reflection data for a pair of tessellation shaders. This contains the information needed to construct a tessellation pipeline. */
	struct SPIRVTessReflectionData {
		/** The partition mode, one of SpacingEqual, SpacingFractionalEven, or SpacingFractionalOdd. */
		spv::ExecutionMode partitionMode = spv::ExecutionModeMax;

		/** The winding order of generated triangles, one of VertexOrderCw or VertexOrderCcw. */
		spv::ExecutionMode windingOrder = spv::ExecutionModeMax;

		/** Whether or not tessellation should produce points instead of lines or triangles. */
		bool pointMode = false;

		/** The kind of patch expected as input, one of Triangles, Quads, or Isolines. */
		spv::ExecutionMode patchKind = spv::ExecutionModeMax;

		/** The number of control points output by the tessellation control shader. */
		uint32_t numControlPoints = 0;
	};

#pragma mark -
#pragma mark SPIRVShaderOutputData

	/** Reflection data on a single output of a shader. This contains the information needed to construct a stage-input descriptor for the next stage of a pipeline. */
	struct SPIRVShaderOutput {
		/** The type of the output. */
		SPIRV_CROSS_NAMESPACE::SPIRType::BaseType baseType;

		/** The vector size, if a vector. */
		uint32_t vecWidth;

		/** The location number of the output. */
		uint32_t location;

		/** If this is a builtin, the kind of builtin this is. */
		spv::BuiltIn builtin;

		/** Whether this is a per-patch or per-vertex output. Only meaningful for tessellation control shaders. */
		bool perPatch;

		/** Whether this output is actually used (populated) by the shader. */
		bool isUsed;
	};

#pragma mark -
#pragma mark Functions

	/** Given a tessellation control shader and a tessellation evaluation shader, both in SPIR-V format, returns tessellation reflection data. */
	template<typename Vs>
	static inline bool getTessReflectionData(const Vs& tesc, const std::string& tescEntryName,
											 const Vs& tese, const std::string& teseEntryName,
											 SPIRVTessReflectionData& reflectData, std::string& errorLog) {
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
				errorLog = "Neither tessellation shader specifies a patch input mode (Triangles, Quads, or Isolines).";
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
				errorLog = "Neither tessellation shader specifies a winding order mode (VertexOrderCw or VertexOrderCcw).";
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
				errorLog = "Neither tessellation shader specifies a partition mode (SpacingEqual, SpacingFractionalOdd, or SpacingFractionalEven).";
				return false;
			}

			if (tescModes.get(spv::ExecutionModeOutputVertices)) {
				reflectData.numControlPoints = tescReflect.get_execution_mode_argument(spv::ExecutionModeOutputVertices);
			} else if (teseModes.get(spv::ExecutionModeOutputVertices)) {
				reflectData.numControlPoints = teseReflect.get_execution_mode_argument(spv::ExecutionModeOutputVertices);
			} else {
				errorLog = "Neither tessellation shader specifies the number of output control points.";
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
	template<typename Vs, typename Vo>
	static inline bool getShaderOutputs(const Vs& spirv, spv::ExecutionModel model, const std::string& entryName,
										Vo& outputs, std::string& errorLog) {
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
			reflect.update_active_builtins();

			outputs.clear();

			auto addSat = [](uint32_t a, uint32_t b) { return a == uint32_t(-1) ? a : a + b; };
			for (auto varID : reflect.get_active_interface_variables()) {
				spv::StorageClass storage = reflect.get_storage_class(varID);
				if (storage != spv::StorageClassOutput) { continue; }

				bool isUsed = true;
				const auto* type = &reflect.get_type(reflect.get_type_from_variable(varID).parent_type);
				bool patch = reflect.has_decoration(varID, spv::DecorationPatch);
				auto biType = spv::BuiltInMax;
				if (reflect.has_decoration(varID, spv::DecorationBuiltIn)) {
					biType = (spv::BuiltIn)reflect.get_decoration(varID, spv::DecorationBuiltIn);
					isUsed = reflect.has_active_builtin(biType, storage);
				}
				uint32_t loc = -1;
				if (reflect.has_decoration(varID, spv::DecorationLocation)) {
					loc = reflect.get_decoration(varID, spv::DecorationLocation);
				}
				if (model == spv::ExecutionModelTessellationControl && !patch)
					type = &reflect.get_type(type->parent_type);

				if (type->basetype == SPIRV_CROSS_NAMESPACE::SPIRType::Struct) {
					for (uint32_t idx = 0; idx < type->member_types.size(); idx++) {
						// Each member may have a location decoration. If not, each member
						// gets an incrementing location.
						uint32_t memberLoc = addSat(loc, idx);
						if (reflect.has_member_decoration(type->self, idx, spv::DecorationLocation)) {
							memberLoc = reflect.get_member_decoration(type->self, idx, spv::DecorationLocation);
						}
						patch = patch || reflect.has_member_decoration(type->self, idx, spv::DecorationPatch);
						if (reflect.has_member_decoration(type->self, idx, spv::DecorationBuiltIn)) {
							biType = (spv::BuiltIn)reflect.get_member_decoration(type->self, idx, spv::DecorationBuiltIn);
							isUsed = reflect.has_active_builtin(biType, storage);
						}
						const SPIRV_CROSS_NAMESPACE::SPIRType& memberType = reflect.get_type(type->member_types[idx]);
						if (memberType.columns > 1) {
							for (uint32_t i = 0; i < memberType.columns; i++) {
								outputs.push_back({memberType.basetype, memberType.vecsize, addSat(memberLoc, i), biType, patch, isUsed});
							}
						} else if (!memberType.array.empty()) {
							for (uint32_t i = 0; i < memberType.array[0]; i++) {
								outputs.push_back({memberType.basetype, memberType.vecsize, addSat(memberLoc, i), biType, patch, isUsed});
							}
						} else {
							outputs.push_back({memberType.basetype, memberType.vecsize, memberLoc, biType, patch, isUsed});
						}
					}
				} else if (type->columns > 1) {
					for (uint32_t i = 0; i < type->columns; i++) {
						outputs.push_back({type->basetype, type->vecsize, addSat(loc, i), biType, patch, isUsed});
					}
				} else if (!type->array.empty()) {
					for (uint32_t i = 0; i < type->array[0]; i++) {
						outputs.push_back({type->basetype, type->vecsize, addSat(loc, i), biType, patch, isUsed});
					}
				} else {
					outputs.push_back({type->basetype, type->vecsize, loc, biType, patch, isUsed});
				}
			}
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
#endif
