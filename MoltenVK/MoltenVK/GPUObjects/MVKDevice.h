/*
 * MVKDevice.h
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

#pragma once

#include "MVKFoundation.h"
#include "MVKVulkanAPIObject.h"
#include "MVKMTLResourceBindings.h"
#include "MVKLayers.h"
#include "MVKObjectPool.h"
#include "MVKSmallVector.h"
#include "MVKPixelFormats.h"
#include "MVKOSExtensions.h"
#include "mvk_datatypes.hpp"
#include <string>
#include <mutex>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

class MVKInstance;
class MVKDevice;
class MVKQueue;
class MVKQueueFamily;
class MVKSurface;
class MVKSemaphoreImpl;
class MVKResource;
class MVKBuffer;
class MVKBufferView;
class MVKImage;
class MVKPresentableSwapchainImage;
class MVKImageView;
class MVKSwapchain;
class MVKDeviceMemory;
class MVKFence;
class MVKSemaphore;
class MVKTimelineSemaphore;
class MVKDeferredOperation;
class MVKEvent;
class MVKQueryPool;
class MVKShaderModule;
class MVKPipelineCache;
class MVKPipelineLayout;
class MVKPipeline;
class MVKSampler;
class MVKSamplerYcbcrConversion;
class MVKDescriptorSetLayout;
class MVKDescriptorPool;
class MVKDescriptorUpdateTemplate;
class MVKResourcesCommandEncoderState;
class MVKFramebuffer;
class MVKRenderPass;
class MVKCommandPool;
class MVKCommandEncoder;
class MVKCommandResourceFactory;
class MVKPrivateDataSlot;


/** The buffer index to use for vertex content. */
static constexpr uint32_t kMVKVertexContentBufferIndex = 0;

// Parameters to define the sizing of inline collections
static constexpr uint32_t   kMVKQueueFamilyCount = 4;
static constexpr uint32_t   kMVKQueueCountPerQueueFamily = 1;		// Must be 1. See comments in MVKPhysicalDevice::getQueueFamilies()
static constexpr uint32_t   kMVKMinSwapchainImageCount = 2;
static constexpr uint32_t   kMVKMaxSwapchainImageCount = 3;
static constexpr uint32_t   kMVKMaxColorAttachmentCount = 8;
static constexpr uint32_t   kMVKMaxViewportScissorCount = 16;
static constexpr uint32_t   kMVKMaxDescriptorSetCount = SPIRV_CROSS_NAMESPACE::kMaxArgumentBuffers;
static constexpr uint32_t   kMVKMaxSampleCount = 8;
static constexpr uint32_t   kMVKSampleLocationCoordinateGridSize = 16;
static constexpr float      kMVKMinSampleLocationCoordinate = 0.0;
static constexpr float      kMVKMaxSampleLocationCoordinate = (float)(kMVKSampleLocationCoordinateGridSize - 1) / (float)kMVKSampleLocationCoordinateGridSize;
static constexpr VkExtent2D kMVKSampleLocationPixelGridSize = { 1, 1 };
static constexpr VkExtent2D kMVKSampleLocationPixelGridSizeNotSupported = { 0, 0 };

#if !MVK_XCODE_12
typedef NSUInteger MTLTimestamp;
#endif


#pragma mark -
#pragma mark MVKMTLDeviceCapabilities

typedef struct MVKMTLDeviceCapabilities {
	bool supportsApple1;
	bool supportsApple2;
	bool supportsApple3;
	bool supportsApple4;
	bool supportsApple5;
	bool supportsApple6;
	bool supportsApple7;
	bool supportsApple8;
	bool supportsApple9;
	bool supportsMac1;
	bool supportsMac2;
	bool supportsMetal3;

	bool isAppleGPU;
	bool supportsBCTextureCompression;
	bool supportsDepth24Stencil8;
	bool supports32BitFloatFiltering;
	bool supports32BitMSAA;

	uint8_t getHighestAppleGPU() const;
	uint8_t getHighestMacGPU() const;

	MVKMTLDeviceCapabilities(id<MTLDevice> mtlDev);
} MVKMTLDeviceCapabilities;


#pragma mark -
#pragma mark MVKPhysicalDevice

typedef enum {
	MVKSemaphoreStyleUseMTLEvent,
	MVKSemaphoreStyleUseEmulation,
	MVKSemaphoreStyleSingleQueue,
} MVKSemaphoreStyle;

/** VkPhysicalDeviceVulkan12Features entries that did not originate in a prior extension. */
typedef struct MVKPhysicalDeviceVulkan12NoExtFeatures {
	VkBool32 samplerMirrorClampToEdge;
	VkBool32 drawIndirectCount;
	VkBool32 descriptorIndexing;
	VkBool32 samplerFilterMinmax;
	VkBool32 shaderOutputViewportIndex;
	VkBool32 shaderOutputLayer;
	VkBool32 subgroupBroadcastDynamicId;
} MVKPhysicalDeviceVulkan12NoExtFeatures;

/** VkPhysicalDeviceVulkan14Features entries that did not originate in a prior extension. */
typedef struct MVKPhysicalDeviceVulkan14NoExtFeatures {
	VkBool32 pushDescriptor;
} MVKPhysicalDeviceVulkan14NoExtFeatures;

