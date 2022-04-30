/*
 * MVKImage.h
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

#pragma once

#include "MVKResource.h"
#include "MVKCommandResourceFactory.h"
#include "MVKSync.h"
#include "MVKSmallVector.h"
#include <MoltenVKShaderConverter/SPIRVToMSLConverter.h>
#include <unordered_map>
#include <mutex>

#import <IOSurface/IOSurfaceRef.h>

class MVKImage;
class MVKImageView;
class MVKSwapchain;
class MVKCommandEncoder;


#pragma mark -
#pragma mark MVKImagePlane

/** Tracks the state of an image subresource.  */
typedef struct {
    VkImageSubresource subresource;
    VkSubresourceLayout layout;
    VkImageLayout layoutState;
} MVKImageSubresource;

class MVKImagePlane : public MVKBaseObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

	/** Returns the Metal texture underlying this image plane. */
    id<MTLTexture> getMTLTexture();

    /** Returns a Metal texture that interprets the pixels in the specified format. */
    id<MTLTexture> getMTLTexture(MTLPixelFormat mtlPixFmt);

    void releaseMTLTexture();

    ~MVKImagePlane();

protected:
	friend class MVKImageMemoryBinding;
	friend MVKImage;

    MTLTextureDescriptor* newMTLTextureDescriptor();
    void initSubresources(const VkImageCreateInfo* pCreateInfo);
    MVKImageSubresource* getSubresource(uint32_t mipLevel, uint32_t arrayLayer);
    void updateMTLTextureContent(MVKImageSubresource& subresource, VkDeviceSize offset, VkDeviceSize size);
    void getMTLTextureContent(MVKImageSubresource& subresource, VkDeviceSize offset, VkDeviceSize size);
	bool overlaps(VkSubresourceLayout& imgLayout, VkDeviceSize offset, VkDeviceSize size);
    void propagateDebugName();
    MVKImageMemoryBinding* getMemoryBinding() const;
	void applyImageMemoryBarrier(VkPipelineStageFlags srcStageMask,
								 VkPipelineStageFlags dstStageMask,
								 MVKPipelineBarrier& barrier,
								 MVKCommandEncoder* cmdEncoder,
								 MVKCommandUse cmdUse);
	void pullFromDeviceOnCompletion(MVKCommandEncoder* cmdEncoder,
									MVKImageSubresource& subresource,
									const MVKMappedMemoryRange& mappedRange);

    MVKImagePlane(MVKImage* image, uint8_t planeIndex);

    MVKImage* _image;
    uint8_t _planeIndex;
    VkExtent2D _blockTexelSize;
    uint32_t _bytesPerBlock;
    MTLPixelFormat _mtlPixFmt;
    id<MTLTexture> _mtlTexture;
    std::unordered_map<NSUInteger, id<MTLTexture>> _mtlTextureViews;
    MVKSmallVector<MVKImageSubresource, 1> _subresources;
};


#pragma mark -
#pragma mark MVKImageMemoryBinding

class MVKImageMemoryBinding : public MVKResource {

public:
    
    /** Returns the Vulkan type of this object. */
    VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_UNKNOWN; }

    /** Returns the debug report object type of this object. */
    VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_UNKNOWN_EXT; }

    /** Returns the memory requirements of this resource by populating the specified structure. */
    VkResult getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements);

    /** Returns the memory requirements of this resource by populating the specified structure. */
    VkResult getMemoryRequirements(const void* pInfo, VkMemoryRequirements2* pMemoryRequirements);

    /** Binds this resource to the specified offset within the specified memory allocation. */
    VkResult bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset) override;

    /** Applies the specified global memory barrier. */
    void applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
                            VkPipelineStageFlags dstStageMask,
                            MVKPipelineBarrier& barrier,
                            MVKCommandEncoder* cmdEncoder,
                            MVKCommandUse cmdUse) override;

    ~MVKImageMemoryBinding();

protected:
    friend MVKDeviceMemory;
    friend MVKImagePlane;
    friend MVKImage;

    void propagateDebugName() override;
    bool needsHostReadSync(VkPipelineStageFlags srcStageMask,
                           VkPipelineStageFlags dstStageMask,
                           MVKPipelineBarrier& barrier);
    bool shouldFlushHostMemory();
    VkResult flushToDevice(VkDeviceSize offset, VkDeviceSize size);
    VkResult pullFromDevice(VkDeviceSize offset, VkDeviceSize size);
    uint8_t beginPlaneIndex() const;
    uint8_t endPlaneIndex() const;

    MVKImageMemoryBinding(MVKDevice* device, MVKImage* image, uint8_t planeIndex);

    MVKImage* _image;
    id<MTLBuffer> _mtlTexelBuffer = nil;
    NSUInteger _mtlTexelBufferOffset = 0;
    uint8_t _planeIndex;
    bool _ownsTexelBuffer = false;
};


