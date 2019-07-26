/*
 * MVKExtensions.mm
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

#include "MVKExtensions.h"
#include "MVKFoundation.h"
#include "MVKOSExtensions.h"
#include "MVKEnvironment.h"
#include "vk_mvk_moltenvk.h"
#include <vulkan/vulkan_ios.h>
#include <vulkan/vulkan_macos.h>

using namespace std;


#pragma mark -
#pragma mark MVKExtension

// Returns a VkExtensionProperties struct populated with a name and version
static VkExtensionProperties mvkMakeExtProps(const char* extensionName, uint32_t specVersion) {
	VkExtensionProperties extProps;
	memset(extProps.extensionName, 0, sizeof(extProps.extensionName));
	if (extensionName) { strcpy(extProps.extensionName, extensionName); }
	extProps.specVersion = specVersion;
	return extProps;
}

// Extension properties
#define MVK_EXTENSION(var, EXT) \
static VkExtensionProperties kVkExtProps_ ##EXT = mvkMakeExtProps(VK_ ##EXT ##_EXTENSION_NAME, VK_ ##EXT ##_SPEC_VERSION);
#include "MVKExtensions.def"

// Returns whether the specified properties are valid for this platform
static bool mvkIsSupportedOnPlatform(VkExtensionProperties* pProperties) {
#if MVK_MACOS
	if (pProperties == &kVkExtProps_EXT_MEMORY_BUDGET) {
		return mvkOSVersion() >= 10.13;
	}
	if (pProperties == &kVkExtProps_EXT_POST_DEPTH_COVERAGE) { return false; }
	if (pProperties == &kVkExtProps_EXT_SHADER_STENCIL_EXPORT) {
		return mvkOSVersion() >= 10.14;
	}
	if (pProperties == &kVkExtProps_EXT_TEXEL_BUFFER_ALIGNMENT) {
		return mvkOSVersion() >= 10.13;
	}
	if (pProperties == &kVkExtProps_MVK_IOS_SURFACE) { return false; }
	if (pProperties == &kVkExtProps_AMD_SHADER_IMAGE_LOAD_STORE_LOD) { return false; }
	if (pProperties == &kVkExtProps_AMD_SHADER_TRINARY_MINMAX) {
		return mvkOSVersion() >= 10.14;
	}
	if (pProperties == &kVkExtProps_IMG_FORMAT_PVRTC) { return false; }
#endif
#if MVK_IOS
	if (pProperties == &kVkExtProps_KHR_SAMPLER_MIRROR_CLAMP_TO_EDGE) { return false; }
	if (pProperties == &kVkExtProps_EXT_MEMORY_BUDGET) {
		return mvkOSVersion() >= 11.0;
	}
	if (pProperties == &kVkExtProps_EXT_POST_DEPTH_COVERAGE) {
		return mvkOSVersion() >= 11.0;
	}
	if (pProperties == &kVkExtProps_EXT_SHADER_STENCIL_EXPORT) {
		return mvkOSVersion() >= 12.0;
	}
	if (pProperties == &kVkExtProps_EXT_SWAPCHAIN_COLOR_SPACE) { return false; }
	if (pProperties == &kVkExtProps_EXT_TEXEL_BUFFER_ALIGNMENT) {
		return mvkOSVersion() >= 11.0;
	}
	if (pProperties == &kVkExtProps_MVK_MACOS_SURFACE) { return false; }
	if (pProperties == &kVkExtProps_AMD_SHADER_TRINARY_MINMAX) {
		return mvkOSVersion() >= 12.0;
	}
#endif

	return true;
}

// Disable by default unless asked to enable for platform and the extension is valid for this platform
MVKExtension::MVKExtension(VkExtensionProperties* pProperties, bool enableForPlatform) {
	this->pProperties = pProperties;
	this->enabled = enableForPlatform && mvkIsSupportedOnPlatform(pProperties);
}


#pragma mark -
#pragma mark MVKExtensionList

MVKExtensionList::MVKExtensionList(MVKVulkanAPIObject* apiObject, bool enableForPlatform) : _apiObject(apiObject),
#define MVK_EXTENSION_LAST(var, EXT)	vk_ ##var(&kVkExtProps_ ##EXT, enableForPlatform)
#define MVK_EXTENSION(var, EXT)			MVK_EXTENSION_LAST(var, EXT),
#include "MVKExtensions.def"
{
	initCount();
}

// We can't determine size of annonymous struct, and can't rely on size of this class, since
// it can contain additional member variables. So we need to explicitly count the extensions.
void MVKExtensionList::initCount() {
	_count = 0;

#define MVK_EXTENSION(var, EXT) _count++;
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

VkResult MVKExtensionList::enable(uint32_t count, const char* const* names, MVKExtensionList* parent) {
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

VkResult MVKExtensionList::getProperties(uint32_t* pCount, VkExtensionProperties* pProperties) {

	uint32_t enabledCnt = 0;

	// Iterate extensions and handle those that are enabled. Count them,
	// and if they are to be returned, and there is room, do so.
	uint32_t extnCnt = getCount();
	MVKExtension* extnAry = &extensionArray;
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