/** Represents a Vulkan physical GPU device. */
class MVKPhysicalDevice : public MVKDispatchableVulkanAPIObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_PHYSICAL_DEVICE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_PHYSICAL_DEVICE_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _mvkInstance; }

	/** Populates the specified array with the supported extensions of this device. */
	VkResult getExtensionProperties(const char* pLayerName, uint32_t* pCount, VkExtensionProperties* pProperties);

	/** Populates the specified structure with the features of this device. */
	void getFeatures(VkPhysicalDeviceFeatures* features);

	/** Populates the specified structure with the features of this device. */
	void getFeatures(VkPhysicalDeviceFeatures2* features);

	/** Populates the specified structure with the properties of this device. */
	void getProperties(VkPhysicalDeviceProperties* properties);

	/** Populates the specified structure with the properties of this device. */
	void getProperties(VkPhysicalDeviceProperties2* properties);

	/** Returns the name of this device. */
	const char* getName() { return _properties.deviceName; }

	/** Populates the specified structure with the format properties of this device. */
	void getFormatProperties(VkFormat format, VkFormatProperties* pFormatProperties);

	/** Populates the specified structure with the format properties of this device. */
	void getFormatProperties(VkFormat format, VkFormatProperties2* pFormatProperties);

	/** Populates the specified structure with the multisample properties of this device. */
	void getMultisampleProperties(VkSampleCountFlagBits samples,
								  VkMultisamplePropertiesEXT* pMultisampleProperties);

	/** Populates the image format properties supported on this device. */
    VkResult getImageFormatProperties(VkFormat format,
                                      VkImageType type,
                                      VkImageTiling tiling,
                                      VkImageUsageFlags usage,
                                      VkImageCreateFlags flags,
                                      VkImageFormatProperties* pImageFormatProperties);

    /** Populates the image format properties supported on this device. */
    VkResult getImageFormatProperties(const VkPhysicalDeviceImageFormatInfo2* pImageFormatInfo,
                                      VkImageFormatProperties2* pImageFormatProperties);

	/** Populates the external buffer properties supported on this device. */
	void getExternalBufferProperties(const VkPhysicalDeviceExternalBufferInfo* pExternalBufferInfo,
									 VkExternalBufferProperties* pExternalBufferProperties);

	/** Populates the external fence properties supported on this device. */
	void getExternalFenceProperties(const VkPhysicalDeviceExternalFenceInfo* pExternalFenceInfo,
									VkExternalFenceProperties* pExternalFenceProperties);

	/** Populates the external semaphore properties supported on this device. */
	void getExternalSemaphoreProperties(const VkPhysicalDeviceExternalSemaphoreInfo* pExternalSemaphoreInfo,
										VkExternalSemaphoreProperties* pExternalSemaphoreProperties);

	/** Returns the supported time domains for calibration on this device. */
	VkResult getCalibrateableTimeDomains(uint32_t* pTimeDomainCount, VkTimeDomainEXT* pTimeDomains);

	/** Populates the specified structure with the tool properties of this device. */
	VkResult getToolProperties(uint32_t* pToolCount, VkPhysicalDeviceToolProperties* pToolProperties);

#pragma mark Surfaces

	/**
	 * Queries whether this device supports presentation to the specified surface,
	 * using a queue of the specified queue family.
	 */
	VkResult getSurfaceSupport(uint32_t queueFamilyIndex, MVKSurface* surface, VkBool32* pSupported);

	/** Returns the capabilities of the surface. */
	VkResult getSurfaceCapabilities(VkSurfaceKHR surface, VkSurfaceCapabilitiesKHR* pSurfaceCapabilities);

	/** Returns the capabilities of the surface. */
	VkResult getSurfaceCapabilities(const VkPhysicalDeviceSurfaceInfo2KHR* pSurfaceInfo,
									VkSurfaceCapabilities2KHR* pSurfaceCapabilities);

	/**
	 * Returns the pixel formats supported by the surface.
	 *
	 * If pSurfaceFormats is null, the value of pCount is updated with the number of
	 * pixel formats supported by the surface.
	 *
	 * If pSurfaceFormats is not null, then pCount formats are copied into the array.
	 * If the number of available formats is less than pCount, the value of pCount is
	 * updated to indicate the number of formats actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of supported
	 * formats is larger than pCount. Returns other values if an error occurs.
	 */
	VkResult getSurfaceFormats(MVKSurface* surface, uint32_t* pCount, VkSurfaceFormatKHR* pSurfaceFormats);

	/**
	 * Returns the pixel formats supported by the surface.
	 *
	 * If pSurfaceFormats is null, the value of pCount is updated with the number of
	 * pixel formats supported by the surface.
	 *
	 * If pSurfaceFormats is not null, then pCount formats are copied into the array.
	 * If the number of available formats is less than pCount, the value of pCount is
	 * updated to indicate the number of formats actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of supported
	 * formats is larger than pCount. Returns other values if an error occurs.
	 */
	VkResult getSurfaceFormats(MVKSurface* surface, uint32_t* pCount, VkSurfaceFormat2KHR* pSurfaceFormats);

	/**
	 * Returns the presentation modes supported by the surface.
	 *
	 * If pPresentModes is null, the value of pCount is updated with the number of
	 * presentation modes supported by the surface.
	 *
	 * If pPresentModes is not null, then pCount presentation modes are copied into the array.
	 * If the number of available modes is less than pCount, the value of pCount is updated
	 * to indicate the number of presentation modes actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of supported
	 * presentation modes is larger than pCount. Returns other values if an error occurs.
	 */
	VkResult getSurfacePresentModes(MVKSurface* surface, uint32_t* pCount, VkPresentModeKHR* pPresentModes);

	/**
	 * Returns the rectangles that will be used on the surface by this physical device
	 * when the surface is presented.
	 *
	 * If pRects is null, the value of pRectCount is updated with the number of
	 * rectangles used the surface by this physical device.
	 *
	 * If pRects is not null, then pCount rectangles are copied into the array.
	 * If the number of rectangles is less than pCount, the value of pCount is updated
	 * to indicate the number of rectangles actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of rectangles
	 * is larger than pCount. Returns other values if an error occurs.
	 */
	VkResult getPresentRectangles(MVKSurface* surface, uint32_t* pRectCount, VkRect2D* pRects);


#pragma mark Queues

	/**
	 * If pQueueFamilyProperties is null, the value of pCount is updated with the number of
	 * queue families supported by this instance.
	 *
	 * If pQueueFamilyProperties is not null, then pCount queue family properties are copied into
	 * the array. If the number of available queue families is less than pCount, the value of
	 * pCount is updated to indicate the number of queue families actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of queue families
	 * available in this instance is larger than the specified pCount. Returns other values if
	 * an error occurs.
	 */
	VkResult getQueueFamilyProperties(uint32_t* pCount, VkQueueFamilyProperties* pQueueFamilyProperties);

	/**
	 * If pQueueFamilyProperties is null, the value of pCount is updated with the number of
	 * queue families supported by this instance.
	 *
	 * If pQueueFamilyProperties is not null, then pCount queue family properties are copied into
	 * the array. If the number of available queue families is less than pCount, the value of 
	 * pCount is updated to indicate the number of queue families actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of queue families
	 * available in this instance is larger than the specified pCount. Returns other values if
	 * an error occurs.
	 */
	VkResult getQueueFamilyProperties(uint32_t* pCount, VkQueueFamilyProperties2KHR* pQueueFamilyProperties);


