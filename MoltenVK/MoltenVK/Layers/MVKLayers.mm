/*
 * MVKLayers.mm
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

#include "MVKLayers.h"
#include "MVKEnvironment.h"
#include "MVKFoundation.h"
#include "vk_mvk_moltenvk.h"
#include <mutex>

using namespace std;


#pragma mark MVKLayer

const char* MVKLayer::getName() { return (const char*)&_layerProperties.layerName; }

VkLayerProperties* const MVKLayer::getLayerProperties() { return &_layerProperties; }

VkResult MVKLayer::getInstanceExtensionProperties(uint32_t* pCount, VkExtensionProperties* pProperties) {
	return _supportedInstanceExtensions.getProperties(pCount, pProperties);
}


#pragma mark Object Creation

MVKLayer::MVKLayer() : _supportedInstanceExtensions(nullptr, true) {

	// The core driver layer
	mvkClear(_layerProperties.layerName, VK_MAX_EXTENSION_NAME_SIZE);
	strcpy(_layerProperties.layerName, "MoltenVK");
	mvkClear(_layerProperties.description, VK_MAX_DESCRIPTION_SIZE);
	strcpy(_layerProperties.description, "MoltenVK driver layer");
	_layerProperties.specVersion = mvkGetMVKConfiguration()->apiVersionToAdvertise;
	_layerProperties.implementationVersion = MVK_VERSION;

	((MVKExtensionList*)&_supportedInstanceExtensions)->disableAllButEnabledInstanceExtensions();
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

	// Otherwise, determine how many layers we'll return, and return that count
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
	_layers.emplace_back();
}

static mutex _lock;
static MVKLayerManager* _globalManager = VK_NULL_HANDLE;

MVKLayerManager* MVKLayerManager::globalManager() {
	lock_guard<mutex> lock(_lock);
	if ( !_globalManager ) { _globalManager = new MVKLayerManager(); }
	return _globalManager;
}


