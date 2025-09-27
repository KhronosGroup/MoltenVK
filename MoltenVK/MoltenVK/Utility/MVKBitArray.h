/*
 * MVKBitArray.h
 *
 * Copyright (c) 2020-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKFoundation.h"

#include <cassert>
#include <type_traits>
#include <functional>

namespace detail {
	static constexpr std::size_t SizeTBits = sizeof(std::size_t) * CHAR_BIT;

	template <typename T>
	static constexpr T maskLo(std::size_t begin) {
		constexpr std::size_t bits = sizeof(T) * CHAR_BIT;
		return static_cast<T>(~static_cast<T>(0)) << (begin % bits);
	}

	template <typename T>
	static constexpr T maskHi(std::size_t end) {
		constexpr std::size_t bits = sizeof(T) * CHAR_BIT;
		return static_cast<T>(~static_cast<T>(0)) >> ((bits - end) % bits);
	}

	template <typename Fn>
	static constexpr void applyToBitRange(MVKArrayRef<std::size_t> bits, std::size_t begin, std::size_t end, Fn&& fn) {
		if (begin >= end) [[unlikely]]
			return;
		std::size_t lo = begin / SizeTBits;
		std::size_t hi = (end - 1) / SizeTBits;

		std::size_t masklo = maskLo<std::size_t>(begin);
		std::size_t maskhi = maskHi<std::size_t>(end);
		if (lo == hi) {
			fn(bits[lo], masklo & maskhi);
		} else {
			fn(bits[lo], masklo);
			fn(bits[hi], maskhi);
			for (std::size_t i = lo + 1; i < hi; i++) {
				fn(bits[i], ~static_cast<std::size_t>(0));
			}
		}
	}
}

#pragma mark - MVKStaticBitArray

/**
 * A pointer to a bit in a bit set.
 * It decays into a bit offset, but if it's used directly with another bit set of the same type, you can save putting the pieces together only to take them apart again.
 */
template <typename Bits>
struct MVKBitPointer {
	std::size_t wordOffset;
	std::size_t bitOffset;
	operator std::size_t() const { return sizeof(Bits) * CHAR_BIT * wordOffset + bitOffset; }
};

/** Iterate over the bits set in `bits`, adding the offset `wordOffset` to each. */
template <typename Bits>
struct MVKSetBitIterator {
	// Codegen for uint32 iteration is a bit better than smaller sizes
	std::conditional_t<sizeof(Bits) < sizeof(uint32_t), uint32_t, Bits> bits;
	std::size_t wordOffset;
	constexpr MVKSetBitIterator begin() const { return *this; }
	constexpr MVKSetBitIterator end() const { return {0, wordOffset}; }
	constexpr operator bool() const { return bits != 0; }
	constexpr MVKBitPointer<Bits> operator*() const { return {wordOffset, mvkCTZ(bits)}; }
	constexpr bool operator==(const MVKSetBitIterator& other) const { assert(wordOffset == other.wordOffset); return bits == other.bits; }
	constexpr bool operator!=(const MVKSetBitIterator& other) const { assert(wordOffset == other.wordOffset); return bits != other.bits; }
	constexpr MVKSetBitIterator& operator++() {
		bits &= bits - 1;
		return *this;
	}
	constexpr MVKSetBitIterator operator++(int) {
		MVKSetBitIterator old = *this;
		operator++();
		return old;
	}
};

/**
 * Iterate over the bits set in an array of `Count` numbers.
 * This iterator will yield a `MVKSetBitIterator` for each element of the array.
 */
template <typename Bits>
struct MVKSetBitIteratorIterator {
	const Bits* bits;
	std::size_t index;
	std::size_t count;
	constexpr MVKSetBitIteratorIterator begin() const { return *this; }
	constexpr MVKSetBitIteratorIterator end() const { return {bits, count, count}; }
	constexpr bool operator==(const MVKSetBitIteratorIterator& other) const { assert(bits == other.bits); return index == other.index; }
	constexpr bool operator!=(const MVKSetBitIteratorIterator& other) const { assert(bits == other.bits); return index != other.index; }
	constexpr bool operator> (const MVKSetBitIteratorIterator& other) const { assert(bits == other.bits); return index >  other.index; }
	constexpr bool operator< (const MVKSetBitIteratorIterator& other) const { assert(bits == other.bits); return index <  other.index; }
	constexpr bool operator>=(const MVKSetBitIteratorIterator& other) const { assert(bits == other.bits); return index >= other.index; }
	constexpr bool operator<=(const MVKSetBitIteratorIterator& other) const { assert(bits == other.bits); return index <= other.index; }
	constexpr MVKSetBitIterator<Bits> operator*() const { return { bits[index], index }; }
	constexpr MVKSetBitIteratorIterator& operator++() {
		index++;
		return *this;
	}
	constexpr MVKSetBitIteratorIterator operator++(int) {
		MVKSetBitIteratorIterator old = *this;
		operator++();
		return old;
	}
};

