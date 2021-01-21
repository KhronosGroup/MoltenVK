/*
 * MVKCodec.cpp
 *
 * Copyright (c) 2018-2021 Chip Davis for CodeWeavers
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


#include "MVKCodec.h"

#include <algorithm>
#include <simd/simd.h>


using simd::float3;
using simd::float4;
using simd::pow;
using simd::select;

static uint32_t pack_float_to_unorm4x8(float4 x) {
	return ((((uint8_t)(x.r * 255)) & 0x000000ff) | ((((uint8_t)(x.g * 255)) << 8) & 0x0000ff00) |
		((((uint8_t)(x.b * 255)) & 0x00ff0000) << 16) | ((((uint8_t)(x.a * 255)) << 24) & 0xff000000));
}

static float3 unpack_unorm565_to_float(uint16_t x) {
	return simd::make_float3(((x >> 11) & 0x1f) / 31.0f, ((x >> 5) & 0x3f) / 63.0f, (x & 0x1f) / 31.0f);
}


/** Texture codec for DXTn (i.e. BC[1-3]) compressed data.
 *
 * This implementation is largely derived from Wine, from code originally
 * written by Connor McAdams.
 */
class MVKDXTnCodec : public MVKCodec {

public:

	void decompress(void* pDest, const void* pSrc, const VkSubresourceLayout& destLayout, const VkSubresourceLayout& srcLayout, VkExtent3D extent) override {
		VkDeviceSize blockByteCount;
		const uint8_t* pSrcRow;
		const uint8_t* pSrcSlice = (const uint8_t*)pSrc;
		uint8_t* pDestRow;
		uint8_t* pDestSlice = (uint8_t*)pDest;

		blockByteCount = isBC1Format(_format) ? 8 : 16;

		for (uint32_t z = 0; z < extent.depth; ++z) {
			pSrcRow = pSrcSlice;
			pDestRow = pDestSlice;
			for (uint32_t y = 0; y < extent.height; y += 4) {
				for (uint32_t x = 0; x < extent.width; x += 4) {
					VkExtent2D blockExtent;
					blockExtent.width = std::min(extent.width - x, 4u);
					blockExtent.height = std::min(extent.height - y, 4u);
					decompressDXTnBlock(pSrcRow + x * (blockByteCount / 4),
						pDestRow + x * 4, blockExtent, destLayout.rowPitch, _format);
				}
				pSrcRow += srcLayout.rowPitch;
				pDestRow += destLayout.rowPitch * 4;
			}
			pSrcSlice += srcLayout.depthPitch;
			pDestSlice += destLayout.depthPitch;
		}
	}

	/** Constructs an instance. */
	MVKDXTnCodec(VkFormat format) : _format(format) {}

private:

#define constant const
#define device
#define thread
#define MVK_DECOMPRESS_CODE(...) __VA_ARGS__
#include "MVKDXTnCodec.def"
#undef MVK_DECOMPRESS_CODE

	VkFormat _format;
};

std::unique_ptr<MVKCodec> mvkCreateCodec(VkFormat format) {
	switch (format) {
	case VK_FORMAT_BC1_RGB_UNORM_BLOCK:
	case VK_FORMAT_BC1_RGB_SRGB_BLOCK:
	case VK_FORMAT_BC1_RGBA_UNORM_BLOCK:
	case VK_FORMAT_BC1_RGBA_SRGB_BLOCK:
	case VK_FORMAT_BC2_UNORM_BLOCK:
	case VK_FORMAT_BC2_SRGB_BLOCK:
	case VK_FORMAT_BC3_UNORM_BLOCK:
	case VK_FORMAT_BC3_SRGB_BLOCK:
		return std::unique_ptr<MVKCodec>(new MVKDXTnCodec(format));

	default:
		return nullptr;
	}
}

bool mvkCanDecodeFormat(VkFormat format) {
	switch (format) {
	case VK_FORMAT_BC1_RGB_UNORM_BLOCK:
	case VK_FORMAT_BC1_RGB_SRGB_BLOCK:
	case VK_FORMAT_BC1_RGBA_UNORM_BLOCK:
	case VK_FORMAT_BC1_RGBA_SRGB_BLOCK:
	case VK_FORMAT_BC2_UNORM_BLOCK:
	case VK_FORMAT_BC2_SRGB_BLOCK:
	case VK_FORMAT_BC3_UNORM_BLOCK:
	case VK_FORMAT_BC3_SRGB_BLOCK:
		return true;

	default:
		return false;
	}
}
