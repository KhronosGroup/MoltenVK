/*
 * SPIRVReflection.h
 *
 * Copyright (c) 2019-2026 Chip Davis for Codeweavers
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
#include <spirv_msl.hpp>
#include <spirv_reflect.hpp>
#include <string>
#include <unordered_map>
#include <vector>


namespace mvk {

#pragma mark -
#pragma mark SPIRVTessReflectionData

	/**
	 * Reflection data for a pair of tessellation shaders.
	 * This contains the information needed to construct a tessellation pipeline.
	 */
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

		/** Whether both shaders can exchange float32 tessellation levels (SPIRV-Cross tessellation_factors_float32). */
		bool float32TessLevels = false;
	};

#pragma mark -
#pragma mark SPIRVShaderInterfaceVariable

	/**
	 * Reflection data on a single interface variable of a shader.
	 * This contains the information needed to construct a
	 * stage-input descriptor for the next stage of a pipeline.
	 */
	struct SPIRVShaderInterfaceVariable {
		/** The type of the variable. */
		SPIRV_CROSS_NAMESPACE::SPIRType::BaseType baseType;

		/** The vector size, if a vector. */
		uint32_t vecWidth;

		/** The location number of the variable. */
		uint32_t location;

		/** The component index of the variable. */
		uint32_t component;

		/**
		 * If this is the first member of a struct, this will contain the alignment
		 * of the struct containing this variable, otherwise this will be zero.
		 */
		uint32_t firstStructMemberAlignment;

		/** If this is a builtin, the kind of builtin this is. */
		spv::BuiltIn builtin;

		/** Whether this is a per-patch or per-vertex variable. Only meaningful for tessellation shaders. */
		bool perPatch;

		/** Whether this variable is actually used (read or written) by the shader. */
		bool isUsed;

		/** Whether this fragment input is read per vertex, including leaves of a PerVertexKHR block. */
		bool perVertex = false;
	};
	typedef SPIRVShaderInterfaceVariable SPIRVShaderOutput;


