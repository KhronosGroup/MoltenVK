// Copyright 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// Capability probe of the Mac family harness: what Metal and the bundled MoltenVK actually expose on this Mac, before
// and after the test-only device adapters. Creates a Metal device, a Vulkan instance and the physical device list, and
// submits no GPU work. Prints key=value lines; the runner derives every eligibility decision from them, never from the
// name of the Mac or of its GPU, which are printed for the record only.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#define VK_ENABLE_BETA_EXTENSIONS 1
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

static void emit(const std::string& key, long long value) { std::printf("%s=%lld\n", key.c_str(), value); }
static void emit(const std::string& key, const char* value) { std::printf("%s=%s\n", key.c_str(), value); }

static void probeMetal() {
	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	emit("mtl.present", device != nil);
	if (!device) return;
	emit("mtl.name", device.name.UTF8String);
	emit("mtl.registry_id", (long long)device.registryID);
	// Family values as plain numbers: supportsFamily: answers NO for families this OS does not know.
	for (int family = 1; family <= 11; ++family) emit("mtl.family.apple" + std::to_string(family), [device supportsFamily:(MTLGPUFamily)(1000 + family)]);
	emit("mtl.family.mac2", [device supportsFamily:(MTLGPUFamily)2002]);
	long long metal3 = 0, metal4 = 0;
	if (@available(macOS 13.0, *)) metal3 = [device supportsFamily:MTLGPUFamilyMetal3];
	if (@available(macOS 26.0, *)) metal4 = [device supportsFamily:MTLGPUFamilyMetal4];
	emit("mtl.family.metal3", metal3);
	emit("mtl.family.metal4", metal4);
	emit("mtl.barycentric_coordinates", device.supportsShaderBarycentricCoordinates);
	emit("mtl.argument_buffers_tier", (long long)device.argumentBuffersSupport + 1);
	emit("mtl.max_buffer_length", (long long)device.maxBufferLength);
	emit("mtl.unified_memory", device.hasUnifiedMemory);
	emit("mtl.recommended_max_working_set_size", (long long)device.recommendedMaxWorkingSetSize);
	emit("mtl.low_power", device.isLowPower);
	emit("mtl.headless", device.isHeadless);
	emit("mtl.removable", device.isRemovable);
}

static bool has(const std::vector<VkExtensionProperties>& extensions, const char* name) {
	for (const auto& extension : extensions) if (!std::strcmp(extension.extensionName, name)) return true;
	return false;
}

static std::vector<VkExtensionProperties> extensionsOf(VkPhysicalDevice physical) {
	uint32_t count = 0;
	vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, nullptr);
	std::vector<VkExtensionProperties> extensions(count);
	vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, extensions.data());
	return extensions;
}

// Extensions and features the harness cases depend on, under a prefix: vk.public.* before the adapters, vk.* after.
static void probeDevice(VkPhysicalDevice physical, const std::string& prefix) {
	auto extensions = extensionsOf(physical);
	emit(prefix + "extension_count", (long long)extensions.size());
	for (const char* name : {VK_KHR_FRAGMENT_SHADER_BARYCENTRIC_EXTENSION_NAME, VK_EXT_MESH_SHADER_EXTENSION_NAME, VK_KHR_DRAW_INDIRECT_COUNT_EXTENSION_NAME,
	                         VK_EXT_EXTENDED_DYNAMIC_STATE_2_EXTENSION_NAME, VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME, VK_KHR_MAINTENANCE_2_EXTENSION_NAME,
	                         VK_KHR_INDEX_TYPE_UINT8_EXTENSION_NAME, VK_EXT_INDEX_TYPE_UINT8_EXTENSION_NAME})
		emit(prefix + "ext." + name, has(extensions, name));
	VkPhysicalDeviceMeshShaderFeaturesEXT mesh{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT};
	VkPhysicalDeviceFragmentShaderBarycentricFeaturesKHR barycentric{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_BARYCENTRIC_FEATURES_KHR};
	barycentric.pNext = &mesh;
	VkPhysicalDeviceExtendedDynamicState2FeaturesEXT dynamicState2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT};
	dynamicState2.pNext = &barycentric;
	VkPhysicalDeviceVulkan12Features vulkan12{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES};
	vulkan12.pNext = &dynamicState2;
	VkPhysicalDeviceVulkan11Features vulkan11{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES};
	vulkan11.pNext = &vulkan12;
	VkPhysicalDeviceFeatures2 features{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
	features.pNext = &vulkan11;
	vkGetPhysicalDeviceFeatures2(physical, &features);
	const VkPhysicalDeviceFeatures& core = features.features;
	emit(prefix + "feature.fragmentShaderBarycentric", barycentric.fragmentShaderBarycentric);
	emit(prefix + "feature.meshShader", mesh.meshShader);
	emit(prefix + "feature.taskShader", mesh.taskShader);
	if (prefix != "vk.") return;
	emit("vk.feature.tessellationShader", core.tessellationShader);
	emit("vk.feature.multiDrawIndirect", core.multiDrawIndirect);
	emit("vk.feature.drawIndirectFirstInstance", core.drawIndirectFirstInstance);
	emit("vk.feature.vertexPipelineStoresAndAtomics", core.vertexPipelineStoresAndAtomics);
	emit("vk.feature.fragmentStoresAndAtomics", core.fragmentStoresAndAtomics);
	emit("vk.feature.shaderInt16", core.shaderInt16);
	emit("vk.feature.geometryShader", core.geometryShader);
	emit("vk.feature.multiview", vulkan11.multiview);
	emit("vk.feature.shaderDrawParameters", vulkan11.shaderDrawParameters);
	emit("vk.feature.storageInputOutput16", vulkan11.storageInputOutput16);
	emit("vk.feature.bufferDeviceAddress", vulkan12.bufferDeviceAddress);
	emit("vk.feature.shaderFloat16", vulkan12.shaderFloat16);
	emit("vk.feature.drawIndirectCount", vulkan12.drawIndirectCount);
	emit("vk.feature.timelineSemaphore", vulkan12.timelineSemaphore);
	emit("vk.feature.extendedDynamicState2PatchControlPoints", dynamicState2.extendedDynamicState2PatchControlPoints);
	VkPhysicalDeviceMeshShaderPropertiesEXT meshProperties{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_PROPERTIES_EXT};
	VkPhysicalDeviceVulkan11Properties properties11{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES};
	properties11.pNext = mesh.meshShader ? &meshProperties : nullptr;
	VkPhysicalDeviceProperties2 properties{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};
	properties.pNext = &properties11;
	vkGetPhysicalDeviceProperties2(physical, &properties);
	const VkPhysicalDeviceLimits& limits = properties.properties.limits;
	emit("vk.limit.maxTessellationGenerationLevel", limits.maxTessellationGenerationLevel);
	emit("vk.limit.maxTessellationPatchSize", limits.maxTessellationPatchSize);
	emit("vk.limit.maxFragmentInputComponents", limits.maxFragmentInputComponents);
	emit("vk.limit.maxDrawIndirectCount", limits.maxDrawIndirectCount);
	emit("vk.limit.maxMultiviewViewCount", properties11.maxMultiviewViewCount);
	emit("vk.limit.maxMemoryAllocationSize", (long long)properties11.maxMemoryAllocationSize);
	if (mesh.meshShader) {
		emit("vk.limit.maxMeshWorkGroupInvocations", meshProperties.maxMeshWorkGroupInvocations);
		emit("vk.limit.maxMeshOutputVertices", meshProperties.maxMeshOutputVertices);
		emit("vk.limit.maxMeshOutputPrimitives", meshProperties.maxMeshOutputPrimitives);
	}
}

