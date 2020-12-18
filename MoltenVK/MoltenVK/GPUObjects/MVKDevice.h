/*
 * MVKDevice.h
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

#include "MVKFoundation.h"
#include "MVKVulkanAPIObject.h"
#include "MVKMTLResourceBindings.h"
#include "MVKLayers.h"
#include "MVKObjectPool.h"
#include "MVKSmallVector.h"
#include "MVKPixelFormats.h"
#include "MVKOSExtensions.h"
#include "mvk_datatypes.hpp"
#include "vk_mvk_moltenvk.h"
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
class MVKEvent;
class MVKSemaphoreImpl;
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
class MVKFramebuffer;
class MVKRenderPass;
class MVKCommandPool;
class MVKCommandEncoder;
class MVKCommandResourceFactory;
class MVKPrivateDataSlot;


/** The buffer index to use for vertex content. */
const static uint32_t kMVKVertexContentBufferIndex = 0;

// Parameters to define the sizing of inline collections
const static uint32_t kMVKQueueFamilyCount = 4;
const static uint32_t kMVKQueueCountPerQueueFamily = 1;		// Must be 1. See comments in MVKPhysicalDevice::getQueueFamilies()
const static uint32_t kMVKMinSwapchainImageCount = 2;
const static uint32_t kMVKMaxSwapchainImageCount = 3;
const static uint32_t kMVKCachedViewportScissorCount = 16;
const static uint32_t kMVKCachedColorAttachmentCount = 8;


#pragma mark -
#pragma mark MVKPhysicalDevice

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
	inline const char* getName() { return _properties.deviceName; }

	/** Populates the specified structure with the format properties of this device. */
	void getFormatProperties(VkFormat format, VkFormatProperties* pFormatProperties);

	/** Populates the specified structure with the format properties of this device. */
	void getFormatProperties(VkFormat format, VkFormatProperties2* pFormatProperties);

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

#pragma mark Surfaces

	/**
	 * Queries whether this device supports presentation to the specified surface,
	 * using a queue of the specified queue family.
	 */
	VkResult getSurfaceSupport(uint32_t queueFamilyIndex, MVKSurface* surface, VkBool32* pSupported);

	/** Returns the capabilities of the specified surface. */
	VkResult getSurfaceCapabilities(MVKSurface* surface, VkSurfaceCapabilitiesKHR* pSurfaceCapabilities);

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
    inline const VkPhysicalDeviceMemoryProperties* getMemoryProperties() { return &_memoryProperties; }

	/** Populates the specified memory properties with the memory characteristics of this device. */
	VkResult getMemoryProperties(VkPhysicalDeviceMemoryProperties* pMemoryProperties);

	/** Populates the specified memory properties with the memory characteristics of this device. */
	VkResult getMemoryProperties(VkPhysicalDeviceMemoryProperties2* pMemoryProperties);

	/**
	 * Returns a bit mask of all memory type indices. 
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	inline uint32_t getAllMemoryTypes() { return _allMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that allow host visibility to the memory. 
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	inline uint32_t getHostVisibleMemoryTypes() { return _hostVisibleMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that are coherent between host and device.
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	inline uint32_t getHostCoherentMemoryTypes() { return _hostCoherentMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that do NOT allow host visibility to the memory.
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	inline uint32_t getPrivateMemoryTypes() { return _privateMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that are lazily allocated.
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	inline uint32_t getLazilyAllocatedMemoryTypes() { return _lazilyAllocatedMemoryTypes; }

	/** Returns whether this is a unified memory device. */
	bool getHasUnifiedMemory();

	/** Returns the external memory properties supported for buffers for the handle type. */
	VkExternalMemoryProperties& getExternalBufferProperties(VkExternalMemoryHandleTypeFlagBits handleType);

	/** Returns the external memory properties supported for images for the handle type. */
	VkExternalMemoryProperties& getExternalImageProperties(VkExternalMemoryHandleTypeFlagBits handleType);

	
