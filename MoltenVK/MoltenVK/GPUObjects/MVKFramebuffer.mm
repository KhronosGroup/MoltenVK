/*
 * MVKFramebuffer.mm
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKFramebuffer.h"
#include "MVKRenderPass.h"

using namespace std;


#pragma mark MVKFramebuffer

id<MTLTexture> MVKFramebuffer::getDummyAttachmentMTLTexture(MVKRenderSubpass* subpass, uint32_t passIdx) {
	if (_mtlDummyTex) { return _mtlDummyTex; }

	// Lock and check again in case another thread has created the texture.
	lock_guard<mutex> lock(_lock);
	if (_mtlDummyTex) { return _mtlDummyTex; }

	VkExtent2D fbExtent = getExtent2D();
	uint32_t fbLayerCount = getLayerCount();
	uint32_t sampleCount = mvkSampleCountFromVkSampleCountFlagBits(subpass->getDefaultSampleCount());
	MTLTextureDescriptor* mtlTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatR8Unorm width: fbExtent.width height: fbExtent.height mipmapped: NO];
	if (subpass->isMultiview()) {
#if MVK_MACOS_OR_IOS
		if (sampleCount > 1 && getMetalFeatures().multisampleLayeredRendering) {
			mtlTexDesc.textureType = MTLTextureType2DMultisampleArray;
			mtlTexDesc.sampleCount = sampleCount;
		} else {
			mtlTexDesc.textureType = MTLTextureType2DArray;
		}
#else
		mtlTexDesc.textureType = MTLTextureType2DArray;
#endif
		mtlTexDesc.arrayLength = subpass->getViewCountInMetalPass(passIdx);
	} else if (fbLayerCount > 1) {
#if MVK_MACOS
		if (sampleCount > 1 && getMetalFeatures().multisampleLayeredRendering) {
			mtlTexDesc.textureType = MTLTextureType2DMultisampleArray;
			mtlTexDesc.sampleCount = sampleCount;
		} else {
			mtlTexDesc.textureType = MTLTextureType2DArray;
		}
#else
		mtlTexDesc.textureType = MTLTextureType2DArray;
#endif
		mtlTexDesc.arrayLength = fbLayerCount;
	} else if (sampleCount > 1) {
		mtlTexDesc.textureType = MTLTextureType2DMultisample;
		mtlTexDesc.sampleCount = sampleCount;
	}
#if !MVK_MACOS || MVK_XCODE_12
	mtlTexDesc.storageMode = MTLStorageModeMemoryless;
#else
	mtlTexDesc.storageMode = MTLStorageModePrivate;
#endif
	mtlTexDesc.usage = MTLTextureUsageRenderTarget;

	_mtlDummyTex = [getMTLDevice() newTextureWithDescriptor: mtlTexDesc];	// retained
	[_mtlDummyTex setPurgeableState: MTLPurgeableStateVolatile];

	return _mtlDummyTex;
}

MVKFramebuffer::MVKFramebuffer(MVKDevice* device,
							   const VkFramebufferCreateInfo* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	_layerCount = pCreateInfo->layers;
    _extent = { .width = pCreateInfo->width, .height = pCreateInfo->height };

	// If this is not an image-less framebuffer, add the attachments
	if ( !mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_FRAMEBUFFER_CREATE_IMAGELESS_BIT) ) {
		_attachments.reserve(pCreateInfo->attachmentCount);
		for (uint32_t i = 0; i < pCreateInfo->attachmentCount; i++) {
			_attachments.push_back((MVKImageView*)pCreateInfo->pAttachments[i]);
		}
	}
}

MVKFramebuffer::MVKFramebuffer(MVKDevice* device,
							   const VkRenderingInfo* pRenderingInfo) : MVKVulkanAPIDeviceObject(device) {
	_layerCount = pRenderingInfo->layerCount;

	_extent = {};
	for (uint32_t caIdx = 0; caIdx < pRenderingInfo->colorAttachmentCount; caIdx++) {
		auto& clrAtt = pRenderingInfo->pColorAttachments[caIdx];
		if (clrAtt.imageView) {
			_extent = mvkVkExtent2DFromVkExtent3D(((MVKImageView*)clrAtt.imageView)->getExtent3D());
		}
	}
	if (pRenderingInfo->pDepthAttachment && pRenderingInfo->pDepthAttachment->imageView) {
		_extent = mvkVkExtent2DFromVkExtent3D(((MVKImageView*)pRenderingInfo->pDepthAttachment->imageView)->getExtent3D());
	}
	if (pRenderingInfo->pStencilAttachment && pRenderingInfo->pStencilAttachment->imageView) {
		_extent = mvkVkExtent2DFromVkExtent3D(((MVKImageView*)pRenderingInfo->pStencilAttachment->imageView)->getExtent3D());
	}
}

MVKFramebuffer::~MVKFramebuffer() {
	[_mtlDummyTex release];
}
