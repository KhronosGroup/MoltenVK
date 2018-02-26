/*
 * MVKLogging.h
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

#ifdef __cplusplus
extern "C" {
#endif	//  __cplusplus

#include "MVKCommonEnvironment.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <asl.h>
#include <stdbool.h>

/**
 * This library adds flexible, non-intrusive logging and assertion capabilities
 * that can be efficiently enabled or disabled via compiler switches.
 *
 * There are four levels of logging: Trace, Info, Error and Debug, and each can be enabled
 * independently via the MVK_LOG_LEVEL_TRACE, MVK_LOG_LEVEL_INFO, MVK_LOG_LEVEL_ERROR and
 * MVK_LOG_LEVEL_DEBUG switches, respectively.
 *
 * ALL logging can be enabled or disabled via the MVK_LOGGING_ENABLED switch.
 *
 * Each logging level also has a conditional logging variation, which outputs a log entry
 * only if the specified conditional expression evaluates to YES.
 *
 * Logging functions are implemented here via macros. Disabling logging, either entirely, or
 * at a specific level, completely removes the corresponding log invocations from the compiled
 * code, thus eliminating both the memory and CPU overhead that the logging calls would add.
 * You might choose, for example, to completely remove all logging from production release code,
 * by setting MVK_LOGGING_ENABLED off in your production builds settings. Or, as another example,
 * you might choose to include Error logging in your production builds by turning only
 * MVK_LOGGING_ENABLED and MVK_LOG_LEVEL_ERROR on, and turning the others off.
 *
 * To perform logging, use any of the following function calls in your code:
 *
 *		MVKLogError(fmt, ...)			- recommended for use only when there is an error to be logged
 *										- will print if MVK_LOG_LEVEL_ERROR is set on.
 *		MVKLogErrorIf(cond, fmt, ...)	- same as MVKLogError if boolean "cond" condition expression evaluates to YES,
 *										  otherwise logs nothing.
 *
 *		MVKLogInfo(fmt, ...)			- recommended for general, infrequent, information messages
 *										- will print if MVK_LOG_LEVEL_INFO is set on.
 *		MVKLogInfoIf(cond, fmt, ...)	- same as MVKLogInfo if boolean "cond" condition expression evaluates to YES,
 *										  otherwise logs nothing.
 *
 *		MVKLogDebug(fmt, ...)			- recommended for temporary use during debugging
 *										- will print if MVK_LOG_LEVEL_DEBUG is set on.
 *		MVKLogDebugIf(cond, fmt, ...)	- same as MVKLogDebug if boolean "cond" condition expression evaluates to YES,
 *										  otherwise logs nothing.
 *
 *		MVKLogTrace(fmt, ...)			- recommended for detailed tracing of program flow
 *										- will print if MVK_LOG_LEVEL_TRACE is set on.
 *		MVKLogTraceIf(cond, fmt, ...)	- same as MVKLogTrace if boolean "cond" condition expression evaluates to YES,
 *										  otherwise logs nothing.
 *
 * In each case, the functions follow the general NSLog/printf template, where the first argument
 * "fmt" is an NSString that optionally includes embedded Format Specifiers, and subsequent optional
 * arguments indicate data to be formatted and inserted into the string. As with NSLog/printf, the number
 * of optional arguments must match the number of embedded Format Specifiers. For more info, see the
 * core documentation for NSLog and String Format Specifiers.
 *
 * This library also enchances the assertion functions.
 * 
 * The MVKAssert() function can be used in place of the standard NSAssert() family of functions.
 * MVKAssert() improves the NSAssert() family of functions in two ways:
 *    - MVKAssert ensures that the assertion message is logged to the console.
 *    - MVKAssert can be used with a variable number of arguments without the need for
 *      NSAssert1(), NSAssert2(), etc.
 *
 * Like the NSAssert() functions, you can turn assertions off in production code by either setting
 * NS_BLOCK_ASSERTIONS to 1 in your compiler build settings, or setting the ENABLE_NS_ASSERTIONS
 * compiler setting to 0. Doing so completely removes the corresponding assertion invocations
 * from the compiled code, thus eliminating both the memory and CPU overhead that the assertion
 * calls would add
 *
 * A special MVKAssertUnimplemented(name) and MVKAssertCUnimplemented(name) assertion functions
 * are provided to conveniently raise an assertion exception when some expected functionality
 * is unimplemented. Either functions may be used as a temporary placeholder for functionalty
 * that will be added at a later time. MVKAssertUnimplemented(name) may also be used in a method
 * body by a superclass that requires each subclass to implement that method
 *
 * Although you can directly edit this file to turn on or off the switches below, the preferred
 * technique is to set these switches via the compiler build setting GCC_PREPROCESSOR_DEFINITIONS
 * in your build configuration.
 */

/**
 * Set this switch to  enable or disable logging capabilities. This can be set either here 
 * or via the compiler build setting GCC_PREPROCESSOR_DEFINITIONS in your build configuration. 
 * Using the compiler build setting is preferred for this to ensure that logging is not 
 * accidentally left enabled by accident in release builds.
 *
 * Logging is enabled by default.
 */
#ifndef MVK_LOGGING_ENABLED
#	define MVK_LOGGING_ENABLED		1
#endif

/**
 * Set any or all of these switches to enable or disable logging at specific levels.
 * These can be set either here or as a compiler build settings.
 */