#pragma mark Metal

	/** Populates the specified structure with the Metal-specific features of this device. */
	inline const MVKPhysicalDeviceMetalFeatures* getMetalFeatures() { return &_metalFeatures; }

	/** Returns whether or not vertex instancing can be used to implement multiview. */
	inline bool canUseInstancingForMultiview() { return _metalFeatures.layeredRendering && _metalFeatures.deferredStoreActions; }

	/** Returns the underlying Metal device. */
	inline id<MTLDevice> getMTLDevice() { return _mtlDevice; }
    
    /*** Replaces the underlying Metal device .*/
    inline void replaceMTLDevice(id<MTLDevice> mtlDevice) {
		if (mtlDevice != _mtlDevice) {
			[_mtlDevice release];
			_mtlDevice = [mtlDevice retain];
		}
	}

#pragma mark Construction

	/** Constructs an instance wrapping the specified Vulkan instance and Metal device. */
	MVKPhysicalDevice(MVKInstance* mvkInstance, id<MTLDevice> mtlDevice);

	/** Default destructor. */
	~MVKPhysicalDevice() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKPhysicalDevice() method.
     */
    inline VkPhysicalDevice getVkPhysicalDevice() { return (VkPhysicalDevice)getVkHandle(); }

    /**
     * Retrieves the MVKPhysicalDevice instance referenced by the VkPhysicalDevice handle.
     * This is the compliment of the getVkPhysicalDevice() method.
     */
    static inline MVKPhysicalDevice* getMVKPhysicalDevice(VkPhysicalDevice vkPhysicalDevice) {
        return (MVKPhysicalDevice*)getDispatchableObject(vkPhysicalDevice);
    }

protected:
	friend class MVKDevice;

	void propagateDebugName() override {}
	MTLFeatureSet getMaximalMTLFeatureSet();
    void initMetalFeatures();
	void initFeatures();
	void initProperties();
	void initLimits();
	void initGPUInfoProperties();
	void initMemoryProperties();
	void setMemoryHeap(uint32_t heapIndex, VkDeviceSize heapSize, VkMemoryHeapFlags heapFlags);
	void setMemoryType(uint32_t typeIndex, uint32_t heapIndex, VkMemoryPropertyFlags propertyFlags);
	uint64_t getVRAMSize();
	uint64_t getRecommendedMaxWorkingSetSize();
	uint64_t getCurrentAllocatedSize();
	void initExternalMemoryProperties();
	void initExtensions();
	MVKArrayRef<MVKQueueFamily*> getQueueFamilies();
	void initPipelineCacheUUID();
	uint32_t getHighestMTLFeatureSet();
	uint64_t getMoltenVKGitRevision();
	void populate(VkPhysicalDeviceIDProperties* pDevIdProps);
	void logGPUInfo();

	id<MTLDevice> _mtlDevice;
	MVKInstance* _mvkInstance;
	const MVKExtensionList _supportedExtensions;
	VkPhysicalDeviceFeatures _features;
	MVKPhysicalDeviceMetalFeatures _metalFeatures;
	VkPhysicalDeviceProperties _properties;
	VkPhysicalDeviceTexelBufferAlignmentPropertiesEXT _texelBuffAlignProperties;
	VkPhysicalDeviceMemoryProperties _memoryProperties;
	MVKSmallVector<MVKQueueFamily*, kMVKQueueFamilyCount> _queueFamilies;
	MVKPixelFormats _pixelFormats;
	uint32_t _allMemoryTypes;
	uint32_t _hostVisibleMemoryTypes;
	uint32_t _hostCoherentMemoryTypes;
	uint32_t _privateMemoryTypes;
	uint32_t _lazilyAllocatedMemoryTypes;
	VkExternalMemoryProperties _mtlBufferExternalMemoryProperties;
	VkExternalMemoryProperties _mtlTextureExternalMemoryProperties;
};


