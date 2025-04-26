/*
 * MVKObjectPool.h
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include <mutex>


#pragma mark -
#pragma mark MVKLinkableMixin

/**
 * Instances of sublcasses of this mixin can participate in a typed linked list or pool.
 * A simple implementation of the CRTP (https://en.wikipedia.org/wiki/Curiously_recurring_template_pattern).
 */
template <class T>
class MVKLinkableMixin {

public:

	/**
	 * When participating in a linked list or pool, this is a reference to the next instance
	 * in the list or pool. This value should only be managed and set by the list or pool.
	 */
	T* _next = nullptr;

protected:
	friend T;
	MVKLinkableMixin() {};
};


#pragma mark -
#pragma mark MVKObjectPool

/** Track pool stats. */
typedef struct MVKObjectPoolCounts {
	uint64_t created = 0;
	uint64_t alive = 0;
	uint64_t resident = 0;
} MVKObjectPoolCounts;

/**
 * Manages a pool of instances of a particular object type.
 *
 * The objects managed by this pool should derive from MVKLinkableMixin, or otherwise
 * support a public member variable named "_next", of the same object type, which is
 * used by this pool to create a linked list of objects.
 *
 * When this pool is destroyed, any objects contained in the pool are also destroyed.
 *
 * This pool includes member functions for managing resources in either a thread-safe,
 * or somewhat faster, but not-thread-safe manner.
 *
 * An instance of this pool can be configured to either manage a pool of objects,
 * or simply allocate a new object instance on each request and destroy the object
 * when it is released back to the pool.
 */
template <class T>
class MVKObjectPool : public MVKBaseObject {

public:

	/**
	 * Acquires and returns the next available object from the pool, creating it if necessary.
	 *
	 * If this instance was configured to use pooling, the object is removed from the pool
	 * until it is returned back to the pool. If this instance was configured NOT to use
	 * pooling, the object is created anew on each request, and will be deleted when
	 * returned back to the pool.
     *
     * This method is not thread-safe. For a particular pool instance, all calls to
     * aquireObject() and returnObject() must be made from the same thread.
	 */
	T* acquireObject() {
		T* obj = nullptr;
		if (_isPooling) { obj = nextObject(); }
		if ( !obj ) {
			obj = newObject();
			_counts.created++;
			_counts.alive++;
		}

		return obj;
	}

	/**
	 * Returns the specified object back to the pool.
	 *
	 * If this instance was configured to use pooling, the returned object is added back
	 * into the pool. If this instance was configured NOT to use pooling, the returned
	 * object is simply deleted.
     *
     * This method is not thread-safe. For a particular pool instance, all calls to 
     * aquireObject() and returnObject() must be made from the same thread.
	 */
	void returnObject(T* obj) {
		if ( !obj ) { return; }

		if (_isPooling) {
			if (_tail) { _tail->_next = obj; }
			obj->_next = nullptr;
			_tail = obj;
			if ( !_head ) { _head = obj; }
			_counts.resident++;
		} else {
			destroyObject(obj);
		}
	}

	/** A thread-safe version of the acquireObject() function. */
	T* acquireObjectSafely() {
		std::lock_guard<std::mutex> lock(_lock);
		return acquireObject();
	}

	/** A thread-safe version of the returnObject() function. */
	void returnObjectSafely(T* obj) {
		std::lock_guard<std::mutex> lock(_lock);
		returnObject(obj);
	}

	/** Clears all the objects from this pool, destroying each one. This method is thread-safe. */
	void clear() {
        std::lock_guard<std::mutex> lock(_lock);
		while ( T* obj = nextObject() ) { destroyObject(obj); }
	}

	/** Returns the current counts. */
	MVKObjectPoolCounts getCounts() { return _counts; }

	/**
	 * Configures this instance to either use pooling, or not, depending on the
	 * value of isPooling, which defaults to true if not indicated explicitly.
	 */
    MVKObjectPool(bool isPooling = true) : _isPooling(isPooling) {}

	~MVKObjectPool() override { clear(); }

protected:

    /**
     * Removes and returns the first object in this pool, or returns null if this pool
     * contains no objects. This differs from the acquireObject() function, which creates
     * and return a new instance if this pool is empty. This method is not thread-safe.
     */
    T* nextObject() {
        T* obj = _head;
        if (obj) {
            _head = (T*)obj->_next;				// Will be null for last object in pool
            if ( !_head ) { _tail = nullptr; }	// If last, also clear tail
            obj->_next = nullptr;				// Objects in the wild should never think they are still part of this pool
			_counts.resident--;
        }
        return obj;
    }

    /** Returns a new instance of the type of object managed by this pool. */
    virtual T* newObject() = 0;

	/** Destroys the object. */
	void destroyObject(T* obj) {
		obj->destroy();
		_counts.alive--;
	}

    std::mutex _lock;
	T* _head = nullptr;
	T* _tail = nullptr;
	bool _isPooling;
	MVKObjectPoolCounts _counts;
};

