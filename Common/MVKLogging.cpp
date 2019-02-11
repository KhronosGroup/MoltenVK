/*
 * MVKLogging.cpp
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


#include "MVKLogging.h"


// The logging level
// 0 = None
// 1 = Errors only
// 2 = All
#ifndef MVK_CONFIG_LOG_LEVEL
#   define MVK_CONFIG_LOG_LEVEL    2
#endif

static uint32_t _mvkLogLevel = MVK_CONFIG_LOG_LEVEL;

void MVKLogImplV(bool logToPrintf, bool /*logToASL*/, int aslLvl, const char* lvlStr, const char* format, va_list args) {

	if (aslLvl > (_mvkLogLevel << 2)) { return; }

	// Combine the level and format string
	char lvlFmt[strlen(lvlStr) + strlen(format) + 5];
	sprintf(lvlFmt, "[%s] %s\n", lvlStr, format);

	if (logToPrintf) { vfprintf(stderr, lvlFmt, args); }
//	if (logToASL) { asl_vlog(NULL, NULL, aslLvl, lvlFmt, args); }       // Multi-threaded ASL support requires a separate ASL client to be opened per thread!
}

void MVKLogImpl(bool logToPrintf, bool logToASL, int aslLvl, const char* lvlStr, const char* format, ...) {
	va_list args;
	va_start(args, format);
	MVKLogImplV(logToPrintf, logToASL, aslLvl, lvlStr, format, args);
	va_end(args);
}

#ifdef MVK_ENV_LOG_LEVEL
#include "MVKOSExtensions.h"
static bool _mvkLoggingInitialized = false;
__attribute__((constructor)) static void MVKInitLogging() {
	if (_mvkLoggingInitialized ) { return; }
	_mvkLoggingInitialized = true;

	MVK_SET_FROM_ENV_OR_BUILD_INT32(_mvkLogLevel, MVK_CONFIG_LOG_LEVEL);
}
#endif
