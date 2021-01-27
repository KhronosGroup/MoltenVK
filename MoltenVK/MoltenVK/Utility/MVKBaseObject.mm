/*
 * MVKBaseObject.mm
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKBaseObject.h"
#include "MVKVulkanAPIObject.h"
#include "MVKInstance.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include <cxxabi.h>

using namespace std;


static const char* getReportingLevelString(int aslLvl) {
	switch (aslLvl) {
		case ASL_LEVEL_DEBUG:
			return "mvk-debug";

		case ASL_LEVEL_INFO:
		case ASL_LEVEL_NOTICE:
			return "mvk-info";

		case ASL_LEVEL_WARNING:
			return "mvk-warn";

		case ASL_LEVEL_ERR:
		case ASL_LEVEL_CRIT:
		case ASL_LEVEL_ALERT:
		case ASL_LEVEL_EMERG:
		default:
			return "mvk-error";
	}
}


#pragma mark -
#pragma mark MVKBaseObject

string MVKBaseObject::getClassName() {
    int status;
    char* demangled = abi::__cxa_demangle(typeid(*this).name(), 0, 0, &status);
    string clzName = demangled;
    free(demangled);
    return clzName;
}

void MVKBaseObject::reportMessage(int aslLvl, const char* format, ...) {
	va_list args;
	va_start(args, format);
	reportMessage(this, aslLvl, format, args);
	va_end(args);
}

void MVKBaseObject::reportMessage(MVKBaseObject* mvkObj, int aslLvl, const char* format, ...) {
	va_list args;
	va_start(args, format);
	reportMessage(mvkObj, aslLvl, format, args);
	va_end(args);
}

// This is the core reporting implementation. Other similar functions delegate here.
void MVKBaseObject::reportMessage(MVKBaseObject* mvkObj, int aslLvl, const char* format, va_list args) {

	MVKVulkanAPIObject* mvkAPIObj = mvkObj ? mvkObj->getVulkanAPIObject() : nullptr;
	MVKInstance* mvkInst = mvkAPIObj ? mvkAPIObj->getInstance() : nullptr;
	bool hasDebugCallbacks = mvkInst && mvkInst->hasDebugCallbacks();
	bool shouldLog = (aslLvl < (mvkGetMVKConfiguration()->logLevel << 2));

	// Fail fast to avoid further unnecessary processing.
	if ( !(shouldLog || hasDebugCallbacks) ) { return; }

	va_list origArgs, redoArgs;
	va_copy(origArgs, args);
	va_copy(redoArgs, args);

	// Choose a buffer size suitable for most messages and attempt to write it out.
	const int kOrigBuffSize = 2 * KIBI;
	char origBuff[kOrigBuffSize];
	char* pMessage = origBuff;
	int msgLen = vsnprintf(origBuff, kOrigBuffSize, format, origArgs);

	// If message is too big for original buffer, allocate a buffer big enough to hold it and
	// write the message out again. We only want to do this double writing if we have to.
	int redoBuffSize = (msgLen >= kOrigBuffSize) ? msgLen + 1 : 0;
	char *redoBuff = NULL;
	if (redoBuffSize > 0 && (redoBuff = (char *)malloc(redoBuffSize))) {
		pMessage = redoBuff;
		vsnprintf(redoBuff, redoBuffSize, format, redoArgs);
	}

	va_end(redoArgs);
	va_end(origArgs);

	// Log the message to the standard error stream
	if (shouldLog) { fprintf(stderr, "[%s] %s\n", getReportingLevelString(aslLvl), pMessage); }

	// Broadcast the message to any Vulkan debug report callbacks
	if (hasDebugCallbacks) { mvkInst->debugReportMessage(mvkAPIObj, aslLvl, pMessage); }

	free(redoBuff);
}

VkResult MVKBaseObject::reportError(VkResult vkErr, const char* format, ...) {
	va_list args;
	va_start(args, format);
	VkResult rslt = reportError(this, vkErr, format, args);
	va_end(args);
	return rslt;
}

VkResult MVKBaseObject::reportError(MVKBaseObject* mvkObj, VkResult vkErr, const char* format, ...) {
	va_list args;
	va_start(args, format);
	VkResult rslt = reportError(mvkObj, vkErr, format, args);
	va_end(args);
	return rslt;
}

// This is the core reporting implementation. Other similar functions delegate here.
VkResult MVKBaseObject::reportError(MVKBaseObject* mvkObj, VkResult vkErr, const char* format, va_list args) {

	// Prepend the error code to the format string
	const char* vkRsltName = mvkVkResultName(vkErr);
	char fmtStr[strlen(vkRsltName) + strlen(format) + 4];
	sprintf(fmtStr, "%s: %s", vkRsltName, format);

	// Report the error
	va_list lclArgs;
	va_copy(lclArgs, args);
	reportMessage(mvkObj, ASL_LEVEL_ERR, fmtStr, lclArgs);
	va_end(lclArgs);

	return vkErr;
}
