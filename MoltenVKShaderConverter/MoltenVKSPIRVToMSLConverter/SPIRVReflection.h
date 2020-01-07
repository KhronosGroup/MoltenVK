/*
 * SPIRVReflection.h
 *
 * Copyright (c) 2019-2020 Chip Davis for Codeweavers
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

#include <SPIRV-Cross/spirv.hpp>
#include <SPIRV-Cross/spirv_common.hpp>
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
	bool getTessReflectionData(const std::vector<uint32_t>& tesc, const std::string& tescEntryName, const std::vector<uint32_t>& tese, const std::string& teseEntryName, SPIRVTessReflectionData& reflectData, std::string& errorLog);

	/** Given a shader in SPIR-V format, returns output reflection data. */
	bool getShaderOutputs(const std::vector<uint32_t>& spirv, spv::ExecutionModel model, const std::string& entryName, std::vector<SPIRVShaderOutput>& outputs, std::string& errorLog);

}
#endif