#ifndef MVK_LOG_LEVEL_ERROR
#	define MVK_LOG_LEVEL_ERROR		MVK_LOGGING_ENABLED
#endif
#ifndef MVK_LOG_LEVEL_INFO
#	define MVK_LOG_LEVEL_INFO		MVK_LOGGING_ENABLED
#endif
#ifndef MVK_LOG_LEVEL_DEBUG
#	define MVK_LOG_LEVEL_DEBUG		(MVK_LOGGING_ENABLED && MVK_DEBUG)
#endif
#ifndef MVK_LOG_LEVEL_TRACE
#	define MVK_LOG_LEVEL_TRACE		0
#endif


// *********** END OF USER SETTINGS  - Do not change anything below this line ***********

// Error logging - only when there is an error to be logged
#if MVK_LOG_LEVEL_ERROR
#	define MVKLogError(fmt, ...)			MVKLogErrorImpl(fmt, ##__VA_ARGS__)
#	define MVKLogErrorIf(cond, fmt, ...)	if(cond) { MVKLogErrorImpl(fmt, ##__VA_ARGS__); }
#else
#	define MVKLogError(...)
#	define MVKLogErrorIf(cond, fmt, ...)
#endif

// Info logging - for general, non-performance affecting information messages
#if MVK_LOG_LEVEL_INFO
#	define MVKLogInfo(fmt, ...)				MVKLogInfoImpl(fmt, ##__VA_ARGS__)
#	define MVKLogInfoIf(cond, fmt, ...)		if(cond) { MVKLogInfoImpl(fmt, ##__VA_ARGS__); }
#else
#	define MVKLogInfo(...)
#	define MVKLogInfoIf(cond, fmt, ...)
#endif

// Trace logging - for detailed tracing
#if MVK_LOG_LEVEL_TRACE
#	define MVKLogTrace(fmt, ...)			MVKLogTraceImpl(fmt, ##__VA_ARGS__)
#	define MVKLogTraceIf(cond, fmt, ...)	if(cond) { MVKLogTraceImpl(fmt, ##__VA_ARGS__); }
#else
#	define MVKLogTrace(...)
#	define MVKLogTraceIf(cond, fmt, ...)
#endif

// Debug logging - use only temporarily for highlighting and tracking down problems
#if MVK_LOG_LEVEL_DEBUG
#	define MVKLogDebug(fmt, ...)			MVKLogDebugImpl(fmt, ##__VA_ARGS__)
#	define MVKLogDebugIf(cond, fmt, ...)	if(cond) { MVKLogDebugImpl(fmt, ##__VA_ARGS__); }
#else
#	define MVKLogDebug(...)
#	define MVKLogDebugIf(cond, fmt, ...)
#endif

/**
 * Combine the specified log level and format string, then log
 * the specified args to one or both of ASL and printf.
 */
static inline void MVKLogImplV(bool logToPrintf, bool logToASL, int aslLvl, const char* lvlStr, const char* format, va_list args) __printflike(5, 0);
static inline void MVKLogImplV(bool logToPrintf, bool logToASL, int aslLvl, const char* lvlStr, const char* format, va_list args) {

	// Combine the level and format string
	char lvlFmt[strlen(lvlStr) + strlen(format) + 5];
	sprintf(lvlFmt, "[%s] %s\n", lvlStr, format);

	if (logToPrintf) { vprintf(lvlFmt, args); }
//	if (logToASL) { asl_vlog(NULL, NULL, aslLvl, lvlFmt, args); }       // Multi-threaded ASL support requires a separate ASL client to be opened per thread!
}

/** 
 * Combine the specified log level and format string, then log 
 * the specified args to one or both of ASL and printf.
 */
static inline void MVKLogImpl(bool logToPrintf, bool logToASL, int aslLvl, const char* lvlStr, const char* format, ...) __printflike(5, 6);
static inline void MVKLogImpl(bool logToPrintf, bool logToASL, int aslLvl, const char* lvlStr, const char* format, ...) {
	va_list args;
	va_start(args, format);
	MVKLogImplV(logToPrintf, logToASL, aslLvl, lvlStr, format, args);
	va_end(args);
}

#define MVKLogErrorImpl(fmt, ...)	MVKLogImpl(true, !(MVK_DEBUG), ASL_LEVEL_ERR, "***MoltenVK ERROR***", fmt, ##__VA_ARGS__)
#define MVKLogInfoImpl(fmt, ...)	MVKLogImpl(true, !(MVK_DEBUG), ASL_LEVEL_NOTICE, "mvk-info", fmt, ##__VA_ARGS__)
#define MVKLogTraceImpl(fmt, ...)	MVKLogImpl(true, !(MVK_DEBUG), ASL_LEVEL_DEBUG, "mvk-trace", fmt, ##__VA_ARGS__)
#define MVKLogDebugImpl(fmt, ...)	MVKLogImpl(true, !(MVK_DEBUG), ASL_LEVEL_DEBUG, "mvk-debug", fmt, ##__VA_ARGS__)

// Assertions
#if NS_BLOCK_ASSERTIONS
#	define MVKAssert(test, fmt, ...)
#else
#	define MVKAssert(test, fmt, ...)					\
	if (!(test)) {										\
		MVKLogError(fmt, ##__VA_ARGS__);				\
		assert(false);									\
	}
#endif

#define MVKAssertUnimplemented(name) MVKAssert(false, "%s is not implemented!", name)

// Use this macro to open a break-point programmatically.
#ifndef MVK_DEBUGGER
#	define MVK_DEBUGGER() { kill( getpid(), SIGINT ) ; }
#endif


#ifdef __cplusplus
}
#endif	//  __cplusplus
