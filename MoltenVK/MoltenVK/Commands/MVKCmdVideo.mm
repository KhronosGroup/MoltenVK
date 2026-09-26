/*
 * MVKCmdVideo.mm
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCmdVideo.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKVideo.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKQueryPool.h"
#include "MVKFoundation.h"


#pragma mark -
#pragma mark MVKCmdBeginVideoCoding

VkResult MVKCmdBeginVideoCoding::setContent(MVKCommandBuffer* cmdBuff, const VkVideoBeginCodingInfoKHR* pBeginInfo) {
	_session = (MVKVideoSession*)pBeginInfo->videoSession;
	_parameters = (MVKVideoSessionParameters*)pBeginInfo->videoSessionParameters;
	return VK_SUCCESS;
}

void MVKCmdBeginVideoCoding::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_videoSession = _session;
	cmdEncoder->_videoSessionParameters = _parameters;
}


#pragma mark -
#pragma mark MVKCmdEndVideoCoding

VkResult MVKCmdEndVideoCoding::setContent(MVKCommandBuffer* cmdBuff, const VkVideoEndCodingInfoKHR* pEndInfo) {
	return VK_SUCCESS;
}

void MVKCmdEndVideoCoding::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->_videoSession = nullptr;
	cmdEncoder->_videoSessionParameters = nullptr;
}


#pragma mark -
#pragma mark MVKCmdControlVideoCoding

VkResult MVKCmdControlVideoCoding::setContent(MVKCommandBuffer* cmdBuff, const VkVideoCodingControlInfoKHR* pControlInfo) {
	_flags = pControlInfo->flags;
	_hasRateControl = false;
	for (const auto* next = (VkBaseInStructure*)pControlInfo->pNext; next; next = next->pNext) {
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_RATE_CONTROL_INFO_KHR) {
			_rateControl = *(const VkVideoEncodeRateControlInfoKHR*)next;
			_rateControl.pNext = nullptr;
			if (_rateControl.layerCount > 0 && _rateControl.pLayers) {
				_rateControlLayer = _rateControl.pLayers[0];
				_rateControlLayer.pNext = nullptr;
				_rateControl.layerCount = 1;
			} else {
				_rateControl.layerCount = 0;
			}
			_rateControl.pLayers = nullptr;
			_hasRateControl = true;
		}
	}
	return VK_SUCCESS;
}

// session state changes land in queue order, at execution
void MVKCmdControlVideoCoding::encode(MVKCommandEncoder* cmdEncoder) {
	MVKVideoSession* session = cmdEncoder->_videoSession;
	if ( !session ) { return; }

	VkVideoCodingControlFlagsKHR flags = _flags;
	bool applyRateControl = _hasRateControl && mvkIsAnyFlagEnabled(flags, VK_VIDEO_CODING_CONTROL_ENCODE_RATE_CONTROL_BIT_KHR);
	VkVideoEncodeRateControlInfoKHR rateControl = _rateControl;
	VkVideoEncodeRateControlLayerInfoKHR layer = _rateControlLayer;

	session->retain();
	[cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mtlCB) {
		if (mvkIsAnyFlagEnabled(flags, VK_VIDEO_CODING_CONTROL_RESET_BIT_KHR)) { session->reset(); }
		if (applyRateControl) {
			VkVideoEncodeRateControlInfoKHR rc = rateControl;
			rc.pLayers = rc.layerCount ? &layer : nullptr;
			session->setRateControl(rc);
		}
		session->release();
	}];
}


#pragma mark -
#pragma mark MVKCmdEncodeVideo

VkResult MVKCmdEncodeVideo::setContent(MVKCommandBuffer* cmdBuff, const VkVideoEncodeInfoKHR* pEncodeInfo) {
	_dstBuffer = (MVKBuffer*)pEncodeInfo->dstBuffer;
	_dstBufferOffset = pEncodeInfo->dstBufferOffset;
	_dstBufferRange = pEncodeInfo->dstBufferRange;
	_srcView = (MVKImageView*)pEncodeInfo->srcPictureResource.imageViewBinding;
	_codedOffset = pEncodeInfo->srcPictureResource.codedOffset;
	_codedExtent = pEncodeInfo->srcPictureResource.codedExtent;
	_baseArrayLayer = pEncodeInfo->srcPictureResource.baseArrayLayer;
	_spsId = 0;
	_ppsId = 0;
	_idr = false;
	_constantQp = 26;

	for (const auto* next = (VkBaseInStructure*)pEncodeInfo->pNext; next; next = next->pNext) {
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H264_PICTURE_INFO_KHR) {
			auto* pH264 = (const VkVideoEncodeH264PictureInfoKHR*)next;
			if (pH264->pStdPictureInfo) {
				_spsId = pH264->pStdPictureInfo->seq_parameter_set_id;
				_ppsId = pH264->pStdPictureInfo->pic_parameter_set_id;
				_idr = pH264->pStdPictureInfo->flags.IdrPicFlag;
			}
			if (pH264->naluSliceEntryCount > 0 && pH264->pNaluSliceEntries) {
				_constantQp = pH264->pNaluSliceEntries[0].constantQp;
			}
		}
	}
	return VK_SUCCESS;
}

void MVKCmdEncodeVideo::encode(MVKCommandEncoder* cmdEncoder) {
	MVKVideoSession* session = cmdEncoder->_videoSession;
	MVKVideoSessionParameters* params = cmdEncoder->_videoSessionParameters;
	MVKVideoQueryPool* queryPool = cmdEncoder->_videoQueryPool;
	uint32_t query = cmdEncoder->_videoQuery;
	if ( !session || !params ) {
		reportError(VK_ERROR_VALIDATION_FAILED_EXT, "vkCmdEncodeVideoKHR(): called outside a video coding scope.");
		return;
	}

	VkResult rslt = session->prepare(params->getSPS(_spsId), params->getPPS(_spsId, _ppsId), nullptr, nullptr);
	id<MTLTexture> luma = nil, chroma = nil;
	CVMetalTextureRef lumaRef = nullptr, chromaRef = nullptr;
	CVPixelBufferRef pixelBuffer = (rslt == VK_SUCCESS) ? session->newPixelBuffer(&luma, &chroma, &lumaRef, &chromaRef) : nullptr;

	// the picture goes into VideoToolbox's buffer on the GPU
	if (pixelBuffer) {
		VkExtent2D frame = session->getFrameExtent();
		uint32_t w = std::min(frame.width, _codedExtent.width);
		uint32_t h = std::min(frame.height, _codedExtent.height);
		MVKImage* image = _srcView->getImage();
		uint32_t slice = _srcView->getSubresourceRange().baseArrayLayer + _baseArrayLayer;
		id<MTLTexture> srcLuma = image->getMTLTexture(0);
		id<MTLTexture> srcChroma = image->getMTLTexture(1);
		id<MTLBlitCommandEncoder> blit = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseEncodeVideo);
		[blit copyFromTexture: srcLuma
				  sourceSlice: slice
				  sourceLevel: 0
				 sourceOrigin: MTLOriginMake(_codedOffset.x, _codedOffset.y, 0)
				   sourceSize: MTLSizeMake(w, h, 1)
					toTexture: luma
			 destinationSlice: 0
			 destinationLevel: 0
			destinationOrigin: MTLOriginMake(0, 0, 0)];
		[blit copyFromTexture: srcChroma
				  sourceSlice: slice
				  sourceLevel: 0
				 sourceOrigin: MTLOriginMake(_codedOffset.x / 2, _codedOffset.y / 2, 0)
				   sourceSize: MTLSizeMake((w + 1) / 2, (h + 1) / 2, 1)
					toTexture: chroma
			 destinationSlice: 0
			 destinationLevel: 0
			destinationOrigin: MTLOriginMake(0, 0, 0)];
	}

	// VideoToolbox runs once the picture is complete
	MVKBuffer* dstBuffer = _dstBuffer;
	VkDeviceSize dstOffset = _dstBufferOffset;
	VkDeviceSize dstRange = _dstBufferRange;
	bool idr = _idr;
	int32_t qp = _constantQp;
	session->retain();
	dstBuffer->retain();
	if (queryPool) { queryPool->retain(); }
	[cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mtlCB) {
		uint64_t written = 0;
		int32_t status = VK_QUERY_RESULT_STATUS_ERROR_KHR;
		if (pixelBuffer && mtlCB.status == MTLCommandBufferStatusCompleted) {
			uint8_t* base = (uint8_t*)dstBuffer->getMTLBuffer().contents;
			if (base) {
				session->encodeFrame(pixelBuffer, idr, qp,
									 base + dstBuffer->getMTLBufferOffset() + dstOffset, (size_t)dstRange,
									 &written, &status);
			}
		}
		if (queryPool) {
			queryPool->setFeedback(query, 0, written, status);
			queryPool->release();
		}
		if (pixelBuffer) { CVPixelBufferRelease(pixelBuffer); }
		if (lumaRef) { CFRelease(lumaRef); }
		if (chromaRef) { CFRelease(chromaRef); }
		dstBuffer->release();
		session->release();
	}];
}


#pragma mark -
#pragma mark MVKCmdDecodeVideo

VkResult MVKCmdDecodeVideo::setContent(MVKCommandBuffer* cmdBuff, const VkVideoDecodeInfoKHR* pDecodeInfo) {
	_srcBuffer = (MVKBuffer*)pDecodeInfo->srcBuffer;
	_srcBufferOffset = pDecodeInfo->srcBufferOffset;
	_srcBufferRange = pDecodeInfo->srcBufferRange;
	_dstView = (MVKImageView*)pDecodeInfo->dstPictureResource.imageViewBinding;
	_codedOffset = pDecodeInfo->dstPictureResource.codedOffset;
	_codedExtent = pDecodeInfo->dstPictureResource.codedExtent;
	_baseArrayLayer = pDecodeInfo->dstPictureResource.baseArrayLayer;
	_spsId = 0;
	_ppsId = 0;
	_sliceOffsets.clear();

	for (const auto* next = (VkBaseInStructure*)pDecodeInfo->pNext; next; next = next->pNext) {
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_DECODE_H264_PICTURE_INFO_KHR) {
			auto* pH264 = (const VkVideoDecodeH264PictureInfoKHR*)next;
			if (pH264->pStdPictureInfo) {
				_spsId = pH264->pStdPictureInfo->seq_parameter_set_id;
				_ppsId = pH264->pStdPictureInfo->pic_parameter_set_id;
			}
			for (uint32_t i = 0; i < pH264->sliceCount; i++) { _sliceOffsets.push_back(pH264->pSliceOffsets[i]); }
		}
	}
	return VK_SUCCESS;
}

// VideoToolbox decodes as the command is encoded to Metal
void MVKCmdDecodeVideo::encode(MVKCommandEncoder* cmdEncoder) {
	MVKVideoSession* session = cmdEncoder->_videoSession;
	MVKVideoSessionParameters* params = cmdEncoder->_videoSessionParameters;
	MVKVideoQueryPool* queryPool = cmdEncoder->_videoQueryPool;
	uint32_t query = cmdEncoder->_videoQuery;
	if ( !session || !params ) {
		reportError(VK_ERROR_VALIDATION_FAILED_EXT, "vkCmdDecodeVideoKHR(): called outside a video coding scope.");
		return;
	}

	const StdVideoH264SequenceParameterSet* pSPS = params->getSPS(_spsId);
	CVPixelBufferRef pixelBuffer = nullptr;
	uint8_t* base = (uint8_t*)_srcBuffer->getMTLBuffer().contents;
	if (base) {
		const uint8_t* data = base + _srcBuffer->getMTLBufferOffset() + _srcBufferOffset;
		session->decodeFrame(pSPS, params->getPPS(_spsId, _ppsId), data, (size_t)_srcBufferRange,
							 _sliceOffsets.data(), (uint32_t)_sliceOffsets.size(), &pixelBuffer);
	}

	id<MTLTexture> luma = nil, chroma = nil;
	CVMetalTextureRef lumaRef = nullptr, chromaRef = nullptr;
	bool decoded = pixelBuffer && session->newTextures(pixelBuffer, &luma, &chroma, &lumaRef, &chromaRef);
	if (decoded) {
		// a cropped picture sits at the SPS crop origin
		uint32_t codedW = (pSPS->pic_width_in_mbs_minus1 + 1) * 16;
		uint32_t cropX = 0, cropY = 0;
		if (pSPS->flags.frame_cropping_flag && luma.width < codedW) {
			cropX = 2 * pSPS->frame_crop_left_offset;
			cropY = 2 * (pSPS->flags.frame_mbs_only_flag ? 1 : 2) * pSPS->frame_crop_top_offset;
		}
		MVKImage* image = _dstView->getImage();
		id<MTLTexture> dstLuma = image->getMTLTexture(0);
		id<MTLTexture> dstChroma = image->getMTLTexture(1);
		uint32_t x = _codedOffset.x + cropX;
		uint32_t y = _codedOffset.y + cropY;
		uint32_t w = (uint32_t)std::min<NSUInteger>(luma.width, dstLuma.width > x ? dstLuma.width - x : 0);
		uint32_t h = (uint32_t)std::min<NSUInteger>(luma.height, dstLuma.height > y ? dstLuma.height - y : 0);
		uint32_t slice = _dstView->getSubresourceRange().baseArrayLayer + _baseArrayLayer;
		if (w && h) {
			id<MTLBlitCommandEncoder> blit = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseDecodeVideo);
			[blit copyFromTexture: luma
					  sourceSlice: 0
					  sourceLevel: 0
					 sourceOrigin: MTLOriginMake(0, 0, 0)
					   sourceSize: MTLSizeMake(w, h, 1)
						toTexture: dstLuma
				 destinationSlice: slice
				 destinationLevel: 0
				destinationOrigin: MTLOriginMake(x, y, 0)];
			[blit copyFromTexture: chroma
					  sourceSlice: 0
					  sourceLevel: 0
					 sourceOrigin: MTLOriginMake(0, 0, 0)
					   sourceSize: MTLSizeMake(std::min<NSUInteger>((w + 1) / 2, chroma.width), std::min<NSUInteger>((h + 1) / 2, chroma.height), 1)
						toTexture: dstChroma
				 destinationSlice: slice
				 destinationLevel: 0
				destinationOrigin: MTLOriginMake(x / 2, y / 2, 0)];
		}
	}

	// the status lands when the copy is on the GPU timeline
	if (queryPool) { queryPool->retain(); }
	[cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mtlCB) {
		if (queryPool) {
			bool ok = decoded && mtlCB.status == MTLCommandBufferStatusCompleted;
			queryPool->setFeedback(query, 0, 0, ok ? VK_QUERY_RESULT_STATUS_COMPLETE_KHR : VK_QUERY_RESULT_STATUS_ERROR_KHR);
			queryPool->release();
		}
		if (lumaRef) { CFRelease(lumaRef); }
		if (chromaRef) { CFRelease(chromaRef); }
		if (pixelBuffer) { CVPixelBufferRelease(pixelBuffer); }
	}];
}
