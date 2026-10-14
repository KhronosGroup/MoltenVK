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

/** Whether this system has a hardware H.265 encoder. */
bool mvkVideoEncodeH265Available();

/** Whether the H.265 encoder takes 4:4:4 pictures. */
bool mvkVideoEncodeH265Chroma444Available();

/** Whether this system has an H.265 decoder. */
bool mvkVideoDecodeH265Available();

/** Whether any codec encodes. */
bool mvkVideoEncodeAvailable();

/** Whether any codec decodes. */
bool mvkVideoDecodeAvailable();

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

/** A VkVideoSessionKHR, coding H.264 or H.265 through VideoToolbox. */
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

	/** Whether this session codes H.265. */
	bool isHevc() const { return _hevc; }

	/** Whether its pictures are 4:4:4 (else 4:2:0). */
	bool isChroma444() const { return _chroma444; }

	/** Readies an encoder for this SPS, returning its SPS and PPS. */
	VkResult prepare(const StdVideoH264SequenceParameterSet* pSPS,
					 const StdVideoH264PictureParameterSet* pPPS,
					 std::vector<uint8_t>* pSPSOut,
					 std::vector<uint8_t>* pPPSOut);

	/** Readies an H.265 encoder; returns its VPS, SPS and PPS. */
	VkResult prepareH265(const StdVideoH265VideoParameterSet* pVPS,
						 const StdVideoH265SequenceParameterSet* pSPS,
						 const StdVideoH265PictureParameterSet* pPPS,
						 std::vector<uint8_t>* pVPSOut,
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

	/** Decodes one H.265 picture of Annex B slice segments. */
	VkResult decodeFrameH265(const StdVideoH265VideoParameterSet* pVPS,
							 const StdVideoH265SequenceParameterSet* pSPS,
							 const StdVideoH265PictureParameterSet* pPPS,
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
	VkResult prepareEncoder(VkExtent2D extent, bool fullRange, bool cabac, double frameRate);
	void destroyEncoder();
	void applyRateControl(int32_t constantQp);
	VkResult primeParameterSets();
	VkResult prepareDecoder(const std::vector<std::vector<uint8_t>>& sets, bool fullRange);
	VkResult decodeSample(const std::vector<std::vector<uint8_t>>& sets, bool fullRange,
						  const uint8_t* data, size_t size,
						  const uint32_t* pSliceOffsets, uint32_t sliceCount,
						  CVPixelBufferRef* pPixelBuffer);
	OSType pixelFormatFor(bool fullRange) const;
	void destroyDecoder();

	std::mutex _lock;
	VTCompressionSessionRef _vtSession = nullptr;
	CVPixelBufferPoolRef _pixelBufferPool = nullptr;
	CVMetalTextureCacheRef _textureCache = nullptr;
	std::vector<uint8_t> _vps;
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
	bool _hevc = false;
	bool _chroma444 = false;
	VTDecompressionSessionRef _vtDecoder = nullptr;
	CMVideoFormatDescriptionRef _decodeFormat = nullptr;
	std::vector<std::vector<uint8_t>> _decodeSets;
};


#pragma mark -
#pragma mark MVKVideoSessionParameters

/** A VkVideoSessionParametersKHR: H.264 SPS/PPS or H.265 VPS/SPS/PPS. */
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

	/** The H.265 VPS with this id, or null. */
	const StdVideoH265VideoParameterSet* getH265VPS(uint8_t vpsId) const;

	/** The H.265 SPS with these ids, or null. */
	const StdVideoH265SequenceParameterSet* getH265SPS(uint8_t vpsId, uint8_t spsId) const;

	/** The H.265 PPS with these ids, or null. */
	const StdVideoH265PictureParameterSet* getH265PPS(uint8_t vpsId, uint8_t spsId, uint8_t ppsId) const;

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
	VkResult addH265(uint32_t vpsCount, const StdVideoH265VideoParameterSet* pVPSs,
					 uint32_t spsCount, const StdVideoH265SequenceParameterSet* pSPSs,
					 uint32_t ppsCount, const StdVideoH265PictureParameterSet* pPPSs);
	VkResult getEncodedH265(const VkVideoEncodeSessionParametersGetInfoKHR* pInfo,
							VkVideoEncodeSessionParametersFeedbackInfoKHR* pFeedbackInfo,
							size_t* pDataSize, void* pData);

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

	// H.265 entries keep their own copy of every pointed-to part
	struct H265VPSEntry {
		StdVideoH265VideoParameterSet vps;
		StdVideoH265ProfileTierLevel ptl;
		StdVideoH265DecPicBufMgr dpbm;
		bool hasPtl;
		bool hasDpbm;
	};

	struct H265SPSEntry {
		StdVideoH265SequenceParameterSet sps;
		StdVideoH265ProfileTierLevel ptl;
		StdVideoH265DecPicBufMgr dpbm;
		StdVideoH265ScalingLists scalingLists;
		StdVideoH265ShortTermRefPicSet stRps[STD_VIDEO_H265_MAX_SHORT_TERM_REF_PIC_SETS];
		StdVideoH265LongTermRefPicsSps ltRps;
		StdVideoH265SequenceParameterSetVui vui;
		bool hasPtl;
		bool hasDpbm;
		bool hasScalingLists;
		bool hasStRps;
		bool hasLtRps;
		bool hasVui;
	};

	struct H265PPSEntry {
		StdVideoH265PictureParameterSet pps;
		StdVideoH265ScalingLists scalingLists;
		bool hasScalingLists;
	};

	MVKVideoSession* _session;
	MVKSmallVector<SPSEntry, 1> _spsList;
	MVKSmallVector<PPSEntry, 1> _ppsList;
	MVKSmallVector<H265VPSEntry, 1> _h265VpsList;
	MVKSmallVector<H265SPSEntry, 1> _h265SpsList;
	MVKSmallVector<H265PPSEntry, 1> _h265PpsList;
	uint32_t _maxVPSCount = 0;
	uint32_t _maxSPSCount;
	uint32_t _maxPPSCount;
	uint32_t _updateSequenceCount = 0;
};
