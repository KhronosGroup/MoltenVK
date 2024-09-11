/*
 * MVKBitArray.h
 *
 * Copyright (c) 2020-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#pragma mark - MVKBitArray

/** Represents an array of bits, optimized for reduced storage and fast scanning for bits that are set. */
class MVKBitArray {

public:

	/**
	 * Returns the value of the bit, and optionally disables that bit if it was enabled.
	 * Returns false if the bitIndex is beyond the size of this array.
	 */
	bool getBit(size_t bitIndex, bool shouldDisable = false) {
		if (bitIndex >= _bitCount) { return false; }
		bool val = mvkIsAnyFlagEnabled(getSection(getIndexOfSection(bitIndex)), getBitPositionSectionMask(bitIndex));
		if (val && shouldDisable) { disableBit(bitIndex); }
		return val;
	}

	/** Sets the value of the bit to the val. */
	void setBit(size_t bitIndex, bool val) {
		if (bitIndex >= _bitCount) { return; }

		auto secIdx = getIndexOfSection(bitIndex);
		auto& sectionData = getSection(secIdx);
		if (val) {
			mvkEnableFlags(getSection(secIdx), getBitPositionSectionMask(bitIndex));
		} else {
			mvkDisableFlags(getSection(secIdx), getBitPositionSectionMask(bitIndex));
		}

		// Adjust fully disabled tracker
		if (isFullyDisabled(sectionData)) {
			if (secIdx == _fullyDisabledSectionCount) {
				auto secCnt = getSectionCount();
				while (++_fullyDisabledSectionCount < secCnt && isFullyDisabled(getSection(_fullyDisabledSectionCount)));
			}
		} else {
			_fullyDisabledSectionCount = std::min(_fullyDisabledSectionCount, (uint32_t)secIdx);
		}

		// Adjust partially disabled tracker
		if (isFullyEnabled(sectionData)) {
			if (secIdx + 1 == _partiallyDisabledSectionCount) {
				while (--_partiallyDisabledSectionCount > 0 && isFullyEnabled(getSection(_partiallyDisabledSectionCount - 1)));
			}
		} else {
			_partiallyDisabledSectionCount = std::max(_partiallyDisabledSectionCount, (uint32_t)secIdx + 1);
		}
	}

	/** Enables the bit. */
	void enableBit(size_t bitIndex) { setBit(bitIndex, true); }

	/** Enables all bits in the array. */
	void enableAllBits() {
		for (size_t secIdx = 0; secIdx < _partiallyDisabledSectionCount; secIdx++) {
			getSection(secIdx) = FullyEnabledSectionMask;
		}
		_partiallyDisabledSectionCount = 0;
		_fullyDisabledSectionCount = 0;
	}

	/** Disables the bit. */
	void disableBit(size_t bitIndex) { setBit(bitIndex, false); }

	/** Disables all bits in the array. */
	void disableAllBits() {
		size_t secCnt = getSectionCount();
		for (size_t secIdx = _fullyDisabledSectionCount; secIdx < secCnt; secIdx++) {
			getSection(secIdx) = 0;
		}
		_partiallyDisabledSectionCount = (uint32_t)secCnt;
		_fullyDisabledSectionCount = (uint32_t)secCnt;
	}

	/**
	 * Returns the index of the first enabled bit, at or after the specified index.
	 * If no bits are enabled, returns the size() of this bit array.
	 */
	size_t getIndexOfFirstEnabledBit(size_t startIndex = 0) {
		size_t secCnt = getSectionCount();
		size_t secIdx = getIndexOfSection(startIndex);

		// Optimize by skipping all consecutive sections at the beginning that are known to have no enabled bits.
		if (secIdx < _fullyDisabledSectionCount) {
			secIdx = _fullyDisabledSectionCount;
			startIndex = 0;
		}

		// Search all sections at or after the starting index, and if an enabled bit is found, return the index of it.
		while (secIdx < secCnt) {
			size_t lclBitIdx = getIndexOfFirstEnabledBitInSection(getSection(secIdx), getBitIndexInSection(startIndex));
			if (lclBitIdx < SectionBitCount) {
				return (secIdx * SectionBitCount) + lclBitIdx;
			}
			startIndex = 0;
			secIdx++;
		}

		return _bitCount;
	}

