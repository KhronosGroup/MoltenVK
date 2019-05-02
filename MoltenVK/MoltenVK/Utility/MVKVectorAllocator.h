/*
 * MVKVectorAllocator.h
 *
 * Copyright (c) 2012-2019 Dr. Torsten Hans (hans@ipacs.de)
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

namespace mvk_memory_allocator
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
// mvk_vector_allocator_base -> base class so we can use MVKVector with template parameter
//
//////////////////////////////////////////////////////////////////////////////////////////
template<typename T>
class mvk_vector_allocator_base
{
public:
  typedef T value_type;
  T      *ptr;
  size_t  num_elements_used;

public:
  mvk_vector_allocator_base()                                           : ptr{ nullptr }, num_elements_used{ 0 }                  { }
  mvk_vector_allocator_base( T *_ptr, const size_t _num_elements_used ) : ptr{ _ptr },    num_elements_used{ _num_elements_used } { }
  virtual ~mvk_vector_allocator_base() { }

  const T &operator[]( const size_t i ) const { return ptr[i]; }
  T       &operator[]( const size_t i )       { return ptr[i]; }

  size_t size() const { return num_elements_used; }

  virtual size_t get_capacity() const = 0;
  virtual void   allocate( const size_t num_elements_to_reserve ) = 0;
  virtual void   re_allocate( const size_t num_elements_to_reserve ) = 0;
  virtual void   shrink_to_fit() = 0;
  virtual void   deallocate() = 0;
};


//////////////////////////////////////////////////////////////////////////////////////////
//
// mvk_vector_allocator_default -> malloc based allocator for MVKVector
//
//////////////////////////////////////////////////////////////////////////////////////////
template <typename T>
class mvk_vector_allocator_default final : public mvk_vector_allocator_base<T>
{
private:
  size_t  num_elements_reserved;

public:
  template<class S, class... Args> typename std::enable_if< !std::is_trivially_constructible<S>::value >::type
    construct( S *_ptr, Args&&... _args )
  {
    new ( _ptr ) S( std::forward<Args>( _args )... );
  }

  template<class S, class... Args> typename std::enable_if< std::is_trivially_constructible<S>::value >::type
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
    for( size_t i = 0; i < mvk_vector_allocator_base<S>::num_elements_used; ++i )
    {
      mvk_vector_allocator_base<S>::ptr[i].~S();
    }

    mvk_vector_allocator_base<S>::num_elements_used = 0;
  }

  template<class S> typename std::enable_if< std::is_trivially_destructible<S>::value >::type
    destruct_all()
  {
    mvk_vector_allocator_base<T>::num_elements_used = 0;
  }

public:
  constexpr mvk_vector_allocator_default() : mvk_vector_allocator_base<T>{}, num_elements_reserved{ 0 }
  {
  }

  mvk_vector_allocator_default( mvk_vector_allocator_default &&a ) : mvk_vector_allocator_base<T>{ a.ptr, a.num_elements_used }, num_elements_reserved{ a.num_elements_reserved }
  {
    a.ptr                   = nullptr;
    a.num_elements_used     = 0;
    a.num_elements_reserved = 0;
  }

  virtual ~mvk_vector_allocator_default()
  {
    deallocate();
  }

  size_t get_capacity() const override
  {
    return num_elements_reserved;
  }

  void swap( mvk_vector_allocator_default &a )
  {
    const auto copy_ptr                   = a.ptr;
    const auto copy_num_elements_used     = a.num_elements_used;
    const auto copy_num_elements_reserved = a.num_elements_reserved;

    a.ptr                   = mvk_vector_allocator_base<T>::ptr;
    a.num_elements_used     = mvk_vector_allocator_base<T>::num_elements_used;
    a.num_elements_reserved = num_elements_reserved;

    mvk_vector_allocator_base<T>::ptr                = copy_ptr;
    mvk_vector_allocator_base<T>::num_elements_used  = copy_num_elements_used;
    num_elements_reserved = copy_num_elements_reserved;
  }

  void allocate( const size_t num_elements_to_reserve ) override
  {
    deallocate();

    mvk_vector_allocator_base<T>::ptr                = reinterpret_cast< T* >( mvk_memory_allocator::alloc( num_elements_to_reserve * sizeof( T ) ) );
    mvk_vector_allocator_base<T>::num_elements_used  = 0;
    num_elements_reserved = num_elements_to_reserve;
  }

  void re_allocate( const size_t num_elements_to_reserve ) override
  {
    //if constexpr( std::is_trivially_copyable<T>::value )
    //{
    //  ptr = reinterpret_cast< T* >( mvk_memory_allocator::tm_memrealloc( ptr, num_elements_to_reserve * sizeof( T ) );
    //}
    //else
    {
      auto *new_ptr = reinterpret_cast< T* >( mvk_memory_allocator::alloc( num_elements_to_reserve * sizeof( T ) ) );

      for( size_t i = 0; i < mvk_vector_allocator_base<T>::num_elements_used; ++i )
      {
        construct( &new_ptr[i], std::move( mvk_vector_allocator_base<T>::ptr[i] ) );
        destruct( &mvk_vector_allocator_base<T>::ptr[i] );
      }

      //if ( ptr != nullptr )
      {
        mvk_memory_allocator::free( mvk_vector_allocator_base<T>::ptr );
      }

      mvk_vector_allocator_base<T>::ptr = new_ptr;
    }

    num_elements_reserved = num_elements_to_reserve;
  }

  void shrink_to_fit() override
  {
    if( mvk_vector_allocator_base<T>::num_elements_used == 0 )
    {
      deallocate();
    }
    else
    {
      auto *new_ptr = reinterpret_cast< T* >( mvk_memory_allocator::alloc( mvk_vector_allocator_base<T>::num_elements_used * sizeof( T ) ) );

      for( size_t i = 0; i < mvk_vector_allocator_base<T>::num_elements_used; ++i )
      {
        construct( &new_ptr[i], std::move( mvk_vector_allocator_base<T>::ptr[i] ) );
        destruct( &mvk_vector_allocator_base<T>::ptr[i] );
      }

      mvk_memory_allocator::free( mvk_vector_allocator_base<T>::ptr );

      mvk_vector_allocator_base<T>::ptr = new_ptr;
      num_elements_reserved = mvk_vector_allocator_base<T>::num_elements_used;
    }
  }

  void deallocate() override
  {
    destruct_all<T>();

    mvk_memory_allocator::free( mvk_vector_allocator_base<T>::ptr );

    mvk_vector_allocator_base<T>::ptr = nullptr;
    num_elements_reserved = 0;
  }
};


//////////////////////////////////////////////////////////////////////////////////////////
//
// mvk_vector_allocator_with_stack -> malloc based MVKVector allocator with preallocated storage
//
//////////////////////////////////////////////////////////////////////////////////////////
template <typename T, int N>
class mvk_vector_allocator_with_stack final : public mvk_vector_allocator_base<T>
{
private:
  //size_t  num_elements_reserved; // uhh, num_elements_reserved is mapped onto the stack elements, let the fun begin
  alignas( alignof( T ) ) unsigned char   elements_stack[N * sizeof( T )];

  static_assert( N * sizeof( T ) >= sizeof( size_t ), "Bummer, nasty optimization doesn't work" );

  void set_num_elements_reserved( const size_t num_elements_reserved )
  {
    *reinterpret_cast<size_t*>( &elements_stack[0] ) = num_elements_reserved;
  }

public:
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
    for( size_t i = 0; i < mvk_vector_allocator_base<S>::num_elements_used; ++i )
    {
      mvk_vector_allocator_base<S>::ptr[i].~S();
    }

    mvk_vector_allocator_base<S>::num_elements_used = 0;
  }

  template<class S> typename std::enable_if< std::is_trivially_destructible<S>::value >::type
    destruct_all()
  {
    mvk_vector_allocator_base<S>::num_elements_used = 0;
  }

  template<class S> typename std::enable_if< !std::is_trivially_destructible<S>::value >::type
    swap_stack( mvk_vector_allocator_with_stack &a )
  {
    T stack_copy[N];

    for( size_t i = 0; i < mvk_vector_allocator_base<S>::num_elements_used; ++i )
    {
      construct( &stack_copy[i], std::move( S::ptr[i] ) );
      destruct( &mvk_vector_allocator_base<S>::ptr[i] );
    }

    for( size_t i = 0; i < a.num_elements_used; ++i )
    {
      construct( &mvk_vector_allocator_base<S>::ptr[i], std::move( a.ptr[i] ) );
      destruct( &mvk_vector_allocator_base<S>::ptr[i] );
    }

    for( size_t i = 0; i < mvk_vector_allocator_base<S>::num_elements_used; ++i )
    {
      construct( &a.ptr[i], std::move( stack_copy[i] ) );
      destruct( &stack_copy[i] );
    }
  }

  template<class S> typename std::enable_if< std::is_trivially_destructible<S>::value >::type
    swap_stack( mvk_vector_allocator_with_stack &a )
  {
    constexpr int STACK_SIZE = N * sizeof( T );
    for( int i = 0; i < STACK_SIZE; ++i )
    {
      const auto v = elements_stack[i];
      elements_stack[i] = a.elements_stack[i];
      a.elements_stack[i] = v;
    }
  }

public:
  mvk_vector_allocator_with_stack() : mvk_vector_allocator_base<T>{ reinterpret_cast<T*>( &elements_stack[0] ), 0 }
  {
  }

  mvk_vector_allocator_with_stack( mvk_vector_allocator_with_stack &&a ) : mvk_vector_allocator_base<T>{ nullptr, a.num_elements_used }
  {
    // is a heap based -> steal ptr from a
    if( !a.get_data_on_stack() )
    {
      mvk_vector_allocator_base<T>::ptr = a.ptr;
      set_num_elements_reserved( a.get_capacity() );

      a.ptr = a.get_default_ptr();
    }
    else
    {
      mvk_vector_allocator_base<T>::ptr = get_default_ptr();
      for( size_t i = 0; i < a.num_elements_used; ++i )
      {
        construct( &mvk_vector_allocator_base<T>::ptr[i], std::move( a.ptr[i] ) );
        destruct( &a.ptr[i] );
      }
    }

    a.num_elements_used = 0;
  }

  ~mvk_vector_allocator_with_stack()
  {
    deallocate();
  }

  size_t get_capacity() const override
  {
    return get_data_on_stack() ? N : *reinterpret_cast<const size_t*>( &elements_stack[0] );
  }

  constexpr T *get_default_ptr() const
  {
    return reinterpret_cast< T* >( const_cast< unsigned char * >( &elements_stack[0] ) );
  }

  bool get_data_on_stack() const
  {
    return mvk_vector_allocator_base<T>::ptr == get_default_ptr();
  }

  void swap( mvk_vector_allocator_with_stack &a )
  {
    // both allocators on heap -> easy case
    if( !get_data_on_stack() && !a.get_data_on_stack() )
    {
      auto copy_ptr = mvk_vector_allocator_base<T>::ptr;
      auto copy_num_elements_reserved = get_capacity();
      mvk_vector_allocator_base<T>::ptr = a.ptr;
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
      for( size_t i = 0; i < mvk_vector_allocator_base<T>::num_elements_used; ++i )
      {
        construct( &a.ptr[i], std::move( mvk_vector_allocator_base<T>::ptr[i] ) );
        destruct( &mvk_vector_allocator_base<T>::ptr[i] );
      }

      mvk_vector_allocator_base<T>::ptr = copy_ptr;
      set_num_elements_reserved( copy_num_elements_reserved );
    }
    else if( !get_data_on_stack() && a.get_data_on_stack() )
    {
      auto copy_ptr = mvk_vector_allocator_base<T>::ptr;
      auto copy_num_elements_reserved = get_capacity();

      mvk_vector_allocator_base<T>::ptr = get_default_ptr();
      for( size_t i = 0; i < a.num_elements_used; ++i )
      {
        construct( &mvk_vector_allocator_base<T>::ptr[i], std::move( a.ptr[i] ) );
        destruct( &a.ptr[i] );
      }

      a.ptr = copy_ptr;
      a.set_num_elements_reserved( copy_num_elements_reserved );
    }

    auto copy_num_elements_used = mvk_vector_allocator_base<T>::num_elements_used;
    mvk_vector_allocator_base<T>::num_elements_used = a.num_elements_used;
    a.num_elements_used = copy_num_elements_used;
  }

  //
  // allocates rounded up to the defined alignment the number of bytes / if the system cannot allocate the specified amount of memory then a null block is returned
  //
  void allocate( const size_t num_elements_to_reserve ) override
  {
    deallocate();

    // check if enough memory on stack space is left
    if( num_elements_to_reserve <= N )
    {
      return;
    }

    mvk_vector_allocator_base<T>::ptr               = reinterpret_cast< T* >( mvk_memory_allocator::alloc( num_elements_to_reserve * sizeof( T ) ) );
    mvk_vector_allocator_base<T>::num_elements_used = 0;
    set_num_elements_reserved( num_elements_to_reserve );
  }

  //template<class S> typename std::enable_if< !std::is_trivially_copyable<S>::value >::type
  void _re_allocate( const size_t num_elements_to_reserve )
  {
    auto *new_ptr = reinterpret_cast< T* >( mvk_memory_allocator::alloc( num_elements_to_reserve * sizeof( T ) ) );

    for( size_t i = 0; i < mvk_vector_allocator_base<T>::num_elements_used; ++i )
    {
      construct( &new_ptr[i], std::move( mvk_vector_allocator_base<T>::ptr[i] ) );
      destruct( &mvk_vector_allocator_base<T>::ptr[i] );
    }

    if( mvk_vector_allocator_base<T>::ptr != get_default_ptr() )
    {
      mvk_memory_allocator::free( mvk_vector_allocator_base<T>::ptr );
    }

    mvk_vector_allocator_base<T>::ptr = new_ptr;
    set_num_elements_reserved( num_elements_to_reserve );
  }

  //template<class S> typename std::enable_if< std::is_trivially_copyable<S>::value >::type
  //  _re_allocate( const size_t num_elements_to_reserve )
  //{
  //  const bool data_is_on_stack = get_data_on_stack();
  //
  //  auto *new_ptr = reinterpret_cast< S* >( mvk_memory_allocator::tm_memrealloc( data_is_on_stack ? nullptr : ptr, num_elements_to_reserve * sizeof( S ) ) );
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

  void re_allocate( const size_t num_elements_to_reserve ) override
  {
    //TM_ASSERT( num_elements_to_reserve > get_capacity() );

    if( num_elements_to_reserve > N )
    {
      _re_allocate( num_elements_to_reserve );
    }
  }

  void shrink_to_fit() override
  {
    // nothing to do if data is on stack already
    if( get_data_on_stack() )
      return;

    // move elements to stack space
    if( mvk_vector_allocator_base<T>::num_elements_used <= N )
    {
      //const auto num_elements_reserved = get_capacity();

      auto *stack_ptr = get_default_ptr();
      for( size_t i = 0; i < mvk_vector_allocator_base<T>::num_elements_used; ++i )
      {
        construct( &stack_ptr[i], std::move( mvk_vector_allocator_base<T>::ptr[i] ) );
        destruct( &mvk_vector_allocator_base<T>::ptr[i] );
      }

      mvk_memory_allocator::free( mvk_vector_allocator_base<T>::ptr );

      mvk_vector_allocator_base<T>::ptr = stack_ptr;
    }
    else
    {
      auto *new_ptr = reinterpret_cast< T* >( mvk_memory_allocator::alloc( mvk_vector_allocator_base<T>::num_elements_used * sizeof( T ) ) );

      for( size_t i = 0; i < mvk_vector_allocator_base<T>::num_elements_used; ++i )
      {
        construct( &new_ptr[i], std::move( mvk_vector_allocator_base<T>::ptr[i] ) );
        destruct( &mvk_vector_allocator_base<T>::ptr[i] );
      }

      mvk_memory_allocator::free( mvk_vector_allocator_base<T>::ptr );

      mvk_vector_allocator_base<T>::ptr = new_ptr;
      set_num_elements_reserved( mvk_vector_allocator_base<T>::num_elements_used );
    }
  }

  void deallocate() override
  {
    destruct_all<T>();

    if( !get_data_on_stack() )
    {
      mvk_memory_allocator::free( mvk_vector_allocator_base<T>::ptr );
    }

    mvk_vector_allocator_base<T>::ptr = get_default_ptr();
    mvk_vector_allocator_base<T>::num_elements_used = 0;
  }
};


