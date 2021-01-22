/*
 * MVKCodec.h
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


#pragma once

#include "MVKFoundation.h"

#include <string>


#pragma mark Texture data codecs

/**
 * This is the base class implemented by all codecs supported by MoltenVK.
 * Objects of this class are used to decompress texture data for upload to a
 * 3D texture.
 */
class MVKCodec {

public:

	/** Decompresses compressed texture data for upload. */
	virtual void decompress(void* pDest, const void* pSrc, const VkSubresourceLayout& destLayout, const VkSubresourceLayout& srcLayout, VkExtent3D extent) = 0;

	/** Destructor. */
	virtual ~MVKCodec() = default;

};

/** Returns an appropriate codec for the given format, or nullptr if the format is not supported. */
std::unique_ptr<MVKCodec> mvkCreateCodec(VkFormat format);

/** Returns whether or not the given format can be decompressed. */
bool mvkCanDecodeFormat(VkFormat format);