	/**
	 * Enumerates the bits, executing a custom function on each bit that is enabled.
	 *
	 * The function to execute is passed a bitIndex parameter which indicates
	 * the index of the bit for which the function is executing.
	 *
	 * The custom function should return true to continue processing further bits, or false
	 * to stop processing further bits. This function returns false if any of the invocations
	 * of the custom function halted further invocations, and returns true otherwise.
	 */
	bool enumerateEnabledBits(std::function<bool(size_t bitIndex)> func) {
		for (size_t bitIdx = getIndexOfFirstEnabledBit();
			 bitIdx < _bitCount;
			 bitIdx = getIndexOfFirstEnabledBit(++bitIdx)) {

			if ( !func(bitIdx) ) { return false; }
		}
		return true;
	}

	/** Returns the number of bits in this array. */
	size_t size() const { return _bitCount; }

	/** Returns whether this array is empty. */
	bool empty() const { return _bitCount == 0; }

	/**
	 * Resize this array to the specified number of bits.
	 *
	 * The value of existing bits that fit within the new size are retained, and any
	 * new bits that are added to accommodate the new size are set to the given value.
	 *
	 * If the new size is larger than the existing size, new memory is allocated.
	 * If the new size is less than the existing size, consumed memory is retained.
	 */
	void resize(size_t size, bool val = false) {
		assert(size < SectionBitCount * std::numeric_limits<uint32_t>::max());	// Limited by _partially/fullyDisabledSectionCount

		if (size == _bitCount) { return; }

		size_t oldBitCnt = _bitCount;
		size_t oldSecCnt = getSectionCount();
		size_t oldEndBitCnt = oldSecCnt * SectionBitCount;

		_bitCount = size;	// After here, functions refer to new data characteristics.

		// If the number of data sections is not growing, we retain the existing data memory,
		// to avoid having to reallocate if this array is resized larger in the future.
		// If the number of data sections is growing, we need to expand memory.
		size_t newSecCnt = getSectionCount();
		if (newSecCnt == oldSecCnt) {
			// The number of data sections is staying the same.
			// Keep the existing data, but fill any bits in the last section
			// that were beyond the old bit count with the new initial value.
			for (size_t bitIdx = oldBitCnt; bitIdx < _bitCount; bitIdx++) { setBit(bitIdx, val); }
		} else if (newSecCnt > oldSecCnt) {
			// The number of data sections is growing.
			// Reallocate new memory to keep the existing contents.
			_data = (uint64_t*)realloc(_data, newSecCnt * SectionByteCount);

			// Fill any bits in the last section that were beyond the old bit count with the fill value.
			for (size_t bitIdx = oldBitCnt; bitIdx < oldEndBitCnt; bitIdx++) { setBit(bitIdx, val); }

			// Fill the additional sections with the fill value.
			uint64_t* pExtraData = &_data[oldSecCnt];
			memset(pExtraData, val ? (uint8_t)FullyEnabledSectionMask : 0, (newSecCnt - oldSecCnt) * SectionByteCount);

			// If the additional sections have been cleared, extend the associated trackers.
			if ( !val ) {
				if (_partiallyDisabledSectionCount == oldSecCnt) { _partiallyDisabledSectionCount = (uint32_t)newSecCnt; }
				if (_fullyDisabledSectionCount == oldSecCnt) { _fullyDisabledSectionCount = (uint32_t)newSecCnt; }
			}
		} else {
			// The number of data sections is shrinking.
			// Retain existing allocation, but ensure these values still fit.
			_partiallyDisabledSectionCount = std::min(_partiallyDisabledSectionCount, (uint32_t)newSecCnt);
			_fullyDisabledSectionCount = std::min(_fullyDisabledSectionCount, (uint32_t)newSecCnt);
		}
	}

	/** Resets back to zero size and frees all data. */
	void reset() {
		free(_data);
		_data = nullptr;
		_bitCount = 0;
		_partiallyDisabledSectionCount = 0;
		_fullyDisabledSectionCount = 0;
	}

	/** Constructs an instance for the specified number of bits, and sets the initial value of all the bits. */
	MVKBitArray(size_t size = 0, bool val = false) { resize(size, val); }

	MVKBitArray(const MVKBitArray& other) {
		resize(other._bitCount);
		memcpy(_data, other._data, getSectionCount() * SectionByteCount);
	}

	MVKBitArray& operator=(const MVKBitArray& other) {
		resize(other._bitCount);
		memcpy(_data, other._data, getSectionCount() * SectionByteCount);
		return *this;
	}

	~MVKBitArray() { reset(); }

protected:

	uint64_t& getSection(size_t secIdx) { return _data[secIdx]; }
	size_t getSectionCount() const { return _bitCount ? getIndexOfSection(_bitCount - 1) + 1 : 0; }

