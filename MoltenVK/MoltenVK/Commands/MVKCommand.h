/*
 * MVKCommand.h
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

class MVKCommandBuffer;
class MVKCommandEncoder;
class MVKCommandPool;
//class MVKCommandEncodingPool;
template <class T> class MVKCommandTypePool;


#pragma mark -
#pragma mark MVKCommand

/**
 * Abstract class that represents a Vulkan command.
 *
 * To allow the command contents to be populated, all concrete
 * subclasses must support a member function of the following form:
 *
 *     VkResult setContent(MVKCommandBuffer* cmdBuff, ...);
 */
class MVKCommand : public MVKBaseObject, public MVKLinkableMixin<MVKCommand> {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; }

	/** Encodes this command on the specified command encoder. */
	virtual void encode(MVKCommandEncoder* cmdEncoder) = 0;

	/** 
     * Returns this object back to the type pool associated with the subclass type,
	 * contained in the command pool.
     *
     * This method is not thread-safe. Vulkan Command Pools are externally synchronized. 
     * For a particular MVKCommandTypePool instance, all calls to pool->aquireObject(), 
     * and returnToPool() (or pool->returnObject()), MUST be called from the same thread.
     *
     * Do not call this function if a subclass instance has been created inline to
	 * perform a transient sub-command operation. Instead, let the instance be destroyed
	 * automatically at the end of the inline scope, as usual for inline instantiation.
     */
    void returnToPool(MVKCommandPool* cmdPool);

    MVKCommand(MVKCommandTypePool<MVKCommand>* pool) {}

protected:
	virtual MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) = 0;

	// Macro to implement a subclass override of the getTypePool(MVKCommandPool* cmdPool) function.
#	define MVKFuncionOverride_getTypePool(cmdType)					  							\
	MVKCommandTypePool<MVKCommand>* MVKCmd ##cmdType ::getTypePool(MVKCommandPool* cmdPool) {	\
		return (MVKCommandTypePool<MVKCommand>*)&cmdPool->_cmd  ##cmdType ##Pool;				\
	}
};


#pragma mark -
#pragma mark MVKCommandTypePool

/**
 * Static function for MVKCommandTypePool template to call to resolve its own getVulkanAPIObject()
 * from its MVKCommandPool. Needed because MVKCommandTypePool template cannot have a function
 * implementation outside the template, and MVKCommandPool is not fully defined in this header file.
 */
MVKVulkanAPIObject* mvkCommandPoolGetVulkanAPIObject(MVKCommandPool* cmdPool);


/** A pool of MVKCommand instances of a particular type. */
template <class T>
class MVKCommandTypePool : public MVKObjectPool<T> {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return mvkCommandPoolGetVulkanAPIObject(_commandPool); };

    /** Some commands require access to the command pool to access resources. */
    MVKCommandPool* getCommandPool() { return _commandPool; }

    /** Returns a new command instance. */
    T* newObject() override { return new T(this); }

    /**
     * Configures this instance to either use pooling, or not, depending on the
     * value of isPooling, which defaults to true if not indicated explicitly.
     */
    MVKCommandTypePool(MVKCommandPool* cmdPool, bool isPooling = true) : MVKObjectPool<T>(isPooling), _commandPool(cmdPool) {}

protected:
    MVKCommandPool* _commandPool;
};


#pragma mark -
#pragma mark MVKLoadStoreOverrideMixin

/**
 * Shared state mixin for draw commands.
 *
 * As a mixin, this class should only be used as a component of multiple inheritance.
 * Any class that inherits from this class should also inherit from MVKBaseObject.
 * This requirement is to avoid the diamond problem of multiple inheritance.
 */
class MVKLoadStoreOverrideMixin {
public:
	void setLoadOverride(bool loadOverride) { _loadOverride = loadOverride; }
	void setStoreOverride(bool storeOverride) { _storeOverride = storeOverride; }

protected:
    bool _loadOverride;
    bool _storeOverride;
};


