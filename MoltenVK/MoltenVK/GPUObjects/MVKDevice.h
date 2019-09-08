/*
 * MVKDevice.h
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKLayers.h"
#include "MVKObjectPool.h"
#include "MVKVector.h"
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
class MVKSwapchainImage;
class MVKImageView;
class MVKSwapchain;
class MVKDeviceMemory;
class MVKFence;
class MVKSemaphore;
class MVKEvent;
class MVKQueryPool;
class MVKShaderModule;
class MVKPipelineCache;
class MVKPipelineLayout;
class MVKPipeline;
class MVKSampler;
class MVKDescriptorSetLayout;
class MVKDescriptorPool;
class MVKDescriptorUpdateTemplate;
class MVKFramebuffer;
class MVKRenderPass;
class MVKCommandPool;
class MVKCommandEncoder;
class MVKCommandResourceFactory;


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

	/** Returns whether the specified format is supported on this device. */
	bool getFormatIsSupported(VkFormat format);

	/** Populates the specified structure with the format properties of this device. */
	void getFormatProperties(VkFormat format, VkFormatProperties* pFormatProperties);

	/** Populates the specified structure with the format properties of this device. */
	void getFormatProperties(VkFormat format, VkFormatProperties2KHR* pFormatProperties);

    /** 
     * Populates the specified structure with the image format properties
     * supported for the specified image characteristics on this device.
     */
    VkResult getImageFormatProperties(VkFormat format,
                                      VkImageType type,
                                      VkImageTiling tiling,
                                      VkImageUsageFlags usage,
                                      VkImageCreateFlags flags,
                                      VkImageFormatProperties* pImageFormatProperties);

    /** 
     * Populates the specified structure with the image format properties
     * supported for the specified image characteristics on this device.
     */
    VkResult getImageFormatProperties(const VkPhysicalDeviceImageFormatInfo2KHR* pImageFormatInfo,
                                      VkImageFormatProperties2KHR* pImageFormatProperties);

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
    inline const VkPhysicalDeviceMemoryProperties* getPhysicalDeviceMemoryProperties() { return &_memoryProperties; }

	/** Populates the specified memory properties with the memory characteristics of this device. */
	VkResult getPhysicalDeviceMemoryProperties(VkPhysicalDeviceMemoryProperties* pMemoryProperties);

	/** Populates the specified memory properties with the memory characteristics of this device. */
	VkResult getPhysicalDeviceMemoryProperties(VkPhysicalDeviceMemoryProperties2* pMemoryProperties);

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

	
#pragma mark Metal

	/** Populates the specified structure with the Metal-specific features of this device. */
	inline const MVKPhysicalDeviceMetalFeatures* getMetalFeatures() { return &_metalFeatures; }

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

	void propogateDebugName() override {}
	MTLFeatureSet getMaximalMTLFeatureSet();
    void initMetalFeatures();
	void initFeatures();
	void initProperties();
	void initMemoryProperties();
	void initExtensions();
	MVKVector<MVKQueueFamily*>& getQueueFamilies();
	void initPipelineCacheUUID();
	MTLFeatureSet getHighestMTLFeatureSet();
	uint64_t getSpirvCrossRevision();
	bool getImageViewIsSupported(const VkPhysicalDeviceImageFormatInfo2KHR *pImageFormatInfo);
	void logGPUInfo();

	id<MTLDevice> _mtlDevice;
	MVKInstance* _mvkInstance;
	const MVKExtensionList _supportedExtensions;
	VkPhysicalDeviceFeatures _features;
	MVKPhysicalDeviceMetalFeatures _metalFeatures;
	VkPhysicalDeviceProperties _properties;
	VkPhysicalDeviceTexelBufferAlignmentPropertiesEXT _texelBuffAlignProperties;
	VkPhysicalDeviceMemoryProperties _memoryProperties;
	MVKVectorInline<MVKQueueFamily*, kMVKQueueFamilyCount> _queueFamilies;
	uint32_t _allMemoryTypes;
	uint32_t _hostVisibleMemoryTypes;
	uint32_t _hostCoherentMemoryTypes;
	uint32_t _privateMemoryTypes;
	uint32_t _lazilyAllocatedMemoryTypes;
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

	/** Returns the name of this device. */
	inline const char* getName() { return _pProperties->deviceName; }

    /** Returns the common resource factory for creating command resources. */
    inline MVKCommandResourceFactory* getCommandResourceFactory() { return _commandResourceFactory; }

	/** Returns the function pointer corresponding to the specified named entry point. */
	PFN_vkVoidFunction getProcAddr(const char* pName);

	/** Retrieves a queue at the specified index within the specified family. */
	MVKQueue* getQueue(uint32_t queueFamilyIndex = 0, uint32_t queueIndex = 0);

	/** Block the current thread until all queues in this device are idle. */
	VkResult waitIdle();

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

	MVKSwapchainImage* createSwapchainImage(const VkImageCreateInfo* pCreateInfo,
											MVKSwapchain* swapchain,
											uint32_t swapchainIndex,
											const VkAllocationCallbacks* pAllocator);
	void destroySwapchainImage(MVKSwapchainImage* mvkImg,
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


#pragma mark Operations

	/** Applies the specified global memory barrier to all resource issued by this device. */
	void applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
							VkPipelineStageFlags dstStageMask,
							VkMemoryBarrier* pMemoryBarrier,
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
    inline uint64_t getPerformanceTimestamp() {
		return _pMVKConfig->performanceTracking ? getPerformanceTimestampImpl() : 0;
	}

    /**
     * If performance is being tracked, adds the performance for an activity with a duration
     * interval between the start and end times, to the given performance statistics.
     *
     * If endTime is zero or not supplied, the current time is used.
     */
    inline void addActivityPerformance(MVKPerformanceTracker& activityTracker,
									   uint64_t startTime, uint64_t endTime = 0) {
		if (_pMVKConfig->performanceTracking) {
			addActivityPerformanceImpl(activityTracker, startTime, endTime);
		}
	};

    /** Populates the specified statistics structure from the current activity performance statistics. */
    void getPerformanceStatistics(MVKPerformanceStatistics* pPerf);

	/** Invalidates the memory regions. */
	VkResult invalidateMappedMemoryRanges(uint32_t memRangeCount, const VkMappedMemoryRange* pMemRanges);


#pragma mark Metal

	/** Returns the underlying Metal device. */
	inline id<MTLDevice> getMTLDevice() { return _physicalDevice->getMTLDevice(); }

	/** Returns standard compilation options to be used when compiling MSL shaders. */
	inline MTLCompileOptions* getMTLCompileOptions() { return _mtlCompileOptions; }

	/** Returns the Metal vertex buffer index to use for the specified vertex attribute binding number.  */
	uint32_t getMetalBufferIndexForVertexAttributeBinding(uint32_t binding);

	/**
	 * Returns the Metal MTLPixelFormat corresponding to the specified Vulkan VkFormat,
	 * or returns MTLPixelFormatInvalid if no corresponding MTLPixelFormat exists.
	 *
	 * This function uses the MoltenVK API function mvkMTLPixelFormatFromVkFormat(), but 
     * not all MTLPixelFormats returned by that API function are supported by all GPU's.
	 * This function may substitute and return a MTLPixelFormat value that is different than
	 * the value returned by the mvkMTLPixelFormatFromVkFormat() function, but is compatible
	 * with the GPU underlying this instance.
	 *
	 * Not all macOS GPU's support the MTLPixelFormatDepth24Unorm_Stencil8 pixel format, and
	 * in that case, this function will return MTLPixelFormatDepth32Float_Stencil8 instead.
	 *
	 * All other pixel formats are returned unchanged.
	 */
	MTLPixelFormat getMTLPixelFormatFromVkFormat(VkFormat vkFormat, MVKBaseObject* mvkObj);

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
	const VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT _enabledInterlockFeatures;
	const VkPhysicalDeviceHostQueryResetFeaturesEXT _enabledHostQryResetFeatures;
	const VkPhysicalDeviceScalarBlockLayoutFeaturesEXT _enabledScalarLayoutFeatures;
	const VkPhysicalDeviceTexelBufferAlignmentFeaturesEXT _enabledTexelBuffAlignFeatures;
	const VkPhysicalDeviceVertexAttributeDivisorFeaturesEXT _enabledVtxAttrDivFeatures;
	const VkPhysicalDevicePortabilitySubsetFeaturesEXTX _enabledPortabilityFeatures;

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

	// Indicates whether semaphores should use a MTLFence if available.
	// Set by the MVK_ALLOW_METAL_FENCES environment variable if MTLFences are available.
	// This should be a temporary fix after some repair to semaphore handling.
	bool _useMTLFenceForSemaphores;

	// Indicates whether semaphores should use a MTLEvent if available.
	// Set by the MVK_ALLOW_METAL_EVENTS environment variable if MTLEvents are available.
	// This should be a temporary fix after some repair to semaphore handling.
	bool _useMTLEventForSemaphores;


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
	void propogateDebugName() override  {}
	MVKResource* addResource(MVKResource* rez);
	MVKResource* removeResource(MVKResource* rez);
    void initPerformanceTracking();
	void initPhysicalDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo);
	void initQueues(const VkDeviceCreateInfo* pCreateInfo);
	void initMTLCompileOptions();
	void enableFeatures(const VkDeviceCreateInfo* pCreateInfo);
	void enableFeatures(const VkBool32* pEnable, const VkBool32* pRequested, const VkBool32* pAvailable, uint32_t count);
	void enableExtensions(const VkDeviceCreateInfo* pCreateInfo);
    const char* getActivityPerformanceDescription(MVKPerformanceTracker& activityTracker);
	uint64_t getPerformanceTimestampImpl();
	void addActivityPerformanceImpl(MVKPerformanceTracker& activityTracker,
									uint64_t startTime, uint64_t endTime);

	MVKPhysicalDevice* _physicalDevice;
    MVKCommandResourceFactory* _commandResourceFactory;
	MTLCompileOptions* _mtlCompileOptions;
	MVKVectorInline<MVKVectorInline<MVKQueue*, kMVKQueueCountPerQueueFamily>, kMVKQueueFamilyCount> _queuesByQueueFamilyIndex;
	MVKVectorInline<MVKResource*, 256> _resources;
	std::mutex _rezLock;
    std::mutex _perfLock;
    id<MTLBuffer> _globalVisibilityResultMTLBuffer;
    uint32_t _globalVisibilityQueryCount;
    std::mutex _vizLock;
};


