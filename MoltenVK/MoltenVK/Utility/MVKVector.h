/*
 * MVKVectorAllocator.h
 *
 * Copyright (c) 2012-2018 Dr. Torsten Hans (hans@ipacs.de)
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

//
// a simple std::vector like container with a configurable extra stack space
// this class supports just the necessary members to be compatible with MoltenVK
// if C++17 is used, code can be simplified further
// by default MVKVector used 8 elements from the stack before getting memory from heap
//
#include "MVKVectorAllocator.h"
#include <type_traits>
#include <initializer_list>
#include <utility>

template<class Type, class Allocator = mvk_vector_allocator_with_stack<Type, 8>> class MVKVector
{
  Allocator alc;

public:
  class iterator
  {
    const MVKVector *vector;
    size_t           index;

  public:
    iterator() = delete;
    iterator( const size_t _index, const MVKVector &_vector ) : vector{ &_vector }, index{ _index } { }

    iterator &operator=( const iterator &it )
    {
      vector = it.vector;
      index = it.index;
      return *this;
    }

    Type *operator->() const
    {
      return &vector->alc.ptr[index];
    }

    operator Type*( ) const
    {
      return &vector->alc.ptr[index];
    }

    bool operator==( const iterator &it ) const
    {
      return ( vector == it.vector ) && ( index == it.index );
    }

    bool operator!=( const iterator &it ) const
    {
      return ( vector != it.vector ) || ( index != it.index );
    }

    iterator& operator++() { ++index; return *this; }

    bool   is_valid()     const { return index < vector->alc.num_elements_used; }
    size_t get_position() const { return index; }
  };

  class reverse_iterator
  {
    const MVKVector *vector;
    size_t           index;

  public:
    reverse_iterator() = delete;
    reverse_iterator( const size_t _index, const MVKVector &_vector ) : vector{ &_vector }, index{ _index } { }
    reverse_iterator &operator=( const reverse_iterator & ) = delete;

    Type *operator->() const
    {
      return &vector->alc.ptr[index];
    }

    operator Type*( ) const
    {
      return &vector->alc.ptr[index];
    }

    bool operator==( const reverse_iterator &it ) const
    {
      return vector == it.vector && index == it.index;
    }

    bool operator!=( const reverse_iterator &it ) const
    {
      return vector != it.vector || index != it.index;
    }

    reverse_iterator& operator++() { --index; return *this; }

    bool   is_valid()     const { return index < vector->alc.num_elements_used; }
    size_t get_position() const { return index; }
  };

private:
  size_t vector_GetNextCapacity() const
  {
    constexpr auto ELEMENTS_FOR_64_BYTES = 64 / sizeof( Type );
    constexpr auto MINIMUM_CAPACITY = ELEMENTS_FOR_64_BYTES > 4 ? ELEMENTS_FOR_64_BYTES : 4;
    const auto current_capacity = capacity();
    //if( current_capacity < 256 )
    //  return MINIMUM_CAPACITY + 2 * current_capacity;
    return MINIMUM_CAPACITY + ( 3 * current_capacity ) / 2;
  }

  void vector_Allocate( const size_t s )
  {
    const auto new_reserved_size = tm_max( s, alc.num_elements_used );

    alc.allocate( new_reserved_size );
  }

  void vector_ReAllocate( const size_t s )
  {
    alc.re_allocate( s );
  }

public:
  MVKVector()
  {
  }

  MVKVector( const size_t n, const Type t )
  {
    if( n > 0 )
    {
      alc.allocate( n );

      for( size_t i = 0; i < n; ++i )
      {
        alc.construct( &alc.ptr[i], t );
      }

      alc.num_elements_used = n;
    }
  }

  MVKVector( const MVKVector &a )
  {
    const size_t n = a.size();

    if( n > 0 )
    {
      alc.allocate( n );

      for( size_t i = 0; i < n; ++i )
      {
        alc.construct( &alc.ptr[i], a.alc.ptr[i] );
      }

      alc.num_elements_used = n;
    }
  }

  MVKVector( MVKVector &&a ) : alc{ std::move( a.alc ) }
  {
  }

  MVKVector( std::initializer_list<Type> vector )
  {
    if( vector.size() > capacity() )
    {
      vector_Allocate( vector.size() );
    }

    // std::initializer_list does not yet support std::move, we use it anyway but it has no effect
    for( auto &&element : vector )
    {
      alc.construct( &alc.ptr[alc.num_elements_used], std::move( element ) );
      ++alc.num_elements_used;
    }
  }

  ~MVKVector()
  {
  }

  MVKVector& operator=( const MVKVector &a )
  {
    if( this != &a )
    {
      const auto n = a.alc.num_elements_used;

      if( alc.num_elements_used == n )
      {
        for( size_t i = 0; i < n; ++i )
        {
          alc.ptr[i] = a.alc.ptr[i];
        }
      }
      else
      {
        if( n > capacity() )
        {
          vector_ReAllocate( n );
        }
        else
        {
          alc.destruct_all();
        }

        for( size_t i = 0; i < n; ++i )
        {
          alc.construct( &alc.ptr[i], a.alc.ptr[i] );
        }

        alc.num_elements_used = n;
      }
    }

    return *this;
  }

  MVKVector& operator=( MVKVector &&a )
  {
    alc.swap( a.alc );
    return *this;
  }

  bool operator==( const MVKVector &a ) const
  {
    if( alc.num_elements_used != a.alc.num_elements_used )
      return false;
    for( size_t i = 0; i < alc.num_elements_used; ++i )
    {
      if( alc.ptr[i] != a.alc.ptr[i] )
        return false;
    }
    return true;
  }

  bool operator!=( const MVKVector &a ) const
  {
    if( alc.num_elements_used != a.alc.num_elements_used )
      return true;
    for( size_t i = 0; i < alc.num_elements_used; ++i )
    {
      if( alc.ptr[i] != a.alc.ptr[i] )
        return true;
    }
    return false;
  }

  void swap( MVKVector &a )
  {
    alc.swap( a.alc );
  }

  void clear()
  {
    alc.template destruct_all<Type>();
  }

  void reset()
  {
    alc.deallocate();
  }

  iterator         begin()  const { return iterator( 0, *this ); }
  iterator         end()    const { return iterator( alc.num_elements_used, *this ); }
  reverse_iterator rbegin() const { return reverse_iterator( alc.num_elements_used - 1, *this ); }
  reverse_iterator rend()   const { return reverse_iterator( size_t( -1 ), *this ); }
  size_t           size()   const { return alc.num_elements_used; }
  bool             empty()  const { return alc.num_elements_used == 0; }

  Type &at( const size_t i ) const
  {
    return alc.ptr[i];
  }

  const Type &operator[]( const size_t i ) const
  {
    return alc.ptr[i];
  }

  Type &operator[]( const size_t i )
  {
    return alc.ptr[i];
  }

  const Type *data() const
  {
    return alc.ptr;
  }

  Type *data()
  {
    return alc.ptr;
  }

  size_t capacity() const
  {
    return alc.get_capacity();
  }

  const Type &front() const
  {
    return alc.ptr[0];
  }

  Type &front()
  {
    return alc.ptr[0];
  }

  const Type &back() const
  {
    return alc.ptr[alc.num_elements_used - 1];
  }

  Type &back()
  {
    return alc.ptr[alc.num_elements_used - 1];
  }

  void pop_back()
  {
    if( alc.num_elements_used > 0 )
    {
      --alc.num_elements_used;
      alc.destruct( &alc.ptr[alc.num_elements_used] );
    }
  }

  void reserve( const size_t new_size )
  {
    if( new_size > capacity() )
    {
      vector_ReAllocate( new_size );
    }
  }

  void assign( const size_t new_size, const Type &t )
  {
    if( new_size <= capacity() )
    {
      clear();
    }
    else
    {
      vector_Allocate( new_size );
    }

    for( size_t i = 0; i < new_size; ++i )
    {
      alc.construct( &alc.ptr[i], t );
    }

    alc.num_elements_used = new_size;
  }

  void resize( const size_t new_size, const Type t = { } )
  {
    if( new_size == alc.num_elements_used )
    {
      return;
    }

    if( new_size == 0 )
    {
      clear();
      return;
    }

    if( new_size > alc.num_elements_used )
    {
      if( new_size > capacity() )
      {
        vector_ReAllocate( new_size );
      }

      while( alc.num_elements_used < new_size )
      {
        alc.construct( &alc.ptr[alc.num_elements_used], t );
        ++alc.num_elements_used;
      }
    }
    else
    {
      //if constexpr( !std::is_trivially_destructible<Type>::value )
      {
        while( alc.num_elements_used > new_size )
        {
          --alc.num_elements_used;
          alc.destruct( &alc.ptr[alc.num_elements_used] );
        }
      }
      //else
      //{
      //  alc.num_elements_used = new_size;
      //}
    }
  }

  // trims the capacity of the slist to the number of alc.ptr
  void shrink_to_fit()
  {
    alc.shrink_to_fit();
  }

  void erase( const iterator it )
  {
    if( it.is_valid() )
    {
      --alc.num_elements_used;

      for( size_t i = it.GetIndex(); i < alc.num_elements_used; ++i )
      {
        alc.ptr[i] = std::move( alc.ptr[i + 1] );
      }

      // this is required for types with a destructor
      alc.destruct( &alc.ptr[alc.num_elements_used] );
    }
  }

  // adds t before it and automatically resizes vector if necessary
  void insert( const iterator it, Type t )
  {
    if( !it.is_valid() || alc.num_elements_used == 0 )
    {
      push_back( std::move( t ) );
    }
    else
    {
      if( alc.num_elements_used == capacity() )
        vector_ReAllocate( vector_GetNextCapacity() );

      // move construct last element
      alc.construct( &alc.ptr[alc.num_elements_used], std::move( alc.ptr[alc.num_elements_used - 1] ) );

      // move the remaining elements
      const size_t it_position = it.get_position();
      for( size_t i = alc.num_elements_used - 1; i > it_position; --i )
      {
        alc.ptr[i] = std::move( alc.ptr[i - 1] );
      }

      alc.ptr[it_position] = std::move( t );
      ++alc.num_elements_used;
    }
  }

  void push_back( const Type &t )
  {
    if( alc.num_elements_used == capacity() )
      vector_ReAllocate( vector_GetNextCapacity() );

    alc.construct( &alc.ptr[alc.num_elements_used], t );
    ++alc.num_elements_used;
  }

  void push_back( Type &&t )
  {
    if( alc.num_elements_used == capacity() )
      vector_ReAllocate( vector_GetNextCapacity() );

    alc.construct( &alc.ptr[alc.num_elements_used], std::forward<Type>( t ) );
    ++alc.num_elements_used;
  }

  template<class... Args>
  Type &emplace_back( Args&&... args )
  {
    if( alc.num_elements_used == capacity() )
      vector_ReAllocate( vector_GetNextCapacity() );

    alc.construct( &alc.ptr[alc.num_elements_used], std::forward<Args>( args )... );
    ++alc.num_elements_used;

    return alc.ptr[alc.num_elements_used - 1];
  }
};