template <typename Base>
class MVKSmallStaticBitSet {
	Base _bits;

	constexpr MVKSmallStaticBitSet(Base bits): _bits(bits) {}

public:
	constexpr MVKSmallStaticBitSet(): _bits(0) {}
	/** Constructs from a raw bit array. */
	static constexpr MVKSmallStaticBitSet fromBits(Base bits) { return { bits }; }
	/** Constructs from a range of set bits. */
	static constexpr MVKSmallStaticBitSet range(std::size_t begin, std::size_t end) {
		MVKSmallStaticBitSet res;
		if (end > begin) [[likely]] {
			std::size_t numBits = sizeof(Base) * CHAR_BIT;
			res._bits = static_cast<Base>(~static_cast<Base>(0)) >> ((numBits - end) % numBits);
			res._bits &= static_cast<Base>(~static_cast<Base>(0)) << begin;
		}
		return res;
	}

	/** Gets the raw bit array from the bitset. */
	constexpr Base bits() const { return _bits; }
	/** For C++ ranged for. */
	constexpr MVKSetBitIterator<Base> begin() const { return { _bits, 0 }; }
	/** For C++ ranged for. */
	constexpr MVKSetBitIterator<Base> end() const { return { 0, 0 }; }
	/**
	 * Gets an iterator over iterators over the bits set in the bitset.
	 *
	 * This is a convenience function for API compatibility with MVKLargeStaticBitSet.  If you know your bit set is small, you can iterate over its bits directly.
	 */
	constexpr MVKSetBitIteratorIterator<Base> setBitsList() const { return { &_bits, 0, 1 }; }

	/** Removes all bits from the set. */
	constexpr void reset() { _bits = 0; }
	/** Removes all bits from the set, then adds all the bits in the range `[begin, end)`. */
	constexpr void resetToRange(std::size_t begin, std::size_t end) { *this = range(begin, end); }
	/** Sets all bits in the given range. */
	constexpr void setRange(std::size_t begin, std::size_t end) { *this |= range(begin, end); }
	/** Clears all bits in the given range. */
	constexpr void clearRange(std::size_t begin, std::size_t end) { clearAllIn(range(begin, end)); }
	/** Sets or clears the given bit. */
	constexpr void set(std::size_t bit, bool value = true) {
		Base flag = static_cast<Base>(1) << bit;
		_bits = value ? _bits | flag : _bits & ~flag;
	}
	/** Sets or clears the given bit. */
	constexpr void set(MVKBitPointer<Base> bit, bool value = true) { set(bit.bitOffset, value); }
	/** A convenience function for set(bit, false). */
	constexpr void clear(MVKBitPointer<Base> bit) { set(bit, false); }
	/** A convenience function for set(bit, false). */
	constexpr void clear(std::size_t bit) { set(bit, false); }
	/** Returns whether the given bit is set. */
	constexpr bool get(std::size_t bit) const { return (_bits >> bit) & 1; }
	/** Returns whether the given bit is set. */
	constexpr bool get(MVKBitPointer<Base> bit) const { return get(bit.bitOffset); }
	/** Returns whether any bits in the array are set. */
	constexpr bool areAnyBitsSet() const { return _bits != 0; }
	/** Returns whether all bits in the array are unset. */
	constexpr bool areAllBitsClear() const { return !areAnyBitsSet(); }
	/** Returns the intersection of this and another set. */
	constexpr MVKSmallStaticBitSet operator&(MVKSmallStaticBitSet other) const { return MVKSmallStaticBitSet(_bits & other._bits); }
	/** Returns the union of this and another set. */
	constexpr MVKSmallStaticBitSet operator|(MVKSmallStaticBitSet other) const { return MVKSmallStaticBitSet(_bits | other._bits); }
	/** Intersects this set with the given set. */
	constexpr MVKSmallStaticBitSet& operator&=(MVKSmallStaticBitSet other) { *this = (*this & other); return *this; }
	/** Unions this set with the given set. */
	constexpr MVKSmallStaticBitSet& operator|=(MVKSmallStaticBitSet other) { *this = (*this | other); return *this; }
	/** Returns whether this set is equal to the given set. */
	constexpr bool operator==(MVKSmallStaticBitSet other) const { return _bits == other._bits; }
	/** Returns whether this set is not equal to the given set. */
	constexpr bool operator!=(MVKSmallStaticBitSet other) const { return !(*this == other); }
	/** Returns whether there are any elements in the intersection between this and another set. */
	constexpr bool containsAny(MVKSmallStaticBitSet other) const { return (*this & other).any(); }
	/** Returns whether this set is a superset of the given set. */
	constexpr bool containsAll(MVKSmallStaticBitSet other) const { return (*this & other) == other; }
	/** Subtracts the elements in the given set from this set. */
	constexpr void clearAllIn(MVKSmallStaticBitSet other) { _bits &= ~other._bits; }
	/** Returns the difference between this and another set. */
	constexpr MVKSmallStaticBitSet clearingAllIn(MVKSmallStaticBitSet other) const { return MVKSmallStaticBitSet(_bits & ~other._bits); }
};

