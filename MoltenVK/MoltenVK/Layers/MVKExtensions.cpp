/*
 * MVKExtensions.cpp
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

#include "MVKExtensions.h"
#include "MVKFoundation.h"
#include "vk_mvk_moltenvk.h"
#include <vulkan/vulkan_ios.h>
#include <vulkan/vulkan_macos.h>

using namespace std;


// Returns a VkExtensionProperties struct populated with a name and version
static VkExtensionProperties mvkMakeExtProps(const char* extensionName, uint32_t specVersion) {
	VkExtensionProperties extProps;
	memset(extProps.extensionName, 0, sizeof(extProps.extensionName));
	if (extensionName) { strcpy(extProps.extensionName, extensionName); }
	extProps.specVersion = specVersion;
	return extProps;
}

// Declares and populates a static VkExtensionProperties variable for the extention EXT,
// which should include the unique portion of the extension name, as uppercase.
// For example, for the extension VK_KHR_surface, use KHR_SURFACE.
#define MVK_MAKE_VK_EXT_PROPS(EXT) \
static VkExtensionProperties kVkExtProps_ ##EXT = mvkMakeExtProps(VK_ ##EXT ##_EXTENSION_NAME, VK_ ##EXT ##_SPEC_VERSION)

// Extension properties
MVK_MAKE_VK_EXT_PROPS(MVK_MOLTENVK);
MVK_MAKE_VK_EXT_PROPS(MVK_MACOS_SURFACE);
MVK_MAKE_VK_EXT_PROPS(MVK_IOS_SURFACE);
MVK_MAKE_VK_EXT_PROPS(KHR_SURFACE);
MVK_MAKE_VK_EXT_PROPS(KHR_SWAPCHAIN);
MVK_MAKE_VK_EXT_PROPS(KHR_MAINTENANCE1);
MVK_MAKE_VK_EXT_PROPS(IMG_FORMAT_PVRTC);
MVK_MAKE_VK_EXT_PROPS(AMD_NEGATIVE_VIEWPORT_HEIGHT);
MVK_MAKE_VK_EXT_PROPS(KHR_SHADER_DRAW_PARAMETERS);
MVK_MAKE_VK_EXT_PROPS(KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
MVK_MAKE_VK_EXT_PROPS(KHR_PUSH_DESCRIPTOR);
MVK_MAKE_VK_EXT_PROPS(KHR_DESCRIPTOR_UPDATE_TEMPLATE);

// Calls the constructor for a MVKExtension member variable, using the member name and the
// portion of the extension name, as uppercase, used in the MVK_MAKE_VK_EXT_PROPS() macro above.
// For example, for the memeber variable vk_KHR_surface, use MVKExt_CONSTRUCT(vk_KHR_surface, KHR_SURFACE).
#define MVKExt_CONSTRUCT(var, EXT)	var(&kVkExtProps_ ##EXT, enableForPlatform)

MVKExtensionList::MVKExtensionList(bool enableForPlatform) :
	MVKExt_CONSTRUCT(vk_MVK_moltenvk, MVK_MOLTENVK),
	MVKExt_CONSTRUCT(vk_MVK_macos_surface, MVK_MACOS_SURFACE),
	MVKExt_CONSTRUCT(vk_MVK_ios_surface, MVK_IOS_SURFACE),
	MVKExt_CONSTRUCT(vk_KHR_surface, KHR_SURFACE),
	MVKExt_CONSTRUCT(vk_KHR_swapchain, KHR_SWAPCHAIN),
	MVKExt_CONSTRUCT(vk_KHR_maintenance1, KHR_MAINTENANCE1),
	MVKExt_CONSTRUCT(vk_IMG_format_pvrtc, IMG_FORMAT_PVRTC),
	MVKExt_CONSTRUCT(vk_AMD_negative_viewport_height, AMD_NEGATIVE_VIEWPORT_HEIGHT),
	MVKExt_CONSTRUCT(vk_KHR_shader_draw_parameters, KHR_SHADER_DRAW_PARAMETERS),
	MVKExt_CONSTRUCT(vk_KHR_get_physical_device_properties2, KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2),
	MVKExt_CONSTRUCT(vk_KHR_push_descriptor, KHR_PUSH_DESCRIPTOR),
	MVKExt_CONSTRUCT(vk_KHR_descriptor_update_template, KHR_DESCRIPTOR_UPDATE_TEMPLATE)
{}

bool MVKExtensionList::isEnabled(const char* extnName) const {
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
			result = mvkNotifyErrorWithText(VK_ERROR_EXTENSION_NOT_PRESENT, "Vulkan extension %s is not supported.", extnName);
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

// Returns whether the specified properties are valid for this platform
static bool mvkIsSupportedOnPlatform(VkExtensionProperties* pProperties) {
#if !(MVK_IOS)
	if (pProperties == &kVkExtProps_MVK_IOS_SURFACE) { return false; }
	if (pProperties == &kVkExtProps_IMG_FORMAT_PVRTC) { return false; }
#endif
#if !(MVK_MACOS)
	if (pProperties == &kVkExtProps_MVK_MACOS_SURFACE) { return false; }
#endif

	if (pProperties == &kVkExtProps_AMD_NEGATIVE_VIEWPORT_HEIGHT) { return false; }

	return true;
}

// Disable by default unless asked to enable for platform and the extension is valid for this platform
MVKExtension::MVKExtension(VkExtensionProperties* pProperties, bool enableForPlatform) {
	this->pProperties = pProperties;
	this->enabled = enableForPlatform && mvkIsSupportedOnPlatform(pProperties);
}
