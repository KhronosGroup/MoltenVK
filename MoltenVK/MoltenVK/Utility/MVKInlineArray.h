/*
 * MVKInlineArray.h
 *
 * Copyright (c) 2023-2025 Evan Tang for CodeWeavers
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

/* A lot of Vulkan objects contain many arrays whose sizes never change after creation.
 * Use these classes to allocate them all on the same allocation as the object instance.
 * Construct objects containing these with MVKInlineObjectConstructor
 */

#pragma once

#include "MVKFoundation.h"

template <typename Base> class MVKInlineObjectConstructor;

/** Base class for classes that use inline objects. */
class MVKInlineConstructible {
public:
	void operator delete(void* ptr) noexcept {
		// Since we custom allocate with a size other than sizeof(*this),
		// we can't let C++ use the operator delete(void*, size_t)
		// Define a custom operator delete, so C++ will use that instead
		::operator delete(ptr);
	}
	// You can't make arrays of these
	void operator delete[](void*) = delete;
};

/** An array whose allocation is part of the allocation of its parent object. */
template <typename T>
class MVKInlineArray : public MVKArrayRef<T> {
	constexpr MVKInlineArray(T* ptr, size_t sz): MVKArrayRef<T>(ptr, sz) {}
public:
	// MVKInlineArray is for use by heap allocated objects, which don't need to be copied
	// Copying an inline array wouldn't copy its allocation, which would be bad
	MVKInlineArray(MVKInlineArray&&) = delete;
	constexpr MVKInlineArray() = default;
	/**
	 * Manually construct an MVKInlineArray.
	 * `ptr` must be allocated on the parent object, e.g. with MVKInlineObjectConstructor::Allocate.
	 */
	void manualConstruct(T* ptr, size_t sz) {
		MVKArrayRef<T>::_data = ptr;
		MVKArrayRef<T>::_size = sz;
	}
	~MVKInlineArray() {
		for (T& t : *this)
			t.~T();
	}
};

/** A pointer whose allocation is part of the allocation of its parent object. */
template <typename T>
class MVKInlinePointer {
	T* _ptr = nullptr;
public:
	// MVKInlinePointer is for use by heap allocated objects, which don't need to be copied
	// Copying an inline pointer wouldn't copy its allocation, which would be bad
	MVKInlinePointer(MVKInlinePointer&&) = delete;
	constexpr MVKInlinePointer() = default;
	T& operator*() const { return *_ptr; }
	T* operator->() const { return _ptr; }
	T* get() const { return _ptr; }
	/**
	 * Manually construct an MVKInlinePointer.
	 * `ptr` must be allocated on the parent object, e.g. with MVKInlineObjectConstructor::Allocate.
	 */
	void manualConstruct(T* ptr) {
		_ptr = ptr;
	}
	~MVKInlinePointer() {
		if (_ptr)
			_ptr->~T();
	}
};
