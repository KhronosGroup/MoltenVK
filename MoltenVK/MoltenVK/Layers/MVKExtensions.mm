/*
 * MVKExtensions.mm
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKExtensions.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKEnvironment.h"
#include <vulkan/vulkan_ios.h>
#include <vulkan/vulkan_macos.h>

using namespace std;


#pragma mark -
#pragma mark MVKExtension

// Returns a VkExtensionProperties struct populated with a name and version
static VkExtensionProperties mvkMakeExtProps(const char* extensionName, uint32_t specVersion) {
	VkExtensionProperties extProps;
	mvkClear(extProps.extensionName, VK_MAX_EXTENSION_NAME_SIZE);
	if (extensionName) { strcpy(extProps.extensionName, extensionName); }
	extProps.specVersion = specVersion;
	return extProps;
}

// Extension properties
#define MVK_EXTENSION(var, EXT, type, macos, ios) \
static VkExtensionProperties kVkExtProps_ ##EXT = mvkMakeExtProps(VK_ ##EXT ##_EXTENSION_NAME, VK_ ##EXT ##_SPEC_VERSION);
#include "MVKExtensions.def"

// Returns whether the specified properties are valid for this platform
static bool mvkIsSupportedOnPlatform(VkExtensionProperties* pProperties) {
#define MVK_EXTENSION_MIN_OS(EXT, MAC, IOS) \
	if (pProperties == &kVkExtProps_##EXT) { return mvkOSVersionIsAtLeast(MAC, IOS); }

	// If the config indicates that not all supported extensions should be advertised,
	// only advertise those supported extensions that have been specifically configured.
	auto advExtns = mvkConfig().advertiseExtensions;
	if ( !mvkIsAnyFlagEnabled(advExtns, MVK_CONFIG_ADVERTISE_EXTENSIONS_ALL) ) {
#define MVK_NA  kMVKOSVersionUnsupported
		if (mvkIsAnyFlagEnabled(advExtns, MVK_CONFIG_ADVERTISE_EXTENSIONS_MOLTENVK)) {
			MVK_EXTENSION_MIN_OS(MVK_MOLTENVK,                         10.11,  8.0)
		}
		if (mvkIsAnyFlagEnabled(advExtns, MVK_CONFIG_ADVERTISE_EXTENSIONS_WSI)) {
			MVK_EXTENSION_MIN_OS(EXT_METAL_SURFACE,                    10.11,  8.0)
			MVK_EXTENSION_MIN_OS(MVK_IOS_SURFACE,                      MVK_NA, 8.0)
			MVK_EXTENSION_MIN_OS(MVK_MACOS_SURFACE,                    10.11,  MVK_NA)
			MVK_EXTENSION_MIN_OS(KHR_SURFACE,                          10.11,  8.0)
			MVK_EXTENSION_MIN_OS(KHR_SWAPCHAIN,                        10.11,  8.0)
		}
		if (mvkIsAnyFlagEnabled(advExtns, MVK_CONFIG_ADVERTISE_EXTENSIONS_PORTABILITY)) {
			MVK_EXTENSION_MIN_OS(KHR_PORTABILITY_SUBSET,               10.11,  8.0)
			MVK_EXTENSION_MIN_OS(KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2, 10.11,  8.0)
		}
#undef MVK_NA

		return false;
	}

	// Otherwise, emumerate all available extensions to match the extension being validated for OS support.
#define MVK_EXTENSION(var, EXT, type, macos, ios)  MVK_EXTENSION_MIN_OS(EXT, macos, ios)
#include "MVKExtensions.def"
#undef MVK_EXTENSION_MIN_OS

	return false;
}

// Disable by default unless asked to enable for platform and the extension is valid for this platform
MVKExtension::MVKExtension(VkExtensionProperties* pProperties, bool enableForPlatform) {
	this->pProperties = pProperties;
	this->enabled = enableForPlatform && mvkIsSupportedOnPlatform(pProperties);
}


#pragma mark -
#pragma mark MVKExtensionList

MVKExtensionList::MVKExtensionList(MVKVulkanAPIObject* apiObject, bool enableForPlatform) : _apiObject(apiObject),
#define MVK_EXTENSION_LAST(var, EXT, type, macos, ios)		vk_ ##var(&kVkExtProps_ ##EXT, enableForPlatform)
#define MVK_EXTENSION(var, EXT, type, macos, ios)			MVK_EXTENSION_LAST(var, EXT, type, macos, ios),
#include "MVKExtensions.def"
{
	initCount();
}

// We can't determine size of annonymous struct, and can't rely on size of this class, since
// it can contain additional member variables. So we need to explicitly count the extensions.
void MVKExtensionList::initCount() {
	_count = 0;

#define MVK_EXTENSION(var, EXT, type, macos, ios) _count++;
#include "MVKExtensions.def"
}

#define MVK_ENSURE_EXTENSION_TYPE(var, EXT, type) vk_ ##var.enabled = vk_ ##var.enabled && MVK_EXTENSION_ ##type;

void MVKExtensionList::disableAllButEnabledInstanceExtensions() {
#define MVK_EXTENSION_INSTANCE         true
#define MVK_EXTENSION_DEVICE           false
#define MVK_EXTENSION(var, EXT, type, macos, ios)  MVK_ENSURE_EXTENSION_TYPE(var, EXT, type)
#include "MVKExtensions.def"
}

void MVKExtensionList::disableAllButEnabledDeviceExtensions() {
#define MVK_EXTENSION_INSTANCE         false
#define MVK_EXTENSION_DEVICE           true
#define MVK_EXTENSION(var, EXT, type, macos, ios)  MVK_ENSURE_EXTENSION_TYPE(var, EXT, type)
#include "MVKExtensions.def"
}

uint32_t MVKExtensionList::getEnabledCount() const {
	uint32_t enabledCnt = 0;
	uint32_t extnCnt = getCount();
	const MVKExtension* extnAry = &extensionArray;
	for (uint32_t extnIdx = 0; extnIdx < extnCnt; extnIdx++) {
		if (extnAry[extnIdx].enabled) { enabledCnt++; }
	}
	return enabledCnt;
}

bool MVKExtensionList::isEnabled(const char* extnName) const {
	if ( !extnName ) { return false; }

	uint32_t extnCnt = getCount();
	const MVKExtension* extnAry = &extensionArray;
	for (uint32_t extnIdx = 0; extnIdx < extnCnt; extnIdx++) {
		const MVKExtension& extn = extnAry[extnIdx];
		if ( strcmp(extn.pProperties->extensionName, extnName) == 0 ) {
			return extn.enabled;
		}
	}
	return false;
}

void MVKExtensionList::enable(const char* extnName) {
	uint32_t extnCnt = getCount();
	MVKExtension* extnAry = &extensionArray;
	for (uint32_t extnIdx = 0; extnIdx < extnCnt; extnIdx++) {
		MVKExtension& extn = extnAry[extnIdx];
		if ( strcmp(extn.pProperties->extensionName, extnName) == 0 ) {
			extn.enabled = true;
			return;
		}
	}
}

VkResult MVKExtensionList::enable(uint32_t count, const char* const* names, const MVKExtensionList* parent) {
	VkResult result = VK_SUCCESS;
	for (uint32_t i = 0; i < count; i++) {
		auto extnName = names[i];
		if (parent && !parent->isEnabled(extnName)) {
			result = reportError(VK_ERROR_EXTENSION_NOT_PRESENT, "Vulkan extension %s is not supported.", extnName);
		} else {
			enable(extnName);
		}
	}
	return result;
}

string MVKExtensionList::enabledNamesString(const char* separator, bool prefixFirstWithSeparator) const {
	string logMsg;
	bool isFirst = true;
	uint32_t extnCnt = getCount();
	const MVKExtension* extnAry = &extensionArray;
	for (uint32_t extnIdx = 0; extnIdx < extnCnt; extnIdx++) {
		const MVKExtension& extn = extnAry[extnIdx];
		if (extn.enabled) {
			if ( !isFirst || prefixFirstWithSeparator ) { logMsg += separator; }
			logMsg += extn.pProperties->extensionName;
			logMsg += " v";
			logMsg += to_string(extn.pProperties->specVersion);
			isFirst  = false;
		}
	}
	return logMsg;
}

VkResult MVKExtensionList::getProperties(uint32_t* pCount, VkExtensionProperties* pProperties) const {

	uint32_t enabledCnt = 0;

	// Iterate extensions and handle those that are enabled. Count them,
	// and if they are to be returned, and there is room, do so.
	uint32_t extnCnt = getCount();
	const MVKExtension* extnAry = &extensionArray;
	for (uint32_t extnIdx = 0; extnIdx < extnCnt; extnIdx++) {
		if (extnAry[extnIdx].enabled) {
			if (pProperties) {
				if (enabledCnt < *pCount) {
					pProperties[enabledCnt] = *(extnAry[extnIdx].pProperties);
				} else {
					return VK_INCOMPLETE;
				}
			}
			enabledCnt++;
		}
	}

	// Return the count of enabled extensions. This will either be a
	// count of all enabled extensions, or a count of those returned.
	*pCount = enabledCnt;
	return VK_SUCCESS;
}

