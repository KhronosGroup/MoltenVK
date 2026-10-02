// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// The Vulkan library given to the CTS (--deqp-vk-library-path): it loads the MoltenVK test build named by
// PERVERTEX_CTS_MOLTENVK and forwards every entry point to it. The only difference is on the physical devices that
// vkEnumeratePhysicalDevices and vkEnumeratePhysicalDeviceGroups return: before the CTS can query their extensions or
// features, it calls the test build's mvkEnableTESFixtureDevice and mvkEnableMeshTestDevice on each of them, as the
// PerVertex fixtures do. The public extension gate of MoltenVK is never changed.
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void (*EnableFunction)(VkPhysicalDevice);

static PFN_vkGetInstanceProcAddr nextGetInstanceProcAddr;
static PFN_vkEnumeratePhysicalDevices nextEnumeratePhysicalDevices;
static PFN_vkEnumeratePhysicalDeviceGroups nextEnumeratePhysicalDeviceGroups;
static EnableFunction enableBarycentric, enableMesh;

static int load(void) {
	if (nextGetInstanceProcAddr) { return 1; }
	const char* path = getenv("PERVERTEX_CTS_MOLTENVK");
	void* library = path ? dlopen(path, RTLD_NOW | RTLD_LOCAL) : NULL;
	if (!library) {
		fprintf(stderr, "PERVERTEX_CTS_SHIM ERROR: cannot load PERVERTEX_CTS_MOLTENVK=%s: %s\n", path ? path : "(unset)", dlerror());
		return 0;
	}
	enableBarycentric = (EnableFunction)dlsym(library, "mvkEnableTESFixtureDevice");
	enableMesh = (EnableFunction)dlsym(library, "mvkEnableMeshTestDevice");
	if (!enableBarycentric || !enableMesh) {
		fprintf(stderr, "PERVERTEX_CTS_SHIM ERROR: %s is not a MoltenVK test build with the test device adapters\n", path);
		return 0;
	}
	nextGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(library, "vkGetInstanceProcAddr");
	return nextGetInstanceProcAddr != NULL;
}

static void openAdapters(uint32_t count, const VkPhysicalDevice* devices) {
	for (uint32_t i = 0; i < count; ++i) {
		enableBarycentric(devices[i]);
		enableMesh(devices[i]);
	}
}

static VKAPI_ATTR VkResult VKAPI_CALL enumeratePhysicalDevices(VkInstance instance, uint32_t* count, VkPhysicalDevice* devices) {
	VkResult result = nextEnumeratePhysicalDevices(instance, count, devices);
	if (devices && (result == VK_SUCCESS || result == VK_INCOMPLETE)) { openAdapters(*count, devices); }
	return result;
}

static VKAPI_ATTR VkResult VKAPI_CALL enumeratePhysicalDeviceGroups(VkInstance instance, uint32_t* count, VkPhysicalDeviceGroupProperties* groups) {
	VkResult result = nextEnumeratePhysicalDeviceGroups(instance, count, groups);
	if (groups && (result == VK_SUCCESS || result == VK_INCOMPLETE)) {
		for (uint32_t i = 0; i < *count; ++i) { openAdapters(groups[i].physicalDeviceCount, groups[i].physicalDevices); }
	}
	return result;
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance, const char* name) {
	if (!load()) { return NULL; }
	PFN_vkVoidFunction function = nextGetInstanceProcAddr(instance, name);
	if (!function || !name) { return function; }
	// MoltenVK returns the same entry points for every instance, so one saved pointer serves them all.
	if (!strcmp(name, "vkEnumeratePhysicalDevices")) {
		nextEnumeratePhysicalDevices = (PFN_vkEnumeratePhysicalDevices)function;
		return (PFN_vkVoidFunction)enumeratePhysicalDevices;
	}
	if (!strcmp(name, "vkEnumeratePhysicalDeviceGroups") || !strcmp(name, "vkEnumeratePhysicalDeviceGroupsKHR")) {
		nextEnumeratePhysicalDeviceGroups = (PFN_vkEnumeratePhysicalDeviceGroups)function;
		return (PFN_vkVoidFunction)enumeratePhysicalDeviceGroups;
	}
	return function;
}
