/*
 * MVKFoundation.h
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


#include "MVKEnvironment.h"
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

/** A generic 32-bit color permitting float, int32, or uint32 values. */
typedef VkClearColorValue MVKColor32;

/** Tracks the Vulkan command currently being used. */
typedef enum : uint8_t {
    kMVKCommandUseNone = 0,                     /**< No use defined. */
	kMVKCommandUseBeginCommandBuffer,           /**< vkBeginCommandBuffer (prefilled VkCommandBuffer). */
    kMVKCommandUseQueueSubmit,                  /**< vkQueueSubmit. */
	kMVKCommandUseAcquireNextImage,             /**< vkAcquireNextImageKHR. */
    kMVKCommandUseQueuePresent,                 /**< vkQueuePresentKHR. */
    kMVKCommandUseQueueWaitIdle,                /**< vkQueueWaitIdle. */
    kMVKCommandUseDeviceWaitIdle,               /**< vkDeviceWaitIdle. */
	kMVKCommandUseInvalidateMappedMemoryRanges, /**< vkInvalidateMappedMemoryRanges. */
	kMVKCommandUseBeginRendering,               /**< vkCmdBeginRendering. */
    kMVKCommandUseBeginRenderPass,              /**< vkCmdBeginRenderPass. */
    kMVKCommandUseNextSubpass,                  /**< vkCmdNextSubpass. */
	kMVKCommandUseRestartSubpass,               /**< Create a new Metal renderpass due to Metal requirements. */
    kMVKCommandUsePipelineBarrier,              /**< vkCmdPipelineBarrier. */
    kMVKCommandUseBlitImage,                    /**< vkCmdBlitImage. */
    kMVKCommandUseCopyImage,                    /**< vkCmdCopyImage. */
    kMVKCommandUseResolveImage,                 /**< vkCmdResolveImage - resolve stage. */
    kMVKCommandUseResolveExpandImage,           /**< vkCmdResolveImage - expand stage. */
    kMVKCommandUseResolveCopyImage,             /**< vkCmdResolveImage - copy stage. */
	kMVKCommandUseCopyImageToMemory,            /**< vkCopyImageToMemory host sync. */
    kMVKCommandUseCopyBuffer,                   /**< vkCmdCopyBuffer. */
    kMVKCommandUseCopyBufferToImage,            /**< vkCmdCopyBufferToImage. */
    kMVKCommandUseCopyImageToBuffer,            /**< vkCmdCopyImageToBuffer. */
    kMVKCommandUseFillBuffer,                   /**< vkCmdFillBuffer. */
    kMVKCommandUseUpdateBuffer,                 /**< vkCmdUpdateBuffer. */
	kMVKCommandUseClearAttachments,             /**< vkCmdClearAttachments. */
    kMVKCommandUseClearColorImage,              /**< vkCmdClearColorImage. */
    kMVKCommandUseClearDepthStencilImage,       /**< vkCmdClearDepthStencilImage. */
    kMVKCommandUseResetQueryPool,               /**< vkCmdResetQueryPool. */
    kMVKCommandUseDispatch,                     /**< vkCmdDispatch. */
    kMVKCommandUseTessellationVertexTessCtl,    /**< vkCmdDraw* - vertex and tessellation control stages. */
	kMVKCommandUseDrawIndirectConvertBuffers,   /**< vkCmdDrawIndirect* convert indirect buffers. */
	kMVKCommandUseCopyQueryPoolResults,         /**< vkCmdCopyQueryPoolResults. */
	kMVKCommandUseAccumOcclusionQuery,          /**< Any command terminating a Metal render pass with active visibility buffer. */
	kMVKCommandConvertUint8Indices,             /**< Converting a Uint8 index buffer to Uint16. */
	kMVKCommandUseRecordGPUCounterSample        /**< Any command triggering the recording of a GPU counter sample. */
} MVKCommandUse;

/** Represents a given stage of a graphics pipeline. */
enum MVKGraphicsStage {
	kMVKGraphicsStageVertex = 0,	/**< The tessellation vertex compute shader stage. */
	kMVKGraphicsStageTessControl,	/**< The tessellation control compute shader stage. */
	kMVKGraphicsStageRasterization	/**< The rest of the pipeline. */
};

