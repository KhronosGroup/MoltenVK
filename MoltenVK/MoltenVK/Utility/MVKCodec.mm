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

#import <Foundation/Foundation.h>

using namespace std;


#pragma mark -
#pragma mark Support functions

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
