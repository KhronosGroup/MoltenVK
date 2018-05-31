/*
 * MVKResource.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKDeviceMemory.h"

class MVKCommandEncoder;


#pragma mark -
#pragma mark MVKResource

/** Represents an abstract Vulkan resource. Specialized subclasses include MVKBuffer and MVKImage. */
class MVKResource : public MVKBaseDeviceObject {

public:

	/** Returns the number of bytes required for the entire resource. */
    inline VkDeviceSize getByteCount() { return _byteCount; }

    /** Returns the byte offset in the bound device memory. */
    inline VkDeviceSize getDeviceMemoryOffset() { return _deviceMemoryOffset; }

	/** Returns the memory requirements of this resource by populating the specified structure. */
	virtual VkResult getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements) = 0;

	/** Binds this resource to the specified offset within the specified memory allocation. */
	virtual VkResult bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset);

	/** Returns the device memory underlying this resource. */
	inline MVKDeviceMemory* getDeviceMemory() { return _deviceMemory; }

	/** Returns whether the memory is accessible from the host. */
	inline bool isMemoryHostAccessible() { return _deviceMemory && _deviceMemory->isMemoryHostAccessible(); }

	/** Returns whether the memory is automatically coherent between device and host. */
	inline bool isMemoryHostCoherent() { return _deviceMemory && _deviceMemory->isMemoryHostCoherent(); }

	/**
	 * Returns the host memory address of this resource, or NULL if the memory
	 * is marked as device-only and cannot be mapped to a host address.
	 */
	inline void* getHostMemoryAddress() {
		return (_deviceMemory ? (void*)((uintptr_t)_deviceMemory->getHostMemoryAddress() + _deviceMemoryOffset) : nullptr);
	}

	/** Applies the specified global memory barrier. */
	virtual void applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
									VkPipelineStageFlags dstStageMask,
									VkMemoryBarrier* pMemoryBarrier,
                                    MVKCommandEncoder* cmdEncoder,
                                    MVKCommandUse cmdUse) = 0;

	
#pragma mark Construction

	/** Constructs an instance for the specified device. */
    MVKResource(MVKDevice* device) : MVKBaseDeviceObject(device) {}

	/** Destructor. */
	~MVKResource() override;

protected:
	friend MVKDeviceMemory;
	
	virtual VkResult flushToDevice(VkDeviceSize offset, VkDeviceSize size) { return VK_SUCCESS; };
	virtual VkResult pullFromDevice(VkDeviceSize offset, VkDeviceSize size) { return VK_SUCCESS; };
	virtual bool needsHostReadSync(VkPipelineStageFlags srcStageMask,
								   VkPipelineStageFlags dstStageMask,
								   VkMemoryBarrier* pMemoryBarrier);

	MVKDeviceMemory* _deviceMemory = nullptr;
	VkDeviceSize _deviceMemoryOffset = 0;
    VkDeviceSize _byteCount = 0;
    VkDeviceSize _byteAlignment = 0;
	bool _isBuffer  = false;
};