#pragma mark -
#pragma mark MVKImage

/** Represents a Vulkan image. */
class MVKImage : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_IMAGE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_IMAGE_EXT; }

    /** Returns the plane index of VkImageAspectFlags. */
    static uint8_t getPlaneFromVkImageAspectFlags(VkImageAspectFlags aspectMask);

	/**
	 * Returns the Vulkan image type of this image.
	 * This may be different than the value originally specified for the image
	 * if a 1D texture is being handled via a Metal 2D texture with height of 1.
	 */
    VkImageType getImageType();

    /** Returns the Vulkan image format of this image. */
    VkFormat getVkFormat() { return _vkFormat; };

	/** Returns whether this image has a depth or stencil format. */
	bool getIsDepthStencil();

	/** Returns whether this image is compressed. */
	bool getIsCompressed();

	/** Returns whether this image has a linear memory layout. */
	bool getIsLinear() { return _isLinear; }

	/** Returns whether this image is allowed to alias another image. */
	bool getIsAliasable() { return _isAliasable; }

	/**  Returns the 3D extent of this image at the specified mipmap level. */
	VkExtent3D getExtent3D(uint8_t planeIndex = 0, uint32_t mipLevel = 0);

	/** Returns the number of mipmap levels in this image. */
	uint32_t getMipLevelCount() { return _mipLevels; }

	/**
	 * Returns the number of layers at each mipmap level. For an array image type, this is
	 * the number of elements in the array. For cube image type, this is a multiple of 6.
	 */
	uint32_t getLayerCount() { return _arrayLayers; }

    /** Returns the number of samples for each pixel of this image. */
    VkSampleCountFlagBits getSampleCount() { return _samples; }

	 /** 
	  * Returns the number of bytes per image row at the specified zero-based mip level.
      * For non-compressed formats, this is the number of bytes in a row of texels.
      * For compressed formats, this is the number of bytes in a row of blocks, which
      * will typically span more than one row of texels.
	  */
	VkDeviceSize getBytesPerRow(uint8_t planeIndex, uint32_t mipLevel);

	/**
	 * Returns the number of bytes per image layer (for cube, array, or 3D images) 
	 * at the specified zero-based mip level. This value will normally be the number
	 * of bytes per row (as returned by the getBytesPerRow() function, multiplied by 
	 * the height of each 2D image.
	 */
	VkDeviceSize getBytesPerLayer(uint8_t planeIndex, uint32_t mipLevel);
    
    /** Returns the number of planes of this image view. */
    uint8_t getPlaneCount() { return _planes.size(); }

	/** Populates the specified layout for the specified sub-resource. */
	VkResult getSubresourceLayout(const VkImageSubresource* pSubresource,
								  VkSubresourceLayout* pLayout);

    /** Populates the specified transfer image descriptor data structure. */
    void getTransferDescriptorData(MVKImageDescriptorData& imgData);


#pragma mark Resource memory

	/** Returns the memory requirements of this resource by populating the specified structure. */
	VkResult getMemoryRequirements(VkMemoryRequirements* pMemoryRequirements, uint8_t planeIndex);

	/** Returns the memory requirements of this resource by populating the specified structure. */
	VkResult getMemoryRequirements(const void* pInfo, VkMemoryRequirements2* pMemoryRequirements);

	/** Binds this resource to the specified offset within the specified memory allocation. */
	virtual VkResult bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset, uint8_t planeIndex);

	/** Binds this resource to the specified offset within the specified memory allocation. */
	virtual VkResult bindDeviceMemory2(const VkBindImageMemoryInfo* pBindInfo);

	/** Applies the specified image memory barrier. */
	void applyImageMemoryBarrier(VkPipelineStageFlags srcStageMask,
								 VkPipelineStageFlags dstStageMask,
								 MVKPipelineBarrier& barrier,
								 MVKCommandEncoder* cmdEncoder,
								 MVKCommandUse cmdUse);

    /** Flush underlying buffer memory into the image if necessary */
    void flushToDevice(VkDeviceSize offset, VkDeviceSize size);

