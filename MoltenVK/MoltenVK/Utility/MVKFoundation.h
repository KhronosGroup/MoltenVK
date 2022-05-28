/*
 * MVKFoundation.h
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#include "MVKCommonEnvironment.h"
#include "mvk_vulkan.h"
#include <algorithm>
#include <cassert>
#include <limits>
#include <string>
#include <cassert>
#include <simd/simd.h>
#include <type_traits>


#pragma mark Math

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


#pragma mark -
#pragma mark Vertex content structures

/** 2D vertex position and texcoord content. */
typedef struct {
	simd::float2 position;
	simd::float3 texCoord;
} MVKVertexPosTex;


#pragma mark -
#pragma mark Vulkan support

/** Tracks the Vulkan command currently being used. */
typedef enum : uint8_t {
    kMVKCommandUseNone = 0,                     /**< No use defined. */
	kMVKCommandUseEndCommandBuffer,             /**< vkEndCommandBuffer (prefilled VkCommandBuffer). */
    kMVKCommandUseQueueSubmit,                  /**< vkQueueSubmit. */
	kMVKCommandUseAcquireNextImage,             /**< vkAcquireNextImageKHR. */
    kMVKCommandUseQueuePresent,                 /**< vkQueuePresentKHR. */
    kMVKCommandUseQueueWaitIdle,                /**< vkQueueWaitIdle. */
    kMVKCommandUseDeviceWaitIdle,               /**< vkDeviceWaitIdle. */
	kMVKCommandUseInvalidateMappedMemoryRanges, /**< vkInvalidateMappedMemoryRanges. */
    kMVKCommandUseBeginRenderPass,              /**< vkCmdBeginRenderPass. */
    kMVKCommandUseNextSubpass,                  /**< vkCmdNextSubpass. */
	kMVKCommandUseRestartSubpass,               /**< Restart a subpass because of explicit or implicit barrier. */
    kMVKCommandUsePipelineBarrier,              /**< vkCmdPipelineBarrier. */
    kMVKCommandUseBlitImage,                    /**< vkCmdBlitImage. */
    kMVKCommandUseCopyImage,                    /**< vkCmdCopyImage. */
    kMVKCommandUseResolveImage,                 /**< vkCmdResolveImage - resolve stage. */
    kMVKCommandUseResolveExpandImage,           /**< vkCmdResolveImage - expand stage. */
    kMVKCommandUseResolveCopyImage,             /**< vkCmdResolveImage - copy stage. */
    kMVKCommandUseCopyBuffer,                   /**< vkCmdCopyBuffer. */
    kMVKCommandUseCopyBufferToImage,            /**< vkCmdCopyBufferToImage. */
    kMVKCommandUseCopyImageToBuffer,            /**< vkCmdCopyImageToBuffer. */
    kMVKCommandUseFillBuffer,                   /**< vkCmdFillBuffer. */
    kMVKCommandUseUpdateBuffer,                 /**< vkCmdUpdateBuffer. */
    kMVKCommandUseClearColorImage,              /**< vkCmdClearColorImage. */
    kMVKCommandUseClearDepthStencilImage,       /**< vkCmdClearDepthStencilImage. */
    kMVKCommandUseResetQueryPool,               /**< vkCmdResetQueryPool. */
    kMVKCommandUseDispatch,                     /**< vkCmdDispatch. */
    kMVKCommandUseTessellationVertexTessCtl,    /**< vkCmdDraw* - vertex and tessellation control stages. */
	kMVKCommandUseMultiviewInstanceCountAdjust, /**< vkCmdDrawIndirect* - adjust instance count for multiview. */
    kMVKCommandUseCopyQueryPoolResults,         /**< vkCmdCopyQueryPoolResults. */
    kMVKCommandUseAccumOcclusionQuery,          /**< Any command terminating a Metal render pass with active visibility buffer. */
	kMVKCommandUseRecordGPUCounterSample        /**< Any command triggering the recording of a GPU counter sample. */
} MVKCommandUse;

/** Represents a given stage of a graphics pipeline. */
enum MVKGraphicsStage {
	kMVKGraphicsStageVertex = 0,	/**< The vertex shader stage. */
	kMVKGraphicsStageTessControl,	/**< The tessellation control shader stage. */
	kMVKGraphicsStageRasterization	/**< The rest of the pipeline. */
};