#pragma mark -
#pragma mark MVKDevice

typedef struct {
	id<MTLBlitCommandEncoder> mtlBlitEncoder = nil;
	id<MTLCommandBuffer> mtlCmdBuffer = nil;
} MVKMTLBlitEncoder;

/** Represents a Vulkan logical GPU device, associated with a physical device. */
class MVKDevice : public MVKDispatchableVulkanAPIObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_DEVICE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_DEVICE_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _physicalDevice->getInstance(); }

	/** Returns the physical device underlying this logical device. */
	inline MVKPhysicalDevice* getPhysicalDevice() { return _physicalDevice; }

	/** Returns info about the pixel format supported by the physical device. */
	inline MVKPixelFormats* getPixelFormats() { return &_physicalDevice->_pixelFormats; }

	/** Returns the name of this device. */
	inline const char* getName() { return _pProperties->deviceName; }

    /** Returns the common resource factory for creating command resources. */
    inline MVKCommandResourceFactory* getCommandResourceFactory() { return _commandResourceFactory; }

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
	
	/** Mark this device as lost. Releases all waits for this device. */
	VkResult markLost();

	/** Returns whether or not the given descriptor set layout is supported. */
	void getDescriptorSetLayoutSupport(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
									   VkDescriptorSetLayoutSupport* pSupport);

	/** Populates the device group presentation capabilities. */
	VkResult getDeviceGroupPresentCapabilities(VkDeviceGroupPresentCapabilitiesKHR* pDeviceGroupPresentCapabilities);

	/** Populates the device group surface presentation modes. */
	VkResult getDeviceGroupSurfacePresentModes(MVKSurface* surface, VkDeviceGroupPresentModeFlagsKHR* pModes);

	/** Populates the device group peer memory features. */
	void getPeerMemoryFeatures(uint32_t heapIndex, uint32_t localDevice, uint32_t remoteDevice, VkPeerMemoryFeatureFlags* pPeerMemoryFeatures);


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

	MVKDescriptorUpdateTemplate* createDescriptorUpdateTemplate(const VkDescriptorUpdateTemplateCreateInfoKHR* pCreateInfo,
																const VkAllocationCallbacks* pAllocator);
	void destroyDescriptorUpdateTemplate(MVKDescriptorUpdateTemplate* mvkDUT,
										 const VkAllocationCallbacks* pAllocator);

	MVKFramebuffer* createFramebuffer(const VkFramebufferCreateInfo* pCreateInfo,
									  const VkAllocationCallbacks* pAllocator);
	void destroyFramebuffer(MVKFramebuffer* mvkFB,
							const VkAllocationCallbacks* pAllocator);

	MVKRenderPass* createRenderPass(const VkRenderPassCreateInfo* pCreateInfo,
									const VkAllocationCallbacks* pAllocator);
	MVKRenderPass* createRenderPass(const VkRenderPassCreateInfo2* pCreateInfo,
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
								   VkPrivateDataSlotEXT* pPrivateDataSlot);

	void destroyPrivateDataSlot(VkPrivateDataSlotEXT privateDataSlot,
								const VkAllocationCallbacks* pAllocator);


