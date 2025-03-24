/*
 * MVKDescriptor.mm
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

#include "MVKDescriptor.h"
#include "MVKDescriptorSet.h"
#include "MVKBuffer.h"
#include <sstream>
#include <iomanip>


#define BIND_GRAPHICS_OR_COMPUTE(cmdEncoder, bind, pipelineBindPoint, stage, ...) \
	do { \
		if ((stage) == kMVKShaderStageCompute) { \
			if ((cmdEncoder) && (pipelineBindPoint) == VK_PIPELINE_BIND_POINT_COMPUTE) \
				(cmdEncoder)->_computeResourcesState.bind(__VA_ARGS__); \
		} else { \
			if ((cmdEncoder) && (pipelineBindPoint) == VK_PIPELINE_BIND_POINT_GRAPHICS) \
				(cmdEncoder)->_graphicsResourcesState.bind(static_cast<MVKShaderStage>(stage), __VA_ARGS__); \
		} \
	} while (0)

#pragma mark MVKShaderResourceBinding

uint32_t MVKShaderResourceBinding::getMaxBufferIndex() {
	return std::max({stages[kMVKShaderStageVertex].bufferIndex, stages[kMVKShaderStageTessCtl].bufferIndex, stages[kMVKShaderStageTessEval].bufferIndex, stages[kMVKShaderStageFragment].bufferIndex, stages[kMVKShaderStageCompute].bufferIndex});
}

uint32_t MVKShaderResourceBinding::getMaxTextureIndex() {
	return std::max({stages[kMVKShaderStageVertex].textureIndex, stages[kMVKShaderStageTessCtl].textureIndex, stages[kMVKShaderStageTessEval].textureIndex, stages[kMVKShaderStageFragment].textureIndex, stages[kMVKShaderStageCompute].textureIndex});
}

uint32_t MVKShaderResourceBinding::getMaxSamplerIndex() {
	return std::max({stages[kMVKShaderStageVertex].samplerIndex, stages[kMVKShaderStageTessCtl].samplerIndex, stages[kMVKShaderStageTessEval].samplerIndex, stages[kMVKShaderStageFragment].samplerIndex, stages[kMVKShaderStageCompute].samplerIndex});
}

MVKShaderResourceBinding MVKShaderResourceBinding::operator+ (const MVKShaderResourceBinding& rhs) {
	MVKShaderResourceBinding rslt;
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		rslt.stages[i] = this->stages[i] + rhs.stages[i];
	}
	return rslt;
}

MVKShaderResourceBinding& MVKShaderResourceBinding::operator+= (const MVKShaderResourceBinding& rhs) {
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		this->stages[i] += rhs.stages[i];
	}
	return *this;
}

void MVKShaderResourceBinding::clearArgumentBufferResources() {
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		stages[i].clearArgumentBufferResources();
	}
}

void MVKShaderResourceBinding::addArgumentBuffers(uint32_t count) {
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		stages[i].bufferIndex += count;
	}
}
