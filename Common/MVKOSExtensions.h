/*
 * MVKOSExtensions.h
 *
 * Copyright (c) 2015-2023 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include <dispatch/dispatch.h>
#include <string>
#include <limits>


typedef float MVKOSVersion;

/*** Constant indicating unsupported functionality in an OS. */
static const MVKOSVersion kMVKOSVersionUnsupported = std::numeric_limits<MVKOSVersion>::max();

/**
 * Returns the operating system version as an MVKOSVersion, which is a float in which the
 * whole number portion indicates the major version, and the fractional portion indicates 
 * the minor and patch versions, associating 2 decimal places to each.
 * - (10.12.3) => 10.1203
 * - (8.0.2) => 8.0002
 */
MVKOSVersion mvkOSVersion();

/** Returns a MVKOSVersion built from the version components. */
inline MVKOSVersion mvkMakeOSVersion(uint32_t major, uint32_t minor, uint32_t patch) {
	return (float)major + ((float)minor / 100.0f) + ((float)patch / 10000.0f);
}

/** Returns whether the operating system version is at least minVer. */
inline bool mvkOSVersionIsAtLeast(MVKOSVersion minVer) { return mvkOSVersion() >= minVer; }

/**
 * Returns whether the operating system version is at least the appropriate min version.
 * The constant kMVKOSVersionUnsupported can be used for either value to cause the test
 * to always fail on that OS, which is useful for indidicating functionalty guarded by
 * this test is not supported on that OS.
 */
inline bool mvkOSVersionIsAtLeast(MVKOSVersion macOSMinVer, MVKOSVersion iOSMinVer) {
#if MVK_MACOS
	return mvkOSVersionIsAtLeast(macOSMinVer);
#endif
#if MVK_IOS_OR_TVOS
	return mvkOSVersionIsAtLeast(iOSMinVer);
#endif
}

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

/** Ensures the block is executed on the main thread. */
void mvkDispatchToMainAndWait(dispatch_block_t block);


#pragma mark -
#pragma mark Process environment

/**
 * Returns the value of the environment variable at the given name,
 * or an empty string if no environment variable with that name exists.
 *
 * If pWasFound is not null, its value is set to true if the environment
 * variable exists, or false if not.
 */
std::string mvkGetEnvVar(std::string varName, bool* pWasFound = nullptr);

/**
 * Returns the value of the environment variable at the given name,
 * or zero if no environment variable with that name exists.
 *
 * If pWasFound is not null, its value is set to true if the environment
 * variable exists, or false if not.
 */
int64_t mvkGetEnvVarInt64(std::string varName, bool* pWasFound = nullptr);

/**
 * Returns the value of the environment variable at the given name,
 * or false if no environment variable with that name exists.
 *
 * If pWasFound is not null, its value is set to true if the environment
 * variable exists, or false if not.
 */
bool mvkGetEnvVarBool(std::string varName, bool* pWasFound = nullptr);

#define MVK_SET_FROM_ENV_OR_BUILD_BOOL(cfgVal, EV)				\
	do {														\
		bool wasFound = false;									\
		bool ev = mvkGetEnvVarBool(#EV, &wasFound);				\
		cfgVal = wasFound ? ev : EV;							\
	} while(false)

#define MVK_SET_FROM_ENV_OR_BUILD_INT64(cfgVal, EV)				\
	do {														\
		bool wasFound = false;									\
		int64_t ev = mvkGetEnvVarInt64(#EV, &wasFound);			\
		cfgVal = wasFound ? ev : EV;							\
	} while(false)

// Pointer cast permits cfgVal to be an enum var
#define MVK_SET_FROM_ENV_OR_BUILD_INT32(cfgVal, EV)				\
	do {														\
		bool wasFound = false;									\
		int64_t ev = mvkGetEnvVarInt64(#EV, &wasFound);			\
		int64_t val = wasFound ? ev : EV;						\
		*(int32_t*)&cfgVal = (int32_t)std::min(std::max(val, (int64_t)INT32_MIN), (int64_t)INT32_MAX);	\
	} while(false)

#define MVK_SET_FROM_ENV_OR_BUILD_STRING(cfgVal, EV, strObj)	\
	do {														\
		bool wasFound = false;									\
		std::string ev = mvkGetEnvVar(#EV, &wasFound);			\
		strObj = wasFound ? std::move(ev) : EV;					\
		cfgVal = strObj.c_str();								\
	} while(false)


#pragma mark -
#pragma mark System memory

/** Returns the total amount of physical RAM in the system. */
uint64_t mvkGetSystemMemorySize();

/** Returns the amount of memory available to this process. */
uint64_t mvkGetAvailableMemorySize();

/** Returns the amount of memory currently used by this process. */
uint64_t mvkGetUsedMemorySize();

/** Returns the size of a page of host memory on this platform. */
uint64_t mvkGetHostMemoryPageSize();
