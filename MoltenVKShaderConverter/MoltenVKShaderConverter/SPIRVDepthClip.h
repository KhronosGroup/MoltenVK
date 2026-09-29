/*
 * SPIRVDepthClip.h
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

#pragma mark -
#pragma mark SPIRVDepthClip

	/**
	 * Rewrites a shader that writes a position so that it maps the depth it writes according to a
	 * flag the driver supplies at draw time, instead of according to a convention baked in when
	 * the shader was compiled.
	 *
	 * VK_EXT_depth_clip_control lets a depth run from minus one, which Metal does not clip
	 * against, so SPIRV-Cross maps such a depth onto the range Metal does. Under
	 * VK_EXT_shader_object a draw can change the convention, and baking it means each value costs
	 * a recompile of the shader as well as a pipeline. The mapping SPIRV-Cross would have written
	 * is used unchanged, chosen at draw time rather than at compile time.
	 */

	/** The block the driver fills in, laid out as the rewritten shader reads it. */
	typedef struct SPIRVDepthClipState {
		uint32_t negativeOneToOne[4];	/**< A non-zero first component maps the depth. */
	} SPIRVDepthClipState;

	static_assert(sizeof(SPIRVDepthClipState) == 16, "SPIRVDepthClipState must match the std140 layout the shader reads.");

	/**
	 * The descriptor set and binding the state block is declared at, which the converter maps to
	 * a Metal buffer index. The set is beyond the argument buffer range, as the driver binds this
	 * buffer itself rather than through a descriptor set the application supplied.
	 */
	static constexpr uint32_t kSPIRVDepthClipDescriptorSet = 8;
	static constexpr uint32_t kSPIRVDepthClipBinding = 17;

	/**
	 * Rewrites the shader to map the depth it writes according to the state block, and returns
	 * whether it did. Declines, leaving the shader untouched, where it writes no position the
	 * mapping can reach.
	 */
	bool mapDepthClipInShader(std::vector<uint32_t>& spirv, std::string& log);

	/** Returns whether mapDepthClipInShader() would rewrite this shader, without changing it. */
	bool canMapDepthClipInShader(const std::vector<uint32_t>& spirv, std::string& log);

}