#pragma mark Memory models

	/** Returns a pointer to the memory characteristics of this device. */
    const VkPhysicalDeviceMemoryProperties* getMemoryProperties() { return &_memoryProperties; }

	/** Populates the specified memory properties with the memory characteristics of this device. */
	VkResult getMemoryProperties(VkPhysicalDeviceMemoryProperties* pMemoryProperties);

	/** Populates the specified memory properties with the memory characteristics of this device. */
	VkResult getMemoryProperties(VkPhysicalDeviceMemoryProperties2* pMemoryProperties);

	/**
	 * Returns a bit mask of all memory type indices. 
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	uint32_t getAllMemoryTypes() const { return _allMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that allow host visibility to the memory. 
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	uint32_t getHostVisibleMemoryTypes() const { return _hostVisibleMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that are coherent between host and device.
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	uint32_t getHostCoherentMemoryTypes() const { return _hostCoherentMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that do NOT allow host visibility to the memory.
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	uint32_t getPrivateMemoryTypes() const { return _privateMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that are lazily allocated.
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	uint32_t getLazilyAllocatedMemoryTypes() const { return _lazilyAllocatedMemoryTypes; }

	/** Returns the external memory properties supported for buffers for the handle type. */
	VkExternalMemoryProperties& getExternalBufferProperties(VkExternalMemoryHandleTypeFlagBits handleType);

	/** Returns the external memory properties supported for images for the handle type. */
	VkExternalMemoryProperties& getExternalImageProperties(VkFormat format, VkExternalMemoryHandleTypeFlagBits handleType);

	uint32_t getExternalResourceMemoryTypeBits(VkExternalMemoryHandleTypeFlagBits handleType, const void* handle) const;

	/** Returns the amount of memory currently consumed by the GPU. */
	size_t getCurrentAllocatedSize();


#pragma mark Metal

	/** Populates the specified structure with the Metal-specific features of this device. */
	const MVKPhysicalDeviceMetalFeatures* getMetalFeatures() { return &_metalFeatures; }

	/** Returns whether or not vertex instancing can be used to implement multiview. */
	bool canUseInstancingForMultiview() { return _metalFeatures.layeredRendering && _metalFeatures.deferredStoreActions; }

	/** Returns the underlying Metal device. */
	id<MTLDevice> getMTLDevice() { return _mtlDevice; }

	/** Returns whether the MSL version is supported on this device. */
	bool mslVersionIsAtLeast(MTLLanguageVersion minVer) { return _metalFeatures.mslVersionEnum >= minVer; }

	/** Returns the MTLStorageMode that matches the Vulkan memory property flags. */
	MTLStorageMode getMTLStorageModeFromVkMemoryPropertyFlags(VkMemoryPropertyFlags vkFlags);

	/** Returns the MTLDevice capabilities. */
	const MVKMTLDeviceCapabilities getMTLDeviceCapabilities() { return _gpuCapabilities; }


#pragma mark Construction

	/** Constructs an instance wrapping the specified Vulkan instance and Metal device. */
	MVKPhysicalDevice(MVKInstance* mvkInstance, id<MTLDevice> mtlDevice);

	/** Default destructor. */
	~MVKPhysicalDevice() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKPhysicalDevice() method.
     */
    VkPhysicalDevice getVkPhysicalDevice() { return (VkPhysicalDevice)getVkHandle(); }

    /**
     * Retrieves the MVKPhysicalDevice instance referenced by the VkPhysicalDevice handle.
     * This is the compliment of the getVkPhysicalDevice() method.
     */
    static inline MVKPhysicalDevice* getMVKPhysicalDevice(VkPhysicalDevice vkPhysicalDevice) {
        return (MVKPhysicalDevice*)getDispatchableObject(vkPhysicalDevice);
    }

protected:
	friend class MVKDevice;
	friend class MVKDeviceTrackingMixin;

	void propagateDebugName() override {}
	MTLFeatureSet getMaximalMTLFeatureSet();
    void initMetalFeatures();
	void initFeatures();
	void initMTLDevice();
	void initProperties();
	void initLimits();
	void initGPUInfoProperties();
	void initMemoryProperties();
	void initVkSemaphoreStyle();
	void setMemoryHeap(uint32_t heapIndex, VkDeviceSize heapSize, VkMemoryHeapFlags heapFlags);
	void setMemoryType(uint32_t typeIndex, uint32_t heapIndex, VkMemoryPropertyFlags propertyFlags);
	uint64_t getVRAMSize();
	uint64_t getRecommendedMaxWorkingSetSize();
	uint32_t getMaxSamplerCount();
	uint32_t getMaxPerSetDescriptorCount();
	void initExternalMemoryProperties();
	void initExtensions();
	void initCounterSets();
	bool needsCounterSetRetained();
	void updateTimestampPeriod();
	MVKArrayRef<MVKQueueFamily*> getQueueFamilies();
	void initPipelineCacheUUID();
	uint32_t getHighestGPUCapability();
	uint32_t getMoltenVKGitRevision();
	void populateDeviceIDProperties(VkPhysicalDeviceVulkan11Properties* pVk11Props);
	void populateSubgroupProperties(VkPhysicalDeviceVulkan11Properties* pVk11Props);
	template<typename HostImageCopyProps> void populateHostImageCopyProperties(HostImageCopyProps* pHostImageCopyProps);
	void logGPUInfo();

	MVKInstance* _mvkInstance;
	id<MTLDevice> _mtlDevice;
	const MVKMTLDeviceCapabilities _gpuCapabilities;
	const MVKExtensionList _supportedExtensions;
	MVKPixelFormats _pixelFormats;
	VkPhysicalDeviceFeatures _features;
	MVKPhysicalDeviceVulkan12NoExtFeatures _vulkan12NoExtFeatures;
	MVKPhysicalDeviceVulkan14NoExtFeatures _vulkan14NoExtFeatures;
	MVKPhysicalDeviceMetalFeatures _metalFeatures;
	VkPhysicalDeviceProperties _properties;
	VkPhysicalDeviceTexelBufferAlignmentProperties _texelBuffAlignProperties;
	VkPhysicalDeviceMemoryProperties _memoryProperties;
	MVKSmallVector<MVKQueueFamily*, kMVKQueueFamilyCount> _queueFamilies;
	VkExternalMemoryProperties _hostPointerExternalMemoryProperties;
	VkExternalMemoryProperties _mtlBufferExternalMemoryProperties;
	VkExternalMemoryProperties _mtlTextureExternalMemoryProperties;
	VkExternalMemoryProperties _mtlTextureHeapExternalMemoryProperties;
	id<MTLCounterSet> _timestampMTLCounterSet;
	MVKSemaphoreStyle _vkSemaphoreStyle;
	MTLTimestamp _prevCPUTimestamp = 0;
	MTLTimestamp _prevGPUTimestamp = 0;
	uint32_t _allMemoryTypes;
	uint32_t _hostVisibleMemoryTypes;
	uint32_t _hostCoherentMemoryTypes;
	uint32_t _privateMemoryTypes;
	uint32_t _lazilyAllocatedMemoryTypes;
	bool _hasUnifiedMemory = true;
	bool _isUsingMetalArgumentBuffers = true;
};