	static size_t getIndexOfSection(size_t bitIndex) { return bitIndex / SectionBitCount; }
	static uint8_t getBitIndexInSection(size_t bitIndex) { return bitIndex & (SectionBitCount - 1); }
	static bool isFullyEnabled(uint64_t sectionData) { return sectionData == FullyEnabledSectionMask; }
	static bool isFullyDisabled(uint64_t sectionData) { return sectionData == 0; }

	// Returns a section mask containing a single 1 value in the bit in the section that
	// corresponds to the specified global bit index, and 0 values in all other bits.
	static uint64_t getBitPositionSectionMask(size_t bitIndex) {
		return (uint64_t)1U << ((SectionBitCount - 1) - getBitIndexInSection(bitIndex));
	}

	// Returns the local index of the first enabled bit in the section, starting from the highest order bit.
	// Disables all bits ahead of the start bit so they will be ignored, then counts the number of zeros
	// ahead of the set bit. If there are no enabled bits, returns the number of bits in a section.
	static uint8_t getIndexOfFirstEnabledBitInSection(uint64_t section, uint8_t lclStartBitIndex) {
		uint64_t lclStartMask = FullyEnabledSectionMask;
		lclStartMask >>= lclStartBitIndex;
		section &= lclStartMask;
		return section ? __builtin_clzll(section) : SectionBitCount;
	}

	static constexpr size_t SectionBitCount = 64;
	static constexpr size_t SectionByteCount = SectionBitCount / 8;
	static constexpr uint64_t FullyEnabledSectionMask = ~static_cast<uint64_t>(0);

	uint64_t* _data = nullptr;
	size_t _bitCount = 0;
	uint32_t _partiallyDisabledSectionCount = 0;	// Tracks where to stop filling when enabling all bits
	uint32_t _fullyDisabledSectionCount = 0;		// Tracks where to start looking for enabled bits
};

#pragma mark - MVKStaticBitArray

/**
 * A pointer to a bit in a bit set
 * Decays into a bit offset, but if used directly with another bit set of the same type, can save putting the pieces together only to take them apart again
 */
template <typename Bits>
struct MVKBitPointer {
	std::size_t wordOffset;
	std::size_t bitOffset;
	operator std::size_t() const { return sizeof(Bits) * CHAR_BIT * wordOffset + bitOffset; }
};

