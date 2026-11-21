/*
 * SPIRVDualSourceBlend.h
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
	 * Writes zeros to whichever of the two dual source blending outputs the fragment shader leaves
	 * unassigned, declaring the first source where the shader never declared it, and returns
	 * whether it changed anything.
	 *
	 * Vulkan leaves the value of an output the shader never assigns undefined, and SPIRV-Cross
	 * drops such an output as inactive. Metal then refuses to build the pipeline, because blending
	 * from two sources reads both of them, so a shader that assigned only one of the pair could
	 * not be drawn with at all. A shader that declares no second source is not blending from two
	 * of them and is left untouched.
	 *
	 * See the Vulkan specification, Fragment Output Interface, and MTLRenderPipelineDescriptor.
	 */
	bool addMissingDualSourceOutput(std::vector<uint32_t>& spirv, std::string& log);

}
