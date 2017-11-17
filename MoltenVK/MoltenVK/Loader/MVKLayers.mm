/*
 * MVKLayers.mm
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKLayers.h"
#include "MVKEnvironment.h"
#include "vk_mvk_moltenvk.h"
#include <mutex>

using namespace std;


#pragma mark MVKLayer

const char* MVKLayer::getName() { return (const char*)&_layerProperties.layerName; }

VkLayerProperties* const MVKLayer::getLayerProperties() { return &_layerProperties; }

VkResult MVKLayer::getExtensionProperties(uint32_t* pCount, VkExtensionProperties* pProperties) {

	// If properties aren't actually being requested yet, simply update the returned count
	if ( !pProperties ) {
		*pCount = (uint32_t)_extensions.size();
		return VK_SUCCESS;
	}

	// Othewise, determine how many extensions we'll return, and return that count
	uint32_t extCnt = (uint32_t)_extensions.size();
	VkResult result = (*pCount <= extCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(extCnt, *pCount);

	// Now populate the layer properties
	for (uint32_t extIdx = 0; extIdx < *pCount; extIdx++) {
		pProperties[extIdx] = _extensions[extIdx];
	}

	return result;
}

bool MVKLayer::hasExtensionNamed(const char* extnName) {
    for (auto& extn : _extensions) {
        if ( strcmp(extn.extensionName, extnName) == 0 ) { return true; }
    }
    return false;
}


#pragma mark Object Creation

MVKLayer::MVKLayer() {

	// The core driver layer
	strcpy(_layerProperties.layerName, "MoltenVK");
	strcpy(_layerProperties.description, "MoltenVK driver layer");
	_layerProperties.specVersion = MVK_VULKAN_API_VERSION;
	_layerProperties.implementationVersion = MVK_VERSION;

    // Extensions
    VkExtensionProperties extTmplt;

    memset(extTmplt.extensionName, 0, sizeof(extTmplt.extensionName));
    strcpy(extTmplt.extensionName, VK_MVK_MOLTENVK_EXTENSION_NAME);
    extTmplt.specVersion = VK_MVK_MOLTENVK_SPEC_VERSION;
    _extensions.push_back(extTmplt);

    memset(extTmplt.extensionName, 0, sizeof(extTmplt.extensionName));
	strcpy(extTmplt.extensionName, VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    extTmplt.specVersion = VK_KHR_SWAPCHAIN_SPEC_VERSION;
	_extensions.push_back(extTmplt);

    memset(extTmplt.extensionName, 0, sizeof(extTmplt.extensionName));
    strcpy(extTmplt.extensionName, VK_KHR_SURFACE_EXTENSION_NAME);
    extTmplt.specVersion = VK_KHR_SURFACE_SPEC_VERSION;
    _extensions.push_back(extTmplt);

    memset(extTmplt.extensionName, 0, sizeof(extTmplt.extensionName));
    strcpy(extTmplt.extensionName, VK_AMD_NEGATIVE_VIEWPORT_HEIGHT_EXTENSION_NAME);
    extTmplt.specVersion = VK_AMD_NEGATIVE_VIEWPORT_HEIGHT_SPEC_VERSION;
    _extensions.push_back(extTmplt);

#if MVK_IOS
    memset(extTmplt.extensionName, 0, sizeof(extTmplt.extensionName));
	strcpy(extTmplt.extensionName, VK_MVK_IOS_SURFACE_EXTENSION_NAME);
    extTmplt.specVersion = VK_MVK_IOS_SURFACE_SPEC_VERSION;
	_extensions.push_back(extTmplt);

    memset(extTmplt.extensionName, 0, sizeof(extTmplt.extensionName));
    strcpy(extTmplt.extensionName, VK_IMG_FORMAT_PVRTC_EXTENSION_NAME);
    extTmplt.specVersion = VK_IMG_FORMAT_PVRTC_SPEC_VERSION;
    _extensions.push_back(extTmplt);
#endif
#if MVK_MACOS
    memset(extTmplt.extensionName, 0, sizeof(extTmplt.extensionName));
	strcpy(extTmplt.extensionName, VK_MVK_MACOS_SURFACE_EXTENSION_NAME);
    extTmplt.specVersion = VK_MVK_MACOS_SURFACE_SPEC_VERSION;
	_extensions.push_back(extTmplt);
#endif
}


#pragma mark MVKLayerManager

MVKLayer* MVKLayerManager::getDriverLayer() { return &(_layers[0]); }

MVKLayer* MVKLayerManager::getLayerNamed(const char* pLayerName) {

	// If name is null, return the driver layer
	if ( !pLayerName ) { return getDriverLayer(); }

	// Otherwise look for a layer with the specified name
	uint32_t layCnt = (uint32_t)_layers.size();
	for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
		MVKLayer* pLayer = &_layers[layIdx];
		if ( strcmp(pLayer->getName(), pLayerName) == 0 ) { return pLayer; }
	}
	return VK_NULL_HANDLE;
}


VkResult MVKLayerManager::getLayerProperties(uint32_t* pCount, VkLayerProperties* pProperties) {

	// If properties aren't actually being requested yet, simply update the returned count
	if ( !pProperties ) {
		*pCount = (uint32_t)_layers.size();
		return VK_SUCCESS;
	}

	// Othewise, determine how many layers we'll return, and return that count
	uint32_t layerCnt = (uint32_t)_layers.size();
	VkResult result = (*pCount <= layerCnt) ? VK_SUCCESS : VK_INCOMPLETE;
	*pCount = min(layerCnt, *pCount);

	// Now populate the layer properties
	for (uint32_t layIdx = 0; layIdx < *pCount; layIdx++) {
		pProperties[layIdx] = *(&_layers[layIdx])->getLayerProperties();
	}

	return result;
}


#pragma mark Object Creation

// Populate the layers
MVKLayerManager::MVKLayerManager() {
	_layers.push_back(MVKLayer());
}

static mutex _lock;
static MVKLayerManager* _globalManager = VK_NULL_HANDLE;

MVKLayerManager* MVKLayerManager::globalManager() {
	lock_guard<mutex> lock(_lock);
	if ( !_globalManager ) { _globalManager = new MVKLayerManager(); }
	return _globalManager;
}


