/*
 * MVKCommand.h
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
class MVKCommand : public MVKConfigurableObject {

public:

    /** Called when this command is added to a command buffer. */
    virtual void added(MVKCommandBuffer* cmdBuffer) {};

    /** Indicates that this command has a valid configuration and can be encoded. */
    inline bool canEncode() { return _configurationResult == VK_SUCCESS; }

	/** Encodes this command on the specified command encoder. */
	virtual void encode(MVKCommandEncoder* cmdEncoder) = 0;

	/** 
     * Returns this object back to the pool that created it. This will reset the value of _next member.
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

	/**
	 * Instances of this class can participate in a linked list or pool. When so participating,
	 * this is a reference to the next instance in the list or pool. This value should only be
	 * managed and set by the list or pool.
	 */
	MVKCommand* _next = nullptr;

protected:
    MVKCommandTypePool<MVKCommand>* _pool;
};


#pragma mark -
#pragma mark MVKCommandTypePool

/** A pool of MVKCommand instances of a particular type. */
template <class T>
class MVKCommandTypePool : public MVKObjectPool<T> {

public:

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
#pragma mark MVKLoadStoreOverride

/** Shared state with all draw commands */
class MVKLoadStoreOverride {
public:
    void setLoadOverride(bool loadOverride);
    void setStoreOverride(bool storeOverride);

protected:
    bool _loadOverride;
    bool _storeOverride;
};


