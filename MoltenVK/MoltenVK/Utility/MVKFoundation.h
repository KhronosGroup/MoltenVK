/*
 * MVKFoundation.h
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#include <vulkan/vulkan.h>
#include "MVKLogging.h"
#include <algorithm>
#include <simd/simd.h>


#pragma mark Math

/**
 * The following constants are used to indicate values that have no defined limit.
 * They are ridiculously large numbers, but low enough to be safely used as both
 * uint and int values without risking overflowing between positive and negative values.
 */
static int32_t kMVKUndefinedLargeNegativeInt32 = std::numeric_limits<int32_t>::min() / 2;
static int32_t kMVKUndefinedLargePositiveInt32 = std::numeric_limits<int32_t>::max() / 2;
static uint32_t kMVKUndefinedLargeUInt32 = kMVKUndefinedLargePositiveInt32;
static int64_t kMVKUndefinedLargeNegativeInt64 = std::numeric_limits<int64_t>::min() / 2;
static int64_t kMVKUndefinedLargePositiveInt64 = std::numeric_limits<int64_t>::max() / 2;
static uint64_t kMVKUndefinedLargeUInt64 = kMVKUndefinedLargePositiveInt64;

// Common scaling multipliers
#define KIBI		(1024)
#define MEBI		(KIBI * KIBI)
#define GIBI        (KIBI * MEBI)

/** Represents a non-existent index. */
static const int kMVKIndexNone = -1;

/** A type definition for 16-bit half-float values. */
typedef uint16_t MVKHalfFloat;

/** A representation of the value of 1.0 as a 16-bit half-float. */
#define kHalfFloat1	0x3C00

/** Common header for many standard Vulkan API structures. */
typedef struct {
	VkStructureType sType;
	const void* pNext;
} MVKVkAPIStructHeader;


#pragma mark -
#pragma mark Vertex content structures

/** 2D vertex position and texcoord content. */
typedef struct {
	simd::float2 position;
	simd::float2 texCoord;
} MVKVertexPosTex;


#pragma mark -
#pragma mark Vulkan support

/** Tracks the Vulkan command currently being used. */
typedef enum {
    kMVKCommandUseNone,                     /**< No use defined. */
    kMVKCommandUseQueueSubmit,              /**< vkQueueSubmit. */
    kMVKCommandUseQueuePresent,             /**< vkQueuePresentKHR. */
    kMVKCommandUseQueueWaitIdle,            /**< vkQueueWaitIdle. */
    kMVKCommandUseDeviceWaitIdle,           /**< vkDeviceWaitIdle. */
    kMVKCommandUseBeginRenderPass,          /**< vkCmdBeginRenderPass. */
    kMVKCommandUseNextSubpass,              /**< vkCmdNextSubpass. */
    kMVKCommandUsePipelineBarrier,          /**< vkCmdPipelineBarrier. */
    kMVKCommandUseBlitImage,                /**< vkCmdBlitImage. */
    kMVKCommandUseCopyImage,                /**< vkCmdCopyImage. */
    kMVKCommandUseResolveImage,             /**< vkCmdResolveImage - resolve stage. */
    kMVKCommandUseResolveExpandImage,       /**< vkCmdResolveImage - expand stage. */
    kMVKCommandUseResolveCopyImage,         /**< vkCmdResolveImage - expand stage. */
    kMVKCommandUseCopyBuffer,               /**< vkCmdCopyBuffer. */
    kMVKCommandUseCopyBufferToImage,        /**< vkCmdCopyBufferToImage. */
    kMVKCommandUseCopyImageToBuffer,        /**< vkCmdCopyImageToBuffer. */
    kMVKCommandUseFillBuffer,               /**< vkCmdFillBuffer. */
    kMVKCommandUseUpdateBuffer,             /**< vkCmdUpdateBuffer. */
    kMVKCommandUseClearColorImage,          /**< vkCmdClearColorImage. */
    kMVKCommandUseClearDepthStencilImage,   /**< vkCmdClearDepthStencilImage. */
    kMVKCommandUseResetQueryPool,           /**< vkCmdResetQueryPool. */
	kMVKCommandUseDispatch,                 /**< vkCmdDispatch. */
} MVKCommandUse;

/**
 * Copies the name of the specified VkResult code to the specified string.
 *
 * Returns a pointer to that string. 
 */
#define MVKResultNameMaxLen		64
char* mvkResultName(VkResult vkResult, char* name);

/**
 * Notifies the app of an error code and error message, via the following methods:
 *
 * - Logs the error code and message to the console
 */
VkResult mvkNotifyErrorWithText(VkResult vkErr, const char* errFmt, ...) __printflike(2, 3);


#pragma mark -
#pragma mark Alignment functions

/** Returns the result of an unsigned integer division, rounded up. */
static inline size_t mvkCeilingDivide(size_t numerator, size_t denominator) {
	if (denominator == 1) { return numerator; }		// Short circuit for this very common usecase.
	return (numerator + denominator - 1) / denominator;
}

