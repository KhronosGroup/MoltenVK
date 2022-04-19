/*
 * MVKFramebuffer.mm
 *
 * Copyright (c) 2015-2022 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
		if (sampleCount > 1 && getDevice()->_pMetalFeatures->multisampleLayeredRendering) {
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
		if (sampleCount > 1 && getDevice()->_pMetalFeatures->multisampleLayeredRendering) {
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
#if MVK_IOS
	if ([getMTLDevice() supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily1_v3]) {
		mtlTexDesc.storageMode = MTLStorageModeMemoryless;
	} else {
		mtlTexDesc.storageMode = MTLStorageModePrivate;
	}
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
    _extent = { .width = pCreateInfo->width, .height = pCreateInfo->height };
	_layerCount = pCreateInfo->layers;

	// If this is not an image-less framebuffer, add the attachments
	if ( !mvkIsAnyFlagEnabled(pCreateInfo->flags, VK_FRAMEBUFFER_CREATE_IMAGELESS_BIT) ) {
		_attachments.reserve(pCreateInfo->attachmentCount);
		for (uint32_t i = 0; i < pCreateInfo->attachmentCount; i++) {
			_attachments.push_back((MVKImageView*)pCreateInfo->pAttachments[i]);
		}
	}
}

MVKFramebuffer::~MVKFramebuffer() {
	[_mtlDummyTex release];
}


#pragma mark -
#pragma mark Support functions

MVKFramebuffer* mvkCreateFramebuffer(MVKDevice* device,
									 const VkRenderingInfo* pRenderingInfo,
									 MVKRenderPass* mvkRenderPass) {
	uint32_t attCnt = 0;
	VkExtent3D fbExtent = {};
	for (uint32_t caIdx = 0; caIdx < pRenderingInfo->colorAttachmentCount; caIdx++) {
		auto& clrAtt = pRenderingInfo->pColorAttachments[caIdx];
		if (clrAtt.imageView) {
			fbExtent = ((MVKImageView*)clrAtt.imageView)->getExtent3D();
			attCnt++;
			if (clrAtt.resolveImageView && clrAtt.resolveMode != VK_RESOLVE_MODE_NONE) {
				attCnt++;
			}
		}
	}
	auto* pDSAtt = pRenderingInfo->pDepthAttachment ? pRenderingInfo->pDepthAttachment : pRenderingInfo->pStencilAttachment;
	if (pDSAtt) {
		if (pDSAtt->imageView) {
			fbExtent = ((MVKImageView*)pDSAtt->imageView)->getExtent3D();
			attCnt++;
		}
		if (pDSAtt->resolveImageView && pDSAtt->resolveMode != VK_RESOLVE_MODE_NONE) {
			attCnt++;
		}
	}

	VkFramebufferCreateInfo fbCreateInfo;
	fbCreateInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
	fbCreateInfo.pNext = nullptr;
	fbCreateInfo.flags = VK_FRAMEBUFFER_CREATE_IMAGELESS_BIT;
	fbCreateInfo.renderPass = (VkRenderPass)mvkRenderPass;
	fbCreateInfo.attachmentCount = attCnt;
	fbCreateInfo.pAttachments = nullptr;
	fbCreateInfo.width = fbExtent.width;
	fbCreateInfo.height = fbExtent.height;
	fbCreateInfo.layers = pRenderingInfo->layerCount;

	return device->createFramebuffer(&fbCreateInfo, nullptr);
}

