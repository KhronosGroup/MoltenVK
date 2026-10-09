// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// Attachment content across the capture/replay of a direct non-indexed portable PerVertexKHR draw. A 64x64 render pass
// writes content before the PerVertex draw, which must still hold for that draw and after it:
// - memoryless-depth: an imported memoryless D32 attachment, cleared to 0 on the left half; the triangle, at depth 0.5
//   with LESS, must stay hidden there;
// - memoryless-stencil: an imported memoryless D32S8 attachment, stencil set to 1 on the left half; the triangle,
//   with stencil EQUAL 0, must stay hidden there;
// - msaa: an ordinary 4x color attachment resolved to the readback image, red on the left half before the draw; the
//   triangle is scissored to the right half, and the left must stay red;
// - msaa-memoryless: the same with an imported memoryless 4x color attachment;
// - indirect-count-0, indirect-count-1: no other attachment; the same triangle through vkCmdDrawIndirectCount with a
//   1 GiB argument buffer, stride 16 and the largest legal maxDrawCount (2^26), on a device whose Metal buffer limit
//   the test build lowers to 1 GiB. Count 1 draws the triangle, Count 0 nothing.
// Outcome: REFUSED when vkEndCommandBuffer refuses the draw, RENDERED when the image matches, WRONG otherwise.
// Exit 0 for RENDERED, 4 for REFUSED, 1 for WRONG or a device loss, 2 for a setup failure, 3 for a missing capability.
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_metal.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <string>
#include <vector>

namespace {

constexpr uint32_t kSide = 64;

void check(VkResult result, const char* step) {
	if (result != VK_SUCCESS) { std::fprintf(stderr, "%s: %d\n", step, int(result)); std::exit(2); }
}

std::vector<uint32_t> readSpirv(const std::string& path) {
	std::ifstream file(path, std::ios::binary | std::ios::ate);
	if (!file) { std::fprintf(stderr, "Cannot read %s\n", path.c_str()); std::exit(2); }
	std::vector<uint32_t> words(size_t(file.tellg()) / 4);
	file.seekg(0);
	file.read(reinterpret_cast<char*>(words.data()), words.size() * 4);
	return words;
}

uint32_t memoryType(VkPhysicalDevice physical, uint32_t bits, VkMemoryPropertyFlags flags) {
	VkPhysicalDeviceMemoryProperties properties;
	vkGetPhysicalDeviceMemoryProperties(physical, &properties);
	for (uint32_t i = 0; i < properties.memoryTypeCount; ++i) {
		if ((bits & (1u << i)) && (properties.memoryTypes[i].propertyFlags & flags) == flags) { return i; }
	}
	std::fprintf(stderr, "No memory type\n");
	std::exit(3);
}

}  // namespace

