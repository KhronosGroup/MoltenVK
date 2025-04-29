/*
 * MVKCommandPipelineStateFactoryShaderSource.h
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

#include "MVKDevice.h"

#import <Foundation/Foundation.h>


/** This file contains static MSL source code for the MoltenVK command shaders. */

static NSString* _MVKStaticCmdShaderSource = @"                                                                 \n\
#include <metal_stdlib>                                                                                         \n\
using namespace metal;                                                                                          \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    float2 a_position [[attribute(0)]];                                                                         \n\
    float3 a_texCoord [[attribute(1)]];                                                                         \n\
} AttributesPosTex;                                                                                             \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    float4 v_position [[position]];                                                                             \n\
    float3 v_texCoord;                                                                                          \n\
} VaryingsPosTex;                                                                                               \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    float4 v_position [[position]];                                                                             \n\
    float3 v_texCoord;                                                                                          \n\
    uint v_layer [[render_target_array_index]];                                                                 \n\
} VaryingsPosTexLayer;                                                                                          \n\
                                                                                                                \n\
typedef size_t VkDeviceSize;                                                                                    \n\
                                                                                                                \n\
typedef enum : uint32_t {                                                                                       \n\
    VK_FORMAT_BC1_RGB_UNORM_BLOCK = 131,                                                                        \n\
    VK_FORMAT_BC1_RGB_SRGB_BLOCK = 132,                                                                         \n\
    VK_FORMAT_BC1_RGBA_UNORM_BLOCK = 133,                                                                       \n\
    VK_FORMAT_BC1_RGBA_SRGB_BLOCK = 134,                                                                        \n\
    VK_FORMAT_BC2_UNORM_BLOCK = 135,                                                                            \n\
    VK_FORMAT_BC2_SRGB_BLOCK = 136,                                                                             \n\
    VK_FORMAT_BC3_UNORM_BLOCK = 137,                                                                            \n\
    VK_FORMAT_BC3_SRGB_BLOCK = 138,                                                                             \n\
} VkFormat;                                                                                                     \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    uint32_t width;                                                                                             \n\
    uint32_t height;                                                                                            \n\
} VkExtent2D;                                                                                                   \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    uint32_t width;                                                                                             \n\
    uint32_t height;                                                                                            \n\
    uint32_t depth;                                                                                             \n\
} __attribute__((packed)) VkExtent3D;                                                                           \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    int32_t x;                                                                                                  \n\
    int32_t y;                                                                                                  \n\
    int32_t z;                                                                                                  \n\
} __attribute__((packed)) VkOffset3D;                                                                           \n\
                                                                                                                \n"
