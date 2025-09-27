/*
 * MVKInlineObjectConstructor.h
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

#pragma once

#include "MVKInlineArray.h"

#include <new>
#include <type_traits>

/** Helper for creating objects that utilize inline arrays. */
template <typename Base>
class MVKInlineObjectConstructor {
	static_assert(std::is_base_of<MVKInlineConstructible, Base>::value);
private:
	size_t offset = 0;

	size_t Allocate(size_t amt, size_t align) {
		size_t mask = align - 1;
		offset = (offset + mask) & ~mask;
		size_t ret = offset;
		offset += amt;
		return ret;
	}

	template <typename T>
	size_t Allocate(size_t count) {
		return Allocate(sizeof(T) * count, alignof(T));
	}

	MVKInlineObjectConstructor() = default;

	enum class InitType {
		Uninit,
		DefaultInit,
		Copy,
	};

	template <typename T, InitType Init>
	class PointerInitializer {
		MVKInlinePointer<T> Base::*member;
		size_t offset;
		const T* src;
		bool enabled;
		friend class MVKInlineObjectConstructor;
		PointerInitializer(MVKInlinePointer<T> Base::*member, const T* src, bool enabled)
			: member(member), offset(0), src(src), enabled(enabled) {}
		void Allocate(MVKInlineObjectConstructor& constructor) {
			if (enabled) { offset = constructor.Allocate<T>(1); }
		}
		void Write(Base* base, char* allocation) {
			T* ptr = enabled ? reinterpret_cast<T*>(allocation + offset) : nullptr;
			(base->*member).manualConstruct(ptr);
			if (!enabled)
				return;
			if constexpr (Init == InitType::DefaultInit) {
				new (ptr) T();
			} else if constexpr (Init == InitType::Copy) {
				new (ptr) T(*src);
			}
		}
	};

	template <typename T, InitType Init>
	class ArrayInitializer {
		MVKInlineArray<T> Base::*member;
		size_t offset;
		const T* src;
		size_t length;
		friend class MVKInlineObjectConstructor;
		ArrayInitializer(MVKInlineArray<T> Base::*member, const T* src, size_t length)
			: member(member), offset(0), src(src), length(length) {}
		void Allocate(MVKInlineObjectConstructor& constructor) {
			if (length) { offset = constructor.Allocate<T>(length); }
		}
		void Write(Base* base, char* allocation) {
			T* ptr = length ? reinterpret_cast<T*>(allocation + offset) : nullptr;
			(base->*member).manualConstruct(ptr, length);
			if constexpr (Init == InitType::DefaultInit) {
				for (size_t i = 0; i < length; i++)
					new (ptr + i) T();
			} else if constexpr (Init == InitType::Copy) {
				if constexpr (std::is_trivially_copyable<T>::value) {
					std::memcpy(ptr, src, sizeof(T) * length);
				} else {
					for (size_t i = 0; i < length; i++)
						new (ptr + i) T(src[i]);
				}
			}
		}
	};

	class ManualAllocationInitializer {
		void** target;
		size_t size;
		size_t align;
		size_t offset;
		friend class MVKInlineObjectConstructor;
		ManualAllocationInitializer(void** target, size_t size, size_t align)
			: target(target), size(size), align(align), offset(0) {}
		void Allocate(MVKInlineObjectConstructor& constructor) {
			if (size) { offset = constructor.Allocate(size, align); }
		}
		void Write(Base* base, char* allocation) {
			*target = size ? static_cast<void*>(allocation + offset) : nullptr;
		}
	};

	template <typename T>
	struct IsInitializer : public std::false_type {};
	template <typename T, InitType Init>
	struct IsInitializer<PointerInitializer<T, Init>> : public std::true_type {};
	template <typename T, InitType Init>
	struct IsInitializer<ArrayInitializer<T, Init>> : public std::true_type {};
	template <>
	struct IsInitializer<ManualAllocationInitializer> : public std::true_type {};

	template <typename T>
	static void AssertIsInitializer() {
		static_assert(IsInitializer<T>::value);
	}

public:
	/**
	 * Create an initializer for an allocation that can be manually used after a Create call.
	 * `*ptr` will be filled by the call to Create.
	 */
	static ManualAllocationInitializer Allocate(void** ptr, size_t size, size_t align) {
		return { ptr, size, align };
	}

	/** Create a pointer by copying the data behind an existing pointer. */
	template <typename T>
	static PointerInitializer<T, InitType::Copy> Copy(MVKInlinePointer<T> Base::*member, const T* ptr) {
		return { member, ptr, ptr };
	}
	/** Create an array by copying the data behind an existing array. */
	template <typename T>
	static ArrayInitializer<T, InitType::Copy> Copy(MVKInlineArray<T> Base::*member, MVKArrayRef<const T> ptr) {
		return { member, ptr.data(), ptr.size() };
	}

	/** Create a pointer by default-initializing the object. */
	template <typename T>
	static PointerInitializer<T, InitType::DefaultInit> Init(MVKInlinePointer<T> Base::*member, bool enabled = true) {
		return { member, nullptr, enabled };
	}
	/** Create an array by default-initializing its contents. */
	template <typename T>
	static ArrayInitializer<T, InitType::DefaultInit> Init(MVKInlineArray<T> Base::*member, size_t length) {
		return { member, nullptr, length };
	}

	/** Create a pointer but leave it uninitialized. */
	template <typename T>
	static PointerInitializer<T, InitType::Uninit> Uninit(MVKInlinePointer<T> Base::*member, bool enabled = true) {
		return { member, nullptr, enabled };
	}
	/** Create an array but leave it uninitialized. */
	template <typename T>
	static ArrayInitializer<T, InitType::Uninit> Uninit(MVKInlineArray<T> Base::*member, size_t length) {
		return { member, nullptr, length };
	}

	template <typename Allocator, typename... Fields, typename... Args>
	static Base* CreateWithAllocator(Allocator allocator, std::tuple<Fields...> fields, Args... args) {
		(AssertIsInitializer<Fields>(), ...);
		MVKInlineObjectConstructor constructor;
		constructor.Allocate<Base>(1);
		std::apply([&](auto&... field){ (field.Allocate(constructor), ...); }, fields);
		char* ptr = static_cast<char*>(allocator(constructor.offset));
		Base* base = new (ptr) Base(std::forward<Args>(args)...);
		std::apply([&](auto&... field){ (field.Write(base, ptr), ...); }, fields);
		return base;
	}

	template <typename... Fields, typename... Args>
	static Base* Create(std::tuple<Fields...> fields, Args... args) {
		return CreateWithAllocator(static_cast<void*(*)(size_t)>(::operator new), fields, std::forward<Args>(args)...);
	}
};
