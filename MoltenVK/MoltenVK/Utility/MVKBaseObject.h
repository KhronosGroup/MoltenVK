/*
 * MVKBaseObject.h
 *
 * Copyright (c) 2015-2023 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include <string>
#include <atomic>

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
	void reportMessage(MVKConfigLogLevel logLevel, const char* format, ...) __printflike(3, 4);

	/**
	 * Report a Vulkan error message, on behalf of the object, which may be nil.
	 * Reporting includes logging to a standard system logging stream, and if the object
	 * is not nil and has access to the VkInstance, the message will also be forwarded
	 * to the VkInstance for output to the Vulkan debug report messaging API.
	 */
	static void reportMessage(MVKBaseObject* mvkObj, MVKConfigLogLevel logLevel, const char* format, ...) __printflike(3, 4);

	/**
	 * Report a Vulkan error message, on behalf of the object, which may be nil.
	 * Reporting includes logging to a standard system logging stream, and if the object
	 * is not nil and has access to the VkInstance, the message will also be forwarded
	 * to the VkInstance for output to the Vulkan debug report messaging API.
	 *
	 * This is the core reporting implementation. Other similar functions delegate here.
	 */
	static void reportMessage(MVKBaseObject* mvkObj, MVKConfigLogLevel logLevel, const char* format, va_list args) __printflike(3, 0);

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
#pragma mark MVKReferenceCountingMixin

/**
 * This templated mixin adds the ability for an object to track references
 * to itself and defer destruction while existing references are alive.
 *
 * The BaseClass template parameter should derive from MVKBaseObject.
 * or must otherwise declare a virtual destroy() function.
 *
 * To add this mixin to a class, subclass from this mixin template class, and
 * set the template BaseClass to the nominal parent class of the class this is
 * being added to. For example, if MySubClass nominally inherits from MyBaseClass,
 * this mixin can be added to MySubClass by declaring MySubClass as follows:
 *
 *   class MySubClass : public MVKReferenceCountingMixin<MyBaseClass>
 *
 * As noted, in this example, MyBaseClass should derive from MVKBaseObject,
 * or must otherwise declare a virtual destroy() function
 */
template <class BaseClass>
class MVKReferenceCountingMixin : public BaseClass {

public:

	/**
	 * Called when this instance has been retained as a reference by another object,
	 * indicating that this instance will not be deleted until that reference is released.
	 */
	void retain() { _refCount++; }

	/**
	 * Called when this instance has been released as a reference from another object.
	 * Once all references have been released, this object is free to be deleted.
	 * If the destroy() function has already been called on this instance by the time
	 * this function is called, this instance will be deleted.
	 *
	 * Note that the destroy() function is called on the BaseClass.
	 * Releasing will not call any overridden destroy() function in a descendant class.
	 */
	void release() { if (--_refCount == 0) { BaseClass::destroy(); } }

	/**
	 * Marks this instance as destroyed. If all previous references to this instance
	 * have been released, this instance will be deleted, otherwise deletion of this
	 * instance will automatically be deferred until all references have been released.
	 */
	void destroy() override { release(); }

	MVKReferenceCountingMixin() : _refCount(1) {}

	/** Copy starts with fresh reference counts. */
	MVKReferenceCountingMixin(const MVKReferenceCountingMixin& other) {
		_refCount = 1;
	}

	/** Copy starts with fresh reference counts. */
	MVKReferenceCountingMixin& operator=(const MVKReferenceCountingMixin& other) {
		_refCount = 1;
		return *this;
	}

protected:
	std::atomic<uint32_t> _refCount;

};


#pragma mark -
#pragma mark MVKConfigurableMixin

/**
 * Mixin that can be added to a class whose instances are configured from Vulkan configuration
 * info, and the result of which can be validated and tracked as a queriable Vulkan VkResult.
 */
class MVKConfigurableMixin {

public:

	/** Returns a indication of the success of the configuration of this instance. */
	VkResult getConfigurationResult() { return _configurationResult; }

	/** If the existing configuration result is VK_SUCCESS, it is set to the specified value. */
	void setConfigurationResult(VkResult vkResult) {
		if (_configurationResult == VK_SUCCESS) { _configurationResult = vkResult; }
	}

	/** Returns whether the configuration was successful. */
	bool wasConfigurationSuccessful() { return _configurationResult == VK_SUCCESS; }

	/** Resets the indication of the success of the configuration of this instance back to VK_SUCCESS. */
	void clearConfigurationResult() { _configurationResult = VK_SUCCESS; }

protected:
	VkResult _configurationResult = VK_SUCCESS;
};
