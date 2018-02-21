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
#import <QuartzCore/CAMetalLayer.h>


typedef float MVKOSVersion;

/**
 * Returns the operating system version as an MVKOSVersion, which is a float in which the
 * whole number portion indicates the major version, and the fractional portion indicates 
 * the minor and patch versions, associating 2 decimal places to each.
 * - (10.12.3) => 10.1203
 * - (8.0.2) => 8.0002
 */
MVKOSVersion mvkOSVersion(void);


#pragma mark -
#pragma mark MTLTextureDescriptor

/** Extensions to MTLTextureDescriptor to support MoltenVK. */
@interface MTLTextureDescriptor (MoltenVK)

/** 
 * Replacement for the usage property.
 *
 * This property allows support under iOS 8. Delegates to the usage property
 * if it is available. otherwise, returns MTLTextureUsageUnknown when read
 * and does nothing when set.
 */
@property(nonatomic, readwrite) MTLTextureUsage usageMVK;

/**
 * Replacement for the storageMode property.
 *
 * This property allows support under iOS 8. Delegates to the storageMode property
 * if it is available. otherwise, returns MTLStorageModeShared when read and does 
 * nothing when set.
 */
@property(nonatomic, readwrite) MTLStorageMode storageModeMVK;

@end


#pragma mark -
#pragma mark MTLSamplerDescriptor

/** Extensions to MTLSamplerDescriptor to support MoltenVK. */
@interface MTLSamplerDescriptor (MoltenVK)

/**
 * Replacement for the compareFunction property.
 *
 * This property allows support under iOS 8. Delegates to the compareFunction property
 * if it is available. otherwise, returns MTLTextureUsageUnknown when read and does 
 * nothing when set.
 */
@property(nonatomic, readwrite) MTLCompareFunction compareFunctionMVK;

@end


#pragma mark -
#pragma mark CAMetalLayer

/** Extensions to CAMetalLayer to support MoltenVK. */
@interface CAMetalLayer (MoltenVK)

/**
 * Ensures the drawableSize property of this layer is up to date, by combining the size
 * of the bounds property and the contentScale property, and returns the updated value.
 */
-(CGSize) updatedDrawableSizeMVK;

@end


#pragma mark -
#pragma mark MTLDevice

/** Returns an approximation of how much memory, in bytes, the device can use with good performance. */
uint64_t mvkRecommendedMaxWorkingSetSize(id<MTLDevice> mtlDevice);

/** Populate the propertes with info about the GPU represented by the MTLDevice. */
void mvkPopulateGPUInfo(VkPhysicalDeviceProperties& devProps, id<MTLDevice> mtlDevice);

