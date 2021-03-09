/*
 * MVKExtensions.mm
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
#define MVK_EXTENSION(var, EXT, type) \
static VkExtensionProperties kVkExtProps_ ##EXT = mvkMakeExtProps(VK_ ##EXT ##_EXTENSION_NAME, VK_ ##EXT ##_SPEC_VERSION);
#include "MVKExtensions.def"

// Returns whether the specified properties are valid for this platform
static bool mvkIsSupportedOnPlatform(VkExtensionProperties* pProperties) {
#define MVK_NA  kMVKOSVersionUnsupported
#define MVK_EXTENSION_MIN_OS(EXT, MAC, IOS) \
	if (pProperties == &kVkExtProps_##EXT) { return mvkOSVersionIsAtLeast(MAC, IOS); }

	// If the config indicates that not all supported extensions should be advertised,
	// only advertise those supported extensions that have been specifically configured.
	auto advExtns = mvkGetMVKConfiguration()->advertiseExtensions;
	if ( !mvkIsAnyFlagEnabled(advExtns, MVK_CONFIG_ADVERTISE_EXTENSIONS_ALL) ) {
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

		return false;
	}

	MVK_EXTENSION_MIN_OS(MVK_IOS_SURFACE,                    MVK_NA, 8.0)
	MVK_EXTENSION_MIN_OS(MVK_MACOS_SURFACE,                  10.11,  MVK_NA)

	MVK_EXTENSION_MIN_OS(EXT_HDR_METADATA,                   10.15,  MVK_NA)
	MVK_EXTENSION_MIN_OS(AMD_SHADER_IMAGE_LOAD_STORE_LOD,    10.16,  8.0)
	MVK_EXTENSION_MIN_OS(IMG_FORMAT_PVRTC,                   10.16,  8.0)
	MVK_EXTENSION_MIN_OS(KHR_SAMPLER_MIRROR_CLAMP_TO_EDGE,   10.11,  14.0)
	MVK_EXTENSION_MIN_OS(EXT_SWAPCHAIN_COLOR_SPACE,          10.11,  9.0)
	MVK_EXTENSION_MIN_OS(KHR_SHADER_SUBGROUP_EXTENDED_TYPES, 10.14,  13.0)
	MVK_EXTENSION_MIN_OS(EXT_FRAGMENT_SHADER_INTERLOCK,      10.13,  11.0)
	MVK_EXTENSION_MIN_OS(EXT_MEMORY_BUDGET,                  10.13,  11.0)
	MVK_EXTENSION_MIN_OS(EXT_POST_DEPTH_COVERAGE,            10.16,  11.0)
	MVK_EXTENSION_MIN_OS(EXT_SHADER_STENCIL_EXPORT,          10.14,  12.0)
	MVK_EXTENSION_MIN_OS(EXT_SUBGROUP_SIZE_CONTROL,          10.14,  13.0)
	MVK_EXTENSION_MIN_OS(EXT_TEXEL_BUFFER_ALIGNMENT,         10.13,  11.0)
	MVK_EXTENSION_MIN_OS(EXT_TEXTURE_COMPRESSION_ASTC_HDR,   10.16,  13.0)
	MVK_EXTENSION_MIN_OS(AMD_SHADER_TRINARY_MINMAX,          10.14,  12.0)

	return true;

#undef MVK_NA
#undef MVK_EXTENSION_MIN_OS
}

// Disable by default unless asked to enable for platform and the extension is valid for this platform
MVKExtension::MVKExtension(VkExtensionProperties* pProperties, bool enableForPlatform) {
	this->pProperties = pProperties;
	this->enabled = enableForPlatform && mvkIsSupportedOnPlatform(pProperties);
}


#pragma mark -
#pragma mark MVKExtensionList

MVKExtensionList::MVKExtensionList(MVKVulkanAPIObject* apiObject, bool enableForPlatform) : _apiObject(apiObject),
#define MVK_EXTENSION_LAST(var, EXT, type)		vk_ ##var(&kVkExtProps_ ##EXT, enableForPlatform)
#define MVK_EXTENSION(var, EXT, type)			MVK_EXTENSION_LAST(var, EXT, type),
#include "MVKExtensions.def"
{
	initCount();
}

// We can't determine size of annonymous struct, and can't rely on size of this class, since
// it can contain additional member variables. So we need to explicitly count the extensions.
void MVKExtensionList::initCount() {
	_count = 0;

#define MVK_EXTENSION(var, EXT, type) _count++;
#include "MVKExtensions.def"
}

#define MVK_ENSURE_EXTENSION_TYPE(var, EXT, type) vk_ ##var.enabled = vk_ ##var.enabled && MVK_EXTENSION_ ##type;

void MVKExtensionList::disableAllButEnabledInstanceExtensions() {
#define MVK_EXTENSION_INSTANCE         true
#define MVK_EXTENSION_DEVICE           false
#define MVK_EXTENSION(var, EXT, type)  MVK_ENSURE_EXTENSION_TYPE(var, EXT, type)
#include "MVKExtensions.def"
}

void MVKExtensionList::disableAllButEnabledDeviceExtensions() {
#define MVK_EXTENSION_INSTANCE         false
#define MVK_EXTENSION_DEVICE           true
#define MVK_EXTENSION(var, EXT, type)  MVK_ENSURE_EXTENSION_TYPE(var, EXT, type)
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

