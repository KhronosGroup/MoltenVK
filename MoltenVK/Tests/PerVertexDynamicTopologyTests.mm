// Copyright 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// Portable PerVertexKHR with VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY. One render pass draws the same vertices with each
// topology of a class (triangle list, strip, fan; or line list, strip), changing the topology between draws. The image
// must equal the same draws through one static pipeline per topology, and differ from the dynamic pipeline kept at its
// first topology, so that each change is applied. Direct, indexed, indirect or indexed indirect draws. The adjacency
// form sets VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST_WITH_ADJACENCY, valid within the triangle class but outside capture and
// replay: recording must fail with VK_ERROR_FEATURE_NOT_PRESENT and nothing is submitted. The ordinary fragment has no
// PerVertexKHR input, so the same draws test MoltenVK's ordinary path, which converts triangle fans to triangles.
// The weights fragment (triangles only) outputs barycentric weights and index-weighted vertex values. Its static and
// dynamic images must also equal an independent reference: the draws triangulated explicitly in the order of the Vulkan
// barycentric order table and drawn without PerVertexKHR (pervertex-dynamic-reference.vert). The same reference with
// every triangle's corners turned by one must differ, so that the check sees vertex order, not only coverage.
// weights-w and weights-w-noperspective give each corner of a triangle a different w (same window position), so that
// perspective and linear interpolation differ: BaryCoordKHR against the reference weight interpolated with perspective,
// BaryCoordNoPerspKHR against the one interpolated without. The reference interpolated the other way must differ, so
// that w reaches the result.
// Usage: pervertex-dynamic-topology <shader directory> triangles|lines direct|indexed|indirect|indexed-indirect|adjacency
//        [pervertex|ordinary|weights|weights-w|weights-w-noperspective]
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <string>
#include <vector>

static void check(VkResult result, const char* step) {
	if (result != VK_SUCCESS) { std::fprintf(stderr, "%s: %d\n", step, int(result)); std::exit(1); }
}

static std::vector<uint32_t> readSpirv(const std::string& path) {
	std::ifstream file(path, std::ios::binary | std::ios::ate);
	if (!file) { std::fprintf(stderr, "Cannot open %s\n", path.c_str()); std::exit(2); }
	std::vector<uint32_t> words(size_t(file.tellg()) / 4);
	file.seekg(0);
	file.read(reinterpret_cast<char*>(words.data()), words.size() * 4);
	return words;
}

static bool hasExtension(const std::vector<VkExtensionProperties>& extensions, const char* name) {
	for (const auto& extension : extensions) if (!strcmp(extension.extensionName, name)) return true;
	return false;
}

constexpr uint32_t kSide = 64;

struct Buffer { VkBuffer buffer = VK_NULL_HANDLE; VkDeviceMemory memory = VK_NULL_HANDLE; uint8_t* data = nullptr; };

