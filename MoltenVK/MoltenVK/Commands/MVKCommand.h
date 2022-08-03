/*
 * MVKCommand.h
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#include "MVKObjectPool.h"
#include "MVKSmallVector.h"

class MVKCommandBuffer;
class MVKCommandEncoder;
class MVKCommandPool;


#pragma mark -
#pragma mark MVKCommandTypePool

/** A pool of MVKCommand instances of a particular type. */
template <class T>
class MVKCommandTypePool : public MVKObjectPool<T> {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; }

	MVKCommandTypePool(bool isPooling = true) : MVKObjectPool<T>(isPooling) {}

protected:
	T* newObject() override { return new T(); }

};


#pragma mark -
#pragma mark MVKCommand

/**
 * Abstract class that represents a Vulkan command.
 *
 * To allow command contents to be populated in a standard way, all concrete
 * subclasses must support a public member function of the following form:
 *
 *     VkResult setContent(MVKCommandBuffer* cmdBuff, ...);
 */
class MVKCommand : public MVKBaseObject, public MVKLinkableMixin<MVKCommand> {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; }

	/** Encodes this command on the specified command encoder. */
	virtual void encode(MVKCommandEncoder* cmdEncoder) = 0;

protected:
	friend MVKCommandBuffer;
};


void *mvkPushCommandMemory(MVKCommandBuffer *cmdBuffer, size_t size);

/**
 * Allocator for MVKCommandVector below.
 */
template <typename T>
class MVKCommandStorageAllocator {
public:
    typedef T value_type;
    MVKCommandBuffer *cmdBuffer        = nullptr;
    T                *ptr              = nullptr;
    size_t           num_elements_used = 0;
    size_t           capacity          = 0;

public:
    const T &operator[](const size_t i) const { return ptr[i]; }
    T       &operator[](const size_t i)       { return ptr[i]; }

    size_t size() const { return num_elements_used; }

    void swap(MVKCommandStorageAllocator &a) {
        auto copy = *this;
        *this = a;
        a = copy;
    }

    template<class S, class... Args> void construct(S *_ptr, Args&&... _args) {
        *_ptr = S(std::forward<Args>(_args)...);
    }

    template<class S> void destruct(S *_ptr) {}

    void allocate(const size_t num_elements_to_reserve) {
        ptr = (T *)mvkPushCommandMemory(cmdBuffer, num_elements_to_reserve * sizeof(T));
        num_elements_used = 0;
        capacity = num_elements_to_reserve;
    }

    void re_allocate(const size_t num_elements_to_reserve) {
        auto new_ptr = mvkPushCommandMemory(cmdBuffer, num_elements_to_reserve * sizeof(T));
        memcpy(new_ptr, ptr, num_elements_used * sizeof(T));
        ptr = (T *)new_ptr;
        capacity = num_elements_to_reserve;
    }

    void shrink_to_fit() {}

    void deallocate() {}

    size_t get_capacity() const { return capacity; }

    template<class S> void destruct_all() {
        num_elements_used = 0;
    }
};

#pragma mark -
#pragma mark MVKCommandVector

/**
 * Array for storing dynamic amounts of data in the command buffer.
 */
template<typename Type>
using MVKCommandVector = MVKSmallVectorImpl<Type, MVKCommandStorageAllocator<Type>>;
