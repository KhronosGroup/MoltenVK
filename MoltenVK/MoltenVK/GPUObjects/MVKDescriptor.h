/*
 * MVKDescriptor.h
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

#pragma once

#include "MVKImage.h"
#include "MVKSmallVector.h"
#include "MVKMTLBufferAllocation.h"

class MVKDescriptorSet;
class MVKDescriptorSetLayout;
class MVKCommandEncoder;
class MVKResourcesCommandEncoderState;


/** Magic number to indicate the variable descriptor count is currently unknown. */
static uint32_t kMVKVariableDescriptorCountUnknown = std::numeric_limits<uint32_t>::max();


#pragma mark MVKShaderStageResourceBinding

/** Indicates the Metal resource indexes used by a single shader stage in a descriptor. */
typedef struct MVKShaderStageResourceBinding {
	uint32_t bufferIndex = 0;
	uint32_t textureIndex = 0;
	uint32_t samplerIndex = 0;
	uint32_t dynamicOffsetBufferIndex = 0;

	MVKShaderStageResourceBinding operator+(const MVKShaderStageResourceBinding& rhs) const { auto tmp = *this; tmp += rhs; return tmp;}
	MVKShaderStageResourceBinding& operator+=(const MVKShaderStageResourceBinding& rhs) {
		bufferIndex += rhs.bufferIndex;
		textureIndex += rhs.textureIndex;
		samplerIndex += rhs.samplerIndex;
		dynamicOffsetBufferIndex += rhs.dynamicOffsetBufferIndex;
		return *this;
	}
	void clearArgumentBufferResources() {
		bufferIndex = 0;
		textureIndex = 0;
		samplerIndex = 0;
	}
} MVKShaderStageResourceBinding;


#pragma mark MVKShaderResourceBinding

/** Indicates the Metal resource indexes used by each shader stage in a descriptor. */
typedef struct MVKShaderResourceBinding {
	MVKShaderStageResourceBinding stages[kMVKShaderStageCount];

	uint32_t getMaxBufferIndex();
	uint32_t getMaxTextureIndex();
	uint32_t getMaxSamplerIndex();

	MVKShaderResourceBinding operator+ (const MVKShaderResourceBinding& rhs);
	MVKShaderResourceBinding& operator+= (const MVKShaderResourceBinding& rhs);
	MVKShaderStageResourceBinding& getMetalResourceIndexes(MVKShaderStage stage = kMVKShaderStageVertex) { return stages[stage]; }
	void clearArgumentBufferResources();
	void addArgumentBuffers(uint32_t count);

} MVKShaderResourceBinding;