/** Iterate over the bits set in `bits`, adding the offset `wordOffset` to each */
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
 * Iterate over the bits set in an array of `Count` numbers
 * This iterator will yield a `MVKSetBitIterator` for each element of the array
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
	/** Construct from a raw bit array */
	static constexpr MVKSmallStaticBitSet fromBits(Base bits) { return { bits }; }
	/** Construct from a range of set bits */
	static constexpr MVKSmallStaticBitSet range(std::size_t begin, std::size_t end) {
		MVKSmallStaticBitSet res;
		if (end > begin) [[likely]] {
			std::size_t numBits = sizeof(Base) * CHAR_BIT;
			res._bits = static_cast<Base>(~static_cast<Base>(0)) >> ((numBits - end) % numBits);
			res._bits &= static_cast<Base>(~static_cast<Base>(0)) << begin;
		}
		return res;
	}

	/** Get the raw bit array from the bitset */
	constexpr Base bits() const { return _bits; }
	/** For C++ for-in */
	constexpr MVKSetBitIterator<Base> begin() const { return { _bits, 0 }; }
	/** For C++ for-in */
	constexpr MVKSetBitIterator<Base> end() const { return { 0, 0 }; }
	/**
	 * Get an iterator over iterators over the bits set in the bitset
	 *
	 * This is a convenience function for API compatibility with MVKLargeStaticBitSet.  If you know your bit set is small, you can iterate over its bits directly.
	 */
	constexpr MVKSetBitIteratorIterator<Base> setBitsList() const { return { &_bits, 0, 1 }; }

	/** Remove all bits from the set */
	constexpr void reset() { _bits = 0; }
	/** Remove all bits from the set, then add all the bits in the range `[begin, end)` */
	constexpr void resetToRange(std::size_t begin, std::size_t end) { *this = range(begin, end); }
	/** Set all bits in the given range */
	constexpr void setRange(std::size_t begin, std::size_t end) { *this |= range(begin, end); }
	/** Clear all bits in the given range */
	constexpr void clearRange(std::size_t begin, std::size_t end) { clearAllIn(range(begin, end)); }
	/** Set or clear the given bit */
	constexpr void set(std::size_t bit, bool value = true) {
		Base flag = static_cast<Base>(1) << bit;
		_bits = value ? _bits | flag : _bits & ~flag;
	}
	/** Set or clear the given bit */
	constexpr void set(MVKBitPointer<Base> bit, bool value = true) { set(bit.bitOffset, value); }
	/** Convenience function for set(bit, false) */
	constexpr void clear(MVKBitPointer<Base> bit) { set(bit, false); }
	/** Convenience function for set(bit, false) */
	constexpr void clear(std::size_t bit) { set(bit, false); }
	/** Check if the given bit is set */
	constexpr bool get(std::size_t bit) const { return (_bits >> bit) & 1; }
	/** Check if the given bit is set */
	constexpr bool get(MVKBitPointer<Base> bit) const { return get(bit.bitOffset); }
	/** Check if any bits in the array are set */
	constexpr bool areAnyBitsSet() const { return _bits != 0; }
	/** Check if all bits in the array are unset */
	constexpr bool areAllBitsClear() const { return !areAnyBitsSet(); }
	/** Get the intersection of this and another set */
	constexpr MVKSmallStaticBitSet operator&(MVKSmallStaticBitSet other) const { return MVKSmallStaticBitSet(_bits & other._bits); }
	/** Get the union of this and another set */
	constexpr MVKSmallStaticBitSet operator|(MVKSmallStaticBitSet other) const { return MVKSmallStaticBitSet(_bits | other._bits); }
	/** Intersect this set with the given set */
	constexpr MVKSmallStaticBitSet& operator&=(MVKSmallStaticBitSet other) { *this = (*this & other); return *this; }
	/** Union this set with the given set */
	constexpr MVKSmallStaticBitSet& operator|=(MVKSmallStaticBitSet other) { *this = (*this | other); return *this; }
	/** Check if this set is equal to the given set */
	constexpr bool operator==(MVKSmallStaticBitSet other) const { return _bits == other._bits; }
	/** Check if this set is not equal to the given set */
	constexpr bool operator!=(MVKSmallStaticBitSet other) const { return !(*this == other); }
	/** Check if there are any elements in the intersection between this and another set */
	constexpr bool containsAny(MVKSmallStaticBitSet other) const { return (*this & other).any(); }
	/** Check if this set is a superset of the given set */
	constexpr bool containsAll(MVKSmallStaticBitSet other) const { return (*this & other) == other; }
	/** Subtract the elements in the given set from this one */
	constexpr void clearAllIn(MVKSmallStaticBitSet other) { _bits &= ~other._bits; }
	/** Subtract the elements in the given set from this one */
	constexpr MVKSmallStaticBitSet clearingAllIn(MVKSmallStaticBitSet other) const { return MVKSmallStaticBitSet(_bits & ~other._bits); }
};

template <uint32_t Bits>
class MVKLargeStaticBitSet {
	static constexpr std::size_t ElemSize = 8 * sizeof(std::size_t);
	static constexpr std::size_t ArrayLen = (Bits + ElemSize - 1) / ElemSize;
	std::size_t bits[ArrayLen];

