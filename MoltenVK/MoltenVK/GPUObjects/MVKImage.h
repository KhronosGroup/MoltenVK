/*
 * MVKImage.h
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKResource.h"
#include "MVKCommandResourceFactory.h"
#include "MVKSync.h"
#include "MVKVector.h"
#include <MoltenVKSPIRVToMSLConverter/SPIRVToMSLConverter.h>
#include <unordered_map>
#include <mutex>

#import <IOSurface/IOSurfaceRef.h>

class MVKImageView;
class MVKSwapchain;
class MVKCommandEncoder;


/** Tracks the state of an image subresource.  */
typedef struct {
	VkImageSubresource subresource;
	VkSubresourceLayout layout;
	VkImageLayout layoutState;
} MVKImageSubresource;


#pragma mark -
#pragma mark MVKImage

/** Represents a Vulkan image. */
class MVKImage : public MVKResource {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_IMAGE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_IMAGE_EXT; }

	/**
	 * Returns the Vulkan image type of this image.
	 * This may be different than the value originally specified for the image
	 * if a 1D texture is being handled via a Metal 2D texture with height of 1.
	 */
    VkImageType getImageType();

    /** Returns the Vulkan image format of this image. */
    VkFormat getVkFormat();

	/** Returns whether this image has a depth or stencil format. */
	bool getIsDepthStencil();

	/** Returns whether this image is compressed. */
	bool getIsCompressed();

	/** 
	 * Returns the 3D extent of this image at the base mipmap level.
	 * For 2D or cube images, the Z component will be 1.  
	 */
	inline VkExtent3D getExtent3D() { return _extent; }

	/** 
	 * Returns the 3D extent of this image at the specified mipmap level. 
	 * For 2D or cube images, the Z component will be 1.
	 */
	VkExtent3D getExtent3D(uint32_t mipLevel);

	/** Returns the number of mipmap levels in this image. */
	inline uint32_t getMipLevelCount() { return _mipLevels; }

	/**
	 * Returns the number of layers at each mipmap level. For an array image type, this is
	 * the number of elements in the array. For cube image type, this is a multiple of 6.
	 */
	inline uint32_t getLayerCount() { return _arrayLayers; }

    /** Returns the number of samples for each pixel of this image. */
    inline VkSampleCountFlagBits getSampleCount() { return _samples; }

	 /** 
	  * Returns the number of bytes per image row at the specified zero-based mip level.
      * For non-compressed formats, this is the number of bytes in a row of texels.
      * For compressed formats, this is the number of bytes in a row of blocks, which
      * will typically span more than one row of texels.
	  */
	VkDeviceSize getBytesPerRow(uint32_t mipLevel);

	/**
	 * Returns the number of bytes per image layer (for cube, array, or 3D images) 
	 * at the specified zero-based mip level. This value will normally be the number
	 * of bytes per row (as returned by the getBytesPerRow() function, multiplied by 
	 * the height of each 2D image.
	 */
	VkDeviceSize getBytesPerLayer(uint32_t mipLevel);

	/** Populates the specified layout for the specified sub-resource. */
	VkResult getSubresourceLayout(const VkImageSubresource* pSubresource,
								  VkSubresourceLayout* pLayout);

    /** Populates the specified transfer image descriptor data structure. */
    void getTransferDescriptorData(MVKImageDescriptorData& imgData);