#pragma mark -
#pragma mark Functions

	/** Returns whether a type has a PerVertexKHR-decorated member, including nested structs and arrays. */
	static inline bool hasPerVertexInputMember(const SPIRV_CROSS_NAMESPACE::CompilerReflection& reflect, const SPIRV_CROSS_NAMESPACE::SPIRType& type) {
		for (uint32_t member = 0; member < type.member_types.size(); member++) {
			if (reflect.has_member_decoration(type.self, member, spv::DecorationPerVertexKHR) || hasPerVertexInputMember(reflect, reflect.get_type(type.member_types[member]))) { return true; }
		}
		return false;
	}

	/**
	 * Reports PerVertexKHR decorations on statically active fragment input variables or their members.
	 * Activity is per interface variable (including whole blocks), as in SPIRV-Cross reflection.
	 * An empty entryName selects the module's default entry point, which must be a fragment entry point.
	 * Returns success separately from usesPerVertexInput; on failure the latter is false and errorLog is set.
	 * Like the other reflection helpers, parser errors are recoverable when SPIRV-Cross exceptions are enabled.
	 */
	template<typename Vs>
	static inline bool getFragmentShaderUsesPerVertexInput(const Vs& spirv, const std::string& entryName, bool& usesPerVertexInput, std::string& errorLog) {
		usesPerVertexInput = false;
		errorLog.clear();
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
		try {
#endif
			SPIRV_CROSS_NAMESPACE::Parser parser(spirv);
			parser.parse();
			SPIRV_CROSS_NAMESPACE::CompilerReflection reflect(parser.get_parsed_ir());
			if (!entryName.empty()) {
				bool found = false;
				for (const auto& entry : reflect.get_entry_points_and_stages()) {
					if (entry.name == entryName && entry.execution_model == spv::ExecutionModelFragment) { found = true; break; }
				}
				if (!found) {
					errorLog = "Fragment entry point not found: " + entryName;
					return false;
				}
				reflect.set_entry_point(entryName, spv::ExecutionModelFragment);
			}
			if (reflect.get_execution_model() != spv::ExecutionModelFragment) {
				errorLog = "PerVertexKHR input reflection requires a fragment entry point.";
				return false;
			}
			for (auto varID : reflect.get_active_interface_variables()) {
				if (reflect.get_storage_class(varID) != spv::StorageClassInput) { continue; }
				if (reflect.has_decoration(varID, spv::DecorationPerVertexKHR) || hasPerVertexInputMember(reflect, reflect.get_type_from_variable(varID))) {
					usesPerVertexInput = true;
					break;
				}
			}
			return true;
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
		} catch (SPIRV_CROSS_NAMESPACE::CompilerError& ex) {
			errorLog = ex.what();
			return false;
		}
#endif
	}

	/**
	 * Returns the Locations of the fragment PerVertexKHR inputs that the corner copies of a mesh pipeline support:
	 * arrays of one to three 16- or 32-bit scalars or vectors below Location 32, outside blocks.
	 * Returns zero if any other form is read. Parser errors throw, as in the other mesh admission checks.
	 */
	template<typename Vs>
	static inline uint32_t getMeshPerVertexCornerLocations(const Vs& spirv, const std::string& entryName) {
		SPIRV_CROSS_NAMESPACE::CompilerReflection reflect(spirv);
		reflect.set_entry_point(entryName, spv::ExecutionModelFragment);
		uint32_t locations = 0;
		for (auto varID : reflect.get_active_interface_variables()) {
			if (reflect.get_storage_class(varID) != spv::StorageClassInput) { continue; }
			const auto& type = reflect.get_type(reflect.get_type_from_variable(varID).parent_type);
			if (!reflect.has_decoration(varID, spv::DecorationPerVertexKHR)) {
				if (hasPerVertexInputMember(reflect, type)) { return 0; }
				continue;
			}
			if (type.array.size() != 1 || !type.array_size_literal[0] || type.array[0] < 1 || type.array[0] > 3) { return 0; }
			const auto& element = reflect.get_type(type.parent_type);
			bool scalarOrVector = element.array.empty() && element.columns == 1 &&
				(element.basetype == SPIRV_CROSS_NAMESPACE::SPIRType::Float || element.basetype == SPIRV_CROSS_NAMESPACE::SPIRType::Half ||
				 element.basetype == SPIRV_CROSS_NAMESPACE::SPIRType::Int || element.basetype == SPIRV_CROSS_NAMESPACE::SPIRType::UInt ||
				 element.basetype == SPIRV_CROSS_NAMESPACE::SPIRType::Short || element.basetype == SPIRV_CROSS_NAMESPACE::SPIRType::UShort);
			uint32_t location = reflect.get_decoration(varID, spv::DecorationLocation);
			if (!scalarOrVector || reflect.has_decoration(varID, spv::DecorationBuiltIn) || !reflect.has_decoration(varID, spv::DecorationLocation) || location >= 32) { return 0; }
			locations |= 1u << location;
		}
		return locations;
	}

	/**
	 * Given a tessellation control shader and a tessellation evaluation shader,
	 * both in SPIR-V format, returns tessellation reflection data.
	 */
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

			// Same execution modes as the MSL conversion, which sets the patch kind and control points on both stages.
			SPIRV_CROSS_NAMESPACE::CompilerMSL tescMSL(tesc), teseMSL(tese);
			if (!tescEntryName.empty()) { tescMSL.set_entry_point(tescEntryName, spv::ExecutionModelTessellationControl); }
			if (!teseEntryName.empty()) { teseMSL.set_entry_point(teseEntryName, spv::ExecutionModelTessellationEvaluation); }
			for (auto* compiler : {&tescMSL, &teseMSL}) {
				compiler->set_execution_mode(reflectData.patchKind);
				compiler->set_execution_mode(spv::ExecutionModeOutputVertices, reflectData.numControlPoints);
			}
			reflectData.float32TessLevels = tescMSL.get_tessellation_factors_float32_incompatibility().empty() && teseMSL.get_tessellation_factors_float32_incompatibility().empty();

			return true;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
		} catch (SPIRV_CROSS_NAMESPACE::CompilerError& ex) {
			errorLog = ex.what();
			return false;
		}