/** Returns the name of the result value. */
const char* mvkVkResultName(VkResult vkResult);

/** Returns the name of the component swizzle. */
const char* mvkVkComponentSwizzleName(VkComponentSwizzle swizzle);

/** Returns the Vulkan API version number as a string. */
static inline std::string mvkGetVulkanVersionString(uint32_t vkVersion) {
	std::string verStr;
	verStr += std::to_string(VK_VERSION_MAJOR(vkVersion));
	verStr += ".";
	verStr += std::to_string(VK_VERSION_MINOR(vkVersion));
	verStr += ".";
	verStr += std::to_string(VK_VERSION_PATCH(vkVersion));
	return verStr;
}

/** Returns the MoltenVK API version number as a string. */
static inline std::string mvkGetMoltenVKVersionString(uint32_t mvkVersion) {
	std::string verStr;
	verStr += std::to_string(mvkVersion / 10000);
	verStr += ".";
	verStr += std::to_string((mvkVersion % 10000) / 100);
	verStr += ".";
	verStr += std::to_string(mvkVersion % 100);
	return verStr;
}


#pragma mark -
#pragma mark Alignment functions

/** Returns whether the specified positive value is a power-of-two. */
template<typename T>
static inline bool mvkIsPowerOfTwo(T value) {
	// Test POT:  (x != 0) && ((x & (x - 1)) == 0)
	return value && ((value & (value - 1)) == 0);
}

/**
 * Ensures the specified positive value is a power-of-two. Returns the specified value
 * if it is a power-of-two value. If it is not, returns the next power-of-two value
 * that is larger than the specified value is returned.
 */
template<typename T>
static inline T mvkEnsurePowerOfTwo(T value) {
	if (mvkIsPowerOfTwo(value)) { return value; }

	T pot = 1;
	while(pot <= value) { pot <<= 1; };
	return pot;
}

/**
 * Returns the power-of-two exponent of the next power-of-two 
 * number that is at least as big as the specified value.
 *
 * This implementation returns zero for both zero and one as inputs.
 */
template<typename T>
static inline T mvkPowerOfTwoExponent(T value) {
    T p2Value = mvkEnsurePowerOfTwo(value);

    // Count the trailing zeros
    p2Value = (p2Value ^ (p2Value - 1)) >> 1;  // Set trailing 0s to 1s and zero rest
    T potExp = 0;
    while (p2Value) {
        p2Value >>= 1;
        potExp++;
    }
    return potExp;
}

/**
 * Aligns the byte reference to the specified alignment, and returns the aligned value,
 * which will be greater than or equal to the reference if alignDown is false, or less
 * than or equal to the reference if alignDown is true.
 *
 * This is a low level utility method. Usually you will use the convenience functions
 * mvkAlignAddress() and mvkAlignByteCount() to align addresses and offsets respectively.
 */
static inline uintptr_t mvkAlignByteRef(uintptr_t byteRef, uintptr_t byteAlignment, bool alignDown = false) {
	if (byteAlignment == 0) { return byteRef; }

	assert(mvkIsPowerOfTwo(byteAlignment));

	uintptr_t mask = byteAlignment - 1;
	uintptr_t alignedRef = (byteRef + mask) & ~mask;

	if (alignDown && (alignedRef > byteRef)) {
		alignedRef -= byteAlignment;
	}

	return alignedRef;
}

/**
 * Aligns the memory address to the specified byte alignment, and returns the aligned address,
 * which will be greater than or equal to the original address if alignDown is false, or less
 * than or equal to the original address if alignDown is true.
 */
static inline void* mvkAlignAddress(void* address, uintptr_t byteAlignment, bool alignDown = false) {
	return (void*)mvkAlignByteRef((uintptr_t)address, byteAlignment, alignDown);
}

/**
 * Aligns the byte offset to the specified byte alignment, and returns the aligned offset,
 * which will be greater than or equal to the original offset if alignDown is false, or less
 * than or equal to the original offset if alignDown is true.
 */
