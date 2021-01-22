/*
 * MVKSmallVectorAllocator.h
 *
 * Copyright (c) 2012-2021 Dr. Torsten Hans (hans@ipacs.de)
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

#include <new>
#include <type_traits>


namespace mvk_smallvector_memory_allocator
{
  inline char *alloc( const size_t num_bytes )
  {
    return new char[num_bytes];
  }

  inline void free( void *ptr )
  {
    delete[] (char*)ptr;
  }
};


//////////////////////////////////////////////////////////////////////////////////////////
//
// mvk_smallvector_allocator -> malloc based MVKSmallVector allocator with preallocated storage
//
//////////////////////////////////////////////////////////////////////////////////////////
template <typename T, int M>
class mvk_smallvector_allocator final
{
public:
	typedef T value_type;
	T      *ptr;
	size_t  num_elements_used;

private:

	// Once dynamic allocation is in use, the preallocated content memory space will
	// be re-purposed to hold the capacity count. If the content type is small, ensure
	// preallocated memory is large enough to hold the capacity count, and increase
	// the number of preallocated elements accordintly, to make use of this memory.
	// In addition, increase the number of pre-allocated elements to fill any space created
	// by the alignment of this structure, to maximize the use of the preallocated memory.
	static constexpr size_t CAP_CNT_SIZE = sizeof( size_t );
	static constexpr size_t ALIGN_CNT = CAP_CNT_SIZE / sizeof( T );
	static constexpr size_t ALIGN_MASK = (ALIGN_CNT > 0) ? (ALIGN_CNT - 1) : 0;

	static constexpr size_t MIN_CNT = M > ALIGN_CNT ? M : ALIGN_CNT;
	static constexpr size_t N = (MIN_CNT + ALIGN_MASK) & ~ALIGN_MASK;

	static constexpr size_t MIN_STACK_SIZE = ( N * sizeof( T ) );
	static constexpr size_t STACK_SIZE = MIN_STACK_SIZE > CAP_CNT_SIZE ? MIN_STACK_SIZE : CAP_CNT_SIZE;
	alignas( alignof( T ) ) unsigned char elements_stack[ STACK_SIZE ];

  void set_num_elements_reserved( const size_t num_elements_reserved )
  {
    *reinterpret_cast<size_t*>( &elements_stack[0] ) = num_elements_reserved;
  }

public:
  const T &operator[]( const size_t i ) const { return ptr[i]; }
  T       &operator[]( const size_t i )       { return ptr[i]; }

  size_t size() const { return num_elements_used; }

  //
  // faster element construction and destruction using type traits
  //
  template<class S, class... Args> typename std::enable_if< !std::is_trivially_constructible<S, Args...>::value >::type
    construct( S *_ptr, Args&&... _args )
  {
    new ( _ptr ) S( std::forward<Args>( _args )... );
  }

  template<class S, class... Args> typename std::enable_if< std::is_trivially_constructible<S, Args...>::value >::type
    construct( S *_ptr, Args&&... _args )
  {
    *_ptr = S( std::forward<Args>( _args )... );
  }

  template<class S> typename std::enable_if< !std::is_trivially_destructible<S>::value >::type
    destruct( S *_ptr )
  {
    _ptr->~S();
  }

  template<class S> typename std::enable_if< std::is_trivially_destructible<S>::value >::type
    destruct( S *_ptr )
  {
  }

  template<class S> typename std::enable_if< !std::is_trivially_destructible<S>::value >::type
    destruct_all()
  {
    for( size_t i = 0; i < num_elements_used; ++i )
    {
      ptr[i].~S();
    }

    num_elements_used = 0;
  }

  template<class S> typename std::enable_if< std::is_trivially_destructible<S>::value >::type
    destruct_all()
  {
    num_elements_used = 0;
  }

  template<class S> typename std::enable_if< !std::is_trivially_destructible<S>::value >::type
    swap_stack( mvk_smallvector_allocator &a )
  {
    T stack_copy[N];

    for( size_t i = 0; i < num_elements_used; ++i )
    {
      construct( &stack_copy[i], std::move( S::ptr[i] ) );
      destruct( &ptr[i] );
    }

    for( size_t i = 0; i < a.num_elements_used; ++i )
    {
      construct( &ptr[i], std::move( a.ptr[i] ) );
      destruct( &ptr[i] );
    }

    for( size_t i = 0; i < num_elements_used; ++i )
    {
      construct( &a.ptr[i], std::move( stack_copy[i] ) );
      destruct( &stack_copy[i] );
    }
  }

  template<class S> typename std::enable_if< std::is_trivially_destructible<S>::value >::type
    swap_stack( mvk_smallvector_allocator &a )
  {
    for( int i = 0; i < STACK_SIZE; ++i )
    {
      const auto v = elements_stack[i];
      elements_stack[i] = a.elements_stack[i];
      a.elements_stack[i] = v;
    }
  }

public:
  mvk_smallvector_allocator() : ptr(reinterpret_cast<T*>( &elements_stack[0] )), num_elements_used(0)
  {
  }

  mvk_smallvector_allocator( mvk_smallvector_allocator &&a )
  {
    // is a heap based -> steal ptr from a
    if( !a.get_data_on_stack() )
    {
      ptr = a.ptr;
      set_num_elements_reserved( a.get_capacity() );

      a.ptr = a.get_default_ptr();
    }
    else
    {
      ptr = get_default_ptr();
      for( size_t i = 0; i < a.num_elements_used; ++i )
      {
        construct( &ptr[i], std::move( a.ptr[i] ) );
        destruct( &a.ptr[i] );
      }
    }

	num_elements_used = a.num_elements_used;
    a.num_elements_used = 0;
  }

  ~mvk_smallvector_allocator()
  {
    deallocate();
  }

  size_t get_capacity() const
  {
    return get_data_on_stack() ? N : *reinterpret_cast<const size_t*>( &elements_stack[0] );
  }

  constexpr T *get_default_ptr() const
  {
    return reinterpret_cast< T* >( const_cast< unsigned char * >( &elements_stack[0] ) );
  }

  bool get_data_on_stack() const
  {
    return ptr == get_default_ptr();
  }

  void swap( mvk_smallvector_allocator &a )
  {
    // both allocators on heap -> easy case
    if( !get_data_on_stack() && !a.get_data_on_stack() )
    {
      auto copy_ptr = ptr;
      auto copy_num_elements_reserved = get_capacity();
      ptr = a.ptr;
      set_num_elements_reserved( a.get_capacity() );
      a.ptr = copy_ptr;
      a.set_num_elements_reserved( copy_num_elements_reserved );
    }
    // both allocators on stack -> just switch the stack contents
    else if( get_data_on_stack() && a.get_data_on_stack() )
    {
      swap_stack<T>( a );
    }
    else if( get_data_on_stack() && !a.get_data_on_stack() )
    {
      auto copy_ptr = a.ptr;
      auto copy_num_elements_reserved = a.get_capacity();

      a.ptr = a.get_default_ptr();
      for( size_t i = 0; i < num_elements_used; ++i )
      {
        construct( &a.ptr[i], std::move( ptr[i] ) );
        destruct( &ptr[i] );
      }

      ptr = copy_ptr;
      set_num_elements_reserved( copy_num_elements_reserved );
    }
    else if( !get_data_on_stack() && a.get_data_on_stack() )
    {
      auto copy_ptr = ptr;
      auto copy_num_elements_reserved = get_capacity();

      ptr = get_default_ptr();
      for( size_t i = 0; i < a.num_elements_used; ++i )
      {
        construct( &ptr[i], std::move( a.ptr[i] ) );
        destruct( &a.ptr[i] );
      }

      a.ptr = copy_ptr;
      a.set_num_elements_reserved( copy_num_elements_reserved );
    }

    auto copy_num_elements_used = num_elements_used;
    num_elements_used = a.num_elements_used;
    a.num_elements_used = copy_num_elements_used;
  }

  //
  // allocates rounded up to the defined alignment the number of bytes / if the system cannot allocate the specified amount of memory then a null block is returned
  //
  void allocate( const size_t num_elements_to_reserve )
  {
    deallocate();

    // check if enough memory on stack space is left
    if( num_elements_to_reserve <= N )
    {
      return;
    }

    ptr = reinterpret_cast< T* >( mvk_smallvector_memory_allocator::alloc( num_elements_to_reserve * sizeof( T ) ) );
    num_elements_used = 0;
    set_num_elements_reserved( num_elements_to_reserve );
  }

  //template<class S> typename std::enable_if< !std::is_trivially_copyable<S>::value >::type
  void _re_allocate( const size_t num_elements_to_reserve )
  {
    auto *new_ptr = reinterpret_cast< T* >( mvk_smallvector_memory_allocator::alloc( num_elements_to_reserve * sizeof( T ) ) );

    for( size_t i = 0; i < num_elements_used; ++i )
    {
      construct( &new_ptr[i], std::move( ptr[i] ) );
      destruct( &ptr[i] );
    }

    if( ptr != get_default_ptr() )
    {
      mvk_smallvector_memory_allocator::free( ptr );
    }

    ptr = new_ptr;
    set_num_elements_reserved( num_elements_to_reserve );
  }

  //template<class S> typename std::enable_if< std::is_trivially_copyable<S>::value >::type
  //  _re_allocate( const size_t num_elements_to_reserve )
  //{
  //  const bool data_is_on_stack = get_data_on_stack();
  //
  //  auto *new_ptr = reinterpret_cast< S* >( mvk_smallvector_memory_allocator::tm_memrealloc( data_is_on_stack ? nullptr : ptr, num_elements_to_reserve * sizeof( S ) ) );
  //  if( data_is_on_stack )
  //  {
  //    for( int i = 0; i < N; ++i )
  //    {
  //      new_ptr[i] = ptr[i];
  //    }
  //  }
  //
  //  ptr = new_ptr;
  //  set_num_elements_reserved( num_elements_to_reserve );
  //}

  void re_allocate( const size_t num_elements_to_reserve )
  {
    //TM_ASSERT( num_elements_to_reserve > get_capacity() );

    if( num_elements_to_reserve > N )
    {
      _re_allocate( num_elements_to_reserve );
    }
  }

  void shrink_to_fit()
  {
    // nothing to do if data is on stack already
    if( get_data_on_stack() )
      return;

    // move elements to stack space
    if( num_elements_used <= N )
    {
      //const auto num_elements_reserved = get_capacity();

      auto *stack_ptr = get_default_ptr();
      for( size_t i = 0; i < num_elements_used; ++i )
      {
        construct( &stack_ptr[i], std::move( ptr[i] ) );
        destruct( &ptr[i] );
      }

      mvk_smallvector_memory_allocator::free( ptr );

      ptr = stack_ptr;
    }
    else
    {
      auto *new_ptr = reinterpret_cast< T* >( mvk_smallvector_memory_allocator::alloc( num_elements_used * sizeof( T ) ) );

      for( size_t i = 0; i < num_elements_used; ++i )
      {
        construct( &new_ptr[i], std::move( ptr[i] ) );
        destruct( &ptr[i] );
      }

      mvk_smallvector_memory_allocator::free( ptr );

      ptr = new_ptr;
      set_num_elements_reserved( num_elements_used );
    }
  }

  void deallocate()
  {
    destruct_all<T>();

    if( !get_data_on_stack() )
    {
      mvk_smallvector_memory_allocator::free( ptr );
    }

    ptr = get_default_ptr();
    num_elements_used = 0;
  }
};

