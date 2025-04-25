/*
 * MVKCommonEnvironment.h
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

#ifdef __cplusplus
extern "C" {
#endif	//  __cplusplus


#include <TargetConditionals.h>


/**
 * Compiler build setting that ensures a definite value for whether this
 * build is a debug build or not.
 *
 * If the standard DEBUG build setting is defined, MVK_CONFIG_DEBUG is
 * set to true, otherwise, it is set to false.
 */
#ifndef MVK_DEBUG
#	ifdef DEBUG
#		define MVK_DEBUG			1
#	else
#		define MVK_DEBUG			0
#	endif
#endif
#ifndef MVK_CONFIG_DEBUG
#	define MVK_CONFIG_DEBUG			MVK_DEBUG
#endif

/** Building for macOS. */
#ifndef MVK_MACOS
#	define MVK_MACOS				(TARGET_OS_OSX || TARGET_OS_MACCATALYST)
#endif

/** Building for iOS. */
#ifndef MVK_IOS
#	define MVK_IOS					(TARGET_OS_IOS && !TARGET_OS_MACCATALYST)
#endif

/** Building for iOS on Mac Catalyst. */
#ifndef MVK_MACCAT
#	define MVK_MACCAT				TARGET_OS_MACCATALYST
#endif

/** Building for tvOS. */
#ifndef MVK_TVOS
#	define MVK_TVOS					TARGET_OS_TV
#endif

/** Building for visionOS. */
#ifndef TARGET_OS_XR
#	define TARGET_OS_XR				0		// Older SDK's don't define TARGET_OS_XR
#endif
#ifndef TARGET_OS_VISION
#   define TARGET_OS_VISION         0        // Older SDK's don't define TARGET_OS_VISION
#endif
#ifndef MVK_VISIONOS
#	define MVK_VISIONOS				(TARGET_OS_XR || TARGET_OS_VISION)
#endif

/** Building for iOS or tvOS. */
#ifndef MVK_IOS_OR_TVOS
#	define MVK_IOS_OR_TVOS			(MVK_IOS || MVK_TVOS)
#endif

/** Building for macOS or iOS. */
#ifndef MVK_MACOS_OR_IOS
#	define MVK_MACOS_OR_IOS			(MVK_MACOS || MVK_IOS)
#endif

/** Building for iOS or visionOS. */
#ifndef MVK_IOS_OR_VISIONOS
#    define MVK_IOS_OR_VISIONOS    (MVK_IOS || MVK_VISIONOS)
#endif

/** Building for a Simulator. */
#ifndef MVK_OS_SIMULATOR
#	define MVK_OS_SIMULATOR			TARGET_OS_SIMULATOR
#endif

/** Building for Apple Silicon on iOS, tvOS, or macOS platform. */
#ifndef MVK_APPLE_SILICON
#	define MVK_APPLE_SILICON    	TARGET_CPU_ARM64
#endif

/** Building for macOS with support for Apple Silicon. */
#ifndef MVK_MACOS_APPLE_SILICON
#	define MVK_MACOS_APPLE_SILICON	(MVK_MACOS && MVK_APPLE_SILICON)
#endif

/** Building with Xcode versions. */
#ifndef MVK_XCODE_16
#   define MVK_XCODE_16             ((__MAC_OS_X_VERSION_MAX_ALLOWED >= 150000) || \
                                    (__IPHONE_OS_VERSION_MAX_ALLOWED >= 180000) || \
                                        (__TV_OS_VERSION_MAX_ALLOWED >= 180000))
#endif
#ifndef MVK_XCODE_15
#   define MVK_XCODE_15             ((__MAC_OS_X_VERSION_MAX_ALLOWED >= 140000) || \
                                    (__IPHONE_OS_VERSION_MAX_ALLOWED >= 170000) || \
                                        (__TV_OS_VERSION_MAX_ALLOWED >= 170000))
#endif
#ifndef MVK_XCODE_14_3
#	define MVK_XCODE_14_3			((__MAC_OS_X_VERSION_MAX_ALLOWED >= 130300) || \
									(__IPHONE_OS_VERSION_MAX_ALLOWED >= 160400) || \
                                        (__TV_OS_VERSION_MAX_ALLOWED >= 160400))
#endif
#ifndef MVK_XCODE_14
#	define MVK_XCODE_14				((__MAC_OS_X_VERSION_MAX_ALLOWED >= 130000) || \
									(__IPHONE_OS_VERSION_MAX_ALLOWED >= 160000) || \
                                        (__TV_OS_VERSION_MAX_ALLOWED >= 160000))
#endif
#ifndef MVK_XCODE_13
#	define MVK_XCODE_13 			((__MAC_OS_X_VERSION_MAX_ALLOWED >= 120000) || \
									(__IPHONE_OS_VERSION_MAX_ALLOWED >= 150000 || \
                                        (__TV_OS_VERSION_MAX_ALLOWED >= 150000)))
#endif
#ifndef MVK_XCODE_12
#	define MVK_XCODE_12 			((__MAC_OS_X_VERSION_MAX_ALLOWED >= 110000) || \
									(__IPHONE_OS_VERSION_MAX_ALLOWED >= 140000 || \
                                        (__TV_OS_VERSION_MAX_ALLOWED >= 140000)))
#endif

/**
 * Enable use of private Metal APIs.
 *
 * Enabling this build setting during a MoltenVK build will allow MoltenVK to
 * extend its functionality by using certain private Metal API calls, but it 
 * will also disqualify the app from being distributed via Apple App Stores.
 *
 * Disabled by default.
 */
#ifndef MVK_USE_METAL_PRIVATE_API
#	define MVK_USE_METAL_PRIVATE_API		0
#endif

/** Directive to identify public symbols. */
#define MVK_PUBLIC_SYMBOL    __attribute__((visibility("default"))) __attribute__((used))

/** Directive to make a public alias of another symbol. */
#define MVK_PUBLIC_ALIAS(ALIAS, TARGET)   asm(".globl _" #ALIAS "\n\t_" #ALIAS " = _" #TARGET)

/**
 * Directives to hide public symbols from the Vulkan API, to avoid library linking
 * conflicts when bound to a Vulkan Loader that also exports identical symbols.
 */
#ifndef MVK_HIDE_VULKAN_SYMBOLS
#	define MVK_HIDE_VULKAN_SYMBOLS		0
#endif
#if MVK_HIDE_VULKAN_SYMBOLS
#	define MVK_PUBLIC_VULKAN_SYMBOL
#	define MVK_PUBLIC_VULKAN_ALIAS(ALIAS, TARGET)
#else
#	define MVK_PUBLIC_VULKAN_SYMBOL		MVK_PUBLIC_SYMBOL
#	define MVK_PUBLIC_VULKAN_ALIAS(ALIAS, TARGET)	MVK_PUBLIC_ALIAS(ALIAS, TARGET)
#endif


#ifdef __cplusplus
}
#endif	//  __cplusplus

