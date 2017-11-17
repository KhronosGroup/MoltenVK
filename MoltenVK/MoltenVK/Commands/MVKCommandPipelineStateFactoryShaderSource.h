/*
 * MVKCommandPipelineStateFactoryShaderSource.h
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
fragment float4 fragCmdBlitImageF(VaryingsPosTex varyings [[stage_in]],                                         \n\
                                  texture2d<float> texture [[texture(0)]],                                      \n\
                                  sampler sampler  [[ sampler(0) ]]) {                                          \n\
	return texture.sample(sampler, varyings.v_texCoord);                                                        \n\
};                                                                                                              \n\
                                                                                                                \n\
fragment int4 fragCmdBlitImageI(VaryingsPosTex varyings [[stage_in]],                                           \n\
                                texture2d<int> texture [[texture(0)]],                                          \n\
                                sampler sampler  [[ sampler(0) ]]) {                                            \n\
    return texture.sample(sampler, varyings.v_texCoord);                                                        \n\
};                                                                                                              \n\
                                                                                                                \n\
fragment uint4 fragCmdBlitImageU(VaryingsPosTex varyings [[stage_in]],                                          \n\
                                 texture2d<uint> texture [[texture(0)]],                                        \n\
                                 sampler sampler  [[ sampler(0) ]]) {                                           \n\
    return texture.sample(sampler, varyings.v_texCoord);                                                        \n\
};                                                                                                              \n\
                                                                                                                \n\
fragment float4 fragCmdBlitImageDF(VaryingsPosTex varyings [[stage_in]],                                        \n\
                                   depth2d<float> texture [[texture(0)]],                                       \n\
                                   sampler sampler  [[ sampler(0) ]]) {                                         \n\
    return texture.sample(sampler, varyings.v_texCoord);                                                        \n\
};                                                                                                              \n\
                                                                                                                \n\
fragment int4 fragCmdBlitImageDI(VaryingsPosTex varyings [[stage_in]],                                          \n\
                                 depth2d<float> texture [[texture(0)]],                                         \n\
                                 sampler sampler  [[ sampler(0) ]]) {                                           \n\
    return int4(texture.sample(sampler, varyings.v_texCoord));                                                  \n\
};                                                                                                              \n\
                                                                                                                \n\
fragment uint4 fragCmdBlitImageDU(VaryingsPosTex varyings [[stage_in]],                                         \n\
                                  depth2d<float> texture [[texture(0)]],                                        \n\
                                  sampler sampler  [[ sampler(0) ]]) {                                          \n\
    return uint4(texture.sample(sampler, varyings.v_texCoord));                                                 \n\
};                                                                                                              \n\
																			                			        \n\
typedef struct {                                                                                                \n\
    float4 colors[9];                                                                                           \n\
} ClearColorsIn;                                                                                                \n\
												        						        				        \n\
typedef struct {                                                                                                \n\
    float4 color0  [[color(0)]];                                                                                \n\
    float4 color1  [[color(1)]];                                                                                \n\
    float4 color2  [[color(2)]];                                                                                \n\
    float4 color3  [[color(3)]];                                                                                \n\
    float4 color4  [[color(4)]];					                									        \n\
    float4 color5  [[color(5)]];							                							        \n\
    float4 color6  [[color(6)]];									                					        \n\
    float4 color7  [[color(7)]];											                			        \n\
} ClearColorsOutF;                                                                                              \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    int4 color0  [[color(0)]];                                                                                  \n\
    int4 color1  [[color(1)]];                                                                                  \n\
    int4 color2  [[color(2)]];                                                                                  \n\
    int4 color3  [[color(3)]];                                                                                  \n\
    int4 color4  [[color(4)]];                                                                                  \n\
    int4 color5  [[color(5)]];                                                                                  \n\
    int4 color6  [[color(6)]];                                                                                  \n\
    int4 color7  [[color(7)]];                                                                                  \n\
} ClearColorsOutI;                                                                                              \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    uint4 color0  [[color(0)]];                                                                                 \n\
    uint4 color1  [[color(1)]];                                                                                 \n\
    uint4 color2  [[color(2)]];                                                                                 \n\
    uint4 color3  [[color(3)]];                                                                                 \n\
    uint4 color4  [[color(4)]];                                                                                 \n\
    uint4 color5  [[color(5)]];                                                                                 \n\
    uint4 color6  [[color(6)]];                                                                                 \n\
    uint4 color7  [[color(7)]];                                                                                 \n\
} ClearColorsOutU;                                                                                              \n\
                                                                                                                \n\
vertex VaryingsPos vtxCmdClearAttachments(AttributesPos attributes [[stage_in]],                                \n\
                                          constant ClearColorsIn& ccIn [[buffer(0)]]) {                         \n\
    VaryingsPos varyings;                                                                                       \n\
    varyings.gl_Position = float4(attributes.a_position.x, -attributes.a_position.y, ccIn.colors[8].r, 1.0);    \n\
    return varyings;                                                                                            \n\
}                                                                                                               \n\
																		                				        \n\
fragment ClearColorsOutF fragCmdClearAttachmentsF(VaryingsPos varyings [[stage_in]],                            \n\
                                                  constant ClearColorsIn& ccIn [[buffer(0)]]) {                 \n\
    ClearColorsOutF ccOut;                                                                                      \n\
    ccOut.color0 = ccIn.colors[0];                                                                              \n\
    ccOut.color1 = ccIn.colors[1];                                                                              \n\
    ccOut.color2 = ccIn.colors[2];                                                                              \n\
    ccOut.color3 = ccIn.colors[3];                                                                              \n\
    ccOut.color4 = ccIn.colors[4];                                                                              \n\
    ccOut.color5 = ccIn.colors[5];                                                                              \n\
    ccOut.color6 = ccIn.colors[6];                                                                              \n\
    ccOut.color7 = ccIn.colors[7];                                                                              \n\
    return ccOut;                                                                                               \n\
};                                                                                                              \n\
																		                				        \n\
fragment float4 fragCmdClearAttachments0F(VaryingsPos varyings [[stage_in]],                                    \n\
                                         constant ClearColorsIn& ccIn [[buffer(0)]]) {                          \n\
    return ccIn.colors[0];                                                                                      \n\
};                                                                                                              \n\
                                                                                                                \n\
fragment ClearColorsOutI fragCmdClearAttachmentsI(VaryingsPos varyings [[stage_in]],                            \n\
                                                  constant ClearColorsIn& ccIn [[buffer(0)]]) {                 \n\
    ClearColorsOutI ccOut;                                                                                      \n\
    ccOut.color0 = int4(ccIn.colors[0]);                                                                        \n\
    ccOut.color1 = int4(ccIn.colors[1]);                                                                        \n\
    ccOut.color2 = int4(ccIn.colors[2]);                                                                        \n\
    ccOut.color3 = int4(ccIn.colors[3]);                                                                        \n\
    ccOut.color4 = int4(ccIn.colors[4]);                                                                        \n\
    ccOut.color5 = int4(ccIn.colors[5]);                                                                        \n\
    ccOut.color6 = int4(ccIn.colors[6]);                                                                        \n\
    ccOut.color7 = int4(ccIn.colors[7]);                                                                        \n\
    return ccOut;                                                                                               \n\
};                                                                                                              \n\
                                                                                                                \n\
fragment int4 fragCmdClearAttachments0I(VaryingsPos varyings [[stage_in]],                                      \n\
                                       constant ClearColorsIn& ccIn [[buffer(0)]]) {                            \n\
    return int4(ccIn.colors[0]);                                                                                \n\
};                                                                                                              \n\
                                                                                                                \n\
fragment ClearColorsOutU fragCmdClearAttachmentsU(VaryingsPos varyings [[stage_in]],                            \n\
                                                  constant ClearColorsIn& ccIn [[buffer(0)]]) {                 \n\
    ClearColorsOutU ccOut;                                                                                      \n\
    ccOut.color0 = uint4(ccIn.colors[0]);                                                                       \n\
    ccOut.color1 = uint4(ccIn.colors[1]);                                                                       \n\
    ccOut.color2 = uint4(ccIn.colors[2]);                                                                       \n\
    ccOut.color3 = uint4(ccIn.colors[3]);                                                                       \n\
    ccOut.color4 = uint4(ccIn.colors[4]);                                                                       \n\
    ccOut.color5 = uint4(ccIn.colors[5]);                                                                       \n\
    ccOut.color6 = uint4(ccIn.colors[6]);                                                                       \n\
    ccOut.color7 = uint4(ccIn.colors[7]);                                                                       \n\
    return ccOut;                                                                                               \n\
};                                                                                                              \n\
                                                                                                                \n\
fragment uint4 fragCmdClearAttachments0U(VaryingsPos varyings [[stage_in]],                                     \n\
                                        constant ClearColorsIn& ccIn [[buffer(0)]]) {                           \n\
    return uint4(ccIn.colors[0]);                                                                               \n\
};                                                                                                              \n\
";


