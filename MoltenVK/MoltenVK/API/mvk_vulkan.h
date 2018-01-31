/*
 * mvk_vulkan.h
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


/** 
 * This is a convenience header file that loads vulkan.h with the appropriate MoltenVK
 * Vulkan platform extensions automatically enabled for iOS or macOS.
 *
 * When building for iOS, this header automatically enables the VK_MVK_ios_surface Vulkan extension.
 * When building for macOS, this header automatically enables the VK_MVK_macos_surface Vulkan extension.
 *
 * Use the following form when including this header file:
 *
 *     #include <MoltenVK/mvk_vulkan.h>
 */

#ifndef __mvk_vulkan_h_
#define __mvk_vulkan_h_ 1


#include <Availability.h>

#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
#	define VK_USE_PLATFORM_IOS_MVK				1
#endif

#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
#	define VK_USE_PLATFORM_MACOS_MVK			1
#endif

#include <vulkan/vulkan.h>

#endif