#pragma mark Resource memory

	/** Returns the memory requirements of this resource by populating the specified structure. */
	VkResult getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements) override;

	/** Returns the memory requirements of this resource by populating the specified structure. */
	VkResult getMemoryRequirements(const void* pInfo, VkMemoryRequirements2* pMemoryRequirements) override;

	/** Binds this resource to the specified offset within the specified memory allocation. */
	VkResult bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) override;

	/** Binds this resource to the specified offset within the specified memory allocation. */
	virtual VkResult bindDeviceMemory2(const VkBindImageMemoryInfo* pBindInfo);

	/** Applies the specified global memory barrier. */
	void applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
							VkPipelineStageFlags dstStageMask,
							MVKPipelineBarrier& barrier,
							MVKCommandEncoder* cmdEncoder,
							MVKCommandUse cmdUse) override;

	/** Applies the specified image memory barrier. */
	void applyImageMemoryBarrier(VkPipelineStageFlags srcStageMask,
								 VkPipelineStageFlags dstStageMask,
								 MVKPipelineBarrier& barrier,
								 MVKCommandEncoder* cmdEncoder,
								 MVKCommandUse cmdUse);

#pragma mark Metal

	/** Returns the Metal texture underlying this image. */
	virtual id<MTLTexture> getMTLTexture();

	/** Returns a Metal texture that interprets the pixels in the specified format. */
	id<MTLTexture> getMTLTexture(MTLPixelFormat mtlPixFmt);

    /**
     * Sets this image to use the specified MTLTexture.
     *
     * Any differences in the properties of mtlTexture and this image will modify the 
     * properties of this image.
     *
     * If a MTLTexture has already been created for this image, it will be destroyed.
     */
    VkResult setMTLTexture(id<MTLTexture> mtlTexture);

    /**
     * Indicates that this VkImage should use an IOSurface to underlay the Metal texture.
     *
     * If ioSurface is provided and is not nil, it will be used as the IOSurface.
     *
     * If ioSurface is not provided, or is nil, this image will create and use an IOSurface
     * whose properties are compatible with the properties of this image.
     *
     * If a MTLTexture has already been created for this image, it will be destroyed.
     *
     * Returns:
     *   - VK_SUCCESS.
     *   - VK_ERROR_FEATURE_NOT_PRESENT if IOSurfaces are not supported on the platform.
     *   - VK_ERROR_INITIALIZATION_FAILED if ioSurface is specified and is not compatible with this VkImage.
     */
    VkResult useIOSurface(IOSurfaceRef ioSurface = nil);

    /**
     * Returns the IOSurface underlying the MTLTexture,
     * or nil if no IOSurface has been set via useIOSurface().
     */
    IOSurfaceRef getIOSurface();

	/** Returns the Metal pixel format of this image. */
	inline MTLPixelFormat getMTLPixelFormat() { return _mtlPixelFormat; }

	/** Returns the Metal texture type of this image. */
	inline MTLTextureType getMTLTextureType() { return _mtlTextureType; }

    /** 
     * Returns whether the Metal texel size is the same as the Vulkan texel size.
     *
     * If a different MTLPixelFormat was substituted for the desired VkFormat, the texel 
     * size may be different. This can occur for certain depth formats when the format 
     * is not supported on a platform, and the application has not verified this. 
     * In this case, a different depth format will automatically be substituted. 
     * With depth formats, this is usually accpetable, but can cause problems when
     * attempting to copy a depth image with a substituted format to and from a buffer.
     */
    inline bool hasExpectedTexelSize() { return _hasExpectedTexelSize; }

	/** Returns the Metal resource options for this image. */
    MTLStorageMode getMTLStorageMode();

	/** Returns the Metal CPU cache mode used by this image. */
	MTLCPUCacheMode getMTLCPUCacheMode();

	/** 
	 * Returns whether the memory is automatically coherent between device and host. 
	 * On macOS, this always returns false because textures cannot use Shared storage mode.
	 */
	bool isMemoryHostCoherent();

#pragma mark Construction

	MVKImage(MVKDevice* device, const VkImageCreateInfo* pCreateInfo);

	~MVKImage() override;

