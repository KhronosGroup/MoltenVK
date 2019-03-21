/*
 * MVKLayers.mm
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

#include "MVKLayers.h"
#include "MVKEnvironment.h"
#include "vk_mvk_moltenvk.h"
#include <mutex>

using namespace std;


#pragma mark MVKLayer

const char* MVKLayer::getName() { return (const char*)&_layerProperties.layerName; }

VkLayerProperties* const MVKLayer::getLayerProperties() { return &_layerProperties; }

VkResult MVKLayer::getExtensionProperties(uint32_t* pCount, VkExtensionProperties* pProperties) {

	uint32_t enabledCnt = 0;

	// Iterate extensions and handle those that are enabled. Count them,
	// and if they are to be returned, and there is room, do so.
	uint32_t extnCnt = _supportedExtensions.getCount();
	MVKExtension* extnAry = &_supportedExtensions.extensionArray;
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


#pragma mark Object Creation

MVKLayer::MVKLayer() : _supportedExtensions(true) {

	// The core driver layer
	memset(_layerProperties.layerName, 0, sizeof(_layerProperties.layerName));
	strcpy(_layerProperties.layerName, "MoltenVK");
	memset(_layerProperties.description, 0, sizeof(_layerProperties.description));
	strcpy(_layerProperties.description, "MoltenVK driver layer");
	_layerProperties.specVersion = MVK_VULKAN_API_VERSION;
	_layerProperties.implementationVersion = MVK_VERSION;
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
	VkResult result = (*pCount >= layerCnt) ? VK_SUCCESS : VK_INCOMPLETE;
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


