/*
 * MVKCodec.cpp
 *
 * Copyright (c) 2018-2025 Chip Davis for CodeWeavers
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
#include "MVKBaseObject.h"
#include "MVKFoundation.h"

#include <algorithm>
#include <simd/simd.h>

#import <Foundation/Foundation.h>

using namespace std;

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
					blockExtent.width = min(extent.width - x, 4u);
					blockExtent.height = min(extent.height - y, 4u);
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


#pragma mark -
#pragma mark Support functions

unique_ptr<MVKCodec> mvkCreateCodec(VkFormat format) {
	switch (format) {
	case VK_FORMAT_BC1_RGB_UNORM_BLOCK:
	case VK_FORMAT_BC1_RGB_SRGB_BLOCK:
	case VK_FORMAT_BC1_RGBA_UNORM_BLOCK:
	case VK_FORMAT_BC1_RGBA_SRGB_BLOCK:
	case VK_FORMAT_BC2_UNORM_BLOCK:
	case VK_FORMAT_BC2_SRGB_BLOCK:
	case VK_FORMAT_BC3_UNORM_BLOCK:
	case VK_FORMAT_BC3_SRGB_BLOCK:
		return unique_ptr<MVKCodec>(new MVKDXTnCodec(format));

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

static NSDataCompressionAlgorithm getSystemCompressionAlgo(MVKConfigCompressionAlgorithm compAlgo) {
	switch (compAlgo) {
		case MVK_CONFIG_COMPRESSION_ALGORITHM_NONE:     return NSDataCompressionAlgorithmLZFSE;
		case MVK_CONFIG_COMPRESSION_ALGORITHM_LZFSE:    return NSDataCompressionAlgorithmLZFSE;
		case MVK_CONFIG_COMPRESSION_ALGORITHM_LZ4:      return NSDataCompressionAlgorithmLZ4;
		case MVK_CONFIG_COMPRESSION_ALGORITHM_LZMA:     return NSDataCompressionAlgorithmLZMA;
		case MVK_CONFIG_COMPRESSION_ALGORITHM_ZLIB:     return NSDataCompressionAlgorithmZlib;
		default:                                        return NSDataCompressionAlgorithmLZFSE;
	}
}

// Only copy into the dstBytes if it can fit, otherwise the data will be corrupted
static size_t mvkCompressDecompress(const uint8_t* srcBytes, size_t srcSize,
									uint8_t* dstBytes, size_t dstSize,
									MVKConfigCompressionAlgorithm compAlgo,
									bool isCompressing) {
	size_t dstByteCount = 0;
	bool compressionSupported = ([NSData instancesRespondToSelector: @selector(compressedDataUsingAlgorithm:error:)] &&
								 [NSData instancesRespondToSelector: @selector(decompressedDataUsingAlgorithm:error:)]);
	if (compressionSupported && compAlgo != MVK_CONFIG_COMPRESSION_ALGORITHM_NONE) {
		@autoreleasepool {
			NSDataCompressionAlgorithm sysCompAlgo = getSystemCompressionAlgo(compAlgo);
			NSData* srcData = [NSData dataWithBytesNoCopy: (void*)srcBytes length: srcSize freeWhenDone: NO];

			NSError* err = nil;
			NSData* dstData = (isCompressing
							   ? [srcData compressedDataUsingAlgorithm: sysCompAlgo error: &err]
							   : [srcData decompressedDataUsingAlgorithm: sysCompAlgo error: &err]);
			if ( !err ) {
				size_t dataLen = dstData.length;
				if (dstSize >= dataLen) {
					[dstData getBytes: dstBytes length: dstSize];
					dstByteCount = dataLen;
				}
			} else {
				MVKBaseObject::reportError(nullptr, VK_ERROR_FORMAT_NOT_SUPPORTED,
										   "Could not %scompress data (Error code %li):\n%s",
										   (isCompressing ? "" : "de"),
										   (long)err.code, err.localizedDescription.UTF8String);
			}
		}
	} else if (dstSize >= srcSize) {
		mvkCopy(dstBytes, srcBytes, srcSize);
		dstByteCount = srcSize;
	}
	return dstByteCount;
}

size_t mvkCompress(const uint8_t* srcBytes, size_t srcSize,
				   uint8_t* dstBytes, size_t dstSize,
				   MVKConfigCompressionAlgorithm compAlgo) {

	return mvkCompressDecompress(srcBytes, srcSize, dstBytes, dstSize, compAlgo, true);
}

size_t mvkDecompress(const uint8_t* srcBytes, size_t srcSize,
					 uint8_t* dstBytes, size_t dstSize,
					 MVKConfigCompressionAlgorithm compAlgo) {

	return mvkCompressDecompress(srcBytes, srcSize, dstBytes, dstSize, compAlgo, false);
}