template <uint32_t Bits>
class MVKLargeStaticBitSet {
	static constexpr std::size_t ElemSize = detail::SizeTBits;
	static constexpr std::size_t ArrayLen = (Bits + ElemSize - 1) / ElemSize;
	std::size_t bits[ArrayLen];

public:
	/** Constructs an empty bitset. */
	constexpr MVKLargeStaticBitSet(): bits{} {}

	/** Constructs from a range of set bits. */
	static constexpr MVKLargeStaticBitSet range(std::size_t begin, std::size_t end) {
		MVKLargeStaticBitSet res;
		res.setRange(begin, end);
		return res;
	}

	/** Returns an iterator over iterators over the bits set in the bitset. */
	constexpr MVKSetBitIteratorIterator<std::size_t> setBitsList() const { return { bits, 0, ArrayLen }; }

	/** Removes all bits from the set. */
	constexpr void reset() {
		for (uint32_t i = 0; i < ArrayLen; i++)
			bits[i] = 0;
	}

	/** Removes all bits from the set, then add all the bits in the range `[begin, end)`. */
	constexpr void resetToRange(std::size_t begin, std::size_t end) {
		*this = range(begin, end);
	}

	/** Sets all bits in the given range. */
	constexpr void setRange(std::size_t begin, std::size_t end) {
		detail::applyToBitRange(bits, begin, end, [](std::size_t& val, std::size_t mask){ val |= mask; });
	}

	/** Clears all bits in the given range. */
	constexpr void clearRange(std::size_t begin, std::size_t end) {
		detail::applyToBitRange(bits, begin, end, [](std::size_t& val, std::size_t mask){ val &= ~mask; });
	}

	/** Sets or clears the given bit. */
	constexpr void set(MVKBitPointer<std::size_t> bit, bool value = true) {
		std::size_t& word = bits[bit.wordOffset];
		std::size_t flag = static_cast<std::size_t>(1ull << bit.bitOffset);
		word = value ? word | flag : word & ~flag;
	}
	/** Sets or clears the given bit. */
	constexpr void set(std::size_t bit, bool value = true) { set({ bit / ElemSize, bit % ElemSize }, value); }
	/** Clears the given bit. A convenience function for set(bit, false). */
	constexpr void clear(MVKBitPointer<std::size_t> bit) { set(bit, false); }
	/** Clears the given bit. A convenience function for set(bit, false). */
	constexpr void clear(std::size_t bit) { set(bit, false); }
	/** Returns whether the given bit is set. */
	constexpr bool get(MVKBitPointer<std::size_t> bit) const { return (bits[bit.wordOffset] >> bit.bitOffset) & 1; }
	constexpr bool get(std::size_t bit) const { return get({ bit / ElemSize, bit % ElemSize }); }
	/** Returns whether there are any bits in the set. */
	constexpr bool any() const {
		bool any = false;
		for (uint32_t i = 0; i < ArrayLen; i++)
			any |= bits[i] != 0;
		return any;
	}
	/** Returns whether the set is empty. */
	constexpr bool empty() const { return !any(); }
	/** Intersects this set with the given set. */
	constexpr MVKLargeStaticBitSet operator&=(const MVKLargeStaticBitSet& other) {
		for (uint32_t i = 0; i < ArrayLen; i++)
			bits[i] &= other.bits[i];
		return *this;
	}
	/** Unions this set with the given set. */
	constexpr MVKLargeStaticBitSet operator|=(const MVKLargeStaticBitSet& other) {
		for (uint32_t i = 0; i < ArrayLen; i++)
			bits[i] |= other.bits[i];
		return *this;
	}
	/** Returns whether this set is equal to the given set. */
	constexpr bool operator==(const MVKLargeStaticBitSet& other) const {
		bool eq = true;
		for (uint32_t i = 0; i < ArrayLen; i++)
			eq |= bits[i] == other.bits[i];
		return eq;
	}
	/** Returns the intersection of this and another set. */
	constexpr MVKLargeStaticBitSet operator&(const MVKLargeStaticBitSet& other) const { MVKLargeStaticBitSet res = *this; return res &= other; }
	/** Returns the union of this and another set. */
	constexpr MVKLargeStaticBitSet operator|(const MVKLargeStaticBitSet& other) const { MVKLargeStaticBitSet res = *this; return res |= other; }
	/** Returns whether this set is not equal to the given set. */
	constexpr bool operator!=(const MVKLargeStaticBitSet& other) const { return !(*this == other); }
	/** Returns whether there are any elements in the intersection between this and another set. */
	constexpr bool containsAny(const MVKLargeStaticBitSet& other) const {
		bool found = false;
		for (uint32_t i = 0; i < ArrayLen; i++)
			found |= (bits[i] & other.bits[i]) != 0;
		return found;
	}
	/** Returns whether this set is a superset of the given set. */
	constexpr bool containsAll(const MVKLargeStaticBitSet& other) const {
		bool check = true;
		for (uint32_t i = 0; i < ArrayLen; i++)
			check &= (bits[i] & other.bits[i]) == other.bits[i];
		return check;
	}
	/** Subtracts the elements in the given set from this one. */
	constexpr void clearAllIn(const MVKLargeStaticBitSet& other) {
		for (uint32_t i = 0; i < ArrayLen; i++)
			bits[i] &= ~other.bits[i];
	}
	/** Returns the difference between this set and the given set. */
	constexpr MVKLargeStaticBitSet clearingAllIn(const MVKLargeStaticBitSet& other) const {
		MVKLargeStaticBitSet res = *this;
		res.clearAllIn(other);
		return res;
	}
};