#pragma mark -
#pragma mark MVKDevice

typedef enum {
	MVKActivityPerformanceValueTypeDuration,
	MVKActivityPerformanceValueTypeByteCount,
} MVKActivityPerformanceValueType;

typedef struct MVKMTLBlitEncoder {
	id<MTLBlitCommandEncoder> mtlBlitEncoder = nil;
	id<MTLCommandBuffer> mtlCmdBuffer = nil;
} MVKMTLBlitEncoder;

// Arbitrary, after that many barriers with a given source pipeline stage we will wrap around
// and potentially introduce extra synchronization on previous invocations of the same stage.
static const uint32_t kMVKBarrierFenceCount = 64;

/** Represents a Vulkan logical GPU device, associated with a physical device. */
class MVKDevice : public MVKDispatchableVulkanAPIObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DEVICE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DEVICE_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _physicalDevice->_mvkInstance; }

	const MVKPhysicalDevice* getPhysicalDevice() const { return _physicalDevice; }

	/** Returns the name of this device. */
	const char* getName() { return _physicalDevice->_properties.deviceName; }

    /** Returns the common resource factory for creating command resources. */
    MVKCommandResourceFactory* getCommandResourceFactory() { return _commandResourceFactory; }

	/** Returns the function pointer corresponding to the specified named entry point. */
	PFN_vkVoidFunction getProcAddr(const char* pName);

	/** Returns the queue at the specified index within the specified family. */
	MVKQueue* getQueue(uint32_t queueFamilyIndex, uint32_t queueIndex);

	/** Returns the queue described by the specified structure. */
	MVKQueue* getQueue(const VkDeviceQueueInfo2* queueInfo);

	/** Retrieves the queue at the lowest queue and queue family indices used by the app. */
	MVKQueue* getAnyQueue();

	/** Block the current thread until all queues in this device are idle. */
	VkResult waitIdle();
	
	/** Mark this device (and optionally the physical device) as lost. Releases all waits for this device. */
	VkResult markLost(bool alsoMarkPhysicalDevice = false);

	/** Returns whether or not the given descriptor set layout is supported. */
	void getDescriptorSetLayoutSupport(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
									   VkDescriptorSetLayoutSupport* pSupport);

	/** Populates the device group presentation capabilities. */
	VkResult getDeviceGroupPresentCapabilities(VkDeviceGroupPresentCapabilitiesKHR* pDeviceGroupPresentCapabilities);

	/** Populates the device group surface presentation modes. */
	VkResult getDeviceGroupSurfacePresentModes(MVKSurface* surface, VkDeviceGroupPresentModeFlagsKHR* pModes);

	/** Populates the device group peer memory features. */
	void getPeerMemoryFeatures(uint32_t heapIndex, uint32_t localDevice, uint32_t remoteDevice, VkPeerMemoryFeatureFlags* pPeerMemoryFeatures);

	/** Returns the properties of the host memory pointer. */
	VkResult getMemoryHostPointerProperties(VkExternalMemoryHandleTypeFlagBits handleType,
											const void* pHostPointer,
											VkMemoryHostPointerPropertiesEXT* pMemHostPtrProps);

	/** Samples timestamps from the specified domains and returns the sampled values. */
	void getCalibratedTimestamps(uint32_t timestampCount,
								 const VkCalibratedTimestampInfoEXT* pTimestampInfos,
								 uint64_t* pTimestamps,
								 uint64_t* pMaxDeviation);

    /** Returns the granularity of the dynamic rendering optimal render area.  */
    VkExtent2D getDynamicRenderAreaGranularity();

