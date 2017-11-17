/*
 * MVKBaseObject.h
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

#include <vulkan/vulkan.h>
#include <string>


#pragma mark -
#pragma mark MVKBaseObject

/** 
 * An abstract base class for all MoltenVK C++ classes, to allow common object
 * behaviour, and common custom allocation and deallocation behaviour.
 */
class MVKBaseObject {

public:

    /** Returns the name of the class of which this object is an instance. */
    std::string className();

    virtual ~MVKBaseObject() {}
};


#pragma mark -
#pragma mark MVKConfigurableObject

/** 
 * Abstract class that represents an object whose configuration can be validated and tracked
 * as a queriable result. This is the base class of opaque Vulkan API objects, and commands.
 */
class MVKConfigurableObject : public MVKBaseObject {

public:

	/** Returns a indication of the success of the configuration of this instance. */
	inline VkResult getConfigurationResult() { return _configurationResult; }

	/** If the existing configuration result is VK_SUCCESS, it is set to the specified value. */
    inline void setConfigurationResult(VkResult vkResult) {
        if (_configurationResult == VK_SUCCESS) { _configurationResult = vkResult; }
    }

    /** Resets the indication of the success of the configuration of this instance back to VK_SUCCESS. */
    inline void clearConfigurationResult() { _configurationResult = VK_SUCCESS; }

protected:
	VkResult _configurationResult = VK_SUCCESS;
};
