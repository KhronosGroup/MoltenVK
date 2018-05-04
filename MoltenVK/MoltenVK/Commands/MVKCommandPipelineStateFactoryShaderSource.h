/*
 * MVKCommandPipelineStateFactoryShaderSource.h
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


/** This file contains static source code for the MoltenVK command shaders. */

static const char* _MVKStaticCmdShaderSource = "                                                                \n\
#include <metal_stdlib>                                                                                         \n\
using namespace metal;                                                                                          \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    float2 a_position	[[attribute(0)]];                                                                       \n\
} AttributesPos;                                                                                                \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    float4 gl_Position [[position]];                                                                            \n\
} VaryingsPos;                                                                                                  \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    float2 a_position	[[attribute(0)]];                                                                       \n\
    float2 a_texCoord	[[attribute(1)]];                                                                       \n\
} AttributesPosTex;                                                                                             \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    float4 gl_Position [[position]];                                                                            \n\
    float2 v_texCoord;                                                                                          \n\
} VaryingsPosTex;                                                                                               \n\
                                                                                                                \n\
vertex VaryingsPosTex vtxCmdBlitImage(AttributesPosTex attributes [[stage_in]]) {                               \n\
    VaryingsPosTex varyings;                                                                                    \n\
    varyings.gl_Position = float4(attributes.a_position, 0.0, 1.0);                                             \n\
    varyings.v_texCoord = attributes.a_texCoord;                                                                \n\
    return varyings;                                                                                            \n\
}                                                                                                               \n\
                                                                                                                \n\
vertex VaryingsPos vtxCmdBlitImageD(AttributesPosTex attributes [[stage_in]],                                   \n\
                                    depth2d<float> texture [[texture(0)]],                                      \n\
                                    sampler sampler  [[ sampler(0) ]]) {                                        \n\
    float depth = texture.sample(sampler, attributes.a_texCoord);                                               \n\
    VaryingsPos varyings;                                                                                       \n\
    varyings.gl_Position = float4(attributes.a_position, depth, 1.0);                                           \n\
    return varyings;                                                                                            \n\
}                                                                                                               \n\
																			                			        \n\
typedef struct {                                                                                                \n\
    float4 colors[9];                                                                                           \n\
} ClearColorsIn;                                                                                                \n\
												        						        				        \n\
vertex VaryingsPos vtxCmdClearAttachments(AttributesPos attributes [[stage_in]],                                \n\
                                          constant ClearColorsIn& ccIn [[buffer(0)]]) {                         \n\
    VaryingsPos varyings;                                                                                       \n\
    varyings.gl_Position = float4(attributes.a_position.x, -attributes.a_position.y, ccIn.colors[8].r, 1.0);    \n\
    return varyings;                                                                                            \n\
}                                                                                                               \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    uint32_t srcOffset;                                                                                         \n\
    uint32_t dstOffset;                                                                                         \n\
    uint32_t copySize;                                                                                          \n\
} CopyInfo;                                                                                                     \n\
                                                                                                                \n\
kernel void compCopyBufferBytes(device uint8_t* src [[ buffer(0) ]],                                            \n\
                                device uint8_t* dst [[ buffer(1) ]],                                            \n\
                                constant CopyInfo& info [[ buffer(2) ]]) {                                      \n\
    for (size_t i = 0; i < info.copySize; i++) {                                                                \n\
        dst[i + info.dstOffset] = src[i + info.srcOffset];                                                      \n\
    }                                                                                                           \n\
};                                                                                                              \n\
";


