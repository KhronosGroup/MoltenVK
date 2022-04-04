/*
 * MVKExtensions.h
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

#pragma once

#include "MVKBaseObject.h"
#include <string>


#pragma mark -
#pragma mark MVKExtension

/** Describes a Vulkan extension and whether or not it is enabled or supported. */
struct MVKExtension {
	bool enabled = false;
	VkExtensionProperties* pProperties;

	MVKExtension(VkExtensionProperties* pProperties, bool enableForPlatform = false);
};


#pragma mark -
#pragma mark MVKExtensionList

/**
 * A fixed list of the Vulkan extensions known to MoltenVK, with
 * an indication of whether each extension is supported/enabled.
 *
 * To add support for a Vulkan extension, add a variable to this list.
 */
class MVKExtensionList : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _apiObject; };

	union {
		struct {
#define MVK_EXTENSION(var, EXT, type, macos, ios) MVKExtension vk_ ##var;
#include "MVKExtensions.def"
		};
		MVKExtension extensionArray;
	};

	/** Returns the total number of extensions that are tracked by this object. */
	uint32_t getCount() const { return _count; }

	/** Returns the number of extensions that are enabled. */
	uint32_t getEnabledCount() const;

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
	VkResult enable(uint32_t count, const char* const* names, const MVKExtensionList* parent = nullptr);

	/**
	 * Returns a string containing the names of the enabled extensions, separated by the separator string.
	 * If prefixFirstWithSeparator is true the separator will also appear before the first extension name.
	 */
	std::string enabledNamesString(const char* separator = " ", bool prefixFirstWithSeparator = false) const;

	/**
	 * Disables all extensions except instance extensions that are already enabled,
	 * effectively leaving a list of platform-supported instance extensions.
	 */
	void disableAllButEnabledInstanceExtensions();

	/**
	 * Disables all extensions except device extensions that are already enabled,
	 * effectively leaving a list of platform-supported device extensions.
	 */
	void disableAllButEnabledDeviceExtensions();

	/**
	 * If pProperties is null, the value of pCount is updated with the number of extensions
	 * enabled in this list.
	 *
	 * If pProperties is not null, then pCount extension properties are copied into the array.
	 * If the number of available extensions is less than pCount, the value of pCount is updated
	 * to indicate the number of extension properties actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of extensions
	 * enabled in this list is larger than the specified pCount. Returns other values
	 * if an error occurs.
	 */
	VkResult getProperties(uint32_t* pCount, VkExtensionProperties* pProperties) const;

	MVKExtensionList(MVKVulkanAPIObject* apiObject, bool enableForPlatform = false);

protected:
	void initCount();

	MVKVulkanAPIObject* _apiObject;
	uint32_t _count;

};