#pragma mark Operations

	/** Applies the specified global memory barrier to all resource issued by this device. */
	void applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
							VkPipelineStageFlags dstStageMask,
							MVKPipelineBarrier& barrier,
							MVKCommandEncoder* cmdEncoder,
							MVKCommandUse cmdUse);

    /**
	 * If performance is being tracked, returns a monotonic timestamp value for use performance timestamping.
	 *
	 * The returned value corresponds to the number of CPU "ticks" since the app was initialized.
	 *
	 * Calling this value twice, subtracting the first value from the second, and then multiplying
	 * the result by the value returned by mvkGetTimestampPeriod() will provide an indication of the
	 * number of nanoseconds between the two calls. The convenience function mvkGetElapsedMilliseconds()
	 * can be used to perform this calculation.
     */
    inline uint64_t getPerformanceTimestamp() { return _pMVKConfig->performanceTracking ? mvkGetTimestamp() : 0; }

    /**
     * If performance is being tracked, adds the performance for an activity with a duration
     * interval between the start and end times, to the given performance statistics.
     *
     * If endTime is zero or not supplied, the current time is used.
     */
    inline void addActivityPerformance(MVKPerformanceTracker& activityTracker,
									   uint64_t startTime, uint64_t endTime = 0) {
		if (_pMVKConfig->performanceTracking) {
			updateActivityPerformance(activityTracker, startTime, endTime);

			// Log call not locked. Very minor chance that the tracker data will be updated during log call,
			// resulting in an inconsistent report. Not worth taking lock perf hit for rare inline reporting.
			if (_logActivityPerformanceInline) { logActivityPerformance(activityTracker, _performanceStatistics, true); }
		}
	};

    /** Populates the specified statistics structure from the current activity performance statistics. */
    void getPerformanceStatistics(MVKPerformanceStatistics* pPerf);

	/** Invalidates the memory regions. */
	VkResult invalidateMappedMemoryRanges(uint32_t memRangeCount, const VkMappedMemoryRange* pMemRanges);

	/** Log all performance statistics. */
	void logPerformanceSummary();


#pragma mark Metal

	/** Returns the underlying Metal device. */
	inline id<MTLDevice> getMTLDevice() { return _physicalDevice->getMTLDevice(); }

	/** Returns standard compilation options to be used when compiling MSL shaders. */
	inline MTLCompileOptions* getMTLCompileOptions() { return _mtlCompileOptions; }

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

    /** Returns the memory type index corresponding to the specified Metal memory storage mode. */
    uint32_t getVulkanMemoryTypeIndex(MTLStorageMode mtlStorageMode);

	/** Returns a default MTLSamplerState to populate empty array element descriptors. */
	id<MTLSamplerState> getDefaultMTLSamplerState();

	/**
	 * Returns whether MTLCommandBuffers can be prefilled.
	 *
	 * This depends both on whether the app config has requested prefilling, and whether doing so will
	 * interfere with other requested features, such as updating resource descriptors after bindings.
	 */
	bool shouldPrefillMTLCommandBuffers();


#pragma mark Properties directly accessible

	/** Pointer to the MoltenVK configuration settings. */
	const MVKConfiguration* _pMVKConfig;

	/** Device features available and enabled. */
	const VkPhysicalDeviceFeatures _enabledFeatures;
	const VkPhysicalDevice16BitStorageFeatures _enabledStorage16Features;
	const VkPhysicalDevice8BitStorageFeaturesKHR _enabledStorage8Features;
	const VkPhysicalDeviceFloat16Int8FeaturesKHR _enabledF16I8Features;
	const VkPhysicalDeviceUniformBufferStandardLayoutFeaturesKHR _enabledUBOLayoutFeatures;
	const VkPhysicalDeviceVariablePointerFeatures _enabledVarPtrFeatures;
	const VkPhysicalDeviceDescriptorIndexingFeaturesEXT _enabledDescriptorIndexingFeatures;
	const VkPhysicalDeviceInlineUniformBlockFeaturesEXT _enabledInlineUniformBlockFeatures;
	const VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT _enabledInterlockFeatures;
	const VkPhysicalDeviceHostQueryResetFeaturesEXT _enabledHostQryResetFeatures;
	const VkPhysicalDeviceSamplerYcbcrConversionFeatures _enabledSamplerYcbcrConversionFeatures;
	const VkPhysicalDevicePrivateDataFeaturesEXT _enabledPrivateDataFeatures;
	const VkPhysicalDeviceScalarBlockLayoutFeaturesEXT _enabledScalarLayoutFeatures;
	const VkPhysicalDeviceTexelBufferAlignmentFeaturesEXT _enabledTexelBuffAlignFeatures;
	const VkPhysicalDeviceVertexAttributeDivisorFeaturesEXT _enabledVtxAttrDivFeatures;
	const VkPhysicalDevicePortabilitySubsetFeaturesKHR _enabledPortabilityFeatures;

	/** The list of Vulkan extensions, indicating whether each has been enabled by the app for this device. */
	const MVKExtensionList _enabledExtensions;

	/** Pointer to the Metal-specific features of the underlying physical device. */
	const MVKPhysicalDeviceMetalFeatures* _pMetalFeatures;

	/** Pointer to the properties of the underlying physical device. */
	const VkPhysicalDeviceProperties* _pProperties;

	/** Pointer to the memory properties of the underlying physical device. */
	const VkPhysicalDeviceMemoryProperties* _pMemoryProperties;

    /** Performance statistics. */
    MVKPerformanceStatistics _performanceStatistics;


