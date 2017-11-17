/*
 * MVKLayers.h
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

#pragma once

#include "mvk_vulkan.h"
#include "MVKBaseObject.h"
#include <vector>


#pragma mark MVKLayer

/** Represents a single Vulkan layer. */
class MVKLayer : public MVKConfigurableObject {

public:

	/** Returns the name of this layer. */
	const char* getName();

	/** Returns the properties associated with this layer. */
	VkLayerProperties* const getLayerProperties();

	/**
	 * If pProperties is null, the value of pCount is updated with the number of extensions
	 * available in this layer.
	 *
	 * If pProperties is not null, then pCount extension properties are copied into the array.
	 * If the number of available layers is less than pCount, the value of pCount is updated
	 * to indicate the number of extension properties actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of extensions
	 * available in this instance is larger than the specified pCount. Returns other values
	 * if an error occurs.
	 */
	VkResult getExtensionProperties(uint32_t* pCount, VkExtensionProperties* pProperties);

    /** Returns whether this layer supports the specified extension. */
    bool hasExtensionNamed(const char* extnName);

	/** Default constructor.  This represents the driver implementation. */
	MVKLayer();

protected:
	VkLayerProperties _layerProperties;
	std::vector<VkExtensionProperties> _extensions;
	
};


#pragma mark MVKLayerManager

/** Manages a set of Vulkan layers. */
class MVKLayerManager : public MVKConfigurableObject {

public:

	/** Returns a pointer to the driver layer. */
	MVKLayer* getDriverLayer();

	/**
	 * Returns a pointe to the layer with the specified name, 
	 * or null if no layer was found with that name.
	 *
	 * If pLayerName is null, returns the driver layer, which is
	 * the same layer returned by the getDriverLayer() function.
	 */
	MVKLayer* getLayerNamed(const char* pLayerName);

	/**
	 * If pProperties is null, the value of pCount is updated with the number of layers
	 * available in this instance.
	 *
	 * If pProperties is not null, then pCount layer properties are copied into the array.
	 * If the number of available layers is less than pCount, the value of pCount is updated
	 * to indicate the number of layer properties actually returned in the array.
	 * 
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of layers
	 * available in this instance is larger than the specified pCount. Returns other
	 * values if an error occurs.
	 */
	VkResult getLayerProperties(uint32_t* pCount, VkLayerProperties* pProperties);


#pragma mark Object Creation
	
	/** Creates a default layer manager with a single layer representing the driver implementation. */
	MVKLayerManager();

	/** 
	 * Returns the singleton instance representing the global layers populated by the Loader.
	 * 
	 * This function is thread-safe.
	 */
	static MVKLayerManager* globalManager();

protected:
	std::vector<MVKLayer> _layers;

};

