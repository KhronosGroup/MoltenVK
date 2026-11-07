/*
 * SPIRVVertexPulling.h
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace mvk {

	/**
	 * The layout of the vertex input block a vertex shader reads after the transform below.
	 *
	 * One entry per attribute location. The driver resolves each attribute to the GPU address
	 * of its first element, the stride between elements, the instance divisor, a description
	 * of its format, and how many bytes may be read from that address. The shader computes the
	 * element to fetch, checks it against the bound, loads the raw bytes and converts them.
	 *
	 * Laid out as std140 arrays of uvec4, which have a 16 byte stride, so this maps directly.
	 */
	static constexpr uint32_t kSPIRVVertexPullMaxLocations = 32;

	struct SPIRVVertexPullAttribute {
		uint32_t addressLo;			/**< GPU address of element zero of this attribute, low word. */
		uint32_t addressHi;			/**< GPU address of element zero of this attribute, high word. */
		uint32_t stride;			/**< Bytes between consecutive elements. */
		uint32_t divisor;			/**< Instance divisor, for an instanced attribute. */
		uint32_t control;			/**< Format and rate, see the kSPIRVVertexPull flags. */
		uint32_t byteBound;			/**< Bytes readable from the address; an element past it reads as zero. */
		uint32_t unused[2];
	};

	struct SPIRVVertexPullState {
		SPIRVVertexPullAttribute attributes[kSPIRVVertexPullMaxLocations];	/**< Indexed by location. */
		uint32_t nullAddressLo;		/**< GPU address of a zeroed buffer, read for out-of-bounds elements, low word. */
		uint32_t nullAddressHi;		/**< GPU address of a zeroed buffer, read for out-of-bounds elements, high word. */
		uint32_t unused[2];
	};
	static_assert(sizeof(SPIRVVertexPullState) == 1040, "SPIRVVertexPullState must match the std140 layout the shader reads.");

	/** The smallest buffer the null address may point at, so that any element reads within it. */
	static constexpr uint32_t kSPIRVVertexPullNullBufferSize = 64;

	/** The numeric kind of a vertex format, in the control word. */
	enum SPIRVVertexPullKind : uint32_t {
		kSPIRVVertexPullUnorm = 0,
		kSPIRVVertexPullSnorm = 1,
		kSPIRVVertexPullUInt = 2,
		kSPIRVVertexPullSInt = 3,
		kSPIRVVertexPullSFloat = 4,
		kSPIRVVertexPullUScaled = 5,
		kSPIRVVertexPullSScaled = 6,
	};

	/** The control word: component count, component size, numeric kind, and flags. */
	static constexpr uint32_t kSPIRVVertexPullComponentCountShift = 0;		/**< 0..4, three bits. */
	static constexpr uint32_t kSPIRVVertexPullComponentSizeShift = 3;		/**< log2 of the bytes per component, two bits. */
	static constexpr uint32_t kSPIRVVertexPullKindShift = 5;				/**< A SPIRVVertexPullKind, four bits. */
	static constexpr uint32_t kSPIRVVertexPullFlagPacked = 1u << 9;			/**< 10-10-10-2 bit packing, in one 32 bit word. */
	static constexpr uint32_t kSPIRVVertexPullFlagSwapRedBlue = 1u << 10;	/**< The first and third components are stored swapped. */
	static constexpr uint32_t kSPIRVVertexPullFlagInstanced = 1u << 11;		/**< Advances per instance rather than per vertex. */

	/** The descriptor set and binding the transformed shader reads the vertex input block from. */
	static constexpr uint32_t kSPIRVVertexPullDescriptorSet = 8;
	static constexpr uint32_t kSPIRVVertexPullBinding = 16;

	/**
	 * Rewrites a vertex shader so that it loads its own vertex attributes from the vertex
	 * buffers, instead of receiving them through the vertex layout baked into a Metal pipeline.
	 *
	 * Metal fixes the vertex formats, offsets, bindings and step rates when a pipeline is built,
	 * so any change to them costs a new pipeline. Apple GPUs have no vertex fetch hardware: the
	 * layout a pipeline is built with becomes loads and conversions at the top of the vertex
	 * function. This transform makes those explicit, with the layout read from a uniform block
	 * at draw time rather than compiled in. For each input, it computes the element from the
	 * vertex or instance index, checks it against the bytes bound, loads the raw words through
	 * a physical storage buffer pointer, converts them according to the format, and stores the
	 * result in a private variable the rest of the shader reads as it did before. The vertex
	 * layout then leaves the pipeline entirely, and changing it costs a buffer update.
	 *
	 * Returns true if the shader was transformed, which it also is when it has no attribute
	 * inputs, since no layout then matters. Returns false, leaving the SPIR-V untouched, when
	 * the shader is not a vertex shader, or has an input that is not a 32-bit scalar, vector,
	 * matrix, or an array of those, or that uses the Component decoration; the caller then keeps
	 * the vertex layout in the pipeline as before. On failure, log describes the reason.
	 */
	bool pullVerticesInShader(std::vector<uint32_t>& spirv, std::string& log);

	/**
	 * Returns whether pullVerticesInShader() would transform this shader, without transforming
	 * it. A shader object needs to know this when it is created, because it decides whether the
	 * vertex layout belongs in the key its pipelines are cached under.
	 */
	bool canPullVerticesInShader(const std::vector<uint32_t>& spirv);

}
