/*
 * MVKVideo.h
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

#include "MVKDevice.h"
#include "MVKSmallVector.h"
#include <mutex>
#include <vector>

#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

class MVKImageView;
class MVKBuffer;
class MVKQueryPool;
class MVKCommandEncoder;


#pragma mark -
#pragma mark Video support queries

/** Whether this system has a hardware H.264 encoder. */
bool mvkVideoEncodeH264Available();

/** Whether this system has an H.264 decoder. */
bool mvkVideoDecodeH264Available();

/** Whether any video codec operation is available. */
bool mvkVideoAvailable();

/** vkGetPhysicalDeviceVideoCapabilitiesKHR. */
VkResult mvkGetPhysicalDeviceVideoCapabilities(MVKPhysicalDevice* physicalDevice,
											   const VkVideoProfileInfoKHR* pVideoProfile,
											   VkVideoCapabilitiesKHR* pCapabilities);

/** vkGetPhysicalDeviceVideoFormatPropertiesKHR. */
VkResult mvkGetPhysicalDeviceVideoFormatProperties(MVKPhysicalDevice* physicalDevice,
												   const VkPhysicalDeviceVideoFormatInfoKHR* pVideoFormatInfo,
												   uint32_t* pVideoFormatPropertyCount,
												   VkVideoFormatPropertiesKHR* pVideoFormatProperties);

/** vkGetPhysicalDeviceVideoEncodeQualityLevelPropertiesKHR. */
VkResult mvkGetPhysicalDeviceVideoEncodeQualityLevelProperties(MVKPhysicalDevice* physicalDevice,
															   const VkPhysicalDeviceVideoEncodeQualityLevelInfoKHR* pQualityLevelInfo,
															   VkVideoEncodeQualityLevelPropertiesKHR* pQualityLevelProperties);

/** Whether a video profile is one MoltenVK encodes or decodes. */
bool mvkIsSupportedVideoProfile(const VkVideoProfileInfoKHR* pVideoProfile);


#pragma mark -
#pragma mark MVKVideoSession

/** A VkVideoSessionKHR, coding H.264 through VideoToolbox. */
class MVKVideoSession : public MVKVulkanAPIDeviceObject {

public:

	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_VIDEO_SESSION_KHR; }

	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_UNKNOWN_EXT; }

	/** VideoToolbox owns its memory: there is nothing to bind. */
	VkResult getMemoryRequirements(uint32_t* pCount, VkVideoSessionMemoryRequirementsKHR* pRequirements);

	/** Accepts the (empty) set of memory bindings. */
	VkResult bindMemory(uint32_t bindCount, const VkBindVideoSessionMemoryInfoKHR* pBindInfos);

	/** The H.264 profile this session codes. */
	StdVideoH264ProfileIdc getProfileIdc() const { return _profileIdc; }

	/** Whether this session decodes. */
	bool isDecode() const { return _decode; }

	/** Readies an encoder for this SPS, returning its SPS and PPS. */
	VkResult prepare(const StdVideoH264SequenceParameterSet* pSPS,
					 const StdVideoH264PictureParameterSet* pPPS,
					 std::vector<uint8_t>* pSPSOut,
					 std::vector<uint8_t>* pPPSOut);

	/** A pixel buffer of the encoder's size, and its planes. */
	CVPixelBufferRef newPixelBuffer(id<MTLTexture>* pLuma, id<MTLTexture>* pChroma,
									CVMetalTextureRef* pLumaRef, CVMetalTextureRef* pChromaRef);

	/** The encoder's frame size, in pixels. */
	VkExtent2D getFrameExtent() const { return _frameExtent; }

	/** VK_VIDEO_CODING_CONTROL_RESET_BIT_KHR: start clean. */
	void reset();

	/** Rate control from vkCmdControlVideoCodingKHR. */
	void setRateControl(const VkVideoEncodeRateControlInfoKHR& rateControl);

	/** Decodes one picture of Annex B slices; returns its buffer. */
	VkResult decodeFrame(const StdVideoH264SequenceParameterSet* pSPS,
						 const StdVideoH264PictureParameterSet* pPPS,
						 const uint8_t* data, size_t size,
						 const uint32_t* pSliceOffsets, uint32_t sliceCount,
						 CVPixelBufferRef* pPixelBuffer);

	/** Metal textures over a pixel buffer's two planes. */
	bool newTextures(CVPixelBufferRef pixelBuffer, id<MTLTexture>* pLuma, id<MTLTexture>* pChroma,
					 CVMetalTextureRef* pLumaRef, CVMetalTextureRef* pChromaRef);

	/** Encodes one frame as Annex B into dst; status per query. */
	void encodeFrame(CVPixelBufferRef pixelBuffer, bool idr, int32_t constantQp,
					 uint8_t* dst, size_t dstSize,
					 uint64_t* pBytesWritten, int32_t* pStatus);

	MVKVideoSession(MVKDevice* device, const VkVideoSessionCreateInfoKHR* pCreateInfo);

	~MVKVideoSession() override;

