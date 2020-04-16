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
#include "MVKDevice.h"

class MVKCommandBuffer;
class MVKCommandEncoder;
class MVKCommandPool;
class MVKCommandEncodingPool;
template <class T> class MVKCommandTypePool;


#pragma mark -
#pragma mark MVKCommand

/** Abstract class that represents a Vulkan command. */
class MVKCommand : public MVKConfigurableObject, public MVKLinkableMixin<MVKCommand> {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

    /** Indicates that this command has a valid configuration and can be encoded. */
    inline bool canEncode() { return _configurationResult == VK_SUCCESS; }

	/** Encodes this command on the specified command encoder. */
	virtual void encode(MVKCommandEncoder* cmdEncoder) = 0;

	/** 
     * Returns this object back to the pool that created it.
     *
     * This method is not thread-safe. Vulkan Command Pools are externally synchronized. 
     * For a particular MVKCommandTypePool instance, all calls to pool->aquireObject(), 
     * and returnToPool() (or pool->returnObject()), MUST be called from the same thread.
     *
     * It is possible to instantiate command instances directly, without retrieving them from
     * a command pool via acquireObject(). This can be done when a transient sub-command can be
     * used to perform some of the work during the execution of another command. In that case,
     * this method should not be called. It is sufficient to just destroy the command instance.
     */
    void returnToPool();

	/** Constructs this instance with the specified pool as its origin. */
    MVKCommand(MVKCommandTypePool<MVKCommand>* pool) : _pool(pool) {}

	/** Returns the command pool that is managing the resources used by this command. */
    MVKCommandPool* getCommandPool();

	/** Returns the command encoding pool. */
	MVKCommandEncodingPool* getCommandEncodingPool();

    /** Returns the device for which this command was created. */
    MVKDevice* getDevice();

    /** Returns the underlying Metal device. */
    id<MTLDevice> getMTLDevice();

	/** Returns info about the pixel format supported by the physical device. */
	MVKPixelFormats* getPixelFormats();

protected:
    MVKCommandTypePool<MVKCommand>* _pool;
};


#pragma mark -
#pragma mark MVKCommandTypePool

/**
 * Static function for MVKCommandTypePool template to call to resolve getVulkanAPIObject().
 * Needed because MVKCommandTypePool template cannot have function implementation outside
 * the template, and MVKCommandPool is not completely defined in this header file.
 */
MVKVulkanAPIObject* mvkCommandTypePoolGetVulkanAPIObject(MVKCommandPool* cmdPool);


/** A pool of MVKCommand instances of a particular type. */
template <class T>
class MVKCommandTypePool : public MVKObjectPool<T> {

public:


	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return mvkCommandTypePoolGetVulkanAPIObject(_commandPool); };

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
    void setLoadOverride(bool loadOverride);
    void setStoreOverride(bool storeOverride);

protected:
    bool _loadOverride;
    bool _storeOverride;
};