#pragma mark -
#pragma mark MVKDeviceTrackingMixin

/**
 * This mixin class adds the ability for an object to track the device that created it.
 * Implementation supports an instance where the device is null.
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
	inline id<MTLDevice> getMTLDevice() { return _device ? _device->getMTLDevice() : nil; }

	/**
	 * Returns the Metal MTLPixelFormat corresponding to the specified Vulkan VkFormat,
	 * or returns MTLPixelFormatInvalid if no corresponding MTLPixelFormat exists.
	 *
	 * This function delegates to the MVKDevice::getMTLPixelFormatFromVkFormat() function.
	 * See the notes for that function for more information about how MTLPixelFormats
	 * are managed for each platform device.
	 */
	inline MTLPixelFormat getMTLPixelFormatFromVkFormat(VkFormat vkFormat) {
		return _device ? _device->getMTLPixelFormatFromVkFormat(vkFormat, getBaseObject())
					   : mvkMTLPixelFormatFromVkFormatInObj(vkFormat, getBaseObject());
	}

	/** Constructs an instance for the specified device. */
    MVKDeviceTrackingMixin(MVKDevice* device) : _device(device) {}

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

/** Returns an approximation of how much memory, in bytes, the device can use with good performance. */
uint64_t mvkRecommendedMaxWorkingSetSize(id<MTLDevice> mtlDevice);

/** Populate the propertes with info about the GPU represented by the MTLDevice. */
void mvkPopulateGPUInfo(VkPhysicalDeviceProperties& devProps, id<MTLDevice> mtlDevice);

/** Returns the registry ID of the specified device, or zero if the device does not have a registry ID. */
uint64_t mvkGetRegistryID(id<MTLDevice> mtlDevice);

/**
 * If the MTLDevice defines a texture memory alignment for the format, it is retrieved from
 * the MTLDevice and returned, or returns zero if the MTLDevice does not define an alignment.
 * The format must support linear texture memory (must not be depth, stencil, or compressed).
 */
VkDeviceSize mvkMTLPixelFormatLinearTextureAlignment(MTLPixelFormat mtlPixelFormat, id<MTLDevice> mtlDevice);