protected:
	void propagateDebugName() override {}
	VkResult createEncoder(uint32_t width, uint32_t height, bool fullRange, bool cabac, double frameRate);
	void destroyEncoder();
	void applyRateControl(int32_t constantQp);
	VkResult primeParameterSets();
	VkResult prepareDecoder(const std::vector<uint8_t>& sps, const std::vector<uint8_t>& pps, bool fullRange);
	void destroyDecoder();

	std::mutex _lock;
	VTCompressionSessionRef _vtSession = nullptr;
	CVPixelBufferPoolRef _pixelBufferPool = nullptr;
	CVMetalTextureCacheRef _textureCache = nullptr;
	std::vector<uint8_t> _sps;
	std::vector<uint8_t> _pps;
	VkExtent2D _frameExtent = { 0, 0 };
	VkExtent2D _maxCodedExtent;
	StdVideoH264ProfileIdc _profileIdc;
	OSType _pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
	bool _cabac = true;
	double _frameRate = 60.0;
	int64_t _frameIndex = 0;
	bool _forceIdr = true;
	VkVideoEncodeRateControlModeFlagBitsKHR _rcMode = VK_VIDEO_ENCODE_RATE_CONTROL_MODE_DEFAULT_KHR;
	uint64_t _averageBitrate = 0;
	uint64_t _maxBitrate = 0;
	int32_t _appliedQp = -1;
	bool _rcDirty = false;
	bool _decode = false;
	VTDecompressionSessionRef _vtDecoder = nullptr;
	CMVideoFormatDescriptionRef _decodeFormat = nullptr;
	std::vector<uint8_t> _decodeSPS;
	std::vector<uint8_t> _decodePPS;
};


#pragma mark -
#pragma mark MVKVideoSessionParameters

/** A VkVideoSessionParametersKHR holding H.264 SPS and PPS entries. */
class MVKVideoSessionParameters : public MVKVulkanAPIDeviceObject {

public:

	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_VIDEO_SESSION_PARAMETERS_KHR; }

	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_UNKNOWN_EXT; }

	/** The session these parameters belong to. */
	MVKVideoSession* getSession() const { return _session; }

	/** vkUpdateVideoSessionParametersKHR. */
	VkResult update(const VkVideoSessionParametersUpdateInfoKHR* pUpdateInfo);

	/** The SPS with this id, or null. */
	const StdVideoH264SequenceParameterSet* getSPS(uint8_t spsId) const;

	/** The PPS with these ids, or null. */
	const StdVideoH264PictureParameterSet* getPPS(uint8_t spsId, uint8_t ppsId) const;

	/** vkGetEncodedVideoSessionParametersKHR. */
	VkResult getEncoded(const VkVideoEncodeSessionParametersGetInfoKHR* pInfo,
						VkVideoEncodeSessionParametersFeedbackInfoKHR* pFeedbackInfo,
						size_t* pDataSize, void* pData);

	MVKVideoSessionParameters(MVKDevice* device, const VkVideoSessionParametersCreateInfoKHR* pCreateInfo);

	~MVKVideoSessionParameters() override;

protected:
	void propagateDebugName() override {}
	VkResult add(uint32_t spsCount, const StdVideoH264SequenceParameterSet* pSPSs,
				 uint32_t ppsCount, const StdVideoH264PictureParameterSet* pPPSs);

	struct SPSEntry {
		StdVideoH264SequenceParameterSet sps;
		StdVideoH264SequenceParameterSetVui vui;
		StdVideoH264HrdParameters hrd;
		StdVideoH264ScalingLists scalingLists;
		int32_t offsetForRefFrame[255];
		bool hasVui;
		bool hasHrd;
		bool hasScalingLists;
	};

	struct PPSEntry {
		StdVideoH264PictureParameterSet pps;
		StdVideoH264ScalingLists scalingLists;
		bool hasScalingLists;
	};

	MVKVideoSession* _session;
	MVKSmallVector<SPSEntry, 1> _spsList;
	MVKSmallVector<PPSEntry, 1> _ppsList;
	uint32_t _maxSPSCount;
	uint32_t _maxPPSCount;
	uint32_t _updateSequenceCount = 0;
};
