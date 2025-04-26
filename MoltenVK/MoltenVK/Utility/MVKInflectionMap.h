/*
 * MVKInflectionMap.h
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

#include "MVKSmallVector.h"
#include <unordered_map>

/**
 * An unordered map that splits elements between a fast-access vector of LinearCount consecutively
 * indexed elements, and a slower-access map holding sparse indexes larger than LinearCount.
 *
 * This design can be useful for a collection that is indexed by an enum that has a large
 * set of consecutive elements, plus additional enum values that are more sparsely assigned.
 * Examples of these enums are VkFormat and MTLPixelFormat.
 *
 * KeyType is used to lookup values, and must be a type that is convertable to an unsigned integer.
 * ValueType must have an empty constructor (default or otherwise).
 * IndexType must be a type that is convertable to an unsigned integer (eg. uint8_t...uint64_t),
 * and which is large enough to represent the number of values in this map.
 * Iteration can be accomplished as
 */
template<typename KeyType, typename ValueType, size_t LinearCount, typename IndexType = uint16_t>
class MVKInflectionMap {

public:
	using value_type = ValueType;
	class iterator {
		MVKInflectionMap* map;
		IndexType index;

	public:
		using iterator_category = std::forward_iterator_tag;
		using value_type = ValueType;
		using pointer = value_type*;
		using reference = value_type&;

		iterator() : map(nullptr), index(0) {}
		iterator(MVKInflectionMap& m, const IndexType i) : map(&m), index(i) {}

		iterator &operator=( const iterator &it ) {
			map = it.map;
			index  = it.index;
			return *this;
		}

		ValueType* operator->() { return &map->_values[index]; }
		ValueType& operator*()  { return  map->_values[index]; }
		operator ValueType*()   { return &map->_values[index]; }

		bool operator==(const iterator& it) const { return map == it.map && index == it.index; }
		bool operator!=(const iterator& it) const { return map != it.map || index != it.index; }

		iterator& operator++()      {                 index++; return *this; }
		iterator  operator++( int ) { auto t = *this; index++; return t; }

		bool is_valid()       const { return index < map->_values.size(); }
	};
	using reverse_iterator = std::reverse_iterator<iterator>;

	const ValueType& operator[](const KeyType idx) const { return getValue(idx); }
	ValueType& operator[](const KeyType idx) { return getValue(idx); }

	iterator begin() { return iterator(*this, 0); }
	iterator end()   { return iterator(*this, _values.size()); }

	bool empty() { return _values.size() == 0; }
	size_t size() { return _values.size(); }
	void reserve(const size_t new_cap) { _values.reserve(new_cap); }
	void shrink_to_fit() { _values.shrink_to_fit(); }

protected:
	static constexpr IndexType kMVKInflectionMapValueMissing = std::numeric_limits<IndexType>::max();
	typedef struct IndexValue { IndexType value = kMVKInflectionMapValueMissing; } IndexValue;

	// Returns a refrence to the value at the index.
	// If the index has not been initialized, add an empty element at 
	// the end of the values array, and set the index to its position.
	ValueType& getValue(KeyType idx) {
		IndexValue& valIdx = idx < LinearCount ? _linearIndexes[idx] : _inflectionIndexes[idx];
		if (valIdx.value == kMVKInflectionMapValueMissing) {
			_values.push_back({});
			valIdx.value = _values.size() - 1;
		}
		return _values[valIdx.value];
	}

	MVKSmallVector<ValueType> _values;
	std::unordered_map<KeyType, IndexValue> _inflectionIndexes;
	IndexValue _linearIndexes[LinearCount];
};
