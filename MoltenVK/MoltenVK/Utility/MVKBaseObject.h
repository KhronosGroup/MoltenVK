/*
 * MVKBaseObject.h
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

#pragma once

#include "mvk_vulkan.h"
#include <vulkan/vk_icd.h>
#include <string>
#include <mutex>

class MVKInstance;
class MVKVulkanAPIObject;


#pragma mark -
#pragma mark MVKBaseObject

/** 
 * An abstract base class for all MoltenVK C++ classes, to allow common object
 * behaviour, and common custom allocation and deallocation behaviour.
 */
class MVKBaseObject {

public:

    /** Returns the name of the class of which this object is an instance. */
    std::string getClassName();

	/** Returns the Vulkan API opaque object controlling this object. */
	virtual MVKVulkanAPIObject* getVulkanAPIObject() = 0;

	/**
	 * Report a message. This includes logging to a standard system logging stream,
	 * and some subclasses will also forward the message to their VkInstance for
	 * output to the Vulkan debug report messaging API.
	 */
	void reportMessage(int aslLvl, const char* format, ...) __printflike(3, 4);

	/**
	 * Report a Vulkan error message, on behalf of the object, which may be nil.
	 * Reporting includes logging to a standard system logging stream, and if the object
	 * is not nil and has access to the VkInstance, the message will also be forwarded
	 * to the VkInstance for output to the Vulkan debug report messaging API.
	 */
	static void reportMessage(MVKBaseObject* mvkObj, int aslLvl, const char* format, ...) __printflike(3, 4);

	/**
	 * Report a Vulkan error message, on behalf of the object, which may be nil.
	 * Reporting includes logging to a standard system logging stream, and if the object
	 * is not nil and has access to the VkInstance, the message will also be forwarded
	 * to the VkInstance for output to the Vulkan debug report messaging API.
	 *
	 * This is the core reporting implementation. Other similar functions delegate here.
	 */
	static void reportMessage(MVKBaseObject* mvkObj, int aslLvl, const char* format, va_list args) __printflike(3, 0);

	/**
	 * Report a Vulkan error message. This includes logging to a standard system logging stream,
	 * and some subclasses will also forward the message to their VkInstance for output to the
	 * Vulkan debug report messaging API.
	 */
	VkResult reportError(VkResult vkErr, const char* format, ...) __printflike(3, 4);

	/**
	 * Report a Vulkan error message, on behalf of the object. which may be nil.
	 * Reporting includes logging to a standard system logging stream, and if the object
	 * is not nil and has access to the VkInstance, the message will also be forwarded
	 * to the VkInstance for output to the Vulkan debug report messaging API.
	 */
	static VkResult reportError(MVKBaseObject* mvkObj, VkResult vkErr, const char* format, ...) __printflike(3, 4);

	/**
	 * Report a Vulkan error message, on behalf of the object. which may be nil.
	 * Reporting includes logging to a standard system logging stream, and if the object
	 * is not nil and has access to the VkInstance, the message will also be forwarded
	 * to the VkInstance for output to the Vulkan debug report messaging API.
	 *
	 * This is the core reporting implementation. Other similar functions delegate here.
	 */
	static VkResult reportError(MVKBaseObject* mvkObj, VkResult vkErr, const char* format, va_list args) __printflike(3, 0);

	/** Destroys this object. Default behaviour simply deletes it. Subclasses may override to delay deletion. */
	virtual void destroy() { delete this; }

    virtual ~MVKBaseObject() {}
};


#pragma mark -
#pragma mark MVKConfigurableObject

/** 
 * Abstract class that represents an object whose configuration can be validated and tracked
 * as a queriable result. This is the base class of opaque Vulkan API objects, and commands.
 */
class MVKConfigurableObject : public MVKBaseObject {

public:

	/** Returns a indication of the success of the configuration of this instance. */
	inline VkResult getConfigurationResult() { return _configurationResult; }

	/** If the existing configuration result is VK_SUCCESS, it is set to the specified value. */
    inline void setConfigurationResult(VkResult vkResult) {
        if (_configurationResult == VK_SUCCESS) { _configurationResult = vkResult; }
    }

    /** Resets the indication of the success of the configuration of this instance back to VK_SUCCESS. */
    inline void clearConfigurationResult() { _configurationResult = VK_SUCCESS; }

protected:
	VkResult _configurationResult = VK_SUCCESS;
};


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

	/** Returns the debug report object type of this object. */
	virtual VkDebugReportObjectTypeEXT getVkDebugReportObjectType() = 0;

	/** Returns the Vulkan instance. */
	virtual MVKInstance* getInstance() = 0;

	/**
	 * Called when this instance has been retained as a reference by another object,
	 * indicating that this instance will not be deleted until that reference is released.
	 */
	void retain();

	/**
	 * Called when this instance has been released as a reference from another object.
	 * Once all references have been released, this object is free to be deleted.
	 * If the destroy() function has already been called on this instance by the time
	 * this function is called, this instance will be deleted.
	 */
	void release();

	/**
	 * Marks this instance as destroyed. If all previous references to this instance
	 * have been released, this instance will be deleted, otherwise deletion of this
	 * instance will automatically be deferred until all references have been released.
	 */
	void destroy() override;

	/** Construct an empty instance. Declared here to support copy constructor. */
	MVKVulkanAPIObject() {}

	/**
	 * Construct an instance from a copy. Default copy constructor disallowed due to mutex.
	 * Copies start with fresh reference counts.
	 */
	MVKVulkanAPIObject(const MVKVulkanAPIObject& other) {}

protected:

	bool decrementRetainCount();
	bool markDestroyed();

	std::mutex _refLock;
	unsigned _refCount = 0;
	bool _isDestroyed = false;
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
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getDispatchableObject() method.
     */
    void* getVkHandle() override { return &_icdRef; }

    /**
     * Retrieves the MVKDispatchableVulkanAPIObject instance referenced by the dispatchable Vulkan handle.
     * This is the compliment of the getVkHandle() method.
     */
    static inline MVKDispatchableVulkanAPIObject* getDispatchableObject(void* vkHandle) {
		return vkHandle ? ((MVKDispatchableObjectICDRef*)vkHandle)->mvkObject : nullptr;
    }

protected:
    MVKDispatchableObjectICDRef _icdRef = { ICD_LOADER_MAGIC, this };

};