static inline uintptr_t mvkAlignByteCount(uintptr_t byteCount, uintptr_t byteAlignment, bool alignDown = false) {
	return mvkAlignByteRef(byteCount, byteAlignment, alignDown);
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

/**
 * The following constants are used to indicate values that have no defined limit.
 * They are ridiculously large numbers, but low enough to be safely used as both
 * uint and int values without risking overflowing between positive and negative values.
 */
static  int32_t kMVKUndefinedLargePositiveInt32 =  mvkEnsurePowerOfTwo(std::numeric_limits<int32_t>::max() / 2);
static  int32_t kMVKUndefinedLargeNegativeInt32 = -kMVKUndefinedLargePositiveInt32;
static uint32_t kMVKUndefinedLargeUInt32        =  kMVKUndefinedLargePositiveInt32;
static  int64_t kMVKUndefinedLargePositiveInt64 =  mvkEnsurePowerOfTwo(std::numeric_limits<int64_t>::max() / 2);
static  int64_t kMVKUndefinedLargeNegativeInt64 = -kMVKUndefinedLargePositiveInt64;
static uint64_t kMVKUndefinedLargeUInt64        =  kMVKUndefinedLargePositiveInt64;


#pragma mark Vulkan structure support functions

/** Returns a VkExtent2D created from the width and height of a VkExtent3D. */
static inline VkExtent2D mvkVkExtent2DFromVkExtent3D(VkExtent3D e) { return {e.width, e.height }; }

/** Returns a VkExtent3D, created from a VkExtent2D, and with depth of 1. */
static inline VkExtent3D mvkVkExtent3DFromVkExtent2D(VkExtent2D e) { return {e.width, e.height, 1U }; }

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

/** Packs the four swizzle components into a single 32-bit word. */
static inline uint32_t mvkPackSwizzle(VkComponentMapping components) {
	return ((components.r & 0xFF) << 0) | ((components.g & 0xFF) << 8) |
	((components.b & 0xFF) << 16) | ((components.a & 0xFF) << 24);
}

/** Unpacks a single 32-bit word containing four swizzle components. */
static inline VkComponentMapping mvkUnpackSwizzle(uint32_t packed) {
	VkComponentMapping components;
	components.r = (VkComponentSwizzle)((packed >> 0) & 0xFF);
	components.g = (VkComponentSwizzle)((packed >> 8) & 0xFF);
	components.b = (VkComponentSwizzle)((packed >> 16) & 0xFF);
	components.a = (VkComponentSwizzle)((packed >> 24) & 0xFF);
	return components;
}

/**
 * Returns whether the two component swizzles, cs1 and cs2 match. Positional identity matches
 * and wildcard matches are allowed. The two values match under any of the following conditions:
 *   1) cs1 and cs2 are equal to each other.
 *   2) Either cs1 or cs2 is equal to VK_COMPONENT_SWIZZLE_IDENTITY and the other value
 *      is equal to the positional value csPos, which is one of VK_COMPONENT_SWIZZLE_R,
 *      VK_COMPONENT_SWIZZLE_G, VK_COMPONENT_SWIZZLE_B, or VK_COMPONENT_SWIZZLE_A.
 *   3) Either cs1 or cs2 is VK_COMPONENT_SWIZZLE_MAX_ENUM, which is considered a wildcard,
 *      and matches any value.
 */
static inline bool mvkVKComponentSwizzlesMatch(VkComponentSwizzle cs1,
											   VkComponentSwizzle cs2,
											   VkComponentSwizzle csPos) {
	return ((cs1 == cs2) ||
			((cs1 == VK_COMPONENT_SWIZZLE_IDENTITY) && (cs2 == csPos)) ||
			((cs2 == VK_COMPONENT_SWIZZLE_IDENTITY) && (cs1 == csPos)) ||
			(cs1 == VK_COMPONENT_SWIZZLE_MAX_ENUM) || (cs2 == VK_COMPONENT_SWIZZLE_MAX_ENUM));
}

/**
 * Returns whether the two swizzle component mappings match each other, by comparing the
 * corresponding elements of the two mappings. A component value of VK_COMPONENT_SWIZZLE_IDENTITY
 * on either mapping matches the VK_COMPONENT_SWIZZLE_R, VK_COMPONENT_SWIZZLE_G, VK_COMPONENT_SWIZZLE_B,
 * or VK_COMPONENT_SWIZZLE_A value in the other mapping if it is the correct position.
 * A component value of VK_COMPONENT_SWIZZLE_MAX_ENUM is considered a wildcard and matches
 * any value in the corresponding component in the other mapping.
 */
static inline bool mvkVkComponentMappingsMatch(VkComponentMapping cm1, VkComponentMapping cm2) {
	return (mvkVKComponentSwizzlesMatch(cm1.r, cm2.r, VK_COMPONENT_SWIZZLE_R) &&
			mvkVKComponentSwizzlesMatch(cm1.g, cm2.g, VK_COMPONENT_SWIZZLE_G) &&
			mvkVKComponentSwizzlesMatch(cm1.b, cm2.b, VK_COMPONENT_SWIZZLE_B) &&
			mvkVKComponentSwizzlesMatch(cm1.a, cm2.a, VK_COMPONENT_SWIZZLE_A));
}

/** Print the size of the type. */
#define mvkPrintSizeOf(type)    printf("Size of " #type " is %lu.\n", sizeof(type))


#pragma mark -
#pragma mark Template functions

#pragma mark Math

/** Returns whether the value will fit inside the numeric type. */
template<typename T, typename Tval>
const bool mvkFits(const Tval& val) {
	return val <= std::numeric_limits<T>::max();
}

/** Clamps the value between the lower and upper bounds, inclusive. */
template<typename T>
const T& mvkClamp(const T& val, const T& lower, const T& upper) {
    return std::min(std::max(val, lower), upper);
}

/** Returns the result of a division, rounded up. */
template<typename T, typename U>
constexpr typename std::common_type<T, U>::type mvkCeilingDivide(T numerator, U denominator) {
	typedef typename std::common_type<T, U>::type R;
	// Short circuit very common usecase of dividing by one.
	return (denominator == 1) ? numerator : (R(numerator) + denominator - 1) / denominator;
}

/** Returns the absolute value of a number. */
template<typename R, typename T, bool = std::is_signed<T>::value>
struct MVKAbs;

template<typename R, typename T>
struct MVKAbs<R, T, true> {
	static constexpr R eval(T x) noexcept {
		return x >= 0 ? x : (x == std::numeric_limits<T>::min() ? -static_cast<R>(x) : -x);
	}
};

template<typename R, typename T>
struct MVKAbs<R, T, false> {
	static constexpr R eval(T x) noexcept {
		return x;
	}
};

/** Returns the absolute value of the difference of two numbers. */
template<typename T, typename U>
constexpr typename std::common_type<T, U>::type mvkAbsDiff(T x, U y) {
	return x >= y ? x - y : y - x;
}

/** Returns the greatest common divisor of two numbers. */
template<typename T>
constexpr T mvkGreatestCommonDivisorImpl(T a, T b) {
	return b == 0 ? a : mvkGreatestCommonDivisorImpl(b, a % b);
}

template<typename T, typename U>
constexpr typename std::common_type<T, U>::type mvkGreatestCommonDivisor(T a, U b) {
	typedef typename std::common_type<T, U>::type R;
	typedef typename std::make_unsigned<R>::type UI;
	return static_cast<R>(mvkGreatestCommonDivisorImpl(static_cast<UI>(MVKAbs<R, T>::eval(a)), static_cast<UI>(MVKAbs<R, U>::eval(b))));
}

/** Returns the least common multiple of two numbers. */
template<typename T, typename U>
constexpr typename std::common_type<T, U>::type mvkLeastCommonMultiple(T a, U b) {
	typedef typename std::common_type<T, U>::type R;
	return (a == 0 && b == 0) ? 0 : MVKAbs<R, T>::eval(a) / mvkGreatestCommonDivisor(a, b) * MVKAbs<R, U>::eval(b);
}


#pragma mark Hashing

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


#pragma mark Containers

/**
 * Structure to reference an array of typed elements in contiguous memory.
 * Allocation and management of the memory is handled externally.
 */
template<typename Type>
struct MVKArrayRef {
	Type* data;
	const size_t size;

	const Type* begin() const { return data; }
	const Type* end() const { return &data[size]; }
	const Type& operator[]( const size_t i ) const { return data[i]; }
	Type& operator[]( const size_t i ) { return data[i]; }
	MVKArrayRef<Type>& operator=(const MVKArrayRef<Type>& other) {
		data = other.data;
		*(size_t*)&size = other.size;
		return *this;
	}
	MVKArrayRef() : MVKArrayRef(nullptr, 0) {}
	MVKArrayRef(Type* d, size_t s) : data(d), size(s) {}
};

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
#ifdef __OBJC__
template<typename C>
void mvkReleaseContainerContents(C& container) {
    for (auto elem : container) { [elem release]; }
    container.clear();
}
#endif

/** Returns whether the container contains an item equal to the value. */
template<class C, class T>
bool contains(C& container, const T& val) {
	for (const T& cVal : container) { if (cVal == val) { return true; } }
	return false;
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
    container.erase(std::remove(container.begin(), container.end(), val), container.end());
}


#pragma mark Values and structs

/** Selects and returns one of the values, based on the platform OS. */
template<typename T>
const T& mvkSelectPlatformValue(const T& macOSVal, const T& iOSVal) {
#if MVK_IOS_OR_TVOS
	return iOSVal;
#endif
#if MVK_MACOS
	return macOSVal;
#endif
}

/**
 * If pVal is not null, clears the memory occupied by *pVal by writing zeros to all bytes.
 * The optional count allows clearing multiple elements in an array.
 */
template<typename T>
void mvkClear(T* pVal, size_t count = 1) { if (pVal) { memset(pVal, 0, sizeof(T) * count); } }

/**
 * If pVal is not null, overrides the const declaration, and clears the memory occupied by *pVal
 * by writing zeros to all bytes. The optional count allows clearing multiple elements in an array.
*/
template<typename T>
void mvkClear(const T* pVal, size_t count = 1) { mvkClear((T*)pVal, count); }

/**
 * If pSrc and pDst are both not null, copies the contents of the source value to the
 * destination value. The optional count allows copying of multiple elements in an array.
 */
template<typename T>
void mvkCopy(T* pDst, const T* pSrc, size_t count = 1) {
	if (pSrc && pDst) { memcpy(pDst, pSrc, sizeof(T) * count); }
}

/**
 * If pV1 and pV2 are both not null, returns whether the contents of the two values are equal,
 * otherwise returns false. The optional count allows comparing multiple elements in an array.
 */
template<typename T>
bool mvkAreEqual(const T* pV1, const T* pV2, size_t count = 1) {
	return (pV1 && pV2) ? (memcmp(pV1, pV2, sizeof(T) * count) == 0) : false;
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
    if (pDest) { mvkClear(pDest); }
    return false;
}


#pragma mark Boolean flags

/** Enables the flags (sets bits to 1) within the value parameter specified by the bitMask parameter. */
template<typename Tv, typename Tm>
void mvkEnableFlags(Tv& value, const Tm bitMask) { value = (Tv)(value | bitMask); }

/** Disables the flags (sets bits to 0) within the value parameter specified by the bitMask parameter. */
template<typename Tv, typename Tm>
void mvkDisableFlags(Tv& value, const Tm bitMask) { value = (Tv)(value & ~(Tv)bitMask); }

/** Returns whether the specified value has ANY of the flags specified in bitMask enabled (set to 1). */
template<typename Tv, typename Tm>
bool mvkIsAnyFlagEnabled(Tv value, const Tm bitMask) { return ((value & bitMask) != 0); }

/** Returns whether the specified value has ALL of the flags specified in bitMask enabled (set to 1). */
template<typename Tv, typename Tm>
bool mvkAreAllFlagsEnabled(Tv value, const Tm bitMask) { return ((value & bitMask) == bitMask); }

/** Returns whether the specified value has ONLY one or more of the flags specified in bitMask enabled (set to 1), and none others. */
template<typename Tv, typename Tm>
bool mvkIsOnlyAnyFlagEnabled(Tv value, const Tm bitMask) { return (mvkIsAnyFlagEnabled(value, bitMask) && ((value | bitMask) == bitMask)); }

/** Returns whether the specified value has ONLY ALL of the flags specified in bitMask enabled (set to 1), and none others. */
template<typename Tv, typename Tm>
bool mvkAreOnlyAllFlagsEnabled(Tv value, const Tm bitMask) { return (value == bitMask); }

