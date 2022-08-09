/*
 * MVKBitArray.h
 *
 * Copyright (c) 2020-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#pragma mark -
#pragma mark MVKBitArray

/** Represents an array of bits, optimized for reduced storage and fast scanning for bits that are set. */
class MVKBitArray {

	static constexpr size_t SectionMaskSize = 6;	// 64 bits
	static constexpr size_t SectionBitCount = (size_t)1U << SectionMaskSize;
	static constexpr size_t SectionByteCount = SectionBitCount / 8;
	static constexpr uint64_t SectionMask = SectionBitCount - 1;

public:

	/**
	 * Returns the value of the bit, and optionally clears that bit if it was set.
	 * Returns false if the bitIndex is beyond the size of this array, returns false.
	 */
	bool getBit(size_t bitIndex, bool shouldClear = false) {
		if (bitIndex >= _bitCount) { return false; }
		bool val = mvkIsAnyFlagEnabled(getSection(getIndexOfSection(bitIndex)), getSectionSetMask(bitIndex));
		if (shouldClear && val) { clearBit(bitIndex); }
		return val;
	}

	/** Sets the value of the bit to the val (or to 1 by default). */
	void setBit(size_t bitIndex, bool val = true) {
		if (bitIndex >= _bitCount) { return; }

		size_t secIdx = getIndexOfSection(bitIndex);
		if (val) {
			mvkEnableFlags(getSection(secIdx), getSectionSetMask(bitIndex));
			if (secIdx < _clearedSectionCount) { _clearedSectionCount = secIdx; }
		} else {
			mvkDisableFlags(getSection(secIdx), getSectionSetMask(bitIndex));
			if (secIdx == _clearedSectionCount && !getSection(secIdx)) { _clearedSectionCount++; }
			_lowestNeverClearedBitIndex = std::max(_lowestNeverClearedBitIndex, bitIndex + 1);
		}
	}

	/** Sets the value of the bit to 0. */
	void clearBit(size_t bitIndex) { setBit(bitIndex, false); }

	/** Sets all bits in the array to 1. */
	void setAllBits() {
		// Nothing to do if no bits have been cleared (also ensure _lowestNeverClearedBitIndex doesn't go negative)
		if (_lowestNeverClearedBitIndex) {
			size_t endSecIdx = getIndexOfSection(_lowestNeverClearedBitIndex - 1);
			for (size_t secIdx = 0; secIdx <= endSecIdx; secIdx++) {
				getSection(secIdx) = ~0;
			}
		}
		_clearedSectionCount = 0;
		_lowestNeverClearedBitIndex = 0;
	}

	/** Clears all bits in the array to 0. */
	void clearAllBits() {
		size_t secCnt = getSectionCount();
		while (_clearedSectionCount < secCnt) {
			getSection(_clearedSectionCount++) = 0;
		}
		_lowestNeverClearedBitIndex = _bitCount;
	}

	/**
	 * Returns the index of the first bit that is set, at or after the specified index,
	 * and optionally clears that bit. If no bits are set, returns the size() of this bit array.
	 */
	size_t getIndexOfFirstSetBit(size_t startIndex, bool shouldClear) {
		size_t startSecIdx = std::max(getIndexOfSection(startIndex), _clearedSectionCount);
		size_t bitIdx = startSecIdx << SectionMaskSize;
		size_t secCnt = getSectionCount();
		for (size_t secIdx = startSecIdx; secIdx < secCnt; secIdx++) {
			size_t lclBitIdx = getIndexOfFirstSetBitInSection(getSection(secIdx), getBitIndexInSection(startIndex));
			bitIdx += lclBitIdx;
			if (lclBitIdx < SectionBitCount) {
				if (startSecIdx == _clearedSectionCount && !getSection(startSecIdx)) { _clearedSectionCount = secIdx; }
				if (shouldClear) { clearBit(bitIdx); }
				return std::min(bitIdx, _bitCount);
			}
		}
		return std::min(bitIdx, _bitCount);
	}

	/**
	 * Returns the index of the first bit that is set, at or after the specified index.
	 * If no bits are set, returns the size() of this bit array.
	 */
	size_t getIndexOfFirstSetBit(size_t startIndex) {
		return getIndexOfFirstSetBit(startIndex, false);
	}

	/**
	 * Returns the index of the first bit that is set and optionally clears that bit.
	 * If no bits are set, returns the size() of this bit array.
	 */
	size_t getIndexOfFirstSetBit(bool shouldClear) {
		return getIndexOfFirstSetBit(0, shouldClear);
	}

	/**
	 * Returns the index of the lowest bit that has never been cleared since the last time all the bits were set or cleared.
	 * In other words, this bit, and all above it, have never been cleared since the last time they were all set or cleared.
	 */
	size_t getLowestNeverClearedBitIndex() { return _lowestNeverClearedBitIndex; }

