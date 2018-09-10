/*
 * MVKExtensions.h
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

#include "mvk_vulkan.h"
#include <string>

/** Describes a Vulkan extension and whether or not it is enabled or supported. */
struct MVKExtension {
	bool enabled = false;
	VkExtensionProperties* pProperties;

	MVKExtension(VkExtensionProperties* pProperties, bool enableForPlatform = false);
};

/**
 * A fixed list of the Vulkan extensions known to MoltenVK, with
 * an indication of whether each extension is supported/enabled.
 *
 * To add support for a Vulkan extension, add a variable to this list.
 */
struct MVKExtensionList {
	union {
		struct {
			MVKExtension vk_MVK_moltenvk;
			MVKExtension vk_MVK_macos_surface;
			MVKExtension vk_MVK_ios_surface;
			MVKExtension vk_KHR_surface;
			MVKExtension vk_KHR_swapchain;
			MVKExtension vk_KHR_maintenance1;
			MVKExtension vk_IMG_format_pvrtc;
			MVKExtension vk_AMD_negative_viewport_height;
			MVKExtension vk_KHR_shader_draw_parameters;
			MVKExtension vk_KHR_get_physical_device_properties2;
			MVKExtension vk_KHR_push_descriptor;
			MVKExtension vk_KHR_descriptor_update_template;
		};
		MVKExtension extensionArray;
	};

	/** Returns the total number of extensions that are tracked by this object. */
	static uint32_t getCount() { return sizeof(MVKExtensionList) / sizeof(MVKExtension); }

	/** Returns whether the named extension is enabled. */
	bool isEnabled(const char* extnName) const;

	/** Enables the named extension. */
	void enable(const char* extnName);

	/**
	 * Enables the named extensions.
	 *
	 * If parent is non null, the extension must also be enabled in the parent in order
	 * for it to be enabled here. If it is not enabled in the parent, an error is logged
	 * and returned. Returns VK_SUCCESS if all requested extensions were able to be enabled.
	 */
	VkResult enable(uint32_t count, const char* const* names, MVKExtensionList* parent = nullptr);

	/**
	 * Returns a string containing the names of the enabled extensions, separated by the separator string.
	 * If prefixFirstWithSeparator is true the separator will also appear before the first extension name.
	 */
	std::string enabledNamesString(const char* separator = " ", bool prefixFirstWithSeparator = false) const;

	MVKExtensionList(bool enableForPlatform = false);
};

