// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include <algorithm>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

struct MVKImage;
struct MVKImageMemoryBinding;
struct MVKDeviceMemory {
	MTLStorageMode storage = MTLStorageModeMemoryless;
	id<MTLTexture> _mtlTexture = nil;
	VkExternalMemoryHandleTypeFlags _externalMemoryHandleType = 0;
	bool dedicated = false;
	std::vector<MVKImageMemoryBinding*> _imageMemoryBindings;
	MTLStorageMode getMTLStorageMode() { return storage; }
	bool isDedicatedAllocation() { return dedicated; }
	id<MTLHeap> getMTLHeap() { return nil; }
};
struct MVKImageMemoryBinding { MVKDeviceMemory* _deviceMemory = nullptr; MVKImage* _image = nullptr; id<MTLBuffer> _mtlTexelBuffer = nil; };
struct MVKImagePlane { id<MTLTexture> _mtlTexture = nil; };
struct Extension { bool enabled = false; };
struct Extensions { Extension vk_KHR_fragment_shader_barycentric, vk_NV_fragment_shader_barycentric; };
template<class T> bool mvkContains(const std::vector<T>& values, T value) { return std::find(values.begin(), values.end(), value) != values.end(); }
static bool mvkIsAnyFlagEnabled(uint32_t value, uint32_t flags) { return value & flags; }
// The test entry point sets this flag; without it, the extensions keep their native path.
struct MVKPhysicalDevice {
	bool portablePerVertex = true;
	bool isPortablePerVertexEnabled() const { return portablePerVertex; }
};
struct MVKImage {
	MVKPhysicalDevice physicalDevice;
	MVKPhysicalDevice* getPhysicalDevice() { return &physicalDevice; }
	MVKImageMemoryBinding binding;
	MVKImagePlane plane;
	std::vector<MVKImageMemoryBinding*> _memoryBindings{&binding};
	std::vector<MVKImagePlane*> _planes{&plane};
	void* _ioSurface = nullptr;
	bool _isAliasable = false;
	VkImageUsageFlags usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
	Extensions extensions;
	MVKImage() { binding._image = this; }
	VkImageUsageFlags getCombinedUsage() { return usage; }
	const Extensions& getEnabledExtensions() { return extensions; }
	bool getIsDepthStencil() { return usage & VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT; }
	MTLStorageMode getMTLStorageMode();
};
#include "ImageStorageMode.inc"

// An external texture's storageMode is inspectable even without a Metal device.
@interface StorageTexture : NSObject
@property(nonatomic) MTLStorageMode storageMode;
@end
@implementation StorageTexture
@end

static void checkPolicy() {
	MVKDeviceMemory memory;
	MVKImage image;
	assert(image.getMTLStorageMode() == MTLStorageModePrivate);
	image.binding._deviceMemory = &memory;
	assert(image.getMTLStorageMode() == MTLStorageModeMemoryless);
	for (bool nv : {false, true}) {
		image.extensions.vk_KHR_fragment_shader_barycentric.enabled = !nv;
		image.extensions.vk_NV_fragment_shader_barycentric.enabled = nv;
		for (auto usage : {VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT}) {
			image.usage = usage | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
			assert(image.getMTLStorageMode() == MTLStorageModePrivate);
		}
		for (auto mode : {MTLStorageModePrivate, MTLStorageModeShared, MTLStorageModeManaged}) {
			memory.storage = mode;
			assert(image.getMTLStorageMode() == mode);
		}
		memory.storage = MTLStorageModeMemoryless;
		// Native path: an enabled extension alone keeps memoryless storage, except for input attachments.
		image.physicalDevice.portablePerVertex = false;
		image.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
		assert(image.getMTLStorageMode() == MTLStorageModeMemoryless);
		image.usage = VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
		assert(image.getMTLStorageMode() == MTLStorageModePrivate);
		image.physicalDevice.portablePerVertex = true;
	}
	image.extensions = {};
	assert(image.getMTLStorageMode() == MTLStorageModePrivate); // Existing input-attachment exception.
	image.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
	assert(image.getMTLStorageMode() == MTLStorageModeMemoryless);
	image.extensions.vk_KHR_fragment_shader_barycentric.enabled = true;
	image._ioSurface = &image;
	assert(image.getMTLStorageMode() == MTLStorageModeShared); // IOSurface cannot use private storage.
	image._ioSurface = nullptr;
	StorageTexture* imported = [StorageTexture new];
	imported.storageMode = MTLStorageModeMemoryless;
	image.plane._mtlTexture = (id<MTLTexture>)imported;
	image.binding._deviceMemory = nullptr; // VkImportMetalTextureInfoEXT / vkSetMTLTextureMVK.
	assert(image.getMTLStorageMode() == MTLStorageModeMemoryless);
	image.binding._deviceMemory = &memory;
	assert(image.getMTLStorageMode() == MTLStorageModeMemoryless);
	MVKImage alias;
	alias.extensions = image.extensions;
	alias._isAliasable = true;
	alias.binding._deviceMemory = &memory;
	memory.dedicated = true;
	memory._imageMemoryBindings = {&image.binding};
	assert(alias.getMTLStorageMode() == MTLStorageModeMemoryless);
	image.plane._mtlTexture = nil;
	assert(alias.getMTLStorageMode() == MTLStorageModePrivate); // Internally backed dedicated alias.
	memory._externalMemoryHandleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_MTLTEXTURE_BIT_EXT;
	memory._mtlTexture = (id<MTLTexture>)imported;
	memory.storage = MTLStorageModePrivate; // Import must win even over a nonlazy Vulkan memory type.
	assert(image.getMTLStorageMode() == MTLStorageModeMemoryless);
	assert(alias.getMTLStorageMode() == MTLStorageModeMemoryless);
	imported.storageMode = MTLStorageModePrivate;
	memory.storage = MTLStorageModeMemoryless;
	assert(image.getMTLStorageMode() == MTLStorageModePrivate);
	assert(alias.getMTLStorageMode() == MTLStorageModePrivate);
	[imported release];
	puts("PASS: production image storage policy; KHR/NV, input attachments, unchanged nonlazy modes, external textures and dedicated aliases");
}