/** Returns the name of the command defined by the command use. */
const char* mvkVkCommandName(MVKCommandUse cmdUse);

/** Returns the name of the result value. */
const char* mvkVkResultName(VkResult vkResult);

/** Returns the name of the component swizzle. */
const char* mvkVkComponentSwizzleName(VkComponentSwizzle swizzle);

/** Returns whether this platform supports buffer device address. */
bool mvkSupportsBufferDeviceAddress();

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


#pragma mark -
#pragma mark Alignment functions

/** Returns whether the specified positive value is a power-of-two. */
template<typename T>
static constexpr bool mvkIsPowerOfTwo(T value) {
	return value > 0 && ((value & (value - 1)) == 0);
}

/**
 * Ensures the specified positive value is a power-of-two. Returns the specified value
 * if it is a power-of-two value. If it is not, returns the next power-of-two value
 * that is larger than the specified value is returned.
 */
template<typename T>
static constexpr T mvkEnsurePowerOfTwo(T value) {
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
static constexpr T mvkPowerOfTwoExponent(T value) {
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
static constexpr uintptr_t mvkAlignByteRef(uintptr_t byteRef, uintptr_t byteAlignment, bool alignDown = false) {
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
static constexpr uint64_t mvkAlignByteCount(uint64_t byteCount, uint64_t byteAlignment, bool alignDown = false) {
	return mvkAlignByteRef(byteCount, byteAlignment, alignDown);
}

/**
 * Compile time indication if the struct contains a specific member.
 *
 * If S::mbr is well-formed because the struct contains that member, the decltype() and
 * comma operator together trigger a true_type, otherwise it falls back to a false_type.
 *
 * Credit to: https://fekir.info/post/detect-member-variables/
 */
#define mvk_define_has_member(mbr) \
	template <typename T, typename = void> struct mvk_has_##mbr : std::false_type {}; \
	template <typename T> struct mvk_has_##mbr<T, decltype((void)T::mbr, void())> : std::true_type {};

mvk_define_has_member(pNext);	// Defines the mvk_has_pNext() function.

/** Returns the address of the first member of a structure, which is just the address of the structure. */
template <typename S>
void* mvkGetAddressOfFirstMember(const S* pStruct, std::false_type){
	return (void*)pStruct;
}

/**
 * Returns the address of the first member of a Vulkan structure containing a pNext member.
 * The first member is the one after the pNext member.
 */
template <class S>
void* mvkGetAddressOfFirstMember(const S* pStruct, std::true_type){
	return (void*)(&(pStruct->pNext) + 1);
}

/**
 * Returns the address of the first member of a structure. If the structure is a Vulkan
 * structure containing a pNext member, the first member is the one after the pNext member.
 */
template <class S>
void* mvkGetAddressOfFirstMember(const S* pStruct){
	return mvkGetAddressOfFirstMember(pStruct, mvk_has_pNext<S>{});
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
static constexpr  int32_t kMVKUndefinedLargePositiveInt32 =  mvkEnsurePowerOfTwo(std::numeric_limits<int32_t>::max() / 2);
static constexpr  int32_t kMVKUndefinedLargeNegativeInt32 = -kMVKUndefinedLargePositiveInt32;
static constexpr uint32_t kMVKUndefinedLargeUInt32        =  kMVKUndefinedLargePositiveInt32;
static constexpr  int64_t kMVKUndefinedLargePositiveInt64 =  mvkEnsurePowerOfTwo(std::numeric_limits<int64_t>::max() / 2);
static constexpr  int64_t kMVKUndefinedLargeNegativeInt64 = -kMVKUndefinedLargePositiveInt64;
static constexpr uint64_t kMVKUndefinedLargeUInt64        =  kMVKUndefinedLargePositiveInt64;


#pragma mark Vulkan structure support functions

/** Returns a VkExtent2D created from the width and height of a VkExtent3D. */
static constexpr VkExtent2D mvkVkExtent2DFromVkExtent3D(VkExtent3D e) { return {e.width, e.height }; }

/** Returns a VkExtent3D, created from a VkExtent2D, and with depth of 1. */
static constexpr VkExtent3D mvkVkExtent3DFromVkExtent2D(VkExtent2D e) { return {e.width, e.height, 1U }; }

/** Returns whether the two Vulkan extents are equal by comparing their respective components. */
static constexpr bool mvkVkExtent2DsAreEqual(VkExtent2D e1, VkExtent2D e2) {
	return (e1.width == e2.width) && (e1.height == e2.height);
}

/** Returns whether the two Vulkan extents are equal by comparing their respective components. */
static constexpr bool mvkVkExtent3DsAreEqual(VkExtent3D e1, VkExtent3D e2) {
	return (e1.width == e2.width) && (e1.height == e2.height) && (e1.depth == e2.depth);
}

/** Returns whether the two Vulkan offsets are equal by comparing their respective components. */
static constexpr bool mvkVkOffset2DsAreEqual(VkOffset2D os1, VkOffset2D os2) {
	return (os1.x == os2.x) && (os1.y == os2.y);
}

/** Returns whether the two Vulkan offsets are equal by comparing their respective components. */
static constexpr bool mvkVkOffset3DsAreEqual(VkOffset3D os1, VkOffset3D os2) {
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
static constexpr uint32_t mvkPackSwizzle(VkComponentMapping components) {
	return (((components.r & 0xFF) << 0) | ((components.g & 0xFF) << 8) |
			((components.b & 0xFF) << 16) | ((components.a & 0xFF) << 24));
}

/** Unpacks a single 32-bit word containing four swizzle components. */
static constexpr VkComponentMapping mvkUnpackSwizzle(uint32_t packed) {
	return {
		.r = (VkComponentSwizzle)((packed >> 0) & 0xFF),
		.g = (VkComponentSwizzle)((packed >> 8) & 0xFF),
		.b = (VkComponentSwizzle)((packed >> 16) & 0xFF),
		.a = (VkComponentSwizzle)((packed >> 24) & 0xFF),
	};
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
static constexpr bool mvkVKComponentSwizzlesMatch(VkComponentSwizzle cs1,
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
static constexpr bool mvkVkComponentMappingsMatch(VkComponentMapping cm1, VkComponentMapping cm2) {
	return (mvkVKComponentSwizzlesMatch(cm1.r, cm2.r, VK_COMPONENT_SWIZZLE_R) &&
			mvkVKComponentSwizzlesMatch(cm1.g, cm2.g, VK_COMPONENT_SWIZZLE_G) &&
			mvkVKComponentSwizzlesMatch(cm1.b, cm2.b, VK_COMPONENT_SWIZZLE_B) &&
			mvkVKComponentSwizzlesMatch(cm1.a, cm2.a, VK_COMPONENT_SWIZZLE_A));
}


#pragma mark Math

/** Rounds the value to nearest integer using half-to-even rounding. */
static inline double mvkRoundHalfToEven(const double val) {
	return val - std::remainder(val, 1.0);	// remainder() uses half-to-even rounding, but unfortunately isn't constexpr until C++23.
}

/** Returns whether the value will fit inside the numeric type. */
template<typename T, typename Tval>
static constexpr bool mvkFits(const Tval& val) {
	return val <= std::numeric_limits<T>::max();
}

/** Clamps the value between the lower and upper bounds, inclusive. */
template<typename T>
static constexpr const T& mvkClamp(const T& val, const T& lower, const T& upper) {
    return std::min(std::max(val, lower), upper);
}

/** Returns the result of a division, rounded up. */
template<typename T, typename U>
static constexpr typename std::common_type<T, U>::type mvkCeilingDivide(T numerator, U denominator) {
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
static constexpr typename std::common_type<T, U>::type mvkAbsDiff(T x, U y) {
	return x >= y ? x - y : y - x;
}

/** Returns the greatest common divisor of two numbers. */
template<typename T>
static constexpr T mvkGreatestCommonDivisorImpl(T a, T b) {
	return b == 0 ? a : mvkGreatestCommonDivisorImpl(b, a % b);
}

template<typename T, typename U>
static constexpr typename std::common_type<T, U>::type mvkGreatestCommonDivisor(T a, U b) {
	typedef typename std::common_type<T, U>::type R;
	typedef typename std::make_unsigned<R>::type UI;
	return static_cast<R>(mvkGreatestCommonDivisorImpl(static_cast<UI>(MVKAbs<R, T>::eval(a)), static_cast<UI>(MVKAbs<R, U>::eval(b))));
}

/** Returns the least common multiple of two numbers. */
template<typename T, typename U>
static constexpr typename std::common_type<T, U>::type mvkLeastCommonMultiple(T a, U b) {
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
static constexpr std::size_t mvkHash(const N* pVals, std::size_t count = 1, std::size_t seed = 5381) {
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
public:
	constexpr Type* begin() const { return _data; }
	constexpr Type* end() const { return &_data[_size]; }
	constexpr Type* data() const { return _data; }
	constexpr size_t size() const { return _size; }
	constexpr size_t byteSize() const { return _size * sizeof(Type); }
	constexpr Type& operator[]( const size_t i ) const { return _data[i]; }
	constexpr MVKArrayRef() : MVKArrayRef(nullptr, 0) {}
	constexpr MVKArrayRef(Type* d, size_t s) : _data(d), _size(s) {}
	template <typename Other, std::enable_if_t<std::is_convertible_v<Other(*)[], Type(*)[]>, bool> = true>
	constexpr MVKArrayRef(MVKArrayRef<Other> other) : _data(other.data()), _size(other.size()) {}

protected:
	Type* _data;
	size_t _size;
};

/** Ensures the size of the specified container is at least the specified size. */
template<typename C, typename S>
static void mvkEnsureSize(C& container, S size) {
    if (size > container.size()) { container.resize(size); }
}

/**
 * Iterates through the contents of the specified object pointer container and destroys
 * each object, including freeing the object memory, and clearing the container.
 */
template<typename C>
static void mvkDestroyContainerContents(C& container) {
    for (auto elem : container) { elem->destroy(); }
    container.clear();
}

/**
 * Iterates through the contents of the specified Objective-C object pointer 
 * container and releases each object, and clears the container.
 */
#ifdef __OBJC__
template<typename C>
static void mvkReleaseContainerContents(C& container) {
    for (auto elem : container) { [elem release]; }
    container.clear();
}
#endif

/** Returns whether the container contains an item equal to the value. */
template<class C, class T>
static constexpr bool mvkContains(C& container, const T& val) {
	for (const T& cVal : container) { if (cVal == val) { return true; } }
	return false;
}

/** Removes the first occurance of the specified value from the specified container. */
template<class C, class T>
static void mvkRemoveFirstOccurance(C& container, T val) {
    for (auto iter = container.begin(), end = container.end(); iter != end; iter++) {
        if( *iter == val ) {
            container.erase(iter);
            return;
        }
    }
}

/** Removes all occurances of the specified value from the specified container. */
template<class C, class T>
static void mvkRemoveAllOccurances(C& container, T val) {
    container.erase(std::remove(container.begin(), container.end(), val), container.end());
}


#pragma mark Values and structs

/** Selects and returns one of the values, based on the platform OS. */
template<typename T>
static constexpr const T& mvkSelectPlatformValue(const T& macOSVal, const T& iOSVal) {
#if MVK_MACOS
	return macOSVal;
#else
    return iOSVal;
#endif
}

/**
 * If pVal is not null, clears the memory occupied by *pVal by writing zeros to all bytes.
 * The optional count allows clearing multiple elements in an array.
 */
template<typename T>
static void mvkClear(T* pDst, size_t count = 1) {
	if ( !pDst ) { return; }					// Bad pointer
	if constexpr(std::is_arithmetic_v<T>) { if (count == 1) { *pDst = static_cast<T>(0); } }  // Fast clear of a single primitive
	memset(pDst, 0, sizeof(T) * count);			// Memory clear of complex content or array
}

/**
 * If pVal is not null, overrides the const declaration, and clears the memory occupied by *pVal
 * by writing zeros to all bytes. The optional count allows clearing multiple elements in an array.
*/
template<typename T>
static void mvkClear(const T* pVal, size_t count = 1) { mvkClear((T*)pVal, count); }

/**
 * If pSrc and pDst are both not null, copies the contents of the source value to the
 * destination value. The optional count allows copying of multiple elements in an array.
 * Supports void pointers, and copies single values via direct assignment.
 */
template<typename T>
static void mvkCopy(T* pDst, const T* pSrc, size_t count = 1) {
	if ( !pDst || !pSrc ) { return; }				// Bad pointers
	if (pDst == pSrc) { return; }					// Same object

	if constexpr(std::is_void_v<T>) {
		memcpy(pDst, pSrc, count);					// Copy as bytes
	} else {
		if (count == 1) {
			*pDst = *pSrc;  						// Fast copy of a single value
		} else {
			memcpy(pDst, pSrc, sizeof(T) * count);	// Memory copy of value array
		}
	}
}

/**
 * If pV1 and pV2 are both not null, returns whether the contents of the two values are equal,
 * otherwise returns false. The optional count allows comparing multiple elements in an array.
 */
template<typename T>
static constexpr bool mvkAreEqual(const T* pV1, const T* pV2, size_t count = 1) {
	if ( !pV2 || !pV2 ) { return false; }				// Bad pointers
	if (pV1 == pV2) { return true; }					// Same object
	if constexpr(std::is_arithmetic_v<T>) { if (count == 1) { return *pV1 == *pV2; } }  // Fast compare of a single primitive
	return memcmp(pV1, pV2, sizeof(T) * count) == 0;	// Memory compare of complex content or array
}

/**
 * Returns whether the contents of the two strings are equal, otherwise returns false.
 * This functionality is different than the char version of mvkAreEqual(),
 * which works on individual chars or char arrays, not strings.
 * Returns false if either string is null.
 */
static constexpr bool mvkStringsAreEqual(const char* pV1, const char* pV2) {
	return pV1 && pV2 && (pV1 == pV2 || strcmp(pV1, pV2) == 0);
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
static constexpr bool mvkSetOrClear(T* pDest, const T* pSrc) {
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

/** Enables all the flags (sets bits to 1) within the value parameter. */
template<typename Tv>
void mvkEnableAllFlags(Tv& value) { value = ~static_cast<Tv>(0); }

/** Disables the flags (sets bits to 0) within the value parameter specified by the bitMask parameter. */
template<typename Tv, typename Tm>
void mvkDisableFlags(Tv& value, const Tm bitMask) { value = (Tv)(value & ~(Tv)bitMask); }

/** Enables all the flags (sets bits to 1) within the value parameter. */
template<typename Tv>
void mvkDisableAllFlags(Tv& value) { value = static_cast<Tv>(0); }

/** Returns whether the specified value has ANY of the flags specified in bitMask enabled (set to 1). */
template<typename Tv, typename Tm>
static constexpr bool mvkIsAnyFlagEnabled(Tv value, const Tm bitMask) { return ((value & bitMask) != 0); }

/** Returns whether the specified value has ALL of the flags specified in bitMask enabled (set to 1). */
template<typename Tv, typename Tm>
static constexpr bool mvkAreAllFlagsEnabled(Tv value, const Tm bitMask) { return ((value & bitMask) == bitMask); }

/** Returns whether the specified value has ONLY one or more of the flags specified in bitMask enabled (set to 1), and none others. */
template<typename Tv, typename Tm>
static constexpr bool mvkIsOnlyAnyFlagEnabled(Tv value, const Tm bitMask) { return (mvkIsAnyFlagEnabled(value, bitMask) && ((value | bitMask) == bitMask)); }

/** Returns whether the specified value has ONLY ALL of the flags specified in bitMask enabled (set to 1), and none others. */
template<typename Tv, typename Tm>
static constexpr bool mvkAreOnlyAllFlagsEnabled(Tv value, const Tm bitMask) { return (value == bitMask); }