	template <typename Fn>
	constexpr void applyToRange(std::size_t begin, std::size_t end, Fn&& fn) {
		if (begin >= end) [[unlikely]]
			return;
		std::size_t lo = begin / ElemSize;
		std::size_t hi = (end - 1) / ElemSize;
		std::size_t masklo = ~static_cast<std::size_t>(0) << (begin % ElemSize);
		std::size_t maskhi = ~static_cast<std::size_t>(0) >> ((ElemSize - end) % ElemSize);
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

public:
	/** Construct an empty bitset */
	constexpr MVKLargeStaticBitSet(): bits{} {}

	/** Construct from a range of set bits */
	static constexpr MVKLargeStaticBitSet range(std::size_t begin, std::size_t end) {
		MVKLargeStaticBitSet res;
		res.setRange(begin, end);
		return res;
	}

	/** Get an iterator over iterators over the bits set in the bitset */
	constexpr MVKSetBitIteratorIterator<std::size_t> setBitsList() const { return { bits, 0, ArrayLen }; }

	/** Remove all bits from the set */
	constexpr void reset() {
		for (uint32_t i = 0; i < ArrayLen; i++)
			bits[i] = 0;
	}

	/** Remove all bits from the set, then add all the bits in the range `[begin, end)` */
	constexpr void resetToRange(std::size_t begin, std::size_t end) {
		*this = range(begin, end);
	}

	/** Set all bits in the given range */
	constexpr void setRange(std::size_t begin, std::size_t end) {
		applyToRange(begin, end, [](std::size_t& val, std::size_t mask){ val |= mask; });
	}

	/** Clear all bits in the given range */
	constexpr void clearRange(std::size_t begin, std::size_t end) {
		applyToRange(begin, end, [](std::size_t& val, std::size_t mask){ val &= ~mask; });
	}

	/** Set or clear the given bit */
	constexpr void set(MVKBitPointer<std::size_t> bit, bool value = true) {
		std::size_t& word = bits[bit.wordOffset];
		std::size_t flag = static_cast<std::size_t>(1ull << bit.bitOffset);
		word = value ? word | flag : word & ~flag;
	}
	/** Set or clear the given bit */
	constexpr void set(std::size_t bit, bool value = true) { set({ bit / ElemSize, bit % ElemSize }, value); }
	/** Convenience function for set(bit, false) */
	constexpr void clear(MVKBitPointer<std::size_t> bit) { set(bit, false); }
	/** Convenience function for set(bit, false) */
	constexpr void clear(std::size_t bit) { set(bit, false); }
	/** Check if the given bit is set */
	constexpr bool get(MVKBitPointer<std::size_t> bit) const { return (bits[bit.wordOffset] >> bit.bitOffset) & 1; }
	constexpr bool get(std::size_t bit) const { return get({ bit / ElemSize, bit % ElemSize }); }
	/** Check if there are any bits in the set */
	constexpr bool any() const {
		bool any = false;
		for (uint32_t i = 0; i < ArrayLen; i++)
			any |= bits[i] != 0;
		return any;
	}
	/** Check if the set is empty */
	constexpr bool empty() const { return !any(); }
	/** Intersect this set with the given set */
	constexpr MVKLargeStaticBitSet operator&=(const MVKLargeStaticBitSet& other) {
		for (uint32_t i = 0; i < ArrayLen; i++)
			bits[i] &= other.bits[i];
		return *this;
	}
	/** Union this set with the given set */
	constexpr MVKLargeStaticBitSet operator|=(const MVKLargeStaticBitSet& other) {
		for (uint32_t i = 0; i < ArrayLen; i++)
			bits[i] |= other.bits[i];
		return *this;
	}
	/** Check if this set is equal to the given set */
	constexpr bool operator==(const MVKLargeStaticBitSet& other) const {
		bool eq = true;
		for (uint32_t i = 0; i < ArrayLen; i++)
			eq |= bits[i] == other.bits[i];
		return eq;
	}
	/** Get the intersection of this and another set */
	constexpr MVKLargeStaticBitSet operator&(const MVKLargeStaticBitSet& other) const { MVKLargeStaticBitSet res = *this; return res &= other; }
	/** Get the union of this and another set */
	constexpr MVKLargeStaticBitSet operator|(const MVKLargeStaticBitSet& other) const { MVKLargeStaticBitSet res = *this; return res |= other; }
	/** Check if this set is not equal to the given set */
	constexpr bool operator!=(const MVKLargeStaticBitSet& other) const { return !(*this == other); }
	/** Check if there are any elements in the intersection between this and another set */
	constexpr bool containsAny(const MVKLargeStaticBitSet& other) const {
		bool found = false;
		for (uint32_t i = 0; i < ArrayLen; i++)
			found |= (bits[i] & other.bits[i]) != 0;
		return found;
	}
	/** Check if this set is a superset of the given set */
	constexpr bool containsAll(const MVKLargeStaticBitSet& other) const {
		bool check = true;
		for (uint32_t i = 0; i < ArrayLen; i++)
			check &= (bits[i] & other.bits[i]) == other.bits[i];
		return check;
	}
	/** Subtract the elements in the given set from this one */
	constexpr void clearAllIn(const MVKLargeStaticBitSet& other) {
		for (uint32_t i = 0; i < ArrayLen; i++)
			bits[i] &= ~other.bits[i];
	}
	/** Subtract the elements in the given set from this one */
	constexpr MVKLargeStaticBitSet clearingAllIn(const MVKLargeStaticBitSet& other) const {
		MVKLargeStaticBitSet res = *this;
		res.clearAllIn(other);
		return res;
	}
};

/**
 * A set for storing existence of bits in the known range `0..<Bits`
 * Like a std::bitset but supports iterating over the set bits
 */
template <uint32_t Bits>
using MVKStaticBitSet = std::conditional_t<(Bits > 32), MVKLargeStaticBitSet<Bits>, MVKSmallStaticBitSet<std::conditional_t<(Bits > 16), uint32_t, uint16_t>>>;