#pragma mark Metal

	/** Returns the Metal texture underlying this image. */
	virtual id<MTLTexture> getMTLTexture(uint8_t planeIndex = 0);

	/** Returns a Metal texture that interprets the pixels in the specified format. */
	id<MTLTexture> getMTLTexture(uint8_t planeIndex, MTLPixelFormat mtlPixFmt);

    /**
     * Sets this image to use the specified MTLTexture.
     *
     * Any differences in the properties of mtlTexture and this image will modify the 
     * properties of this image.
     *
     * If a MTLTexture has already been created for this image, it will be destroyed.
     */
    VkResult setMTLTexture(uint8_t planeIndex, id<MTLTexture> mtlTexture);

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
	inline MTLPixelFormat getMTLPixelFormat(uint8_t planeIndex = 0) { return _planes[planeIndex]->_mtlPixFmt; }

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


#pragma mark Construction

	MVKImage(MVKDevice* device, const VkImageCreateInfo* pCreateInfo);

	~MVKImage() override;

protected:
    friend MVKDeviceMemory;
    friend MVKDevice;
    friend MVKImageMemoryBinding;
    friend MVKImagePlane;
    friend class MVKImageViewPlane;
	friend MVKImageView;

	void propagateDebugName() override;
	void validateConfig(const VkImageCreateInfo* pCreateInfo, bool isAttachment);
	VkSampleCountFlagBits validateSamples(const VkImageCreateInfo* pCreateInfo, bool isAttachment);
	uint32_t validateMipLevels(const VkImageCreateInfo* pCreateInfo, bool isAttachment);
	bool validateLinear(const VkImageCreateInfo* pCreateInfo, bool isAttachment);
	void initExternalMemory(VkExternalMemoryHandleTypeFlags handleTypes);
    void releaseIOSurface();
	bool getIsValidViewFormat(VkFormat viewFormat);
	VkImageUsageFlags getCombinedUsage() { return _usage | _stencilUsage; }
	MTLTextureUsage getMTLTextureUsage(MTLPixelFormat mtlPixFmt);

    MVKSmallVector<MVKImageMemoryBinding*, 3> _memoryBindings;
    MVKSmallVector<MVKImagePlane*, 3> _planes;
	MVKSmallVector<VkFormat, 2> _viewFormats;
    VkExtent3D _extent;
    uint32_t _mipLevels;
    uint32_t _arrayLayers;
    VkSampleCountFlagBits _samples;
    VkImageUsageFlags _usage;
	VkImageUsageFlags _stencilUsage;
    VkFormat _vkFormat;
	MTLTextureType _mtlTextureType;
    std::mutex _lock;
    IOSurfaceRef _ioSurface;
	VkDeviceSize _rowByteAlignment;
    bool _isDepthStencilAttachment;
	bool _canSupportMTLTextureView;
    bool _hasExpectedTexelSize;
    bool _hasChromaSubsampling;
	bool _isLinear;
	bool _is3DCompressed;
	bool _isAliasable;
	bool _hasExtendedUsage;
	bool _hasMutableFormat;
	bool _isLinearForAtomics;
};


#pragma mark -
#pragma mark MVKSwapchainImage

/** Abstract class of Vulkan image used as a rendering destination within a swapchain. */
class MVKSwapchainImage : public MVKImage {

public:

	/** Binds this resource to the specified offset within the specified memory allocation. */
	VkResult bindDeviceMemory(MVKDeviceMemory* mvkMem, VkDeviceSize memOffset, uint8_t planeIndex) override;

#pragma mark Metal

	/** Returns the Metal texture used by the CAMetalDrawable underlying this image. */
	id<MTLTexture> getMTLTexture(uint8_t planeIndex) override;


#pragma mark Construction

	/** Constructs an instance for the specified device and swapchain. */
	MVKSwapchainImage(MVKDevice* device,
					  const VkImageCreateInfo* pCreateInfo,
					  MVKSwapchain* swapchain,
					  uint32_t swapchainIndex);

