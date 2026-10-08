/*
 * MVKVideo.mm
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

#include "MVKVideo.h"
#include "MVKFoundation.h"
#include <string.h>

using namespace std;


#pragma mark -
#pragma mark Video support queries

// H.264 caps VideoToolbox gives on every Apple encoder
static const VkExtent2D kMVKVideoMinCodedExtent = { 16, 16 };
static const VkExtent2D kMVKVideoMaxCodedExtent = { 4096, 2304 };
static const uint32_t kMVKVideoMaxDpbSlots = 16;
static const int32_t kMVKVideoMinQp = 1;
static const int32_t kMVKVideoMaxQp = 51;
static const uint64_t kMVKVideoMaxBitrate = 200000000;
static const uint32_t kMVKVideoDecodeMaxDpbSlots = 17;
static const uint32_t kMVKVideoDecodeMaxActiveReferences = 16;

// a hardware encoder for this codec opens on this system
static bool mvkVideoEncoderOpens(CMVideoCodecType codec) {
	@autoreleasepool {
		NSMutableDictionary* spec = [NSMutableDictionary dictionary];
#if MVK_MACOS
		spec[(NSString*)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = @YES;
#endif
		VTCompressionSessionRef vt = nullptr;
		OSStatus st = VTCompressionSessionCreate(kCFAllocatorDefault, 64, 64, codec,
												 (CFDictionaryRef)spec, nullptr, kCFAllocatorDefault,
												 nullptr, nullptr, &vt);
		if (vt) {
			VTCompressionSessionInvalidate(vt);
			CFRelease(vt);
		}
		return st == noErr;
	}
}

// VideoToolbox's name for the H.265 4:4:4 profile (no SDK constant)
static CFStringRef const kMVKProfileLevel_HEVC_Main444 = CFSTR("HEVC_Main444_AutoLevel");

bool mvkVideoEncodeH264Available() {
	static bool available = mvkVideoEncoderOpens(kCMVideoCodecType_H264);
	return available;
}

bool mvkVideoDecodeH264Available() {
	static bool available = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264);
	return available;
}

bool mvkVideoEncodeH265Available() {
	static bool available = mvkVideoEncoderOpens(kCMVideoCodecType_HEVC);
	return available;
}

bool mvkVideoEncodeH265Chroma444Available() {
	static bool available = []() {
		if ( !mvkVideoEncodeH265Available() ) { return false; }
		@autoreleasepool {
			VTCompressionSessionRef vt = nullptr;
			VTCompressionSessionCreate(kCFAllocatorDefault, 64, 64, kCMVideoCodecType_HEVC, nullptr, nullptr,
									   kCFAllocatorDefault, nullptr, nullptr, &vt);
			if ( !vt ) { return false; }
			bool found = false;
			CFDictionaryRef props = nullptr;
			if (VTSessionCopySupportedPropertyDictionary(vt, &props) == noErr && props) {
				CFDictionaryRef pl = (CFDictionaryRef)CFDictionaryGetValue(props, kVTCompressionPropertyKey_ProfileLevel);
				CFArrayRef vals = pl ? (CFArrayRef)CFDictionaryGetValue(pl, kVTPropertySupportedValueListKey) : nullptr;
				found = vals && CFArrayContainsValue(vals, CFRangeMake(0, CFArrayGetCount(vals)), kMVKProfileLevel_HEVC_Main444);
				CFRelease(props);
			}
			VTCompressionSessionInvalidate(vt);
			CFRelease(vt);
			return found;
		}
	}();
	return available;
}

bool mvkVideoDecodeH265Available() {
	static bool available = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC);
	return available;
}

bool mvkVideoEncodeAvailable() {
	return mvkVideoEncodeH264Available() || mvkVideoEncodeH265Available();
}

bool mvkVideoDecodeAvailable() {
	return mvkVideoDecodeH264Available() || mvkVideoDecodeH265Available();
}

bool mvkVideoAvailable() {
	return mvkVideoEncodeAvailable() || mvkVideoDecodeAvailable();
}

static bool mvkIsDecodeProfile(const VkVideoProfileInfoKHR* pVideoProfile) {
	return (pVideoProfile->videoCodecOperation == VK_VIDEO_CODEC_OPERATION_DECODE_H264_BIT_KHR ||
			pVideoProfile->videoCodecOperation == VK_VIDEO_CODEC_OPERATION_DECODE_H265_BIT_KHR);
}

static bool mvkIsHevcProfile(const VkVideoProfileInfoKHR* pVideoProfile) {
	return (pVideoProfile->videoCodecOperation == VK_VIDEO_CODEC_OPERATION_ENCODE_H265_BIT_KHR ||
			pVideoProfile->videoCodecOperation == VK_VIDEO_CODEC_OPERATION_DECODE_H265_BIT_KHR);
}

// the codec profile of this type chained under a video profile
static const void* mvkProfileNext(const VkVideoProfileInfoKHR* pVideoProfile, VkStructureType sType) {
	for (const auto* next = (VkBaseInStructure*)pVideoProfile->pNext; next; next = next->pNext) {
		if (next->sType == sType) { return next; }
	}
	return nullptr;
}

static const VkVideoEncodeH264ProfileInfoKHR* mvkH264Profile(const VkVideoProfileInfoKHR* pVideoProfile) {
	return (const VkVideoEncodeH264ProfileInfoKHR*)mvkProfileNext(pVideoProfile, VK_STRUCTURE_TYPE_VIDEO_ENCODE_H264_PROFILE_INFO_KHR);
}

static const VkVideoDecodeH264ProfileInfoKHR* mvkH264DecodeProfile(const VkVideoProfileInfoKHR* pVideoProfile) {
	return (const VkVideoDecodeH264ProfileInfoKHR*)mvkProfileNext(pVideoProfile, VK_STRUCTURE_TYPE_VIDEO_DECODE_H264_PROFILE_INFO_KHR);
}

// the H.265 profile idc, encode or decode; -1 when absent
static int32_t mvkH265ProfileIdc(const VkVideoProfileInfoKHR* pVideoProfile) {
	if (auto* e = (const VkVideoEncodeH265ProfileInfoKHR*)mvkProfileNext(pVideoProfile, VK_STRUCTURE_TYPE_VIDEO_ENCODE_H265_PROFILE_INFO_KHR)) {
		return e->stdProfileIdc;
	}
	if (auto* d = (const VkVideoDecodeH265ProfileInfoKHR*)mvkProfileNext(pVideoProfile, VK_STRUCTURE_TYPE_VIDEO_DECODE_H265_PROFILE_INFO_KHR)) {
		return d->stdProfileIdc;
	}
	return -1;
}

static bool mvkIsSupportedProfileIdc(StdVideoH264ProfileIdc idc) {
	return (idc == STD_VIDEO_H264_PROFILE_IDC_BASELINE ||
			idc == STD_VIDEO_H264_PROFILE_IDC_MAIN ||
			idc == STD_VIDEO_H264_PROFILE_IDC_HIGH);
}

static bool mvkIsChroma444Profile(const VkVideoProfileInfoKHR* pVideoProfile) {
	return pVideoProfile->chromaSubsampling == VK_VIDEO_CHROMA_SUBSAMPLING_444_BIT_KHR;
}

static VkResult mvkCheckH265Profile(const VkVideoProfileInfoKHR* pVideoProfile, bool decode) {
	if ( !(decode ? mvkVideoDecodeH265Available() : mvkVideoEncodeH265Available()) ) {
		return VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR;
	}
	bool c444 = mvkIsChroma444Profile(pVideoProfile);
	if ( (pVideoProfile->chromaSubsampling != VK_VIDEO_CHROMA_SUBSAMPLING_420_BIT_KHR && !c444) ||
		pVideoProfile->lumaBitDepth != VK_VIDEO_COMPONENT_BIT_DEPTH_8_BIT_KHR ||
		pVideoProfile->chromaBitDepth != VK_VIDEO_COMPONENT_BIT_DEPTH_8_BIT_KHR) {
		return VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR;
	}
	if (c444 && !decode && !mvkVideoEncodeH265Chroma444Available()) {
		return VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR;
	}
	int32_t idc = mvkH265ProfileIdc(pVideoProfile);
	// 4:2:0 is Main; 4:4:4 is the range extensions profile
	bool ok = (idc == STD_VIDEO_H265_PROFILE_IDC_FORMAT_RANGE_EXTENSIONS ||
			   (idc == STD_VIDEO_H265_PROFILE_IDC_MAIN && !c444));
	return ok ? VK_SUCCESS : VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR;
}

static VkResult mvkCheckVideoProfile(const VkVideoProfileInfoKHR* pVideoProfile) {
	if ( !pVideoProfile ) { return VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR; }
	bool decode = mvkIsDecodeProfile(pVideoProfile);
	if (mvkIsHevcProfile(pVideoProfile)) { return mvkCheckH265Profile(pVideoProfile, decode); }
	if (pVideoProfile->videoCodecOperation != VK_VIDEO_CODEC_OPERATION_ENCODE_H264_BIT_KHR && !decode) {
		return VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR;
	}
	if ( !(decode ? mvkVideoDecodeH264Available() : mvkVideoEncodeH264Available()) ) {
		return VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR;
	}
	if (pVideoProfile->chromaSubsampling != VK_VIDEO_CHROMA_SUBSAMPLING_420_BIT_KHR ||
		pVideoProfile->lumaBitDepth != VK_VIDEO_COMPONENT_BIT_DEPTH_8_BIT_KHR ||
		pVideoProfile->chromaBitDepth != VK_VIDEO_COMPONENT_BIT_DEPTH_8_BIT_KHR) {
		return VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR;
	}
	if (decode) {
		auto* pH264Decode = mvkH264DecodeProfile(pVideoProfile);
		if ( !pH264Decode || !mvkIsSupportedProfileIdc(pH264Decode->stdProfileIdc) ) {
			return VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR;
		}
		if (pH264Decode->pictureLayout != VK_VIDEO_DECODE_H264_PICTURE_LAYOUT_PROGRESSIVE_KHR) {
			return VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR;
		}
		return VK_SUCCESS;
	}
	auto* pH264 = mvkH264Profile(pVideoProfile);
	if ( !pH264 || !mvkIsSupportedProfileIdc(pH264->stdProfileIdc) ) {
		return VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR;
	}
	return VK_SUCCESS;
}

bool mvkIsSupportedVideoProfile(const VkVideoProfileInfoKHR* pVideoProfile) {
	return mvkCheckVideoProfile(pVideoProfile) == VK_SUCCESS;
}

VkResult mvkGetPhysicalDeviceVideoCapabilities(MVKPhysicalDevice* physicalDevice,
											   const VkVideoProfileInfoKHR* pVideoProfile,
											   VkVideoCapabilitiesKHR* pCapabilities) {
	VkResult rslt = mvkCheckVideoProfile(pVideoProfile);
	if (rslt != VK_SUCCESS) { return rslt; }
	bool hevc = mvkIsHevcProfile(pVideoProfile);

	// VideoToolbox keeps every reference: the images only stand in
	if (mvkIsDecodeProfile(pVideoProfile)) {
		pCapabilities->flags = VK_VIDEO_CAPABILITY_SEPARATE_REFERENCE_IMAGES_BIT_KHR;
		pCapabilities->minBitstreamBufferOffsetAlignment = 1;
		pCapabilities->minBitstreamBufferSizeAlignment = 1;
		pCapabilities->pictureAccessGranularity = { 16, 16 };
		pCapabilities->minCodedExtent = kMVKVideoMinCodedExtent;
		pCapabilities->maxCodedExtent = kMVKVideoMaxCodedExtent;
		pCapabilities->maxDpbSlots = kMVKVideoDecodeMaxDpbSlots;
		pCapabilities->maxActiveReferencePictures = kMVKVideoDecodeMaxActiveReferences;
		strncpy(pCapabilities->stdHeaderVersion.extensionName,
				hevc ? VK_STD_VULKAN_VIDEO_CODEC_H265_DECODE_EXTENSION_NAME : VK_STD_VULKAN_VIDEO_CODEC_H264_DECODE_EXTENSION_NAME,
				VK_MAX_EXTENSION_NAME_SIZE);
		pCapabilities->stdHeaderVersion.specVersion = (hevc ? VK_STD_VULKAN_VIDEO_CODEC_H265_DECODE_SPEC_VERSION
															: VK_STD_VULKAN_VIDEO_CODEC_H264_DECODE_SPEC_VERSION);
		for (auto* next = (VkBaseOutStructure*)pCapabilities->pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_VIDEO_DECODE_CAPABILITIES_KHR: {
					auto* pDecCaps = (VkVideoDecodeCapabilitiesKHR*)next;
					pDecCaps->flags = (VK_VIDEO_DECODE_CAPABILITY_DPB_AND_OUTPUT_COINCIDE_BIT_KHR |
									   VK_VIDEO_DECODE_CAPABILITY_DPB_AND_OUTPUT_DISTINCT_BIT_KHR);
					break;
				}
				case VK_STRUCTURE_TYPE_VIDEO_DECODE_H264_CAPABILITIES_KHR: {
					auto* pH264Caps = (VkVideoDecodeH264CapabilitiesKHR*)next;
					pH264Caps->maxLevelIdc = STD_VIDEO_H264_LEVEL_IDC_5_2;
					pH264Caps->fieldOffsetGranularity = { 0, 0 };
					break;
				}
				case VK_STRUCTURE_TYPE_VIDEO_DECODE_H265_CAPABILITIES_KHR: {
					auto* pH265Caps = (VkVideoDecodeH265CapabilitiesKHR*)next;
					pH265Caps->maxLevelIdc = STD_VIDEO_H265_LEVEL_IDC_6_2;
					break;
				}
				default:
					break;
			}
		}
		return VK_SUCCESS;
	}

	pCapabilities->flags = VK_VIDEO_CAPABILITY_SEPARATE_REFERENCE_IMAGES_BIT_KHR;
	pCapabilities->minBitstreamBufferOffsetAlignment = 1;
	pCapabilities->minBitstreamBufferSizeAlignment = 1;
	pCapabilities->pictureAccessGranularity = { 16, 16 };
	pCapabilities->minCodedExtent = kMVKVideoMinCodedExtent;
	pCapabilities->maxCodedExtent = kMVKVideoMaxCodedExtent;
	pCapabilities->maxDpbSlots = kMVKVideoMaxDpbSlots;
	pCapabilities->maxActiveReferencePictures = 1;
	strncpy(pCapabilities->stdHeaderVersion.extensionName,
			hevc ? VK_STD_VULKAN_VIDEO_CODEC_H265_ENCODE_EXTENSION_NAME : VK_STD_VULKAN_VIDEO_CODEC_H264_ENCODE_EXTENSION_NAME,
			VK_MAX_EXTENSION_NAME_SIZE);
	pCapabilities->stdHeaderVersion.specVersion = (hevc ? VK_STD_VULKAN_VIDEO_CODEC_H265_ENCODE_SPEC_VERSION
														: VK_STD_VULKAN_VIDEO_CODEC_H264_ENCODE_SPEC_VERSION);

	for (auto* next = (VkBaseOutStructure*)pCapabilities->pNext; next; next = next->pNext) {
		switch (next->sType) {
			case VK_STRUCTURE_TYPE_VIDEO_ENCODE_CAPABILITIES_KHR: {
				auto* pEncCaps = (VkVideoEncodeCapabilitiesKHR*)next;
				pEncCaps->flags = VK_VIDEO_ENCODE_CAPABILITY_INSUFFICIENT_BITSTREAM_BUFFER_RANGE_DETECTION_BIT_KHR;
				pEncCaps->rateControlModes = (VK_VIDEO_ENCODE_RATE_CONTROL_MODE_DISABLED_BIT_KHR |
											  VK_VIDEO_ENCODE_RATE_CONTROL_MODE_CBR_BIT_KHR |
											  VK_VIDEO_ENCODE_RATE_CONTROL_MODE_VBR_BIT_KHR);
				pEncCaps->maxRateControlLayers = 1;
				pEncCaps->maxBitrate = kMVKVideoMaxBitrate;
				pEncCaps->maxQualityLevels = 1;
				pEncCaps->encodeInputPictureGranularity = { 1, 1 };
				pEncCaps->supportedEncodeFeedbackFlags = (VK_VIDEO_ENCODE_FEEDBACK_BITSTREAM_BUFFER_OFFSET_BIT_KHR |
														  VK_VIDEO_ENCODE_FEEDBACK_BITSTREAM_BYTES_WRITTEN_BIT_KHR |
														  VK_VIDEO_ENCODE_FEEDBACK_BITSTREAM_HAS_OVERRIDES_BIT_KHR);
				break;
			}
			case VK_STRUCTURE_TYPE_VIDEO_ENCODE_H264_CAPABILITIES_KHR: {
				auto* pH264Caps = (VkVideoEncodeH264CapabilitiesKHR*)next;
				pH264Caps->flags = 0;
				pH264Caps->maxLevelIdc = STD_VIDEO_H264_LEVEL_IDC_5_2;
				pH264Caps->maxSliceCount = 1;
				pH264Caps->maxPPictureL0ReferenceCount = 1;
				pH264Caps->maxBPictureL0ReferenceCount = 0;
				pH264Caps->maxL1ReferenceCount = 0;
				pH264Caps->maxTemporalLayerCount = 1;
				pH264Caps->expectDyadicTemporalLayerPattern = VK_FALSE;
				pH264Caps->minQp = kMVKVideoMinQp;
				pH264Caps->maxQp = kMVKVideoMaxQp;
				pH264Caps->prefersGopRemainingFrames = VK_FALSE;
				pH264Caps->requiresGopRemainingFrames = VK_FALSE;
				pH264Caps->stdSyntaxFlags = 0;
				break;
			}
			case VK_STRUCTURE_TYPE_VIDEO_ENCODE_H265_CAPABILITIES_KHR: {
				auto* pH265Caps = (VkVideoEncodeH265CapabilitiesKHR*)next;
				pH265Caps->flags = 0;
				pH265Caps->maxLevelIdc = STD_VIDEO_H265_LEVEL_IDC_6_2;
				pH265Caps->maxSliceSegmentCount = 1;
				pH265Caps->maxTiles = { 1, 1 };
				pH265Caps->ctbSizes = VK_VIDEO_ENCODE_H265_CTB_SIZE_32_BIT_KHR | VK_VIDEO_ENCODE_H265_CTB_SIZE_64_BIT_KHR;
				pH265Caps->transformBlockSizes = (VK_VIDEO_ENCODE_H265_TRANSFORM_BLOCK_SIZE_4_BIT_KHR |
												  VK_VIDEO_ENCODE_H265_TRANSFORM_BLOCK_SIZE_8_BIT_KHR |
												  VK_VIDEO_ENCODE_H265_TRANSFORM_BLOCK_SIZE_16_BIT_KHR |
												  VK_VIDEO_ENCODE_H265_TRANSFORM_BLOCK_SIZE_32_BIT_KHR);
				pH265Caps->maxPPictureL0ReferenceCount = 1;
				pH265Caps->maxBPictureL0ReferenceCount = 0;
				pH265Caps->maxL1ReferenceCount = 0;
				pH265Caps->maxSubLayerCount = 1;
				pH265Caps->expectDyadicTemporalSubLayerPattern = VK_FALSE;
				pH265Caps->minQp = kMVKVideoMinQp;
				pH265Caps->maxQp = kMVKVideoMaxQp;
				pH265Caps->prefersGopRemainingFrames = VK_FALSE;
				pH265Caps->requiresGopRemainingFrames = VK_FALSE;
				pH265Caps->stdSyntaxFlags = 0;
				break;
			}
			default:
				break;
		}
	}
	return VK_SUCCESS;
}

VkResult mvkGetPhysicalDeviceVideoFormatProperties(MVKPhysicalDevice* physicalDevice,
												   const VkPhysicalDeviceVideoFormatInfoKHR* pVideoFormatInfo,
												   uint32_t* pVideoFormatPropertyCount,
												   VkVideoFormatPropertiesKHR* pVideoFormatProperties) {
	const VkVideoProfileListInfoKHR* pProfiles = nullptr;
	for (const auto* next = (VkBaseInStructure*)pVideoFormatInfo->pNext; next; next = next->pNext) {
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_PROFILE_LIST_INFO_KHR) {
			pProfiles = (const VkVideoProfileListInfoKHR*)next;
		}
	}
	if ( !pProfiles || pProfiles->profileCount == 0 ) { return VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR; }
	bool encode = false, decode = false;
	bool c444 = mvkIsChroma444Profile(&pProfiles->pProfiles[0]);
	for (uint32_t i = 0; i < pProfiles->profileCount; i++) {
		VkResult rslt = mvkCheckVideoProfile(&pProfiles->pProfiles[i]);
		if (rslt != VK_SUCCESS) { return rslt; }
		if (mvkIsChroma444Profile(&pProfiles->pProfiles[i]) != c444) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }
		(mvkIsDecodeProfile(&pProfiles->pProfiles[i]) ? decode : encode) = true;
	}

	const VkImageUsageFlags encodeUsage = VK_IMAGE_USAGE_VIDEO_ENCODE_SRC_BIT_KHR | VK_IMAGE_USAGE_VIDEO_ENCODE_DPB_BIT_KHR;
	const VkImageUsageFlags decodeUsage = VK_IMAGE_USAGE_VIDEO_DECODE_DST_BIT_KHR | VK_IMAGE_USAGE_VIDEO_DECODE_DPB_BIT_KHR;
	const VkImageUsageFlags allVideoUsage = encodeUsage | decodeUsage | VK_IMAGE_USAGE_VIDEO_DECODE_SRC_BIT_KHR;
	VkImageUsageFlags videoUsage = (encode ? encodeUsage : 0) | (decode ? decodeUsage : 0);
	if ( !mvkIsAnyFlagEnabled(pVideoFormatInfo->imageUsage, videoUsage) ) { return VK_ERROR_FORMAT_NOT_SUPPORTED; }
	if ( mvkIsAnyFlagEnabled(pVideoFormatInfo->imageUsage, allVideoUsage & ~videoUsage) ) {
		return VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR;
	}

	// one picture format, two planes, as VideoToolbox takes it
	if ( !pVideoFormatProperties ) {
		*pVideoFormatPropertyCount = 1;
		return VK_SUCCESS;
	}
	if (*pVideoFormatPropertyCount == 0) { return VK_INCOMPLETE; }
	*pVideoFormatPropertyCount = 1;

	auto& props = pVideoFormatProperties[0];
	props.format = c444 ? VK_FORMAT_G8_B8R8_2PLANE_444_UNORM : VK_FORMAT_G8_B8R8_2PLANE_420_UNORM;
	props.componentMapping = { VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
							   VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY };
	props.imageCreateFlags = 0;
	props.imageType = VK_IMAGE_TYPE_2D;
	props.imageTiling = VK_IMAGE_TILING_OPTIMAL;
	props.imageUsageFlags = pVideoFormatInfo->imageUsage;
	if (mvkIsAnyFlagEnabled(pVideoFormatInfo->imageUsage, VK_IMAGE_USAGE_VIDEO_ENCODE_SRC_BIT_KHR | VK_IMAGE_USAGE_VIDEO_DECODE_DST_BIT_KHR)) {
		props.imageUsageFlags |= (VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT |
								  VK_IMAGE_USAGE_SAMPLED_BIT);
	}
	return VK_SUCCESS;
}

VkResult mvkGetPhysicalDeviceVideoEncodeQualityLevelProperties(MVKPhysicalDevice* physicalDevice,
															   const VkPhysicalDeviceVideoEncodeQualityLevelInfoKHR* pQualityLevelInfo,
															   VkVideoEncodeQualityLevelPropertiesKHR* pQualityLevelProperties) {
	VkResult rslt = mvkCheckVideoProfile(pQualityLevelInfo->pVideoProfile);
	if (rslt != VK_SUCCESS) { return rslt; }
	if (pQualityLevelInfo->qualityLevel != 0) { return VK_ERROR_VALIDATION_FAILED_EXT; }

	pQualityLevelProperties->preferredRateControlMode = VK_VIDEO_ENCODE_RATE_CONTROL_MODE_VBR_BIT_KHR;
	pQualityLevelProperties->preferredRateControlLayerCount = 1;

	auto* pH264 = mvkH264Profile(pQualityLevelInfo->pVideoProfile);
	bool cabac = pH264 && pH264->stdProfileIdc != STD_VIDEO_H264_PROFILE_IDC_BASELINE;
	for (auto* next = (VkBaseOutStructure*)pQualityLevelProperties->pNext; next; next = next->pNext) {
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H264_QUALITY_LEVEL_PROPERTIES_KHR) {
			auto* pH264Props = (VkVideoEncodeH264QualityLevelPropertiesKHR*)next;
			pH264Props->preferredRateControlFlags = 0;
			pH264Props->preferredGopFrameCount = 60;
			pH264Props->preferredIdrPeriod = 60;
			pH264Props->preferredConsecutiveBFrameCount = 0;
			pH264Props->preferredTemporalLayerCount = 1;
			pH264Props->preferredConstantQp = { 26, 26, 26 };
			pH264Props->preferredMaxL0ReferenceCount = 1;
			pH264Props->preferredMaxL1ReferenceCount = 0;
			pH264Props->preferredStdEntropyCodingModeFlag = cabac;
		} else if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H265_QUALITY_LEVEL_PROPERTIES_KHR) {
			auto* pH265Props = (VkVideoEncodeH265QualityLevelPropertiesKHR*)next;
			pH265Props->preferredRateControlFlags = 0;
			pH265Props->preferredGopFrameCount = 60;
			pH265Props->preferredIdrPeriod = 60;
			pH265Props->preferredConsecutiveBFrameCount = 0;
			pH265Props->preferredSubLayerCount = 1;
			pH265Props->preferredConstantQp = { 26, 26, 26 };
			pH265Props->preferredMaxL0ReferenceCount = 1;
			pH265Props->preferredMaxL1ReferenceCount = 0;
		}
	}
	return VK_SUCCESS;
}


#pragma mark -
#pragma mark MVKVideoSession

VkResult MVKVideoSession::getMemoryRequirements(uint32_t* pCount, VkVideoSessionMemoryRequirementsKHR* pRequirements) {
	*pCount = 0;
	return VK_SUCCESS;
}

VkResult MVKVideoSession::bindMemory(uint32_t bindCount, const VkBindVideoSessionMemoryInfoKHR* pBindInfos) {
	return VK_SUCCESS;
}

// the picture size an SPS describes, after its cropping
static VkExtent2D mvkSPSFrameExtent(const StdVideoH264SequenceParameterSet* pSPS) {
	uint32_t frameMbsOnly = pSPS->flags.frame_mbs_only_flag ? 1 : 0;
	uint32_t w = (pSPS->pic_width_in_mbs_minus1 + 1) * 16;
	uint32_t h = (pSPS->pic_height_in_map_units_minus1 + 1) * 16 * (2 - frameMbsOnly);
	if (pSPS->flags.frame_cropping_flag) {
		uint32_t cropX = 2;
		uint32_t cropY = 2 * (2 - frameMbsOnly);
		w -= cropX * (pSPS->frame_crop_left_offset + pSPS->frame_crop_right_offset);
		h -= cropY * (pSPS->frame_crop_top_offset + pSPS->frame_crop_bottom_offset);
	}
	return { w, h };
}

VkResult MVKVideoSession::prepare(const StdVideoH264SequenceParameterSet* pSPS,
								  const StdVideoH264PictureParameterSet* pPPS,
								  vector<uint8_t>* pSPSOut,
								  vector<uint8_t>* pPPSOut) {
	if ( !pSPS ) { return VK_ERROR_INITIALIZATION_FAILED; }

	VkExtent2D extent = mvkSPSFrameExtent(pSPS);
	bool fullRange = false;
	double frameRate = _frameRate;
	const auto* pVui = pSPS->flags.vui_parameters_present_flag ? pSPS->pSequenceParameterSetVui : nullptr;
	if (pVui) {
		fullRange = pVui->flags.video_full_range_flag;
		if (pVui->flags.timing_info_present_flag && pVui->num_units_in_tick) {
			frameRate = double(pVui->time_scale) / (2.0 * pVui->num_units_in_tick);
		}
	}
	bool cabac = pPPS ? pPPS->flags.entropy_coding_mode_flag : (_profileIdc != STD_VIDEO_H264_PROFILE_IDC_BASELINE);

	lock_guard<mutex> lock(_lock);
	VkResult rslt = prepareEncoder(extent, fullRange, cabac, frameRate);
	if (rslt != VK_SUCCESS) { return rslt; }
	if (pSPSOut) { *pSPSOut = _sps; }
	if (pPPSOut) { *pPPSOut = _pps; }
	return VK_SUCCESS;
}

// the picture size an H.265 SPS describes, after its conformance window
static VkExtent2D mvkH265FrameExtent(const StdVideoH265SequenceParameterSet* pSPS) {
	uint32_t w = pSPS->pic_width_in_luma_samples;
	uint32_t h = pSPS->pic_height_in_luma_samples;
	if (pSPS->flags.conformance_window_flag) {
		uint32_t subW = (pSPS->chroma_format_idc == STD_VIDEO_H265_CHROMA_FORMAT_IDC_420 ||
						 pSPS->chroma_format_idc == STD_VIDEO_H265_CHROMA_FORMAT_IDC_422) ? 2 : 1;
		uint32_t subH = (pSPS->chroma_format_idc == STD_VIDEO_H265_CHROMA_FORMAT_IDC_420) ? 2 : 1;
		w -= subW * (pSPS->conf_win_left_offset + pSPS->conf_win_right_offset);
		h -= subH * (pSPS->conf_win_top_offset + pSPS->conf_win_bottom_offset);
	}
	return { w, h };
}

VkResult MVKVideoSession::prepareH265(const StdVideoH265VideoParameterSet* pVPS,
									  const StdVideoH265SequenceParameterSet* pSPS,
									  const StdVideoH265PictureParameterSet* pPPS,
									  vector<uint8_t>* pVPSOut,
									  vector<uint8_t>* pSPSOut,
									  vector<uint8_t>* pPPSOut) {
	if ( !pSPS ) { return VK_ERROR_INITIALIZATION_FAILED; }

	VkExtent2D extent = mvkH265FrameExtent(pSPS);
	bool fullRange = false;
	double frameRate = _frameRate;
	const auto* pVui = pSPS->flags.vui_parameters_present_flag ? pSPS->pSequenceParameterSetVui : nullptr;
	if (pVui) {
		fullRange = pVui->flags.video_signal_type_present_flag && pVui->flags.video_full_range_flag;
		if (pVui->flags.vui_timing_info_present_flag && pVui->vui_num_units_in_tick) {
			frameRate = double(pVui->vui_time_scale) / double(pVui->vui_num_units_in_tick);
		}
	} else if (pVPS && pVPS->flags.vps_timing_info_present_flag && pVPS->vps_num_units_in_tick) {
		frameRate = double(pVPS->vps_time_scale) / double(pVPS->vps_num_units_in_tick);
	}

	lock_guard<mutex> lock(_lock);
	VkResult rslt = prepareEncoder(extent, fullRange, true, frameRate);
	if (rslt != VK_SUCCESS) { return rslt; }
	if (pVPSOut) { *pVPSOut = _vps; }
	if (pSPSOut) { *pSPSOut = _sps; }
	if (pPPSOut) { *pPPSOut = _pps; }
	return VK_SUCCESS;
}

// called with _lock held: a new encoder only when the picture changes
VkResult MVKVideoSession::prepareEncoder(VkExtent2D extent, bool fullRange, bool cabac, double frameRate) {
	bool same = (_vtSession && _frameExtent.width == extent.width && _frameExtent.height == extent.height &&
				 _pixelFormat == pixelFormatFor(fullRange) && _cabac == cabac);
	if (same) { return VK_SUCCESS; }
	destroyEncoder();
	VkResult rslt = createEncoder(extent.width, extent.height, fullRange, cabac, frameRate);
	if (rslt != VK_SUCCESS) { return rslt; }
	return primeParameterSets();
}

// two planes: luma, then interleaved chroma at 4:2:0 or 4:4:4
OSType MVKVideoSession::pixelFormatFor(bool fullRange) const {
	if (_chroma444) {
		return fullRange ? kCVPixelFormatType_444YpCbCr8BiPlanarFullRange
						 : kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange;
	}
	return fullRange ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
					 : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
}

static void mvkSetVTProperty(VTCompressionSessionRef vt, CFStringRef key, id value) {
	VTSessionSetProperty(vt, key, (__bridge CFTypeRef)value);
}

VkResult MVKVideoSession::createEncoder(uint32_t width, uint32_t height, bool fullRange, bool cabac, double frameRate) {
	@autoreleasepool {
		_pixelFormat = pixelFormatFor(fullRange);
		NSMutableDictionary* spec = [NSMutableDictionary dictionary];
#if MVK_MACOS
		spec[(NSString*)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = @YES;
#endif
		NSDictionary* sourceAttrs = @{
			(NSString*)kCVPixelBufferPixelFormatTypeKey: @(_pixelFormat),
			(NSString*)kCVPixelBufferWidthKey: @(width),
			(NSString*)kCVPixelBufferHeightKey: @(height),
			(NSString*)kCVPixelBufferIOSurfacePropertiesKey: @{},
			(NSString*)kCVPixelBufferMetalCompatibilityKey: @YES,
		};
		OSStatus st = VTCompressionSessionCreate(kCFAllocatorDefault, (int32_t)width, (int32_t)height,
												 _hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264, (CFDictionaryRef)spec,
												 (CFDictionaryRef)sourceAttrs, kCFAllocatorDefault,
												 nullptr, nullptr, &_vtSession);
		if (st != noErr || !_vtSession) {
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateVideoSessionKHR(): VideoToolbox could not create an %s encoder (%d).",
							   _hevc ? "H.265" : "H.264", (int)st);
		}

		mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_RealTime, @YES);
		mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_AllowFrameReordering, @NO);
		if (_hevc) {
			CFStringRef profile = _chroma444 ? kMVKProfileLevel_HEVC_Main444 : kVTProfileLevel_HEVC_Main_AutoLevel;
			OSStatus pst = VTSessionSetProperty(_vtSession, kVTCompressionPropertyKey_ProfileLevel, profile);
			if (pst != noErr) {
				destroyEncoder();
				return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateVideoSessionKHR(): VideoToolbox refused the H.265 %s profile (%d).",
								   _chroma444 ? "4:4:4" : "Main", (int)pst);
			}
		} else {
			CFStringRef profile = kVTProfileLevel_H264_High_AutoLevel;
			if (_profileIdc == STD_VIDEO_H264_PROFILE_IDC_MAIN) { profile = kVTProfileLevel_H264_Main_AutoLevel; }
			if (_profileIdc == STD_VIDEO_H264_PROFILE_IDC_BASELINE) { profile = kVTProfileLevel_H264_Baseline_AutoLevel; }
			bool useCabac = cabac && _profileIdc != STD_VIDEO_H264_PROFILE_IDC_BASELINE;
			mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_ProfileLevel, (__bridge id)profile);
			mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_H264EntropyMode,
							 (__bridge id)(useCabac ? kVTH264EntropyMode_CABAC : kVTH264EntropyMode_CAVLC));
		}
		// the app places each IDR; VideoToolbox never adds its own
		mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, @(INT32_MAX));
		mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_ExpectedFrameRate, @(frameRate));
		VTCompressionSessionPrepareToEncodeFrames(_vtSession);

		_pixelBufferPool = VTCompressionSessionGetPixelBufferPool(_vtSession);
		if (_pixelBufferPool) { CFRetain(_pixelBufferPool); }
		CVMetalTextureCacheCreate(kCFAllocatorDefault, nullptr, getMTLDevice(), nullptr, &_textureCache);
		if ( !_pixelBufferPool || !_textureCache ) {
			destroyEncoder();
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateVideoSessionKHR(): VideoToolbox gave no pixel buffer pool.");
		}

		_frameExtent = { width, height };
		_cabac = cabac;
		_frameRate = frameRate;
		_appliedQp = -1;
		_rcDirty = true;
		_forceIdr = true;
		return VK_SUCCESS;
	}
}

void MVKVideoSession::destroyEncoder() {
	if (_vtSession) {
		VTCompressionSessionCompleteFrames(_vtSession, kCMTimeInvalid);
		VTCompressionSessionInvalidate(_vtSession);
		CFRelease(_vtSession);
		_vtSession = nullptr;
	}
	if (_pixelBufferPool) { CFRelease(_pixelBufferPool); _pixelBufferPool = nullptr; }
	if (_textureCache) { CFRelease(_textureCache); _textureCache = nullptr; }
	_vps.clear();
	_sps.clear();
	_pps.clear();
	_frameExtent = { 0, 0 };
}

// the SPS and PPS exist once a frame is encoded: encode one black frame
VkResult MVKVideoSession::primeParameterSets() {
	@autoreleasepool {
	CVPixelBufferRef pb = nullptr;
	if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pixelBufferPool, &pb) != kCVReturnSuccess || !pb) {
		return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateVideoSessionParametersKHR(): no pixel buffer to prime the encoder.");
	}
	bool fullRange = (_pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
					  _pixelFormat == kCVPixelFormatType_444YpCbCr8BiPlanarFullRange);
	CVPixelBufferLockBaseAddress(pb, 0);
	for (size_t plane = 0; plane < 2; plane++) {
		uint8_t* base = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pb, plane);
		size_t size = CVPixelBufferGetBytesPerRowOfPlane(pb, plane) * CVPixelBufferGetHeightOfPlane(pb, plane);
		if (base) { memset(base, plane ? 128 : (fullRange ? 0 : 16), size); }
	}
	CVPixelBufferUnlockBaseAddress(pb, 0);

	__block CMFormatDescriptionRef fmt = nullptr;
	NSDictionary* frameProps = @{ (NSString*)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES };
	CMTime pts = CMTimeMake(_frameIndex++, 1000);
	OSStatus st = VTCompressionSessionEncodeFrameWithOutputHandler(_vtSession, pb, pts, kCMTimeInvalid,
																   (CFDictionaryRef)frameProps, nullptr,
																   ^(OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sb) {
		if (status == noErr && sb) {
			fmt = CMSampleBufferGetFormatDescription(sb);
			if (fmt) { CFRetain(fmt); }
		}
	});
	VTCompressionSessionCompleteFrames(_vtSession, pts);
	CVPixelBufferRelease(pb);
	if (st != noErr || !fmt) {
		return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateVideoSessionParametersKHR(): VideoToolbox gave no parameter sets (%d).", (int)st);
	}

	size_t count = 0;
	if (_hevc) {
		// sorted by NAL type: VPS 32, SPS 33, PPS 34
		CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fmt, 0, nullptr, nullptr, &count, nullptr);
		for (size_t i = 0; i < count; i++) {
			const uint8_t* ps = nullptr;
			size_t psSize = 0;
			if (CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fmt, i, &ps, &psSize, nullptr, nullptr) != noErr || !psSize) { continue; }
			uint32_t type = (ps[0] >> 1) & 63;
			if (type == 32 && _vps.empty()) { _vps.assign(ps, ps + psSize); }
			if (type == 33 && _sps.empty()) { _sps.assign(ps, ps + psSize); }
			if (type == 34 && _pps.empty()) { _pps.assign(ps, ps + psSize); }
		}
	} else {
		CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, 0, nullptr, nullptr, &count, nullptr);
		for (size_t i = 0; i < count && i < 2; i++) {
			const uint8_t* ps = nullptr;
			size_t psSize = 0;
			if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, i, &ps, &psSize, nullptr, nullptr) == noErr) {
				(i == 0 ? _sps : _pps).assign(ps, ps + psSize);
			}
		}
	}
	CFRelease(fmt);
	_forceIdr = true;
	if (_sps.empty() || _pps.empty() || (_hevc && _vps.empty())) {
		return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateVideoSessionParametersKHR(): VideoToolbox gave incomplete parameter sets.");
	}
	return VK_SUCCESS;
	}
}

CVPixelBufferRef MVKVideoSession::newPixelBuffer(id<MTLTexture>* pLuma, id<MTLTexture>* pChroma,
												 CVMetalTextureRef* pLumaRef, CVMetalTextureRef* pChromaRef) {
	lock_guard<mutex> lock(_lock);
	*pLuma = nil; *pChroma = nil; *pLumaRef = nullptr; *pChromaRef = nullptr;
	if ( !_pixelBufferPool ) { return nullptr; }

	CVPixelBufferRef pb = nullptr;
	if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pixelBufferPool, &pb) != kCVReturnSuccess) { return nullptr; }
	if ( !newTextures(pb, pLuma, pChroma, pLumaRef, pChromaRef) ) {
		CVPixelBufferRelease(pb);
		return nullptr;
	}
	return pb;
}

// called with _lock held, or on a buffer only this thread has
bool MVKVideoSession::newTextures(CVPixelBufferRef pb, id<MTLTexture>* pLuma, id<MTLTexture>* pChroma,
								  CVMetalTextureRef* pLumaRef, CVMetalTextureRef* pChromaRef) {
	*pLuma = nil; *pChroma = nil; *pLumaRef = nullptr; *pChromaRef = nullptr;
	if ( !_textureCache ) { return false; }
	size_t w = CVPixelBufferGetWidthOfPlane(pb, 0);
	size_t h = CVPixelBufferGetHeightOfPlane(pb, 0);
	size_t cw = CVPixelBufferGetWidthOfPlane(pb, 1);
	size_t ch = CVPixelBufferGetHeightOfPlane(pb, 1);
	CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pb, nullptr,
											  MTLPixelFormatR8Unorm, w, h, 0, pLumaRef);
	CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pb, nullptr,
											  MTLPixelFormatRG8Unorm, cw, ch, 1, pChromaRef);
	if ( !*pLumaRef || !*pChromaRef ) {
		if (*pLumaRef) { CFRelease(*pLumaRef); *pLumaRef = nullptr; }
		if (*pChromaRef) { CFRelease(*pChromaRef); *pChromaRef = nullptr; }
		return false;
	}
	*pLuma = CVMetalTextureGetTexture(*pLumaRef);
	*pChroma = CVMetalTextureGetTexture(*pChromaRef);
	return true;
}

void MVKVideoSession::reset() {
	lock_guard<mutex> lock(_lock);
	if (_vtSession) { VTCompressionSessionCompleteFrames(_vtSession, kCMTimeInvalid); }
	if (_vtDecoder) { VTDecompressionSessionWaitForAsynchronousFrames(_vtDecoder); }
	_forceIdr = true;
}

void MVKVideoSession::setRateControl(const VkVideoEncodeRateControlInfoKHR& rateControl) {
	lock_guard<mutex> lock(_lock);
	_rcMode = rateControl.rateControlMode;
	_averageBitrate = 0;
	_maxBitrate = 0;
	if (rateControl.layerCount > 0 && rateControl.pLayers) {
		const auto& layer = rateControl.pLayers[0];
		_averageBitrate = layer.averageBitrate;
		_maxBitrate = layer.maxBitrate;
		if (layer.frameRateNumerator && layer.frameRateDenominator) {
			_frameRate = double(layer.frameRateNumerator) / double(layer.frameRateDenominator);
		}
	}
	_rcDirty = true;
}

// called with _lock held
void MVKVideoSession::applyRateControl(int32_t constantQp) {
	if ( !_vtSession ) { return; }
	@autoreleasepool {
		if (_rcDirty) {
			_rcDirty = false;
			mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_ExpectedFrameRate, @(_frameRate));
			if (_rcMode == VK_VIDEO_ENCODE_RATE_CONTROL_MODE_CBR_BIT_KHR && _averageBitrate) {
				bool cbr = false;
				if (@available(macOS 13.0, iOS 16.0, tvOS 16.0, *)) {
					cbr = VTSessionSetProperty(_vtSession, kVTCompressionPropertyKey_ConstantBitRate,
											   (__bridge CFTypeRef)@(_averageBitrate)) == noErr;
				}
				if ( !cbr ) {
					mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_AverageBitRate, @(_averageBitrate));
					mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_DataRateLimits, @[ @(_averageBitrate / 8), @1 ]);
				}
			} else if (_rcMode == VK_VIDEO_ENCODE_RATE_CONTROL_MODE_VBR_BIT_KHR && _averageBitrate) {
				mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_AverageBitRate, @(_averageBitrate));
				uint64_t peak = _maxBitrate ? _maxBitrate : _averageBitrate;
				mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_DataRateLimits, @[ @(peak / 8), @1 ]);
			}
			if (_rcMode != VK_VIDEO_ENCODE_RATE_CONTROL_MODE_DISABLED_BIT_KHR && _appliedQp >= 0) {
				if (@available(macOS 13.0, iOS 16.0, tvOS 16.0, *)) {
					mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_MinAllowedFrameQP, @(kMVKVideoMinQp));
					mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_MaxAllowedFrameQP, @(kMVKVideoMaxQp));
				}
				_appliedQp = -1;
			}
		}

		// rate control off: every frame at the app's QP
		if (_rcMode == VK_VIDEO_ENCODE_RATE_CONTROL_MODE_DISABLED_BIT_KHR && constantQp != _appliedQp) {
			int32_t qp = mvkClamp(constantQp, kMVKVideoMinQp, kMVKVideoMaxQp);
			bool exact = false;
			if (@available(macOS 13.0, iOS 16.0, tvOS 16.0, *)) {
				exact = (VTSessionSetProperty(_vtSession, kVTCompressionPropertyKey_MinAllowedFrameQP, (__bridge CFTypeRef)@(qp)) == noErr &&
						 VTSessionSetProperty(_vtSession, kVTCompressionPropertyKey_MaxAllowedFrameQP, (__bridge CFTypeRef)@(qp)) == noErr);
			}
			if ( !exact ) {
				float quality = 1.0f - float(qp - kMVKVideoMinQp) / float(kMVKVideoMaxQp - kMVKVideoMinQp);
				mvkSetVTProperty(_vtSession, kVTCompressionPropertyKey_Quality, @(quality));
			}
			_appliedQp = constantQp;
		}
	}
}

// AVCC length prefixes become Annex B start codes
static size_t mvkAnnexBSize(const uint8_t* avcc, size_t size, int nalHeaderLength) {
	size_t out = 0;
	size_t pos = 0;
	while (pos + nalHeaderLength <= size) {
		uint32_t nalSize = 0;
		for (int i = 0; i < nalHeaderLength; i++) { nalSize = (nalSize << 8) | avcc[pos + i]; }
		pos += nalHeaderLength;
		if (pos + nalSize > size) { break; }
		out += 4 + nalSize;
		pos += nalSize;
	}
	return out;
}

static void mvkWriteAnnexB(const uint8_t* avcc, size_t size, int nalHeaderLength, uint8_t* dst) {
	size_t pos = 0;
	while (pos + nalHeaderLength <= size) {
		uint32_t nalSize = 0;
		for (int i = 0; i < nalHeaderLength; i++) { nalSize = (nalSize << 8) | avcc[pos + i]; }
		pos += nalHeaderLength;
		if (pos + nalSize > size) { break; }
		dst[0] = 0; dst[1] = 0; dst[2] = 0; dst[3] = 1;
		memcpy(dst + 4, avcc + pos, nalSize);
		dst += 4 + nalSize;
		pos += nalSize;
	}
}

void MVKVideoSession::encodeFrame(CVPixelBufferRef pixelBuffer, bool idr, int32_t constantQp,
								  uint8_t* dst, size_t dstSize,
								  uint64_t* pBytesWritten, int32_t* pStatus) {
	*pBytesWritten = 0;
	*pStatus = VK_QUERY_RESULT_STATUS_ERROR_KHR;

	lock_guard<mutex> lock(_lock);
	if ( !_vtSession || !pixelBuffer || !dst ) { return; }
	applyRateControl(constantQp);

	@autoreleasepool {
		bool key = idr || _forceIdr;
		_forceIdr = false;
		NSDictionary* frameProps = key ? @{ (NSString*)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES } : nil;
		double rate = _frameRate > 0 ? _frameRate : 60.0;
		CMTime pts = CMTimeMake((int64_t)(_frameIndex++ * (1000000.0 / rate)), 1000000);

		__block uint64_t written = 0;
		__block int32_t status = VK_QUERY_RESULT_STATUS_ERROR_KHR;
		OSStatus st = VTCompressionSessionEncodeFrameWithOutputHandler(_vtSession, pixelBuffer, pts, kCMTimeInvalid,
																	   (CFDictionaryRef)frameProps, nullptr,
																	   ^(OSStatus encStatus, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sb) {
			if (encStatus != noErr || !sb) { return; }
			CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
			CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sb);
			if ( !bb || !fmt ) { return; }
			int nalHeaderLength = 4;
			if (_hevc) {
				CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fmt, 0, nullptr, nullptr, nullptr, &nalHeaderLength);
			} else {
				CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, 0, nullptr, nullptr, nullptr, &nalHeaderLength);
			}

			size_t size = CMBlockBufferGetDataLength(bb);
			char* data = nullptr;
			vector<uint8_t> copy;
			size_t contiguous = 0;
			if (CMBlockBufferGetDataPointer(bb, 0, &contiguous, nullptr, &data) != kCMBlockBufferNoErr || contiguous < size) {
				copy.resize(size);
				CMBlockBufferCopyDataBytes(bb, 0, size, copy.data());
				data = (char*)copy.data();
			}
			size_t annexB = mvkAnnexBSize((const uint8_t*)data, size, nalHeaderLength);
			if (annexB > dstSize) {
				status = VK_QUERY_RESULT_STATUS_INSUFFICIENT_BITSTREAM_BUFFER_RANGE_KHR;
				return;
			}
			mvkWriteAnnexB((const uint8_t*)data, size, nalHeaderLength, dst);
			written = annexB;
			status = VK_QUERY_RESULT_STATUS_COMPLETE_KHR;
		});
		VTCompressionSessionCompleteFrames(_vtSession, pts);
		if (st == noErr) {
			*pBytesWritten = written;
			*pStatus = status;
		}
	}
}

MVKVideoSession::MVKVideoSession(MVKDevice* device, const VkVideoSessionCreateInfoKHR* pCreateInfo) : MVKVulkanAPIDeviceObject(device) {
	_maxCodedExtent = pCreateInfo->maxCodedExtent;
	_profileIdc = STD_VIDEO_H264_PROFILE_IDC_HIGH;

	VkResult rslt = mvkCheckVideoProfile(pCreateInfo->pVideoProfile);
	if (rslt != VK_SUCCESS) {
		setConfigurationResult(reportError(rslt, "vkCreateVideoSessionKHR(): unsupported video profile."));
		return;
	}
	_decode = mvkIsDecodeProfile(pCreateInfo->pVideoProfile);
	_hevc = mvkIsHevcProfile(pCreateInfo->pVideoProfile);
	_chroma444 = mvkIsChroma444Profile(pCreateInfo->pVideoProfile);
	if ( !_hevc ) {
		_profileIdc = (_decode ? mvkH264DecodeProfile(pCreateInfo->pVideoProfile)->stdProfileIdc
							   : mvkH264Profile(pCreateInfo->pVideoProfile)->stdProfileIdc);
	}

	if (pCreateInfo->maxCodedExtent.width < kMVKVideoMinCodedExtent.width ||
		pCreateInfo->maxCodedExtent.height < kMVKVideoMinCodedExtent.height ||
		pCreateInfo->maxCodedExtent.width > kMVKVideoMaxCodedExtent.width ||
		pCreateInfo->maxCodedExtent.height > kMVKVideoMaxCodedExtent.height) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateVideoSessionKHR(): maxCodedExtent %ux%u is outside what VideoToolbox supports.",
										   pCreateInfo->maxCodedExtent.width, pCreateInfo->maxCodedExtent.height));
		return;
	}
	uint32_t maxRefs = _decode ? kMVKVideoDecodeMaxActiveReferences : 1;
	uint32_t maxSlots = _decode ? kMVKVideoDecodeMaxDpbSlots : kMVKVideoMaxDpbSlots;
	if (pCreateInfo->maxActiveReferencePictures > maxRefs || pCreateInfo->maxDpbSlots > maxSlots) {
		setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCreateVideoSessionKHR(): more reference pictures than VideoToolbox supports."));
		return;
	}
	const char* stdName = (_hevc ? (_decode ? VK_STD_VULKAN_VIDEO_CODEC_H265_DECODE_EXTENSION_NAME
											: VK_STD_VULKAN_VIDEO_CODEC_H265_ENCODE_EXTENSION_NAME)
								 : (_decode ? VK_STD_VULKAN_VIDEO_CODEC_H264_DECODE_EXTENSION_NAME
											: VK_STD_VULKAN_VIDEO_CODEC_H264_ENCODE_EXTENSION_NAME));
	if (pCreateInfo->pStdHeaderVersion && strcmp(pCreateInfo->pStdHeaderVersion->extensionName, stdName) != 0) {
		setConfigurationResult(reportError(VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR, "vkCreateVideoSessionKHR(): unsupported video std header."));
		return;
	}
}

MVKVideoSession::~MVKVideoSession() {
	lock_guard<mutex> lock(_lock);
	destroyDecoder();
	destroyEncoder();
}


#pragma mark -
#pragma mark H.264 parameter set writer

// RBSP bits, closed into one NAL with emulation prevention
class MVKH264Writer {

public:
	void u(uint32_t bits, uint32_t value) {
		for (int32_t i = int32_t(bits) - 1; i >= 0; i--) { bit((value >> i) & 1); }
	}

	void ue(uint32_t value) {
		uint64_t v = uint64_t(value) + 1;
		uint32_t len = 0;
		for (uint64_t t = v; t > 1; t >>= 1) { len++; }
		u(len, 0);
		for (int32_t i = int32_t(len); i >= 0; i--) { bit(uint32_t(v >> i) & 1); }
	}

	void se(int32_t value) {
		ue(value > 0 ? uint32_t(2 * int64_t(value) - 1) : uint32_t(-2 * int64_t(value)));
	}

	void flag(bool value) { bit(value ? 1 : 0); }

	vector<uint8_t> nal(uint8_t header) { return nal(&header, 1); }

	// H.265 NAL units carry a two-byte header
	vector<uint8_t> nal(const uint8_t* header, size_t headerSize) {
		bit(1);
		while (_count) { bit(0); }
		vector<uint8_t> out(header, header + headerSize);
		uint32_t zeros = 0;
		for (uint8_t b : _rbsp) {
			if (zeros >= 2 && b <= 3) { out.push_back(3); zeros = 0; }
			out.push_back(b);
			zeros = b ? 0 : zeros + 1;
		}
		return out;
	}

protected:
	void bit(uint32_t b) {
		_cur = uint8_t((_cur << 1) | b);
		if (++_count == 8) { _rbsp.push_back(_cur); _cur = 0; _count = 0; }
	}

	vector<uint8_t> _rbsp;
	uint8_t _cur = 0;
	uint32_t _count = 0;
};

static uint32_t mvkH264LevelIdc(StdVideoH264LevelIdc level) {
	static const uint8_t idc[] = { 10, 11, 12, 13, 20, 21, 22, 30, 31, 32, 40, 41, 42, 50, 51, 52, 60, 61, 62 };
	return uint32_t(level) < sizeof(idc) ? idc[level] : 52;
}

// the profiles whose SPS carries chroma format and bit depths
static bool mvkH264HasChromaInfo(uint32_t profileIdc) {
	switch (profileIdc) {
		case 100: case 110: case 122: case 244: case 44: case 83:
		case 86: case 118: case 128: case 138: case 139: case 134: case 135:
			return true;
		default:
			return false;
	}
}

// lists are in scan order, as the bitstream carries them
static void mvkWriteH264ScalingList(MVKH264Writer& w, const uint8_t* list, uint32_t size, bool useDefault) {
	if (useDefault) {
		w.se(-8);
		return;
	}
	int32_t last = 8;
	for (uint32_t j = 0; j < size; j++) {
		int32_t delta = int32_t(list[j]) - last;
		if (delta > 127) { delta -= 256; }
		if (delta < -128) { delta += 256; }
		w.se(delta);
		last = list[j];
	}
}

static void mvkWriteH264ScalingLists(MVKH264Writer& w, const StdVideoH264ScalingLists& lists, uint32_t count) {
	for (uint32_t i = 0; i < count; i++) {
		bool present = lists.scaling_list_present_mask & (1u << i);
		w.flag(present);
		if ( !present ) { continue; }
		bool useDefault = lists.use_default_scaling_matrix_mask & (1u << i);
		if (i < 6) {
			mvkWriteH264ScalingList(w, lists.ScalingList4x4[i], 16, useDefault);
		} else {
			mvkWriteH264ScalingList(w, lists.ScalingList8x8[i - 6], 64, useDefault);
		}
	}
}

static void mvkWriteH264Hrd(MVKH264Writer& w, const StdVideoH264HrdParameters& hrd) {
	uint32_t count = min<uint32_t>(hrd.cpb_cnt_minus1, STD_VIDEO_H264_CPB_CNT_LIST_SIZE - 1);
	w.ue(count);
	w.u(4, hrd.bit_rate_scale);
	w.u(4, hrd.cpb_size_scale);
	for (uint32_t i = 0; i <= count; i++) {
		w.ue(hrd.bit_rate_value_minus1[i]);
		w.ue(hrd.cpb_size_value_minus1[i]);
		w.flag(hrd.cbr_flag[i]);
	}
	w.u(5, hrd.initial_cpb_removal_delay_length_minus1);
	w.u(5, hrd.cpb_removal_delay_length_minus1);
	w.u(5, hrd.dpb_output_delay_length_minus1);
	w.u(5, hrd.time_offset_length);
}

static void mvkWriteH264Vui(MVKH264Writer& w, const StdVideoH264SequenceParameterSetVui& vui) {
	const auto& f = vui.flags;
	w.flag(f.aspect_ratio_info_present_flag);
	if (f.aspect_ratio_info_present_flag) {
		w.u(8, vui.aspect_ratio_idc);
		if (vui.aspect_ratio_idc == STD_VIDEO_H264_ASPECT_RATIO_IDC_EXTENDED_SAR) {
			w.u(16, vui.sar_width);
			w.u(16, vui.sar_height);
		}
	}
	w.flag(f.overscan_info_present_flag);
	if (f.overscan_info_present_flag) { w.flag(f.overscan_appropriate_flag); }
	w.flag(f.video_signal_type_present_flag);
	if (f.video_signal_type_present_flag) {
		w.u(3, vui.video_format);
		w.flag(f.video_full_range_flag);
		w.flag(f.color_description_present_flag);
		if (f.color_description_present_flag) {
			w.u(8, vui.colour_primaries);
			w.u(8, vui.transfer_characteristics);
			w.u(8, vui.matrix_coefficients);
		}
	}
	w.flag(f.chroma_loc_info_present_flag);
	if (f.chroma_loc_info_present_flag) {
		w.ue(vui.chroma_sample_loc_type_top_field);
		w.ue(vui.chroma_sample_loc_type_bottom_field);
	}
	w.flag(f.timing_info_present_flag);
	if (f.timing_info_present_flag) {
		w.u(32, vui.num_units_in_tick);
		w.u(32, vui.time_scale);
		w.flag(f.fixed_frame_rate_flag);
	}
	bool nalHrd = f.nal_hrd_parameters_present_flag && vui.pHrdParameters;
	bool vclHrd = f.vcl_hrd_parameters_present_flag && vui.pHrdParameters;
	w.flag(nalHrd);
	if (nalHrd) { mvkWriteH264Hrd(w, *vui.pHrdParameters); }
	w.flag(vclHrd);
	if (vclHrd) { mvkWriteH264Hrd(w, *vui.pHrdParameters); }
	if (nalHrd || vclHrd) { w.flag(false); }	// low_delay_hrd_flag
	w.flag(false);									// pic_struct_present_flag
	w.flag(f.bitstream_restriction_flag);
	if (f.bitstream_restriction_flag) {
		// fields the std structure leaves out take their defaults
		w.flag(true);
		w.ue(2);
		w.ue(1);
		w.ue(15);
		w.ue(15);
		w.ue(vui.max_num_reorder_frames);
		w.ue(vui.max_dec_frame_buffering);
	}
}

static vector<uint8_t> mvkWriteH264SPS(const StdVideoH264SequenceParameterSet& sps) {
	MVKH264Writer w;
	const auto& f = sps.flags;
	w.u(8, sps.profile_idc);
	w.flag(f.constraint_set0_flag);
	w.flag(f.constraint_set1_flag);
	w.flag(f.constraint_set2_flag);
	w.flag(f.constraint_set3_flag);
	w.flag(f.constraint_set4_flag);
	w.flag(f.constraint_set5_flag);
	w.u(2, 0);
	w.u(8, mvkH264LevelIdc(sps.level_idc));
	w.ue(sps.seq_parameter_set_id);
	if (mvkH264HasChromaInfo(sps.profile_idc)) {
		w.ue(sps.chroma_format_idc);
		if (sps.chroma_format_idc == STD_VIDEO_H264_CHROMA_FORMAT_IDC_444) { w.flag(f.separate_colour_plane_flag); }
		w.ue(sps.bit_depth_luma_minus8);
		w.ue(sps.bit_depth_chroma_minus8);
		w.flag(f.qpprime_y_zero_transform_bypass_flag);
		bool scaling = f.seq_scaling_matrix_present_flag && sps.pScalingLists;
		w.flag(scaling);
		if (scaling) {
			uint32_t count = sps.chroma_format_idc != STD_VIDEO_H264_CHROMA_FORMAT_IDC_444 ? 8 : 12;
			mvkWriteH264ScalingLists(w, *sps.pScalingLists, count);
		}
	}
	w.ue(sps.log2_max_frame_num_minus4);
	w.ue(sps.pic_order_cnt_type);
	if (sps.pic_order_cnt_type == STD_VIDEO_H264_POC_TYPE_0) {
		w.ue(sps.log2_max_pic_order_cnt_lsb_minus4);
	} else if (sps.pic_order_cnt_type == STD_VIDEO_H264_POC_TYPE_1) {
		w.flag(f.delta_pic_order_always_zero_flag);
		w.se(sps.offset_for_non_ref_pic);
		w.se(sps.offset_for_top_to_bottom_field);
		w.ue(sps.num_ref_frames_in_pic_order_cnt_cycle);
		for (uint32_t i = 0; i < sps.num_ref_frames_in_pic_order_cnt_cycle; i++) {
			w.se(sps.pOffsetForRefFrame ? sps.pOffsetForRefFrame[i] : 0);
		}
	}
	w.ue(sps.max_num_ref_frames);
	w.flag(f.gaps_in_frame_num_value_allowed_flag);
	w.ue(sps.pic_width_in_mbs_minus1);
	w.ue(sps.pic_height_in_map_units_minus1);
	w.flag(f.frame_mbs_only_flag);
	if ( !f.frame_mbs_only_flag ) { w.flag(f.mb_adaptive_frame_field_flag); }
	w.flag(f.direct_8x8_inference_flag);
	w.flag(f.frame_cropping_flag);
	if (f.frame_cropping_flag) {
		w.ue(sps.frame_crop_left_offset);
		w.ue(sps.frame_crop_right_offset);
		w.ue(sps.frame_crop_top_offset);
		w.ue(sps.frame_crop_bottom_offset);
	}
	const auto* pVui = f.vui_parameters_present_flag ? sps.pSequenceParameterSetVui : nullptr;
	w.flag(pVui != nullptr);
	if (pVui) { mvkWriteH264Vui(w, *pVui); }
	return w.nal(0x67);
}

static vector<uint8_t> mvkWriteH264PPS(const StdVideoH264SequenceParameterSet& sps,
									   const StdVideoH264PictureParameterSet& pps) {
	MVKH264Writer w;
	const auto& f = pps.flags;
	w.ue(pps.pic_parameter_set_id);
	w.ue(pps.seq_parameter_set_id);
	w.flag(f.entropy_coding_mode_flag);
	w.flag(f.bottom_field_pic_order_in_frame_present_flag);
	w.ue(0);	// num_slice_groups_minus1
	w.ue(pps.num_ref_idx_l0_default_active_minus1);
	w.ue(pps.num_ref_idx_l1_default_active_minus1);
	w.flag(f.weighted_pred_flag);
	w.u(2, pps.weighted_bipred_idc);
	w.se(pps.pic_init_qp_minus26);
	w.se(pps.pic_init_qs_minus26);
	w.se(pps.chroma_qp_index_offset);
	w.flag(f.deblocking_filter_control_present_flag);
	w.flag(f.constrained_intra_pred_flag);
	w.flag(f.redundant_pic_cnt_present_flag);
	bool scaling = f.pic_scaling_matrix_present_flag && pps.pScalingLists;
	if (f.transform_8x8_mode_flag || scaling || pps.second_chroma_qp_index_offset != pps.chroma_qp_index_offset) {
		w.flag(f.transform_8x8_mode_flag);
		w.flag(scaling);
		if (scaling) {
			uint32_t lists8x8 = sps.chroma_format_idc != STD_VIDEO_H264_CHROMA_FORMAT_IDC_444 ? 2 : 6;
			mvkWriteH264ScalingLists(w, *pps.pScalingLists, 6 + (f.transform_8x8_mode_flag ? lists8x8 : 0));
		}
		w.se(pps.second_chroma_qp_index_offset);
	}
	return w.nal(0x68);
}


#pragma mark -
#pragma mark H.265 parameter set writer

static uint32_t mvkH265LevelIdc(StdVideoH265LevelIdc level) {
	static const uint8_t idc[] = { 30, 60, 63, 90, 93, 120, 123, 150, 153, 156, 180, 183, 186 };
	return uint32_t(level) < sizeof(idc) ? idc[level] : 186;
}

static vector<uint8_t> mvkH265Nal(MVKH264Writer& w, uint32_t type) {
	uint8_t header[2] = { uint8_t(type << 1), 1 };
	return w.nal(header, 2);
}

// general profile only: the std structure carries no sub-layer profiles
static void mvkWriteH265PTL(MVKH264Writer& w, const StdVideoH265ProfileTierLevel* pPTL,
							uint32_t maxSubLayersMinus1, uint32_t chromaIdc, uint32_t bitDepth) {
	uint32_t profile = pPTL ? uint32_t(pPTL->general_profile_idc) : uint32_t(STD_VIDEO_H265_PROFILE_IDC_MAIN);
	w.u(2, 0);
	w.flag(pPTL && pPTL->flags.general_tier_flag);
	w.u(5, profile);
	for (uint32_t j = 0; j < 32; j++) { w.flag(j == profile || (profile == 1 && j == 2)); }
	w.flag(pPTL ? pPTL->flags.general_progressive_source_flag : true);
	w.flag(pPTL && pPTL->flags.general_interlaced_source_flag);
	w.flag(pPTL && pPTL->flags.general_non_packed_constraint_flag);
	w.flag(pPTL ? pPTL->flags.general_frame_only_constraint_flag : true);
	if (profile == STD_VIDEO_H265_PROFILE_IDC_FORMAT_RANGE_EXTENSIONS) {
		// the range extensions profile is named by these constraints
		w.flag(bitDepth <= 12);
		w.flag(bitDepth <= 10);
		w.flag(bitDepth <= 8);
		w.flag(chromaIdc <= 2);
		w.flag(chromaIdc <= 1);
		w.flag(chromaIdc == 0);
		w.flag(false);			// general_intra_constraint_flag
		w.flag(false);			// general_one_picture_only_constraint_flag
		w.flag(true);			// general_lower_bit_rate_constraint_flag
		w.u(32, 0);
		w.u(2, 0);
	} else {
		w.u(32, 0);
		w.u(11, 0);
	}
	w.flag(false);				// general_inbld_flag
	w.u(8, pPTL ? mvkH265LevelIdc(pPTL->general_level_idc) : 93);
	for (uint32_t i = 0; i < maxSubLayersMinus1; i++) {
		w.flag(false);
		w.flag(false);
	}
	if (maxSubLayersMinus1 > 0) {
		for (uint32_t i = maxSubLayersMinus1; i < 8; i++) { w.u(2, 0); }
	}
}

static void mvkWriteH265Ordering(MVKH264Writer& w, const StdVideoH265DecPicBufMgr* pDpbm,
								 bool allLayers, uint32_t maxSubLayersMinus1) {
	w.flag(allLayers);
	for (uint32_t i = allLayers ? 0 : maxSubLayersMinus1; i <= maxSubLayersMinus1; i++) {
		w.ue(pDpbm ? pDpbm->max_dec_pic_buffering_minus1[i] : 4);
		w.ue(pDpbm ? pDpbm->max_num_reorder_pics[i] : 0);
		w.ue(pDpbm ? pDpbm->max_latency_increase_plus1[i] : 0);
	}
}

// every list coded explicitly, in the scan order the std keeps
static void mvkWriteH265ScalingLists(MVKH264Writer& w, const StdVideoH265ScalingLists& sl) {
	for (uint32_t sizeId = 0; sizeId < 4; sizeId++) {
		for (uint32_t matrixId = 0; matrixId < 6; matrixId += (sizeId == 3) ? 3 : 1) {
			w.flag(true);		// scaling_list_pred_mode_flag
			uint32_t mi = (sizeId == 3) ? matrixId / 3 : matrixId;
			const uint8_t* list = (sizeId == 0 ? sl.ScalingList4x4[mi] :
								   sizeId == 1 ? sl.ScalingList8x8[mi] :
								   sizeId == 2 ? sl.ScalingList16x16[mi] : sl.ScalingList32x32[mi]);
			uint32_t coefNum = (sizeId == 0) ? 16 : 64;
			int32_t next = 8;
			if (sizeId > 1) {
				int32_t dc = (sizeId == 2) ? sl.ScalingListDCCoef16x16[mi] : sl.ScalingListDCCoef32x32[mi];
				w.se(dc - 8);
				next = dc;
			}
			for (uint32_t i = 0; i < coefNum; i++) {
				int32_t delta = int32_t(list[i]) - next;
				if (delta > 127) { delta -= 256; }
				if (delta < -128) { delta += 256; }
				w.se(delta);
				next = list[i];
			}
		}
	}
}

// the delta POCs of each short-term set, as the decoder derives them
struct MVKH265RpsDeltas {
	int32_t s0[STD_VIDEO_H265_MAX_DPB_SIZE * 2];
	int32_t s1[STD_VIDEO_H265_MAX_DPB_SIZE * 2];
	uint32_t numNeg;
	uint32_t numPos;
};

static void mvkWriteH265StRps(MVKH264Writer& w, const StdVideoH265ShortTermRefPicSet* sets,
							  uint32_t idx, MVKH265RpsDeltas* deltas) {
	const auto& rps = sets[idx];
	auto& d = deltas[idx];
	d.numNeg = d.numPos = 0;
	bool inter = idx != 0 && rps.flags.inter_ref_pic_set_prediction_flag;
	if (idx != 0) { w.flag(inter); }
	if (inter) {
		// in the SPS the reference is always the set before
		const auto& ref = deltas[idx - 1];
		uint32_t numDelta = ref.numNeg + ref.numPos;
		int32_t deltaRps = (rps.flags.delta_rps_sign ? -1 : 1) * (int32_t(rps.abs_delta_rps_minus1) + 1);
		w.flag(rps.flags.delta_rps_sign);
		w.ue(rps.abs_delta_rps_minus1);
		bool used[33], useDelta[33];
		for (uint32_t j = 0; j <= numDelta; j++) {
			used[j] = (rps.used_by_curr_pic_flag >> j) & 1;
			useDelta[j] = used[j] || ((rps.use_delta_flag >> j) & 1);
			w.flag(used[j]);
			if ( !used[j] ) { w.flag(useDelta[j]); }
		}
		for (int32_t j = int32_t(ref.numPos) - 1; j >= 0; j--) {
			int32_t poc = ref.s1[j] + deltaRps;
			if (poc < 0 && useDelta[ref.numNeg + j]) { d.s0[d.numNeg++] = poc; }
		}
		if (deltaRps < 0 && useDelta[numDelta]) { d.s0[d.numNeg++] = deltaRps; }
		for (uint32_t j = 0; j < ref.numNeg; j++) {
			int32_t poc = ref.s0[j] + deltaRps;
			if (poc < 0 && useDelta[j]) { d.s0[d.numNeg++] = poc; }
		}
		for (int32_t j = int32_t(ref.numNeg) - 1; j >= 0; j--) {
			int32_t poc = ref.s0[j] + deltaRps;
			if (poc > 0 && useDelta[j]) { d.s1[d.numPos++] = poc; }
		}
		if (deltaRps > 0 && useDelta[numDelta]) { d.s1[d.numPos++] = deltaRps; }
		for (uint32_t j = 0; j < ref.numPos; j++) {
			int32_t poc = ref.s1[j] + deltaRps;
			if (poc > 0 && useDelta[ref.numNeg + j]) { d.s1[d.numPos++] = poc; }
		}
		return;
	}
	w.ue(rps.num_negative_pics);
	w.ue(rps.num_positive_pics);
	int32_t poc = 0;
	for (uint32_t i = 0; i < rps.num_negative_pics; i++) {
		w.ue(rps.delta_poc_s0_minus1[i]);
		w.flag((rps.used_by_curr_pic_s0_flag >> i) & 1);
		poc -= int32_t(rps.delta_poc_s0_minus1[i]) + 1;
		d.s0[d.numNeg++] = poc;
	}
	poc = 0;
	for (uint32_t i = 0; i < rps.num_positive_pics; i++) {
		w.ue(rps.delta_poc_s1_minus1[i]);
		w.flag((rps.used_by_curr_pic_s1_flag >> i) & 1);
		poc += int32_t(rps.delta_poc_s1_minus1[i]) + 1;
		d.s1[d.numPos++] = poc;
	}
}

// the VUI without its HRD: decoding needs no buffering model
static void mvkWriteH265Vui(MVKH264Writer& w, const StdVideoH265SequenceParameterSetVui& vui) {
	const auto& f = vui.flags;
	w.flag(f.aspect_ratio_info_present_flag);
	if (f.aspect_ratio_info_present_flag) {
		w.u(8, vui.aspect_ratio_idc);
		if (vui.aspect_ratio_idc == STD_VIDEO_H265_ASPECT_RATIO_IDC_EXTENDED_SAR) {
			w.u(16, vui.sar_width);
			w.u(16, vui.sar_height);
		}
	}
	w.flag(f.overscan_info_present_flag);
	if (f.overscan_info_present_flag) { w.flag(f.overscan_appropriate_flag); }
	w.flag(f.video_signal_type_present_flag);
	if (f.video_signal_type_present_flag) {
		w.u(3, vui.video_format);
		w.flag(f.video_full_range_flag);
		w.flag(f.colour_description_present_flag);
		if (f.colour_description_present_flag) {
			w.u(8, vui.colour_primaries);
			w.u(8, vui.transfer_characteristics);
			w.u(8, vui.matrix_coeffs);
		}
	}
	w.flag(f.chroma_loc_info_present_flag);
	if (f.chroma_loc_info_present_flag) {
		w.ue(vui.chroma_sample_loc_type_top_field);
		w.ue(vui.chroma_sample_loc_type_bottom_field);
	}
	w.flag(f.neutral_chroma_indication_flag);
	w.flag(f.field_seq_flag);
	w.flag(f.frame_field_info_present_flag);
	w.flag(f.default_display_window_flag);
	if (f.default_display_window_flag) {
		w.ue(vui.def_disp_win_left_offset);
		w.ue(vui.def_disp_win_right_offset);
		w.ue(vui.def_disp_win_top_offset);
		w.ue(vui.def_disp_win_bottom_offset);
	}
	w.flag(f.vui_timing_info_present_flag);
	if (f.vui_timing_info_present_flag) {
		w.u(32, vui.vui_num_units_in_tick);
		w.u(32, vui.vui_time_scale);
		w.flag(f.vui_poc_proportional_to_timing_flag);
		if (f.vui_poc_proportional_to_timing_flag) { w.ue(vui.vui_num_ticks_poc_diff_one_minus1); }
		w.flag(false);		// vui_hrd_parameters_present_flag
	}
	w.flag(f.bitstream_restriction_flag);
	if (f.bitstream_restriction_flag) {
		w.flag(f.tiles_fixed_structure_flag);
		w.flag(f.motion_vectors_over_pic_boundaries_flag);
		w.flag(f.restricted_ref_pic_lists_flag);
		w.ue(vui.min_spatial_segmentation_idc);
		w.ue(vui.max_bytes_per_pic_denom);
		w.ue(vui.max_bits_per_min_cu_denom);
		w.ue(vui.log2_max_mv_length_horizontal);
		w.ue(vui.log2_max_mv_length_vertical);
	}
}

static vector<uint8_t> mvkWriteH265VPS(const StdVideoH265VideoParameterSet& vps, const StdVideoH265SequenceParameterSet& sps) {
	MVKH264Writer w;
	const auto& f = vps.flags;
	w.u(4, vps.vps_video_parameter_set_id);
	w.flag(true);				// vps_base_layer_internal_flag
	w.flag(true);				// vps_base_layer_available_flag
	w.u(6, 0);					// vps_max_layers_minus1
	w.u(3, vps.vps_max_sub_layers_minus1);
	w.flag(f.vps_temporal_id_nesting_flag);
	w.u(16, 0xFFFF);
	mvkWriteH265PTL(w, vps.pProfileTierLevel ? vps.pProfileTierLevel : sps.pProfileTierLevel,
					vps.vps_max_sub_layers_minus1, sps.chroma_format_idc, sps.bit_depth_luma_minus8 + 8);
	mvkWriteH265Ordering(w, vps.pDecPicBufMgr ? vps.pDecPicBufMgr : sps.pDecPicBufMgr,
						 f.vps_sub_layer_ordering_info_present_flag, vps.vps_max_sub_layers_minus1);
	w.u(6, 0);					// vps_max_layer_id
	w.ue(0);					// vps_num_layer_sets_minus1
	w.flag(f.vps_timing_info_present_flag);
	if (f.vps_timing_info_present_flag) {
		w.u(32, vps.vps_num_units_in_tick);
		w.u(32, vps.vps_time_scale);
		w.flag(f.vps_poc_proportional_to_timing_flag);
		if (f.vps_poc_proportional_to_timing_flag) { w.ue(vps.vps_num_ticks_poc_diff_one_minus1); }
		w.ue(0);				// vps_num_hrd_parameters
	}
	w.flag(false);				// vps_extension_flag
	return mvkH265Nal(w, 32);
}

static vector<uint8_t> mvkWriteH265SPS(const StdVideoH265SequenceParameterSet& sps) {
	MVKH264Writer w;
	const auto& f = sps.flags;
	w.u(4, sps.sps_video_parameter_set_id);
	w.u(3, sps.sps_max_sub_layers_minus1);
	w.flag(f.sps_temporal_id_nesting_flag);
	mvkWriteH265PTL(w, sps.pProfileTierLevel, sps.sps_max_sub_layers_minus1,
					sps.chroma_format_idc, sps.bit_depth_luma_minus8 + 8);
	w.ue(sps.sps_seq_parameter_set_id);
	w.ue(sps.chroma_format_idc);
	if (sps.chroma_format_idc == STD_VIDEO_H265_CHROMA_FORMAT_IDC_444) { w.flag(f.separate_colour_plane_flag); }
	w.ue(sps.pic_width_in_luma_samples);
	w.ue(sps.pic_height_in_luma_samples);
	w.flag(f.conformance_window_flag);
	if (f.conformance_window_flag) {
		w.ue(sps.conf_win_left_offset);
		w.ue(sps.conf_win_right_offset);
		w.ue(sps.conf_win_top_offset);
		w.ue(sps.conf_win_bottom_offset);
	}
	w.ue(sps.bit_depth_luma_minus8);
	w.ue(sps.bit_depth_chroma_minus8);
	w.ue(sps.log2_max_pic_order_cnt_lsb_minus4);
	mvkWriteH265Ordering(w, sps.pDecPicBufMgr, f.sps_sub_layer_ordering_info_present_flag, sps.sps_max_sub_layers_minus1);
	w.ue(sps.log2_min_luma_coding_block_size_minus3);
	w.ue(sps.log2_diff_max_min_luma_coding_block_size);
	w.ue(sps.log2_min_luma_transform_block_size_minus2);
	w.ue(sps.log2_diff_max_min_luma_transform_block_size);
	w.ue(sps.max_transform_hierarchy_depth_inter);
	w.ue(sps.max_transform_hierarchy_depth_intra);
	w.flag(f.scaling_list_enabled_flag);
	if (f.scaling_list_enabled_flag) {
		bool data = f.sps_scaling_list_data_present_flag && sps.pScalingLists;
		w.flag(data);
		if (data) { mvkWriteH265ScalingLists(w, *sps.pScalingLists); }
	}
	w.flag(f.amp_enabled_flag);
	w.flag(f.sample_adaptive_offset_enabled_flag);
	w.flag(f.pcm_enabled_flag);
	if (f.pcm_enabled_flag) {
		w.u(4, sps.pcm_sample_bit_depth_luma_minus1);
		w.u(4, sps.pcm_sample_bit_depth_chroma_minus1);
		w.ue(sps.log2_min_pcm_luma_coding_block_size_minus3);
		w.ue(sps.log2_diff_max_min_pcm_luma_coding_block_size);
		w.flag(f.pcm_loop_filter_disabled_flag);
	}
	uint32_t numSets = sps.pShortTermRefPicSet ? sps.num_short_term_ref_pic_sets : 0;
	w.ue(numSets);
	vector<MVKH265RpsDeltas> deltas(numSets ? numSets : 1);
	for (uint32_t i = 0; i < numSets; i++) { mvkWriteH265StRps(w, sps.pShortTermRefPicSet, i, deltas.data()); }
	bool lt = f.long_term_ref_pics_present_flag;
	w.flag(lt);
	if (lt) {
		uint32_t numLt = sps.pLongTermRefPicsSps ? sps.num_long_term_ref_pics_sps : 0;
		w.ue(numLt);
		for (uint32_t i = 0; i < numLt; i++) {
			w.u(sps.log2_max_pic_order_cnt_lsb_minus4 + 4, sps.pLongTermRefPicsSps->lt_ref_pic_poc_lsb_sps[i]);
			w.flag((sps.pLongTermRefPicsSps->used_by_curr_pic_lt_sps_flag >> i) & 1);
		}
	}
	w.flag(f.sps_temporal_mvp_enabled_flag);
	w.flag(f.strong_intra_smoothing_enabled_flag);
	const auto* pVui = f.vui_parameters_present_flag ? sps.pSequenceParameterSetVui : nullptr;
	w.flag(pVui != nullptr);
	if (pVui) { mvkWriteH265Vui(w, *pVui); }
	bool range = f.sps_extension_present_flag && f.sps_range_extension_flag;
	w.flag(range);
	if (range) {
		w.flag(true);			// sps_range_extension_flag
		w.flag(false);			// sps_multilayer_extension_flag
		w.flag(false);			// sps_3d_extension_flag
		w.flag(false);			// sps_scc_extension_flag
		w.u(4, 0);
		w.flag(f.transform_skip_rotation_enabled_flag);
		w.flag(f.transform_skip_context_enabled_flag);
		w.flag(f.implicit_rdpcm_enabled_flag);
		w.flag(f.explicit_rdpcm_enabled_flag);
		w.flag(f.extended_precision_processing_flag);
		w.flag(f.intra_smoothing_disabled_flag);
		w.flag(f.high_precision_offsets_enabled_flag);
		w.flag(f.persistent_rice_adaptation_enabled_flag);
		w.flag(f.cabac_bypass_alignment_enabled_flag);
	}
	return mvkH265Nal(w, 33);
}

static vector<uint8_t> mvkWriteH265PPS(const StdVideoH265PictureParameterSet& pps) {
	MVKH264Writer w;
	const auto& f = pps.flags;
	w.ue(pps.pps_pic_parameter_set_id);
	w.ue(pps.pps_seq_parameter_set_id);
	w.flag(f.dependent_slice_segments_enabled_flag);
	w.flag(f.output_flag_present_flag);
	w.u(3, pps.num_extra_slice_header_bits);
	w.flag(f.sign_data_hiding_enabled_flag);
	w.flag(f.cabac_init_present_flag);
	w.ue(pps.num_ref_idx_l0_default_active_minus1);
	w.ue(pps.num_ref_idx_l1_default_active_minus1);
	w.se(pps.init_qp_minus26);
	w.flag(f.constrained_intra_pred_flag);
	w.flag(f.transform_skip_enabled_flag);
	w.flag(f.cu_qp_delta_enabled_flag);
	if (f.cu_qp_delta_enabled_flag) { w.ue(pps.diff_cu_qp_delta_depth); }
	w.se(pps.pps_cb_qp_offset);
	w.se(pps.pps_cr_qp_offset);
	w.flag(f.pps_slice_chroma_qp_offsets_present_flag);
	w.flag(f.weighted_pred_flag);
	w.flag(f.weighted_bipred_flag);
	w.flag(f.transquant_bypass_enabled_flag);
	w.flag(f.tiles_enabled_flag);
	w.flag(f.entropy_coding_sync_enabled_flag);
	if (f.tiles_enabled_flag) {
		w.ue(pps.num_tile_columns_minus1);
		w.ue(pps.num_tile_rows_minus1);
		w.flag(f.uniform_spacing_flag);
		if ( !f.uniform_spacing_flag ) {
			for (uint32_t i = 0; i < pps.num_tile_columns_minus1; i++) { w.ue(pps.column_width_minus1[i]); }
			for (uint32_t i = 0; i < pps.num_tile_rows_minus1; i++) { w.ue(pps.row_height_minus1[i]); }
		}
		w.flag(f.loop_filter_across_tiles_enabled_flag);
	}
	w.flag(f.pps_loop_filter_across_slices_enabled_flag);
	w.flag(f.deblocking_filter_control_present_flag);
	if (f.deblocking_filter_control_present_flag) {
		w.flag(f.deblocking_filter_override_enabled_flag);
		w.flag(f.pps_deblocking_filter_disabled_flag);
		if ( !f.pps_deblocking_filter_disabled_flag ) {
			w.se(pps.pps_beta_offset_div2);
			w.se(pps.pps_tc_offset_div2);
		}
	}
	bool data = f.pps_scaling_list_data_present_flag && pps.pScalingLists;
	w.flag(data);
	if (data) { mvkWriteH265ScalingLists(w, *pps.pScalingLists); }
	w.flag(f.lists_modification_present_flag);
	w.ue(pps.log2_parallel_merge_level_minus2);
	w.flag(f.slice_segment_header_extension_present_flag);
	bool range = f.pps_extension_present_flag && f.pps_range_extension_flag;
	w.flag(range);
	if (range) {
		w.flag(true);			// pps_range_extension_flag
		w.flag(false);			// pps_multilayer_extension_flag
		w.flag(false);			// pps_3d_extension_flag
		w.flag(false);			// pps_scc_extension_flag
		w.u(4, 0);
		if (f.transform_skip_enabled_flag) { w.ue(pps.log2_max_transform_skip_block_size_minus2); }
		w.flag(f.cross_component_prediction_enabled_flag);
		w.flag(f.chroma_qp_offset_list_enabled_flag);
		if (f.chroma_qp_offset_list_enabled_flag) {
			w.ue(pps.diff_cu_chroma_qp_offset_depth);
			w.ue(pps.chroma_qp_offset_list_len_minus1);
			for (uint32_t i = 0; i <= pps.chroma_qp_offset_list_len_minus1; i++) {
				w.se(pps.cb_qp_offset_list[i]);
				w.se(pps.cr_qp_offset_list[i]);
			}
		}
		w.ue(pps.log2_sao_offset_scale_luma);
		w.ue(pps.log2_sao_offset_scale_chroma);
	}
	return mvkH265Nal(w, 34);
}


#pragma mark -
#pragma mark MVKVideoSession decode

// called with _lock held
VkResult MVKVideoSession::prepareDecoder(const vector<vector<uint8_t>>& sets, bool fullRange) {
	if (_vtDecoder && sets == _decodeSets) { return VK_SUCCESS; }

	@autoreleasepool {
		vector<const uint8_t*> ptrs;
		vector<size_t> sizes;
		for (auto& set : sets) { ptrs.push_back(set.data()); sizes.push_back(set.size()); }
		CMVideoFormatDescriptionRef fmt = nullptr;
		OSStatus st = (_hevc
					   ? CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault, ptrs.size(), ptrs.data(),
																			   sizes.data(), 4, nullptr, &fmt)
					   : CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, ptrs.size(), ptrs.data(),
																			   sizes.data(), 4, &fmt));
		if (st != noErr || !fmt) {
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCmdDecodeVideoKHR(): VideoToolbox rejected the parameter sets (%d).", (int)st);
		}

		OSType pixelFormat = pixelFormatFor(fullRange);
		if (_vtDecoder && _pixelFormat == pixelFormat && VTDecompressionSessionCanAcceptFormatDescription(_vtDecoder, fmt)) {
			CFRelease(_decodeFormat);
			_decodeFormat = fmt;
		} else {
			destroyDecoder();
			NSMutableDictionary* spec = [NSMutableDictionary dictionary];
#if MVK_MACOS
			spec[(NSString*)kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder] = @YES;
#endif
			NSDictionary* destAttrs = @{
				(NSString*)kCVPixelBufferPixelFormatTypeKey: @(pixelFormat),
				(NSString*)kCVPixelBufferIOSurfacePropertiesKey: @{},
				(NSString*)kCVPixelBufferMetalCompatibilityKey: @YES,
			};
			st = VTDecompressionSessionCreate(kCFAllocatorDefault, fmt, (CFDictionaryRef)spec,
											  (CFDictionaryRef)destAttrs, nullptr, &_vtDecoder);
			if (st != noErr || !_vtDecoder) {
				CFRelease(fmt);
				_vtDecoder = nullptr;
				return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCmdDecodeVideoKHR(): VideoToolbox could not create an %s decoder (%d).",
								   _hevc ? "H.265" : "H.264", (int)st);
			}
			_decodeFormat = fmt;
			_pixelFormat = pixelFormat;
			if ( !_textureCache ) {
				CVMetalTextureCacheCreate(kCFAllocatorDefault, nullptr, getMTLDevice(), nullptr, &_textureCache);
			}
		}
		_decodeSets = sets;
		return VK_SUCCESS;
	}
}

void MVKVideoSession::destroyDecoder() {
	if (_vtDecoder) {
		VTDecompressionSessionWaitForAsynchronousFrames(_vtDecoder);
		VTDecompressionSessionInvalidate(_vtDecoder);
		CFRelease(_vtDecoder);
		_vtDecoder = nullptr;
	}
	if (_decodeFormat) { CFRelease(_decodeFormat); _decodeFormat = nullptr; }
	_decodeSets.clear();
}

VkResult MVKVideoSession::decodeFrame(const StdVideoH264SequenceParameterSet* pSPS,
									  const StdVideoH264PictureParameterSet* pPPS,
									  const uint8_t* data, size_t size,
									  const uint32_t* pSliceOffsets, uint32_t sliceCount,
									  CVPixelBufferRef* pPixelBuffer) {
	*pPixelBuffer = nullptr;
	if ( !pSPS || !pPPS || !data ) {
		return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCmdDecodeVideoKHR(): the picture names an SPS or PPS the parameters lack.");
	}
	const auto* pVui = pSPS->flags.vui_parameters_present_flag ? pSPS->pSequenceParameterSetVui : nullptr;
	bool fullRange = pVui && pVui->flags.video_signal_type_present_flag && pVui->flags.video_full_range_flag;
	vector<vector<uint8_t>> sets = { mvkWriteH264SPS(*pSPS), mvkWriteH264PPS(*pSPS, *pPPS) };
	return decodeSample(sets, fullRange, data, size, pSliceOffsets, sliceCount, pPixelBuffer);
}

VkResult MVKVideoSession::decodeFrameH265(const StdVideoH265VideoParameterSet* pVPS,
										  const StdVideoH265SequenceParameterSet* pSPS,
										  const StdVideoH265PictureParameterSet* pPPS,
										  const uint8_t* data, size_t size,
										  const uint32_t* pSliceOffsets, uint32_t sliceCount,
										  CVPixelBufferRef* pPixelBuffer) {
	*pPixelBuffer = nullptr;
	if ( !pVPS || !pSPS || !pPPS || !data ) {
		return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCmdDecodeVideoKHR(): the picture names a VPS, SPS or PPS the parameters lack.");
	}
	const auto* pVui = pSPS->flags.vui_parameters_present_flag ? pSPS->pSequenceParameterSetVui : nullptr;
	bool fullRange = pVui && pVui->flags.video_signal_type_present_flag && pVui->flags.video_full_range_flag;
	vector<vector<uint8_t>> sets = { mvkWriteH265VPS(*pVPS, *pSPS), mvkWriteH265SPS(*pSPS), mvkWriteH265PPS(*pPPS) };
	return decodeSample(sets, fullRange, data, size, pSliceOffsets, sliceCount, pPixelBuffer);
}

VkResult MVKVideoSession::decodeSample(const vector<vector<uint8_t>>& sets, bool fullRange,
									   const uint8_t* data, size_t size,
									   const uint32_t* pSliceOffsets, uint32_t sliceCount,
									   CVPixelBufferRef* pPixelBuffer) {
	// each slice loses its start code and gains a length
	vector<uint8_t> sample;
	for (uint32_t i = 0; i < sliceCount; i++) {
		size_t start = pSliceOffsets[i];
		size_t end = (i + 1 < sliceCount) ? pSliceOffsets[i + 1] : size;
		if (start >= end || end > size) { continue; }
		const uint8_t* nal = data + start;
		size_t n = end - start;
		while (n && *nal == 0) { nal++; n--; }
		if (n && *nal == 1) { nal++; n--; }
		while (n && nal[n - 1] == 0) { n--; }
		if ( !n ) { continue; }
		uint8_t len[4] = { uint8_t(n >> 24), uint8_t(n >> 16), uint8_t(n >> 8), uint8_t(n) };
		sample.insert(sample.end(), len, len + 4);
		sample.insert(sample.end(), nal, nal + n);
	}
	if (sample.empty()) {
		return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCmdDecodeVideoKHR(): the bitstream holds no slices.");
	}

	lock_guard<mutex> lock(_lock);
	VkResult rslt = prepareDecoder(sets, fullRange);
	if (rslt != VK_SUCCESS) { return rslt; }

	@autoreleasepool {
		CMBlockBufferRef bb = nullptr;
		OSStatus st = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, nullptr, sample.size(), kCFAllocatorDefault,
														 nullptr, 0, sample.size(), kCMBlockBufferAssureMemoryNowFlag, &bb);
		if (st == kCMBlockBufferNoErr) { st = CMBlockBufferReplaceDataBytes(sample.data(), bb, 0, sample.size()); }
		CMSampleBufferRef sb = nullptr;
		size_t sampleSize = sample.size();
		if (st == noErr) {
			st = CMSampleBufferCreateReady(kCFAllocatorDefault, bb, _decodeFormat, 1, 0, nullptr, 1, &sampleSize, &sb);
		}

		// no temporal processing: pictures come out in decode order
		__block CVPixelBufferRef out = nullptr;
		__block OSStatus decStatus = noErr;
		if (st == noErr) {
			st = VTDecompressionSessionDecodeFrameWithOutputHandler(_vtDecoder, sb, 0, nullptr,
																	^(OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef image,
																	  CMTime pts, CMTime duration) {
				decStatus = status;
				if (status == noErr && image && !out) { out = CVPixelBufferRetain(image); }
			});
			VTDecompressionSessionWaitForAsynchronousFrames(_vtDecoder);
		}
		if (sb) { CFRelease(sb); }
		if (bb) { CFRelease(bb); }
		if (st != noErr || decStatus != noErr || !out) {
			if (out) { CVPixelBufferRelease(out); }
			return reportError(VK_ERROR_INITIALIZATION_FAILED, "vkCmdDecodeVideoKHR(): VideoToolbox could not decode the picture (%d, %d).", (int)st, (int)decStatus);
		}
		*pPixelBuffer = out;
		return VK_SUCCESS;
	}
}


#pragma mark -
#pragma mark MVKVideoSessionParameters

VkResult MVKVideoSessionParameters::add(uint32_t spsCount, const StdVideoH264SequenceParameterSet* pSPSs,
										uint32_t ppsCount, const StdVideoH264PictureParameterSet* pPPSs) {
	for (uint32_t i = 0; i < spsCount; i++) {
		SPSEntry entry = {};
		entry.sps = pSPSs[i];
		const auto* pVui = entry.sps.pSequenceParameterSetVui;
		entry.hasVui = entry.sps.flags.vui_parameters_present_flag && pVui;
		if (entry.hasVui) {
			entry.vui = *pVui;
			entry.hasHrd = pVui->pHrdParameters != nullptr;
			if (entry.hasHrd) { entry.hrd = *pVui->pHrdParameters; }
		}
		entry.hasScalingLists = entry.sps.pScalingLists != nullptr;
		if (entry.hasScalingLists) { entry.scalingLists = *entry.sps.pScalingLists; }
		if (entry.sps.pOffsetForRefFrame) {
			uint32_t count = min<uint32_t>(entry.sps.num_ref_frames_in_pic_order_cnt_cycle, 255);
			memcpy(entry.offsetForRefFrame, entry.sps.pOffsetForRefFrame, count * sizeof(int32_t));
		}
		// the copy keeps none of the app's pointers
		entry.vui.pHrdParameters = nullptr;
		entry.sps.pSequenceParameterSetVui = nullptr;
		entry.sps.pOffsetForRefFrame = nullptr;
		entry.sps.pScalingLists = nullptr;
		bool replaced = false;
		for (auto& existing : _spsList) {
			if (existing.sps.seq_parameter_set_id == entry.sps.seq_parameter_set_id) { existing = entry; replaced = true; }
		}
		if ( !replaced ) {
			if (_spsList.size() >= _maxSPSCount) { return VK_ERROR_TOO_MANY_OBJECTS; }
			_spsList.push_back(entry);
		}
	}
	for (uint32_t i = 0; i < ppsCount; i++) {
		PPSEntry entry = {};
		entry.pps = pPPSs[i];
		entry.hasScalingLists = entry.pps.pScalingLists != nullptr;
		if (entry.hasScalingLists) { entry.scalingLists = *entry.pps.pScalingLists; }
		entry.pps.pScalingLists = nullptr;
		bool replaced = false;
		for (auto& existing : _ppsList) {
			if (existing.pps.seq_parameter_set_id == entry.pps.seq_parameter_set_id &&
				existing.pps.pic_parameter_set_id == entry.pps.pic_parameter_set_id) { existing = entry; replaced = true; }
		}
		if ( !replaced ) {
			if (_ppsList.size() >= _maxPPSCount) { return VK_ERROR_TOO_MANY_OBJECTS; }
			_ppsList.push_back(entry);
		}
	}
	return VK_SUCCESS;
}

VkResult MVKVideoSessionParameters::update(const VkVideoSessionParametersUpdateInfoKHR* pUpdateInfo) {
	if (pUpdateInfo->updateSequenceCount != _updateSequenceCount + 1) {
		return reportError(VK_ERROR_VALIDATION_FAILED_EXT, "vkUpdateVideoSessionParametersKHR(): updateSequenceCount must be %u.", _updateSequenceCount + 1);
	}
	_updateSequenceCount = pUpdateInfo->updateSequenceCount;
	for (const auto* next = (VkBaseInStructure*)pUpdateInfo->pNext; next; next = next->pNext) {
		VkResult rslt = VK_SUCCESS;
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H264_SESSION_PARAMETERS_ADD_INFO_KHR) {
			auto* pAdd = (const VkVideoEncodeH264SessionParametersAddInfoKHR*)next;
			rslt = add(pAdd->stdSPSCount, pAdd->pStdSPSs, pAdd->stdPPSCount, pAdd->pStdPPSs);
		} else if (next->sType == VK_STRUCTURE_TYPE_VIDEO_DECODE_H264_SESSION_PARAMETERS_ADD_INFO_KHR) {
			auto* pAdd = (const VkVideoDecodeH264SessionParametersAddInfoKHR*)next;
			rslt = add(pAdd->stdSPSCount, pAdd->pStdSPSs, pAdd->stdPPSCount, pAdd->pStdPPSs);
		} else if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H265_SESSION_PARAMETERS_ADD_INFO_KHR) {
			auto* pAdd = (const VkVideoEncodeH265SessionParametersAddInfoKHR*)next;
			rslt = addH265(pAdd->stdVPSCount, pAdd->pStdVPSs, pAdd->stdSPSCount, pAdd->pStdSPSs, pAdd->stdPPSCount, pAdd->pStdPPSs);
		} else if (next->sType == VK_STRUCTURE_TYPE_VIDEO_DECODE_H265_SESSION_PARAMETERS_ADD_INFO_KHR) {
			auto* pAdd = (const VkVideoDecodeH265SessionParametersAddInfoKHR*)next;
			rslt = addH265(pAdd->stdVPSCount, pAdd->pStdVPSs, pAdd->stdSPSCount, pAdd->pStdSPSs, pAdd->stdPPSCount, pAdd->pStdPPSs);
		}
		if (rslt != VK_SUCCESS) { return rslt; }
	}
	return VK_SUCCESS;
}

VkResult MVKVideoSessionParameters::addH265(uint32_t vpsCount, const StdVideoH265VideoParameterSet* pVPSs,
											uint32_t spsCount, const StdVideoH265SequenceParameterSet* pSPSs,
											uint32_t ppsCount, const StdVideoH265PictureParameterSet* pPPSs) {
	for (uint32_t i = 0; i < vpsCount; i++) {
		H265VPSEntry e = {};
		e.vps = pVPSs[i];
		e.hasPtl = e.vps.pProfileTierLevel != nullptr;
		if (e.hasPtl) { e.ptl = *e.vps.pProfileTierLevel; }
		e.hasDpbm = e.vps.pDecPicBufMgr != nullptr;
		if (e.hasDpbm) { e.dpbm = *e.vps.pDecPicBufMgr; }
		e.vps.pProfileTierLevel = nullptr;
		e.vps.pDecPicBufMgr = nullptr;
		e.vps.pHrdParameters = nullptr;
		bool replaced = false;
		for (auto& x : _h265VpsList) {
			if (x.vps.vps_video_parameter_set_id == e.vps.vps_video_parameter_set_id) { x = e; replaced = true; }
		}
		if ( !replaced ) {
			if (_h265VpsList.size() >= _maxVPSCount) { return VK_ERROR_TOO_MANY_OBJECTS; }
			_h265VpsList.push_back(e);
		}
	}
	for (uint32_t i = 0; i < spsCount; i++) {
		H265SPSEntry e = {};
		e.sps = pSPSs[i];
		const auto& src = pSPSs[i];
		e.hasPtl = src.pProfileTierLevel != nullptr;
		if (e.hasPtl) { e.ptl = *src.pProfileTierLevel; }
		e.hasDpbm = src.pDecPicBufMgr != nullptr;
		if (e.hasDpbm) { e.dpbm = *src.pDecPicBufMgr; }
		e.hasScalingLists = src.pScalingLists != nullptr;
		if (e.hasScalingLists) { e.scalingLists = *src.pScalingLists; }
		e.hasStRps = src.pShortTermRefPicSet != nullptr;
		if (e.hasStRps) {
			uint32_t n = min<uint32_t>(src.num_short_term_ref_pic_sets, STD_VIDEO_H265_MAX_SHORT_TERM_REF_PIC_SETS);
			memcpy(e.stRps, src.pShortTermRefPicSet, n * sizeof(StdVideoH265ShortTermRefPicSet));
		}
		e.hasLtRps = src.pLongTermRefPicsSps != nullptr;
		if (e.hasLtRps) { e.ltRps = *src.pLongTermRefPicsSps; }
		e.hasVui = src.flags.vui_parameters_present_flag && src.pSequenceParameterSetVui;
		if (e.hasVui) { e.vui = *src.pSequenceParameterSetVui; }
		// the copy keeps none of the app's pointers
		e.vui.pHrdParameters = nullptr;
		e.sps.pProfileTierLevel = nullptr;
		e.sps.pDecPicBufMgr = nullptr;
		e.sps.pScalingLists = nullptr;
		e.sps.pShortTermRefPicSet = nullptr;
		e.sps.pLongTermRefPicsSps = nullptr;
		e.sps.pSequenceParameterSetVui = nullptr;
		e.sps.pPredictorPaletteEntries = nullptr;
		bool replaced = false;
		for (auto& x : _h265SpsList) {
			if (x.sps.sps_video_parameter_set_id == e.sps.sps_video_parameter_set_id &&
				x.sps.sps_seq_parameter_set_id == e.sps.sps_seq_parameter_set_id) { x = e; replaced = true; }
		}
		if ( !replaced ) {
			if (_h265SpsList.size() >= _maxSPSCount) { return VK_ERROR_TOO_MANY_OBJECTS; }
			_h265SpsList.push_back(e);
		}
	}
	for (uint32_t i = 0; i < ppsCount; i++) {
		H265PPSEntry e = {};
		e.pps = pPPSs[i];
		e.hasScalingLists = e.pps.pScalingLists != nullptr;
		if (e.hasScalingLists) { e.scalingLists = *e.pps.pScalingLists; }
		e.pps.pScalingLists = nullptr;
		e.pps.pPredictorPaletteEntries = nullptr;
		bool replaced = false;
		for (auto& x : _h265PpsList) {
			if (x.pps.sps_video_parameter_set_id == e.pps.sps_video_parameter_set_id &&
				x.pps.pps_seq_parameter_set_id == e.pps.pps_seq_parameter_set_id &&
				x.pps.pps_pic_parameter_set_id == e.pps.pps_pic_parameter_set_id) { x = e; replaced = true; }
		}
		if ( !replaced ) {
			if (_h265PpsList.size() >= _maxPPSCount) { return VK_ERROR_TOO_MANY_OBJECTS; }
			_h265PpsList.push_back(e);
		}
	}
	return VK_SUCCESS;
}

const StdVideoH265VideoParameterSet* MVKVideoSessionParameters::getH265VPS(uint8_t vpsId) const {
	for (auto& entry : _h265VpsList) {
		if (entry.vps.vps_video_parameter_set_id == vpsId) {
			auto& e = const_cast<H265VPSEntry&>(entry);
			e.vps.pProfileTierLevel = e.hasPtl ? &e.ptl : nullptr;
			e.vps.pDecPicBufMgr = e.hasDpbm ? &e.dpbm : nullptr;
			return &e.vps;
		}
	}
	return nullptr;
}

const StdVideoH265SequenceParameterSet* MVKVideoSessionParameters::getH265SPS(uint8_t vpsId, uint8_t spsId) const {
	for (auto& entry : _h265SpsList) {
		if (entry.sps.sps_video_parameter_set_id == vpsId && entry.sps.sps_seq_parameter_set_id == spsId) {
			auto& e = const_cast<H265SPSEntry&>(entry);
			e.sps.pProfileTierLevel = e.hasPtl ? &e.ptl : nullptr;
			e.sps.pDecPicBufMgr = e.hasDpbm ? &e.dpbm : nullptr;
			e.sps.pScalingLists = e.hasScalingLists ? &e.scalingLists : nullptr;
			e.sps.pShortTermRefPicSet = e.hasStRps ? e.stRps : nullptr;
			e.sps.pLongTermRefPicsSps = e.hasLtRps ? &e.ltRps : nullptr;
			e.sps.pSequenceParameterSetVui = e.hasVui ? &e.vui : nullptr;
			return &e.sps;
		}
	}
	return nullptr;
}

const StdVideoH265PictureParameterSet* MVKVideoSessionParameters::getH265PPS(uint8_t vpsId, uint8_t spsId, uint8_t ppsId) const {
	for (auto& entry : _h265PpsList) {
		if (entry.pps.sps_video_parameter_set_id == vpsId && entry.pps.pps_seq_parameter_set_id == spsId &&
			entry.pps.pps_pic_parameter_set_id == ppsId) {
			auto& e = const_cast<H265PPSEntry&>(entry);
			e.pps.pScalingLists = e.hasScalingLists ? &e.scalingLists : nullptr;
			return &e.pps;
		}
	}
	return nullptr;
}

// the pointers are set here, to this entry's own copies
const StdVideoH264SequenceParameterSet* MVKVideoSessionParameters::getSPS(uint8_t spsId) const {
	for (auto& entry : _spsList) {
		if (entry.sps.seq_parameter_set_id == spsId) {
			auto& e = const_cast<SPSEntry&>(entry);
			e.vui.pHrdParameters = e.hasHrd ? &e.hrd : nullptr;
			e.sps.pSequenceParameterSetVui = e.hasVui ? &e.vui : nullptr;
			e.sps.pScalingLists = e.hasScalingLists ? &e.scalingLists : nullptr;
			e.sps.pOffsetForRefFrame = e.offsetForRefFrame;
			return &e.sps;
		}
	}
	return nullptr;
}

const StdVideoH264PictureParameterSet* MVKVideoSessionParameters::getPPS(uint8_t spsId, uint8_t ppsId) const {
	for (auto& entry : _ppsList) {
		if (entry.pps.seq_parameter_set_id == spsId && entry.pps.pic_parameter_set_id == ppsId) {
			auto& e = const_cast<PPSEntry&>(entry);
			e.pps.pScalingLists = e.hasScalingLists ? &e.scalingLists : nullptr;
			return &e.pps;
		}
	}
	return nullptr;
}

VkResult MVKVideoSessionParameters::getEncoded(const VkVideoEncodeSessionParametersGetInfoKHR* pInfo,
											   VkVideoEncodeSessionParametersFeedbackInfoKHR* pFeedbackInfo,
											   size_t* pDataSize, void* pData) {
	if (_session->isHevc()) { return getEncodedH265(pInfo, pFeedbackInfo, pDataSize, pData); }
	const VkVideoEncodeH264SessionParametersGetInfoKHR* pH264Get = nullptr;
	for (const auto* next = (VkBaseInStructure*)pInfo->pNext; next; next = next->pNext) {
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H264_SESSION_PARAMETERS_GET_INFO_KHR) {
			pH264Get = (const VkVideoEncodeH264SessionParametersGetInfoKHR*)next;
		}
	}
	if ( !pH264Get ) { return reportError(VK_ERROR_VALIDATION_FAILED_EXT, "vkGetEncodedVideoSessionParametersKHR(): missing H.264 get info."); }

	const auto* pSPS = getSPS((uint8_t)pH264Get->stdSPSId);
	const auto* pPPS = getPPS((uint8_t)pH264Get->stdSPSId, (uint8_t)pH264Get->stdPPSId);
	if ( !pSPS ) { return reportError(VK_ERROR_VALIDATION_FAILED_EXT, "vkGetEncodedVideoSessionParametersKHR(): no SPS with id %u.", pH264Get->stdSPSId); }

	vector<uint8_t> sps, pps;
	VkResult rslt = _session->prepare(pSPS, pPPS, &sps, &pps);
	if (rslt != VK_SUCCESS) { return rslt; }

	// VideoToolbox writes its own parameter sets: report the override
	if (pFeedbackInfo) {
		pFeedbackInfo->hasOverrides = VK_TRUE;
		for (auto* next = (VkBaseOutStructure*)pFeedbackInfo->pNext; next; next = next->pNext) {
			if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H264_SESSION_PARAMETERS_FEEDBACK_INFO_KHR) {
				auto* pH264Feedback = (VkVideoEncodeH264SessionParametersFeedbackInfoKHR*)next;
				pH264Feedback->hasStdSPSOverrides = pH264Get->writeStdSPS;
				pH264Feedback->hasStdPPSOverrides = pH264Get->writeStdPPS;
			}
		}
	}

	size_t total = (pH264Get->writeStdSPS ? 4 + sps.size() : 0) + (pH264Get->writeStdPPS ? 4 + pps.size() : 0);
	if ( !pData ) {
		*pDataSize = total;
		return VK_SUCCESS;
	}
	if (*pDataSize < total) { return VK_INCOMPLETE; }
	uint8_t* dst = (uint8_t*)pData;
	static const uint8_t startCode[4] = { 0, 0, 0, 1 };
	if (pH264Get->writeStdSPS) {
		memcpy(dst, startCode, 4); memcpy(dst + 4, sps.data(), sps.size());
		dst += 4 + sps.size();
	}
	if (pH264Get->writeStdPPS) {
		memcpy(dst, startCode, 4); memcpy(dst + 4, pps.data(), pps.size());
	}
	*pDataSize = total;
	return VK_SUCCESS;
}

VkResult MVKVideoSessionParameters::getEncodedH265(const VkVideoEncodeSessionParametersGetInfoKHR* pInfo,
												   VkVideoEncodeSessionParametersFeedbackInfoKHR* pFeedbackInfo,
												   size_t* pDataSize, void* pData) {
	const VkVideoEncodeH265SessionParametersGetInfoKHR* pGet = nullptr;
	for (const auto* next = (VkBaseInStructure*)pInfo->pNext; next; next = next->pNext) {
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H265_SESSION_PARAMETERS_GET_INFO_KHR) {
			pGet = (const VkVideoEncodeH265SessionParametersGetInfoKHR*)next;
		}
	}
	if ( !pGet ) { return reportError(VK_ERROR_VALIDATION_FAILED_EXT, "vkGetEncodedVideoSessionParametersKHR(): missing H.265 get info."); }

	uint8_t vpsId = (uint8_t)pGet->stdVPSId, spsId = (uint8_t)pGet->stdSPSId, ppsId = (uint8_t)pGet->stdPPSId;
	const auto* pSPS = getH265SPS(vpsId, spsId);
	if ( !pSPS ) { return reportError(VK_ERROR_VALIDATION_FAILED_EXT, "vkGetEncodedVideoSessionParametersKHR(): no SPS with ids %u/%u.", vpsId, spsId); }

	vector<uint8_t> vps, sps, pps;
	VkResult rslt = _session->prepareH265(getH265VPS(vpsId), pSPS, getH265PPS(vpsId, spsId, ppsId), &vps, &sps, &pps);
	if (rslt != VK_SUCCESS) { return rslt; }

	// VideoToolbox writes its own parameter sets: report the override
	if (pFeedbackInfo) {
		pFeedbackInfo->hasOverrides = VK_TRUE;
		for (auto* next = (VkBaseOutStructure*)pFeedbackInfo->pNext; next; next = next->pNext) {
			if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H265_SESSION_PARAMETERS_FEEDBACK_INFO_KHR) {
				auto* pFeedback = (VkVideoEncodeH265SessionParametersFeedbackInfoKHR*)next;
				pFeedback->hasStdVPSOverrides = pGet->writeStdVPS;
				pFeedback->hasStdSPSOverrides = pGet->writeStdSPS;
				pFeedback->hasStdPPSOverrides = pGet->writeStdPPS;
			}
		}
	}

	const vector<uint8_t>* parts[3] = { pGet->writeStdVPS ? &vps : nullptr,
										pGet->writeStdSPS ? &sps : nullptr,
										pGet->writeStdPPS ? &pps : nullptr };
	size_t total = 0;
	for (auto* part : parts) { if (part) { total += 4 + part->size(); } }
	if ( !pData ) {
		*pDataSize = total;
		return VK_SUCCESS;
	}
	if (*pDataSize < total) { return VK_INCOMPLETE; }
	uint8_t* dst = (uint8_t*)pData;
	static const uint8_t startCode[4] = { 0, 0, 0, 1 };
	for (auto* part : parts) {
		if ( !part ) { continue; }
		memcpy(dst, startCode, 4); memcpy(dst + 4, part->data(), part->size());
		dst += 4 + part->size();
	}
	*pDataSize = total;
	return VK_SUCCESS;
}

MVKVideoSessionParameters::MVKVideoSessionParameters(MVKDevice* device, const VkVideoSessionParametersCreateInfoKHR* pCreateInfo)
	: MVKVulkanAPIDeviceObject(device) {
	_session = (MVKVideoSession*)pCreateInfo->videoSession;
	_session->retain();
	_maxSPSCount = 0;
	_maxPPSCount = 0;

	if (pCreateInfo->videoSessionParametersTemplate) {
		auto* pTemplate = (MVKVideoSessionParameters*)pCreateInfo->videoSessionParametersTemplate;
		for (auto& e : pTemplate->_spsList) { _spsList.push_back(e); }
		for (auto& e : pTemplate->_ppsList) { _ppsList.push_back(e); }
		for (auto& e : pTemplate->_h265VpsList) { _h265VpsList.push_back(e); }
		for (auto& e : pTemplate->_h265SpsList) { _h265SpsList.push_back(e); }
		for (auto& e : pTemplate->_h265PpsList) { _h265PpsList.push_back(e); }
	}

	// H.265 creates carry a VPS list beside the SPS and PPS
	uint32_t vpsCount5 = 0, spsCount5 = 0, ppsCount5 = 0;
	const StdVideoH265VideoParameterSet* pVPSs5 = nullptr;
	const StdVideoH265SequenceParameterSet* pSPSs5 = nullptr;
	const StdVideoH265PictureParameterSet* pPPSs5 = nullptr;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H265_SESSION_PARAMETERS_CREATE_INFO_KHR) {
			auto* pH265 = (const VkVideoEncodeH265SessionParametersCreateInfoKHR*)next;
			_maxVPSCount = pH265->maxStdVPSCount;
			_maxSPSCount = pH265->maxStdSPSCount;
			_maxPPSCount = pH265->maxStdPPSCount;
			if (auto* pAdd = pH265->pParametersAddInfo) {
				vpsCount5 = pAdd->stdVPSCount; pVPSs5 = pAdd->pStdVPSs;
				spsCount5 = pAdd->stdSPSCount; pSPSs5 = pAdd->pStdSPSs;
				ppsCount5 = pAdd->stdPPSCount; pPPSs5 = pAdd->pStdPPSs;
			}
		} else if (next->sType == VK_STRUCTURE_TYPE_VIDEO_DECODE_H265_SESSION_PARAMETERS_CREATE_INFO_KHR) {
			auto* pH265 = (const VkVideoDecodeH265SessionParametersCreateInfoKHR*)next;
			_maxVPSCount = pH265->maxStdVPSCount;
			_maxSPSCount = pH265->maxStdSPSCount;
			_maxPPSCount = pH265->maxStdPPSCount;
			if (auto* pAdd = pH265->pParametersAddInfo) {
				vpsCount5 = pAdd->stdVPSCount; pVPSs5 = pAdd->pStdVPSs;
				spsCount5 = pAdd->stdSPSCount; pSPSs5 = pAdd->pStdSPSs;
				ppsCount5 = pAdd->stdPPSCount; pPPSs5 = pAdd->pStdPPSs;
			}
		}
	}
	if (_session->isHevc()) {
		_maxVPSCount = max(_maxVPSCount, (uint32_t)_h265VpsList.size());
		_maxSPSCount = max(_maxSPSCount, (uint32_t)_h265SpsList.size());
		_maxPPSCount = max(_maxPPSCount, (uint32_t)_h265PpsList.size());
		VkResult rslt5 = addH265(vpsCount5, pVPSs5, spsCount5, pSPSs5, ppsCount5, pPPSs5);
		if (rslt5 != VK_SUCCESS) {
			setConfigurationResult(reportError(rslt5, "vkCreateVideoSessionParametersKHR(): more parameter sets than the maximum."));
		}
		return;
	}

	// the encode and decode add infos share one layout
	uint32_t spsCount = 0, ppsCount = 0;
	const StdVideoH264SequenceParameterSet* pSPSs = nullptr;
	const StdVideoH264PictureParameterSet* pPPSs = nullptr;
	for (const auto* next = (VkBaseInStructure*)pCreateInfo->pNext; next; next = next->pNext) {
		if (next->sType == VK_STRUCTURE_TYPE_VIDEO_ENCODE_H264_SESSION_PARAMETERS_CREATE_INFO_KHR) {
			auto* pH264 = (const VkVideoEncodeH264SessionParametersCreateInfoKHR*)next;
			_maxSPSCount = pH264->maxStdSPSCount;
			_maxPPSCount = pH264->maxStdPPSCount;
			if (auto* pAdd = pH264->pParametersAddInfo) {
				spsCount = pAdd->stdSPSCount; pSPSs = pAdd->pStdSPSs;
				ppsCount = pAdd->stdPPSCount; pPPSs = pAdd->pStdPPSs;
			}
		} else if (next->sType == VK_STRUCTURE_TYPE_VIDEO_DECODE_H264_SESSION_PARAMETERS_CREATE_INFO_KHR) {
			auto* pH264 = (const VkVideoDecodeH264SessionParametersCreateInfoKHR*)next;
			_maxSPSCount = pH264->maxStdSPSCount;
			_maxPPSCount = pH264->maxStdPPSCount;
			if (auto* pAdd = pH264->pParametersAddInfo) {
				spsCount = pAdd->stdSPSCount; pSPSs = pAdd->pStdSPSs;
				ppsCount = pAdd->stdPPSCount; pPPSs = pAdd->pStdPPSs;
			}
		}
	}
	_maxSPSCount = max(_maxSPSCount, (uint32_t)_spsList.size());
	_maxPPSCount = max(_maxPPSCount, (uint32_t)_ppsList.size());
	VkResult rslt = add(spsCount, pSPSs, ppsCount, pPPSs);
	if (rslt != VK_SUCCESS) {
		setConfigurationResult(reportError(rslt, "vkCreateVideoSessionParametersKHR(): more parameter sets than the maximum."));
	}
}

MVKVideoSessionParameters::~MVKVideoSessionParameters() {
	if (_session) { _session->release(); }
}
