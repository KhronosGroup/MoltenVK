/*
 * MVKWatermarkShaderSource.h
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


/** This file contains static source code for the Watermark shaders. */

static const char* __watermarkShaderSource = "											\n\
#include <metal_stdlib>																	\n\
using namespace metal;																	\n\
																						\n\
typedef struct {																		\n\
	float4x4 mvpMtx;																	\n\
	float4 color;																		\n\
} Uniforms;																				\n\
																						\n\
typedef struct {																		\n\
	float2 a_position	[[attribute(0)]];												\n\
	float2 a_texCoord	[[attribute(1)]];												\n\
} Attributes;																			\n\
																						\n\
typedef struct {																		\n\
	float4 v_position [[position]];													\n\
	float2 v_texCoord;																	\n\
	float4 v_fragColor;																	\n\
} Varyings;																				\n\
																						\n\
vertex Varyings watermarkVertex(Attributes attributes [[stage_in]],						\n\
								constant Uniforms& uniforms [[ buffer(0) ]]) {			\n\
	Varyings varyings;																	\n\
	varyings.v_position = uniforms.mvpMtx * float4(attributes.a_position, 0.0, 1.0);	\n\
	varyings.v_fragColor = uniforms.color;												\n\
	varyings.v_texCoord = attributes.a_texCoord;										\n\
	return varyings;																	\n\
}																						\n\
																						\n\
fragment float4 watermarkFragment(Varyings varyings [[stage_in]],						\n\
								  texture2d<float> texture [[ texture(0) ]],			\n\
								  sampler sampler  [[ sampler(0) ]]) {					\n\
	return varyings.v_fragColor * texture.sample(sampler, varyings.v_texCoord);			\n\
};																						\n\
";