	~MVKSwapchainImage() override;

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

/** VK_GOOGLE_display_timing extension info */
typedef struct  {
	MVKPresentableSwapchainImage* presentableImage;
	bool hasPresentTime;      		// Keep track of whether presentation included VK_GOOGLE_display_timing
	uint32_t presentID;           	// VK_GOOGLE_display_timing presentID
	uint64_t desiredPresentTime;  	// VK_GOOGLE_display_timing desired presentation time in nanoseconds
} MVKPresentTimingInfo;

/** Tracks a semaphore and fence for later signaling. */
struct MVKSwapchainSignaler {
	MVKFence* fence;
	MVKSemaphore* semaphore;
	uint64_t semaphoreSignalToken;
};


/** Represents a Vulkan swapchain image that can be submitted to the presentation engine. */
class MVKPresentableSwapchainImage : public MVKSwapchainImage {

public:

#pragma mark Metal

	/** Presents the contained drawable to the OS. */
	void presentCAMetalDrawable(id<MTLCommandBuffer> mtlCmdBuff,
								MVKPresentTimingInfo presentTimingInfo);


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
	void presentCAMetalDrawable(id<CAMetalDrawable> mtlDrawable, MVKPresentTimingInfo presentTimingInfo);
	void releaseMetalDrawable();
	MVKSwapchainImageAvailability getAvailability();
	void makeAvailable(const MVKSwapchainSignaler& signaler);
	void acquireAndSignalWhenAvailable(MVKSemaphore* semaphore, MVKFence* fence);
	void signal(const MVKSwapchainSignaler& signaler, id<MTLCommandBuffer> mtlCmdBuff);
	void signalPresentationSemaphore(const MVKSwapchainSignaler& signaler, id<MTLCommandBuffer> mtlCmdBuff);
	static void markAsTracked(const MVKSwapchainSignaler& signaler);
	static void unmarkAsTracked(const MVKSwapchainSignaler& signaler);
	void renderWatermark(id<MTLCommandBuffer> mtlCmdBuff);

	id<CAMetalDrawable> _mtlDrawable;
	id<MTLCommandBuffer> _presentingMTLCmdBuff;
	MVKSwapchainImageAvailability _availability;
	MVKSmallVector<MVKSwapchainSignaler, 1> _availabilitySignalers;
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
#pragma mark MVKImageViewPlane

class MVKImageViewPlane : public MVKBaseDeviceObject {

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override;

public:
    /** Returns the Metal texture underlying this image view. */
    id<MTLTexture> getMTLTexture();

    void releaseMTLTexture();

	/** Returns the packed component swizzle of this image view. */
	uint32_t getPackedSwizzle() { return _useShaderSwizzle ? mvkPackSwizzle(_componentSwizzle) : 0; }

    ~MVKImageViewPlane();

protected:
    void propagateDebugName();
    id<MTLTexture> newMTLTexture();
	VkResult initSwizzledMTLPixelFormat(const VkImageViewCreateInfo* pCreateInfo);
	bool enableSwizzling();
    MVKImageViewPlane(MVKImageView* imageView, uint8_t planeIndex, MTLPixelFormat mtlPixFmt, const VkImageViewCreateInfo* pCreateInfo);

    friend MVKImageView;
    MVKImageView* _imageView;
	id<MTLTexture> _mtlTexture;
	VkComponentMapping _componentSwizzle;
    MTLPixelFormat _mtlPixFmt;
	uint8_t _planeIndex;
    bool _useMTLTextureView;
	bool _useNativeSwizzle;
	bool _useShaderSwizzle;
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

	/**  Returns the 3D extent of this image at the specified mipmap level. */
	VkExtent3D getExtent3D(uint8_t planeIndex = 0, uint32_t mipLevel = 0) { return _image->getExtent3D(planeIndex, mipLevel); }

#pragma mark Metal

	/** Returns the Metal texture underlying this image view.  */
	id<MTLTexture> getMTLTexture(uint8_t planeIndex = 0) { return planeIndex < _planes.size() ? _planes[planeIndex]->getMTLTexture() : nil; }	// Guard against destroyed instance retained in a descriptor.

	/** Returns the Metal pixel format of this image view. */
	MTLPixelFormat getMTLPixelFormat(uint8_t planeIndex = 0) { return planeIndex < _planes.size() ? _planes[planeIndex]->_mtlPixFmt : MTLPixelFormatInvalid; }	// Guard against destroyed instance retained in a descriptor.

	/** Returns the Vulkan pixel format of this image view. */
	VkFormat getVkFormat(uint8_t planeIndex = 0) { return getPixelFormats()->getVkFormat(getMTLPixelFormat(planeIndex)); }

	/** Returns the number of samples for each pixel of this image view. */
	VkSampleCountFlagBits getSampleCount() { return _image->getSampleCount(); }

