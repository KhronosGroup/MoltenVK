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


#pragma mark -
#pragma mark MVKCommandTypePool

/** A pool of MVKCommand instances of a particular type. */
template <class T>
class MVKCommandTypePool : public MVKObjectPool<T> {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; }

	/** Returns a new command instance. */
	T* newObject() override { return new T(); }

	MVKCommandTypePool(bool isPooling = true) : MVKObjectPool<T>(isPooling) {}

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

	virtual MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) = 0;

	// Macro to implement a subclass override of the getTypePool(MVKCommandPool* cmdPool) function.
#	define MVKFuncionOverride_getTypePool(cmdType)					  							\
	MVKCommandTypePool<MVKCommand>* MVKCmd ##cmdType ::getTypePool(MVKCommandPool* cmdPool) {	\
		return (MVKCommandTypePool<MVKCommand>*)&cmdPool->_cmd  ##cmdType ##Pool;				\
	}
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


