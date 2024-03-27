/*
 * MVKMap.h
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

#include "MVKFoundation.h"
#include <unordered_map>

namespace mvk_map_memory_allocator
{
    inline char *alloc(const size_t num_bytes)
    {
        return new char[num_bytes];
    }

    inline void free(void *ptr)
    {
        delete[] (char*)ptr;
    }
};

template <typename Key, typename T, int M>
class mvk_map_allocator final {

public:
    std::pair<Key, T>* ptr;
    size_t num_elements_used;
private:
    static constexpr size_t CAP_CNT_SIZE = sizeof(size_t);
    static constexpr size_t ALIGN_CNT = CAP_CNT_SIZE / sizeof(std::pair<Key, T>);
    static constexpr size_t ALIGN_MASK = (ALIGN_CNT> 0) ? (ALIGN_CNT - 1) : 0;

    static constexpr size_t MIN_CNT = M> ALIGN_CNT ? M : ALIGN_CNT;
    static constexpr size_t N = (MIN_CNT + ALIGN_MASK) & ~ALIGN_MASK;

    static constexpr size_t MIN_STACK_SIZE = (N * sizeof(std::pair<Key, T>));
    static constexpr size_t STACK_SIZE = MIN_STACK_SIZE> CAP_CNT_SIZE ? MIN_STACK_SIZE : CAP_CNT_SIZE;
    alignas(alignof(std::pair<Key, T>)) unsigned char elements_stack[ STACK_SIZE ];
    
    void set_num_elements_reserved(const size_t num_elements_reserved)
    {
        *reinterpret_cast<size_t*>(&elements_stack[0]) = num_elements_reserved;
    }
public:
    const T &operator[](const size_t i) const { return ptr[i]; }
    T       &operator[](const size_t i)       { return ptr[i]; }
    
    size_t size() const { return num_elements_used; }
    
    constexpr T *get_default_ptr() const
    {
        return reinterpret_cast<T*>(const_cast<unsigned char *>(&elements_stack[0]));
    }
    
    template<class S, class... Args> typename std::enable_if<!std::is_trivially_constructible<S, Args...>::value>::type
        construct(S *_ptr, Args&&... _args)
    {
        new (_ptr) S(std::forward<Args>(_args)...);
    }

    template<class S, class... Args> typename std::enable_if<std::is_trivially_constructible<S, Args...>::value>::type
        construct(S *_ptr, Args&&... _args)
    {
            *_ptr = S(std::forward<Args>(_args)...);
    }

    template<class S> typename std::enable_if<!std::is_trivially_destructible<S>::value>::type
        destruct(S *_ptr)
    {
            _ptr->~S();
    }

    template<class S> typename std::enable_if<std::is_trivially_destructible<S>::value>::type
        destruct(S *_ptr) {}

    template<class S> typename std::enable_if<!std::is_trivially_destructible<S>::value>::type
        destruct_all()
    {
        for(size_t i = 0; i < num_elements_used; ++i)
        {
            ptr[i].~S();
        }

        num_elements_used = 0;
    }

    template<class S> typename std::enable_if<std::is_trivially_destructible<S>::value>::type
    destruct_all()
    {
        num_elements_used = 0;
    }
    
    void re_allocate(const size_t num_elements_to_reserve)
    {
        auto *new_ptr = reinterpret_cast<T*>(mvk_smallvector_memory_allocator::alloc(num_elements_to_reserve * sizeof(T)));

        for(size_t i = 0; i < num_elements_used; ++i)
        {
            construct(&new_ptr[i], std::move(ptr[i]));
            destruct(&ptr[i]);
        }

        if(ptr != get_default_ptr())
        {
            mvk_smallvector_memory_allocator::free(ptr);
        }

        ptr = new_ptr;
        set_num_elements_reserved(num_elements_to_reserve);
    }
};