    /** Returns the packed component swizzle of this image view. */
    uint32_t getPackedSwizzle() { return _planes.empty() ? 0 : _planes[0]->getPackedSwizzle(); }	// Guard against destroyed instance retained in a descriptor.
    
    /** Returns the number of planes of this image view. */
    uint8_t getPlaneCount() { return _planes.size(); }

	/** Returns the Metal texture type of this image view. */
	MTLTextureType getMTLTextureType() { return _mtlTextureType; }

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


#pragma mark Construction

	MVKImageView(MVKDevice* device, const VkImageViewCreateInfo* pCreateInfo);

	~MVKImageView();

	void destroy() override;

protected:
    friend MVKImageViewPlane;
    
	void propagateDebugName() override;
	void detachMemory();

    MVKImage* _image;
    MVKSmallVector<MVKImageViewPlane*, 3> _planes;
    VkImageSubresourceRange _subresourceRange;
    VkImageUsageFlags _usage;
	std::mutex _lock;
	MTLTextureType _mtlTextureType;
};


#pragma mark -
#pragma mark MVKSamplerYcbcrConversion

/** Represents a Vulkan sampler ycbcr conversion. */
class MVKSamplerYcbcrConversion : public MVKVulkanAPIDeviceObject {

public:
    /** Returns the Vulkan type of this object. */
    VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_SAMPLER_YCBCR_CONVERSION; }

    /** Returns the debug report object type of this object. */
    VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_SAMPLER_YCBCR_CONVERSION_EXT; }
    
    /** Returns the number of planes of this ycbcr conversion. */
    inline uint8_t getPlaneCount() { return _planes; }

    /** Writes this conversion settings to a MSL constant sampler */
    void updateConstExprSampler(SPIRV_CROSS_NAMESPACE::MSLConstexprSampler& constExprSampler) const;

    MVKSamplerYcbcrConversion(MVKDevice* device, const VkSamplerYcbcrConversionCreateInfo* pCreateInfo);

    ~MVKSamplerYcbcrConversion() override {}

protected:
    void propagateDebugName() override {}

    uint8_t _planes, _bpc;
    SPIRV_CROSS_NAMESPACE::MSLFormatResolution _resolution;
    SPIRV_CROSS_NAMESPACE::MSLSamplerFilter _chroma_filter;
    SPIRV_CROSS_NAMESPACE::MSLChromaLocation _x_chroma_offset, _y_chroma_offset;
    SPIRV_CROSS_NAMESPACE::MSLComponentSwizzle _swizzle[4];
    SPIRV_CROSS_NAMESPACE::MSLSamplerYCbCrModelConversion _ycbcr_model;
    SPIRV_CROSS_NAMESPACE::MSLSamplerYCbCrRange _ycbcr_range;
    bool _forceExplicitReconstruction;
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
    
    /** Returns the number of planes if this is a ycbcr conversion or 0 otherwise. */
    inline uint8_t getPlaneCount() { return (_ycbcrConversion) ? _ycbcrConversion->getPlaneCount() : 0; }

	/**
	 * If this sampler requires hardcoding in MSL, populates the hardcoded sampler in the resource binding.
	 * Returns whether this sampler requires hardcoding in MSL, and the constant sampler was populated.
	 */
	bool getConstexprSampler(mvk::MSLResourceBinding& resourceBinding);

	/** Returns whether this sampler must be implemented as a hardcoded constant sampler in the shader MSL code. */
	inline 	bool getRequiresConstExprSampler() { return _requiresConstExprSampler; }

	/** Returns the Metal MTLSamplerAddressMode corresponding to the specified Vulkan VkSamplerAddressMode. */
	MTLSamplerAddressMode getMTLSamplerAddressMode(VkSamplerAddressMode vkMode);

	MVKSampler(MVKDevice* device, const VkSamplerCreateInfo* pCreateInfo);

	~MVKSampler() override;

	void destroy() override;

protected:
	void propagateDebugName() override {}
	MTLSamplerDescriptor* newMTLSamplerDescriptor(const VkSamplerCreateInfo* pCreateInfo);
	void initConstExprSampler(const VkSamplerCreateInfo* pCreateInfo);
	void detachMemory();

	id<MTLSamplerState> _mtlSamplerState;
	SPIRV_CROSS_NAMESPACE::MSLConstexprSampler _constExprSampler;
	MVKSamplerYcbcrConversion* _ycbcrConversion;
	bool _requiresConstExprSampler;
};
