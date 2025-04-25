/*
 * MVKOSExtensions.h
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

#include "MVKCommonEnvironment.h"
#include <dispatch/dispatch.h>
#include <string>
#include <limits>


#pragma mark -
#pragma mark Operating System versions

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
static inline MVKOSVersion mvkMakeOSVersion(uint32_t major, uint32_t minor, uint32_t patch) {
	return (float)major + ((float)minor / 100.0f) + ((float)patch / 10000.0f);
}

/** Returns whether the operating system version is at least minVer. */
static inline bool mvkOSVersionIsAtLeast(MVKOSVersion minVer) { return mvkOSVersion() >= minVer; }

/**
 * Returns whether the operating system version is at least the appropriate min version.
 * The constant kMVKOSVersionUnsupported can be used for any of the values to cause the test
 * to always fail on that OS, which is useful for indicating that functionalty guarded by
 * this test is not supported on that OS.
 */
static inline bool mvkOSVersionIsAtLeast(MVKOSVersion macOSMinVer,
										 MVKOSVersion iOSMinVer,
										 MVKOSVersion visionOSMinVer) {
#if MVK_MACOS
	return mvkOSVersionIsAtLeast(macOSMinVer);
#endif
#if MVK_IOS_OR_TVOS
	return mvkOSVersionIsAtLeast(iOSMinVer);
#endif
#if MVK_VISIONOS
	return mvkOSVersionIsAtLeast(visionOSMinVer);
#endif
}


#pragma mark -
#pragma mark Timestamps

/**
 * Returns a monotonic tick value for use in Vulkan and performance timestamping.
 *
 * The returned value corresponds to the number of CPU ticks since an arbitrary 
 * point in the past, and does not increment while the system is asleep.
 */
uint64_t mvkGetTimestamp();

/** 
 * Returns the number of runtime nanoseconds since an arbitrary point in the past,
 * excluding any time spent while the system is asleep.
 *
 * This value corresponds to the timestamps returned by Metal presentation timings.
 */
uint64_t mvkGetRuntimeNanoseconds();

/**
 * Returns the number of nanoseconds since an arbitrary point in the past,
 * including any time spent while the system is asleep.
 */
uint64_t mvkGetContinuousNanoseconds();

/**
 * Returns the number of nanoseconds elapsed between startTimestamp and endTimestamp,
 * each of which should be a value returned by mvkGetTimestamp().
 * If endTimestamp is zero or not supplied, it is taken to be the current time.
 * If startTimestamp is zero or not supplied, it is taken to be the time the app was initialized.
 */
uint64_t mvkGetElapsedNanoseconds(uint64_t startTimestamp = 0, uint64_t endTimestamp = 0);

/**
 * Returns the number of milliseconds elapsed between startTimestamp and endTimestamp,
 * each of which should be a value returned by mvkGetTimestamp().
 * If endTimestamp is zero or not supplied, it is taken to be the current time.
 * If startTimestamp is zero or not supplied, it is taken to be the time the app was initialized.
 */
double mvkGetElapsedMilliseconds(uint64_t startTimestamp = 0, uint64_t endTimestamp = 0);


#pragma mark -
#pragma mark Process environment

/**
 * Sets the value of the environment variable at the given name, into the
 * std::string, and returns whether the environment variable was found.
 */
bool mvkGetEnvVar(const char* evName, std::string& evStr);

/**
 * Returns a pointer to a string containing the value of the environment variable at
 * the given name, or returns the default value if the environment variable was not set.
 */
const char* mvkGetEnvVarString(const char* evName, std::string& evStr, const char* defaultValue = "");

/**
 * Returns the value of the environment variable at the given name,
 * or returns the default value if the environment variable was not set.
 */
double mvkGetEnvVarNumber(const char* evName, double defaultValue = 0.0);


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


#pragma mark -
#pragma mark Threading

/** Returns the amount of avaliable CPU cores. */
uint32_t mvkGetAvaliableCPUCores();

/** Ensures the block is executed on the main thread. */
void mvkDispatchToMainAndWait(dispatch_block_t block);