protected:
	friend class MVKDeviceMemory;
	friend class MVKImageView;
	using MVKResource::needsHostReadSync;

	void propogateDebugName() override;
	MVKImageSubresource* getSubresource(uint32_t mipLevel, uint32_t arrayLayer);
	void validateConfig(const VkImageCreateInfo* pCreateInfo, bool isAttachment);
	VkSampleCountFlagBits validateSamples(const VkImageCreateInfo* pCreateInfo, bool isAttachment);
	uint32_t validateMipLevels(const VkImageCreateInfo* pCreateInfo, bool isAttachment);
	bool validateLinear(const VkImageCreateInfo* pCreateInfo, bool isAttachment);
	bool validateUseTexelBuffer();
	void initSubresources(const VkImageCreateInfo* pCreateInfo);
	void initSubresourceLayout(MVKImageSubresource& imgSubRez);
	void initExternalMemory(VkExternalMemoryHandleTypeFlags handleTypes);
	id<MTLTexture> newMTLTexture();
	void releaseMTLTexture();
    void releaseIOSurface();
	MTLTextureDescriptor* newMTLTextureDescriptor();
    void updateMTLTextureContent(MVKImageSubresource& subresource, VkDeviceSize offset, VkDeviceSize size);
    void getMTLTextureContent(MVKImageSubresource& subresource, VkDeviceSize offset, VkDeviceSize size);
	bool shouldFlushHostMemory();
	VkResult flushToDevice(VkDeviceSize offset, VkDeviceSize size);
	VkResult pullFromDevice(VkDeviceSize offset, VkDeviceSize size);
	bool needsHostReadSync(VkPipelineStageFlags srcStageMask,
						   VkPipelineStageFlags dstStageMask,
						   MVKPipelineBarrier& barrier);

	MVKVectorInline<MVKImageSubresource, 1> _subresources;
	std::unordered_map<NSUInteger, id<MTLTexture>> _mtlTextureViews;
    VkExtent3D _extent;
    uint32_t _mipLevels;
    uint32_t _arrayLayers;
    VkSampleCountFlagBits _samples;
    VkImageUsageFlags _usage;
	MTLPixelFormat _mtlPixelFormat;
	MTLTextureType _mtlTextureType;
    id<MTLTexture> _mtlTexture;
    std::mutex _lock;
    IOSurfaceRef _ioSurface;
	VkDeviceSize _rowByteAlignment;
    bool _isDepthStencilAttachment;
	bool _canSupportMTLTextureView;
    bool _hasExpectedTexelSize;
	bool _usesTexelBuffer;
	bool _isLinear;
	bool _is3DCompressed;
	bool _isAliasable;
};


#pragma mark -
#pragma mark MVKSwapchainImage

/** Abstract class of Vulkan image used as a rendering destination within a swapchain. */
class MVKSwapchainImage : public MVKImage {

public:

	/** Binds this resource to the specified offset within the specified memory allocation. */
	VkResult bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) override;

#pragma mark Metal

	/** Returns the Metal texture used by the CAMetalDrawable underlying this image. */
	id<MTLTexture> getMTLTexture() override;


#pragma mark Construction

	/** Constructs an instance for the specified device and swapchain. */
	MVKSwapchainImage(MVKDevice* device,
					  const VkImageCreateInfo* pCreateInfo,
					  MVKSwapchain* swapchain,
					  uint32_t swapchainIndex);

protected:
	friend class MVKPeerSwapchainImage;

	virtual id<CAMetalDrawable> getCAMetalDrawable() = 0;

	MVKSwapchain* _swapchain;
	uint32_t _swapchainIndex;
};


#pragma mark -
#pragma mark MVKPresentableSwapchainImage

/** Indicates the relative availability of each image in the swapchain. */
typedef struct MVKSwapchainImageAvailability {
	uint64_t acquisitionID;			/**< When this image was last made available, relative to the other images in the swapchain. Smaller value is earlier. */
	bool isAvailable;				/**< Indicates whether this image is currently available. */

	bool operator< (const MVKSwapchainImageAvailability& rhs) const;
} MVKSwapchainImageAvailability;

