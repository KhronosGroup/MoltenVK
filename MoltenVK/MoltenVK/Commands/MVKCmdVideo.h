/*
 * MVKCmdVideo.h
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

#pragma once

#include "MVKCommand.h"
#include "MVKSmallVector.h"

class MVKVideoSession;
class MVKVideoSessionParameters;
class MVKImageView;
class MVKBuffer;


#pragma mark -
#pragma mark MVKCmdBeginVideoCoding

/** vkCmdBeginVideoCodingKHR. */
class MVKCmdBeginVideoCoding : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff, const VkVideoBeginCodingInfoKHR* pBeginInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKVideoSession* _session;
	MVKVideoSessionParameters* _parameters;
};


#pragma mark -
#pragma mark MVKCmdEndVideoCoding

/** vkCmdEndVideoCodingKHR. */
class MVKCmdEndVideoCoding : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff, const VkVideoEndCodingInfoKHR* pEndInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;
};


#pragma mark -
#pragma mark MVKCmdControlVideoCoding

/** vkCmdControlVideoCodingKHR. */
class MVKCmdControlVideoCoding : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff, const VkVideoCodingControlInfoKHR* pControlInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	VkVideoCodingControlFlagsKHR _flags;
	VkVideoEncodeRateControlInfoKHR _rateControl;
	VkVideoEncodeRateControlLayerInfoKHR _rateControlLayer;
	bool _hasRateControl;
};


#pragma mark -
#pragma mark MVKCmdEncodeVideo

/** vkCmdEncodeVideoKHR. */
class MVKCmdEncodeVideo : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff, const VkVideoEncodeInfoKHR* pEncodeInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKBuffer* _dstBuffer;
	VkDeviceSize _dstBufferOffset;
	VkDeviceSize _dstBufferRange;
	MVKImageView* _srcView;
	VkOffset2D _codedOffset;
	VkExtent2D _codedExtent;
	uint32_t _baseArrayLayer;
	uint8_t _spsId;
	uint8_t _ppsId;
	bool _idr;
	int32_t _constantQp;
};


#pragma mark -
#pragma mark MVKCmdDecodeVideo

/** vkCmdDecodeVideoKHR. */
class MVKCmdDecodeVideo : public MVKCommand {

public:
	VkResult setContent(MVKCommandBuffer* cmdBuff, const VkVideoDecodeInfoKHR* pDecodeInfo);

	void encode(MVKCommandEncoder* cmdEncoder) override;

protected:
	MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool* cmdPool) override;

	MVKSmallVector<uint32_t, 4> _sliceOffsets;
	MVKBuffer* _srcBuffer;
	VkDeviceSize _srcBufferOffset;
	VkDeviceSize _srcBufferRange;
	MVKImageView* _dstView;
	VkOffset2D _codedOffset;
	VkExtent2D _codedExtent;
	uint32_t _baseArrayLayer;
	uint8_t _spsId;
	uint8_t _ppsId;
};