/**
 * A set for storing existence of bits in the known range `0..<Bits`,
 * like a std::bitset, but it also supports iterating over the set bits.
 */
template <uint32_t Bits>
using MVKStaticBitSet = std::conditional_t<(Bits > 32), MVKLargeStaticBitSet<Bits>, MVKSmallStaticBitSet<std::conditional_t<(Bits > 16), uint32_t, uint16_t>>>;

#pragma mark - MVKBitArray

class MVKBitArray {
	static constexpr std::size_t ElemSize = detail::SizeTBits;
	std::size_t* _data = nullptr;
	std::size_t _size = 0;
	// Small array optimization: For small arrays, store data in _capacity
	std::size_t _capacity = 0;

	static std::size_t elemCount(size_t size) {
		return (size + ElemSize - 1) / ElemSize;
	}

	std::size_t capacity() const {
		return _data == &_capacity ? ElemSize : _capacity;
	}

	void freeBuffer() {
		if (_data != &_capacity)
			free(_data);
	}

	MVKArrayRef<std::size_t> elems() {
		return { _data, elemCount(_size) };
	}

	MVKArrayRef<const std::size_t> elems() const {
		return { _data, elemCount(_size) };
	}

public:
	MVKBitArray(): _data(&_capacity) {}
	MVKBitArray(std::size_t size, bool value): MVKBitArray() { resizeAndClear(size, value); }
	MVKBitArray(const MVKBitArray& other): MVKBitArray() {
		_size = other._size;
		if (other._size <= ElemSize) {
			*_data = *other._data;
		} else {
			size_t elems = elemCount(other._size);
			size_t bytes = elems * sizeof(std::size_t);
			_capacity = elems * ElemSize;
			_data = static_cast<std::size_t*>(malloc(bytes));
			memcpy(_data, other._data, bytes);
		}
	}
	~MVKBitArray() { freeBuffer(); }

	MVKBitArray& operator=(const MVKBitArray& other) {
		_size = other._size;
		size_t elems = elemCount(other._size);
		if (other._size <= ElemSize) {
			*_data = *other._data;
		} else {
			size_t bytes = elems * sizeof(std::size_t);
			if (other._size > capacity()) {
				freeBuffer();
				_data = static_cast<std::size_t*>(malloc(bytes));
				_capacity = elems * ElemSize;
			}
			memcpy(_data, other._data, bytes);
		}
		return *this;
	}

