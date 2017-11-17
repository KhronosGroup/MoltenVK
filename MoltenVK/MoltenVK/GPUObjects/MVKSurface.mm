/*
 * MVKSurface.mm
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

#include "MVKSurface.h"
#include "MVKInstance.h"
#include "MVKFoundation.h"


#pragma mark MVKSurface

#pragma mark Construction

MVKSurface::MVKSurface(MVKInstance* mvkInstance,
					   const Vk_PLATFORM_SurfaceCreateInfoMVK* pCreateInfo,
					   const VkAllocationCallbacks* pAllocator) {

    CALayer* viewLayer = ((PLATFORM_VIEW_CLASS*)pCreateInfo->pView).layer;
    if ( [viewLayer isKindOfClass: [CAMetalLayer class]] ) {
        _mtlCAMetalLayer = (CAMetalLayer*)[viewLayer retain];		// retained
    } else {
        setConfigurationResult(mvkNotifyErrorWithText(VK_ERROR_INITIALIZATION_FAILED, "On-screen rendering requires a view that is backed by a layer of type CAMetalLayer."));
        _mtlCAMetalLayer = nil;
    }
}

MVKSurface::~MVKSurface() {
	[_mtlCAMetalLayer release];
}