/** Returns whether the specified value is a power-of-two. */
static inline bool mvkIsPowerOfTwo(uintptr_t value) {
	// Test POT:  (x != 0) && ((x & (x - 1)) == 0)
	return value && ((value & (value - 1)) == 0);
}

/**
 * Ensures the specified value is a power-of-two. Returns the specified value if it is a
 * power-of-two value. If it is not, returns the next power-of-two value that is larger
 * than the specified value is returned.
 */
static inline uintptr_t mvkEnsurePowerOfTwo(uintptr_t value) {
	if (mvkIsPowerOfTwo(value)) { return value; }

	uintptr_t pot = 1;
	while(pot <= value) { pot <<= 1; };
	return pot;
}

/**
 * Returns the power-of-two exponent of the next power-of-two 
 * number that is at least as big as the specified value.
 *
 * This implementation returns zero for both zero and one as inputs.
 */
static inline uint32_t mvkPowerOfTwoExponent(uintptr_t value) {
    uintptr_t p2Value = mvkEnsurePowerOfTwo(value);

    // Count the trailing zeros
    p2Value = (p2Value ^ (p2Value - 1)) >> 1;  // Set trailing 0s to 1s and zero rest
    uint32_t potExp = 0;
    while (p2Value) {
        p2Value >>= 1;
        potExp++;
    }
    return potExp;
}

/**
 * Aligns the specified bytes reference to the specified alignment, and returns the
 * aligned value, which will be equal to or greater than the specified reference.
 *
 * This is a low level utility method. Usually you will use the convenience methods
 * mvkAlignAddress and mvkAlignByteOffset to align addresses and offsets respectively.
 */
static inline uintptr_t mvkAlignByteRef(uintptr_t byteRef, uintptr_t byteAlignment) {
	if (byteAlignment == 0) { return byteRef; }

	MVKAssert(mvkIsPowerOfTwo(byteAlignment), "Byte alignment %lu is not a power-of-two value.", byteAlignment);

	uintptr_t mask = byteAlignment - 1;
	return (byteRef + mask) & ~mask;
}

/**
 * Aligns the specified memory address to the specified byte alignment. The memory address
 * returned by this function will be equal to or greater than the specified address.
 */
static inline void* mvkAlignAddress(void* address, uintptr_t byteAlignment) {
	return (void*)mvkAlignByteRef((uintptr_t)address, byteAlignment);
}

/**
 * Aligns the specified byte offset to the specified byte alignment. The byte offset
 * returned by this function will be equal to or greater than the specified byte offset.
 */
static inline uintptr_t mvkAlignByteOffset(uintptr_t byteOffset, uintptr_t byteAlignment) {
	return mvkAlignByteRef(byteOffset, byteAlignment);
}

/**
 * Reverses the order of the rows in the specified data block.
 * The transformation is performed in-place.
 *
 * This function may be used to reverse the order of the rows of any row-major memory
 * structure, but is particularly useful for vertically flipping the contents of a texture
 * or image, which is a common requirement when converting content data between a Vulkan
 * texture orientation and a Metal texture orientation.
 *
 * The specified data block is assumed to be in row-major order, containing the specified
 * number of rows, and with the specified number of bytes in each row. The total number of
 * bytes in the data block must be at least (bytesPerRow * rowCount).
 */
void mvkFlipVertically(void* rowMajorData, uint32_t rowCount, size_t bytesPerRow);


#pragma mark Vulkan structure support functions

/** Returns whether the two Vulkan extents are equal by comparing their respective components. */
static inline bool mvkVkExtent2DsAreEqual(VkExtent2D e1, VkExtent2D e2) {
	return (e1.width == e2.width) && (e1.height == e2.height);
}

/** Returns whether the two Vulkan extents are equal by comparing their respective components. */
static inline bool mvkVkExtent3DsAreEqual(VkExtent3D e1, VkExtent3D e2) {
	return (e1.width == e2.width) && (e1.height == e2.height) && (e1.depth == e2.depth);
}

/** Returns whether the two Vulkan offsets are equal by comparing their respective components. */
static inline bool mvkVkOffset2DsAreEqual(VkOffset2D os1, VkOffset2D os2) {
	return (os1.x == os2.x) && (os1.y == os2.y);
}

/** Returns whether the two Vulkan offsets are equal by comparing their respective components. */
static inline bool mvkVkOffset3DsAreEqual(VkOffset3D os1, VkOffset3D os2) {
	return (os1.x == os2.x) && (os1.y == os2.y) && (os1.z == os2.z);
}

/**
 * Returns the difference between two offsets, by subtracting the subtrahend from the minuend,
 * which is accomplished by subtracting each of the corresponding x,y,z components.
 */