#pragma mark Construction

	/** Constructs an instance on the specified physical device. */
	MVKDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo);

	~MVKDevice() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKDevice() method.
     */
    inline VkDevice getVkDevice() { return (VkDevice)getVkHandle(); }

    /**
     * Retrieves the MVKDevice instance referenced by the VkDevice handle.
     * This is the compliment of the getVkDevice() method.
     */
    static inline MVKDevice* getMVKDevice(VkDevice vkDevice) {
        return (MVKDevice*)getDispatchableObject(vkDevice);
    }

protected:
	friend class MVKSemaphoreEmulated;
	friend class MVKTimelineSemaphoreMTLEvent;
	friend class MVKTimelineSemaphoreEmulated;
	friend class MVKFence;
	friend class MVKEventEmulated;

	void propagateDebugName() override  {}
	MVKResource* addResource(MVKResource* rez);
	MVKResource* removeResource(MVKResource* rez);
	void addSemaphore(MVKSemaphoreImpl* sem4);
	void removeSemaphore(MVKSemaphoreImpl* sem4);
	void addTimelineSemaphore(MVKTimelineSemaphore* sem4, uint64_t value);
	void removeTimelineSemaphore(MVKTimelineSemaphore* sem4, uint64_t value);
    void initPerformanceTracking();
	void initPhysicalDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo);
	void initQueues(const VkDeviceCreateInfo* pCreateInfo);
	void reservePrivateData(const VkDeviceCreateInfo* pCreateInfo);
	void initMTLCompileOptions();
	void enableFeatures(const VkDeviceCreateInfo* pCreateInfo);
	void enableFeatures(const VkBool32* pEnable, const VkBool32* pRequested, const VkBool32* pAvailable, uint32_t count);
	void enableExtensions(const VkDeviceCreateInfo* pCreateInfo);
    const char* getActivityPerformanceDescription(MVKPerformanceTracker& activity, MVKPerformanceStatistics& perfStats);
	void logActivityPerformance(MVKPerformanceTracker& activity, MVKPerformanceStatistics& perfStats, bool isInline = false);
	void updateActivityPerformance(MVKPerformanceTracker& activity, uint64_t startTime, uint64_t endTime);
	void getDescriptorVariableDescriptorCountLayoutSupport(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
														   VkDescriptorSetLayoutSupport* pSupport,
														   VkDescriptorSetVariableDescriptorCountLayoutSupportEXT* pVarDescSetCountSupport);

	MVKPhysicalDevice* _physicalDevice;
    MVKCommandResourceFactory* _commandResourceFactory;
	MTLCompileOptions* _mtlCompileOptions;
	MVKSmallVector<MVKSmallVector<MVKQueue*, kMVKQueueCountPerQueueFamily>, kMVKQueueFamilyCount> _queuesByQueueFamilyIndex;
	MVKSmallVector<MVKResource*, 256> _resources;
	MVKSmallVector<MVKPrivateDataSlot*> _privateDataSlots;
	MVKSmallVector<bool> _privateDataSlotsAvailability;
	MVKSmallVector<MVKSemaphoreImpl*> _awaitingSemaphores;
	MVKSmallVector<std::pair<MVKTimelineSemaphore*, uint64_t>> _awaitingTimelineSem4s;
	std::mutex _rezLock;
	std::mutex _sem4Lock;
    std::mutex _perfLock;
    id<MTLBuffer> _globalVisibilityResultMTLBuffer;
	id<MTLSamplerState> _defaultMTLSamplerState;
    uint32_t _globalVisibilityQueryCount;
    std::mutex _vizLock;
	bool _useMTLFenceForSemaphores;
	bool _useMTLEventForSemaphores;
	bool _useCommandPooling;
	bool _logActivityPerformanceInline;
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
	inline MVKDevice* getDevice() { return _device; }

	/** Returns the underlying Metal device. */
	inline id<MTLDevice> getMTLDevice() { return _device->getMTLDevice(); }

	/** Returns info about the pixel format supported by the physical device. */
	inline MVKPixelFormats* getPixelFormats() { return _device->getPixelFormats(); }

	/** Returns whether the device supports using Metal argument buffers. */
	inline bool supportsMetalArgumentBuffers() const  { return _device->_pMetalFeatures->argumentBuffers; };

	/** Constructs an instance for the specified device. */
    MVKDeviceTrackingMixin(MVKDevice* device) : _device(device) { assert(_device); }

	virtual ~MVKDeviceTrackingMixin() {}