int main() {
	@autoreleasepool {
		emit("os.version", NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
		probeMetal();
		uint32_t instanceVersion = 0;
		vkEnumerateInstanceVersion(&instanceVersion);
		emit("vk.instance_version", (long long)instanceVersion);
		VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
		app.pApplicationName = "Mac family harness probe";
		app.apiVersion = VK_API_VERSION_1_3;
		VkInstanceCreateInfo instanceInfo{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
		instanceInfo.pApplicationInfo = &app;
		VkInstance instance = VK_NULL_HANDLE;
		VkResult created = vkCreateInstance(&instanceInfo, nullptr, &instance);
		emit("vk.instance", created == VK_SUCCESS);
		if (created != VK_SUCCESS) { emit("vk.instance_result", created); return 0; }
		uint32_t count = 0;
		vkEnumeratePhysicalDevices(instance, &count, nullptr);
		std::vector<VkPhysicalDevice> devices(count);
		vkEnumeratePhysicalDevices(instance, &count, devices.data());
		emit("vk.physical_device_count", count);
		if (!count) return 0;
		// The fixtures use the first physical device, as does this probe.
		VkPhysicalDevice physical = devices[0];
		VkPhysicalDeviceProperties properties{};
		vkGetPhysicalDeviceProperties(physical, &properties);
		emit("vk.device_name", properties.deviceName);
		emit("vk.api_version", properties.apiVersion);
		emit("vk.driver_version", properties.driverVersion);
		emit("vk.vendor_id", properties.vendorID);
		emit("vk.device_id", properties.deviceID);
		// MoltenVK stores its git revision, big-endian, in the first four bytes of the pipeline cache UUID.
		char revision[9];
		std::snprintf(revision, sizeof(revision), "%02x%02x%02x%02x", properties.pipelineCacheUUID[0], properties.pipelineCacheUUID[1],
		              properties.pipelineCacheUUID[2], properties.pipelineCacheUUID[3]);
		emit("vk.mvk_revision", revision);
		probeDevice(physical, "vk.public.");
		auto tes = reinterpret_cast<void (*)(VkPhysicalDevice)>(dlsym(RTLD_DEFAULT, "mvkEnableTESFixtureDevice"));
#ifdef PROBE_BARYCENTRIC_ADAPTER_ONLY
		// The experimental candidate activates only VK_KHR_fragment_shader_barycentric.
		void (*mesh)(VkPhysicalDevice) = nullptr;
#else
		auto mesh = reinterpret_cast<void (*)(VkPhysicalDevice)>(dlsym(RTLD_DEFAULT, "mvkEnableMeshTestDevice"));
#endif
		emit("vk.adapter.tes_linked", tes != nullptr);
		emit("vk.adapter.mesh_linked", mesh != nullptr);
		if (tes) tes(physical);
		if (mesh) mesh(physical);
		probeDevice(physical, "vk.");
		vkDestroyInstance(instance, nullptr);
		emit("probe.complete", 1);
	}
	return 0;
}