int main(int argc, char** argv) {
	@autoreleasepool {
	if (argc != 4 && argc != 5) { std::fprintf(stderr, "Usage: pervertex-dynamic-topology shader-dir triangles|lines direct|indexed|indirect|indexed-indirect|adjacency [pervertex|ordinary|weights|weights-w|weights-w-noperspective]\n"); return 2; }
	const std::string shaders = argv[1], klass = argv[2], form = argv[3], fragmentKind = argc == 5 ? argv[4] : "pervertex";
	const bool indexed = form == "indexed" || form == "indexed-indirect", indirect = form == "indirect" || form == "indexed-indirect";
	const bool adjacency = form == "adjacency", ordinary = fragmentKind == "ordinary";
	const bool variedW = fragmentKind == "weights-w" || fragmentKind == "weights-w-noperspective", noPerspective = fragmentKind == "weights-w-noperspective";
	const bool weights = fragmentKind == "weights" || variedW;
	if ((klass != "triangles" && klass != "lines") || (form != "direct" && !indexed && !indirect && !adjacency) || (adjacency && (klass != "triangles" || fragmentKind != "pervertex")) || (weights && klass != "triangles") || (!ordinary && !weights && fragmentKind != "pervertex")) { std::fprintf(stderr, "Unknown case\n"); return 2; }
	const std::vector<VkPrimitiveTopology> topologies = klass == "triangles"
		? std::vector<VkPrimitiveTopology>{VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN}
		: std::vector<VkPrimitiveTopology>{VK_PRIMITIVE_TOPOLOGY_LINE_LIST, VK_PRIMITIVE_TOPOLOGY_LINE_STRIP};

	uint32_t count = 0;
	check(vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr), "Enumerate instance extensions");
	std::vector<VkExtensionProperties> instanceExtensions(count);
	check(vkEnumerateInstanceExtensionProperties(nullptr, &count, instanceExtensions.data()), "Read instance extensions");
	const bool portability = hasExtension(instanceExtensions, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
	const char* portabilityName = VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;
	VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
	app.pApplicationName = "PerVertexKHR dynamic topology";
	app.apiVersion = VK_API_VERSION_1_3;  // vkCmdSetPrimitiveTopology is core
	VkInstanceCreateInfo instanceInfo{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
	instanceInfo.pApplicationInfo = &app;
	instanceInfo.flags = portability ? VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR : 0;
	instanceInfo.enabledExtensionCount = portability ? 1 : 0;
	instanceInfo.ppEnabledExtensionNames = portability ? &portabilityName : nullptr;
	VkInstance instance = VK_NULL_HANDLE;
	check(vkCreateInstance(&instanceInfo, nullptr, &instance), "Create instance");
	count = 1;
	VkPhysicalDevice physical = VK_NULL_HANDLE;
	VkResult enumerated = vkEnumeratePhysicalDevices(instance, &count, &physical);
	if (enumerated != VK_SUCCESS && enumerated != VK_INCOMPLETE) check(enumerated, "Enumerate devices");
	// The combined test library exposes an adapter; shipping libraries have no such symbol.
	if (auto enable = reinterpret_cast<void (*)(VkPhysicalDevice)>(dlsym(RTLD_DEFAULT, "mvkEnableTESFixtureDevice"))) enable(physical);
	check(vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, nullptr), "Enumerate device extensions");
	std::vector<VkExtensionProperties> extensions(count);
	check(vkEnumerateDeviceExtensionProperties(physical, nullptr, &count, extensions.data()), "Read device extensions");
	std::vector<const char*> deviceExtensions{VK_KHR_FRAGMENT_SHADER_BARYCENTRIC_EXTENSION_NAME};
	if (!hasExtension(extensions, deviceExtensions[0])) { std::fprintf(stderr, "Missing %s\n", deviceExtensions[0]); return 3; }
	if (hasExtension(extensions, "VK_KHR_portability_subset")) deviceExtensions.push_back("VK_KHR_portability_subset");
	VkPhysicalDeviceFragmentShaderBarycentricFeaturesKHR barycentric{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_BARYCENTRIC_FEATURES_KHR};
	VkPhysicalDeviceVulkan11Features features11{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES};
	features11.pNext = &barycentric;
	VkPhysicalDeviceFeatures2 features{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
	features.pNext = &features11;
	vkGetPhysicalDeviceFeatures2(physical, &features);
	if (!barycentric.fragmentShaderBarycentric || !features11.shaderDrawParameters || !features.features.vertexPipelineStoresAndAtomics || (indirect && !features.features.drawIndirectFirstInstance)) { std::fprintf(stderr, "Required features are unavailable\n"); return 3; }
	VkPhysicalDeviceVulkan11Features enable11{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES};
	enable11.shaderDrawParameters = VK_TRUE;
	enable11.pNext = &barycentric;
	VkPhysicalDeviceFeatures2 enabled{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
	enabled.pNext = &enable11;
	enabled.features.vertexPipelineStoresAndAtomics = VK_TRUE;
	enabled.features.drawIndirectFirstInstance = indirect;
	vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, nullptr);
	std::vector<VkQueueFamilyProperties> families(count);
	vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, families.data());
	uint32_t family = 0;
	while (family < count && !(families[family].queueFlags & VK_QUEUE_GRAPHICS_BIT)) ++family;
	float priority = 1;
	VkDeviceQueueCreateInfo queueInfo{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
	queueInfo.queueFamilyIndex = family;
	queueInfo.queueCount = 1;
	queueInfo.pQueuePriorities = &priority;
	VkDeviceCreateInfo deviceInfo{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
	deviceInfo.pNext = &enabled;
	deviceInfo.queueCreateInfoCount = 1;
	deviceInfo.pQueueCreateInfos = &queueInfo;
	deviceInfo.enabledExtensionCount = uint32_t(deviceExtensions.size());
	deviceInfo.ppEnabledExtensionNames = deviceExtensions.data();
	VkDevice device = VK_NULL_HANDLE;
	check(vkCreateDevice(physical, &deviceInfo, nullptr, &device), "Create device");
	VkQueue queue = VK_NULL_HANDLE;
	vkGetDeviceQueue(device, family, 0, &queue);
	VkPhysicalDeviceProperties properties{};
	vkGetPhysicalDeviceProperties(physical, &properties);
	std::printf("DEVICE=%s class=%s form=%s fragment=%s\n", properties.deviceName, klass.c_str(), form.c_str(), fragmentKind.c_str());

	auto memoryType = [&](uint32_t bits, VkMemoryPropertyFlags flags) {
		VkPhysicalDeviceMemoryProperties memory{};
		vkGetPhysicalDeviceMemoryProperties(physical, &memory);
		for (uint32_t i = 0; i < memory.memoryTypeCount; ++i)
			if ((bits & (1u << i)) && (memory.memoryTypes[i].propertyFlags & flags) == flags) return i;
		std::fprintf(stderr, "No suitable memory type\n");
		std::exit(3);
	};
	auto makeBuffer = [&](VkDeviceSize size, VkBufferUsageFlags usage) {
		Buffer b;
		VkBufferCreateInfo info{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
		info.size = size;
		info.usage = usage;
		check(vkCreateBuffer(device, &info, nullptr, &b.buffer), "Create buffer");
		VkMemoryRequirements requirements{};
		vkGetBufferMemoryRequirements(device, b.buffer, &requirements);
		VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
		allocation.allocationSize = requirements.size;
		allocation.memoryTypeIndex = memoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
		check(vkAllocateMemory(device, &allocation, nullptr, &b.memory), "Allocate buffer");
		check(vkBindBufferMemory(device, b.buffer, b.memory, 0), "Bind buffer");
		void* mapped = nullptr;
		check(vkMapMemory(device, b.memory, 0, size, 0, &mapped), "Map buffer");
		b.data = static_cast<uint8_t*>(mapped);
		memset(b.data, 0, size);
		return b;
	};
	// The VS records its invocations here; identity indices address the corners it reads by gl_VertexIndex.
	Buffer effects = makeBuffer(16 + (1u << 18) * 16, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
	Buffer indices = makeBuffer(14 * sizeof(uint32_t), VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
	for (uint32_t i = 0; i < 14; ++i) reinterpret_cast<uint32_t*>(indices.data)[i] = i;
	// One command per draw, with the arguments of the direct and indexed forms.
	Buffer commands = makeBuffer(3 * sizeof(VkDrawIndexedIndirectCommand), VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT);
	for (uint32_t i = 0; i < 3; ++i) {
		if (indexed) reinterpret_cast<VkDrawIndexedIndirectCommand*>(commands.data)[i] = {6, 1, 4, 0, 2 + i % 2};
		else reinterpret_cast<VkDrawIndirectCommand*>(commands.data)[i] = {6, 1, 4, 2 + i % 2};
	}
	Buffer readback = makeBuffer(kSide * kSide * 4, VK_BUFFER_USAGE_TRANSFER_DST_BIT);

	VkImageCreateInfo imageInfo{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
	imageInfo.imageType = VK_IMAGE_TYPE_2D;
	imageInfo.format = VK_FORMAT_R8G8B8A8_UNORM;
	imageInfo.extent = {kSide, kSide, 1};
	imageInfo.mipLevels = 1;
	imageInfo.arrayLayers = 1;
	imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
	imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
	imageInfo.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
	VkImage image = VK_NULL_HANDLE;
	check(vkCreateImage(device, &imageInfo, nullptr, &image), "Create image");
	VkMemoryRequirements imageRequirements{};
	vkGetImageMemoryRequirements(device, image, &imageRequirements);
	VkMemoryAllocateInfo imageAllocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
	imageAllocation.allocationSize = imageRequirements.size;
	imageAllocation.memoryTypeIndex = memoryType(imageRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
	VkDeviceMemory imageMemory = VK_NULL_HANDLE;
	check(vkAllocateMemory(device, &imageAllocation, nullptr, &imageMemory), "Allocate image");
	check(vkBindImageMemory(device, image, imageMemory, 0), "Bind image");
	VkImageViewCreateInfo viewInfo{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
	viewInfo.image = image;
	viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
	viewInfo.format = imageInfo.format;
	viewInfo.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
	VkImageView view = VK_NULL_HANDLE;
	check(vkCreateImageView(device, &viewInfo, nullptr, &view), "Create image view");
	VkAttachmentDescription attachment{};
	attachment.format = imageInfo.format;
	attachment.samples = VK_SAMPLE_COUNT_1_BIT;
	attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
	attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
	attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	attachment.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
	VkAttachmentReference reference{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
	VkSubpassDescription subpass{};
	subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
	subpass.colorAttachmentCount = 1;
	subpass.pColorAttachments = &reference;
	VkSubpassDependency toTransfer{0, VK_SUBPASS_EXTERNAL, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT, 0};
	VkRenderPassCreateInfo passInfo{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
	passInfo.attachmentCount = 1;
	passInfo.pAttachments = &attachment;
	passInfo.subpassCount = 1;
	passInfo.pSubpasses = &subpass;
	passInfo.dependencyCount = 1;
	passInfo.pDependencies = &toTransfer;
	VkRenderPass renderPass = VK_NULL_HANDLE;
	check(vkCreateRenderPass(device, &passInfo, nullptr, &renderPass), "Create render pass");
	VkFramebufferCreateInfo framebufferInfo{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
	framebufferInfo.renderPass = renderPass;
	framebufferInfo.attachmentCount = 1;
	framebufferInfo.pAttachments = &view;
	framebufferInfo.width = kSide;
	framebufferInfo.height = kSide;
	framebufferInfo.layers = 1;
	VkFramebuffer framebuffer = VK_NULL_HANDLE;
	check(vkCreateFramebuffer(device, &framebufferInfo, nullptr, &framebuffer), "Create framebuffer");

	VkDescriptorSetLayoutBinding binding{0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_VERTEX_BIT, nullptr};
	VkDescriptorSetLayoutCreateInfo setLayoutInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
	setLayoutInfo.bindingCount = 1;
	setLayoutInfo.pBindings = &binding;
	VkDescriptorSetLayout setLayout = VK_NULL_HANDLE;
	check(vkCreateDescriptorSetLayout(device, &setLayoutInfo, nullptr, &setLayout), "Create set layout");
	VkDescriptorPoolSize poolSize{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1};
	VkDescriptorPoolCreateInfo descriptorPoolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
	descriptorPoolInfo.maxSets = 1;
	descriptorPoolInfo.poolSizeCount = 1;
	descriptorPoolInfo.pPoolSizes = &poolSize;
	VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
	check(vkCreateDescriptorPool(device, &descriptorPoolInfo, nullptr, &descriptorPool), "Create descriptor pool");
	VkDescriptorSetAllocateInfo setInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
	setInfo.descriptorPool = descriptorPool;
	setInfo.descriptorSetCount = 1;
	setInfo.pSetLayouts = &setLayout;
	VkDescriptorSet set = VK_NULL_HANDLE;
	check(vkAllocateDescriptorSets(device, &setInfo, &set), "Allocate descriptor set");
	VkDescriptorBufferInfo effectsInfo{effects.buffer, 0, VK_WHOLE_SIZE};
	VkWriteDescriptorSet write{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
	write.dstSet = set;
	write.descriptorCount = 1;
	write.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
	write.pBufferInfo = &effectsInfo;
	vkUpdateDescriptorSets(device, 1, &write, 0, nullptr);
	VkPipelineLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
	layoutInfo.setLayoutCount = 1;
	layoutInfo.pSetLayouts = &setLayout;
	VkPipelineLayout layout = VK_NULL_HANDLE;
	check(vkCreatePipelineLayout(device, &layoutInfo, nullptr, &layout), "Create pipeline layout");
	struct ReferenceDraw { uint32_t topology, rotate; };
	VkPushConstantRange referenceRange{VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(ReferenceDraw)};
	VkPipelineLayoutCreateInfo referenceLayoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
	referenceLayoutInfo.pushConstantRangeCount = 1;
	referenceLayoutInfo.pPushConstantRanges = &referenceRange;
	VkPipelineLayout referenceLayout = VK_NULL_HANDLE;
	check(vkCreatePipelineLayout(device, &referenceLayoutInfo, nullptr, &referenceLayout), "Create reference pipeline layout");

	auto module = [&](const std::string& name) {
		auto code = readSpirv(shaders + "/" + name);
		VkShaderModuleCreateInfo info{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
		info.codeSize = code.size() * 4;
		info.pCode = code.data();
		VkShaderModule result = VK_NULL_HANDLE;
		check(vkCreateShaderModule(device, &info, nullptr, &result), "Create shader module");
		return result;
	};
	// The PORTABLE fragment also reads BaryCoordKHR, so every pipeline takes the portable capture and replay.
	VkShaderModule vertex = module(variedW ? "indirect-w.vert.spv" : "indirect.vert.spv");
	VkShaderModule fragment = module(ordinary ? "ordinary.frag.spv" : noPerspective ? "weights-noperspective.frag.spv" : weights ? "weights.frag.spv" : "pervertex-portable.frag.spv");
	auto graphicsPipeline = [&](VkPrimitiveTopology topology, bool dynamicTopology, VkPipeline& result, VkShaderModule vertexModule, VkShaderModule fragmentModule, VkPipelineLayout pipelineLayout) {
		VkPipelineShaderStageCreateInfo stages[2]{{VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO}, {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO}};
		stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
		stages[0].module = vertexModule;
		stages[0].pName = "main";
		stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
		stages[1].module = fragmentModule;
		stages[1].pName = "main";
		VkPipelineVertexInputStateCreateInfo vertexInput{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
		VkPipelineInputAssemblyStateCreateInfo assembly{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
		assembly.topology = topology;
		VkViewport viewport{0, 0, float(kSide), float(kSide), 0, 1};
		VkRect2D scissor{{0, 0}, {kSide, kSide}};
		VkPipelineViewportStateCreateInfo viewportState{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
		viewportState.viewportCount = 1;
		viewportState.pViewports = &viewport;
		viewportState.scissorCount = 1;
		viewportState.pScissors = &scissor;
		VkPipelineRasterizationStateCreateInfo raster{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
		raster.polygonMode = VK_POLYGON_MODE_FILL;
		raster.cullMode = VK_CULL_MODE_NONE;
		raster.lineWidth = 1;
		VkPipelineMultisampleStateCreateInfo multisample{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
		multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
		// Blending makes the order of the overlapping draws part of the result.
		VkPipelineColorBlendAttachmentState blendAttachment{};
		blendAttachment.blendEnable = VK_TRUE;
		blendAttachment.srcColorBlendFactor = blendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
		blendAttachment.dstColorBlendFactor = blendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
		blendAttachment.colorBlendOp = blendAttachment.alphaBlendOp = VK_BLEND_OP_ADD;
		blendAttachment.colorWriteMask = 0xF;
		VkPipelineColorBlendStateCreateInfo blend{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
		blend.attachmentCount = 1;
		blend.pAttachments = &blendAttachment;
		const VkDynamicState dynamicState = VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY;
		VkPipelineDynamicStateCreateInfo dynamic{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
		dynamic.dynamicStateCount = 1;
		dynamic.pDynamicStates = &dynamicState;
		VkGraphicsPipelineCreateInfo info{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
		info.stageCount = 2;
		info.pStages = stages;
		info.pVertexInputState = &vertexInput;
		info.pInputAssemblyState = &assembly;
		info.pViewportState = &viewportState;
		info.pRasterizationState = &raster;
		info.pMultisampleState = &multisample;
		info.pColorBlendState = &blend;
		info.pDynamicState = dynamicTopology ? &dynamic : nullptr;
		info.layout = pipelineLayout;
		info.renderPass = renderPass;
		return vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &info, nullptr, &result);
	};
	std::vector<VkPipeline> statics(topologies.size());
	for (size_t i = 0; i < topologies.size(); ++i) check(graphicsPipeline(topologies[i], false, statics[i], vertex, fragment, layout), "Create static pipeline");
	VkPipeline referencePipeline = VK_NULL_HANDLE;
	if (weights) check(graphicsPipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, false, referencePipeline, module(variedW ? "reference-w.vert.spv" : "reference.vert.spv"), module(noPerspective ? "reference-noperspective.frag.spv" : "reference.frag.spv"), referenceLayout), "Create reference pipeline");
	VkPipeline otherReferencePipeline = VK_NULL_HANDLE;
	if (variedW) check(graphicsPipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, false, otherReferencePipeline, module("reference-w.vert.spv"), module(noPerspective ? "reference.frag.spv" : "reference-noperspective.frag.spv"), referenceLayout), "Create reference pipeline interpolated the other way");
	VkPipeline dynamicPipeline = VK_NULL_HANDLE;
	VkResult dynamicCreated = graphicsPipeline(topologies[0], true, dynamicPipeline, vertex, fragment, layout);
	std::printf("dynamic topology pipeline: vkCreateGraphicsPipelines=%d\n", int(dynamicCreated));
	if (dynamicCreated != VK_SUCCESS) { std::printf("PERVERTEX_DYNAMIC_TOPOLOGY FAIL %s %s %s: the dynamic topology pipeline is refused\n", klass.c_str(), form.c_str(), fragmentKind.c_str()); return 1; }

	VkCommandPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
	poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
	poolInfo.queueFamilyIndex = family;
	VkCommandPool pool = VK_NULL_HANDLE;
	check(vkCreateCommandPool(device, &poolInfo, nullptr, &pool), "Create command pool");
	VkCommandBufferAllocateInfo commandInfo{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
	commandInfo.commandPool = pool;
	commandInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	commandInfo.commandBufferCount = 1;
	VkCommandBuffer cb = VK_NULL_HANDLE;
	check(vkAllocateCommandBuffers(device, &commandInfo, &cb), "Allocate command buffer");
	VkFenceCreateInfo fenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
	VkFence fence = VK_NULL_HANDLE;
	check(vkCreateFence(device, &fenceInfo, nullptr, &fence), "Create fence");

	// Draw i: corners 4..9 of the VS, one instance at firstInstance 2 or 3 (left or right), so that the draws overlap
	// in pairs. mode 0: one static pipeline per topology; 1: the dynamic pipeline, changing topology between draws;
	// 2: the dynamic pipeline kept at the first topology; 3: the triangulated reference; 4: the reference turned by one;
	// 5: the reference interpolated the other way (weights-w kinds).
	struct Result { std::vector<uint8_t> rgba; uint32_t invocations = 0; };
	auto render = [&](int mode) {
		check(vkResetCommandBuffer(cb, 0), "Reset command buffer");
		VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
		check(vkBeginCommandBuffer(cb, &begin), "Begin command buffer");
		VkClearValue clear{};
		VkRenderPassBeginInfo pass{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};
		pass.renderPass = renderPass;
		pass.framebuffer = framebuffer;
		pass.renderArea = {{0, 0}, {kSide, kSide}};
		pass.clearValueCount = 1;
		pass.pClearValues = &clear;
		vkCmdBeginRenderPass(cb, &pass, VK_SUBPASS_CONTENTS_INLINE);
		if (mode >= 3) {
			vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, mode == 5 ? otherReferencePipeline : referencePipeline);
			for (uint32_t i = 0; i < uint32_t(topologies.size()); ++i) {
				const ReferenceDraw draw{uint32_t(topologies[i]), uint32_t(mode == 4)};
				vkCmdPushConstants(cb, referenceLayout, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(draw), &draw);
				// Six vertices: a list has two triangles, a strip or a fan four.
				vkCmdDraw(cb, topologies[i] == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST ? 6 : 12, 1, 0, 2 + i % 2);
			}
		} else if (mode) vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, dynamicPipeline);
		for (size_t i = 0; mode < 3 && i < topologies.size(); ++i) {
			if (mode == 0) vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, statics[i]);
			else vkCmdSetPrimitiveTopology(cb, adjacency && i == 1 ? VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST_WITH_ADJACENCY : mode == 1 ? topologies[i] : topologies[0]);
			vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, layout, 0, 1, &set, 0, nullptr);
			const uint32_t firstInstance = 2 + uint32_t(i % 2);
			if (indexed) vkCmdBindIndexBuffer(cb, indices.buffer, 0, VK_INDEX_TYPE_UINT32);
			if (indirect && indexed) vkCmdDrawIndexedIndirect(cb, commands.buffer, i * sizeof(VkDrawIndexedIndirectCommand), 1, sizeof(VkDrawIndexedIndirectCommand));
			else if (indirect) vkCmdDrawIndirect(cb, commands.buffer, i * sizeof(VkDrawIndirectCommand), 1, sizeof(VkDrawIndirectCommand));
			else if (indexed) vkCmdDrawIndexed(cb, 6, 1, 4, 0, firstInstance);
			else vkCmdDraw(cb, 6, 1, 4, firstInstance);
		}
		vkCmdEndRenderPass(cb);
		VkBufferImageCopy copy{};
		copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
		copy.imageExtent = {kSide, kSide, 1};
		vkCmdCopyImageToBuffer(cb, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &copy);
		VkMemoryBarrier toHost{VK_STRUCTURE_TYPE_MEMORY_BARRIER};
		toHost.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT | VK_ACCESS_SHADER_WRITE_BIT;
		toHost.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
		vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT | VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &toHost, 0, nullptr, 0, nullptr);
		VkResult ended = vkEndCommandBuffer(cb);
		if (adjacency && mode == 1) {
			const bool refused = ended == VK_ERROR_FEATURE_NOT_PRESENT;
			std::printf("adjacency through the dynamic topology: vkEndCommandBuffer=%d expected=%d, nothing submitted\n", int(ended), int(VK_ERROR_FEATURE_NOT_PRESENT));
			std::printf("PERVERTEX_DYNAMIC_TOPOLOGY %s triangles adjacency\n", refused ? "PASS" : "FAIL");
			std::exit(refused ? 0 : 2);
		}
		if (ended != VK_SUCCESS) { std::printf("mode %d: vkEndCommandBuffer=%d\n", mode, int(ended)); std::exit(1); }
		memset(effects.data, 0, 16);
		memset(readback.data, 0, kSide * kSide * 4);
		check(vkResetFences(device, 1, &fence), "Reset fence");
		VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
		submit.commandBufferCount = 1;
		submit.pCommandBuffers = &cb;
		check(vkQueueSubmit(queue, 1, &submit, fence), "Submit");
		check(vkWaitForFences(device, 1, &fence, VK_TRUE, 20ull * 1000 * 1000 * 1000), "Wait");
		Result result;
		result.rgba.assign(readback.data, readback.data + kSide * kSide * 4);
		memcpy(&result.invocations, effects.data, 4);
		return result;
	};
	Result staticResult = render(0), dynamicResult = render(1), unchanged = render(2);
	// Pixels that differ, and the largest channel difference with its position.
	auto compare = [&](const Result& a, const Result& b, const char* what) {
		uint32_t differing = 0, worst = 0, at = 0;
		for (size_t i = 0; i < a.rgba.size(); i += 4) {
			differing += memcmp(&a.rgba[i], &b.rgba[i], 4) != 0;
			for (size_t c = 0; c < 4; ++c) {
				uint32_t d = uint32_t(std::abs(int(a.rgba[i + c]) - int(b.rgba[i + c])));
				if (d > worst) { worst = d; at = uint32_t(i / 4); }
			}
		}
		if (what) std::printf("%s: pixel_mismatches=%u max_channel_difference=%u at (%u, %u)\n", what, differing, worst, at % kSide, at / kSide);
		return differing;
	};
	uint32_t mismatches = compare(staticResult, dynamicResult, nullptr), covered = 0;
	for (size_t i = 0; i < staticResult.rgba.size(); i += 4) covered += staticResult.rgba[i + 3] != 0;
	bool referenceMatches = true;
	if (weights) {
		Result reference = render(3), turned = render(4);
		uint32_t referenceCovered = 0;
		for (size_t i = 0; i < reference.rgba.size(); i += 4) referenceCovered += reference.rgba[i + 3] != 0;
		std::printf("reference: covered=%u\n", referenceCovered);
		const uint32_t staticDiffers = compare(staticResult, reference, "static vs reference");
		const uint32_t dynamicDiffers = compare(dynamicResult, reference, "dynamic vs reference");
		const uint32_t turnedDiffers = compare(dynamicResult, turned, "dynamic vs reference turned by one (must differ)");
		uint32_t otherDiffers = 1;
		if (variedW) otherDiffers = compare(dynamicResult, render(5), "dynamic vs reference interpolated the other way (must differ)");
		referenceMatches = referenceCovered == covered && staticDiffers == 0 && dynamicDiffers == 0 && turnedDiffers > 0 && otherDiffers > 0;
	}
	const bool changed = dynamicResult.rgba != unchanged.rgba;
	const uint32_t expected = uint32_t(topologies.size()) * 6;
	std::printf("static vs dynamic: covered=%u pixel_mismatches=%u; dynamic differs from its first topology kept=%d; VS invocations static=%u dynamic=%u expected=%u\n",
	            covered, mismatches, int(changed), staticResult.invocations, dynamicResult.invocations, expected);
	// The ordinary path may shade a vertex more than once (a converted fan is indexed): it must only match static.
	const bool invocationsMatch = ordinary ? staticResult.invocations >= expected && dynamicResult.invocations == staticResult.invocations
	                                       : staticResult.invocations == expected && dynamicResult.invocations == expected;
	const bool pass = covered > 0 && mismatches == 0 && changed && invocationsMatch && referenceMatches;
	std::printf("PERVERTEX_DYNAMIC_TOPOLOGY %s %s %s %s\n", pass ? "PASS" : "FAIL", klass.c_str(), form.c_str(), fragmentKind.c_str());
	vkDeviceWaitIdle(device);
	vkDestroyDevice(device, nullptr);
	vkDestroyInstance(instance, nullptr);
	return pass ? 0 : 2;
	}
}