/** Tracks a semaphore and fence for later signaling. */
typedef std::pair<MVKSemaphore*, MVKFence*> MVKSwapchainSignaler;


/** Represents a Vulkan swapchain image that can be submitted to the presentation engine. */
class MVKPresentableSwapchainImage : public MVKSwapchainImage {

public:

#pragma mark Metal

	/**
	 * Presents the contained drawable to the OS, releases the Metal drawable and its
	 * texture back to the Metal layer's pool, and makes the image memory available for new use.
	 *
	 * If mtlCmdBuff is not nil, the contained drawable is scheduled for presentation using
	 * the presentDrawable: method of the command buffer. If mtlCmdBuff is nil, the contained
	 * drawable is presented immediately using the present method of the drawable.
	 */
	void presentCAMetalDrawable(id<MTLCommandBuffer> mtlCmdBuff, bool hasPresentTime, uint32_t presentID, uint64_t desiredPresentTime);


#pragma mark Construction

	/** Constructs an instance for the specified device and swapchain. */
	MVKPresentableSwapchainImage(MVKDevice* device,
								 const VkImageCreateInfo* pCreateInfo,
								 MVKSwapchain* swapchain,
								 uint32_t swapchainIndex);

	~MVKPresentableSwapchainImage() override;

protected:
	friend MVKSwapchain;

	id<CAMetalDrawable> getCAMetalDrawable() override;
	void releaseMetalDrawable();
	MVKSwapchainImageAvailability getAvailability();
	void makeAvailable();
	void acquireAndSignalWhenAvailable(MVKSemaphore* semaphore, MVKFence* fence);
	void signal(MVKSwapchainSignaler& signaler, id<MTLCommandBuffer> mtlCmdBuff);
	void signalPresentationSemaphore(id<MTLCommandBuffer> mtlCmdBuff);
	static void markAsTracked(MVKSwapchainSignaler& signaler);
	static void unmarkAsTracked(MVKSwapchainSignaler& signaler);
	void renderWatermark(id<MTLCommandBuffer> mtlCmdBuff);

	id<CAMetalDrawable> _mtlDrawable;
	MVKSwapchainImageAvailability _availability;
	MVKVectorInline<MVKSwapchainSignaler, 1> _availabilitySignalers;
	MVKSwapchainSignaler _preSignaler;
	std::mutex _availabilityLock;
};


#pragma mark -
#pragma mark MVKPeerSwapchainImage

/** Represents a Vulkan swapchain image that can be associated as a peer to a swapchain image. */
class MVKPeerSwapchainImage : public MVKSwapchainImage {

public:

	/** Binds this resource according to the specified bind information. */
	VkResult bindDeviceMemory2(const VkBindImageMemoryInfo* pBindInfo) override;


#pragma mark Construction

	/** Constructs an instance for the specified device and swapchain. */
	MVKPeerSwapchainImage(MVKDevice* device,
						  const VkImageCreateInfo* pCreateInfo,
						  MVKSwapchain* swapchain,
						  uint32_t swapchainIndex);

protected:
	id<CAMetalDrawable> getCAMetalDrawable() override;

};


#pragma mark -
#pragma mark MVKImageView

/** Represents a Vulkan image view. */
class MVKImageView : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_IMAGE_VIEW; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_IMAGE_VIEW_EXT; }