static void checkMetal() {
	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	assert(device && "Metal device required for --metal");
	MVKDeviceMemory memory;
	MVKImage image;
	image.binding._deviceMemory = &memory;
	image.extensions.vk_KHR_fragment_shader_barycentric.enabled = true;
	MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:16 height:16 mipmapped:NO];
	desc.storageMode = image.getMTLStorageMode();
	desc.usage = MTLTextureUsageRenderTarget;
	id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
	assert(texture && texture.storageMode == MTLStorageModePrivate);
	if ([device supportsFamily:MTLGPUFamilyApple1]) {
		desc.storageMode = MTLStorageModeMemoryless;
		id<MTLTexture> imported = [device newTextureWithDescriptor:desc];
		assert(imported);
		image.plane._mtlTexture = imported;
		assert(image.getMTLStorageMode() == MTLStorageModeMemoryless);
		image.plane._mtlTexture = nil;
		[imported release];
	}
	NSError* error = nil;
	id<MTLLibrary> library = [device newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal; kernel void touch(device uint* p [[buffer(0)]]) { *p = 42; }" options:nil error:&error];
	assert(library && !error);
	id<MTLFunction> function = [library newFunctionWithName:@"touch"];
	id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
	assert(pipeline && !error);
	id<MTLBuffer> result = [device newBufferWithLength:4096 options:MTLResourceStorageModeShared];
	id<MTLCommandQueue> queue = [device newCommandQueue];
	id<MTLCommandBuffer> command = [queue commandBuffer];
	MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = texture;
	pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1);
	pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	[[command renderCommandEncoderWithDescriptor:pass] endEncoding];
	id<MTLComputeCommandEncoder> compute = [command computeCommandEncoder];
	[compute setComputePipelineState:pipeline];
	[compute setBuffer:result offset:0 atIndex:0];
	[compute dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
	[compute endEncoding];
	pass.colorAttachments[0].loadAction = MTLLoadActionLoad;
	[[command renderCommandEncoderWithDescriptor:pass] endEncoding];
	id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
	[blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(16, 16, 1) toBuffer:result destinationOffset:256 destinationBytesPerRow:64 destinationBytesPerImage:1024];
	[blit endEncoding];
	[command commit];
	[command waitUntilCompleted];
	assert(command.status == MTLCommandBufferStatusCompleted && !command.error);
	assert(*(uint32_t*)result.contents == 42);
	const auto* pixels = (const uint8_t*)result.contents + 256;
	for (unsigned i = 0; i < 256; ++i) { assert(pixels[i * 4] == 255 && pixels[i * 4 + 1] == 0 && pixels[i * 4 + 2] == 0 && pixels[i * 4 + 3] == 255); }
	[queue release]; [result release]; [pipeline release]; [function release]; [library release]; [texture release]; [device release];
	puts("PASS: Metal render/store -> compute -> render/load preserves all attachment pixels");
}

int main(int argc, char** argv) {
	@autoreleasepool {
		checkPolicy();
		if (argc > 1 && !strcmp(argv[1], "--metal")) { checkMetal(); }
	}
}