#define MVK_DECOMPRESS_CODE(...) #__VA_ARGS__
#include "MVKDXTnCodec.def"
#undef MVK_DECOMPRESS_CODE
"\n\
                                                                                                                \n\
vertex VaryingsPosTex vtxCmdBlitImage(AttributesPosTex attributes [[stage_in]]) {                               \n\
    VaryingsPosTex varyings;                                                                                    \n\
    varyings.v_position = float4(attributes.a_position, 0.0, 1.0);                                              \n\
    varyings.v_texCoord = attributes.a_texCoord;                                                                \n\
    return varyings;                                                                                            \n\
}                                                                                                               \n\
																			                			        \n\
vertex VaryingsPosTexLayer vtxCmdBlitImageLayered(AttributesPosTex attributes [[stage_in]],                     \n\
                                                  uint instanceID [[instance_id]],                              \n\
                                                  constant float &zIncr [[buffer(0)]]) {                        \n\
    VaryingsPosTexLayer varyings;                                                                               \n\
    varyings.v_position = float4(attributes.a_position, 0.0, 1.0);                                              \n\
    varyings.v_texCoord = float3(attributes.a_texCoord.xy, attributes.a_texCoord.z + (instanceID + 0.5) * zIncr);\n\
    varyings.v_layer = instanceID;                                                                              \n\
    return varyings;                                                                                            \n\
}                                                                                                               \n\
																			                			        \n\
typedef struct {                                                                                                \n\
    uint32_t srcOffset;                                                                                         \n\
    uint32_t dstOffset;                                                                                         \n\
    uint32_t size;                                                                                              \n\
} CopyInfo;                                                                                                     \n\
                                                                                                                \n\
kernel void cmdCopyBufferBytes(device uint8_t* src [[ buffer(0) ]],                                             \n\
                               device uint8_t* dst [[ buffer(1) ]],                                             \n\
                               constant CopyInfo& info [[ buffer(2) ]]) {                                       \n\
    for (size_t i = 0; i < info.size; i++) {                                                                    \n\
        dst[i + info.dstOffset] = src[i + info.srcOffset];                                                      \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdFillBuffer(device uint32_t* dst [[ buffer(0) ]],                                                 \n\
                          constant uint32_t& fillValue [[ buffer(1) ]],                                         \n\
                          uint pos [[thread_position_in_grid]]) {                                               \n\
    dst[pos] = fillValue;                                                                                       \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdClearColorImage2DFloat(texture2d<float, access::write> dst [[ texture(0) ]],                     \n\
                                      constant float4& clearValue [[ buffer(0) ]],                              \n\
                                      uint2 pos [[thread_position_in_grid]]) {                                  \n\
    dst.write(clearValue, pos);                                                                                 \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdClearColorImage2DFloatArray(texture2d_array<float, access::write> dst [[ texture(0) ]],          \n\
                                           constant float4& clearValue [[ buffer(0) ]],                         \n\
                                           uint2 pos [[thread_position_in_grid]]) {                             \n\
    for (uint i = 0u; i < dst.get_array_size(); ++i) {                                                          \n\
        dst.write(clearValue, pos, i);                                                                          \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdClearColorImage2DUInt(texture2d<uint, access::write> dst [[ texture(0) ]],                       \n\
                                     constant uint4& clearValue [[ buffer(0) ]],                                \n\
                                     uint2 pos [[thread_position_in_grid]]) {                                   \n\
    dst.write(clearValue, pos);                                                                                 \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdClearColorImage2DUIntArray(texture2d_array<uint, access::write> dst [[ texture(0) ]],            \n\
                                          constant uint4& clearValue [[ buffer(0) ]],                           \n\
                                          uint2 pos [[thread_position_in_grid]]) {                              \n\
    for (uint i = 0u; i < dst.get_array_size(); ++i) {                                                          \n\
        dst.write(clearValue, pos, i);                                                                          \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdClearColorImage2DInt(texture2d<int, access::write> dst [[ texture(0) ]],                         \n\
                                    constant int4& clearValue [[ buffer(0) ]],                                  \n\
                                    uint2 pos [[thread_position_in_grid]]) {                                    \n\
    dst.write(clearValue, pos);                                                                                 \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdClearColorImage2DIntArray(texture2d_array<int, access::write> dst [[ texture(0) ]],              \n\
                                         constant int4& clearValue [[ buffer(0) ]],                             \n\
                                         uint2 pos [[thread_position_in_grid]]) {                               \n\
    for (uint i = 0u; i < dst.get_array_size(); ++i) {                                                          \n\
        dst.write(clearValue, pos, i);                                                                          \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdResolveColorImage2DFloat(texture2d<float, access::write> dst [[ texture(0) ]],                   \n\
                                        texture2d_ms<float, access::read> src [[ texture(1) ]],                 \n\
                                        uint2 pos [[thread_position_in_grid]]) {                                \n\
    dst.write(src.read(pos, 0), pos);                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
#if __HAVE_TEXTURE_2D_MS_ARRAY__                                                                                \n\
kernel void cmdResolveColorImage2DFloatArray(texture2d_array<float, access::write> dst [[ texture(0) ]],        \n\
                                             texture2d_ms_array<float, access::read> src [[ texture(1) ]],      \n\
                                             uint2 pos [[thread_position_in_grid]]) {                           \n\
    for (uint i = 0u; i < src.get_array_size(); ++i) {                                                          \n\
        dst.write(src.read(pos, i, 0), pos, i);                                                                 \n\
    }                                                                                                           \n\
}                                                                                                               \n\
#endif                                                                                                          \n\
                                                                                                                \n\