#pragma mark Object lifecycle

	MVKBuffer* createBuffer(const VkBufferCreateInfo* pCreateInfo,
							const VkAllocationCallbacks* pAllocator);
	void destroyBuffer(MVKBuffer* mvkBuff,
					   const VkAllocationCallbacks* pAllocator);

    MVKBufferView* createBufferView(const VkBufferViewCreateInfo* pCreateInfo,
                                    const VkAllocationCallbacks* pAllocator);
    void destroyBufferView(MVKBufferView* mvkBuffView,
                       const VkAllocationCallbacks* pAllocator);

	MVKImage* createImage(const VkImageCreateInfo* pCreateInfo,
						  const VkAllocationCallbacks* pAllocator);
	void destroyImage(MVKImage* mvkImg,
					  const VkAllocationCallbacks* pAllocator);

	MVKImageView* createImageView(const VkImageViewCreateInfo* pCreateInfo,
								  const VkAllocationCallbacks* pAllocator);
	void destroyImageView(MVKImageView* mvkImgView, const VkAllocationCallbacks* pAllocator);

	MVKSwapchain* createSwapchain(const VkSwapchainCreateInfoKHR* pCreateInfo,
								  const VkAllocationCallbacks* pAllocator);
	void destroySwapchain(MVKSwapchain* mvkSwpChn,
						  const VkAllocationCallbacks* pAllocator);

	MVKPresentableSwapchainImage* createPresentableSwapchainImage(const VkImageCreateInfo* pCreateInfo,
																  MVKSwapchain* swapchain,
																  uint32_t swapchainIndex,
																  const VkAllocationCallbacks* pAllocator);
	void destroyPresentableSwapchainImage(MVKPresentableSwapchainImage* mvkImg,
										  const VkAllocationCallbacks* pAllocator);

	MVKFence* createFence(const VkFenceCreateInfo* pCreateInfo,
						  const VkAllocationCallbacks* pAllocator);
	void destroyFence(MVKFence* mvkFence,
					  const VkAllocationCallbacks* pAllocator);

	MVKSemaphore* createSemaphore(const VkSemaphoreCreateInfo* pCreateInfo,
								  const VkAllocationCallbacks* pAllocator);
	void destroySemaphore(MVKSemaphore* mvkSem4,
						  const VkAllocationCallbacks* pAllocator);
    
    MVKDeferredOperation* createDeferredOperation(const VkAllocationCallbacks* pAllocator);
    void destroyDeferredOperation(MVKDeferredOperation* mvkDeferredOperation,
                                  const VkAllocationCallbacks* pAllocator);

	MVKEvent* createEvent(const VkEventCreateInfo* pCreateInfo,
						  const VkAllocationCallbacks* pAllocator);
	void destroyEvent(MVKEvent* mvkEvent,
					  const VkAllocationCallbacks* pAllocator);

	MVKQueryPool* createQueryPool(const VkQueryPoolCreateInfo* pCreateInfo,
								  const VkAllocationCallbacks* pAllocator);
	void destroyQueryPool(MVKQueryPool* mvkQP,
						  const VkAllocationCallbacks* pAllocator);

	MVKShaderModule* createShaderModule(const VkShaderModuleCreateInfo* pCreateInfo,
										const VkAllocationCallbacks* pAllocator);
	void destroyShaderModule(MVKShaderModule* mvkShdrMod,
							 const VkAllocationCallbacks* pAllocator);

	MVKPipelineCache* createPipelineCache(const VkPipelineCacheCreateInfo* pCreateInfo,
										  const VkAllocationCallbacks* pAllocator);
	void destroyPipelineCache(MVKPipelineCache* mvkPLC,
							  const VkAllocationCallbacks* pAllocator);

	MVKPipelineLayout* createPipelineLayout(const VkPipelineLayoutCreateInfo* pCreateInfo,
											const VkAllocationCallbacks* pAllocator);
	void destroyPipelineLayout(MVKPipelineLayout* mvkPLL,
							   const VkAllocationCallbacks* pAllocator);

    /**
     * Template function that creates count number of pipelines of type PipelineType,
     * using a collection of configuration information of type PipelineInfoType,
     * and adds the new pipelines to the specified pipeline cache.
     */
    template<typename PipelineType, typename PipelineInfoType>
    VkResult createPipelines(VkPipelineCache pipelineCache,
                             uint32_t count,
                             const PipelineInfoType* pCreateInfos,
                             const VkAllocationCallbacks* pAllocator,
                             VkPipeline* pPipelines);
    void destroyPipeline(MVKPipeline* mvkPPL,
                         const VkAllocationCallbacks* pAllocator);

	MVKSampler* createSampler(const VkSamplerCreateInfo* pCreateInfo,
							  const VkAllocationCallbacks* pAllocator);
	void destroySampler(MVKSampler* mvkSamp,
						const VkAllocationCallbacks* pAllocator);

	MVKSamplerYcbcrConversion* createSamplerYcbcrConversion(const VkSamplerYcbcrConversionCreateInfo* pCreateInfo,
										                    const VkAllocationCallbacks* pAllocator);
	void destroySamplerYcbcrConversion(MVKSamplerYcbcrConversion* mvkSampConv,
								       const VkAllocationCallbacks* pAllocator);

	MVKDescriptorSetLayout* createDescriptorSetLayout(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
													  const VkAllocationCallbacks* pAllocator);
	void destroyDescriptorSetLayout(MVKDescriptorSetLayout* mvkDSL,
									const VkAllocationCallbacks* pAllocator);

	MVKDescriptorPool* createDescriptorPool(const VkDescriptorPoolCreateInfo* pCreateInfo,
											const VkAllocationCallbacks* pAllocator);
	void destroyDescriptorPool(MVKDescriptorPool* mvkDP,
							   const VkAllocationCallbacks* pAllocator);

	MVKDescriptorUpdateTemplate* createDescriptorUpdateTemplate(const VkDescriptorUpdateTemplateCreateInfo* pCreateInfo,
																const VkAllocationCallbacks* pAllocator);
	void destroyDescriptorUpdateTemplate(MVKDescriptorUpdateTemplate* mvkDUT,
										 const VkAllocationCallbacks* pAllocator);

	MVKFramebuffer* createFramebuffer(const VkFramebufferCreateInfo* pCreateInfo,
									  const VkAllocationCallbacks* pAllocator);
	MVKFramebuffer* createFramebuffer(const VkRenderingInfo* pRenderingInfo,
									  const VkAllocationCallbacks* pAllocator);
	void destroyFramebuffer(MVKFramebuffer* mvkFB,
							const VkAllocationCallbacks* pAllocator);

	MVKRenderPass* createRenderPass(const VkRenderPassCreateInfo* pCreateInfo,
									const VkAllocationCallbacks* pAllocator);
	MVKRenderPass* createRenderPass(const VkRenderPassCreateInfo2* pCreateInfo,
									const VkAllocationCallbacks* pAllocator);
	MVKRenderPass* createRenderPass(const VkRenderingInfo* pRenderingInfo,
									const VkAllocationCallbacks* pAllocator);
	void destroyRenderPass(MVKRenderPass* mvkRP,
						   const VkAllocationCallbacks* pAllocator);

	MVKCommandPool* createCommandPool(const VkCommandPoolCreateInfo* pCreateInfo,
									  const VkAllocationCallbacks* pAllocator);
	void destroyCommandPool(MVKCommandPool* mvkCmdPool,
							const VkAllocationCallbacks* pAllocator);

	MVKDeviceMemory* allocateMemory(const VkMemoryAllocateInfo* pAllocateInfo,
									const VkAllocationCallbacks* pAllocator);
	void freeMemory(MVKDeviceMemory* mvkDevMem,
					const VkAllocationCallbacks* pAllocator);

	VkResult createPrivateDataSlot(const VkPrivateDataSlotCreateInfoEXT* pCreateInfo,
								   const VkAllocationCallbacks* pAllocator,
								   VkPrivateDataSlot* pPrivateDataSlot);

	void destroyPrivateDataSlot(VkPrivateDataSlot privateDataSlot,
								const VkAllocationCallbacks* pAllocator);


#pragma mark Operations

	/** Tell the GPU to be ready to use any of the GPU-addressable buffers. */
	void encodeGPUAddressableBuffers(MVKResourcesCommandEncoderState* rezEncState,
										 MVKShaderStage stage);

	/** Adds the specified host semaphore to be woken upon device loss. */
	void addSemaphore(MVKSemaphoreImpl* sem4);

	/** Removes the specified host semaphore. */
	void removeSemaphore(MVKSemaphoreImpl* sem4);

	/** Adds the specified timeline semaphore to be woken at the specified value upon device loss. */
	void addTimelineSemaphore(MVKTimelineSemaphore* sem4, uint64_t value);

	/** Removes the specified timeline semaphore. */
	void removeTimelineSemaphore(MVKTimelineSemaphore* sem4, uint64_t value);

	/** Applies the specified global memory barrier to all resource issued by this device. */
	void applyMemoryBarrier(MVKPipelineBarrier& barrier,
							MVKCommandEncoder* cmdEncoder,
							MVKCommandUse cmdUse);

	/** Invalidates the memory regions. */
	VkResult invalidateMappedMemoryRanges(uint32_t memRangeCount, const VkMappedMemoryRange* pMemRanges);

	/** Returns the number of Metal render passes needed to render all views. */
	uint32_t getMultiviewMetalPassCount(uint32_t viewMask) const;

	/** Returns the first view to be rendered in the given multiview pass. */
	uint32_t getFirstViewIndexInMetalPass(uint32_t viewMask, uint32_t passIdx) const;

	/** Returns the number of views to be rendered in the given multiview pass. */
	uint32_t getViewCountInMetalPass(uint32_t viewMask, uint32_t passIdx) const;

	/** Populates the specified statistics structure from the current activity performance statistics. */
	void getPerformanceStatistics(MVKPerformanceStatistics* pPerf);

	/** Log all performance statistics. */
	void logPerformanceSummary();


