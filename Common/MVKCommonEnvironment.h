/*
 * MVKCommonEnvironment.h
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#include <Availability.h>


/**
 * Compiler build setting that ensures a definite value for whether this build is
 * a debug build or not.
 *
 * If the standard DEBUG build setting is defined, MVK_DEBUG is set to true,
 * otherwise, it is set to false.
 */
#ifndef MVK_DEBUG
#	ifdef DEBUG
#		define MVK_DEBUG		1
#	else
#		define MVK_DEBUG		0
#	endif	// DEBUG
#endif	// MVK_DEBUG

/** Building for tvOS. Use ifdef instead of defined() operator to allow MVK_TVOS to be used in expansions */
#ifndef MVK_TVOS
#    ifdef __TV_OS_VERSION_MAX_ALLOWED
#        define MVK_TVOS            1
#    else
#        define MVK_TVOS            0
#    endif
#endif

/** Building for iOS or tvOS. Use ifdef instead of defined() operator to allow MVK_IOS_OR_TVOS to be used in expansions */
#ifndef MVK_IOS_OR_TVOS
#    if __IPHONE_OS_VERSION_MAX_ALLOWED
#        define MVK_IOS_OR_TVOS     1
#    else
#        define MVK_IOS_OR_TVOS     0
#    endif
#endif

/** Building for iOS. Use ifdef instead of defined() operator to allow MVK_IOS to be used in expansions */
#ifndef MVK_IOS
#    if MVK_IOS_OR_TVOS && !MVK_TVOS
#        define MVK_IOS            1
#    else
#        define MVK_IOS            0
#    endif
#endif

/** Building for macOS. Use ifdef instead of defined() operator to allow MVK_MACOS to be used in expansions */
#ifndef MVK_MACOS
#    ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
#        define MVK_MACOS        1
#    else
#        define MVK_MACOS        0
#    endif
#endif

/** Directive to identify public symbols. */
#define MVK_PUBLIC_SYMBOL        __attribute__((visibility("default")))


#ifdef __cplusplus
}
#endif	//  __cplusplus