	/**
	 * Resize this array to the specified number of bits, and reset all bits to the given value.
	 *
	 * This is faster than separately resizing and clearing the bits.
	 *
	 * If the new size is larger than the existing size, new memory may be allocated.
	 * If the new size is less than the existing size, consumed memory is retained.
	 */
	void resizeAndClear(std::size_t newSize, bool value = false) {
		size_t elems = elemCount(newSize);
		_size = newSize;

		if (newSize <= ElemSize) {
			*_data = value ? MVKSmallStaticBitSet<std::size_t>::range(0, newSize).bits() : 0;
			return;
		}

		if (newSize > capacity()) {
			freeBuffer();
			_data = static_cast<std::size_t*>(calloc(elems, sizeof(std::size_t)));
			_capacity = elems * ElemSize;
			if (value)
				memset(_data, 0xff, elems * sizeof(std::size_t));
		} else {
			memset(_data, value ? 0xff : 0, elems * sizeof(std::size_t));
		}
		if (value)
			_data[elems - 1] = detail::maskHi<std::size_t>(newSize);
	}

	/**
	 * Resize this array to the specified number of bits.
	 *
	 * The value of existing bits that fit within the new size are retained, and any
	 * new bits that are added to accommodate the new size are set to the given value.
	 *
	 * If the new size is larger than the existing size, new memory may be allocated.
	 * If the new size is less than the existing size, consumed memory is retained.
	 */
	void resize(std::size_t newSize, bool value = false) {
		size_t elems = elemCount(newSize);
		size_t oldSize = _size;
		_size = newSize;
		if (newSize <= oldSize) {
			if (newSize)
				_data[elems - 1] &= detail::maskHi<std::size_t>(newSize);
		} else {
			size_t bytes = elems * sizeof(std::size_t);
			if (newSize > capacity()) {
				if (_data == &_capacity) {
					_data = static_cast<std::size_t*>(malloc(bytes));
					*_data = _capacity;
				} else {
					_data = static_cast<std::size_t*>(realloc(_data, bytes));
				}
				_capacity = elems * ElemSize;
				// The rest of the elements will get overwritten by the set/clear range
				_data[elems - 1] = 0;
			}
			if (value)
				setRange(oldSize, newSize);
			else
				clearRange(oldSize, newSize);
		}
	}

	/** Returns an iterator over iterators over the set bits in this array. */
	MVKSetBitIteratorIterator<std::size_t> setBitsList() const { return { _data, 0, elemCount(_size) }; }

	/** Sets all bits in the given range. */
	void setRange(std::size_t begin, std::size_t end) {
		assert(end <= _size);
		detail::applyToBitRange(elems(), begin, end, [](std::size_t& val, std::size_t mask){ val |= mask; });
	}

	/** Clears all bits in the given range. */
	void clearRange(std::size_t begin, std::size_t end) {
		assert(end <= _size);
		detail::applyToBitRange(elems(), begin, end, [](std::size_t& val, std::size_t mask){ val &= ~mask; });
	}

	/** Sets or clears the given bit. */
	void set(MVKBitPointer<std::size_t> bit, bool value = true) {
		assert(static_cast<std::size_t>(bit) < _size);
		std::size_t& word = _data[bit.wordOffset];
		std::size_t flag = static_cast<std::size_t>(1ull << bit.bitOffset);
		word = value ? word | flag : word & ~flag;
	}
	/** Sets or clears the given bit. */
	void set(std::size_t bit, bool value = true) { set({ bit / ElemSize, bit % ElemSize }, value); }
	/** Clears the given bit. A convenience function for set(bit, false). */
	void clear(MVKBitPointer<std::size_t> bit) { set(bit, false); }
	/** Clears the given bit. A convenience function for set(bit, false). */
	void clear(std::size_t bit) { set(bit, false); }
	/** Returns whether the given bit is set. */
	bool get(MVKBitPointer<std::size_t> bit) const {
		assert(static_cast<std::size_t>(bit) < _size);
		return (_data[bit.wordOffset] >> bit.bitOffset) & 1;
	}
	/** Returns whether the given bit is set. */
	bool get(std::size_t bit) const { return get({ bit / ElemSize, bit % ElemSize }); }
	/** Returns whether any bits in the array are set. */
	bool areAnyBitsSet() const {
		for (std::size_t elem : elems())
			if (elem)
				return false;
		return true;
	}
	/** Returns whether all bits in the array are unset. */
	bool areAllBitsClear() const { return !areAnyBitsSet(); }

	bool operator==(const MVKBitArray& other) const {
		if (_size != other._size)
			return false;
		size_t end = elemCount(_size);
		for (size_t i = 0; i < end; i++)
			if (_data[i] != other._data[i])
				return false;
		return true;
	}
	bool operator!=(const MVKBitArray& other) const { return !(*this == other); }
};