#pragma mark Metal

	/**
	 * Returns an autoreleased options object to be used when compiling MSL shaders.
	 * The requestFastMath parameter is combined with the value of MVKConfiguration::fastMathEnabled
	 * to determine whether to enable fast math optimizations in the compiled shader.
	 * The preserveInvariance parameter indicates that the shader requires the position
	 * output invariance across invocations (typically for the position output).
	 */
	MTLCompileOptions* getMTLCompileOptions(bool requestFastMath = true, bool preserveInvariance = false);

	/** Returns the Metal vertex buffer index to use for the specified vertex attribute binding number.  */
	uint32_t getMetalBufferIndexForVertexAttributeBinding(uint32_t binding);

	/** Returns the memory alignment required for the format when used in a texel buffer. */
	VkDeviceSize getVkFormatTexelBufferAlignment(VkFormat format, MVKBaseObject* mvkObj);

    /** 
     * Returns the MTLBuffer used to hold occlusion query results, 
     * when all query pools use the same MTLBuffer.
     */
    id<MTLBuffer> getGlobalVisibilityResultMTLBuffer();

    /**
     * Expands the visibility results buffer, used for occlusion queries, by replacing the
     * existing buffer with a new MTLBuffer that is large enough to accommodate all occlusion
     * queries created to date, including those defined in the specified query pool.
     * Returns the previous query count, before the new queries were added, which can
     * be used by the new query pool to locate its queries within the single large buffer.
     */
    uint32_t expandVisibilityResultMTLBuffer(uint32_t queryCount);

	/** Returns the GPU sample counter used for timestamps. */
	id<MTLCounterSet> getTimestampMTLCounterSet() { return _physicalDevice->_timestampMTLCounterSet; }

    /** Returns the memory type index corresponding to the specified Metal memory storage mode. */
    uint32_t getVulkanMemoryTypeIndex(MTLStorageMode mtlStorageMode);

	/** Returns a default MTLSamplerState to populate empty array element descriptors. */
	id<MTLSamplerState> getDefaultMTLSamplerState();

	/**
	 * Returns a MTLBuffer of length one that can be used as a dummy to
	 * create a no-op BLIT encoder based on filling this single-byte buffer.
	 */
	id<MTLBuffer> getDummyBlitMTLBuffer();

	/**
	 * Returns whether MTLCommandBuffers can be prefilled.
	 *
	 * This depends both on whether the app config has requested prefilling, and whether doing so will
	 * interfere with other requested features, such as updating resource descriptors after bindings.
	 */
	bool shouldPrefillMTLCommandBuffers();

	/**
	 * Checks if automatic GPU capture is supported, and is enabled for the specified auto
	 * capture scope, and if so, starts capturing from the specified Metal capture object.
	 * The capture will be made either to Xcode, or to a file if one has been configured.
	 *
	 * The mtlCaptureObject must be one of:
	 *   - MTLDevice for scope MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_DEVICE
	 *   - MTLCommandQueue for scopes MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_FRAME
	 *       and MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE_ON_DEMAND.
	 */
	void startAutoGPUCapture(MVKConfigAutoGPUCaptureScope autoGPUCaptureScope, id mtlCaptureObject);

	/**
	 * Checks if automatic GPU capture is enabled for the specified
	 * auto capture scope, and if so, stops capturing.
	 */
	void stopAutoGPUCapture(MVKConfigAutoGPUCaptureScope autoGPUCaptureScope);

	/** Returns whether this instance is currently automatically capturing a GPU trace. */
	bool isCurrentlyAutoGPUCapturing() { return _isCurrentlyAutoGPUCapturing; }

	/** Returns the Metal objects underpinning the Vulkan objects indicated in the pNext chain of pMetalObjectsInfo. */
	void getMetalObjects(VkExportMetalObjectsInfoEXT* pMetalObjectsInfo);

	void* getResourceIdFromHandle(const VkMemoryGetMetalHandleInfoEXT* pGetMetalHandleInfo) const;

#if !MVK_XCODE_16
	void makeResident(id allocation) {}
#else
	void makeResident(id<MTLAllocation> allocation) {
		@synchronized(_residencySet) {
			[_residencySet addAllocation: allocation];
			[_residencySet commit];
		}
	}
#endif

#if !MVK_XCODE_16
	void removeResidency(id allocation) {}
#else
	void removeResidency(id<MTLAllocation> allocation) {
		@synchronized(_residencySet) {
			[_residencySet removeAllocation:allocation];
			[_residencySet commit];
		}
	}
#endif

	void addResidencySet(id<MTLCommandQueue> queue) {
#if MVK_XCODE_16
		if (_residencySet) [queue addResidencySet:_residencySet];
#endif
	}

	void removeResidencySet(id<MTLCommandQueue> queue) {
#if MVK_XCODE_16
		if (_residencySet) [queue removeResidencySet:_residencySet];
#endif
	}

	bool hasResidencySet() {
#if MVK_XCODE_16
		return _residencySet != nil;
#else
		return false;
#endif
	}

#pragma mark Construction

	/** Constructs an instance on the specified physical device. */
	MVKDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo);

	~MVKDevice() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKDevice() method.
     */
    VkDevice getVkDevice() { return (VkDevice)getVkHandle(); }

    /**
     * Retrieves the MVKDevice instance referenced by the VkDevice handle.
     * This is the compliment of the getVkDevice() method.
     */
    static inline MVKDevice* getMVKDevice(VkDevice vkDevice) {
        return (MVKDevice*)getDispatchableObject(vkDevice);
    }

