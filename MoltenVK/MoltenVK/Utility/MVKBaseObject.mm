/*
 * MVKBaseObject.mm
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

#include "MVKBaseObject.h"
#include "MVKVulkanAPIObject.h"
#include "MVKInstance.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKStrings.h"

using namespace std;


#pragma mark -
#pragma mark MVKBaseObject

string MVKBaseObject::getClassName() { return mvk::getTypeName(this); }

const MVKConfiguration& MVKBaseObject::getMVKConfig() {
	MVKVulkanAPIObject* mvkAPIObj = getVulkanAPIObject();
	MVKInstance* mvkInst = mvkAPIObj ? mvkAPIObj->getInstance() : nullptr;
	return mvkGetMVKConfig(mvkInst);
}

void MVKBaseObject::reportMessage(MVKConfigLogLevel logLevel, const char* format, ...) {
	va_list args;
	va_start(args, format);
	reportMessage(this, logLevel, format, args);
	va_end(args);
}

void MVKBaseObject::reportMessage(MVKBaseObject* mvkObj, MVKConfigLogLevel logLevel, const char* format, ...) {
	va_list args;
	va_start(args, format);
	reportMessage(mvkObj, logLevel, format, args);
	va_end(args);
}

// This is the core reporting implementation. Other similar functions delegate here.
void MVKBaseObject::reportMessage(MVKBaseObject* mvkObj, MVKConfigLogLevel logLevel, const char* format, va_list args) {

	MVKVulkanAPIObject* mvkAPIObj = mvkObj ? mvkObj->getVulkanAPIObject() : nullptr;
	MVKInstance* mvkInst = mvkAPIObj ? mvkAPIObj->getInstance() : nullptr;
	bool hasDebugCallbacks = mvkInst && mvkInst->hasDebugCallbacks();
	bool shouldLog = logLevel <= mvkGetMVKConfig(mvkInst).logLevel;

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
	if (shouldLog) { fprintf(stderr, "[%s] %s\n", mvkGetReportingLevelString(logLevel), pMessage); }

	// Broadcast the message to any Vulkan debug report callbacks
	if (hasDebugCallbacks) { mvkInst->debugReportMessage(mvkAPIObj, logLevel, pMessage); }

	free(redoBuff);
}

VkResult MVKBaseObject::reportResult(VkResult vkErr, MVKConfigLogLevel logLevel, const char* format, ...) {
	va_list args;
	va_start(args, format);
	VkResult rslt = reportResult(this, vkErr, logLevel, format, args);
	va_end(args);
	return rslt;
}

VkResult MVKBaseObject::reportResult(MVKBaseObject* mvkObj, VkResult vkErr, MVKConfigLogLevel logLevel, const char* format, ...) {
	va_list args;
	va_start(args, format);
	VkResult rslt = reportResult(mvkObj, vkErr, logLevel, format, args);
	va_end(args);
	return rslt;
}

VkResult MVKBaseObject::reportResult(MVKBaseObject* mvkObj, VkResult vkRslt, MVKConfigLogLevel logLevel, const char* format, va_list args) {

	// Prepend the result code to the format string
	const char* vkRsltName = mvkVkResultName(vkRslt);
	size_t rsltLen = strlen(vkRsltName) + strlen(format) + 4;
	char fmtStr[rsltLen];
	snprintf(fmtStr, rsltLen, "%s: %s", vkRsltName, format);

	// Report the message
	va_list lclArgs;
	va_copy(lclArgs, args);
	reportMessage(mvkObj, logLevel, fmtStr, lclArgs);
	va_end(lclArgs);

	return vkRslt;
}

VkResult MVKBaseObject::reportError(VkResult vkErr, const char* format, ...) {
	va_list args;
	va_start(args, format);
	VkResult rslt = reportResult(this, vkErr, MVK_CONFIG_LOG_LEVEL_ERROR, format, args);
	va_end(args);
	return rslt;
}

VkResult MVKBaseObject::reportError(MVKBaseObject* mvkObj, VkResult vkErr, const char* format, ...) {
	va_list args;
	va_start(args, format);
	VkResult rslt = reportResult(mvkObj, vkErr, MVK_CONFIG_LOG_LEVEL_ERROR, format, args);
	va_end(args);
	return rslt;
}

VkResult MVKBaseObject::reportWarning(VkResult vkErr, const char* format, ...) {
	va_list args;
	va_start(args, format);
	VkResult rslt = reportResult(this, vkErr, MVK_CONFIG_LOG_LEVEL_WARNING, format, args);
	va_end(args);
	return rslt;
}

VkResult MVKBaseObject::reportWarning(MVKBaseObject* mvkObj, VkResult vkErr, const char* format, ...) {
	va_list args;
	va_start(args, format);
	VkResult rslt = reportResult(mvkObj, vkErr, MVK_CONFIG_LOG_LEVEL_WARNING, format, args);
	va_end(args);
	return rslt;
}
