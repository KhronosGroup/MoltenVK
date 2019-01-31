/*
 * MVKOSExtensions.h
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "mvk_vulkan.h"
#include "MVKFoundation.h"
#include <string>

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif


typedef float MVKOSVersion;

/**
 * Returns the operating system version as an MVKOSVersion, which is a float in which the
 * whole number portion indicates the major version, and the fractional portion indicates 
 * the minor and patch versions, associating 2 decimal places to each.
 * - (10.12.3) => 10.1203
 * - (8.0.2) => 8.0002
 */
MVKOSVersion mvkOSVersion(void);

/**
 * Returns a monotonic timestamp value for use in Vulkan and performance timestamping.
 *
 * The returned value corresponds to the number of CPU "ticks" since the app was initialized.
 *
 * Calling this value twice, subtracting the first value from the second, and then multiplying
 * the result by the value returned by mvkGetTimestampPeriod() will provide an indication of the
 * number of nanoseconds between the two calls. The convenience function mvkGetElapsedMilliseconds()
 * can be used to perform this calculation.
 */
uint64_t mvkGetTimestamp();

/** Returns the number of nanoseconds between each increment of the value returned by mvkGetTimestamp(). */
double mvkGetTimestampPeriod();

/**
 * Returns the number of milliseconds elapsed between startTimestamp and endTimestamp,
 * each of which should be a value returned by mvkGetTimestamp().
 * If endTimestamp is zero or not supplied, it is taken to be the current time.
 * If startTimestamp is zero or not supplied, it is taken to be the time the app was initialized.
 */
double mvkGetElapsedMilliseconds(uint64_t startTimestamp = 0, uint64_t endTimestamp = 0);

#ifdef __OBJC__
/** Ensures the block is executed on the main thread. */
inline void mvkDispatchToMainAndWait(dispatch_block_t block) {
	if (NSThread.isMainThread) {
		block();
	} else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}
#endif


#pragma mark -
#pragma mark Process environment


#ifdef __OBJC__
/**
 * Returns the value of the environment variable at the given name,
 * or an empty string if no environment variable with that name exists.
 *
 * If pWasFound is not null, it's value is set to true if the environment
 * variable exists, or false if not.
 */
std::string mvkGetEnvVar(std::string varName, bool* pWasFound = nullptr);

/**
 * Returns the value of the environment variable at the given name,
 * or zero if no environment variable with that name exists.
 *
 * If pWasFound is not null, it's value is set to true if the environment
 * variable exists, or false if not.
 */
int64_t mvkGetEnvVarInt64(std::string varName, bool* pWasFound = nullptr);

/**
 * Returns the value of the environment variable at the given name,
 * or false if no environment variable with that name exists.
 *
 * If pWasFound is not null, it's value is set to true if the environment
 * variable exists, or false if not.
 */
bool mvkGetEnvVarBool(std::string varName, bool* pWasFound = nullptr);

#define MVK_SET_FROM_ENV_OR_BUILD_BOOL(cfgVal, EV)	\
	do {											\
		bool wasFound = false;						\
		bool ev = mvkGetEnvVarBool(#EV, &wasFound);	\
		cfgVal = wasFound ? ev : EV;				\
	} while(false)

#define MVK_SET_FROM_ENV_OR_BUILD_INT64(cfgVal, EV)		\
	do {												\
		bool wasFound = false;							\
		int64_t ev = mvkGetEnvVarInt64(#EV, &wasFound);	\
		cfgVal = wasFound ? ev : EV;					\
	} while(false)

#define MVK_SET_FROM_ENV_OR_BUILD_INT32(cfgVal, EV)				\
	do {														\
		bool wasFound = false;									\
		int64_t ev = mvkGetEnvVarInt64(#EV, &wasFound);			\
		int64_t val = wasFound ? ev : EV;						\
		cfgVal = (int32_t)mvkClamp(val, (int64_t)INT32_MIN, (int64_t)INT32_MAX);	\
	} while(false)
#endif


#pragma mark -
#pragma mark MTLDevice

#ifdef __OBJC__
/** Returns an approximation of how much memory, in bytes, the device can use with good performance. */
uint64_t mvkRecommendedMaxWorkingSetSize(id<MTLDevice> mtlDevice);

/** Populate the propertes with info about the GPU represented by the MTLDevice. */
void mvkPopulateGPUInfo(VkPhysicalDeviceProperties& devProps, id<MTLDevice> mtlDevice);

/**
 * If the MTLDevice defines a texture memory alignment for the format, it is retrieved from
 * the MTLDevice and returned, or returns zero if the MTLDevice does not define an alignment.
 * The format must support linear texture memory (must not be depth, stencil, or compressed).
 */
VkDeviceSize mvkMTLPixelFormatLinearTextureAlignment(MTLPixelFormat mtlPixelFormat, id<MTLDevice> mtlDevice);
#endif