static inline VkOffset3D mvkVkOffset3DDifference(VkOffset3D minuend, VkOffset3D subtrahend) {
	VkOffset3D rslt;
	rslt.x = minuend.x - subtrahend.x;
	rslt.y = minuend.y - subtrahend.y;
	rslt.z = minuend.z - subtrahend.z;
	return rslt;
}


#pragma mark -
#pragma mark Template functions

/** Clamps the value between the lower and upper bounds, inclusive. */
template<typename T>
const T& mvkClamp(const T& val, const T& lower, const T& upper) {
    return std::min(upper, std::max(val, lower));
}

/**
 * Returns a hash value calculated from the specified array of numeric elements,
 * using the DJB2a algorithm:  hash = (hash * 33) ^ value.
 *
 * For a hash on a single array, leave the seed value unspecified, to use the default
 * seed value. To accumulate a single hash value over several arrays, use the hash
 * value returned by previous calls as the seed in subsequent calls.
 */
template<class N>
std::size_t mvkHash(const N* pVals, std::size_t count = 1, std::size_t seed = 5381) {
    std::size_t hash = seed;
    for (std::size_t i = 0; i < count; i++) { hash = ((hash << 5) + hash) ^ pVals[i]; }
    return hash;
}

/** Ensures the size of the specified container is at least the specified size. */
template<typename C, typename S>
void mvkEnsureSize(C& container, S size) {
    if (size > container.size()) { container.resize(size); }
}

/**
 * Iterates through the contents of the specified object pointer container and destroys
 * each object, including freeing the object memory, and clearing the container.
 */
template<typename C>
void mvkDestroyContainerContents(C& container) {
    for (auto elem : container) { elem->destroy(); }
    container.clear();
}

/**
 * Iterates through the contents of the specified Objective-C object pointer 
 * container and releases each object, and clears the container.
 */
template<typename C>
void mvkReleaseContainerContents(C& container) {
    for (auto elem : container) { [elem release]; }
    container.clear();
}

/** Removes the first occurance of the specified value from the specified container. */
template<class C, class T>
void mvkRemoveFirstOccurance(C& container, T val) {
    for (auto iter = container.begin(), end = container.end(); iter != end; iter++) {
        if( *iter == val ) {
            container.erase(iter);
            return;
        }
    }
}

/** Removes all occurances of the specified value from the specified container. */
template<class C, class T>
void mvkRemoveAllOccurances(C& container, T val) {
    container.erase(remove(container.begin(), container.end(), val), container.end());
}

/**
 * Sets the value referenced by the destination pointer with the value referenced by
 * the source pointer, and returns whether the value was set.
 *
 * If both specified pointers are non-NULL, populates the value referenced by the
 * destination pointer with the value referenced by the source pointer, and returns true.
 *
 * If the source pointer is NULL, the value referenced by the destination pointer
 * is overwritten with zeros to clear it, and returns false.
 *
 * If the destination pointer is NULL, does nothing, and returns false.
 */
template<typename T>
bool mvkSetOrClear(T* pDest, const T* pSrc) {
    if (pDest && pSrc) {
        *pDest = *pSrc;
        return true;
    }
    if (pDest) { memset(pDest, 0, sizeof(T)); }
    return false;
}

/**
 * Enables the flag (set the bit to 1) within the value parameter specified by the bitMask parameter.
 *
 * Typically, you call this function with only a single bit of the bitMask parameter set to 1.
 * However, you may also call this function with more than one bit of the bitMask parameter set
 * to 1, in which case, this function will set all corresponding bits in the value parameter to 1.
 */
template<typename T1, typename T2>
void mvkEnableFlag(T1& value, const T2 bitMask) { value |= bitMask; }

/**
 * Disables the flag (set the bit to 0) within the value parameter specified by the bitMask parameter.
 *
 * Typically, you call this function with only a single bit of the bitMask parameter set to 1.
 * However, you may also call this function with more than one bit of the bitMask parameter set
 * to 1, in which case, this function will set all corresponding bits in the value parameter to 0.
 */
template<typename T1, typename T2>
void mvkDisableFlag(T1& value, const T2 bitMask) { value &= ~bitMask; }

/** Returns whether the specified value has ALL of the flags specified in bitMask enabled (set to 1). */
template<typename T1, typename T2>
bool mvkAreFlagsEnabled(T1 value, const T2 bitMask) { return ((value & bitMask) == bitMask); }

/** Returns whether the specified value has ANY of the flags specified in bitMask enabled (set to 1). */
template<typename T1, typename T2>
bool mvkIsAnyFlagEnabled(T1 value, const T2 bitMask) { return !!(value & bitMask); }

/** Returns whether the specified value has ONLY of the flags specified in bitMask enabled (set to 1). */
template<typename T1, typename T2>
bool mvkAreOnlyFlagsEnabled(T1 value, const T2 bitMask) { return (value == bitMask); }