#pragma mark Metal

	/** Returns the Metal texture underlying this image view. */
	id<MTLTexture> getMTLTexture();

	/** Returns the Metal pixel format of this image view. */
	inline MTLPixelFormat getMTLPixelFormat() { return _mtlPixelFormat; }

	/** Returns the Metal texture type of this image view. */
	inline MTLTextureType getMTLTextureType() { return _mtlTextureType; }

	/** Returns the packed component swizzle of this image view. */
	inline uint32_t getPackedSwizzle() { return _packedSwizzle; }

	/**
	 * Populates the texture of the specified render pass descriptor
	 * with the Metal texture underlying this image.
	 */
	void populateMTLRenderPassAttachmentDescriptor(MTLRenderPassAttachmentDescriptor* mtlAttDesc);

	/**
	 * Populates the resolve texture of the specified render pass descriptor
	 * with the Metal texture underlying this image.
	 */
	void populateMTLRenderPassAttachmentDescriptorResolve(MTLRenderPassAttachmentDescriptor* mtlAttDesc);

	/**
	 * Returns, in mtlPixFmt, a MTLPixelFormat, based on the MTLPixelFormat converted from
	 * the VkFormat, but possibly modified by the swizzles defined in the VkComponentMapping
	 * of the VkImageViewCreateInfo.
	 *
	 * Metal prior to version 3.0 does not support native per-texture swizzles, so if the swizzle
	 * is not an identity swizzle, this function attempts to find an alternate MTLPixelFormat that
	 * coincidentally matches the swizzled format.
	 *
	 * If a replacement MTLFormat was found, it is returned and useSwizzle is set to false.
	 * If a replacement MTLFormat could not be found, the original MTLPixelFormat is returned,
	 * and the useSwizzle is set to true, indicating that either native or shader swizzling
	 * should be used for this image view.
	 *
	 * This is a static function that can be used to validate image view formats prior to creating one.
	 */
	static VkResult validateSwizzledMTLPixelFormat(const VkImageViewCreateInfo* pCreateInfo,
												   MVKPixelFormats* mvkPixFmts,
												   MVKVulkanAPIObject* apiObject,
												   bool hasNativeSwizzleSupport,
												   bool hasShaderSwizzleSupport,
												   MTLPixelFormat& mtlPixFmt,
												   bool& useSwizzle);


#pragma mark Construction

	MVKImageView(MVKDevice* device,
				 const VkImageViewCreateInfo* pCreateInfo,
				 const MVKConfiguration* pAltMVKConfig = nullptr);

	~MVKImageView() override;

protected:
	void propogateDebugName() override;
	id<MTLTexture> newMTLTexture();
	void initMTLTextureViewSupport();
	void validateImageViewConfig(const VkImageViewCreateInfo* pCreateInfo);

    MVKImage* _image;
    VkImageSubresourceRange _subresourceRange;
    VkImageUsageFlags _usage;
	id<MTLTexture> _mtlTexture;
	std::mutex _lock;
	MTLPixelFormat _mtlPixelFormat;
	MTLTextureType _mtlTextureType;
	uint32_t _packedSwizzle;
	bool _useMTLTextureView;
};


#pragma mark -
#pragma mark MVKSampler

/** Represents a Vulkan sampler. */
class MVKSampler : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_SAMPLER; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_SAMPLER_EXT; }

	/** Returns the Metal sampler state. */
	inline id<MTLSamplerState> getMTLSamplerState() { return _mtlSamplerState; }

	/**
	 * If this sampler requires hardcoding in MSL, populates the hardcoded sampler in the resource binding.
	 * Returns whether this sampler requires hardcoding in MSL, and the constant sampler was populated.
	 */
	bool getConstexprSampler(mvk::MSLResourceBinding& resourceBinding);

	/** Returns whether this sampler must be implemented as a hardcoded constant sampler in the shader MSL code. */
	inline 	bool getRequiresConstExprSampler() { return _requiresConstExprSampler; }

	MVKSampler(MVKDevice* device, const VkSamplerCreateInfo* pCreateInfo);

	~MVKSampler() override;

protected:
	void propogateDebugName() override {}
	MTLSamplerDescriptor* newMTLSamplerDescriptor(const VkSamplerCreateInfo* pCreateInfo);
	void initConstExprSampler(const VkSamplerCreateInfo* pCreateInfo);

	id<MTLSamplerState> _mtlSamplerState;
	SPIRV_CROSS_NAMESPACE::MSLConstexprSampler _constExprSampler;
	bool _requiresConstExprSampler;
};
