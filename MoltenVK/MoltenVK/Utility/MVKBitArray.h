/*
 * MVKBitArray.h
 *
 * Copyright (c) 2020-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
	static constexpr size_t SectionBitCount = 1U << SectionMaskSize;
	static constexpr size_t SectionByteCount = SectionBitCount / 8;
	static constexpr uint64_t SectionMask = SectionBitCount - 1;

public:

	/** Returns the value of the bit. */
	inline bool getBit(size_t bitIndex) {
		return mvkIsAnyFlagEnabled(_pSections[getIndexOfSection(bitIndex)], getSectionSetMask(bitIndex));
	}

	/** Sets the value of the bit to 1. */
	inline void setBit(size_t bitIndex) {
		size_t secIdx = getIndexOfSection(bitIndex);
		mvkEnableFlags(_pSections[secIdx], getSectionSetMask(bitIndex));

		if (secIdx < _minUnclearedSectionIndex) { _minUnclearedSectionIndex = secIdx; }
	}

	/** Sets the value of the bit to 0. */
	inline void clearBit(size_t bitIndex) {
		size_t secIdx = getIndexOfSection(bitIndex);
		mvkDisableFlags(_pSections[secIdx], getSectionSetMask(bitIndex));

		if (secIdx == _minUnclearedSectionIndex && !_pSections[secIdx]) { _minUnclearedSectionIndex++; }
	}

	/** Sets the value of the bit to the value. */
	inline void setBit(size_t bitIndex, bool val) {
		if (val) {
			setBit(bitIndex);
		} else {
			clearBit(bitIndex);
		}
	}

	/** Sets all bits in the array to 1. */
	inline void setAllBits() { setAllSections(~0); }

	/** Clears all bits in the array to 0. */
	inline void clearAllBits() { setAllSections(0); }

	/**
	 * Returns the index of the first bit that is set, at or after the specified index,
	 * and optionally clears that bit. If no bits are set, returns the size() of this bit array.
	 */
	size_t getIndexOfFirstSetBit(size_t startIndex, bool shouldClear) {
		size_t startSecIdx = std::max(getIndexOfSection(startIndex), _minUnclearedSectionIndex);
		size_t bitIdx = startSecIdx << SectionMaskSize;
		size_t secCnt = getSectionCount();
		for (size_t secIdx = startSecIdx; secIdx < secCnt; secIdx++) {
			size_t lclBitIdx = getIndexOfFirstSetBitInSection(_pSections[secIdx], getBitIndexInSection(startIndex));
			bitIdx += lclBitIdx;
			if (lclBitIdx < SectionBitCount) {
				if (startSecIdx == _minUnclearedSectionIndex && !_pSections[startSecIdx]) { _minUnclearedSectionIndex = secIdx; }
				if (shouldClear) { clearBit(bitIdx); }
				return bitIdx;
			}
		}
		return std::min(bitIdx, _bitCount);
	}

	/**
	 * Returns the index of the first bit that is set, at or after the specified index.
	 * If no bits are set, returns the size() of this bit array.
	 */
	inline size_t getIndexOfFirstSetBit(size_t startIndex) {
		return getIndexOfFirstSetBit(startIndex, false);
	}

	/**
	 * Returns the index of the first bit that is set and optionally clears that bit.
	 * If no bits are set, returns the size() of this bit array.
	 */
	inline size_t getIndexOfFirstSetBit(bool shouldClear) {
		return getIndexOfFirstSetBit(0, shouldClear);
	}

	/**
	 * Returns the index of the first bit that is set.
	 * If no bits are set, returns the size() of this bit array.
	 */
	inline size_t getIndexOfFirstSetBit() {
		return getIndexOfFirstSetBit(0, false);
	}

	/** Returns the number of bits in this array. */
	inline size_t size() { return _bitCount; }

	/** Returns whether this array is empty. */
	inline bool empty() { return !_bitCount; }

	/** Constructs an instance for the specified number of bits, and sets the initial value of all the bits. */
	MVKBitArray(size_t size, bool val = false) {
		_bitCount = size;
		_pSections = _bitCount ? (uint64_t*)malloc(getSectionCount() * SectionByteCount) : nullptr;
		if (val) {
			setAllBits();
		} else {
			clearAllBits();
		}
	}

	~MVKBitArray() { free(_pSections); }

protected:

	// Returns the number of sections.
	inline size_t getSectionCount() {
		return _bitCount ? getIndexOfSection(_bitCount - 1) + 1 : 0;
	}

	// Returns the index of the section that contains the specified bit.
	static inline size_t getIndexOfSection(size_t bitIndex) {
		return bitIndex >> SectionMaskSize;
	}

	// Converts the bit index to a local bit index within a section, and returns that local bit index.
	static inline size_t getBitIndexInSection(size_t bitIndex) {
		return bitIndex & SectionMask;
	}

	// Returns a section mask containing a single 1 value in the bit in the section that
	// corresponds to the specified global bit index, and 0 values in all other bits.
	static inline uint64_t getSectionSetMask(size_t bitIndex) {
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

	// Sets the content of all sections to the value
	void setAllSections(uint64_t sectionValue) {
		size_t secCnt = getSectionCount();
		for (size_t secIdx = 0; secIdx < secCnt; secIdx++) {
			_pSections[secIdx] = sectionValue;
		}
		_minUnclearedSectionIndex = sectionValue ? 0 : secCnt;
	}

	uint64_t* _pSections;
	size_t _bitCount;
	size_t _minUnclearedSectionIndex;	// Tracks where to start looking for bits that are set
};