#pragma mark Barriers

	/** Returns a Metal fence to update for the given barrier stage. */
	id<MTLFence> getBarrierStageFence(id<MTLCommandBuffer> mtlCommandBuffer, MVKBarrierStage stage);

	/** Returns a Metal fence by its stage and slot index. */
	id<MTLFence> getFence(MVKBarrierStage stage, int index) {
		return _barrierFences[stage][index];
	}

protected:
	friend class MVKDeviceTrackingMixin;

	void propagateDebugName() override  {}
	MVKBuffer* addBuffer(MVKBuffer* mvkBuff);
	MVKBuffer* removeBuffer(MVKBuffer* mvkBuff);
	MVKImage* addImage(MVKImage* mvkImg);
	MVKImage* removeImage(MVKImage* mvkImg);
    void initPerformanceTracking();
	void initPhysicalDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo);
	void initQueues(const VkDeviceCreateInfo* pCreateInfo);
	void reservePrivateData(const VkDeviceCreateInfo* pCreateInfo);
	void enableFeatures(const VkDeviceCreateInfo* pCreateInfo);
	template<typename S> void enableFeatures(S* pEnabled, const S* pRequested, const S* pAvailable, uint32_t count);
	template<typename S> void enableFeatures(S* pRequested, VkBool32* pEnabledBools, const VkBool32* pRequestedBools, const VkBool32* pAvailableBools, uint32_t count);
	void enableExtensions(const VkDeviceCreateInfo* pCreateInfo);
	void updateActivityPerformance(MVKPerformanceTracker& activity, double currentValue);
    const char* getActivityPerformanceDescription(MVKPerformanceTracker& activity, MVKPerformanceStatistics& perfStats);
	MVKActivityPerformanceValueType getActivityPerformanceValueType(MVKPerformanceTracker& activity, MVKPerformanceStatistics& perfStats);
	void logActivityInline(MVKPerformanceTracker& activity, MVKPerformanceStatistics& perfStats);
	void logActivityDuration(MVKPerformanceTracker& activity, MVKPerformanceStatistics& perfStats, bool isInline = false);
	void logActivityByteCount(MVKPerformanceTracker& activity, MVKPerformanceStatistics& perfStats, bool isInline = false);
	void getDescriptorVariableDescriptorCountLayoutSupport(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
														   VkDescriptorSetLayoutSupport* pSupport,
														   VkDescriptorSetVariableDescriptorCountLayoutSupport* pVarDescSetCountSupport);
	bool readGPUCapturePipe() { char dummy; return _capturePipeFileDesc >= 0 && read(_capturePipeFileDesc, &dummy, 1) > 0; };

	MVKPhysicalDevice* _physicalDevice = nullptr;
	MVKExtensionList _enabledExtensions;
	VkPhysicalDeviceFeatures _enabledFeatures;
	MVKPhysicalDeviceVulkan12NoExtFeatures _enabledVulkan12NoExtFeatures;
	MVKPhysicalDeviceVulkan14NoExtFeatures _enabledVulkan14NoExtFeatures;

	// List of extended device feature enabling structures, as member variables.
#define MVK_DEVICE_FEATURE(structName, enumName, flagCount) \
	VkPhysicalDevice##structName##Features _enabled##structName##Features;
#define MVK_DEVICE_FEATURE_EXTN(structName, enumName, extnSfx, flagCount) \
	VkPhysicalDevice##structName##Features##extnSfx _enabled##structName##Features;
#include "MVKDeviceFeatureStructs.def"

	id<MTLFence> _barrierFences[kMVKBarrierStageCount][kMVKBarrierFenceCount];

	MVKPerformanceStatistics _performanceStats;
    MVKCommandResourceFactory* _commandResourceFactory = nullptr;
	MVKSmallVector<MVKSmallVector<MVKQueue*, kMVKQueueCountPerQueueFamily>, kMVKQueueFamilyCount> _queuesByQueueFamilyIndex;
	MVKSmallVector<MVKResource*> _resources;
	MVKSmallVector<MVKBuffer*> _gpuAddressableBuffers;
	MVKSmallVector<MVKPrivateDataSlot*> _privateDataSlots;
	MVKSmallVector<bool> _privateDataSlotsAvailability;
	MVKSmallVector<MVKSemaphoreImpl*> _awaitingSemaphores;
	MVKSmallVector<std::pair<MVKTimelineSemaphore*, uint64_t>> _awaitingTimelineSem4s;
	std::mutex _rezLock;
	std::mutex _sem4Lock;
    std::mutex _perfLock;
	std::mutex _vizLock;
	std::string _capturePipeFileName;
    id<MTLBuffer> _globalVisibilityResultMTLBuffer = nil;
	id<MTLSamplerState> _defaultMTLSamplerState = nil;
	id<MTLBuffer> _dummyBlitMTLBuffer = nil;
#if MVK_XCODE_16
	id<MTLResidencySet> _residencySet = nil;
#endif
    uint32_t _globalVisibilityQueryCount = 0;
	int _capturePipeFileDesc = -1;
	bool _isPerformanceTracking = false;
	bool _isCurrentlyAutoGPUCapturing = false;

};


#pragma mark -
#pragma mark MVKDeviceTrackingMixin

/**
 * This mixin class adds the ability for an object to track the device that created it.
 *
 * As a mixin, this class should only be used as a component of multiple inheritance.
 * Any class that inherits from this class should also inherit from MVKBaseObject.
 * This requirement is to avoid the diamond problem of multiple inheritance.
 */
class MVKDeviceTrackingMixin {

public:

	/** Returns the device for which this object was created. */
	MVKDevice* getDevice() { return _device; }

	/** Returns the physical device underlying this logical device. */
	MVKPhysicalDevice* getPhysicalDevice() { return _device->_physicalDevice; }

	/** Returns the underlying Metal device. */
	id<MTLDevice> getMTLDevice() { return _device->_physicalDevice->_mtlDevice; }

	/** Returns whether the GPU is a unified memory device. */
	bool isUnifiedMemoryGPU() { return _device->_physicalDevice->_hasUnifiedMemory; }

	/** Returns whether the GPU is Apple Silicon. */
	bool isAppleGPU() { return _device->_physicalDevice->_gpuCapabilities.isAppleGPU; }

	/** Returns whether this device is using one Metal argument buffer for each descriptor set, on multiple pipeline and pipeline stages. */
	virtual bool isUsingMetalArgumentBuffers() { return _device->_physicalDevice->_isUsingMetalArgumentBuffers; };

	/** Returns whether this device needs Metal argument buffer encoders to populate argument buffer content. */
	bool needsMetalArgumentBufferEncoders() { return _device->_physicalDevice->_metalFeatures.needsArgumentBufferEncoders; };

