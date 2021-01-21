/*
 * MVKBaseObject.h
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

#include "mvk_vulkan.h"
#include <string>

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

	/** Returns whether the configuration was successful. */
	inline bool wasConfigurationSuccessful() { return _configurationResult == VK_SUCCESS; }

    /** Resets the indication of the success of the configuration of this instance back to VK_SUCCESS. */
    inline void clearConfigurationResult() { _configurationResult = VK_SUCCESS; }

protected:
	VkResult _configurationResult = VK_SUCCESS;
};
