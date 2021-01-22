/*
 * MVKVulkanAPIObject.h
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKBaseObject.h"
#include <vulkan/vk_icd.h>
#include <string>
#include <atomic>

#import <Foundation/NSString.h>

class MVKInstance;


#pragma mark -
#pragma mark MVKVulkanAPIObject

/**
 * Abstract class that represents an opaque Vulkan API handle object.
 *
 * API objects can sometimes be destroyed by the client before the GPU is done with them.
 * To support this, an object of this type will automatically be deleted iff it has been
 * destroyed by the client, and all references have been released. An object of this type
 * is therefore allowed to live past its destruction by the client, until it is no longer
 * referenced by other objects.
 */
class MVKVulkanAPIObject : public MVKConfigurableObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return this; };

	/** Returns a reference to this object suitable for use as a Vulkan API handle. */
	virtual void* getVkHandle() { return this; }

	/** Returns the Vulkan type of this object. */
	virtual VkObjectType getVkObjectType() = 0;

	/** Returns the debug report object type of this object. */
	virtual VkDebugReportObjectTypeEXT getVkDebugReportObjectType() = 0;

	/** Returns the Vulkan instance. */
	virtual MVKInstance* getInstance() = 0;

	/**
	 * Called when this instance has been retained as a reference by another object,
	 * indicating that this instance will not be deleted until that reference is released.
	 */
	inline void retain() { _refCount++; }

	/**
	 * Called when this instance has been released as a reference from another object.
	 * Once all references have been released, this object is free to be deleted.
	 * If the destroy() function has already been called on this instance by the time
	 * this function is called, this instance will be deleted.
	 */
	inline void release() { if (--_refCount == 0) { MVKConfigurableObject::destroy(); } }

	/**
	 * Marks this instance as destroyed. If all previous references to this instance
	 * have been released, this instance will be deleted, otherwise deletion of this
	 * instance will automatically be deferred until all references have been released.
	 */
	void destroy() override { release(); }

	/** Gets the debug object name of this instance. */
	inline NSString* getDebugName() { return _debugName; }

	/** Sets the debug object name of this instance. */
	VkResult setDebugName(const char* pObjectName);

	/** Returns the MVKVulkanAPIObject instance referenced by the object of the given type. */
	static MVKVulkanAPIObject* getMVKVulkanAPIObject(VkDebugReportObjectTypeEXT objType, uint64_t object);

	/** Returns the MVKVulkanAPIObject instance referenced by the object of the given type. */
	static MVKVulkanAPIObject* getMVKVulkanAPIObject(VkObjectType objType, uint64_t objectHandle);

	/** Construct an empty instance. Declared here to support copy constructor. */
	MVKVulkanAPIObject() : _refCount(1) {}

	/** Default copy constructor disallowed due to mutex. Copy starts with fresh reference counts. */
	MVKVulkanAPIObject(const MVKVulkanAPIObject& other) : _refCount(1) {}

	~MVKVulkanAPIObject() override;

protected:
	virtual void propagateDebugName() = 0;

	std::atomic<uint32_t> _refCount;
	NSString* _debugName = nil;
};


#pragma mark -
#pragma mark MVKDispatchableVulkanAPIObject

/** Abstract class that represents a dispatchable opaque Vulkan API handle object. */
class MVKDispatchableVulkanAPIObject : public MVKVulkanAPIObject {

    typedef struct {
        VK_LOADER_DATA loaderData;
        MVKDispatchableVulkanAPIObject* mvkObject;
    } MVKDispatchableObjectICDRef;

public:

    /**
     * Returns a reference to this object suitable for use as a dispatchable Vulkan API handle.
	 *
	 * Establishes the loader magic number every time, in case the loader
	 * overwrote it for some reason before passing the object back,
	 * particularly in pooled objects that the loader might consider freed.
	 *
	 * This is the compliment of the getDispatchableObject() function.
     */
    void* getVkHandle() override {
		set_loader_magic_value(&_icdRef);
		return &_icdRef;
	}

    /**
     * Retrieves the MVKDispatchableVulkanAPIObject instance referenced by the dispatchable Vulkan handle.
	 *
     * This is the compliment of the getVkHandle() function.
     */
    static inline MVKDispatchableVulkanAPIObject* getDispatchableObject(void* vkHandle) {
		return vkHandle ? ((MVKDispatchableObjectICDRef*)vkHandle)->mvkObject : nullptr;
    }

protected:
    MVKDispatchableObjectICDRef _icdRef = { VK_NULL_HANDLE, this };

};

#pragma mark -
#pragma mark Support functions

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-method-access"
/** Generically avoids setting a label to nil, which many objects don't like. */
static inline void setLabelIfNotNil(id object, NSString* label) { if (label) { [object setLabel: label]; } }
#pragma clang diagnostic pop