	/**
	 * Returns the index of the first bit that is set.
	 * If no bits are set, returns the size() of this bit array.
	 */
	size_t getIndexOfFirstSetBit() {
		return getIndexOfFirstSetBit(0, false);
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
	 *
	 * If shouldClear is true, each enabled bit is cleared before the custom function executes.
	 */
	bool enumerateEnabledBits(bool shouldClear, std::function<bool(size_t bitIndex)> func) {
		for (size_t bitIdx = getIndexOfFirstSetBit(shouldClear);
			 bitIdx < _bitCount;
			 getIndexOfFirstSetBit(++bitIdx, shouldClear)) {

			if ( !func(bitIdx) ) { return false; }
		}
		return true;
	}

	/** Returns the number of bits in this array. */
	size_t size() const { return _bitCount; }

	/** Returns whether this array is empty. */
	bool empty() const { return !_bitCount; }

	/**
	 * Resize this array to the specified number of bits.
	 *
	 * The value of existing bits that fit within the new size are retained, and any
	 * new bits that are added to accommodate the new size are set to the given value.
	 *
	 * If the new size is larger than the existing size, new memory may be allocated.
	 * If the new size is less than the existing size, consumed memory is retained
	 * unless the size is set to zero.
	 */
	void resize(size_t size, bool val = false) {
		if (size == _bitCount) { return; }

		size_t oldBitCnt = _bitCount;
		size_t oldSecCnt = getSectionCount();
		size_t oldEndBitCnt = oldSecCnt << SectionMaskSize;

		// Some magic here. If we need only one section, _data is used as that section,
		// and it will be stomped on if we reallocate, so we cache it here.
		uint64_t* oldData = _data;
		uint64_t* pOldData = oldSecCnt > 1 ? oldData : (uint64_t*)&oldData;

		_bitCount = size;

		size_t newSecCnt = getSectionCount();
		if (newSecCnt == 0) {
			// Clear out the existing data
			if (oldSecCnt > 1) { free(pOldData); }
			_data = 0;
			_clearedSectionCount = 0;
			_lowestNeverClearedBitIndex = 0;
		} else if (newSecCnt == oldSecCnt) {
			// Keep the existing data, but fill any bits in the last section
			// that were beyond the old bit count with the new initial value.
			for (size_t bitIdx = oldBitCnt; bitIdx < oldEndBitCnt; bitIdx++) { setBit(bitIdx, val); }
		} else if (newSecCnt > oldSecCnt) {
			size_t oldByteCnt = oldSecCnt * SectionByteCount;
			size_t newByteCnt = newSecCnt * SectionByteCount;

			// If needed, allocate new memory.
			if (newSecCnt > 1) { _data = (uint64_t*)malloc(newByteCnt); }

			// Fill the new memory with the new initial value, copy the old contents to
			// the new memory, fill any bits in the old last section that were beyond
			// the old bit count with the new initial value, and remove the old memory.
			uint64_t* pNewData = getData();
			memset(pNewData, val ? ~0 : 0, newByteCnt);
			memcpy(pNewData, pOldData, oldByteCnt);
			for (size_t bitIdx = oldBitCnt; bitIdx < oldEndBitCnt; bitIdx++) { setBit(bitIdx, val); }
			if (oldSecCnt > 1) { free(pOldData); }
			if (!val) { _lowestNeverClearedBitIndex = _bitCount; }	// Cover additional sections

			// If the entire old array and the new array are cleared, move the uncleared indicator to the new end.
			if (_clearedSectionCount == oldSecCnt && !val) { _clearedSectionCount = newSecCnt; }
		}
		// If we shrank, ensure this value still fits
		if (_lowestNeverClearedBitIndex > _bitCount) { _lowestNeverClearedBitIndex = _bitCount; }
	}

	/** Constructs an instance for the specified number of bits, and sets the initial value of all the bits. */
	MVKBitArray(size_t size = 0, bool val = false) { resize(size, val); }

	MVKBitArray(const MVKBitArray& other) {
		resize(other._bitCount);
		memcpy(getData(), other.getData(), getSectionCount() * SectionByteCount);
		_clearedSectionCount = other._clearedSectionCount;
		_lowestNeverClearedBitIndex = other._lowestNeverClearedBitIndex;
	}

	MVKBitArray& operator=(const MVKBitArray& other) {
		resize(0);		// Clear out the old memory
		resize(other._bitCount);
		memcpy(getData(), other.getData(), getSectionCount() * SectionByteCount);
		_clearedSectionCount = other._clearedSectionCount;
		_lowestNeverClearedBitIndex = other._lowestNeverClearedBitIndex;
		return *this;
	}

	~MVKBitArray() { resize(0); }

protected:

	// Returns a pointer do the data.
	// Some magic here. If we need only one section, _data is used as that section.
	uint64_t* getData() const {
		return getSectionCount() > 1 ? _data : (uint64_t*)&_data;
	}

	// Returns a reference to the section.
	uint64_t& getSection(size_t secIdx) {
		return getData()[secIdx];
	}

	// Returns the number of sections.
	size_t getSectionCount() const {
		return _bitCount ? getIndexOfSection(_bitCount - 1) + 1 : 0;
	}

	// Returns the index of the section that contains the specified bit.
	static size_t getIndexOfSection(size_t bitIndex) {
		return bitIndex >> SectionMaskSize;
	}

	// Converts the bit index to a local bit index within a section, and returns that local bit index.
	static size_t getBitIndexInSection(size_t bitIndex) {
		return bitIndex & SectionMask;
	}

	// Returns a section mask containing a single 1 value in the bit in the section that
	// corresponds to the specified global bit index, and 0 values in all other bits.
	static uint64_t getSectionSetMask(size_t bitIndex) {
		return (uint64_t)1U << ((SectionBitCount - 1) - getBitIndexInSection(bitIndex));
	}

	// Returns the local index of the first set bit in the section, starting from the highest order bit.
	// Clears all bits ahead of the start bit so they will be ignored, then counts the number of zeros
	// ahead of the set bit. If there are no set bits, returns the number of bits in a section.
	static size_t getIndexOfFirstSetBitInSection(uint64_t section, size_t lclStartBitIndex) {
		uint64_t lclStartMask = ~(uint64_t)0;
		lclStartMask >>= lclStartBitIndex;
		section &= lclStartMask;
		return section ? __builtin_clzll(section) : SectionBitCount;
	}

	uint64_t* _data = nullptr;
	size_t _bitCount = 0;
	size_t _clearedSectionCount = 0;			// Tracks where to start looking for bits that are set
	size_t _lowestNeverClearedBitIndex = 0;		// Tracks the lowest bit that has never been cleared
};
