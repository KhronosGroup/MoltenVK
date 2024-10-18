/*
 * MVKBitArray.h
 *
 * Copyright (c) 2020-2024 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include <functional>


#pragma mark -
#pragma mark MVKBitArray

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

	/** Returns the index of the first bit that is enabled, at or after the specified index. */
	size_t getIndexOfFirstEnabledBit(size_t startIndex = 0) {
		size_t secIdx = getIndexOfSection(startIndex);
		if (secIdx < _fullyDisabledSectionCount) {
			secIdx = _fullyDisabledSectionCount;
			startIndex = 0;
		}
		if (secIdx >= getSectionCount()) { return _bitCount; }
		return std::min((secIdx * SectionBitCount) + getIndexOfFirstEnabledBitInSection(getSection(secIdx), getBitIndexInSection(startIndex)), _bitCount);
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