protected:
	virtual MVKBaseObject* getBaseObject() = 0;

	MVKDevice* _device;
};


#pragma mark -
#pragma mark MVKBaseDeviceObject

/** Represents an object that is spawned from a Vulkan device, and tracks that device. */
class MVKBaseDeviceObject : public MVKBaseObject, public MVKDeviceTrackingMixin {

public:

	/** Constructs an instance for the specified device. */
	MVKBaseDeviceObject(MVKDevice* device) : MVKDeviceTrackingMixin(device) {}

protected:
	MVKBaseObject* getBaseObject() override { return this; };
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

protected:
	MVKBaseObject* getBaseObject() override { return this; };
};


#pragma mark -
#pragma mark MVKPrivateDataSlot

/** Private data slot. */
class MVKPrivateDataSlot : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_PRIVATE_DATA_SLOT_EXT; }

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
class MVKDeviceObjectPool : public MVKObjectPool<T> {

public:


	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _device; };

	/** Returns a new instance. */
	T* newObject() override { return new T(_device); }

	/**
	 * Configures this instance for the device, and either use pooling, or not, depending
	 * on the value of isPooling, which defaults to true if not indicated explicitly.
	 */
	MVKDeviceObjectPool(MVKDevice* device, bool isPooling = true) : MVKObjectPool<T>(isPooling), _device(device) {}

protected:
	MVKDevice* _device;
};


#pragma mark -
#pragma mark Support functions

/** Returns the registry ID of the specified device, or zero if the device does not have a registry ID. */
uint64_t mvkGetRegistryID(id<MTLDevice> mtlDevice);

/** Redefinitions because Mac Catalyst doesn't support feature sets. */
#if MVK_MACCAT
#define MTLFeatureSet_macOS_GPUFamily1_v1		MTLGPUFamilyMacCatalyst1
#define MTLFeatureSet_macOS_GPUFamily1_v2		MTLGPUFamilyMacCatalyst1
#define MTLFeatureSet_macOS_GPUFamily1_v3		MTLGPUFamilyMacCatalyst1
#define MTLFeatureSet_macOS_GPUFamily1_v4		MTLGPUFamilyMacCatalyst1

#define MTLFeatureSet_macOS_GPUFamily2_v1		MTLGPUFamilyMacCatalyst2
#endif