kernel void cmdResolveColorImage2DUInt(texture2d<uint, access::write> dst [[ texture(0) ]],                     \n\
                                       texture2d_ms<uint, access::read> src [[ texture(1) ]],                   \n\
                                       uint2 pos [[thread_position_in_grid]]) {                                 \n\
    dst.write(src.read(pos, 0), pos);                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
#if __HAVE_TEXTURE_2D_MS_ARRAY__                                                                                \n\
kernel void cmdResolveColorImage2DUIntArray(texture2d_array<uint, access::write> dst [[ texture(0) ]],          \n\
                                            texture2d_ms_array<uint, access::read> src [[ texture(1) ]],        \n\
                                            uint2 pos [[thread_position_in_grid]]) {                            \n\
    for (uint i = 0u; i < src.get_array_size(); ++i) {                                                          \n\
        dst.write(src.read(pos, i, 0), pos, i);                                                                 \n\
    }                                                                                                           \n\
}                                                                                                               \n\
#endif                                                                                                          \n\
                                                                                                                \n\
kernel void cmdResolveColorImage2DInt(texture2d<int, access::write> dst [[ texture(0) ]],                       \n\
                                      texture2d_ms<int, access::read> src [[ texture(1) ]],                     \n\
                                      uint2 pos [[thread_position_in_grid]]) {                                  \n\
    dst.write(src.read(pos, 0), pos);                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
#if __HAVE_TEXTURE_2D_MS_ARRAY__                                                                                \n\
kernel void cmdResolveColorImage2DIntArray(texture2d_array<int, access::write> dst [[ texture(0) ]],            \n\
                                           texture2d_ms_array<int, access::read> src [[ texture(1) ]],          \n\
                                           uint2 pos [[thread_position_in_grid]]) {                             \n\
    for (uint i = 0u; i < src.get_array_size(); ++i) {                                                          \n\
        dst.write(src.read(pos, i, 0), pos, i);                                                                 \n\
    }                                                                                                           \n\
}                                                                                                               \n\
#endif                                                                                                          \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    uint32_t srcRowStride;                                                                                      \n\
    uint32_t srcRowStrideHigh;                                                                                  \n\
    uint32_t srcDepthStride;                                                                                    \n\
    uint32_t srcDepthStrideHigh;                                                                                \n\
    uint32_t destRowStride;                                                                                     \n\
    uint32_t destRowStrideHigh;                                                                                 \n\
    uint32_t destDepthStride;                                                                                   \n\
    uint32_t destDepthStrideHigh;                                                                               \n\
    VkFormat format;                                                                                            \n\
    VkOffset3D offset;                                                                                          \n\
    VkExtent3D extent;                                                                                          \n\
} CmdCopyBufferToImageInfo;                                                                                     \n\
                                                                                                                \n\
kernel void cmdCopyBufferToImage3DDecompressDXTn(const device uint8_t* src [[buffer(0)]],                       \n\
                                                 texture3d<float, access::write> dest [[texture(0)]],           \n\
                                                 constant CmdCopyBufferToImageInfo& info [[buffer(2)]],         \n\
                                                 uint3 pos [[thread_position_in_grid]]) {                       \n\
    uint x = pos.x * 4, y = pos.y * 4, z = pos.z;                                                               \n\
    VkDeviceSize blockByteCount = isBC1Format(info.format) ? 8 : 16;                                            \n\
                                                                                                                \n\
    if (x >= info.extent.width || y >= info.extent.height || z >= info.extent.depth) { return; }                \n\
                                                                                                                \n\
    src += z * info.srcDepthStride + y * info.srcRowStride / 4 + x * blockByteCount / 4;                        \n\
    VkExtent2D blockExtent;                                                                                     \n\
    blockExtent.width = min(info.extent.width - x, 4u);                                                         \n\
    blockExtent.height = min(info.extent.height - y, 4u);                                                       \n\
    uint pixels[16] = {0};                                                                                      \n\
    decompressDXTnBlock(src, pixels, blockExtent, 4 * sizeof(uint), info.format);                               \n\
    for (uint j = 0; j < blockExtent.height; ++j) {                                                             \n\
        for (uint i = 0; i < blockExtent.width; ++i) {                                                          \n\
            // The pixel components are in BGRA order, but texture::write wants them                            \n\
            // in RGBA order. We can fix that (ironically) with a BGRA swizzle.                                 \n\
            dest.write(unpack_unorm4x8_to_float(pixels[j * 4 + i]).bgra,                                        \n\
                       uint3(info.offset.x + x + i, info.offset.y + y + j, info.offset.z + z));                 \n\
        }                                                                                                       \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdCopyBufferToImage3DDecompressTempBufferDXTn(const device uint8_t* src [[buffer(0)]],             \n\
                                                           device uint8_t* dest [[buffer(1)]],                  \n\
                                                           constant CmdCopyBufferToImageInfo& info [[buffer(2)]],\n\
                                                           uint3 pos [[thread_position_in_grid]]) {             \n\
    uint x = pos.x * 4, y = pos.y * 4, z = pos.z;                                                               \n\
    VkDeviceSize blockByteCount = isBC1Format(info.format) ? 8 : 16;                                            \n\
                                                                                                                \n\
    if (x >= info.extent.width || y >= info.extent.height || z >= info.extent.depth) { return; }                \n\
                                                                                                                \n\
    src += z * info.srcDepthStride + y * info.srcRowStride / 4 + x * blockByteCount / 4;                        \n\
    dest += z * info.destDepthStride + y * info.destRowStride + x * sizeof(uint);                               \n\
    VkExtent2D blockExtent;                                                                                     \n\
    blockExtent.width = min(info.extent.width - x, 4u);                                                         \n\
    blockExtent.height = min(info.extent.height - y, 4u);                                                       \n\
    uint pixels[16] = {0};                                                                                      \n\
    decompressDXTnBlock(src, pixels, blockExtent, 4 * sizeof(uint), info.format);                               \n\
    device uint* destPixel = (device uint*)dest;                                                                \n\
    for (uint j = 0; j < blockExtent.height; ++j) {                                                             \n\
        for (uint i = 0; i < blockExtent.width; ++i) {                                                          \n\
            destPixel[j * info.destRowStride / sizeof(uint) + i] = pixels[j * 4 + i];                           \n\
        }                                                                                                       \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
#if __METAL_VERSION__ >= 210                                                                                    \n\
// This structure is missing from the MSL headers. :/                                                           \n\
struct MTLStageInRegionIndirectArguments {                                                                      \n\
    uint32_t stageInOrigin[3];                                                                                  \n\
    uint32_t stageInSize[3];                                                                                    \n\
};                                                                                                              \n\
#endif                                                                                                          \n\
                                                                                                                \n\
typedef enum : uint8_t {                                                                                        \n\
    MTLIndexTypeUInt16 = 0,                                                                                     \n\
    MTLIndexTypeUInt32 = 1,                                                                                     \n\
} MTLIndexType;                                                                                                 \n\
																												\n\
typedef struct MVKVtxAdj {                                                                                      \n\
    MTLIndexType idxType;                                                                                       \n\
    bool isMultiView;                                                                                           \n\
    bool isTriFan;                                                                                              \n\
} MVKVtxAdj;                                                                                                    \n\
                                                                                                                \n\
// Populates triangle vertex indexes for a triangle fan.                                                        \n\
template<typename T>                                                                                            \n\
static inline void populateTriIndxsFromTriFan(device T* triIdxs,                                                \n\
                                              constant T* triFanIdxs,                                           \n\
                                              uint32_t triFanIdxCnt) {                                          \n\
    T primRestartSentinel = (T)0xFFFFFFFF;                                                                      \n\
    uint32_t triIdxIdx = 0;                                                                                     \n\
    uint32_t triFanBaseIdx = 0;                                                                                 \n\
    uint32_t triFanIdxIdx = triFanBaseIdx + 2;                                                                  \n\
    while (triFanIdxIdx < triFanIdxCnt) {                                                                       \n\
        uint32_t triFanBaseIdxCurr = triFanBaseIdx;                                                             \n\
                                                                                                                \n\
        // Detect primitive restart on any index, to catch possible consecutive restarts                        \n\
        T triIdx0 = triFanIdxs[triFanBaseIdx];                                                                  \n\
        if (triIdx0 == primRestartSentinel)                                                                     \n\
            triFanBaseIdx++;                                                                                    \n\
                                                                                                                \n\
        T triIdx1 = triFanIdxs[triFanIdxIdx - 1];                                                               \n\
        if (triIdx1 == primRestartSentinel)                                                                     \n\
            triFanBaseIdx = triFanIdxIdx;                                                                       \n\
                                                                                                                \n\
        T triIdx2 = triFanIdxs[triFanIdxIdx];                                                                   \n\
        if (triIdx2 == primRestartSentinel)                                                                     \n\
            triFanBaseIdx = triFanIdxIdx + 1;                                                                   \n\
                                                                                                                \n\
        if (triFanBaseIdx != triFanBaseIdxCurr) {    // Restart the triangle fan                                \n\
            triFanIdxIdx = triFanBaseIdx + 2;                                                                   \n\
        } else {                                                                                                \n\
            // Provoking vertex is 1 in triangle fan but 0 in triangle list                                     \n\
            triIdxs[triIdxIdx++] = triIdx1;                                                                     \n\
            triIdxs[triIdxIdx++] = triIdx2;                                                                     \n\
            triIdxs[triIdxIdx++] = triIdx0;                                                                     \n\
            triFanIdxIdx++;                                                                                     \n\
        }                                                                                                       \n\
    }                                                                                                           \n\
}                                                                                                               \n\
																												\n\
kernel void cmdDrawIndirectPopulateIndexes(const device char* srcBuff [[buffer(0)]],                            \n\
                                           device MTLDrawIndexedPrimitivesIndirectArguments* destBuff [[buffer(1)]],\n\
                                           constant uint32_t& srcStride [[buffer(2)]],                          \n\
                                           constant uint32_t& drawCount [[buffer(3)]],                          \n\
										   device uint32_t* idxBuff [[buffer(4)]],                              \n\
                                           uint idx [[thread_position_in_grid]]) {                              \n\
    if (idx >= drawCount) { return; }                                                                           \n\
    const device auto& src = *reinterpret_cast<const device MTLDrawPrimitivesIndirectArguments*>(srcBuff + idx * srcStride);\n\
	device auto& dst = destBuff[idx];                                                                           \n\
    dst.indexCount = src.vertexCount;                                                                           \n\
	dst.indexStart = src.vertexStart;                                                                           \n\
	dst.baseVertex = 0;                                                                                         \n\
	dst.instanceCount = src.instanceCount;                                                                      \n\
	dst.baseInstance = src.baseInstance;                                                                        \n\
																												\n\
    for (uint32_t idxIdx = 0; idxIdx < dst.indexCount; idxIdx++) {                                              \n\
		uint32_t idxBuffIdx = dst.indexStart + idxIdx;															\n\
		idxBuff[idxBuffIdx] = idxBuffIdx;                                                                       \n\
    }                                                                                                           \n\
}                                                                                                               \n\
																												\n\
kernel void cmdDrawIndirectConvertBuffers(const device char* srcBuff [[buffer(0)]],                             \n\
                                          device MTLDrawPrimitivesIndirectArguments* destBuff [[buffer(1)]],    \n\
                                          constant uint32_t& srcStride [[buffer(2)]],                           \n\
                                          constant uint32_t& drawCount [[buffer(3)]],                           \n\
                                          constant uint32_t& viewCount [[buffer(4)]],                           \n\
                                          uint idx [[thread_position_in_grid]]) {                               \n\
    if (idx >= drawCount) { return; }                                                                           \n\
    const device auto& src = *reinterpret_cast<const device MTLDrawPrimitivesIndirectArguments*>(srcBuff + idx * srcStride);\n\
    destBuff[idx] = src;                                                                                        \n\
    destBuff[idx].instanceCount *= viewCount;                                                                   \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdDrawIndexedIndirectConvertBuffers(const device char* srcBuff [[buffer(0)]],                      \n\
                                                 device MTLDrawIndexedPrimitivesIndirectArguments* destBuff [[buffer(1)]],\n\
                                                 constant uint32_t& srcStride [[buffer(2)]],                    \n\
                                                 constant uint32_t& drawCount [[buffer(3)]],                    \n\
                                                 constant uint32_t& viewCount [[buffer(4)]],                    \n\
                                                 constant MVKVtxAdj& vtxAdj [[buffer(5)]],                      \n\
                                                 device void* triIdxs [[buffer(6)]],                            \n\
                                                 constant void* triFanIdxs [[buffer(7)]],                       \n\
                                                 uint idx [[thread_position_in_grid]]) {                        \n\
    if (idx >= drawCount) { return; }                                                                           \n\
    const device auto& src = *reinterpret_cast<const device MTLDrawIndexedPrimitivesIndirectArguments*>(srcBuff + idx * srcStride);\n\
    destBuff[idx] = src;                                                                                        \n\
																												\n\
    device auto& dst = destBuff[idx];                                                                           \n\
	if (vtxAdj.isMultiView) {                                                                                   \n\
		dst.instanceCount *= viewCount;                                                                         \n\
	}                                                                                                           \n\
    if (vtxAdj.isTriFan) {                                                                                      \n\
	    dst.indexCount = (src.indexCount - 2) * 3;                                                              \n\
        switch (vtxAdj.idxType) {                                                                               \n\
            case MTLIndexTypeUInt16:                                                                            \n\
                populateTriIndxsFromTriFan(&((device uint16_t*)triIdxs)[dst.indexStart],                        \n\
                                           &((constant uint16_t*)triFanIdxs)[src.indexStart],                   \n\
                                           src.indexCount);                                                     \n\
                break;                                                                                          \n\
            case MTLIndexTypeUInt32:                                                                            \n\
                populateTriIndxsFromTriFan(&((device uint32_t*)triIdxs)[dst.indexStart],                        \n\
                                           &((constant uint32_t*)triFanIdxs)[src.indexStart],                   \n\
                                           src.indexCount);                                                     \n\
                break;                                                                                          \n\
        }                                                                                                       \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
#if __METAL_VERSION__ >= 120                                                                                    \n\
kernel void cmdDrawIndirectTessConvertBuffers(const device char* srcBuff [[buffer(0)]],                         \n\
                                              device char* destBuff [[buffer(1)]],                              \n\
                                              device char* paramsBuff [[buffer(2)]],                            \n\
                                              constant uint32_t& srcStride [[buffer(3)]],                       \n\
                                              constant uint32_t& inControlPointCount [[buffer(4)]],             \n\
                                              constant uint32_t& outControlPointCount [[buffer(5)]],            \n\
                                              constant uint32_t& drawCount [[buffer(6)]],                       \n\
                                              constant uint32_t& vtxThreadExecWidth [[buffer(7)]],              \n\
                                              constant uint32_t& tcWorkgroupSize [[buffer(8)]],                 \n\
                                              uint idx [[thread_position_in_grid]]) {                           \n\
    if (idx >= drawCount) { return; }                                                                           \n\
    const device auto& src = *reinterpret_cast<const device MTLDrawPrimitivesIndirectArguments*>(srcBuff + idx * srcStride);\n\
    device char* dest;                                                                                          \n\
    device auto* params = reinterpret_cast<device uint32_t*>(paramsBuff + idx * 256);                           \n\
#if __METAL_VERSION__ >= 210                                                                                    \n\
    dest = destBuff + idx * (sizeof(MTLStageInRegionIndirectArguments) + sizeof(MTLDispatchThreadgroupsIndirectArguments) * 2 + sizeof(MTLDrawPatchIndirectArguments));\n\
    device auto& destSI = *(device MTLStageInRegionIndirectArguments*)dest;                                     \n\
    dest += sizeof(MTLStageInRegionIndirectArguments);                                                          \n\
#else                                                                                                           \n\
    dest = destBuff + idx * (sizeof(MTLDispatchThreadgroupsIndirectArguments) * 2 + sizeof(MTLDrawPatchIndirectArguments));\n\
#endif                                                                                                          \n\
    device auto& destVtx = *(device MTLDispatchThreadgroupsIndirectArguments*)dest;                             \n\
    device auto& destTC = *(device MTLDispatchThreadgroupsIndirectArguments*)(dest + sizeof(MTLDispatchThreadgroupsIndirectArguments));\n\
    device auto& destTE = *(device MTLDrawPatchIndirectArguments*)(dest + sizeof(MTLDispatchThreadgroupsIndirectArguments) * 2);\n\
    uint32_t patchCount = (src.vertexCount * src.instanceCount + inControlPointCount - 1) / inControlPointCount;\n\
    params[0] = inControlPointCount;                                                                            \n\
    params[1] = patchCount;                                                                                     \n\
    destVtx.threadgroupsPerGrid[0] = (src.vertexCount + vtxThreadExecWidth - 1) / vtxThreadExecWidth;           \n\
    destVtx.threadgroupsPerGrid[1] = src.instanceCount;                                                         \n\
    destVtx.threadgroupsPerGrid[2] = 1;                                                                         \n\
    destTC.threadgroupsPerGrid[0] = (patchCount * outControlPointCount + tcWorkgroupSize - 1) / tcWorkgroupSize;\n\
    destTC.threadgroupsPerGrid[1] = destTC.threadgroupsPerGrid[2] = 1;                                          \n\
    destTE.patchCount = patchCount;                                                                             \n\
    destTE.instanceCount = 1;                                                                                   \n\
    destTE.patchStart = destTE.baseInstance = 0;                                                                \n\
#if __METAL_VERSION__ >= 210                                                                                    \n\
    destSI.stageInOrigin[0] = src.vertexStart;                                                                  \n\
    destSI.stageInOrigin[1] = src.baseInstance;                                                                 \n\
    destSI.stageInOrigin[2] = 0;                                                                                \n\
    destSI.stageInSize[0] = src.vertexCount;                                                                    \n\
    destSI.stageInSize[1] = src.instanceCount;                                                                  \n\
    destSI.stageInSize[2] = 1;                                                                                  \n\
#endif                                                                                                          \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdDrawIndexedIndirectTessConvertBuffers(const device char* srcBuff [[buffer(0)]],                  \n\
                                                     device char* destBuff [[buffer(1)]],                       \n\
                                                     device char* paramsBuff [[buffer(2)]],                     \n\
                                                     constant uint32_t& srcStride [[buffer(3)]],                \n\
                                                     constant uint32_t& inControlPointCount [[buffer(4)]],      \n\
                                                     constant uint32_t& outControlPointCount [[buffer(5)]],     \n\
                                                     constant uint32_t& drawCount [[buffer(6)]],                \n\
                                                     constant uint32_t& vtxThreadExecWidth [[buffer(7)]],       \n\
                                                     constant uint32_t& tcWorkgroupSize [[buffer(8)]],          \n\
                                                     uint idx [[thread_position_in_grid]]) {                    \n\
    if (idx >= drawCount) { return; }                                                                           \n\
    const device auto& src = *reinterpret_cast<const device MTLDrawIndexedPrimitivesIndirectArguments*>(srcBuff + idx * srcStride);\n\
    device char* dest;                                                                                          \n\
    device auto* params = reinterpret_cast<device uint32_t*>(paramsBuff + idx * 256);                           \n\
#if __METAL_VERSION__ >= 210                                                                                    \n\
    dest = destBuff + idx * (sizeof(MTLStageInRegionIndirectArguments) + sizeof(MTLDispatchThreadgroupsIndirectArguments) * 2 + sizeof(MTLDrawPatchIndirectArguments));\n\
    device auto& destSI = *(device MTLStageInRegionIndirectArguments*)dest;                                     \n\
    dest += sizeof(MTLStageInRegionIndirectArguments);                                                          \n\
#else                                                                                                           \n\
    dest = destBuff + idx * (sizeof(MTLDispatchThreadgroupsIndirectArguments) * 2 + sizeof(MTLDrawPatchIndirectArguments));\n\
#endif                                                                                                          \n\
    device auto& destVtx = *(device MTLDispatchThreadgroupsIndirectArguments*)dest;                             \n\
    device auto& destTC = *(device MTLDispatchThreadgroupsIndirectArguments*)(dest + sizeof(MTLDispatchThreadgroupsIndirectArguments));\n\
    device auto& destTE = *(device MTLDrawPatchIndirectArguments*)(dest + sizeof(MTLDispatchThreadgroupsIndirectArguments) * 2);\n\
    uint32_t patchCount = (src.indexCount * src.instanceCount + inControlPointCount - 1) / inControlPointCount;\n\
    params[0] = inControlPointCount;                                                                            \n\
    params[1] = patchCount;                                                                                     \n\
    destVtx.threadgroupsPerGrid[0] = (src.indexCount + vtxThreadExecWidth - 1) / vtxThreadExecWidth;            \n\
    destVtx.threadgroupsPerGrid[1] = src.instanceCount;                                                         \n\
    destVtx.threadgroupsPerGrid[2] = 1;                                                                         \n\
    destTC.threadgroupsPerGrid[0] = (patchCount * outControlPointCount + tcWorkgroupSize - 1) / tcWorkgroupSize;\n\
    destTC.threadgroupsPerGrid[1] = destTC.threadgroupsPerGrid[2] = 1;                                          \n\
    destTE.patchCount = patchCount;                                                                             \n\
    destTE.instanceCount = 1;                                                                                   \n\
    destTE.patchStart = destTE.baseInstance = 0;                                                                \n\
#if __METAL_VERSION__ >= 210                                                                                    \n\
    destSI.stageInOrigin[0] = src.baseVertex;                                                                   \n\
    destSI.stageInOrigin[1] = src.baseInstance;                                                                 \n\
    destSI.stageInOrigin[2] = 0;                                                                                \n\
    destSI.stageInSize[0] = src.indexCount;                                                                     \n\
    destSI.stageInSize[1] = src.instanceCount;                                                                  \n\
    destSI.stageInSize[2] = 1;                                                                                  \n\
#endif                                                                                                          \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdDrawIndexedCopyIndex16Buffer(const device uint16_t* srcBuff [[buffer(0)]],                       \n\
                                            device uint16_t* destBuff [[buffer(1)]],                            \n\
                                            const device MTLDrawIndexedPrimitivesIndirectArguments& params [[buffer(2)]],\n\
                                            uint i [[thread_position_in_grid]]) {                               \n\
    destBuff[i] = srcBuff[params.indexStart + i];                                                               \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdDrawIndexedCopyIndex32Buffer(const device uint32_t* srcBuff [[buffer(0)]],                       \n\
                                            device uint32_t* destBuff [[buffer(1)]],                            \n\
                                            const device MTLDrawIndexedPrimitivesIndirectArguments& params [[buffer(2)]],\n\
                                            uint i [[thread_position_in_grid]]) {                               \n\
    destBuff[i] = srcBuff[params.indexStart + i];                                                               \n\
}                                                                                                               \n\
                                                                                                                \n\
#endif                                                                                                          \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    uint32_t count;                                                                                             \n\
    uint32_t countHigh;                                                                                         \n\
} VisibilityBuffer;                                                                                             \n\
                                                                                                                \n\
typedef enum {                                                                                                  \n\
    Initial,                                                                                                    \n\
    DeviceAvailable,                                                                                            \n\
    Available                                                                                                   \n\
} QueryStatus;                                                                                                  \n\
                                                                                                                \n\
typedef enum {                                                                                                  \n\
    VK_QUERY_RESULT_64_BIT                = 0x00000001,                                                         \n\
    VK_QUERY_RESULT_WAIT_BIT              = 0x00000002,                                                         \n\
    VK_QUERY_RESULT_WITH_AVAILABILITY_BIT = 0x00000004,                                                         \n\
    VK_QUERY_RESULT_PARTIAL_BIT           = 0x00000008,                                                         \n\
} VkQueryResultFlagBits;                                                                                        \n\
                                                                                                                \n\
kernel void cmdCopyQueryPoolResultsToBuffer(const device VisibilityBuffer* src [[buffer(0)]],                   \n\
                                            device uint8_t* dest [[buffer(1)]],                                 \n\
                                            constant uint& stride [[buffer(2)]],                                \n\
                                            constant uint& numQueries [[buffer(3)]],                            \n\
                                            constant uint& flags [[buffer(4)]],                                 \n\
                                            constant QueryStatus* availability [[buffer(5)]],                   \n\
                                            uint query [[thread_position_in_grid]]) {                           \n\
    if (query >= numQueries) { return; }                                                                        \n\
    device uint32_t* destCount = (device uint32_t*)(dest + stride * query);                                     \n\
    if (availability[query] != Initial || flags & VK_QUERY_RESULT_PARTIAL_BIT) {                                \n\
        destCount[0] = src[query].count;                                                                        \n\
        if (flags & VK_QUERY_RESULT_64_BIT) { destCount[1] = src[query].countHigh; }                            \n\
    }                                                                                                           \n\
    if (flags & VK_QUERY_RESULT_WITH_AVAILABILITY_BIT) {                                                        \n\
        if (flags & VK_QUERY_RESULT_64_BIT) {                                                                   \n\
            destCount[2] = availability[query] != Initial ? 1 : 0;                                              \n\
            destCount[3] = 0;                                                                                   \n\
        } else {                                                                                                \n\
            destCount[1] = availability[query] != Initial ? 1 : 0;                                              \n\
        }                                                                                                       \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void accumulateOcclusionQueryResults(device VisibilityBuffer& dest [[buffer(0)]],                        \n\
                                            const device VisibilityBuffer& src [[buffer(1)]]) {                 \n\
    uint32_t oldDestCount = dest.count;                                                                         \n\
    dest.count += src.count;                                                                                    \n\
    dest.countHigh += src.countHigh;                                                                            \n\
    if (dest.count < max(oldDestCount, src.count)) { dest.countHigh++; }                                        \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void convertUint8Indices(device uint8_t* src [[ buffer(0) ]],                                            \n\
                                device uint16_t* dst [[ buffer(1) ]],                                           \n\
                                uint pos [[thread_position_in_grid]]) {                                         \n\
    uint8_t idx = src[pos];                                                                                     \n\
    dst[pos] = idx == 0xFF ? 0xFFFF : idx;                                                                      \n\
}                                                                                                               \n\
                                                                                                                \n\
";

