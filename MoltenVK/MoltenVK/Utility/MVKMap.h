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
#include "MVKMapAllocator.h"

template<typename Key,
         typename T,
         typename Allocator = mvk_map_allocator<Key, T, 0>,
         class Hash = std::hash<Key>>
class MVKMapImpl {
    
private:
    Allocator alc;
    
    class iterator
    {
        const MVKMapImpl* map;
        size_t            index;
    public:
        using iterator_category = std::random_access_iterator_tag;
        using difference_type = std::ptrdiff_t;
        typedef difference_type diff_type;

        iterator() : map{ nullptr }, index{ 0 } { }
        iterator(const size_t _index, const MVKMapImpl &_map) : map{ &_map }, index{ _index } { }

        iterator &operator=(const iterator &it)
        {
            map = it.map;
            index  = it.index;
            return *this;
        }

        T *operator->() { return &map->alc.ptr[index]; }
        T &operator*()  { return  map->alc.ptr[index]; }
        operator T*()   { return &map->alc.ptr[index]; }

        bool operator==( const iterator &it ) const { return map == it.map && index == it.index; }
        bool operator!=( const iterator &it ) const { return map != it.map || index != it.index; }

        iterator& operator++()      {                 ++index; return *this; }
        iterator  operator++( int ) { auto t = *this; ++index; return t; }
        iterator& operator--()      {                 --index; return *this; }
        iterator  operator--( int ) { auto t = *this; --index; return t; }

        iterator operator+ (const diff_type n)   { return iterator( index + n, *map ); }
        iterator& operator+= (const diff_type n) { index += n; return *this; }
        iterator operator- (const diff_type n)   { return iterator( index - n, *map ); }
        iterator& operator-= (const diff_type n) { index -= n; return *this; }

        diff_type operator- (const iterator& it) { return index - it.index; }

        bool operator< (const iterator& it)  { return index < it.index; }
        bool operator<= (const iterator& it) { return index <= it.index; }
        bool operator> (const iterator& it)  { return index > it.index; }
        bool operator>= (const iterator& it) { return index >= it.index; }

        const T &operator[]( const diff_type i ) const { return map->alc.ptr[index + i]; }
        T &operator[]( const diff_type i )             { return map->alc.ptr[index + i]; }

        bool   is_valid()     const { return index < map->alc.size(); }
        size_t get_position() const { return index; }
    };
protected:
    bool empty() { return alc.num_elements_used == 0;}
    size_t size() { return alc.size(); }
    
    T* &at( const size_t i )                { return alc[i]; }
    const T* const at(const size_t i) const { return alc[i]; }
    
    iterator begin() { return iterator(0, this); }
    iterator end() { return iterator(size(), this); }
    
    void erase(const iterator it)
    {
        if(it.is_valid())
        {
            --alc.num_elements_used;

            for(size_t i = it.get_position(); i < alc.num_elements_used; ++i)
            {
                alc.ptr[i] = alc.ptr[i + 1];
            }
        }
    }
    
    void erase(const iterator first, const iterator last)
    {
        if(first.is_valid())
        {
            size_t last_pos = last.is_valid() ? last.get_position() : size();
            size_t n = last_pos - first.get_position();
            alc.num_elements_used -= n;

            for(size_t i = first.get_position(), e = last_pos; i < alc.num_elements_used && e < alc.num_elements_used + n; ++i, ++e)
            {
                alc.ptr[i] = alc.ptr[e];
            }
        }
    }
    
    std::pair<iterator, bool> insert(const T& value)
    {
        alc.re_allocate(size() + 1);
        alc.ptr[size()] = value;
        return std::make_pair<iterator, bool>(end(), true);
    }
};