	/** Returns info about the pixel format supported by the physical device. */
	MVKPixelFormats* getPixelFormats() { return &_device->_physicalDevice->_pixelFormats; }

	/** The list of Vulkan extensions, indicating whether each has been enabled by the app for this device. */
	MVKExtensionList& getEnabledExtensions() { return _device->_enabledExtensions; }

	/** Device features available and enabled. */
	VkPhysicalDeviceFeatures& getEnabledFeatures() { return _device->_enabledFeatures; }

	// List of extended device feature enabling structures, as getEnabledXXXFeatures() functions.
#define MVK_DEVICE_FEATURE(structName, enumName, flagCount) \
	VkPhysicalDevice##structName##Features& getEnabled##structName##Features() { return _device->_enabled##structName##Features; }
#define MVK_DEVICE_FEATURE_EXTN(structName, enumName, extnSfx, flagCount) \
	VkPhysicalDevice##structName##Features##extnSfx& getEnabled##structName##Features() { return _device->_enabled##structName##Features; }
#include "MVKDeviceFeatureStructs.def"

	/** Pointer to the Metal-specific features of the underlying physical device. */
	const MVKPhysicalDeviceMetalFeatures& getMetalFeatures() { return _device->_physicalDevice->_metalFeatures; }

	/** Pointer to the properties of the underlying physical device. */
	const VkPhysicalDeviceProperties& getDeviceProperties() { return _device->_physicalDevice->_properties; }

	/** Pointer to the memory properties of the underlying physical device. */
	const VkPhysicalDeviceMemoryProperties& getDeviceMemoryProperties() { return _device->_physicalDevice->_memoryProperties; }

	/** Performance statistics. */
	MVKPerformanceStatistics& getPerformanceStats() { return _device->_performanceStats; }

	/**
	 * If performance is being tracked, returns a monotonic timestamp value for use performance timestamping.
	 * The returned value corresponds to the number of CPU "ticks" since the app was initialized.
	 *
	 * Call this function twice, then use the functions mvkGetElapsedNanoseconds() or mvkGetElapsedMilliseconds()
	 * to determine the number of nanoseconds or milliseconds between the two calls.
	 */
	uint64_t getPerformanceTimestamp() { return _device->_isPerformanceTracking ? mvkGetTimestamp() : 0; }

	/**
	 * If performance is being tracked, adds the performance for an activity with a duration interval
	 * between the start and end times, measured in milliseconds, to the given performance statistics.
	 *
	 * If endTime is zero or not supplied, the current time is used.
	 * If addAlways is true, the duration is tracked even if performance tracking is disabled.
	 */
	void addPerformanceInterval(MVKPerformanceTracker& perfTracker, uint64_t startTime, uint64_t endTime = 0, bool addAlways = false) {
		if (_device->_isPerformanceTracking || addAlways) {
			_device->updateActivityPerformance(perfTracker, mvkGetElapsedMilliseconds(startTime, endTime));
		}
	};

	/** Constructs an instance for the specified device. */
	MVKDeviceTrackingMixin(MVKDevice* device) : _device(device) { assert(_device); }

	virtual ~MVKDeviceTrackingMixin() {}

protected:
	MVKDevice* _device;
};


#pragma mark -
#pragma mark MVKBaseDeviceObject

/** Represents an object that is spawned from a Vulkan device, and tracks that device. */
class MVKBaseDeviceObject : public MVKBaseObject, public MVKDeviceTrackingMixin {

public:

	/** Constructs an instance for the specified device. */
	MVKBaseDeviceObject(MVKDevice* device) : MVKDeviceTrackingMixin(device) {}
};


#pragma mark -
#pragma mark MVKVulkanAPIDeviceObject

/** Abstract class that represents an opaque Vulkan API handle object spawned from a Vulkan device. */
class MVKVulkanAPIDeviceObject : public MVKVulkanAPIObject, public MVKDeviceTrackingMixin {

public:

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _device ? _device->getInstance() : nullptr; }

	/** Constructs an instance for the specified device. */
	MVKVulkanAPIDeviceObject(MVKDevice* device) : MVKDeviceTrackingMixin(device) {}
};


#pragma mark -
#pragma mark MVKPrivateDataSlot

/** Private data slot. */
class MVKPrivateDataSlot : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_PRIVATE_DATA_SLOT; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_UNKNOWN_EXT; }

	void setData(VkObjectType objectType, uint64_t objectHandle, uint64_t data) { _privateData[objectHandle] = data; }

	uint64_t getData(VkObjectType objectType, uint64_t objectHandle) { return _privateData[objectHandle]; }

	void clearData() { _privateData.clear(); }

	MVKPrivateDataSlot(MVKDevice* device) : MVKVulkanAPIDeviceObject(device) {}

protected:
	void propagateDebugName() override {}

	std::unordered_map<uint64_t, uint64_t> _privateData;
};


#pragma mark -
#pragma mark MVKDeviceObjectPool

/** Manages a pool of instances of a particular object type that requires an MVKDevice during construction. */
template <class T>
class MVKDeviceObjectPool : public MVKObjectPool<T>, public MVKDeviceTrackingMixin {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _device; };

	/**
	 * Configures this instance for the device, and either use pooling, or not, depending
	 * on the value of isPooling, which defaults to true if not indicated explicitly.
	 */
	MVKDeviceObjectPool(MVKDevice* device, bool isPooling = true) : MVKObjectPool<T>(isPooling), MVKDeviceTrackingMixin(device) {}

protected:
	T* newObject() override { return new T(_device); }

};


#pragma mark -
#pragma mark Support functions

/**
 * Returns an autoreleased array containing the MTLDevices available on this system,
 * sorted according to power, with higher power GPU's at the front of the array.
 * This ensures that a lazy app that simply grabs the first GPU will get a high-power
 * one by default. If MVKConfiguration::forceLowPowerGPU is enabled, the returned
 * array will only include low-power devices. The instance may be a nullptr.
 */
NSArray<id<MTLDevice>>* mvkGetAvailableMTLDevicesArray(MVKInstance* instance);

/** Returns the registry ID of the specified device, or zero if the device does not have a registry ID. */
uint64_t mvkGetRegistryID(id<MTLDevice> mtlDevice);

/**
 * Returns a value identifying the physical location of the specified device.
 * The returned value is a hash of the location, locationNumber, peerGroupID,
 * and peerIndex properties of the device. On devices with only one built-in GPU,
 * the returned value will be zero.
 */
uint64_t mvkGetLocationID(id<MTLDevice> mtlDevice);
