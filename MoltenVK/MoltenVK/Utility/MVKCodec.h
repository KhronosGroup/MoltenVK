/*
 * MVKCodec.h
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


#pragma once

#include "MVKEnvironment.h"
#include <vector>
#include <string>


#pragma mark -
#pragma mark Texture data codecs

/**
 * This is the base class implemented by all codecs supported by MoltenVK.
 * Objects of this class are used to decompress texture data for upload to a 3D texture.
 */
class MVKCodec {

public:

	/** Decompresses compressed texture data for upload. */
	virtual void decompress(void* pDest, const void* pSrc, const VkSubresourceLayout& destLayout, const VkSubresourceLayout& srcLayout, VkExtent3D extent) = 0;

	/** Destructor. */
	virtual ~MVKCodec() = default;

};


#pragma mark -
#pragma mark General data compressor

/**
 * Holds compressed data, along with information allowing it to be decompressed again.
 * The template class C must support the basic data container methods data(), size() and resize().
 *
 * THIS CLASS IS STREAMED OUT AS PART OF THE PIEPLINE CACHE.
 * STURCTURAL CHANGES TO THIS CLASS MUST BE CAPTURED IN THE STREAMING LOGIC OF THE PIPELINE CACHE.
 */
template <class C>
class MVKCompressor {

public:

	/**
	 * Compresses the content in the data container using the algorithm, and retains
	 * the compressed content. If an error occurs, or if the compressed data is actually
	 * larger (which can happen with some compression algorithms if the source is small),
	 * the uncompressed content is retained. Returns true if the content was successfully
	 * compressed, or returns false if the content was retained as uncompressed,
	 */
	bool compress(const C& uncompressed, MVKConfigCompressionAlgorithm algorithm) {

		_uncompressedSize = uncompressed.size();
		_compressed.resize(_uncompressedSize);
		_algorithm = algorithm;
		size_t compSize = mvkCompress((uint8_t*)uncompressed.data(), uncompressed.size(),
									  _compressed.data(), _compressed.size(),
									  _algorithm);

		bool wasCompressed = (compSize > 0);
		if ( !wasCompressed ) {
			_algorithm = MVK_CONFIG_COMPRESSION_ALGORITHM_NONE;
			compSize = mvkCompress((uint8_t*)uncompressed.data(), uncompressed.size(),
								   _compressed.data(), _compressed.size(),
								   _algorithm);
		}

		_compressed.resize(compSize);
		_compressed.shrink_to_fit();

		return wasCompressed;
	}

	/** Decompress the retained compressed content into the data container. */
	void decompress(C& uncompressed) {
		uncompressed.resize(_uncompressedSize);
		mvkDecompress(_compressed.data(), _compressed.size(),
					  (uint8_t*)uncompressed.data(), uncompressed.size(),
					  _algorithm);
	}

	std::vector<uint8_t> _compressed;
	size_t _uncompressedSize = 0;
	MVKConfigCompressionAlgorithm _algorithm = MVK_CONFIG_COMPRESSION_ALGORITHM_NONE;
};


#pragma mark -
#pragma mark Support functions

/** Returns an appropriate codec for the given format, or nullptr if the format is not supported. */
std::unique_ptr<MVKCodec> mvkCreateCodec(VkFormat format);

/** Returns whether or not the given format can be decompressed. */
bool mvkCanDecodeFormat(VkFormat format);

/**
 * Compresses the source bytes into the destination bytes using a compression algorithm,
 * and returns the number of bytes written to dstBytes. If an error occurs, or the compressed
 * data is larger than dstSize, no data is copied to dstBytes, and zero is returned.
 */
size_t mvkCompress(const uint8_t* srcBytes, size_t srcSize,
				   uint8_t* dstBytes, size_t dstSize,
				   MVKConfigCompressionAlgorithm compAlgo);

/**
 * Decompresses the source bytes into the destination bytes using a compression algorithm,
 * and returns the number of bytes written to dstBytes. If an error occurs, or the decompressed
 * data is larger than dstSize, no data is copied to dstBytes, and zero is returned.
 */
size_t mvkDecompress(const uint8_t* srcBytes, size_t srcSize,
					 uint8_t* dstBytes, size_t dstSize,
					 MVKConfigCompressionAlgorithm compAlgo);