#endif
	}

	/** Returns the size in bytes of the interface variable. */
	static inline uint32_t getShaderInterfaceVariableSize(const SPIRVShaderInterfaceVariable& var) {
		if ( !var.isUsed ) { return 0; }		// Unused variables consume no buffer space.

		uint32_t vecWidth = var.vecWidth;
		if (vecWidth == 3) { vecWidth = 4; }	// Metal 3-vectors consume same as 4-vectors.
		switch (var.baseType) {
			case SPIRV_CROSS_NAMESPACE::SPIRType::SByte:
			case SPIRV_CROSS_NAMESPACE::SPIRType::UByte:
				return 1 * vecWidth;
			case SPIRV_CROSS_NAMESPACE::SPIRType::Short:
			case SPIRV_CROSS_NAMESPACE::SPIRType::UShort:
			case SPIRV_CROSS_NAMESPACE::SPIRType::Half:
				return 2 * vecWidth;
			case SPIRV_CROSS_NAMESPACE::SPIRType::Int:
			case SPIRV_CROSS_NAMESPACE::SPIRType::UInt:
			case SPIRV_CROSS_NAMESPACE::SPIRType::Float:
			default:
				return 4 * vecWidth;
		}
	}
	static inline uint32_t getShaderOutputSize(const SPIRVShaderOutput& output) {
		return getShaderInterfaceVariableSize(output);
	}

	/**
	 * Returns the alignment of the shader interface variable, which typically matches the size of the variable,
	 * but the first member of a nested struct may inherit special alignment from the struct.
	 */
	static inline uint32_t getShaderInterfaceVariableAlignment(const SPIRVShaderInterfaceVariable& var) {
		if(var.firstStructMemberAlignment && var.isUsed) {
			return var.firstStructMemberAlignment;
		} else {
			return getShaderOutputSize(var);
		}
	}
	static inline uint32_t getShaderOutputAlignment(const SPIRVShaderOutput& output) {
		return getShaderInterfaceVariableAlignment(output);
	}

	auto addSat = [](uint32_t a, uint32_t b) { return a == uint32_t(-1) ? a : a + b; };

	template<typename Vi>
	static inline uint32_t getShaderInterfaceStructMembers(const SPIRV_CROSS_NAMESPACE::CompilerReflection& reflect,
														   Vi& vars, size_t parentFirstMember,
														   const SPIRV_CROSS_NAMESPACE::SPIRType* structType, spv::StorageClass storage,
														   bool patch, uint32_t loc, bool perVertex = false) {
		bool isUsed = true;
		auto biType = spv::BuiltInMax;
		const size_t firstMember = vars.size();
		size_t mbrCnt = structType->member_types.size();
		for (uint32_t mbrIdx = 0; mbrIdx < mbrCnt; mbrIdx++) {
			// Each member may have a location decoration. If not, each member
			// gets an incrementing location based on the base location for the struct.
			uint32_t cmp = 0;
			if (reflect.has_member_decoration(structType->self, mbrIdx, spv::DecorationLocation)) {
				loc = reflect.get_member_decoration(structType->self, mbrIdx, spv::DecorationLocation);
				cmp = reflect.get_member_decoration(structType->self, mbrIdx, spv::DecorationComponent);
			}
			patch = patch || reflect.has_member_decoration(structType->self, mbrIdx, spv::DecorationPatch);
			if (reflect.has_member_decoration(structType->self, mbrIdx, spv::DecorationBuiltIn)) {
				biType = (spv::BuiltIn)reflect.get_member_decoration(structType->self, mbrIdx, spv::DecorationBuiltIn);
				isUsed = reflect.has_active_builtin(biType, storage);
			}
			const SPIRV_CROSS_NAMESPACE::SPIRType* type = &reflect.get_type(structType->member_types[mbrIdx]);
			bool memberPerVertex = storage == spv::StorageClassInput && reflect.get_execution_model() == spv::ExecutionModelFragment && reflect.has_member_decoration(structType->self, mbrIdx, spv::DecorationPerVertexKHR);
			if (memberPerVertex && !type->array.empty()) { type = &reflect.get_type(type->parent_type); }
			uint32_t elemCnt = type->columns;
			for (uint32_t count : type->array) { elemCnt *= count; }
			for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
				if (type->basetype == SPIRV_CROSS_NAMESPACE::SPIRType::Struct)
					loc = getShaderInterfaceStructMembers(reflect, vars, firstMember, type, storage, patch, loc, perVertex || memberPerVertex);
				else {
					// The alignment of a structure is the same as the largest member of the structure.
					// Consequently, the first flattened member of a structure should align with structure itself.
					vars.push_back({type->basetype, type->vecsize, loc, cmp, 0, biType, patch, isUsed, perVertex || memberPerVertex});
					vars[firstMember].firstStructMemberAlignment = std::max(vars[firstMember].firstStructMemberAlignment, getShaderOutputSize(vars.back()));
					loc = addSat(loc, 1);
				}
			}
		}

		// Set the parent's first member alignment to the largest alignment found so far.
		// Indices remain valid when appending leaves reallocates the container.
		if (parentFirstMember < vars.size() && firstMember < vars.size()) {
			vars[parentFirstMember].firstStructMemberAlignment = std::max(vars[parentFirstMember].firstStructMemberAlignment, vars[firstMember].firstStructMemberAlignment);
		}

		return loc;
	}
	template<typename Vo>
	static inline uint32_t getShaderOutputStructMembers(const SPIRV_CROSS_NAMESPACE::CompilerReflection& reflect,
														Vo& outputs, size_t parentFirstMember,
														const SPIRV_CROSS_NAMESPACE::SPIRType* structType, spv::StorageClass storage,
														bool patch, uint32_t loc) {
		return getShaderInterfaceStructMembers(reflect, outputs, parentFirstMember, structType, storage, patch, loc);
	}

	/** Given a shader in SPIR-V format, returns interface reflection data. */
	template<typename Vs, typename Vi>
	static inline bool getShaderInterfaceVariables(const Vs& spirv, spv::StorageClass storage, spv::ExecutionModel model,
												   const std::string& entryName, Vi& vars, std::string& errorLog) {
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
		try {
#endif
			SPIRV_CROSS_NAMESPACE::Parser parser(spirv);
			parser.parse();
			if (model == spv::ExecutionModelFragment && storage == spv::StorageClassInput) {
				// Match the MSL backend's builtin analysis: access chains must see through
				// copied/aliased Input pointers before deciding which block members are active.
				// Only the parser's private IR is changed; entry-point reachability is retained.
				auto& ir = parser.get_parsed_ir();
				std::unordered_map<uint32_t, uint32_t> pointerAliases;
				ir.for_each_typed_id<SPIRV_CROSS_NAMESPACE::SPIRBlock>([&](uint32_t, SPIRV_CROSS_NAMESPACE::SPIRBlock& block) {
					for (auto& op : block.ops) {
						bool emptyAccessChain = (op.op == spv::OpAccessChain || op.op == spv::OpInBoundsAccessChain) && op.length == 3;
						if ((op.op != spv::OpCopyObject && !emptyAccessChain) || op.length < 3) { continue; }
						const auto* args = ir.spirv.data() + op.offset;
						const auto& type = SPIRV_CROSS_NAMESPACE::variant_get<SPIRV_CROSS_NAMESPACE::SPIRType>(ir.ids[args[0]]);
						if (type.pointer && type.storage == spv::StorageClassInput) {
							pointerAliases[args[1]] = args[2];
							// Empty access chains are identity copies, but ActiveBuiltinHandler
							// stops traversal on their three operands. A copy keeps it walking.
							op.op = spv::OpCopyObject;
						}
					}
				});
				ir.for_each_typed_id<SPIRV_CROSS_NAMESPACE::SPIRBlock>([&](uint32_t, const SPIRV_CROSS_NAMESPACE::SPIRBlock& block) {
					for (const auto& op : block.ops) {
						if ((op.op != spv::OpAccessChain && op.op != spv::OpInBoundsAccessChain) || op.length < 3) { continue; }
						auto* args = ir.spirv.data() + op.offset;
						for (size_t count = 0; pointerAliases.count(args[2]); ++count) {
							if (count == pointerAliases.size()) { using namespace SPIRV_CROSS_NAMESPACE; SPIRV_CROSS_THROW("Cyclic input pointer aliases."); }
							args[2] = pointerAliases.at(args[2]);
						}
					}
				});
			}
			SPIRV_CROSS_NAMESPACE::CompilerReflection reflect(parser.get_parsed_ir());
			if (!entryName.empty()) {
				reflect.set_entry_point(entryName, model);
			}
			reflect.compile();
			reflect.update_active_builtins();

			vars.clear();

			for (auto varID : reflect.get_active_interface_variables()) {
				if (storage != reflect.get_storage_class(varID)) { continue; }

				bool isUsed = true;
				const auto* type = &reflect.get_type(reflect.get_type_from_variable(varID).parent_type);
				bool patch = reflect.has_decoration(varID, spv::DecorationPatch);
				if (reflect.has_decoration(type->self, spv::DecorationBlock)) {
					// In this case, the Patch decoration is on the members.
					// FIXME It is theoretically possible for some members of a block to have
					// the decoration and some not. What then?
					patch = reflect.has_member_decoration(type->self, 0, spv::DecorationPatch);
				}
				auto biType = spv::BuiltInMax;
				if (reflect.has_decoration(varID, spv::DecorationBuiltIn)) {
					biType = (spv::BuiltIn)reflect.get_decoration(varID, spv::DecorationBuiltIn);
					isUsed = reflect.has_active_builtin(biType, storage);
					// The active interface includes whole-variable InterpolateAt* operands,
					// which update_active_builtins() does not count as loads.
					if (model == spv::ExecutionModelFragment && storage == spv::StorageClassInput && (biType == spv::BuiltInBaryCoordKHR || biType == spv::BuiltInBaryCoordNoPerspKHR)) { isUsed = true; }
				}
				uint32_t loc = -1;
				uint32_t cmp = 0;
				if (reflect.has_decoration(varID, spv::DecorationLocation)) {
					loc = reflect.get_decoration(varID, spv::DecorationLocation);
				}
				if (reflect.has_decoration(varID, spv::DecorationComponent)) {
					cmp = reflect.get_decoration(varID, spv::DecorationComponent);
				}
				// Mesh outputs are arrays over the emitted vertices or primitives, and the primitive index builtins
				// describe connectivity, not varyings.
				bool meshOutput = model == spv::ExecutionModelMeshEXT && storage == spv::StorageClassOutput;
				if (meshOutput && (biType == spv::BuiltInPrimitivePointIndicesEXT || biType == spv::BuiltInPrimitiveLineIndicesEXT || biType == spv::BuiltInPrimitiveTriangleIndicesEXT)) { continue; }
				// For tessellation shaders, peel away the initial array type. SPIRV-Cross adds the array back automatically.
				// Only some builtins will be arrayed here.
				if (((model == spv::ExecutionModelTessellationControl || (model == spv::ExecutionModelTessellationEvaluation && storage == spv::StorageClassInput)) && !patch &&
					 (biType == spv::BuiltInMax || biType == spv::BuiltInPosition || biType == spv::BuiltInPointSize ||
					  biType == spv::BuiltInClipDistance || biType == spv::BuiltInCullDistance)) ||
					(meshOutput && !type->array.empty()))
					type = &reflect.get_type(type->parent_type);

				// PerVertexKHR's outer array selects a vertex, not additional varying locations.
				bool perVertex = model == spv::ExecutionModelFragment && storage == spv::StorageClassInput && reflect.has_decoration(varID, spv::DecorationPerVertexKHR);
				if (perVertex && !type->array.empty()) { type = &reflect.get_type(type->parent_type); }
				uint32_t elemCnt = type->columns;
				for (uint32_t count : type->array) { elemCnt *= count; }
				for (uint32_t i = 0; i < elemCnt; i++) {
					if (type->basetype == SPIRV_CROSS_NAMESPACE::SPIRType::Struct) {
						loc = getShaderInterfaceStructMembers(reflect, vars, size_t(-1), type, storage, patch, loc, perVertex);
					} else {
						vars.push_back({type->basetype, type->vecsize, loc, cmp, 0, biType, patch, isUsed, perVertex});
						loc = addSat(loc, 1);
					}
				}
			}
			// Sort variables by ascending location.
			std::stable_sort(vars.begin(), vars.end(), [](const SPIRVShaderInterfaceVariable& a, const SPIRVShaderInterfaceVariable& b) {
				return a.location < b.location;
			});
			// Assign locations to variables that don't have one.
			uint32_t loc = -1;
			for (SPIRVShaderInterfaceVariable& var : vars) {
				if (var.location == uint32_t(-1)) { var.location = loc + 1; }
				loc = var.location;
			}
			return true;
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
		} catch (SPIRV_CROSS_NAMESPACE::CompilerError& ex) {
			errorLog = ex.what();
			return false;
		}
#endif
	}
	template<typename Vs, typename Vo>
	static inline bool getShaderOutputs(const Vs& spirv, spv::ExecutionModel model, const std::string& entryName,
										Vo& outputs, std::string& errorLog) {
		return getShaderInterfaceVariables(spirv, spv::StorageClassOutput, model, entryName, outputs, errorLog);
	}
	template<typename Vs, typename Vo>
	static inline bool getShaderInputs(const Vs& spirv, spv::ExecutionModel model, const std::string& entryName,
										Vo& outputs, std::string& errorLog) {
		return getShaderInterfaceVariables(spirv, spv::StorageClassInput, model, entryName, outputs, errorLog);
	}

}
#endif
