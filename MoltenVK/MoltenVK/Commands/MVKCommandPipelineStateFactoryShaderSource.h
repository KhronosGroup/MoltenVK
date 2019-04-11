/*
 * MVKCommandPipelineStateFactoryShaderSource.h
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
    float2 a_texCoord [[attribute(1)]];                                                                         \n\
} AttributesPosTex;                                                                                             \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    float4 v_position [[position]];                                                                             \n\
    float2 v_texCoord;                                                                                          \n\
} VaryingsPosTex;                                                                                               \n\
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
};                                                                                                              \n\
                                                                                                                \n\
typedef struct {                                                                                                \n\
    uint32_t size;                                                                                              \n\
    uint32_t data;                                                                                              \n\
} FillInfo;                                                                                                     \n\
                                                                                                                \n\
kernel void cmdFillBuffer(device uint32_t* dst [[ buffer(0) ]],                                                 \n\
                          constant FillInfo& info [[ buffer(1) ]]) {                                            \n\
    for (uint32_t i = 0; i < info.size; i++) {                                                                  \n\
        dst[i] = info.data;                                                                                     \n\
    }                                                                                                           \n\
};                                                                                                              \n\
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
kernel void cmdCopyBufferToImage3DDecompressDXTn(constant uint8_t* src [[buffer(0)]],                           \n\
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
kernel void cmdCopyBufferToImage3DDecompressTempBufferDXTn(constant uint8_t* src [[buffer(0)]],                 \n\
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
#if __METAL_VERSION__ == 210                                                                                    \n\
// This structure is missing from the MSL headers. :/                                                           \n\
struct MTLStageInRegionIndirectArguments {                                                                      \n\
    uint32_t stageInOrigin[3];                                                                                  \n\
    uint32_t stageInSize[3];                                                                                    \n\
};                                                                                                              \n\
#endif                                                                                                          \n\
                                                                                                                \n\
#if __METAL_VERSION__ >= 120                                                                                    \n\
kernel void cmdDrawIndirectConvertBuffers(const device char* srcBuff [[buffer(0)]],                             \n\
                                          device char* destBuff [[buffer(1)]],                                  \n\
                                          constant uint32_t& srcStride [[buffer(2)]],                           \n\
                                          constant uint32_t& inControlPointCount [[buffer(3)]],                 \n\
                                          constant uint32_t& outControlPointCount [[buffer(4)]],                \n\
                                          constant uint32_t& drawCount [[buffer(5)]],                           \n\
                                          uint idx [[thread_position_in_grid]]) {                               \n\
    if (idx >= drawCount) { return; }                                                                           \n\
    const device auto& src = *reinterpret_cast<const device MTLDrawPrimitivesIndirectArguments*>(srcBuff + idx * srcStride);\n\
    device char* dest = destBuff + idx * (sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments));\n\
#if __METAL_VERSION__ >= 210                                                                                    \n\
    device auto& destSI = *(device MTLStageInRegionIndirectArguments*)dest;                                     \n\
    dest += sizeof(MTLStageInRegionIndirectArguments);                                                          \n\
#endif                                                                                                          \n\
    device auto& destTC = *(device MTLDispatchThreadgroupsIndirectArguments*)dest;                              \n\
    device auto& destTE = *(device MTLDrawPatchIndirectArguments*)(dest + sizeof(MTLDispatchThreadgroupsIndirectArguments));\n\
    destTC.threadgroupsPerGrid[0] = (src.vertexCount * src.instanceCount + inControlPointCount - 1) / inControlPointCount;\n\
    destTC.threadgroupsPerGrid[1] = destTC.threadgroupsPerGrid[2] = 1;                                          \n\
    destTE.patchCount = destTC.threadgroupsPerGrid[0];                                                          \n\
    destTE.instanceCount = 1;                                                                                   \n\
    destTE.patchStart = destTE.baseInstance = 0;                                                                \n\
#if __METAL_VERSION__ >= 210                                                                                    \n\
    destSI.stageInOrigin[0] = destSI.stageInOrigin[1] = destSI.stageInOrigin[2] = 0;                            \n\
    destSI.stageInSize[0] = src.instanceCount * max(src.vertexCount, outControlPointCount * destTE.patchCount); \n\
    destSI.stageInSize[1] = destSI.stageInSize[2] = 1;                                                          \n\
#endif                                                                                                          \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdDrawIndexedIndirectConvertBuffers(const device char* srcBuff [[buffer(0)]],                      \n\
                                                 device char* destBuff [[buffer(1)]],                           \n\
                                                 constant uint32_t& srcStride [[buffer(2)]],                    \n\
                                                 constant uint32_t& inControlPointCount [[buffer(3)]],          \n\
                                                 constant uint32_t& outControlPointCount [[buffer(4)]],         \n\
                                                 constant uint32_t& drawCount [[buffer(5)]],                    \n\
                                                 uint idx [[thread_position_in_grid]]) {                        \n\
    if (idx >= drawCount) { return; }                                                                           \n\
    const device auto& src = *reinterpret_cast<const device MTLDrawIndexedPrimitivesIndirectArguments*>(srcBuff + idx * srcStride);\n\
    device char* dest = destBuff + idx * (sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments));\n\
#if __METAL_VERSION__ >= 210                                                                                    \n\
    device auto& destSI = *(device MTLStageInRegionIndirectArguments*)dest;                                     \n\
    dest += sizeof(MTLStageInRegionIndirectArguments);                                                          \n\
#endif                                                                                                          \n\
    device auto& destTC = *(device MTLDispatchThreadgroupsIndirectArguments*)dest;                              \n\
    device auto& destTE = *(device MTLDrawPatchIndirectArguments*)(dest + sizeof(MTLDispatchThreadgroupsIndirectArguments));\n\
    destTC.threadgroupsPerGrid[0] = (src.indexCount * src.instanceCount + inControlPointCount - 1) / inControlPointCount;\n\
    destTC.threadgroupsPerGrid[1] = destTC.threadgroupsPerGrid[2] = 1;                                          \n\
    destTE.patchCount = destTC.threadgroupsPerGrid[0];                                                          \n\
    destTE.instanceCount = 1;                                                                                   \n\
    destTE.patchStart = destTE.baseInstance = 0;                                                                \n\
#if __METAL_VERSION__ >= 210                                                                                    \n\
    destSI.stageInOrigin[0] = destSI.stageInOrigin[1] = destSI.stageInOrigin[2] = 0;                            \n\
    destSI.stageInSize[0] = src.instanceCount * max(src.indexCount, outControlPointCount * destTE.patchCount); \n\
    destSI.stageInSize[1] = destSI.stageInSize[2] = 1;                                                          \n\
#endif                                                                                                          \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdDrawIndexedCopyIndex16Buffer(const device uint16_t* srcBuff [[buffer(0)]],                       \n\
                                            device uint16_t* destBuff [[buffer(1)]],                            \n\
                                            constant uint32_t& inControlPointCount [[buffer(2)]],               \n\
                                            constant uint32_t& outControlPointCount [[buffer(3)]],              \n\
                                            const device MTLDrawIndexedPrimitivesIndirectArguments& params [[buffer(4)]]) {\n\
    uint patchCount = (params.indexCount + inControlPointCount - 1) / inControlPointCount;                      \n\
    for (uint i = 0; i < params.instanceCount; i++) {                                                           \n\
        for (uint j = 0; j < patchCount; j++) {                                                                 \n\
            for (uint k = 0; k < max(inControlPointCount, outControlPointCount); k++) {                         \n\
                if (k < inControlPointCount) {                                                                  \n\
                    destBuff[i * params.indexCount + j * outControlPointCount + k] = srcBuff[params.indexStart + j * inControlPointCount + k] + i * params.indexCount;\n\
                } else {                                                                                        \n\
                    destBuff[i * params.indexCount + j * outControlPointCount + k] = 0;                         \n\
                }                                                                                               \n\
            }                                                                                                   \n\
        }                                                                                                       \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
kernel void cmdDrawIndexedCopyIndex32Buffer(const device uint32_t* srcBuff [[buffer(0)]],                       \n\
                                            device uint32_t* destBuff [[buffer(1)]],                            \n\
                                            constant uint32_t& inControlPointCount [[buffer(2)]],               \n\
                                            constant uint32_t& outControlPointCount [[buffer(3)]],              \n\
                                            const device MTLDrawIndexedPrimitivesIndirectArguments& params [[buffer(4)]]) {\n\
    uint patchCount = (params.indexCount + inControlPointCount - 1) / inControlPointCount;                      \n\
    for (uint i = 0; i < params.instanceCount; i++) {                                                           \n\
        for (uint j = 0; j < patchCount; j++) {                                                                 \n\
            for (uint k = 0; k < max(inControlPointCount, outControlPointCount); k++) {                         \n\
                if (k < inControlPointCount) {                                                                  \n\
                    destBuff[i * params.indexCount + j * outControlPointCount + k] = srcBuff[params.indexStart + j * inControlPointCount + k] + i * params.indexCount;\n\
                } else {                                                                                        \n\
                    destBuff[i * params.indexCount + j * outControlPointCount + k] = 0;                         \n\
                }                                                                                               \n\
            }                                                                                                   \n\
        }                                                                                                       \n\
    }                                                                                                           \n\
}                                                                                                               \n\
                                                                                                                \n\
#endif                                                                                                          \n\
                                                                                                                \n\
";

