/*
 * MVKEnvironment.h
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

#include "MVKCommonEnvironment.h"


/** Macro to determine the Vulkan version supported by MoltenVK. */
#define MVK_VULKAN_API_VERSION		VK_MAKE_VERSION(VK_VERSION_MAJOR(VK_API_VERSION_1_0),	\
													VK_VERSION_MINOR(VK_API_VERSION_1_0),	\
													VK_HEADER_VERSION)

/** 
 * Macro to adjust the specified Vulkan version to a value that can be compared for conformance 
 * against another Vulkan version. This macro strips the patch value from the specified Vulkan
 * version and replaces it with zero. A Vulkan version is comformant with another version if it
 * has the same or higher major and minor values, regardless of the patch value of each version.
 * In particular, by definition, a Vulkan version is conformant with another Vulkan version that
 * has a larger patch number, as long as it has a same or greater major and minor value.
 */
#define MVK_VULKAN_API_VERSION_CONFORM(api_ver)		VK_MAKE_VERSION(VK_VERSION_MAJOR(api_ver),	\
                                                                    VK_VERSION_MINOR(api_ver),	\
                                                                    0)

/** To present surface using a command buffer, define the MVK_PRESENT_WITHOUT_COMMAND_BUFFER build setting. */
#ifdef MVK_PRESENT_WITHOUT_COMMAND_BUFFER
#   define MVK_PRESENT_WITH_COMMAND_BUFFER_BOOL    0
#else
#   define MVK_PRESENT_WITH_COMMAND_BUFFER_BOOL    1
#endif

/** To display the MoltenVK logo watermark by default, define the MVK_DISPLAY_WATERMARK build setting. */
#ifdef MVK_DISPLAY_WATERMARK
#   define MVK_DISPLAY_WATERMARK_BOOL    1
#else
#   define MVK_DISPLAY_WATERMARK_BOOL    0
#endif


/**
 * IOSurfaces are supported on macOS, and on iOS starting with iOS 11.
 *
 * To enable IOSurface support on iOS in MoltenVK, set the iOS Deployment Target
 * (IPHONEOS_DEPLOYMENT_TARGET) build setting to 11.0 or greater when building
 * MoltenVK, and any app that uses IOSurfaces.
 */
#if MVK_MACOS
#	define MVK_SUPPORT_IOSURFACE_BOOL    1
#endif

#if MVK_IOS
#	define MVK_SUPPORT_IOSURFACE_BOOL	(__IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_11_0)
#endif