int main(int argc, char** argv) {
	if (argc != 3) { std::fprintf(stderr, "usage: %s <shader directory> memoryless-depth|memoryless-stencil|msaa|msaa-memoryless\n", argv[0]); return 64; }
	std::string shaders = argv[1], variant = argv[2];
	bool depth = variant == "memoryless-depth", stencil = variant == "memoryless-stencil";
	bool msaa = variant == "msaa" || variant == "msaa-memoryless", memorylessColor = variant == "msaa-memoryless";
	bool indirectCount = variant == "indirect-count-0" || variant == "indirect-count-1";
	uint32_t drawnCount = variant == "indirect-count-1" ? 1 : 0;
	constexpr VkDeviceSize kArgumentBytes = 1ull << 30;
	if (!depth && !stencil && !msaa && !indirectCount) { std::fprintf(stderr, "unknown variant %s\n", variant.c_str()); return 64; }
	VkSampleCountFlagBits samples = msaa ? VK_SAMPLE_COUNT_4_BIT : VK_SAMPLE_COUNT_1_BIT;

	@autoreleasepool {
		VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
		app.apiVersion = VK_API_VERSION_1_2;
		VkInstanceCreateInfo instanceInfo{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
		instanceInfo.pApplicationInfo = &app;
		VkInstance instance;
		check(vkCreateInstance(&instanceInfo, nullptr, &instance), "vkCreateInstance");
		uint32_t count = 1;
		VkPhysicalDevice physical;
		VkResult enumerated = vkEnumeratePhysicalDevices(instance, &count, &physical);
		if ((enumerated != VK_SUCCESS && enumerated != VK_INCOMPLETE) || !count) { std::fprintf(stderr, "No Vulkan device\n"); return 3; }
		// The test build opens VK_KHR_fragment_shader_barycentric through its adapter, as the PerVertex fixtures do.
		auto enable = reinterpret_cast<void (*)(VkPhysicalDevice)>(dlsym(RTLD_DEFAULT, "mvkEnableTESFixtureDevice"));
		if (!enable) { std::fprintf(stderr, "Needs a MoltenVK test build with its test device adapter\n"); return 3; }
		enable(physical);
		if (indirectCount) {
			auto limit = reinterpret_cast<void (*)(VkPhysicalDevice, uint64_t)>(dlsym(RTLD_DEFAULT, "mvkTestLimitMetalBufferSize"));
			if (!limit) { std::fprintf(stderr, "Needs a MoltenVK test build with mvkTestLimitMetalBufferSize\n"); return 3; }
			limit(physical, kArgumentBytes);
		}
		VkPhysicalDeviceFragmentShaderBarycentricFeaturesKHR barycentric{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_BARYCENTRIC_FEATURES_KHR};
		VkPhysicalDeviceFeatures2 features{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
		features.pNext = &barycentric;
		vkGetPhysicalDeviceFeatures2(physical, &features);
		if (!barycentric.fragmentShaderBarycentric) { std::fprintf(stderr, "No fragment shader barycentric feature\n"); return 3; }
		if (indirectCount && !features.features.multiDrawIndirect) { std::fprintf(stderr, "No multiDrawIndirect\n"); return 3; }
		VkPhysicalDeviceFeatures2 enabled{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
		enabled.pNext = &barycentric;
		enabled.features.multiDrawIndirect = indirectCount;
		float priority = 1;
		VkDeviceQueueCreateInfo queueInfo{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
		queueInfo.queueCount = 1;
		queueInfo.pQueuePriorities = &priority;
		const char* extensions[] = {VK_KHR_FRAGMENT_SHADER_BARYCENTRIC_EXTENSION_NAME, VK_EXT_METAL_OBJECTS_EXTENSION_NAME, "VK_KHR_portability_subset", VK_KHR_DRAW_INDIRECT_COUNT_EXTENSION_NAME};
		VkDeviceCreateInfo deviceInfo{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
		deviceInfo.pNext = &enabled;
		deviceInfo.queueCreateInfoCount = 1;
		deviceInfo.pQueueCreateInfos = &queueInfo;
		deviceInfo.enabledExtensionCount = 4;
		deviceInfo.ppEnabledExtensionNames = extensions;
		VkDevice device;
		check(vkCreateDevice(physical, &deviceInfo, nullptr, &device), "vkCreateDevice");
		VkQueue queue;
		vkGetDeviceQueue(device, 0, 0, &queue);
		VkExportMetalDeviceInfoEXT metalDevice{VK_STRUCTURE_TYPE_EXPORT_METAL_DEVICE_INFO_EXT};
		VkExportMetalObjectsInfoEXT exportInfo{VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT};
		exportInfo.pNext = &metalDevice;
		vkExportMetalObjectsEXT(device, &exportInfo);
		if (!metalDevice.mtlDevice) { std::fprintf(stderr, "No exported MTLDevice\n"); return 3; }

		// Images: the attachment under test, and the single-sample color image that is read back.
		auto makeImage = [&](VkFormat format, VkImageUsageFlags usage, VkSampleCountFlagBits sampleCount, id<MTLTexture> imported, VkImage& image, VkDeviceMemory& memory) {
			VkImportMetalTextureInfoEXT import{VK_STRUCTURE_TYPE_IMPORT_METAL_TEXTURE_INFO_EXT};
			import.plane = VK_IMAGE_ASPECT_PLANE_0_BIT;
			import.mtlTexture = imported;
			VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
			info.pNext = imported ? &import : nullptr;
			info.imageType = VK_IMAGE_TYPE_2D;
			info.format = format;
			info.extent = {kSide, kSide, 1};
			info.mipLevels = info.arrayLayers = 1;
			info.samples = sampleCount;
			info.usage = usage;
			check(vkCreateImage(device, &info, nullptr, &image), "vkCreateImage");
			VkMemoryRequirements requirements;
			vkGetImageMemoryRequirements(device, image, &requirements);
			VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
			allocation.allocationSize = requirements.size;
			allocation.memoryTypeIndex = memoryType(physical, requirements.memoryTypeBits, 0);
			check(vkAllocateMemory(device, &allocation, nullptr, &memory), "vkAllocateMemory image");
			check(vkBindImageMemory(device, image, memory, 0), "vkBindImageMemory");
		};
		auto memorylessTexture = [&](MTLPixelFormat format, NSUInteger sampleCount) {
			MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:kSide height:kSide mipmapped:NO];
			descriptor.textureType = sampleCount > 1 ? MTLTextureType2DMultisample : MTLTextureType2D;
			descriptor.sampleCount = sampleCount;
			descriptor.storageMode = MTLStorageModeMemoryless;
			descriptor.usage = MTLTextureUsageRenderTarget;
			id<MTLTexture> texture = [metalDevice.mtlDevice newTextureWithDescriptor:descriptor];
			if (!texture) { std::fprintf(stderr, "Memoryless textures unavailable\n"); std::exit(3); }
			return texture;
		};
		VkImage colorImage, testImage = VK_NULL_HANDLE;
		VkDeviceMemory colorMemory, testMemory = VK_NULL_HANDLE;
		makeImage(VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT, VK_SAMPLE_COUNT_1_BIT, nil, colorImage, colorMemory);
		VkFormat testFormat = depth ? VK_FORMAT_D32_SFLOAT : stencil ? VK_FORMAT_D32_SFLOAT_S8_UINT : VK_FORMAT_R8G8B8A8_UNORM;
		id<MTLTexture> imported = nil;
		if (depth) { imported = memorylessTexture(MTLPixelFormatDepth32Float, 1); }
		if (stencil) { imported = memorylessTexture(MTLPixelFormatDepth32Float_Stencil8, 1); }
		if (memorylessColor) { imported = memorylessTexture(MTLPixelFormatRGBA8Unorm, 4); }
		VkImageUsageFlags testUsage = (msaa ? VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT : VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) | (imported ? VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT : 0);
		if (!indirectCount) { makeImage(testFormat, testUsage, samples, imported, testImage, testMemory); }
		VkImageAspectFlags testAspect = depth ? VK_IMAGE_ASPECT_DEPTH_BIT : stencil ? VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT : VK_IMAGE_ASPECT_COLOR_BIT;
		auto view = [&](VkImage image, VkFormat format, VkImageAspectFlags aspect) {
			VkImageViewCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
			info.image = image;
			info.viewType = VK_IMAGE_VIEW_TYPE_2D;
			info.format = format;
			info.subresourceRange = {aspect, 0, 1, 0, 1};
			VkImageView result;
			check(vkCreateImageView(device, &info, nullptr, &result), "vkCreateImageView");
			return result;
		};
		VkImageView colorView = view(colorImage, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_ASPECT_COLOR_BIT);
		VkImageView testView = indirectCount ? VK_NULL_HANDLE : view(testImage, testFormat, testAspect);

		// Render pass: color 0 (single sample, or MSAA resolved into it), and the depth/stencil attachment.
		std::vector<VkAttachmentDescription> attachments;
		VkAttachmentDescription color{};
		color.format = VK_FORMAT_R8G8B8A8_UNORM;
		color.samples = VK_SAMPLE_COUNT_1_BIT;
		color.loadOp = msaa ? VK_ATTACHMENT_LOAD_OP_DONT_CARE : VK_ATTACHMENT_LOAD_OP_CLEAR;
		color.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
		color.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
		attachments.push_back(color);
		VkAttachmentDescription test{};
		test.format = testFormat;
		test.samples = samples;
		test.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
		test.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		test.stencilLoadOp = stencil ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		test.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		test.finalLayout = msaa ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		if (!indirectCount) { attachments.push_back(test); }
		VkAttachmentReference colorRef{msaa ? 1u : 0u, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
		VkAttachmentReference resolveRef{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
		VkAttachmentReference depthRef{1, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
		VkSubpassDescription subpass{};
		subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
		subpass.colorAttachmentCount = 1;
		subpass.pColorAttachments = &colorRef;
		subpass.pResolveAttachments = msaa ? &resolveRef : nullptr;
		subpass.pDepthStencilAttachment = msaa || indirectCount ? nullptr : &depthRef;
		VkRenderPassCreateInfo passInfo{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
		passInfo.attachmentCount = uint32_t(attachments.size());
		passInfo.pAttachments = attachments.data();
		passInfo.subpassCount = 1;
		passInfo.pSubpasses = &subpass;
		VkRenderPass renderPass;
		check(vkCreateRenderPass(device, &passInfo, nullptr, &renderPass), "vkCreateRenderPass");
		VkImageView views[] = {colorView, testView};
		VkFramebufferCreateInfo framebufferInfo{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
		framebufferInfo.renderPass = renderPass;
		framebufferInfo.attachmentCount = indirectCount ? 1 : 2;
		framebufferInfo.pAttachments = views;
		framebufferInfo.width = framebufferInfo.height = kSide;
		framebufferInfo.layers = 1;
		VkFramebuffer framebuffer;
		check(vkCreateFramebuffer(device, &framebufferInfo, nullptr, &framebuffer), "vkCreateFramebuffer");

		// A full-screen green triangle at depth 0.5, whose fragment reads its PerVertexKHR color.
		auto module = [&](const char* name) {
			std::vector<uint32_t> code = readSpirv(shaders + "/" + name);
			VkShaderModuleCreateInfo info{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
			info.codeSize = code.size() * 4;
			info.pCode = code.data();
			VkShaderModule result;
			check(vkCreateShaderModule(device, &info, nullptr, &result), "vkCreateShaderModule");
			return result;
		};
		VkShaderModule vertex = module("split.vert.spv"), fragment = module("split.frag.spv");
		VkPipelineShaderStageCreateInfo stages[2] = {{VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO}, {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO}};
		stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
		stages[0].module = vertex;
		stages[0].pName = "main";
		stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
		stages[1].module = fragment;
		stages[1].pName = "main";
		VkPipelineVertexInputStateCreateInfo vertexInput{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
		VkPipelineInputAssemblyStateCreateInfo assembly{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
		assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
		VkViewport viewport{0, 0, float(kSide), float(kSide), 0, 1};
		VkRect2D scissor{{msaa ? int32_t(kSide / 2) : 0, 0}, {msaa ? kSide / 2 : kSide, kSide}};
		VkPipelineViewportStateCreateInfo viewportState{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
		viewportState.viewportCount = viewportState.scissorCount = 1;
		viewportState.pViewports = &viewport;
		viewportState.pScissors = &scissor;
		VkPipelineRasterizationStateCreateInfo raster{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
		raster.lineWidth = 1;
		VkPipelineMultisampleStateCreateInfo multisample{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
		multisample.rasterizationSamples = samples;
		VkPipelineDepthStencilStateCreateInfo depthState{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
		depthState.depthTestEnable = depth;
		depthState.depthWriteEnable = depth;
		depthState.depthCompareOp = VK_COMPARE_OP_LESS;
		depthState.stencilTestEnable = stencil;
		depthState.front.compareOp = VK_COMPARE_OP_EQUAL;
		depthState.front.compareMask = 0xFF;
		depthState.front.reference = 0;
		depthState.front.failOp = depthState.front.passOp = depthState.front.depthFailOp = VK_STENCIL_OP_KEEP;
		depthState.back = depthState.front;
		VkPipelineColorBlendAttachmentState blendAttachment{};
		blendAttachment.colorWriteMask = 0xF;
		VkPipelineColorBlendStateCreateInfo blend{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
		blend.attachmentCount = 1;
		blend.pAttachments = &blendAttachment;
		VkPipelineLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
		VkPipelineLayout layout;
		check(vkCreatePipelineLayout(device, &layoutInfo, nullptr, &layout), "vkCreatePipelineLayout");
		VkGraphicsPipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
		pipelineInfo.stageCount = 2;
		pipelineInfo.pStages = stages;
		pipelineInfo.pVertexInputState = &vertexInput;
		pipelineInfo.pInputAssemblyState = &assembly;
		pipelineInfo.pViewportState = &viewportState;
		pipelineInfo.pRasterizationState = &raster;
		pipelineInfo.pMultisampleState = &multisample;
		pipelineInfo.pDepthStencilState = msaa || indirectCount ? nullptr : &depthState;
		pipelineInfo.pColorBlendState = &blend;
		pipelineInfo.layout = layout;
		pipelineInfo.renderPass = renderPass;
		VkPipeline pipeline;
		check(vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline), "vkCreateGraphicsPipelines");

		// Commands: clear, write the left half before the draw, draw, copy the color image to a host buffer.
		VkBufferCreateInfo bufferInfo{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
		bufferInfo.size = kSide * kSide * 4;
		bufferInfo.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
		VkBuffer readback;
		check(vkCreateBuffer(device, &bufferInfo, nullptr, &readback), "vkCreateBuffer");
		VkMemoryRequirements bufferRequirements;
		vkGetBufferMemoryRequirements(device, readback, &bufferRequirements);
		VkMemoryAllocateInfo bufferAllocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
		bufferAllocation.allocationSize = bufferRequirements.size;
		bufferAllocation.memoryTypeIndex = memoryType(physical, bufferRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
		VkDeviceMemory readbackMemory;
		check(vkAllocateMemory(device, &bufferAllocation, nullptr, &readbackMemory), "vkAllocateMemory readback");
		check(vkBindBufferMemory(device, readback, readbackMemory, 0), "vkBindBufferMemory");
		void* pixels = nullptr;
		check(vkMapMemory(device, readbackMemory, 0, VK_WHOLE_SIZE, 0, &pixels), "vkMapMemory");
		std::memset(pixels, 0, kSide * kSide * 4);
		// The argument buffer holds the triangle as its first command; the count buffer holds Count.
		VkBuffer arguments = VK_NULL_HANDLE, countBuffer = VK_NULL_HANDLE;
		VkDeviceMemory argumentMemory = VK_NULL_HANDLE, countMemory = VK_NULL_HANDLE;
		auto hostBuffer = [&](VkDeviceSize size, VkBuffer& buffer, VkDeviceMemory& memory) {
			VkBufferCreateInfo info{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
			info.size = size;
			info.usage = VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
			check(vkCreateBuffer(device, &info, nullptr, &buffer), "vkCreateBuffer indirect");
			VkMemoryRequirements requirements;
			vkGetBufferMemoryRequirements(device, buffer, &requirements);
			VkMemoryAllocateInfo allocationInfo{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
			allocationInfo.allocationSize = requirements.size;
			allocationInfo.memoryTypeIndex = memoryType(physical, requirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
			check(vkAllocateMemory(device, &allocationInfo, nullptr, &memory), "vkAllocateMemory indirect");
			check(vkBindBufferMemory(device, buffer, memory, 0), "vkBindBufferMemory indirect");
			void* data = nullptr;
			check(vkMapMemory(device, memory, 0, 64, 0, &data), "vkMapMemory indirect");
			return static_cast<uint32_t*>(data);
		};
		if (indirectCount) {
			uint32_t* command = hostBuffer(kArgumentBytes, arguments, argumentMemory);
			command[0] = 3; command[1] = 1; command[2] = 0; command[3] = 0;
			hostBuffer(4, countBuffer, countMemory)[0] = drawnCount;
		}
		VkCommandPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
		VkCommandPool pool;
		check(vkCreateCommandPool(device, &poolInfo, nullptr, &pool), "vkCreateCommandPool");
		VkCommandBufferAllocateInfo allocation{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
		allocation.commandPool = pool;
		allocation.commandBufferCount = 1;
		VkCommandBuffer commands;
		check(vkAllocateCommandBuffers(device, &allocation, &commands), "vkAllocateCommandBuffers");
		VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
		check(vkBeginCommandBuffer(commands, &begin), "vkBeginCommandBuffer");
		VkClearValue clears[2]{};
		clears[0].color.float32[2] = clears[0].color.float32[3] = 1;	// blue
		clears[1] = clears[0];
		if (!msaa && !indirectCount) { clears[1].depthStencil = {1.0f, 0}; }
		VkRenderPassBeginInfo passBegin{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};
		passBegin.renderPass = renderPass;
		passBegin.framebuffer = framebuffer;
		passBegin.renderArea = {{0, 0}, {kSide, kSide}};
		passBegin.clearValueCount = indirectCount ? 1 : 2;
		passBegin.pClearValues = clears;
		vkCmdBeginRenderPass(commands, &passBegin, VK_SUBPASS_CONTENTS_INLINE);
		VkClearAttachment left{};
		VkClearRect leftRect{{{0, 0}, {kSide / 2, kSide}}, 0, 1};
		if (msaa) {
			left.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
			left.clearValue.color.float32[0] = left.clearValue.color.float32[3] = 1;	// red
		} else {
			left.aspectMask = depth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_STENCIL_BIT;
			left.clearValue.depthStencil = {0.0f, 1};
		}
		if (!indirectCount) { vkCmdClearAttachments(commands, 1, &left, 1, &leftRect); }
		vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
		if (indirectCount) {
			vkCmdDrawIndirectCountKHR(commands, arguments, 0, countBuffer, 0, uint32_t(kArgumentBytes / 16), 16);
		} else {
			vkCmdDraw(commands, 3, 1, 0, 0);
		}
		vkCmdEndRenderPass(commands);
		VkBufferImageCopy copy{};
		copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
		copy.imageExtent = {kSide, kSide, 1};
		vkCmdCopyImageToBuffer(commands, colorImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback, 1, &copy);
		VkResult ended = vkEndCommandBuffer(commands);
		std::printf("variant=%s vkEndCommandBuffer=%d\n", variant.c_str(), int(ended));
		int rc;
		if (ended != VK_SUCCESS) {
			std::printf("SPLIT_ATTACHMENT REFUSED: the draw was refused before submission (%d)\n", int(ended));
			rc = 4;
		} else {
			check(ended, "vkEndCommandBuffer");
			VkFenceCreateInfo fenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
			VkFence fence;
			check(vkCreateFence(device, &fenceInfo, nullptr, &fence), "vkCreateFence");
			VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
			submit.commandBufferCount = 1;
			submit.pCommandBuffers = &commands;
			VkResult submitted = vkQueueSubmit(queue, 1, &submit, fence);
			VkResult waited = submitted == VK_SUCCESS ? vkWaitForFences(device, 1, &fence, VK_TRUE, 5000000000ull) : submitted;
			// Left half keeps what was written before the draw (blue for a hidden triangle, red for MSAA); right is green.
			uint32_t wrong = 0;
			const uint8_t* p = static_cast<const uint8_t*>(pixels);
			for (uint32_t y = 0; y < kSide; ++y) {
				for (uint32_t x = 0; x < kSide; ++x, p += 4) {
					bool leftHalf = x < kSide / 2;
					uint8_t want[4] = {uint8_t(leftHalf && msaa ? 255 : 0), uint8_t(leftHalf ? 0 : 255), uint8_t(leftHalf && !msaa ? 255 : 0), 255};
					if (indirectCount) { want[0] = 0; want[1] = drawnCount ? 255 : 0; want[2] = drawnCount ? 0 : 255; }
					wrong += std::memcmp(p, want, 4) != 0;
				}
			}
			const uint8_t* corner = static_cast<const uint8_t*>(pixels);
			std::printf("submit=%d wait=%d wrong_pixels=%u left_pixel=%02x%02x%02x%02x\n", int(submitted), int(waited), wrong, corner[0], corner[1], corner[2], corner[3]);
			bool rendered = waited == VK_SUCCESS && wrong == 0;
			std::printf("SPLIT_ATTACHMENT %s\n", rendered ? "RENDERED: content before the draw was preserved" : "WRONG: content was lost or the draw failed");
			rc = rendered ? 0 : 1;
			vkDestroyFence(device, fence, nullptr);
		}
		std::fflush(stdout);
		vkDeviceWaitIdle(device);
		vkDestroyDevice(device, nullptr);
		vkDestroyInstance(instance, nullptr);
		return rc;
	}
}
