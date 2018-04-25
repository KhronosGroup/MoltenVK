/*
 * MVKOSExtensions.h
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


/* This file contains convenient functions for accessing Metal components during execution. */

#pragma once

#include "MVKCommonEnvironment.h"
#include <vulkan/vulkan.h>

#import <Metal/Metal.h>


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


#pragma mark -
#pragma mark MTLDevice

/** Returns an approximation of how much memory, in bytes, the device can use with good performance. */
uint64_t mvkRecommendedMaxWorkingSetSize(id<MTLDevice> mtlDevice);

/** Populate the propertes with info about the GPU represented by the MTLDevice. */
void mvkPopulateGPUInfo(VkPhysicalDeviceProperties& devProps, id<MTLDevice> mtlDevice);

